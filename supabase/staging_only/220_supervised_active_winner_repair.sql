-- Staging-only migration 220: repair Monitor rule reads and bind apply to the deterministic active winner.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-220-supervised-winner-repair',0));
select public.pdc_monitor_staging_guard();
do $guard$ begin
 if not public.pdc_monitor_staging_guard()
 or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or to_regclass('public.pdc_production_environment_sentinel') is not null
 or not exists(select 1 from supabase_migrations.schema_migrations where version='219' and name='supervised_active_version_schema_fix')
 or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::integer>219)
 or exists(select 1 from supabase_migrations.schema_migrations where version='220')
 then raise exception 'PDC_220_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
end $guard$;

create or replace function public.read_pdc_supervised_learning_rule(p_scope jsonb) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_monitor_scope_213(); r jsonb; v public.pdc_supervised_rule_versions%rowtype;
begin
 if not coalesce((s->>'ok')::boolean,false) then return public.navision_backend_response(false,'forbidden'); end if;
 r:=public.review_pdc_supervised_email_line_213(null,nullif(p_scope->>'operation_code',''),p_scope->>'operation_description',p_scope->>'current_mapping');
 if not coalesce((r->>'ok')::boolean,false) or r->>'code'<>'deterministic_match' then
  return public.navision_backend_response(true,'active_lessons',jsonb_build_object('matched',false,'rule',null));
 end if;
 select * into strict v from public.pdc_supervised_rule_versions where version_id=(r->'data'->>'version_id')::uuid;
 return public.navision_backend_response(true,'active_lessons',jsonb_build_object('matched',true,'rule',jsonb_build_object(
  'lesson_id',v.version_id,'version',v.version_no,'target_mapping',v.work_key,'estimated_hours',v.estimated_hours,
  'pricing',case when v.cost_ex_gst is null then null else jsonb_build_object('cost_ex_gst',to_char(v.cost_ex_gst,'FM999999990.00'),'sell_ex_gst',to_char(v.sell_ex_gst,'FM999999990.00'),'gst_percent',to_char(v.gst_percent,'FM990.00'),'currency',v.currency) end)));
exception when no_data_found or too_many_rows then return public.navision_backend_response(false,'conflict');
end$$;

create or replace function public.apply_pdc_supervised_learning_rule(p_scope jsonb,p_lesson_id uuid,p_expected_version integer,p_resolution jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_supervised_monitor_scope_213(); a uuid; e text; r jsonb; v public.pdc_supervised_rule_versions%rowtype; supplied_hours numeric;
begin
 if not coalesce((s->>'ok')::boolean,false) then return public.navision_backend_response(false,'forbidden'); end if;
 a=(s->'data'->>'actor_id')::uuid; e=s->'data'->>'actor_email';
 r:=public.review_pdc_supervised_email_line_213(null,nullif(p_scope->>'operation_code',''),p_scope->>'operation_description',p_scope->>'current_mapping');
 if not coalesce((r->>'ok')::boolean,false) or r->>'code'<>'deterministic_match'
 or (r->'data'->>'version_id')::uuid is distinct from p_lesson_id
 or (r->'data'->>'version_no')::integer is distinct from p_expected_version
 then return public.navision_backend_response(false,'conflict'); end if;
 select * into strict v from public.pdc_supervised_rule_versions where version_id=p_lesson_id and version_no=p_expected_version for share;
 if coalesce(p_resolution->>'target_mapping',p_resolution->>'work_key') is distinct from v.work_key then return public.navision_backend_response(false,'conflict'); end if;
 if p_resolution ? 'estimated_hours' and nullif(p_resolution->>'estimated_hours','') is not null then supplied_hours=(p_resolution->>'estimated_hours')::numeric; end if;
 if supplied_hours is distinct from v.estimated_hours then return public.navision_backend_response(false,'conflict'); end if;
 insert into public.pdc_supervised_monitor_applications(rule_version_id,operation_code,source_description,display_description,source_work_key,applied_work_key,scope,resolution,actor_id,actor_email)
 values(v.version_id,nullif(p_scope->>'operation_code',''),p_scope->>'operation_description',p_resolution->>'display_description',p_scope->>'current_mapping',v.work_key,p_scope,p_resolution,a,e);
 return public.navision_backend_response(true,'lesson_activated',jsonb_build_object('work_key',v.work_key,'estimated_hours',v.estimated_hours,'version_id',v.version_id,'version_no',v.version_no,'display_description',p_resolution->>'display_description'));
exception when no_data_found or too_many_rows or invalid_text_representation or numeric_value_out_of_range then return public.navision_backend_response(false,'conflict');
end$$;

revoke all on function public.read_pdc_supervised_learning_rule(jsonb),public.apply_pdc_supervised_learning_rule(jsonb,uuid,integer,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_supervised_learning_rule(jsonb),public.apply_pdc_supervised_learning_rule(jsonb,uuid,integer,jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('220','supervised_active_winner_repair',array[
 'Repair migration 218/219 schema assumptions using the existing deterministic active-rule resolver',
 'Bind Monitor apply to the exact active deterministic winner for the supplied scope',
 'Require server-owned mapping and standard hours to match before recording application',
 'Remove service_role EXECUTE drift from Monitor rule RPCs']);
notify pgrst,'reload schema';
commit;
