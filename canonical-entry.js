(() => {
  'use strict';
  const location = window.location;
  const pathname = String(location.pathname || '');
  if (pathname.endsWith('/index.html')) {
    const canonicalPath = pathname.slice(0, -'/index.html'.length) || '/';
    location.replace(`${canonicalPath}${location.search || ''}${location.hash || ''}`);
    return;
  }

  // The same authenticated website becomes a QC-only client on phones.
  // Never rewrite OAuth/password-recovery fragments.
  const phone = window.matchMedia?.('(max-width: 900px), (pointer: coarse) and (max-width: 1024px)').matches;
  document.documentElement.classList.toggle('pdc-qc-phone', Boolean(phone));
  if (phone && (!location.hash || location.hash.startsWith('#/'))) {
    window.history.replaceState({ pdcView: 'qc' }, '', `${location.pathname}${location.search}#/qc`);
  }
  const version = '2026.09.09.05';
  const style = document.createElement('link');
  style.rel = 'stylesheet';
  style.href = `pdc-qc-mobile.css?v=${version}`;
  document.head.appendChild(style);
  const load = () => {
    // Append last so the phone layout wins over legacy desktop refinements.
    document.head.appendChild(style);
    const script = document.createElement('script');
    script.src = `pdc-qc-mobile.js?v=${version}`;
    script.onerror = () => document.documentElement.classList.remove('pdc-qc-phone');
    document.head.appendChild(script);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', load, { once: true });
  else load();
})();
