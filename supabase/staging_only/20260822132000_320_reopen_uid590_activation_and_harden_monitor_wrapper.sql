begin;
do $guard$ declare p text;begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_320_PRODUCTION_SENTINEL_PRESENT';end if;
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_320_STAGING_GUARD_FAILED';end if;
 select project_ref into p from public.pdc_staging_environment_sentinel where singleton;
 if p is distinct from 'cdsmnqxtyyoeoznmbidd' then raise exception 'PDC_320_PROJECT_MISMATCH';end if;
end $guard$;
create table public.pdc_uid590_activation_reopen_320(
 receipt_id uuid primary key default gen_random_uuid(),backend_record_id uuid not null unique references public.navision_backend_records(id) on delete restrict,
 vehicle_id uuid not null unique references public.vehicles(id) on delete restrict,intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
 activation_before jsonb not null,receipt_hash text not null unique check(receipt_hash~'^[a-f0-9]{64}$'),reopened_by uuid not null references auth.users(id) on delete restrict,
 reopened_at timestamptz not null default clock_timestamp());
revoke all on table public.pdc_uid590_activation_reopen_320 from public,anon,authenticated,service_role;
create or replace function public.pdc_uid590_activation_reopen_immutable_320() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$begin raise exception 'PDC_320_RECEIPT_IMMUTABLE' using errcode='55000';end$$;
revoke all on function public.pdc_uid590_activation_reopen_immutable_320() from public,anon,authenticated,service_role;
create trigger pdc_uid590_activation_reopen_320_immutable before update or delete on public.pdc_uid590_activation_reopen_320 for each row execute function public.pdc_uid590_activation_reopen_immutable_320();
do $repair$ declare a uuid;e text;act public.navision_board_activations%rowtype;b public.navision_backend_records%rowtype;v public.vehicles%rowtype;i public.ai_email_intake%rowtype;ev jsonb;h text;begin
 select auth_user_id,lower(email) into a,e from public.pdc_user_roles where role='administrator' and active and account_status='approved' and lower(email)='craig.watson@broometoyota.com.au' limit 1;
 if a is null then raise exception 'PDC_320_OWNER_ADMIN_MISSING';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email',e)::text,true);
 perform pg_advisory_xact_lock(hashtextextended('pdc:uid590-activation-reopen-320',0));
 select * into act from public.navision_board_activations where backend_record_id='9bb43a07-9d01-442f-bb04-780a3bdce0aa' for update;
 select * into b from public.navision_backend_records where id=act.backend_record_id for share;
 select * into v from public.vehicles where id='5ad6f5e2-674c-5bd0-af02-b5a8f25fdfce' for share;
 select * into i from public.ai_email_intake where id='9095b557-9ddf-4f6f-9d21-a5fa419c54e3' for update;
 if act.backend_record_id is null or act.canonical_vehicle_id<>v.id or act.activation_source<>'manual' or act.activated_stock_number<>'13018324' or not act.active
   or act.completed_at<>'2026-08-17T12:58:05.543881+00:00'::timestamptz or act.completion_reason<>'Overnight staging page clear' or act.completed_by is not null or act.completed_by_email is not null
   or b.id is null or b.version<>10 or b.normalized_data->>'vin'<>'MR0MABAV402403845' or b.canonical_vehicle_id<>v.id or not b.is_current or b.record_status<>'current'
   or v.id is null or v.version<>16 or v.lifecycle_state<>'active' or v.deleted_at is not null or not v.visible_on_board or v.vin_normalized<>'MR0MABAV402403845'
   or i.id is null or i.provider_uid<>'imap_uid:590' or i.status<>'received' or i.permanent_failure
 then raise exception 'PDC_320_EXACT_PRECONDITION_FAILED';end if;
 ev:=jsonb_build_object('contract','uid590_activation_reopen_320','provider_uid','imap_uid:590','intake_id',i.id,'backend_record_id',b.id,'vehicle_id',v.id,'activation_before',to_jsonb(act),'reason','Reverse only the Overnight staging page clear completion marker; no physical completion asserted');
 h:=encode(extensions.digest(convert_to(ev::text,'UTF8'),'sha256'),'hex');
 insert into public.pdc_uid590_activation_reopen_320(backend_record_id,vehicle_id,intake_id,activation_before,receipt_hash,reopened_by) values(b.id,v.id,i.id,to_jsonb(act),h,a);
 update public.navision_board_activations set completed_at=null,completion_reason=null,completed_by=null,completed_by_email=null,updated_at=clock_timestamp() where backend_record_id=act.backend_record_id;
 insert into public.navision_backend_audit(action,backend_record_id,canonical_vehicle_id,revision,evidence,actor_id,actor_email)
 values('board_activate',b.id,v.id,(select revision from public.navision_backend_revision where singleton),ev||jsonb_build_object('receipt_hash',h),a,e);
 update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 if exists(select 1 from public.navision_board_activations where backend_record_id=b.id and completed_at is not null) then raise exception 'PDC_320_ACTIVATION_POSTCONDITION_FAILED';end if;
end $repair$;

create or replace function public.import_pdc_monitor_jobcard_attachment_279(p_gateway_instance_id text,p_intake_id uuid,p_attachment_id uuid,p_expected_parent_hash text,p_expected_attachment_hash text,p_authentication jsonb,p_email_vehicle jsonb,p_required_work jsonb,p_operation_lines jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,auth as $wrapper$
declare s jsonb:=public.pdc_monitor_actor_scope();a uuid;r jsonb;begin
 if not coalesce((s->>'ok')::boolean,false) then return public.navision_backend_response(false,'monitor_scope_required');end if;
 a:=nullif(s->>'user_id','')::uuid;
 if a is null or not exists(select 1 from public.pdc_monitor_runtime_bindings_255 b where b.singleton and b.actor_id=a and b.gateway_instance_id=btrim(coalesce(p_gateway_instance_id,''))) then return public.navision_backend_response(false,'monitor_runtime_binding_required');end if;
 r:=public.import_pdc_jobcard_attachment_canonical(p_intake_id,p_attachment_id,p_expected_parent_hash,p_expected_attachment_hash,p_authentication,p_email_vehicle,p_required_work,p_operation_lines);
 if coalesce((r->>'ok')::boolean,false) and r->>'code'<>'jobcard_attachment_receipt' then
  return public.navision_backend_response(false,'monitor_nonreceipt_success_rejected');
 end if;
 return r;
end $wrapper$;
revoke all on function public.import_pdc_monitor_jobcard_attachment_279(text,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_monitor_jobcard_attachment_279(text,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('20260822132000','320_reopen_uid590_activation_and_harden_monitor_wrapper',array['exact UID590 overnight-clear activation reopen','Monitor wrapper rejects non-receipt success envelopes']) on conflict(version) do nothing;
commit;
