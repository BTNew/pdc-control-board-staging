-- Owner-reviewed Department138 line routing. Private management workflow; no user impersonation.
-- Source operations, staff adjustments/hours, approvals, bookings and completion history are not rewritten.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379(uuid)'::regprocedure)<>'91a91511b2896591ecec202827490f20' THEN RAISE EXCEPTION 'category_projection_changed_since_review'; END IF;
END $guard$;

CREATE TABLE pdc_work_categories_private.owner_review_receipts(
 request_key text PRIMARY KEY,
 authority text NOT NULL,
 request_payload jsonb NOT NULL,
 result jsonb NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 database_actor text NOT NULL DEFAULT current_user
);
ALTER TABLE pdc_work_categories_private.owner_review_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.owner_review_receipts FROM PUBLIC,anon,authenticated;
CREATE TABLE pdc_work_categories_private.owner_line_reviews(
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 line_identity text NOT NULL,
 category text NOT NULL CHECK(category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET')),
 source_signature text NOT NULL,
 adjustment_signature text NOT NULL,
 before_line jsonb NOT NULL,
 reason text NOT NULL,
 request_key text NOT NULL REFERENCES pdc_work_categories_private.owner_review_receipts(request_key),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(vehicle_id,line_identity)
);
ALTER TABLE pdc_work_categories_private.owner_line_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.owner_line_reviews FROM PUBLIC,anon,authenticated;

CREATE FUNCTION pdc_work_categories_private.source_signature(line jsonb) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
 SELECT md5(jsonb_build_array(line->'line_identity',line->'description',line->'job_card_number',
 line->'department',line->'original_line_number')::text)
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.source_signature(jsonb) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION pdc_work_categories_private.adjustment_signature(adjustment jsonb) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN adjustment IS NULL THEN 'none' ELSE md5(jsonb_build_array(adjustment->'stage_code',
 adjustment->'manual_assignment_locked',adjustment->'description',adjustment->'operation_code',
 adjustment->'job_card_number',adjustment->'active')::text) END
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.adjustment_signature(jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH source AS MATERIALIZED(SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.base_pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY a(l,ord)),
 projected AS (SELECT l,ord,o.category override_category,o.version category_version,
   a.adjustment_id,a.manual_assignment_locked,a.stage_code saved_stage,r.category owner_reviewed_category,
   CASE WHEN l->>'department'='138' AND public.pdc_is_pre_delivery_20260910(l->>'description')
     THEN coalesce(a.estimated_hours,op.effective_estimated_hours,(l->>'estimated_hours')::numeric) ELSE (l->>'estimated_hours')::numeric END hours,
   pdc_work_categories_private.suggest(l) suggested,
   (SELECT b.work_category FROM public.workshop_bookings b
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.work_category IS NOT NULL
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category_scope ? (l->>'line_identity')
     ORDER BY (b.status<>'completed') DESC,b.created_at DESC LIMIT 1) booked_category,
   EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND s.code=l->>'stage_code'
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category IS NULL) protected_booking
 FROM source LEFT JOIN pdc_work_categories_private.line_overrides o ON o.vehicle_id=p_vehicle_id AND o.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 LEFT JOIN pdc_work_categories_private.owner_line_reviews r
 ON r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
 AND l->>'department'='138' AND r.source_signature=pdc_work_categories_private.source_signature(l)
 AND r.adjustment_signature=pdc_work_categories_private.adjustment_signature(to_jsonb(a))
 LEFT JOIN public.pdc_pilbara_service_operations op ON op.vehicle_id=p_vehicle_id AND 'source:'||op.operation_id::text=l->>'line_identity'),
 chosen AS (SELECT *,coalesce(override_category,booked_category,owner_reviewed_category,CASE
 WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW' THEN l->>'stage_code'
 WHEN l->>'stage_code'='BUS_4X4' THEN CASE WHEN suggested LIKE 'BUS_%' AND suggested<>'BUS_PIT' THEN suggested ELSE CASE WHEN protected_booking OR coalesce(manual_assignment_locked,false) THEN 'BUS_MECHANICAL' ELSE suggested END END
 WHEN protected_booking OR coalesce(manual_assignment_locked,false) OR l->>'department' IS DISTINCT FROM '138' THEN l->>'stage_code'
 ELSE suggested END) category FROM projected)
 SELECT coalesce(jsonb_agg(l||jsonb_build_object('work_category',category,'category_version',coalesce(category_version,0),
 'stage_code',pdc_work_categories_private.stage(category),'estimated_hours',hours,
 'zero_hour_task',category='BUS_QA' AND hours=0,
 'category_rule','craig_jobcard_categories_20261015') ORDER BY ord),'[]'::jsonb) FROM chosen
$function$;


CREATE FUNCTION pdc_work_categories_private.apply_owner_review(request_key text,authority text,rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
DECLARE x jsonb; vid uuid; current_line jsonb; raw_line jsonb; v public.vehicles;
 target text; outcome text; results jsonb:='[]'; previous pdc_work_categories_private.owner_review_receipts;
 adjustment_signature text; changed_ids uuid[]:='{}'; before_bookings text; before_adjustments text; before_operations text;
 before_completed jsonb; after_completed jsonb; review_result jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection()
 OR coalesce(auth.uid()::text,'')<>'' THEN RAISE EXCEPTION 'management_connection_without_user_impersonation_required'; END IF;
 IF length(request_key)<20 OR length(authority)<40 OR jsonb_typeof(rows)<>'array' OR jsonb_array_length(rows)>2000 THEN RAISE EXCEPTION 'review_manifest_required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO previous FROM pdc_work_categories_private.owner_review_receipts r WHERE r.request_key=apply_owner_review.request_key;
 IF FOUND THEN
  IF previous.request_payload IS DISTINCT FROM rows OR previous.authority IS DISTINCT FROM authority THEN RAISE EXCEPTION 'idempotency_intent_mismatch'; END IF;
  RETURN previous.result||jsonb_build_object('replay',true);
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(rows) j GROUP BY j->>'vehicle_id',j->'expected_line'->>'line_identity' HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate_line_identity'; END IF;
 PERFORM 1 FROM public.vehicles WHERE id IN(SELECT (j->>'vehicle_id')::uuid FROM jsonb_array_elements(rows) j) ORDER BY id FOR UPDATE;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id)::text,'[]')) INTO before_bookings FROM public.workshop_bookings b;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.adjustment_id)::text,'[]')) INTO before_adjustments FROM public.vehicle_workshop_line_adjustments a;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id)::text,'[]')) INTO before_operations FROM public.pdc_pilbara_service_operations o;
 SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY w.vehicle_id,w.work_key),'[]') INTO before_completed FROM public.vehicle_work_items w WHERE completed;
 INSERT INTO pdc_work_categories_private.owner_review_receipts(request_key,authority,request_payload,result)
 VALUES(request_key,authority,rows,'{}');
 FOR x IN SELECT value FROM jsonb_array_elements(rows) LOOP
  vid:=(x->>'vehicle_id')::uuid; outcome:=NULL; current_line:=NULL; raw_line:=NULL;
  SELECT * INTO v FROM public.vehicles WHERE id=vid;
  IF v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' THEN RAISE EXCEPTION 'inactive_vehicle'; END IF;
  IF v.stock_number IS DISTINCT FROM x->>'stock' OR v.version IS DISTINCT FROM (x->>'vehicle_version')::integer THEN RAISE EXCEPTION 'vehicle_identity_or_version_changed'; END IF;
  SELECT l INTO current_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vid)) l WHERE l->>'line_identity'=x->'expected_line'->>'line_identity';
  IF current_line IS DISTINCT FROM x->'expected_line' OR current_line->>'department' IS DISTINCT FROM '138' THEN RAISE EXCEPTION 'exact_department138_line_changed'; END IF;
  IF x->>'category' IS NULL THEN outcome:='held_no_workshop_category';
  ELSIF x->>'category' NOT IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET') THEN RAISE EXCEPTION 'invalid_department138_category';
  ELSIF current_line->>'work_category'=x->>'category' THEN outcome:='unchanged';
  ELSIF NOT coalesce((current_line->>'active')::boolean,true) OR coalesce((current_line->>'completed')::boolean,false) OR coalesce((current_line->>'rejected')::boolean,false) THEN outcome:='held_history';
  ELSIF coalesce((current_line->>'category_version')::integer,0)>0 THEN outcome:='held_explicit_category_override';
  ELSIF EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=vid AND w.completed AND s.code=current_line->>'stage_code') THEN outcome:='held_completed_stage';
  ELSE
   target:=pdc_work_categories_private.stage(x->>'category');
   IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.vehicle_id=vid AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
    AND ((b.work_category IS NOT NULL AND b.work_category_scope ? (current_line->>'line_identity'))
     OR (b.work_category IS NULL AND s.code IN(current_line->>'stage_code',target)
      AND (target IS DISTINCT FROM current_line->>'stage_code' OR b.status IN('started','stoppage','completed'))))) THEN outcome:='held_booking_scope';
   END IF;
  END IF;
  IF outcome IS NULL THEN
   SELECT l INTO raw_line FROM jsonb_array_elements(pdc_work_categories_private.base_pdc_qc_operation_lines_379(vid)) l WHERE l->>'line_identity'=current_line->>'line_identity';
   IF raw_line IS NULL THEN RAISE EXCEPTION 'original_line_missing'; END IF;
   SELECT pdc_work_categories_private.adjustment_signature(to_jsonb(a)) INTO adjustment_signature FROM public.vehicle_workshop_line_adjustments a
    WHERE a.vehicle_id=vid AND a.line_key=current_line->>'line_identity';
   INSERT INTO pdc_work_categories_private.owner_line_reviews(vehicle_id,line_identity,category,source_signature,adjustment_signature,before_line,reason,request_key)
   VALUES(vid,current_line->>'line_identity',x->>'category',pdc_work_categories_private.source_signature(raw_line),
    coalesce(adjustment_signature,'none'),current_line,x->>'reason',request_key);
   changed_ids:=array_append(changed_ids,vid);outcome:='category_applied';
  END IF;
  results:=results||jsonb_build_array(jsonb_build_object('vehicle_id',vid,'stock',v.stock_number,
   'line_identity',current_line->>'line_identity','job',current_line->>'job_card_number','before_category',current_line->>'work_category',
   'requested_category',x->>'category','outcome',outcome));
 END LOOP;
 IF cardinality(changed_ids)>0 THEN
  PERFORM public.pdc_auditor_recalculate_required_work_226(changed_ids);
  PERFORM public.workshop_bump_revision();
 END IF;
 IF before_bookings IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id)::text,'[]')) FROM public.workshop_bookings b)
 OR before_adjustments IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.adjustment_id)::text,'[]')) FROM public.vehicle_workshop_line_adjustments a)
 OR before_operations IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY o.operation_id)::text,'[]')) FROM public.pdc_pilbara_service_operations o)
 THEN RAISE EXCEPTION 'source_staff_or_bookings_changed'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY w.vehicle_id,w.work_key),'[]') INTO after_completed FROM public.vehicle_work_items w WHERE completed;
 IF before_completed IS DISTINCT FROM after_completed THEN RAISE EXCEPTION 'completed_history_changed'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(rows) LOOP
  SELECT l INTO current_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379((x->>'vehicle_id')::uuid)) l
   WHERE l->>'line_identity'=x->'expected_line'->>'line_identity';
  IF current_line - ARRAY['work_category','stage_code','zero_hour_task'] IS DISTINCT FROM (x->'expected_line') - ARRAY['work_category','stage_code','zero_hour_task']
  THEN RAISE EXCEPTION 'non_category_line_fields_changed'; END IF;
 END LOOP;
 review_result:=jsonb_build_object('ok',true,'replay',false,'outcomes',results,'source_hours_staff_bookings_completed_preserved',true);
 UPDATE pdc_work_categories_private.owner_review_receipts r SET result=review_result WHERE r.request_key=apply_owner_review.request_key;
 RETURN review_result;
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.apply_owner_review(text,text,jsonb) FROM PUBLIC,anon,authenticated;

