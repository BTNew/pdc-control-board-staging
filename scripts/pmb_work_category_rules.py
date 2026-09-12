"""Craig's explicit work routing, 12 September 2026.

Generate review proposals only. Keep source hours and manual staff choices intact.
Specific product rules precede generic keyword and department defaults.
"""
import re
from decimal import Decimal, InvalidOperation

VERSION = 'craig_work_categories_20260912'

def category(description):
    s = re.sub(r'\s+', ' ', str(description or '').upper()).strip()
    roof = bool(re.search(r'ROOF[ -]?RACK|RHINO[ -]?RACK', s))
    whip = bool(re.search(r'WHIP[ -]?FLAGS?', s))
    if (re.search(r'\b(?:FILL\s+(?:WITH\s+)?FUEL|FULL\s+TANK\s+(?:OF\s+)?FUEL|REFUEL(?:LING|ING)?|PIT\s*(?:AND|&)\s*WEIGH)\b', s)
        or re.search(r'BATTERY\s*100\s*%', s)):
        return 'FITTING', 'preparation_fitting'
    if re.search(r'MINE[ -]?BARS?', s) or (whip and (roof or re.search(r'LIGHT|LED|ILLUMINAT', s))):
        return 'ELECTRICAL', 'mine_bar_or_lit_roof_whip'
    if re.search(r'SUBCORE?\b.*(?:SIGN|LOGO|RIBBON)', s):
        return 'SUBLET', 'subcore_signs'
    if re.search(r'\bPTE\b.*TRAY', s):
        return 'SUBLET', 'pte_tray'
    if (re.search(r'HEAVY[ -]?DUTY.*RUBBER.*(?:FLOOR[ -]?)?MATS?', s)
        or re.search(r'\b(?:PROTECTED|PROTECTA)\b.*MATS?', s)
        or re.search(r'VINYL[ -]?FLOOR', s)):
        return 'SUBLET', 'floor_coverings'
    if (re.search(r'\b(?:HI[ -]?DRIVE|HIGH[ -]?DRIVE|BOSTON|MTE)\b.*(?:CANOP|BULL|MOTOR[ -]?BOD|BODIES|BODY)', s)
        or re.search(r'\bCANOP(?:Y|IES)\b|BODY[ -]?BUILDER', s)) and not re.search(r'SOCKET|OUTLET|ANDERSON|COMPRESSOR|BEACON|DECAL|FRIDGE[ -]?SLIDE|AIR[ -]?VENT|SECURITY[ -]?GRILL|ROOF[ -]?RACK|RHINO[ -]?RACK|CABINET|LIGHT', s):
        return 'SUBLET', 'canopy_body_builder'
    if re.search(r'WHEEL[ -]?CHOCK', s):
        return 'FITTING', 'wheel_chocks_fitting'
    if re.search(r'TRIANGLE.*(?:MOUNT|HOLDER)|(?:MOUNT|HOLDER).*TRIANGLE', s):
        return 'FABRICATION', 'mounted_triangle_holder_fabrication'
    if re.search(r'MMT.*SEAT[ -]?COVERS?', s):
        return 'SUBLET', 'mmt_seat_covers_sublet'
    if re.search(r'MANUAL.*ROLLER.*PZQ7D0K050', s):
        return 'FITTING', 'toyota_manual_roller_cover'
    if re.search(r'RYCO.*CATCH[ -]?CAN.*KIT', s):
        return 'FITTING', 'ryco_catch_can_kit'
    if re.search(r'ADDITIONAL.*(?:GENUINE|ALLOY).*RIM', s):
        return 'FABRICATION', 'additional_genuine_alloy_rim'
    if re.search(r'SPARE[ -]?(?:TYRE|WHEEL).*(?:HOLDER|MOUNT).*PMB.*CAB[ -]?RACK', s):
        return 'FABRICATION', 'pmb_cab_rack_tyre_holder'
    if (re.search(r'CERTIFIED.*MESH.*CAB[ -]?RACK.*BARRIER', s)
        or re.search(r'ADDITIONAL.*ALLOY.*RIMS?', s)
        or (re.search(r'\b(?:800\s*MM\s*)?TOOL[ -]?BOX(?:ES)?\b', s) and not re.search(r'CENTRAL[ -]?LOCK|SOCKET|OUTLET|WIRING|LIGHT', s))
        or re.search(r'TIE[ -]?DOWN.*(?:POINT|ANCHOR).*FLOOR', s)
        or re.search(r'SPARE[ -]?WHEEL.*(?:MOUNT|HOLDER).*\b(?:TRAY|TOOL[ -]?BOX)', s)):
        return 'FABRICATION', 'fabricated_accessory'
    if (re.search(r'BUSHRANGER.*COVERT.*WINCH', s) or roof
        or re.search(r'FIRST[ -]?AID.*KIT', s)
        or re.search(r'ANTI[ -]?THEFT.*(?:NUMBER|NO[ .-]?)[ -]?PLATE.*SCREW', s)
        or re.search(r'\bEV[ -]?TAGS?\b', s)):
        return 'FITTING', 'specific_minor_or_roof_fitment'
    # Product identifiers / PMB-branded descriptions, not incidental location mentions.
    if re.search(r'\bPMB[ -]*0*02\b|\bPMB[ -]+ITEMS?\b|^PMB(?:[A-Z]?\d+)?\b', s):
        return 'FABRICATION', 'pmb_product'
    return None, None

def _hours(value):
    if value is None or value == '':
        return None
    try:
        n = Decimal(str(value))
        if not n.is_finite() or n < 0:
            raise ValueError('Invalid hours')
        return n
    except InvalidOperation as exc:
        raise ValueError('Invalid hours') from exc

def propose(description, source_hours=None, fallback_station='REVIEW', department=None,
            staff_station=None, staff_hours=None):
    """Immutable source value plus separate effective-hour/station proposal.

    Source zero is a placeholder unless a specific zero-hour instruction is present.
    Explicit staff zero is preserved for review, never replaced by a default.
    """
    matched, rule = category(description)
    station = staff_station or matched or ('BUS_4X4' if str(department) == '138' else fallback_station)
    original = _hours(source_hours)
    effective = _hours(staff_hours) if staff_hours is not None else original
    provenance = 'staff_estimate' if staff_hours is not None else 'source_estimate'
    needs_review = False
    default_hours = None
    default_provenance = None
    d = re.sub(r'\s+', ' ', str(description or '').upper()).strip()
    if station == 'ELECTRICAL':
        default_hours = Decimal('1.5'); default_provenance = 'craig_electrical_default_1_5_hours'
    elif station == 'FITTING' and re.search(r'MANUAL.*ROLLER.*PZQ7D0K050', d):
        default_hours = Decimal('3'); default_provenance = 'craig_manual_roller_cover_default_3_hours'
    elif station == 'FITTING' and re.search(r'ARB.*COMMERCIAL.*BULL[ -]?BAR', d) and 'HILUX' in d and re.search(r'MY ?26', d):
        default_hours = Decimal('5'); default_provenance = 'craig_my26_hilux_arb_commercial_bar_5_hours'
    elif station == 'FITTING' and re.search(r'RYCO.*CATCH[ -]?CAN.*KIT', d):
        default_hours = Decimal('1.5'); default_provenance = 'craig_ryco_catch_can_default_1_5_hours'
    elif station == 'FABRICATION':
        if re.search(r'ADDITIONAL.*(?:GENUINE|ALLOY).*RIM', d):
            default_hours = Decimal('0.5'); default_provenance = 'craig_additional_rim_default_0_5_hours'
        elif re.search(r'TIE[ -]?DOWN.*POINT.*FLOOR', d):
            quantity = re.search(r' X\s*(\d+)\b', d)
            default_hours = Decimal(quantity[1] if quantity else '1'); default_provenance = 'craig_floor_tie_down_1_hour_each'
        elif re.search(r'PMB.*STEEL.*TRAY|PMB.*TRAY.*STEEL', d):
            default_hours = Decimal('2'); default_provenance = 'craig_steel_tray_default_2_hours'
        elif re.search(r'MESH.*CAB[ -]?RACK.*BARRIER', d):
            default_hours = Decimal('0.5'); default_provenance = 'craig_mesh_cab_rack_default_0_5_hours'
        elif re.search(r'SPARE[ -]?(?:TYRE|WHEEL).*(?:HOLDER|MOUNT).*PMB.*CAB[ -]?RACK', d):
            default_hours = Decimal('0.5'); default_provenance = 'craig_tyre_holder_default_0_5_hours'
    if default_hours is not None and staff_hours is None and (original is None or original == 0):
        times = {Decimal(n) / (60 if unit.lower().startswith('min') else 1)
                 for n, unit in re.findall(r'\b(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?)\b',str(description or ''),re.I)}
        if len(times) > 1:
            effective = None; provenance = 'conflicting_description_times'; needs_review = True
        elif times:
            effective = times.pop(); provenance = 'explicit_description_time'
        else:
            effective = default_hours; provenance = default_provenance
    return {'proposed_station':station,'source_estimated_hours':source_hours,
            'effective_estimated_hours':float(effective) if effective is not None else None,
            'hours_provenance':provenance,'routing_rule':rule,'routing_rule_version':VERSION,
            'routing_provenance':'staff_assignment' if staff_station else 'explicit_owner_rule' if matched else 'existing_default',
            'needs_hours_review':needs_review or (station != 'SUBLET' and (effective is None or effective <= 0))}

def apply_to_rows(rows):
    """Use on NEW service request preparation, never mutate saved/replayed payloads."""
    result=[]
    for row in rows:
        proposal=propose(row.get('operation_description'),row.get('source_estimated_hours'),
                         row.get('proposed_station','REVIEW'),row.get('department'),
                         row.get('staff_station'),row.get('staff_hours'))
        # Preserve source, descriptions and all raw cells. Provenance is additive.
        result.append(dict(row,**proposal))
    return result
