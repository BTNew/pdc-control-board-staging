-- r415 (F31, resolves F12): a job that was started and then returned to the queue can be re-planned.
-- Decision (Craig, 21 Oct 2026): RESUME. The time already worked and the full history are kept; the re-planned booking
-- covers only the remaining hours; the job's estimate hours are not changed. Keys 203, 225, 235 and 261 are resumed here.
-- Staging only. Undo: supabase/rollbacks/<this name>.down.sql
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r415: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r415: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r415: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r415: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'7edd2a97fb88093a09d3275fb349797f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capture_capacity_basis()'::regprocedure)<>'1c8341ad165c9e968286546387e5374f'
 THEN RAISE EXCEPTION 'r415: the move or capacity function is not the expected version'; END IF;
 IF to_regclass('public.workshop_booking_resume_ledger_415') IS NOT NULL OR to_regprocedure('public.workshop_resume_returned_booking_415(uuid,integer,text)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='started_returned_jobs_replannable') THEN RAISE EXCEPTION 'r415: already applied'; END IF;
END $g$;

CREATE TABLE public.workshop_booking_resume_ledger_415(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 booking_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 stage_id uuid,
 actual_start_at timestamptz NOT NULL,
 returned_to_queue_at timestamptz NOT NULL,
 worked_minutes integer NOT NULL CHECK (worked_minutes>=0),
 stoppage_minutes integer NOT NULL DEFAULT 0,
 base_minutes_before numeric,
 base_minutes_after numeric NOT NULL CHECK (base_minutes_after>=1),
 estimate_minutes integer,
 default_duration_minutes_before integer,
 booking_version_before integer NOT NULL,
 old_capacity_base_minutes numeric,
 old_capacity_efficiency_percent integer,
 old_capacity_estimate_minutes integer,
 metadata_before jsonb,
 actor_id uuid,
 actor_email text,
 source text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(booking_id,actual_start_at,returned_to_queue_at)
);
COMMENT ON TABLE public.workshop_booking_resume_ledger_415 IS 'r415 (F31): time already worked on a started-then-returned job, kept when it is re-planned.';
ALTER TABLE public.workshop_booking_resume_ledger_415 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workshop_booking_resume_ledger_415 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.workshop_booking_resume_ledger_415 TO service_role;

CREATE OR REPLACE FUNCTION public.workshop_resume_returned_booking_415(p_booking_id uuid, p_expected_version integer, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
-- r415 (F31): resume a job that was started, stopped and returned to the queue so it can be re-planned.
-- The time already worked is recorded (ledger, booking metadata and history) and taken off the capacity base,
-- so only the remaining hours are planned. The job's estimate hours are not changed.
DECLARE b public.workshop_bookings%rowtype; v_worked integer; v_base numeric; v_new_base numeric; v_quote integer;
 v_repeat boolean:=false; v_before jsonb; v_after jsonb; v_entry jsonb; v_ctx text:=current_setting('pdc.workshop_resume_415',true);
BEGIN
 IF p_booking_id IS NULL OR p_expected_version IS NULL OR nullif(btrim(p_source),'') IS NULL THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_input');
 END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','booking_not_found'); END IF;
 IF b.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF NOT (b.deleted_at IS NULL AND b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NOT NULL
   AND b.actual_end_at IS NULL AND b.returned_to_queue_at IS NOT NULL) THEN
  RETURN jsonb_build_object('ok',false,'error','protected_booking');
 END IF;
 v_worked:=greatest(0,coalesce(public.workshop_operational_minutes_between(b.actual_start_at,b.returned_to_queue_at),0)
   -coalesce(b.stoppage_accumulated_minutes,0));
 v_base:=public.workshop_booking_capacity_base_minutes(b.id);
 -- An undone move puts the start time back; the same worked period is never taken off twice.
 v_repeat:=EXISTS(SELECT 1 FROM public.workshop_booking_resume_ledger_415 l WHERE l.booking_id=b.id
   AND l.actual_start_at=b.actual_start_at AND l.returned_to_queue_at=b.returned_to_queue_at);
 v_new_base:=CASE WHEN v_repeat THEN greatest(1,coalesce(v_base,b.capacity_base_minutes,1))
   ELSE greatest(1,coalesce(v_base,b.capacity_base_minutes,1)-v_worked) END;
 v_quote:=coalesce(pdc_work_categories_private.minutes(b.id,b.vehicle_id,b.stage_id),b.capacity_estimate_minutes);
 v_entry:=jsonb_build_object('actual_start_at',b.actual_start_at,'returned_to_queue_at',b.returned_to_queue_at,
   'worked_minutes',v_worked,'stoppage_minutes',coalesce(b.stoppage_accumulated_minutes,0),
   'base_minutes_before',v_base,'base_minutes_after',v_new_base,'estimate_minutes',v_quote,
   'default_duration_minutes_before',b.default_duration_minutes,'repeat',v_repeat,
   'resumed_at',clock_timestamp(),'resumed_by',auth.uid(),'source',p_source);
 v_before:=public.workshop_booking_snapshot(b.id);
 PERFORM set_config('pdc.workshop_resume_415',jsonb_build_object('booking',b.id,'base',v_new_base)::text,true);
 UPDATE public.workshop_bookings w SET actual_start_at=NULL,
   capacity_base_minutes=v_new_base,capacity_efficiency_percent=100,capacity_estimate_minutes=v_quote,
   metadata=coalesce(w.metadata,'{}'::jsonb)||jsonb_build_object('pdc_resume_415',
     CASE WHEN jsonb_typeof(w.metadata->'pdc_resume_415')='array' THEN w.metadata->'pdc_resume_415' ELSE '[]'::jsonb END||jsonb_build_array(v_entry)),
   version=w.version+1,updated_by=coalesce(auth.uid(),w.updated_by),updated_at=clock_timestamp()
 WHERE w.id=b.id;
 PERFORM set_config('pdc.workshop_resume_415',coalesce(v_ctx,''),true);
 IF NOT v_repeat THEN
  INSERT INTO public.workshop_booking_resume_ledger_415(booking_id,vehicle_id,stage_id,actual_start_at,returned_to_queue_at,
    worked_minutes,stoppage_minutes,base_minutes_before,base_minutes_after,estimate_minutes,default_duration_minutes_before,
    booking_version_before,old_capacity_base_minutes,old_capacity_efficiency_percent,old_capacity_estimate_minutes,metadata_before,actor_id,actor_email,source)
  VALUES(b.id,b.vehicle_id,b.stage_id,b.actual_start_at,b.returned_to_queue_at,v_worked,coalesce(b.stoppage_accumulated_minutes,0),
    v_base,v_new_base,v_quote,b.default_duration_minutes,b.version,b.capacity_base_minutes,b.capacity_efficiency_percent,b.capacity_estimate_minutes,b.metadata,auth.uid(),public.current_actor_email(),p_source);
 END IF;
 v_after:=public.workshop_booking_snapshot(b.id);
 PERFORM public.workshop_write_history(b.id,'resumed_for_replan',v_before,v_after,v_entry||jsonb_build_object('release','r415'));
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'booking_version',b.version+1,'worked_minutes',v_worked,
   'base_minutes_before',v_base,'base_minutes_after',v_new_base,'repeat',v_repeat);
END $function$;
REVOKE ALL ON FUNCTION public.workshop_resume_returned_booking_415(uuid,integer,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.workshop_capture_capacity_basis()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base numeric; quote integer; efficiency integer; manual integer;
BEGIN
 -- r415 (F31): a resume (or its undo) sets the capacity base itself: the time already worked is not planned again.
 -- Honoured only for the one booking and base value that workshop_resume_returned_booking_415 put in this transaction.
 IF TG_OP='UPDATE' AND NEW.status='queued' AND NEW.bay_id IS NULL AND NEW.deleted_at IS NULL
  AND NEW.capacity_base_minutes IS NOT NULL AND NEW.capacity_base_minutes>=1
  AND coalesce(nullif(current_setting('pdc.workshop_resume_415',true),''),'{}')::jsonb
      @> jsonb_build_object('booking',NEW.id,'base',NEW.capacity_base_minutes) THEN
  RETURN NEW;
 END IF;
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
 v_resumable boolean:=false; v_resume jsonb; v_move_version integer:=p_expected_version;
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
 -- r415 (F31): a job that was started, stopped and returned to the queue is resumed (Craig, 21 Oct 2026): the time already
 -- worked is kept (booking history and workshop_booking_resume_ledger_415) and only the remaining hours are planned.
 -- Started, stopped, completed and deleted bookings stay protected.
 v_resumable:=v_booking.deleted_at is null and v_booking.status='queued' and v_booking.bay_id is null
   and v_booking.actual_start_at is not null and v_booking.actual_end_at is null and v_booking.returned_to_queue_at is not null;
 if not v_resumable and (v_booking.deleted_at is not null or v_booking.status not in('queued','planned') or v_booking.actual_start_at is not null or v_booking.actual_end_at is not null) then return jsonb_build_object('ok',false,'error','protected_booking'); end if;
 select id into v_target_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_target_bay from public.workshop_bays where stage_id=v_target_stage and bay_number=p_bay_number and is_active;
 if v_target_stage is null or v_target_bay is null then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-move:'||p_booking_id::text,0));
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into v_ids from public.workshop_bookings x
 where x.id=p_booking_id or (x.deleted_at is null and x.status in('queued','planned') and x.bay_id in(v_booking.bay_id,v_target_bay));
 perform 1 from public.workshop_bookings x where x.id=any(v_ids) order by x.id for update;
 v_before:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 begin
 -- r415 (F31): resume and move are one step; if the move is refused the resume is rolled back too.
 if v_resumable then
   v_resume:=public.workshop_resume_returned_booking_415(p_booking_id,p_expected_version,'administrator_move');
   if coalesce((v_resume->>'ok')::boolean,false) is not true then v_result:=v_resume; raise exception 'r415: resume not applied' using errcode='P0415'; end if;
   v_move_version:=(v_resume->>'booking_version')::integer;
 end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.move_workshop_booking(p_booking_id,v_move_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_override_reason,
     coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if v_resumable and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;
 exception when sqlstate 'P0415' then return v_result;
 end;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move')
   ||case when v_resumable then jsonb_build_object('resumed',v_resume) else '{}'::jsonb end;
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

-- Resume the jobs already waiting (Keys 203, 225, 235, 261 when prepared). None is scheduled here.
-- Recorded under the approving administrator's account (decision 21 Oct 2026), source r415_migration.
DO $r$ DECLARE x record; v jsonb; v_claims text:=current_setting('request.jwt.claims',true); BEGIN
 -- Public copy: the approving administrator's claims are supplied at run time (staging used the release owner's account).
 IF coalesce(current_setting('pdc.release_actor_claims',true),'')='' THEN RAISE EXCEPTION 'r415: set pdc.release_actor_claims to the approving administrator''s JWT claims first'; END IF;
 PERFORM set_config('request.jwt.claims',current_setting('pdc.release_actor_claims'),true);
 FOR x IN SELECT id,version FROM public.workshop_bookings WHERE deleted_at IS NULL AND status='queued' AND bay_id IS NULL
   AND actual_start_at IS NOT NULL AND actual_end_at IS NULL AND returned_to_queue_at IS NOT NULL ORDER BY id LOOP
  v:=public.workshop_resume_returned_booking_415(x.id,x.version,'r415_migration');
  IF coalesce((v->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'r415: resume failed for %: %',x.id,v; END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_claims,''),true);
END $r$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT x.sig,md5(p.prosrc),'r415','F31: started-then-returned jobs resume for re-planning',now()
FROM (VALUES('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'),
 ('public.workshop_capture_capacity_basis()'),('public.workshop_resume_returned_booking_415(uuid,integer,text)')) x(sig)
JOIN pg_proc p ON p.oid=x.sig::regprocedure
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=excluded.updated_at
 WHERE expected_function_md5.signature=excluded.signature; -- no-op WHERE for the safeupdate lint; applied text ended before it

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in)
VALUES('started_returned_jobs_replannable','F31',
 'A job started and then returned to the queue can be re-planned: the move resumes it, the time worked is kept in the ledger and history, and the capacity base stays at least 1 minute.',
 $c$with fx as (
  select
   (select prosrc like '%workshop_resume_returned_booking_415%' and prosrc like '%v_resumable%' from pg_proc where oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'::regprocedure) move_resumes,
   (select prosrc like '%pdc.workshop_resume_415%' from pg_proc where oid='public.workshop_capture_capacity_basis()'::regprocedure) basis_honours_resume,
   (select not has_function_privilege('authenticated','public.workshop_resume_returned_booking_415(uuid,integer,text)','EXECUTE')
       and not has_function_privilege('anon','public.workshop_resume_returned_booking_415(uuid,integer,text)','EXECUTE')) resume_internal_only
), led as (
  select count(*) n,
   count(*) filter (where not exists(select 1 from public.workshop_booking_history h where h.booking_id=l.booking_id and h.event_type='resumed_for_replan'
      and h.metadata->>'actual_start_at' is not null and (h.metadata->>'actual_start_at')::timestamptz=l.actual_start_at)) missing_history,
   count(*) filter (where l.base_minutes_after<1 or l.worked_minutes<0) bad_numbers
  from public.workshop_booking_resume_ledger_415 l
), waiting as (
  select count(*) n from public.workshop_bookings b where b.deleted_at is null and b.status='queued' and b.bay_id is null
   and b.actual_start_at is not null and b.actual_end_at is null and b.returned_to_queue_at is not null
)
select jsonb_build_object('ok',fx.move_resumes and fx.basis_honours_resume and fx.resume_internal_only and led.missing_history=0 and led.bad_numbers=0,
  'detail',jsonb_build_object('move_resumes',fx.move_resumes,'basis_honours_resume',fx.basis_honours_resume,'resume_internal_only',fx.resume_internal_only,
   'resumed',led.n,'missing_history',led.missing_history,'bad_numbers',led.bad_numbers,'returned_waiting_for_replan',waiting.n))
from fx,led,waiting$c$,true,216,'r415');

DO $v$ DECLARE c jsonb; BEGIN
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='started_returned_jobs_replannable') INTO c;
 IF coalesce((c->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'r415: check failed %',c; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE proname='workshop_clock_tick' AND pronamespace='public'::regnamespace)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r415: clock tick changed'; END IF;
END $v$;
