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
  const requestedIntake = !phone && location.hash === '#/newvehicles';
  document.documentElement.classList.toggle('pdc-qc-phone', Boolean(phone));
  if (phone && (!location.hash || location.hash.startsWith('#/'))) {
    window.history.replaceState({ pdcView: 'qc' }, '', `${location.pathname}${location.search}#/qc`);
  }
  const version = '2026.09.10.01';
  const style = document.createElement('link');
  style.rel = 'stylesheet';
  style.href = `pdc-qc-mobile.css?v=${version}`;
  document.head.appendChild(style);
  const load = () => {
    document.head.appendChild(style);

    const script = document.createElement('script');
    script.src = `pdc-qc-mobile.js?v=${version}`;
    const loadReview = () => {
      const reviewStyle = document.createElement('link');
      reviewStyle.rel = 'stylesheet';
      reviewStyle.href = 'pdc-review-stations.css?v=2026.09.09.12';
      document.head.appendChild(reviewStyle);
      const review = document.createElement('script');
      review.src = 'pdc-review-stations.js?v=2026.09.09.12';
      document.head.appendChild(review);
    };
    const loadRework = () => {
      const rework = document.createElement('script');
      rework.src = 'pdc-qc-rework.js?v=2026.09.09.10';
      rework.onload = () => {
        const usability = document.createElement('script');
        usability.src = 'pdc-workshop-usability.js?v=2026.09.09.13';
        usability.onload = loadReview; usability.onerror = loadReview;
        document.head.appendChild(usability);
      };
      rework.onerror = loadReview;
      document.head.appendChild(rework);
    };
    script.onload = loadRework;
    script.onerror = () => { document.documentElement.classList.remove('pdc-qc-phone'); loadRework(); };
    document.head.appendChild(script);

    // Planner-only presentation/search helper. It is versioned separately so
    // existing browsers pick up small planner fixes without touching mobile QC.
    const tileCleanup = document.createElement('script');
    tileCleanup.src = 'pdc-workshop-tile-cleanup.js?v=2026.09.10.03';
    document.head.appendChild(tileCleanup);

    const intakeStyle = document.createElement('link');
    intakeStyle.rel = 'stylesheet';
    intakeStyle.href = 'pdc-new-vehicles.css?v=2026.09.09.11';
    document.head.appendChild(intakeStyle);
    const intakeScript = document.createElement('script');
    intakeScript.src = 'pdc-new-vehicles.js?v=2026.09.09.11';
    intakeScript.onload = () => {
      if (requestedIntake && typeof showView === 'function') showView('newvehicles', { historyMode: 'replace' });
    };
    document.head.appendChild(intakeScript);
    const rftStyle = document.createElement('link');
    rftStyle.rel = 'stylesheet';
    rftStyle.href = 'pdc-rft-actions.css?v=2026.09.10.04';
    document.head.appendChild(rftStyle);
    const rftScript = document.createElement('script');
    rftScript.src = 'pdc-rft-actions.js?v=2026.09.10.04';
    document.head.appendChild(rftScript);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', load, { once: true });
  else load();
})();

