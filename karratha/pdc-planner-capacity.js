/* Shared bay efficiency and reviewed station gap-closing. No local booking writes. */
(function (root) {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const STAGES = new Set(['BUS_4X4', 'FITTING', 'ELECTRICAL', 'FABRICATION', 'HOIST', 'TINT', 'TYRE']);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  function percentage(value) {
    if (value === null || value === undefined || String(value).trim() === '') return null;
    const number = Number(value);
    return Number.isInteger(number) && number >= 10 && number <= 200 ? number : null;
  }
  function allocatedHours(baseHours, efficiency) {
    const percent = percentage(efficiency), base = Number(baseHours);
    return percent !== null && Number.isFinite(base) && base > 0 ? Math.ceil(Math.round(base * 60) * 100 / percent) / 60 : null;
  }
  function allocatedBaseMinutes(baseMinutes, efficiency) {
    const percent = percentage(efficiency), base = Number(baseMinutes);
    if (percent === null || !Number.isFinite(base) || base <= 0) return null;
    const minutes = base * 100 / percent, nearest = Math.round(minutes);
    // JSON decimal values can land one floating-point step above an integer
    // (1.1 base minutes at 10% is exactly 11 minutes in the database).
    const exact = Math.abs(minutes - nearest) <= Number.EPSILON * Math.max(1, Math.abs(minutes)) * 2;
    return (exact ? nearest : Math.ceil(minutes)) / 60;
  }
  function selectEfficiency(configurationRow, referenceRow) {
    const configured = percentage(configurationRow?.efficiency_percent), referenced = percentage(referenceRow?.efficiency_percent);
    if (referenced === null) return configured;
    if (configured === null) return referenced;
    const version = row => row?.version !== null && row?.version !== undefined && String(row.version).trim() !== ''
      && Number.isInteger(Number(row.version)) && Number(row.version) >= 0 ? Number(row.version) : null;
    const configuredVersion = version(configurationRow), referenceVersion = version(referenceRow);
    return configuredVersion !== null && referenceVersion !== null && configuredVersion > referenceVersion ? configured : referenced;
  }
  function requestInput(input = {}) {
    const stage = String(input.stage || '').toUpperCase();
    const bay = input.bay == null ? null : Number(input.bay);
    const efficiency = input.efficiency == null ? null : percentage(input.efficiency);
    if (!STAGES.has(stage) || (bay !== null && (!Number.isInteger(bay) || bay < 1))
      || (bay === null && input.efficiency != null) || (bay !== null && efficiency === null)) {
      throw Error('Enter an efficiency from 10% to 200% for the selected bay.');
    }
    return { stage, bay, efficiency };
  }
  function createController(options) {
    let generation = 0, running = null, preview = null;
    const context = options.getContext;
    const timer = options.setTimeout || setTimeout, clearTimer = options.clearTimeout || clearTimeout;
    const errorFor = (message, code) => Object.assign(Error(message), { code });
    function available(value, write = true) {
      return Boolean(value?.actor && value.token && value.config?.projectRef === PROJECT
        && value.config.url?.replace(/\/$/, '') === `https://${PROJECT}.supabase.co`
        && value.config.workshop?.sharedData === true && value.service?.getTrustedSnapshot?.()
        && value.service.getScope?.()?.stageCode === value.stage && STAGES.has(value.stage)
        && (!write || (['operator', 'administrator'].includes(value.role) && value.service.getState?.() === 'connected_editable')));
    }
    function capture(stage, write = true) {
      const current = context();
      if (current?.stage !== stage || !available(current, write)) throw errorFor('Refresh the planner and check that you have permission to change its bookings.', 'authority_unavailable');
      return { ...current, generation };
    }
    function current(owner, write = true) {
      const next = context();
      return Boolean(owner && owner.generation === generation && next && owner.actor === next.actor
        && owner.token === next.token && owner.config === next.config && owner.service === next.service
        && owner.stage === next.stage && available(next, write));
    }
    async function rpc(name, body, owner, write = true) {
      if (!current(owner, write)) throw errorFor('Your session or planner changed. Open the preview again.', 'session_changed');
      const abort = new AbortController();
      let timeout;
      try {
        const response = await Promise.race([
          options.fetch(owner.config.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
            method:'POST', signal:abort.signal,
            headers:{ apikey:owner.config.publishableKey, Authorization:`Bearer ${owner.token}`, 'Content-Type':'application/json' },
            body:JSON.stringify(body),
          }).then(async response => ({ ok:response.ok, result:await response.json() })),
          new Promise((_, reject) => { timeout = timer(() => { abort.abort(); reject(errorFor('The request timed out.', 'unconfirmed')); }, options.timeoutMs || 90000); }),
        ]);
        if (!current(owner, write)) throw errorFor('Your session or planner changed. Open the preview again.', 'session_changed');
        if (!response.ok || response.result?.ok !== true) {
          const code = response.result?.error || response.result?.code || 'rejected';
          throw errorFor(code === 'stale_preview' ? 'Bookings changed since this preview. Preview again before applying.'
            : response.result?.message || 'The planner could not complete this request. Refresh and try again.', code);
        }
        return response.result;
      } catch (error) {
        if (error.code) throw error;
        throw errorFor('The request result could not be confirmed.', 'unconfirmed');
      } finally { clearTimer(timeout); }
    }
    async function configuration(stage) {
      const owner = capture(stage, false);
      const result = await rpc('get_workshop_capacity_configuration', { p_stage_code:stage }, owner, false);
      if (!Array.isArray(result.bays) || result.stage_code !== stage || result.bays.some(bay => !Number.isInteger(Number(bay.bay_number))
        || Number(bay.bay_number) < 1 || percentage(bay.efficiency_percent) === null)
        || new Set(result.bays.map(bay => Number(bay.bay_number))).size !== result.bays.length) {
        throw errorFor('Bay efficiency could not be verified. Refresh the planner.', 'invalid_response');
      }
      return result;
    }
    async function makePreview(input) {
      if (running) throw errorFor('A planner request is already running.', 'busy');
      input = requestInput(input);
      const owner = capture(input.stage), operation = {};
      running = operation; preview = null;
      try {
        const result = await rpc('replan_workshop_capacity', { p_stage_code:input.stage, p_bay_number:input.bay,
          p_efficiency_percent:input.efficiency, p_apply:false, p_expected_plan_hash:null, p_idempotency_key:null }, owner);
        if (!Array.isArray(result.changes) || typeof result.can_apply !== 'boolean'
          || (result.can_apply && (typeof result.plan_hash !== 'string' || !result.plan_hash))) {
          throw errorFor('The booking preview was incomplete. No changes were requested.', 'invalid_response');
        }
        preview = { input, owner, result, key:options.uuid() };
        return result;
      } finally { if (running === operation) running = null; }
    }
    async function apply() {
      if (running) throw errorFor('A planner request is already running.', 'busy');
      const saved = preview;
      if (!saved || saved.result.can_apply !== true || (saved.input.bay === null && !saved.result.changes.length) || !current(saved.owner)) throw errorFor('Preview the current bookings before applying changes.', 'preview_required');
      const operation = {}; running = operation;
      try {
        const input = saved.input;
        const result = await rpc('replan_workshop_capacity', { p_stage_code:input.stage, p_bay_number:input.bay,
          p_efficiency_percent:input.efficiency, p_apply:true, p_expected_plan_hash:saved.result.plan_hash,
          p_idempotency_key:saved.key }, saved.owner);
        preview = null;
        return result;
      } catch (error) {
        preview = null;
        if (error.code === 'unconfirmed') error.message = 'The result could not be confirmed. Refresh the planner before trying again.';
        throw error;
      } finally { if (running === operation) running = null; }
    }
    return { configuration, preview:makePreview, apply,
      clearPreview() { preview = null; },
      invalidate() { generation++; preview = null; running = null; },
      canWrite:() => available(context()),
      get busy() { return Boolean(running); }, get canApply() { return Boolean(preview?.result.can_apply && (preview.input.bay !== null || preview.result.changes.length > 0) && current(preview.owner)); },
    };
  }
  const exported = { percentage, allocatedHours, allocatedBaseMinutes, selectEfficiency, requestInput, createController };
  if (typeof module !== 'undefined' && module.exports) { module.exports = exported; return; }
  if (!root.document || root.PDC_PLANNER_CAPACITY) return;
  const doc = root.document;
  const configurationCache = new Map();
  let dialog = null, dialogOwner = null, installed = false, rendering = false, actorGeneration = 0;
  const stageNow = () => String(root.__activeWorkshopPlannerStage || '').toUpperCase();
  const context = () => ({ actor:root.PDC_AUTH_CONTEXT?.userId, role:root.PDC_AUTH_CONTEXT?.role,
    token:typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '',
    config:root.PDC_SUPABASE_CONFIG, service:root.__workshopDataService, stage:stageNow() });
  const controller = createController({ getContext:context, fetch:(...args) => root.fetch(...args), uuid:() => root.crypto.randomUUID() });
  const stageLabel = stage => typeof pmbStageLabel === 'function' ? pmbStageLabel(stage) : stage;
  function referenceBay(stage, bay) {
    const cache = root.__workshopReferenceDataService?.getCachedWorkshopBays?.();
    if (!['connected_editable', 'connected_read_only'].includes(cache?.state)) return null;
    const code = `${stage}-BAY-${String(bay).padStart(2, '0')}`;
    const matches = (cache.rows || []).filter(row => row.code === code && row.is_active !== false);
    return matches.length === 1 ? matches[0] : null;
  }
  function efficiencyPercent(stage, bay) {
    const cached = configurationCache.get(stage), current = context();
    if (cached?.service === current.service && cached.actor === current.actor && cached.token === current.token && cached.status === 'ready') {
      const row = cached.data.bays.find(row => Number(row.bay_number) === Number(bay));
      if (row) return selectEfficiency(row, referenceBay(stage, bay));
    }
    return selectEfficiency(null, referenceBay(stage, bay));
  }
  function loadConfiguration(stage) {
    const current = context(), snapshot = current.service?.getTrustedSnapshot?.();
    if (!snapshot || !current.actor || !current.token || !STAGES.has(stage)) return;
    const previous = configurationCache.get(stage);
    if (previous?.service === current.service && previous.actor === current.actor && previous.token === current.token
      && (previous.status === 'loading' || previous.revision === snapshot.revision)) return;
    const request = { ...current, revision:snapshot.revision, status:'loading', generation:actorGeneration };
    configurationCache.set(stage, request);
    controller.configuration(stage).then(data => {
      if (configurationCache.get(stage) !== request || request.generation !== actorGeneration) return;
      Object.assign(request, { status:'ready', data });
    }).catch(error => {
      if (configurationCache.get(stage) === request) Object.assign(request, { status:'error', error:error.message });
    }).finally(() => { if (configurationCache.get(stage) === request) decorate(); });
  }
  function decorate() {
    if (rendering) return;
    const board = doc.querySelector('#workshop-planner-root .workshop-station-board:not(.is-focused-booking)');
    const stage = stageNow();
    if (!board || !STAGES.has(stage) || board.dataset.plannerStage !== stage) return;
    rendering = true;
    try {
      loadConfiguration(stage);
      const canWrite = controller.canWrite() && !controller.busy && !dialogOwner?.busy;
      let close = board.querySelector('[data-planner-close-gaps]');
      if (!close) {
        close = doc.createElement('button'); close.type = 'button'; close.className = 'small-button planner-close-gaps';
        close.dataset.plannerCloseGaps = stage; close.textContent = 'Close gaps';
        const refresh = board.querySelector('[data-workshop-refresh-vehicle]');
        if (refresh) refresh.insertAdjacentElement('afterend', close);
        else board.querySelector('.workshop-date-controls')?.appendChild(close);
      }
      close.disabled = !canWrite;
      close.title = canWrite ? 'Preview moving queued bookings into the next safe spaces from now.' : 'Planner changes require a current connection and operator access.';
      board.querySelectorAll('[data-workshop-bay-mechanic-stage]').forEach(select => {
        const bay = Number(select.dataset.workshopBayMechanicNumber);
        const label = select.closest('.workshop-bay-label');
        if (!label || select.dataset.workshopBayMechanicStage !== stage) return;
        let button = label.querySelector('[data-planner-bay-efficiency]');
        if (!button) {
          button = doc.createElement('button'); button.type = 'button'; button.className = 'planner-bay-efficiency';
          button.dataset.plannerBayEfficiency = String(bay); button.dataset.plannerCapacityStage = stage; label.appendChild(button);
        }
        const efficiency = efficiencyPercent(stage, bay);
        button.textContent = efficiency === null ? 'Efficiency —' : `Efficiency ${efficiency}%${efficiency === 100 ? ' · normal' : ''}`;
        button.disabled = !canWrite || efficiency === null;
        button.title = efficiency === null ? configurationCache.get(stage)?.error || 'Loading confirmed bay efficiency.'
          : 'Change the time allowed for this bay’s planned work. 100% is normal speed.';
      });
    } finally { rendering = false; }
  }
  function timeLabel(value) {
    const date = new Date(value);
    return Number.isNaN(+date) ? 'Unavailable' : date.toLocaleString('en-AU', { timeZone:'Australia/Perth', weekday:'short', day:'numeric', month:'short', hour:'numeric', minute:'2-digit' });
  }
  function summaryHtml(result, applied = false) {
    const changes = Array.isArray(result.changes) ? result.changes : [];
    const warnings = Array.isArray(result.warnings) ? result.warnings : [];
    const blocked = !applied && result.can_apply === false;
    return (blocked ? `<p class="planner-capacity-warning" role="alert">${esc(result.message || 'These bookings cannot be changed safely. Review the affected bookings before trying again.')}</p>`
      : `<p><strong>${applied ? 'Changes saved.' : `${changes.length} booking${changes.length === 1 ? '' : 's'} would change.`}</strong></p>`)
      + (!applied && !blocked && !changes.length ? '<p>No earlier safe moves are available. Gaps may remain while vehicles finish another station, wait for the 1-hour handover, or are unavailable. Each vehicle keeps its station order.</p>' : '')
      + (changes.length ? `<div class="planner-capacity-table"><table><thead><tr><th>Vehicle / bay</th><th>Current booking</th><th>${applied ? 'Updated booking' : 'Proposed booking'}</th></tr></thead><tbody>${changes.map(row => `<tr><td><strong>Stock ${esc(row.stock_number || '—')}</strong><small>${esc(stageLabel(row.stage_code))} · Bay ${esc(row.bay_number)}</small></td><td>${esc(timeLabel(row.old_start_at))}<small>to ${esc(timeLabel(row.old_end_at))}</small></td><td>${esc(timeLabel(row.new_start_at))}<small>to ${esc(timeLabel(row.new_end_at))}</small></td></tr>`).join('')}</tbody></table></div>` : '')
      + warnings.map(warning => `<p class="planner-capacity-warning">${esc(typeof warning === 'string' ? warning : warning.message || 'Check the booking sequence before applying.')}</p>`).join('')
      + (Number(result.unchanged_count) > 0 ? `<p>${esc(result.unchanged_count)} booking${Number(result.unchanged_count) === 1 ? '' : 's'} stay unchanged.</p>` : '');
  }
  function ensureDialog() {
    if (dialog) return dialog;
    dialog = doc.createElement('dialog'); dialog.className = 'planner-capacity-dialog'; dialog.setAttribute('aria-labelledby', 'planner-capacity-title');
    dialog.innerHTML = '<h2 id="planner-capacity-title"></h2><p class="planner-capacity-subtitle" data-capacity-subtitle></p><p data-capacity-explanation></p><label class="planner-capacity-input" data-capacity-input-row>Bay efficiency <input type="number" min="10" max="200" step="1" data-capacity-efficiency aria-label="Bay efficiency percentage"> %</label><p data-capacity-example></p><p>Uses workshop opening hours and keeps 1 hour between each vehicle’s jobs. Jobs already started, STOPPAGES and completed work stay in place.</p><div class="planner-capacity-result" data-capacity-result role="status" aria-live="polite"></div><footer><button type="button" class="small-button" data-capacity-close>Cancel</button><button type="button" class="small-button" data-capacity-preview>Preview changes</button><button type="button" class="primary" data-capacity-apply disabled>Apply changes</button></footer>';
    doc.body.appendChild(dialog);
    dialog.querySelector('[data-capacity-close]').addEventListener('click', () => { if (!dialogOwner?.busy) dialog.close(); });
    dialog.addEventListener('cancel', event => { if (dialogOwner?.busy) event.preventDefault(); });
    dialog.addEventListener('close', () => { if (!dialogOwner?.busy) { dialogOwner = null; controller.clearPreview(); } });
    dialog.querySelector('[data-capacity-preview]').addEventListener('click', () => void previewDialog());
    dialog.querySelector('[data-capacity-apply]').addEventListener('click', () => void applyDialog());
    dialog.querySelector('[data-capacity-efficiency]').addEventListener('input', () => {
      controller.clearPreview(); dialog.querySelector('[data-capacity-apply]').disabled = true;
      dialog.querySelector('[data-capacity-result]').textContent = 'Preview the new efficiency to see its effect on planned bookings.';
      updateExample();
    });
    return dialog;
  }
  function updateExample() {
    const percent = percentage(dialog.querySelector('[data-capacity-efficiency]').value);
    dialog.querySelector('[data-capacity-example]').textContent = percent === null ? 'Enter a whole percentage from 10 to 200.'
      : `100% is normal speed. At ${percent}%, a 4-hour estimate allows ${Number(allocatedHours(4, percent).toFixed(2))} hours in the bay.`;
  }
  function owns(owner) {
    const now = context();
    return dialogOwner === owner && owner.generation === actorGeneration && owner.actor === now.actor && owner.token === now.token
      && owner.service === now.service && owner.stage === now.stage && owner.config === now.config;
  }
  function setBusy(owner, busy) {
    owner.busy = busy;
    if (dialogOwner !== owner) return;
    for (const selector of ['[data-capacity-close]', '[data-capacity-preview]', '[data-capacity-efficiency]']) dialog.querySelector(selector).disabled = busy;
    dialog.querySelector('[data-capacity-apply]').disabled = busy || !controller.canApply;
    dialog.setAttribute('aria-busy', String(busy)); decorate();
  }
  function openDialog(stage, bay = null) {
    if (!controller.canWrite() || controller.busy || dialogOwner?.busy || stage !== stageNow()) return;
    const efficiency = bay === null ? null : efficiencyPercent(stage, bay);
    if (bay !== null && efficiency === null) return;
    ensureDialog(); controller.clearPreview();
    dialogOwner = { ...context(), generation:actorGeneration, stage, bay, busy:false };
    dialog.querySelector('h2').textContent = bay === null ? 'Close gaps' : 'Bay efficiency';
    dialog.querySelector('[data-capacity-subtitle]').textContent = `${stageLabel(stage)}${bay === null ? ' · all bays' : ` · Bay ${bay}`}`;
    dialog.querySelector('[data-capacity-explanation]').textContent = bay === null
      ? 'Preview filling the earliest safe spaces from now. Ready jobs can move ahead of waiting vehicles within the same bay.'
      : 'Allow more or less time for this bay’s queued and planned work. The preview shows the bookings that would move.';
    dialog.querySelector('[data-capacity-input-row]').hidden = bay === null;
    dialog.querySelector('[data-capacity-example]').hidden = bay === null;
    dialog.querySelector('[data-capacity-efficiency]').value = efficiency ?? 100;
    dialog.querySelector('[data-capacity-result]').textContent = 'Choose Preview changes to check the proposed schedule before saving.';
    dialog.querySelector('[data-capacity-close]').textContent = 'Cancel';
    dialog.querySelector('[data-capacity-preview]').hidden = false;
    dialog.querySelector('[data-capacity-apply]').hidden = false;
    setBusy(dialogOwner, false); updateExample(); dialog.showModal();
    if (bay === null) void previewDialog(); else dialog.querySelector('[data-capacity-efficiency]').focus();
  }
  async function previewDialog() {
    const owner = dialogOwner;
    if (!owner || owner.busy || !owns(owner)) return;
    setBusy(owner, true); dialog.querySelector('[data-capacity-result]').textContent = 'Checking available spaces and vehicle bookings…';
    try {
      const result = await controller.preview({ stage:owner.stage, bay:owner.bay,
        efficiency:owner.bay === null ? null : dialog.querySelector('[data-capacity-efficiency]').value });
      if (owns(owner)) dialog.querySelector('[data-capacity-result]').innerHTML = summaryHtml(result);
    } catch (error) {
      if (owns(owner)) dialog.querySelector('[data-capacity-result]').innerHTML = `<p class="planner-capacity-error">${esc(error.message)} No changes were requested.</p>`;
    } finally {
      if (owns(owner)) setBusy(owner, false);
      else if (dialogOwner === owner) { dialogOwner = null; dialog.close(); }
    }
  }
  async function applyDialog() {
    const owner = dialogOwner;
    if (!owner || owner.busy || !owns(owner) || !controller.canApply) return;
    setBusy(owner, true); dialog.querySelector('[data-capacity-result]').textContent = 'Saving the reviewed booking changes…';
    try {
      const result = await controller.apply();
      if (!owns(owner)) return;
      dialog.querySelector('[data-capacity-result]').innerHTML = summaryHtml(result, true);
      dialog.querySelector('[data-capacity-preview]').hidden = true; dialog.querySelector('[data-capacity-apply]').hidden = true;
      dialog.querySelector('[data-capacity-close]').textContent = 'Close';
      configurationCache.delete(owner.stage);
      let refreshTimeout;
      try {
        await Promise.race([
          Promise.all([owner.service.loadSnapshot('capacity_applied'),
            root.__workshopReferenceDataService?.listWorkshopBays?.(true)]),
          new Promise((_, reject) => { refreshTimeout = root.setTimeout(() => reject(Error('refresh_timeout')), 30000); }),
        ]);
        if (owns(owner) && !owner.service.getTrustedSnapshot?.()) throw Error('refresh_failed');
        if (owns(owner) && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
      } catch (_) {
        if (owns(owner)) dialog.querySelector('[data-capacity-result]').insertAdjacentHTML('beforeend', '<p class="planner-capacity-warning">The changes were saved. Refresh the planner to see the updated bookings.</p>');
      } finally { root.clearTimeout(refreshTimeout); }
    } catch (error) {
      if (owns(owner)) dialog.querySelector('[data-capacity-result]').innerHTML = `<p class="planner-capacity-error">${esc(error.message)}</p>`;
    } finally {
      if (owns(owner)) setBusy(owner, false);
      else if (dialogOwner === owner) { dialogOwner = null; dialog.close(); }
    }
  }
  function reset() {
    actorGeneration++; controller.invalidate(); configurationCache.clear(); dialogOwner = null;
    if (dialog?.open) dialog.close(); decorate();
  }
  function install() {
    if (installed) return true;
    if (typeof renderWorkshopPlanner !== 'function') return false;
    const original = renderWorkshopPlanner;
    renderWorkshopPlanner = function (...args) { const value = original.apply(this, args); decorate(); return value; };
    installed = true; decorate(); return true;
  }
  doc.addEventListener('load', event => { if (event.target?.id === 'workshop-planner-script') install(); }, true);
  doc.addEventListener('click', event => {
    const button = event.target.closest?.('[data-planner-close-gaps], [data-planner-bay-efficiency]');
    if (!button) return;
    event.preventDefault(); event.stopPropagation();
    if (!button.disabled) openDialog(button.dataset.plannerCloseGaps || button.dataset.plannerCapacityStage,
      button.dataset.plannerBayEfficiency ? Number(button.dataset.plannerBayEfficiency) : null);
  }, true);
  root.addEventListener('pdc-auth-locked', reset); root.addEventListener('pdc-auth-ready', reset);
  root.PDC_PLANNER_CAPACITY = Object.freeze({ efficiencyPercent,
    allocatedHours:(stage, bay, hours) => allocatedHours(hours, efficiencyPercent(stage, bay)),
    allocatedBaseMinutes:(stage, bay, minutes) => allocatedBaseMinutes(minutes, efficiencyPercent(stage, bay)),
    refresh:() => { configurationCache.clear(); decorate(); },
  });
  if (!install()) { let attempts = 0; const retry = () => { if (!install() && ++attempts < 80) root.setTimeout(retry, 250); }; retry(); }
})(typeof window === 'undefined' ? globalThis : window);
