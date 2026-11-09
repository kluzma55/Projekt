from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Backup

@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display = ('username', 'email', 'is_ad_free', 'is_staff', 'created_at')
    list_filter = ('is_ad_free', 'is_staff', 'is_superuser', 'is_active')
    search_fields = ('username', 'email')
    
    fieldsets = UserAdmin.fieldsets + (
        ('Prémiové funkce', {'fields': ('is_ad_free',)}),
    )

@admin.register(Backup)
class BackupAdmin(admin.ModelAdmin):
    list_display = ('id', 'user', 'created_at', 'backup_file')
    search_fields = ('user__username', 'user__email')
    list_filter = ('created_at',)