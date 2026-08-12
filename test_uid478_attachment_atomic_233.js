'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/233_uid478_attachment_atomic_import.sql', 'utf8');
const lower = sql.toLowerCase();

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'exact staging project guard');
assert(sql.includes("version='232'"), 'exact predecessor 232 required');
assert(sql.includes("version='233'"), 'migration 233 ledger entry/guard');
assert(sql.includes('UIDVALIDITY1_UID478_ONLY'), 'UIDVALIDITY 1 UID 478 gate is explicit');
assert(/p_mailbox_uidvalidity\s*(?:<>|=)\s*1/.test(sql) && /p_mailbox_uid\s*(?:<>|=)\s*478/.test(sql), 'only generation 1 UID 478 is accepted');
assert(sql.includes('between 470 and 477'), 'UIDs 470-477 are fail-closed excluded');

assert(sql.includes('drop constraint pdc_provider_email_observations_intake_id_key'), 'legacy one-observation-per-intake constraint is generalized');
assert(sql.includes('unique(intake_id,attachment_id)'), 'observation identity is per attachment');
assert(sql.includes('pdc_uid478_attachment_terminal_receipts'), 'immutable per-attachment terminal receipts exist');
assert(sql.includes("terminal_status text not null check(terminal_status in ('applied','review'))"), 'applied/review are the only terminal states');
for (const field of ['mailbox_uidvalidity','mailbox_uid','message_received_at','attachment_file_name','attachment_sha256','original_extracted_values','match_evidence','attempt_metadata','review_metadata','applied_metadata']) {
  assert(sql.includes(field), `receipt retains ${field}`);
}
assert(sql.includes('pdc_uid478_attachment_attempt_receipts'), 'attempt evidence is append-only and attachment scoped');
assert(sql.includes('pdc_uid478_message_receipts'), 'message aggregate receipt exists');
assert(sql.includes('all_attachments_terminal'), 'aggregate readiness is explicit');
assert(sql.includes('high_water_eligible'), 'high-water eligibility is explicit');
assert(sql.includes("count(*) filter(where terminal_status in ('applied','review'))") && sql.includes('if v_count<>4 or v_terminal<>4'), 'high water requires four terminal attachments');
assert(sql.includes("pg_get_functiondef('public.attest_pdc_provider_email_observation") && sql.includes('execute replace(replace(d,old_lock,new_lock),old_lookup,new_lookup)'), 'legacy observation body and replay behavior are preserved by targeted replacement');
assert(sql.includes("'pdc-provider-email-observation-233:'||p_intake_id::text||':'||p_attachment_id::text"), 'observation lock is attachment scoped');
assert(sql.includes('where intake_id=p_intake_id and attachment_id=p_attachment_id'), 'observation lookup is attachment scoped');
assert(sql.includes("'pdc-uid478-terminal:'||v_attempt.intake_id::text||':'||v_attempt.attachment_id::text") && sql.includes('where intake_id=v_attempt.intake_id and attachment_id=v_attempt.attachment_id'), 'terminal idempotency is attachment scoped');
assert(sql.includes('PDC_233_RECEIPT_IMMUTABLE'), 'receipts reject update/delete');
assert(lower.includes('revoke all on table public.pdc_uid478_attachment_terminal_receipts from public,anon,authenticated,service_role'), 'no direct receipt-table authority');
assert(!/grant\s+execute[\s\S]{0,120}service_role/i.test(sql), 'new RPCs do not grant service_role bot authority');
assert(sql.includes("grant execute on function public.record_pdc_uid478_attachment_terminal"), 'scoped authenticated caller can terminally receipt attachments');
assert(sql.includes("to authenticated"), 'new execution authority uses existing authenticated monitor identity');

console.log('Migration 233 UID478 attachment-atomic contracts passed');
