(function () {
  'use strict';
  function init() {
    const existing = document.querySelector('[data-site-switcher]');
    if (!existing || document.getElementById('pd135-department')) return;
    const label = document.createElement('label');
    label.className = 'site-switcher';
    label.hidden = true;
    const title = document.createElement('span'); title.textContent = 'PD Departments';
    const select = document.createElement('select');
    select.id = 'pd135-department'; select.setAttribute('aria-label', 'Choose PD department');
    for (const [value, text] of [['135', 'Karratha PMG (135)'], ['pmb', 'PMB']]) {
      const option = document.createElement('option'); option.value = value; option.textContent = text; select.append(option);
    }
    label.append(title, select); existing.after(label);
    function sync() { label.hidden = !window.PDC_AUTH_CONTEXT; select.disabled = !window.PDC_AUTH_CONTEXT; select.value = '135'; }
    select.addEventListener('change', () => {
      if (!window.PDC_AUTH_CONTEXT) return sync();
      if (select.value === 'pmb') window.location.assign('https://btnew.github.io/pdc-control-board-staging/');
      else sync();
    });
    window.addEventListener('pdc-auth-ready', sync);
    window.addEventListener('pdc-auth-locked', sync); sync();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true }); else init();
})();
