'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const repo = __dirname;
const runner = path.join(repo, 'scripts', 'qa_run_checkpointed_process.py');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-qa-supervisor-'));

function run(name, timeoutSeconds, pythonSource) {
  const result = spawnSync('python', [
    runner,
    '--name', name,
    '--evidence-dir', temp,
    '--timeout-seconds', String(timeoutSeconds),
    '--heartbeat-seconds', '0.1',
    '--', 'python', '-c', pythonSource,
  ], { cwd: repo, encoding: 'utf8', timeout: 15000 });
  const state = JSON.parse(fs.readFileSync(path.join(temp, `${name}.supervisor.json`), 'utf8'));
  return { result, state };
}

try {
  const passed = run('pass', 5, "print('checkpoint pass')");
  assert.strictEqual(passed.result.status, 0, passed.result.stderr || passed.result.stdout);
  assert.strictEqual(passed.state.status, 'passed');
  assert.strictEqual(passed.state.returnCode, 0);
  assert.strictEqual(passed.state.stopReason, null);
  assert.ok(fs.readFileSync(path.join(temp, 'pass.log'), 'utf8').includes('checkpoint pass'));

  const timed = run('timeout', 1, 'import time; time.sleep(30)');
  assert.strictEqual(timed.result.status, 124, timed.result.stderr || timed.result.stdout);
  assert.strictEqual(timed.state.status, 'failed');
  assert.strictEqual(timed.state.timedOut, true);
  assert.strictEqual(timed.state.stopReason, 'timeout');
  assert.ok(timed.state.elapsedSeconds < 8, JSON.stringify(timed.state));

  const interrupted = path.join(temp, 'stale.supervisor.json');
  fs.writeFileSync(interrupted, JSON.stringify({ status: 'running', childPid: 999999, marker: 'stale' }));
  const resumed = run('stale', 5, "print('resumed')");
  assert.strictEqual(resumed.result.status, 0, resumed.result.stderr || resumed.result.stdout);
  assert.strictEqual(resumed.state.status, 'passed');
  assert.strictEqual(resumed.state.priorInterruptedRun.marker, 'stale');

  console.log('QA checkpointed process supervisor tests passed');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
