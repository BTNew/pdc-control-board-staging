-- STAGING ONLY 741: normalize the 739 booking email regex after read-lock repair.
-- The 739 function was applied before its source regex escaping was corrected.
-- This append-only successor changes only the effective function definition.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-741-rft-transport-email-draft-regex-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260829070000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260829070000' AND name='740_rft_transport_email_draft_read_lock_repair')<>1
     OR to_regprocedure('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_741_STAGING_ONLY' USING errcode='55000'; END IF;
END $guard$;

DO $repair$
DECLARE d text; repaired text; slash text:=chr(92);
BEGIN
  SELECT pg_get_functiondef('public.read_rft_transport_booking_context_739(uuid)'::regprocedure) INTO d;
  repaired:=replace(d,slash||slash||'.',slash||'.');
  IF repaired=d OR position(slash||slash||'.' in repaired)>0 OR position(slash||'.' in repaired)=0
    THEN RAISE EXCEPTION 'PDC_741_CONTEXT_REGEX_REPAIR_NOT_EXACT' USING errcode='55000'; END IF;
  EXECUTE repaired;
  SELECT pg_get_functiondef('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure) INTO d;
  repaired:=replace(d,slash||slash||'.',slash||'.');
  IF repaired=d OR position(slash||slash||'.' in repaired)>0 OR position(slash||'.' in repaired)=0
    THEN RAISE EXCEPTION 'PDC_741_BOOKING_REGEX_REPAIR_NOT_EXACT' USING errcode='55000'; END IF;
  EXECUTE repaired;
END $repair$;

DO $post$
BEGIN
  IF position(chr(92)||chr(92)||'.' in pg_get_functiondef('public.read_rft_transport_booking_context_739(uuid)'::regprocedure))>0
     OR position(chr(92)||chr(92)||'.' in pg_get_functiondef('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure))>0
     OR position('salesperson_email_required' in pg_get_functiondef('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure))=0
     OR has_function_privilege('anon','public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_741_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260829080000','741_rft_transport_email_draft_regex_repair',ARRAY[
  'Append-only repair over 739/740 normalizes the effective salesperson-email regex to accept the authoritative recipient',
  'No table, row, vehicle, transport receipt or outbox data is changed by this repair',
  'Production sentinel and outbound delivery containment remain required'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
