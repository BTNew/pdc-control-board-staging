"""Reviewed workshop-manager defaults for new imports; never edits saved board rows.

Private registry is installed beside this module. Exact model, department, bay and
full description are required. Explicit source/staff times and owner rules win.
"""
import json,re
from pathlib import Path
from decimal import Decimal,InvalidOperation

REGISTRY=Path(__file__).with_name('workshop-hour-standards.json')
def normalize(value):
    return re.sub(r'\s+',' ',str(value or '')).strip().upper()

def reviewed_standard(row,registry=None):
    if str(row.get('department') or '').strip()!='138':return None
    if row.get('staff_hours') is not None or row.get('manual_assignment_locked') is True:return None
    proof=str(row.get('hours_provenance') or '')
    if proof.startswith('craig_') or proof in {'staff_estimate','explicit_description_time','manual_operator','conflicting_description_times'}:return None
    try:
        source=row.get('source_estimated_hours')
        if source not in (None,'') and Decimal(str(source))!=0:return None
    except (InvalidOperation,ValueError):return None
    from pmb_work_category_rules import _description_times
    if _description_times(row.get('operation_description')):return None
    context=row.get('vehicle_context') or (row.get('raw_row') or {}).get('vehicle_context') or {}
    if context.get('source') not in {'unique_current_exact_stock_navision','explicit_source_vehicle_context'}:return None
    model=normalize(context.get('vehicle') or context.get('model'))
    if not model:return None
    if registry is None:
        if not REGISTRY.exists():return None
        registry=json.loads(REGISTRY.read_text(encoding='utf-8'))
    matched=[r for r in registry.get('rules',[]) if r.get('department')=='138'
        and normalize(r.get('model'))==model
        and normalize(r.get('description'))==normalize(row.get('operation_description'))
        and r.get('stage')==row.get('proposed_station')]
    if len(matched)!=1:return None
    rule=matched[0]
    if not rule.get('evidence') or not rule.get('id'):return None
    hours=Decimal(str(rule['hours']))
    if hours<Decimal('.1') or hours>999 or hours!=hours.quantize(Decimal('.01')):return None
    return dict(standard_id=rule['id'],registry_version=registry['version'],model=rule['model'],
        description=rule['description'],department='138',stage=rule['stage'],hours=float(hours),
        source=rule['source'],evidence=rule['evidence'])

def apply_reviewed_standard(original,registry=None):
    row=dict(original)
    standard=reviewed_standard(row,registry)
    if standard:
        row.update(effective_estimated_hours=standard['hours'],hours_provenance='craig_workshop_manager_standard',needs_hours_review=False)
        row['workshop_standard']=standard
        row['raw_row']=dict(row.get('raw_row') or {},workshop_standard=standard)
    return row