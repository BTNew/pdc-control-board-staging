"""r479 (F92): read a Revolution 'PMG PD Service as a Whole w/Sublet' workbook, the FULL snapshot of every open R/O for
Departments 138 and 139 (R/O status 20 to under 90), and prepare it the w/Sublet way.

Craig, 22 Oct 2026 (via Kajel, 12:09 AWST): this report replaces the hourly 'PMG PD Service Complete w/Sublet' feed as the
primary service import. It has the same 15 columns as w/Sublet; Revolution writes the header cells as formulas (="Dept"),
so a reader that does not use the cached values sees the text wrapped in =" ". This module:

* checks the title, the extraction parameters (Company 01, Division 1, Dept 138 or 139, Status >= 20 and < 90: the scope a
  full snapshot must have, or 'missing from the snapshot' would be wrong) and unwraps ="..." header cells;
* then reads, classifies and collapses through revolution_service_wsublet (r442 one line per Dept + R/O + Line #,
  hours never summed; r468 optional leading Type; r509 optional trailing Create Advisor, dropped before the manifest,
  and when that column is present only data rows with a non-blank advisor are imported; r444 sublet PO descriptions;
  r471 bay codes are applied later by the pipeline step that has the board context). Those rules are not copied here;
* resolves each R/O to a board vehicle WITHOUT ever creating one: a non-blank Stock # must be an exact board stock; a blank
  Stock # matches ONLY an exact board stock equal to the Rego # value, or an exact job-card match (the vehicle's job card, or
  a service job already on the board for that R/O). Anything else (no vehicle, a completed / deleted vehicle, or more than
  one candidate) is not sent; it goes to the review list instead;
* builds the snapshot payload (sha, R/O, line, seen_at) for pdc_service_snapshot_private.record_snapshot_479 and an
  offline mirror of the read-only reconcile (pdc_service_snapshot_private.reconcile_479) for dry runs and tests.

Pure functions over already-read cell values and plain dicts; no network, no database, no file names or stock numbers.
"""
import re

import revolution_service_wsublet as ws

TITLE = 'PMG PD Service as a Whole w/Sublet'
# The Revolution attachment keeps its report name. CreateAdvisor-Service-as-a-Whole.xlsx is Craig's filtered export
# (Create Advisor <> ""), the file Kajel tests the widened header against. The worksheet title is still TITLE.
FILENAME_RE = re.compile(r'^(?:PMG PD Service as a Whole w[/_ -]?Sublet( - Job 1)?|CreateAdvisor-Service-as-a-Whole)[.]xlsx?$')
SNAPSHOT_SCOPE = 'full_open_ro_snapshot_r479'          # manifest provenance marker (snapshot_scope)
IDENTITY_RULE = 'r479_exact_board_stock_or_job_card'   # raw_row.identity_r479.rule
IDENTITY_KEY = 'identity_r479'
LIVE_STATES = ('active', 'rft')
CLOSING_SUB_STATUS = ('80', '99')                      # Sub Status 80 / 99: the line is checked out / complete in Revolution
MISSING_AFTER = 2                                      # consecutive complete snapshots before a board R/O or vehicle is flagged

_PARAM_RES = [
    (re.compile(r'Company\s*=\s*"01"'), 'Company = "01"'),
    (re.compile(r'Division\s*=\s*"1"'), 'Division = "1"'),
    (re.compile(r'Dept\s*=\s*"138"\s+or\s+Dept\s*=\s*"139"', re.I), 'Dept = "138" or Dept = "139"'),
    (re.compile(r'Status\s*>=\s*"20"\s+and\s+Status\s*<\s*"90"', re.I), 'Status >= "20" and Status < "90"'),
]

ContractError = ws.ContractError
norm = ws.norm


def unwrap_header(value):
    """'="Dept"' -> 'Dept'. Same helper as the w/Sublet reader (formula header text)."""
    return ws.unwrap_header(value)


def check_parameters(params):
    """The extraction must cover every open R/O of both departments; otherwise it is not a full snapshot."""
    p = norm(params)
    missing = [label for rx, label in _PARAM_RES if not rx.search(p)]
    if missing:
        raise ContractError('parameters: a full open-R/O snapshot needs %s; got %r' % (', '.join(missing), p[:300]))
    return p


def read_values(values):
    """values: worksheet rows (title, parameters, blank, headers, data...). Returns the w/Sublet SheetRead
    (headers, data, footer, excluded, params), with .create_advisor, for the 'as a Whole' title, after unwrapping
    ="..." headers. A parameter cell that also says Create Advisor <> "" still has to carry the full-snapshot clauses."""
    if not values or norm(values[0][0]) != TITLE:
        raise ContractError('title: expected %r, got %r' % (TITLE, values[0][0] if values else None))
    if len(values) < 4:
        raise ContractError('worksheet: no header row')
    check_parameters(values[1][0])
    headers = tuple(unwrap_header(h) for h in values[3])
    # The w/Sublet reader checks its own title. Headers are unwrapped first; Type, Create Advisor, collapse and PO
    # descriptions are that reader's rules (r442 / r468 / r509 / r444).
    first = (ws.TITLE,) + tuple(values[0][1:])
    return ws.read_values([first, values[1], values[2], headers] + list(values[4:]))


def source_headers(values):
    """The unwrapped header row without the optional Type column and without a trailing Create Advisor column
    (what the manifest's source_headers must carry). Do not send the raw worksheet header row."""
    return ws.check_headers([unwrap_header(h) for h in values[3]])


# ---- board identity (never creates a vehicle) ----------------------------------------------------------------------------
def _key(v):
    return norm(v).upper()


def board_index(board):
    """board: {'vehicles': [{id, stock, jc, ls, deleted}], 'jobs': [{vehicle_id, ro}]} (see BOARD_SQL)."""
    by_stock, by_jc, by_job = {}, {}, {}
    vehicles = {}
    for v in board.get('vehicles') or []:
        vehicles[str(v['id'])] = v
        if _key(v.get('stock')):
            by_stock.setdefault(_key(v.get('stock')), []).append(v)
        if _key(v.get('jc')):
            by_jc.setdefault(_key(v.get('jc')), []).append(v)
    for j in board.get('jobs') or []:
        v = vehicles.get(str(j.get('vehicle_id')))
        if v is not None and _key(j.get('ro')):
            lst = by_job.setdefault(_key(j.get('ro')), [])
            if v not in lst:
                lst.append(v)
    return {'stock': by_stock, 'jc': by_jc, 'job': by_job, 'vehicles': vehicles}


def _live(v):
    return not v.get('deleted') and v.get('ls') in LIVE_STATES


def _one(cands):
    out = []
    for v in cands:
        if all(str(v['id']) != str(x['id']) for x in out):
            out.append(v)
    return out


def resolve_ro(ro, file_stock, file_rego, idx):
    """Identity of one R/O: {'status': linked | no_board_vehicle | vehicle_not_live | ambiguous, 'basis', 'stock',
    'vehicle_id', 'file_stock', 'file_rego', 'rule'}. Only 'linked' rows are sent to the service preview."""
    st, rg, r = _key(file_stock), _key(file_rego), _key(ro)
    out = {'rule': IDENTITY_RULE, 'file_stock': norm(file_stock) or None, 'file_rego': norm(file_rego) or None}
    if st:
        tried = [('stock_column', idx['stock'].get(st, []))]
    else:
        tried = [('rego_column_exact_board_stock', idx['stock'].get(rg, []) if rg else []),
                 ('job_card_exact', idx['jc'].get(r, [])),
                 ('job_card_service_job', idx['job'].get(r, []))]
    live = _one([v for _, c in tried for v in c if _live(v)])
    if len(live) == 1:
        v = live[0]
        basis = next(b for b, c in tried if any(str(x['id']) == str(v['id']) for x in c))
        out.update(status='linked', basis=basis, stock=norm(v.get('stock')), vehicle_id=str(v['id']))
        return out
    if len(live) > 1:
        out.update(status='ambiguous', basis=None, stock=None, vehicle_id=None,
                   candidates=sorted(norm(v.get('stock')) for v in live))
        return out
    other = _one([v for _, c in tried for v in c])
    if other:
        states = sorted({'deleted' if v.get('deleted') else str(v.get('ls')) for v in other})
        out.update(status='vehicle_not_live', basis=None, stock=None, vehicle_id=None, board_states=states)
        return out
    out.update(status='no_board_vehicle', basis=None, stock=None, vehicle_id=None,
               reason='stock_not_on_board' if st else ('rego_not_a_board_stock_and_no_job_card' if rg else 'no_stock_no_rego_no_job_card'))
    return out


def resolve_lines(lines, idx):
    """{(dept, R/O): identity} for collapsed lines (first line of each R/O gives Stock # / Rego #; an R/O whose lines
    disagree on Stock # or Rego # is ambiguous and not sent)."""
    seen, out = {}, {}
    for L in lines:
        raw = L['raw']
        k = (norm(raw['Dept']), norm(raw['R/O #']).upper())
        seen.setdefault(k, set()).add((_key(raw.get('Stock #')), _key(raw.get('Rego #'))))
        if k not in out:
            out[k] = resolve_ro(k[1], raw.get('Stock #'), raw.get('Rego #'), idx)
    for k, ids in seen.items():
        if len(ids) > 1:
            out[k] = dict(out[k], status='ambiguous', basis=None, stock=None, vehicle_id=None, reason='stock_or_rego_differs_between_lines')
    return out


# ---- snapshot payload and offline reconcile ------------------------------------------------------------------------------
def sub_status(raw):
    s = norm(raw.get('Sub Status'))
    return s or None


def snapshot_payload(sha256, snapshot_at, lines, identities, gmail_message_id=None, lib_md5=None):
    """{'header': {...}, 'lines': [[dept, ro, line, stock|None, file_stock|None, file_rego|None, sub_status|None, identity]]}
    for record_snapshot_479 (the order of the line fields is fixed: LINE_FIELDS)."""
    if not re.fullmatch(r'[0-9a-f]{64}', sha256 or ''):
        raise ContractError('snapshot: sha256 must be 64 lower-case hex')
    rows = []
    for L in lines:
        raw = L['raw']
        k = (norm(raw['Dept']), norm(raw['R/O #']).upper())
        ident = identities[k]
        rows.append([k[0], k[1], int(raw['Line #']), ident.get('stock'), ident.get('file_stock'), ident.get('file_rego'),
                     sub_status(raw), ident['status']])
    header = {'snapshot_sha256': sha256, 'report_title': TITLE, 'snapshot_scope': SNAPSHOT_SCOPE, 'source_snapshot_at': snapshot_at,
              'gmail_message_id': gmail_message_id, 'line_count': len(rows), 'ro_count': len({(r[0], r[1]) for r in rows}),
              'lib_md5': lib_md5}
    return {'header': header, 'lines': rows}


LINE_FIELDS = ['department', 'repair_order_number', 'original_line_number', 'stock_number', 'file_stock', 'file_rego',
               'sub_status', 'identity_status']


def reconcile(snapshots, board):
    """Offline mirror of pdc_service_snapshot_private.reconcile_479. snapshots: payloads, oldest first (complete ones only).
    board: {'vehicles', 'jobs' [{vehicle_id, ro, closed}]}. Read-only: returns the review list, never closes, hides or deletes.
    Categories:
      open_ro_no_board_vehicle       latest snapshot R/O not linked (no_board_vehicle / vehicle_not_live / ambiguous)
      ro_all_lines_80_99_still_open  latest snapshot R/O whose every line has Sub Status 80 or 99 (the R/O is still open)
      board_vehicle_missing          live vehicle with an open service job, absent (by stock and by all its open R/Os) from the
                                     last MISSING_AFTER consecutive snapshots
      board_ro_missing               open service job R/O on a live vehicle absent from the last MISSING_AFTER snapshots, when
                                     the vehicle itself is still in the snapshot
    With fewer than MISSING_AFTER snapshots the two missing categories are reported as pending, not flagged."""
    out = {'contract': 'pdc-service-whole-reconcile-479', 'snapshots_considered': len(snapshots[-MISSING_AFTER:]),
           'missing_after_consecutive_snapshots': MISSING_AFTER, 'items': []}
    if not snapshots:
        out['note'] = 'no_complete_snapshot'
        return out
    latest = snapshots[-1]
    by_ro = {}
    for r in latest['lines']:
        by_ro.setdefault((r[0], r[1]), []).append(r)
    for (dept, ro), rs in sorted(by_ro.items()):
        ident = rs[0][7]
        if ident != 'linked':
            out['items'].append({'category': 'open_ro_no_board_vehicle', 'reason': ident, 'department': dept, 'ro': ro,
                                 'file_stock': rs[0][4], 'file_rego': rs[0][5], 'lines': len(rs)})
        if all((r[6] or '') in CLOSING_SUB_STATUS for r in rs):
            out['items'].append({'category': 'ro_all_lines_80_99_still_open', 'department': dept, 'ro': ro, 'stock': rs[0][3],
                                 'lines': len(rs), 'sub_status': sorted({r[6] for r in rs})})
    window = snapshots[-MISSING_AFTER:]
    seen_ro = [{_key(r[1]) for r in s['lines']} for s in window]
    seen_stock = [{_key(r[3]) for r in s['lines'] if r[3]} | {_key(r[4]) for r in s['lines'] if r[4]}
                  | {_key(r[5]) for r in s['lines'] if r[5]} for s in window]
    vehicles = {str(v['id']): v for v in board.get('vehicles') or []}
    open_ros = {}
    for j in board.get('jobs') or []:
        v = vehicles.get(str(j.get('vehicle_id')))
        if v is not None and _live(v) and not j.get('closed') and _key(j.get('ro')):
            open_ros.setdefault(str(v['id']), set()).add(_key(j.get('ro')))
    flagged = len(window) >= MISSING_AFTER
    for vid, ros in sorted(open_ros.items(), key=lambda kv: _key(vehicles[kv[0]].get('stock'))):
        v = vehicles[vid]
        st = _key(v.get('stock'))
        absent_everywhere = all(st not in ss and not (ros & sr) for ss, sr in zip(seen_stock, seen_ro))
        if absent_everywhere:
            out['items'].append({'category': 'board_vehicle_missing' if flagged else 'board_vehicle_missing_pending',
                                 'stock': v.get('stock'), 'open_ros': sorted(ros)})
            continue
        for ro in sorted(ros):
            if all(ro not in sr for sr in seen_ro):
                out['items'].append({'category': 'board_ro_missing' if flagged else 'board_ro_missing_pending',
                                     'stock': v.get('stock'), 'ro': ro})
    counts = {}
    for i in out['items']:
        counts[i['category']] = counts.get(i['category'], 0) + 1
    out['counts'] = counts
    return out


# Read-only board index for resolve_ro (run on the management connection; staging only). One JSON value.
BOARD_SQL = """SELECT jsonb_build_object('at',clock_timestamp(),
 'vehicles',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'stock',v.stock_number,'jc',v.job_card_number,'ls',v.lifecycle_state::text,
   'deleted',v.deleted_at IS NOT NULL,'visible',v.visible_on_board,'key',v.key_number)),'[]'::jsonb) FROM public.vehicles v),
 'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object('vehicle_id',j.vehicle_id,'ro',j.ro_number,'closed',j.closed_at IS NOT NULL)),'[]'::jsonb)
   FROM pdc_parts_private.jobs j WHERE j.company='01' AND j.division='1')) AS board;"""
