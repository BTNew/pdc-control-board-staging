-- r566 (F180) undo: re-activates Elec bays 08-10 (PMB Bays 20-22). Staging only.
-- Does not require F177 or the arrival-age check to be absent. Deletes only electrical_bays_7_566.

SET LOCAL lock_timeout = '2s';
CREATE TEMP TABLE r566_hide(id uuid PRIMARY KEY, bay_number integer NOT NULL, code text NOT NULL) ON COMMIT DROP;
INSERT INTO r566_hide VALUES
  ('88bfd1d0-5e69-473b-88e3-572135184022'::uuid,8,'ELECTRICAL-BAY-08'),
  ('5af51266-df78-4cb0-88e9-bc65af3bf656'::uuid,9,'ELECTRICAL-BAY-09'),
  ('3dd68646-b4a7-4c32-98fa-39e068b0b1e9'::uuid,10,'ELECTRICAL-BAY-10');

DO $g$ DECLARE v_bad text; BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r566 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r566 undo: staging only'; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad
   FROM r566_hide h LEFT JOIN public.workshop_bays b ON b.id=h.id
  WHERE b.id IS NULL OR b.is_active OR b.code IS DISTINCT FROM h.code
     OR NOT EXISTS(SELECT 1 FROM public.audit_events a WHERE a.row_id=h.id AND a.table_name='workshop_bays' AND a.metadata->>'release'='r566' AND a.metadata->>'action'='deactivate_workshop_bay');
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r566 undo: Elec bay(s) not hidden by r566: %', v_bad; END IF;
END $g$;

CREATE TEMP TABLE r566_bays_before ON COMMIT DROP AS SELECT b.id, to_jsonb(b) AS j FROM public.workshop_bays b;
CREATE TEMP TABLE r566_bookings_before ON COMMIT DROP AS SELECT k.id, to_jsonb(k) AS value FROM public.workshop_bookings k;

WITH upd AS (
  UPDATE public.workshop_bays b SET is_active=true, version=b.version+1
    FROM r566_hide h WHERE b.id=h.id AND NOT b.is_active
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'rollback', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r566','fault','F180','action','rollback_deactivate_workshop_bay')
  FROM upd u JOIN r566_bays_before o ON o.id=u.id;

DELETE FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566' AND added_in='r566';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM r566_hide h JOIN public.workshop_bays b ON b.id=h.id WHERE NOT b.is_active) THEN RAISE EXCEPTION 'r566 undo: bays not re-activated'; END IF;
 IF (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND action='rollback' AND metadata->>'release'='r566' AND created_at=now())<>3 THEN RAISE EXCEPTION 'r566 undo: expected 3 audit rows'; END IF;
 IF EXISTS(SELECT 1 FROM r566_bays_before o FULL JOIN public.workshop_bays b USING(id)
            WHERE o.id IS NULL OR b.id IS NULL
               OR (b.id NOT IN (SELECT id FROM r566_hide) AND o.j IS DISTINCT FROM to_jsonb(b))) THEN RAISE EXCEPTION 'r566 undo: another bay changed'; END IF;
 IF EXISTS(SELECT 1 FROM r566_bookings_before o FULL JOIN public.workshop_bookings k USING(id) WHERE o.value IS DISTINCT FROM to_jsonb(k)) THEN RAISE EXCEPTION 'r566 undo: a booking changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r566 undo: pin count changed'; END IF;
END $g$;
