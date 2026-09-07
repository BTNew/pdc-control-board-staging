-- STAGING ONLY: permit the existing controlled Navision activation path for its scoped runtime viewer.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-service-scoped-activation-gate',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260907101000,pilbara_service_runtime_actor_gate)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907102000')
  THEN RAISE EXCEPTION 'PDC_20260907102000_STAGING_PREDECESSOR_OR_SCOPE_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.activate_navision_backend_record(p_idempotency_key text, p_backend_record_id uuid, p_expected_revision bigint, p_activation_source text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_role text := public.current_pdc_user_role()::text;
  v_source text := lower(btrim(coalesce(p_activation_source, '')));
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_stock_number text;
  v_revision bigint;
  v_result_revision bigint;
  v_response jsonb;
begin
  if not (
    coalesce(v_role = any(array['operator','importer','administrator']), false)
    or (v_role='viewer'
      and exists(select 1 from public.pdc_email_ai_successor_runtime_identities i
        where i.auth_user_id=auth.uid() and i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
          and i.environment='staging' and i.identity_purpose='pdc_email_ai_transaction_successor'
          and i.active and i.revoked_at is null)
      and exists(select 1 from public.pdc_monitor_stage_activation_writers w
        where w.user_id=auth.uid() and w.active and w.revoked_at is null))
  ) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if p_backend_record_id is null then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'backend_record_id'));
  end if;
  if v_key = '' or length(v_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'expected_revision'));
  end if;
  if v_source not in ('manual', 'approved_email_build', 'approved_pd_document') then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'activation_source'));
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1,
    'idempotency_key', v_key,
    'backend_record_id', p_backend_record_id,
    'expected_revision', p_expected_revision,
    'activation_source', v_source
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-board-activate:' || v_key, 0));
  select * into v_existing
  from public.navision_operation_receipts
  where operation_kind = 'board_activate' and idempotency_key = v_key;
  if found then
    if v_existing.request_hash <> v_request_hash then
      return public.navision_backend_response(false, 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store', 0));
  select revision into v_revision
  from public.navision_backend_revision
  where singleton
  for update;
  if v_revision <> p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;

  select * into v_record
  from public.navision_backend_records
  where id = p_backend_record_id
  for update;
  if not found then
    return public.navision_backend_response(false, 'not_found');
  end if;
  if not v_record.is_current or v_record.record_status <> 'current' then
    return public.navision_backend_response(false, 'record_not_current');
  end if;

  v_stock_number := nullif(btrim(coalesce(v_record.normalized_data ->> 'batch', '')), '');
  if v_stock_number is null then
    return public.navision_backend_response(false, 'stock_required');
  end if;

  if exists (
    select 1 from public.navision_board_activations
    where backend_record_id = p_backend_record_id
      and activated_stock_number = v_stock_number
  ) then
    v_response := public.navision_backend_response(true, 'already_activated', jsonb_build_object(
      'backend_record_id', p_backend_record_id,
      'result_revision', v_revision,
      'activated', true
    ));
  else
    insert into public.navision_board_activations (
      backend_record_id, activation_source, activated_stock_number, activated_by, activated_by_email
    ) values (
      p_backend_record_id, v_source, v_stock_number, auth.uid(), public.current_actor_email()
    )
    on conflict (backend_record_id) do update
      set activation_source = excluded.activation_source,
          activated_stock_number = excluded.activated_stock_number,
          activated_at = now(),
          activated_by = excluded.activated_by,
          activated_by_email = excluded.activated_by_email,
          updated_at = now();
    v_result_revision := v_revision + 1;
    update public.navision_backend_revision
    set revision = v_result_revision, updated_at = now()
    where singleton;
    insert into public.navision_backend_audit (
      action, backend_record_id, revision, evidence, actor_id, actor_email
    ) values (
      'board_activate', p_backend_record_id, v_result_revision,
      jsonb_build_object('activation_source', v_source, 'stock_number', v_stock_number),
      auth.uid(), public.current_actor_email()
    );
    v_response := public.navision_backend_response(true, 'board_activated', jsonb_build_object(
      'backend_record_id', p_backend_record_id,
      'result_revision', v_result_revision,
      'activated', true,
      'activation_source', v_source,
      'stock_number', v_stock_number
    ));
  end if;

  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, response, actor_id, actor_email
  ) values (
    'board_activate', v_key, v_request_hash, v_response, auth.uid(), public.current_actor_email()
  );
  return v_response;
end;
$function$;

REVOKE ALL ON FUNCTION public.activate_navision_backend_record(text,uuid,bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.activate_navision_backend_record(text,uuid,bigint,text) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907102000','pilbara_service_scoped_activation_gate',ARRAY[
  'permit controlled Navision activation for the scoped runtime viewer only when both runtime identity and activation-writer grants are active',
  'preserve operator importer administrator activation behavior and keep anon service-role execution revoked'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
