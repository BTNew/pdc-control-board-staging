-- Read-only effective estimates. Original Tune operations and saved staff work are untouched.
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.service_catalogue_hours_20260917(p_line jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
DECLARE op public.pdc_pilbara_service_operations%rowtype; ev jsonb; candidate jsonb; a jsonb; nav jsonb; n integer; h numeric; lo numeric; hi numeric; cost numeric; basis text; d text; source_desc text;
BEGIN
 IF coalesce(nullif(p_line->>'source_estimated_hours','')::numeric,0)>0 OR p_line->>'stage_code'='SUBLET'
 OR p_line->>'hours_provenance'='explicit_description_time' OR p_line->>'hours_provenance'='staff_estimate'
 OR (p_line ? 'staff_hours' AND p_line->>'staff_hours' IS NOT NULL)
 OR (p_line->>'hours_provenance' LIKE 'craig_%' AND coalesce((p_line->>'estimated_hours')::numeric,0)>0)
 OR coalesce(p_line->>'source_line_id','') !~* '^[0-9a-f-]{36}$' THEN RETURN '{}'; END IF;
 SELECT * INTO op FROM public.pdc_pilbara_service_operations WHERE operation_id=(p_line->>'source_line_id')::uuid;
 IF NOT FOUND OR coalesce(op.source_estimated_hours,0)>0 THEN RETURN '{}'; END IF;
 -- Approved changed-source work has its own reviewed hours, even when its description is unchanged.
 IF public.pdc_tune_approved_operation_source_20260912(op.operation_id) IS NOT NULL THEN RETURN '{}'; END IF;
 source_desc:=op.operation_description;
 IF source_desc IS DISTINCT FROM op.operation_description OR p_line->>'description' IS DISTINCT FROM op.operation_description THEN RETURN '{}'; END IF;
 SELECT ir.raw_row INTO ev FROM public.pdc_pilbara_service_import_rows ir WHERE ir.evidence_id=op.raw_evidence_id;
 -- The latest successful unchanged-source receipt can carry a newly researched estimate.
 -- Selecting the latest observation before checking its value prevents fallback to an older estimate after a review withdrawal.
 SELECT ir.normalized_payload||jsonb_build_object('arb_review',ir.raw_row->'arb_review') INTO candidate
 FROM public.pdc_pilbara_service_operation_history hist
 JOIN public.pdc_pilbara_service_import_batches applied ON applied.batch_id=hist.batch_id AND applied.batch_kind='apply' AND applied.response->>'ok'='true'
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.source_hash=applied.source_hash AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_rows ir ON ir.batch_id=preview.batch_id AND ir.normalized_payload=hist.immutable_snapshot
 WHERE hist.operation_id=op.operation_id AND hist.resulting_semantic_hash=op.semantic_hash
 AND ir.stock_number=op.stock_number AND ir.repair_order_number=op.repair_order_number AND ir.original_line_number=op.original_line_number
 AND ir.decision IN ('insert','unchanged')
 AND ir.raw_row->>'Company' IS NOT DISTINCT FROM ev->>'Company' AND ir.raw_row->>'Division' IS NOT DISTINCT FROM ev->>'Division'
 ORDER BY CASE WHEN ir.raw_row->>'source_snapshot_at' ~ '^\d{4}-\d{2}-\d{2}T' THEN (ir.raw_row->>'source_snapshot_at')::timestamptz END DESC NULLS LAST,
 hist.created_at DESC,hist.history_id DESC LIMIT 1;
 IF candidate->>'hours_provenance'='ai_estimated' AND candidate->'arb_review'->>'status'='estimated'
 AND pdc_codex_intake_private.arb_hours_review_valid(candidate) THEN
  a:=candidate->'arb_review'; h:=(candidate->>'effective_estimated_hours')::numeric;
  RETURN jsonb_build_object('estimated_hours',h,'effective_estimated_hours',h,'hours_provenance','ai_estimated','needs_hours_review',false,'arb_review',a,
   'estimate_basis',a->>'match_basis','review_note','AI estimate from '||(a->>'guide_version')||'; '||coalesce(a->>'caveat','Confirm fitment before scheduling.'));
 END IF;
 -- Only a unique current exact-Stock Navision production record may establish model generation.
 SELECT count(*),min(b.normalized_data::text)::jsonb INTO n,nav FROM public.navision_backend_records b
 WHERE b.canonical_vehicle_id=op.vehicle_id AND b.is_current AND b.record_status='current' AND b.source_system='microsoft_navision'
 AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=op.stock_number;
 IF n<>1 OR coalesce(nav->>'vehicle','') !~* 'hilux' OR coalesce(nav->>'prodMth','') !~ '^(12/25|0[1-9]/26|1[0-2]/26)$' THEN RETURN '{}'; END IF;
 d:=upper(op.operation_description);
 IF d ~ '\mARB\M.*\mCOMMERCIAL\M.*\m(BULL|BAR)\M' AND d !~ 'PAINT|COLOUR|COLOR|REMOV|REPAIR' THEN
  RETURN jsonb_build_object('estimated_hours',5,'effective_estimated_hours',5,'hours_provenance','craig_my26_arb_commercial_bullbar_5_hours','needs_hours_review',false,'estimate_basis','Craig MY26 HiLux ARB commercial bull bar standard: 5 hours; exact Navision production month '||(nav->>'prodMth'));
 END IF;
 IF d !~ '^SAFARI[ -]+SNORKEL([ -]+(V[ -]?SPEC|ARMAX|SS223HF|SS223HP))?([ ]*\*[^*]*\*)?[ ]*$' THEN RETURN '{}'; END IF;
 IF d ~ 'V[ -]?SPEC|SS223HF' THEN h:=2;lo:=2;hi:=2;cost:=320;basis:='MY26 HiLux Safari V-Spec SS223HF: fitting 320 / 160 = 2 hours.';
 ELSIF d ~ 'ARMAX|SS223HP' THEN h:=2.5;lo:=2.5;hi:=2.5;cost:=400;basis:='MY26 HiLux Safari ARMAX SS223HP: fitting 400 / 160 = 2.5 hours.';
 ELSE h:=2.25;lo:=2;hi:=2.5;cost:=320;basis:='MY26 HiLux Safari: SS223HF 320/160=2h and SS223HP 400/160=2.5h; 2.25h lies within 15% of both. Confirm variant.'; END IF;
 a:=jsonb_build_object('checked',true,'status','estimated','guide_version','DRT20260901.1','guide_sha256','4e1a8c9cd5f317d1a9b28fbf0c9448f1b33a33651e4dff8507e9947a157c46c6','pages',jsonb_build_array(5,56),'searched_terms',jsonb_build_array(op.operation_description,'HiLux MY26'),
 'fitting_charge',cost,'labour_rate',160,'estimated_hours',h,'comparable_min_hours',lo,'comparable_max_hours',hi,'match_basis',basis,'vehicle_context',jsonb_build_object('source','unique_current_exact_stock_navision','production_month',nav->>'prodMth'),'caveat','AI estimate; confirm kit. Excludes relocating non-original accessories.');
 RETURN jsonb_build_object('estimated_hours',h,'effective_estimated_hours',h,'hours_provenance','ai_estimated','needs_hours_review',false,'arb_review',a,'estimate_basis',basis,'review_note','AI estimate - DRT20260901.1 pp5,56; confirm kit; excludes relocating non-original accessories.');
END $fn$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_catalogue_hours_20260917(jsonb) FROM PUBLIC,anon,authenticated;


