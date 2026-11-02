/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const test = require('node:test');
const root = __dirname;
const ui = path.join(root, 'karratha');
const original = root;
const manifest = {"files":[{"file":"ai-auditor.css","unchanged":true,"baseline_sha256":"c69b084fb957e03fc663d276dc4322657d0f9fd3cc3da96130c894d1b848a846"},{"file":"ai-board-advisor.js","unchanged":true,"baseline_sha256":"a01dc581a417684c5a3377057bc70a57624bdaa3ad67c24b408eedfa86e0fc4e"},{"file":"app.js","unchanged":false,"baseline_sha256":"f284d8560033a3617a238e75e44321321833d036f6d9eb1700dee8f068dbe6d3"},{"file":"arb-labor-catalog.js","unchanged":true,"baseline_sha256":"db99ee8c4ddf341ce3f948dc04fb70cbe6c66d122be1a262f7074552a2fa49c0"},{"file":"assets/brand-logo.svg","unchanged":true,"baseline_sha256":"4bffc708627c0ee8de1a997aec6bf3aae7461fb779f2700f41fd47e6645dd28d"},{"file":"assets/pmb-logo.png","unchanged":true,"baseline_sha256":"b795f771135b94768d211ca912472fd7d74e324cf27d5d03a354380344b7a923"},{"file":"broome-navision-import.js","unchanged":true,"baseline_sha256":"1c44ccfed43c4ad484187741e1100fec1f396efbefd646e9bf0eb29a2f3a7db5"},{"file":"canonical-entry.js","unchanged":true,"baseline_sha256":"c2b28f96a0634f46c48b85f0cc40cf8df2c57fdcc7ce86501e0c8cacf70ab56f"},{"file":"control-board-overview.js","unchanged":true,"baseline_sha256":"2b4e0c4f27caa344cd6be2a0bdea78cad0c84e94706d5f43fa86a03faed03d44"},{"file":"data-staging-empty.js","unchanged":true,"baseline_sha256":"d2a9ed658daa1cc5eabb45a78eeb5c7f93ef0146a12e7f8c23d0b028f915c7a9"},{"file":"deployment-manifest.json","unchanged":false,"baseline_sha256":"dae0c7e8066afd366860dc2a68d07343c43607d2fd41e4a3f4f495154415e9a2"},{"file":"desktop-operations.css","unchanged":true,"baseline_sha256":"e53d2b11ebd6092c47d54427cad0bc6d535d802396faabe1712cd8baefd43dfb"},{"file":"email-board-data.js","unchanged":true,"baseline_sha256":"3b55079afe708ae6842a6ddb61e19e912a8182cdc835a5d4102e4a5815dbace0"},{"file":"favicon.svg","unchanged":true,"baseline_sha256":"f79b374447017a73a77012096c6d031ddb2ad6bf1b647d2efbfd465e6a5f32e6"},{"file":"index.html","unchanged":false,"baseline_sha256":"43c6e261e872cff08828fc3ad439a4f836bad7b4fd889945b073cf87e53c7486"},{"file":"navision-backend-service.js","unchanged":true,"baseline_sha256":"a07082fa56a74e4ccb5806f474eb1fabdbc582f7d71ab07d2a7b3a3da4a1c4ea"},{"file":"navision-vin.js","unchanged":true,"baseline_sha256":"f164d55b23c87037ad497fdad2a083b663e064c7e6369de01d68322af74d8e77"},{"file":"pdc-ai-auditor-stage-a.js","unchanged":true,"baseline_sha256":"3660fddd23117d249fb50d78f560cf0d0927a09abbbb34273782574777273636"},{"file":"pdc-ai-intake-review.css","unchanged":true,"baseline_sha256":"cc5f0c4039e8e10bcace3cab4ffe73b39cc725e8c3582bf28dbbb54bd9fd5064"},{"file":"pdc-ai-intake-review.js","unchanged":true,"baseline_sha256":"575ea073661ea77830c249e6b64e86f9b4fae50708a3609dd1f18653a55e7c04"},{"file":"pdc-ai-intake-service.js","unchanged":true,"baseline_sha256":"0212c9c485fc78115e0f4a5a7138944bc56f0de7d2ef097b49bc2841d09186f2"},{"file":"pdc-auth-registration.js","unchanged":true,"baseline_sha256":"71cb6c0f474751f08b1033b4ee57bbc34a2a58f03e55bbb709c42dda22a6a19a"},{"file":"pdc-auth.js","unchanged":false,"baseline_sha256":"b4e5c08d4f26acf5d3100947df16740e4cfda1b839cabe214ff1d953e72ff0ce"},{"file":"pdc-book-all-stations.js","unchanged":true,"baseline_sha256":"27873ee562e90bd0601e09777ce5cdb988c9e884ac84b5a4749b7a04c392bf2f"},{"file":"pdc-bus-workflow.css","unchanged":true,"baseline_sha256":"5e099ff88b97579fe030ebe9b663fd10d577acaba1c7beedba76d0f1b24b74d0"},{"file":"pdc-bus-workflow.js","unchanged":true,"baseline_sha256":"75de57a69d13dd72cd840418116d3d11438430006b64b2bfe7eccbf18f3ad083"},{"file":"pdc-completed-history.css","unchanged":true,"baseline_sha256":"5222865f7b0e8d74cc05eec84329ee2a8c577ff597c1cc2c800c11789404ab9b"},{"file":"pdc-conversions.js","unchanged":true,"baseline_sha256":"e2fab8534ec59c16f6d4cb71373901224c0bd7631f11b1ae3f946f8bae7a7b5e"},{"file":"pdc-department-filter.js","unchanged":false,"baseline_sha256":"f247cc5a3753637c87a941964a1e70f3a56ee69d4c9b4b36e0435949d8eaeb6a"},{"file":"pdc-email-ai-successor-inbox.css","unchanged":true,"baseline_sha256":"4e504662e5bc203d071d697ee3ccabb8cd5ae215fde27213fb2c7781c0902d07"},{"file":"pdc-email-ai-successor-inbox.js","unchanged":true,"baseline_sha256":"3f3aad15c1399c5aa99f3556543b7923ba4655ea2c95ffc73100569cf384c764"},{"file":"pdc-email-ai-v2-actions.js","unchanged":true,"baseline_sha256":"9a600a225b087f9af3789ba746097c89c37b23c6aecc0360df9608fb666fc5e3"},{"file":"pdc-email-vehicle-location-service.js","unchanged":false,"baseline_sha256":"1520f88a13cb18c988bc2c6d433c9d684c4657606798d20d91e7bc599eda7f40"},{"file":"pdc-emergency-priority.css","unchanged":true,"baseline_sha256":"dba32f8bef9b4c3f63ecd52b243866e3076e5a025be601caa55c630f8796d387"},{"file":"pdc-emergency-priority.js","unchanged":true,"baseline_sha256":"afac55282a208eb49ef2136f1c17b3e8d5747df7bcbd237d1d36aa8239e98205"},{"file":"pdc-estimated-hours.css","unchanged":true,"baseline_sha256":"c4ba795d17c9b46214498fb7f993c0600d4538cec3e985db444567b24e6b49b9"},{"file":"pdc-estimated-hours.js","unchanged":true,"baseline_sha256":"df863d78fcc7eeaadee7eb911b139a19f8c25cafc9b0fc262222c87b760ff122"},{"file":"pdc-fitters.css","unchanged":true,"baseline_sha256":"f8ef8149791bcce540a1a8669346316d2153325db2f285729bc44d2497e4888a"},{"file":"pdc-fitters.js","unchanged":true,"baseline_sha256":"0690924b100eaf5c35df45aed0cd4c1dbd1b13bdb08c465e3dfa8f43dec919a0"},{"file":"pdc-location-override.js","unchanged":true,"baseline_sha256":"cdf3878e17601edfeef8a25e791a9c2ecdd0d58c5e1642064948d6db040dc117"},{"file":"pdc-new-vehicles.css","unchanged":true,"baseline_sha256":"ba3705ea8318c3b5effc9a2e98cdf8db64c8e679a438bb750f1424c75139399d"},{"file":"pdc-new-vehicles.js","unchanged":false,"baseline_sha256":"fd48af4e7386c1971265b856e899df6e497b4472cb9ba2ee6c082d5c9d92142e"},{"file":"pdc-parts-confirmation.js","unchanged":true,"baseline_sha256":"6c319cebc6f121866d04551d918dbc9caf5f5f6bbd4ff6fd1d4fd3abad23cf3e"},{"file":"pdc-planner-capacity.css","unchanged":true,"baseline_sha256":"0f9c8e1163bc5672ad09d83eddf645305c45c568c97b76eae632d2b11db0bd64"},{"file":"pdc-planner-capacity.js","unchanged":true,"baseline_sha256":"e060f96c1666001fb54a2090218784a68ef2b76373070ce305cdb99170864652"},{"file":"pdc-planner-slim.css","unchanged":true,"baseline_sha256":"e5dfae0b4b5d160cc8a83efcae72335db5eb02b822ae27b61189cd1d7a203e27"},{"file":"pdc-planner-slim.js","unchanged":true,"baseline_sha256":"941e4c695533816856dd64f5c43d7f0da9fb4d41ef6f7a8747827607ade85e36"},{"file":"pdc-professional-polish.css","unchanged":true,"baseline_sha256":"48872b974ef10ae00cbabff6761d4f8efa6db611f679ca8299a38a093d6acd96"},{"file":"pdc-qc-mobile.css","unchanged":true,"baseline_sha256":"67de1b138eedfecc10be47449ef3d6cfec5319b00d375017dd758e1a6f2b4552"},{"file":"pdc-qc-mobile.js","unchanged":true,"baseline_sha256":"378fd0e3780403c6a193a38e389331269caef7a11813bb4672f324f4f3538127"},{"file":"pdc-qc-rework.js","unchanged":true,"baseline_sha256":"8ff76ae9c8a4ad94369e6abecc456c807d80e17db9b2adb29eb3ee76d25927d6"},{"file":"pdc-review-stations.css","unchanged":true,"baseline_sha256":"9ab6637f31651d233ff69f20daf9d3fcf2bf29e7d74f524dd0cde798d69e2e59"},{"file":"pdc-review-stations.js","unchanged":true,"baseline_sha256":"f8c63a2b65e15030bf2b3c61cc096e2548e038a419e1fb34b51a9f29ee261dcb"},{"file":"pdc-rft-actions.css","unchanged":true,"baseline_sha256":"ad14ec5b7e231af7c1ff3aa462d76ba1113c2164aeec8e8edaf65f168bf4e104"},{"file":"pdc-rft-actions.js","unchanged":true,"baseline_sha256":"904b5e075214e9e8a467c2ff22868cbf7415a2daa86a86497fd232ff6cfccf5b"},{"file":"pdc-service-locations.js","unchanged":true,"baseline_sha256":"0a2db193406c155f50b78301c91668e350e32f679f56383fc761b99d78c83aff"},{"file":"pdc-stacked-jobcards.css","unchanged":true,"baseline_sha256":"30dee3fc92b587851b86bb9fb227447b54a6f74316c5fbe10cd79774e940cfce"},{"file":"pdc-stacked-jobcards.js","unchanged":true,"baseline_sha256":"a27816234614b3a8fdcd465d9f82f45daf52499aa5116d9bf8d9d71533b01b0d"},{"file":"pdc-staff-usage.css","unchanged":true,"baseline_sha256":"459383cb01fbbd7051e5dce8b365633b13ccd191cd1bae39a331f4c1e9163c2c"},{"file":"pdc-staff-usage.js","unchanged":true,"baseline_sha256":"aef8dff8892d7d83cab5aa49768de11f10625aaad730a192b4bd390f2ed8f57a"},{"file":"pdc-sublet-intake.js","unchanged":true,"baseline_sha256":"425328ef7f0d66b1fb1a18201405002af5efea146c29ea810e77332f08927fa8"},{"file":"pdc-supabase-config.staging.js","unchanged":false,"baseline_sha256":"5a9fed40d5cd492b36b1cbed745372b38f2f2727443a0c1762afc959bd0fff81"},{"file":"pdc-update-history.css","unchanged":true,"baseline_sha256":"f8fa3f4ffd7e60f1104a29d83821458c56180fa9856dbf4ad55e4dffc9054e90"},{"file":"pdc-update-history.js","unchanged":true,"baseline_sha256":"bc94317de5e59947a02ea62b732356490008c0161c73ac2fa90ce79425d778c1"},{"file":"pdc-vehicle-handover.js","unchanged":true,"baseline_sha256":"c2c431bb0e13e980e53dd81768e50e527c7b0a8cfbca849ee33b932b89b0213d"},{"file":"pdc-workshop-hours.js","unchanged":true,"baseline_sha256":"7ae6d40030b78432eac2da4c14a857c4de9ad11e9713b78b2d643983ac2b3941"},{"file":"pdc-workshop-tile-cleanup.js","unchanged":true,"baseline_sha256":"b9dece036310530218255f12ccda1ca3433705dd63e7b146b29c828bf1539a59"},{"file":"pdc-workshop-usability.js","unchanged":true,"baseline_sha256":"07ec24bae57d249659ac591e50539cdef9f2ee79090ec268a8736b959a193953"},{"file":"sales/navision-orders.js","unchanged":true,"baseline_sha256":"f033097922622e193494c9b99a1ed51609c617deaa893c1f7cc8df66b6e68812"},{"file":"scripts/stage2b_c4_browser_export.js","unchanged":false,"baseline_sha256":"5dafeb35a33626fec47aeaa931d17f83f22e436a4f602cbae66914537ab90f18"},{"file":"site-switcher.css","unchanged":true,"baseline_sha256":"4f323e25ae2bccb1719f126b516d56bec8fd0a4a886c94cd87c4b4a9b5d0aa2a"},{"file":"site-switcher.js","unchanged":false,"baseline_sha256":"83bb71e9a56653b29be6163e288556d344c113c1d610af53b8af4ee2f1107f34"},{"file":"staging-browser-assessment.js","unchanged":true,"baseline_sha256":"29acbe12e27d787b12d75614086278ac54e2ffe04bb6dfd755b3cacc7077bded"},{"file":"styles.css","unchanged":true,"baseline_sha256":"6faf7a65d7f2ce2dd914ed9c36697cfb2353a4afa760fd5b68b3d406bc125634"},{"file":"vehicle-lifecycle-actions.js","unchanged":true,"baseline_sha256":"7d2896ad86ff6e85e3843ce9f1db208d4845534e6dbbca4f5797870dd7bacb2e"},{"file":"vehicle-location-lifecycle.js","unchanged":false,"baseline_sha256":"004d4cc4abed034af9fae3f4cb189fd9c0c18142aaf8477fc14eef3953fd416d"},{"file":"vehicle-locations-refresh-ui.js","unchanged":true,"baseline_sha256":"10677f6b5e1c97258448302eebb7c9100d8a9a513b7c2c257cf3239ed7bd7738"},{"file":"vehicle-locations-refresh.js","unchanged":true,"baseline_sha256":"3d26fa044d344cec3aef3dd6e27a81a8443f14b7859247dfd1906a9746aaf365"},{"file":"vehicle-modal-identity.js","unchanged":true,"baseline_sha256":"0340df41901b64b54e4f7bea3d42c894502f66b1b4466d4655410d2d58625a65"},{"file":"vehicle-requirements-guard.js","unchanged":true,"baseline_sha256":"ad21c96e95fb97ad5b47b75ac4765fcda10866ba38689482c5445b40833db665"},{"file":"vendor/pdfjs/LICENSE","unchanged":true,"baseline_sha256":"0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594"},{"file":"vendor/pdfjs/pdf.min.js","unchanged":true,"baseline_sha256":"5b5799e6f8c680663207ac5b42ee14eed2a406fa7af48f50c154f0c0b1566946"},{"file":"vendor/pdfjs/pdf.worker.min.js","unchanged":true,"baseline_sha256":"feabdf309770ed24bba31a5467836cdc8cf639c705af27d52b585b041bb8527b"},{"file":"vendor/qz/qz-tray.js","unchanged":true,"baseline_sha256":"b0a0afde74511e5284195cc875bc862b1ea4233f6c6aecb3ad485430a56bf4a6"},{"file":"vendor/supabase/supabase-2.110.5.js","unchanged":true,"baseline_sha256":"8e00fd587eb7c5148c977fa7c425316e8f9f168b3831100d8e2925a9807b5893"},{"file":"workshop-booking-timing.js","unchanged":true,"baseline_sha256":"c8e780380e1571a4cd5d103c5c26ffa5237f15ca3096eddc3414c48b102a310f"},{"file":"workshop-data-service.js","unchanged":false,"baseline_sha256":"004267f09a9fa4f5ad0852dd8f983e25395d8352f8b0f9fb798777b3d733e9ff"},{"file":"workshop-display-identity.js","unchanged":true,"baseline_sha256":"6734759a5b2b39c0bf057c96394b3487280a45a921502113160b8fb8d17b488b"},{"file":"workshop-eligibility.js","unchanged":false,"baseline_sha256":"df26b6c24a13091721e3aa9ff3faab443da80def91b37847ea3862d911dbbb23"},{"file":"workshop-navigation.js","unchanged":true,"baseline_sha256":"61f845673c0c9aa2c9a650c43bf0e2c05588ab6e78d806a1d21f9875a412996a"},{"file":"workshop-planner.css","unchanged":true,"baseline_sha256":"ac0c86ee34a4785aeee648513da5b9ce188fabf0425f9964dc6ea94f34ae53f1"},{"file":"workshop-planner.js","unchanged":false,"baseline_sha256":"5ef627cc0b957fdfd965146bbc39312c8b9ff841b43339bd3e982f9814532b67"},{"file":"workshop-realtime.js","unchanged":true,"baseline_sha256":"484c0a4ebc6e823fbca6eaf7f6c3fe4e563902abfbd3959221d21c19f45c0361"},{"file":"workshop-reference-data-service.js","unchanged":true,"baseline_sha256":"4fb8ac0421cf7fc94c90a2f272efe66a2bed07c068b3d98dd4ece027e02d0931"},{"file":"workshop-shared-actions.js","unchanged":true,"baseline_sha256":"6080315b8615d544ecec0ad324be883e064ecb912a2c5a28c41a19f11d4980d5"}]};
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function loadMap() {
  const window = {};
  vm.runInNewContext(fs.readFileSync(path.join(ui, 'pd135-api-map.js'), 'utf8'), { window });
  return window.K135_API_MAP;
}

test('actual facade inventory covers required calls with one declared uncommissioned exception',()=>{
 const map=loadMap(),required={"native_rpc_candidates":["add_salesperson","add_sublet_provider","add_technician","admin_approve_user","admin_change_role","admin_disable_user","admin_reject_registration","admin_restore_user","administrator_move_workshop_booking","administrator_schedule_workshop_vehicle","apply_pdc_email_ai_typed_action_surface_20260901","approve_pdc_new_vehicle_review","approve_pdc_tune_operation_change_with_schedule","assign_booking_technician","assign_pdc_vehicle_salesperson_386","book_all_vehicle_stations","book_rft_transport_412","book_rft_transport_700","book_rft_transport_734","book_rft_transport_email_draft_739","cancel_workshop_booking","cascade_workshop_booking_move","cascade_workshop_schedule","change_booking_bay","clear_vehicle_stoppage_422","collect_rft_transport_412","collect_rft_transport_700","collect_rft_transport_734","complete_pdc_vehicle_department_772","complete_workshop_work","create_pdc_acceptance_vehicle_375","create_pdc_sublet_booking","create_pdc_sublet_operation_booking","create_workshop_admin_block","decide_pdc_ai_intake_proposal","delete_pdc_authenticated_operation_line_772","delete_vehicle_workshop_line_adjustment","delete_workshop_admin_block","edit_salesperson","edit_sublet_provider","edit_technician","export_navision_backend_records","finalize_pdc_qc_retest_to_rft_747","finalize_pdc_qc_to_rft_399","finalize_pdc_qc_to_rft_700","fitter_job_command","get_fitter_job","get_fitter_jobs","get_fitter_refresh","get_fitter_roster","get_navision_backend_snapshot","get_navision_reconciliation_report","get_navision_visible_snapshot","get_pdc_ai_intake_snapshot","get_pdc_auditor_review_queue","get_pdc_auditor_snapshot","get_pdc_bus_workflow","get_pdc_email_ai_successor_action_contract_20260901","get_pdc_email_ai_transaction_successor_inbox_v2","get_pdc_email_monitor_status","get_pdc_email_vehicle_board_snapshot","get_pdc_email_vehicle_location_snapshot","get_pdc_review_counts","get_pdc_review_counts_by_department","get_pdc_sublet_audit_ledgers","get_pdc_update_history","get_pdc_usage_report_20260914","get_pdc_vehicle_planning_windows","get_pdc_vehicle_provenance_history","get_station_workshop_snapshot","get_vehicle_workshop_detail_scoped","get_workshop_admin_block_audit_771_successor","get_workshop_booking_search_scoped","get_workshop_capacity_configuration","get_workshop_configuration","get_workshop_eligibility_snapshot","get_workshop_hours_for_setup","get_workshop_overview_revisions","get_workshop_snapshot","list_pdc_new_vehicle_reviews","list_pdc_new_vehicle_reviews_by_department","list_pdc_tune_operation_changes","list_pdc_tune_operation_changes_by_department","list_pdc_unidentified_tune_reviews","list_pdc_unidentified_tune_reviews_by_department","list_salespeople","list_sublet_providers","list_technicians","list_workshop_bays","mark_pdc_parts_ordered_377","mark_pdc_parts_received_authenticated_751","mark_vehicle_ready_for_qc","move_vehicle_workshop_source_line_stage","move_workshop_admin_block","move_workshop_booking","pdc_admin_allow_vehicle_recreation_once","pdc_admin_archive_vehicle","pdc_admin_archived_vehicle_snapshot","pdc_admin_complete_vehicle_delete","pdc_admin_reset_staging_test_vehicle","pdc_admin_restore_vehicle","pdc_pilbara_service_apply_v1","pdc_pilbara_service_preview_v1","pit_transfer_vehicle","pmb_transfer_vehicle","prioritise_workshop_vehicle","qc_complete_vehicle","qc_signoff_to_rft","read_pdc_rft_transport_evidence_734","read_rft_transport_booking_context_739","read_rft_transport_draft_739","record_pdc_auditor_decision","record_pdc_bus_helper_labour","record_pdc_login","record_pdc_qc_photo_evidence_399","record_pdc_qc_retest_photo_747","record_pdc_usage_20260914","reject_pdc_qc_vehicle_to_pmb_stoppage_767","rename_workshop_admin_block_20260904","replan_workshop_capacity","resize_workshop_admin_block","resize_workshop_booking","resolve_vehicle_lifecycle_identity","restore_workshop_booking","resume_workshop_work","retry_vehicle_notification","return_completed_work","return_pdc_sublet_booking","return_work_to_queue","rft_collect_vehicle","rft_transfer_vehicle","save_pdc_bus_workflow","save_vehicle_workshop_line_hours_batch_768","schedule_vehicle_work","set_bay_default_technician","set_pdc_bus_booking_team","set_pdc_bus_supplier_status","set_pdc_parts_stoppage_376","set_pdc_qc_operation_completion_379","set_pdc_vehicle_location_1500","set_pdc_vehicle_location_override","set_pdc_vehicle_work_states","set_pmb_stoppage_422","set_rft_confirmation_736","set_salesperson_active","set_sublet_provider_active","set_technician_active","set_workshop_bay_active","set_workshop_hours_0600_1630","set_workshop_stage_estimated_minutes_407","start_workshop_work","stop_workshop_work","undo_administrator_workshop_booking_move","undo_pdc_authenticated_operation_line_772","update_pdc_parts_eta","update_pdc_sublet_booking","update_pdc_sublet_booking_field","update_pdc_sublet_booking_provider_399","update_pdc_vehicle_detail_fields_388","update_pdc_vehicle_sales_preparation","update_workshop_configuration","upsert_vehicle_workshop_line_adjustment"],"excluded_central_source_rpc_candidates":["activate_navision_backend_record","apply_navision_backend_import","apply_navision_combined_import","apply_navision_upload_profile","approve_navision_combined_initial_scopes","approve_navision_initial_scope","approve_navision_upload_profile","import_broome_sales_orders","link_navision_backend_record","preview_navision_backend_import","preview_navision_combined_import","preview_navision_upload_profile","review_navision_complete_snapshot","rollback_navision_backend_import"],"native_storage_bucket":"pdc-qc-evidence-staging","notes":["RPC candidates include commissioned alternatives and historical rollback functions; backend live catalog must decide exact compatibility availability.","get_navision_visible_snapshot must return only authorised linked Department135 records; no master writer facade.","Source same-shape read uses own local UUID authority and only read-only linked master display fields.","Three reader/export facades are own shadow-only replicas, confirmed by root/backend; central source writes stay blocked.","pdc_admin_complete_vehicle_delete remains intentionally unmapped; unchanged native commissioning gate is false."],"native_rest_relation_candidates":["backup_runs","navision_backend_revision","pdc_ai_intake_revision","pdc_auditor_revision","pdc_email_ai_successor_ui_revision","pdc_email_vehicle_revision","pdc_final_pdc_lifecycle_receipts_700","pdc_user_roles","restore_test_runs","salespeople","sublet_providers","vehicle_parts_updates","vehicle_work_items","vehicles","workshop_bays","workshop_revision","workshop_technicians"],"additional_dynamic_relations":["workshop_station_revision","workshop_settings"],"own_scoped_source_reader_export_candidates":["export_navision_backend_records","get_navision_backend_snapshot","get_navision_reconciliation_report"],"intentionally_unmapped_historical_candidates":["pdc_admin_complete_vehicle_delete"]};
 const missing=required.native_rpc_candidates.filter(name=>!map.rpc[name]);assert.deepEqual(missing,required.intentionally_unmapped_historical_candidates);
 for(const name of required.excluded_central_source_rpc_candidates)assert.equal(map.rpc[name],undefined,name);
 for(const name of required.own_scoped_source_reader_export_candidates)assert.ok(map.rpc[name]?.startsWith('k135_'));
});
test('all frozen native files outside declared boundary adaptations retain original bytes', () => {
  assert.equal(manifest.files.length, 95);
  for (const item of manifest.files.filter(row => row.unchanged)) {
    const native = fs.readFileSync(path.join(ui,item.file));
    // Shared PDC/Sales now includes Sales activity; the native centre retains its
    // original own-engine tracker. Pin that unchanged asset independently.
    if (item.file === 'pdc-staff-usage.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'adb054e560cb911a588622303e7f7f4549d7274eb840e6051002fc5e6bc041de',item.file);
    // PMG now has a read-error recovery repair; keep the isolated fitter asset at its original baseline.
    else if (item.file === 'control-board-overview.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'440d999fb5478214a2c763093068b3446bbdd7f97847853f26e86650fb13c7b1',item.file);
    else if (['pdc-fitters.js','canonical-entry.js','control-board-overview.js','pdc-new-vehicles.css','workshop-planner.css','pdc-review-stations.js','pdc-review-stations.css'].includes(item.file)) assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),item.baseline_sha256,item.file);
    else if (item.file === 'pdc-planner-slim.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),item.baseline_sha256,item.file);
    // r482: the PMG Prioritise vehicle copy asks about a parts ETA before applying (F95); the hidden Karratha copy stays frozen.
    // (pdc-book-all-stations.js uses the r483 branch below: its Karratha copy stays at the manifest baseline.)
    else if (item.file === 'pdc-emergency-priority.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'4a4b4a13455c2395209a569efe3957ec1811a25a8e44104c8dad85ceba64d64f',item.file);
    // r417: the PMG copy asks to confirm a bay rule warning; the hidden Karratha copy stays frozen.
    else if (item.file === 'workshop-shared-actions.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'6080315b8615d544ecec0ad324be883e064ecb912a2c5a28c41a19f11d4980d5',item.file);
    // r483: the PMG copy shows the Dept 139 bay names (F96); the hidden Karratha copy stays frozen.
    else if (item.file === 'pdc-book-all-stations.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),item.baseline_sha256,item.file);
    // r497: the PMG copy guards the capacity cache read on the first planner open (F110); the hidden Karratha copy stays frozen.
    else if (item.file === 'pdc-planner-capacity.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),item.baseline_sha256,item.file);
    // r501: the PMG Sublet intake hides Create Sublet / Book Sublet and points to Manage sublets (F114); the hidden Karratha copy stays frozen.
    else if (item.file === 'pdc-sublet-intake.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),item.baseline_sha256,item.file);
    else if (item.file === 'workshop-data-service.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'004267f09a9fa4f5ad0852dd8f983e25395d8352f8b0f9fb798777b3d733e9ff',item.file);
    // r526: the PMG outstanding Parts paint is blue (F140). Department 135 is not tagged and keeps the orange paint.
    else if (item.file === 'styles.css') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r532: the PMG other-station list stays full strength when this bay can tick it (F146). Department 135 keeps this frozen copy.
    else if (item.file === 'pdc-fitters.css') assert.equal(sha(native), item.baseline_sha256, item.file);
    // r527: a refused technician write no longer clears the bay list (F141). Department 135 keeps this frozen copy.
    else if (item.file === 'workshop-reference-data-service.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r572: open 138/139 job cards stack on every PMG board view (F186). Department 135 keeps these frozen copies.
    else if (item.file === 'pdc-stacked-jobcards.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    else if (item.file === 'pdc-stacked-jobcards.css') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), 'aa7e9bcc40a8a86b18fd0f91023de0b82fea03c7106e70fcbe550c30d3f5b0c3', item.file);
    // r661: only a job placed in a bay shows as booked on the PMG station icons (F271). Department 135 keeps its frozen copy.
    else if (item.file === 'vehicle-requirements-guard.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r695: the PMG copy exposes PDC_OPEN_LOCATION_OVERRIDE for the side panel's Override location button (F305). Department 135 keeps its frozen copy.
    else if (item.file === 'pdc-location-override.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r747: the PMG copy counts the side-panel Parts complete tick as a confirmation (F353). Department 135 keeps its frozen copy.
    else if (item.file === 'pdc-parts-confirmation.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r756a: the PMG Completed page gained scope buttons (F361); the hidden Karratha copy stays frozen.
    else if (item.file === 'pdc-completed-history.css') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    // r807: the PMG copy puts Email salesperson before Mark RFT'd and Mark collected on the RFT page only (F423); the hidden Karratha copy stays frozen.
    else if (item.file === 'pdc-rft-actions.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))), item.baseline_sha256, item.file);
    else assert.deepEqual(native,fs.readFileSync(path.join(original,item.file)),item.file);
  }
});
test('all CSS and core planner/helper presentation files remain byte-exact', () => {
  for (const item of manifest.files.filter(row => row.file.endsWith('.css'))) assert.equal(item.unchanged, true, item.file);
  // workshop-data-service.js is an approved root difference: a confirmed
  // write stays committed when the follow-up read loses authority. Department
  // 135 keeps its frozen copy.
  for (const file of ['canonical-entry.js', 'pdc-fitters.js', 'workshop-reference-data-service.js', 'workshop-shared-actions.js', 'workshop-realtime.js', 'pdc-planner-slim.js', 'pdc-qc-mobile.js', 'pdc-qc-rework.js', 'pdc-rft-actions.js']) assert.equal(manifest.files.find(row => row.file === file).unchanged, true, file);
});
// Explicitly pinned upstream releases and owner-approved navigation, including the 18 October full-week planner scope repair.
const approvedRootImportPatch = Object.freeze({
  // r497: planner capacity cache read guarded on the first planner open (F110).
  // r539: Close gaps uses the workshop bay name and a hold reason (F153). Department 135 is not tagged.
  // r549: Why it stays prefers workshop_bays.display_name (F163). Department 135 is not tagged.
  "pdc-planner-capacity.js": "3d26cf1c357a64b2328706f3f2902234c13d3678e7c80a2b696f84ee4fa784f2",
  // r493: 'Paused · Key …' label for a started job outside bay working time (F106).
  "pdc-planner-slim.js": "34aa7d3d2b45d80713c120aad743077db85560b6798f2bcd79eb42893134d691",
  "pdc-review-stations.css": "e65e01d446092ae60f05460e7073f07e3bed4ba0299d4858d1c875be9b2e8fb7",
  // Confirmed workshop writes stay committed if the readback authority changes,
  // and the dialog listener fires before the snapshot refresh. Department 135
  // stays parked and keeps the previous service bytes.
  // r417: bay_rule_warning and bay_rule_not_confirmed are known codes (F32).
  // r424: bay re-order RPCs and their codes (F38).
  // r592: place_after_running and place_after_not_confirmed are known codes (F206). Department 135 keeps its frozen copy.
  "workshop-data-service.js": "b72621c72dcbbfbfe614226e2d13a93ada56208e92d844302dd105f5cb5617b8",
  // Bhavesh-authorised PMG non-Navision booking lookup repair; KTA stays frozen.
  "pdc-review-stations.js": "851ebde33942fd3a3542f2292093483b6f9bc9f3ff9feb6cfc96aa8e6cf51488",
  "supabase/migrations/20261015005540_bus4x4_department_bays_and_shared_work.sql": "9b8c4934d263bad4d0c0ed808a82771246ac7caaaaf8566da4af3bd1a1d1df01",
  "supabase/migrations/20261015003957_accepted_vehicle_operation_updates.sql": "6e75bf6e2b5dcaee264fb6414e20e066175f08295a5753dcc16f50b8e29a213d",
  // r447: Dept 138 bay guide: preferred (own) bays and no-warning bays incl. overflow 5-6; preferredBays() (F60).
  // r450: whole-job booking (BUS_WHOLE_JOB, wholeJobChoice) for Dept 138 Bus 4x4 (F63).
  // r483: PMB_BAYS map, pmbBayLabel() and bayLabel() show Craig's Dept 139 bay names (F96).
  // r509: Fabrication planner count is 14 (F122). Karratha's copy stays frozen.
  // r548: a missing bay reads Unallocated (F162). Department 135 is not tagged.
  // r566: Electrical planner count is 7; PMB Bays 20-22 hidden (F180). Department 135 is not tagged.
  "pdc-workshop-departments.js": "d77909d0ade7193f32d092981fcbaeab53d4ff6a7a8a95442587a9a08a69fb90",
  // Shared planner: pointer-capture drops from a deep queue or search overlay,
  // keep the last search rows during a post-drop refresh, close Add to planner
  // when the write is confirmed, follow the bay mechanic, and keep unallocated
  // counts on the snapshot totals; planner cards offer a controller reset for
  // a running item left too long (r384). Department 135's copy stays frozen.
  // r415: started-then-returned jobs can be dragged, Best slot or Scheduled again; the server resumes them (F31).
  // r417: every visible bay offered; a drop books the bay's own outstanding category; bay rule warning messages (F32).
  // r424: stopped jobs in Unallocated re-plan; drag onto a booking in the same bay offers Move ahead of / Swap with, preview, undo (F38).
  // r447: own bays first in the Schedule list, Best slot uses own bays only, new category_bay_mismatch text (F60).
  // r448: Bay 3 refusal text: height restriction, no Coaster, confirm route (F61).
  // r449: retired parts-readiness banner and messages removed; one out-of-date message for retired parts codes (F62).
  // r450: Schedule window offers Whole job to one technician; whole jobs show by bay (F63).
  // r469: the planner names the booking a cascade push would clash with (F82).
  // r470: Find scrolls to the result once per selection, not on every render (F83).
  // r478: station vehicle job popup shows the estimated hours read-only; no manual hours save (F91).
  // r483: planner slot summary, booking search, weekly header, admin block bay picker and overlap text use the Dept 139 bay names (F96).
  // r482: every booking command asks about a parts ETA after the booking date before it is sent (F95).
  // r493: workshopEntryPausedNow: started tile outside bay working time is amber Paused; running strip paused reason (F106).
  // r498: 'Undo last move' shows straight after an administrator move and goes after Undo (F111).
  // r527: QA Bay 07 resolves by code, bay number, QA label or the live snapshot, and a refused technician write no longer says to sign in as an administrator (F141). Department 135 keeps its frozen planner.
  // r531: the clash helper is called only when it is loaded, so the error catalog can read the describer on its own (F145).
  // r535: Schedule offers Next available or a bay order (F149). Department 135 keeps its frozen planner.
  // r540: a job chip opens the Vehicle Locations side panel instead of the centred station job modal (F154). Department 135 keeps its frozen planner.
  // r550: Find a workshop booking is a key-number box plus stock, job card, customer or vehicle (F164). Department 135 keeps its frozen planner.
  // r548: null-bay siblings do not block a drop, and bay 0 reads Unallocated (F162). Department 135 is not tagged.
  // Linked job-card search labels use the same verified card list as matching; Department 135 keeps its frozen planner.
  // r549: bay headers, toasts and the side panel prefer display_name. A controller pencil renames that label only (F163).
  // r561: slim Workshop Planner header — one title, status dot, one control row (F175). Department 135 keeps its frozen planner.
  // r569: Pause for another job on a started or stoppage chip (F183). Department 135 keeps its frozen planner.
  // r572: a planner bay lists every open job card, primary first (F186). Department 135 is not tagged.
  // r566: delegates vehicle search matching to pdc-workshop-vehicle-search.js (F180). Department 135 is not tagged.
  // r570: per-bay work hours when a Bay Manager override exists; no override keeps today's windows (F184). Department 135 keeps its frozen planner.
  // r573: the left rail has a Stoppage section for a parts ETA placed as STOPPAGE (F187). Department 135 is not tagged.
  // r592: a drop onto a running job asks to place this job after it and lists the jobs that move back (F206). Department 135 keeps its frozen planner.
  // r594: an unallocated drag books the unticked lines for that station (F208). Department 135 keeps its frozen planner.
  // r597: an occupied-bay drop cascades and says which jobs moved; a bayless card shows the unticked hours (F211). Department 135 keeps its frozen planner.
  // 30 Oct 2026: a same-bay swap applies straight away (no preview screen); Undo re-order stays. Department 135 keeps its frozen planner.
  // 30 Oct 2026: Start wraps its server call in the busy overlay ("Starting Key N… moving later jobs back"). Department 135 keeps its frozen planner.
  "workshop-planner.js": "d50c33aa61c9002044f0c44b403d540df65fffdcbf689a0c40c5cd139b3a184c", // r863 (F414): Unallocated parts chip; r862 (F413): At PMB sort; returned bookings sorted in (r861 F411, r860 F410)
  // r527: a refused set_bay_default_technician no longer wipes the cached bay list (F141). Department 135 keeps the baseline bytes.
  // r549: setWorkshopBayDisplayName calls set_workshop_bay_display_name (F163). Department 135 keeps the baseline bytes.
  "workshop-reference-data-service.js": "105e1f26100390826b8a4b0b8dabd12233a356995d067c24bf9585d9277319a9",
  // r415: the started-before chip keeps its dashed border but is no longer greyed out (F31).
  // r457: one-column side menu 901-1180 px and no blank band in the stacked planner header up to 1300 px (F70).
  // r478: read-only estimated work hours value in the station vehicle job popup (F91).
  // r535: Next available / Bay order controls on the Schedule dialog (F149). Department 135 keeps its frozen stylesheet.
  // r550: the two search boxes sit above the department selector (F164).
  // r549: the bay rename field sits in the bay header (F163).
  // r561: slim Workshop Planner header chrome (F175). Department 135 keeps its frozen stylesheet.
  // r570: blue bay-hours caption under the bay name (F184). Department 135 keeps its frozen stylesheet.
  // r573: Stoppage section cards are blue (F187). Department 135 keeps its frozen stylesheet.
  "workshop-planner.css": "8171feaa6db86a48e6b32043492dfec7cdf2b58681ead91d43fda12557418571", // r863 (F414): Unallocated parts chip; r862 (F413): At PMB sort; returned bookings sorted in (r861 F411, r860 F410)
  // Publish minifies app.js and styles.css in the Pages artifact only.
  // Department 135 still compares the unminified source pin below.
  // r526: outstanding Parts (class imported-parts-orange) paints #dbeafe / #1d4ed8 / #2563eb (F140).
  // Department 135 is not tagged and keeps the orange paint. The colour token and the labels stay.
  // r557: New to PMB flashes blue, and prefers-reduced-motion keeps a solid blue (F171). Department 135 is not tagged.
  // r562: the Key number needed badge is blue (#dbeafe / #1d4ed8), not orange (F176). Department 135 is not tagged.
  // r563: a board-arrival age is grey (#e2e8f0). Department 135 is not tagged.
  // r574: the department bay picker is the same blue (F188). Department 135 is not tagged.
  // r575: a duplicate key sentence on the vehicle card is blue (F189). Department 135 keeps the previous paint.
  // r573: Place as STOPPAGE on the Parts tile is blue (#dbeafe / #1d4ed8) (F187). Department 135 is not tagged.
  // r593: the New to PMB tag is the same blue (F207). Department 135 is not tagged.
  // r582: Delivered to body builder is blue (#dbeafe / #1d4ed8). Department 135 is not tagged.
  // r590: a QC sign-off button that is still blocked is grey (F204). Department 135 keeps the previous paint.
  // r593: the New to PMB tag is the same blue (F207). Department 135 is not tagged.
  "styles.css": "795e162db7a7a6938ba03ce984b9371176ee2fcdcda9654e400e234247092bd2",
  // r495: allowlist adds site-switcher-branches.js, sales/sales-branch.js, sales/karratha-sales-import.js and the Karratha Toyota logo (F108).
  // r565: the runtime list adds pdc-bus-component-split.js before the fitter scripts (F179). Department 135 is not tagged.
  // r566: the runtime list adds pdc-workshop-vehicle-search.js before the Vehicle Locations table (F180). Department 135 is not tagged.
  // r570: the runtime list adds pdc-bay-manager.css and pdc-bay-manager.js (F184). Department 135 is not tagged.
  // r591: the runtime list adds pdc-revolution-upload.css and pdc-revolution-upload.js (F205). Department 135 is not tagged.
  // r816: the runtime list adds pdc-fitter-logins.js; pdc-fitters.js/.css and pdc-bay-manager.css carry r816 (fitter logins, F455). Department 135 is not tagged.
  "scripts/build_pages_runtime.js": "201582c959e13dbaa39601a0c322a5a1ec67ddf4f0e12aad31f62b52cd3701ad",
  "pdc-operation-review-slim.css": "67196ee7dd4415c31c1eb2237fbcdb6c49fa5852fa7d0020aedf6198db0b167a",
  // Quick approval ignores unable-to-estimate, AI and conflicting hours tags
  // on Sublet lines. Department 135 keeps its frozen copy.
  "pdc-new-vehicles.js": "3f8dc80f7b51493fd0da7224c5ab65345ca1ee3c9c33bbcdedeb574242576f75",
  "pdc-new-vehicles.css": "8e3930a3d42f6b309e327ae1f1bec066f15794be114868f5b4fe015eb3a142d5",
  "docs/bus4x4-workflow.md": "d2dab9a76da3b23ddfe0e21418d9e0f8212b48aa517443c47e657b2f656869c8",
  // r456: staff guide matches r447/r448/r450 bay rules (F69).
  "docs/bus4x4-user-guide.md": "e360b5a829db55d14694007d41301ca7c1deea9362b2f42b3bec6651cdb5ea24",
  // r456: staff guide matches r447/r448/r450 bay rules (F69).
  "docs/bus4x4-user-guide.html": "66e58fb788f8ba4653baa4b0dba0ad92286783f79ab742ce8801a21933a05798",
  // pdc-new-vehicles.js? adds sublet-hours-tags=2026.10.20.01.
  // r436: loads pdc-parts-eta.js?parts-eta=2026.10.21.r436 after pdc-service-locations.js (parts ETA beside the parts location, F47).
  // r439: loads pdc-sublet-po.js?sublet-po=2026.10.21.r439 (GP PO lines with a sublet done tick; Sublet box orange/green, F50).
  // r439b: pdc-sublet-po.js?sublet-po=2026.10.21.r439b (PO chip and sublet done tick inline on each line, F53).
  // r439c: pdc-sublet-po.js?sublet-po=2026.10.21.r439c (PO chip and tick on their own row; F55).
  // r443: loads pdc-operation-panels.js?operation-panels=2026.10.21.r443 after pdc-sublet-po.js (packed category panels; F56).
  // r444: sublet-po=2026.10.21.r444 and operation-panels=2026.10.21.r444 (Sublet box lists every sublet with its description; F57).
  // r445: loads pdc-sublet-po-attach.js?sublet-po-attach=2026.10.21.r445 between pdc-sublet-po.js and pdc-operation-panels.js (sublet PO attach pilot; F58).
  // r446: r446=2026.10.21.r446 on pdc-new-vehicles.js and pdc-new-vehicles.css (Dept 138 review uses the Bus 4x4 stations; F59).
  // r459: r459=2026.10.22.r459 on pdc-new-vehicles.js (Dept 138 approval follows the reviewer's station; F72).
  // r460: loads pdc-key-number.js?key-number=2026.10.22.r460 after pdc-parts-eta.js (vehicle key number edit + audit; F73).
  // r461: loads pdc-vehicle-locations-table.js?vehicle-locations-table=2026.10.22.r461 after pdc-key-number.js (Vehicle Locations table view switch, default drop-down; F74).
  // r462: r462=2026.10.22.r462 on the table module, then loads pdc-vehicle-slideout.js?vehicle-slideout=2026.10.22.r462 after it (Table view slide-out panel, Parts loc column, resizable columns; F75).
  // r463: r463=2026.10.22.r463 on the table module and vehicle-slideout=2026.10.22.r463 (Job Card column; panel drag-to-bay withdrawn; F76).
  // r472: key-number=2026.10.22.r460&r472=2026.10.22.r472 on pdc-key-number.js (vehicle-card key save keeps snapshot rows raw; F85).
  // r473: vehicle-slideout=2026.10.22.r473 on pdc-vehicle-slideout.js (panel top without the summary row, Open Vehicle; F86).
  // r475: r475=2026.10.22.r475 on pdc-parts-eta.js and on the table module (parts ETA countdown + source hover, Parts ETA column; F88).
  // r476: r476=2026.10.22.r476 on the table module (Vehicle Locations Table view columns bunched up; F89).
  // r481: r481=2026.10.22.r481 on the table module (search shows matches from every tile and other departments; F94).
  // r483: r483=2026.10.22.r483 on pdc-book-all-stations.js (F96).
  // r482: r482=2026.10.22.r482 on pdc-parts-eta.js and pdc-book-all-stations.js (parts ETA warning before booking; F95).
  // r485: r485=2026.10.22.r485 on the table module (Table view only, Drop-down view hidden behind a flag) and vehicle-slideout=2026.10.22.r485 (stoppage box with Clear stoppage / Return to QC; F98).
  // r490: r490=2026.10.23.r490 on pdc-sublet-po.js, pdc-parts-eta.js, pdc-sublet-po-attach.js and pdc-key-number.js (4 s retry only when nothing loaded; no hidden-tab polls; F103).
  // r493: r493=2026.10.22.r493 on pdc-planner-slim.js (F106).
  // r494: r494=2026.10.23.r494 on pdc-sublet-po.js (exposes the per-vehicle GP PO lines to Manage sublets; F107).
  // r494b: r494=2026.10.23.r494b on pdc-sublet-po.js (uniform vehicle Sublet box; F107).
  // r494c: r494=2026.10.23.r494c on pdc-sublet-po.js (board 'PO to raise' with no per-vehicle RPC or redraw; F107b).
  // r496: vehicle-slideout=2026.10.22.r496 on pdc-vehicle-slideout.js (edit hours and move lines between jobs in the panel; F109).
  // r565: vehicle-slideout=2026.10.27.r565 on pdc-vehicle-slideout.js (edit stays on the chip list; F179). Department 135 keeps its frozen loader.
  // r578: vehicle-slideout=2026.10.27.r578 (green complete tick and station override; F196). Department 135 is not tagged.
  // r588: vehicle-slideout=2026.10.28.r588 (operation-line grid: hours, PO chip and tick columns; F202). Department 135 is not tagged.
  // r501: r501=2026.10.23.r501 on pdc-sublet-intake.js (Sublet page create hidden; bookings made in Manage sublets; F114).
  // r557: the Vehicle Locations table loads with r557=2026.10.27.r557 (New to PMB, F171). Department 135 keeps its frozen loader.
  // r560: vehicle-slideout=2026.10.27.r560 (More details link to the vehicle card; F174). Department 135 keeps its frozen loader.
  // r562: the table loader also carries r562=2026.10.27.r562 (key-number gate, F176). Department 135 is not tagged.
  // r563: the table loader also carries r563=2026.10.27.r563 (arrival age, F177). Department 135 is not tagged.
  // r567: pdc-parts-stoppage.js?r567=2026.10.27.r567 loads after the key number and before the table (typed Parts ETA, F181). The table query also carries r567. Department 135 is not tagged.
  // r566: loads pdc-workshop-vehicle-search.js before the key-number chain; the table loader adds r566=2026.10.27.r566 (planner search boxes, F180). Department 135 is not tagged.
  // r593: the table loader also carries r593=2026.10.28.r593 (New to PMB view, F207). Department 135 is not tagged.
  // r575: pdc-key-number.js cache bust r575=2026.10.27.r575 (F189). Department 135 is not tagged.
  // r573: the same loader adds r573=2026.10.27.r573 (Place as STOPPAGE, F187). Department 135 is not tagged.
  // r595: the loader adds r595=2026.10.28.r595 on pdc-parts-stoppage.js. The slide-out keeps vehicle-slideout=2026.10.28.r588 and adds r595=2026.10.28.r595 (Parts ETA is set in the side panel; F209). Department 135 is not tagged.
  // r604: canonical-entry.js loads pdc-pit-bookings.js beside the table and tags the table r604 (Pit column, F218). Department 135 is not tagged.
  // r616: r616=2026.10.28.r616 on the Parts ETA, key-number, Parts stoppage, pit, Sublet PO and Sublet PO attach loaders (fitter sessions stop polling boards, F231). Department 135 is not tagged.
  // r618: canonical-entry.js adds r618=2026.10.28.r618 to the pit and table loaders (pit list on the PIT tile only, searched; F233). Department 135 is not tagged.
  // r630: canonical-entry.js adds r630=2026.10.28.r630 to the pit loader (time and place box on the pit calendar; F245). Department 135 is not tagged.
  // r632: canonical-entry.js adds r632=2026.10.28.r632 to the pit loader (Welshpool, quarter hours; F247). Department 135 is not tagged.
  // r685: canonical-entry.js adds r685=2026.10.29.r685 to the table loader (station headings filter; F295). Department 135 is not tagged.
  // r738: canonical-entry.js adds r738=2026.10.30.r738 to the slide-out loader (line Complete only from its own tick; F343).
  // r745: canonical-entry.js adds r745=2026.10.30.r745 to the table loader (Vehicle Locations opens on PMB; F350).
  // r747: canonical-entry.js adds r747=2026.10.30.r747 to the Parts stoppage and parts confirmation loaders (Parts complete tick; F353). Department 135 is not tagged.
  "pdc-rft-actions.js": "4500a18706c574128c5aa1a784879ec3abed17543f27651a56f5fb72ffe126de", // r807 (F423): email before RFT'd; collect on the RFT page only
  "canonical-entry.js": "d7e13a12887268c6a2eeafacb8911ecf08baf46d02200598cd366e5d04676323", // r803 cache tags; merge; r800 loader; r798 cache tag; r797 slideout cache tag; r795 cache tag; r792: station headings red/green/off cache tag; r863 (F414): Unallocated parts chip; r747 (F353) cache tags
  "pdc-workshop-vehicle-search.js": "d0be4a60c5ca2213ba71d4cd31cb7019736db3d7e0470d22b3fa88243e56eb4c",
  // r747: the side-panel Parts complete tick counts as a parts confirmation on the PMG board (F353). Department 135 keeps its frozen copy.
  "pdc-parts-confirmation.js": "3331298a8335e4b807b6108f67c2a5bc5a3bfdcbe2d97a8153c4061fb4c2e6c7", // r803 red label
  // Owner-authorised PMG fitter read recovery, 13 October 2026.
  // Coaster and HiAce conversions: one Start / Done tick per section in a
  // dropdown (20 Oct 2026); every bay item gets Start / Done and the board
  // shows running items beside a Done-only % (r384). Department 135 keeps
  // the frozen fitter script.
  // r440: item Done needs Start ("Press Start first"), no static " · Done" meta, "under 1 min" actuals, running segment = started items' hours (F51).
  // r449: fitter parts messages say parts no longer hold up a job (F62).
  // r483: fitter page bay text uses the Dept 139 bay names (F96).
  // r493: started items / sections and the running strip show amber Paused while the job clock is held (F106).
  // r500: every started item / section shows Pause (also when running too long) and Resume while the job is stopped; Pause opens the stoppage panel under the item (F113).
  // r532: a started job can tick Start and Done on other-station items (F146). Department 135 keeps the frozen fitter script.
  // r564: Fitters bay shows Key N beside stock (F178). Department 135 keeps the frozen fitter script.
  // r568: a Bus 4x4 bay can start or finish another component's line items (F182). Department 135 keeps the frozen fitter script.
  // r583: each bay line can be sent to another department (F197). Department 135 keeps its frozen pdc-fitters.js.
  // r740: the key tag shows on the next job, later jobs and other active jobs too (Craig, 30 Oct 2026). Department 135 keeps its frozen pdc-fitters.js.
  // r741: one Complete button; unticked items stay open for the station (Craig, 30 Oct 2026). Department 135 keeps its frozen pdc-fitters.js.
  // 30 Oct 2026: Start shows the busy overlay while the server starts the job and pushes later jobs back. Department 135 is not tagged.
  "pdc-fitters.js": "83248f3e4d71e859a5723c84e2c096e0fd201cc356fac8c902e10b1ae94f1ee4",
  // Deliberate live-board change, 19 October 2026. Department 135 stays parked.
  // app.js keeps Setup backup polling, hoist-corrections=2026.10.19.02,
  // planner-followup=2026.10.19.01, and the Vehicle Locations summary that
  // says "Loading vehicles…" until the board snapshot arrives.
  // 20 October 2026: Delivered - At Dealer rows whose vehicle is missing or
  // soft-deleted are listed on the upload result. Department 135 stays parked.
  // r400: QC no longer asks for the Pit inspection or job-card notes lines.
  // r401: Pit and weigh never counts as required work; optional Pit tick for any department.
  // r405: a Pit and weigh / Pit inspection line is Pit by its wording, whatever its category (F14).
  // r408: runtime errors are toasts, not stacking start-up banners (F23); admin list
  // requests surface a failed fetch (F24); index.html adds r408=2026.10.21.01.
  // r409: the other 210 alert() calls are pdcNotify toasts (F25); index.html adds r409=2026.10.21.01.
  // r414: the QC page reads the stored completion photo back (F30); index.html adds qc-photo-readback=2026.10.21.01.
  // r415: workshop-planner.js loads with r415=2026.10.21.01 (started-before jobs re-plan, F31).
  // r417: r417=2026.10.21.01 on workshop-planner.js, workshop-data-service.js and workshop-shared-actions.js (bay rule warn-and-confirm, F32).
  // r419: User Admin role lists offer every role, preselect the real role and confirm role changes (F34); index.html adds r419=2026.10.21.01.
  // r421: importers can no longer show a Navision record on Vehicle Locations (F36); index.html adds r421=2026.10.21.01.
  // r424: r424=2026.10.21.01 on workshop-planner.js, workshop-data-service.js and workshop-shared-actions.js (bay re-order, stopped-job re-plan, F38).
  // r426: Board sales-prep ticks (Tint / Build PO / Tray) read-only for importers and viewers (F39); index.html adds r426=2026.10.21.01.
  // r429: User Admin confirm says a salesperson's Sales record is linked by email (F41); index.html adds r429=2026.10.21.01.
  // r430: User Admin All list hides Disabled accounts behind a "Show disabled (N)" toggle (display only); index.html adds r430=2026.10.21.01.
  // r432: User Admin "Link salesperson record" for controllers (F43); index.html adds r432=2026.10.21.01 on app.js and pdc-auth.js.
  // r437: the vehicle card opens for Toyota head office account vehicles (001234 / 002345) under the board's own dealer scope (F48); index.html adds r437=2026.10.21.01.
  // r483: Dept 139 bays show Craig's names (Express / Pits Hoist, Express, Hoist, Fitting 06-10, Internal / External Fabrication 11-12, Electrical 13-22) on booking pills, places, vehicle detail and the control board; Fab planner count 13 -> 2 (F96).
  // r489: Admin > Fitting statistics route (administrators only; guard, admin nav, title, open / close / reset like Update history; F102).
  // r490: the 2-minute workshop reference-data safety net skips while the tab is hidden and catches up once on return (F103).
  // r493: r493=2026.10.22.r493 on both workshop-planner.js loads (paused jobs amber; F106).
  // r491: Sublet page Away now filter and days away / overdue days, cache bust sublet-away (F104) (app.js).
  // r492: Sublet provider email draft adds key number, VIN, sublet work and due back, cache bust sublet-email (F105) (app.js).
  // r498: r498=2026.10.22.r498 on both workshop-planner.js loads (F111).
  // r510: User Administration Role dropdown filters the loaded list on screen (F123).
  // r509: Fabrication planner, WIP and capacity label are 14 bays (live check F122 sort 294). Department 135 keeps its frozen app.js.
  // r518: a verified Navision JITA number completes Parts Jita (F132). Department 135 keeps its frozen app.js.
  // r521: the Booking column no longer uses a Pilbara service job card as a read-only badge (F135). Department 135 keeps its frozen app.js.
  // r524: imported orange, red, review and grey keep the Parts tile colour; a JITA number is the corner mark unless the import is missing or green (F138). Department 135 keeps its frozen app.js.
  // r527: r527=2026.10.25.r527 on workshop-reference-data-service.js and both workshop-planner.js loads (QA bay technician, F141). Department 135 keeps its frozen app.js.
  // r531: r531=2026.10.26.r531 on both workshop-planner.js loads (duration cache and technician clash text, F145). Department 135 keeps its frozen app.js.
  // r535: r535=2026.10.26.r535 on both workshop-planner.js loads (Schedule next slot or bay order, F149). Department 135 keeps its frozen app.js.
  // r540: r540=2026.10.26.r540 on both workshop-planner.js loads (chip opens the vehicle side panel, F154). Department 135 keeps its frozen app.js.
  // r536: r536=2026.10.26.r536 on app.js (confirm before an unstarted booking is released; F150). Department 135 keeps its frozen app.js.
  // r540: r540=2026.10.26.r540 on both workshop-planner.js loads in app.js (chip opens the vehicle side panel, F154). Department 135 is not tagged.
  // r550: r550=2026.10.26.r550 on both workshop-planner.js loads (F164).
  // r548: r548=2026.10.26.r548 on both workshop-planner.js loads in app.js (unallocated rows do not block a bay, F162). Department 135 is not tagged.
  // search-jobcards=2026.10.26.01 versions both planner loads; Department 135 keeps its frozen app.js.
  // r549: booking pills and the vehicle side panel prefer display_name, and both planner loads add r549=2026.10.26.r549 (F163).
  // r556: Parts ETA email warnings on the vehicle card for a controller (F170). Department 135 keeps its frozen app.js.
  // r557: New to PMB tile and acknowledgement (F171). Department 135 keeps its frozen app.js.
  // r560: stock numbers open the Vehicle Locations side panel; More details opens the vehicle card (F174). Department 135 keeps its frozen app.js.
  // r561: r561=2026.10.27.r561 on both workshop-planner.js loads (slim planner header, F175). Department 135 is not tagged.
  // r562: a vehicle cannot leave New to PMB without a key number (F176). Department 135 is not tagged. app.js keeps r560 for the stock panel and adds r562.
  // r563: the PMB age is the earlier of that key instant and the first Tune import (F177). Department 135 is not tagged.
  // r565: side-panel completion read and controller tick (F179). Department 135 keeps its frozen app.js. app.js keeps r560, r562 and the arrival-age r563, and adds r565.
  // r566: Electrical bay count 7 in PMB_WIP_LIMITS / PMB_STAGE_BAY_COUNTS (F180). Department 135 keeps its frozen app.js. app.js keeps r560, r562, the arrival-age r563 and r565, and adds r566.
  // r569: r569=2026.10.27.r569 on both workshop-planner.js loads and both workshop-shared-actions.js loads (pause a bay job for another, F183). Department 135 is not tagged.

  // r573: a job wording longer than 2000 characters is named when hours cannot be saved (F187). Department 135 keeps its frozen app.js and the 180-character prompt.

  // r574: a keyed New to PMB tick can book that department's bay (F188). Department 135 keeps its frozen app.js.
  // r570: Bay Manager under Admin, and r570=2026.10.27.r570 on both workshop-planner.js loads (F184). Department 135 is not tagged.
  // r575: a changed key that another loaded board vehicle already has says which stock, in blue (F189). Department 135 is not tagged.
  // r578: a station icon is green when every line of that station is complete, or a controller overrides it (F196). Department 135 is not tagged.
  // r573: r573=2026.10.27.r573 on both workshop-planner.js loads, and the Parts tile date has a blue Place as STOPPAGE button (F187). Department 135 is not tagged.
  // r582: a body-builder delivery stays on New to PMB until To PMB (F195). Department 135 keeps its frozen app.js.
  // r592: r592=2026.10.28.r592 on both workshop-planner.js loads, both workshop-shared-actions.js loads, and the workshop-data-service.js loads (F206). Department 135 is not tagged.
  // r594: r594=2026.10.28.r594 on both workshop-planner.js loads and on app.js (unticked station hours, F208). Department 135 is not tagged.
  // r590: the QC sign-off button stays visible and names what is still outstanding (F204). Department 135 keeps its frozen app.js.
  // r593: a recent key is listed in New to PMB and stays in the PMB bucket. No department tick (F207). Department 135 keeps its frozen app.js.
  // r591: Admin > Revolution uploads is administrators only (F205). Department 135 is not tagged.
  // r687: ".2" hours save as 0.2 in Edit hours and jobs (F297). Department 135 keeps its frozen app.js.
  "app.js": "c56f00d66dfb4107b9fabe32930093c88129cd3d0977ff4384afc4e30a95fbc9", // merge; r799 dept station columns; r863 (F414): Unallocated parts chip; r862 (F413): At PMB sort; returned bookings sorted in (r861 F411, r860 F410)
  "vehicle-requirements-guard.js": "7462e178c839df0ce1bd2509b838dab61fd739172f20fd0c34a419e011052658",
  // r464: a booking that runs past the day divider is one bar (joined per-day pieces, display only; F77). The Karratha copy stays frozen.
  // r465: overview bar labels show Key · JC and the customer only (Stock and the vehicle description stay in the hover title); the customer span is classed for the Running layout (F78).
  // r467: Day / Week / Month zoom on the overview timeline (display only; F80).
  // r483: overview bay rows use the Dept 139 bay names; inactive bays with nothing booked are not drawn (F96). The Karratha copy stays frozen.
  // r493: STOPPAGE bars show the running strip as Paused (amber; F106).
  // r509: control board comment matches the 14-bay fabrication count (live check F122 sort 294). The hidden Karratha copy stays frozen.
  // r549: Control Board bay rows prefer display_name (F163). The Karratha copy stays frozen.
  // r572: a control-board bay card lists every open job card (F186). Department 135 keeps the frozen copy.
  "control-board-overview.js": "44f2f3925850c19f6afd2ae45b37a4344a13f20d47b8193f2b7885684c104d86",
  "deployment-manifest.json": "1dc3bc539884bba81076059861c3621db90cca8a721eb8d6cfef81da99454b46",
  // Live board defers its startup scripts and drops the empty and assessment tags.
  // app.js?v= keeps backup-status=2026.10.19.01, hoist-corrections=2026.10.19.02,
  // location-loading=2026.10.19.01 and publish-minify=2026.10.19.01, and adds
  // planner-followup=2026.10.19.01. delivery-review=2026.10.20.01 loads the
  // upload result that lists held Delivered - At Dealer rows.
  // Source app.js stays the pin above. The Pages artifact minifies that source.
  // Department 135's pages stay frozen.
  // pdc-fitters.js conversion-tick=2026.10.20.02, item-ticks=2026.10.20.02, self-update=2026.10.20.01 and
  // pdc-conversion-ticks.css v=2026.10.20.02.
  // canonical-entry.js? adds sublet-hours-tags=2026.10.20.01.
  // r399: app.js, workshop-planner.js, workshop-data-service.js and pdc-workshop-departments.js
  // add bay8-category=2026.10.20.01 (Bus 4x4 bay lists by category, done-before-the-board).
  // r400: app.js adds qc-pit-notes=2026.10.20.01.
  // r401: app.js and pdc-email-vehicle-location-service.js add pit-neutral=2026.10.20.01.
  // r405: app.js adds pit-text=2026.10.20.01.
  // r408: app.js and pdc-auth.js add r408=2026.10.21.01.
  // r409: app.js adds r409=2026.10.21.01.
  // r414: qc-photo-readback=2026.10.21.01 on app.js and pdc-email-vehicle-location-service.js.
  // r415: r415=2026.10.21.01 on workshop-planner.css.
  // r419: app.js adds r419=2026.10.21.01.
  // r421: app.js adds r421=2026.10.21.01.
  // r426: app.js adds r426=2026.10.21.01.
  // r429: app.js adds r429=2026.10.21.01.
  // r430: app.js adds r430=2026.10.21.01.
  // r432: app.js and pdc-auth.js add r432=2026.10.21.01.
  // r437: app.js adds r437=2026.10.21.01.
  // r436: canonical-entry.js adds parts-eta=2026.10.21.r436.
  // r440: pdc-fitters.js and pdc-conversion-ticks.css add start-before-done=2026.10.21.r440 (F51).
  // r439: index.html adds sublet-po=2026.10.21.r439 on canonical-entry.js (F50).
  // r441: index.html loads pdc-auto-reload.js first (reload open tabs after a release, F52); Department 135 is not tagged.
  // r439b: index.html sublet-po=2026.10.21.r439b on canonical-entry.js (F53).
  // r439c: index.html sublet-po=2026.10.21.r439c on canonical-entry.js (F55).
  // r443: index.html operation-panels=2026.10.21.r443 on canonical-entry.js (F56).
  // r444: index.html sublet-po=2026.10.21.r444 and operation-panels=2026.10.21.r444 on canonical-entry.js (F57).
  // r445: index.html sublet-po-attach=2026.10.21.r445 on canonical-entry.js (F58).
  // r446: index.html r446=2026.10.21.r446 on canonical-entry.js (F59).
  // r447: index.html bay-guide=2026.10.21.r447 on pdc-workshop-departments.js (F60).
  // r449: parts-retired=2026.10.21.r449 on pdc-fitters.js (F62).
  // r450: index.html whole-job=2026.10.21.r450 on pdc-workshop-departments.js (F63).
  // r459: index.html r459=2026.10.22.r459 on canonical-entry.js (F72).
  // r460: index.html key-number=2026.10.22.r460 on canonical-entry.js (F73).
  // r454: index.html identity-dealer=2026.10.22.r454 on pdc-email-vehicle-location-service.js (F67).
  // r457: index.html ipad-landscape=2026.10.22.r457 on workshop-planner.css (F70).
  // r458: index.html vehicle-created=2026.10.22.r458 on pdc-email-vehicle-location-service.js (F71).
  // r461: index.html vehicle-locations-table=2026.10.22.r461 on canonical-entry.js (F74).
  // r462: index.html r462=2026.10.22.r462 on canonical-entry.js (F75).
  // r463: index.html r463=2026.10.22.r463 on canonical-entry.js (F76).
  // r464: index.html r464=2026.10.22.r464 on control-board-overview.js (F77).
  // r465: index.html loads pdc-running-row.css?running-row=2026.10.22.r465 after pdc-conversion-ticks.css and adds running-row=2026.10.22.r465 on control-board-overview.js (F78).
  // r466: index.html slim Emergency vehicle priority panel (text moved to hover titles) and pdc-emergency-slim.css?emergency-slim=2026.10.22.r466 (F79).
  // r467: index.html r467=2026.10.22.r467 on control-board-overview.js and control-board-zoom.css?control-board-zoom=2026.10.22.r467 (F80).
  // r469: index.html r469=2026.10.22.r469 on canonical-entry.js (F82).
  // r470: index.html r470=2026.10.22.r470 on canonical-entry.js (F83).
  // r472: index.html r472=2026.10.22.r472 on canonical-entry.js (F85).
  // r473: index.html r473=2026.10.22.r473 on canonical-entry.js (F86).
  // r475: index.html r475=2026.10.22.r475 on canonical-entry.js (F88).
  // r476: index.html r476=2026.10.22.r476 on canonical-entry.js (F89).
  // r477: index.html loads pdc-sidebar-compact.css?sidebar-compact=2026.10.22.r477 last (PMG sidebar compressed, Parts nav item hidden by a flag; F90).
  // r478: index.html r478=2026.10.22.r478 on workshop-planner.css (F91).
  // r480: index.html pdc-copyright.css link and copyright footer (sidebar foot + sign-in screen) (F93).
  // r481: index.html r481=2026.10.22.r481 on canonical-entry.js (F94).
  // r483: index.html r483=2026.10.22.r483 on pdc-workshop-departments.js, control-board-overview.js, app.js, pdc-fitters.js and canonical-entry.js (F96).
  // r482: r482=2026.10.22.r482 on canonical-entry.js and pdc-emergency-priority.js (F95).
  // r485: index.html r485=2026.10.22.r485 on canonical-entry.js (F98).
  // r489: index.html adds the Fitting statistics admin nav item and view (hidden), pdc-fitting-stats.css / .js?r489=2026.10.23.r489 and r489=2026.10.23.r489 on app.js (F102).
  // r489: index.html moves r489=2026.10.23.r489 on app.js next to r483, adds r489 on pdc-staff-usage.js (F102).
  // r490: index.html r490=2026.10.23.r490 on canonical-entry.js and app.js (F103).
  // r493: r493=2026.10.22.r493 on pdc-fitters.js, pdc-conversion-ticks.css, pdc-running-row.css, control-board-overview.js and canonical-entry.js (F106).
  // r493b: r493b=2026.10.22.r493b on pdc-running-row.css (F106b).
  // r491: Sublet page Away now filter and days away / overdue days, cache bust sublet-away (F104) (index.html).
  // r492: Sublet provider email draft adds key number, VIN, sublet work and due back, cache bust sublet-email (F105) (index.html).
  // r494: index.html adds pdc-vehicle-sublets.css / .js?r494=2026.10.23.r494 and r494=2026.10.23.r494 on canonical-entry.js (Manage sublets; F107).
  // r494b: r494=2026.10.23.r494b on pdc-vehicle-sublets.css / .js and canonical-entry.js (uniform Sublet box; F107).
  // r494c: r494=2026.10.23.r494c on canonical-entry.js (board 'PO to raise' with no per-vehicle RPC or redraw; F107b).
  // r496: index.html r496=2026.10.22.r496 on canonical-entry.js (F109).
  // r497: r497=2026.10.22.r497 on pdc-planner-capacity.js (F110).
  // r498: r498=2026.10.22.r498 on app.js (F111).
  // r500: r500=2026.10.23.r500 on pdc-fitters.js and pdc-conversion-ticks.css (F113).
  // r501: r501=2026.10.23.r501 on canonical-entry.js and pdc-vehicle-sublets.css / .js (Due out / Due back in Manage sublets; F114).
  // r509: r509=2026.10.23.r509 on pdc-workshop-departments.js, app.js and control-board-overview.js (14 fabrication bays; F122).
  // r502: r502=2026.10.23.r502 on pdc-vehicle-sublets.css / .js, pdc-email-vehicle-location-service.js and canonical-entry.js query (Manage sublets Save error codes, ^ clean, promote, layout; F115).
  // r495: Website option Karratha Toyota (Sales), site-switcher-branches.js after the frozen switcher, r495 on pdc-auth.js (F108). Department 135 is not tagged.
  // r510: Role dropdown beside the User Administration status tabs; r510=2026.10.23.r510 on app.js (F123). Department 135 is not tagged.
  // r516: JITA Upload under Navision Uploads; r516=2026.10.23.r516 on canonical-entry.js (F130). Department 135 is not tagged.
  // r517: JITA apply confirmation and Parts ETA nesting; r517=2026.10.23.r517 on pdc-jita-eta.js and canonical-entry.js (F131). Department 135 is not tagged.
  // r518: r518=2026.10.23.r518 on app.js (a verified Navision JITA number completes Parts Jita; F132). Department 135 is not tagged.
  // r519: JITA Upload hidden and the nested JITA ETA not drawn; r519=2026.10.23.r519 on canonical-entry.js (F133). Department 135 is not tagged. r518 Parts Jita tick stays.
  // r521: r521=2026.10.24.r521 on app.js (Booking column does not show the Pilbara service read-only badge; F135). Department 135 is not tagged.
  // r524: r524=2026.10.24.r524 on app.js and sales/pmb-stations.js (imported orange, red, review and grey keep the Parts colour; F138). Department 135 is not tagged.
  // r509: r509=2026.10.23.r509 on pdc-workshop-departments.js, app.js and control-board-overview.js (14 fabrication bays; live check F122 sort 294).
  // r525: r525=2026.10.24.r525 on pdc-staff-usage.js (Website activity Last 24 hours; F139). Department 135 is not tagged. The applied check stays usage_period_24h_513 / F126.
  // r526: r526=2026.10.24.r526 on styles.css (outstanding Parts paint is blue; F140). Department 135 is not tagged.
  // r532: r532=2026.10.26.r532 on pdc-fitters.js (other-station Start and Done; F146). Department 135 is not tagged.
  // r535: r535=2026.10.26.r535 on workshop-planner.css (Schedule next slot or bay order, F149). Department 135 is not tagged.
  // r536: r536=2026.10.26.r536 on app.js (confirm before an unstarted booking is released; F150). Department 135 is not tagged.
  // r539: r539=2026.10.26.r539 on pdc-planner-capacity.js (Close gaps bay name and hold reason; F153). Department 135 is not tagged.
  // r550: r550=2026.10.26.r550 on workshop-planner.css (F164). Department 135 is not tagged.
  // r548: r548=2026.10.26.r548 on pdc-workshop-departments.js and app.js (unallocated rows do not block a bay, F162). Department 135 is not tagged.
  // search-jobcards=2026.10.26.01 versions the app loader; Department 135 keeps its frozen entry page.
  // r549: r549=2026.10.26.r549 on the planner stylesheet, Control Board and Close gaps (bay display name; F163). Department 135 is not tagged.
  // r556: r556=2026.10.26.r556 on app.js (Parts ETA email warnings, not the Stoppages bucket; F170). Department 135 is not tagged.
  // r557: index.html adds r557=2026.10.27.r557 on app.js and canonical-entry.js (New to PMB, F171). Department 135 is not tagged.
  // r560: index.html adds r560=2026.10.27.r560 on app.js (stock opens side panel, F174). Department 135 is not tagged.
  // r561: r561=2026.10.27.r561 on workshop-planner.css (slim planner header, F175). Department 135 is not tagged.
  // r562: index.html adds r562=2026.10.27.r562 on canonical-entry.js, app.js and styles.css (key-number gate, F176). The stock-panel r560 on app.js stays. Department 135 is not tagged.
  // r563: index.html adds r563=2026.10.27.r563 on canonical-entry.js, app.js and styles.css (arrival age, F177). Department 135 is not tagged.
  // r564: index.html adds r564=2026.10.27.r564 on pdc-fitters.js (Fitters key badge, F178). Department 135 is not tagged.
  // r565: index.html adds r565=2026.10.27.r565 on canonical-entry.js and app.js (side-panel edit stays on the chip list, F179). styles.css keeps the arrival-age r563. Department 135 is not tagged.
  // r566: index.html adds r566=2026.10.27.r566 on pdc-workshop-departments.js and app.js (hide Elec PMB 20-22, F180). Arrival-age r563 and panel r565 stay. Department 135 is not tagged.
  // r567: index.html adds r567=2026.10.27.r567 on canonical-entry.js (typed Parts ETA, F181). Fitters r564 stays on pdc-fitters.js. Department 135 is not tagged.

  // r568: index.html loads pdc-bus-component-split.js and adds r568=2026.10.27.r568 on pdc-fitters.js (F182). Department 135 is not tagged.

  // r572: r572=2026.10.27.r572 on pdc-stacked-jobcards.js and pdc-stacked-jobcards.css (F186). Department 135 is not tagged.

  // r573: index.html adds r573=2026.10.27.r573 on app.js and pdc-email-vehicle-location-service.js (hours wording, F187). Department 135 is not tagged.

  // r574: index.html adds r574=2026.10.27.r574 on app.js and styles.css (department bay booking, F188). Department 135 is not tagged.

  // r566: index.html loads pdc-workshop-vehicle-search.js (F180). Department 135 is not tagged.
  // r570: Bay Manager nav and view, pdc-bay-manager.css/js, and r570 on app.js and workshop-planner.css (F184). Department 135 is not tagged.
  // r575: index.html adds r575=2026.10.27.r575 on the key cell, the card, the detail save and the stylesheet (F189). Department 135 is not tagged.
  // r578: index.html adds r578=2026.10.27.r578 on canonical-entry.js and app.js (station icon complete, F196). Department 135 is not tagged.
  // r588: index.html adds r588=2026.10.28.r588 on canonical-entry.js (side-panel tick grid, F202). Department 135 is not tagged.
  // r593: index.html adds r593=2026.10.28.r593 on app.js and styles.css (New to PMB view, F207). Department 135 is not tagged.
  // r573: index.html adds r573=2026.10.27.r573 on canonical-entry.js, and the hidden JITA panel has Place as STOPPAGE (F187). Department 135 is not tagged.
  // r582: index.html adds r582=2026.10.27.r582 on app.js, styles.css and vehicle-location-lifecycle.js (body-builder hold, F195). Department 135 is not tagged.
  // r583: index.html adds r583=2026.10.27.r583 on pdc-fitters.js and pdc-fitters.css (send a line to another department, F197). Department 135 is not tagged.
  // r592: index.html adds r592=2026.10.28.r592 on app.js and workshop-data-service.js (F206). Department 135 is not tagged.
  // r590: index.html adds r590=2026.10.28.r590 on app.js and pdc-email-vehicle-location-service.js (QC sign-off wording, F204). Department 135 is not tagged.
  // r595: index.html adds r595=2026.10.28.r595 on canonical-entry.js (Parts ETA is set in the side panel, F209). Department 135 is not tagged.
  // r591: Revolution uploads nav, view, stylesheet and script (F205). Department 135 is not tagged.
  // r597: index.html adds r597=2026.10.28.r597 on app.js (unticked hours and cascade without a question, F211). Department 135 is not tagged.
  // r591: index.html cache-busts pdc-revolution-upload.js after the header fix (F205). Department 135 is not tagged.
  // r602: index.html cache-busts pdc-revolution-upload.js so the dry run compares the current board (F216). Department 135 is not tagged.
  // r601: index.html adds r601=2026.10.28.r601 on app.js (cascade text, cross-bay guard off, F212 to F215). Department 135 is not tagged.
  // r604: index.html adds r604=2026.10.28.r604 on canonical-entry.js (pit bookings, F218). Department 135 is not tagged.
  // r616: pdc-auth.js, pdc-bay-manager.js and canonical-entry.js carry r616=2026.10.28.r616 (fitter sessions send only Fitters bay requests, F231). Department 135 is not tagged.
  // r642: Sublet · MMT nav and view, pdc-mmt-sublet.css/js, r642 on app.js and pdc-staff-usage.js (F257). Department 135 is not tagged.
  "index.html": "21586dc5b16e470f5464e8043a82ee0c52511fb18628dc15f990390224900d74", // r808 (F443) stock take tag and intro text (was r781 F386)
  "pdc-conversions.js": "0a99e7a5306f15e434b293a3ca9a318ffad4b78eb814c27144d75ff98821d810",
  // r401: Pit tick and read RPCs (set_pdc_pit_line_tick_401, get_pdc_pit_line_ticks_401).
  // r414: readQcPhotoReceipt (get_pdc_qc_photo_receipt_414) for the QC page (F30).
  // r454: a board row's identity_dealer_code (14450/37047) fills a missing dealer in mapServerVehicle (F67).
  // r458: Detailed history shows a vehicle's creation as Created (presentVehicleCreationEvents, display only) (F71).
  // r502: subletRpc returns message + safe json(); createSubletBooking normalises identity / truncates notes (F115).
  // r573: a description-check rejection from the hours batch is returned as hours_description_rejected (F187). Department 135 keeps its frozen copy.
  // r575: the vehicle-detail save keeps the server's key sentence (F189). Department 135 is not tagged.
  // r590: sign-off failures keep the server sentence, and QC can ask what is still outstanding (F204). Department 135 keeps its frozen copy.
  "pdc-email-vehicle-location-service.js": "e7b7b1895d7a122ccfb69274f87376c5e9d483e7265b4aaad3985dd81b8e1c2b",
  // r590: the phone sign-off names what is still outstanding. Both copies move together. Department 135 is not tagged.
  "pdc-qc-mobile.js": "ef70a4f25b81d51c514d3bc74d3efa15e1e1cb1069fc05d41e6c9b2816ad1dc5",
  // r482: Prioritise vehicle asks before applying a plan that books before the parts ETA (F95).
  "pdc-emergency-priority.js": "f32dfc9d81bafb4dcfb8e6e6805f4932ba5e5219149093d9bc45f1e1ae34d7db",
  // r532: other-station items stay full strength when this bay can tick them (F146).
  // r564: fitter-key-badge styles beside stock (F178).
  // r583: a sent line is blue (#1d4ed8 / #2563eb). Green stays complete (F197). Department 135 keeps its frozen stylesheet.
  "pdc-fitters.css": "b7be2bb27352e03840e544ed51beb5c02ab8aa33347eeeaa2c6d8663157486f6",
  // r572: stacked job cards are readable outside the incoming row (F186). Department 135 keeps the previous sheet.
  "pdc-stacked-jobcards.css": "ae0ca5c86f4342befcb197bbf262a2775c527cac82aaad6b8c7f2c35f6bef30b",
  "pdc-stacked-jobcards.js": "76e6b3da13a00eb26a2fdda738233876f7333632526b7a657d39fc612c4211de",
  "pdc-staff-usage.css": "e7769d72b7601097fa4c41a19140fdcda4408f3d1f620008282d9df136b1ddf0",
  // r489: 'fitting-stats' counts under the Update History bucket (F102).
  // r525: Period option Last 24 hours (p_days 1) on Website activity (F139). The Karratha copy stays frozen.
  // r570: bay-manager counts under the Update History bucket (F184). The Karratha copy stays frozen.
  // r591: revolution-upload counts under the Update History bucket (F205). The Karratha copy stays frozen.
  // r768 (F430): Sales Navision Uploads counts under the Navision Uploads (import) bucket.
  "pdc-staff-usage.js": "b5f4267529ae56c52c1e4e1ab40ebb43f007c3072924f1c0ff2e642c0f242f2c",
  "site-switcher.css": "84882066f9ff13057de368d8af1418788e82b2723ec68683166e2f8ded6c8348",
  // r403: the own-role monitor reconnects instead of locking on a realtime blip
  // (F11); index.html and app.js/canonical-entry.js add r403=2026.10.21.01 for
  // pdc-auth.js, app.js, canonical-entry.js, workshop-planner.js/.css and
  // pdc-new-vehicles.js (plain error text, started-before chips, next-workday
  // default, no return in finally). Department 135 keeps its frozen copies.
  // r408: no record_pdc_login for Fitters bay accounts (F22).
  // r432: a controller linked to a salesperson record stays on the Sales site (pdc_my_sales_link_432) (F43).
  // r495: on the Sales page only, sends the x-pdc-sales-branch header for a non-Broome Sales branch (Karratha) (F108).
  // r616: fitter sessions answer non-Fitters-bay RPCs locally with 42501 and never send them (F231). Department 135 keeps its frozen auth script.
  // r890: pdc-auth.js sends the workshop TV login to the TV page and refuses its other RPCs (F440). Department 135 is not tagged.
  "pdc-auth.js": "ed1a89d00411548510504cb046fa8974215e8315138a569f68c7eb084f29d980",
  // r417: administrator move/schedule ask the planner to confirm a bay rule warning, then resend confirmed (F32).
  // r424: push-back warning confirm; bay re-order and undo actions (F38).
  // r569: pauseBayForOther calls pause_bay_job_for_other_566 (F183). Department 135 keeps its frozen copy.
  // r592: a running-job drop asks to place the job after it (F206). Department 135 keeps its frozen copy.
  "workshop-shared-actions.js": "8f7c750886938a752021d83457623f1cdd0a1fb9a6495be347d8494e5df45851",
  // r483: Book all stations result shows the Dept 139 bay names (F96). The Karratha copy stays frozen.
  // r482: Book all stations asks first when the parts ETA is after today and marks bookings before it (F95).
  "pdc-book-all-stations.js": "5001a53b8a79fc7bd4cdc837178ff8b53cb5afd61a94991c27543d22db8c6e3c",
  // r501: Create Sublet and Book Sublet hidden behind CREATE_ON_SUBLET_PAGE=false; calendar view only with Manage sublets per card (F114). Karratha stays frozen.
  "pdc-sublet-intake.js": "7054c68b4b0bffdf8e738dc96177a67195f7076ed8e83eae11ad1fc27d6f214b",
  "site-switcher.js": "dbd495a575c34078fdfb62103ac74becbccc4d9bd260287a5f0eff067de6d938",
  // r574: OD Delivered to body builder stays a PMB location and waits for To PMB (F188). Department 135 keeps its frozen lifecycle module.
  "vehicle-location-lifecycle.js": "cdc5463c07cd7d653e22b4772e86583cd9dad7695a428141b6a51918ae2d8304",
  // r695: the side panel opens the override dialog through PDC_OPEN_LOCATION_OVERRIDE (F305). Department 135 keeps its frozen copy.
  "pdc-location-override.js": "f3d8b723184351a2abb0674b222d2fb7f00037c21640a66f3b7e62abbf8d874d",
  // r756a (F361): Completed page scope buttons (Completed | Archived | All left the board). Department 135 keeps its frozen copy.
  "pdc-completed-history.css": "20fd3338d06196746e8c4104ccb5e462691cb73e21ab5edd2375c8dc6b7e0041"
});
test('PMB/Sales runtime preserves its frozen baseline and approved root release patches', () => {
  for (const item of manifest.files) {
    let bytes = fs.readFileSync(path.join(original, item.file));
    if (!item.file.endsWith('.png')) bytes = Buffer.from(bytes.toString('utf8').replace(/\r\n/g, '\n'));
    if (item.file === 'index.html') bytes = Buffer.from(bytes.toString('utf8').split(/(?<=\n)/).filter(line => !line.includes('src="pd-department-navigation.js')).join(''));
    assert.equal(sha(bytes), approvedRootImportPatch[item.file] || item.baseline_sha256, item.file);
  }
});
test('static connection is ready while operational readiness stays gated and transport precedes Auth', () => {
  const map = loadMap(); assert.equal(map.ready, true);
  assert.equal(JSON.parse(fs.readFileSync(path.join(ui,'deployment-manifest.json'),'utf8')).operational,false);
  const html = fs.readFileSync(path.join(ui, 'index.html'), 'utf8');
  assert.ok(html.indexOf('src="pd135-transport.js') < html.indexOf('src="pdc-auth.js'));
  assert.ok(html.indexOf('src="pd135-transport.js') < html.indexOf('src="app.js'));
  assert.ok(html.includes('data-view="planner-tint"'));
  assert.ok(html.includes('data-view="planner-hoist"'));
  assert.ok(html.includes('data-view="planner-fitting"'));
  assert.ok(html.includes('data-view="planner-fab"'));
  assert.ok(html.includes('data-view="planner-elec"'));
  assert.ok(html.includes('data-view="planner-tyre"'));
  assert.equal(html.includes('data-view="import"'), false);
  assert.equal(html.includes('<section id="import"'), false);
  assert.equal(html.includes('src="broome-navision-import.js'), false);
  assert.equal(html.includes('src="sales/navision-orders.js'), false);
});
test('own browser namespace also covers backups, clear/reset, table widths and planner freshness', () => {
  for (const file of ['app.js', 'workshop-planner.js', 'scripts/stage2b_c4_browser_export.js']) {
    const code = fs.readFileSync(path.join(ui, file), 'utf8');
    assert.equal(/(?<!k135)vehicleTrackingCore/.test(code), false, file);
    assert.ok(code.includes('k135VehicleTrackingCore'), file);
  }
  assert.ok(fs.readFileSync(path.join(ui, 'pdc-department-filter.js'), 'utf8').includes('k135_department_view_filter_v1'));
});
test('own resource defaults contain no copied staff/provider/email/printer allocations', () => {
  const app = fs.readFileSync(path.join(ui, 'app.js'), 'utf8');
  for (const constant of ['DEFAULT_MECHANICS', 'DEFAULT_SUBLET_PROVIDERS', 'DEFAULT_SALESPERSONS', 'QZ_DEFAULT_PRINTER_NAMES']) assert.ok(app.includes('const ' + constant + ' = [];'), constant);
  for (const constant of ['AMY_EMAIL', 'PMG_UPDATE_EMAIL', 'TINT_EMAIL', 'RFT_SALESPERSON_EMAIL']) assert.ok(app.includes("const " + constant + " = '';"), constant);
  assert.ok(app.includes("String(photo.bucket_id || '').trim() === 'karratha135-qc-evidence-staging'"));
});
test('native auth verifies its exact own engine and tracks membership changes', () => {
  const auth = fs.readFileSync(path.join(ui, 'pdc-auth.js'), 'utf8');
  assert.ok(auth.includes("state.client.rpc('k135_get_native_engine_context', {})"));
  assert.ok(auth.includes("value.user_id === session.user.id && typeof value.ready === 'boolean'"));
  assert.equal(auth.match(/if \(context.ready !== true\) return \{ role: null, error: null, commissioning: true \};/g)?.length,2);
  assert.ok(auth.includes("setMessage('Signed in — awaiting verification'"));
  assert.ok(auth.includes('value.engine_version === window.K135_API_MAP?.engine_version'));
  assert.ok(auth.includes('state.role.membership_version !== role.membership_version'));
  assert.ok(auth.includes("state.client.rpc('k135_request_department_access_135'"));
  assert.equal(auth.includes('get_karratha_pdc_context'), false);
  assert.ok(auth.includes('await applySession(session);'));
  assert.ok(auth.includes("window.PDC_SUPABASE_CONFIG?.centreCode === '135'"));
});

test('uncommissioned historical complete-delete cannot acquire a guessed facade',()=>{
  const map=loadMap();assert.equal(map.rpc.pdc_admin_complete_vehicle_delete,undefined);
  const config=fs.readFileSync(path.join(ui,'pdc-supabase-config.staging.js'),'utf8');assert.ok(config.includes('completeVehicleDeleteCommissioned: false'));
  const app=fs.readFileSync(path.join(ui,'app.js'),'utf8');assert.ok(app.includes('window.PDC_SUPABASE_CONFIG?.vehicleLifecycle?.completeVehicleDeleteCommissioned === true'));
});

test('Department 135 filters use real source codes and Bus is excluded without altering six workshop rules', () => {
  const review=require('./karratha/pdc-new-vehicles.js');
  assert.equal(review.normalizeReviewDepartment('135'),'135');assert.equal(review.normalizeReviewDepartment('139'),'');
  assert.deepEqual(review.departmentReadRequest('list_pdc_new_vehicle_reviews',{},'135'),{name:'list_pdc_new_vehicle_reviews_by_department',payload:{p_department:'135'}});
  assert.throws(()=>review.verifyDepartmentResponse({data:{department:'139'}},'135'),/scope_mismatch/);
  assert.equal(review.STATIONS.some(([code])=>code==='BUS_4X4'),false);
  const html=fs.readFileSync(path.join(ui,'index.html'),'utf8');
  assert.equal(html.includes('data-view="planner-bus-4x4"'),false);assert.equal(html.includes('src="pdc-bus-workflow.js'),false);
  const eligibility=fs.readFileSync(path.join(ui,'workshop-eligibility.js'),'utf8');
  assert.equal(eligibility.includes("Object.freeze({ code: 'BUS_4X4'"),false);
  for(const code of ['TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE'])assert.ok(eligibility.includes("code: '"+code+"'"));
});
test('every copied JS script remains syntactically valid and no private fixture enters the release', () => {
  const files = ["ai-auditor.css","ai-board-advisor.js","app.js","arb-labor-catalog.js","assets/brand-logo.svg","assets/pmb-logo.png","broome-navision-import.js","canonical-entry.js","control-board-overview.js","data-staging-empty.js","deployment-manifest.json","desktop-operations.css","email-board-data.js","favicon.svg","index.html","navision-backend-service.js","navision-vin.js","pd135-api-map.js","pd135-navigation.js","pd135-nuvu-intake.css","pd135-nuvu-intake.js","pd135-nuvu-parser.js","pd135-transport.js","pdc-ai-auditor-stage-a.js","pdc-ai-intake-review.css","pdc-ai-intake-review.js","pdc-ai-intake-service.js","pdc-auth-registration.js","pdc-auth.js","pdc-book-all-stations.js","pdc-bus-workflow.css","pdc-bus-workflow.js","pdc-completed-history.css","pdc-conversions.js","pdc-department-filter.js","pdc-email-ai-successor-inbox.css","pdc-email-ai-successor-inbox.js","pdc-email-ai-v2-actions.js","pdc-email-vehicle-location-service.js","pdc-emergency-priority.css","pdc-emergency-priority.js","pdc-estimated-hours.css","pdc-estimated-hours.js","pdc-fitters.css","pdc-fitters.js","pdc-location-override.js","pdc-new-vehicles.css","pdc-new-vehicles.js","pdc-parts-confirmation.js","pdc-planner-capacity.css","pdc-planner-capacity.js","pdc-planner-slim.css","pdc-planner-slim.js","pdc-professional-polish.css","pdc-qc-mobile.css","pdc-qc-mobile.js","pdc-qc-rework.js","pdc-review-stations.css","pdc-review-stations.js","pdc-rft-actions.css","pdc-rft-actions.js","pdc-service-locations.js","pdc-stacked-jobcards.css","pdc-stacked-jobcards.js","pdc-staff-usage.css","pdc-staff-usage.js","pdc-sublet-intake.js","pdc-supabase-config.staging.js","pdc-update-history.css","pdc-update-history.js","pdc-vehicle-handover.js","pdc-workshop-hours.js","pdc-workshop-tile-cleanup.js","pdc-workshop-usability.js","sales/navision-orders.js","scripts/stage2b_c4_browser_export.js","site-switcher.css","site-switcher.js","staging-browser-assessment.js","styles.css","vehicle-lifecycle-actions.js","vehicle-location-lifecycle.js","vehicle-locations-refresh-ui.js","vehicle-locations-refresh.js","vehicle-modal-identity.js","vehicle-requirements-guard.js","vendor/pdfjs/LICENSE","vendor/pdfjs/pdf.min.js","vendor/pdfjs/pdf.worker.min.js","vendor/qz/qz-tray.js","vendor/supabase/supabase-2.110.5.js","vendor/xlsx/LICENSE","vendor/xlsx/xlsx.full.min.js","workshop-booking-timing.js","workshop-data-service.js","workshop-display-identity.js","workshop-eligibility.js","workshop-navigation.js","workshop-planner.css","workshop-planner.js","workshop-realtime.js","workshop-reference-data-service.js","workshop-shared-actions.js"];
  for (const file of files.filter(name=>name.endsWith('.js'))) new vm.Script(fs.readFileSync(path.join(ui,file),'utf8'),{filename:file});
  for (const file of ['private-fixture.js','private-fixture.css','candidate-index.html','app-domain.js','calendar.js','api.js','auth.js','config.js','karratha.css','nuvu.js']) assert.equal(fs.existsSync(path.join(ui,file)),false,file);
});
