"""
Management command: demo_sync

One-command demo setup for reviewer recordings.

Creates a realistic two-version scenario with real food data, exports snapshot
and delta files, runs the full upload pipeline in --local mode (no R2 needed),
then prints every API endpoint's response so you can see exactly what the
Flutter client will receive.

Usage
-----
    python manage.py demo_sync

What it does (all in one command)
-----------------------------------
    1. Create published version 1  (3 foods: Apple, Banana, Bread)
    2. Modify Banana's kcal, add Chicken → publish version 2
    3. Export snapshot  (snapshot_<v2>.db.gz)
    4. Export delta     (delta_<v1>_<v2>.json)
    5. Upload both in --local mode (real checksums, no R2 credentials)
    6. Print all three API responses with curl commands

WARNING: This command inserts real rows into whichever database Django is
         currently configured to use.  Run against a local dev DB only.
"""

import json
import textwrap
from decimal import Decimal
from io import StringIO
from pathlib import Path
import tempfile

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.test import RequestFactory

from foods.models import DbVersion, Food
from foods.services.r2_upload import upload_artifact
from foods.views import SyncStatusView, SyncSnapshotView, SyncDeltaView


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ZEROES = dict(
    protein_g=Decimal("0"), carbs_g=Decimal("0"), sugars_g=Decimal("0"),
    fat_g=Decimal("0"), saturated_fat_g=Decimal("0"),
    fibers_g=Decimal("0"), salt_g=Decimal("0"),
)

def _food(name, ean, kcal):
    return Food.objects.create(name=name, ean=ean, kcal_per_100=Decimal(str(kcal)), **_ZEROES)

def _publish():
    v = DbVersion.objects.get(is_published=False)
    v.is_published = True
    v.save(update_fields=["is_published"])
    return v.version

def _call_view(view_cls, path, query_string=""):
    factory = RequestFactory()
    url = path + (f"?{query_string}" if query_string else "")
    request = factory.get(url)
    response = view_cls.as_view()(request)
    return json.loads(response.content)

def _section(title):
    width = 60
    print()
    print("=" * width)
    print(f"  {title}")
    print("=" * width)

def _json(data):
    print(json.dumps(data, indent=2))


# ---------------------------------------------------------------------------
# Command
# ---------------------------------------------------------------------------

class Command(BaseCommand):
    help = "One-command demo: sets up data, exports files, and shows all API responses."

    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING(
            "\n Warning: demo_sync writes real rows to your current database.\n"
            "   Use only against a local dev DB.\n"
        ))

        # Ensure all migrations are applied (critical for in-memory SQLite
        # used with --settings=backend.test_settings).
        self.stdout.write("  Applying migrations...")
        call_command("migrate", "--run-syncdb", verbosity=0)

        with tempfile.TemporaryDirectory() as tmp_dir:
            export_dir = Path(tmp_dir)

            # ── STEP 1: Version 1 ────────────────────────────────────────────
            _section("STEP 1 — Create & publish Version 1 (3 foods)")
            apple  = _food("Apple",  "0000000000001", 52)
            banana = _food("Banana", "0000000000002", 89)
            bread  = _food("Bread",  "0000000000003", 265)
            v1 = _publish()
            print(f"  ✓ Published Version {v1} with 3 foods: Apple, Banana, Bread")

            # ── STEP 2: Version 2 ────────────────────────────────────────────
            _section("STEP 2 — Modify Banana, add Chicken → publish Version 2")
            banana.kcal_per_100 = Decimal("95")
            banana.save()
            _food("Chicken", "0000000000004", 165)
            v2 = _publish()
            print(f"  ✓ Published Version {v2}")
            print(f"    Changes: Banana kcal 89→95, Chicken added")

            # ── STEP 3: Export snapshot ───────────────────────────────────────
            _section(f"STEP 3 — Export snapshot for Version {v2}")
            out = StringIO()
            call_command("export_sync", "snapshot", f"--output-dir={export_dir}", stdout=out)
            snapshot_path = export_dir / "snapshots" / f"snapshot_{v2}.db.gz"
            print(f"  ✓ {snapshot_path.name}  ({snapshot_path.stat().st_size:,} bytes)")

            # ── STEP 4: Export delta ─────────────────────────────────────────
            _section(f"STEP 4 — Export delta from Version {v1} → {v2}")
            call_command("export_sync", "delta",
                         f"--from-version={v1}", f"--output-dir={export_dir}", stdout=out)
            delta_path = export_dir / "deltas" / f"delta_{v1}_{v2}.json"
            print(f"  ✓ {delta_path.name}  ({delta_path.stat().st_size:,} bytes)")
            delta_content = json.loads(delta_path.read_text(encoding="utf-8"))
            print(f"  Delta contains {len(delta_content['changes'])} change(s):")
            for change in delta_content["changes"]:
                print(f"    • food_id={change['food_id']}  action={change['action']}", end="")
                if "data" in change:
                    print(f"  data={change['data']}", end="")
                print()

            # ── STEP 5: Upload (local mode — no R2 credentials) ──────────────
            _section("STEP 5 — Upload artifacts in LOCAL mode (no R2 needed)")
            snap_result  = upload_artifact(snapshot_path, local=True)
            delta_result = upload_artifact(delta_path, local=True)
            print(f"  ✓ Snapshot  → R2 key : {snap_result['r2_key']}")
            print(f"               SHA-256 : {snap_result['checksum']}")
            print(f"               Size    : {snap_result['file_size_bytes']:,} bytes")
            print()
            print(f"  ✓ Delta     → R2 key : {delta_result['r2_key']}")
            print(f"               SHA-256 : {delta_result['checksum']}")
            print(f"               Size    : {delta_result['file_size_bytes']:,} bytes")

            # ── STEP 6: Call all three API endpoints ─────────────────────────
            _section("STEP 6 — Sync API responses (what the Flutter client sees)")

            print("\n  GET /api/sync/status/")
            _json(_call_view(SyncStatusView, "/api/sync/status/"))

            print("\n  GET /api/sync/snapshot/")
            _json(_call_view(SyncSnapshotView, "/api/sync/snapshot/"))

            print(f"\n  GET /api/sync/delta/?from_version={v1}  (update available)")
            _json(_call_view(SyncDeltaView, "/api/sync/delta/", f"from_version={v1}"))

            print(f"\n  GET /api/sync/delta/?from_version={v2}  (already up-to-date)")
            _json(_call_view(SyncDeltaView, "/api/sync/delta/", f"from_version={v2}"))

            print(f"\n  GET /api/sync/delta/  (missing param → 400)")
            _json(_call_view(SyncDeltaView, "/api/sync/delta/"))

            # ── Curl cheat-sheet ─────────────────────────────────────────────
           # _section("Curl cheat-sheet (run with Django dev server on :8000)")
           # cmds = textwrap.dedent(f"""\
           #     curl -s http://127.0.0.1:8000/api/sync/status/   | python -m json.tool
           #     curl -s http://127.0.0.1:8000/api/sync/snapshot/ | python -m json.tool
           #     curl -s "http://127.0.0.1:8000/api/sync/delta/?from_version={v1}" | python -m json.tool
           #     curl -s "http://127.0.0.1:8000/api/sync/delta/?from_version={v2}" | python -m json.tool
           #     curl -s "http://127.0.0.1:8000/api/sync/delta/?from_version=abc"  | python -m json.tool
            #""")
            #print(cmds)

        self.stdout.write(self.style.SUCCESS("\nDemo complete — all data is in the database."))
        self.stdout.write(
            "    Start the dev server and hit the curl commands above on camera.\n"
        )
