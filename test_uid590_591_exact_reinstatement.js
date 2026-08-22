'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '20260822130000_318_reinstate_uid590_591_exact_archived_vehicles.sql'), 'utf8');
assert(sql.includes('PDC_318_PRODUCTION_SENTINEL_PRESENT'));
assert(sql.includes("v_project is distinct from 'cdsmnqxtyyoeoznmbidd'"));
for (const value of [
  'imap_uid:590','imap_uid:591',
  '9095b557-9ddf-4f6f-9d21-a5fa419c54e3','0b4339a0-ae16-4d64-8bba-33fd2ef2d798',
  '5149bfc9-ab29-472c-9bcb-73b0315ba8b6','fd2b3adf-4244-4c32-b5b9-7789cd579e3e',
  '13018324','13001466','J139125160','J139125226',
  '5ad6f5e2-674c-5bd0-af02-b5a8f25fdfce','19b74592-f41a-515c-bf61-46d06b8667ed',
  '9bb43a07-9d01-442f-bb04-780a3bdce0aa','cb81e3a9-d6da-4562-a0f6-23553d540293',
  '14450','37047'
]) assert(sql.includes(value), `missing exact binding ${value}`);
assert(sql.includes('PDC_318_IDENTITY_CONFLICT'));
assert(sql.includes('PDC_318_TERMINAL_RECEIPT_ALREADY_EXISTS'));
assert(sql.includes("status='received'"));
assert(sql.includes('pdc_uid590_591_exact_reinstatements_318'));
assert(sql.includes('PDC_318_REINSTATEMENT_RECEIPT_IMMUTABLE'));
assert(sql.trim().endsWith('commit;'));
console.log('uid590_591_exact_reinstatement: PASS');
