-- r412 undo: puts back the exact pre-r412 bodies (outer location function and the five helpers, LANGUAGE sql again),
-- removes the r412 pins and check. Run between :02 and :45 with lock_timeout 2s. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r412 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r412 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r412 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r412 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot()','930f0f56572db71445d7de704f027aa3'),
  ('public.pdc_imported_parts_flags_vehicle_20260912(uuid)','79dcb7e2b2eb795efb9e0d7b020dbaaa'),
  ('public.pdc_vehicle_department_membership_20260919(uuid)','98c1144e9c0207a29e753913f9f1e7eb'),
  ('pdc_codex_intake_private.vehicle_tune_checkout(uuid)','42da25784d87ac98c76c451d96a603a9'),
  ('pdc_codex_intake_private.vehicle_service_locations(uuid)','5c4eb58c5a462cc9f34da1a09a63d4a2'),
  ('pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)','81aa51172c34d120101e335dd10e6d2b')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>6 THEN RAISE EXCEPTION 'r412 undo: a function is not the r412 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_imported_parts_flags_vehicle_20260912(uuid)','{postgres=X/postgres,service_role=X/postgres}falses|search_path=pg_catalog, public, pdc_parts_private'),
  ('public.pdc_vehicle_department_membership_20260919(uuid)','{postgres=X/postgres}falses|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.vehicle_tune_checkout(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.vehicle_service_locations(uuid)','{postgres=X/postgres}falses|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u')<>6 THEN RAISE EXCEPTION 'r412 undo: owner, grants, security, volatility, strictness or search_path changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||public.pdc_vehicle_department_membership_20260919((row_value->>'id')::uuid)||jsonb_build_object(
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_build_object(
    'tune_checkout',pdc_codex_intake_private.vehicle_tune_checkout(canonical.id),'tune_service_locations',pdc_codex_intake_private.vehicle_service_locations(canonical.id),'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE dept138.station_code WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',dept138.station_code,'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN LATERAL (
     SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code
     WHERE btrim(op->>'department')='138'
   ) dept138 ON true
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',classified.operation_id,'department',classified.department,
      'operation_no','PD'||lpad(classified.original_line_number::text,3,'0')||'-'||upper(substr(classified.semantic_hash,1,8)),
      'work_key',CASE classified.station_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(classified.station_code) END,
      'job_card_number',classified.repair_order_number,'description',coalesce(classified.approved_source->>'operation_description',classified.operation_description),
      'estimated_hours',classified.effective_estimated_hours,
      'estimated_hours_source',CASE classified.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',classified.source_estimated_hours,'effective_estimated_hours',classified.effective_estimated_hours,
      'hours_provenance',classified.hours_provenance,'parts_on_backorder_raw',classified.parts_on_backorder_raw,'parts_semantics',classified.parts_semantics,
      'classification',classified.station_code,'classification_method',coalesce(classified.method,'review'),
      'classification_confidence',coalesce(classified.confidence,0),'classification_rationale',coalesce(classified.rationale,'No current classification; retained for Review.'),
      'source_description_hash',classified.source_description_hash,'classifier_version',classified.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||classified.stock_number||':'||classified.repair_order_number||':'||classified.original_line_number
    )) ORDER BY classified.source_order),'[]'::jsonb) service_lines
    FROM (
      SELECT sourced.*,
        CASE WHEN sourced.department='138' THEN pdc_bus_private.operation_station(sourced.operation_id)
             WHEN public.pdc_is_pre_delivery_20260910(coalesce(sourced.approved_source->>'operation_description',sourced.operation_description)) THEN 'FITTING'
             ELSE coalesce(sourced.category,sourced.proposed_station,'REVIEW') END AS station_code
      FROM (
        SELECT o.operation_id,o.department,o.original_line_number,o.semantic_hash,o.repair_order_number,o.operation_description,
          o.effective_estimated_hours,o.hours_provenance,o.source_estimated_hours,o.parts_on_backorder_raw,o.parts_semantics,
          o.proposed_station,o.stock_number,o.source_order,h.category,h.method,h.confidence,h.rationale,h.source_description_hash,h.classifier_version,
          public.pdc_tune_approved_operation_source_20260912(o.operation_id) AS approved_source
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
        LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
        WHERE o.vehicle_id=(row_value->>'id')::uuid
      ) sourced
    ) classified
  ) projected
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)
     OR canonical.lifecycle_state::text='completed';
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$;

-- public.pdc_imported_parts_flags_vehicle_20260912(uuid): old body has CRLF line endings; restored byte-exact from base64.
DO $b$ BEGIN
 EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcHVibGljLnBkY19pbXBvcnRlZF9wYXJ0c19mbGFnc192ZWhpY2xlXzIwMjYwOTEyKHBfdmVoaWNsZV9pZCB1dWlkKQogUkVUVVJOUyBqc29uYgogTEFOR1VBR0Ugc3FsCiBTVEFCTEUKIFNFVCBzZWFyY2hfcGF0aCBUTyAncGdfY2F0YWxvZycsICdwdWJsaWMnLCAncGRjX3BhcnRzX3ByaXZhdGUnCkFTICRmdW5jdGlvbiQNCiBXSVRIIGFjdGl2ZSBBUyAoDQogU0VMRUNUIGouKixwZGNfcGFydHNfcHJpdmF0ZS5qb2Jfc3RhdHVzKGopIHN0YXR1cyBGUk9NIHBkY19wYXJ0c19wcml2YXRlLmpvYnMgaiBKT0lOIHB1YmxpYy52ZWhpY2xlcyB2IE9OIHYuaWQ9ai52ZWhpY2xlX2lkDQogV0hFUkUgai52ZWhpY2xlX2lkPXBfdmVoaWNsZV9pZCBBTkQgai5jbG9zZWRfYXQgSVMgTlVMTCBBTkQgdi5kZWxldGVkX2F0IElTIE5VTEwgQU5EIHYubGlmZWN5Y2xlX3N0YXRlPSdhY3RpdmUnDQogQU5EIHYuYm9hcmRfcHVyZ2VkX2F0IElTIE5VTEwgQU5EIG51bGxpZihidHJpbSh2LnN0b2NrX251bWJlciksJycpIElTIE5PVCBOVUxMIEFORCBqLnN0b2NrX251bWJlcj1idHJpbSh2LnN0b2NrX251bWJlcikNCiApLCBzdW1tYXJ5IEFTICgNCiBTRUxFQ1QgY291bnQoKikgbixib29sX29yKGJhY2tvcmRlcj0xKSBvdXRzdGFuZGluZyxib29sX2FuZChzdGF0dXMtPj4nY29sb3VyJz0nZ3JlZW4nKSByZWFkeSwNCiBib29sX29yKHN0YXR1cy0+Pidjb2xvdXInPSdyZXZpZXcnKSB1bmtub3duLG1heChwYXJ0c19pbXBvcnRlZF9hdCkgaW1wb3J0ZWRfYXQsDQogbWF4KHBhcnRzX3NuYXBzaG90X2F0KSBzbmFwc2hvdF9hdCxqc29uYl9hZ2coc3RhdHVzIE9SREVSIEJZIHJvX251bWJlcixjb21wYW55LGRpdmlzaW9uKSBqb2JzIEZST00gYWN0aXZlDQogKSBTRUxFQ1QgQ0FTRSBXSEVOIG49MCBUSEVOIE5VTEwgRUxTRSBqc29uYl9idWlsZF9vYmplY3QoJ2ZlZWQnLCdzZXBhcmF0ZV9wYXJ0c19zdGF0dXMnLCdqb2JzJyxqb2JzLA0KICdjb2xvdXInLENBU0UgV0hFTiBvdXRzdGFuZGluZyBUSEVOICdvcmFuZ2UnIFdIRU4gcmVhZHkgVEhFTiAnZ3JlZW4nIFdIRU4gdW5rbm93biBUSEVOICdyZXZpZXcnIEVMU0UgJ2dyZXknIEVORCwNCiAnbGFiZWwnLENBU0UgV0hFTiBvdXRzdGFuZGluZyBUSEVOICdQYXJ0cyBvdXRzdGFuZGluZyDigJQgc2VlIGpvYiBjYXJkcycgV0hFTiByZWFkeSBUSEVOICdBbGwgYWN0aXZlIGpvYnMgcGFydHMtcmVhZHknDQogRUxTRSAnUGFydHMgcmVxdWlyZW1lbnRzIG5lZWQgcmV2aWV3JyBFTkQsJ3BhcnRzX2NvbXBsZXRlJyxjb2FsZXNjZShyZWFkeSxmYWxzZSksDQogJ2xhc3Rfc3VjY2Vzc2Z1bF9pbXBvcnRfYXQnLGltcG9ydGVkX2F0LCdwYXJ0c19zbmFwc2hvdF9hdCcsc25hcHNob3RfYXQsDQogJ2xhc3Rfc3VjY2Vzc2Z1bF9wYXJ0c19mZWVkX2ltcG9ydF9hdCcsKFNFTEVDVCBsYXN0X3N1Y2Nlc3NmdWxfaW1wb3J0X2F0IEZST00gcGRjX3BhcnRzX3ByaXZhdGUuc2V0dGluZ3MgV0hFUkUgc2luZ2xldG9uKSwNCiAnbWVhbmluZycsJ0VhY2ggYWN0aXZlIFIvTyBpcyBhc3Nlc3NlZCBzZXBhcmF0ZWx5LiBBIFBPIG1heSBjb3ZlciBvbmx5IHNvbWUgb3V0c3RhbmRpbmcgcGFydHMuIFJlY29yZGVkIGZsYWdzIGRvIG5vdCBpbmRlcGVuZGVudGx5IHZlcmlmeSBzdG9jayBhdmFpbGFiaWxpdHkuJywNCiAnb3BlcmF0aW9ucycsKFNFTEVDVCBjb2FsZXNjZShqc29uYl9vYmplY3RfYWdnKG8ub3BlcmF0aW9uX2lkOjp0ZXh0LGEuc3RhdHVzfHxqc29uYl9idWlsZF9vYmplY3QoJ2pvYl9sZXZlbCcsdHJ1ZSwNCiAnam9iX2xhYmVsJyxDQVNFIFdIRU4gYS5iYWNrb3JkZXI9MSBUSEVOICdKb2IgaGFzIG91dHN0YW5kaW5nIHBhcnRzJyBFTFNFICdKb2IgcGFydHMgc3RhdHVzIOKAlCBzZWUgUi9PJyBFTkQpKSwgJ3t9JykNCiBGUk9NIHB1YmxpYy5wZGNfcGlsYmFyYV9zZXJ2aWNlX29wZXJhdGlvbnMgbyBKT0lOIHB1YmxpYy5wZGNfcGlsYmFyYV9zZXJ2aWNlX2ltcG9ydF9yb3dzIHIgT04gci5ldmlkZW5jZV9pZD1vLnJhd19ldmlkZW5jZV9pZA0KIEpPSU4gYWN0aXZlIGEgT04gYS52ZWhpY2xlX2lkPW8udmVoaWNsZV9pZCBBTkQgYS5yb19udW1iZXI9by5yZXBhaXJfb3JkZXJfbnVtYmVyDQogQU5EIGEuY29tcGFueT0ocGRjX3BhcnRzX3ByaXZhdGUuc2VydmljZV9zY29wZShyLnJhd19yb3csci5zdG9ja19udW1iZXIsci5yZXBhaXJfb3JkZXJfbnVtYmVyKS0+Pidjb21wYW55JykgQU5EIGEuZGl2aXNpb249KHBkY19wYXJ0c19wcml2YXRlLnNlcnZpY2Vfc2NvcGUoci5yYXdfcm93LHIuc3RvY2tfbnVtYmVyLHIucmVwYWlyX29yZGVyX251bWJlciktPj4nZGl2aXNpb24nKSkpDQogRU5EIEZST00gc3VtbWFyeQ0KJGZ1bmN0aW9uJA==','base64'),'UTF8');
END $b$;

CREATE OR REPLACE FUNCTION public.pdc_vehicle_department_membership_20260919(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.vehicle_tune_checkout(vid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT jsonb_build_object('confirmed',true,'source','Tune Sub Status 99','snapshot_at',r.snapshot_at,
 'recorded_at',r.recorded_at,'job_cards',r.job_cards,'receipt_id',r.receipt_id)
 FROM pdc_codex_intake_private.tune_checkout_receipts r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.vehicle_id=vid AND v.source_payload->>'tune_checkout_receipt_id'=r.receipt_id::text
 AND upper(v.current_location) IN ('QC','RFT') AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
$function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.vehicle_service_locations(vid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
SELECT jsonb_build_object('source','Tune PD Service','jobs',coalesce(jsonb_agg(jsonb_build_object(
 'company',m.company,'division',m.division,'ro_number',m.ro_number,'parts_location',m.parts_location,
 'vehicle_key_number',m.vehicle_key_number,'snapshot_at',m.snapshot_at,'imported_at',m.imported_at) ORDER BY m.ro_number),'[]'::jsonb))
FROM pdc_codex_intake_private.service_location_fields m
JOIN pdc_parts_private.jobs j ON j.vehicle_id=m.vehicle_id AND j.company=m.company AND j.division=m.division AND j.ro_number=m.ro_number AND j.source_system='tune_pmg' AND j.closed_at IS NULL
WHERE m.vehicle_id=vid;
$function$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.owner_board_hold_active_20261019(p_vehicle_id uuid, p_stock text, p_backend_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
SELECT EXISTS(SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h
 WHERE h.released_at IS NULL AND ((p_vehicle_id IS NOT NULL AND h.vehicle_id=p_vehicle_id) OR (p_stock IS NOT NULL AND h.stock_number=p_stock) OR(p_backend_id IS NOT NULL AND h.backend_record_id=p_backend_id)))
$function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='snapshot_outer_single_eval' AND added_in='r412';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r412';
DO $p$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r412 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r412 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r412 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot()','09f6a5c2b02dbf9ae993b80d05c69c98'),
  ('public.pdc_imported_parts_flags_vehicle_20260912(uuid)','120ba955eace34fbfa7d594815b85485'),
  ('public.pdc_vehicle_department_membership_20260919(uuid)','91cda241a3b3c0eb7004ad77e531655f'),
  ('pdc_codex_intake_private.vehicle_tune_checkout(uuid)','916b975cbd9cc8bcda5c745b656addd5'),
  ('pdc_codex_intake_private.vehicle_service_locations(uuid)','cef440c7375636ffaaac0a3e20244cc1'),
  ('pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)','6457a23a3036ebce52090e69ada08173')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>6 THEN RAISE EXCEPTION 'r412 undo: a function is not back to its pre-r412 version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_691()','775d90e421042423670990b467f157be'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_750()','714fa7a3a5f79e95f2cd891ba96045cc'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','580bf52022a37d11b78f228c37254c4a'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre168()','d3b6f69bdf3420336403816fc7c60255'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_169()','b9d15c26231ceb6c0284fc7980878a09'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_174()','ff6ff8b4589ce811faeb97662b22a158'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_310()','2cdf8dfb3943babfb18d7476041c92cf'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_395()','8c37da97120ae46764a21c279a622a73'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_396()','c30cb9b0837aa50ac743745a3c7f2616'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_399()','bcca3e5857f70635cf1a3eb2cff64056'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_412()','8d835e24b24cd8dc4eda0e7748857ee8'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_422()','aa2bd6e7335f6bc873b2d91856179a67'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_429()','f3447cc81a348c8202d138cb3b440bdf'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_700()','33deecc1ae222a28984842862199ec2a'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','733c898847d84a79576f028dd9d1fea6'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_82000()','10a51ee7591f9c1ee65e735108ec9ced'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_ext1300()','b1de398abce363b921d916a91892f2d9'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','2ed0984e0f1a6b6e10ac5601a0014e18'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','623b014b00ab74159639ed23f257f607'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_693()','4f3f4dd8cab754543d3c0cc934ad111f'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_767()','db446d2222101f0028666333779fdf23'),
  ('public.get_pdc_email_vehicle_board_snapshot()','a3a635b978cb6b266ea04f03c876672f'),
  ('public.pdc_parts_flags_vehicle_20260911(uuid)','6c828cb4ffdd7e0717bd5d9f50f4c764'),
  ('pdc_bus_private.operation_station(uuid)','f7ab4745fb8e97fcd58a209145cfab0f'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','ef6301a91e9fcbb7a663c2319c5bef9d'),
  ('public.pdc_tune_approved_operation_source_20260912(uuid)','867bb1b1c0afebfb62f45c08ad6b3154')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>26 THEN RAISE EXCEPTION 'r412 undo: a kept function changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_imported_parts_flags_vehicle_20260912(uuid)','{postgres=X/postgres,service_role=X/postgres}falses|search_path=pg_catalog, public, pdc_parts_private'),
  ('public.pdc_vehicle_department_membership_20260919(uuid)','{postgres=X/postgres}falses|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.vehicle_tune_checkout(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.vehicle_service_locations(uuid)','{postgres=X/postgres}falses|search_path=pg_catalog, public'),
  ('pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u')<>6 THEN RAISE EXCEPTION 'r412 undo: owner, grants, security, volatility, strictness or search_path changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid IN (SELECT to_regprocedure(x) FROM unnest(ARRAY['public.pdc_imported_parts_flags_vehicle_20260912(uuid)','public.pdc_vehicle_department_membership_20260919(uuid)','pdc_codex_intake_private.vehicle_tune_checkout(uuid)','pdc_codex_intake_private.vehicle_service_locations(uuid)','pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)']) x) AND l.lanname='sql')<>5 THEN RAISE EXCEPTION 'r412 undo: helpers are not sql'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r412') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r412') THEN RAISE EXCEPTION 'r412 undo: r412 rows left'; END IF;
END $p$;
