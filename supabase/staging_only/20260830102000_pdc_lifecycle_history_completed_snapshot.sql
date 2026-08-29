-- STAGING ONLY 1020: include retained canonical Completed/Collected rows in
-- the authenticated Vehicle Locations snapshot.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-lifecycle-history-completed-snapshot-1020',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260830101000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830101000' AND name='pdc_lifecycle_history_synthetic_scope_repair')<>1
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830102000')
 THEN RAISE EXCEPTION 'PDC_1020_EXACT_STAGING_1010_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_1020;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $snapshot$
DECLARE base jsonb; rows jsonb; appended jsonb;
BEGIN
 base:=public.get_pdc_email_vehicle_location_snapshot_pre_1020();
 IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
 SELECT coalesce(jsonb_agg(x||jsonb_build_object('lifecycle_history',coalesce(h,'{}'::jsonb))||jsonb_build_object(
   'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
   'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days') ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
 FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x
 LEFT JOIN LATERAL public.pdc_lifecycle_history_payload_82000((x->>'id')::uuid) h ON true;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'key_number',v.key_number,'job_card_number',v.job_card_number,
   'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,'registration',v.registration,
   'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,
   'delivered_to_dealer_date',v.delivered_to_dealer_date,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
   'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'source_system',v.source_system,'source_record_id',v.source_record_id,
   'pdc_lifecycle',jsonb_build_object('state',case when v.current_location='Completed' or v.lifecycle_state::text='completed' then 'completed' when v.current_location='Collected' then 'collected' else lower(v.lifecycle_state::text) end,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'rft_collected_at',v.rft_collected_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds),
   'lifecycle_history',h,'first_reached_yard_hold_at',h->'first_reached_yard_hold_at','first_entered_pmb_at',h->'first_entered_pmb_at','first_became_rft_at',h->'first_became_rft_at',
   'elapsed_yard_hold_to_pmb_days',h->'elapsed_yard_hold_to_pmb_days','elapsed_pmb_to_rft_days',h->'elapsed_pmb_to_rft_days','elapsed_yard_hold_to_rft_days',h->'elapsed_yard_hold_to_rft_days',
   'work_items',coalesce((select jsonb_agg(to_jsonb(w) order by w.work_key) from public.vehicle_work_items w where w.vehicle_id=v.id),'[]'::jsonb)
 ) ORDER BY coalesce(v.rft_collected_at,v.updated_at),v.id),'[]'::jsonb) INTO appended
 FROM public.vehicles v
 LEFT JOIN LATERAL public.pdc_lifecycle_history_payload_82000(v.id) h ON true
 WHERE v.deleted_at IS NULL AND (v.current_location IN('Collected','Completed') OR v.lifecycle_state::text='completed')
   AND (h IS NOT NULL OR EXISTS(select 1 from public.pdc_final_pdc_lifecycle_receipts_700 q where q.vehicle_id=v.id) OR EXISTS(select 1 from public.pdc_rft_transport_lifecycle_receipts_734 q where q.vehicle_id=v.id))
   AND NOT EXISTS(select 1 from jsonb_array_elements(rows) x where (x->>'id')=v.id::text);
 rows:=rows||coalesce(appended,'[]'::jsonb);
 RETURN jsonb_set(base,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_1020(),public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830102000','pdc_lifecycle_history_completed_snapshot',ARRAY[
 'Append-only successor after exact 20260830101000 lifecycle-history synthetic-scope repair',
 'Include canonical non-deleted Completed and Collected vehicles backed by retained lifecycle or final transport evidence',
 'Overlay exact lifecycle timestamps, provenance and durations without using Kewdale ETA or mutable current milestone dates',
 'Preserve existing authenticated snapshot filtering, audit, RLS and Production exclusion'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
