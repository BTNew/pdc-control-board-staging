/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r429 (F41): switching an account to salesperson in User Admin must also link its Sales site record
// (pdc_sales_private.account_scopes -> salespeople), otherwise the Sales site says
// "Ask an administrator to assign your salesperson access". Server: supabase/migrations/*_r429_*.sql and *_r429b_*.sql.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
const mig=fs.readFileSync('supabase/migrations/20261021041812_r429_salesperson_role_links_sales_record.sql','utf8');
const migB=fs.readFileSync('supabase/migrations/20261021042111_r429b_link_helper_where.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021041812_r429_salesperson_role_links_sales_record.down.sql','utf8');
const downB=fs.readFileSync('supabase/rollbacks/20261021042111_r429b_link_helper_where.down.sql','utf8');
function runtime(){
 const confirms=[];const notes=[];
 const c={window:{PDC_AUTH_CONTEXT:{role:'administrator'},confirm:m=>{confirms.push(m);return true;},prompt:()=>null},
  document:{getElementById:()=>null},escapeHtml:String,cleanNavisionText:String,pdcNotify:m=>notes.push(m),backupStatusSharedModeReady:()=>true};
 vm.createContext(c);
 vm.runInContext(source.slice(source.indexOf('const USER_MANAGEMENT_STATE ='),source.indexOf('function cancelWorkshopPlannerRender()')),c);
 return {c,confirms,notes};
}
test('changing a role to salesperson tells the admin the Sales record is linked by email',()=>{
 const {c,confirms}=runtime();
 assert.equal(c.userManagementConfirmRoleChange('s@example.invalid','operator','salesperson'),true);
 assert.match(confirms[0],/from controller to salesperson/);
 assert.match(confirms[0],/linked to the salesperson record with the same email/);
 assert.match(confirms[0],/add them to the salespeople list first/);
});
test('other role changes do not mention the Sales record',()=>{
 const {c,confirms}=runtime();
 c.userManagementConfirmRoleChange('s@example.invalid','salesperson','viewer');
 c.userManagementConfirmRoleChange('s@example.invalid','viewer','operator');
 assert.equal(confirms.some(m=>/salesperson record/.test(m)),false);
});
test('admin_change_role links the Sales record (strict) and admin_approve_user links it when the email matches',()=>{
 assert.match(mig,/CREATE OR REPLACE FUNCTION public\.admin_change_role\(/);
 assert.match(mig,/perform pdc_sales_private\.link_salesperson_scope_429\(v_target\.id, 'admin_change_role', true\);/);
 assert.match(mig,/perform pdc_sales_private\.link_salesperson_scope_429\(v_target\.id, 'admin_approve_user', false\);/);
 assert.match(mig,/if p_role = 'salesperson' then/);
 // r419 guard kept
 assert.match(mig,/You cannot remove your own administrator role/);
 assert.match(mig,/pdc_effective_admin_count_419/);
});
test('link helper: same-email active salespeople row only, never re-points an existing link, audited, closed to app roles',()=>{
 for(const s of [mig,migB]){
  assert.match(s,/s\.active AND s\.email IS NOT NULL AND lower\(btrim\(s\.email\)\)=lower\(btrim\(r\.email\)\)/);
  assert.match(s,/already linked: never re-point an existing link/);
  assert.match(s,/'operation','assign_broome_sales_access','via',p_operation,'release','r429'/);
  assert.match(s,/No active salesperson record has the email %/);
  assert.match(s,/REVOKE ALL ON FUNCTION pdc_sales_private\.link_salesperson_scope_429\(uuid,text,boolean\) FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(s,/WHERE account_scopes\.user_role_id=excluded\.user_role_id;/);
  assert.doesNotMatch(s,/can_view_all_salespeople\s*=/);
 }
});
test('release guards, pins, regression check and undo are in place',()=>{
 for(const s of [mig,migB,down,downB]){
  assert.match(s,/NOT BETWEEN 2 AND 45/);
  assert.match(s,/project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.doesNotMatch(s,/vjdtsswhroyguxyfjdkt/);
 }
 assert.match(mig,/'salesperson_role_has_sales_link','F41'/);
 assert.match(mig,/UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5='[0-9a-f]{32}', release='r429'/);
 assert.match(down,/eace79d601b07c3c9d001c35f03672c2/);
 assert.match(down,/e09e4333b01a887ab5a475100dfda5e3/);
 assert.match(down,/DROP FUNCTION pdc_sales_private\.link_salesperson_scope_429\(uuid,text,boolean\);/);
 assert.match(down,/DELETE FROM pdc_ops\.regression_checks WHERE check_name='salesperson_role_has_sales_link' AND added_in='r429';/);
 assert.match(downB,/6f252dc514a40ff8d728073109de91bf/);
});
test('no staff emails or account ids in the release files',()=>{
 for(const s of [mig,migB,down,downB,fs.readFileSync(__filename,'utf8')]){
  assert.doesNotMatch(s,/@(broometoyota|pmgwa)\.com\.au/);
  assert.doesNotMatch(s,/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/);
 }
});
test('app.js cache bust carries r429',()=>{
 // r430 appends its own token after r429; the r429 param stays on the app.js tag.
 assert.match(fs.readFileSync('index.html','utf8'),/app\.js\?[^"]*&amp;r429=2026\.10\.21\.01(?:&amp;|")/);
});
