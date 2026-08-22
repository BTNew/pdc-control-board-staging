begin;

-- Exact staging-only recovery for Craig's two authenticated 22-August emails.
do $guard$
declare v_project text;begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_318_PRODUCTION_SENTINEL_PRESENT';end if;
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_318_STAGING_GUARD_FAILED';end if;
 select project_ref into v_project from public.pdc_staging_environment_sentinel where singleton;
 if v_project is distinct from 'cdsmnqxtyyoeoznmbidd' then raise exception 'PDC_318_PROJECT_MISMATCH';end if;
end $guard$;

create table if not exists public.pdc_uid590_591_exact_reinstatements_318(
 receipt_id uuid primary key default gen_random_uuid(),
 provider_uid text not null unique check(provider_uid in('imap_uid:590','imap_uid:591')),
 intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
 attachment_id uuid not null unique references public.ai_email_attachments(id) on delete restrict,
 parent_source_hash text not null check(parent_source_hash~'^[a-f0-9]{64}$'),
 attachment_source_hash text not null check(attachment_source_hash~'^[a-f0-9]{64}$'),
 stock_number text not null check(stock_number in('13018324','13001466')),
 job_card_number text not null check(job_card_number in('J139125160','J139125226')),
 vehicle_id uuid not null unique references public.vehicles(id) on delete restrict,
 backend_record_id uuid not null unique references public.navision_backend_records(id) on delete restrict,
 vehicle_before jsonb not null,
 backend_before jsonb not null,
 intake_before jsonb not null,
 receipt_hash text not null unique check(receipt_hash~'^[a-f0-9]{64}$'),
 reinstated_by uuid not null references auth.users(id) on delete restrict,
 reinstated_at timestamptz not null default clock_timestamp()
);
revoke all on table public.pdc_uid590_591_exact_reinstatements_318 from public,anon,authenticated,service_role;
create or replace function public.pdc_uid590_591_reinstatement_immutable_318()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $immutable$
begin raise exception 'PDC_318_REINSTATEMENT_RECEIPT_IMMUTABLE' using errcode='55000';end $immutable$;
revoke all on function public.pdc_uid590_591_reinstatement_immutable_318() from public,anon,authenticated,service_role;
drop trigger if exists pdc_uid590_591_exact_reinstatements_318_immutable on public.pdc_uid590_591_exact_reinstatements_318;
create trigger pdc_uid590_591_exact_reinstatements_318_immutable before update or delete on public.pdc_uid590_591_exact_reinstatements_318
for each row execute function public.pdc_uid590_591_reinstatement_immutable_318();

do $repair$
declare
 a uuid;e text;r record;v public.vehicles%rowtype;b public.navision_backend_records%rowtype;i public.ai_email_intake%rowtype;att public.ai_email_attachments%rowtype;
 before_v jsonb;before_b jsonb;before_i jsonb;after_v jsonb;h text;expected_version integer;expected_vin text;expected_location text;
begin
 select auth_user_id,lower(email) into a,e from public.pdc_user_roles
 where role='administrator' and active and account_status='approved' and lower(email)='craig.watson@broometoyota.com.au' limit 1;
 if a is null then raise exception 'PDC_318_OWNER_ADMIN_MISSING';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email',e)::text,true);

 for r in select * from (values
  ('imap_uid:590'::text,'9095b557-9ddf-4f6f-9d21-a5fa419c54e3'::uuid,'5149bfc9-ab29-472c-9bcb-73b0315ba8b6'::uuid,
   '2855bcf0ea006fd314f4b5d9bbf6b87eb3724e66710f94041529f24c244384b1'::text,'06b774775084520591d15de6aef40fbb4d7c0ee99015f5242cc1daa7d9f5dbd1'::text,
   '13018324'::text,'J139125160'::text,'MR0MABAV402403845'::text,'5ad6f5e2-674c-5bd0-af02-b5a8f25fdfce'::uuid,'9bb43a07-9d01-442f-bb04-780a3bdce0aa'::uuid,14,'14450'::text),
  ('imap_uid:591'::text,'0b4339a0-ae16-4d64-8bba-33fd2ef2d798'::uuid,'fd2b3adf-4244-4c32-b5b9-7789cd579e3e'::uuid,
   '7262ecf1ac518027d8580f69b18b7f75233c5ecc37823fe8944162b9bebf55f5'::text,'4ae184210b5be5a368b5640c1484fb7b5555078773f09d7c2b4b420add7142e7'::text,
   '13001466'::text,'J139125226'::text,'MR0PEBHV000401108'::text,'19b74592-f41a-515c-bf61-46d06b8667ed'::uuid,'cb81e3a9-d6da-4562-a0f6-23553d540293'::uuid,13,'37047'::text)
 )x(provider_uid,intake_id,attachment_id,parent_hash,attachment_hash,stock,job_card,vin,vehicle_id,backend_id,vehicle_version,dealer_code)
 loop
  if exists(select 1 from public.pdc_uid590_591_exact_reinstatements_318 z where z.provider_uid=r.provider_uid) then
   continue;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc:uid590-591:318:'||r.provider_uid,0));
  select * into i from public.ai_email_intake where id=r.intake_id for update;
  select * into att from public.ai_email_attachments where id=r.attachment_id and intake_id=r.intake_id for share;
  select * into v from public.vehicles where id=r.vehicle_id for update;
  select * into b from public.navision_backend_records where id=r.backend_id for update;
  if i.id is null or i.provider_uid is distinct from r.provider_uid or lower(i.recipient_mailbox)<>'pmbcontroller@gmail.com'
    or i.source_hash is distinct from r.parent_hash or i.provider_authserv_id<>'mx.google.com'
    or i.provider_authentication->>'gmail_authentication_results'<>'true'
    or not(i.provider_authentication->>'spf_aligned'='true' or i.provider_authentication->>'dmarc_aligned'='true')
    or att.id is null or att.source_hash is distinct from r.attachment_hash or lower(att.content_type)<>'application/pdf'
    or v.id is null or v.version<>r.vehicle_version or v.stock_number_normalized<>r.stock or v.job_card_number<>r.job_card
    or v.lifecycle_state<>'deleted' or v.visible_on_board or v.deleted_at is null or v.deleted_reason<>'Overnight staging page clear'
    or b.id is null or b.is_current is distinct from true or b.record_status<>'current' or b.source_system<>'microsoft_navision' or b.dealer_code<>r.dealer_code
    or public.normalize_vehicle_stock_number(b.normalized_data->>'stock')<>r.stock
  then raise exception 'PDC_318_EXACT_PRECONDITION_FAILED:%',r.provider_uid;end if;
  if r.provider_uid='imap_uid:591' and public.normalize_vehicle_vin(b.normalized_data->>'vin')<>public.normalize_vehicle_vin(r.vin) then raise exception 'PDC_318_UID591_VIN_MISMATCH';end if;
  if r.provider_uid='imap_uid:590' and upper(coalesce(b.normalized_data->>'vdsNumber',''))||upper(coalesce(b.normalized_data->>'frame',''))<>'MABAV402403845' then raise exception 'PDC_318_UID590_VDS_FRAME_MISMATCH';end if;
  if exists(select 1 from public.vehicles q where q.id<>v.id and q.lifecycle_state='active' and q.deleted_at is null and (q.stock_number_normalized=r.stock or q.vin_normalized=public.normalize_vehicle_vin(r.vin))) then raise exception 'PDC_318_IDENTITY_CONFLICT:%',r.provider_uid;end if;
  if exists(select 1 from public.pdc_jobcard_attachment_import_receipts q where q.intake_id=i.id or q.attachment_id=att.id) then raise exception 'PDC_318_TERMINAL_RECEIPT_ALREADY_EXISTS:%',r.provider_uid;end if;
  expected_location:=public.navision_operational_location(b.normalized_data);
  if expected_location not in('PMB','YH','IT','Other') then raise exception 'PDC_318_LOCATION_INVALID:%',r.provider_uid;end if;
  before_v:=to_jsonb(v);before_b:=to_jsonb(b);before_i:=to_jsonb(i);
  h:=encode(extensions.digest(convert_to(jsonb_build_object('contract','uid590_591_exact_reinstatement_318','provider_uid',r.provider_uid,'intake_id',r.intake_id,'attachment_id',r.attachment_id,'parent_hash',r.parent_hash,'attachment_hash',r.attachment_hash,'stock',r.stock,'job_card',r.job_card,'vin',r.vin,'vehicle_id',r.vehicle_id,'backend_id',r.backend_id,'vehicle_before',before_v,'backend_before',before_b,'intake_before',before_i)::text,'UTF8'),'sha256'),'hex');
  insert into public.pdc_uid590_591_exact_reinstatements_318(provider_uid,intake_id,attachment_id,parent_source_hash,attachment_source_hash,stock_number,job_card_number,vehicle_id,backend_record_id,vehicle_before,backend_before,intake_before,receipt_hash,reinstated_by)
  values(r.provider_uid,r.intake_id,r.attachment_id,r.parent_hash,r.attachment_hash,r.stock,r.job_card,r.vehicle_id,r.backend_id,before_v,before_b,before_i,h,a);
  update public.vehicles set lifecycle_state='active',visible_on_board=true,current_location=expected_location,deleted_at=null,deleted_reason=null,board_purged_at=null,board_purge_reason=null,board_purged_by=null,version=version+1,updated_by=a,updated_at=clock_timestamp() where id=v.id returning to_jsonb(public.vehicles.*) into after_v;
  update public.navision_backend_records set canonical_vehicle_id=v.id,version=version+1,updated_at=clock_timestamp() where id=b.id;
  update public.ai_email_intake set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,last_error_code=null,error_details=null,processing_result='{}'::jsonb,updated_at=clock_timestamp() where id=i.id;
  perform public.audit_pdc_event('restore','vehicles',v.id,v.id,before_v,after_v,jsonb_build_object('contract','uid590_591_exact_reinstatement_318','provider_uid',r.provider_uid,'intake_id',r.intake_id,'attachment_id',r.attachment_id,'receipt_hash',h,'same_uuid',true,'duplicate_vehicle_created',false,'backend_record_id',b.id,'email_retry_requeued',true));
 end loop;
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 update public.navision_backend_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 perform public.workshop_bump_revision();
 if (select count(*) from public.pdc_uid590_591_exact_reinstatements_318)<>2 then raise exception 'PDC_318_RECEIPT_COUNT_FAILED';end if;
 if exists(select 1 from public.vehicles where id in('5ad6f5e2-674c-5bd0-af02-b5a8f25fdfce','19b74592-f41a-515c-bf61-46d06b8667ed') and (lifecycle_state<>'active' or deleted_at is not null or not visible_on_board)) then raise exception 'PDC_318_VEHICLE_POSTCONDITION_FAILED';end if;
 if (select count(*) from public.ai_email_intake where id in('9095b557-9ddf-4f6f-9d21-a5fa419c54e3','0b4339a0-ae16-4d64-8bba-33fd2ef2d798') and status='received' and not permanent_failure)<>2 then raise exception 'PDC_318_REQUEUE_POSTCONDITION_FAILED';end if;
end $repair$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260822130000','318_reinstate_uid590_591_exact_archived_vehicles',array['exact staging UID590/591 same-UUID reinstatement and retry requeue'])
on conflict(version) do nothing;
commit;
