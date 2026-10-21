-- r448 undo (F61): restores pdc_bus_private.booking_rule (md5 fc9b14ff691b36205c24977ccb07388e) and pdc_bay_rules_private.mismatches (md5 0af8a12ddb42988b169d1fbf07a15d57) byte for
-- byte (r417: Bay 3 HiAce only), puts their r417 pins back and drops bay3_no_coaster_448. Bookings placed in Bay 3 while r448 was
-- live that the HiAce-only rule would warn about (e.g. a Hilux) are kept where they are with an 'applied' override row tagged
-- 'r448_undo_kept', so the validator and the clock tick keep accepting them. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r448 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r448 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r448 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'72e436aa18baad933dbc38d50933eaa6' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: booking_rule is not the r448 version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0f21e96fe19b3736235088a133a8ad52' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: mismatches is not the r448 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r448')<>2 THEN RAISE EXCEPTION 'r448 undo: r448 pins not found'; END IF;
END $g$;

DROP TABLE IF EXISTS pg_temp.r448_new_ok;
CREATE TEMP TABLE r448_new_ok ON COMMIT DROP AS
SELECT b.id booking_id,b.vehicle_id,b.bay_id,bay.bay_number,b.work_category
FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.workshop_stages s ON s.id=bay.stage_id AND s.code='BUS_4X4'
WHERE bay.bay_number=3 AND b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')
 AND coalesce((pdc_bus_private.booking_rule(b.vehicle_id,b.bay_id,NULL)->>'ok')::boolean,false);

CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 -- r417 (F32): a planner-confirmed, logged override lets this one booking use Bay 3; the rule itself is unchanged.
 IF bay=3 AND (model_name~* 'coaster' OR (model_name!~* 'hi[[:space:]-]?ace' AND upper(btrim(model_name))<>'TOYHIA'))
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$;

CREATE OR REPLACE FUNCTION pdc_bay_rules_private.mismatches(p_vehicle_id uuid, p_category text, p_bay_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
-- r417 (F32): which bay rules this vehicle/category would break in this bay. The rules themselves are unchanged
-- (pdc_work_categories_private.allowed_bay and pdc_bus_private.booking_rule); this only explains them.
DECLARE n integer; code text; out jsonb:='[]'::jsonb; rule jsonb; bay_for text;
BEGIN
 SELECT b.bay_number,s.code INTO n,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF n IS NULL OR code IS DISTINCT FROM 'BUS_4X4' THEN RETURN out; END IF;
 IF p_category IS NOT NULL AND NOT pdc_work_categories_private.allowed_bay(p_category,n) THEN
  SELECT string_agg(pdc_bay_rules_private.category_label(c),' and ' ORDER BY o) INTO bay_for
  FROM (VALUES('BUS_MECHANICAL',1),('BUS_ELECTRICAL',2),('BUS_ACCESSORIES',3),('BUS_QA',4)) x(c,o) WHERE pdc_work_categories_private.preferred_bay(c,n);
  out:=out||jsonb_build_array(jsonb_build_object('rule','category_bay_mismatch','bay_number',n,'work_category',p_category,
   'message',format('Bay %s is set up for %s work, and this booking is %s work.',n,coalesce(bay_for,'other'),pdc_bay_rules_private.category_label(p_category))));
 END IF;
 rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,NULL);
 IF rule->>'error'='bus_bay_vehicle_incompatible' THEN
  out:=out||jsonb_build_array(jsonb_build_object('rule','bus_bay_vehicle_incompatible','bay_number',n,
   'message',format('Bay %s is for %s vehicles only, and this vehicle is not a %s.',n,coalesce(rule->>'required_model','HiAce'),coalesce(rule->>'required_model','HiAce'))));
 END IF;
 RETURN out;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='fc9b14ff691b36205c24977ccb07388e',release='r417',note='F32: bay rule mismatch warns; confirmed overrides are logged',updated_at='2026-10-20 23:36:17.059572+00'
 WHERE signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='72e436aa18baad933dbc38d50933eaa6' AND release='r448';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57',release='r417',note='F32: bay rule mismatch warns; confirmed overrides are logged',updated_at='2026-10-20 23:36:17.059572+00'
 WHERE signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0f21e96fe19b3736235088a133a8ad52' AND release='r448';

INSERT INTO pdc_bay_rules_private.overrides(actor_id,actor_email,vehicle_id,booking_id,bay_id,bay_number,stage_code,work_category,rule,message,action,source,outcome,finished_at)
SELECT '00000000-0000-0000-0000-000000000000'::uuid,'r448 undo (no person)',o.vehicle_id,o.booking_id,o.bay_id,3,'BUS_4X4',o.work_category,'bus_bay_vehicle_incompatible',
 'Booked in Bay 3 while r448 let any vehicle except a Coaster use it. Kept where it was placed.','move','r448_undo_kept','applied',clock_timestamp()
FROM r448_new_ok o
WHERE pdc_bus_private.booking_rule(o.vehicle_id,o.bay_id,NULL)->>'error'='bus_bay_vehicle_incompatible'
 AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides x WHERE x.booking_id=o.booking_id AND x.bay_id=o.bay_id
  AND x.rule='bus_bay_vehicle_incompatible' AND x.outcome='applied' AND x.revoked_at IS NULL);

DELETE FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' AND added_in='r448';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'fc9b14ff691b36205c24977ccb07388e' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: booking_rule not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0af8a12ddb42988b169d1fbf07a15d57' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448 undo: mismatches not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448') OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature IN ('pdc_bus_private.booking_rule(uuid,uuid,uuid)','pdc_bay_rules_private.mismatches(uuid,text,uuid)') AND release='r417')<>2 THEN RAISE EXCEPTION 'r448 undo: pins not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r448') THEN RAISE EXCEPTION 'r448 undo: check not removed'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
   WHERE b.deleted_at IS NULL AND b.status IN('planned','started','stoppage') AND bay.bay_number=3
    AND pdc_bus_private.booking_rule(b.vehicle_id,b.bay_id,NULL)->>'error'='bus_bay_vehicle_incompatible'
    AND NOT EXISTS(SELECT 1 FROM pdc_bay_rules_private.overrides o WHERE o.booking_id=b.id AND o.bay_id=b.bay_id AND o.rule='bus_bay_vehicle_incompatible' AND o.outcome='applied' AND o.revoked_at IS NULL))
 THEN RAISE EXCEPTION 'r448 undo: a Bay 3 booking would break the HiAce rule without an override'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448 undo: clock tick changed'; END IF;
END $g$;
