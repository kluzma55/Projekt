from django.urls import path
from .views import SyncStatusView, SyncSnapshotView, SyncDeltaView

app_name = "foods"

urlpatterns = [
    path("status/", SyncStatusView.as_view(), name="sync-status"),
    path("snapshot/", SyncSnapshotView.as_view(), name="sync-snapshot"),
    path("delta/", SyncDeltaView.as_view(), name="sync-delta"),
]
