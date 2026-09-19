-- Read-only department filters. Existing list/approval RPCs and planner scope stay unchanged.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Department filter migration is staging only'; END IF;
END $guard$;

-- Same active source sets and exact vehicle/stock binding as pdc_qc_operation_lines_379.
-- No classifier, bay, default department, source-history scan, or frontend line cap.
CREATE FUNCTION public.pdc_vehicle_department_membership_20260919(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
 WITH departments AS (
  SELECT nullif(btrim(o.department),'') department
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.vehicle_workshop_line_adjustments a
   ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id AND coalesce(a.active,true)
  UNION ALL
  SELECT NULL::text FROM public.pdc_authenticated_email_operation_lines o
  JOIN public.vehicles v ON v.id=o.vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a
   ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_line_id::text
  WHERE o.vehicle_id=p_vehicle_id AND coalesce(a.active,true)
  UNION ALL
  SELECT NULL::text FROM public.vehicle_workshop_line_adjustments a
  JOIN public.vehicles v ON v.id=a.vehicle_id
  WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual' AND a.active
 )
 SELECT jsonb_build_object(
  'department_codes',coalesce(jsonb_agg(DISTINCT department ORDER BY department)
    FILTER(WHERE department IS NOT NULL),'[]'::jsonb),
  'has_unknown_department',count(*)=0 OR coalesce(bool_or(department IS NULL),false))
 FROM departments;
$fn$;

-- A changed line belongs to its affected source department(s), not every department
-- on its vehicle. A move across departments remains visible from either side.
CREATE FUNCTION public.pdc_change_department_membership_20260919(p_change public.pdc_tune_operation_change_reviews)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
 WITH departments AS (
  SELECT nullif(btrim(p_change.before_source->>'department'),'') department
  UNION ALL SELECT nullif(btrim(p_change.proposed_source->>'department'),'')
  UNION ALL SELECT nullif(btrim(o.department),'') FROM public.pdc_pilbara_service_operations o
   WHERE o.operation_id=p_change.source_operation_id AND o.vehicle_id=p_change.vehicle_id
 )
 SELECT jsonb_build_object(
  'department_codes',coalesce(jsonb_agg(DISTINCT department ORDER BY department)
   FILTER(WHERE department IS NOT NULL),'[]'::jsonb),
  'has_unknown_department',count(department)=0)
 FROM departments;
$fn$;

CREATE FUNCTION public.pdc_department_review_reader_20260919()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
 SELECT auth.uid() IS NOT NULL AND auth.role()='authenticated' AND EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
  AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
  AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'));
$fn$;
REVOKE ALL ON FUNCTION public.pdc_vehicle_department_membership_20260919(uuid),
 public.pdc_change_department_membership_20260919(public.pdc_tune_operation_change_reviews),
 public.pdc_department_review_reader_20260919() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.list_pdc_new_vehicle_reviews_by_department(
 p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE rows jsonb; total bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 WITH candidates AS MATERIALIZED (
  SELECT r.vehicle_id,r.received_at,public.pdc_vehicle_department_membership_20260919(r.vehicle_id) membership
  FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
 ), matching AS MATERIALIZED (
  SELECT * FROM candidates c WHERE scope_department IS NULL OR c.membership->'department_codes' ? scope_department
 ), page AS (
  SELECT * FROM matching ORDER BY received_at DESC,vehicle_id LIMIT p_limit OFFSET p_offset
 )
 SELECT (SELECT count(*) FROM matching),
  coalesce(jsonb_agg(public.pdc_new_vehicle_review_row(x.vehicle_id)||x.membership
   ORDER BY x.received_at DESC,x.vehicle_id),'[]'::jsonb) INTO total,rows FROM page x;
 RETURN jsonb_build_object('ok',true,'code','new_vehicle_reviews','data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total,'department',scope_department));
END $fn$;

CREATE FUNCTION public.list_pdc_tune_operation_changes_by_department(
 p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE rows jsonb; total bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 WITH candidates AS MATERIALIZED (
  SELECT r.change_id,r.created_at,public.pdc_change_department_membership_20260919(r) membership
  FROM public.pdc_tune_operation_change_reviews r WHERE r.status='pending'
 ), matching AS MATERIALIZED (
  SELECT * FROM candidates c WHERE scope_department IS NULL OR c.membership->'department_codes' ? scope_department
 ), page AS (
  SELECT * FROM matching ORDER BY created_at,change_id LIMIT p_limit OFFSET p_offset
 )
 SELECT (SELECT count(*) FROM matching),
  coalesce(jsonb_agg(public.pdc_tune_operation_change_row_20260912(x.change_id)||x.membership
   ORDER BY x.created_at,x.change_id),'[]'::jsonb) INTO total,rows FROM page x;
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total,'department',scope_department));
END $fn$;

CREATE FUNCTION public.list_pdc_unidentified_tune_reviews_by_department(
 p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE rows jsonb; total bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 WITH groups AS MATERIALIZED (
  SELECT r.workbook_sha256,r.repair_order_number,r.department FROM public.pdc_unidentified_tune_review r
  WHERE scope_department IS NULL OR btrim(r.department)=scope_department
  GROUP BY r.workbook_sha256,r.repair_order_number,r.department
 ), page AS (
  SELECT * FROM groups ORDER BY workbook_sha256,repair_order_number,department LIMIT p_limit OFFSET p_offset
 ), projected AS (
  SELECT g.workbook_sha256,g.repair_order_number,g.department,count(*) operation_count,
   sum(public.pdc_standard_operation_hours_20260910(r.operation_description,r.source_estimated_hours)) hours,
   jsonb_build_array(btrim(g.department)) department_codes,false has_unknown_department,
   jsonb_agg(jsonb_build_object('description',r.operation_description,'line',r.original_line_number,
    'source_estimated_hours',r.source_estimated_hours,
    'hours',public.pdc_standard_operation_hours_20260910(r.operation_description,r.source_estimated_hours),
    'station',r.proposed_station,'operation_code',r.operation_code)
    ORDER BY r.original_line_number,r.operation_identity_hash) operations
  FROM page g JOIN public.pdc_unidentified_tune_review r
   ON r.workbook_sha256=g.workbook_sha256 AND r.repair_order_number=g.repair_order_number AND r.department=g.department
  GROUP BY g.workbook_sha256,g.repair_order_number,g.department
 )
 SELECT (SELECT count(*) FROM groups),coalesce(jsonb_agg(to_jsonb(q)
   ORDER BY q.workbook_sha256,q.repair_order_number,q.department),'[]'::jsonb) INTO total,rows FROM projected q;
 RETURN jsonb_build_object('ok',true,'code','unidentified_tune_reviews','data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total,'department',scope_department));
END $fn$;

CREATE FUNCTION public.get_pdc_review_counts_by_department(p_department text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE vehicles_count bigint; changes_count bigint; unidentified_count bigint; scope_department text:=nullif(btrim(p_department),'');
BEGIN
 IF public.pdc_department_review_reader_20260919() IS NOT TRUE
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF scope_department IS NOT NULL AND scope_department NOT IN('138','139')
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_department'); END IF;
 SELECT count(*) INTO vehicles_count
 FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  AND (scope_department IS NULL OR public.pdc_vehicle_department_membership_20260919(r.vehicle_id)->'department_codes' ? scope_department);
 SELECT count(*) INTO changes_count FROM public.pdc_tune_operation_change_reviews r
 WHERE r.status='pending' AND (scope_department IS NULL OR public.pdc_change_department_membership_20260919(r)->'department_codes' ? scope_department);
 SELECT count(*) INTO unidentified_count FROM (
  SELECT r.workbook_sha256,r.repair_order_number,r.department FROM public.pdc_unidentified_tune_review r
  WHERE scope_department IS NULL OR btrim(r.department)=scope_department
  GROUP BY r.workbook_sha256,r.repair_order_number,r.department) x;
 RETURN jsonb_build_object('ok',true,'data',jsonb_build_object(
  'new_vehicles',vehicles_count,'operation_changes',changes_count,'unidentified',unidentified_count,'department',scope_department));
END $fn$;

REVOKE ALL ON FUNCTION public.list_pdc_new_vehicle_reviews_by_department(integer,integer,text),
 public.list_pdc_tune_operation_changes_by_department(integer,integer,text),
 public.list_pdc_unidentified_tune_reviews_by_department(integer,integer,text),
 public.get_pdc_review_counts_by_department(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_pdc_new_vehicle_reviews_by_department(integer,integer,text),
 public.list_pdc_tune_operation_changes_by_department(integer,integer,text),
 public.list_pdc_unidentified_tune_reviews_by_department(integer,integer,text),
 public.get_pdc_review_counts_by_department(text) TO authenticated;

-- Add uncapped membership to each already-authorized location row. Preserve the
-- existing function OID, ACL, role checks, payload and all combined planner data.
DO $snapshot$
DECLARE original text; revised text; needle text:='row_value||jsonb_build_object(';
BEGIN
 original:=pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure);
 IF md5(original)<>'3e9dc5ab93528a4167574b56f113e5cc'
 THEN RAISE EXCEPTION 'Location snapshot changed; reconcile department metadata before applying'; END IF;
 IF (length(original)-length(replace(original,needle,'')))/length(needle)<>1
 THEN RAISE EXCEPTION 'Location snapshot department anchor changed'; END IF;
 revised:=replace(original,needle,'row_value||public.pdc_vehicle_department_membership_20260919((row_value->>''id'')::uuid)||jsonb_build_object(');
 EXECUTE revised;
END $snapshot$;

NOTIFY pgrst,'reload schema';
