'use strict';
// r758 (F364, Craig 30 Oct 13:01): a work-complete car (WPC or RFT) completes when Navision says Delivered - At Dealer
// or when its record leaves Navision, and the dealer-transit time runs from work complete when there was no RFT booking.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r758: delivery fallback interval, left-Navision completion, trigger hook, check 475, rollback', () => {
  const up = fs.readFileSync('supabase/migrations/20261030131500_r758_wpc_completes_on_navision.sql', 'utf8');
  assert.match(up, /FUNCTION pdc_navision_delivery_private\.work_complete_at_758\(p_vehicle public\.vehicles\)/);
  assert.match(up, /IF md5\(v_old\) <> 'b7f8a5e503f820fa85d21ccac579e582' THEN RAISE EXCEPTION 'r758: reconcile_navision_delivery_734/);
  assert.match(up, /has_fallback:=true; duration:=greatest\(0,floor\(extract\(epoch FROM\(closed_at-fallback_start\)\)\)::bigint\)/);
  assert.match(up, /'Delivered - At Dealer \(from work complete, no RFT booking\)'/);
  assert.match(up, /FUNCTION pdc_navision_delivery_private\.complete_left_navision_758\(p_backend_record_id uuid\)/);
  assert.match(up, /v\.qc_completed_at IS NULL\s*\n\s*OR upper\(btrim\(coalesce\(v\.current_location, ''\)\)\) <> 'RFT'/, 'only work-complete cars at WPC/RFT');
  assert.match(up, /left_navision_open_booking/);
  assert.match(up, /IF md5\(v_old\) <> '54fbd5264b1a3dca04840ca635b5a55f' THEN RAISE EXCEPTION 'r758: trigger body/);
  assert.match(up, /AND NOT \(NEW\.is_current AND NEW\.record_status=''current''\) AND NEW\.canonical_vehicle_id IS NOT NULL THEN/);
  assert.match(up, /'wpc_completes_on_navision_758', 'F364',/);
  const down = fs.readFileSync('supabase/rollbacks/20261030131500_r758_wpc_completes_on_navision.down.sql', 'utf8');
  assert.match(down, /would not return to the r734 md5/);
  assert.match(down, /DROP FUNCTION pdc_navision_delivery_private\.complete_left_navision_758\(uuid\)/);
});
