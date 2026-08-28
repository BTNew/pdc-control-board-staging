const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/20260828550000_733_acceptance_sublet_cleanup.sql', 'utf8').toLowerCase();
for (const marker of [
  'pdc_733_exact_acceptance_sublet_prestate_mismatch',
  '47dde42b-f768-4a3f-a680-28b6ae8f36f7',
  '2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02',
  '4cbd486c-78c2-42ce-987a-99d45d1eeaf4',
  'cancel_pdc_sublet_booking',
  'pdc_acceptance_sublet_cleanup_history_733',
  'required=false',
  'target_vehicle_preserved',
  'cleanup_path_revoked',
  'revoke all on function public.run_pdc_acceptance_sublet_cleanup_733',
]) assert(sql.includes(marker), `missing cleanup marker: ${marker}`);
assert(!sql.includes('delete from public.pdc_sublet_booking_instances'));
assert(!sql.includes('returned_at=clock_timestamp()'));
assert(!sql.includes('grant update on public.vehicle_work_items'));
console.log('Acceptance Sublet cleanup 733 staging contract passed');
