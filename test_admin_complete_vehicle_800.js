/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r800 (F415, Craig 1 Nov 2026 08:37): administrators can complete a vehicle from the drawer.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r800: drawer button for administrators only, dialog module, loader, migration guards, docs', () => {
  const slideout = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(slideout, /isAdministrator\(\) && !\['completed', 'archived', 'deleted'\]/);
  assert.match(slideout, /root\.PDC_OPEN_ADMIN_COMPLETE\(vehicleFor\(key\) \|\| vehicle\)/);
  assert.match(slideout, /r800=2026\.11\.01\.r800`/);
  const mod = fs.readFileSync('pdc-admin-complete.js', 'utf8');
  assert.match(mod, /role \|\| ''\)\.trim\(\)\.toLowerCase\(\) === 'administrator'/);
  assert.match(mod, /rest\/v1\/rpc\/admin_complete_vehicle_800/);
  assert.match(mod, /p_confirmation_stock: stock, p_reason: reason, p_idempotency_key: crypto\.randomUUID\(\)/);
  assert.match(mod, /stock\.replace\(\/\\s\+\/g, ''\)\.toUpperCase\(\) !== selected\.stock/, 'the stock typed must match before anything is sent');
  assert.match(mod, /refreshEmailVehicleLocations\(\)/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-admin-complete\.js\?r800=2026\.11\.01\.r800/);
  assert.match(entry, /pdc-vehicle-slideout\.js\?[^']*&r800=2026\.11\.01\.r800(?:&r820=2026\.11\.02\.r820)?'/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-admin-complete\.js'/);
  const mig = fs.readFileSync('supabase/migrations/20261101093000_r800_admin_complete_vehicle.sql', 'utf8');
  assert.match(mig, /r\.role = 'administrator'/);
  assert.match(mig, /stock_confirmation_mismatch/);
  assert.match(mig, /started_booking_must_be_completed_first/);
  assert.match(mig, /public\.cancel_workshop_booking\(b\.id, b\.version/);
  assert.match(mig, /admin_completed_800/);
  assert.doesNotMatch(mig, /DELETE FROM public\./);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.admin_complete_vehicle_800\(uuid, integer, text, text, uuid\) FROM PUBLIC, anon/);
  assert.match(fs.readFileSync('supabase/rollbacks/20261101093000_r800_admin_complete_vehicle.down.sql', 'utf8'), /DROP FUNCTION IF EXISTS public\.admin_complete_vehicle_800/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F415 \|/);
});
