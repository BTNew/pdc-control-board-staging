#!/usr/bin/env node
const fs=require('fs'),crypto=require('crypto');
const assert=(v,m)=>{if(!v)throw new Error(m)};
const sql=fs.readFileSync('supabase/staging_only/167_live_vehicle_alias_identity_ownership.sql','utf8');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p,'utf8').replace(/\r\n/g,'\n')).digest('hex');
assert(sha('supabase/staging_only/166_operator_apply_and_terminal_quarantine.sql')==='7354760cf412959d09116b83de96b989212fb7d1d4a865d33c5514f4e6e6701a','Migration166 drift');
assert(/pdc_monitor_staging_guard\(\)/.test(sql)&&/version='166' and name='operator_apply_and_terminal_quarantine'/.test(sql)&&/version>'166'/.test(sql),'staging/predecessor guards missing');
assert(sql.indexOf('lock table public.vehicles')<sql.indexOf('lock table public.vehicle_aliases'),'identity lock order drift');
assert(/set active=false from public\.vehicles owner where owner\.id=a\.vehicle_id and owner\.deleted_at is not null/.test(sql),'existing deleted-owner alias cleanup missing');
assert(/drop constraint if exists vehicle_aliases_alias_type_alias_value_key/.test(sql),'legacy global raw alias constraint retained');
assert(/active vehicle alias requires a live owner/.test(sql),'active alias live-owner guard missing');
assert(/before insert or update of vehicle_id,alias_type,alias_value,active,source_system/.test(sql),'alias owner reassignment must execute identity trigger');
assert((sql.match(/join public\.vehicles owner on owner\.id=a\.vehicle_id and owner\.deleted_at is null/g)||[]).length===2,'alias collision checks must ignore deleted owners');
assert(/and v\.deleted_at is null/.test(sql),'canonical collision check must ignore deleted vehicles');
assert(/create trigger vehicles_deactivate_aliases_on_soft_delete/.test(sql)&&/update public\.vehicle_aliases set active=false where vehicle_id=new\.id and active/.test(sql),'atomic soft-delete alias deactivation missing');
assert((sql.match(/alias_owner\.deleted_at is null/g)||[]).length===2,'Stock and registration classifier aliases must have live owners');
assert(/update public\.navision_backend_revision set revision=revision\+1/.test(sql),'preview invalidation missing');
assert(/values\('167','live_vehicle_alias_identity_ownership'/.test(sql),'ledger entry missing');
console.log('Migration167 live vehicle alias ownership contracts passed');
