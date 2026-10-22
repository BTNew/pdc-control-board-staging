-- r483 (F96) undo: puts the 20 Dept 139 bay names back exactly and re-activates the 11 Fab bays r483 hid (staging
-- cdsmnqxtyyoeoznmbidd only). Changes only display_name / is_active (+ version+1) on those 31 bays by id; never touches bookings,
-- bay numbers, stations, codes, Dept 138 or the shared bays. One audit_events 'rollback' row per bay; removes the r483 check row.
-- The r483 audit rows stay (history is kept). Undo the frontend first (revert the F96 commit) or together: the r483 frontend
-- draws 2 Fab bays and would not show Fab 03-13 again until reverted.
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
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r483 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r483 undo: staging only'; END IF;
 SELECT string_agg(m.code||' ('||coalesce(b.display_name,'missing')||')',', ' ORDER BY m.code) INTO v_bad
   FROM r483_rename m LEFT JOIN public.workshop_bays b ON b.id=m.id LEFT JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.id IS NULL OR s.code IS DISTINCT FROM m.stage_code OR b.bay_number IS DISTINCT FROM m.bay_number OR b.code IS DISTINCT FROM m.code
     OR b.display_name IS DISTINCT FROM m.new_name;
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r483 undo: bay(s) not at the r483 name (renamed since?): %', v_bad; END IF;
 SELECT string_agg(h.code,', ' ORDER BY h.bay_number) INTO v_bad
   FROM r483_hide h LEFT JOIN public.workshop_bays b ON b.id=h.id
  WHERE b.id IS NULL OR b.is_active OR b.code IS DISTINCT FROM h.code
     OR NOT EXISTS(SELECT 1 FROM public.audit_events a WHERE a.row_id=h.id AND a.table_name='workshop_bays' AND a.metadata->>'release'='r483' AND a.metadata->>'action'='deactivate_workshop_bay');
 IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'r483 undo: Fab bay(s) not hidden by r483: %', v_bad; END IF;
END $g$;

CREATE TEMP TABLE r483_bays_before ON COMMIT DROP AS SELECT b.id, to_jsonb(b) AS j FROM public.workshop_bays b;
CREATE TEMP TABLE r483_bookings_before ON COMMIT DROP AS SELECT k.id, to_jsonb(k) AS value FROM public.workshop_bookings k;

WITH upd AS (
  UPDATE public.workshop_bays b SET display_name=m.old_name, version=b.version+1
    FROM r483_rename m WHERE b.id=m.id AND b.display_name=m.new_name
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'rollback', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r483','fault','F96','action','rollback_rename_pmb_bay_139','old_name',o.j->>'display_name','new_name',u.display_name)
  FROM upd u JOIN r483_bays_before o ON o.id=u.id;

WITH upd AS (
  UPDATE public.workshop_bays b SET is_active=true, version=b.version+1
    FROM r483_hide h WHERE b.id=h.id AND NOT b.is_active
  RETURNING b.*
)
INSERT INTO public.audit_events(action, table_name, row_id, actor_id, actor_email, before_data, after_data, metadata)
SELECT 'rollback', 'workshop_bays', u.id, NULL, 'release@pdc.invalid', o.j, to_jsonb(u),
       jsonb_build_object('release','r483','fault','F96','action','rollback_deactivate_workshop_bay')
  FROM upd u JOIN r483_bays_before o ON o.id=u.id;

DELETE FROM pdc_ops.regression_checks WHERE check_name='pmb_bay_names_483' AND added_in='r483';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM r483_rename m JOIN public.workshop_bays b ON b.id=m.id WHERE b.display_name<>m.old_name) THEN RAISE EXCEPTION 'r483 undo: names not restored'; END IF;
 IF EXISTS(SELECT 1 FROM r483_hide h JOIN public.workshop_bays b ON b.id=h.id WHERE NOT b.is_active OR b.display_name<>h.name) THEN RAISE EXCEPTION 'r483 undo: Fab bays not re-activated'; END IF;
 IF (SELECT count(*) FROM public.audit_events WHERE table_name='workshop_bays' AND action='rollback' AND metadata->>'release'='r483' AND created_at=now())<>31 THEN RAISE EXCEPTION 'r483 undo: expected 31 audit rows'; END IF;
 IF EXISTS(SELECT 1 FROM r483_bays_before o FULL JOIN public.workshop_bays b USING(id)
            WHERE o.id IS NULL OR b.id IS NULL
               OR (b.id NOT IN (SELECT id FROM r483_rename) AND b.id NOT IN (SELECT id FROM r483_hide) AND o.j IS DISTINCT FROM to_jsonb(b))) THEN RAISE EXCEPTION 'r483 undo: another bay changed'; END IF;
 IF EXISTS(SELECT 1 FROM r483_bookings_before o FULL JOIN public.workshop_bookings k USING(id) WHERE o.value IS DISTINCT FROM to_jsonb(k)) THEN RAISE EXCEPTION 'r483 undo: a booking changed'; END IF;
END $g$;
