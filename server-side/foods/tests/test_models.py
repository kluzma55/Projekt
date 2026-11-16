"""
Comprehensive test suite for the foods table.

Run with:
    python manage.py test foods --settings=backend.test_settings --verbosity=2
"""
from decimal import Decimal
from django.core.exceptions import ValidationError
from django.test import TestCase

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
# V1 — no logs at all
# ===========================================================================

class V1NoLogsTests(TestCase):
    """V1 foods should never generate changelog entries."""

    def test_new_food_in_v1_has_no_log(self):
        """Creating a food in the very first version must NOT write a Changelog row."""
        food = create_food(name="Apple")
        self.assertEqual(Changelog.objects.count(), 0, "V1 must produce zero changelog entries.")

    def test_editing_food_in_v1_produces_no_log(self):
        """Editing a food while still in V1 must NOT produce a changelog entry."""
        food = create_food(name="Apple", kcal_per_100=Decimal("50.00"))
        food.kcal_per_100 = Decimal("60.00")
        food.save()
        self.assertEqual(Changelog.objects.count(), 0)

    def test_new_food_in_v1_sets_created_in_version(self):
        """created_in_version must be set on a new food created during V1."""
        food = create_food(name="Apple")
        draft = DbVersion.objects.get(is_published=False)
        food.refresh_from_db()
        self.assertEqual(food.created_in_version_id, draft.pk)

    def test_new_food_in_v1_has_null_updated_in_version(self):
        food = create_food(name="Apple")
        food.refresh_from_db()
        self.assertIsNone(food.updated_in_version)


# ===========================================================================
# V2+ — basic CREATED log
# ===========================================================================

class V2CreatedLogTests(TestCase):
    """Foods created in V2+ get a CREATED log with no field values."""

    def setUp(self):
        # Publish V1 so a new draft (V2) is opened on the next save.
        create_food(name="Existing V1 food")
        publish_draft()

    def test_new_food_in_v2_gets_created_log(self):
        food = create_food(name="New V2 Food")
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log.action, "CREATED")
        self.assertEqual(log.old_values, {})
        self.assertEqual(log.new_values, {})

    def test_created_log_has_no_field_deltas(self):
        food = create_food(name="Strawberry", kcal_per_100=Decimal("33.00"))
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log.old_values, {})
        self.assertEqual(log.new_values, {})

    def test_new_food_updated_in_version_is_null(self):
        food = create_food(name="New V2 Food")
        food.refresh_from_db()
        self.assertIsNone(food.updated_in_version)


# ===========================================================================
# Cross-version UPDATE log
# ===========================================================================

class CrossVersionUpdateTests(TestCase):
    """Editing a published food in a later version must generate correct deltas."""

    def setUp(self):
        self.food = create_food(name="Banana", kcal_per_100=Decimal("90.00"))
        publish_draft()

    def test_update_generates_updated_log(self):
        self.food.kcal_per_100 = Decimal("100.00")
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=self.food, version=v2)
        self.assertEqual(log.action, "UPDATED")
        self.assertEqual(log.old_values["kcal_per_100"], "90.00")
        self.assertEqual(log.new_values["kcal_per_100"], "100.00")

    def test_update_sets_updated_in_version(self):
        self.food.kcal_per_100 = Decimal("100.00")
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        self.food.refresh_from_db()
        self.assertEqual(self.food.updated_in_version, v2)

    def test_multiple_fields_updated_all_captured(self):
        self.food.name = "Ripe Banana"
        self.food.kcal_per_100 = Decimal("95.00")
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=self.food, version=v2)
        self.assertIn("name", log.old_values)
        self.assertIn("kcal_per_100", log.old_values)
        self.assertEqual(log.old_values["name"], "Banana")
        self.assertEqual(log.new_values["name"], "Ripe Banana")


# ===========================================================================
# Same-version aggregation (second edit accumulates onto the first log)
# ===========================================================================

class SameVersionAggregationTests(TestCase):
    """Multiple edits within the same draft produce a single aggregated log."""

    def setUp(self):
        self.food = create_food(name="Milk", kcal_per_100=Decimal("40.00"))
        publish_draft()

    def test_second_edit_updates_existing_log(self):
        self.food.kcal_per_100 = Decimal("45.00")
        self.food.save()

        self.food.kcal_per_100 = Decimal("50.00")
        self.food.save()

        v2 = DbVersion.objects.get(is_published=False)
        # Must still be only ONE log row for this food in this version.
        self.assertEqual(Changelog.objects.filter(food=self.food, version=v2).count(), 1)
        log = Changelog.objects.get(food=self.food, version=v2)
        # old_values must reflect the state at V1, not the intermediate 45.
        self.assertEqual(log.old_values["kcal_per_100"], "40.00")
        self.assertEqual(log.new_values["kcal_per_100"], "50.00")


# ===========================================================================
# Ping-pong (full revert)
# ===========================================================================

class PingPongTests(TestCase):
    """Reverting all changes within a draft must delete the log and clear updated_in_version."""

    def setUp(self):
        self.food = create_food(name="Nuts", kcal_per_100=Decimal("600.00"))
        publish_draft()

    def test_full_revert_deletes_log(self):
        self.food.kcal_per_100 = Decimal("650.00")
        self.food.save()

        v2 = DbVersion.objects.get(is_published=False)
        self.assertTrue(Changelog.objects.filter(food=self.food, version=v2).exists())

        # Revert back.
        self.food.kcal_per_100 = Decimal("600.00")
        self.food.save()

        self.assertFalse(
            Changelog.objects.filter(food=self.food, version=v2).exists(),
            "Full ping-pong must delete the log entirely.",
        )

    def test_full_revert_across_multiple_versions_restores_tracker(self):
        """If a food was updated in V2, and we ping-pong an edit in V3, it should restore to V2, not None."""
        # 1. Start with the food from setUp (created in V1)
        
        # 2. Update in V2 and publish it, so it has a legitimate update history
        self.food.kcal_per_100 = Decimal("610.00")
        self.food.save()
        v2 = publish_draft()
        
        self.food.refresh_from_db()
        self.assertEqual(self.food.updated_in_version, v2)
        
        # 3. Make a new edit in the V3 draft
        self.food.kcal_per_100 = Decimal("650.00")
        self.food.save()
        
        # 4. Revert the edit (Ping-pong in V3)
        self.food.kcal_per_100 = Decimal("610.00")
        self.food.save()
        
        self.food.refresh_from_db()
        
        # 5. Assert it correctly rewound to V2 instead of dropping to None
        self.assertIsNotNone(
            self.food.updated_in_version,
            "Ping-pong must not erase prior version history."
        )
        self.assertEqual(
            self.food.updated_in_version, v2,
            "Ping-pong should restore the tracker to the last published update (V2)."
        )


# ===========================================================================
# Partial ping-pong
# ===========================================================================

class PartialPingPongTests(TestCase):
    """Reverting some (but not all) changed fields must keep the log but remove reverted fields."""

    def setUp(self):
        self.food = create_food(name="Full-fat Milk", kcal_per_100=Decimal("40.00"))
        publish_draft()

    def test_partial_revert_removes_only_reverted_field(self):
        self.food.name = "Skimmed Milk"
        self.food.kcal_per_100 = Decimal("65.00")
        self.food.save()

        # Revert kcal but keep name change.
        self.food.kcal_per_100 = Decimal("40.00")
        self.food.save()

        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=self.food, version=v2)

        self.assertIn("name", log.new_values, "Name change must remain in log.")
        self.assertNotIn("kcal_per_100", log.new_values, "Reverted kcal must be gone from log.")
        self.assertNotIn("kcal_per_100", log.old_values, "Reverted kcal must be gone from old_values too.")


# ===========================================================================
# Soft-delete / restore
# ===========================================================================

class SoftDeleteTests(TestCase):

    def test_soft_delete_born_in_draft_blocked_by_clean(self):
        """Foods born in the current draft must not be soft-deletable (ValidationError)."""
        draft = DbVersion.objects.get_or_create(is_published=False)[0]
        food = create_food(name="New Draft Food")
        food.is_active = False
        with self.assertRaises(ValidationError):
            food.full_clean()

    def test_soft_delete_historical_food_generates_deleted_log(self):
        food = create_food(name="Historical Food")
        publish_draft()

        food.is_active = False
        food.save()

        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log.action, "DELETED")
        self.assertIn("is_active", log.new_values)
        self.assertEqual(log.new_values["is_active"], "False")

    def test_restore_historical_food_is_pingpong(self):
        """Soft-deleting then restoring a historical food in the same draft → no log."""
        food = create_food(name="Historical Food")
        publish_draft()

        food.is_active = False
        food.save()

        food.is_active = True
        food.save()

        v2 = DbVersion.objects.get(is_published=False)
        self.assertFalse(
            Changelog.objects.filter(food=food, version=v2).exists(),
            "Restoring a soft-deleted food in the same version should ping-pong the log away.",
        )

    def test_born_in_draft_toggle_created_deleted(self):
        """Foods born in this draft only toggle between CREATED and DELETED (no deltas)."""
        # Create a V1 food to initialise V1, then publish it so V2 is the current draft.
        create_food(name="V1 Seed")  # triggers V1 creation
        publish_draft()
        food = create_food(name="New V2 Food")

        # Directly bypass clean() to simulate admin hard-delete path in test.
        # For the toggle test we simulate by setting updated status (admin would block soft-delete).
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=food, version=v2)
        self.assertEqual(log.action, "CREATED")
        # Simulate toggling via the model directly (skipping validation for this test).
        food.is_active = False
        food.save()
        log.refresh_from_db()
        self.assertEqual(log.action, "DELETED")
        self.assertEqual(log.old_values, {})
        self.assertEqual(log.new_values, {})

        food.is_active = True
        food.save()
        log.refresh_from_db()
        self.assertEqual(log.action, "CREATED")


# ===========================================================================
# Decimal comparison
# ===========================================================================

class DecimalComparisonTests(TestCase):

    def setUp(self):
        self.food = create_food(name="Butter", kcal_per_100=Decimal("744.00"))
        publish_draft()

    def test_decimal_format_difference_is_no_op(self):
        """744.00 vs 744 vs 744.0 — all the same value → no log."""
        self.food.kcal_per_100 = Decimal("744")
        self.food.save()

        self.food.kcal_per_100 = 744.0
        self.food.save()

        # No-op saves must NOT open a new draft version at all.
        v2 = DbVersion.objects.filter(is_published=False).first()
        self.assertIsNone(v2, "No draft version should be created for a no-op decimal save.")
        self.assertEqual(Changelog.objects.count(), 0, "Format-only decimal change must not produce a log.")

    def test_float_noise_ignored(self):
        """0.1+0.2 (which may differ from 0.3 as a float) must not generate a log."""
        food = create_food(name="Float Noise Food", salt_g=Decimal("0.30"))
        publish_draft()  # Publishes V2 (the food got a CREATED log in V2)

        log_count_before = Changelog.objects.count()

        food.salt_g = Decimal(str(0.1 + 0.2))  # may be 0.30000000000000004
        food.save()

        # No-op — no draft version created, no additional log.
        v3 = DbVersion.objects.filter(is_published=False).first()
        self.assertIsNone(v3, "No draft version should be created for a float-noise no-op.")
        self.assertEqual(
            Changelog.objects.count(), log_count_before,
            "Float noise must not trigger a new changelog entry.",
        )


# ===========================================================================
# EAN handling
# ===========================================================================

class EanTests(TestCase):

    def setUp(self):
        self.food = create_food(name="Product", ean="0012345678905")
        publish_draft()

    def test_same_ean_with_leading_zeros_is_no_op(self):
        """'0012345678905' saved again must not register as changed."""
        self.food.ean = "0012345678905"
        self.food.save()
        # No-op — no draft version should have been created.
        v2 = DbVersion.objects.filter(is_published=False).first()
        self.assertIsNone(v2, "A no-op EAN save must not open a new draft version.")
        self.assertEqual(Changelog.objects.count(), 0)

    def test_different_ean_is_detected(self):
        self.food.ean = "0012345678906"
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=self.food, version=v2)
        self.assertEqual(log.old_values["ean"], "0012345678905")
        self.assertEqual(log.new_values["ean"], "0012345678906")

    def test_leading_zeros_not_stripped(self):
        """EAN comparison must be string-based, never numeric (12345… ≠ 0012345…)."""
        self.food.ean = "12345678905"  # leading zero stripped → different string
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        self.assertTrue(
            Changelog.objects.filter(food=self.food, version=v2).exists(),
            "Stripping leading zeros must be detected as a real change.",
        )

    def test_multiple_foods_without_ean_allowed(self):
        """Multiple foods with ean='' must not violate the unique_active_ean constraint."""
        f1 = create_food(name="No EAN 1", ean="")
        f2 = create_food(name="No EAN 2", ean="")
        # If we get here without IntegrityError the constraint is correct.
        self.assertEqual(Food.objects.filter(ean="").count(), 2)


# ===========================================================================
# image_path tracking
# ===========================================================================

class ImagePathTrackingTests(TestCase):

    def setUp(self):
        self.food = create_food(name="Yoghurt", image_path="old/path.jpg")
        publish_draft()

    def test_image_path_change_is_logged(self):
        self.food.image_path = "new/path.jpg"
        self.food.save()
        v2 = DbVersion.objects.get(is_published=False)
        log = Changelog.objects.get(food=self.food, version=v2)
        self.assertIn("image_path", log.new_values)
        self.assertEqual(log.old_values["image_path"], "old/path.jpg")
        self.assertEqual(log.new_values["image_path"], "new/path.jpg")


# ===========================================================================
# No-op saves
# ===========================================================================

class NoOpSaveTests(TestCase):

    def test_no_op_save_does_not_open_draft_version(self):
        """If nothing changes, no draft version should be created."""
        food = create_food(name="Cheese")
        # Publish V1 so we can test whether V2 is opened needlessly.
        publish_draft()

        # Save with identical values.
        food.name = "Cheese"
        food.save()

        # No new draft should have been created.
        self.assertEqual(DbVersion.objects.filter(is_published=False).count(), 0)

    def test_no_op_save_produces_no_log(self):
        food = create_food(name="Ham")
        publish_draft()

        food.name = "Ham"  # same value
        food.save()

        self.assertEqual(Changelog.objects.count(), 0)


# ===========================================================================
# Hard-delete
# ===========================================================================

class HardDeleteTests(TestCase):

    def test_hard_delete_born_in_draft_is_allowed(self):
        """Foods born in the current draft can be physically deleted."""
        publish_draft()
        food = create_food(name="New V2 Food")
        food_pk = food.pk
        
        # Pass the flag to authorize the test
        food.delete(from_hard_delete_action=True)
        self.assertFalse(Food.objects.filter(pk=food_pk).exists())

    def test_hard_delete_v1_food_in_v1_is_allowed(self):
        """Genesis foods can be deleted while still in V1 (before publish)."""
        food = create_food(name="Genesis Food")
        food_pk = food.pk
        
        # Pass the flag to authorize the test
        food.delete(from_hard_delete_action=True)
        self.assertFalse(Food.objects.filter(pk=food_pk).exists())

    def test_delete_blocked_without_explicit_flag(self):
        """Calling delete() without the authorization flag must raise a ValueError."""
        food = create_food(name="Standard Food")
        
        with self.assertRaisesMessage(ValueError, "Direct deletions are disabled"):
            food.delete() # No flag passed

    def test_hard_delete_blocked_for_published_food_at_model_level(self):
        """Even with the auth flag, calling delete() on a published food must raise a ValueError."""
        # 1. Create a food and publish it so it becomes historical data
        food = create_food(name="Published Food")
        publish_draft() 
        
        # 2. Attempt to hard-delete it via the authorized action flag
        with self.assertRaisesMessage(ValueError, "Nelze trvale smazat publikovanou potravinu"):
            food.delete(from_hard_delete_action=True) # <-- Add the flag here
            
        # 3. Verify it still exists in the database
        self.assertTrue(Food.objects.filter(pk=food.pk).exists())