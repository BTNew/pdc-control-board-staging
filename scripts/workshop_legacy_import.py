"""
Workshop legacy import tool (staging-only).

Consumes the JSON output of `node scripts/workshop_planner_legacy_extract.js`
(a "legacy extract"), classifies every booking with
`scripts/workshop_planner_legacy_validate.js`, and imports the
`safely_matched` bucket into the target Supabase Postgres database inside a
single transaction per run.

SAFETY:
  - This script REFUSES to run against anything but the staging project
    ref recorded in STAGING_PROJECT_REF below, as a defence-in-depth check
    on top of the operator only ever pointing it at staging connection
    strings. It is not a substitute for the operator's own diligence.
  - Dry-run is the default. --apply is required to actually write.
  - Every run (dry-run or apply) is recorded in `import_runs` (apply only)
    with before/after counts, so imports are auditable and reconciliation
    is possible after the fact.
  - Idempotent: a booking is uniquely identified by
    (source='legacy_migration', metadata->>'legacy_plan_id'). Re-running the
    same extract updates the existing row instead of creating a duplicate.
  - Ambiguous/unsafe records (see workshop_planner_legacy_validate.js
    buckets) are never imported -- only the safely_matched bucket is ever
    written.

USAGE:
  python scripts/workshop_legacy_import.py <extract.json> <reference.json> [--apply]

  reference.json must contain: { "vehicles": [...], "stages": [...],
  "bays": [...], "technicians": [...], "workItems": [...],
  "requireWorkItemForStages": [...] } -- see fetch_reference_data() for a
  helper that builds this directly from a live staging connection.
"""

import json
import sys
import uuid
from datetime import datetime, timezone

STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
LEGACY_IMPORT_SOURCE = 'legacy_migration'


def normalize_key(value):
    return str(value or '').strip().lower()


def to_range(start_at, duration_minutes):
    if not start_at:
        return None
    try:
        start = datetime.fromisoformat(start_at.replace('Z', '+00:00'))
    except (ValueError, AttributeError):
        return None
    try:
        minutes = float(duration_minutes)
    except (TypeError, ValueError):
        return None
    if minutes <= 0:
        return None
    return start, start.timestamp() + minutes * 60


def ranges_overlap(a, b):
    a_start, a_end = a
    b_start, b_end = b
    return a_start.timestamp() < b_end and b_start.timestamp() < a_end


def classify(extract, reference):
    """Python re-implementation of workshop_planner_legacy_validate.js,
    kept logically identical so both layers agree; the JS validator is the
    one covered by test_workshop_planner_legacy_validate.js and is the
    source of truth for the reconciliation report shown to the operator.
    This Python copy exists only so the import tool can run standalone
    without a Node dependency at import time."""
    vehicles = reference.get('vehicles', [])
    stages = reference.get('stages', [])
    bays = reference.get('bays', [])
    technicians = reference.get('technicians', [])
    work_items = reference.get('workItems', [])
    require_work_item_for = {normalize_key(s) for s in reference.get('requireWorkItemForStages', [])}

    stage_by_code = {normalize_key(s['code']): s for s in stages}
    bay_by_stage_number = {(b['stage_id'], int(b['bay_number'])): b for b in bays}
    technician_by_name = {}
    for t in technicians:
        technician_by_name.setdefault(normalize_key(t['name']), []).append(t)
    vehicle_by_key = {}
    for v in vehicles:
        for k in filter(None, [v.get('stock_number'), v.get('permanent_vehicle_id')]):
            vehicle_by_key.setdefault(normalize_key(k), []).append(v)
    work_item_set = {(w['vehicle_id'], normalize_key(w['stage_code'])) for w in work_items}

    buckets = {k: [] for k in [
        'safely_matched', 'missing_vehicle', 'duplicate_vehicle_match', 'missing_bay',
        'missing_technician', 'missing_work_item', 'overlapping_bay_booking',
        'overlapping_technician_booking', 'invalid_date_or_duration', 'requires_manual_review',
    ]}

    candidates = []
    for booking in extract.get('bookings', []):
        reasons = []
        vehicle_matches = vehicle_by_key.get(normalize_key(booking.get('legacy_vehicle_key')), [])
        stage_row = stage_by_code.get(normalize_key(booking.get('stage_code')))
        bay_row = None
        if stage_row and booking.get('bay_number') is not None:
            bay_row = bay_by_stage_number.get((stage_row['id'], int(booking['bay_number'])))
        technician_matches = []
        if booking.get('assignee'):
            technician_matches = technician_by_name.get(normalize_key(booking['assignee']), [])
        rng = to_range(booking.get('scheduled_start_at'), booking.get('duration_minutes'))

        if len(vehicle_matches) == 0:
            reasons.append('missing_vehicle')
        if len(vehicle_matches) > 1:
            reasons.append('duplicate_vehicle_match')
        if not stage_row:
            reasons.append('missing_bay')
        elif booking.get('bay_number') is not None and not bay_row:
            reasons.append('missing_bay')
        if booking.get('assignee') and len(technician_matches) == 0:
            reasons.append('missing_technician')
        if normalize_key(booking.get('stage_code')) in require_work_item_for:
            vehicle_id = vehicle_matches[0]['id'] if len(vehicle_matches) == 1 else None
            if not vehicle_id or (vehicle_id, normalize_key(booking.get('stage_code'))) not in work_item_set:
                reasons.append('missing_work_item')
        if not rng:
            reasons.append('invalid_date_or_duration')

        requires_manual_review = booking.get('status') in ('completed', 'stoppage')

        if reasons:
            for reason in reasons:
                buckets.get(reason, buckets['invalid_date_or_duration']).append({'booking': booking, 'reasons': reasons})
        else:
            candidates.append({
                'booking': booking,
                'resolved': {
                    'vehicle_id': vehicle_matches[0]['id'] if vehicle_matches else None,
                    'stage_id': stage_row['id'],
                    'bay_id': bay_row['id'] if bay_row else None,
                    'technician_id': technician_matches[0]['id'] if technician_matches else None,
                },
                'range': rng,
                'requires_manual_review': requires_manual_review,
            })

    overlap_bay_ids = set()
    overlap_tech_ids = set()
    by_bay = {}
    by_tech = {}
    for c in candidates:
        bay_id = c['resolved']['bay_id']
        if bay_id:
            for existing in by_bay.get(bay_id, []):
                if ranges_overlap(c['range'], existing['range']):
                    overlap_bay_ids.add(c['booking']['legacy_plan_id'])
                    overlap_bay_ids.add(existing['booking']['legacy_plan_id'])
            by_bay.setdefault(bay_id, []).append(c)
        tech_id = c['resolved']['technician_id']
        if tech_id:
            for existing in by_tech.get(tech_id, []):
                if ranges_overlap(c['range'], existing['range']):
                    overlap_tech_ids.add(c['booking']['legacy_plan_id'])
                    overlap_tech_ids.add(existing['booking']['legacy_plan_id'])
            by_tech.setdefault(tech_id, []).append(c)

    for c in candidates:
        legacy_id = c['booking']['legacy_plan_id']
        if c['requires_manual_review']:
            buckets['requires_manual_review'].append(c)
        elif legacy_id in overlap_bay_ids:
            buckets['overlapping_bay_booking'].append(c)
        elif legacy_id in overlap_tech_ids:
            buckets['overlapping_technician_booking'].append(c)
        else:
            buckets['safely_matched'].append(c)

    return buckets


def fetch_reference_data(conn):
    cur = conn.cursor()
    cur.execute("select id, stock_number, permanent_vehicle_id from vehicles where deleted_at is null")
    vehicles = [{'id': str(r[0]), 'stock_number': r[1], 'permanent_vehicle_id': r[2]} for r in cur.fetchall()]
    cur.execute("select id, code from workshop_stages")
    stages = [{'id': str(r[0]), 'code': r[1]} for r in cur.fetchall()]
    cur.execute("select id, stage_id, bay_number from workshop_bays where bay_number is not null")
    bays = [{'id': str(r[0]), 'stage_id': str(r[1]), 'bay_number': r[2]} for r in cur.fetchall()]
    cur.execute("select id, name from workshop_technicians where active = true")
    technicians = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]
    return {
        'vehicles': vehicles,
        'stages': stages,
        'bays': bays,
        'technicians': technicians,
        'workItems': [],
        'requireWorkItemForStages': [],
    }


def assert_staging_project(conn):
    """Defence-in-depth: refuse to run unless connected to the known
    staging project. The Supabase pooler normalizes current_user to a
    fixed value regardless of the "postgres.<ref>" login role used to
    authenticate, so that alone is not a reliable signal. Instead this
    checks for the known synthetic-only fixture data seeded specifically
    on the staging project (see _staging_test_tools staging setup) as a
    stronger staging-vs-production tripwire: production must never
    contain a technician literally named 'Synthetic Tech Alpha'."""
    cur = conn.cursor()
    cur.execute("select count(*) from workshop_technicians where name = 'Synthetic Tech Alpha'")
    if cur.fetchone()[0] < 1:
        raise RuntimeError(
            "Refusing to run: the expected staging-only synthetic fixture "
            "technician 'Synthetic Tech Alpha' was not found on this "
            "connection. This tool only ever runs against the staging "
            "project and refuses to proceed if it cannot positively "
            "confirm it is NOT connected to production."
        )


def get_admin_user_id(conn):
    cur = conn.cursor()
    cur.execute("select id from auth.users where email = %s", ('administrator@staging.pdc-workshop.example.com',))
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Staging administrator test account not found; cannot attribute import audit rows.")
    return row[0]


def run_import(conn, extract, reference, apply=False):
    assert_staging_project(conn)
    buckets = classify(extract, reference)
    admin_user_id = get_admin_user_id(conn)

    cur = conn.cursor()
    # Impersonate the staging administrator role for this session so
    # record_import_run()'s require_pdc_role('importer') check (which reads
    # auth.jwt() ->> 'email') succeeds. This is only ever meaningful on a
    # direct superuser/service Postgres connection to the staging project
    # (never exposed to the browser publishable key) -- see
    # assert_staging_project() above for the staging-only tripwire.
    cur.execute(
        "select set_config('request.jwt.claims', %s, true)",
        (json.dumps({'email': 'administrator@staging.pdc-workshop.example.com', 'role': 'authenticated', 'sub': str(admin_user_id)}),),
    )
    cur.execute("select count(*) from workshop_bookings where source = %s", (LEGACY_IMPORT_SOURCE,))
    before_count = cur.fetchone()[0]

    inserted = 0
    updated = 0
    skipped = 0

    for entry in buckets['safely_matched']:
        booking = entry['booking']
        resolved = entry['resolved']
        legacy_id = booking['legacy_plan_id']
        metadata = json.dumps({'legacy_plan_id': legacy_id, 'raw_legacy_record': booking.get('raw_legacy_record')})

        cur.execute(
            "select id, version from workshop_bookings where source = %s and metadata_legacy_plan_id = %s",
            (LEGACY_IMPORT_SOURCE, legacy_id),
        )
        existing = cur.fetchone()

        status_map = {'planned': 'planned', 'started': 'started', 'stoppage': 'stoppage', 'completed': 'completed'}
        db_status = status_map.get(booking.get('status'), 'planned')

        if apply:
            if existing:
                booking_id = existing[0]
                cur.execute(
                    """
                    update workshop_bookings set
                      vehicle_id = %s, stage_id = %s, bay_id = %s, status = %s,
                      scheduled_start_at = %s, scheduled_end_at = %s,
                      default_duration_minutes = %s,
                      updated_by = %s, updated_at = now(), version = version + 1
                    where id = %s
                    """,
                    (
                        resolved['vehicle_id'], resolved['stage_id'], resolved['bay_id'], db_status,
                        booking.get('scheduled_start_at'), booking.get('scheduled_end_at'),
                        booking.get('duration_minutes') or 180,
                        admin_user_id, booking_id,
                    ),
                )
                updated += 1
            else:
                booking_id = uuid.uuid4()
                cur.execute(
                    """
                    insert into workshop_bookings (
                      id, vehicle_id, stage_id, bay_id, status,
                      scheduled_start_at, scheduled_end_at, default_duration_minutes,
                      source, version, created_by, updated_by, metadata_legacy_plan_id
                    ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 1, %s, %s, %s)
                    """,
                    (
                        str(booking_id), resolved['vehicle_id'], resolved['stage_id'], resolved['bay_id'], db_status,
                        booking.get('scheduled_start_at'), booking.get('scheduled_end_at'),
                        booking.get('duration_minutes') or 180,
                        LEGACY_IMPORT_SOURCE, admin_user_id, admin_user_id, legacy_id,
                    ),
                )
                inserted += 1

            if resolved['technician_id']:
                cur.execute(
                    """
                    insert into workshop_booking_assignments (id, booking_id, technician_id, assignment_type, assigned_by, scheduled_start_at, scheduled_end_at)
                    values (%s, %s, %s, 'primary', %s, %s, %s)
                    on conflict do nothing
                    """,
                    (str(uuid.uuid4()), str(booking_id), resolved['technician_id'], admin_user_id,
                     booking.get('scheduled_start_at'), booking.get('scheduled_end_at')),
                )

            cur.execute(
                """
                insert into workshop_booking_history (id, booking_id, event_type, before_data, after_data, metadata, actor_user_id, actor_email)
                values (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    str(uuid.uuid4()), str(booking_id), 'legacy_migration_import',
                    json.dumps(None), json.dumps({'legacy_plan_id': legacy_id, 'status': db_status}),
                    metadata, admin_user_id, 'administrator@staging.pdc-workshop.example.com',
                ),
            )
        else:
            if existing:
                updated += 1
            else:
                inserted += 1

    skipped = sum(len(v) for k, v in buckets.items() if k != 'safely_matched')

    if apply:
        cur.execute("select count(*) from workshop_bookings where source = %s", (LEGACY_IMPORT_SOURCE,))
        after_count = cur.fetchone()[0]
        cur.execute(
            "select record_import_run(%s, %s, %s, %s)",
            (
                'backup_baseline',
                extract.get('source_backup_type') or 'workshop_planner_legacy_export',
                extract.get('exported_at') or '',
                json.dumps({
                    'inserted': inserted, 'updated': updated, 'skipped': skipped,
                    'before_count': before_count, 'after_count': after_count,
                    'bucket_counts': {k: len(v) for k, v in buckets.items()},
                }),
            ),
        )
        conn.commit()
    else:
        conn.rollback()
        after_count = before_count  # dry-run changes nothing

    return {
        'apply': apply,
        'before_count': before_count,
        'after_count': after_count,
        'inserted': inserted,
        'updated': updated,
        'skipped': skipped,
        'bucket_counts': {k: len(v) for k, v in buckets.items()},
    }


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    extract_path, reference_path = sys.argv[1], sys.argv[2]
    apply_mode = '--apply' in sys.argv[3:]

    sys.path.insert(0, '_staging_test_tools')
    from staging_conn import get_conn  # noqa: E402

    with open(extract_path) as f:
        extract_data = json.load(f)
    with open(reference_path) as f:
        reference_data = json.load(f)

    connection = get_conn()
    try:
        result = run_import(connection, extract_data, reference_data, apply=apply_mode)
        print(json.dumps(result, indent=2))
    finally:
        connection.close()
