-- Staging-only migration 095: exact-idempotency fast path for authenticated operation replays.
-- The 093 importer remains the sole mutation implementation, renamed to an internal function.
-- Exact replays return before any no-op work/parts statements can bump shared revisions.
begin;
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regprocedure('public.import_pdc_authenticated_email_operations(text,text,jsonb)') is null then
    raise exception 'PDC_MIGRATION_095_STAGING_OR_DEPENDENCY_MISMATCH';
  end if;
end;
$guard$;

alter function public.import_pdc_authenticated_email_operations(text,text,jsonb)
  rename to import_pdc_authenticated_email_operations_093_internal;
revoke all on function public.import_pdc_authenticated_email_operations_093_internal(text,text,jsonb)
  from public,anon,authenticated;

create function public.import_pdc_authenticated_email_operations(
  p_source_hash text,
  p_source_uid text,
  p_operation_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $wrapper$
declare
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_source_uid text:=btrim(coalesce(p_source_uid,''));
  v_operations jsonb:=coalesce(p_operation_lines,'[]'::jsonb);
  v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_existing integer:=0;
  v_resulting_revision bigint;
begin
  if not public.pdc_monitor_staging_guard() or v_actor_id is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.email=v_actor_email and (r.auth_user_id is null or r.auth_user_id=v_actor_id)
     and r.role='viewer' and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  if v_source_hash !~ '^[a-f0-9]{64}$'
     or length(v_source_uid) not between 1 and 100
     or jsonb_typeof(v_operations) is distinct from 'array'
     or jsonb_array_length(v_operations)>50
     or exists(
       select 1 from jsonb_array_elements(v_operations) x
       where jsonb_typeof(x)<>'object'
          or (select array_agg(k order by k) from jsonb_object_keys(x) k)
             is distinct from array['description','operation_no','work_key']::text[]
          or coalesce(x->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$'
          or coalesce(x->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
          or length(coalesce(x->>'description','')) not between 1 and 180
          or x->>'description' is distinct from btrim(x->>'description')
          or x->>'description' ~ '[[:cntrl:]]'
     )
     or (select count(*) from jsonb_array_elements(v_operations))
        <> (select count(distinct x->>'operation_no') from jsonb_array_elements(v_operations) x) then
    return public.navision_backend_response(false,'invalid_operation_lines');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-operation-lines:'||v_source_hash,0));
  select * into v_receipt from public.pdc_authenticated_email_import_receipts
   where actor_id=v_actor_id and source_hash=v_source_hash for update;
  if not found or v_receipt.source_uid<>v_source_uid then
    return public.navision_backend_response(false,'source_receipt_not_found');
  end if;
  perform 1 from public.vehicles v
   where v.id=v_receipt.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null for update;
  if not found then return public.navision_backend_response(false,'operational_vehicle_inactive'); end if;

  select count(*) into v_existing
  from jsonb_array_elements(v_operations) x
  where exists(
    select 1 from public.pdc_authenticated_email_operation_lines ol
    where ol.source_hash=v_source_hash
      and ol.operation_no=x->>'operation_no'
      and ol.operation_fingerprint=encode(extensions.digest(jsonb_build_object(
        'source_hash',v_source_hash,'operation_no',x->>'operation_no',
        'work_key',x->>'work_key','description',x->>'description'
      )::text,'sha256'),'hex')
  );
  if v_existing=jsonb_array_length(v_operations) then
    select revision into v_resulting_revision from public.pdc_email_vehicle_revision where singleton;
    return public.navision_backend_response(true,'operation_lines_already_imported',jsonb_build_object(
      'vehicle_id',v_receipt.vehicle_id,'source_hash',v_source_hash,
      'operation_lines_received',jsonb_array_length(v_operations),'operation_lines_added',0,
      'required_work_added',0,'parts_required_added',0,
      'resulting_revision',v_resulting_revision,'booking_created',false));
  end if;

  return public.import_pdc_authenticated_email_operations_093_internal(
    v_source_hash,v_source_uid,v_operations
  );
end;
$wrapper$;
revoke all on function public.import_pdc_authenticated_email_operations(text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.import_pdc_authenticated_email_operations(text,text,jsonb)
  to authenticated;
comment on function public.import_pdc_authenticated_email_operations(text,text,jsonb) is
  'Staging-only typed wrapper: exact authenticated job-card replays return before any mutation statement; partial/new evidence delegates to the bounded 093 importer.';
commit;
