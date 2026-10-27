(() => {
  'use strict';
  const root = typeof globalThis !== 'undefined' ? globalThis : this;
  const clean = value => (typeof cleanNavisionText === 'function' ? cleanNavisionText(value) : String(value || '').trim());
  const esc = value => (typeof escapeHtml === 'function' ? escapeHtml(value) : String(value || ''));
  const CLOSED = new Set(['80', '99']);

  function lineCard(line) {
    return clean(line?.job_card_number || line?.jobCardNumber || line?.job_card || '');
  }
  function lineSub(line) {
    const raw = line?.raw_row || line?.rawRow;
    return clean(line?.sub_status || line?.subStatus || raw?.['Sub Status'] || raw?.sub_status || '');
  }
  function sourceVehicle(vehicle = {}) {
    const stock = clean(vehicle.stock || vehicle.stock_number || vehicle.stockNumber);
    const id = clean(vehicle.id || vehicle.permanent_vehicle_id || '');
    const rows = root.app && Array.isArray(root.app.data) ? root.app.data : [];
    const found = rows.find(row => (id && clean(row.id) === id) || (stock && clean(row.stock || row.stock_number) === stock));
    if (!found || found === vehicle) return vehicle;
    return {
      ...found,
      ...vehicle,
      pdcJobCardNumbers: vehicle.pdcJobCardNumbers || found.pdcJobCardNumbers,
      pdcEmailOperationLines: vehicle.pdcEmailOperationLines || found.pdcEmailOperationLines,
      pdcQcOperationLines: vehicle.pdcQcOperationLines || found.pdcQcOperationLines,
      jobCardNumbers: vehicle.jobCardNumbers || found.jobCardNumbers,
      job_card_numbers: vehicle.job_card_numbers || found.job_card_numbers,
      job_card_number: vehicle.job_card_number || found.job_card_number,
      jobCardNumber: vehicle.jobCardNumber || vehicle.job_card_number || found.jobCardNumber,
    };
  }
  function collectLines(vehicle) {
    return [
      ...(Array.isArray(vehicle.pdcEmailOperationLines) ? vehicle.pdcEmailOperationLines : []),
      ...(Array.isArray(vehicle.pdcQcOperationLines) ? vehicle.pdcQcOperationLines : []),
      ...(Array.isArray(vehicle.operation_lines) ? vehicle.operation_lines : []),
      ...(Array.isArray(vehicle.job_card_lines) ? vehicle.job_card_lines : []),
    ];
  }
  function openJobCards(vehicle = {}) {
    const source = sourceVehicle(vehicle);
    const primary = clean(typeof vehicleJobcardNumber === 'function' ? vehicleJobcardNumber(source) : '')
      || clean(source.job_card_number || source.jobCardNumber || '');
    const named = [
      primary,
      ...(Array.isArray(source.pdcJobCardNumbers) ? source.pdcJobCardNumbers : []),
      ...(Array.isArray(source.jobCardNumbers) ? source.jobCardNumbers : []),
      ...(Array.isArray(source.job_card_numbers) ? source.job_card_numbers : []),
    ];
    const lines = collectLines(source);
    const cards = new Map();
    const touch = number => {
      const card = clean(number);
      if (!card) return null;
      const key = card.toUpperCase();
      if (!cards.has(key)) cards.set(key, { card, subs: [], bare: false });
      return cards.get(key);
    };
    named.forEach(number => {
      const row = touch(number);
      if (row && !lines.some(line => lineCard(line).toUpperCase() === row.card.toUpperCase())) row.bare = true;
    });
    lines.forEach(line => {
      const row = touch(lineCard(line));
      if (!row) return;
      const sub = lineSub(line);
      if (sub) row.subs.push(sub);
      else row.bare = true;
    });
    const open = [...cards.values()].filter(row => {
      if (row.bare || !row.subs.length) return true;
      return row.subs.some(sub => !CLOSED.has(sub));
    });
    const rest = open
      .map(row => row.card)
      .filter(card => card.toUpperCase() !== primary.toUpperCase())
      .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    const primaryOpen = open.find(row => row.card.toUpperCase() === primary.toUpperCase());
    return primaryOpen ? [primaryOpen.card, ...rest] : rest;
  }
  function cardLabel(vehicle) {
    return openJobCards(vehicle).join(' · ');
  }
  function lineHours(line) {
    if (typeof vehicleWorkshopHoursProjection === 'function') {
      const projected = vehicleWorkshopHoursProjection(line);
      const scheduled = Number(projected && projected.schedulingHours);
      if (Number.isFinite(scheduled)) return scheduled;
    }
    const raw = line?.estimatedHours ?? line?.estimated_hours;
    const numeric = Number(raw);
    return raw === null || raw === undefined || raw === '' || !Number.isFinite(numeric) ? null : numeric;
  }
  function groupsFor(lines) {
    const groups = new Map();
    (lines || []).forEach(line => {
      const card = lineCard(line) || '—';
      const key = card.toUpperCase();
      if (!groups.has(key)) groups.set(key, { card, lines: [], hours: 0, known: false });
      const group = groups.get(key);
      group.lines.push(line);
      const hours = lineHours(line);
      if (hours !== null) {
        group.hours += hours;
        group.known = true;
      }
    });
    return [...groups.values()];
  }
  function subtotalHtml(group) {
    const hours = group.known ? `${group.hours.toFixed(2)} h` : 'Hours not stated';
    return `<header class="pdc-card-group-head"><strong>${esc(group.card)}</strong><span>${group.lines.length} line${group.lines.length === 1 ? '' : 's'} · ${esc(hours)}</span></header>`;
  }

  root.pdcOpenJobCards = openJobCards;
  root.pdcOpenJobCardLabel = cardLabel;
  root.pdcCardLineGroups = groupsFor;

  if (typeof vehicleIdentityStackHtml === 'function' && !vehicleIdentityStackHtml.pdcStackedCards) {
    const original = vehicleIdentityStackHtml;
    const wrapped = function (vehicle = {}, options = {}) {
      const html = original(vehicle, options);
      const cards = openJobCards(vehicle);
      if (cards.length < 2) return html;
      const cell = `<span class="vehicle-identity-cell identity-jc identity-jc-stacked" data-label="JC"><span class="pdc-stacked-jobcards" title="${esc(cards.join(', '))}" aria-label="${esc(`Job cards ${cards.join(', ')}`)}">${cards.map(card => `<span>${esc(card)}</span>`).join('')}</span></span>`;
      return html.replace(/<span class="vehicle-identity-cell identity-jc" data-label="JC">[\s\S]*?<\/span>(?:<\/span>)?/, cell);
    };
    wrapped.pdcStackedCards = true;
    vehicleIdentityStackHtml = wrapped;
    root.vehicleIdentityStackHtml = wrapped;
  }

  if (typeof vehicleWorkshopCompactLinesHtml === 'function' && !vehicleWorkshopCompactLinesHtml.pdcStackedCards) {
    const originalLines = vehicleWorkshopCompactLinesHtml;
    const wrappedLines = function (group = {}, bookingFallback = 'Not booked', vehicle = {}, validStages = []) {
      const primary = clean(typeof vehicleJobcardNumber === 'function' ? vehicleJobcardNumber(vehicle) : '')
        || clean(vehicle.job_card_number || vehicle.jobCardNumber || '');
      const grouped = groupsFor(group.lines).sort((a, b) => {
        if (primary && a.card.toUpperCase() === primary.toUpperCase()) return -1;
        if (primary && b.card.toUpperCase() === primary.toUpperCase()) return 1;
        return a.card.localeCompare(b.card, undefined, { numeric: true });
      });
      if (grouped.length < 2) return originalLines(group, bookingFallback, vehicle, validStages);
      return grouped.map(card => {
        const body = originalLines({ ...group, lines: card.lines }, bookingFallback, vehicle, validStages);
        return `<section class="pdc-card-group" data-job-card="${esc(card.card)}">${subtotalHtml(card)}${body}</section>`;
      }).join('');
    };
    wrappedLines.pdcStackedCards = true;
    vehicleWorkshopCompactLinesHtml = wrappedLines;
    root.vehicleWorkshopCompactLinesHtml = wrappedLines;
  }

  if (typeof authenticatedEmailOperationLinesHtml === 'function' && !authenticatedEmailOperationLinesHtml.pdcStackedCards) {
    const originalSummary = authenticatedEmailOperationLinesHtml;
    const wrappedSummary = function (vehicle = {}) {
      const html = originalSummary(vehicle);
      const lines = typeof authenticatedOperationSummaryLines === 'function' ? authenticatedOperationSummaryLines(vehicle) : [];
      const grouped = groupsFor(lines);
      if (!html || grouped.length < 2) return html;
      const openHours = grouped.reduce((sum, group) => sum + group.hours, 0);
      const known = grouped.some(group => group.known);
      const total = known ? `${openHours.toFixed(2)} h` : 'Hours not stated';
      const bar = `<div class="pdc-card-subtotals" aria-label="Open job cards">${grouped.map(subtotalHtml).join('')}<p>Open cards · ${esc(total)}</p></div>`;
      const heading = /(<div class="authenticated-email-operations-heading">[\s\S]*?<\/div>)/;
      return heading.test(html) ? html.replace(heading, `$1${bar}`) : `${bar}${html}`;
    };
    wrappedSummary.pdcStackedCards = true;
    authenticatedEmailOperationLinesHtml = wrappedSummary;
    root.authenticatedEmailOperationLinesHtml = wrappedSummary;
  }
})();
