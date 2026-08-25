const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationName = '20260825090000_324_typed_monitor_parts_complete.sql';
const migrationPath = [
  path.join(__dirname, 'supabase', 'staging_only', migrationName),
  path.join(__dirname, migrationName),
].find(fs.existsSync);
assert(migrationPath, 'migration file exists');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();

function currentUnquotedText(body) {
  for (const raw of String(body).replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trim().replace(/\s+/g, ' ');
    if (!line) continue;
    if (line.startsWith('>') || /^(on .+ wrote:|from:|sent:|to:|subject:|-----original message-----)/i.test(line)) return null;
    if (line === '--') return null;
    return line;
  }
  return null;
}

assert(sql.startsWith('-- STAGING ONLY migration 324'));
for (const marker of [
  "pdc_email_parts_complete_rules_324",
  "pdc_email_parts_complete_rule_history_324",
  "pdc_email_parts_complete_receipts_324",
  "pdc_email_parts_complete_action_receipts_324",
  "public.process_pdc_email_parts_complete",
  "public.read_pdc_email_parts_complete_receipt_324",
  "public.mark_pdc_parts_complete",
  "pdc_parts_complete_canonical_apply_324",
  "disable_pdc_email_parts_complete_rule_324",
  "721e14afcdede43ef0091ae34456fbc4ba55dbe9696509f2b9bfe6b163b162f8",
  "<SY1P282MB635569B0CA01A2D8BA5CE4E8ACA02@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>",
  "talin.parker@pmgwa.com.au",
  "pdc-monitor-staging-pmbcontroller-hourly-v1",
  "Parts complete",
  "uidvalidity=1",
  "uid=615",
  "non_parts_diff",
  "mailbox_flags_unchanged",
]) assert(lower.includes(marker.toLowerCase()), `missing contract marker: ${marker}`);

assert(lower.includes("grant execute on function public.process_pdc_email_parts_complete"));
assert(lower.includes("grant execute on function public.read_pdc_email_parts_complete_receipt_324"));
assert(lower.includes("grant execute on function public.mark_pdc_parts_complete"));
assert(!/grant\s+.*\s+to\s+service_role/i.test(sql), 'service_role must not receive new API authority');
assert(!/grant\s+(insert|update|delete|truncate).*\s+to\s+authenticated/i.test(sql), 'generic authenticated DML must not be granted');
assert(!lower.includes('create scheduler') && !lower.includes('pg_cron'));
assert(lower.includes("notify pgrst,'reload schema'"));
assert(lower.includes("current_setting('pdc.email_vehicle_revision_batch',true)='suppress'"));

const positive = ['Parts complete', 'Parts completed', 'Parts received'];
for (const text of positive) assert(positive.includes(currentUnquotedText(text)), `positive evidence rejected: ${text}`);
for (const [label, body] of [
  ['quoted-only', '> Parts complete'],
  ['negated', 'Parts not complete'],
  ['conditional', 'Parts complete if the supplier confirms'],
  ['future', 'Parts will be complete'],
  ['question', 'Are Parts complete?'],
  ['quoted-after-prefix', 'On Tue, someone wrote:\n> Parts complete'],
  ['signature-only', '--\nParts complete'],
]) assert(!positive.includes(currentUnquotedText(body)), `${label} evidence accepted`);

assert(sql.includes("lower(coalesce(i.provider_uid,'')) not in('imap_uid:615','1:615')"));
assert(sql.includes("v_attachment_count<>1 or v_image_count<>1"));
assert(sql.includes("not v_before.visible_on_board"));
assert(sql.includes("v_before.rft_collected_at is not null"));
assert(sql.includes("upper(btrim(coalesce(v_before.current_location,'')))='COMPLETED'"));
assert(sql.includes("v_candidate_count<>1"));
assert(sql.includes("i.claim_token<>p_claim_token"));
assert(sql.includes("i.locked_at<clock_timestamp()-interval '10 minutes'"));
assert(sql.includes("i.provider_authentication is distinct from rule.authentication"));
assert(sql.includes("o.authentication is distinct from rule.authentication"));
assert(sql.includes("v_revision_after<>v_revision_before+1"));

console.log('typed Monitor Parts-complete migration 324 contract passed');
