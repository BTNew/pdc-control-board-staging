-- Transaction-scoped proof that the page lookup matches an independent copy of
-- the snapshot membership. Every row is synthetic and the transaction rolls back.
-- The reference function below is the oracle; it must not call the page helper.

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS pdc_codex_intake_private;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE AS $$ SELECT current_setting('request.jwt.claim.role', true) $$;
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT true $$;
CREATE OR REPLACE FUNCTION public.current_pdc_user_role() RETURNS text
LANGUAGE sql STABLE AS $$ SELECT 'administrator' $$;
CREATE OR REPLACE FUNCTION public.normalize_vehicle_stock_number(p_value text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(regexp_replace(upper(btrim(p_value)), '[[:space:]-]+', '', 'g'), '') $$;
CREATE OR REPLACE FUNCTION public.pdc_tune_vehicle_details_v5(p_vehicle_id uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_vehicle_id = 'a1000000-0000-4000-8000-000000000001'::uuid
    THEN jsonb_build_object('vehicle_description', 'Tune rewritten description', 'details_backend_version', 9)
    ELSE '{}'::jsonb
  END
$$;
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_source_evidence_digest_20260901(
  text, text, text, text, timestamptz, text, text, text, text, jsonb
) RETURNS text LANGUAGE sql STABLE AS $$ SELECT 'digest-fixed' $$;
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_safe_plan(jsonb) RETURNS jsonb
LANGUAGE sql STABLE AS $$ SELECT coalesce($1, '{}'::jsonb) $$;

CREATE TABLE IF NOT EXISTS pdc_codex_intake_private.owner_board_visibility_holds_20261019 (
  vehicle_id uuid,
  stock_number text,
  backend_record_id uuid,
  released_at timestamptz
);
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.owner_board_hold_active_20261019(
  p_vehicle_id uuid, p_stock text, p_backend_id uuid
) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h
    WHERE h.released_at IS NULL
      AND (
        (p_vehicle_id IS NOT NULL AND h.vehicle_id = p_vehicle_id)
        OR (p_stock IS NOT NULL AND h.stock_number = p_stock)
        OR (p_backend_id IS NOT NULL AND h.backend_record_id = p_backend_id)
      )
  )
$$;

CREATE TABLE IF NOT EXISTS public.vehicles (
  id uuid PRIMARY KEY,
  stock_number text,
  vehicle_description text,
  current_location text,
  version integer,
  deleted_at timestamptz,
  lifecycle_state text,
  visible_on_board boolean,
  rft_collected_at timestamptz,
  source_system text,
  source_batch_id text,
  source_record_id text,
  source_payload jsonb
);
CREATE OR REPLACE FUNCTION public.pdc_lifecycle_history_payload_82000(p_vehicle_id uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_vehicle_id IN (
      'a1000000-0000-4000-8000-000000000006'::uuid,
      'a1000000-0000-4000-8000-000000000007'::uuid,
      'a1000000-0000-4000-8000-000000000010'::uuid,
      'a1000000-0000-4000-8000-000000000011'::uuid
    ) THEN NULL
    WHEN EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id) THEN '{}'::jsonb
    ELSE NULL
  END
$$;
CREATE TABLE IF NOT EXISTS public.pdc_authenticated_email_import_receipts (receipt_id uuid PRIMARY KEY, vehicle_id uuid);
CREATE TABLE IF NOT EXISTS public.pdc_pilbara_service_operations (operation_id uuid PRIMARY KEY, vehicle_id uuid, stock_number text);
CREATE TABLE IF NOT EXISTS public.vehicle_work_items (vehicle_id uuid, work_key text, required boolean);
CREATE TABLE IF NOT EXISTS public.pdc_sublet_bookings (vehicle_id uuid);
CREATE TABLE IF NOT EXISTS public.pdc_overnight_synthetic_fleet_registry_363 (run_id text, vehicle_id uuid, stock_number text);
CREATE TABLE IF NOT EXISTS public.pdc_rft_transport_action_receipts_412 (vehicle_id uuid, action text);
CREATE TABLE IF NOT EXISTS public.pdc_final_pdc_lifecycle_receipts_700 (vehicle_id uuid, action text);
CREATE TABLE IF NOT EXISTS public.pdc_rft_transport_lifecycle_receipts_734 (vehicle_id uuid, action text);
CREATE TABLE IF NOT EXISTS public.pdc_external_completion_receipts_20260903 (vehicle_id uuid, completed_at timestamptz);
CREATE TABLE IF NOT EXISTS public.navision_backend_records (
  id uuid PRIMARY KEY, is_current boolean, record_status text, dealer_code text, normalized_data jsonb
);
CREATE TABLE IF NOT EXISTS public.navision_board_activations (
  canonical_vehicle_id uuid, active boolean, activated_stock_number text
);
CREATE TABLE IF NOT EXISTS public.pdc_owner_supplied_document_receipts_396 (
  receipt_id uuid PRIMARY KEY, vehicle_id uuid, canonical_import_receipt_id uuid
);
CREATE TABLE IF NOT EXISTS public.pdc_owner_supplied_document_undo_receipts_396 (receipt_id uuid PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.pdc_new_vehicle_reviews (vehicle_id uuid, source_kind text);
CREATE TABLE IF NOT EXISTS public.pdc_email_ai_successor_ui_revision (singleton boolean, revision bigint);
CREATE TABLE IF NOT EXISTS public.ai_email_intake (
  id uuid PRIMARY KEY,
  received_at timestamptz,
  created_at timestamptz,
  provider_uid text,
  graph_message_id text,
  internet_message_id text,
  graph_thread_id text,
  source_hash text,
  extracted_data jsonb,
  sender_email text,
  subject text,
  raw_body text,
  permanent_failure boolean,
  queue_attempts integer,
  retry_class text,
  next_attempt_at timestamptz,
  last_error_code text
);
CREATE TABLE IF NOT EXISTS public.ai_email_attachments (
  id uuid PRIMARY KEY, intake_id uuid, file_name text, created_at timestamptz, source_hash text
);
CREATE TABLE IF NOT EXISTS public.pdc_email_ai_successor_transaction_receipts (
  transaction_id uuid PRIMARY KEY,
  source_receipt_id uuid,
  source_digest text,
  evidence_digest text,
  plan_hash text,
  typed_plan jsonb,
  aggregate_disposition text,
  readback_parity boolean,
  response jsonb
);
CREATE TABLE IF NOT EXISTS public.pdc_email_ai_successor_action_receipts (
  action_receipt_id uuid PRIMARY KEY,
  transaction_id uuid,
  vehicle_id uuid,
  action_type text,
  instruction_id text,
  canonical_rpc text,
  disposition text,
  reason text,
  before_state jsonb,
  requested jsonb,
  after_state jsonb,
  verification jsonb,
  action_key text,
  created_at timestamptz
);

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
  v_snapshot jsonb;
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
  v_snapshot:=public.get_pdc_email_vehicle_location_snapshot();
  WITH snapshot_vehicles AS (
    SELECT
      (v->>'id')::uuid AS vehicle_id,
      v->>'stock_number' AS stock_number,
      v->>'vehicle_description' AS vehicle_description,
      v->>'current_location' AS current_location,
      v->>'version' AS vehicle_version
    FROM jsonb_array_elements(coalesce(v_snapshot#>'{data,vehicles}','[]'::jsonb)) v
    WHERE (v->>'id') IS NOT NULL
  ),
  selected AS (
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
      LEFT JOIN snapshot_vehicles sv ON sv.vehicle_id=groups.vehicle_id
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


CREATE OR REPLACE FUNCTION public.inbox_page_reference_vehicle(p_vehicle_id uuid)
RETURNS TABLE (
  vehicle_id uuid,
  stock_number text,
  vehicle_description text,
  current_location text,
  vehicle_version text
)
LANGUAGE plpgsql STABLE AS $reference$
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
  WHERE (p_vehicle_id IS NULL OR v.id = p_vehicle_id)
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
    );
END
$reference$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'vehicles', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id', s.vehicle_id,
          'stock_number', s.stock_number,
          'vehicle_description', s.vehicle_description,
          'current_location', s.current_location,
          'version', CASE WHEN s.vehicle_version ~ '^[0-9]+$' THEN to_jsonb(s.vehicle_version::int) ELSE 'null'::jsonb END
        ))
        FROM public.inbox_page_reference_vehicle(NULL) s
      ), '[]'::jsonb)
    )
  );
$$;

BEGIN;
INSERT INTO public.vehicles (
  id, stock_number, vehicle_description, current_location, version, deleted_at,
  lifecycle_state, visible_on_board, rft_collected_at, source_system, source_batch_id,
  source_record_id, source_payload
) VALUES
  ('a1000000-0000-4000-8000-000000000001', 'TUNE-001', 'Original tune description', 'PMB', 7, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000002', 'PLAIN-001', 'Plain description', 'Yard Hold', 3, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000003', 'DEL-001', 'Deleted description', 'Completed', 1, now(), 'completed', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000004', 'HIDDEN-001', 'Hidden description', 'Yard', 2, NULL, 'active', false, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000005', 'COL-HIST', 'Collected with history', 'Collected', 4, NULL, 'active', false, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000006', 'COL-NONE', 'Collected without history', 'Collected', 5, NULL, 'active', false, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000007', 'COL-RCPT', 'Collected with receipt', 'Collected', 6, NULL, 'active', false, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000008', 'DONE-HOLD', 'Completed hold', 'Yard', 8, NULL, 'completed', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000009', 'HOLD-001', 'Active hold', 'Yard Hold', 9, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-00000000000a', 'UNDO-YARD', 'Undo yard', 'Yard', 10, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-00000000000b', 'UNDO-DONE', 'Undo completed', 'Yard', 11, NULL, 'completed', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-00000000000c', 'HERMES-TEST-001', 'Hermes description', 'Yard', 12, NULL, 'active', true, NULL, 'hermes_overnight_synthetic', 'HERMES-TEST-RUN-20260824', 'HERMES-TEST-001', '{"contract":"pdc-overnight-synthetic-fleet-363/render_only"}'::jsonb),
  ('a1000000-0000-4000-8000-00000000000d', 'SUBLET-001', 'Sublet description', 'Yard', 13, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-00000000000e', 'PIL-001', 'Pilbara description', 'Yard', 14, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-00000000000f', 'PIL-MIS', 'Pilbara mismatch', 'Yard', 15, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000010', 'PRE168-DONE', 'Pre168 completed', 'Yard', 16, NULL, 'completed', true, now(), NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000011', 'EXT-DONE', 'External completion', 'Completed', 17, NULL, 'completed', false, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000012', 'SUBLET-BOOK', 'Sublet booking', 'Yard', 18, NULL, 'active', true, NULL, NULL, NULL, NULL, NULL),
  ('a1000000-0000-4000-8000-000000000013', 'RFT-BARE', 'Bare RFT', 'Yard', 19, NULL, 'rft', true, NULL, NULL, NULL, NULL, NULL);

INSERT INTO public.pdc_authenticated_email_import_receipts (receipt_id, vehicle_id) VALUES
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000004'),
  ('b1000000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-000000000009'),
  ('b1000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-00000000000a'),
  ('b1000000-0000-4000-8000-00000000000b', 'a1000000-0000-4000-8000-00000000000b'),
  ('b1000000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-000000000010');
INSERT INTO public.pdc_new_vehicle_reviews (vehicle_id, source_kind) VALUES
  ('a1000000-0000-4000-8000-000000000001', 'tune_pmg');
INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700 (vehicle_id, action) VALUES
  ('a1000000-0000-4000-8000-000000000007', 'collected');
INSERT INTO pdc_codex_intake_private.owner_board_visibility_holds_20261019 (vehicle_id, stock_number, released_at) VALUES
  ('a1000000-0000-4000-8000-000000000008', 'DONE-HOLD', NULL),
  ('a1000000-0000-4000-8000-000000000009', 'HOLD-001', NULL);
INSERT INTO public.pdc_owner_supplied_document_receipts_396 (receipt_id, vehicle_id, canonical_import_receipt_id) VALUES
  ('c1000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-00000000000a', 'b1000000-0000-4000-8000-00000000000a'),
  ('c1000000-0000-4000-8000-00000000000b', 'a1000000-0000-4000-8000-00000000000b', 'b1000000-0000-4000-8000-00000000000b');
INSERT INTO public.pdc_owner_supplied_document_undo_receipts_396 (receipt_id) VALUES
  ('c1000000-0000-4000-8000-00000000000a'),
  ('c1000000-0000-4000-8000-00000000000b');
INSERT INTO public.pdc_overnight_synthetic_fleet_registry_363 (run_id, vehicle_id, stock_number) VALUES
  ('HERMES-TEST-RUN-20260824', 'a1000000-0000-4000-8000-00000000000c', 'HERMES-TEST-001');
INSERT INTO public.vehicle_work_items (vehicle_id, work_key, required) VALUES
  ('a1000000-0000-4000-8000-00000000000d', 'Sublet', true);
INSERT INTO public.pdc_pilbara_service_operations (operation_id, vehicle_id, stock_number) VALUES
  ('d2000000-0000-4000-8000-00000000000e', 'a1000000-0000-4000-8000-00000000000e', 'PIL-001'),
  ('d2000000-0000-4000-8000-00000000000f', 'a1000000-0000-4000-8000-00000000000f', 'OTHER-STOCK');
INSERT INTO public.pdc_rft_transport_action_receipts_412 (vehicle_id, action) VALUES
  ('a1000000-0000-4000-8000-000000000010', 'collected');
INSERT INTO public.pdc_external_completion_receipts_20260903 (vehicle_id, completed_at) VALUES
  ('a1000000-0000-4000-8000-000000000011', now());
INSERT INTO public.pdc_sublet_bookings (vehicle_id) VALUES
  ('a1000000-0000-4000-8000-000000000012');

INSERT INTO public.pdc_email_ai_successor_ui_revision (singleton, revision) VALUES (true, 4);
INSERT INTO public.ai_email_intake (
  id, received_at, created_at, provider_uid, graph_message_id, internet_message_id,
  graph_thread_id, source_hash, extracted_data, sender_email, subject, raw_body,
  permanent_failure, queue_attempts, retry_class, next_attempt_at, last_error_code
) VALUES (
  'd1000000-0000-4000-8000-000000000001',
  '2026-10-19 01:02:03+00', '2026-10-19 01:02:04+00', 'provider-synthetic', 'graph-synthetic',
  'internet-synthetic', 'thread-synthetic', repeat('ab', 32), '{}'::jsonb,
  'synthetic@example.test', 'Synthetic inbox proof', 'synthetic body',
  false, 0, NULL, NULL, NULL
);
INSERT INTO public.pdc_email_ai_successor_transaction_receipts (
  transaction_id, source_receipt_id, source_digest, evidence_digest, plan_hash,
  typed_plan, aggregate_disposition, readback_parity, response
) VALUES (
  'e1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  repeat('ab', 32), 'evidence', 'plan',
  '{"instructions":[]}'::jsonb, 'SUCCESS', true,
  '{"actions":[],"readback_parity":true,"model_version":"synthetic"}'::jsonb
);
INSERT INTO public.pdc_email_ai_successor_action_receipts (
  action_receipt_id, transaction_id, vehicle_id, action_type, instruction_id,
  canonical_rpc, disposition, reason, before_state, requested, after_state,
  verification, action_key, created_at
)
SELECT
  ('f1000000-0000-4000-8000-' || lpad(to_hex(row_number() OVER (ORDER BY id)), 12, '0'))::uuid,
  'e1000000-0000-4000-8000-000000000001',
  id, 'note', 'instruction-synthetic', 'synthetic_rpc', 'SUCCESS', NULL,
  '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'action-' || stock_number,
  '2026-10-19 01:03:00+00'
FROM public.vehicles;

CREATE TEMP TABLE inbox_capture (label text PRIMARY KEY, result jsonb);
INSERT INTO inbox_capture
SELECT 'old_unauth', public.get_pdc_email_ai_transaction_successor_inbox_v2(NULL, 100);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000099', true);
INSERT INTO inbox_capture
SELECT 'old', public.get_pdc_email_ai_transaction_successor_inbox_v2(NULL, 100);

\ir ../supabase/migrations/20261019231000_inbox_page_vehicles.sql

SELECT set_config('request.jwt.claim.sub', '', true);
INSERT INTO inbox_capture
SELECT 'new_unauth', public.get_pdc_email_ai_transaction_successor_inbox_v2(NULL, 100);
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-4000-8000-000000000099', true);
INSERT INTO inbox_capture
SELECT 'new', public.get_pdc_email_ai_transaction_successor_inbox_v2(NULL, 100);

DO $proof$
DECLARE
  old_result jsonb;
  new_result jsonb;
  old_unauth jsonb;
  new_unauth jsonb;
  expected record;
  found jsonb;
  version_text text;
BEGIN
  SELECT result INTO old_unauth FROM inbox_capture WHERE label = 'old_unauth';
  SELECT result INTO new_unauth FROM inbox_capture WHERE label = 'new_unauth';
  SELECT result INTO old_result FROM inbox_capture WHERE label = 'old';
  SELECT result INTO new_result FROM inbox_capture WHERE label = 'new';
  IF old_unauth->>'code' IS DISTINCT FROM 'successor_inbox_unauthorized'
     OR new_unauth->>'code' IS DISTINCT FROM 'successor_inbox_unauthorized'
     OR md5(old_unauth::text) IS DISTINCT FROM md5(new_unauth::text) THEN
    RAISE EXCEPTION 'unauthorized envelopes diverged % %', old_unauth, new_unauth;
  END IF;
  IF old_result->>'ok' IS DISTINCT FROM 'true'
     OR new_result->>'ok' IS DISTINCT FROM 'true'
     OR new_result->>'code' IS DISTINCT FROM 'successor_inbox_snapshot' THEN
    RAISE EXCEPTION 'authorized envelope changed %', new_result;
  END IF;
  IF md5((old_result->'items')::text) IS DISTINCT FROM md5((new_result->'items')::text) THEN
    RAISE EXCEPTION 'items md5 diverged old % new %', old_result->'items', new_result->'items';
  END IF;
  IF jsonb_array_length(new_result->'items') IS DISTINCT FROM 1
     OR jsonb_array_length(new_result->'items'->0->'vehicle_results') IS DISTINCT FROM 19 THEN
    RAISE EXCEPTION 'page shape changed %', new_result->'items';
  END IF;
  FOR expected IN
    SELECT * FROM (VALUES
      ('a1000000-0000-4000-8000-000000000001'::uuid, 'MATCHED', 'TUNE-001', 'Tune rewritten description', 'PMB'),
      ('a1000000-0000-4000-8000-000000000002'::uuid, 'MATCHED', 'PLAIN-001', 'Plain description', 'Yard Hold'),
      ('a1000000-0000-4000-8000-000000000003'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-000000000004'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-000000000005'::uuid, 'MATCHED', 'COL-HIST', 'Collected with history', 'Collected'),
      ('a1000000-0000-4000-8000-000000000006'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-000000000007'::uuid, 'MATCHED', 'COL-RCPT', 'Collected with receipt', 'Collected'),
      ('a1000000-0000-4000-8000-000000000008'::uuid, 'MATCHED', 'DONE-HOLD', 'Completed hold', 'Yard'),
      ('a1000000-0000-4000-8000-000000000009'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-00000000000a'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-00000000000b'::uuid, 'MATCHED', 'UNDO-DONE', 'Undo completed', 'Yard'),
      ('a1000000-0000-4000-8000-00000000000c'::uuid, 'MATCHED', 'HERMES-TEST-001', 'Hermes description', 'Yard'),
      ('a1000000-0000-4000-8000-00000000000d'::uuid, 'MATCHED', 'SUBLET-001', 'Sublet description', 'Yard'),
      ('a1000000-0000-4000-8000-00000000000e'::uuid, 'MATCHED', 'PIL-001', 'Pilbara description', 'Yard'),
      ('a1000000-0000-4000-8000-00000000000f'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—'),
      ('a1000000-0000-4000-8000-000000000010'::uuid, 'MATCHED', 'PRE168-DONE', 'Pre168 completed', 'Yard'),
      ('a1000000-0000-4000-8000-000000000011'::uuid, 'MATCHED', 'EXT-DONE', 'External completion', 'Completed'),
      ('a1000000-0000-4000-8000-000000000012'::uuid, 'MATCHED', 'SUBLET-BOOK', 'Sublet booking', 'Yard'),
      ('a1000000-0000-4000-8000-000000000013'::uuid, 'UNRESOLVED', 'Unresolved stock', 'Vehicle identity unavailable', '—')
    ) AS e(vehicle_id, identity_status, stock, vehicle, location)
  LOOP
    SELECT x INTO found
    FROM jsonb_array_elements(new_result->'items'->0->'vehicle_results') x
    WHERE (x->>'vehicle_id')::uuid = expected.vehicle_id;
    IF found IS NULL
       OR found->>'identity_status' IS DISTINCT FROM expected.identity_status
       OR found->>'stock' IS DISTINCT FROM expected.stock
       OR found->>'vehicle' IS DISTINCT FROM expected.vehicle
       OR found->>'location' IS DISTINCT FROM expected.location THEN
      RAISE EXCEPTION 'vehicle % rendered % expected %', expected.vehicle_id, found, expected;
    END IF;
  END LOOP;
  SELECT s.vehicle_version INTO version_text
  FROM public.pdc_email_inbox_snapshot_vehicle('a1000000-0000-4000-8000-000000000001') s;
  IF version_text IS DISTINCT FROM '7' THEN
    RAISE EXCEPTION 'tune version text changed to %', version_text;
  END IF;
  IF EXISTS (SELECT 1 FROM public.pdc_email_inbox_snapshot_vehicle('a1000000-0000-4000-8000-000000000003')) THEN
    RAISE EXCEPTION 'deleted vehicle was returned by the page lookup';
  END IF;
END
$proof$;
ROLLBACK;
