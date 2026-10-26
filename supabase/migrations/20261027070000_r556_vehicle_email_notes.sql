-- r556 (F170). Approved go-live 26 Oct 2026. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- Rebased onto main ffd87797 (r555 / F169 / sort 330). Never applied as r543. r543 / F157 / sort 321 is not reused.
-- The parts importer and the new-addition routing functions are not edited.
-- 26 Oct 2026 10:45 AWST: board facts from pdc@ emails do not appear on the vehicle card.
-- 26 Oct 2026, relayed by Kajel: every board-relevant pdc@ email is attached to the vehicle and
-- shows in the Parts ETA section. This is not the Stoppages bucket. It does not move the vehicle
-- and it does not change any status. The first case is stock 13057027 (fbafc3cd-09ff-414d-a29a-60529c0d3fca):
-- a Prado, key 209, at PMB. Talin says the bull bar is still waiting, due this week, and the board
-- shows parts received. The warning does not take it out of PMB.
-- append_vehicle_timeline_event is pinned (ef3bd3587978f25862546483913231e4, r421) and requires
-- auth.uid(), so the hourly importer does not call it. This release writes the timeline row itself.
-- It does not create a vehicle or a job. Pin count stays 241.
-- r555 took sort 330. This check is sort 331.
-- After go-live the importer backfills 13000779, 13115427, 13047406, 13070395, 12311152 and
-- 13128722 through 13128725. Each add, clear and stock read is an index lookup. A batch of at
-- most 100 items is one call. A missing stock is reported and is not created.
-- Add:    record_pdc_vehicle_email_556(text, uuid, text, text, text, timestamptz, text, text, text, text, text)
-- Clear:  clear_pdc_vehicle_email_556(text)
-- Read:   list_pdc_vehicle_email_warnings_556(text)
-- Batch:  apply_pdc_vehicle_email_batch_556(jsonb)
-- Undo: supabase/rollbacks/20261027070000_r556_vehicle_email_notes.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r556: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r556: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r556: pin count is not 241'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event') IS DISTINCT FROM 'ef3bd3587978f25862546483913231e4' THEN RAISE EXCEPTION 'r556: append_vehicle_timeline_event is not the pinned body'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=331 OR fault_id='F170' OR check_name='vehicle_email_notes_556' OR added_in='r556') THEN RAISE EXCEPTION 'r556: sort 331 or F170 is taken'; END IF;
 IF to_regclass('public.vehicle_timeline_events') IS NULL THEN RAISE EXCEPTION 'r556: timeline table missing'; END IF;
 IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='vehicle_timeline_events' AND indexdef ILIKE '%source_email_id%') THEN RAISE EXCEPTION 'r556: a source email index already exists'; END IF;
END $g$;

CREATE UNIQUE INDEX vehicle_timeline_events_source_email_556
  ON public.vehicle_timeline_events (source_email_id)
  WHERE source_email_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.record_pdc_vehicle_email_556(
  p_stock text,
  p_vehicle_id uuid,
  p_message_id text,
  p_from_address text,
  p_to_address text,
  p_received_at timestamp with time zone,
  p_subject text,
  p_snippet text,
  p_category text,
  p_summary text DEFAULT NULL,
  p_quote text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $note556$
DECLARE
  existing_id uuid;
  existing_vehicle uuid;
  new_id uuid;
  vehicle_id uuid;
  vehicle_stock text;
  vehicle_count integer := 0;
  existing_cleared boolean := false;
  message_id text := btrim(coalesce(p_message_id, ''));
  snippet_text text := btrim(coalesce(p_snippet, ''));
  summary_text text := btrim(coalesce(p_summary, ''));
  quote_text text := btrim(coalesce(p_quote, ''));
  subject_text text := btrim(coalesce(p_subject, ''));
  to_text text := btrim(coalesce(p_to_address, ''));
  from_raw text := btrim(coalesce(p_from_address, ''));
  from_email text := lower(coalesce(substring(from_raw from '<([^<>[:space:]]+)>'), ''));
  from_name text;
  stock_token text := btrim(coalesce(p_stock, ''));
  service_ok boolean := coalesce(auth.role(), '') = 'service_role' OR coalesce(current_user, '') = 'service_role';
  controller_ok boolean := coalesce(public.is_pdc_role('operator'::public.pdc_role), false)
    OR coalesce(public.is_pdc_role('administrator'::public.pdc_role), false);
BEGIN
  IF NOT (
    service_ok
    OR controller_ok
    OR coalesce(pdc_codex_intake_private.management_connection(), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_category IS NULL OR p_category NOT IN (
    'parts_eta', 'waiting_parts', 'stoppage', 'parts_complete',
    'cancellation', 'job_card_problem', 'po_received', 'other'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'category_not_allowed');
  END IF;
  IF message_id = '' OR length(message_id) < 8 OR length(message_id) > 512 OR message_id ~ '[[:space:]]' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_id_required');
  END IF;
  IF from_email = '' THEN from_email := lower(from_raw); END IF;
  from_name := nullif(btrim(regexp_replace(from_raw, '<[^>]*>', '', 'g')), '');
  IF from_name IS NOT NULL AND lower(from_name) = from_email THEN from_name := NULL; END IF;
  IF from_email !~ '^[^[:space:]@]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'sender_required');
  END IF;
  IF to_text = '' OR length(to_text) > 1000 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'to_required');
  END IF;
  IF snippet_text = '' OR length(snippet_text) > 4000 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'snippet_required');
  END IF;
  IF length(summary_text) > 2000 OR length(quote_text) > 2000 OR length(subject_text) > 500 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'note_text_too_long');
  END IF;
  IF p_received_at IS NULL OR p_received_at < '2020-01-01T00:00:00Z' OR p_received_at > pg_catalog.clock_timestamp() + interval '5 minutes' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'received_at_required');
  END IF;
  IF summary_text = '' THEN summary_text := left(snippet_text, 240); END IF;
  IF quote_text = '' THEN quote_text := snippet_text; END IF;
  IF p_vehicle_id IS NOT NULL THEN
    SELECT v.id, v.stock_number INTO vehicle_id, vehicle_stock
    FROM public.vehicles v
    WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
    END IF;
    IF stock_token <> '' AND btrim(vehicle_stock) IS DISTINCT FROM stock_token THEN
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_stock_mismatch');
    END IF;
  ELSIF stock_token <> '' THEN
    -- Equality on stock_number uses vehicles_stock_idx. At most two rows are read.
    FOR vehicle_id, vehicle_stock IN
      SELECT v.id, v.stock_number
      FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND v.stock_number = stock_token
      LIMIT 2
    LOOP
      vehicle_count := vehicle_count + 1;
    END LOOP;
    IF vehicle_count = 0 THEN
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
    END IF;
    IF vehicle_count <> 1 THEN
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_ambiguous');
    END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_required');
  END IF;
  SELECT e.id, e.vehicle_id, (coalesce(e.structured_data->>'cleared', 'false') = 'true')
    INTO existing_id, existing_vehicle, existing_cleared
  FROM public.vehicle_timeline_events e
  WHERE e.source_email_id = message_id
  LIMIT 1;
  IF FOUND AND existing_vehicle IS DISTINCT FROM vehicle_id THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_already_on_another_vehicle', 'event_id', existing_id, 'action', 'add');
  END IF;
  IF FOUND THEN
    -- The same message id does not add a second warning and does not reopen a cleared one.
    RETURN jsonb_build_object('ok', true, 'replay', true, 'action', 'add', 'cleared', existing_cleared, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
  END IF;
  -- Timeline row only. This is not the Stoppages bucket. Location, key and every status stay as they are.
  INSERT INTO public.vehicle_timeline_events (
    vehicle_id, event_type, event_at, source_kind, event_state,
    source_system, source_mailbox, source_email_id, sender_name, sender_email,
    recipient_mailbox, subject, ai_summary, original_statement, structured_data,
    confidence_label, automatic_update, new_values, previous_values, created_by
  ) VALUES (
    vehicle_id, p_category, p_received_at,
    'email'::public.vehicle_timeline_source_kind,
    'confirmed'::public.vehicle_timeline_event_state,
    'email_note_556', 'pdc@pmgwa.com.au', message_id,
    from_name, from_email,
    left(to_text, 320), nullif(subject_text, ''),
    summary_text, quote_text,
    jsonb_build_object(
      'category', p_category, 'source', 'email_note_556',
      'to_address', to_text, 'snippet', snippet_text
    ),
    'high_confidence', false, '{}'::jsonb, '{}'::jsonb, auth.uid()
  )
  ON CONFLICT (source_email_id) WHERE source_email_id IS NOT NULL DO NOTHING
  RETURNING id INTO new_id;
  IF new_id IS NULL THEN
    SELECT e.id, e.vehicle_id, (coalesce(e.structured_data->>'cleared', 'false') = 'true')
      INTO existing_id, existing_vehicle, existing_cleared
    FROM public.vehicle_timeline_events e
    WHERE e.source_email_id = message_id
    LIMIT 1;
    IF existing_vehicle IS DISTINCT FROM vehicle_id THEN
      RETURN jsonb_build_object('ok', false, 'code', 'message_already_on_another_vehicle', 'event_id', existing_id, 'action', 'add');
    END IF;
    RETURN jsonb_build_object('ok', true, 'replay', true, 'action', 'add', 'cleared', existing_cleared, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
  END IF;
  RETURN jsonb_build_object('ok', true, 'replay', false, 'action', 'add', 'cleared', false, 'event_id', new_id, 'vehicle_id', vehicle_id, 'stock_number', vehicle_stock, 'category', p_category, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
END
$note556$;

REVOKE ALL ON FUNCTION public.record_pdc_vehicle_email_556(text, uuid, text, text, text, timestamp with time zone, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_pdc_vehicle_email_556(text, uuid, text, text, text, timestamp with time zone, text, text, text, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_vehicle_email_notes_556(p_vehicle_id uuid)
RETURNS TABLE (
  event_at timestamp with time zone,
  category text,
  summary text,
  quote text,
  sender_name text,
  sender_email text,
  to_address text,
  source_email_id text,
  subject text,
  snippet text,
  conflicts boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $list556$
DECLARE
  board_received boolean;
BEGIN
  IF NOT (
    public.is_pdc_role('operator'::public.pdc_role)
    OR public.is_pdc_role('administrator'::public.pdc_role)
  ) THEN
    RETURN;
  END IF;
  SELECT u.parts_received INTO board_received
  FROM public.vehicle_parts_updates u
  WHERE u.vehicle_id = p_vehicle_id
  ORDER BY u.updated_at DESC NULLS LAST
  LIMIT 1;
  RETURN QUERY
  SELECT e.event_at, e.event_type, e.ai_summary, e.original_statement,
         e.sender_name, e.sender_email,
         coalesce(e.structured_data->>'to_address', e.recipient_mailbox),
         e.source_email_id, e.subject,
         coalesce(e.structured_data->>'snippet', e.original_statement),
         CASE
           WHEN e.event_type IN ('waiting_parts', 'parts_eta') AND coalesce(board_received, false) THEN true
           WHEN e.event_type = 'parts_complete' AND NOT coalesce(board_received, false) THEN true
           ELSE false
         END
  FROM public.vehicle_timeline_events e
  WHERE e.vehicle_id = p_vehicle_id
    AND e.source_email_id IS NOT NULL
    AND e.structured_data->>'source' = 'email_note_556'
    AND coalesce(e.structured_data->>'cleared', 'false') <> 'true'
    AND e.event_type IN (
      'parts_eta', 'waiting_parts', 'stoppage', 'parts_complete',
      'cancellation', 'job_card_problem', 'po_received', 'other'
    )
  ORDER BY e.event_at DESC, e.created_at DESC
  LIMIT 50;
END
$list556$;

REVOKE ALL ON FUNCTION public.list_vehicle_email_notes_556(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_vehicle_email_notes_556(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.clear_pdc_vehicle_email_556(p_message_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $clear556$
DECLARE
  message_id text := btrim(coalesce(p_message_id, ''));
  existing_id uuid;
  existing_vehicle uuid;
  service_ok boolean := coalesce(auth.role(), '') = 'service_role' OR coalesce(current_user, '') = 'service_role';
  controller_ok boolean := coalesce(public.is_pdc_role('operator'::public.pdc_role), false)
    OR coalesce(public.is_pdc_role('administrator'::public.pdc_role), false);
BEGIN
  IF NOT (
    service_ok
    OR controller_ok
    OR coalesce(pdc_codex_intake_private.management_connection(), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized', 'action', 'clear');
  END IF;
  IF message_id = '' OR length(message_id) < 8 OR length(message_id) > 512 OR message_id ~ '[[:space:]]' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_id_required', 'action', 'clear');
  END IF;
  -- One unique-index lookup. A second clear of the same message id does not write.
  UPDATE public.vehicle_timeline_events e
  SET structured_data = e.structured_data || jsonb_build_object('cleared', true, 'cleared_at', pg_catalog.to_jsonb(pg_catalog.clock_timestamp()))
  WHERE e.source_email_id = message_id
    AND e.structured_data->>'source' = 'email_note_556'
    AND coalesce(e.structured_data->>'cleared', 'false') <> 'true'
  RETURNING e.id, e.vehicle_id INTO existing_id, existing_vehicle;
  IF existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'replay', false, 'action', 'clear', 'cleared', true, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
  END IF;
  SELECT e.id, e.vehicle_id INTO existing_id, existing_vehicle
  FROM public.vehicle_timeline_events e
  WHERE e.source_email_id = message_id
    AND e.structured_data->>'source' = 'email_note_556'
    AND coalesce(e.structured_data->>'cleared', 'false') = 'true'
  LIMIT 1;
  IF existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'replay', true, 'action', 'clear', 'cleared', true, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
  END IF;
  IF EXISTS (SELECT 1 FROM public.vehicle_timeline_events e WHERE e.source_email_id = message_id) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_not_a_warning', 'action', 'clear', 'source_email_id', message_id, 'status_changed', false, 'vehicle_moved', false);
  END IF;
  RETURN jsonb_build_object('ok', true, 'replay', true, 'action', 'clear', 'found', false, 'source_email_id', message_id, 'parts_status_changed', false, 'status_changed', false, 'vehicle_moved', false);
END
$clear556$;

REVOKE ALL ON FUNCTION public.clear_pdc_vehicle_email_556(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_pdc_vehicle_email_556(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_pdc_vehicle_email_warnings_556(p_stock text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $read556$
DECLARE
  stock_token text := btrim(coalesce(p_stock, ''));
  target_id uuid;
  target_stock text;
  vehicle_count integer := 0;
  board_received boolean;
  warnings jsonb;
  service_ok boolean := coalesce(auth.role(), '') = 'service_role' OR coalesce(current_user, '') = 'service_role';
  controller_ok boolean := coalesce(public.is_pdc_role('operator'::public.pdc_role), false)
    OR coalesce(public.is_pdc_role('administrator'::public.pdc_role), false);
BEGIN
  IF NOT (
    service_ok
    OR controller_ok
    OR coalesce(pdc_codex_intake_private.management_connection(), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF stock_token = '' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_required');
  END IF;
  FOR target_id, target_stock IN
    SELECT v.id, v.stock_number
    FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND v.stock_number = stock_token
    LIMIT 2
  LOOP
    vehicle_count := vehicle_count + 1;
  END LOOP;
  IF vehicle_count = 0 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found', 'stock_number', stock_token);
  END IF;
  IF vehicle_count <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_ambiguous', 'stock_number', stock_token);
  END IF;
  SELECT u.parts_received INTO board_received
  FROM public.vehicle_parts_updates u
  WHERE u.vehicle_id = target_id
  ORDER BY u.updated_at DESC NULLS LAST
  LIMIT 1;
  SELECT coalesce(jsonb_agg(row_value ORDER BY row_at DESC), '[]'::jsonb) INTO warnings
  FROM (
    SELECT e.event_at AS row_at, jsonb_build_object(
      'message_id', e.source_email_id,
      'category', e.event_type,
      'event_at', e.event_at,
      'sender_name', e.sender_name,
      'sender_email', e.sender_email,
      'to_address', coalesce(e.structured_data->>'to_address', e.recipient_mailbox),
      'subject', e.subject,
      'snippet', coalesce(e.structured_data->>'snippet', e.original_statement),
      'conflicts', CASE
        WHEN e.event_type IN ('waiting_parts', 'parts_eta') AND coalesce(board_received, false) THEN true
        WHEN e.event_type = 'parts_complete' AND NOT coalesce(board_received, false) THEN true
        ELSE false
      END
    ) AS row_value
    FROM public.vehicle_timeline_events e
    WHERE e.vehicle_id = target_id
      AND e.source_email_id IS NOT NULL
      AND e.structured_data->>'source' = 'email_note_556'
      AND coalesce(e.structured_data->>'cleared', 'false') <> 'true'
      AND e.event_type IN (
        'parts_eta', 'waiting_parts', 'stoppage', 'parts_complete',
        'cancellation', 'job_card_problem', 'po_received', 'other'
      )
    ORDER BY e.event_at DESC, e.created_at DESC
    LIMIT 50
  ) active_rows;
  RETURN jsonb_build_object('ok', true, 'code', 'ok', 'stock_number', target_stock, 'vehicle_id', target_id, 'warnings', warnings, 'status_changed', false, 'vehicle_moved', false);
END
$read556$;

REVOKE ALL ON FUNCTION public.list_pdc_vehicle_email_warnings_556(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pdc_vehicle_email_warnings_556(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_pdc_vehicle_email_batch_556(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $batch556$
DECLARE
  item jsonb;
  action text;
  one jsonb;
  results jsonb := '[]'::jsonb;
  n integer;
  failed integer := 0;
  service_ok boolean := coalesce(auth.role(), '') = 'service_role' OR coalesce(current_user, '') = 'service_role';
  controller_ok boolean := coalesce(public.is_pdc_role('operator'::public.pdc_role), false)
    OR coalesce(public.is_pdc_role('administrator'::public.pdc_role), false);
BEGIN
  IF NOT (
    service_ok
    OR controller_ok
    OR coalesce(pdc_codex_intake_private.management_connection(), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'batch_required');
  END IF;
  n := jsonb_array_length(p_items);
  IF n > 100 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'batch_too_large', 'limit', 100);
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    action := lower(btrim(coalesce(item->>'action', '')));
    BEGIN
      IF action = 'add' THEN
        one := public.record_pdc_vehicle_email_556(
          item->>'stock',
          nullif(item->>'vehicle_id', '')::uuid,
          item->>'message_id',
          item->>'from_address',
          item->>'to_address',
          nullif(item->>'received_at', '')::timestamptz,
          item->>'subject',
          item->>'snippet',
          item->>'category',
          item->>'summary',
          item->>'quote'
        );
      ELSIF action = 'clear' THEN
        one := public.clear_pdc_vehicle_email_556(item->>'message_id');
      ELSE
        one := jsonb_build_object('ok', false, 'code', 'action_not_allowed', 'action', action);
      END IF;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN
      one := jsonb_build_object('ok', false, 'code', 'item_invalid', 'action', action);
    END;
    IF coalesce(one->>'ok', 'false') <> 'true' THEN failed := failed + 1; END IF;
    results := results || jsonb_build_array(one);
  END LOOP;
  RETURN jsonb_build_object('ok', failed = 0, 'count', n, 'failed', failed, 'results', results, 'status_changed', false, 'vehicle_moved', false);
END
$batch556$;

REVOKE ALL ON FUNCTION public.apply_pdc_vehicle_email_batch_556(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_pdc_vehicle_email_batch_556(jsonb) TO authenticated, service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('vehicle_email_notes_556', 'F170',
 'Vehicle email warnings (r556): the hourly importer, the service role, or a controller can add or clear one pdc@ email on an existing vehicle, idempotent by message id. The stock read lists the active warnings. A batch of at most 100 is one call and each item is an index lookup. This is not the Stoppages bucket: nothing moves the vehicle or changes a status. A waiting email conflicts when the board already shows parts received, as on the Prado 13057027, key 209, at PMB. No vehicle or job is created. The pinned timeline append stays put.',
 $chk556$
SELECT
 (
  pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)') IS NOT NULL
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) IS TRUE
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%management_connection()%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%service_role%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%source_email_id%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%parts_eta%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%waiting_parts%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%stoppage%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%parts_complete%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%cancellation%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%job_card_problem%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%po_received%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%parts_status_changed%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%ON CONFLICT (source_email_id) WHERE source_email_id IS NOT NULL%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) NOT LIKE '%INSERT INTO public.vehicles%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) NOT LIKE '%INSERT INTO public.workshop_bookings%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) NOT LIKE '%vehicle_parts_updates%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%v.stock_number = stock_token%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) LIKE '%vehicle_moved%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) NOT LIKE '%UPDATE public.vehicles%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)')) NOT LIKE '%current_location%'
  AND pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.list_pdc_vehicle_email_warnings_556(text)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.apply_pdc_vehicle_email_batch_556(jsonb)') IS NOT NULL
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)')) LIKE '%cleared%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)')) LIKE '%source_email_id = message_id%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)')) NOT LIKE '%UPDATE public.vehicles%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)')) NOT LIKE '%workshop_bookings%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.clear_pdc_vehicle_email_556(text)')) NOT LIKE '%vehicle_parts_updates%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_pdc_vehicle_email_warnings_556(text)')) LIKE '%v.stock_number = stock_token%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_pdc_vehicle_email_warnings_556(text)')) LIKE '%cleared%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.apply_pdc_vehicle_email_batch_556(jsonb)')) LIKE '%jsonb_array_length(p_items) > 100%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.apply_pdc_vehicle_email_batch_556(jsonb)')) NOT LIKE '%UPDATE public.vehicles%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)')) LIKE '%is_pdc_role(''operator''::public.pdc_role)%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)')) LIKE '%is_pdc_role(''administrator''::public.pdc_role)%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)')) LIKE '%waiting_parts%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)')) LIKE '%parts_received%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_556(uuid)')) LIKE '%cleared%'
  AND pg_catalog.to_regclass('public.vehicle_timeline_events_source_email_556') IS NOT NULL
  AND (SELECT i.indisunique FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid WHERE c.relname = 'vehicle_timeline_events_source_email_556') IS TRUE
  AND (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'append_vehicle_timeline_event') = 1
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'append_vehicle_timeline_event') = 'ef3bd3587978f25862546483913231e4'
  AND (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature LIKE 'public.append_vehicle_timeline_event(%') = 'ef3bd3587978f25862546483913231e4'
  AND NOT pg_catalog.has_function_privilege('anon', 'public.list_vehicle_email_notes_556(uuid)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('authenticated', 'public.list_vehicle_email_notes_556(uuid)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('service_role', 'public.list_vehicle_email_notes_556(uuid)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('authenticated', 'public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('service_role', 'public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('service_role', 'public.clear_pdc_vehicle_email_556(text)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('service_role', 'public.list_pdc_vehicle_email_warnings_556(text)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('service_role', 'public.apply_pdc_vehicle_email_batch_556(jsonb)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.clear_pdc_vehicle_email_556(text)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.list_pdc_vehicle_email_warnings_556(text)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.apply_pdc_vehicle_email_batch_556(jsonb)', 'EXECUTE')
  AND pg_catalog.to_regprocedure('karratha135_pdc.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)') IS NULL
  AND (SELECT count(*) FROM public.vehicles v WHERE v.stock_number = '13057027' AND v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND v.visible_on_board) = 1
  AND (SELECT v.id::text FROM public.vehicles v WHERE v.stock_number = '13057027' AND v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND v.visible_on_board) = 'fbafc3cd-09ff-414d-a29a-60529c0d3fca'
  AND (SELECT v.key_number FROM public.vehicles v WHERE v.id = 'fbafc3cd-09ff-414d-a29a-60529c0d3fca'::uuid) = '209'
  AND (SELECT v.current_location FROM public.vehicles v WHERE v.id = 'fbafc3cd-09ff-414d-a29a-60529c0d3fca'::uuid) = 'PMB'
  AND (SELECT v.model FROM public.vehicles v WHERE v.id = 'fbafc3cd-09ff-414d-a29a-60529c0d3fca'::uuid) LIKE 'Prado%'
  AND (SELECT u.parts_received FROM public.vehicle_parts_updates u JOIN public.vehicles v ON v.id = u.vehicle_id WHERE v.stock_number = '13057027' AND v.deleted_at IS NULL ORDER BY u.updated_at DESC NULLS LAST LIMIT 1) IS TRUE
  AND (
    'waiting_parts' IN ('waiting_parts', 'parts_eta')
    AND (SELECT u.parts_received FROM public.vehicle_parts_updates u JOIN public.vehicles v ON v.id = u.vehicle_id WHERE v.stock_number = '13057027' AND v.deleted_at IS NULL ORDER BY u.updated_at DESC NULLS LAST LIMIT 1) IS TRUE
  )
 ) AS ok,
 '13057027 is a Prado, key 209, at PMB, and parts received, so a waiting email would warn; the warning does not move it or change that status; the pinned append stays ef3bd358' AS detail
$chk556$, true, 331, 'r556');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r556: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event') IS DISTINCT FROM 'ef3bd3587978f25862546483913231e4' THEN RAISE EXCEPTION 'r556: pinned append changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='vehicle_email_notes_556' AND fault_id='F170' AND sort_order=331 AND added_in='r556' AND enabled)<>1 THEN RAISE EXCEPTION 'r556: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='vehicle_email_notes_556') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r556: vehicle_email_notes_556 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r556: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
