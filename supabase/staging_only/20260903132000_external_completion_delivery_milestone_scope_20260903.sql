-- STAGING ONLY: keep the historical first-delivery latch authoritative while
-- allowing the narrowly identified external/non-Navision completion path to
-- mean collected-and-closed rather than Delivered - At Dealer.

DO $guard$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-head',0));
  IF current_database()<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903131000' AND name='external_completion_workshop_status_not_null_repair_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260903131000')
     OR to_regprocedure('public.pdc_vehicle_first_milestones()') IS NULL
     OR to_regprocedure('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_MILESTONE_REPAIR_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_vehicle_first_milestones()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $milestones$
DECLARE
  v_business_date date:=(clock_timestamp() at time zone 'Australia/Perth')::date;
  v_external_collected_completion boolean:=false;
BEGIN
  IF tg_op='INSERT' THEN
    IF upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN
      new.date_to_pmb:=coalesce(new.date_to_pmb,v_business_date);
    END IF;
    IF upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN
      new.date_to_rft:=coalesce(new.date_to_rft,v_business_date);
    END IF;
    IF lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN
      new.delivered_to_dealer_date:=coalesce(new.delivered_to_dealer_date,v_business_date);
    END IF;
    RETURN new;
  END IF;

  -- Existing facts always win. The sole no-latch exception is the dedicated
  -- external completion authority after physical RFT collection, with no
  -- Navision delivery evidence and no pre-existing dealer-delivery milestone.
  v_external_collected_completion:=
    old.delivered_to_dealer_date IS NULL
    AND new.delivered_to_dealer_date IS NULL
    AND new.rft_collected_at IS NOT NULL
    AND lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed'
    AND coalesce(new.source_payload->>'completion_authority','')='external_non_navision_final_collection'
    AND NOT (coalesce(new.source_payload,'{}'::jsonb) ? 'navision_status_literal');

  new.date_to_pmb:=coalesce(old.date_to_pmb,new.date_to_pmb,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN v_business_date END);
  new.date_to_rft:=coalesce(old.date_to_rft,new.date_to_rft,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN v_business_date END);
  new.delivered_to_dealer_date:=CASE
    WHEN v_external_collected_completion THEN NULL
    ELSE coalesce(old.delivered_to_dealer_date,new.delivered_to_dealer_date,
      CASE WHEN lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN v_business_date END)
  END;
  RETURN new;
END;
$milestones$;

REVOKE ALL ON FUNCTION public.pdc_vehicle_first_milestones() FROM PUBLIC;

DO $post$
DECLARE d text:=pg_get_functiondef('public.pdc_vehicle_first_milestones()'::regprocedure);
BEGIN
  IF position('external_non_navision_final_collection' in d)=0
     OR position('v_external_collected_completion' in d)=0
     OR position('old.delivered_to_dealer_date IS NULL' in d)=0
     OR position('new.rft_collected_at IS NOT NULL' in d)=0
     OR position('navision_status_literal' in d)=0
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_MILESTONE_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903132000','external_completion_delivery_milestone_scope_20260903',ARRAY['external completion delivery milestone scope 20260903'])
ON CONFLICT(version) DO UPDATE SET name=excluded.name,statements=excluded.statements;
