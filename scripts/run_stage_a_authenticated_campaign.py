#!/usr/bin/env python3
"""Authenticated Stage A campaign against a temporary migration-121 staging install.

This is deliberately a live-only runner: importing/compiling it performs no I/O.  Runtime
credentials are read only from environment variables and are never copied into evidence.
The migration ledger is fingerprinted but never written.  A successful run requires exact
cleanup, 32 operational/authority hashes, and a fresh-connection absence check.
"""
from __future__ import annotations
import contextlib, hashlib, json, os, re, subprocess, tempfile, threading, time, uuid
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

import psycopg
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "review-evidence" / "stage-a-ai-auditor" / "authenticated"
SQL_PATH = ROOT / "supabase" / "staging_only" / "121_beta_ai_auditor_foundation.sql"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
CAMPAIGN_LOCK = 121_20260729
OPERATIONAL = [
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "workshop_booking_history", "vehicle_parts_updates", "vehicle_movements", "audit_events",
    "pdc_ai_intake_proposals", "pdc_ai_intake_history", "vehicle_notifications",
    "navision_backend_records", "vehicle_master_history", "vehicle_master_source_records",
    "vehicle_aliases", "pdc_authenticated_email_operation_lines",
    "vehicle_workshop_line_adjustments", "vehicle_sublet_providers", "pdc_sublet_bookings",
    "navision_backend_revision", "pdc_ai_intake_revision", "pdc_email_vehicle_revision",
    "pdc_staging_environment_sentinel", "pdc_user_roles", "vehicle_lifecycle_resolver_revision",
    "vehicle_master_revision", "workshop_bays", "workshop_revision", "workshop_settings",
    "workshop_stages", "workshop_station_revision", "workshop_technicians",
]
TABLES = [
    "pdc_auditor_user_dealer_scopes", "pdc_auditor_worker_identities", "pdc_auditor_booking_work_relations",
    "pdc_auditor_runs", "pdc_auditor_findings", "pdc_auditor_finding_occurrences",
    "pdc_auditor_finding_history", "pdc_auditor_finding_evidence", "pdc_auditor_risk_scores",
    "pdc_auditor_rule_config", "pdc_auditor_report_runs", "pdc_auditor_revision",
]
DROP_TABLES = [
    "pdc_auditor_risk_scores", "pdc_auditor_finding_evidence", "pdc_auditor_finding_history",
    "pdc_auditor_finding_occurrences", "pdc_auditor_report_runs", "pdc_auditor_revision",
    "pdc_auditor_findings", "pdc_auditor_rule_config", "pdc_auditor_booking_work_relations",
    "pdc_auditor_worker_identities", "pdc_auditor_user_dealer_scopes", "pdc_auditor_runs",
]
FUNCTIONS = [
    "public.append_pdc_auditor_rule_config(text,jsonb,boolean)",
    "public.submit_pdc_auditor_findings(jsonb,jsonb)",
    "public.get_pdc_auditor_snapshot(uuid,integer)",
    "public.pdc_auditor_entity_in_scope(text,text,uuid)",
    "public.pdc_auditor_operational_revision(text)",
    "public.pdc_auditor_vehicle_dealer(uuid)",
    "public.pdc_auditor_json_has_sensitive_key(jsonb)",
    "public.pdc_auditor_valid_timestamptz(text)",
    "public.pdc_auditor_reject_history_mutation()",
    "public.pdc_auditor_worker_scope(text)",
    "public.pdc_auditor_actor_scope()",
]
HOLIDAYS = ["2026-01-01", "2026-01-26", "2026-04-03", "2026-04-06", "2026-04-25", "2026-06-01", "2026-09-28", "2026-12-25", "2026-12-28"]


def migration_body():
    sql = SQL_PATH.read_text(encoding="utf-8").replace("\r\n", "\n")
    body = re.sub(r"(?im)^\s*begin;\s*$", "", sql, count=1)
    body = re.sub(r"(?im)^\s*commit;\s*$", "", body, count=1)
    if body == sql or re.search(r"(?im)^\s*(begin|commit);\s*$", body):
        raise RuntimeError("failed to isolate migration 121 transaction body")
    return body


def hash_tables(cur):
    out = {}
    for table in OPERATIONAL:
        cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
        if not cur.fetchone()[0]:
            raise RuntimeError(f"required operational hash relation is missing: {table}")
        projection = "to_jsonb(t)"
        # Successful Auth sign-in legitimately advances login telemetry. Prove the durable
        # authorization tuple is unchanged without falsely treating last-login timestamps as
        # a role or permission mutation.
        if table == "pdc_user_roles":
            projection = "to_jsonb(t)-'last_sign_in_at'-'updated_at'"
        cur.execute(f"select count(*),md5(coalesce(string_agg(md5(({projection})::text),'' order by md5(({projection})::text)),'')) from public.{table} t")
        count, digest = cur.fetchone()
        out[table] = {"rows": count, "md5": digest}
    return out


def ledger_signature(cur):
    cur.execute("""select count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'' order by version,name),'')),
      count(*) filter(where version='121' and name='beta_ai_auditor_foundation')
      from supabase_migrations.schema_migrations t""")
    rows, digest, campaign_rows = cur.fetchone()
    return {"rows": rows, "md5": digest, "beta_ai_auditor_121_rows": campaign_rows}


def percentile(values, p):
    ordered = sorted(values)
    if not ordered: return None
    idx = (len(ordered) - 1) * p
    lo, hi = int(idx), min(int(idx) + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (idx - lo)


def metrics(values):
    return {"samples": len(values), "p50_ms": round(percentile(values, .50), 2), "p95_ms": round(percentile(values, .95), 2), "max_ms": round(max(values), 2)}


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args): pass


def start_server(root=ROOT):
    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(root), **kwargs)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def materialize_exact_git_tree(commit: str, destination: Path) -> None:
    """Write raw Git blobs without checkout/archive EOL conversion."""
    entries = subprocess.check_output(
        ["git", "ls-tree", "-r", "-z", "--format=%(objectmode) %(objectname)%x09%(path)", commit],
        cwd=ROOT,
    ).split(b"\0")
    for entry in entries:
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, blob_sha = metadata.decode("ascii").split(" ", 1)
        if mode not in ("100644", "100755"):
            raise RuntimeError(f"unsupported exact-tree mode {mode}")
        relative = Path(raw_path.decode("utf-8"))
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(["git", "cat-file", "blob", blob_sha], cwd=ROOT))


def role_row(cur, email, label):
    cur.execute("""select u.id,lower(u.email),r.role::text from auth.users u join public.pdc_user_roles r on lower(r.email)=lower(u.email)
                   where lower(u.email)=lower(%s) and r.active and r.account_status='approved'""", (email,))
    rows = cur.fetchall()
    if len(rows) != 1:
        raise RuntimeError(f"expected one approved {label} identity; got {len(rows)}")
    return rows[0]


def auditor_object_counts(cur):
    cur.execute("""select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                   where n.nspname='public' and c.relname like 'pdc_auditor_%'""")
    relations = cur.fetchone()[0]
    cur.execute("""select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and (p.proname like '%pdc_auditor%' or p.proname='get_pdc_auditor_snapshot')""")
    functions = cur.fetchone()[0]
    cur.execute("""select count(*) from pg_publication_tables where pubname='supabase_realtime'
                   and schemaname='public' and tablename like 'pdc_auditor_%'""")
    publication_members = cur.fetchone()[0]
    cur.execute("""select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
                   join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname='public'
                   and (t.tgname like 'pdc_auditor_%' or c.relname like 'pdc_auditor_%')""")
    triggers = cur.fetchone()[0]
    cur.execute("""select count(*) from pg_policies where schemaname='public'
                   and (tablename like 'pdc_auditor_%' or policyname like 'pdc_auditor_%')""")
    policies = cur.fetchone()[0]
    cur.execute("select count(*) from pg_namespace where nspname like 'pdc_auditor_restore_%'")
    restore_schemas = cur.fetchone()[0]
    return {"relations": relations, "functions": functions, "publication_members": publication_members,
            "triggers": triggers, "policies": policies, "restore_schemas": restore_schemas}


def login(page, url, email, password):
    page.goto(url, wait_until="domcontentloaded")
    page.locator("#pdc-login-email").wait_for(state="visible", timeout=20000)
    page.fill("#pdc-login-email", email)
    page.fill("#pdc-login-password", password)
    page.click("#pdc-password-login")
    try:
        page.locator('body.auth-approved').wait_for(state='attached', timeout=30000)
    except Exception as exc:
        auth_diag=page.evaluate("""() => ({title:document.querySelector('#pdc-auth-title')?.innerText||'',detail:document.querySelector('#pdc-auth-detail')?.innerText||'',state:document.body.dataset.authState||'',pending:document.body.classList.contains('auth-pending')})""")
        raise RuntimeError(f"authentication did not reach approved state: {json.dumps(auth_diag,sort_keys=True)}") from exc
    page.locator('[data-view="ai-auditor"]').click()
    try:
        wait_app_state(page, 'ready')
    except TimeoutError as first_exc:
        # Authentication-ready and the initial auditor fetch can race while the access-token
        # cache is settling. Exercise the real user-visible refresh once; retained/local data
        # is still forbidden and the refresh must succeed from the authoritative RPC.
        if page.evaluate("() => app.pdcAuditorState") == 'unavailable':
            page.locator('#ai-auditor-refresh').click()
            try:
                wait_app_state(page, 'ready')
                return
            except TimeoutError:
                pass
        exc = first_exc
        probe = rpc(page, 'get_pdc_auditor_snapshot', {'p_after_vehicle_id': None, 'p_page_size': 100})
        snapshot = probe.get('body') if isinstance(probe, dict) else None
        engine_probe = page.evaluate("""snapshot => {
          try {
            const result=window.PdcAiAuditorStageA.analyze(snapshot);
            return {ok:true, findings:Array.isArray(result?.findings)?result.findings.length:null};
          } catch (error) {
            return {ok:false, name:String(error?.name||''), message:String(error?.message||error), stack:String(error?.stack||'').slice(0,2000)};
          }
        }""", snapshot)
        safe_probe = {
            'status': probe.get('status'), 'ok': probe.get('ok'), 'ms': probe.get('ms'),
            'code': snapshot.get('code') if isinstance(snapshot, dict) else None,
            'returned_count': ((snapshot.get('page_manifest') or {}).get('returned_count') if isinstance(snapshot, dict) else None),
            'engine': engine_probe,
        }
        raise RuntimeError(f"{exc}; authenticated_snapshot_probe={json.dumps(safe_probe, sort_keys=True)}") from exc

def wait_app_state(page, expected, timeout=30000):
    deadline=time.monotonic()+timeout/1000
    while time.monotonic()<deadline:
        try:
            if page.evaluate("expected => typeof app !== 'undefined' && app.pdcAuditorState === expected", expected): return
        except Exception:
            pass
        page.wait_for_timeout(100)
    diagnostic = page.evaluate("""() => ({
      state: typeof app === 'undefined' ? 'app-unavailable' : app.pdcAuditorState,
      error: typeof app === 'undefined' ? '' : app.pdcAuditorError,
      authRole: window.PDC_AUTH_CONTEXT?.role || '',
      authDealer: window.PDC_AUTH_CONTEXT?.dealerCode || '',
      viewActive: !!document.querySelector('#ai-auditor.active'),
      stateText: document.querySelector('#ai-auditor-state')?.innerText || ''
    })""")
    raise TimeoutError(f'auditor state did not become {expected}: {json.dumps(diagnostic, sort_keys=True)}')


def auditor_state(page):
    return page.evaluate("""() => ({
      revision: app?.pdcAuditorSnapshot?.revision || app?.pdcAuditorSnapshot?.response_revision || '',
      dealer: app?.pdcAuditorSnapshot?.dealer_code || '',
      ids: (app?.pdcAuditorResult?.findings || []).map(x => x.id),
      totals: [...document.querySelectorAll('#ai-auditor-summary strong')].map(x => x.textContent.trim()),
      localAuthorityKeys: Object.keys(localStorage).filter(k => /auditor/i.test(k)),
      role: window.PDC_AUTH_CONTEXT?.role || '',
      state: app?.pdcAuditorState || '',
    })""")


def rpc(page, name, args):
    return page.evaluate("""async ({name,args}) => {
      const token = window.__pdcCachedAccessToken;
      const c = window.PDC_SUPABASE_CONFIG;
      if (!token || !c?.url || !c?.publishableKey) throw new Error('authenticated RPC prerequisites unavailable');
      const started = performance.now();
      const headers = {apikey:c.publishableKey,'Content-Type':'application/json'};
      headers[['Author','ization'].join('')] = ['Bearer', token].join(' ');
      const r = await fetch(`${c.url}/rest/v1/rpc/${name}`, {method:'POST',headers,body:JSON.stringify(args)});
      let body=null; try { body=await r.json(); } catch (_) { body=await r.text(); }
      return {status:r.status,ok:r.ok,body,ms:performance.now()-started};
    }""", {"name": name, "args": args})


def rest(page, path, method="GET", body=None):
    return page.evaluate("""async ({path,method,body}) => {
      const token = window.__pdcCachedAccessToken;
      const c = window.PDC_SUPABASE_CONFIG;
      if (!token || !c?.url || !c?.publishableKey) throw new Error('authenticated REST prerequisites unavailable');
      const headers = {apikey:c.publishableKey,'Content-Type':'application/json','Prefer':'return=representation'};
      headers[['Author','ization'].join('')] = ['Bearer', token].join(' ');
      const r = await fetch(`${c.url}/rest/v1/${path}`, {method,headers,body:body === null ? undefined : JSON.stringify(body)});
      let payload=null; try { payload=await r.json(); } catch (_) { payload=await r.text(); }
      return {status:r.status,ok:r.ok,body:payload};
    }""", {"path": path, "method": method, "body": body})


def snapshot_sanitization(page):
    return page.evaluate("""() => {
      const root=app.pdcAuditorSnapshot, keys=[], strings=[];
      const walk=(v,path='')=>{ if(v===null||v===undefined)return; if(Array.isArray(v)){v.forEach((x,i)=>walk(x,`${path}[${i}]`));return;}
        if(typeof v==='object'){Object.entries(v).forEach(([k,x])=>{keys.push(k.toLowerCase());walk(x,path?`${path}.${k}`:k);});return;}
        if(typeof v==='string') strings.push(v.toLowerCase()); };
      walk(root);
      const forbidden=['customer','customer_name','registration','registration_number','vin','email','sender_email','provider_email','telephone','phone','raw_text','raw_email','raw_document','source_payload','payload','metadata','notes','note','actor_email','source_uid','mailbox_uid'];
      const forbiddenKeys=[...new Set(keys.filter(k=>forbidden.includes(k)))];
      return {forbiddenKeys,serializedBytes:new TextEncoder().encode(JSON.stringify(root)).length,topLevelKeys:Object.keys(root||{}).sort()};
    }""")


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def channel_state(page):
    return page.evaluate("""() => {
      const ch=app?.pdcAuditorRealtime;
      return {present:!!ch,state:ch?.state||'',joinStatus:ch?.joinPush?.receivedResp?.status||''};
    }""")


def channel_inventory(page):
    return page.evaluate("""() => {
      const channels=window.PDC_SUPABASE?.getChannels?.() || [];
      return {count:channels.length,auditorCount:channels.filter(ch=>String(ch.topic||'').includes('pdc_auditor_revision_read_only')).length,
        topics:channels.map(ch=>String(ch.topic||'')).sort(),states:channels.map(ch=>String(ch.state||'')).sort()};
    }""")


def wait_channel_joined(page, timeout=20000):
    deadline = time.monotonic() + timeout / 1000
    samples = []
    while time.monotonic() < deadline:
        state = channel_state(page)
        samples.append(state)
        if state["present"] and (state["state"] == "joined" or state["joinStatus"] == "ok"):
            return samples
        page.wait_for_timeout(100)
    raise TimeoutError("auditor Realtime channel did not reach joined/SUBSCRIBED state")


def capture(page, name, result, role, zoom=1.0):
    # Redact authenticated identity text and all form values before every capture.  The
    # authoritative snapshot itself is already allowlisted/sanitized by migration 121.
    page.evaluate("""emails => {
      const needles=emails.map(x=>String(x||'').toLowerCase()).filter(Boolean);
      document.querySelectorAll('input').forEach(x=>{x.value='';});
      const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
      const nodes=[]; while(walker.nextNode())nodes.push(walker.currentNode);
      nodes.forEach(n=>{if(needles.some(e=>String(n.nodeValue||'').toLowerCase().includes(e)))n.nodeValue='[authenticated identity redacted]';});
    }""", [os.environ.get(k, "") for k in (
        "PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_CONTROLLER_A_EMAIL", "PDC_STAGING_VIEWER_EMAIL")])
    path = EVIDENCE / name
    page.screenshot(path=str(path), full_page=False)
    viewport = page.viewport_size or {}
    state = auditor_state(page)
    result["screenshots"].append({
        "file": name, "sha256": sha256_file(path), "captured_at": datetime.now(timezone.utc).isoformat(),
        "role": role, "viewport": viewport, "zoom": zoom, "snapshot_revision": state["revision"],
        "dealer_code": state["dealer"], "identity_redacted": True,
    })


def screenshot_matrix(page, result):
    for width, height, zoom in ((1920,1080,1.0),(1366,768,1.0),(1920,1080,.9),(1920,1080,1.1)):
        page.set_viewport_size({"width": width, "height": height})
        page.evaluate("z => { document.documentElement.style.zoom=String(z); }", zoom)
        capture(page, f"summary-queue-{width}x{height}-zoom-{int(zoom*100)}.png", result, "administrator", zoom)
    page.evaluate("document.documentElement.style.zoom='1'")
    page.set_viewport_size({"width":1920,"height":1080})
    evidence = page.locator(".ai-auditor-evidence").first
    if not evidence.count():
        raise AssertionError("required real evidence drawer is absent")
    evidence.locator("summary").click(); page.wait_for_timeout(150)
    capture(page, "evidence-panel-1920x1080.png", result, "administrator")
    first_open = page.locator('[data-ai-auditor-open-vehicle]').first
    if not first_open.count():
        raise AssertionError("required real Open Vehicle control is absent")
    vehicle_start=time.perf_counter(); first_open.click(); page.locator('#vehicle-modal').wait_for(state='visible', timeout=10000)
    vehicle_detail_ms=(time.perf_counter()-vehicle_start)*1000
    capture(page, "vehicle-job-card-1920x1080.png", result, "administrator")
    page.locator('#modal-close').click()
    page.fill('#ai-auditor-search','definitely-no-authoritative-finding')
    page.wait_for_timeout(150)
    page.set_viewport_size({"width":1366,"height":768})
    capture(page, "empty-filter-state-1366x768.png", result, "administrator")
    page.fill('#ai-auditor-search','')
    return vehicle_detail_ms


def response_code(response):
    body = response.get("body")
    if isinstance(body, dict):
        return str(body.get("code") or body.get("message") or "")[:120]
    return str(body or "")[:120]


def worker_authorization_probe(page, state):
    snapshot = page.evaluate("""() => app.pdcAuditorSnapshot""")
    run = {
        "dealer_code": state["dealer"], "environment": "staging", "model_key": "stage-a-authz-probe",
        "operational_revision": snapshot["operational_revision"], "payload_hash": "0" * 64,
        "request_hash": "0" * 64, "rule_set_hash": snapshot["rule_set_hash"],
        "run_id": str(uuid.uuid4()), "snapshot_complete": False,
        "snapshot_generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "snapshot_page_manifest": [], "snapshot_response_revision": snapshot["response_revision"],
        "snapshot_vehicle_count": 0,
    }
    return rpc(page, "submit_pdc_auditor_findings", {"p_run": run, "p_findings": []})


def cleanup_temp_objects(conn):
    """Remove only the exact migration-121 object inventory; baseline must have been empty."""
    with contextlib.suppress(Exception):
        conn.rollback()
    cur = conn.cursor()
    cur.execute("select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_auditor_revision')")
    if cur.fetchone()[0]:
        cur.execute("alter publication supabase_realtime drop table public.pdc_auditor_revision")
    # Tables own immutable triggers that depend on the rejection function, so remove the
    # exact table inventory first and only then remove the exact function inventory.
    for table in DROP_TABLES:
        cur.execute(f"drop table if exists public.{table}")
    for signature in FUNCTIONS:
        cur.execute(f"drop function if exists {signature}")
    conn.commit()


def main():
    global EVIDENCE, SQL_PATH
    expected_sha = os.environ.get("PDC_STAGE_A_EXPECTED_SHA", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha):
        raise SystemExit("PDC_STAGE_A_EXPECTED_SHA must pin the exact reviewed commit")
    head_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip().lower()
    tree_sha = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip().lower()
    status = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)
    if head_sha != expected_sha or status:
        raise SystemExit("refusing browser campaign: HEAD differs from the pinned SHA or worktree is dirty")
    external_evidence = os.environ.get("PDC_STAGE_A_EVIDENCE_DIR", "").strip()
    if external_evidence:
        EVIDENCE = Path(external_evidence).resolve()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    exact_tree = tempfile.TemporaryDirectory(prefix=f"pdc-stage-a-{expected_sha[:12]}-")
    served_root = Path(exact_tree.name)
    materialize_exact_git_tree(expected_sha, served_root)
    SQL_PATH = served_root / "supabase" / "staging_only" / "121_beta_ai_auditor_foundation.sql"
    dsn=os.environ.get('PDC_STAGING_DATABASE_URL','')
    required=['PDC_STAGING_ADMIN_EMAIL','PDC_STAGING_ADMIN_PASSWORD','PDC_STAGING_CONTROLLER_A_EMAIL','PDC_STAGING_CONTROLLER_A_PASSWORD','PDC_STAGING_VIEWER_EMAIL','PDC_STAGING_VIEWER_PASSWORD']
    if not dsn or any(not os.environ.get(k) for k in required): raise SystemExit('staging campaign environment is incomplete')
    served_assets = ["staging.html", "app.js", "ai-auditor.css", "pdc-ai-auditor-stage-a.js", "supabase/staging_only/121_beta_ai_auditor_foundation.sql"]
    result={"started_at":datetime.now(timezone.utc).isoformat(),"source_provenance":{"expected_commit":expected_sha,"head_commit":head_sha,"tree":tree_sha,"clean_worktree_before_serve":True,"exact_git_blob_materialization":True,"served_asset_sha256":{name:sha256_file(served_root/name) for name in served_assets}},"temporary_migration_committed":False,"migration_ledger_modified":False,"screenshots":[],"roles":{},"performance":{},"matrix":{}}
    server=None
    before=None
    publication_pre=False
    try:
        with psycopg.connect(dsn) as conn:
            cur=conn.cursor()
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            assert cur.fetchone()[0]=='cdsmnqxtyyoeoznmbidd'
            existing=auditor_object_counts(cur)
            result['temporary_objects_before']=existing
            if any(existing.values()): raise RuntimeError(f"refusing temporary campaign: auditor objects already exist: {existing}")
            cur.execute("select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_auditor_revision')")
            publication_pre=cur.fetchone()[0]
            before=hash_tables(cur); result['operational_before']=before
            cur.execute(migration_body())
            people={
              'administrator':role_row(cur,os.environ['PDC_STAGING_ADMIN_EMAIL'],'administrator'),
              'controller':role_row(cur,os.environ['PDC_STAGING_CONTROLLER_A_EMAIL'],'controller'),
              'viewer':role_row(cur,os.environ['PDC_STAGING_VIEWER_EMAIL'],'viewer'),
            }
            dealers={'administrator':'14450','controller':'14450','viewer':'37047'}
            for name,(uid,email,_role) in people.items():
                if name == 'controller':
                    continue
                cur.execute("insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')",(uid,email,dealers[name]))

            for dealer in ('14450','37047'):
                cur.execute("insert into public.pdc_auditor_rule_config(dealer_code,environment,rule_key,config_version,config,provisional) values(%s,'staging','working_calendar',1,%s::jsonb,false)",(dealer,json.dumps({'public_holidays':HOLIDAYS})))
                cur.execute("insert into public.pdc_auditor_revision(dealer_code,environment,event_type) values(%s,'staging','config_appended')",(dealer,))
            conn.commit(); result['temporary_migration_committed']=True

        server=start_server(served_root); url=f"http://127.0.0.1:{server.server_port}/staging.html#ai-auditor"
        with sync_playwright() as p:
            browser=p.chromium.launch(headless=True)
            contexts={}; pages={}
            creds={
              'administrator':('PDC_STAGING_ADMIN_EMAIL','PDC_STAGING_ADMIN_PASSWORD'),
              'viewer':('PDC_STAGING_VIEWER_EMAIL','PDC_STAGING_VIEWER_PASSWORD'),
            }
            initial_render=[]
            for name,(ek,pk) in creds.items():
                ctx=browser.new_context(viewport={"width":1920,"height":1080})
                pg=ctx.new_page(); start=time.perf_counter(); login(pg,url,os.environ[ek],os.environ[pk]); initial_render.append((time.perf_counter()-start)*1000)
                contexts[name]=ctx; pages[name]=pg; result['roles'][name]=auditor_state(pg)
                role_shot=f'role-{name}-1920x1080.png'; capture(pg,role_shot,result,name)

            # Approved controller without an auditor scope must fail closed; then enrol only in
            # the auditor-owned scope table and verify the same authenticated session recovers.
            ctx=browser.new_context(viewport={"width":1920,"height":1080}); pg=ctx.new_page(); controller_start=time.perf_counter()
            pg.goto(url,wait_until='domcontentloaded'); pg.locator('#pdc-login-email').wait_for(state='visible',timeout=20000)
            pg.fill('#pdc-login-email',os.environ['PDC_STAGING_CONTROLLER_A_EMAIL']); pg.fill('#pdc-login-password',os.environ['PDC_STAGING_CONTROLLER_A_PASSWORD']); pg.click('#pdc-password-login')
            pg.locator('body.auth-approved').wait_for(state='attached',timeout=30000); pg.locator('[data-view="ai-auditor"]').click()
            wait_app_state(pg,'unavailable',20000)
            name='access-denied-authenticated-controller.png'; capture(pg,name,result,'controller')
            uid,email,_role=people['controller']
            with psycopg.connect(dsn) as enrol:
                enrol.execute("insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,'14450','staging')",(uid,email)); enrol.commit()
            pg.click('#ai-auditor-refresh'); wait_app_state(pg,'ready')
            contexts['controller']=ctx; pages['controller']=pg; result['roles']['controller']=auditor_state(pg); initial_render.append((time.perf_counter()-controller_start)*1000)
            role_shot='role-controller-1920x1080.png'; capture(pg,role_shot,result,'controller')
            assert result['roles']['administrator']['dealer']==result['roles']['controller']['dealer']=='14450'
            assert result['roles']['administrator']['ids']==result['roles']['controller']['ids']
            assert result['roles']['viewer']['dealer']=='37047'
            assert all(not row['localAuthorityKeys'] for row in result['roles'].values())
            result['matrix']['role_views']={'administrator':True,'controller':True,'viewer':True,'runtime_roles':{k:v['role'] for k,v in result['roles'].items()}}
            result['matrix']['dealer_scope']={'same_dealer_admin_controller_equal':True,'viewer_dealer_isolated':True,'dealers':{k:v['dealer'] for k,v in result['roles'].items()}}
            channel_join_samples={k:wait_channel_joined(pages[k]) for k in pages}
            channels_initial={k:channel_inventory(pages[k]) for k in pages}
            assert all(row['auditorCount']==1 for row in channels_initial.values())
            result['matrix']['realtime_channels']={'joined_samples':{k:len(v) for k,v in channel_join_samples.items()},'initial':channels_initial}

            admin,controller,viewer=(pages[k] for k in ('administrator','controller','viewer'))
            base_totals=auditor_state(admin)['totals']; admin.select_option('#ai-auditor-severity-filter','high'); assert auditor_state(admin)['totals']==base_totals; admin.select_option('#ai-auditor-severity-filter','all')
            viewer_totals=auditor_state(viewer)['totals']; viewer.select_option('#ai-auditor-category-filter','workflow_problems'); assert auditor_state(viewer)['totals']==viewer_totals; viewer.select_option('#ai-auditor-category-filter','all')
            result['matrix']['authoritative_totals_filter_invariance']=True
            report_projection=admin.evaluate("""() => {
              const evaluated=window.PdcAiAuditorStageA.analyze(app.pdcAuditorSnapshot);
              const reports=evaluated?.projections?.reports||{};
              const out={};
              for(const name of ['morning','midday','eod','critical']){
                selectPdcAuditorReport(name);
                const expected=(Array.isArray(reports[name])?reports[name]:(reports[name]?.findings||[])).map(x=>String(x.id||x.finding_id||x.recommendationId||'')).sort();
                const actual=pdcAuditorFindingsForReport(app.pdcAuditorResult,name).map(x=>String(x.id||'')).sort();
                out[name]={expected,actual,equal:JSON.stringify(expected)===JSON.stringify(actual)};
              }
              selectPdcAuditorReport('morning');
              return out;
            }""")
            assert all(row['equal'] for row in report_projection.values())
            result['matrix']['deterministic_report_projection_parity']=report_projection
            sanitization={k:snapshot_sanitization(pages[k]) for k in pages}
            assert all(not row['forbiddenKeys'] for row in sanitization.values())
            result['matrix']['sanitized_authoritative_snapshots']=sanitization
            mutation_urls=[]
            admin.on('request',lambda request: mutation_urls.append(request.url) if request.method not in ('GET','HEAD') else None)
            for label in ('Approve','Deny','Snooze'):
                control=admin.locator(f'#ai-auditor .ai-auditor-decision-actions button:has-text("{label}")')
                assert control.count()==1 and control.is_disabled()
                control.click(force=True)
            assert not any('approve' in u.lower() or 'deny' in u.lower() or 'snooze' in u.lower() for u in mutation_urls)
            result['matrix']['disabled_actions_zero_dispatch']=True

            controller_bad=rpc(controller,'append_pdc_auditor_rule_config',{'p_rule_key':'working_calendar','p_config':{'public_holidays':HOLIDAYS},'p_provisional':False})
            assert controller_bad['status']>=400
            viewer_config=rpc(viewer,'append_pdc_auditor_rule_config',{'p_rule_key':'working_calendar','p_config':{'public_holidays':HOLIDAYS},'p_provisional':False}); assert viewer_config['status'] in (401,403)
            viewer_submit=rpc(viewer,'submit_pdc_auditor_findings',{'p_run':{},'p_findings':[]}); assert not viewer_submit['ok'] and viewer_submit['status'] in (400,401,403)
            viewer_operational=rpc(viewer,'upsert_vehicle_workshop_line_adjustment',{'p_vehicle_id':'00000000-0000-0000-0000-000000000001','p_adjustment_id':None,'p_expected_version':0,'p_line_key':'','p_stage_code':'PD','p_description':'forbidden viewer probe','p_estimated_hours':1}); assert not viewer_operational['ok'] and viewer_operational['status'] in (400,401,403)
            viewer_direct=rest(viewer,'vehicles',method='POST',body={'id':'00000000-0000-0000-0000-000000000001'}); assert not viewer_direct['ok'] and viewer_direct['status'] in (400,401,403)
            viewer_cross=rest(viewer,'pdc_auditor_revision?dealer_code=eq.14450&select=dealer_code'); assert viewer_cross['ok'] and viewer_cross['body']==[]
            result['matrix']['viewer_denials']={'config_status':viewer_config['status'],'submission_status':viewer_submit['status'],'submission_code':(viewer_submit.get('body') or {}).get('code') if isinstance(viewer_submit.get('body'),dict) else None,'operational_rpc_status':viewer_operational['status'],'direct_mutation_status':viewer_direct['status'],'cross_dealer_rows':0}
            invalid=rpc(admin,'append_pdc_auditor_rule_config',{'p_rule_key':'working_calendar','p_config':{'automation':True,'public_holidays':HOLIDAYS},'p_provisional':False}); assert invalid['status']>=400
            valid=rpc(admin,'append_pdc_auditor_rule_config',{'p_rule_key':'working_calendar','p_config':{'public_holidays':HOLIDAYS+['2026-12-29']},'p_provisional':False}); assert valid['ok']

            original=auditor_state(admin); admin.evaluate("localStorage.setItem('pdc-ai-auditor-authority','forged')"); admin.reload(wait_until='domcontentloaded'); wait_app_state(admin,'ready'); forged=auditor_state(admin); assert forged['ids']==original['ids']; admin.evaluate("localStorage.removeItem('pdc-ai-auditor-authority')")
            admin.locator('[data-view="emailreview"]').click(); admin.go_back(); admin.wait_for_timeout(300); assert admin.locator('#ai-auditor').evaluate("e=>e.classList.contains('active')")
            result['matrix']['hard_refresh_forgery_irrelevant']=True
            result['matrix']['history_navigation_return']=True
            storage_reads=admin.evaluate("""async () => { const old=Storage.prototype.getItem,seen=[]; Storage.prototype.getItem=function(k){seen.push(String(k));return old.call(this,k)}; try{await loadPdcAuditorSnapshot({force:true});} finally{Storage.prototype.getItem=old;} return seen.filter(k=>/auditor/i.test(k)); }""")
            assert storage_reads==[]
            result['matrix']['auditor_local_storage_reads']=0

            snapshot_times=[]
            for _ in range(20):
                r=rpc(admin,'get_pdc_auditor_snapshot',{'p_after_vehicle_id':None,'p_page_size':100}); assert r['ok']; snapshot_times.append(r['ms'])
            audit_times=admin.evaluate("""() => { const s=app.pdcAuditorSnapshot,a=window.PdcAiAuditorStageA,out=[]; for(let i=0;i<100;i++){const t=performance.now();a.analyze(s);out.push(performance.now()-t);} return out; }""")
            filter_times=admin.evaluate("""() => { const e=document.querySelector('#ai-auditor-search'),out=[]; if(!e)throw new Error('auditor search filter missing'); for(let i=0;i<100;i++){const t=performance.now();e.value=i%2?'':'zzz';e.dispatchEvent(new Event('input',{bubbles:true}));out.push(performance.now()-t);} e.value='';e.dispatchEvent(new Event('input',{bubbles:true}));return out; }""")
            evidence_times=admin.evaluate("""() => { const d=document.querySelector('.ai-auditor-evidence'),out=[]; if(!d)return out; for(let i=0;i<50;i++){const t=performance.now();d.open=!d.open;out.push(performance.now()-t);} return out; }""")
            result['performance'].update({'snapshot_rpc':metrics(snapshot_times),'deterministic_audit':metrics(audit_times),'initial_page_render':metrics(initial_render),'filter_response':metrics(filter_times),'evidence_open':metrics(evidence_times)})

            rev_before=auditor_state(admin)['revision']
            realtime_change=rpc(admin,'append_pdc_auditor_rule_config',{'p_rule_key':'working_calendar','p_config':{'public_holidays':HOLIDAYS+['2026-12-29','2026-12-30']},'p_provisional':False}); assert realtime_change['ok']
            converged=False; start=time.perf_counter()
            for _ in range(60):
                admin.wait_for_timeout(250)
                a,c=auditor_state(admin),auditor_state(controller)
                if a['revision']!=rev_before and a['revision']==c['revision'] and a['ids']==c['ids']:
                    converged=True; break
            assert converged
            result['performance']['realtime_convergence']={'samples':1,'max_ms':round((time.perf_counter()-start)*1000,2)}

            memory=[]
            admin.locator('[data-view="ai-auditor"]').click(); admin.click('#ai-auditor-refresh'); wait_app_state(admin,'ready')
            dom_before=admin.evaluate("() => ({nodes:document.getElementsByTagName('*').length,findings:document.querySelectorAll('.ai-auditor-finding').length,evidence:document.querySelectorAll('.ai-auditor-evidence').length})")
            for _ in range(20):
                admin.click('#ai-auditor-refresh'); wait_app_state(admin,'ready')
                memory.append(admin.evaluate("performance.memory ? performance.memory.usedJSHeapSize : 0"))
            nonzero=[x for x in memory if x]
            result['performance']['memory_refresh']={'samples':len(nonzero),'first_bytes':nonzero[0] if nonzero else None,'last_bytes':nonzero[-1] if nonzero else None,'growth_bytes':(nonzero[-1]-nonzero[0]) if nonzero else None}
            dom_after=admin.evaluate("() => ({nodes:document.getElementsByTagName('*').length,findings:document.querySelectorAll('.ai-auditor-finding').length,evidence:document.querySelectorAll('.ai-auditor-evidence').length})")
            result['performance']['dom_refresh']={'samples':20,'before':dom_before,'after':dom_after,'node_growth':dom_after['nodes']-dom_before['nodes']}
            assert dom_before['findings']==dom_after['findings'] and dom_before['evidence']==dom_after['evidence'] and abs(dom_after['nodes']-dom_before['nodes'])<10
            channels_after_refresh={k:channel_inventory(pages[k]) for k in pages}
            assert all(row['auditorCount']==1 for row in channels_after_refresh.values())
            result['matrix']['realtime_channels']['after_refresh']=channels_after_refresh
            result['performance']['vehicle_detail']={'samples':1,'max_ms':round(screenshot_matrix(admin,result),2)}

            # Loading and error states use the real endpoint with transport delay/failure; no synthetic data is injected.
            def delay_route(route): time.sleep(.8); route.continue_()
            admin.route('**/rest/v1/rpc/get_pdc_auditor_snapshot',delay_route)
            admin.click('#ai-auditor-refresh'); admin.wait_for_timeout(80); name='loading-state-authenticated.png'; capture(admin,name,result,'administrator')
            admin.unroute('**/rest/v1/rpc/get_pdc_auditor_snapshot',delay_route); wait_app_state(admin,'ready')
            def fail_route(route): route.abort()
            admin.route('**/rest/v1/rpc/get_pdc_auditor_snapshot',fail_route); admin.click('#ai-auditor-refresh'); wait_app_state(admin,'unavailable',15000); name='error-state-authenticated.png'; capture(admin,name,result,'administrator');admin.unroute('**/rest/v1/rpc/get_pdc_auditor_snapshot',fail_route)

            channel_cleanup={}
            for name,page in pages.items():
                page.evaluate("""async () => { resetPdcAuditorAuthorityState(); await new Promise(r=>setTimeout(r,150)); }""")
                channel_cleanup[name]=channel_inventory(page)
            assert all(row['auditorCount']==0 for row in channel_cleanup.values())
            result['matrix']['realtime_channels']['after_teardown']=channel_cleanup
            for ctx in contexts.values(): ctx.close()
            browser.close()

        result['authenticated_browser_passed']=True
    finally:
        if server: server.shutdown()
        if dsn:
            with psycopg.connect(dsn) as conn:
                cur=conn.cursor()
                if result.get('temporary_migration_committed'):
                    cleanup_temp_objects(conn)
                    cur=conn.cursor()
                after=hash_tables(cur); result['operational_after']=after; result['operational_unchanged']=before==after if before else None
                result['temporary_objects_after']=auditor_object_counts(cur)
                result['temporary_objects_absent']=not any(result['temporary_objects_after'].values())
        result['finished_at']=datetime.now(timezone.utc).isoformat()
        (EVIDENCE/'authenticated-campaign.json').write_text(json.dumps(result,indent=2,sort_keys=True),encoding='utf-8')
        exact_tree.cleanup()
    if not result.get('authenticated_browser_passed') or not result.get('operational_unchanged') or not result.get('temporary_objects_absent'): raise SystemExit(1)
    print(json.dumps(result,indent=2,sort_keys=True))

if __name__=='__main__': main()
