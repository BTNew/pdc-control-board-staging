-- Undo r424 (F38): put administrator_move_workshop_booking and its pin back exactly as before, remove the bay re-order
-- and undo functions, the r424 check and the private schema (plans, receipts, stopped-job log). Bookings already
-- re-ordered, pushed back or re-planned after a stoppage stay where they are; their history rows remain.
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r424 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r424 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure)
    IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE release='r424' AND signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')
    OR to_regnamespace('pdc_bay_seq_private') IS NULL
 THEN RAISE EXCEPTION 'r424 undo: the r424 functions are not the released version'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype; v_booking public.workshop_bookings%rowtype;
 v_target_stage uuid; v_target_bay uuid; v_ids uuid[]; v_before jsonb; v_after jsonb; v_result jsonb; v_receipt uuid; v_intent jsonb; v_hash text;
 v_resumable boolean:=false; v_resume jsonb; v_move_version integer:=p_expected_version; v_rules jsonb:='[]'::jsonb;
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
 -- r417 (F32): a bay category or vehicle rule that does not match warns instead of refusing. The planner confirms
 -- (metadata bay_rule_confirm.rules) and the override is logged in pdc_bay_rules_private.overrides.
 v_rules:=pdc_bay_rules_private.mismatches(v_booking.vehicle_id,v_booking.work_category,v_target_bay);
 if jsonb_array_length(v_rules)>0 then
   if not pdc_bay_rules_private.confirmed(v_rules,p_metadata) then return pdc_bay_rules_private.warning(v_rules); end if;
   perform pdc_bay_rules_private.log_pending(v_rules,v_booking.vehicle_id,p_booking_id,v_target_bay,v_booking.work_category,'move',p_metadata);
 end if;
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
 exception when sqlstate 'P0415' then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result);
 end;
 if coalesce((v_result->>'ok')::boolean,false) is not true then return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result); end if;
 v_after:=public.workshop_admin_state_244(v_ids,v_booking.vehicle_id);
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',p_booking_id,'booking_version',(select version from public.workshop_bookings where id=p_booking_id),'operation_type','move')
   ||case when v_resumable then jsonb_build_object('resumed',v_resume) else '{}'::jsonb end;
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),p_booking_id,v_booking.vehicle_id,'move',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_drag_drop'),80),nullif(left(btrim(coalesce(p_override_reason,p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 return pdc_bay_rules_private.finish(v_rules,p_booking_id,v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false));
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true); end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r424';
INSERT INTO pdc_ops.expected_function_md5 SELECT * FROM pdc_bay_seq_private.before_424_pins ON CONFLICT (signature) DO NOTHING;
DELETE FROM pdc_ops.regression_checks WHERE check_name='bay_resequence_and_stopped_replan' AND added_in='r424';
DROP FUNCTION public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid);
DROP FUNCTION public.workshop_undo_bay_resequence_424(uuid,uuid);
DROP SCHEMA pdc_bay_seq_private CASCADE;

DO $v$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure)<>'0f5bff8fba5c0a3385609c893a5edc44'
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')<>'0f5bff8fba5c0a3385609c893a5edc44'
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r424') OR to_regprocedure('public.workshop_resequence_bay_424(uuid,integer,uuid,text,boolean,text,jsonb,uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'r424 undo: not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r424 undo: clock tick changed'; END IF;
END $v$;
