from decimal import Decimal
from django.test import TestCase
from foods.models import Food, DbVersion, Changelog

class ChangelogRobustnessTests(TestCase):
    
    def publish_current_version(self):
        """Pomocná metoda, která nasimuluje uzavření/vydání aktuální verze."""
        draft = DbVersion.objects.get(is_published=False)
        draft.is_published = True
        draft.save()
        return draft

    def test_genesis_version_no_delta_logs(self):
        """
        KRITICKÝ TEST: Položka vytvořená a upravovaná v té samé (a to i první) verzi 
        nesmí nikdy generovat delta logy (old_values/new_values musí být prázdné).
        """
        # 1. Vytvoření
        food = Food.objects.create(name="Jablko", kcal_per_100=50)
        log = Changelog.objects.get(food=food)
        
        self.assertEqual(log.action, 'CREATED', "Akce musí být CREATED.")
        self.assertEqual(log.old_values, {}, "Old values musí být prázdné.")
        self.assertEqual(log.new_values, {}, "New values musí být prázdné.")
        self.assertIsNone(food.updated_in_version, "Updated in version musí být None.")

        # 2. Úprava ve stejné verzi
        food.kcal_per_100 = 60
        food.save()
        
        # Testujeme, že to nepřepsalo akci na UPDATED a nezačalo to logovat hodnoty
        log.refresh_from_db()
        self.assertEqual(log.action, 'CREATED', "Změna v domovské verzi nesmí přepsat akci z CREATED.")
        self.assertEqual(log.old_values, {}, "I po úpravě musí zůstat old_values prázdné.")
        self.assertEqual(log.new_values, {}, "I po úpravě musí zůstat new_values prázdné.")

    def test_cross_version_update_generates_delta(self):
        """
        KRITICKÝ TEST: Jakmile je položka z minulé verze upravena, 
        musí uložit správné delty a nastavit 'updated_in_version'.
        """
        food = Food.objects.create(name="Banán", kcal_per_100=90)
        v1 = self.publish_current_version()

        # Úprava ve Verzi 2
        food.kcal_per_100 = 100
        food.save()
        
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        food.refresh_from_db()

        self.assertEqual(log.action, 'UPDATED')
        self.assertEqual(log.old_values['kcal_per_100'], '90.00', "Old value si musí pamatovat stav z V1.")
        self.assertEqual(log.new_values['kcal_per_100'], '100.00', "New value musí obsahovat novou hodnotu.")
        self.assertEqual(food.updated_in_version, v2, "Pole updated_in_version musí ukazovat na V2.")

    def test_ping_pong_effect_cancels_log(self):
        """
        KRITICKÝ TEST: Pokud uživatel změní hodnotu a pak ji ve stejné verzi vrátí zpět,
        záznam v logu se musí kompletně smazat (net-zero change).
        """
        food = Food.objects.create(name="Ořechy", kcal_per_100=600)
        self.publish_current_version()

        # Změna z 600 na 650 (Verze 2)
        food.kcal_per_100 = 650
        food.save()
        
        v2 = DbVersion.objects.get(is_published=False)
        self.assertTrue(Changelog.objects.filter(food=food, version=v2).exists(), "Log by měl existovat.")

        # Změna zpět z 650 na 600 (Ping-pong)
        food.kcal_per_100 = 600
        food.save()

        # Záznam by měl kompletně zmizet, protože se vlastně nic nezměnilo
        log_exists = Changelog.objects.filter(food=food, version=v2).exists()
        self.assertFalse(log_exists, "Ping-pong změna nedokázala smazat zbytečný log!")

    def test_partial_ping_pong_keeps_log(self):
        """
        KRITICKÝ TEST: Pokud uživatel změní 2 věci, ale vrátí zpět jen jednu z nich,
        log musí přežít, ale vrácená hodnota z něj musí zmizet.
        """
        food = Food.objects.create(name="Mléko", kcal_per_100=40)
        self.publish_current_version()

        # Měníme dvě věci
        food.name = "Plnotučné mléko"
        food.kcal_per_100 = 65
        food.save()

        # Vracíme zpět POUZE kalorie na 40
        food.kcal_per_100 = 40
        food.save()

        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)

        self.assertIn('name', log.new_values, "Název se trvale změnil, musí být v logu.")
        self.assertNotIn('kcal_per_100', log.new_values, "Kalorie se vrátily zpět, v logu NESMÍ být!")
        self.assertNotIn('kcal_per_100', log.old_values, "Kalorie nesmí být ani v old_values.")

    def test_soft_delete_and_restore_in_same_version(self):
        """
        KRITICKÝ TEST: Změna is_active na False a zpět na True 
        (jak v domovské verzi, tak v cizí verzi).
        """
        # A) V domovské verzi (vytvoření, smazání, obnova)
        food = Food.objects.create(name="Tatranka", kcal_per_100=500)
        
        food.is_active = False
        food.save()
        log = Changelog.objects.get(food=food)
        self.assertEqual(log.action, 'DELETED', "Po skrytí nové položky musí být akce DELETED.")
        
        food.is_active = True
        food.save()
        log.refresh_from_db()
        self.assertEqual(log.action, 'CREATED', "Po obnovení nové položky musí být akce zpět na CREATED.")

        # B) V cizí verzi (historická položka)
        self.publish_current_version()
        
        food.is_active = False # Skrýváme ve V2
        food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log_v2 = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log_v2.action, 'DELETED')
        self.assertEqual(log_v2.new_values['is_active'], 'False')

        food.is_active = True # Odkrýváme zpět ve V2 (Ping-pong)
        food.save()
        self.assertFalse(Changelog.objects.filter(food=food, version=v2).exists(), "Obnovení historické položky nesmazalo zbytečný DELETED log!")

    def test_decimal_ghost_update_ignored(self):
        """
        KRITICKÝ TEST: Změna formátu desetinného čísla (např. 744.00 na 744 nebo 744.0)
        nesmí vygenerovat vůbec žádný log, protože matematicky se nic nemění.
        """
        food = Food.objects.create(name="Máslo", kcal_per_100=Decimal('744.00'))
        self.publish_current_version()

        # Přiřazení "jiného" typu téže hodnoty
        food.kcal_per_100 = Decimal('744')
        food.save()

        food.kcal_per_100 = 744.0
        food.save()

        # Ověření
        v2 = DbVersion.objects.get(is_published=False)
        log_exists = Changelog.objects.filter(food=food, version=v2).exists()
        self.assertFalse(log_exists, "Kód naletěl na falešného ducha! Vytvořil log pro matematicky totožné číslo.")