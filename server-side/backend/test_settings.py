# test_settings.py
# ---------------------------------------------------------------------------
# A minimal settings override for running tests with SQLite in-memory instead
# of the production PostgreSQL database.  Use with:
#
#   python manage.py test foods --settings=backend.test_settings --verbosity=2
# ---------------------------------------------------------------------------
from .settings import *  # noqa: F401, F403  (import everything from main settings)

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}
