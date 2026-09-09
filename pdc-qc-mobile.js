/* Phone-only QC presentation. Existing authenticated services remain the write
 * authority; no local vehicle transitions, synthetic completion or new grants. */
(() => {
  'use strict';
  if (typeof renderQualityControlPage !== 'function'
      || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd') {
    document.documentElement.classList.remove('pdc-qc-phone');
    return;
  }
  const media = window.matchMedia('(max-width: 900px), (pointer: coarse) and (max-width: 1024px)');
  const desktopRender = renderQualityControlPage;
  const desktopShowView = showView;
  const desktopSignoff = qcPageSignoff;
  const cachePrefix = 'pdc.qc.photo.receipt.v1:';
  const rejected = new Map();
  const rejectionDrafts = new Map();
  const retryFiles = new Map();
  let refreshBusy = false;
  let fileInput = null;
  let photoTarget = '';
  const e = value => escapeHtml(String(value ?? ''));
  const mobile = () => media.matches;
  const canWrite = () => ['operator', 'administrator'].includes(String(window.PDC_AUTH_CONTEXT?.role || '').toLowerCase());
  const rowFor = key => qcPageVehicles().find(row => qcPageVehicleKey(row) === key);
  const pending = key => [...qcPageOperationPending.keys()].some(value => value.startsWith(`${key}::`));
  const busy = key => qcPagePhotoUploadInFlight.has(key) || qcPageRejectInFlight.has(key) || qcPageSignoffInFlight.has(key);
  const knownLine = line => line.stageCode !== 'UNALLOCATED_MAPPING_REVIEW'
    && line.estimatedHours !== null && line.estimatedHours !== undefined && line.estimatedHours !== ''
    && Number.isFinite(Number(line.estimatedHours));
  const inspected = row => qcPageAllOperationLinesComplete(row) && qcPageOperationLines(row).every(knownLine);
  const cacheKey = row => `${cachePrefix}${window.PDC_AUTH_CONTEXT?.userId || ''}:${row.__emailVehicleId}:${row.pdcQcRetestCycleId || 'initial'}`;

  function rememberPhoto(row, photo) {
    // Receipt metadata only, never photo bytes or credentials. The finalisation
    // RPC must still validate this receipt against the server's immutable record.
    try {
      const { url, ...metadata } = photo;
      sessionStorage.setItem(cacheKey(row), JSON.stringify({ at: Date.now(), photo: metadata }));
    } catch (_) { /* Private mode/storage limits must not lose the in-memory receipt. */ }
  }
  function restorePhoto(row) {
    const key = qcPageVehicleKey(row);
    if (qcPhotoEvidence.has(key)) return;
    try {
      const value = JSON.parse(sessionStorage.getItem(cacheKey(row)) || 'null');
      if (value && Date.now() - value.at < 8 * 60 * 60 * 1000
          && value.photo.vehicle_id === row.__emailVehicleId
          && String(value.photo.cycle_id || '') === String(row.pdcQcRetestCycleId || '')
          && qcPhotoEvidenceIsValid(value.photo)) {
        qcPhotoEvidence.set(key, { ...value.photo, restoredReceipt: true });
      }
    } catch (_) { /* Malformed/unavailable browser cache is not accepted. */ }
  }
  function forgetPhoto(row) {
    if (!row) return;
    try { sessionStorage.removeItem(cacheKey(row)); } catch (_) {}
    qcPhotoEvidence.delete(qcPageVehicleKey(row));
    retryFiles.delete(qcPageVehicleKey(row));
  }
  function feedback(key, kind, message) {
    qcPageFeedback.set(key, { kind, message });
    renderQualityControlPage();
  }
  function ensureFileInput() {
    if (fileInput?.isConnected) return fileInput;
    fileInput = document.createElement('input');
    fileInput.type = 'file';
    fileInput.accept = 'image/*';
    fileInput.id = 'qc-mobile-photo-input';
    fileInput.className = 'qc-phone-file-input';
    fileInput.setAttribute('aria-label', 'Take or choose a QC completion photo');
    // Kept OUTSIDE the rerendered host. Foreground refresh while iOS's camera
    // or library is open must not replace the input and lose its change event.
    document.querySelector('.qc-page-panel').appendChild(fileInput);
    fileInput.addEventListener('change', () => {
      const file = fileInput.files?.[0];
      const target = photoTarget;
      fileInput.value = ''; // Selecting the same file after a failure must fire again.
      if (file && target) void attachPhoto(target, file);
    });
    return fileInput;
  }
  function readPreview(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      const timer = setTimeout(() => { reader.abort(); reject(new Error('photo_read_failed')); }, 15000);
      reader.onload = () => { clearTimeout(timer); resolve(String(reader.result || '')); };
      reader.onerror = reader.onabort = () => { clearTimeout(timer); reject(new Error('photo_read_failed')); };
      reader.readAsDataURL(file);
    });
  }
  function photoError(code) {
    if (/version.*conflict|VERSION_CONFLICT/.test(code)) return 'The vehicle changed while saving. Refresh QC, then retry the photo.';
    if (/not_authenticated|not_authorized|auth_subject/.test(code)) return 'Your session needs to be refreshed. Sign in again before uploading.';
    if (code === 'qc_photo_already_recorded') return 'A photo is already recorded for this vehicle. Complete sign-off in the session that saved it; it cannot be overwritten here.';
    if (/compression|invalid_input|photo_read_failed/.test(code)) return 'This photo could not be prepared. Choose a JPEG or PNG under 10 MB, or take another photo.';
    if (/receipt/.test(code)) return 'The photo was not confirmed by the server. Sign-off stays blocked; retry the upload.';
    return 'Photo upload was not confirmed. Check your connection and tap Retry photo. No QC sign-off was recorded.';
  }
  async function attachPhoto(key, selectedFile) {
    const actor = window.PDC_AUTH_CONTEXT?.userId;
    let row = rowFor(key);
    if (!row || !canWrite() || busy(key)) return false;
    restorePhoto(row);
    if (qcPhotoEvidenceIsValid(qcPhotoEvidence.get(key))) return false;
    let file = selectedFile;
    if (!file?.type && /\.(jpe?g|png|webp|heic|heif)$/i.test(file?.name || '')) {
      const ext = file.name.split('.').pop().toLowerCase();
      file = new File([file], file.name, { type: `image/${ext === 'jpg' ? 'jpeg' : ext}`, lastModified: file.lastModified });
    }
    if (!file || !String(file.type).startsWith('image/') || file.size < 1 || file.size > 10485760) {
      feedback(key, 'error', 'Choose a photo between 1 byte and 10 MB. Nothing was uploaded.');
      return false;
    }
    const disabled = qcPagePhotoDisabledReason(row, key);
    if (disabled) { feedback(key, 'error', disabled); return false; }
    retryFiles.set(key, file);
    qcPagePhotoUploadInFlight.add(key); // Before FileReader: no double uploads or checkbox races.
    qcPhotoEvidence.set(key, { status: 'uploading', originalFilename: file.name });
    feedback(key, 'saving', 'Preparing and uploading photo…');
    try {
      const preview = await readPreview(file);
      qcPhotoEvidence.set(key, { status: 'uploading', originalFilename: file.name, url: preview });
      renderQualityControlPage();
      await qcPageOperationMutationChain;
      const refreshed = await refreshEmailVehicleLocations();
      row = rowFor(key);
      if (actor !== window.PDC_AUTH_CONTEXT?.userId) return false;
      if (!refreshed || !row) throw new Error('qc_photo_vehicle_refresh_failed');
      const service = app.emailVehicleLocationService;
      if (typeof service?.uploadQcPhotoEvidence !== 'function') throw new Error('qc_photo_service_unavailable');
      const result = row.pdcQcRetestCycleId
        ? await service.uploadQcPhotoEvidence(row.__emailVehicleId, row.__emailVehicleVersion, row.pdcQcRetestCycleId, file)
        : await service.uploadQcPhotoEvidence(row.__emailVehicleId, row.__emailVehicleVersion, file);
      if (actor !== window.PDC_AUTH_CONTEXT?.userId) return false;
      const data = result?.data;
      const photo = { ...data, status: 'accepted', photoReceiptId: data?.photo_receipt_id,
        byteLength: data?.byte_length, originalByteLength: data?.original_byte_length,
        imageWidth: data?.image_width, imageHeight: data?.image_height,
        originalFilename: data?.original_filename || file.name, url: preview };
      if (!result?.ok || data?.vehicle_id !== row.__emailVehicleId
          || String(data?.cycle_id || '') !== String(row.pdcQcRetestCycleId || '')
          || !qcPhotoEvidenceIsValid(photo)) throw new Error(result?.code || 'qc_photo_receipt_invalid');
      qcPhotoEvidence.set(key, photo);
      rememberPhoto(row, photo);
      retryFiles.delete(key);
      feedback(key, 'saved', 'Photo saved. Your completion evidence is recorded.');
      return true;
    } catch (error) {
      if (actor !== window.PDC_AUTH_CONTEXT?.userId) return false;
      qcPhotoEvidence.set(key, { ...qcPhotoEvidence.get(key), status: 'error', photoReceiptId: '' });
      feedback(key, 'error', photoError(String(error?.message || '')));
      return false;
    } finally {
      qcPagePhotoUploadInFlight.delete(key);
      renderQualityControlPage();
    }
  }

  function openRejection(key, lineIdentity = '') {
    const row = rowFor(key);
    if (!row || !canWrite() || busy(key) || pending(key)) return;
    const line = qcPageOperationLines(row).find(item => item.lineIdentity === lineIdentity);
    const reason = line ? `Not fitted: ${line.description}`.slice(0, 240) : '';
    rejectionDrafts.set(key, { lineIdentity: line?.lineIdentity || '', description: line?.description || '', reason });
    renderQualityControlPage();
    document.querySelector('.qc-phone-reject-panel')?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }
  async function rejectVehicle(key) {
    let row = rowFor(key);
    const draft = rejectionDrafts.get(key);
    if (!row || !draft || !canWrite() || busy(key) || pending(key)) return false;
    const reason = String(draft.reason || '').trim().replace(/\s+/g, ' ');
    if (reason.length < 3 || reason.length > 240) { feedback(key, 'error', 'Enter a rejection reason of 3–240 characters.'); return false; }
    const service = app.emailVehicleLocationService;
    if (typeof service?.rejectQcVehicleToPmb !== 'function') { feedback(key, 'error', 'QC rejection is unavailable. Nothing was changed.'); return false; }
    qcPageRejectInFlight.add(key);
    feedback(key, 'saving', 'Rejecting QC and returning the vehicle to stoppages…');
    try {
      await qcPageOperationMutationChain;
      row = rowFor(key);
      if (!row) throw new Error('Vehicle is no longer awaiting QC. Refresh the list.');
      const line = qcPageOperationLines(row).find(item => item.lineIdentity === draft.lineIdentity);
      // A previously checked item must not remain checked when reported missing.
      // A failed second step leaves it unchecked and reports failure, never RFT.
      if (line?.completed) {
        const unchecked = await service.setQcOperationCompletion(row.__emailVehicleId, row.__emailVehicleVersion,
          line.lineIdentity, Number(line.lineVersion || 0), false, crypto.randomUUID());
        if (!unchecked?.ok || unchecked.data?.line?.completed !== false || !qcPageReceiptLineApply(row, line.lineIdentity, unchecked)) {
          throw new Error('The missing item could not be unchecked. Refresh and retry; QC has not been rejected.');
        }
      }
      const stock = displayStockNumber(row) || key;
      const result = await service.rejectQcVehicleToPmb(row.__emailVehicleId, stock, row.__emailVehicleVersion, reason, crypto.randomUUID());
      const receipt = result?.data;
      if (!result?.ok || receipt?.vehicle_id !== row.__emailVehicleId || !receipt?.receipt_id
          || receipt.current_location !== 'PMB' || receipt.workshop_status !== 'stoppage') {
        throw new Error(/version/i.test(result?.code || '')
          ? 'The vehicle changed in another session. Refresh and retry the rejection.'
          : 'QC rejection was not confirmed. Refresh and check the vehicle before retrying.');
      }
      rejected.set(key, Number(receipt.vehicle_version_after));
      forgetPhoto(row);
      rejectionDrafts.delete(key);
      qcSelectedVehicleKey = '';
      qcPageNotice = `${stock} — QC rejected. Returned to PMB Stoppage / Fix First. Reason: ${reason}`;
      await refreshEmailVehicleLocations();
      window.scrollTo(0, 0);
      return true;
    } catch (error) {
      feedback(key, 'error', error.message || 'QC rejection failed. Nothing was signed off.');
      return false;
    } finally {
      qcPageRejectInFlight.delete(key);
      renderQualityControlPage();
    }
  }
  async function signoff(key) {
    const row = rowFor(key);
    if (!row || !canWrite() || busy(key) || pending(key) || rejectionDrafts.has(key) || !inspected(row)) return false;
    restorePhoto(row);
    if (!qcPhotoEvidenceIsValid(qcPhotoEvidence.get(key))) return false;
    try {
      const task = desktopSignoff(key); // Existing protected QC → RFT action.
      renderQualityControlPage();
      const result = await task;
      if (result === true || result?.ok === true) {
        forgetPhoto(row);
        await refreshEmailVehicleLocations();
        window.scrollTo(0, 0);
        return true;
      }
      feedback(key, 'error', 'Sign-off was not completed. Your saved photo receipt is retained; refresh and check the checklist.');
      return false;
    } catch (_) {
      feedback(key, 'error', 'Sign-off was not confirmed. Refresh QC before retrying. Your saved photo receipt is retained.');
      return false;
    } finally { renderQualityControlPage(); }
  }
  async function refresh() {
    if (refreshBusy) return;
    refreshBusy = true;
    renderQualityControlPage();
    try {
      const ok = await refreshEmailVehicleLocations();
      if (!ok) qcPageNotice = 'Could not refresh QC. Check your connection and try again.';
    } catch (_) { qcPageNotice = 'Could not refresh QC. Check your connection and try again.'; }
    finally { refreshBusy = false; renderQualityControlPage(); }
  }

  function vehicleCard(row) {
    const key = qcPageVehicleKey(row);
    const lines = qcPageOperationLines(row);
    const count = lines.filter(line => line.completed).length;
    return `<button type="button" class="qc-phone-vehicle" data-qc-open-vehicle="${e(key)}">
      <span class="qc-phone-card-top"><strong>${e(displayStockNumber(row) || key)}</strong><span aria-hidden="true">→</span></span>
      <span class="qc-phone-model">${e(displayVehicle(row) || 'Vehicle')}</span>
      <span class="qc-phone-muted">${e(vehicleCustomerName(row) || row.customerName || 'Customer unavailable')}</span>
      <span class="qc-phone-card-bottom"><span>${e(row.jobCardNumber || row.jobcard || 'Job card unavailable')}</span><span class="qc-phone-pill ${count === lines.length ? 'is-ready' : ''}">${count ? `${count}/${lines.length} checked` : 'Awaiting inspection'}</span></span>
    </button>`;
  }
  function checklist(row) {
    const key = qcPageVehicleKey(row);
    const locked = busy(key) || rejectionDrafts.has(key) || !canWrite();
    return qcPageOperationLines(row).map((line, index) => {
      const waiting = qcPageOperationPending.has(qcPagePendingKey(key, line.lineIdentity));
      const enabled = !locked && !waiting && knownLine(line);
      return `<div class="qc-phone-item ${line.completed ? 'is-checked' : ''}" data-qc-line-identity="${e(line.lineIdentity)}" ${waiting ? 'aria-busy="true"' : ''}>
        <label class="qc-phone-check"><input type="checkbox" data-qc-operation-check="${e(key)}" data-qc-line-identity="${e(line.lineIdentity)}" ${line.completed ? 'checked' : ''} ${enabled ? '' : 'disabled'} aria-label="${e(`Verify fitted: ${line.description}`)}">
          <span><strong>${e(line.description || line.operationNo || `Item ${index + 1}`)}</strong><small>${e(qcPageStageLabel(line.stageCode))} · ${waiting ? 'Saving…' : line.completed ? 'Checked' : knownLine(line) ? 'Check fitted and correct' : 'Hours / station review required'}</small></span>
        </label>
        <button type="button" class="qc-phone-missing" data-qc-not-fitted="${e(line.lineIdentity)}" ${locked || pending(key) ? 'disabled' : ''} aria-label="${e(`Not fitted: ${line.description}`)}">Not fitted</button>
      </div>`;
    }).join('');
  }
  function rejectionPanel(key) {
    const draft = rejectionDrafts.get(key);
    if (!draft) return '';
    return `<section class="qc-phone-reject-panel" role="region" aria-label="Confirm QC rejection">
      <h3>Reject QC?</h3><p>This returns the vehicle to <strong>PMB Stoppage / Fix First</strong> for repairs. It will not move to RFT.</p>
      ${draft.description ? `<p class="qc-phone-reject-item">${e(draft.description)}</p>` : ''}
      <label for="qc-phone-reason">Reason for rejection</label><textarea id="qc-phone-reason" maxlength="240" rows="3" ${busy(key) ? 'disabled' : ''}>${e(draft.reason)}</textarea>
      <div class="qc-phone-reject-buttons"><button type="button" data-qc-cancel-reject ${busy(key) ? 'disabled' : ''}>Cancel</button><button type="button" class="qc-phone-danger" data-qc-confirm-reject ${busy(key) ? 'disabled' : ''}>${qcPageRejectInFlight.has(key) ? 'Rejecting…' : 'Reject QC → Stoppage'}</button></div>
    </section>`;
  }
  function detail(row) {
    const key = qcPageVehicleKey(row);
    restorePhoto(row);
    const lines = qcPageOperationLines(row);
    const checked = lines.filter(line => line.completed).length;
    const photo = qcPhotoEvidence.get(key);
    const valid = qcPhotoEvidenceIsValid(photo);
    const photoBusy = qcPagePhotoUploadInFlight.has(key);
    const currentFeedback = qcPageFeedback.get(key);
    const ready = inspected(row) && valid && !busy(key) && !pending(key) && !rejectionDrafts.has(key) && canWrite();
    const photoBlocked = valid || busy(key) || pending(key) || rejectionDrafts.has(key) || !canWrite() || Boolean(qcPagePhotoDisabledReason(row, key));
    return `<div class="qc-phone-detail" data-qc-vehicle-key="${e(key)}">
      <section class="qc-phone-summary"><p class="qc-phone-kicker">${e(row.jobCardNumber || row.jobcard || 'QC inspection')}</p><h2>${e(displayStockNumber(row) || key)}</h2><p class="qc-phone-model">${e(displayVehicle(row) || 'Vehicle')}</p><p class="qc-phone-muted">${e(vehicleCustomerName(row) || row.customerName || 'Customer unavailable')}${vehicleKeyNumber(row) ? ` · Key ${e(vehicleKeyNumber(row))}` : ''}</p></section>
      <div class="qc-phone-progress-heading"><h3>Inspection checklist</h3><span>${checked} of ${lines.length} checked</span></div>
      <progress class="qc-phone-inspection-progress" max="${lines.length || 1}" value="${checked}" aria-label="Inspection progress"></progress>
      <div class="qc-phone-feedback ${currentFeedback?.kind === 'error' ? 'is-error' : ''}" role="status" aria-live="polite">${e(currentFeedback?.message || (!canWrite() ? 'Read-only account. An approved operator must complete QC.' : 'Tick each item only after checking the vehicle.'))}</div>
      <div class="qc-phone-checklist">${checklist(row)}</div>
      ${rejectionPanel(key)}
      <section class="qc-phone-photo"><div class="qc-phone-photo-heading"><h3>Completion photo</h3>${valid ? '<span class="qc-phone-pill is-ready">✓ Saved</span>' : ''}</div><p class="qc-phone-muted">Take a photo or choose one from your library. Up to 10 MB.</p>
        ${photo?.url ? `<img class="qc-phone-photo-preview" src="${e(photo.url)}" alt="Completion photo for ${e(displayStockNumber(row))}">` : ''}
        ${valid ? `<p class="qc-phone-photo-saved">${e(photo.originalFilename || 'Completion photo')}<br>${photo.restoredReceipt ? 'Saved receipt retained for final server validation.' : 'Photo and evidence receipt saved.'}</p>` : `<label class="qc-phone-picker ${photoBlocked ? 'is-disabled' : ''}" for="qc-mobile-photo-input" aria-disabled="${photoBlocked}">${photoBusy ? 'Preparing & uploading…' : 'Take or choose photo'}</label>`}
        ${photoBusy ? '<progress class="qc-phone-upload-progress" aria-label="Uploading completion photo"></progress><p class="qc-phone-muted">Keep this screen open while the photo saves.</p>' : ''}
        ${photo?.status === 'error' && retryFiles.has(key) ? `<button type="button" class="qc-phone-retry" data-qc-retry-photo ${photoBlocked ? 'disabled' : ''}>Retry photo</button>` : ''}
        ${!valid && !photoBusy && qcPagePhotoDisabledReason(row, key) ? `<p class="qc-phone-muted">${e(qcPagePhotoDisabledReason(row, key))}</p>` : ''}
      </section>
      <button class="qc-phone-reject-other" type="button" data-qc-reject-other ${busy(key) || pending(key) || !canWrite() ? 'disabled' : ''}>Reject QC / other fault</button>
      <footer class="qc-phone-finish"><p>${ready ? 'Checklist checked and photo saved.' : photoBusy ? 'Wait for the photo to finish saving.' : pending(key) ? 'Wait for checklist changes to save.' : !inspected(row) ? 'Check every item before signing off.' : !valid ? 'Save a completion photo before signing off.' : 'Resolve the pending action before signing off.'}</p><button type="button" data-qc-signoff="${e(key)}" ${ready ? '' : 'disabled'}>${qcPageSignoffInFlight.has(key) ? 'Signing off…' : 'Sign off QC → RFT'}</button></footer>
    </div>`;
  }
  function renderPhone() {
    const host = document.querySelector('#qc-page-host');
    if (!host) return;
    const input = ensureFileInput();
    const rows = qcPageVehicles().filter(row => {
      const key = qcPageVehicleKey(row);
      if (!rejected.has(key)) return true;
      if (row.__emailVehicleVersion > rejected.get(key)) { rejected.delete(key); return true; }
      return false; // Suppress only a receipt-confirmed rejection awaiting readback.
    });
    if (!rows.some(row => qcPageVehicleKey(row) === qcSelectedVehicleKey)) qcSelectedVehicleKey = '';
    const selected = rows.find(row => qcPageVehicleKey(row) === qcSelectedVehicleKey);
    const key = selected ? qcPageVehicleKey(selected) : '';
    const focus = document.activeElement;
    const reasonFocused = focus?.id === 'qc-phone-reason';
    const selection = reasonFocused ? [focus.selectionStart, focus.selectionEnd] : null;
    if (reasonFocused && rejectionDrafts.has(key)) rejectionDrafts.get(key).reason = focus.value;
    host.innerHTML = `<div class="qc-phone-app">
      <header class="qc-phone-header"><div>${selected ? '<button type="button" class="qc-phone-back" data-qc-back-to-list>← QC vehicles</button>' : '<h1>QC <span class="qc-phone-environment">Staging</span></h1>'}<p>${selected ? 'Vehicle inspection' : `${rows.length} vehicle${rows.length === 1 ? '' : 's'} awaiting QC`}</p></div><div class="qc-phone-header-actions"><button type="button" data-qc-phone-refresh ${refreshBusy || (key && (busy(key) || pending(key))) ? 'disabled' : ''}>${refreshBusy ? 'Refreshing…' : 'Refresh'}</button><button type="button" class="qc-phone-signout" data-qc-phone-signout>Sign out</button></div></header>
      ${qcPageNotice ? `<div class="qc-phone-notice" role="status" aria-live="polite">${e(qcPageNotice)}</div>` : ''}
      ${navigator.onLine === false ? '<div class="qc-phone-notice is-error" role="alert">Offline. Reconnect before saving QC or uploading photos.</div>' : ''}
      ${selected ? detail(selected) : `<section class="qc-phone-list" aria-label="Vehicles awaiting QC">${rows.length ? rows.map(vehicleCard).join('') : `<div class="qc-phone-empty"><h2>${app.emailVehicleLocationError ? 'QC list unavailable' : 'No vehicles awaiting QC'}</h2><p>${app.emailVehicleLocationError ? 'Check your connection and tap Refresh.' : 'Vehicles will appear here when ready for inspection.'}</p></div>`}</section>`}
    </div>`;
    const bind = (selector, event, fn) => host.querySelectorAll(selector).forEach(node => node.addEventListener(event, fn));
    bind('[data-qc-open-vehicle]', 'click', event => { qcSelectedVehicleKey = event.currentTarget.dataset.qcOpenVehicle; qcPageNotice = ''; window.history.pushState({ pdcView: 'qc', qcMobileVehicle: qcSelectedVehicleKey }, '', '#/qc'); renderQualityControlPage(); window.scrollTo(0, 0); });
    bind('[data-qc-back-to-list]', 'click', () => { qcSelectedVehicleKey = ''; window.history.replaceState({ pdcView: 'qc' }, '', '#/qc'); renderQualityControlPage(); window.scrollTo(0, 0); });
    bind('[data-qc-phone-refresh]', 'click', () => { void refresh(); });
    bind('[data-qc-phone-signout]', 'click', () => { document.querySelector('#pdc-auth-signout')?.click(); });
    bind('[data-qc-operation-check]', 'change', event => {
      const node = event.currentTarget;
      if (!canWrite() || busy(key) || rejectionDrafts.has(key)) { renderQualityControlPage(); return; }
      qcPageQueueOperationState(key, node.dataset.qcLineIdentity, node.checked, node);
    });
    bind('[data-qc-not-fitted]', 'click', event => { openRejection(key, event.currentTarget.dataset.qcNotFitted); });
    bind('[data-qc-reject-other]', 'click', () => { openRejection(key); });
    bind('#qc-phone-reason', 'input', event => { const draft = rejectionDrafts.get(key); if (draft) draft.reason = event.currentTarget.value; });
    bind('[data-qc-cancel-reject]', 'click', () => { rejectionDrafts.delete(key); renderQualityControlPage(); });
    bind('[data-qc-confirm-reject]', 'click', () => { void rejectVehicle(key); });
    bind('[data-qc-retry-photo]', 'click', () => { void attachPhoto(key, retryFiles.get(key)); });
    bind('[data-qc-signoff]', 'click', () => { void signoff(key); });
    bind('.qc-phone-picker', 'click', event => {
      if (event.currentTarget.getAttribute('aria-disabled') === 'true') { event.preventDefault(); return; }
      photoTarget = key;
      input.disabled = false;
    });
    input.disabled = !selected || busy(key) || pending(key) || !canWrite() || qcPhotoEvidenceIsValid(qcPhotoEvidence.get(key));
    if (reasonFocused) {
      const textarea = host.querySelector('#qc-phone-reason');
      textarea?.focus({ preventScroll: true });
      textarea?.setSelectionRange(...selection);
    }
  }
  renderQualityControlPage = function () { return mobile() ? renderPhone() : desktopRender(); };
  showView = function (view, options) { return desktopShowView(mobile() ? 'qc' : view, options); };
  function updateMode() {
    document.documentElement.classList.toggle('pdc-qc-phone', mobile());
    if (mobile()) {
      const authFragment = window.location.hash && !window.location.hash.startsWith('#/');
      showView('qc', { historyMode: authFragment ? 'none' : 'replace' });
    } else if (app.currentView === 'qc') desktopRender();
  }
  media.addEventListener?.('change', updateMode);
  window.addEventListener('pdc-auth-ready', updateMode);
  window.addEventListener('popstate', event => {
    if (!mobile()) return;
    qcSelectedVehicleKey = String(event.state?.qcMobileVehicle || '');
    renderQualityControlPage();
  });
  window.addEventListener('beforeunload', event => {
    if (qcPagePhotoUploadInFlight.size || qcPageRejectInFlight.size || qcPageSignoffInFlight.size || qcPageOperationPending.size) {
      event.preventDefault(); event.returnValue = '';
    }
  });
  window.addEventListener('pdc-auth-locked', event => {
    if (event.detail?.reason === 'session-revalidate') return;
    qcPhotoEvidence.clear(); retryFiles.clear(); rejectionDrafts.clear(); rejected.clear();
    try { Object.keys(sessionStorage).filter(key => key.startsWith(cachePrefix)).forEach(key => sessionStorage.removeItem(key)); } catch (_) {}
  });
  window.addEventListener('online', () => { if (mobile()) void refresh(); });
  window.addEventListener('offline', () => { if (mobile()) renderQualityControlPage(); });
  window.PDC_QC_MOBILE_VERSION = '2026.09.09.05';
  updateMode();
})();
