'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '148_bind_canonical_document_evidence_to_retained_source.sql'), 'utf8');

assert(sql.includes("version='147' and name='bind_monitor_import_to_activation_stock'"), 'migration must require exact staging ledger head 147');
assert(sql.includes("p.source_hash=v_source_hash and p.action_type='board_activate_only' and p.source_uid=v_source_uid"), 'v7 must retain exact source/proposal binding and narrow to activation proposals');
assert(!sql.includes("v_new text:=$new$and p.source_hash=v_source_hash and lower(p.evidence_hash)=v_evidence_hash"), 'v7 must not equate message-level and canonical-document hashes');
assert(sql.includes("'contract_version',7"), 'receipt request hash must be versioned for changed evidence semantics');
assert(sql.includes('pdc_monitor_canonical_stock_import_148'), 'audit source marker must advance to migration 148');
assert(sql.includes("public.normalize_vehicle_stock_number(v_activation.activated_stock_number) is distinct from v_stock"), 'exact activation Stock binding must remain');
assert(sql.includes("insert into supabase_migrations.schema_migrations(version,name,statements) values('148'"), 'migration ledger record is required');
for (const forbidden of ['insert into public.vehicles', 'insert into public.navision_board_activations', 'update public.navision_board_activations']) {
  assert(!sql.toLowerCase().includes(`v_new text:=$new$${forbidden}`), `migration must not add forbidden mutator ${forbidden}`);
}

console.log('migration 148 canonical-document source binding contract verified');
