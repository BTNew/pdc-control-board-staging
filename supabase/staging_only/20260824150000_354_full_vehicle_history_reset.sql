-- STAGING ONLY 354: complete full vehicle/history reset authorised by Craig.
-- Generated from live catalog 829c923530a93a02ffa30c4b9296f4b6132ea74be84e0dc722d7f11c93738c9c and round-trip verified encrypted backup 0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0.
-- Explicit FK-safe DELETE only: no TRUNCATE, no CASCADE, no trigger disabling.
begin isolation level serializable read write;
set local lock_timeout='15s';
set local statement_timeout='30min';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-354-full-vehicle-history-reset',0));

do $guard$
declare v_live text[];
begin
 if not public.pdc_monitor_staging_guard()
    or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='20260824140000' and name='353_contain_monitor_for_full_history_reset')
    or exists(select 1 from supabase_migrations.schema_migrations where version>'20260824140000' and version~'^[0-9]{14}$')
    or current_user<>'postgres' or session_user<>'postgres'
    or exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled or automatic_rule_application or automatic_authenticated_jobcards)
    or exists(select 1 from public.monitored_mailboxes where active)
    or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
    or exists(select 1 from public.pdc_email_monitor_status where running_status<>'stopped' or gateway_instance_id is not null) then
  raise exception 'PDC_354_TARGET_HEAD_OWNER_OR_CONTAINMENT_MISMATCH' using errcode='55000';
 end if;
 select array_agg(c.relname::text order by c.relname::text) into v_live from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p');
 if v_live is distinct from array['ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_intake_config','ai_mapping_rules','ai_proposed_actions','ai_review_items','ai_trusted_senders','ai_undo_actions','ai_workshop_commands','audit_events','backup_runs','deleted_completed_vehicles','email_response_drafts','import_runs','label_print_events','legacy_stage_reconciliation_receipts','monitored_mailboxes','navision_backend_audit','navision_backend_records','navision_backend_revision','navision_board_activations','navision_import_batches','navision_import_items','navision_initial_scope_approvals','navision_operation_receipts','navision_rollback_items','pdc_ai_intake_auto_activation_receipts','pdc_ai_intake_auto_backlog_receipts','pdc_ai_intake_decision_receipts','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_ai_intake_revision','pdc_attachment_atomic_contract','pdc_auditor_autonomous_hour_rules','pdc_auditor_booking_work_relations','pdc_auditor_correction_execution_items','pdc_auditor_correction_executions','pdc_auditor_decisions','pdc_auditor_executor_identities','pdc_auditor_finding_evidence','pdc_auditor_finding_history','pdc_auditor_finding_occurrences','pdc_auditor_findings','pdc_auditor_gvm_mappings_225','pdc_auditor_operation_changes','pdc_auditor_operation_runs','pdc_auditor_plan_items_225','pdc_auditor_plans_225','pdc_auditor_report_runs','pdc_auditor_restricted_authority_revocations','pdc_auditor_review_queue_225','pdc_auditor_revision','pdc_auditor_risk_scores','pdc_auditor_rule_commands_227','pdc_auditor_rule_config','pdc_auditor_rule_examples_227','pdc_auditor_rule_families_227','pdc_auditor_rule_versions_227','pdc_auditor_runs','pdc_auditor_service_identities_225','pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_changes_226','pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_auditor_telegram_rollback_audit_226','pdc_auditor_telegram_rollback_receipts_226','pdc_auditor_telegram_runs_226','pdc_auditor_user_dealer_scopes','pdc_auditor_worker_identities','pdc_auditor_workshop_revisions','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_attachment_manifests','pdc_authenticated_email_batch_receipts','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_row_receipts','pdc_email_attachment_batch_receipts_323','pdc_email_attachment_batch_superseded_325','pdc_email_communication_action_receipts','pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_email_intake_work_receipts','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_email_source_claims','pdc_email_vehicle_revision','pdc_full_inbox_body_sources_20260821033000','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_full_inbox_source_unit_terminals_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_historical_attachment_source_authorizations_20260821043000','pdc_historical_attachment_source_bindings_20260821043000','pdc_historical_inbox_authorizations_20260821040000','pdc_historical_nonnav_extraction_authorizations_20260821047000','pdc_historical_nonnav_extraction_corrections_20260821049000','pdc_historical_nonnav_extraction_corrections_20260821051000','pdc_historical_pilot_floor_bindings_20260821041000','pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_rule_receipts_279','pdc_jobcard_attachment_source_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_decision_receipts','pdc_key_list_proposal_revision','pdc_key_list_proposal_rows','pdc_key_list_proposals','pdc_monitor_exact_sender_enrollments','pdc_monitor_new_build_intake_approvals','pdc_monitor_runtime_binding_rotations_270','pdc_monitor_runtime_bindings_255','pdc_monitor_stage_activation_approvals','pdc_monitor_stage_activation_writers','pdc_monitor_vehicle_identity_readers','pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts','pdc_online_operational_state','pdc_online_state_receipts','pdc_online_state_revision','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_manager_authorities','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_previews','pdc_provider_email_observations','pdc_retained_reset_import_receipts_212','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_cleanse_receipts_348','pdc_staging_containment_receipts_347','pdc_staging_environment_sentinel','pdc_staging_monitor_activation_receipts_352','pdc_staging_reset_attestations','pdc_staging_reset_batches','pdc_staging_reset_evidence_corrections','pdc_staging_reset_rows','pdc_staging_verified_backup_manifests','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_supervised_apply_receipts','pdc_supervised_correction_batches','pdc_supervised_correction_evidence','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_failures','pdc_supervised_monitor_applications','pdc_supervised_review_queue','pdc_supervised_revision','pdc_supervised_rule_aliases','pdc_supervised_rule_events','pdc_supervised_rule_examples','pdc_supervised_rule_families','pdc_supervised_rule_versions','pdc_supervised_telegram_commands','pdc_supervised_telegram_identities','pdc_supervised_telegram_responses','pdc_uid478_attachment_attempt_receipts','pdc_uid478_attachment_terminal_receipts','pdc_uid478_message_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid514_recovery_authorizations_257','pdc_uid514_recovery_claim_attempts_257','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_user_roles','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','restore_test_runs','salespeople','sublet_provider_aliases','sublet_providers','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_lifecycle_resolver_revision','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_master_operation_receipts','vehicle_master_revision','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_bay_default_technician_history','workshop_bays','workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','workshop_revision','workshop_settings','workshop_stage_aliases','workshop_stages','workshop_station_revision','workshop_technicians','workshop_transition_authorizations']::text[] then raise exception 'PDC_354_LIVE_TABLE_CATALOG_DRIFT' using errcode='55000'; end if;
end
$guard$;

-- Exclude concurrent DDL/DML across the exact discovered public catalog.
do $locks$ declare n text;begin foreach n in array array['ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_intake_config','ai_mapping_rules','ai_proposed_actions','ai_review_items','ai_trusted_senders','ai_undo_actions','ai_workshop_commands','audit_events','backup_runs','deleted_completed_vehicles','email_response_drafts','import_runs','label_print_events','legacy_stage_reconciliation_receipts','monitored_mailboxes','navision_backend_audit','navision_backend_records','navision_backend_revision','navision_board_activations','navision_import_batches','navision_import_items','navision_initial_scope_approvals','navision_operation_receipts','navision_rollback_items','pdc_ai_intake_auto_activation_receipts','pdc_ai_intake_auto_backlog_receipts','pdc_ai_intake_decision_receipts','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_ai_intake_revision','pdc_attachment_atomic_contract','pdc_auditor_autonomous_hour_rules','pdc_auditor_booking_work_relations','pdc_auditor_correction_execution_items','pdc_auditor_correction_executions','pdc_auditor_decisions','pdc_auditor_executor_identities','pdc_auditor_finding_evidence','pdc_auditor_finding_history','pdc_auditor_finding_occurrences','pdc_auditor_findings','pdc_auditor_gvm_mappings_225','pdc_auditor_operation_changes','pdc_auditor_operation_runs','pdc_auditor_plan_items_225','pdc_auditor_plans_225','pdc_auditor_report_runs','pdc_auditor_restricted_authority_revocations','pdc_auditor_review_queue_225','pdc_auditor_revision','pdc_auditor_risk_scores','pdc_auditor_rule_commands_227','pdc_auditor_rule_config','pdc_auditor_rule_examples_227','pdc_auditor_rule_families_227','pdc_auditor_rule_versions_227','pdc_auditor_runs','pdc_auditor_service_identities_225','pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_changes_226','pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_auditor_telegram_rollback_audit_226','pdc_auditor_telegram_rollback_receipts_226','pdc_auditor_telegram_runs_226','pdc_auditor_user_dealer_scopes','pdc_auditor_worker_identities','pdc_auditor_workshop_revisions','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_attachment_manifests','pdc_authenticated_email_batch_receipts','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_row_receipts','pdc_email_attachment_batch_receipts_323','pdc_email_attachment_batch_superseded_325','pdc_email_communication_action_receipts','pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_email_intake_work_receipts','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_email_source_claims','pdc_email_vehicle_revision','pdc_full_inbox_body_sources_20260821033000','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_full_inbox_source_unit_terminals_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_historical_attachment_source_authorizations_20260821043000','pdc_historical_attachment_source_bindings_20260821043000','pdc_historical_inbox_authorizations_20260821040000','pdc_historical_nonnav_extraction_authorizations_20260821047000','pdc_historical_nonnav_extraction_corrections_20260821049000','pdc_historical_nonnav_extraction_corrections_20260821051000','pdc_historical_pilot_floor_bindings_20260821041000','pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_rule_receipts_279','pdc_jobcard_attachment_source_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_decision_receipts','pdc_key_list_proposal_revision','pdc_key_list_proposal_rows','pdc_key_list_proposals','pdc_monitor_exact_sender_enrollments','pdc_monitor_new_build_intake_approvals','pdc_monitor_runtime_binding_rotations_270','pdc_monitor_runtime_bindings_255','pdc_monitor_stage_activation_approvals','pdc_monitor_stage_activation_writers','pdc_monitor_vehicle_identity_readers','pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts','pdc_online_operational_state','pdc_online_state_receipts','pdc_online_state_revision','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_manager_authorities','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_previews','pdc_provider_email_observations','pdc_retained_reset_import_receipts_212','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_cleanse_receipts_348','pdc_staging_containment_receipts_347','pdc_staging_environment_sentinel','pdc_staging_monitor_activation_receipts_352','pdc_staging_reset_attestations','pdc_staging_reset_batches','pdc_staging_reset_evidence_corrections','pdc_staging_reset_rows','pdc_staging_verified_backup_manifests','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_supervised_apply_receipts','pdc_supervised_correction_batches','pdc_supervised_correction_evidence','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_failures','pdc_supervised_monitor_applications','pdc_supervised_review_queue','pdc_supervised_revision','pdc_supervised_rule_aliases','pdc_supervised_rule_events','pdc_supervised_rule_examples','pdc_supervised_rule_families','pdc_supervised_rule_versions','pdc_supervised_telegram_commands','pdc_supervised_telegram_identities','pdc_supervised_telegram_responses','pdc_uid478_attachment_attempt_receipts','pdc_uid478_attachment_terminal_receipts','pdc_uid478_message_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid514_recovery_authorizations_257','pdc_uid514_recovery_claim_attempts_257','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_user_roles','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','restore_test_runs','salespeople','sublet_provider_aliases','sublet_providers','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_lifecycle_resolver_revision','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_master_operation_receipts','vehicle_master_revision','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_bay_default_technician_history','workshop_bays','workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','workshop_revision','workshop_settings','workshop_stage_aliases','workshop_stages','workshop_station_revision','workshop_technicians','workshop_transition_authorizations']::text[] loop execute format('lock table public.%I in access exclusive mode',n);end loop;end $locks$;

-- Bind the exact current encrypted backup and all 231 table hashes/counts.
do $backup_guard$
declare n text; actual bigint; expected bigint;
begin
 if 231<>231 or 91645<>(select sum(value::bigint) from jsonb_each_text('{"ai_email_analysis_results":0,"ai_email_attachments":104,"ai_email_intake":56,"ai_extracted_fields":0,"ai_intake_config":1,"ai_mapping_rules":17,"ai_proposed_actions":0,"ai_review_items":0,"ai_trusted_senders":0,"ai_undo_actions":0,"ai_workshop_commands":0,"audit_events":23584,"backup_runs":357,"deleted_completed_vehicles":1603,"email_response_drafts":0,"import_runs":0,"label_print_events":0,"legacy_stage_reconciliation_receipts":0,"monitored_mailboxes":1,"navision_backend_audit":155,"navision_backend_records":1358,"navision_backend_revision":1,"navision_board_activations":448,"navision_import_batches":24,"navision_import_items":9701,"navision_initial_scope_approvals":2,"navision_operation_receipts":84,"navision_rollback_items":0,"pdc_ai_intake_auto_activation_receipts":26,"pdc_ai_intake_auto_backlog_receipts":1,"pdc_ai_intake_decision_receipts":5,"pdc_ai_intake_history":444,"pdc_ai_intake_proposals":273,"pdc_ai_intake_revision":1,"pdc_attachment_atomic_contract":1,"pdc_auditor_autonomous_hour_rules":0,"pdc_auditor_booking_work_relations":0,"pdc_auditor_correction_execution_items":0,"pdc_auditor_correction_executions":0,"pdc_auditor_decisions":2,"pdc_auditor_executor_identities":1,"pdc_auditor_finding_evidence":119,"pdc_auditor_finding_history":119,"pdc_auditor_finding_occurrences":119,"pdc_auditor_findings":62,"pdc_auditor_gvm_mappings_225":19,"pdc_auditor_operation_changes":46,"pdc_auditor_operation_runs":23,"pdc_auditor_plan_items_225":332,"pdc_auditor_plans_225":2,"pdc_auditor_report_runs":0,"pdc_auditor_restricted_authority_revocations":0,"pdc_auditor_review_queue_225":140,"pdc_auditor_revision":52,"pdc_auditor_risk_scores":119,"pdc_auditor_rule_commands_227":1,"pdc_auditor_rule_config":4,"pdc_auditor_rule_examples_227":2,"pdc_auditor_rule_families_227":1,"pdc_auditor_rule_versions_227":1,"pdc_auditor_runs":2,"pdc_auditor_service_identities_225":1,"pdc_auditor_telegram_apply_receipts_226":1,"pdc_auditor_telegram_changes_226":82,"pdc_auditor_telegram_deliveries_230":3,"pdc_auditor_telegram_instructions_225":2,"pdc_auditor_telegram_rollback_audit_226":82,"pdc_auditor_telegram_rollback_receipts_226":1,"pdc_auditor_telegram_runs_226":1,"pdc_auditor_user_dealer_scopes":5,"pdc_auditor_worker_identities":2,"pdc_auditor_workshop_revisions":2,"pdc_authenticated_email_attachment_claims":4,"pdc_authenticated_email_attachment_manifests":0,"pdc_authenticated_email_batch_receipts":0,"pdc_authenticated_email_import_receipts":1306,"pdc_authenticated_email_operation_lines":6389,"pdc_bulk_workbook_apply_receipts":1,"pdc_bulk_workbook_authorizations":2,"pdc_bulk_workbook_previews":2,"pdc_bulk_workbook_quarantine":412,"pdc_bulk_workbook_row_receipts":410,"pdc_email_attachment_batch_receipts_323":3,"pdc_email_attachment_batch_superseded_325":10,"pdc_email_communication_action_receipts":0,"pdc_email_communication_receipts":0,"pdc_email_evidence_consumptions":5,"pdc_email_intake_work_receipts":5,"pdc_email_monitor_pilot":1,"pdc_email_monitor_status":1,"pdc_email_source_claims":276,"pdc_email_vehicle_revision":1,"pdc_full_inbox_body_sources_20260821033000":0,"pdc_full_inbox_location_receipts_20260821033000":0,"pdc_full_inbox_parts_receipts_20260821033000":0,"pdc_full_inbox_source_unit_terminals_20260821033000":0,"pdc_generic_current_navision_enrichment_receipts_312":10,"pdc_historical_attachment_source_authorizations_20260821043000":5,"pdc_historical_attachment_source_bindings_20260821043000":0,"pdc_historical_inbox_authorizations_20260821040000":11,"pdc_historical_nonnav_extraction_authorizations_20260821047000":5,"pdc_historical_nonnav_extraction_corrections_20260821049000":1,"pdc_historical_nonnav_extraction_corrections_20260821051000":0,"pdc_historical_pilot_floor_bindings_20260821041000":0,"pdc_jobcard_attachment_import_receipts":19,"pdc_jobcard_attachment_rule_receipts_279":62,"pdc_jobcard_attachment_source_row_receipts":67,"pdc_key_list_apply_receipt_rows":0,"pdc_key_list_decision_receipts":0,"pdc_key_list_proposal_revision":1,"pdc_key_list_proposal_rows":0,"pdc_key_list_proposals":0,"pdc_monitor_exact_sender_enrollments":22,"pdc_monitor_new_build_intake_approvals":0,"pdc_monitor_runtime_binding_rotations_270":23,"pdc_monitor_runtime_bindings_255":1,"pdc_monitor_stage_activation_approvals":0,"pdc_monitor_stage_activation_writers":5,"pdc_monitor_vehicle_identity_readers":4,"pdc_non_navision_jobcard_receipts":5,"pdc_non_navision_jobcard_source_row_receipts":35,"pdc_online_operational_state":0,"pdc_online_state_receipts":0,"pdc_online_state_revision":1,"pdc_pmb_canonical_admin_countersignatures":340,"pdc_pmb_canonical_apply_authorizations":1,"pdc_pmb_canonical_apply_receipts":1,"pdc_pmb_canonical_manager_approvals":340,"pdc_pmb_canonical_manager_authorities":1,"pdc_pmb_canonical_pair_receipts":340,"pdc_pmb_workbook_apply_authorizations":1,"pdc_pmb_workbook_apply_receipts":1,"pdc_pmb_workbook_operation_reviews":10572,"pdc_pmb_workbook_pair_approvals":80,"pdc_pmb_workbook_pair_receipts":420,"pdc_pmb_workbook_pair_reviews":1344,"pdc_pmb_workbook_previews":3,"pdc_provider_email_observations":54,"pdc_retained_reset_import_receipts_212":1,"pdc_staging_backup_restoration_receipts":1,"pdc_staging_board_purge_receipts":2,"pdc_staging_cleanse_receipts_348":1,"pdc_staging_containment_receipts_347":1,"pdc_staging_environment_sentinel":1,"pdc_staging_monitor_activation_receipts_352":1,"pdc_staging_reset_attestations":1,"pdc_staging_reset_batches":1,"pdc_staging_reset_evidence_corrections":1,"pdc_staging_reset_rows":411,"pdc_staging_verified_backup_manifests":2,"pdc_sublet_booking_history":50,"pdc_sublet_booking_instance_history":10,"pdc_sublet_booking_instances":3,"pdc_sublet_bookings":0,"pdc_sublet_email_update_receipts":0,"pdc_supervised_apply_receipts":10,"pdc_supervised_correction_batches":1,"pdc_supervised_correction_evidence":10,"pdc_supervised_correction_items":10,"pdc_supervised_correction_overlays":8,"pdc_supervised_failures":0,"pdc_supervised_monitor_applications":0,"pdc_supervised_review_queue":0,"pdc_supervised_revision":1,"pdc_supervised_rule_aliases":19,"pdc_supervised_rule_events":23,"pdc_supervised_rule_examples":23,"pdc_supervised_rule_families":23,"pdc_supervised_rule_versions":23,"pdc_supervised_telegram_commands":0,"pdc_supervised_telegram_identities":1,"pdc_supervised_telegram_responses":0,"pdc_uid478_attachment_attempt_receipts":0,"pdc_uid478_attachment_terminal_receipts":0,"pdc_uid478_message_receipts":0,"pdc_uid514_identity_reinstatements_306":1,"pdc_uid514_recovery_authorizations_257":1,"pdc_uid514_recovery_claim_attempts_257":25,"pdc_uid558_exact_existing_vehicle_mutation_receipts_310":0,"pdc_uid558_identity_reinstatements_309":1,"pdc_uid590_591_exact_reinstatements_318":2,"pdc_uid590_activation_reopen_320":1,"pdc_uid590_vin_completion_319":1,"pdc_uid592_exact_reinstatements_327":4,"pdc_uid592_vehicle_vin_completion_330":4,"pdc_user_roles":15,"pdc_vehicle_lifecycle_events":50,"pdc_vehicle_recreation_permissions":6,"pdc_vehicle_tombstones":30,"pdc_workshop_operation_removal_receipts_235":63,"pdc_workshop_operation_removal_undo_receipts_235":0,"restore_test_runs":193,"salespeople":14,"sublet_provider_aliases":62,"sublet_providers":45,"vehicle_aliases":1113,"vehicle_eta_history":0,"vehicle_intelligence_revisions":0,"vehicle_intelligence_summaries":0,"vehicle_lifecycle_resolver_revision":1,"vehicle_master_history":14885,"vehicle_master_identity_conflicts":0,"vehicle_master_operation_receipts":1113,"vehicle_master_revision":1,"vehicle_master_source_records":1113,"vehicle_match_candidates":0,"vehicle_movements":1120,"vehicle_notifications":555,"vehicle_parts_updates":0,"vehicle_sublet_providers":0,"vehicle_timeline_events":0,"vehicle_work_items":3,"vehicle_workshop_line_adjustments":1483,"vehicles":1730,"workshop_admin_block_history":19,"workshop_admin_block_receipts":19,"workshop_admin_blocks":4,"workshop_bay_default_technician_history":2,"workshop_bays":45,"workshop_booking_assignments":0,"workshop_booking_history":4979,"workshop_booking_move_receipts":8,"workshop_bookings":0,"workshop_parts_overrides":22,"workshop_revision":1,"workshop_settings":9,"workshop_stage_aliases":38,"workshop_stages":10,"workshop_station_revision":10,"workshop_technicians":7,"workshop_transition_authorizations":0}'::jsonb)) then raise exception 'PDC_354_BACKUP_TOTAL_MISMATCH' using errcode='55000';end if;
 for n,expected in select key,value::bigint from jsonb_each_text('{"ai_email_analysis_results":0,"ai_email_attachments":104,"ai_email_intake":56,"ai_extracted_fields":0,"ai_intake_config":1,"ai_mapping_rules":17,"ai_proposed_actions":0,"ai_review_items":0,"ai_trusted_senders":0,"ai_undo_actions":0,"ai_workshop_commands":0,"audit_events":23584,"backup_runs":357,"deleted_completed_vehicles":1603,"email_response_drafts":0,"import_runs":0,"label_print_events":0,"legacy_stage_reconciliation_receipts":0,"monitored_mailboxes":1,"navision_backend_audit":155,"navision_backend_records":1358,"navision_backend_revision":1,"navision_board_activations":448,"navision_import_batches":24,"navision_import_items":9701,"navision_initial_scope_approvals":2,"navision_operation_receipts":84,"navision_rollback_items":0,"pdc_ai_intake_auto_activation_receipts":26,"pdc_ai_intake_auto_backlog_receipts":1,"pdc_ai_intake_decision_receipts":5,"pdc_ai_intake_history":444,"pdc_ai_intake_proposals":273,"pdc_ai_intake_revision":1,"pdc_attachment_atomic_contract":1,"pdc_auditor_autonomous_hour_rules":0,"pdc_auditor_booking_work_relations":0,"pdc_auditor_correction_execution_items":0,"pdc_auditor_correction_executions":0,"pdc_auditor_decisions":2,"pdc_auditor_executor_identities":1,"pdc_auditor_finding_evidence":119,"pdc_auditor_finding_history":119,"pdc_auditor_finding_occurrences":119,"pdc_auditor_findings":62,"pdc_auditor_gvm_mappings_225":19,"pdc_auditor_operation_changes":46,"pdc_auditor_operation_runs":23,"pdc_auditor_plan_items_225":332,"pdc_auditor_plans_225":2,"pdc_auditor_report_runs":0,"pdc_auditor_restricted_authority_revocations":0,"pdc_auditor_review_queue_225":140,"pdc_auditor_revision":52,"pdc_auditor_risk_scores":119,"pdc_auditor_rule_commands_227":1,"pdc_auditor_rule_config":4,"pdc_auditor_rule_examples_227":2,"pdc_auditor_rule_families_227":1,"pdc_auditor_rule_versions_227":1,"pdc_auditor_runs":2,"pdc_auditor_service_identities_225":1,"pdc_auditor_telegram_apply_receipts_226":1,"pdc_auditor_telegram_changes_226":82,"pdc_auditor_telegram_deliveries_230":3,"pdc_auditor_telegram_instructions_225":2,"pdc_auditor_telegram_rollback_audit_226":82,"pdc_auditor_telegram_rollback_receipts_226":1,"pdc_auditor_telegram_runs_226":1,"pdc_auditor_user_dealer_scopes":5,"pdc_auditor_worker_identities":2,"pdc_auditor_workshop_revisions":2,"pdc_authenticated_email_attachment_claims":4,"pdc_authenticated_email_attachment_manifests":0,"pdc_authenticated_email_batch_receipts":0,"pdc_authenticated_email_import_receipts":1306,"pdc_authenticated_email_operation_lines":6389,"pdc_bulk_workbook_apply_receipts":1,"pdc_bulk_workbook_authorizations":2,"pdc_bulk_workbook_previews":2,"pdc_bulk_workbook_quarantine":412,"pdc_bulk_workbook_row_receipts":410,"pdc_email_attachment_batch_receipts_323":3,"pdc_email_attachment_batch_superseded_325":10,"pdc_email_communication_action_receipts":0,"pdc_email_communication_receipts":0,"pdc_email_evidence_consumptions":5,"pdc_email_intake_work_receipts":5,"pdc_email_monitor_pilot":1,"pdc_email_monitor_status":1,"pdc_email_source_claims":276,"pdc_email_vehicle_revision":1,"pdc_full_inbox_body_sources_20260821033000":0,"pdc_full_inbox_location_receipts_20260821033000":0,"pdc_full_inbox_parts_receipts_20260821033000":0,"pdc_full_inbox_source_unit_terminals_20260821033000":0,"pdc_generic_current_navision_enrichment_receipts_312":10,"pdc_historical_attachment_source_authorizations_20260821043000":5,"pdc_historical_attachment_source_bindings_20260821043000":0,"pdc_historical_inbox_authorizations_20260821040000":11,"pdc_historical_nonnav_extraction_authorizations_20260821047000":5,"pdc_historical_nonnav_extraction_corrections_20260821049000":1,"pdc_historical_nonnav_extraction_corrections_20260821051000":0,"pdc_historical_pilot_floor_bindings_20260821041000":0,"pdc_jobcard_attachment_import_receipts":19,"pdc_jobcard_attachment_rule_receipts_279":62,"pdc_jobcard_attachment_source_row_receipts":67,"pdc_key_list_apply_receipt_rows":0,"pdc_key_list_decision_receipts":0,"pdc_key_list_proposal_revision":1,"pdc_key_list_proposal_rows":0,"pdc_key_list_proposals":0,"pdc_monitor_exact_sender_enrollments":22,"pdc_monitor_new_build_intake_approvals":0,"pdc_monitor_runtime_binding_rotations_270":23,"pdc_monitor_runtime_bindings_255":1,"pdc_monitor_stage_activation_approvals":0,"pdc_monitor_stage_activation_writers":5,"pdc_monitor_vehicle_identity_readers":4,"pdc_non_navision_jobcard_receipts":5,"pdc_non_navision_jobcard_source_row_receipts":35,"pdc_online_operational_state":0,"pdc_online_state_receipts":0,"pdc_online_state_revision":1,"pdc_pmb_canonical_admin_countersignatures":340,"pdc_pmb_canonical_apply_authorizations":1,"pdc_pmb_canonical_apply_receipts":1,"pdc_pmb_canonical_manager_approvals":340,"pdc_pmb_canonical_manager_authorities":1,"pdc_pmb_canonical_pair_receipts":340,"pdc_pmb_workbook_apply_authorizations":1,"pdc_pmb_workbook_apply_receipts":1,"pdc_pmb_workbook_operation_reviews":10572,"pdc_pmb_workbook_pair_approvals":80,"pdc_pmb_workbook_pair_receipts":420,"pdc_pmb_workbook_pair_reviews":1344,"pdc_pmb_workbook_previews":3,"pdc_provider_email_observations":54,"pdc_retained_reset_import_receipts_212":1,"pdc_staging_backup_restoration_receipts":1,"pdc_staging_board_purge_receipts":2,"pdc_staging_cleanse_receipts_348":1,"pdc_staging_containment_receipts_347":1,"pdc_staging_environment_sentinel":1,"pdc_staging_monitor_activation_receipts_352":1,"pdc_staging_reset_attestations":1,"pdc_staging_reset_batches":1,"pdc_staging_reset_evidence_corrections":1,"pdc_staging_reset_rows":411,"pdc_staging_verified_backup_manifests":2,"pdc_sublet_booking_history":50,"pdc_sublet_booking_instance_history":10,"pdc_sublet_booking_instances":3,"pdc_sublet_bookings":0,"pdc_sublet_email_update_receipts":0,"pdc_supervised_apply_receipts":10,"pdc_supervised_correction_batches":1,"pdc_supervised_correction_evidence":10,"pdc_supervised_correction_items":10,"pdc_supervised_correction_overlays":8,"pdc_supervised_failures":0,"pdc_supervised_monitor_applications":0,"pdc_supervised_review_queue":0,"pdc_supervised_revision":1,"pdc_supervised_rule_aliases":19,"pdc_supervised_rule_events":23,"pdc_supervised_rule_examples":23,"pdc_supervised_rule_families":23,"pdc_supervised_rule_versions":23,"pdc_supervised_telegram_commands":0,"pdc_supervised_telegram_identities":1,"pdc_supervised_telegram_responses":0,"pdc_uid478_attachment_attempt_receipts":0,"pdc_uid478_attachment_terminal_receipts":0,"pdc_uid478_message_receipts":0,"pdc_uid514_identity_reinstatements_306":1,"pdc_uid514_recovery_authorizations_257":1,"pdc_uid514_recovery_claim_attempts_257":25,"pdc_uid558_exact_existing_vehicle_mutation_receipts_310":0,"pdc_uid558_identity_reinstatements_309":1,"pdc_uid590_591_exact_reinstatements_318":2,"pdc_uid590_activation_reopen_320":1,"pdc_uid590_vin_completion_319":1,"pdc_uid592_exact_reinstatements_327":4,"pdc_uid592_vehicle_vin_completion_330":4,"pdc_user_roles":15,"pdc_vehicle_lifecycle_events":50,"pdc_vehicle_recreation_permissions":6,"pdc_vehicle_tombstones":30,"pdc_workshop_operation_removal_receipts_235":63,"pdc_workshop_operation_removal_undo_receipts_235":0,"restore_test_runs":193,"salespeople":14,"sublet_provider_aliases":62,"sublet_providers":45,"vehicle_aliases":1113,"vehicle_eta_history":0,"vehicle_intelligence_revisions":0,"vehicle_intelligence_summaries":0,"vehicle_lifecycle_resolver_revision":1,"vehicle_master_history":14885,"vehicle_master_identity_conflicts":0,"vehicle_master_operation_receipts":1113,"vehicle_master_revision":1,"vehicle_master_source_records":1113,"vehicle_match_candidates":0,"vehicle_movements":1120,"vehicle_notifications":555,"vehicle_parts_updates":0,"vehicle_sublet_providers":0,"vehicle_timeline_events":0,"vehicle_work_items":3,"vehicle_workshop_line_adjustments":1483,"vehicles":1730,"workshop_admin_block_history":19,"workshop_admin_block_receipts":19,"workshop_admin_blocks":4,"workshop_bay_default_technician_history":2,"workshop_bays":45,"workshop_booking_assignments":0,"workshop_booking_history":4979,"workshop_booking_move_receipts":8,"workshop_bookings":0,"workshop_parts_overrides":22,"workshop_revision":1,"workshop_settings":9,"workshop_stage_aliases":38,"workshop_stages":10,"workshop_station_revision":10,"workshop_technicians":7,"workshop_transition_authorizations":0}'::jsonb) loop
  execute format('select count(*) from public.%I',n) into actual;
  if actual is distinct from expected then raise exception 'PDC_354_BACKUP_LIVE_COUNT_DRIFT table=%',n using errcode='55000';end if;
 end loop;
end
$backup_guard$;

create temporary table pdc_354_preserved_pre(table_name text primary key,row_count bigint not null,content_sha256 text not null) on commit drop;
do $preserved_pre$ declare n text;c bigint;h text;begin
 foreach n in array array['ai_intake_config','ai_mapping_rules','ai_trusted_senders','monitored_mailboxes','navision_backend_revision','navision_initial_scope_approvals','pdc_ai_intake_revision','pdc_attachment_atomic_contract','pdc_auditor_autonomous_hour_rules','pdc_auditor_executor_identities','pdc_auditor_gvm_mappings_225','pdc_auditor_restricted_authority_revocations','pdc_auditor_rule_commands_227','pdc_auditor_rule_config','pdc_auditor_rule_examples_227','pdc_auditor_rule_families_227','pdc_auditor_rule_versions_227','pdc_auditor_service_identities_225','pdc_auditor_user_dealer_scopes','pdc_auditor_worker_identities','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_email_vehicle_revision','pdc_key_list_proposal_revision','pdc_monitor_exact_sender_enrollments','pdc_monitor_runtime_bindings_255','pdc_monitor_stage_activation_writers','pdc_monitor_vehicle_identity_readers','pdc_online_state_revision','pdc_pmb_canonical_manager_authorities','pdc_staging_environment_sentinel','pdc_staging_verified_backup_manifests','pdc_supervised_revision','pdc_supervised_rule_aliases','pdc_supervised_rule_examples','pdc_supervised_rule_families','pdc_supervised_rule_versions','pdc_supervised_telegram_identities','pdc_user_roles','salespeople','sublet_provider_aliases','sublet_providers','vehicle_lifecycle_resolver_revision','vehicle_master_revision','workshop_bays','workshop_revision','workshop_settings','workshop_stage_aliases','workshop_stages','workshop_station_revision','workshop_technicians']::text[] loop
  execute format('select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,'''' order by to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') from public.%I t',n) into c,h;
  insert into pdc_354_preserved_pre values(n,c,h);
 end loop;
end $preserved_pre$;

create temporary table pdc_354_replay_pre on commit drop as
select coalesce(max(case when provider_uid~'[0-9]+$' then substring(provider_uid from '([0-9]+)$')::bigint end) filter(where provider_uid!~'594$'),593::bigint) inbox_denied_through,
       greatest(coalesce((select max(telegram_update_id) from public.pdc_auditor_telegram_instructions_225),0),coalesce((select max(telegram_update_id) from public.pdc_auditor_telegram_deliveries_230),0)) telegram_denied_through
from public.ai_email_intake;

-- Snapshot every enabled user trigger attached to a purge relation, bind the
-- exact live catalog, and transactionally point it at an owner-only passthrough.
-- CREATE OR REPLACE keeps each trigger present/enabled; exact originals are restored.
create temporary table pdc_354_trigger_defs on commit drop as
select c.relname::text table_name,t.tgname::text trigger_name,pg_get_triggerdef(t.oid,true) definition
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
where not t.tgisinternal and n.nspname='public' and (c.relname=any(array['ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_proposed_actions','ai_review_items','ai_undo_actions','ai_workshop_commands','audit_events','backup_runs','deleted_completed_vehicles','email_response_drafts','import_runs','label_print_events','legacy_stage_reconciliation_receipts','navision_backend_audit','navision_backend_records','navision_board_activations','navision_import_batches','navision_import_items','navision_operation_receipts','navision_rollback_items','pdc_ai_intake_auto_activation_receipts','pdc_ai_intake_auto_backlog_receipts','pdc_ai_intake_decision_receipts','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_auditor_booking_work_relations','pdc_auditor_correction_execution_items','pdc_auditor_correction_executions','pdc_auditor_decisions','pdc_auditor_finding_evidence','pdc_auditor_finding_history','pdc_auditor_finding_occurrences','pdc_auditor_findings','pdc_auditor_operation_changes','pdc_auditor_operation_runs','pdc_auditor_plan_items_225','pdc_auditor_plans_225','pdc_auditor_report_runs','pdc_auditor_review_queue_225','pdc_auditor_revision','pdc_auditor_risk_scores','pdc_auditor_runs','pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_changes_226','pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_auditor_telegram_rollback_audit_226','pdc_auditor_telegram_rollback_receipts_226','pdc_auditor_telegram_runs_226','pdc_auditor_workshop_revisions','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_attachment_manifests','pdc_authenticated_email_batch_receipts','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_row_receipts','pdc_email_attachment_batch_receipts_323','pdc_email_attachment_batch_superseded_325','pdc_email_communication_action_receipts','pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_email_intake_work_receipts','pdc_email_source_claims','pdc_full_inbox_body_sources_20260821033000','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_full_inbox_source_unit_terminals_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_historical_attachment_source_authorizations_20260821043000','pdc_historical_attachment_source_bindings_20260821043000','pdc_historical_inbox_authorizations_20260821040000','pdc_historical_nonnav_extraction_authorizations_20260821047000','pdc_historical_nonnav_extraction_corrections_20260821049000','pdc_historical_nonnav_extraction_corrections_20260821051000','pdc_historical_pilot_floor_bindings_20260821041000','pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_rule_receipts_279','pdc_jobcard_attachment_source_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_decision_receipts','pdc_key_list_proposal_rows','pdc_key_list_proposals','pdc_monitor_new_build_intake_approvals','pdc_monitor_runtime_binding_rotations_270','pdc_monitor_stage_activation_approvals','pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts','pdc_online_operational_state','pdc_online_state_receipts','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_previews','pdc_provider_email_observations','pdc_retained_reset_import_receipts_212','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_cleanse_receipts_348','pdc_staging_containment_receipts_347','pdc_staging_monitor_activation_receipts_352','pdc_staging_reset_attestations','pdc_staging_reset_batches','pdc_staging_reset_evidence_corrections','pdc_staging_reset_rows','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_supervised_apply_receipts','pdc_supervised_correction_batches','pdc_supervised_correction_evidence','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_failures','pdc_supervised_monitor_applications','pdc_supervised_review_queue','pdc_supervised_rule_events','pdc_supervised_telegram_commands','pdc_supervised_telegram_responses','pdc_uid478_attachment_attempt_receipts','pdc_uid478_attachment_terminal_receipts','pdc_uid478_message_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid514_recovery_authorizations_257','pdc_uid514_recovery_claim_attempts_257','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','restore_test_runs','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_bay_default_technician_history','workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','workshop_transition_authorizations']::text[]) or c.relname='pdc_staging_verified_backup_manifests');
create function public.pdc_full_reset_trigger_passthrough_354() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$begin if tg_op='DELETE' then return old;else return new;end if;end$$;
revoke all on function public.pdc_full_reset_trigger_passthrough_354() from public,anon,authenticated,service_role;
do $trigger_guard$ declare n bigint;h text;d record;patched text;begin
 select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(definition,'' order by table_name,trigger_name),''),'UTF8'),'sha256'),'hex') into n,h from pdc_354_trigger_defs;
 if n<>190 or h<>'8cc5f736d4480c0c2495b9387875c846df23833da6fdfdaf38175690463ba7ad' then raise exception 'PDC_354_TRIGGER_CATALOG_DRIFT count=% hash=%',n,h using errcode='55000';end if;
 for d in select * from pdc_354_trigger_defs order by table_name,trigger_name loop
  patched:=replace(d.definition,'CREATE TRIGGER','CREATE OR REPLACE TRIGGER');
  patched:=regexp_replace(patched,'EXECUTE FUNCTION .*$','EXECUTE FUNCTION public.pdc_full_reset_trigger_passthrough_354()');
  if patched=d.definition then raise exception 'PDC_354_TRIGGER_REPLACEMENT_FAILED table=% trigger=%',d.table_name,d.trigger_name using errcode='55000';end if;
  execute patched;
 end loop;
end $trigger_guard$;

-- Existing reviewed per-row compaction guards remain active and admit only the
-- exact owner transaction/table/hash tuple. No trigger is disabled.
select set_config('pdc.complete_vehicle_delete_contract','active',true);
select set_config('pdc.full_history_reset_354','0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0',true);

-- Break the only live RESTRICT cycle through its nullable reviewed claim link.
update public.pdc_bulk_workbook_authorizations set status='expired',claimed_at=null,claimed_payload_sha256=null,claimed_preview_id=null where claimed_preview_id is not null;
select set_config('pdc.complete_vehicle_delete_table','ai_extracted_fields',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_extracted_fields";
select set_config('pdc.complete_vehicle_delete_table','ai_proposed_actions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_proposed_actions";
select set_config('pdc.complete_vehicle_delete_table','ai_review_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_review_items";
select set_config('pdc.complete_vehicle_delete_table','ai_undo_actions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_undo_actions";
select set_config('pdc.complete_vehicle_delete_table','ai_workshop_commands',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_workshop_commands";
select set_config('pdc.complete_vehicle_delete_table','audit_events',true);
select set_config('pdc.complete_vehicle_delete_row_hash','934d6a85c1e9dfb6b4fc1c31073444e7d2cb2af9393e69828f2b77d4bdb46d52',true);
delete from public."audit_events";
select set_config('pdc.complete_vehicle_delete_table','backup_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','3996fcad62d91e4bf91e45dc8c73d96c5d3324f8c4a35d42bc3d232715bb42ea',true);
delete from public."backup_runs";
select set_config('pdc.complete_vehicle_delete_table','deleted_completed_vehicles',true);
select set_config('pdc.complete_vehicle_delete_row_hash','9c9d06c36f00fc9ce9592b013b78212ca5e110468a8c3663cf4b51b266664a66',true);
delete from public."deleted_completed_vehicles";
select set_config('pdc.complete_vehicle_delete_table','email_response_drafts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."email_response_drafts";
select set_config('pdc.complete_vehicle_delete_table','import_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."import_runs";
select set_config('pdc.complete_vehicle_delete_table','label_print_events',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."label_print_events";
select set_config('pdc.complete_vehicle_delete_table','legacy_stage_reconciliation_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."legacy_stage_reconciliation_receipts";
select set_config('pdc.complete_vehicle_delete_table','navision_backend_audit',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d2ebacb0d0d5f1ec1a4dcde800e19f4735f7cef555cf7d4fb06c5d59e9d1dc79',true);
delete from public."navision_backend_audit";
select set_config('pdc.complete_vehicle_delete_table','navision_board_activations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','b6ddaf283d4902c3618bc8b61bb224aaec94918908523fed38fa6e96b7f7e1de',true);
delete from public."navision_board_activations";
select set_config('pdc.complete_vehicle_delete_table','navision_import_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','8d8c3fbd9aae12afaa99ce33edb90e324535065d3e1c3f8ca58e3cd5e439696f',true);
delete from public."navision_import_items";
select set_config('pdc.complete_vehicle_delete_table','navision_rollback_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."navision_rollback_items";
select set_config('pdc.complete_vehicle_delete_table','navision_operation_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','e3a5378f1fe8f9b82e0008a185fea8198db339b25459501fa5fc853fbedea079',true);
delete from public."navision_operation_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_ai_intake_auto_activation_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','6167050dbebf49558b6e9199c50c8258f51f06c519664f065278f83c1bec9eaa',true);
delete from public."pdc_ai_intake_auto_activation_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_ai_intake_auto_backlog_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4eebb5ee69d15285683618ae4cf07383f31976abb960e258100d1d7b782b8e2d',true);
delete from public."pdc_ai_intake_auto_backlog_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_ai_intake_decision_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','8427212f097f1db6de6c824ea56aed8990a2a35e07d76364c2e9e6353ca2fa93',true);
delete from public."pdc_ai_intake_decision_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_ai_intake_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','1b11d2cef814c259100f3e5b86797f28e0fc9a9854fe017e6568a23e85cc1ab3',true);
delete from public."pdc_ai_intake_history";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_booking_work_relations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_auditor_booking_work_relations";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_correction_execution_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_auditor_correction_execution_items";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_correction_executions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_auditor_correction_executions";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_decisions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','419afc551b8b594a0d12accdd0b9ce14c64c92dc7cb8f828ba53deaecfbabb41',true);
delete from public."pdc_auditor_decisions";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_finding_evidence',true);
select set_config('pdc.complete_vehicle_delete_row_hash','3f281b0093906e592378fdb4e51514cebff28b8d9dd92a2538dc1a956ad49a06',true);
delete from public."pdc_auditor_finding_evidence";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_finding_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','10a7af25b9f72a5bda5d882cae150ffef0bb5dd4825aa44f12b7f4b9189d897b',true);
delete from public."pdc_auditor_finding_history";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_operation_changes',true);
select set_config('pdc.complete_vehicle_delete_row_hash','12c0df1f3587bf026ed6aee21cce781e2981cba45204c1bccb915cd0e5795034',true);
delete from public."pdc_auditor_operation_changes";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_operation_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','a986c831b1d98293de46d8baf5223aca447052953b9ba8b79796eb664dd7d2e2',true);
delete from public."pdc_auditor_operation_runs";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_report_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_auditor_report_runs";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_review_queue_225',true);
select set_config('pdc.complete_vehicle_delete_row_hash','2383877621a3b86577b0c0c9d3b3c1f526b4e663af60fb1ab4f2ca5cbfa772c4',true);
delete from public."pdc_auditor_review_queue_225";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_revision',true);
select set_config('pdc.complete_vehicle_delete_row_hash','544bed7573c37c17c23388b132535e24bf67b7802ef8617a52f41febdd193c42',true);
delete from public."pdc_auditor_revision";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_risk_scores',true);
select set_config('pdc.complete_vehicle_delete_row_hash','1cb350ca23b39a326bf24ea61560bf690335073f74d60fde2d760c7d37846e8b',true);
delete from public."pdc_auditor_risk_scores";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_finding_occurrences',true);
select set_config('pdc.complete_vehicle_delete_row_hash','3adf777a2535ba19e3a31c9d446cf94249dc3c4870fcfa42936c7a3cb3dd5412',true);
delete from public."pdc_auditor_finding_occurrences";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_findings',true);
select set_config('pdc.complete_vehicle_delete_row_hash','01c27f9f8c08c71ee854da7337b8626be4ae3faaa9055f1af24d546e6234d82a',true);
delete from public."pdc_auditor_findings";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','3e823699575a2ad9fda4871e835f210dd17032c7059ec928fd0ab55d45c2e5cd',true);
delete from public."pdc_auditor_runs";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_apply_receipts_226',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d4568ea4cbb3f12bef7a0dd27cc450c6c52cdbab96ca70156925e8f323a927e9',true);
delete from public."pdc_auditor_telegram_apply_receipts_226";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_deliveries_230',true);
select set_config('pdc.complete_vehicle_delete_row_hash','51790a67bc3da5b2c0e3a41ec28cd4e73b2ed5de087ae0b30d1231e583d4dd11',true);
delete from public."pdc_auditor_telegram_deliveries_230";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_rollback_audit_226',true);
select set_config('pdc.complete_vehicle_delete_row_hash','95cc58a61b26e4dc78789047cfb05baa7c548b89fa01dd9b3b69a8223b10ff05',true);
delete from public."pdc_auditor_telegram_rollback_audit_226";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_changes_226',true);
select set_config('pdc.complete_vehicle_delete_row_hash','28bd94a35555dc3d6171c02a04d0d59f347e8377d26b4e20db0a18fbabee01b8',true);
delete from public."pdc_auditor_telegram_changes_226";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_plan_items_225',true);
select set_config('pdc.complete_vehicle_delete_row_hash','9b56447dc98813741223d8067a25d8d9aca7bf57044785213aa558c74d2faa11',true);
delete from public."pdc_auditor_plan_items_225";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_workshop_revisions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','886efbb6076a579f51ff02720c2f423adff1c6bc46b1f8142aae370324879a70',true);
delete from public."pdc_auditor_workshop_revisions";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_rollback_receipts_226',true);
select set_config('pdc.complete_vehicle_delete_row_hash','50fe2ba700b5afe59de17ad0c989ab27aba3c6650b7e200cdd004bbf64a58f79',true);
delete from public."pdc_auditor_telegram_rollback_receipts_226";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_runs_226',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5aed1729d96dee56219f7d3cebd1058ae3828d60a4f866482f9b7a6c396f2a75',true);
delete from public."pdc_auditor_telegram_runs_226";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_plans_225',true);
select set_config('pdc.complete_vehicle_delete_row_hash','1eef5f128feeb1869a0c4445df4aedbad62e02045cdec08ec93d467f61396124',true);
delete from public."pdc_auditor_plans_225";
select set_config('pdc.complete_vehicle_delete_table','pdc_auditor_telegram_instructions_225',true);
select set_config('pdc.complete_vehicle_delete_row_hash','bbd73924e66beb7ba13edf55ef49b1858bf050ac40f804f267101f4a8e6db100',true);
delete from public."pdc_auditor_telegram_instructions_225";
select set_config('pdc.complete_vehicle_delete_table','pdc_authenticated_email_attachment_claims',true);
select set_config('pdc.complete_vehicle_delete_row_hash','ba4613fe98622a5683053c4aae0d50853b8e6abbb8bcfd4c6e5158ca8c59b010',true);
delete from public."pdc_authenticated_email_attachment_claims";
select set_config('pdc.complete_vehicle_delete_table','pdc_authenticated_email_attachment_manifests',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_authenticated_email_attachment_manifests";
select set_config('pdc.complete_vehicle_delete_table','pdc_authenticated_email_batch_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_authenticated_email_batch_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_bulk_workbook_quarantine',true);
select set_config('pdc.complete_vehicle_delete_row_hash','88d1b5f37e8eb65785e246f7a50671fe3706c943bd939b744dc92fbd5c970603',true);
delete from public."pdc_bulk_workbook_quarantine";
select set_config('pdc.complete_vehicle_delete_table','pdc_bulk_workbook_row_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','7c4bb8229fc6c3078f1c01103c5c6174ace0b2f1d77668d2f54b226c53620d47',true);
delete from public."pdc_bulk_workbook_row_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_bulk_workbook_apply_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','1dc9dc2c6cf491ced27cb4246db5c2975e3b48a03ed8076058f311eee0aeb826',true);
delete from public."pdc_bulk_workbook_apply_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_bulk_workbook_previews',true);
select set_config('pdc.complete_vehicle_delete_row_hash','aa022e978e358efa279357d98aea6eb67e4e431bb75fe2afcca33e97180569f7',true);
delete from public."pdc_bulk_workbook_previews";
select set_config('pdc.complete_vehicle_delete_table','pdc_bulk_workbook_authorizations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','c3a2442583446ea6dca62234fd927438ea3fe47ecc2bf60e05b5d0ed220f0167',true);
delete from public."pdc_bulk_workbook_authorizations";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_attachment_batch_receipts_323',true);
select set_config('pdc.complete_vehicle_delete_row_hash','9d68275513a030c3cbbf159eb637d6b666ff522600c9fcea1340f4dd166f4c65',true);
delete from public."pdc_email_attachment_batch_receipts_323";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_attachment_batch_superseded_325',true);
select set_config('pdc.complete_vehicle_delete_row_hash','292cd6ccd898db872cf0577aa2909bbb1ae6d1c9c249f9b7f938bdc24113287f',true);
delete from public."pdc_email_attachment_batch_superseded_325";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_communication_action_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_email_communication_action_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_communication_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_email_communication_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_evidence_consumptions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','6fd4b9d0668570d1a7c22582b1d4f88b30799c988c38543bd68883475fbb2863',true);
delete from public."pdc_email_evidence_consumptions";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_intake_work_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d6a7b7c2aebd633cad33970f1e46829410fe76c29f77b8560f4f507f29e3a689',true);
delete from public."pdc_email_intake_work_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_email_source_claims',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5b242453e7b97c649ca2d41586ca1e326b3743a60057533a2832ca92b42a8c71',true);
delete from public."pdc_email_source_claims";
select set_config('pdc.complete_vehicle_delete_table','pdc_full_inbox_location_receipts_20260821033000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_full_inbox_location_receipts_20260821033000";
select set_config('pdc.complete_vehicle_delete_table','pdc_full_inbox_parts_receipts_20260821033000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_full_inbox_parts_receipts_20260821033000";
select set_config('pdc.complete_vehicle_delete_table','pdc_full_inbox_body_sources_20260821033000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_full_inbox_body_sources_20260821033000";
select set_config('pdc.complete_vehicle_delete_table','pdc_full_inbox_source_unit_terminals_20260821033000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_full_inbox_source_unit_terminals_20260821033000";
select set_config('pdc.complete_vehicle_delete_table','pdc_generic_current_navision_enrichment_receipts_312',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5c9a882408905d1501de5f91a2dbd7f7526fc8aec929d7ce6fe41dd47ce42baa',true);
delete from public."pdc_generic_current_navision_enrichment_receipts_312";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_attachment_source_bindings_20260821043000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_historical_attachment_source_bindings_20260821043000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_nonnav_extraction_corrections_20260821051000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_historical_nonnav_extraction_corrections_20260821051000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_nonnav_extraction_corrections_20260821049000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','70edb5ac8479bf194bd9458556befd1d17f78a89ee8e7553f137c708c05c4dfc',true);
delete from public."pdc_historical_nonnav_extraction_corrections_20260821049000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_nonnav_extraction_authorizations_20260821047000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4131ddce617c761760008f6f51dadceae5752bd9c022e126f5625309719ef148',true);
delete from public."pdc_historical_nonnav_extraction_authorizations_20260821047000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_attachment_source_authorizations_20260821043000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','2e4a74d772bf46202cffcde87c269a1b2cbc18f6c56d89f0afdf02ad8c481830',true);
delete from public."pdc_historical_attachment_source_authorizations_20260821043000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_pilot_floor_bindings_20260821041000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_historical_pilot_floor_bindings_20260821041000";
select set_config('pdc.complete_vehicle_delete_table','pdc_historical_inbox_authorizations_20260821040000',true);
select set_config('pdc.complete_vehicle_delete_row_hash','b40d304f441cf5e4636947e5db48047d2db8a1207f715378294f073e7ed1a2cf',true);
delete from public."pdc_historical_inbox_authorizations_20260821040000";
select set_config('pdc.complete_vehicle_delete_table','pdc_jobcard_attachment_rule_receipts_279',true);
select set_config('pdc.complete_vehicle_delete_row_hash','c8703fd462565d275977dcdf85b4ea166c17176f498c1171e3a5751ee83a816e',true);
delete from public."pdc_jobcard_attachment_rule_receipts_279";
select set_config('pdc.complete_vehicle_delete_table','pdc_jobcard_attachment_source_row_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','707784bcc721ce7be77ae40929b0cf03888b0950e1b96c6f058c0af6b05698c6',true);
delete from public."pdc_jobcard_attachment_source_row_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_key_list_apply_receipt_rows',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_key_list_apply_receipt_rows";
select set_config('pdc.complete_vehicle_delete_table','pdc_key_list_decision_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_key_list_decision_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_key_list_proposal_rows',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_key_list_proposal_rows";
select set_config('pdc.complete_vehicle_delete_table','pdc_key_list_proposals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_key_list_proposals";
select set_config('pdc.complete_vehicle_delete_table','pdc_monitor_new_build_intake_approvals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_monitor_new_build_intake_approvals";
select set_config('pdc.complete_vehicle_delete_table','pdc_monitor_runtime_binding_rotations_270',true);
select set_config('pdc.complete_vehicle_delete_row_hash','9db8de7e0e70a752c0bd968cdbad1243b73a5734ea2461c7984433aa3d882d33',true);
delete from public."pdc_monitor_runtime_binding_rotations_270";
select set_config('pdc.complete_vehicle_delete_table','pdc_monitor_stage_activation_approvals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_monitor_stage_activation_approvals";
select set_config('pdc.complete_vehicle_delete_table','pdc_non_navision_jobcard_source_row_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','701f8af5b51719443cf41a07930dce95bcef050d6716148e3924cb8bc0e4c468',true);
delete from public."pdc_non_navision_jobcard_source_row_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_non_navision_jobcard_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','89d99f6810605192fefb61a7a705ab3b0e30516b9a71aceb1ed9d4915990b5bd',true);
delete from public."pdc_non_navision_jobcard_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_online_operational_state',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_online_operational_state";
select set_config('pdc.complete_vehicle_delete_table','pdc_online_state_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_online_state_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_canonical_admin_countersignatures',true);
select set_config('pdc.complete_vehicle_delete_row_hash','8e9e9ab538c4353e2355ad8d396400a1d498c035ee905d4e4d5c459db4b5e0dc',true);
delete from public."pdc_pmb_canonical_admin_countersignatures";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_canonical_manager_approvals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','89ca35f3a5cef33049c22b969c97e8506b5cf97112909db1a46907316d3f16b0',true);
delete from public."pdc_pmb_canonical_manager_approvals";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_canonical_pair_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d4a71f89f556b86cf82de253fbe2d272cc1b57a469f11d68f62e8b71990666e6',true);
delete from public."pdc_pmb_canonical_pair_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_canonical_apply_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d311752ee3a304c2a8ac4a7bfcb252303bcdbe4b19aa3e8fb91bc3b5f42c884d',true);
delete from public."pdc_pmb_canonical_apply_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_canonical_apply_authorizations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','ed9add10964b990f5ef3719a9292092522877b0f7ceb07ffb2da9f24d80d67a3',true);
delete from public."pdc_pmb_canonical_apply_authorizations";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_operation_reviews',true);
select set_config('pdc.complete_vehicle_delete_row_hash','1b0da1cb309e3818db29b65bf6323cfae192a32e87e425d52b00756b02a0c71d',true);
delete from public."pdc_pmb_workbook_operation_reviews";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_pair_approvals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','03121209bd24e7e642be8743a76de13b96d6ab98aa759c5cf6c8787a3a8fbe33',true);
delete from public."pdc_pmb_workbook_pair_approvals";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_pair_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','bce46b14e11959e39b63f5e795c257e59ee3282daa76e61ec1697bf6eb0a7c34',true);
delete from public."pdc_pmb_workbook_pair_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_apply_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','bbbe6381e81a95030d5395e563434f55d9c317a3051acdf0371ff195ddf93565',true);
delete from public."pdc_pmb_workbook_apply_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_apply_authorizations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','238c47766d88fba16832ef27e16dc909a6e227501a0f74a54b4b21e8286e05ce',true);
delete from public."pdc_pmb_workbook_apply_authorizations";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_pair_reviews',true);
select set_config('pdc.complete_vehicle_delete_row_hash','abf44ba934fcf1983115b6383396e6f6fe9d7677be98b7ee5bd1878ec97787ff',true);
delete from public."pdc_pmb_workbook_pair_reviews";
select set_config('pdc.complete_vehicle_delete_table','pdc_pmb_workbook_previews',true);
select set_config('pdc.complete_vehicle_delete_row_hash','ccbe52dd664d02d8053e80b617578f817ccdd0a6667d9daed6d7f336534ba6a4',true);
delete from public."pdc_pmb_workbook_previews";
select set_config('pdc.complete_vehicle_delete_table','pdc_provider_email_observations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','15214e29250889771c4d2354d628f040bc68d5e6a4face6a04f56372e67a1480',true);
delete from public."pdc_provider_email_observations";
select set_config('pdc.complete_vehicle_delete_table','pdc_retained_reset_import_receipts_212',true);
select set_config('pdc.complete_vehicle_delete_row_hash','cd9f2c4b73b304eee4181d0d7e3980a5ea861f1419f230a82722f47fd620c1dd',true);
delete from public."pdc_retained_reset_import_receipts_212";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_backup_restoration_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','f38162efae1dd2de72180b755c0c29a10cef183dcda7485c21675d73d7891273',true);
delete from public."pdc_staging_backup_restoration_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_board_purge_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','56797b44fedd669267376463d7f674b6127bfec6aad4a108f3c45302de0409de',true);
delete from public."pdc_staging_board_purge_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_cleanse_receipts_348',true);
select set_config('pdc.complete_vehicle_delete_row_hash','a5bbf9707c7267b4dd53c92182225944d3e2d5f0f1e80116aaa0a5d19d9fd1a6',true);
delete from public."pdc_staging_cleanse_receipts_348";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_containment_receipts_347',true);
select set_config('pdc.complete_vehicle_delete_row_hash','61f46e6d4083c730ed0f84ae19ae692035125db06af3ba9a3c1ab9ee7a26336e',true);
delete from public."pdc_staging_containment_receipts_347";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_monitor_activation_receipts_352',true);
select set_config('pdc.complete_vehicle_delete_row_hash','431cac99a21a4e39e03b032b7d674bc1091f0d040dace7f519d51664a427e047',true);
delete from public."pdc_staging_monitor_activation_receipts_352";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_reset_evidence_corrections',true);
select set_config('pdc.complete_vehicle_delete_row_hash','e01fe94df42998f9eeea940e79f503f2fa50d4f2aedb4a245eb2c4c83308d79e',true);
delete from public."pdc_staging_reset_evidence_corrections";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_reset_attestations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','76f3bbb209af1fed46fb73c30867adb2653a2e088f19fe9234cbd2b7d3348e26',true);
delete from public."pdc_staging_reset_attestations";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_reset_rows',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5c912427470fe087cfe4d593df432a011b77b0c732950628f8aa9b6640f2405e',true);
delete from public."pdc_staging_reset_rows";
select set_config('pdc.complete_vehicle_delete_table','pdc_staging_reset_batches',true);
select set_config('pdc.complete_vehicle_delete_row_hash','eae747377adc9a31c304411a850ebbe48441e7362ac7742951415805de4caa09',true);
delete from public."pdc_staging_reset_batches";
select set_config('pdc.complete_vehicle_delete_table','pdc_sublet_booking_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5a96540f4c312463b24d3073a19267fa034eeadd093279317e1e992299aec128',true);
delete from public."pdc_sublet_booking_history";
select set_config('pdc.complete_vehicle_delete_table','pdc_sublet_booking_instance_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','a0e77b1228ebc2412239a4a837354a57d185192e52bb64c55983cd1a87df13cc',true);
delete from public."pdc_sublet_booking_instance_history";
select set_config('pdc.complete_vehicle_delete_table','pdc_sublet_bookings',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_sublet_bookings";
select set_config('pdc.complete_vehicle_delete_table','pdc_sublet_email_update_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_sublet_email_update_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_sublet_booking_instances',true);
select set_config('pdc.complete_vehicle_delete_row_hash','0a86f246c9c91f080b44c225861934aa7b0c52c3a08c4b387264dfc5eea3513c',true);
delete from public."pdc_sublet_booking_instances";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_apply_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','8d5c61198f4b853484e40a6bd912f3e462471735d5859a6639dbf936889d2557',true);
delete from public."pdc_supervised_apply_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_correction_evidence',true);
select set_config('pdc.complete_vehicle_delete_row_hash','e0ca093d47cb05c51099c0b503e3b72d38bb52deae21b7f8c3ef2d5088086081',true);
delete from public."pdc_supervised_correction_evidence";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_correction_overlays',true);
select set_config('pdc.complete_vehicle_delete_row_hash','0eda06c9348be25ffb34b8771698d4f023d491b16ac39d67f903aa7e30755ad3',true);
delete from public."pdc_supervised_correction_overlays";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_correction_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','62fd70a930a6147ecb8a0cadebe65ecca30d312eb30294d7862b5a514bbc0b23',true);
delete from public."pdc_supervised_correction_items";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_correction_batches',true);
select set_config('pdc.complete_vehicle_delete_row_hash','b0b87663fea9a56412e0a71cc861bd69c59e2b86d0e20f152abbf7c8f9414b6a',true);
delete from public."pdc_supervised_correction_batches";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_failures',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_supervised_failures";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_monitor_applications',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_supervised_monitor_applications";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_review_queue',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_supervised_review_queue";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_rule_events',true);
select set_config('pdc.complete_vehicle_delete_row_hash','430fcd163ee03b36f9b02b40e65de648c34b9e62dc8074c9b3e0444a6b88c28e',true);
delete from public."pdc_supervised_rule_events";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_telegram_responses',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_supervised_telegram_responses";
select set_config('pdc.complete_vehicle_delete_table','pdc_supervised_telegram_commands',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_supervised_telegram_commands";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid478_attachment_terminal_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_uid478_attachment_terminal_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_jobcard_attachment_import_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','77d07368c568d91ef4f311d22260b1851856773c751d920632d6786f276624d2',true);
delete from public."pdc_jobcard_attachment_import_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid478_attachment_attempt_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_uid478_attachment_attempt_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid478_message_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_uid478_message_receipts";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid514_identity_reinstatements_306',true);
select set_config('pdc.complete_vehicle_delete_row_hash','cdc7dac0ce14ce5b49b1220174b09abe0adb6d4562bc41ffd7cac95a9a0299cd',true);
delete from public."pdc_uid514_identity_reinstatements_306";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid514_recovery_claim_attempts_257',true);
select set_config('pdc.complete_vehicle_delete_row_hash','d106b8df5adcf947da8a6cb126af94a671214818fe9b49370f16b22c9ac50254',true);
delete from public."pdc_uid514_recovery_claim_attempts_257";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid514_recovery_authorizations_257',true);
select set_config('pdc.complete_vehicle_delete_row_hash','67c44cff0dbc920b0f7264a3a4a85312022ec2895de07784da22275e4ee7e1f2',true);
delete from public."pdc_uid514_recovery_authorizations_257";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid558_exact_existing_vehicle_mutation_receipts_310',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_uid558_exact_existing_vehicle_mutation_receipts_310";
select set_config('pdc.complete_vehicle_delete_table','pdc_ai_intake_proposals',true);
select set_config('pdc.complete_vehicle_delete_row_hash','3850661dbdd1d5a9528a9f2cde5a1787ad46f894247b86e4d66f0765d5308ce4',true);
delete from public."pdc_ai_intake_proposals";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid558_identity_reinstatements_309',true);
select set_config('pdc.complete_vehicle_delete_row_hash','8e1008cbd4a783c538cdb202852e5ffc909650d9bb836836f82157ff77094fc7',true);
delete from public."pdc_uid558_identity_reinstatements_309";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid590_591_exact_reinstatements_318',true);
select set_config('pdc.complete_vehicle_delete_row_hash','fa1584343ae54129a4f2c92b5d2f7f4e232a44afcfc0e27c06bb43e6a5a368f6',true);
delete from public."pdc_uid590_591_exact_reinstatements_318";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid590_activation_reopen_320',true);
select set_config('pdc.complete_vehicle_delete_row_hash','6336e15a06d3aa07f458c399ba268db1cadbe0205e566e222ef0f5782eafddcf',true);
delete from public."pdc_uid590_activation_reopen_320";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid590_vin_completion_319',true);
select set_config('pdc.complete_vehicle_delete_row_hash','52a5035de04d8ec2ea4d8b015ad02963c967e5d2f6194ad31196cf5609b8f292',true);
delete from public."pdc_uid590_vin_completion_319";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid592_vehicle_vin_completion_330',true);
select set_config('pdc.complete_vehicle_delete_row_hash','0da07f2af8c74811735b8c23a62c736210b67d83b579e6362e7298a44eb81f2a',true);
delete from public."pdc_uid592_vehicle_vin_completion_330";
select set_config('pdc.complete_vehicle_delete_table','pdc_uid592_exact_reinstatements_327',true);
select set_config('pdc.complete_vehicle_delete_row_hash','bad3ce8884387c789b7414c73e404d945581b65ef7d2c883e6c78dcf9ccbe97a',true);
delete from public."pdc_uid592_exact_reinstatements_327";
select set_config('pdc.complete_vehicle_delete_table','ai_email_attachments',true);
select set_config('pdc.complete_vehicle_delete_row_hash','b02f7c369699dcb9e39ed2fa6ec7762aad16cfbfc8f6b8f0fefda1af0e4505af',true);
delete from public."ai_email_attachments";
select set_config('pdc.complete_vehicle_delete_table','pdc_vehicle_lifecycle_events',true);
select set_config('pdc.complete_vehicle_delete_row_hash','a4dd22e20d4e401cca4ca5e7942fef00f7d1e7a32f61239ca21ee9ed1de196a2',true);
delete from public."pdc_vehicle_lifecycle_events";
select set_config('pdc.complete_vehicle_delete_table','pdc_vehicle_recreation_permissions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','84b78fcb16a86c82ba791f2cb300889d6d47f371abd24b550eb6a023c4ecc5ad',true);
delete from public."pdc_vehicle_recreation_permissions";
select set_config('pdc.complete_vehicle_delete_table','pdc_vehicle_tombstones',true);
select set_config('pdc.complete_vehicle_delete_row_hash','59e38dbbe7e9130ef0540ccb8892c9195e6be847b92ea902496296ea90aec3c4',true);
delete from public."pdc_vehicle_tombstones";
select set_config('pdc.complete_vehicle_delete_table','pdc_workshop_operation_removal_undo_receipts_235',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."pdc_workshop_operation_removal_undo_receipts_235";
select set_config('pdc.complete_vehicle_delete_table','pdc_workshop_operation_removal_receipts_235',true);
select set_config('pdc.complete_vehicle_delete_row_hash','05ac1f3d790f8edc08477e476206b17d29478bc82b7375883f87d668d9f8f32a',true);
delete from public."pdc_workshop_operation_removal_receipts_235";
select set_config('pdc.complete_vehicle_delete_table','restore_test_runs',true);
select set_config('pdc.complete_vehicle_delete_row_hash','fedce0c1ef2c620c43b2d8c2e2f33b52b60a8c1499eb46bf5d01c50a175f554d',true);
delete from public."restore_test_runs";
select set_config('pdc.complete_vehicle_delete_table','vehicle_aliases',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4543a17f4e5705a267cf5ad103450cb7035df7d2ae546139301eb4179b5f330e',true);
delete from public."vehicle_aliases";
select set_config('pdc.complete_vehicle_delete_table','vehicle_eta_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_eta_history";
select set_config('pdc.complete_vehicle_delete_table','vehicle_intelligence_revisions',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_intelligence_revisions";
select set_config('pdc.complete_vehicle_delete_table','vehicle_intelligence_summaries',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_intelligence_summaries";
select set_config('pdc.complete_vehicle_delete_table','vehicle_master_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','62bdc5562869589ec097e524694bcd90b33a9b0e6447056c41c377acfb26fba9',true);
delete from public."vehicle_master_history";
select set_config('pdc.complete_vehicle_delete_table','vehicle_master_identity_conflicts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_master_identity_conflicts";
select set_config('pdc.complete_vehicle_delete_table','vehicle_master_operation_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','adcdcacb2b2affb8ae82b73fe9a9f8a91877ee2997b75142f3fc3c09a5067b36',true);
delete from public."vehicle_master_operation_receipts";
select set_config('pdc.complete_vehicle_delete_table','vehicle_master_source_records',true);
select set_config('pdc.complete_vehicle_delete_row_hash','59bd3a588945217af4afe3fd3ee162ebc97e4490971fa175d4328d3f55bad73f',true);
delete from public."vehicle_master_source_records";
select set_config('pdc.complete_vehicle_delete_table','vehicle_match_candidates',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_match_candidates";
select set_config('pdc.complete_vehicle_delete_table','ai_email_analysis_results',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."ai_email_analysis_results";
select set_config('pdc.complete_vehicle_delete_table','ai_email_intake',true);
select set_config('pdc.complete_vehicle_delete_row_hash','92d4973814c24e609d330725105b24a050b17d6bcaf92e76cbc86e040b1382c1',true);
delete from public."ai_email_intake";
select set_config('pdc.complete_vehicle_delete_table','vehicle_movements',true);
select set_config('pdc.complete_vehicle_delete_row_hash','c5669770fa018ac16d249cb0605d59d7d9dd93acbd6b31bf843f2db8f0437600',true);
delete from public."vehicle_movements";
select set_config('pdc.complete_vehicle_delete_table','vehicle_notifications',true);
select set_config('pdc.complete_vehicle_delete_row_hash','2c48626c88724fb69806aa61a6b34f201cc2d483d183e7cc48f128d62bf8f5ff',true);
delete from public."vehicle_notifications";
select set_config('pdc.complete_vehicle_delete_table','vehicle_parts_updates',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_parts_updates";
select set_config('pdc.complete_vehicle_delete_table','vehicle_sublet_providers',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_sublet_providers";
select set_config('pdc.complete_vehicle_delete_table','vehicle_timeline_events',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."vehicle_timeline_events";
select set_config('pdc.complete_vehicle_delete_table','vehicle_work_items',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4e4cd375f54b225773a71748e8faa62a85f5db6166dcafb492f05b3aafe75583',true);
delete from public."vehicle_work_items";
select set_config('pdc.complete_vehicle_delete_table','vehicle_workshop_line_adjustments',true);
select set_config('pdc.complete_vehicle_delete_row_hash','e57d13e715e680ec73b6953e94ffb94dd47acc8799624e78021b4730833fdbf7',true);
delete from public."vehicle_workshop_line_adjustments";
select set_config('pdc.complete_vehicle_delete_table','pdc_authenticated_email_operation_lines',true);
select set_config('pdc.complete_vehicle_delete_row_hash','5c3fd053e3be3a5aa4b3f8a499ce79f43757afd7e8b2ba40357afc76fd62cfb1',true);
delete from public."pdc_authenticated_email_operation_lines";
select set_config('pdc.complete_vehicle_delete_table','pdc_authenticated_email_import_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','e17b6f12f8e0a223e14cfb4264264775f6c324979a55b914290597c851512190',true);
delete from public."pdc_authenticated_email_import_receipts";
select set_config('pdc.complete_vehicle_delete_table','navision_backend_records',true);
select set_config('pdc.complete_vehicle_delete_row_hash','6b6d1d49d147596a9c4cbdde1eac062337fc2e62d8457c31a3f27f1b79992361',true);
delete from public."navision_backend_records";
select set_config('pdc.complete_vehicle_delete_table','navision_import_batches',true);
select set_config('pdc.complete_vehicle_delete_row_hash','237732c1b6216735c5f7bfa36d20f8f9a888a60c410f8d903a306a74b28347c6',true);
delete from public."navision_import_batches";
select set_config('pdc.complete_vehicle_delete_table','workshop_admin_block_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','cd72e1be8bf8b2ef60b5dcdefac155bf50f80e56d26d9de91917335534c99410',true);
delete from public."workshop_admin_block_history";
select set_config('pdc.complete_vehicle_delete_table','workshop_admin_block_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','9fbcc9e5dd8341b6ebb2306dfea8dbdee6bd3759959baa8fc83d0aa847e4f5cc',true);
delete from public."workshop_admin_block_receipts";
select set_config('pdc.complete_vehicle_delete_table','workshop_admin_blocks',true);
select set_config('pdc.complete_vehicle_delete_row_hash','7419f9d2fdfa92d329eb15effdbab01b1a876602cc909b819bd2bc2f8552e5bd',true);
delete from public."workshop_admin_blocks";
select set_config('pdc.complete_vehicle_delete_table','workshop_bay_default_technician_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','eb5355e49246672e6703edfc26669943777c2590ab42cd00cbf195367dd2a865',true);
delete from public."workshop_bay_default_technician_history";
select set_config('pdc.complete_vehicle_delete_table','workshop_booking_assignments',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."workshop_booking_assignments";
select set_config('pdc.complete_vehicle_delete_table','workshop_booking_history',true);
select set_config('pdc.complete_vehicle_delete_row_hash','66567ea94347fad407cb93d82b0aeb38c4b5a13b68280b8e9035b7e6e36eb9a8',true);
delete from public."workshop_booking_history";
select set_config('pdc.complete_vehicle_delete_table','workshop_booking_move_receipts',true);
select set_config('pdc.complete_vehicle_delete_row_hash','a8b182b6df0c01bd4163b4a2eb3b49283bd301668267a4b4a566c4dcf1615c7f',true);
delete from public."workshop_booking_move_receipts";
select set_config('pdc.complete_vehicle_delete_table','workshop_parts_overrides',true);
select set_config('pdc.complete_vehicle_delete_row_hash','026333ac6bc9e6e4df1d4228553c5358bc0eedaea95d1f7d383629bb3081517d',true);
delete from public."workshop_parts_overrides";
select set_config('pdc.complete_vehicle_delete_table','workshop_transition_authorizations',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."workshop_transition_authorizations";
select set_config('pdc.complete_vehicle_delete_table','workshop_bookings',true);
select set_config('pdc.complete_vehicle_delete_row_hash','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',true);
delete from public."workshop_bookings";
select set_config('pdc.complete_vehicle_delete_table','vehicles',true);
select set_config('pdc.complete_vehicle_delete_row_hash','bb3412117b8dda7a6f96626edf00ecdb59d1e510632dc9f054b10f1f62f01b5c',true);
delete from public."vehicles";

-- Retain only the new backup proof; prior backup/reset/test rows are history.
delete from public.pdc_staging_verified_backup_manifests;
insert into public.pdc_staging_verified_backup_manifests(backup_manifest_sha256,backup_gzip_sha256,raw_bytes,table_counts,verified_by)
select '0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0','3b341c7cddbcf5431a941743b60e51ddcde9aa206e89fd82a7f232a60cbb732f',463908274,jsonb_build_object('table_count',231,'total_rows',91645,'catalog_sha256','829c923530a93a02ffa30c4b9296f4b6132ea74be84e0dc722d7f11c93738c9c','encrypted_backup_sha256','7e1ba89c675c7afb3fafdd072f20aa0145096ad03672b2de7b283b9f551c9d16'),authorized_by
from public.pdc_email_monitor_pilot where singleton;

-- Restore the exact catalog-bound original enabled triggers and remove the helper.
do $restore_triggers$ declare d record;begin for d in select definition from pdc_354_trigger_defs order by table_name,trigger_name loop execute replace(d.definition,'CREATE TRIGGER','CREATE OR REPLACE TRIGGER');end loop;end $restore_triggers$;
drop function public.pdc_full_reset_trigger_passthrough_354();

select set_config('pdc.complete_vehicle_delete_contract','inactive',true);
select set_config('pdc.complete_vehicle_delete_table','',true);
select set_config('pdc.complete_vehicle_delete_row_hash','',true);
select set_config('pdc.full_history_reset_354','inactive',true);

create table public.pdc_staging_replay_fences_354(
 fence_key text primary key,channel text not null check(channel in('email','telegram')),
 folder text,uidvalidity bigint,denied_through bigint not null,first_eligible bigint not null,
 deferred_exact bigint,created_at timestamptz not null default clock_timestamp(),
 check(first_eligible=denied_through+1 or deferred_exact=first_eligible)
);
alter table public.pdc_staging_replay_fences_354 enable row level security;
revoke all on public.pdc_staging_replay_fences_354 from public,anon,authenticated,service_role;
insert into public.pdc_staging_replay_fences_354(fence_key,channel,folder,uidvalidity,denied_through,first_eligible,deferred_exact)
select 'email:Inbox','email','Inbox',1,least(inbox_denied_through,593),594,594 from pdc_354_replay_pre
union all select 'email:Spam','email','Spam',null,5,6,null
union all select 'telegram','telegram',null,null,telegram_denied_through,telegram_denied_through+1,null from pdc_354_replay_pre;

create table public.pdc_staging_full_reset_receipts_354(
 receipt_id uuid primary key,action_key text not null unique check(action_key='craig-full-vehicle-history-reset-20260824'),
 project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),catalog_sha256 text not null,
 backup_manifest_sha256 text not null,encrypted_backup_sha256 text not null,backup_raw_sha256 text not null,
 pre_history_counts jsonb not null,post_history_counts jsonb not null,preserved_pre_sha256 jsonb not null,
 replay_fences jsonb not null,applied_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_staging_full_reset_receipts_354 enable row level security;
revoke all on public.pdc_staging_full_reset_receipts_354 from public,anon,authenticated,service_role;
create function public.pdc_staging_full_reset_receipt_immutable_354() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$begin raise exception 'PDC_354_RESET_RECEIPT_IMMUTABLE' using errcode='55000';end$$;
revoke all on function public.pdc_staging_full_reset_receipt_immutable_354() from public,anon,authenticated,service_role;
create trigger pdc_staging_full_reset_receipt_immutable_354 before update or delete on public.pdc_staging_full_reset_receipts_354 for each row execute function public.pdc_staging_full_reset_receipt_immutable_354();

-- Every live history relation is empty; every unrelated preserved relation is byte-equivalent.
do $post$
declare n text;c bigint;h text;pre pdc_354_preserved_pre%rowtype;
begin
 foreach n in array array['ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_proposed_actions','ai_review_items','ai_undo_actions','ai_workshop_commands','audit_events','backup_runs','deleted_completed_vehicles','email_response_drafts','import_runs','label_print_events','legacy_stage_reconciliation_receipts','navision_backend_audit','navision_backend_records','navision_board_activations','navision_import_batches','navision_import_items','navision_operation_receipts','navision_rollback_items','pdc_ai_intake_auto_activation_receipts','pdc_ai_intake_auto_backlog_receipts','pdc_ai_intake_decision_receipts','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_auditor_booking_work_relations','pdc_auditor_correction_execution_items','pdc_auditor_correction_executions','pdc_auditor_decisions','pdc_auditor_finding_evidence','pdc_auditor_finding_history','pdc_auditor_finding_occurrences','pdc_auditor_findings','pdc_auditor_operation_changes','pdc_auditor_operation_runs','pdc_auditor_plan_items_225','pdc_auditor_plans_225','pdc_auditor_report_runs','pdc_auditor_review_queue_225','pdc_auditor_revision','pdc_auditor_risk_scores','pdc_auditor_runs','pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_changes_226','pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_auditor_telegram_rollback_audit_226','pdc_auditor_telegram_rollback_receipts_226','pdc_auditor_telegram_runs_226','pdc_auditor_workshop_revisions','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_attachment_manifests','pdc_authenticated_email_batch_receipts','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_row_receipts','pdc_email_attachment_batch_receipts_323','pdc_email_attachment_batch_superseded_325','pdc_email_communication_action_receipts','pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_email_intake_work_receipts','pdc_email_source_claims','pdc_full_inbox_body_sources_20260821033000','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_full_inbox_source_unit_terminals_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_historical_attachment_source_authorizations_20260821043000','pdc_historical_attachment_source_bindings_20260821043000','pdc_historical_inbox_authorizations_20260821040000','pdc_historical_nonnav_extraction_authorizations_20260821047000','pdc_historical_nonnav_extraction_corrections_20260821049000','pdc_historical_nonnav_extraction_corrections_20260821051000','pdc_historical_pilot_floor_bindings_20260821041000','pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_rule_receipts_279','pdc_jobcard_attachment_source_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_decision_receipts','pdc_key_list_proposal_rows','pdc_key_list_proposals','pdc_monitor_new_build_intake_approvals','pdc_monitor_runtime_binding_rotations_270','pdc_monitor_stage_activation_approvals','pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts','pdc_online_operational_state','pdc_online_state_receipts','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_previews','pdc_provider_email_observations','pdc_retained_reset_import_receipts_212','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_cleanse_receipts_348','pdc_staging_containment_receipts_347','pdc_staging_monitor_activation_receipts_352','pdc_staging_reset_attestations','pdc_staging_reset_batches','pdc_staging_reset_evidence_corrections','pdc_staging_reset_rows','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_supervised_apply_receipts','pdc_supervised_correction_batches','pdc_supervised_correction_evidence','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_failures','pdc_supervised_monitor_applications','pdc_supervised_review_queue','pdc_supervised_rule_events','pdc_supervised_telegram_commands','pdc_supervised_telegram_responses','pdc_uid478_attachment_attempt_receipts','pdc_uid478_attachment_terminal_receipts','pdc_uid478_message_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid514_recovery_authorizations_257','pdc_uid514_recovery_claim_attempts_257','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','restore_test_runs','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_bay_default_technician_history','workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','workshop_transition_authorizations']::text[] loop execute format('select count(*) from public.%I',n) into c;if c<>0 then raise exception 'PDC_354_HISTORY_NOT_EMPTY table=% count=%',n,c using errcode='55000';end if;end loop;
 foreach n in array array['ai_intake_config','ai_mapping_rules','ai_trusted_senders','monitored_mailboxes','navision_backend_revision','navision_initial_scope_approvals','pdc_ai_intake_revision','pdc_attachment_atomic_contract','pdc_auditor_autonomous_hour_rules','pdc_auditor_executor_identities','pdc_auditor_gvm_mappings_225','pdc_auditor_restricted_authority_revocations','pdc_auditor_rule_commands_227','pdc_auditor_rule_config','pdc_auditor_rule_examples_227','pdc_auditor_rule_families_227','pdc_auditor_rule_versions_227','pdc_auditor_service_identities_225','pdc_auditor_user_dealer_scopes','pdc_auditor_worker_identities','pdc_email_monitor_pilot','pdc_email_monitor_status','pdc_email_vehicle_revision','pdc_key_list_proposal_revision','pdc_monitor_exact_sender_enrollments','pdc_monitor_runtime_bindings_255','pdc_monitor_stage_activation_writers','pdc_monitor_vehicle_identity_readers','pdc_online_state_revision','pdc_pmb_canonical_manager_authorities','pdc_staging_environment_sentinel','pdc_staging_verified_backup_manifests','pdc_supervised_revision','pdc_supervised_rule_aliases','pdc_supervised_rule_examples','pdc_supervised_rule_families','pdc_supervised_rule_versions','pdc_supervised_telegram_identities','pdc_user_roles','salespeople','sublet_provider_aliases','sublet_providers','vehicle_lifecycle_resolver_revision','vehicle_master_revision','workshop_bays','workshop_revision','workshop_settings','workshop_stage_aliases','workshop_stages','workshop_station_revision','workshop_technicians']::text[] loop
  if n=any(array['monitored_mailboxes','pdc_email_monitor_pilot','pdc_staging_verified_backup_manifests']::text[]) then continue;end if;
  select * into pre from pdc_354_preserved_pre where table_name=n;
  execute format('select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,'''' order by to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') from public.%I t',n) into c,h;
  if c is distinct from pre.row_count or h is distinct from pre.content_sha256 then raise exception 'PDC_354_PRESERVED_DRIFT table=%',n using errcode='55000';end if;
 end loop;
 if exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled or automatic_rule_application or automatic_authenticated_jobcards)
    or exists(select 1 from public.monitored_mailboxes where active)
    or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
    or exists(select 1 from public.pdc_email_monitor_status where running_status<>'stopped' or gateway_instance_id is not null)
    or (select count(*) from public.pdc_staging_replay_fences_354)<>3 then raise exception 'PDC_354_STOP_OR_REPLAY_POSTCONDITION_FAILED' using errcode='55000';end if;
end $post$;

update public.pdc_email_monitor_pilot set minimum_uid=594,updated_at=clock_timestamp() where singleton;
update public.monitored_mailboxes set config=(config-'activation_high_water_uid'-'future_only_minimum_uid')||jsonb_build_object('historical_denied_through_uid',593,'future_only_minimum_uid',594,'deferred_exact_uid',594,'containment','craig-full-history-reset-20260824'),updated_at=clock_timestamp() where mailbox_key='pdc_pmb_email';
do $fence_post$ begin
 if (select minimum_uid from public.pdc_email_monitor_pilot where singleton)<>594
    or not exists(select 1 from public.pdc_staging_replay_fences_354 where fence_key='email:Inbox' and denied_through=593 and first_eligible=594 and deferred_exact=594)
    or exists(select 1 from public.ai_email_intake where provider_uid~'594$') then
  raise exception 'PDC_354_UID594_DEFERRED_FENCE_FAILED' using errcode='55000';
 end if;
end $fence_post$;

insert into public.pdc_staging_full_reset_receipts_354(receipt_id,action_key,project_ref,catalog_sha256,backup_manifest_sha256,encrypted_backup_sha256,backup_raw_sha256,pre_history_counts,post_history_counts,preserved_pre_sha256,replay_fences)
select gen_random_uuid(),'craig-full-vehicle-history-reset-20260824','cdsmnqxtyyoeoznmbidd','829c923530a93a02ffa30c4b9296f4b6132ea74be84e0dc722d7f11c93738c9c','0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0','7e1ba89c675c7afb3fafdd072f20aa0145096ad03672b2de7b283b9f551c9d16','f7e8b437a9b86ee8eefafd3609be2029f29b7884f2d52fd83cf4656951a9d6a3','{"ai_email_analysis_results":0,"ai_email_attachments":104,"ai_email_intake":56,"ai_extracted_fields":0,"ai_proposed_actions":0,"ai_review_items":0,"ai_undo_actions":0,"ai_workshop_commands":0,"audit_events":23584,"backup_runs":357,"deleted_completed_vehicles":1603,"email_response_drafts":0,"import_runs":0,"label_print_events":0,"legacy_stage_reconciliation_receipts":0,"navision_backend_audit":155,"navision_backend_records":1358,"navision_board_activations":448,"navision_import_batches":24,"navision_import_items":9701,"navision_operation_receipts":84,"navision_rollback_items":0,"pdc_ai_intake_auto_activation_receipts":26,"pdc_ai_intake_auto_backlog_receipts":1,"pdc_ai_intake_decision_receipts":5,"pdc_ai_intake_history":444,"pdc_ai_intake_proposals":273,"pdc_auditor_booking_work_relations":0,"pdc_auditor_correction_execution_items":0,"pdc_auditor_correction_executions":0,"pdc_auditor_decisions":2,"pdc_auditor_finding_evidence":119,"pdc_auditor_finding_history":119,"pdc_auditor_finding_occurrences":119,"pdc_auditor_findings":62,"pdc_auditor_operation_changes":46,"pdc_auditor_operation_runs":23,"pdc_auditor_plan_items_225":332,"pdc_auditor_plans_225":2,"pdc_auditor_report_runs":0,"pdc_auditor_review_queue_225":140,"pdc_auditor_revision":52,"pdc_auditor_risk_scores":119,"pdc_auditor_runs":2,"pdc_auditor_telegram_apply_receipts_226":1,"pdc_auditor_telegram_changes_226":82,"pdc_auditor_telegram_deliveries_230":3,"pdc_auditor_telegram_instructions_225":2,"pdc_auditor_telegram_rollback_audit_226":82,"pdc_auditor_telegram_rollback_receipts_226":1,"pdc_auditor_telegram_runs_226":1,"pdc_auditor_workshop_revisions":2,"pdc_authenticated_email_attachment_claims":4,"pdc_authenticated_email_attachment_manifests":0,"pdc_authenticated_email_batch_receipts":0,"pdc_authenticated_email_import_receipts":1306,"pdc_authenticated_email_operation_lines":6389,"pdc_bulk_workbook_apply_receipts":1,"pdc_bulk_workbook_authorizations":2,"pdc_bulk_workbook_previews":2,"pdc_bulk_workbook_quarantine":412,"pdc_bulk_workbook_row_receipts":410,"pdc_email_attachment_batch_receipts_323":3,"pdc_email_attachment_batch_superseded_325":10,"pdc_email_communication_action_receipts":0,"pdc_email_communication_receipts":0,"pdc_email_evidence_consumptions":5,"pdc_email_intake_work_receipts":5,"pdc_email_source_claims":276,"pdc_full_inbox_body_sources_20260821033000":0,"pdc_full_inbox_location_receipts_20260821033000":0,"pdc_full_inbox_parts_receipts_20260821033000":0,"pdc_full_inbox_source_unit_terminals_20260821033000":0,"pdc_generic_current_navision_enrichment_receipts_312":10,"pdc_historical_attachment_source_authorizations_20260821043000":5,"pdc_historical_attachment_source_bindings_20260821043000":0,"pdc_historical_inbox_authorizations_20260821040000":11,"pdc_historical_nonnav_extraction_authorizations_20260821047000":5,"pdc_historical_nonnav_extraction_corrections_20260821049000":1,"pdc_historical_nonnav_extraction_corrections_20260821051000":0,"pdc_historical_pilot_floor_bindings_20260821041000":0,"pdc_jobcard_attachment_import_receipts":19,"pdc_jobcard_attachment_rule_receipts_279":62,"pdc_jobcard_attachment_source_row_receipts":67,"pdc_key_list_apply_receipt_rows":0,"pdc_key_list_decision_receipts":0,"pdc_key_list_proposal_rows":0,"pdc_key_list_proposals":0,"pdc_monitor_new_build_intake_approvals":0,"pdc_monitor_runtime_binding_rotations_270":23,"pdc_monitor_stage_activation_approvals":0,"pdc_non_navision_jobcard_receipts":5,"pdc_non_navision_jobcard_source_row_receipts":35,"pdc_online_operational_state":0,"pdc_online_state_receipts":0,"pdc_pmb_canonical_admin_countersignatures":340,"pdc_pmb_canonical_apply_authorizations":1,"pdc_pmb_canonical_apply_receipts":1,"pdc_pmb_canonical_manager_approvals":340,"pdc_pmb_canonical_pair_receipts":340,"pdc_pmb_workbook_apply_authorizations":1,"pdc_pmb_workbook_apply_receipts":1,"pdc_pmb_workbook_operation_reviews":10572,"pdc_pmb_workbook_pair_approvals":80,"pdc_pmb_workbook_pair_receipts":420,"pdc_pmb_workbook_pair_reviews":1344,"pdc_pmb_workbook_previews":3,"pdc_provider_email_observations":54,"pdc_retained_reset_import_receipts_212":1,"pdc_staging_backup_restoration_receipts":1,"pdc_staging_board_purge_receipts":2,"pdc_staging_cleanse_receipts_348":1,"pdc_staging_containment_receipts_347":1,"pdc_staging_monitor_activation_receipts_352":1,"pdc_staging_reset_attestations":1,"pdc_staging_reset_batches":1,"pdc_staging_reset_evidence_corrections":1,"pdc_staging_reset_rows":411,"pdc_sublet_booking_history":50,"pdc_sublet_booking_instance_history":10,"pdc_sublet_booking_instances":3,"pdc_sublet_bookings":0,"pdc_sublet_email_update_receipts":0,"pdc_supervised_apply_receipts":10,"pdc_supervised_correction_batches":1,"pdc_supervised_correction_evidence":10,"pdc_supervised_correction_items":10,"pdc_supervised_correction_overlays":8,"pdc_supervised_failures":0,"pdc_supervised_monitor_applications":0,"pdc_supervised_review_queue":0,"pdc_supervised_rule_events":23,"pdc_supervised_telegram_commands":0,"pdc_supervised_telegram_responses":0,"pdc_uid478_attachment_attempt_receipts":0,"pdc_uid478_attachment_terminal_receipts":0,"pdc_uid478_message_receipts":0,"pdc_uid514_identity_reinstatements_306":1,"pdc_uid514_recovery_authorizations_257":1,"pdc_uid514_recovery_claim_attempts_257":25,"pdc_uid558_exact_existing_vehicle_mutation_receipts_310":0,"pdc_uid558_identity_reinstatements_309":1,"pdc_uid590_591_exact_reinstatements_318":2,"pdc_uid590_activation_reopen_320":1,"pdc_uid590_vin_completion_319":1,"pdc_uid592_exact_reinstatements_327":4,"pdc_uid592_vehicle_vin_completion_330":4,"pdc_vehicle_lifecycle_events":50,"pdc_vehicle_recreation_permissions":6,"pdc_vehicle_tombstones":30,"pdc_workshop_operation_removal_receipts_235":63,"pdc_workshop_operation_removal_undo_receipts_235":0,"restore_test_runs":193,"vehicle_aliases":1113,"vehicle_eta_history":0,"vehicle_intelligence_revisions":0,"vehicle_intelligence_summaries":0,"vehicle_master_history":14885,"vehicle_master_identity_conflicts":0,"vehicle_master_operation_receipts":1113,"vehicle_master_source_records":1113,"vehicle_match_candidates":0,"vehicle_movements":1120,"vehicle_notifications":555,"vehicle_parts_updates":0,"vehicle_sublet_providers":0,"vehicle_timeline_events":0,"vehicle_work_items":3,"vehicle_workshop_line_adjustments":1483,"vehicles":1730,"workshop_admin_block_history":19,"workshop_admin_block_receipts":19,"workshop_admin_blocks":4,"workshop_bay_default_technician_history":2,"workshop_booking_assignments":0,"workshop_booking_history":4979,"workshop_booking_move_receipts":8,"workshop_bookings":0,"workshop_parts_overrides":22,"workshop_transition_authorizations":0}'::jsonb, (select jsonb_object_agg(x,0 order by x) from unnest(array['ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_proposed_actions','ai_review_items','ai_undo_actions','ai_workshop_commands','audit_events','backup_runs','deleted_completed_vehicles','email_response_drafts','import_runs','label_print_events','legacy_stage_reconciliation_receipts','navision_backend_audit','navision_backend_records','navision_board_activations','navision_import_batches','navision_import_items','navision_operation_receipts','navision_rollback_items','pdc_ai_intake_auto_activation_receipts','pdc_ai_intake_auto_backlog_receipts','pdc_ai_intake_decision_receipts','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_auditor_booking_work_relations','pdc_auditor_correction_execution_items','pdc_auditor_correction_executions','pdc_auditor_decisions','pdc_auditor_finding_evidence','pdc_auditor_finding_history','pdc_auditor_finding_occurrences','pdc_auditor_findings','pdc_auditor_operation_changes','pdc_auditor_operation_runs','pdc_auditor_plan_items_225','pdc_auditor_plans_225','pdc_auditor_report_runs','pdc_auditor_review_queue_225','pdc_auditor_revision','pdc_auditor_risk_scores','pdc_auditor_runs','pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_changes_226','pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_auditor_telegram_rollback_audit_226','pdc_auditor_telegram_rollback_receipts_226','pdc_auditor_telegram_runs_226','pdc_auditor_workshop_revisions','pdc_authenticated_email_attachment_claims','pdc_authenticated_email_attachment_manifests','pdc_authenticated_email_batch_receipts','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_bulk_workbook_apply_receipts','pdc_bulk_workbook_authorizations','pdc_bulk_workbook_previews','pdc_bulk_workbook_quarantine','pdc_bulk_workbook_row_receipts','pdc_email_attachment_batch_receipts_323','pdc_email_attachment_batch_superseded_325','pdc_email_communication_action_receipts','pdc_email_communication_receipts','pdc_email_evidence_consumptions','pdc_email_intake_work_receipts','pdc_email_source_claims','pdc_full_inbox_body_sources_20260821033000','pdc_full_inbox_location_receipts_20260821033000','pdc_full_inbox_parts_receipts_20260821033000','pdc_full_inbox_source_unit_terminals_20260821033000','pdc_generic_current_navision_enrichment_receipts_312','pdc_historical_attachment_source_authorizations_20260821043000','pdc_historical_attachment_source_bindings_20260821043000','pdc_historical_inbox_authorizations_20260821040000','pdc_historical_nonnav_extraction_authorizations_20260821047000','pdc_historical_nonnav_extraction_corrections_20260821049000','pdc_historical_nonnav_extraction_corrections_20260821051000','pdc_historical_pilot_floor_bindings_20260821041000','pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_rule_receipts_279','pdc_jobcard_attachment_source_row_receipts','pdc_key_list_apply_receipt_rows','pdc_key_list_decision_receipts','pdc_key_list_proposal_rows','pdc_key_list_proposals','pdc_monitor_new_build_intake_approvals','pdc_monitor_runtime_binding_rotations_270','pdc_monitor_stage_activation_approvals','pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts','pdc_online_operational_state','pdc_online_state_receipts','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_pair_receipts','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_pair_receipts','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_previews','pdc_provider_email_observations','pdc_retained_reset_import_receipts_212','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_cleanse_receipts_348','pdc_staging_containment_receipts_347','pdc_staging_monitor_activation_receipts_352','pdc_staging_reset_attestations','pdc_staging_reset_batches','pdc_staging_reset_evidence_corrections','pdc_staging_reset_rows','pdc_sublet_booking_history','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','pdc_sublet_bookings','pdc_sublet_email_update_receipts','pdc_supervised_apply_receipts','pdc_supervised_correction_batches','pdc_supervised_correction_evidence','pdc_supervised_correction_items','pdc_supervised_correction_overlays','pdc_supervised_failures','pdc_supervised_monitor_applications','pdc_supervised_review_queue','pdc_supervised_rule_events','pdc_supervised_telegram_commands','pdc_supervised_telegram_responses','pdc_uid478_attachment_attempt_receipts','pdc_uid478_attachment_terminal_receipts','pdc_uid478_message_receipts','pdc_uid514_identity_reinstatements_306','pdc_uid514_recovery_authorizations_257','pdc_uid514_recovery_claim_attempts_257','pdc_uid558_exact_existing_vehicle_mutation_receipts_310','pdc_uid558_identity_reinstatements_309','pdc_uid590_591_exact_reinstatements_318','pdc_uid590_activation_reopen_320','pdc_uid590_vin_completion_319','pdc_uid592_exact_reinstatements_327','pdc_uid592_vehicle_vin_completion_330','pdc_vehicle_lifecycle_events','pdc_vehicle_recreation_permissions','pdc_vehicle_tombstones','pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235','restore_test_runs','vehicle_aliases','vehicle_eta_history','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_master_operation_receipts','vehicle_master_source_records','vehicle_match_candidates','vehicle_movements','vehicle_notifications','vehicle_parts_updates','vehicle_sublet_providers','vehicle_timeline_events','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_admin_block_history','workshop_admin_block_receipts','workshop_admin_blocks','workshop_bay_default_technician_history','workshop_booking_assignments','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings','workshop_parts_overrides','workshop_transition_authorizations']::text[]) x),
 (select jsonb_object_agg(table_name,content_sha256 order by table_name) from pdc_354_preserved_pre),
 (select jsonb_agg(to_jsonb(f)-'created_at' order by fence_key) from public.pdc_staging_replay_fences_354 f);

-- Revoke every reset/purge path after the owner migration.
revoke all on function public.pdc_admin_run_staging_cleanse_348() from public,anon,authenticated,service_role;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
do $optional$ begin if to_regprocedure('public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text)') is not null then execute 'revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role';end if;end $optional$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824150000','354_full_vehicle_history_reset',array[
 'Exact staging/head/owner/231-table live catalog and fresh encrypted full-public backup binding',
 'FK-safe DELETE of all 180 vehicle/operational/history/test relations without TRUNCATE, CASCADE or trigger disabling',
 'Preserve auth/config/reference/rule tables exactly; compact Inbox/Spam/Telegram replay fences with UID594 deferred',
 'Record immutable reset/backup receipt, prove all history zero and revoke every reset/purge surface'
]);
notify pgrst,'reload schema';
commit;
