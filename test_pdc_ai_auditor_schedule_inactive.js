'use strict';

const assert = require('assert');
const fs = require('fs');

const config = JSON.parse(fs.readFileSync('config/pdc-ai-auditor-stage-a-schedule.json', 'utf8'));
assert.strictEqual(config.environment, 'staging');
assert.strictEqual(config.enabled, false, 'Stage A schedule must remain globally disabled');
assert.strictEqual(config.external_delivery_enabled, false, 'external delivery must remain disabled');
assert.strictEqual(config.timezone, 'Australia/Perth');
assert.deepStrictEqual(config.working_calendar.working_days, ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']);
assert.strictEqual(config.working_calendar.working_hour_start, '08:00');
assert.strictEqual(config.working_calendar.working_hour_end_exclusive, '16:00');
assert.deepStrictEqual(config.working_calendar.public_holiday_dates, []);
assert.ok(Array.isArray(config.prepared_jobs) && config.prepared_jobs.length === 4);
assert.ok(config.prepared_jobs.every(job => job.enabled === false), 'every prepared job must remain disabled');
assert.deepStrictEqual(config.prepared_jobs.map(job => job.cron), [
  '*/15 8-15 * * 1-5',
  '0 7 * * 1-5',
  '0 12 * * 1-5',
  '30 15 * * 1-5',
]);
assert.ok(!JSON.stringify(config).match(/telegram|email|webhook/i), 'no external destination may be configured');

console.log('Stage A disabled Australia/Perth schedule contract passed');
