"""Full-source, network-isolated UI tests. Authentication/backend are explicitly simulated.
These tests do NOT certify real login, CSP/origin behavior, iPhone uploads or Outlook.
"""
from __future__ import annotations
import argparse,json,os,re,time,traceback
from pathlib import Path
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2]
LAYER='simulated-browser: real frontend handlers; fixture auth/network/storage/history; CSP not tested'

def prepared_document():
    soup=BeautifulSoup((ROOT/'index.html').read_text(),'html.parser')
    for t in soup.find_all('meta'):
        if t.get('http-equiv','').lower()=='content-security-policy': t.decompose()
    scripts=[t.get('src','').split('?')[0] for t in soup.find_all('script') if t.get('src')]
    for t in soup.find_all('script'):t.decompose()
    for t in soup.find_all('link'):
        if t.get('rel')==['stylesheet']:
            f=ROOT/t['href'].split('?')[0]
            if f.is_file():
                st=soup.new_tag('style');st.string=f.read_text();t.replace_with(st)
    assets={f.name:f.read_text() for ext in ('*.js','*.css') for f in ROOT.glob(ext) if not f.name.startswith(('test_','browser_'))}
    return str(soup),scripts,assets

ADAPTER=r'''()=>{
class MemoryStorage{constructor(){this.m=new Map()}getItem(k){return this.m.get(String(k))??null}setItem(k,v){this.m.set(String(k),String(v))}removeItem(k){this.m.delete(String(k))}clear(){this.m.clear()}key(i){return [...this.m.keys()][i]??null}get length(){return this.m.size}}
Object.defineProperty(window,'localStorage',{value:new MemoryStorage()});Object.defineProperty(window,'sessionStorage',{value:new MemoryStorage()});
let qaCounter=1;if(!crypto.randomUUID)crypto.randomUUID=()=> '00000000-0000-4000-8000-'+String(qaCounter++).padStart(12,'0');
window.fetch=async()=>new Response(JSON.stringify({ok:false,code:'qa_not_authenticated'}),{status:401,headers:{'Content-Type':'application/json'}});
history.pushState=(state,unused,url)=>{window.__qaHistory={state,url}};history.replaceState=history.pushState;
const append=Node.prototype.appendChild;
Node.prototype.appendChild=function(n){
 if(n.tagName==='SCRIPT'&&n.getAttribute('src')){const name=n.getAttribute('src').split('?')[0].split('/').pop();if(!__qaAssets[name])throw new Error('Unmapped dynamic asset '+name);n.removeAttribute('src');n.textContent=__qaAssets[name]+'\n//# sourceURL='+name;const r=append.call(this,n);queueMicrotask(()=>n.dispatchEvent(new Event('load')));return r;}
 if(n.tagName==='LINK'&&n.rel==='stylesheet'){const name=n.getAttribute('href').split('?')[0].split('/').pop();if(__qaAssets[name]){const st=document.createElement('style');st.textContent=__qaAssets[name];append.call(this,st);queueMicrotask(()=>n.dispatchEvent(new Event('load')));return n;}}
 return append.call(this,n);
};}'''

def run(engine,output):
    cases=[];html,scripts,assets=prepared_document()
    with sync_playwright() as pw:
        kwargs={'headless':True}
        executable=os.environ.get('QC_BROWSER_EXECUTABLE')
        if executable and engine=='chromium':kwargs.update(executable_path=executable,args=['--no-sandbox'])
        browser=getattr(pw,engine).launch(**kwargs)
        def page_for(width):
            context=browser.new_context(viewport={'width':width,'height':1000})
            context.route('**/*',lambda route:route.abort())
            page=context.new_page();page.set_default_timeout(4000);errors=[]
            page.on('pageerror',lambda err:errors.append(str(err)))
            page.on('dialog',lambda dialog:dialog.dismiss())
            page.set_content(html);page.evaluate('(x)=>window.__qaAssets=x',assets);page.evaluate(ADAPTER)
            for name in scripts:
                if name!='canonical-entry.js':page.add_script_tag(content=(ROOT/name).read_text()+'\n//# sourceURL='+name)
            page.add_script_tag(content=assets['canonical-entry.js']);page.wait_for_timeout(100)
            page.add_script_tag(content=(ROOT/'qa/overnight/fixture_adapter.js').read_text())
            return context,page,errors
        def check(name,fn):
            start=time.monotonic()
            try:
                fn();cases.append({'name':name,'status':'PASS','seconds':round(time.monotonic()-start,3),'layer':LAYER})
            except Exception as exc:
                cases.append({'name':name,'status':'FAIL','seconds':round(time.monotonic()-start,3),'layer':LAYER,'error':str(exc)[:1800]})
        for width in (1440,390):
            context,page,errors=page_for(width)
            prefix=f'{engine}/{width}px '
            check(prefix+'complete source bootstrap has no JavaScript exception',lambda:assertion(not errors,str(errors)))
            check(prefix+'AI tools are placed under Admin',lambda:assertion(page.evaluate("()=>['emailreview','ai-auditor'].every(v=>document.querySelector('#nav-admin-menu .nav-item[data-view=\"'+v+'\"]'))"),'AI navigation not relocated'))
            page.evaluate("()=>{showView('qc');renderQualityControlPage()}");page.wait_for_timeout(100)
            if width<900:
                check(prefix+'phone has QC-only full width layout',lambda:assertion(page.evaluate("()=>app.currentView==='qc' && document.querySelector('#qc-page-host').getBoundingClientRect().width>innerWidth*.9"),'QC layout not full width'))
                page.locator('[data-qc-open-vehicle]').first.click()
            check(prefix+'three source items present and unchecked',lambda:assertion(page.locator('[data-qc-operation-check]').count()==3 and page.locator('[data-qc-operation-check]:checked').count()==0,'Checklist count/state'))
            check(prefix+'unmapped Review item cannot be checked',lambda:assertion(page.locator('[data-qc-operation-check][data-qc-line-identity$="203"]').is_disabled(),'Review is checkable before mapping'))
            def review_save():
                page.locator('[data-review-station-select]').first.select_option('FITTING')
                page.evaluate('()=>__qa.failMove=true')
                page.locator('[data-review-station-save]').first.click();page.wait_for_timeout(100)
                assertion(page.locator('[data-review-station-select]').first.input_value()=='FITTING','Failed mapping lost station choice')
                assertion(page.evaluate("()=>__qa.raw.qc_operation_lines[2].stage_code==='UNALLOCATED_MAPPING_REVIEW'"),'Failed mapping was presented as accepted')
                page.evaluate('()=>__qa.failMove=false')
                page.locator('[data-review-station-save]').first.click()
                page.wait_for_function("()=>__qa.raw.qc_operation_lines[2].stage_code==='FITTING'")
                page.wait_for_timeout(150)
                calls=page.evaluate('()=>__qa.calls')
                assertion(any(c['name']=='get_vehicle_workshop_detail_scoped' and c['body']['p_dealer_code']=='37047' for c in calls),'Wrong exact dealer read')
                assertion(any(c['name']=='move_vehicle_workshop_source_line_stage' for c in calls),'No station-move call')
                assertion(page.evaluate('()=>__qa.raw.qc_operation_lines[2].estimated_hours===0 && !__qa.raw.qc_operation_lines[2].completed'),'Source hours/check overwritten')
            check(prefix+'actual Review failure/retry preserves choice, exact dealer and zero hours',review_save)
            def checkbox():
                node=page.locator('[data-qc-operation-check][data-qc-line-identity$="201"]')
                node.check();page.wait_for_timeout(120)
                assertion(page.evaluate('()=>__qa.raw.qc_operation_lines[0].completed'),'Check did not reach typed request')
                assertion(node.is_checked(),'Receipt did not render checked')
                node.uncheck();page.wait_for_timeout(100)
                assertion(not page.evaluate('()=>__qa.raw.qc_operation_lines[0].completed'),'Uncheck did not persist in fixture')
            check(prefix+'QC tick and untick execute actual client and reconcile receipt',checkbox)
            if width<900:
                def invalid_photo():
                    page.locator('.qc-phone-picker').dispatch_event('click')
                    page.locator('#qc-mobile-photo-input').set_input_files({'name':'bad.txt','mimeType':'text/plain','buffer':b'not an image'})
                    page.wait_for_timeout(80)
                    assertion('Choose a photo' in page.locator('.qc-phone-feedback').inner_text(),'Invalid file has no error')
                    assertion(page.locator('[data-qc-signoff]').is_disabled(),'Missing photo permits signoff')
                check(prefix+'phone rejects non-image upload and keeps signoff disabled',invalid_photo)
                def failed_photo():
                    page.evaluate("()=>{app.emailVehicleLocationService.uploadQcPhotoEvidence=async()=>{__qa.photoCalls++;return {ok:false,code:'qa_simulated_upload_failure'}}}")
                    page.locator('.qc-phone-picker').dispatch_event('click')
                    # FileReader is real; the transport failure is explicit and simulated.
                    page.locator('#qc-mobile-photo-input').set_input_files({'name':'qa.jpg','mimeType':'image/jpeg','buffer':bytes([255,216,255,217])})
                    page.wait_for_function('()=>__qa.photoCalls===1');page.wait_for_timeout(100)
                    assertion(page.locator('[data-qc-retry-photo]').is_visible(),'No retry after upload failure')
                    page.locator('[data-qc-retry-photo]').click();page.wait_for_function('()=>__qa.photoCalls===2')
                    assertion(page.locator('[data-qc-signoff]').is_disabled(),'Failed photo enables signoff')
                check(prefix+'photo transport failure shows retry and never enables signoff',failed_photo)
            def rejection():
                page.evaluate('()=>{__qa.calls=[];showView("qc");renderQualityControlPage()}')
                if width<900:
                    if page.locator('[data-qc-open-vehicle]').count():page.locator('[data-qc-open-vehicle]').first.click()
                    page.locator('[data-qc-not-fitted]').first.click()
                else:page.locator('[data-qc-reject]').first.click()
                boxes=page.locator('[data-qc-reject-select]')
                assertion(boxes.count()==3,'Selection list missing')
                boxes.nth(0).check();boxes.nth(1).check()
                assertion(not any(c['name']=='reject_pdc_qc_vehicle_to_pmb_stoppage_767' for c in page.evaluate('()=>__qa.calls')),'Changed before confirmation')
                page.locator('[data-qc-confirm-reject]').click()
                page.wait_for_function("()=>__qa.calls.some(c=>c.name==='reject_pdc_qc_vehicle_to_pmb_stoppage_767')")
                calls=page.evaluate("()=>__qa.calls.filter(c=>c.name==='reject_pdc_qc_vehicle_to_pmb_stoppage_767')")
                assertion(len(calls)==1 and len(calls[0]['body']['p_rejected_lines'])==2,'Wrong exact rejection set')
            check(prefix+'multiple selected QC defects send one request only after confirmation',rejection)
            if width>=900:
                def nav():
                    for route in ('dashboard','workflow','parts','sublet','rft','newvehicles','qc','backend','lists','backup','import','zpl'):
                        page.evaluate('(r)=>showView(r)',route);page.wait_for_timeout(35)
                        assertion(page.evaluate('()=>app.currentView')==route,'Route '+route+' did not open')
                check(prefix+'twelve desktop routes open without synchronous exception',nav)
                def newvehicles():
                    page.evaluate("()=>showView('newvehicles')")
                    page.locator('[data-nv-open]').first.click()
                    page.locator('[data-nv-station]').first.select_option('FITTING')
                    assertion(page.locator('[data-nv-approve]').is_enabled(),'Approval still unavailable')
                    page.evaluate('()=>{__qa.calls=[];__qa.failApproval=true}')
                    page.locator('[data-nv-approve]').click();page.wait_for_timeout(120)
                    assertion(page.locator('[data-nv-station]').first.input_value()=='FITTING','Failed approval lost choice')
                    page.evaluate('()=>__qa.failApproval=false');page.locator('[data-nv-approve]').click()
                    page.wait_for_function("()=>app.currentView==='dashboard'")
                    reqs=page.evaluate("()=>__qa.calls.filter(c=>c.name==='approve_pdc_new_vehicle_review')")
                    assertion(len(reqs)==2 and reqs[0]['body']['p_idempotency_key']==reqs[1]['body']['p_idempotency_key'],'Retry request not stable')
                check(prefix+'New Vehicles failed approval preserves choices and exact retry succeeds',newvehicles)
                def admin():
                    page.evaluate("()=>openWorkshopPlannerForStage('FITTING')");page.wait_for_function("()=>typeof bindWorkshopAdminPalette==='function'")
                    # The real renderer may display a backend error with our fixture;
                    # test its real palette binding independently, not a fake schedule.
                    page.evaluate('''()=>{const root=document.createElement('div');root.id='qa-admin';root.innerHTML='<div data-workshop-admin-palette><input data-workshop-admin-palette-duration value="1"><select data-workshop-admin-palette-unit><option value="hours">Hours</option></select><div data-workshop-admin-palette-tile tabindex="0"></div><span data-workshop-admin-palette-label></span></div>';document.body.appendChild(root);renderQualityControlPage();bindWorkshopAdminPalette(root)}''')
                    field=page.locator('#qa-admin [data-workshop-admin-palette-duration]')
                    for hours,minutes in [('0.25','15'),('1.5','90'),('2.75','165'),('15','900')]:
                        field.fill(hours);field.dispatch_event('change')
                        assertion(page.locator('#qa-admin [data-workshop-admin-palette-tile]').get_attribute('data-admin-palette-duration')==minutes,'Admin conversion '+hours)
                    field.fill('0');field.dispatch_event('change')
                    assertion(page.locator('#qa-admin [data-workshop-admin-palette-tile]').get_attribute('aria-disabled')=='true','Zero duration enabled')
                check(prefix+'lazy planner Admin input preserves decimal and multi-day hours',admin)
                def stations():
                    for station in ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE'):
                        page.evaluate('(s)=>openWorkshopPlannerForStage(s)',station);page.wait_for_timeout(35)
                        assertion(page.evaluate('()=>app.activeWorkshopPlannerStage')==station, 'Station routing '+station)
                check(prefix+'all seven dedicated planner routes select the intended station',stations)
            check(prefix+'interaction pass has no uncaught JavaScript exception',lambda:assertion(not errors,str(errors)))
            page.screenshot(path=str(output/f'{engine}-{width}.png'),full_page=False)
            context.close()
        browser.close()
    return cases

def assertion(condition,message):
    if not condition:raise AssertionError(message)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--engine',default='chromium',choices=['chromium','firefox','webkit']);parser.add_argument('--output',required=True);args=parser.parse_args()
    output=Path(args.output);output.mkdir(parents=True,exist_ok=True)
    try:cases=run(args.engine,output)
    except Exception as exc:cases=[{'name':args.engine+' browser infrastructure','status':'ERROR','layer':LAYER,'error':str(exc)[:2000]}]
    report={'engine':args.engine,'layer':LAYER,'cases':cases,'passed':sum(c['status']=='PASS' for c in cases),'failed':sum(c['status']!='PASS' for c in cases)}
    (output/'browser-results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2));return 1 if report['failed'] else 0
if __name__=='__main__':raise SystemExit(main())
