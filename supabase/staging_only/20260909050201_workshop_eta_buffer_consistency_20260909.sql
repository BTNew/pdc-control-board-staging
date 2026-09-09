-- STAGING ONLY: enforce the existing ETA + 7 rule on lower-level booking paths.
-- No existing booking is moved, cancelled, or rewritten by this migration.
DO $migration$
DECLARE d text; patched text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'STAGING only';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:staging:audit-priority-20260909',0));
 SELECT pg_get_functiondef('public.workshop_enforce_vehicle_eta()'::regprocedure) INTO d;
 IF md5(d)<>'87af40fb17f46963419b3e197f3fd55d' THEN RAISE EXCEPTION 'ETA trigger changed since review'; END IF;
 patched:=replace(d,'::date<v_vehicle.eta_to_kewdale then','::date<v_vehicle.eta_to_kewdale+7 then');
 patched:=replace(patched,'booking_before_eta earliest_permitted_date=%','booking_before_eta_plus_seven earliest_permitted_date=%');
 patched:=replace(patched,'v_vehicle.eta_to_kewdale using errcode','v_vehicle.eta_to_kewdale+7 using errcode');
 IF patched=d OR position('::date<v_vehicle.eta_to_kewdale+7 then' in patched)=0 THEN RAISE EXCEPTION 'ETA trigger repair mismatch'; END IF;
 EXECUTE patched;

 SELECT pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) INTO d;
 IF md5(d)<>'3588c164c1c03f2109735f6cbb85c380' THEN RAISE EXCEPTION 'Booking validator changed since review'; END IF;
 patched:=replace(d,'v_local_date<v_vehicle.eta_to_kewdale then','v_local_date<v_vehicle.eta_to_kewdale+7 then');
 patched:=replace(patched,'''error'',''it_before_eta''','''error'',''it_before_eta_plus_seven'',''earliest_permitted_date'',v_vehicle.eta_to_kewdale+7');
 IF patched=d OR position('v_local_date<v_vehicle.eta_to_kewdale+7 then' in patched)=0 THEN RAISE EXCEPTION 'Booking validator repair mismatch'; END IF;
 EXECUTE patched;

 SELECT pg_get_functiondef('public.workshop_refresh_eta_risk()'::regprocedure) INTO d;
 IF md5(d)<>'0ab98615679e11e0c2d2940c8aa531a7' THEN RAISE EXCEPTION 'ETA risk projection changed since review'; END IF;
 patched:=replace(d,
 'v_new_status:=case when new.eta_to_kewdale is null or (v_booking.scheduled_start_at at time zone ''Australia/Perth'')::date<new.eta_to_kewdale then ''at_risk'' else ''none'' end;',
 'v_new_status:=case when upper(btrim(coalesce(new.current_location,'''')))<>''IT'' then ''none'' when new.eta_to_kewdale is null or (v_booking.scheduled_start_at at time zone ''Australia/Perth'')::date<new.eta_to_kewdale+7 then ''at_risk'' else ''none'' end;');
 IF patched=d THEN RAISE EXCEPTION 'ETA risk repair mismatch'; END IF;
 EXECUTE patched;
END $migration$;