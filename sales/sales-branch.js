/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r495 (F108): one Sales site, one branch per page. sales/ is Broome Toyota (dealer 37047, unchanged);
// sales/?branch=karratha is Karratha Toyota (Pilbara Toyota, Navision dealer 14450). The server decides what each
// account may see (pdc_sales_private.context): administrators pick the branch with the X-PDC-Sales-Branch header,
// salespeople always get the branch of their own Sales access. Broome sends no header, exactly as before.
(function (root) {
  'use strict';
  const BRANCHES = Object.freeze({
    broome: Object.freeze({
      key: 'broome', dealerCode: '37047', label: 'Broome Toyota', town: 'Broome', isDefault: true,
      logo: 'assets/broome-toyota-logo.png', financeGroups: Object.freeze(['Broome', 'Port Hedland']),
      financeLocations: Object.freeze([['broome', 'Broome'], ['pilbara', 'Pilbara']]),
      roster: Object.freeze(['BG', 'AW', 'PM', 'CW']),
    }),
    karratha: Object.freeze({
      key: 'karratha', dealerCode: '14450', label: 'Karratha Toyota', town: 'Karratha', isDefault: false,
      logo: 'assets/karratha-toyota-logo.svg',
      // Craig 23 Oct: no Karratha finance groups and no Port Hedland finance in this release. Broome finance is unchanged.
      financeSkipped: true,
      // Default: the Karratha Sales tab does not list Toyota head-office dealer batches.
      headOfficeDealers: Object.freeze(['001234', '002345']),
      // Fleet / Rental rows stay under the salesperson on the feed. No separate bucket.
      fleetUnderFeedSalesperson: true,
      // A Broome salesperson with the same initials is a different person. The server join enforces that.
      separateFromBroomeInitials: true,
      roster: null, // from the server (CF / SL). Inactive future initials (RK / JS / DB) are not on the roster.
    }),
  });
  const HEADER = 'x-pdc-sales-branch';
  function byKey(key) {
    const k = String(key || '').trim().toLowerCase();
    return Object.prototype.hasOwnProperty.call(BRANCHES, k) ? BRANCHES[k] : null;
  }
  function fromSearch(search) {
    let value = '';
    try { value = new URLSearchParams(String(search || '')).get('branch') || ''; } catch { value = ''; }
    return byKey(value) || BRANCHES.broome;
  }
  function requestHeaders(branch) {
    return branch && !branch.isDefault && byKey(branch.key) === branch ? { [HEADER]: branch.key } : null;
  }
  function current() { return (root && byKey(root.PDC_SALES_BRANCH?.key)) || BRANCHES.broome; }
  // Roster used by the board filter and the salesperson drop-down. Broome keeps its fixed four.
  function roster(branch, context, items) {
    const b = branch || current();
    if (b.roster) return b.roster;
    const mapped = Array.isArray(context?.branch_roster) ? context.branch_roster.filter(code => typeof code === 'string' && code.trim()) : [];
    if (mapped.length) return Object.freeze([...new Set(mapped.map(code => code.trim().toUpperCase()))]);
    const seen = new Set();
    for (const row of Array.isArray(items) ? items : []) {
      const code = typeof row?.salesperson_code === 'string' ? row.salesperson_code.trim().toUpperCase() : '';
      if (code) seen.add(code);
    }
    return Object.freeze([...seen].sort());
  }
  function dealerDigits(value) {
    const text = String(value ?? '').trim();
    return text.replace(/^0+/, '') || '0';
  }
  // Head-office batches (001234 / 002345) are hidden on a non-default branch. Broome's list is not filtered.
  function hidesHeadOffice(branch, dealerCode) {
    if (!branch || branch.isDefault || !Array.isArray(branch.headOfficeDealers)) return false;
    const raw = String(dealerCode ?? '').trim();
    const digits = dealerDigits(raw);
    return branch.headOfficeDealers.some(code => raw === String(code) || digits === dealerDigits(code));
  }
  function applyLabels(doc, branch) {
    if (!doc || !branch) return;
    const label = branch.label;
    if (doc.body?.dataset) doc.body.dataset.salesBranch = branch.key;
    const view = String(doc.title || '').split(' · ').slice(1).join(' · ') || 'Dashboard';
    doc.title = label + ' · ' + view;
    for (const img of doc.querySelectorAll?.('img.pdc-auth-brand, img.brand-logo') || []) { img.src = branch.logo; img.alt = label; }
    const authEyebrow = doc.querySelector?.('.pdc-auth-card .eyebrow'); if (authEyebrow) authEyebrow.textContent = label + ' Vehicle Tracking';
    const brandTitle = doc.querySelector?.('.brand-title'); if (brandTitle) brandTitle.textContent = label;
    const topEyebrow = doc.querySelector?.('.topbar .eyebrow'); if (topEyebrow) topEyebrow.textContent = label + ' New Vehicle Tracking';
    const skipFinance = branch.financeSkipped === true;
    for (const button of doc.querySelectorAll?.('[data-sales-view="finance"]') || []) button.hidden = skipFinance;
  }
  // A salesperson who signs in on sales/ is shown their own branch (the server already returned its vehicles).
  function adopt(key) {
    const branch = byKey(key);
    if (!branch || !root || branch === current()) return false;
    root.PDC_SALES_BRANCH = branch;
    applyLabels(root.document, branch);
    try {
      const url = new URL(root.location.href);
      if (branch.isDefault) url.searchParams.delete('branch'); else url.searchParams.set('branch', branch.key);
      root.history?.replaceState?.(root.history.state, '', url.href);
    } catch { /* address bar only */ }
    return true;
  }
  const api = Object.freeze({ BRANCHES, HEADER, byKey, fromSearch, requestHeaders, current, roster, hidesHeadOffice, applyLabels, adopt });
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root && root.document && root.location) {
    const branch = fromSearch(root.location.search);
    root.PDC_SALES_BRANCH = branch;
    const headers = requestHeaders(branch);
    if (headers) root.PDC_SUPABASE_REQUEST_HEADERS = Object.freeze(headers);
    root.BROOME_SALES_BRANCH = api;
    if (!branch.isDefault) applyLabels(root.document, branch);
  }
})(typeof window !== 'undefined' ? window : null);
