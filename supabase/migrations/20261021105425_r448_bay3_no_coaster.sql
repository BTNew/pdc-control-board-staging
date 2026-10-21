-- r448 (F61, change request: Bhavesh 21 Oct 18:19 AWST "RE: Bays - Dept 138 – Station & Bay Rules", approved by Craig): Bay 3
-- takes any vehicle except a Coaster ("Keep flexibility for any car except coaster in that bay"). A Coaster (model text with
-- "coaster" or the TOYCOA model code) stays warn-and-confirm with a logged override (r417, controllers/admins); Book all stations
-- skips Bay 3 for a Coaster (it only books where booking_rule is ok). A HiAce, a Hilux, any other model and a vehicle with no model
-- are now accepted with no warning. The warning text now says "Bay 3 has a height restriction and does not take a Coaster."
-- Changes pdc_bus_private.booking_rule and pdc_bay_rules_private.mismatches (pins move from r417 to r448). New check
-- bay3_no_coaster_448 (sort 247); bay3_hiace_only (r399) still holds (Coaster refused, HiAce accepted) and stays.
-- No booking, override or vehicle row is written. Not touched: workshop_clock_tick, workshop_validate_booking, bay guide (r447),
-- book_all_vehicle_stations, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r448: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r448: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r448: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'fc9b14ff691b36205c24977ccb07388e' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule is not the r417 version; nothing changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0af8a12ddb42988b169d1fbf07a15d57' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches is not the r417 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417')
      OR (signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417'))<>2 THEN RAISE EXCEPTION 'r448: pins are not the expected r417 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r448')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' OR added_in='r448') THEN RAISE EXCEPTION 'r448: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=247) THEN RAISE EXCEPTION 'r448: sort_order 247 taken'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r447') THEN RAISE EXCEPTION 'r448: r447 is not applied'; END IF;
END $g$;

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
 -- r448 (F61, Bhavesh 21 Oct 18:19): Bay 3 has a height restriction and takes any vehicle except a Coaster (model text with
 -- "coaster" or the TOYCOA model code). A vehicle with no or an unknown model is allowed. A planner-confirmed, logged override
 -- (r417) still lets one Coaster booking use Bay 3; Book all stations skips Bay 3 for a Coaster.
 IF bay=3 AND (model_name~* 'coaster' OR upper(btrim(model_name))='TOYCOA')
  AND NOT pdc_bay_rules_private.override_active(p_booking_id,p_vehicle_id,p_bay_id,'bus_bay_vehicle_incompatible') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'refused_model','Coaster'); END IF;
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
   -- r448 (F61): Bay 3 takes any vehicle except a Coaster.
   'message',format('Bay %s has a height restriction and does not take a Coaster.',n)));
 END IF;
 RETURN out;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='72e436aa18baad933dbc38d50933eaa6',release='r448',note='r448: Bay 3 takes any vehicle except a Coaster (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bus_private.booking_rule(uuid,uuid,uuid)' AND prosrc_md5='fc9b14ff691b36205c24977ccb07388e' AND release='r417';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0f21e96fe19b3736235088a133a8ad52',release='r448',note='r448: Bay 3 Coaster warning text (F61)',updated_at=clock_timestamp()
 WHERE signature='pdc_bay_rules_private.mismatches(uuid,text,uuid)' AND prosrc_md5='0af8a12ddb42988b169d1fbf07a15d57' AND release='r417';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('bay3_no_coaster_448','F61','Bus Bay 3 (r448) takes any vehicle except a Coaster: a Coaster by model text or TOYCOA code is refused (warn-and-confirm), a HiAce and another model are accepted, the warning names the Coaster, both functions pinned',
  $chk$WITH bay AS (SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=3),
v AS (SELECT v.id,concat_ws(' ',v.model,v.vehicle_description) m FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND pdc_bus_private.active_vehicle(v.id)),
pick AS (
 SELECT (SELECT id FROM v WHERE m~*'coaster' ORDER BY id LIMIT 1) coaster_text,
  (SELECT id FROM v WHERE upper(btrim(m))='TOYCOA' ORDER BY id LIMIT 1) coaster_code,
  (SELECT id FROM v WHERE (m~*'hi[[:space:]-]?ace' OR upper(btrim(m))='TOYHIA') AND m!~*'coaster' ORDER BY id LIMIT 1) hiace,
  (SELECT id FROM v WHERE m!~*'coaster' AND m!~*'hi[[:space:]-]?ace' AND upper(btrim(m)) NOT IN ('TOYHIA','TOYCOA') ORDER BY id LIMIT 1) other),
r AS (
 SELECT (SELECT pdc_bus_private.booking_rule(p.coaster_text,bay.id,NULL)->>'error' FROM bay) ct,
  (SELECT pdc_bus_private.booking_rule(p.coaster_code,bay.id,NULL)->>'error' FROM bay) cc,
  (SELECT pdc_bus_private.booking_rule(p.hiace,bay.id,NULL)->>'ok' FROM bay) hi,
  (SELECT pdc_bus_private.booking_rule(p.other,bay.id,NULL)->>'ok' FROM bay) ot,
  (SELECT pdc_bay_rules_private.mismatches(coalesce(p.coaster_text,p.coaster_code),NULL,bay.id)->0->>'message' FROM bay) msg,
  p.* FROM pick p),
pins AS (
 SELECT count(*) FILTER (WHERE md5(pr.prosrc)=e.prosrc_md5) n FROM pdc_ops.expected_function_md5 e
 JOIN pg_proc pr ON pr.oid=to_regprocedure(e.signature) WHERE e.release='r448')
SELECT (coaster_text IS NULL OR ct='bus_bay_vehicle_incompatible') AND (coaster_code IS NULL OR cc='bus_bay_vehicle_incompatible')
  AND (hiace IS NULL OR hi='true') AND (other IS NULL OR ot='true')
  AND (coalesce(coaster_text,coaster_code) IS NULL OR msg ~ 'does not take a Coaster')
  AND (SELECT n FROM pins)=2 AS ok,
 'Bay 3 (r448): Coaster by model text: '||coalesce(ct,CASE WHEN coaster_text IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; Coaster by TOYCOA code: '||coalesce(cc,CASE WHEN coaster_code IS NULL THEN 'no active one to test' ELSE 'ALLOWED' END)
 ||'; HiAce ok: '||coalesce(hi,'no active HiAce to test')||'; other vehicle ok: '||coalesce(ot,'no other active vehicle to test')
 ||'; warning: '||coalesce(msg,'-')||'; r448 pins matching: '||(SELECT n FROM pins)||'/2' AS detail
FROM r$chk$,true,247,'r448');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'72e436aa18baad933dbc38d50933eaa6' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: booking_rule did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'0f21e96fe19b3736235088a133a8ad52' OR (SELECT coalesce(p.proacl::text,'NULL')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'') FROM pg_proc p WHERE p.oid='pdc_bay_rules_private.mismatches(uuid,text,uuid)'::regprocedure)<>'{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r448: mismatches did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r448')<>2 THEN RAISE EXCEPTION 'r448: pins not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448' AND added_in='r448')<>'bb01c45979e533e206ea8ad024877063' THEN RAISE EXCEPTION 'r448: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_no_coaster_448') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_no_coaster_448 not OK: %',x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='bay3_hiace_only') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r448: check bay3_hiace_only not OK: %',x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r448: clock tick changed'; END IF;
END $g$;
