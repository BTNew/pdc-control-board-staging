'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const plannerSource = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const rosterMatch = appSource.match(/const DEFAULT_MECHANICS = (\[[\s\S]*?\n\]);/);
assert.ok(rosterMatch, 'The approved mechanic roster must be defined in app.js');
const roster = vm.runInNewContext(rosterMatch[1]);
const expected = [
  'Ajafari Abdelkrim',
  'Andrew McCormick',
  'Ben Palmer',
  'Chelsea Rees # 2',
  'Daniel Evelyn',
  'Gurmohan Singh',
  'James Ierino',
  'Jamie Bello',
  'Joe Izzi',
  'John Castagna',
  'Jundullah Sharif Ramli',
  'Kade Bailey',
  'Luke Walton',
  'Nick Darker',
  'Ratchapool Jaumorn',
  'Ravindra Singh',
  'Richard Tatov',
  'Robert Celenza',
  'Samuel Sherratt',
  'Simon Duncan',
  'Simon Fraser',
  'Thanh Truong',
  'Wilfredo Aquionos',
  'Winn Chiu Pang',
  'Zachary King',
];
assert.deepStrictEqual(Array.from(roster), expected, 'The roster must exactly match the supplied department 138 and 139 screenshots');
assert.strictEqual(new Set(roster).size, 25, 'Duplicate staff appearing in both departments must only be listed once');
assert.ok(appSource.includes("const MECHANICS_ROSTER_SEED_VERSION = '2026-07-15-departments-138-139-v1'"), 'The historical roster-seed version marker constant must remain defined for the Stage 2A browser-data importer to reference');
// Stage 2A (independent-review remediation, localStorage-to-Supabase
// migration): mechanics are now authoritative in Supabase
// (public.workshop_technicians via workshop-reference-data-service.js).
// DEFAULT_MECHANICS/MECHANICS_KEY/MECHANICS_ROSTER_SEED_KEY are no longer
// used to seed or read a browser's local mechanic list -- the constants
// remain defined only so the Stage 2A browser-data importer can still
// read a given staff computer's old local roster. loadMechanics() must
// read exclusively from the Supabase-backed reference-data service.
assert.ok(!appSource.includes('const roster = normalizedMechanicList(DEFAULT_MECHANICS);'), 'Stage 2A: loadMechanics() must no longer auto-seed a browser mechanic list from DEFAULT_MECHANICS');
assert.ok(appSource.includes('function loadMechanics()') && /function loadMechanics\(\) \{[\s\S]{0,400}initWorkshopReferenceDataServiceIfAvailable/.test(appSource), 'Stage 2A: loadMechanics() must read from the Supabase-backed workshop reference data service, not localStorage');
assert.ok(!/CRM_BACKUP_STORAGE_KEYS = \[[\s\S]*?MECHANICS_KEY,[\s\S]*?\];/.test(appSource.replace(/\/\/.*$/gm, '')), 'Stage 2A: MECHANICS_KEY must no longer be exported by the browser-local backup key list (mechanics are covered by the Supabase encrypted backup instead)');
assert.ok(plannerSource.includes('const options = cleanSelected && !names.includes(cleanSelected) ? [cleanSelected, ...names] : names;'), 'Existing plans assigned to an old mechanic must retain that selected historical name');

console.log('Mechanic roster regression checks passed');
