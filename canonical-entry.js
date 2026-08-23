(() => {
  'use strict';

  const location = window.location;
  const pathname = String(location.pathname || '');
  if (!pathname.endsWith('/index.html')) return;

  const canonicalPath = pathname.slice(0, -'/index.html'.length) || '/';
  location.replace(`${canonicalPath}${location.search || ''}${location.hash || ''}`);
})();
