-- STAGING ONLY 950: authenticated canonical Yard Hold transition for
-- controlled lifecycle acceptance and operational use.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-lifecycle-history-yard-hold-950',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830094000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830094000' AND name='pdc_lifecycle_history_rpc_repair')<>1
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830095000')
 THEN RAISE EXCEPTION 'PDC_950_EXACT_STAGING_940_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.mark_vehicle_yard_hold_82000(p_vehicle_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $yh$
DECLARE before_v public.vehicles%rowtype; after_v public.vehicles%rowtype; now_at timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_pdc_role('operator');
 IF p_vehicle_id IS NULL OR p_expected_version IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_input'); END IF;
 SELECT * INTO before_v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR before_v.deleted_at IS NOT NULL OR before_v.lifecycle_state<>'active' THEN RETURN jsonb_build_object('ok',false,'code','not_in_active_lifecycle'); END IF;
 IF before_v.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',before_v.version); END IF;
 IF upper(coalesce(before_v.current_location,''))='YH' THEN RETURN jsonb_build_object('ok',true,'code','already_at_yard_hold','vehicle',to_jsonb(before_v)); END IF;
 IF upper(coalesce(before_v.current_location,'')) NOT IN('IT','OTHER') THEN RETURN jsonb_build_object('ok',false,'code','yard_hold_requires_it_or_other'); END IF;
 UPDATE public.vehicles SET current_location='YH',version=version+1,updated_at=now_at,updated_by=auth.uid(),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','canonical_yard_hold_transition_82000','transition_at',now_at) WHERE id=p_vehicle_id RETURNING * INTO after_v;
 INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at) VALUES(p_vehicle_id,before_v.current_location,'YH',before_v.pmb_stage,before_v.pmb_stage,before_v.pmb_bay_stage,before_v.pmb_bay_stage,before_v.pmb_bay_number,before_v.pmb_bay_number,'Authenticated canonical transition to Yard Hold',auth.uid(),now_at);
 PERFORM public.audit_pdc_event('move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(before_v),to_jsonb(after_v),jsonb_build_object('action','mark_vehicle_yard_hold_82000','canonical_transition',true,'transition_at',now_at));
 RETURN jsonb_build_object('ok',true,'code','yard_hold_recorded','vehicle',to_jsonb(after_v));
END $yh$;
REVOKE ALL ON FUNCTION public.mark_vehicle_yard_hold_82000(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_vehicle_yard_hold_82000(uuid,integer) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830095000','pdc_lifecycle_history_yard_hold_transition',ARRAY[
 'Append-only successor after exact 20260830094000 lifecycle-history RPC repair',
 'Authenticated operator canonical IT/Other to Yard Hold transition with expected-version, movement, audit and idempotent already-at-YH response',
 'Yard Hold transition is captured by the 82000 first-transition latch trigger and does not use ETA or mutable date fields',
 'Production sentinel/data/remotes remain excluded'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
