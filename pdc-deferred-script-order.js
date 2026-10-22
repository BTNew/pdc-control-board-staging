/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// The live board marks every startup script defer so the page can parse while
// those files download. Deferred scripts run after the browser has already
// set document.readyState to "interactive", and several modules call their
// boot function immediately unless readyState is still "loading". Holding
// the reported state until DOMContentLoaded keeps that boot on the same
// side of the last startup script as the old parser-blocking page.
//
// Restore the previous startup by reverting this change, or by removing this
// script and every defer attribute together. Removing only this script leaves
// the deferred boots running before the scripts that follow them.
(function () {
  'use strict';
  const prototype = typeof Document === 'function' ? Document.prototype : null;
  const descriptor = prototype ? Object.getOwnPropertyDescriptor(prototype, 'readyState') : null;
  const root = typeof window === 'object' ? window : null;
  if (!root) return;
  if (!descriptor || typeof descriptor.get !== 'function' || descriptor.configurable === false) {
    root.PDC_DEFERRED_SCRIPT_ORDER = 'unheld';
    return;
  }
  let hold = true;
  Object.defineProperty(prototype, 'readyState', {
    configurable: true,
    enumerable: descriptor.enumerable,
    get() {
      const value = descriptor.get.call(this);
      if (hold && this === document && value !== 'loading') return 'loading';
      return value;
    }
  });
  document.addEventListener('DOMContentLoaded', function () { hold = false; }, { capture: true, once: true });
  root.PDC_DEFERRED_SCRIPT_ORDER = true;
})();
