-- r729 rollback: puts the check literals, the QC gate pin, the refill cadence and the pre-warm job back.
-- Staging cdsmnqxtyyoeoznmbidd only. No vehicle, booking, line or tick changes.
DO $$ BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r729 down: staging only'; END IF;
END $$;

UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,'20fac9508d40f9bb79438208bba7fa45','ca08696ffbe6a1834e63f8b8faf246e1'),'fad0a85d5dfcdfb0526b2062463d3188','82c809d15c382e73c0ae5bf135293ebe')
WHERE check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523','named_external_sublet_584');
UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,'before_import_rules_20261017(uuid)'')=''sublet_rule_20261029''','before_import_rules_20261017(uuid)'')=''r523'''),'note_fee_sublet_521(jsonb)'')=''sublet_rule_20261029''','note_fee_sublet_521(jsonb)'')=''r521''')
WHERE check_name = 'named_external_sublet_584';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'b2de35bd65bd1021b4dfc14410244dc4','f8f91d313d3e5240355eca18eb14ab79') WHERE check_name = 'bus_component_split_568';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'release=''sublet_rule_20261029''','release=''r538''') WHERE check_name IN ('category_unstarted_release_536','running_booking_end_538');
UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,'before_import_rules_20261017(uuid)'')=''sublet_rule_20261029''','before_import_rules_20261017(uuid)'')=''r523'''),'boolean,jsonb)'')=''sublet_rule_20261029''','boolean,jsonb)'')=''r538''')
WHERE check_name = 'bus_whole_job_450';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'coalesce\(rs\.stage_code,asr\.stage_code,h\.stage_code,','coalesce\(rs\.stage_code,h\.stage_code,') WHERE check_name = 'dept138_review_routing_459';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'be14ea3e9d330a21a5547deb9145a4d7','4e8dfda7795a8a547358554c5720a174') WHERE check_name IN ('planner_duration_after_insert_537','planner_duration_cache_531');
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'AND NOT pdc_ops.cross_bay_vehicle_guard_on() AND to_regclass(''pdc_ops.workshop_guard_599'') IS NOT NULL AS ok','AND (SELECT pg_catalog.strpos(def, ''stoppage'') > 0 AND pg_catalog.strpos(def, ''queued'') > 0 AND pg_catalog.strpos(def, ''bay_id IS NULL'') > 0 FROM rule) AS ok')
WHERE check_name = 'parts_eta_stoppage_573';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,' AND coalesce(m.reason,'''') <> ''Explicit Vehicle Locations release to PMB''','') WHERE check_name = 'bodybuilder_new_to_pmb_574';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,',''cross_station_park_575'',''cross_station_push_575'')',')') WHERE check_name = 'bay_resequence_and_stopped_replan';
UPDATE pdc_ops.regression_checks SET check_sql = regexp_replace(check_sql,'IS NOT DISTINCT FROM \(SELECT nullif\(sum.*?completed IS TRUE\)\)','= 5.00') WHERE check_name = 'key460_drag_597';
UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,'IS NOT DISTINCT FROM nullif(open_hours.total,0)','= open_hours.total'),'  AND true','  AND open_hours.total = 5.00') WHERE check_name = 'outstanding_station_hours_594';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = '4973560977892d1a6b3a52c9ec0c7855', note = regexp_replace(coalesce(note,''),'; r729:.*$',''), updated_at = clock_timestamp()
WHERE signature = 'public.pdc_qc_gate_issues(uuid)' AND prosrc_md5 = '22d863876a4cfa8f127756cc4a8a6da4';
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729';
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'staging-cron-history-cleanup-729';
SELECT cron.alter_job(jobid, schedule => '20 seconds') FROM cron.job WHERE jobname = 'staging-qc-operation-lines-cache-refill';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,'''5 seconds''','''20 seconds''') WHERE check_name = 'qc_cache_refill_busy_not_error';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'board_prewarm_729';
