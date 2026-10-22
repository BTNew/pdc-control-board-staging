-- r479 local harness schema (synthetic; no staging data). Stand-ins for the staging objects r479 reads or guards.
CREATE SCHEMA pdc_ops; CREATE SCHEMA pdc_codex_intake_private; CREATE SCHEMA pdc_parts_private;
CREATE TABLE pdc_ops.expected_function_md5(signature text primary key, prosrc_md5 text, release text, note text, updated_at timestamptz);
CREATE TABLE pdc_ops.regression_checks(check_name text, fault_id text, description text, check_sql text, enabled boolean, sort_order int, added_in text);
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean, project_ref text); INSERT INTO public.pdc_staging_environment_sentinel VALUES(true,'cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public.workshop_clock_tick(boolean,timestamptz) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION pdc_ops.fault_regression_check() RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION public.pdc_pilbara_service_preview_v1(jsonb,text,text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
-- apply stand-in: only the r442 check's text markers (feed before the single apply receipt)
CREATE FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN
 -- service_sublet_po_feed_442(v_preview.batch_id,false)
 -- VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response
 RETURN '{}'::jsonb; END $$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) FROM PUBLIC;
CREATE FUNCTION pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"code":"preview_batch_not_found"}'::jsonb /* import_sublet_pos_439 */ $$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean) FROM PUBLIC;
-- authentication stand-in (the real one is not guarded or changed by r479)
CREATE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb, p_message_id text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_auth->>'gmail_message_id'=p_message_id AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au' AND p_auth->>'authentication_results' ~ 'dmarc=pass',false) $$;
CREATE FUNCTION pdc_codex_intake_private.revolution_service_headers_439(p_headers jsonb, p_base jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE n integer; v_extra text[]; 
BEGIN
 -- r439 (F50): a Revolution service header list is the exact base list, in order, optionally followed by any of the
 -- seven sublet columns (each at most once, any order). Nothing else is accepted: no missing, renamed, reordered or
 -- unknown column. The per-line Company / Division sublet columns are evidence only; the report-level Company 01 /
 -- Division 1 checks are unchanged.
 IF jsonb_typeof(p_headers) IS DISTINCT FROM 'array' OR jsonb_typeof(p_base) IS DISTINCT FROM 'array' THEN RETURN false; END IF;
 n:=jsonb_array_length(p_base);
 IF n=0 OR jsonb_array_length(p_headers)<n OR jsonb_array_length(p_headers)>n+7 THEN RETURN false; END IF;
 IF (SELECT jsonb_agg(e ORDER BY o) FROM jsonb_array_elements(p_headers) WITH ORDINALITY x(e,o) WHERE o<=n) IS DISTINCT FROM p_base THEN RETURN false; END IF;
 SELECT coalesce(array_agg(CASE WHEN jsonb_typeof(e)='string' THEN e#>>'{}' END),'{}') INTO v_extra FROM jsonb_array_elements(p_headers) WITH ORDINALITY x(e,o) WHERE o>n;
 RETURN NOT EXISTS(SELECT 1 FROM unnest(v_extra) h WHERE h IS NULL
   OR h <> ALL(ARRAY['Company','Description of sublet','Division','Document Line','Job #','PO #','Sublet Line']))
  AND cardinality(v_extra)=(SELECT count(DISTINCT h) FROM unnest(v_extra) h);
END
$function$;
CREATE FUNCTION public.pdc_tune_text_field_v5(p_row jsonb, p_keys text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT nullif(btrim(e.value),'') FROM unnest(p_keys) WITH ORDINALITY k(key,rank)
 CROSS JOIN LATERAL jsonb_each_text(coalesce(p_row,'{}')||'{}'::jsonb) e
 WHERE regexp_replace(lower(e.key),'[^a-z0-9]','','g')=regexp_replace(lower(k.key),'[^a-z0-9]','','g') AND nullif(btrim(e.value),'') IS NOT NULL
 ORDER BY k.rank,e.key LIMIT 1
$function$;
CREATE FUNCTION public.pdc_tune_key_number_v1(p_row jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare value text;
begin
 value:=public.pdc_tune_text_field_v5(coalesce(p_row->'raw_row','{}')||p_row,
  array['Key Tag Number','key_tag_number','key_number','key number','key tag','key no']);
 if value is null or lower(value) in ('','0','none','null','n/a','na','unknown','not recorded','-') then return null; end if;
 if value ~ '^0+([.]0+)?$' then return null; end if;
 if value ~ '^[0-9]+[.]0+$' then value:=split_part(value,'.',1); end if;
 if value !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$' then return null; end if;
 return upper(value);
end $function$;
CREATE TABLE public.vehicles(id uuid primary key, stock_number text, job_card_number text, lifecycle_state text, deleted_at timestamptz, visible_on_board boolean default true,
 key_number text, source_payload jsonb, version int default 1, updated_by uuid, updated_at timestamptz,
 current_location text, board_purged_at timestamptz, qc_completed_at timestamptz, rft_transferred_at timestamptz, pmb_stage text, pmb_bay_stage text, pmb_bay_number int,
 location_override text, location_override_reason text, location_override_at timestamptz, location_override_by uuid, workshop_status text);
CREATE TABLE pdc_parts_private.jobs(id uuid primary key default gen_random_uuid(), vehicle_id uuid, company text default '01', division text default '1', ro_number text, closed_at timestamptz,
 source_system text default 'tune_pmg', stock_number text);
-- r479 99-once stand-ins: the tables capture_service_status (real staging body, loaded from the rollback) reads and writes
CREATE TABLE pdc_codex_intake_private.service_job_status(company text, division text, ro_number text, vehicle_id uuid, stock_number text, status text, sub_status text,
 snapshot_at timestamptz, batch_id uuid, imported_at timestamptz default clock_timestamp(), PRIMARY KEY(company,division,ro_number));
CREATE TABLE pdc_codex_intake_private.service_status_reviews(batch_id uuid, company text, division text, ro_number text, stock_number text, reason text, evidence jsonb,
 UNIQUE(batch_id,company,division,ro_number,reason));
CREATE TABLE pdc_codex_intake_private.tune_checkout_receipts(receipt_id uuid primary key default gen_random_uuid(), vehicle_id uuid, batch_id uuid, snapshot_at timestamptz,
 source_hash text, job_cards jsonb, prior_location text, recorded_at timestamptz default clock_timestamp(), transaction_id bigint default txid_current(), actor_id uuid, UNIQUE(vehicle_id,batch_id));
CREATE TABLE pdc_codex_intake_private.tune_pmb_complete_receipts(receipt_id uuid primary key default gen_random_uuid(), vehicle_id uuid);
CREATE FUNCTION pdc_codex_intake_private.finish_tune_checkout(uuid) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION pdc_codex_intake_private.apply_service_pmb_complete(uuid) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE TABLE public.pdc_new_vehicle_reviews(vehicle_id uuid, status text, closed_at timestamptz, closure_reason text);
CREATE TABLE public.vehicle_movements(vehicle_id uuid, from_location text, to_location text, from_pmb_stage text, to_pmb_stage text, from_pmb_bay_stage text, to_pmb_bay_stage text,
 from_pmb_bay_number int, to_pmb_bay_number int, reason text, moved_by uuid, moved_at timestamptz);
CREATE TABLE public.pdc_qc_vehicle_rejection_receipts_767(vehicle_id uuid);
CREATE TABLE public.pdc_qc_operation_rejections_381(vehicle_id uuid, active boolean);
CREATE TABLE public.pdc_pilbara_service_operations(vehicle_id uuid, repair_order_number text, original_line_number int, department text, operation_description text, source_estimated_hours numeric);
CREATE TABLE public.audit_events(id uuid primary key default gen_random_uuid(), action text, table_name text, vehicle_id uuid, metadata jsonb, created_at timestamptz default clock_timestamp());
CREATE TABLE public.pdc_pilbara_service_import_batches(batch_id uuid primary key, batch_kind text, contract_revision text, source_hash text, created_by uuid);
CREATE TABLE public.pdc_pilbara_service_import_rows(evidence_id uuid primary key default gen_random_uuid(), batch_id uuid, stock_number text, repair_order_number text,
 original_line_number int, decision text, reason text, vehicle_id uuid, raw_row jsonb, normalized_payload jsonb default '{}', created_at timestamptz default now());
CREATE TABLE public.pdc_pilbara_service_import_receipts(batch_id uuid, receipt_kind text, outcome jsonb, created_at timestamptz default now());
CREATE TABLE public.h_audit(entity uuid, before jsonb, after jsonb, meta jsonb);
CREATE FUNCTION public.audit_pdc_event(text,text,uuid,uuid,jsonb,jsonb,jsonb) RETURNS void LANGUAGE sql AS $$ INSERT INTO public.h_audit VALUES($3,$5,$6,$7) $$;
