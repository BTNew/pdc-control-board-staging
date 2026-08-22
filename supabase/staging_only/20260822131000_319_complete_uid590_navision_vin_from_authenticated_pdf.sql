begin;
do $guard$ declare p text;begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_319_PRODUCTION_SENTINEL_PRESENT';end if;
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_319_STAGING_GUARD_FAILED';end if;
 select project_ref into p from public.pdc_staging_environment_sentinel where singleton;
 if p is distinct from 'cdsmnqxtyyoeoznmbidd' then raise exception 'PDC_319_PROJECT_MISMATCH';end if;
end $guard$;
create table public.pdc_uid590_vin_completion_319(
 receipt_id uuid primary key default gen_random_uuid(),backend_record_id uuid not null unique references public.navision_backend_records(id) on delete restrict,
 vehicle_id uuid not null unique references public.vehicles(id) on delete restrict,intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
 attachment_id uuid not null unique references public.ai_email_attachments(id) on delete restrict,partial_vin text not null check(partial_vin='MABAV402403845'),
 completed_vin text not null check(completed_vin='MR0MABAV402403845'),evidence jsonb not null,receipt_hash text not null unique check(receipt_hash~'^[a-f0-9]{64}$'),
 completed_by uuid not null references auth.users(id) on delete restrict,completed_at timestamptz not null default clock_timestamp());
revoke all on table public.pdc_uid590_vin_completion_319 from public,anon,authenticated,service_role;
create or replace function public.pdc_uid590_vin_completion_immutable_319() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$begin raise exception 'PDC_319_RECEIPT_IMMUTABLE' using errcode='55000';end$$;
revoke all on function public.pdc_uid590_vin_completion_immutable_319() from public,anon,authenticated,service_role;
create trigger pdc_uid590_vin_completion_319_immutable before update or delete on public.pdc_uid590_vin_completion_319 for each row execute function public.pdc_uid590_vin_completion_immutable_319();
do $repair$ declare a uuid;e text;b public.navision_backend_records%rowtype;v public.vehicles%rowtype;i public.ai_email_intake%rowtype;att public.ai_email_attachments%rowtype;ev jsonb;h text;begin
 select auth_user_id,lower(email) into a,e from public.pdc_user_roles where role='administrator' and active and account_status='approved' and lower(email)='craig.watson@broometoyota.com.au' limit 1;
 if a is null then raise exception 'PDC_319_OWNER_ADMIN_MISSING';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email',e)::text,true);
 perform pg_advisory_xact_lock(hashtextextended('pdc:uid590-vin-completion-319',0));
 select * into b from public.navision_backend_records where id='9bb43a07-9d01-442f-bb04-780a3bdce0aa' for update;
 select * into v from public.vehicles where id='5ad6f5e2-674c-5bd0-af02-b5a8f25fdfce' for update;
 select * into i from public.ai_email_intake where id='9095b557-9ddf-4f6f-9d21-a5fa419c54e3' for update;
 select * into att from public.ai_email_attachments where id='5149bfc9-ab29-472c-9bcb-73b0315ba8b6' for share;
 if b.id is null or b.version<>9 or not b.is_current or b.record_status<>'current' or b.canonical_vehicle_id<>v.id or b.dealer_code<>'14450'
   or b.normalized_data->>'vin'<>'MABAV402403845' or coalesce(b.normalized_data->>'wmi','')<>'' or b.normalized_data->>'vdsNumber'<>'MABAV4' or b.normalized_data->>'frame'<>'02403845'
   or v.id is null or v.version<>15 or v.lifecycle_state<>'active' or v.deleted_at is not null or v.stock_number_normalized<>'13018324' or v.vin is not null
   or i.id is null or i.provider_uid<>'imap_uid:590' or i.source_hash<>'2855bcf0ea006fd314f4b5d9bbf6b87eb3724e66710f94041529f24c244384b1' or i.status<>'received'
   or att.id is null or att.source_hash<>'06b774775084520591d15de6aef40fbb4d7c0ee99015f5242cc1daa7d9f5dbd1'
   or position('MR0MABAV402403845' in coalesce(att.extracted_text,''))=0
 then raise exception 'PDC_319_EXACT_PRECONDITION_FAILED';end if;
 if exists(select 1 from public.vehicles x where x.id<>v.id and x.vin_normalized='MR0MABAV402403845') then raise exception 'PDC_319_VIN_CONFLICT';end if;
 ev:=jsonb_build_object('contract','uid590_vin_completion_319','provider_uid','imap_uid:590','intake_id',i.id,'attachment_id',att.id,'parent_source_hash',i.source_hash,'attachment_source_hash',att.source_hash,'backend_before',to_jsonb(b),'vehicle_before',to_jsonb(v),'authenticated_pdf_full_vin','MR0MABAV402403845','navision_vds_frame','MABAV402403845');
 h:=encode(extensions.digest(convert_to(ev::text,'UTF8'),'sha256'),'hex');
 insert into public.pdc_uid590_vin_completion_319(backend_record_id,vehicle_id,intake_id,attachment_id,partial_vin,completed_vin,evidence,receipt_hash,completed_by)
 values(b.id,v.id,i.id,att.id,'MABAV402403845','MR0MABAV402403845',ev,h,a);
 update public.navision_backend_records set normalized_data=jsonb_set(jsonb_set(normalized_data,'{vin}','"MR0MABAV402403845"'::jsonb,true),'{wmi}','"MR0"'::jsonb,true),version=version+1,updated_at=clock_timestamp() where id=b.id;
 insert into public.navision_backend_audit(action,backend_record_id,canonical_vehicle_id,revision,evidence,actor_id,actor_email)
 values('canonical_link',b.id,v.id,(select revision from public.navision_backend_revision where singleton),ev||jsonb_build_object('receipt_hash',h),a,e);
 update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 if (select normalized_data->>'vin' from public.navision_backend_records where id=b.id)<>'MR0MABAV402403845' then raise exception 'PDC_319_POSTCONDITION_FAILED';end if;
end $repair$;
insert into supabase_migrations.schema_migrations(version,name,statements) values('20260822131000','319_complete_uid590_navision_vin_from_authenticated_pdf',array['exact UID590 authenticated WMI/VIN completion']) on conflict(version) do nothing;
commit;
