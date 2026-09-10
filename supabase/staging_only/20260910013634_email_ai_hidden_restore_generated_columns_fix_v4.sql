DO $fix$
DECLARE d text; patched text;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING only'; END IF;
  SELECT pg_get_functiondef('public.pdc_email_ai_restore_hidden_new_vehicle_v1(uuid,text,uuid,uuid,text)'::regprocedure) INTO d;
  patched:=regexp_replace(d,'stock_number_normalized\s*=\s*v_stock\s*,','','g');
  patched:=regexp_replace(patched,'vin_normalized\s*=\s*coalesce\([^\n]*?\),','','g');
  patched:=regexp_replace(patched,'source_system_normalized\s*=\s*''microsoft_navision''\s*,','','g');
  patched:=regexp_replace(patched,'source_record_id_normalized\s*=\s*upper\(v_backend.id::text\)\s*,','','g');
  IF patched=d THEN RAISE EXCEPTION 'generated-column repair did not change reviewed definition'; END IF;
  EXECUTE patched;
END
$fix$;
