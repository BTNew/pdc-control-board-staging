"""r442 (F54): read a Revolution 'PMG PD Service Complete w/Sublet' workbook and collapse it to one service line per
Dept + R/O # + Line #.

The w/Sublet report carries the 13 usual service columns followed by 'Description of sublet' and 'PO #', and repeats a
service line once per sublet PO. r468 (F81): from 22 Oct 2026 Revolution may also send an OPTIONAL leading Type column
(D on data rows, T1 on the totals footer). Like the sales feed, the preparer drops it: Type is read here, checked against
the row's shape, and removed from the headers and from every row, so nothing downstream (manifest source_headers, raw_row,
the database) ever sees a Type column. A file without Type parses exactly as before. This module:

* finds data rows: a data row has an R/O # and a Line #; the totals footer (no R/O #, no Line #) is kept aside and never
  imported; any other row shape stops the whole file (nothing is guessed);
* r468: when the leading Type column is present, D must be a data row (or a row of another department, excluded as
  before), T1 must be the totals footer, and any other Type value (blank, lower case, T2, ...) stops the whole file;
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
TYPE_BASIS = 'absent_r442'          # manifest type_column: no Type column reaches the database (true with or without r468)
TYPE_COLUMN = 'Type'
TYPE_DATA, TYPE_FOOTER = 'D', 'T1'
TYPE_DROPPED = 'leading_type_dropped_r468'  # provenance source_type_column when the file had the leading Type column
TYPE_ABSENT = 'absent'


class ContractError(ValueError):
    pass


def norm(v):
    if v is None:
        return ''
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return str(v).strip()


def has_type_column(headers):
    """r468 (F81): True when the first header is exactly 'Type' (Revolution's optional leading Type column)."""
    return bool(headers) and norm(headers[0]) == TYPE_COLUMN


def check_headers(headers):
    """Returns the service headers WITHOUT the optional leading Type column (r468 drops it, like the sales feed)."""
    h = [norm(x) for x in headers]
    while h and h[-1] == '':
        h.pop()
    if h and h[0] == TYPE_COLUMN:
        h = h[1:]
    if TYPE_COLUMN in h:
        raise ContractError('headers: Type is only accepted as the first column (r468), got it at column %d' % (h.index(TYPE_COLUMN) + 2))
    if h[:len(BASE_HEADERS)] != BASE_HEADERS:
        raise ContractError('headers: expected the 13 service columns first, got %r' % h[:len(BASE_HEADERS)])
    extra = h[len(BASE_HEADERS):]
    if len(set(extra)) != len(extra) or any(x not in SUBLET_HEADERS for x in extra) or 'PO #' not in extra:
        raise ContractError('headers: only the optional sublet columns may follow, and PO # is required; got %r' % extra)
    return h


def classify(raw):
    """'data', 'footer', 'excluded_department' or raises, from the row's shape (r442). r468: when the file has a Type
    column, classify_typed() checks that D / T1 agree with this."""
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


def classify_typed(type_value, raw, rn=None):
    """r468 (F81): a row of a file WITH the leading Type column. D = data (or another department, excluded as before),
    T1 = the totals footer (skipped, exactly like the r442 footer). Any other Type value stops the whole file."""
    t = type_value.strip() if isinstance(type_value, str) else type_value
    where = 'row %s: ' % rn if rn is not None else 'row: '
    if t not in (TYPE_DATA, TYPE_FOOTER):
        raise ContractError(where + 'Type %r is not D (data) or T1 (footer); only D and T1 are accepted' % (type_value,))
    kind = classify(raw)
    if t == TYPE_FOOTER and kind != 'footer':
        raise ContractError(where + 'Type T1 (footer) but the row has an R/O # or Line #')
    if t == TYPE_DATA and kind == 'footer':
        raise ContractError(where + 'Type D (data) but the row has no R/O # and no Line #')
    return kind


def source_type_column(headers):
    """r468: provenance marker for the manifest's evidence: TYPE_DROPPED when the leading Type column was dropped, else
    TYPE_ABSENT. The manifest's own type_column stays TYPE_BASIS ('absent_r442'): no Type reaches the database."""
    return TYPE_DROPPED if has_type_column(headers) else TYPE_ABSENT


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
    typed = has_type_column(values[3])
    headers = check_headers(values[3])
    data, footer, excluded = [], [], []
    for rn, cells in enumerate(values[4:], 5):
        cells = tuple(cells)
        if all(x is None or norm(x) == '' for x in cells):
            continue
        if typed:
            # r468: drop the leading Type cell (like the sales feed); raw rows never carry a Type key.
            t, cells = cells[0], cells[1:]
            raw = dict(zip(headers, cells[:len(headers)]))
            kind = classify_typed(t, raw, rn)
        else:
            raw = dict(zip(headers, cells[:len(headers)]))
            kind = classify(raw)
        (data if kind == 'data' else footer if kind == 'footer' else excluded).append((rn, raw))
    if len(footer) > 1:
        raise ContractError('more than one footer row')
    return headers, data, footer, excluded, params
