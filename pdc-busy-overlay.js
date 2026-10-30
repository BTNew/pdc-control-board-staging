/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r714 (F324, Craig 29 Oct 13:12): a loading overlay over the page while something the user did is still saving or
 * loading (a chip dropped into a bay, a tick, a station move, a sign-off, opening a planner), so a slow save never looks
 * like a crash.
 *
 * How it decides: it wraps window.fetch once, before any other script loads. A request to the board's own Supabase
 * project is tracked when it starts within 2 seconds of a user action (click, drop, change, Enter / Space), or while a
 * tracked request is still running (the refresh that follows a save). Background polling, live refreshes and anything
 * the user did not start are not tracked, so the overlay never appears on its own.
 * The overlay shows only after 400 ms (a fast save shows nothing), blocks clicks while it is up (no double drops), and
 * after 25 seconds it steps aside to a small "Still working…" note so the page is never locked.
 * Other code can wrap its own long work: PDC_BUSY.track(promise, 'Saving…').
 * It reads and changes nothing: the wrapped fetch returns exactly what fetch returns. */
(function pdcBusyOverlay(root) {
  'use strict';
  const INTENT_MS = 2000;
  const SHOW_DELAY_MS = 400;
  const HIDE_DELAY_MS = 150;
  const STEP_ASIDE_MS = 25000;
  const READ_RPC = /\/rpc\/(get_|list_|read_|load_|search_)/i;
  // r726 (F336, Craig 29 Oct 14:06): background calls never raise the overlay. Moving between buckets logged page use
  // (record_pdc_usage_*), which showed "Saving…" and blocked taps; the Stock take shows its own ticks at once.
  const QUIET_RPC = /\/rpc\/(record_pdc_|pdc_my_sales_link|get_pdc_stock_take_|set_pdc_stock_take_)/i;
  const QUIET_VIEWS = new Set(['stock-take']);

  function classify(url, method) {
    const text = String(url || '');
    const verb = String(method || 'GET').toUpperCase();
    if (/\/storage\/v1\/object\//.test(text) && verb !== 'GET') return 'Uploading…';
    if (/\/rest\/v1\/rpc\//.test(text)) return READ_RPC.test(text) ? 'Loading…' : 'Saving…';
    return verb === 'GET' || verb === 'HEAD' ? 'Loading…' : 'Saving…';
  }
  // A request is ours when it goes to the board's Supabase project (REST, RPC, storage, functions).
  function isBoardRequest(url, projectUrl) {
    const text = String(url || '');
    if (!projectUrl) return /\.supabase\.co\/(rest|storage|functions)\/v1\//.test(text);
    return text.startsWith(String(projectUrl).replace(/\/$/, '') + '/');
  }
  function quiet(url, view) {
    return QUIET_RPC.test(String(url || '')) || QUIET_VIEWS.has(String(view || ''));
  }
  const api = { classify, isBoardRequest, quiet, INTENT_MS, SHOW_DELAY_MS, STEP_ASIDE_MS };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (!root || !root.document || typeof root.fetch !== 'function' || root.PDC_BUSY) return;

  const doc = root.document;
  const now = () => (root.performance && typeof root.performance.now === 'function' ? root.performance.now() : Date.now());
  let lastIntent = -Infinity;
  let pending = 0;
  let label = 'Loading…';
  let shownAt = 0;
  let showTimer = null;
  let hideTimer = null;
  let asideTimer = null;
  let el = null;

  const markIntent = event => {
    if (event.type === 'keydown' && event.key !== 'Enter' && event.key !== ' ') return;
    lastIntent = now();
  };
  ['pointerup', 'click', 'drop', 'change', 'submit', 'keydown'].forEach(type => doc.addEventListener(type, markIntent, true));

  function ensureElement() {
    if (el) return el;
    const style = doc.createElement('style');
    style.dataset.pdcBusy = '1';
    style.textContent = `
#pdc-busy{position:fixed;inset:0;z-index:2147483000;display:none;align-items:center;justify-content:center;background:rgba(241,245,249,.55);cursor:progress}
#pdc-busy.is-on{display:flex}
#pdc-busy .pdc-busy-box{display:flex;align-items:center;gap:12px;padding:14px 20px;border-radius:12px;background:#0f172a;color:#fff;font:700 15px/1.2 Arial,Helvetica,sans-serif;box-shadow:0 10px 30px rgba(15,23,42,.3)}
#pdc-busy .pdc-busy-spin{width:22px;height:22px;border:3px solid rgba(255,255,255,.35);border-top-color:#fff;border-radius:50%;animation:pdc-busy-spin .8s linear infinite}
#pdc-busy.is-aside{inset:auto 16px 16px auto;background:transparent;pointer-events:none}
@keyframes pdc-busy-spin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion: reduce){#pdc-busy .pdc-busy-spin{animation-duration:2.4s}}`;
    (doc.head || doc.documentElement).appendChild(style);
    el = doc.createElement('div');
    el.id = 'pdc-busy';
    el.setAttribute('role', 'status');
    el.setAttribute('aria-live', 'polite');
    el.innerHTML = '<div class="pdc-busy-box"><span class="pdc-busy-spin" aria-hidden="true"></span><span class="pdc-busy-text">Loading…</span></div>';
    (doc.body || doc.documentElement).appendChild(el);
    return el;
  }
  function paint() {
    const node = ensureElement();
    node.querySelector('.pdc-busy-text').textContent = node.classList.contains('is-aside') ? 'Still working…' : label;
  }
  function show() {
    showTimer = null;
    if (pending < 1) return;
    const node = ensureElement();
    node.classList.remove('is-aside');
    node.classList.add('is-on');
    shownAt = now();
    paint();
    clearTimeout(asideTimer);
    asideTimer = setTimeout(() => { if (pending > 0 && el) { el.classList.add('is-aside'); paint(); } }, STEP_ASIDE_MS);
  }
  function hide() {
    hideTimer = null;
    if (pending > 0) return;
    clearTimeout(asideTimer); asideTimer = null;
    if (el) el.classList.remove('is-on', 'is-aside');
  }
  const GENERIC = new Set(['Loading…', 'Saving…', 'Uploading…']);
  function begin(text) {
    pending += 1;
    // 30 Oct (Craig): a specific label from PDC_BUSY.track ("Starting Key 201…") stays up while its saves run;
    // only a generic label gives way to the fetch wrapper's Saving… / Uploading….
    if (pending === 1 || (GENERIC.has(label) && (text === 'Saving…' || text === 'Uploading…'))) label = text || 'Loading…';
    clearTimeout(hideTimer); hideTimer = null;
    if (el && el.classList.contains('is-on')) paint();
    else if (!showTimer) showTimer = setTimeout(show, SHOW_DELAY_MS);
  }
  function end() {
    pending = Math.max(0, pending - 1);
    if (pending > 0) return;
    clearTimeout(showTimer); showTimer = null;
    if (!hideTimer) hideTimer = setTimeout(hide, HIDE_DELAY_MS);
  }
  function track(work, text = 'Loading…') {
    begin(text);
    return Promise.resolve(work).finally(end);
  }

  const originalFetch = root.fetch.bind(root);
  function busyFetch(input, init) {
    let url = '';
    try { url = typeof input === 'string' ? input : (input && input.url) || String(input); } catch (_) { url = ''; }
    const method = (init && init.method) || (input && typeof input === 'object' && input.method) || 'GET';
    const projectUrl = root.PDC_SUPABASE_CONFIG && root.PDC_SUPABASE_CONFIG.url;
    const userStarted = now() - lastIntent <= INTENT_MS || pending > 0;
    if (!userStarted || !isBoardRequest(url, projectUrl) || quiet(url, doc.body && doc.body.dataset && doc.body.dataset.currentView)) return originalFetch(input, init);
    begin(classify(url, method));
    let result;
    try { result = originalFetch(input, init); } catch (error) { end(); throw error; }
    return Promise.resolve(result).finally(end);
  }
  root.fetch = busyFetch;
  root.PDC_BUSY = Object.freeze({ ...api, track, begin, end, get pending() { return pending; }, get shownAt() { return shownAt; } });
}(typeof window !== 'undefined' ? window : null));
