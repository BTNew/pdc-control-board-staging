-- Look up inbox vehicle labels from the page's action receipts.
-- The previous inbox loaded the full vehicle location snapshot for every
-- vehicle on the board. This reads public.vehicles only for the vehicle ids on
-- the current page, using the same final membership:
--   pre168 board rows, minus an owner-document undo that has no sibling import,
--   plus Collected/Completed and completed-lifecycle rows kept by the later
--   snapshot layers, plus the one Navision board vehicle those layers force in,
--   minus an active owner-board hold unless the lifecycle is completed.
-- Tune PMG details still replace vehicle_description when that review exists.
-- current_location and version stay on the vehicle row. v1 is unchanged.
-- No schedule and no receipt authority changes.
-- Rollback: supabase/rollbacks/20261019231000_inbox_page_vehicles.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  src text;
  definer boolean;
  volatility "char";
  config text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  SELECT p.prosrc, p.prosecdef, p.provolatile, p.proconfig
    INTO src, definer, volatility, config
  FROM pg_proc p
  WHERE p.oid = 'public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '6f2c14b914643a93e53dfb9339de9dca'
     OR definer IS DISTINCT FROM true
     OR volatility IS DISTINCT FROM 's'
     OR config IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, auth, extensions'] THEN
    RAISE EXCEPTION 'reviewed_inbox_v2_changed';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.pdc_email_inbox_snapshot_vehicle(p_vehicle_id uuid)
RETURNS TABLE (
  vehicle_id uuid,
  stock_number text,
  vehicle_description text,
  current_location text,
  vehicle_version text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $helper$
BEGIN
  RETURN QUERY

  SELECT
    v.id,
    v.stock_number,
    CASE
      WHEN tuned.details ? 'vehicle_description' THEN tuned.details->>'vehicle_description'
      ELSE v.vehicle_description
    END,
    v.current_location,
    v.version::text
  FROM public.vehicles v
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN EXISTS (
        SELECT 1 FROM public.pdc_new_vehicle_reviews nr
        WHERE nr.vehicle_id = v.id AND nr.source_kind = 'tune_pmg'
      ) THEN public.pdc_tune_vehicle_details_v5(v.id)
      ELSE '{}'::jsonb
    END AS details
  ) tuned
  WHERE v.id = p_vehicle_id
    AND v.deleted_at IS NULL
    AND (
      (
        v.id = '2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid
        AND public.normalize_vehicle_stock_number(v.stock_number) = '13000765'
        AND v.lifecycle_state::text = 'active'
        AND v.visible_on_board
        AND v.source_system = 'microsoft_navision'
        AND v.source_batch_id IN ('14450', '37047')
        AND v.source_record_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.navision_backend_records n
          WHERE n.id = CASE
            WHEN v.id = '2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid
             AND v.source_record_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            THEN v.source_record_id::uuid ELSE NULL END
            AND n.is_current
            AND n.record_status = 'current'
            AND n.dealer_code = v.source_batch_id
            AND public.normalize_vehicle_stock_number(n.normalized_data->>'batch') = '13000765'
        )
        AND EXISTS (
          SELECT 1 FROM public.navision_board_activations a
          WHERE a.canonical_vehicle_id = v.id
            AND a.active
            AND public.normalize_vehicle_stock_number(a.activated_stock_number) = '13000765'
        )
      )
      OR (
        (v.current_location IN ('Collected', 'Completed') OR v.lifecycle_state::text = 'completed')
        AND (
          public.pdc_lifecycle_history_payload_82000(v.id) IS NOT NULL
          OR EXISTS (SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id = v.id)
          OR EXISTS (SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id = v.id)
        )
      )
      OR (
        v.lifecycle_state::text = 'completed'
        AND v.current_location = 'Completed'
        AND EXISTS (SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id = v.id)
      )
      OR (
        v.current_location = 'Collected'
        AND EXISTS (
          SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q
          WHERE q.vehicle_id = v.id AND q.action = 'collected'
        )
      )
      OR (
        v.current_location IN ('Collected', 'Completed')
        AND EXISTS (
          SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q
          WHERE q.vehicle_id = v.id AND q.action IN ('collected', 'delivered')
        )
      )
      OR (
        (
          (v.lifecycle_state::text IN ('active', 'rft') AND v.visible_on_board)
          OR (
            v.lifecycle_state::text = 'completed'
            AND v.rft_collected_at IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM public.pdc_rft_transport_action_receipts_412 handover
              WHERE handover.vehicle_id = v.id AND handover.action = 'collected'
            )
          )
        )
        AND (
          EXISTS (SELECT 1 FROM public.pdc_authenticated_email_import_receipts r WHERE r.vehicle_id = v.id)
          OR (
            v.lifecycle_state::text IN ('active', 'rft')
            AND v.visible_on_board
            AND EXISTS (
              SELECT 1 FROM public.pdc_pilbara_service_operations o
              WHERE o.vehicle_id = v.id AND o.stock_number = v.stock_number
            )
          )
          OR EXISTS (
            SELECT 1 FROM public.vehicle_work_items wi
            WHERE wi.vehicle_id = v.id AND lower(wi.work_key) = 'sublet' AND wi.required
          )
          OR EXISTS (SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id = v.id)
          OR EXISTS (
            SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
            WHERE r.run_id = 'HERMES-TEST-RUN-20260824'
              AND r.vehicle_id = v.id
              AND r.stock_number = v.stock_number
              AND v.stock_number ~ '^HERMES-TEST-(00[1-9]|01[0-9]|020)$'
              AND v.source_system = 'hermes_overnight_synthetic'
              AND v.source_batch_id = r.run_id
              AND v.source_record_id = r.stock_number
              AND v.source_payload->>'contract' = 'pdc-overnight-synthetic-fleet-363/render_only'
          )
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.pdc_owner_supplied_document_receipts_396 r
          JOIN public.pdc_owner_supplied_document_undo_receipts_396 u ON u.receipt_id = r.receipt_id
          WHERE r.vehicle_id = v.id
            AND NOT EXISTS (
              SELECT 1 FROM public.pdc_authenticated_email_import_receipts sibling
              WHERE sibling.vehicle_id = r.vehicle_id
                AND sibling.receipt_id <> r.canonical_import_receipt_id
            )
        )
      )
    )
    AND (
      NOT pdc_codex_intake_private.owner_board_hold_active_20261019(v.id, v.stock_number, NULL)
      OR v.lifecycle_state::text = 'completed'
    )
;
END
$helper$;

REVOKE ALL ON FUNCTION public.pdc_email_inbox_snapshot_vehicle(uuid) FROM PUBLIC;
DO $revoke$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.pdc_email_inbox_snapshot_vehicle(uuid) FROM %I', role_name);
    END IF;
  END LOOP;
END
$revoke$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(p_cursor jsonb DEFAULT NULL::jsonb, p_page_size integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_limit integer:=greatest(1,least(coalesce(p_page_size,100),250));
  v_revision bigint;
  v_items jsonb;
  v_next_cursor jsonb;
  v_cursor_sort_time timestamptz;
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
  v_has_more boolean:=false;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR auth.role()<>'authenticated'
     OR auth.uid() IS NULL
     OR v_role NOT IN('viewer','operator','importer','administrator')
  THEN
    RETURN jsonb_build_object('ok',false,'code','successor_inbox_unauthorized','items','[]'::jsonb);
  END IF;
  IF p_cursor IS NOT NULL THEN
    IF jsonb_typeof(p_cursor)<>'object'
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_cursor) k) IS DISTINCT FROM ARRAY['created_at','id','sort_time']::text[]
       OR (p_cursor->>'sort_time') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
       OR (p_cursor->>'created_at') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
       OR (p_cursor->>'id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_successor_inbox_cursor','items','[]'::jsonb); END IF;
    v_cursor_sort_time:=(p_cursor->>'sort_time')::timestamptz;
    v_cursor_created_at:=(p_cursor->>'created_at')::timestamptz;
    v_cursor_id:=(p_cursor->>'id')::uuid;
  END IF;
  SELECT revision INTO v_revision FROM public.pdc_email_ai_successor_ui_revision WHERE singleton;
  WITH selected AS (
    SELECT i.*, row_number() OVER (ORDER BY coalesce(i.received_at,i.created_at) DESC, i.created_at DESC, i.id DESC) AS row_no,
      coalesce(i.received_at,i.created_at) AS sort_time
    FROM public.ai_email_intake i
    WHERE p_cursor IS NULL OR coalesce(i.received_at,i.created_at)<v_cursor_sort_time OR (coalesce(i.received_at,i.created_at)=v_cursor_sort_time AND (i.created_at<v_cursor_created_at OR (i.created_at=v_cursor_created_at AND i.id<v_cursor_id)))
    ORDER BY coalesce(i.received_at,i.created_at) DESC, i.created_at DESC, i.id DESC
    LIMIT v_limit+1
  ),
  bounded AS (SELECT * FROM selected WHERE row_no<=v_limit),
  parent_rows AS (
    SELECT b.*,
      t.transaction_id,t.source_digest AS transaction_source_digest,t.evidence_digest AS transaction_evidence_digest,
      t.plan_hash,t.typed_plan,t.aggregate_disposition,t.readback_parity,t.response,
      coalesce(att.attachments,'[]'::jsonb) AS attachment_summary,
      jsonb_build_object('job_card_number',left(coalesce(b.extracted_data->>'job_card_number',''),80),'operation_count',case when jsonb_typeof(b.extracted_data->'operation_lines')='array' then jsonb_array_length(b.extracted_data->'operation_lines') else 0 end,'extraction_status',case when b.extracted_data='{}'::jsonb then 'not_extracted' else 'available' end) AS job_card_summary,
      coalesce(vr.vehicle_results,'[]'::jsonb) AS vehicle_results
    FROM bounded b
    LEFT JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=b.id
    LEFT JOIN LATERAL (
      SELECT jsonb_build_object(
        'count',count(*)::integer,
        'names',coalesce(jsonb_agg(a.file_name ORDER BY a.created_at,a.id),'[]'::jsonb),
        'digests',coalesce(jsonb_agg(a.source_hash ORDER BY a.created_at,a.id) FILTER (WHERE a.source_hash IS NOT NULL),'[]'::jsonb)
      ) AS attachments
      FROM public.ai_email_attachments a WHERE a.intake_id=b.id
    ) att ON true
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id',groups.vehicle_id,
        'stock',coalesce(sv.stock_number,'Unresolved stock'),
        'vehicle',coalesce(sv.vehicle_description,'Vehicle identity unavailable'),
        'location',coalesce(sv.current_location,'—'),
        'identity_status',case when sv.vehicle_id IS NULL then 'UNRESOLVED' else 'MATCHED' end,
        'actions',groups.actions,
        'readback',coalesce((t.response->'readback'),null)
      ) ORDER BY coalesce(sv.stock_number,''),groups.vehicle_id) AS vehicle_results
      FROM (
        SELECT a.vehicle_id,
          jsonb_agg(jsonb_build_object(
            'action_type',a.action_type,
            'instruction_id',a.instruction_id,
            'canonical_rpc',a.canonical_rpc,
            'disposition',a.disposition,
            'reason',a.reason,
            'before',a.before_state,
            'requested',a.requested,
            'result',a.after_state,
            'expected',coalesce(response_action.action->'expected','null'::jsonb),
            'actual',coalesce(response_action.action->'actual','null'::jsonb),
            'verification',a.verification,
            'evidence_refs',coalesce(plan_instruction.instruction->'evidence_refs','[]'::jsonb),
            'action_receipt_id',a.action_receipt_id,
            'action_key',a.action_key
          ) ORDER BY a.created_at,a.action_receipt_id) AS actions
        FROM public.pdc_email_ai_successor_action_receipts a
        LEFT JOIN LATERAL (
          SELECT x AS action FROM jsonb_array_elements(coalesce(t.response->'actions','[]'::jsonb)) x
          WHERE x->>'action_key'=a.action_key LIMIT 1
        ) response_action ON true
        LEFT JOIN LATERAL (
          SELECT x AS instruction FROM jsonb_array_elements(coalesce(t.typed_plan->'instructions','[]'::jsonb)) x
          WHERE x->>'instruction_id'=a.instruction_id LIMIT 1
        ) plan_instruction ON true
        WHERE a.transaction_id=t.transaction_id
        GROUP BY a.vehicle_id
      ) groups
      LEFT JOIN LATERAL public.pdc_email_inbox_snapshot_vehicle(groups.vehicle_id) sv ON true
    ) vr ON true
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'intake_id',p.id,
    'source_receipt_id',p.id,
    'intake_uid',coalesce(nullif(p.provider_uid,''),nullif(p.graph_message_id,''),p.id::text),
    'provider_uid',p.provider_uid,
    'message_id',coalesce(p.internet_message_id,p.graph_message_id),
    'thread_id',p.graph_thread_id,
    'source_digest',CASE
      WHEN lower(coalesce(p.source_hash,''))~'^[a-f0-9]{64}$'
      THEN lower(p.source_hash) ELSE NULL END,
    'evidence_digest',public.pdc_email_ai_successor_source_evidence_digest_20260901(
      p.source_hash,p.extracted_data->>'pdc_email_ai_evidence_digest',
      coalesce(p.internet_message_id,p.graph_message_id),p.graph_thread_id,
      coalesce(p.received_at,p.created_at),p.sender_email,p.subject,p.provider_uid,
      p.raw_body,p.attachment_summary->'digests'),
    'received_at',coalesce(p.received_at,p.created_at),
    'sender',coalesce(p.sender_email,'Unknown sender'),
    'subject',coalesce(p.subject,'Email received'),
    'attachment_summary',p.attachment_summary,
    'job_card_summary',p.job_card_summary,
    'disposition',coalesce(p.aggregate_disposition::text,case when p.permanent_failure then 'QUARANTINED' else 'RECEIVED_WAITING' end),
    'verification_status',case when p.aggregate_disposition='SUCCESS' and p.readback_parity then 'PASS' when p.aggregate_disposition IS NOT NULL then 'PARTIAL' else 'NOT_RUN' end,
    'summary',jsonb_build_object(
      'before',case when jsonb_array_length(p.vehicle_results)>0 then jsonb_array_length(p.vehicle_results)::text||' vehicle result(s)' else 'No successor result yet' end,
      'requested',case when p.transaction_id IS NULL then 'Awaiting typed plan' else coalesce(jsonb_array_length(p.response->'actions')::text,'0')||' typed action(s)' end,
      'result',coalesce(p.aggregate_disposition::text,'Awaiting successor processing')
    ),
    'transaction',case when p.transaction_id IS NULL then null else jsonb_build_object(
      'transaction_id',p.transaction_id,
      'source_receipt_id',p.id,
      'source_digest',p.transaction_source_digest,
      'evidence_digest',p.transaction_evidence_digest,
      'plan_hash',p.plan_hash,
      'disposition',p.aggregate_disposition,
      'typed_plan',public.pdc_email_ai_successor_safe_plan(p.typed_plan),
      'versions',jsonb_build_object(
        'model',p.response->>'model_version',
        'prompt',p.response->>'prompt_version',
        'instruction_set',p.response->>'action_contract_version',
        'taxonomy',p.response->>'taxonomy_version',
        'rules',p.response->>'rule_version',
        'action_contract',p.response->>'action_contract_version',
        'supabase_action',p.response->>'supabase_action_version',
        'transport',p.response->>'transport_release_version'
      ),
      'readback',p.response->'readback',
      'readback_parity',p.readback_parity,
      'response',jsonb_build_object('actions',p.response->'actions','readback_parity',p.response->'readback_parity')
    ) end,
    'vehicle_results',p.vehicle_results,
    'retry_state',jsonb_build_object(
      'attempts',coalesce(p.queue_attempts,0),
      'retry_class',p.retry_class,
      'next_attempt_at',p.next_attempt_at,
      'last_error_code',p.last_error_code,
      'quarantine',coalesce(p.permanent_failure,false)
    ),
    'quarantine',case when p.permanent_failure then jsonb_build_object('quarantined',true,'reason',p.last_error_code,'retry_class',p.retry_class) else null end
  ) ORDER BY p.sort_time DESC,p.created_at DESC,p.id DESC),'[]'::jsonb),
  (SELECT jsonb_build_object('sort_time',q.sort_time,'created_at',q.created_at,'id',q.id) FROM parent_rows q WHERE q.row_no=v_limit LIMIT 1),
  (SELECT count(*) FROM selected)>v_limit
  INTO v_items,v_next_cursor,v_has_more
  FROM parent_rows p;
  RETURN jsonb_build_object('ok',true,'code','successor_inbox_snapshot','revision',coalesce(v_revision,1),
    'has_more',v_has_more,'next_cursor',v_next_cursor,'items',v_items);
END $function$;

DO $check$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '7db67f598be0a2ad38cffb63e1745e15'
     OR position('pdc_email_inbox_snapshot_vehicle' in src) = 0
     OR position('get_pdc_email_vehicle_location_snapshot' in src) > 0
     OR position('snapshot_vehicles' in src) > 0 THEN
    RAISE EXCEPTION 'inbox_page_vehicle_rewrite_mismatch';
  END IF;
END
$check$;
