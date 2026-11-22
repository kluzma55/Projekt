# Generated manually — adds created_in_version FK to Food, updates the unique_active_ean
# constraint to allow blank EANs, adds unique_draft_version on DbVersion, and adds
# unique_changelog_per_food_version on Changelog.

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('foods', '0007_food_unique_active_ean'),
    ]

    operations = [
        # 1. Add the new created_in_version FK to Food.
        migrations.AddField(
            model_name='food',
            name='created_in_version',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='created_foods',
                to='foods.dbversion',
            ),
        ),

        # 2. Add related_name to the existing updated_in_version FK.
        #    Django cannot rename the column, so we alter the field in-place.
        migrations.AlterField(
            model_name='food',
            name='updated_in_version',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='updated_foods',
                to='foods.dbversion',
            ),
        ),

        # 3. Replace the old unique_active_ean constraint (which allowed duplicate blank EANs
        #    only for inactive foods) with a tighter one that always allows blank EANs.
        migrations.RemoveConstraint(
            model_name='food',
            name='unique_active_ean',
        ),
        migrations.AddConstraint(
            model_name='food',
            constraint=models.UniqueConstraint(
                fields=['ean'],
                condition=models.Q(is_active=True) & ~models.Q(ean=''),
                name='unique_active_ean',
            ),
        ),

        # 4. Add partial-unique constraint on DbVersion so only one draft may exist.
        migrations.AddConstraint(
            model_name='dbversion',
            constraint=models.UniqueConstraint(
                fields=['is_published'],
                condition=models.Q(is_published=False),
                name='unique_draft_version',
            ),
        ),

        # 5. Add unique constraint on Changelog so each (food, version) pair has at most
        #    one entry (prevents duplicate log rows on rapid saves).
        migrations.AddConstraint(
            model_name='changelog',
            constraint=models.UniqueConstraint(
                fields=['food', 'version'],
                name='unique_changelog_per_food_version',
            ),
        ),
    ]
