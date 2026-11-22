"""
Management command: upload_to_r2

Uploads a locally-generated export file (snapshot or delta) to Cloudflare R2
and records its metadata (size, checksum) in the SyncArtifact table so the
sync API can serve it immediately.

Usage
-----
    # Upload a snapshot
    python manage.py upload_to_r2 exports/snapshots/snapshot_3.db.gz

    # Upload a delta
    python manage.py upload_to_r2 exports/deltas/delta_1_2.json

    # Validate without uploading or writing to DB
    python manage.py upload_to_r2 exports/snapshots/snapshot_3.db.gz --dry-run

    # Skip the actual R2 upload but write metadata to DB (demo / reviewer mode)
    python manage.py upload_to_r2 exports/snapshots/snapshot_3.db.gz --local

Typical CI/CD pipeline
-----------------------
    python manage.py export_sync snapshot
    python manage.py upload_to_r2 exports/snapshots/snapshot_<version>.db.gz
"""

from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from foods.services.r2_upload import upload_artifact, ParseError


class Command(BaseCommand):
    help = (
        "Upload a local export file to Cloudflare R2 and store its "
        "metadata (size, checksum) in the SyncArtifact table."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "file",
            type=Path,
            help=(
                "Path to the export file to upload. "
                "Must match snapshot_<v>.db.gz or delta_<from>_<to>.json."
            ),
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            default=False,
            help=(
                "Parse the file and compute its checksum, but do NOT upload "
                "to R2 or write to the database. Useful for validation in CI."
            ),
        )
        parser.add_argument(
            "--local",
            action="store_true",
            default=False,
            help=(
                "Skip the actual R2 upload (no credentials needed) but still "
                "compute real checksums and write the SyncArtifact DB row. "
                "Use this for demos and reviewer recordings when R2 is not set up yet. "
                "The API will return real file sizes, checksums, and correctly "
                "formatted download URLs."
            ),
        )

    def handle(self, *args, **options):
        path: Path = options["file"]
        dry_run: bool = options["dry_run"]
        local: bool = options["local"]

        if dry_run and local:
            raise CommandError("--dry-run and --local are mutually exclusive.")

        try:
            result = upload_artifact(path, dry_run=dry_run, local=local)
        except FileNotFoundError as exc:
            raise CommandError(str(exc)) from exc
        except ParseError as exc:
            raise CommandError(str(exc)) from exc
        except ValueError as exc:
            raise CommandError(str(exc)) from exc
        except RuntimeError as exc:
            raise CommandError(str(exc)) from exc
        except Exception as exc:
            raise CommandError(f"Upload failed: {exc}") from exc

        if dry_run:
            prefix = "[DRY RUN] "
        elif local:
            prefix = "[LOCAL MODE] "
        else:
            prefix = ""

        artifact_type = result["artifact_type"].capitalize()

        self.stdout.write(self.style.SUCCESS(f"{prefix}{artifact_type} processed successfully."))
        self.stdout.write(f"  R2 key      : {result['r2_key']}")
        self.stdout.write(f"  Size        : {result['file_size_bytes']:,} bytes")
        self.stdout.write(f"  SHA-256     : {result['checksum']}")
        self.stdout.write(f"  Version     : {result['version']}")
        if result["artifact_type"] == "delta":
            self.stdout.write(f"  From version: {result['from_version']}")

        if dry_run:
            self.stdout.write(
                self.style.WARNING("No files were uploaded and no DB rows were written.")
            )
        elif local:
            self.stdout.write(
                self.style.WARNING(
                    "LOCAL MODE: R2 upload was skipped. "
                    "Metadata written to DB — the sync API will return real checksums "
                    "and correctly-formatted URLs (files won't be downloadable until "
                    "uploaded to real R2)."
                )
            )
