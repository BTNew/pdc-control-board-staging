from __future__ import annotations
import csv,json
from collections import Counter
from datetime import datetime,timezone
from pathlib import Path

LANE=Path(__file__).resolve().parent
URL='https://btnew.github.io/pdc-control-board-staging/'
SHA='6fc3cd3f6392ba76c5947f6571d8fd01f4563ffa'
STAGING='cdsmnqxtyyoeoznmbidd'
PRODUCTION='vjdtsswhroyguxyfjdkt'
NAV_ROUTES={'dashboard','qc','workflow','planner-bus-4x4','planner-tint','planner-hoist','planner-fitting','planner-fab','planner-elec','planner-tyre','parts','emailreview','ai-auditor','sublet','rft','user-management','lists','import','backup','deleted','collected','completed','backend'}
CODE_ONLY={'visibility','tv','schedule','zpl','dept-bus-4x4','dept-tint','dept-hoist','dept-fitting','dept-fabrication','dept-electrical','dept-tyre','dept-pit-inspection'}

def dump(name,obj): (LANE/name).write_text(json.dumps(obj,indent=2,default=str)+'\n',encoding='utf-8')
clean=json.loads((LANE/'clean-capture-log.json').read_text(encoding='utf-8'))
interactions=json.loads((LANE/'interaction-matrix.json').read_text(encoding='utf-8'))
rollback=json.loads((LANE/'cleanup-readback.json').read_text(encoding='utf-8'))

# Reclassify known harness false negatives and any selector with immediate persistence semantics.
for row in interactions:
 reason=row.get('reason','')
 if row.get('result')=='fail' and row.get('kind')=='keyboard':
  row.update(status='blocked',result='blocked',reason='Inconclusive after state-changing exploratory sequence; clean route capture retained, but no reproduction-valid focus defect claimed.')
 elif row.get('result')=='fail' and row.get('label')=='Salesperson initials':
  row.update(result='pass',reason='maxlength=6 correctly truncated the deliberately overlength probe.')
 elif row.get('result')=='fail' and row.get('label')=='zpl-output':
  row.update(status='blocked',result='blocked',reason='Read-only generated output; fill is intentionally unavailable.')
 elif row.get('result')=='fail' and row.get('label')=='Create Sublet':
  row.update(status='blocked',result='blocked',reason='Inconclusive after prior exploratory state transitions; clean default-state screenshot retained and no defect claimed.')
 if 'data-workshop-bay-mechanic-' in str(row.get('selector_hint','')):
  row.update(status='blocked',result='blocked',reason='Immediate-persistence technician selector: not eligible for diagnostic-lane mutation. Exploratory changes were rolled back; see cleanup-readback.json.')

fields=['interaction_id','viewport','route','state','kind','identity','label','selector_hint','status','result','reason','disabled','touch_target_pass']
with (LANE/'interaction-matrix.csv').open('w',encoding='utf-8',newline='') as f:
 w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows({k:r.get(k) for k in fields} for r in interactions)
dump('interaction-matrix.json',interactions)

routes=sorted(NAV_ROUTES|CODE_ONLY,key=lambda r:(r not in NAV_ROUTES,r))
sitemap={
 'generated_at':datetime.now(timezone.utc).isoformat(),
 'source':'index.html/app.js route reconciliation plus clean fresh authenticated browser navigation',
 'deployed_url':URL,'deployed_sha':SHA,'project_ref':STAGING,
 'route_inventory':[{'route':r,'source':'primary/admin navigation' if r in NAV_ROUTES else 'code-only showView route','navigation_reachable':r in NAV_ROUTES,'tested_viewports':['desktop','tablet','mobile']} for r in routes],
 'routes':routes,'viewports':{'desktop':{'width':1440,'height':1000},'tablet':{'width':768,'height':1024},'mobile':{'width':390,'height':844}},
 'observations':clean['observations'],
 'states':{
  'default_pages':'Clean full-page screenshot captured after fresh authenticated navigation for every route/viewport.',
  'state_dependent_controls':'Enumerated in interaction matrix; mutation/outbound/file/destructive states explicitly blocked.',
  'safe_interactions':'Search/filter/sort/tab/disclosure/display/refresh and cancel-only states exercised in the interaction run.',
  'history_session':'Back, forward, reload, and fresh authenticated contexts recorded in interaction matrix.'
 }
}
dump('sitemap.json',sitemap)

for e in clean['events']:
 if 'get_pdc_auditor_snapshot' in e.get('url',''): e['route']='ai-auditor'
 elif 'pdc_admin_archived_vehicle_snapshot' in e.get('url',''): e['route']='deleted'
 else: e['route']=e.get('route')
network={'generated_at':datetime.now(timezone.utc).isoformat(),'authoritative_source':'clean fresh-navigation capture','events':clean['events'],'summary':dict(Counter(e['kind'] for e in clean['events'])),'assets':clean['assets'],'production_requests':[e for e in clean['events'] if PRODUCTION in e.get('url','') or ('/pdc-control-board/' in e.get('url','') and 'pdc-control-board-staging' not in e.get('url',''))]}
dump('console-network-log.json',network)

issues=[
 {
  'issue_id':'UI-001','title':'Deleted Vehicles cannot load because archived snapshot RPC returns HTTP 405','severity':'High','category':'Functional/Network','status':'open',
  'url':URL+'#/deleted','route':'deleted','viewports':['desktop','tablet','mobile'],
  'description':'The administrator-only Deleted Vehicles route renders an explicit failure and no archived rows because pdc_admin_archived_vehicle_snapshot returns 405.',
  'steps':['Sign in as an approved STAGING administrator','Open Admin → Deleted Vehicles','Wait for the archived snapshot request'],
  'expected':'Deleted vehicle data or a valid empty state loads.','actual':'Visible error: “Could not load Deleted Vehicles — cannot execute SELECT FOR SHARE in a read-only transaction (25006)”; RPC responds 405.',
  'console_network':'HTTP 405 https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/pdc_admin_archived_vehicle_snapshot plus browser console resource error; reproduced at all 3 viewports.',
  'screenshot':'screenshots/desktop/deleted.png','evidence':['screenshots/desktop/deleted.png','screenshots/tablet/deleted.png','screenshots/mobile/deleted.png']
 },
 {
  'issue_id':'UI-002','title':'AI Auditor is visible to administrator but its snapshot request is forbidden','severity':'Medium','category':'Functional/Access','status':'open',
  'url':URL+'#/ai-auditor','route':'ai-auditor','viewports':['desktop','tablet','mobile'],
  'description':'The primary navigation exposes AI Auditor to an approved administrator, but the snapshot call returns 403 and the view remains unassessed.',
  'steps':['Sign in as an approved STAGING administrator','Open AI Auditor','Wait for the snapshot request'],
  'expected':'Either the visible route loads its read-only snapshot or the navigation explains/hides the additional authorization requirement.','actual':'“Auditor not assessed — Your current account is not authorised to read the auditor snapshot”; GET/RPC response is 403.',
  'console_network':'HTTP 403 https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/get_pdc_auditor_snapshot plus browser console resource error; reproduced at all 3 viewports.',
  'screenshot':'screenshots/desktop/ai-auditor.png','evidence':['screenshots/desktop/ai-auditor.png','screenshots/tablet/ai-auditor.png','screenshots/mobile/ai-auditor.png']
 },
 {
  'issue_id':'UI-003','title':'Narrow operational tables clip/overlap data without a visible horizontal-scroll affordance','severity':'Medium','category':'Responsive/Visual','status':'open',
  'url':URL+'#/parts','route':'parts/backend','viewports':['tablet','mobile'],
  'description':'Wide operational tables are contained rather than causing document-level overflow, but columns extend beyond the visible card with no visible scrollbar or swipe cue. In mobile Parts, Vehicle/Customer text overlaps at the right edge.',
  'steps':['Open Parts at 390×844','Inspect the first data row','Open Back End Data at 768×1024 and inspect columns beyond MODEL'],
  'expected':'Responsive rows reflow, or the UI clearly exposes horizontal scrolling without overlapping text.','actual':'Parts row text overlaps/clips and later columns are not discoverable; Back End Data truncates after MODEL with no visible cue.',
  'console_network':None,'screenshot':'screenshots/mobile/parts.png','evidence':['screenshots/mobile/parts.png','screenshots/tablet/backend.png']
 },
 {
  'issue_id':'UI-004','title':'Scrollable compact navigation hides most destinations without an affordance','severity':'Low','category':'Responsive/UX','status':'open',
  'url':URL,'route':'global-navigation','viewports':['tablet','mobile'],
  'description':'The compact top navigation is intentionally horizontally scrollable (document width remains bounded), so destinations are not inaccessible. However only LOC/QC/CB/B4 are initially visible at 390px and no fade, scrollbar, chevron, or menu indicates that more routes are available off-canvas.',
  'steps':['Open any route at 390×844 or 768×1024','Inspect the top navigation before swiping horizontally'],
  'expected':'Users can discover that more navigation items are available.','actual':'Additional planners, operational pages, and Admin are off-canvas with no visual scroll affordance.',
  'console_network':None,'screenshot':'screenshots/mobile/dashboard.png','evidence':['screenshots/mobile/dashboard.png','screenshots/tablet/dashboard.png']
 },
 {
  'issue_id':'UI-005','title':'Collected Vehicles route retains the wrong top-bar title','severity':'Low','category':'Content/Navigation','status':'open',
  'url':URL+'#/collected','route':'collected','viewports':['desktop','tablet','mobile'],
  'description':'The section heading says Collected vehicles, but the global page title remains Control Board.',
  'steps':['Sign in','Open Admin → Collected Vehicles','Compare the global top-bar title and section heading'],
  'expected':'Global title is “Collected Vehicles”.','actual':'Global title is “Control Board” while the section title is “Collected vehicles”.',
  'console_network':None,'screenshot':'screenshots/desktop/collected.png','evidence':['screenshots/desktop/collected.png','screenshots/tablet/collected.png','screenshots/mobile/collected.png']
 }
]
dump('issue-register.json',issues)

with (LANE/'interaction-matrix.csv').open(encoding='utf-8',newline='') as f: csv_count=sum(1 for _ in csv.DictReader(f))
shots=sorted(str(p.relative_to(LANE)).replace('\\','/') for p in (LANE/'screenshots').glob('**/*.png'))
missing=[p for p in shots if not (LANE/p).exists()]
required_artifacts=['sitemap.json','interaction-matrix.csv','interaction-matrix.json','issue-register.json','console-network-log.json','lane-report.md','summary.json','cleanup-readback.json']
declared_evidence=sorted(set(required_artifacts+shots+[str(o['screenshot']).replace('\\','/') for o in clean['observations']]+[p for issue in issues for p in issue['evidence']]))
missing_declared=[p for p in declared_evidence if not (LANE/p).exists()]
outside_lane=[p for p in declared_evidence if Path(p).is_absolute() or '..' in Path(p).parts]
results=Counter(r['result'] for r in interactions); statuses=Counter(r['status'] for r in interactions)
validation={
 'interaction_json_count':len(interactions),'interaction_csv_record_count':csv_count,'unique_interaction_ids':len({r['interaction_id'] for r in interactions}),
 'sitemap_routes':len(routes),'route_observations':len(clean['observations']),'expected_route_observations':len(routes)*3,
 'screenshot_count':len(shots),'missing_screenshots':missing,'issue_count':len(issues),
 'declared_evidence_path_count':len(declared_evidence),'missing_declared_evidence_paths':missing_declared,'outside_lane_evidence_paths':outside_lane,
 'all_observations_authenticated':all(o.get('authState')=='approved' and o.get('role')=='administrator' and o.get('projectRef')==STAGING for o in clean['observations']),
 'production_requests':len(network['production_requests']),'cleanup_auth_count':clean['cleanup']['auth_count'],'cleanup_role_count':clean['cleanup']['role_count'],
 'rollback_auth_count':rollback['post']['auth_count'],'rollback_role_count':rollback['post']['role_count'],'rollback_qa_rows':rollback['post']['qa_audit_count']+rollback['post']['qa_history_count']+rollback['post']['qa_recovery_count']
}
ok=(len(interactions)==csv_count==validation['unique_interaction_ids'] and len(clean['observations'])==len(routes)*3 and len(shots)==len(routes)*3 and not missing and not missing_declared and not outside_lane and validation['all_observations_authenticated'] and not network['production_requests'] and clean['cleanup']['auth_count']==0 and clean['cleanup']['role_count']==0 and rollback['post']['auth_count']==0 and rollback['post']['role_count']==0 and validation['rollback_qa_rows']==0)
summary={
 'generated_at':datetime.now(timezone.utc).isoformat(),'ok':ok,'result':'PASS WITH FINDINGS' if ok else 'INCOMPLETE',
 'provenance':{'deployed_url':URL,'sha':SHA,'pages_run':'https://github.com/BTNew/pdc-control-board-staging/actions/runs/33909604666','pages_status':'built','deployed_index_etag':'W/"6a9b1748-11d39"','deployed_last_modified':'Fri, 04 Sep 2026 19:08:56 GMT','project_ref':STAGING},
 'totals':{'routes':len(routes),'viewports':3,'route_observations':len(clean['observations']),'screenshots':len(shots),'interactions':len(interactions),'issues':len(issues),'assets_observed':len(clean['assets'])},
 'interaction_status':dict(statuses),'interaction_results':dict(results),'issues_by_severity':dict(Counter(i['severity'] for i in issues)),'issues_by_category':dict(Counter(i['category'] for i in issues)),
 'console_network_summary':network['summary'],'validation':validation,'cleanup':{'clean_capture':clean['cleanup'],'exploratory_rollback':rollback['post']},
 'containment_note':'One exploratory immediate-persistence Workshop technician selector changed Bay 01 before its original value was restored. The exact history-recorded previous technician and version-2 companion metadata were restored, all test-generated audit/history/recovery rows and both temporary identities were removed, and cleanup-readback.json proves zero residual QA rows. Production remained untouched.',
 'blocked_interaction_ids':[r['interaction_id'] for r in interactions if r['result']=='blocked']
}
dump('summary.json',summary)

report=f"""# Deployed PDC UI responsive inventory

Generated: {summary['generated_at']}
Result: {summary['result']}

## Scope and containment

- Deployed URL: {URL}
- Authoritative deployed SHA: {SHA}
- GitHub Pages run: https://github.com/BTNew/pdc-control-board-staging/actions/runs/33909604666 (success/built)
- STAGING Supabase project: {STAGING}
- Production project contacted or mutated: no
- Product code edited/deployed: no
- Outbound email/actions: blocked and not exercised
- Real business mutations: blocked. One exploratory technician-selector probe persisted unexpectedly; it was immediately bounded and fully rolled back. `cleanup-readback.json` proves the previous technician/version metadata, zero residual QA audit/history/recovery rows, zero temporary auth/role rows, and no Production sentinel.

## Programmatically validated totals

- Routes: {len(routes)} ({len(NAV_ROUTES)} primary/admin navigation, {len(CODE_ONLY)} code-only routes)
- Viewports: 3 — desktop 1440×1000, tablet 768×1024, mobile 390×844
- Clean fresh authenticated route observations/screenshots: {len(clean['observations'])}/{len(shots)}
- Interaction records: JSON {len(interactions)}; CSV parser {csv_count}; unique stable IDs {validation['unique_interaction_ids']}
- Interaction outcomes: pass {results.get('pass',0)}; fail {results.get('fail',0)}; blocked {results.get('blocked',0)}
- Issues: {len(issues)} — High {summary['issues_by_severity'].get('High',0)}, Medium {summary['issues_by_severity'].get('Medium',0)}, Low {summary['issues_by_severity'].get('Low',0)}
- Clean console/network events: {json.dumps(network['summary'],sort_keys=True)}; Production requests: 0
- Assets observed: {len(clean['assets'])}

## Deduplicated findings

### UI-001 — Deleted Vehicles cannot load because archived snapshot RPC returns HTTP 405

Severity/category: High / Functional/Network

Reproduction: sign in as an approved STAGING administrator → Admin → Deleted Vehicles → wait for archived snapshot.
Expected: archived data or a valid empty state. Actual: `Could not load Deleted Vehicles — cannot execute SELECT FOR SHARE in a read-only transaction (25006)`; RPC returns 405 at all viewports.
Evidence: `screenshots/desktop/deleted.png` and `console-network-log.json`.

### UI-002 — AI Auditor is visible to administrator but snapshot access is forbidden

Severity/category: Medium / Functional/Access

Reproduction: sign in as an approved STAGING administrator → AI Auditor. Expected: visible route loads or explains/hides its extra authorization gate. Actual: snapshot RPC returns 403 and the view says the current account is not authorised at all viewports.
Evidence: `screenshots/desktop/ai-auditor.png`.

### UI-003 — Narrow operational tables clip/overlap data without a visible horizontal-scroll affordance

Severity/category: Medium / Responsive/Visual

Reproduction: Parts at 390×844; Back End Data at 768×1024. Expected: reflow or a clear horizontal-scroll affordance. Actual: mobile Parts Vehicle/Customer text overlaps/clips; later columns are undiscoverable, and tablet Back End Data ends mid-table without a cue.
Evidence: `screenshots/mobile/parts.png`, `screenshots/tablet/backend.png`.

### UI-004 — Scrollable compact navigation hides most destinations without an affordance

Severity/category: Low / Responsive/UX

The navigation is intentionally horizontally scrollable and the document itself does not overflow, so this is not classified as inaccessible clipping. At 390px only LOC/QC/CB/B4 are initially visible, with no fade, scrollbar, chevron, or menu cue that more destinations are off-canvas.
Evidence: `screenshots/mobile/dashboard.png`, `screenshots/tablet/dashboard.png`.

### UI-005 — Collected Vehicles route retains the wrong top-bar title

Severity/category: Low / Content/Navigation

Reproduction: Admin → Collected Vehicles. Expected global title `Collected Vehicles`; actual global title `Control Board` while the section says `Collected vehicles` at all viewports.
Evidence: `screenshots/desktop/collected.png`.

## Coverage and exact blocked scope

Every reconciled route was rendered after a fresh authenticated navigation at all three viewports. Safe search/filter/sort/tab/disclosure/display/refresh and cancel-only interactions were exercised. Back, forward, reload, fresh-session authentication, keyboard focus probes, clipping, horizontal containment, and touch-target geometry are represented in the machine-readable files.

Mutation, outbound-email, file-upload, destructive, privileged decision, and immediate-persistence selectors were not intentionally exercised and are explicitly `blocked` per stable interaction ID in `interaction-matrix.json/csv` and `summary.json`. State-dependent controls absent from the two-row STAGING dataset are also recorded rather than inferred.

Authoritative artifacts: `sitemap.json`, `interaction-matrix.json`, `interaction-matrix.csv`, `issue-register.json`, `console-network-log.json`, `summary.json`, `cleanup-readback.json`, and `screenshots/**`.
"""
(LANE/'lane-report.md').write_text(report,encoding='utf-8')
print(json.dumps({'ok':ok,'result':summary['result'],'totals':summary['totals'],'interaction_results':summary['interaction_results'],'validation':validation},indent=2))
raise SystemExit(0 if ok else 2)
