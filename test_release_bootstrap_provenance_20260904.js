'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  createPdcEmailVehicleLocationService,
  PDC_VEHICLE_HISTORY_RPC,
} = require('./pdc-email-vehicle-location-service.js');

const baselinePath = path.join('supabase', 'release_history', '014_vehicle_intelligence_timeline_foundation.sql');
assert(fs.existsSync(baselinePath), 'clean Preview baseline migration 014 must remain present in the repository');
const baseline = fs.readFileSync(baselinePath, 'utf8');
const optionalPolicyBlock = baseline.match(/DO \$vehicle_intelligence_summary_policy\$[\s\S]*?\$vehicle_intelligence_summary_policy\$;/i)?.[0] || '';
assert(optionalPolicyBlock, 'optional vehicle intelligence summary policy must use a narrow conditional block');
assert.match(optionalPolicyBlock, /to_regclass\('public\.vehicle_intelligence_summaries'\)\s+is\s+not\s+null/i);
assert.match(optionalPolicyBlock, /execute\s+'drop policy if exists vehicle_intelligence_summaries_select_viewer on public\.vehicle_intelligence_summaries'/i);
assert.match(optionalPolicyBlock, /execute\s+'create policy vehicle_intelligence_summaries_select_viewer on public\.vehicle_intelligence_summaries for select to authenticated using \(public\.is_pdc_role\(''viewer''\)\)'/i);
assert.match(optionalPolicyBlock, /execute\s+'alter table public\.vehicle_intelligence_summaries enable row level security'/i);
assert.match(optionalPolicyBlock, /execute\s+'revoke insert, update, delete on table public\.vehicle_intelligence_summaries from anon, authenticated'/i);
assert.match(optionalPolicyBlock, /pg_publication_tables/i);
assert(!/^\s*drop policy if exists vehicle_intelligence_summaries_select_viewer on public\.vehicle_intelligence_summaries\s*;/im.test(baseline), 'optional relation must never be referenced by an unguarded DROP POLICY');
assert(!/^\s*alter table public\.vehicle_intelligence_summaries\b/im.test(baseline), 'optional relation must never be referenced by unguarded RLS DDL');
assert(!/^\s*create trigger vehicle_intelligence_summaries_set_updated_at\b/im.test(baseline), 'optional relation trigger must be catalog-guarded');
assert(!/^\s*alter publication supabase_realtime add table public\.vehicle_intelligence_summaries\s*;/im.test(baseline), 'optional relation publication membership must be catalog-guarded');

const canonicalHistorySql = fs.readFileSync('supabase/staging_only/20260830093000_pdc_lifecycle_history.sql', 'utf8');
const indexHtml = fs.readFileSync('index.html', 'utf8');
assert.match(canonicalHistorySql, /CREATE FUNCTION public\.get_pdc_vehicle_provenance_history\(p_vehicle_id uuid\)/);
assert(!/CREATE FUNCTION public\.get_pdc_vehicle_provenance_history\(p_vehicle_id uuid\s*,/i.test(canonicalHistorySql));
assert.match(canonicalHistorySql, /GRANT EXECUTE ON FUNCTION public\.get_pdc_vehicle_provenance_history\(uuid\) TO authenticated/);
assert(!/GRANT\s+(?:SELECT|ALL)[\s\S]{0,120}pdc_vehicle_lifecycle_history_events_82000/i.test(canonicalHistorySql));
assert.match(indexHtml, /pdc-email-vehicle-location-service\.js[^"\n]*provenance-contract=2026\.09\.04\.01/, 'changed provenance caller asset must receive a release-specific cache key');

(async () => {
  const requests = [];
  const service = createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'test-publishable-key' },
    getAccessToken: () => 'test-access-token',
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return { ok: true, status: 200, json: async () => ({ ok: true, code: 'ok', data: { vehicle: { vehicle_id: 'e49685ca-c9b7-448d-9b45-1aba97d6d3b4' } } }) };
    },
  });
  const result = await service.vehicleHistory('e49685ca-c9b7-448d-9b45-1aba97d6d3b4', '37047');
  assert.strictEqual(result.ok, true);
  assert.strictEqual(requests.length, 1);
  assert.match(requests[0].url, new RegExp(`/rpc/${PDC_VEHICLE_HISTORY_RPC}$`));
  assert.deepStrictEqual(JSON.parse(requests[0].options.body), {
    p_vehicle_id: 'e49685ca-c9b7-448d-9b45-1aba97d6d3b4',
  }, 'browser caller must bind the canonical one-argument provenance RPC exactly');
  console.log('Preview bootstrap guard and canonical provenance caller contract passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
