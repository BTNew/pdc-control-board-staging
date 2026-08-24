#!/usr/bin/env node
// Capture authenticated staging UI without persisting credentials/session tokens.
const fs=require('fs'),path=require('path'),os=require('os'),cp=require('child_process');
const envPath='C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/.env';
const values={};for(const raw of fs.readFileSync(envPath,'utf8').replace(/^\uFEFF/,'').split(/\r?\n/)){const s=raw.trim();if(s&&!s.startsWith('#')&&s.includes('=')){const i=s.indexOf('=');values[s.slice(0,i).trim()]=s.slice(i+1).trim().replace(/^['"]|['"]$/g,'');}}
const ref='cdsmnqxtyyoeoznmbidd', url=`https://btnew.github.io/pdc-control-board-staging/?reset-proof=20260824-${Date.now()}`;
if(values.PDC_STAGING_PROJECT_REF!==ref||!values.PDC_STAGING_SUPABASE_URL.includes(ref))throw Error('target guard failed');
const out=path.resolve('_staging_deployment_receipts/20260824_staging_ui_authenticated_empty.png');
const evidence=path.resolve('_staging_deployment_receipts/20260824_staging_ui_authenticated_empty.json');
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'pdc-ui-proof-'));let chrome;
function sleep(ms){return new Promise(r=>setTimeout(r,ms));}
async function jsonFetch(u,o){const r=await fetch(u,o);if(!r.ok)throw Error(`HTTP ${r.status}`);return r.json();}
async function main(){
 let session;for(const [ek,pk] of [['PDC_STAGING_VIEWER_EMAIL','PDC_STAGING_VIEWER_PASSWORD'],['PDC_STAGING_CONTROLLER_A_EMAIL','PDC_STAGING_CONTROLLER_A_PASSWORD'],['PDC_STAGING_ADMIN_EMAIL','PDC_STAGING_ADMIN_PASSWORD'],['PDC_STAGING_ADMIN2_EMAIL','PDC_STAGING_ADMIN2_PASSWORD']]){try{session=await jsonFetch(`${values.PDC_STAGING_SUPABASE_URL}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:values.PDC_STAGING_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:values[ek],password:values[pk]})});break}catch{}}if(!session)throw Error('no approved staging UI identity authenticated');
 const chromePath='C:/Program Files/Google/Chrome/Application/chrome.exe';
 chrome=cp.spawn(chromePath,['--headless=new','--disable-gpu','--hide-scrollbars','--window-size=1440,1200','--remote-debugging-port=9237',`--user-data-dir=${profile}`,'about:blank'],{stdio:'ignore'});
 let version;for(let i=0;i<100;i++){try{version=await jsonFetch('http://127.0.0.1:9237/json/version');break}catch{await sleep(100);}}if(!version)throw Error('chrome cdp unavailable');
 const target=await jsonFetch('http://127.0.0.1:9237/json/new?about:blank',{method:'PUT'});const ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise((res,rej)=>{ws.onopen=res;ws.onerror=rej});
 let id=0,pending=new Map(),events=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const [res,rej]=pending.get(m.id);pending.delete(m.id);m.error?rej(Error(m.error.message)):res(m.result);}else if(m.method&&events.has(m.method)){for(const f of events.get(m.method))f(m.params);}};
 const send=(method,params={})=>new Promise((res,rej)=>{const n=++id;pending.set(n,[res,rej]);ws.send(JSON.stringify({id:n,method,params}));});
 const once=method=>new Promise(res=>{const f=p=>{events.get(method).delete(f);res(p)};if(!events.has(method))events.set(method,new Set());events.get(method).add(f)});
 await send('Page.enable');await send('Runtime.enable');let loaded=once('Page.loadEventFired');await send('Page.navigate',{url});await loaded;
 const storageKey=`sb-${ref}-auth-token`;const stored={access_token:session.access_token,refresh_token:session.refresh_token,expires_in:session.expires_in,expires_at:Math.floor(Date.now()/1000)+session.expires_in,token_type:session.token_type,user:session.user};
 await send('Runtime.evaluate',{expression:`localStorage.setItem(${JSON.stringify(storageKey)},${JSON.stringify(JSON.stringify(stored))})`});
 loaded=once('Page.loadEventFired');await send('Page.reload',{ignoreCache:true});await loaded;await sleep(6000);
 const state=await send('Runtime.evaluate',{expression:`(()=>({title:document.title,text:document.body.innerText,vehicleCards:document.querySelectorAll('[data-vehicle-id],.vehicle-card,.board-card').length,url:location.href}))()`,returnByValue:true});
 const text=state.result.value.text||'';if(/PDC staff sign-in/i.test(text))throw Error('authenticated UI remained on sign-in');
 const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(out,Buffer.from(shot.data,'base64'));
 const emptyMarkers=(text.match(/[^\n]*(?:no vehicles|0 vehicles|no matching|empty)[^\n]*/ig)||[]).slice(0,20);const doc={schema:'pdc-staging-authenticated-ui-proof-v1',project_ref:ref,captured_at_utc:new Date().toISOString(),title:state.result.value.title,vehicle_card_count:state.result.value.vehicleCards,empty_markers:emptyMarkers,screenshot:path.basename(out)};fs.writeFileSync(evidence,JSON.stringify(doc,null,2));console.log(JSON.stringify({status:'AUTHENTICATED_UI_CAPTURED',project_ref:ref,title:doc.title,vehicle_card_count:doc.vehicle_card_count,empty_markers:doc.empty_markers,screenshot:out,evidence},null,2));ws.close();
}
main().catch(e=>{console.error(JSON.stringify({status:'FAILED',error:e.message}));process.exitCode=1}).finally(async()=>{if(chrome){chrome.kill();await sleep(300)}try{fs.rmSync(profile,{recursive:true,force:true})}catch{}});
