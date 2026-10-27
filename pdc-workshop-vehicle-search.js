/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r566 (F180): one vehicle search matcher for Workshop Planner Find and Vehicle Locations table search.
 * Key number is exact (364 matches Key 364 only). The other box is stock, job card, customer and vehicle only. */
'use strict';

(function workshopVehicleSearchModule(root) {
  function create(getDeps) {
    const deps = () => (typeof getDeps === 'function' ? getDeps() : getDeps) || {};

    function workshopSearchJobCards(vehicle = {}) {
      const { vehicleJobcardNumber } = deps();
      return [...new Set([vehicleJobcardNumber(vehicle), ...(Array.isArray(vehicle.jobCardNumbers) ? vehicle.jobCardNumbers : []), ...(Array.isArray(vehicle.job_card_numbers) ? vehicle.job_card_numbers : [])]
        .filter(value => typeof value === 'string' && value.trim()).map(value => value.trim()))];
    }

    function workshopSearchKeyToken(value = '') {
      const { cleanNavisionText } = deps();
      const compact = cleanNavisionText(value || '').replace(/\s+/g, '').toLowerCase();
      const stripped = compact.replace(/^0+/, '');
      return stripped || (compact ? '0' : '');
    }

    function workshopVehicleKeyToken(vehicle = {}) {
      const { vehicleKeyNumber } = deps();
      return workshopSearchKeyToken(vehicleKeyNumber(vehicle) || vehicle.key_number || '');
    }

    function workshopSearchCriteria(state = {}) {
      return { key: state?.searchKey || state?.key || '', text: state?.search || state?.text || '' };
    }

    function workshopSearchCriteriaKey(criteria = {}) {
      const { cleanNavisionText } = deps();
      const key = workshopSearchKeyToken(criteria.key || '');
      const text = cleanNavisionText(criteria.text || '').toLowerCase();
      return `${key}\n${text}`;
    }

    function workshopSearchIsActive(criteria = {}) {
      const { cleanNavisionText } = deps();
      return workshopSearchKeyToken(criteria.key || '').length >= 1 || cleanNavisionText(criteria.text || '').length >= 2;
    }

    function workshopVehicleSearchText(vehicle = {}) {
      const { vehicleKey, displayStockNumber, vehicleCustomerName, displayVehicle } = deps();
      return [vehicleKey(vehicle), displayStockNumber(vehicle), vehicle.pdcJobcard, ...workshopSearchJobCards(vehicle), vehicleCustomerName(vehicle), vehicle.vehicle, vehicle.toyotaVehicle, displayVehicle(vehicle)]
        .filter(Boolean).join(' ').toLowerCase();
    }

    function workshopSearchVehicleMatches(vehicle = {}, criteria = {}) {
      const { cleanNavisionText } = deps();
      const text = cleanNavisionText(criteria.text || '').toLowerCase();
      const key = workshopSearchKeyToken(criteria.key || '');
      if (!workshopSearchIsActive({ key, text })) return false;
      if (key && workshopVehicleKeyToken(vehicle) !== key) return false;
      if (text.length >= 2 && !workshopVehicleSearchText(vehicle).includes(text)) return false;
      return true;
    }

    function workshopSearchRank(vehicle = {}, query = '') {
      const { cleanNavisionText, vehicleKey, displayStockNumber, vehicleKeyNumber, vehicleCustomerName } = deps();
      const clean = cleanNavisionText(query || '').toLowerCase();
      const exactFields = [vehicleKey(vehicle), displayStockNumber(vehicle), vehicleKeyNumber(vehicle), ...workshopSearchJobCards(vehicle)]
        .map(value => cleanNavisionText(value || '').toLowerCase());
      if (exactFields.includes(clean)) return 0;
      const customer = cleanNavisionText(vehicleCustomerName(vehicle) || '').toLowerCase();
      if (customer === clean) return 1;
      if (exactFields.some(value => value.startsWith(clean))) return 2;
      if (customer.startsWith(clean)) return 3;
      return 4;
    }

    return {
      workshopSearchJobCards,
      workshopSearchKeyToken,
      workshopVehicleKeyToken,
      workshopSearchCriteria,
      workshopSearchCriteriaKey,
      workshopSearchIsActive,
      workshopSearchVehicleMatches,
      workshopVehicleSearchText,
      workshopSearchRank,
    };
  }

  const factory = { create };
  if (typeof module === 'object' && module.exports) module.exports = factory;
  if (root) root.PDC_WORKSHOP_VEHICLE_SEARCH_FACTORY = factory;
})(typeof globalThis !== 'undefined' ? globalThis : this);
