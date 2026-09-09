-- STAGING only: repair existing endpoints without changing business records or grants.
DO $migration$
DECLARE
 d text; patched text;
 guard_sql text := $guard$auth.role() is distinct from 'authenticated'
    or auth.uid() is null
    or not exists (
      select 1 from public.pdc_user_roles r
      where r.auth_user_id = auth.uid()
        and lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
        and r.active is true
        and r.account_status::text = 'approved'
        and r.role::text in ('operator', 'importer', 'administrator')
    )$guard$;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING only'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:staging:audit-priority-20260909',0));
 SELECT pg_get_functiondef('public.save_pdc_online_state(text,jsonb,bigint,text)'::regprocedure) INTO d;
 IF md5(d)<>'1adae884b4f6c4d4aa2721d7652a8e5d' THEN RAISE EXCEPTION 'Online save changed since review'; END IF;
 patched:=replace(d,'v_actor is null or v_role not in (''operator'', ''importer'', ''administrator'')',guard_sql);
 patched:=replace(patched,'jsonb_typeof(v_payload) <> ''array''','jsonb_typeof(v_payload) is distinct from ''array''');
 patched:=replace(patched,'jsonb_typeof(v_item) <> ''object''','jsonb_typeof(v_item) is distinct from ''object''');
 patched:=replace(patched,'return jsonb_build_object(''ok'', false, ''error'', ''invalid_vehicle_row'');','raise exception using errcode = ''PDC01'', message = ''invalid_vehicle_row'';');
 patched:=replace(patched,'return jsonb_build_object(''ok'', false, ''error'', ''invalid_manual_vehicle_id'');','raise exception using errcode = ''PDC01'', message = ''invalid_manual_vehicle_id'';');
 patched:=replace(patched,E'  return v_response;\nend;',E'  return v_response;\nexception\n  when sqlstate ''PDC01'' then\n    return jsonb_build_object(''ok'', false, ''error'', sqlerrm);\nend;');
 IF patched=d OR position('when sqlstate ''PDC01''' in patched)=0 OR position('r.account_status::text = ''approved''' in patched)=0 OR position('return jsonb_build_object(''ok'', false, ''error'', ''invalid_vehicle_row'');' in patched)>0 THEN RAISE EXCEPTION 'Online save repair did not match'; END IF;
 EXECUTE patched;
 SELECT pg_get_functiondef('public.save_pdc_online_state_batch(jsonb,text)'::regprocedure) INTO d;
 IF md5(d)<>'c000cdcddf7b1a9fda39957315702941' THEN RAISE EXCEPTION 'Online batch changed since review'; END IF;
 patched:=replace(d,'auth.uid() is null or public.current_pdc_user_role()::text not in (''operator'', ''importer'', ''administrator'')',guard_sql);
 patched:=replace(patched,'jsonb_typeof(p_items) <> ''array''','jsonb_typeof(p_items) is distinct from ''array''');
 patched:=replace(patched,'jsonb_typeof(v_item) <> ''object''','jsonb_typeof(v_item) is distinct from ''object''');
 IF patched=d OR position('r.account_status::text = ''approved''' in patched)=0 THEN RAISE EXCEPTION 'Online batch repair did not match'; END IF;
 EXECUTE patched;
END $migration$;