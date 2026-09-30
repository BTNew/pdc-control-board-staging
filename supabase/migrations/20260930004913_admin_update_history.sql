-- Administrator-only history of committed import receipts. Never returns payloads,
-- filenames, email subjects, senders, customer identities, or receipt identifiers.
CREATE OR REPLACE FUNCTION public.get_pdc_update_history()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id = auth.uid()
      AND r.role::text = 'administrator'
      AND r.active IS TRUE AND r.account_status = 'approved'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'permission_denied');
  END IF;

  WITH feed_definitions(feed_key, label, sort_order) AS (
    VALUES
      ('broome_navision', 'Broome Navision Update', 1),
      ('pilbara_navision', 'Pilbara Navision Update', 2),
      ('other_navision', 'Other codes Navision Update', 3),
      ('service_codes', 'Service Codes update', 4),
      ('parts_info', 'Parts info update', 5)
  ),
  -- A combined upload has real child batch IDs. Group by this durable receipt
  -- identity, never just by coincident timestamps or a user-supplied filename.
  combined_child_candidates AS (
    SELECT c.actor_id::text || ':' || c.idempotency_key AS event_key,
           child #>> '{result,data,batch_id}' AS batch_id
    FROM pdc_navision_combined_private.receipts c
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(c.response #> '{data,dealer_receipts}') = 'array'
           THEN c.response #> '{data,dealer_receipts}' ELSE '[]'::jsonb END
    ) child
    WHERE c.response->>'ok' = 'true' AND c.response->>'code' = 'applied'
  ),
  combined_children AS (
    SELECT batch_id, min(event_key) AS event_key
    FROM combined_child_candidates WHERE batch_id IS NOT NULL
    GROUP BY batch_id HAVING count(DISTINCT event_key) = 1
  ),
  navision_batches AS (
    SELECT b.*,
      CASE b.dealer_code WHEN '37047' THEN 'broome_navision'
                        WHEN '14450' THEN 'pilbara_navision'
                        ELSE 'other_navision' END AS feed_key,
      coalesce('combined:' || c.event_key, 'batch:' || b.id::text) AS event_key
    FROM public.navision_import_batches b
    LEFT JOIN combined_children c ON c.batch_id = b.id::text
    WHERE b.source_system = 'microsoft_navision'
      AND b.dealer_code IN ('37047', '14450', '002345', '001234')
  ),
  navision_events AS (
    SELECT n.feed_key, n.event_key,
      CASE WHEN bool_and(n.status = 'applied' AND coalesce(n.receipt->>'ok' = 'true', false))
           THEN max(n.applied_at) END AS completed_at,
      greatest(max(n.applied_at), max(n.rolled_back_at)) AS attempted_at,
      CASE WHEN NOT bool_and(n.status = 'applied' AND coalesce(n.receipt->>'ok' = 'true', false))
             THEN 'rolled_back'
           WHEN sum(n.invalid_count + n.conflict_count) > 0
             THEN 'completed_with_warnings'
           ELSE 'completed' END AS status,
      sum(n.total_rows)::bigint AS record_count,
      format('Dealer codes %s; %s new, %s changed, %s unchanged, %s missing from this update, %s invalid, %s conflicts.',
        string_agg(DISTINCT n.dealer_code, ', ' ORDER BY n.dealer_code),
        sum(n.new_count), sum(n.changed_count), sum(n.unchanged_count),
        sum(n.missing_count), sum(n.invalid_count), sum(n.conflict_count)) AS detail
    FROM navision_batches n GROUP BY n.feed_key, n.event_key
  ),
  -- These are service-workbook operation imports, not a reference-code catalogue.
  -- Require both the apply batch and its committed successful apply receipt.
  service_candidates AS (
    SELECT b.*,
      coalesce(nullif(b.source_link->>'workbook_sha256', ''),
               nullif(b.response->>'workbook_sha256', ''), b.source_hash) AS workbook_key,
      r.created_at AS completed_at
    FROM public.pdc_pilbara_service_import_batches b
    JOIN public.pdc_pilbara_service_import_receipts r ON r.batch_id = b.batch_id
      AND r.receipt_kind = 'apply' AND r.outcome->>'ok' = 'true'
      AND r.outcome->>'code' = 'applied'
    WHERE b.batch_kind = 'apply' AND b.response->>'ok' = 'true'
      AND b.response->>'code' = 'applied'
      AND b.importer_version = 'pilbara_service_open_jobcards_v1'
  ),
  service_partitions AS (
    -- Replaying the same partition must not multiply the workbook row count.
    SELECT DISTINCT ON (workbook_key, source_hash) *
    FROM service_candidates
    ORDER BY workbook_key, source_hash, completed_at DESC, batch_id DESC
  ),
  service_events AS (
    SELECT 'service_codes'::text AS feed_key, 'service:' || workbook_key AS event_key,
      max(completed_at) AS completed_at, max(completed_at) AS attempted_at,
      CASE WHEN sum(quarantined_line_count + unmatched_stock_count +
                    ambiguous_stock_count + conflict_count) > 0
           THEN 'completed_with_warnings' ELSE 'completed' END AS status,
      sum(source_row_count)::bigint AS record_count,
      format('%s accepted, %s held for review; %s unmatched, %s ambiguous, %s conflicts across %s committed batches.',
        sum(accepted_line_count), sum(quarantined_line_count),
        sum(unmatched_stock_count), sum(ambiguous_stock_count),
        sum(conflict_count), count(*)) AS detail
    FROM service_partitions GROUP BY workbook_key
  ),
  service_previews AS (
    SELECT 'service_codes'::text AS feed_key, 'preview:' || b.batch_id::text AS event_key,
      NULL::timestamptz AS completed_at, b.created_at AS attempted_at,
      'preview'::text AS status, b.source_row_count::bigint AS record_count,
      'Preview only; not a completed update.'::text AS detail
    FROM public.pdc_pilbara_service_import_batches b
    WHERE b.batch_kind = 'preview' AND b.importer_version = 'pilbara_service_open_jobcards_v1'
  ),
  parts_receipts AS MATERIALIZED (
    SELECT r.* FROM pdc_parts_private.receipts r
    WHERE r.response->>'ok' = 'true' AND r.imported_at IS NOT NULL
    ORDER BY r.imported_at DESC, r.id DESC LIMIT 20
  ),
  parts_counts AS (
    SELECT r.id, count(rr.row_number)::bigint AS source_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'updated') AS updated_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'unchanged') AS unchanged_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'unmatched') AS unmatched_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'ambiguous') AS ambiguous_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'invalid') AS invalid_rows,
      count(rr.row_number) FILTER (WHERE rr.outcome = 'stale') AS stale_rows
    FROM parts_receipts r
    LEFT JOIN pdc_parts_private.row_results rr ON rr.receipt_id = r.id
    WHERE r.response->>'ok' = 'true' GROUP BY r.id
  ),
  parts_events AS (
    SELECT 'parts_info'::text AS feed_key, 'parts:' || r.id::text AS event_key,
      r.imported_at AS completed_at, r.imported_at AS attempted_at,
      CASE WHEN p.unmatched_rows + p.ambiguous_rows + p.invalid_rows + p.stale_rows > 0
           THEN 'completed_with_warnings' ELSE 'completed' END AS status,
      p.source_rows AS record_count,
      format('%s; %s updated, %s unchanged, %s unmatched, %s ambiguous, %s invalid, %s older rows skipped.',
        CASE r.source_kind
          WHEN 'gmail_csv' THEN 'Email import'
          WHEN 'authorised_gmail_workbook' THEN 'Email workbook'
          WHEN 'user_attached_workbook' THEN 'Manual workbook'
          ELSE 'Recorded import' END,
        p.updated_rows, p.unchanged_rows, p.unmatched_rows,
        p.ambiguous_rows, p.invalid_rows, p.stale_rows) AS detail
    FROM parts_receipts r JOIN parts_counts p ON p.id = r.id
    WHERE r.response->>'ok' = 'true' AND r.imported_at IS NOT NULL
  ),
  events AS MATERIALIZED (
    SELECT * FROM navision_events UNION ALL
    SELECT * FROM service_events UNION ALL
    SELECT * FROM service_previews UNION ALL
    SELECT * FROM parts_events
  ),
  latest_success AS (
    SELECT DISTINCT ON (feed_key) *
    FROM events WHERE completed_at IS NOT NULL
      AND status IN ('completed', 'completed_with_warnings')
    ORDER BY feed_key, completed_at DESC, event_key DESC
  ),
  latest_attempt AS (
    SELECT DISTINCT ON (feed_key) *
    FROM events ORDER BY feed_key, attempted_at DESC NULLS LAST, event_key DESC
  ),
  recent_history AS (
    SELECT e.* FROM events e
    WHERE e.completed_at IS NOT NULL
      AND e.status IN ('completed', 'completed_with_warnings')
    ORDER BY e.completed_at DESC, e.feed_key, e.event_key DESC LIMIT 20
  )
  SELECT jsonb_build_object(
    'ok', true,
    'generated_at', statement_timestamp(),
    'feeds', (
      SELECT jsonb_agg(jsonb_build_object(
        'key', d.feed_key, 'label', d.label,
        'last_success_at', s.completed_at, 'last_success_status', s.status,
        'last_attempt_at', a.attempted_at,
        'last_status', coalesce(a.status, 'not_recorded'),
        'record_count', s.record_count,
        'detail', coalesce(s.detail, 'No completed update recorded.')
      ) ORDER BY d.sort_order)
      FROM feed_definitions d
      LEFT JOIN latest_success s ON s.feed_key = d.feed_key
      LEFT JOIN latest_attempt a ON a.feed_key = d.feed_key
    ),
    'history', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'feed_key', h.feed_key, 'completed_at', h.completed_at,
        'status', h.status, 'record_count', h.record_count, 'detail', h.detail
      ) ORDER BY h.completed_at DESC, h.feed_key, h.event_key DESC), '[]'::jsonb)
      FROM recent_history h
    )
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_update_history() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_update_history() TO authenticated;
COMMENT ON FUNCTION public.get_pdc_update_history() IS
'Admin-only metadata from committed import receipts. Five fixed feeds; latest-success counts remain separate from later previews. History is capped at 20. No source or customer payloads.';
