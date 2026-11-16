"""Django adapter for the Food/DbVersion/Changelog catalogue."""
from contextlib import contextmanager
from pathlib import Path

from django.conf import settings
from django.db import connection, transaction
from django.db.models import Exists, OuterRef

from ..models import Changelog, DbVersion, Food
from .sync_core import STATE_FIELDS, normalize_row, rewind, build_delta, write_delta, write_snapshot


def output_directory(output_dir=None):
    return Path(output_dir if output_dir is not None else
                getattr(settings, 'SYNC_EXPORT_DIR', Path(settings.BASE_DIR) / 'exports'))


@contextmanager
def consistent_read():
    # PostgreSQL: all reads in an export see the same database snapshot.
    # Call from outside an existing transaction for that guarantee.
    outermost = not connection.in_atomic_block
    with transaction.atomic():
        if outermost and connection.vendor == 'postgresql':
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        yield


def published_version(version=None):
    versions = DbVersion.objects.filter(is_published=True)
    if version is not None:
        versions = versions.filter(version=version)
    result = versions.order_by('-version').first()
    if result is None:
        raise ValueError('No matching published database version')
    return result.version


def validate_history():
    # A draft earlier than a published version cannot be safely replayed.
    latest = published_version()
    if DbVersion.objects.filter(is_published=False, version__lt=latest).exists():
        raise ValueError('Unpublished version precedes the latest published version')


def reverse_logs(queryset):
    prior = Changelog.objects.filter(food_id=OuterRef('food_id'),
                                     version_id__lt=OuterRef('version_id'))
    return (queryset.annotate(has_prior_history=Exists(prior))
            .order_by('-version_id', '-pk')
            .values('food_id', 'action', 'old_values', 'has_prior_history')
            .iterator(chunk_size=2000))


def read_foods(queryset):
    return {row['id']: normalize_row(row) for row in
            queryset.values(*STATE_FIELDS).iterator(chunk_size=2000)}


def export_delta(from_version, to_version=None, output_dir=None):
    """Export net changes between any two existing published versions."""
    with consistent_read():
        validate_history()
        start = published_version(from_version)
        end = published_version(to_version)
        if start > end:
            raise ValueError('from_version must be <= to_version')
        interval = Changelog.objects.filter(version_id__gt=start, version_id__lte=end)
        ids = interval.order_by().values('food_id').distinct()
        after = read_foods(Food.objects.filter(pk__in=ids))
        # The server Food table can include changes newer than end (even a draft).
        rewind(after, reverse_logs(Changelog.objects.filter(
            food_id__in=ids, version_id__gt=end)))
        before = {key: row.copy() for key, row in after.items()}
        rewind(before, reverse_logs(interval))
        payload = build_delta(before, after, start, end)
    return write_delta(payload, output_directory(output_dir))


def export_snapshot(output_dir=None):
    """Export the latest published catalogue, excluding unpublished edits."""
    with consistent_read():
        validate_history()
        version = published_version()
        states = read_foods(Food.objects.all())
        rewind(states, reverse_logs(Changelog.objects.filter(version_id__gt=version)))
    return write_snapshot((states[key] for key in sorted(states)), version,
                          output_directory(output_dir))
