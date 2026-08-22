begin;
do $guard$ declare p text;c integer;begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_322_PRODUCTION_SENTINEL_PRESENT';end if;
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_322_STAGING_GUARD_FAILED';end if;
 select project_ref into p from public.pdc_staging_environment_sentinel where singleton;
 if p is distinct from 'cdsmnqxtyyoeoznmbidd' then raise exception 'PDC_322_PROJECT_MISMATCH';end if;
 select count(*) into c from public.vehicle_work_items wi join public.vehicles v on v.id=wi.vehicle_id
 where v.lifecycle_state='active' and v.deleted_at is null and wi.required and not wi.completed
   and not exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=wi.vehicle_id and e.active and e.work_key=wi.work_key);
 if c<>1 or not exists(select 1 from public.vehicle_work_items wi join public.vehicles v on v.id=wi.vehicle_id where v.stock_number='13047224' and v.job_card_number='J139125358' and wi.work_key='tint' and wi.required and not wi.completed) then raise exception 'PDC_322_SCOPE_DRIFT count=%',c;end if;
end $guard$;
create or replace function public.pdc_reconcile_required_work_after_adjustment_322()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin
 if tg_op in('UPDATE','DELETE') then perform public.pdc_auditor_recalculate_required_work_226(array[old.vehicle_id]);end if;
 if tg_op in('INSERT','UPDATE') and (tg_op='INSERT' or new.vehicle_id is distinct from old.vehicle_id or new.stage_code is distinct from old.stage_code or new.active is distinct from old.active) then perform public.pdc_auditor_recalculate_required_work_226(array[new.vehicle_id]);end if;
 return null;
end $trigger$;
revoke all on function public.pdc_reconcile_required_work_after_adjustment_322() from public,anon,authenticated,service_role;
drop trigger if exists pdc_adjustment_required_work_reconciliation_322 on public.vehicle_workshop_line_adjustments;
create trigger pdc_adjustment_required_work_reconciliation_322
after insert or update of vehicle_id,stage_code,active or delete on public.vehicle_workshop_line_adjustments
for each row execute function public.pdc_reconcile_required_work_after_adjustment_322();
do $repair$ declare a uuid;e text;v uuid;wi public.vehicle_work_items%rowtype;after_row public.vehicle_work_items%rowtype;before_json jsonb;begin
 select auth_user_id,lower(email) into a,e from public.pdc_user_roles where role='administrator' and active and account_status='approved' and lower(email)='craig.watson@broometoyota.com.au' limit 1;
 if a is null then raise exception 'PDC_322_OWNER_ADMIN_MISSING';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email',e)::text,true);
 select id into v from public.vehicles where stock_number='13047224' and lifecycle_state='active' and deleted_at is null;
 select * into wi from public.vehicle_work_items where vehicle_id=v and work_key='tint' for update;
 if not found or not wi.required or wi.completed then raise exception 'PDC_322_TARGET_DRIFT';end if;
 before_json:=to_jsonb(wi);
 perform public.pdc_auditor_recalculate_required_work_226(array[v]);
 select * into after_row from public.vehicle_work_items where id=wi.id;
 if after_row.required or after_row.completed then raise exception 'PDC_322_RECONCILIATION_FAILED';end if;
 perform public.audit_pdc_event('update','vehicle_work_items',wi.id,v,before_json,to_jsonb(after_row),jsonb_build_object('contract','required_work_reconciliation_322','reason','No active effective Tint operation remains','stock_number','13047224','job_card_number','J139125358','work_key','tint','owner_rule','A Workshop bay is not required when all jobs in that section are removed'));
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
 perform public.workshop_bump_revision();
end $repair$;
do $post$ declare c integer;begin
 select count(*) into c from public.vehicle_work_items wi join public.vehicles v on v.id=wi.vehicle_id
 where v.lifecycle_state='active' and v.deleted_at is null and wi.required and not wi.completed
   and not exists(select 1 from public.pdc_effective_operation_lines e where e.vehicle_id=wi.vehicle_id and e.active and e.work_key=wi.work_key);
 if c<>0 then raise exception 'PDC_322_STALE_REQUIREMENTS_REMAIN count=%',c;end if;
end $post$;
insert into supabase_migrations.schema_migrations(version,name,statements) values('20260822140000','322_reconcile_removed_operation_workbay_requirements',array['automatic adjustment required-work reconciliation','clear audited stale 13047224 Tint requirement']) on conflict(version) do nothing;
commit;
