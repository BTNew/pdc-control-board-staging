-- Staging-only migration 222: expose active rule standard hours to later email intake.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-222-supervised-review-hours',0));
select public.pdc_monitor_staging_guard();
do $guard$ begin
 if not public.pdc_monitor_staging_guard()
 or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or to_regclass('public.pdc_production_environment_sentinel') is not null
 or not exists(select 1 from supabase_migrations.schema_migrations where version='221' and name='supervised_replay_undo_precedence_hardening')
 or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>221)
 or exists(select 1 from supabase_migrations.schema_migrations where version='222')
 then raise exception 'PDC_222_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
end $guard$;

create or replace function public.review_pdc_supervised_email_line_213(p_operation_line_id uuid,p_operation_code text,p_description text,p_existing_work_key text) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_admin_scope_213(); r record; d text:=lower(regexp_replace(btrim(coalesce(p_description,'')),'[^a-zA-Z0-9]+',' ','g')); locked_key text; hours numeric;
begin
 if not coalesce((s->>'ok')::boolean,false) then s:=public.pdc_supervised_monitor_scope_213(); end if;
 if not coalesce((s->>'ok')::boolean,false) then return s; end if;
 if p_operation_line_id is not null then
  select coalesce(public.pdc_auditor_work_key_for_stage(a.stage_code),l.work_key) into locked_key
  from public.pdc_authenticated_email_operation_lines l join public.vehicle_workshop_line_adjustments a on a.vehicle_id=l.vehicle_id and a.line_key='source:'||l.operation_line_id::text
  where l.operation_line_id=p_operation_line_id;
  if found then return public.navision_backend_response(true,'existing_mapping',jsonb_build_object('operation_line_id',p_operation_line_id,'work_key',locked_key,'estimated_hours',null,'precedence','manual_overlay')); end if;
 end if;
 select x.* into r from public.list_pdc_supervised_rules_213(false) x left join public.pdc_supervised_rule_aliases al on al.version_id=x.version_id
 where (x.match_kind='operation_code' and x.operation_code=upper(btrim(p_operation_code))) or (x.match_kind='exact_description' and x.normalized_description=btrim(d)) or (x.match_kind='phrase' and (btrim(d) like '%'||replace(x.phrase_category,'_',' ')||'%' or btrim(d) like '%'||al.alias||'%'))
 order by case x.match_kind when 'operation_code' then 2 when 'exact_description' then 3 when 'phrase' then 4 else 9 end,x.priority desc,x.confidence desc,x.version_no desc limit 1;
 if found then
  select estimated_hours into hours from public.pdc_supervised_rule_versions where version_id=r.version_id;
  return public.navision_backend_response(true,'deterministic_match',jsonb_build_object('operation_line_id',p_operation_line_id,'work_key',r.work_key,'estimated_hours',hours,'version_id',r.version_id,'version_no',r.version_no,'precedence',r.match_kind));
 end if;
 if p_existing_work_key is not null then return public.navision_backend_response(true,'existing_mapping',jsonb_build_object('work_key',p_existing_work_key,'estimated_hours',null,'precedence','existing_mapping')); end if;
 return public.navision_backend_response(false,'inference_review_required');
end$$;
revoke all on function public.review_pdc_supervised_email_line_213(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.review_pdc_supervised_email_line_213(uuid,text,text,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('222','supervised_review_standard_hours',array[
 'Return active deterministic rule standard hours to the later-email intake path',
 'Never source hours from manual or existing mappings',
 'Retain operation-line manual-overlay precedence']);
notify pgrst,'reload schema';
commit;
