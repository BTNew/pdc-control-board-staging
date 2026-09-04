-- STAGING ONLY: Craig 2026-09-04 Workshop and Job Card authority repairs.
-- Source evidence remains immutable. Effective corrections are append-only overlays.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010000-craig-repairs',0));

DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903200000' AND name='pdc14_synthetic_operator_verification_helper')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260903200000')
 THEN RAISE EXCEPTION 'PDC_20260904010000_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

-- Rename is a first-class, separately audited Admin-block mutation.
ALTER TABLE public.workshop_admin_block_history DROP CONSTRAINT workshop_admin_block_history_event_type_check;
ALTER TABLE public.workshop_admin_block_history ADD CONSTRAINT workshop_admin_block_history_event_type_check CHECK(event_type IN('created','moved','resized','renamed','deleted'));
ALTER TABLE public.workshop_admin_block_receipts DROP CONSTRAINT workshop_admin_block_receipts_mutation_type_check;
ALTER TABLE public.workshop_admin_block_receipts ADD CONSTRAINT workshop_admin_block_receipts_mutation_type_check CHECK(mutation_type IN('create','move','resize','rename','delete'));

CREATE OR REPLACE FUNCTION public.rename_workshop_admin_block_20260904(
 p_block_id uuid,p_expected_version bigint,p_label text,p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $rename$
DECLARE a uuid:=auth.uid(); e text:=lower(coalesce(auth.jwt()->>'email','')); b public.workshop_admin_blocks%rowtype; before_j jsonb; after_j jsonb; result jsonb;
BEGIN
 PERFORM public.require_pdc_role('administrator');
 IF p_block_id IS NULL OR p_expected_version IS NULL OR length(btrim(coalesce(p_label,''))) NOT BETWEEN 1 AND 120 OR jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' THEN RETURN jsonb_build_object('ok',false,'error','invalid_input'); END IF;
 SELECT * INTO b FROM public.workshop_admin_blocks WHERE id=p_block_id FOR UPDATE;
 IF NOT FOUND OR b.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','admin_block_not_found'); END IF;
 IF b.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','admin_block_version_conflict','current_version',b.version); END IF;
 before_j:=public.workshop_admin_block_snapshot(b.id);
 UPDATE public.workshop_admin_blocks SET label=btrim(p_label),version=version+1,updated_by=a,updated_at=clock_timestamp() WHERE id=b.id RETURNING * INTO b;
 after_j:=public.workshop_admin_block_snapshot(b.id);
 result:=jsonb_build_object('ok',true,'code','admin_block_renamed','admin_block',after_j,'cascade',jsonb_build_object('shifted_count',0));
 INSERT INTO public.workshop_admin_block_history(block_id,event_type,block_version,before_data,after_data,metadata,actor_user_id,actor_email) VALUES(b.id,'renamed',b.version,before_j,after_j,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('label',b.label,'admin_block_rename_cascaded',false),a,e);
 INSERT INTO public.workshop_admin_block_receipts(block_id,mutation_type,expected_version,resulting_version,response,metadata,actor_user_id,actor_email) VALUES(b.id,'rename',p_expected_version,b.version,result,coalesce(p_metadata,'{}'::jsonb),a,e);
 PERFORM public.workshop_bump_revision(); PERFORM public.workshop_bump_station_revision((after_j->>'stage_code'));
 RETURN result;
END $rename$;
REVOKE ALL ON FUNCTION public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb) TO authenticated;

-- PIT is a real planner station. Deleting a PIT Admin block atomically cancels
-- any overlapping queued/planned PIT booking so no stale BOOKED state survives.
UPDATE public.workshop_stages SET planner_enabled=true,updated_at=clock_timestamp() WHERE code='PIT_INSPECTION' AND active AND is_physical AND NOT planner_enabled;
CREATE OR REPLACE FUNCTION public.pdc_admin_block_delete_cancel_pit_20260904() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $pit$
DECLARE r record; before_j jsonb; after_j jsonb;
BEGIN
 IF NEW.event_type<>'deleted' OR upper(coalesce(NEW.before_data->>'stage_code',''))<>'PIT_INSPECTION' THEN RETURN NEW; END IF;
 FOR r IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE s.code='PIT_INSPECTION' AND b.bay_id=(NEW.before_data->>'bay_id')::uuid AND b.deleted_at IS NULL AND b.status IN('queued','planned')
    AND b.scheduled_start_at<(NEW.before_data->>'scheduled_end_at')::timestamptz AND b.scheduled_end_at>(NEW.before_data->>'scheduled_start_at')::timestamptz FOR UPDATE OF b
 LOOP
  before_j:=public.workshop_booking_snapshot(r.id);
  UPDATE public.workshop_bookings SET status='deleted',deleted_at=clock_timestamp(),deleted_reason='Admin block deleted; PIT scheduled entry cancelled',updated_by=NEW.actor_user_id,updated_at=clock_timestamp(),version=version+1 WHERE id=r.id;
  UPDATE public.workshop_booking_assignments SET released_at=coalesce(released_at,clock_timestamp()),updated_at=clock_timestamp() WHERE booking_id=r.id AND released_at IS NULL;
  after_j:=public.workshop_booking_snapshot(r.id);
  PERFORM public.workshop_write_history(r.id,'admin_block_delete_cancelled',before_j,after_j,NEW.metadata||jsonb_build_object('admin_block_id',NEW.block_id,'admin_block_delete_cancelled',true));
 END LOOP;
 RETURN NEW;
END $pit$;
REVOKE ALL ON FUNCTION public.pdc_admin_block_delete_cancel_pit_20260904() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_admin_block_delete_cancel_pit_20260904 AFTER INSERT ON public.workshop_admin_block_history FOR EACH ROW EXECUTE FUNCTION public.pdc_admin_block_delete_cancel_pit_20260904();

-- Pure prospective authority rule. Explicit 0.0 Pre-Delivery and missing
-- Pre-Delivery both become 1.50 effective hours; non-PD explicit zero remains zero.
CREATE OR REPLACE FUNCTION public.pdc_apply_craig_pd_hours_rule_20260904(p_description text,p_source_hours numeric,p_source_provenance text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $pd$
 SELECT CASE WHEN lower(coalesce(p_description,'')) ~ '(^|[^a-z])(pd|pre[ -]?delivery)([^a-z]|$)'
  THEN jsonb_build_object('applied',true,'estimated_hours',1.50,'estimated_hours_source','craig_standard_pd_1_5','source_estimated_hours',p_source_hours,'source_estimated_hours_source',p_source_provenance)
  ELSE jsonb_build_object('applied',false,'estimated_hours',p_source_hours,'estimated_hours_source',p_source_provenance,'source_estimated_hours',p_source_hours,'source_estimated_hours_source',p_source_provenance) END
$pd$;
REVOKE ALL ON FUNCTION public.pdc_apply_craig_pd_hours_rule_20260904(text,numeric,text) FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_jobcard_hours_corrections_20260904(
 correction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),operation_line_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,operation_no text NOT NULL,description text NOT NULL,
 source_estimated_hours numeric,source_estimated_hours_source text,effective_estimated_hours numeric NOT NULL CHECK(effective_estimated_hours>=0),effective_provenance text NOT NULL,
 correction_reason text NOT NULL,authority text NOT NULL,metadata jsonb NOT NULL DEFAULT '{}'::jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_jobcard_hours_corrections_20260904 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_jobcard_hours_corrections_20260904 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_jobcard_hours_corrections_20260904 FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.pdc_jobcard_hours_correction_immutable_20260904() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$BEGIN RAISE EXCEPTION 'PDC_20260904_HOURS_CORRECTION_IMMUTABLE' USING errcode='55000';END$$;
REVOKE ALL ON FUNCTION public.pdc_jobcard_hours_correction_immutable_20260904() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_jobcard_hours_correction_immutable_20260904 BEFORE UPDATE OR DELETE ON public.pdc_jobcard_hours_corrections_20260904 FOR EACH ROW EXECUTE FUNCTION public.pdc_jobcard_hours_correction_immutable_20260904();

ALTER TABLE public.vehicle_workshop_line_adjustments DROP CONSTRAINT pdc_auditor_adjustment_origin_check;
ALTER TABLE public.vehicle_workshop_line_adjustments ADD CONSTRAINT pdc_auditor_adjustment_origin_check CHECK(correction_origin IS NULL OR correction_origin IN('ai_auditor','ai_auditor_rolled_back','manual_operator','craig_standard_pd_1_5','job_card_source_correction'));

CREATE OR REPLACE FUNCTION public.pdc_project_craig_pd_hours_20260904() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $project$
DECLARE rule jsonb; stage text;
BEGIN
 rule:=public.pdc_apply_craig_pd_hours_rule_20260904(NEW.description,NEW.estimated_hours,NEW.estimated_hours_source);
 IF coalesce((rule->>'applied')::boolean,false) THEN
  stage:=public.workshop_stage_code_for_work_key(NEW.work_key);
  INSERT INTO public.pdc_jobcard_hours_corrections_20260904(operation_line_id,vehicle_id,operation_no,description,source_estimated_hours,source_estimated_hours_source,effective_estimated_hours,effective_provenance,correction_reason,authority,metadata)
  VALUES(NEW.operation_line_id,NEW.vehicle_id,NEW.operation_no,NEW.description,NEW.estimated_hours,NEW.estimated_hours_source,1.50,'craig_standard_pd_1_5','Craig standard duration overrides explicit 0.0 and missing Pre-Delivery hours','Craig 2026-09-04',jsonb_build_object('source_preserved',true));
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number)
  VALUES(NEW.vehicle_id,'source:'||NEW.operation_line_id,'source',stage,NEW.description,1.50,true,1,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7',NEW.operation_no,true,'craig_standard_pd_1_5',NEW.operation_line_id,NEW.job_card_number);
 END IF;
 RETURN NEW;
END $project$;
REVOKE ALL ON FUNCTION public.pdc_project_craig_pd_hours_20260904() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_project_craig_pd_hours_20260904 AFTER INSERT ON public.pdc_authenticated_email_operation_lines FOR EACH ROW EXECUTE FUNCTION public.pdc_project_craig_pd_hours_20260904();

-- Controlled Stock 13048501: immutable source total is 17.00 hours. OP1's
-- explicit zero becomes Craig-standard 1.50 effective hours; OP15 remains
-- explicit Job Card 1.50 (not ai_estimate) via a provenance correction overlay.
DO $fixture$
DECLARE v public.vehicles%rowtype; op1 public.pdc_authenticated_email_operation_lines%rowtype; op15 public.pdc_authenticated_email_operation_lines%rowtype; old_adj public.vehicle_workshop_line_adjustments%rowtype; new_adj public.vehicle_workshop_line_adjustments%rowtype; sp uuid; before_v jsonb; after_v jsonb;
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE stock_number_normalized='13048501' AND job_card_number='J139125583' AND deleted_at IS NULL FOR UPDATE;
 SELECT * INTO STRICT op1 FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id=v.id AND operation_no='OP1' AND description='Pre-Delivery (Commercial)' AND estimated_hours=0 AND estimated_hours_source='job_card';
 SELECT * INTO STRICT op15 FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id=v.id AND operation_no='OP15' AND description='TYRE x6 Upgrade to Toyo M55F 265/65R17' AND estimated_hours=1.50 AND estimated_hours_source='ai_estimate';
 IF (SELECT sum(estimated_hours) FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id=v.id)<>17.00 THEN RAISE EXCEPTION 'PDC_20260904_SOURCE_TOTAL_NOT_17_00'; END IF;
 SELECT id INTO STRICT sp FROM public.salespeople WHERE name='Stephen Peck' AND active;
 INSERT INTO public.pdc_jobcard_hours_corrections_20260904(operation_line_id,vehicle_id,operation_no,description,source_estimated_hours,source_estimated_hours_source,effective_estimated_hours,effective_provenance,correction_reason,authority,metadata) VALUES
 (op1.operation_line_id,v.id,'OP1',op1.description,0,'job_card',1.50,'craig_standard_pd_1_5','Explicit 0.0 Pre-Delivery corrected to Craig standard 1.5','Craig 2026-09-04',jsonb_build_object('stock_authority','069','job_card','J139125583')),
 (op15.operation_line_id,v.id,'OP15',op15.description,1.50,'ai_estimate',1.50,'job_card','PDF page 4 explicitly supplies [1.50]; classification correction only','Job Card PDF page 4 lines 135-137',jsonb_build_object('source_preserved',true,'all_15_job_card_hours_explicit',true));
 -- These five legacy null-origin overlays changed explicit Job Card zeroes into
 -- estimates. Correct only their mutable effective hours/provenance and append
 -- an audit event; immutable operation identity and source evidence are intact.
 FOR old_adj IN SELECT a.* FROM public.vehicle_workshop_line_adjustments a JOIN public.pdc_authenticated_email_operation_lines o ON o.operation_line_id=a.source_operation_line_id
  WHERE a.vehicle_id=v.id AND a.active AND a.correction_origin IS NULL AND o.estimated_hours=0 AND o.operation_no<>'OP1' FOR UPDATE OF a
 LOOP
  UPDATE public.vehicle_workshop_line_adjustments SET estimated_hours=0,correction_origin='job_card_source_correction',version=version+1,updated_at=clock_timestamp(),updated_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7' WHERE adjustment_id=old_adj.adjustment_id RETURNING * INTO new_adj;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','vehicle_workshop_line_adjustments',old_adj.adjustment_id,v.id,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au',to_jsonb(old_adj),to_jsonb(new_adj),jsonb_build_object('source','job-card-explicit-zero-repair-20260904','operation_no',(SELECT operation_no FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id=old_adj.source_operation_line_id),'non_pd_explicit_zero_unchanged',true));
 END LOOP;
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number) VALUES
 (v.id,'source:'||op1.operation_line_id,'source','FITTING',op1.description,1.50,true,1,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','OP1',1,true,'craig_standard_pd_1_5',op1.operation_line_id,'J139125583'),
 (v.id,'source:'||op15.operation_line_id,'source','TYRE',op15.description,1.50,true,1,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','OP15',15,true,'job_card_source_correction',op15.operation_line_id,'J139125583');
 before_v:=to_jsonb(v); PERFORM set_config('pdc.salesperson_assignment_manual_386','allow',true);
 UPDATE public.vehicles SET customer_name='SHIRE OF EAST PILBARA',salesperson_id=sp,salesperson_reference='Stephen Peck',salesperson_manual_override=true,salesperson_manual_override_at=clock_timestamp(),salesperson_manual_override_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7',source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('job_card_customer','SHIRE OF EAST PILBARA','job_card_salesperson','Stephen Peck','stock_authority','069','job_card_invoice_value',1324.5,'job_card_source_total_hours',17.00,'effective_total_hours',18.50),updated_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7',updated_at=clock_timestamp(),version=version+1 WHERE id=v.id RETURNING to_jsonb(vehicles.*) INTO after_v;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','vehicles',v.id,v.id,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au',before_v,after_v,jsonb_build_object('source','craig-job-card-authority-20260904','customer','SHIRE OF EAST PILBARA','salesperson','Stephen Peck','stock_authority','069','invoice_value',1324.5));
END $fixture$;

DO $post$
DECLARE explicit_zero jsonb; missing_pd jsonb; non_pd_zero jsonb;
BEGIN
 explicit_zero:=public.pdc_apply_craig_pd_hours_rule_20260904('Pre-Delivery (Commercial)',0.0,'job_card');
 missing_pd:=public.pdc_apply_craig_pd_hours_rule_20260904('PD Inspection',NULL,NULL);
 non_pd_zero:=public.pdc_apply_craig_pd_hours_rule_20260904('PIT AND WEIGH',0.0,'job_card');
 IF explicit_zero->>'estimated_hours'<>'1.50' OR missing_pd->>'estimated_hours'<>'1.50' OR (non_pd_zero->>'applied')::boolean OR non_pd_zero->>'estimated_hours'<>'0.0' THEN RAISE EXCEPTION 'PDC_20260904_PD_RULE_REGRESSION'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE code='PIT_INSPECTION' AND planner_enabled)
  OR has_function_privilege('anon','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute')
  OR has_function_privilege('service_role','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute')
  OR NOT has_function_privilege('authenticated','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute')
  OR (SELECT count(*) FROM public.pdc_jobcard_hours_corrections_20260904)<>2
  OR (SELECT sum(estimated_hours) FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0')<>17.00
  OR (SELECT sum(coalesce(a.estimated_hours,o.estimated_hours)) FROM public.pdc_authenticated_email_operation_lines o LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.source_operation_line_id=o.operation_line_id AND a.active WHERE o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0')<>18.50
 THEN RAISE EXCEPTION 'PDC_20260904_POSTCONDITION_FAILED'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260904010000','craig_workshop_and_jobcard_repairs',ARRAY[
 'Admin blocks support separately audited label rename and PIT deletion cancellation',
 'PIT_INSPECTION is planner-enabled',
 'Craig standard makes explicit-zero and missing-hour Pre-Delivery effective 1.50 while non-PD zero remains unchanged',
 'Immutable Job Card source evidence remains unchanged beneath append-only effective overlays',
 'Stock 13048501 corrected to SHIRE OF EAST PILBARA / Stephen Peck / authority 069 / invoice 1324.5',
 'OP15 1.50 classified as explicit job_card through append-only provenance correction; immutable original is retained'
]);
COMMIT;
