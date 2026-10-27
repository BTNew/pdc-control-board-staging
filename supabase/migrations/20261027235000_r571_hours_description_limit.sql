-- r573 (F187) / sort 344. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Staging ledger r573_hours_description_limit 20261027052235.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Craig, 27 Oct 2026 12:02 AWST: stock 13077205 will not let him change the hours.
-- Saving hours copies the whole job-line wording into vehicle_workshop_line_adjustments.
-- That table refused any description longer than 180 characters. The save died as
-- check constraint vehicle_workshop_line_adjustments_description_check (23514), and
-- the screen said only that the hours batch was rejected.
--
-- Stock 13077205 (vehicle 6e034f6b-2a5f-4988-b236-5a0c50e2f490, dept 139, one row,
-- not deleted, not hidden) has two lines over 180: operation 0c91e556-d221-40c1-8c02-7a5b71627794
-- SUBLET 297 characters, and operation 9f21339d-f245-46f3-94ac-975caf67db04 ELECTRICAL
-- 329 characters. A short Tint line on the same vehicle saves and rolls back cleanly.
-- The job card is status 20, sub status not 80 or 99. There is no booking and no
-- hours adjustment. Today's go-lives (#546 key gate, #547 PMB age, #549 side panel,
-- #550 parts ETA, #553 bus split, #554 pause) do not impose the 180-character check.
-- #549 is only the editor that calls this save.
--
-- The wording is the real job text. No source row is shortened and no vehicle row
-- is updated. The same state on non-deleted vehicles, read 27 Oct 2026: 47 lines,
-- longest 329, on 34 stocks:
-- 12710966, 12710968, 13003383, 13004183, 13017855, 13025962, 13025963, 13047337,
-- 13047338, 13047339, 13052490, 13071999, 13075144, 13077191, 13077196, 13077197,
-- 13077198, 13077199, 13077200, 13077201, 13077203, 13077205, 13077206, 13077210,
-- 13077211, 13092247, 13102906, 13102907, 13102908, 13102909, 13102910, 13102911,
-- 13102912, 13106992.
-- Three deleted vehicles with no stock number also have long wording (longest 545).
-- They are not on the board. 2000 still covers them.
--
-- Release ledger when this file was written:
--   origin/main r569 (F183) / sort 340 is the live bay-job pause (#554).
--   Open preview #558 claims r570 / F184 / sort 342.
--   Open previews #556 and #544 claim r570 / F184 / sort 341.
--   Open preview #557 (Tint push-back) still claims r567 / F181 / sort 341.
--   Open preview #555 claims r566 / F180 in the page only.
--   Open preview #552 claims r563 / F177. #551 is the rolled-back Electrical hide.
--   Next free triple is r573 / F187 / sort 344.
--
-- The description check on public.vehicle_workshop_line_adjustments becomes
-- 1 to 2000 characters, still trimmed, still with no control character.
-- Department 135 keeps its own 180-character check. Pin count stays 241.
-- The hours-batch pin moves in place from e21c5c8901714498c71b75ea9caaf812
-- to 8255bcf5461babcc01714481fcd8cbe0. A line whose wording still cannot be
-- stored returns ok false and code hours_description_rejected, naming the line.
-- It does not die as an unnamed check error.
-- Parts tile colour is not edited.
-- Undo: supabase/rollbacks/20261027235000_r571_hours_description_limit.down.sql
-- r571 / F185 / sort 343 is left unused for #559. This release does not take it.
-- The parent already on staging is service_card_stack_572, F186, sort 342, added_in r572.
-- Bay pause r569 / F183 / sort 340 stays.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r573: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r573: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569') THEN RAISE EXCEPTION 'r573: r569 / F183 sort 340 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_card_stack_572' AND fault_id='F186' AND sort_order=342 AND added_in='r572') THEN RAISE EXCEPTION 'r573: parent r572 / F186 sort 342 is not applied'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=344 OR fault_id='F187' OR check_name='hours_description_fits_573' OR added_in='r573') THEN RAISE EXCEPTION 'r573: sort 344 or F187 is taken'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')) IS DISTINCT FROM 'e21c5c8901714498c71b75ea9caaf812' THEN RAISE EXCEPTION 'r573: hours batch is not the r423 body'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)') IS DISTINCT FROM 'e21c5c8901714498c71b75ea9caaf812' THEN RAISE EXCEPTION 'r573: hours batch pin is not the r423 md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')) IS DISTINCT FROM '8d67349867890d566253c4d7d9ee3907' THEN RAISE EXCEPTION 'r573: upsert body changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)') THEN RAISE EXCEPTION 'r573: upsert is pinned'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('public.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573: public description check is not 180'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('karratha135_pdc.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573: department 135 description check changed'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.vehicle_workshop_line_adjustments
   WHERE length(description) > 2000 OR description IS DISTINCT FROM btrim(description) OR description ~ '[[:cntrl:]]'
 ) THEN RAISE EXCEPTION 'r573: a stored hours description already fails the 2000 rule'; END IF;
END $g$;

ALTER TABLE public.vehicle_workshop_line_adjustments
  DROP CONSTRAINT vehicle_workshop_line_adjustments_description_check;
ALTER TABLE public.vehicle_workshop_line_adjustments
  ADD CONSTRAINT vehicle_workshop_line_adjustments_description_check
  CHECK (
    length(description) >= 1
    AND length(description) <= 2000
    AND description = btrim(description)
    AND description !~ '[[:cntrl:]]'
  );

DO $batch$
DECLARE def text;
 old text := $old$    INSERT INTO public.vehicle_workshop_line_adjustments($old$;
 new text := $new$    IF EXISTS (
      SELECT 1 FROM pdc_hours_batch_changes_t780 c
      WHERE c.current_adjustment_id IS NULL
        AND (c.source_description IS NULL
          OR length(c.source_description) NOT BETWEEN 1 AND 2000
          OR c.source_description IS DISTINCT FROM btrim(c.source_description)
          OR c.source_description ~ '[[:cntrl:]]')
    ) THEN
      RETURN jsonb_build_object('ok',false,'code','hours_description_rejected','message',(
        SELECT 'The hours were not saved. Job wording on '
          || coalesce(string_agg(coalesce(c.operation_no, c.line_key), ', ' ORDER BY c.display_order), 'one line')
          || ' is empty, has a hidden character, or is longer than 2000 characters. Shorten that wording, then try again. Nothing else was changed.'
        FROM pdc_hours_batch_changes_t780 c
        WHERE c.current_adjustment_id IS NULL
          AND (c.source_description IS NULL
            OR length(c.source_description) NOT BETWEEN 1 AND 2000
            OR c.source_description IS DISTINCT FROM btrim(c.source_description)
            OR c.source_description ~ '[[:cntrl:]]')
      ));
    END IF;

    INSERT INTO public.vehicle_workshop_line_adjustments($new$;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')) IS DISTINCT FROM 'e21c5c8901714498c71b75ea9caaf812' THEN RAISE EXCEPTION 'r573: hours batch changed before the patch'; END IF;
 def := pg_get_functiondef(pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'));
 IF length(old)=0 OR (length(def)-length(replace(def, old, '')))/length(old) <> 1 THEN RAISE EXCEPTION 'r573: hours insert was not found once'; END IF;
 EXECUTE replace(def, old, new);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')) IS DISTINCT FROM '8255bcf5461babcc01714481fcd8cbe0' THEN RAISE EXCEPTION 'r573: hours batch md5 is not 8255bcf5461babcc01714481fcd8cbe0'; END IF;
 UPDATE pdc_ops.expected_function_md5
    SET prosrc_md5='8255bcf5461babcc01714481fcd8cbe0',
        release='r573',
        note='r573 (F187): name a job wording that cannot be stored before the hours insert (was e21c5c8901714498c71b75ea9caaf812)',
        updated_at=clock_timestamp()
  WHERE signature='public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'
    AND prosrc_md5='e21c5c8901714498c71b75ea9caaf812';
 IF NOT FOUND THEN RAISE EXCEPTION 'r573: hours batch pin was not updated in place'; END IF;
END $batch$;

DO $upsert$
DECLARE def text;
 old text := $old$ or length(v_description)not between 1 and 180 or v_description~'[[:cntrl:]]'
    or p_estimated_hours is null or p_estimated_hours<0 or p_estimated_hours>999.99 or mod(p_estimated_hours,0.01)<>0 then
  return jsonb_build_object('ok',false,'code','invalid_workshop_line');
 end if;$old$;
 new text := $new$ or p_estimated_hours is null or p_estimated_hours<0 or p_estimated_hours>999.99 or mod(p_estimated_hours,0.01)<>0 then
  return jsonb_build_object('ok',false,'code','invalid_workshop_line');
 end if;
 if v_description is null or length(v_description) not between 1 and 2000
    or v_description is distinct from btrim(v_description) or v_description~'[[:cntrl:]]' then
  return jsonb_build_object('ok',false,'code','hours_description_rejected','message','This job wording is empty, has a hidden character, or is longer than 2000 characters. The hours were not saved. Shorten the wording, then try again.');
 end if;$new$;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')) IS DISTINCT FROM '8d67349867890d566253c4d7d9ee3907' THEN RAISE EXCEPTION 'r573: upsert changed before the patch'; END IF;
 def := pg_get_functiondef(pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'));
 IF length(old)=0 OR (length(def)-length(replace(def, old, '')))/length(old) <> 1 THEN RAISE EXCEPTION 'r573: upsert description gate was not found once'; END IF;
 EXECUTE replace(def, old, new);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')) IS DISTINCT FROM '78c1833ad4db912bd0f7bf2772ecb548' THEN RAISE EXCEPTION 'r573: upsert md5 is not 78c1833ad4db912bd0f7bf2772ecb548'; END IF;
END $upsert$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('hours_description_fits_573', 'F187',
 'r573: a non-deleted vehicle whose job wording is empty, untrimmed, has a control character, or is longer than 2000 characters cannot have its hours stored. The public hours description check stays at 2000. Department 135 stays at 180. The hours batch names that refusal and its pin matches. Pin count stays 241.',
$chk573$
SELECT
 bad.n = 0
 AND pg_catalog.strpos(rule.def, 'length(description) <= 2000') > 0
 AND pg_catalog.strpos(rule.def, 'length(description) >= 1') > 0
 AND pg_catalog.strpos(rule.def, 'btrim(description)') > 0
 AND pg_catalog.strpos(rule.def, '[[:cntrl:]]') > 0
 AND pg_catalog.strpos(k135.def, 'length(description) <= 180') > 0
 AND pg_catalog.strpos(k135.def, 'length(description) <= 2000') = 0
 AND pins.n = 241
 AND batch.md5 = '8255bcf5461babcc01714481fcd8cbe0'
 AND batch.pin = '8255bcf5461babcc01714481fcd8cbe0'
 AND batch.release = 'r573'
 AND pg_catalog.strpos(batch.prosrc, 'hours_description_rejected') > 0
 AND batch.prosecdef
 AND batch.proconfig @> ARRAY['search_path=pg_catalog, public, extensions']::text[]
 AND upsert.md5 = '78c1833ad4db912bd0f7bf2772ecb548'
 AND upsert.prosecdef
 AND upsert.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
 AND pg_catalog.strpos(upsert.prosrc, 'hours_description_rejected') > 0
 AND pg_catalog.strpos(upsert.prosrc, 'not between 1 and 180') = 0
 AND NOT EXISTS (
   SELECT 1 FROM pdc_ops.expected_function_md5 e
   WHERE e.signature = 'public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'
 )
 AS ok,
 'lines '||bad.n::text||' stocks '||coalesce(nullif(bad.stocks, ''), '(none)')||' batch '||batch.md5 AS detail
FROM (
  SELECT count(*)::integer AS n,
         coalesce(string_agg(DISTINCT stock_number, ', '), '') AS stocks
  FROM (
    SELECT v.stock_number
    FROM public.pdc_pilbara_service_operations o
    JOIN public.vehicles v ON v.id = o.vehicle_id
    WHERE v.deleted_at IS NULL
      AND o.operation_description IS NOT NULL
      AND (
        pg_catalog.length(o.operation_description) > 2000
        OR pg_catalog.length(o.operation_description) < 1
        OR o.operation_description IS DISTINCT FROM pg_catalog.btrim(o.operation_description)
        OR o.operation_description ~ '[[:cntrl:]]'
      )
  ) s
) bad
CROSS JOIN (
  SELECT pg_get_constraintdef(c.oid) AS def
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid = pg_catalog.to_regclass('public.vehicle_workshop_line_adjustments')
    AND c.conname = 'vehicle_workshop_line_adjustments_description_check'
) rule
CROSS JOIN (
  SELECT pg_get_constraintdef(c.oid) AS def
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid = pg_catalog.to_regclass('karratha135_pdc.vehicle_workshop_line_adjustments')
    AND c.conname = 'vehicle_workshop_line_adjustments_description_check'
) k135
CROSS JOIN (SELECT count(*)::integer AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (
  SELECT p.prosrc, md5(p.prosrc) AS md5, p.prosecdef, p.proconfig, pin.prosrc_md5 AS pin, pin.release
  FROM pg_catalog.pg_proc p
  JOIN pdc_ops.expected_function_md5 pin
    ON pin.signature = 'public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'
  WHERE p.oid = pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')
) batch
CROSS JOIN (
  SELECT p.prosrc, md5(p.prosrc) AS md5, p.prosecdef, p.proconfig
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')
) upsert
$chk573$, true, 344, 'r573');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r573')<>1 THEN RAISE EXCEPTION 'r573: pin release count is not 1'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='hours_description_fits_573' AND fault_id='F187' AND sort_order=344 AND added_in='r573' AND enabled)<>1 THEN RAISE EXCEPTION 'r573: check missing'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('karratha135_pdc.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573: department 135 description check changed'; END IF;
 PERFORM set_config('request.jwt.claims', '', true);
 PERFORM set_config('search_path', 'pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='hours_description_fits_573' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r573: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
