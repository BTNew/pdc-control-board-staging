-- Staging-only migration 209: close legacy deletion bypasses and bind one-use recreation to exact email evidence.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-209-vehicle-lifecycle-review-hardening',0));

do $guard$
declare v_head text;v_name text;
begin
 select version,name into v_head,v_name from supabase_migrations.schema_migrations
 where version ~ '^[0-9]+$' order by version::bigint desc limit 1;
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or v_head is distinct from '208' or v_name is distinct from 'archived_vehicle_snapshot_lock_volatility'
    or exists(select 1 from supabase_migrations.schema_migrations where version='209') then
  raise exception 'PDC_209_STAGING_OR_LEDGER_MISMATCH' using errcode='55000',detail='wrong_environment_or_exact_head';
 end if;
end
$guard$;

-- Retire every browser-callable legacy path that can bypass recoverable tombstones.
revoke all on function public.mark_vehicle_deleted(uuid,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.restore_vehicle(uuid,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;

-- The five-argument helper may classify tombstone kind and must never be an external API.
revoke all on function public.pdc_admin_archive_vehicle(uuid,integer,text,text,text) from public,anon,authenticated,service_role;

-- Expose manual archive without a caller-controlled tombstone kind.
create or replace function public.pdc_admin_archive_vehicle(
 p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text
) returns jsonb language sql volatile security definer set search_path=pg_catalog,public as $$
 select public.pdc_admin_archive_vehicle(p_vehicle_id,p_expected_version,p_confirmation_stock,p_reason,'manual_delete')
$$;
revoke all on function public.pdc_admin_archive_vehicle(uuid,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_archive_vehicle(uuid,integer,text,text) to authenticated;

-- Bind each one-use permission to immutable evidence from one exact authenticated email.
alter table public.pdc_vehicle_recreation_permissions
 add column if not exists intended_source_hash text,
 add column if not exists intended_evidence_hash text,
 add column if not exists intended_source_uid text,
 add column if not exists intended_evidence_digest text;
alter table public.pdc_vehicle_recreation_permissions
 add constraint pdc_vehicle_recreation_source_hash_format check(intended_source_hash is null or intended_source_hash ~ '^[a-f0-9]{64}$'),
 add constraint pdc_vehicle_recreation_evidence_hash_format check(intended_evidence_hash is null or intended_evidence_hash ~ '^[a-f0-9]{64}$'),
 add constraint pdc_vehicle_recreation_source_uid_format check(intended_source_uid is null or length(intended_source_uid) between 1 and 100),
 add constraint pdc_vehicle_recreation_digest_format check(intended_evidence_digest is null or intended_evidence_digest ~ '^[a-f0-9]{64}$');

create or replace function public.pdc_vehicle_recreation_permission_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if tg_op='DELETE' or old.tombstone_id is distinct from new.tombstone_id or old.normalized_stock is distinct from new.normalized_stock
    or old.intended_source_system is distinct from new.intended_source_system or old.authorized_by is distinct from new.authorized_by
    or old.authorized_at is distinct from new.authorized_at or old.expires_at is distinct from new.expires_at
    or old.intended_source_hash is distinct from new.intended_source_hash
    or old.intended_evidence_hash is distinct from new.intended_evidence_hash
    or old.intended_source_uid is distinct from new.intended_source_uid
    or old.intended_evidence_digest is distinct from new.intended_evidence_digest
    or old.consumed_at is not null or new.consumed_at is null or new.consumed_vehicle_id is null then
  raise exception 'PDC_VEHICLE_RECREATION_PERMISSION_IMMUTABLE' using errcode='55000',detail='immutable_or_invalid_consumption';
 end if;
 return new;
end $$;
revoke all on function public.pdc_vehicle_recreation_permission_guard() from public,anon,authenticated,service_role;

create or replace function public.pdc_vehicle_archive_recreation_gate()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_stock text;v_t public.pdc_vehicle_tombstones%rowtype;v_p public.pdc_vehicle_recreation_permissions%rowtype;v_source text;v_source_hash text;v_evidence_hash text;v_source_uid text;v_digest text;
begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_205_NOT_STAGING' using errcode='55000',detail='wrong_environment'; end if;
 v_stock:=coalesce(new.stock_number_normalized,public.normalize_vehicle_stock_number(new.stock_number));
 if tg_op='UPDATE' then
  select * into v_t from public.pdc_vehicle_tombstones t where t.vehicle_id=old.id
   and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored')
   order by t.deleted_at desc limit 1 for share;
  if found then v_stock:=v_t.normalized_stock;perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone-stock:'||v_stock,0));end if;
 end if;
 if v_t.tombstone_id is null then
  if v_stock is null then return new;end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone-stock:'||v_stock,0));
  select * into v_t from public.pdc_vehicle_tombstones t where t.normalized_stock=v_stock
   and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored')
   order by t.deleted_at desc limit 1 for share;
 end if;
 if not found then return new;end if;
 if exists(select 1 from public.pdc_vehicle_recreation_permissions p where p.tombstone_id=v_t.tombstone_id and p.consumed_at is not null and p.consumed_vehicle_id=new.id) then return new;end if;
 if tg_op='UPDATE' and new.id=v_t.vehicle_id and current_setting('pdc.vehicle_restore_tombstone',true)=v_t.tombstone_id::text then return new;end if;
 if tg_op='UPDATE' then raise exception 'PDC_VEHICLE_TOMBSTONED' using errcode='55000',detail='vehicle_tombstoned';end if;
 v_source:=lower(btrim(coalesce(new.source_system,'')));
 if v_source<>'authenticated_email' then raise exception 'PDC_RECREATION_AUTHORIZATION_REQUIRED' using errcode='55000',detail='recreation_authorization_required';end if;
 -- Current authenticated-email creators are SECURITY DEFINER functions with no
 -- direct browser table writes. Bind the permission to the immutable evidence
 -- they put on the NEW row: parent source hash, attachment/evidence hash and
 -- exact intake/source record id.
 v_source_hash:=lower(btrim(coalesce(new.source_payload->>'source_hash','')));
 v_evidence_hash:=lower(btrim(coalesce(new.source_payload->>'attachment_hash',new.source_payload->>'evidence_hash','')));
 v_source_uid:=btrim(coalesce(new.source_record_id,''));
 if v_source_hash !~ '^[a-f0-9]{64}$' or v_evidence_hash !~ '^[a-f0-9]{64}$' or length(v_source_uid) not between 1 and 100 then
  raise exception 'PDC_RECREATION_AUTHORIZATION_CONFLICT' using errcode='55000',detail='recreation_evidence_missing';
 end if;
 v_digest:=encode(extensions.digest(jsonb_build_object('source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid)::text,'sha256'),'hex');
 select * into v_p from public.pdc_vehicle_recreation_permissions where tombstone_id=v_t.tombstone_id and normalized_stock=v_stock
  and intended_source_system='authenticated_email' and intended_source_hash=v_source_hash and intended_evidence_hash=v_evidence_hash
  and intended_source_uid=v_source_uid and intended_evidence_digest=v_digest and consumed_at is null order by authorized_at desc limit 1 for update;
 if not found then raise exception 'PDC_RECREATION_AUTHORIZATION_REQUIRED' using errcode='55000',detail='recreation_authorization_conflict';end if;
 if v_p.expires_at<=clock_timestamp() then raise exception 'PDC_RECREATION_AUTHORIZATION_EXPIRED' using errcode='55000',detail='recreation_authorization_expired';end if;

 update public.pdc_vehicle_recreation_permissions set consumed_at=clock_timestamp(),consumed_vehicle_id=new.id where permission_id=v_p.permission_id;
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(v_t.tombstone_id,new.id,v_stock,'recreation_consumed',v_p.authorized_by,'email-monitor',jsonb_build_object('permission_id',v_p.permission_id,'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,'source_uid',v_source_uid,'evidence_digest',v_digest));
 return new;
end $$;
revoke all on function public.pdc_vehicle_archive_recreation_gate() from public,anon,authenticated,service_role;

create or replace function public.pdc_admin_allow_vehicle_recreation_once(
 p_tombstone_id uuid,p_confirmation_stock text,p_reason text,p_source_hash text,p_evidence_hash text,p_source_uid text,p_ttl_minutes integer default 30
) returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,extensions as $$
declare s jsonb;t public.pdc_vehicle_tombstones%rowtype;p public.pdc_vehicle_recreation_permissions%rowtype;v_uid uuid;v_email text;v_source text:=lower(btrim(coalesce(p_source_hash,'')));v_evidence text:=lower(btrim(coalesce(p_evidence_hash,'')));v_source_uid text:=btrim(coalesce(p_source_uid,''));v_digest text;
begin
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;v_uid:=(s->'data'->>'actor_id')::uuid;v_email:=s->'data'->>'actor_email';
 if p_tombstone_id is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 or p_ttl_minutes not between 1 and 120
    or v_source !~ '^[a-f0-9]{64}$' or v_evidence !~ '^[a-f0-9]{64}$' or length(v_source_uid) not between 1 and 100 then return public.navision_backend_response(false,'invalid_input');end if;
 v_digest:=encode(extensions.digest(jsonb_build_object('source_hash',v_source,'evidence_hash',v_evidence,'source_uid',v_source_uid)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-tombstone:'||p_tombstone_id::text,0));select * into t from public.pdc_vehicle_tombstones where tombstone_id=p_tombstone_id for share;
 if not found or exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=t.tombstone_id and e.event_kind='restored') then return public.navision_backend_response(false,'vehicle_not_tombstoned');end if;
 -- Revalidate Administrator authority after all blocking tombstone locks. A role
 -- revoked while this call waited must not authorize recreation.
 s:=public.pdc_admin_vehicle_actor();if not coalesce((s->>'ok')::boolean,false) then return s;end if;v_uid:=(s->'data'->>'actor_id')::uuid;v_email:=s->'data'->>'actor_email';
 if p_confirmation_stock is distinct from t.normalized_stock then return public.navision_backend_response(false,'invalid_input',jsonb_build_object('detail','confirmation_stock_mismatch'));end if;
 if t.tombstone_kind<>'staging_reset' then return public.navision_backend_response(false,'manual_tombstone_restore_required');end if;
 if exists(select 1 from public.pdc_vehicle_recreation_permissions x where x.tombstone_id=t.tombstone_id and x.consumed_at is not null) then return public.navision_backend_response(false,'recreation_authorization_consumed');end if;
 insert into public.pdc_vehicle_recreation_permissions(tombstone_id,normalized_stock,authorized_by,expires_at,intended_source_hash,intended_evidence_hash,intended_source_uid,intended_evidence_digest)
 values(t.tombstone_id,t.normalized_stock,v_uid,clock_timestamp()+make_interval(mins=>p_ttl_minutes),v_source,v_evidence,v_source_uid,v_digest) returning * into p;
 insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
 values(t.tombstone_id,t.vehicle_id,t.normalized_stock,'recreation_authorized',v_uid,v_email,jsonb_build_object('permission_id',p.permission_id,'source_system','authenticated_email','source_hash',v_source,'evidence_hash',v_evidence,'source_uid',v_source_uid,'evidence_digest',v_digest,'reason',btrim(p_reason),'expires_at',p.expires_at));
 return public.navision_backend_response(true,'recreation_authorized_once',jsonb_build_object('permission_id',p.permission_id,'tombstone_id',t.tombstone_id,'expires_at',p.expires_at,'evidence_digest',v_digest));
end $$;
revoke all on function public.pdc_admin_allow_vehicle_recreation_once(uuid,text,text,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_allow_vehicle_recreation_once(uuid,text,text,text,text,text,integer) to authenticated;
revoke all on function public.pdc_admin_allow_vehicle_recreation_once(uuid,text,text,integer) from public,anon,authenticated,service_role;

-- Ensure the deferred recreation path used by current non-Navision/used
-- job-card intake stamps the exact immutable evidence tuple before the vehicle
-- trigger evaluates the one-use permission.
alter function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)
 rename to pdc_process_non_navision_jobcard_pre209;
revoke all on function public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
create function public.process_pdc_non_navision_jobcard(
 p_intake_id uuid,p_expected_source_hash text,p_extraction_hash text,p_extraction jsonb,p_actor text
) returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $$
declare v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));v_payload jsonb:=coalesce(p_extraction,'null'::jsonb);v_evidence text;v_source_uid text;
begin
 if v_source !~ '^[a-f0-9]{64}$' or p_intake_id is null or jsonb_typeof(v_payload)<>'object' then
  return public.navision_backend_response(false,'invalid_non_navision_extraction');
 end if;
 v_evidence:=lower(btrim(coalesce(v_payload->>'canonical_document_hash','')));
 v_source_uid:=p_intake_id::text;
 if v_evidence !~ '^[a-f0-9]{64}$' then return public.navision_backend_response(false,'invalid_non_navision_extraction');end if;
 perform set_config('pdc.recreation_source_hash',v_source,true);
 perform set_config('pdc.recreation_evidence_hash',v_evidence,true);
 perform set_config('pdc.recreation_source_uid',v_source_uid,true);
 return public.pdc_process_non_navision_jobcard_pre209(p_intake_id,p_expected_source_hash,p_extraction_hash,p_extraction,p_actor);
end $$;
revoke all on function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('209','vehicle_lifecycle_review_hardening',array[
 'Retire legacy mark/restore and destructive single-vehicle purge browser RPCs',
 'Remove caller-controlled tombstone kind from public archive API',
 'Bind one-time authenticated-email recreation to immutable vehicle source/evidence metadata',
 'Stamp exact retained job-card evidence into transaction-local recreation context',
 'Require exact numeric migration head 208 before install'
]);
commit;
