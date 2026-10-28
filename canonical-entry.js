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
  const requestedIntake = !phone && ['#/newvehicles','#/operationupdates'].includes(location.hash);
  // r643 (F258): Fitters bay and Sublet · MMT keep their own page on a phone (pmgpdc.au/mmt opens #/mmt-sublet).
  const ownPhonePage = ['#/fitters', '#/mmt-sublet'].includes(location.hash);
  document.documentElement.classList.toggle('pdc-qc-phone', Boolean(phone && !ownPhonePage));
  if (phone && !ownPhonePage && (!location.hash || location.hash.startsWith('#/'))) {
    window.history.replaceState({ pdcView: 'qc' }, '', `${location.pathname}${location.search}#/qc`);
  }
  const version = '2026.09.10.01';
  const style = document.createElement('link');
  style.rel = 'stylesheet';
  style.href = `pdc-qc-mobile.css?v=${version}&readable-text=2026.09.16.01`;
  document.head.appendChild(style);
  const load = () => {
    document.head.appendChild(style);

    const script = document.createElement('script');
    script.src = `pdc-qc-mobile.js?v=${version}&deep-review=2026.09.13.01&sublet-qc=2026.09.14.01&readable-text=2026.09.16.01&fitters=2026.09.16.01&separate-screens-pmb-warning=2026.09.16.01&r643=2026.10.28.r643`;
    const loadReview = () => {
      const reviewStyle = document.createElement('link');
      reviewStyle.rel = 'stylesheet';
      reviewStyle.href = 'pdc-review-stations.css?v=2026.09.09.12';
      document.head.appendChild(reviewStyle);
      const review = document.createElement('script');
      review.src = 'pdc-review-stations.js?v=2026.09.09.12&nonnav138-bookings=2026.10.15.01&pmg-read=2026.10.19.01&pmg-read=2026.10.19.01';
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
    const slimStyle = document.createElement('link');
    slimStyle.rel = 'stylesheet'; slimStyle.href = 'pdc-planner-slim.css?v=2026.09.12.identity-fields&pill-lines=2026.10.02.15';
    document.head.appendChild(slimStyle);
    const slimScript = document.createElement('script');
    slimScript.src = 'pdc-planner-slim.js?returned-queue=2026.10.19.01&r493=2026.10.22.r493&v=2026.09.12.identity-fields&fitter-sync=2026.09.16.03&bhavesh-followup=2026.09.23.01';
    document.head.appendChild(slimScript);
    const tileCleanup = document.createElement('script');
    tileCleanup.src = 'pdc-workshop-tile-cleanup.js?v=2026.09.10.03';
    document.head.appendChild(tileCleanup);

    const serviceLocations = document.createElement('script');
    serviceLocations.src = 'pdc-service-locations.js?v=2026.09.14.03';
    // r436 (F47): parts ETA loads after the parts location so its chip sits beside it (and still loads if that file fails).
    // r475 (F88): r475=2026.10.22.r475 on the parts ETA script (countdown and source-email hover).
    // r482 (F95): r482=2026.10.22.r482 on the parts ETA script (parts ETA warning before a bay booking).
    const loadPartsEta = () => {
      if (document.querySelector('script[data-pdc-parts-eta]')) return;
      const partsEta = document.createElement('script');
      partsEta.src = 'pdc-parts-eta.js?parts-eta=2026.10.21.r436&r475=2026.10.22.r475&r482=2026.10.22.r482&r490=2026.10.23.r490&r616=2026.10.28.r616';
      partsEta.dataset.pdcPartsEta = '1';
      partsEta.onload = loadJitaEta;
      partsEta.onerror = loadJitaEta;
      document.head.appendChild(partsEta);
    };
    // r516 (F130): JITA ETA from the daily paste. Loads after the email parts ETA.
    // r519 (F133): the script still loads, then returns. SHOW_JITA_ETA is false, so it
    // keeps the paste hidden and does not nest a JITA ETA. The key number still loads next.
    const loadJitaEta = () => {
      if (document.querySelector('script[data-pdc-jita-eta]')) return;
      const jitaEta = document.createElement('script');
      jitaEta.src = 'pdc-jita-eta.js?r516=2026.10.23.r516&r517=2026.10.23.r517&r519=2026.10.23.r519';
      jitaEta.dataset.pdcJitaEta = '1';
      jitaEta.onload = loadWorkshopVehicleSearch;
      jitaEta.onerror = loadWorkshopVehicleSearch;
      document.head.appendChild(jitaEta);
    };
    // r460 (F73): vehicle key number (Key No. in the drop-down; inline edit for controllers / administrators, audited);
    // loads after the service locations and parts ETA so the recorded key wins in the Key column.
    // r472 (F85): the key number module also keeps the snapshot rows raw after a vehicle-card save, so the card no longer re-reads
    // the whole board to rebind its UUID + Stock (a key-only save confirms its read-back in the background).
    // r566 (F180): planner/table vehicle search matcher (exact key + stock/job/customer/vehicle text).
    const loadWorkshopVehicleSearch = () => {
      if (document.querySelector('script[data-pdc-workshop-vehicle-search]')) {
        loadKeyNumber();
        return;
      }
      const search = document.createElement('script');
      search.src = 'pdc-workshop-vehicle-search.js?r566=2026.10.27.r566';
      search.dataset.pdcWorkshopVehicleSearch = '1';
      search.onload = loadKeyNumber;
      search.onerror = loadKeyNumber;
      document.head.appendChild(search);
    };
    const loadKeyNumber = () => {
      if (document.querySelector('script[data-pdc-key-number]')) return;
      const keyNumber = document.createElement('script');
      keyNumber.src = 'pdc-key-number.js?key-number=2026.10.22.r460&r472=2026.10.22.r472&r490=2026.10.23.r490&r575=2026.10.27.r575&r616=2026.10.28.r616';
      keyNumber.dataset.pdcKeyNumber = '1';
      keyNumber.onload = loadPartsStoppage;
      keyNumber.onerror = loadPartsStoppage;
      document.head.appendChild(keyNumber);
    };
    // r567 (F181): typed parts ETA and stoppage note. Loads after the key number and before the table, so the
    // table can lift the read-only date into the Parts ETA column. r586 (F200): the date is set in the side panel.
    // A missing script still opens the table.
    const loadPartsStoppage = () => {
      if (document.querySelector('script[data-pdc-parts-stoppage]')) return;
      const stoppage = document.createElement('script');
      stoppage.src = 'pdc-parts-stoppage.js?r567=2026.10.27.r567&r573=2026.10.27.r573&r595=2026.10.28.r595&r616=2026.10.28.r616';
      stoppage.dataset.pdcPartsStoppage = '1';
      stoppage.onload = loadVehicleLocationsTable;
      stoppage.onerror = loadVehicleLocationsTable;
      document.head.appendChild(stoppage);
    };
    // r461 (F74): Vehicle Locations "Table view" switch (default stays the drop-down view); loads last in this chain so
    // the table shows the same cells as the drop-downs, including the parts ETA and key number additions.
    const loadVehicleLocationsTable = () => {
      if (document.querySelector('script[data-pdc-vehicle-locations-table]')) return;
      // r604 (F218): pit bookings (PIT tile list and calendar, Pit column) load beside the table. The table asks it for
      // each Pit cell at render time and the module redraws once its data is in, so the order does not matter.
      if (!document.querySelector('script[data-pdc-pit-bookings]')) {
        const pit = document.createElement('script');
        pit.src = 'pdc-pit-bookings.js?r604=2026.10.28.r604&r611=2026.10.28.r611&r612=2026.10.28.r612&r616=2026.10.28.r616&r618=2026.10.28.r618&r622=2026.10.28.r622&r630=2026.10.28.r630&r632=2026.10.28.r632';
        pit.dataset.pdcPitBookings = '1';
        document.head.appendChild(pit);
      }
      // r612 (F226): Completed Vehicles lists every vehicle that has been at PMB. It wraps renderCompletedVehicles
      // from app.js, which has loaded by the time this table step runs.
      if (!document.querySelector('script[data-pdc-vehicle-history]')) {
        const history = document.createElement('script');
        history.src = 'pdc-vehicle-history.js?r612=2026.10.28.r612';
        history.dataset.pdcVehicleHistory = '1';
        document.head.appendChild(history);
      }
      const table = document.createElement('script');
      table.src = 'pdc-vehicle-locations-table.js?vehicle-locations-table=2026.10.22.r461&r462=2026.10.22.r462&r463=2026.10.22.r463&r476=2026.10.22.r476&r475=2026.10.22.r475&r481=2026.10.22.r481&r485=2026.10.22.r485&r557=2026.10.27.r557&r562=2026.10.27.r562&r563=2026.10.27.r563&r567=2026.10.27.r567&r566=2026.10.27.r566&r593=2026.10.28.r593&r604=2026.10.28.r604&r613=2026.10.28.r613&r618=2026.10.28.r618&r622=2026.10.28.r622&r672=2026.10.28.r672'; // r672 (F281): PMB flashes red on missing, 0 or duplicate keys; r613 (F228): key search waits for typing to stop; r604 (F218): Pit column; r476 (F89): bunched-up columns; r475 (F88): Parts ETA column; r481 (F94): search shows matches from every tile; r485 (F98): Table view only; r557 (F171): New to PMB tile; r562 (F176): key-number gate; r563 (F177): arrival age; r567 (F181): typed Parts ETA; r566: planner search boxes; r593 (F207): New to PMB view
      table.dataset.pdcVehicleLocationsTable = '1';
      table.onload = loadVehicleSlideout;
      document.head.appendChild(table);
    };
    // r462 (F75): Table view only: clicking a vehicle opens the slide-out panel. r463 (F76): the panel shows the card
    // (stations, details, operations); its drag-to-bay is withdrawn. Loads after the table module, which it registers with.
    // r473 (F86): the panel drops its summary row (station strip, PMB status, Book all stations) and gets an Open Vehicle button.
    const loadVehicleSlideout = () => {
      if (document.querySelector('script[data-pdc-vehicle-slideout]')) return;
      const slideout = document.createElement('script');
      slideout.src = 'pdc-vehicle-slideout.js?vehicle-slideout=2026.10.28.r588&r595=2026.10.28.r595'; // r588 (F202): five-column grid cache-bust stays; r595 (F209): panel opens once; r578 (F192): green complete tick; r560 (F174): More details; r565 (F179): chip edit
      slideout.dataset.pdcVehicleSlideout = '1';
      document.head.appendChild(slideout);
    };
    serviceLocations.onload = loadPartsEta;
    serviceLocations.onerror = loadPartsEta;
    document.head.appendChild(serviceLocations);
    // r439 (F50): sublet POs: each GP PO line gets its PO and a 'sublet done' tick inline (r439b; own row under the description, r439c); Sublet box orange/green (the script guards double loads).
    const subletPo = document.createElement('script');
    subletPo.src = 'pdc-sublet-po.js?sublet-po=2026.10.21.r444&r490=2026.10.23.r490&r494=2026.10.23.r494c&r616=2026.10.28.r616';
    // r443 (F56): packed 2-column category panels for the operations summary; loads after the PO module so it wraps outermost.
    const loadOperationPanels = () => {
      if (document.querySelector('script[data-pdc-operation-panels]')) return;
      const operationPanels = document.createElement('script');
      operationPanels.src = 'pdc-operation-panels.js?operation-panels=2026.10.21.r444';
      operationPanels.dataset.pdcOperationPanels = '1';
      document.head.appendChild(operationPanels);
    };
    // r445 (F58): sublet PO attach (pilot vehicles; controllers / administrators) loads between the PO module and the panels,
    // so its documents block sits in the Sublet box before the panels place it full width; the panels still load if it fails.
    const loadSubletPoAttach = () => {
      if (document.querySelector('script[data-pdc-sublet-po-attach]')) return loadOperationPanels();
      const subletPoAttach = document.createElement('script');
      subletPoAttach.src = 'pdc-sublet-po-attach.js?sublet-po-attach=2026.10.21.r445&r490=2026.10.23.r490&r616=2026.10.28.r616';
      subletPoAttach.dataset.pdcSubletPoAttach = '1';
      subletPoAttach.onload = loadOperationPanels;
      subletPoAttach.onerror = loadOperationPanels;
      document.head.appendChild(subletPoAttach);
    };
    subletPo.onload = loadSubletPoAttach;
    subletPo.onerror = loadSubletPoAttach;
    document.head.appendChild(subletPo);
    const partsConfirmation = document.createElement('script');
    partsConfirmation.src = 'pdc-parts-confirmation.js?v=2026.09.13.person-confirmed.1';
    document.head.appendChild(partsConfirmation);
    const intakeStyle = document.createElement('link');
    intakeStyle.rel = 'stylesheet';
    intakeStyle.href = 'pdc-new-vehicles.css?v=2026.09.12.review-orange-match&compact-approve=2026.09.14.01&review-fixes=2026.09.13.01&operation-approval=2026.09.14.01&bulk-ready=2026.09.14.01&department-filter=2026.09.19.01&accepted-updates=2026.10.15.01&r446=2026.10.21.r446';
    document.head.appendChild(intakeStyle);
    const intakeScript = document.createElement('script');
    intakeScript.src = 'pdc-new-vehicles.js?v=2026.09.13.render-performance&r403=2026.10.21.01&compact-approve=2026.09.14.01&ai-estimates=2026.09.14.01&review-fixes=2026.09.13.01&operation-approval=2026.09.14.01&deep-review=2026.09.13.01&one-hour-gap=2026.09.14.01&tune-hours=2026.09.14.01&bulk-ready=2026.09.14.01&department138-bus=2026.09.16.01&department138-tint=2026.09.17.01&speed=2026.09.17.01&planner-speed=2026.09.17.02&department-filter=2026.09.19.01&accepted-updates=2026.10.15.01&approval-errors=2026.10.19.02&automatic-additions=2026.10.19.01&sublet-hours-tags=2026.10.20.01&r446=2026.10.21.r446&r459=2026.10.22.r459';
    intakeScript.onload = () => {
      if (requestedIntake && typeof showView === 'function') showView(location.hash.slice(2), { historyMode: 'replace' });
    };
    document.head.appendChild(intakeScript);
    const bookAllStations = document.createElement('script');
    // r482 (F95): r482=2026.10.22.r482 on Book all stations (parts ETA warning first).
    bookAllStations.src = 'pdc-book-all-stations.js?v=2026.09.14.01-book-all-speed&render-cost=2026.09.14.01&one-hour-gap=2026.09.14.01&r483=2026.10.22.r483&r482=2026.10.22.r482';
    document.head.appendChild(bookAllStations);
    const locationOverride = document.createElement('script');
    locationOverride.src = 'pdc-location-override.js?v=2026.09.11.01&review-fixes=2026.09.13.01&separate-screens-pmb-warning=2026.09.16.01';
    document.head.appendChild(locationOverride);
    const subletIntake = document.createElement('script');
    // r501 (F114): r501=2026.10.23.r501 on the Sublet intake (Sublet page create hidden; book in Manage sublets).
    subletIntake.src = 'pdc-sublet-intake.js?v=2026.09.12.inline-provider&deep-review=2026.09.13.01&r501=2026.10.23.r501';
    document.head.appendChild(subletIntake);
    const rftStyle = document.createElement('link');
    rftStyle.rel = 'stylesheet';
    rftStyle.href = 'pdc-rft-actions.css?v=2026.09.10.04';
    document.head.appendChild(rftStyle);
    const rftScript = document.createElement('script');
    rftScript.src = 'pdc-rft-actions.js?v=2026.09.10.04&render-cost=2026.09.14.01';
    document.head.appendChild(rftScript);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', load, { once: true });
  else load();
})();
