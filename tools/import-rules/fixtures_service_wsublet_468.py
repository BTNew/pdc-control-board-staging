"""r468 (F81): synthetic 'PMG PD Service Complete w/Sublet' worksheets, with and without Revolution's leading Type column.

Shaped like Kajel's 22 Oct 08:33 AWST file as reported (that file is not in this repo): 2,572 service lines across 154
stocks with 243 distinct sublet POs, service lines repeated once per PO, a department-135 row (excluded) and one totals
footer. Stock numbers, R/Os, regos, owners and POs are synthetic (SYN..., J13x9..., GP13x9...); no real data.
build(typed) returns worksheet rows (title, parameters, blank, headers, data..., footer) as read_values() expects;
write_xlsx() saves the same rows as a workbook for a manual run of the preparer.
"""
from revolution_service_wsublet import BASE_HEADERS, TITLE

HEADERS = BASE_HEADERS + ['Description of sublet', 'PO #']
PARAMS = 'Extracted on 22/10/2026 08:33   Parameters: Company = "01" Division = "1"'
EXPECTED = {'lines': 2572, 'stocks': 154, 'distinct_pos': 243}


def _lines():
    """[(stock_index, dept, ro, line_no, hours, [POs])] in source order: 108 stocks of 17 lines + 46 of 16 = 2,572."""
    out, po_seq = [], 0
    for s in range(154):
        dept = 138 if s % 5 == 0 else 139
        ro = 'J%d9%05d' % (dept, s + 1)
        for ln in range(1, (17 if s < 108 else 16) + 1):
            out.append([s, dept, ro, ln, round(0.5 + ((s * 7 + ln * 3) % 12) * 0.25, 2), []])
    # 243 distinct POs: PO k sits on line index k*10 (k < 243). Lines 0, 40, 80, ... (every 4th PO line) also carry a
    # second PO already used elsewhere (repeated rows, no new distinct PO), and line 1000 carries three POs.
    for k in range(243):
        dept = out[k * 10][1]
        out[k * 10][5].append('GP%d9%05d' % (dept, k + 1))
    for k in range(0, 243, 4):
        if k + 1 < 243:
            out[k * 10][5].append(out[(k + 1) * 10][5][0])
    out[1000][5] += [out[20][5][0], out[30][5][0]]
    return out


def rows():
    """Worksheet data rows (dicts over HEADERS) in source order, one per line per PO, plus one excluded 135 row."""
    data = []
    for s, dept, ro, ln, hours, pos in _lines():
        base = dict(zip(BASE_HEADERS, [dept, 'SYN%04d' % (s + 1), 'SYN-R%04d' % (s + 1), 'Synthetic Owner %d' % (s % 9),
                                       'A%d' % (s % 30), str(100 + s), ro, '20', ln, 'Synthetic operation %d' % ln, hours,
                                       '22/10/2026', 'HILUX']))
        for po in (pos or [None]):
            r = dict(base)
            r['Description of sublet'] = ('Sublet for %s' % po) if po else None
            r['PO #'] = po
            data.append(r)
        if s == 77 and ln == 3:
            x = dict(base); x['Dept'] = 135; x['R/O #'] = 'J135900001'; x['Description of sublet'] = None; x['PO #'] = None
            data.append(x)
    return data


_UNSET = object()


def build(typed=False, bad_type=_UNSET, bad_at=None):
    """typed: add the leading Type column (D on data rows, T1 on the footer). bad_type: put this Type value on data row
    number bad_at (0-based) instead of D (None and '' included), to check the preparer stops the file."""
    data = rows()
    hours = round(sum(r['Estimated labour hours'] for r in data), 2)
    header = (['Type'] if typed else []) + HEADERS
    out = [(TITLE,), (PARAMS,), (None,), tuple(header)]
    for i, r in enumerate(data):
        cells = [r.get(h) for h in HEADERS]
        if typed:
            cells = [bad_type if (bad_type is not _UNSET and i == bad_at) else 'D'] + cells
        out.append(tuple(cells))
    footer = [None] * len(HEADERS)
    footer[HEADERS.index('Estimated labour hours')] = hours
    out.append(tuple((['T1'] if typed else []) + footer))
    return out


def write_xlsx(path, **kw):
    import openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active
    for r in build(**kw):
        ws.append(list(r))
    wb.save(path)
    return path


if __name__ == '__main__':
    import sys
    d = sys.argv[1] if len(sys.argv) > 1 else '.'
    write_xlsx(d + '/PMG PD Service Complete w_Sublet - no Type (synthetic).xlsx')
    write_xlsx(d + '/PMG PD Service Complete w_Sublet - Type D-T1 (synthetic).xlsx', typed=True)
    write_xlsx(d + '/PMG PD Service Complete w_Sublet - bad Type (synthetic).xlsx', typed=True, bad_type='X', bad_at=500)
