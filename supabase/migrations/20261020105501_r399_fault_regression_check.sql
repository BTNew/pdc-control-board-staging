-- r399 Part B: daily fault regression check (read-only). Staging cdsmnqxtyyoeoznmbidd only.
-- Run: select * from pdc_ops.fault_regression_check();
-- Add a check for a new fault: INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,sort_order,added_in)
--   VALUES ('my_check','F09','...', 'SELECT <boolean> AS ok, <text> AS detail', 170, 'r4xx');  (one row; it must be read-only)
-- A release that changes a pinned function updates its row in pdc_ops.expected_function_md5 in the same migration.
DO $g$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='cdsmnqxtyyoeoznmbidd')
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r399 ops: staging only'; END IF;
 IF to_regclass('pdc_work_categories_private.offboard_done') IS NULL THEN RAISE EXCEPTION 'r399 ops: apply r399 first'; END IF;
 IF to_regnamespace('pdc_ops') IS NOT NULL THEN RAISE EXCEPTION 'r399 ops: already applied'; END IF;
END $g$;
CREATE SCHEMA pdc_ops;
REVOKE ALL ON SCHEMA pdc_ops FROM PUBLIC;
GRANT USAGE ON SCHEMA pdc_ops TO service_role, authenticated;
CREATE TABLE pdc_ops.expected_function_md5(
 signature text PRIMARY KEY,
 prosrc_md5 text NOT NULL CHECK (prosrc_md5 ~ '^[0-9a-f]{32}$'),
 release text NOT NULL,
 note text,
 updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE pdc_ops.regression_checks(
 check_name text PRIMARY KEY CHECK (check_name ~ '^[a-z0-9_]+$'),
 fault_id text NOT NULL,
 description text NOT NULL,
 check_sql text NOT NULL,
 enabled boolean NOT NULL DEFAULT true,
 sort_order integer NOT NULL,
 added_in text NOT NULL);
ALTER TABLE pdc_ops.expected_function_md5 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_ops.regression_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_ops.expected_function_md5, pdc_ops.regression_checks FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.workshop_clock_tick(boolean,timestamp with time zone)','84af7607bfd0ce9907c89bae8644d5b6','#368','clock tick - do not interfere'),
 ('public.start_workshop_work_pre_116(uuid,integer,timestamp with time zone,jsonb)','40ab1b0a75d347b56c69e54c65ddd193','#380','Bus start on the Bus calendar (PMB Email hands-off)'),
 ('pdc_bus_private.add_minutes(timestamp with time zone,integer,uuid)','c43afa5c1312392aa5d3666a8aa7cf65','20261020015824','clock slowdown fix'),
 ('pdc_bus_private.clock_add_minutes(timestamp with time zone,integer,uuid)','d0a395e6739423c1e4f5f2329fa5cd75','#380',NULL),
 ('pdc_bus_private.booking_rule(uuid,uuid,uuid)','55e1810fd2a47a29c9608a55ae292741','baseline','Bay 3 HiAce-only'),
 ('pdc_bus_private.booking_shift_guard()','245d4bf9a0324bc65563f48c1a62c619','baseline','Bus shift guard'),
 ('pdc_work_categories_private.preferred_bay(text,integer)','9a785c3f4301213c4dae78e3717611ee','baseline','preferred bays'),
 ('pdc_work_categories_private.allowed_bay(text,integer)','a9e529f8e2153924fd8a5d323084f1c1','#386','Bays 9/10 accept MECH/ELEC/ACC'),
 ('pdc_work_categories_private.capture_scope()','8fac512c435782ee712a7a46680f0b9c','#386','category_bay_mismatch rule'),
 ('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)','cfdd37872dd80c1e456a1863dccadca8','#386',NULL),
 ('public.workshop_enforce_booking_lifecycle()','94230674500701543bcaf93e58158a54','baseline','booking lifecycle'),
 ('pdc_work_categories_private.hours(uuid,text)','e01e0cd55ddb1b8d05d6ec952debf8d6','baseline',NULL),
 ('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)','4952bea1ccb019c7d1dfe0dc873a5c67','#387','multiple Start/Done items'),
 ('pdc_fitter_private.progress(uuid)','2eccf8ad296d2ae89f873d1eb5050ca5','#387',NULL),
 ('pdc_fitter_private.item_timing_save(uuid,uuid,jsonb,text,text)','3d02199b82afb222a05a01baac0a3c18','#387',NULL),
 ('pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)','39b8f50d21d7932e671c31a5d539001d','#387','sections may run together'),
 ('public.reset_fitter_item_timing(uuid,text,text,text)','d5461e0e53d359d30ff31365abe5b501','#387',NULL),
 ('pdc_codex_intake_private.apply_service_pmb_complete(uuid)','eea5bb523c2538742db52508665191d3','baseline','PMB Email Sub Status 80'),
 ('pdc_codex_intake_private.finish_tune_checkout(uuid)','3e5c6b28e7c025a6ebbae61879ff3a82','baseline','PMB Email Sub Status 99'),
 ('public.get_workshop_booking_search_scoped(jsonb)','1d4b86872f7559b106f40dbadd3f907f','baseline','booking search'),
 ('public.get_vehicle_workshop_detail_scoped(uuid,text)','2e059658db08521d92103504ddff7c97','baseline',NULL),
 ('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)','47c743a8c0a8eebf176a3b5485b0bf98','baseline',NULL),
 ('pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(jsonb,uuid,text)','5df1cb2c8dcafd25148f5b43aaf4f67f','baseline',NULL),
 ('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)','e45bbe3ddc4d30c1845099ee3efd33c0','r390','Key 243 + mixed 138/139 read'),
 ('public.pdc_qc_operation_lines_379(uuid)','b7f90bff12643229ff80f8ca552663a2','baseline','QC lines (cached)'),
 ('public.pdc_qc_operation_lines_379_uncached(uuid)','b677d7bfdf67c046fd05922da249325c','baseline',NULL),
 ('pdc_work_categories_private.invalidate_qc_operation_lines_cache()','00f532fdd214dcd242c267616f43bc7f','baseline',NULL),
 ('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)','c9bad5fb2c6ce6f549539fc06647a215','baseline',NULL),
 ('public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)','f76a8333a700a66158bf60ab7ca536d8','r391','Close gaps'),
 ('pdc_sales_private.sales_accessory_tick(jsonb,text)','d428d8808dd3770ed3001ce2be6e9e4f','r394','derived-only ticks'),
 ('pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)','777c24b152c73878914f4d66c23c2817','r394','refuses for all roles'),
 ('pdc_sales_private.set_ordering_status(uuid,text,text,integer)','777c24b152c73878914f4d66c23c2817','r394','refuses for all roles'),
 ('pdc_sales_private.get_accessories()','49f6feab0ef97e1f515cf9d8c5de4fd9','r394',NULL),
 ('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)','ee577536b060c7447e1a4ff352250b79','r396','PMB Email accessory import'),
 ('pdc_sales_private.sales_accessory_normalize(jsonb,jsonb)','8ab9269a3e43bb60f60177f295f42167','r396',NULL),
 ('pdc_fitter_private.conversion_completion_guard()','4222b51b637b85cf22315b38f7ea16d4','r399',NULL),
 ('pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)','ed61f7d555d910abbf02b7ede6bda288','r399',NULL),
 ('pdc_work_categories_private.line_completed(uuid,jsonb)','0c8cc64db074645da4adea3be9d15a79','r399',NULL),
 ('pdc_work_categories_private.completed(uuid,text)','7039c06acd173d890c4d7ffbdd4b749d','r399',NULL),
 ('pdc_work_categories_private.vehicle_categories(uuid)','0f77e09d7ab31418082bf4beb6af036a','r399',NULL),
 ('public.confirm_bus_category_done(uuid,integer,text,text,text[])','77925eadb63b0433cdb4580acf2be911','r399',NULL),
 ('public.undo_bus_category_done(uuid,integer,text,text)','4e82a43eefa6926c99c94946a2154db2','r399',NULL),
 ('pdc_work_categories_private.offboard_line_done(uuid,jsonb)','8d284834b9ee42a0a4aad005d74be164','r399',NULL),
 ('pdc_work_categories_private.offboard_identity_done(uuid,text)','d4113167414b3f3361af32abb5942607','r399',NULL);
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,sort_order,added_in) VALUES
 ('bays_9_10_accept_mech_elec_acc','F01','Bus Bays 9 and 10 accept Mechanical, Electrical and Accessories work (not QA).',$c$SELECT bool_and(pdc_work_categories_private.allowed_bay(c,b)) AND NOT pdc_work_categories_private.allowed_bay('BUS_QA',9) AND NOT pdc_work_categories_private.allowed_bay('BUS_QA',10) AS ok,
 'allowed_bay MECH/ELEC/ACC x 9/10 all true; QA 9/10 false' AS detail
FROM unnest(ARRAY['BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES']) c, unnest(ARRAY[9,10]) b$c$,10,'r399'),
 ('bus_bay_category_grid','F01,F08','Full Bus bay/category grid: MECH 1-4,9,10; ELEC 8-10; ACC 9-10; QA 7 only.',$c$WITH e(cat,bays) AS (VALUES ('BUS_MECHANICAL',ARRAY[1,2,3,4,9,10]),('BUS_ELECTRICAL',ARRAY[8,9,10]),('BUS_ACCESSORIES',ARRAY[9,10]),('BUS_QA',ARRAY[7])),
 g AS (SELECT e.cat,b,(b=ANY(e.bays)) want,pdc_work_categories_private.allowed_bay(e.cat,b) got FROM e, generate_series(1,10) b)
SELECT count(*) FILTER (WHERE want IS DISTINCT FROM got)=0 AS ok,
 coalesce('mismatch: '||string_agg(cat||' bay '||b||' got '||got,', ') FILTER (WHERE want IS DISTINCT FROM got),'40 cells match') AS detail FROM g$c$,20,'r399'),
 ('bay3_hiace_only','F01','Bus Bay 3 refuses a Coaster and accepts a HiAce (booking_rule).',$c$WITH bay AS (SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=3),
 co AS (SELECT v.id FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND concat_ws(' ',v.model,v.vehicle_description)~*'coaster' AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1),
 hi AS (SELECT v.id FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND concat_ws(' ',v.model,v.vehicle_description)~*'hi[[:space:]-]?ace' AND concat_ws(' ',v.model,v.vehicle_description)!~*'coaster' AND pdc_bus_private.active_vehicle(v.id) ORDER BY v.id LIMIT 1),
 r AS (SELECT (SELECT pdc_bus_private.booking_rule(co.id,bay.id,NULL)->>'error' FROM co,bay) coaster,(SELECT pdc_bus_private.booking_rule(hi.id,bay.id,NULL)->>'ok' FROM hi,bay) hiace)
SELECT (coaster IS NULL OR coaster='bus_bay_vehicle_incompatible') AND (hiace IS NULL OR hiace='true') AND position('bay=3' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure))>0 AS ok,
 'coaster in bay 3: '||coalesce(coaster,'no active Coaster to test')||'; hiace ok: '||coalesce(hiace,'no active HiAce to test') AS detail FROM r$c$,30,'r399'),
 ('bay8_electrical_and_offboard_confirm','F08','Bay 8 takes Bus Electrical (not Mechanical); managers can confirm work done off the board; the conversion guard honours it.',$c$SELECT pdc_work_categories_private.allowed_bay('BUS_ELECTRICAL',8) AND NOT pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',8)
 AND position('category_bay_mismatch' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure))>0
 AND to_regprocedure('public.confirm_bus_category_done(uuid,integer,text,text,text[])') IS NOT NULL
 AND has_function_privilege('authenticated','public.confirm_bus_category_done(uuid,integer,text,text,text[])','EXECUTE')
 AND NOT has_function_privilege('anon','public.confirm_bus_category_done(uuid,integer,text,text,text[])','EXECUTE')
 AND position('offboard_identity_done' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_fitter_private.conversion_completion_guard()'::regprocedure))>0
 AND position('offboard_done' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_work_categories_private.line_completed(uuid,jsonb)'::regprocedure))>0 AS ok,
 'ELEC->8 allowed, MECH->8 refused, confirm RPC authenticated-only, guard and line_completed honour confirmations; active confirmations: '||(SELECT count(*) FROM pdc_work_categories_private.offboard_done WHERE revoked_at IS NULL) AS detail$c$,40,'r399'),
 ('multiple_started_items_allowed','F02','Fitters can run several items/sections at once (no single-start limit).',$c$SELECT position('conversion_section_in_progress' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_fitter_private.conversion_save(uuid,uuid,text,jsonb)'::regprocedure))=0
 AND position('item_timing_tick' IN (SELECT prosrc FROM pg_proc WHERE oid='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure))>0 AS ok,
 'conversion_save has no one-section-at-a-time refusal; fitter_job_command has item timing' AS detail$c$,50,'r399'),
 ('close_gaps_fingerprint_excludes_clock_fields','F03','Close gaps preview fingerprint ignores the fields the minute clock re-times.',$c$SELECT position($q$x.before_row-ARRAY['version','updated_at','updated_by','scheduled_start_at','scheduled_end_at']$q$ IN p.prosrc)>0
 AND position($q$to_jsonb(a)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at']$q$ IN p.prosrc)>0 AS ok,
 'planned rows and assignments hashed without clock-managed fields' AS detail
FROM pg_proc p WHERE p.oid='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::regprocedure$c$,60,'r399'),
 ('bus_plans_use_bay_shift','F03','Close gaps plans Bus 4x4 work on each bays Bus shift.',$c$SELECT position('pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id' IN p.prosrc)>0 AS ok,
 'capacity plan passes the bay calendar for active Dept 138 Bus bookings' AS detail
FROM pg_proc p WHERE p.oid='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::regprocedure$c$,70,'r399'),
 ('clock_ticks_recent','GENERAL','workshop_clock_tick ran every minute for the last 30 minutes, none failed, p95 under 2 s.',$c$WITH d AS (SELECT d.status, extract(epoch FROM d.end_time-d.start_time)*1000 ms FROM cron.job_run_details d JOIN cron.job j ON j.jobid=d.jobid
  WHERE j.jobname='staging-workshop-clock-cascade' AND d.start_time>now()-interval '30 minutes')
SELECT count(*)>=25 AND count(*) FILTER (WHERE status<>'succeeded')=0 AND coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY ms),0)<2000 AS ok,
 count(*)||' runs, '||count(*) FILTER (WHERE status<>'succeeded')||' not succeeded, p95 '||round(coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY ms),0)::numeric)||' ms, max '||round(coalesce(max(ms),0)::numeric)||' ms' AS detail FROM d$c$,80,'r399'),
 ('qc_cache_zero_mismatches','GENERAL','Every cached QC line set equals a fresh computation.',$c$SELECT count(*) FILTER (WHERE c.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(c.vehicle_id))=0 AS ok,
 count(*)||' cached, '||count(*) FILTER (WHERE c.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(c.vehicle_id))||' mismatches' AS detail
FROM pdc_work_categories_private.qc_operation_lines_cache c$c$,90,'r399'),
 ('no_orphan_bookings','GENERAL','No active booking points at a missing/deleted/inactive vehicle or a bay of another station.',$c$WITH a AS (SELECT b.id,b.status,b.vehicle_id,b.bay_id,b.stage_id,bay.stage_id bay_stage FROM public.workshop_bookings b LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage'))
SELECT count(*)=0 AS ok, coalesce(count(*)||' orphan: '||string_agg(left(a.id::text,8)||' '||a.status,', '),'0 orphan bookings') AS detail
FROM a LEFT JOIN public.vehicles v ON v.id=a.vehicle_id
WHERE v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' OR (a.bay_id IS NOT NULL AND a.bay_stage IS DISTINCT FROM a.stage_id)$c$,100,'r399'),
 ('no_double_booked_bays','GENERAL','No two planned/started/stoppage bookings overlap in the same physical bay.',$c$WITH a AS (SELECT b.id,b.bay_id,b.scheduled_start_at s,b.scheduled_end_at e FROM public.workshop_bookings b JOIN public.workshop_stages st ON st.id=b.stage_id
  WHERE b.deleted_at IS NULL AND b.status IN('planned','started','stoppage') AND b.bay_id IS NOT NULL AND NOT coalesce(st.is_sublet,false))
SELECT count(*)=0 AS ok, coalesce(count(*)||' overlaps: '||string_agg(left(x.id::text,8)||'/'||left(y.id::text,8),', '),'0 overlaps') AS detail
FROM a x JOIN a y ON x.bay_id=y.bay_id AND x.id<y.id AND tstzrange(x.s,x.e) && tstzrange(y.s,y.e)$c$,110,'r399'),
 ('no_booking_breaks_bay_category_rule','F01,F08','No active Bus category booking sits in a bay its category may not use.',$c$SELECT count(*)=0 AS ok, coalesce(count(*)||' violations: '||string_agg(left(b.id::text,8)||' '||b.work_category||' bay '||bay.bay_number,', '),'0 violations') AS detail
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.work_category IS NOT NULL
 AND NOT pdc_work_categories_private.allowed_bay(b.work_category,bay.bay_number)$c$,120,'r399'),
 ('dept138_read_complete','F04,F05,F08','Every Dept 138 Tune job (138-only or mixed 138/139) is readable by the Dept 138 delegated scope (search/detail).',$c$WITH s AS (SELECT '{"role":"operator","environment":"staging","dealer_code":"14450","department_scope":"138"}'::jsonb sc),
c AS (SELECT v.id, v.key_number, v.stock_number FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
 WHERE v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
 AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
 AND (v.source_system='tune_pmg' OR (v.source_system='microsoft_navision' AND v.permanent_vehicle_id='TUNE/PMG:'||v.stock_number AND v.source_payload->>'intake_source_system'='tune_pmg'))
 AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
 AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR NOT coalesce(j.departments IN (ARRAY['138']::text[],ARRAY['139']::text[]),false) OR j.stock_number IS DISTINCT FROM v.stock_number))
 AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS NULL OR o.department NOT IN ('138','139') OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))),
x AS (SELECT c.*, pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s.sc,c.id,'14450') readable FROM c, s)
SELECT count(*) FILTER (WHERE NOT readable)=0 AS ok,
 count(*)||' Dept 138 jobs, '||count(*) FILTER (WHERE NOT readable)||' unreadable'||coalesce(': keys '||string_agg(key_number,', ') FILTER (WHERE NOT readable),'') AS detail FROM x$c$,130,'r399'),
 ('karratha_135_hidden_data_kept','STANDING','Karratha 135 stays hidden (not readable by Dept 138, no realtime, its clock job off) and its data still exists.',$c$WITH s AS (SELECT '{"role":"operator","environment":"staging","dealer_code":"14450","department_scope":"138"}'::jsonb sc)
SELECT (SELECT count(*) FROM karratha135_pdc.vehicles)>0
 AND NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE schemaname ~ '^karratha')
 AND NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname ~ '^k135' AND active)
 AND (SELECT count(*) FROM public.vehicles v, s WHERE v.deleted_at IS NULL AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND '135'=ANY(j.departments))
   AND pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s.sc,v.id,'14450'))=0 AS ok,
 'karratha135_pdc.vehicles '||(SELECT count(*) FROM karratha135_pdc.vehicles)||' rows; realtime tables '||(SELECT count(*) FROM pg_publication_tables WHERE schemaname ~ '^karratha')||'; active k135 cron jobs '||(SELECT count(*) FROM cron.job WHERE jobname ~ '^k135' AND active) AS detail$c$,140,'r399'),
 ('sales_ticks_derived_only','F07','TINT/BUILD/TRAY ticks come only from PO lines; manual tick writes are refused for all roles.',$c$SELECT pdc_sales_private.sales_accessory_tick('[]'::jsonb,'BUILD')->>'state'='grey'
 AND pdc_sales_private.sales_accessory_tick('[{"line_class":"BUILD","po_state":"blank"}]'::jsonb,'BUILD')->>'state'='red'
 AND pdc_sales_private.sales_accessory_tick('[{"line_class":"BUILD","po_state":"po"}]'::jsonb,'BUILD')->>'state'='green'
 AND position('cannot be changed here' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_sales_private.set_ordering_flag(uuid,text,boolean,integer)'::regprocedure))>0
 AND position('cannot be changed here' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_sales_private.set_ordering_status(uuid,text,text,integer)'::regprocedure))>0 AS ok,
 'grey/red/green from PO lines; set_ordering_flag/status refuse' AS detail$c$,150,'r399'),
 ('sales_board_has_vehicles','F06','The Sales board source is not empty (an empty Sales table is then a filter or browser state).',$c$SELECT count(*)>0 AND to_regprocedure('public.get_broome_sales_board_snapshot()') IS NOT NULL AS ok,
 count(*)||' active board vehicles; get_broome_sales_board_snapshot '||CASE WHEN to_regprocedure('public.get_broome_sales_board_snapshot()') IS NULL THEN 'MISSING' ELSE 'present' END AS detail
FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board$c$,160,'r399'),
 ('protected_function_md5s','GENERAL','Every pinned function body matches pdc_ops.expected_function_md5 (a release must update the pin it changes).',$c$WITH x AS (SELECT e.signature, e.prosrc_md5, (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(e.signature)) live FROM pdc_ops.expected_function_md5 e)
SELECT count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)=0 AS ok,
 count(*)||' pinned, '||count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)||' changed'||coalesce(': '||string_agg(signature||' '||coalesce(left(live,8),'MISSING'),'; ') FILTER (WHERE live IS DISTINCT FROM prosrc_md5),'') AS detail FROM x$c$,900,'r399');
CREATE FUNCTION pdc_ops.fault_regression_check()
 RETURNS TABLE(check_name text, ok boolean, detail text)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '120s'
AS $function$
DECLARE c record; r record;
BEGIN
 -- Service role, a PDC administrator, or a direct database session (SQL editor / routine). Read-only: STABLE refuses writes.
 IF NOT (coalesce(auth.role(),'')='service_role'
   OR coalesce(public.current_pdc_user_role()::text,'')='administrator'
   OR (session_user IN ('postgres','supabase_admin') AND coalesce(auth.role(),'') NOT IN ('authenticated','anon'))) THEN
  RAISE EXCEPTION 'Administrator or service role required' USING ERRCODE='42501';
 END IF;
 FOR c IN SELECT * FROM pdc_ops.regression_checks rc WHERE rc.enabled ORDER BY rc.sort_order, rc.check_name LOOP
  check_name:=c.check_name;
  BEGIN
   EXECUTE c.check_sql INTO r;
   ok:=coalesce(r.ok,false); detail:=coalesce(r.detail,'');
  EXCEPTION WHEN OTHERS THEN ok:=false; detail:='check failed to run: '||SQLSTATE||' '||SQLERRM;
  END;
  RETURN NEXT;
 END LOOP;
END $function$;
REVOKE ALL ON FUNCTION pdc_ops.fault_regression_check() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION pdc_ops.fault_regression_check() TO authenticated, service_role;
