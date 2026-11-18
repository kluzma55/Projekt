"""Pure helpers for the offline catalogue export (no Django dependency)."""
import gzip
import json
import os
import shutil
import sqlite3
import tempfile
from pathlib import Path
from decimal import Decimal

TEXT_FIELDS = ('ean', 'name', 'unit', 'image_path')
NUMBER_FIELDS = ('kcal_per_100', 'protein_g', 'carbs_g', 'sugars_g',
                 'fat_g', 'saturated_fat_g', 'fibers_g', 'salt_g')
FOOD_FIELDS = ('id', *TEXT_FIELDS, *NUMBER_FIELDS)
STATE_FIELDS = (*FOOD_FIELDS, 'is_active')


def normalize(field, value):
    if field in NUMBER_FIELDS:
        number = Decimal(str(value))
        if not number.is_finite():
            raise ValueError(f'Invalid nutritional value: {field}={value!r}')
        return float(number)
    if field == 'is_active':
        if isinstance(value, bool):
            return value
        if str(value).lower() in ('true', '1'):
            return True
        if str(value).lower() in ('false', '0'):
            return False
        raise ValueError(f'Invalid is_active: {value!r}')
    return value


def normalize_row(row):
    return {field: normalize(field, row[field]) for field in STATE_FIELDS}


def rewind(states, logs):
    """Undo logs supplied in descending (version, id) order, in place.

    A CREATED log has no values in the existing model: remove the row
    from the historical state. For other actions restore the old values.
    """
    for log in logs:
        food_id = log['food_id']
        action = log['action']
        if action == 'CREATED':
            states.pop(food_id, None)
        elif action in ('UPDATED', 'DELETED'):
            if food_id not in states:
                raise ValueError(f'Missing food {food_id} while restoring history')
            old = log['old_values'] or {}
            if action == 'DELETED' and not old:
                # Food.save() can bypass clean(): a food created and hidden
                # in the same draft has a DELETED log with empty history.
                # Without an earlier creation event it did not exist before.
                if not log.get('has_prior_history', True):
                    states.pop(food_id, None)
                    continue
                raise ValueError(f'DELETION of food {food_id} lacks old_values')
            for field, value in old.items():
                if field in STATE_FIELDS and field != 'id':
                    states[food_id][field] = normalize(field, value)
        else:
            raise ValueError(f'Unknown changelog action: {action}')
    return states


def active_food(row):
    return row is not None and row['is_active']


def public_food(row):
    return {field: row[field] for field in FOOD_FIELDS}


def build_delta(before, after, from_version, to_version):
    changes = []
    for food_id in sorted(before.keys() | after.keys()):
        old, new = before.get(food_id), after.get(food_id)
        was_active, is_active = active_food(old), active_food(new)
        if was_active and not is_active:
            changes.append({'food_id': food_id, 'action': 'DELETED'})
        elif is_active and not was_active:
            changes.append({'food_id': food_id, 'action': 'CREATED',
                            'data': public_food(new)})
        elif was_active and is_active:
            data = {f: new[f] for f in FOOD_FIELDS if f != 'id' and old[f] != new[f]}
            if data:
                changes.append({'food_id': food_id, 'action': 'UPDATED', 'data': data})
    # Apply deletes first, then updates and inserts; order deterministic.
    order = {'DELETED': 0, 'UPDATED': 1, 'CREATED': 2}
    changes.sort(key=lambda c: (order[c['action']], c['food_id']))
    return {'from_version': from_version, 'to_version': to_version, 'changes': changes}


def atomic_write(path, writer):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.export-', dir=path.parent)
    os.close(fd)
    try:
        writer(Path(name))
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return path


def write_delta(payload, output_dir):
    path = Path(output_dir) / 'deltas' / (
        f"delta_{payload['from_version']}_{payload['to_version']}.json")
    def writer(temp):
        with temp.open('w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    return atomic_write(path, writer)


def write_snapshot(rows, version, output_dir):
    """Create a minimal SQLite DB, then gzip it, with atomic publication."""
    path = Path(output_dir) / 'snapshots' / f'snapshot_{version}.db.gz'
    def writer(temp):
        with tempfile.TemporaryDirectory() as directory:
            db_path = Path(directory) / 'snapshot.db'
            db = sqlite3.connect(db_path)
            try:
                columns = ['id INTEGER PRIMARY KEY']
                columns += [f'{f} TEXT NOT NULL' for f in TEXT_FIELDS]
                columns += [f'{f} REAL NOT NULL' for f in NUMBER_FIELDS]
                db.execute('CREATE TABLE food (' + ', '.join(columns) + ')')
                db.execute('CREATE TABLE db_version (version INTEGER PRIMARY KEY)')
                db.execute('INSERT INTO db_version (version) VALUES (?)', (version,))
                db.execute(f'PRAGMA user_version = {int(version)}')
                marks = ', '.join('?' for _ in FOOD_FIELDS)
                db.executemany(
                    f"INSERT INTO food ({', '.join(FOOD_FIELDS)}) VALUES ({marks})",
                    (tuple(row[f] for f in FOOD_FIELDS) for row in rows if active_food(row)),
                )
                db.execute('CREATE INDEX food_ean_idx ON food(ean)')
                db.commit()
                if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                    raise ValueError('SQLite integrity check failed')
            finally:
                db.close()
            with db_path.open('rb') as source, temp.open('wb') as target:
                with gzip.GzipFile(filename='', fileobj=target, mode='wb', mtime=0) as zipped:
                    shutil.copyfileobj(source, zipped)
    return atomic_write(path, writer)
