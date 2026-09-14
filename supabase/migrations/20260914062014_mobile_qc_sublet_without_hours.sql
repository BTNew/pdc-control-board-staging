-- STAGING ONLY: Sublet requires an inspector tick, but no workshop hours.
-- No vehicle, operation, booking, photo or completion record is changed.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-mobile-qc-sublet-20260914',0));

DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_STAGING_ONLY'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
     WHERE conrelid='public.pdc_qc_operation_completions_379'::regclass
       AND conname='pdc_qc_operation_completions_379_stage_code_check')
 IS DISTINCT FROM $expected$CHECK ((stage_code = ANY (ARRAY['BUS_4X4'::text, 'TINT'::text, 'HOIST'::text, 'FITTING'::text, 'FABRICATION'::text, 'ELECTRICAL'::text, 'TYRE'::text])))$expected$
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_COMPLETION_CONSTRAINT_CHANGED'; END IF;
END $guard$;

-- Permit the existing Sublet stage in the per-operation completion ledger.
ALTER TABLE public.pdc_qc_operation_completions_379
 DROP CONSTRAINT pdc_qc_operation_completions_379_stage_code_check;
ALTER TABLE public.pdc_qc_operation_completions_379
 ADD CONSTRAINT pdc_qc_operation_completions_379_stage_code_check
 CHECK (stage_code IN ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'));

-- Patch the inspected live definitions without changing their other guards,
-- function configuration, owners, grants, receipt handling or audit writes.
DO $patch$
DECLARE d text; before_acl aclitem[]; before_owner oid; function_id oid;
BEGIN

 -- book_rft_transport_734
 function_id:='public.book_rft_transport_734(uuid,integer,uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'0f4c62ae8b382ac12d87c4205f97a279' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: book_rft_transport_734'; END IF;
 d:=replace(d,$old$nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL$old$,$new$(line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: book_rft_transport_734'; END IF;

 -- book_rft_transport_email_draft_739
 function_id:='public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'2b7c48ac814cca4cefb4f985b5608ccd' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: book_rft_transport_email_draft_739'; END IF;
 d:=replace(d,$old$nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL$old$,$new$(line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: book_rft_transport_email_draft_739'; END IF;

 -- finalize_pdc_qc_retest_to_rft_747
 function_id:='public.finalize_pdc_qc_retest_to_rft_747(uuid,integer,uuid,uuid,uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'0547ebfcc88a6e8c5838fa65a792c5af' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: finalize_pdc_qc_retest_to_rft_747'; END IF;
 d:=replace(d,$old$nullif(btrim(coalesce(x->>'estimated_hours','')),'') IS NULL$old$,$new$(x->>'stage_code' IS DISTINCT FROM 'SUBLET' AND nullif(btrim(coalesce(x->>'estimated_hours','')),'') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: finalize_pdc_qc_retest_to_rft_747'; END IF;

 -- finalize_pdc_qc_to_rft_399
 function_id:='public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'df7ad22476160390253ae2015cd0ba3a' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: finalize_pdc_qc_to_rft_399'; END IF;
 d:=replace(d,$old$(line->>'estimated_hours') IS NULL$old$,$new$(line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: finalize_pdc_qc_to_rft_399'; END IF;

 -- finalize_pdc_qc_to_rft_700
 function_id:='public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'8a373b1b4959a100ef4c77e0863f3914' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: finalize_pdc_qc_to_rft_700'; END IF;
 d:=replace(d,$old$(line->>'estimated_hours') IS NULL$old$,$new$(line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: finalize_pdc_qc_to_rft_700'; END IF;

 -- pdc_qc_require_all_operations_complete_379
 function_id:='public.pdc_qc_require_all_operations_complete_379()'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'e30cfb81f3c7bc5b6918386be2d17048' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: pdc_qc_require_all_operations_complete_379'; END IF;
 d:=replace(d,$old$(l->>'estimated_hours') IS NULL$old$,$new$(l->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (l->>'estimated_hours') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: pdc_qc_require_all_operations_complete_379'; END IF;

 -- read_rft_transport_booking_context_739
 function_id:='public.read_rft_transport_booking_context_739(uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'dcca64a27899b4f33b25cc0fa280ed87' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: read_rft_transport_booking_context_739'; END IF;
 d:=replace(d,$old$nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL$old$,$new$(line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: read_rft_transport_booking_context_739'; END IF;

 -- set_pdc_qc_operation_completion_379
 function_id:='public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'4e478286d33393a6ff7157527596c4ae' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: set_pdc_qc_operation_completion_379'; END IF;
 d:=replace(d,$old$IF v_hours IS NULL THEN$old$,$new$IF v_stage IS DISTINCT FROM 'SUBLET' AND v_hours IS NULL THEN$new$);
 d:=replace(d,$old$(l->>'estimated_hours') IS NULL$old$,$new$(l->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (l->>'estimated_hours') IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: set_pdc_qc_operation_completion_379'; END IF;

 -- pdc_qc_rework_scope_20260909
 function_id:='public.pdc_qc_rework_scope_20260909(uuid)'::regprocedure;
 SELECT proacl,proowner INTO before_acl,before_owner FROM pg_proc WHERE oid=function_id;
 d:=pg_get_functiondef(function_id);
 IF md5(d)<>'8699ee82a620ab504bf7d2b2b671fb36' THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_FUNCTION_CHANGED: pdc_qc_rework_scope_20260909'; END IF;
 d:=replace(d,$old$s->>'estimated_hours' IS NULL$old$,$new$(s->>'stage_code' IS DISTINCT FROM 'SUBLET' AND s->>'estimated_hours' IS NULL)$new$);
 EXECUTE d;
 IF (SELECT proacl FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_acl
  OR (SELECT proowner FROM pg_proc WHERE oid=function_id) IS DISTINCT FROM before_owner
 THEN RAISE EXCEPTION 'MOBILE_QC_SUBLET_PRIVILEGE_CHANGED: pdc_qc_rework_scope_20260909'; END IF;

END $patch$;
NOTIFY pgrst, 'reload schema';
COMMIT;
