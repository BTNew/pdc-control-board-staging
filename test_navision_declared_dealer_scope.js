'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/075_navision_declared_dealer_cross_scope.sql','utf8');
assert(sql.includes("v_reason='cross_dealer_identity_overlap'"),'Migration must only release the cross-dealer blocker');
assert(sql.includes('v_incoming>=100'),'Migration must require a substantial full extract');
assert(sql.includes('v_valid_rows=v_incoming'),'Every valid incoming row must be checked');
assert(sql.includes('v_declared_selected=v_incoming'),'Every incoming row must declare the selected dealer');
assert(sql.includes('v_declared_missing=0'),'Missing Dealer evidence must remain blocked');
assert(sql.includes('v_declared_other=0'),'Mixed/other Dealer evidence must remain blocked');
assert(sql.includes("p_row #> '{navisionRawEvidence,columns}'"),'The release must read original Navision column evidence');
assert(sql.includes("'hard_delete',false"),'The release must keep hard deletion disabled');
assert(!sql.includes('update public.navision_backend_records'),'Safety release must not silently reassign or mutate existing dealer records');
console.log('Navision authoritative Dealer-column cross-scope safety checks passed');
