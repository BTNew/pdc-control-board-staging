-- Evidence for 20261003015156_sales_source_vin_and_labels.
-- Run only after the candidate helper/snapshot exists. All fixture edits are rolled back.
BEGIN;
DO $test$
DECLARE
 actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 source_row public.navision_backend_records; second_row public.navision_backend_records; canonical public.vehicles;
 snap jsonb; item jsonb; test_case record; denied boolean; dummy jsonb; vin_expression text; projected_vin text;
 vin_a text:='MR0REBHVX00541949'; vin_b text:='JTM5CAAVX0D014977';
 op_before text; op_after text; public_functions_before text; public_functions_after text; sales_before text; sales_after text;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
 -- No direct client call is added by this pure private helper.
 IF EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
  WHERE has_function_privilege(role_name,'pdc_sales_private.source_vin(jsonb)','EXECUTE')) THEN RAISE EXCEPTION 'Private VIN helper has client access'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) acl
  WHERE p.oid='pdc_sales_private.source_vin(jsonb)'::regprocedure AND acl.grantee<>p.proowner) THEN RAISE EXCEPTION 'Private VIN helper has a non-owner grant'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='pdc_sales_private.visibility_source_snapshot(boolean)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'Snapshot ACL changed'; END IF;
 IF has_function_privilege('anon','public.get_broome_sales_snapshot()','EXECUTE') OR has_table_privilege('authenticated','pdc_sales_private.tracked_orders','SELECT') THEN RAISE EXCEPTION 'Existing client boundaries expanded'; END IF;
 FOR test_case IN SELECT * FROM (VALUES
  ('full VIN',jsonb_build_object('vin',vin_a),vin_a),
  ('null component keys',jsonb_build_object('vin',vin_a,'wmi',null,'vdsNumber',null,'frame',null),vin_a),
  ('empty component keys',jsonb_build_object('vin',vin_a,'wmi','','vdsNumber','','frame',''),vin_a),
  ('partial components',jsonb_build_object('vin',vin_a,'wmi','MR0','vdsNumber',null,'frame',null),vin_a),
  ('normalization only',jsonb_build_object('vin',' mr0 rebhvx-00541949 '),vin_a),
  ('explicit fullVin',jsonb_build_object('fullVin',vin_b,'wmi',null),vin_b),
  ('explicit frameVin',jsonb_build_object('frameVin',vin_b,'frame',null),vin_b),
  ('valid alternate field after invalid VIN',jsonb_build_object('vin','invalid','fullVin',vin_b,'wmi',null),vin_b),
  ('explicit priority with conflicting complete components',jsonb_build_object('vin',vin_b,'wmi','MR0','vdsNumber','REBHVX','frame','00541949'),vin_b),
  ('existing complete component fallback',jsonb_build_object('wmi','MR0','vdsNumber','REBHVX','frame','00541949'),vin_a),
  ('invalid explicit with valid components',jsonb_build_object('vin','invalid','wmi','MR0','vdsNumber','REBHVX','frame','00541949'),vin_a),
  ('no VIN evidence','{}'::jsonb,NULL::text),
  ('null payload',NULL::jsonb,NULL::text),
  ('partial VIN',jsonb_build_object('wmi','MR0'),NULL::text),
  ('short explicit VIN',jsonb_build_object('vin','MR0REBHVX'),NULL::text),
  ('forbidden letter',jsonb_build_object('vin','MR0REBHVX0054I949'),NULL::text),
  ('ZPL text is not a VIN',jsonb_build_object('vin','^XA^FD'||vin_a||'^FS'),NULL::text),
  ('punctuation is not silently stripped',jsonb_build_object('vin','MR0REBHVX0054194!9'),NULL::text),
  ('object is not a VIN',jsonb_build_object('vin',jsonb_build_object('payload',vin_a)),NULL::text),
  ('raw header guesses are not used',jsonb_build_object('navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','VIN','value',vin_a)))),NULL::text)
 ) cases(name,payload,expected) LOOP
  IF pdc_sales_private.source_vin(test_case.payload) IS DISTINCT FROM test_case.expected THEN RAISE EXCEPTION 'VIN case failed: %',test_case.name; END IF;
 END LOOP;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 SELECT * INTO canonical FROM public.vehicles WHERE deleted_at IS NULL AND public.is_valid_vehicle_vin(vin) LIMIT 1;
 SELECT n.* INTO source_row FROM public.navision_backend_records n JOIN public.navision_import_batches b ON b.id=n.last_seen_batch_id
 WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND n.canonical_vehicle_id IS NULL AND n.is_current AND n.record_status='current'
 AND b.id=(SELECT id FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1)
 AND n.first_seen_batch_id<>n.last_seen_batch_id LIMIT 1;
 SELECT * INTO second_row FROM public.navision_backend_records WHERE source_system='microsoft_navision' AND dealer_code='37047' AND canonical_vehicle_id IS NULL AND is_current AND record_status='current' AND last_seen_batch_id=source_row.last_seen_batch_id AND id<>source_row.id LIMIT 1;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL OR canonical.id IS NULL OR source_row.id IS NULL OR second_row.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.salespeople WHERE code='CW' AND active) THEN RAISE EXCEPTION 'Missing controlled rollback fixtures'; END IF;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.vehicle_parts_updates p),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO op_before;
 SELECT md5(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text)::text) INTO public_functions_before
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('pdc_navision_effective_vin_471','pdc_navision_complete_vin_20260907','normalize_vehicle_vin','is_valid_vehicle_vin','navision_original_column_value','get_broome_sales_snapshot');
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM pdc_sales_private.tracked_orders o),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY tracking_id) FROM pdc_sales_private.ordering_progress p),
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY tracking_id) FROM pdc_sales_private.vehicle_visibility v),
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM public.pdc_user_roles r))::text) INTO sales_before;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  UPDATE public.navision_backend_records SET normalized_data=jsonb_build_object('order','SALES-VIN-PROOF-20261003','stock','','batch','','cosi','Yes','consultant','BG','vin',vin_a,'wmi',null,'vdsNumber',null,'frame',null),canonical_vehicle_id=NULL WHERE id=source_row.id;
  INSERT INTO pdc_sales_private.vehicle_visibility(tracking_id,dealer_code,order_key,hidden,changed_by) VALUES(source_row.id,'37047','SALES-VIN-PROOF-20261003',false,actor.auth_user_id)
  ON CONFLICT(tracking_id) DO UPDATE SET order_key=excluded.order_key,hidden=false;
  snap:=public.get_broome_sales_snapshot();
  SELECT e INTO item FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_row.id::text;
  IF item IS NULL OR item->>'vin' IS DISTINCT FROM vin_a OR item->>'stock' IS DISTINCT FROM '' OR item->>'canonical_vehicle_id' IS NOT NULL THEN RAISE EXCEPTION 'Stockless explicit VIN/null parts not projected without inventing a canonical link'; END IF;
  -- No current latest Broome row has a valid canonical VIN fixture. Execute the exact
  -- snapshot projection clause read-only, rather than attaching a stockless source
  -- and invoking the protected operational link/synchronisation trigger.
  vin_expression:=substring(pg_get_functiondef('pdc_sales_private.visibility_source_snapshot(boolean)'::regprocedure)
   FROM '''vin'',(CASE WHEN public[.]is_valid_vehicle_vin[(]v[.]vin[)] THEN v[.]vin ELSE pdc_sales_private[.]source_vin[(]n[.]normalized_data[)] END),');
  IF vin_expression IS NULL THEN RAISE EXCEPTION 'Expected actual canonical-first snapshot projection not found'; END IF;
  EXECUTE 'SELECT '||vin_expression||' FROM (SELECT $1::text AS vin) v CROSS JOIN (SELECT $2::jsonb AS normalized_data) n'
   INTO projected_vin USING canonical.vin,jsonb_build_object('vin',CASE WHEN canonical.vin=vin_a THEN vin_b ELSE vin_a END,'wmi',null,'vdsNumber',null,'frame',null);
  IF projected_vin IS DISTINCT FROM canonical.vin THEN RAISE EXCEPTION 'Canonical VIN priority over conflicting source VIN changed'; END IF;
  EXECUTE 'SELECT '||vin_expression||' FROM (SELECT $1::text AS vin) v CROSS JOIN (SELECT $2::jsonb AS normalized_data) n'
   INTO projected_vin USING canonical.vin,jsonb_build_object('wmi',null,'vdsNumber',null,'frame',null);
  IF projected_vin IS DISTINCT FROM canonical.vin THEN RAISE EXCEPTION 'Canonical VIN priority with missing source VIN changed'; END IF;
  -- A same-order ambiguity never borrows the other row VIN or invents a PMB link.
  UPDATE public.navision_backend_records SET normalized_data=jsonb_build_object('order','SALES-VIN-PROOF-20261003','stock','EXAMPLE-CW','batch','EXAMPLE-CW','cosi','Yes','consultant','CW','vin',vin_b,'wmi',null,'vdsNumber',null,'frame',null) WHERE id=second_row.id;
  snap:=pdc_sales_private.visibility_source_snapshot(NULL);
  SELECT e INTO item FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_row.id::text;
  IF item IS NULL OR item->>'vin' IS DISTINCT FROM vin_a OR item->>'identity_conflict' IS DISTINCT FROM 'true' OR item->>'canonical_vehicle_id' IS NOT NULL THEN RAISE EXCEPTION 'Ambiguous source borrowed a VIN or canonical identity'; END IF;
  SELECT e INTO item FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=second_row.id::text;
  IF item IS NULL OR item->>'vin' IS DISTINCT FROM vin_b OR item->>'canonical_vehicle_id' IS NOT NULL THEN RAISE EXCEPTION 'Second source VIN was mixed with first'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{order}','"SALES-VIN-PROOF-CW-20261003"') WHERE id=second_row.id;
  UPDATE pdc_sales_private.vehicle_visibility SET hidden=true WHERE tracking_id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'navision_record_id'=source_row.id::text) THEN RAISE EXCEPTION 'VIN fix exposed a hidden vehicle'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_sales_private.visibility_source_snapshot(true)->'items') e WHERE e->>'navision_record_id'=source_row.id::text AND e->>'vin'=vin_a) THEN RAISE EXCEPTION 'Authorized hidden snapshot lost VIN'; END IF;
  UPDATE pdc_sales_private.vehicle_visibility SET hidden=false WHERE tracking_id=source_row.id;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{cosi}','"No"') WHERE id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'navision_record_id'=source_row.id::text) THEN RAISE EXCEPTION 'VIN fix exposed a non-COSI order'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{cosi}','"Yes"'),is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=last_seen_batch_id WHERE id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'navision_record_id'=source_row.id::text) THEN RAISE EXCEPTION 'VIN fix exposed a non-current source'; END IF;
  UPDATE public.navision_backend_records SET is_current=true,record_status='current',missing_since_batch_id=NULL,last_seen_batch_id=source_row.first_seen_batch_id WHERE id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'navision_record_id'=source_row.id::text) THEN RAISE EXCEPTION 'VIN fix exposed an older dealer snapshot'; END IF;
  UPDATE public.navision_backend_records SET last_seen_batch_id=source_row.last_seen_batch_id WHERE id=source_row.id;
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  snap:=public.get_broome_sales_snapshot();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_row.id::text AND e->>'vin'=vin_a AND e->>'salesperson_code'='BG') THEN RAISE EXCEPTION 'Own salesperson explicit VIN missing'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=second_row.id::text OR e->>'salesperson_code' IS DISTINCT FROM 'BG') THEN RAISE EXCEPTION 'VIN fix widened salesperson scope'; END IF;
  UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=viewer.id;
  denied:=false;BEGIN dummy:=public.get_broome_sales_snapshot();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Disabled account could read VIN'; END IF;
  RAISE EXCEPTION 'Rollback successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.vehicle_parts_updates p),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO op_after;
 IF op_after IS DISTINCT FROM op_before THEN RAISE EXCEPTION 'PDC/source/bookings/parts/batch rollback fingerprint changed'; END IF;
 SELECT md5(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text)::text) INTO public_functions_after
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('pdc_navision_effective_vin_471','pdc_navision_complete_vin_20260907','normalize_vehicle_vin','is_valid_vehicle_vin','navision_original_column_value','get_broome_sales_snapshot');
 IF public_functions_after IS DISTINCT FROM public_functions_before THEN RAISE EXCEPTION 'Shared PDC helper/ACL fingerprint changed'; END IF;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM pdc_sales_private.tracked_orders o),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY tracking_id) FROM pdc_sales_private.ordering_progress p),
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY tracking_id) FROM pdc_sales_private.vehicle_visibility v),
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM public.pdc_user_roles r))::text) INTO sales_after;
 IF sales_after IS DISTINCT FROM sales_before THEN RAISE EXCEPTION 'Private sales/account rollback fingerprint changed'; END IF;
END $test$;
SELECT 'Explicit VIN/null-part preservation, component fallback, canonical priority, current-source/COSI/hidden/own-salesperson boundaries, owner-only helper, unchanged public helpers and PDC fingerprints passed; all fixtures rolled back' AS verification;
ROLLBACK;

