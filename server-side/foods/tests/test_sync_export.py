"""Integration test: run with python manage.py test foods.test_sync_export."""
import gzip
import json
import sqlite3
from pathlib import Path
from tempfile import TemporaryDirectory
from contextlib import closing

from django.core.management import call_command
from django.test import TestCase

from ..models import DbVersion, Food
from ..services.sync_core import NUMBER_FIELDS


class SyncExportIntegrationTest(TestCase):
    def make_food(self, name, ean, kcal):
        values = dict.fromkeys(NUMBER_FIELDS, 0)
        values['kcal_per_100'] = kcal
        return Food.objects.create(name=name, ean=ean, **values)

    def publish(self):
        version = DbVersion.objects.get(is_published=False)
        version.is_published = True
        version.save(update_fields=['is_published'])
        return version.version

    def test_commands_with_real_models(self):
        apple = self.make_food('Jablko', '0000000000001', 52)
        roll = self.make_food('Rohlík', '0000000000002', 150)
        v1 = self.publish()
        roll.kcal_per_100 = 300
        roll.save()
        banana = self.make_food('Banán', '0000000000003', 89)
        v2 = self.publish()
        apple.is_active = False
        apple.save()
        banana.kcal_per_100 = 95
        banana.save()
        v3 = self.publish()
        # An unpublished edit must not leak into snapshot or delta.
        roll.kcal_per_100 = 400
        roll.save()
        self.make_food('Hruška', '0000000000004', 57)
        with TemporaryDirectory() as temp:
            out = Path(temp)
            call_command('export_sync', 'delta', '--from-version', str(v1),
                         '--to-version', str(v2), '--output-dir', temp)
            data = json.loads((out/'deltas'/f'delta_{v1}_{v2}.json').read_text(encoding='utf8'))
            by_id = {change['food_id']: change for change in data['changes']}
            self.assertEqual(by_id[roll.pk]['data']['kcal_per_100'], 300)
            self.assertEqual(by_id[banana.pk]['data']['kcal_per_100'], 89)
            self.assertNotIn(apple.pk, by_id)
            call_command('export_sync', 'delta', '--from-version', str(v1), '--output-dir', temp)
            data = json.loads((out/'deltas'/f'delta_{v1}_{v3}.json').read_text(encoding='utf8'))
            self.assertEqual(data['changes'][0], {'food_id': apple.pk, 'action': 'DELETED'})
            call_command('export_sync', 'snapshot', '--output-dir', temp)
            db = out/'check.db'
            db.write_bytes(gzip.decompress((out/'snapshots'/f'snapshot_{v3}.db.gz').read_bytes()))
            with closing(sqlite3.connect(db)) as conn:
                self.assertEqual(conn.execute('SELECT name, kcal_per_100 FROM food ORDER BY id').fetchall(),
                                 [('Rohlík', 300.0), ('Banán', 95.0)])
                self.assertEqual(conn.execute('SELECT version FROM db_version').fetchone(), (v3,))
