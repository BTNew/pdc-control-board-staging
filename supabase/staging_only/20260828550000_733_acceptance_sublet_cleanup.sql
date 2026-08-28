-- STAGING ONLY 733: one-shot cleanup of the proven acceptance Sublet artifact.
-- This never deletes booking/history rows, never marks returned, never mutates
-- vehicle identity, and is disabled/revoked by the guarded apply controller after use.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-733-acceptance-sublet-cleanup',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR to_regprocedure('public.run_pdc_acceptance_sublet_cleanup_733(uuid,text)') IS NOT NULL
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.create_pdc_email_ai_acceptance_693()'::regprocedure)<>'e0cce2f4f026d6382a7c79380bcc72f677f93345c9a9aab7ee69b5f3b53223c7'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.cancel_pdc_sublet_booking(uuid,bigint,text)'::regprocedure)<>'f1d15bbfbbc39291d21b2c0c438c1d75190560a44c27bf80daff5d98bbcddff1'
     OR (SELECT count(*) FROM public.pdc_email_ai_acceptance_runs_693 WHERE target_vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid)<>2
     OR (SELECT count(*) FROM public.pdc_sublet_booking_instance_history WHERE booking_id='47dde42b-f768-4a3f-a680-28b6ae8f36f7'::uuid AND action='created' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid AND event_at='2026-08-27 16:42:03.891928+00'::timestamptz)<>1
     OR (SELECT count(*) FROM public.pdc_sublet_booking_instances WHERE booking_id='47dde42b-f768-4a3f-a680-28b6ae8f36f7'::uuid AND vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND provider_id='4cbd486c-78c2-42ce-987a-99d45d1eeaf4'::uuid AND status='active' AND source_kind='manual' AND created_by='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid AND created_at='2026-08-27 16:42:03.887085+00'::timestamptz AND notes='HERMES bounded staging acceptance fixture' AND version=5)<>1
     OR (SELECT count(*) FROM public.vehicle_work_items WHERE id='97340bcf-b31d-48dc-921a-4d0afc87db10'::uuid AND vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND lower(work_key)='sublet' AND required AND NOT completed AND notes='Required only after manual canonical Sublet booking; HERMES acceptance')<>1
     OR (SELECT count(*) FROM public.vehicles WHERE id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND public.normalize_vehicle_stock_number(stock_number)='13000765' AND source_system='microsoft_navision' AND source_record_id='6ddb2053-3ca2-41aa-8ef5-0418582bcde0' AND lifecycle_state='active' AND deleted_at IS NULL AND visible_on_board AND current_location='Other' AND version=9)<>1
     OR (SELECT count(*) FROM public.sublet_providers WHERE id='4cbd486c-78c2-42ce-987a-99d45d1eeaf4'::uuid AND name='Customer Sublet' AND active)<>1
  THEN RAISE EXCEPTION 'PDC_733_EXACT_ACCEPTANCE_SUBLET_PRESTATE_MISMATCH' USING errcode='55000';
  END IF;
END
$guard$;

CREATE TABLE public.pdc_acceptance_sublet_cleanup_controls_733(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true,
  used boolean NOT NULL DEFAULT false,
  booking_id uuid NOT NULL CHECK(booking_id='47dde42b-f768-4a3f-a680-28b6ae8f36f7'),
  vehicle_id uuid NOT NULL CHECK(vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'),
  provider_id uuid NOT NULL CHECK(provider_id='4cbd486c-78c2-42ce-987a-99d45d1eeaf4'),
  work_item_id uuid NOT NULL CHECK(work_item_id='97340bcf-b31d-48dc-921a-4d0afc87db10'),
  expected_booking_version bigint NOT NULL CHECK(expected_booking_version=5),
  expected_vehicle_version bigint NOT NULL CHECK(expected_vehicle_version=9),
  expected_created_by uuid NOT NULL CHECK(expected_created_by='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  expected_created_at timestamptz NOT NULL CHECK(expected_created_at='2026-08-27 16:42:03.887085+00'),
  expected_note text NOT NULL CHECK(expected_note='HERMES bounded staging acceptance fixture'),
  expected_source_kind text NOT NULL CHECK(expected_source_kind='manual'),
  acceptance_function text NOT NULL CHECK(acceptance_function='create_pdc_email_ai_acceptance_693'),
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_acceptance_sublet_cleanup_controls_733 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_acceptance_sublet_cleanup_controls_733 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_acceptance_sublet_cleanup_controls_733 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_acceptance_sublet_cleanup_controls_733(booking_id,vehicle_id,provider_id,work_item_id,expected_booking_version,expected_vehicle_version,expected_created_by,expected_created_at,expected_note,expected_source_kind,acceptance_function)
VALUES('47dde42b-f768-4a3f-a680-28b6ae8f36f7','2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02','4cbd486c-78c2-42ce-987a-99d45d1eeaf4','97340bcf-b31d-48dc-921a-4d0afc87db10',5,9,'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','2026-08-27 16:42:03.887085+00','HERMES bounded staging acceptance fixture','manual','create_pdc_email_ai_acceptance_693');

CREATE TABLE public.pdc_acceptance_sublet_cleanup_history_733(
  cleanup_history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('cancelled_and_work_recomputed','cleanup_path_revoked')),
  booking_id uuid NOT NULL CHECK(booking_id='47dde42b-f768-4a3f-a680-28b6ae8f36f7'),
  vehicle_id uuid NOT NULL CHECK(vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'),
  provider_id uuid NOT NULL CHECK(provider_id='4cbd486c-78c2-42ce-987a-99d45d1eeaf4'),
  work_item_id uuid NOT NULL CHECK(work_item_id='97340bcf-b31d-48dc-921a-4d0afc87db10'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  before_booking jsonb NOT NULL,
  after_booking jsonb NOT NULL,
  before_work jsonb NOT NULL,
  after_work jsonb NOT NULL,
  before_vehicle jsonb NOT NULL,
  after_vehicle jsonb NOT NULL,
  canonical_cancel_result jsonb,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_acceptance_sublet_cleanup_history_733 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_acceptance_sublet_cleanup_history_733 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_acceptance_sublet_cleanup_history_733 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_acceptance_sublet_cleanup_history_immutable_733()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_733_ACCEPTANCE_SUBLET_CLEANUP_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_acceptance_sublet_cleanup_history_immutable_733() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_acceptance_sublet_cleanup_history_immutable_733 BEFORE UPDATE OR DELETE ON public.pdc_acceptance_sublet_cleanup_history_733 FOR EACH ROW EXECUTE FUNCTION public.pdc_acceptance_sublet_cleanup_history_immutable_733();

CREATE FUNCTION public.run_pdc_acceptance_sublet_cleanup_733(p_booking_id uuid,p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $cleanup$
DECLARE
  c public.pdc_acceptance_sublet_cleanup_controls_733%rowtype;
  b public.pdc_sublet_booking_instances%rowtype;
  b_after public.pdc_sublet_booking_instances%rowtype;
  v public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  w public.vehicle_work_items%rowtype;
  w_after public.vehicle_work_items%rowtype;
  cancel_result jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated'
     OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
     OR public.current_pdc_user_role()<>'importer'
     OR p_confirmation<>'PDC-ACCEPTANCE-SUBLET-CLEANUP-733'
     OR to_regprocedure('public.create_pdc_email_ai_acceptance_693()') IS NULL
     OR (SELECT count(*) FROM public.pdc_email_ai_acceptance_runs_693 WHERE target_vehicle_id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid)<>2
  THEN RAISE EXCEPTION 'PDC_733_CLEANUP_SCOPE_DENIED' USING errcode='42501'; END IF;

  SELECT * INTO c FROM public.pdc_acceptance_sublet_cleanup_controls_733 WHERE singleton FOR UPDATE;
  IF NOT FOUND OR NOT c.enabled OR c.used OR p_booking_id<>c.booking_id THEN RAISE EXCEPTION 'PDC_733_ONE_SHOT_ALREADY_USED_OR_WRONG_OBJECT' USING errcode='55000'; END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=c.vehicle_id AND public.normalize_vehicle_stock_number(stock_number)='13000765' AND source_system='microsoft_navision' AND source_record_id='6ddb2053-3ca2-41aa-8ef5-0418582bcde0' AND lifecycle_state='active' AND deleted_at IS NULL AND visible_on_board AND current_location='Other' AND version=c.expected_vehicle_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_733_VEHICLE_PROVENANCE_DRIFT' USING errcode='55000'; END IF;
  SELECT * INTO b FROM public.pdc_sublet_booking_instances WHERE booking_id=c.booking_id FOR UPDATE;
  IF NOT FOUND OR b.vehicle_id<>c.vehicle_id OR b.provider_id<>c.provider_id OR b.status<>'active' OR b.returned_at IS NOT NULL OR b.returned_by IS NOT NULL OR b.cancelled_at IS NOT NULL OR b.cancelled_by IS NOT NULL OR b.source_kind<>c.expected_source_kind OR b.created_by<>c.expected_created_by OR b.created_at<>c.expected_created_at OR b.notes<>c.expected_note OR b.version<>c.expected_booking_version THEN RAISE EXCEPTION 'PDC_733_BOOKING_PROVENANCE_DRIFT' USING errcode='55000'; END IF;
  SELECT * INTO w FROM public.vehicle_work_items WHERE id=c.work_item_id AND vehicle_id=c.vehicle_id AND lower(work_key)='sublet' AND required AND NOT completed AND notes='Required only after manual canonical Sublet booking; HERMES acceptance' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_733_WORK_PRESTATE_DRIFT' USING errcode='55000'; END IF;

  cancel_result:=public.cancel_pdc_sublet_booking(b.booking_id,b.version,'PDC-ACCEPTANCE-733 canonical staging artifact cleanup');
  IF coalesce((cancel_result->>'ok')::boolean,false) IS NOT TRUE OR cancel_result->>'code'<>'cancelled' THEN RAISE EXCEPTION 'PDC_733_CANONICAL_CANCEL_FAILED' USING errcode='55000'; END IF;
  SELECT * INTO b_after FROM public.pdc_sublet_booking_instances WHERE booking_id=b.booking_id;
  IF b_after.status<>'cancelled' OR b_after.returned_at IS NOT NULL OR b_after.returned_by IS NOT NULL OR b_after.cancelled_by<>auth.uid() OR b_after.version<>b.version+1 THEN RAISE EXCEPTION 'PDC_733_CANCEL_READBACK_FAILED' USING errcode='55000'; END IF;

  UPDATE public.vehicle_work_items SET required=false,updated_at=clock_timestamp(),notes=concat_ws(E'\n',notes,'PDC-ACCEPTANCE-733: not required after canonical Sublet cancellation') WHERE id=w.id AND vehicle_id=c.vehicle_id AND NOT completed AND required RETURNING * INTO w_after;
  IF NOT FOUND OR w_after.required OR w_after.completed THEN RAISE EXCEPTION 'PDC_733_WORK_RECOMPUTE_FAILED' USING errcode='55000'; END IF;
  SELECT * INTO v_after FROM public.vehicles WHERE id=v.id;
  IF to_jsonb(v)<>to_jsonb(v_after) THEN RAISE EXCEPTION 'PDC_733_VEHICLE_IDENTITY_CHANGED' USING errcode='55000'; END IF;

  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','vehicle_work_items',w_after.id,c.vehicle_id,auth.uid(),lower(auth.jwt()->>'email'),to_jsonb(w),to_jsonb(w_after),jsonb_build_object('contract','pdc_acceptance_sublet_cleanup_733','reason','PDC-ACCEPTANCE-733 canonical staging artifact cleanup','booking_id',b.booking_id,'booking_cancelled',true,'required_recomputed',true,'target_vehicle_preserved',true,'production_untouched',true));
  UPDATE public.pdc_acceptance_sublet_cleanup_controls_733 SET enabled=false,used=true,used_at=clock_timestamp() WHERE singleton;
  INSERT INTO public.pdc_acceptance_sublet_cleanup_history_733(event_key,event_kind,booking_id,vehicle_id,provider_id,work_item_id,actor_id,actor_email,before_booking,after_booking,before_work,after_work,before_vehicle,after_vehicle,canonical_cancel_result,production_writes,task_enabled,mailbox_contacted,uid514_processed)
  VALUES(encode(extensions.digest(convert_to('pdc-acceptance-733|cancel|'||b.booking_id::text,'UTF8'),'sha256'),'hex'),'cancelled_and_work_recomputed',b.booking_id,c.vehicle_id,c.provider_id,w.id,auth.uid(),lower(auth.jwt()->>'email'),to_jsonb(b),to_jsonb(b_after),to_jsonb(w),to_jsonb(w_after),to_jsonb(v),to_jsonb(v_after),cancel_result,false,false,false,false);
  RETURN jsonb_build_object('ok',true,'code','pdc_acceptance_sublet_cleaned_733','booking_id',b.booking_id,'booking_status',b_after.status,'booking_version',b_after.version,'work_item_required',w_after.required,'active_booking_count',(SELECT count(*) FROM public.pdc_sublet_booking_instances WHERE vehicle_id=c.vehicle_id AND status='active'),'target_vehicle_preserved',true,'immutable_history_preserved',true,'returned',false,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
END
$cleanup$;
REVOKE ALL ON FUNCTION public.run_pdc_acceptance_sublet_cleanup_733(uuid,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.run_pdc_acceptance_sublet_cleanup_733(uuid,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260828550000','733_acceptance_sublet_cleanup',ARRAY[
  'Guard exact staging sentinel, acceptance function/hash, booking history, provider, genuine Navision vehicle and required Sublet work prestate',
  'Create forced-RLS one-shot cleanup controls and immutable before/after cleanup history',
  'Cancel exactly one proven acceptance booking through canonical versioned cancellation semantics',
  'Recompute Sublet required=false only after the active manual booking is cancelled',
  'Preserve vehicle/Navision identity, booking/history receipts, no returned/physical evidence fabrication, task/outbound/UID514/Production false',
  'Disable the one-shot control after successful use; apply controller revokes EXECUTE'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
