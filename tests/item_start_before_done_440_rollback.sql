BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL TIME ZONE 'Australia/Perth';
CREATE TEMP TABLE t_res(step serial, k text, v jsonb) ON COMMIT DROP;
INSERT INTO t_res(k,v) SELECT 'S0 meta', jsonb_build_object(
 'cmd',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure),
 'pins',(SELECT md5(string_agg(signature||prosrc_md5||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5),
 'checks',(SELECT md5(string_agg(check_name||md5(check_sql)||sort_order||enabled,',' ORDER BY check_name)) FROM pdc_ops.regression_checks),'nchecks',(SELECT count(*) FROM pdc_ops.regression_checks),
 'tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure));
-- r440 (F51, Craig via PMB Email 14:31 AWST 21 Oct): fitter bay items need Start before Done.
-- Staging cdsmnqxtyyoeoznmbidd only. Changes one function: public.fitter_job_command, action 'line', refuses to tick an
-- internal bay item Done unless that item is started (item_status 'running'), returns error 'item_not_started' and writes an
-- 'item_done_refused' row to pdc_fitter_private.operation_timing_audit. Already-Done items, note saves on them, unticking,
-- supplier (external) lines and conversion lines are unchanged. No row is changed: items Done without a start stay Done.
-- Not touched: workshop_clock_tick and its cron, the r431 clock helpers, item_timing*, reset_fitter_item_timing, the hidden
-- Karratha copy. Pin #387 for fitter_job_command moves to r440 (undo restores it); adds check item_start_before_done.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r440: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r440: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r440: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='4952bea1ccb019c7d1dfe0dc873a5c67'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command is not the #387 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387')<>1 THEN RAISE EXCEPTION 'r440: pin is not the #387 pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r440')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' OR added_in='r440') THEN RAISE EXCEPTION 'r440: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=241) THEN RAISE EXCEPTION 'r440: sort_order 241 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     -- r440 (F51): an internal bay item must be started before it is ticked Done. An item already Done stays Done (a note
     -- save re-sends completed=true and is allowed) and unticking is always allowed. Supplier and conversion lines keep
     -- their own ticks. Same rule for fitters, controllers and admins on this card; refusals are audited.
     IF p_completed AND NOT coalesce((l->>'completed')::boolean,false)
        AND l->>'external_work' IS DISTINCT FROM 'true' AND coalesce(jsonb_typeof(l->'conversion'),'null')='null'
        AND l->>'item_status' IS DISTINCT FROM 'running' THEN
       INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
       VALUES(b.id,p_line_identity,p_technician_id,auth.uid(),'item_done_refused',
        coalesce((SELECT to_jsonb(t) FROM pdc_fitter_private.operation_timing t WHERE t.booking_id=b.id AND t.line_identity=p_line_identity),'{}'::jsonb),
        jsonb_build_object('error','item_not_started','item_status',l->'item_status','release','r440'));
       RETURN jsonb_build_object('ok',false,'error','item_not_started');
     END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9c30466cfef22ccda3c6d955bf484489',release='r440',note='r440: item Done needs Start (F51)',updated_at=clock_timestamp()
 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('item_start_before_done','F51','Fitter bay items (r440): fitter_job_command carries the Start-before-Done guard (item_not_started, audited as item_done_refused) and matches its pin; since r440 no item ticked Done has a timing row left running or reset (Done was ticked without the item being started); reports refusals in the last 24 h',
  $chk$WITH fn AS (
  SELECT p.prosrc ~ 'r440 \(F51\)' AND p.prosrc ~ '''error'',''item_not_started''' AND p.prosrc ~ '''item_done_refused''' AS guarded,
   md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440') AS pinned
  FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')
), since AS (
  SELECT greatest((SELECT e.updated_at FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440'),
   statement_timestamp()-interval '7 days') t
), bad AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_progress op
   JOIN pdc_fitter_private.operation_timing ot ON ot.booking_id=op.booking_id AND ot.line_identity=op.line_identity
  WHERE op.completed AND op.updated_at>(SELECT t FROM since) AND ot.status IN ('running','reset') AND ot.updated_at<=op.updated_at
), refused AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done_refused' AND a.created_at>statement_timestamp()-interval '24 hours'
), done AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done' AND a.created_at>(SELECT t FROM since)
)
SELECT coalesce((SELECT guarded AND pinned FROM fn),false) AND (SELECT n FROM bad)=0 AS ok,
 'guard in fitter_job_command: '||coalesce((SELECT guarded::text FROM fn),'function missing')||', matches r440 pin: '||coalesce((SELECT pinned::text FROM fn),'no')
 ||'; since r440: '||(SELECT n FROM done)||' items ticked Done after Start, '||(SELECT n FROM bad)||' ticked Done while the item was not started'
 ||'; Done refused (Press Start first) in the last 24 h: '||(SELECT n FROM refused) AS detail
$chk$,true,241,'r440');

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='9c30466cfef22ccda3c6d955bf484489'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r440')<>1 THEN RAISE EXCEPTION 'r440: pin not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' AND added_in='r440')<>'909dde10e0882bb95cf31af9bcc6dfe3' THEN RAISE EXCEPTION 'r440: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed'; END IF;
END $g$;
INSERT INTO t_res(k,v) SELECT 'S1 meta', jsonb_build_object(
 'cmd',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure),
 'pins',(SELECT md5(string_agg(signature||prosrc_md5||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5),
 'checks',(SELECT md5(string_agg(check_name||md5(check_sql)||sort_order||enabled,',' ORDER BY check_name)) FROM pdc_ops.regression_checks),'nchecks',(SELECT count(*) FROM pdc_ops.regression_checks),
 'tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure));
CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ou_assert(pass boolean, label text, evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO ou_results VALUES(label,'PASS',evidence);
END $fn$;

DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; b uuid:=gen_random_uuid();
BEGIN
 e:='operation-update-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"Temporary operation update rollback fixture"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 INSERT INTO ou_context VALUES(a,e,(date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+18),b);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-base-'||b,'apply',1,1,0,1,0,0,'{}',a,e);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM pg_temp.ou_assert(public.workshop_is_planner_operator(),'Synthetic operator is authorized');
END $setup$;

CREATE FUNCTION pg_temp.ou_vehicle(tag text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid:=gen_random_uuid(); stock text:='OU-'||substr(v::text,1,8); actor_id uuid;
BEGIN
 SELECT actor INTO actor_id FROM ou_context;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,visible_on_board,
 source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Synthetic vehicle','PMB',true,
 'operation_update_rollback_20260913',v::text,'{"rollback_fixture":true}',actor_id,actor_id);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,approved_at,approved_by)
 VALUES(v,'approved','OU-JC-'||substr(v::text,1,8),clock_timestamp(),actor_id);
 INSERT INTO ou_refs VALUES('vehicle-'||tag,v);
 RETURN v;
END $fn$;

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, opdesc text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description',CASE WHEN opdesc IS NOT NULL THEN opdesc WHEN stage='BUS_4X4' THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,'139',stage);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vid,wk,true,false)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE true;
 RETURN op;
END $fn$;

CREATE FUNCTION pg_temp.ou_booking(tag text, vid uuid, stage text, bay uuid, start_at timestamptz, state public.workshop_booking_status DEFAULT 'planned')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE bid uuid:=gen_random_uuid(); sid uuid; mins integer; actor_id uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage;
 SELECT actor INTO actor_id FROM ou_context;
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;


CREATE FUNCTION pg_temp.fcmd(tech uuid, b uuid, act text, li text, done boolean DEFAULT NULL, note text DEFAULT NULL, rid uuid DEFAULT gen_random_uuid()) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE d jsonb;
BEGIN
 d:=public.get_fitter_job(tech,b);
 RETURN public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',rid,act,li,done,note);
END $fn$;
CREATE FUNCTION pg_temp.ln(tech uuid, b uuid, li text) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT x FROM jsonb_array_elements(public.get_fitter_job(tech,b)->'lines') x WHERE x->>'line_identity'=li
$fn$;
CREATE FUNCTION pg_temp.cmd(tech uuid, b uuid, change jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE d jsonb; l jsonb;
BEGIN
 d:=public.get_fitter_job(tech,b);
 SELECT x INTO l FROM jsonb_array_elements(d->'lines') x WHERE x->'conversion' IS NOT NULL;
 RETURN public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion',l->>'line_identity',NULL,change::text);
END $fn$;
CREATE FUNCTION pg_temp.conv(tech uuid, b uuid) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT x FROM jsonb_array_elements(public.get_fitter_job(tech,b)->'lines') x WHERE x->'conversion' IS NOT NULL
$fn$;

CREATE FUNCTION pg_temp.chk(name text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE q text; r record;
BEGIN SELECT check_sql INTO STRICT q FROM pdc_ops.regression_checks WHERE check_name=name; EXECUTE q INTO r; RETURN jsonb_build_object('ok',r.ok,'d',r.detail); END $fn$;
INSERT INTO t_res(k,v) SELECT 'S1 chk '||n, pg_temp.chk(n) FROM unnest(ARRAY['item_start_before_done','protected_function_md5s']) n;

DO $t$
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); d jsonb; l jsonb; r jsonb; prog jsonb; l1 text; l2 text; l3 text;
 p0 jsonb; n0 bigint; n1 bigint; adm uuid:=gen_random_uuid(); ae text; vrow0 jsonb; cnt int;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'r440 rollback fitter','technician',true);
 v:=pg_temp.ou_vehicle('fit'); bay:=pg_temp.ou_bay('fit','FITTING'); UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'FITTING',5,1); PERFORM pg_temp.ou_operation(v,'FITTING',3,2); PERFORM pg_temp.ou_operation(v,'FITTING',2,3);
 b:=pg_temp.ou_booking('fit',v,'FITTING',bay,date_trunc('minute',now())-interval '3 hours','started');
 d:=public.get_fitter_job(tech,b);
 SELECT x->>'line_identity' INTO l1 FROM jsonb_array_elements(d->'lines') x WHERE x->>'stage_code'='FITTING' AND (x->>'hours')::numeric=5;
 SELECT x->>'line_identity' INTO l2 FROM jsonb_array_elements(d->'lines') x WHERE x->>'stage_code'='FITTING' AND (x->>'hours')::numeric=3;
 SELECT x->>'line_identity' INTO l3 FROM jsonb_array_elements(d->'lines') x WHERE x->>'stage_code'='FITTING' AND (x->>'hours')::numeric=2;
 PERFORM pg_temp.ou_assert(l1 IS NOT NULL AND l2 IS NOT NULL AND l3 IS NOT NULL,'01 three synthetic Dept 139 fitting lines (5 h, 3 h, 2 h)',d->'progress');
 n0:=(SELECT count(*) FROM pdc_fitter_private.operation_timing_audit WHERE booking_id=b AND action='item_done_refused');
 r:=pg_temp.fcmd(tech,b,'line',l1,true,'');
 n1:=(SELECT count(*) FROM pdc_fitter_private.operation_timing_audit WHERE booking_id=b AND action='item_done_refused');
 PERFORM pg_temp.ou_assert(r->>'error'='item_not_started' AND NOT coalesce((pg_temp.ln(tech,b,l1)->>'completed')::boolean,false)
   AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=b AND line_identity=l1),'02 Done before Start refused (item_not_started), nothing written',r);
 PERFORM pg_temp.ou_assert(n1=n0+1 AND EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing_audit WHERE booking_id=b AND line_identity=l1 AND action='item_done_refused' AND after_state->>'error'='item_not_started' AND technician_id=tech),'03 refusal audited as item_done_refused',jsonb_build_object('n0',n0,'n1',n1));
 r:=pg_temp.fcmd(tech,b,'item_start',l1);
 prog:=pdc_fitter_private.progress(b);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (prog->>'running')::int=1 AND (prog#>>'{current,0,allowance_minutes}')::numeric=300 AND (prog->>'total_hours')::numeric=10,'04 Start ok; progress.current carries the started item 5 h of a 10 h job (bar segment = 50%)',prog-'current');
 r:=pg_temp.fcmd(tech,b,'line',l1,true,'');
 l:=pg_temp.ln(tech,b,l1);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (l->>'completed')::boolean AND l->>'item_status'='done' AND l ? 'item_actual_minutes','05 Done after Start ok, actual stamped',l-'source_note');
 r:=pg_temp.fcmd(tech,b,'line',l1,true,'note on a done item');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'06 Note save on a Done item (completed=true re-sent) allowed',r);
 -- legacy item: Done without a start, written as before r440 (fixture only)
 INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
 VALUES(b,l2,pg_temp.ln(tech,b,l2)->>'scope_hash',true,'',tech,(SELECT actor FROM ou_context));
 l:=pg_temp.ln(tech,b,l2);
 PERFORM pg_temp.ou_assert((l->>'completed')::boolean AND NOT (l ? 'item_status'),'07 legacy Done-without-Start item stays Done (not re-opened)',l-'source_note');
 r:=pg_temp.fcmd(tech,b,'line',l2,true,'legacy note');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (pg_temp.ln(tech,b,l2)->>'completed')::boolean,'08 note save on the legacy Done item allowed',r);
 r:=pg_temp.fcmd(tech,b,'line',l2,false,'');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND NOT (pg_temp.ln(tech,b,l2)->>'completed')::boolean,'09 untick always allowed',r);
 r:=pg_temp.fcmd(tech,b,'line',l2,true,'');
 PERFORM pg_temp.ou_assert(r->>'error'='item_not_started','10 re-tick after untick needs Start again',r);
 r:=pg_temp.fcmd(tech,b,'item_start',l2); r:=pg_temp.fcmd(tech,b,'item_reset',l2);
 r:=pg_temp.fcmd(tech,b,'line',l2,true,'');
 PERFORM pg_temp.ou_assert(r->>'error'='item_not_started','11 Start then fitter reset: Done refused again',r);
 -- administrator on the fitter card: no bypass; admin correction (reset) still works
 ae:='r440-admin-'||adm||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(adm,'authenticated','authenticated',ae,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"r440 rollback admin"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved',approved_at=clock_timestamp() WHERE auth_user_id=adm AND email=ae;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',adm,'email',ae,'role','authenticated')::text,true);
 PERFORM pg_temp.ou_assert(public.current_pdc_user_role()::text='administrator','12 synthetic administrator signed in');
 r:=pg_temp.fcmd(tech,b,'line',l3,true,'');
 PERFORM pg_temp.ou_assert(r->>'error'='item_not_started','13 administrator gets no bypass on the fitter card',r);
 r:=pg_temp.fcmd(tech,b,'item_start',l3);
 r:=public.reset_fitter_item_timing(b,l3,NULL,'r440 rollback correction');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (SELECT status FROM pdc_fitter_private.operation_timing WHERE booking_id=b AND line_identity=l3)='reset','14 admin correction reset_fitter_item_timing still works',r);
 r:=pg_temp.fcmd(tech,b,'item_start',l3); r:=pg_temp.fcmd(tech,b,'line',l3,true,'');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'15 administrator: Start then Done ok',r);
 r:=pg_temp.fcmd(tech,b,'line',l1,false,'');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND NOT (pg_temp.ln(tech,b,l1)->>'completed')::boolean,'16 administrator can untick a Done item (correction)',r);
 PERFORM pg_temp.ou_assert((pg_temp.chk('item_start_before_done')->>'ok')::boolean,'17 item_start_before_done green with the fixture',pg_temp.chk('item_start_before_done'));
 -- the check catches a Done tick left without a start (simulated old behaviour, fixture only)
 UPDATE pdc_fitter_private.operation_timing SET status='reset',updated_at=clock_timestamp()-interval '1 second' WHERE booking_id=b AND line_identity=l2 AND status='reset';
 UPDATE pdc_fitter_private.operation_progress SET completed=true,updated_at=clock_timestamp() WHERE booking_id=b AND line_identity=l2 AND completed=false;
 PERFORM pg_temp.ou_assert(NOT (pg_temp.chk('item_start_before_done')->>'ok')::boolean,'18 item_start_before_done turns red on a Done-without-Start tick',pg_temp.chk('item_start_before_done'));
 UPDATE pdc_fitter_private.operation_progress SET completed=false,updated_at=clock_timestamp() WHERE booking_id=b AND line_identity=l2 AND completed=true;
 PERFORM pg_temp.ou_assert((SELECT count(*) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure AND md5(prosrc)='84af7607bfd0ce9907c89bae8644d5b6')=1,'19 clock tick unchanged');
 INSERT INTO t_res(k,v) SELECT 'tests', jsonb_agg(name ORDER BY name) FROM ou_results;
END $t$;
SELECT set_config('request.jwt.claims','',true);
-- r440 undo (F51): restores public.fitter_job_command byte for byte (#387 version, md5 4952bea1ccb019c7d1dfe0dc873a5c67), puts the #387 pin back and
-- drops the item_start_before_done check. Audit rows written by r440 refusals ('item_done_refused') are history and stay.
-- Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r440 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r440 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r440 undo: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='9c30466cfef22ccda3c6d955bf484489'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440 undo: fitter_job_command is not the r440 version; nothing restored'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67',release='#387',note='multiple Start/Done items',updated_at=clock_timestamp()
 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='9c30466cfef22ccda3c6d955bf484489' AND release='r440';
DELETE FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' AND added_in='r440';

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='4952bea1ccb019c7d1dfe0dc873a5c67'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440 undo: fitter_job_command not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387')<>1
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r440') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r440')
 THEN RAISE EXCEPTION 'r440 undo: r440 rows remain'; END IF;
END $g$;
INSERT INTO t_res(k,v) SELECT 'S2 meta', jsonb_build_object(
 'cmd',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure),
 'pins',(SELECT md5(string_agg(signature||prosrc_md5||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5),
 'checks',(SELECT md5(string_agg(check_name||md5(check_sql)||sort_order||enabled,',' ORDER BY check_name)) FROM pdc_ops.regression_checks),'nchecks',(SELECT count(*) FROM pdc_ops.regression_checks),
 'tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure));
-- r440 (F51, Craig via PMB Email 14:31 AWST 21 Oct): fitter bay items need Start before Done.
-- Staging cdsmnqxtyyoeoznmbidd only. Changes one function: public.fitter_job_command, action 'line', refuses to tick an
-- internal bay item Done unless that item is started (item_status 'running'), returns error 'item_not_started' and writes an
-- 'item_done_refused' row to pdc_fitter_private.operation_timing_audit. Already-Done items, note saves on them, unticking,
-- supplier (external) lines and conversion lines are unchanged. No row is changed: items Done without a start stay Done.
-- Not touched: workshop_clock_tick and its cron, the r431 clock helpers, item_timing*, reset_fitter_item_timing, the hidden
-- Karratha copy. Pin #387 for fitter_job_command moves to r440 (undo restores it); adds check item_start_before_done.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r440: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r440: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r440: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='4952bea1ccb019c7d1dfe0dc873a5c67'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command is not the #387 version; nothing changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387')<>1 THEN RAISE EXCEPTION 'r440: pin is not the #387 pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r440')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' OR added_in='r440') THEN RAISE EXCEPTION 'r440: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=241) THEN RAISE EXCEPTION 'r440: sort_order 241 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     -- r440 (F51): an internal bay item must be started before it is ticked Done. An item already Done stays Done (a note
     -- save re-sends completed=true and is allowed) and unticking is always allowed. Supplier and conversion lines keep
     -- their own ticks. Same rule for fitters, controllers and admins on this card; refusals are audited.
     IF p_completed AND NOT coalesce((l->>'completed')::boolean,false)
        AND l->>'external_work' IS DISTINCT FROM 'true' AND coalesce(jsonb_typeof(l->'conversion'),'null')='null'
        AND l->>'item_status' IS DISTINCT FROM 'running' THEN
       INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
       VALUES(b.id,p_line_identity,p_technician_id,auth.uid(),'item_done_refused',
        coalesce((SELECT to_jsonb(t) FROM pdc_fitter_private.operation_timing t WHERE t.booking_id=b.id AND t.line_identity=p_line_identity),'{}'::jsonb),
        jsonb_build_object('error','item_not_started','item_status',l->'item_status','release','r440'));
       RETURN jsonb_build_object('ok',false,'error','item_not_started');
     END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='9c30466cfef22ccda3c6d955bf484489',release='r440',note='r440: item Done needs Start (F51)',updated_at=clock_timestamp()
 WHERE signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND prosrc_md5='4952bea1ccb019c7d1dfe0dc873a5c67' AND release='#387';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('item_start_before_done','F51','Fitter bay items (r440): fitter_job_command carries the Start-before-Done guard (item_not_started, audited as item_done_refused) and matches its pin; since r440 no item ticked Done has a timing row left running or reset (Done was ticked without the item being started); reports refusals in the last 24 h',
  $chk$WITH fn AS (
  SELECT p.prosrc ~ 'r440 \(F51\)' AND p.prosrc ~ '''error'',''item_not_started''' AND p.prosrc ~ '''item_done_refused''' AS guarded,
   md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440') AS pinned
  FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')
), since AS (
  SELECT greatest((SELECT e.updated_at FROM pdc_ops.expected_function_md5 e WHERE e.signature='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)' AND e.release='r440'),
   statement_timestamp()-interval '7 days') t
), bad AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_progress op
   JOIN pdc_fitter_private.operation_timing ot ON ot.booking_id=op.booking_id AND ot.line_identity=op.line_identity
  WHERE op.completed AND op.updated_at>(SELECT t FROM since) AND ot.status IN ('running','reset') AND ot.updated_at<=op.updated_at
), refused AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done_refused' AND a.created_at>statement_timestamp()-interval '24 hours'
), done AS (
  SELECT count(*) n FROM pdc_fitter_private.operation_timing_audit a WHERE a.action='item_done' AND a.created_at>(SELECT t FROM since)
)
SELECT coalesce((SELECT guarded AND pinned FROM fn),false) AND (SELECT n FROM bad)=0 AS ok,
 'guard in fitter_job_command: '||coalesce((SELECT guarded::text FROM fn),'function missing')||', matches r440 pin: '||coalesce((SELECT pinned::text FROM fn),'no')
 ||'; since r440: '||(SELECT n FROM done)||' items ticked Done after Start, '||(SELECT n FROM bad)||' ticked Done while the item was not started'
 ||'; Done refused (Press Start first) in the last 24 h: '||(SELECT n FROM refused) AS detail
$chk$,true,241,'r440');

DO $g$ BEGIN
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)') AND md5(p.prosrc)='9c30466cfef22ccda3c6d955bf484489'
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|v|postgres|search_path=pg_catalog, public')<>1 THEN RAISE EXCEPTION 'r440: fitter_job_command did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r440')<>1 THEN RAISE EXCEPTION 'r440: pin not moved'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='item_start_before_done' AND added_in='r440')<>'909dde10e0882bb95cf31af9bcc6dfe3' THEN RAISE EXCEPTION 'r440: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r440: clock tick changed'; END IF;
END $g$;
INSERT INTO t_res(k,v) SELECT 'S3 meta', jsonb_build_object(
 'cmd',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure),
 'pins',(SELECT md5(string_agg(signature||prosrc_md5||release,',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),'npins',(SELECT count(*) FROM pdc_ops.expected_function_md5),
 'checks',(SELECT md5(string_agg(check_name||md5(check_sql)||sort_order||enabled,',' ORDER BY check_name)) FROM pdc_ops.regression_checks),'nchecks',(SELECT count(*) FROM pdc_ops.regression_checks),
 'tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure));
SELECT jsonb_build_object('res',(SELECT jsonb_agg(jsonb_build_object('k',k,'v',v) ORDER BY step) FROM t_res),
 'undo_restores_before',(SELECT v FROM t_res WHERE k='S0 meta')=(SELECT v FROM t_res WHERE k='S2 meta'),
 'reapply_equals_apply',(SELECT v FROM t_res WHERE k='S1 meta')=(SELECT v FROM t_res WHERE k='S3 meta'),'at',clock_timestamp()) r;
ROLLBACK;
