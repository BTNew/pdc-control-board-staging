/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r406 (F17): the planner shows and sends times in Australia/Perth whatever the
// device's timezone. Perth has no daylight saving (always UTC+8).
// r406 (F18): the Bus Pit inspections list recognises Pit by wording (r405 rule).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const { execFileSync } = require('child_process');

const src = fs.readFileSync('workshop-planner.js', 'utf8');
const FUNCTIONS = ['workshopPad', 'workshopClockMinutes', 'workshopSetClock', 'workshopPerthWeekday', 'workshopPerthAddDays',
  'workshopPerthLocalInputValue', 'workshopParsePerthLocalInput', 'workshopValidDateKey', 'workshopDateKey', 'workshopDateFromKey',
  'workshopCalendarDateKeyOffset', 'workshopBusShift', 'workshopCalendarStartMinutes', 'workshopIsConfiguredWorkingDay',
  'workshopIsClosureDate', 'workshopIsWorkday', 'workshopCoerceWorkDate', 'workshopPerthMinutesOfDay', 'workshopDefaultOpenDateKey',
  'workshopShiftWorkday', 'workshopWeekStart', 'workshopWeekDates', 'workshopIntervalsOverlap', 'workshopMinuteOfDay',
  'workshopWindowApplies', 'workshopSubtractWindows', 'workshopAvailabilityWindowsForDate', 'workshopMoveToNextWorkStart',
  'workshopNormalizeStartDate', 'workshopAddWorkMinutes', 'workshopWorkMinutesBetween', 'workshopNextWorkdayDate'];

function extract(name) {
  const start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let i = src.indexOf('(', start), depth = 0;
  for (; i < src.length; i += 1) {
    if (src[i] === '(') depth += 1;
    if (src[i] === ')' && --depth === 0) break;
  }
  i = src.indexOf('{', i);
  for (depth = 0; i < src.length; i += 1) {
    if (src[i] === '{') depth += 1;
    if (src[i] === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(name);
}

const program = `
const WORKSHOP_DAY_NAME_TO_INDEX = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
let WORKSHOP_PLANNER_CONFIG = { dayStartMinutes: 420, dayEndMinutes: 1020, dayLengthMinutes: 600, schedulingIncrementMinutes: 15,
  defaultBookingDurationMinutes: 60, workingDayIndexes: [1, 2, 3, 4, 5], closureDateKeys: ['2026-10-23'],
  breakWindowsByDateOrScope: [{ startMinutes: 720, endMinutes: 750, dateKey: '', scope: 'global' }],
  overtimeWindowsByDateOrScope: [], technicianLeaveByTechnicianId: {} };
${FUNCTIONS.map(extract).join('\n')}
const iso = d => d.toISOString();
const out = {
  // 21 Oct 2026 23:30 UTC = Thursday 22 Oct 07:30 Perth
  dateKey: workshopDateKey(new Date('2026-10-21T23:30:00Z')),
  weekday: workshopPerthWeekday(new Date('2026-10-21T23:30:00Z')),
  minute: workshopMinuteOfDay(new Date('2026-10-21T23:30:00Z')),
  fromKey: iso(workshopDateFromKey('2026-10-22')),
  setClock: iso(workshopSetClock(new Date('2026-10-21T23:30:00Z'), 600)),
  offsetKey: workshopCalendarDateKeyOffset('2026-10-31', 1),
  workday: workshopIsWorkday(new Date('2026-10-23T01:00:00Z')),
  coerce: iso(workshopCoerceWorkDate(new Date('2026-10-23T01:00:00Z'), 1)),
  normalize: iso(workshopNormalizeStartDate(new Date('2026-10-22T09:05:00Z'))),
  addWork: iso(workshopAddWorkMinutes(new Date('2026-10-22T07:00:00Z'), 180)),
  between: workshopWorkMinutesBetween(new Date('2026-10-21T23:00:00Z'), new Date('2026-10-26T09:00:00Z')),
  weekStart: iso(workshopWeekStart(new Date('2026-10-21T23:30:00Z'))),
  weekDates: workshopWeekDates(new Date('2026-10-21T23:30:00Z')).map(workshopDateKey),
  shift: iso(workshopShiftWorkday(new Date('2026-10-22T02:00:00Z'), 1)),
  openAfterShift: workshopDefaultOpenDateKey(new Date('2026-10-21T09:30:00Z')),
  openDuringShift: workshopDefaultOpenDateKey(new Date('2026-10-21T01:00:00Z')),
  nextWorkday: iso(workshopNextWorkdayDate(new Date('2026-10-22T02:00:00Z'))),
  inputValue: workshopPerthLocalInputValue(new Date('2026-10-21T23:30:00Z')),
  parsedInput: iso(workshopParsePerthLocalInput('2026-10-22T07:30')),
  parsedIsoKeepsZone: iso(workshopParsePerthLocalInput('2026-10-22T07:30:00+10:00')),
  label: new Date('2026-10-21T23:30:00Z').toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', hour: 'numeric', minute: '2-digit' }),
};
process.stdout.write(JSON.stringify(out));`;

function runIn(tz) {
  return JSON.parse(execFileSync(process.execPath, ['-e', program], { env: { ...process.env, TZ: tz }, encoding: 'utf8' }));
}

const ZONES = ['Australia/Perth', 'UTC', 'Australia/Sydney', 'America/Los_Angeles', 'Asia/Kolkata', 'Pacific/Kiritimati', 'Pacific/Pago_Pago'];

test('planner date maths gives the same Perth answers on a device in any timezone', () => {
  const perth = runIn('Australia/Perth');
  assert.deepStrictEqual(perth, {
    dateKey: '2026-10-22', weekday: 4, minute: 450,
    fromKey: '2026-10-21T23:00:00.000Z',
    setClock: '2026-10-22T02:00:00.000Z',
    offsetKey: '2026-11-01',
    workday: false, // 23 Oct is a closure
    coerce: '2026-10-25T23:00:00.000Z', // Monday 26 Oct 07:00 Perth
    normalize: '2026-10-25T23:00:00.000Z', // Thu 17:05 Perth is after the day; Fri closed -> Mon 07:00 Perth
    addWork: '2026-10-26T00:00:00.000Z', // Thu 15:00 Perth + 3 h: 2 h Thu, Fri closed, 1 h Mon -> 08:00 Perth
    between: 1140, // Thu 570 + Mon 570 work minutes (30 min break), Fri closed
    weekStart: '2026-10-18T23:00:00.000Z', // Monday 19 Oct 07:00 Perth
    weekDates: ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23'],
    shift: '2026-10-25T23:00:00.000Z', // one workday after Thu -> Mon 07:00 Perth
    openAfterShift: '2026-10-22', // 17:30 Perth Wed -> Thursday
    openDuringShift: '2026-10-21',
    nextWorkday: '2026-10-25T23:00:00.000Z', // Fri 23 Oct is closed -> Monday 26 Oct 07:00 Perth
    inputValue: '2026-10-22T07:30',
    parsedInput: '2026-10-21T23:30:00.000Z',
    parsedIsoKeepsZone: '2026-10-21T21:30:00.000Z',
    label: perth.label,
  });
  for (const tz of ZONES.slice(1)) assert.deepStrictEqual(runIn(tz), perth, tz);
});

test('the planner source never uses device-local date fields or unzoned labels', () => {
  const code = src.replace(/\/\/.*$/gm, '');
  const local = code.match(/\.(getHours|getMinutes|getDate|getDay|getMonth|getFullYear|setHours|setMinutes|setDate|setMonth|setFullYear)\(/g) || [];
  // The one allowed read converts parseDateAU's device-local d/m/y back to a calendar date.
  assert.deepStrictEqual(local, ['.getFullYear(', '.getMonth(', '.getDate('], local.join(' '));
  assert.match(code, /Date\.UTC\(local\.getFullYear\(\), local\.getMonth\(\), local\.getDate\(\)\) - 8 \* 3600000/);
  assert.doesNotMatch(code, /new Date\(\s*[A-Za-z_.[\]0-9]+\s*,\s*[A-Za-z_.[\]0-9]+\s*(-\s*1\s*)?,/, 'no new Date(y, m, d)');
  for (const call of code.match(/\.toLocale(?:String|DateString|TimeString)\([^;]*/g) || []) {
    assert.ok(/timeZone: 'Australia\/Perth'|dateOptions/.test(call), call.slice(0, 120));
  }
  assert.match(code, /const start = workshopParsePerthLocalInput\(String\(data\.get\('startAt'\)/, 'Schedule form start is read as Perth time');
  assert.strictEqual((code.match(/workshopPerthLocalInputValue\(start\)/g) || []).length, 2, 'Schedule form start is shown in Perth time');
});

test('F18: Bus Pit list finds Pit lines by wording in every department', () => {
  const layout = require('./pdc-workshop-departments.js');
  const vehicle = lines => ({ __emailVehicleServerAuthoritative: true, pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: lines });
  const line = (description, stageCode, department, extra = {}) => ({ lineIdentity: `source:${description}`, description, stageCode, department, active: true, completed: false, ...extra });
  const pit = ['PIT AND WEIGH', 'Pit & Weigh', 'Pit and weigh', 'PIT N WEIGH', "PIT 'N' WEIGH", 'PITS AND WEIGH', 'PIT/WEIGH', 'PIT+WEIGH', 'PIT  AND  WEIGH', 'PIT INSPECTION', 'PIT INSPECT FOR TRANSFER TO WA REGISTRATION', 'Supply pit and weigh certificate'];
  const not = ['Complete Pre-Delivery Inspection', 'PITS - REFER BRYCE', 'TRANSPORT TO PITS', 'NO PITTING REQUIRED', 'PIT FEE FOR FUEL TANK CERTIFICATION', 'MECHANICAL INSPECTION AN PIT PASSING', 'SPITWEIGHT', ''];
  for (const d of pit) for (const [stage, dept] of [['FITTING', '139'], ['SUBLET', '139'], ['BUS_4X4', '138']]) {
    assert.strictEqual(layout.externalPitLines(vehicle([line(d, stage, dept)])).length, 1, `${d} ${stage} ${dept}`);
  }
  for (const d of not) assert.strictEqual(layout.externalPitLines(vehicle([line(d, 'FITTING', '139')])).length, 0, d);
  assert.strictEqual(layout.externalPitLines(vehicle([line('External check', 'PIT_INSPECTION', '138')])).length, 1, 'stage still counts');
  for (const extra of [{ completed: true }, { active: false }, { rejected: true }]) {
    assert.strictEqual(layout.externalPitLines(vehicle([line('PIT AND WEIGH', 'FITTING', '139', extra)])).length, 0, JSON.stringify(extra));
  }
  const departments = fs.readFileSync('pdc-workshop-departments.js', 'utf8');
  const app = fs.readFileSync('app.js', 'utf8');
  const rule = String.raw`/(^|[^A-Z])PITS? ?(AND|&|\+|\/|N|'N')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT/`;
  assert.ok(departments.includes(rule) && app.includes(rule), 'same wording rule as the QC page and the server (r405)');
  assert.match(app, /<th>Dept<\/th><th>Inspection required<\/th>/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.strictEqual((html.match(/pdc-workshop-departments\.js\?[^"]*pit-text=2026\.10\.21\.01/g) || []).length, 1);
  assert.strictEqual((html.match(/app\.js\?[^"]*r406=2026\.10\.21\.01/g) || []).length, 1);
  assert.strictEqual((app.match(/workshop-planner\.js\?station-scope=2026\.10\.19\.03&r403=2026\.10\.21\.01&r406=2026\.10\.21\.01&/g) || []).length, 2);
});
