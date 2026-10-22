-- r471 (F84; reported by Kajel, PMB Email bot; Craig approved the first retirement in chat 22 Oct 2026 09:33 AWST): a service
-- line that Revolution re-sends with the vehicle's bay / parts-location code appended ('DE MINE SPEC' -> 'DE MINE SPEC 05K4F')
-- was imported as a SECOND version of the same Dept + R/O + Line # (pdc_pilbara_service_operations is append-only and keys a
-- version on its description). Two live versions make the next native preview refuse the stock
-- (pdc_tune_operation_change_candidate_20260912: ambiguous_existing_operation), so PMB Email holds the whole stock.
-- Staging cdsmnqxtyyoeoznmbidd only. This migration adds the MECHANISM only; it retires nothing by itself:
-- (1) public.pdc_service_operation_supersessions_471: one row per retired ("superseded") operation version, naming the
--     version kept, the rule ('owner_decision' or 'trailing_bay_code_471'), the approver and reason, the board line before
--     and the adjustment used. Append-only (delete only inside the r471 undo), RLS, no app-role access.
-- (2) pdc_service_supersede_private.supersede_operation_471(retire, keep, rule, approved_by, reason, live_booking_ok):
--     same vehicle / stock / Dept / R/O / Line # only; refuses completed, rejected, PIT-ticked or Auditor-evidence lines, a
--     pending change review on the retired version, an inactive or protected board line, a kept version that is itself retired, and (unless
--     live_booking_ok) a live booking on the retired line's stage. The retired version's board line source:<id> is made
--     inactive the native way (vehicle_workshop_line_adjustments, active=false, locked, manual_operator - the same overlay
--     remove_pdc_workshop_operation_line_235 writes); the kept line must read back unchanged. The operation rows and their
--     history are never edited or deleted. Not executable by any app role.
-- (3) pdc_service_supersede_private.bay_code_same_line_471(a, b): the SQL twin of the preparer rule (whole trailing bay
--     code token [0-9]{2}[A-Z][0-9][A-Z], optionally after ' -' / ' --'; the rest equal apart from case and spacing).
-- (4) pdc_tune_operation_change_candidate_20260912: counts and picks only versions NOT in the supersession table (two
--     NOT EXISTS clauses; nothing else changes). Before r471 it was unpinned; it is pinned now.
-- Not touched: workshop_clock_tick, the service preview / apply functions (375bffc2 / fc3717a5), the manifest and row
-- validator, the operation and history tables, bookings, bays, vehicles, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r471: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r471: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r471: clock tick changed since prepared (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r471: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'cc5dee40fa5a86fc1caa3704af318744'
    OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_772_protect_source_projection()'::regprocedure)<>'b47709fd384dd20db09ac96cc1b305c7'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.base_pdc_qc_operation_lines_379(uuid)'::regprocedure)<>'a93005010cf96ab6eb804ef879039861' THEN RAISE EXCEPTION 'r471: service import / board line functions are not the expected versions'; END IF;
 IF to_regclass('public.pdc_service_operation_supersessions_471') IS NOT NULL OR to_regnamespace('pdc_service_supersede_private') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r471' OR signature='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471' OR added_in='r471') THEN RAISE EXCEPTION 'r471: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=270 OR fault_id='F84') THEN RAISE EXCEPTION 'r471: sort_order 270 / F84 taken'; END IF;
 PERFORM set_config('pdc.r471_pins_before',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE SCHEMA pdc_service_supersede_private;
REVOKE ALL ON SCHEMA pdc_service_supersede_private FROM PUBLIC;
REVOKE ALL ON SCHEMA pdc_service_supersede_private FROM anon, authenticated, service_role;

CREATE TABLE public.pdc_service_operation_supersessions_471 (
 superseded_operation_id uuid PRIMARY KEY REFERENCES public.pdc_pilbara_service_operations(operation_id) ON DELETE RESTRICT,
 kept_operation_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_operations(operation_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 department text NOT NULL,
 repair_order_number text NOT NULL,
 original_line_number integer NOT NULL CHECK (original_line_number > 0),
 rule text NOT NULL CHECK (rule IN ('owner_decision','trailing_bay_code_471')),
 approved_by text NOT NULL CHECK (length(btrim(approved_by)) BETWEEN 3 AND 200),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
 adjustment_id uuid NOT NULL REFERENCES public.vehicle_workshop_line_adjustments(adjustment_id) ON DELETE RESTRICT,
 adjustment_created boolean NOT NULL,
 before_adjustment jsonb CHECK (before_adjustment IS NULL OR jsonb_typeof(before_adjustment)='object'),
 before_line jsonb NOT NULL CHECK (jsonb_typeof(before_line)='object'),
 kept_line jsonb NOT NULL CHECK (jsonb_typeof(kept_line)='object'),
 live_booking_ok boolean NOT NULL DEFAULT false,
 release text NOT NULL DEFAULT 'r471' CHECK (release='r471'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK (superseded_operation_id <> kept_operation_id),
 CHECK ((adjustment_created AND before_adjustment IS NULL) OR (NOT adjustment_created AND before_adjustment IS NOT NULL))
);
CREATE INDEX pdc_service_operation_supersessions_471_kept ON public.pdc_service_operation_supersessions_471(kept_operation_id);
ALTER TABLE public.pdc_service_operation_supersessions_471 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_service_operation_supersessions_471 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_service_operation_supersessions_471 IS 'r471 (F84): retired service operation versions (append-only; the kept version stays the live line).';

CREATE FUNCTION pdc_service_supersede_private.append_only_471()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r471: rows are written once; only the r471 undo (which sets pdc.r471_undo to the row's superseded id) may delete one.
 IF TG_OP='DELETE' AND current_setting('pdc.r471_undo',true) IS NOT DISTINCT FROM OLD.superseded_operation_id::text THEN RETURN OLD; END IF;
 RAISE EXCEPTION 'r471: pdc_service_operation_supersessions_471 is append-only' USING errcode='55000';
END $f$;
REVOKE ALL ON FUNCTION pdc_service_supersede_private.append_only_471() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER pdc_service_operation_supersessions_471_append_only BEFORE UPDATE OR DELETE ON public.pdc_service_operation_supersessions_471
 FOR EACH ROW EXECUTE FUNCTION pdc_service_supersede_private.append_only_471();
CREATE TRIGGER pdc_service_operation_supersessions_471_no_truncate BEFORE TRUNCATE ON public.pdc_service_operation_supersessions_471
 FOR EACH STATEMENT EXECUTE FUNCTION pdc_service_supersede_private.append_only_471();

CREATE FUNCTION pdc_service_supersede_private.bay_code_same_line_471(p_a text, p_b text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog'
AS $f$
 -- r471: true when two different descriptions differ ONLY by a whole trailing bay code token (added, removed or changed),
 -- optionally after ' -' / ' --', plus letter case and spacing. Twin of same_line_ignoring_bay_code() in
 -- tools/import-rules/revolution_service_wsublet.py.
 WITH d AS (SELECT btrim(regexp_replace(coalesce(p_a,''),'\s+',' ','g')) a, btrim(regexp_replace(coalesce(p_b,''),'\s+',' ','g')) b),
 s AS (SELECT a, b,
   a ~ '\S(\s+-{1,2})?\s+[0-9]{2}[A-Z][0-9][A-Z]$' ac, b ~ '\S(\s+-{1,2})?\s+[0-9]{2}[A-Z][0-9][A-Z]$' bc,
   regexp_replace(a,'(\s+-{1,2})?\s+[0-9]{2}[A-Z][0-9][A-Z]$','') ast, regexp_replace(b,'(\s+-{1,2})?\s+[0-9]{2}[A-Z][0-9][A-Z]$','') bst FROM d)
 SELECT a<>'' AND b<>'' AND a<>b AND (ac OR bc)
   AND lower(CASE WHEN ac THEN ast ELSE a END)=lower(CASE WHEN bc THEN bst ELSE b END)
 FROM s
$f$;
REVOKE ALL ON FUNCTION pdc_service_supersede_private.bay_code_same_line_471(text,text) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_service_supersede_private.supersede_operation_471(p_superseded uuid, p_kept uuid, p_rule text, p_approved_by text, p_reason text, p_live_booking_ok boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $f$
DECLARE
 s public.pdc_pilbara_service_operations%rowtype; k public.pdc_pilbara_service_operations%rowtype; v public.vehicles%rowtype;
 a_before public.vehicle_workshop_line_adjustments%rowtype; a_after public.vehicle_workshop_line_adjustments%rowtype; has_adj boolean;
 line_before jsonb; line_after jsonb; kept_before jsonb; kept_after jsonb; v_stage text; v_hours numeric; v_desc text;
 v_actor constant uuid:='47100000-0000-5000-8000-000000000471';  -- r471 release actor (no auth user; recorded on the overlay)
 v_kept_fields constant text[]:=ARRAY['line_identity','description','stage_code','estimated_hours','active','completed','job_card_number','operation_no'];
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r471: staging only'; END IF;
 IF p_superseded IS NULL OR p_kept IS NULL OR p_superseded=p_kept OR coalesce(p_rule,'') NOT IN ('owner_decision','trailing_bay_code_471')
    OR length(btrim(coalesce(p_approved_by,''))) NOT BETWEEN 3 AND 200 OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 THEN
  RAISE EXCEPTION 'r471: invalid_input';
 END IF;
 SELECT * INTO s FROM public.pdc_pilbara_service_operations WHERE operation_id=p_superseded;
 IF NOT FOUND THEN RAISE EXCEPTION 'r471: superseded_operation_not_found'; END IF;
 SELECT * INTO k FROM public.pdc_pilbara_service_operations WHERE operation_id=p_kept;
 IF NOT FOUND THEN RAISE EXCEPTION 'r471: kept_operation_not_found'; END IF;
 IF s.vehicle_id IS DISTINCT FROM k.vehicle_id OR s.stock_number IS DISTINCT FROM k.stock_number OR s.department IS DISTINCT FROM k.department
    OR upper(s.repair_order_number) IS DISTINCT FROM upper(k.repair_order_number) OR s.original_line_number IS DISTINCT FROM k.original_line_number THEN
  RAISE EXCEPTION 'r471: not_the_same_line';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-471-supersede:'||s.vehicle_id::text||':'||upper(s.repair_order_number)||':'||s.original_line_number::text,0));
 IF EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x WHERE x.superseded_operation_id=p_superseded) THEN
  IF EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x WHERE x.superseded_operation_id=p_superseded AND x.kept_operation_id=p_kept) THEN
   RETURN jsonb_build_object('ok',true,'code','already_superseded','superseded_operation_id',p_superseded,'kept_operation_id',p_kept);
  END IF;
  RAISE EXCEPTION 'r471: superseded_in_favour_of_another_version';
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x WHERE x.superseded_operation_id=p_kept) THEN RAISE EXCEPTION 'r471: kept_version_is_retired'; END IF;
 IF p_rule='trailing_bay_code_471' AND NOT pdc_service_supersede_private.bay_code_same_line_471(k.operation_description,s.operation_description) THEN
  RAISE EXCEPTION 'r471: rule_trailing_bay_code_does_not_match';
 END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=s.vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number IS DISTINCT FROM s.stock_number THEN RAISE EXCEPTION 'r471: vehicle_protected'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_qc_operation_completions_379 c WHERE c.vehicle_id=v.id AND c.line_identity='source:'||p_superseded::text AND c.completed) THEN RAISE EXCEPTION 'r471: completed_line_protected'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_qc_operation_rejections_381 r WHERE r.vehicle_id=v.id AND r.line_identity='source:'||p_superseded::text AND r.active) THEN RAISE EXCEPTION 'r471: rejected_line_protected'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_pit_line_ticks_401 t WHERE t.vehicle_id=v.id AND t.line_identity='source:'||p_superseded::text AND t.ticked) THEN RAISE EXCEPTION 'r471: pit_ticked_line_protected'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_auditor_finding_evidence e WHERE e.entity_type='operation_line' AND e.entity_id=p_superseded) THEN RAISE EXCEPTION 'r471: auditor_evidence_protected'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews q WHERE q.source_operation_id=p_superseded AND q.status='pending') THEN RAISE EXCEPTION 'r471: open_change_review'; END IF;
 SELECT l INTO line_before FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||p_superseded::text;
 SELECT l INTO kept_before FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||p_kept::text;
 IF line_before IS NULL OR kept_before IS NULL THEN RAISE EXCEPTION 'r471: board_line_missing'; END IF;
 IF (line_before->>'active')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'r471: retired_line_already_inactive'; END IF;
 IF (kept_before->>'active')::boolean IS NOT TRUE OR (kept_before->>'completed')::boolean IS TRUE THEN RAISE EXCEPTION 'r471: kept_line_not_live'; END IF;
 v_stage:=CASE WHEN coalesce(line_before->>'stage_code','') ~ '^[A-Z][A-Z0-9_]{1,39}$' THEN line_before->>'stage_code' ELSE 'UNALLOCATED_MAPPING_REVIEW' END;
 IF NOT coalesce(p_live_booking_ok,false) AND EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages st ON st.id=b.stage_id
     WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status::text NOT IN ('completed','cancelled') AND st.code=v_stage) THEN
  RAISE EXCEPTION 'r471: live_workshop_booking_protected (stage %)',v_stage;
 END IF;
 SELECT * INTO a_before FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=v.id AND a.line_key='source:'||p_superseded::text FOR UPDATE;
 has_adj:=FOUND;
 IF has_adj AND (a_before.active IS NOT TRUE OR a_before.source_kind<>'source' OR a_before.source_operation_line_id IS NOT NULL) THEN RAISE EXCEPTION 'r471: board_overlay_protected'; END IF;
 IF current_setting('pdc.772.explicit_operation_delete',true) IS NOT NULL THEN RAISE EXCEPTION 'r471: pdc.772.explicit_operation_delete is set in this session; use a fresh session'; END IF;
 IF has_adj THEN
  UPDATE public.vehicle_workshop_line_adjustments SET active=false, manual_assignment_locked=true, correction_origin='manual_operator',
   version=version+1, updated_by=v_actor, updated_at=clock_timestamp()
  WHERE adjustment_id=a_before.adjustment_id RETURNING * INTO a_after;
 ELSE
  v_hours:=round(least(greatest(coalesce(nullif(line_before->>'estimated_hours','')::numeric,0),0),999.99),2);
  v_desc:=left(btrim(regexp_replace(regexp_replace(coalesce(line_before->>'description',s.operation_description),'[[:cntrl:]]',' ','g'),'\s+',' ','g')),180);
  v_desc:=btrim(v_desc);
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,
    created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number)
  VALUES(v.id,'source:'||p_superseded::text,'source',v_stage,v_desc,v_hours,false,1,v_actor,v_actor,NULL,NULL,true,'manual_operator',NULL,
    nullif(btrim(coalesce(line_before->>'job_card_number',s.repair_order_number)),''))
  RETURNING * INTO a_after;
 END IF;
 SELECT l INTO line_after FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||p_superseded::text;
 SELECT l INTO kept_after FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'='source:'||p_kept::text;
 IF line_after IS NULL OR (line_after->>'active')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'r471: retired_line_still_active'; END IF;
 IF (SELECT jsonb_object_agg(f,kept_before->f) FROM unnest(v_kept_fields) f) IS DISTINCT FROM (SELECT jsonb_object_agg(f,kept_after->f) FROM unnest(v_kept_fields) f) THEN
  RAISE EXCEPTION 'r471: kept_line_changed %',kept_after;
 END IF;
 INSERT INTO public.pdc_service_operation_supersessions_471(superseded_operation_id,kept_operation_id,vehicle_id,department,repair_order_number,original_line_number,
   rule,approved_by,reason,adjustment_id,adjustment_created,before_adjustment,before_line,kept_line,live_booking_ok)
 VALUES(p_superseded,p_kept,v.id,s.department,s.repair_order_number,s.original_line_number,p_rule,btrim(p_approved_by),btrim(p_reason),
   a_after.adjustment_id,NOT has_adj,CASE WHEN has_adj THEN to_jsonb(a_before) END,line_before,kept_before,coalesce(p_live_booking_ok,false));
 RETURN jsonb_build_object('ok',true,'code','superseded','superseded_operation_id',p_superseded,'kept_operation_id',p_kept,'vehicle_id',v.id,
  'adjustment_id',a_after.adjustment_id,'adjustment_created',NOT has_adj,'adjustment_version',a_after.version,
  'retired_line_after',jsonb_build_object('active',line_after->'active','stage_code',line_after->'stage_code','estimated_hours',line_after->'estimated_hours'),
  'kept_line',(SELECT jsonb_object_agg(f,kept_after->f) FROM unnest(v_kept_fields) f));
END $f$;
REVOKE ALL ON FUNCTION pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.pdc_tune_operation_change_candidate_20260912(vid uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE old public.pdc_pilbara_service_operations%rowtype; prior public.pdc_tune_operation_change_reviews%rowtype;
 base jsonb:='{}'; proposed jsonb; company_name text:=coalesce(p->'raw_row'->>'Company',p->'raw_row'->>'company','');
 division_name text:=coalesce(p->'raw_row'->>'Division',p->'raw_row'->>'division',''); matches integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND visible_on_board AND deleted_at IS NULL) THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicles WHERE id=vid AND stock_number=p->>'stock_number') THEN RETURN jsonb_build_object('conflict','stock_identity_changed'); END IF;
 SELECT count(*) INTO matches FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer
 -- r471 (F84): a version retired by pdc_service_supersede_private.supersede_operation_471 is not a live version of the line
 AND NOT EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 s WHERE s.superseded_operation_id=o.operation_id);
 IF matches>1 THEN RETURN jsonb_build_object('conflict','ambiguous_existing_operation'); END IF;
 SELECT * INTO old FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=vid
 AND o.repair_order_number=p->>'repair_order_number' AND o.original_line_number=(p->>'original_line_number')::integer
 AND NOT EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 s WHERE s.superseded_operation_id=o.operation_id);
 IF old.operation_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r WHERE r.evidence_id=old.raw_evidence_id
     AND (pdc_parts_private.service_scope(r.raw_row,old.stock_number,old.repair_order_number)->>'company')=company_name
     AND (pdc_parts_private.service_scope(r.raw_row,old.stock_number,old.repair_order_number)->>'division')=division_name)
   THEN RETURN jsonb_build_object('conflict','company_division_identity_requires_review'); END IF;
   base:=jsonb_build_object('operation_description',old.operation_description,'source_estimated_hours',old.source_estimated_hours,'department',old.department,'operation_code',old.operation_code);
 END IF;
 SELECT * INTO prior FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=vid AND q.company=company_name AND q.division=division_name
 AND q.repair_order_number=p->>'repair_order_number' AND q.original_line_number=(p->>'original_line_number')::integer AND q.status='approved'
 ORDER BY approved_at DESC,change_id DESC LIMIT 1;
 IF FOUND THEN base:=prior.proposed_source; END IF;
 proposed:=public.pdc_tune_operation_source_signature_20260912(p);
 RETURN jsonb_build_object('needs_review',old.operation_id IS NULL OR proposed IS DISTINCT FROM public.pdc_tune_operation_source_signature_20260912(base),
 'source_operation_id',old.operation_id,'change_kind',CASE WHEN old.operation_id IS NULL THEN 'added' ELSE 'modified' END,
 'before_source',base,'company',company_name,'division',division_name,
 'proposed_hash',encode(extensions.digest(convert_to(proposed::text,'UTF8'),'sha256'),'hex'));
END $function$;

-- signatures are written schema-qualified as literals (a regprocedure cast to text drops 'public.' while public is on the
-- search_path, and protected_function_md5s resolves pins with search_path pg_catalog only: that pin then reads MISSING)
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT v.sig, md5(p.prosrc), 'r471', 'r471 (F84) retired service operation versions + trailing bay code rule', now()
FROM (VALUES ('pdc_service_supersede_private.append_only_471()'),
 ('pdc_service_supersede_private.bay_code_same_line_471(text,text)'),
 ('pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean)'),
 ('public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)')) v(sig)
JOIN pg_proc p ON p.oid=to_regprocedure(v.sig);

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('service_operation_supersede_471','F84','r471: a service line re-sent with a trailing bay code must not leave two live versions: supersession table private and append-only, every retired version names a kept version of the SAME line that is not itself retired, its board line source:<id> is inactive, trailing-bay-code rows really differ only by the code, the change candidate ignores retired versions, and no service line has two live versions that differ only by a trailing bay code without being flagged here.',
$chk$WITH b AS (
 SELECT (SELECT c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')
    FROM pg_catalog.pg_class c WHERE c.oid=to_regclass('public.pdc_service_operation_supersessions_471')) IS TRUE AS table_private,
  (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=to_regclass('public.pdc_service_operation_supersessions_471')
    AND tgname IN ('pdc_service_operation_supersessions_471_append_only','pdc_service_operation_supersessions_471_no_truncate') AND tgenabled='O')=2 AS append_only,
  NOT EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x
    LEFT JOIN public.pdc_pilbara_service_operations s ON s.operation_id=x.superseded_operation_id
    LEFT JOIN public.pdc_pilbara_service_operations k ON k.operation_id=x.kept_operation_id
    WHERE s.operation_id IS NULL OR k.operation_id IS NULL OR s.vehicle_id IS DISTINCT FROM k.vehicle_id OR s.vehicle_id IS DISTINCT FROM x.vehicle_id
     OR s.department IS DISTINCT FROM k.department OR upper(s.repair_order_number) IS DISTINCT FROM upper(k.repair_order_number)
     OR s.original_line_number IS DISTINCT FROM k.original_line_number
     OR EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 y WHERE y.superseded_operation_id=x.kept_operation_id)
     OR (x.rule='trailing_bay_code_471' AND NOT pdc_service_supersede_private.bay_code_same_line_471(k.operation_description,s.operation_description))) AS same_line,
  NOT EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x
    WHERE NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a WHERE a.adjustment_id=x.adjustment_id AND a.vehicle_id=x.vehicle_id
     AND a.line_key='source:'||x.superseded_operation_id::text AND a.active IS FALSE)) AS board_line_inactive,
  (SELECT p.prosrc LIKE '%pdc_service_operation_supersessions_471 s WHERE s.superseded_operation_id=o.operation_id%'
    FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)')) IS TRUE AS candidate_ignores_retired,
  NOT has_schema_privilege('authenticated','pdc_service_supersede_private','USAGE') AND NOT has_schema_privilege('anon','pdc_service_supersede_private','USAGE')
   AND NOT has_function_privilege('service_role','pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean)','EXECUTE') AS grants,
  (SELECT count(*) FROM (SELECT 1 FROM public.pdc_pilbara_service_operations a JOIN public.pdc_pilbara_service_operations c
     ON c.vehicle_id=a.vehicle_id AND upper(c.repair_order_number)=upper(a.repair_order_number) AND c.original_line_number=a.original_line_number AND c.operation_id>a.operation_id
    WHERE pdc_service_supersede_private.bay_code_same_line_471(a.operation_description,c.operation_description)
     AND NOT EXISTS(SELECT 1 FROM public.pdc_service_operation_supersessions_471 x WHERE x.superseded_operation_id IN (a.operation_id,c.operation_id))) z) AS open_bay_code_pairs
)
SELECT b.table_private AND b.append_only AND b.same_line AND b.board_line_inactive AND b.candidate_ignores_retired AND b.grants AS ok,
 format('%s retired service version(s) (%s owner decision, %s trailing bay code); table private %s, append-only %s, same line %s, board line inactive %s, candidate ignores retired %s, grants %s; %s live pair(s) still differ only by a trailing bay code (informational: listed for review, preparer r471 stops new ones)',
  (SELECT count(*) FROM public.pdc_service_operation_supersessions_471),
  (SELECT count(*) FROM public.pdc_service_operation_supersessions_471 WHERE rule='owner_decision'),
  (SELECT count(*) FROM public.pdc_service_operation_supersessions_471 WHERE rule='trailing_bay_code_471'),
  b.table_private,b.append_only,b.same_line,b.board_line_inactive,b.candidate_ignores_retired,b.grants,b.open_bay_code_pairs) AS detail
FROM b
$chk$,true,270,'r471');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r471')<>4
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r471_pins_before')::int+4 THEN RAISE EXCEPTION 'r471: pins not written'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'3781d764a2aedf1bbfddab707a1ccfd9'
    OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r471: change candidate not the prepared version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r471: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744' THEN RAISE EXCEPTION 'r471: preview / apply changed'; END IF;
 IF has_function_privilege('authenticated','pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean)','EXECUTE')
    OR has_function_privilege('service_role','pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean)','EXECUTE')
    OR has_table_privilege('authenticated','public.pdc_service_operation_supersessions_471','SELECT') THEN RAISE EXCEPTION 'r471: unexpected grants'; END IF;
 IF (SELECT count(*) FROM public.pdc_service_operation_supersessions_471)<>0 THEN RAISE EXCEPTION 'r471: the mechanism migration must not retire anything'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471' AND sort_order=270 AND fault_id='F84' AND enabled)<>1 THEN RAISE EXCEPTION 'r471: check missing'; END IF;
 -- run the daily checks this release can affect exactly as fault_regression_check() does (search_path pg_catalog)
 PERFORM set_config('search_path','pg_catalog',true);
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r471' AND to_regprocedure(signature) IS NULL) THEN RAISE EXCEPTION 'r471: a pin does not resolve under search_path pg_catalog'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r471: protected_function_md5s fails: %',x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r471: service_operation_supersede_471 fails: %',x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
