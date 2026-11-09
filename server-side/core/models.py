from django.db import models
from django.conf import settings
from foods.models import Food

class BugReport(models.Model):
    """
    Represents a bug report or data correction request submitted by a user.
    Allows users to report incorrect food data or application bugs.
    """
    STATUS_CHOICES = [
        ('NEW', 'Nová'),
        ('IN_PROGRESS', 'V řešení'),
        ('RESOLVED', 'Vyřešeno'),
        ('REJECTED', 'Zamítnuto'),
    ]
    CATEGORY_CHOICES = [
        ('BAD_DATA', 'Chybná data potraviny'),
        ('APP_BUG', 'Chyba aplikace'),
        ('OTHER', 'Jiné'),
    ]
    # The user who submitted the report. Nullable in case the user deleted/unregistered users.
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    # The specific food item being reported (if the bug relates to bad food data).
    food = models.ForeignKey(Food, on_delete=models.SET_NULL, null=True, blank=True)
    category = models.CharField(max_length=50, choices=CATEGORY_CHOICES)
    description = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='NEW')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Chyba {self.id} - {self.get_status_display()}"