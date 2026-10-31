-- Rollback for r773 (F431). Restores the r830 sweep body exactly and drops the r773 helpers.
-- Bookings already cleared stay cleared: each one is in pdc_ops.r746_cleared_bookings (source r773_*) with its
-- before_booking row if one has to be put back.
SET LOCAL lock_timeout = '6s';
DO $pre$
BEGIN
  IF to_regprocedure('pdc_work_categories_private.no_work_station_bookings_773(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'r773 rollback: r773 is not applied'; END IF;
END $pre$;

DELETE FROM pdc_ops.regression_checks WHERE check_name = 'no_work_station_bookings_773' AND added_in = 'r773';

CREATE OR REPLACE FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_ids uuid[];
  v_stages text[];
  v_n integer := 0;
  v_stage text;
  v_actor uuid;
  v_email text;
  v_original_claims text := current_setting('request.jwt.claims', true);
BEGIN
  -- r830 (F390): safety net for r746. Every minute, a queued / planned booking on a station whose lines are all ticked
  -- is cleared, in case the tick trigger missed it (13073056 FITTING, 30 Oct 2026).
  v_ids := ARRAY(SELECT DISTINCT vehicle_id FROM public.workshop_bookings
                 WHERE deleted_at IS NULL AND status IN ('queued','planned'));
  IF pg_catalog.cardinality(v_ids) = 0 THEN RETURN 0; END IF;

  SELECT pg_catalog.array_agg(DISTINCT d.stage_code), pg_catalog.array_agg(DISTINCT d.vehicle_id)
    INTO v_stages, v_ids
  FROM pdc_work_categories_private.done_planner_stations_746(v_ids) d
  JOIN public.workshop_bookings wb ON wb.vehicle_id = d.vehicle_id AND wb.stage_id = d.stage_id
   AND wb.deleted_at IS NULL AND wb.status IN ('queued','planned');
  IF v_ids IS NULL THEN RETURN 0; END IF;

  -- Cron has no user: act as the workshop system actor (as workshop_sync_vehicle_stage_booking_duration does), because
  -- workshop_booking_history needs an actor.
  IF auth.uid() IS NULL THEN
    SELECT r.auth_user_id, r.email INTO v_actor, v_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id = r.auth_user_id
    WHERE r.active AND r.account_status = 'approved' AND r.role = 'administrator' AND r.auth_user_id IS NOT NULL
    ORDER BY r.created_at, r.id LIMIT 1;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PDC_830_SYSTEM_ACTOR_MISSING' USING errcode = '55000'; END IF;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'email', v_email, 'role', 'authenticated')::text, true);
  END IF;

  v_n := pdc_work_categories_private.clear_done_station_bookings_746(v_ids, 'r830_sweep');
  IF v_n > 0 THEN
    FOREACH v_stage IN ARRAY v_stages LOOP
      PERFORM public.workshop_bump_station_revision(v_stage);
    END LOOP;
  END IF;
  PERFORM set_config('request.jwt.claims', coalesce(v_original_claims, ''), true);
  RETURN v_n;
END
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830() FROM PUBLIC, anon, authenticated;

DROP FUNCTION pdc_work_categories_private.clear_no_work_station_bookings_773(uuid[], text);
DROP FUNCTION pdc_work_categories_private.no_work_station_bookings_773(uuid[]);

DO $post$
BEGIN
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.sweep_done_station_bookings_830()'::regprocedure)) <> '8f937836105c82f6de70477701c69409'
  THEN RAISE EXCEPTION 'r773 rollback: r830 sweep body not restored exactly'; END IF;
END $post$;
