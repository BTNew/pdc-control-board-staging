'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const copyStart = appSource.indexOf('async function copyTextToClipboard');
const copyEnd = appSource.indexOf('\nfunction navisionDealerNoteText', copyStart);
assert.ok(copyStart >= 0 && copyEnd > copyStart, 'Stock copy behavior is extractable');
const copySource = appSource.slice(copyStart, copyEnd);

function createCopyContext({ clipboard, execResult = true, execError = null } = {}) {
  const timers = [];
  const textareas = [];
  const context = {
    navigator: clipboard === undefined ? {} : { clipboard },
    document: {
      body: {
        appendChild(node) {
          node.isConnected = true;
        },
      },
      createElement(tag) {
        assert.strictEqual(tag, 'textarea');
        const node = {
          value: '',
          style: {},
          selected: false,
          removed: false,
          setAttribute() {},
          select() { this.selected = true; },
          remove() {
            this.removed = true;
            this.isConnected = false;
          },
        };
        textareas.push(node);
        return node;
      },
      execCommand(command) {
        assert.strictEqual(command, 'copy');
        if (execError) throw execError;
        return execResult;
      },
    },
    window: {
      setTimeout(callback, delay) {
        timers.push({ callback, delay });
        return timers.length;
      },
    },
  };
  vm.createContext(context);
  vm.runInContext(copySource, context);
  return { context, timers, textareas };
}

function feedbackTargets() {
  return {
    button: { textContent: 'Copy', isConnected: true },
    status: { textContent: '' },
  };
}

(async () => {
  {
    const writes = [];
    const { context, timers, textareas } = createCopyContext({
      clipboard: { async writeText(value) { writes.push(value); } },
    });
    const { button, status } = feedbackTargets();
    const copied = await context.copyVehicleStockNumber('HERMES-PDC14-67594974', button, status);
    assert.strictEqual(copied, true, 'Clipboard API success is reported');
    assert.deepStrictEqual(writes, ['HERMES-PDC14-67594974'], 'Clipboard receives the exact Stock Number');
    assert.strictEqual(textareas.length, 0, 'Clipboard API success does not use the fallback');
    assert.strictEqual(button.textContent, 'Copied', 'success has deterministic visible button feedback');
    assert.strictEqual(status.textContent, 'Copied HERMES-PDC14-67594974', 'success has deterministic aria-live feedback');
    assert.strictEqual(timers[0].delay, 1500);
    timers[0].callback();
    assert.strictEqual(button.textContent, 'Copy', 'success button feedback resets deterministically');
  }

  {
    const { context, textareas } = createCopyContext({
      clipboard: { async writeText() { throw new Error('permission denied'); } },
      execResult: true,
    });
    const { button, status } = feedbackTargets();
    const copied = await context.copyVehicleStockNumber('STOCK-REJECTION', button, status);
    assert.strictEqual(copied, true, 'Clipboard API rejection falls back without throwing');
    assert.strictEqual(textareas[0].value, 'STOCK-REJECTION', 'rejection fallback receives the exact Stock Number');
    assert.strictEqual(textareas[0].selected, true);
    assert.strictEqual(textareas[0].removed, true, 'rejection fallback is cleaned up');
    assert.strictEqual(button.textContent, 'Copied');
    assert.strictEqual(status.textContent, 'Copied STOCK-REJECTION');
  }

  {
    const { context, textareas } = createCopyContext({ execResult: true });
    const { button, status } = feedbackTargets();
    const copied = await context.copyVehicleStockNumber('STOCK-UNAVAILABLE', button, status);
    assert.strictEqual(copied, true, 'unavailable Clipboard API uses the fallback without throwing');
    assert.strictEqual(textareas[0].value, 'STOCK-UNAVAILABLE');
    assert.strictEqual(textareas[0].removed, true);
    assert.strictEqual(button.textContent, 'Copied');
    assert.strictEqual(status.textContent, 'Copied STOCK-UNAVAILABLE');
  }

  {
    const { context, textareas } = createCopyContext({ execResult: false });
    const { button, status } = feedbackTargets();
    const copied = await context.copyVehicleStockNumber('STOCK-FAILURE', button, status);
    assert.strictEqual(copied, false, 'fallback failure is handled without an uncaught exception');
    assert.strictEqual(textareas[0].removed, true, 'failed fallback is cleaned up');
    assert.strictEqual(button.textContent, 'Copy failed', 'failure has deterministic visible button feedback');
    assert.strictEqual(status.textContent, 'Clipboard copy is unavailable. Select and copy the Stock Number manually.', 'failure has explicit aria-live feedback');
  }

  console.log('PDC-14 Copy Stock feedback regression: PASS');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
