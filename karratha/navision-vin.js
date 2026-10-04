'use strict';

(function exposeNavisionVin(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.PDC_NAVISION_VIN = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function createNavisionVinApi() {
  const COMPLETE_VIN = /^[A-HJ-NPR-Z0-9]{17}$/;

  function cleanPart(value) {
    return String(value || '').replace(/\s+/g, '');
  }

  function buildNavisionVinParts(wmiValue, vdsValue, frameValue) {
    const wmi = cleanPart(wmiValue);
    const vdsNumber = cleanPart(vdsValue);
    const frame = cleanPart(frameValue);
    const candidate = `${wmi}${vdsNumber}${frame}`.toUpperCase();
    return {
      wmi,
      vdsNumber,
      frame,
      vin: COMPLETE_VIN.test(candidate) ? candidate : '',
    };
  }

  function navisionSourceIdentity(stock, vin, excelRow) {
    return `navision-${String(stock || vin || excelRow || '').trim()}`;
  }

  return Object.freeze({ buildNavisionVinParts, navisionSourceIdentity });
});
