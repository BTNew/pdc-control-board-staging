-- r436 (F47, change request, Craig via PMB Email 13:10 AWST 21 Oct): parts ETA per job / job-card line on the PDC staging board.
-- Staging cdsmnqxtyyoeoznmbidd only. Parts staff email "PARTS ETA - <Stock> - <R/O>" (Stock, R/O, optional Line, Part, ETA dd/mm/yy Perth,
-- optional Bay and Notes); PMB Email imports them hourly through public.set_parts_eta. Adds only new objects:
--   public.pdc_parts_eta                 one row per message; current = NOT superseded, one current row per job + line + part
--   public.pdc_parts_eta_sender_domains  admin-edited allowlist of exact sender domains (seed broometoyota.com.au, pmgwa.com.au)
--   public.pdc_parts_eta_audit           one row per non-dry-run call (every status) and per allowlist change
--   public.set_parts_eta(...)            importer / controller / administrator (or the server-side import session); never creates
--                                        vehicles, jobs or lines; idempotent on p_source_message_id; p_dry_run previews
--   public.get_pdc_parts_eta_board()     board readers: current ETAs per vehicle for open jobs (latest ETA, count, overdue)
--   public.set_pdc_parts_eta_sender_domain(domain, allowed, note)  administrators only
-- RLS on all three tables: board readers (viewer and up) read pdc_parts_eta; admins read the allowlist and audit; nobody writes
-- except through the functions. No existing function, table, row, import or email path is changed. No FK to live tables.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r436: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r436: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r436: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r436: fault_regression_check changed'; END IF;
 IF to_regprocedure('pdc_work_categories_private.before_import_rules_20261017(uuid)') IS NULL OR to_regclass('pdc_parts_private.jobs') IS NULL
    OR to_regprocedure('public.is_pdc_role(pdc_role)') IS NULL THEN RAISE EXCEPTION 'r436: a dependency is missing'; END IF;
 IF to_regclass('public.pdc_parts_eta') IS NOT NULL OR to_regclass('public.pdc_parts_eta_sender_domains') IS NOT NULL OR to_regclass('public.pdc_parts_eta_audit') IS NOT NULL
    OR to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)') IS NOT NULL OR to_regprocedure('public.get_pdc_parts_eta_board()') IS NOT NULL OR to_regprocedure('public.set_pdc_parts_eta_sender_domain(text,boolean,text)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc WHERE proname='set_parts_eta')
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r436')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract' OR added_in='r436') THEN RAISE EXCEPTION 'r436: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=236) THEN RAISE EXCEPTION 'r436: sort_order 236 taken'; END IF;
END $g$;

CREATE TABLE public.pdc_parts_eta_sender_domains(
  domain text PRIMARY KEY CHECK (domain=lower(btrim(domain)) AND domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' AND length(domain)<=120),
  active boolean NOT NULL DEFAULT true,
  note text CHECK (note IS NULL OR length(note)<=300),
  changed_by text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO public.pdc_parts_eta_sender_domains(domain,active,note,changed_by) VALUES
 ('broometoyota.com.au',true,'r436 seed: Broome Toyota parts staff','r436'),
 ('pmgwa.com.au',true,'r436 seed: PMG WA','r436');

CREATE TABLE public.pdc_parts_eta(
  id uuid PRIMARY KEY,
  parts_job_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  stock_number text NOT NULL,
  ro_number text NOT NULL,
  line_no integer CHECK (line_no IS NULL OR line_no BETWEEN 1 AND 999),
  line_identity text,
  part text NOT NULL CHECK (length(part) BETWEEN 1 AND 120),
  part_key text NOT NULL CHECK (part_key=lower(part)),
  eta_date date NOT NULL,
  bay text CHECK (bay IS NULL OR length(bay)<=40),
  notes text CHECK (notes IS NULL OR length(notes)<=500),
  source_message_id text NOT NULL UNIQUE CHECK (length(source_message_id) BETWEEN 1 AND 300),
  sender text NOT NULL,
  message_at timestamptz,
  set_at timestamptz NOT NULL,
  set_by uuid,
  set_by_actor text NOT NULL,
  superseded boolean NOT NULL DEFAULT false,
  superseded_at timestamptz,
  superseded_by uuid,
  result jsonb NOT NULL,
  CHECK (superseded = (superseded_at IS NOT NULL)));
CREATE UNIQUE INDEX pdc_parts_eta_one_current ON public.pdc_parts_eta(parts_job_id, coalesce(line_no,0), part_key) WHERE NOT superseded;
CREATE INDEX pdc_parts_eta_vehicle_current ON public.pdc_parts_eta(vehicle_id) WHERE NOT superseded;

CREATE TABLE public.pdc_parts_eta_audit(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT clock_timestamp(),
  action text NOT NULL CHECK (action IN ('set_parts_eta','sender_domain_set')),
  actor_id uuid, actor text, actor_role text,
  source_message_id text, sender text, stock text, ro text, line_no integer, part text, eta_date date,
  status text NOT NULL, result jsonb NOT NULL);
CREATE INDEX pdc_parts_eta_audit_msg ON public.pdc_parts_eta_audit(source_message_id);

ALTER TABLE public.pdc_parts_eta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_parts_eta_sender_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_parts_eta_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_parts_eta, public.pdc_parts_eta_sender_domains, public.pdc_parts_eta_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pdc_parts_eta, public.pdc_parts_eta_sender_domains, public.pdc_parts_eta_audit TO authenticated;
CREATE POLICY pdc_parts_eta_board_read ON public.pdc_parts_eta FOR SELECT TO authenticated USING (public.is_pdc_role('viewer'::public.pdc_role));
CREATE POLICY pdc_parts_eta_domains_admin_read ON public.pdc_parts_eta_sender_domains FOR SELECT TO authenticated USING (public.is_pdc_role('administrator'::public.pdc_role));
CREATE POLICY pdc_parts_eta_audit_admin_read ON public.pdc_parts_eta_audit FOR SELECT TO authenticated USING (public.is_pdc_role('administrator'::public.pdc_role));

CREATE FUNCTION public.set_parts_eta(p_stock text, p_ro text, p_line_no integer DEFAULT NULL, p_part text DEFAULT NULL, p_eta_date date DEFAULT NULL,
  p_bay text DEFAULT NULL, p_notes text DEFAULT NULL, p_source_message_id text DEFAULT NULL, p_sender text DEFAULT NULL,
  p_dry_run boolean DEFAULT false, p_message_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE
  -- r436 (F47): parts ETA from the parts-staff email template, imported hourly by PMB Email. Never creates vehicles, jobs or lines.
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_jwt_role text := coalesce(auth.jwt()->>'role','');
  v_actor text;
  v_today date := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date;
  v_stock text := upper(btrim(coalesce(p_stock,'')));
  v_ro text := upper(btrim(coalesce(p_ro,'')));
  v_part text := regexp_replace(btrim(coalesce(p_part,'')),'\s+',' ','g');
  v_key text;
  v_bay text := nullif(regexp_replace(btrim(coalesce(p_bay,'')),'\s+',' ','g'),'');
  v_notes text := nullif(btrim(coalesce(p_notes,'')),'');
  v_msg text := btrim(coalesce(p_source_message_id,''));
  v_sender_raw text := lower(btrim(coalesce(p_sender,'')));
  v_sender text;
  v_domain text;
  v_dry boolean := coalesce(p_dry_run,false);
  v_order timestamptz := coalesce(p_message_at, clock_timestamp());
  v_status text; v_reason text; v_msgtxt text;
  v_job_id uuid; v_vehicle_id uuid; v_job_ro text; v_job_stock text; v_njobs int; v_nclosed int; v_nstock int;
  v_line_identity text; v_nlines int;
  v_cur public.pdc_parts_eta%ROWTYPE; v_dup public.pdc_parts_eta%ROWTYPE;
  v_id uuid; v_prev date; v_res jsonb;
BEGIN
  IF v_role IN ('importer','operator','administrator') THEN
    v_actor := coalesce(auth.jwt()->>'email', v_uid::text);
  ELSIF v_uid IS NULL AND (v_jwt_role='service_role' OR session_user IN ('postgres','supabase_admin')) THEN
    v_actor := 'service:'||CASE WHEN v_jwt_role='service_role' THEN 'service_role' ELSE session_user::text END;
    v_role := 'service';
  ELSE
    RAISE EXCEPTION 'PDC_PARTS_ETA_FORBIDDEN: importer, controller or administrator access is required' USING errcode='42501';
  END IF;

  v_key := lower(v_part);
  v_sender := coalesce(substring(v_sender_raw from '<([^<>]+)>\s*$'), v_sender_raw);
  v_domain := substring(v_sender from '^[^@\s<>"]+@([a-z0-9-]+(?:\.[a-z0-9-]+)+)$');

  -- Idempotent on the source message id: a repeat returns the stored result and changes nothing, whatever else it says.
  IF v_msg<>'' AND length(v_msg)<=300 THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc_parts_eta_msg:'||v_msg,0));
    SELECT * INTO v_dup FROM public.pdc_parts_eta WHERE source_message_id=v_msg;
    IF FOUND THEN
      v_status:='duplicate'; v_reason:='source_message_id_already_processed';
      v_res := v_dup.result || jsonb_build_object('status','duplicate','original_status',v_dup.result->>'status',
        'message','Already processed this message; nothing changed.','dry_run',v_dry);
    END IF;
  END IF;

  IF v_status IS NOT NULL THEN NULL;
  ELSIF v_stock='' OR length(v_stock)>40 OR v_stock ~ '[[:cntrl:]]' THEN v_status:='invalid'; v_reason:='stock_missing_or_too_long';
  ELSIF v_ro='' OR length(v_ro)>40 OR v_ro !~ '^[A-Z0-9][A-Z0-9/_-]*$' THEN v_status:='invalid'; v_reason:='ro_missing_or_malformed';
  ELSIF p_line_no IS NOT NULL AND (p_line_no<1 OR p_line_no>999) THEN v_status:='invalid'; v_reason:='line_no_out_of_range';
  ELSIF v_part='' OR length(v_part)>120 OR v_part ~ '[[:cntrl:]]' THEN v_status:='invalid'; v_reason:='part_missing_or_too_long';
  ELSIF p_eta_date IS NULL THEN v_status:='invalid'; v_reason:='eta_date_missing';
  ELSIF p_eta_date < v_today-30 OR p_eta_date > v_today+366 THEN v_status:='invalid'; v_reason:='eta_date_out_of_range';
  ELSIF v_bay IS NOT NULL AND (length(v_bay)>40 OR v_bay ~ '[[:cntrl:]]') THEN v_status:='invalid'; v_reason:='bay_too_long';
  ELSIF v_notes IS NOT NULL AND length(v_notes)>500 THEN v_status:='invalid'; v_reason:='notes_too_long';
  ELSIF v_msg='' OR length(v_msg)>300 THEN v_status:='invalid'; v_reason:='source_message_id_missing_or_too_long';
  ELSIF p_message_at IS NOT NULL AND p_message_at > clock_timestamp()+interval '1 day' THEN v_status:='invalid'; v_reason:='message_at_in_future';
  ELSIF v_domain IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_parts_eta_sender_domains d WHERE d.active AND d.domain=v_domain) THEN
    v_status:='rejected_sender'; v_reason:=CASE WHEN v_domain IS NULL THEN 'sender_not_an_email_address' ELSE 'sender_domain_not_allowed' END;
  END IF;

  IF v_status IS NULL THEN
    SELECT count(*), count(*) FILTER (WHERE j.closed_at IS NOT NULL) INTO v_njobs, v_nclosed
    FROM pdc_parts_private.jobs j JOIN public.vehicles v ON v.id=j.vehicle_id AND v.deleted_at IS NULL
    WHERE upper(btrim(j.ro_number))=v_ro AND (upper(btrim(j.stock_number))=v_stock OR upper(btrim(v.stock_number))=v_stock);
    IF v_njobs - v_nclosed = 0 THEN
      SELECT count(*) INTO v_nstock FROM public.vehicles v WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_stock;
      v_status:='unmatched';
      v_reason:=CASE WHEN v_nclosed>0 THEN 'job_closed' WHEN v_nstock=0 THEN 'stock_not_found' ELSE 'ro_not_on_this_stock' END;
    ELSIF v_njobs - v_nclosed > 1 THEN
      v_status:='ambiguous'; v_reason:='more_than_one_open_job_for_stock_ro';
    ELSE
      SELECT j.id, j.vehicle_id, j.ro_number, v.stock_number INTO v_job_id, v_vehicle_id, v_job_ro, v_job_stock
      FROM pdc_parts_private.jobs j JOIN public.vehicles v ON v.id=j.vehicle_id AND v.deleted_at IS NULL
      WHERE j.closed_at IS NULL AND upper(btrim(j.ro_number))=v_ro AND (upper(btrim(j.stock_number))=v_stock OR upper(btrim(v.stock_number))=v_stock);
      IF p_line_no IS NOT NULL THEN
        SELECT count(*), min(l->>'line_identity') INTO v_nlines, v_line_identity
        FROM jsonb_array_elements(pdc_work_categories_private.before_import_rules_20261017(v_vehicle_id)) l
        WHERE upper(btrim(coalesce(l->>'job_card_number','')))=v_ro AND coalesce(l->>'active','true')<>'false'
          AND coalesce(l->>'original_line_number','') ~ '^[0-9]{1,6}$' AND (l->>'original_line_number')::int=p_line_no;
        IF v_nlines=0 THEN v_status:='unmatched'; v_reason:='line_not_on_job_card';
        ELSIF v_nlines>1 THEN v_status:='ambiguous'; v_reason:='more_than_one_line_with_this_number'; END IF;
      END IF;
    END IF;
  END IF;

  IF v_status IS NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('pdc_parts_eta_job:'||v_job_id::text,0));
    SELECT * INTO v_cur FROM public.pdc_parts_eta e
    WHERE e.parts_job_id=v_job_id AND coalesce(e.line_no,0)=coalesce(p_line_no,0) AND e.part_key=v_key AND NOT e.superseded FOR UPDATE;
    IF NOT FOUND THEN v_status:='applied'; v_reason:='new_parts_eta';
    ELSIF v_order >= coalesce(v_cur.message_at, v_cur.set_at) THEN v_status:='replaced'; v_reason:='newer_message_replaces_older'; v_prev:=v_cur.eta_date;
    ELSE v_status:='stale'; v_reason:='older_than_current_eta'; v_prev:=v_cur.eta_date; END IF;
  END IF;

  v_msgtxt := CASE v_status
    WHEN 'applied' THEN 'Parts ETA set.' WHEN 'replaced' THEN 'Parts ETA replaced (previous '||to_char(v_prev,'DD/MM/YY')||').'
    WHEN 'stale' THEN 'Kept the newer ETA ('||to_char(v_prev,'DD/MM/YY')||'); this older message was recorded but not applied.'
    WHEN 'duplicate' THEN 'Already processed this message; nothing changed.'
    WHEN 'unmatched' THEN 'No matching open job: '||replace(v_reason,'_',' ')||'. Nothing was created.'
    WHEN 'ambiguous' THEN 'More than one match: '||replace(v_reason,'_',' ')||'. Nothing changed.'
    WHEN 'rejected_sender' THEN 'Sender is not on the allowed parts-staff domains: '||replace(v_reason,'_',' ')||'.'
    ELSE 'Invalid request: '||replace(coalesce(v_reason,'unknown'),'_',' ')||'.' END;

  IF v_status IN ('applied','replaced','stale') AND NOT v_dry THEN
    v_id := gen_random_uuid();
    IF v_status='replaced' THEN
      UPDATE public.pdc_parts_eta SET superseded=true, superseded_at=clock_timestamp(), superseded_by=v_id WHERE id=v_cur.id;
    END IF;
  END IF;

  IF v_res IS NULL THEN
    v_res := jsonb_build_object('status',v_status,'reason',v_reason,'parts_eta_id',v_id,'job_id',v_job_id,'vehicle_id',v_vehicle_id,
      'line_no',p_line_no,'line_identity',v_line_identity,'part',nullif(v_part,''),'previous_eta',v_prev,
      'eta_date',CASE WHEN v_status='stale' THEN v_prev ELSE p_eta_date END,'bay',v_bay,'message',v_msgtxt,'dry_run',v_dry);
  END IF;

  IF v_status IN ('applied','replaced','stale') AND NOT v_dry THEN
    INSERT INTO public.pdc_parts_eta(id,parts_job_id,vehicle_id,stock_number,ro_number,line_no,line_identity,part,part_key,eta_date,bay,notes,
      source_message_id,sender,message_at,set_at,set_by,set_by_actor,superseded,superseded_at,superseded_by,result)
    VALUES (v_id,v_job_id,v_vehicle_id,v_job_stock,v_job_ro,p_line_no,v_line_identity,v_part,v_key,p_eta_date,v_bay,v_notes,
      v_msg,v_sender,p_message_at,clock_timestamp(),v_uid,v_actor,v_status='stale',CASE WHEN v_status='stale' THEN clock_timestamp() END,
      CASE WHEN v_status='stale' THEN v_cur.id END,v_res);
  END IF;

  IF NOT v_dry THEN
    INSERT INTO public.pdc_parts_eta_audit(action,actor_id,actor,actor_role,source_message_id,sender,stock,ro,line_no,part,eta_date,status,result)
    VALUES ('set_parts_eta',v_uid,v_actor,v_role,nullif(v_msg,''),nullif(v_sender,''),nullif(v_stock,''),nullif(v_ro,''),p_line_no,nullif(v_part,''),p_eta_date,v_status,v_res);
  END IF;
  RETURN v_res;
END
$f$;
REVOKE ALL ON FUNCTION public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone) TO authenticated, service_role;

CREATE FUNCTION public.get_pdc_parts_eta_board()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
  -- r436 (F47): current parts ETAs per vehicle for the board (open jobs on live vehicles only). Board readers only.
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role),false) THEN NULL::jsonb ELSE
   jsonb_build_object('today',(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,'vehicles',coalesce((
    SELECT jsonb_agg(x ORDER BY x->>'vehicle_id') FROM (
     SELECT jsonb_build_object('vehicle_id',e.vehicle_id,'stock_number',v.stock_number,'latest_eta',max(e.eta_date),'count',count(*),
       'overdue_count',count(*) FILTER (WHERE e.eta_date<(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date),
       'parts',jsonb_agg(jsonb_build_object('part',e.part,'eta_date',e.eta_date,'bay',e.bay,'line_no',e.line_no,'ro',e.ro_number,
         'notes',e.notes,'set_at',e.set_at) ORDER BY e.eta_date DESC, e.part)) x
     FROM public.pdc_parts_eta e
     JOIN public.vehicles v ON v.id=e.vehicle_id AND v.deleted_at IS NULL
     JOIN pdc_parts_private.jobs j ON j.id=e.parts_job_id AND j.closed_at IS NULL
     WHERE NOT e.superseded
     GROUP BY e.vehicle_id, v.stock_number) s),'[]'::jsonb)) END
$f$;
REVOKE ALL ON FUNCTION public.get_pdc_parts_eta_board() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_parts_eta_board() TO authenticated, service_role;

CREATE FUNCTION public.set_pdc_parts_eta_sender_domain(p_domain text, p_allowed boolean, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE
  -- r436 (F47): administrators edit the parts ETA sender allowlist (exact domains, lower case). Rows are never deleted.
  v_domain text := lower(btrim(coalesce(p_domain,'')));
  v_actor text := coalesce(auth.jwt()->>'email', auth.uid()::text);
  v_before jsonb; v_after jsonb;
BEGIN
  IF public.current_pdc_user_role()::text IS DISTINCT FROM 'administrator' THEN
    RAISE EXCEPTION 'PDC_PARTS_ETA_FORBIDDEN: administrator access is required' USING errcode='42501';
  END IF;
  IF v_domain !~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' OR length(v_domain)>120 OR p_allowed IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_domain','domain',v_domain);
  END IF;
  SELECT to_jsonb(d) INTO v_before FROM public.pdc_parts_eta_sender_domains d WHERE d.domain=v_domain;
  INSERT INTO public.pdc_parts_eta_sender_domains(domain,active,note,changed_by,changed_at)
  VALUES (v_domain,p_allowed,nullif(btrim(coalesce(p_note,'')),''),v_actor,clock_timestamp())
  ON CONFLICT (domain) DO UPDATE SET active=EXCLUDED.active, note=coalesce(EXCLUDED.note,pdc_parts_eta_sender_domains.note),
    changed_by=EXCLUDED.changed_by, changed_at=EXCLUDED.changed_at
  WHERE pdc_parts_eta_sender_domains.domain=EXCLUDED.domain;
  SELECT to_jsonb(d) INTO v_after FROM public.pdc_parts_eta_sender_domains d WHERE d.domain=v_domain;
  INSERT INTO public.pdc_parts_eta_audit(action,actor_id,actor,actor_role,status,result)
  VALUES ('sender_domain_set',auth.uid(),v_actor,'administrator',CASE WHEN p_allowed THEN 'allowed' ELSE 'removed' END,
    jsonb_build_object('before',v_before,'after',v_after));
  RETURN jsonb_build_object('ok',true,'domain',v_domain,'active',p_allowed,'domains',
    (SELECT jsonb_agg(d.domain ORDER BY d.domain) FROM public.pdc_parts_eta_sender_domains d WHERE d.active));
END
$f$;
REVOKE ALL ON FUNCTION public.set_pdc_parts_eta_sender_domain(text,boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_parts_eta_sender_domain(text,boolean,text) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)','88d31cbd6ca5ddd372e3143d5f8c013f','r436','r436 (F47): parts ETA import RPC (importer/controller/admin; allowlisted sender domains; idempotent; never creates jobs)'),
 ('public.get_pdc_parts_eta_board()','decd9053241b3fe8ede99bd231ad98ec','r436','r436 (F47): board read of current parts ETAs'),
 ('public.set_pdc_parts_eta_sender_domain(text,boolean,text)','eb44898f34bca89afc1ee5e129a04928','r436','r436 (F47): admin edit of the parts ETA sender-domain allowlist');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('parts_eta_rpc_contract','F47','Parts ETA (r436): set_parts_eta / board read / allowlist functions are security definer and closed to anon; the three tables have RLS with no app-role writes; the sender allowlist holds broometoyota.com.au and pmgwa.com.au (exact, lower case); one current ETA per job + line + part; 9 dry-run contract cases (sender domain exact and case-insensitive, subdomain and non-Broome refused, unmatched never creates, invalid date/line/message id) return the right status and write nothing',
  $chk$WITH fn AS (
  SELECT count(*) FILTER (WHERE p.prosecdef) sd,
   bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE')) no_anon,
   bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')) auth_exec
  FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)'),
   to_regprocedure('public.get_pdc_parts_eta_board()'),to_regprocedure('public.set_pdc_parts_eta_sender_domain(text,boolean,text)'))
), tb AS (
  SELECT count(*) n, count(*) FILTER (WHERE c.relrowsecurity) rls,
   count(*) FILTER (WHERE has_table_privilege('authenticated',c.oid,'INSERT') OR has_table_privilege('authenticated',c.oid,'UPDATE')
     OR has_table_privilege('authenticated',c.oid,'DELETE') OR has_table_privilege('authenticated',c.oid,'TRUNCATE')
     OR has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('anon',c.oid,'INSERT')) writable,
   (SELECT count(*) FROM pg_policy po WHERE po.polrelid IN (to_regclass('public.pdc_parts_eta'),to_regclass('public.pdc_parts_eta_sender_domains'),to_regclass('public.pdc_parts_eta_audit')) AND po.polcmd<>'r') write_policies
  FROM pg_class c WHERE c.oid IN (to_regclass('public.pdc_parts_eta'),to_regclass('public.pdc_parts_eta_sender_domains'),to_regclass('public.pdc_parts_eta_audit'))
), dom AS (
  SELECT string_agg(domain,', ' ORDER BY domain) FILTER (WHERE active) allowed,
   count(*) FILTER (WHERE domain<>lower(btrim(domain)) OR domain !~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$') bad,
   bool_and(true) FILTER (WHERE domain IN ('broometoyota.com.au','pmgwa.com.au') AND active) seeded,
   count(*) FILTER (WHERE domain IN ('broometoyota.com.au','pmgwa.com.au') AND active) nseed
  FROM public.pdc_parts_eta_sender_domains
), cur AS (
  SELECT count(*) FILTER (WHERE NOT superseded) cur_rows, count(*) total,
   (SELECT count(*) FROM (SELECT 1 FROM public.pdc_parts_eta WHERE NOT superseded GROUP BY parts_job_id,coalesce(line_no,0),part_key HAVING count(*)>1) z) dup_keys,
   count(*) FILTER (WHERE NOT superseded AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.id=parts_job_id)) orphan
  FROM public.pdc_parts_eta
), t AS (SELECT (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date d),
cases(name, want_status, want_reason, r) AS (
  SELECT 'gmail sender','rejected_sender','sender_domain_not_allowed',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+7 FROM t),NULL,NULL,'r436-check-1','parts@gmail.com',true,NULL) UNION ALL
  SELECT 'subdomain sender','rejected_sender','sender_domain_not_allowed',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+7 FROM t),NULL,NULL,'r436-check-2','parts@mail.broometoyota.com.au',true,NULL) UNION ALL
  SELECT 'not an address','rejected_sender','sender_not_an_email_address',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+7 FROM t),NULL,NULL,'r436-check-3','broometoyota.com.au',true,NULL) UNION ALL
  SELECT 'mixed-case Broome sender','unmatched','stock_not_found',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+7 FROM t),NULL,NULL,'r436-check-4','Parts Desk <Parts.Desk@BroomeToyota.com.au>',true,NULL) UNION ALL
  SELECT 'PMG WA sender','unmatched','stock_not_found',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',3,'Check part',(SELECT d+7 FROM t),'P-12',NULL,'r436-check-5','parts@pmgwa.com.au',true,NULL) UNION ALL
  SELECT 'missing ETA','invalid','eta_date_missing',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',NULL,NULL,NULL,'r436-check-6','parts@broometoyota.com.au',true,NULL) UNION ALL
  SELECT 'ETA too far','invalid','eta_date_out_of_range',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+400 FROM t),NULL,NULL,'r436-check-7','parts@broometoyota.com.au',true,NULL) UNION ALL
  SELECT 'line 0','invalid','line_no_out_of_range',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',0,'Check part',(SELECT d+7 FROM t),NULL,NULL,'r436-check-8','parts@broometoyota.com.au',true,NULL) UNION ALL
  SELECT 'no message id','invalid','source_message_id_missing_or_too_long',public.set_parts_eta('R436-CHECK-NO-STOCK','J000000000',NULL,'Check part',(SELECT d+7 FROM t),NULL,NULL,'','parts@broometoyota.com.au',true,NULL)
), cs AS (
  SELECT count(*) n, count(*) FILTER (WHERE r->>'status'=want_status AND r->>'reason'=want_reason AND r->>'dry_run'='true' AND r->>'parts_eta_id' IS NULL
     AND r ?& ARRAY['status','parts_eta_id','job_id','line_no','previous_eta','eta_date','message']) good,
   string_agg(CASE WHEN NOT (r->>'status'=want_status AND r->>'reason'=want_reason AND r->>'dry_run'='true') THEN name||' -> '||coalesce(r->>'status','null')||'/'||coalesce(r->>'reason','null') END,'; ') bad
  FROM cases
)
SELECT (SELECT sd=3 AND no_anon AND auth_exec FROM fn) AND (SELECT n=3 AND rls=3 AND writable=0 AND write_policies=0 FROM tb)
   AND (SELECT bad=0 AND nseed=2 FROM dom) AND (SELECT dup_keys=0 AND orphan=0 FROM cur) AND (SELECT good=n AND n=9 FROM cs)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_parts_eta WHERE source_message_id LIKE 'r436-check-%') AS ok,
 'functions: '||(SELECT sd FROM fn)||'/3 security definer, anon blocked '||(SELECT no_anon FROM fn)||', authenticated can call '||(SELECT auth_exec FROM fn)
 ||'; tables: '||(SELECT rls FROM tb)||'/'||(SELECT n FROM tb)||' with RLS, '||(SELECT writable FROM tb)||' writable by app roles, '||(SELECT write_policies FROM tb)||' write policies'
 ||'; allowed sender domains: '||coalesce((SELECT allowed FROM dom),'none')||' (seed '||(SELECT nseed FROM dom)||'/2, malformed '||(SELECT bad FROM dom)||')'
 ||'; parts ETAs: '||(SELECT cur_rows FROM cur)||' current of '||(SELECT total FROM cur)||', duplicate current keys '||(SELECT dup_keys FROM cur)||', on missing jobs '||(SELECT orphan FROM cur)
 ||'; dry-run contract cases: '||(SELECT good FROM cs)||'/'||(SELECT n FROM cs)||' right'||coalesce(' (WRONG: '||(SELECT bad FROM cs)||')','') AS detail
$chk$,true,236,'r436');

DO $g$ BEGIN
 IF (SELECT count(*) FROM (VALUES ('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)','88d31cbd6ca5ddd372e3143d5f8c013f'),('public.get_pdc_parts_eta_board()','decd9053241b3fe8ede99bd231ad98ec'),('public.set_pdc_parts_eta_sender_domain(text,boolean,text)','eb44898f34bca89afc1ee5e129a04928')) e(s,m)
     JOIN pg_proc p ON p.oid=to_regprocedure(e.s) WHERE md5(p.prosrc)=e.m AND p.prosecdef AND p.proowner::regrole::text='postgres')<>3 THEN RAISE EXCEPTION 'r436: functions did not land as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract' AND added_in='r436')<>'0854a63912b8bbf0ed50635e535e4a0e' THEN RAISE EXCEPTION 'r436: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r436: clock tick changed'; END IF;
END $g$;
