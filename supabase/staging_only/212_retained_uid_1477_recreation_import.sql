-- Staging-only retained UID 1:477 controlled recreation/import remediation.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-212',0));
select public.pdc_monitor_staging_guard();
do $guard$
begin
 if not public.pdc_monitor_staging_guard()
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='211' and name='vehicle_archive_environment_reattestation')
    or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>211)
    or exists(select 1 from supabase_migrations.schema_migrations where version='212') then
  raise exception 'PDC_212_STAGING_PREREQUISITE_MISSING' using errcode='55000';
 end if;
end $guard$;

create table public.pdc_retained_reset_import_receipts_212(
 receipt_id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references auth.users(id) on delete restrict,
 tombstone_id uuid not null unique references public.pdc_vehicle_tombstones(tombstone_id) on delete restrict,
 permission_id uuid not null unique references public.pdc_vehicle_recreation_permissions(permission_id) on delete restrict,
 old_proposal_id uuid not null references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
 rebound_proposal_id uuid not null unique references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
 provider_uid text not null unique,
 parent_source_hash text not null unique check(parent_source_hash~'^[a-f0-9]{64}$'),
 attachment_hash text not null check(attachment_hash~'^[a-f0-9]{64}$'),
 vehicle_id uuid not null unique references public.vehicles(id) on delete restrict,
 canonical_import_receipt_id uuid not null unique references public.pdc_authenticated_email_import_receipts(receipt_id) on delete restrict,
 operation_count integer not null check(operation_count=13),
 estimated_hours_sum numeric(10,2) not null check(estimated_hours_sum=13.32),
 request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
 response jsonb not null check(jsonb_typeof(response)='object'),
 created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_retained_reset_import_receipts_212 enable row level security;
revoke all on table public.pdc_retained_reset_import_receipts_212 from public,anon,authenticated,service_role;
create function public.pdc_retained_reset_receipt_immutable_212() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$begin raise exception 'PDC_212_RECEIPT_IMMUTABLE' using errcode='55000';end$$;
revoke all on function public.pdc_retained_reset_receipt_immutable_212() from public,anon,authenticated,service_role;
create trigger pdc_retained_reset_receipt_immutable_212 before update or delete on public.pdc_retained_reset_import_receipts_212 for each row execute function public.pdc_retained_reset_receipt_immutable_212();

create function public.get_pdc_retained_reset_binding_212(p_stock text)
returns table(stock_number text,tombstone_id uuid,tombstone_kind text,grant_exists boolean,grant_unused boolean,grant_expires_at timestamptz,intended_source_hash text,intended_evidence_hash text,intended_source_uid text)
language plpgsql stable security definer set search_path=pg_catalog,public,auth as $$
declare a uuid:=auth.uid();e text:=lower(btrim(coalesce(auth.jwt()->>'email','')));s text:=public.normalize_vehicle_stock_number(p_stock);
begin
 if not public.pdc_monitor_staging_guard() or s<>'13047224' or not exists(select 1 from public.pdc_user_roles r join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id where r.auth_user_id=a and lower(r.email)=e and r.role='importer' and r.active and r.account_status='approved' and w.active and w.revoked_at is null) then raise insufficient_privilege using message='importer_required';end if;
 return query select t.normalized_stock,t.tombstone_id,t.tombstone_kind,p.permission_id is not null,p.permission_id is not null and p.consumed_at is null,p.expires_at,p.intended_source_hash,p.intended_evidence_hash,p.intended_source_uid from public.pdc_vehicle_tombstones t left join lateral(select * from public.pdc_vehicle_recreation_permissions x where x.tombstone_id=t.tombstone_id order by x.authorized_at desc limit 1)p on true where t.normalized_stock=s and t.tombstone_kind='staging_reset' order by t.deleted_at desc limit 1;
end$$;
revoke all on function public.get_pdc_retained_reset_binding_212(text) from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_retained_reset_binding_212(text) to authenticated;

-- Existing attachment functions remain exact hash/manifest bound, but the scoped
-- enrolled identity is now Importer rather than the obsolete Viewer label.
do $rewrite$
declare d text;
begin
 select pg_get_functiondef('public.attest_pdc_authenticated_email_attachments(text,jsonb)'::regprocedure) into d;
 if position($needle$r.role='viewer'$needle$ in d)=0 then raise exception 'PDC_212_ATTEST_SHAPE_CHANGED';end if;
 execute replace(d,$needle$r.role='viewer'$needle$,$needle$r.role='importer'$needle$);
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_attachment(text,integer,text,jsonb,jsonb)'::regprocedure) into d;
 if position($needle$r.role='viewer'$needle$ in d)=0 then raise exception 'PDC_212_IMPORT_SHAPE_CHANGED';end if;
 execute replace(d,$needle$r.role='viewer'$needle$,$needle$r.role='importer'$needle$);
end $rewrite$;
revoke all on function public.attest_pdc_authenticated_email_attachments(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.attest_pdc_authenticated_email_attachments(text,jsonb) to authenticated;
revoke all on function public.import_pdc_authenticated_vehicle_attachment(text,integer,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_attachment(text,integer,text,jsonb,jsonb) to authenticated;

create function public.import_pdc_retained_reset_jobcard_212(
 p_provider_uid text,p_parent_source_hash text,p_attachment_hash text,p_stock text,p_job_card text,p_vin text,p_operation_lines jsonb
) returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,extensions,auth set statement_timeout='180s' as $$
declare
 a uuid:=auth.uid();e text:=lower(btrim(coalesce(auth.jwt()->>'email','')));s text:=public.normalize_vehicle_stock_number(p_stock);vuid text:=btrim(coalesce(p_provider_uid,''));sh text:=lower(btrim(coalesce(p_parent_source_hash,'')));ah text:=lower(btrim(coalesce(p_attachment_hash,'')));jc text:=upper(btrim(coalesce(p_job_card,'')));vin text:=public.normalize_vehicle_vin(p_vin);
 oldp public.pdc_ai_intake_proposals%rowtype;newp public.pdc_ai_intake_proposals%rowtype;t public.pdc_vehicle_tombstones%rowtype;perm public.pdc_vehicle_recreation_permissions%rowtype;nav public.navision_backend_records%rowtype;v public.vehicles%rowtype;rec public.pdc_authenticated_email_import_receipts%rowtype;rr public.pdc_retained_reset_import_receipts_212%rowtype;
 ops jsonb:=coalesce(p_operation_lines,'null'::jsonb);req jsonb;reqhash text;digest text;vid uuid;op jsonb;k text;lineid uuid;linehash text;lineids uuid[]:='{}';total numeric(10,2);response jsonb;oldid uuid;newid uuid;rrid uuid:=gen_random_uuid();
begin
 if not public.pdc_monitor_staging_guard() or not exists(select 1 from public.pdc_user_roles r join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id where r.auth_user_id=a and lower(r.email)=e and r.role='importer' and r.active and r.account_status='approved' and w.active and w.revoked_at is null) then return public.navision_backend_response(false,'importer_required');end if;
 if vuid<>'1:477' or sh<>'971afa06b68bb54a94316a8d14fc3a6bf95d3eb8364d50a366add8cf7e6ee7cb' or ah<>'9ab13a8a43200ad32470b06406e1a1c7c53d85dc8f9e3b1d9ba3fe21170aabcd' or s<>'13047224' or jc<>'J139125358' or vin<>'MR0PEBHV600404885' or jsonb_typeof(ops)<>'array' or jsonb_array_length(ops)<>13 then return public.navision_backend_response(false,'retained_source_binding_mismatch');end if;
 if exists(select 1 from jsonb_array_elements(ops)x where jsonb_typeof(x)<>'object' or (select array_agg(key_name order by key_name) from jsonb_object_keys(x) key_name) is distinct from array['description','estimated_hours','operation_no','source_row_no','work_key']::text[] or x->>'operation_no'!~'^OP([1-9]|1[0-3])$' or (x->>'source_row_no')!~'^[0-9]+$' or (x->>'source_row_no')::int not between 1 and 13 or x->>'work_key' not in('fitting','tyre','electrical','hoist','pitInspection') or length(btrim(x->>'description')) not between 1 and 180 or (x->>'estimated_hours')!~'^([0-9]+)(\.[0-9]{1,2})?$') or (select count(distinct x->>'operation_no') from jsonb_array_elements(ops)x)<>13 or (select count(distinct (x->>'source_row_no')::int) from jsonb_array_elements(ops)x)<>13 then return public.navision_backend_response(false,'invalid_operation_lines');end if;
 select sum((x->>'estimated_hours')::numeric) into total from jsonb_array_elements(ops)x;
 if total<>13.32 or (select coalesce(sum((x->>'estimated_hours')::numeric),0) from jsonb_array_elements(ops)x where x->>'work_key'='fitting')<>8.42 or (select coalesce(sum((x->>'estimated_hours')::numeric),0) from jsonb_array_elements(ops)x where x->>'work_key'='tyre')<>1.40 or (select coalesce(sum((x->>'estimated_hours')::numeric),0) from jsonb_array_elements(ops)x where x->>'work_key'='electrical')<>2.00 or (select coalesce(sum((x->>'estimated_hours')::numeric),0) from jsonb_array_elements(ops)x where x->>'work_key'='hoist')<>1.50 then return public.navision_backend_response(false,'operation_totals_mismatch');end if;
 reqhash:=encode(extensions.digest(convert_to(jsonb_build_object('contract',212,'actor',a,'uid',vuid,'source_hash',sh,'attachment_hash',ah,'stock',s,'job_card',jc,'vin',vin,'operations',ops)::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc-retained-reset-212:'||s,0));
 select * into rr from public.pdc_retained_reset_import_receipts_212 where provider_uid=vuid for update;
 if found then if rr.request_sha256<>reqhash then return public.navision_backend_response(false,'idempotency_conflict');end if;return rr.response;end if;
 select * into oldp from public.pdc_ai_intake_proposals where source_hash=sh and source_uid=vuid and submitted_by=a for update;
 if not found or oldp.proposal_id::text<>(select proposal_ref from public.pdc_email_source_claims where source_hash=sh) or oldp.sender_address<>'craig.watson@broometoyota.com.au' or oldp.authentication->>'sender_domain'<>'broometoyota.com.au' or oldp.authentication->'gmail_authentication_results'<>'true'::jsonb or not(oldp.authentication->'spf_aligned'='true'::jsonb or oldp.authentication->'dkim_aligned'='true'::jsonb or oldp.authentication->'dmarc_aligned'='true'::jsonb) then return public.navision_backend_response(false,'source_proposal_binding_mismatch');end if;
 select * into t from public.pdc_vehicle_tombstones where normalized_stock=s and tombstone_kind='staging_reset' order by deleted_at desc limit 1 for update;
 if not found or exists(select 1 from public.pdc_vehicle_lifecycle_events le where le.tombstone_id=t.tombstone_id and le.event_kind in('restored','recreation_consumed')) then return public.navision_backend_response(false,'staging_reset_not_available');end if;
 select * into nav from public.navision_backend_records where source_system='microsoft_navision' and is_current and record_status='current' and public.normalize_vehicle_stock_number(normalized_data->>'batch')=s for update;
 if not found or public.normalize_vehicle_vin(nav.normalized_data->>'vin')<>vin then return public.navision_backend_response(false,'canonical_vehicle_binding_mismatch');end if;
 req:='["Tint","Hoist/GVM","Fitting","Electrical","Tyre","Pit Inspection","Parts"]'::jsonb;
 oldid:=oldp.proposal_id;
 insert into public.pdc_ai_intake_proposals(dedupe_key,source_hash,evidence_hash,source_uid,sender_address,authentication,source_received_at,subject,action_type,stock_number,backend_record_id,backend_record_version,observed_navision_revision,summary,observations,fingerprint,status,submitted_by)
 values(encode(extensions.digest(convert_to('212:'||reqhash,'UTF8'),'sha256'),'hex'),sh,ah,vuid,oldp.sender_address,oldp.authentication,oldp.source_received_at,oldp.subject,'board_activate_only',s,nav.id,nav.version,oldp.observed_navision_revision,'Migration 212 retained UID 1:477 exact staging-reset rebind',jsonb_build_object('authenticated',true,'match_outcome','resolved_navision_exact','required_work',req,'attachment_manifest',jsonb_build_array(jsonb_build_object('attachment_index',1,'attachment_hash',ah,'filename','retained-job-card.pdf'))),upper(substr(encode(extensions.digest(convert_to('212-fingerprint:'||reqhash,'UTF8'),'sha256'),'hex'),1,16)),'pending',a) returning * into newp;
 -- Preserve the immutable original source claim. The append-only rebind receipt below
 -- records the old/new proposal generation; this RPC owns that exact translation.
 digest:=encode(extensions.digest(jsonb_build_object('source_hash',sh,'evidence_hash',ah,'source_uid',vuid)::text,'sha256'),'hex');
 insert into public.pdc_vehicle_recreation_permissions(tombstone_id,normalized_stock,authorized_by,expires_at,intended_source_hash,intended_evidence_hash,intended_source_uid,intended_evidence_digest)
 values(t.tombstone_id,s,t.deleted_by,clock_timestamp()+interval '120 minutes',sh,ah,vuid,digest) returning * into perm;
 vid:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,s||':'||vin||':'||sh);
 insert into public.vehicles(id,permanent_vehicle_id,stock_number,vin,job_card_number,customer_name,vehicle_description,model,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
 values(vid,'PDC-AI-'||upper(substr(sh,1,24)),s,vin,jc,coalesce(nav.normalized_data->>'client',nav.normalized_data->>'customerSurname'),coalesce(nav.normalized_data->>'modelDescription',nav.normalized_data->>'vehicle'),coalesce(nav.normalized_data->>'modelDescription',nav.normalized_data->>'vehicle'),'active',true,'IT','authenticated_email',nav.dealer_code,vuid,jsonb_build_object('source_hash',sh,'attachment_hash',ah,'evidence_hash',ah,'provider_uid',vuid,'backend_record_id',nav.id,'contract','pdc_retained_reset_212'),a,a) returning * into v;
 update public.navision_backend_records set canonical_vehicle_id=vid where id=nav.id;
 insert into public.navision_board_activations(backend_record_id,canonical_vehicle_id,activated_stock_number,active,activated_by,activation_source) values(nav.id,vid,s,true,a,'approved_email_build') on conflict(backend_record_id) do update set canonical_vehicle_id=excluded.canonical_vehicle_id,activated_stock_number=excluded.activated_stock_number,active=true,completed_at=null,activated_by=excluded.activated_by,activation_source=excluded.activation_source;
 response:=public.navision_backend_response(true,'retained_reset_jobcard_imported',jsonb_build_object('receipt_id',rrid,'vehicle_id',vid,'stock_number',s,'job_card_number',jc,'vin',vin,'operation_count',13,'estimated_hours_sum',13.32,'booking_created',false,'deleted_vehicle',false));
 insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response)
 values(a,'pdc-email-import-'||substr(sh,1,40),reqhash,sh,ah,vuid,oldp.sender_address,oldp.source_received_at,s,vin,nav.id,nav.version,vid,'navision_exact',req,response) returning * into rec;
 for op in select value from jsonb_array_elements(ops) loop
  linehash:=encode(extensions.digest(convert_to(jsonb_build_object('source_hash',sh,'operation_no',op->>'operation_no','work_key',op->>'work_key','description',btrim(op->>'description'),'estimated_hours',(op->>'estimated_hours')::numeric)::text,'UTF8'),'sha256'),'hex');
  insert into public.pdc_authenticated_email_operation_lines(import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract)
  values(rec.receipt_id,vid,sh,vuid,op->>'operation_no',op->>'work_key',btrim(op->>'description'),linehash,(op->>'estimated_hours')::numeric,'job_card',jc,(op->>'source_row_no')::int,'pmb-email-communications-v1') returning operation_line_id into lineid;lineids:=array_append(lineids,lineid);
 end loop;
 foreach newid in array lineids loop insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values('insert','pdc_authenticated_email_operation_lines',newid,vid,a,e,null,jsonb_build_object('operation_line_id',newid),jsonb_build_object('source','pdc_retained_reset_212','no_booking',true));end loop;
 for k in select distinct value->>'work_key' from jsonb_array_elements(ops) loop insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,updated_at) values(vid,k,true,false,clock_timestamp()) on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp();end loop;
 insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,updated_at) values(vid,'tint',true,false,clock_timestamp()),(vid,'PARTS',true,false,clock_timestamp()) on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp();
 -- The tombstone guard consumes the exact permission and writes the single
 -- recreation_consumed lifecycle event during the vehicle insert above.
 insert into public.pdc_retained_reset_import_receipts_212(receipt_id,actor_id,tombstone_id,permission_id,old_proposal_id,rebound_proposal_id,provider_uid,parent_source_hash,attachment_hash,vehicle_id,canonical_import_receipt_id,operation_count,estimated_hours_sum,request_sha256,response)
 values(rrid,a,t.tombstone_id,perm.permission_id,oldid,newp.proposal_id,vuid,sh,ah,vid,rec.receipt_id,13,13.32,reqhash,response) returning * into rr;
 update public.pdc_ai_intake_proposals set status='applied',version=version+1,decided_by=a,decided_by_email=e,decided_at=clock_timestamp(),decision_reason='migration_212_retained_replay',result=response where proposal_id=newp.proposal_id;
 return response;
exception when unique_violation then return public.navision_backend_response(false,'retained_import_conflict');end$$;
revoke all on function public.import_pdc_retained_reset_jobcard_212(text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_retained_reset_jobcard_212(text,text,text,text,text,text,jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('212','retained_uid_1477_recreation_import',array['exact scoped Importer tombstone/grant reader','Importer-only internal attachment attestation/import authority','UID 1:477 exact atomic proposal rebind, one-use recreation, vehicle, 13 operations and canonical receipts','no booking/delete authority']);
notify pgrst,'reload schema';
commit;
