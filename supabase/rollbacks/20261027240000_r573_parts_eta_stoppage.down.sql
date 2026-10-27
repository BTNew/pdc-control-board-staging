-- r573 (F187) undo. PREVIEW. Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45.
-- Ends bookings this release placed, drops the place/lift audit rows, the new
-- columns, the functions and check parts_eta_stoppage_573.
-- The r567 manual ETA tables stay. No vehicle row is rewritten. Pins stay 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r573 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r573 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r573 undo: manual set changed'; END IF;
END $g$;

UPDATE public.workshop_bookings
   SET status = 'deleted',
       deleted_at = clock_timestamp(),
       deleted_reason = 'r573 undo',
       updated_at = clock_timestamp(),
       version = version + 1
 WHERE deleted_at IS NULL
   AND metadata->>'source' = 'parts_eta_stoppage_573';

DELETE FROM public.pdc_parts_stoppage_audit_564 WHERE action IN ('place', 'lift');

DROP TRIGGER IF EXISTS trg_parts_eta_stoppage_573_received ON public.vehicle_parts_updates;
DROP TRIGGER IF EXISTS trg_parts_eta_stoppage_573_manual ON public.pdc_parts_stoppage_564;
DROP FUNCTION IF EXISTS public.parts_eta_stoppage_573_on_received();
DROP FUNCTION IF EXISTS public.parts_eta_stoppage_573_on_manual();
DROP FUNCTION IF EXISTS public.get_pdc_parts_eta_stoppage_board_573();
DROP FUNCTION IF EXISTS public.place_parts_eta_stoppage_573(uuid, date, text, boolean);
DROP FUNCTION IF EXISTS public.end_parts_eta_stoppage_573(uuid, text, text);

ALTER TABLE public.pdc_parts_stoppage_564 DROP COLUMN IF EXISTS stoppage_booking_id;
ALTER TABLE public.pdc_parts_stoppage_564 DROP COLUMN IF EXISTS placed_stoppage;

ALTER TABLE public.pdc_parts_stoppage_audit_564 DROP CONSTRAINT IF EXISTS pdc_parts_stoppage_audit_564_action_check;
ALTER TABLE public.pdc_parts_stoppage_audit_564
  ADD CONSTRAINT pdc_parts_stoppage_audit_564_action_check
  CHECK (action IN ('set', 'clear', 'check'));

DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_eta_stoppage_573' AND fault_id='F187' AND sort_order=344 AND added_in='r573';

DO $g$ BEGIN
 IF pg_catalog.to_regprocedure('public.place_parts_eta_stoppage_573(uuid,date,text,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r573 undo: place remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r573') THEN RAISE EXCEPTION 'r573 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_parts_stoppage_564') IS NULL THEN RAISE EXCEPTION 'r573 undo: r567 table was dropped'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r573 undo: manual set changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r573 undo: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r573 undo: department 135 move changed'; END IF;
END $g$;
