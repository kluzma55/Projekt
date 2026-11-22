import gzip
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from foods.services.sync_core import (NUMBER_FIELDS, normalize_row, rewind, build_delta,
                             write_delta, write_snapshot)


def food(id, name, kcal, active=True, unit='g'):
    row = dict.fromkeys(NUMBER_FIELDS, '0.00')
    row.update(id=id, ean=str(id).zfill(13), name=name, unit=unit, image_path='',
               kcal_per_100=str(kcal), is_active=active)
    return normalize_row(row)


def log(id, action, old=None):
    return {'food_id': id, 'action': action, 'old_values': old or {}}


class ExportTests(unittest.TestCase):
    def test_historical_delta_and_draft(self):
        current = {1: food(1, 'Jablko', 52, False),
                   2: food(2, 'Rohlík', 400), 3: food(3, 'Banán', 95),
                   4: food(4, 'Hruška', 57)}
        # Undo draft 5 and version 4 to get version 3.
        rewind(current, [log(4, 'CREATED'), log(2, 'UPDATED', {'kcal_per_100': '300'}),
                         log(3, 'UPDATED', {'kcal_per_100': '89'})])
        after = {key: val.copy() for key, val in current.items()}
        # Undo v3 deletion and v2 creation/update to get v1.
        rewind(current, [log(1, 'DELETED', {'is_active': 'True'}),
                         log(3, 'CREATED'), log(2, 'UPDATED', {'kcal_per_100': '150'})])
        delta = build_delta(current, after, 1, 3)
        self.assertEqual([c['action'] for c in delta['changes']],
                         ['DELETED', 'UPDATED', 'CREATED'])
        self.assertEqual(delta['changes'][1]['data'], {'kcal_per_100': 300.0})
        self.assertEqual(delta['changes'][2]['data']['kcal_per_100'], 89.0)
        self.assertEqual(delta['changes'][2]['data']['ean'], '0000000000003')
        self.assertNotIn('old_values', json.dumps(delta))
        with tempfile.TemporaryDirectory() as d:
            p = write_delta(delta, d)
            self.assertEqual(json.loads(p.read_text(encoding='utf-8')), delta)

    def test_net_zero_and_reactivation(self):
        a = {1: food(1, 'A', 10), 2: food(2, 'B', 20, False)}
        b = {1: food(1, 'A', 10), 2: food(2, 'B', 20)}
        self.assertEqual(build_delta(a, b, 1, 3)['changes'][0]['action'], 'CREATED')
        self.assertEqual(build_delta(a, a, 1, 1)['changes'], [])
        self.assertEqual(build_delta({}, {3: food(3, 'C', 1, False)}, 1, 3)['changes'], [])

    def test_snapshot(self):
        rows = [food(1, 'Jablko', 52), food(2, 'Rohlík', 300, False), food(3, 'Mléko', 42, unit='ml')]
        with tempfile.TemporaryDirectory() as d:
            p = write_snapshot(rows, 7, d)
            self.assertEqual(p.name, 'snapshot_7.db.gz')
            db_path = Path(d) / 'check.db'
            db_path.write_bytes(gzip.decompress(p.read_bytes()))
            db = sqlite3.connect(db_path)
            try:
                self.assertEqual(db.execute('SELECT id, name FROM food').fetchall(),
                                 [(1, 'Jablko'), (3, 'Mléko')])
                self.assertEqual(db.execute('SELECT unit FROM food WHERE id=1').fetchone(), ('g',))
                self.assertEqual(db.execute('SELECT unit FROM food WHERE id=3').fetchone(), ('ml',))
                self.assertEqual(db.execute('SELECT version FROM db_version').fetchone(), (7,))
                self.assertEqual(db.execute('PRAGMA user_version').fetchone(), (7,))
                self.assertEqual(db.execute('PRAGMA integrity_check').fetchone(), ('ok',))
                self.assertEqual({r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}, {'food', 'db_version'})
            finally:
                db.close()

    def test_empty_deletion_without_history(self):
        states = {1: food(1, 'A', 1, False)}
        rewind(states, [dict(log(1, 'DELETED'), has_prior_history=False)])
        self.assertEqual(states, {})


if __name__ == '__main__':
    unittest.main()
