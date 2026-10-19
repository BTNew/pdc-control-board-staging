(() => {
  'use strict';
  if (window.PDC135_BOARD_ENABLED !== true) return;
  document.documentElement.removeAttribute('data-pd135-board');
  const waiting = [...document.querySelectorAll('script[type="text/plain"][src]')];
  const host = document.body || document.documentElement;
  const loadAt = index => {
    if (index >= waiting.length) return;
    const source = waiting[index];
    const script = document.createElement('script');
    script.src = source.getAttribute('src');
    script.async = false;
    const integrity = source.getAttribute('integrity');
    if (integrity) {
      script.integrity = integrity;
      script.crossOrigin = source.getAttribute('crossorigin') || 'anonymous';
    }
    script.onload = () => loadAt(index + 1);
    script.onerror = () => loadAt(index + 1);
    host.appendChild(script);
  };
  loadAt(0);
})();
