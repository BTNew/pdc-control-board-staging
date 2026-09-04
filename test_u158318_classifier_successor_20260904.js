'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(
  __dirname,
  'supabase/staging_only/20260904010600_u158318_jobcard_classifier.sql',
);
assert.ok(fs.existsSync(migrationPath), 'append-only U158318 classifier migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "v_head IS DISTINCT FROM '20260904010500'",
  "VALUES('20260904010600','u158318_jobcard_classifier'",
  "standalone mine bars remain Fabrication",
  "Production untouched",
]) assert.ok(sql.includes(marker), `missing guarded successor marker: ${marker}`);

const applyPath = path.join(__dirname, 'scripts/apply_u158318_classifier_20260904.py');
assert.ok(fs.existsSync(applyPath), 'guarded U158318 STAGING apply/read-back script must exist');
const applyScript = fs.readFileSync(applyPath, 'utf8');
for (const marker of [
  'cdsmnqxtyyoeoznmbidd',
  '20260904010600',
  'dry-run',
  'ROLLBACK',
  'security_advisor_summary',
  'production_contacted',
  'email_contacted',
]) assert.ok(applyScript.includes(marker), `apply/read-back script missing ${marker}`);
assert.ok(!applyScript.includes('vjdtsswhroyguxyfjdkt'), 'apply/read-back script must not contain or contact Production');

const operations = [
  ['BUS 4X4 CONVERSION SLWB & COMMUTER 05C2B', 'bus4x4'],
  ['Bus 4x4 Conversion 5x BFG 265/65R17 Tyres and Rims', 'tyre'],
  ['BUS 4X4 Tanami Snorkel', 'bus4x4'],
  ['Hiace Rock Sliders', 'fitting'],
  ['MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON -ACOT500', 'electrical'],
  ['BATTERY ISOLATOR WITH RED LOCKOUT', 'electrical'],
  ['175 AMP JUMP START UNDER BONNET', 'electrical'],
  ['Headlamps Auto On & Hand Brake OFF Alarm -DYNAMCO', 'electrical'],
  ['MMT COMMUTER SEAT COVERS -CANVAS', 'fitting'],
  ['MOUNTED WHEEL CHOCKS AND HOLDER', 'fitting'],
  ['SAFETY TRIANGLE IN PMB HOLDER', 'fitting'],
  ['WHEEL NUT INDICATORS -COMMUTER', 'tyre'],
  ['UHF GME XRS370C WITH AE4704B AERIAL', 'electrical'],
  ['SUB REFLECTIVE STRIPING YELLOW', 'sublet'],
  ['Darkest Legal Tint Commuter van', 'tint'],
  ['NARVA (72843) 20" EX2-R LIGHT BAR RGB DOUBLE RGB ENABLED', 'electrical'],
  ['POST REGO CONVERSION', 'bus4x4'],
  ['2.5KG FIRE EXTINGUISHER', 'fabrication'],
];
for (const [description, workKey] of operations) {
  const assertion = `public.pdc_email_jobcard_work_key('${description.replaceAll("'", "''")}') IS DISTINCT FROM '${workKey}'`;
  assert.ok(sql.includes(assertion), `missing exact classifier regression: ${description} -> ${workKey}`);
}

for (const preserved of [
  "public.pdc_email_jobcard_work_key('MINE BAR') IS DISTINCT FROM 'fabrication'",
  "public.pdc_email_jobcard_work_key('!FAB MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON') IS DISTINCT FROM 'fabrication'",
  "public.pdc_email_jobcard_work_key('Bedrock Sliders') IS DISTINCT FROM 'owner_supplied_document'",
  "public.pdc_email_jobcard_work_key('Unmapped bespoke instruction') IS DISTINCT FROM 'owner_supplied_document'",
  "has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')",
  "NOT has_function_privilege('authenticated','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')",
  "NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='pdc_non_navision_operation_lines_immutable' AND tgenabled='O')",
  "planner_enabled FROM public.workshop_stages WHERE code='PIT_INSPECTION'",
]) assert.ok(sql.includes(preserved), `missing preserved contract assertion: ${preserved}`);

console.log('U158318 exact classifier successor regression: PASS');
