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
assert.ok(appSource.includes("const MECHANICS_ROSTER_SEED_VERSION = '2026-07-15-departments-138-139-v1'"), 'The roster needs a versioned browser migration');
assert.ok(appSource.includes('const roster = normalizedMechanicList(DEFAULT_MECHANICS);'), 'A new roster version must replace stale browser mechanic lists');
assert.ok(appSource.includes('MECHANICS_ROSTER_SEED_KEY,'), 'The roster seed marker must be included in backup storage keys');
assert.ok(plannerSource.includes('const options = cleanSelected && !names.includes(cleanSelected) ? [cleanSelected, ...names] : names;'), 'Existing plans assigned to an old mechanic must retain that selected historical name');

console.log('Mechanic roster regression checks passed');
