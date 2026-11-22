from django.contrib import admin, messages
from django.shortcuts import render
from django.contrib.admin import helpers
from django.http import HttpResponseRedirect
from django.urls import path, reverse
from django.db import transaction
from .models import Food, DbVersion, Changelog
from .services.etl import run_food_etl


@admin.register(DbVersion)
class DbVersionAdmin(admin.ModelAdmin):
    list_display = ('version', 'is_published', 'created_at')
    list_filter = ('is_published',)
    ordering = ('-version',)

    def has_add_permission(self, request):
        # Versions are created automatically via Food.save(); prevent manual creation.
        return False


@admin.register(Food)
class FoodAdmin(admin.ModelAdmin):
    list_display = ('name', 'ean', 'kcal_per_100', 'is_active', 'updated_in_version')
    search_fields = ('name', 'ean')
    list_filter = ('is_active', 'updated_in_version')
    # Version FK fields must not be editable directly in the admin form.
    readonly_fields = ('updated_in_version', 'created_in_version')
    change_list_template = 'admin/foods/food/change_list.html'
    actions = ['soft_delete_foods', 'hard_delete_with_warning']

    @admin.action(description="Soft-delete (Skrýt vybrané potraviny)")
    def soft_delete_foods(self, request, queryset):
        """
        Soft-deletes foods by setting is_active=False.
        Validates that only foods born in a *published* version can be soft-deleted.
        Foods born in the current open draft must be hard-deleted instead.
        """
        try:
            draft_version = DbVersion.objects.get(is_published=False)
        except DbVersion.DoesNotExist:
            draft_version = None

        count = 0
        blocked = 0
        for food in queryset:
            # Block soft-delete for foods created in the current open draft.
            if draft_version and food.created_in_version_id == draft_version.pk:
                blocked += 1
                continue

            food.is_active = False
            try:
                food.full_clean()   # Run model-level validation (including clean())
            except Exception:
                blocked += 1
                continue
            food.save()
            count += 1

        if count:
            self.message_user(request, f"Skryto {count} potravin.", messages.SUCCESS)
        if blocked:
            self.message_user(
                request,
                f"{blocked} potravin nebylo skryto, protože byly vytvořeny v aktuální otevřené verzi. "
                f"Použijte Trvalé smazání.",
                messages.WARNING,
            )

    @admin.action(description="Hard-delete (TRVALÉ SMAZÁNÍ - NEBEZPEČNÉ!)")
    def hard_delete_with_warning(self, request, queryset):
        """
        Permanently deletes foods. Only allowed for foods born in the current open draft
        (they have never been published, so there is no history to protect).
        Foods from published versions must be soft-deleted instead.
        """
        try:
            draft_version = DbVersion.objects.get(is_published=False)
        except DbVersion.DoesNotExist:
            draft_version = None

        # Partition the queryset: deletable vs blocked.
        deletable = []
        blocked_names = []
        for food in queryset:
            if draft_version and food.created_in_version_id == draft_version.pk:
                # Born in current draft — safe to hard-delete (never published).
                deletable.append(food)
            elif food.created_in_version is None and draft_version and draft_version.version == 1:
                # Genesis food (created before versioning) being removed still inside V1.
                deletable.append(food)
            else:
                blocked_names.append(str(food))

        if blocked_names:
            self.message_user(
                request,
                f"Nelze trvale smazat: {', '.join(blocked_names)}. "
                f"Tyto potraviny existují v publikovaných verzích – použijte Skrýt.",
                messages.ERROR,
            )
            if not deletable:
                return

        if 'apply' in request.POST:
            with transaction.atomic():
                for food in deletable:
                    # Pass the flag to prove this is the authorized admin action
                    food.delete(from_hard_delete_action=True)
            self.message_user(
                request,
                f"Nenávratně smazáno {len(deletable)} potravin.",
                messages.SUCCESS,
            )
            return

        # First pass: show confirmation page before destructive action.
        context = {
            'queryset': deletable,
            'blocked': blocked_names,
            'action_checkbox_name': helpers.ACTION_CHECKBOX_NAME,
        }
        return render(request, 'admin/hard_delete_confirmation.html', context)

    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path(
                'run-etl/',
                self.admin_site.admin_view(self.run_etl_view),
                name='foods_food_run_etl',
            ),
        ]
        return custom_urls + urls

    def run_etl_view(self, request):
        if request.method != 'POST':
            return HttpResponseRedirect(reverse('admin:foods_food_changelist'))
        try:
            stats = run_food_etl()
            self.message_user(
                request,
                f"Import z OpenFoodFacts dokončen – vytvořeno: {stats['created']}, "
                f"upraveno: {stats['updated']}, beze změny: {stats['skipped']}, "
                f"zahozeno nevalidních: {stats['invalid']}.",
                level=messages.SUCCESS,
            )
        except Exception as exc:
            self.message_user(request, f"Chyba při spuštění importu: {exc}", level=messages.ERROR)
        return HttpResponseRedirect(reverse('admin:foods_food_changelist'))
    
    def get_actions(self, request):
        actions = super().get_actions(request)
        if 'delete_selected' in actions:
            del actions['delete_selected']
        return actions

    def has_delete_permission(self, request, obj=None):
        # obj is None when viewing the main list page. Return True so checkboxes appear.
        if obj is None:
            return True
            
        # obj is populated when viewing a specific food item. 
        # Only show the red Delete button if the food was born in the current draft.
        try:
            draft_version = DbVersion.objects.get(is_published=False)
            is_in_draft = (obj.created_in_version_id == draft_version.pk)
        except DbVersion.DoesNotExist:
            is_in_draft = False

        if obj.created_in_version is None and draft_version and draft_version.version == 1:
            is_in_draft = True
            
        return is_in_draft


@admin.register(Changelog)
class ChangelogAdmin(admin.ModelAdmin):
    list_display = ('food', 'action', 'version', 'old_values', 'new_values')
    list_filter = ('action', 'version')
    search_fields = ('food__name',)

    # Changelog entries are an audit trail — they must not be manually created or edited.
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    # Allow deletion (with Django's built-in confirmation) so admins can clean up mistakes.
    def has_delete_permission(self, request, obj=None):
        return True
