-- PDC-14 location replay runtime schema alignment. STAGING ONLY.
-- Approved STAGING project ref: cdsmnqxtyyoeoznmbidd.
BEGIN;
DO $guard$
DECLARE v_head record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-lane',0));
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_14_LOCATION_REPLAY_RUNTIME_WRONG_ENVIRONMENT';
  END IF;
  SELECT version,name INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head.version IS DISTINCT FROM '20260904011000' OR v_head.name IS DISTINCT FROM 'pdc14_location_replay_idempotency' THEN
    RAISE EXCEPTION 'PDC_14_LOCATION_REPLAY_RUNTIME_STALE_HEAD: got %/%',v_head.version,v_head.name;
  END IF;
  IF to_regclass('public.pdc_vehicle_location_receipts_20260904') IS NULL
     OR to_regprocedure('public.set_pdc_vehicle_location_1500(uuid,integer,text,text)') IS NULL THEN
    RAISE EXCEPTION 'PDC_14_LOCATION_REPLAY_RUNTIME_DEPENDENCY_MISSING';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.set_pdc_vehicle_location_1500(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_location text,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $location$
DECLARE
  v_actor_id uuid:=auth.uid();
  v_actor_email text:=public.current_actor_email();
  v_key text:=btrim(coalesce(p_request_key,''));
  v_request_hash text;
  v_receipt public.pdc_vehicle_location_receipts_20260904%ROWTYPE;
  v_before public.vehicles%ROWTYPE;
  v_after public.vehicles%ROWTYPE;
  v_from text;
  v_to text:=upper(btrim(coalesce(p_location,'')));
  v_now timestamptz:=clock_timestamp();
  v_response jsonb;
BEGIN
  PERFORM public.require_pdc_role('operator');
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF length(v_key) NOT BETWEEN 16 AND 200 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_request_key');
  END IF;
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','pdc14_location_replay_v1','actor_id',v_actor_id,
    'vehicle_id',p_vehicle_id,'expected_version',p_expected_version,'location',v_to
  )::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc14-location:'||v_actor_id::text||':'||v_key,0));
  SELECT * INTO v_receipt FROM public.pdc_vehicle_location_receipts_20260904
  WHERE actor_id=v_actor_id AND request_key=v_key;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'error','idempotency_conflict');
    END IF;
    RETURN v_receipt.response;
  END IF;

  IF p_vehicle_id IS NULL THEN
    v_response:=jsonb_build_object('ok',false,'error','invalid_vehicle');
  ELSIF v_to NOT IN ('YH','PMB','PIT') THEN
    v_response:=jsonb_build_object('ok',false,'error','invalid_pdc_location');
  ELSE
    SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
      v_response:=jsonb_build_object('ok',false,'error','vehicle_not_found');
    ELSIF p_expected_version IS NULL THEN
      v_response:=jsonb_build_object('ok',false,'error','missing_expected_version');
    ELSIF v_before.version<>p_expected_version THEN
      v_response:=jsonb_build_object('ok',false,'error','vehicle_version_conflict');
    ELSIF v_before.lifecycle_state<>'active' OR v_before.deleted_at IS NOT NULL THEN
      v_response:=jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
    ELSE
      v_from:=upper(btrim(coalesce(v_before.current_location,'')));
      IF v_from=v_to THEN
        v_response:=jsonb_build_object('ok',true,'code','pdc_location_unchanged','vehicle',to_jsonb(v_before));
      ELSIF NOT ((v_from='YH' AND v_to='PMB') OR (v_from='PMB' AND v_to='PIT') OR (v_from='PIT' AND v_to='PMB')) THEN
        v_response:=jsonb_build_object('ok',false,'error','invalid_pdc_location_transition','from',v_from,'to',v_to);
      ELSIF v_from='PMB' AND v_to='PIT' AND (
        v_before.qc_completed_at IS NOT NULL
        OR nullif(btrim(coalesce(v_before.pmb_stage,'')),'') IS NOT NULL
        OR nullif(btrim(coalesce(v_before.pmb_bay_stage,'')),'') IS NOT NULL
        OR v_before.pmb_bay_number IS NOT NULL
      ) THEN
        v_response:=jsonb_build_object('ok',false,'error','pit_requires_pmb_unallocated');
      ELSE
        UPDATE public.vehicles
        SET current_location=v_to,visible_on_board=true,
            pmb_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_stage END,
            pmb_bay_stage=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_stage END,
            pmb_bay_number=CASE WHEN v_from='YH' AND v_to='PMB' THEN NULL ELSE pmb_bay_number END,
            date_to_pmb=CASE WHEN v_to IN ('PMB','PIT') THEN coalesce(date_to_pmb,(v_now AT TIME ZONE 'Australia/Perth')::date) ELSE date_to_pmb END,
            source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
              'manual_location_authority',v_to,'manual_location_updated_at',v_now,
              'manual_location_updated_by',v_actor_email,'location_rule_version','pdc14_operator_location_dropdown_v3_replay'
            ),version=version+1,updated_by=v_actor_id
        WHERE id=p_vehicle_id RETURNING * INTO v_after;
        INSERT INTO public.vehicle_movements(
          vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
          from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by
        ) VALUES(
          p_vehicle_id,v_before.current_location,v_after.current_location,
          v_before.pmb_stage,v_after.pmb_stage,v_before.pmb_bay_stage,v_after.pmb_bay_stage,
          v_before.pmb_bay_number,v_after.pmb_bay_number,'Vehicle Detail PDC location dropdown',v_actor_id
        );
        PERFORM public.audit_pdc_event(
          'move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
          jsonb_build_object('action','set_pdc_vehicle_location_1500','from',v_from,'to',v_to,'rule_version','v3_replay','request_key',v_key)
        );
        UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
        IF to_regclass('public.navision_backend_revision') IS NOT NULL THEN
          UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
        END IF;
        v_response:=jsonb_build_object('ok',true,'code','pdc_location_updated','vehicle',to_jsonb(v_after));
      END IF;
    END IF;
  END IF;
  INSERT INTO public.pdc_vehicle_location_receipts_20260904(
    actor_id,actor_email,request_key,request_hash,vehicle_id,expected_vehicle_version,
    requested_location,response,vehicle_version_before,vehicle_version_after
  ) VALUES(
    v_actor_id,v_actor_email,v_key,v_request_hash,p_vehicle_id,p_expected_version,
    v_to,v_response,v_before.version,v_after.version
  );
  RETURN v_response;
END;
$location$;
REVOKE ALL ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_location_1500(uuid,integer,text,text) TO authenticated,service_role;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904011100','pdc14_location_replay_runtime_schema_alignment',ARRAY[
  'Align PMB-to-PIT QC boundary with the live authoritative qc_completed_at column while retaining the 20260904011000 replay receipt contract'
]::text[]);
COMMIT;
