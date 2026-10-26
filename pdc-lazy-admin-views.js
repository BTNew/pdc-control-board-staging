/* © 2026 Specialise Pty Ltd ATFT Specialise Trust. See LICENSE. */
// Load independent read-only reports only when opened. Existing report controllers
// retain their access checks, requests, rendering and auth-reset behaviour.
(function (root) {
  'use strict';
  const VERSION = '2026.10.26.opt1';
  const DEFINITIONS = Object.freeze([
    { name: 'PdcUpdateHistory', view: 'update-history', title: 'Update history', script: 'pdc-update-history.js?v=2026.09.30.01', css: 'pdc-update-history.css?v=2026.09.30.01' },
    { name: 'PdcFittingStats', view: 'fitting-stats', title: 'Fitting statistics', script: 'pdc-fitting-stats.js?r489=2026.10.23.r489', css: 'pdc-fitting-stats.css?r489=2026.10.23.r489' }
  ]);
  function install(win, definition) {
    const doc = win.document;
    let active = false, locked = false, generation = 0, loading = null, opening = null;
    const identity = () => [win.PDC_AUTH_CONTEXT?.userId, win.PDC_AUTH_CONTEXT?.role,
      win.__pdcCachedAccessToken, win.PDC_SUPABASE_CONFIG?.url, win.PDC_SUPABASE_CONFIG?.publishableKey].join('\u0000');
    const allowed = () => !locked && !!win.PDC_AUTH_CONTEXT?.userId &&
      win.PDC_AUTH_CONTEXT?.role === 'administrator' && !!win.__pdcCachedAccessToken;
    const host = () => doc.getElementById(definition.view + '-content');
    const viewIsActive = () => !!doc.getElementById(definition.view)?.classList.contains('active');
    const installed = () => {
      const controller = win[definition.name];
      return controller && controller !== stub && typeof controller.open === 'function' ? controller : null;
    };
    function clear() { host()?.replaceChildren(); }
    function syncAccess() {
      const access = allowed();
      const nav = doc.getElementById('nav-' + definition.view);
      const section = doc.getElementById(definition.view);
      if (nav) nav.hidden = !access;
      if (section) section.hidden = !access;
      if (!access) { active = false; generation++; opening = null; clear(); }
      return access;
    }
    function message(failed) {
      const target = host();
      if (!target) return;
      target.replaceChildren();
      const text = doc.createElement('p');
      text.setAttribute('role', 'status');
      text.textContent = failed ? definition.title + ' could not load. Please try again.' : 'Loading ' + definition.title.toLowerCase() + '…';
      target.appendChild(text);
      if (failed) {
        const retry = doc.createElement('button');
        retry.type = 'button'; retry.className = 'small-button'; retry.textContent = 'Try again';
        retry.addEventListener('click', () => { void stub.open(); });
        target.appendChild(retry);
      }
    }
    function asset(kind, url) {
      return new Promise((resolve, reject) => {
        const id = 'pdc-lazy-' + definition.view + '-' + kind;
        const existing = doc.getElementById(id);
        if (existing?.dataset.loaded === 'true') { resolve(); return; }
        const node = doc.createElement(kind === 'script' ? 'script' : 'link');
        node.id = id;
        if (kind === 'script') { node.src = url; node.async = true; }
        else { node.rel = 'stylesheet'; node.href = url; }
        let timer, settled = false;
        const done = (error) => {
          if (settled) return;
          settled = true;
          win.clearTimeout(timer);
          node.onload = node.onerror = null;
          if (error) { node.remove(); reject(new Error('Report asset unavailable')); }
          else { node.dataset.loaded = 'true'; resolve(); }
        };
        node.onload = () => done(false);
        node.onerror = () => done(true);
        timer = win.setTimeout(() => done(true), 20000);
        doc.head.appendChild(node);
      });
    }
    function load() {
      // A timed-out script may finish later; reuse its controller instead of
      // installing duplicate listeners on the next attempt.
      const existingController = installed();
      if (existingController) return Promise.resolve(existingController);
      if (!loading) {
        // Await styling first so a delayed stylesheet cannot expose an unstyled report.
        loading = asset('style', definition.css).then(() => asset('script', definition.script))
          .then(() => {
            const controller = installed();
            if (!controller) {
              // A load event can follow a script runtime failure. A retry must
              // fetch it again instead of reusing a falsely successful element.
              doc.getElementById('pdc-lazy-' + definition.view + '-script')?.remove();
              win[definition.name] = stub;
              throw new Error('Report controller unavailable');
            }
            return controller;
          }).catch(error => { loading = null; throw error; });
      }
      return loading;
    }
    const stub = {
      lazyVersion: VERSION,
      syncAccess,
      close() { active = false; generation++; opening = null; clear(); },
      reset() { locked = true; stub.close(); syncAccess(); },
      open() {
        if (!syncAccess()) return Promise.resolve();
        active = true;
        if (opening) return opening;
        const requestGeneration = ++generation, requestOwner = identity();
        message(false);
        const promise = load().then(controller => {
          if (!allowed()) { controller.reset(); return; }
          if (!active || !viewIsActive() || requestGeneration !== generation || requestOwner !== identity()) return;
          return controller.open();
        }).catch(() => {
          if (active && viewIsActive() && allowed() && requestGeneration === generation && requestOwner === identity()) message(true);
        }).finally(() => { if (opening === promise) opening = null; });
        opening = promise;
        return promise;
      }
    };
    win[definition.name] = stub;
    win.addEventListener('pdc-auth-locked', () => {
      // A script finishing after lock is reset by open's completion guard.
      if (win[definition.name] === stub) stub.reset();
    });
    win.addEventListener('pdc-auth-ready', () => {
      if (win[definition.name] !== stub) return;
      // Auth-ready can replace a token or actor while assets are downloading.
      // Reuse the download, but replace the pending open's identity and epoch.
      locked = false; generation++; opening = null;
      if (!syncAccess()) return;
      if (viewIsActive()) void stub.open();
      else { active = false; clear(); }
    });
    syncAccess();
    return stub;
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { VERSION, DEFINITIONS, install };
  if (!root.document) return;
  for (const definition of DEFINITIONS) if (!root[definition.name]) install(root, definition);
})(typeof window === 'object' ? window : globalThis);
