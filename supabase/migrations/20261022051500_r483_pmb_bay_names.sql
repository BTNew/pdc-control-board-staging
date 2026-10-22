-- r483 (F96, change request, Craig 22 Oct 2026 ~13:15 and ~13:35 AWST): Department 139 (PMB) bay names and Fab bays.
-- Staging cdsmnqxtyyoeoznmbidd only (never vjdtsswhroyguxyfjdkt).
-- Craig: "Bay 1 is express slash pits hoist. Bay 2 is express. Bay 3, 4, and 5 are hoist. Bay 6, 7, 8, 9, 10 are fitting.
--         Bay 11 and 12 are internal fabrication and external fabrication. Bay 13 ... 22 are all electrical based."
--   then: keep the 3 hoist bays (Hoist 01 Express / Pits Hoist Bay 1, Hoist 02 Express Bay 2, Hoist 03 Hoist Bay 3) and HIDE
--   (not delete) the 11 unused Fab bays 03-13.
-- 1. Renames 20 bays by id: public.workshop_bays.display_name only (+ version+1, as the 15 Oct Dept 138 rename 20261015005540):
--      Hoist 01-03 -> 'Express / Pits Hoist - PMB Bay 01', 'Express - PMB Bay 02', 'Hoist - PMB Bay 03'
--      Fitting 01-05 -> 'Fitting - PMB Bay 06' .. '10'; Fab 01 / 02 -> 'Internal / External Fabrication - PMB Bay 11 / 12';
--      Elec 01-10 -> 'Electrical - PMB Bay 13' .. '22'.
-- 2. Hides Fab Bays 03-13: is_active=false (+ version+1), the same change as public.set_workshop_bay_active. Refused unless each
--    has never had a booking, admin block or parts-override target and has no default technician. Names, rows and history stay.
-- Never changes id, stage_id, bay_number, code, is_sublet_row, efficiency or default technician, never touches a booking, and
-- never touches Dept 138 (Bus 4x4) or the shared Tint / Tyre bays (post-checks prove all of that).
-- Audit: one audit_events 'reference_change' row per bay (metadata release r483, fault F96, action rename_pmb_bay_139 or
-- deactivate_workshop_bay). Check pmb_bay_names_483 (F96, sort 283). Frontend: F96 commit (planner shows Fab 2 bays, labels).
-- Undo: supabase/rollbacks/20261022051500_r483_pmb_bay_names.down.sql.
SET LOCAL lock_timeout = '2s';
CREATE TEMP TABLE r483_rename(id uuid PRIMARY KEY, stage_code text NOT NULL, bay_number integer NOT NULL, code text NOT NULL,
  old_name text NOT NULL, new_name text NOT NULL) ON COMMIT DROP;
INSERT INTO r483_rename VALUES
  ('5ba7b0a7-44e7-4cbd-ad9a-7e2b6349f5e8'::uuid,'HOIST',1,'HOIST-BAY-01','Hoist Bay 01','Express / Pits Hoist - PMB Bay 01'),
  ('24b02c9b-e40f-46ba-93ba-37ec37d174ea'::uuid,'HOIST',2,'HOIST-BAY-02','Hoist Bay 02','Express - PMB Bay 02'),
  ('72ef5d9c-1206-45ad-b3cd-e921b5d7f703'::uuid,'HOIST',3,'HOIST-BAY-03','Hoist Bay 03','Hoist - PMB Bay 03'),
  ('2dfbb177-f353-4f4f-9668-6519909d418a'::uuid,'FITTING',1,'FITTING-BAY-01','Fitting Bay 01','Fitting - PMB Bay 06'),
  ('ed1e5eb9-d0c5-44c5-be26-f564a5c88a9d'::uuid,'FITTING',2,'FITTING-BAY-02','Fitting Bay 02','Fitting - PMB Bay 07'),
  ('88c3c9a4-a57d-48ff-a722-8a776c09c99c'::uuid,'FITTING',3,'FITTING-BAY-03','Fitting Bay 03','Fitting - PMB Bay 08'),
  ('c8514c1a-9e22-4c7d-a579-43a7bbf13906'::uuid,'FITTING',4,'FITTING-BAY-04','Fitting Bay 04','Fitting - PMB Bay 09'),
  ('ff080124-3632-4a07-944c-e0fb0f45fa1b'::uuid,'FITTING',5,'FITTING-BAY-05','Fitting Bay 05','Fitting - PMB Bay 10'),
  ('8707df84-f06d-4532-a716-54b1b812a8f7'::uuid,'FABRICATION',1,'FABRICATION-BAY-01','Fab Bay 01','Internal Fabrication - PMB Bay 11'),
  ('246c823d-fe26-4d15-a7e9-f5b8e711cbc9'::uuid,'FABRICATION',2,'FABRICATION-BAY-02','Fab Bay 02','External Fabrication - PMB Bay 12'),
  ('a79d295c-cb1a-4a76-b0a4-69337532fcfc'::uuid,'ELECTRICAL',1,'ELECTRICAL-BAY-01','Elec Bay 01','Electrical - PMB Bay 13'),
  ('4568081e-7232-4447-8806-77d15ab1dd01'::uuid,'ELECTRICAL',2,'ELECTRICAL-BAY-02','Elec Bay 02','Electrical - PMB Bay 14'),
  ('a642d2fb-ecbe-4c6e-b6df-ce310039553e'::uuid,'ELECTRICAL',3,'ELECTRICAL-BAY-03','Elec Bay 03','Electrical - PMB Bay 15'),
  ('29621a7c-60a7-4bfb-92e6-5867c518ed44'::uuid,'ELECTRICAL',4,'ELECTRICAL-BAY-04','Elec Bay 04','Electrical - PMB Bay 16'),
  ('2ee8ca5c-6556-45f9-b0cd-20e98cc3452a'::uuid,'ELECTRICAL',5,'ELECTRICAL-BAY-05','Elec Bay 05','Electrical - PMB Bay 17'),
  ('458648c7-5468-4ce5-a4e2-45a72006829c'::uuid,'ELECTRICAL',6,'ELECTRICAL-BAY-06','Elec Bay 06','Electrical - PMB Bay 18'),
  ('7bffd1a7-f8c6-4781-9303-4262a4f1abad'::uuid,'ELECTRICAL',7,'ELECTRICAL-BAY-07','Elec Bay 07','Electrical - PMB Bay 19'),
  ('88bfd1d0-5e69-473b-88e3-572135184022'::uuid,'ELECTRICAL',8,'ELECTRICAL-BAY-08','Elec Bay 08','Electrical - PMB Bay 20'),
  ('5af51266-df78-4cb0-88e9-bc65af3bf656'::uuid,'ELECTRICAL',9,'ELECTRICAL-BAY-09','Elec Bay 09','Electrical - PMB Bay 21'),
  ('3dd68646-b4a7-4c32-98fa-39e068b0b1e9'::uuid,'ELECTRICAL',10,'ELECTRICAL-BAY-10','Elec Bay 10','Electrical - PMB Bay 22');
CREATE TEMP TABLE r483_hide(id uuid PRIMARY KEY, bay_number integer NOT NULL, code text NOT NULL, name text NOT NULL) ON COMMIT DROP;
INSERT INTO r483_hide VALUES
  ('38ed4599-d9a1-41b3-a181-5b5bf091be2b'::uuid,3,'FABRICATION-BAY-03','Fab Bay 03'),
  ('4a4d4f44-73f4-48fb-9e22-01b5d43a21e7'::uuid,4,'FABRICATION-BAY-04','Fab Bay 04'),
  ('a739aa2b-eec8-4fb3-a051-1d9bec10f179'::uuid,5,'FABRICATION-BAY-05','Fab Bay 05'),
  ('666e8838-d8bf-47cc-8e7b-4f6580840d14'::uuid,6,'FABRICATION-BAY-06','Fab Bay 06'),
  ('7c1d1a1f-e666-4f50-ab79-f61c826c3c23'::uuid,7,'FABRICATION-BAY-07','Fab Bay 07'),
  ('a774d3e1-01b1-46fa-b5ae-b44d104af31c'::uuid,8,'FABRICATION-BAY-08','Fab Bay 08'),
  ('3fc1e88d-fef2-445a-9363-1127ba46494c'::uuid,9,'FABRICATION-BAY-09','Fab Bay 09'),
  ('85143aff-7734-4678-9020-129225b4ea13'::uuid,10,'FABRICATION-BAY-10','Fab Bay 10'),
  ('76cc2896-fea1-412c-8704-04a6a095259c'::uuid,11,'FABRICATION-BAY-11','Fab Bay 11'),
  ('afabdb4e-84f6-4684-ade6-29fa7dec5641'::uuid,12,'FABRICATION-BAY-12','Fab Bay 12'),
  ('d496db2f-864b-4927-b859-6a76156b05b4'::uuid,13,'FABRICATION-BAY-13','Fab Bay 13');

DO $g$ DECLARE v_bad text; BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r483: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r483: staging only'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483' OR added_in='r483')
    OR EXISTS(SELECT 1 FROM public.workshop_bays b JOIN r483_rename m ON m.id=b.id AND b.display_name=m.new_name) THEN RAISE EXCEPTION 'r483: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=283 OR fault_id='F96') THEN RAISE EXCEPTION 'r483: sort_order 283 / F96 taken'; END IF;
 IF (SELECT count(*) FROM r483_rename)<>20 OR (SELECT count(*) FROM r483_hide)<>11 THEN RAISE EXCEPTION 'r483: map must have 20 + 11 rows'; END IF;
 -- Guard on current values: every bay must still be exactly what Craig's list was matched against.
 SELECT string_agg(m.code||' ('||coalesce(b.display_name,'missing')||')',', ' ORDER BY m.code) INTO v_bad
   FROM r483_rename m LEFT JOIN public.workshop_bays b ON b.id=m.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id IS NULL OR s.code IS DISTINCT FROM m.stage_code OR b.bay_number IS DISTINCT FROM m.bay_number OR b.code IS DISTINCT FROM m.code
     OR b.display_name IS DISTINCT FROM m.old_name OR b.is_sublet_row OR NOT b.is_active;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r483: bay(s) changed since prepared: %', v_bad; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad
   FROM r483_hide h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id IS NULL OR s.code IS DISTINCT FROM 'FABRICATION' OR b.bay_number IS DISTINCT FROM h.bay_number OR b.code IS DISTINCT FROM h.code
     OR b.display_name IS DISTINCT FROM h.name OR NOT b.is_active OR b.is_sublet_row OR b.default_technician_id IS NOT NULL;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r483: Fab bay(s) to hide changed since prepared: %', v_bad; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad FROM r483_hide h
  WHERE EXISTS(SELECT 1 FROM public.workshop_bookings k WHERE k.bay_id=h.id)
     OR EXISTS(SELECT 1 FROM public.workshop_admin_blocks x WHERE x.bay_id=h.id)
     OR EXISTS(SELECT 1 FROM public.workshop_parts_overrides x WHERE x.intended_bay_id=h.id)
     OR EXISTS(SELECT 1 FROM pdc_bus_private.activity_events x WHERE x.bay_id=h.id);
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r483: Fab bay(s) to hide have bookings, blocks, overrides or bay events: %', v_bad; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN r483_rename m ON m.new_name=b.display_name) THEN RAISE EXCEPTION 'r483: a new name is already in use'; END IF;
END $g$;

-- Before-images for the post-checks.
CREATE TEMP TABLE r483_bays_before ON COMMIT DROP AS SELECT b.id, to_jsonb(b) AS j FROM public.workshop_bays b;
CREATE TEMP TABLE r483_bookings_before ON COMMIT DROP AS SELECT k.id, to_jsonb(k) AS value FROM public.workshop_bookings k;

WITH upd AS (
  UPDATE public.workshop_bays b SET display_name=m.new_name, version=b.version+1
    FROM r483_rename m WHERE b.id=m.id AND b.display_name=m.old_name AND b.bay_number=m.bay_number AND b.code=m.code
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'reference_change', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r483','fault','F96','action','rename_pmb_bay_139','department','139',
                          'source','Craig 22 Oct 2026 bay list for 139','old_name',o.j->>'display_name','new_name',u.display_name)
  FROM upd u JOIN r483_bays_before o ON o.id=u.id;

WITH upd AS (
  UPDATE public.workshop_bays b SET is_active=false, version=b.version+1
    FROM r483_hide h WHERE b.id=h.id AND b.is_active AND b.code=h.code
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'reference_change', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r483','fault','F96','action','deactivate_workshop_bay','department','139',
                          'source','Craig 22 Oct 2026: hide unused Fab bays 03-13 (not deleted)')
  FROM upd u JOIN r483_bays_before o ON o.id=u.id;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES (
 'pmb_bay_names_483', 'F96',
 'Dept 139 bays per Craig (r483): 20 bays keep id, station, bay number and code and carry his names (Hoist 01-03 = PMB Bays 01-03, Fitting 01-05 = 06-10, Fab 01/02 = Internal/External Fabrication 11/12, Elec 01-10 = 13-22); Fab Bays 03-13 exist, are inactive (hidden, not deleted) and hold no live booking; Bus 4x4 keeps 10 active bays and Tint / Tyre 2 each; no two bays share a name. A later rename by Craig must update this check.',
 $c$WITH m(id,stage_code,bay_number,code,new_name) AS (VALUES
  ('5ba7b0a7-44e7-4cbd-ad9a-7e2b6349f5e8'::uuid,'HOIST',1,'HOIST-BAY-01','Express / Pits Hoist - PMB Bay 01'),
  ('24b02c9b-e40f-46ba-93ba-37ec37d174ea'::uuid,'HOIST',2,'HOIST-BAY-02','Express - PMB Bay 02'),
  ('72ef5d9c-1206-45ad-b3cd-e921b5d7f703'::uuid,'HOIST',3,'HOIST-BAY-03','Hoist - PMB Bay 03'),
  ('2dfbb177-f353-4f4f-9668-6519909d418a'::uuid,'FITTING',1,'FITTING-BAY-01','Fitting - PMB Bay 06'),
  ('ed1e5eb9-d0c5-44c5-be26-f564a5c88a9d'::uuid,'FITTING',2,'FITTING-BAY-02','Fitting - PMB Bay 07'),
  ('88c3c9a4-a57d-48ff-a722-8a776c09c99c'::uuid,'FITTING',3,'FITTING-BAY-03','Fitting - PMB Bay 08'),
  ('c8514c1a-9e22-4c7d-a579-43a7bbf13906'::uuid,'FITTING',4,'FITTING-BAY-04','Fitting - PMB Bay 09'),
  ('ff080124-3632-4a07-944c-e0fb0f45fa1b'::uuid,'FITTING',5,'FITTING-BAY-05','Fitting - PMB Bay 10'),
  ('8707df84-f06d-4532-a716-54b1b812a8f7'::uuid,'FABRICATION',1,'FABRICATION-BAY-01','Internal Fabrication - PMB Bay 11'),
  ('246c823d-fe26-4d15-a7e9-f5b8e711cbc9'::uuid,'FABRICATION',2,'FABRICATION-BAY-02','External Fabrication - PMB Bay 12'),
  ('a79d295c-cb1a-4a76-b0a4-69337532fcfc'::uuid,'ELECTRICAL',1,'ELECTRICAL-BAY-01','Electrical - PMB Bay 13'),
  ('4568081e-7232-4447-8806-77d15ab1dd01'::uuid,'ELECTRICAL',2,'ELECTRICAL-BAY-02','Electrical - PMB Bay 14'),
  ('a642d2fb-ecbe-4c6e-b6df-ce310039553e'::uuid,'ELECTRICAL',3,'ELECTRICAL-BAY-03','Electrical - PMB Bay 15'),
  ('29621a7c-60a7-4bfb-92e6-5867c518ed44'::uuid,'ELECTRICAL',4,'ELECTRICAL-BAY-04','Electrical - PMB Bay 16'),
  ('2ee8ca5c-6556-45f9-b0cd-20e98cc3452a'::uuid,'ELECTRICAL',5,'ELECTRICAL-BAY-05','Electrical - PMB Bay 17'),
  ('458648c7-5468-4ce5-a4e2-45a72006829c'::uuid,'ELECTRICAL',6,'ELECTRICAL-BAY-06','Electrical - PMB Bay 18'),
  ('7bffd1a7-f8c6-4781-9303-4262a4f1abad'::uuid,'ELECTRICAL',7,'ELECTRICAL-BAY-07','Electrical - PMB Bay 19'),
  ('88bfd1d0-5e69-473b-88e3-572135184022'::uuid,'ELECTRICAL',8,'ELECTRICAL-BAY-08','Electrical - PMB Bay 20'),
  ('5af51266-df78-4cb0-88e9-bc65af3bf656'::uuid,'ELECTRICAL',9,'ELECTRICAL-BAY-09','Electrical - PMB Bay 21'),
  ('3dd68646-b4a7-4c32-98fa-39e068b0b1e9'::uuid,'ELECTRICAL',10,'ELECTRICAL-BAY-10','Electrical - PMB Bay 22')),
 h(id,bay_number,code) AS (VALUES
  ('38ed4599-d9a1-41b3-a181-5b5bf091be2b'::uuid,3,'FABRICATION-BAY-03'),
  ('4a4d4f44-73f4-48fb-9e22-01b5d43a21e7'::uuid,4,'FABRICATION-BAY-04'),
  ('a739aa2b-eec8-4fb3-a051-1d9bec10f179'::uuid,5,'FABRICATION-BAY-05'),
  ('666e8838-d8bf-47cc-8e7b-4f6580840d14'::uuid,6,'FABRICATION-BAY-06'),
  ('7c1d1a1f-e666-4f50-ab79-f61c826c3c23'::uuid,7,'FABRICATION-BAY-07'),
  ('a774d3e1-01b1-46fa-b5ae-b44d104af31c'::uuid,8,'FABRICATION-BAY-08'),
  ('3fc1e88d-fef2-445a-9363-1127ba46494c'::uuid,9,'FABRICATION-BAY-09'),
  ('85143aff-7734-4678-9020-129225b4ea13'::uuid,10,'FABRICATION-BAY-10'),
  ('76cc2896-fea1-412c-8704-04a6a095259c'::uuid,11,'FABRICATION-BAY-11'),
  ('afabdb4e-84f6-4684-ade6-29fa7dec5641'::uuid,12,'FABRICATION-BAY-12'),
  ('d496db2f-864b-4927-b859-6a76156b05b4'::uuid,13,'FABRICATION-BAY-13')),
 x AS (SELECT m.code, b.id IS NOT NULL AND s.code=m.stage_code AND b.bay_number=m.bay_number AND b.code=m.code AND b.display_name=m.new_name AND b.is_active AS good
         FROM m LEFT JOIN public.workshop_bays b ON b.id=m.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id),
 y AS (SELECT h.code, b.id IS NOT NULL AND s.code='FABRICATION' AND b.bay_number=h.bay_number AND b.code=h.code AND NOT b.is_active
              AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings k WHERE k.bay_id=h.id AND k.deleted_at IS NULL) AS good
         FROM h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id),
 o AS (SELECT s.code, count(*) FILTER (WHERE b.is_active) n FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code IN ('BUS_4X4','TINT','TYRE') GROUP BY s.code),
 d AS (SELECT count(*) n FROM (SELECT display_name FROM public.workshop_bays GROUP BY display_name HAVING count(*)>1) z)
SELECT (SELECT bool_and(good) FROM x) AND (SELECT bool_and(good) FROM y) AND (SELECT n FROM d)=0
       AND coalesce((SELECT n FROM o WHERE code='BUS_4X4'),0)=10 AND coalesce((SELECT n FROM o WHERE code='TINT'),0)=2 AND coalesce((SELECT n FROM o WHERE code='TYRE'),0)=2 AS ok,
 coalesce('wrong name: '||(SELECT string_agg(code,', ' ORDER BY code) FROM x WHERE NOT good),'20/20 bays named per Craig''s list')
 ||'; '||coalesce('not hidden: '||(SELECT string_agg(code,', ' ORDER BY code) FROM y WHERE NOT good),'Fab 03-13 hidden (11)')
 ||'; active Bus/Tint/Tyre: '||coalesce((SELECT string_agg(code||' '||n,', ' ORDER BY code) FROM o),'none')||'; duplicate names: '||(SELECT n FROM d) AS detail$c$,
 true, 283, 'r483');

DO $g$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND metadata->>'release'='r483' AND metadata->>'action'='rename_pmb_bay_139' AND created_at=now())<>20
    OR (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND metadata->>'release'='r483' AND metadata->>'action'='deactivate_workshop_bay' AND created_at=now())<>11
   THEN RAISE EXCEPTION 'r483: expected 20 + 11 audit rows'; END IF;
 IF EXISTS(SELECT 1 FROM r483_rename m JOIN public.workshop_bays b ON b.id=m.id WHERE b.display_name<>m.new_name OR NOT b.is_active) THEN RAISE EXCEPTION 'r483: rename incomplete'; END IF;
 IF EXISTS(SELECT 1 FROM r483_hide h JOIN public.workshop_bays b ON b.id=h.id WHERE b.is_active) THEN RAISE EXCEPTION 'r483: hide incomplete'; END IF;
 -- Only display_name (20 bays) / is_active (11 bays) / version / updated_at changed; no bay added or removed; every other bay identical.
 IF EXISTS(SELECT 1 FROM r483_bays_before o FULL JOIN public.workshop_bays b USING(id)
            WHERE o.id IS NULL OR b.id IS NULL
               OR (o.j - ARRAY['display_name','is_active','version','updated_at']) IS DISTINCT FROM (to_jsonb(b) - ARRAY['display_name','is_active','version','updated_at'])
               OR (b.id NOT IN (SELECT id FROM r483_rename) AND b.id NOT IN (SELECT id FROM r483_hide) AND o.j IS DISTINCT FROM to_jsonb(b))
               OR (b.id IN (SELECT id FROM r483_rename) AND (o.j->>'is_active')::boolean IS DISTINCT FROM b.is_active)
               OR (b.id IN (SELECT id FROM r483_hide) AND o.j->>'display_name' IS DISTINCT FROM b.display_name))
   THEN RAISE EXCEPTION 'r483: a bay field other than the planned name / active flag changed'; END IF;
 -- Every booking row is identical (no booking moved, retimed or touched).
 IF EXISTS(SELECT 1 FROM r483_bookings_before o FULL JOIN public.workshop_bookings k USING(id) WHERE o.value IS DISTINCT FROM to_jsonb(k)) THEN RAISE EXCEPTION 'r483: a booking changed'; END IF;
 FOR r IN SELECT * FROM pdc_ops.fault_regression_check() WHERE check_name='pmb_bay_names_483' LOOP
   IF NOT r.ok THEN RAISE EXCEPTION 'r483: check failed: %', r.detail; END IF;
 END LOOP;
END $g$;
