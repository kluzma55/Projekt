from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import time
import requests
import gzip
import json
import os
import tempfile
from django.db import transaction
from django.db.models import Count, Q
from django.conf import settings
from django.db import transaction
from foods.models import Food

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
DEFAULT_OFF_DUMP_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"


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
    Povinné: validní EAN (8/13 číslic), název a energetická hodnota (kcal nebo přepočet z kJ).
    Ostatní atributy jsou nepovinné (výchozí 0.00 / prázdný řetězec).
    """
    ean = str(raw.get("code") or raw.get("ean") or "").strip()
    if len(ean) == 14 and ean.startswith("0"):
        ean = ean[1:]

    name = str(
        raw.get("product_name_cs")
        or raw.get("product_name")
        or raw.get("product_name_sk")
        or raw.get("product_name_en")
        or raw.get("generic_name_cs")
        or ""
    ).strip()

    if not ean.isdigit() or len(ean) not in (8, 13) or not name:
        return None

    nutriments = raw.get("nutriments") or {}

    # 1. Zkusíme přímo kcal
    kcal = _parse_decimal(nutriments.get("energy-kcal_100g"), max_val=Decimal("9999.99"))

    # 2. Fallback: přepočet z kJ (velmi časté u českých/EU výrobků v OFF)
    if kcal is None:
        energy_unit = str(nutriments.get("energy_unit") or "").lower()
        if energy_unit == "kcal" and nutriments.get("energy_100g") is not None:
            kcal = _parse_decimal(nutriments.get("energy_100g"), max_val=Decimal("9999.99"))
        else:
            kj_raw = nutriments.get("energy-kj_100g")
            if kj_raw is None:
                kj_raw = nutriments.get("energy_100g")
            kj = _parse_decimal(kj_raw, max_val=Decimal("41840.00"))
            if kj is not None:
                kcal = (kj / Decimal("4.184")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    if kcal is None:
        return None

    # Nepovinné atributy (uloží se, pokud jsou v rozumném rozsahu, jinak 0.00)
    sugars = _parse_optional_nutrient(nutriments.get("sugars_100g"))
    protein = _parse_optional_nutrient(nutriments.get("proteins_100g"))
    carbs = _parse_optional_nutrient(nutriments.get("carbohydrates_100g"))
    fat = _parse_optional_nutrient(nutriments.get("fat_100g"))
    saturated_fat = _parse_optional_nutrient(nutriments.get("saturated-fat_100g"))
    fibers = _parse_optional_nutrient(nutriments.get("fiber_100g"))
    salt = _parse_optional_nutrient(nutriments.get("salt_100g"))

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


def fetch_products_from_api(page: int = 1, page_size: int = 100, max_retries: int = 3) -> list[dict]:
    """Stáhne jednu stránku dat z OpenFoodFacts API v2."""
    source_url = getattr(settings, "FOOD_ETL_SOURCE_URL", DEFAULT_OFF_SEARCH_URL)
    params = {
        "page": page,
        "page_size": page_size,
        "sort_by": "last_modified_t",
        "fields": "code,product_name,product_name_cs,product_name_sk,product_name_en,nutriments,image_front_small_url,image_url",
    }
    headers = {
        "User-Agent": "KalorickaKalkulacka-StudentProject/1.0 (contact: lukas.zvonicek.s01@osu.cz)",
        "Accept": "application/json",
    }

    last_exception = None
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(source_url, params=params, timeout=(5, 12), headers=headers)
            if response.status_code in (429, 502, 503, 504) and attempt < max_retries:
                time.sleep(1.5 * attempt)
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
            if attempt < max_retries:
                time.sleep(1.5 * attempt)
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


def run_food_etl(max_pages: int = 3, page_delay: float = 1.5) -> dict[str, int]:
    """
    Stáhne nejnověji přidané a upravené potraviny z OFF API (delta sync).
    Výchozí limit 3 stránky (300 položek) zajišťuje rychlý běh bez HTTP timeoutu v adminu.
    """
    stats = {"created": 0, "updated": 0, "skipped": 0, "invalid": 0}
    existing_by_ean = {
        food.ean: food
        for food in Food.objects.filter(is_active=True).exclude(ean="")
    }

    for page in range(1, max_pages + 1):
        try:
            raw_products = fetch_products_from_api(page=page, page_size=100)
        except requests.RequestException:
            # Pokud už proběhla alespoň 1. stránka a OFF API dočasně vrátí 503,
            # uložená data z předchozích stránek zachováme a skončíme bez pádu.
            if page > 1:
                break
            raise

        if not raw_products:
            break

        prev_changes = stats["created"] + stats["updated"]
        _process_batch(raw_products, existing_by_ean, stats)
        new_changes = (stats["created"] + stats["updated"]) - prev_changes

        if new_changes == 0:
            break

        if page < max_pages and page_delay > 0:
            time.sleep(page_delay)

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


def download_off_dump(dest_path: str, url: str = DEFAULT_OFF_DUMP_URL, on_download_progress=None) -> str:
    """Stáhne aktuální hromadný .jsonl.gz export z Open Food Facts na disk."""
    headers = {
        "User-Agent": "KalorickaKalkulacka-StudentProject/1.0 (contact@example.com)",
    }
    with requests.get(url, stream=True, timeout=(10, 60), headers=headers) as response:
        response.raise_for_status()
        total_bytes = int(response.headers.get("Content-Length", 0))
        downloaded = 0
        last_reported_mb = 0

        with open(dest_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    current_mb = downloaded // (100 * 1024 * 1024)
                    if on_download_progress and current_mb > last_reported_mb:
                        last_reported_mb = current_mb
                        on_download_progress(downloaded, total_bytes)
    return dest_path


def run_dump_food_etl(
    file_path: str | None = None,
    keep_file: bool = False,
    on_progress=None,
    on_download_progress=None,
) -> dict[str, int]:
    """
    Načte lokální nebo automaticky stažený .jsonl.gz export z OpenFoodFacts
    a uloží validní české potraviny do databáze.
    """
    temp_file_created = False
    if not file_path:
        fd, temp_path = tempfile.mkstemp(prefix="off_dump_", suffix=".jsonl.gz")
        os.close(fd)
        file_path = download_off_dump(temp_path, on_download_progress=on_download_progress)
        temp_file_created = True

    stats = {"created": 0, "updated": 0, "skipped": 0, "invalid": 0}
    existing_by_ean = {
        food.ean: food
        for food in Food.objects.filter(is_active=True).exclude(ean="")
    }

    batch = []
    batch_num = 0

    try:
        with gzip.open(file_path, "rt", encoding="utf-8") as f:
            for line in f:
                # Rychlé textové předfiltrování (přeskočí ~99 % ne-českých řádků bez parsování JSONu)
                if '"en:czech' not in line and '"product_name_cs"' not in line and '859' not in line:
                    continue

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
    finally:
        if temp_file_created and not keep_file and os.path.exists(file_path):
            os.remove(file_path)

    return stats


def verify_food_database_quality() -> dict[str, int]:
    """Zkontroluje integritu dat v databázi (duplicity EAN, chybějící povinná pole)."""
    active = Food.objects.filter(is_active=True)
    duplicate_eans = (
        active.exclude(ean="")
        .values("ean")
        .annotate(c=Count("id"))
        .filter(c__gt=1)
        .count()
    )
    bad_ean_count = sum(
        1 for ean in active.values_list("ean", flat=True)
        if not ean or not ean.isdigit() or len(ean) not in (8, 13)
    )
    missing_required = active.filter(
        Q(name__isnull=True) | Q(name="") |
        Q(kcal_per_100__isnull=True) | Q(kcal_per_100__lt=0) | Q(kcal_per_100__gt=9999.99)
    ).count()

    return {
        "total_active": active.count(),
        "duplicate_eans": duplicate_eans,
        "invalid_eans": bad_ean_count,
        "missing_required_fields": missing_required,
    }