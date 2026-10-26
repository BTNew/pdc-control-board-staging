'use strict';
// Local browser proof with synthetic read-only reports. Never proxies a live API.
// Usage: node tools/performance/serve-optimisation-proof.cjs <built-artifact-directory>
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = fs.realpathSync(process.argv[2]);
const html = `<!doctype html><html lang="en"><meta charset="utf-8"><base href="/"><title>PDC optimisation browser proof</title>
<link rel="stylesheet" href="/styles.css"><style>body{padding:24px;display:block}.view:not(.active){display:none}button{margin:6px}#proof-status{white-space:pre-wrap}</style>
<h1>PDC optimisation browser proof</h1><p>Synthetic reports only. No connection to the working database.</p>
<button id="nav-update-history">Open update history</button><button id="nav-fitting-stats">Open fitting statistics</button>
<button id="dashboard-button">Return to dashboard</button><button id="lock-button">Lock synthetic session</button><button id="unlock-button">Unlock synthetic session</button>
<pre id="proof-status" aria-live="polite"></pre><section id="dashboard" class="view active"><h2>Dashboard</h2></section>
<section id="update-history" class="view"><div id="update-history-content"></div></section>
<section id="fitting-stats" class="view"><div id="fitting-stats-content"></div></section>
<script src="/__proof__/fixture.js" defer></script><script src="/pdc-lazy-admin-views.js?v=2026.10.26.opt1" defer></script></html>`;
const fixture = `(() => {
  window.PDC_AUTH_CONTEXT={userId:'synthetic-admin',role:'administrator'};
  window.__pdcCachedAccessToken='synthetic-only';
  window.PDC_SUPABASE_CONFIG={url:location.origin,publishableKey:'synthetic-only'};
  let reads=0, current='dashboard';
  const originalFetch=window.fetch.bind(window);
  function status(){
    const scripts=[...document.scripts].map(s=>new URL(s.src).pathname).filter(s=>/pdc-update-history|pdc-fitting-stats/.test(s));
    document.getElementById('proof-status').textContent='Active view: '+current+'\\nReport requests: '+reads+'\\nLoaded report scripts: '+scripts.length+'\\n'+scripts.join('\\n');
  }
  window.fetch=async(url,options)=>{
    if(!String(url).startsWith(location.origin+'/rest/v1/rpc/'))throw Error('External access forbidden by synthetic fixture');
    reads++;status();return originalFetch(url,options);
  };
  function controller(view){return view==='update-history'?window.PdcUpdateHistory:view==='fitting-stats'?window.PdcFittingStats:null;}
  async function open(view){
    controller(current)?.close();current=view;
    document.querySelectorAll('.view').forEach(e=>e.classList.toggle('active',e.id===view));
    await controller(view)?.open();status();
  }
  document.addEventListener('DOMContentLoaded',()=>{
    document.getElementById('nav-update-history').onclick=()=>open('update-history');
    document.getElementById('nav-fitting-stats').onclick=()=>open('fitting-stats');
    document.getElementById('dashboard-button').onclick=()=>open('dashboard');
    document.getElementById('lock-button').onclick=()=>{window.dispatchEvent(new Event('pdc-auth-locked'));status();};
    document.getElementById('unlock-button').onclick=()=>{window.dispatchEvent(new Event('pdc-auth-ready'));status();};
    status();
  });
})();`;
const server = http.createServer((req,res) => {
  const url = new URL(req.url,'http://localhost');
  res.setHeader('Cache-Control','no-store');
  if (url.pathname === '/__proof__/' || url.pathname === '/__proof__') {res.setHeader('Content-Type','text/html');res.end(html);return;}
  if (url.pathname === '/__proof__/fixture.js') {res.setHeader('Content-Type','application/javascript');res.end(fixture);return;}
  if (req.method === 'POST') {
    const now='2026-10-26T10:00:00Z';
    const reports={
      '/rest/v1/rpc/get_pdc_update_history':{ok:true,generated_at:now,feeds:[{key:'service_codes',last_success_at:now,last_status:'completed',record_count:3}],history:[]},
      '/rest/v1/rpc/get_pdc_fitting_statistics_489':{ok:true,days:30,generated_at:now,since:'2026-09-26T10:00:00Z',categories:[{category:'FITTING',jobs_completed:2,job_avg_elapsed_minutes:60,lines:[{line_type:'Synthetic verification job',completed:2,timed:2,avg_minutes:30,median_minutes:30,min_minutes:25,max_minutes:35,avg_allowance_minutes:40}]}]}
    };
    if (!reports[url.pathname]) {res.writeHead(403);res.end('Fixture endpoint not permitted');return;}
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(reports[url.pathname]));return;
  }
  if (req.method !== 'GET') {res.writeHead(405);res.end();return;}
  const file = path.resolve(root,'.'+decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',({'.js':'application/javascript','.css':'text/css','.html':'text/html','.json':'application/json','.svg':'image/svg+xml','.png':'image/png'})[path.extname(file)]||'application/octet-stream');
  fs.createReadStream(file).pipe(res);
});
server.listen(0,'127.0.0.1',()=>console.log('Browser proof: http://127.0.0.1:'+server.address().port+'/__proof__'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
