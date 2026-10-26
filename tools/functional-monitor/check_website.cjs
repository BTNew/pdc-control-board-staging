'use strict';
// Read-only public availability and regression checks. This runner has no signed
// staff token, database credential, email client or operational mutation call.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const {ENTRY_POINTS} = require('../../scripts/build_pages_runtime.js');
const repo = path.resolve(__dirname, '../..');
const base = 'https://pmgpdc.au/';
const legacyBase = 'https://btnew.github.io/pdc-control-board-staging/';
const backend = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
const CRITICAL_ASSETS = Object.freeze(['app.js','workshop-planner.js','workshop-shared-actions.js','pdc-fitters.js','pdc-auth.js','sales/sales.js','sales/finance-pipeline.js','sales/customer-emails.js']);
const publicFiles = new Set([...ENTRY_POINTS, ...CRITICAL_ASSETS]);

async function fetchCheck(relative, method = 'GET', fetcher = fetch) {
  if (!publicFiles.has(relative)) throw new Error('Unexpected website target');
  if (!['GET','HEAD'].includes(method)) throw new Error('Only read-only website methods are permitted');
  const url = new URL(relative, base);
  const response = await fetcher(url, {method,signal:AbortSignal.timeout(20000),redirect:'error'});
  if (!response.ok) throw new Error('HTTP ' + response.status);
  if (method === 'GET' && !(await response.text()).toLowerCase().includes('<html')) throw new Error('HTML entry point missing');
  return {name:relative,status:'PASS'};
}

async function checkLegacyEntryRedirect(relative, fetcher = fetch) {
  if (!ENTRY_POINTS.includes(relative)) throw new Error('Unexpected legacy entry point');
  const response = await fetcher(new URL(relative, legacyBase), {
    method:'HEAD',signal:AbortSignal.timeout(20000),redirect:'manual'
  });
  // Never follow a redirect. Validate the exact HTTPS host, path and absence of
  // credentials/query/fragment before the canonical checks make their own read.
  if (![301,308].includes(response.status) || response.headers.get('location') !== new URL(relative, base).href) {
    throw new Error('Legacy entry must redirect directly to its exact canonical HTTPS URL');
  }
  return {name:'Legacy entry redirect: '+relative,status:'PASS',http_status:response.status};
}

async function probeSignedOutAccess(key, fetcher = fetch) {
  const results=[];
  for (const name of ['get_broome_sales_board_snapshot','get_workshop_configuration','get_pdc_usage_report_20260914']) {
    try {
      const response=await fetcher(backend+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(20000),redirect:'error'});
      results.push({name:'Signed-out access denied: '+name,status:[401,403].includes(response.status)?'PASS':'FAIL',http_status:response.status});
    } catch(error) { results.push({name:'Backend availability: '+name,status:'FAIL',reason:error.message}); }
  }
  return results;
}

async function run({full = false, output, skipNetwork = false} = {}) {
  if (!output) throw new Error('A private report directory is required');
  const privateRoot = path.resolve(repo,'../../work/functional-monitor-private');
  const resolved = path.resolve(output);
  if (!resolved.startsWith(privateRoot + path.sep) || resolved === privateRoot) throw new Error('Reports must remain in functional-monitor-private');
  fs.mkdirSync(resolved,{recursive:true});
  const results = [];
  if (skipNetwork) results.push({name:'Live availability',status:'NOT RUN',reason:'Network explicitly skipped'});
  else {
    // Small bounded requests. No staff account or customer data is used.
    for (let i = 0; i < ENTRY_POINTS.length; i += 3) {
      const chunk = ENTRY_POINTS.slice(i,i+3);
      const checks = await Promise.allSettled(chunk.map(file => fetchCheck(file)));
      checks.forEach((item,j) => results.push(item.status === 'fulfilled' ? item.value : {name:chunk[j],status:'FAIL',reason:String(item.reason.message)}));
    }
    for (let i = 0; i < ENTRY_POINTS.length; i += 3) {
      const chunk = ENTRY_POINTS.slice(i,i+3);
      const checks = await Promise.allSettled(chunk.map(file => checkLegacyEntryRedirect(file)));
      checks.forEach((item,j) => results.push(item.status === 'fulfilled' ? item.value : {name:'Legacy entry redirect: '+chunk[j],status:'FAIL',reason:String(item.reason.message)}));
    }
    for (const file of CRITICAL_ASSETS) {
      try { results.push(await fetchCheck(file,'HEAD')); } catch(error) { results.push({name:file,status:'FAIL',reason:error.message}); }
    }
    const sandbox = {window:{location:{origin:new URL(base).origin,pathname:new URL(base).pathname}}};
    vm.runInNewContext(fs.readFileSync(path.join(repo,'pdc-supabase-config.staging.js'),'utf8'),sandbox);
    const config = sandbox.window.PDC_SUPABASE_CONFIG;
    if (config.url.replace(/\/$/,'') !== backend || !config.publishableKey) throw new Error('Staging-only configuration required');
    // Read endpoints must deny signed-out clients. Never probe write/import RPCs.
    results.push(...await probeSignedOutAccess(config.publishableKey));
  }
  const tests = full ? fs.readdirSync(repo).filter(file=>/^test_.*\.js$/.test(file)) : [
    'test_workshop_start_priority.js','test_workshop_start_safeupdate.js',
    'test_workshop_shared_cascade_persistence.js','test_workshop_stoppage_fix_first.js',
    'test_workshop_fitter_live_sync.js','test_fitter_workflow.js','test_fitter_handover.js',
    'test_jobcard_work_categories.js',
    'test_control_board_overview.js','test_vehicle_locations_refresh.js',
    'test_navision_apply_recovery.js','test_broome_finance_autosave.js',
    'test_staff_usage_all_pages_20261012.js'
  ];
  const existing = tests.filter(file=>fs.existsSync(path.join(repo,file)));
  for (const missing of tests.filter(file=>!existing.includes(file))) results.push({name:missing,status:'BLOCKED',reason:'Configured test file is missing'});
  const tested = spawnSync(process.execPath,['--test',...existing],{cwd:repo,encoding:'utf8',timeout:300000,windowsHide:true,maxBuffer:8*1024*1024});
  fs.writeFileSync(path.join(resolved,'regression.private.log'),(tested.stdout||'')+'\n'+(tested.stderr||''));
  const outputText = tested.stdout||'';
  const total = outputText.match(/(?:ℹ|#) tests (\d+)/)?.[1];
  results.push({name:full?'Complete website regression suite':'Workshop and critical-page regressions',status:tested.status===0?'PASS':'FAIL',tests:total?Number(total):null});
  const report = {checked_at:new Date().toISOString(),mode:full?'full':'hourly',live_mutations:false,emails_sent:false,
    results,authenticated_browser_checks:'NOT RUN by this runner; scheduled agent must record separate browser evidence or a BLOCKED result',
    overall:results.some(x=>['FAIL','BLOCKED'].includes(x.status))?'FAIL':'PUBLIC_AND_REGRESSION_CHECKS_PASSED'};
  fs.writeFileSync(path.join(resolved,'website-checks.json'),JSON.stringify(report,null,2));
  return report;
}

if(require.main===module){
  const args=process.argv.slice(2), index=args.indexOf('--output');
  run({full:args.includes('--full'),output:index<0?null:args[index+1],skipNetwork:args.includes('--skip-network')})
    .then(report=>{console.log(JSON.stringify(report,null,2));process.exitCode=report.overall==='FAIL'?1:0;})
    .catch(error=>{console.error(error.message);process.exitCode=1;});
}
module.exports={run,fetchCheck,checkLegacyEntryRedirect,probeSignedOutAccess};
