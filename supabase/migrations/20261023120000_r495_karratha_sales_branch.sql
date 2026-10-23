-- r495 (F108): Karratha Toyota sales branch. PREPARED ONLY - NOT APPLIED (preview 22 Oct 2026; apply only after Craig approves).
-- Staging cdsmnqxtyyoeoznmbidd only. Craig 22 Oct 18:18: a Karratha Toyota entry in the Website drop-down showing the Pilbara / Karratha
--   Toyota Navision vehicles (dealer 14450) with the same rules as Broome Toyota Sales, by salesperson; PMB / PMG rules unchanged.
-- How: the existing Sales functions already read ctx->>'dealer_code' from pdc_sales_private.context(). context() now picks the branch:
--   * administrators: the X-PDC-Sales-Branch request header ('karratha' or '14450'); no header = Broome Toyota 37047 exactly as before;
--   * salespeople / linked controllers: always the branch of their own account_scopes row; a header naming another branch is refused.
--   'division' becomes the branch label ('Broome Toyota' for 37047, so Broome output is unchanged). Extra context keys (additive):
--   branch_key, finance_group, branch_roster.
-- New private tables: sales_branches (37047 Broome Toyota, 14450 Karratha Toyota), salesperson_branches (roster mapping).
--   Craig 23 Oct, go-live fix: CF and SL already exist as Broome salespeople. Update those emails and map the
--   same rows to 14450. Do not insert a second CF/SL. Their Broome account scope (37047) is left in place.
--   RK, JS, DB are inactive placeholders only when code, name and email are all free. No finance table.
-- Constraint change: account_scopes / vehicle_visibility / autocare_dispatches dealer_code CHECK (= '37047') widened to
--   IN ('37047','14450') so a Karratha salesperson, a Karratha "Hide from sales" and Karratha Autocare dispatch can be saved.
--   Every other 37047-only table (tracked orders, builds, accessories) is unchanged: those feeds are Broome-only.
-- Function changes (Broome output unchanged when there is no Karratha header):
--   context, visibility_source_snapshot, board_visibility_source_snapshot (Karratha matches only salespeople mapped to that
--   dealer, so Broome initials stay separate; head-office dealers 001234 / 002345 are excluded on dealer 14450),
--   get_builds / get_accessories (empty list outside Broome instead of an error), set_board_view_access (any open branch),
--   admin_accounts (shows branch), link_salesperson_scope_429 (salesperson mapped to exactly one branch is linked to it).
--   Finance functions are NOT replaced (Craig 23 Oct: skip Karratha finance and Port Hedland finance). Broome finance stays as it is.
-- New RPCs (administrators only, authenticated EXECUTE, not anon): public.assign_pdc_sales_branch_access(user_role_id, salesperson_id,
--   dealer_code), public.set_pdc_salesperson_branch(salesperson_id, dealer_code, enabled).
-- Writes no vehicle, job, booking, Navision, finance or account-scope row. Updates the existing CF and SL emails
--   and maps those rows to 14450. Inserts RK/JS/DB only when that code, name and email are all free.
-- Pins: 5 updated, 7 new (+7). Finance pins are not moved. Check sales_branch_495 (sort 295, F108).
-- File timestamp 20261023120000 sorts after r508 (20261023113000) already on main. Family name stays *_r495_karratha_sales_branch.sql.
-- Body is LF only. Undo: supabase/rollbacks/20261023120000_r495_karratha_sales_branch.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r495: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r495: staging only'; END IF;
 PERFORM set_config('pdc.r495_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r495_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r495_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r495_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r495: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF to_regclass('pdc_sales_private.sales_branches') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r495') THEN RAISE EXCEPTION 'r495: already applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.context()')) IS DISTINCT FROM 'f46074748e6fcb748b97b072d1160b4e'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.context()') IS DISTINCT FROM 'f46074748e6fcb748b97b072d1160b4er432' THEN RAISE EXCEPTION 'r495: pdc_sales_private.context() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.visibility_source_snapshot(boolean)') IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14efr420' THEN RAISE EXCEPTION 'r495: pdc_sales_private.visibility_source_snapshot(boolean) changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.board_visibility_source_snapshot(boolean)') IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4fr420' THEN RAISE EXCEPTION 'r495: pdc_sales_private.board_visibility_source_snapshot(boolean) changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.crm_finance_refs()')) IS DISTINCT FROM '4aaf4702df0aa0515485046e05892d0b'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.crm_finance_refs()') IS DISTINCT FROM '4aaf4702df0aa0515485046e05892d0br420' THEN RAISE EXCEPTION 'r495: pdc_sales_private.crm_finance_refs() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_pipeline()')) IS DISTINCT FROM '372dcae199c750594923e2269f661e43'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.finance_pipeline()') IS DISTINCT FROM '372dcae199c750594923e2269f661e43r435' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_pipeline() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '6249e21543ac7caf096e3175c81406c4'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.get_accessories()') IS DISTINCT FROM '6249e21543ac7caf096e3175c81406c4r427' THEN RAISE EXCEPTION 'r495: pdc_sales_private.get_accessories() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)')) IS DISTINCT FROM '280d0afd36816510053cd6ea8fe154b1'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)') IS DISTINCT FROM '280d0afd36816510053cd6ea8fe154b1r429b' THEN RAISE EXCEPTION 'r495: pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()')) IS DISTINCT FROM 'b618db56602ab648872951306a5ad273'
    OR (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_sales_private.finance_visibility_check_435()') IS DISTINCT FROM 'b618db56602ab648872951306a5ad273r435' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_visibility_check_435() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_builds()')) IS DISTINCT FROM '2c23751b84a788ae49eb58169ed89159' THEN RAISE EXCEPTION 'r495: pdc_sales_private.get_builds() changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer)')) IS DISTINCT FROM 'bbeb49580363dcf5acc4dfac35d1e226' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer) changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.set_board_view_access(uuid,boolean)')) IS DISTINCT FROM '1338c8ccee286f34ba7e60ff061f380b' THEN RAISE EXCEPTION 'r495: pdc_sales_private.set_board_view_access(uuid,boolean) changed since this release was prepared'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.admin_accounts()')) IS DISTINCT FROM '42649fa165a7a40e625e15a1cd0051ab' THEN RAISE EXCEPTION 'r495: pdc_sales_private.admin_accounts() changed since this release was prepared'; END IF;
 IF to_regclass('pdc_sales_private.sales_branches') IS NOT NULL OR to_regclass('pdc_sales_private.salesperson_branches') IS NOT NULL OR to_regclass('pdc_sales_private.finance_application_branches') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r495') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495' OR added_in='r495') THEN RAISE EXCEPTION 'r495: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=295 OR fault_id='F108') THEN RAISE EXCEPTION 'r495: sort_order 295 / F108 taken'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='account_scopes_dealer_code_check' AND conrelid='pdc_sales_private.account_scopes'::regclass) IS DISTINCT FROM 'CHECK ((dealer_code = ''37047''::text))'
    OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='vehicle_visibility_dealer_code_check' AND conrelid='pdc_sales_private.vehicle_visibility'::regclass) IS DISTINCT FROM 'CHECK ((dealer_code = ''37047''::text))'
    OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='autocare_dispatches_dealer_code_check' AND conrelid='pdc_sales_private.autocare_dispatches'::regclass) IS DISTINCT FROM 'CHECK ((dealer_code = ''37047''::text))' THEN RAISE EXCEPTION 'r495: dealer checks are not as prepared'; END IF;
 PERFORM set_config('pdc.r495_scopes',(SELECT md5(coalesce(string_agg(user_role_id::text||salesperson_id::text||dealer_code||can_view_all_salespeople::text,',' ORDER BY user_role_id),'')) FROM pdc_sales_private.account_scopes),true);
 PERFORM set_config('pdc.r495_fin',(SELECT md5(coalesce(string_agg(id::text||version::text,',' ORDER BY id),'')) FROM pdc_sales_private.finance_applications),true);
END $g$;

CREATE TABLE pdc_sales_private.sales_branches(
 dealer_code text PRIMARY KEY CHECK (dealer_code ~ '^[0-9]{4,6}$'),
 branch_key text NOT NULL UNIQUE CHECK (branch_key ~ '^[a-z]{3,20}$'),
 label text NOT NULL CHECK (length(label) BETWEEN 3 AND 60),
 finance_group text NOT NULL CHECK (length(finance_group) BETWEEN 3 AND 40),
 active boolean NOT NULL DEFAULT true,
 sort_order integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO pdc_sales_private.sales_branches(dealer_code,branch_key,label,finance_group,active,sort_order) VALUES
 ('37047','broome','Broome Toyota','Broome',true,10),
 ('14450','karratha','Karratha Toyota','Later',true,20);
CREATE TABLE pdc_sales_private.salesperson_branches(
 salesperson_id uuid NOT NULL REFERENCES public.salespeople(id) ON DELETE RESTRICT,
 dealer_code text NOT NULL REFERENCES pdc_sales_private.sales_branches(dealer_code),
 enabled boolean NOT NULL DEFAULT true,
 -- Craig 23 Oct: the 8-digit Navision salesperson number on the feed (CF 19901126). Not a second code.
 navision_number text CHECK (navision_number IS NULL OR navision_number ~ '^[0-9]{8}$'),
 updated_by uuid,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (salesperson_id,dealer_code));
ALTER TABLE pdc_sales_private.sales_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.salesperson_branches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_sales_private.sales_branches, pdc_sales_private.salesperson_branches FROM PUBLIC, anon, authenticated;

-- Craig 23 Oct go-live fix. Staging already has these Broome salespeople (unique code and name), so a second
-- insert cannot land: Clint Franklin CF clint.franklin@pmgwa.com.au, Scott Lovett SL scott.lovett@pmgwa.com.au
-- (SL already has account_scopes dealer 37047). Update those emails and map the same rows to Karratha 14450.
-- Do not insert another CF or SL. Do not change account_scopes: a Broome 37047 scope stays, so they remain
-- Broome-capable, and the new salesperson_branches row is what puts them on the Karratha roster. Not Karratha-only.
-- No 37047 salesperson_branches row is added. Broome still matches any active initials; a second mapping would make
-- a future Approve see two branches and link a new account to Broome. set_pdc_salesperson_branch is the admin RPC
-- for this table, but it needs an administrator session and does not store navision_number, so this seed writes
-- salesperson_branches directly (same enabled 14450 row, plus the Navision number).
-- RK / JS / DB: inactive placeholders only when that code, that name and that email are all free. A collision is
-- skipped (NOTICE) and documented; it does not fail the migration.
DO $seed$
DECLARE cf_id uuid; sl_id uuid; cf_n int; sl_n int;
BEGIN
 SELECT count(*) INTO cf_n FROM public.salespeople s
  WHERE upper(btrim(coalesce(s.code,'')))='CF' OR lower(btrim(coalesce(s.name,'')))='clint franklin';
 IF cf_n<>1 OR NOT EXISTS (SELECT 1 FROM public.salespeople s
    WHERE upper(btrim(s.code))='CF' AND lower(btrim(s.name))='clint franklin' AND s.active) THEN
  RAISE EXCEPTION 'r495: expected exactly one active salesperson Clint Franklin (code CF). Found % row(s) with that code or name.', cf_n;
 END IF;
 SELECT s.id INTO cf_id FROM public.salespeople s
  WHERE upper(btrim(s.code))='CF' AND lower(btrim(s.name))='clint franklin' AND s.active;
 IF EXISTS (SELECT 1 FROM public.salespeople s WHERE s.id<>cf_id AND lower(btrim(coalesce(s.email,'')))='clint.franklin@karrathatoyota.com.au') THEN
  RAISE EXCEPTION 'r495: clint.franklin@karrathatoyota.com.au already belongs to a different salesperson.';
 END IF;
 UPDATE public.salespeople SET email='clint.franklin@karrathatoyota.com.au' WHERE id=cf_id;
 INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,navision_number)
 VALUES (cf_id,'14450',true,'19901126')
 ON CONFLICT (salesperson_id,dealer_code) DO UPDATE
 SET enabled=true, navision_number=excluded.navision_number, updated_at=clock_timestamp()
 WHERE salesperson_branches.salesperson_id=excluded.salesperson_id AND salesperson_branches.dealer_code=excluded.dealer_code;

 SELECT count(*) INTO sl_n FROM public.salespeople s
  WHERE upper(btrim(coalesce(s.code,'')))='SL' OR lower(btrim(coalesce(s.name,'')))='scott lovett';
 IF sl_n<>1 OR NOT EXISTS (SELECT 1 FROM public.salespeople s
    WHERE upper(btrim(s.code))='SL' AND lower(btrim(s.name))='scott lovett' AND s.active) THEN
  RAISE EXCEPTION 'r495: expected exactly one active salesperson Scott Lovett (code SL). Found % row(s) with that code or name.', sl_n;
 END IF;
 SELECT s.id INTO sl_id FROM public.salespeople s
  WHERE upper(btrim(s.code))='SL' AND lower(btrim(s.name))='scott lovett' AND s.active;
 IF EXISTS (SELECT 1 FROM public.salespeople s WHERE s.id<>sl_id AND lower(btrim(coalesce(s.email,'')))='scott@karrathatoyota.com.au') THEN
  RAISE EXCEPTION 'r495: scott@karrathatoyota.com.au already belongs to a different salesperson.';
 END IF;
 UPDATE public.salespeople SET email='scott@karrathatoyota.com.au' WHERE id=sl_id;
 INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,navision_number)
 VALUES (sl_id,'14450',true,'19660914')
 ON CONFLICT (salesperson_id,dealer_code) DO UPDATE
 SET enabled=true, navision_number=excluded.navision_number, updated_at=clock_timestamp()
 WHERE salesperson_branches.salesperson_id=excluded.salesperson_id AND salesperson_branches.dealer_code=excluded.dealer_code;

 IF NOT EXISTS (SELECT 1 FROM public.salespeople s
    WHERE upper(btrim(coalesce(s.code,'')))='RK' OR lower(btrim(coalesce(s.name,'')))='rebecca kingma'
       OR lower(btrim(coalesce(s.email,'')))='rebecca.kingma@pmgwa.com.au') THEN
  INSERT INTO public.salespeople(id,name,email,code,active,sort_order) VALUES
   ('c4950003-0000-4000-a000-000000000003','Rebecca Kingma','rebecca.kingma@pmgwa.com.au','RK',false,60);
  INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,navision_number) VALUES
   ('c4950003-0000-4000-a000-000000000003','14450',false,NULL);
  RAISE NOTICE 'r495: inserted inactive placeholder RK Rebecca Kingma';
 ELSE
  RAISE NOTICE 'r495: skipped RK Rebecca Kingma; code, name or email already exists';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.salespeople s
    WHERE upper(btrim(coalesce(s.code,'')))='JS' OR lower(btrim(coalesce(s.name,'')))='joel sutton'
       OR lower(btrim(coalesce(s.email,'')))='joel.sutton@pmgwa.com.au') THEN
  INSERT INTO public.salespeople(id,name,email,code,active,sort_order) VALUES
   ('c4950004-0000-4000-a000-000000000004','Joel Sutton','joel.sutton@pmgwa.com.au','JS',false,61);
  INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,navision_number) VALUES
   ('c4950004-0000-4000-a000-000000000004','14450',false,NULL);
  RAISE NOTICE 'r495: inserted inactive placeholder JS Joel Sutton';
 ELSE
  RAISE NOTICE 'r495: skipped JS Joel Sutton; code, name or email already exists';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.salespeople s
    WHERE upper(btrim(coalesce(s.code,'')))='DB' OR lower(btrim(coalesce(s.name,'')))='damien bowden'
       OR lower(btrim(coalesce(s.email,'')))='damien.bowden@pmgwa.com.au') THEN
  INSERT INTO public.salespeople(id,name,email,code,active,sort_order) VALUES
   ('c4950005-0000-4000-a000-000000000005','Damien Bowden','damien.bowden@pmgwa.com.au','DB',false,62);
  INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,navision_number) VALUES
   ('c4950005-0000-4000-a000-000000000005','14450',false,NULL);
  RAISE NOTICE 'r495: inserted inactive placeholder DB Damien Bowden';
 ELSE
  RAISE NOTICE 'r495: skipped DB Damien Bowden; code, name or email already exists';
 END IF;
END $seed$;


ALTER TABLE pdc_sales_private.account_scopes DROP CONSTRAINT account_scopes_dealer_code_check;
ALTER TABLE pdc_sales_private.account_scopes ADD CONSTRAINT account_scopes_dealer_code_check CHECK (dealer_code IN ('37047','14450'));
ALTER TABLE pdc_sales_private.vehicle_visibility DROP CONSTRAINT vehicle_visibility_dealer_code_check;
ALTER TABLE pdc_sales_private.vehicle_visibility ADD CONSTRAINT vehicle_visibility_dealer_code_check CHECK (dealer_code IN ('37047','14450'));
ALTER TABLE pdc_sales_private.autocare_dispatches DROP CONSTRAINT autocare_dispatches_dealer_code_check;
ALTER TABLE pdc_sales_private.autocare_dispatches ADD CONSTRAINT autocare_dispatches_dealer_code_check CHECK (dealer_code IN ('37047','14450'));

CREATE FUNCTION pdc_sales_private.parse_branch_header_495(p_headers text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v text; d text;
BEGIN
 -- r495 (F108): p_headers is PostgREST's request.headers JSON (header names lower case). Returns the dealer code of the open
 -- sales branch named by x-pdc-sales-branch (its key such as 'karratha', or its dealer code), NULL when no header is sent.
 IF p_headers IS NULL OR btrim(p_headers)='' THEN RETURN NULL; END IF;
 BEGIN
  v:=lower(btrim(coalesce(p_headers::jsonb->>'x-pdc-sales-branch','')));
 EXCEPTION WHEN others THEN RETURN NULL;
 END;
 IF v='' THEN RETURN NULL; END IF;
 SELECT b.dealer_code INTO d FROM pdc_sales_private.sales_branches b WHERE b.active AND (b.branch_key=v OR b.dealer_code=v);
 IF d IS NULL THEN RAISE EXCEPTION 'Unknown sales branch' USING errcode='22023'; END IF;
 RETURN d;
END $function$;

CREATE FUNCTION pdc_sales_private.requested_branch_495()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ SELECT pdc_sales_private.parse_branch_header_495(current_setting('request.headers',true)) $function$;

CREATE FUNCTION pdc_sales_private.branch_info_495(p_dealer_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r495 (F108): extra Sales context keys. branch_roster is active salespeople mapped and enabled on this dealer (CF and SL; inactive RK/JS/DB stay off).
 SELECT jsonb_build_object('branch_key',b.branch_key,'finance_group',b.finance_group,
  'branch_roster',(SELECT coalesce(jsonb_agg(s.code ORDER BY s.sort_order,s.code),'[]'::jsonb) FROM pdc_sales_private.salesperson_branches m
   JOIN public.salespeople s ON s.id=m.salesperson_id AND s.active AND coalesce(s.code,'')<>'' WHERE m.dealer_code=b.dealer_code AND m.enabled))
 FROM pdc_sales_private.sales_branches b WHERE b.dealer_code=p_dealer_code $function$;

CREATE FUNCTION pdc_sales_private.assign_branch_access_495(p_user_role_id uuid, p_salesperson_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE r public.pdc_user_roles; br pdc_sales_private.sales_branches; before_scope jsonb;
BEGIN
 -- r495 (F108): administrator gives one account Sales access as one salesperson in one branch (Broome 37047 or Karratha 14450).
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 SELECT * INTO br FROM pdc_sales_private.sales_branches WHERE dealer_code=p_dealer_code AND active;
 IF br.dealer_code IS NULL THEN RAISE EXCEPTION 'Choose an open sales branch'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles WHERE id=p_user_role_id FOR UPDATE;
 IF r.id IS NULL OR r.auth_user_id IS NULL OR
  NOT (r.account_status='pending' OR (r.account_status='approved' AND r.role::text='salesperson')) THEN
  RAISE EXCEPTION 'Choose a pending registration or an approved salesperson';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.salespeople WHERE id=p_salesperson_id AND active) THEN RAISE EXCEPTION 'Active salesperson required'; END IF;
 SELECT to_jsonb(a) INTO before_scope FROM pdc_sales_private.account_scopes a WHERE user_role_id=r.id;
 IF r.account_status='pending' THEN PERFORM public.admin_approve_user(r.email,'salesperson'::public.pdc_role,br.label||' salesperson access'); END IF;
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by,dealer_code)
 VALUES(r.id,p_salesperson_id,auth.uid(),br.dealer_code) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,dealer_code=excluded.dealer_code,assigned_by=excluded.assigned_by,updated_at=now()
 WHERE account_scopes.user_role_id=excluded.user_role_id;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  before_scope,jsonb_build_object('salesperson_id',p_salesperson_id,'dealer_code',br.dealer_code),jsonb_build_object('operation','assign_pdc_sales_branch_access','release','r495'));
 RETURN jsonb_build_object('ok',true,'dealer_code',br.dealer_code,'division',br.label);
END $function$;

CREATE FUNCTION pdc_sales_private.set_salesperson_branch_495(p_salesperson_id uuid, p_dealer_code text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE before_row jsonb; after_row jsonb;
BEGIN
 -- r495 (F108): administrator maps a salesperson record to a sales branch roster (switch off with p_enabled=false; never deleted).
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'Choose enabled or disabled'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.sales_branches WHERE dealer_code=p_dealer_code AND active) THEN RAISE EXCEPTION 'Choose an open sales branch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.salespeople WHERE id=p_salesperson_id AND active) THEN RAISE EXCEPTION 'Active salesperson required'; END IF;
 SELECT to_jsonb(m) INTO before_row FROM pdc_sales_private.salesperson_branches m WHERE salesperson_id=p_salesperson_id AND dealer_code=p_dealer_code FOR UPDATE;
 INSERT INTO pdc_sales_private.salesperson_branches(salesperson_id,dealer_code,enabled,updated_by)
 VALUES(p_salesperson_id,p_dealer_code,p_enabled,auth.uid()) ON CONFLICT(salesperson_id,dealer_code) DO UPDATE
 SET enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=clock_timestamp()
 WHERE salesperson_branches.salesperson_id=excluded.salesperson_id AND salesperson_branches.dealer_code=excluded.dealer_code RETURNING to_jsonb(salesperson_branches) INTO after_row;
 PERFORM public.audit_pdc_event('reference_change'::public.audit_action,'pdc_sales_private.salesperson_branches',p_salesperson_id,NULL,
  before_row,after_row,jsonb_build_object('operation','set_pdc_salesperson_branch','release','r495'));
 RETURN jsonb_build_object('ok',true,'salesperson_id',p_salesperson_id,'dealer_code',p_dealer_code,'enabled',p_enabled);
END $function$;

CREATE FUNCTION public.assign_pdc_sales_branch_access(p_user_role_id uuid, p_salesperson_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ SELECT pdc_sales_private.assign_branch_access_495(p_user_role_id,p_salesperson_id,p_dealer_code) $function$;

CREATE FUNCTION public.set_pdc_salesperson_branch(p_salesperson_id uuid, p_dealer_code text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$ SELECT pdc_sales_private.set_salesperson_branch_495(p_salesperson_id,p_dealer_code,p_enabled) $function$;

REVOKE ALL ON FUNCTION pdc_sales_private.parse_branch_header_495(text), pdc_sales_private.requested_branch_495(), pdc_sales_private.branch_info_495(text),
 pdc_sales_private.assign_branch_access_495(uuid,uuid,text), pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean),
 public.assign_pdc_sales_branch_access(uuid,uuid,text), public.set_pdc_salesperson_branch(uuid,text,boolean) FROM PUBLIC, anon, authenticated;
-- The public wrappers are plain SQL (run as the caller), so the caller needs EXECUTE on the two admin functions they call.
-- Both check context() role = administrator before anything else (SQLSTATE 42501 otherwise), the same pattern as
-- pdc_sales_private.assign_access / set_accessory_line_delay. The three branch helpers stay closed.
GRANT EXECUTE ON FUNCTION public.assign_pdc_sales_branch_access(uuid,uuid,text), public.set_pdc_salesperson_branch(uuid,text,boolean),
 pdc_sales_private.assign_branch_access_495(uuid,uuid,text), pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION pdc_sales_private.context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE r public.pdc_user_roles; sp public.salespeople; scope pdc_sales_private.account_scopes; br pdc_sales_private.sales_branches;
 req text:=pdc_sales_private.requested_branch_495();
BEGIN
 -- r495 (F108): the Sales site serves one branch per request. Administrators choose it with the X-PDC-Sales-Branch header
 -- (no header = Broome Toyota 37047, as before); a salesperson always gets the branch of their own account scope and a header
 -- naming another branch is refused. division is the branch label ('Broome Toyota' for 37047, unchanged).
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 SELECT * INTO r FROM public.pdc_user_roles
 WHERE email=lower(coalesce(auth.jwt()->>'email','')) AND active AND account_status='approved'
 AND (auth_user_id=auth.uid() OR auth_user_id IS NULL);
 IF r.role::text='administrator' THEN
  SELECT * INTO br FROM pdc_sales_private.sales_branches b WHERE b.dealer_code=coalesce(req,'37047') AND b.active;
  IF br.dealer_code IS NULL THEN RAISE EXCEPTION 'This sales branch is not open' USING errcode='42501'; END IF;
  RETURN jsonb_build_object('role','administrator','display_name',coalesce(r.full_name,r.display_name,r.email),
   'dealer_code',br.dealer_code,'division',br.label,'can_view_all_salespeople',true)||pdc_sales_private.branch_info_495(br.dealer_code);
 END IF;
 -- r432 (F43): a controller (operator) whose account has a Sales record link uses Sales as that salesperson, with the
 -- same scope as a salesperson (own vehicles unless can_view_all_salespeople). It is never treated as administrator here.
 IF coalesce(r.role::text,'') NOT IN ('salesperson','operator') OR r.auth_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Salesperson access required' USING errcode='42501';
 END IF;
 SELECT * INTO scope FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 SELECT * INTO sp FROM public.salespeople WHERE id=scope.salesperson_id AND active;
 IF sp.id IS NULL AND r.role::text='operator' THEN RAISE EXCEPTION 'Salesperson access required' USING errcode='42501'; END IF;
 IF sp.id IS NULL THEN RAISE EXCEPTION 'Ask an administrator to assign your salesperson access' USING errcode='42501'; END IF;
 SELECT * INTO br FROM pdc_sales_private.sales_branches b WHERE b.dealer_code=scope.dealer_code AND b.active;
 IF br.dealer_code IS NULL THEN RAISE EXCEPTION 'Your sales branch is not open yet' USING errcode='42501'; END IF;
 IF req IS NOT NULL AND req<>br.dealer_code THEN RAISE EXCEPTION 'Your Sales access is for %', br.label USING errcode='42501'; END IF;
 RETURN jsonb_build_object('role','salesperson','display_name',sp.name,'salesperson_code',sp.code,
  'salesperson_id',sp.id,'dealer_code',scope.dealer_code,'division',br.label,
  'can_view_all_salespeople',scope.can_view_all_salespeople,'account_role',r.role::text)||pdc_sales_private.branch_info_495(br.dealer_code);
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.visibility_source_snapshot(p_hidden boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Sales-only order identity follows the exact dealer + Toyota order, never stock or customer.
 -- Only the current successful Navision dealer snapshot supplies sales vehicles.
 WITH latest_scope AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b
  WHERE b.source_system='microsoft_navision' AND b.dealer_code=ctx->>'dealer_code'
    AND b.status='applied' AND b.rolled_back_at IS NULL
  ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key
  FROM public.navision_backend_records n JOIN latest_scope applied ON applied.id=n.last_seen_batch_id WHERE source_system='microsoft_navision' AND dealer_code=ctx->>'dealer_code' AND n.is_current AND n.record_status='current'

 ), counted AS (
  SELECT n.*,count(*) OVER (PARTITION BY dealer_code,order_key) AS order_matches FROM source_rows n
 ), feed_values AS (
  SELECT coalesce(o.id,n.id) AS tracking_id,n.id,n.canonical_vehicle_id,n.dealer_code,n.order_key,
   n.normalized_data,n.updated_at,n.created_at,n.is_current,n.record_status,n.order_matches>1 AS identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o
   ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 ), feed AS (
  SELECT n.*,lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM feed_values n
 )
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'identity_conflict',n.identity_conflict,'source_current',n.is_current,'first_seen_at',n.created_at,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
  'sales_hidden',coalesce(h.hidden,false),'sales_visibility_version',coalesce(h.version,0),'sales_visibility_updated_at',h.changed_at,
  'identity_status',CASE WHEN v.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END,
  'division',ctx->>'division','dealer_code',n.dealer_code,'cosi',n.cosi_status IN ('yes','true','1'),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''),
  'order',coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'),v.toyota_order_number,''),
  'production_month',coalesce(n.normalized_data->>'prodMth',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),v.customer_name,n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.normalized_data->>'vehicle',''),v.vehicle_description,v.model,''),
  'colour',coalesce(n.normalized_data->>'colourDescription',n.normalized_data->>'colour',''),
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE pdc_sales_private.source_vin(n.normalized_data) END,
  'suffix',coalesce(n.normalized_data->>'suffixDescription',n.normalized_data->>'suffix',''),
  'trim',coalesce(n.normalized_data->>'trimDescription',n.normalized_data->>'trim','')
 )||jsonb_build_object(
  'sales_type',coalesce(n.normalized_data->>'salesType',''),
  'customer_category',coalesce(n.normalized_data->>'dealerCustomerCategory',''),
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'location_status',coalesce(n.normalized_data->>'navisionLocationStatus',''),
  'kewdale_eta',coalesce(nullif(n.normalized_data->>'navisionKewdaleEta',''),v.eta_to_kewdale::text,''),
  'dealer_eta',coalesce(n.normalized_data->>'navisionEtaAtDealerBB',''),
  'port_plant_eta',coalesce(n.normalized_data->>'navisionPortPlantEta',''),
  'pmb_arrival_date',v.date_to_pmb,'dealer_delivered_date',v.delivered_to_dealer_date,
  'transport_booked_at',v.rft_transport_booked_at,'collected_at',v.rft_collected_at,
  'bay_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'stage',s.display_name,'bay',b.display_name,'status',w.status,
   'scheduled_start_at',w.scheduled_start_at,'scheduled_end_at',w.scheduled_end_at,
   'actual_start_at',w.actual_start_at,'actual_end_at',w.actual_end_at
  ) ORDER BY w.scheduled_start_at,w.id) FROM public.workshop_bookings w
   JOIN public.workshop_stages s ON s.id=w.stage_id LEFT JOIN public.workshop_bays b ON b.id=w.bay_id
   WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined),'[]'::jsonb),
  'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
  'jita',n.normalized_data->'jitaPartsOrdered',
  'tint',v.sales_tint_raised,'build_po',v.sales_build_po_raised,'build_complete',v.sales_build_complete,
  'tray_ordered',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_ordered) ELSE n.normalized_data->'trayOrdered' END,
  'tray_complete',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_complete) ELSE n.normalized_data->'trayFitmentComplete' END,
  'pmb_location',coalesce(nullif(v.location_override,''),v.current_location),
  'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,
  'key_number',v.key_number,'job_card',v.job_card_number,
  'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,
  'navision_updated_at',n.updated_at,'pmb_updated_at',v.updated_at
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO latest,rows
 FROM feed n
 LEFT JOIN LATERAL (SELECT x.* FROM pdc_sales_private.vehicle_visibility x
  WHERE x.tracking_id=n.tracking_id OR (NOT n.identity_conflict AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
  ORDER BY (x.tracking_id=n.tracking_id) DESC LIMIT 1) h ON true
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
  -- r495 Craig 23 Oct: Broome (37047) still matches any active salesperson by initials. Karratha matches only people mapped to that branch, so a Broome AW is not Karratha's AW.
  AND (ctx->>'dealer_code'='37047' OR EXISTS (SELECT 1 FROM pdc_sales_private.salesperson_branches mb WHERE mb.salesperson_id=source_sp.id AND mb.dealer_code=ctx->>'dealer_code' AND mb.enabled))
 WHERE n.cosi_status IN ('yes','true','1')
 AND (p_hidden IS NULL OR coalesce(h.hidden,false)=p_hidden)
 -- r495 Craig 23 Oct: the Karratha Sales tab does not list Toyota head-office dealers 001234 / 002345 (default). Broome's read is unchanged.
 AND NOT (ctx->>'dealer_code'='14450' AND ltrim(coalesce(n.dealer_code,''),'0') IN ('1234','2345'))
 -- r420 (F35): a feed row stays on Sales whatever its PMB state; a deleted PMB vehicle reads as awaiting PMB link.
 AND (ctx->>'role'='administrator' OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.board_visibility_source_snapshot(p_hidden boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); rows jsonb; latest timestamptz;
BEGIN
 -- Sales-only order identity follows the exact dealer + Toyota order, never stock or customer.
 -- Only the current successful Navision dealer snapshot supplies sales vehicles.
 WITH latest_scope AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b
  WHERE b.source_system='microsoft_navision' AND b.dealer_code=ctx->>'dealer_code'
    AND b.status='applied' AND b.rolled_back_at IS NULL
  ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*, upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) AS order_key
  FROM public.navision_backend_records n JOIN latest_scope applied ON applied.id=n.last_seen_batch_id WHERE source_system='microsoft_navision' AND dealer_code=ctx->>'dealer_code' AND n.is_current AND n.record_status='current'

 ), counted AS (
  SELECT n.*,count(*) OVER (PARTITION BY dealer_code,order_key) AS order_matches FROM source_rows n
 ), feed_values AS (
  SELECT coalesce(o.id,n.id) AS tracking_id,n.id,n.canonical_vehicle_id,n.dealer_code,n.order_key,
   n.normalized_data,n.updated_at,n.created_at,n.is_current,n.record_status,n.order_matches>1 AS identity_conflict
  FROM counted n LEFT JOIN pdc_sales_private.tracked_orders o
   ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 ), feed AS (
  SELECT n.*,lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi'
   ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) AS cosi_status
  FROM feed_values n
 )
 SELECT max(n.updated_at),coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',n.tracking_id,'navision_record_id',n.id,'identity_conflict',n.identity_conflict,'source_current',n.is_current,'first_seen_at',n.created_at,'canonical_vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,
  'sales_hidden',coalesce(h.hidden,false),'sales_visibility_version',coalesce(h.version,0),'sales_visibility_updated_at',h.changed_at,
  'identity_status',CASE WHEN v.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END,
  'division',ctx->>'division','dealer_code',n.dealer_code,'cosi',n.cosi_status IN ('yes','true','1'),
  'salesperson_code',CASE WHEN v.salesperson_manual_override THEN sp.code ELSE source_sp.code END,
  'salesperson_name',CASE WHEN v.salesperson_manual_override THEN sp.name ELSE source_sp.name END,
  'stock',coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,''),
  'order',coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'),v.toyota_order_number,''),
  'production_month',coalesce(n.normalized_data->>'prodMth',''),
  'client',coalesce(nullif(n.normalized_data->>'client',''),v.customer_name,n.normalized_data->>'toyotaCustomer',''),
  'vehicle',coalesce(nullif(n.normalized_data->>'vehicle',''),v.vehicle_description,v.model,''),
  'colour',coalesce(n.normalized_data->>'colourDescription',n.normalized_data->>'colour',''),
  'vin',CASE WHEN public.is_valid_vehicle_vin(v.vin) THEN v.vin ELSE pdc_sales_private.source_vin(n.normalized_data) END,
  'suffix',coalesce(n.normalized_data->>'suffixDescription',n.normalized_data->>'suffix',''),
  'trim',coalesce(n.normalized_data->>'trimDescription',n.normalized_data->>'trim','')
 )||jsonb_build_object(
  'sales_type',coalesce(n.normalized_data->>'salesType',''),
  'customer_category',coalesce(n.normalized_data->>'dealerCustomerCategory',''),
  'toyota_status',coalesce(n.normalized_data->>'navisionSubLocationDescription',n.normalized_data->>'toyotaStatus',''),
  'location_status',coalesce(n.normalized_data->>'navisionLocationStatus',''),
  'kewdale_eta',coalesce(nullif(n.normalized_data->>'navisionKewdaleEta',''),v.eta_to_kewdale::text,''),
  'dealer_eta',coalesce(n.normalized_data->>'navisionEtaAtDealerBB',''),
  'port_plant_eta',coalesce(n.normalized_data->>'navisionPortPlantEta',''),
  'pmb_arrival_date',v.date_to_pmb,'dealer_delivered_date',v.delivered_to_dealer_date,
  'transport_booked_at',v.rft_transport_booked_at,'collected_at',v.rft_collected_at,
  'bay_bookings',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'stage',s.display_name,'bay',b.display_name,'status',w.status,
   'scheduled_start_at',w.scheduled_start_at,'scheduled_end_at',w.scheduled_end_at,
   'actual_start_at',w.actual_start_at,'actual_end_at',w.actual_end_at
  ) ORDER BY w.scheduled_start_at,w.id) FROM public.workshop_bookings w
   JOIN public.workshop_stages s ON s.id=w.stage_id LEFT JOIN public.workshop_bays b ON b.id=w.bay_id
   WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined),'[]'::jsonb),
  'navision_notes',coalesce(n.normalized_data->>'navisionDealerComments',''),
  'jita',n.normalized_data->'jitaPartsOrdered',
  'tint',v.sales_tint_raised,'build_po',v.sales_build_po_raised,'build_complete',v.sales_build_complete,
  'tray_ordered',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_ordered) ELSE n.normalized_data->'trayOrdered' END,
  'tray_complete',CASE WHEN v.id IS NOT NULL THEN to_jsonb(v.sales_tray_complete) ELSE n.normalized_data->'trayFitmentComplete' END,
  'pmb_location',coalesce(nullif(v.location_override,''),v.current_location),
  'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,
  'key_number',v.key_number,'job_card',v.job_card_number,
  'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,
  'navision_updated_at',n.updated_at,'pmb_updated_at',v.updated_at
 ) ORDER BY n.tracking_id),'[]'::jsonb) INTO latest,rows
 FROM feed n
 LEFT JOIN LATERAL (SELECT x.* FROM pdc_sales_private.vehicle_visibility x
  WHERE x.tracking_id=n.tracking_id OR (NOT n.identity_conflict AND x.dealer_code=n.dealer_code AND x.order_key=n.order_key)
  ORDER BY (x.tracking_id=n.tracking_id) DESC LIMIT 1) h ON true
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN public.salespeople sp ON sp.id=v.salesperson_id
 LEFT JOIN public.salespeople source_sp ON source_sp.active AND upper(source_sp.code)=upper(split_part(btrim(coalesce(
  nullif(btrim(public.navision_original_column_value(n.normalized_data,'Salesperson')),''),
  nullif(n.normalized_data->>'salesperson',''),nullif(n.normalized_data->>'consultant',''),n.normalized_data->>'owner','')),' ',1))
  -- r495 Craig 23 Oct: Broome (37047) still matches any active salesperson by initials. Karratha matches only people mapped to that branch, so a Broome AW is not Karratha's AW.
  AND (ctx->>'dealer_code'='37047' OR EXISTS (SELECT 1 FROM pdc_sales_private.salesperson_branches mb WHERE mb.salesperson_id=source_sp.id AND mb.dealer_code=ctx->>'dealer_code' AND mb.enabled))
 WHERE n.cosi_status IN ('yes','true','1')
 AND (p_hidden IS NULL OR coalesce(h.hidden,false)=p_hidden)
 -- r495 Craig 23 Oct: the Karratha Sales tab does not list Toyota head-office dealers 001234 / 002345 (default). Broome's read is unchanged.
 AND NOT (ctx->>'dealer_code'='14450' AND ltrim(coalesce(n.dealer_code,''),'0') IN ('1234','2345'))
 -- r420 (F35): a feed row stays on Sales whatever its PMB state; a deleted PMB vehicle reads as awaiting PMB link.
 AND (ctx->>'role'='administrator' OR coalesce((ctx->>'can_view_all_salespeople')::boolean,false) OR
  CASE WHEN v.salesperson_manual_override THEN v.salesperson_id ELSE source_sp.id END=(ctx->>'salesperson_id')::uuid);
 IF jsonb_array_length(rows)>5000 THEN RAISE EXCEPTION 'Vehicle list exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',rows,'navision_updated_at',latest,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.get_builds()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 -- r495 (F108): the build sheet and Sales Results accessory feeds exist for Broome Toyota (37047) only.
 IF ctx->>'dealer_code' IS DISTINCT FROM '37047' THEN RETURN jsonb_build_object('context',ctx,'items','[]'::jsonb,'checked_at',now()); END IF;
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order',
  'items',b.data->'items','notes',b.data->'notes','other_lines',b.data->'other_lines','source_rows',b.data->'source_rows',
  'source_file',f.file_name,'source_file_sha256',f.file_sha256,'imported_at',b.imported_at,
  'source_stock',b.source_stock,'build_version',b.version
 ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_build_orders b ON b.dealer_code='37047' AND b.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=b.source_record_id::text
 JOIN pdc_sales_private.sales_build_import_batches f ON f.id=b.import_batch_id
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales build display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.get_accessories()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 -- r495 (F108): the build sheet and Sales Results accessory feeds exist for Broome Toyota (37047) only.
 IF ctx->>'dealer_code' IS DISTINCT FROM '37047' THEN RETURN jsonb_build_object('context',ctx,'items','[]'::jsonb,'checked_at',now()); END IF;
 SELECT pdc_sales_private.board_visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order','quote',st.quote,
   'source_file',r.file_name,'snapshot_at',st.snapshot_at,'derived',d.ticks,'status_version',st.version,
   'display',jsonb_build_object(
     'tint',jsonb_build_object('state',d.ticks->'tint'->>'state','source','derived','reason',d.ticks->'tint'->>'reason'),
     'build_po',jsonb_build_object('state',d.ticks->'build'->>'state','source','derived','reason',d.ticks->'build'->>'reason'),
     'tray_ordered',jsonb_build_object('state',d.ticks->'tray'->>'state','source','derived','reason',d.ticks->'tray'->>'reason')),
   'lines',d.lines,
   -- r418: yard hold delay. at_or_past_yard_hold lifts every delay; delay_lifted_lines flags the order row.
   -- r427: yard hold is read from the whole stage order (board location, PMB dates and the Navision/Toyota stage).
   'at_or_past_yard_hold',pdc_sales_private.accessory_yard_hold_reached(e),'delay_lifted_lines',d.lifted
  ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_accessory_vehicle_status st ON st.dealer_code='37047' AND st.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=st.navision_record_id::text
 JOIN pdc_sales_private.sales_accessory_receipts r ON r.id=st.receipt_id
 CROSS JOIN LATERAL (
   SELECT pdc_sales_private.sales_accessory_ticks_delayed(coalesce(jsonb_agg(jsonb_build_object('line_class',l.line_class,'po_state',l.po_state,'delay_active',x.delay='delayed')),'[]'::jsonb)) ticks,
     coalesce(jsonb_agg(jsonb_build_object('group',l.line_class,'line',l.po_line,'item',l.description,'type',l.txn_type,
       'sublet',l.sub_type,'po',l.po_number,'po_state',l.po_state,'notes',l.notes,'in_house',l.in_house,'line_key',l.line_key,'delay',x.delay)
       ORDER BY array_position(ARRAY['build','tray','tint','admin'],l.line_class), l.source_row),'[]'::jsonb) lines,
     count(*) FILTER (WHERE x.delay='lifted') lifted
   FROM pdc_sales_private.sales_accessory_lines l
   LEFT JOIN pdc_sales_private.sales_accessory_line_delays dl ON dl.dealer_code=l.dealer_code AND dl.order_key=l.order_key AND dl.line_key=l.line_key
   CROSS JOIN LATERAL (SELECT CASE WHEN dl.line_key IS NULL OR l.po_state<>'blank' THEN 'none'
     WHEN pdc_sales_private.accessory_yard_hold_reached(e) THEN 'lifted' ELSE 'delayed' END delay) x
   WHERE l.dealer_code='37047' AND l.order_key=st.order_key AND l.superseded_receipt_id IS NULL) d
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales accessory display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.set_board_view_access(p_user_role_id uuid, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE ctx jsonb:=pdc_sales_private.context(); target public.pdc_user_roles; old_scope jsonb; new_scope jsonb;
BEGIN
 IF auth.uid() IS NULL OR ctx->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'Choose enabled or disabled'; END IF;
 SELECT * INTO target FROM public.pdc_user_roles WHERE id=p_user_role_id FOR UPDATE;
 IF target.id IS NULL OR target.role::text<>'salesperson' OR NOT target.active OR target.account_status<>'approved' OR target.auth_user_id IS NULL
 THEN RAISE EXCEPTION 'Approved active salesperson account required'; END IF;
 SELECT to_jsonb(s) INTO old_scope FROM pdc_sales_private.account_scopes s JOIN public.salespeople sp ON sp.id=s.salesperson_id AND sp.active
 WHERE s.user_role_id=target.id AND s.dealer_code IN (SELECT b.dealer_code FROM pdc_sales_private.sales_branches b WHERE b.active) FOR UPDATE OF s;
 IF old_scope IS NULL THEN RAISE EXCEPTION 'Assign Broome salesperson access first'; END IF;
 UPDATE pdc_sales_private.account_scopes SET can_view_all_salespeople=p_enabled,assigned_by=auth.uid(),updated_at=now()
 WHERE user_role_id=target.id AND dealer_code=old_scope->>'dealer_code' RETURNING to_jsonb(account_scopes) INTO new_scope;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',target.id,NULL,
  old_scope,new_scope,jsonb_build_object('operation','set_broome_sales_board_view_access','can_view_all_salespeople',p_enabled));
 RETURN jsonb_build_object('ok',true,'can_view_all_salespeople',p_enabled);
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.admin_accounts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
BEGIN
 IF pdc_sales_private.context()->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator access required' USING errcode='42501'; END IF;
 RETURN jsonb_build_object(
  'accounts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',coalesce(r.full_name,r.display_name,r.email),
   'email',r.email,'status',r.account_status,'salesperson_id',a.salesperson_id,'dealer_code',a.dealer_code) ORDER BY r.email),'[]'::jsonb)
   FROM public.pdc_user_roles r LEFT JOIN pdc_sales_private.account_scopes a ON a.user_role_id=r.id
   WHERE r.auth_user_id IS NOT NULL AND (r.account_status='pending' OR r.role::text='salesperson')),
  'salespeople',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name,'branches',(SELECT coalesce(jsonb_agg(m.dealer_code ORDER BY m.dealer_code),'[]'::jsonb) FROM pdc_sales_private.salesperson_branches m WHERE m.salesperson_id=s.id AND m.enabled)) ORDER BY s.name),'[]'::jsonb)
   FROM public.salespeople s WHERE s.active));
END $function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.link_salesperson_scope_429(p_user_role_id uuid, p_operation text, p_strict boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE r public.pdc_user_roles; cur pdc_sales_private.account_scopes; sp_ids uuid[]; v_sp uuid; v_actor uuid; v_dealer text;
BEGIN
 -- r429 (F41). Called only from admin_change_role (strict) and admin_approve_user (not strict); not granted to app roles.
 SELECT * INTO r FROM public.pdc_user_roles WHERE id=p_user_role_id;
 IF r.id IS NULL OR r.role::text<>'salesperson' THEN RETURN NULL; END IF;
 SELECT * INTO cur FROM pdc_sales_private.account_scopes WHERE user_role_id=r.id;
 IF cur.user_role_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.salespeople s WHERE s.id=cur.salesperson_id AND s.active) THEN
  RETURN cur.salesperson_id;  -- already linked: never re-point an existing link
 END IF;
 SELECT array_agg(s.id) INTO sp_ids FROM public.salespeople s
  WHERE s.active AND s.email IS NOT NULL AND lower(btrim(s.email))=lower(btrim(r.email));
 v_actor:=auth.uid();
 IF coalesce(cardinality(sp_ids),0)<>1 OR v_actor IS NULL THEN
  IF p_strict THEN
   IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required to link Sales access' USING errcode='42501'; END IF;
   IF coalesce(cardinality(sp_ids),0)=0 THEN
    RAISE EXCEPTION 'No active salesperson record has the email %, so their Sales access cannot be linked. Add them to the salespeople list (or correct the email there) first, then change the role again.', r.email USING errcode='22023';
   END IF;
   RAISE EXCEPTION 'More than one active salesperson record has the email %. Fix the salespeople list first, then change the role again.', r.email USING errcode='22023';
  END IF;
  RETURN NULL;
 END IF;
 v_sp:=sp_ids[1];
 -- r495 (F108): a salesperson mapped to exactly one open sales branch is linked to it; otherwise Broome Toyota (37047) as before.
 SELECT CASE WHEN count(*)=1 THEN min(m.dealer_code) END INTO v_dealer FROM pdc_sales_private.salesperson_branches m
  JOIN pdc_sales_private.sales_branches b ON b.dealer_code=m.dealer_code AND b.active WHERE m.salesperson_id=v_sp AND m.enabled;
 v_dealer:=coalesce(v_dealer,'37047');
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by,dealer_code)
 VALUES(r.id,v_sp,v_actor,v_dealer) ON CONFLICT(user_role_id) DO UPDATE
 SET salesperson_id=excluded.salesperson_id,assigned_by=excluded.assigned_by,updated_at=now()
 WHERE account_scopes.user_role_id=excluded.user_role_id;
 PERFORM public.audit_pdc_event('role_change'::public.audit_action,'pdc_sales_private.account_scopes',r.id,NULL,
  CASE WHEN cur.user_role_id IS NULL THEN NULL ELSE to_jsonb(cur) END,
  jsonb_build_object('salesperson_id',v_sp,'dealer_code',v_dealer),
  jsonb_build_object('operation','assign_broome_sales_access','via',p_operation,'release','r429','matched_by','salespeople email'));
 RETURN v_sp;
END
$function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='b95e3c7a8081c0cc49fcf68ba8071686',release='r495',note='r495 (F108): Sales branch (Broome / Karratha) aware (was f46074748e6fcb748b97b072d1160b4e r432)',updated_at=now() WHERE signature='pdc_sales_private.context()';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='4a50d3bd71ae2178298bebce34e85d9f',release='r495',note='r495 (F108): Sales branch (Broome / Karratha) aware (was e57e0904890225fad39c5e41ee1b14ef r420)',updated_at=now() WHERE signature='pdc_sales_private.visibility_source_snapshot(boolean)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='085cea9cec2ff1102591969416869784',release='r495',note='r495 (F108): Sales branch (Broome / Karratha) aware (was 37a9d2d92ce5c34e8617a0058cfd3e4f r420)',updated_at=now() WHERE signature='pdc_sales_private.board_visibility_source_snapshot(boolean)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='2f7f060cdaca01cc2763a15b921debf8',release='r495',note='r495 (F108): Sales branch (Broome / Karratha) aware (was 6249e21543ac7caf096e3175c81406c4 r427)',updated_at=now() WHERE signature='pdc_sales_private.get_accessories()';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a9dc1a0fdfa58c46159175c9eb72e0e7',release='r495',note='r495 (F108): Sales branch (Broome / Karratha) aware (was 280d0afd36816510053cd6ea8fe154b1 r429b)',updated_at=now() WHERE signature='pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('pdc_sales_private.parse_branch_header_495(text)','af48dbdee7c20de5303a813404f81faf','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('pdc_sales_private.requested_branch_495()','be30cc4479d0060117d5fb7e3621b85e','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('pdc_sales_private.branch_info_495(text)','4b1882d777bdb1d02f0b287e0d0f446c','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('pdc_sales_private.assign_branch_access_495(uuid,uuid,text)','a6d883f25fcb3607733bc23f9adc8e58','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean)','3ca79b00df99eb1122342878d5d8d65a','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('public.assign_pdc_sales_branch_access(uuid,uuid,text)','6eff6ccebb87ab14d18db91e49828815','r495','r495 (F108): Karratha Toyota sales branch',now()),
 ('public.set_pdc_salesperson_branch(uuid,text,boolean)','f715acfe093fd0a3343445db4b53d2ef','r495','r495 (F108): Karratha Toyota sales branch',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sales_branch_495','F108','Sales branches (r495): Broome Toyota 37047 and Karratha Toyota 14450; existing CF and SL emails updated and mapped to 14450; Broome account scope kept; RK/JS/DB inserted only when free; finance functions unchanged; head-office dealers are not a Sales branch; context() keeps the r432 controller rules',
  $chk$WITH b AS (
  SELECT count(*) FILTER (WHERE dealer_code='37047' AND branch_key='broome' AND label='Broome Toyota' AND finance_group='Broome' AND active) broome,
         count(*) FILTER (WHERE dealer_code='14450' AND branch_key='karratha') karratha FROM pdc_sales_private.sales_branches
), c AS (
  SELECT position('requested_branch_495()' IN p.prosrc)>0 AND position('NOT IN (''salesperson'',''operator'')' IN p.prosrc)>0
     AND position('''account_role'',r.role::text' IN p.prosrc)>0 AND position('Your Sales access is for %' IN p.prosrc)>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_sales_private.context()')
), h AS (
  SELECT pdc_sales_private.parse_branch_header_495(NULL) IS NULL AND pdc_sales_private.parse_branch_header_495('{}') IS NULL
     AND pdc_sales_private.parse_branch_header_495('not json') IS NULL
     AND pdc_sales_private.parse_branch_header_495('{"x-pdc-sales-branch":"karratha"}') IS NOT DISTINCT FROM (SELECT dealer_code FROM pdc_sales_private.sales_branches WHERE branch_key='karratha' AND active)
     AND pdc_sales_private.parse_branch_header_495('{"x-pdc-sales-branch":"37047"}')='37047' ok
), g AS (
  SELECT bool_and(NOT pg_catalog.has_function_privilege('anon',f,'EXECUTE') AND NOT pg_catalog.has_function_privilege('authenticated',f,'EXECUTE')) priv_closed
  FROM unnest(ARRAY['pdc_sales_private.parse_branch_header_495(text)','pdc_sales_private.requested_branch_495()','pdc_sales_private.branch_info_495(text)']::regprocedure[]) f
), w AS (
  SELECT bool_and(NOT pg_catalog.has_function_privilege('anon',f,'EXECUTE') AND pg_catalog.has_function_privilege('authenticated',f,'EXECUTE')) ok
  FROM unnest(ARRAY['public.assign_pdc_sales_branch_access(uuid,uuid,text)','public.set_pdc_salesperson_branch(uuid,text,boolean)',
   'pdc_sales_private.assign_branch_access_495(uuid,uuid,text)','pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean)']::regprocedure[]) f
), s AS (
  SELECT (SELECT count(*) FROM pdc_sales_private.account_scopes a WHERE NOT EXISTS(SELECT 1 FROM pdc_sales_private.sales_branches x WHERE x.dealer_code=a.dealer_code AND x.active)) bad_scopes,
         (SELECT count(*) FROM pdc_sales_private.account_scopes WHERE dealer_code<>'37047') other_scopes
), people AS (
  SELECT (SELECT count(*) FROM public.salespeople s JOIN pdc_sales_private.salesperson_branches m ON m.salesperson_id=s.id
           WHERE upper(btrim(s.code))='CF' AND lower(btrim(s.name))='clint franklin' AND s.active
             AND lower(btrim(s.email))='clint.franklin@karrathatoyota.com.au'
             AND m.dealer_code='14450' AND m.enabled AND m.navision_number='19901126'
             AND (SELECT count(*) FROM public.salespeople x WHERE upper(btrim(coalesce(x.code,'')))='CF')=1) cf,
         (SELECT count(*) FROM public.salespeople s JOIN pdc_sales_private.salesperson_branches m ON m.salesperson_id=s.id
           WHERE upper(btrim(s.code))='SL' AND lower(btrim(s.name))='scott lovett' AND s.active
             AND lower(btrim(s.email))='scott@karrathatoyota.com.au'
             AND m.dealer_code='14450' AND m.enabled AND m.navision_number='19660914'
             AND (SELECT count(*) FROM public.salespeople x WHERE upper(btrim(coalesce(x.code,'')))='SL')=1) sl,
         (SELECT count(*) FROM public.salespeople s
           WHERE s.id IN ('c4950003-0000-4000-a000-000000000003','c4950004-0000-4000-a000-000000000004','c4950005-0000-4000-a000-000000000005')
             AND NOT s.active) future_inserted,
         (SELECT count(*) FROM pdc_sales_private.account_scopes a JOIN public.salespeople s ON s.id=a.salesperson_id
           WHERE upper(btrim(s.code)) IN ('CF','SL') AND a.dealer_code<>'37047') moved_scopes
), fin AS (
  SELECT to_regclass('pdc_sales_private.finance_application_branches') IS NULL
     AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_pipeline()'))='372dcae199c750594923e2269f661e43'
     AND (SELECT finance_group FROM pdc_sales_private.sales_branches WHERE dealer_code='14450')='Later'
     AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.sales_branches WHERE ltrim(dealer_code,'0') IN ('1234','2345'))
     AND position('dealer_code''=''37047'' OR EXISTS' IN (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')))>0 ok
)
SELECT (SELECT broome=1 AND karratha=1 FROM b) AND coalesce((SELECT ok FROM c),false) AND (SELECT ok FROM h) AND (SELECT priv_closed FROM g) AND (SELECT ok FROM w)
   AND (SELECT bad_scopes=0 FROM s) AND (SELECT cf=1 AND sl=1 AND moved_scopes=0 FROM people) AND (SELECT ok FROM fin) AS ok,
 'branches: Broome '||(SELECT broome FROM b)||', Karratha '||(SELECT karratha FROM b)||'; Sales check picks the branch (header for admins, own scope for salespeople): '
 ||CASE WHEN coalesce((SELECT ok FROM c),false) THEN 'yes' ELSE 'NO' END||'; header parsing: '||CASE WHEN (SELECT ok FROM h) THEN 'ok' ELSE 'BAD' END
 ||'; private helpers closed to app roles: '||CASE WHEN (SELECT priv_closed FROM g) THEN 'yes' ELSE 'NO' END
 ||'; admin RPCs authenticated-only: '||CASE WHEN (SELECT ok FROM w) THEN 'yes' ELSE 'NO' END
 ||'; Sales accounts outside an open branch: '||(SELECT bad_scopes FROM s)||'; non-Broome accounts: '||(SELECT other_scopes FROM s)
 ||'; Karratha salespeople CF/SL/placeholders inserted: '||(SELECT cf FROM people)||'/'||(SELECT sl FROM people)||'/'||(SELECT future_inserted FROM people)
 ||'; CF/SL scopes moved off Broome: '||(SELECT moved_scopes FROM people)
 ||'; finance left as Broome (no Karratha finance table): '||CASE WHEN (SELECT ok FROM fin) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,295,'r495');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.context()')) IS DISTINCT FROM 'b95e3c7a8081c0cc49fcf68ba8071686' THEN RAISE EXCEPTION 'r495: pdc_sales_private.context() did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM '4a50d3bd71ae2178298bebce34e85d9f' THEN RAISE EXCEPTION 'r495: pdc_sales_private.visibility_source_snapshot(boolean) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '085cea9cec2ff1102591969416869784' THEN RAISE EXCEPTION 'r495: pdc_sales_private.board_visibility_source_snapshot(boolean) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.crm_finance_refs()')) IS DISTINCT FROM '4aaf4702df0aa0515485046e05892d0b' THEN RAISE EXCEPTION 'r495: pdc_sales_private.crm_finance_refs() changed; this release does not touch finance'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_pipeline()')) IS DISTINCT FROM '372dcae199c750594923e2269f661e43' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_pipeline() changed; this release does not touch finance'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_accessories()')) IS DISTINCT FROM '2f7f060cdaca01cc2763a15b921debf8' THEN RAISE EXCEPTION 'r495: pdc_sales_private.get_accessories() did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean)')) IS DISTINCT FROM 'a9dc1a0fdfa58c46159175c9eb72e0e7' THEN RAISE EXCEPTION 'r495: pdc_sales_private.link_salesperson_scope_429(uuid,text,boolean) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_visibility_check_435()')) IS DISTINCT FROM 'b618db56602ab648872951306a5ad273' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_visibility_check_435() changed; this release does not touch finance'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.parse_branch_header_495(text)')) IS DISTINCT FROM 'af48dbdee7c20de5303a813404f81faf' THEN RAISE EXCEPTION 'r495: pdc_sales_private.parse_branch_header_495(text) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.requested_branch_495()')) IS DISTINCT FROM 'be30cc4479d0060117d5fb7e3621b85e' THEN RAISE EXCEPTION 'r495: pdc_sales_private.requested_branch_495() did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.branch_info_495(text)')) IS DISTINCT FROM '4b1882d777bdb1d02f0b287e0d0f446c' THEN RAISE EXCEPTION 'r495: pdc_sales_private.branch_info_495(text) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.assign_branch_access_495(uuid,uuid,text)')) IS DISTINCT FROM 'a6d883f25fcb3607733bc23f9adc8e58' THEN RAISE EXCEPTION 'r495: pdc_sales_private.assign_branch_access_495(uuid,uuid,text) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean)')) IS DISTINCT FROM '3ca79b00df99eb1122342878d5d8d65a' THEN RAISE EXCEPTION 'r495: pdc_sales_private.set_salesperson_branch_495(uuid,text,boolean) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.assign_pdc_sales_branch_access(uuid,uuid,text)')) IS DISTINCT FROM '6eff6ccebb87ab14d18db91e49828815' THEN RAISE EXCEPTION 'r495: public.assign_pdc_sales_branch_access(uuid,uuid,text) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_pdc_salesperson_branch(uuid,text,boolean)')) IS DISTINCT FROM 'f715acfe093fd0a3343445db4b53d2ef' THEN RAISE EXCEPTION 'r495: public.set_pdc_salesperson_branch(uuid,text,boolean) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.get_builds()')) IS DISTINCT FROM '1f8a3b4c3d8d827bece9d0eb2bb20e8a' THEN RAISE EXCEPTION 'r495: pdc_sales_private.get_builds() did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.finance_application_save(uuid,uuid,jsonb,text,jsonb,integer)')) IS DISTINCT FROM 'bbeb49580363dcf5acc4dfac35d1e226' THEN RAISE EXCEPTION 'r495: pdc_sales_private.finance_application_save changed; this release does not touch finance'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.set_board_view_access(uuid,boolean)')) IS DISTINCT FROM '3e9fbb1b8bbd0ae26c885fa050143265' THEN RAISE EXCEPTION 'r495: pdc_sales_private.set_board_view_access(uuid,boolean) did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.admin_accounts()')) IS DISTINCT FROM 'fd9d90752b2d3a744c7853ba5b8fc5af' THEN RAISE EXCEPTION 'r495: pdc_sales_private.admin_accounts() did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r495_tick') THEN RAISE EXCEPTION 'r495: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r495_frc') THEN RAISE EXCEPTION 'r495: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r495')<>12 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r495_pins')::int+7 THEN RAISE EXCEPTION 'r495: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495' AND added_in='r495' AND sort_order=295) IS DISTINCT FROM '8ff7e1e97dd9cb89ed5ff4e43ce98da9' THEN RAISE EXCEPTION 'r495: check did not land as expected'; END IF;
 IF (SELECT md5(coalesce(string_agg(user_role_id::text||salesperson_id::text||dealer_code||can_view_all_salespeople::text,',' ORDER BY user_role_id),'')) FROM pdc_sales_private.account_scopes) IS DISTINCT FROM current_setting('pdc.r495_scopes')
    OR (SELECT md5(coalesce(string_agg(id::text||version::text,',' ORDER BY id),'')) FROM pdc_sales_private.finance_applications) IS DISTINCT FROM current_setting('pdc.r495_fin') THEN RAISE EXCEPTION 'r495: existing Sales accounts or finance entries changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r495: check not OK: %',y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
