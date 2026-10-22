-- r475 (F88, change request, Craig 22 Oct 2026 10:51 AWST): parts ETA from free-form emails, with the source email on hover.
-- Staging cdsmnqxtyyoeoznmbidd only. r436 (F47) only records the parts-staff template ("PARTS ETA - <Stock> - <R/O>", with
-- Stock, R/O, Part and ETA required). A free-form reply such as "PARTS DELAY ETA NOW dd/mm/yy" names no R/O and no part, can
-- refer to a renumbered stock ("... changed to new batch number ..."), and r436 keeps no subject or quoted line for a hover.
-- Adds only:
--   public.pdc_parts_eta: 5 nullable / defaulted columns (source_kind, source_from_name, source_subject, source_quote,
--                         previous_stock). Existing rows read as source_kind 'template' with no source text.
--   public.pdc_parts_eta_audit: action may also be 'set_parts_eta_from_email' (wrapper-only refusals are audited too).
--   public.set_parts_eta_from_email(...)  importer / controller / administrator (or the server-side import session). Resolves the
--        R/O from the stock when the email has none (exactly one open job), falls back to the previous stock number only when
--        the stated one is not on the board, defaults the part to 'Parts (per email)', then calls r436 public.set_parts_eta
--        unchanged (same sender allowlist, matching, idempotency, newer-replaces-older, dry run) and stores the source fields.
--   public.get_pdc_parts_eta_board_v2()   the r436 board read plus each ETA's source (sender, name, sent time, subject, quote).
-- r436 functions, pins and its check are not changed (set_parts_eta 88d31cbd, get_pdc_parts_eta_board decd9053).
-- Never creates vehicles, jobs or lines. Not touched: workshop_clock_tick, any board, booking, job, import or email path.
-- Check parts_eta_email_source_475 (sort 275). Undo: supabase/rollbacks/20261022031500_r475_parts_eta_email_source.down.sql.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r475: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r475: staging only'; END IF;
 PERFORM set_config('pdc.r475_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r475_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r475_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r475_tick') IS DISTINCT FROM '0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r475: clock tick changed since prepared (this release must not touch it)'; END IF;
 IF current_setting('pdc.r475_frc') IS DISTINCT FROM 'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r475: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec'
    OR (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract' AND added_in='r436') IS DISTINCT FROM '0854a63912b8bbf0ed50635e535e4a0e' THEN RAISE EXCEPTION 'r475: r436 parts ETA is not the version this release was prepared on'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.pdc_parts_eta_audit'::regclass AND conname='pdc_parts_eta_audit_action_check')
    IS DISTINCT FROM 'CHECK ((action = ANY (ARRAY[''set_parts_eta''::text, ''sender_domain_set''::text])))' THEN RAISE EXCEPTION 'r475: audit action check changed since prepared'; END IF;
 IF to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)') IS NOT NULL
    OR to_regprocedure('public.get_pdc_parts_eta_board_v2()') IS NOT NULL
    OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pdc_parts_eta' AND column_name IN ('source_kind','source_from_name','source_subject','source_quote','previous_stock'))
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r475')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_eta_email_source_475' OR added_in='r475') THEN RAISE EXCEPTION 'r475: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=275 OR fault_id='F88') THEN RAISE EXCEPTION 'r475: sort_order 275 / F88 taken'; END IF;
END $g$;

ALTER TABLE public.pdc_parts_eta
  ADD COLUMN source_kind text NOT NULL DEFAULT 'template' CONSTRAINT pdc_parts_eta_source_kind_check CHECK (source_kind IN ('template','free_form')),
  ADD COLUMN source_from_name text CONSTRAINT pdc_parts_eta_source_from_name_check CHECK (source_from_name IS NULL OR length(source_from_name)<=120),
  ADD COLUMN source_subject text CONSTRAINT pdc_parts_eta_source_subject_check CHECK (source_subject IS NULL OR length(source_subject)<=300),
  ADD COLUMN source_quote text CONSTRAINT pdc_parts_eta_source_quote_check CHECK (source_quote IS NULL OR length(source_quote)<=500),
  ADD COLUMN previous_stock text CONSTRAINT pdc_parts_eta_previous_stock_check CHECK (previous_stock IS NULL OR length(previous_stock)<=40);
ALTER TABLE public.pdc_parts_eta_audit DROP CONSTRAINT pdc_parts_eta_audit_action_check,
  ADD CONSTRAINT pdc_parts_eta_audit_action_check CHECK (action IN ('set_parts_eta','sender_domain_set','set_parts_eta_from_email'));

CREATE FUNCTION public.set_parts_eta_from_email(p_stock text, p_eta_date date, p_source_message_id text, p_sender text, p_message_at timestamptz,
  p_subject text, p_quote text, p_ro text DEFAULT NULL, p_part text DEFAULT NULL, p_line_no integer DEFAULT NULL, p_previous_stock text DEFAULT NULL,
  p_sender_name text DEFAULT NULL, p_bay text DEFAULT NULL, p_notes text DEFAULT NULL, p_dry_run boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE
  -- r475 (F88): any parts ETA email (template or free form) with its source. Matching, sender allowlist, idempotency and
  -- newer-replaces-older stay in r436 public.set_parts_eta, which this calls unchanged. Never creates vehicles, jobs or lines.
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_jwt_role text := coalesce(auth.jwt()->>'role','');
  v_actor text;
  v_stock text := upper(btrim(coalesce(p_stock,'')));
  v_prev text := nullif(upper(btrim(coalesce(p_previous_stock,''))),'');
  v_ro text := nullif(upper(btrim(coalesce(p_ro,''))),'');
  v_part text := coalesce(nullif(regexp_replace(btrim(coalesce(p_part,'')),'\s+',' ','g'),''),'Parts (per email)');
  v_subject text := nullif(regexp_replace(btrim(coalesce(p_subject,'')),'\s+',' ','g'),'');
  v_quote text := nullif(regexp_replace(btrim(coalesce(p_quote,'')),'\s+',' ','g'),'');
  v_name text := nullif(regexp_replace(btrim(coalesce(p_sender_name,'')),'\s+',' ','g'),'');
  v_msg text := btrim(coalesce(p_source_message_id,''));
  v_dry boolean := coalesce(p_dry_run,false);
  v_kind text;
  v_use text;
  v_fallback boolean := false;
  v_ro_from_stock boolean := false;
  v_placeholder boolean := false;
  v_nveh integer;
  v_nopen integer;
  v_status text;
  v_reason text;
  v_res jsonb;
  v_id uuid;
BEGIN
  IF v_role IN ('importer','operator','administrator') THEN
    v_actor := coalesce(auth.jwt()->>'email', v_uid::text);
  ELSIF v_uid IS NULL AND (v_jwt_role='service_role' OR session_user IN ('postgres','supabase_admin')) THEN
    v_actor := 'service:'||CASE WHEN v_jwt_role='service_role' THEN 'service_role' ELSE session_user::text END;
    v_role := 'service';
  ELSE
    RAISE EXCEPTION 'PDC_PARTS_ETA_FORBIDDEN: importer, controller or administrator access is required' USING errcode='42501';
  END IF;
  v_kind := CASE WHEN coalesce(v_subject,'') ~* '^((re|fw|fwd)\s*:\s*)*parts\s+eta\s*-' THEN 'template' ELSE 'free_form' END;
  v_use := v_stock;

  -- The source fields this function adds; set_parts_eta validates everything else.
  IF v_subject IS NULL OR length(v_subject)>300 THEN v_status:='invalid'; v_reason:='subject_missing_or_too_long';
  ELSIF v_quote IS NULL OR length(v_quote)>500 THEN v_status:='invalid'; v_reason:='quote_missing_or_too_long';
  ELSIF p_message_at IS NULL THEN v_status:='invalid'; v_reason:='message_at_missing';
  ELSIF v_name IS NOT NULL AND length(v_name)>120 THEN v_status:='invalid'; v_reason:='sender_name_too_long';
  ELSIF v_prev IS NOT NULL AND (length(v_prev)>40 OR v_prev ~ '[[:cntrl:]]') THEN v_status:='invalid'; v_reason:='previous_stock_too_long';
  END IF;

  IF v_status IS NULL AND v_msg<>'' AND EXISTS(SELECT 1 FROM public.pdc_parts_eta e WHERE e.source_message_id=v_msg) THEN
    -- Already processed: set_parts_eta answers 'duplicate' before it looks at anything else.
    IF v_ro IS NULL THEN v_ro := 'DUPLICATE'; v_placeholder := true; END IF;
  ELSIF v_status IS NULL THEN
    -- Renumbered stock: the stated (new) number wins; the previous number is used only when the stated one is not on the board.
    SELECT count(*) INTO v_nveh FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_stock;
    IF v_nveh=0 AND v_prev IS NOT NULL AND v_prev<>v_stock
       AND EXISTS(SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_prev) THEN
      v_use := v_prev; v_fallback := true;
    END IF;
    IF v_ro IS NULL THEN
      SELECT count(DISTINCT upper(btrim(j.ro_number))), min(upper(btrim(j.ro_number))) INTO v_nopen, v_ro
      FROM pdc_parts_private.jobs j JOIN public.vehicles v ON v.id=j.vehicle_id AND v.deleted_at IS NULL
      WHERE j.closed_at IS NULL AND (upper(btrim(j.stock_number))=v_use OR upper(btrim(v.stock_number))=v_use);
      IF v_nopen=1 THEN
        v_ro_from_stock := true;
      ELSE
        v_ro := CASE WHEN v_nopen>1 THEN 'AMBIGUOUS' ELSE 'NO-OPEN-JOB' END; v_placeholder := true;
        IF v_nopen>1 THEN
          -- Sender and field problems are reported first (dry run of set_parts_eta writes nothing).
          v_res := public.set_parts_eta(v_use, v_ro, p_line_no, v_part, p_eta_date, p_bay, p_notes, v_msg, p_sender, true, p_message_at);
          IF v_res->>'status' IN ('invalid','rejected_sender') THEN v_status := v_res->>'status'; v_reason := v_res->>'reason';
          ELSE v_status := 'ambiguous'; v_reason := 'more_than_one_open_job_on_stock_send_ro'; END IF;
          v_res := NULL;
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_status IS NULL THEN
    v_res := public.set_parts_eta(v_use, v_ro, p_line_no, v_part, p_eta_date, p_bay, p_notes, v_msg, p_sender, v_dry, p_message_at);
    v_status := v_res->>'status'; v_reason := v_res->>'reason';
    IF v_ro='NO-OPEN-JOB' AND v_reason='ro_not_on_this_stock' THEN v_reason := 'no_open_job_on_stock'; END IF;
    v_id := nullif(v_res->>'parts_eta_id','')::uuid;
    IF v_id IS NOT NULL AND NOT v_dry AND v_status IN ('applied','replaced','stale') THEN
      UPDATE public.pdc_parts_eta SET source_kind=v_kind, source_from_name=v_name, source_subject=v_subject, source_quote=v_quote,
        previous_stock=CASE WHEN v_fallback THEN v_stock ELSE v_prev END
      WHERE id=v_id;
    END IF;
  ELSE
    v_res := jsonb_build_object('parts_eta_id',NULL,'job_id',NULL,'vehicle_id',NULL,'line_no',p_line_no,'line_identity',NULL,
      'previous_eta',NULL,'eta_date',p_eta_date,'bay',p_bay,'dry_run',v_dry,
      'message',CASE WHEN v_status='ambiguous' THEN 'More than one open job on this stock: send the R/O. Nothing changed.'
        WHEN v_status='rejected_sender' THEN 'Sender is not on the allowed parts-staff domains: '||replace(v_reason,'_',' ')||'.'
        ELSE 'Invalid request: '||replace(v_reason,'_',' ')||'.' END);
    IF NOT v_dry THEN
      INSERT INTO public.pdc_parts_eta_audit(action,actor_id,actor,actor_role,source_message_id,sender,stock,ro,line_no,part,eta_date,status,result)
      VALUES ('set_parts_eta_from_email',v_uid,v_actor,v_role,nullif(v_msg,''),nullif(lower(btrim(coalesce(p_sender,''))),''),nullif(v_stock,''),
        CASE WHEN v_placeholder THEN NULL ELSE v_ro END,p_line_no,v_part,p_eta_date,v_status,
        v_res || jsonb_build_object('status',v_status,'reason',v_reason,'subject',v_subject,'quote',v_quote,'previous_stock',v_prev));
    END IF;
  END IF;

  RETURN v_res || jsonb_build_object('status',v_status,'reason',v_reason,'part',v_part,'source_kind',v_kind,
    'matched_stock',nullif(v_use,''),'previous_stock',v_prev,'stock_fallback',v_fallback,
    'ro',CASE WHEN v_placeholder THEN NULL ELSE v_ro END,'ro_from_stock',v_ro_from_stock,
    'source',jsonb_build_object('from_name',v_name,'sender',nullif(btrim(coalesce(p_sender,'')),''),'sent_at',p_message_at,'subject',v_subject,'quote',v_quote));
END
$f$;
REVOKE ALL ON FUNCTION public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean) TO authenticated, service_role;

CREATE FUNCTION public.get_pdc_parts_eta_board_v2()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
  -- r475 (F88): the r436 board read (same rows, same gate) plus each current ETA's source email for the hover. Board readers only.
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role),false) THEN NULL::jsonb ELSE
   jsonb_build_object('today',(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,'version','r475','vehicles',coalesce((
    SELECT jsonb_agg(x ORDER BY x->>'vehicle_id') FROM (
     SELECT jsonb_build_object('vehicle_id',e.vehicle_id,'stock_number',v.stock_number,'latest_eta',max(e.eta_date),'count',count(*),
       'overdue_count',count(*) FILTER (WHERE e.eta_date<(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date),
       'parts',jsonb_agg(jsonb_build_object('part',e.part,'eta_date',e.eta_date,'bay',e.bay,'line_no',e.line_no,'ro',e.ro_number,
         'notes',e.notes,'set_at',e.set_at,'sender',e.sender,'sender_name',e.source_from_name,'message_at',e.message_at,
         'subject',e.source_subject,'quote',e.source_quote,'source_kind',e.source_kind,'previous_stock',e.previous_stock)
         ORDER BY e.eta_date DESC, e.part)) x
     FROM public.pdc_parts_eta e
     JOIN public.vehicles v ON v.id=e.vehicle_id AND v.deleted_at IS NULL
     JOIN pdc_parts_private.jobs j ON j.id=e.parts_job_id AND j.closed_at IS NULL
     WHERE NOT e.superseded
     GROUP BY e.vehicle_id, v.stock_number) s),'[]'::jsonb)) END
$f$;
REVOKE ALL ON FUNCTION public.get_pdc_parts_eta_board_v2() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_parts_eta_board_v2() TO authenticated, service_role;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)','a81b786bfc7868c3217d827933299678','r475','r475 (F88): parts ETA from any parts email (free form or template) with its source; calls r436 set_parts_eta'),
 ('public.get_pdc_parts_eta_board_v2()','6a0046123aeb862667dce68884318850','r475','r475 (F88): board read of current parts ETAs with the source email');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('parts_eta_email_source_475','F88','Parts ETA from free-form emails (r475): set_parts_eta_from_email / board v2 are pinned, security definer and closed to anon; the 5 source columns and the audit action exist; 7 dry-run refusals (sender, unknown stock, renumbered unknown stock, no quote, no subject, no sent time, no message id) return the right status and write nothing; a free-form ETA naming only a stock with one open job resolves its R/O, and a renumbered stock falls back to the previous number (dry run)',
  $chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r475'
), fn AS (
  SELECT count(*) FILTER (WHERE p.prosecdef) sd, bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE')) no_anon,
   bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')) auth_exec
  FROM pg_catalog.pg_proc p WHERE p.oid IN (pg_catalog.to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)'),
   pg_catalog.to_regprocedure('public.get_pdc_parts_eta_board_v2()'))
), cols AS (
  SELECT count(*) n FROM information_schema.columns WHERE table_schema='public' AND table_name='pdc_parts_eta'
   AND column_name IN ('source_kind','source_from_name','source_subject','source_quote','previous_stock')
), aud AS (
  SELECT strpos(pg_catalog.pg_get_constraintdef(c.oid),'set_parts_eta_from_email')>0 ok FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='public.pdc_parts_eta_audit'::regclass AND c.conname='pdc_parts_eta_audit_action_check'
), t AS (SELECT (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date d, clock_timestamp()-interval '1 hour' sent),
one AS (
  SELECT x.s FROM (
    SELECT upper(btrim(v.stock_number)) s FROM pdc_parts_private.jobs j JOIN public.vehicles v ON v.id=j.vehicle_id AND v.deleted_at IS NULL
    WHERE j.closed_at IS NULL AND btrim(coalesce(v.stock_number,''))<>'' AND upper(btrim(j.ro_number)) ~ '^[A-Z0-9][A-Z0-9/_-]{0,39}$' GROUP BY 1 HAVING count(*)=1) x
  WHERE (SELECT count(*) FROM public.vehicles v2 WHERE v2.deleted_at IS NULL AND upper(btrim(v2.stock_number))=x.s)=1
    AND (SELECT count(*) FROM pdc_parts_private.jobs j2 JOIN public.vehicles v3 ON v3.id=j2.vehicle_id AND v3.deleted_at IS NULL
         WHERE j2.closed_at IS NULL AND (upper(btrim(j2.stock_number))=x.s OR upper(btrim(v3.stock_number))=x.s))=1
  ORDER BY 1 LIMIT 1
), cases(name, want_status, want_reason, r) AS (
  SELECT 'gmail sender','rejected_sender','sender_domain_not_allowed',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-1',p_sender=>'parts@gmail.com',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check',p_quote=>'PARTS DELAY ETA NOW',p_dry_run=>true) UNION ALL
  SELECT 'unknown stock','unmatched','stock_not_found',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-2',p_sender=>'Parts <parts@pmgwa.com.au>',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check',p_quote=>'PARTS DELAY ETA NOW',p_dry_run=>true) UNION ALL
  SELECT 'renumbered unknown stock','unmatched','stock_not_found',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NEW',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-3',p_sender=>'parts@broometoyota.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check changed to new batch number',p_quote=>'ETA',p_previous_stock=>'R475-CHECK-OLD',p_dry_run=>true) UNION ALL
  SELECT 'no quote','invalid','quote_missing_or_too_long',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-4',p_sender=>'parts@pmgwa.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check',p_quote=>' ',p_dry_run=>true) UNION ALL
  SELECT 'no subject','invalid','subject_missing_or_too_long',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-5',p_sender=>'parts@pmgwa.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>NULL,p_quote=>'ETA',p_dry_run=>true) UNION ALL
  SELECT 'no sent time','invalid','message_at_missing',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-6',p_sender=>'parts@pmgwa.com.au',p_message_at=>NULL,p_subject=>'RE: check',p_quote=>'ETA',p_dry_run=>true) UNION ALL
  SELECT 'no message id','invalid','source_message_id_missing_or_too_long',public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NO-STOCK',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'',p_sender=>'parts@pmgwa.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check',p_quote=>'ETA',p_dry_run=>true)
), cs AS (
  SELECT count(*) n, count(*) FILTER (WHERE r->>'status'=want_status AND r->>'reason'=want_reason AND r->>'dry_run'='true' AND r->>'parts_eta_id' IS NULL AND r->>'source_kind'='free_form') good,
   string_agg(CASE WHEN NOT (r->>'status'=want_status AND r->>'reason'=want_reason AND r->>'dry_run'='true') THEN name||' -> '||coalesce(r->>'status','null')||'/'||coalesce(r->>'reason','null') END,'; ') bad
  FROM cases
), live AS (
  SELECT public.set_parts_eta_from_email(p_stock=>one.s,p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-live',p_sender=>'parts@pmgwa.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>'RE: check',p_quote=>'PARTS DELAY ETA NOW',p_dry_run=>true) a,
   public.set_parts_eta_from_email(p_stock=>'R475-CHECK-NEW',p_eta_date=>(SELECT d+7 FROM t),p_source_message_id=>'r475-check-renumber',p_sender=>'parts@pmgwa.com.au',p_message_at=>(SELECT sent FROM t),p_subject=>'PARTS ETA - check',p_quote=>'ETA',p_previous_stock=>one.s,p_dry_run=>true) b
  FROM one
), lv AS (
  SELECT count(*) n, count(*) FILTER (WHERE a->>'status' IN ('applied','replaced','stale') AND a->>'ro_from_stock'='true' AND a->>'ro' IS NOT NULL AND a->>'part'='Parts (per email)' AND a->>'parts_eta_id' IS NULL) a_ok,
   count(*) FILTER (WHERE b->>'status' IN ('applied','replaced','stale') AND b->>'stock_fallback'='true' AND b->>'source_kind'='template' AND b->>'parts_eta_id' IS NULL) b_ok,
   string_agg(coalesce(a->>'status','null')||'/'||coalesce(a->>'reason','null')||' | '||coalesce(b->>'status','null')||'/'||coalesce(b->>'reason','null'),'; ') detail
  FROM live
)
SELECT (SELECT n=2 AND ok=2 FROM pins) AND (SELECT sd=2 AND no_anon AND auth_exec FROM fn) AND (SELECT n=5 FROM cols) AND coalesce((SELECT ok FROM aud),false)
   AND (SELECT good=n AND n=7 FROM cs) AND (SELECT n=a_ok AND n=b_ok FROM lv)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_parts_eta WHERE source_message_id LIKE 'r475-check-%')
   AND NOT EXISTS(SELECT 1 FROM public.pdc_parts_eta_audit WHERE source_message_id LIKE 'r475-check-%') AS ok,
 'r475 pins '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)||'; functions '||(SELECT sd FROM fn)||'/2 security definer, anon blocked '||(SELECT no_anon FROM fn)
 ||'; source columns '||(SELECT n FROM cols)||'/5; audit action '||coalesce((SELECT ok FROM aud),false)
 ||'; dry-run refusals '||(SELECT good FROM cs)||'/'||(SELECT n FROM cs)||' right'||coalesce(' (WRONG: '||(SELECT bad FROM cs)||')','')
 ||'; stock-only and renumbered live dry runs '||(SELECT a_ok FROM lv)||'+'||(SELECT b_ok FROM lv)||' of '||(SELECT n FROM lv)||' right'||coalesce(' ('||(SELECT detail FROM lv)||')','')
 ||'; free-form ETAs current '||(SELECT count(*) FROM public.pdc_parts_eta WHERE NOT superseded AND source_kind='free_form') AS detail
$chk$,true,275,'r475');

DO $g$ DECLARE x record; y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)')) IS DISTINCT FROM 'a81b786bfc7868c3217d827933299678'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board_v2()')) IS DISTINCT FROM '6a0046123aeb862667dce68884318850' THEN RAISE EXCEPTION 'r475: functions did not land as expected'; END IF;
 IF (SELECT count(*) FROM pg_proc WHERE oid IN (to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)'),to_regprocedure('public.get_pdc_parts_eta_board_v2()'))
     AND prosecdef AND proowner::regrole::text='postgres' AND NOT has_function_privilege('anon',oid,'EXECUTE'))<>2 THEN RAISE EXCEPTION 'r475: owner / security definer / grants not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r475: r436 functions changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r475')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r475_pins')::int+2 THEN RAISE EXCEPTION 'r475: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_email_source_475' AND added_in='r475' AND sort_order=275) IS DISTINCT FROM '4a7027ea5c24ee0071d4a0ee72c7393a' THEN RAISE EXCEPTION 'r475: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('parts_eta_email_source_475','parts_eta_rpc_contract') LOOP
  EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r475: check % not OK: %',x.check_name,y.detail; END IF;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r475_tick') THEN RAISE EXCEPTION 'r475: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r475_frc') THEN RAISE EXCEPTION 'r475: fault_regression_check changed'; END IF;
END $g$;
