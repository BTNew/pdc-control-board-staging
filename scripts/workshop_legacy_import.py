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
  - Every committed apply is recorded in `import_runs`; an exact replay
    returns the completed receipt without repeating operational writes
    with before/after counts, so imports are auditable and reconciliation
    is possible after the fact.
  - Idempotent: a booking is uniquely identified by
    (source='legacy_migration', metadata->>'legacy_plan_id'). Re-running the
    same extract updates the existing row instead of creating a duplicate.
  - Ambiguous/unsafe records (see workshop_planner_legacy_validate.js
    buckets) are never imported -- only the safely_matched bucket is ever
    written.

USAGE:
  python scripts/workshop_legacy_import.py <extract.json> <reference.json>
      [--apply] [--vehicle-export-rollback]

  reference.json must contain the strict C2b envelope:
  { "vehicleIdentityArtifact": {"schema_version": "pdc.workshop.vehicle-reference/v2", ...},
    "stages": [...], "bays": [...], "technicians": [...], "workItems": [...],
    "requireWorkItemForStages": [...] } -- see fetch_reference_data().

  The prior {"vehicles": [...], "vehicleIdentityExport": {...}} envelope is
  disabled by default and accepted only with the explicit staging/test
  --vehicle-export-rollback compatibility flag plus exact revision validation.
"""

import hashlib
import json
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from workshop_vehicle_reference_artifact import (
    ARTIFACT_SCHEMA_VERSION,
    VehicleReferenceArtifactError,
    VehicleReferenceArtifactStale,
    build_vehicle_reference_artifact,
    parse_workshop_reference,
)

STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd'
LEGACY_IMPORT_SOURCE = 'legacy_migration'
WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED = True
VEHICLE_IDENTITY_EXPORT_RPC = 'export_workshop_legacy_vehicle_identities'
VEHICLE_IDENTITY_EXPORT_MAX_PAGE_SIZE = 500


class VehicleIdentityExportError(RuntimeError):
    pass


class VehicleIdentityExportStale(VehicleIdentityExportError):
    pass


class VehicleIdentityExportInvalid(VehicleIdentityExportError):
    pass


def normalize_key(value):
    return str(value or '').strip().lower()


def normalize_vehicle_stock_number(value):
    normalized = re.sub(r'[\s-]+', '', str(value or '').strip().upper())
    return normalized or None


def is_real_vehicle_stock_number(value):
    normalized = normalize_vehicle_stock_number(value)
    raw = str(value or '').strip().upper()
    return bool(
        normalized
        and normalized not in {'0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED'}
        and not any(raw.startswith(prefix) for prefix in ('NEW-', 'PD-', 'PENDING-', 'TEMP-'))
    )


def normalize_vehicle_vin(value):
    normalized = re.sub(r'[\s-]+', '', str(value or '').strip().upper())
    return normalized or None


def is_valid_vehicle_vin(value):
    return bool(re.fullmatch(r'[A-HJ-NPR-Z0-9]{17}', normalize_vehicle_vin(value) or ''))


def normalize_vehicle_source_identifier(value):
    normalized = str(value or '').strip().upper()
    return normalized or None


def _legacy_identity_forms(value):
    forms = set()
    if is_real_vehicle_stock_number(value):
        forms.add(('stock_number', normalize_vehicle_stock_number(value)))
    if is_valid_vehicle_vin(value):
        forms.add(('vin', normalize_vehicle_vin(value)))
    source_value = normalize_vehicle_source_identifier(value)
    if source_value:
        for identifier_type in (
            'job_card_number', 'permanent_vehicle_id',
            'toyota_order_number', 'source_record_id',
        ):
            forms.add((identifier_type, source_value))
    return forms


def _legacy_vehicle_record(item):
    vehicle_id = str(item.get('vehicle_id') or item.get('id') or '')
    return {
        **item,
        'id': vehicle_id,
        'vehicle_id': vehicle_id,
        'version': int(item.get('version') or 1),
        'is_archived': bool(item.get('is_archived', False)),
    }


def _vehicle_claims(item):
    claims = list(item.get('identifiers') or [])
    if not claims:
        if item.get('stock_number') and is_real_vehicle_stock_number(item.get('stock_number')):
            claims.append({
                'identifier_type': 'stock_number',
                'normalized_value': normalize_vehicle_stock_number(item.get('stock_number')),
                'value': item.get('stock_number'), 'origin': 'rollback', 'source_system': None,
            })
        if item.get('permanent_vehicle_id'):
            claims.append({
                'identifier_type': 'permanent_vehicle_id',
                'normalized_value': normalize_vehicle_source_identifier(item.get('permanent_vehicle_id')),
                'value': item.get('permanent_vehicle_id'), 'origin': 'rollback', 'source_system': None,
            })
    return claims


def build_vehicle_identity_index(vehicles, conflicts=None):
    by_claim = {}
    evidence_by_claim = {}
    by_id = {}
    for raw_item in vehicles:
        item = _legacy_vehicle_record(raw_item)
        vehicle_id = item['id']
        if not vehicle_id:
            raise VehicleIdentityExportInvalid('vehicle export item has no canonical UUID')
        if vehicle_id in by_id:
            raise VehicleIdentityExportInvalid(f'duplicate vehicle UUID in export: {vehicle_id}')
        by_id[vehicle_id] = item
        for claim in _vehicle_claims(item):
            identifier_type = str(claim.get('identifier_type') or '').strip().lower()
            normalized_value = str(claim.get('normalized_value') or '').strip().upper()
            if identifier_type and normalized_value:
                key = (identifier_type, normalized_value)
                by_claim.setdefault(key, set()).add(vehicle_id)
                evidence_by_claim.setdefault(key, []).append({
                    'vehicle_id': vehicle_id, 'origin': claim.get('origin'),
                    'source_system': claim.get('source_system'),
                })

    conflict_by_claim = {}
    for conflict in conflicts or []:
        key = (
            str(conflict.get('identifier_type') or '').strip().lower(),
            str(conflict.get('normalized_value') or '').strip().upper(),
        )
        if key[0] and key[1]:
            conflict_by_claim.setdefault(key, []).append(conflict)
    return {'by_claim': by_claim, 'by_id': by_id, 'conflicts': conflict_by_claim,
            'evidence_by_claim': evidence_by_claim}


def match_legacy_vehicle_identity(value, index):
    candidate_ids = set()
    identity_conflicts = []
    matched_claims = []
    for claim_key in sorted(_legacy_identity_forms(value)):
        ids = index['by_claim'].get(claim_key, set())
        if ids:
            candidate_ids.update(ids)
            matched_claims.extend({
                'identifier_type': claim_key[0], 'normalized_value': claim_key[1], **evidence,
            } for evidence in index['evidence_by_claim'].get(claim_key, []))
        identity_conflicts.extend(index['conflicts'].get(claim_key, []))
    vehicles = [index['by_id'][vehicle_id] for vehicle_id in sorted(candidate_ids)]
    return {
        'vehicles': vehicles,
        'matched_claims': matched_claims,
        'identity_conflicts': identity_conflicts,
    }


def fetch_vehicle_identity_export_pages(fetch_page, page_size=200, retry_attempts=3):
    if not isinstance(page_size, int) or page_size < 1 or page_size > VEHICLE_IDENTITY_EXPORT_MAX_PAGE_SIZE:
        raise VehicleIdentityExportInvalid('page size must be between 1 and 500')
    if not isinstance(retry_attempts, int) or retry_attempts < 1:
        raise VehicleIdentityExportInvalid('retry attempts must be positive')

    cursor = None
    expected_revision = None
    items = []
    conflicts = []
    seen_vehicle_ids = set()
    seen_conflicts = set()
    page_evidence = []
    pages = 0
    while True:
        pages += 1
        if pages > 10000:
            raise VehicleIdentityExportInvalid('export exceeded the bounded page limit')
        response = None
        last_error = None
        for attempt in range(retry_attempts):
            try:
                response = fetch_page(cursor, page_size, expected_revision)
                break
            except Exception as exc:  # read-only retry repeats the exact cursor/revision
                last_error = exc
                if attempt + 1 == retry_attempts:
                    raise VehicleIdentityExportError('identity export page failed after retries') from exc
        if response is None:
            raise VehicleIdentityExportError('identity export returned no response') from last_error
        if not isinstance(response, dict):
            raise VehicleIdentityExportInvalid('identity export response is not an object')
        outcome = response.get('outcome')
        if outcome == 'unauthorized':
            raise PermissionError('importer or administrator role required for vehicle identity export')
        if outcome == 'stale_export':
            raise VehicleIdentityExportStale('vehicle identity export revision changed during pagination')
        if outcome != 'exported':
            raise VehicleIdentityExportInvalid(f'identity export failed closed: {outcome or "malformed_response"}')
        expected_keys = {
            'outcome', 'export_revision', 'page_size', 'items', 'conflicts',
            'has_more', 'next_cursor',
        }
        if set(response) != expected_keys:
            raise VehicleIdentityExportInvalid('identity export response envelope is malformed')
        returned_page_size = response.get('page_size')
        if isinstance(returned_page_size, bool) or returned_page_size != page_size:
            raise VehicleIdentityExportInvalid('identity export returned an unexpected page size')

        revision = response.get('export_revision')
        if isinstance(revision, bool) or not isinstance(revision, int) or not 0 <= revision <= 2**53 - 1:
            raise VehicleIdentityExportInvalid('identity export revision is invalid')
        if expected_revision is None:
            expected_revision = revision
        elif revision != expected_revision:
            raise VehicleIdentityExportStale('vehicle identity export page revision mismatch')

        page_items = response.get('items')
        if (
            not isinstance(page_items, list)
            or len(page_items) > page_size
            or any(not isinstance(item, dict) for item in page_items)
        ):
            raise VehicleIdentityExportInvalid('identity export page is malformed or over limit')
        page_ids = [str(item.get('vehicle_id') or '') for item in page_items]
        if page_ids != sorted(page_ids):
            raise VehicleIdentityExportInvalid('identity export page is not deterministically ordered')
        if cursor is not None and page_ids and page_ids[0] <= str(cursor):
            raise VehicleIdentityExportInvalid('identity export page regressed behind its cursor')
        for item, vehicle_id in zip(page_items, page_ids):
            if not vehicle_id or vehicle_id in seen_vehicle_ids:
                raise VehicleIdentityExportInvalid('identity export contains a missing or duplicate vehicle UUID')
            seen_vehicle_ids.add(vehicle_id)
            items.append(item)

        page_conflicts = response.get('conflicts')
        if not isinstance(page_conflicts, list) or any(not isinstance(row, dict) for row in page_conflicts):
            raise VehicleIdentityExportInvalid('identity export conflict evidence is malformed')
        for conflict in page_conflicts:
            signature = json.dumps(conflict, sort_keys=True, separators=(',', ':'))
            if signature not in seen_conflicts:
                seen_conflicts.add(signature)
                conflicts.append(conflict)

        if not isinstance(response.get('has_more'), bool):
            raise VehicleIdentityExportInvalid('identity export has_more marker is missing or malformed')
        has_more = response['has_more']
        next_cursor = response.get('next_cursor')
        end_cursor = page_ids[-1] if page_ids else None
        page_evidence.append({
            'after_cursor': cursor,
            'end_cursor': end_cursor,
            'item_count': len(page_items),
            'has_more': has_more,
            'next_cursor': str(next_cursor) if next_cursor is not None else None,
        })
        if not has_more:
            if next_cursor is not None:
                raise VehicleIdentityExportInvalid('complete identity export page has an unexpected cursor')
            break
        if not next_cursor or (cursor is not None and str(next_cursor) <= str(cursor)):
            raise VehicleIdentityExportInvalid('identity export cursor did not advance')
        if not page_items or str(next_cursor) != page_ids[-1]:
            raise VehicleIdentityExportInvalid('identity export cursor does not match the page boundary')
        cursor = str(next_cursor)

    return {
        'outcome': 'exported',
        'export_revision': expected_revision,
        'items': items,
        'conflicts': sorted(
            conflicts,
            key=lambda row: (
                str(row.get('identifier_type') or ''),
                str(row.get('source_system') or ''),
                str(row.get('normalized_value') or ''),
            ),
        ),
        'completion': {
            'complete': True,
            'page_count': len(page_evidence),
            'terminal_cursor': items[-1]['vehicle_id'] if items else None,
            'pages': page_evidence,
        },
    }


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


def _parse_reference_data(
    reference,
    *,
    expected_revision,
    legacy_reference_rollback=False,
    logger=lambda _message: None,
):
    try:
        return parse_workshop_reference(
            reference,
            expected_resolver_revision=expected_revision,
            allow_legacy_rollback=legacy_reference_rollback,
            legacy_source_environment=(
                f'staging:{STAGING_PROJECT_REF}' if legacy_reference_rollback else None
            ),
            diagnostic=logger,
        )
    except VehicleReferenceArtifactStale as exc:
        raise VehicleIdentityExportStale(str(exc)) from exc
    except VehicleReferenceArtifactError as exc:
        raise VehicleIdentityExportInvalid(str(exc)) from exc


def classify(
    extract,
    reference,
    *,
    expected_revision,
    legacy_reference_rollback=False,
    logger=lambda _message: None,
):
    """Classify scheduling fields compatibly with the offline validator,
    while vehicle identity uses the typed migration-031 export contract.
    The remaining JS validator is intentionally a separate C2b cutover."""
    reference = _parse_reference_data(
        reference,
        expected_revision=expected_revision,
        legacy_reference_rollback=legacy_reference_rollback,
        logger=logger,
    )
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
    export_meta = reference.get('vehicleIdentityExport') or {}
    vehicle_identity_index = build_vehicle_identity_index(vehicles, export_meta.get('conflicts') or [])
    work_item_set = {(w['vehicle_id'], normalize_key(w['stage_code'])) for w in work_items}

    buckets = {k: [] for k in [
        'safely_matched', 'missing_vehicle', 'duplicate_vehicle_match',
        'conflicting_vehicle_identity', 'inactive_vehicle', 'missing_bay',
        'missing_technician', 'duplicate_technician_match', 'missing_work_item', 'overlapping_bay_booking',
        'overlapping_technician_booking', 'invalid_date_or_duration', 'requires_manual_review',
    ]}

    candidates = []
    for booking in extract.get('bookings', []):
        reasons = []
        identity_match = match_legacy_vehicle_identity(booking.get('legacy_vehicle_key'), vehicle_identity_index)
        vehicle_matches = identity_match['vehicles']
        matched_vehicle = None
        if len(vehicle_matches) == 1:
            (matched_vehicle,) = vehicle_matches
        stage_row = stage_by_code.get(normalize_key(booking.get('stage_code')))
        bay_row = None
        if stage_row and booking.get('bay_number') is not None:
            bay_row = bay_by_stage_number.get((stage_row['id'], int(booking['bay_number'])))
        technician_matches = []
        if booking.get('assignee'):
            technician_matches = technician_by_name.get(normalize_key(booking['assignee']), [])
        rng = to_range(booking.get('scheduled_start_at'), booking.get('duration_minutes'))

        if identity_match['identity_conflicts']:
            reasons.append('conflicting_vehicle_identity')
        elif len(vehicle_matches) == 0:
            reasons.append('missing_vehicle')
        elif len(vehicle_matches) > 1:
            reasons.append('duplicate_vehicle_match')
        elif matched_vehicle.get('is_archived'):
            reasons.append('inactive_vehicle')
        if not stage_row:
            reasons.append('missing_bay')
        elif booking.get('bay_number') is not None and not bay_row:
            reasons.append('missing_bay')
        if booking.get('assignee') and len(technician_matches) == 0:
            reasons.append('missing_technician')
        if booking.get('assignee') and len(technician_matches) > 1:
            reasons.append('duplicate_technician_match')
        if normalize_key(booking.get('stage_code')) in require_work_item_for:
            vehicle_id = matched_vehicle['id'] if matched_vehicle is not None else None
            if not vehicle_id or (vehicle_id, normalize_key(booking.get('stage_code'))) not in work_item_set:
                reasons.append('missing_work_item')
        if not rng:
            reasons.append('invalid_date_or_duration')

        requires_manual_review = booking.get('status') in ('completed', 'stoppage')

        if reasons:
            for reason in reasons:
                buckets.get(reason, buckets['invalid_date_or_duration']).append({
                    'booking': booking,
                    'reasons': reasons,
                    'identity_candidates': [row['id'] for row in vehicle_matches],
                    'identity_conflicts': identity_match['identity_conflicts'],
                    'matched_claims': identity_match['matched_claims'],
                })
        else:
            candidates.append({
                'booking': booking,
                'resolved': {
                    'vehicle_id': matched_vehicle['id'],
                    'vehicle_version': matched_vehicle['version'],
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


def _set_export_actor(conn, actor_email):
    cur = conn.cursor()
    cur.execute(
        """
        select r.role::text, r.email, u.id::text
        from public.pdc_user_roles r
        join auth.users u on lower(u.email) = lower(r.email)
        where lower(r.email) = lower(%s) and r.active
        """,
        (actor_email,),
    )
    rows = cur.fetchall()
    if len(rows) != 1:
        raise PermissionError('vehicle identity export actor is not one active PDC user')
    (role, email, user_id), = rows
    if role not in ('importer', 'administrator'):
        raise PermissionError('vehicle identity export actor must be importer or administrator')
    cur.execute(
        "select set_config('request.jwt.claims', %s, true)",
        (json.dumps({'email': email, 'role': 'authenticated', 'sub': user_id}),),
    )


def _fetch_vehicle_identity_export_page(conn, cursor, page_size, expected_revision):
    cur = conn.cursor()
    cur.execute(
        "select public.export_workshop_legacy_vehicle_identities(%s, %s, %s)",
        (cursor, page_size, expected_revision),
    )
    row = cur.fetchone()
    if not row:
        raise VehicleIdentityExportInvalid('vehicle identity export RPC returned no row')
    return row[0]


def _rollback_identity_conflicts(vehicles):
    claims = {}
    for raw_vehicle in vehicles:
        vehicle = _legacy_vehicle_record(raw_vehicle)
        for claim in _vehicle_claims(vehicle):
            key = (claim['identifier_type'], claim['normalized_value'])
            claims.setdefault(key, []).append({
                'vehicle_id': vehicle['id'], 'origin': 'rollback', 'value': claim['value'],
            })
    conflicts = []
    for (identifier_type, normalized_value), candidates in sorted(claims.items()):
        vehicle_ids = sorted({row['vehicle_id'] for row in candidates})
        if len(vehicle_ids) > 1:
            conflicts.append({
                'classification': 'ambiguous_normalized_identity',
                'identifier_type': identifier_type,
                'normalized_value': normalized_value,
                'source_system': None,
                'vehicle_ids': vehicle_ids,
                'candidates': sorted(candidates, key=lambda row: (row['vehicle_id'], row['value'])),
            })
    return conflicts


def _fetch_vehicle_identity_export_rollback(conn, logger):
    assert_staging_project(conn)
    logger('WARNING: staging-only workshop legacy vehicle identity rollback read is active')
    cur = conn.cursor()
    cur.execute(
        "select revision from public.vehicle_lifecycle_resolver_revision "
        "where singleton for share"
    )
    revision_rows = cur.fetchall()
    if len(revision_rows) != 1 or not isinstance(revision_rows[0][0], int):
        raise VehicleIdentityExportInvalid('rollback could not establish an identity revision')
    export_revision = revision_rows[0][0]
    cur.execute("select id, stock_number, permanent_vehicle_id, version from vehicles where deleted_at is null")
    vehicles = [
        {
            'id': str(row[0]), 'vehicle_id': str(row[0]), 'version': row[3],
            'is_archived': False, 'stock_number': row[1], 'permanent_vehicle_id': row[2],
        }
        for row in cur.fetchall()
    ]
    vehicles.sort(key=lambda row: row['vehicle_id'])
    return {
        'outcome': 'exported',
        'export_revision': export_revision,
        'items': vehicles,
        'conflicts': _rollback_identity_conflicts(vehicles),
        'rollback_used': True,
    }


def fetch_reference_data(
    conn,
    *,
    actor_email=None,
    vehicle_export_rollback=False,
    page_size=200,
    retry_attempts=3,
    generated_at=None,
    logger=lambda message: print(message, file=sys.stderr),
):
    assert_staging_project(conn)
    if actor_email:
        _set_export_actor(conn, actor_email)

    if vehicle_export_rollback:
        vehicle_export = _fetch_vehicle_identity_export_rollback(conn, logger)
    else:
        vehicle_export = fetch_vehicle_identity_export_pages(
            lambda cursor, size, revision: _fetch_vehicle_identity_export_page(
                conn, cursor, size, revision,
            ),
            page_size=page_size,
            retry_attempts=retry_attempts,
        )
        vehicle_export['rollback_used'] = False

    cur = conn.cursor()
    cur.execute("select id, code from workshop_stages")
    stages = [{'id': str(r[0]), 'code': r[1]} for r in cur.fetchall()]
    cur.execute("select id, stage_id, bay_number from workshop_bays where bay_number is not null")
    bays = [{'id': str(r[0]), 'stage_id': str(r[1]), 'bay_number': r[2]} for r in cur.fetchall()]
    cur.execute("select id, name from workshop_technicians where active = true")
    technicians = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]
    reference = {
        'stages': stages,
        'bays': bays,
        'technicians': technicians,
        'workItems': [],
        'requireWorkItemForStages': [],
    }
    if vehicle_export_rollback:
        # C2a reference shape is retained only for an explicit staging/test
        # rollback. It is never emitted by the normal C2b path.
        reference.update({
            'vehicles': vehicle_export['items'],
            'vehicleIdentityExport': {
                'outcome': vehicle_export['outcome'],
                'export_revision': vehicle_export['export_revision'],
                'conflicts': vehicle_export['conflicts'],
                'rollback_used': True,
            },
        })
    else:
        reference['vehicleIdentityArtifact'] = build_vehicle_reference_artifact(
            vehicle_export,
            generated_at=generated_at or datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            source_environment=f'staging:{STAGING_PROJECT_REF}',
        )
    return reference


def assert_staging_project(conn):
    """Refuse unless both connection identity and fixture prove staging."""
    try:
        dsn = conn.get_dsn_parameters()
    except (AttributeError, TypeError) as exc:
        raise RuntimeError(
            'Refusing to run: cannot verify the staging project connection identity'
        ) from exc
    dsn_identity = ' '.join(str(dsn.get(key) or '') for key in ('user', 'host'))
    if STAGING_PROJECT_REF not in dsn_identity:
        raise RuntimeError(
            f'Refusing to run: connection does not identify staging project {STAGING_PROJECT_REF}'
        )

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
    admin_email = os.environ.get('PDC_STAGING_ADMIN_EMAIL', '').strip().lower()
    if not admin_email:
        raise RuntimeError('PDC_STAGING_ADMIN_EMAIL is required for audited staging imports.')
    cur = conn.cursor()
    cur.execute("select id from auth.users where lower(email) = %s", (admin_email,))
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Staging administrator test account not found; cannot attribute import audit rows.")
    return row[0]


def _lock_vehicle_identity_export_revision(conn, reference, rollback_permitted=False, logger=lambda _message: None):
    metadata = reference.get('vehicleIdentityExport')
    if not isinstance(metadata, dict) or metadata.get('outcome') != 'exported':
        raise VehicleIdentityExportInvalid('reference data lacks a successful guarded vehicle identity export')
    if metadata.get('rollback_used') is True:
        if not rollback_permitted:
            raise VehicleIdentityExportInvalid('rollback reference requires the explicit staging-only rollback flag')
        logger('WARNING: import is using staging-only rollback vehicle identity evidence')
    expected_revision = metadata.get('export_revision')
    if not isinstance(expected_revision, int) or expected_revision < 0:
        raise VehicleIdentityExportInvalid('reference data has no valid export revision')
    cur = conn.cursor()
    cur.execute(
        "select revision from public.vehicle_lifecycle_resolver_revision where singleton for share"
    )
    rows = cur.fetchall()
    if len(rows) != 1 or rows[0][0] != expected_revision:
        raise VehicleIdentityExportStale('vehicle identity export is stale; regenerate reference data')
    return expected_revision


def _current_vehicle_identity_export_revision(conn):
    cur = conn.cursor()
    cur.execute(
        "select revision from public.vehicle_lifecycle_resolver_revision where singleton"
    )
    rows = cur.fetchall()
    if len(rows) != 1 or isinstance(rows[0][0], bool) or not isinstance(rows[0][0], int):
        raise VehicleIdentityExportInvalid('current resolver revision is unavailable')
    return rows[0][0]


def _import_request_fingerprint(extract, reference, buckets):
    safe = []
    for entry in buckets['safely_matched']:
        booking = entry['booking']
        resolved = entry['resolved']
        safe.append({
            'legacy_plan_id': booking.get('legacy_plan_id'),
            'vehicle_id': resolved.get('vehicle_id'),
            'vehicle_version': resolved.get('vehicle_version'),
            'stage_id': resolved.get('stage_id'),
            'bay_id': resolved.get('bay_id'),
            'technician_id': resolved.get('technician_id'),
            'scheduled_start_at': booking.get('scheduled_start_at'),
            'scheduled_end_at': booking.get('scheduled_end_at'),
            'duration_minutes': booking.get('duration_minutes'),
            'status': booking.get('status'),
        })
    export_meta = reference.get('vehicleIdentityExport') or {}
    artifact = reference.get('vehicleIdentityArtifact') or {}
    payload = {
        'extract': extract,
        'vehicle_export_revision': export_meta.get('export_revision', artifact.get('resolver_revision')),
        'vehicle_artifact_checksum': export_meta.get('artifact_checksum', (artifact.get('checksum') or {}).get('value')),
        'rollback_used': export_meta.get('rollback_used') is True,
        'safely_matched': sorted(safe, key=lambda row: str(row.get('legacy_plan_id') or '')),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest()


def _find_completed_import_receipt(cur, request_fingerprint):
    cur.execute(
        """
        select id::text, summary
        from public.import_runs
        where import_type='backup_baseline'
          and source_hash=%s
          and status='completed'
        order by completed_at, id
        """,
        (request_fingerprint,),
    )
    rows = cur.fetchall()
    if len(rows) > 1:
        raise VehicleIdentityExportInvalid('multiple completed receipts exist for one importer request')
    if not rows:
        return None
    (receipt,) = rows
    return {'receipt_id': receipt[0], 'summary': receipt[1] or {}}


def run_import(
    conn,
    extract,
    reference,
    apply=False,
    vehicle_export_rollback=False,
    commit_apply=True,
    logger=lambda message: print(message, file=sys.stderr),
):
    assert_staging_project(conn)
    admin_user_id = get_admin_user_id(conn)
    admin_email = os.environ['PDC_STAGING_ADMIN_EMAIL'].strip().lower()

    cur = conn.cursor()
    # Impersonate the staging administrator role for this session so
    # record_import_run()'s require_pdc_role('importer') check (which reads
    # auth.jwt() ->> 'email') succeeds. This is only ever meaningful on a
    # direct superuser/service Postgres connection to the staging project
    # (never exposed to the browser publishable key) -- see
    # assert_staging_project() above for the staging-only tripwire.
    cur.execute(
        "select set_config('request.jwt.claims', %s, true)",
        (json.dumps({'email': admin_email, 'role': 'authenticated', 'sub': str(admin_user_id)}),),
    )
    declared_meta = reference.get('vehicleIdentityArtifact') or reference.get('vehicleIdentityExport') or {}
    declared_revision = declared_meta.get('resolver_revision', declared_meta.get('export_revision'))
    if isinstance(declared_revision, bool) or not isinstance(declared_revision, int):
        raise VehicleIdentityExportInvalid('reference data has no declared resolver revision')
    reference = _parse_reference_data(
        reference,
        expected_revision=declared_revision,
        legacy_reference_rollback=vehicle_export_rollback,
        logger=logger,
    )
    buckets = classify(
        extract,
        reference,
        expected_revision=declared_revision,
        legacy_reference_rollback=vehicle_export_rollback,
        logger=logger,
    )
    if apply and WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED:
        raise RuntimeError(
            'Direct Workshop Planner legacy apply is disabled. Regenerate an operational preview '
            'and apply bookings only through protected runtime RPCs.'
        )
    request_fingerprint = _import_request_fingerprint(extract, reference, buckets)
    if apply:
        # Serialize identical requests. If the first caller committed but its
        # response was lost, the retry returns the durable receipt and makes
        # no second booking/history/assignment mutation.
        cur.execute(
            "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
            (request_fingerprint,),
        )
        completed = _find_completed_import_receipt(cur, request_fingerprint)
        if completed:
            replay = dict(completed['summary'])
            replay.update({
                'apply': True,
                'replayed': True,
                'request_fingerprint': request_fingerprint,
                'receipt_id': completed['receipt_id'],
            })
            if commit_apply:
                conn.commit()
            return replay
    _lock_vehicle_identity_export_revision(
        conn, reference, rollback_permitted=vehicle_export_rollback, logger=logger,
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
                    metadata, admin_user_id, admin_email,
                ),
            )
        else:
            if existing:
                updated += 1
            else:
                inserted += 1

    skipped = sum(len(v) for k, v in buckets.items() if k != 'safely_matched')
    resolved_vehicles = sorted(({
        'legacy_plan_id': row['booking'].get('legacy_plan_id'),
        'vehicle_id': row['resolved']['vehicle_id'],
        'vehicle_version': row['resolved']['vehicle_version'],
    } for row in buckets['safely_matched']), key=lambda row: str(row['legacy_plan_id'] or ''))
    vehicle_reference_summary = {
        'schema_version': (reference.get('vehicleIdentityExport') or {}).get('artifact_schema_version') or 'legacy-rollback',
        'resolver_revision': (reference.get('vehicleIdentityExport') or {}).get('export_revision'),
        'checksum': (reference.get('vehicleIdentityExport') or {}).get('artifact_checksum'),
        'source_environment': (reference.get('vehicleIdentityArtifact') or {}).get('source_environment')
            or (f'staging:{STAGING_PROJECT_REF}' if vehicle_export_rollback else None),
        'item_count': len(reference.get('vehicles') or []),
    }

    if apply:
        cur.execute("select count(*) from workshop_bookings where source = %s", (LEGACY_IMPORT_SOURCE,))
        after_count = cur.fetchone()[0]
        cur.execute(
            "select record_import_run(%s, %s, %s, %s)",
            (
                'backup_baseline',
                extract.get('source_backup_type') or 'workshop_planner_legacy_export',
                request_fingerprint,
                json.dumps({
                    'apply': True,
                    'replayed': False,
                    'request_fingerprint': request_fingerprint,
                    'inserted': inserted,
                    'updated': updated,
                    'skipped': skipped,
                    'before_count': before_count,
                    'after_count': after_count,
                    'vehicle_reference': vehicle_reference_summary,
                    'resolved_vehicles': resolved_vehicles,
                    'bucket_counts': {k: len(v) for k, v in buckets.items()},
                }),
            ),
        )
        receipt_id = str(cur.fetchone()[0])
        if commit_apply:
            conn.commit()
    else:
        conn.rollback()
        after_count = before_count  # dry-run changes nothing

    return {
        'apply': apply,
        'replayed': False,
        'request_fingerprint': request_fingerprint,
        'receipt_id': receipt_id if apply else None,
        'before_count': before_count,
        'after_count': after_count,
        'inserted': inserted,
        'updated': updated,
        'skipped': skipped,
        'vehicle_reference': vehicle_reference_summary,
        'resolved_vehicles': resolved_vehicles,
        'bucket_counts': {k: len(v) for k, v in buckets.items()},
    }


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    extract_path, reference_path = sys.argv[1], sys.argv[2]
    apply_mode = '--apply' in sys.argv[3:]
    rollback_mode = '--vehicle-export-rollback' in sys.argv[3:]

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from scripts.pdc_staging_runtime import get_conn  # noqa: E402

    with open(extract_path) as f:
        extract_data = json.load(f)
    with open(reference_path) as f:
        reference_data = json.load(f)

    connection = get_conn()
    try:
        result = run_import(
            connection,
            extract_data,
            reference_data,
            apply=apply_mode,
            vehicle_export_rollback=rollback_mode,
        )
        print(json.dumps(result, indent=2))
    finally:
        connection.close()
