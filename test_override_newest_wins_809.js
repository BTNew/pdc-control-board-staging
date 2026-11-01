'use strict';
// r809 (F444): a line tick or untick after a station override cancels the override (newest action wins). Key 102 Tint.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/migrations/20261101192500_r809_override_newest_wins.sql', 'utf8');
test('trigger on the board line tick, only when the tick really changes, nesting OLD inside the UPDATE test', () => {
  assert.match(sql, /CREATE TRIGGER zz_override_newest_wins_809 AFTER INSERT OR UPDATE OF completed ON public\.pdc_panel_line_completion_565\s+FOR EACH ROW/);
  assert.match(sql, /IF TG_OP = 'UPDATE' THEN\s+IF OLD\.completed IS NOT DISTINCT FROM NEW\.completed THEN RETURN NULL; END IF;\s+END IF;/);
});
test('cancels only an override that is on and older than the line change, with a history row', () => {
  assert.match(sql, /WHERE vehicle_id = p_vehicle_id AND work_key = p_work_key AND completed AND acted_at < p_before\) THEN\s+RETURN false;/);
  assert.match(sql, /INSERT INTO public\.pdc_station_completion_history_578/);
  assert.match(sql, /SET completed = false, actor_id = p_actor_id/);
});
test('the line station is counted as the icons count it (handoff first)', () => {
  assert.match(sql, /coalesce\(pdc_work_categories_private\.line_handoff_work_key_583\(h\.to_stage_code\),/);
  for (const k of ['tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'parts', 'bus4x4']) assert.ok(sql.includes(`THEN '${k}'`), k);
});
test('retro is bounded and private helpers are not callable by logins', () => {
  assert.match(sql, /IF n > 5 THEN RAISE EXCEPTION 'r809: retro would cancel/);
  assert.match(sql, /WHERE i\.done < i\.total/);
  assert.match(sql, /REVOKE ALL ON FUNCTION pdc_work_categories_private\.cancel_override_809\(uuid, text, timestamptz, uuid, text, text, timestamptz\) FROM PUBLIC, anon, authenticated;/);
});
