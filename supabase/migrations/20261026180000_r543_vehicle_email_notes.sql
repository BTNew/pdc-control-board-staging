-- r543 (F157). PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- 26 Oct 2026 10:45 AWST: board facts from pdc@ emails (a stoppage, a cancellation, a job card
-- problem, an ETA chase, a PO received) do not appear on the vehicle card.
-- append_vehicle_timeline_event is pinned and has no rows: it requires auth.uid(), so the
-- management connection cannot use it. The card does not read vehicle_timeline_events.
-- This release lets that connection, the email-AI action, or the importer append one note
-- per message id. It does not create a vehicle or a job. Pin count stays 241.
-- Sort 320 is live r542 (Close gaps holds). Sort 319 is reserved for the open r541 parts preview. This check is sort 321.
-- Undo: supabase/rollbacks/20261026180000_r543_vehicle_email_notes.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r543: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r543: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r543: pin count is not 241'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event') IS DISTINCT FROM 'ef3bd3587978f25862546483913231e4' THEN RAISE EXCEPTION 'r543: append_vehicle_timeline_event is not the pinned body'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=321 OR fault_id='F157' OR check_name='vehicle_email_notes_543' OR added_in='r543') THEN RAISE EXCEPTION 'r543: sort 321 or F157 is taken'; END IF;
 IF to_regclass('public.vehicle_timeline_events') IS NULL THEN RAISE EXCEPTION 'r543: timeline table missing'; END IF;
 IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='vehicle_timeline_events' AND indexdef ILIKE '%source_email_id%') THEN RAISE EXCEPTION 'r543: a source email index already exists'; END IF;
END $g$;

CREATE UNIQUE INDEX vehicle_timeline_events_source_email_543
  ON public.vehicle_timeline_events (source_email_id)
  WHERE source_email_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.append_vehicle_email_note_543(
  p_vehicle_id uuid,
  p_source_email_id text,
  p_sender_name text,
  p_sender_email text,
  p_quote text,
  p_summary text,
  p_category text,
  p_subject text DEFAULT NULL,
  p_event_at timestamp with time zone DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $note543$
DECLARE
  existing_id uuid;
  existing_vehicle uuid;
  new_id uuid;
  message_id text := btrim(coalesce(p_source_email_id, ''));
  quote_text text := btrim(coalesce(p_quote, ''));
  summary_text text := btrim(coalesce(p_summary, ''));
  sender text := lower(btrim(coalesce(p_sender_email, '')));
BEGIN
  IF NOT (
    coalesce(pdc_codex_intake_private.management_connection(), false)
    OR coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(), false)
    OR (auth.uid() IS NOT NULL AND coalesce(public.pdc_importer_monitor_action_421(), false))
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_category IS NULL OR p_category NOT IN ('stoppage', 'cancellation', 'job_card', 'eta_chase', 'po_received') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'category_not_allowed');
  END IF;
  IF message_id = '' OR length(message_id) < 8 OR length(message_id) > 512 OR message_id ~ '[[:space:]]' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_id_required');
  END IF;
  IF quote_text = '' OR length(quote_text) > 2000 OR summary_text = '' OR length(summary_text) > 2000 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'note_text_required');
  END IF;
  IF sender !~ '^[^[:space:]@]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'sender_required');
  END IF;
  IF p_vehicle_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  END IF;
  SELECT e.id, e.vehicle_id INTO existing_id, existing_vehicle
  FROM public.vehicle_timeline_events e
  WHERE e.source_email_id = message_id
  ORDER BY e.created_at
  LIMIT 1;
  IF FOUND AND existing_vehicle IS DISTINCT FROM p_vehicle_id THEN
    RETURN jsonb_build_object('ok', false, 'code', 'message_already_on_another_vehicle', 'event_id', existing_id);
  END IF;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', true, 'replay', true, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id);
  END IF;
  INSERT INTO public.vehicle_timeline_events (
    vehicle_id, event_type, event_at, source_kind, event_state,
    source_system, source_mailbox, source_email_id, sender_name, sender_email,
    recipient_mailbox, subject, ai_summary, original_statement, structured_data,
    confidence_label, automatic_update, created_by
  ) VALUES (
    p_vehicle_id, p_category, coalesce(p_event_at, pg_catalog.now()),
    'email'::public.vehicle_timeline_source_kind,
    'confirmed'::public.vehicle_timeline_event_state,
    'email_note_543', 'pdc@pmgwa.com.au', message_id,
    nullif(btrim(coalesce(p_sender_name, '')), ''), sender,
    'pdc@pmgwa.com.au', nullif(btrim(coalesce(p_subject, '')), ''),
    summary_text, quote_text,
    jsonb_build_object('category', p_category, 'source', 'email_note_543'),
    'high_confidence', false, auth.uid()
  )
  ON CONFLICT (source_email_id) WHERE source_email_id IS NOT NULL DO NOTHING
  RETURNING id INTO new_id;
  IF new_id IS NULL THEN
    SELECT e.id, e.vehicle_id INTO existing_id, existing_vehicle
    FROM public.vehicle_timeline_events e
    WHERE e.source_email_id = message_id
    LIMIT 1;
    IF existing_vehicle IS DISTINCT FROM p_vehicle_id THEN
      RETURN jsonb_build_object('ok', false, 'code', 'message_already_on_another_vehicle', 'event_id', existing_id);
    END IF;
    RETURN jsonb_build_object('ok', true, 'replay', true, 'event_id', existing_id, 'vehicle_id', existing_vehicle, 'source_email_id', message_id);
  END IF;
  RETURN jsonb_build_object('ok', true, 'replay', false, 'event_id', new_id, 'vehicle_id', p_vehicle_id, 'category', p_category, 'source_email_id', message_id);
END
$note543$;

REVOKE ALL ON FUNCTION public.append_vehicle_email_note_543(uuid, text, text, text, text, text, text, text, timestamp with time zone) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.append_vehicle_email_note_543(uuid, text, text, text, text, text, text, text, timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_vehicle_email_notes_543(p_vehicle_id uuid)
RETURNS TABLE (
  event_at timestamp with time zone,
  category text,
  summary text,
  quote text,
  sender_name text,
  sender_email text,
  source_email_id text,
  subject text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $list543$
BEGIN
  IF NOT (
    public.is_pdc_role('operator'::public.pdc_role)
    OR public.is_pdc_role('administrator'::public.pdc_role)
  ) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT e.event_at, e.event_type, e.ai_summary, e.original_statement,
         e.sender_name, e.sender_email, e.source_email_id, e.subject
  FROM public.vehicle_timeline_events e
  WHERE e.vehicle_id = p_vehicle_id
    AND e.source_email_id IS NOT NULL
    AND e.event_type IN ('stoppage', 'cancellation', 'job_card', 'eta_chase', 'po_received')
  ORDER BY e.event_at DESC, e.created_at DESC
  LIMIT 50;
END
$list543$;

REVOKE ALL ON FUNCTION public.list_vehicle_email_notes_543(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_vehicle_email_notes_543(uuid) TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('vehicle_email_notes_543', 'F157',
 'Vehicle email notes (r543): the importer or email-AI path can append a stoppage, cancellation, job card, ETA chase or PO note onto an existing vehicle, once per message id. The card read is for a controller. No vehicle or job is created. The pinned timeline append stays put.',
 $chk543$
SELECT
 (
  pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.list_vehicle_email_notes_543(uuid)') IS NOT NULL
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) IS TRUE
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%management_connection()%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%pdc_email_ai_v2_canonical_action_capability_20260902()%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%source_email_id%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%stoppage%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%cancellation%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%job_card%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%eta_chase%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%po_received%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) LIKE '%ON CONFLICT (source_email_id) WHERE source_email_id IS NOT NULL%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) NOT LIKE '%INSERT INTO public.vehicles%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)')) NOT LIKE '%INSERT INTO public.workshop_bookings%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_543(uuid)')) LIKE '%is_pdc_role(''operator''::public.pdc_role)%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.list_vehicle_email_notes_543(uuid)')) LIKE '%is_pdc_role(''administrator''::public.pdc_role)%'
  AND pg_catalog.to_regclass('public.vehicle_timeline_events_source_email_543') IS NOT NULL
  AND (SELECT i.indisunique FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid WHERE c.relname = 'vehicle_timeline_events_source_email_543') IS TRUE
  AND (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'append_vehicle_timeline_event') = 1
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'append_vehicle_timeline_event') = 'ef3bd3587978f25862546483913231e4'
  AND (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature LIKE 'public.append_vehicle_timeline_event(%') = 'ef3bd3587978f25862546483913231e4'
  AND NOT pg_catalog.has_function_privilege('anon', 'public.list_vehicle_email_notes_543(uuid)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('authenticated', 'public.list_vehicle_email_notes_543(uuid)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)', 'EXECUTE')
  AND pg_catalog.has_function_privilege('authenticated', 'public.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)', 'EXECUTE')
  AND pg_catalog.to_regprocedure('karratha135_pdc.append_vehicle_email_note_543(uuid,text,text,text,text,text,text,text,timestamp with time zone)') IS NULL
 ) AS ok,
 'email notes append once per message id and the pinned timeline function stays ef3bd358' AS detail
$chk543$, true, 321, 'r543');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r543: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='append_vehicle_timeline_event') IS DISTINCT FROM 'ef3bd3587978f25862546483913231e4' THEN RAISE EXCEPTION 'r543: pinned append changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='vehicle_email_notes_543' AND fault_id='F157' AND sort_order=321 AND added_in='r543' AND enabled)<>1 THEN RAISE EXCEPTION 'r543: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='vehicle_email_notes_543') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r543: vehicle_email_notes_543 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r543: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
