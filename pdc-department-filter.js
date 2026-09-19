/* A display preference shared only by New Vehicles and Vehicle Locations. */
(() => {
  'use strict';
  const browser = typeof window === 'object' ? window : null;
  const STORAGE_KEY = 'pdc_department_view_filter_v1';
  const normalize = value => ['138', '139'].includes(String(value ?? '').trim()) ? String(value).trim() : '';
  const code = value => /^\d{3}$/.test(String(value ?? '').trim()) ? String(value).trim() : '';
  const uniqueCodes = values => [...new Set(values.map(code).filter(Boolean))].sort();
  const label = value => normalize(value) === '138' ? 'Department 138 — Bus 4×4' : normalize(value) === '139' ? 'Department 139 — PD' : 'All departments';

  function departmentCodes(row = {}) {
    // The server membership is calculated before any operation display limits.
    // An explicitly empty authority remains empty, even if legacy fields differ.
    for (const key of ['department_codes', 'pdcDepartmentCodes']) {
      if (Array.isArray(row[key])) return uniqueCodes(row[key]);
    }
    let lines = null;
    if (Array.isArray(row.operations)) lines = row.operations;
    else if (Array.isArray(row.qc_operation_lines)) lines = row.qc_operation_lines;
    else if (row.pdcQcOperationLinesProjectionPresent === true) lines = Array.isArray(row.pdcQcOperationLines) ? row.pdcQcOperationLines : [];
    else if (Array.isArray(row.pdcQcOperationLines) && row.pdcQcOperationLines.length) lines = row.pdcQcOperationLines;
    else if (Array.isArray(row.operation_lines)) lines = row.operation_lines;
    else if (Array.isArray(row.pdcEmailOperationLines)) lines = row.pdcEmailOperationLines;
    if (lines) return uniqueCodes(lines.filter(line => line && line.active !== false && !line.deleted_at && line.is_deleted !== true).map(line => line.department));
    // Legacy rows may carry an explicit department but never derive it from
    // a workshop station: Tint and other stations are shared by departments.
    return uniqueCodes([row.pdcDepartmentCode, row.departmentCode, row.navisionDepartmentCode, row.department, row.dept]);
  }

  function matches(row, department = '') {
    const selected = normalize(department);
    return !selected || departmentCodes(row).includes(selected);
  }

  let selection = '';
  try { selection = normalize(browser?.localStorage.getItem(STORAGE_KEY)); } catch (_) { /* Keep an in-memory preference when storage is unavailable. */ }
  const getSelection = () => selection;
  function announce() {
    if (browser && typeof browser.CustomEvent === 'function') browser.dispatchEvent(new browser.CustomEvent('pdc-department-filter-changed', { detail: { department: selection } }));
  }
  function setSelection(value) {
    const next = normalize(value);
    if (next === selection) return selection;
    selection = next;
    try { browser?.localStorage.setItem(STORAGE_KEY, selection); } catch (_) { /* The live view still changes. */ }
    announce();
    return selection;
  }
  browser?.addEventListener('storage', event => {
    if (event.key !== STORAGE_KEY && event.key !== null) return;
    const next = normalize(event.newValue);
    if (next !== selection) { selection = next; announce(); }
  });
  const api = Object.freeze({ normalize, departmentCodes, matches, getSelection, setSelection, label });
  if (browser) browser.PDC_DEPARTMENT_FILTER = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})();
