const fs=require('fs'),assert=require('assert');
const p='supabase/staging_only/213_persistent_supervised_email_learning.sql';
const s=fs.readFileSync(p,'utf8');
const has=x=>assert.ok(s.includes(x),`missing ${x}`);
for(const x of [
 "project_ref='cdsmnqxtyyoeoznmbidd'","version='212'","name='retained_uid_1477_recreation_import'","version::integer>212","version='213'","pdc_production_environment_sentinel",
 'pdc_supervised_rule_families','pdc_supervised_rule_versions','pdc_supervised_rule_aliases','pdc_supervised_rule_examples','pdc_supervised_rule_events',
 'original_telegram_instruction','authorized_by_email','effective_from','effective_until','priority','confidence','operation_code','normalized_description','phrase_category','work_key','estimated_hours','cost_ex_gst','sell_ex_gst','gst_percent','currency',
 "event_kind in('proposed','activated','superseded','disabled','undo')",'PDC_213_APPEND_ONLY','pdc_supervised_correction_batches','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_apply_receipts','pdc_supervised_failures',
 'create_pdc_supervised_rule_family_213','propose_pdc_supervised_rule_version_213','activate_pdc_supervised_rule_version_213','disable_pdc_supervised_rule_213','undo_pdc_supervised_rule_213','list_pdc_supervised_rules_213','why_pdc_supervised_email_line_213','review_pdc_supervised_email_line_213','scope_pdc_supervised_corrections_213','apply_pdc_supervised_correction_batch_213','undo_pdc_supervised_correction_batch_213',
 "e='craig.watson@broometoyota.com.au'",'pdc_monitor_stage_activation_writers',"r.role in('viewer','importer')",'monitor_scope_required',
 "when 'operation_code' then 2","when 'exact_description' then 3","when 'phrase' then 4",'existing_mapping','inference_review_required',
 "ae.entity_type='operation_line' and ae.entity_id=l.operation_line_id",'pre-existing manual/authoritative overlay','station-only correction overlay; no source/hour/booking/location/status mutation',
 "'booking_changed',false","'location_changed',false","'status_changed',false",'exact_scope_replay','idempotency_conflict','correction_batch_undone',
 'pdc_supervised_revision','replica identity full','supabase_realtime',
 'correction_12535460_safety_triangle','57a961ce','correction_12661296_bonnet_matte','181e088d','correction_12657868_seat_covers_a','229cdafe','correction_12657868_seat_covers_b','1400e0cf','296043b5','dc7881da','de4e4ba0','65ac95e3','78420504','e4fd4137',
 "'12546480'","'12586645'",'Deleted historical example; evidence only, never correction scope',
 "'213','persistent_supervised_email_learning'"
]) has(x);
assert.strictEqual((s.match(/\('correction_[^\n]+/g)||[]).length,10,'must seed exactly ten authorised groups');
assert.ok(!/\b(vjdtsswhroyguxyfjdkt)\b/i.test(s),'production project forbidden');
assert.ok(!/grant\s+[^;]*(?:table|pdc_supervised_(?:admin|monitor)_scope)[^;]*to\s+(?:anon|public|service_role)/i.test(s),'no direct/public/service grants');
assert.ok(!/grant\s+execute\s+on\s+function\s+public\.(?:create|propose|activate|disable|undo|scope)_pdc_supervised[^;]+to\s+(?:anon|public|service_role)/i.test(s));
assert.ok(!/update\s+public\.pdc_authenticated_email_operation_lines/i.test(s),'immutable source lines must not be rewritten');
assert.ok(!/update\s+public\.(?:vehicles|workshop_bookings|vehicle_work_items|pdc_auditor_)/i.test(s),'apply must not mutate vehicle/booking/status/completion/Auditor state');
assert.ok(!/estimated_hours\s*=/i.test((s.match(/create function public\.apply_pdc_supervised_correction_batch_213[\s\S]*?end\$\$;/)||[''])[0]),'apply must not change hours');
console.log('Migration 213 persistent supervised learning contract passed');
