(() => {
  'use strict';
  const select = document.getElementById('pdc-site-switcher');
  if (!select) return;
  function sync() {
    const admin = window.PDC_AUTH_CONTEXT?.role === 'administrator';
    select.closest('[data-site-switcher]').hidden = !admin;
    select.disabled = !admin;
    select.value = document.body.dataset.pdcSite === 'broome' ? 'broome' : 'pmb';
  }
  select.addEventListener('change', () => {
    if (window.PDC_AUTH_CONTEXT?.role !== 'administrator') return sync();
    const onSales = document.body.dataset.pdcSite === 'broome';
    if (select.value === 'broome' && !onSales) window.location.assign(new URL('sales/', window.location.href));
    if (select.value === 'pmb' && onSales) window.location.assign(new URL('../', window.location.href));
  });
  window.addEventListener('pdc-auth-ready', sync);
  window.addEventListener('pdc-auth-locked', sync);
  sync();
})();
