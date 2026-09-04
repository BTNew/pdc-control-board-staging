from __future__ import annotations
import json,secrets,string,sys,time
from datetime import datetime,timezone
from pathlib import Path
from urllib.request import Request,urlopen

from playwright.sync_api import sync_playwright

LANE=Path(__file__).resolve().parent
ROOT=LANE.parents[3]
SCREENSHOTS=LANE/'screenshots'
sys.path.insert(0,str(ROOT/'scripts'))
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import STAGING_REF,management_query,supabase_access_token
from run_ui_inventory import EMAIL,PRODUCTION_REF,ROUTES,URL,VIEWPORTS,active_state


def request_json(url,method='GET',headers=None,payload=None):
 body=None if payload is None else json.dumps(payload).encode()
 req=Request(url,data=body,method=method,headers=headers or {})
 with urlopen(req,timeout=60) as response:
  raw=response.read().decode(); return json.loads(raw) if raw else None


def state():
 return management_query(f"select jsonb_build_object('auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null)) as state")[0]['state']


def main():
 before=state()
 if before!={'auth_count':0,'role_count':0,'production_sentinel_present':False}: raise RuntimeError(f'preflight failed: {before}')
 password=''.join(secrets.choice(string.ascii_letters+string.digits+'!@#$%^&*()-_=+') for _ in range(48))
 service=''; uid=''; observations=[]; events=[]; assets={}; cleanup={}; error=''
 try:
  keys=request_json(f'https://api.supabase.com/v1/projects/{STAGING_REF}/api-keys',headers={'Authorization':f'Bearer {supabase_access_token()}','Accept':'application/json','User-Agent':'SupabaseCLI/2.116.0'})
  service=str(next((x for x in keys if x.get('name')=='service_role'),{}).get('api_key') or '')
  headers={'apikey':service,'Authorization':f'Bearer {service}','Content-Type':'application/json','Accept':'application/json'}
  uid=str(request_json(f'https://{STAGING_REF}.supabase.co/auth/v1/admin/users',method='POST',headers=headers,payload={'email':EMAIL,'password':password,'email_confirm':True}).get('id') or '')
  for _ in range(10):
   rows=management_query(f"select count(*)::int c from public.pdc_user_roles where lower(email)='{EMAIL}'")[0]['c']
   if rows: break
   time.sleep(.25)
  management_write(f"update public.pdc_user_roles set display_name='UI Inventory Test Administrator',role='administrator',active=true,account_status='approved',auth_user_id='{uid}'::uuid,approved_at=coalesce(approved_at,clock_timestamp()),updated_at=clock_timestamp() where lower(email)='{EMAIL}'")
  with sync_playwright() as p:
   browser=p.chromium.launch(headless=True)
   for viewport_name,viewport in VIEWPORTS.items():
    context=browser.new_context(viewport=viewport)
    page=context.new_page(); page.set_default_timeout(3000)
    def request_seen(req,v=viewport_name):
     if PRODUCTION_REF in req.url or ('/pdc-control-board/' in req.url and 'pdc-control-board-staging' not in req.url): events.append({'kind':'production-request','viewport':v,'url':req.url})
    def failed(req,v=viewport_name): events.append({'kind':'requestfailed','viewport':v,'url':req.url,'failure':req.failure})
    def response_seen(res,v=viewport_name):
     if res.status>=400: events.append({'kind':'http-error','viewport':v,'status':res.status,'url':res.url})
     if res.url.startswith(URL): assets[res.url]={'url':res.url,'status':res.status,'content_type':res.headers.get('content-type'),'etag':res.headers.get('etag'),'last_modified':res.headers.get('last-modified')}
    page.on('request',request_seen); page.on('requestfailed',failed); page.on('response',response_seen)
    page.on('pageerror',lambda exc,v=viewport_name: events.append({'kind':'pageerror','viewport':v,'message':str(exc)}))
    page.on('console',lambda msg,v=viewport_name: events.append({'kind':'console','viewport':v,'level':msg.type,'message':msg.text}) if msg.type in {'error','warning'} else None)
    for route in ROUTES:
     page.goto(URL+f'?clean_inventory={int(time.time())}-{viewport_name}-{route}',wait_until='domcontentloaded',timeout=90000)
     page.wait_for_function("() => ['signed-out','approved'].includes(document.body.dataset.authState)",timeout=90000)
     if page.evaluate("() => document.body.dataset.authState")=='signed-out':
      page.locator('#pdc-login-email').fill(EMAIL); page.locator('#pdc-login-password').fill(password); page.locator('#pdc-password-login').click()
      page.wait_for_function("() => document.body.dataset.authState === 'approved'",timeout=90000)
     page.evaluate("route => showView(route,{historyMode:'replace'})",route); page.wait_for_timeout(350)
     observed=active_state(page); shot=SCREENSHOTS/viewport_name/f'{route}.png'; shot.parent.mkdir(parents=True,exist_ok=True)
     page.screenshot(path=str(shot),full_page=True,timeout=30000)
     observed.update({'viewport':viewport_name,'route':route,'screenshot':str(shot.relative_to(LANE)).replace('\\','/'),'clean_fresh_navigation':True})
     observations.append(observed)
    context.close()
   browser.close()
 except Exception as exc:
  error=f'{type(exc).__name__}: {exc}'
 finally:
  errors=[]
  if uid:
   try:
    cleanup['rows']=management_write(f"""
with a as (delete from public.audit_events where actor_id='{uid}'::uuid returning id),
 r as (delete from public.workshop_schedule_recovery_receipts where actor_user_id='{uid}'::uuid returning receipt_id),
 h as (delete from public.workshop_bay_default_technician_history where actor_id='{uid}'::uuid returning id)
select (select count(*) from a)::int audit_events,(select count(*) from r)::int recovery_receipts,(select count(*) from h)::int bay_history
""")
   except Exception as exc: errors.append(f'bounded rows: {exc}')
   try: request_json(f'https://{STAGING_REF}.supabase.co/auth/v1/admin/users/{uid}',method='DELETE',headers={'apikey':service,'Authorization':f'Bearer {service}','Accept':'application/json'})
   except Exception as exc: errors.append(f'auth delete: {exc}')
  try: management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
  except Exception as exc: errors.append(f'role delete: {exc}')
  cleanup.update(state()); cleanup['errors']=errors
  password=''; service=''; uid=''
  payload={'generated_at':datetime.now(timezone.utc).isoformat(),'error':error or None,'observations':observations,'events':events,'assets':sorted(assets.values(),key=lambda x:x['url']),'cleanup':cleanup}
  (LANE/'clean-capture-log.json').write_text(json.dumps(payload,indent=2,default=str)+'\n',encoding='utf-8')
  print(json.dumps({'ok':not error and len(observations)==len(ROUTES)*len(VIEWPORTS) and cleanup.get('auth_count')==0 and cleanup.get('role_count')==0 and not errors,'error':error or None,'observations':len(observations),'events':len(events),'assets':len(assets),'cleanup':cleanup},indent=2))
 return 0 if not error and len(observations)==len(ROUTES)*len(VIEWPORTS) and cleanup.get('auth_count')==0 and cleanup.get('role_count')==0 and not errors else 2

if __name__=='__main__': raise SystemExit(main())
