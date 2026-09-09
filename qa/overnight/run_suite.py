"""Bounded verification runner: local tests plus public, read-only deployed-asset checks.
No Supabase JWT, privileged credential, mailbox, customer mutation or test auto-repair.
"""
from __future__ import annotations
import argparse,csv,hashlib,json,os,re,subprocess,sys,time,urllib.request
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SITE='https://btnew.github.io/pdc-control-board-staging/'

def command(args,log,timeout=180):
    started=time.monotonic()
    try:
        result=subprocess.run(args,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
        log.write_text(result.stdout+'\n'+result.stderr)
        return {'status':'PASS' if result.returncode==0 else 'FAIL','exit_code':result.returncode,'seconds':round(time.monotonic()-started,3),'log':log.name}
    except (OSError,subprocess.TimeoutExpired) as exc:
        log.write_text(str(exc));return {'status':'ERROR','error':str(exc)[:1000],'log':log.name}

def inventory(out):
    functions=[];attrs={};rpcs={}
    for file in sorted(ROOT.glob('*.js')):
        if file.name.startswith(('test_','browser_')):continue
        text=file.read_text()
        for m in re.finditer(r'\b(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(',text):
            functions.append({'file':file.name,'line':text.count('\n',0,m.start())+1,'function':m[1],
                'independent_function_certification':'NOT ESTABLISHED','evidence':'See test cases; inventory is not execution coverage'})
        for m in re.finditer(r'\bdata-[a-z][a-z0-9-]+',text):attrs.setdefault(m[0],set()).add(file.name)
        patterns=[r'/rpc/([a-z][a-z0-9_]+)',r'\b(?:rpc|callRpc)\(\s*[\'\"]([a-z][a-z0-9_]+)',r'\b[A-Z_]*RPC[A-Z_]*\s*=\s*[\'\"]([a-z][a-z0-9_]+)']
        for pattern in patterns:
            for name in re.findall(pattern,text):rpcs.setdefault(name,set()).add(file.name)
    with (out/'named-functions.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=['file','line','function','independent_function_certification','evidence']);w.writeheader();w.writerows(functions)
    for name,data in [('data-attributes',attrs),('literal-rpc-references',rpcs)]:
        with (out/(name+'.csv')).open('w',newline='') as f:
            w=csv.writer(f);w.writerow(['name','referencing_files','status']);w.writerows((k,';'.join(sorted(v)),'INVENTORIED, NOT AUTOMATICALLY CERTIFIED') for k,v in sorted(data.items()))
    return {'named_function_declarations':len(functions),'data_attributes':len(attrs),'literal_rpc_references':len(rpcs),'warning':'Regex inventory excludes dynamic/anonymous calls; data attributes are not all buttons. Counts are not function coverage.'}

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--engine',default='chromium');p.add_argument('--skip-public-fetch',action='store_true');a=p.parse_args()
    out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
    checks={};files=sorted(x.name for x in ROOT.glob('test_*.js'))
    checks['node_regressions']=command(['node','--test','--test-reporter=tap',*files],out/'node-regressions.tap')
    tap=(out/'node-regressions.tap').read_text()
    counts={k:int(m[1]) if (m:=re.search(r'^# '+k+r' (\d+)\s*$',tap,re.M)) else None for k in ('tests','pass','fail','skipped','cancelled')}
    checks['node_regressions']['counts']=counts
    checks['secret_scan']=command(['node','scripts/check_frontend_secrets.js'],out/'frontend-secret-scan.log')
    # All root deployable JS and QA JavaScript, not generated/minified vendor bytes.
    syntax=[]
    for file in [*sorted(ROOT.glob('*.js')),*sorted((ROOT/'qa/overnight').glob('*.js'))]:
        result=subprocess.run(['node','--check',str(file)],capture_output=True,text=True,timeout=20)
        if result.returncode:syntax.append({'file':str(file.relative_to(ROOT)),'error':result.stderr[:1200]})
    checks['javascript_parse']={'status':'PASS' if not syntax else 'FAIL','errors':syntax}
    checks['browser']=command([sys.executable,str(ROOT/'qa/overnight/browser_check.py'),'--engine',a.engine,'--output',str(out/'browser')],out/'browser.log',180)
    browser_path=out/'browser/browser-results.json'
    browser=json.loads(browser_path.read_text()) if browser_path.exists() else {'cases':[],'failed':1,'passed':0}
    checks['browser']['passed']=browser['passed'];checks['browser']['failed']=browser['failed']
    checks['public_deployment']={'status':'UNVERIFIED','reason':'Not requested in this local run'}
    if not a.skip_public_fetch:
        assets=['index.html','canonical-entry.js','pdc-qc-mobile.js','pdc-review-stations.js','pdc-new-vehicles.js','pdc-workshop-usability.js','pdc-rft-actions.js']
        results=[]
        for path in assets:
            try:
                req=urllib.request.Request(SITE+path+'?verification='+str(int(time.time())),headers={'User-Agent':'PDC-Staging-QA/1.0'})
                with urllib.request.urlopen(req,timeout=25) as response:
                    content=response.read(4_000_000);status=response.status
                match=hashlib.sha256(content).hexdigest()==hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
                results.append({'path':path,'http_status':status,'matches_tested_source':match})
            except Exception as exc:results.append({'path':path,'error':str(exc)[:500]})
        checks['public_deployment']={'status':'PASS' if all(r.get('http_status')==200 and r.get('matches_tested_source') for r in results) else 'FAIL','assets':results,'scope':'Public static bytes only; authenticated app and Supabase are not contacted.'}
    stats=inventory(out)
    report={'checked_at_utc':datetime.now(timezone.utc).isoformat(),'commit':os.environ.get('GITHUB_SHA','local-published-c139298-baseline'),
        'engine':a.engine,'checks':checks,'inventory':stats,'browser_cases':browser['cases'],
        'all_executed_checks_passed':all(x['status'] in ('PASS','UNVERIFIED') for x in checks.values()),
        'every_function_certified':False,'live_database_in_this_runner':False,
        'outstanding':['Actual staff sign-in and scoped network session','Actual iPhone camera/photo upload and reinspection upload',
        'Native Outlook open/review/send handoff','Next real Revolution report ingestion and unattended Email AI scheduler',
        'Multi-user concurrency across independent sessions','Label printer/device and all external integrations',
        'Fresh database rebuild/preview-environment discrepancy','Every individual function and destructive administrative action']}
    (out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    header=['# PDC overnight verification result','',f"UTC: {report['checked_at_utc']}",f"Commit: `{report['commit']}`",f"Browser engine: {a.engine}",'',
        '**This run does not certify every board function or readiness of external devices/services.**','',
        '| Check | Result |','|---|---|']
    header.extend(f"| {key} | {val['status']} |" for key,val in checks.items())
    header += ['',f"Node suite: {counts}. Simulated UI cases: {browser['passed']} passed, {browser['failed']} failed.",'',
        '## UI evidence layer','Real frontend sources and event handlers run in memory. Staff authentication, backend responses, browser storage/history and origin policy are adapted for the fixture. No customer data or live browser credentials are used. A green result does not demonstrate a live Supabase mutation or physical phone upload.','',
        '## Individual executed UI cases','| Case | Result |','|---|---|']
    header.extend(f"| {c['name']} | {c['status']} |" for c in browser['cases'])
    header+=['','## Function and control inventory',json.dumps(stats),'','Full CSV inventories accompany this artifact. Unmatched inventory rows are not assumed PASS.','',
        '## Still unverified / commissioning limits']+[f'- {x}' for x in report['outstanding']]
    header += ['','No business database credentials are provided to this job. The only network check is the fixed public STAGING website URL; GitHub publishes the report in a separate job.']
    (out/'REPORT.md').write_text('\n'.join(header)+'\n')
    print(json.dumps({'executed_checks_passed':report['all_executed_checks_passed'],'node':counts,'browser_passed':browser['passed'],'browser_failed':browser['failed'],'every_function_certified':False},indent=2))
    return 0 if report['all_executed_checks_passed'] else 1
if __name__=='__main__':raise SystemExit(main())
