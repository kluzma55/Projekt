from django.contrib.auth.models import AbstractUser
from django.db import models

class User(AbstractUser):
    """
    Custom user model extending Django's built-in authentication system.
    """
    email = models.EmailField(unique=True)
    # Flag to determine if the user has purchased a premium/ad-free subscription.
    is_ad_free = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.username
    
class Backup(models.Model):
    """
    Stores references to user diary backups.
    Since the diary is primarily stored offline on the device, 
    this tracks the backup files uploaded to the server (e.g., Cloudflare R2).
    """
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    # Path or key to the actual SQLite backup file stored in the cloud bucket.
    backup_file = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Záloha {self.id} ({self.user.username})"