"""
Unit tests for the R2 upload service (foods/services/r2_upload.py).

The actual boto3 S3 call is mocked — no real Cloudflare connection is made.

Run with:
    python manage.py test foods.tests.test_r2_upload --settings=backend.test_settings --verbosity=2
"""
import gzip
import hashlib
import json
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch, call

from django.test import TestCase, override_settings

from foods.models import DbVersion, SyncArtifact
from foods.services.r2_upload import (
    ParseError,
    compute_metadata,
    parse_export_path,
    upload_artifact,
)

# ---------------------------------------------------------------------------
# Settings override — fake R2 credentials so the client can be constructed
# ---------------------------------------------------------------------------
R2_SETTINGS = dict(
    R2_ACCOUNT_ID="test_account",
    R2_ACCESS_KEY="test_key",
    R2_SECRET_KEY="test_secret",
    R2_BUCKET_NAME="test-bucket",
    R2_PUBLIC_URL="https://cdn.example.com",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_published(version_pk=None) -> DbVersion:
    v = DbVersion.objects.create(is_published=True)
    return v


def _write_snapshot(directory: Path, version: int) -> Path:
    """Write a minimal gzip file that looks like a real snapshot export."""
    path = directory / "snapshots" / f"snapshot_{version}.db.gz"
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wb") as f:
        f.write(b"fake sqlite content")
    return path


def _write_delta(directory: Path, from_v: int, to_v: int) -> Path:
    """Write a minimal JSON delta file."""
    path = directory / "deltas" / f"delta_{from_v}_{to_v}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({"from_version": from_v, "to_version": to_v, "changes": []}),
        encoding="utf-8",
    )
    return path


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


# ---------------------------------------------------------------------------
# parse_export_path
# ---------------------------------------------------------------------------

class ParseExportPathTests(TestCase):

    def test_snapshot_parsed_correctly(self):
        info = parse_export_path(Path("exports/snapshots/snapshot_3.db.gz"))
        self.assertEqual(info["type"], "snapshot")
        self.assertEqual(info["version"], 3)
        self.assertEqual(info["r2_key"], "snapshots/version_3_snapshot.db.gz")

    def test_delta_parsed_correctly(self):
        info = parse_export_path(Path("exports/deltas/delta_1_3.json"))
        self.assertEqual(info["type"], "delta")
        self.assertEqual(info["from_version"], 1)
        self.assertEqual(info["version"], 3)
        self.assertEqual(info["r2_key"], "deltas/delta_1_to_3.json")

    def test_unknown_filename_raises_parse_error(self):
        with self.assertRaises(ParseError):
            parse_export_path(Path("exports/unknown_file.txt"))

    def test_snapshot_r2_key_format(self):
        """R2 key uses 'version_N_snapshot' convention (matches the API URL helper)."""
        info = parse_export_path(Path("snapshot_42.db.gz"))
        self.assertIn("version_42_snapshot", info["r2_key"])

    def test_delta_r2_key_uses_to_separator(self):
        """R2 key uses 'delta_N_to_M' convention (matches the API URL helper)."""
        info = parse_export_path(Path("delta_2_5.json"))
        self.assertIn("delta_2_to_5", info["r2_key"])


# ---------------------------------------------------------------------------
# compute_metadata
# ---------------------------------------------------------------------------

class ComputeMetadataTests(TestCase):

    def test_size_and_checksum(self):
        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as f:
            f.write(b"hello world")
            tmp = Path(f.name)
        try:
            size, checksum = compute_metadata(tmp)
            self.assertEqual(size, 11)
            self.assertEqual(
                checksum,
                hashlib.sha256(b"hello world").hexdigest(),
            )
        finally:
            tmp.unlink()

    def test_empty_file(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            tmp = Path(f.name)
        try:
            size, checksum = compute_metadata(tmp)
            self.assertEqual(size, 0)
            self.assertEqual(checksum, hashlib.sha256(b"").hexdigest())
        finally:
            tmp.unlink()


# ---------------------------------------------------------------------------
# upload_artifact — dry run (no boto3, no DB writes)
# ---------------------------------------------------------------------------

class UploadArtifactDryRunTests(TestCase):

    def test_dry_run_snapshot_returns_correct_info(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            v = _make_published()
            path = _write_snapshot(d, v.version)

            result = upload_artifact(path, dry_run=True)

        self.assertTrue(result["dry_run"])
        self.assertEqual(result["artifact_type"], "snapshot")
        self.assertEqual(result["version"], v.version)
        self.assertIn("checksum", result)
        self.assertGreater(result["file_size_bytes"], 0)

    def test_dry_run_delta_returns_correct_info(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            v1 = _make_published()
            v2 = _make_published()
            path = _write_delta(d, v1.version, v2.version)

            result = upload_artifact(path, dry_run=True)

        self.assertEqual(result["artifact_type"], "delta")
        self.assertEqual(result["from_version"], v1.version)
        self.assertEqual(result["version"], v2.version)

    def test_dry_run_does_not_write_db(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = _make_published()
            path = _write_snapshot(Path(tmp), v.version)
            upload_artifact(path, dry_run=True)

        self.assertEqual(SyncArtifact.objects.count(), 0)

    def test_file_not_found_raises(self):
        with self.assertRaises(FileNotFoundError):
            upload_artifact(Path("/nonexistent/snapshot_1.db.gz"), dry_run=True)

    def test_unrecognised_filename_raises_parse_error(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            tmp = Path(f.name)
        try:
            with self.assertRaises(ParseError):
                upload_artifact(tmp, dry_run=True)
        finally:
            tmp.unlink()


# ---------------------------------------------------------------------------
# upload_artifact — real upload (boto3 mocked)
# ---------------------------------------------------------------------------

@override_settings(**R2_SETTINGS)
class UploadArtifactUploadTests(TestCase):

    def _run_upload(self, path: Path):
        """Run upload_artifact with boto3.client mocked out."""
        mock_client = MagicMock()
        with patch("foods.services.r2_upload.boto3.client", return_value=mock_client):
            result = upload_artifact(path, dry_run=False)
        return result, mock_client

    # --- Snapshot ---

    def test_snapshot_calls_upload_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = _make_published()
            path = _write_snapshot(Path(tmp), v.version)
            result, mock_client = self._run_upload(path)

        mock_client.upload_file.assert_called_once()
        call_kwargs = mock_client.upload_file.call_args
        self.assertEqual(call_kwargs.kwargs["Key"], f"snapshots/version_{v.version}_snapshot.db.gz")
        self.assertEqual(call_kwargs.kwargs["Bucket"], "test-bucket")

    def test_snapshot_creates_sync_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = _make_published()
            path = _write_snapshot(Path(tmp), v.version)
            with patch("foods.services.r2_upload.boto3.client", return_value=MagicMock()):
                upload_artifact(path, dry_run=False)

        artifact = SyncArtifact.objects.get(version=v, artifact_type=SyncArtifact.SNAPSHOT)
        self.assertIsNotNone(artifact.checksum)
        self.assertGreater(artifact.file_size_bytes, 0)
        self.assertIsNone(artifact.from_version)

    def test_snapshot_checksum_matches_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            v = _make_published()
            path = _write_snapshot(Path(tmp), v.version)
            expected_checksum = _sha256(path)
            with patch("foods.services.r2_upload.boto3.client", return_value=MagicMock()):
                upload_artifact(path, dry_run=False)

        artifact = SyncArtifact.objects.get(version=v, artifact_type=SyncArtifact.SNAPSHOT)
        self.assertEqual(artifact.checksum, expected_checksum)

    # --- Delta ---

    def test_delta_calls_upload_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            v1 = _make_published()
            v2 = _make_published()
            path = _write_delta(Path(tmp), v1.version, v2.version)
            result, mock_client = self._run_upload(path)

        mock_client.upload_file.assert_called_once()
        key = mock_client.upload_file.call_args.kwargs["Key"]
        self.assertEqual(key, f"deltas/delta_{v1.version}_to_{v2.version}.json")

    def test_delta_creates_sync_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            v1 = _make_published()
            v2 = _make_published()
            path = _write_delta(Path(tmp), v1.version, v2.version)
            with patch("foods.services.r2_upload.boto3.client", return_value=MagicMock()):
                upload_artifact(path, dry_run=False)

        artifact = SyncArtifact.objects.get(version=v2, artifact_type=SyncArtifact.DELTA)
        self.assertEqual(artifact.from_version, v1.version)
        self.assertIsNotNone(artifact.checksum)

    def test_upload_idempotent_updates_existing_artifact(self):
        """Uploading the same file twice must update (not duplicate) the row."""
        with tempfile.TemporaryDirectory() as tmp:
            v = _make_published()
            path = _write_snapshot(Path(tmp), v.version)
            with patch("foods.services.r2_upload.boto3.client", return_value=MagicMock()):
                upload_artifact(path, dry_run=False)
                upload_artifact(path, dry_run=False)  # second upload

        self.assertEqual(
            SyncArtifact.objects.filter(version=v, artifact_type=SyncArtifact.SNAPSHOT).count(),
            1,
        )

    def test_unpublished_version_raises_value_error(self):
        """Cannot upload an artifact for an unpublished (draft) version."""
        draft = DbVersion.objects.create(is_published=False)
        with tempfile.TemporaryDirectory() as tmp:
            path = _write_snapshot(Path(tmp), draft.version)
            with self.assertRaises(ValueError):
                with patch("foods.services.r2_upload.boto3.client", return_value=MagicMock()):
                    upload_artifact(path, dry_run=False)

    def test_missing_r2_credentials_raises_runtime_error(self):
        with override_settings(R2_ACCOUNT_ID=""):
            with tempfile.TemporaryDirectory() as tmp:
                v = _make_published()
                path = _write_snapshot(Path(tmp), v.version)
                with self.assertRaises(RuntimeError):
                    upload_artifact(path, dry_run=False)
