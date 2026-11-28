from decimal import Decimal
import gzip
from io import BytesIO, StringIO
import json
import os
import tempfile
from unittest.mock import MagicMock, patch

import requests
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import IntegrityError
from django.test import TestCase
from django.urls import reverse

from foods.models import Changelog, DbVersion, Food
from foods.services.etl import (
    is_czech_product,
    normalize_openfoodfacts_item,
    run_dump_food_etl,
    run_food_etl,
    verify_food_database_quality,
)


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
        normalized_with_bad_opt = normalize_openfoodfacts_item({**valid_raw, "nutriments": bad_nutriments})
        self.assertIsNotNone(normalized_with_bad_opt)
        self.assertEqual(normalized_with_bad_opt["fat_g"], Decimal("0.00"))

    @patch("foods.services.etl.requests.get")
    def test_etl_creates_food_and_skips_identical_on_rerun(self, mock_get):
        mock_response = mock_get.return_value
        mock_response.raise_for_status.return_value = None
        page_1_payload = {
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
        mock_response.json.side_effect = [
            page_1_payload,
            {"products": []},  # end of 1st run
            page_1_payload,
            {"products": []},  # end of 2nd run
        ]

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
def _build_gz_payload(records: list[dict | str]) -> bytes:
    """Creates in-memory compressed .jsonl.gz content from a list of records."""
    buf = BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        for item in records:
            line = item if isinstance(item, str) else json.dumps(item, ensure_ascii=False)
            gz.write((line + "\n").encode("utf-8"))
    return buf.getvalue()


class FoodDumpEtlAndQualityTests(TestCase):
    """Tests for bulk .jsonl.gz dump import, auto-download, and DB quality checks."""

    def setUp(self):
        self.cz_by_tag = {
            "code": "4008400404127",
            "product_name": "Čokoláda mléčná",
            "countries_tags": ["en:czech-republic"],
            "nutriments": {
                "energy-kcal_100g": 540,
                "proteins_100g": 7.5,
                "carbohydrates_100g": 56.0,
                "fat_100g": 31.0,
            },
        }
        self.cz_by_ean = {
            "code": "8594001234567",
            "product_name": "Tvaroh polotučný",
            "countries_tags": [],
            "nutriments": {"energy-kcal_100g": 105},
        }
        self.cz_by_cs_name = {
            "code": "12345678",
            "product_name_cs": "Rohlík bílý",
            "countries_tags": ["en:slovakia"],
            "nutriments": {"energy-kcal_100g": 290},
        }
        self.foreign_product = {
            "code": "3017620422003",
            "product_name": "Nutella",
            "countries_tags": ["en:france"],
            "nutriments": {"energy-kcal_100g": 539},
        }
        self.invalid_cz_product = {
            "code": "8590000000001",
            "product_name": "Produkt bez kalorií",
            "countries_tags": ["en:czechia"],
            "nutriments": {},
        }

    def test_is_czech_product_filters_correctly(self):
        self.assertTrue(is_czech_product(self.cz_by_tag))
        self.assertTrue(is_czech_product(self.cz_by_ean))
        self.assertTrue(is_czech_product(self.cz_by_cs_name))
        self.assertFalse(is_czech_product(self.foreign_product))

    def test_run_dump_food_etl_from_local_file_and_idempotency(self):
        payload = _build_gz_payload([
            self.cz_by_tag,
            self.cz_by_ean,
            self.cz_by_cs_name,
            self.foreign_product,
            self.invalid_cz_product,
            "{nevalidni-json-radek",
        ])

        fd, temp_path = tempfile.mkstemp(suffix=".jsonl.gz")
        os.close(fd)
        try:
            with open(temp_path, "wb") as f:
                f.write(payload)

            stats_first = run_dump_food_etl(file_path=temp_path)
            self.assertEqual(stats_first["created"], 3)
            self.assertEqual(stats_first["updated"], 0)
            self.assertEqual(stats_first["invalid"], 1)
            self.assertEqual(Food.objects.filter(is_active=True).count(), 3)

            stats_second = run_dump_food_etl(file_path=temp_path)
            self.assertEqual(stats_second["created"], 0)
            self.assertEqual(stats_second["skipped"], 3)
            self.assertEqual(Food.objects.filter(is_active=True).count(), 3)
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    @patch("foods.services.etl.requests.get")
    def test_run_dump_food_etl_auto_download_and_cleanup(self, mock_get):
        payload = _build_gz_payload([self.cz_by_tag, self.cz_by_ean])

        mock_response = MagicMock()
        mock_response.headers = {"Content-Length": str(len(payload))}
        mock_response.iter_content.return_value = [payload]
        mock_response.__enter__.return_value = mock_response
        mock_response.__exit__.return_value = False
        mock_get.return_value = mock_response

        created_temp_paths = []
        original_mkstemp = tempfile.mkstemp

        def track_mkstemp(*args, **kwargs):
            fd, path = original_mkstemp(*args, **kwargs)
            created_temp_paths.append(path)
            return fd, path

        with patch("foods.services.etl.tempfile.mkstemp", side_effect=track_mkstemp):
            stats = run_dump_food_etl(file_path=None, keep_file=False)

        self.assertEqual(stats["created"], 2)
        self.assertEqual(len(created_temp_paths), 1)
        self.assertFalse(os.path.exists(created_temp_paths[0]))

    def test_verify_food_database_quality_detects_clean_and_corrupted_data(self):
        create_test_food(
            ean="8591111111111",
            name="Čistá položka",
            kcal_per_100=Decimal("120.00"),
            is_active=True,
        )
        clean_report = verify_food_database_quality()
        self.assertEqual(clean_report["total_active"], 1)
        self.assertEqual(clean_report["duplicate_eans"], 0)
        self.assertEqual(clean_report["invalid_eans"], 0)
        self.assertEqual(clean_report["missing_required_fields"], 0)

        # The database itself prevents inserting a duplicate EAN
        with self.assertRaises(IntegrityError):
            create_test_food(
                ean="8591111111111",
                name="Duplicitní položka",
                kcal_per_100=Decimal("150.00"),
                is_active=True,
            )

        # Inserting a record with an invalid EAN and empty name
        create_test_food(
            ean="123ABC",
            name="",
            kcal_per_100=Decimal("50.00"),
            is_active=True,
        )

        corrupted_report = verify_food_database_quality()
        self.assertEqual(corrupted_report["total_active"], 2)
        self.assertEqual(corrupted_report["duplicate_eans"], 0)
        self.assertEqual(corrupted_report["invalid_eans"], 1)
        self.assertEqual(corrupted_report["missing_required_fields"], 1)

    @patch("foods.services.etl.requests.get")
    def test_import_foods_command_with_dump_flag(self, mock_get):
        payload = _build_gz_payload([self.cz_by_tag, self.foreign_product])

        mock_response = MagicMock()
        mock_response.headers = {"Content-Length": str(len(payload))}
        mock_response.iter_content.return_value = [payload]
        mock_response.__enter__.return_value = mock_response
        mock_response.__exit__.return_value = False
        mock_get.return_value = mock_response

        out = StringIO()
        call_command("import_foods", "--dump", stdout=out)
        output = out.getvalue()

        self.assertIn("Import dokončen | vytvořeno: 1", output)
        self.assertIn("Kontrola kvality DB | aktivních položek: 1, duplicitní EAN: 0", output)