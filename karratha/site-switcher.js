(() => {
  'use strict';
  const select = document.getElementById('pdc-site-switcher');
  if (!select) return;
  const current = document.body.dataset.pdcSite === 'broome' ? 'broome'
    : /\/karratha(?:\/|$)/.test(window.location.pathname || new URL(window.location.href).pathname) ? 'karratha' : 'pmb';
  const base = new URL(current === 'pmb' ? './' : '../', window.location.href);
  const destinations = { pmb: './', karratha: 'karratha/', broome: 'sales/' };
  function sync() {
    const admin = window.PDC_AUTH_CONTEXT?.role === 'administrator';
    select.closest('[data-site-switcher]').hidden = !admin;
    select.disabled = !admin;
    select.value = current;
  }
  select.addEventListener('change', () => {
    if (window.PDC_AUTH_CONTEXT?.role !== 'administrator') return sync();
    if (Object.hasOwn(destinations, select.value) && select.value !== current)
      window.location.assign(new URL(destinations[select.value], base));
  });
  window.addEventListener('pdc-auth-ready', sync);
  window.addEventListener('pdc-auth-locked', sync);
  sync();
})();
