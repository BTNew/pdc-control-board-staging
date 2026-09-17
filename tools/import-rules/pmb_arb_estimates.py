"""Mandatory ARB research checkpoint for NEW import requests. No board writes.

Search returns evidence candidates, not an automatic product/fitment match.
Supply a reviewed arb_review record, then finalize_rows before hashing a request.
"""
import json, re
from pathlib import Path
from decimal import Decimal
GUIDE_VERSION='DRT20260901.1'
GUIDE_SHA256='4e1a8c9cd5f317d1a9b28fbf0c9448f1b33a33651e4dff8507e9947a157c46c6'
CATALOGUES={
    GUIDE_VERSION: ('arb-toyota-guide-index.json', GUIDE_SHA256),
    'RT20260901.1': ('arb-guide-index.json', '6ceaecee5b8a8e4fb23127de0941b06ca710b09a3b76dfb4f1e6f2c39af78163'),
}
CATALOGUE_DIRECTORY=Path(__file__).parent
UNABLE_REASONS={'missing_vehicle_context','ambiguous_kit','incompatible_scope','unsupported_product','no_published_labour','conditional_or_bundled'}

def search_guide(terms,limit=12,guide_version=None,vehicle_terms=None):
    """Evidence candidates only. Search Toyota first; select RT explicitly for other makes.

    Supply model/series/cab context in vehicle_terms. Review page heading and
    exclusions; a text search is never proof of compatible fitment.
    """
    versions=[guide_version] if guide_version else list(CATALOGUES)
    words=[t.casefold().strip() for t in terms if t.strip()]
    context=[t.casefold().strip() for t in (vehicle_terms or []) if t.strip()]
    hits=[]
    for priority,version in enumerate(versions):
        filename,digest=CATALOGUES[version]
        data=json.loads((CATALOGUE_DIRECTORY/filename).read_text(encoding='utf-8'))
        if data['guide_sha256']!=digest or data['guide_version']!=version:
            raise ValueError('Wrong ARB guide index')
        for page in data['pages']:
            folded=page['text'].casefold()
            found=[t for t in words if t in folded]
            matched_context=[t for t in context if t in folded]
            if found and (not context or matched_context):
                hits.append(dict(page=page['page'],matched_terms=found,text=page['text'],
                    guide_version=version,guide_sha256=digest,matched_vehicle_terms=matched_context,
                    catalogue_priority=priority))
    return sorted(hits,key=lambda x:(x['catalogue_priority'],-len(x['matched_vehicle_terms']),-len(x['matched_terms']),x['page']))[:limit]

def needs_lookup(r):
    source=r.get('source_estimated_hours')
    if source not in (None,'') and Decimal(str(source))>0: return False
    if r.get('proposed_station')=='SUBLET' or r.get('staff_hours') is not None: return False
    proof=r.get('hours_provenance','')
    if proof.startswith('craig_') and Decimal(str(r.get('effective_estimated_hours') or 0))>0: return False
    if proof=='explicit_description_time': return False
    return True

def catalogue_estimate(r):
    """Verified reusable matches only. Unknown descriptions still require interpreted review.

    vehicle_context must come from an exact current Stock/Navision match or an
    explicit model/production field in the source. Never infer age from email date.
    """
    if not needs_lookup(r): return None
    ctx=r.get('vehicle_context') or (r.get('raw_row') or {}).get('vehicle_context') or {}
    if ctx.get('source') not in {'unique_current_exact_stock_navision','explicit_source_vehicle_context'}: return None
    vehicle=str(ctx.get('vehicle') or ctx.get('model') or '')
    month=str(ctx.get('production_month') or '')
    if not re.search(r'hilux',vehicle,re.I) or not re.fullmatch(r'12/25|0[1-9]/26|1[0-2]/26|202512|2026(0[1-9]|1[0-2])',month): return None
    d=str(r.get('operation_description') or '').strip().upper()
    if not re.fullmatch(r'SAFARI[ -]+SNORKEL(?:[ -]+(?:V[ -]?SPEC|ARMAX|SS223HF|SS223HP))?(?:\s*\*[^*]*\*)?\s*',d): return None
    # Verify that the installed reference still contains the exact product evidence.
    data=json.loads((CATALOGUE_DIRECTORY/CATALOGUES[GUIDE_VERSION][0]).read_text(encoding='utf-8'))
    if data['guide_version']!=GUIDE_VERSION or data['guide_sha256']!=GUIDE_SHA256: raise ValueError('Wrong ARB guide index')
    page=next(x['text'] for x in data['pages'] if x['page']==56)
    if not all(x in page for x in ['SS223HF','SS223HP','320.00','400.00']): raise ValueError('ARB evidence changed; re-review page56')
    if re.search(r'V[ -]?SPEC|SS223HF',d): h=lo=hi=2;cost=320;kit='SS223HF'
    elif re.search(r'ARMAX|SS223HP',d): h=lo=hi=2.5;cost=400;kit='SS223HP'
    else: h=2.25;lo=2;hi=2.5;cost=320;kit='SS223HF / SS223HP'
    return dict(checked=True,status='estimated',guide_version=GUIDE_VERSION,guide_sha256=GUIDE_SHA256,pages=[5,56],searched_terms=[d,'HiLux MY26'],
        estimated_hours=h,fitting_charge=cost,labour_rate=160,comparable_min_hours=lo,comparable_max_hours=hi,vehicle_context=ctx,
        match_basis=f'HiLux MY26 production {month}: {kit}; published fitting 320/160=2h or400/160=2.5h; chosen {h}h is within15% of the relevant candidates.',
        reviewed_candidates=[dict(part='SS223HF',hours=2),dict(part='SS223HP',hours=2.5)],
        caveat='AI estimate; confirm ordered kit. Excludes relocating non-original accessories.')

def validate(r):
    if not needs_lookup(r): return True
    a=r.get('arb_review') or {}
    if not (a.get('checked') is True and a.get('guide_version') in CATALOGUES and a.get('guide_sha256')==CATALOGUES[a['guide_version']][1] and len(a.get('match_basis','').strip())>=15 and a.get('searched_terms')):
        return False
    if a.get('status')=='unable':
        # An executed keyword search is not a completed fitment review. New requests
        # must record why specific candidates cannot support a defensible estimate.
        return (len(a.get('reason','').strip())>15 and not r.get('effective_estimated_hours')
            and a.get('unable_reason_code') in UNABLE_REASONS
            and isinstance(a.get('reviewed_candidates'),list)
            and isinstance(a.get('vehicle_context'),dict)
            and bool(a['vehicle_context'].get('source')))
    if a.get('status')!='estimated' or r.get('hours_provenance')!='ai_estimated' or not a.get('pages'): return False
    try:
        h=Decimal(str(r['effective_estimated_hours'])); cost=Decimal(str(a['fitting_charge'])); rate=Decimal(str(a['labour_rate']))
        candidates=[cost/rate,Decimal(str(a['comparable_min_hours'])),Decimal(str(a['comparable_max_hours']))]
        return rate==160 and 0<h<=Decimal('999.99') and h==h.quantize(Decimal('.01')) and all(c>0 and abs(h-c)/c<=Decimal('.15') for c in candidates)
    except (KeyError,ValueError,ArithmeticError): return False

def finalize_rows(rows):
    result=[]
    for original in rows:
        r=dict(original)
        # A previous generic Unable must not bypass a verified catalogue match.
        matched=catalogue_estimate(r)
        if matched and (not r.get('arb_review') or r['arb_review'].get('status')=='unable'):
            r['arb_review']=matched
        a=r.get('arb_review')
        if a and needs_lookup(r):
            if a.get('status')=='estimated':
                r.update(effective_estimated_hours=a.get('estimated_hours',a.get('calculated_hours')),hours_provenance='ai_estimated',needs_hours_review=False)
            elif a.get('status')=='unable':
                r.update(effective_estimated_hours=0,hours_provenance='estimate_unable',needs_hours_review=True)
        if not validate(r):
            raise ValueError(f"ARB guide check required: {r.get('stock_number')} / {r.get('repair_order_number')} / line {r.get('original_line_number')}: {r.get('operation_description')}")
        if a: r['raw_row']=dict(r.get('raw_row') or {},arb_review=a)
        result.append(r)
    return result

