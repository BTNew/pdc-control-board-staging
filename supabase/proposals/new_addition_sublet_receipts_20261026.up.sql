-- DRAFT for root review. Future automatic external-line routing via the existing server approval receipt.
-- Existing rows and approvals are not rewritten. No new table, privilege or bypass.
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='20s';
DO $canonical_auto_receipt$
DECLARE
 entries jsonb:=$entry_json$[
  {
    "signature": "pdc_operation_updates_private.accept_change(uuid)",
    "before_hash": "b51e1d2211722fe2c04c246d5e0a0d83",
    "after_hash": "91683e76e8418e2d3f305ae152451965",
    "prosecdef": false,
    "volatile": "v",
    "config": [
      "search_path=pg_catalog, public, extensions"
    ],
    "pinned": false,
    "replacements": [
      {
        "before": "  approved_at=clock_timestamp(),approved_by=actor WHERE change_id=q.change_id;",
        "after": "  approved_at=clock_timestamp(),approved_by=actor,\n  -- The server-chosen estimate is already part of the final approval receipt.\n  -- Make that same decision visible to routing within this atomic acceptance.\n  -- Any later refusal raises and rolls this provisional receipt back with the line.\n  approval_receipt=CASE WHEN q.source_operation_id IS NULL AND q.change_kind='added'\n    AND choice->>'routing_rule'='canonical_external_sublet_20261026'\n    AND stage='SUBLET' AND choice->>'work_category'='SUBLET'\n   THEN jsonb_build_object('data',jsonb_build_object('estimate',choice))\n   ELSE approval_receipt END\n  WHERE change_id=q.change_id;"
      }
    ]
  },
  {
    "signature": "pdc_bus_private.operation_station(uuid)",
    "before_hash": "03e96225dc36891ec0d122aecd87b967",
    "after_hash": "e9ee86ee7214bcfeb920343eb01bca83",
    "prosecdef": true,
    "volatile": "s",
    "config": [
      "search_path=pg_catalog"
    ],
    "pinned": true,
    "replacements": [
      {
        "before": " SELECT coalesce(rs.stage_code,h.stage_code,pdc_work_categories_private.stage(r.category),",
        "after": " SELECT coalesce(rs.stage_code,h.stage_code,auto_policy.stage_code,pdc_work_categories_private.stage(r.category),"
      },
      {
        "before": " LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)",
        "after": " -- Only newly accepted operations with the exact server-issued policy receipt\n -- use this route. Existing reviewer/history choices still precede it.\n LEFT JOIN LATERAL (\n  SELECT 'SUBLET'::text AS stage_code\n  FROM public.pdc_tune_operation_change_reviews q\n  WHERE q.source_operation_id=o.operation_id AND q.vehicle_id=o.vehicle_id\n   AND q.change_kind='added' AND q.status='approved' AND btrim(o.department)='138'\n   AND q.approval_receipt#>>'{data,estimate,routing_rule}'='canonical_external_sublet_20261026'\n   AND q.approval_receipt#>>'{data,estimate,ok}'='true'\n   AND q.approval_receipt#>>'{data,estimate,stage_code}'='SUBLET'\n   AND q.approval_receipt#>>'{data,estimate,work_category}'='SUBLET'\n   AND (pdc_work_categories_private.note_fee_sublet_521(jsonb_build_object(\n         'description',d.description,'operation_code',o.operation_code))\n     OR pdc_work_categories_private.perth_delivery_sublet_523(jsonb_build_object(\n         'description',d.description,'operation_code',o.operation_code)))\n  ORDER BY q.approved_at DESC, q.change_id DESC LIMIT 1\n ) auto_policy ON true\n LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)"
      }
    ]
  }
]$entry_json$::jsonb;
 item jsonb; replacement jsonb; target oid; definition text; metadata_before jsonb;
 metadata_snapshots jsonb:='{}'::jsonb; pins_before jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NOT NULL
  OR NOT pdc_codex_intake_private.management_connection()
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'canonical_auto_receipt_staging_management_required'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.proposal(uuid)'::regprocedure)<>'1c1eb17a1594f36489cf33572117d642'
 OR md5(pg_get_functiondef('pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure))<>'a5e081c31037886985f77ba2f4209c84'
 OR md5(pg_get_functiondef('pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure))<>'2613c2ca36345a3bcb10bf6be2c4c111'
 THEN RAISE EXCEPTION 'canonical_auto_receipt_dependency_changed'; END IF;
 SELECT to_jsonb(e) INTO STRICT pins_before FROM pdc_ops.expected_function_md5 e
 WHERE signature='pdc_bus_private.operation_station(uuid)';
 FOR item IN SELECT value FROM jsonb_array_elements(entries) LOOP
  target:=(item->>'signature')::regprocedure;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=target
   AND md5(p.prosrc)=item->>'before_hash' AND pg_get_userbyid(p.proowner)='postgres'
   AND p.proacl='{postgres=X/postgres}'::aclitem[] AND to_jsonb(p.proconfig)=item->'config'
   AND p.prosecdef=(item->>'prosecdef')::boolean AND p.provolatile=(item->>'volatile')::"char"
   AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u')
  THEN RAISE EXCEPTION 'canonical_auto_receipt_function_changed: %',item->>'signature'; END IF;
  IF (item->>'pinned')::boolean THEN
   IF pins_before->>'prosrc_md5' IS DISTINCT FROM item->>'before_hash'
   THEN RAISE EXCEPTION 'canonical_auto_receipt_pin_changed'; END IF;
  ELSIF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature=item->>'signature')
  THEN RAISE EXCEPTION 'canonical_auto_receipt_unexpected_pin'; END IF;
  SELECT to_jsonb(p)-'prosrc' INTO STRICT metadata_before FROM pg_proc p WHERE p.oid=target;
  metadata_snapshots:=metadata_snapshots||jsonb_build_object(item->>'signature',metadata_before);
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(entries) LOOP
  target:=(item->>'signature')::regprocedure;
  SELECT pg_get_functiondef(target) INTO definition;
  FOR replacement IN SELECT value FROM jsonb_array_elements(item->'replacements') LOOP
   IF (length(definition)-length(replace(definition,replacement->>'before','')))/length(replacement->>'before')<>1
   THEN RAISE EXCEPTION 'canonical_auto_receipt_anchor_changed: %',item->>'signature'; END IF;
   definition:=replace(definition,replacement->>'before',replacement->>'after');
  END LOOP;
  EXECUTE definition;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=target AND md5(p.prosrc)=item->>'after_hash'
   AND to_jsonb(p)-'prosrc'=metadata_snapshots->(item->>'signature'))
  THEN RAISE EXCEPTION 'canonical_auto_receipt_readback_failed: %',item->>'signature'; END IF;
  IF (item->>'pinned')::boolean THEN
   UPDATE pdc_ops.expected_function_md5 SET prosrc_md5=item->>'after_hash'
   WHERE signature=item->>'signature' AND prosrc_md5=item->>'before_hash';
   IF NOT FOUND THEN RAISE EXCEPTION 'canonical_auto_receipt_pin_write_failed'; END IF;
   IF (SELECT to_jsonb(e) FROM pdc_ops.expected_function_md5 e WHERE signature=item->>'signature')
    IS DISTINCT FROM pins_before||jsonb_build_object('prosrc_md5',item->>'after_hash')
   THEN RAISE EXCEPTION 'canonical_auto_receipt_pin_metadata_changed'; END IF;
  END IF;
 END LOOP;
END
$canonical_auto_receipt$;


