-- Guarded rollback for staging-only migration 126.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-126-bulk-workbook-preview-performance',0));
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'PDC_BULK_126_ROLLBACK_STAGING_SENTINEL_MISMATCH';
  end if;
  if exists(select 1 from public.pdc_bulk_workbook_previews)
     or exists(select 1 from public.pdc_bulk_workbook_apply_receipts) then
    raise exception 'PDC_BULK_126_ROLLBACK_PREVIEW_ACTIVITY_PRESENT_RECOVERY_REQUIRED';
  end if;
end;
$guard$;

create or replace function public.preview_pdc_bulk_jc_stock_workbook(p_workbook_sha256 text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $preview$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_sha text:=lower(btrim(coalesce(p_workbook_sha256,'')));
  v_payload jsonb:=coalesce(p_payload,'null'::jsonb); v_payload_sha text; v_auth public.pdc_bulk_workbook_authorizations%rowtype; v_existing_preview public.pdc_bulk_workbook_previews%rowtype;
  v_preview_id uuid:=gen_random_uuid(); v_row jsonb; v_row_no integer; v_jc text; v_stock text; v_reason text;
  v_exact integer; v_stock_count integer; v_jc_count integer; v_oper_exact integer; v_oper_partial integer; v_bound integer; v_ops integer;
  v_rows integer; v_operation_count integer; v_accepted integer:=0; v_quarantine integer:=0; v_operation_quarantine integer:=0;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_sha !~ '^[a-f0-9]{64}$' or jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) not between 1 and 500 then
    return public.navision_backend_response(false,'invalid_workbook_payload');
  end if;
  if exists(select 1 from jsonb_array_elements(v_payload) r where jsonb_typeof(r)<>'object'
    or not (r ?& array['row_no','job_card_number','stock_number','operations'])
    or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['row_no','job_card_number','stock_number','vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','operations']))
    or jsonb_typeof(r->'row_no')<>'number' or coalesce(r->>'row_no','') !~ '^[1-9][0-9]{0,5}$'
    or length(coalesce(r->>'job_card_number','')) not between 1 and 60 or r->>'job_card_number' is distinct from btrim(r->>'job_card_number') or r->>'job_card_number' ~ '[[:cntrl:]]'
    or length(coalesce(r->>'stock_number','')) not between 1 and 80 or r->>'stock_number' is distinct from btrim(r->>'stock_number') or r->>'stock_number' ~ '[[:cntrl:]]' or not public.is_real_vehicle_stock_number(r->>'stock_number')
    or exists(select 1 from jsonb_each(r) e where e.key in ('vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale') and jsonb_typeof(e.value) not in ('string','null'))
    or length(coalesce(r->>'vin',''))>80 or coalesce(r->>'vin','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'customer_name',''))>180 or coalesce(r->>'customer_name','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'vehicle_description',''))>180 or coalesce(r->>'vehicle_description','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'registration',''))>40 or coalesce(r->>'registration','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'salesperson_reference',''))>120 or coalesce(r->>'salesperson_reference','') ~ '[[:cntrl:]]'
    or (coalesce(r->>'eta_to_kewdale','')<>'' and coalesce(r->>'eta_to_kewdale','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
    or jsonb_typeof(r->'operations')<>'array' or jsonb_array_length(r->'operations') not between 1 and 100
    or exists(select 1 from jsonb_array_elements(r->'operations') o where jsonb_typeof(o)<>'object'
      or (select array_agg(k order by k) from jsonb_object_keys(o) k) is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
      or coalesce(o->>'operation_no','') !~ '^OP(00[1-9]|0[1-9][0-9]|100)$'
      or not ((o->'work_key')='null'::jsonb or (jsonb_typeof(o->'work_key')='string' and o->>'work_key' in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','PARTS')))
      or length(coalesce(o->>'description','')) not between 1 and 180 or o->>'description' is distinct from btrim(o->>'description') or o->>'description' ~ '[[:cntrl:]]'
      or jsonb_typeof(o->'estimated_hours') not in ('number','null')
      or (jsonb_typeof(o->'estimated_hours')='number' and coalesce(o->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
      or (jsonb_typeof(o->'estimated_hours')='null' and o->>'estimated_hours_source' is not null)
      or (jsonb_typeof(o->'estimated_hours')='number' and ((o->>'estimated_hours')::numeric<0 or (o->>'estimated_hours')::numeric>999.99 or mod((o->>'estimated_hours')::numeric,0.01)<>0))
    ) or (select count(*) from jsonb_array_elements(r->'operations'))<>(select count(distinct o->>'operation_no') from jsonb_array_elements(r->'operations') o)
  ) then return public.navision_backend_response(false,'invalid_row_or_operation'); end if;
  if jsonb_array_length(v_payload)<>(select count(distinct (r->>'row_no')::integer) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_row'); end if;
  if jsonb_array_length(v_payload)<>(select count(distinct upper(btrim(r->>'job_card_number'))||'|'||public.normalize_vehicle_stock_number(r->>'stock_number')) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_jc_stock_pair'); end if;
  v_rows:=jsonb_array_length(v_payload);
  select sum(jsonb_array_length(r->'operations')) into v_operation_count from jsonb_array_elements(v_payload) r;
  v_payload_sha:=public.pdc_bulk_workbook_canonical_payload_sha256(v_payload);
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-preview:'||v_uid::text,0));
  select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.workbook_sha256=v_sha and a.expected_pair_count=v_rows and a.expected_operation_count=v_operation_count and a.status='available' and a.expires_at>clock_timestamp() order by a.created_at desc limit 1 for update;
  if not found then
    select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.workbook_sha256=v_sha and a.claimed_payload_sha256=v_payload_sha and a.status in ('claimed','applied') order by a.created_at desc limit 1;
    if not found then return public.navision_backend_response(false,'authorization_not_available_or_count_mismatch'); end if;
    select * into strict v_existing_preview from public.pdc_bulk_workbook_previews where preview_id=v_auth.claimed_preview_id and actor_id=v_uid;
    return public.navision_backend_response(true,'exact_preview_replay',jsonb_build_object(
      'preview_id',v_auth.claimed_preview_id,'authorization_id',v_auth.authorization_id,
      'workbook_sha256',v_sha,'payload_sha256',v_payload_sha,
      'row_count',v_existing_preview.row_count,'operation_count',v_existing_preview.operation_count,
      'accepted_count',v_existing_preview.accepted_count,'quarantine_count',v_existing_preview.quarantine_count,
      'operation_quarantine_count',v_existing_preview.operation_quarantine_count,
      'blocked_count',v_existing_preview.blocked_count,'applyable',v_existing_preview.accepted_count>0));
  end if;
  create temporary table pg_temp.pdc_bulk_classification(row_no integer primary key,jc text,stock text,reason text,op_quarantine integer,row_payload jsonb) on commit drop;
  for v_row in select value from jsonb_array_elements(v_payload) loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number')); v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number'); v_ops:=jsonb_array_length(v_row->'operations');
    select count(*) into v_exact from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_stock_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) into v_jc_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_oper_exact from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
    select count(*) into v_oper_partial from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc) or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock));
    select count(*) into v_bound
    from public.navision_backend_records r
    join public.navision_board_activations a on a.backend_record_id=r.id and a.active and a.completed_at is null
    join public.vehicles v on v.id=a.canonical_vehicle_id and v.deleted_at is null and v.lifecycle_state='active'
    where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
      and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock
      and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc
      and public.normalize_vehicle_stock_number(v.stock_number)=v_stock
      and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
    v_reason:=null;
    if exists(select 1 from jsonb_array_elements(v_row->'operations') o where o->'work_key'='null'::jsonb) then v_reason:='missing_authoritative_work_key';
    elsif v_exact=1 and v_stock_count=1 and v_jc_count=1 and v_bound=1 and v_oper_exact=1 and v_oper_partial=0 then v_accepted:=v_accepted+1;
    elsif v_exact=1 and v_stock_count=1 and v_jc_count=1 then v_reason:='operational_identity_conflict';
    elsif v_exact>1 or v_stock_count>1 or v_jc_count>1 then v_reason:='multiple_current_identity_matches';
    elsif v_stock_count>0 or v_jc_count>0 then v_reason:='partial_identity_disagreement';
    elsif v_oper_partial>0 then v_reason:='operational_identity_conflict';
    elsif v_oper_exact=1 then v_reason:='operational_exact_without_current_navision';
    else v_reason:='no_current_match'; end if;
    if v_reason is not null then v_quarantine:=v_quarantine+1; v_operation_quarantine:=v_operation_quarantine+v_ops; end if;
    insert into pg_temp.pdc_bulk_classification values(v_row_no,v_jc,v_stock,v_reason,case when v_reason is null then 0 else v_ops end,v_row);
  end loop;
  insert into public.pdc_bulk_workbook_previews(preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,preview_payload,row_count,operation_count,accepted_count,quarantine_count,operation_quarantine_count,blocked_count)
  values(v_preview_id,v_auth.authorization_id,v_uid,v_sha,v_payload_sha,v_payload,v_rows,v_operation_count,v_accepted,v_quarantine,v_operation_quarantine,0);
  insert into public.pdc_bulk_workbook_quarantine(preview_id,row_no,job_card_number,stock_number,reason_code,operation_quarantine_count,row_payload)
  select v_preview_id,row_no,jc,stock,reason,op_quarantine,row_payload from pg_temp.pdc_bulk_classification where reason is not null order by row_no;
  update public.pdc_bulk_workbook_authorizations set claimed_at=clock_timestamp(),claimed_payload_sha256=v_payload_sha,claimed_preview_id=v_preview_id,status='claimed' where authorization_id=v_auth.authorization_id and status='available';
  if not found then raise exception 'pdc_bulk_workbook_authorization_claim_race' using errcode='40001'; end if;
  return public.navision_backend_response(true,'preview_ready',jsonb_build_object('preview_id',v_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_sha,'payload_sha256',v_payload_sha,'row_count',v_rows,'operation_count',v_operation_count,'accepted_count',v_accepted,'quarantine_count',v_quarantine,'operation_quarantine_count',v_operation_quarantine,'blocked_count',0,'applyable',v_accepted>0));
end;
$preview$;

delete from supabase_migrations.schema_migrations where version='126' and name='short_circuit_bulk_workbook_work_authority_quarantine';
commit;
