from django.contrib import admin, messages
from django.shortcuts import render
from django.contrib.admin import helpers
from django.http import HttpResponseRedirect
from django.urls import path, reverse
from .models import Food, DbVersion, Changelog
from .services import run_food_etl

@admin.register(DbVersion)
class DbVersionAdmin(admin.ModelAdmin):
    list_display = ('version', 'is_published', 'created_at')
    list_filter = ('is_published',)
    ordering = ('-version',)

@admin.register(Food)
class FoodAdmin(admin.ModelAdmin):
    list_display = ('name', 'ean', 'kcal_per_100', 'is_active', 'updated_in_version')
    search_fields = ('name', 'ean')
    list_filter = ('is_active', 'updated_in_version')

    readonly_fields = ('updated_in_version',)
    change_list_template = 'admin/foods/food/change_list.html' 
    
    actions = ['soft_delete_foods', 'hard_delete_with_warning']

    @admin.action(description="Soft-delete (Skrýt vybrané potraviny)")
    def soft_delete_foods(self, request, queryset):
        """
        Iterates over items and calls .save() to automatically trigger the Changelog.
        """
        count = 0
        for food in queryset:
            food.is_active = False
            food.save()
            count += 1
            
        self.message_user(request, f"Vybrané potraviny ({count}) byly skryty.")

    @admin.action(description="Hard-delete (TRVALÉ SMAZÁNÍ - NEBEZPEČNÉ!)")
    def hard_delete_with_warning(self, request, queryset):
        """Akce s mezikrokem pro potvrzení fatálních následků."""
        # Pokud formulář z naší varovné stránky obsahuje pole 'apply', mažeme
        if 'apply' in request.POST:
            count = queryset.count()
            queryset.delete()  # Fyzické smazání z databáze
            self.message_user(request, f"Nenávratně smazáno {count} potravin.")
            return

        # Pokud 'apply' chybí, zobrazíme varovnou HTML stránku
        context = {
            'queryset': queryset,
            'action_checkbox_name': helpers.ACTION_CHECKBOX_NAME, # Předá ID vybraných položek
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
            self.message_user(
                request,
                f"Chyba při spuštění importu: {exc}",
                level=messages.ERROR,
            )

        return HttpResponseRedirect(reverse('admin:foods_food_changelist'))

@admin.register(Changelog)
class ChangelogAdmin(admin.ModelAdmin):
    list_display = ('food', 'action', 'version', 'old_values', 'new_values')
    list_filter = ('action', 'version')
    search_fields = ('food__name',)