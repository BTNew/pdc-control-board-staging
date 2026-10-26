-- Synthetic-only local integration fixture. No customer backup. Entire test rolls back.
\set ON_ERROR_STOP on
BEGIN;
DO $local$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_database()<>'pdc_synthetic_helper_access'
 OR to_regclass('public.vehicles') IS NOT NULL OR to_regclass('public._r551_file') IS NOT NULL THEN RAISE EXCEPTION 'requires owned empty loopback database'; END IF;
 CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;
END $local$;
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean,project_ref text);
INSERT INTO public.pdc_staging_environment_sentinel VALUES(true,'cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
CREATE TABLE public._r551_file(n integer PRIMARY KEY,b64 text NOT NULL);
CREATE TABLE public._r551_stmt(n integer PRIMARY KEY,b64 text NOT NULL);
INSERT INTO public._r551_file VALUES(1,'synthetic-file-1'),(2,'synthetic-file-2');
INSERT INTO public._r551_stmt VALUES(1,'synthetic-stmt-1'),(2,'synthetic-stmt-2');
GRANT ALL PRIVILEGES ON public._r551_file,public._r551_stmt TO anon,authenticated,service_role;
CREATE TEMP TABLE baseline AS
SELECT c.oid,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
CASE c.relname WHEN '_r551_file' THEN (SELECT jsonb_agg(to_jsonb(t) ORDER BY n) FROM public._r551_file t)
ELSE (SELECT jsonb_agg(to_jsonb(t) ORDER BY n) FROM public._r551_stmt t) END AS rows
FROM pg_class c WHERE c.oid IN ('public._r551_file'::regclass,'public._r551_stmt'::regclass);
CREATE FUNCTION pg_temp.assert_true(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END$$;
-- Underscores are literal: this unrelated near-match must not count as a dependency.
CREATE FUNCTION public.synthetic_unrelated_token() RETURNS text LANGUAGE sql AS $$SELECT '_r551Xfile'::text$$;
SAVEPOINT dependency_guard;
CREATE VIEW public.synthetic_helper_dependency AS SELECT n FROM public._r551_file;
\set ON_ERROR_STOP off
\ir ../supabase/proposals/r551_helper_api_access_20261026.up.sql
\set guard_sqlstate :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT dependency_guard;
SELECT pg_temp.assert_true(:'guard_sqlstate'='PDC03','view dependency rejected before ACL change');
SAVEPOINT acl_guard;
CREATE ROLE synthetic_extra NOLOGIN;
GRANT SELECT ON public._r551_stmt TO synthetic_extra;
\set ON_ERROR_STOP off
\ir ../supabase/proposals/r551_helper_api_access_20261026.up.sql
\set guard_sqlstate :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT acl_guard;
SELECT pg_temp.assert_true(:'guard_sqlstate'='PDC01','unexpected ACL rejected before either table change');
\ir ../supabase/proposals/r551_helper_api_access_20261026.up.sql
DO $assert$ DECLARE t record; BEGIN
 FOR t IN SELECT * FROM baseline LOOP
  IF has_table_privilege('anon',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
  OR has_table_privilege('authenticated',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
  OR NOT has_table_privilege('service_role',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
  OR NOT has_table_privilege('postgres',t.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') THEN RAISE EXCEPTION 'role matrix failed'; END IF;
 END LOOP;
END $assert$;
SET LOCAL ROLE anon;
DO $denials$ BEGIN
 BEGIN PERFORM 1 FROM public._r551_file; RAISE EXCEPTION 'anon SELECT unexpectedly permitted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO public._r551_stmt VALUES(99,'must-not-save'); RAISE EXCEPTION 'anon INSERT unexpectedly permitted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denials$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $denials$ BEGIN
 BEGIN PERFORM 1 FROM public._r551_stmt; RAISE EXCEPTION 'authenticated SELECT unexpectedly permitted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO public._r551_file VALUES(99,'must-not-save'); RAISE EXCEPTION 'authenticated INSERT unexpectedly permitted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denials$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT count(*) AS service_can_read FROM public._r551_file;
INSERT INTO public._r551_file VALUES(99,'service-still-works');
DELETE FROM public._r551_file WHERE n=99;
INSERT INTO public._r551_stmt VALUES(99,'service-still-works');
DELETE FROM public._r551_stmt WHERE n=99;
RESET ROLE;
INSERT INTO public._r551_file VALUES(99,'owner-still-works'); DELETE FROM public._r551_file WHERE n=99;
INSERT INTO public._r551_stmt VALUES(99,'owner-still-works'); DELETE FROM public._r551_stmt WHERE n=99;
\ir ../supabase/proposals/r551_helper_api_access_20261026.down.sql
DO $rollback$ DECLARE t record; current_acl aclitem[]; actual_rows jsonb; BEGIN
 FOR t IN SELECT * FROM baseline LOOP
  SELECT relacl INTO current_acl FROM pg_class WHERE oid=t.oid;
  IF NOT(current_acl @> t.relacl AND current_acl <@ t.relacl) THEN RAISE EXCEPTION 'exact ACL set not restored'; END IF;
  EXECUTE format('SELECT jsonb_agg(to_jsonb(t) ORDER BY n) FROM public.%I t',t.relname) INTO actual_rows;
  IF actual_rows IS DISTINCT FROM t.rows THEN RAISE EXCEPTION 'contents changed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=t.oid AND c.relowner=t.relowner AND c.relrowsecurity=t.relrowsecurity AND c.relforcerowsecurity=t.relforcerowsecurity) THEN RAISE EXCEPTION 'OID/owner/RLS changed'; END IF;
 END LOOP;
END $rollback$;
SELECT 'PASS: helper ACL matrix, real role denials, owner/service operations, exact ACL rollback, contents/OID/owner/RLS preservation' AS result;
ROLLBACK;