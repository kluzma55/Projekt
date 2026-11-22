from django.core.management.base import BaseCommand, CommandError
from foods.services.etl import (
    run_dump_food_etl,
    run_food_etl,
    run_full_food_etl,
    verify_food_database_quality,
)


class Command(BaseCommand):
    help = "Spustí synchronizaci databáze potravin z OpenFoodFacts (UC14 / E6)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dump",
            action="store_true",
            help="Stáhne aktuální hromadný export .jsonl.gz z OpenFoodFacts a provede kompletní import.",
        )
        parser.add_argument(
            "--file",
            type=str,
            default=None,
            help="Cesta k lokálnímu exportnímu souboru .jsonl.gz z OpenFoodFacts.",
        )
        parser.add_argument(
            "--keep-file",
            action="store_true",
            help="Při použití --dump nesmaže stažený .jsonl.gz soubor po dokončení.",
        )
        parser.add_argument(
            "--full",
            action="store_true",
            help="Projde katalog po stránkách přes API.",
        )
        parser.add_argument(
            "--start-page",
            type=int,
            default=1,
            help="Číslo stránky pro API import (výchozí: 1).",
        )
        parser.add_argument(
            "--max-pages",
            type=int,
            default=None,
            help="Maximální počet stránek pro API import.",
        )

    def handle(self, *args, **options):
        def print_progress(step, stats):
            self.stdout.write(
                f"Dávka/stránka {step} hotova | "
                f"vytvořeno: {stats['created']}, "
                f"upraveno: {stats['updated']}, "
                f"beze změny: {stats['skipped']}, "
                f"zahozeno nevalidních: {stats['invalid']}"
            )

        def print_download(downloaded, total):
            mb_done = downloaded / (1024 * 1024)
            if total > 0:
                pct = (downloaded / total) * 100
                self.stdout.write(f"Stahuji export OFF: {mb_done:.0f} MB ({pct:.1f} %)")
            else:
                self.stdout.write(f"Stahuji export OFF: {mb_done:.0f} MB")

        try:
            if options["dump"] or options["file"]:
                source_label = options["file"] if options["file"] else "online hromadného exportu OFF"
                self.stdout.write(f"Spouštím kompletní import z {source_label}...")
                stats = run_dump_food_etl(
                    file_path=options["file"],
                    keep_file=options["keep_file"],
                    on_progress=print_progress,
                    on_download_progress=print_download,
                )
            elif options["full"]:
                self.stdout.write("Spouštím import z API po stránkách...")
                stats = run_full_food_etl(
                    start_page=options["start_page"],
                    max_pages=options["max_pages"],
                    on_progress=print_progress,
                )
            else:
                self.stdout.write("Spouštím rychlou synchronizaci první stránky...")
                stats = run_food_etl()
        except Exception as exc:
            raise CommandError(f"Import selhal: {exc}") from exc

        self.stdout.write(
            self.style.SUCCESS(
                f"Import dokončen | vytvořeno: {stats['created']}, "
                f"upraveno: {stats['updated']}, "
                f"beze změny: {stats['skipped']}, "
                f"zahozeno nevalidních: {stats['invalid']}"
            )
        )

        if options["dump"] or options["file"]:
            quality = verify_food_database_quality()
            self.stdout.write(
                f"Kontrola kvality DB | aktivních položek: {quality['total_active']}, "
                f"duplicitní EAN: {quality['duplicate_eans']}, "
                f"nevalidní EAN: {quality['invalid_eans']}, "
                f"chybějící povinná pole: {quality['missing_required_fields']}"
            )