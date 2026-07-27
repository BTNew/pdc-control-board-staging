'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/079_navision_exact_dealer_scope_without_fleet_floor.sql','utf8');
assert(sql.includes("v_incoming>0"),'Cross-dealer release must accept non-empty exact dealer snapshots');
assert(sql.includes('v_selected_count>0'),'Mixed report scoping must not impose an arbitrary fleet floor');
assert(sql.includes('check(row_count>0)'),'Initial baseline ledger must accept a non-empty dealer snapshot');
assert(!sql.includes('v_incoming>=100'),'Legacy 100-row cross-dealer floor must be removed');
assert(!sql.includes('v_selected_count>=100'),'Legacy 100-row mixed-scope floor must be removed');
assert(sql.includes('public.navision_row_declared_dealer_code(e.value)=v_dealer_code'),'Initial baseline must verify every original Dealer column');
assert(sql.includes('v_valid_rows=v_incoming and v_declared_selected=v_incoming'),'Cross-scope release must require every valid row to declare the selected dealer');
assert(sql.includes("'hard_delete',false"),'Exact dealer release must preserve the no-hard-delete policy');
assert(sql.includes("v_reason='cross_dealer_identity_overlap'"),'Only the intended cross-dealer blocker may be released');
console.log('Navision exact-dealer sub-100 snapshot contract passed');
