-- r460 (F73) contract test: read-only (raises on failure). Staging cdsmnqxtyyoeoznmbidd.
DO $t$ DECLARE r record; BEGIN
 SELECT * INTO r FROM pdc_ops.fault_regression_check() WHERE check_name='vehicle_key_number_audit_460';
 IF NOT FOUND OR NOT r.ok THEN RAISE EXCEPTION 'r460 check not ok: %', r.detail; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) AND md5(p.prosrc)=e.prosrc_md5 WHERE e.release='r460')<>6 THEN RAISE EXCEPTION 'r460 pins drifted'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.vehicles'::regclass AND tgname IN ('zz_pdc_key_number_audit_460_upd','zz_pdc_key_number_audit_460_ins') AND tgenabled='O')<>2 THEN RAISE EXCEPTION 'r460 capture triggers missing'; END IF;
 IF has_function_privilege('authenticated','pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','EXECUTE')
    OR has_table_privilege('authenticated','public.pdc_vehicle_key_number_audit_460','SELECT') THEN RAISE EXCEPTION 'r460 grants wrong'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'4b25c88071288d598d4ae29c50320d3b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_arrival(uuid)'::regprocedure)<>'5e9ca7c4862bdee353c958f86f2edd35' THEN RAISE EXCEPTION 'r460: service import key writers changed'; END IF;
END $t$;
SELECT 'PASS: key number audit append-only and private, capture triggers on, latest audit = vehicle key, 6 pins, importers unchanged' AS result;
