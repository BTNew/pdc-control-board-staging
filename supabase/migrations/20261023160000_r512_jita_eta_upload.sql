-- r512 (F128): daily JITA parts ETA paste. PREVIEW ONLY. Do not apply to staging until Craig says so.
-- Staging cdsmnqxtyyoeoznmbidd only. Adds a paste under Navision Uploads. It does not call set_parts_eta and does not write pdc_parts_eta.
-- One board date per JITA Vehicle (stock number):
--   latest Planned Delivery Date among rows with Qty Outstanding > 0 (header is "Qty Oustanding" in the Revolution export; "Qty Outstanding" is also accepted);
--   if none of those rows have a date, the latest Planned Delivery Date on any row for that stock.
-- Latest means the greatest calendar date. Previous ETA, Latest ETA, Manual ETA and Vehicle ETA at Kewdale are not read.
-- A stock is saved only when exactly one live vehicle has it (not deleted, not purged). Unknown and ambiguous stocks are skipped.
-- Stocks left out of the paste are left as they are.
-- Undo: supabase/rollbacks/20261023160000_r512_jita_eta_upload.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r512: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r512: staging only'; END IF;
 PERFORM set_config('pdc.r512_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r512_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r512_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r512_parts',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')),true);
 PERFORM set_config('pdc.r512_board',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')),true);
 IF current_setting('pdc.r512_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r512: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r512_parts') IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r512: set_parts_eta is not the r436 body'; END IF;
 IF current_setting('pdc.r512_board') IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r512: get_pdc_parts_eta_board is not the r436 body'; END IF;
 IF to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)') IS NOT NULL
    AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)')) IS DISTINCT FROM 'a81b786bfc7868c3217d827933299678'
  THEN RAISE EXCEPTION 'r512: set_parts_eta_from_email is not the r475 body'; END IF;
 IF to_regprocedure('public.jita_eta_parse_512(text)') IS NOT NULL
    OR to_regprocedure('public.import_jita_eta_512(text,boolean)') IS NOT NULL
    OR to_regprocedure('public.get_pdc_jita_eta_board()') IS NOT NULL
    OR to_regclass('public.pdc_jita_eta') IS NOT NULL
    OR to_regclass('public.pdc_jita_eta_audit') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r512')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_512' OR added_in='r512' OR fault_id='F128')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=300) THEN RAISE EXCEPTION 'r512: already applied or sort 300 / F128 taken'; END IF;
END $g$;

CREATE TABLE public.pdc_jita_eta(
  id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  stock_number text NOT NULL,
  eta_date date NOT NULL,
  rule text NOT NULL CHECK (rule IN ('latest_outstanding','latest_any')),
  source_rows integer NOT NULL CHECK (source_rows>=0),
  outstanding_rows integer NOT NULL CHECK (outstanding_rows>=0),
  source_md5 text NOT NULL CHECK (source_md5 ~ '^[0-9a-f]{32}$'),
  set_at timestamptz NOT NULL,
  set_by uuid,
  set_by_actor text NOT NULL,
  superseded boolean NOT NULL DEFAULT false,
  superseded_at timestamptz,
  superseded_by uuid,
  CHECK (superseded=(superseded_at IS NOT NULL)));
CREATE UNIQUE INDEX pdc_jita_eta_one_current ON public.pdc_jita_eta(vehicle_id) WHERE NOT superseded;

CREATE TABLE public.pdc_jita_eta_audit(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id uuid,
  actor text,
  actor_role text,
  dry_run boolean NOT NULL,
  status text NOT NULL,
  source_md5 text,
  result jsonb NOT NULL);

ALTER TABLE public.pdc_jita_eta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jita_eta_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_jita_eta, public.pdc_jita_eta_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pdc_jita_eta, public.pdc_jita_eta_audit TO authenticated;
CREATE POLICY pdc_jita_eta_board_read ON public.pdc_jita_eta FOR SELECT TO authenticated
  USING (public.is_pdc_role('viewer'::public.pdc_role));
CREATE POLICY pdc_jita_eta_audit_admin_read ON public.pdc_jita_eta_audit FOR SELECT TO authenticated
  USING (public.is_pdc_role('administrator'::public.pdc_role));

CREATE FUNCTION public.jita_eta_parse_512(p_text text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $parse$
DECLARE
  -- r512 (F128): read a Revolution JITA paste. Only three columns drive the date.
  v_raw text := replace(replace(coalesce(p_text,''), E'\r\n', E'\n'), E'\r', E'\n');
  v_lines text[];
  v_cols text[];
  v_line text;
  v_name text;
  v_i int;
  v_start int := 0;
  v_veh int := 0;
  v_eta int := 0;
  v_qty int := 0;
  v_data int := 0;
  v_blank int := 0;
  v_bad int := 0;
  v_stock text;
  v_key text;
  v_raw_date text;
  v_qty_text text;
  v_d int;
  v_m int;
  v_y int;
  v_iso text;
  v_outstanding boolean;
  v_acc jsonb := '{}'::jsonb;
  v_item jsonb;
  v_stocks jsonb;
BEGIN
  IF left(v_raw,1)=chr(65279) THEN v_raw := substr(v_raw,2); END IF;
  IF length(v_raw)>1500000 THEN
    RETURN jsonb_build_object('ok',false,'error','too_big','message','Paste is too big.');
  END IF;
  IF btrim(v_raw)='' THEN
    RETURN jsonb_build_object('ok',false,'error','empty','message','Paste the Revolution JITA export, including the header row.');
  END IF;
  v_lines := regexp_split_to_array(v_raw, E'\n');
  FOR v_i IN 1..coalesce(array_length(v_lines,1),0) LOOP
    IF btrim(v_lines[v_i])<>'' THEN v_start := v_i; EXIT; END IF;
  END LOOP;
  IF v_start=0 THEN
    RETURN jsonb_build_object('ok',false,'error','empty','message','Paste the Revolution JITA export, including the header row.');
  END IF;
  v_cols := string_to_array(v_lines[v_start], E'\t');
  FOR v_i IN 1..coalesce(array_length(v_cols,1),0) LOOP
    v_name := lower(btrim(v_cols[v_i]));
    IF v_name='jita vehicle' AND v_veh=0 THEN v_veh := v_i;
    ELSIF v_name='jita planned delivery date' AND v_eta=0 THEN v_eta := v_i;
    ELSIF v_name IN ('qty oustanding','qty outstanding') AND v_qty=0 THEN v_qty := v_i;
    END IF;
  END LOOP;
  IF v_veh=0 OR v_eta=0 OR v_qty=0 THEN
    RETURN jsonb_build_object('ok',false,'error','header','message','Header must include JITA Vehicle, JITA Planned Delivery Date, and Qty Outstanding.');
  END IF;
  FOR v_i IN v_start+1..coalesce(array_length(v_lines,1),0) LOOP
    v_line := v_lines[v_i];
    IF btrim(v_line)='' THEN CONTINUE; END IF;
    IF v_data>=8000 THEN
      RETURN jsonb_build_object('ok',false,'error','too_big','message','Paste has too many rows.');
    END IF;
    v_cols := string_to_array(v_line, E'\t');
    v_stock := btrim(coalesce(v_cols[v_veh],''));
    IF v_stock='' OR length(v_stock)>40 OR v_stock ~ '[[:cntrl:]]' THEN
      v_blank := v_blank+1; CONTINUE;
    END IF;
    v_data := v_data+1;
    v_raw_date := btrim(coalesce(v_cols[v_eta],''));
    v_iso := NULL;
    IF v_raw_date<>'' THEN
      IF v_raw_date ~ '^\d{1,2}/\d{1,2}/\d{2}$' OR v_raw_date ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
        v_d := split_part(v_raw_date,'/',1)::int;
        v_m := split_part(v_raw_date,'/',2)::int;
        v_y := split_part(v_raw_date,'/',3)::int;
        IF v_y<100 THEN v_y := CASE WHEN v_y<=69 THEN 2000+v_y ELSE 1900+v_y END; END IF;
        IF v_y BETWEEN 2000 AND 2099 AND v_m BETWEEN 1 AND 12 AND v_d BETWEEN 1 AND 31 THEN
          BEGIN
            v_iso := to_char(make_date(v_y,v_m,v_d),'YYYY-MM-DD');
          EXCEPTION WHEN datetime_field_overflow THEN
            v_iso := NULL;
          END;
        END IF;
      END IF;
      IF v_iso IS NULL THEN v_bad := v_bad+1; END IF;
    END IF;
    v_qty_text := replace(btrim(coalesce(v_cols[v_qty],'')),',','');
    v_outstanding := length(v_qty_text)<=12 AND v_qty_text ~ '^[0-9]+(\.[0-9]+)?$' AND v_qty_text::numeric>0;
    v_key := upper(v_stock);
    v_item := coalesce(v_acc->v_key, jsonb_build_object(
      'stock',v_stock,'rows',0,'outstanding_rows',0,
      'latest_outstanding',NULL,'latest_any',NULL,'outstanding_dates','[]'::jsonb));
    v_item := jsonb_set(v_item,'{rows}',to_jsonb(coalesce((v_item->>'rows')::int,0)+1));
    IF v_iso IS NOT NULL AND (v_item->>'latest_any' IS NULL OR v_iso>(v_item->>'latest_any')) THEN
      v_item := jsonb_set(v_item,'{latest_any}',to_jsonb(v_iso));
    END IF;
    IF v_outstanding THEN
      v_item := jsonb_set(v_item,'{outstanding_rows}',to_jsonb(coalesce((v_item->>'outstanding_rows')::int,0)+1));
      IF v_iso IS NOT NULL THEN
        IF v_item->>'latest_outstanding' IS NULL OR v_iso>(v_item->>'latest_outstanding') THEN
          v_item := jsonb_set(v_item,'{latest_outstanding}',to_jsonb(v_iso));
        END IF;
        IF NOT coalesce(v_item->'outstanding_dates' ? v_iso, false) THEN
          v_item := jsonb_set(v_item,'{outstanding_dates}',coalesce(v_item->'outstanding_dates','[]'::jsonb)||to_jsonb(v_iso));
        END IF;
      END IF;
    END IF;
    v_acc := jsonb_set(v_acc, ARRAY[v_key], v_item);
  END LOOP;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'stock', e.value->>'stock',
    'eta_date', CASE WHEN e.value->>'latest_outstanding' IS NOT NULL THEN e.value->>'latest_outstanding' ELSE e.value->>'latest_any' END,
    'rule', CASE WHEN e.value->>'latest_outstanding' IS NOT NULL THEN 'latest_outstanding' WHEN e.value->>'latest_any' IS NOT NULL THEN 'latest_any' ELSE NULL END,
    'source_rows', (e.value->>'rows')::int,
    'outstanding_rows', (e.value->>'outstanding_rows')::int,
    'distinct_outstanding_dates', coalesce(jsonb_array_length(e.value->'outstanding_dates'),0)
  ) ORDER BY e.value->>'stock'), '[]'::jsonb) INTO v_stocks
  FROM jsonb_each(v_acc) e;
  RETURN jsonb_build_object('ok',true,'rows',v_data,'blank_vehicle_rows',v_blank,'bad_date_rows',v_bad,'stocks',v_stocks);
END
$parse$;
REVOKE ALL ON FUNCTION public.jita_eta_parse_512(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.jita_eta_parse_512(text) TO authenticated;

CREATE FUNCTION public.import_jita_eta_512(p_text text, p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $imp$
DECLARE
  -- r512 (F128): importer or administrator paste. Never creates vehicles. Never writes the email parts ETA.
  v_uid uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_actor text := coalesce(auth.jwt()->>'email', v_uid::text);
  v_dry boolean := coalesce(p_dry_run, true);
  v_parsed jsonb;
  v_stock jsonb;
  v_n int;
  v_vehicle_id uuid;
  v_board_stock text;
  v_eta date;
  v_cur public.pdc_jita_eta%ROWTYPE;
  v_id uuid;
  v_status text;
  v_results jsonb := '[]'::jsonb;
  v_row jsonb;
  v_msg text;
  v_shown int := 0;
  v_unknown int := 0;
  v_amb int := 0;
  v_md5 text := md5(coalesce(p_text,''));
  v_audit text;
BEGIN
  IF NOT coalesce(public.is_pdc_role('importer'::public.pdc_role), false) THEN
    RAISE EXCEPTION 'PDC_JITA_ETA_FORBIDDEN: importer or administrator access is required' USING ERRCODE='42501';
  END IF;
  v_parsed := public.jita_eta_parse_512(p_text);
  IF coalesce((v_parsed->>'ok')::boolean, false) IS NOT TRUE THEN
    IF NOT v_dry THEN
      INSERT INTO public.pdc_jita_eta_audit(actor_id,actor,actor_role,dry_run,status,source_md5,result)
      VALUES (v_uid, v_actor, v_role, false, 'refused', v_md5, v_parsed||jsonb_build_object('dry_run',false));
    END IF;
    RETURN v_parsed||jsonb_build_object('dry_run', v_dry);
  END IF;
  IF coalesce(jsonb_array_length(v_parsed->'stocks'),0)=0 THEN
    v_row := jsonb_build_object('ok',true,'dry_run',v_dry,'rows',0,'blank_vehicle_rows',coalesce((v_parsed->>'blank_vehicle_rows')::int,0),
      'bad_date_rows',coalesce((v_parsed->>'bad_date_rows')::int,0),'results','[]'::jsonb,
      'message', CASE WHEN v_dry THEN 'Preview only. Nothing saved. No vehicle rows.' ELSE 'Nothing to save. No vehicle rows.' END);
    IF NOT v_dry THEN
      INSERT INTO public.pdc_jita_eta_audit(actor_id,actor,actor_role,dry_run,status,source_md5,result)
      VALUES (v_uid, v_actor, v_role, false, 'empty', v_md5, v_row);
    END IF;
    RETURN v_row;
  END IF;
  FOR v_stock IN SELECT value FROM jsonb_array_elements(v_parsed->'stocks') LOOP
    IF v_stock->>'eta_date' IS NULL OR v_stock->>'rule' IS NULL THEN
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'stock', v_stock->>'stock', 'status', 'no_planned_date',
        'source_rows', v_stock->'source_rows', 'outstanding_rows', v_stock->'outstanding_rows'));
      CONTINUE;
    END IF;
    v_eta := (v_stock->>'eta_date')::date;
    SELECT count(*) INTO v_n FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL
      AND upper(btrim(v.stock_number))=upper(btrim(v_stock->>'stock'));
    IF v_n=0 THEN
      v_unknown := v_unknown+1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('stock', v_stock->>'stock', 'status', 'skipped_unknown', 'eta_date', v_eta));
      CONTINUE;
    ELSIF v_n>1 THEN
      v_amb := v_amb+1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('stock', v_stock->>'stock', 'status', 'ambiguous', 'eta_date', v_eta));
      CONTINUE;
    END IF;
    SELECT v.id, v.stock_number INTO v_vehicle_id, v_board_stock FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL
      AND upper(btrim(v.stock_number))=upper(btrim(v_stock->>'stock'));
    IF NOT v_dry THEN
      PERFORM pg_advisory_xact_lock(hashtextextended('pdc_jita_eta:'||v_vehicle_id::text, 0));
      SELECT * INTO v_cur FROM public.pdc_jita_eta e WHERE e.vehicle_id=v_vehicle_id AND NOT e.superseded FOR UPDATE;
    ELSE
      SELECT * INTO v_cur FROM public.pdc_jita_eta e WHERE e.vehicle_id=v_vehicle_id AND NOT e.superseded;
    END IF;
    IF FOUND AND v_cur.eta_date=v_eta THEN
      v_status := 'unchanged';
    ELSIF FOUND THEN
      v_status := CASE WHEN v_dry THEN 'would_replace' ELSE 'replaced' END;
    ELSE
      v_status := CASE WHEN v_dry THEN 'would_apply' ELSE 'applied' END;
    END IF;
    IF NOT v_dry AND v_status IN ('applied','replaced') THEN
      v_id := gen_random_uuid();
      IF v_status='replaced' THEN
        UPDATE public.pdc_jita_eta SET superseded=true, superseded_at=clock_timestamp(), superseded_by=v_id
        WHERE id=v_cur.id AND NOT superseded;
      END IF;
      INSERT INTO public.pdc_jita_eta(id,vehicle_id,stock_number,eta_date,rule,source_rows,outstanding_rows,source_md5,set_at,set_by,set_by_actor)
      VALUES (v_id, v_vehicle_id, v_board_stock, v_eta, v_stock->>'rule', coalesce((v_stock->>'source_rows')::int,0),
        coalesce((v_stock->>'outstanding_rows')::int,0), v_md5, clock_timestamp(), v_uid, v_actor);
    END IF;
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'stock', v_board_stock, 'vehicle_id', v_vehicle_id, 'eta_date', v_eta, 'previous_eta', CASE WHEN v_status IN ('replaced','would_replace') THEN v_cur.eta_date END,
      'rule', v_stock->>'rule', 'status', v_status,
      'source_rows', coalesce((v_stock->>'source_rows')::int,0),
      'outstanding_rows', coalesce((v_stock->>'outstanding_rows')::int,0),
      'distinct_outstanding_dates', coalesce((v_stock->>'distinct_outstanding_dates')::int,0)));
    IF v_shown<8 AND v_status IN ('would_apply','would_replace','applied','replaced','unchanged') THEN
      v_msg := coalesce(v_msg,'') || ' ' || v_board_stock || ' JITA ETA ' || to_char(v_eta,'DD/MM/YYYY') || '.';
      v_shown := v_shown+1;
    END IF;
  END LOOP;
  v_msg := CASE WHEN v_dry THEN 'Preview only. Nothing saved.' ELSE 'Saved.' END || coalesce(v_msg,'');
  IF v_unknown>0 THEN v_msg := v_msg || ' Skipped ' || v_unknown || ' not on the board.'; END IF;
  IF v_amb>0 THEN v_msg := v_msg || ' Skipped ' || v_amb || ' that match more than one vehicle.'; END IF;
  v_audit := CASE
    WHEN v_dry THEN 'preview'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_results) e WHERE e->>'status' IN ('applied','replaced')) THEN 'applied'
    WHEN v_unknown>0 OR v_amb>0 THEN 'skipped'
    ELSE 'unchanged' END;
  v_row := jsonb_build_object('ok',true,'dry_run',v_dry,'rows',coalesce((v_parsed->>'rows')::int,0),
    'blank_vehicle_rows',coalesce((v_parsed->>'blank_vehicle_rows')::int,0),
    'bad_date_rows',coalesce((v_parsed->>'bad_date_rows')::int,0),
    'results',v_results,'message',btrim(v_msg));
  IF NOT v_dry THEN
    INSERT INTO public.pdc_jita_eta_audit(actor_id,actor,actor_role,dry_run,status,source_md5,result)
    VALUES (v_uid, v_actor, v_role, false, v_audit, v_md5, v_row);
  END IF;
  RETURN v_row;
END
$imp$;
REVOKE ALL ON FUNCTION public.import_jita_eta_512(text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.import_jita_eta_512(text,boolean) TO authenticated;

CREATE FUNCTION public.get_pdc_jita_eta_board()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $board$
  -- r512 (F128): current JITA ETA per live vehicle. Board readers only. Not the email parts ETA.
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE
    jsonb_build_object('today', (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date, 'vehicles', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id', e.vehicle_id, 'stock_number', v.stock_number, 'eta_date', e.eta_date, 'rule', e.rule,
        'source_rows', e.source_rows, 'outstanding_rows', e.outstanding_rows, 'set_at', e.set_at
      ) ORDER BY v.stock_number)
      FROM public.pdc_jita_eta e
      JOIN public.vehicles v ON v.id=e.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
      WHERE NOT e.superseded
    ), '[]'::jsonb))
  END
$board$;
REVOKE ALL ON FUNCTION public.get_pdc_jita_eta_board() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_jita_eta_board() TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('public.jita_eta_parse_512(text)','492ab29757e9ba25674f67f76b206b1e','r512','r512 (F128): JITA paste parse and one date per stock',now()),
 ('public.import_jita_eta_512(text,boolean)','daaa7f839a33bf7719d282f749896aa7','r512','r512 (F128): JITA paste apply for importer or administrator',now()),
 ('public.get_pdc_jita_eta_board()','2d0930074c9f9372aed02901964bb4e9','r512','r512 (F128): board read of the JITA ETA',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('jita_eta_upload_512','F128','JITA paste (r512): parse and import and board read are security definer and closed to anon; the two tables have RLS and no app-role writes; one current ETA per vehicle; the paste picks the latest outstanding planned date, else the latest planned date; it does not read Previous ETA, Latest ETA, Manual ETA or Kewdale ETA; set_parts_eta stays the r436 body',
  $chk$WITH fn AS (
  SELECT count(*) n, count(*) FILTER (WHERE p.prosecdef) sd,
   bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE')) no_anon,
   bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')) auth_exec
  FROM pg_proc p WHERE p.oid IN (
   to_regprocedure('public.jita_eta_parse_512(text)'),
   to_regprocedure('public.import_jita_eta_512(text,boolean)'),
   to_regprocedure('public.get_pdc_jita_eta_board()'))
), tb AS (
  SELECT count(*) n, count(*) FILTER (WHERE c.relrowsecurity) rls,
   count(*) FILTER (WHERE has_table_privilege('authenticated',c.oid,'INSERT') OR has_table_privilege('authenticated',c.oid,'UPDATE')
     OR has_table_privilege('authenticated',c.oid,'DELETE') OR has_table_privilege('anon',c.oid,'SELECT')
     OR has_table_privilege('anon',c.oid,'INSERT')) writable,
   (SELECT count(*) FROM pg_policy po WHERE po.polrelid IN (to_regclass('public.pdc_jita_eta'),to_regclass('public.pdc_jita_eta_audit')) AND po.polcmd<>'r') write_policies
  FROM pg_class c WHERE c.oid IN (to_regclass('public.pdc_jita_eta'),to_regclass('public.pdc_jita_eta_audit'))
), src AS (
  SELECT (SELECT position('set_parts_eta' IN prosrc)+position('pdc_parts_eta' IN prosrc)+position('previous eta' IN lower(prosrc))
    FROM pg_proc WHERE oid=to_regprocedure('public.jita_eta_parse_512(text)')) parse_noise,
   (SELECT position('set_parts_eta' IN prosrc)+position('pdc_parts_eta' IN prosrc)
    FROM pg_proc WHERE oid=to_regprocedure('public.import_jita_eta_512(text,boolean)')) import_noise,
   (SELECT position('is_pdc_role(''importer''' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.import_jita_eta_512(text,boolean)')) importer_gate,
   (SELECT md5(prosrc)= '88d31cbd6ca5ddd372e3143d5f8c013f' FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) parts_same
), one AS (
  SELECT (SELECT count(*) FROM (SELECT 1 FROM public.pdc_jita_eta WHERE NOT superseded GROUP BY vehicle_id HAVING count(*)>1) z) dup_current
), hdr AS (
  SELECT chr(9) t, chr(10) n
), cases AS (
  SELECT public.jita_eta_parse_512('JITA Vehicle'||t||'Qty Oustanding'||t||'JITA Planned Delivery Date'||t||'Previous ETA'||n||'13102912'||t||'1'||t||'29/10/2026'||t||'01/01/2026'||n||'13102912'||t||'1'||t||'29/10/2026'||t||'16/10/26') same,
   public.jita_eta_parse_512('JITA Vehicle'||t||'Qty Outstanding'||t||'JITA Planned Delivery Date'||n||'13102912'||t||'1'||t||'29/10/2026'||n||'13102912'||t||'2'||t||'01/11/2026') multi,
   public.jita_eta_parse_512('JITA Vehicle'||t||'Qty Oustanding'||t||'JITA Planned Delivery Date'||t||'Latest ETA'||t||'Vehicle ETA at Kewdale'||n||'ABC'||t||'0'||t||'15/10/26'||t||'01/12/2026'||t||'20/12/2026'||n||'ABC'||t||'1'||t||''||t||'02/12/2026'||t||'03/12/2026') fallback,
   public.jita_eta_parse_512('Hello'||n||'13102912') bad
  FROM hdr
)
SELECT (SELECT n=3 AND sd=3 AND no_anon AND auth_exec FROM fn)
 AND (SELECT n=2 AND rls=2 AND writable=0 AND write_policies=0 FROM tb)
 AND (SELECT parse_noise=0 AND import_noise=0 AND importer_gate>0 AND parts_same FROM src)
 AND (SELECT dup_current=0 FROM one)
 AND (SELECT (same->>'ok')::boolean AND same->'stocks'->0->>'eta_date'='2026-10-29' AND same->'stocks'->0->>'rule'='latest_outstanding' AND (same->'stocks'->0->>'distinct_outstanding_dates')::int=1 FROM cases)
 AND (SELECT (multi->>'ok')::boolean AND multi->'stocks'->0->>'eta_date'='2026-11-01' AND multi->'stocks'->0->>'rule'='latest_outstanding' AND (multi->'stocks'->0->>'distinct_outstanding_dates')::int=2 FROM cases)
 AND (SELECT (fallback->>'ok')::boolean AND fallback->'stocks'->0->>'eta_date'='2026-10-15' AND fallback->'stocks'->0->>'rule'='latest_any' FROM cases)
 AND (SELECT (bad->>'ok')::boolean IS FALSE AND bad->>'error'='header' FROM cases) AS ok,
 'functions '||(SELECT sd FROM fn)||'/3 definer, anon blocked '||(SELECT no_anon FROM fn)
 ||'; tables RLS '||(SELECT rls FROM tb)||'/2, app writes '||(SELECT writable FROM tb)
 ||'; parts ETA still r436 '||coalesce((SELECT parts_same FROM src)::text,'missing')
 ||'; sample date '||coalesce((SELECT same->'stocks'->0->>'eta_date' FROM cases),'none') AS detail
$chk$,true,300,'r512');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.jita_eta_parse_512(text)')) IS DISTINCT FROM '492ab29757e9ba25674f67f76b206b1e' THEN RAISE EXCEPTION 'r512: parse did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.import_jita_eta_512(text,boolean)')) IS DISTINCT FROM 'daaa7f839a33bf7719d282f749896aa7' THEN RAISE EXCEPTION 'r512: import did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '2d0930074c9f9372aed02901964bb4e9' THEN RAISE EXCEPTION 'r512: board read did not land as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_512' AND added_in='r512' AND sort_order=300) IS DISTINCT FROM '9334a9062b9065f8426093636fdf5b11' THEN RAISE EXCEPTION 'r512: check did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r512')<>3
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r512_pins')::int+3 THEN RAISE EXCEPTION 'r512: pins not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r512_tick') THEN RAISE EXCEPTION 'r512: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r512_frc') THEN RAISE EXCEPTION 'r512: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r512: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r512: parts ETA board read changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_512') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r512: check not OK: %', y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
