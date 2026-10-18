-- Keep free-slot inserts scoped to the new booking while preserving receipt replay.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL OR NOT pdc_codex_intake_private.management_connection() THEN RAISE EXCEPTION 'staging_management_required'; END IF;
IF md5(replace(pg_get_functiondef('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure),chr(13),'')) <> '0e6e960721cf74c178b86aba215ae1f0' THEN RAISE EXCEPTION 'reviewed_administrator_schedule_changed'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION public.administrator_schedule_workshop_vehicle(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 previous_context text:=current_setting('pdc.work_category',true);
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_stage uuid; v_bay uuid; v_result jsonb; v_booking_id uuid; v_booking_version integer; v_receipt uuid;
 v_ids_before uuid[]; v_ids_after uuid[]; v_before jsonb; v_after jsonb; v_intent jsonb; v_hash text; v_intent_hash_source text;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 perform pdc_work_categories_private.set_context(p_vehicle_id,p_stage_code,p_metadata);
 if p_request_id is null or p_vehicle_id is null or p_vehicle_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','create','vehicle_id',p_vehicle_id,'vehicle_expected_version',p_vehicle_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'technician_id',p_technician_id,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,true));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then
     raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
   end if;
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select id into v_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_bay from public.workshop_bays where stage_id=v_stage and bay_number=p_bay_number and is_active;
 if v_stage is null or v_bay is null then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-create:'||p_vehicle_id::text,0));
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 if p_cascade then
 select coalesce(array_agg(b.id order by b.id),'{}'::uuid[]) into v_ids_before from public.workshop_bookings b
 where b.deleted_at is null and b.status='planned' and b.bay_id=v_bay and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
 perform 1 from public.workshop_bookings b where b.id=any(v_ids_before) order by b.id for update;
 else
  -- A free-slot insert cannot alter later bay bookings; its receipt owns only the new booking.
  v_ids_before:='{}'::uuid[];
 end if;
 v_before:=public.workshop_admin_state_244(v_ids_before,p_vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_schedule('insert',p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,p_duration_minutes,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.schedule_vehicle_work(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return v_result; end if;
 v_booking_id:=nullif(v_result->'booking'->>'booking_id','')::uuid;
 if v_booking_id is null then raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_MISSING' using errcode='55000'; end if;
 if not exists(select 1 from public.workshop_bookings where id=v_booking_id and vehicle_id=p_vehicle_id and stage_id=v_stage) then
   raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_INVALID' using errcode='55000';
 end if;
 v_ids_after:=array(select distinct x from unnest(v_ids_before||array[v_booking_id]) x order by x);
 v_after:=public.workshop_admin_state_244(v_ids_after,p_vehicle_id);
 select version into v_booking_version from public.workshop_bookings where id=v_booking_id;
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),v_booking_id,p_vehicle_id,'create',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_unallocated_drag'),80),nullif(left(btrim(coalesce(p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 perform set_config('pdc.work_category',coalesce(previous_context,''),true);
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$
;
