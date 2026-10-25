-- r527 (F141). Staging cdsmnqxtyyoeoznmbidd only. Preview for Craig; he will go-live. Do not apply yet.
-- Bhavesh Patel (operator, not administrator), 25 Oct 2026: Workshop Planner, Bus 4x4 (Dept 138) QA,
-- 26/10/2026, QA Bay 07, Key 515 / stock 12379669. Setting the bay mechanic to Andrew McCormick failed.
-- This script replaces public.set_bay_default_technician only. It does not write workshop_bays,
-- workshop_bookings or workshop_booking_assignments. It does not change karratha135_pdc.
-- Open PRs #498 (r516), #501 (r519) and #493 (r512) are not merged and are not reused.
-- r526 / F140 is the main tip. This pair is the next free id.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r527: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r527: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'4849edd770bac33b569ae65023cf7aac'
 THEN RAISE EXCEPTION 'r527: set_bay_default_technician is not the live body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'d07f40a33443eff357d3a9cd58503696'
 THEN RAISE EXCEPTION 'r527: Department 135 function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_workshop_bay_active(uuid,integer,boolean)'::regprocedure)<>'fbdf5fefaff3d68c2e2240037ec14064'
 THEN RAISE EXCEPTION 'r527: set_workshop_bay_active changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>235 THEN RAISE EXCEPTION 'r527: pin count is not 235'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=308 OR fault_id='F141' OR check_name='qa_bay_technician_527' OR added_in='r527')
 THEN RAISE EXCEPTION 'r527: check slot already taken'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.set_bay_default_technician(uuid,integer,uuid)')
 THEN RAISE EXCEPTION 'r527: function is already pinned'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.set_bay_default_technician(p_bay_id uuid, p_expected_version integer, p_technician_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $r527$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
  v_technician public.workshop_technicians%rowtype;
  v_other public.workshop_bays%rowtype;
begin
  -- r527 (F141): an administrator may set any bay. A planner operator may set the default technician
  -- only on Department 138 (BUS_4X4, including QA Bays 5-7) and the shared Tint / Tyre bays.
  -- Department 139 stays administrator-only. Bay active, name and efficiency stay on other functions.
  -- Department 135 uses karratha135_pdc.set_bay_default_technician and is not this function.
  if not public.is_pdc_role('administrator') then
    if public.current_pdc_user_role()::text is distinct from 'operator' then
      raise exception 'PDC role administrator required' using errcode='42501';
    end if;
    if not exists (
      select 1 from public.workshop_bays b
      join public.workshop_stages s on s.id=b.stage_id
      where b.id=p_bay_id and s.code in ('BUS_4X4','TINT','TYRE')
    ) then
      raise exception 'PDC role administrator required' using errcode='42501';
    end if;
  end if;
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
end $r527$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.set_bay_default_technician(uuid,integer,uuid)','51415343720a6d3a02fb2597109db9b1','r527','Operator may set the default technician on Dept 138 and shared Tint/Tyre bays (F141)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('qa_bay_technician_527','F141','Dept 138 QA Bay 07 resolves to BUS_4X4-BAY-07. A planner operator may set that bay default. Department 139 bay defaults and set_workshop_bay_active stay administrator-only. Department 135 is unchanged (r527).',
 $c527$
SELECT
 (SELECT count(*) FROM public.workshop_bays b
   JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE s.code='BUS_4X4' AND b.bay_number IN (5,6,7) AND b.is_active
     AND b.code=s.code||'-BAY-'||lpad(b.bay_number::text,2,'0'))=3
 AND (SELECT display_name FROM public.workshop_bays WHERE id='06bda616-299e-4a63-8650-cff768f46319'::uuid)='QA - Bus4x4 Bay 07'
 AND (SELECT code FROM public.workshop_bays WHERE id='06bda616-299e-4a63-8650-cff768f46319'::uuid)='BUS_4X4-BAY-07'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)='51415343720a6d3a02fb2597109db9b1'
 AND position('s.code in (''BUS_4X4'',''TINT'',''TYRE'')' IN (SELECT prosrc FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure))>0
 AND position('is distinct from ''operator''' IN (SELECT prosrc FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure))>0
 AND position('require_pdc_role' IN (SELECT prosrc FROM pg_proc WHERE oid='public.set_workshop_bay_active(uuid,integer,boolean)'::regprocedure))>0
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_workshop_bay_active(uuid,integer,boolean)'::regprocedure)='fbdf5fefaff3d68c2e2240037ec14064'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)='d07f40a33443eff357d3a9cd58503696'
 AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=236
 AS ok,
 'qa bay 07 and operator technician gate' AS detail
$c527$,
 true, 308, 'r527');

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'51415343720a6d3a02fb2597109db9b1'
 THEN RAISE EXCEPTION 'r527: new body md5 mismatch'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.set_bay_default_technician(uuid,integer,uuid)')<>'51415343720a6d3a02fb2597109db9b1'
 THEN RAISE EXCEPTION 'r527: pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>236 THEN RAISE EXCEPTION 'r527: pin count is not 236'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.set_bay_default_technician(uuid,integer,uuid)'::regprocedure)<>'d07f40a33443eff357d3a9cd58503696'
 THEN RAISE EXCEPTION 'r527: Department 135 function changed'; END IF;
END $p$;
