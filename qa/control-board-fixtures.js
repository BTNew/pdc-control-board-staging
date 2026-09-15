(function (root, factory) {
  'use strict';
  const fixtures = factory();
  if (typeof module === 'object' && module.exports) module.exports = fixtures;
  else root.ControlBoardFixtures = fixtures;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const stages = [['BUS_4X4', 8], ['TINT', 2], ['HOIST', 3], ['FITTING', 5], ['FABRICATION', 13], ['ELECTRICAL', 10], ['TYRE', 2]];
  const uuid = number => `${Number(number).toString(16).padStart(8, '0')}-0000-4000-8000-000000000001`;
  const vehicle = (number, overrides = {}) => ({
    id: uuid(10000 + number), stock_number: `DEMO-${String(number).padStart(4, '0')}`,
    key_number: String(number + 100), job_card_number: `DEMO-JC-${number}`,
    customer_name: number % 3 === 0 ? 'Demonstration community services with a long customer name' : `Demonstration customer ${number}`,
    vehicle_description: number % 4 === 0 ? 'HiLux 4x4 2.8L Diesel Double Cab automatic with canopy and accessories' : 'Demonstration Hilux DCC',
    current_location: 'PMB', ...overrides,
  });
  function emptySnapshot() {
    let number = 0;
    return {
      generated_at: '2026-09-15T01:00:00Z',
      stages: stages.map(([code], index) => ({ code, display_name: code, planner_enabled: true, revision: index + 1 })),
      candidates: [], pipeline: [],
      board: {
        calendar: { day_start_time: "07:00", day_end_time: "17:00", working_week: ["monday","tuesday","wednesday","thursday","friday","saturday"], closures: [], break_windows: [{scope:"saturday",start:"07:00",end:"08:00"},{scope:"saturday",start:"12:00",end:"17:00"}], overtime_windows: [] },
        bays: stages.flatMap(([stage, count], index) => Array.from({ length: count }, (_, offset) => ({
          bay_id: uuid(++number), stage_id: uuid(500 + index), stage_code: stage, bay_number: offset + 1,
          display_name: `${stage} Bay ${offset + 1}`, is_active: true, efficiency_percent: 100,
          technician_name: offset === 0 ? `Demo technician ${index + 1}` : null,
        }))),
        bookings: [], admin_blocks: [],
      },
    };
  }
  function booking(number, bay, person = vehicle(number), overrides = {}) {
    return {
      booking_id: uuid(20000 + number), vehicle_id: person.id, vehicle: person,
      stage_code: bay.stage_code, bay_id: bay.bay_id, bay_number: bay.bay_number,
      status: 'planned', scheduled_start_at: '2026-09-15T02:00:00Z',
      scheduled_end_at: '2026-09-15T04:00:00Z', version: 1, ...overrides,
    };
  }
  function populatedSnapshot() {
    const snapshot = emptySnapshot();
    snapshot.board.bays.forEach((bay, index) => {
      if (index % 5 === 4) return;
      const depth = index % 7 === 0 ? 7 : index % 3 + 1;
      for (let n = 0; n < depth; n += 1) {
        const number = index * 10 + n + 1;
        const hour = 1 + n;
        snapshot.board.bookings.push(booking(number, bay, vehicle(number), {
          status: n === 0 && index % 6 === 0 ? 'started' : n === 0 && index % 8 === 0 ? 'stoppage' : 'planned',
          scheduled_start_at: `2026-09-15T${String(hour).padStart(2, '0')}:00:00Z`,
          scheduled_end_at: `2026-09-15T${String(hour + 1).padStart(2, '0')}:00:00Z`,
        }));
      }
    });
    // One vehicle has a later booking in another department, not a duplicate card.
    const first = snapshot.board.bookings[0];
    const tyre = snapshot.board.bays.find(bay => bay.stage_code === 'TYRE');
    snapshot.board.bookings.push(booking(900, tyre, first.vehicle, { scheduled_start_at: '2026-09-17T02:00:00Z', scheduled_end_at: '2026-09-17T03:00:00Z' }));
    snapshot.candidates = stages.map(([stage], index) => ({ stage_code: stage, vehicle: vehicle(1000 + index, { current_location: index === 0 ? 'YH' : index === 1 ? 'IT' : 'PMB' }), existing_booking: false, schedule_enabled: index !== 2, disabled_reason: index === 2 ? 'estimated_duration_missing' : null }));
    snapshot.board.bookings.push(booking(901, snapshot.board.bays[0], vehicle(1100), { status: 'queued', bay_id: null, bay_number: null }));
    snapshot.board.admin_blocks.push({ block_id: uuid(30000), stage_code: 'FITTING', bay_id: snapshot.board.bays.find(bay => bay.stage_code === 'FITTING').bay_id, label: 'Demonstration maintenance', block_type: 'admin', scheduled_start_at: '2026-09-15T04:00:00Z', scheduled_end_at: '2026-09-15T05:00:00Z', version: 1 });
    snapshot.board.bays[12].is_active = false;
    snapshot.board.bays[12].efficiency_percent = 80;
    return snapshot;
  }
  return { stages, uuid, vehicle, booking, emptySnapshot, populatedSnapshot };
});
