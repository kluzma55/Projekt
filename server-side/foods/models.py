from django.db import models, transaction
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from django.db.models import Q
from django.core.exceptions import ValidationError


def _normalise_decimal(value) -> Decimal:
    """Quantise a value to 2 decimal places for consistent comparison and storage.
    This eliminates float noise (0.1+0.2 == 0.3) and format differences (744 == 744.00).
    """
    try:
        return Decimal(str(value)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError):
        return Decimal('0.00')


class DbVersion(models.Model):
    """
    Represents a specific release version of the food database.
    Used for the offline-first sync mechanism to send only deltas (changes) to mobile clients.
    At most one draft (unpublished) version may exist at any time, enforced by DB constraint.
    """
    version = models.AutoField(primary_key=True)
    created_at = models.DateTimeField(auto_now_add=True)
    # Indicates if this version is finalised and available for mobile clients to download.
    is_published = models.BooleanField(default=False)

    class Meta:
        constraints = [
            # Only one unpublished (draft) version may exist at a time.
            models.UniqueConstraint(
                fields=['is_published'],
                condition=Q(is_published=False),
                name='unique_draft_version',
            )
        ]

    def __str__(self):
        return f"Verze {self.version}"


class Food(models.Model):
    """
    The main food catalog. Contains the currently valid nutritional values.
    Historical values are not kept here, but in the Changelog.
    """
    ean = models.CharField(max_length=13, blank=True, db_index=True)
    name = models.CharField(max_length=255)

    # Nutritional values per 100 g/ml.
    kcal_per_100 = models.DecimalField(max_digits=6, decimal_places=2)
    protein_g = models.DecimalField(max_digits=5, decimal_places=2)
    carbs_g = models.DecimalField(max_digits=5, decimal_places=2)
    sugars_g = models.DecimalField(max_digits=5, decimal_places=2)
    fat_g = models.DecimalField(max_digits=5, decimal_places=2)
    saturated_fat_g = models.DecimalField(max_digits=5, decimal_places=2)
    fibers_g = models.DecimalField(max_digits=5, decimal_places=2)
    salt_g = models.DecimalField(max_digits=5, decimal_places=2)

    # Unit of measurement for the food: grams or millilitres.
    UNIT_G = 'g'
    UNIT_ML = 'ml'
    UNIT_CHOICES = [(UNIT_G, 'Gram'), (UNIT_ML, 'Mililiter')]
    unit = models.CharField(max_length=2, choices=UNIT_CHOICES, default=UNIT_G)

    # Path or URL to the food's image stored in a cloud bucket (e.g. Cloudflare R2).
    image_path = models.CharField(max_length=255, blank=True)

    # Soft-delete flag. If False, the item is removed from the mobile catalog
    # but remains in the DB to preserve history / FK integrity.
    is_active = models.BooleanField(default=True)

    # Tracks which database version this food was last modified in.
    # Crucial for fast API queries: "give me everything changed since version N".
    updated_in_version = models.ForeignKey(
        DbVersion, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='updated_foods',
    )

    # FK that records which version this food was first created in.
    # NULL means the food was part of the genesis import (V1 snapshot) with no creation log.
    # Non-null means it was added explicitly during a draft and gets a CREATED changelog entry.
    created_in_version = models.ForeignKey(
        DbVersion, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='created_foods',
    )

    class Meta:
        constraints = [
            # Unique active EAN — but allow multiple rows with a blank EAN so foods
            # without a barcode can be stored freely.
            models.UniqueConstraint(
                fields=['ean'],
                condition=Q(is_active=True) & ~Q(ean=''),
                name='unique_active_ean',
            )
        ]

    def __str__(self):
        return self.name

    # ── FIELD TRACKING CONFIGURATION ──────────────────────────────────────────

    # All fields whose changes are eligible for Changelog entries.
    TRACKED_FIELDS = [
        'name', 'ean', 'unit', 'kcal_per_100', 'protein_g',
        'carbs_g', 'sugars_g', 'fat_g', 'saturated_fat_g',
        'fibers_g', 'salt_g', 'is_active', 'image_path',
    ]

    # Fields whose values must be compared and stored as quantised 2-dp decimals.
    DECIMAL_FIELDS = {
        'kcal_per_100', 'protein_g', 'carbs_g', 'sugars_g',
        'fat_g', 'saturated_fat_g', 'fibers_g', 'salt_g',
    }

    @classmethod
    def _serialise(cls, field: str, value) -> str:
        """Serialise a field value to a canonical string for log storage and comparison.
        Decimal fields are quantised to 2 dp; everything else is plain str().
        """
        if field in cls.DECIMAL_FIELDS:
            return format(_normalise_decimal(value), 'f')  # e.g. '10.00'
        return str(value)

    @classmethod
    def _compare(cls, field: str, old_val, new_val) -> bool:
        """Return True if old_val and new_val represent a real change for this field.
        For decimals, quantise first to avoid float-noise false positives.
        For EAN (and other string fields), compare as plain strings — never numeric —
        so leading zeros are preserved correctly.
        """
        if field in cls.DECIMAL_FIELDS:
            return _normalise_decimal(old_val) != _normalise_decimal(new_val)
        # Plain equality for strings, booleans, etc.
        return old_val != new_val

    # ── SAVE / VERSIONING LOGIC ────────────────────────────────────────────────

    @transaction.atomic
    def save(self, *args, **kwargs):
        """
        Saves the Food record and manages versioning + changelog.

        Rules (summarised):
          V1 (draft_version.version == 1):
            - save normally, set created_in_version for new foods; NO logs at all.
          New food in V2+:
            - write a CREATED log (empty old_values / new_values).
          Existing food updated in V2+:
            - write / update an UPDATED or DELETED log with deltas.
          No-op save (zero real changes):
            - call super().save() and return; no log, no draft version opened.
          Ping-pong (all changed fields revert to their version-start value):
            - delete the existing log; restore updated_in_version to None.
          Partial ping-pong:
            - keep log but remove reverted fields from old_values / new_values.
        """
        is_new = self._is_new_record()
        changed_data = {}  # {field: (old_serialised, new_serialised)}

        # ── STEP 1: Detect changes on existing records ────────────────────────
        old_obj = None
        if not is_new:
            try:
                old_obj = Food.objects.select_for_update().get(pk=self.pk)
            except Food.DoesNotExist:
                # pk was set explicitly (e.g. fixtures) but doesn't exist yet — treat as new.
                is_new = True

            if old_obj is not None:
                for field in self.TRACKED_FIELDS:
                    old_val = getattr(old_obj, field)
                    new_val = getattr(self, field)
                    if self._compare(field, old_val, new_val):
                        changed_data[field] = (
                            self._serialise(field, old_val),
                            self._serialise(field, new_val),
                        )

                # Early exit: nothing actually changed — just persist and return.
                # Do NOT open a draft version or write any log for a no-op.
                if not changed_data:
                    super().save(*args, **kwargs)
                    return

        # ── STEP 2: Get or create the single open draft version ───────────────
        # get_or_create is safe here because the DB constraint enforces uniqueness.
        draft_version, _ = DbVersion.objects.get_or_create(is_published=False)
        is_first_version = (draft_version.version == 1)

        # ── STEP 3: Determine action type and version bookkeeping ─────────────
        if is_new:
            action_type = 'CREATED'
            # Mark this food as born in the current draft so we know its origin later.
            self.created_in_version = draft_version
            self.updated_in_version = None
        else:
            # Was this food born in a previous (published) version or in this draft?
            born_in_current_draft = (old_obj.created_in_version_id == draft_version.pk)

            # Determine action type from the actual is_active transition.
            if self.is_active is False and old_obj.is_active is True:
                action_type = 'DELETED'
            elif born_in_current_draft and self.is_active is True and old_obj.is_active is False:
                # Restoring a draft-born food: treat as CREATED again (never published as deleted).
                action_type = 'CREATED'
            else:
                # Restoration of a historical food, or a regular field update.
                action_type = 'UPDATED'

            if born_in_current_draft:
                # Foods born in this draft are never "updated" from the mobile app's
                # perspective — they are simply being shaped before first publication.
                self.updated_in_version = None
            else:
                # Historical food (from a published version): mark it as modified.
                self.updated_in_version = draft_version

        # ── STEP 4: Physical save ─────────────────────────────────────────────
        super().save(*args, **kwargs)

        # ── STEP 5: Write / update Changelog ─────────────────────────────────
        # V1: the initial DB state is captured by a snapshot in R2 storage.
        # No CREATED (or any other) logs are written for V1 foods.
        if is_first_version:
            return

        existing_log = Changelog.objects.filter(food=self, version=draft_version).first()

        if is_new:
            # Brand-new food in V2+: simple CREATED log, no field values needed.
            if existing_log:
                # Defensive: shouldn't happen, but reset it cleanly.
                existing_log.action = 'CREATED'
                existing_log.old_values = {}
                existing_log.new_values = {}
                existing_log.save()
            else:
                Changelog.objects.create(
                    food=self, version=draft_version,
                    action='CREATED', old_values={}, new_values={},
                )
            return

        # ── Existing food (UPDATE / DELETE) ────────────────────────────────
        # Re-read born_in_current_draft after the physical save (self.created_in_version_id
        # is now correct regardless of whether we set it above).
        born_in_current_draft = (self.created_in_version_id == draft_version.pk)

        if born_in_current_draft:
            # Foods born in this draft: only toggle CREATED ↔ DELETED; never track deltas.
            if existing_log:
                existing_log.action = action_type
                existing_log.old_values = {}
                existing_log.new_values = {}
                existing_log.save()
            else:
                Changelog.objects.create(
                    food=self, version=draft_version,
                    action=action_type, old_values={}, new_values={},
                )
        else:
            # Historical food (from a published version): track deltas + handle ping-pong.
            if existing_log:
                existing_log.action = action_type

                if existing_log.old_values is None:
                    existing_log.old_values = {}
                if existing_log.new_values is None:
                    existing_log.new_values = {}

                for field, (old_v, new_v) in changed_data.items():
                    # The "original" value at the very start of this draft version.
                    # If we've already recorded it, keep that; otherwise use the current DB value.
                    original_old = existing_log.old_values.get(field, old_v)

                    if original_old == new_v:
                        # Ping-pong: field reverted to its version-start value → remove from log.
                        existing_log.new_values.pop(field, None)
                        existing_log.old_values.pop(field, None)
                    else:
                        existing_log.new_values[field] = new_v
                        # Keep the very first old value for rollback accuracy.
                        if field not in existing_log.old_values:
                            existing_log.old_values[field] = old_v

                # Full ping-pong AND not a DELETED event → the log is entirely redundant.
                if not existing_log.new_values and action_type != 'DELETED':
                    existing_log.delete()
                    
                    # Restore updated_in_version to its previous published state (if any),
                    # rather than blindly setting it to None.
                    last_published_update = Changelog.objects.filter(
                        food=self,
                        version__is_published=True,
                        action__in=['UPDATED', 'DELETED']
                    ).order_by('-version_id').first()
                    
                    restore_version_id = last_published_update.version_id if last_published_update else None
                    Food.objects.filter(pk=self.pk).update(updated_in_version_id=restore_version_id)
                else:
                    existing_log.save()
            else:
                # First edit of this food in this draft version → create a fresh log.
                old_vals = {k: v[0] for k, v in changed_data.items()}
                new_vals = {k: v[1] for k, v in changed_data.items()}
                Changelog.objects.create(
                    food=self, version=draft_version,
                    action=action_type,
                    old_values=old_vals,
                    new_values=new_vals,
                )

    def delete(self, *args, **kwargs):
        # 1. Block any delete call that doesn't explicitly pass our secret flag
        hard_delete_flag = kwargs.pop('from_hard_delete_action', False)
        if not hard_delete_flag:
            raise ValueError(
                "Direct deletions are disabled. You must use the admin "
                "'hard_delete_with_warning' action to remove items safely."
            )

        # 2. Even with the flag, enforce the draft-only database rules
        from .models import DbVersion 
        try:
            draft_version = DbVersion.objects.get(is_published=False)
            is_in_draft = (self.created_in_version_id == draft_version.pk)
        except DbVersion.DoesNotExist:
            is_in_draft = False

        if self.created_in_version is None and draft_version and draft_version.version == 1:
            is_in_draft = True

        if not is_in_draft and (self.created_in_version is not None or self.updated_in_version is not None):
             raise ValueError("Nelze trvale smazat publikovanou potravinu. Použijte soft-delete (is_active=False).")
             
        return super().delete(*args, **kwargs)
    
    def _is_new_record(self) -> bool:
        """True if this instance has no pk yet (i.e. INSERT not UPDATE)."""
        return self.pk is None

    def clean(self):
        """
        Validates that soft-delete (is_active=False) is not applied to a food
        that was born in the current open draft version.
        Foods born in a draft can only be hard-deleted (they were never published).
        """
        super().clean()
        if not self.is_active:
            try:
                draft_version = DbVersion.objects.get(is_published=False)
            except DbVersion.DoesNotExist:
                return  # No open draft — nothing to validate.

            if self.pk is None:
                raise ValidationError({
                    'is_active': 'A newly added food item cannot be hidden immediately.'
                })
            else:
                # Use created_in_version to decide whether this food was born in the current draft.
                if self.created_in_version_id == draft_version.pk:
                    raise ValidationError({
                        'is_active': (
                            f'This food item cannot be hidden because it was created in the '
                            f'current open version ({draft_version}). '
                            f'Publish the version first, or hard-delete this item instead.'
                        )
                    })


class SyncArtifact(models.Model):
    """
    Stores metadata for the binary sync artifacts (snapshot .db.gz and delta .json)
    that are physically hosted on Cloudflare R2.

    Django never serves these files itself — it only reads this table to build
    public download URLs and to supply file_size_bytes / checksum to mobile clients.

    One row per (version, artifact_type) pair.
    """
    SNAPSHOT = 'snapshot'
    DELTA = 'delta'
    ARTIFACT_TYPE_CHOICES = [
        (SNAPSHOT, 'Snapshot'),
        (DELTA, 'Delta'),
    ]

    version = models.ForeignKey(
        DbVersion,
        on_delete=models.CASCADE,
        related_name='sync_artifacts',
    )
    artifact_type = models.CharField(max_length=10, choices=ARTIFACT_TYPE_CHOICES)

    # For deltas only: the version the client must be on to apply this delta.
    from_version = models.IntegerField(null=True, blank=True)

    # Populated after the file is uploaded to R2.
    file_size_bytes = models.BigIntegerField(null=True, blank=True)
    checksum = models.CharField(max_length=255, null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['version', 'artifact_type', 'from_version'],
                name='unique_sync_artifact',
            )
        ]

    def __str__(self):
        if self.artifact_type == self.DELTA:
            return f"Delta v{self.from_version}→v{self.version_id}"
        return f"Snapshot v{self.version_id}"


class Changelog(models.Model):
    """
    Records the delta (changes) of foods across database versions.
    Acts as the source of truth for historical data and allows data rollbacks.
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
    # Fields changed, stored as their values at the START of this version
    # (used for rollback / reverting to previous state).
    old_values = models.JSONField(default=dict, blank=True)
    # Fields changed, stored as their values at the END of this version
    # (sent to mobile clients as the delta for this version).
    new_values = models.JSONField(default=dict, blank=True)

    class Meta:
        constraints = [
            # At most one changelog entry per (food, version) pair.
            models.UniqueConstraint(
                fields=['food', 'version'],
                name='unique_changelog_per_food_version',
            )
        ]

    def __str__(self):
        return f"{self.get_action_display()} - {self.food.name}"
