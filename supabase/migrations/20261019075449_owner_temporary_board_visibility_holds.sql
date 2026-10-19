-- Owner-requested reversible visibility only. Operational status/QC/booking data is untouched.
DO $guard$ BEGIN
IF NOT pdc_codex_intake_private.management_connection() OR NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required';END IF;
IF md5(replace(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure),chr(13),''))<>'9c927ff0c054ff70c0d5bedb656b9548' OR md5(replace(pg_get_functiondef('public.get_navision_visible_snapshot(text,text,uuid,integer,bigint)'::regprocedure),chr(13),''))<>'054654e01c554e9204d2dcbf4c6d757c' THEN RAISE EXCEPTION 'snapshot_contract_changed';END IF;
END $guard$;
CREATE TABLE pdc_codex_intake_private.owner_board_visibility_holds_20261019(
 stock_number text PRIMARY KEY CHECK(length(btrim(stock_number))>0),
 vehicle_id uuid REFERENCES public.vehicles(id),
 backend_record_id uuid REFERENCES public.navision_backend_records(id),
 request_key text NOT NULL,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 source_jobs jsonb NOT NULL CHECK(jsonb_typeof(source_jobs)='array'),
 owner_authority text NOT NULL CHECK(length(owner_authority)>20),
 previous_vehicle jsonb,
 reason text NOT NULL,
 held_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 database_actor text NOT NULL DEFAULT current_user,
 released_at timestamptz,
 release_reason text
);
ALTER TABLE pdc_codex_intake_private.owner_board_visibility_holds_20261019 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_codex_intake_private.owner_board_visibility_holds_20261019 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION pdc_codex_intake_private.owner_board_hold_active_20261019(p_vehicle_id uuid,p_stock text,p_backend_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog AS $fn$
SELECT EXISTS(SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h
 WHERE h.released_at IS NULL AND ((p_vehicle_id IS NOT NULL AND h.vehicle_id=p_vehicle_id) OR (p_stock IS NOT NULL AND h.stock_number=p_stock) OR(p_backend_id IS NOT NULL AND h.backend_record_id=p_backend_id)))
$fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION pdc_codex_intake_private.enforce_owner_board_hold_20261019()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $fn$
BEGIN
 IF pdc_codex_intake_private.owner_board_hold_active_20261019(NEW.id,NEW.stock_number,NULL) THEN NEW.visible_on_board:=false;END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.enforce_owner_board_hold_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER z_owner_board_hold_20261019 BEFORE INSERT OR UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION pdc_codex_intake_private.enforce_owner_board_hold_20261019();
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
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')),'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
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
      'operation_line_id',o.operation_id,'department',o.department,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key',CASE CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END) END,
      'job_card_number',o.repair_order_number,'description',coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,'parts_semantics',o.parts_semantics,
      'classification',CASE WHEN o.department='138' THEN pdc_bus_private.operation_station(o.operation_id) WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END,'classification_method',coalesce(h.method,'review'),
      'classification_confidence',coalesce(h.confidence,0),'classification_rationale',coalesce(h.rationale,'No current classification; retained for Review.'),
      'source_description_hash',h.source_description_hash,'classifier_version',h.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||o.stock_number||':'||o.repair_order_number||':'||o.original_line_number
    )) ORDER BY o.source_order),'[]'::jsonb) service_lines
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE o.vehicle_id=(row_value->>'id')::uuid
  ) projected
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)
     OR canonical.lifecycle_state::text='completed';
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$;
CREATE OR REPLACE FUNCTION public.get_navision_visible_snapshot(p_source_system text, p_dealer_code text, p_after_record_id uuid DEFAULT NULL::uuid, p_page_size integer DEFAULT 200, p_expected_revision bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE base jsonb; rows jsonb;
BEGIN
  base:=public.get_navision_visible_snapshot_pre_82000(p_source_system,p_dealer_code,p_after_record_id,p_page_size,p_expected_revision);
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',h)||jsonb_build_object('first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at','elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days') ORDER BY x->>'id'),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,items}','[]'::jsonb)) x
  CROSS JOIN LATERAL public.pdc_lifecycle_history_payload_82000(coalesce((x->>'canonical_vehicle_id')::uuid,(x->>'id')::uuid)) h
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(nullif(x->>'canonical_vehicle_id','')::uuid,coalesce(x#>>'{normalized_data,batch}',x#>>'{normalized_data,stock}',x->>'stock_number',x->>'batch',x->>'stock'),nullif(x->>'id','')::uuid);
  RETURN jsonb_set(base,'{data,items}',rows,true);
END $function$;
CREATE FUNCTION pdc_codex_intake_private.protect_owner_hold_evidence_20261019()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog AS $fn$
BEGIN
 IF TG_OP='DELETE' OR NOT pdc_codex_intake_private.management_connection() OR auth.uid() IS NOT NULL
 THEN RAISE EXCEPTION 'owner_hold_evidence_protected';END IF;
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-ARRAY['released_at','release_reason']) IS DISTINCT FROM(to_jsonb(OLD)-ARRAY['released_at','release_reason'])
 THEN RAISE EXCEPTION 'owner_hold_original_is_immutable';END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.protect_owner_hold_evidence_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER owner_hold_immutable BEFORE UPDATE OR DELETE ON pdc_codex_intake_private.owner_board_visibility_holds_20261019 FOR EACH ROW EXECUTE FUNCTION pdc_codex_intake_private.protect_owner_hold_evidence_20261019();
