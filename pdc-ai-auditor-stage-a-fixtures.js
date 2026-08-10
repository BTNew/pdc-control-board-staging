'use strict';

const DEALERS = Object.freeze(['dealer-north', 'dealer-south', 'dealer-east', 'dealer-west']);
const NOW_ISO = '2026-07-29T04:00:00.000Z'; // Wednesday 12:00 Australia/Perth.

function buildDealerSnapshot(dealer, ordinal, count = 48) {
  const vehicles = [], workItems = [], bookings = [], stationCompatibility = [];
  for (let i = 0; i < count; i += 1) {
    const suffix = `${ordinal}-${String(i).padStart(3, '0')}`, vehicleId = `${dealer}-vehicle-${suffix}`, workId = `${dealer}-work-${suffix}`, bookingId = `${dealer}-booking-${suffix}`, station = `${dealer}-station-${i}`, mode = i % 10;
    vehicles.push({ id: vehicleId, dealer, Key: `KEY-${suffix}`, stock: `STK-${ordinal}${String(i).padStart(4, '0')}`, model: i % 2 ? 'Hilux' : 'Prado', location: 'Workshop', revision: `vr-${i}` });
    workItems.push({ id: workId, dealer, vehicleId, revision: `wr-${i}`, type: mode === 0 ? 'Sublet' : 'FAB', external: mode === 0, plannerEligible: mode === 0, status: mode === 3 ? 'stoppage' : mode === 4 ? 'complete' : mode === 5 ? 'mystery' : 'queued', createdAt: '2026-07-20T00:00:00.000Z', estimatedHours: mode === 5 ? 0 : 1, labourProvenance: mode === 5 ? '' : 'staff-confirmed', stoppageReason: mode === 3 ? 'Synthetic STOPPAGE' : '', requiredPriorWorkIds: mode === 4 ? [`${dealer}-missing-${i}`] : [] });
    if (mode !== 2) {
      const startAt = mode === 6 ? '2026-07-29T22:00:00.000Z' : `2026-07-30T${String(1 + (i % 6)).padStart(2, '0')}:00:00.000Z`, endAt = mode === 6 ? '2026-07-29T22:30:00.000Z' : `2026-07-30T${String(2 + (i % 6)).padStart(2, '0')}:00:00.000Z`;
      bookings.push({ id: bookingId, dealer, revision: `br-${i}`, vehicleId, workId, type: mode === 0 ? 'Sublet' : 'FAB', external: mode === 0, station, status: mode === 3 ? 'stoppage' : 'planned', startAt, endAt, expectedDurationMinutes: mode === 7 ? 180 : 60 });
      if (mode !== 0 && mode !== 9) stationCompatibility.push({ station, workType: 'FAB', allowed: true });
    }
  }
  if (bookings.length >= 4) {
    bookings[1].station = `${dealer}-shared-conflict`; bookings[3].station = `${dealer}-shared-conflict`;
    bookings[1].startAt = '2026-07-30T02:00:00.000Z'; bookings[1].endAt = '2026-07-30T04:00:00.000Z'; bookings[3].startAt = '2026-07-30T03:00:00.000Z'; bookings[3].endAt = '2026-07-30T05:00:00.000Z';
    stationCompatibility.push({ station: `${dealer}-shared-conflict`, workType: 'FAB', allowed: true });
  }
  return { authoritative: true, dealer, snapshotRevision: `snapshot-${ordinal}`, vehicleRevision: `vehicles-${ordinal}`, workRevision: `work-${ordinal}`, bookingRevision: `bookings-${ordinal}`, vehicles, workItems, bookings, operationLines: [], parts: [], stationCompatibility, parallelCompatibility: [], config: { timezone: 'Australia/Perth', holidays: ['2026-07-27'], forgottenWorkingDays: 3 } };
}

function directBase() {
  return { authoritative: true, dealer: 'dealer-rule', snapshotRevision: 's1', vehicleRevision: 'v1', workRevision: 'w1', bookingRevision: 'b1',
    vehicles: [{ id: 'v1', dealer: 'dealer-rule', Key: 'KEY-1', stock: 'STK-1', model: 'Hilux', location: 'Workshop', revision: 'vr1' }],
    workItems: [{ id: 'w1', dealer: 'dealer-rule', vehicleId: 'v1', revision: 'wr1', type: 'FAB', status: 'queued', createdAt: NOW_ISO, estimatedHours: 1, labourProvenance: 'staff-confirmed' }],
    bookings: [], operationLines: [], parts: [], stationCompatibility: [{ station: 'B1', workType: 'FAB', allowed: true }, { station: 'B1', workType: 'QC', allowed: true }], parallelCompatibility: [], config: { holidays: [] } };
}
function booking(id='b1', workId='w1', overrides={}) { return { id, dealer: 'dealer-rule', revision: `${id}-r`, vehicleId: 'v1', workId, type: 'FAB', department: 'FAB', station: 'B1', technicianId: `t-${id}`, status: 'planned', startAt: '2026-07-30T01:00:00.000Z', endAt: '2026-07-30T02:00:00.000Z', expectedDurationMinutes: 60, ...overrides }; }
function jobParts(overrides={}) { return { id: 'p1', dealer: 'dealer-rule', vehicleId: 'v1', workId: 'w1', scope: 'job-specific', vehicleConfidence: 1, jobConfidence: 1, status: 'not-confirmed', createdAt: '2026-07-27T00:00:00.000Z', ...overrides }; }
function operationLine(overrides={}) { return { id: 'o1', dealer: 'dealer-rule', vehicleId: 'v1', workKey: 'FITTING', estimatedHours: 1, hoursProvenance: 'job_card', ...overrides }; }
function buildRuleFixture(id) {
  const s=directBase(), w=s.workItems[0], v=s.vehicles[0];
  switch(id) {
    case 'SNAPSHOT_AUTHORITY_INVALID': s.authoritative=false; break;
    case 'SNAPSHOT_DEALER_SCOPE_VIOLATION': s.vehicles.push({...v,id:'foreign',dealer:'other'}); break;
    case 'HOLIDAY_CALENDAR_COVERAGE_LIMIT': delete s.config.holidays; break;
    case 'DUPLICATE_VEHICLE_ID': s.vehicles.push({...v}); break;
    case 'DUPLICATE_WORK_ID': s.workItems.push({...w}); break;
    case 'DUPLICATE_OPERATION_LINE_ID': s.operationLines=[operationLine(),operationLine()]; break;
    case 'OPERATION_LINE_AUTHORITY_INVALID': s.operationLines=[operationLine({id:''})]; break;
    case 'DUPLICATE_BOOKING_ID': s.bookings=[booking(),booking()]; break;
    case 'BOOKING_AUTHORITY_INVALID': s.bookings=[booking('b1','w1',{revision:''})]; break;
    case 'BOOKING_VEHICLE_UNRESOLVED': s.bookings=[booking('b1','w1',{vehicleId:'absent'})]; break;
    case 'BOOKING_INTERVAL_INVALID': s.bookings=[booking('b1','w1',{endAt:'2026-07-30T01:00:00.000Z'})]; break;
    case 'BOOKING_WITHOUT_ACTIVE_CANONICAL_WORK': s.bookings=[booking('b1','missing')]; break;
    case 'WORK_MULTIPLE_ACTIVE_BOOKINGS': s.bookings=[booking('b1'),booking('b2','w1',{startAt:'2026-07-30T03:00:00.000Z',endAt:'2026-07-30T04:00:00.000Z'})]; break;
    case 'DUPLICATE_ACTIVE_BOOKING': s.bookings=[booking('b1'),booking('b2','w1',{technicianId:'t2'})]; break;
    case 'COMPLETED_INACTIVE_WORK_BOOKED': w.status='completed'; w.completedAt=NOW_ISO; w.completedBy='u1'; s.bookings=[booking()]; break;
    case 'VEHICLE_OVERLAP': s.workItems.push({...w,id:'w2'}); s.bookings=[booking('b1'),booking('b2','w2',{station:'B2'})]; s.stationCompatibility.push({station:'B2',workType:'FAB',allowed:true}); break;
    case 'BAY_OVERLAP': s.vehicles.push({...v,id:'v2'}); s.workItems.push({...w,id:'w2',vehicleId:'v2'}); s.bookings=[booking('b1'),booking('b2','w2',{vehicleId:'v2'})]; break;
    case 'TECHNICIAN_OVERLAP': s.vehicles.push({...v,id:'v2'}); s.workItems.push({...w,id:'w2',vehicleId:'v2'}); s.bookings=[booking('b1'),booking('b2','w2',{vehicleId:'v2',station:'B2',technicianId:'t-b1'})]; s.stationCompatibility.push({station:'B2',workType:'FAB',allowed:true}); break;
    case 'STATION_INCOMPATIBLE': s.stationCompatibility[0].allowed=false; s.bookings=[booking()]; break;
    case 'STATION_COMPATIBILITY_UNKNOWN': s.stationCompatibility=[]; s.bookings=[booking()]; break;
    case 'APPROVED_PARALLEL_COMPATIBLE_WORK': s.vehicles.push({...v,id:'v2'}); s.workItems.push({...w,id:'w2',vehicleId:'v2',type:'QC'}); s.bookings=[booking('b1'),booking('b2','w2',{vehicleId:'v2',type:'QC'})]; s.parallelCompatibility=[{station:'B1',leftType:'FAB',rightType:'QC',allowed:true}]; break;
    case 'BOOKING_OUTSIDE_HOURS': s.bookings=[booking('b1','w1',{startAt:'2026-07-29T23:00:00.000Z',endAt:'2026-07-30T00:00:00.000Z'})]; break;
    case 'LABOUR_HOURS_MISSING': delete w.estimatedHours; break;
    case 'LABOUR_HOURS_ZERO': w.estimatedHours=0; break;
    case 'LABOUR_HOURS_NEGATIVE': w.estimatedHours=-1; break;
    case 'LABOUR_PROVENANCE_MISSING': w.labourProvenance=''; break;
    case 'OPERATION_LINE_HOURS_MISSING': s.operationLines=[operationLine({estimatedHours:null})]; break;
    case 'OPERATION_LINE_HOURS_NEGATIVE': s.operationLines=[operationLine({estimatedHours:-1})]; break;
    case 'OPERATION_LINE_HOURS_PROVENANCE_UNKNOWN': s.operationLines=[operationLine({hoursProvenance:'unknown'})]; break;
    case 'OPERATION_LINE_STAGE_MISSING': s.operationLines=[operationLine({workKey:''})]; break;
    case 'BOOKING_DURATION_TOO_SHORT': s.bookings=[booking('b1','w1',{endAt:'2026-07-30T01:10:00.000Z',expectedDurationMinutes:10})]; break;
    case 'BOOKING_DURATION_TOO_LONG': s.bookings=[booking('b1','w1',{endAt:'2026-07-30T10:00:00.000Z',expectedDurationMinutes:540})]; break;
    case 'BOOKING_DURATION_MISMATCH': s.bookings=[booking('b1','w1',{expectedDurationMinutes:120})]; break;
    case 'PARTS_CONFIDENCE_LIMIT': s.parts=[jobParts({scope:'vehicle',workId:''})]; break;
    case 'PARTS_REQUIRED_TODAY': s.bookings=[booking('b1','w1',{startAt:'2026-07-29T01:00:00.000Z',endAt:'2026-07-29T02:00:00.000Z'})]; s.parts=[jobParts()]; break;
    case 'PARTS_NOT_CONFIRMED_ONE_WORKING_DAY': s.parts=[jobParts()]; break;
    case 'PARTS_ORDERED_OR_UNKNOWN_THREE_WORKING_DAYS': s.parts=[jobParts({status:'ordered',orderedAt:'2026-07-23T00:00:00.000Z'})]; break;
    case 'PARTS_ACTIVE_STOPPAGE_BOOKED_OR_STARTED': s.bookings=[booking()]; s.parts=[jobParts({stoppage:true})]; break;
    case 'PARTS_RECEIVED_WITH_STOPPAGE': s.parts=[jobParts({status:'received',ready:true,stoppage:true})]; break;
    case 'PARTS_READY_NO_FUTURE_BOOKING': s.parts=[jobParts({status:'ready',ready:true})]; break;
    case 'FORGOTTEN_WORK': w.createdAt='2026-07-23T00:00:00.000Z'; break;
    case 'CANCELLED_NO_REPLACEMENT': s.bookings=[booking('b1','w1',{status:'cancelled'})]; break;
    case 'NEXT_DEPARTMENT_UNPLANNED': w.nextDepartment='QC'; break;
    case 'NO_PROGRESS': w.status='started'; w.lastProgressAt='2026-07-23T00:00:00.000Z'; break;
    case 'STALE_STOPPAGE': w.status='stoppage'; w.stoppageReason='hold'; w.stoppageOwner='u'; w.stoppageNextAction='review'; w.stoppageReviewAt='2026-07-28T00:00:00.000Z'; w.stoppageExpectedResolutionAt='2026-07-30T00:00:00.000Z'; break;
    case 'QC_NOT_RFT': v.qcComplete=true; break;
    case 'RFT_NOT_COLLECTED': v.rftAt='2026-07-27T00:00:00.000Z'; break;
    case 'IT_AT_ETA_NO_PLAN': v.location='IT'; v.eta='2026-07-29T03:00:00.000Z'; break;
    case 'YH_READY_NOT_REVIEWED': v.location='YH'; v.yhReadyAt='2026-07-29T03:00:00.000Z'; break;
    case 'WORK_STOPPAGE': w.status='stoppage'; break;
    case 'BOOKING_STOPPAGE': s.bookings=[booking('b1','w1',{status:'stoppage'})]; break;
    case 'STOPPAGE_DETAILS_INCOMPLETE': w.status='stoppage'; break;
    case 'WORKFLOW_SEQUENCE_INVALID': w.status='completed'; w.completedAt=NOW_ISO; w.completedBy='u'; w.requiredPriorWorkIds=['missing']; break;
    case 'WORKFLOW_STATUS_INVALID': w.status='mystery'; break;
    case 'BOOKING_STATUS_INVALID': s.bookings=[booking('b1','w1',{status:'mystery'})]; break;
    case 'STARTED_WORK_WITHOUT_STARTED_BOOKING': w.status='started'; break;
    case 'COMPLETED_WORK_MISSING_EVIDENCE': w.status='completed'; break;
    case 'CANCELLED_WORK_MISSING_REASON': w.status='cancelled'; break;
    case 'FUTURE_BOOKING_MARKED_STARTED': w.status='started'; s.bookings=[booking('b1','w1',{status:'started'})]; break;
    case 'SUBLET_PLANNER_FORBIDDEN': w.type='Sublet'; w.external=true; w.plannerEligible=true; break;
    default: throw new Error(`No direct fixture for ${id}`);
  }
  return s;
}
const snapshots=Object.freeze(DEALERS.map((d,i)=>buildDealerSnapshot(d,i+1))),fixtureCount=snapshots.reduce((n,s)=>n+s.vehicles.length,0);
module.exports=Object.freeze({DEALERS,NOW_ISO,snapshots,fixtureCount,buildDealerSnapshot,buildRuleFixture});
