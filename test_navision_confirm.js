const fs = require('fs');
const path = require('path');
const vm = require('vm');
let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  renderAll = function(){};
  populateFilters = function(){};
  renderNavisionSummary = function(){};
  updateNavisionControlStats = function(){};
  updateNavisionImportButton = function(){};
  updateNavisionSidebarMeta = function(){};
  renderKpis = function(){};
  renderVehicleTable = function(){};
  renderKanban = function(){};
  renderCustomers = function(){};
  function assert(condition, message) { if (!condition) throw new Error(message); }
  function row(values) { return values.join('\t'); }
  const header = row(['Order','Batch','Production Month','Model Description','Suffix Description','Trim Description','Colour Description','Customer Surname','Dealer Comments','Sub Location Description','ETA At Dealer/BB','ETA At Kewdale Yard','ETA Date','Port/Plant ETA Date','JITA PreOrder','Tray Fitment Ordered','Tray Fitment Complete','WMI','VDS Number','Frame']);
  const incomingChanged = row(['ORD1','12345678','202608','Hilux','SR','Fabric','White','MERCER','New dealer note','In Transit to WA','20/08/2026','18/08/2026','17/08/2026','16/08/2026','JITA-2471','Yes','Yes','MR0','BA3FS2','01361094']);
  const parsed = parseNavisionInput(header + '\n' + incomingChanged);
  assert(parsed.vehicles.length === 1, 'Navision parser should read one vehicle');
  assert(parsed.vehicles[0].etaAtDealer === '18/08/2026', 'Dashboard ETA should use ETA At Kewdale Yard, not ETA At Dealer/BB');
  assert(parsed.vehicles[0].navisionEtaAtDealerBB === '20/08/2026', 'ETA At Dealer/BB should still be stored for reference');
  assert(parsed.vehicles[0].navisionEtaDate === '17/08/2026', 'ETA Date should be stored for reference');
  saveJson(EDITS_KEY, { '12345678': { buildPoRaised: true, tintRaised: true, internalStatus: 'Manual salesperson task' } });
  app.data = buildVehicleData();
  const plan = buildNavisionImportPlan(parsed);
  assert(plan.requiresConfirmation === true, 'Existing vehicle changes should require confirmation');
  assert(plan.updated.length === 1, 'One existing vehicle should be in the pending update list');
  assert(plan.updated[0].changes.some(change => change.key === 'toyotaStatus'), 'Pending review should show Toyota Status change');
  assert(app.data.find(v => v.stock === '12345678').toyotaStatus === 'Waiting PD1', 'Tracker must not change before confirmation');
  applyNavisionImportPlan(plan);
  app.data = buildVehicleData();
  const updated = app.data.find(v => v.stock === '12345678');
  assert(updated.toyotaStatus === 'In Transit to WA', 'Confirmed import should apply Navision Toyota Status');
  assert(updated.etaAtDealer === '18/08/2026', 'Confirmed import should apply Kewdale ETA, not Dealer/BB ETA');
  assert(updated.navisionEtaAtDealerBB === '20/08/2026', 'Confirmed import should preserve Dealer/BB ETA for popup reference only');
  assert(updated.navisionEtaDate === '17/08/2026', 'Confirmed import should preserve ETA Date for popup reference');
  assert(updated.prodMth === '08/26', 'Confirmed import should apply P/Month');
  assert(updated.jitaPartsOrdered === 'Yes' && updated.jitQty === 'JITA-2471' && updated.navisionJitaNumberAuthority === NAVISION_JITA_NUMBER_AUTHORITY, 'Confirmed import should retain the authoritative provenance-bound Navision JITA number');
  const importedJitaBeforeBlockedEdit = updated.jitQty;
  assert(saveVehicleEdits(vehicleKey(updated), { jitQty: 'JITA-FAKE-999', navisionJitaNumberAuthority: NAVISION_JITA_NUMBER_AUTHORITY }) === false, 'Generic vehicle edits must reject every attempted Navision JITA authority-only update');
  assert(updated.jitQty === importedJitaBeforeBlockedEdit, 'A rejected generic edit must not change the imported JITA number');
  assert(updated.navisionDealerComments === 'New dealer note', 'Confirmed import should apply Navision Notes');
  assert(updated.trayOrdered === true, 'Confirmed import should apply Tray Fitment Ordered');
  assert(updated.trayFitmentComplete === true, 'Confirmed import should apply Tray Fitment Complete');
  assert(plan.updated[0].changes.some(change => change.key === 'trayFitmentComplete'), 'Pending review should show Tray Fitment Complete change');
  assert(updated.buildPoRaised === true && updated.tintRaised === true, 'Protected PMB PO and Tint should survive Navision update');
  assert(updated.internalStatus === 'Manual salesperson task', 'Manual Task should survive Navision update');

  // If Kewdale is blank, leave dashboard ETA blank. Do not use ETA Date, Port/Plant or Dealer/BB.
  localStorage.clear();
  app.data = buildVehicleData();
  const incomingEtaDateOnly = row(['ORD1','12345678','202608','Hilux','SR','Fabric','White','MERCER','ETA Date only','In Transit to WA','30/08/2026','','22/08/2026','21/08/2026','Yes','No','No','MR0','BA3FS2','01361094']);
  const parsedEtaDate = parseNavisionInput(header + '\n' + incomingEtaDateOnly);
  assert(parsedEtaDate.vehicles[0].etaAtDealer === '', 'When Kewdale is blank, dashboard ETA should stay blank and ignore ETA Date, Port/Plant and Dealer/BB');
  assert(parsedEtaDate.vehicles[0].jitaPartsOrdered === 'Unknown' && parsedEtaDate.vehicles[0].jitQty === '' && parsedEtaDate.vehicles[0].navisionJitaNumberAuthority === NAVISION_JITA_NUMBER_AUTHORITY, 'A present Navision JITA column with a Yes-only value must retain import provenance but no JITA number');
  const authoritativeJitaVehicle = { source: 'Navision', navisionJitaNumberAuthority: NAVISION_JITA_NUMBER_AUTHORITY, jitQty: 'JITA-77881', jitaPartsOrdered: 'No' };
  assert(vehicleNavisionJitaNumber({ jitaPartsOrdered: 'Yes' }) === '', 'A stale/manual local JITA boolean must never create a Parts-screen tick');
  assert(vehicleNavisionJitaNumber({ source: 'Manual', navisionJitaNumberAuthority: NAVISION_JITA_NUMBER_AUTHORITY, jitQty: 'JITA-FAKE-123' }) === '', 'A manually supplied numeric JITA value must remain blank even if an authority marker is forged');
  assert(vehicleNavisionJitaNumber({ source: 'Navision', jitQty: 'JITA-STALE-123' }) === '', 'A stale numeric value without validated import provenance must remain blank');
  assert(vehicleNavisionJitaNumber(authoritativeJitaVehicle) === 'JITA-77881', 'A provenance-bound imported Navision JITA number must create the read-only Parts tick');
  assert(jitaDisplay({ jitaPartsOrdered: 'Yes' }) === '', 'The main Control Board display must ignore a stale local JITA yes flag');
  assert(!jitaIndicator({ jitaPartsOrdered: 'Yes' }).includes('✓'), 'A stale local JITA yes flag must not create a main-table tick');
  assert(!jitaIndicator({ jitaPartsOrdered: 'No' }).includes('×'), 'The main table must not render a manual JITA cross');
  assert(jitaIndicator(authoritativeJitaVehicle).includes('✓'), 'An imported Navision JITA number must create the main-table tick even when a stale flag disagrees');
  assert(jitaIndicator(authoritativeJitaVehicle).includes('Navision JITA number JITA-77881'), 'The main-table tick must expose the authoritative Navision JITA number');
  assert(sortValue({ jitaPartsOrdered: 'Yes' }, 'jita') === 'Unknown', 'JITA sorting must ignore stale local booleans');
  assert(sortValue(authoritativeJitaVehicle, 'jita') === 'Yes', 'JITA sorting must use only a provenance-bound imported Navision number');
  const restoredAuthority = normalizedBackupStorage({ storage: {
    [EDITS_KEY]: JSON.stringify({ '12345678': { comments: 'keep', source: 'Navision', jitQty: 'JITA-FORGED-RESTORE', navisionJitaNumber: 'JITA-FORGED-RESTORE', navisionJitaNumberAuthority: NAVISION_JITA_NUMBER_AUTHORITY, jitaPartsOrdered: 'Yes' } }),
    [ADDED_KEY]: JSON.stringify([{ id: 'restored-added', source: 'Navision', jitQty: 'JITA-FORGED-ADDED', navisionJitaNumberAuthority: NAVISION_JITA_NUMBER_AUTHORITY }]),
  } });
  const restoredEditRow = JSON.parse(restoredAuthority[EDITS_KEY])['12345678'];
  const restoredAddedRow = JSON.parse(restoredAuthority[ADDED_KEY])[0];
  assert(restoredEditRow.comments === 'keep' && restoredEditRow.jitQty === undefined && restoredEditRow.navisionJitaNumberAuthority === undefined, 'Backup restore must preserve ordinary edits while stripping forged JITA authority from persisted edits');
  assert(restoredAddedRow.jitQty === undefined && restoredAddedRow.navisionJitaNumberAuthority === undefined, 'Backup restore must strip forged JITA authority from restored added vehicles');

  // Selected-only apply should skip unselected existing updates but still add new vehicles.
  localStorage.clear();
  app.data = buildVehicleData();
  const incomingNew = row(['ORD2','87654321','202609','RAV4','GXL','','Blue','NEW CUSTOMER','','Planned for Production','29/09/2026','21/09/2026','','','No','No','No','JTM','AAAAAA','12345678']);
  const parsed2 = parseNavisionInput(header + '\n' + incomingChanged + '\n' + incomingNew);
  const plan2 = buildNavisionImportPlan(parsed2);
  assert(plan2.requiresConfirmation === true, 'Mixed existing/new import should still require confirmation');
  applyNavisionImportPlan(plan2, new Set());
  app.data = buildVehicleData();
  assert(app.data.find(v => v.stock === '12345678').toyotaStatus === 'Waiting PD1', 'Unselected existing update should not apply');
  assert(app.data.some(v => v.stock === '87654321'), 'New vehicle should still be added after selected-only confirmation');

  // PDC work/job-file mode should accept rows with a Body Builder signal and skip plain Navision rows.
  const pmbOnlyHeader = row(['Order','Batch','Production Month','Model Description','Body Builder','Tray Fitment Ordered']);
  const pmbOnlyMatch = row(['ORD3','33333333','202610','Landcruiser','2','No']);
  const pmbOnlySkip = row(['ORD4','44444444','202610','Corolla','','No']);
  const parsedPmbOnly = parseNavisionInput(pmbOnlyHeader + '\n' + pmbOnlyMatch + '\n' + pmbOnlySkip, { pmbOnly: true });
  assert(parsedPmbOnly.vehicles.length === 1, 'Work/job-file mode should keep only rows with PDC work signals');
  assert(parsedPmbOnly.vehicles[0].stock === '33333333' && parsedPmbOnly.vehicles[0].pdcSheetVisible === true, 'Work/job-file mode should promote the body-builder row');
  assert(parsedPmbOnly.warnings.some(warning => warning.includes('44444444') && warning.includes('skipped')), 'Work/job-file mode should report skipped rows without work signals');

  // Normal Navision never promotes Body Builder / consignment statuses; work/job-file mode may do so.
  localStorage.clear();
  app.data = buildVehicleData();
  const bodyBuilderHeader = row(['Order','Batch','Production Month','Model Description','Sub Location Description']);
  const bodyBuilderRow = row(['ORD5','55555555','202610','Prado','Delivered - At Body Builder']);
  const consignmentRow = row(['ORD6','66666666','202610','Hilux','On Consignment']);
  const parsedBodyBuilder = parseNavisionInput(bodyBuilderHeader + '\n' + bodyBuilderRow + '\n' + consignmentRow);
  assert(parsedBodyBuilder.vehicles.length === 2, 'Body builder status rows should import');
  assert(parsedBodyBuilder.vehicles.every(vehicle => vehicle.pdcSheetVisible === false && !vehicle.pdcLocation), 'Normal Navision Body Builder/consignment rows should stay in Back End Data only');
  const parsedBodyBuilderWork = parseNavisionInput(bodyBuilderHeader + '\n' + bodyBuilderRow + '\n' + consignmentRow, { pmbOnly: true });
  assert(parsedBodyBuilderWork.vehicles.every(vehicle => vehicle.pdcSheetVisible === true && vehicle.pdcLocation === 'PMB'), 'Work/job-file mode may promote Body Builder/consignment rows to PMB');
  assert(parsedBodyBuilderWork.vehicles.every(vehicle => vehicle.pmbStage === ''), 'First PMB landing should stay Unallocated');

  // Report title lines, header aliases and order-only vehicles should import cleanly.
  const titledCsv = 'Navision Vehicle Report\nGenerated 13/07/2026\nToyota Order,Stock No.,Model Desc.,ETA To Kewdale\nORD7,77770000,Camry,01/08/2026';
  const parsedTitledCsv = parseNavisionInput(titledCsv);
  assert(parsedTitledCsv.vehicles.length === 1 && parsedTitledCsv.vehicles[0].stock === '77770000', 'CSV headings below report title lines should be detected');
  assert(parsedTitledCsv.warnings.some(warning => warning.includes('headings were detected on row 3')), 'Import should explain that report title rows were ignored');
  const orderOnly = parseNavisionInput(row(['Toyota Order','Model Description']) + '\n' + row(['ORDER-ONLY-1','HiAce']));
  assert(orderOnly.vehicles.length === 1 && orderOnly.vehicles[0].order === 'ORDER-ONLY-1', 'An order-only Navision vehicle should remain available in Back End Data until a stock number arrives');

  // Navision browser copy uses U+2002 EN SPACE separators rather than tabs.
  const enSpace = '\u2002';
  const expandTabs = line => {
    let column = 0;
    return line.split('').map(character => {
      if (character !== '\t') { column += 1; return character; }
      const spaces = 6 - (column % 6 || 0);
      column += spaces;
      return enSpace.repeat(spaces);
    }).join('');
  };
  const unicodeHeader = expandTabs(row(['Order','Batch','Production Month','Compliance Date','Model Description','Customer Surname','Sub Location Description','ETA At Kewdale Yard','JITA PreOrder']));
  const unicodeVehicle = expandTabs(row(['250038414','13056889','202607','','Prado 2.8L 48V Dsl Wgn 8AT','NINDILINGARRI CULTURAL HEALTH','Planned for Production','20/07/2026','2']));
  const parsedUnicodePaste = parseNavisionInput(unicodeHeader + '\n' + unicodeVehicle);
  assert(parsedUnicodePaste.vehicles.length === 1, 'Unicode EN SPACE separated Navision paste should import');
  assert(parsedUnicodePaste.vehicles[0].stock === '13056889' && parsedUnicodePaste.vehicles[0].order === '250038414', 'Unicode Navision paste should preserve Order and Batch columns');

  const locationRows = vehicleLocationBoardRows(
    [
      { id: 'local-match', stock: '10010010', order: 'ORD-MATCH', source: 'Manual', pdcSheetVisible: true, toyotaStatus: 'Old local status', pdcPartsStoppage: true },
      { id: 'local-only', stock: '10010011', source: 'Manual', pdcSheetVisible: true, toyotaStatus: 'Vehicle Yard Hold' },
    ],
    [
      { id: 'shared-match', stock_number: '10010010', toyota_order_number: 'ORD-MATCH', model: 'HiLux', colour: 'White', vehicle_status: 'In Transit to WA', eta_to_kewdale: '31/07/2026', is_current: true },
      { id: 'shared-only', dealer_code: '14450', stock_number: '10010012', toyota_order_number: 'ORD-SHARED', model: 'Prado', colour: 'Silver', vehicle_status: 'Planned for Production', eta_to_kewdale: '02/08/2026', is_current: true },
      { id: 'shared-duplicate', dealer_code: '14450', stock_number: '10010012', toyota_order_number: 'ORD-SHARED', model: 'Prado', colour: 'Silver', vehicle_status: 'Planned for Production', eta_to_kewdale: '02/08/2026', is_current: true },
      { id: 'shared-old', stock_number: '10010013', vehicle_status: 'Planned for Production', is_current: false },
    ],
  );
  assert(locationRows.length === 3, 'Locations must combine local operational rows with every current shared Navision row, deduplicate matches and exclude rows missing from the latest upload');
  const matchedLocation = locationRows.find(vehicle => vehicle.stock === '10010010');
  assert(matchedLocation.toyotaStatus === 'In Transit to WA' && matchedLocation.etaAtDealer === '31/07/2026', 'Current shared Navision status and ETA must override stale browser-local Navision display fields');
  assert(matchedLocation.pdcPartsStoppage === true && matchedLocation.__sharedNavisionReadOnly === false, 'A matched operational vehicle must preserve local workflow fields and controls');
  const sharedOnlyLocation = locationRows.find(vehicle => vehicle.stock === '10010012');
  assert(sharedOnlyLocation && sharedOnlyLocation.__sharedNavisionReadOnly === true, 'A current Navision-only vehicle must appear in Locations as read-only');
  const sharedOnlyHtml = incomingVehicleDetailRow(sharedOnlyLocation, incomingBucketForVehicle(sharedOnlyLocation));
  assert(sharedOnlyHtml.includes('Shared Navision · Read only'), 'Navision-only Locations rows must be visibly read-only');
  for (const forbiddenAction of ['data-open-stock=', 'data-yh-transfer-pmb=', 'data-transfer-rft-stock=', 'data-rft-collected-key=', 'data-label-vehicle=', 'data-select-stock=']) {
    assert(!sharedOnlyHtml.includes(forbiddenAction), 'Navision-only Locations row must not expose browser-local action ' + forbiddenAction);
  }

  const ambiguousLocationRows = vehicleLocationBoardRows(
    [{ id: 'local-ambiguous', stock: 'STOCK-A', order: 'ORDER-B', toyotaStatus: 'Local review required' }],
    [
      { id: 'shared-a', stock_number: 'STOCK-A', toyota_order_number: 'ORDER-A', vehicle_status: 'Vehicle Yard Hold', is_current: true },
      { id: 'shared-b', stock_number: 'STOCK-B', toyota_order_number: 'ORDER-B', vehicle_status: 'In Transit to WA', is_current: true },
    ],
  );
  assert(ambiguousLocationRows.length === 3 && ambiguousLocationRows[0].toyotaStatus === 'Local review required' && ambiguousLocationRows[0].__sharedNavisionReadOnly !== false, 'Conflicting stock/order matches must fail closed without overlaying either shared record onto the local operational vehicle');
  assert(ambiguousLocationRows.filter(vehicle => vehicle.__sharedNavisionReadOnly === true).length === 2, 'Conflicting current shared Navision records must remain separately visible for review');
  assert(ambiguousLocationRows[0].__locationIdentityReadOnly === true, 'A conflicting local identity must be visibly read-only until reviewed');

  const blankAuthorityRows = vehicleLocationBoardRows(
    [{ id: 'blank-local', stock: 'BLANK-1', order: 'BLANK-ORDER', toyotaStatus: 'Stale status', etaAtDealer: '01/01/2020' }],
    [{ id: 'blank-shared', dealer_code: '14450', stock_number: 'BLANK-1', toyota_order_number: 'BLANK-ORDER', vehicle_status: '', eta_to_kewdale: '', is_current: true }],
  );
  assert(blankAuthorityRows.length === 1 && blankAuthorityRows[0].toyotaStatus === '' && blankAuthorityRows[0].etaAtDealer === '', 'Authoritative shared blanks must clear stale browser-local status and ETA values');

  const duplicateLocalRows = vehicleLocationBoardRows(
    [
      { id: 'dup-local-a', stock: 'ABC-1', order: 'ORD-1', toyotaStatus: 'STALE-A' },
      { id: 'dup-local-b', stock: 'ABC1', order: 'ORD1', toyotaStatus: 'STALE-B' },
    ],
    [{ id: 'dup-shared', dealer_code: '14450', stock_number: 'ABC1', toyota_order_number: 'ORD1', vehicle_status: 'In Transit to WA', eta_to_kewdale: '01/08/2026', is_current: true }],
  );
  assert(duplicateLocalRows.length === 2, 'Normalized duplicate operational identities must collapse to one local review row while retaining the unconsumed shared row for separate review');
  assert(duplicateLocalRows[0].toyotaStatus === 'STALE-A' && duplicateLocalRows[0].__locationIdentityReadOnly === true, 'A normalized local identity collision must not receive a shared overlay and must stay read-only');
  assert(duplicateLocalRows[1].__sharedNavisionReadOnly === true && duplicateLocalRows[1].toyotaStatus === 'In Transit to WA', 'The unconsumed shared identity must remain separately visible and read-only');
  const duplicateLocalHtml = incomingVehicleDetailRow(duplicateLocalRows[0], incomingBucketForVehicle(duplicateLocalRows[0]), { draggable: true, showDelete: true });
  for (const forbiddenAction of ['draggable="true"', 'data-open-stock=', 'data-label-vehicle=', 'data-select-stock=', 'data-incoming-delete=']) {
    assert(!duplicateLocalHtml.includes(forbiddenAction), 'Identity-conflict rows must not expose browser-local action ' + forbiddenAction);
  }

  const partialConflictRows = vehicleLocationBoardRows(
    [{ id: 'partial-local', stock: 'STOCK-1', order: 'LOCAL-ORDER', toyotaStatus: 'LOCAL-STATUS' }],
    [{ id: 'partial-shared', dealer_code: '14450', stock_number: 'STOCK-1', toyota_order_number: 'OTHER-ORDER', vehicle_status: 'Vehicle Yard Hold', is_current: true }],
  );
  assert(partialConflictRows.length === 2 && partialConflictRows[0].toyotaStatus === 'LOCAL-STATUS' && partialConflictRows[0].__locationIdentityReadOnly === true, 'One matching identifier plus one conflicting identifier must fail closed without overlay');

  const liveConflictVehicle = app.data[0];
  app.sharedNavisionVisibleRows = [{ id: 'live-conflict', dealer_code: '14450', stock_number: liveConflictVehicle.stock, toyota_order_number: 'CONFLICTING-ORDER', vehicle_status: 'Vehicle Yard Hold', is_current: true }];
  app.sharedNavisionLocationReadOnlyKeys = new Set();
  assert(saveVehicleEdits(vehicleKey(liveConflictVehicle), { comments: 'must-not-write' }, { render: false }) === false, 'Generic mutation paths must recompute and reject a newly conflicted shared identity even when the previous read-only cache was stale');
  app.selectedRows.add(vehicleKey(liveConflictVehicle));
  assert(selectedVehiclesForBulkEmail().length === 0 && app.selectedRows.size === 0, 'A previously selected row must be removed from bulk authority as soon as its shared identity becomes conflicted');
  app.sharedNavisionVisibleRows = [];
  app.sharedNavisionLocationReadOnlyKeys = new Set();
  const originalBulkTransfer = transferSelectedYhVehiclesToPmb;
  const originalLiveStatus = liveConflictVehicle.toyotaStatus;
  let mainBulkDelegateCalls = 0;
  transferSelectedYhVehiclesToPmb = async () => { mainBulkDelegateCalls += 1; };
  liveConflictVehicle.toyotaStatus = 'Vehicle Yard Hold';
  app.selectedRows.add(vehicleKey(liveConflictVehicle));
  transferSelectedMainYhVehiclesToPmb();
  assert(mainBulkDelegateCalls === 1, 'The visible main-board bulk YH to PMB action must delegate to the implemented guarded bulk transfer workflow');
  transferSelectedYhVehiclesToPmb = originalBulkTransfer;
  liveConflictVehicle.toyotaStatus = originalLiveStatus;
  app.selectedRows.clear();

  const reusedSharedRows = vehicleLocationBoardRows(
    [
      { id: 'reused-local-a', stock: 'DUP', toyotaStatus: 'LOCAL-A' },
      { id: 'reused-local-b', stock: 'DUP', order: 'ORDER-B', toyotaStatus: 'LOCAL-B' },
    ],
    [{ id: 'reused-shared', dealer_code: '14450', stock_number: 'DUP', vehicle_status: 'Vehicle Yard Hold', is_current: true }],
  );
  assert(reusedSharedRows.length === 3 && reusedSharedRows.slice(0, 2).every(vehicle => vehicle.__locationIdentityReadOnly === true), 'One shared record must never overlay more than one local operational identity');
  assert(reusedSharedRows[0].toyotaStatus === 'LOCAL-A' && reusedSharedRows[1].toyotaStatus === 'LOCAL-B', 'One-to-many identity ambiguity must preserve both local statuses without overlay');

  const dealerScopedRows = vehicleLocationBoardRows([], [
    { id: 'dealer-a', dealer_code: '14450', stock_number: 'DEALER-STOCK', toyota_order_number: 'DEALER-ORDER', vehicle_status: 'In Transit to WA', is_current: true },
    { id: 'dealer-b', dealer_code: '37047', stock_number: 'DEALER-STOCK', toyota_order_number: 'DEALER-ORDER', vehicle_status: 'In Transit to WA', is_current: true },
  ]);
  assert(dealerScopedRows.length === 2 && new Set(dealerScopedRows.map(vehicle => vehicle.__sharedNavisionDealerCode)).size === 2, 'Current records from different dealer scopes must remain separately visible');
  const crossDealerRows = vehicleLocationBoardRows([
    { id: 'local-dealer-a', stock: 'DEALER-STOCK-1', order: 'DEALER-ORDER-1', dealer_code: '14450', toyotaStatus: 'LOCAL-DEALER' },
  ], [
    { id: 'shared-dealer-b', dealer_code: '37047', stock_number: 'DEALER-STOCK-1', toyota_order_number: 'DEALER-ORDER-1', vehicle_status: 'REMOTE-DEALER', is_current: true },
  ]);
  assert(crossDealerRows.length === 2 && crossDealerRows[0].toyotaStatus === 'LOCAL-DEALER' && crossDealerRows[0].__locationIdentityReadOnly === true && crossDealerRows[1].__sharedNavisionReadOnly === true, 'A populated local dealer conflict must reject overlay and keep both local and shared records visible for review');

  const orderOnlyShared = sharedNavisionLocationVehicle({ id: 'order-only-shared', dealer_code: '14450', toyota_order_number: 'ORDER-ONLY-SHARED', vehicle_status: 'In Transit to WA', is_current: true });
  assert(incomingBucketForVehicle(orderOnlyShared) === 'transit', 'An order-only shared Navision vehicle must follow its authoritative status bucket');

  let realtimeStatus = null;
  let realtimeChange = null;
  let realtimeRemoved = 0;
  let snapshotCalls = 0;
  const fakeChannel = {
    on(_event, _filter, callback) { realtimeChange = callback; return this; },
    subscribe(callback) { realtimeStatus = callback; return this; },
  };
  app.navisionSharedBackendService = {
    visibleSnapshot() {
      snapshotCalls += 1;
      return Promise.resolve({ ok: true, data: { revision: 81, items: [], has_more: false } });
    },
  };
  window.PDC_AUTH_CONTEXT = { user: { id: 'approved-test-user' } };
  window.PDC_SUPABASE = {
    channel() { return fakeChannel; },
    removeChannel(channel) { if (channel === fakeChannel) realtimeRemoved += 1; },
  };
  app.sharedNavisionVisibleRealtime = null;
  app.sharedNavisionVisibleRealtimeState = 'idle';
  app.sharedNavisionVisibleState = 'loading';
  const pendingAuthorityHtml = incomingVehicleDetailRow(app.data[0], incomingBucketForVehicle(app.data[0]), { draggable: true, showDelete: true });
  for (const forbiddenAction of ['draggable="true"', 'data-open-stock=', 'data-label-vehicle=', 'data-select-stock=', 'data-incoming-delete=']) {
    assert(!pendingAuthorityHtml.includes(forbiddenAction), 'Local Locations actions must fail closed while shared identity authority is loading: ' + forbiddenAction);
  }
  assert(pendingAuthorityHtml.includes('Shared sync pending · Read only'), 'Rows must visibly explain their read-only state while shared identity authority is loading');
  const pendingVehicle = app.data[0];
  const pendingLocation = vehiclePdcLocation(pendingVehicle);
  const pendingDeletedCount = deletedVehicleRecords().length;
  assert(openVehicleModal(vehicleKey(pendingVehicle)) === false, 'Direct modal opening must fail closed while shared identity authority is loading');
  deleteIncomingVehicleFromMain(vehicleKey(pendingVehicle));
  removeVehicle(vehicleKey(pendingVehicle));
  transferYhVehicleToPmb(vehicleKey(pendingVehicle));
  assert(deletedVehicleRecords().length === pendingDeletedCount && vehiclePdcLocation(pendingVehicle) === pendingLocation, 'Direct delete and single-transfer handlers must not mutate while shared identity authority is loading');
  subscribeSharedNavisionVisibility();
  assert(typeof realtimeStatus === 'function' && typeof realtimeChange === 'function' && app.sharedNavisionVisibleRealtimeState === 'connecting', 'Shared Navision Realtime must retain lifecycle and revision callbacks while connecting');
  realtimeStatus('SUBSCRIBED');
  assert(app.sharedNavisionVisibleRealtimeState === 'subscribed' && snapshotCalls > 0, 'A healthy Realtime subscription must trigger post-subscribe snapshot reconciliation');
  assert(app.sharedNavisionVisibleRealtimeReconciled === false && !sharedNavisionLocationsStatusHtml().includes('synchronized across signed-in computers'), 'Realtime subscription alone must not claim synchronization before the reconciliation snapshot resolves');
  realtimeStatus('CHANNEL_ERROR');
  assert(app.sharedNavisionVisibleRealtime === null && app.sharedNavisionVisibleRealtimeState === 'reconnecting' && realtimeRemoved === 1 && app.sharedNavisionVisibleReconnectTimer && app.sharedNavisionVisibleReconnectTimer._idleTimeout === 1000, 'A Realtime channel failure must release ownership and schedule the first bounded reconnection');
  const generationAfterFailure = app.sharedNavisionVisibleRealtimeGeneration;
  realtimeStatus('SUBSCRIBED');
  assert(app.sharedNavisionVisibleRealtimeGeneration === generationAfterFailure && app.sharedNavisionVisibleRealtimeState === 'reconnecting', 'A stale channel callback must remain inert after ownership is released');
  clearSharedNavisionVisibilityReconnectTimer();
  subscribeSharedNavisionVisibility();
  realtimeStatus('SUBSCRIBED');
  realtimeStatus('CLOSED');
  assert(app.sharedNavisionVisibleReconnectTimer && app.sharedNavisionVisibleReconnectTimer._idleTimeout === 2000, 'A short-lived SUBSCRIBED/CLOSED flap must increase backoff instead of resetting to a one-second hot loop');
  clearSharedNavisionVisibilityReconnectTimer();
  app.sharedNavisionVisibleGeneration += 1;
  releaseSharedNavisionVisibilityChannel();
  delete window.PDC_AUTH_CONTEXT;

  // Missing cleanup on a full refresh should protect non-Toyota records.
  const toyotaExisting = { id: 'toyota-1', stock: '77777777', batch: '77777777', vehicle: 'Toyota Prado', toyotaVehicle: 'Prado', source: 'Navision' };
  const nissanExisting = { id: 'nissan-1', stock: '88888888', batch: '88888888', vehicle: 'Nissan Patrol', source: 'Manual' };
  const missingToyotaOnly = vehiclesMissingFromNavisionImport([toyotaExisting, nissanExisting], [], { fullRefresh: true });
  assert(missingToyotaOnly.length === 1 && missingToyotaOnly[0].stock === '77777777', 'Full Navision cleanup should only remove Toyota vehicles');

  console.log('Navision confirmation tests passed');
})();
`;
const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [{
    id: 'base-1', stock: '12345678', batch: '12345678', order: 'ORD1', client: 'MERCER', toyotaCustomer: 'MERCER', vehicle: 'Hilux SR', toyotaVehicle: 'Hilux', suffix: 'SR', trim: 'Fabric', colour: 'White', prodMth: '07/26', toyotaStatus: 'Waiting PD1', etaAtDealer: '19/08/2026', source: 'Navision', jitaPartsOrdered: 'No', trayOrdered: false
  }], toyotaMatches: {}, report: {} } },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; }
  },
  document: {
    querySelector: selector => {
      if (selector === '#navision-remove-missing') return { checked: false };
      if (selector === '#search') return { value: '' };
      if (selector === '#source-filter') return { value: '' };
      return null;
    },
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{add(){},remove(){},toggle(){}} })
  },
  navigator: {},
  FileReader: function(){},
  Blob: function(){},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
  Intl,
  Date,
  Map,
  Set,
  JSON,
  String,
  Number,
  Boolean,
  Array,
  Object,
  RegExp,
  Math,
  Error,
  Promise,
  setTimeout,
  clearTimeout,
  window_alerts: [],
};
context.window.alert = msg => context.window_alerts.push(msg);
context.window.confirm = () => true;
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
