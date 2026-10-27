/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r568 (F182): on a running Bus 4x4 bay, other components' line items can start here and finish here.
 * A typed date is not involved. The email Parts ETA path is not involved.
 * The section is not drawn until get_pdc_bus_component_board_565 exists.
 * Nothing here closes a job card or takes a vehicle off the board.
 */
(() => {
  'use strict';
  const VERSION = '2026.10.27.r568';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const BOARD_RPC = 'get_pdc_bus_component_board_565';
  const SET_RPC = 'set_pdc_bus_component_line_565';

  function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  }
  function groupItems(items) {
    const groups = [];
    const by = new Map();
    for (const item of Array.isArray(items) ? items : []) {
      const key = item.category || 'other';
      let group = by.get(key);
      if (!group) {
        group = { category: key, label: item.category_label || key, home_busy: !!item.home_busy, items: [] };
        by.set(key, group);
        groups.push(group);
      }
      group.home_busy = group.home_busy || !!item.home_busy;
      group.items.push(item);
    }
    return groups;
  }
  function itemHtml(item, editable) {
    const busy = !!item.home_busy;
    const done = item.kind === 'section' ? item.status === 'complete' : !!item.completed;
    const running = item.kind === 'section' ? item.status === 'in_progress' : item.item_status === 'running';
    const title = item.kind === 'section'
      ? `${item.section_label || 'Section'} — ${item.section_description || ''}`.trim()
      : (item.description || 'Line');
    const where = done
      ? (item.finished_bay ? `Finished in ${item.finished_bay}` : 'Done')
      : running
        ? (item.started_bay ? `Started in ${item.started_bay}` : 'In progress')
        : '';
    const locked = !editable || busy;
    const startChecked = running || done;
    const line = esc(item.line_identity);
    const section = esc(item.section_id || '');
    return `<li class="pdc-bus-split-item${done ? ' is-done' : ''}${running ? ' is-running' : ''}${busy ? ' is-busy' : ''}">
      <span><strong>${esc(title)}</strong><small>${item.kind === 'line' && item.hours != null ? `${esc(item.hours)} h` : 'Bus 4x4'}${where ? ` · ${esc(where)}` : ''}${busy ? ' · That bay still has this component' : ''}</small></span>
      <label class="conv-tick"><input type="checkbox" data-bus-split-step="start" data-bus-line="${line}" data-bus-section="${section}" ${startChecked ? 'checked' : ''} ${locked || done ? 'disabled' : ''}> Start</label>
      <label class="conv-tick"><input type="checkbox" data-bus-split-step="done" data-bus-line="${line}" data-bus-section="${section}" ${done ? 'checked' : ''} ${locked || (!running && !done) ? 'disabled' : ''}> Done</label>
    </li>`;
  }
  function componentHtml(board, opts = {}) {
    const items = board && board.items;
    if (!items || !items.length) return '';
    const editable = !!opts.editable;
    const groups = groupItems(items);
    return `<section class="pdc-bus-split" data-pdc-bus-split="${esc(opts.bookingId || board.booking_id || '')}"><h3>Other Bus 4x4 components</h3><p>A component can start in one bay and finish in another. Start, then Done. A component that already has a running bay stays on that bay. This does not close the job card.</p>${groups.map(group => `<div class="pdc-bus-split-group"><h4>${esc(group.label)}</h4><ul>${group.items.map(item => itemHtml(item, editable && !group.home_busy)).join('')}</ul></div>`).join('')}</section>`;
  }

  const api = { VERSION, componentHtml, groupItems, esc };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
    return;
  }

  const root = window;
  if (!root.PDC_SUPABASE_CONFIG || root.PDC_SUPABASE_CONFIG.projectRef !== PROJECT) return;
  let missing = false;
  let painting = false;
  let cache = { booking: '', html: '', editable: false, stamp: '' };
  const token = () => root.__pdcCachedAccessToken;
  const base = () => String(root.PDC_SUPABASE_CONFIG.url || '').replace(/\/$/, '');

  function paint() {
    if (painting) return;
    const host = document.getElementById('fitters-host');
    const work = host && host.querySelector('.fitter-work');
    if (!work) return;
    const booking = work.getAttribute('data-bus-booking') || '';
    const editable = work.getAttribute('data-bus-editable') === '1';
    const box = work.querySelector('[data-pdc-bus-split]');
    if (!booking || missing) {
      if (box) box.remove();
      return;
    }
    if (cache.booking !== booking) {
      if (box) box.remove();
      cache = { booking, html: '', editable, stamp: '', board: null };
      void load(booking, editable);
      return;
    }
    if (cache.board && cache.editable !== editable) {
      cache.editable = editable;
      cache.html = componentHtml(cache.board, { editable, bookingId: booking });
      cache.stamp = String(cache.html.length) + (editable ? '1' : '0');
    }
    if (!cache.html) {
      if (box) box.remove();
      return;
    }
    if (box && box.getAttribute('data-pdc-bus-stamp') === cache.stamp) return;
    painting = true;
    if (box) box.remove();
    const help = work.querySelector('.fitter-help');
    const html = cache.html.replace('data-pdc-bus-split="', `data-pdc-bus-stamp="${esc(cache.stamp)}" data-pdc-bus-split="`);
    if (help) help.insertAdjacentHTML('beforebegin', html);
    else work.insertAdjacentHTML('beforeend', html);
    painting = false;
  }

  async function rpc(name, body) {
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: root.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {})
    });
    if (response.status === 404) {
      missing = true;
      return null;
    }
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.message || payload.code || 'The workshop could not save that component.');
    return payload;
  }

  async function load(booking, editable) {
    if (missing || !token()) return;
    try {
      const board = await rpc(BOARD_RPC, { p_booking: booking });
      if (!board || cache.booking !== booking) return;
      cache.board = board.ok ? board : { items: [] };
      cache.editable = editable;
      cache.html = componentHtml(cache.board, { editable, bookingId: booking });
      cache.stamp = String(cache.html.length) + (editable ? '1' : '0');
      paint();
    } catch (_) { /* the bay card stays as it is */ }
  }

  const MESSAGES = {
    component_busy: 'That component is already running in its own bay.',
    item_not_started: 'Press Start first.',
    use_own_ticks: 'That item is already on this bay.',
    job_not_running: 'Start this bay job first.',
    not_authorized: 'View only.',
    vehicle_not_found: 'That vehicle is not on the board.'
  };

  document.addEventListener('change', async event => {
    const box = event.target.closest && event.target.closest('[data-bus-split-step]');
    if (!box || missing) return;
    event.preventDefault();
    event.stopPropagation();
    const checked = box.checked;
    box.checked = !checked;
    const step = !checked ? 'reset' : box.getAttribute('data-bus-split-step');
    const work = box.closest('.fitter-work');
    const booking = work && work.getAttribute('data-bus-booking');
    const tech = work && work.getAttribute('data-bus-tech');
    if (!booking || !tech) return;
    try {
      const result = await rpc(SET_RPC, {
        p_booking: booking,
        p_technician: tech,
        p_line: box.getAttribute('data-bus-line'),
        p_section: box.getAttribute('data-bus-section') || null,
        p_step: step
      });
      if (result && result.ok === false) throw new Error(MESSAGES[result.code] || 'The workshop could not save that component.');
      cache.booking = '';
      document.querySelector('[data-fitter-refresh]')?.click();
    } catch (error) {
      const text = error.message || 'The workshop could not save that component.';
      const section = work && work.querySelector('[data-pdc-bus-split]');
      if (section) {
        let note = section.querySelector('[data-pdc-bus-error]');
        if (!note) {
          note = document.createElement('p');
          note.setAttribute('data-pdc-bus-error', '1');
          section.appendChild(note);
        }
        note.textContent = text;
      }
    }
  }, true);

  if (!document.getElementById('pdc-bus-split-style')) {
    const style = document.createElement('style');
    style.id = 'pdc-bus-split-style';
    style.textContent = '.pdc-bus-split{margin:12px 0;padding:10px 12px;border:1px solid #cbd5e1;border-radius:8px;background:#f8fafc}.pdc-bus-split h3{margin:0 0 4px;font-size:15px}.pdc-bus-split h4{margin:8px 0 4px;font-size:13px}.pdc-bus-split-item{display:flex;gap:8px;align-items:center;padding:4px 0;border-top:1px solid #e2e8f0}.pdc-bus-split-item small{display:block;color:#475569}.pdc-bus-split-item.is-done strong{color:#166534}.pdc-bus-split-item.is-running strong{color:#1d4ed8}.pdc-bus-split-item.is-busy{opacity:.7}';
    document.head.appendChild(style);
  }
  const host = document.getElementById('fitters-host');
  if (host && typeof MutationObserver === 'function') {
    new MutationObserver(() => paint()).observe(host, { childList: true, subtree: true });
  }
  root.PDC_BUS_COMPONENT_SPLIT = { VERSION, reload: () => { cache.booking = ''; paint(); } };
})();
