(() => {
  'use strict';
  // Navigation only. Centre access is checked by the destination's own API.
  const website = document.querySelector('[data-site-switcher]');
  if (!website || document.body.dataset.pdcSite === 'broome') return;
  const label = document.createElement('label');
  label.className = 'site-switcher';
  label.dataset.pdDepartmentNavigation = '';
  label.hidden = true;
  const title = document.createElement('span');
  title.textContent = 'PD Departments';
  const select = document.createElement('select');
  select.id = 'pdc-pd-department-switcher';
  select.setAttribute('aria-label', 'Switch PD department');
  select.disabled = true;
  for (const [value, text] of [['pmb', 'PMB'], ['karratha', 'Karratha PMG']]) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = text;
    select.append(option);
  }
  label.append(title, select);
  website.insertAdjacentElement('afterend', label);
  function sync() {
    const allowed = window.PDC_AUTH_CONTEXT?.role === 'administrator';
    label.hidden = !allowed;
    select.disabled = !allowed;
    select.value = 'pmb';
  }
  select.addEventListener('change', () => {
    if (window.PDC_AUTH_CONTEXT?.role !== 'administrator') return sync();
    if (select.value === 'karratha') {
      window.location.assign(new URL('karratha/', window.location.href));
    }
  });
  window.addEventListener('pdc-auth-ready', sync);
  window.addEventListener('pdc-auth-locked', sync);
  sync();
})();
