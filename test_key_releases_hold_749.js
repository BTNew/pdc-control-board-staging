'use strict';
// r749 (F354): a key number releases a body-builder hold, so a keyed car never waits in New to PMB on one.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030100000_r749_key_number_releases_bodybuilder_hold.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030100000_r749_key_number_releases_bodybuilder_hold.down.sql', 'utf8');

test('r749: release mirrors To PMB, both triggers in place, check 462, hold check widened only for key_number', () => {
  assert.match(up, /PERFORM set_config\('pdc\.bodybuilder_to_pmb_574', r\.arrival_id::text, true\);/, 'passes the r574 arrival guard the same way To PMB does');
  assert.match(up, /release_action = 'key_number'/);
  assert.match(up, /OR \(released_at IS NOT NULL AND release_action = 'to_pmb' AND released_by IS NOT NULL\)/, 'To PMB still needs an actor');
  assert.match(up, /CREATE TRIGGER zz_pdc_key_releases_hold_745 AFTER UPDATE OF key_number ON public\.vehicles/);
  assert.match(up, /CREATE CONSTRAINT TRIGGER zz_pdc_hold_opened_with_key_745 AFTER INSERT ON pdc_pmb_ack_private\.bodybuilder_hold_574\n DEFERRABLE INITIALLY DEFERRED/);
  assert.match(up, /IF n <> 3 THEN RAISE EXCEPTION/, 'the three stuck cars, no more');
  assert.match(up, /'key_number_releases_bodybuilder_hold_745', 'F354', 'r749', true, 462,/);
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_pmb_ack_private\.release_hold_on_key_745\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.match(down, /DROP TRIGGER IF EXISTS zz_pdc_key_releases_hold_745 ON public\.vehicles;/);
  assert.match(down, /key_number releases exist; the widened check stays/);
});
