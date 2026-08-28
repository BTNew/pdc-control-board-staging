'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const offerStart = app.indexOf('function offerSalespersonChangeEmail(');
const offerEnd = app.indexOf('\nfunction vehicleOutstandingWorkEmailLines', offerStart);
const offer = app.slice(offerStart, offerEnd);

function ruleZIndex(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const rules = [...css.matchAll(new RegExp(`${escaped}\\s*\\{([^}]*)\\}`, 'g'))];
  assert.ok(rules.length, `Missing CSS rule for ${selector}`);
  const declarations = rules
    .map(rule => rule[1].match(/z-index\s*:\s*(\d+)/))
    .filter(Boolean);
  assert.ok(declarations.length, `Missing numeric z-index for ${selector}`);
  return Number(declarations.at(-1)[1]);
}

const baseModalZIndex = ruleZIndex('#vehicle-modal');
const emailModalZIndex = ruleZIndex('.sales-change-email-overlay');

assert.ok(
  emailModalZIndex > baseModalZIndex,
  `EMAIL UPDATE dialog z-index (${emailModalZIndex}) must exceed the vehicle modal (${baseModalZIndex})`,
);
assert.ok(offer.includes("overlay.className = 'modal-overlay sales-change-email-overlay';"), 'EMAIL UPDATE dialog must use the specialised top-layer class');
assert.ok(offer.includes('document.body.appendChild(overlay);'), 'EMAIL UPDATE dialog must remain a body-level sibling of the vehicle modal');
assert.ok(offer.includes("if (event.key === 'Tab')"), 'EMAIL UPDATE dialog must take first ownership of Tab');
assert.ok(offer.includes('trapModalFocus(overlay, event);'), 'EMAIL UPDATE dialog must trap keyboard focus above the vehicle modal');
assert.ok(offer.includes("if (event.key !== 'Escape') return;"), 'EMAIL UPDATE dialog must take first ownership of Escape');
assert.ok(offer.includes('if (returnFocus instanceof HTMLElement && returnFocus.isConnected) returnFocus.focus();'), 'closing EMAIL UPDATE must restore focus to its opener');
assert.ok(html.includes('styles.css?v=2026.08.29.737-email-update-modal-front'), 'staging entrypoint must cache-bust the repaired stylesheet');
assert.ok(html.includes('email-modal=2026.08.29.737-email-update-modal-front'), 'staging entrypoint must cache-bust the repaired modal keyboard handler');

console.log('EMAIL UPDATE modal layering contract passed.');