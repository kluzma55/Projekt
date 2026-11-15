from django.core.management.base import BaseCommand, CommandError
from foods.sync_export import export_delta, export_snapshot


class Command(BaseCommand):
    help = 'Generate catalogue files for Cloudflare R2 (no upload).'

    def add_arguments(self, parser):
        modes = parser.add_subparsers(dest='mode', required=True)
        delta = modes.add_parser('delta', help='Export changes between published versions')
        delta.add_argument('--from-version', type=int, required=True)
        delta.add_argument('--to-version', type=int, default=None)
        delta.add_argument('--output-dir', default=None)
        snapshot = modes.add_parser('snapshot', help='Export latest published version')
        snapshot.add_argument('--output-dir', default=None)

    def handle(self, *args, **options):
        try:
            if options['mode'] == 'delta':
                path = export_delta(options['from_version'], options['to_version'],
                                    options['output_dir'])
            else:
                path = export_snapshot(options['output_dir'])
        except (ValueError, OSError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(self.style.SUCCESS(f'Export saved: {path}'))
