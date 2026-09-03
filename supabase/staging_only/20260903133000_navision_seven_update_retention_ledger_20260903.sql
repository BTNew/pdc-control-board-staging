-- STAGING ONLY 20260903133000: canonical seven-applicable-update Navision
-- retention. This successor adds immutable dealer-scoped sequencing and
-- per-record observations, repairs retained canonical visibility, and keeps
-- exact Delivered at Dealer lifecycle closure outside the retention writer.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-navision-seven-update-retention-20260903133000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
LOCK TABLE public.navision_import_batches IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.navision_import_items IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_apply_sha text;
  v_predecessor_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
    INTO v_apply_sha
  FROM pg_proc p
  WHERE p.oid='public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure;

  IF to_regprocedure('public.apply_navision_backend_import_pre_20260902271000(text,jsonb,text,text,text,timestamptz,text,text,bigint)') IS NOT NULL THEN
    SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
      INTO v_predecessor_sha
    FROM pg_proc p
    WHERE p.oid='public.apply_navision_backend_import_pre_20260902271000(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure;
  END IF;

  IF current_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR current_setting('app.environment',true)='production'
     OR (SELECT max(version) FILTER (WHERE version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260903132000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903132000')<>1
     OR to_regclass('public.pdc_navision_applicable_updates_20260903') IS NOT NULL
     OR to_regclass('public.pdc_navision_retention_observations_20260903') IS NOT NULL
     OR (v_predecessor_sha IS NULL AND v_apply_sha<>'78ba5f3e5f7885cc0c31ca2723f3ababdb74f88775eba9a4edc1e393d35334cc')
     OR (v_predecessor_sha IS NOT NULL AND (v_predecessor_sha<>'78ba5f3e5f7885cc0c31ca2723f3ababdb74f88775eba9a4edc1e393d35334cc'
         OR v_apply_sha<>'c6a5b784f26e3d7ca042d349bd36996c9e65b6f667f0d3f65089c76d48dc102a'))
  THEN
    RAISE EXCEPTION 'PDC_20260903133000_STAGING_PREDECESSOR_OR_ENVIRONMENT_FAILED' USING errcode='55000';
  END IF;
END
$guard$;

-- On a clean source replay migration 20260902271000 is intentionally absent.
-- Preserve the exact 770 apply as the common private predecessor. On deployed
-- STAGING the same predecessor already exists and is hash-bound above.
DO $predecessor$
BEGIN
  IF to_regprocedure('public.apply_navision_backend_import_pre_20260902271000(text,jsonb,text,text,text,timestamptz,text,text,bigint)') IS NULL THEN
    ALTER FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
      RENAME TO apply_navision_backend_import_pre_20260902271000;
  END IF;
END
$predecessor$;
REVOKE ALL ON FUNCTION public.apply_navision_backend_import_pre_20260902271000(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_navision_retention_threshold_20260903()
RETURNS integer LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog
AS $threshold$
  SELECT 7
$threshold$;
REVOKE ALL ON FUNCTION public.pdc_navision_retention_threshold_20260903() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_navision_retain_after_absence_count_20260903(
  p_applicable_absences integer,p_lifecycle_status text
)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog,public
AS $retain$
  SELECT coalesce(p_applicable_absences,0)<public.pdc_navision_retention_threshold_20260903()
     AND lower(btrim(coalesce(p_lifecycle_status,'')))<>'deliveredatdealer'
$retain$;
REVOKE ALL ON FUNCTION public.pdc_navision_retain_after_absence_count_20260903(integer,text)
  FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_navision_applicable_updates_20260903(
  source_system text NOT NULL CHECK(source_system='microsoft_navision'),
  dealer_code text NOT NULL CHECK(dealer_code IN('14450','37047')),
  sequence_no bigint NOT NULL CHECK(sequence_no>0),
  batch_id uuid NOT NULL REFERENCES public.navision_import_batches(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL,
  source_hash text NOT NULL CHECK(source_hash~'^[0-9a-f]{64}$'),
  result_revision bigint NOT NULL CHECK(result_revision>0),
  applied_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(source_system,dealer_code,sequence_no),
  UNIQUE(batch_id),
  UNIQUE(source_system,dealer_code,sequence_no)
);

CREATE TABLE public.pdc_navision_retention_observations_20260903(
  source_system text NOT NULL CHECK(source_system='microsoft_navision'),
  dealer_code text NOT NULL CHECK(dealer_code IN('14450','37047')),
  sequence_no bigint NOT NULL CHECK(sequence_no>0),
  batch_id uuid NOT NULL REFERENCES public.navision_import_batches(id) ON DELETE RESTRICT,
  backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  source_record_id text NOT NULL,
  present_in_update boolean NOT NULL,
  lifecycle_status text NOT NULL,
  consecutive_absences integer NOT NULL CHECK(consecutive_absences>=0),
  decision text NOT NULL CHECK(decision IN('present','absent_retained','absent_retired','delivered_at_dealer')),
  record_is_current_after boolean NOT NULL,
  record_status_after text NOT NULL CHECK(record_status_after IN('current','not_in_latest_batch','inactive')),
  missing_since_batch_id_after uuid REFERENCES public.navision_import_batches(id) ON DELETE RESTRICT,
  evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(source_system,dealer_code,sequence_no,backend_record_id),
  FOREIGN KEY(source_system,dealer_code,sequence_no)
    REFERENCES public.pdc_navision_applicable_updates_20260903(source_system,dealer_code,sequence_no)
    ON DELETE RESTRICT,
  CHECK((record_is_current_after AND missing_since_batch_id_after IS NULL)
     OR (NOT record_is_current_after AND missing_since_batch_id_after IS NOT NULL))
);

CREATE INDEX pdc_navision_retention_observations_record_20260903
  ON public.pdc_navision_retention_observations_20260903(backend_record_id,sequence_no DESC);

CREATE OR REPLACE FUNCTION public.pdc_navision_retention_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_NAVISION_RETENTION_HISTORY_IMMUTABLE' USING errcode='55000';
END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_navision_retention_immutable_20260903() FROM public,anon,authenticated,service_role;

CREATE TRIGGER pdc_navision_applicable_updates_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_navision_applicable_updates_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_navision_retention_immutable_20260903();
CREATE TRIGGER pdc_navision_retention_observations_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_navision_retention_observations_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_navision_retention_immutable_20260903();

ALTER TABLE public.pdc_navision_applicable_updates_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_retention_observations_20260903 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_navision_applicable_updates_20260903 FROM public,anon,authenticated,service_role;
REVOKE ALL ON public.pdc_navision_retention_observations_20260903 FROM public,anon,authenticated,service_role;
GRANT SELECT ON public.pdc_navision_applicable_updates_20260903 TO authenticated;
GRANT SELECT ON public.pdc_navision_retention_observations_20260903 TO authenticated;
CREATE POLICY pdc_navision_applicable_updates_read_20260903
ON public.pdc_navision_applicable_updates_20260903 FOR SELECT TO authenticated
USING(public.current_pdc_user_role()::text IN('viewer','operator','importer','administrator'));
CREATE POLICY pdc_navision_retention_observations_read_20260903
ON public.pdc_navision_retention_observations_20260903 FOR SELECT TO authenticated
USING(public.current_pdc_user_role()::text IN('viewer','operator','importer','administrator'));

-- Existing successful batches are the authoritative dealer-scoped update ledger.
-- Rolled-back batches are not applicable current Navision updates.
INSERT INTO public.pdc_navision_applicable_updates_20260903(
  source_system,dealer_code,sequence_no,batch_id,idempotency_key,source_hash,result_revision,applied_at
)
SELECT b.source_system,b.dealer_code,
  row_number() OVER(PARTITION BY b.source_system,b.dealer_code ORDER BY b.applied_at,b.id),
  b.id,b.idempotency_key,b.source_hash,b.result_revision,b.applied_at
FROM public.navision_import_batches b
WHERE b.source_system='microsoft_navision'
  AND b.dealer_code IN('14450','37047')
  AND b.status='applied'
ORDER BY b.source_system,b.dealer_code,b.applied_at,b.id;

-- Reconstruct immutable canonical decisions from retained import-item snapshots.
-- This does not rewrite current records or operational lifecycle state.
WITH item_state AS MATERIALIZED(
  SELECT u.source_system,u.dealer_code,u.sequence_no,u.batch_id,r.id AS backend_record_id,
    r.source_record_id,i.classification,
    i.classification IN('new','changed','unchanged') AS present_in_update,
    public.navision_exact_lifecycle_status(coalesce(i.after_record->'normalized_data',i.before_record->'normalized_data',r.normalized_data)) AS lifecycle_status
  FROM public.pdc_navision_applicable_updates_20260903 u
  JOIN public.navision_backend_records r
    ON r.source_system=u.source_system AND r.dealer_code=u.dealer_code
  JOIN public.pdc_navision_applicable_updates_20260903 first_seen
    ON first_seen.batch_id=r.first_seen_batch_id AND first_seen.sequence_no<=u.sequence_no
  JOIN LATERAL(
    SELECT x.* FROM public.navision_import_items x
    WHERE x.batch_id=u.batch_id AND x.backend_record_id=r.id
    ORDER BY x.id LIMIT 1
  ) i ON true
), running AS MATERIALIZED(
  SELECT s.*,
    max(sequence_no) FILTER(WHERE present_in_update) OVER(
      PARTITION BY backend_record_id ORDER BY sequence_no ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS last_present_sequence
  FROM item_state s
), decisions AS(
  SELECT x.*,
    CASE WHEN present_in_update THEN 0 ELSE sequence_no-last_present_sequence END::integer AS consecutive_absences,
    CASE
      WHEN lifecycle_status='deliveredatdealer' THEN 'delivered_at_dealer'
      WHEN present_in_update THEN 'present'
      WHEN sequence_no-last_present_sequence<7 THEN 'absent_retained'
      ELSE 'absent_retired'
    END AS decision
  FROM running x
)
INSERT INTO public.pdc_navision_retention_observations_20260903(
  source_system,dealer_code,sequence_no,batch_id,backend_record_id,source_record_id,
  present_in_update,lifecycle_status,consecutive_absences,decision,record_is_current_after,
  record_status_after,missing_since_batch_id_after,evidence
)
SELECT d.source_system,d.dealer_code,d.sequence_no,d.batch_id,d.backend_record_id,d.source_record_id,
  d.present_in_update,d.lifecycle_status,d.consecutive_absences,d.decision,
  CASE WHEN d.present_in_update THEN true
       WHEN d.lifecycle_status='deliveredatdealer' THEN false
       ELSE d.consecutive_absences<7 END,
  CASE WHEN d.present_in_update THEN 'current'
       WHEN d.lifecycle_status='deliveredatdealer' THEN 'not_in_latest_batch'
       WHEN d.consecutive_absences<7 THEN 'current'
       ELSE 'not_in_latest_batch' END,
  CASE WHEN d.present_in_update OR (d.lifecycle_status<>'deliveredatdealer' AND d.consecutive_absences<7)
       THEN NULL ELSE d.batch_id END,
  jsonb_build_object('contract','pdc_navision_retention_20260903133000','bootstrap',true,
    'classification',d.classification,'threshold',7,'hard_delete',false)
FROM decisions d
ORDER BY d.source_system,d.dealer_code,d.sequence_no,d.backend_record_id;

CREATE OR REPLACE FUNCTION public.apply_navision_backend_import(
  p_idempotency_key text,p_rows jsonb,p_source_system text,p_dealer_code text,p_source_name text,
  p_source_timestamp timestamptz,p_source_hash text,p_preview_hash text,p_expected_revision bigint
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $apply$
DECLARE
  v_result jsonb;
  v_batch public.navision_import_batches%rowtype;
  v_sequence bigint;
  v_new_update boolean;
  v_record public.navision_backend_records%rowtype;
  v_previous_absences integer;
  v_consecutive_absences integer;
  v_present boolean;
  v_status text;
  v_decision text;
  v_retained integer:=0;
  v_retired integer:=0;
  v_terminal integer:=0;
  v_observations integer:=0;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     OR btrim(coalesce(p_dealer_code,'')) NOT IN('14450','37047') THEN
    RETURN public.navision_backend_response(false,'wrong_environment_or_scope');
  END IF;

  v_result:=public.apply_navision_backend_import_pre_20260902271000(
    p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
    p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision
  );
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;

  SELECT b.* INTO v_batch
  FROM public.navision_import_batches b
  WHERE b.idempotency_key=btrim(p_idempotency_key)
    AND b.source_system=lower(btrim(p_source_system))
    AND b.dealer_code=btrim(p_dealer_code)
    AND b.status='applied'
  ORDER BY b.applied_at DESC,b.id DESC LIMIT 1;
  IF v_batch.id IS NULL THEN
    RAISE EXCEPTION 'PDC_20260903133000_IMPORT_BATCH_READBACK_FAILED' USING errcode='55000';
  END IF;

  INSERT INTO public.pdc_navision_applicable_updates_20260903(
    source_system,dealer_code,sequence_no,batch_id,idempotency_key,source_hash,result_revision,applied_at
  ) VALUES(
    v_batch.source_system,v_batch.dealer_code,
    coalesce((SELECT max(u.sequence_no)+1 FROM public.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_batch.source_system AND u.dealer_code=v_batch.dealer_code),1),
    v_batch.id,v_batch.idempotency_key,v_batch.source_hash,v_batch.result_revision,v_batch.applied_at
  )
  ON CONFLICT(batch_id) DO NOTHING
  RETURNING sequence_no INTO v_sequence;
  v_new_update:=FOUND;

  IF NOT v_new_update THEN
    SELECT sequence_no INTO v_sequence
    FROM public.pdc_navision_applicable_updates_20260903 WHERE batch_id=v_batch.id;
    RETURN v_result||jsonb_build_object(
      'absence_retention_contract','absence_from_last_seven_applicable_updates',
      'applicable_update_sequence',v_sequence,
      'exact_retention_replay',true,
      'backend_only_retention',true,
      'board_lifecycle_mutated_by_retention',false
    );
  END IF;

  FOR v_record IN
    SELECT r.* FROM public.navision_backend_records r
    JOIN public.pdc_navision_applicable_updates_20260903 first_seen ON first_seen.batch_id=r.first_seen_batch_id
    WHERE r.source_system=v_batch.source_system
      AND r.dealer_code=v_batch.dealer_code
      AND first_seen.sequence_no<=v_sequence
    ORDER BY r.id FOR UPDATE OF r
  LOOP
    v_present:=v_record.last_seen_batch_id=v_batch.id;
    v_status:=public.navision_exact_lifecycle_status(v_record.normalized_data);
    SELECT o.consecutive_absences INTO v_previous_absences
    FROM public.pdc_navision_retention_observations_20260903 o
    WHERE o.source_system=v_batch.source_system AND o.dealer_code=v_batch.dealer_code
      AND o.backend_record_id=v_record.id AND o.sequence_no<v_sequence
    ORDER BY o.sequence_no DESC LIMIT 1;
    v_consecutive_absences:=CASE WHEN v_present THEN 0 ELSE coalesce(v_previous_absences,0)+1 END;

    IF v_status='deliveredatdealer' THEN
      v_decision:='delivered_at_dealer';
      v_terminal:=v_terminal+1;
    ELSIF v_present THEN
      v_decision:='present';
    ELSIF v_consecutive_absences<7
       AND public.pdc_navision_retain_after_absence_count_20260903(v_consecutive_absences,v_status) THEN
      UPDATE public.navision_backend_records
      SET is_current=true,record_status='current',missing_since_batch_id=null,updated_at=clock_timestamp()
      WHERE id=v_record.id;
      SELECT * INTO v_record FROM public.navision_backend_records WHERE id=v_record.id;
      v_decision:='absent_retained';
      v_retained:=v_retained+1;
    ELSE
      v_decision:='absent_retired';
      v_retired:=v_retired+1;
    END IF;

    INSERT INTO public.pdc_navision_retention_observations_20260903(
      source_system,dealer_code,sequence_no,batch_id,backend_record_id,source_record_id,
      present_in_update,lifecycle_status,consecutive_absences,decision,record_is_current_after,
      record_status_after,missing_since_batch_id_after,evidence
    ) VALUES(
      v_batch.source_system,v_batch.dealer_code,v_sequence,v_batch.id,v_record.id,v_record.source_record_id,
      v_present,v_status,v_consecutive_absences,v_decision,v_record.is_current,
      v_record.record_status,v_record.missing_since_batch_id,
      jsonb_build_object('contract','pdc_navision_retention_20260903133000','bootstrap',false,
        'threshold',public.pdc_navision_retention_threshold_20260903(),
        'last_seen_batch_id',v_record.last_seen_batch_id,'hard_delete',false,
        'evidence_sha256',encode(extensions.digest(convert_to(jsonb_build_object(
          'batch_id',v_batch.id,'backend_record_id',v_record.id,'sequence_no',v_sequence,
          'present',v_present,'status',v_status,'absences',v_consecutive_absences,
          'decision',v_decision,'is_current',v_record.is_current,'record_status',v_record.record_status
        )::text,'UTF8'),'sha256'),'hex'))
    );
    v_observations:=v_observations+1;
  END LOOP;

  RETURN v_result||jsonb_build_object(
    'absence_retention_contract','absence_from_last_seven_applicable_updates',
    'applicable_update_sequence',v_sequence,
    'exact_retention_replay',false,
    'retention_observations_appended',v_observations,
    'backend_rows_retained',v_retained,
    'backend_rows_retired',v_retired,
    'backend_rows_terminal',v_terminal,
    'backend_only_retention',true,
    'board_lifecycle_mutated_by_retention',false
  );
END
$apply$;
REVOKE ALL ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_navision_retention_readback_20260903(
  p_source_system text,p_dealer_code text,p_backend_record_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $readback$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_source text:=lower(btrim(coalesce(p_source_system,'')));
  v_dealer text:=btrim(coalesce(p_dealer_code,''));
  v_result jsonb;
BEGIN
  IF v_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  IF v_source<>'microsoft_navision' OR v_dealer NOT IN('14450','37047') THEN
    RETURN public.navision_backend_response(false,'invalid_scope');
  END IF;
  IF p_backend_record_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.navision_backend_records r WHERE r.id=p_backend_record_id
      AND r.source_system=v_source AND r.dealer_code=v_dealer
  ) THEN RETURN public.navision_backend_response(false,'record_not_in_scope'); END IF;

  SELECT jsonb_build_object(
    'contract','pdc_navision_retention_20260903133000',
    'source_system',v_source,'dealer_code',v_dealer,'threshold',7,
    'applicable_update_count',(SELECT count(*) FROM public.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_source AND u.dealer_code=v_dealer),
    'latest_update',(SELECT jsonb_build_object('sequence_no',u.sequence_no,'batch_id',u.batch_id,
        'source_hash',u.source_hash,'result_revision',u.result_revision,'applied_at',u.applied_at)
      FROM public.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_source AND u.dealer_code=v_dealer ORDER BY u.sequence_no DESC LIMIT 1),
    'latest_decisions',(SELECT coalesce(jsonb_object_agg(x.decision,x.count),'{}'::jsonb) FROM(
      SELECT o.decision,count(*) AS count
      FROM public.pdc_navision_retention_observations_20260903 o
      WHERE o.source_system=v_source AND o.dealer_code=v_dealer
        AND o.sequence_no=(SELECT max(u.sequence_no) FROM public.pdc_navision_applicable_updates_20260903 u
          WHERE u.source_system=v_source AND u.dealer_code=v_dealer)
      GROUP BY o.decision ORDER BY o.decision
    ) x),
    'record_observations',CASE WHEN p_backend_record_id IS NULL THEN '[]'::jsonb ELSE(
      SELECT coalesce(jsonb_agg(to_jsonb(y) ORDER BY y.sequence_no),'[]'::jsonb) FROM(
        SELECT o.sequence_no,o.batch_id,o.present_in_update,o.lifecycle_status,o.consecutive_absences,
          o.decision,o.record_is_current_after,o.record_status_after,o.missing_since_batch_id_after,o.recorded_at
        FROM public.pdc_navision_retention_observations_20260903 o
        WHERE o.source_system=v_source AND o.dealer_code=v_dealer AND o.backend_record_id=p_backend_record_id
        ORDER BY o.sequence_no DESC LIMIT 7
      ) y
    ) END,
    'history_sha256',(SELECT encode(extensions.digest(convert_to(coalesce(string_agg(
      jsonb_build_object('sequence_no',o.sequence_no,'batch_id',o.batch_id,'backend_record_id',o.backend_record_id,
        'present',o.present_in_update,'status',o.lifecycle_status,'absences',o.consecutive_absences,
        'decision',o.decision,'is_current',o.record_is_current_after,'record_status',o.record_status_after)::text,
      '' ORDER BY o.sequence_no,o.backend_record_id),'') ,'UTF8'),'sha256'),'hex')
      FROM public.pdc_navision_retention_observations_20260903 o
      WHERE o.source_system=v_source AND o.dealer_code=v_dealer),
    'history_immutable',true,'hard_delete',false,'production_touched',false
  ) INTO v_result;
  RETURN public.navision_backend_response(true,'navision_retention_readback',v_result);
END
$readback$;
REVOKE ALL ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid)
  FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_pdc_navision_retention_contract_20260903()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $validate$
DECLARE
  d text;
  v_ok boolean;
  v_updates bigint;
  v_observations bigint;
BEGIN
  IF public.current_pdc_user_role()::text NOT IN('viewer','operator','importer','administrator') THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  SELECT lower(pg_get_functiondef('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure)) INTO d;
  SELECT count(*) INTO v_updates FROM public.pdc_navision_applicable_updates_20260903;
  SELECT count(*) INTO v_observations FROM public.pdc_navision_retention_observations_20260903;
  v_ok:=public.pdc_monitor_staging_guard()
    AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
    AND public.pdc_navision_retain_after_absence_count_20260903(6,'plannedforproduction')
    AND NOT public.pdc_navision_retain_after_absence_count_20260903(7,'plannedforproduction')
    AND NOT public.pdc_navision_retain_after_absence_count_20260903(0,'deliveredatdealer')
    AND position($marker$set is_current=true,record_status='current',missing_since_batch_id=null$marker$ in replace(d,E'\n',' '))>0
    AND position('update public.navision_board_activations' in d)=0
    AND position('update public.vehicles' in d)=0
    AND position('delete from' in d)=0
    AND (SELECT count(*) FROM pg_trigger WHERE tgname IN(
      'pdc_navision_applicable_updates_immutable_20260903','pdc_navision_retention_observations_immutable_20260903'
    ) AND tgenabled<>'D')=2
    AND NOT has_table_privilege('authenticated','public.pdc_navision_applicable_updates_20260903','INSERT,UPDATE,DELETE,TRUNCATE')
    AND NOT has_table_privilege('authenticated','public.pdc_navision_retention_observations_20260903','INSERT,UPDATE,DELETE,TRUNCATE')
    AND NOT EXISTS(
      SELECT 1 FROM public.pdc_navision_retention_observations_20260903 o
      WHERE o.decision='absent_retained'
        AND (NOT o.record_is_current_after OR o.record_status_after<>'current' OR o.missing_since_batch_id_after IS NOT NULL)
    );
  RETURN public.navision_backend_response(v_ok,CASE WHEN v_ok THEN 'navision_retention_contract_valid' ELSE 'navision_retention_contract_invalid' END,
    jsonb_build_object('contract','pdc_navision_retention_20260903133000','threshold',7,
      'applicable_update_count',v_updates,'observation_count',v_observations,
      'history_immutable',true,'replay_safe',true,'hard_delete',false,'production_touched',false));
END
$validate$;
REVOKE ALL ON FUNCTION public.validate_pdc_navision_retention_contract_20260903()
  FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.validate_pdc_navision_retention_contract_20260903()
  TO authenticated;

DO $role_acl$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='pdc_email_monitor') THEN
    REVOKE ALL ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) FROM pdc_email_monitor;
    REVOKE ALL ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid) FROM pdc_email_monitor;
    REVOKE ALL ON FUNCTION public.validate_pdc_navision_retention_contract_20260903() FROM pdc_email_monitor;
    REVOKE ALL ON public.pdc_navision_applicable_updates_20260903 FROM pdc_email_monitor;
    REVOKE ALL ON public.pdc_navision_retention_observations_20260903 FROM pdc_email_monitor;
  END IF;
END
$role_acl$;

DO $post$
DECLARE
  d text;
BEGIN
  SELECT lower(pg_get_functiondef('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure)) INTO d;
  IF public.pdc_navision_retention_threshold_20260903()<>7
     OR NOT public.pdc_navision_retain_after_absence_count_20260903(6,'plannedforproduction')
     OR public.pdc_navision_retain_after_absence_count_20260903(7,'plannedforproduction')
     OR public.pdc_navision_retain_after_absence_count_20260903(0,'deliveredatdealer')
     OR position($marker$set is_current=true,record_status='current',missing_since_batch_id=null$marker$ in replace(d,E'\n',' '))=0
     OR position('on conflict(batch_id) do nothing' in d)=0
     OR position('exact_retention_replay' in d)=0
     OR position('update public.navision_board_activations' in d)>0
     OR position('update public.vehicles' in d)>0
     OR position('delete from' in d)>0
     OR (SELECT count(*) FROM public.pdc_navision_applicable_updates_20260903)<>
        (SELECT count(*) FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code IN('14450','37047') AND status='applied')
     OR EXISTS(
       SELECT 1 FROM public.pdc_navision_retention_observations_20260903 o
       WHERE o.decision='absent_retained'
         AND (NOT o.record_is_current_after OR o.record_status_after<>'current' OR o.missing_since_batch_id_after IS NOT NULL)
     )
     OR has_function_privilege('public','public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)','EXECUTE')
     OR has_function_privilege('anon','public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)','EXECUTE')
     OR has_function_privilege('service_role','public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_20260903133000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260903133000','navision_seven_update_retention_ledger_20260903',ARRAY[
    'Dealer-scoped immutable applicable-update sequencing for Broome 37047 and Pilbara 14450; only successful applied batches count and exact batch replay allocates no new sequence',
    'Immutable per-record observations preserve present/absent evidence, consecutive absence count, decision and exact post-decision backend state',
    'First six applicable same-dealer absences restore is_current, record_status current and null missing marker; seventh absence remains retired without hard deletion',
    'Exact Delivered at Dealer remains terminal for lifecycle reconciliation and is never reopened or rewritten by retention',
    'Authenticated readback and validator expose exact ledger state and history digest while RLS and append-only triggers deny history mutation',
    'STAGING cdsmnqxtyyoeoznmbidd only; Production, vehicles, Board activation, mailbox and outbound email paths untouched'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
