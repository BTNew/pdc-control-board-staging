'use strict';
const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8').replace(/\r\n/g, '\n');
const staging = fs.readFileSync('staging.html', 'utf8').replace(/\r\n/g, '\n');
const styles = fs.readFileSync('styles.css', 'utf8').replace(/\r\n/g, '\n');

const nav = staging.slice(staging.indexOf('<nav class="nav">'), staging.indexOf('</nav>') + 6);
assert(!nav.includes('data-view="visibility"') && !nav.includes('>Operations<'), 'Operations must not remain in staging navigation');
assert(nav.includes('id="nav-admin-toggle"') && nav.includes('aria-expanded="false"') && nav.includes('aria-controls="nav-admin-menu"'), 'Admin must be an accessible disclosure button');
assert(nav.includes('id="nav-admin-group" hidden'), 'Admin navigation must remain fail-closed until an authenticated Administrator is confirmed');
const menu = nav.slice(nav.indexOf('id="nav-admin-menu"'), nav.indexOf('</div>', nav.indexOf('id="nav-admin-menu"')));
const adminEntries = [
  ['User Management', 'user-management'],
  ['Setup', 'lists'],
  ['Navision Uploads', 'import'],
  ['Backup / Restore', 'backup'],
  ['Deleted Vehicles', 'deleted'],
  ['Completed Vehicles', 'completed'],
  ['Back End Data', 'backend'],
];
let previous = -1;
for (const [label, view] of adminEntries) {
  const marker = `data-view="${view}"`;
  const at = menu.indexOf(marker);
  assert(at > previous, `${label} must appear in the requested Admin menu order`);
  assert(menu.includes(`>${label}</button>`), `${label} must use the requested staff-facing label`);
  previous = at;
}
assert(app.includes('const allowed = Boolean(window.PDC_AUTH_CONTEXT?.userId || window.PDC_AUTH_CONTEXT?.email);'), 'Admin menu must be visible to every approved signed-in staff member');
assert(!app.slice(app.indexOf('function syncAdminNavigationVisibility()'), app.indexOf('function bindNav()')).includes('backupStatusSharedModeReady'), 'Admin menu visibility must not depend on backup readiness');
assert(app.includes("$$('.nav-item[data-view]')"), 'Admin disclosure button must not be treated as a page route');
assert(app.includes('setAdminNavigationExpanded') && app.includes('syncAdminNavigationVisibility'), 'Admin disclosure state and auth visibility must be synchronized');

const dashboard = staging.slice(staging.indexOf('<section id="dashboard"'), staging.indexOf('<section id="workflow"'));
assert(dashboard.includes('class="incoming-search-panel incoming-search-only"'), 'Vehicle Locations must retain one simplified search');
assert(dashboard.includes('id="incoming-search"'), 'Vehicle Locations search input must remain available');
for (const removed of ['id="kpi-grid"', 'id="incoming-status-filter"', 'id="incoming-bucket-filter"', 'id="incoming-more-filters"', 'id="incoming-find"', 'id="incoming-clear-filters"']) {
  assert(!dashboard.includes(removed), `Vehicle Locations must remove ${removed}`);
}
assert(styles.includes('.incoming-search-panel.incoming-search-only'), 'Search-only Vehicle Locations layout needs responsive styling');

const intake = staging.slice(staging.indexOf('<section id="emailreview"'), staging.indexOf('<section id="sublet"'));
assert(intake.includes('AI / Email Intake') && intake.includes('Approve or deny the items that need a decision.'), 'AI Intake heading must be concise and decision-focused');
assert(!intake.includes('ai-board-advisor-panel') && staging.includes('<section id="ai-auditor"'), 'Read-only auditing must be separate from the staff-facing intake screen');
assert(intake.includes('class="email-intake-upload-panel"') && intake.includes('aria-label="AI file assistant upload" hidden'), 'Legacy local upload drafts must be preserved but removed from the staff-facing intake screen');
assert(app.includes('>✓ Approve</button>') && app.includes('>× Deny</button>'), 'Tricky pending intake items must expose Approve and Deny actions');
assert(app.includes("data-ai-intake-apply=") && app.includes("data-ai-intake-reject="), 'Approve and Deny labels must retain the authoritative apply/reject handlers');
assert(app.includes("service.decide(attempt.proposal, decision, reason, attempt.idempotencyKey)"), 'Decisions must still use authoritative idempotent server apply');
assert(styles.includes('.ai-intake-review-card') && styles.includes('.ai-intake-decision-panel') && styles.includes('.ai-intake-approve') && styles.includes('.ai-intake-deny'), 'Clean intake card and decision styling is required');

console.log('Admin navigation, simplified AI Intake and search-only Vehicle Locations checks passed');
