/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r495 (F108): adds "Karratha Toyota (Sales)" to the Website drop-down. It is the same Sales page for the
// Karratha branch (sales/?branch=karratha). site-switcher.js stays byte-identical to the frozen Department 135 copy,
// so this file runs after it and only handles the Karratha Sales value (and Broome when on the Karratha branch).
(() => {
  'use strict';
  const select = document.getElementById('pdc-site-switcher');
  if (!select) return;
  const onSales = document.body.dataset.pdcSite === 'broome';
  const base = new URL(onSales ? '../' : './', window.location.href);
  const now = () => (onSales ? (window.PDC_SALES_BRANCH?.key === 'karratha' ? 'karratha-sales' : 'broome') : null);
  const admin = () => window.PDC_AUTH_CONTEXT?.role === 'administrator';
  function sync() { if (admin() && now() === 'karratha-sales') select.value = 'karratha-sales'; }
  select.addEventListener('change', () => {
    if (!admin()) return;
    if (select.value === 'karratha-sales' && now() !== 'karratha-sales') window.location.assign(new URL('sales/?branch=karratha', base));
    else if (select.value === 'broome' && now() === 'karratha-sales') window.location.assign(new URL('sales/', base));
  });
  window.addEventListener('pdc-auth-ready', sync);
  window.addEventListener('pdc-auth-locked', sync);
  sync();
})();
