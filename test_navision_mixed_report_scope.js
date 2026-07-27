'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/076_navision_mixed_report_selected_scope.sql','utf8');
assert(sql.includes('v_total=v_valid'),'Mixed-report scoping must not hide invalid rows');
assert(sql.includes('v_valid=v_known'),'Every row must carry a known Dealer value');
assert(sql.includes('v_selected_count>=100'),'Selected dealer scope must be substantial');
assert(sql.includes('v_other_count>0'),'Scoping must only activate for a mixed report');
assert(sql.includes("declared_dealer in ('14450','37047')"),'Only approved dealer codes may be auto-scoped');
assert(sql.includes('preview_navision_backend_import_pre076'),'Preview must use preserved server authority');
assert(sql.includes('apply_navision_backend_import_pre076'),'Apply must use preserved server authority');
assert((sql.match(/navision_scope_rows_for_selected_dealer\(p_rows,p_source_system,p_dealer_code\)/g)||[]).length===2,'Preview and Apply must run the identical scope helper');
assert(sql.includes("'source_scope_filter',v_scope-'rows'"),'Receipt data must report source scoping without echoing rows');
assert(!sql.includes('delete from'),'Mixed-report handling must not delete records');
console.log('Navision mixed-report selected-dealer scope contract passed');
