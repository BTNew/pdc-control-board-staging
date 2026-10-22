-- r469 (F82): staging rolled-back proof. Runs the real drag path (cascade_workshop_schedule 'insert', as the planner's
-- Unallocated drag does through administrator_schedule_workshop_vehicle) as a real controller account, for a real vehicle
-- that has no bookings, into the first free time in every Fitting bay that has a later planned booking. Every drop must
-- book, move NO other booking (the pre-r469 rule pushed every later booking and failed with vehicle_overlap), and every
-- booking row except the new ones must be byte-identical afterwards. Nothing is kept: the whole transaction rolls back.
-- Run between :02 and :45 (the clock tick runs at :00). Staging only. No identifiers are written to Git.
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- other sessions (clock tick, planners) cannot change the snapshot under the byte-compare
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='120s';
DO $test$
DECLARE actor uuid; actor_email text; veh record; bay record; d integer; t timestamptz; r jsonb; before_md5 text; after_md5 text;
 tried integer:=0; booked integer:=0;
BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'run between :02 and :45'; END IF;
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF to_regnamespace('pdc_cascade_private') IS NULL THEN RAISE EXCEPTION 'r469 is not applied'; END IF;
 SELECT auth_user_id,email INTO STRICT actor,actor_email FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='operator'
  AND email!~* '(monitor|auditor|bot|service|import|hermes)' ORDER BY created_at LIMIT 1;
 PERFORM set_config('request.jwt.claims',json_build_object('sub',actor,'role','authenticated','email',actor_email)::text,true);
 SELECT md5(string_agg(to_jsonb(b)::text,'|' ORDER BY b.id)) INTO before_md5 FROM public.workshop_bookings b;
 SELECT v.id, v.version INTO veh FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN ('PMB','YH')
   AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed AND public.workshop_stage_code_for_work_key(wi.work_key)='FITTING')
   AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews rv WHERE rv.vehicle_id=v.id AND rv.status='pending')
  ORDER BY v.id LIMIT 1;
 IF veh.id IS NULL THEN RAISE EXCEPTION 'no unbooked Fitting vehicle available as a read-only probe'; END IF;
 PERFORM pdc_work_categories_private.set_context(veh.id,'FITTING','{}'::jsonb);
 FOR bay IN SELECT wb.id, wb.bay_number, wb.stage_id FROM public.workshop_bays wb JOIN public.workshop_stages s ON s.id=wb.stage_id
   WHERE s.code='FITTING' AND wb.is_active AND NOT wb.is_sublet_row ORDER BY wb.bay_number LOOP
  d:=public.workshop_booking_capacity_duration_minutes(NULL,veh.id,bay.stage_id,bay.id);
  CONTINUE WHEN d IS NULL OR NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.bay_id=bay.id AND b.status='planned' AND b.deleted_at IS NULL AND b.scheduled_start_at>now());
  -- First free window of d operational minutes from tomorrow 07:30 Perth that ends before the next booking in this bay.
  SELECT x.t INTO t FROM (
    SELECT public.workshop_next_calendar_window(greatest(coalesce(lag(public.workshop_booking_effective_end_at(b.id)) OVER w, now()+interval '1 day'), now()+interval '1 day'), d) t,
           b.scheduled_start_at nxt
    FROM public.workshop_bookings b WHERE b.bay_id=bay.id AND b.deleted_at IS NULL AND b.status IN ('planned','started','stoppage')
      AND public.workshop_booking_effective_end_at(b.id)>now()
    WINDOW w AS (ORDER BY b.scheduled_start_at, b.id)) x
   WHERE x.t IS NOT NULL AND public.workshop_add_operational_minutes(x.t,d)<=x.nxt ORDER BY x.t LIMIT 1;
  CONTINUE WHEN t IS NULL;
  tried:=tried+1;
  BEGIN
   r:=public.cascade_workshop_schedule('insert',veh.id,veh.version,'FITTING',bay.bay_number,t,d,NULL,d,NULL,'{"source":"r469_rolled_back_test"}'::jsonb);
   IF coalesce(r->>'ok','')<>'true' THEN RAISE EXCEPTION 'Fitting bay % free-time drop refused: %',bay.bay_number,r; END IF;
   IF coalesce((r->>'shifted_count')::int,-1)<>0 THEN RAISE EXCEPTION 'Fitting bay % free-time drop pushed % booking(s)',bay.bay_number,r->>'shifted_count'; END IF;
   SELECT md5(string_agg(to_jsonb(b)::text,'|' ORDER BY b.id)) INTO after_md5 FROM public.workshop_bookings b WHERE b.id<>(r->'booking'->>'booking_id')::uuid;
   IF after_md5 IS DISTINCT FROM before_md5 THEN RAISE EXCEPTION 'Fitting bay %: an existing booking changed during a free-time drop',bay.bay_number; END IF;
   RAISE EXCEPTION 'r469_probe_ok';  -- undo this probe booking (subtransaction) so the next bay sees the vehicle unbooked
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'r469_probe_ok' THEN RAISE; END IF;
   booked:=booked+1;
  END;
 END LOOP;
 IF tried=0 THEN RAISE EXCEPTION 'no Fitting bay with a later planned booking and free time to probe'; END IF;
 RAISE NOTICE 'r469: % free-time drops on % Fitting bays booked, 0 bookings moved, existing bookings byte-identical (rolled back)',booked,tried;
END $test$;
ROLLBACK;
