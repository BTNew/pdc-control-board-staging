-- Undo r573 (F187) / sort 344. PREVIEW. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Restores the 180-character public description check, the r423 hours-batch body
-- and pin, and the previous Edit-line gate. Does not shorten job wording and does
-- not update a vehicle. Refuses while a stored hours description is longer than
-- 180 characters, so those rows are not rejected by the restored check.
-- Department 135 is not edited. Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r573 down: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r573 down: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573 down: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')) IS DISTINCT FROM '8255bcf5461babcc01714481fcd8cbe0' THEN RAISE EXCEPTION 'r573 down: hours batch is not the r573 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')) IS DISTINCT FROM '78c1833ad4db912bd0f7bf2772ecb548' THEN RAISE EXCEPTION 'r573 down: upsert is not the r573 body'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE length(description) > 180
 ) THEN RAISE EXCEPTION 'r573 down: an hours record holds wording longer than 180 characters. Leave the 2000 limit in place, or shorten those rows in a separate reviewed change.'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('karratha135_pdc.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573 down: department 135 description check changed'; END IF;
END $g$;

DO $batch$
DECLARE def text;
 new text := $old$    INSERT INTO public.vehicle_workshop_line_adjustments($old$;
 old text := $new$    IF EXISTS (
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
 def := pg_get_functiondef(pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'));
 IF length(old)=0 OR (length(def)-length(replace(def, old, '')))/length(old) <> 1 THEN RAISE EXCEPTION 'r573 down: hours guard was not found once'; END IF;
 EXECUTE replace(def, old, new);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)')) IS DISTINCT FROM 'e21c5c8901714498c71b75ea9caaf812' THEN RAISE EXCEPTION 'r573 down: hours batch did not return to the r423 body'; END IF;
 UPDATE pdc_ops.expected_function_md5
    SET prosrc_md5='e21c5c8901714498c71b75ea9caaf812',
        release='r423',
        note='controller scope (was c16f3b384c19c3e1b120347be72c9af1)',
        updated_at=clock_timestamp()
  WHERE signature='public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'
    AND prosrc_md5='8255bcf5461babcc01714481fcd8cbe0'
    AND release='r573';
 IF NOT FOUND THEN RAISE EXCEPTION 'r573 down: hours batch pin was not restored'; END IF;
END $batch$;

DO $upsert$
DECLARE def text;
 new text := $old$ or length(v_description)not between 1 and 180 or v_description~'[[:cntrl:]]'
    or p_estimated_hours is null or p_estimated_hours<0 or p_estimated_hours>999.99 or mod(p_estimated_hours,0.01)<>0 then
  return jsonb_build_object('ok',false,'code','invalid_workshop_line');
 end if;$old$;
 old text := $new$ or p_estimated_hours is null or p_estimated_hours<0 or p_estimated_hours>999.99 or mod(p_estimated_hours,0.01)<>0 then
  return jsonb_build_object('ok',false,'code','invalid_workshop_line');
 end if;
 if v_description is null or length(v_description) not between 1 and 2000
    or v_description is distinct from btrim(v_description) or v_description~'[[:cntrl:]]' then
  return jsonb_build_object('ok',false,'code','hours_description_rejected','message','This job wording is empty, has a hidden character, or is longer than 2000 characters. The hours were not saved. Shorten the wording, then try again.');
 end if;$new$;
BEGIN
 def := pg_get_functiondef(pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'));
 IF length(old)=0 OR (length(def)-length(replace(def, old, '')))/length(old) <> 1 THEN RAISE EXCEPTION 'r573 down: upsert gate was not found once'; END IF;
 EXECUTE replace(def, old, new);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)')) IS DISTINCT FROM '8d67349867890d566253c4d7d9ee3907' THEN RAISE EXCEPTION 'r573 down: upsert did not return to the previous body'; END IF;
END $upsert$;

ALTER TABLE public.vehicle_workshop_line_adjustments
  DROP CONSTRAINT vehicle_workshop_line_adjustments_description_check;
ALTER TABLE public.vehicle_workshop_line_adjustments
  ADD CONSTRAINT vehicle_workshop_line_adjustments_description_check
  CHECK (
    length(description) >= 1
    AND length(description) <= 180
    AND description = btrim(description)
    AND description !~ '[[:cntrl:]]'
  );

DELETE FROM pdc_ops.regression_checks
 WHERE check_name = 'hours_description_fits_573'
   AND fault_id = 'F187'
   AND sort_order = 344
   AND added_in = 'r573';

DO $post$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r573 down: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r573') THEN RAISE EXCEPTION 'r573 down: r573 pin remains'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)') IS DISTINCT FROM 'e21c5c8901714498c71b75ea9caaf812' THEN RAISE EXCEPTION 'r573 down: hours pin is not the r423 md5'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hours_description_fits_573' OR fault_id='F187' OR added_in='r573' OR sort_order=344) THEN RAISE EXCEPTION 'r573 down: check still present'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('public.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573 down: public description check is not 180'; END IF;
 IF coalesce((SELECT pg_catalog.strpos(pg_get_constraintdef(c.oid), 'length(description) <= 180') FROM pg_constraint c WHERE c.conrelid = pg_catalog.to_regclass('karratha135_pdc.vehicle_workshop_line_adjustments') AND c.conname = 'vehicle_workshop_line_adjustments_description_check'), 0) = 0 THEN RAISE EXCEPTION 'r573 down: department 135 description check changed'; END IF;
END $post$;
