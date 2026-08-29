-- STAGING ONLY 768: atomic batch editing for canonical Job Card operation hours.
-- Parts is deliberately excluded: it is a completion state, never labour hours.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-768-workshop-hours-batch',0));

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$') IS DISTINCT FROM '20260830060000'
    OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830060000' AND name='767_qc_vehicle_reject_to_pmb_stoppage')
    OR to_regclass('public.vehicles') IS NULL
    OR to_regclass('public.pdc_authenticated_email_operation_lines') IS NULL
    OR to_regclass('public.vehicle_workshop_line_adjustments') IS NULL
    OR to_regclass('public.audit_events') IS NULL
    OR to_regclass('public.pdc_email_vehicle_revision') IS NULL
    OR to_regprocedure('public.require_pdc_role(public.pdc_role)') IS NULL
    OR to_regprocedure('public.workshop_stage_code_for_work_key(text)') IS NULL
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830070000')
  THEN RAISE EXCEPTION 'PDC_768_EXACT_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.vehicle_workshop_hours_batch_receipts_768(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key uuid NOT NULL,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  request_hash text NOT NULL CHECK(request_hash~'^[a-f0-9]{64}$'),
  base_vehicle_version bigint NOT NULL CHECK(base_vehicle_version>=1),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.vehicle_workshop_hours_batch_receipts_768 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_workshop_hours_batch_receipts_768 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.vehicle_workshop_hours_batch_receipts_768 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.vehicle_workshop_hours_batch_receipt_immutable_768()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_768_APPEND_ONLY_HOURS_BATCH_RECEIPT' USING errcode='55000'; END $$;
CREATE TRIGGER vehicle_workshop_hours_batch_receipt_immutable
BEFORE UPDATE OR DELETE ON public.vehicle_workshop_hours_batch_receipts_768
FOR EACH ROW EXECUTE FUNCTION public.vehicle_workshop_hours_batch_receipt_immutable_768();
REVOKE ALL ON FUNCTION public.vehicle_workshop_hours_batch_receipt_immutable_768() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.save_vehicle_workshop_line_hours_batch_768(
  p_vehicle_id uuid,
  p_stock_number text,
  p_job_card_number text,
  p_expected_vehicle_version bigint,
  p_estimated_rows jsonb,
  p_idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $save$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_vehicle public.vehicles%rowtype;
  v_receipt public.vehicle_workshop_hours_batch_receipts_768%rowtype;
  v_rows jsonb:=coalesce(p_estimated_rows,'[]'::jsonb);
  v_canonical_rows jsonb;
  v_request jsonb;
  v_request_hash text;
  v_current_rows jsonb:='[]'::jsonb;
  v_conflicts jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
  v_revision bigint;
  v_vehicle_after public.vehicles%rowtype;
  v_changed_count integer:=0;
  v_receipt_id uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  PERFORM public.require_pdc_role('operator');

  IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR jsonb_typeof(v_rows)<>'array' OR jsonb_array_length(v_rows) NOT BETWEEN 1 AND 250
    OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(v_rows) x
      WHERE jsonb_typeof(x)<>'object'
        OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
           IS DISTINCT FROM ARRAY['adjustment_id','estimated_hours','expected_line_version','line_key','operation_line_id','stage_code','work_key']::text[]
        OR coalesce(x->>'operation_line_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(x->>'line_key','')<>('source:'||lower(coalesce(x->>'operation_line_id','')))
        OR coalesce(x->>'work_key','')<>lower(btrim(coalesce(x->>'work_key','')))
        OR coalesce(x->>'work_key','') IN ('parts','pit_inspection','unallocated_mapping_review')
        OR coalesce(x->>'stage_code','')<>upper(btrim(coalesce(x->>'stage_code','')))
        OR coalesce(x->>'stage_code','') !~ '^[A-Z][A-Z0-9_]{1,39}$'
        OR coalesce(x->>'expected_line_version','') !~ '^[0-9]+$'
        OR jsonb_typeof(x->'adjustment_id') IS NULL
        OR (jsonb_typeof(x->'adjustment_id')='string' AND coalesce(x->>'adjustment_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        OR jsonb_typeof(x->'adjustment_id') NOT IN ('string','null')
        OR jsonb_typeof(x->'estimated_hours') IS NULL
        OR jsonb_typeof(x->'estimated_hours') NOT IN ('number','null')
        OR (jsonb_typeof(x->'estimated_hours')='number' AND (
          coalesce(x->>'estimated_hours','') !~ '^(0|[0-9]+)(\.[0-9]{1,2})?$'
          OR (x->>'estimated_hours')::numeric<0 OR (x->>'estimated_hours')::numeric>999.99
        ))
    )
    OR (SELECT count(*) FROM jsonb_array_elements(v_rows))
      <>(SELECT count(DISTINCT lower(x->>'operation_line_id')) FROM jsonb_array_elements(v_rows) x)
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_hours_batch'); END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY lower(x->>'operation_line_id')),'[]'::jsonb)
    INTO v_canonical_rows FROM jsonb_array_elements(v_rows) x;
  v_request:=jsonb_build_object(
    'contract','vehicle_workshop_hours_batch_768','actor_id',v_actor,'vehicle_id',p_vehicle_id,
    'stock_number',btrim(p_stock_number),'job_card_number',btrim(p_job_card_number),
    'expected_vehicle_version',p_expected_vehicle_version,'estimated_rows',v_canonical_rows,
    'idempotency_key',p_idempotency_key);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-workshop-hours-batch:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.vehicle_workshop_hours_batch_receipts_768
   WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict','data',jsonb_build_object('receipt_id',v_receipt.receipt_id));
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles
   WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF btrim(coalesce(v_vehicle.stock_number::text,''))<>btrim(p_stock_number)
     OR btrim(coalesce(v_vehicle.job_card_number,''))<>btrim(p_job_card_number) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'requested_stock_number',p_stock_number,'requested_job_card_number',p_job_card_number));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_request_768 ON COMMIT DROP AS
  SELECT lower(x->>'operation_line_id')::uuid operation_line_id,
    NULLIF(x->>'adjustment_id','')::uuid adjustment_id,
    (x->>'expected_line_version')::bigint expected_line_version,
    x->>'line_key' line_key,upper(x->>'stage_code') stage_code,lower(x->>'work_key') work_key,
    CASE WHEN jsonb_typeof(x->'estimated_hours')='null' THEN NULL ELSE (x->>'estimated_hours')::numeric END estimated_hours
  FROM jsonb_array_elements(v_rows) x;
  CREATE INDEX ON pdc_hours_batch_request_768(operation_line_id);

  IF EXISTS(SELECT 1 FROM pdc_hours_batch_request_768 WHERE work_key='parts') THEN
    RETURN jsonb_build_object('ok',false,'code','parts_not_hour_bearing','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'booking_created',false,'parts_mutated',false));
  END IF;

  -- Lock every existing overlay before comparing versions. Source operation evidence is immutable.
  PERFORM 1 FROM public.vehicle_workshop_line_adjustments a
   JOIN pdc_hours_batch_request_768 r ON r.adjustment_id=a.adjustment_id
   WHERE a.vehicle_id=p_vehicle_id FOR UPDATE;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'line_key',r.line_key,'work_key',r.work_key,'stage_code',r.stage_code,
    'adjustment_id',a.adjustment_id,'line_version',coalesce(a.version,0),
    'estimated_hours',CASE WHEN coalesce(a.active,true) THEN coalesce(a.estimated_hours,ol.estimated_hours) ELSE NULL END,
    'source_job_card_number',coalesce(nullif(btrim(ol.job_card_number),''),btrim(v_vehicle.job_card_number)),
    'active',coalesce(a.active,true)
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_current_rows
  FROM pdc_hours_batch_request_768 r
  LEFT JOIN public.pdc_authenticated_email_operation_lines ol
    ON ol.operation_line_id=r.operation_line_id AND ol.vehicle_id=p_vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a
    ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key;

  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'current_rows',v_current_rows));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'requested_work_key',r.work_key,'requested_stage_code',r.stage_code,
    'requested_line_version',r.expected_line_version,'current_work_key',ol.work_key,
    'current_stage_code',coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)),
    'current_adjustment_id',a.adjustment_id,'current_line_version',coalesce(a.version,0),
    'current_estimated_hours',CASE WHEN coalesce(a.active,true) THEN coalesce(a.estimated_hours,ol.estimated_hours) ELSE NULL END,
    'reason',CASE
      WHEN ol.operation_line_id IS NULL THEN 'operation_line_not_found'
      WHEN coalesce(a.active,true)=false THEN 'operation_line_adjustment_inactive'
      WHEN coalesce(nullif(btrim(ol.job_card_number),''),btrim(v_vehicle.job_card_number))<>btrim(p_job_card_number) THEN 'job_card_identity_conflict'
      WHEN lower(ol.work_key)<>r.work_key THEN 'work_key_conflict'
      WHEN coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))<>r.stage_code THEN 'stage_identity_conflict'
      WHEN a.adjustment_id IS DISTINCT FROM r.adjustment_id THEN 'adjustment_identity_conflict'
      WHEN coalesce(a.version,0)<>r.expected_line_version THEN 'line_version_conflict'
      WHEN r.estimated_hours IS NULL AND ol.estimated_hours IS NOT NULL THEN 'unknown_hours_override_unsupported'
      ELSE 'row_drift'
    END
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_conflicts
  FROM pdc_hours_batch_request_768 r
  LEFT JOIN public.pdc_authenticated_email_operation_lines ol
    ON ol.operation_line_id=r.operation_line_id AND ol.vehicle_id=p_vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a
    ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE ol.operation_line_id IS NULL
     OR coalesce(a.active,true)=false
     OR coalesce(nullif(btrim(ol.job_card_number),''),btrim(v_vehicle.job_card_number))<>btrim(p_job_card_number)
     OR lower(ol.work_key)<>r.work_key
     OR coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))<>r.stage_code
     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id
     OR coalesce(a.version,0)<>r.expected_line_version
     OR (r.estimated_hours IS NULL AND ol.estimated_hours IS NOT NULL);
  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN jsonb_build_object('ok',false,'code','line_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'conflicts',v_conflicts,'current_rows',v_current_rows));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_changes_768 ON COMMIT DROP AS
  SELECT r.operation_line_id,r.adjustment_id current_adjustment_id,r.expected_line_version,
    r.line_key,r.stage_code,r.work_key,r.estimated_hours,
    ol.description source_description,ol.estimated_hours source_estimated_hours,
    coalesce(a.estimated_hours,ol.estimated_hours) current_estimated_hours,
    coalesce(a.version,0) current_line_version
  FROM pdc_hours_batch_request_768 r
  JOIN public.pdc_authenticated_email_operation_lines ol ON ol.operation_line_id=r.operation_line_id AND ol.vehicle_id=p_vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE r.estimated_hours IS DISTINCT FROM coalesce(a.estimated_hours,ol.estimated_hours);
  SELECT count(*) INTO v_changed_count FROM pdc_hours_batch_changes_768;

  IF v_changed_count>0 THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,
      created_by,updated_by,source_operation_line_id,job_card_number
    )
    SELECT p_vehicle_id,c.line_key,'source',c.stage_code,c.source_description,c.estimated_hours,true,1,v_actor,v_actor,
      c.operation_line_id,p_job_card_number
    FROM pdc_hours_batch_changes_768 c WHERE c.current_adjustment_id IS NULL
    ON CONFLICT(vehicle_id,line_key) DO UPDATE SET
      stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,
      active=true,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();

    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',c.operation_line_id,'line_key',c.line_key,'work_key',c.work_key,
      'before',jsonb_build_object('adjustment_id',c.current_adjustment_id,'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      'after',jsonb_build_object('adjustment_id',a.adjustment_id,'estimated_hours',a.estimated_hours,'version',a.version)
    ) ORDER BY c.operation_line_id),'[]'::jsonb) INTO v_changes
    FROM pdc_hours_batch_changes_768 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    SELECT CASE WHEN c.current_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
      'vehicle_workshop_line_adjustments',a.adjustment_id,p_vehicle_id,v_actor,v_email,
      jsonb_build_object('adjustment_id',c.current_adjustment_id,'operation_line_id',c.operation_line_id,'work_key',c.work_key,
        'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      jsonb_build_object('adjustment_id',a.adjustment_id,'operation_line_id',c.operation_line_id,'work_key',c.work_key,
        'estimated_hours',a.estimated_hours,'version',a.version),
      jsonb_build_object('source','vehicle_workshop_hours_batch_768','request_id',p_idempotency_key,
        'request_hash',v_request_hash,'bookings_changed',false,'parts_changed',false,'completion_changed',false)
    FROM pdc_hours_batch_changes_768 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    -- One authoritative vehicle-version increment for the whole batch.
    UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  ELSE
    v_vehicle_after:=v_vehicle;
  END IF;

  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  v_receipt.response:=jsonb_build_object('ok',true,'code',CASE WHEN v_changed_count>0 THEN 'workshop_hours_batch_saved' ELSE 'workshop_hours_batch_no_changes' END,
    'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_hash,'vehicle_id',p_vehicle_id,
    'vehicle_version_before',v_vehicle.version,'vehicle_version_after',v_vehicle_after.version,
    'revision',v_revision,'changed_count',v_changed_count,'changes',v_changes,
    'booking_created',false,'parts_mutated',false,'completion_changed',false);
  INSERT INTO public.vehicle_workshop_hours_batch_receipts_768(
    receipt_id,idempotency_key,actor_id,vehicle_id,request_hash,base_vehicle_version,response)
  VALUES(v_receipt_id,p_idempotency_key,v_actor,p_vehicle_id,v_request_hash,v_vehicle.version,v_receipt.response)
  RETURNING * INTO v_receipt;
  RETURN v_receipt.response;
END $save$;

REVOKE ALL ON FUNCTION public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid) TO authenticated;
COMMENT ON FUNCTION public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid) IS
'Staging-only authenticated atomic Job Card hour batch: exact vehicle Stock/JC identity, immutable operation UUID/work key identity, base vehicle and line versions, idempotent request hash, all-or-none audit and one vehicle-version increment; Parts excluded and bookings untouched.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830070000','768_vehicle_workshop_hours_batch',ARRAY[
 'Replace per-row hour saves with one authenticated atomic Save all hours operation',
 'Validate exact vehicle UUID Stock Job Card operation UUID work key stage and base/line versions before any DML',
 'Preserve explicit zero and unknown source hours without coercion; reject invalid negative non-finite excess and Parts values',
 'Increment the canonical vehicle version once and return immutable before/after changes with idempotent request hash',
 'Keep Parts completion/risk semantics and all Workshop bookings outside the hour batch mutation'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
