/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r441 (F52): reload an open page once after a new release is published, but
// only when nobody would lose work. The Pages build writes version.json and a
// <meta name="pdc-build"> tag into each entry page; this compares the two.
// Read-only: it never writes data, and it does nothing when version.json is
// missing or malformed.
(function (root) {
  const SETTINGS = Object.freeze({
    pollMs: 60000,            // normal check interval
    maxBackoffMs: 15 * 60000, // longest wait after repeated fetch failures
    idleMs: 10000,            // no typing for this long before a reload
    retryMs: 2000,            // re-check a deferred reload this often
    focusThrottleMs: 15000,   // at most one extra check per 15 s on focus/visibility
    guardKey: 'pdc.auto-reload.v1:'
  });
  const BUILD_PATTERN = /^[A-Za-z0-9._-]{6,80}$/;

  function validBuild(value) {
    return typeof value === 'string' && BUILD_PATTERN.test(value) ? value : null;
  }

  // version.json body -> build id, or null when missing/malformed.
  function parseVersion(body) {
    let data = body;
    if (typeof data === 'string') {
      try { data = JSON.parse(data); } catch (_) { return null; }
    }
    if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
    return validBuild(data.build);
  }

  // Pure decision. Returns {action: 'none' | 'defer' | 'reload', reason}.
  function decide(s) {
    const server = validBuild(s.server);
    const loaded = validBuild(s.loaded);
    if (!server) return { action: 'none', reason: 'no-version' };
    if (!loaded) return { action: 'none', reason: 'baseline' };
    if (server === loaded) return { action: 'none', reason: 'current' };
    if (s.alreadyReloadedFor === server) return { action: 'none', reason: 'loop-guard' };
    if (s.guardUnavailable) return { action: 'none', reason: 'loop-guard-unavailable' };
    if (s.writesInFlight > 0) return { action: 'defer', reason: 'saving' };
    if (s.unsaved) return { action: 'defer', reason: 'unsaved' };
    if (s.modalOpen) return { action: 'defer', reason: 'modal-open' };
    if (s.pointerActive) return { action: 'defer', reason: 'dragging' };
    if (s.fieldFocused) return { action: 'defer', reason: 'field-focused' };
    if (Number.isFinite(s.lastTypingAt) && s.now - s.lastTypingAt < SETTINGS.idleMs) return { action: 'defer', reason: 'recent-typing' };
    return { action: 'reload', reason: 'new-version' };
  }

  function nextDelay(failures) {
    const n = Math.max(0, Math.min(Number(failures) || 0, 10));
    return Math.min(SETTINGS.pollMs * Math.pow(2, n), SETTINGS.maxBackoffMs);
  }

  const NON_TEXT_INPUTS = /^(?:button|checkbox|radio|submit|reset|image|range|color|file|hidden)$/i;
  function isTextField(el) {
    if (!el || !el.tagName) return false;
    const tag = String(el.tagName).toUpperCase();
    if (tag === 'TEXTAREA' || tag === 'SELECT') return true;
    if (tag === 'INPUT') return !NON_TEXT_INPUTS.test(el.type || 'text');
    return el.isContentEditable === true;
  }

  function start(win) {
    if (!win || !win.document || win.__pdcAutoReloadStarted) return null;
    win.__pdcAutoReloadStarted = true;
    const doc = win.document;
    const now = () => Date.now();
    const meta = doc.querySelector && doc.querySelector('meta[name="pdc-build"]');
    let loaded = validBuild(meta && meta.getAttribute && meta.getAttribute('content'));
    const scriptSrc = (doc.currentScript && doc.currentScript.src) || '';
    let versionUrl;
    try { versionUrl = new URL('version.json', scriptSrc || win.location.href).href; } catch (_) { return null; }
    const guardKey = SETTINGS.guardKey + (win.location && win.location.pathname || '/');
    const nativeFetch = typeof win.fetch === 'function' ? win.fetch : null;
    const state = { server: null, failures: 0, writesInFlight: 0, lastTypingAt: NaN, pointerActive: false, pointerAt: 0, lastCheckAt: 0, last: null };
    let pollTimer = null, retryTimer = null, checking = false;

    function readGuard() {
      try { return { value: win.sessionStorage.getItem(guardKey), ok: true }; } catch (_) { return { value: null, ok: false }; }
    }
    // A page that loaded the build it was sent to has finished its reload.
    const startGuard = readGuard();
    if (startGuard.ok && loaded && startGuard.value === loaded) { try { win.sessionStorage.removeItem(guardKey); } catch (_) {} }

    // Count writes (non-GET fetches, which includes Supabase saves) so a reload
    // never cuts one off. Pure pass-through otherwise.
    if (nativeFetch) {
      win.fetch = function pdcTrackedFetch(input, init) {
        const method = String((init && init.method) || (input && typeof input === 'object' && input.method) || 'GET').toUpperCase();
        const write = !/^(?:GET|HEAD|OPTIONS)$/.test(method);
        if (write) state.writesInFlight += 1;
        let result;
        try { result = nativeFetch.apply(win, arguments); } catch (error) { if (write) state.writesInFlight -= 1; throw error; }
        if (write) {
          const done = () => { state.writesInFlight = Math.max(0, state.writesInFlight - 1); };
          Promise.resolve(result).then(done, done);
        }
        return result;
      };
    }

    function modalOpen() {
      if (!doc.querySelectorAll) return false;
      for (const el of doc.querySelectorAll('dialog[open], [aria-modal="true"]')) {
        if (el.hidden || (el.closest && el.closest('[hidden]'))) continue;
        if (typeof el.getClientRects === 'function' && el.getClientRects().length === 0) continue;
        return true;
      }
      return false;
    }
    // Reuse every page's existing "unsaved changes" rule: they all cancel
    // beforeunload when they hold drafts or a save is pending.
    function unsaved() {
      if (win.PDC_UNSAVED_WORK === true) return true;
      if (typeof win.Event !== 'function' || typeof win.dispatchEvent !== 'function') return false;
      try {
        const probe = new win.Event('beforeunload', { cancelable: true });
        win.dispatchEvent(probe);
        return probe.defaultPrevented === true;
      } catch (_) { return true; }
    }

    function snapshot() {
      const guard = readGuard();
      return {
        loaded, server: state.server, now: now(), lastTypingAt: state.lastTypingAt,
        writesInFlight: state.writesInFlight, pointerActive: state.pointerActive && now() - state.pointerAt < 30000,
        fieldFocused: isTextField(doc.activeElement), modalOpen: modalOpen(),
        unsaved: unsaved(), alreadyReloadedFor: guard.value, guardUnavailable: !guard.ok
      };
    }

    function evaluate() {
      if (retryTimer) { win.clearTimeout(retryTimer); retryTimer = null; }
      if (!state.server || !loaded || state.server === loaded) return state.last = { action: 'none', reason: state.server ? 'current' : 'no-version' };
      const result = decide(snapshot());
      state.last = result;
      if (result.action === 'defer') retryTimer = win.setTimeout(evaluate, SETTINGS.retryMs);
      if (result.action === 'reload') {
        try { win.sessionStorage.setItem(guardKey, state.server); } catch (_) { return state.last = { action: 'none', reason: 'loop-guard-unavailable' }; }
        win.location.reload();
      }
      return result;
    }

    function schedule() {
      if (pollTimer) win.clearTimeout(pollTimer);
      pollTimer = win.setTimeout(() => { check().finally(schedule); }, nextDelay(state.failures));
    }

    async function check() {
      if (checking || !nativeFetch) return state.last;
      if (win.navigator && win.navigator.onLine === false) return state.last;
      checking = true;
      state.lastCheckAt = now();
      try {
        const response = await nativeFetch.call(win, versionUrl + (versionUrl.includes('?') ? '&' : '?') + 't=' + now(), { cache: 'no-store', credentials: 'same-origin' });
        const build = response && response.ok ? parseVersion(await response.text()) : null;
        if (!build) { state.failures += 1; return state.last = { action: 'none', reason: 'no-version' }; }
        state.failures = 0;
        state.server = build;
        if (!loaded) loaded = build; // page without the build tag: first answer is the baseline
        return evaluate();
      } catch (_) {
        state.failures += 1;
        return state.last = { action: 'none', reason: 'fetch-failed' };
      } finally { checking = false; }
    }

    const typed = () => { state.lastTypingAt = now(); };
    for (const name of ['keydown', 'input', 'change', 'paste', 'compositionstart']) doc.addEventListener(name, typed, true);
    doc.addEventListener('pointerdown', () => { state.pointerActive = true; state.pointerAt = now(); }, true);
    for (const name of ['pointerup', 'pointercancel']) doc.addEventListener(name, () => { state.pointerActive = false; }, true);
    const onShowOrHide = () => {
      if (now() - state.lastCheckAt >= SETTINGS.focusThrottleMs) check(); else evaluate();
    };
    doc.addEventListener('visibilitychange', onShowOrHide);
    win.addEventListener('focus', onShowOrHide);
    win.addEventListener('online', () => check());
    schedule();

    const api = Object.freeze({
      check, evaluate,
      status: () => ({ loaded, server: state.server, failures: state.failures, writesInFlight: state.writesInFlight, last: state.last, nextDelayMs: nextDelay(state.failures) })
    });
    win.PDCAutoReload = api;
    return api;
  }

  const exported = { SETTINGS, parseVersion, decide, nextDelay, isTextField, start };
  if (typeof module !== 'undefined' && module.exports) module.exports = exported;
  if (root && root.document) start(root);
})(typeof window !== 'undefined' ? window : undefined);
