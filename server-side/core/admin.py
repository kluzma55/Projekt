from django.contrib import admin
from .models import BugReport

@admin.register(BugReport)
class BugReportAdmin(admin.ModelAdmin):
    list_display = ('id', 'category', 'status', 'user', 'food', 'created_at')
    list_filter = ('status', 'category', 'created_at')
    search_fields = ('description', 'user__username', 'food__name')
    list_editable = ('status',)