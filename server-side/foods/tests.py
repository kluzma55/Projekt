from decimal import Decimal
from io import StringIO
from unittest.mock import patch
import requests
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.urls import reverse
from .models import Food, DbVersion, Changelog
from .services import normalize_openfoodfacts_item, run_food_etl

class ChangelogRobustnessTests(TestCase):
    
    def publish_current_version(self):
        """Pomocná metoda, která nasimuluje uzavření/vydání aktuální verze."""
        draft = DbVersion.objects.get(is_published=False)
        draft.is_published = True
        draft.save()
        return draft

    def test_genesis_version_no_delta_logs(self):
        """
        KRITICKÝ TEST: Položka vytvořená a upravovaná v té samé (a to i první) verzi 
        nesmí nikdy generovat delta logy (old_values/new_values musí být prázdné).
        """
        # 1. Vytvoření
        food = Food.objects.create(name="Jablko", kcal_per_100=50)
        log = Changelog.objects.get(food=food)
        
        self.assertEqual(log.action, 'CREATED', "Akce musí být CREATED.")
        self.assertEqual(log.old_values, {}, "Old values musí být prázdné.")
        self.assertEqual(log.new_values, {}, "New values musí být prázdné.")
        self.assertIsNone(food.updated_in_version, "Updated in version musí být None.")

        # 2. Úprava ve stejné verzi
        food.kcal_per_100 = 60
        food.save()
        
        # Testujeme, že to nepřepsalo akci na UPDATED a nezačalo to logovat hodnoty
        log.refresh_from_db()
        self.assertEqual(log.action, 'CREATED', "Změna v domovské verzi nesmí přepsat akci z CREATED.")
        self.assertEqual(log.old_values, {}, "I po úpravě musí zůstat old_values prázdné.")
        self.assertEqual(log.new_values, {}, "I po úpravě musí zůstat new_values prázdné.")

    def test_cross_version_update_generates_delta(self):
        """
        KRITICKÝ TEST: Jakmile je položka z minulé verze upravena, 
        musí uložit správné delty a nastavit 'updated_in_version'.
        """
        food = Food.objects.create(name="Banán", kcal_per_100=90)
        v1 = self.publish_current_version()

        # Úprava ve Verzi 2
        food.kcal_per_100 = 100
        food.save()
        
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        food.refresh_from_db()

        self.assertEqual(log.action, 'UPDATED')
        self.assertEqual(log.old_values['kcal_per_100'], '90.00', "Old value si musí pamatovat stav z V1.")
        self.assertEqual(log.new_values['kcal_per_100'], '100.00', "New value musí obsahovat novou hodnotu.")
        self.assertEqual(food.updated_in_version, v2, "Pole updated_in_version musí ukazovat na V2.")

    def test_ping_pong_effect_cancels_log(self):
        """
        KRITICKÝ TEST: Pokud uživatel změní hodnotu a pak ji ve stejné verzi vrátí zpět,
        záznam v logu se musí kompletně smazat (net-zero change).
        """
        food = Food.objects.create(name="Ořechy", kcal_per_100=600)
        self.publish_current_version()

        # Změna z 600 na 650 (Verze 2)
        food.kcal_per_100 = 650
        food.save()
        
        v2 = DbVersion.objects.get(is_published=False)
        self.assertTrue(Changelog.objects.filter(food=food, version=v2).exists(), "Log by měl existovat.")

        # Změna zpět z 650 na 600 (Ping-pong)
        food.kcal_per_100 = 600
        food.save()

        # Záznam by měl kompletně zmizet, protože se vlastně nic nezměnilo
        log_exists = Changelog.objects.filter(food=food, version=v2).exists()
        self.assertFalse(log_exists, "Ping-pong změna nedokázala smazat zbytečný log!")

    def test_partial_ping_pong_keeps_log(self):
        """
        KRITICKÝ TEST: Pokud uživatel změní 2 věci, ale vrátí zpět jen jednu z nich,
        log musí přežít, ale vrácená hodnota z něj musí zmizet.
        """
        food = Food.objects.create(name="Mléko", kcal_per_100=40)
        self.publish_current_version()

        # Měníme dvě věci
        food.name = "Plnotučné mléko"
        food.kcal_per_100 = 65
        food.save()

        # Vracíme zpět POUZE kalorie na 40
        food.kcal_per_100 = 40
        food.save()

        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)

        self.assertIn('name', log.new_values, "Název se trvale změnil, musí být v logu.")
        self.assertNotIn('kcal_per_100', log.new_values, "Kalorie se vrátily zpět, v logu NESMÍ být!")
        self.assertNotIn('kcal_per_100', log.old_values, "Kalorie nesmí být ani v old_values.")

    def test_soft_delete_and_restore_in_same_version(self):
        """
        KRITICKÝ TEST: Změna is_active na False a zpět na True 
        (jak v domovské verzi, tak v cizí verzi).
        """
        # A) V domovské verzi (vytvoření, smazání, obnova)
        food = Food.objects.create(name="Tatranka", kcal_per_100=500)
        
        food.is_active = False
        food.save()
        log = Changelog.objects.get(food=food)
        self.assertEqual(log.action, 'DELETED', "Po skrytí nové položky musí být akce DELETED.")
        
        food.is_active = True
        food.save()
        log.refresh_from_db()
        self.assertEqual(log.action, 'CREATED', "Po obnovení nové položky musí být akce zpět na CREATED.")

        # B) V cizí verzi (historická položka)
        self.publish_current_version()
        
        food.is_active = False # Skrýváme ve V2
        food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log_v2 = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log_v2.action, 'DELETED')
        self.assertEqual(log_v2.new_values['is_active'], 'False')

        food.is_active = True # Odkrýváme zpět ve V2 (Ping-pong)
        food.save()
        self.assertFalse(Changelog.objects.filter(food=food, version=v2).exists(), "Obnovení historické položky nesmazalo zbytečný DELETED log!")

    def test_decimal_ghost_update_ignored(self):
        """
        KRITICKÝ TEST: Změna formátu desetinného čísla (např. 744.00 na 744 nebo 744.0)
        nesmí vygenerovat vůbec žádný log, protože matematicky se nic nemění.
        """
        food = Food.objects.create(name="Máslo", kcal_per_100=Decimal('744.00'))
        self.publish_current_version()

        # Přiřazení "jiného" typu téže hodnoty
        food.kcal_per_100 = Decimal('744')
        food.save()

        food.kcal_per_100 = 744.0
        food.save()

        # Ověření
        v2 = DbVersion.objects.get(is_published=False)
        log_exists = Changelog.objects.filter(food=food, version=v2).exists()
        self.assertFalse(log_exists, "Kód naletěl na falešného ducha! Vytvořil log pro matematicky totožné číslo.")

class FoodEtlPipelineTests(TestCase):
    """Testy čištění dat z OpenFoodFacts a napojení na verzování + Changelog."""

    def test_normalize_valid_and_invalid_items(self):
        valid_raw = {
            "code": "8594001234567",
            "product_name_cs": "Polotučné mléko",
            "nutriments": {
                "energy-kcal_100g": "47.5",
                "proteins_100g": 3.3,
                "carbohydrates_100g": 4.8,
                "sugars_100g": 4.8,
                "fat_100g": 1.5,
                "saturated-fat_100g": 1.0,
                "fiber_100g": 0,
                "salt_100g": 0.1,
            },
            "image_front_small_url": "https://images.openfoodfacts.org/milk.jpg",
        }
        cleaned = normalize_openfoodfacts_item(valid_raw)
        self.assertIsNotNone(cleaned)
        self.assertEqual(cleaned["ean"], "8594001234567")
        self.assertEqual(cleaned["name"], "Polotučné mléko")
        self.assertEqual(cleaned["kcal_per_100"], Decimal("47.50"))

        # Pouze povinné atributy (EAN, název, kalorie) -> projde, nepovinné se doplní jako 0.00
        minimal_cleaned = normalize_openfoodfacts_item(
            {"code": "8594001234567", "product_name": "Test", "nutriments": {"energy-kcal_100g": 100}}
        )
        self.assertIsNotNone(minimal_cleaned)
        self.assertEqual(minimal_cleaned["kcal_per_100"], Decimal("100.00"))
        self.assertEqual(minimal_cleaned["protein_g"], Decimal("0.00"))
        self.assertEqual(minimal_cleaned["carbs_g"], Decimal("0.00"))
        self.assertEqual(minimal_cleaned["fat_g"], Decimal("0.00"))

        # Nevalidní EAN -> zahozeno
        self.assertIsNone(normalize_openfoodfacts_item({**valid_raw, "code": "ABC-123"}))

        # Chybějící povinné kalorie -> zahozeno
        self.assertIsNone(
            normalize_openfoodfacts_item(
                {"code": "8594001234567", "product_name": "Test", "nutriments": {"proteins_100g": 10}}
            )
        )

        # Záporná hodnota -> zahozeno
        bad_nutriments = dict(valid_raw["nutriments"], fat_100g=-5)
        self.assertIsNone(normalize_openfoodfacts_item({**valid_raw, "nutriments": bad_nutriments}))

    @patch("foods.services.requests.get")
    def test_etl_creates_food_and_skips_identical_on_rerun(self, mock_get):
        """1. běh vytvoří Food + Changelog; 2. běh se stejnými daty nic nezmění."""
        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "products": [
                {
                    "code": "8594001112223",
                    "product_name": "Ovesné vločky",
                    "nutriments": {
                        "energy-kcal_100g": 370,
                        "proteins_100g": 13,
                        "carbohydrates_100g": 60,
                        "fat_100g": 7,
                    },
                },
                {
                    "code": "invalid",
                    "product_name": "Špatný záznam",
                    "nutriments": {},
                },
            ]
        }

        stats_first = run_food_etl()
        self.assertEqual(stats_first, {"created": 1, "updated": 0, "skipped": 0, "invalid": 1})
        self.assertEqual(Food.objects.count(), 1)
        self.assertEqual(Changelog.objects.count(), 1)

        # Opakovaný běh se stejnými daty nesmí vygenerovat žádné zbytečné změny
        stats_second = run_food_etl()
        self.assertEqual(stats_second, {"created": 0, "updated": 0, "skipped": 1, "invalid": 1})
        self.assertEqual(Changelog.objects.count(), 1)

    @patch("foods.services.requests.get")
    def test_etl_cross_version_update_creates_new_draft_version(self, mock_get):
        """Změna dat v externím API po publikaci verze vytvoří novou verzi a UPDATED log."""
        v1 = DbVersion.objects.create(version=1, is_published=False)
        food = Food.objects.create(
            ean="8594009998887",
            name="Tvaroh měkký",
            kcal_per_100=Decimal("100.00"),
            protein_g=Decimal("12.00"),
            carbs_g=Decimal("4.00"),
            sugars_g=Decimal("4.00"),
            fat_g=Decimal("3.50"),
            saturated_fat_g=Decimal("2.20"),
            fibers_g=Decimal("0.00"),
            salt_g=Decimal("0.10"),
        )
        # Publikujeme verzi 1, aby následná změna z ETL musela otevřít verzi 2
        v1.is_published = True
        v1.save()

        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "products": [
                {
                    "code": "8594009998887",
                    "product_name": "Tvaroh měkký",
                    "nutriments": {
                        "energy-kcal_100g": 115,
                        "proteins_100g": 12,
                        "carbohydrates_100g": 4,
                        "sugars_100g": 4,
                        "fat_100g": 3.5,
                        "saturated-fat_100g": 2.2,
                        "fiber_100g": 0,
                        "salt_100g": 0.1,
                    },
                }
            ]
        }

        stats = run_food_etl()
        self.assertEqual(stats["updated"], 1)

        food.refresh_from_db()
        self.assertEqual(food.kcal_per_100, Decimal("115.00"))
        self.assertEqual(food.updated_in_version.version, 2)
        self.assertFalse(food.updated_in_version.is_published)

        update_log = Changelog.objects.filter(food=food).exclude(old_values={}).get()
        self.assertEqual(update_log.old_values["kcal_per_100"], "100.00")
        self.assertEqual(update_log.new_values["kcal_per_100"], "115.00")

class FoodAdminAndCommandTests(TestCase):
    """Testy ručního spuštění importu z Django Adminu (UC14) i přes CLI (E7)."""

    def setUp(self):
        User = get_user_model()
        self.admin_user = User.objects.create_superuser(
            username="admin", email="admin@example.com", password="password123"
        )

    @patch("foods.services.requests.get")
    def test_admin_run_etl_endpoint_imports_data(self, mock_get):
        """Kliknutí na tlačítko v Django Adminu spustí ETL a přesměruje zpět."""
        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {
            "products": [
                {
                    "code": "8594005556661",
                    "product_name": "Bílý jogurt",
                    "nutriments": {
                        "energy-kcal_100g": 65,
                        "proteins_100g": 4.5,
                        "carbohydrates_100g": 5.0,
                        "fat_100g": 3.0,
                    },
                }
            ]
        }

        self.client.force_login(self.admin_user)
        url = reverse("admin:foods_food_run_etl")
        response = self.client.post(url, follow=True)

        self.assertEqual(response.status_code, 200)
        self.assertTrue(Food.objects.filter(ean="8594005556661").exists())

    @patch("foods.services.requests.get")
    def test_import_foods_management_command_success(self, mock_get):
        """Management příkaz stáhne data a vypíše souhrn."""
        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"products": []}

        out = StringIO()
        call_command("import_foods", stdout=out)

        self.assertEqual(mock_get.call_count, 1)
        self.assertIn("Import dokončen", out.getvalue())

    @patch("foods.services.requests.get")
    def test_import_foods_management_command_network_error(self, mock_get):
        """Výpadek externího API vyhodí čitelný CommandError."""
        mock_get.side_effect = requests.ConnectionError("API nedostupné")

        with self.assertRaises(CommandError):
            call_command("import_foods")