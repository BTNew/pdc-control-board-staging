(function () {
  'use strict';
  const host = document.getElementById('workflow-board');
  const scenario = document.getElementById('fixture-scenario');
  const search = document.getElementById('fixture-search');
  const status = document.getElementById('fixture-status');
  let model;
  function render() {
    const previousScroll = host.querySelector('.control-board-bays-scroll')?.scrollLeft || 0;
    const snapshot = scenario.value === 'populated' ? ControlBoardFixtures.populatedSnapshot() : scenario.value === 'empty' ? ControlBoardFixtures.emptySnapshot() : {};
    const started = performance.now();
    model = ControlBoardOverview.buildModel(snapshot, { search: search.value });
    host.innerHTML = model ? ControlBoardOverview.render(model) : '<div class="fixture-error" role="status">Workshop overview unavailable. No stale jobs are shown.</div>';
    const scroller = host.querySelector('.control-board-bays-scroll');
    if (scroller) scroller.scrollLeft = previousScroll;
    status.textContent = model ? `${model.totalBays} physical bays; ${model.totalBookings} bookings; ${model.totalWaiting} waiting. Rendered in ${(performance.now() - started).toFixed(1)}ms.` : 'Unavailable scenario';
  }
  host.addEventListener('click', event => {
    const move = event.target.closest('[data-control-board-scroll]');
    const jump = event.target.closest('[data-control-board-jump]');
    const card = event.target.closest('[data-control-board-item]');
    const planner = event.target.closest('[data-control-board-planner]');
    if (move) {
      const scroller = host.querySelector('.control-board-bays-scroll');
      scroller?.scrollBy({ left: Number(move.dataset.controlBoardScroll) * scroller.clientWidth * 0.8, behavior: 'smooth' });
    } else if (jump) {
      host.querySelector(`[data-control-board-stage="${jump.dataset.controlBoardJump}"]`)?.scrollIntoView({ inline: 'start', block: 'nearest', behavior: 'smooth' });
    } else if (card) {
      const item = [...model.waiting, ...model.columns.flatMap(column => column.items)].find(item => item.id === card.dataset.controlBoardId);
      status.textContent = item ? `Local navigation fixture: ${item.kind}, ${item.stage}, booking ${item.source.booking_id || 'unallocated'}, bay ${item.source.bay_number || 'unallocated'}, vehicle ${item.vehicle.stock_number}. No live action performed.` : 'Fixture item missing';
    } else if (planner) {
      status.textContent = `Local planner navigation fixture: ${planner.dataset.controlBoardPlanner}. No live action performed.`;
    }
  });
  scenario.addEventListener('change', render);
  search.addEventListener('input', render);
  document.getElementById('fixture-clear').addEventListener('click', () => { search.value = ''; render(); });
  document.getElementById('fixture-find').addEventListener('click', () => {
    render();
    host.querySelector('[data-control-board-match]')?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' });
  });
  render();
})();
