'use strict';

/* Staging-only, read-only consumer of authenticated email vehicle imports. */
const PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
const PDC_EMAIL_VEHICLE_REVISION_TABLE = 'pdc_email_vehicle_revision';
const PDC_EMAIL_VEHICLE_SNAPSHOT_RPC = 'get_pdc_email_vehicle_location_snapshot';
const PDC_SUBLET_AUDIT_READ_RPC = 'get_pdc_sublet_audit_ledgers';
const PDC_WORKSHOP_HOURS_BATCH_RPC = 'save_vehicle_workshop_line_hours_batch_768';
const PDC_SUBLET_UPDATE_RPC = 'update_pdc_sublet_booking_field';
const PDC_SUBLET_CREATE_RPC = 'create_pdc_sublet_booking';
const PDC_SUBLET_BOOKING_UPDATE_RPC = 'update_pdc_sublet_booking';
const PDC_SUBLET_PROVIDER_UPDATE_RPC = 'update_pdc_sublet_booking_provider_399';
const PDC_SUBLET_RETURN_RPC = 'return_pdc_sublet_booking';
const PDC_PARTS_ETA_UPDATE_RPC = 'update_pdc_parts_eta';
const PDC_PARTS_ORDERED_RPC = 'mark_pdc_parts_ordered_377';
const PDC_PARTS_COMPLETE_RPC = 'mark_pdc_parts_received_authenticated_751';
const PDC_PARTS_STOPPAGE_RPC = 'set_pdc_parts_stoppage_376';
const PDC_VEHICLE_HISTORY_RPC = 'get_pdc_vehicle_provenance_history';
const PDC_SALES_PREPARATION_UPDATE_RPC = 'update_pdc_vehicle_sales_preparation';
const PDC_ACCEPTANCE_VEHICLE_CREATE_RPC = 'create_pdc_acceptance_vehicle_375';
const PDC_QC_OPERATION_COMPLETION_RPC = 'set_pdc_qc_operation_completion_379';
const PDC_QC_PHOTO_BUCKET = 'pdc-qc-evidence-staging';
const PDC_QC_PHOTO_RECEIPT_RPC = 'record_pdc_qc_photo_evidence_399';
const PDC_QC_FINALIZATION_RPC = 'finalize_pdc_qc_to_rft_399';
const PDC_QC_RETEST_PHOTO_RPC = 'record_pdc_qc_retest_photo_747';
const PDC_QC_RETEST_FINALIZATION_RPC = 'finalize_pdc_qc_retest_to_rft_747';
const PDC_SALESPERSON_ASSIGNMENT_RPC = 'assign_pdc_vehicle_salesperson_386';
const PDC_VEHICLE_DETAIL_FIELDS_RPC = 'update_pdc_vehicle_detail_fields_388';
const PDC_STOPPAGE_CLEAR_RPC = 'clear_vehicle_stoppage_422';
const PDC_PMB_STOPPAGE_RPC = 'set_pmb_stoppage_422';
const PDC_RFT_TRANSPORT_BOOK_RPC = 'book_rft_transport_412';
const PDC_RFT_TRANSPORT_COLLECT_RPC = 'collect_rft_transport_412';
const PDC_FINAL_QC_TO_RFT_RPC = 'finalize_pdc_qc_to_rft_700';
const PDC_FINAL_RFT_BOOK_RPC = 'book_rft_transport_700';
const PDC_FINAL_RFT_COLLECT_RPC = 'collect_rft_transport_700';
const PDC_DURABLE_RFT_BOOK_RPC = 'book_rft_transport_734';
const PDC_DURABLE_RFT_COLLECT_RPC = 'collect_rft_transport_734';
const PDC_DURABLE_RFT_EVIDENCE_RPC = 'read_pdc_rft_transport_evidence_734';
const PDC_RFT_CONFIRMATION_RPC = 'set_rft_confirmation_736';
const PDC_RFT_TRANSPORT_DRAFT_BOOK_RPC = 'book_rft_transport_email_draft_739';
const PDC_RFT_TRANSPORT_DRAFT_CONTEXT_RPC = 'read_rft_transport_booking_context_739';
const PDC_RFT_TRANSPORT_DRAFT_READ_RPC = 'read_rft_transport_draft_739';

const PDC_FINAL_LIFECYCLE_RECEIPTS_TABLE = 'pdc_final_pdc_lifecycle_receipts_700';
const PDC_PARTS_COMPLETE_SUCCESS_CODES = new Set(['parts_completed', 'replayed']);
const PDC_SUBLET_CANONICAL_ERRORS = new Set(['version_conflict', 'workshop_booking_conflict', 'sublet_away']);
const WORK_FIELDS = Object.freeze({
  bus4x4: ['pdcRequiresBus4x4', 'pdcCompleteBus4x4'], tint: ['pdcRequiresTint', 'pdcCompleteTint'], hoist: ['pdcRequiresHoist', 'pdcCompleteHoist'], fitting: ['pdcRequiresFitting', 'pdcCompleteFitting'], fabrication: ['pdcRequiresFabrication', 'pdcCompleteFabrication'], electrical: ['pdcRequiresElectrical', 'pdcCompleteElectrical'], tyre: ['pdcRequiresTyre', 'pdcCompleteTyre'], sublet: ['pdcRequiresSublet', 'pdcCompleteSublet'], pitinspection: ['pdcRequiresPitInspection', 'pdcCompletePitInspection'], parts: ['pdcRequiresParts', 'pdcCompleteParts'],
});
function projectRef(url = '') { const match = String(url || '').trim().match(/^https:\/\/([a-z0-9]+)\.supabase\.co(?:\/|$)/i); return match ? match[1].toLowerCase() : ''; }
function identity(value = '') { return String(value || '').trim().toUpperCase().replace(/[\s-]+/g, ''); }
function mapLifecycleHistory(row = {}) {
  const history = row.lifecycle_history && typeof row.lifecycle_history === 'object' ? row.lifecycle_history : {};
  const value = (key, fallback = '') => history[key] ?? row[key] ?? fallback;
  return {
    ...history,
    vehicleId: String(value('vehicle_id', row.id || '') || ''),
    stockNumber: String(value('stock_number', row.stock_number || '') || '').trim(),
    jobCardNumber: String(value('job_card_number', row.job_card_number || '') || '').trim(),
    firstReachedYardHoldAt: value('first_reached_yard_hold_at', ''),
    firstEnteredPmbAt: value('first_entered_pmb_at', ''),
    firstBecameRftAt: value('first_became_rft_at', ''),
    firstReachedYardHoldAtUtc: value('first_reached_yard_hold_at_utc', ''),
    firstEnteredPmbAtUtc: value('first_entered_pmb_at_utc', ''),
    firstBecameRftAtUtc: value('first_became_rft_at_utc', ''),
    firstReachedYardHoldAtBusiness: value('first_reached_yard_hold_at_business', ''),
    firstEnteredPmbAtBusiness: value('first_entered_pmb_at_business', ''),
    firstBecameRftAtBusiness: value('first_became_rft_at_business', ''),
    elapsedYardHoldToPmbSeconds: value('elapsed_yard_hold_to_pmb_seconds', null),
    elapsedPmbToRftSeconds: value('elapsed_pmb_to_rft_seconds', null),
    elapsedYardHoldToRftSeconds: value('elapsed_yard_hold_to_rft_seconds', null),
    elapsedYardHoldToPmbDays: value('elapsed_yard_hold_to_pmb_days', null),
    elapsedPmbToRftDays: value('elapsed_pmb_to_rft_days', null),
    elapsedYardHoldToRftDays: value('elapsed_yard_hold_to_rft_days', null),
    evidenceState: String(value('evidence_state', 'partial_or_unknown') || 'partial_or_unknown'),
    missingEvidence: Array.isArray(value('missing_evidence', [])) ? value('missing_evidence', []) : [],
  };
}
function subletResponseCode(body, status) {
  const direct = String(body?.code || body?.error || '').trim();
  if (PDC_SUBLET_CANONICAL_ERRORS.has(direct)) return direct;
  const message = String(body?.message || body?.details || '').trim();
  const match = message.match(/["']error["']\s*:\s*["']([a-z0-9_]+)["']/i);
  const extracted = String(match?.[1] || '').toLowerCase();
  return PDC_SUBLET_CANONICAL_ERRORS.has(extracted) ? extracted : (direct || `HTTP ${status}`);
}
function canonicalWorkKey(value = '') {
  const key = String(value || '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
  if (['pit', 'pitinspection', 'inspectionpit', 'pitinspect'].includes(key)) return 'pitinspection';
  if (['bus4x4', 'bus4wd', '4x4bus'].includes(key)) return 'bus4x4';
  if (['tyres', 'tire', 'tires'].includes(key)) return 'tyre';
  if (['part', 'partsrequired'].includes(key)) return 'parts';
  return key;
}
function mapServerVehicle(row = {}) {
  const lifecycleHistory = mapLifecycleHistory(row);
  const mapped = {
    id: String(row.permanent_vehicle_id || row.id || ''), permanentVehicleId: String(row.permanent_vehicle_id || ''), stock: String(row.stock_number || '').trim(), vin: String(row.vin || '').trim(), keyNumber: String(row.key_number || '').trim(), jobCardNumber: String(row.job_card_number || '').trim(), jobcard: String(row.job_card_number || '').trim(), client: String(row.customer_name || '').trim(), vehicle: String(row.vehicle_description || '').trim(), colour: String(row.navision_colour || '').trim(), salesperson: String(row.salesperson_reference || '').trim(), navisionSalespersonRaw: String(row.navision_salesperson_raw || '').trim(), registration: String(row.registration || '').trim(), rego: String(row.registration || '').trim(), navisionKewdaleEta: row.eta_to_kewdale || '', etaAtDealer: row.eta_to_kewdale || '', pdcLocation: String(row.current_location || 'Other').trim() || 'Other', dateToPmb: row.date_to_pmb || '', dateToRft: row.date_to_rft || '', deliveredToDealerDate: row.delivered_to_dealer_date || '', firstReachedYardHoldAt: lifecycleHistory.firstReachedYardHoldAt || '', firstEnteredPmbAt: lifecycleHistory.firstEnteredPmbAt || '', firstBecameRftAt: lifecycleHistory.firstBecameRftAt || '', lifecycleHistory, pdcQcComplete: Boolean(row.qc_completed_at), pdcQcCompleteAt: row.qc_completed_at || '', pdcQcCompleteBy: String(row.qc_completed_by || ''), rftTransferredAt: row.rft_transferred_at || '', pdcSheetVisible: row.visible_on_board !== false, source: String(row.source_system || 'Authenticated email auto-import'), sourceRecordId: String(row.source_record_id || ''), updatedAt: row.updated_at || '', __emailVehicleServerAuthoritative: true, __emailVehicleReadOnly: true, __emailVehicleId: String(row.id || ''), __emailVehicleVersion: Number(row.version || 0), __subletBookingVersion: Number(row.sublet_booking?.version || 0),
  };
  mapped.sourceLocationStatus = String(row.source_location_status || row.navision_location_status || row.navisionLocationStatus || '').trim();
  mapped.navisionLocationStatus = mapped.sourceLocationStatus;
  mapped.currentLocation = mapped.pdcLocation;
  mapped.navisionJitaIdentityVerified = row.navision_jita_identity_verified === true;
  mapped.navisionJitaNumberColumnPresent = row.navision_jita_column_present === true;
  mapped.navisionJitaNumberAuthority = mapped.navisionJitaIdentityVerified && mapped.navisionJitaNumberColumnPresent
    ? String(row.navision_jita_number_authority || '') : '';
  mapped.navisionJitaNumber = mapped.navisionJitaIdentityVerified && mapped.navisionJitaNumberColumnPresent
    ? String(row.navision_jita_number || '').trim() : '';
  mapped.jitQty = mapped.navisionJitaNumber;
  const salesPreparation = row.sales_preparation && typeof row.sales_preparation === 'object' ? row.sales_preparation : {};
  mapped.salespersonCode = String(row.salesperson_code || row.salesperson_reference || '').trim().toUpperCase();
  mapped.salespersonName = String(row.salesperson_name || row.salesperson_reference || '').trim();
  mapped.salespersonEmail = String(row.salesperson_email || '').trim().toLowerCase();
  mapped.salespersonManualOverride = row.salesperson_manual_override === true;
  mapped.salespersonManualOverrideAt = row.salesperson_manual_override_at || '';
  mapped.salespersonManualOverrideBy = String(row.salesperson_manual_override_by || '');
  mapped.rftTransportBookedAt = row.rft_transport_booked_at || '';
  mapped.rftTransportBookedBy = String(row.rft_transport_booked_by || '');
  mapped.rftCollectedAt = row.rft_collected_at || '';
  mapped.rftCollectedBy = String(row.rft_collected_by || '');
  mapped.lifecycleState = String(row.lifecycle_state || '');
  const finalLifecycle = row.pdc_lifecycle && typeof row.pdc_lifecycle === 'object' ? row.pdc_lifecycle : {};
  mapped.pdcLifecycleState = String(finalLifecycle.state || row.lifecycle_state || '').trim().toLowerCase();
  mapped.vehicleLifecycleState = mapped.pdcLifecycleState;
  mapped.vehicleCollectedState = mapped.pdcLifecycleState === 'collected' || row.current_location === 'Collected';
  mapped.vehicleDeliveredState = mapped.pdcLifecycleState === 'completed' || row.current_location === 'Completed';
  mapped.dealerTransitStartedAt = finalLifecycle.dealer_transit_started_at || row.dealer_transit_started_at || '';
  mapped.dealerTransitClosedAt = finalLifecycle.dealer_transit_closed_at || row.dealer_transit_closed_at || '';
  mapped.dealerTransitDurationSeconds = finalLifecycle.dealer_transit_duration_seconds ?? row.dealer_transit_duration_seconds ?? null;
  mapped.rftConfirmed = finalLifecycle.rft_confirmed === true || row.rft_confirmed === true || Boolean(row.rft_confirmed_at);
  mapped.rftConfirmedAt = finalLifecycle.rft_confirmed_at || row.rft_confirmed_at || '';
  mapped.rftConfirmedBy = String(finalLifecycle.rft_confirmed_by || row.rft_confirmed_by || '');
  mapped.rftTransportOutbox = row.rft_transport_outbox && typeof row.rft_transport_outbox === 'object' ? row.rft_transport_outbox : {};
  mapped.rftTransportEmailEvidence = row.rft_transport_outbox?.evidence && typeof row.rft_transport_outbox.evidence === 'object'
    ? row.rft_transport_outbox.evidence
    : row.rft_transport_email_evidence && typeof row.rft_transport_email_evidence === 'object'
      ? row.rft_transport_email_evidence
      : {};
  mapped.rftTransportDraft = row.rft_transport_draft && typeof row.rft_transport_draft === 'object' ? row.rft_transport_draft : {};
  mapped.pdcBlocked = Boolean(row.pmb_stoppage_started_at);
  mapped.pdcBlockReason = String(row.pmb_stoppage_reason || '');
  mapped.pdcBlockedAt = row.pmb_stoppage_started_at || '';
  mapped.pdcBlockedBy = String(row.pmb_stoppage_started_by || '');
  mapped.pdcBlockClearedAt = row.pmb_stoppage_cleared_at || '';
  mapped.pdcBlockClearedBy = row.pmb_stoppage_cleared_by || '';
  const qcFix = row.qc_fix && typeof row.qc_fix === 'object' ? row.qc_fix : {};
  mapped.customerName = String(row.customer_name || '').trim();
  mapped.pdcQcFixRequired = qcFix.status === 'Pending QC fixes' && String(row.current_location || '').toUpperCase() === 'PMB';
  mapped.pdcQcFixStatus = mapped.pdcQcFixRequired ? 'Pending QC fixes' : '';
  mapped.pdcQcFixReason = mapped.pdcQcFixRequired ? String(qcFix.reason || row.pmb_stoppage_reason || '').trim() : '';
  mapped.pdcQcFixReceiptId = mapped.pdcQcFixRequired ? String(qcFix.receipt_id || '').trim() : '';
  mapped.consultant = mapped.salespersonCode || mapped.salespersonName || mapped.salesperson || 'Unassigned';
  mapped.salesPreparation = {
    tintRaised: salesPreparation.tint_raised === true,
    buildPoRaised: salesPreparation.build_po_raised === true,
    buildComplete: salesPreparation.build_complete === true,
    trayOrdered: salesPreparation.tray_ordered === true,
    trayComplete: salesPreparation.tray_complete === true,
    updatedAt: salesPreparation.updated_at || '',
    updatedBy: String(salesPreparation.updated_by || ''),
  };
  mapped.salesWorkshopBookings = (Array.isArray(row.workshop_bookings) ? row.workshop_bookings : []).map(booking => ({
    bookingId: String(booking?.booking_id || ''),
    version: Number(booking?.version || 0),
    stageCode: String(booking?.stage_code || ''),
    stageName: String(booking?.stage_name || booking?.stage_code || ''),
    bayName: String(booking?.bay_name || ''),
    status: String(booking?.status || ''),
    scheduledStartAt: booking?.scheduled_start_at || '',
    scheduledEndAt: booking?.scheduled_end_at || '',
    actualStartAt: booking?.actual_start_at || '',
    actualEndAt: booking?.actual_end_at || '',
    stoppageReason: String(booking?.stoppage_reason || ''),
    updatedAt: booking?.updated_at || '',
  })).filter(booking => booking.bookingId);
  for (const [requiredKey, completeKey] of Object.values(WORK_FIELDS)) { mapped[requiredKey] = false; mapped[completeKey] = false; }
  for (const item of Array.isArray(row.work_items) ? row.work_items : []) {
    const fields = WORK_FIELDS[canonicalWorkKey(item?.work_key)]; if (!fields) continue;
    mapped[fields[0]] = item.required === true; mapped[fields[1]] = item.completed === true;
    if (item.completed_at) mapped[`${fields[1]}At`] = item.completed_at;
    if (item.completed_by) mapped[`${fields[1]}By`] = item.completed_by;
  }
  const allowedOperationKeys = new Set(['bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'pitinspection', 'parts']);
  mapped.pdcEmailOperationLines = (Array.isArray(row.operation_lines) ? row.operation_lines : []).slice(0, 50).map(item => ({
    operation_line_id: String(item?.operation_line_id || item?.source_line_id || '').trim().toLowerCase(),
    operation_no: String(item?.operation_no || '').trim().toUpperCase(),
    work_key: canonicalWorkKey(item?.work_key),
    job_card_number: String(item?.job_card_number || item?.jobCardNumber || '').trim().slice(0, 80),
    description: String(item?.description || '').trim().slice(0, 180),
    estimatedHours: item?.estimated_hours != null && item?.estimated_hours !== '' && Number.isFinite(Number(item.estimated_hours))
      ? Number(item.estimated_hours)
      : null,
    estimatedHoursSource: ['job_card', 'ai_estimate'].includes(String(item?.estimated_hours_source || '').trim().toLowerCase())
      ? String(item.estimated_hours_source).trim().toLowerCase()
      : null,
    source_uid: String(item?.source_uid || '').trim().slice(0, 100),
  })).filter(item => /^(?:OP(?:[1-9]|[1-9][0-9]{1,2})|PD[0-9]{3}-[A-F0-9]{8})$/.test(item.operation_no)
    && allowedOperationKeys.has(item.work_key) && item.description.length > 0);
  const qcProjection = Array.isArray(row.qc_operation_lines)
    ? row.qc_operation_lines
    : (Array.isArray(row.operation_lines) && row.operation_lines.some(item => String(item?.line_identity || '').trim()) ? row.operation_lines : null);
  const qcProjectionFieldPresent = Array.isArray(qcProjection);
  mapped.pdcQcOperationLinesProjectionPresent = qcProjectionFieldPresent;
  mapped.pdcQcOperationLines = (qcProjectionFieldPresent ? qcProjection : []).slice(0, 250).map(item => ({
    lineIdentity: String(item?.line_identity || ''), sourceKind: String(item?.source_kind || ''), sourceLineId: String(item?.source_line_id || ''),
    operationNo: String(item?.operation_no || ''), description: String(item?.description || '').trim(), jobCardNumber: String(item?.job_card_number || '').trim(),
    estimatedHours: item?.estimated_hours == null || item?.estimated_hours === '' ? null : Number(item.estimated_hours), stageCode: String(item?.stage_code || '').toUpperCase(),
    active: item?.active === true, completed: item?.completed === true, completedBy: String(item?.completed_by || ''), completedAt: item?.completed_at || '', lineVersion: Number(item?.line_version || 0),
  })).filter(item => /^(?:source|manual):[0-9a-f-]{36}$/.test(item.lineIdentity) && item.sourceLineId && item.description && item.active);
  const qcRetest = row.qc_retest && typeof row.qc_retest === 'object' ? row.qc_retest : {};
  mapped.pdcQcRetestCycleId = String(qcRetest.cycle_id || '').trim();
  mapped.pdcQcRetestFreshCycleOpen = qcRetest.fresh_cycle_open === true;
  mapped.pdcQcRetestFreshPhotoAccepted = qcRetest.fresh_photo_accepted === true;
  const partsUpdate = row.parts_update && typeof row.parts_update === 'object' ? row.parts_update : {};
  const qcFinalization = row.qc_finalization && typeof row.qc_finalization === 'object' ? row.qc_finalization : null;
  mapped.pdcQcFinalization = qcFinalization ? {
    receiptId: String(qcFinalization.receipt_id || ''), photoReceiptId: String(qcFinalization.photo_receipt_id || ''),
    actorId: String(qcFinalization.actor_id || ''), actorEmail: String(qcFinalization.actor_email || ''),
    signedOffAt: qcFinalization.signed_off_at || '', vehicleVersionBefore: Number(qcFinalization.vehicle_version_before || 0),
    vehicleVersionAfter: Number(qcFinalization.vehicle_version_after || 0), salesperson: qcFinalization.salesperson || null,
    completedItems: Array.isArray(qcFinalization.completed_items) ? qcFinalization.completed_items : [],
    outboxStatus: String(qcFinalization.outbox_status || ''), outboxNotificationId: String(qcFinalization.outbox_notification_id || ''),
    outboxSentAt: qcFinalization.outbox_sent_at || null, outboxDeliveredAt: qcFinalization.outbox_delivered_at || null,
  } : null;
  // Staging snapshot revisions have emitted Parts fields both inside the
  // parts_update projection and, for some retained rows, at the row root.
  // Prefer the nested authoritative projection when present, while accepting
  // the root aliases so a valid ETA/order state is not silently discarded.
  const projectedPartsValue = (field, fallback = null) => Object.prototype.hasOwnProperty.call(partsUpdate, field)
    ? partsUpdate[field]
    : (Object.prototype.hasOwnProperty.call(row, field) ? row[field] : fallback);
  if (row.parts_required != null || projectedPartsValue('parts_required') != null) {
    mapped.pdcRequiresParts = projectedPartsValue('parts_required', row.parts_required) === true;
  }
  mapped.pdcCompleteParts = row.parts_completed === true
    || row.parts_received === true
    || projectedPartsValue('parts_received', false) === true;
  mapped.pdcPartsOrdered = projectedPartsValue('parts_ordered', false) === true;
  mapped.pdcPartsStoppage = projectedPartsValue('parts_stoppage', false) === true;
  mapped.pdcPartsStoppageReason = String(projectedPartsValue('parts_stoppage_reason', '') || '');
  mapped.pdcPartsWorstEta = projectedPartsValue('worst_eta', '') || '';
  mapped.pdcPartsPreviousWorstEta = projectedPartsValue('previous_worst_eta', '') || '';
  mapped.pdcPartsWorstEtaUpdatedAt = projectedPartsValue('updated_at', '') || '';

  const canonicalBookings = (Array.isArray(row.sublet_bookings) ? row.sublet_bookings : []).map(booking => ({
    bookingId: String(booking?.booking_id || ''), vehicleId: String(booking?.vehicle_id || row.id || ''),
    vehicleVersion: Number(booking?.vehicle_version || row.version || 0), providerId: String(booking?.provider_id || ''),
    provider: String(booking?.provider_name || ''), providerEmail: String(booking?.provider_email || ''),
    outDate: booking?.out_date || '', expectedReturnDate: booking?.expected_return_date || '',
    status: ['active', 'returned', 'cancelled'].includes(String(booking?.status || '')) ? String(booking.status) : 'cancelled',
    returnedAt: booking?.returned_at || '', returnedBy: String(booking?.returned_by || ''), notes: String(booking?.notes || ''),
    version: Number(booking?.version || 0), updatedAt: booking?.updated_at || '',
  })).filter(booking => booking.bookingId && booking.providerId);
  mapped.pdcSubletBookings = canonicalBookings;
  mapped.__subletActiveCount = canonicalBookings.filter(booking => booking.status === 'active').length;
  // Multi-provider snapshots do not populate the legacy singular work item.
  // Active bookings require incomplete Sublet; returned bookings retain a
  // completed historical requirement; cancelled-only rows remain optional.
  const bookedBookings = canonicalBookings.filter(booking => ['active', 'returned'].includes(booking.status));
  if (bookedBookings.length) {
    mapped.pdcRequiresSublet = true;
    mapped.pdcCompleteSublet = mapped.__subletActiveCount === 0;
  }
  const activeBridge = canonicalBookings.filter(booking => booking.status === 'active').sort((a, b) => a.outDate.localeCompare(b.outDate))[0];
  const latestBridge = canonicalBookings.slice().sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))[0];
  const bridge = activeBridge || latestBridge;
  const sublet = bridge ? {
    provider: bridge.provider, provider_email: bridge.providerEmail, booking_date: bridge.outDate,
    expected_return_date: bridge.expectedReturnDate, actual_return_date: bridge.returnedAt,
    notes: bridge.notes, version: bridge.version,
  } : (row.sublet_booking && typeof row.sublet_booking === 'object' ? row.sublet_booking : {});
  mapped.pmbSubletProvider = String(sublet.provider || '');
  mapped.pmbSubletProviderEmail = String(sublet.provider_email || '');
  mapped.pmbSubletPoSentDate = sublet.po_sent_date || '';
  mapped.pmbSubletBookingDate = sublet.booking_date || '';
  mapped.pmbSubletExpectedReturnDate = sublet.expected_return_date || '';
  mapped.pmbSubletActualReturnDate = sublet.actual_return_date || '';
  mapped.pmbSubletNotes = String(sublet.notes || '');
  mapped.pmbSubletEmailSent = sublet.email_sent === true;
  if (bookedBookings.length) mapped.pdcCompleteSublet = mapped.__subletActiveCount === 0;
  return mapped;
}
function rowIdentities(row = {}) { return { stock: identity(row.stock_number ?? row.stock), vin: identity(row.vin ?? row.VIN ?? row.chassis ?? row.chassisNo) }; }
function reconcileVehicleRows(localRows = [], serverRows = [], options = {}) {
  const local = Array.isArray(localRows) ? localRows : [];
  const authoritative = options && options.authoritative === true;
  const visibleServer = (Array.isArray(serverRows) ? serverRows : []).filter(row => row && (row.visible_on_board !== false
    || Boolean(row.rft_collected_at)));
  const localStockIndexes = new Map();
  const localVinIndexes = new Map();
  local.forEach((row, index) => {
    const ids = rowIdentities(row);
    if (ids.stock) {
      const bucket = localStockIndexes.get(ids.stock) || [];
      bucket.push(index);
      localStockIndexes.set(ids.stock, bucket);
    }
    if (ids.vin) {
      const bucket = localVinIndexes.get(ids.vin) || [];
      bucket.push(index);
      localVinIndexes.set(ids.vin, bucket);
    }
  });
  const replaced = new Set(); const conflicts = new Set(); const additions = [];
  for (const serverRow of visibleServer) {
    const serverId = rowIdentities(serverRow);
    const stockMatches = serverId.stock ? (localStockIndexes.get(serverId.stock) || []) : [];
    const vinMatches = serverId.vin ? (localVinIndexes.get(serverId.vin) || []) : [];
    const candidates = new Set([...stockMatches, ...vinMatches]);
    const stockIndex = stockMatches.length === 1 ? stockMatches[0] : -1; const vinIndex = vinMatches.length === 1 ? vinMatches[0] : -1;
    const ambiguous = stockMatches.length > 1 || vinMatches.length > 1 || (stockIndex >= 0 && vinIndex >= 0 && stockIndex !== vinIndex);
    if (ambiguous) { candidates.forEach(index => conflicts.add(index)); continue; }
    const index = stockIndex >= 0 ? stockIndex : vinIndex; const mapped = mapServerVehicle(serverRow);
    if (index >= 0) { additions.push({ ...local[index], ...mapped }); replaced.add(index); } else additions.push(mapped);
  }
  const retained = local.flatMap((row, index) => {
    if (replaced.has(index) || (authoritative && !conflicts.has(index))) return [];
    return [conflicts.has(index)
      ? { ...row, __locationIdentityReadOnly: true, __emailVehicleIdentityConflict: true }
      : row];
  });
  return { rows: retained.concat(additions), conflictCount: conflicts.size };
}
function createPdcEmailVehicleLocationService(options = {}) {
  const config = options.config || {};
  if (projectRef(config.url) !== PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF) throw new Error('Authenticated email vehicle locations are staging-only.');
  const getAccessToken = typeof options.getAccessToken === 'function' ? options.getAccessToken : () => null;
  const subscribeRealtime = typeof options.subscribeRealtime === 'function' ? options.subscribeRealtime : null;
  const request = options.fetchImpl || (typeof fetch !== 'undefined' ? fetch : null);
  const url = String(config.url || '').replace(/\/$/, ''); const key = String(config.publishableKey || '');
  if (!request || !key) throw new Error('Authenticated email vehicle locations require the staging browser client.');
  async function snapshot() {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_EMAIL_VEHICLE_SNAPSHOT_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}' });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || `HTTP ${response.status}`, data: null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'snapshot_unavailable', data: null }; }
  }
  async function readSubletAuditLedgers(vehicleId = '', stockNumber = '', jobCardNumber = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_SUBLET_AUDIT_READ_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_stock_number: String(stockNumber || '').trim(), p_job_card_number: String(jobCardNumber || '').trim() }) });
      const body = await response.json().catch(() => null);
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'sublet_audit_read_unavailable', data: null }; }
  }
  async function saveVehicleWorkshopLineHoursBatch({ vehicleId = '', stockNumber = '', jobCardNumber = '', expectedVehicleVersion = 0, rows = [], idempotencyKey = '' } = {}) {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    const payload = {
      p_vehicle_id: String(vehicleId || ''),
      p_stock_number: String(stockNumber || '').trim(),
      p_job_card_number: String(jobCardNumber || '').trim(),
      p_expected_vehicle_version: Number(expectedVehicleVersion),
      p_estimated_rows: (Array.isArray(rows) ? rows : []).map(row => ({
        operation_line_id: String(row?.operationLineId || row?.operation_line_id || '').trim().toLowerCase(),
        adjustment_id: row?.adjustmentId || row?.adjustment_id || null,
        expected_line_version: Number(row?.expectedLineVersion ?? row?.expected_line_version ?? 0),
        line_key: String(row?.lineKey || row?.line_key || '').trim(),
        stage_code: String(row?.stageCode || row?.stage_code || '').trim().toUpperCase(),
        work_key: canonicalWorkKey(row?.workKey || row?.work_key || ''),
        estimated_hours: row?.estimatedHours !== undefined ? row.estimatedHours : row?.estimated_hours ?? null,
      })),
      p_idempotency_key: String(idempotencyKey || '').trim(),
    };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_WORKSHOP_HOURS_BATCH_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json().catch(() => null);
      const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '') || !/^[a-f0-9]{64}$/i.test(String(data.request_sha256 || ''))) {
        return { ok: false, code: body?.code || body?.error || 'workshop_hours_batch_receipt_invalid', data: data || null };
      }
      return { ok: true, code: body.code || 'workshop_hours_batch_saved', data };
    } catch (_error) { return { ok: false, code: 'workshop_hours_batch_unavailable', data: null }; }
  }
  async function updateSublet(vehicleId = '', expectedVersion = 0, field = '', value = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_SUBLET_UPDATE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_field: field, p_value: String(value ?? '') }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: subletResponseCode(body, response.status), data: body?.data || null };
      return { ok: true, code: body.code || 'updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'sublet_update_unavailable', data: null }; }
  }
  async function subletRpc(name, payload, unavailableCode) {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: subletResponseCode(body, response.status), data: body?.data || null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: unavailableCode, data: null }; }
  }
  function createSubletBooking(vehicleId = '', vehicleVersion = 0, providerId = '', outDate = '', expectedReturnDate = '', providerEmail = '', notes = '') {
    return subletRpc(PDC_SUBLET_CREATE_RPC, { p_vehicle_id: vehicleId, p_vehicle_version: Number(vehicleVersion) || 0, p_provider_id: providerId, p_out_date: outDate, p_expected_return_date: expectedReturnDate, p_provider_email: providerEmail, p_notes: notes }, 'sublet_create_unavailable');
  }
  function updateSubletBooking(bookingId = '', expectedVersion = 0, outDate = '', expectedReturnDate = '', notes = null) {
    return subletRpc(PDC_SUBLET_BOOKING_UPDATE_RPC, { p_booking_id: bookingId, p_expected_version: Number(expectedVersion) || 0, p_out_date: outDate, p_expected_return_date: expectedReturnDate, p_notes: notes }, 'sublet_update_unavailable');
  }
  function updateSubletBookingProvider(bookingId = '', expectedVersion = 0, providerId = '', providerEmail = '', idempotencyKey = '') {
    return subletRpc(PDC_SUBLET_PROVIDER_UPDATE_RPC, { p_booking_id: bookingId, p_expected_version: Number(expectedVersion) || 0, p_provider_id: providerId, p_provider_email: providerEmail, p_idempotency_key: idempotencyKey || crypto.randomUUID() }, 'sublet_provider_update_unavailable');
  }
  function returnSubletBooking(bookingId = '', expectedVersion = 0, returnedAt = null) {
    return subletRpc(PDC_SUBLET_RETURN_RPC, { p_booking_id: bookingId, p_expected_version: Number(expectedVersion) || 0, p_returned_at: returnedAt }, 'sublet_return_unavailable');
  }
  async function updatePartsEta(vehicleId = '', expectedVersion = 0, value = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_ETA_UPDATE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_worst_eta: String(value || '') || null }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'parts_eta_update_unavailable', data: null }; }
  }
  async function markPartsOrdered(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_ORDERED_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }) });
      const body = await response.json();
      const data = body?.data || body;
      if (!response.ok || !body || !data?.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '') || typeof data.changed !== 'boolean') return { ok: false, code: body?.code || body?.error || 'parts_ordered_receipt_invalid', data: null };
      return { ok: body.ok === true, code: body.code || data.code || 'parts_ordered_rejected', data };
    } catch (_error) { return { ok: false, code: 'parts_ordered_update_unavailable', data: null }; }
  }
  async function markPartsComplete(vehicleId = '', stockNumber = '', expectedVersion = 0, idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_COMPLETE_RPC}`, { method: 'POST', headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_stock_number: String(stockNumber || '').trim(), p_expected_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || crypto.randomUUID()) }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      const data = body.data || body;
      if (!PDC_PARTS_COMPLETE_SUCCESS_CODES.has(String(body.code || '').trim())
          || !data || typeof data !== 'object' || !data.receipt_id
          || String(data.vehicle_id || '') !== String(vehicleId || '')
          || identity(data.stock_number) !== identity(stockNumber)
          || Number(data.vehicle_version) < 1
          || typeof data.changed !== 'boolean') {
        return { ok: false, code: 'parts_completion_receipt_invalid', data: null };
      }
      return { ok: true, code: body.code, data };
    } catch (_error) { return { ok: false, code: 'parts_complete_update_unavailable', data: null }; }
  }
  async function setPartsStoppage(vehicleId = '', expectedVersion = 0, action = 'set', reason = '', idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_PARTS_STOPPAGE_RPC}`, {
        method: 'POST',
        headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_expected_version: Number(expectedVersion) || 0,
          p_idempotency_key: String(idempotencyKey || ''), p_action: String(action || ''), p_reason: String(reason || '').trim() }),
      });
      const body = await response.json();
      const data = body?.data || body;
      if (!response.ok || !data || !data.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '')
          || typeof data.changed !== 'boolean' || Number(data.vehicle_version_after || 0) < 1) {
        return { ok: false, code: body?.code || body?.error || 'parts_stoppage_receipt_invalid', data: null };
      }
      return { ok: body.ok === true, code: body.code || data.code || 'parts_stoppage_rejected', data };
    } catch (_error) { return { ok: false, code: 'parts_stoppage_update_unavailable', data: null }; }
  }
  async function createAcceptanceVehicle(stock = '', customer = '', vehicleDescription = '', jobCardNumber = '', idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_ACCEPTANCE_VEHICLE_CREATE_RPC}`, {
        method: 'POST',
        headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_stock_number: String(stock || '').trim(),
          p_customer_name: String(customer || '').trim(),
          p_vehicle_description: String(vehicleDescription || '').trim(),
          p_job_card_number: String(jobCardNumber || '').trim(),
          p_idempotency_key: String(idempotencyKey || '').trim(),
        }),
      });
      const body = await response.json();
      const data = body?.data || body;
      const requestedStock = String(stock || '').trim();
      if (!response.ok || !body || body.ok === false || !data?.receipt_id || !data?.vehicle_id || Number(data.vehicle_version || 0) < 1
          || data.notification_delta !== 0 || data.protected_state?.rows !== 1498
          || String(data.vehicle?.stock_number || '').trim() !== requestedStock
          || String(data.vehicle?.source_batch_id || '') !== 'HERMES-TEST-ACCEPTANCE-20260825') {
        return { ok: false, code: body?.code || body?.error || 'acceptance_vehicle_receipt_invalid', data: null };
      }
      return { ok: true, code: body.code || 'acceptance_vehicle_created', data };
    } catch (_error) { return { ok: false, code: 'acceptance_vehicle_create_unavailable', data: null }; }
  }
  async function setQcOperationCompletion(vehicleId = '', vehicleVersion = 0, lineIdentity = '', lineVersion = 0, completed = false, idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_QC_OPERATION_COMPLETION_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(vehicleVersion) || 0, p_line_identity: String(lineIdentity || ''),
          p_expected_line_version: Number(lineVersion) || 0, p_idempotency_key: String(idempotencyKey || ''), p_completed: completed === true }) });
      const body = await response.json(); const data = body?.data || body;
      if (!response.ok || body?.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '')
          || String(data.line?.line_identity || '') !== String(lineIdentity || '') || data.line?.completed !== (completed === true)
          || Number(data.line?.version || 0) < 1 || Number(data.vehicle_version_after || 0) < 1 || !/^[a-f0-9]{64}$/.test(String(data.request_sha256 || '')))
        return { ok: false, code: body?.code || body?.error || 'qc_operation_receipt_invalid', data: null };
      return { ok: true, code: body.code || 'qc_operation_completion_saved', data };
    } catch (_error) { return { ok: false, code: 'qc_operation_completion_unavailable', data: null }; }
  }
  async function rejectQcVehicleToPmb(vehicleId = '', stockNumber = '', expectedVersion = 0, reason = '', idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/reject_pdc_qc_vehicle_to_pmb_stoppage_767`, {
        method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_stock_number: String(stockNumber || '').trim(), p_expected_vehicle_version: Number(expectedVersion) || 0, p_reason: String(reason || '').trim(), p_idempotency_key: String(idempotencyKey || crypto.randomUUID()) }),
      });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '') || String(data.stock_number || '').trim() !== String(stockNumber || '').trim() || Number(data.vehicle_version_after || 0) !== Number(expectedVersion) + 1 || data.status !== 'Pending QC fixes' || data.current_location !== 'PMB' || data.workshop_status !== 'stoppage' || Number(data.notification_delta || 0) !== 0) return { ok: false, code: body?.code || body?.error || 'qc_vehicle_rejection_receipt_invalid', data: null };
      return { ok: true, code: body.code || 'qc_vehicle_rejected_to_pmb_stoppage', data };
    } catch (_error) { return { ok: false, code: 'qc_vehicle_rejection_unavailable', data: null }; }
  }
  function jwtSubject(token = '') {
    try {
      const payload = String(token || '').split('.')[1];
      if (!payload) return '';
      const normalized = payload.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((payload.length + 3) % 4);
      const decoded = JSON.parse(typeof atob === 'function' ? atob(normalized) : Buffer.from(normalized, 'base64').toString('utf8'));
      return String(decoded.sub || '').trim().toLowerCase();
    } catch (_error) { return ''; }
  }
  async function qcPhotoSource(file) {
    if (typeof createImageBitmap === 'function') {
      try { return { source: await createImageBitmap(file, { imageOrientation: 'from-image' }), close: true }; } catch (_error) { /* use the Image fallback */ }
    }
    if (typeof Image !== 'function' || typeof FileReader !== 'function') throw new Error('qc_photo_compression_unavailable');
    const dataUrl = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.addEventListener('load', () => resolve(String(reader.result || '')), { once: true });
      reader.addEventListener('error', () => reject(new Error('qc_photo_compression_unavailable')), { once: true });
      reader.readAsDataURL(file);
    });
    const image = await new Promise((resolve, reject) => {
      const element = new Image(); element.onload = () => resolve(element); element.onerror = () => reject(new Error('qc_photo_invalid_input')); element.src = dataUrl;
    });
    return { source: image, close: false };
  }
  async function compressQcPhoto(file) {
    const originalByteLength = Number(file?.size || 0);
    if (!file || !String(file.type || '').toLowerCase().startsWith('image/')) throw new Error('qc_photo_invalid_input');
    const loaded = await qcPhotoSource(file);
    const bitmap = loaded.source;
    const maxDimension = 1600;
    let scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height));
    let best = null;
    for (let pass = 0; pass < 6; pass += 1) {
      const width = Math.max(1, Math.round(bitmap.width * scale));
      const height = Math.max(1, Math.round(bitmap.height * scale));
      const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
      const context = canvas.getContext('2d', { alpha: false });
      if (!context) throw new Error('qc_photo_compression_unavailable');
      context.drawImage(bitmap, 0, 0, width, height);
      for (const quality of [0.82, 0.72, 0.62, 0.52, 0.42, 0.32]) {
        const blob = await new Promise(resolve => {
          let settled = false;
          const finish = value => { if (settled) return; settled = true; resolve(value || null); };
          const timer = setTimeout(() => finish(null), 8000);
          try { canvas.toBlob(value => { clearTimeout(timer); finish(value); }, 'image/jpeg', quality); } catch (_error) { clearTimeout(timer); finish(null); }
        });
        if (!blob || !blob.size) continue;
        if (!best || blob.size < best.blob.size) best = { blob, width, height };
        if (blob.size <= 750 * 1024) {
          if (loaded.close) bitmap.close?.();
          return { file: new File([blob], `${String(file.name || 'completion-photo').replace(/\.[^.]+$/, '')}.jpg`, { type: 'image/jpeg', lastModified: Date.now() }), originalByteLength, width, height };
        }
      }
      scale *= 0.85;
    }
    if (loaded.close) bitmap.close?.();
    if (!best || best.blob.size > 1024 * 1024) throw new Error('qc_photo_compression_limit');
    return { file: new File([best.blob], `${String(file.name || 'completion-photo').replace(/\.[^.]+$/, '')}.jpg`, { type: 'image/jpeg', lastModified: Date.now() }), originalByteLength, width: best.width, height: best.height };
  }
  async function uploadQcPhotoEvidence(vehicleId = '', vehicleVersion = 0, cycleIdOrFile, maybeFile) {
    const token = getAccessToken();
    if (!token) return { ok: false, code: 'not_authenticated', data: null };
    const retest = typeof cycleIdOrFile === 'string';
    const cycleId = retest ? String(cycleIdOrFile || '').trim() : '';
    const file = retest ? maybeFile : cycleIdOrFile;
    if (retest && !/^[0-9a-f-]{36}$/i.test(cycleId)) return { ok: false, code: 'qc_retest_cycle_invalid', data: null };
    if (!file || !String(file.type || '').toLowerCase().startsWith('image/') || Number(file.size || 0) < 1 || Number(file.size || 0) > 10 * 1024 * 1024) return { ok: false, code: 'qc_photo_invalid_input', data: null };
    const actorId = jwtSubject(token);
    if (!actorId) return { ok: false, code: 'auth_subject_unavailable', data: null };
    try {
      const compressed = await compressQcPhoto(file);
      const uploadFile = compressed.file;
      const bytes = await uploadFile.arrayBuffer();
      const digest = await crypto.subtle.digest('SHA-256', bytes);
      const sha256 = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
      const vehicle = String(vehicleId || '').trim();
      const safeName = String(uploadFile.name || 'completion-photo').replace(/[^a-zA-Z0-9._-]+/g, '-').slice(-120) || 'completion-photo';
      const path = retest ? `qc-finalization/${actorId}/${crypto.randomUUID()}/${safeName}` : `qc-finalization/${actorId}/${vehicle}/${crypto.randomUUID()}-${safeName}`;
      const upload = await request(`${url}/storage/v1/object/${PDC_QC_PHOTO_BUCKET}/${encodeURIComponent(path)}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': uploadFile.type, 'x-upsert': 'false' }, body: uploadFile });
      if (!upload.ok) return { ok: false, code: 'qc_photo_upload_failed', data: null };
      const payload = { p_vehicle_id: vehicle, p_expected_vehicle_version: Number(vehicleVersion) || 0, p_bucket_id: PDC_QC_PHOTO_BUCKET, p_storage_path: path, p_content_type: uploadFile.type, p_byte_length: Number(uploadFile.size), p_original_byte_length: compressed.originalByteLength, p_image_width: compressed.width, p_image_height: compressed.height, p_sha256: sha256, p_original_filename: String(file.name || safeName).slice(0, 180), p_idempotency_key: crypto.randomUUID() };
      if (retest) payload.p_cycle_id = cycleId;
      const response = await request(`${url}/rest/v1/rpc/${retest ? PDC_QC_RETEST_PHOTO_RPC : PDC_QC_PHOTO_RECEIPT_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      const transformed = { bucket_id: PDC_QC_PHOTO_BUCKET, storage_path: path, content_type: uploadFile.type, byte_length: Number(uploadFile.size), original_byte_length: compressed.originalByteLength, image_width: Number(compressed.width), image_height: Number(compressed.height), sha256, original_filename: String(file.name || safeName).slice(0, 180), photo_receipt_id: data?.photo_receipt_id, vehicle_id: data?.vehicle_id, cycle_id: data?.cycle_id };
      const explicitMetadataInvalid = (Object.prototype.hasOwnProperty.call(data || {}, 'byte_length') && Number(data.byte_length) < 1)
        || (Object.prototype.hasOwnProperty.call(data || {}, 'image_width') && Number(data.image_width) < 1)
        || (Object.prototype.hasOwnProperty.call(data || {}, 'image_height') && Number(data.image_height) < 1)
        || (Object.prototype.hasOwnProperty.call(data || {}, 'sha256') && !/^[a-f0-9]{64}$/i.test(String(data.sha256 || '')))
        || (Object.prototype.hasOwnProperty.call(data || {}, 'storage_path') && !String(data.storage_path || '').trim());
      if (!response.ok || !body || body.ok !== true || explicitMetadataInvalid || !data?.photo_receipt_id || String(data.vehicle_id || '') !== vehicle || (retest && String(data.cycle_id || '') !== cycleId) || transformed.byte_length < 1 || transformed.byte_length > 1048576 || transformed.image_width < 1 || transformed.image_width > 1600 || transformed.image_height < 1 || transformed.image_height > 1600 || !/^[a-f0-9]{64}$/i.test(transformed.sha256)) return { ok: false, code: explicitMetadataInvalid ? 'qc_photo_receipt_invalid' : (body?.code || 'qc_photo_receipt_invalid'), data: null };
      return { ok: true, code: body.code || 'qc_photo_stored', data: { ...data, ...transformed } };
    } catch (error) { return { ok: false, code: error?.message || 'qc_photo_upload_unavailable', data: null }; }
  }
  async function finalizeQcToRft(vehicleId = '', vehicleVersion = 0, photoReceiptId = '', idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_QC_FINALIZATION_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(vehicleVersion) || 0, p_photo_receipt_id: String(photoReceiptId || ''), p_idempotency_key: String(idempotencyKey || '') }) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(vehicleId || '') || Number(data.vehicle_version_after || 0) < 1 || data.outbox?.delivery_status !== 'pending' || data.outbox?.sent_at != null || data.outbox?.delivered_at != null) return { ok: false, code: body?.code || 'qc_finalization_receipt_invalid', data };
      return { ok: true, code: body.code || 'qc_signed_off_moved_to_rft', data };
    } catch (_error) { return { ok: false, code: 'qc_finalization_unavailable', data: null }; }
  }
  async function finalizeQcRetest(vehicleId = '', vehicleVersion = 0, cycleId = '', photoReceiptId = '', idempotencyKey = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    if (!/^[0-9a-f-]{36}$/i.test(String(cycleId || '')) || !/^[0-9a-f-]{36}$/i.test(String(photoReceiptId || ''))) return { ok: false, code: 'qc_retest_signoff_invalid_input', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_QC_RETEST_FINALIZATION_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(vehicleVersion) || 0, p_cycle_id: String(cycleId), p_photo_receipt_id: String(photoReceiptId), p_idempotency_key: String(idempotencyKey || crypto.randomUUID()) }) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || String(data?.vehicle_id || '') !== String(vehicleId || '') || String(data?.cycle_id || '') !== String(cycleId) || Number(data?.vehicle_version_after || 0) < 1) return { ok: false, code: body?.code || 'qc_retest_signoff_receipt_invalid', data };
      return { ok: true, code: body.code || 'qc_retest_signed_off_to_rft', replay: body.replay === true, data };
    } catch (_error) { return { ok: false, code: 'qc_retest_signoff_unavailable', data: null }; }
  }
  async function pdc700Rpc(name = '', payload = {}, unavailableCode = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(payload.p_vehicle_id || data.vehicle_id || '')) return { ok: false, code: body?.code || body?.error || unavailableCode, data };
      return { ok: true, code: body.code || data.code || 'ok', replay: body.replay === true, data };
    } catch (_error) { return { ok: false, code: unavailableCode, data: null }; }
  }
  function finalizeQcToRft700(vehicleId = '', vehicleVersion = 0, photoReceiptId = '', idempotencyKey = '') {
    return pdc700Rpc(PDC_FINAL_QC_TO_RFT_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(vehicleVersion) || 0, p_photo_receipt_id: String(photoReceiptId || ''), p_idempotency_key: String(idempotencyKey || '') }, 'qc_finalization_unavailable');
  }
  function bookRftTransport700(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc700Rpc(PDC_FINAL_RFT_BOOK_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_booking_unavailable');
  }
  function collectRftTransport700(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc700Rpc(PDC_FINAL_RFT_COLLECT_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_collection_unavailable');
  }
  function bookRftTransport734(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc700Rpc(PDC_DURABLE_RFT_BOOK_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_booking_unavailable');
  }
  function collectRftTransport734(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc700Rpc(PDC_DURABLE_RFT_COLLECT_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_collection_unavailable');
  }
  function setRftConfirmation736(vehicleId = '', expectedVersion = 0, confirmed = false, idempotencyKey = '') {
    return pdc700Rpc(PDC_RFT_CONFIRMATION_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_confirmed: confirmed === true, p_idempotency_key: String(idempotencyKey || '') }, 'rft_confirmation_unavailable');
  }
  function bytesToBase64(bytes) {
    const value = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
    if (typeof btoa === 'function') {
      let binary = '';
      for (let index = 0; index < value.length; index += 0x8000) binary += String.fromCharCode(...value.subarray(index, index + 0x8000));
      return btoa(binary);
    }
    return Buffer.from(value).toString('base64');
  }
  async function sha256Bytes(bytes) {
    if (!globalThis.crypto?.subtle) return '';
    const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  }
  async function readRftBookingContext739(vehicleId = '') {
    const token = getAccessToken();
    if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_RFT_TRANSPORT_DRAFT_CONTEXT_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || '') }) });
      const body = await response.json().catch(() => null); const data = body?.data || null;
      if (!response.ok || !body || body.ok !== true || !data?.vehicle_id || String(data.vehicle_id) !== String(vehicleId || '') || !data.photo?.photo_receipt_id) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data };
      return { ok: true, code: body.code || 'rft_transport_booking_context', data };
    } catch (_error) { return { ok: false, code: 'rft_transport_context_unavailable', data: null }; }
  }
  async function bookRftTransport739(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    const token = getAccessToken();
    if (!token) return { ok: false, code: 'not_authenticated', data: null };
    const requestedVehicleId = String(vehicleId || '').trim();
    const contextResult = await readRftBookingContext739(requestedVehicleId);
    if (!contextResult.ok) return contextResult;
    const photo = contextResult.data.photo || {};
    try {
      const photoPath = String(photo.storage_path || '').split('/').map(segment => encodeURIComponent(segment)).join('/');
      const photoResponse = await request(`${url}/storage/v1/object/authenticated/${encodeURIComponent(String(photo.bucket_id || ''))}/${photoPath}`, { method: 'GET', headers: { apikey: key, Authorization: `Bearer ${token}` } });
      if (!photoResponse.ok) return { ok: false, code: 'qc_photo_storage_missing', data: null };
      const photoBytes = new Uint8Array(await photoResponse.arrayBuffer());
      if (photoBytes.byteLength !== Number(photo.byte_length || 0)) return { ok: false, code: 'qc_photo_bytes_mismatch', data: null };
      const photoSha256 = await sha256Bytes(photoBytes);
      if (photoSha256 && photoSha256 !== String(photo.sha256 || '').toLowerCase()) return { ok: false, code: 'qc_photo_bytes_mismatch', data: null };
      const payload = {
        p_vehicle_id: requestedVehicleId,
        p_expected_vehicle_version: Number(expectedVersion) || 0,
        p_idempotency_key: String(idempotencyKey || ''),
        p_photo_receipt_id: String(photo.photo_receipt_id || ''),
        p_photo_bucket_id: String(photo.bucket_id || ''),
        p_photo_storage_path: String(photo.storage_path || ''),
        p_photo_content_type: String(photo.content_type || '').toLowerCase(),
        p_photo_byte_length: Number(photo.byte_length) || 0,
        p_photo_sha256: String(photo.sha256 || '').toLowerCase(),
        p_photo_bytes_base64: bytesToBase64(photoBytes),
      };
      const response = await request(`${url}/rest/v1/rpc/${PDC_RFT_TRANSPORT_DRAFT_BOOK_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== requestedVehicleId || !data.draft_id || data.draft_content_type !== 'message/rfc822' || !/^[a-f0-9]{64}$/i.test(String(data.draft_mime_sha256 || '')) || Number(data.draft_mime_byte_length || 0) < 1 || data.delivery_enabled !== false || data.sent_at != null || data.delivered_at != null) return { ok: false, code: body?.code || body?.error || 'rft_transport_draft_receipt_invalid', data: null };
      return { ok: true, code: body.code || 'rft_transport_booked', replay: body.replay === true, data };
    } catch (_error) { return { ok: false, code: 'rft_transport_draft_unavailable', data: null }; }
  }
  function readRftTransportDraft739(vehicleId = '') {
    const token = getAccessToken();
    if (!token) return Promise.resolve({ ok: false, code: 'not_authenticated', data: null });
    return request(`${url}/rest/v1/rpc/${PDC_RFT_TRANSPORT_DRAFT_READ_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || '') }) })
      .then(async response => {
        const body = await response.json().catch(() => null); const data = body?.data || null;
        if (!response.ok || !body || body.ok !== true || !data?.draft_id || data.mime_content_type !== 'message/rfc822' || !data.mime_base64 || Number(data.mime_byte_length || 0) < 1 || !/^[a-f0-9]{64}$/i.test(String(data.mime_sha256 || ''))) return { ok: false, code: body?.code || 'rft_transport_draft_unavailable', data };
        return { ok: true, code: body.code || 'rft_transport_draft', data };
      })
      .catch(() => ({ ok: false, code: 'rft_transport_draft_unavailable', data: null }));
  }
  function readRftTransportEvidence734(vehicleId = '') {
    const token = getAccessToken();
    if (!token) return Promise.resolve({ ok: false, code: 'not_authenticated', data: null });
    return request(`${url}/rest/v1/rpc/${PDC_DURABLE_RFT_EVIDENCE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: String(vehicleId || '') }) })
      .then(async response => {
        const body = await response.json().catch(() => null);
        if (!response.ok || !body || body.ok !== true) return { ok: false, code: body?.code || 'rft_transport_evidence_unavailable', data: body?.data || null };
        return { ok: true, code: body.code || 'rft_transport_evidence', data: body };
      })
      .catch(() => ({ ok: false, code: 'rft_transport_evidence_unavailable', data: null }));
  }

  async function vehicleHistory(vehicleId = '', dealerCode = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_VEHICLE_HISTORY_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_dealer_code: String(dealerCode || '').trim() || null }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'ok', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'vehicle_history_unavailable', data: null }; }
  }
  async function updateSalesPreparation(vehicleId = '', expectedVersion = 0, field = '', value = false) {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_SALES_PREPARATION_UPDATE_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: vehicleId, p_expected_version: Number(expectedVersion) || 0, p_field: String(field || ''), p_value: value === true }) });
      const body = await response.json();
      if (!response.ok || !body || body.ok === false) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data: body?.data || null };
      return { ok: true, code: body.code || 'sales_preparation_updated', data: body.data || body };
    } catch (_error) { return { ok: false, code: 'sales_preparation_update_unavailable', data: null }; }
  }
  async function updateSalespersonAssignment(vehicleId = '', expectedVersion = 0, code = '', idempotencyKey = '') {
    const token = getAccessToken();
    if (!token) return { ok: false, code: 'not_authenticated', data: null };
    const requestedVehicleId = String(vehicleId || '').trim();
    const requestedCode = String(code || '').trim().toUpperCase();
    const requestedIdempotencyKey = String(idempotencyKey || '').trim();
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_SALESPERSON_ASSIGNMENT_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: requestedVehicleId, p_expected_vehicle_version: Number(expectedVersion) || 0, p_salesperson_code: requestedCode || null, p_idempotency_key: requestedIdempotencyKey }) });
      const body = await response.json().catch(() => null); const data = body?.data || null;
      if (!response.ok || !body || body.ok !== true) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data };
      if (!body.receipt_id || !/^[a-f0-9]{64}$/i.test(String(body.request_sha256 || '')) || String(data?.vehicle_id || '') !== requestedVehicleId || Number(data?.vehicle_version_after ?? data?.vehicle_version ?? 0) < 1) return { ok: false, code: 'salesperson_assignment_receipt_invalid', data: null };
      return { ok: true, code: body.code || 'salesperson_assigned', data: { ...data, receipt_id: body.receipt_id, request_sha256: body.request_sha256, replay: body.replay === true } };
    } catch (_error) { return { ok: false, code: 'salesperson_assignment_unavailable', data: null }; }
  }
  async function updateVehicleDetailFields(vehicleId = '', expectedVersion = 0, changes = {}, idempotencyKey = '') {
    const token = getAccessToken();
    if (!token) return { ok: false, code: 'not_authenticated', data: null };
    const requestedVehicleId = String(vehicleId || '').trim();
    const requestedChanges = {};
    Object.entries(changes && typeof changes === 'object' ? changes : {}).forEach(([field, value]) => { if (['client_name', 'key_number', 'job_card_number'].includes(field)) requestedChanges[field] = String(value ?? ''); });
    try {
      const response = await request(`${url}/rest/v1/rpc/${PDC_VEHICLE_DETAIL_FIELDS_RPC}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_vehicle_id: requestedVehicleId, p_expected_vehicle_version: Number(expectedVersion) || 0, p_changes: requestedChanges, p_idempotency_key: String(idempotencyKey || '').trim() }) });
      const body = await response.json().catch(() => null); const data = body?.data || null;
      if (!response.ok || !body || body.ok !== true) return { ok: false, code: body?.code || body?.error || `HTTP ${response.status}`, data };
      if (!body.receipt_id || !/^[a-f0-9]{64}$/i.test(String(body.request_sha256 || '')) || String(data?.vehicle_id || '') !== requestedVehicleId || Number(data?.vehicle_version_after ?? data?.vehicle_version ?? 0) < 1) return { ok: false, code: 'vehicle_detail_receipt_invalid', data: null };
      return { ok: true, code: body.code || 'vehicle_detail_updated', data: { ...data, receipt_id: body.receipt_id, request_sha256: body.request_sha256, replay: body.replay === true } };
    } catch (_error) { return { ok: false, code: 'vehicle_detail_update_unavailable', data: null }; }
  }
  async function pdc412Rpc(name = '', payload = {}, unavailableCode = '') {
    const token = getAccessToken(); if (!token) return { ok: false, code: 'not_authenticated', data: null };
    try {
      const response = await request(`${url}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const body = await response.json().catch(() => null); const data = body?.data || body;
      if (!response.ok || !body || body.ok !== true || !data?.receipt_id || String(data.vehicle_id || '') !== String(payload.p_vehicle_id || '')) return { ok: false, code: body?.code || body?.error || unavailableCode, data };
      return { ok: true, code: body.code || data.code || 'ok', data };
    } catch (_error) { return { ok: false, code: unavailableCode, data: null }; }
  }
  function clearVehicleStoppage(vehicleId = '', expectedVersion = 0, stoppageKind = '', bookingId = '', bookingVersion = 0, resolutionNote = '', idempotencyKey = '') {
    return pdc412Rpc(PDC_STOPPAGE_CLEAR_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_stoppage_kind: String(stoppageKind || '').trim().toLowerCase(), p_booking_id: bookingId ? String(bookingId) : null, p_expected_booking_version: Number(bookingVersion) || 0, p_resolution_note: String(resolutionNote || '').trim(), p_idempotency_key: String(idempotencyKey || '') }, 'stoppage_clear_unavailable');
  }
  function setPmbStoppage(vehicleId = '', expectedVersion = 0, action = '', reason = '', idempotencyKey = '') {
    return pdc412Rpc(PDC_PMB_STOPPAGE_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_action: String(action || '').trim().toLowerCase(), p_reason: String(reason || '').trim(), p_idempotency_key: String(idempotencyKey || '') }, 'pmb_stoppage_unavailable');
  }
  function bookRftTransport(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc412Rpc(PDC_RFT_TRANSPORT_BOOK_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_booking_unavailable');
  }
  function collectRftTransport(vehicleId = '', expectedVersion = 0, idempotencyKey = '') {
    return pdc412Rpc(PDC_RFT_TRANSPORT_COLLECT_RPC, { p_vehicle_id: String(vehicleId || ''), p_expected_vehicle_version: Number(expectedVersion) || 0, p_idempotency_key: String(idempotencyKey || '') }, 'rft_transport_collection_unavailable');
  }
  function subscribe(onRevision) {
    if (!subscribeRealtime) return { unsubscribe() {} };
    return subscribeRealtime(PDC_EMAIL_VEHICLE_REVISION_TABLE, event => { if (typeof onRevision === 'function') onRevision(event?.new?.revision ?? null, event); });
  }
  return { authority: 'supabase_staging_authenticated_email_vehicle', snapshot, readSubletAuditLedgers, saveVehicleWorkshopLineHoursBatch, updateSublet, createSubletBooking, updateSubletBooking, updateSubletBookingProvider, returnSubletBooking, updatePartsEta, markPartsOrdered, markPartsComplete, setPartsStoppage, vehicleHistory, updateSalesPreparation, updateSalespersonAssignment, updateVehicleDetailFields, clearVehicleStoppage, setPmbStoppage, bookRftTransport, collectRftTransport, finalizeQcToRft700, bookRftTransport700, collectRftTransport700, bookRftTransport734, collectRftTransport734, setRftConfirmation736, bookRftTransport739, readRftBookingContext739, readRftTransportDraft739, readRftTransportEvidence734, createAcceptanceVehicle, setQcOperationCompletion, rejectQcVehicleToPmb, uploadQcPhotoEvidence, finalizeQcToRft, finalizeQcRetest, subscribe };
 }
const pdcEmailVehicleLocationExported = { PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF, PDC_EMAIL_VEHICLE_REVISION_TABLE, PDC_EMAIL_VEHICLE_SNAPSHOT_RPC, PDC_SUBLET_AUDIT_READ_RPC, PDC_WORKSHOP_HOURS_BATCH_RPC, PDC_SUBLET_UPDATE_RPC, PDC_SUBLET_CREATE_RPC, PDC_SUBLET_BOOKING_UPDATE_RPC, PDC_SUBLET_PROVIDER_UPDATE_RPC, PDC_SUBLET_RETURN_RPC, PDC_PARTS_ETA_UPDATE_RPC, PDC_PARTS_ORDERED_RPC, PDC_PARTS_COMPLETE_RPC, PDC_PARTS_STOPPAGE_RPC, PDC_PARTS_COMPLETE_SUCCESS_CODES, PDC_VEHICLE_HISTORY_RPC, PDC_SALES_PREPARATION_UPDATE_RPC, PDC_SALESPERSON_ASSIGNMENT_RPC, PDC_VEHICLE_DETAIL_FIELDS_RPC, PDC_STOPPAGE_CLEAR_RPC, PDC_PMB_STOPPAGE_RPC, PDC_RFT_TRANSPORT_BOOK_RPC, PDC_RFT_TRANSPORT_COLLECT_RPC, PDC_RFT_CONFIRMATION_RPC, PDC_RFT_TRANSPORT_DRAFT_BOOK_RPC, PDC_RFT_TRANSPORT_DRAFT_CONTEXT_RPC, PDC_RFT_TRANSPORT_DRAFT_READ_RPC, PDC_FINAL_QC_TO_RFT_RPC, PDC_FINAL_RFT_BOOK_RPC, PDC_FINAL_RFT_COLLECT_RPC, PDC_FINAL_LIFECYCLE_RECEIPTS_TABLE, PDC_ACCEPTANCE_VEHICLE_CREATE_RPC, PDC_QC_OPERATION_COMPLETION_RPC, PDC_QC_PHOTO_BUCKET, PDC_QC_PHOTO_RECEIPT_RPC, PDC_QC_FINALIZATION_RPC, PDC_QC_RETEST_PHOTO_RPC, PDC_QC_RETEST_FINALIZATION_RPC, canonicalWorkKey, mapLifecycleHistory, mapServerVehicle, reconcileVehicleRows, createPdcEmailVehicleLocationService };
if (typeof module !== 'undefined' && module.exports) module.exports = pdcEmailVehicleLocationExported;
if (typeof window !== 'undefined') window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE = pdcEmailVehicleLocationExported;
