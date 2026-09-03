-- PDC-14 canonical Control Board controls. STAGING ONLY.

DO $pdc14_guard$
DECLARE
  v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane', 0));
  IF to_regclass('public.pdc_staging_environment_sentinel') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.pdc_staging_environment_sentinel
       WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'
     )
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_NON_STAGING_TARGET';
  END IF;

  SELECT version,name INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$'
  ORDER BY version::bigint DESC
  LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260903150000'
     OR v_head.name IS DISTINCT FROM 'pdc14_parts_coordinator_role' THEN
    RAISE EXCEPTION 'PDC_14_PREDECESSOR_MISMATCH:%/%', v_head.version, v_head.name;
  END IF;
END
$pdc14_guard$;

-- Preserve the strict standard VIN contract and add only the documented
-- 14-character electric HiLux chassis family (for example REBHV100551477).
CREATE OR REPLACE FUNCTION public.is_valid_vehicle_vin(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE STRICT
SET search_path='public','pg_temp'
AS $vin$
  SELECT coalesce(
    public.normalize_vehicle_vin(p_value) ~ '^[A-HJ-NPR-Z0-9]{17}$'
    OR public.normalize_vehicle_vin(p_value) ~ '^REBHV1[0-9]{8}$',
    false
  );
$vin$;
REVOKE ALL ON FUNCTION public.is_valid_vehicle_vin(text) FROM public,anon;

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

  UPDATE public.vehicles
  SET current_location=v_to,
      visible_on_board=true,
      pmb_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_stage END,
      pmb_bay_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_stage END,
      pmb_bay_number=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_number END,
      date_to_pmb=CASE
        WHEN v_to IN ('PMB','PIT') THEN coalesce(date_to_pmb,(v_now AT TIME ZONE 'Australia/Perth')::date)
        ELSE date_to_pmb
      END,
      source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
        'manual_location_authority',v_to,
        'manual_location_updated_at',v_now,
        'manual_location_updated_by',public.current_actor_email(),
        'location_rule_version','pdc14_operator_location_dropdown_v1'
      ),
      version=version+1,
      updated_by=auth.uid()
  WHERE id=p_vehicle_id
  RETURNING * INTO v_after;

  INSERT INTO public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,
    reason,moved_by
  ) VALUES(
    p_vehicle_id,v_before.current_location,v_after.current_location,
    v_before.pmb_stage,v_after.pmb_stage,v_before.pmb_bay_stage,v_after.pmb_bay_stage,
    v_before.pmb_bay_number,v_after.pmb_bay_number,
    'Vehicle Detail PDC location dropdown',auth.uid()
  );

  PERFORM public.audit_pdc_event(
    'move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','set_pdc_vehicle_location_1500','from',v_from,'to',v_to)
  );
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  IF to_regclass('public.navision_backend_revision') IS NOT NULL THEN
    UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  END IF;

  -- first_entered_pmb_at is recorded by the existing
  -- vehicles_lifecycle_milestones trigger on the same transaction.
  RETURN jsonb_build_object('ok',true,'code','pdc_location_updated','vehicle',to_jsonb(v_after));
END;
$location$;
REVOKE ALL ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text) TO authenticated,service_role;
COMMENT ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text) IS
  'Operator-authorized, version-checked, audited Vehicle Detail dropdown transitions from YH onward.';

-- 169 already maps the exact status directly to PMB; retain an explicit,
-- executable postcondition and a versioned authority marker here.
DO $body_builder_postcondition$
BEGIN
  IF public.navision_operational_location(jsonb_build_object(
    'navisionSubLocationDescription','Delivered - At Body Builder'
  )) IS DISTINCT FROM 'PMB' THEN
    RAISE EXCEPTION 'PDC_14_BODY_BUILDER_NOT_PMB';
  END IF;
END
$body_builder_postcondition$;
COMMENT ON FUNCTION public.navision_operational_location(jsonb) IS
  'pdc14_navision_body_builder_direct_pmb_v1: exact Delivered - At Body Builder maps directly to PMB; vehicle milestone triggers preserve date_to_pmb and first_entered_pmb_at.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES(
  '20260903160000',
  'pdc14_canonical_controls',
  ARRAY['PDC-14 bounded electric HiLux identity, operator PDC location dropdown RPC, and body-builder PMB postcondition']
);
