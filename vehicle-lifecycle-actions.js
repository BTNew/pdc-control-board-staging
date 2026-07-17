'use strict';

/*
 * Vehicle lifecycle shared actions bridge (QC complete -> RFT -> Collected).
 *
 * Mirrors the existing workshop-shared-actions.js pattern: maps each
 * frontend action to the exact protected transactional RPC name/parameter
 * shape defined by migration 016, over the same minimal fetch-based
 * Supabase REST/RPC client used by workshop-data-service.js
 * (createWorkshopSupabaseClient), so this file has no new dependency and no
 * DOM code. app.js is responsible for calling the right bridge function
 * when vehicleLifecycleSharedModeActive() is true, and for reloading/
 * re-rendering from authoritative vehicle data afterwards either way.
 *
 * Shared mode is opt-in and independent of the workshop planner's own
 * sharedData flag (a site could enable shared workshop scheduling without
 * yet enabling shared QC/RFT/Collected, or vice versa) - see
 * window.PDC_SUPABASE_CONFIG.vehicleLifecycle.sharedData.
 */

function vehicleLifecycleSharedModeEnabled(config) {
  return !!(config && config.vehicleLifecycle && config.vehicleLifecycle.sharedData === true);
}

function buildVehicleLifecycleSharedActions(client, getAccessToken) {
  async function rpc(name, params) {
    const token = typeof getAccessToken === 'function' ? getAccessToken() : null;
    const result = await client.rpc(token, name, params);
    if (!result.ok) {
      return { ok: false, error: 'request_failed', status: result.status, body: result.body };
    }
    return result.body || {};
  }

  return {
    qcCompleteVehicle({ vehicleId, expectedVersion, workItemKey, completedSummary }) {
      return rpc('qc_complete_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
        p_work_item_key: workItemKey ?? 'QC',
        p_completed_summary: completedSummary ?? null,
      });
    },

    rftTransferVehicle({ vehicleId, expectedVersion }) {
      return rpc('rft_transfer_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
      });
    },

    rftCollectVehicle({ vehicleId, expectedVersion }) {
      return rpc('rft_collect_vehicle', {
        p_vehicle_id: vehicleId,
        p_expected_version: expectedVersion,
      });
    },

    retryVehicleNotification({ notificationId, recipientEmail }) {
      return rpc('retry_vehicle_notification', {
        p_notification_id: notificationId,
        p_recipient_email: recipientEmail ?? null,
      });
    },
  };
}

// Human-readable, non-technical mapping for the error codes the RPCs above
// can return, matching the pattern already established by
// workshopDescribeSharedActionError() in workshop-planner.js. Staff should
// never see a raw backend error code.
function describeVehicleLifecycleActionError(error = '') {
  const MESSAGES = {
    vehicle_version_conflict: 'This vehicle changed since you loaded it. The latest information has been reloaded - please check and try again.',
    already_qc_complete: 'QC has already been completed for this vehicle.',
    already_collected: 'This vehicle has already been collected and moved to Completed Vehicles.',
    qc_not_complete: 'QC sign-off is required before this vehicle can be transferred to RFT.',
    not_in_active_lifecycle: 'This vehicle is not currently active in PMB, so it cannot be transferred to RFT.',
    not_in_rft: 'This vehicle is not currently in RFT, so it cannot be marked collected.',
    request_failed: 'The change could not be saved. Please check your connection and try again.',
    missing_expected_version: 'This action is missing required version information and was not applied.',
  };
  return MESSAGES[error] || 'The change could not be saved. Please try again or contact an administrator.';
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    vehicleLifecycleSharedModeEnabled,
    buildVehicleLifecycleSharedActions,
    describeVehicleLifecycleActionError,
  };
}
if (typeof window !== 'undefined') {
  window.vehicleLifecycleSharedModeEnabled = vehicleLifecycleSharedModeEnabled;
  window.buildVehicleLifecycleSharedActions = buildVehicleLifecycleSharedActions;
  window.describeVehicleLifecycleActionError = describeVehicleLifecycleActionError;
}
