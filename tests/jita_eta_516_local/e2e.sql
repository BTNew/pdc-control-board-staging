-- r516 local proof. Synthetic stocks only. The sample paste is /tmp/jita-sample.tsv.
\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","email":"viewer@example.com","pdc_role":"viewer"}', false);
DO $$BEGIN
  BEGIN
    PERFORM public.import_jita_eta_516('JITA Vehicle'||chr(9)||'Qty Oustanding'||chr(9)||'JITA Planned Delivery Date'||chr(10)||'13102912'||chr(9)||'1'||chr(9)||'29/10/2026', true);
    RAISE EXCEPTION 'viewer was allowed to import';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END$$;
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","email":"op@example.com","pdc_role":"operator"}', false);
DO $$BEGIN
  BEGIN
    PERFORM public.import_jita_eta_516('x', true);
    RAISE EXCEPTION 'operator was allowed to import';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END$$;
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","email":"sales@example.com","pdc_role":"salesperson"}', false);
SELECT CASE WHEN public.get_pdc_jita_eta_board() IS NULL THEN 'salesperson null' ELSE 'FAIL salesperson' END;

SELECT set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-8444-444444444444","email":"importer@example.com","pdc_role":"importer"}', false);
SELECT public.import_jita_eta_516(pg_read_file('/tmp/jita-sample.tsv'), true) AS preview \gset
SELECT CASE
  WHEN (:'preview'::jsonb->>'ok')::boolean
   AND (:'preview'::jsonb->>'dry_run')::boolean
   AND (:'preview'::jsonb->'results'->0->>'stock')='13102912'
   AND (:'preview'::jsonb->'results'->0->>'eta_date')='2026-10-29'
   AND (:'preview'::jsonb->'results'->0->>'status')='would_apply'
   AND (:'preview'::jsonb->'results'->0->>'rule')='latest_outstanding'
  THEN 'preview 2026-10-29' ELSE 'FAIL preview '||:'preview' END;
SELECT CASE WHEN (SELECT count(*) FROM public.pdc_jita_eta)=0 AND (SELECT count(*) FROM public.pdc_jita_eta_audit)=0
  THEN 'dry run wrote nothing' ELSE 'FAIL dry run wrote' END;

SELECT public.import_jita_eta_516(pg_read_file('/tmp/jita-sample.tsv'), false) AS applied \gset
SELECT CASE
  WHEN (:'applied'::jsonb->'results'->0->>'status')='applied'
   AND (:'applied'::jsonb->'results'->0->>'eta_date')='2026-10-29'
   AND (:'applied'::jsonb->>'message') LIKE 'Saved.%13102912 JITA ETA 29/10/2026.%'
  THEN 'applied 2026-10-29' ELSE 'FAIL applied '||:'applied' END;
SELECT CASE WHEN (SELECT count(*) FROM public.pdc_jita_eta WHERE NOT superseded AND eta_date='2026-10-29' AND stock_number='13102912')=1
  AND (SELECT count(*) FROM public.pdc_jita_eta_audit)=1
  AND (SELECT count(*) FROM public.pdc_parts_eta)=0
  THEN 'one current row' ELSE 'FAIL row count' END;

SELECT public.import_jita_eta_516(pg_read_file('/tmp/jita-sample.tsv'), false) AS again \gset
SELECT CASE WHEN (:'again'::jsonb->'results'->0->>'status')='unchanged'
  AND (SELECT count(*) FROM public.pdc_jita_eta WHERE NOT superseded)=1
  AND (SELECT count(*) FROM public.pdc_jita_eta_audit)=2
  THEN 'reapply unchanged' ELSE 'FAIL reapply '||:'again' END;

SELECT public.import_jita_eta_516('JITA Vehicle'||chr(9)||'Qty Oustanding'||chr(9)||'JITA Planned Delivery Date'||chr(10)||'13102912'||chr(9)||'1'||chr(9)||'01/11/2026', false) AS replaced \gset
SELECT CASE WHEN (:'replaced'::jsonb->'results'->0->>'status')='replaced'
  AND (SELECT eta_date FROM public.pdc_jita_eta WHERE NOT superseded)='2026-11-01'
  AND (SELECT count(*) FROM public.pdc_jita_eta WHERE superseded)=1
  THEN 'replaced newer date' ELSE 'FAIL replace '||:'replaced' END;

SELECT public.import_jita_eta_516(pg_read_file('/tmp/jita-sample.tsv'), false) AS back \gset
SELECT CASE WHEN (SELECT eta_date FROM public.pdc_jita_eta WHERE NOT superseded AND stock_number='13102912')='2026-10-29'
  THEN 'sample restored' ELSE 'FAIL restore' END;

SELECT public.import_jita_eta_516(
  'JITA Vehicle'||chr(9)||'Qty Oustanding'||chr(9)||'JITA Planned Delivery Date'||chr(9)||'Latest ETA'||chr(9)||'Vehicle ETA at Kewdale'||chr(10)
  ||'99999999'||chr(9)||'1'||chr(9)||'02/12/2026'||chr(9)||'01/01/2027'||chr(9)||'03/01/2027'||chr(10)
  ||'DELETED1'||chr(9)||'1'||chr(9)||'02/12/2026'||chr(9)||'01/01/2027'||chr(9)||'03/01/2027'||chr(10)
  ||'PURGED01'||chr(9)||'1'||chr(9)||'02/12/2026'||chr(9)||'01/01/2027'||chr(9)||'03/01/2027'||chr(10)
  ||'TWICE'||chr(9)||'1'||chr(9)||'02/12/2026'||chr(9)||'01/01/2027'||chr(9)||'03/01/2027'||chr(10)
  ||'13102912'||chr(9)||'1'||chr(9)||'29/10/2026'||chr(9)||'01/01/2027'||chr(9)||'03/01/2027',
  false) AS skips \gset
SELECT CASE
  WHEN (:'skips'::jsonb->'results'->0->>'status')='unchanged'
   AND (:'skips'::jsonb->'results'->1->>'status')='skipped_unknown'
   AND (:'skips'::jsonb->'results'->2->>'status')='skipped_unknown'
   AND (:'skips'::jsonb->'results'->3->>'status')='skipped_unknown'
   AND (:'skips'::jsonb->'results'->4->>'status')='ambiguous'
   AND (SELECT count(*) FROM public.pdc_jita_eta WHERE NOT superseded)=1
   AND (SELECT eta_date FROM public.pdc_jita_eta WHERE NOT superseded)='2026-10-29'
  THEN 'skips clean' ELSE 'FAIL skips '||:'skips' END;

SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","email":"view2@example.com","pdc_role":"viewer"}', false);
SELECT CASE WHEN (public.get_pdc_jita_eta_board()->'vehicles'->0->>'eta_date')='2026-10-29'
  AND (public.get_pdc_jita_eta_board()->'vehicles'->0->>'stock_number')='13102912'
  THEN 'board read' ELSE 'FAIL board' END;

SELECT CASE WHEN (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)'))='88d31cbd6ca5ddd372e3143d5f8c013f'
  THEN 'set_parts_eta unchanged' ELSE 'FAIL parts md5' END;

SET ROLE anon;
DO $$BEGIN
  BEGIN
    PERFORM public.jita_eta_parse_516('x');
    RAISE EXCEPTION 'anon could parse';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END$$;
RESET ROLE;

SELECT set_config('request.jwt.claims', '{"pdc_role":"importer"}', false);
SET ROLE authenticated;
DO $$BEGIN
  BEGIN
    INSERT INTO public.pdc_jita_eta(id,vehicle_id,stock_number,eta_date,rule,source_rows,outstanding_rows,source_md5,set_at,set_by_actor)
    VALUES (gen_random_uuid(),'13102912-0000-4000-8000-000000000001','13102912','2026-01-01','latest_any',1,1,'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',now(),'x');
    RAISE EXCEPTION 'authenticated inserted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END$$;
RESET ROLE;
SELECT 'e2e done';
