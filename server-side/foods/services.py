from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import time
import requests
import gzip
import json
from django.conf import settings
from django.db import transaction
from .models import Food

NUTRITION_FIELDS = (
    "kcal_per_100",
    "protein_g",
    "carbs_g",
    "sugars_g",
    "fat_g",
    "saturated_fat_g",
    "fibers_g",
    "salt_g",
)

TRACKED_FIELDS = ("name", "ean", *NUTRITION_FIELDS)

DEFAULT_OFF_SEARCH_URL = "https://cz.openfoodfacts.org/api/v2/search"


def _parse_decimal(value, *, max_val: Decimal, default: Decimal | None = None) -> Decimal | None:
    if value is None or value == "":
        return default
    try:
        dec = Decimal(str(value).replace(",", ".").strip()).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
    except (InvalidOperation, ValueError):
        return default

    if dec < Decimal("0.00") or dec > max_val:
        return None
    return dec


def _parse_optional_nutrient(value) -> Decimal:
    """Vrátí hodnotu živiny v g/100g, nebo 0.00 pokud chybí či je mimo rozsah."""
    parsed = _parse_decimal(value, max_val=Decimal("100.00"), default=Decimal("0.00"))
    return parsed if parsed is not None else Decimal("0.00")


def normalize_openfoodfacts_item(raw: dict) -> dict | None:
    """
    Vyčistí jeden záznam z OpenFoodFacts.
    Povinné: validní EAN (8/13 číslic), název a kalorie (kcal_per_100).
    Ostatní atributy jsou nepovinné (výchozí 0.00 / prázdný řetězec).
    """
    ean = str(raw.get("code") or raw.get("ean") or "").strip()
    name = str(raw.get("product_name_cs") or raw.get("product_name") or "").strip()

    if not ean.isdigit() or len(ean) not in (8, 13) or not name:
        return None

    nutriments = raw.get("nutriments") or {}

    # Jediná povinná nutriční hodnota jsou kalorie
    kcal = _parse_decimal(nutriments.get("energy-kcal_100g"), max_val=Decimal("9999.99"))
    if kcal is None:
        return None

    # Nepovinné atributy (uloží se, pokud existují, jinak 0.00)
    sugars = _parse_decimal(nutriments.get("sugars_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    protein = _parse_decimal(nutriments.get("proteins_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    carbs = _parse_decimal(nutriments.get("carbohydrates_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    fat = _parse_decimal(nutriments.get("fat_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    saturated_fat = _parse_decimal(nutriments.get("saturated-fat_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    fibers = _parse_decimal(nutriments.get("fiber_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))
    salt = _parse_decimal(nutriments.get("salt_100g"), max_val=Decimal("100.00"), default=Decimal("0.00"))

    if None in (protein, carbs, fat, sugars, saturated_fat, fibers, salt):
        return None

    image_url = str(raw.get("image_front_small_url") or raw.get("image_url") or "").strip()

    return {
        "ean": ean,
        "name": name[:255],
        "kcal_per_100": kcal,
        "protein_g": protein,
        "carbs_g": carbs,
        "sugars_g": sugars,
        "fat_g": fat,
        "saturated_fat_g": saturated_fat,
        "fibers_g": fibers,
        "salt_g": salt,
        "image_path": image_url[:255],
    }


def fetch_products_from_api(page: int = 1, page_size: int = 100) -> list[dict]:
    """Stáhne jednu stránku dat z OpenFoodFacts API v2."""
    source_url = getattr(settings, "FOOD_ETL_SOURCE_URL", DEFAULT_OFF_SEARCH_URL)
    params = {
        "page": page,
        "page_size": page_size,
        "sort_by": "last_modified_t",
        "fields": "code,product_name,product_name_cs,nutriments,image_front_small_url,image_url",
    }
    headers = {
        "User-Agent": "KalorickaKalkulacka-StudentProject/1.0 (contact@example.com)",
        "Accept": "application/json",
    }

    last_exception = None
    for attempt in range(1, 6):
        try:
            response = requests.get(source_url, params=params, timeout=(5, 30), headers=headers)
            if response.status_code in (429, 502, 503, 504) and attempt < 5:
                time.sleep(3 * attempt)
                continue
            response.raise_for_status()
            payload = response.json()

            if isinstance(payload, list):
                return payload
            if isinstance(payload, dict) and isinstance(payload.get("products"), list):
                return payload["products"]
            raise ValueError("Neočekávaný formát odpovědi z externího API.")
        except requests.RequestException as exc:
            last_exception = exc
            if attempt < 5:
                time.sleep(3 * attempt)
                continue
            raise

    raise last_exception


def _process_batch(raw_products: list[dict], existing_by_ean: dict[str, Food], stats: dict[str, int]) -> None:
    """Očistí a uloží jednu dávku produktů v rámci jedné databázové transakce."""
    with transaction.atomic():
        for raw in raw_products:
            cleaned = normalize_openfoodfacts_item(raw)
            if cleaned is None:
                stats["invalid"] += 1
                continue

            ean = cleaned["ean"]
            existing = existing_by_ean.get(ean)

            if existing is None:
                food = Food(**cleaned, is_active=True)
                food.save()
                existing_by_ean[ean] = food
                stats["created"] += 1
            else:
                has_changes = any(
                    getattr(existing, field) != cleaned[field]
                    for field in TRACKED_FIELDS
                )
                for field in TRACKED_FIELDS:
                    setattr(existing, field, cleaned[field])

                if not existing.image_path and cleaned["image_path"]:
                    existing.image_path = cleaned["image_path"]
                    has_changes = True

                if has_changes:
                    existing.save()
                    stats["updated"] += 1
                else:
                    stats["skipped"] += 1


def run_food_etl(max_pages: int = 10) -> dict[str, int]:
    """Stáhne všechny nově přidané a upravené potraviny od poslední synchronizace."""
    stats = {"created": 0, "updated": 0, "skipped": 0, "invalid": 0}
    existing_by_ean = {
        food.ean: food
        for food in Food.objects.filter(is_active=True).exclude(ean="")
    }

    for page in range(1, max_pages + 1):
        raw_products = fetch_products_from_api(page=page, page_size=100)
        if not raw_products:
            break

        prev_changes = stats["created"] + stats["updated"]
        _process_batch(raw_products, existing_by_ean, stats)
        new_changes = (stats["created"] + stats["updated"]) - prev_changes

        # Jakmile stránka nepřinesla žádnou novou ani upravenou položku,
        # všechny další stránky jsou ještě starší -> končíme.
        if new_changes == 0:
            break

        if page < max_pages:
            time.sleep(6.5)

    return stats


def run_full_food_etl(
    start_page: int = 1,
    max_pages: int | None = None,
    on_progress=None,
) -> dict[str, int]:
    """Kompletní prvotní import všech validních českých výrobků přes všechny stránky API."""
    stats = {"created": 0, "updated": 0, "skipped": 0, "invalid": 0}
    existing_by_ean = {
        food.ean: food
        for food in Food.objects.filter(is_active=True).exclude(ean="")
    }

    page = start_page
    processed_pages = 0
    consecutive_errors = 0

    while True:
        if max_pages is not None and processed_pages >= max_pages:
            break

        try:
            raw_products = fetch_products_from_api(page=page, page_size=100)
            consecutive_errors = 0
        except requests.RequestException:
            consecutive_errors += 1
            if consecutive_errors >= 5:
                raise
            time.sleep(60)
            continue

        if not raw_products:
            break

        _process_batch(raw_products, existing_by_ean, stats)
        processed_pages += 1

        if on_progress:
            on_progress(page, stats)

        page += 1
        time.sleep(7.0)

    return stats

CZECH_COUNTRY_TAGS = {"en:czech-republic", "en:czechia"}


def is_czech_product(raw: dict) -> bool:
    """Vrátí True, pokud se produkt prodává v ČR nebo má český název/EAN."""
    countries = raw.get("countries_tags") or []
    if any(tag in CZECH_COUNTRY_TAGS for tag in countries):
        return True

    if raw.get("product_name_cs"):
        return True

    code = str(raw.get("code") or "").strip()
    return code.startswith("859")


def run_dump_food_etl(file_path: str, on_progress=None) -> dict[str, int]:
    """Načte lokální .jsonl.gz export z OpenFoodFacts a uloží validní české potraviny."""
    stats = {"created": 0, "updated": 0, "skipped": 0, "invalid": 0}
    existing_by_ean = {
        food.ean: food
        for food in Food.objects.filter(is_active=True).exclude(ean="")
    }

    batch = []
    batch_num = 0

    with gzip.open(file_path, "rt", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            try:
                raw = json.loads(line)
            except json.JSONDecodeError:
                continue

            if not is_czech_product(raw):
                continue

            batch.append(raw)
            if len(batch) >= 500:
                _process_batch(batch, existing_by_ean, stats)
                batch.clear()
                batch_num += 1
                if on_progress:
                    on_progress(batch_num, stats)

    if batch:
        _process_batch(batch, existing_by_ean, stats)
        batch_num += 1
        if on_progress:
            on_progress(batch_num, stats)

    return stats