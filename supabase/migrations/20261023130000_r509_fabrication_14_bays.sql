-- r509 (F122, Craig Watson): Fabrication has exactly 14 bays.
-- Staging cdsmnqxtyyoeoznmbidd only (never vjdtsswhroyguxyfjdkt). PREVIEW. Do not apply from this file's author;
-- apply later on staging, in the :02-:45 release-test window. Do not merge to production.
-- Before this release (read on staging 23 Oct 2026): 13 public.workshop_bays rows on FABRICATION.
--   Bays 01 and 02 are active (r483 names: Internal Fabrication - PMB Bay 11, External Fabrication - PMB Bay 12).
--   Bays 03-13 exist, are inactive, and still carry 'Fab Bay NN' (r483 hid them; it did not delete them).
-- This release:
--   1. Sets is_active=true (+ version+1) on those 11 rows, the reverse of public.set_workshop_bay_active's hide.
--      id, stage, bay_number, code, display_name, efficiency (Bay 09 stays 80%), technician and sublet flag stay.
--   2. Inserts FABRICATION-BAY-14 (id b14fab14-0509-4230-8fab-000000000014, display_name 'Fab Bay 14',
--      efficiency 100, active, not a sublet row).
--   3. Updates pmb_bay_names_483 so the daily check no longer requires Fab 03-13 to be hidden with no booking.
--      The 20 r483 names stay pinned. New check fabrication_bays_14_509 (F122, sort 294) requires exactly
--      these 14 active fabrication rows and no other fabrication row.
-- Never touches a booking, Dept 138, Tint, Tyre, Hoist, Fitting or Electrical. The existing statement trigger
-- workshop_bump_all_station_revisions() advances workshop_station_revision for every stage; that is the same
-- side effect as any bay edit (including r483) and is not reversed to an old revision number.
-- Frontend (same release): the planner and PMB bay board read PMB_STAGE_BAY_COUNTS.FABRICATION = 14.
-- Undo: supabase/rollbacks/20261023130000_r509_fabrication_14_bays.down.sql
--   (refuses if Fab 03-14 have a booking, admin block, parts override or bay activity event).
SET LOCAL lock_timeout = '2s';
CREATE TEMP TABLE r509_reactivate(id uuid PRIMARY KEY, bay_number integer NOT NULL, code text NOT NULL, name text NOT NULL) ON COMMIT DROP;
INSERT INTO r509_reactivate VALUES
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
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r509: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r509: staging only'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='fabrication_bays_14_509' OR added_in='r509') THEN RAISE EXCEPTION 'r509: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=294 OR fault_id='F122') THEN RAISE EXCEPTION 'r509: sort_order 294 / F122 taken'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bays WHERE id='b14fab14-0509-4230-8fab-000000000014'::uuid OR code='FABRICATION-BAY-14' OR display_name='Fab Bay 14') THEN RAISE EXCEPTION 'r509: Fab Bay 14 already exists'; END IF;
 IF (SELECT count(*) FROM r509_reactivate)<>11 THEN RAISE EXCEPTION 'r509: reactivate map must have 11 rows'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483' AND added_in='r483' AND fault_id='F96')
      IS DISTINCT FROM 'f3587293c462a257df388db475a327b1' THEN RAISE EXCEPTION 'r509: pmb_bay_names_483 is not the r483 check this release replaces'; END IF;
 IF (SELECT count(*) FROM public.workshop_stages WHERE code='FABRICATION')<>1 THEN RAISE EXCEPTION 'r509: expected one FABRICATION stage'; END IF;
 IF (SELECT count(*) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='FABRICATION')<>13 THEN RAISE EXCEPTION 'r509: expected 13 fabrication bays before adding Bay 14'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
                WHERE b.id='8707df84-f06d-4532-a716-54b1b812a8f7'::uuid AND s.code='FABRICATION' AND b.bay_number=1 AND b.code='FABRICATION-BAY-01'
                  AND b.display_name='Internal Fabrication - PMB Bay 11' AND b.is_active)
    OR NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
                WHERE b.id='246c823d-fe26-4d15-a7e9-f5b8e711cbc9'::uuid AND s.code='FABRICATION' AND b.bay_number=2 AND b.code='FABRICATION-BAY-02'
                  AND b.display_name='External Fabrication - PMB Bay 12' AND b.is_active)
   THEN RAISE EXCEPTION 'r509: Fab Bays 01 and 02 are not the r483 Internal / External rows'; END IF;
 SELECT string_agg(h.code||' ('||coalesce(b.display_name,'missing')||', active='||coalesce(b.is_active::text,'missing')||')', ', ' ORDER BY h.bay_number) INTO v_bad
   FROM r509_reactivate h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id IS NULL OR s.code IS DISTINCT FROM 'FABRICATION' OR b.bay_number IS DISTINCT FROM h.bay_number OR b.code IS DISTINCT FROM h.code
     OR b.display_name IS DISTINCT FROM h.name OR b.is_active OR b.is_sublet_row;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r509: Fab bay(s) to reactivate changed since prepared: %', v_bad; END IF;
END $g$;

CREATE TEMP TABLE r509_bays_before ON COMMIT DROP AS SELECT b.id, to_jsonb(b) AS j FROM public.workshop_bays b;
CREATE TEMP TABLE r509_bookings_before ON COMMIT DROP AS SELECT k.id, to_jsonb(k) AS value FROM public.workshop_bookings k;

WITH upd AS (
  UPDATE public.workshop_bays b SET is_active=true, version=b.version+1
    FROM r509_reactivate h WHERE b.id=h.id AND NOT b.is_active AND b.code=h.code AND b.display_name=h.name AND b.bay_number=h.bay_number
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'reference_change', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r509','fault','F122','action','activate_workshop_bay','department','139',
                          'source','Craig Watson: Fabrication has exactly 14 bays; r483 had hidden Fab 03-13')
  FROM upd u JOIN r509_bays_before o ON o.id=u.id;

INSERT INTO public.workshop_bays(id, stage_id, bay_number, code, display_name, is_active, is_sublet_row, efficiency_percent, version)
SELECT 'b14fab14-0509-4230-8fab-000000000014'::uuid, s.id, 14, 'FABRICATION-BAY-14', 'Fab Bay 14', true, false, 100, 1
  FROM public.workshop_stages s WHERE s.code='FABRICATION';

INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'reference_change', 'workshop_bays', b.id, NULL, 'release@pdc.invalid', NULL, to_jsonb(b),
       jsonb_build_object('release','r509','fault','F122','action','insert_workshop_bay','department','139',
                          'source','Craig Watson: Fabrication Bay 14','code',b.code,'bay_number',b.bay_number)
  FROM public.workshop_bays b WHERE b.id='b14fab14-0509-4230-8fab-000000000014'::uuid;

UPDATE pdc_ops.regression_checks
   SET description = 'Dept 139 bays per Craig (r483), after r509: 20 bays keep id, station, bay number and code and carry his names (Hoist 01-03 = PMB Bays 01-03, Fitting 01-05 = 06-10, Fab 01/02 = Internal/External Fabrication 11/12, Elec 01-10 = 13-22); Fab Bays 03-13 exist and are active (r509 turned the r483 hide back on); Bus 4x4 keeps 10 active bays and Tint / Tyre 2 each; no two bays share a name. Exactly 14 active fabrication bays is fabrication_bays_14_509.',
       check_sql = $r509upd$WITH m(id,stage_code,bay_number,code,new_name) AS (VALUES
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
 y AS (SELECT h.code, b.id IS NOT NULL AND s.code='FABRICATION' AND b.bay_number=h.bay_number AND b.code=h.code AND b.is_active AS good
         FROM h LEFT JOIN public.workshop_bays b ON b.id=h.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id),
 o AS (SELECT s.code, count(*) FILTER (WHERE b.is_active) n FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
        WHERE s.code IN ('BUS_4X4','TINT','TYRE') GROUP BY s.code),
 d AS (SELECT count(*) n FROM (SELECT display_name FROM public.workshop_bays GROUP BY display_name HAVING count(*)>1) z)
SELECT (SELECT bool_and(good) FROM x) AND (SELECT bool_and(good) FROM y) AND (SELECT n FROM d)=0
       AND coalesce((SELECT n FROM o WHERE code='BUS_4X4'),0)=10 AND coalesce((SELECT n FROM o WHERE code='TINT'),0)=2 AND coalesce((SELECT n FROM o WHERE code='TYRE'),0)=2 AS ok,
 coalesce('wrong name: '||(SELECT string_agg(code,', ' ORDER BY code) FROM x WHERE NOT good),'20/20 bays named per Craig''s list')
 ||'; '||coalesce('not active: '||(SELECT string_agg(code,', ' ORDER BY code) FROM y WHERE NOT good),'Fab 03-13 active (11)')
 ||'; active Bus/Tint/Tyre: '||coalesce((SELECT string_agg(code||' '||n,', ' ORDER BY code) FROM o),'none')||'; duplicate names: '||(SELECT n FROM d) AS detail$r509upd$
 WHERE check_name='pmb_bay_names_483' AND added_in='r483' AND fault_id='F96';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES (
 'fabrication_bays_14_509', 'F122',
 'Fabrication has exactly 14 active bays (r509): Bay 01 Internal Fabrication - PMB Bay 11, Bay 02 External Fabrication - PMB Bay 12, Bays 03-13 the existing Fab Bay rows r483 had hidden, and Bay 14 Fab Bay 14. Same ids, numbers, codes and names. No other fabrication row. A later fabrication bay add or hide must update this check.',
 $r509new$WITH e(bay_number,id,code,display_name) AS (VALUES
 (1,'8707df84-f06d-4532-a716-54b1b812a8f7'::uuid,'FABRICATION-BAY-01','Internal Fabrication - PMB Bay 11'),
 (2,'246c823d-fe26-4d15-a7e9-f5b8e711cbc9'::uuid,'FABRICATION-BAY-02','External Fabrication - PMB Bay 12'),
 (3,'38ed4599-d9a1-41b3-a181-5b5bf091be2b'::uuid,'FABRICATION-BAY-03','Fab Bay 03'),
 (4,'4a4d4f44-73f4-48fb-9e22-01b5d43a21e7'::uuid,'FABRICATION-BAY-04','Fab Bay 04'),
 (5,'a739aa2b-eec8-4fb3-a051-1d9bec10f179'::uuid,'FABRICATION-BAY-05','Fab Bay 05'),
 (6,'666e8838-d8bf-47cc-8e7b-4f6580840d14'::uuid,'FABRICATION-BAY-06','Fab Bay 06'),
 (7,'7c1d1a1f-e666-4f50-ab79-f61c826c3c23'::uuid,'FABRICATION-BAY-07','Fab Bay 07'),
 (8,'a774d3e1-01b1-46fa-b5ae-b44d104af31c'::uuid,'FABRICATION-BAY-08','Fab Bay 08'),
 (9,'3fc1e88d-fef2-445a-9363-1127ba46494c'::uuid,'FABRICATION-BAY-09','Fab Bay 09'),
 (10,'85143aff-7734-4678-9020-129225b4ea13'::uuid,'FABRICATION-BAY-10','Fab Bay 10'),
 (11,'76cc2896-fea1-412c-8704-04a6a095259c'::uuid,'FABRICATION-BAY-11','Fab Bay 11'),
 (12,'afabdb4e-84f6-4684-ade6-29fa7dec5641'::uuid,'FABRICATION-BAY-12','Fab Bay 12'),
 (13,'d496db2f-864b-4927-b859-6a76156b05b4'::uuid,'FABRICATION-BAY-13','Fab Bay 13'),
 (14,'b14fab14-0509-4230-8fab-000000000014'::uuid,'FABRICATION-BAY-14','Fab Bay 14')),
 g AS (SELECT b.bay_number,b.id,b.code,b.display_name,b.is_active,b.is_sublet_row
         FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='FABRICATION'),
 bad AS (SELECT coalesce(e.code,g.code) AS code, coalesce(e.bay_number,g.bay_number) AS bay_number
           FROM e FULL JOIN g ON g.id=e.id
          WHERE e.id IS NULL OR g.id IS NULL OR g.bay_number IS DISTINCT FROM e.bay_number OR g.code IS DISTINCT FROM e.code
             OR g.display_name IS DISTINCT FROM e.display_name OR NOT g.is_active OR g.is_sublet_row)
SELECT (SELECT count(*) FROM g)=14 AND (SELECT count(*) FROM g WHERE is_active AND NOT is_sublet_row)=14 AND NOT EXISTS(SELECT 1 FROM bad) AS ok,
 'fabrication rows '||(SELECT count(*) FROM g)||', active '||(SELECT count(*) FILTER (WHERE is_active) FROM g)
 || coalesce('; off: '||(SELECT string_agg(code,', ' ORDER BY bay_number) FROM bad),'') AS detail$r509new$,
 true, 294, 'r509');

DO $g$ DECLARE r record; BEGIN
 IF (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND metadata->>'release'='r509' AND metadata->>'action'='activate_workshop_bay' AND created_at=now())<>11
    OR (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND metadata->>'release'='r509' AND metadata->>'action'='insert_workshop_bay' AND created_at=now())<>1
   THEN RAISE EXCEPTION 'r509: expected 11 + 1 audit rows'; END IF;
 IF (SELECT count(*) FROM public.workshop_bays WHERE id='b14fab14-0509-4230-8fab-000000000014'::uuid AND code='FABRICATION-BAY-14' AND bay_number=14 AND display_name='Fab Bay 14' AND is_active AND NOT is_sublet_row AND efficiency_percent=100)<>1
   THEN RAISE EXCEPTION 'r509: Bay 14 did not land'; END IF;
 IF EXISTS(SELECT 1 FROM r509_reactivate h JOIN public.workshop_bays b ON b.id=h.id WHERE NOT b.is_active OR b.display_name<>h.name OR b.version IS DISTINCT FROM ((SELECT (o.j->>'version')::integer FROM r509_bays_before o WHERE o.id=h.id)+1))
   THEN RAISE EXCEPTION 'r509: reactivate incomplete'; END IF;
 IF EXISTS(SELECT 1 FROM r509_bays_before o FULL JOIN public.workshop_bays b USING(id)
            WHERE (o.id IS NULL AND b.id IS DISTINCT FROM 'b14fab14-0509-4230-8fab-000000000014'::uuid)
               OR (b.id IS NULL)
               OR (o.id IS NOT NULL AND b.id NOT IN (SELECT id FROM r509_reactivate)
                   AND o.j IS DISTINCT FROM to_jsonb(b))
               OR (b.id IN (SELECT id FROM r509_reactivate)
                   AND (o.j - ARRAY['is_active','version','updated_at']) IS DISTINCT FROM (to_jsonb(b) - ARRAY['is_active','version','updated_at'])))
   THEN RAISE EXCEPTION 'r509: a bay field other than the planned active flag changed, or an unexpected bay appeared'; END IF;
 IF EXISTS(SELECT 1 FROM r509_bookings_before o FULL JOIN public.workshop_bookings k USING(id) WHERE o.value IS DISTINCT FROM to_jsonb(k)) THEN RAISE EXCEPTION 'r509: a booking changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483' AND added_in='r483') IS DISTINCT FROM 'ddec61058565f4b2bde2223816dea9e2' THEN RAISE EXCEPTION 'r509: pmb_bay_names_483 did not land as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='fabrication_bays_14_509' AND added_in='r509' AND sort_order=294 AND fault_id='F122') IS DISTINCT FROM '9354c95694a44bbc7aeda68e50eafa37' THEN RAISE EXCEPTION 'r509: fabrication_bays_14_509 did not land as expected'; END IF;
 FOR r IN SELECT * FROM pdc_ops.fault_regression_check() WHERE check_name IN ('pmb_bay_names_483','fabrication_bays_14_509') LOOP
   IF NOT r.ok THEN RAISE EXCEPTION 'r509: check % failed: %', r.check_name, r.detail; END IF;
 END LOOP;
END $g$;
