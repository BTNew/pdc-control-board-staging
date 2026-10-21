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
    // r417: the PMG copy asks to confirm a bay rule warning; the hidden Karratha copy stays frozen.
    else if (item.file === 'workshop-shared-actions.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'6080315b8615d544ecec0ad324be883e064ecb912a2c5a28c41a19f11d4980d5',item.file);
    else if (item.file === 'workshop-data-service.js') assert.equal(sha(Buffer.from(native.toString('utf8').replace(/\r\n/g,'\n'))),'004267f09a9fa4f5ad0852dd8f983e25395d8352f8b0f9fb798777b3d733e9ff',item.file);
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
  "pdc-planner-slim.js": "d9b51f217cc1fb85d2a4a009f54d2902e9d2388f023984b6f20f158a6a090709",
  "pdc-review-stations.css": "e65e01d446092ae60f05460e7073f07e3bed4ba0299d4858d1c875be9b2e8fb7",
  // Confirmed workshop writes stay committed if the readback authority changes,
  // and the dialog listener fires before the snapshot refresh. Department 135
  // stays parked and keeps the previous service bytes.
  // r417: bay_rule_warning and bay_rule_not_confirmed are known codes (F32).
  // r424: bay re-order RPCs and their codes (F38).
  "workshop-data-service.js": "6dfb5b4400b3fe42f61c2cbc64ee6e95e452b508297ce8f00ef5cee061bcf4dd",
  // Bhavesh-authorised PMG non-Navision booking lookup repair; KTA stays frozen.
  "pdc-review-stations.js": "851ebde33942fd3a3542f2292093483b6f9bc9f3ff9feb6cfc96aa8e6cf51488",
  "supabase/migrations/20261015005540_bus4x4_department_bays_and_shared_work.sql": "9b8c4934d263bad4d0c0ed808a82771246ac7caaaaf8566da4af3bd1a1d1df01",
  "supabase/migrations/20261015003957_accepted_vehicle_operation_updates.sql": "6e75bf6e2b5dcaee264fb6414e20e066175f08295a5753dcc16f50b8e29a213d",
  // r447: Dept 138 bay guide: preferred (own) bays and no-warning bays incl. overflow 5-6; preferredBays() (F60).
  // r450: whole-job booking (BUS_WHOLE_JOB, wholeJobChoice) for Dept 138 Bus 4x4 (F63).
  "pdc-workshop-departments.js": "bd8d72d06f318f6c0c63f1451892570d766dc8e0283facdcf6f4c27bebcd7ddb",
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
  "workshop-planner.js": "ea451784cd90f348c90418fa56f21d010e31f9587f85da5d8f48c52984a78eb2",
  // r415: the started-before chip keeps its dashed border but is no longer greyed out (F31).
  "workshop-planner.css": "51c8dd7628ee620d55af26b7f1af78cbb4a2c7c0b8aa4e729faaac38d7cf4cfa",
  // Publish minifies app.js and styles.css in the Pages artifact only.
  // Department 135 still compares the unminified source pin below.
  "scripts/build_pages_runtime.js": "f39cb3b2b550ac467feb7acbec932c091a8ad75229531e539fc706ec665210d3",
  "pdc-operation-review-slim.css": "67196ee7dd4415c31c1eb2237fbcdb6c49fa5852fa7d0020aedf6198db0b167a",
  // Quick approval ignores unable-to-estimate, AI and conflicting hours tags
  // on Sublet lines. Department 135 keeps its frozen copy.
  "pdc-new-vehicles.js": "3f8dc80f7b51493fd0da7224c5ab65345ca1ee3c9c33bbcdedeb574242576f75",
  "pdc-new-vehicles.css": "8e3930a3d42f6b309e327ae1f1bec066f15794be114868f5b4fe015eb3a142d5",
  "docs/bus4x4-workflow.md": "d2dab9a76da3b23ddfe0e21418d9e0f8212b48aa517443c47e657b2f656869c8",
  "docs/bus4x4-user-guide.md": "d2729f19b9132afcfe4ee41413c98d2fba9db03c99e45a3a1d298cb57be9840f",
  "docs/bus4x4-user-guide.html": "0a56823214fdd0e5ba0f7601671a92678d87231f07052937eaf09cdf29773b0a",
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
  "canonical-entry.js": "1a16c2b9cc6a25f4690c766308c14cbf093ec3c65e12c0ea243916ae47c67d8b",
  // Owner-authorised PMG fitter read recovery, 13 October 2026.
  // Coaster and HiAce conversions: one Start / Done tick per section in a
  // dropdown (20 Oct 2026); every bay item gets Start / Done and the board
  // shows running items beside a Done-only % (r384). Department 135 keeps
  // the frozen fitter script.
  // r440: item Done needs Start ("Press Start first"), no static " · Done" meta, "under 1 min" actuals, running segment = started items' hours (F51).
  // r449: fitter parts messages say parts no longer hold up a job (F62).
  "pdc-fitters.js": "1718b24ee86e7d1874a0810b9a627b32672ab2f9ca3abb160a13fb7608c930ee",
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
  "app.js": "0feed7e96704a3d98cc3d3b41636a767aea447a58aefbc8f102f7ba73f67c089",
  "control-board-overview.js": "82de1cc91b314ef995a2f2d997990993092133804240682f4c18294f1bce2194",
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
  "index.html": "0c7f39f86db9be557d9346685efa7ce1f14672f78bb318f30d3b61b68e2b48da",
  "pdc-conversions.js": "0a99e7a5306f15e434b293a3ca9a318ffad4b78eb814c27144d75ff98821d810",
  // r401: Pit tick and read RPCs (set_pdc_pit_line_tick_401, get_pdc_pit_line_ticks_401).
  // r414: readQcPhotoReceipt (get_pdc_qc_photo_receipt_414) for the QC page (F30).
  "pdc-email-vehicle-location-service.js": "0c7a2678c17ca384fcd01f5f35c01c248c4d62d59762dbfb96b6780498e4860e",
  "pdc-emergency-priority.js": "4a4b4a13455c2395209a569efe3957ec1811a25a8e44104c8dad85ceba64d64f",
  "pdc-fitters.css": "fefe7159e728653806fcc7e62f5e7d30dfc99e67b5cc38fab04eb8ee6794fb9a",
  "pdc-stacked-jobcards.css": "aa7e9bcc40a8a86b18fd0f91023de0b82fea03c7106e70fcbe550c30d3f5b0c3",
  "pdc-staff-usage.css": "e7769d72b7601097fa4c41a19140fdcda4408f3d1f620008282d9df136b1ddf0",
  "pdc-staff-usage.js": "0aed9f9c4045745faf38a2024ccf8cc7c30751a1564fdfd500175a9aa97f7282",
  "site-switcher.css": "84882066f9ff13057de368d8af1418788e82b2723ec68683166e2f8ded6c8348",
  // r403: the own-role monitor reconnects instead of locking on a realtime blip
  // (F11); index.html and app.js/canonical-entry.js add r403=2026.10.21.01 for
  // pdc-auth.js, app.js, canonical-entry.js, workshop-planner.js/.css and
  // pdc-new-vehicles.js (plain error text, started-before chips, next-workday
  // default, no return in finally). Department 135 keeps its frozen copies.
  // r408: no record_pdc_login for Fitters bay accounts (F22).
  // r432: a controller linked to a salesperson record stays on the Sales site (pdc_my_sales_link_432) (F43).
  "pdc-auth.js": "f1cc70b86a4fdbb4bef78c39040d264184c7cc542f412ebae2035079ff61ef2d",
  // r417: administrator move/schedule ask the planner to confirm a bay rule warning, then resend confirmed (F32).
  // r424: push-back warning confirm; bay re-order and undo actions (F38).
  "workshop-shared-actions.js": "dcc5cda131757438ce285de7130672addb540664e13d56b666f03df0cd45df1f",
  "site-switcher.js": "dbd495a575c34078fdfb62103ac74becbccc4d9bd260287a5f0eff067de6d938"
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
