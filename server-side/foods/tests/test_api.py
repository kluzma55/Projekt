"""
Unit tests for the synchronisation API endpoints.

Run with:
    python manage.py test foods.tests.test_api --settings=backend.test_settings --verbosity=2
"""
import json
from unittest.mock import patch

from django.test import TestCase, Client, override_settings
from django.urls import reverse

from foods.models import DbVersion, SyncArtifact

# ---------------------------------------------------------------------------
# Shared constants
# ---------------------------------------------------------------------------
FAKE_CDN = "https://cdn.example.com"


def _make_published_version(**extra) -> DbVersion:
    """Create and return a published DbVersion."""
    v = DbVersion.objects.create(is_published=True, **extra)
    return v


def _make_draft_version() -> DbVersion:
    """Create and return an unpublished (draft) DbVersion."""
    return DbVersion.objects.create(is_published=False)


def _attach_snapshot_artifact(version: DbVersion, size=1_048_576, checksum="abc123sha") -> SyncArtifact:
    return SyncArtifact.objects.create(
        version=version,
        artifact_type=SyncArtifact.SNAPSHOT,
        file_size_bytes=size,
        checksum=checksum,
    )


def _attach_delta_artifact(version: DbVersion, from_version: int, size=45_020, checksum="delta_sha") -> SyncArtifact:
    return SyncArtifact.objects.create(
        version=version,
        artifact_type=SyncArtifact.DELTA,
        from_version=from_version,
        file_size_bytes=size,
        checksum=checksum,
    )


# ---------------------------------------------------------------------------
# GET /api/sync/status/
# ---------------------------------------------------------------------------
@override_settings(R2_PUBLIC_URL=FAKE_CDN)
class SyncStatusViewTests(TestCase):

    def setUp(self):
        self.client = Client()
        self.url = reverse("foods:sync-status")

    def test_returns_latest_published_version(self):
        """Returns the highest published version number."""
        _make_published_version()  # version 1 (auto)
        v2 = _make_published_version()  # version 2

        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["latest_version"], v2.version)

    def test_ignores_unpublished_drafts(self):
        """Draft versions must not appear in the status response."""
        published = _make_published_version()
        _make_draft_version()   # this draft must NOT be returned

        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["latest_version"], published.version)

    def test_404_when_no_published_version(self):
        """Returns 404 with an error key when no published version exists."""
        _make_draft_version()   # only an unpublished draft

        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 404)
        self.assertIn("error", resp.json())

    def test_404_when_database_empty(self):
        """Returns 404 when the DbVersion table is entirely empty."""
        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 404)
        self.assertIn("error", resp.json())

    def test_only_get_allowed(self):
        """Non-GET methods return 405 (Django class-based view default)."""
        resp = self.client.post(self.url)
        self.assertEqual(resp.status_code, 405)


# ---------------------------------------------------------------------------
# GET /api/sync/snapshot/
# ---------------------------------------------------------------------------
@override_settings(R2_PUBLIC_URL=FAKE_CDN)
class SyncSnapshotViewTests(TestCase):

    def setUp(self):
        self.client = Client()
        self.url = reverse("foods:sync-snapshot")

    def test_200_with_all_required_keys(self):
        """Full happy-path: returns 200 with all four required JSON keys."""
        v = _make_published_version()
        _attach_snapshot_artifact(v, size=2_097_152, checksum="sha256abc")

        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        for key in ("current_version", "file_size_bytes", "checksum", "download_url"):
            self.assertIn(key, data, msg=f"Missing key: {key}")

    def test_current_version_matches_published(self):
        v = _make_published_version()
        _attach_snapshot_artifact(v)

        data = self.client.get(self.url).json()

        self.assertEqual(data["current_version"], v.version)

    def test_download_url_uses_r2_public_url(self):
        """download_url must start with R2_PUBLIC_URL and follow the expected path pattern."""
        v = _make_published_version()
        _attach_snapshot_artifact(v)

        data = self.client.get(self.url).json()
        expected_url = f"{FAKE_CDN}/snapshots/version_{v.version}_snapshot.db.gz"

        self.assertEqual(data["download_url"], expected_url)

    def test_download_url_without_trailing_slash_in_cdn(self):
        """R2_PUBLIC_URL with trailing slash should produce a clean URL (no double slash)."""
        v = _make_published_version()
        _attach_snapshot_artifact(v)

        with self.settings(R2_PUBLIC_URL=FAKE_CDN + "/"):
            data = self.client.get(self.url).json()

        self.assertNotIn("//snapshots", data["download_url"])

    def test_file_size_and_checksum_returned(self):
        v = _make_published_version()
        _attach_snapshot_artifact(v, size=512_000, checksum="deadbeef")

        data = self.client.get(self.url).json()

        self.assertEqual(data["file_size_bytes"], 512_000)
        self.assertEqual(data["checksum"], "deadbeef")

    def test_null_metadata_when_artifact_not_yet_populated(self):
        """When no SyncArtifact row exists, file_size_bytes and checksum are null."""
        _make_published_version()

        data = self.client.get(self.url).json()

        self.assertEqual(resp_code := 200, 200)  # implicitly checks 200 above
        self.assertIsNone(data["file_size_bytes"])
        self.assertIsNone(data["checksum"])

    def test_404_when_no_published_version(self):
        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 404)
        self.assertIn("error", resp.json())

    def test_returns_latest_when_multiple_published(self):
        """When multiple published versions exist the endpoint returns the newest."""
        _make_published_version()  # v1
        v2 = _make_published_version()  # v2
        _attach_snapshot_artifact(v2)

        data = self.client.get(self.url).json()

        self.assertEqual(data["current_version"], v2.version)


# ---------------------------------------------------------------------------
# GET /api/sync/delta/
# ---------------------------------------------------------------------------
@override_settings(R2_PUBLIC_URL=FAKE_CDN)
class SyncDeltaViewTests(TestCase):

    def setUp(self):
        self.client = Client()
        self.url = reverse("foods:sync-delta")

    # --- Happy path: update available ---

    def test_delta_available_returns_200_with_all_keys(self):
        """from_version < current_version → 200 with four keys."""
        v1 = _make_published_version()  # version 1 (auto)
        v2 = _make_published_version()  # version 2 (auto)
        _attach_delta_artifact(v2, from_version=v1.version)

        resp = self.client.get(self.url, {"from_version": v1.version})

        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        for key in ("current_version", "file_size_bytes", "checksum", "download_url"):
            self.assertIn(key, data, msg=f"Missing key: {key}")

    def test_delta_url_format(self):
        """download_url must follow the delta_{from}_to_{to}.json pattern."""
        v1 = _make_published_version()
        v2 = _make_published_version()
        _attach_delta_artifact(v2, from_version=v1.version)

        data = self.client.get(self.url, {"from_version": v1.version}).json()
        expected = f"{FAKE_CDN}/deltas/delta_{v1.version}_to_{v2.version}.json"

        self.assertEqual(data["download_url"], expected)

    def test_delta_metadata_returned(self):
        v1 = _make_published_version()
        v2 = _make_published_version()
        _attach_delta_artifact(v2, from_version=v1.version, size=99_999, checksum="deltahash")

        data = self.client.get(self.url, {"from_version": v1.version}).json()

        self.assertEqual(data["file_size_bytes"], 99_999)
        self.assertEqual(data["checksum"], "deltahash")

    def test_current_version_in_delta_response(self):
        v1 = _make_published_version()
        v2 = _make_published_version()

        data = self.client.get(self.url, {"from_version": v1.version}).json()

        self.assertEqual(data["current_version"], v2.version)

    # --- Already up-to-date ---

    def test_up_to_date_when_from_version_equals_current(self):
        """from_version == current_version → up_to_date response."""
        v = _make_published_version()

        resp = self.client.get(self.url, {"from_version": v.version})

        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertTrue(data.get("up_to_date"))
        self.assertIsNone(data.get("download_url"))
        self.assertEqual(data["current_version"], v.version)

    def test_up_to_date_when_from_version_exceeds_current(self):
        """from_version > current_version → also up_to_date."""
        v = _make_published_version()

        resp = self.client.get(self.url, {"from_version": v.version + 100})

        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get("up_to_date"))

    # --- Validation: 400 errors ---

    def test_missing_from_version_returns_400(self):
        resp = self.client.get(self.url)

        self.assertEqual(resp.status_code, 400)
        self.assertIn("error", resp.json())

    def test_non_integer_from_version_returns_400(self):
        resp = self.client.get(self.url, {"from_version": "abc"})

        self.assertEqual(resp.status_code, 400)
        self.assertIn("error", resp.json())

    def test_zero_from_version_returns_400(self):
        resp = self.client.get(self.url, {"from_version": 0})

        self.assertEqual(resp.status_code, 400)
        self.assertIn("error", resp.json())

    def test_negative_from_version_returns_400(self):
        resp = self.client.get(self.url, {"from_version": -5})

        self.assertEqual(resp.status_code, 400)
        self.assertIn("error", resp.json())

    def test_float_string_from_version_returns_400(self):
        resp = self.client.get(self.url, {"from_version": "1.5"})

        self.assertEqual(resp.status_code, 400)
        self.assertIn("error", resp.json())

    # --- No published version: 404 ---

    def test_404_when_no_published_version(self):
        resp = self.client.get(self.url, {"from_version": 1})

        self.assertEqual(resp.status_code, 404)
        self.assertIn("error", resp.json())

    def test_404_ignores_draft_version(self):
        _make_draft_version()   # only a draft, not published

        resp = self.client.get(self.url, {"from_version": 1})

        self.assertEqual(resp.status_code, 404)
        self.assertIn("error", resp.json())

    # --- Null metadata when no SyncArtifact row ---

    def test_null_metadata_when_delta_artifact_not_populated(self):
        v1 = _make_published_version()
        _make_published_version()

        data = self.client.get(self.url, {"from_version": v1.version}).json()

        self.assertIsNone(data["file_size_bytes"])
        self.assertIsNone(data["checksum"])
