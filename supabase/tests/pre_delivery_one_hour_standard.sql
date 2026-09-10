BEGIN;

CREATE TEMP TABLE pd_before_ops AS SELECT o.operation_id,o.vehicle_id,o.operation_description,o.source_estimated_hours,o.semantic_hash,o.raw_evidence_id,to_jsonb(o) raw FROM public.pdc_pilbara_service_operations o;
CREATE TEMP TABLE pd_before_lines AS SELECT v.id,public.pdc_qc_operation_lines_379(v.id) lines FROM public.vehicles v WHERE EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id);
CREATE TEMP TABLE pd_before_receipts AS SELECT batch_id,to_jsonb(b) raw FROM public.pdc_pilbara_service_import_batches b WHERE batch_kind='apply';

DO $test$
#variable_conflict use_column
DECLARE d text; h numeric; v record; l jsonb; before_line jsonb; actor record; snapshot jsonb; review jsonb; target uuid;
BEGIN
 FOREACH d IN ARRAY ARRAY['Pre-Delivery (Commercial)','Pre Delivery Passenger','PREDELIVERY','Complete pre-delivery inspection','PDI','Pre–Delivery','Pre-delivery (Bus 4x4)'] LOOP
  FOREACH h IN ARRAY ARRAY[0::numeric,1.5,2.5,null] LOOP
   IF public.pdc_standard_operation_hours_20260910(d,h) IS DISTINCT FROM 1::numeric THEN RAISE EXCEPTION 'PD standard failed: % %',d,h; END IF;
  END LOOP;
 END LOOP;
 IF public.pdc_standard_operation_hours_20260910('Complimentary fuel',0) IS DISTINCT FROM 0::numeric
 OR public.pdc_standard_operation_hours_20260910('Battery isolator',2.5) IS DISTINCT FROM 2.5::numeric
 OR public.pdc_standard_operation_hours_20260910('Tray ordered',null) IS NOT NULL
 OR public.pdc_is_pre_delivery_20260910('Delivery charge') THEN RAISE EXCEPTION 'Non-PD hours changed'; END IF;
 FOR v IN SELECT * FROM pd_before_lines LOOP
  FOR l IN SELECT value FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) LOOP
   IF public.pdc_is_pre_delivery_20260910(l->>'description') THEN
    IF (l->>'estimated_hours')::numeric IS DISTINCT FROM 1::numeric THEN RAISE EXCEPTION 'Live PD hours mismatch'; END IF;
    IF l->>'department'='138' AND l->>'stage_code'<>'BUS_4X4' THEN RAISE EXCEPTION 'Dept138 mismatch'; END IF;
   ELSE
    SELECT value INTO before_line FROM jsonb_array_elements(v.lines) WHERE value->>'line_identity'=l->>'line_identity';
    IF l IS DISTINCT FROM before_line THEN RAISE EXCEPTION 'Unrelated line changed: %',l->>'line_identity'; END IF;
   END IF;
  END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pd_before_ops b JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE b.raw IS DISTINCT FROM to_jsonb(o))
 OR EXISTS(SELECT 1 FROM pd_before_receipts b JOIN public.pdc_pilbara_service_import_batches a USING(batch_id) WHERE b.raw IS DISTINCT FROM to_jsonb(a))
 THEN RAISE EXCEPTION 'Immutable source or receipts changed'; END IF;
 SELECT id INTO target FROM public.vehicles WHERE stock_number='13070889' AND deleted_at IS NULL;
 IF target IS NOT NULL THEN
  review:=public.pdc_new_vehicle_review_row(target);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(review->'operations') l WHERE public.pdc_is_pre_delivery_20260910(l->>'description') AND l->>'stage_code'='FITTING' AND (l->>'estimated_hours')::numeric=1)
  THEN RAISE EXCEPTION 'Screenshot vehicle not corrected'; END IF;
  IF public.workshop_vehicle_stage_estimated_hours(target,'FITTING')<1 THEN RAISE EXCEPTION 'Planner hours not corrected'; END IF;
 END IF;
 SELECT auth_user_id,email INTO actor FROM public.pdc_user_roles WHERE active AND role='administrator' AND account_status='approved' LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 snapshot:=public.get_pdc_email_vehicle_location_snapshot();
 IF snapshot->>'ok'<>'true' THEN RAISE EXCEPTION 'Snapshot failed: %',snapshot->>'code'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snapshot#>'{data,vehicles}') v, jsonb_array_elements(v->'operation_lines') l WHERE public.pdc_is_pre_delivery_20260910(l->>'description') AND (l->>'estimated_hours')::numeric IS DISTINCT FROM 1)
 THEN RAISE EXCEPTION 'Board snapshot PD mismatch'; END IF;
 snapshot:=public.list_pdc_unidentified_tune_reviews(0,100);
 IF snapshot->>'ok'<>'true' THEN RAISE EXCEPTION 'Unidentified read failed'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snapshot#>'{data,items}') g,jsonb_array_elements(g->'operations') l WHERE public.pdc_is_pre_delivery_20260910(l->>'description') AND (l->>'hours')::numeric IS DISTINCT FROM 1)
 THEN RAISE EXCEPTION 'Unidentified PD mismatch'; END IF;
END $test$;
SELECT 'PASS: PD variations, zero/nonzero/missing hours, source preservation, non-PD unchanged, live review, planner, board snapshot and unidentified review' result;

ROLLBACK;

