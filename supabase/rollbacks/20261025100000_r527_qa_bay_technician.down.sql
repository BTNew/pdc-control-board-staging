-- r527 (F141) undo. Staging cdsmnqxtyyoeoznmbidd only. Restores the administrator-only body.
-- Removes the unused Bhavesh Patel roster row. Refuses if that row is referenced.
-- Does not change workshop_bays, bookings or Department 135.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r527 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r527 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'51415343720a6d3a02fb2597109db9b1'
 THEN RAISE EXCEPTION 'r527 undo: function is not the r527 body'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.set_bay_default_technician(uuid,integer,uuid)')<>'51415343720a6d3a02fb2597109db9b1'
 THEN RAISE EXCEPTION 'r527 undo: pin is not the r527 md5'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>236 THEN RAISE EXCEPTION 'r527 undo: pin count is not 236'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'d07f40a33443eff357d3a9cd58503696'
 THEN RAISE EXCEPTION 'r527 undo: Department 135 function changed'; END IF;
 IF (SELECT count(*) FROM public.workshop_technicians WHERE id='b1410527-1410-4410-8410-00000000b141'::uuid AND name='Bhavesh Patel' AND active AND role_type='technician' AND code IS NULL AND can_fit_stages=ARRAY['BUS_4X4']::text[])<>1
 THEN RAISE EXCEPTION 'r527 undo: Bhavesh roster row is not the r527 row'; END IF;
 IF EXISTS (SELECT 1 FROM public.workshop_bays WHERE default_technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM public.workshop_booking_assignments WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM public.workshop_bay_default_technician_history WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid OR previous_technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM pdc_bus_private.supplier WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM pdc_bus_private.helper_labour WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
  OR EXISTS (SELECT 1 FROM pdc_fitter_private.operation_timing WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
 THEN RAISE EXCEPTION 'r527 undo: Bhavesh roster row is in use'; END IF;
END $g$;

DELETE FROM public.workshop_technicians
 WHERE id='b1410527-1410-4410-8410-00000000b141'::uuid
   AND name='Bhavesh Patel'
   AND role_type='technician'
   AND code IS NULL
   AND can_fit_stages=ARRAY['BUS_4X4']::text[]
   AND created_by IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.workshop_bays WHERE default_technician_id='b1410527-1410-4410-8410-00000000b141'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.workshop_booking_assignments WHERE technician_id='b1410527-1410-4410-8410-00000000b141'::uuid);

CREATE OR REPLACE FUNCTION public.set_bay_default_technician(p_bay_id uuid, p_expected_version integer, p_technician_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $r527down$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
  v_technician public.workshop_technicians%rowtype;
  v_other public.workshop_bays%rowtype;
begin
  perform public.require_pdc_role('administrator');
  perform pg_advisory_xact_lock(hashtextextended('pdc:bay-default-technician',0));

  select * into v_before from public.workshop_bays where id=p_bay_id for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_before.version<>p_expected_version then
    -- An exact repeat is idempotently successful even if the caller retained the old version.
    if v_before.default_technician_id is not distinct from p_technician_id then
      return jsonb_build_object('ok',true,'idempotent',true,'bay',to_jsonb(v_before));
    end if;
    return jsonb_build_object('ok',false,'error','version_conflict','current',to_jsonb(v_before));
  end if;
  if v_before.default_technician_id is not distinct from p_technician_id then
    return jsonb_build_object('ok',true,'idempotent',true,'bay',to_jsonb(v_before));
  end if;

  if p_technician_id is not null then
    select * into v_technician from public.workshop_technicians where id=p_technician_id for update;
    if not found then return jsonb_build_object('ok',false,'error','technician_not_found'); end if;
    if not v_technician.active then return jsonb_build_object('ok',false,'error','technician_inactive'); end if;
    select * into v_other from public.workshop_bays
      where default_technician_id=p_technician_id and id<>p_bay_id for update;
    if found then
      return jsonb_build_object('ok',false,'error','technician_already_assigned_to_bay',
        'conflict',jsonb_build_object('bay_id',v_other.id,'bay_code',v_other.code,'bay_number',v_other.bay_number));
    end if;
  end if;

  update public.workshop_bays
     set default_technician_id=p_technician_id,version=version+1,
         updated_by=auth.uid(),updated_at=now()
   where id=p_bay_id and version=p_expected_version
   returning * into v_after;
  if not found then return jsonb_build_object('ok',false,'error','version_conflict'); end if;

  perform public.audit_pdc_event('reference_change','workshop_bays',v_after.id,null,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','set_bay_default_technician','migration',232));
  return jsonb_build_object('ok',true,'idempotent',false,'bay',to_jsonb(v_after));
end $r527down$;

DELETE FROM pdc_ops.expected_function_md5 WHERE signature='public.set_bay_default_technician(uuid,integer,uuid)' AND release='r527' AND prosrc_md5='51415343720a6d3a02fb2597109db9b1';
DELETE FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527' AND added_in='r527' AND fault_id='F141' AND sort_order=308;

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'4849edd770bac33b569ae65023cf7aac'
 THEN RAISE EXCEPTION 'r527 undo: old body was not restored'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.set_bay_default_technician(uuid,integer,uuid)')
 THEN RAISE EXCEPTION 'r527 undo: pin remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qa_bay_technician_527')
 THEN RAISE EXCEPTION 'r527 undo: check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>235 THEN RAISE EXCEPTION 'r527 undo: pin count is not 235'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'d07f40a33443eff357d3a9cd58503696'
 THEN RAISE EXCEPTION 'r527 undo: Department 135 function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_workshop_bay_active(uuid,integer,boolean)'::regprocedure)<>'fbdf5fefaff3d68c2e2240037ec14064'
 THEN RAISE EXCEPTION 'r527 undo: set_workshop_bay_active changed'; END IF;
 IF EXISTS (SELECT 1 FROM public.workshop_technicians WHERE id='b1410527-1410-4410-8410-00000000b141'::uuid OR lower(btrim(name))='bhavesh patel')
 THEN RAISE EXCEPTION 'r527 undo: Bhavesh roster row remains'; END IF;
END $p$;
