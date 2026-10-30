/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r525 (F139): Website activity Period "Last 24 hours". Synthetic staff only. SQL is already applied as r513; do not re-apply.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const { USAGE_PERIODS, usagePeriodDays } = require('./pdc-staff-usage.js');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const code = read('pdc-staff-usage.js');
const migration = read('supabase/migrations/20261023140000_r513_usage_last_24_hours.sql');
const rollback = read('supabase/rollbacks/20261023140000_r513_usage_last_24_hours.down.sql');
const OLD_MD5 = '1343d2c98a83cde1904a22eb5d2d3d85';
const NEW_MD5 = '258cb7610a194909c2bf814cfeb8126d';

function functionBody(sql, tag = 'function') {
  const match = sql.match(new RegExp('create or replace function pdc_usage_private\\.report_usage\\(p_days integer default 30\\)\\nreturns jsonb language plpgsql stable security definer\\nset search_path = pg_catalog\\nas \\$' + tag + '\\$([\\s\\S]*?)\\$' + tag + '\\$;'));
  assert.ok(match, 'report_usage body');
  return match[1];
}
const md5 = text => crypto.createHash('md5').update(text).digest('hex');

test('Last 24 hours is the first period and 1, 7, 30, 90 are the only values', () => {
  assert.deepEqual(USAGE_PERIODS.map(period => [period.days, period.label]), [
    [1, 'Last 24 hours'],
    [7, 'Last 7 days'],
    [30, 'Last 30 days'],
    [90, 'Last 90 days']
  ]);
  for (const days of [1, 7, 30, 90]) assert.equal(usagePeriodDays(String(days)), days);
  for (const bad of [0, 2, 14, 24, 365, null, '', '1 day']) assert.equal(usagePeriodDays(bad), null);
});

test('the report function accepts 1 as the same rolling day window and nothing else changed', () => {
  const previous = functionBody(read('supabase/migrations/20260915054254_staff_usage_active_presence.sql'));
  const next = functionBody(migration, 'ru513');
  const restored = functionBody(rollback);
  assert.equal(md5(previous), OLD_MD5);
  assert.equal(md5(next), NEW_MD5);
  assert.equal(restored, previous);
  const widened = previous.replace(
    '  if p_days is null or p_days not in (7,30,90) then\n',
    '  -- r510: 1 is the rolling last 24 hours. make_interval(days => 1) is 24 hours,\n  -- the same rolling window as 7, 30 and 90, not a Perth calendar day.\n  if p_days is null or p_days not in (1,7,30,90) then\n'
  );
  assert.equal(next, widened);
  assert.match(next, /cutoff timestamptz := now\(\) - make_interval\(days => p_days\);/);
  assert.match(next, /count\(distinct \(e\.recorded_at at time zone 'Australia\/Perth'\)::date\)\s+filter \(where e\.recorded_at >= cutoff\)/);
  assert.match(next, /sum\(e\.visits\) filter \(where e\.recorded_at >= cutoff\)/);
  assert.match(next, /sum\(e\.clicks\) filter \(where e\.recorded_at >= cutoff\)/);
  assert.match(next, /count\(\*\) filter \(where s\.first_seen_at >= cutoff\)/);
  assert.match(next, /max\(e\.recorded_at\) as last_active_at/);
  assert.match(next, /where e\.recorded_at >= cutoff/);
  assert.doesNotMatch(migration, /karratha135_usage\.report_usage\(p_days/);
  assert.match(migration, /SQL already applied on staging as r513_usage_last_24_hours version 20261023055941/);
  assert.match(migration, /Do not re-apply/);
  assert.match(migration, /Do not apply to production/);
  assert.match(migration, new RegExp(OLD_MD5));
  assert.match(migration, new RegExp(NEW_MD5));
  assert.match(rollback, /DELETE FROM pdc_ops\.expected_function_md5\n WHERE signature/);
  assert.match(rollback, /DELETE FROM pdc_ops\.regression_checks\n WHERE check_name/);
  assert.deepEqual(scanSql(migration), []);
  assert.deepEqual(scanSql(rollback), []);
  assert.equal(read('karratha/pdc-staff-usage.js').includes('Last 24 hours'), false);
});

// Mirrors report_usage: rolling cutoff, Perth calendar dates for active days,
// period totals for visits/clicks/sign-ins/pages, lifetime last activity.
function perthDate(ms) {
  return new Date(ms + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
function aggregate(events, sessions, now, days) {
  const cutoff = now - days * 24 * 60 * 60 * 1000;
  const inWindow = events.filter(event => event.at >= cutoff);
  const pages = new Map();
  for (const event of inWindow) {
    const page = pages.get(event.page) || {page: event.page, visits: 0, clicks: 0};
    page.visits += event.visits;
    page.clicks += event.clicks;
    pages.set(event.page, page);
  }
  return {
    cutoff,
    sign_ins: sessions.filter(session => session.first_seen_at >= cutoff).length,
    active_days: new Set(inWindow.map(event => perthDate(event.at))).size,
    page_visits: inWindow.reduce((total, event) => total + event.visits, 0),
    clicks: inWindow.reduce((total, event) => total + event.clicks, 0),
    pages: [...pages.values()],
    last_active_at: events.reduce((latest, event) => Math.max(latest, event.at), 0)
  };
}

test('a rolling 24-hour window drops older activity and can span two Perth dates', () => {
  const now = Date.parse('2026-10-23T05:21:00.000Z'); // 13:21 in Perth
  const hour = 60 * 60 * 1000;
  const events = [
    {at: now - 23 * hour, page: 'dashboard', visits: 1, clicks: 3}, // 14:21 Perth, 22 Oct
    {at: now - 1 * hour, page: 'workflow', visits: 1, clicks: 4}, // 12:21 Perth, 23 Oct
    {at: now - 25 * hour, page: 'parts', visits: 1, clicks: 9}, // inside 7 days, outside 24 hours
    {at: now - 8 * 24 * hour, page: 'qc', visits: 1, clicks: 2}
  ];
  const sessions = [
    {first_seen_at: now - 23 * hour},
    {first_seen_at: now - 25 * hour},
    {first_seen_at: now - 8 * 24 * hour}
  ];
  const day = aggregate(events, sessions, now, 1);
  const week = aggregate(events, sessions, now, 7);
  assert.equal(day.sign_ins, 1);
  assert.equal(day.active_days, 2);
  assert.equal(day.page_visits, 2);
  assert.equal(day.clicks, 7);
  assert.deepEqual(day.pages.map(page => page.page).sort(), ['dashboard', 'workflow']);
  assert.equal(week.sign_ins, 2);
  assert.equal(week.page_visits, 3);
  assert.equal(week.clicks, 16);
  assert.equal(week.pages.some(page => page.page === 'qc'), false);
  assert.equal(day.last_active_at, now - hour);
  assert.equal(perthDate(now - 23 * hour), '2026-10-22');
  assert.equal(perthDate(now - hour), '2026-10-23');
  assert.equal(now - day.cutoff, 24 * hour);
});

function panelHarness() {
  const requests = [];
  let panel = null;
  const content = {
    textContent: '',
    _html: '',
    _tbody: {innerHTML: ''},
    _wrap: {scrollLeft: 0},
    querySelector(selector) {
      if (selector === 'table') return this._html.includes('<table') ? {} : null;
      if (selector === '.admin-reference-table-wrap') return this._html.includes('admin-reference-table-wrap') ? this._wrap : null;
      if (selector === 'tbody') return this._tbody;
      return null;
    },
    querySelectorAll() { return []; }
  };
  Object.defineProperty(content, 'innerHTML', {
    get() { return this._html; },
    set(html) { this._html = String(html); }
  });
  const note = {textContent: '', classList: {toggle() {}}};
  const bits = {
    results: {textContent: ''},
    status: {textContent: ''},
    counts: {textContent: ''},
    search: {value: '', addEventListener() {}},
    activity: {value: 'all', addEventListener() {}},
    sort: {value: 'last_active_at', addEventListener() {}},
    direction: {textContent: '', addEventListener() {}},
    refresh: {addEventListener() {}},
    about: {open: false}
  };
  let daysSelect = null;
  function makePanel() {
    const node = {
      id: 'staff-usage-panel',
      hidden: true,
      className: '',
      addEventListener() {},
      querySelector(selector) {
        if (selector === '[data-usage-days]') return daysSelect;
        if (selector === '[data-usage-refresh]') return bits.refresh;
        if (selector === '[data-usage-search]') return bits.search;
        if (selector === '[data-usage-activity]') return bits.activity;
        if (selector === '[data-usage-sort]') return bits.sort;
        if (selector === '[data-usage-direction]') return bits.direction;
        if (selector === '[data-usage-content]') return content;
        if (selector === '[data-usage-note]') return note;
        if (selector === '[data-usage-results]') return bits.results;
        if (selector === '[data-usage-status]') return bits.status;
        if (selector === '[data-usage-counts]') return bits.counts;
        if (selector === '.staff-usage-about') return bits.about;
        return null;
      },
      querySelectorAll() { return []; }
    };
    Object.defineProperty(node, 'innerHTML', {
      set(html) {
        const options = [...String(html).matchAll(/<option value="(\d+)"([^>]*)>([^<]*)<\/option>/g)].map(match => ({
          value: match[1], selected: /\bselected\b/.test(match[2]), label: match[3]
        }));
        const selected = options.find(option => option.selected) || options[0];
        daysSelect = {
          value: selected ? selected.value : '',
          options,
          listeners: {},
          addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
        };
      }
    });
    return node;
  }
  const doc = {
    visibilityState: 'visible',
    activeElement: null,
    body: {dataset: {}},
    querySelector(selector) {
      if (selector === '#user-management .pdc-lists-layout') return {append(child) { panel = child; }};
      if (selector === '.view.active') return {id: 'user-management'};
      if (selector === '.nav-item.active[data-view]') return {dataset: {view: 'user-management'}};
      return null;
    },
    querySelectorAll(selector) { return selector === '.view, .sales-view' ? [{id: 'user-management'}] : []; },
    getElementById(id) { return id === 'staff-usage-panel' ? panel : null; },
    createElement() { return makePanel(); },
    addEventListener() {}
  };
  const win = {
    document: doc,
    crypto: {randomUUID: () => 'batch-1'},
    performance: {now: () => 0},
    PDC_SUPABASE_CONFIG: {url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'public-test-key'},
    PDC_AUTH_CONTEXT: {userId: 'synthetic-admin', role: 'administrator'},
    __pdcCachedAccessToken: 'token-synthetic',
    addEventListener() {},
    setTimeout() { return 1; },
    setInterval() { return 1; },
    MutationObserver: class { observe() {} },
    fetch(url, options) {
      const body = JSON.parse(options.body);
      requests.push({url, body});
      const day = body.p_days === 1;
      return Promise.resolve({
        ok: true,
        json: async () => ({
          days: body.p_days,
          tracking_started_at: '2026-09-14T00:00:00.000Z',
          generated_at: '2026-10-23T05:21:00.000Z',
          active_window_seconds: 120,
          users: [{
            user_id: 'synthetic-1',
            name: 'Example Staff',
            email: 'example.staff@example.invalid',
            last_sign_in_at: '2026-10-21T01:00:00.000Z',
            last_active_at: '2026-10-23T04:00:00.000Z',
            sign_ins: day ? 2 : 9,
            active_days: day ? 1 : 4,
            page_visits: day ? 5 : 40,
            clicks: day ? 8 : 80,
            pages: [{page: 'dashboard', visits: day ? 5 : 40, clicks: day ? 8 : 80}],
            active_now: false,
            presence_last_active_at: null
          }]
        })
      });
    }
  };
  vm.runInNewContext(code, win);
  return {requests, get panel() { return panel; }, content, counts: bits.counts};
}
const flush = async () => { for (let i = 0; i < 6; i++) await new Promise(resolve => setImmediate(resolve)); };

test('the Period control loads Last 30 days, then Last 24 hours reloads those counts', async () => {
  const harness = panelHarness();
  await flush();
  const reports = () => harness.requests.filter(request => request.url.endsWith('/rpc/get_pdc_usage_report_20260914'));
  const select = harness.panel.querySelector('[data-usage-days]');
  assert.deepEqual(select.options.map(option => option.label), ['Last 24 hours', 'Last 7 days', 'Last 30 days', 'Last 90 days']);
  assert.equal(select.value, '30');
  assert.equal(reports().at(-1).body.p_days, 30);
  assert.match(harness.content._tbody.innerHTML, />9<\/td><td>4<\/td><td>40<\/td><td>80<\/td>/);
  select.value = '1';
  select.listeners.change.forEach(fn => fn({target: select}));
  await flush();
  assert.equal(reports().at(-1).body.p_days, 1);
  assert.match(harness.content._tbody.innerHTML, />2<\/td><td>1<\/td><td>5<\/td><td>8<\/td>/);
  assert.match(harness.content._tbody.innerHTML, /Example Staff/);
  assert.match(harness.content._tbody.innerHTML, /example\.staff@example\.invalid/);
  assert.match(harness.counts.textContent, /rolling 24 hours before the report/);
  assert.match(harness.counts.textContent, /not the previous Perth calendar day/);
  const before = harness.requests.length;
  select.value = '2';
  select.listeners.change.forEach(fn => fn({target: select}));
  await flush();
  assert.equal(harness.requests.length, before);
  assert.equal(select.value, '1');
});

test('PDC and Sales cache-bust the tracker; Karratha keeps its own copy', () => {
  assert.match(read('index.html'), /pdc-staff-usage\.js\?v=2026\.10\.16\.01&amp;all-pages=2026\.10\.16\.01&amp;r489=2026\.10\.23\.r489&amp;r525=2026\.10\.24\.r525(&amp;r642=2026\.10\.28\.r642)?(&amp;r711=2026\.10\.29\.r711)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?"/);
  assert.match(read('sales/index.html'), /\.\.\/pdc-staff-usage\.js\?v=2026\.10\.16\.01&amp;all-pages=2026\.10\.16\.01&amp;r525=2026\.10\.24\.r525(&amp;r642=2026\.10\.28\.r642)?(&amp;r711=2026\.10\.29\.r711)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?(&amp;r768=2026\.10\.31\.r768)?"/);
  assert.doesNotMatch(read('karratha/index.html'), /r525=2026\.10\.24\.r525/);
  assert.doesNotMatch(read('karratha/pdc-staff-usage.js'), /Last 24 hours/);
  const log = read('docs/FAULT_LOG.md');
  assert.match(log, /\| F139 \|/);
  assert.match(log, /\| F136 \|/);
  assert.match(log, /\| F123 \|/);
  assert.match(log, /User Administration/);
  assert.match(log, /usage_period_24h_513/);
  assert.match(log, /20261023055941/);
  assert.match(read('docs/staff-usage-reporting.md'), /rolling last 24 hours/);
});
