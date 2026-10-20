-- Local proof schema for the Coaster / HiAce checkbox. Not applied to staging.
CREATE SCHEMA IF NOT EXISTS pdc_fitter_private;
CREATE SCHEMA IF NOT EXISTS pdc_codex_intake_private;

CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

CREATE TABLE public.workshop_stages (
 id uuid PRIMARY KEY, code text NOT NULL
);
CREATE TABLE public.vehicles (
 id uuid PRIMARY KEY, vehicle_description text, current_location text, lifecycle_state text DEFAULT 'active',
 qc_completed_at timestamptz, rft_transferred_at timestamptz, deleted_at timestamptz
);
CREATE TABLE public.workshop_bookings (
 id uuid PRIMARY KEY, vehicle_id uuid NOT NULL, stage_id uuid NOT NULL, status text NOT NULL,
 deleted_at timestamptz, version integer NOT NULL DEFAULT 1, default_duration_minutes integer NOT NULL,
 updated_at timestamptz
);
CREATE TABLE public.vehicle_work_items (
 vehicle_id uuid NOT NULL, work_key text NOT NULL, required boolean NOT NULL, completed boolean NOT NULL,
 completed_at timestamptz, completed_by uuid, notes text NOT NULL DEFAULT '', updated_at timestamptz,
 PRIMARY KEY (vehicle_id, work_key)
);
CREATE TABLE pdc_fitter_private.operation_progress (
 booking_id uuid NOT NULL, line_identity text NOT NULL, scope_hash text NOT NULL,
 completed boolean NOT NULL DEFAULT false, note text NOT NULL DEFAULT '',
 technician_id uuid NOT NULL, updated_by uuid NOT NULL, updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (booking_id, line_identity)
);
CREATE TABLE pdc_fitter_private.conversion_state (
 vehicle_id uuid NOT NULL, line_identity text NOT NULL, scope_hash text NOT NULL,
 template_id text NOT NULL, template_version text NOT NULL, sections jsonb NOT NULL, metadata jsonb NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_by uuid NOT NULL,
 PRIMARY KEY (vehicle_id, line_identity, scope_hash)
);
CREATE TABLE pdc_fitter_private.conversion_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, vehicle_id uuid NOT NULL, line_identity text NOT NULL
);
CREATE TABLE pdc_codex_intake_private.tune_pmb_complete_receipts (
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL UNIQUE,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE pdc_codex_intake_private.tune_checkout_receipts (
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL UNIQUE,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(), transaction_id bigint NOT NULL DEFAULT txid_current(),
 actor_id uuid
);
CREATE TABLE pdc_codex_intake_private.service_job_status (
 vehicle_id uuid, sub_status text
);
CREATE TABLE public.tick_ops (
 vehicle_id uuid NOT NULL, line_identity text NOT NULL, description text NOT NULL,
 hours numeric NOT NULL, scope_hash text NOT NULL
);
CREATE TABLE public.tick_refs (name text PRIMARY KEY, id uuid NOT NULL);

CREATE FUNCTION pdc_fitter_private.conversion_model(p_description text, p_vehicle text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog AS $$
DECLARE d text := upper(coalesce(p_description, '')); v text := upper(coalesce(p_vehicle, ''));
BEGIN
 IF d !~ '^(COASTER[ -]*(BUS[ -]*)?|BUS[ -]*)?4[ -]*X[ -]*4[ -]+CONVERSION'
  OR d ~ '(TYRES?|TIRES?|RIMS?|BULL[ -]*BAR|SNORKEL|HEADLIGHT|SERVICE|SAFETY CHECK)' THEN RETURN NULL; END IF;
 IF d ~ '(QUOTE|REPAIR|REWORK)' THEN RETURN 'review'; END IF;
 IF v ~ 'COASTER' AND d !~ '(HIACE|COMMUTER|SLWB)' THEN RETURN 'coaster'; END IF;
 IF v ~ 'HI[ -]*ACE' AND v ~ 'COMMUTER' AND d !~ 'COASTER' THEN RETURN 'hiace_commuter'; END IF;
 RETURN 'review';
END $$;

CREATE FUNCTION pdc_fitter_private.conversion_view(p_vehicle uuid, p_line jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE model text; vdesc text;
BEGIN
 SELECT vehicle_description INTO vdesc FROM public.vehicles WHERE id = p_vehicle;
 model := pdc_fitter_private.conversion_model(p_line->>'description', vdesc);
 IF model IS NULL OR p_line->>'stage_code' <> 'BUS_4X4' THEN RETURN NULL; END IF;
 IF model = 'review' THEN
  RETURN jsonb_build_object('model', 'Model / conversion scope needs review', 'needs_review', true, 'complete', false);
 END IF;
 RETURN jsonb_build_object('id', model, 'needs_review', false, 'complete', false, 'release_blocked', true,
  'total_minutes', CASE WHEN model = 'coaster' THEN 3765 ELSE 2280 END, 'completed_planned_minutes', 0,
  'scope_hash', md5(jsonb_build_array(p_line->>'scope_hash', model, '2026-09-17.1')::text));
END $$;

CREATE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE c jsonb;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric) ELSE 0 END);
END $$;

CREATE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid, p_booking_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id, jsonb_build_object(
  'line_identity', s.line_identity, 'description', s.description, 'stage_code', 'BUS_4X4',
  'hours', to_jsonb(s.hours), 'scope_hash', s.scope_hash,
  'completed', coalesce(p.completed AND p.scope_hash = s.scope_hash, false)))), '[]'::jsonb)
 FROM public.tick_ops s
 LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id = p_booking_id AND p.line_identity = s.line_identity
 WHERE s.vehicle_id = p_vehicle_id
$$;

CREATE FUNCTION pdc_fitter_private.conversion_completion_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE bid uuid; vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME = 'workshop_bookings' THEN
  IF NEW.status <> 'completed' OR (TG_OP = 'UPDATE' AND OLD.status = 'completed') THEN RETURN NEW; END IF;
  bid := NEW.id; vid := NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id = NEW.stage_id;
 ELSIF TG_TABLE_NAME = 'vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP = 'UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid := NEW.vehicle_id; stage := CASE WHEN NEW.work_key = 'bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id = NEW.booking_id;
  stage := 'BUS_4X4'; identity := NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid, bid)) x
  WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity' = identity) LOOP
  IF NOT coalesce((l->>'completed')::boolean, false) THEN
   RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
  END IF;
 END LOOP;
 RETURN NEW;
END $$;

CREATE TRIGGER conversion_booking_completion BEFORE UPDATE ON public.workshop_bookings
FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();
CREATE TRIGGER conversion_work_completion BEFORE UPDATE ON public.vehicle_work_items
FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();
CREATE TRIGGER conversion_parent_completion BEFORE INSERT OR UPDATE ON pdc_fitter_private.operation_progress
FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();

CREATE FUNCTION public.fitter_job_command(
 p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text,
 p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL, p_completed boolean DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE l jsonb; vid uuid;
BEGIN
 SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id = p_booking_id;
 SELECT item INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(vid, p_booking_id)) item
  WHERE item->>'line_identity' = p_line_identity;
 IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
 IF l->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
 INSERT INTO pdc_fitter_private.operation_progress(booking_id, line_identity, scope_hash, completed, note, technician_id, updated_by)
 VALUES (p_booking_id, p_line_identity, l->>'scope_hash', p_completed, coalesce(p_note, ''), p_technician_id, p_technician_id)
 ON CONFLICT (booking_id, line_identity) DO UPDATE
  SET scope_hash = excluded.scope_hash, completed = excluded.completed, note = excluded.note,
      technician_id = excluded.technician_id, updated_by = excluded.updated_by, updated_at = clock_timestamp()
  WHERE operation_progress.booking_id = excluded.booking_id
    AND operation_progress.line_identity = excluded.line_identity;
 RETURN jsonb_build_object('ok', true);
END $$;

INSERT INTO public.workshop_stages VALUES ('00000000-0000-0000-0000-0000000000b1', 'BUS_4X4');

CREATE FUNCTION pg_temp.make_job(tag text, description text, vehicle text, hours numeric, location text DEFAULT 'PMB')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE vid uuid := gen_random_uuid(); bid uuid := gen_random_uuid(); actor uuid := '00000000-0000-0000-0000-0000000000a1';
BEGIN
 INSERT INTO public.vehicles(id, vehicle_description, current_location) VALUES (vid, vehicle, location);
 INSERT INTO public.workshop_bookings(id, vehicle_id, stage_id, status, default_duration_minutes)
 VALUES (bid, vid, '00000000-0000-0000-0000-0000000000b1', 'started', 3600);
 INSERT INTO public.vehicle_work_items(vehicle_id, work_key, required, completed)
 VALUES (vid, 'bus4x4', true, false), (vid, 'qc', true, false);
 INSERT INTO public.tick_ops VALUES (vid, 'source:1', description, hours, 'scope-' || tag);
 INSERT INTO public.tick_refs VALUES (tag, vid), (tag || '-booking', bid);
END $$;

SELECT pg_temp.make_job('coaster-before', 'Coaster Bus 4x4 Conversion - 6 Speed 2.8', 'Coaster 2.8L Diesel', 60);
SELECT pg_temp.make_job('hiace-before', 'Bus 4x4 Conversion SLWB & Commuter', 'Toyota HiAce Commuter', 40);
SELECT pg_temp.make_job('coaster-after', 'Coaster Bus 4x4 Conversion - 6 Speed 2.8', 'Coaster 2.8L Diesel', 60);
SELECT pg_temp.make_job('hiace-99', 'Bus 4x4 Conversion SLWB & Commuter', 'Toyota HiAce Commuter', 40);
SELECT pg_temp.make_job('review', 'Bus 4x4 Conversion rework', 'Coaster 2.8L Diesel', 60);
SELECT pg_temp.make_job('tyres', '6 x Super Single Tyres & Rims - Coaster', 'Coaster 2.8L Diesel', 7);
SELECT pg_temp.make_job('already-qc', 'Coaster Bus 4x4 Conversion - 6 Speed 2.8', 'Coaster 2.8L Diesel', 60, 'QC');

INSERT INTO pdc_fitter_private.conversion_state(vehicle_id, line_identity, scope_hash, template_id, template_version, sections, metadata, updated_by)
SELECT id, 'source:1', 'stored-section-hash', 'coaster', '2026-09-17.1', '{"12":{"status":"not_started"}}'::jsonb, '{}'::jsonb,
 '00000000-0000-0000-0000-0000000000a1'
FROM public.tick_refs WHERE name = 'coaster-before';

CREATE FUNCTION pg_temp.vid(tag text) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM public.tick_refs WHERE name = tag $$;
CREATE FUNCTION pg_temp.bid(tag text) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM public.tick_refs WHERE name = tag || '-booking' $$;

CREATE FUNCTION pg_temp.import80(tag text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v public.vehicles%rowtype; receipt uuid; actor uuid := '00000000-0000-0000-0000-0000000000a1';
BEGIN
 SELECT * INTO v FROM public.vehicles WHERE id = pg_temp.vid(tag) FOR UPDATE;
 IF upper(btrim(coalesce(v.current_location, ''))) IN ('QC', 'RFT', 'COMPLETED')
    OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL
    OR EXISTS (SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id = v.id)
    OR EXISTS (SELECT 1 FROM pdc_codex_intake_private.service_job_status WHERE vehicle_id = v.id AND sub_status = '99')
    OR EXISTS (SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id = v.id)
 THEN RETURN 'skipped'; END IF;
 INSERT INTO pdc_codex_intake_private.tune_pmb_complete_receipts(vehicle_id) VALUES (v.id) RETURNING receipt_id INTO receipt;
 UPDATE public.vehicle_work_items SET completed = true, completed_at = clock_timestamp(), completed_by = actor,
  notes = concat_ws(E'\n', nullif(notes, ''), 'PMB work complete from Tune Sub Status 80; receipt ' || receipt),
  updated_at = clock_timestamp()
 WHERE vehicle_id = v.id AND required AND NOT completed
  AND lower(work_key) IN ('bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre');
 UPDATE public.workshop_bookings wb SET status = 'completed', version = wb.version + 1, updated_at = clock_timestamp()
 FROM public.workshop_stages s
 WHERE wb.stage_id = s.id AND wb.vehicle_id = v.id AND wb.deleted_at IS NULL
  AND wb.status IN ('queued', 'planned', 'started', 'stoppage')
  AND s.code IN ('BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE');
 UPDATE public.vehicles SET current_location = 'QC' WHERE id = v.id;
 RETURN 'applied';
END $$;

CREATE FUNCTION pg_temp.import99(tag text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v public.vehicles%rowtype; receipt uuid; actor uuid := '00000000-0000-0000-0000-0000000000a1';
BEGIN
 SELECT * INTO v FROM public.vehicles WHERE id = pg_temp.vid(tag) FOR UPDATE;
 IF v.lifecycle_state = 'rft' OR upper(btrim(coalesce(v.current_location, ''))) IN ('QC', 'RFT')
    OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL
    OR EXISTS (SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id = v.id)
 THEN RETURN 'skipped'; END IF;
 INSERT INTO pdc_codex_intake_private.tune_checkout_receipts(vehicle_id, actor_id) VALUES (v.id, actor) RETURNING receipt_id INTO receipt;
 UPDATE public.vehicle_work_items SET completed = true, completed_at = clock_timestamp(), completed_by = actor,
  notes = concat_ws(E'\n', nullif(notes, ''), 'Completed by Tune Sub Status 99; receipt ' || receipt),
  updated_at = clock_timestamp()
 WHERE vehicle_id = v.id AND required AND NOT completed AND lower(work_key) NOT IN ('qc', 'qc_signoff');
 UPDATE public.workshop_bookings SET status = 'completed', version = version + 1, updated_at = clock_timestamp()
 WHERE vehicle_id = v.id AND deleted_at IS NULL AND status IN ('queued', 'planned', 'started', 'stoppage');
 UPDATE public.vehicles SET current_location = 'QC' WHERE id = v.id;
 RETURN 'applied';
END $$;

CREATE FUNCTION pg_temp.assert_blocked(which text, tag text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF which = '80' THEN PERFORM pg_temp.import80(tag); ELSE PERFORM pg_temp.import99(tag); END IF;
 RAISE EXCEPTION 'import % for % was not blocked', which, tag;
EXCEPTION WHEN check_violation THEN
 IF SQLERRM NOT LIKE '%conversion_sections_required%' THEN
  RAISE EXCEPTION 'import % for % raised %', which, tag, SQLERRM;
 END IF;
END $$;

CREATE FUNCTION pg_temp.tick(tag text, done boolean) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.fitter_job_command('00000000-0000-0000-0000-0000000000a1', pg_temp.bid(tag), 1, 'catalog',
  gen_random_uuid(), 'line', 'source:1', done, '')
$$;
