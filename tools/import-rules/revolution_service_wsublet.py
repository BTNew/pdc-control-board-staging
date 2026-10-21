"""r442 (F54): read a Revolution 'PMG PD Service Complete w/Sublet' workbook and collapse it to one service line per
Dept + R/O # + Line #.

The w/Sublet report has no Type column. It carries the 13 usual service columns followed by 'Description of sublet' and
'PO #', and repeats a service line once per sublet PO. This module:

* finds data rows without Type: a data row has an R/O # and a Line #; the totals footer (no R/O #, no Line #) is kept
  aside and never imported; any other row shape stops the whole file (nothing is guessed);
* collapses repeated rows to ONE line, keeping every distinct PO in source order, and NEVER sums hours;
* when repeated rows disagree outside the sublet columns, keeps the FIRST row in source order (deterministic), and flags
  the line ('collapse.conflict' true, with every differing value) so the apply receipt reports it.

Pure functions over already-read cell values; no network, no database, no file names or stock numbers in here.
"""
import re

TITLE = 'PMG PD Service Complete w/Sublet'
BASE_HEADERS = ['Dept', 'Stock #', 'Rego #', 'Owner Name', 'Parts Location', 'Key Tag Number', 'R/O #', 'Sub Status',
                'Line #', 'Operation Desc', 'Estimated labour hours', 'Modified Date', 'Range #']
SUBLET_HEADERS = ['PO #', 'Job #', 'Document Line', 'Sublet Line', 'Description of sublet', 'Company', 'Division']
FILENAME_RE = re.compile(r'^PMG PD Service Complete w[/_ -]?Sublet( - Job 1)?[.]xlsx?$')
COLLAPSE_RULE = 'r442_one_row_per_dept_ro_line'
TYPE_BASIS = 'absent_r442'


class ContractError(ValueError):
    pass


def norm(v):
    if v is None:
        return ''
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return str(v).strip()


def check_headers(headers):
    h = [norm(x) for x in headers]
    while h and h[-1] == '':
        h.pop()
    if h[:len(BASE_HEADERS)] != BASE_HEADERS:
        raise ContractError('headers: expected the 13 service columns first, got %r' % h[:len(BASE_HEADERS)])
    extra = h[len(BASE_HEADERS):]
    if 'Type' in h:
        raise ContractError('headers: the w/Sublet report has no Type column')
    if len(set(extra)) != len(extra) or any(x not in SUBLET_HEADERS for x in extra) or 'PO #' not in extra:
        raise ContractError('headers: only the optional sublet columns may follow, and PO # is required; got %r' % extra)
    return h


def classify(raw):
    """'data', 'footer' or raises. Replaces the old Type D / T1 test."""
    ro, line = norm(raw.get('R/O #')), raw.get('Line #')
    if not ro and line in (None, ''):
        return 'footer'
    if not re.fullmatch(r'J(138|139)[0-9]+', ro) or norm(raw.get('Dept')) not in ('138', '139') or not ro.startswith('J' + norm(raw.get('Dept'))):
        if norm(raw.get('Dept')) not in ('138', '139') and ro:
            return 'excluded_department'
        raise ContractError('row: R/O # %r / Dept %r is not a J138/J139 service line' % (ro, raw.get('Dept')))
    if not isinstance(line, (int, float)) or isinstance(line, bool) or int(line) != line or line <= 0:
        raise ContractError('row: Line # %r is not a positive whole number' % (line,))
    h = raw.get('Estimated labour hours')
    if h is not None and (not isinstance(h, (int, float)) or isinstance(h, bool) or h < 0):
        raise ContractError('row: Estimated labour hours %r is not a non-negative number' % (h,))
    return 'data'


def collapse(rows):
    """rows: [(source_row_number, {header: value})] in source order (data rows only).
    Returns (lines, summary). Each line: {'raw': first row's service values, 'source_row_numbers', 'sublet_pos',
    'sublet_po_descriptions' (r444: {PO: description} for raw_row.sublet_po_descriptions), 'sublet_columns', 'collapse'}."""
    groups = {}
    order = []
    for rn, raw in rows:
        key = (norm(raw['Dept']), norm(raw['R/O #']).upper(), int(raw['Line #']))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append((rn, raw))
    lines, conflicts, repeated = [], [], 0
    for key in order:
        g = groups[key]
        first_rn, first = g[0]
        base = {k: v for k, v in first.items() if k in BASE_HEADERS}
        differing = {}
        for k in BASE_HEADERS:
            vals = []
            for _, r in g:
                v = r.get(k)
                v = re.sub(r'\s+', ' ', norm(v)) if isinstance(v, str) else v
                if v not in vals:
                    vals.append(v)
            if len(vals) > 1:
                differing[k] = vals
        pos, cols, descs = [], [], {}
        for rn, r in g:
            po = re.sub(r'\s+', '', norm(r.get('PO #'))).upper()
            entry = {k: r.get(k) for k in SUBLET_HEADERS if k in r}
            entry['source_row_number'] = rn
            cols.append(entry)
            if po and po not in pos:
                pos.append(po)
            # r444 (F57): each PO's 'Description of sublet' as typed (ends trimmed); a PO repeated with different
            # descriptions keeps each distinct one in source order, joined with '^' (Revolution's own line break).
            d = norm(r.get('Description of sublet'))
            if po and d:
                if po not in descs:
                    descs[po] = []
                if d not in descs[po]:
                    descs[po].append(d)
        po_descriptions = {po: '^'.join(v)[:4000] for po, v in descs.items()}
        if len(g) > 1:
            repeated += 1
        c = {'rule': COLLAPSE_RULE, 'source_rows': len(g), 'hours_summed': False, 'conflict': bool(differing)}
        if differing:
            c['kept'] = 'first_row_in_source_order'
            c['differing_values'] = differing
            conflicts.append({'dept': key[0], 'ro': key[1], 'line': key[2], 'fields': sorted(differing)})
        lines.append({'key': key, 'raw': base, 'source_row_numbers': [rn for rn, _ in g], 'sublet_pos': pos,
                      'sublet_po_descriptions': po_descriptions, 'sublet_columns': cols, 'collapse': c})
    summary = {'source_rows': len(rows), 'lines': len(lines), 'lines_with_repeats': repeated,
               'rows_collapsed': len(rows) - len(lines), 'conflicts': conflicts,
               'distinct_pos': len({p for l in lines for p in l['sublet_pos']}),
               'hours_first_row_per_line': round(sum(float(l['raw'].get('Estimated labour hours') or 0) for l in lines), 2),
               'hours_naive_all_rows': round(sum(float(r.get('Estimated labour hours') or 0) for _, r in rows), 2)}
    return lines, summary


def read_values(values):
    """values: worksheet rows (title, parameters, blank, headers, data...). Returns (headers, data_rows, footer, excluded, params)."""
    if norm(values[0][0]) != TITLE:
        raise ContractError('title: expected %r, got %r' % (TITLE, values[0][0]))
    params = norm(values[1][0])
    if 'Company = "01"' not in params or 'Division = "1"' not in params:
        raise ContractError('parameters: Company 01 / Division 1 required')
    headers = check_headers(values[3])
    data, footer, excluded = [], [], []
    for rn, cells in enumerate(values[4:], 5):
        if all(x is None or norm(x) == '' for x in cells):
            continue
        raw = dict(zip(headers, cells[:len(headers)]))
        kind = classify(raw)
        (data if kind == 'data' else footer if kind == 'footer' else excluded).append((rn, raw))
    if len(footer) > 1:
        raise ContractError('more than one footer row')
    return headers, data, footer, excluded, params
