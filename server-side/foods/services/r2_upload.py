"""
r2_upload.py — Cloudflare R2 upload service.

Responsibilities
----------------
1. Parse a local export file path to determine artifact type and version(s).
2. Compute SHA-256 checksum and byte size.
3. Upload the file to Cloudflare R2 under the canonical R2 key expected by the
   sync API views (e.g. ``snapshots/version_3_snapshot.db.gz``).
4. Create or update the ``SyncArtifact`` DB row so the API can serve metadata.

Django is never involved in downloading or proxying the binary — this service
only *writes* to R2 and updates the metadata table.

Supported filename patterns (produced by ``export_sync`` management command)
---------------------------------------------------------------------------
  Snapshot : exports/snapshots/snapshot_{version}.db.gz
  Delta    : exports/deltas/delta_{from}_{to}.json

Canonical R2 key (matches the URL pattern served by the API)
------------------------------------------------------------
  Snapshot : snapshots/version_{version}_snapshot.db.gz
  Delta    : deltas/delta_{from}_to_{to}.json
"""

import hashlib
import re
from pathlib import Path

import boto3
from botocore.config import Config
from django.conf import settings
from django.db import transaction

from foods.models import DbVersion, SyncArtifact

# ---------------------------------------------------------------------------
# Filename parsing
# ---------------------------------------------------------------------------

_SNAPSHOT_RE = re.compile(r"^snapshot_(\d+)\.db\.gz$")
_DELTA_RE    = re.compile(r"^delta_(\d+)_(\d+)\.json$")


class ParseError(ValueError):
    """Raised when the filename does not match a known export pattern."""


def parse_export_path(path: Path) -> dict:
    """
    Inspect *path* and return a dict describing the artifact:

    For a snapshot::

        {
            "type": "snapshot",
            "version": 3,
            "r2_key": "snapshots/version_3_snapshot.db.gz",
        }

    For a delta::

        {
            "type": "delta",
            "from_version": 1,
            "version": 3,
            "r2_key": "deltas/delta_1_to_3.json",
        }
    """
    name = path.name

    m = _SNAPSHOT_RE.match(name)
    if m:
        version = int(m.group(1))
        return {
            "type": "snapshot",
            "version": version,
            "r2_key": f"snapshots/version_{version}_snapshot.db.gz",
        }

    m = _DELTA_RE.match(name)
    if m:
        from_v, to_v = int(m.group(1)), int(m.group(2))
        return {
            "type": "delta",
            "from_version": from_v,
            "version": to_v,
            "r2_key": f"deltas/delta_{from_v}_to_{to_v}.json",
        }

    raise ParseError(
        f"Cannot determine artifact type from filename '{name}'. "
        "Expected 'snapshot_<v>.db.gz' or 'delta_<from>_<to>.json'."
    )


# ---------------------------------------------------------------------------
# File metadata
# ---------------------------------------------------------------------------

def compute_metadata(path: Path) -> tuple[int, str]:
    """Return (file_size_bytes, sha256_hex) for *path*."""
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):  # 1 MiB chunks
            h.update(chunk)
            size += len(chunk)
    return size, h.hexdigest()


# ---------------------------------------------------------------------------
# R2 client
# ---------------------------------------------------------------------------

def _build_r2_client():
    """
    Return a boto3 S3 client configured for Cloudflare R2.

    R2 is S3-compatible; the endpoint is:
        https://<account_id>.r2.cloudflarestorage.com
    """
    account_id = settings.R2_ACCOUNT_ID
    if not account_id:
        raise RuntimeError(
            "R2_ACCOUNT_ID is not set. Add it to your .env file."
        )
    for key in ("R2_ACCESS_KEY", "R2_SECRET_KEY", "R2_BUCKET_NAME"):
        if not getattr(settings, key, ""):
            raise RuntimeError(f"{key} is not set. Add it to your .env file.")

    return boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY,
        aws_secret_access_key=settings.R2_SECRET_KEY,
        config=Config(signature_version="s3v4"),
        region_name="auto",
    )


# ---------------------------------------------------------------------------
# DB artifact record
# ---------------------------------------------------------------------------

@transaction.atomic
def _upsert_sync_artifact(
    *,
    artifact_type: str,
    version: int,
    from_version: int | None,
    file_size_bytes: int,
    checksum: str,
) -> SyncArtifact:
    """
    Create or update the SyncArtifact row for this artifact.

    Raises ValueError if the target DbVersion does not exist or is not published.
    """
    try:
        db_version = DbVersion.objects.get(version=version, is_published=True)
    except DbVersion.DoesNotExist:
        raise ValueError(
            f"DbVersion {version} does not exist or is not published. "
            "Publish the version before uploading its artifact."
        )

    artifact, created = SyncArtifact.objects.update_or_create(
        version=db_version,
        artifact_type=artifact_type,
        from_version=from_version,
        defaults={
            "file_size_bytes": file_size_bytes,
            "checksum": checksum,
        },
    )
    return artifact


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def upload_artifact(path: Path, *, dry_run: bool = False, local: bool = False) -> dict:
    """
    Full upload pipeline for a single export file.

    Parameters
    ----------
    path:
        Absolute (or relative) path to a local export file.
    dry_run:
        If True, skip the actual S3 put and DB write; just return what
        *would* happen. Useful for CI validation.
    local:
        If True, skip the boto3 upload (no R2 credentials needed) but still
        compute real checksums and write the SyncArtifact DB row.
        Use this for demos and reviewer recordings when R2 is not set up yet.

    Returns
    -------
    A dict with the keys ``r2_key``, ``file_size_bytes``, ``checksum``,
    ``artifact_type``, ``version`` (and ``from_version`` for deltas).
    """
    path = Path(path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"Export file not found: {path}")

    info = parse_export_path(path)
    file_size_bytes, checksum = compute_metadata(path)

    result = {
        **info,
        "file_size_bytes": file_size_bytes,
        "checksum": checksum,
        "artifact_type": info["type"],
        "dry_run": dry_run,
        "local": local,
    }

    if dry_run:
        return result

    if not local:
        # Upload to R2
        client = _build_r2_client()
        content_type = (
            "application/gzip" if info["type"] == "snapshot" else "application/json"
        )
        client.upload_file(
            Filename=str(path),
            Bucket=settings.R2_BUCKET_NAME,
            Key=info["r2_key"],
            ExtraArgs={"ContentType": content_type},
        )

    # Persist metadata (runs for both real and local modes)
    _upsert_sync_artifact(
        artifact_type=SyncArtifact.SNAPSHOT if info["type"] == "snapshot" else SyncArtifact.DELTA,
        version=info["version"],
        from_version=info.get("from_version"),
        file_size_bytes=file_size_bytes,
        checksum=checksum,
    )

    return result
