'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const production = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const sharedStyles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const overlay = fs.readFileSync(path.join(root, 'pdc-ai-intake-review.js'), 'utf8');
const overlayStyles = fs.readFileSync(path.join(root, 'pdc-ai-intake-review.css'), 'utf8');

const appIndex = staging.indexOf('src="app.js');
const helperIndex = staging.indexOf('src="pdc-ai-intake-review.js');
assert.ok(helperIndex >= 0, 'summary overlay must be loaded in staging');
assert.ok(helperIndex > appIndex, 'summary overlay must load after app.js so it can wrap the existing renderer and decision path');
assert.match(staging, /pdc-ai-intake-review\.css\?v=2026\.07\.28\.20-ai-review-card-separation/, 'staging must load the dedicated overlay stylesheet with the card-separation cache version');
assert.doesNotMatch(production, /pdc-ai-intake-review\.(?:js|css)/, 'production HTML must remain untouched');
assert.doesNotMatch(app, /ai-review-decision-context|buildAiIntakeReviewSummary|ai-intake-decision-effects/, 'shared app.js must remain untouched by this staging-only patch');
assert.doesNotMatch(sharedStyles, /ai-intake-decision-effects/, 'shared production stylesheet must remain untouched');
assert.match(overlay, /function decideServerAiIntakeWithSummaryGate/, 'overlay must wrap direct decision calls');
assert.match(overlay, /const normalizedDecision = normalizeAiIntakeDecision\(decision\)/, 'all decision spellings must be normalized before gating');
assert.match(overlay, /if \(normalizedDecision === 'apply'\)/, 'every normalized apply call must receive the summary gate');
assert.match(overlay, /originalDecision\.call\(this, proposalId, normalizedDecision\)/, 'the original decision path must receive the same normalized value used by the gate');
assert.match(overlay, /if \(!proposal \|\| !buildAiIntakeReviewSummary\(proposal\)\.approvalReady\)/, 'direct apply calls must fail closed without a readable summary');
assert.match(overlay, /paragraph\.textContent = review\.text/, 'summary content must be assigned as text, not HTML');
assert.match(overlay, /warning\.textContent = review\.warning/, 'warning content must be assigned as text, not HTML');
assert.match(overlayStyles, /\.ai-intake-email-summary\.is-missing/, 'missing summaries must receive visible warning styling');
assert.match(overlayStyles, /\.ai-intake-decision-effects/, 'decision consequences must receive dedicated styling');
assert.match(overlayStyles, /\.ai-intake-server-list\s*\{[^}]*gap:\s*18px/s, 'email cards must have a clearly visible gap');
assert.match(overlayStyles, /\.ai-intake-server-list\s*\{[^}]*padding:\s*16px/s, 'email list must expose a dark separator gutter');
assert.match(overlayStyles, /\.ai-intake-server-list\s*\{[^}]*background:\s*#374151/s, 'email cards must sit on a dark grey list background');
assert.match(app, /const APP_VERSION = '\d{4}\.\d{2}\.\d{2}\.[^']+'/, 'shared app must retain an explicit cache-busting release version independent of the staging-only overlay');

console.log('AI Intake summary overlay integration tests passed');
