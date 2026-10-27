-- r566 (F180). Go-live. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig, 27 Oct 2026: hide Electrical PMB Bays 20, 21 and 22 only (not 17-19).
-- Hides Elec station bays 08-10 by id: is_active=false (+ version+1), same as r483 Fab hide /
-- public.set_workshop_bay_active. Rows, ids, bay_number, code and display_name stay; reversible
-- via the down migration or set_workshop_bay_active(true). Refused when a bay has a live booking,
-- admin block, parts override target or default technician. Never touches bookings, overlap /
-- close-gaps rules, pins (241) or department 135.
-- Live before this apply: r565 / F179 / sort 337 is the panel tick. r564 / F178 is the Fitters
-- key badge and inserted no check. This is r566 / F180 / sort 338.
-- Source preview claimed r563 / F177 / sort 337 (up md5 16f025e38da6bd80293ad404a5f95fdb,
-- down md5 d485bf4521dd67c9556bdd541ea03b40). Those ids belong to the arrival age.
-- No pinned function is replaced. The in-migration proof runs only electrical_bays_7_566.
-- Undo: supabase/rollbacks/20261027160000_r566_hide_electrical_bays_20_22.down.sql


SET LOCAL lock_timeout = '2s';
CREATE TEMP TABLE r566_hide(id uuid PRIMARY KEY, bay_number integer NOT NULL, code text NOT NULL, pmb_bay integer NOT NULL) ON COMMIT DROP;
INSERT INTO r566_hide VALUES
  ('88bfd1d0-5e69-473b-88e3-572135184022'::uuid,8,'ELECTRICAL-BAY-08',20),
  ('5af51266-df78-4cb0-88e9-bc65af3bf656'::uuid,9,'ELECTRICAL-BAY-09',21),
  ('3dd68646-b4a7-4c32-98fa-39e068b0b1e9'::uuid,10,'ELECTRICAL-BAY-10',22);

DO $g$ DECLARE v_bad text; BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r566: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r566: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r566: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566' OR added_in='r566') THEN RAISE EXCEPTION 'r566: already applied'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=338 OR fault_id='F180' OR check_name='electrical_bays_7_566') THEN RAISE EXCEPTION 'r566: sort 338 / F180 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' AND fault_id='F173' AND sort_order=334 AND added_in='r559') THEN RAISE EXCEPTION 'r566: r559 / F173 sort 334 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562') THEN RAISE EXCEPTION 'r566: r562 / F176 sort 335 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r566: r563 / F177 sort 336 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565') THEN RAISE EXCEPTION 'r566: r565 / F179 sort 337 is not present'; END IF;
 IF (SELECT count(*) FROM r566_hide)<>3 THEN RAISE EXCEPTION 'r566: hide map must have 3 rows'; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad
   FROM r566_hide h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id IS NULL OR s.code IS DISTINCT FROM 'ELECTRICAL' OR b.bay_number IS DISTINCT FROM h.bay_number OR b.code IS DISTINCT FROM h.code
     OR NOT b.is_active OR b.is_sublet_row OR b.default_technician_id IS NOT NULL;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r566: Elec bay(s) to hide changed since prepared: %', v_bad; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad FROM r566_hide h
  WHERE EXISTS(SELECT 1 FROM public.workshop_bookings k WHERE k.bay_id=h.id AND k.deleted_at IS NULL)
     OR EXISTS(SELECT 1 FROM public.workshop_admin_blocks x WHERE x.bay_id=h.id)
     OR EXISTS(SELECT 1 FROM public.workshop_parts_overrides x WHERE x.intended_bay_id=h.id)
     OR EXISTS(SELECT 1 FROM pdc_bus_private.activity_events x WHERE x.bay_id=h.id);
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r566: Elec bay(s) to hide have bookings, blocks, overrides or bay events: %', v_bad; END IF;
 IF (SELECT count(*) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
     WHERE s.code='ELECTRICAL' AND b.is_active AND NOT b.is_sublet_row)<>10 THEN
  RAISE EXCEPTION 'r566: expected 10 active Elec bays before hide';
 END IF;
END $g$;

CREATE TEMP TABLE r566_bays_before ON COMMIT DROP AS SELECT b.id, to_jsonb(b) AS j FROM public.workshop_bays b;
CREATE TEMP TABLE r566_bookings_before ON COMMIT DROP AS SELECT k.id, to_jsonb(k) AS value FROM public.workshop_bookings k;

WITH upd AS (
  UPDATE public.workshop_bays b SET is_active=false, version=b.version+1
    FROM r566_hide h WHERE b.id=h.id AND b.is_active AND b.code=h.code
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'reference_change', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r566','fault','F180','action','deactivate_workshop_bay','department','139',
                          'source','Craig 27 Oct 2026: hide unused Elec PMB Bays 20-22 (not deleted)')
  FROM upd u JOIN r566_bays_before o ON o.id=u.id;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES (
 'electrical_bays_7_566', 'F180',
 'Dept 139 Electrical (r566): Elec bays 01-07 (PMB Bays 13-19) stay active; Elec bays 08-10 (PMB Bays 20-22) exist, are inactive (hidden, not deleted) and hold no live booking; bays 05-07 (PMB 17-19) stay active. Pin count stays 241. Department 135 is unchanged.',
 $c$WITH h(id,bay_number,code,pmb_bay) AS (VALUES
  ('88bfd1d0-5e69-473b-88e3-572135184022'::uuid,8,'ELECTRICAL-BAY-08',20),
  ('5af51266-df78-4cb0-88e9-bc65af3bf656'::uuid,9,'ELECTRICAL-BAY-09',21),
  ('3dd68646-b4a7-4c32-98fa-39e068b0b1e9'::uuid,10,'ELECTRICAL-BAY-10',22)),
 a AS (SELECT count(*) FILTER (WHERE b.is_active) n
         FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code='ELECTRICAL' AND NOT b.is_sublet_row),
 y AS (SELECT h.code, b.id IS NOT NULL AND s.code='ELECTRICAL' AND b.bay_number=h.bay_number AND b.code=h.code AND NOT b.is_active
              AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings k WHERE k.bay_id=h.id AND k.deleted_at IS NULL) AS good
         FROM h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id),
 v AS (SELECT bool_and(b.is_active) good FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code='ELECTRICAL' AND b.bay_number IN (5,6,7))
SELECT (SELECT n FROM a)=7 AND (SELECT bool_and(good) FROM y) AND (SELECT good FROM v) AS ok,
 coalesce('active Elec '||(SELECT n::text FROM a)||' (want 7)','')
 ||'; '||coalesce('not hidden: '||(SELECT string_agg(code,', ' ORDER BY code) FROM y WHERE NOT good),'Elec 08-10 hidden (3)')
 ||'; PMB 17-19 active: '||(SELECT good::text FROM v) AS detail$c$,
 true, 338, 'r566');

DO $g$ DECLARE probe record; BEGIN
 IF (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND metadata->>'release'='r566' AND metadata->>'action'='deactivate_workshop_bay' AND created_at=now())<>3
   THEN RAISE EXCEPTION 'r566: expected 3 audit rows'; END IF;
 IF EXISTS(SELECT 1 FROM r566_hide h JOIN public.workshop_bays b ON b.id=h.id WHERE b.is_active) THEN RAISE EXCEPTION 'r566: hide incomplete'; END IF;
 IF EXISTS(SELECT 1 FROM r566_bays_before o FULL JOIN public.workshop_bays b USING(id)
            WHERE o.id IS NULL OR b.id IS NULL
               OR (o.j - ARRAY['is_active','version','updated_at']) IS DISTINCT FROM (to_jsonb(b) - ARRAY['is_active','version','updated_at'])
               OR (b.id NOT IN (SELECT id FROM r566_hide) AND o.j IS DISTINCT FROM to_jsonb(b))) THEN RAISE EXCEPTION 'r566: a bay field other than is_active / version changed'; END IF;
 IF EXISTS(SELECT 1 FROM r566_bookings_before o FULL JOIN public.workshop_bookings k USING(id) WHERE o.value IS DISTINCT FROM to_jsonb(k)) THEN RAISE EXCEPTION 'r566: a booking changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r566: pin count changed'; END IF;
 PERFORM set_config('search_path','pg_catalog', true);
 PERFORM set_config('request.jwt.claims','', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='electrical_bays_7_566') INTO probe;
 IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r566: check failed: %', left(coalesce(probe.detail, ''), 200); END IF;
END $g$;
