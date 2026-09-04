'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260905010000_navision_linked_location_projection.sql';
assert.ok(fs.existsSync(migrationPath), 'guarded linked-location successor exists');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  'cdsmnqxtyyoeoznmbidd',
  '20260904011500',
  'parts_stoppage_runtime_containment_repair',
  'pdc_project_linked_navision_location_20260905',
  'navision_operational_location(v_record.normalized_data)',
  "v_status='deliveredatbodybuilder'",
  "location_latch_preserved",
  "projection_not_required",
  'pdc_navision_vehicle_parity_494',
  'audit_pdc_event',
  'pdc_refresh_linked_vehicle_from_navision_481_pre_20260905',
  "'20260905010000'",
  "'navision_linked_location_projection'",
]) assert.ok(sql.includes(marker), `linked-location successor missing ${marker}`);

assert.match(sql, /ALTER FUNCTION public\.pdc_refresh_linked_vehicle_from_navision_481\(uuid,uuid,text\)\s+RENAME TO pdc_refresh_linked_vehicle_from_navision_481_pre_20260905/i);
assert.match(sql, /v_base:=public\.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905\(p_backend_record_id,p_actor_id,p_actor_email\)/i, 'approved descriptive refresh runs first');
assert.match(sql, /IF NOT coalesce\(\(v_base->>'ok'\)::boolean,false\) THEN RETURN v_base; END IF/i, 'failed/unauthorized predecessor results cannot project');
assert.match(sql, /v_projection:=public\.pdc_project_linked_navision_location_20260905\(p_backend_record_id,p_actor_id,p_actor_email\)/i);
assert.match(sql, /position\('reconcile_navision_operational_record_pre_734' in v_public\)=0[\s\S]*position\('reconcile_navision_delivery_734' in v_public\)=0/i, 'public delivery/security wrapper remains unchanged');
assert.match(sql, /cardinality\(v_vehicle_ids\)<>1[\s\S]*canonical_identity_conflict/i, 'ambiguous identities fail closed');
assert.match(sql, /v_current IN \('PMB','PIT','QC','RFT','COLLECTED','COMPLETED'\)[\s\S]*location_latch_preserved/i, 'manual/progress latches cannot be repositioned');
assert.match(sql, /v_location='YH'[\s\S]*v_target:='YH'/i, 'approved past-ETA waiting state can project IT to YH');
assert.match(sql, /v_location='PMB'[\s\S]*v_status='deliveredatbodybuilder'[\s\S]*v_target:='PMB'/i, 'only exact Body Builder state auto-projects PMB');
assert.doesNotMatch(sql, /v_location='Other'[\s\S]{0,200}v_target:=/i, 'ordinary/future-ETA Other mappings do not reposition');
assert.match(sql, /REVOKE ALL ON FUNCTION public\.pdc_refresh_linked_vehicle_from_navision_481\(uuid,uuid,text\) FROM public,anon,authenticated,service_role/i);
assert.doesNotMatch(sql, /GRANT EXECUTE ON FUNCTION public\.pdc_refresh_linked_vehicle_from_navision_481\(uuid,uuid,text\)/i, 'linked refresh remains private');

console.log('Navision linked location projection successor: PASS');
