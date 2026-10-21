-- r455 (F68) rolled-back test A: Workshop detail and booking search per role for every active/RFT board vehicle, importer write and AI auditor refusals,
-- before and after the release (dealer sent as the board sends it). Accounts and vehicles picked by rule at run time.
-- Reads only; everything is rolled back (R455_RB_A).
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R455 with the release tag (e.g. R405).
--
-- Why: board write functions take the top-level change lock
-- (pg_advisory_xact_lock('pdc:workshop:top-level-mutation')) and keep it until the test's
-- ROLLBACK. The live clock tick runs every minute at :00 and waits only 3 s for that lock
-- (lock_timeout), so a test that holds it across a minute boundary makes the real tick fail
-- (21:25, 21:28 and 21:30 AWST on 20 Oct 2026, r404 tests).
--
-- Rule: 1) wait until this minute's tick has finished, 2) start between :02 and :15,
-- 3) never wait long for a live lock (lock_timeout 2 s), 4) stop and roll back before :50
-- (each statement's statement_timeout is cut to the time left; call pg_temp.deadline() before
-- each step). Locks are only taken after step 1, so waiting holds nothing.

-- 1+2. Wait for the tick (holds no locks; reads cron history only).
DO $window_wait$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp())
                    AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'R455_WINDOW: clock tick not seen; test not started'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window_wait$;
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='170s';
CREATE TEMP TABLE t_res(k text, v jsonb) ON COMMIT DROP;
CREATE TEMP TABLE t_acct(role_key text, uid uuid, em text) ON COMMIT DROP;
INSERT INTO t_acct SELECT 'admin_scoped', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='administrator' AND EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=r.auth_user_id AND s.active AND s.environment='staging' AND s.dealer_code='14450')
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
INSERT INTO t_acct SELECT 'admin_unscoped', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='administrator' AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=r.auth_user_id OR s.normalized_email=lower(r.email))
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
INSERT INTO t_acct SELECT 'operator', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='operator' AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=r.auth_user_id OR s.normalized_email=lower(r.email))
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
INSERT INTO t_acct SELECT 'importer', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='importer' AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=r.auth_user_id OR s.normalized_email=lower(r.email))
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
INSERT INTO t_acct SELECT 'salesperson', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='salesperson'
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
INSERT INTO t_acct SELECT 'fitter', r.auth_user_id, lower(r.email) FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND lower(u.email)=lower(r.email) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND r.role::text='fitter'
 ORDER BY r.created_at, r.auth_user_id LIMIT 1;
GRANT SELECT,INSERT ON t_res TO authenticated; GRANT SELECT ON t_acct TO authenticated;

CREATE TEMP TABLE t_board_src(s jsonb) ON COMMIT DROP; GRANT SELECT,INSERT ON t_board_src TO authenticated;
DO $u$ DECLARE a record;  BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='admin_unscoped';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('admin_unscoped:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 INSERT INTO t_board_src SELECT public.get_pdc_email_vehicle_location_snapshot();
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
CREATE TEMP TABLE t_board ON COMMIT DROP AS SELECT DISTINCT (x->>'id')::uuid id, x->>'identity_dealer_code' idc FROM t_board_src, jsonb_array_elements(s#>'{data,vehicles}') x;
GRANT SELECT ON t_board TO authenticated;

CREATE TEMP TABLE t_bd(id uuid, d text, st text) ON COMMIT DROP; GRANT SELECT ON t_bd TO authenticated;
CREATE TEMP TABLE t_detail(phase text, rk text, id uuid, ok boolean, code text) ON COMMIT DROP; GRANT INSERT,SELECT ON t_detail TO authenticated;
CREATE TEMP TABLE t_search(phase text, rk text, id uuid, ok boolean, code text) ON COMMIT DROP; GRANT INSERT,SELECT ON t_search TO authenticated;
DELETE FROM t_bd; INSERT INTO t_bd SELECT b.id, coalesce(public.pdc_auditor_vehicle_dealer(b.id), b.idc, '14450'), v.lifecycle_state::text
 FROM t_board b JOIN public.vehicles v ON v.id=b.id WHERE v.lifecycle_state IN ('active','rft');
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='admin_scoped';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('admin_scoped:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('before','admin_scoped',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('before','admin_scoped',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'before','admin_scoped',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'before','admin_scoped',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='operator';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('operator:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('before','operator',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('before','operator',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'before','operator',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'before','operator',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='importer';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('importer:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('before','importer',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('before','importer',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'before','importer',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'before','importer',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='salesperson';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('salesperson:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('before','salesperson',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('before','salesperson',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'before','salesperson',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'before','salesperson',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='fitter';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('fitter:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('before','fitter',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('before','fitter',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'before','fitter',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'before','fitter',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
-- r455 (F68, Craig 22 Oct, decision 3): importers can open a vehicle's drop-down read-only. Before, the Workshop detail and
-- booking search read scope (workshop_read_actor_scope_20261013) had no rule for the importer role: an importer without a
-- dealer-scope row fell through to pdc_auditor_actor_scope(), which allows viewer/operator/administrator only, and the
-- drop-down failed (pdc_auditor_unauthorized).
-- Fix: workshop_importer_read_scope_455 gives an approved, active importer with no dealer-scope row the shared board's
-- dealer 14450 as a VIEWER scope (actor_role importer, read_only true). Only get_vehicle_workshop_detail_scoped and
-- get_workshop_booking_search_scoped use workshop_read_actor_scope_20261013 (the check proves it). pdc_auditor_actor_scope()
-- and every write function are unchanged, so an importer gains no write right. New check importer_read_scope_455 (sort 254).
-- Not touched: workshop_clock_tick, any data row, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r455: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r455: staging only'; END IF;
 PERFORM set_config('pdc.r455_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r455_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r455_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r455: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r455') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' OR added_in='r455') THEN RAISE EXCEPTION 'r455: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=254) THEN RAISE EXCEPTION 'r455: sort_order 254 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()') IS NOT NULL THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()') IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d|r423' THEN RAISE EXCEPTION 'r455: pin of pdc_codex_intake_private.workshop_read_actor_scope_20261013() not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_auditor_actor_scope()'::regprocedure) IS DISTINCT FROM '79ddabb0a8fef13fad26e82151fcbc44' THEN RAISE EXCEPTION 'r455: pdc_auditor_actor_scope changed'; END IF;
 PERFORM set_config('pdc.r455_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 -- r455 (F68): read scope for an approved, active importer who has NO dealer-scope row (active or not): the shared board's
 -- dealer 14450, as a viewer, so the importer can open a vehicle's drop-down read-only. Only the two Workshop read functions
 -- (get_vehicle_workshop_detail_scoped, get_workshop_booking_search_scoped) use this scope; every write function keeps its own
 -- role check, so an importer gains no write. The AI Auditor still uses pdc_auditor_actor_scope() only.
 SELECT CASE WHEN count(*)=1 THEN jsonb_build_object(
   'user_id',auth.uid(),'email',lower(btrim(coalesce(auth.jwt()->>'email',''))),'role','viewer','actor_role','importer',
   'dealer_code','14450','environment','staging','scope_source','importer_read_455','read_only',true) ELSE NULL END
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE public.pdc_monitor_staging_guard()
   AND auth.uid() IS NOT NULL AND u.id=auth.uid()
   AND lower(coalesce(u.email,''))=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND lower(r.email)=lower(coalesce(u.email,''))
   AND r.active AND r.account_status='approved' AND r.role::text='importer'
   AND (u.banned_until IS NULL OR u.banned_until<=now())
   AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s
     WHERE s.auth_user_id=auth.uid() OR s.normalized_email=lower(coalesce(u.email,'')))
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE s jsonb; BEGIN
 s:=public.pdc_workshop_controller_scope_423();
 IF s IS NOT NULL THEN RETURN s; END IF;
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 -- r455 (F68): an approved importer with no dealer-scope row reads the shared board's dealer 14450, read only.
 s:=pdc_codex_intake_private.workshop_importer_read_scope_455();
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f7dedb862bdc1d85afd7d2392141c946',release='r455',note='r455: importer read scope after controller and delegated (F68); r423 controller scope first',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.workshop_importer_read_scope_455()','93ac42208534e22089c70e025db9cf84','r455','r455: importer read-only scope (board dealer 14450, viewer) (F68)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('importer_read_scope_455','F68','Importers open vehicle drop-downs read-only; the importer read scope reaches only the two Workshop read functions (r455)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r455'),
scope_users AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)'),
     pg_catalog.to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)'))) other
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname<>'karratha135_pdc' AND strpos(p.prosrc,'workshop_read_actor_scope_20261013(')>0),
importer_users AS (
  SELECT count(*) FILTER (WHERE p.oid<>pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'workshop_importer_read_scope_455(')>0),
auditor AS (
  SELECT strpos(p.prosrc,'r.role::text in (''viewer'',''operator'',''administrator'')')>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_auditor_actor_scope()'))
SELECT (SELECT n FROM pins)=2 AND (SELECT ok FROM pins)=2 AND (SELECT other FROM scope_users)=0 AND (SELECT other FROM importer_users)=0
  AND coalesce((SELECT ok FROM auditor),false) AS ok,
 'Importer read scope (r455): r455 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; other functions using the Workshop read scope: '||(SELECT other FROM scope_users)||' (must be 0: read paths only)'
 ||'; other functions using the importer scope: '||(SELECT other FROM importer_users)
 ||'; AI Auditor scope still viewer/operator/administrator only: '||CASE WHEN coalesce((SELECT ok FROM auditor),false) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,254,'r455');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM 'f7dedb862bdc1d85afd7d2392141c946' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '93ac42208534e22089c70e025db9cf84' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r455')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r455_pins')::int+1 THEN RAISE EXCEPTION 'r455: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' AND added_in='r455' AND sort_order=254) IS DISTINCT FROM 'fc188cad04093d1c7f4172e80bc4421f' THEN RAISE EXCEPTION 'r455: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('importer_read_scope_455') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r455: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_tick') THEN RAISE EXCEPTION 'r455: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_frc') THEN RAISE EXCEPTION 'r455: fault_regression_check changed'; END IF;
END $g$;

DELETE FROM t_board_src; DROP TABLE t_board;
DO $u$ DECLARE a record;  BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='admin_unscoped';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('admin_unscoped:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 INSERT INTO t_board_src SELECT public.get_pdc_email_vehicle_location_snapshot();
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
CREATE TEMP TABLE t_board ON COMMIT DROP AS SELECT DISTINCT (x->>'id')::uuid id, x->>'identity_dealer_code' idc FROM t_board_src, jsonb_array_elements(s#>'{data,vehicles}') x;
GRANT SELECT ON t_board TO authenticated;

DELETE FROM t_bd; INSERT INTO t_bd SELECT b.id, coalesce(public.pdc_auditor_vehicle_dealer(b.id), b.idc, '14450'), v.lifecycle_state::text
 FROM t_board b JOIN public.vehicles v ON v.id=b.id WHERE v.lifecycle_state IN ('active','rft');
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='admin_scoped';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('admin_scoped:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('after','admin_scoped',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('after','admin_scoped',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'after','admin_scoped',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'after','admin_scoped',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='operator';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('operator:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('after','operator',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('after','operator',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'after','operator',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'after','operator',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='importer';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('importer:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('after','importer',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('after','importer',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'after','importer',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'after','importer',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='salesperson';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('salesperson:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('after','salesperson',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('after','salesperson',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'after','salesperson',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'after','salesperson',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; g record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='fitter';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('fitter:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR r IN SELECT * FROM t_bd LOOP
  BEGIN res:=public.get_vehicle_workshop_detail_scoped(r.id,r.d);
   INSERT INTO t_detail VALUES ('after','fitter',r.id,coalesce(res->>'ok','true')<>'false' AND res ? 'vehicle_id',coalesce(res->>'code','ok'));
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_detail VALUES ('after','fitter',r.id,false,'raised:'||SQLERRM); END;
 END LOOP;
 FOR g IN SELECT jsonb_agg(jsonb_build_object('vehicle_id',id::text,'dealer_code',d)) j FROM (SELECT id,d,(row_number() OVER (ORDER BY id)-1)/25 grp FROM t_bd) z GROUP BY grp LOOP
  BEGIN res:=public.get_workshop_booking_search_scoped(g.j);
   INSERT INTO t_search SELECT 'after','fitter',(x->>'vehicle_id')::uuid,(x->>'ok')::boolean,coalesce(x->>'error','ok') FROM jsonb_array_elements(res->'results') x;
  EXCEPTION WHEN OTHERS THEN INSERT INTO t_search SELECT 'after','fitter',(y->>'vehicle_id')::uuid,false,'raised:'||SQLERRM FROM jsonb_array_elements(g.j) y; END;
 END LOOP;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
INSERT INTO t_res SELECT 'detail:'||phase||':'||rk, jsonb_build_object('ok',count(*) FILTER (WHERE ok),'n',count(*),
  'codes',(SELECT jsonb_object_agg(c,n) FROM (SELECT left(code,60) c,count(*) n FROM t_detail d2 WHERE d2.phase=d.phase AND d2.rk=d.rk AND NOT d2.ok GROUP BY 1) z)) FROM t_detail d GROUP BY phase,rk;
INSERT INTO t_res SELECT 'search:'||phase||':'||rk, jsonb_build_object('ok',count(*) FILTER (WHERE ok),'n',count(*),
  'codes',(SELECT jsonb_object_agg(c,n) FROM (SELECT left(code,60) c,count(*) n FROM t_search d2 WHERE d2.phase=d.phase AND d2.rk=d.rk AND NOT d2.ok GROUP BY 1) z)) FROM t_search d GROUP BY phase,rk;
INSERT INTO t_res SELECT 'newly_open:'||a.rk, jsonb_build_object('n',count(*),'kinds',jsonb_agg(DISTINCT v.source_system||'/'||v.lifecycle_state::text||'/'||coalesce(b.idc,'no-idc')))
 FROM t_detail a JOIN t_detail b0 ON b0.phase='before' AND b0.rk=a.rk AND b0.id=a.id AND NOT b0.ok JOIN public.vehicles v ON v.id=a.id JOIN t_board b ON b.id=a.id
 WHERE a.phase='after' AND a.ok GROUP BY a.rk;
INSERT INTO t_res SELECT 'newly_closed:'||a.rk, to_jsonb(count(*)) FROM t_detail a JOIN t_detail b0 ON b0.phase='before' AND b0.rk=a.rk AND b0.id=a.id AND b0.ok WHERE a.phase='after' AND NOT a.ok GROUP BY a.rk;
INSERT INTO t_res SELECT 'still_closed_after:'||a.rk, jsonb_agg(DISTINCT left(a.code,40)||' '||v.source_system||'/'||v.lifecycle_state::text) FROM t_detail a JOIN public.vehicles v ON v.id=a.id WHERE a.phase='after' AND NOT a.ok GROUP BY a.rk;
INSERT INTO t_res SELECT 'identity_dealer_rows', jsonb_build_object('n',count(*) FILTER (WHERE idc IS NOT NULL),'states',(SELECT jsonb_agg(DISTINCT v.lifecycle_state::text||'/'||b2.idc) FROM t_board b2 JOIN public.vehicles v ON v.id=b2.id WHERE b2.idc IS NOT NULL)) FROM t_board;
INSERT INTO t_res SELECT 'check', (SELECT to_jsonb(c) FROM pdc_ops.fault_regression_check() c WHERE c.check_name='importer_read_scope_455');
DO $u$ DECLARE a record; r record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='importer';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('importer:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT id INTO r FROM t_bd ORDER BY id LIMIT 1;
 BEGIN res:=public.set_vehicle_work_category(r.id,-1,'BUS_MECHANICAL','r455 probe (version -1: never applies)',-1);
  INSERT INTO t_res VALUES ('write_after:importer', jsonb_build_object('refused',false,'res',res));
 EXCEPTION WHEN OTHERS THEN INSERT INTO t_res VALUES ('write_after:importer', jsonb_build_object('refused',true,'err',left(SQLERRM,80))); END;
 BEGIN res:=to_jsonb(public.get_pdc_auditor_review_queue(1));
  INSERT INTO t_res VALUES ('auditor_after:importer', jsonb_build_object('refused',coalesce(res->>'ok','true')='false','code',res->>'code'));
 EXCEPTION WHEN OTHERS THEN INSERT INTO t_res VALUES ('auditor_after:importer', jsonb_build_object('refused',true,'err',left(SQLERRM,80))); END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $u$ DECLARE a record; r record; res jsonb; BEGIN
 SELECT * INTO a FROM t_acct WHERE role_key='salesperson';
 IF a.uid IS NULL THEN INSERT INTO t_res VALUES ('salesperson:missing','true'); RETURN; END IF;
 PERFORM set_config('request.jwt.claims', json_build_object('sub',a.uid,'role','authenticated','email',a.em,'aud','authenticated')::text, true);
 PERFORM set_config('request.jwt.claim.sub', a.uid::text, true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT id INTO r FROM t_bd ORDER BY id LIMIT 1;
 BEGIN res:=public.set_vehicle_work_category(r.id,-1,'BUS_MECHANICAL','r455 probe (version -1: never applies)',-1);
  INSERT INTO t_res VALUES ('write_after:salesperson', jsonb_build_object('refused',false,'res',res));
 EXCEPTION WHEN OTHERS THEN INSERT INTO t_res VALUES ('write_after:salesperson', jsonb_build_object('refused',true,'err',left(SQLERRM,80))); END;
 BEGIN res:=to_jsonb(public.get_pdc_auditor_review_queue(1));
  INSERT INTO t_res VALUES ('auditor_after:salesperson', jsonb_build_object('refused',coalesce(res->>'ok','true')='false','code',res->>'code'));
 EXCEPTION WHEN OTHERS THEN INSERT INTO t_res VALUES ('auditor_after:salesperson', jsonb_build_object('refused',true,'err',left(SQLERRM,80))); END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claims', '', true); PERFORM set_config('request.jwt.claim.sub', '', true);
END $u$;
DO $f$ BEGIN RAISE EXCEPTION 'R455_RB_A %', (SELECT jsonb_object_agg(k,v) FROM t_res); END $f$;