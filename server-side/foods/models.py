from django.db import models
from decimal import Decimal, InvalidOperation
from django.db.models import Q
from django.core.exceptions import ValidationError

class DbVersion(models.Model):
    """
    Represents a specific release version of the food database.
    Used for the offline-first sync mechanism to send only deltas (changes) to mobile clients.
    """
    version = models.AutoField(primary_key=True)
    created_at = models.DateTimeField(auto_now_add=True)
    # Indicates if this version is finalized and available for mobile clients to download.
    is_published = models.BooleanField(default=False)

    def __str__(self):
        return f"Verze {self.version}"

class Food(models.Model):
    """
    The main food catalog. Contains the currently valid nutritional values.
    Historical values are not kept here, but in the Changelog.
    """
    ean = models.CharField(max_length=13, blank=True, db_index=True)
    name = models.CharField(max_length=255)

    # Nutritional values per 100 per g/ml.
    kcal_per_100 = models.DecimalField(max_digits=6, decimal_places=2)
    protein_g = models.DecimalField(max_digits=5, decimal_places=2)
    carbs_g = models.DecimalField(max_digits=5, decimal_places=2)
    sugars_g = models.DecimalField(max_digits=5, decimal_places=2)
    fat_g = models.DecimalField(max_digits=5, decimal_places=2)
    saturated_fat_g = models.DecimalField(max_digits=5, decimal_places=2)
    fibers_g = models.DecimalField(max_digits=5, decimal_places=2)
    salt_g = models.DecimalField(max_digits=5, decimal_places=2)

    # Path or URL to the food's image stored in a cloud bucket (e.g., Cloudflare R2).
    image_path = models.CharField(max_length=255, blank=True)

    # Soft-delete flag. If False, the item is removed from the mobile catalog,
    # but remains in the DB to preserve integrity.
    is_active = models.BooleanField(default=True)

    # Tracks which database version this specific food was last modified in.
    # Crucial for fast API queries when clients ask for updates since their last sync.
    updated_in_version = models.ForeignKey(DbVersion, on_delete=models.SET_NULL, null=True, blank=True)

    class Meta:
        # Prevents the creation of foods with 2 identical EANs unless duplicous ones are is_active=False
        constraints = [
            models.UniqueConstraint(
                fields=['ean'], 
                condition=Q(is_active=True), 
                name='unique_active_ean'
            )
        ]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
            """
            Saves the Food record and intelligently manages versioning and changelogs.
            
            Key behaviors:
            1. Tracks 'updated_in_version' ONLY if the item is updated in a version 
            different from the one it was created in.
            2. Aggregates Changelog entries within the same draft version to prevent duplicates.
            3. Stores 'new_values' for delta synchronization and 'old_values' for server rollbacks.
            4. Handles the 'ping-pong' effect (reverting a change back to its original state).
            """
            is_new = self.pk is None
            changed_data = {}
            action_type = 'CREATED'
            has_older_version = False

            # 1. Ensure an active draft version exists (is_published=False)
            draft_version, _ = DbVersion.objects.get_or_create(is_published=False)
            is_first_version = (draft_version.version == 1)

            # 2. Detect changes and determine cross-version updates
            if not is_new:
                # Fetch the old state from the database before it gets overwritten
                old_obj = Food.objects.get(pk=self.pk)
                fields_to_check = [
                    'name', 'ean', 'kcal_per_100', 'protein_g', 
                    'carbs_g', 'sugars_g', 'fat_g', 'saturated_fat_g', 
                    'fibers_g', 'salt_g', 'is_active'
                ]
                
                # Compare fields to find what exactly changed
                for field in fields_to_check:
                    old_val = getattr(old_obj, field)
                    new_val = getattr(self, field)
                    
                    try:
                        # Safely compare numeric values (e.g., Decimal) to avoid ghost updates like 744.00 != 744
                        val1 = Decimal(str(old_val)).normalize() if old_val is not None else None
                        val2 = Decimal(str(new_val)).normalize() if new_val is not None else None
                        is_changed = (val1 != val2)
                    except InvalidOperation:
                        # Fallback for non-numeric fields (strings, booleans)
                        is_changed = (old_val != new_val)

                    if is_changed:
                        changed_data[field] = (str(old_val), str(new_val))
                
                # If no tracked fields were changed (AND it's an existing item), exit logging
                if not is_new and not changed_data:
                    super().save(*args, **kwargs)
                    return
                    
                # Determine if the item is being soft-deleted
                action_type = 'DELETED' if self.is_active is False else 'UPDATED'

                # --- LOGIC FOR 'updated_in_version' ---
                # Check if this food item has a history in ANY older, closed version.
                # If it was just created in the current draft version and is being modified again,
                # it shouldn't be marked as "updated" (it's still conceptually new to the mobile app).
                has_older_version = Changelog.objects.filter(food=self).exclude(version=draft_version).exists()
                
                if has_older_version:
                    self.updated_in_version = draft_version
                else:
                    self.updated_in_version = None
            else:
                # Brand new items do not have an "updated_in_version"
                self.updated_in_version = None

            # 3. Perform the actual physical save to the database
            super().save(*args, **kwargs)

            # 4. Handle Changelog Aggregation (Delta Sync & Revert preparation)
            existing_log = Changelog.objects.filter(food=self, version=draft_version).first()

            if existing_log:
                if not has_older_version:
                    # --- ITEM BORN IN THIS DRAFT VERSION ---
                    # This item has no history. It only toggles between CREATED and DELETED.
                    # We NEVER generate delta logs (old_values/new_values) for items born in this version.
                    if action_type == 'DELETED':
                        existing_log.action = 'DELETED'
                    else:
                        existing_log.action = 'CREATED'
                    
                    # Hard reset values to ensure it remains clean, even if manipulated multiple times
                    existing_log.old_values = {}
                    existing_log.new_values = {}
                    existing_log.save()
                else:
                    # --- HISTORICAL ITEM ---
                    # The item existed in previous versions. We track deltas and handle the ping-pong effect.
                    existing_log.action = action_type
                    
                    if action_type in ['UPDATED', 'DELETED']:
                        if existing_log.old_values is None: existing_log.old_values = {}
                        if existing_log.new_values is None: existing_log.new_values = {}
                        
                        for field, (old_v, new_v) in changed_data.items():
                            # Determine the absolute original value at the start of this version
                            original_old = existing_log.old_values.get(field, old_v)
                            
                            if original_old == new_v:
                                # PING-PONG EFFECT (Net-zero change): The user reverted the field 
                                # back to its exact original state at the start of this version.
                                # We remove this field from the log to prevent redundant delta updates.
                                existing_log.new_values.pop(field, None)
                                existing_log.old_values.pop(field, None)
                            else:
                                # The field actually changed.
                                existing_log.new_values[field] = new_v
                                
                                # Preserve the VERY FIRST old value in this draft version for safe rollbacks.
                                # Exclude 'is_first_version' as the initial DB state has no prior state to revert to.
                                if not is_first_version and field not in existing_log.old_values:
                                    existing_log.old_values[field] = old_v
                                    
                        # If all changes were reverted (ping-pong effect on all fields) 
                        # and the item is not deleted, the log is entirely redundant and should be removed.
                        if not existing_log.new_values and existing_log.action == 'UPDATED':
                            existing_log.delete()
                        else:
                            existing_log.save()
            else:
                # No log exists yet in this draft version, create a fresh one
                old_vals = {}
                new_vals = {}
                
                # Extract old and new values ONLY if it's an update to a historical item
                if action_type in ['UPDATED', 'DELETED'] and has_older_version:
                    # Do not track old values for the genesis version (version 1)
                    if not is_first_version:
                        old_vals = {k: v[0] for k, v in changed_data.items()}
                    new_vals = {k: v[1] for k, v in changed_data.items()}
                    
                Changelog.objects.create(
                    food=self,
                    version=draft_version,
                    action=action_type,
                    old_values=old_vals,
                    new_values=new_vals
                )
    def clean(self):
            """
            Validates the Food instance before saving.
            Ensures that a newly created food item in the current draft version 
            cannot be hidden (is_active = False) until the version is published.
            """
            super().clean()
            
            # We only care if the user is trying to hide/soft-delete the item
            if not self.is_active:
                # Fetch the current draft version
                draft_version, _ = DbVersion.objects.get_or_create(is_published=False)
                
                if self.pk is None:
                    # Scenario A: The user is creating a brand new item but unchecked 'is_active' right away.
                    raise ValidationError({
                        'is_active': 'A newly added food item cannot be hidden immediately. It must remain active at least for the version it was created in.'
                    })
                else:
                    # Scenario B: The item exists, but we must check if it was born in THIS draft version.
                    has_older_version = Changelog.objects.filter(food=self).exclude(version=draft_version).exists()
                    if not has_older_version:
                        raise ValidationError({
                            'is_active': f'This food item cannot be hidden because it was created in the current open version ({draft_version}). Publish the version first before removing it.'
                        })
class Changelog(models.Model):
    """
    Records the delta (changes) of foods across database versions.
    Acts as the source of truth for historical data and allows for data rollbacks.
    """
    ACTION_CHOICES = [
        ('CREATED', 'Vytvořeno'),
        ('UPDATED', 'Upraveno'),
        ('DELETED', 'Smazáno'),
    ]
    food = models.ForeignKey(Food, on_delete=models.CASCADE)
    # The database version in which this change occurred.
    version = models.ForeignKey(DbVersion, on_delete=models.CASCADE)
    action = models.CharField(max_length=20, choices=ACTION_CHOICES)
    # Stores ONLY the fields that were changed in that version relative
    # to the previous version (e.g., {"kcal_per_100": 150}). 
    # Used to revert a food item to its exact previous state.
    old_values = models.JSONField(default=dict, blank=True)
    # This value is send to the end users as the change from previous version
    new_values = models.JSONField(default=dict, blank=True)

    def __str__(self):
        return f"{self.get_action_display()} - {self.food.name}"