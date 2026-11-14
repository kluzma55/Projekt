# Export synchronizačních balíčků pro Cloudflare R2

Doplněk pro existující Django projekt `server-side`, podle veřejně dostupného `foods/models.py` z větve master repozitáře kluzma55/Projekt. Nejde o celý projekt ani o hotový commit.

## Instalace

Překopíruj `foods/sync_core.py`, `foods/sync_export.py`, `foods/test_sync_export.py` a `foods/management/commands/export_sync.py` do stejné struktury uvnitř `server-side`. Pokud složky management a commands ještě neexistují, vytvoř je včetně prázdných `__init__.py`. Existující `__init__.py` nepřepisuj. Složka `tests_export` je volitelná pro čisté testy bez Django.

Přidej `/exports/` do `.gitignore` v `server-side` (nebo `/server-side/exports/` do kořenového `.gitignore`). Nastavení `SYNC_EXPORT_DIR` je volitelné, výchozí je `BASE_DIR / 'exports'`. Žádné nové balíčky nejsou potřeba, SQLite i gzip jsou standardní knihovny Pythonu. Není potřeba migrace pro samotný export.

## Úpravy existujícího modelu

V modelu `Food` byly provedeny následující úpravy:

- Doplnění sledování změn pole `image_path`.
- Oddělené porovnávání číselných a textových hodnot.
- Jednotné ukládání desetinných hodnot se dvěma desetinnými místy.
- Oprava odstraňování prázdných záznamů changelogu při vrácení změn do původního stavu.

Byly také doplněny povinné nutriční hodnoty v testovacích datech původních testů projektu.

Tyto změny nevyžadují databázovou migraci.

Pro správné fungování historických exportů je nutné zachovávat historii změn. Potraviny se mají odstraňovat pomocí soft-delete, nikoli fyzickým smazáním z databáze.

## Použití

Ve složce obsahující `manage.py`, s aktivním venv a nastavenou PostgreSQL databází:

```bat
python manage.py check
python manage.py test foods.test_sync_export
python manage.py export_sync delta --from-version 1 --to-version 3
python manage.py export_sync delta --from-version 1
python manage.py export_sync snapshot
```

Čísla 1 a 3 nahraď existujícími publikovanými verzemi. Pokud zatím není publikovaná žádná verze, publikuj první verzi v Django adminu (`DbVersion`, `is_published=True`). Pokud neuvedeš cílovou verzi, vybere se nejnovější publikovaná verze. Stejná počáteční a cílová verze vytvoří prázdnou deltu. Neexistující či nepublikovaná verze je odmítnuta. Změny z draftu jsou z exportů odvinuty. Export je spuštěn příkazem, nikoli automaticky při publikaci; příkaz při spuštění sám vytvoří adresáře a soubory. Upload není součástí.

Výstupy: `exports/deltas/delta_1_3.json` a `exports/snapshots/snapshot_3.db.gz`.

## Smlouva dat (návrh, potvrdit s mobilem)

JSON: `from_version`, `to_version`, `changes`. Změny jsou seřazeny podle akce DELETED, UPDATED, CREATED a ID. CREATED má kompletní objekt včetně id, UPDATED pouze skutečně změněná veřejná pole, DELETED pouze food_id a action. Reaktivace je CREATED, protože v mobilu záznam již není. Pro dvojici verzí se exportuje výsledný rozdíl, nikoli každý mezikrok. Nutriční hodnoty jsou čísla; EAN je řetězec. SQLite: tabulky `food` (id, ean, name, image_path, osm nutričních polí), `db_version` (version), také PRAGMA user_version. Serverové is_active a updated_in_version se neexportují. Mobilní schéma, formát a aplikaci delta balíčku musí potvrdit tým; např. klient s unikátním EAN musí řešit kolize při změnách EAN v transakci.

## Testy a omezení

Implementace byla otestována v prostředí Windows s Pythonem 3.14, Django 5.2.19 a PostgreSQL.

**Výsledky testování:**

- 7 úspěšných testů Django projektu, včetně integračního testu exportního modulu.
- 4 úspěšné samostatné testy exportní logiky.
- Ruční ověření exportu delty mezi verzemi 1 a 2.
- Ruční ověření komprimovaného SQLite snapshotu verze 2.
- Úspěšná kontrola integrity SQLite databáze.

Spuštění testů:

```
python manage.py test
python -m unittest discover -s tests_export -v
```

Bylo ověřeno generování historických delt, vytváření, aktualizace a odstraňování potravin, vyloučení nepublikovaných změn, reaktivace potravin, gzip komprese a export pouze aktivních položek.

**Omezení:**

- Historické exporty vyžadují kompletní historii změn v changelogu.
- Fyzické odstranění potraviny může způsobit ztrátu její historie.
- Export je spouštěn pomocí Django management příkazu. Výstupní soubory se ukládají automaticky.
- Export je vhodné spouštět po dokončení publikace verze, bez souběžných neatomických změn katalogu.
- Snapshot načítá katalog do paměti; u velmi rozsáhlých katalogů může být vhodná dávková optimalizace.
- Formát JSON a SQLite databáze je nutné koordinovat s implementací mobilní aplikace.
- Samotný upload na Cloudflare R2 není součástí této implementace.