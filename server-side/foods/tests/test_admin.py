from decimal import Decimal
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse

from foods.models import Changelog, DbVersion, Food


# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

def create_food(**kwargs) -> Food:
    """Create a Food with sensible zero-nutrient defaults."""
    defaults = {
        "name": "Test Food",
        "kcal_per_100": Decimal("100.00"),
        "protein_g": Decimal("0.00"),
        "carbs_g": Decimal("0.00"),
        "sugars_g": Decimal("0.00"),
        "fat_g": Decimal("0.00"),
        "saturated_fat_g": Decimal("0.00"),
        "fibers_g": Decimal("0.00"),
        "salt_g": Decimal("0.00"),
    }
    defaults.update(kwargs)
    return Food.objects.create(**defaults)


def publish_draft() -> DbVersion:
    """Mark the current open draft as published and return it.
    Creates a new draft (V1) if none exists yet.
    """
    draft, created = DbVersion.objects.get_or_create(is_published=False)
    draft.is_published = True
    draft.save()
    return draft


# ===========================================================================
# Admin: ChangelogAdmin is read-only
# ===========================================================================

class ChangelogAdminPermissionsTests(TestCase):

    def setUp(self):
        User = get_user_model()
        self.admin_user = User.objects.create_superuser(
            username="admin", email="admin@example.com", password="password123"
        )

    def test_has_change_permission_false(self):
        from foods.admin import ChangelogAdmin
        from django.contrib.admin.sites import AdminSite
        site = AdminSite()
        ca = ChangelogAdmin(Changelog, site)
        # has_change_permission must return False for any request.
        self.assertFalse(ca.has_change_permission(None))
        self.assertFalse(ca.has_change_permission(None, obj=object()))

    def test_has_add_permission_false(self):
        from foods.admin import ChangelogAdmin
        from django.contrib.admin.sites import AdminSite
        site = AdminSite()
        ca = ChangelogAdmin(Changelog, site)
        self.assertFalse(ca.has_add_permission(None))

    def test_has_delete_permission_true(self):
        from foods.admin import ChangelogAdmin
        from django.contrib.admin.sites import AdminSite
        site = AdminSite()
        ca = ChangelogAdmin(Changelog, site)
        self.assertTrue(ca.has_delete_permission(None))


# ===========================================================================
# Admin: soft_delete_foods action blocks draft-born foods
# ===========================================================================

class SoftDeleteAdminActionTests(TestCase):

    def setUp(self):
        User = get_user_model()
        self.admin_user = User.objects.create_superuser(
            username="admin2", email="admin2@example.com", password="password123"
        )
        self.client.force_login(self.admin_user)

    def test_soft_delete_action_blocks_draft_born_food(self):
        """The admin action must skip foods born in the current open draft."""
        food = create_food(name="Draft Food")
        url = reverse("admin:foods_food_changelist")
        response = self.client.post(url, {
            "action": "soft_delete_foods",
            "_selected_action": [food.pk],
        }, follow=True)
        food.refresh_from_db()
        # Food should still be active because it was born in this draft.
        self.assertTrue(food.is_active)
        self.assertEqual(response.status_code, 200)

    def test_soft_delete_action_works_for_historical_food(self):
        """The admin action must soft-delete foods from published versions."""
        food = create_food(name="Historical Food")
        publish_draft()

        url = reverse("admin:foods_food_changelist")
        self.client.post(url, {
            "action": "soft_delete_foods",
            "_selected_action": [food.pk],
        }, follow=True)
        food.refresh_from_db()
        self.assertFalse(food.is_active)


# ===========================================================================
# Admin: hard_delete action
# ===========================================================================

class HardDeleteAdminActionTests(TestCase):

    def setUp(self):
        User = get_user_model()
        self.admin_user = User.objects.create_superuser(
            username="admin3", email="admin3@example.com", password="password123"
        )
        self.client.force_login(self.admin_user)

    def test_hard_delete_blocked_for_published_food(self):
        """Historical foods must be blocked from hard-delete in the admin."""
        food = create_food(name="Old Food")
        publish_draft()
        # Create a new draft so there IS a current draft.
        create_food(name="New draft food")

        url = reverse("admin:foods_food_changelist")
        response = self.client.post(url, {
            "action": "hard_delete_with_warning",
            "_selected_action": [food.pk],
        }, follow=True)
        # Food must still exist.
        self.assertTrue(Food.objects.filter(pk=food.pk).exists())