-- Complete a reviewed missing fallback only; no category or supplied/staff hour changes.
DO $guard$ BEGIN
IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required';END IF;
END $guard$;
CREATE TABLE pdc_operation_updates_private.ai_routing_hour_reviews_20261019(
 review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),department text NOT NULL,description_hash text NOT NULL,
 previous_decision jsonb NOT NULL,new_hours numeric NOT NULL CHECK(new_hours>0 AND new_hours<=999.99 AND new_hours=round(new_hours,2)),
 rationale text NOT NULL CHECK(length(rationale)>=30),recorded_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE pdc_operation_updates_private.ai_routing_hour_reviews_20261019 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_operation_updates_private.ai_routing_hour_reviews_20261019 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION pdc_operation_updates_private.complete_reviewed_ai_hours_20261019(p_department text,p_description text,p_expected_rationale text,p_hours numeric,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE old pdc_operation_updates_private.ai_routing_20261019%rowtype;h text;rid uuid;
BEGIN
IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required';END IF;
IF p_hours IS NULL OR p_hours<=0 OR p_hours>999.99 OR p_hours<>round(p_hours,2) OR length(coalesce(p_reason,''))<30 THEN RAISE EXCEPTION 'reviewed_hours_and_reason_required';END IF;
h:=pdc_work_categories_private.import_description_hash_20261017(p_description);
SELECT * INTO old FROM pdc_operation_updates_private.ai_routing_20261019 WHERE department=p_department AND description_hash=h FOR UPDATE;
IF NOT FOUND OR old.rationale IS DISTINCT FROM p_expected_rationale OR old.estimated_hours IS NOT NULL OR old.category IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES') THEN RAISE EXCEPTION 'reviewed_missing_fallback_changed';END IF;
INSERT INTO pdc_operation_updates_private.ai_routing_hour_reviews_20261019(department,description_hash,previous_decision,new_hours,rationale)
VALUES(p_department,h,to_jsonb(old),p_hours,p_reason) RETURNING review_id INTO rid;
UPDATE pdc_operation_updates_private.ai_routing_20261019 SET estimated_hours=p_hours WHERE department=p_department AND description_hash=h;
RETURN pdc_operation_updates_private.remember_ai_routing_20261019(p_department,p_description,old.category,p_hours,old.confidence,old.rationale)||jsonb_build_object('review_id',rid,'previous_decision_preserved',true);
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.complete_reviewed_ai_hours_20261019(text,text,text,numeric,text) FROM PUBLIC,anon,authenticated,service_role;