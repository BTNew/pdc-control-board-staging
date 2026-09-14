const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const begin = source.indexOf('function backupStatusSharedModeReady()');
const end = source.indexOf('// Administrator-only User Management screen.', begin);
const now = Date.parse('2026-09-14T12:00:00Z');
const old = { status: 'success', kind: 'manual', started_at: '2026-09-01T22:37:53Z', finished_at: '2026-09-01T22:39:23Z', file_path: 'private/export.bin', file_size_bytes: 9675852 };
const host = { innerHTML: '' }, panel = { hidden: false };
const calls = [];
let restore = [];
const client = { from(table) {
  const filters = {};
  return { select() { return this; }, eq(k,v) { filters[k]=v; return this; }, order() { return this; },
    limit(n) { calls.push({table,filters,n}); return Promise.resolve({data: table === 'restore_test_runs' ? restore : filters.status === 'success' ? [old] : Array.from({length:20},()=>({status:'failed',started_at:'2026-09-14T10:00:00Z',error_message:'<script>bad</script>'})),error:null}); }
  };
} };
const context = vm.createContext({ Date, console, PRODUCTION_SUPABASE_PROJECT_REF: 'production',
  window: { PDC_SUPABASE_CONFIG: { projectRef: 'staging' }, PDC_SUPABASE: client, PDC_AUTH_CONTEXT: {role:'administrator'} },
  workshopSharedModeEnabled:()=>true, $:id=>id==='#backup-status-panel'?panel:host,
  escapeHtml:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;') });
vm.runInContext(source.slice(begin,end),context);
const health = context.backupHistoryHealth;
assert.match(health([],null,now).join(' '), /No successful backup is recorded/);
assert.match(health([],old,now).join(' '), /past three hours/);
assert.equal(health([],{...old,finished_at:'2026-09-14T11:00:00Z'},now).length,0);
assert.match(health([{status:'running',started_at:'2026-08-28T12:22:23Z'}],old,now).join(' '), /no recorded completion/);
assert.match(health([],{...old,file_path:null},now).join(' '), /no backup file location/);
(async()=>{
  await context.renderBackupStatusPanel();
  assert(calls.some(c=>c.table==='backup_runs'&&c.filters.status==='success'&&c.n===1));
  assert.match(host.innerHTML,/Backup attention needed/);
  assert.match(host.innerHTML,/Last recorded success/);
  assert.match(host.innerHTML,/Automatic schedule<\/span><strong>Not verified/);
  assert.match(host.innerHTML,/Never run/);
  assert.match(host.innerHTML,/&lt;script&gt;bad&lt;\/script&gt;/);
  assert(!host.innerHTML.includes('Next scheduled backup'));
  assert(!host.innerHTML.includes('7d / 30d / 12w / 12mo'));
  restore=[{status:'running',started_at:'2026-09-14T11:00:00Z',row_count_matches:false}];
  await context.renderBackupStatusPanel();
  assert.match(host.innerHTML,/No completed result yet/);
  restore=[{status:'failed',started_at:'2026-09-14T11:00:00Z',row_count_matches:true}];
  await context.renderBackupStatusPanel();
  assert.match(host.innerHTML,/FAILED/);
  context.window.PDC_AUTH_CONTEXT.role='operator';
  await context.renderBackupStatusPanel();
  assert.equal(panel.hidden,true);
  console.log('Backup status checks passed: stale and missing history, unfinished runs, older success outside latest 20, honest schedule/retention, restore status, escaping and admin visibility.');
})().catch(e=>{console.error(e);process.exitCode=1;});
