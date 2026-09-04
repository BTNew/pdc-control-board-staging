-- STAGING ONLY: align non-Navision Job Card intake with current Craig authority.
-- This successor retains the 209 recreation wrapper and changes only its private implementation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010500-non-navision-current-contract',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text; v_outer text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations
 WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 v_outer:=pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure);
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260904010400'
    OR to_regprocedure('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)') IS NULL
    OR v_outer NOT LIKE '%pdc_process_non_navision_jobcard_pre209%'
    OR v_outer NOT LIKE '%pdc.recreation_source_hash%'
    OR v_outer NOT LIKE '%pdc.recreation_evidence_hash%'
    OR v_outer NOT LIKE '%pdc.recreation_source_uid%'
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010500')
 THEN RAISE EXCEPTION 'PDC_20260904010500_STAGING_OR_209_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_safe_nonnegative_numeric_20260904(p_value jsonb,p_max numeric)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $safe$
DECLARE n numeric;
BEGIN
 IF jsonb_typeof(p_value)<>'number' THEN RETURN NULL; END IF;
 n:=(p_value#>>'{}')::numeric;
 IF n<0 OR n>p_max OR mod(n,0.01)<>0 THEN RETURN NULL; END IF;
 RETURN n;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $safe$;
REVOKE ALL ON FUNCTION public.pdc_email_safe_nonnegative_numeric_20260904(jsonb,numeric) FROM public,anon,authenticated,service_role;

-- Classification is deterministic. An unknown line is retained as an immutable
-- owner_supplied_document placeholder and sent to mapping review, never dropped.
CREATE OR REPLACE FUNCTION public.pdc_email_jobcard_work_key(p_description text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog,public AS $classify$
DECLARE d text:=public.pdc_email_normalized_clause(p_description);
BEGIN
 d:=regexp_replace(d,'^op[ ]*[-:#/]?[ ]*[0-9]{1,5}[ ]*[-·|:—–]*[ ]*','','i');
 RETURN CASE
  WHEN d~'(^| )(sub|sublet)( |$)' OR d LIKE '%external provider%' OR d LIKE '%paint protection%' OR d~'^!sublet' THEN 'sublet'
  WHEN d~'wheel nut indicator|(^| )(tyres?|tires?|wheel alignment|wheel balance)( |$)|^!tyre' THEN 'tyre'
  WHEN d~'fire extinguisher|(^| )(canopy|tray|fabricat|weld|service body|rops|mine bar|bull ?bar|jacking point)( |$)|^!fab' THEN 'fabrication'
  WHEN d~'(^| )(uhf|radio|electrical|wiring?|spot ?lights?|driving lights?|light bar|reverse beeper|reverse alarm|whip aerial|aerial|dual batter|brake controller|solis)( |$)|^!elec' THEN 'electrical'
  WHEN d~'(^| )(tint|tinting|window film)( |$)|^!tint' THEN 'tint'
  WHEN d~'(^| )(hoist|suspension|gvm|lift kit|weight upgrade)( |$)|^!hoist' THEN 'hoist'
  WHEN d~'(^| )(pit inspection|pit inspect|pit and weigh|roadworthy)( |$)|^!pit' THEN 'pitInspection'
  WHEN d~'(^| )(parts?|purchase order|p[.]?o[.]?|backorder|kit supplied)( |$)|^!parts' THEN 'PARTS'
  WHEN d~'(^| )(bus ?4x4|bus 4 x 4|department 138)( |$)|^!bus' THEN 'bus4x4'
  WHEN d~'(^| )(fit|fitting|install|pre delivery|pre-delivery|long range( fuel)? tank|tow ?bar|winch|snorkel|seat covers?|floor mats?|side steps?|nudge bar|first aid|safety triangle)( |$)|^!fit' THEN 'fitting'
  ELSE 'owner_supplied_document'
 END;
END $classify$;
REVOKE ALL ON FUNCTION public.pdc_email_jobcard_work_key(text) FROM public,anon,authenticated,service_role;

-- Source operation labels are evidence, not canonical operation ordinals. Strip
-- them only for comparison so OP 018/OP018 clauses still bind to the retained
-- source while the submitted operation list remains ordered OP1..OPn.
CREATE OR REPLACE FUNCTION public.pdc_email_jobcard_clause_matches(p_clause text,p_description text,p_hours numeric)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog,public AS $match$
DECLARE c text:=public.pdc_email_normalized_clause(p_clause);d text:=public.pdc_email_normalized_clause(p_description);tail text;unit text;n numeric;
BEGIN
 c:=regexp_replace(c,'^op[ ]*[-:#/]?[ ]*[0-9]{1,5}[ ]*[-·|:—–]*[ ]*','','i');
 IF c NOT LIKE d||' %' THEN RETURN false; END IF;
 tail:=substr(c,length(d)+2);
 IF tail!~'^[0-9]+([.][0-9]{1,2})?[ ]*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)$' THEN RETURN false; END IF;
 BEGIN
  n:=substring(tail from '^([0-9]+([.][0-9]{1,2})?)')::numeric;
  unit:=regexp_replace(tail,'^[0-9]+([.][0-9]{1,2})?[ ]*','');
  IF unit~'^m' THEN n:=n/60.0; END IF;
 EXCEPTION WHEN OTHERS THEN RETURN false; END;
 RETURN n=p_hours;
END $match$;
REVOKE ALL ON FUNCTION public.pdc_email_jobcard_clause_matches(text,text,numeric) FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_non_navision_mapping_reviews_20260904(
 mapping_review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 receipt_id uuid NOT NULL REFERENCES public.pdc_non_navision_jobcard_receipts(receipt_id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 operation_line_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
 operation_no text NOT NULL CHECK(operation_no~'^OP([1-9]|[1-4][0-9]|50)$'),
 status text NOT NULL DEFAULT 'pending' CHECK(status='pending'),
 reason text NOT NULL CHECK(reason='station mapping is not established by an existing Craig-approved durable rule'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(receipt_id,operation_no)
);
ALTER TABLE public.pdc_non_navision_mapping_reviews_20260904 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_non_navision_mapping_reviews_20260904 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_non_navision_mapping_reviews_20260904 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_non_navision_mapping_reviews_immutable_20260904
 BEFORE UPDATE OR DELETE ON public.pdc_non_navision_mapping_reviews_20260904
 FOR EACH ROW EXECUTE FUNCTION public.pdc_jobcard_attachment_receipt_reject_mutation();

-- Keep receipt verification bound to immutable source tuples while reporting the
-- corrected YH creation authority and pending classification reviews.
DO $read_patch$
DECLARE d text; n text;
BEGIN
 d:=pg_get_functiondef('public.read_pdc_non_navision_jobcard_receipt(uuid)'::regprocedure);
 n:=replace(d,
  $old$'initial_location',case when v_r.vehicle_created then 'YH' else null end,
  'booking_created',false,'completion_created',false$old$,
  $new$'initial_location',case when v_r.vehicle_created then 'YH' else null end,
  'mapping_review_count',(select count(*) from public.pdc_non_navision_mapping_reviews_20260904 mr where mr.receipt_id=v_r.receipt_id and mr.status='pending'),
  'booking_created',false,'completion_created',false$new$);
 IF n=d OR n NOT LIKE '%pdc_non_navision_mapping_reviews_20260904%' OR n NOT LIKE '%then ''YH''%' THEN
  RAISE EXCEPTION 'PDC_20260904010500_READ_PATCH_ANCHOR_MISSING';
 END IF;
 EXECUTE n;
END $read_patch$;

-- Patch the private implementation under the current 209 evidence-context wrapper.
DO $processor_patch$
DECLARE d text; n text;
BEGIN
 d:=pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure);
 n:=d;
 n:=replace(n,'public.pdc_email_safe_positive_numeric','public.pdc_email_safe_nonnegative_numeric_20260904');
 n:=replace(n,
  $old$jsonb_array_length(v_payload->'required_work') not between 1 and 10$old$,
  $new$jsonb_array_length(v_payload->'required_work') not between 0 and 10$new$);
 n:=replace(n,
  $old$coalesce(a->>'work_key','') not in('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')$old$,
  $new$coalesce(a->>'work_key','') not in('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet','owner_supplied_document')$new$);
 n:=replace(n,
  $old$or public.pdc_email_safe_nonnegative_numeric_20260904(a->'estimated_hours',999.99) is null)$old$,
  $new$or jsonb_typeof(a->'estimated_hours')<>'number'
   or public.pdc_email_safe_nonnegative_numeric_20260904(a->'estimated_hours',999.99) is null)$new$);
 n:=replace(n,
  $old$(select array_agg(distinct a->>'work_key' order by a->>'work_key') from jsonb_array_elements(v_lines) a)$old$,
  $new$(select array_agg(distinct a->>'work_key' order by a->>'work_key') from jsonb_array_elements(v_lines) a where a->>'work_key'<>'owner_supplied_document')$new$);
 n:=replace(n,
  $old$'active',true,'YH','UNALLOCATED','authenticated_email'$old$,
  $new$'active',true,'YH',null,'authenticated_email'$new$);
 n:=replace(n,
  $old$  insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,notes,updated_at)
  values(v_vehicle.id,v_work_key,true,false,'Required by retained non-Navision job card '||v_job,v_now)
  on conflict(vehicle_id,work_key) do update set required=true,updated_at=v_now;$old$,
  $new$  if v_work_key<>'owner_supplied_document' then
   insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,notes,updated_at)
   values(v_vehicle.id,v_work_key,true,false,'Required by retained non-Navision job card '||v_job,v_now)
   on conflict(vehicle_id,work_key) do update set required=true,updated_at=v_now;
  else
   insert into public.pdc_non_navision_mapping_reviews_20260904(receipt_id,operation_line_id,operation_no,reason)
   values(v_receipt_id,v_operation_id,v_line->>'operation_no','station mapping is not established by an existing Craig-approved durable rule');
  end if;$new$);
 n:=replace(n,
  $old$'initial_location',case when v_created then 'PMB' else null end,'no_booking',true$old$,
  $new$'initial_location',case when v_created then 'YH' else null end,'no_booking',true$new$);
 IF n=d
    OR n LIKE '%pdc_email_safe_positive_numeric%'
    OR n NOT LIKE '%pdc_email_safe_nonnegative_numeric_20260904%'
    OR n NOT LIKE '%jsonb_typeof(a->''estimated_hours'')<>''number''%'
    OR n NOT LIKE '%owner_supplied_document%'
    OR n NOT LIKE '%pdc_non_navision_mapping_reviews_20260904%'
    OR n NOT LIKE '%''active'',true,''YH'',null,''authenticated_email''%'
    OR n NOT LIKE '%case when v_created then ''YH'' else null end%'
 THEN RAISE EXCEPTION 'PDC_20260904010500_PROCESSOR_PATCH_ANCHOR_MISSING'; END IF;
 EXECUTE n;
END $processor_patch$;

-- Preserve the 209 recreation guard's public/private ACL split.
REVOKE ALL ON FUNCTION public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) TO authenticated;
COMMENT ON FUNCTION public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) IS
 'STAGING-only provider-attested non-Navision Job Card import. New external vehicles start active/visible at YH pending manual YH-to-PMB; explicit zero is preserved; unknown station lines are retained for review; no booking or completion is created.';

DO $post$
DECLARE zero_value numeric; missing_value numeric; outer_def text; inner_def text;
BEGIN
 zero_value:=public.pdc_email_safe_nonnegative_numeric_20260904('0.00'::jsonb,999.99);
 missing_value:=public.pdc_email_safe_nonnegative_numeric_20260904('null'::jsonb,999.99);
 outer_def:=pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure);
 inner_def:=pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure);
 IF zero_value IS DISTINCT FROM 0.00 OR missing_value IS NOT NULL
    OR public.pdc_email_jobcard_work_key('SUB Reflective Striping') IS DISTINCT FROM 'sublet'
    OR public.pdc_email_jobcard_work_key('OP#018: SUB Reflective Striping') IS DISTINCT FROM 'sublet'
    OR public.pdc_email_jobcard_work_key('External provider paint protection') IS DISTINCT FROM 'sublet'
    OR public.pdc_email_jobcard_work_key('Wheel Nut Indicator Set') IS DISTINCT FROM 'tyre'
    OR public.pdc_email_jobcard_work_key('Supply Fire Extinguisher') IS DISTINCT FROM 'fabrication'
    OR public.pdc_email_jobcard_work_key('PIT AND WEIGH') IS DISTINCT FROM 'pitInspection'
    OR NOT public.pdc_email_jobcard_clause_matches('OP 018 Bespoke retained instruction 1.00 hours','Bespoke retained instruction',1.00)
    OR NOT public.pdc_email_jobcard_clause_matches('OP#018: Bespoke retained instruction 1.00 hours','Bespoke retained instruction',1.00)
    OR NOT public.pdc_email_jobcard_clause_matches('OP/018 Bespoke retained instruction 30 min','Bespoke retained instruction',0.50)
    OR public.pdc_email_jobcard_work_key('Unmapped bespoke instruction') IS DISTINCT FROM 'owner_supplied_document'
    OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_non_navision_mapping_reviews_20260904'::regclass)
    OR has_table_privilege('authenticated','public.pdc_non_navision_mapping_reviews_20260904','select')
    OR has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')
    OR has_function_privilege('anon','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR has_function_privilege('service_role','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR NOT has_function_privilege('authenticated','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='pdc_non_navision_operation_lines_immutable' AND tgenabled='O')
    OR outer_def NOT LIKE '%pdc.recreation_source_hash%'
    OR outer_def NOT LIKE '%pdc_process_non_navision_jobcard_pre209%'
    OR inner_def NOT LIKE '%''active'',true,''YH'',null,''authenticated_email''%'
    OR inner_def NOT LIKE '%booking_created'',false%'
    OR inner_def NOT LIKE '%completion_created'',false%'
 THEN RAISE EXCEPTION 'PDC_20260904010500_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010500','non_navision_jobcard_current_contract',ARRAY[
 'Preserve the public 209 recreation evidence wrapper and keep its private processor non-executable',
 'Create new external/non-Navision vehicles active and visible at YH with date_to_pmb IS NULL pending manual authority',
 'Preserve explicit numeric 0.00; reject missing/non-numeric source hours rather than coercing them to zero',
 'Map explicit SUB to Sublet, Wheel Nut Indicator to Tyre, fire extinguisher to Fabrication',
 'Retain unknown classifications as immutable owner_supplied_document lines with pending review',
 'PIT retained as non-bookable deferred QC evidence; no bookings or completion created',
 'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
