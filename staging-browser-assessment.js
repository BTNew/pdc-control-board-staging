'use strict';

(function stagingBrowserAssessmentModule(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else {
    root.PDC_STAGING_BROWSER_ASSESSMENT = api;
    api.install({
      windowObject: root,
      documentObject: root.document,
      exporter: root.PDC_STAGE2B_C4_EXPORT,
    });
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function factory() {
  function isAdministrator(context) {
    return context?.role === 'administrator';
  }

  function sanitizeComputerName(value) {
    const name = String(value == null ? '' : value).trim().replace(/\s+/g, ' ');
    if (!name) throw new Error('Enter a computer name, for example Computer A.');
    if (name.length > 48) throw new Error('The computer name must be 48 characters or fewer.');
    return name;
  }

  function filenameLabel(value) {
    return sanitizeComputerName(value)
      .normalize('NFKD')
      .replace(/[^A-Za-z0-9._-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48) || 'Computer';
  }

  function install(options) {
    const windowObject = options?.windowObject;
    const documentObject = options?.documentObject;
    const exporter = options?.exporter;
    if (!windowObject || !documentObject) return { installed: false, reason: 'missing_browser' };
    const button = documentObject.getElementById('browser-assessment-export');
    const status = documentObject.getElementById('browser-assessment-export-status');
    if (!button) return { installed: false, reason: 'missing_button' };
    const promptFn = options?.promptFn || (message => windowObject.prompt(message));
    const now = options?.now || (() => new Date());

    function setStatus(message, isError) {
      if (!status) return;
      status.textContent = String(message || '');
      status.hidden = !message;
      if (status.dataset) status.dataset.state = isError ? 'error' : 'ok';
    }

    function refreshVisibility(context) {
      const activeContext = context === undefined ? windowObject.PDC_AUTH_CONTEXT : context;
      const allowed = isAdministrator(activeContext);
      button.hidden = !allowed;
      if (!allowed) {
        button.disabled = false;
        setStatus('', false);
      }
      return allowed;
    }

    button.addEventListener('click', async event => {
      event?.preventDefault?.();
      if (!refreshVisibility(windowObject.PDC_AUTH_CONTEXT)) return;
      if (!exporter || typeof exporter.downloadAssessmentExport !== 'function') {
        setStatus('The read-only exporter is unavailable. No data was changed.', true);
        return;
      }
      let computerName;
      try {
        const supplied = promptFn('Name this computer for the comparison (for example Computer A or Computer B):');
        if (supplied == null) return;
        computerName = sanitizeComputerName(supplied);
      } catch (error) {
        setStatus(error?.message || 'Enter a valid computer name.', true);
        return;
      }
      button.disabled = true;
      setStatus('Preparing the read-only assessment…', false);
      try {
        await exporter.downloadAssessmentExport({
          computerName,
          exportedAt: now().toISOString(),
        });
        setStatus(`${filenameLabel(computerName)} assessment downloaded. Browser storage was unchanged.`, false);
      } catch (error) {
        setStatus(error?.message || 'The assessment could not be created. No data was changed.', true);
      } finally {
        button.disabled = false;
      }
    });

    windowObject.addEventListener('pdc-auth-ready', event => refreshVisibility(event?.detail));
    windowObject.addEventListener('pdc-auth-locked', () => refreshVisibility(null));
    refreshVisibility(windowObject.PDC_AUTH_CONTEXT);
    return { installed: true, refreshVisibility };
  }

  return Object.freeze({ isAdministrator, sanitizeComputerName, filenameLabel, install });
}));
