'use strict';
const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');

const adminSlice = app.slice(app.indexOf('function renderAdminList'), app.indexOf('function renderBackupStatusPanel'));
assert(adminSlice.includes('admin-reference-table'), 'Mechanics and Sublet providers must render as compact reference tables');
assert(adminSlice.includes('<th>Name</th><th>Status</th><th>Actions</th>'), 'Reference list columns must match the requested layout');
assert(adminSlice.includes('admin-status-badge is-active'), 'Reference rows must show an active status badge');
assert(!adminSlice.includes('<span class="admin-chip">'), 'Mechanics and providers must not render as pills');

const userRow = app.slice(app.indexOf('function userManagementRowHtml'), app.indexOf('async function renderUserManagementScreen'));
assert(userRow.includes('admin-status-badge'), 'User rows must show status badges');
assert(!userRow.includes('registered_at') && !userRow.includes('last_sign_in_at'), 'Compact user table must omit audit-date columns from the visible row');
const userRender = app.slice(app.indexOf('async function renderUserManagementScreen'), app.indexOf('function subscribeUserManagementRealtime'));
assert(userRender.includes('<th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Actions</th>'), 'User table must match the requested five-column layout');
assert(staging.includes('<h2>User Administration</h2>'), 'Screen heading must match the requested layout');
assert(staging.includes('<h2>Sublet provider list</h2>') && staging.includes('admin-reference-panel'), 'Mechanics and Sublet provider tables must use full-width administration panels');
assert(styles.includes('.admin-reference-table'), 'Shared compact table styling must exist');
assert(styles.includes('text-align: right'), 'Actions must align to the right like the reference');

console.log('Compact mechanics, Sublet provider and user administration layout contracts passed');
