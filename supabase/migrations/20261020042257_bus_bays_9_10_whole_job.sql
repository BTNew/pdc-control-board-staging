-- Dept 138 Bus 4x4: Bay 9 and Bay 10 accept the whole Bus job (mechanical,
-- electrical and accessories categories) so one technician can do it start to
-- finish. Only the booking/validation checks use the new rule; automatic
-- "book all stations" keeps preferred_bay, so its bay choice is unchanged.
-- QA stays Bay 7. Bay 3 HiAce-only (pdc_bus_private.booking_rule) is untouched.
-- Staging cdsmnqxtyyoeoznmbidd only. Undo: 20261020042257_bus_bays_9_10_whole_job.down.sql
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure) IS DISTINCT FROM '9a785c3f4301213c4dae78e3717611ee' THEN RAISE EXCEPTION 'preferred_bay_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure) IS DISTINCT FROM '56b5e232c934e552a288746fb8907981' THEN RAISE EXCEPTION 'capture_scope_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '347efde88281f281b137cd4a551af7db' THEN RAISE EXCEPTION 'validate_booking_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure) IS DISTINCT FROM '55e1810fd2a47a29c9608a55ae292741' THEN RAISE EXCEPTION 'booking_rule_changed'; END IF;
 IF to_regprocedure('pdc_work_categories_private.allowed_bay(text,integer)') IS NOT NULL THEN RAISE EXCEPTION 'allowed_bay_exists'; END IF;
END $g$;

CREATE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $fn$
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (9,10) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES'))
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.allowed_bay(text,integer) FROM PUBLIC;

DO $p$
DECLARE f regprocedure; def text; hits integer;
 old_call constant text:='pdc_work_categories_private.preferred_bay(';
 new_call constant text:='pdc_work_categories_private.allowed_bay(';
BEGIN
 FOREACH f IN ARRAY ARRAY['pdc_work_categories_private.capture_scope()'::regprocedure,
   'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure] LOOP
  def:=pg_get_functiondef(f);
  hits:=(length(def)-length(replace(def,old_call,'')))/length(old_call);
  IF hits IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'expected one preferred_bay call in %, found %',f,hits; END IF;
  EXECUTE replace(def,old_call,new_call);
 END LOOP;
END $p$;

DO $post$ BEGIN
 IF NOT pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',9) OR NOT pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',10)
  OR NOT pdc_work_categories_private.allowed_bay('BUS_ACCESSORIES',9) OR NOT pdc_work_categories_private.allowed_bay('BUS_ELECTRICAL',10)
  OR pdc_work_categories_private.allowed_bay('BUS_QA',9) OR pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',8)
  OR pdc_work_categories_private.allowed_bay('BUS_MECHANICAL',5) THEN RAISE EXCEPTION 'allowed_bay_wrong'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.preferred_bay(text,integer)'::regprocedure) IS DISTINCT FROM '9a785c3f4301213c4dae78e3717611ee' THEN RAISE EXCEPTION 'preferred_bay_changed'; END IF;
 IF position('allowed_bay(' IN (SELECT prosrc FROM pg_proc WHERE oid='pdc_work_categories_private.capture_scope()'::regprocedure))=0
  OR position('allowed_bay(' IN (SELECT prosrc FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure))=0
 THEN RAISE EXCEPTION 'patch_not_applied'; END IF;
END $post$;
