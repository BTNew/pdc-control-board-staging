-- Isolated sales flags must never write PDC, Navision, import or booking records.
BEGIN;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 own_id uuid; other_id uuid; snap jsonb; result jsonb; expected integer:=0; field text; denied boolean;
 public_before text; public_after text; progress_before text;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL THEN RAISE EXCEPTION 'Missing rollback fixtures'; END IF;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO public_before;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY tracking_id),'[]'::jsonb)::text) INTO progress_before FROM pdc_sales_private.ordering_progress p;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  snap:=public.get_broome_sales_snapshot();
  SELECT (e->>'tracking_id')::uuid INTO own_id FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code'='BG' AND e->>'ordering_version'='0' AND e->>'identity_conflict'='false' LIMIT 1;
  SELECT (e->>'tracking_id')::uuid INTO other_id FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code'<>'BG' LIMIT 1;
  IF own_id IS NULL OR other_id IS NULL THEN RAISE EXCEPTION 'Missing scoped order fixtures'; END IF;
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  result:=public.set_broome_sales_ordering_flag(own_id,'tint',true,0);
  IF result->>'tint'<>'true' OR result->>'build_po'<>'false' OR result->>'ordering_version'<>'1' THEN RAISE EXCEPTION 'Initial tick did not isolate field'; END IF;
  result:=public.set_broome_sales_ordering_flag(own_id,'tint',false,1);
  IF result->>'tint'<>'false' THEN RAISE EXCEPTION 'Untick failed'; END IF;
  expected:=2;
  FOREACH field IN ARRAY ARRAY['tint','build_po','build_complete','tray_ordered','tray_complete'] LOOP
   result:=public.set_broome_sales_ordering_flag(own_id,field,true,expected);expected:=expected+1;
   IF result->>field<>'true' OR (result->>'ordering_version')::integer<>expected THEN RAISE EXCEPTION 'Ordering field failed: %',field; END IF;
  END LOOP;
  snap:=public.get_broome_sales_snapshot();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=own_id::text AND e->>'tint'='true' AND e->>'build_po'='true' AND e->>'build_complete'='true' AND e->>'tray_ordered'='true' AND e->>'tray_complete'='true' AND (e->>'ordering_version')::integer=expected) THEN RAISE EXCEPTION 'Saved checklist not returned'; END IF;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(other_id,'tint',true,0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Cross salesperson write allowed'; END IF;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(own_id,'tint',false,0);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Stale update overwrote tick'; END IF;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(own_id,'current_location',true,expected);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Unapproved field writable'; END IF;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(gen_random_uuid(),'tint',true,0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Unknown order writable'; END IF;
  IF public.is_pdc_role('viewer') OR public.is_pdc_role('operator') THEN RAISE EXCEPTION 'PDC permission expanded'; END IF;
  IF has_table_privilege('authenticated','pdc_sales_private.ordering_progress','UPDATE') OR has_table_privilege('authenticated','pdc_sales_private.ordering_progress','SELECT') OR has_function_privilege('anon','public.set_broome_sales_ordering_flag(uuid,text,boolean,integer)','EXECUTE') THEN RAISE EXCEPTION 'Unsafe checklist permissions'; END IF;
  SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO public_after;
  IF public_after<>public_before THEN RAISE EXCEPTION 'Ordering ticks changed PDC/import/workshop records'; END IF;
  UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=viewer.id;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(own_id,'tint',false,expected);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Disabled account can save'; END IF;
  PERFORM set_config('request.jwt.claims','{}',true);
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(own_id,'tint',false,expected);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Signed-out account can save'; END IF;
  RAISE EXCEPTION 'Rollback successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO public_after;
 IF public_after<>public_before THEN RAISE EXCEPTION 'Public record rollback failed'; END IF;
 IF progress_before<>(SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress p) THEN RAISE EXCEPTION 'Checklist fixture rollback failed'; END IF;
END $test$;
SELECT 'Five ticks/untick, scoped write denial, stale-save protection and PDC/source/import/booking fingerprints passed; rolled back' AS verification;
ROLLBACK;
