BEGIN;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 n public.navision_backend_records; target uuid; snap jsonb; row_data jsonb; before_hash text; fixture_hash text; after_hash text; denied boolean;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE active AND code='BG';
 SELECT * INTO n FROM public.navision_backend_records WHERE dealer_code='37047' AND is_current AND canonical_vehicle_id IS NULL LIMIT 1;
 SELECT v.id INTO target FROM public.vehicles v WHERE v.deleted_at IS NULL AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status<>'deleted' AND NOT coalesce(b.legacy_ambiguity_quarantined,false)) LIMIT 1;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL OR n.id IS NULL OR target IS NULL THEN RAISE EXCEPTION 'Missing fixtures'; END IF;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(ns) ORDER BY id) FROM public.navision_backend_records ns),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.vehicle_parts_updates u))::text) INTO before_hash;
 BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=last_seen_batch_id,canonical_vehicle_id=target,updated_at=clock_timestamp()+interval '1 day',normalized_data=jsonb_build_object('order','PMB-DETAIL-TEST','consultant','BG','batch',(SELECT stock_number FROM public.vehicles WHERE id=target)) WHERE id=n.id;
 UPDATE public.vehicles SET salesperson_manual_override=false WHERE id=target;
 INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
 VALUES(target,true,true,false,true,'Example parts delay','2026-10-07',actor.auth_user_id,clock_timestamp()+interval '1 day');
 UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
 PERFORM public.assign_broome_sales_access(viewer.id,person.id);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(ns) ORDER BY id) FROM public.navision_backend_records ns),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.vehicle_parts_updates u))::text) INTO fixture_hash;
 snap:=public.get_broome_sales_snapshot();
 SELECT e INTO row_data FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=n.id::text;
 IF row_data IS NULL OR row_data->>'canonical_vehicle_id'<>target::text THEN RAISE EXCEPTION 'Exact canonical projection missing'; END IF;
 IF row_data->'parts'->>'eta'<>'2026-10-07' OR row_data->'parts'->>'stoppage_reason'<>'Example parts delay' OR row_data->'parts'->>'received'<>'false' THEN RAISE EXCEPTION 'Latest parts update missing'; END IF;
 IF jsonb_array_length(row_data->'bay_bookings')<>(SELECT count(*) FROM public.workshop_bookings b WHERE b.vehicle_id=target AND b.deleted_at IS NULL AND b.status<>'deleted' AND NOT coalesce(b.legacy_ambiguity_quarantined,false)) THEN RAISE EXCEPTION 'Booking scope mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(row_data->'bay_bookings') b WHERE b ? 'metadata' OR b ? 'technician_id' OR NOT(b ? 'actual_start_at') OR NOT(b ? 'stoppage_reason') OR NOT(b ? 'progress')) THEN RAISE EXCEPTION 'Booking projection unsafe or incomplete'; END IF;
 IF row_data->'parts' ? 'updated_by' OR row_data->'parts' ? 'confirmed_by' OR row_data->'parts' ? 'operations' THEN RAISE EXCEPTION 'Private parts identity leaked'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code'<>'BG') OR public.is_pdc_role('viewer') OR public.is_pdc_role('operator') THEN RAISE EXCEPTION 'Sales access widened'; END IF;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(ns) ORDER BY id) FROM public.navision_backend_records ns),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.vehicle_parts_updates u))::text) INTO after_hash;
 IF fixture_hash<>after_hash THEN RAISE EXCEPTION 'Read changed PDC records'; END IF;
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=viewer.id;
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled account can read'; END IF;
 RAISE EXCEPTION 'Rollback successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(ns) ORDER BY id) FROM public.navision_backend_records ns),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.vehicle_parts_updates u))::text) INTO after_hash;
 IF before_hash<>after_hash THEN RAISE EXCEPTION 'Fixtures persisted'; END IF;
 IF has_function_privilege('anon','public.get_broome_sales_snapshot()','EXECUTE') THEN RAISE EXCEPTION 'Anonymous access'; END IF;
END $test$;
SELECT 'Exact scoped PMB bookings/latest parts, private-field filtering, disabled/anonymous denial and unchanged PDC fingerprints passed; rolled back' AS verification;
ROLLBACK;
