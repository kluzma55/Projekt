from django.core.management.base import BaseCommand, CommandError
from foods.services.etl import run_dump_food_etl, run_food_etl, run_full_food_etl


class Command(BaseCommand):
    help = "Spustí synchronizaci databáze potravin z OpenFoodFacts (UC14 / E7)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--file",
            type=str,
            default=None,
            help="Cesta k lokálnímu exportnímu souboru .jsonl.gz z OpenFoodFacts.",
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

        try:
            if options["file"]:
                self.stdout.write(f"Spouštím import ze souboru {options['file']}...")
                stats = run_dump_food_etl(file_path=options["file"], on_progress=print_progress)
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