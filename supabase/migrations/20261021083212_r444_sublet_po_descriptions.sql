-- r444 (F57, change request; Craig 21 Oct 16:24 AWST): sublet descriptions on the PDC staging board. Staging cdsmnqxtyyoeoznmbidd only.
-- The vehicle drop-down's Sublet box lists every sublet with its 'Description of sublet' from the Revolution w/Sublet upload.
-- (1) public.pdc_service_line_po_refs_439 gains description (as typed, ends trimmed, <= 1000 chars) and description_source_file_sha256.
-- (2) import_sublet_pos_439: optional 'description' per row; stored when a PO is attached, refreshed when a later file has a
--     non-blank one, NEVER cleared (blank / missing = keep). Row statuses carry description none/unchanged/set; the result has
--     'descriptions' counts. Everything else (PO-only, GP only, skips, ticks never cleared, receipts, audit) unchanged.
-- (3) sublet_po_vehicle_439 (read by get_pdc_sublet_lines_439): each line adds po_details [{po_number, description}].
-- (4) service_sublet_po_feed_442: passes raw_row.sublet_po_descriptions (w/Sublet) or sublet_columns."Description of sublet"
--     (r439 CSV / workbook) as each row's description. The service apply (pdc_pilbara_service_apply_v1) is NOT changed.
-- (5) revolution_service_rows_20261006: optional raw_row.sublet_po_descriptions = object keyed by POs in sublet_pos, string values.
-- No tick, PO, category, bay or booking changes. Not touched: clock tick, service apply, tick / read RPCs, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r444: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r444: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r444: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r444: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)'::regprocedure)<>'709b0156a11db82721e6acb40c2c947b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_sublet_lines_439(uuid)'::regprocedure)<>'b211d82171b565ee841c08ae9023c297'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_sublet_po_board_439()'::regprocedure)<>'7dde7e19d31b269136a93ebecd12217a' THEN RAISE EXCEPTION 'r444: service apply or sublet tick/read functions changed (this release must not touch them)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6cc118c512e103e33bfe94118b91d8a1'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_po_vehicle_439(uuid)'::regprocedure)<>'bf4f60277f69b53cbd982c7aa24b2401'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)<>'6119632a2c961505b8875d1f0dcbdbaa'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'fd1d9272719cba74fdca23f9015d6d08' THEN RAISE EXCEPTION 'r444: sublet functions are not the r439 / r442 versions'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='public.import_sublet_pos_439(jsonb,text,boolean)' AND prosrc_md5='6cc118c512e103e33bfe94118b91d8a1' AND release='r439') OR (signature='pdc_work_categories_private.sublet_po_vehicle_439(uuid)' AND prosrc_md5='bf4f60277f69b53cbd982c7aa24b2401' AND release='r439') OR (signature='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)' AND prosrc_md5='6119632a2c961505b8875d1f0dcbdbaa' AND release='r442') OR (signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)' AND prosrc_md5='fd1d9272719cba74fdca23f9015d6d08' AND release='r442'))<>4 THEN RAISE EXCEPTION 'r444: pins unexpected'; END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pdc_service_line_po_refs_439' AND column_name IN ('description','description_source_file_sha256'))
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r444')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sublet_po_descriptions_444' OR added_in='r444') THEN RAISE EXCEPTION 'r444: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=243) THEN RAISE EXCEPTION 'r444: sort_order 243 taken'; END IF;
END $g$;

ALTER TABLE public.pdc_service_line_po_refs_439
  ADD COLUMN description text CHECK (description IS NULL OR length(description) BETWEEN 1 AND 1000),
  ADD COLUMN description_source_file_sha256 text CHECK (description_source_file_sha256 IS NULL OR description_source_file_sha256 ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT pdc_service_line_po_refs_439_description_source CHECK ((description IS NULL) = (description_source_file_sha256 IS NULL));
COMMENT ON COLUMN public.pdc_service_line_po_refs_439.description IS 'r444 (F57): Description of sublet from the Revolution upload, as typed (never cleared by imports)';

CREATE OR REPLACE FUNCTION public.import_sublet_pos_439(p_rows jsonb, p_source_file_sha256 text, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $f$
DECLARE
 v_role text:=public.current_pdc_user_role()::text; v_uid uuid:=auth.uid(); v_jwt_role text:=coalesce(auth.jwt()->>'role','');
 v_actor text; v_dry boolean:=coalesce(p_dry_run,true); v_sha text:=lower(btrim(coalesce(p_source_file_sha256,'')));
 v_req text; v_prior public.pdc_sublet_po_import_receipts_439%rowtype; v_now timestamptz:=clock_timestamp();
 r record; v_stock text; v_ro text; v_line_txt text; v_line integer; v_po text; v_status text; v_vid uuid; v_n integer;
 v_ls text; v_l jsonb; v_key text; v_lines jsonb:='{}'::jsonb; v_seen jsonb:='{}'::jsonb; v_out jsonb:='[]'::jsonb;
 v_desc text; v_desc_status text; v_cur_desc text;
 v_ins boolean; v_res jsonb; v_jobs integer; v_open integer; v_veh jsonb:='{}'::jsonb;
BEGIN
 -- r439 (F50, Craig 21 Oct 14:37 AWST): PO-only sublet import. Rows [{stock, ro, line, po}] from one source file
 -- (p_source_file_sha256). Records each GP purchase order against an EXISTING open line so the vehicle shows the PO and a
 -- 'sublet done' tick. It never creates vehicles, jobs or lines and never changes a category, bay, booking, location or tick.
 -- Skipped (per-row status): owner-held vehicles, RFT / completed / inactive vehicles, closed jobs, completed, inactive or
 -- job-card-notes lines. 'All' and blank POs are ignored; other non-GP values are reported. Rolling: a PO missing from a later
 -- file is never removed. p_dry_run (default true) previews and writes nothing; an apply is audited and idempotent per
 -- (file hash, request).
 IF v_role IN ('importer','operator','administrator') THEN
  v_actor:=coalesce(auth.jwt()->>'email',v_uid::text);
 ELSIF v_uid IS NULL AND (v_jwt_role='service_role' OR session_user IN ('postgres','supabase_admin')) THEN
  v_actor:='service:'||CASE WHEN v_jwt_role='service_role' THEN 'service_role' ELSE session_user::text END; v_role:='service';
 ELSE RAISE EXCEPTION 'PDC_439_IMPORT_FORBIDDEN: importer, controller or administrator access is required' USING errcode='42501';
 END IF;
 IF v_sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'PDC_439_SOURCE_FILE_SHA256_REQUIRED' USING errcode='22023'; END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)=0 OR jsonb_array_length(p_rows)>30000 THEN
  RAISE EXCEPTION 'PDC_439_ROWS_MUST_BE_A_NON_EMPTY_ARRAY_OF_AT_MOST_30000' USING errcode='22023'; END IF;
 v_req:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-sublet-po-import-439','sha',v_sha,'rows',p_rows)::text,'UTF8'),'sha256'),'hex');
 IF NOT v_dry THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-po-import-439:'||v_sha,0));
  SELECT * INTO v_prior FROM public.pdc_sublet_po_import_receipts_439 WHERE source_file_sha256=v_sha AND request_sha256=v_req;
  IF FOUND THEN RETURN jsonb_set(v_prior.response,'{replay}','true'::jsonb,false); END IF;
 END IF;
 FOR r IN SELECT x.e, x.o FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(e,o) LOOP
  v_status:=NULL; v_vid:=NULL; v_key:=NULL; v_l:=NULL; v_desc_status:=NULL; v_cur_desc:=NULL;
  -- r444 (F57): optional 'Description of sublet' as typed (ends trimmed, at most 1000 characters); blank = none (never clears).
  v_desc:=CASE WHEN jsonb_typeof(r.e)='object' AND jsonb_typeof(r.e->'description')='string' THEN nullif(left(btrim(r.e->>'description'),1000),'') END;
  v_stock:=upper(btrim(coalesce(r.e->>'stock',r.e->>'stock_number','')));
  v_ro:=upper(btrim(coalesce(r.e->>'ro',r.e->>'repair_order_number','')));
  v_line_txt:=btrim(coalesce(r.e->>'line',r.e->>'original_line_number',''));
  v_po:=upper(regexp_replace(btrim(coalesce(r.e->>'po','')),'\s+','','g'));
  IF jsonb_typeof(r.e) IS DISTINCT FROM 'object' THEN v_status:='invalid_row';
  ELSIF v_po='' THEN v_status:='ignored_blank_po';
  ELSIF v_po='ALL' THEN v_status:='ignored_all_placeholder';
  ELSIF v_po !~ '^GP[0-9]{8}$' THEN v_status:='held_non_gp_po';
  ELSIF v_stock='' OR length(v_stock)>40 THEN v_status:='invalid_stock';
  ELSIF v_ro !~ '^[A-Z0-9][A-Z0-9/_-]{1,39}$' THEN v_status:='invalid_ro';
  ELSIF v_line_txt !~ '^[0-9]{1,4}$' OR v_line_txt::integer<1 THEN v_status:='invalid_line';
  ELSIF v_seen ? (v_stock||'|'||v_ro||'|'||v_line_txt||'|'||v_po) THEN v_status:='duplicate_in_file';
  END IF;
  IF v_status IS NULL THEN
   v_seen:=v_seen||jsonb_build_object(v_stock||'|'||v_ro||'|'||v_line_txt||'|'||v_po,true);
   v_line:=v_line_txt::integer;
   SELECT count(*),min(v.id::text)::uuid,min(v.lifecycle_state::text) INTO v_n,v_vid,v_ls FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_stock;
   IF v_n=0 THEN v_status:='unmatched_stock_not_on_board';
   ELSIF v_n>1 THEN v_status:='held_stock_ambiguous';
   ELSIF EXISTS(SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.vehicle_id=v_vid AND h.released_at IS NULL) THEN v_status:='skipped_owner_hold';
   ELSIF v_ls='rft' THEN v_status:='skipped_vehicle_rft';
   ELSIF v_ls='completed' THEN v_status:='skipped_vehicle_completed';
   ELSIF v_ls IS DISTINCT FROM 'active' THEN v_status:='skipped_vehicle_not_active';
   ELSE
    SELECT count(*),count(*) FILTER (WHERE j.closed_at IS NULL) INTO v_jobs,v_open FROM pdc_parts_private.jobs j
     WHERE j.vehicle_id=v_vid AND upper(btrim(j.ro_number))=v_ro;
    IF v_jobs>0 AND v_open=0 THEN v_status:='skipped_job_closed';
    ELSE
     IF NOT v_lines ? v_vid::text THEN v_lines:=v_lines||jsonb_build_object(v_vid::text,public.pdc_qc_operation_lines_379(v_vid)); END IF;
     SELECT count(*),min(l::text)::jsonb INTO v_n,v_l FROM jsonb_array_elements(v_lines->(v_vid::text)) l
      WHERE upper(btrim(coalesce(l->>'job_card_number','')))=v_ro AND btrim(coalesce(l->>'original_line_number',''))=v_line::text;
     v_key:=pdc_work_categories_private.sublet_line_key_439(v_l);
     IF v_n=0 THEN v_status:='unmatched_line_not_on_job_card';
     ELSIF v_n>1 THEN v_status:='held_line_ambiguous';
     ELSIF NOT coalesce((v_l->>'active')::boolean,true) OR coalesce((v_l->>'rejected')::boolean,false) THEN v_status:='skipped_line_inactive';
     ELSIF coalesce((v_l->>'completed')::boolean,false) THEN v_status:='skipped_line_completed';
     ELSIF upper(btrim(coalesce(v_l->>'stage_code','')))='JOB_CARD_NOTES' THEN v_status:='skipped_notes_line';
     ELSIF v_key IS NULL OR v_key<>'jc:'||v_ro||':'||v_line THEN v_status:='held_line_without_identity';
     ELSIF EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 x WHERE x.vehicle_id=v_vid AND x.line_key=v_key AND x.po_number=v_po) THEN
      v_status:='already_attached';
      SELECT x.description INTO v_cur_desc FROM public.pdc_service_line_po_refs_439 x WHERE x.vehicle_id=v_vid AND x.line_key=v_key AND x.po_number=v_po;
      v_desc_status:=CASE WHEN v_desc IS NULL THEN 'none' WHEN v_desc IS NOT DISTINCT FROM v_cur_desc THEN 'unchanged' ELSE 'set' END;
      IF NOT v_dry THEN
       UPDATE public.pdc_service_line_po_refs_439 SET last_seen_at=v_now,last_source_file_sha256=v_sha,active=true,
        description=coalesce(v_desc,description),
        description_source_file_sha256=CASE WHEN v_desc IS NOT NULL AND v_desc IS DISTINCT FROM description THEN v_sha ELSE description_source_file_sha256 END
        WHERE vehicle_id=v_vid AND line_key=v_key AND po_number=v_po;
      END IF;
     ELSE
      v_status:='attached';
      v_desc_status:=CASE WHEN v_desc IS NULL THEN 'none' ELSE 'set' END;
      IF NOT v_dry THEN
       INSERT INTO public.pdc_service_line_po_refs_439(vehicle_id,line_key,po_number,ro_number,line_no,line_identity,active,
        first_seen_at,last_seen_at,first_source_file_sha256,last_source_file_sha256,created_by,description,description_source_file_sha256)
       VALUES(v_vid,v_key,v_po,v_ro,v_line,v_l->>'line_identity',true,v_now,v_now,v_sha,v_sha,v_actor,v_desc,CASE WHEN v_desc IS NOT NULL THEN v_sha END)
       ON CONFLICT(vehicle_id,line_key,po_number) DO NOTHING;
      END IF;
     END IF;
    END IF;
   END IF;
  END IF;
  IF v_status IN ('attached','already_attached') THEN
   v_veh:=jsonb_set(v_veh,ARRAY[v_vid::text],to_jsonb(coalesce((v_veh->>(v_vid::text))::integer,0)+1));
  END IF;
  v_out:=v_out||(jsonb_build_object('row',r.o,'status',v_status,'stock',nullif(v_stock,''),'ro',nullif(v_ro,''),'line',nullif(v_line_txt,''),
   'po',nullif(left(v_po,40),''),'category',v_l->>'stage_code')||CASE WHEN v_desc_status IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('description',v_desc_status) END);
 END LOOP;
 v_res:=jsonb_build_object('ok',true,'contract','pdc-sublet-po-import-439','dry_run',v_dry,'replay',false,'source_file_sha256',v_sha,
  'request_sha256',v_req,'actor_role',v_role,'rows',jsonb_array_length(p_rows),
  'totals',(SELECT jsonb_object_agg(s,n) FROM (SELECT x->>'status' s,count(*) n FROM jsonb_array_elements(v_out) x GROUP BY 1) z),
  'lines_with_po',(SELECT count(DISTINCT (x->>'stock')||'|'||(x->>'ro')||'|'||(x->>'line')) FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached')),
  'vehicles_with_po',(SELECT count(*) FROM jsonb_object_keys(v_veh)),
  'distinct_pos',(SELECT count(DISTINCT x->>'po') FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached')),
  'by_category',coalesce((SELECT jsonb_object_agg(c,n) FROM (SELECT coalesce(x->>'category','?') c,count(*) n FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached') GROUP BY 1) z),'{}'::jsonb),
  'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,
  'descriptions',coalesce((SELECT jsonb_object_agg(d,n) FROM (SELECT x->>'description' d,count(*) n FROM jsonb_array_elements(v_out) x WHERE x ? 'description' GROUP BY 1) z),'{}'::jsonb),
  'row_statuses',v_out);
 IF NOT v_dry THEN
  INSERT INTO public.pdc_sublet_po_import_receipts_439(receipt_id,source_file_sha256,request_sha256,actor,actor_role,response)
  VALUES(extensions.uuid_generate_v5('43900000-0000-5000-8000-000000000439'::uuid,'import:'||v_sha||':'||v_req),v_sha,v_req,v_actor,v_role,v_res);
  PERFORM public.audit_pdc_event('update','pdc_service_line_po_refs_439',NULL,NULL,NULL,NULL,
   jsonb_build_object('action','import_sublet_pos_439','source_file_sha256',v_sha,'request_sha256',v_req,'actor',v_actor,'actor_role',v_role,
    'totals',v_res->'totals','lines_with_po',v_res->'lines_with_po','vehicles_with_po',v_res->'vehicles_with_po'));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 END IF;
 RETURN v_res;
END
$f$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.sublet_po_vehicle_439(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r439 (F50, Craig 14:37 AWST): the lines of one vehicle that carry a GP purchase order, with their POs and 'sublet done'
 -- ticks, and the vehicle's Sublet box state: none (no GP PO line), ordered (orange: a GP PO line not yet ticked) or done
 -- (green: every GP PO line ticked). Read only; lines keep their own category, bay and booking (sublet contractors come on
 -- site and are never booked into bays).
 RETURN (
 WITH l AS MATERIALIZED (
  SELECT x.l, x.ord, pdc_work_categories_private.sublet_line_key_439(x.l) k
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY x(l,ord)
  WHERE coalesce((x.l->>'active')::boolean,true) AND NOT coalesce((x.l->>'rejected')::boolean,false)
 ), j AS (
  SELECT l.*, t.ticked, t.ticked_by_email, t.ticked_role, t.ticked_at, coalesce(t.version,0) version,
   (SELECT jsonb_agg(r.po_number ORDER BY r.po_number) FROM public.pdc_service_line_po_refs_439 r
     WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.line_key=l.k) pos,
   -- r444 (F57): each PO with its 'Description of sublet' from the upload (null until one has been imported)
   (SELECT jsonb_agg(jsonb_build_object('po_number',r.po_number,'description',r.description) ORDER BY r.po_number) FROM public.pdc_service_line_po_refs_439 r
     WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.line_key=l.k) pod
  FROM l LEFT JOIN public.pdc_sublet_line_ticks_439 t ON t.vehicle_id=p_vehicle_id AND t.line_key=l.k
  WHERE l.k IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.line_key=l.k)
 )
 SELECT jsonb_build_object('vehicle_id',p_vehicle_id,
  'total',count(*),'ticked',count(*) FILTER (WHERE coalesce(ticked,false)),'with_po',count(*),
  'state',CASE WHEN count(*)=0 THEN 'none' WHEN bool_and(coalesce(ticked,false)) THEN 'done' ELSE 'ordered' END,
  'lines',coalesce(jsonb_agg(jsonb_build_object('line_key',k,'line_identity',l->>'line_identity','job_card_number',l->>'job_card_number',
    'line_no',l->'original_line_number','operation_no',l->>'operation_no','description',left(coalesce(l->>'description',''),180),
    'category',l->>'stage_code','completed',coalesce((l->>'completed')::boolean,false),
    'po_numbers',coalesce(pos,'[]'::jsonb),'po_details',coalesce(pod,'[]'::jsonb),'has_po',true,'ticked',coalesce(ticked,false),'ticked_by_email',ticked_by_email,
    'ticked_role',ticked_role,'ticked_at',ticked_at,'version',version,'tickable',true) ORDER BY ord) FILTER (WHERE true),'[]'::jsonb))
 FROM j);
END
$f$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.service_sublet_po_feed_442(p_preview_batch_id uuid, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $f$
DECLARE
 v_sha text; v_rows jsonb; v_res jsonb; v_coll jsonb; v_state text; v_msg text; v_exc jsonb;
BEGIN
 -- r442 (F54, Craig 21 Oct 15:08 AWST): the sublet POs of a service file go into the r439 PO tables as part of the same
 -- service apply, so PMB Email makes one call. Reads the preview batch's stored source rows: a w/Sublet row carries every
 -- distinct PO of its collapsed line in raw_row.sublet_pos (array); an r439 CSV / workbook row carries one in
 -- raw_row.sublet_columns."PO #". Each (stock, R/O, line, PO) goes through public.import_sublet_pos_439 unchanged (GP POs
 -- only, never clears a tick, never removes a PO, never creates or recategorises a line, never touches a bay or booking;
 -- owner-held, RFT, completed, inactive vehicles, closed jobs, completed / inactive / notes lines skipped), keyed by the
 -- source workbook hash. A file without POs is a no-op. A PO failure is reported (ok false, with the error) and rolled back
 -- on its own; it never undoes the service apply. p_dry_run true writes nothing (PMB Email may call it after a preview).
 SELECT b.source_link->>'workbook_sha256' INTO v_sha FROM public.pdc_pilbara_service_import_batches b
  WHERE b.batch_id=p_preview_batch_id AND b.batch_kind='preview' AND b.importer_version='pilbara_service_open_jobcards_v1';
 IF NOT FOUND THEN
  RETURN jsonb_build_object('contract','pdc-service-sublet-po-feed-442','ok',false,'code','preview_batch_not_found','dry_run',coalesce(p_dry_run,true));
 END IF;
 -- r444 (F57): each PO carries its 'Description of sublet' when the row has one (w/Sublet: raw_row.sublet_po_descriptions
 -- keyed by PO; r439 CSV / workbook: sublet_columns."Description of sublet"); no description = no key (never clears).
 SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('stock',coalesce(r.stock_number,''),'ro',coalesce(r.repair_order_number,''),
   'line',coalesce(r.original_line_number::text,''),'po',p.po,'description',CASE
     WHEN jsonb_typeof(r.raw_row->'sublet_po_descriptions')='object' AND jsonb_typeof(r.raw_row->'sublet_po_descriptions'->p.po)='string' THEN r.raw_row->'sublet_po_descriptions'->>p.po
     WHEN jsonb_typeof(r.raw_row->'sublet_columns')='object' AND jsonb_typeof(r.raw_row->'sublet_columns'->'Description of sublet')='string' THEN r.raw_row->'sublet_columns'->>'Description of sublet' END)) ORDER BY r.source_order,p.o),'[]'::jsonb)
  INTO v_rows
  FROM public.pdc_pilbara_service_import_rows r
  CROSS JOIN LATERAL (
   SELECT q.e#>>'{}' AS po, q.o FROM jsonb_array_elements(CASE
     WHEN jsonb_typeof(r.raw_row->'sublet_pos')='array' THEN r.raw_row->'sublet_pos'
     WHEN jsonb_typeof(r.raw_row->'sublet_columns')='object' AND btrim(coalesce(r.raw_row->'sublet_columns'->>'PO #',''))<>''
      THEN jsonb_build_array(r.raw_row->'sublet_columns'->>'PO #')
     ELSE '[]'::jsonb END) WITH ORDINALITY q(e,o)
   WHERE jsonb_typeof(q.e)='string' AND btrim(q.e#>>'{}')<>'') p
  WHERE r.batch_id=p_preview_batch_id;
 SELECT jsonb_build_object('rule','r442_one_row_per_dept_ro_line','hours_summed',false,
   'lines',count(*) FILTER (WHERE r.raw_row ? 'collapse'),
   'lines_with_repeats',count(*) FILTER (WHERE r.raw_row->'collapse'->'source_rows' > '1'::jsonb),
   'source_rows',coalesce(sum(jsonb_array_length(r.raw_row->'source_row_numbers')) FILTER (WHERE jsonb_typeof(r.raw_row->'source_row_numbers')='array'),0),
   'conflicts',coalesce(jsonb_agg(jsonb_build_object('stock',r.stock_number,'ro',r.repair_order_number,'line',r.original_line_number,
      'fields',(SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb) FROM jsonb_object_keys(CASE WHEN jsonb_typeof(r.raw_row->'collapse'->'differing_values')='object' THEN r.raw_row->'collapse'->'differing_values' ELSE '{}'::jsonb END) k),
      'kept','first_row_in_source_order') ORDER BY r.source_order) FILTER (WHERE r.raw_row->'collapse'->>'conflict'='true'),'[]'::jsonb))
  INTO v_coll FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=p_preview_batch_id;
 IF jsonb_array_length(v_rows)=0 THEN
  v_res:=jsonb_build_object('ok',true,'contract','pdc-sublet-po-import-439','dry_run',coalesce(p_dry_run,true),'replay',false,'rows',0,'note','no_po_in_file',
   'totals','{}'::jsonb,'lines_with_po',0,'vehicles_with_po',0,'distinct_pos',0,'by_category','{}'::jsonb,
   'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,'row_statuses','[]'::jsonb);
 ELSE
  BEGIN
   v_res:=public.import_sublet_pos_439(v_rows,v_sha,coalesce(p_dry_run,true));
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE, v_msg=MESSAGE_TEXT;
   v_res:=jsonb_build_object('ok',false,'code','sublet_po_feed_failed','sqlstate',v_state,'message',left(v_msg,300),
    'retry','public.import_sublet_pos_439(rows, source workbook sha256, false) with the same file');
  END;
 END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'row')::integer),'[]'::jsonb) INTO v_exc FROM jsonb_array_elements(coalesce(v_res->'row_statuses','[]'::jsonb)) x
  WHERE x->>'status' NOT IN ('attached','already_attached','duplicate_in_file','ignored_blank_po');
 RETURN jsonb_build_object('contract','pdc-service-sublet-po-feed-442','ok',coalesce((v_res->>'ok')::boolean,false),
  'dry_run',coalesce(p_dry_run,true),'source_file_sha256',v_sha,'po_rows',jsonb_array_length(v_rows),
  'replay',coalesce((v_res->>'replay')::boolean,false),
  'totals',coalesce(v_res->'totals','{}'::jsonb),'lines_with_po',coalesce(v_res->'lines_with_po','0'::jsonb),
  'vehicles_with_po',coalesce(v_res->'vehicles_with_po','0'::jsonb),'distinct_pos',coalesce(v_res->'distinct_pos','0'::jsonb),
  'by_category',coalesce(v_res->'by_category','{}'::jsonb),
  'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,'ticks_cleared',0,'pos_removed',0,
  'import',v_res-'row_statuses','exceptions',v_exc,'collapse',v_coll);
END
$f$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006(p_rows jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $f$
 SELECT coalesce(jsonb_typeof(p_rows)='array' AND jsonb_array_length(p_rows)>0
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE
 coalesce(x->>'department','') NOT IN ('138','139')
 OR x->'raw_row'->>'Dept' IS DISTINCT FROM x->>'department'
 OR x->'raw_row'->>'Company' IS DISTINCT FROM '01'
 OR x->'raw_row'->>'Division' IS DISTINCT FROM '1'
 OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' IS DISTINCT FROM 'pmbcontroller@gmail.com'
 OR NOT coalesce(
  x->'raw_row'->>'email_subject'='PMG PD Service Complete'
  OR (x->'raw_row'->>'email_subject'='CW PMB Service Complete'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_csv'
   AND x->'raw_row'->>'source_filename'='.csv'
   AND x->'raw_row'->>'scope_provenance'='craig_20261019_fixed_company01_division1')
  -- r442 (F54): a w/Sublet line: no Type key, every distinct PO in sublet_pos, the source rows it came from, hours not summed
  OR (x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet'
   AND x->'raw_row'->>'source_kind'='revolution_automated_service_workbook'
   AND NOT (x->'raw_row' ? 'Type')
   AND x->'raw_row'->>'line_collapse'='r442_one_row_per_dept_ro_line'
   AND jsonb_typeof(x->'raw_row'->'sublet_pos')='array'
   AND jsonb_typeof(x->'raw_row'->'source_row_numbers')='array'
   AND jsonb_array_length(x->'raw_row'->'source_row_numbers')>0
   AND jsonb_typeof(x->'raw_row'->'collapse')='object'
   AND x->'raw_row'->'collapse'->'hours_summed'='false'::jsonb
   AND x->'raw_row'->'collapse'->'source_rows'=to_jsonb(jsonb_array_length(x->'raw_row'->'source_row_numbers'))
   -- r444 (F57): optional sublet_po_descriptions: an object keyed by POs of this line (sublet_pos), string values up to 4000 characters
   AND (NOT (x->'raw_row' ? 'sublet_po_descriptions')
    OR (jsonb_typeof(x->'raw_row'->'sublet_po_descriptions')='object'
     AND NOT EXISTS(SELECT 1 FROM jsonb_each(x->'raw_row'->'sublet_po_descriptions') d
      WHERE jsonb_typeof(d.value)<>'string' OR length(d.value#>>'{}')>4000 OR NOT (x->'raw_row'->'sublet_pos') ? d.key)))),false)
 OR coalesce(x->>'repair_order_number','') !~ ('^J'||(x->>'department')||'[0-9]+$'))
 -- r442 (F54): a w/Sublet file is all w/Sublet rows, exactly one per Dept + R/O + Line # (never a repeated line, so never summed hours)
 AND (SELECT count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet') IN (0,count(*))
       AND count(*) FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
        =count(DISTINCT (x->>'department')||'|'||upper(x->>'repair_order_number')||'|'||coalesce(x->>'original_line_number',x->'raw_row'->>'Line #',''))
          FILTER (WHERE x->'raw_row'->>'email_subject'='PMG PD Service Complete w/Sublet')
      FROM jsonb_array_elements(p_rows) x),false);
$f$;


UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6083fb5bcf03d341d9101831c2217cb8',release='r444',note='r444 (F57): optional description per row, stored on attach, refreshed when non-blank, never cleared (was 6cc118c512e103e33bfe94118b91d8a1 r439)',updated_at=now() WHERE signature='public.import_sublet_pos_439(jsonb,text,boolean)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='756b7a4164a6e9ce37bb33c7c861b346',release='r444',note='r444 (F57): lines carry po_details (PO + description) (was bf4f60277f69b53cbd982c7aa24b2401 r439)',updated_at=now() WHERE signature='pdc_work_categories_private.sublet_po_vehicle_439(uuid)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='66379d312c3fddfd2eaab5b37c0ba497',release='r444',note='r444 (F57): passes each PO description (sublet_po_descriptions / sublet_columns) (was 6119632a2c961505b8875d1f0dcbdbaa r442)',updated_at=now() WHERE signature='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0534336e01558066cf7ec3dcb3995cd4',release='r444',note='r444 (F57): optional raw_row.sublet_po_descriptions (object keyed by the line POs, strings) (was fd1d9272719cba74fdca23f9015d6d08 r442)',updated_at=now() WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sublet_po_descriptions_444','F57','Sublet descriptions (r444): GP PO refs carry the ''Description of sublet'' from the upload (description + source hash, at most 1000 characters, RLS, no app-role access); import_sublet_pos_439 stores it on attach and refreshes it only when non-blank (never clears) and still writes PO refs only; the vehicle payload has po_details; the r442 feed passes raw_row.sublet_po_descriptions / sublet_columns descriptions and writes nothing itself; the row validator accepts the optional object only when keyed by the line''s POs with string values; ticks untouched and audited',
  $chk$WITH src AS (
 SELECT (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.import_sublet_pos_439(jsonb,text,boolean)')) imp,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.sublet_po_vehicle_439(uuid)')) veh,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)')) feed
), rw AS (
 SELECT jsonb_build_object('department','139','repair_order_number','J139000444','original_line_number',4,'raw_row',jsonb_build_object('Dept','139','Company','01','Division','1',
  'from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com','email_subject','PMG PD Service Complete w/Sublet',
  'source_kind','revolution_automated_service_workbook','line_collapse','r442_one_row_per_dept_ro_line','sublet_pos','["GP13900444","GP13900445"]'::jsonb,
  'sublet_po_descriptions',jsonb_build_object('GP13900444','Sample sublet^Key 1'),
  'source_row_numbers','[5,6]'::jsonb,'collapse',jsonb_build_object('rule','r442_one_row_per_dept_ro_line','source_rows',2,'hours_summed',false,'conflict',false))) r
), dry AS (
 SELECT public.import_sublet_pos_439(jsonb_build_array(
   jsonb_build_object('stock','R444-NO-SUCH-STOCK','ro','J139000444','line',1,'po','GP13900444','description','Sample sublet'),
   jsonb_build_object('stock','R444-NO-SUCH-STOCK','ro','J139000444','line',2,'po','All','description','x')),repeat('0',64),true) r
), w AS (
 SELECT
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='pdc_service_line_po_refs_439' AND column_name IN ('description','description_source_file_sha256'))=2
   AND (SELECT relrowsecurity AND NOT has_table_privilege('authenticated',oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('anon',oid,'SELECT') FROM pg_catalog.pg_class WHERE oid=to_regclass('public.pdc_service_line_po_refs_439'))
   AND NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 WHERE description IS NOT NULL AND (length(description) NOT BETWEEN 1 AND 1000 OR description_source_file_sha256 IS NULL)) AS store,
  position('description=coalesce(v_desc,description)' in src.imp)>0 AND src.imp !~* 'description\s*=\s*(NULL|v_desc\s*[,\n])'
   AND src.imp !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_pilbara_service_operations|pdc_sublet_line_ticks_439)\b' AS never_clears,
  dry.r->'totals'='{"unmatched_stock_not_on_board":1,"ignored_all_placeholder":1}'::jsonb AND dry.r->'descriptions'='{}'::jsonb AND (dry.r->>'dry_run')::boolean AS importer,
  position($q$'po_details',coalesce(pod,'[]'::jsonb)$q$ in src.veh)>0 AS payload,
  position('sublet_po_descriptions' in src.feed)>0 AND position('jsonb_strip_nulls' in src.feed)>0 AND src.feed !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.' AS feed,
  pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r))
   AND pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(rw.r #- '{raw_row,sublet_po_descriptions}'))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,sublet_po_descriptions}','{"GP13900999":"x"}')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,sublet_po_descriptions}','{"GP13900444":1}')))
   AND NOT pdc_codex_intake_private.revolution_service_rows_20261006(jsonb_build_array(jsonb_set(rw.r,'{raw_row,sublet_po_descriptions}','["x"]'))) AS rows_contract,
  (SELECT coalesce(sum(t.version),0) FROM public.pdc_sublet_line_ticks_439 t)=(SELECT count(*) FROM public.pdc_sublet_line_tick_history_439) AS ticks_audited
 FROM src, rw, dry
)
SELECT w.store AND w.never_clears AND w.importer AND w.payload AND w.feed AND w.rows_contract AND w.ticks_audited AS ok,
 format('%s of %s active GP PO refs have a sublet description (%s vehicles); store %s, import never clears %s, importer dry run %s, po_details %s, feed passes descriptions %s, row contract %s, ticks audited %s',
  (SELECT count(*) FROM public.pdc_service_line_po_refs_439 WHERE active AND description IS NOT NULL),(SELECT count(*) FROM public.pdc_service_line_po_refs_439 WHERE active),
  (SELECT count(DISTINCT vehicle_id) FROM public.pdc_service_line_po_refs_439 WHERE active AND description IS NOT NULL),
  w.store,w.never_clears,w.importer,w.payload,w.feed,w.rows_contract,w.ticks_audited) AS detail
FROM w
$chk$,true,243,'r444');
DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6083fb5bcf03d341d9101831c2217cb8'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_po_vehicle_439(uuid)'::regprocedure)<>'756b7a4164a6e9ce37bb33c7c861b346'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)<>'66379d312c3fddfd2eaab5b37c0ba497'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)<>'0534336e01558066cf7ec3dcb3995cd4' THEN RAISE EXCEPTION 'r444: functions did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r444')<>4 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>157 THEN RAISE EXCEPTION 'r444: pins not written'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_work_categories_private.sublet_po_vehicle_439(uuid)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)='{postgres=X/postgres}'
    AND (SELECT proacl::text FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)='{postgres=X/postgres}') THEN RAISE EXCEPTION 'r444: unexpected function grants'; END IF;
END $g$;
