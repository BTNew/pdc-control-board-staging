-- STAGING ONLY 495: let the reviewed archive transaction finish after its Navision activation update fires reconciliation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-495-archive-navision-reconcile-order',0));
DO $guard$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR v_head IS DISTINCT FROM '20260827044000'
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827044000' AND name='494_navision_all_vehicle_link_refresh_guard')
  OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'187184aee255de64dc89a8d21aea91a2e7b6e95bcce5e631c91f44184a103b81'
  OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_vehicle_archive_recreation_gate()'::regprocedure),'UTF8'),'sha256'),'hex')<>'2e640e679330d0713bebe37834d342d7df66c9efb2be42c3cc95b77e254e6209'
 THEN RAISE EXCEPTION 'PDC_495_TARGET_HEAD_OR_FUNCTION_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

DO $repair$
DECLARE archive_def text; gate_def text;
BEGIN
 archive_def:=pg_get_functiondef('public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)'::regprocedure);
 IF position('pdc.vehicle_archive_in_progress' in archive_def)>0 OR position('insert into public.pdc_vehicle_tombstones' in archive_def)=0 THEN
  RAISE EXCEPTION 'PDC_495_ARCHIVE_REPLACEMENT_MARKER_MISMATCH' USING errcode='55000';
 END IF;
 archive_def:=replace(archive_def,
  'insert into public.pdc_vehicle_tombstones',
  'perform set_config(''pdc.vehicle_archive_in_progress'',v.id::text,true);'||chr(10)||' insert into public.pdc_vehicle_tombstones');
 EXECUTE archive_def;

 gate_def:=pg_get_functiondef('public.pdc_vehicle_archive_recreation_gate()'::regprocedure);
 IF position('pdc.vehicle_archive_in_progress' in gate_def)>0 OR position('if tg_op=''UPDATE'' then raise exception ''PDC_VEHICLE_TOMBSTONED''' in gate_def)=0 THEN
  RAISE EXCEPTION 'PDC_495_GATE_REPLACEMENT_MARKER_MISMATCH' USING errcode='55000';
 END IF;
 gate_def:=replace(gate_def,
  'if tg_op=''UPDATE'' then raise exception ''PDC_VEHICLE_TOMBSTONED''',
  'if tg_op=''UPDATE'' and new.id=v_t.vehicle_id and current_setting(''pdc.vehicle_archive_in_progress'',true)=new.id::text then return new;end if;'||chr(10)||' if tg_op=''UPDATE'' then raise exception ''PDC_VEHICLE_TOMBSTONED''');
 EXECUTE gate_def;
END $repair$;

REVOKE ALL ON FUNCTION public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text),public.pdc_vehicle_archive_recreation_gate() FROM public,anon,authenticated,service_role;

DO $post$
DECLARE a text:=pg_get_functiondef('public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)'::regprocedure);g text:=pg_get_functiondef('public.pdc_vehicle_archive_recreation_gate()'::regprocedure);
BEGIN
 IF position('pdc.vehicle_archive_in_progress' in a)=0
  OR position('pdc.vehicle_archive_in_progress' in g)=0
  OR has_function_privilege('authenticated','public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)','EXECUTE')
  OR has_function_privilege('service_role','public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_495_ARCHIVE_SCOPE_OR_ACL_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827045000','495_archive_navision_reconcile_order',ARRAY[
 'Repair the recoverable staging archive transaction so its own Navision activation reconciliation cannot be rejected by the tombstone gate',
 'Scope the allowance to the exact archived vehicle and current transaction only',
 'Keep the private archive implementation non-executable by API roles and preserve all recreation, identity and RLS controls',
 'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
