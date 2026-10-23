-- r512 undo (F125): put the four New Vehicles approval role gates back to operator/administrator,
-- restore the r446 pin on the base approve, and drop the three r512 pins and the check.
-- Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45. Revert the frontend separately.
-- Restored md5s:
--   public.approve_pdc_new_vehicle_review                         f099baf746f35b500389749ac844bc2f
--   public.approve_pdc_tune_operation_change_with_schedule        c393460c311134c1b7fcdfa02f68b0a7
--   karratha135_pdc.approve_pdc_new_vehicle_review                d4661aa5e0527e92aa1e52d446cd27d3
--   karratha135_pdc.approve_pdc_tune_operation_change_with_schedule 2daae464df647572030a4c5ee5d75828
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r512 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r512 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r512 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)
    IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
 THEN RAISE EXCEPTION 'r512 undo: clock tick does not match its pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
 THEN RAISE EXCEPTION 'r512 undo: wrapper changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r512')<>4
    OR (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='importer_new_vehicles_approve_512' AND added_in='r512' AND sort_order=297 AND fault_id='F125')<>1
 THEN RAISE EXCEPTION 'r512 undo: r512 pins or check not found'; END IF;
END $g$;

DO $a$
DECLARE
  r record;
  src text;
  def text;
  old_tok text := 'role IN(' || chr(39) || 'operator' || chr(39) || ',' || chr(39) || 'importer' || chr(39) || ',' || chr(39) || 'administrator' || chr(39) || ')';
  new_tok text := 'role IN(' || chr(39) || 'operator' || chr(39) || ',' || chr(39) || 'administrator' || chr(39) || ')';
  old_shape text;
  new_shape text;
  n_src integer;
  n_def integer;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','bb8b90544975b50bf9dad84d036473e0','f099baf746f35b500389749ac844bc2f'),
    ('public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','b23c4aca36597cbee7a0c7a56933c075','c393460c311134c1b7fcdfa02f68b0a7'),
    ('karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','0a8b5810af1b1ff60345172bf6ae1165','d4661aa5e0527e92aa1e52d446cd27d3'),
    ('karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','d027211f713bf0edb2b993cf2ade86ff','2daae464df647572030a4c5ee5d75828')
  ) AS v(sig, old_md5, new_md5)
  LOOP
    SELECT p.prosrc,
           coalesce(p.proacl::text,'')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')
      INTO src, old_shape
      FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig);
    IF src IS NULL OR md5(src) IS DISTINCT FROM r.old_md5 THEN RAISE EXCEPTION 'r512 undo: % is not the r512 version', r.sig; END IF;
    n_src := (length(src) - length(replace(src, old_tok, ''))) / length(old_tok);
    IF n_src <> 1 THEN RAISE EXCEPTION 'r512 undo: % role gate is not the r512 importer list', r.sig; END IF;
    def := pg_get_functiondef(to_regprocedure(r.sig));
    n_def := (length(def) - length(replace(def, old_tok, ''))) / length(old_tok);
    IF n_def <> 1 THEN RAISE EXCEPTION 'r512 undo: % definition does not contain the r512 role gate once', r.sig; END IF;
    def := replace(def, old_tok, new_tok);
    EXECUTE def;
    SELECT p.prosrc,
           coalesce(p.proacl::text,'')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')
      INTO src, new_shape
      FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig);
    IF src IS NULL OR md5(src) IS DISTINCT FROM r.new_md5 THEN RAISE EXCEPTION 'r512 undo: % landed as %', r.sig, md5(src); END IF;
    IF new_shape IS DISTINCT FROM old_shape THEN RAISE EXCEPTION 'r512 undo: % owner, grants or settings changed', r.sig; END IF;
  END LOOP;
END
$a$;

UPDATE pdc_ops.expected_function_md5
   SET prosrc_md5='f099baf746f35b500389749ac844bc2f',
       release='r446',
       note='r446 (F59): unchanged dependency of approve_pdc_new_vehicle_review_446',
       updated_at=now()
 WHERE signature='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'
   AND prosrc_md5='bb8b90544975b50bf9dad84d036473e0'
   AND release='r512';

DELETE FROM pdc_ops.expected_function_md5
 WHERE release='r512'
   AND signature IN (
     'public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)',
     'karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)',
     'karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)'
   )
   AND prosrc_md5 IN (
     'b23c4aca36597cbee7a0c7a56933c075',
     '0a8b5810af1b1ff60345172bf6ae1165',
     'd027211f713bf0edb2b993cf2ade86ff'
   );

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='importer_new_vehicles_approve_512'
   AND added_in='r512'
   AND fault_id='F125'
   AND sort_order=297;

DO $p$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r512') THEN RAISE EXCEPTION 'r512 undo: an r512 pin remains'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_new_vehicles_approve_512') THEN RAISE EXCEPTION 'r512 undo: check remains'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)')
    IS DISTINCT FROM 'f099baf746f35b500389749ac844bc2f|r446' THEN RAISE EXCEPTION 'r512 undo: base approve pin was not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)'::regprocedure)<>'c393460c311134c1b7fcdfa02f68b0a7'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'d4661aa5e0527e92aa1e52d446cd27d3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)'::regprocedure)<>'2daae464df647572030a4c5ee5d75828'
 THEN RAISE EXCEPTION 'r512 undo: a function md5 was not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
 THEN RAISE EXCEPTION 'r512 undo: wrapper changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)
    IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
 THEN RAISE EXCEPTION 'r512 undo: clock tick changed'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)')<>'39a794b23d1d63117cf549d78acba4de'
 THEN RAISE EXCEPTION 'r512 undo: is_pdc_role pin moved'; END IF;
END $p$;
