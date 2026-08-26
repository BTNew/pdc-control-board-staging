-- STAGING ONLY 494: every active vehicle with Navision data must be linked and refreshed on every upload.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-494-navision-all-vehicle-link-refresh-guard',0));

DO $guard$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR v_head IS DISTINCT FROM '20260827043000'
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827043000' AND name='493_all_vehicle_operation_projection_guard')
  OR encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'2b2201e6cf5a5b13ef07250fe94c8d2a79375daa9aa93da58cef62432e7723f7'
  OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.navision_backend_records'::regclass AND tgname='navision_record_operational_reconcile' AND tgenabled='O')<>1
 THEN RAISE EXCEPTION 'PDC_494_TARGET_HEAD_OR_RECONCILER_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TABLE public.pdc_owner_navision_all_vehicle_rules_494(
 rule_key text PRIMARY KEY CHECK(rule_key='all-vehicles-link-and-refresh-from-current-navision'),
 rule_text text NOT NULL CHECK(rule_text='Whenever current Navision data exists, every active operational vehicle links to exactly one current Navision row by exact Stock. Every Navision upload refreshes that linked vehicle details and reconciles its location through Craig-approved lifecycle rules; ambiguity fails closed and no duplicate vehicle is created.'),
 created_by_email text NOT NULL CHECK(created_by_email='craig.watson@broometoyota.com.au'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_owner_navision_all_vehicle_rules_494 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_owner_navision_all_vehicle_rules_494 FROM public,anon,authenticated,service_role;
INSERT INTO public.pdc_owner_navision_all_vehicle_rules_494(rule_key,rule_text,created_by_email) VALUES(
 'all-vehicles-link-and-refresh-from-current-navision',
 'Whenever current Navision data exists, every active operational vehicle links to exactly one current Navision row by exact Stock. Every Navision upload refreshes that linked vehicle details and reconciles its location through Craig-approved lifecycle rules; ambiguity fails closed and no duplicate vehicle is created.',
 'craig.watson@broometoyota.com.au'
);

CREATE FUNCTION public.pdc_navision_vehicle_parity_494(p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $parity$
 WITH nav AS(
  SELECT b.*,nullif(upper(regexp_replace(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''),'[^A-Z0-9]','','g')),'') stock
  FROM public.navision_backend_records b
  WHERE b.is_current AND b.record_status='current'
 ), scoped AS(
  SELECT v.id vehicle_id,v.stock_number,v.stock_number_normalized stock,
   count(n.id)::integer navision_match_count,
   count(n.id) FILTER(WHERE n.canonical_vehicle_id=v.id)::integer linked_match_count,
   count(n.id) FILTER(WHERE n.canonical_vehicle_id=v.id
    AND v.source_system='microsoft_navision'
    AND v.source_record_id=n.id::text
    AND coalesce(v.source_payload->>'navision_version','')=n.version::text
    AND coalesce(v.source_payload->>'navision_status','')=coalesce(n.normalized_data->>'toyotaStatus','')
    AND nullif(v.source_payload->>'navision_updated_at','')::timestamptz IS NOT DISTINCT FROM n.updated_at
   )::integer fresh_detail_location_count
  FROM public.vehicles v
  LEFT JOIN nav n ON n.stock=v.stock_number_normalized
  WHERE v.deleted_at IS NULL AND (p_vehicle_id IS NULL OR v.id=p_vehicle_id)
  GROUP BY v.id,v.stock_number,v.stock_number_normalized
 ), in_scope AS(
  SELECT * FROM scoped WHERE navision_match_count>0
 ), mismatches AS(
  SELECT * FROM in_scope
  WHERE navision_match_count<>1 OR linked_match_count<>1 OR fresh_detail_location_count<>1
 )
 SELECT jsonb_build_object(
  'ok',NOT EXISTS(SELECT 1 FROM mismatches),
  'active_vehicle_count',(SELECT count(*) FROM scoped),
  'vehicles_with_navision_data',(SELECT count(*) FROM in_scope),
  'vehicles_without_navision_data',(SELECT count(*) FROM scoped WHERE navision_match_count=0),
  'ambiguous_match_count',(SELECT count(*) FROM in_scope WHERE navision_match_count>1),
  'link_mismatch_count',(SELECT count(*) FROM in_scope WHERE navision_match_count=1 AND linked_match_count<>1),
  'stale_detail_location_count',(SELECT count(*) FROM in_scope WHERE navision_match_count=1 AND fresh_detail_location_count<>1),
  'mismatch_count',(SELECT count(*) FROM mismatches),
  'mismatches',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY stock,vehicle_id) FROM mismatches m),'[]'::jsonb)
 )
$parity$;
REVOKE ALL ON FUNCTION public.pdc_navision_vehicle_parity_494(uuid) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.pdc_navision_vehicle_parity_494(uuid) TO authenticated,service_role;

CREATE FUNCTION public.pdc_enforce_navision_vehicle_parity_494()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $trigger$
DECLARE v_check jsonb;
BEGIN
 v_check:=public.pdc_navision_vehicle_parity_494(NULL);
 IF coalesce((v_check->>'ok')::boolean,false) IS NOT TRUE THEN
  RAISE EXCEPTION 'PDC_NAVISION_VEHICLE_LINK_OR_REFRESH_INCOMPLETE: %',v_check USING errcode='23514';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $trigger$;
REVOKE ALL ON FUNCTION public.pdc_enforce_navision_vehicle_parity_494() FROM public,anon,authenticated,service_role;

CREATE CONSTRAINT TRIGGER zz_navision_all_vehicle_parity_494
AFTER INSERT OR UPDATE OF normalized_data,is_current,record_status,canonical_vehicle_id ON public.navision_backend_records
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.pdc_enforce_navision_vehicle_parity_494();
CREATE CONSTRAINT TRIGGER zz_vehicle_navision_parity_494
AFTER INSERT OR UPDATE OF stock_number,source_system,source_record_id,source_payload,deleted_at ON public.vehicles
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.pdc_enforce_navision_vehicle_parity_494();

DO $post$
DECLARE v_check jsonb;
BEGIN
 v_check:=public.pdc_navision_vehicle_parity_494(NULL);
 IF coalesce((v_check->>'ok')::boolean,false) IS NOT TRUE
  OR coalesce((v_check->>'mismatch_count')::integer,-1)<>0
  OR (SELECT count(*) FROM pg_trigger WHERE tgname IN('zz_navision_all_vehicle_parity_494','zz_vehicle_navision_parity_494') AND tgenabled='O' AND tgdeferrable AND tginitdeferred)<>2
  OR has_function_privilege('public','public.pdc_navision_vehicle_parity_494(uuid)','EXECUTE')
  OR has_function_privilege('anon','public.pdc_navision_vehicle_parity_494(uuid)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.pdc_navision_vehicle_parity_494(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_494_ALL_VEHICLE_NAVISION_PARITY_OR_ACL_POSTCONDITION_FAILED: %',v_check USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827044000','494_navision_all_vehicle_link_refresh_guard',ARRAY[
 'Persist Craig rule that every active vehicle with current Navision data must link to exactly one current Navision row by exact Stock',
 'Require every Navision upload to refresh linked vehicle details and reconcile location through established owner lifecycle rules',
 'Expose authenticated all-vehicle Navision link and refresh parity readback',
 'Fail Navision and vehicle transactions closed on ambiguity, missing canonical link or stale detail/location refresh',
 'Verify zero existing staging mismatches; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
