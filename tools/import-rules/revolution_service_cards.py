"""r572 (F186). Several department 138 and 139 job cards on one vehicle.

Craig, 27 Oct 2026 08:41 AWST: when the import sees more than one 138 or 139
job card for the same stock number, or the same rego when Stock is blank,
those cards stay on that one vehicle. Each card keeps its own department,
repair order and line. Nothing is renumbered and no hours move between cards.

A case with more than one live vehicle is ambiguous and is not merged.
A new card on the existing vehicle is a normal preview insert. It is not
an operation-update quarantine. Sub Status 80 or 99 closes that card only.
The vehicle stays active while any other card is open. This module does not
write, close, hide or delete anything.
"""

CLOSING = ('80', '99')
DEPARTMENTS = ('138', '139')
FLAG = 'open_card_lines_missing_on_board'


def _clean(value):
    return (value or '').strip()


def group(stock, rego, vehicle_count, dept):
    """One live vehicle groups the cards. More than one is ambiguous. None does not merge."""
    department = _clean(dept)
    count = int(vehicle_count or 0)
    has_stock = _clean(stock) != ''
    has_rego = _clean(rego) != ''
    if department not in DEPARTMENTS:
        return {'group': False, 'ambiguous': False, 'key': None, 'reason': 'dept_out_of_scope'}
    if count > 1:
        return {'group': False, 'ambiguous': True, 'key': 'stock' if has_stock else 'rego', 'reason': 'ambiguous_vehicle'}
    if count == 1 and has_stock:
        return {'group': True, 'ambiguous': False, 'key': 'stock', 'reason': 'stock'}
    if count == 1 and not has_stock and has_rego:
        return {'group': True, 'ambiguous': False, 'key': 'rego', 'reason': 'rego'}
    return {'group': False, 'ambiguous': False, 'key': None, 'reason': 'no_vehicle'}


def attach(existing_vehicle, ro_on_vehicle, owner_hold, dept):
    """A new 138/139 card on an existing vehicle is an insert. A held stock is not attached.
    A line on a card the vehicle already has can stay in review. Department 135 is untouched."""
    department = _clean(dept)
    if department == '135':
        return {'attach': False, 'quarantine': False, 'reason': 'dept_135'}
    if owner_hold:
        return {'attach': False, 'quarantine': False, 'reason': 'owner_hold'}
    if existing_vehicle and not ro_on_vehicle and department in DEPARTMENTS:
        return {'attach': True, 'quarantine': False, 'reason': 'new_card'}
    if existing_vehicle and ro_on_vehicle:
        return {'attach': False, 'quarantine': True, 'reason': 'existing_card_line'}
    return {'attach': False, 'quarantine': False, 'reason': 'not_a_new_card'}


def card_close(sub_status, other_open):
    """80 or 99 closes this card. The vehicle closes only when no other card is open.
    Nothing here deletes, tombstones, hides or auto-closes the vehicle."""
    closing = _clean(sub_status) in CLOSING
    return {
        'close_card': closing,
        'close_vehicle': closing and not bool(other_open),
        'delete': False,
        'tombstone': False,
        'hide': False,
        'auto_close': False,
    }


def reconcile_flag(file_lines, board_lines, sub_status):
    """Flag only. An open card that has lines in the file and none on the board.
    A pending review row is not a board line. This does not insert the lines."""
    sub = _clean(sub_status)
    return (file_lines or 0) > 0 and (board_lines or 0) == 0 and sub not in CLOSING


def reconcile_item(dept, ro, stock, file_lines, board_lines, sub_status):
    if not reconcile_flag(file_lines, board_lines, sub_status):
        return None
    return {
        'category': FLAG,
        'department': dept,
        'ro': ro,
        'stock': stock,
        'file_lines': file_lines,
        'board_lines': 0,
    }
