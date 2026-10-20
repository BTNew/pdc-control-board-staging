'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const fitters = require('./pdc-fitters.js');
const conversions = require('./pdc-conversions.js');
const catalog = require('./docs/conversion-templates.json');

const migration = fs.readFileSync('supabase/migrations/20261020140000_bus4x4_conversion_simple_tick.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261020140000_bus4x4_conversion_simple_tick.down.sql', 'utf8');
const save = fs.readFileSync('supabase/migrations/20260917074018_conversion_section_checklists.sql', 'utf8');

test('Coaster and HiAce use the ordinary bay checkbox and keep their planning allowances', () => {
  assert.equal(catalog.coaster.sections.reduce((sum, section) => sum + section.planned_minutes, 0), 3765);
  assert.equal(catalog.hiace_commuter.sections.reduce((sum, section) => sum + section.planned_minutes, 0), 2280);
  for (const [id, hours, description] of [
    ['coaster', 60, 'Coaster Bus 4x4 Conversion - 6 Speed 2.8'],
    ['hiace_commuter', 40, 'Bus 4x4 Conversion SLWB & Commuter'],
  ]) {
    const line = {
      conversion: { id, total_minutes: id === 'coaster' ? 3765 : 2280, release_blocked: true, sections: [{ id: '1' }] },
      line_identity: `source:${id}`, description, stage_code: 'BUS_4X4', hours, completed: true, note: '',
    };
    assert.equal(fitters.conversionUsesSimpleTick(line), true);
    const html = fitters.fitterLineCardHtml(line, 0, { editable: true, disabled: false, note: '', open: false });
    assert.match(html, new RegExp(`data-fitter-line="source:${id}"`));
    assert.match(html, new RegExp(`BUS 4X4 · ${hours} h · Work completed`));
    assert.match(html, /Add a note/);
    assert.doesNotMatch(html, /Release blocked|Save section update|Pre-assembly|Section 12/);
  }
  assert.equal(fitters.conversionUsesSimpleTick({ conversion: { needs_review: true } }), false);
  assert.equal(fitters.conversionUsesSimpleTick({ conversion: { id: 'coaster', needs_review: true } }), false);
  assert.equal(fitters.conversionUsesSimpleTick({ description: '6 x Super Single Tyres & Rims - Coaster' }), false);
  const review = conversions.html({ description: 'Bus 4x4 Conversion rework', conversion: { needs_review: true } });
  assert.match(review, /scope needs review/);
  assert.doesNotMatch(review, /data-fitter-line=/);
});

test('the tick change leaves job start, section 12 and the QC import functions alone', () => {
  assert.equal(migration.includes('CREATE OR REPLACE FUNCTION public.start_workshop_work_pre_116'), false);
  assert.match(migration, /40ab1b0a75d347b56c69e54c65ddd193/);
  assert.match(down, /40ab1b0a75d347b56c69e54c65ddd193/);
  assert.match(down, /bc1d9f840b37882e1d3a115bf81bd411/);
  assert.match(down, /85469fbced10980106d83b61c38b8e96/);
  for (const name of ['apply_service_pmb_complete', 'finish_tune_checkout', 'conversion_save', 'conversion_catalog']) {
    assert.equal(migration.includes(`CREATE OR REPLACE FUNCTION pdc_codex_intake_private.${name}`), false, name);
    assert.equal(migration.includes(`CREATE OR REPLACE FUNCTION pdc_fitter_private.${name}`), false, name);
  }
  assert.match(migration, /eea5bb523c2538742db52508665191d3/);
  assert.match(migration, /3e5c6b28e7c025a6ebbae61879ff3a82/);
  assert.match(migration, /c49e4557e6b5d978352476e36589731b/);
  assert.match(migration, /0c8423441e81705290d74f4a85c78ea2/);
  assert.match(save, /sec->>'id'='12' AND nullif\(meta->>'checklist_reference',''\) IS NULL/);
  assert.match(save, /conversion_checklist_required/);
  assert.match(migration, /pdc_monitor_staging_guard/);
  assert.match(migration, /pdc_production_environment_sentinel/);
  assert.equal(migration.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*conversion-tick=2026\.10\.20\.\d\d/);
});

function postgresAvailable() {
  if (process.env.PGHOST) return true;
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-c', 'SELECT 1'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('Sub Status 80 and 99 do not reopen a ticked conversion and still block an unticked one', { skip: postgresAvailable() ? false : 'no local Postgres' }, () => {
  execFileSync(process.execPath, ['scripts/run_bus4x4_conversion_tick_local.js'], { stdio: 'inherit' });
});
