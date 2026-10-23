-- r512 (F125, Craig 23 Oct): an importer can change hours and approve / add to board on New Vehicles.
-- Staging cdsmnqxtyyoeoznmbidd only. Already applied as r512_importer_new_vehicles_approve version 20261023055815. Do not re-apply. Do not apply to production.
-- Before: New Vehicles write RPCs accept role IN ('operator','administrator') only.
--   public.approve_pdc_new_vehicle_review                         f099baf746f35b500389749ac844bc2f
--   public.approve_pdc_tune_operation_change_with_schedule        c393460c311134c1b7fcdfa02f68b0a7
--   karratha135_pdc.approve_pdc_new_vehicle_review                d4661aa5e0527e92aa1e52d446cd27d3
--   karratha135_pdc.approve_pdc_tune_operation_change_with_schedule 2daae464df647572030a4c5ee5d75828
-- After (one role-list edit, nothing else in the body):
--   public.approve_pdc_new_vehicle_review                         bb8b90544975b50bf9dad84d036473e0
--   public.approve_pdc_tune_operation_change_with_schedule        b23c4aca36597cbee7a0c7a56933c075
--   karratha135_pdc.approve_pdc_new_vehicle_review                0a8b5810af1b1ff60345172bf6ae1165
--   karratha135_pdc.approve_pdc_tune_operation_change_with_schedule d027211f713bf0edb2b993cf2ade86ff
-- approve_pdc_new_vehicle_review_446 has no role list. It calls the base approve, which is the gate, and stays
-- a50e6a6988ae3a106f959e3163b4121c (r459). is_pdc_role stays the r421 ladder. workshop_is_planner_operator stays
-- operator/administrator, so Retry automatic updates and every other planner write stay controller-only.
-- The older public.approve_pdc_tune_operation_change (no schedule) is not this screen's RPC and is not changed.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r512: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r512: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r512: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)
    IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
 THEN RAISE EXCEPTION 'r512: clock tick does not match its pin'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)')
    IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de|r421' THEN RAISE EXCEPTION 'r512: is_pdc_role pin is not r421'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
 THEN RAISE EXCEPTION 'r512: approve_pdc_new_vehicle_review_446 changed'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)')
    IS DISTINCT FROM 'f099baf746f35b500389749ac844bc2f' THEN RAISE EXCEPTION 'r512: base approve pin is not r446'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r512'
    OR signature IN ('public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)',
                     'karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)',
                     'karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)'))
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_new_vehicles_approve_512' OR added_in='r512' OR fault_id='F125' OR sort_order=297)
 THEN RAISE EXCEPTION 'r512: already applied'; END IF;
 PERFORM set_config('pdc.r512_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

DO $a$
DECLARE
  r record;
  src text;
  def text;
  old_tok text := 'role IN(' || chr(39) || 'operator' || chr(39) || ',' || chr(39) || 'administrator' || chr(39) || ')';
  new_tok text := 'role IN(' || chr(39) || 'operator' || chr(39) || ',' || chr(39) || 'importer' || chr(39) || ',' || chr(39) || 'administrator' || chr(39) || ')';
  old_shape text;
  new_shape text;
  n_src integer;
  n_def integer;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','f099baf746f35b500389749ac844bc2f','bb8b90544975b50bf9dad84d036473e0'),
    ('public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','c393460c311134c1b7fcdfa02f68b0a7','b23c4aca36597cbee7a0c7a56933c075'),
    ('karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','d4661aa5e0527e92aa1e52d446cd27d3','0a8b5810af1b1ff60345172bf6ae1165'),
    ('karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','2daae464df647572030a4c5ee5d75828','d027211f713bf0edb2b993cf2ade86ff')
  ) AS v(sig, old_md5, new_md5)
  LOOP
    SELECT p.prosrc,
           coalesce(p.proacl::text,'')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')
      INTO src, old_shape
      FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig);
    IF src IS NULL OR md5(src) IS DISTINCT FROM r.old_md5 THEN RAISE EXCEPTION 'r512: % is not the expected version', r.sig; END IF;
    n_src := (length(src) - length(replace(src, old_tok, ''))) / length(old_tok);
    IF n_src <> 1 OR position(new_tok IN src) > 0 THEN RAISE EXCEPTION 'r512: % role gate is not a single operator/administrator check', r.sig; END IF;
    def := pg_get_functiondef(to_regprocedure(r.sig));
    n_def := (length(def) - length(replace(def, old_tok, ''))) / length(old_tok);
    IF n_def <> 1 THEN RAISE EXCEPTION 'r512: % definition does not contain the role gate once', r.sig; END IF;
    def := replace(def, old_tok, new_tok);
    EXECUTE def;
    SELECT p.prosrc,
           coalesce(p.proacl::text,'')||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')
      INTO src, new_shape
      FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig);
    IF src IS NULL OR md5(src) IS DISTINCT FROM r.new_md5 THEN RAISE EXCEPTION 'r512: % landed as %', r.sig, md5(src); END IF;
    IF new_shape IS DISTINCT FROM old_shape THEN RAISE EXCEPTION 'r512: % owner, grants or settings changed', r.sig; END IF;
    IF (length(src) - length(replace(src, new_tok, ''))) / length(new_tok) <> 1
       OR position(old_tok IN src) > 0 THEN RAISE EXCEPTION 'r512: % role gate did not widen once', r.sig; END IF;
  END LOOP;
END
$a$;

UPDATE pdc_ops.expected_function_md5
   SET prosrc_md5='bb8b90544975b50bf9dad84d036473e0',
       release='r512',
       note='r512 (F125): New Vehicles approval also accepts importer (was f099baf746f35b500389749ac844bc2f r446)',
       updated_at=now()
 WHERE signature='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'
   AND prosrc_md5='f099baf746f35b500389749ac844bc2f';

INSERT INTO pdc_ops.expected_function_md5(signature, prosrc_md5, release, note) VALUES
 ('public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','b23c4aca36597cbee7a0c7a56933c075','r512','r512 (F125): operation-update approval also accepts importer (was c393460c311134c1b7fcdfa02f68b0a7)'),
 ('karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','0a8b5810af1b1ff60345172bf6ae1165','r512','r512 (F125): Karratha New Vehicles approval also accepts importer (was d4661aa5e0527e92aa1e52d446cd27d3)'),
 ('karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','d027211f713bf0edb2b993cf2ade86ff','r512','r512 (F125): Karratha operation-update approval also accepts importer (was 2daae464df647572030a4c5ee5d75828)');

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
 ('importer_new_vehicles_approve_512','F125','New Vehicles approve and hours accept an importer as well as a controller (operator) and an administrator, on the PMG functions and the same Karratha 135 gates. The Dept 138 wrapper has no role list of its own and still calls the base approve. The role ladder, the planner-operator helper and the older tune approval without a schedule are unchanged. A call with no session is refused.',
 $chk$WITH fn AS (
  SELECT * FROM (VALUES
    ('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','bb8b90544975b50bf9dad84d036473e0'),
    ('public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','b23c4aca36597cbee7a0c7a56933c075'),
    ('karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','0a8b5810af1b1ff60345172bf6ae1165'),
    ('karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)','d027211f713bf0edb2b993cf2ade86ff')
  ) v(sig, want)
), bodies AS (
  SELECT v.sig, v.want, md5(p.prosrc) AS got, p.prosrc,
    (length(p.prosrc) - length(replace(p.prosrc, $q$role IN('operator','importer','administrator')$q$, ''))) / length($q$role IN('operator','importer','administrator')$q$) AS widened,
    position($q$role IN('operator','administrator')$q$ IN p.prosrc) AS old_gate
  FROM fn v
  LEFT JOIN pg_proc p ON p.oid=to_regprocedure(v.sig)
), pins AS (
  SELECT (SELECT count(*) FROM fn v JOIN pdc_ops.expected_function_md5 e ON e.signature=v.sig AND e.prosrc_md5=v.want AND e.release='r512') AS n
), wrap AS (
  SELECT md5(p.prosrc) AS got, p.prosrc FROM pg_proc p WHERE p.oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure
), ladder AS (
  SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)' AND release='r421'
), planner AS (
  SELECT md5(p.prosrc) AS got, p.prosrc FROM pg_proc p WHERE p.oid='public.workshop_is_planner_operator()'::regprocedure
), old_tune AS (
  SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid)'::regprocedure
), flags AS (
  SELECT
    (SELECT count(*)=4 AND bool_and(got IS NOT NULL AND got=want AND widened=1 AND old_gate=0) FROM bodies) AS gates,
    (SELECT n=4 FROM pins) AS pinned,
    (SELECT got='a50e6a6988ae3a106f959e3163b4121c' AND position('public.approve_pdc_new_vehicle_review(' IN prosrc)>0 AND position('role IN(' IN prosrc)=0 FROM wrap) AS wrap_ok,
    (SELECT prosrc_md5='39a794b23d1d63117cf549d78acba4de' FROM ladder) AS ladder_ok,
    (SELECT got='a385bd7118aaa8748d137d5535079fa9' AND position($q$in ('operator','administrator')$q$ IN prosrc)>0 AND position('importer' IN prosrc)=0 FROM planner) AS planner_ok,
    (SELECT position($q$role IN('operator','administrator')$q$ IN prosrc)>0 AND position($q$role IN('operator','importer','administrator')$q$ IN prosrc)=0 FROM old_tune) AS old_tune_ok,
    -- CASE evaluates one branch, so an administrator running the daily check does not call the approval functions.
    CASE WHEN auth.uid() IS NOT NULL THEN true
     ELSE (public.approve_pdc_new_vehicle_review(NULL,NULL,'[]'::jsonb,NULL)->>'code')='not_authorized'
      AND (public.approve_pdc_tune_operation_change_with_schedule(NULL,NULL,NULL,NULL,NULL)->>'code')='not_authorized'
      AND (public.approve_pdc_new_vehicle_review_446('00000000-0000-4000-8000-000000000510',repeat('0',64),'[]'::jsonb,'00000000-0000-4000-8000-000000000510')->>'code')='not_authorized'
    END AS no_session
)
SELECT coalesce(gates AND pinned AND wrap_ok AND ladder_ok AND planner_ok AND old_tune_ok AND no_session, false) AS ok,
 format('gates %s pinned %s wrapper %s ladder %s planner %s old tune %s no session %s', gates, pinned, wrap_ok, ladder_ok, planner_ok, old_tune_ok, no_session) AS detail
FROM flags$chk$, true, 297, 'r512');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> current_setting('pdc.r512_pins')::bigint + 3 THEN RAISE EXCEPTION 'r512: pin count did not rise by 3'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r512')<>4 THEN RAISE EXCEPTION 'r512: expected 4 r512 pins'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
 THEN RAISE EXCEPTION 'r512: wrapper changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)
    IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
 THEN RAISE EXCEPTION 'r512: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r512: fault_regression_check changed'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.is_pdc_role(public.pdc_role)')<>'39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r512: is_pdc_role pin moved'; END IF;
 PERFORM set_config('search_path','pg_catalog, public', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='importer_new_vehicles_approve_512') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r512: check failed after apply: %', x.detail; END IF;
END $p$;
