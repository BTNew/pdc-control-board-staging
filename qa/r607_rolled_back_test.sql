-- r607 (F221) rolled-back test. Run AFTER the migration text in the same transaction; it always
-- ends with RAISE so everything (migration included) rolls back. Start between :02 and :15.
DO $t607$
DECLARE
  def text; r jsonb; outp text := '';
  craig jsonb := jsonb_build_object('sub','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','role','authenticated','email','craig.watson@broometoyota.com.au');
  veh uuid := '7cb322ae-f47d-4e77-ba46-212358001ec8';
  jason uuid := 'bdc89698-9786-4aab-99b5-7e17c2f8df64';
  vver integer;
BEGIN
  outp := outp || ' | 460 real length ' || public.workshop_booking_effective_duration_minutes('0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd')
       || ' ends ' || to_char(public.workshop_booking_effective_end_at('0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd') AT TIME ZONE 'Australia/Perth','DD HH24:MI');
  -- The website wrapper requires a real website session (session_user authenticator). Test a temp copy
  -- that skips only that one check; every other line is the patched body.
  def := pg_get_functiondef('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure);
  def := replace(def, 'FUNCTION public.administrator_schedule_workshop_vehicle(', 'FUNCTION pg_temp.t607_schedule(');
  def := replace(def, ' perform pdc_planner_access_private.require_vehicle_planner();', ' -- website session check skipped in this test');
  EXECUTE def;
  PERFORM set_config('request.jwt.claims', craig::text, true);
  SELECT version INTO vver FROM public.vehicles WHERE id=veh;

  -- a) drop on the running Key 460 at 14:00 today: placed right after it.
  BEGIN
    r := pg_temp.t607_schedule(veh, vver, 'HOIST', 2, '2026-10-28 14:00+08', 300, jason,
      '{"source":"admin_unallocated_vehicle_pill","reason":"website_drag_drop"}'::jsonb, gen_random_uuid(), true);
    outp := outp || ' | a ok=' || coalesce(r->>'ok','?') || ' err=' || coalesce(r->>'error','') || ' placement=' || coalesce(r->>'placement','')
      || ' at ' || coalesce(to_char((r->>'placed_start_at')::timestamptz AT TIME ZONE 'Australia/Perth','DD HH24:MI'),'') || ' shifted=' || coalesce(r->>'shifted_count','');
    RAISE EXCEPTION 'undo_a';
  EXCEPTION WHEN OTHERS THEN IF sqlerrm <> 'undo_a' THEN outp := outp || ' | a EXC ' || left(sqlerrm,200); END IF;
  END;

  -- b) drop inside planned Key 365 (Thu 09:15-16:15) at Thu 10:00: takes its start, 365 onward move back.
  BEGIN
    r := pg_temp.t607_schedule(veh, vver, 'HOIST', 2, '2026-10-29 10:00+08', 300, jason,
      '{"source":"admin_unallocated_vehicle_pill","reason":"website_drag_drop"}'::jsonb, gen_random_uuid(), true);
    outp := outp || ' | b ok=' || coalesce(r->>'ok','?') || ' err=' || coalesce(r->>'error','') || ' placement=' || coalesce(r->>'placement','')
      || ' at ' || coalesce(to_char((r->>'placed_start_at')::timestamptz AT TIME ZONE 'Australia/Perth','DD HH24:MI'),'') || ' shifted=' || coalesce(r->>'shifted_count','');
    RAISE EXCEPTION 'undo_b';
  EXCEPTION WHEN OTHERS THEN IF sqlerrm <> 'undo_b' THEN outp := outp || ' | b EXC ' || left(sqlerrm,200); END IF;
  END;

  outp := outp || ' | pins ' || (SELECT count(*) FROM pdc_ops.expected_function_md5)
    || ' | wrapper ' || (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure)
    || ' | trigger ' || (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capture_capacity_basis()'::regprocedure)
    || ' | at ' || to_char(clock_timestamp() AT TIME ZONE 'Australia/Perth','HH24:MI:SS');
  RAISE EXCEPTION 'R607_RESULT%', outp;
END $t607$;
