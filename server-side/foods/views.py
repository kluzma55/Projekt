"""
Synchronisation API endpoints for the mobile client (Flutter).

All endpoints are read-only (GET).  Django never downloads, proxies, or serves
binary files — it only assembles public CDN URL strings and returns metadata.

Endpoints
---------
GET /api/sync/status/   → latest published version number
GET /api/sync/snapshot/ → snapshot metadata + R2 download URL
GET /api/sync/delta/    → delta metadata + R2 download URL (requires ?from_version=N)
"""

from django.conf import settings
from django.http import JsonResponse
from django.views import View

from .models import DbVersion, SyncArtifact


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _latest_published():
    """Return the latest published DbVersion or None."""
    return (
        DbVersion.objects
        .filter(is_published=True)
        .order_by('-version')
        .first()
    )


def _r2_base() -> str:
    """Return R2_PUBLIC_URL with any trailing slash stripped (defensive guard)."""
    return settings.R2_PUBLIC_URL.rstrip("/")


def _snapshot_url(version: int) -> str:
    return f"{_r2_base()}/snapshots/version_{version}_snapshot.db.gz"


def _delta_url(from_version: int, to_version: int) -> str:
    return f"{_r2_base()}/deltas/delta_{from_version}_to_{to_version}.json"


def _artifact_meta(db_version: DbVersion, artifact_type: str, from_version: int | None = None):
    """
    Return (file_size_bytes, checksum) for the requested artifact, falling back
    to (None, None) when the row has not been populated yet.
    """
    qs = SyncArtifact.objects.filter(version=db_version, artifact_type=artifact_type)
    if artifact_type == SyncArtifact.DELTA:
        qs = qs.filter(from_version=from_version)
    artifact = qs.first()
    if artifact is None:
        return None, None
    return artifact.file_size_bytes, artifact.checksum


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

class SyncStatusView(View):
    """GET /api/sync/status/"""

    def get(self, request):
        latest = _latest_published()
        if latest is None:
            return JsonResponse(
                {"error": "No published version available."},
                status=404,
            )
        return JsonResponse({"latest_version": latest.version})


class SyncSnapshotView(View):
    """GET /api/sync/snapshot/"""

    def get(self, request):
        latest = _latest_published()
        if latest is None:
            return JsonResponse(
                {"error": "No published version available."},
                status=404,
            )

        file_size_bytes, checksum = _artifact_meta(latest, SyncArtifact.SNAPSHOT)

        return JsonResponse({
            "current_version": latest.version,
            "file_size_bytes": file_size_bytes,
            "checksum": checksum,
            "download_url": _snapshot_url(latest.version),
        })


class SyncDeltaView(View):
    """GET /api/sync/delta/?from_version=<int>"""

    def get(self, request):
        # --- Validate query param ---
        raw = request.GET.get("from_version")
        if raw is None:
            return JsonResponse(
                {"error": "Missing required query parameter: from_version."},
                status=400,
            )
        try:
            from_version = int(raw)
        except (TypeError, ValueError):
            return JsonResponse(
                {"error": "from_version must be a valid integer."},
                status=400,
            )
        if from_version < 1:
            return JsonResponse(
                {"error": "from_version must be >= 1."},
                status=400,
            )

        # --- Resolve latest published version ---
        latest = _latest_published()
        if latest is None:
            return JsonResponse(
                {"error": "No published version available."},
                status=404,
            )

        current_version = latest.version

        # --- Already up-to-date ---
        if from_version >= current_version:
            return JsonResponse({
                "current_version": current_version,
                "up_to_date": True,
                "download_url": None,
            })

        # --- Delta available ---
        file_size_bytes, checksum = _artifact_meta(
            latest, SyncArtifact.DELTA, from_version=from_version
        )

        return JsonResponse({
            "current_version": current_version,
            "file_size_bytes": file_size_bytes,
            "checksum": checksum,
            "download_url": _delta_url(from_version, current_version),
        })
