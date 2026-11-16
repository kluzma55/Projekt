from decimal import Decimal
from io import StringIO
from unittest.mock import patch

import requests
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.urls import reverse

from foods.models import Changelog, DbVersion, Food
from foods.services.etl import normalize_openfoodfacts_item, run_food_etl


# ===========================================================================
# Existing ETL / service tests 
# ===========================================================================

def create_test_food(**kwargs):
    """Legacy helper used by existing tests."""
    defaults = {
        "protein_g": 0,
        "carbs_g": 0,
        "sugars_g": 0,
        "fat_g": 0,
        "saturated_fat_g": 0,
        "fibers_g": 0,
        "salt_g": 0,
    }
    defaults.update(kwargs)
    return Food.objects.create(**defaults)


# ===========================================================================
# ETL pipeline tests 
# ===========================================================================

class FoodEtlPipelineTests(TestCase):
    """Tests for OpenFoodFacts data cleaning and ETL → versioning pipeline."""

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

        minimal_cleaned = normalize_openfoodfacts_item(
            {"code": "8594001234567", "product_name": "Test", "nutriments": {"energy-kcal_100g": 100}}
        )
        self.assertIsNotNone(minimal_cleaned)
        self.assertEqual(minimal_cleaned["kcal_per_100"], Decimal("100.00"))
        self.assertEqual(minimal_cleaned["protein_g"], Decimal("0.00"))

        self.assertIsNone(normalize_openfoodfacts_item({**valid_raw, "code": "ABC-123"}))

        self.assertIsNone(
            normalize_openfoodfacts_item(
                {"code": "8594001234567", "product_name": "Test", "nutriments": {"proteins_100g": 10}}
            )
        )

        bad_nutriments = dict(valid_raw["nutriments"], fat_100g=-5)
        self.assertIsNone(normalize_openfoodfacts_item({**valid_raw, "nutriments": bad_nutriments}))

    @patch("foods.services.etl.requests.get")
    def test_etl_creates_food_and_skips_identical_on_rerun(self, mock_get):
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
        # V1 — no changelog entries expected.
        self.assertEqual(Changelog.objects.count(), 0)

        stats_second = run_food_etl()
        self.assertEqual(stats_second, {"created": 0, "updated": 0, "skipped": 1, "invalid": 1})
        self.assertEqual(Changelog.objects.count(), 0)
    @patch("foods.services.etl.requests.get")
    def test_etl_cross_version_update_creates_new_draft_version(self, mock_get):
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
    """Tests for the admin ETL button and import_foods management command."""

    def setUp(self):
        User = get_user_model()
        self.admin_user = User.objects.create_superuser(
            username="admin", email="admin@example.com", password="password123"
        )

    @patch("foods.services.etl.requests.get")
    def test_admin_run_etl_endpoint_imports_data(self, mock_get):
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

    @patch("foods.services.etl.requests.get")
    def test_import_foods_management_command_success(self, mock_get):
        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"products": []}

        out = StringIO()
        call_command("import_foods", stdout=out)

        self.assertEqual(mock_get.call_count, 1)
        self.assertIn("Import dokončen", out.getvalue())

    @patch("foods.services.etl.requests.get")
    def test_import_foods_management_command_network_error(self, mock_get):
        mock_get.side_effect = requests.ConnectionError("API nedostupné")

        with self.assertRaises(CommandError):
            call_command("import_foods")