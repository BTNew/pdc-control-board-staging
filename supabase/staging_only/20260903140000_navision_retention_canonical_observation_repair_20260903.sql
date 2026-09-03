-- STAGING ONLY 20260903140000: canonical observation repair for sparse
-- legacy missing-item history. Migration 133000 proved the installed 271000
-- wrapper restored is_current without record_status=current; later absences
-- therefore lacked missing items. Absence is now derived from non-presence in
-- every applicable same-dealer update, with an immutable correction receipt.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-navision-retention-canonical-20260903140000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
LOCK TABLE public.pdc_navision_applicable_updates_20260903 IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.pdc_navision_retention_observations_20260903 IN SHARE MODE;
LOCK TABLE public.navision_import_batches IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.navision_import_items IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE v_apply_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_apply_sha
  FROM pg_proc p WHERE p.oid='public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure;
  IF current_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR current_setting('app.environment',true)='production'
     OR (SELECT max(version) FILTER (WHERE version ~ '^[0-9]{14}$') FROM supabase_migrations.schema_migrations) <> '20260903137000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version = '20260903137000' AND name = 'external_completion_booking_history_revision_20260903') <> 1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version = '20260903136000' AND name = 'external_completion_residual_booking_soft_delete_20260903') <> 1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version = '20260903135000' AND name = 'external_completion_hidden_booking_cancel_20260903') <> 1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version = '20260903134000' AND name = 'external_completion_review_repairs_20260903') <> 1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903133000' AND name='navision_seven_update_retention_ledger_20260903')<>1
     OR v_apply_sha<>'e7f9423b9abfeaf216ca2c6a950a26809a7d9d3a4ecbc6c949517cbf7bfca44b'
     OR to_regclass('public.pdc_navision_retention_canonical_observations_20260903') IS NOT NULL
     OR to_regclass('public.pdc_navision_retention_reconciliation_receipts_20260903') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903140000_STAGING_PREDECESSOR_OR_ENVIRONMENT_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_navision_retention_canonical_observations_20260903(
  source_system text NOT NULL CHECK(source_system='microsoft_navision'),
  dealer_code text NOT NULL CHECK(dealer_code IN('14450','37047')),
  sequence_no bigint NOT NULL CHECK(sequence_no>0),
  batch_id uuid NOT NULL REFERENCES public.navision_import_batches(id) ON DELETE RESTRICT,
  backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  source_record_id text NOT NULL,
  first_sequence bigint NOT NULL CHECK(first_sequence>0),
  present_in_update boolean NOT NULL,
  lifecycle_status text NOT NULL,
  consecutive_absences integer NOT NULL CHECK(consecutive_absences BETWEEN 0 AND 7),
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
CREATE INDEX pdc_navision_retention_canonical_record_20260903
  ON public.pdc_navision_retention_canonical_observations_20260903(backend_record_id,sequence_no DESC);

CREATE TABLE public.pdc_navision_retention_reconciliation_receipts_20260903(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  backend_record_id uuid NOT NULL UNIQUE REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  source_system text NOT NULL CHECK(source_system='microsoft_navision'),
  dealer_code text NOT NULL CHECK(dealer_code IN('14450','37047')),
  sequence_no bigint NOT NULL CHECK(sequence_no>0),
  decision text NOT NULL CHECK(decision='absent_retained'),
  before_record jsonb NOT NULL CHECK(jsonb_typeof(before_record)='object'),
  after_record jsonb NOT NULL CHECK(jsonb_typeof(after_record)='object'),
  receipt_sha256 text CHECK(receipt_sha256 IS NULL OR receipt_sha256~'^[0-9a-f]{64}$'),
  corrected_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE public.pdc_navision_retention_canonical_observations_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_retention_reconciliation_receipts_20260903 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_navision_retention_canonical_observations_20260903 FROM public,anon,authenticated,service_role;
REVOKE ALL ON public.pdc_navision_retention_reconciliation_receipts_20260903 FROM public,anon,authenticated,service_role;
GRANT SELECT ON public.pdc_navision_retention_canonical_observations_20260903 TO authenticated;
GRANT SELECT ON public.pdc_navision_retention_reconciliation_receipts_20260903 TO authenticated;
CREATE POLICY pdc_navision_retention_canonical_read_20260903
ON public.pdc_navision_retention_canonical_observations_20260903 FOR SELECT TO authenticated
USING(public.current_pdc_user_role()::text IN('viewer','operator','importer','administrator'));
CREATE POLICY pdc_navision_retention_reconciliation_read_20260903
ON public.pdc_navision_retention_reconciliation_receipts_20260903 FOR SELECT TO authenticated
USING(public.current_pdc_user_role()::text IN('viewer','operator','importer','administrator'));

-- Every record is observed at every applicable same-dealer update from its
-- first scoped sequence. A sparse legacy import item means absent, never
-- present. The nearest prior present item supplies the status at that update.
WITH item_state AS MATERIALIZED(
  SELECT u.source_system,u.dealer_code,u.sequence_no,u.batch_id,r.id AS backend_record_id,
    r.source_record_id,first_seen.sequence_no AS first_sequence,i.classification,
    coalesce(i.classification IN('new','changed','unchanged'),false) AS present_in_update,
    public.navision_exact_lifecycle_status(coalesce(
      i.after_record->'normalized_data',i.before_record->'normalized_data',
      prior.after_record->'normalized_data',prior.before_record->'normalized_data',r.normalized_data
    )) AS lifecycle_status
  FROM public.pdc_navision_applicable_updates_20260903 u
  JOIN public.navision_backend_records r
    ON r.source_system=u.source_system AND r.dealer_code=u.dealer_code
  JOIN public.pdc_navision_applicable_updates_20260903 first_seen
    ON first_seen.batch_id=r.first_seen_batch_id
   AND first_seen.source_system=u.source_system AND first_seen.dealer_code=u.dealer_code
   AND first_seen.sequence_no<=u.sequence_no
  LEFT JOIN LATERAL(
    SELECT x.* FROM public.navision_import_items x
    WHERE x.batch_id=u.batch_id AND x.backend_record_id=r.id
    ORDER BY x.id LIMIT 1
  ) i ON true
  LEFT JOIN LATERAL(
    SELECT x.* FROM public.navision_import_items x
    JOIN public.pdc_navision_applicable_updates_20260903 ux ON ux.batch_id=x.batch_id
    WHERE x.backend_record_id=r.id AND ux.source_system=u.source_system AND ux.dealer_code=u.dealer_code
      AND ux.sequence_no<=u.sequence_no AND x.classification IN('new','changed','unchanged')
    ORDER BY ux.sequence_no DESC,x.id LIMIT 1
  ) prior ON true
), running AS MATERIALIZED(
  SELECT s.*,
    max(sequence_no) FILTER(WHERE present_in_update) OVER(
      PARTITION BY backend_record_id ORDER BY sequence_no ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS last_present_sequence
  FROM item_state s
), decisions AS(
  SELECT x.*,
    CASE WHEN present_in_update THEN 0 ELSE least(7,(sequence_no-coalesce(last_present_sequence,first_sequence-1))::integer) END AS consecutive_absences
  FROM running x
)
INSERT INTO public.pdc_navision_retention_canonical_observations_20260903(
  source_system,dealer_code,sequence_no,batch_id,backend_record_id,source_record_id,first_sequence,
  present_in_update,lifecycle_status,consecutive_absences,decision,record_is_current_after,
  record_status_after,missing_since_batch_id_after,evidence
)
SELECT d.source_system,d.dealer_code,d.sequence_no,d.batch_id,d.backend_record_id,d.source_record_id,d.first_sequence,
  d.present_in_update,d.lifecycle_status,d.consecutive_absences,
  CASE WHEN d.lifecycle_status='deliveredatdealer' THEN 'delivered_at_dealer'
       WHEN d.present_in_update THEN 'present'
       WHEN d.consecutive_absences<public.pdc_navision_retention_threshold_20260903() THEN 'absent_retained'
       ELSE 'absent_retired' END,
  CASE WHEN d.present_in_update THEN true
       WHEN d.lifecycle_status='deliveredatdealer' THEN false
       ELSE d.consecutive_absences<public.pdc_navision_retention_threshold_20260903() END,
  CASE WHEN d.present_in_update THEN 'current'
       WHEN d.lifecycle_status='deliveredatdealer' THEN 'not_in_latest_batch'
       WHEN d.consecutive_absences<public.pdc_navision_retention_threshold_20260903() THEN 'current'
       ELSE 'not_in_latest_batch' END,
  CASE WHEN d.present_in_update OR (d.lifecycle_status<>'deliveredatdealer'
         AND d.consecutive_absences<public.pdc_navision_retention_threshold_20260903())
       THEN NULL ELSE d.batch_id END,
  jsonb_build_object('contract','pdc_navision_retention_canonical_20260903140000','bootstrap',true,
    'classification',d.classification,'sparse_item_absent',d.classification IS NULL,
    'last_present_sequence',d.last_present_sequence,'first_sequence',d.first_sequence,
    'threshold',public.pdc_navision_retention_threshold_20260903(),'hard_delete',false)
FROM decisions d
ORDER BY d.source_system,d.dealer_code,d.sequence_no,d.backend_record_id;

-- Capture and repair only latest canonical absent-retained rows whose old gate
-- left them hidden. The one-time repair suppresses only the three exact backend
-- propagation/parity triggers, preserving their original enabled state and
-- leaving vehicle/Board/OD rows untouched. The future wrapper retains normal
-- operational reconciliation. Delivered at Dealer rows are excluded.
INSERT INTO public.pdc_navision_retention_reconciliation_receipts_20260903(
  backend_record_id,source_system,dealer_code,sequence_no,decision,before_record,after_record
)
SELECT r.id,o.source_system,o.dealer_code,o.sequence_no,o.decision,to_jsonb(r),'{}'::jsonb
FROM public.navision_backend_records r
JOIN public.pdc_navision_retention_canonical_observations_20260903 o ON o.backend_record_id=r.id
WHERE o.sequence_no=(SELECT max(u.sequence_no) FROM public.pdc_navision_applicable_updates_20260903 u
    WHERE u.source_system=o.source_system AND u.dealer_code=o.dealer_code)
  AND o.decision='absent_retained'
  AND (NOT r.is_current OR r.record_status<>'current' OR r.missing_since_batch_id IS NOT NULL)
ORDER BY r.id;

DO $triggers$
BEGIN
  IF (SELECT count(*) FROM pg_trigger
      WHERE tgrelid='public.navision_backend_records'::regclass
        AND tgname IN('navision_record_operational_reconcile','zz_navision_record_sublet_sync','zz_navision_all_vehicle_parity_494')
        AND tgenabled='O')<>3
  THEN RAISE EXCEPTION 'PDC_20260903140000_TRIGGER_STATE_FAILED' USING errcode='55000'; END IF;
END $triggers$;
ALTER TABLE public.navision_backend_records DISABLE TRIGGER navision_record_operational_reconcile;
ALTER TABLE public.navision_backend_records DISABLE TRIGGER zz_navision_record_sublet_sync;
ALTER TABLE public.navision_backend_records DISABLE TRIGGER zz_navision_all_vehicle_parity_494;
UPDATE public.navision_backend_records r
SET is_current=true,record_status='current',missing_since_batch_id=NULL,updated_at=clock_timestamp()
FROM public.pdc_navision_retention_reconciliation_receipts_20260903 x
WHERE x.backend_record_id=r.id;
ALTER TABLE public.navision_backend_records ENABLE TRIGGER navision_record_operational_reconcile;
ALTER TABLE public.navision_backend_records ENABLE TRIGGER zz_navision_record_sublet_sync;
ALTER TABLE public.navision_backend_records ENABLE TRIGGER zz_navision_all_vehicle_parity_494;

UPDATE public.pdc_navision_retention_reconciliation_receipts_20260903 x
SET after_record=to_jsonb(r),
  receipt_sha256=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract','pdc_navision_retention_reconciliation_20260903140000',
    'backend_record_id',x.backend_record_id,'sequence_no',x.sequence_no,
    'before_record',x.before_record,'after_record',to_jsonb(r),'hard_delete',false
  )::text,'UTF8'),'sha256'),'hex')
FROM public.navision_backend_records r WHERE r.id=x.backend_record_id;

CREATE TRIGGER pdc_navision_retention_canonical_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_navision_retention_canonical_observations_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_navision_retention_immutable_20260903();
CREATE TRIGGER pdc_navision_retention_reconciliation_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_navision_retention_reconciliation_receipts_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_navision_retention_immutable_20260903();

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
  v_first_sequence bigint;
  v_last_present_sequence bigint;
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

  SELECT b.* INTO v_batch FROM public.navision_import_batches b
  WHERE b.idempotency_key=btrim(p_idempotency_key)
    AND b.source_system=lower(btrim(p_source_system)) AND b.dealer_code=btrim(p_dealer_code)
    AND b.status='applied' ORDER BY b.applied_at DESC,b.id DESC LIMIT 1;
  IF v_batch.id IS NULL THEN RAISE EXCEPTION 'PDC_20260903140000_IMPORT_BATCH_READBACK_FAILED' USING errcode='55000'; END IF;

  INSERT INTO public.pdc_navision_applicable_updates_20260903(
    source_system,dealer_code,sequence_no,batch_id,idempotency_key,source_hash,result_revision,applied_at
  ) VALUES(v_batch.source_system,v_batch.dealer_code,
    coalesce((SELECT max(u.sequence_no)+1 FROM public.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_batch.source_system AND u.dealer_code=v_batch.dealer_code),1),
    v_batch.id,v_batch.idempotency_key,v_batch.source_hash,v_batch.result_revision,v_batch.applied_at)
  ON CONFLICT(batch_id) DO NOTHING RETURNING sequence_no INTO v_sequence;
  v_new_update:=FOUND;
  IF NOT v_new_update THEN
    SELECT sequence_no INTO v_sequence FROM public.pdc_navision_applicable_updates_20260903 WHERE batch_id=v_batch.id;
    RETURN v_result||jsonb_build_object('absence_retention_contract','absence_from_last_seven_applicable_updates',
      'canonical_observation_contract','pdc_navision_retention_canonical_20260903140000',
      'applicable_update_sequence',v_sequence,'exact_retention_replay',true,
      'backend_only_retention',true,'direct_board_write_by_retention',false,'existing_operational_reconciliation_preserved',true);
  END IF;

  FOR v_record IN SELECT r.* FROM public.navision_backend_records r
    WHERE r.source_system=v_batch.source_system AND r.dealer_code=v_batch.dealer_code
    ORDER BY r.id FOR UPDATE
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM public.navision_import_items i
      WHERE i.batch_id=v_batch.id AND i.backend_record_id=v_record.id
        AND i.classification IN('new','changed','unchanged')
    ) INTO v_present;
    v_status:=public.navision_exact_lifecycle_status(v_record.normalized_data);
    SELECT min(o.first_sequence),max(o.sequence_no) FILTER(WHERE o.present_in_update)
      INTO v_first_sequence,v_last_present_sequence
    FROM public.pdc_navision_retention_canonical_observations_20260903 o
    WHERE o.source_system=v_batch.source_system AND o.dealer_code=v_batch.dealer_code
      AND o.backend_record_id=v_record.id;
    v_first_sequence:=coalesce(v_first_sequence,v_sequence);
    v_consecutive_absences:=CASE WHEN v_present THEN 0 ELSE least(7,(v_sequence-coalesce(v_last_present_sequence,v_first_sequence-1))::integer) END;

    IF v_status='deliveredatdealer' THEN v_decision:='delivered_at_dealer';v_terminal:=v_terminal+1;
    ELSIF v_present THEN v_decision:='present';
    ELSIF v_consecutive_absences<public.pdc_navision_retention_threshold_20260903()
      AND public.pdc_navision_retain_after_absence_count_20260903(v_consecutive_absences,v_status) THEN
      UPDATE public.navision_backend_records
      SET is_current=true,record_status='current',missing_since_batch_id=NULL,updated_at=clock_timestamp()
      WHERE id=v_record.id;
      SELECT * INTO v_record FROM public.navision_backend_records WHERE id=v_record.id;
      v_decision:='absent_retained';v_retained:=v_retained+1;
    ELSE v_decision:='absent_retired';v_retired:=v_retired+1;
    END IF;

    INSERT INTO public.pdc_navision_retention_canonical_observations_20260903(
      source_system,dealer_code,sequence_no,batch_id,backend_record_id,source_record_id,first_sequence,
      present_in_update,lifecycle_status,consecutive_absences,decision,record_is_current_after,
      record_status_after,missing_since_batch_id_after,evidence
    ) VALUES(v_batch.source_system,v_batch.dealer_code,v_sequence,v_batch.id,v_record.id,v_record.source_record_id,v_first_sequence,
      v_present,v_status,v_consecutive_absences,v_decision,v_record.is_current,v_record.record_status,v_record.missing_since_batch_id,
      jsonb_build_object('contract','pdc_navision_retention_canonical_20260903140000','bootstrap',false,
        'threshold',public.pdc_navision_retention_threshold_20260903(),'last_present_sequence',v_last_present_sequence,
        'hard_delete',false,'evidence_sha256',encode(extensions.digest(convert_to(jsonb_build_object(
          'batch_id',v_batch.id,'record_id',v_record.id,'sequence',v_sequence,'first_sequence',v_first_sequence,
          'present',v_present,'status',v_status,'absences',v_consecutive_absences,'decision',v_decision,
          'is_current',v_record.is_current,'record_status',v_record.record_status
        )::text,'UTF8'),'sha256'),'hex')));
    v_observations:=v_observations+1;
  END LOOP;

  RETURN v_result||jsonb_build_object('absence_retention_contract','absence_from_last_seven_applicable_updates',
    'canonical_observation_contract','pdc_navision_retention_canonical_20260903140000',
    'applicable_update_sequence',v_sequence,'exact_retention_replay',false,
    'retention_observations_appended',v_observations,'backend_rows_retained',v_retained,
    'backend_rows_retired',v_retired,'backend_rows_terminal',v_terminal,
    'backend_only_retention',true,'direct_board_write_by_retention',false,'existing_operational_reconciliation_preserved',true);
END
$apply$;
REVOKE ALL ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_navision_retention_readback_20260903(
  p_source_system text,p_dealer_code text,p_backend_record_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $readback$
DECLARE v_role text:=public.current_pdc_user_role()::text;v_source text:=lower(btrim(coalesce(p_source_system,'')));v_dealer text:=btrim(coalesce(p_dealer_code,''));v_result jsonb;
BEGIN
  IF v_role NOT IN('viewer','operator','importer','administrator') THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
  IF v_source<>'microsoft_navision' OR v_dealer NOT IN('14450','37047') THEN RETURN public.navision_backend_response(false,'invalid_scope'); END IF;
  IF p_backend_record_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records r
    WHERE r.id=p_backend_record_id AND r.source_system=v_source AND r.dealer_code=v_dealer)
  THEN RETURN public.navision_backend_response(false,'record_not_in_scope'); END IF;
  SELECT jsonb_build_object('contract','pdc_navision_retention_canonical_20260903140000',
    'source_system',v_source,'dealer_code',v_dealer,'threshold',7,
    'applicable_update_count',(SELECT count(*) FROM public.pdc_navision_applicable_updates_20260903 u WHERE u.source_system=v_source AND u.dealer_code=v_dealer),
    'latest_update',(SELECT jsonb_build_object('sequence_no',u.sequence_no,'batch_id',u.batch_id,'source_hash',u.source_hash,
      'result_revision',u.result_revision,'applied_at',u.applied_at) FROM public.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_source AND u.dealer_code=v_dealer ORDER BY u.sequence_no DESC LIMIT 1),
    'latest_decisions',(SELECT coalesce(jsonb_object_agg(x.decision,x.count),'{}'::jsonb) FROM(
      SELECT o.decision,count(*) count FROM public.pdc_navision_retention_canonical_observations_20260903 o
      WHERE o.source_system=v_source AND o.dealer_code=v_dealer AND o.sequence_no=(SELECT max(u.sequence_no)
        FROM public.pdc_navision_applicable_updates_20260903 u WHERE u.source_system=v_source AND u.dealer_code=v_dealer)
      GROUP BY o.decision ORDER BY o.decision)x),
    'record_observations',CASE WHEN p_backend_record_id IS NULL THEN '[]'::jsonb ELSE(SELECT coalesce(jsonb_agg(to_jsonb(y) ORDER BY y.sequence_no),'[]'::jsonb) FROM(
      SELECT o.sequence_no,o.batch_id,o.present_in_update,o.lifecycle_status,o.consecutive_absences,o.decision,
        o.record_is_current_after,o.record_status_after,o.missing_since_batch_id_after,o.recorded_at
      FROM public.pdc_navision_retention_canonical_observations_20260903 o
      WHERE o.source_system=v_source AND o.dealer_code=v_dealer AND o.backend_record_id=p_backend_record_id
      ORDER BY o.sequence_no DESC LIMIT 7)y) END,
    'history_sha256',(SELECT encode(extensions.digest(convert_to(coalesce(string_agg(jsonb_build_object(
      'sequence',o.sequence_no,'batch',o.batch_id,'record',o.backend_record_id,'present',o.present_in_update,
      'status',o.lifecycle_status,'absences',o.consecutive_absences,'decision',o.decision,
      'current',o.record_is_current_after,'record_status',o.record_status_after)::text,'' ORDER BY o.sequence_no,o.backend_record_id),''),'UTF8'),'sha256'),'hex')
      FROM public.pdc_navision_retention_canonical_observations_20260903 o WHERE o.source_system=v_source AND o.dealer_code=v_dealer),
    'reconciliation_receipt_count',(SELECT count(*) FROM public.pdc_navision_retention_reconciliation_receipts_20260903 x
      WHERE x.source_system=v_source AND x.dealer_code=v_dealer),
    'history_immutable',true,'hard_delete',false,'production_touched',false) INTO v_result;
  RETURN public.navision_backend_response(true,'navision_retention_readback',v_result);
END
$readback$;
REVOKE ALL ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_pdc_navision_retention_contract_20260903()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $validate$
DECLARE d text;v_ok boolean;v_updates bigint;v_observations bigint;v_corrections bigint;
BEGIN
  IF public.current_pdc_user_role()::text NOT IN('viewer','operator','importer','administrator') THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
  SELECT lower(pg_get_functiondef('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure)) INTO d;
  SELECT count(*) INTO v_updates FROM public.pdc_navision_applicable_updates_20260903;
  SELECT count(*) INTO v_observations FROM public.pdc_navision_retention_canonical_observations_20260903;
  SELECT count(*) INTO v_corrections FROM public.pdc_navision_retention_reconciliation_receipts_20260903;
  v_ok:=public.pdc_monitor_staging_guard() AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
    AND public.pdc_navision_retain_after_absence_count_20260903(6,'plannedforproduction')
    AND NOT public.pdc_navision_retain_after_absence_count_20260903(7,'plannedforproduction')
    AND NOT public.pdc_navision_retain_after_absence_count_20260903(0,'deliveredatdealer')
    AND position('max(o.sequence_no)filter(whereo.present_in_update)' in replace(d,' ',''))>0
    AND position($m$record_status='current'$m$ in d)>0
    AND position('update public.navision_board_activations' in d)=0 AND position('update public.vehicles' in d)=0 AND position('delete from' in d)=0
    AND NOT EXISTS(SELECT 1 FROM public.pdc_navision_retention_canonical_observations_20260903 o
      JOIN public.navision_backend_records r ON r.id=o.backend_record_id
      WHERE o.sequence_no=(SELECT max(u.sequence_no) FROM public.pdc_navision_applicable_updates_20260903 u
        WHERE u.source_system=o.source_system AND u.dealer_code=o.dealer_code)
        AND ((o.decision='absent_retained' AND (NOT r.is_current OR r.record_status<>'current' OR r.missing_since_batch_id IS NOT NULL))
          OR (o.decision='absent_retired' AND r.is_current)))
    AND NOT EXISTS(SELECT 1 FROM public.pdc_navision_retention_canonical_observations_20260903
      WHERE consecutive_absences NOT BETWEEN 0 AND 7 OR (decision='absent_retired' AND consecutive_absences<>7));
  RETURN public.navision_backend_response(v_ok,CASE WHEN v_ok THEN 'navision_retention_contract_valid' ELSE 'navision_retention_contract_invalid' END,
    jsonb_build_object('contract','pdc_navision_retention_canonical_20260903140000','threshold',7,
      'applicable_update_count',v_updates,'observation_count',v_observations,'reconciliation_receipt_count',v_corrections,
      'history_immutable',true,'replay_safe',true,'hard_delete',false,'production_touched',false));
END
$validate$;
REVOKE ALL ON FUNCTION public.validate_pdc_navision_retention_contract_20260903() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.validate_pdc_navision_retention_contract_20260903() TO authenticated;

DO $acl$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='pdc_email_monitor') THEN
    REVOKE ALL ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) FROM pdc_email_monitor;
    REVOKE ALL ON FUNCTION public.get_pdc_navision_retention_readback_20260903(text,text,uuid) FROM pdc_email_monitor;
    REVOKE ALL ON FUNCTION public.validate_pdc_navision_retention_contract_20260903() FROM pdc_email_monitor;
    REVOKE ALL ON public.pdc_navision_retention_canonical_observations_20260903 FROM pdc_email_monitor;
    REVOKE ALL ON public.pdc_navision_retention_reconciliation_receipts_20260903 FROM pdc_email_monitor;
  END IF;
END
$acl$;

DO $post$
DECLARE d text;
BEGIN
  SELECT lower(pg_get_functiondef('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure)) INTO d;
  IF EXISTS(SELECT 1 FROM public.pdc_navision_retention_canonical_observations_20260903
       WHERE consecutive_absences NOT BETWEEN 0 AND 7 OR (decision='absent_retired' AND consecutive_absences<>7))
     OR EXISTS(SELECT 1 FROM public.pdc_navision_retention_canonical_observations_20260903 o
       JOIN public.navision_backend_records r ON r.id=o.backend_record_id
       WHERE o.sequence_no=(SELECT max(u.sequence_no) FROM public.pdc_navision_applicable_updates_20260903 u
         WHERE u.source_system=o.source_system AND u.dealer_code=o.dealer_code)
         AND ((o.decision='absent_retained' AND (NOT r.is_current OR r.record_status<>'current' OR r.missing_since_batch_id IS NOT NULL))
           OR (o.decision='absent_retired' AND r.is_current)))
     OR EXISTS(SELECT 1 FROM public.pdc_navision_retention_reconciliation_receipts_20260903
       WHERE receipt_sha256 IS NULL OR after_record='{}'::jsonb)
     OR position('max(o.sequence_no)filter(whereo.present_in_update)' in replace(d,' ',''))=0
     OR position('update public.navision_board_activations' in d)>0 OR position('update public.vehicles' in d)>0 OR position('delete from' in d)>0
     OR (SELECT count(*) FROM pg_trigger WHERE tgname IN('pdc_navision_retention_canonical_immutable_20260903','pdc_navision_retention_reconciliation_immutable_20260903') AND tgenabled<>'D')<>2
     OR has_table_privilege('authenticated','public.pdc_navision_retention_canonical_observations_20260903','INSERT,UPDATE,DELETE,TRUNCATE')
     OR has_table_privilege('authenticated','public.pdc_navision_retention_reconciliation_receipts_20260903','INSERT,UPDATE,DELETE,TRUNCATE')
  THEN RAISE EXCEPTION 'PDC_20260903140000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260903140000','navision_retention_canonical_observation_repair_20260903',ARRAY[
    'Repair sparse legacy missing-item history by treating non-presence in every applicable same-dealer update as absence',
    'Anchor consecutive absence at exact first dealer sequence and cap retirement state at exact threshold seven',
    'Append immutable canonical observations without rewriting migration 133000 audit history',
    'Reconcile hidden absent-retained backend rows to is_current true, record_status current and null missing marker with immutable before/after receipts',
    'Rebind apply, readback and validator to canonical observations and last actual presence; exact replay allocates no sequence or observation',
    'suppress only exact propagation/parity triggers for one-time retained-state reconciliation; future imports preserve normal operational reconciliation',
    'STAGING cdsmnqxtyyoeoznmbidd only; Production, mailbox, outbound email and hard-delete paths untouched'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
