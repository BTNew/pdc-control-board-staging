-- PDC-14 review hardening for location transitions. STAGING ONLY.
-- Approved STAGING project ref: cdsmnqxtyyoeoznmbidd.

DO $guard$
DECLARE v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane',0));
  IF to_regclass('public.pdc_staging_environment_sentinel') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_WRONG_ENVIRONMENT';
  END IF;
  SELECT version,name INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260903170000' OR v_head.name IS DISTINCT FROM 'pdc14_role_history_rls' THEN
    RAISE EXCEPTION 'PDC_14_STALE_HEAD: expected 20260903170000/pdc14_role_history_rls, got %/%',v_head.version,v_head.name;
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.set_pdc_vehicle_location_1500(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_location text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $location$
DECLARE
  v_before public.vehicles%ROWTYPE;
  v_after public.vehicles%ROWTYPE;
  v_from text;
  v_to text:=upper(btrim(coalesce(p_location,'')));
  v_now timestamptz:=clock_timestamp();
BEGIN
  PERFORM public.require_pdc_role('operator');
  IF p_vehicle_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_vehicle');
  END IF;
  IF v_to NOT IN ('YH','PMB','PIT') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_pdc_location');
  END IF;

  SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vehicle not found' USING ERRCODE='P0002';
  END IF;
  IF p_expected_version IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','missing_expected_version');
  END IF;
  IF v_before.version<>p_expected_version THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict');
  END IF;
  IF v_before.lifecycle_state<>'active' OR v_before.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  END IF;

  v_from:=upper(btrim(coalesce(v_before.current_location,'')));
  IF v_from=v_to THEN
    RETURN jsonb_build_object('ok',true,'code','pdc_location_unchanged','vehicle',to_jsonb(v_before));
  END IF;
  IF NOT (
    (v_from='YH' AND v_to='PMB')
    OR (v_from='PMB' AND v_to='PIT')
    OR (v_from='PIT' AND v_to='PMB')
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_pdc_location_transition','from',v_from,'to',v_to);
  END IF;
  IF v_from='PMB' AND v_to='PIT' AND (
    coalesce(v_before.pdc_qc_complete,false)
    OR nullif(btrim(coalesce(v_before.pmb_stage,'')),'') IS NOT NULL
    OR nullif(btrim(coalesce(v_before.pmb_bay_stage,'')),'') IS NOT NULL
    OR v_before.pmb_bay_number IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok',false,'error','pit_requires_pmb_unallocated');
  END IF;

  UPDATE public.vehicles
  SET current_location=v_to,
      visible_on_board=true,
      pmb_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_stage END,
      pmb_bay_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_stage END,
      pmb_bay_number=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_number END,
      date_to_pmb=CASE WHEN v_to IN ('PMB','PIT') THEN coalesce(date_to_pmb,(v_now AT TIME ZONE 'Australia/Perth')::date) ELSE date_to_pmb END,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'manual_location_authority',v_to,
        'manual_location_updated_at',v_now,
        'manual_location_updated_by',public.current_actor_email(),
        'location_rule_version','pdc14_operator_location_dropdown_v2_review_hardened'
      ),
      version=version+1,
      updated_by=auth.uid()
  WHERE id=p_vehicle_id
  RETURNING * INTO v_after;

  INSERT INTO public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by
  ) VALUES(
    p_vehicle_id,v_before.current_location,v_after.current_location,
    v_before.pmb_stage,v_after.pmb_stage,v_before.pmb_bay_stage,v_after.pmb_bay_stage,
    v_before.pmb_bay_number,v_after.pmb_bay_number,
    'Vehicle Detail PDC location dropdown',auth.uid()
  );
  PERFORM public.audit_pdc_event(
    'move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','set_pdc_vehicle_location_1500','from',v_from,'to',v_to,'rule_version','v2_review_hardened')
  );
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  IF to_regclass('public.navision_backend_revision') IS NOT NULL THEN
    UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  END IF;
  RETURN jsonb_build_object('ok',true,'code','pdc_location_updated','vehicle',to_jsonb(v_after));
END;
$location$;
REVOKE ALL ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text) TO authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903180000','pdc14_location_review_hardening',ARRAY['PDC-14 location RPC rejects PMB to PIT for QC-complete or actively staged vehicles']::text[]);
