'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const production = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const source = fs.readFileSync(path.join(root, 'key-list-review.js'), 'utf8');

assert.match(staging, /id="key-list-review-panel"/, 'staging must expose the authenticated key-list review panel');
assert.match(staging, /key-list-review\.js\?v=2026\.07\.23\.11-key-list-review/, 'staging must load the review module with an immutable cache marker');
assert.doesNotMatch(production, /key-list-review\.js|key-list-review-panel/, 'production HTML must remain unchanged by the staging-only review panel');
assert.match(staging, /Customer names, salesperson details and workbook notes were not imported/, 'review must disclose privacy exclusions');
assert.match(staging, /Ambiguous legacy Hoist records remain operationally unchanged/, 'review must disclose protected ambiguity handling');

assert.match(source, /window\.PDC_AUTH_CONTEXT/, 'review data must require an authenticated context');
assert.match(source, /window\.PDC_SUPABASE/, 'review must use the authenticated deployed client');
assert.match(source, /\.from\('vehicles'\)\s*\.select\(/s, 'review must read vehicle rows');
assert.match(source, /fetchInBatches\(client, 'vehicle_work_items'/, 'review must read actual work-item state');
assert.match(source, /fetchInBatches\(client, 'vehicle_parts_updates'/, 'review must read actual parts state');
assert.match(source, /source_payload->key_list_review->>receipt_id/, 'review must be bounded to receipt-tagged records');
assert.match(source, /pdc-auth-ready/, 'review must load only after approved authentication is ready');
assert.match(source, /pdc-auth-locked/, 'review must clear data immediately when authentication locks');
assert.doesNotMatch(source, /\.(?:insert|update|upsert|delete|rpc)\s*\(/, 'review module must contain no database mutation or RPC call');
assert.doesNotMatch(source, /localStorage|sessionStorage/, 'review module must not persist protected data in browser storage');
assert.doesNotMatch(source, /customer_name|salesperson|operational_notes|workbook_notes/i, 'review query/module must not request excluded personal or note fields');
assert.doesNotMatch(source, /cf5e2bd0-5900-5781-b485-26d6c24e7d5a/, 'review module must not hard-code one receipt ID');
assert.match(staging, /IT rows have no invented ETA/, 'staging review must preserve the IT ETA warning');

console.log('PASS key-list staging review is authenticated, read-only, privacy-bounded and staging-only');
