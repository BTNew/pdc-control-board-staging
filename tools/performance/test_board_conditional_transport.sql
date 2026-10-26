-- Run only in a fresh disposable local database: psql -v ON_ERROR_STOP=1 -f this-file.
-- This builds synthetic tables, fake access roles and an r545-like cache reader.
-- Never run this fixture against the working Supabase project.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='vehicles') THEN
  RAISE EXCEPTION 'fixture requires an empty disposable database';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $$;
CREATE SCHEMA pdc_ops;
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean,project_ref text);
INSERT INTO public.pdc_staging_environment_sentinel VALUES(true,'cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public.current_pdc_user_role() RETURNS text LANGUAGE sql AS $$ SELECT nullif(current_setting('test.role',true),'') $$;
CREATE FUNCTION public.navision_backend_response(p_ok boolean,p_code text) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('ok',p_ok,'code',p_code) $$;
CREATE TABLE public.pdc_email_vehicle_revision(singleton boolean PRIMARY KEY,revision bigint);
INSERT INTO public.pdc_email_vehicle_revision VALUES(true,1);
CREATE TABLE pdc_ops.vehicle_board_snapshot_cache_545(singleton boolean PRIMARY KEY,email_revision bigint NOT NULL,snapshot jsonb NOT NULL,computed_at timestamptz NOT NULL);
CREATE TABLE public.fixture_calls(n integer);
INSERT INTO public.fixture_calls VALUES(0);
CREATE FUNCTION public.get_pdc_email_vehicle_board_snapshot() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_payload jsonb; v_revision bigint;
BEGIN
 UPDATE public.fixture_calls SET n=n+1;
 IF current_setting('test.mode',true)='error' THEN RETURN jsonb_build_object('ok',false,'code','fixture_rebuild_error'); END IF;
 SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
 v_payload:=jsonb_build_object('ok',true,'code','fixture_board','data',jsonb_build_object('revision',v_revision,'vehicles',jsonb_build_array(jsonb_build_object('id','synthetic-1','operation_lines',jsonb_build_array(jsonb_build_object('estimated_hours',5,'source_estimated_hours',2,'active',true)),'qc_operation_lines',jsonb_build_array(jsonb_build_object('completed',false)),'parts_flags',jsonb_build_object('preserve',true)))));
 INSERT INTO pdc_ops.vehicle_board_snapshot_cache_545 VALUES(true,v_revision,v_payload,clock_timestamp()) ON CONFLICT(singleton) DO UPDATE SET email_revision=excluded.email_revision,snapshot=excluded.snapshot,computed_at=excluded.computed_at;
 IF current_setting('test.mode',true)='generation_mismatch' THEN UPDATE pdc_ops.vehicle_board_snapshot_cache_545 SET snapshot=snapshot||'{"another_generation":true}'::jsonb; END IF;
 RETURN v_payload;
END $$;
CREATE FUNCTION pg_temp.assert_true(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
\ir board-snapshot-conditional.sql
DO $$
DECLARE first_read jsonb; repeated_read jsonb; changed_read jsonb; cached jsonb; before_calls integer; token text;
BEGIN
 PERFORM set_config('test.role','operator',true);
 first_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(NULL);
 SELECT snapshot INTO cached FROM pdc_ops.vehicle_board_snapshot_cache_545;
 PERFORM pg_temp.assert_true(first_read-'snapshot_token'=cached,'initial full payload exact equality');
 token:=first_read->>'snapshot_token';
 PERFORM pg_temp.assert_true(token IS NOT NULL,'initial response carries generation token');
 SELECT n INTO before_calls FROM public.fixture_calls;
 repeated_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(token);
 PERFORM pg_temp.assert_true(repeated_read->>'not_modified'='true','same generation replies not modified');
 PERFORM pg_temp.assert_true(NOT repeated_read?'data','not-modified reply carries no vehicle data');
 PERFORM pg_temp.assert_true((SELECT n=before_calls FROM public.fixture_calls),'fresh cache does not rebuild');
 PERFORM pg_temp.assert_true(octet_length(repeated_read::text)<250,'not-modified reply is bounded');
 changed_read:=public.get_pdc_email_vehicle_board_snapshot_conditional('wrong-generation');
 PERFORM pg_temp.assert_true(changed_read-'snapshot_token'=cached,'unknown token returns full unchanged payload');
 UPDATE public.pdc_email_vehicle_revision SET revision=2;
 changed_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(token);
 PERFORM pg_temp.assert_true(changed_read#>>'{data,revision}'='2' AND changed_read->>'snapshot_token'<>token,'revision invalidates previous response');
 token:=changed_read->>'snapshot_token';
 UPDATE pdc_ops.vehicle_board_snapshot_cache_545 SET computed_at=clock_timestamp()-interval '16 seconds';
 changed_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(token);
 PERFORM pg_temp.assert_true(changed_read?'data' AND changed_read->>'snapshot_token'<>token,'expiry invalidates generation even at same revision');
 token:=changed_read->>'snapshot_token';
 SELECT n INTO before_calls FROM public.fixture_calls;
 PERFORM set_config('test.role','',true);
 PERFORM pg_temp.assert_true(public.get_pdc_email_vehicle_board_snapshot_conditional(token)->>'code'='unauthorized','null role denied on fresh cache');
 PERFORM set_config('test.role','revoked',true);
 PERFORM pg_temp.assert_true(public.get_pdc_email_vehicle_board_snapshot_conditional(token)->>'code'='unauthorized','revoked role denied on fresh cache');
 PERFORM pg_temp.assert_true((SELECT n=before_calls FROM public.fixture_calls),'denied cache read invokes no rebuild');
 UPDATE pdc_ops.vehicle_board_snapshot_cache_545 SET computed_at=clock_timestamp()-interval '16 seconds';
 PERFORM pg_temp.assert_true(public.get_pdc_email_vehicle_board_snapshot_conditional(NULL)->>'code'='unauthorized','invalid role denied before cold rebuild');
 PERFORM pg_temp.assert_true((SELECT n=before_calls FROM public.fixture_calls),'denied cold read invokes no rebuild');
 PERFORM set_config('test.role','viewer',true);
 PERFORM set_config('test.mode','generation_mismatch',true);
 changed_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(token);
 PERFORM pg_temp.assert_true(changed_read?'data' AND changed_read->'snapshot_token'='null'::jsonb,'mismatched concurrent generation never issues token');
 UPDATE pdc_ops.vehicle_board_snapshot_cache_545 SET computed_at=clock_timestamp()-interval '16 seconds';
 PERFORM set_config('test.mode','error',true);
 changed_read:=public.get_pdc_email_vehicle_board_snapshot_conditional(token);
 PERFORM pg_temp.assert_true(changed_read=jsonb_build_object('ok',false,'code','fixture_rebuild_error'),'rebuild errors preserved');
 PERFORM pg_temp.assert_true(NOT has_function_privilege('anon','public.get_pdc_email_vehicle_board_snapshot_conditional(text)','EXECUTE'),'anon endpoint access denied');
 PERFORM pg_temp.assert_true(has_function_privilege('authenticated','public.get_pdc_email_vehicle_board_snapshot_conditional(text)','EXECUTE'),'authenticated endpoint executable');
END $$;
-- Preserve the reviewed definition, then prove that the real rollback file
-- refuses both a newer body and changed security metadata without dropping it.
CREATE TEMP TABLE reviewed_conditional_definition AS SELECT pg_get_functiondef('public.get_pdc_email_vehicle_board_snapshot_conditional(text)'::regprocedure) AS definition;
DO $$ BEGIN EXECUTE replace((SELECT definition FROM reviewed_conditional_definition),'BEGIN','BEGIN'||chr(10)||'  -- synthetic newer release'); END $$;
SAVEPOINT newer_body;
\set ON_ERROR_STOP off
\ir board-snapshot-conditional.down.sql
\set refused_body_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT newer_body;
SELECT pg_temp.assert_true(:'refused_body_state'='PDC01','rollback refuses newer body');
SELECT pg_temp.assert_true(to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)') IS NOT NULL,'refused rollback preserves newer endpoint');
DO $$ BEGIN EXECUTE (SELECT definition FROM reviewed_conditional_definition); END $$;
ALTER FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text) SECURITY INVOKER;
SAVEPOINT changed_metadata;
\set ON_ERROR_STOP off
\ir board-snapshot-conditional.down.sql
\set refused_metadata_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT changed_metadata;
SELECT pg_temp.assert_true(:'refused_metadata_state'='PDC02','rollback refuses changed security metadata');
SELECT pg_temp.assert_true(to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)') IS NOT NULL,'refused metadata rollback preserves endpoint');
DO $$ BEGIN EXECUTE (SELECT definition FROM reviewed_conditional_definition); END $$;
\ir board-snapshot-conditional.down.sql
\ir board-snapshot-conditional.down.sql
SELECT pg_temp.assert_true(to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)') IS NULL,'rollback removes additive endpoint');
SELECT pg_temp.assert_true(to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()') IS NOT NULL,'rollback preserves legacy endpoint');
SELECT 'PASS: conditional board SQL scenarios and rollback' AS result;
ROLLBACK;