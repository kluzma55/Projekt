from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('foods', '0008_food_created_in_version_constraints'),
    ]

    operations = [
        migrations.AddField(
            model_name='food',
            name='unit',
            field=models.CharField(
                choices=[('g', 'Gram'), ('ml', 'Mililiter')],
                default='g',
                max_length=2,
            ),
        ),
    ]
