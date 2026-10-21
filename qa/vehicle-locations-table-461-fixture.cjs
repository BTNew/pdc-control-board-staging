'use strict';
// r461 (F74): synthetic Vehicle Locations fixture for the drop-down vs table parity test.
// Every value is invented: stock numbers are SYN-*, there are no customer names, job cards, VINs or real dates of work.
// It covers all eight location buckets and every station state the board draws: not required, required, booked,
// complete, STOPPAGE, parts ordered / stoppage / complete, imported parts colours (green, orange, grey, review, red,
// person-confirmed), sublet booked, the QC'd RFT controls and the STOPPAGES list.
const STATIONS = ['tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet'];
const CAP = { tint: 'Tint', bus4x4: 'Bus4x4', hoist: 'Hoist', fitting: 'Fitting', fabrication: 'Fabrication', electrical: 'Electrical', tyre: 'Tyre', sublet: 'Sublet' };
const STATION_STATES = ['none', 'required', 'booked', 'complete', 'stoppage'];
const PARTS_STATES = ['none', 'required', 'ordered', 'stoppage', 'complete', 'green', 'orange', 'grey', 'review', 'red', 'person'];
const BUCKETS = ['overseas', 'transit', 'yardhold', 'nonnavision', 'pmb', 'qc', 'pit', 'rft'];

function locationFields(bucket) {
  const navision = { source: 'navision', make: 'Toyota' };
  switch (bucket) {
    case 'overseas': return { ...navision };
    case 'transit': return { ...navision, pdcLocation: 'IT', navisionKewdaleEta: '30/10/2026' };
    case 'yardhold': return { ...navision, pdcLocation: 'YH' };
    case 'nonnavision': return { source: 'Manual' };
    case 'pmb': return { ...navision, pdcLocation: 'PMB' };
    case 'qc': return { ...navision, pdcLocation: 'QC' };
    case 'pit': return { ...navision, pdcLocation: 'PIT' };
    case 'rft': return { ...navision, pdcLocation: 'RFT', pdcQcComplete: true };
    default: return {};
  }
}

function partsFields(stateName) {
  const flags = colour => ({ pdcPartsFlags: { colour, label: `Synthetic parts ${colour}`, meaning: 'Synthetic fixture flag.', last_successful_import_at: '2026-10-21T10:00:00Z', ...(stateName === 'person' ? { person_confirmed: true } : {}) } });
  switch (stateName) {
    case 'required': return { pdcRequiresParts: true };
    case 'ordered': return { pdcRequiresParts: true, parts_update: { parts_required: true, parts_ordered: true, parts_received: false, parts_stoppage: false } };
    case 'stoppage': return { pdcRequiresParts: true, pdcPartsStoppage: true, pdcPartsStoppageReason: 'Synthetic parts hold' };
    case 'complete': return { pdcRequiresParts: true, pdcCompleteParts: true };
    case 'green': case 'orange': case 'grey': case 'review': case 'red': return { pdcRequiresParts: true, ...flags(stateName) };
    case 'person': return { pdcRequiresParts: true, ...flags('green') };
    default: return {};
  }
}

function syntheticVehicles({ perBucket = 6 } = {}) {
  const vehicles = [];
  let n = 0;
  BUCKETS.forEach((bucket, b) => {
    for (let i = 0; i < perBucket; i += 1) {
      n += 1;
      const vehicle = {
        id: `00000000-0000-4000-8461-${String(n).padStart(12, '0')}`,
        stock: `SYN-${String(n).padStart(4, '0')}`,
        vehicle: `Synthetic Hilux ${n}`, client: '', pdcSheetVisible: true,
        pdcSubletBookings: [], syntheticBookings: [],
        ...locationFields(bucket),
        ...partsFields(PARTS_STATES[(n + b) % PARTS_STATES.length]),
      };
      STATIONS.forEach((station, s) => {
        const stateName = STATION_STATES[(n + s + b) % STATION_STATES.length];
        const cap = CAP[station];
        if (stateName === 'none') return;
        vehicle[`pdcRequires${cap}`] = true;
        if (stateName === 'complete') vehicle[`pdcComplete${cap}`] = true;
        if (stateName === 'booked') {
          if (station === 'sublet') vehicle.pdcSubletBookings.push({ status: 'active', bookingId: `syn-sublet-${n}`, outDate: '2026-10-23', expectedReturnDate: '2026-10-25' });
          else vehicle.syntheticBookings.push({ station, status: 'planned' });
        }
        if (stateName === 'stoppage') vehicle.syntheticBookings.push({ station, status: 'stoppage' });
      });
      vehicles.push(vehicle);
    }
  });
  return vehicles;
}

// Workshop planner entries for the synthetic bookings, in the shape app.js workshopLoadPlans() returns.
function syntheticPlans(context, vehicles) {
  const defs = new Map(context.pdcJobDefsPartsFirst().map(def => [def.key, def]));
  return vehicles.flatMap(vehicle => vehicle.syntheticBookings.map((booking, index) => ({
    id: `syn-plan-${vehicle.stock}-${index}`,
    vehicleKey: context.vehicleKey(vehicle),
    sharedVehicleId: context.vehicleWorkshopDetailCanonicalId(vehicle) || '',
    stage: context.pmbStageForPdcJob(defs.get(booking.station)),
    status: booking.status,
    stoppageReason: booking.status === 'stoppage' ? 'Synthetic stoppage' : '',
    startAt: '2026-10-23T01:00:00.000Z', endAt: '2026-10-23T03:00:00.000Z',
  })));
}

module.exports = { syntheticVehicles, syntheticPlans, BUCKETS, STATIONS, STATION_STATES, PARTS_STATES };
