-- Undo r415 (F31): put back the move and capacity functions exactly as before, and put the jobs r415 itself resumed
-- (Keys 203, 225, 235, 261) back to "started and returned to the queue" if nobody has re-planned them since.
-- Jobs a planner already re-planned after r415 stay as planned; their history and ledger rows remain in workshop_booking_history.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r415 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r415 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'acb09f07d4bc59ecb1cb75c6f87d78ba'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capture_capacity_basis()'::regprocedure)<>'7dcc9b114f5484722febaa769253d54b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_resume_returned_booking_415(uuid,integer,text)'::regprocedure)<>'870cd66b8511239f449defc8615686ee'
 THEN RAISE EXCEPTION 'r415 undo: the r415 functions are not the released version'; END IF;
END $g$;

DO $u$ DECLARE l record; v_before jsonb; v_ctx text:=current_setting('pdc.workshop_resume_415',true); v_claims text:=current_setting('request.jwt.claims',true); BEGIN
 -- Public copy: the approving administrator's claims are supplied at run time (staging used the release owner's account).
 IF coalesce(current_setting('pdc.release_actor_claims',true),'')='' THEN RAISE EXCEPTION 'r415: set pdc.release_actor_claims to the approving administrator''s JWT claims first'; END IF;
 PERFORM set_config('request.jwt.claims',current_setting('pdc.release_actor_claims'),true);
 FOR l IN SELECT x.* FROM public.workshop_booking_resume_ledger_415 x JOIN public.workshop_bookings b ON b.id=x.booking_id
   WHERE x.source='r415_migration' AND b.deleted_at IS NULL AND b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL
     AND b.version=x.booking_version_before+1 ORDER BY x.booking_id FOR UPDATE OF b LOOP
  v_before:=public.workshop_booking_snapshot(l.booking_id);
  PERFORM set_config('pdc.workshop_resume_415',jsonb_build_object('booking',l.booking_id,'base',l.old_capacity_base_minutes)::text,true);
  UPDATE public.workshop_bookings SET actual_start_at=l.actual_start_at,capacity_base_minutes=l.old_capacity_base_minutes,
    capacity_efficiency_percent=l.old_capacity_efficiency_percent,capacity_estimate_minutes=l.old_capacity_estimate_minutes,
    metadata=coalesce(l.metadata_before,'{}'::jsonb),version=version+1,updated_at=clock_timestamp() WHERE id=l.booking_id;
  PERFORM set_config('pdc.workshop_resume_415',coalesce(v_ctx,''),true);
  PERFORM public.workshop_write_history(l.booking_id,'resume_undone_r415',v_before,public.workshop_booking_snapshot(l.booking_id),jsonb_build_object('release','r415','undo',true));
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_claims,''),true);
END $u$;

CREATE OR REPLACE FUNCTION public.workshop_capture_capacity_basis()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base numeric; quote integer; efficiency integer; manual integer;
BEGIN
 -- Completed/live history and its applied duration stay fixed.
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned') THEN
  IF TG_OP='UPDATE' THEN
   NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
   NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
   NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.status='queued' AND NEW.bay_id IS NULL
  AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  AND NEW.default_duration_minutes=OLD.default_duration_minutes
  AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.vehicle_id IS NOT DISTINCT FROM OLD.vehicle_id
  AND NEW.stage_id IS NOT DISTINCT FROM OLD.stage_id AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
  AND NEW.scheduled_start_at IS NOT DISTINCT FROM OLD.scheduled_start_at
  AND NEW.scheduled_end_at IS NOT DISTINCT FROM OLD.scheduled_end_at
  AND NEW.default_duration_minutes IS NOT DISTINCT FROM OLD.default_duration_minutes
  AND OLD.capacity_base_minutes IS NOT NULL
  AND coalesce((SELECT efficiency_percent FROM public.workshop_bays WHERE id=NEW.bay_id),100)=OLD.capacity_efficiency_percent THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 quote:=pdc_work_categories_private.minutes(NEW.id,NEW.vehicle_id,NEW.stage_id);
 SELECT coalesce(b.efficiency_percent,100) INTO efficiency FROM (SELECT 1) one LEFT JOIN public.workshop_bays b ON b.id=NEW.bay_id;
 base:=CASE WHEN TG_OP='UPDATE' AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  THEN public.workshop_booking_capacity_base_minutes(OLD.id) ELSE quote END;
 IF TG_OP='INSERT' AND NEW.work_category IS NULL AND pdc_bus_private.active_vehicle(NEW.vehicle_id) THEN
  SELECT greatest(1,quote-coalesce(round(sum((l->>'saved_hours')::numeric)*60),0)) INTO base
  FROM jsonb_array_elements(pdc_bus_private.supplier_lines(NEW.vehicle_id)) l
  WHERE l->>'stage_code'=(SELECT code FROM public.workshop_stages WHERE id=NEW.stage_id)
  AND jsonb_typeof(l->'saved_hours')='number';
 END IF;
 manual:=public.workshop_capacity_manual_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id,NEW.default_duration_minutes);
 IF manual IS NOT NULL AND manual IS DISTINCT FROM public.workshop_capacity_duration_minutes(base,NEW.bay_id) THEN
  base:=manual::numeric*efficiency/100;
 END IF;
 IF base IS NOT NULL THEN
  NEW.capacity_base_minutes:=base;
  NEW.capacity_efficiency_percent:=efficiency;
  NEW.capacity_estimate_minutes:=quote;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype;
 v_target_stage uuid; v_target_bay uuid; v_ids uuid[]; v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid; v_intent jsonb; v_hash text;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 if p_request_id is null or p_booking_id is null or p_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','move','booking_id',p_booking_id,'expected_version',p_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'override_reason',p_override_reason,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,false));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023'; end if;
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null then return jsonb_build_object('ok',false,'error','protected_booking'); end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into v_ids from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 perform 1 from public.workshop_bookings x where x.id=any(v_ids) order by x.id for update;
 v_before:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.move_workshop_booking(p_booking_id,p_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_booking.vehicle_id,'move',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80),nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

DROP FUNCTION public.workshop_resume_returned_booking_415(uuid,integer,text);
DROP TABLE public.workshop_booking_resume_ledger_415;
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r415' AND signature IN(
 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)',
 'public.workshop_capture_capacity_basis()','public.workshop_resume_returned_booking_415(uuid,integer,text)');
DELETE FROM pdc_ops.regression_checks WHERE check_name='started_returned_jobs_replannable';

DO $v$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'7edd2a97fb88093a09d3275fb349797f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capture_capacity_basis()'::regprocedure)<>'1c8341ad165c9e968286546387e5374f'
    OR to_regprocedure('public.workshop_resume_returned_booking_415(uuid,integer,text)') IS NOT NULL
    OR to_regclass('public.workshop_booking_resume_ledger_415') IS NOT NULL
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6'
 THEN RAISE EXCEPTION 'r415 undo: verification failed'; END IF;
END $v$;
