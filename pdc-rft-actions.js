/* RFT handover UI. Writes use the existing scoped services; email is draft-only. */
(() => {
  'use strict';
  const STAGING = 'cdsmnqxtyyoeoznmbidd';
  const paths = {
    check: '<path d="m5 12 4 4L19 6"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/>',
    truck: '<path d="M3 6h11v11H3zM14 10h4l3 4v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  };
  function icon(kind) {
    return `<svg class="rft-action-icon" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${paths[kind]}</svg>`;
  }
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function outlookBody(prepared) {
    return String(prepared.text || '').replace(/The QC completion photo is attached\.[\r\n]*/g, '');
  }
  function openOutlook(prepared, navigate = url => { window.location.href = url; }) {
    const recipient = String(prepared.recipient_email || '').trim();
    if (!recipient || /[\r\n]/.test(recipient)) throw new Error('A valid salesperson email is required.');
    const url = `mailto:${encodeURIComponent(recipient)}?subject=${encodeURIComponent(prepared.subject || '')}&body=${encodeURIComponent(outlookBody(prepared))}`;
    navigate(url);
    return url;
  }
  function collected(v) {
    return Boolean(v.rftCollectedAt) || ['collected','completed'].includes(String(v.pdcLifecycleState || v.lifecycleState || '').toLowerCase())
      || ['collected','completed'].includes(String(v.pdcLocation || '').toLowerCase());
  }
  function qcSigned(v) {
    return v.__emailVehicleServerAuthoritative === true && Boolean(v.__emailVehicleId)
      && v.pdcQcComplete === true && Boolean(v.rftTransferredAt);
  }
  function ready(v) {
    return qcSigned(v) && Number.isFinite(Date.parse(v.rftConfirmedAt))
      && Number.isFinite(Date.parse(v.pdcQcCompleteAt))
      && Date.parse(v.rftConfirmedAt) >= Date.parse(v.pdcQcCompleteAt);
  }
  function controls(v, { key, allowed, authority, inFlight, collectionEnabled }) {
    const checked = qcSigned(v);
    const released = ready(v);
    const pickedUp = collected(v);
    const hasDraft = Boolean(v.rftTransportDraft?.draft_id);
    const canEmail = allowed && authority && released && !inFlight && (!pickedUp || hasDraft);
    const canCollect = allowed && authority && released && !pickedUp && collectionEnabled && !inFlight;
    return `<span class="rft-transport-controls rft-actions-clean" role="group" aria-label="RFT handover">
      <span class="rft-action rft-qc-status ${checked ? 'is-ready' : 'is-pending'}" role="status" title="${checked ? 'QC signed off' : 'Awaiting authoritative QC sign-off'}">${icon(checked ? 'check' : 'clock')}<span>${checked ? 'QC’d' : 'Awaiting QC'}</span></span>
      ${released ? `<span class="rft-action rft-ready-status is-ready" role="status" title="PMB confirmed ready for transport">${icon('check')}<span>RFT’d</span></span>` : `<button type="button" class="rft-action rft-release-action" data-pmb-rft-release-key="${esc(key)}" ${allowed && authority && checked && !pickedUp && !inFlight ? '' : 'disabled'} title="PMB: confirm this vehicle is ready for transport">Mark RFT’d</button>`}
      <button type="button" class="rft-action rft-email-action" data-rft-transport-booked-key="${esc(key)}" ${canEmail ? '' : 'disabled'} title="${hasDraft ? 'Open the unsent salesperson email in Outlook' : 'Prepare the unsent salesperson email in Outlook'}">${icon('mail')}<span>${inFlight ? 'Please wait…' : 'Email salesperson'}</span></button>
      ${pickedUp ? `<span class="rft-action rft-collected-status" role="status">${icon('check')}<span>Collected</span></span>` : `<button type="button" class="rft-action rft-collect-action" data-rft-collected-key="${esc(key)}" ${canCollect ? '' : 'disabled'} title="${canCollect ? 'Confirm the vehicle has physically left PMB' : 'Prepare the salesperson email with QC photo first'}">${icon('truck')}<span>Mark collected</span></button>`}
    </span>`;
  }
  const bytes = base64 => Uint8Array.from(atob(String(base64 || '').replace(/\s/g,'')), c => c.charCodeAt(0));
  async function hash(value) {
    return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',value)), b => b.toString(16).padStart(2,'0')).join('');
  }
  async function verifyDraft(data, vehicleId) {
    if (!data || data.vehicle_id !== vehicleId || !data.draft_id || data.mime_content_type !== 'message/rfc822'
        || data.delivery_enabled !== false || data.sent_at != null || data.delivered_at != null
        || !data.photo_receipt_id || !/^[A-Za-z0-9._-]{1,180}[.]eml$/.test(data.draft_filename || '')) throw new Error('Draft identity or file type could not be verified.');
    const mimeBytes = bytes(data.mime_base64);
    if (mimeBytes.length < 1 || mimeBytes.length > 2*1024*1024 || mimeBytes.length !== Number(data.mime_byte_length)
        || await hash(mimeBytes) !== data.mime_sha256) throw new Error('Email integrity check failed. No file was opened.');
    const mime = new TextDecoder().decode(mimeBytes);
    const boundary = mime.match(/^Content-Type: multipart\/mixed; boundary="([^"\r\n]+)"/mi)?.[1];
    if (!boundary || !/^X-Unsent: 1\r?$/mi.test(mime)) throw new Error('The email is not a supported unsent draft.');
    const parts = mime.split(`--${boundary}`);
    const attachmentParts = parts.filter(p => /Content-Disposition: attachment;/i.test(p));
    if (attachmentParts.length !== 1) throw new Error('The QC photo attachment is missing or ambiguous.');
    const photoPart = attachmentParts[0];
    const split = photoPart.indexOf('\r\n\r\n');
    const type = photoPart.match(/Content-Type: (image\/(?:jpeg|png|webp|gif))/i)?.[1]?.toLowerCase();
    if (split < 0 || !type || type !== String(data.photo_content_type).toLowerCase()
        || !/Content-Transfer-Encoding: base64/i.test(photoPart.slice(0,split))) throw new Error('The photo format could not be verified.');
    const photo = bytes(photoPart.slice(split+4).trim());
    if (photo.length !== Number(data.photo_byte_length) || photo.length < 1 || photo.length > 1048576
        || await hash(photo) !== data.photo_sha256) throw new Error('QC photo integrity check failed. No email was opened.');
    const textPart = parts.find(p => /Content-Type: text\/plain/i.test(p));
    const text = textPart && /Content-Transfer-Encoding: base64/i.test(textPart)
      ? new TextDecoder().decode(bytes(textPart.slice(textPart.indexOf('\r\n\r\n')+4).trim())) : null;
    if (!text || text !== data.text_body) throw new Error('Email body does not match the saved draft presentation.');
    if (/please (?:arrange|book(?: for)?) transport/i.test(text)) throw new Error('The old transport-request wording is still present. Refresh before opening this draft.');
    return { ...data, mimeBytes, photo, photoType:type, text };
  }
  // Pure helpers are also used in Node and browser regressions.
  if (typeof module === 'object' && module.exports) module.exports = { controls, qcSigned, ready, collected, verifyDraft, outlookBody, openOutlook };
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== STAGING
      || typeof rftTransportControlsHtml !== 'function') return;

  const sessions = new Map();
  let dialog;
  let currentView;
  let previousFocus;
  function dismiss() {
    if (dialog?.open) dialog.close();
    currentView = null;
    previousFocus?.focus?.();
  }
  function reviewWindow(stock) {
    previousFocus = document.activeElement;
    if (dialog) dialog.remove();
    dialog = document.createElement('dialog');
    dialog.className = 'rft-email-review';
    dialog.setAttribute('aria-labelledby','rft-email-review-title');
    dialog.innerHTML = `<header><div><h2 id="rft-email-review-title">Email salesperson</h2><p>Stock ${esc(stock)} · Unsent draft</p></div><button type="button" class="rft-dialog-close" aria-label="Close email review">×</button></header><div class="rft-email-review-content" role="status">Preparing the email and QC photo…</div>`;
    dialog.querySelector('.rft-dialog-close').onclick = dismiss;
    dialog.addEventListener('cancel',dismiss);
    document.body.appendChild(dialog);
    dialog.showModal();
    return dialog;
  }
  async function copyPhoto(img, notice) {
    try {
      if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') throw new Error('Clipboard unavailable');
      const png = new Promise((resolve, reject) => {
        const draw = () => {
          try {
            const canvas = document.createElement('canvas');
            canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
            canvas.getContext('2d').drawImage(img, 0, 0);
            canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error('Photo unavailable')), 'image/png');
          } catch (error) { reject(error); }
        };
        if (img.complete && img.naturalWidth) draw();
        else { img.onload = draw; img.onerror = () => reject(new Error('Photo unavailable')); }
      });
      await navigator.clipboard.write([new ClipboardItem({'image/png': png})]);
      notice.textContent = 'Photo copied. Paste it into the Outlook message with Ctrl+V before sending.';
    } catch (_error) {
      notice.textContent = 'Photo could not be copied automatically. Right-click the photo, choose Copy image, then paste it into Outlook.';
    }
  }
  function showPrepared(target, prepared) {
    if (target !== dialog || !target.open) return false;
    currentView = prepared;
    const content = target.querySelector('.rft-email-review-content');
    content.removeAttribute('role');
    content.innerHTML = `<dl><dt>To</dt><dd>${esc(prepared.recipient_email)}</dd><dt>Subject</dt><dd>${esc(prepared.subject)}</dd></dl>
      <pre class="rft-email-body"></pre>
      <section class="rft-email-attachment"><div>${icon('check')}<strong>QC completion photo</strong></div><img alt="Verified QC completion photo"/><small>${Math.ceil(prepared.photo.length/1024)} KB · verified against the stored QC photo</small></section>
      <p class="rft-email-open-note" role="status">Outlook has been requested, just like Email an update. Use Copy QC photo, then paste it into the message before sending. Nothing has been sent by the Board.</p>
      <button type="button" class="rft-email-copy-photo">Copy QC photo</button>
      <button type="button" class="rft-email-open-file">Open Outlook again</button>`;
    content.querySelector('pre').textContent = outlookBody(prepared);
    // A data URL avoids exposing private storage links and is allowed by the existing CSP.
    let binary=''; for (let i=0;i<prepared.photo.length;i+=8192) binary+=String.fromCharCode(...prepared.photo.subarray(i,i+8192));
    content.querySelector('img').src = `data:${prepared.photoType};base64,${btoa(binary)}`;
    content.querySelector('.rft-email-copy-photo').onclick = () => {
      if (currentView===prepared) return copyPhoto(content.querySelector('img'), content.querySelector('.rft-email-open-note'));
    };
    content.querySelector('.rft-email-open-file').onclick = () => { if (currentView===prepared) openOutlook(prepared); };
    openOutlook(prepared); // Same direct compose handoff as Email an update.
    return true;
  }
  function message(code) {
    const known = {
      not_authenticated:'Sign in again before preparing the email.',
      not_authorized:'An approved operator or administrator must prepare the email.',
      salesperson_email_required:'Assign the correct salesperson and email address first.',
      qc_photo_storage_missing:'The saved QC photo could not be read. No attachment was substituted.',
      qc_photo_bytes_mismatch:'The QC photo did not match the saved evidence. No email was opened.',
      vehicle_version_conflict:'This vehicle changed in another session. Refresh and retry.',
      rft_confirmation_required:'PMB must mark this vehicle RFT’d before emailing the salesperson.',
      qc_signoff_required:'Complete mobile QC sign-off before PMB marks this vehicle RFT’d.',
      rft_confirmation_stale_version:'This vehicle changed. Refresh and retry the PMB release.',
      vehicle_not_in_rft:'This vehicle is no longer in RFT.',
    };
    return known[code] || `The email could not be prepared (${code || 'unknown error'}). No email was sent.`;
  }
  const authority = v => durableRftLifecycleEnabled() && v.__emailVehicleServerAuthoritative === true
    && Boolean(v.__emailVehicleId) && Number(v.__emailVehicleVersion)>0
    && typeof app.emailVehicleLocationService?.bookRftTransport739 === 'function'
    && typeof app.emailVehicleLocationService?.readRftTransportDraft739 === 'function'
    && typeof app.emailVehicleLocationService?.setRftConfirmation736 === 'function'
    && typeof app.emailVehicleLocationService?.collectRftTransport734 === 'function';
  rftTransportControlsHtml = function(v={}) {
    const key=vehicleKey(v);
    return controls(v,{key,allowed:vehicleRftLifecycleRoleAllowed(),authority:authority(v),
      inFlight:sessions.has(key)||app.rftTransportActionInFlight?.has(`rft:${key}`),
      collectionEnabled:vehicleRftEmailEvidenceReady(v)});
  };
  vehicleRftTransitionAuthoritative = qcSigned;
  vehicleRftConfirmationActive = ready;
  rftTransportEmailStatusLabel = v => v.rftTransportDraft?.draft_id ? 'Email draft prepared — not sent by the Board' : '';
  rftTransportCollectionDisabledReason = v => !authority(v) ? 'Shared staging authority unavailable'
    : !vehicleRftEmailEvidenceReady(v) ? 'Prepare the salesperson email and QC photo first' : '';

  async function openEmail(key) {
    let v=selectedVehicle(key);
    if (!v || !vehicleRftLifecycleRoleAllowed() || !authority(v) || !ready(v) || sessions.has(key)
        || app.rftTransportActionInFlight?.has(`rft:${key}`)) return false;
    const actor=window.PDC_AUTH_CONTEXT?.userId;
    const target=reviewWindow(displayStockNumber(v)||key);
    sessions.set(key,true); renderAll();
    const service=app.emailVehicleLocationService;
    try {
      let result=await service.readRftTransportDraft739(v.__emailVehicleId);
      if (!result.ok && result.code==='transport_draft_not_found') {
        if (collected(v)) throw new Error('A new draft cannot be created after collection.');
        const created=await service.bookRftTransport739(v.__emailVehicleId,Number(v.__emailVehicleVersion),salespersonAssignmentIdempotencyKey());
        if (!created.ok && created.code!=='transport_draft_already_exists') throw new Error(message(created.code));
        await refreshEmailVehicleLocations();
        result=await service.readRftTransportDraft739(v.__emailVehicleId);
      }
      if (actor!==window.PDC_AUTH_CONTEXT?.userId) throw new Error('The signed-in user changed. Reopen the draft after signing in.');
      if (!result.ok) throw new Error(message(result.code));
      const prepared=await verifyDraft(result.data,v.__emailVehicleId);
      if (actor!==window.PDC_AUTH_CONTEXT?.userId) return false;
      return showPrepared(target,prepared);
    } catch(error) {
      if (target===dialog && target.open) target.querySelector('.rft-email-review-content').textContent=error.message;
      return false;
    } finally { sessions.delete(key); renderAll(); }
  }
  markRftTransportBooked = function(key='',booked=true) { return booked ? openEmail(key) : Promise.resolve(false); };
  downloadRftTransportDraft = openEmail;
  markRftConfirmation = async function(key='',confirmed=true) {
    const v=selectedVehicle(key);
    if (!confirmed || !v || !vehicleRftLifecycleRoleAllowed() || !authority(v)
        || !qcSigned(v) || ready(v) || collected(v) || sessions.has(key)) return false;
    const action=beginRftTransportAction(key); if(!action) return false;
    try {
      if (!window.confirm(`Confirm PMB has checked Stock ${displayStockNumber(v)||key} and it is ready for transport?\n\nThis records RFT’d and enables Email salesperson.`)) return false;
      const result=await app.emailVehicleLocationService.setRftConfirmation736(v.__emailVehicleId,Number(v.__emailVehicleVersion),true,salespersonAssignmentIdempotencyKey());
      if (!rftTransportActionIsCurrent(action)) return false;
      if (!result?.ok) { window.alert(message(result?.code)); await refreshEmailVehicleLocations(); return false; }
      const data=result.data;
      if (data?.vehicle_id!==v.__emailVehicleId || data.rft_confirmed!==true || !data.receipt_id
          || Number(data.vehicle_version_after)<=Number(v.__emailVehicleVersion)) throw new Error('PMB release could not be verified. Refresh before retrying.');
      const refreshed=await refreshEmailVehicleLocations();
      if (!refreshed) window.alert('PMB release was saved. Refresh to load its confirmed status.');
      return Boolean(refreshed);
    } catch(error) {window.alert(error.message); return false;}
    finally {finishRftTransportAction(action); renderAll();}
  };
  document.addEventListener('click',event=>{
    const button=event.target.closest?.('[data-pmb-rft-release-key]');
    if (!button || button.disabled) return;
    event.stopPropagation();
    void markRftConfirmation(button.dataset.pmbRftReleaseKey,true);
  });
  const priorRftHeader=vehicleLocationsRftHeaderHtml;
  vehicleLocationsRftHeaderHtml=()=>priorRftHeader().replace('<span>RFT’d</span>','<span>QC’d</span><span>RFT’d</span>');
  const rftBucket=VEHICLE_LOCATION_BUCKET_DEFS.find(bucket=>bucket.key==='rft');
  if(rftBucket) rftBucket.hint='QC signed off · PMB must mark RFT’d before emailing sales';
  markRftVehicleCollected = async function(key='',confirmed=true) {
    const v=selectedVehicle(key); const service=app.emailVehicleLocationService;
    if (!confirmed || !v || collected(v) || !vehicleRftLifecycleRoleAllowed() || !authority(v)
        || !ready(v) || !vehicleRftEmailEvidenceReady(v) || sessions.has(key)) return false;
    if (!window.confirm(`Confirm ${displayStockNumber(v)||key} has physically left PMB?\n\nThis moves it to Collected and starts the transport timer. It does not send an email.`)) return false;
    const action=beginRftTransportAction(key); if(!action) return false;
    try {
      const result=await service.collectRftTransport734(v.__emailVehicleId,Number(v.__emailVehicleVersion),salespersonAssignmentIdempotencyKey());
      if(!rftTransportActionIsCurrent(action)) return false;
      if(!result.ok) { window.alert(message(result.code)); await refreshEmailVehicleLocations(); return false; }
      if(result.data?.vehicle_id!==v.__emailVehicleId || result.data.current_location!=='Collected') throw new Error('Collection response could not be verified. Refresh before retrying.');
      const ok=await refreshEmailVehicleLocations();
      if(!ok) window.alert('Collection was recorded, but the refreshed row was unavailable. Refresh before doing anything else.');
      return Boolean(ok);
    } catch(error) {window.alert(error.message); return false;}
    finally {finishRftTransportAction(action); renderAll();}
  };
  const oldDetailRow=rftVehicleDetailRow;
  rftVehicleDetailRow=function(v={}) {
    return oldDetailRow(v).replace(/<div class="wide rft-detail-actions">[\s\S]*?<\/span><\/div>/,
      `<div class="wide rft-detail-actions"><b>Transport handover</b>${rftTransportControlsHtml(v)}</div>`);
  };
  window.addEventListener('pdc-auth-locked',()=>{dismiss();});
  window.PDC_RFT_ACTIONS_VERSION='2026.09.10.04';
  renderAll();
})();
