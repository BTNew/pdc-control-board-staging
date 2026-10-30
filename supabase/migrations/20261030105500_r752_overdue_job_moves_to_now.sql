-- r752 (F357) / sort 463. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 10:43: "CASCADE IS WRONG AGAIN ... fix asap". Tyre Bay 01 showed its seven planned jobs starting at 11:00
-- with the clock at 10:43 and the bay idle. Since r431 (F49, 21 Oct) workshop_clock_plan moved an overdue planned job to
-- the next 30 minute mark (clock_overdue_step_minutes default 30) to save re-writes: at 10:00:00 the 10:00 job jumped to
-- 10:30, at 10:30:00 to 11:00, each time carrying the queue with it, so the bay sat ahead of the clock. 222 such steps
-- happened across the board today. Nothing released today touched the clock; the queue simply hit the :00 / :30 marks.
-- Fix: the documented setting goes to 1 (move to the next minute). workshop_clock_tick already ignores a move under
-- 15 minutes (r552), so an overdue job now slides to "now" once it is 15 minutes late, and the board is rewritten
-- at most every 15 minutes per bay instead of every minute. The Tyre queue was pulled back to 10:48 by hand (seven
-- move_workshop_booking calls, source r752_pull_to_now). Both clock functions keep their r737 md5 pins.
-- Rollback: supabase/rollbacks/20261030105500_r752_overdue_job_moves_to_now.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $pre752$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r752: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 463 OR fault_id = 'F357' OR added_in = 'r752') THEN RAISE EXCEPTION 'r752: sort 463 or F357 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_plan(jsonb,jsonb,timestamptz)'::regprocedure) <> '58384098be842b62c87b0fa374a15bb6'
    THEN RAISE EXCEPTION 'r752: workshop_clock_plan is not the body this was written against'; END IF;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.workshop_clock_plan(jsonb,jsonb,timestamptz)'::regprocedure), $k$key='clock_overdue_step_minutes'$k$) = 0
    THEN RAISE EXCEPTION 'r752: the plan does not read clock_overdue_step_minutes'; END IF;
END $pre752$;

-- Applied by hand 30 Oct 10:47 AWST ahead of this file (fix asap); the insert is idempotent.
INSERT INTO public.workshop_settings (key, value, scope) VALUES ('clock_overdue_step_minutes', to_jsonb(1), 'global')
ON CONFLICT (key) DO UPDATE SET value = to_jsonb(1), version = public.workshop_settings.version + 1, updated_at = clock_timestamp()
WHERE public.workshop_settings.value IS DISTINCT FROM to_jsonb(1);

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, added_in, enabled, sort_order, description, check_sql) VALUES ('overdue_job_moves_to_now_752', 'F357', 'r752', true, 463,
 'Clock (r752): an overdue planned job moves to now, never to a step mark ahead of the clock. The setting is 1 and no clock move since the fix put an overdue planned job more than 16 minutes past the clock.',
$chk752$
SELECT (SELECT value = to_jsonb(1) FROM public.workshop_settings WHERE key = 'clock_overdue_step_minutes')
  AND NOT EXISTS (
    SELECT 1 FROM public.workshop_clock_history h
    WHERE h.clock_at > greatest(now() - interval '1 day', '2026-10-30 10:50+08'::timestamptz)
      AND h.before_data->>'status' = 'planned' AND nullif(h.before_data->>'actual_start_at', '') IS NULL
      AND (h.before_data->>'scheduled_start_at')::timestamptz <= h.clock_at
      AND (h.after_data->>'scheduled_start_at')::timestamptz > h.clock_at + interval '16 minutes'
      AND h.booking_id IN (
        SELECT b.id FROM public.workshop_bookings b JOIN public.workshop_bays y ON y.id = b.bay_id
        WHERE NOT EXISTS (SELECT 1 FROM public.workshop_bookings o WHERE o.bay_id = b.bay_id AND o.id <> b.id AND o.deleted_at IS NULL
                           AND o.status IN ('started', 'stoppage', 'queued') AND o.scheduled_start_at < (h.after_data->>'scheduled_start_at')::timestamptz
                           AND public.workshop_booking_effective_end_at(o.id) > h.clock_at)
          AND NOT EXISTS (SELECT 1 FROM public.workshop_admin_blocks k WHERE k.bay_id = b.bay_id AND k.deleted_at IS NULL
                           AND k.scheduled_start_at < (h.after_data->>'scheduled_start_at')::timestamptz AND k.scheduled_end_at > h.clock_at)))
 AS ok, 'overdue jobs move to now' AS detail
$chk752$);

DO $post752$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('overdue_job_moves_to_now_752','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r752: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post752$;
