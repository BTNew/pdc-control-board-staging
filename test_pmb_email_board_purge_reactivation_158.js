'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '158_pmb_email_board_purge_reactivation.sql'), 'utf8');
const lower = sql.toLowerCase();

function requireToken(token, message) {
  assert(sql.includes(token), message || `Missing ${token}`);
}

requireToken("version='157' and name='bounded_pmb_workbook_importer_review'", 'Migration157 predecessor must be exact');
requireToken("version='158'", 'Migration158 receipt guard missing');
assert.strictEqual((sql.match(/r\.role in\('viewer','importer'\)/g) || []).length, 2, 'Both submit wrapper and internal auto-apply must enroll Importer');
requireToken("v_role not in ('viewer','importer')", 'Pre135 proposal submission must enroll Importer');
requireToken('v_reactivating_board_purge boolean:=false', 'Narrow reactivation state missing');
requireToken("v_vehicle.board_purged_at is not null and v_vehicle.deleted_at is not null", 'Board-purge tombstone proof missing');
requireToken("v_vehicle.lifecycle_state='deleted' and not v_vehicle.visible_on_board", 'Complete purge lifecycle proof missing');
requireToken('v_record.canonical_vehicle_id=v_vehicle.id', 'Same canonical vehicle binding missing');
requireToken('and not (v_reactivating_board_purge and v.id=v_vehicle_id)', 'Historical-identity exception must be limited to selected purge tombstone');
requireToken('v_activation.canonical_vehicle_id=v_vehicle_id', 'Activation must remain bound to the same vehicle');
requireToken('public.normalize_vehicle_stock_number(v_activation.activated_stock_number)=v_proposal.stock_number', 'Activation Stock binding missing');
requireToken("if v_vehicle_id is not null and not v_reactivating_board_purge then", 'Ordinary active vehicle no-op protection missing');
requireToken("lifecycle_state='active',visible_on_board=true,deleted_at=null,deleted_reason=null", 'Atomic board reactivation missing');
requireToken('board_purged_at=null,board_purge_reason=null,board_purged_by=null', 'Purge latch clear missing');
requireToken("active=true,activation_source='approved_email_build'", 'Canonical activation reactivation missing');
requireToken('completed_at=null,completion_reason=null', 'Old purge completion state must be cleared');
requireToken('perform public.reconcile_navision_operational_record(v_record.id,p_actor_id,v_actor_email)', 'Canonical Navision reconciliation missing');
requireToken('PDC_AI_INTAKE_158_REACTIVATION_POSTCONDITION_FAILED', 'Fail-closed postcondition missing');
requireToken("'board_purge_reactivation',true", 'Audit evidence missing');
requireToken("'board_purge_reactivation',v_reactivating_board_purge", 'Response evidence missing');
requireToken("return public.navision_backend_response(false,'protected_historical_identity')", 'Ordinary historical vehicles must remain protected');
requireToken("return public.navision_backend_response(false,'protected_backend_lifecycle')", 'Completed backend lifecycle protection missing');
requireToken("return public.navision_backend_response(false,'proposal_expired')", 'Old mail must not reactivate vehicles');
requireToken("return public.navision_backend_response(false,'same_stock_evidence_conflict'", 'Conflicting same-Stock evidence must fail closed');
requireToken("return public.navision_backend_response(false,'identity_conflict')", 'Duplicate/noncanonical Stock must fail closed');
requireToken("status='applied'", 'Successful proposal must become applied for receipt binding');
requireToken('revoke all on function public.submit_pdc_ai_intake_observation_pre135', 'Internal submit function ACL missing');
requireToken('revoke all on function public.pdc_auto_apply_ai_intake_activation_internal', 'Internal auto-apply ACL missing');
assert(!lower.includes('production_ref'), 'Migration must not target production');
assert(!lower.includes('grant execute on function public.pdc_auto_apply_ai_intake_activation_internal'), 'Internal auto-apply must not be directly executable');

console.log('Migration158 PMB Email board-purge reactivation contract passed');
