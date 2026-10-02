-- Fictional customer-only finance applications; all changes roll back.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $test$
DECLARE actor public.pdc_user_roles; result jsonb; app uuid:=gen_random_uuid(); legacy uuid:=gen_random_uuid(); denied boolean; f text; version integer:=1; today text:=(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date::text; original_public text; final_public text; accum text; value_hash text; t record;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING required'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 IF actor.id IS NULL THEN RAISE EXCEPTION 'Missing administrator fixture'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; original_public:=md5(accum);
 result:=public.save_broome_finance_application(app,NULL,'{}',NULL,'{"customer":"Example customer-only application","financier":"TFS","finance_comm":100.10,"dof_daf":20.20,"naf":12345.67}',0);
 IF result#>'{record,vehicle}'<>'{}'::jsonb OR result#>>'{record,total_comm}'<>'120.30' THEN RAISE EXCEPTION 'Customer-only creation or total incorrect'; END IF;
 PERFORM public.save_broome_finance_application(app,NULL,'{}',NULL,'{"customer":"Example customer-only application","financier":"TFS","finance_comm":100.10,"dof_daf":20.20,"naf":12345.67}',0);
 PERFORM public.save_broome_finance_application(app,NULL,NULL,NULL,'{"customer":"Example customer-only application","financier":"TFS","finance_comm":100.10,"dof_daf":20.20,"naf":12345.67}',0);
 IF (SELECT x.version FROM pdc_sales_private.finance_applications x WHERE id=app)<>1 THEN RAISE EXCEPTION 'Creation retry changed or duplicated application'; END IF;
 FOREACH f IN ARRAY ARRAY['TFS','TFM','FARADAY','OTHER'] LOOP
  result:=public.save_broome_finance_application(app,NULL,NULL,NULL,jsonb_build_object('financier',f),version); version:=version+1;
  IF result#>>'{record,financier}'<>f THEN RAISE EXCEPTION 'Financier choice did not persist'; END IF;
 END LOOP;
 denied:=false; BEGIN PERFORM public.save_broome_finance_application(app,NULL,NULL,NULL,'{"financier":"NOT A FINANCIER"}',version); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'Invalid financier accepted'; END IF;
 result:=public.save_broome_finance_application(app,NULL,NULL,NULL,'{"settlement":"Yes"}',version); version:=version+1;
 IF result#>>'{record,settlement_date}'<>today THEN RAISE EXCEPTION 'New settlement did not receive Perth date'; END IF;
 result:=public.save_broome_finance_application(app,NULL,NULL,NULL,'{"settlement_date":"2024-02-29"}',version); version:=version+1;
 result:=public.save_broome_finance_application(app,NULL,NULL,NULL,'{"notes":"Editing notes must not move settlement month"}',version); version:=version+1;
 IF result#>>'{record,settlement_date}'<>'2024-02-29' THEN RAISE EXCEPTION 'Settlement month changed when notes edited'; END IF;
 FOREACH f IN ARRAY ARRAY['2023-02-29','2024-02-30','2024-2-29','1899-12-31','9999-01-01',''] LOOP
  denied:=false; BEGIN PERFORM public.save_broome_finance_application(app,NULL,NULL,NULL,jsonb_build_object('settlement_date',f),version); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'Invalid/future settlement date accepted: %',f; END IF;
 END LOOP;
 denied:=false; BEGIN PERFORM public.save_broome_finance_application(app,NULL,NULL,NULL,'{"notes":"stale update"}',version-1); EXCEPTION WHEN serialization_failure THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'Stale date edit accepted'; END IF;
 result:=public.save_broome_finance_application(app,NULL,NULL,NULL,'{"settlement":"No"}',version); version:=version+1;
 IF result#>>'{record,settlement_date}'<>'' THEN RAISE EXCEPTION 'Non-settled row retained settlement month'; END IF;
 result:=public.save_broome_finance_application(legacy,NULL,'{}',NULL,'{"customer":"Example undated legacy entry","settlement":"Yes"}',0);
 UPDATE pdc_sales_private.finance_applications SET data=(data-'settlement_date')||'{"financier":"TFS BM"}'::jsonb WHERE id=legacy;
 result:=public.save_broome_finance_application(legacy,NULL,NULL,NULL,'{"notes":"Legacy notes update"}',1);
 IF nullif(result#>>'{record,settlement_date}','') IS NOT NULL OR result#>>'{record,financier}'<>'TFS BM' THEN RAISE EXCEPTION 'Legacy date inferred or financier overwritten'; END IF;
 denied:=false; BEGIN PERFORM public.save_broome_finance_application(gen_random_uuid(),NULL,'{}',NULL,'{"customer":"   "}',0); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'Blank customer accepted'; END IF;
 denied:=false; BEGIN PERFORM public.save_broome_finance_application(app,NULL,NULL,NULL,'{"bay":"Changed"}',version); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'PDC field accepted'; END IF;
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; final_public:=md5(accum);
 IF original_public<>final_public THEN RAISE EXCEPTION 'Finance statistics changed public/PDC rows'; END IF;
END $test$;
SELECT 'PASS: customer-only applications, all financier choices, idempotent retry, actual settlement dates, legacy preservation, date validation and no PDC changes. All fixtures rolled back.' AS result;
ROLLBACK;
