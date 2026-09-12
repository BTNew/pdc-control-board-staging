(() => {
  'use strict';
  if (typeof vehicleIdentityStackHtml !== 'function') return;
  const original = vehicleIdentityStackHtml;
  function numbers(vehicle) {
    const lines = Array.isArray(vehicle.pdcEmailOperationLines) ? vehicle.pdcEmailOperationLines : [];
    const values = [vehicleJobcardNumber(vehicle),
      ...(Array.isArray(vehicle.pdcJobCardNumbers) ? vehicle.pdcJobCardNumbers : []),
      ...lines.map(line => line?.job_card_number || line?.jobCardNumber || '')];
    const unique = new Map();
    values.forEach(value => {
      const number = cleanNavisionText(value);
      if (number && !unique.has(number.toUpperCase())) unique.set(number.toUpperCase(), number);
    });
    return [...unique.values()].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  }
  vehicleIdentityStackHtml = function(vehicle = {}, options = {}) {
    const html = original(vehicle, options);
    if (!String(options.className || '').split(/\s+/).includes('incoming-identity')) return html;
    const cards = numbers(vehicle);
    if (cards.length < 2) return html;
    const cell = `<span class="vehicle-identity-cell identity-jc identity-jc-stacked" data-label="JC"><span class="pdc-stacked-jobcards" title="${escapeHtml(cards.join(', '))}" aria-label="${escapeHtml(`Job cards ${cards.join(', ')}`)}">${cards.map(card => `<span>${escapeHtml(card)}</span>`).join('')}</span></span>`;
    return html.replace(/<span class="vehicle-identity-cell identity-jc" data-label="JC">[\s\S]*?<\/span><\/span>/, cell);
  };
})();
