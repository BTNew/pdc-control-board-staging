'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const test = require('node:test');
const transport = require('./karratha/pd135-transport.js');
const required = {"native_rpc_candidates":["add_salesperson","add_sublet_provider","add_technician","admin_approve_user","admin_change_role","admin_disable_user","admin_reject_registration","admin_restore_user","administrator_move_workshop_booking","administrator_schedule_workshop_vehicle","apply_pdc_email_ai_typed_action_surface_20260901","approve_pdc_new_vehicle_review","approve_pdc_tune_operation_change_with_schedule","assign_booking_technician","assign_pdc_vehicle_salesperson_386","book_all_vehicle_stations","book_rft_transport_412","book_rft_transport_700","book_rft_transport_734","book_rft_transport_email_draft_739","cancel_workshop_booking","cascade_workshop_booking_move","cascade_workshop_schedule","change_booking_bay","clear_vehicle_stoppage_422","collect_rft_transport_412","collect_rft_transport_700","collect_rft_transport_734","complete_pdc_vehicle_department_772","complete_workshop_work","create_pdc_acceptance_vehicle_375","create_pdc_sublet_booking","create_pdc_sublet_operation_booking","create_workshop_admin_block","decide_pdc_ai_intake_proposal","delete_pdc_authenticated_operation_line_772","delete_vehicle_workshop_line_adjustment","delete_workshop_admin_block","edit_salesperson","edit_sublet_provider","edit_technician","export_navision_backend_records","finalize_pdc_qc_retest_to_rft_747","finalize_pdc_qc_to_rft_399","finalize_pdc_qc_to_rft_700","fitter_job_command","get_fitter_job","get_fitter_jobs","get_fitter_refresh","get_fitter_roster","get_navision_backend_snapshot","get_navision_reconciliation_report","get_navision_visible_snapshot","get_pdc_ai_intake_snapshot","get_pdc_auditor_review_queue","get_pdc_auditor_snapshot","get_pdc_bus_workflow","get_pdc_email_ai_successor_action_contract_20260901","get_pdc_email_ai_transaction_successor_inbox_v2","get_pdc_email_monitor_status","get_pdc_email_vehicle_board_snapshot","get_pdc_email_vehicle_location_snapshot","get_pdc_review_counts","get_pdc_review_counts_by_department","get_pdc_sublet_audit_ledgers","get_pdc_update_history","get_pdc_usage_report_20260914","get_pdc_vehicle_planning_windows","get_pdc_vehicle_provenance_history","get_station_workshop_snapshot","get_vehicle_workshop_detail_scoped","get_workshop_admin_block_audit_771_successor","get_workshop_booking_search_scoped","get_workshop_capacity_configuration","get_workshop_configuration","get_workshop_eligibility_snapshot","get_workshop_hours_for_setup","get_workshop_overview_revisions","get_workshop_snapshot","list_pdc_new_vehicle_reviews","list_pdc_new_vehicle_reviews_by_department","list_pdc_tune_operation_changes","list_pdc_tune_operation_changes_by_department","list_pdc_unidentified_tune_reviews","list_pdc_unidentified_tune_reviews_by_department","list_salespeople","list_sublet_providers","list_technicians","list_workshop_bays","mark_pdc_parts_ordered_377","mark_pdc_parts_received_authenticated_751","mark_vehicle_ready_for_qc","move_vehicle_workshop_source_line_stage","move_workshop_admin_block","move_workshop_booking","pdc_admin_allow_vehicle_recreation_once","pdc_admin_archive_vehicle","pdc_admin_archived_vehicle_snapshot","pdc_admin_complete_vehicle_delete","pdc_admin_reset_staging_test_vehicle","pdc_admin_restore_vehicle","pdc_pilbara_service_apply_v1","pdc_pilbara_service_preview_v1","pit_transfer_vehicle","pmb_transfer_vehicle","prioritise_workshop_vehicle","qc_complete_vehicle","qc_signoff_to_rft","read_pdc_rft_transport_evidence_734","read_rft_transport_booking_context_739","read_rft_transport_draft_739","record_pdc_auditor_decision","record_pdc_bus_helper_labour","record_pdc_login","record_pdc_qc_photo_evidence_399","record_pdc_qc_retest_photo_747","record_pdc_usage_20260914","reject_pdc_qc_vehicle_to_pmb_stoppage_767","rename_workshop_admin_block_20260904","replan_workshop_capacity","resize_workshop_admin_block","resize_workshop_booking","resolve_vehicle_lifecycle_identity","restore_workshop_booking","resume_workshop_work","retry_vehicle_notification","return_completed_work","return_pdc_sublet_booking","return_work_to_queue","rft_collect_vehicle","rft_transfer_vehicle","save_pdc_bus_workflow","save_vehicle_workshop_line_hours_batch_768","schedule_vehicle_work","set_bay_default_technician","set_pdc_bus_booking_team","set_pdc_bus_supplier_status","set_pdc_parts_stoppage_376","set_pdc_qc_operation_completion_379","set_pdc_vehicle_location_1500","set_pdc_vehicle_location_override","set_pdc_vehicle_work_states","set_pmb_stoppage_422","set_rft_confirmation_736","set_salesperson_active","set_sublet_provider_active","set_technician_active","set_workshop_bay_active","set_workshop_hours_0600_1630","set_workshop_stage_estimated_minutes_407","start_workshop_work","stop_workshop_work","undo_administrator_workshop_booking_move","undo_pdc_authenticated_operation_line_772","update_pdc_parts_eta","update_pdc_sublet_booking","update_pdc_sublet_booking_field","update_pdc_sublet_booking_provider_399","update_pdc_vehicle_detail_fields_388","update_pdc_vehicle_sales_preparation","update_workshop_configuration","upsert_vehicle_workshop_line_adjustment"],"excluded_central_source_rpc_candidates":["activate_navision_backend_record","apply_navision_backend_import","apply_navision_combined_import","apply_navision_upload_profile","approve_navision_combined_initial_scopes","approve_navision_initial_scope","approve_navision_upload_profile","import_broome_sales_orders","link_navision_backend_record","preview_navision_backend_import","preview_navision_combined_import","preview_navision_upload_profile","review_navision_complete_snapshot","rollback_navision_backend_import"],"native_storage_bucket":"pdc-qc-evidence-staging","notes":["RPC candidates include commissioned alternatives and historical rollback functions; backend live catalog must decide exact compatibility availability.","get_navision_visible_snapshot must return only authorised linked Department135 records; no master writer facade.","Source same-shape read uses own local UUID authority and only read-only linked master display fields.","Three reader/export facades are own shadow-only replicas, confirmed by root/backend; central source writes stay blocked.","pdc_admin_complete_vehicle_delete remains intentionally unmapped; unchanged native commissioning gate is false."],"native_rest_relation_candidates":["backup_runs","navision_backend_revision","pdc_ai_intake_revision","pdc_auditor_revision","pdc_email_ai_successor_ui_revision","pdc_email_vehicle_revision","pdc_final_pdc_lifecycle_receipts_700","pdc_user_roles","restore_test_runs","salespeople","sublet_providers","vehicle_parts_updates","vehicle_work_items","vehicles","workshop_bays","workshop_revision","workshop_technicians"],"additional_dynamic_relations":["workshop_station_revision","workshop_settings"],"own_scoped_source_reader_export_candidates":["export_navision_backend_records","get_navision_backend_snapshot","get_navision_reconciliation_report"],"intentionally_unmapped_historical_candidates":["pdc_admin_complete_vehicle_delete"]};
const alias = native => ('k135_' + native).length <= 63 ? 'k135_' + native : 'k135_' + native.slice(0, 44) + '_' + crypto.createHash('sha256').update(native).digest('hex').slice(0, 12);
const map = { centre: '135', project_ref: 'cdsmnqxtyyoeoznmbidd', url: transport.PROJECT_URL, ready: true, context_rpc: 'k135_get_native_engine_context', rpc: Object.fromEntries(required.native_rpc_candidates.map(name => [name, alias(name)])), tables: Object.fromEntries([...required.native_rest_relation_candidates, ...required.additional_dynamic_relations].map(name => [name, alias(name)])), realtime: { pdc_user_roles: { schema: 'karratha135_pdc', table: 'pdc_user_roles' }, workshop_station_revision: { schema: 'karratha135_pdc', table: 'workshop_station_revision' } }, buckets: { 'pdc-qc-evidence-staging': 'karratha135-qc-evidence-staging' } };
function fixture(config = map) {
  const calls = [];
  const instance = transport.create({ map: config, pageUrl: 'https://example.test/karratha/', assets: ['deployment-manifest.json', 'vendor/pdfjs/pdf.worker.min.js'], fetch: async (url, options) => { calls.push({ url: typeof url === 'string' ? url : url.url, options }); return new Response('{}', { status: 200 }); } });
  return { instance, calls };
}
test('every inventoried native endpoint is mapped or explicitly excluded', () => {
  const f = fixture();
  for (const name of required.native_rpc_candidates) {
    const routed = f.instance.route(transport.PROJECT_URL + '/rest/v1/rpc/' + name, 'POST');
    assert.equal(new URL(routed.url).pathname, '/rest/v1/rpc/' + map.rpc[name]);
    assert.ok(map.rpc[name].startsWith('k135_'));
  }
  for (const name of required.excluded_central_source_rpc_candidates) assert.throws(() => f.instance.route(transport.PROJECT_URL + '/rest/v1/rpc/' + name, 'POST'), /not enabled/);
  assert.equal(f.calls.length, 0);
});
test('unknown RPC/table/function/bucket and foreign origins fail before dispatch', async () => {
  const f = fixture();
  for (const [url, method] of [
    ['/rest/v1/rpc/save_unknown', 'POST'], ['/rest/v1/unknown_table', 'GET'], ['/functions/v1/notify', 'POST'], ['/storage/v1/object/pdc-qc-photos/x.jpg', 'POST'], ['/rest/v1/rpc/save_work?x=1', 'GET'], ['/rest/v1/rpc/set_pdc_vehicle_work_states%2Funsafe', 'POST']
  ]) await assert.rejects(f.instance.fetch(transport.PROJECT_URL + url, { method, body: '{}' }));
  await assert.rejects(f.instance.fetch('https://other.supabase.co/rest/v1/rpc/start_workshop_work', { method: 'POST', body: '{}' }));
  assert.equal(f.calls.length, 0);
});
test('table GET maps own relation; direct writes and embedded relationships fail', async () => {
  const f = fixture();
  await f.instance.fetch(transport.PROJECT_URL + '/rest/v1/vehicle_parts_updates?select=parts_required,parts_received&vehicle_id=eq.local-uuid');
  assert.match(f.calls[0].url, /\/rest\/v1\/k135_vehicle_parts_updates\?/);
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/rest/v1/vehicles', { method: 'PATCH', body: '{}' }));
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/rest/v1/vehicles?select=id,public_table(id)'));
  assert.equal(f.calls.length, 1);
});
test('native RPC payload preserves identity/version/idempotency and maps photo bucket only', async () => {
  const f = fixture();
  const payload = { p_vehicle_id: 'own-uuid', p_expected_vehicle_version: 3, p_bucket_id: 'pdc-qc-evidence-staging', p_storage_path: 'qc-finalization/own-user/own-uuid/receipt.jpg', p_idempotency_key: 'same-nonce' };
  await f.instance.fetch(transport.PROJECT_URL + '/rest/v1/rpc/record_pdc_qc_photo_evidence_399', { method: 'POST', body: JSON.stringify(payload), headers: { Authorization: 'Bearer own-token', 'Accept-Profile': 'public' } });
  assert.deepEqual(JSON.parse(f.calls[0].options.body), { ...payload, p_bucket_id: 'karratha135-qc-evidence-staging' });
  assert.equal(f.calls[0].options.redirect, 'error');
  assert.equal(f.calls[0].options.headers.get('Authorization'), 'Bearer own-token');
  assert.equal(f.calls[0].options.headers.get('Accept-Profile'), 'public');
  assert.equal(f.calls[0].options.headers.get('Content-Profile'), 'public');
});
test('raw photo POST/authenticated GET map own bucket and reject traversal/double encoding', async () => {
  const f = fixture();
  await f.instance.fetch(transport.PROJECT_URL + '/storage/v1/object/pdc-qc-evidence-staging/' + encodeURIComponent('qc-finalization/own-user/own-uuid/file.jpg'), { method: 'POST', body: new Blob(['image']) });
  assert.match(f.calls[0].url, /\/object\/karratha135-qc-evidence-staging\//);
  await f.instance.fetch(transport.PROJECT_URL + '/storage/v1/object/authenticated/karratha135-qc-evidence-staging/qc-finalization/own-user/file.jpg');
  assert.match(f.calls[1].url, /\/object\/authenticated\/karratha135-qc-evidence-staging\//);
  for (const tail of ['qc-finalization%2F..%2Foutside.jpg', 'qc%252Foutside.jpg', 'qc%5Coutside.jpg']) await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/storage/v1/object/pdc-qc-evidence-staging/' + tail, { method: 'POST', body: new Blob(['image']) }));
  assert.equal(f.calls.length, 2);
});
test('SDK constructor cannot override own Auth namespace or protected fetch', () => {
  const f = fixture(); let captured;
  const raw = { auth: {}, channel() {} };
  f.instance.wrapFactory((url, key, options) => { captured = { url, key, options }; return raw; })(transport.PROJECT_URL, 'publishable', { auth: { storageKey: 'sb-shared-auth-token' }, global: { fetch: () => 'unsafe' } });
  assert.equal(captured.options.auth.storageKey, 'karratha-pdc-auth-v1');
  assert.equal(captured.options.global.fetch, f.instance.fetch);
});
test('SDK signout always local; shared signup and administrator directory blocked', async () => {
  const f = fixture(); const outs = [];
  const wrapped = f.instance.wrapClient({ auth: { signOut: async options => { outs.push(options); return {}; }, signUp: async () => assert.fail('Native signup must not run') } });
  await wrapped.auth.signOut({ scope: 'global' });
  assert.equal(outs[0].scope, 'local');
  assert.match((await wrapped.auth.signUp({ email: 'known@example.test' })).error.message, /existing account/);
  assert.throws(() => wrapped.auth.admin);
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/auth/v1/logout?scope=global', { method: 'POST' }));
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/auth/v1/signup', { method: 'POST' }));
});
test('realtime changes own tables, owns topic and removes original channel', () => {
  const f = fixture(); const registrations = []; const removed = []; let topic;
  const channel = { on(type, spec) { registrations.push({ type, spec }); return this; }, subscribe() { return this; } };
  const wrapped = f.instance.wrapClient({ auth: {}, channel(name) { topic = name; return channel; }, removeChannel(value) { removed.push(value); } });
  const ownChannel = wrapped.channel('pdc_user_roles_admin_view').on('postgres_changes', { event: '*', schema: 'public', table: 'pdc_user_roles', filter: 'email=eq.owner@example.test' }, () => {}).subscribe();
  assert.equal(topic, 'k135:pdc_user_roles_admin_view');
  assert.deepEqual(registrations[0].spec, { event: '*', schema: 'karratha135_pdc', table: 'pdc_user_roles', filter: 'email=eq.owner@example.test' });
  wrapped.removeChannel(ownChannel); assert.equal(removed[0], channel);
  assert.throws(() => wrapped.channel('bad').on('postgres_changes', { schema: 'public', table: 'vehicles' }, () => {}));
  assert.throws(() => wrapped.channel('bad').on('broadcast', { event: 'all' }, () => {}));
  assert.equal(registrations.length, 1);
});
test('uncommissioned map refuses even known actions and sign-in service calls', async () => {
  const f = fixture({ ...map, ready: false });
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/rest/v1/rpc/start_workshop_work', { method: 'POST', body: '{}' }), /waiting/);
  await assert.rejects(f.instance.fetch(transport.PROJECT_URL + '/auth/v1/token?grant_type=password', { method: 'POST' }), /waiting/);
  assert.equal(f.calls.length, 0);
});
test('only declared local files within the own entrypoint may be fetched', async () => {
  const f = fixture();
  await f.instance.fetch('deployment-manifest.json?fresh=1');
  assert.equal(f.calls[0].url, 'https://example.test/karratha/deployment-manifest.json?fresh=1');
  await assert.rejects(f.instance.fetch('../deployment-manifest.json'));
  await assert.rejects(f.instance.fetch('/pdc-control-board-staging/app.js'));
  await assert.rejects(f.instance.fetch('unreviewed.json'));
  assert.equal(f.calls.length, 1);
});
test('configuration rejects PMB aliases, duplicate aliases and project drift', () => {
  assert.throws(() => fixture({ ...map, project_ref: 'production' }));
  assert.throws(() => fixture({ ...map, rpc: { start_workshop_work: 'start_workshop_work' } }));
  assert.throws(() => fixture({ ...map, rpc: { one: 'k135_same', two: 'k135_same' } }));
  assert.throws(() => fixture({ ...map, buckets: { 'pdc-qc-evidence-staging': 'pdc-qc-evidence-staging' } }));
  assert.throws(() => fixture({ ...map, realtime: { vehicles: { schema: 'public', table: 'vehicles' } } }));
});
test('Fetch Request objects preserve headers/signal and use mapped destination', async () => {
  const f = fixture();
  const request = new Request(transport.PROJECT_URL + '/rest/v1/rpc/start_workshop_work', { method: 'POST', body: '{"p_expected_version":4}', headers: { Authorization: 'Bearer own-token' } });
  await f.instance.fetch(request);
  assert.equal(new URL(f.calls[0].url).pathname, '/rest/v1/rpc/k135_start_workshop_work');
  assert.equal(f.calls[0].options.headers.get('Authorization'), 'Bearer own-token');
  assert.equal(JSON.parse(f.calls[0].options.body).p_expected_version, 4);
});
test('a delayed private response cannot survive account or authority replacement', async () => {
  let epoch = 1; let resolve;
  const instance = transport.create({ map, pageUrl: 'https://example.test/karratha/', assets: [], getEpoch: () => epoch, fetch: () => new Promise(done => { resolve = done; }) });
  const pending = instance.fetch(transport.PROJECT_URL + '/rest/v1/rpc/get_workshop_snapshot', { method: 'POST', body: '{}' });
  epoch++; resolve(new Response('{"vehicles":[{"client":"old private customer"}]}'));
  await assert.rejects(pending, /access changed/);
});
test('private JSON body arriving after logout is discarded even after headers arrived', async () => {
  let epoch = 1; let stream;
  const body = new ReadableStream({ start(controller) { stream = controller; } });
  const instance = transport.create({ map, pageUrl: 'https://example.test/karratha/', assets: [], getEpoch: () => epoch, fetch: async () => new Response(body) });
  const response = await instance.fetch(transport.PROJECT_URL + '/rest/v1/rpc/get_workshop_snapshot', { method: 'POST', body: '{}' });
  const parsed = response.json(); epoch++;
  stream.enqueue(new TextEncoder().encode('{"customer":"old private customer"}')); stream.close();
  await assert.rejects(parsed, /access changed/);
});

test('an action whose body is still being read is never dispatched after logout',async()=>{
 let epoch=1,stream,called=false;
 const body=new ReadableStream({start(controller){stream=controller;}});
 const instance=transport.create({map,pageUrl:'https://example.test/karratha/',assets:[],getEpoch:()=>epoch,fetch:async()=>{called=true;return new Response('{}');}});
 const request=new Request(transport.PROJECT_URL+'/rest/v1/rpc/start_workshop_work',{method:'POST',body,duplex:'half'});
 const pending=instance.fetch(request);epoch++;stream.enqueue(new TextEncoder().encode('{}'));stream.close();
 await assert.rejects(pending,/not sent/);assert.equal(called,false);
});

test('late live callbacks are dropped after authority changes', () => {
  let epoch=1, callback, delivered=0;
  const channel={on(_type,_spec,handler){callback=handler;return this;}};
  const instance=transport.create({map,pageUrl:'https://example.test/karratha/',assets:[],getEpoch:()=>epoch,fetch:async()=>new Response('{}')});
  instance.wrapClient({auth:{},channel:()=>channel}).channel('own').on('postgres_changes',{schema:'public',table:'pdc_user_roles'},()=>delivered++);
  callback({});assert.equal(delivered,1);epoch++;callback({});assert.equal(delivered,1);
});

test('the sign-in role monitor survives first proof but not logout or role replacement', () => {
  const listeners={},callbacks=[];let delivered=0;
  const channel=()=>({on(_type,_spec,callback){callbacks.push(callback);return this;}});
  const root={location:{href:'https://example.test/karratha/'},fetch:async()=>new Response('{}'),supabase:{createClient:()=>({auth:{},channel})},addEventListener:(type,handler)=>listeners[type]=handler};
  transport.install({root,map,assets:[]});
  listeners['pdc-auth-locked']();
  root.supabase.createClient(transport.PROJECT_URL,'key').channel('role').on('postgres_changes',{schema:'public',table:'pdc_user_roles'},()=>delivered++);
  root.PDC_AUTH_CONTEXT={userId:'own',role:'operator',membership_version:'1',centreCode:'135'};listeners['pdc-auth-ready']();callbacks[0]({});assert.equal(delivered,1);
  root.PDC_AUTH_CONTEXT={...root.PDC_AUTH_CONTEXT,membership_version:'2'};listeners['pdc-auth-ready']();callbacks[0]({});assert.equal(delivered,1);
  listeners['pdc-auth-locked']();callbacks[0]({});assert.equal(delivered,1);
});
