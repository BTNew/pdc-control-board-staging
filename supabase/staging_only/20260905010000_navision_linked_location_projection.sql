-- STAGING ONLY: repair linked Navision location projection after descriptive refresh.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-navision-linked-location-20260905',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head record; v_refresh text; v_public text;
BEGIN
  SELECT version,name INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  SELECT pg_get_functiondef('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)'::regprocedure) INTO v_refresh;
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO v_public;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head.version IS DISTINCT FROM '20260904011500'
     OR v_head.name IS DISTINCT FROM 'parts_stoppage_runtime_containment_repair'
     OR position('linked_vehicle_refreshed' in v_refresh)=0
     OR position('navision-linked-refresh-481' in v_refresh)=0
     OR position('reconcile_navision_operational_record_pre_734' in v_public)=0
     OR position('reconcile_navision_delivery_734' in v_public)=0 THEN
    RAISE EXCEPTION 'PDC_NAVISION_LINKED_LOCATION_PRECONDITION_FAILED:%/%',v_head.version,v_head.name USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_navision_projection_cleanup_history_20260905(
  cleanup_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL UNIQUE,
  actor_id uuid,
  actor_email text NOT NULL,
  before_vehicle jsonb NOT NULL,
  navision_record jsonb NOT NULL,
  parity jsonb NOT NULL CHECK(coalesce((parity->>'ok')::boolean,false)),
  audit_evidence jsonb NOT NULL,
  movement_evidence jsonb NOT NULL,
  cleanup_reason text NOT NULL CHECK(cleanup_reason='bounded linked Navision projection fixture archived before mutable cleanup'),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_navision_projection_cleanup_history_20260905 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_projection_cleanup_history_20260905 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_projection_cleanup_history_20260905 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_project_linked_navision_location_20260905(
  p_backend_record_id uuid,p_actor_id uuid,p_actor_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $projection$
DECLARE
  v_record public.navision_backend_records%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_vehicle_ids uuid[];
  v_stock text;
  v_vin text;
  v_location text;
  v_status text;
  v_current text;
  v_target text;
  v_before jsonb;
  v_parity jsonb;
  v_now timestamptz:=clock_timestamp();
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN
    RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  SELECT * INTO v_record FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT v_record.is_current OR v_record.record_status<>'current' OR v_record.canonical_vehicle_id IS NULL THEN
    RETURN public.navision_backend_response(true,'projection_not_required',jsonb_build_object('changed',false,'reason','no_current_canonical_link'));
  END IF;
  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=public.pdc_navision_effective_vin_471(v_record.normalized_data);
  SELECT coalesce(array_agg(v.id ORDER BY v.id),'{}'::uuid[]) INTO v_vehicle_ids
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND (v.stock_number_normalized=v_stock OR (v_vin IS NOT NULL AND v.vin_normalized=v_vin));
  IF cardinality(v_vehicle_ids)<>1 OR v_vehicle_ids[1] IS DISTINCT FROM v_record.canonical_vehicle_id
     OR (SELECT count(*) FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current'
           AND nullif(public.normalize_vehicle_stock_number(n.normalized_data->>'batch'),'')=v_stock)<>1 THEN
    RETURN public.navision_backend_response(false,'canonical_identity_conflict',jsonb_build_object(
      'backend_record_id',p_backend_record_id,'candidate_count',cardinality(v_vehicle_ids)));
  END IF;
  SELECT * INTO STRICT v_vehicle FROM public.vehicles WHERE id=v_record.canonical_vehicle_id FOR UPDATE;
  v_location:=public.navision_operational_location(v_record.normalized_data);
  v_status:=public.navision_exact_lifecycle_status(v_record.normalized_data);
  v_current:=upper(btrim(coalesce(v_vehicle.current_location,'')));

  IF lower(btrim(coalesce(v_vehicle.lifecycle_state::text,'')))='completed'
     OR v_current IN ('PMB','PIT','QC','RFT','COLLECTED','COMPLETED')
     OR v_vehicle.date_to_pmb IS NOT NULL THEN
    RETURN public.navision_backend_response(true,'location_latch_preserved',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  IF v_location='YH' AND v_current<>'YH' THEN
    v_target:='YH';
  ELSIF v_location='PMB' AND v_status='deliveredatbodybuilder' AND v_current<>'PMB' THEN
    v_target:='PMB';
  ELSE
    RETURN public.navision_backend_response(true,'projection_not_required',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  v_before:=to_jsonb(v_vehicle);
  UPDATE public.vehicles SET
    current_location=v_target,
    visible_on_board=true,
    eta_to_kewdale=coalesce(public.navision_kewdale_eta(v_record.normalized_data),eta_to_kewdale),
    source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
      'authority','navision_linked_location_projection_20260905',
      'navision_location_projection',v_target,
      'navision_location_projected_at',v_now,
      'navision_record_id',p_backend_record_id),
    version=version+1,updated_at=v_now,updated_by=p_actor_id
  WHERE id=v_vehicle.id RETURNING * INTO v_after;
  INSERT INTO public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v_after.id,v_vehicle.current_location,v_after.current_location,
    v_vehicle.pmb_stage,v_after.pmb_stage,v_vehicle.pmb_bay_stage,v_after.pmb_bay_stage,
    v_vehicle.pmb_bay_number,v_after.pmb_bay_number,
    'Authoritative linked Navision operational location projection',p_actor_id);
  PERFORM public.audit_pdc_event('move','vehicles',v_after.id,v_after.id,v_before,to_jsonb(v_after),jsonb_build_object(
    'action','pdc_project_linked_navision_location_20260905','backend_record_id',p_backend_record_id,
    'from',v_vehicle.current_location,'to',v_after.current_location,'navision_status',v_status));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  v_parity:=public.pdc_navision_vehicle_parity_494(v_after.id);
  IF NOT coalesce((v_parity->>'ok')::boolean,false) OR coalesce((v_parity->>'mismatch_count')::integer,-1)<>0 THEN
    RAISE EXCEPTION 'PDC_NAVISION_LINKED_LOCATION_PARITY_FAILED:%',v_parity USING errcode='23514';
  END IF;
  RETURN public.navision_backend_response(true,'linked_location_projected',jsonb_build_object(
    'changed',true,'vehicle_id',v_after.id,'from_location',v_vehicle.current_location,
    'location',v_after.current_location,'date_to_pmb',v_after.date_to_pmb,
    'eta_to_kewdale',v_after.eta_to_kewdale,'vehicle_version_before',v_vehicle.version,
    'vehicle_version_after',v_after.version,'parity',v_parity));
END $projection$;
REVOKE ALL ON FUNCTION public.pdc_project_linked_navision_location_20260905(uuid,uuid,text) FROM public,anon,authenticated,service_role;

ALTER FUNCTION public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)
  RENAME TO pdc_refresh_linked_vehicle_from_navision_481_pre_20260905;
CREATE FUNCTION public.pdc_refresh_linked_vehicle_from_navision_481(
  p_backend_record_id uuid,p_actor_id uuid,p_actor_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $refresh$
DECLARE v_base jsonb; v_projection jsonb;
BEGIN
  v_base:=public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(p_backend_record_id,p_actor_id,p_actor_email);
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  v_projection:=public.pdc_project_linked_navision_location_20260905(p_backend_record_id,p_actor_id,p_actor_email);
  IF NOT coalesce((v_projection->>'ok')::boolean,false) THEN RETURN v_projection; END IF;
  RETURN jsonb_set(v_base,'{data}',coalesce(v_base->'data','{}'::jsonb)||jsonb_build_object(
    'navision_location_projection',v_projection),true);
END $refresh$;
REVOKE ALL ON FUNCTION public.pdc_refresh_linked_vehicle_from_navision_481_pre_20260905(uuid,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text) FROM public,anon,authenticated,service_role;

DO $post$
DECLARE v_public text; v_refresh text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO v_public;
  SELECT pg_get_functiondef('public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)'::regprocedure) INTO v_refresh;
  IF position('reconcile_navision_operational_record_pre_734' in v_public)=0
     OR position('reconcile_navision_delivery_734' in v_public)=0
     OR position('pdc_project_linked_navision_location_20260905' in v_refresh)=0
     OR has_function_privilege('public','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute')
     OR has_function_privilege('anon','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute')
     OR has_function_privilege('authenticated','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute')
     OR has_function_privilege('service_role','public.pdc_refresh_linked_vehicle_from_navision_481(uuid,uuid,text)','execute')
     OR NOT has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR NOT has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_table_privilege('authenticated','public.pdc_navision_projection_cleanup_history_20260905','select,insert,update,delete')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_navision_projection_cleanup_history_20260905'::regclass) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'PDC_NAVISION_LINKED_LOCATION_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260905010000','navision_linked_location_projection',ARRAY[
  'Linked current Navision refresh now applies the canonical operational location after descriptive refresh',
  'Past authoritative Kewdale ETA waiting states project IT to YH; generic YH to PMB remains manual',
  'Exact Delivered - At Body Builder may establish PMB while existing PMB and later lifecycle latches remain authoritative',
  'Delivered - At Dealer remains routed by the unchanged 734 canonical close wrapper',
  'Projection is audited, versioned, parity checked, ambiguity fail-closed, private, and STAGING contained'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
