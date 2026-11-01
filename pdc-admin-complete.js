/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r800 (F415, Craig 1 Nov 2026 08:37): "give me the option, for admins to override and complete vehicles to remove them to
 * completed vehicles." A red "Complete vehicle" button in the vehicle drawer (administrators only) opens this dialog: type the
 * stock number to confirm, give a reason, and the car goes to Completed through admin_complete_vehicle_800 (same end state as
 * the Navision delivery rule: off the board, open bookings cancelled, pending New Vehicles review closed). The service upload
 * leaves an admin-completed car completed. Nothing is deleted; the history stays. */
(() => {
  'use strict';
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || window.PDC_OPEN_ADMIN_COMPLETE) return;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const admin = () => String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'administrator';
  const MESSAGES = {
    administrator_required: 'Only an administrator can complete a vehicle this way.',
    reason_required: 'Enter a reason (at least 3 characters).',
    stock_confirmation_mismatch: 'The stock number you typed does not match this vehicle.',
    vehicle_version_conflict: 'This vehicle changed. Close this form, refresh the vehicle and try again.',
    vehicle_not_active: 'This vehicle is already completed or archived.',
    started_booking_must_be_completed_first: 'A started workshop job is running on this vehicle. Finish or stop it first.',
    vehicle_not_found: 'This vehicle could not be found.',
  };
  const dialog = document.createElement('dialog');
  dialog.className = 'location-override-dialog admin-complete-dialog';
  dialog.setAttribute('aria-labelledby', 'admin-complete-title');
  dialog.innerHTML = `<form><h2 id="admin-complete-title">Complete vehicle</h2><p data-complete-vehicle></p>
    <p class="subtle">The vehicle leaves the board and goes to Completed. Open workshop bookings are cancelled; a pending New Vehicles review is closed. Future service uploads leave it completed. Nothing is deleted.</p>
    <label>Type the stock number to confirm<input name="stock" autocomplete="off" required></label>
    <label>Reason<textarea name="reason" rows="2" maxlength="500" required></textarea></label>
    <p role="alert" data-complete-error></p>
    <footer><button type="button" data-complete-cancel>Cancel</button><button class="primary" type="submit">Complete vehicle</button></footer></form>`;
  document.body.appendChild(dialog);
  const form = dialog.querySelector('form');
  const error = dialog.querySelector('[data-complete-error]');
  let selected = null; let saving = false;
  function controls() { form.querySelectorAll('button, input, textarea').forEach(node => { node.disabled = saving; }); }
  function dismiss() { if (dialog.open) dialog.close(); selected = null; saving = false; form.reset(); error.textContent = ''; controls(); }
  function open(vehicle) {
    if (!admin() || saving || dialog.open || !vehicle?.__emailVehicleId) return;
    selected = { id: String(vehicle.__emailVehicleId), version: Number(vehicle.__emailVehicleVersion), stock: String(displayStockNumber(vehicle) || vehicle.stockNumber || ''), key: typeof vehicleKey === 'function' ? vehicleKey(vehicle) : '' };
    form.reset(); error.textContent = '';
    dialog.querySelector('[data-complete-vehicle]').textContent = `${selected.stock} · ${typeof vehicleCustomerName === 'function' ? vehicleCustomerName(vehicle) : ''}`;
    controls(); dialog.showModal();
  }
  async function save() {
    if (saving || !selected || !admin() || !dialog.open || !form.reportValidity()) return;
    const stock = form.elements.stock.value.trim(); const reason = form.elements.reason.value.trim();
    if (stock.replace(/\s+/g, '').toUpperCase() !== selected.stock.replace(/\s+/g, '').toUpperCase()) { error.textContent = MESSAGES.stock_confirmation_mismatch; return; }
    if (!Number.isFinite(selected.version) || selected.version < 1) { error.textContent = 'This vehicle has no version yet. Refresh the board and try again.'; return; }
    saving = true; controls(); error.textContent = '';
    const config = window.PDC_SUPABASE_CONFIG; const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '';
    try {
      if (!token) throw Error('Please sign in again.');
      const response = await fetch(config.url.replace(/\/$/, '') + '/rest/v1/rpc/admin_complete_vehicle_800', {
        method: 'POST', headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_vehicle_id: selected.id, p_expected_version: selected.version, p_confirmation_stock: stock, p_reason: reason, p_idempotency_key: crypto.randomUUID() }),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || result?.ok !== true) throw Error(MESSAGES[result?.code] || result?.code || result?.message || 'The vehicle could not be completed.');
      if (result.code !== 'vehicle_completed') throw Error('The response could not be verified. Refresh the board before trying again.');
      try { window.PDC_VEHICLE_SLIDEOUT?.close?.(); } catch (_) { /* the drawer may not be open */ }
      dismiss();
      if (typeof refreshEmailVehicleLocations === 'function') await refreshEmailVehicleLocations();
      if (typeof renderAll === 'function') renderAll();
    } catch (e) {
      saving = false; controls(); error.textContent = e.message || String(e);
    }
  }
  form.addEventListener('submit', event => { event.preventDefault(); void save(); });
  dialog.querySelector('[data-complete-cancel]').addEventListener('click', () => { if (!saving) dismiss(); });
  dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); else dismiss(); });
  window.PDC_OPEN_ADMIN_COMPLETE = open;
  window.PDC_ADMIN_COMPLETE_VERSION = '2026.11.01.r800';
})();
