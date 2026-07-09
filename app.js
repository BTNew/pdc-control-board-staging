const APP_VERSION = '2026.07.09.18-density-jita-days';
window.VEHICLE_TRACKING_DATA = window.VEHICLE_TRACKING_DATA || { report: {}, vehicles: [], toyotaMatches: {} };
const EDITS_KEY = 'vehicleTrackingCoreNavisionOnlyEdits:v1';
const ADDED_KEY = 'vehicleTrackingCoreNavisionOnlyVehicles:v1';
const AMY_EMAIL = 'amy.elkington@broometoyota.com.au';
const PMG_UPDATE_EMAIL = 'Newvehiclebuild@pmgwa.com.au';
const TINT_EMAIL = 'jono@performancetinting.com.au';
const RFT_SALESPERSON_EMAIL = 'bryce.guthrie@broometoyota.com.au';
const AUDIT_LOG_KEY = 'vehicleTrackingCoreNavisionOnlyAuditLog:v1';
const OPERATOR_NAME_KEY = 'vehicleTrackingCoreCurrentOperator:v1';
const OPERATOR_ROLE_KEY = 'vehicleTrackingCoreCurrentOperatorRole:v1';
const MECHANICS_KEY = 'vehicleTrackingCorePdcMechanics:v1';
const SUBLET_PROVIDERS_KEY = 'vehicleTrackingCorePdcSubletProviders:v1';
const VEHICLE_TABLE_COLUMN_ORDER_KEY = 'vehicleTrackingCoreColumnOrder:v4';
const VEHICLE_TABLE_DEFAULT_COLUMN_IDS = ['sp', 'stock', 'prodMth', 'client', 'vehicle', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'pitInspection', 'status', 'eta', 'navisionNotes', 'jita', 'action'];
const PO_TASKS_KEY = 'vehicleTrackingCoreNavisionOnlyPoTasks:v1';
const PO_FILES_KEY = 'vehicleTrackingCoreNavisionOnlyPoFiles:v1';
const DELETED_KEY = 'vehicleTrackingCoreNavisionOnlyDeleted:v1';
const TOYOTA_MATCHES = window.VEHICLE_TRACKING_DATA?.toyotaMatches || {};
const AUTOCARE_DESPATCH_STATUS = 'AUTOCARE DESPATCHED';
const AUTOCARE_RESULTS_KEY = 'vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1';
const NAVISION_IMPORT_RESULTS_KEY = 'vehicleTrackingCoreNavisionOnlyImport:v1';
const CRM_BACKUP_TYPE = 'vehicle-tracking-core-backup';
const CRM_BACKUP_VERSION = 1;
const CRM_BACKUP_STORAGE_KEYS = [
  EDITS_KEY,
  ADDED_KEY,
  PO_TASKS_KEY,
  PO_FILES_KEY,
  DELETED_KEY,
  AUTOCARE_RESULTS_KEY,
  NAVISION_IMPORT_RESULTS_KEY,
  AUDIT_LOG_KEY,
  MECHANICS_KEY,
  SUBLET_PROVIDERS_KEY,
  VEHICLE_TABLE_COLUMN_ORDER_KEY
];

const PDC_LOCATION_OPTIONS = [
  { value: '', label: 'Follow Navision until Yard Hold' },
  { value: 'YH', label: 'YH - Yard Hold' },
  { value: 'PMB', label: 'PMB - Perth Motor Bodies' },
  { value: 'RFT', label: 'RFT - Ready for Transport' },
];

const PDC_LOCATION_LABELS = new Map(PDC_LOCATION_OPTIONS.map(option => [option.value, option.label]));

function normalizePdcLocation(value = '') {
  const clean = String(value || '').trim().toUpperCase();
  if (!clean) return '';
  if (clean === 'YH' || clean.includes('YARD HOLD')) return 'YH';
  if (clean === 'PMB' || clean.includes('PERTH MOTOR BODIES')) return 'PMB';
  if (clean === 'RFT' || clean.includes('READY FOR TRANSPORT') || clean.includes('READY FOR TRANSFER')) return 'RFT';
  return '';
}

function pdcLocationLabel(value = '') {
  const normalized = normalizePdcLocation(value);
  return PDC_LOCATION_LABELS.get(normalized) || normalized || '';
}

function pdcLocationSelectOptions(current = '') {
  const normalizedCurrent = normalizePdcLocation(current);
  return PDC_LOCATION_OPTIONS.map(option => {
    const selected = option.value === normalizedCurrent ? ' selected' : '';
    return `<option value="${escapeHtml(option.value)}"${selected}>${escapeHtml(option.label)}</option>`;
  }).join('');
}

const PMB_STAGE_OPTIONS = [
  { value: '', label: 'UNALLOCATED' },
  { value: 'TINT', label: 'TINT' },
  { value: 'HOIST', label: 'HOIST' },
  { value: 'FITTING', label: 'FITTING' },
  { value: 'FABRICATION', label: 'FAB' },
  { value: 'ELECTRICAL', label: 'ELEC' },
  { value: 'TYRE', label: 'TYRE' },
  { value: 'PIT_INSPECTION', label: 'PIT' },
];

const PMB_STAGE_DEFS = PMB_STAGE_OPTIONS.filter(option => option.value);
const PMB_STAGE_UNASSIGNED_FILTER = '__UNASSIGNED__';
const PMB_STAGE_LABELS = new Map(PMB_STAGE_OPTIONS.map(option => [option.value, option.label]));

const PMB_WIP_LIMITS = {
  '': 12,
  TINT: 2,
  HOIST: 3,
  FITTING: 5,
  FABRICATION: 13,
  ELECTRICAL: 10,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

const PMB_STAGE_BAY_COUNTS = {
  TINT: 2,
  HOIST: 3,
  FITTING: 5,
  FABRICATION: 13,
  ELECTRICAL: 10,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

const PMB_STAGE_CAPACITY_LABELS = {
  FABRICATION: '13 bays',
  TYRE: '2 bays · 1 wheel alignment bay',
};

const PMB_STAGE_AGE_LIMITS = {
  '': 1,
  TINT: 2,
  HOIST: 2,
  FITTING: 3,
  FABRICATION: 4,
  ELECTRICAL: 2,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

const PMB_BAY_MAX_COUNT = 13;
const PMB_BAY_STATION_SEQUENCE = ['TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];
const PRODUCTION_FLOW_DEFS = [
  { key: 'TINT', label: 'TINT', short: 'T', jobKey: 'tint', stage: 'TINT', search: /\b(tint|tinting|window tint)\b/i },
  { key: 'HOIST', label: 'HOIST', short: 'H', jobKey: 'hoist', stage: 'HOIST', search: /\b(hoist|suspension|gvm|lift kit|lift|underbody|towbar|tow bar)\b/i },
  { key: 'FITTING', label: 'FITTING', short: 'F', jobKey: 'fitting', stage: 'FITTING', search: /\b(fit|fitting|build|pdi|pre delivery|pre-delivery|accessor(?:y|ies)|job card|workshop)\b/i },
  { key: 'FABRICATION', label: 'FAB', short: 'Fa', jobKey: 'fabrication', stage: 'FABRICATION', search: /\b(fab|fabricat|tray|canopy|body builder|bodybuilder|steel tray|aluminium tray|tub body|bullbar|bar work)\b/i },
  { key: 'ELECTRICAL', label: 'ELEC', short: 'E', jobKey: 'electrical', stage: 'ELECTRICAL', search: /\b(electrical|auto electrical|auto-elec|12v|dual battery|battery system|uhf|spotlight|light bar|beacon|compressor|anderson|redarc|brake controller|dc dc|dcdc|dash cam|camera|reverse camera|power outlet|usb)\b/i },
  { key: 'TYRE', label: 'TYRE', short: 'Ty', jobKey: 'tyre', stage: 'TYRE', search: /\b(tyre|tire|wheel|wheels|alloy|rotation|balance|alignment)\b/i },
  { key: 'PIT_INSPECTION', label: 'PIT', short: 'PI', jobKey: 'pitInspection', stage: 'PIT_INSPECTION', search: /\b(pit inspection|pit|inspection)\b/i },
];
const PRODUCTION_DEPARTMENT_VIEWS = {
  'dept-tint': 'TINT',
  'dept-hoist': 'HOIST',
  'dept-fitting': 'FITTING',
  'dept-fabrication': 'FABRICATION',
  'dept-electrical': 'ELECTRICAL',
  'dept-tyre': 'TYRE',
  'dept-pit-inspection': 'PIT_INSPECTION',
};

const PDC_JOB_DEFS = [
  { key: 'tint', label: 'TINT', short: 'T', requireKey: 'pdcRequiresTint', completeKey: 'pdcCompleteTint', completeAtKey: 'pdcCompleteTintAt', completeByKey: 'pdcCompleteTintBy' },
  { key: 'hoist', label: 'HOIST', short: 'H', requireKey: 'pdcRequiresHoist', completeKey: 'pdcCompleteHoist', completeAtKey: 'pdcCompleteHoistAt', completeByKey: 'pdcCompleteHoistBy' },
  { key: 'fitting', label: 'FITTING', short: 'F', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting', completeAtKey: 'pdcCompleteFittingAt', completeByKey: 'pdcCompleteFittingBy' },
  { key: 'fabrication', label: 'FAB', short: 'Fa', requireKey: 'pdcRequiresFabrication', completeKey: 'pdcCompleteFabrication', completeAtKey: 'pdcCompleteFabricationAt', completeByKey: 'pdcCompleteFabricationBy' },
  { key: 'electrical', label: 'ELEC', short: 'E', requireKey: 'pdcRequiresElectrical', completeKey: 'pdcCompleteElectrical', completeAtKey: 'pdcCompleteElectricalAt', completeByKey: 'pdcCompleteElectricalBy' },
  { key: 'tyre', label: 'TYRE', short: 'Ty', requireKey: 'pdcRequiresTyre', completeKey: 'pdcCompleteTyre', completeAtKey: 'pdcCompleteTyreAt', completeByKey: 'pdcCompleteTyreBy' },
  { key: 'pitInspection', label: 'PIT', short: 'PI', requireKey: 'pdcRequiresPitInspection', completeKey: 'pdcCompletePitInspection', completeAtKey: 'pdcCompletePitInspectionAt', completeByKey: 'pdcCompletePitInspectionBy' },
  { key: 'parts', label: 'PARTS', short: 'P', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts', completeAtKey: 'pdcCompletePartsAt', completeByKey: 'pdcCompletePartsBy' },
];
function currentPdcJobLabelList() {
  return PDC_JOB_DEFS.map(def => def.label).join(', ');
}

function currentPdcJobColumnList() {
  return PDC_JOB_DEFS.map(def => def.label).join('/');
}

const PDC_JOB_BY_REQUIRE_KEY = new Map(PDC_JOB_DEFS.map(def => [def.requireKey, def]));
const PDC_JOB_BY_COMPLETE_KEY = new Map(PDC_JOB_DEFS.map(def => [def.completeKey, def]));
const PDC_JOB_BY_KEY = new Map(PDC_JOB_DEFS.map(def => [def.key, def]));
const PDC_IMPORT_CONTROL_COLUMNS_TEXT = 'TINT, HOIST, FITTING, FABRICATION, ELECTRICAL, TYRE, PIT INSPECTION, PARTS';

function currentPdcJobLabelsText() {
  return PDC_JOB_DEFS.map(def => def.label).join(', ');
}

const PMB_STAGE_TO_JOB_KEY = {
  TINT: 'tint',
  HOIST: 'hoist',
  FITTING: 'fitting',
  FABRICATION: 'fabrication',
  ELECTRICAL: 'electrical',
  TYRE: 'tyre',
  PIT_INSPECTION: 'pitInspection',
};

function pmbStageJobDef(stage = '') {
  const key = PMB_STAGE_TO_JOB_KEY[normalizePmbStage(stage)];
  return key ? PDC_JOB_BY_KEY.get(key) : null;
}


function pdcJobFieldSuffix(def = {}) {
  const clean = String(def.key || '').trim();
  return clean ? clean.charAt(0).toUpperCase() + clean.slice(1) : '';
}

function pdcJobMechanicKey(def = {}) { return `pdcComplete${pdcJobFieldSuffix(def)}Mechanic`; }
function pdcJobBayKey(def = {}) { return `pdcComplete${pdcJobFieldSuffix(def)}Bay`; }
function pdcJobHoursKey(def = {}) { return `pdcComplete${pdcJobFieldSuffix(def)}Hours`; }

function pdcJobMechanic(vehicle = {}, def = {}) {
  return cleanNavisionText(vehicle[pdcJobMechanicKey(def)] || '');
}

function pdcJobBay(vehicle = {}, def = {}) {
  return cleanNavisionText(vehicle[pdcJobBayKey(def)] || '');
}

function pdcJobHours(vehicle = {}, def = {}) {
  return cleanNavisionText(vehicle[pdcJobHoursKey(def)] || '');
}


function normalizePmbStage(value = '') {
  const clean = String(value || '').trim().toUpperCase();
  if (!clean) return '';
  if (clean.includes('TINT')) return 'TINT';
  if ((clean.includes('EXPRESS') && clean.includes('HOIST')) || clean.includes('PITS HOIST') || clean.includes('PIT HOIST')) return 'HOIST';
  if (clean.includes('EXPRESS') && (clean.includes('FITOUT') || clean.includes('FIT OUT') || clean.includes('FITTING') || clean.includes('FITMENT'))) return 'FITTING';
  if (clean.includes('HOIST') || clean.includes('SUSPENSION') || clean.includes('LIFT')) return 'HOIST';
  if (clean.includes('FITTING') || clean.includes('FITMENT') || clean.includes('FITOUT') || clean.includes('FIT OUT') || clean.includes('BUILD') || clean.includes('PDI') || clean.includes('PRE DELIVERY') || clean.includes('PRE-DELIVERY')) return 'FITTING';
  if (clean.includes('FAB') || clean.includes('TRAY') || clean.includes('BODY')) return 'FABRICATION';
  if (clean.includes('ELECTRICAL') || clean.includes('AUTO ELEC') || clean.includes('AUTO-ELEC') || clean.includes('12V') || clean.includes('UHF')) return 'ELECTRICAL';
  if (clean.includes('TYRE') || clean.includes('TIRE') || clean.includes('WHEEL')) return 'TYRE';
  if (clean.includes('PIT') || clean.includes('INSPECTION')) return 'PIT_INSPECTION';
  if (clean.includes('SUBLET') || clean.includes('SUB-LET') || clean.includes('SUB LET') || clean.includes('OUTSOURCE') || clean.includes('EXTERNAL')) return '';
  return '';
}

function pmbStageLabel(value = '') {
  const normalized = normalizePmbStage(value);
  return PMB_STAGE_LABELS.get(normalized) || normalized || '';
}

function normalizePmbSubFilter(value = '') {
  if (String(value || '') === PMB_STAGE_UNASSIGNED_FILTER) return PMB_STAGE_UNASSIGNED_FILTER;
  return normalizePmbStage(value);
}

function pmbSubFilterLabel(value = '') {
  if (value === PMB_STAGE_UNASSIGNED_FILTER) return 'Unallocated';
  return pmbStageLabel(value);
}

function pmbStageSelectOptions(current = '') {
  const normalizedCurrent = normalizePmbStage(current);
  return PMB_STAGE_OPTIONS.map(option => {
    const selected = option.value === normalizedCurrent ? ' selected' : '';
    return `<option value="${escapeHtml(option.value)}"${selected}>${escapeHtml(option.label)}</option>`;
  }).join('');
}

function pmbStageSourceText(vehicle = {}) {
  return [
    vehicle.pmbStage,
    vehicle.pdcWorkStage,
    vehicle.workStage,
    vehicle.internalStatus,
    vehicle.navisionDealerComments,
    vehicle.navisionVehicleNote,
    vehicle.financeNote,
    ...(vehicle.poTasks || []),
    ...(vehicle.poFiles || []),
    ...getNotes(vehicleKey(vehicle)),
  ].join(' ').toLowerCase();
}

function inferredPmbStage(vehicle = {}) {
  // Only a manually assigned PMB work stream should place a vehicle into
  // Required work ticks do not allocate vehicles into Tint / Hoist / Fitting / Fabrication / Electrical / Tyre / Pit Inspection.
  // Required work ticks do not allocate the vehicle into a production bucket.
  return normalizePmbStage(vehicle.pmbStage || '');
}

function pmbStageBadge(vehicle = {}) {
  const stage = inferredPmbStage(vehicle);
  return stage ? `<span class="badge pmb-stage-badge pmb-stage-${escapeHtml(stage.toLowerCase())}">${escapeHtml(pmbStageLabel(stage))}</span>` : '';
}

function nowIsoString() {
  return new Date().toISOString();
}

function parseIsoTimestamp(value = '') {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function pmbEnteredTimestamp(vehicle = {}) {
  return vehicle.pmbEnteredAt || vehicle.pmbTransferredAt || vehicle.pdcLocationUpdatedAt || vehicle.pmbStageUpdatedAt || '';
}

function daysSinceTimestamp(value = '') {
  const parsed = parseIsoTimestamp(value);
  if (!parsed) return null;
  const start = new Date(parsed);
  start.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.max(0, Math.floor((today - start) / (1000 * 60 * 60 * 24)));
}

function daysSinceDateValue(value = '') {
  const parsed = parseDateAU(value);
  if (!parsed) return null;
  const start = new Date(parsed);
  start.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.floor((today - start) / (1000 * 60 * 60 * 24));
}

function kewdaleEtaValue(vehicle = {}) {
  return scotEtaOnly(vehicle.navisionKewdaleEta || vehicle.etaAtKewdale || vehicle.etaAtDealer || '');
}

function onSiteDays(vehicle = {}) {
  return daysSinceDateValue(kewdaleEtaValue(vehicle));
}

function onSiteDaysLabel(vehicle = {}) {
  const days = onSiteDays(vehicle);
  if (days === null) return 'Days on site unknown';
  if (days < 0) return `Due in ${Math.abs(days)}d`;
  if (days === 0) return 'On site today';
  return `${days}d on site`;
}

function onSiteDaysClass(vehicle = {}) {
  const days = onSiteDays(vehicle);
  if (days === null) return 'unknown';
  if (days < 0) return 'future';
  if (days > 21) return 'critical';
  if (days > 10) return 'warning';
  return 'fresh';
}

function locationAgeLabel(vehicle = {}) {
  const status = statusCategory(vehicle);
  if (status === 'pmb') return onSiteDaysLabel(vehicle).replace('on site', 'at PMB');
  if (status === 'yardhold') return onSiteDaysLabel(vehicle).replace('on site', 'at YH');
  return navisionEtaForVehicle(vehicle) || 'No ETA';
}

function pmbEnteredDateValue(vehicle = {}) {
  const timestamp = pmbEnteredTimestamp(vehicle);
  if (!timestamp) return '';
  const parsed = parseIsoTimestamp(timestamp);
  if (!parsed) return scotEtaOnly(timestamp);
  return parsed.toISOString().slice(0, 10);
}

function pmbAgeDays(vehicle = {}) {
  return daysSinceTimestamp(pmbEnteredTimestamp(vehicle));
}

function pmbAgeLabel(vehicle = {}) {
  const days = pmbAgeDays(vehicle);
  if (days === null) return 'PMB entry unknown';
  if (days === 0) return 'PMB today';
  return `PMB +${days}d`;
}

function partsEtaCounterLabel(vehicle = {}) {
  if (pmbAgeDays(vehicle) !== null) return pmbAgeLabel(vehicle);
  const eta = kewdaleEtaValue(vehicle);
  return dateHelper(eta) || 'No ETA counter';
}

function partsEtaCounterClass(vehicle = {}) {
  if (pmbAgeDays(vehicle) !== null) return pmbAgeClass(vehicle);
  const eta = etaDeltaText(kewdaleEtaValue(vehicle));
  if (eta.cls === 'negative') return 'overdue';
  if (eta.cls === 'positive') return 'future';
  if (eta.cls === 'neutral' && eta.label) return 'fresh';
  return 'unknown';
}

function pmbAgeDetailText(vehicle = {}) {
  const days = pmbAgeDays(vehicle);
  if (days === null) return 'PMB entry date unknown';
  if (days === 0) return 'Transferred to PMB today';
  return `${days} day${days === 1 ? '' : 's'} at PMB`;
}

function pmbAgeClass(vehicle = {}) {
  const days = pmbAgeDays(vehicle);
  if (days === null) return 'unknown';
  if (days > 150) return 'critical';
  if (days > 90) return 'warning';
  if (days < 0) return 'future';
  return 'fresh';
}

function pmbStageEnteredTimestamp(vehicle = {}) {
  return vehicle.pmbStageEnteredAt || vehicle.pmbStageUpdatedAt || pmbEnteredTimestamp(vehicle);
}

function pmbStageAgeDays(vehicle = {}) {
  return daysSinceTimestamp(pmbStageEnteredTimestamp(vehicle));
}

function pmbStageAgeLabel(vehicle = {}) {
  const days = pmbStageAgeDays(vehicle);
  const stage = pmbStageLabel(inferredPmbStage(vehicle)) || 'Unallocated';
  if (days === null) return `${stage} age unknown`;
  return `${stage} ${days} day${days === 1 ? '' : 's'}`;
}

function pmbStageAgeClass(vehicle = {}) {
  const days = pmbStageAgeDays(vehicle);
  if (days === null) return 'unknown';
  const stage = inferredPmbStage(vehicle);
  const limit = PMB_STAGE_AGE_LIMITS[stage] ?? 3;
  if (days > limit) return 'overdue';
  if (days >= Math.max(1, limit - 1)) return 'watch';
  return 'fresh';
}

function pmbLaneLimit(stage = '') {
  const normalized = normalizePmbStage(stage);
  return PMB_WIP_LIMITS[normalized] ?? PMB_WIP_LIMITS[''];
}

function pmbStageBayCount(stage = '') {
  const normalized = normalizePmbStage(stage);
  return PMB_STAGE_BAY_COUNTS[normalized] ?? PMB_BAY_MAX_COUNT;
}

function pmbStageCapacityLabel(stage = '') {
  const normalized = normalizePmbStage(stage);
  const explicit = PMB_STAGE_CAPACITY_LABELS[normalized];
  if (explicit) return explicit;
  const count = pmbStageBayCount(normalized);
  if (!count) return 'Refer Dan';
  return `${count} bay${count === 1 ? '' : 's'}`;
}

function pmbBayVehiclesForStage(stage = '') {
  const normalized = normalizePmbStage(stage);
  if (!normalized) return [];
  return app.data.filter(vehicle => statusCategory(vehicle) === 'pmb'
    && normalizePmbStage(inferredPmbStage(vehicle)) === normalized
    && pmbBayNumber(vehicle, normalized));
}

function pmbBayOccupants(stage = '', bay = '', excludeKey = '') {
  const normalized = normalizePmbStage(stage);
  const bayNumber = normalizePmbBayNumber(bay, normalized);
  const cleanExclude = String(excludeKey || '').trim();
  if (!normalized || !bayNumber) return [];
  return app.data.filter(vehicle => {
    if (cleanExclude && vehicleKey(vehicle) === cleanExclude) return false;
    if (statusCategory(vehicle) !== 'pmb') return false;
    if (normalizePmbStage(inferredPmbStage(vehicle)) !== normalized) return false;
    return pmbBayNumber(vehicle, normalized) === bayNumber;
  });
}

function pmbStageHasBayCapacity(stage = '', excludeKey = '') {
  const normalized = normalizePmbStage(stage);
  const bayCount = pmbStageBayCount(normalized);
  if (!normalized || !bayCount) return true;
  const cleanExclude = String(excludeKey || '').trim();
  const occupied = pmbBayVehiclesForStage(normalized).filter(vehicle => vehicleKey(vehicle) !== cleanExclude).length;
  return occupied < bayCount;
}

function pmbLaneAgeLimit(stage = '') {
  const normalized = normalizePmbStage(stage);
  return PMB_STAGE_AGE_LIMITS[normalized] ?? PMB_STAGE_AGE_LIMITS[''];
}

function pmbLaneMetrics(stage = '', vehicles = []) {
  const limit = pmbLaneLimit(stage);
  const oldestStageDays = vehicles.reduce((max, vehicle) => {
    const days = pmbStageAgeDays(vehicle);
    return days === null ? max : Math.max(max, days);
  }, 0);
  const blockedCount = vehicles.filter(isPdcBlocked).length;
  return {
    limit,
    limitLabel: Number.isFinite(limit) ? String(limit) : 'Refer Dan',
    overLimit: Number.isFinite(limit) && vehicles.length > limit,
    atLimit: Number.isFinite(limit) && vehicles.length === limit,
    blockedCount,
    oldestStageDays,
  };
}

function isPdcBlocked(vehicle = {}) {
  return vehicle.pdcBlocked === true || Boolean(cleanNavisionText(vehicle.pdcBlockReason || ''));
}

function pdcBlockReason(vehicle = {}) {
  return cleanNavisionText(vehicle.pdcBlockReason || '') || 'Blocked';
}

function pdcBooleanFromText(value) {
  const clean = cleanNavisionText(value).toLowerCase();
  if (!clean) return undefined;
  if (/^(yes|y|true|1|tick|ticked|x|required|req|done|complete|completed|signed off)$/i.test(clean)) return true;
  if (/^(no|n|false|0|not required|none|blank|na|n\/a|not needed|open)$/i.test(clean)) return false;
  return undefined;
}

function vehicleRftGateIssues(vehicle = {}) {
  const issues = [];
  if (isPdcBlocked(vehicle)) issues.push(`Blocked: ${pdcBlockReason(vehicle)}`);
  if (vehicle.pdcPartsStoppage === true || cleanNavisionText(vehicle.pdcPartsStoppageReason || '')) {
    issues.push(`Parts stoppage: ${partsStoppageReason(vehicle)}`);
  }
  const outstanding = pdcRequirementDefinitions(vehicle).filter(job => !pdcJobComplete(vehicle, job)).map(job => job.label);
  if (outstanding.length) issues.push(`Outstanding jobs: ${outstanding.join(', ')}`);
  if (!inferredPmbStage(vehicle)) issues.push('No PMB bucket assigned');
  return issues;
}

function vehiclesWithRftGateIssues(vehicles = []) {
  return vehicles.map(vehicle => ({ vehicle, issues: vehicleRftGateIssues(vehicle) })).filter(row => row.issues.length);
}


function pdcJobDefinitionForKey(key = '') {
  const clean = String(key || '').trim();
  return PDC_JOB_BY_REQUIRE_KEY.get(clean) || PDC_JOB_BY_COMPLETE_KEY.get(clean) || PDC_JOB_BY_KEY.get(clean.toLowerCase()) || null;
}

function pdcJobSourceText(vehicle = {}) {
  return pmbStageSourceText(vehicle);
}

function pdcJobFallbackRequired(vehicle = {}, def = {}) {
  const source = pdcJobSourceText(vehicle);
  const stage = normalizePmbStage(vehicle.pmbStage || vehicle.pdcWorkStage || vehicle.workStage || '');
  switch (def.key) {
    case 'tint':
      return legacyVehicleFlag(vehicle, 'tintRaised') || /\b(tint|tinting|window tint)\b/.test(source) || stage === 'TINT';
    case 'hoist':
      return legacyVehicleFlag(vehicle, 'buildPoRaised') || /\b(hoist|suspension|gvm|lift kit|lift|underbody|towbar|tow bar)\b/.test(source) || stage === 'HOIST';
    case 'fitting':
      return legacyVehicleFlag(vehicle, 'buildPoRaised') || legacyVehicleFlag(vehicle, 'buildComplete') || /\b(fit|fitting|fitment|fitout|fit out|build|pdi|pre delivery|pre-delivery|job card|workshop|accessor(?:y|ies))\b/.test(source) || stage === 'FITTING';
    case 'electrical':
      return /\b(electrical|auto electrical|auto-elec|12v|dual battery|battery system|uhf|spotlight|light bar|beacon|compressor|anderson|redarc|brake controller|dc dc|dcdc|dash cam|camera|reverse camera|power outlet|usb)\b/.test(source) || stage === 'ELECTRICAL';
    case 'tyre':
      return /\b(tyre|tire|wheel|wheels|alloy|rotation|balance|alignment)\b/.test(source) || stage === 'TYRE';
    case 'sublet':
      return /\b(sublet|sub-let|sub let|outsourced|external contractor|external work|outside contractor)\b/.test(source) || stage === 'SUBLET';
    case 'fabrication':
      return legacyVehicleFlag(vehicle, 'trayOrdered') || legacyVehicleFlag(vehicle, 'trayFitmentComplete') || /\b(fab|fabricat|tray|canopy|body builder|bodybuilder|steel tray|aluminium tray|tub body|bullbar|bar work)\b/.test(source) || stage === 'FABRICATION';
    case 'pitInspection':
      return /\b(pit inspection|pit|inspection|qc|quality control|final check)\b/.test(source) || stage === 'PIT_INSPECTION';
    default:
      return false;
  }
}

function pdcJobRequired(vehicle = {}, def = {}) {
  if (!def?.requireKey) return false;
  // Parts is not an optional work bucket in this PDC flow.
  // Every imported vehicle with a real batch / stock number requires Parts to order and sign off before RFT.
  if (def.key === 'parts') return vehicleHasBatchNumber(vehicle);
  if (def.key === 'fitting' && vehicle.pdcRequiresBuild === true) return true;
  if (vehicle[def.requireKey] === true) return true;
  if (vehicle[def.requireKey] === false) return false;
  return pdcJobFallbackRequired(vehicle, def);
}

function pdcJobComplete(vehicle = {}, def = {}) {
  if (!def?.completeKey) return false;
  if (vehicle[def.completeKey] === true) return true;
  if (vehicle[def.completeKey] === false) return false;
  return false;
}

function pdcRequiredJobs(vehicle = {}) {
  return PDC_JOB_DEFS.filter(def => pdcJobRequired(vehicle, def));
}

function pdcCompletedJobs(vehicle = {}) {
  return PDC_JOB_DEFS.filter(def => pdcJobRequired(vehicle, def) && pdcJobComplete(vehicle, def));
}

function pdcRequirementDefinitions(vehicle = {}) {
  return pdcRequiredJobs(vehicle).map(def => ({ ...def, required: true, complete: pdcJobComplete(vehicle, def) }));
}

function pmbRequirementDefinitions(vehicle = {}) {
  return pdcRequirementDefinitions(vehicle);
}

function pdcJobCompletionTitle(vehicle = {}, def = {}) {
  const complete = pdcJobComplete(vehicle, def);
  const bits = [`${def.label} required`];
  if (complete) {
    bits.push('signed off');
    if (vehicle[def.completeByKey]) bits.push(`by ${vehicle[def.completeByKey]}`);
    const doneAt = parseIsoTimestamp(vehicle[def.completeAtKey]);
    if (doneAt) bits.push(doneAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }));
  } else {
    bits.push('not signed off yet');
  }
  return bits.join(' - ');
}

function pdcJobMarkerTitle(vehicle = {}, def = {}) {
  const required = pdcJobRequired(vehicle, def);
  const complete = pdcJobComplete(vehicle, def);
  if (!required && !complete) return `${def.label} not required`;
  return pdcJobCompletionTitle(vehicle, def);
}

function pdcJobMarkersHtml(vehicle = {}, interactive = false) {
  return `<div class="pmb-card-requirements" aria-label="PMB requirements">${PDC_JOB_DEFS.map(def => {
    const required = pdcJobRequired(vehicle, def);
    const complete = pdcJobComplete(vehicle, def);
    const stateClass = complete ? 'is-complete' : required ? 'is-pending' : 'is-not-required';
    const attrs = interactive ? ` role="button" tabindex="0" data-toggle-pdc-job-complete="${escapeHtml(def.key)}" data-job-stock="${escapeHtml(vehicleKey(vehicle))}"` : '';
    const markerText = complete ? `${def.short}✓` : def.short;
    return `<span class="pmb-req-marker pmb-req-${escapeHtml(def.key)} ${stateClass}" title="${escapeHtml(pdcJobMarkerTitle(vehicle, def))}"${attrs}>${escapeHtml(markerText)}</span>`;
  }).join('')}</div>`;
}

function pmbRequirementMarkersHtml(vehicle = {}) {
  return pdcJobMarkersHtml(vehicle, true);
}

function pmbOutstandingStationChipsHtml(vehicle = {}) {
  const outstanding = pdcRequirementDefinitions(vehicle).filter(job => !pdcJobComplete(vehicle, job));
  const chips = outstanding.length
    ? outstanding.map(job => `<span class="pmb-outstanding-station" title="${escapeHtml(`${job.label} outstanding`)}">${escapeHtml(job.short || job.label)}</span>`)
    : ['<span class="pmb-outstanding-station is-clear">All clear</span>'];
  return `<div class="pmb-outstanding-stations" aria-label="Outstanding PMB stations">${chips.join('')}</div>`;
}

function pmbBayPillIdentityHtml(vehicle = {}) {
  const stock = displayStockNumber(vehicle) || String(vehicle.order || '').trim() || '—';
  const cells = [
    { label: 'Key', value: vehicleKeyNumber(vehicle) || '—' },
    { label: 'Stock', value: stock },
    { label: 'JC', value: vehicleJobcardNumber(vehicle) || '—' },
  ].map(cell => `<span class="pmb-bay-id-cell pmb-bay-id-${escapeHtml(cell.label.toLowerCase())}" aria-label="${escapeHtml(`${cell.label} ${cell.value}`)}" title="${escapeHtml(cell.value)}">${escapeHtml(truncate(cell.value, 14))}</span>`).join('');
  return `<div class="pmb-bay-pill-ids">${cells}</div>`;
}

function pmbRequirementText(vehicle = {}) {
  const required = pdcRequirementDefinitions(vehicle).map(item => `${item.label}${pdcJobComplete(vehicle, item) ? ' done' : ' required'}`);
  return required.length ? required.join(', ') : 'No PDC requirements set';
}

function pdcCompletedJobsText(vehicle = {}) {
  const done = pdcCompletedJobs(vehicle).map(item => item.label);
  return done.length ? done.join(', ') : 'No PMB jobs signed off yet';
}

function pdcOutstandingJobsText(vehicle = {}) {
  const outstanding = pdcRequirementDefinitions(vehicle).filter(item => !pdcJobComplete(vehicle, item)).map(item => item.label);
  return outstanding.length ? outstanding.join(', ') : 'No outstanding PMB jobs';
}


const TOYOTA_STATUS_ORDER = [
  'Delivered - At Dealer',
  'Planned For Despatch - From TWA',
  'Despatched - From Body Builder',
  'Vehicle Out on Consignment',
  'Delivered - At Body Builder',
  'Waiting PD2',
  'Waiting PD1',
  'Vehicle Yard Hold',
  'Vehicle Delayed',
  'Vehicle Waiting For Wholesale',
  'Vehicle At Wharf',
  'In Transit to WA',
  'Ready For Shipment',
  'Planned for Production'
];

function normalizeToyotaStatus(status = '') {
  return String(status || '')
    .toLowerCase()
    .replace(/[\u2010-\u2015]/g, '-')
    .replace(/\s+/g, ' ')
    .replace(/\s*-\s*/g, ' - ')
    .trim();
}

const TOYOTA_STATUS_RANKS = new Map(
  TOYOTA_STATUS_ORDER.map((status, index) => [normalizeToyotaStatus(status), index])
);

function canonicalToyotaStatus(status = '') {
  const normalized = normalizeToyotaStatus(status);
  if (!normalized || normalized === 'not matched') return '';
  if (normalized === normalizeToyotaStatus(AUTOCARE_DESPATCH_STATUS) || (normalized.includes('autocare') && (normalized.includes('despatch') || normalized.includes('dispatch')))) return AUTOCARE_DESPATCH_STATUS;
  const exact = TOYOTA_STATUS_ORDER.find(item => normalizeToyotaStatus(item) === normalized);
  if (exact) return exact;

  const checks = [
    ['Delivered - At Dealer', s => s.includes('delivered') && s.includes('dealer')],
    ['Planned For Despatch - From TWA', s => s.includes('from twa') && (s.includes('planned for despatch') || s.includes('for despatch') || s.includes('despatched') || s.includes('for transport'))],
    ['Despatched - From Body Builder', s => (s.includes('despatched') || s.includes('for despatch')) && s.includes('body builder')],
    ['Vehicle Out on Consignment', s => s.includes('out on consignment')],
    ['Delivered - At Body Builder', s => s.includes('delivered') && s.includes('body builder')],
    ['Waiting PD2', s => s.includes('waiting pd2')],
    ['Waiting PD1', s => s.includes('waiting pd1')],
    ['Vehicle Yard Hold', s => s.includes('vehicle yard hold') || s.includes('vehicle in yard hold') || s.includes('yard hold')],
    ['Vehicle Delayed', s => s.includes('delayed')],
    ['Vehicle Waiting For Wholesale', s => s.includes('waiting for wholesale')],
    ['Vehicle At Wharf', s => s.includes('at wharf') || s.includes('o/s wharf')],
    ['In Transit to WA', s => s.includes('in transit to wa')],
    ['Ready For Shipment', s => s.includes('ready for shipment')],
    ['Planned for Production', s => s.includes('planned for production') || s === 'for production' || s.endsWith(' for production')],
  ];
  const found = checks.find(([, test]) => test(normalized));
  return found ? found[0] : String(status || '').trim();
}

function toyotaStatusRank(status = '') {
  const canonical = canonicalToyotaStatus(status);
  const normalized = normalizeToyotaStatus(canonical || status);
  if (TOYOTA_STATUS_RANKS.has(normalized)) return TOYOTA_STATUS_RANKS.get(normalized);
  if (normalized === normalizeToyotaStatus(AUTOCARE_DESPATCH_STATUS)) return 1.5;
  return TOYOTA_STATUS_ORDER.length + 100;
}

function sortToyotaStatuses(statuses) {
  const collator = new Intl.Collator('en-AU', { numeric: true, sensitivity: 'base' });
  return statuses.slice().sort((a, b) => {
    const rankDiff = toyotaStatusRank(a) - toyotaStatusRank(b);
    return rankDiff || collator.compare(String(a), String(b));
  });
}

function isAutocareDespatched(vehicleOrStatus) {
  if (vehicleOrStatus && typeof vehicleOrStatus === 'object' && vehicleOrStatus.autocareDespatched) return true;
  const status = typeof vehicleOrStatus === 'string' ? vehicleOrStatus : vehicleOrStatus?.toyotaStatus;
  return canonicalToyotaStatus(status || '') === AUTOCARE_DESPATCH_STATUS;
}

const TASK_OPTIONS = [
  'Allocate vehicle, generate orders',
  'Customer update required',
  'Confirm customer contact details',
  'Order accessories / JITA parts',
  'Confirm JITA parts ordered',
  'Book workshop job card',
  'Book tint / accessories',
  'Book tray / body builder',
  'Released from Perth - book workshop',
  'Vehicle arrived - prepare delivery',
  'Delivery booked',
  'No task required'
];

function loadJson(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key) || JSON.stringify(fallback)); }
  catch { return fallback; }
}

function saveJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

function clearLocalDataFromUrl() {
  const search = String(window.location?.search || '');
  const ParamsCtor = window.URLSearchParams || (typeof URLSearchParams !== 'undefined' ? URLSearchParams : null);
  const resetRequested = ParamsCtor
    ? new ParamsCtor(search).has('clearLocalData') || new ParamsCtor(search).has('resetLocalData') || new ParamsCtor(search).has('freshData')
    : /[?&](clearLocalData|resetLocalData|freshData)(=|&|$)/.test(search);
  if (!resetRequested) return;
  try {
    CRM_BACKUP_STORAGE_KEYS.forEach(key => localStorage.removeItem(key));
    localStorage.removeItem('vehicleTrackingCoreColumnOrder:v1');
    localStorage.removeItem('vehicleTrackingCoreColumnOrder:v2');
    localStorage.removeItem('vehicleTrackingCoreColumnOrder:v3');
    localStorage.removeItem('vehicleTrackingCoreColumnOrder:v4');
    localStorage.removeItem('vehicleTrackingCoreColumnWidths:v1:vehicle-table');
    localStorage.removeItem('vehicleTrackingCoreColumnWidths:v3:vehicle-table');
    localStorage.removeItem('vehicleTrackingCoreColumnWidths:v4:vehicle-table');
    window.PDC_LOCAL_DATA_CLEARED = true;
  } catch (error) {
    console.warn('Unable to clear local PDC data', error);
  }
}

clearLocalDataFromUrl();

function loadVehicleEdits() { return loadJson(EDITS_KEY, {}); }
function loadAddedVehicles() { return loadJson(ADDED_KEY, []); }
function saveAddedVehicles(vehicles) { saveJson(ADDED_KEY, vehicles); }
function loadPoTasks() { return loadJson(PO_TASKS_KEY, {}); }
function savePoTasks(tasks) { saveJson(PO_TASKS_KEY, tasks); }
function loadPoFiles() { return loadJson(PO_FILES_KEY, {}); }
function savePoFiles(files) { saveJson(PO_FILES_KEY, files); }
function loadDeletedVehicles() { return loadJson(DELETED_KEY, []); }
function saveDeletedVehicles(stockList) { saveJson(DELETED_KEY, stockList); }
function loadMechanics() { return loadJson(MECHANICS_KEY, []); }
function saveMechanics(names) {
  const cleaned = [...new Set((Array.isArray(names) ? names : []).map(name => cleanNavisionText(name)).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
  saveJson(MECHANICS_KEY, cleaned);
  return cleaned;
}

function loadSubletProviders() { return loadJson(SUBLET_PROVIDERS_KEY, []); }
function saveSubletProviders(names) {
  const cleaned = [...new Set((Array.isArray(names) ? names : []).map(name => cleanNavisionText(name)).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
  saveJson(SUBLET_PROVIDERS_KEY, cleaned);
  return cleaned;
}

function isBlankStock(value) {
  const stock = String(value || '').trim();
  return !stock || stock === '0' || /^TBA$/i.test(stock) || stock.startsWith('PENDING-');
}

function vehicleKey(vehicleOrKey) {
  if (typeof vehicleOrKey === 'string') return vehicleOrKey.trim();
  const v = vehicleOrKey || {};
  const stock = String(v.stock || '').trim();
  const order = String(v.order || '').trim();
  if (stock && !isBlankStock(stock)) return stock;
  return order || String(v.id || stock || '').trim();
}

function vehicleDeleteKey(vehicleOrStock) {
  return vehicleKey(vehicleOrStock);
}
function isDeletedVehicle(vehicle) {
  const key = vehicleDeleteKey(vehicle);
  return Boolean(key && loadDeletedVehicles().includes(key));
}

function getToyotaMatch(vehicle) {
  const stock = String(vehicle?.stock || '').trim();
  const order = String(vehicle?.order || '').trim();
  if (stock && TOYOTA_MATCHES[stock]) return TOYOTA_MATCHES[stock];
  if (order) return Object.values(TOYOTA_MATCHES).find(match => String(match.order || '').trim() === order) || null;
  return null;
}

function navisionEtaForVehicle(vehicle) {
  // Dashboard ETA must be Kewdale-only.
  // Do not fall back to ETA Date, Port/Plant ETA Date, or ETA At Dealer/BB.
  return scotEtaOnly(vehicle?.navisionKewdaleEta || vehicle?.etaAtKewdale || '');
}

function buildVehicleData() {
  const edits = loadVehicleEdits();
  const poTasks = loadPoTasks();
  const poFiles = loadPoFiles();
  const deleted = new Set(loadDeletedVehicles());
  const base = JSON.parse(JSON.stringify(window.VEHICLE_TRACKING_DATA.vehicles || []));
  const added = loadAddedVehicles();
  return base.concat(added).filter(vehicle => !deleted.has(vehicleDeleteKey(vehicle))).map(vehicle => {
    const key = vehicleKey(vehicle);
    const updated = {
      ...vehicle,
      jitaPartsOrdered: vehicle.jitaPartsOrdered || inferJitaPartsOrdered(vehicle),
      ...(edits[key] || edits[vehicle.stock] || {}),
    };
    return {
      ...updated,
      toyotaStatus: cleanNavisionText(updated.navisionSubLocationDescription || updated.toyotaStatus || ''),
      etaAtDealer: navisionEtaForVehicle(updated),
      poTasks: poTasks[key] || poTasks[vehicle.stock] || updated.poTasks || [],
      poFiles: poFiles[key] || poFiles[vehicle.stock] || updated.poFiles || [],
    };
  });
}

const app = {
  data: buildVehicleData(),
  matches: TOYOTA_MATCHES,
  report: window.VEHICLE_TRACKING_DATA?.report || {},
  currentView: 'dashboard',
  selectedStock: null,
  reviewed: false,
  quickFilter: 'incoming',
  pmbSubFilter: '',
  activePmbBayStage: '',
  pmbDraggingKey: '',
  pmbScheduleClockTimer: null,
  workflowBucketsCollapsed: true,
  workflowSearch: '',
  sort: { key: '', dir: 'asc' },
  selectedRows: new Set(),
  columnFilters: { sales: '', production: '', status: '', jita: '' },
  filterOptions: { statuses: [], consultants: [], productionMonths: [], sources: [] },
  autocareFiles: [],
  autocareScan: loadJson(AUTOCARE_RESULTS_KEY, null),
  navisionImport: loadJson(NAVISION_IMPORT_RESULTS_KEY, null),
  pendingNavisionImport: null,
  navisionFileName: '',
};


window.PDC_APP = app;
window.app = app;

function ensureAppDataAvailable() {
  if (!window.VEHICLE_TRACKING_DATA) window.VEHICLE_TRACKING_DATA = { report: {}, vehicles: [], toyotaMatches: {} };
  if (!Array.isArray(window.VEHICLE_TRACKING_DATA.vehicles)) window.VEHICLE_TRACKING_DATA.vehicles = [];
  if (!app.data.length && window.VEHICLE_TRACKING_DATA.vehicles.length) {
    app.data = buildVehicleData();
    app.selectedStock = vehicleKey(app.data.find(v => v.toyotaStatus) || app.data[0]);
  }
  return app.data;
}

function showStartupError(error) {
  console.error('PDC Control Board startup error', error);
  const message = error?.message || String(error || 'Unknown startup error');
  const target = document.querySelector('#fix-first-grid') || document.querySelector('#kpi-grid') || document.querySelector('main') || document.body;
  if (target && typeof target.insertAdjacentHTML === 'function') {
    target.insertAdjacentHTML('afterbegin', `<div class="startup-error-banner"><strong>Website error</strong><span>${escapeHtml(message)}</span><small>Open the browser console and send the error to the builder.</small></div>`);
  }
}

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const on = (target, eventName, handler, options) => {
  if (target && typeof target.addEventListener === 'function') target.addEventListener(eventName, handler, options);
};

function cleanName(value = '') {
  return String(value)
    .toUpperCase()
    .replace(/\s+-\s+R\b/g, '')
    .replace(/\bPTY\b|\bLTD\b|\bTHE\b|\bTRUSTEE\b|\bFOR\b/g, '')
    .replace(/[^A-Z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function similarity(a, b) {
  const sa = new Set(a.split(' ').filter(Boolean));
  const sb = new Set(b.split(' ').filter(Boolean));
  const intersection = [...sa].filter(x => sb.has(x)).length;
  const union = new Set([...sa, ...sb]).size || 1;
  return intersection / union;
}

function isCustomerMatch(vehicle) {
  if (/navision/i.test(String(vehicle?.source || ''))) return true;
  if (!vehicle.toyotaCustomer) return true;
  const excel = cleanName(vehicle.client);
  const toyota = cleanName(vehicle.toyotaCustomer);
  if (!excel || !toyota) return true;
  return excel.includes(toyota) || toyota.includes(excel) || similarity(excel, toyota) > 0.62;
}

function consultantName(vehicle) {
  return vehicle.consultant || vehicle.owner || 'Unassigned';
}

function salesPersonInitials(value) {
  const name = String(value || '').trim();
  if (!name || name === 'Unassigned') return '--';
  if (/^[A-Z]{1,4}$/i.test(name) && !name.includes(' ')) return name.toUpperCase();
  const words = name.replace(/[^A-Za-z0-9 ]+/g, ' ').split(/\s+/).filter(Boolean);
  if (!words.length) return '--';
  return words.slice(0, 3).map(w => w[0]).join('').toUpperCase();
}

function taskOptionsHtml(current = '') {
  let currentValue = String(current || '').trim();
  let normalizedCurrent = currentValue.toLowerCase();
  const disallowedTask = normalizedCurrent === 'do builds' || normalizedCurrent.includes('purchase order') || normalizedCurrent.includes('po task');
  if (disallowedTask) {
    currentValue = '';
    normalizedCurrent = '';
  }
  const options = TASK_OPTIONS.filter(task => task.toLowerCase() !== 'do builds');
  const extra = currentValue && !options.some(task => task.toLowerCase() === normalizedCurrent)
    ? [`${currentValue}`]
    : [];
  return ['<option value="">Select a task...</option>']
    .concat(options, extra)
    .map((task, index) => {
      if (index === 0) return task;
      const selected = task.toLowerCase() === normalizedCurrent ? ' selected' : '';
      return `<option value="${escapeHtml(task)}"${selected}>${escapeHtml(task)}</option>`;
    })
    .join('');
}

function inferJitaPartsOrdered(vehicle) {
  const qty = String(vehicle.jitQty || '').trim();
  if (qty && qty !== '0') return `Yes${qty ? ` - Qty ${qty}` : ''}`;
  return 'Unknown';
}

function normalizeJita(value) {
  const v = String(value || '').toLowerCase();
  if (v.startsWith('yes')) return 'Yes';
  if (v.startsWith('no')) return 'No';
  return 'Unknown';
}

function jitaDisplay(vehicle) {
  return vehicle.jitaPartsOrdered || inferJitaPartsOrdered(vehicle);
}

function jitaIndicator(vehicle) {
  const state = normalizeJita(jitaDisplay(vehicle));
  const detail = jitaDisplay(vehicle);
  if (state === 'Yes') return `<span class="jita-icon jita-yes" title="${escapeHtml(detail)}">✓</span>`;
  return `<span class="jita-icon jita-no" title="${escapeHtml(detail)}">×</span>`;
}

function legacyVehicleFlag(vehicle, key) {
  if (!vehicle) return false;
  const tasks = (vehicle.poTasks || []).join(' ').toLowerCase();
  const files = (vehicle.poFiles || []).join(' ').toLowerCase();
  const hasPoUpload = Boolean((vehicle.poFiles || []).length || tasks);
  if (key === 'buildPoRaised' && hasPoUpload) return true;
  if (vehicle[key] === true) return true;
  if (vehicle[key] === false) return false;
  if (key === 'tintRaised') return tasks.includes('window tint') || files.includes('tint');
  if (key === 'trayOrdered') return tasks.includes('tray');
  if (key === 'trayFitmentComplete') return false;
  return false;
}

function vehicleFlag(vehicle, key) {
  const def = pdcJobDefinitionForKey(key);
  if (def && key === def.requireKey) return pdcJobRequired(vehicle, def);
  if (def && key === def.completeKey) return pdcJobComplete(vehicle, def);
  return legacyVehicleFlag(vehicle, key);
}

function checkboxCell(vehicle, key, label, shortLabel = '') {
  const checked = vehicleFlag(vehicle, key) ? ' checked' : '';
  const def = pdcJobDefinitionForKey(key);
  const jobClass = def ? ` pdc-mini-${def.key}` : '';
  return `<label class="mini-check${jobClass}" title="${escapeHtml(label)}"><input type="checkbox" data-flag-stock="${escapeHtml(vehicleKey(vehicle))}" data-flag-key="${escapeHtml(key)}"${checked} /><span>${escapeHtml(shortLabel || label)}</span></label>`;
}

function pdcJobPartsVisualStatus(vehicle = {}, def = {}) {
  if (def?.key !== 'parts') return '';
  if (!pdcJobRequired(vehicle, def)) return '';
  if (pdcJobComplete(vehicle, def) || vehicle.pdcPartsReceived === true) return 'issued';
  if (partsOrdered(vehicle)) return 'onorder';
  return 'notordered';
}

function pdcJobTableCell(vehicle, def) {
  if (!def) return '';
  if (statusCategory(vehicle) === 'rft') {
    const checked = pdcJobComplete(vehicle, def);
    const mechanic = pdcJobMechanic(vehicle, def);
    const meta = [mechanic ? `Mechanic: ${mechanic}` : '', pdcJobBay(vehicle, def) ? `Bay ${pdcJobBay(vehicle, def)}` : '', pdcJobHours(vehicle, def) ? `${pdcJobHours(vehicle, def)}h` : ''].filter(Boolean).join(' · ');
    const title = checked
      ? `${def.label} was completed before RFT${meta ? ` · ${meta}` : ''}`
      : `${def.label} has not been signed off before RFT`;
    return `<label class="mini-check pdc-mini-${escapeHtml(def.key)} rft-completion-check ${checked ? 'is-complete' : 'is-missing'}" title="${escapeHtml(title)}"><input type="checkbox" data-flag-stock="${escapeHtml(vehicleKey(vehicle))}" data-flag-key="${escapeHtml(def.completeKey)}"${checked ? ' checked' : ''} /><span>${escapeHtml(def.short)}</span></label>`;
  }
  const partsVisualStatus = pdcJobPartsVisualStatus(vehicle, def);
  if (partsVisualStatus) {
    const checked = vehicleFlag(vehicle, def.requireKey) ? ' checked' : '';
    const statusLabel = partsVisualStatus === 'issued' ? 'Parts received/there' : partsVisualStatus === 'onorder' ? 'Parts confirmed/ordered' : 'Parts required - not ordered';
    return `<label class="mini-check pdc-mini-${escapeHtml(def.key)} parts-visual-${escapeHtml(partsVisualStatus)}" title="${escapeHtml(`${def.label} required · ${statusLabel}`)}"><input type="checkbox" data-flag-stock="${escapeHtml(vehicleKey(vehicle))}" data-flag-key="${escapeHtml(def.requireKey)}"${checked} /><span>${escapeHtml(def.short)}</span></label>`;
  }
  return checkboxCell(vehicle, def.requireKey, `${def.label} required`, def.short);
}

function flagGroupCell(vehicle) {
  return `<div class="flag-group" aria-label="PDC required jobs">${PDC_JOB_DEFS.map(def => checkboxCell(vehicle, def.requireKey, `${def.label} required`, def.short)).join('')}</div>`;
}

function getStage(vehicle) {
  const manualPdcLocation = vehiclePdcLocation(vehicle || {});
  if (manualPdcLocation === 'YH') return 'Yard Hold';
  if (manualPdcLocation === 'PMB') return 'PMB';
  if (manualPdcLocation === 'RFT') return 'RFT';

  const category = statusCategory(vehicle);
  if (category === 'yardhold') return 'Yard Hold';
  if (category === 'prodtransit') return 'Production / In Transit';
  if (category === 'batchmatched') return 'Batch Matched';

  const status = normalizeToyotaStatus(vehicle.toyotaStatus || '');
  if (isAutocareDespatched(vehicle)) return 'Production / In Transit';
  if (!status || status === 'not matched') return 'Needs Matching';
  return 'Needs Matching';
}

const STATUS_TAB_DEFS = [
  { key: 'incoming', label: 'All incoming', className: 'status-tab-batchmatched', sub: 'Not at PMB/RFT' },
  { key: 'prodtransit', label: 'Production / In Transit', className: 'status-tab-prodtransit', sub: 'Vehicles coming in' },
  { key: 'yardhold', label: 'Vehicles at YH', className: 'status-tab-yardhold', sub: 'Ready to release to PMB' },
];
const STATUS_TABS = STATUS_TAB_DEFS;

function vehicleHasBatchNumber(vehicle = {}) {
  return !isBlankStock(vehicle.batch || vehicle.stock || vehicle.toyotaBatch || vehicle.autocareBatch || '');
}

function navisionStatusText(vehicleOrStatus = '') {
  if (vehicleOrStatus && typeof vehicleOrStatus === 'object') {
    return cleanNavisionText(vehicleOrStatus.toyotaStatus || vehicleOrStatus.navisionSubLocationDescription || '');
  }
  return cleanNavisionText(vehicleOrStatus || '');
}

function vehiclePdcLocation(vehicle = {}) {
  return normalizePdcLocation(vehicle.pdcLocation || vehicle.pdcStatus || vehicle.manualLocation || '');
}

function vehicleCollectedFromRft(vehicle = {}) {
  return Boolean(vehicle.rftCollected || vehicle.rftCollectedAt || vehicle.completedVehicle);
}

function statusCategory(vehicleOrStatus = '') {
  const isVehicle = vehicleOrStatus && typeof vehicleOrStatus === 'object';
  if (isVehicle && vehicleCollectedFromRft(vehicleOrStatus)) return 'completed';
  if (isVehicle && !vehicleHasBatchNumber(vehicleOrStatus)) return 'other';

  if (isVehicle) {
    const manualPdcLocation = vehiclePdcLocation(vehicleOrStatus);
    if (manualPdcLocation === 'YH') return 'yardhold';
    if (manualPdcLocation === 'PMB') return 'pmb';
    if (manualPdcLocation === 'RFT') return 'rft';
  }

  const rawStatus = normalizeToyotaStatus(navisionStatusText(vehicleOrStatus));
  const canonicalStatus = normalizeToyotaStatus(canonicalToyotaStatus(rawStatus) || rawStatus);
  const locationStatus = isVehicle
    ? normalizeToyotaStatus(vehicleOrStatus.navisionLocationStatus || vehicleOrStatus.locationStatus || '')
    : '';
  const status = `${rawStatus} ${canonicalStatus} ${locationStatus}`.trim();

  // Navision is allowed to drive locations only up to Yard Hold. PMB and RFT
  // are manual PDC locations inside this tracker and are protected from imports.
  if (
    locationStatus === 'yh' ||
    status.includes('vehicle yard hold') ||
    status.includes('vehicle in yard hold') ||
    status.includes('yard hold') ||
    /\byh\b/.test(status)
  ) return 'yardhold';

  if (
    status.includes('planned for production') ||
    status.includes('line off complete') ||
    status.includes('final inspection') ||
    status.includes('in transit to o/s wharf') ||
    status.includes('in transit to os wharf') ||
    status.includes('in transit to eastern states') ||
    status.includes('ready for shipment') ||
    status.includes('in transit to wa') ||
    status.includes('vehicle at wharf') ||
    (status.includes('at wharf') && !status.includes('enroute')) ||
    status.includes('vehicle enroute from wharf') ||
    status.includes('production') ||
    status.includes('transit') ||
    status.includes('shipment') ||
    status.includes('wharf')
  ) return 'prodtransit';

  if (isVehicle && vehicleHasBatchNumber(vehicleOrStatus)) return 'batchmatched';

  return 'other';
}

function statusCategoryLabel(vehicleOrStatus = '') {
  const category = statusCategory(vehicleOrStatus);
  const tab = STATUS_TAB_DEFS.find(item => item.key === category);
  if (tab) return tab.label;
  return category === 'other' ? 'Other' : category;
}

function statusClass(vehicleOrStatus = '') {
  return `status-${statusCategory(vehicleOrStatus)}`;
}

function needsContact(vehicle) {
  const s = String(vehicle.toyotaStatus || '').toLowerCase();
  const internal = String(vehicle.internalStatus || '').toLowerCase();
  return s.includes('delayed') || s.includes('ready') || s.includes('dealer') || s.includes('transit') || internal.includes('tray') || !isCustomerMatch(vehicle);
}

function scotEtaOnly(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  const dates = [...text.matchAll(/\b\d{1,2}\/\d{1,2}\/\d{2,4}\b/g)].map(match => match[0]);
  // Some imported rows can accidentally include more than one date.
  // Keep the last date-like value for compact display.
  return dates.length ? dates[dates.length - 1] : text;
}

function parseDateAU(value) {
  const cleanValue = scotEtaOnly(value);
  if (!cleanValue || String(cleanValue).toUpperCase().includes('TBA')) return null;
  const m = String(cleanValue).match(/(\d{1,2})\/(\d{1,2})\/(\d{2,4})/);
  if (!m) return null;
  const year = Number(m[3].length === 2 ? '20' + m[3] : m[3]);
  return new Date(year, Number(m[2]) - 1, Number(m[1]));
}

function daysTo(value) {
  const dt = parseDateAU(value);
  if (!dt) return null;
  const baseline = new Date();
  baseline.setHours(0, 0, 0, 0);
  return Math.ceil((dt - baseline) / (1000 * 60 * 60 * 24));
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[ch]));
}

function navisionDealerNoteText(vehicle = {}) {
  return cleanNavisionText(vehicle.navisionDealerComments || vehicle.dealerComments || vehicle.financeNote || '');
}

function navisionNotesCell(vehicle = {}) {
  const note = navisionDealerNoteText(vehicle);
  if (!note) return '<span class="navision-note-empty" aria-label="No Navision Notes"></span>';
  return `<span class="navision-note-icon" tabindex="0" title="Navision Notes: ${escapeHtml(note)}" aria-label="Navision Notes: ${escapeHtml(note)}">!</span>`;
}

function formatStatus(vehicle) {
  const manualPdcLocation = vehiclePdcLocation(vehicle || {});
  const navisionStatus = String(vehicle?.toyotaStatus || '').trim() || 'No Sub Location';
  const primaryStatus = manualPdcLocation ? pdcLocationLabel(manualPdcLocation) : navisionStatus;
  const navisionLine = manualPdcLocation && navisionStatus && navisionStatus !== 'No Sub Location'
    ? `<div class="subtle pdc-status-note">Navision: ${escapeHtml(navisionStatus)}</div>`
    : '';
  const autocare = isAutocareDespatched(vehicle) && navisionStatus !== AUTOCARE_DESPATCH_STATUS
    ? `<div class="subtle autocare-status-note">${escapeHtml(AUTOCARE_DESPATCH_STATUS)}</div>`
    : '';
  return `<span class="badge ${statusClass(vehicle)}">${escapeHtml(primaryStatus)}</span>${navisionLine}${autocare}`;
}

function dateHelper(value) {
  const d = daysTo(value);
  if (d === null) return '';
  if (d < 0) return `${Math.abs(d)} days past ETA`;
  if (d === 0) return 'Due today';
  return `${d} days to ETA`;
}

function etaDeltaText(value) {
  const d = daysTo(value);
  if (d === null) return { label: '', cls: 'neutral' };
  if (d < 0) {
    const daysPast = Math.abs(d);
    return { label: `+${daysPast} days`, cls: 'negative', title: `${daysPast} days past ETA / on ground` };
  }
  if (d === 0) return { label: 'Today', cls: 'neutral', title: 'ETA is today' };
  return { label: `${d} days`, cls: 'positive', title: `${d} days to ETA` };
}

function formatEta(value) {
  const eta = scotEtaOnly(value);
  if (!eta) return '';
  const delta = etaDeltaText(eta);
  const badge = delta.label ? `<span class="eta-badge ${delta.cls}" title="${escapeHtml(delta.title || delta.label)}">${escapeHtml(delta.label)}</span>` : '';
  return `<div class="eta-inline"><strong>${escapeHtml(eta)}</strong>${badge}</div>`;
}

function displayStockNumber(vehicle) {
  const stock = String(vehicle?.stock || '').trim();
  const order = String(vehicle?.order || '').trim();
  if (isBlankStock(stock)) return order || stock.replace(/^PENDING-/, '') || '';
  return stock;
}

function vehicleKeyNumber(vehicle = {}) {
  return cleanNavisionText(
    vehicle.keyNumber ||
    vehicle.keyNo ||
    vehicle.keyTag ||
    vehicle.pdcKeyNumber ||
    vehicle.vehicleKeyNumber ||
    ''
  );
}

function vehicleJobcardNumber(vehicle = {}) {
  return cleanNavisionText(
    vehicle.pdcJobcard ||
    vehicle.jobcard ||
    vehicle.jobCard ||
    vehicle.jobcardNumber ||
    vehicle.jobCardNumber ||
    vehicle.jcJobcard ||
    vehicle.jc ||
    ''
  );
}

function vehicleCustomerName(vehicle = {}) {
  return cleanNavisionText(vehicle.client || vehicle.toyotaCustomer || vehicle.dealerCustomer || '');
}

function vehicleIdentityParts(vehicle = {}) {
  const stock = displayStockNumber(vehicle) || String(vehicle.order || '').trim();
  return [
    { label: 'Key', value: vehicleKeyNumber(vehicle) },
    { label: 'Stock', value: stock },
    { label: 'JC', value: vehicleJobcardNumber(vehicle) },
    { label: 'Customer', value: vehicleCustomerName(vehicle) },
  ].filter(part => cleanNavisionText(part.value));
}

function vehicleIdentityLabelText(part = {}) {
  return `${part.label} ${part.value}`.trim();
}

function vehicleIdentityPrimary(vehicle = {}) {
  return vehicleIdentityParts(vehicle)[0] || { label: 'Vehicle', value: displayVehicle(vehicle) || 'Vehicle' };
}

function vehicleIdentityTitle(vehicle = {}) {
  const parts = vehicleIdentityParts(vehicle).map(vehicleIdentityLabelText);
  const unit = displayVehicle(vehicle);
  if (unit) parts.push(unit);
  return parts.join(' · ');
}

function vehicleIdentitySecondaryText(vehicle = {}) {
  return vehicleIdentityParts(vehicle).slice(1).map(vehicleIdentityLabelText).join(' · ');
}

const VEHICLE_IDENTITY_COLUMNS = [
  { label: 'Key', className: 'identity-key' },
  { label: 'SN', className: 'identity-stock' },
  { label: 'JC', className: 'identity-jc' },
  { label: 'Name', className: 'identity-name' },
];

function vehicleIdentityCells(vehicle = {}) {
  const stock = displayStockNumber(vehicle) || String(vehicle.order || '').trim();
  return [
    { ...VEHICLE_IDENTITY_COLUMNS[0], value: vehicleKeyNumber(vehicle) },
    { ...VEHICLE_IDENTITY_COLUMNS[1], value: stock },
    { ...VEHICLE_IDENTITY_COLUMNS[2], value: vehicleJobcardNumber(vehicle) },
    { ...VEHICLE_IDENTITY_COLUMNS[3], value: vehicleCustomerName(vehicle) },
  ];
}

function vehicleIdentityHeaderHtml(className = '') {
  const cells = VEHICLE_IDENTITY_COLUMNS.map(cell => `<span class="vehicle-identity-heading ${escapeHtml(cell.className)}">${escapeHtml(cell.label)}</span>`).join('');
  return `<div class="vehicle-identity-header vehicle-identity-columns ${escapeHtml(className)}" aria-hidden="true">${cells}</div>`;
}

function vehicleIdentityStackHtml(vehicle = {}, options = {}) {
  const cells = vehicleIdentityCells(vehicle);
  const key = vehicleKey(vehicle);
  const title = vehicleIdentityTitle(vehicle);
  const classes = ['vehicle-identity-stack', 'vehicle-identity-columns', options.className || ''].filter(Boolean).join(' ');
  const html = cells.map((cell, index) => {
    const rawValue = cleanNavisionText(cell.value) || '—';
    const value = truncate(rawValue, cell.label === 'Name' ? 28 : 16);
    const valueHtml = options.button && index === 0
      ? `<button class="stock-link stock-button vehicle-identity-value vehicle-identity-primary" type="button" data-open-stock="${escapeHtml(key)}" title="${escapeHtml(title)}" aria-label="${escapeHtml(`${cell.label} ${rawValue}`)}">${escapeHtml(value)}</button>`
      : `<span class="vehicle-identity-value ${index === 0 ? 'vehicle-identity-primary' : ''}" title="${escapeHtml(rawValue)}" aria-label="${escapeHtml(`${cell.label} ${rawValue}`)}">${escapeHtml(value)}</span>`;
    return `<span class="vehicle-identity-cell ${escapeHtml(cell.className)}" data-label="${escapeHtml(cell.label)}">${valueHtml}</span>`;
  }).join('');
  return `<div class="${escapeHtml(classes)}" title="${escapeHtml(title)}">${html}</div>`;
}

function vehiclePmbKeyNumber(vehicle = {}) {
  return statusCategory(vehicle) === 'pmb' ? vehicleKeyNumber(vehicle) : '';
}

function activePmbVehicleWithKeyNumber(keyNumber = '', currentKey = '') {
  const cleanKeyNumber = cleanNavisionText(keyNumber).toLowerCase();
  const cleanCurrentKey = String(currentKey || '').trim();
  if (!cleanKeyNumber) return null;
  return (app.data || []).find(vehicle => {
    const key = vehicleKey(vehicle);
    return key !== cleanCurrentKey && statusCategory(vehicle) === 'pmb' && vehicleKeyNumber(vehicle).toLowerCase() === cleanKeyNumber;
  }) || null;
}

function pmbKeyNumberPillHtml(vehicle = {}) {
  const keyNumber = vehiclePmbKeyNumber(vehicle);
  return keyNumber ? `<span class="pmb-keytag-pill" title="PMB key tag number">Key ${escapeHtml(keyNumber)}</span>` : '';
}

function stockOrderSubline(vehicle) {
  return '';
}

function stockLabel(vehicle) {
  const stock = String(vehicle?.stock || '').trim();
  if (isBlankStock(stock)) return 'Order';
  return 'Stock';
}


function actionSelectHtml(stock) {
  return `<select class="action-select" data-action-stock="${escapeHtml(stock)}" aria-label="Select vehicle action">
    <option value="">Select action...</option>
    <option value="released">Vehicle Released</option>
    <option value="update">Request Update</option>
    <option value="build">New PMB Work Order</option>
    <option value="tint">Tint PO Email</option>
  </select>`;
}

function truncate(value, max) {
  value = String(value || '');
  return value.length > max ? value.slice(0, max - 1) + '…' : value;
}

function titleCaseVehicle(value) {
  const keepUpper = new Set(['LC300', 'LC70', 'RAV4', 'AWD', '2WD', 'PHEV', 'GR', 'SR', 'SR5', 'GX', 'GXL', 'VX', 'ECC', 'DCC', 'SCC', 'DC', 'WM', 'AT', 'ZX', 'XSE']);
  return String(value || '')
    .trim()
    .split(/\s+/)
    .map(token => {
      const clean = token.replace(/[^A-Za-z0-9+-]/g, '');
      const upper = clean.toUpperCase();
      if (keepUpper.has(upper)) return upper;
      if (upper === 'HILUX') return 'Hilux';
      if (upper === 'HIACE') return 'HiAce';
      if (upper === 'RAV') return 'RAV';
      return clean.charAt(0).toUpperCase() + clean.slice(1).toLowerCase();
    })
    .join(' ')
    .replace(/Yaris-\s*Cross/i, 'Yaris Cross');
}

function displayVehicle(vehicle) {
  const preferred = String(vehicle.vehicle || '').trim();
  const toyota = [vehicle.toyotaVehicle, vehicle.suffix].filter(Boolean).join(' ').trim();
  const raw = (!preferred || /\d\.\dL|\bDSL\b|\bHYB\b|\bCVT\b|\b6AT\b|\b10AT\b|\bWGN\b|\bFABRIC\b|\bGLACIER\b|\bFROSTED\b|\bGRAPHITE\b/i.test(preferred))
    ? (toyota || preferred)
    : preferred;
  return compactVehicleDescription(raw);
}

function compactVehicleDescription(rawValue) {
  let raw = String(rawValue || '').replace(/\s+/g, ' ').trim();
  if (!raw) return '';
  const upper = raw.toUpperCase();
  let model = '';
  if (/\bHI\s?LUX\b/.test(upper)) model = 'Hilux';
  else if (/\bLC300\b/.test(upper)) model = 'LC300';
  else if (/\bLC70\b/.test(upper)) model = 'LC70';
  else if (/\bPRADO\b/.test(upper)) model = 'Prado';
  else if (/\bRAV4\b/.test(upper)) model = 'RAV4';
  else if (/\bFORTUNER\b/.test(upper)) model = 'Fortuner';
  else if (/\bYARIS[- ]?CROSS\b/.test(upper)) model = 'Yaris Cross';
  else if (/\bYARIS\b/.test(upper)) model = 'Yaris';
  else if (/\bCOROLLA CROSS\b/.test(upper)) model = 'Corolla Cross';
  else if (/\bCOROLLA\b/.test(upper)) model = 'Corolla';
  else if (/\bCAMRY\b/.test(upper)) model = 'Camry';
  else if (/\bHIACE\b/.test(upper)) model = 'HiAce';
  else if (/\bCOASTER\b/.test(upper)) model = 'Coaster';
  else if (/\bTUNDRA\b/.test(upper)) model = 'Tundra';
  else if (/\bBZ4X\b/.test(upper)) model = 'bZ4X';

  const parts = model ? [model] : [];
  const bodyMatch = upper.match(/\b(E\/C\/C|D\/C\/C|S\/C\/C|E\/C|D\/C|S\/C|ECC|DCC|SCC|DUAL CAB|SINGLE CAB)\b/);
  if (bodyMatch) {
    const body = bodyMatch[1]
      .replace('E/C/C', 'ECC')
      .replace('D/C/C', 'DCC')
      .replace('S/C/C', 'SCC')
      .replace('E/C', 'EC')
      .replace('D/C', 'DC')
      .replace('S/C', 'SC')
      .replace('DUAL CAB', 'DCC')
      .replace('SINGLE CAB', 'SCC');
    if (!parts.includes(body)) parts.push(body);
  }

  const gradePatterns = [
    ['SAHARA ZX', 'Sahara ZX'], ['GR SPORT', 'GR Sport'], ['GR-SPORT', 'GR Sport'], ['GR-S', 'GR-S'],
    ['RUGGED X', 'Rugged X'], ['WORKMATE', 'WM'], ['ROGUE', 'Rogue'], ['CRUISER', 'Cruiser'],
    ['ALTITUDE', 'Altitude'], ['KAKADU', 'Kakadu'], ['ATMOS', 'Atmos'], ['ASCENT SPORT', 'Ascent Sport'],
    ['SAHARA', 'Sahara'], ['VX', 'VX'], ['GXL', 'GXL'], ['GX', 'GX'], ['SR5', 'SR5'], ['SR', 'SR'],
    ['XSE', 'XSE'], ['BASE', 'Base'], ['DELUXE', 'Deluxe'], ['LIMITED', 'Limited']
  ];
  const found = gradePatterns.find(([pattern]) => upper.includes(pattern));
  if (found && !parts.includes(found[1])) parts.push(found[1]);

  if (upper.includes('AWD') && ['RAV4', 'Yaris Cross', 'Corolla Cross'].includes(model) && !parts.includes('AWD')) parts.splice(1, 0, 'AWD');
  if (upper.includes('2WD') && ['RAV4', 'Yaris Cross', 'Corolla Cross'].includes(model) && !parts.includes('2WD')) parts.splice(1, 0, '2WD');
  if (upper.includes('PHEV') && !parts.includes('PHEV')) parts.splice(Math.min(parts.length, 2), 0, 'PHEV');

  return parts.length ? parts.join(' ') : titleCaseVehicle(raw);
}

function sortValue(vehicle, key) {
  switch (key) {
    case 'consultant': return salesPersonInitials(consultantName(vehicle));
    case 'stock': return vehicle.stock || '';
    case 'prodMth': return `${String(productionMonthRank(vehicle.prodMth || vehicle.productionMonth || '')).padStart(8, '0')} ${productionMonthLabel(vehicle.prodMth || vehicle.productionMonth || '')}`;
    case 'order': return vehicle.order || '';
    case 'client': return vehicle.client || vehicle.toyotaCustomer || '';
    case 'vehicle': return displayVehicle(vehicle);
    case 'navisionNotes': return navisionDealerNoteText(vehicle);
    case 'internalStatus': return vehicle.internalStatus || '';
    case 'toyotaStatus': return `${String(toyotaStatusRank(vehicle.toyotaStatus)).padStart(4, '0')} ${vehicle.toyotaStatus || ''}`;
    case 'eta': return parseDateAU(vehicle.etaAtDealer)?.getTime() || 9999999999999;
    case 'jita': return normalizeJita(jitaDisplay(vehicle));
    case 'pdcRequiresTint': return vehicleFlag(vehicle, 'pdcRequiresTint') ? 'Yes' : 'No';
    case 'pdcRequiresHoist': return vehicleFlag(vehicle, 'pdcRequiresHoist') ? 'Yes' : 'No';
    case 'pdcRequiresFitting': return vehicleFlag(vehicle, 'pdcRequiresFitting') ? 'Yes' : 'No';
    case 'pdcRequiresFabrication': return vehicleFlag(vehicle, 'pdcRequiresFabrication') ? 'Yes' : 'No';
    case 'pdcRequiresElectrical': return vehicleFlag(vehicle, 'pdcRequiresElectrical') ? 'Yes' : 'No';
    case 'pdcRequiresTyre': return vehicleFlag(vehicle, 'pdcRequiresTyre') ? 'Yes' : 'No';
    case 'pdcRequiresPitInspection': return vehicleFlag(vehicle, 'pdcRequiresPitInspection') ? 'Yes' : 'No';
    case 'tintRaised': return legacyVehicleFlag(vehicle, 'tintRaised') ? 'Yes' : 'No';
    case 'buildPoRaised': return legacyVehicleFlag(vehicle, 'buildPoRaised') ? 'Yes' : 'No';
    case 'buildComplete': return legacyVehicleFlag(vehicle, 'buildComplete') ? 'Yes' : 'No';
    case 'trayOrdered': return legacyVehicleFlag(vehicle, 'trayOrdered') ? 'Yes' : 'No';
    case 'trayFitmentComplete': return legacyVehicleFlag(vehicle, 'trayFitmentComplete') ? 'Yes' : 'No';
    default: return '';
  }
}

function sortRows(rows) {
  const { key, dir } = app.sort || {};
  if (!key) return rows;
  const collator = new Intl.Collator('en-AU', { numeric: true, sensitivity: 'base' });
  const direction = dir === 'desc' ? -1 : 1;
  return rows.slice().sort((a, b) => {
    const av = sortValue(a, key);
    const bv = sortValue(b, key);
    const cmp = typeof av === 'number' && typeof bv === 'number'
      ? av - bv
      : collator.compare(String(av), String(bv));
    return cmp * direction;
  });
}

function setSort(key) {
  const current = app.sort || {};
  const defaultDir = key === 'prodMth' ? 'desc' : 'asc';
  app.sort = {
    key,
    dir: current.key === key ? (current.dir === 'asc' ? 'desc' : 'asc') : defaultDir,
  };
  renderVehicleTable();
}

function sortableTh(label, key) {
  const active = app.sort?.key === key;
  const arrow = active ? (app.sort.dir === 'asc' ? '▲' : '▼') : '';
  return `<button class="sort-header" type="button" data-sort-key="${escapeHtml(key)}">${escapeHtml(label)}<span class="sort-indicator">${arrow}</span></button>`;
}

function columnFilterSlot(key, options = [], selected = '', placeholder = 'All') {
  const opts = (options || []).map(option => typeof option === 'object'
    ? { value: String(option.value || ''), label: String(option.label || option.value || '') }
    : { value: String(option || ''), label: String(option || '') });
  const html = [`<option value="">${escapeHtml(placeholder)}</option>`]
    .concat(opts.map(option => `<option value="${escapeHtml(option.value)}"${option.value === selected ? ' selected' : ''}>${escapeHtml(option.label)}</option>`))
    .join('');
  return `<div class="column-filter-slot"><select class="column-filter-select" data-column-filter="${escapeHtml(key)}" aria-label="Filter ${escapeHtml(key)}">${html}</select></div>`;
}

function emptyColumnFilterSlot() {
  return '<div class="column-filter-slot column-filter-empty" aria-hidden="true"><span></span></div>';
}

function bindColumnFilterControls(root = document) {
  $$('[data-column-filter]', root).forEach(select => {
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', () => {
      const key = select.dataset.columnFilter;
      if (!key) return;
      app.columnFilters = app.columnFilters || { sales: '', production: '', status: '', jita: '' };
      app.columnFilters[key] = select.value;
      renderKpis();
      renderVehicleTable();
    });
  });
}

function toggleSidebar() {
  const shell = $('#app-shell');
  if (!shell) return;
  shell.classList.toggle('sidebar-collapsed');
  const collapsed = shell.classList.contains('sidebar-collapsed');
  const button = $('#sidebar-toggle');
  if (button) {
    button.setAttribute('aria-label', collapsed ? 'Expand sidebar' : 'Collapse sidebar');
    button.title = collapsed ? 'Expand sidebar' : 'Collapse sidebar';
  }
}

function updateNavisionSidebarMeta() {
  const importedAt = app.navisionImport?.importedAt ? new Date(app.navisionImport.importedAt) : null;
  const dateLabel = importedAt && !Number.isNaN(importedAt.getTime())
    ? importedAt.toLocaleString('en-AU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : 'No Navision import yet';
  const reportDate = $('#report-date');
  const reportMeta = $('#report-meta');
  if (reportDate) reportDate.textContent = dateLabel;
  if (reportMeta) reportMeta.textContent = `${app.data.length} vehicle${app.data.length === 1 ? '' : 's'} · Navision only`;
}

function init() {
  ensureAppDataAvailable();
  renderAppVersionMarker();
  updateNavisionSidebarMeta();
  app.selectedStock = vehicleKey(app.data.find(v => v.toyotaStatus) || app.data[0]);
  bindNav();
  populateFilters();
  renderAll();
}

function renderAppVersionMarker() {
  const host = $('#app-version');
  if (host) host.textContent = `Version ${APP_VERSION}`;
}

function bindNav() {
  $$('.nav-item').forEach(btn => btn.addEventListener('click', () => showView(btn.dataset.view)));
  on($('#sidebar-toggle'), 'click', toggleSidebar);
  on($('#operator-profile'), 'click', setOperatorProfile);
  on($('#tv-set-operator-top'), 'click', setOperatorProfile);
  $$('[data-view-target]').forEach(btn => btn.addEventListener('click', () => showView(btn.dataset.viewTarget)));
  on($('#search'), 'input', () => { renderKpis(); renderVehicleTable(); });
  on($('#status-filter'), 'change', () => { renderKpis(); renderVehicleTable(); });
  on($('#sales-filter'), 'change', () => { renderKpis(); renderVehicleTable(); });
  on($('#production-filter'), 'change', () => { renderKpis(); renderVehicleTable(); });
  on($('#source-filter'), 'change', () => { renderKpis(); renderVehicleTable(); });
  on($('#jita-filter'), 'change', () => { renderKpis(); renderVehicleTable(); });
  on($('#parts-search'), 'input', renderPartsHome);
  on($('#parts-status-filter'), 'change', renderPartsHome);
  on($('#schedule-search'), 'input', renderScheduleBoard);
  on($('#schedule-department-filter'), 'change', renderScheduleBoard);
  on($('#department-search'), 'input', renderProductionDepartmentBoard);
  on($('#department-status-filter'), 'change', renderProductionDepartmentBoard);
  on($('#parts-export-csv'), 'click', exportPartsCsv);
  on($('#rft-export-csv'), 'click', exportRftCsv);
  on($('#rft-search'), 'input', renderRftHome);
  on($('#rft-status-filter'), 'change', renderRftHome);
  on($('#completed-export-csv'), 'click', exportCompletedVehiclesCsv);
  on($('#completed-search'), 'input', renderCompletedVehicles);
  on($('#customer-search'), 'input', renderCustomers);
  on($('#clear-table-filters'), 'click', () => clearAllFilters());
  on($('#reset-table-columns'), 'click', resetVehicleTableColumnOrder);
  on($('#show-all-priority'), 'click', () => clearAllFilters());
  on($('#export-csv'), 'click', exportCsv);
  on($('#export-backup'), 'click', exportCrmBackup);
  on($('#export-backup-top'), 'click', exportCrmBackup);
  on($('#backup-upload'), 'change', handleCrmBackupFileSelect);
  on($('#email-selected-amy'), 'click', draftSelectedArrivingVehicleEmail);
  on($('#email-selected-amy-bar'), 'click', draftSelectedArrivingVehicleEmail);
  $$('[data-print-selected-zpl]').forEach(button => button.addEventListener('click', printZplFromSelectedRows));
  on($('#override-selected-to-yh-bar'), 'click', overrideSelectedVehiclesToYh);
  on($('#override-selected-to-yh-top'), 'click', overrideSelectedVehiclesToYh);
  on($('#transfer-selected-to-pmb-bar'), 'click', transferSelectedYhVehiclesToPmb);
  on($('#transfer-selected-to-pmb-top'), 'click', transferSelectedYhVehiclesToPmb);
  on($('#transfer-selected-to-rft-bar'), 'click', transferSelectedPmbVehiclesToRft);
  on($('#delete-selected-vehicles'), 'click', deleteSelectedVehicles);
  on($('#delete-selected-vehicles-bar'), 'click', deleteSelectedVehicles);
  on($('#clear-selected-rows'), 'click', clearSelectedRows);
  on($('#clear-selected-rows-bar'), 'click', clearSelectedRows);
  on($('#zpl-generate'), 'click', generateZplFromInput);
  on($('#zpl-copy'), 'click', copyZplOutput);
  on($('#zpl-print'), 'click', printCurrentZplOutput);
  on($('#zpl-clear'), 'click', clearZplGenerator);
  on($('#autocare-upload'), 'change', handleAutocareSelect);
  on($('#navision-upload'), 'change', handleNavisionFileSelect);
  on($('#navision-paste'), 'input', updateNavisionImportButton);
  on($('#dashboard-navision-paste'), 'input', updateDashboardNavisionPasteButtons);
  on($('#dashboard-import-navision'), 'click', importDashboardNavisionPaste);
  on($('#dashboard-clear-navision'), 'click', clearDashboardNavisionPaste);
  on($('#dashboard-pd-paste'), 'input', updateDashboardPdImportButtons);
  on($('#dashboard-pd-upload'), 'change', handleDashboardPdFileSelect);
  on($('#dashboard-import-pd'), 'click', importDashboardPdWork);
  on($('#dashboard-clear-pd'), 'click', clearDashboardPdImport);
  on($('#incoming-search'), 'input', renderIncomingDashboardBoard);
  on($('#incoming-status-filter'), 'change', renderIncomingDashboardBoard);
  on($('#incoming-bucket-filter'), 'change', renderIncomingDashboardBoard);
  on($('#incoming-rep-filter'), 'change', renderIncomingDashboardBoard);
  $$('input[name="incoming-work-filter"]').forEach(input => input.addEventListener('change', renderIncomingDashboardBoard));
  on($('#incoming-find'), 'click', renderIncomingDashboardBoard);
  on($('#incoming-clear-filters'), 'click', clearIncomingDashboardFilters);
  on($('#incoming-collapse-all'), 'click', collapseMainScreenRows);
  on($('#workflow-collapse-all'), 'click', collapseWorkflowRows);
  on($('#workflow-search'), 'input', event => { app.workflowSearch = String(event.target.value || '').trim().toLowerCase(); renderWorkflowBoard(); });
  on($('#workflow-find'), 'click', () => { app.workflowSearch = String($('#workflow-search')?.value || '').trim().toLowerCase(); renderWorkflowBoard(); });
  on($('#workflow-clear-search'), 'click', clearWorkflowSearch);
  on($('#incoming-transfer-selected-pmb'), 'click', transferSelectedMainYhVehiclesToPmb);
  on($('#incoming-delete-selected'), 'click', deleteSelectedVehicles);
  on($('#incoming-clear-selected'), 'click', clearSelectedRows);
  on($('#workflow-transfer-selected-rft'), 'click', transferSelectedPmbVehiclesToRft);
  on($('#workflow-delete-selected'), 'click', deleteSelectedVehicles);
  on($('#workflow-clear-selected'), 'click', clearSelectedRows);
  bindDashboardPdDropZone();
  on($('#navision-pmb-only'), 'change', updateNavisionImportButton);
  on($('#import-navision'), 'click', importNavisionVehicles);
  on($('#navision-clear'), 'click', clearNavisionImport);
  on($('#add-mechanic-list-button'), 'click', addMechanicFromAdminInput);
  on($('#mechanic-name-input'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); addMechanicFromAdminInput(); } });
  on($('#add-sublet-provider-button'), 'click', addSubletProviderFromAdminInput);
  on($('#sublet-provider-name-input'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); addSubletProviderFromAdminInput(); } });
  on($('#scan-autocare'), 'click', scanAutocareNotice);
  on($('#autocare-clear'), 'click', clearAutocareResults);
  on($('#autocare-zpl-all'), 'click', () => generateZplFromAutocareResults('all'));
  on($('#autocare-zpl-unmatched'), 'click', () => generateZplFromAutocareResults('unmatched'));
  on($('#autocare-paste'), 'input', updateAutocareScanButton);
  on($('#pdf-upload'), 'change', handlePdfSelect);
  on($('#po-upload'), 'change', handlePoSelect);
  on($('#scan-report'), 'click', scanReport);
  on($('#approve-all'), 'click', approveCleanMatches);
  on($('#modal-close'), 'click', closeVehicleModal);
  on($('#vehicle-modal'), 'click', (e) => { if (e.target.id === 'vehicle-modal') closeVehicleModal(); });
  on($('#add-customer-open'), 'click', openCustomerModal);
  on($('#add-customer-top'), 'click', openCustomerModal);
  on($('#add-customer-customers'), 'click', openCustomerModal);
  on($('#customer-modal-close'), 'click', closeCustomerModal);
  on($('#customer-modal-cancel'), 'click', closeCustomerModal);
  on($('#customer-modal'), 'click', (e) => { if (e.target.id === 'customer-modal') closeCustomerModal(); });
  on($('#new-customer-form'), 'submit', addCustomerFromForm);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeVehicleModal(); closeCustomerModal(); }
  });
}


function addMechanicFromAdminInput() {
  const input = $('#mechanic-name-input');
  const entered = cleanNavisionText(input?.value || '');
  if (!entered) return;
  saveMechanics([...loadMechanics(), entered]);
  if (input) input.value = '';
  renderAdminLists();
  renderKpis();
}

function removeMechanicFromAdminList(name = '') {
  const clean = cleanNavisionText(name);
  if (!clean) return;
  if (!window.confirm(`Remove mechanic "${clean}" from the dropdown list? Existing vehicle history will stay on the vehicle.`)) return;
  saveMechanics(loadMechanics().filter(item => item !== clean));
  renderAdminLists();
  renderKpis();
}

function addSubletProviderFromAdminInput() {
  const input = $('#sublet-provider-name-input');
  const entered = cleanNavisionText(input?.value || '');
  if (!entered) return;
  saveSubletProviders([...loadSubletProviders(), entered]);
  if (input) input.value = '';
  renderAdminLists();
  renderKpis();
}

function removeSubletProviderFromAdminList(name = '') {
  const clean = cleanNavisionText(name);
  if (!clean) return;
  if (!window.confirm(`Remove provider "${clean}" from the dropdown list? Existing vehicle history will stay on the vehicle.`)) return;
  saveSubletProviders(loadSubletProviders().filter(item => item !== clean));
  renderAdminLists();
  renderKpis();
}

function renderAdminList(host, items, removeAttr, emptyText) {
  if (!host) return;
  if (!items.length) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>No entries yet</strong><span>${escapeHtml(emptyText)}</span></div>`;
    return;
  }
  host.innerHTML = items.map(item => `<span class="admin-chip"><strong>${escapeHtml(item)}</strong><button type="button" class="text-button" ${removeAttr}="${escapeHtml(item)}">Remove</button></span>`).join('');
}

function renderAdminLists() {
  renderAdminList($('#mechanic-list-admin'), loadMechanics(), 'data-remove-mechanic', 'Add mechanics so they appear in the bay assignment dropdowns.');
  renderAdminList($('#sublet-provider-list-admin'), loadSubletProviders(), 'data-remove-provider', 'Add outside providers for specialist work records.');
  $$('[data-remove-mechanic]').forEach(button => button.addEventListener('click', () => removeMechanicFromAdminList(button.dataset.removeMechanic)));
  $$('[data-remove-provider]').forEach(button => button.addEventListener('click', () => removeSubletProviderFromAdminList(button.dataset.removeProvider)));
}

function showView(view) {
  const requestedView = view || 'dashboard';
  const departmentStage = PRODUCTION_DEPARTMENT_VIEWS[requestedView] || '';
  if (requestedView !== 'workflow') {
    app.activePmbBayStage = '';
    app.pmbSubFilter = '';
    document.body.classList.remove('pmb-station-mode');
    const pmbWorkflowHost = $('#pmb-workflow-board');
    if (pmbWorkflowHost) pmbWorkflowHost.classList.remove('station-only');
  }
  if (departmentStage) app.activeProductionDepartment = departmentStage;
  app.currentView = departmentStage ? 'department' : requestedView;
  $$('.view').forEach(el => el.classList.toggle('active', el.id === requestedView || (departmentStage && el.id === 'department')));
  $$('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.view === requestedView));
  const departmentDef = departmentStage ? PRODUCTION_FLOW_DEFS.find(def => def.key === departmentStage) : null;
  const titleMap = {
    dashboard: 'Control Board',
    workflow: 'PMB Workflow',
    pipeline: 'Vehicle Pipeline',
    visibility: 'Operational Visibility',
    tv: 'PDC TV Board',
    schedule: 'Production',
    parts: 'Parts',
    rft: 'RFT',
    lists: 'Reports / Admin',
    import: 'Uploads',
    zpl: 'Label Tools'
  };
  const pageTitle = $('#page-title');
  if (pageTitle) pageTitle.textContent = departmentDef ? departmentDef.label : (titleMap[requestedView] || 'Control Board');
  if (requestedView !== 'dashboard' && app.frozenHeaderCleanup) {
    app.frozenHeaderCleanup();
    app.frozenHeaderCleanup = null;
  }
  renderActiveView();
  if (requestedView === 'dashboard') {
    window.setTimeout(() => setupFrozenVehicleHeader($('#vehicle-table')), 0);
  }
}


function populateFilters() {
  const statuses = sortToyotaStatuses([...new Set(app.data.map(v => v.toyotaStatus).filter(Boolean))]);
  const consultants = [...new Set(app.data.map(v => salesPersonInitials(consultantName(v))).filter(Boolean))].sort();
  const productionMonths = sortProductionMonths([...new Set(app.data.map(v => productionMonthLabel(v.prodMth || v.productionMonth || '')).filter(Boolean))]);
  const sources = [...new Set(app.data.map(v => v.source).filter(Boolean))].sort();
  app.filterOptions = { statuses, consultants, productionMonths, sources };
  app.columnFilters = app.columnFilters || { sales: '', production: '', status: '', jita: '' };
  [['status', statuses], ['sales', consultants], ['production', productionMonths], ['jita', ['Yes', 'No', 'Unknown']]].forEach(([key, options]) => {
    if (app.columnFilters[key] && !options.includes(app.columnFilters[key])) app.columnFilters[key] = '';
  });
  const sourceFilter = $('#source-filter');
  if (sourceFilter) {
    const selected = sourceFilter.value || '';
    sourceFilter.innerHTML = '<option value="">All sources</option>' + sources.map(s => `<option value="${escapeHtml(s)}"${s === selected ? ' selected' : ''}>${escapeHtml(s)}</option>`).join('');
  }
  populateTaskSelects();
}

function populateTaskSelects() {
  const select = $('#new-customer-task');
  if (select) select.innerHTML = taskOptionsHtml('');
}


function updateSidebarStats() {
  updateNavisionSidebarMeta();
}

function renderAll() {
  ensureAppDataAvailable();
  updateSidebarStats();
  populateFilters();
  renderActiveView();
  updateNavisionImportButton();
}

function renderActiveView() {
  ensureAppDataAvailable();
  const view = app.currentView || 'dashboard';
  switch (view) {
    case 'dashboard':
      renderKpis();
      renderFixFirstGrid();
      renderIncomingDashboardBoard();
      renderVehicleTable();
      break;
    case 'workflow':
      renderWorkflowBoard();
      break;
    case 'parts':
      renderPartsHome();
      break;
    case 'rft':
      renderRftHome();
      break;
    case 'completed':
      renderCompletedVehicles();
      break;
    case 'lists':
      renderAdminLists();
      break;
    case 'import':
      renderReviewTable(false);
      renderScotSummary(false);
      renderAutocareResults(app.autocareScan);
      if (app.navisionImport) renderNavisionSummary(app.navisionImport);
      break;
    case 'schedule':
      renderScheduleBoard();
      break;
    case 'department':
      renderProductionDepartmentBoard();
      break;
    case 'pipeline':
      renderKanban();
      break;
    case 'visibility':
      renderOperationalVisibility();
      break;
    case 'tv':
      renderTvBoard();
      break;
    default:
      break;
  }
}




function navisionOrderType(vehicle) {
  return String(vehicle.navisionTransportPriority || vehicle.transportPriority || vehicle.salesType || vehicle.dealerCustomerCategory || '').toLowerCase();
}

function filteredVehiclesIgnoringQuickFilter() {
  const savedQuickFilter = app.quickFilter;
  const savedSubFilter = app.pmbSubFilter;
  app.quickFilter = '';
  app.pmbSubFilter = '';
  const rows = filteredVehicles();
  app.quickFilter = savedQuickFilter;
  app.pmbSubFilter = savedSubFilter;
  return rows;
}

function renderKpis() {
  const dashboardRows = filteredVehiclesIgnoringQuickFilter();
  const grid = $('#kpi-grid');
  if (!grid) return;
  const cards = STATUS_TAB_DEFS.map(def => {
    const value = dashboardRows.filter(matchesQuickFilter(def.key)).length;
    return { ...def, value };
  });
  grid.innerHTML = cards.map(card => {
    const active = app.quickFilter === card.key || (!app.quickFilter && card.key === 'batchmatched');
    return `
    <button class="kpi-card status-tab ${card.className} ${active ? 'active' : ''}" data-kpi-filter="${escapeHtml(card.key)}" type="button" aria-pressed="${active}">
      <span>${escapeHtml(card.label)}</span>
      <strong>${card.value}</strong>
      <small>${escapeHtml(card.sub)}</small>
    </button>
  `;
  }).join('');
  $$('[data-kpi-filter]').forEach(card => card.addEventListener('click', () => {
    applyQuickFilter(card.dataset.kpiFilter);
  }));
}

function isOpenThirdPartyVehicle(vehicle = {}) {
  const thirdPartyJobKeys = new Set(['tint', 'fabrication', 'electrical', 'pitInspection']);
  const hasOpenExternalJob = PDC_JOB_DEFS.some(def => thirdPartyJobKeys.has(def.key) && pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def));
  const hasOpenLegacySublet = vehicle.pdcRequiresSublet === true && vehicle.pdcCompleteSublet !== true;
  const stage = inferredPmbStage(vehicle);
  return hasOpenExternalJob || hasOpenLegacySublet || ['TINT', 'FABRICATION', 'ELECTRICAL', 'PIT_INSPECTION'].includes(stage);
}

function isWorkflowStagnant(vehicle = {}) {
  if (isActivePartsStoppage(vehicle) || isPdcBlocked(vehicle)) return true;
  if (statusCategory(vehicle) !== 'pmb') return false;
  const days = pmbStageAgeDays(vehicle);
  if (days === null) return false;
  return days > pmbLaneAgeLimit(inferredPmbStage(vehicle));
}

function operationalVisibilityMetrics(rows = []) {
  const pmbRows = rows.filter(vehicle => statusCategory(vehicle) === 'pmb');
  const rftGateIssues = vehiclesWithRftGateIssues(pmbRows);
  const stages = ['', ...PMB_STAGE_DEFS.map(def => def.value)];
  const capacityAlerts = stages.map(stage => {
    const vehicles = pmbRows.filter(vehicle => stage ? inferredPmbStage(vehicle) === stage : !inferredPmbStage(vehicle));
    return { stage, vehicles, metrics: pmbLaneMetrics(stage, vehicles) };
  }).filter(row => row.metrics.overLimit || row.metrics.atLimit || row.metrics.blockedCount || row.metrics.oldestStageDays > pmbLaneAgeLimit(row.stage));
  const openThirdPartyRows = rows.filter(isOpenThirdPartyVehicle);
  return {
    openThirdParty: openThirdPartyRows.length,
    assignedThirdParty: openThirdPartyRows.filter(vehicle => pmbBaySubletProvider(vehicle) || pmbBayMechanic(vehicle)).length,
    stagnant: rows.filter(isWorkflowStagnant).length,
    activeBlockers: rows.filter(vehicle => isPdcBlocked(vehicle) || isActivePartsStoppage(vehicle)).length,
    capacityAlerts: capacityAlerts.length,
    rftGateIssues: rftGateIssues.length,
    historyEvents: loadAuditLog().length,
    pmbRows: pmbRows.length,
  };
}

function renderOperationalVisibility() {
  const host = $('#operational-visibility-grid');
  if (!host) return;
  const rows = filteredVehiclesIgnoringQuickFilter();
  const metrics = operationalVisibilityMetrics(rows);
  const cards = [
    { label: 'External/specialist work', value: metrics.openThirdParty, detail: `${metrics.assignedThirdParty} assigned · tint / fabrication / electrical / pit inspection` },
    { label: 'Stagnation & blockers', value: metrics.stagnant, detail: `${metrics.activeBlockers} active blockers or Parts stoppages` },
    { label: 'Capacity alerts', value: metrics.capacityAlerts, detail: `${metrics.pmbRows} PMB vehicles checked against WIP and ageing limits` },
    { label: 'RFT gate issues', value: metrics.rftGateIssues, detail: 'Manual QC remains required before Ready for Transport' },
    { label: 'History events', value: metrics.historyEvents, detail: 'Local timestamped audit records for reporting review' },
  ];
  host.innerHTML = cards.map(card => `
    <article class="visibility-card">
      <span>${escapeHtml(card.label)}</span>
      <strong>${escapeHtml(card.value)}</strong>
      <small>${escapeHtml(card.detail)}</small>
    </article>
  `).join('');
}


function workflowVehiclesForStep(step = '') {
  const rows = app.data.filter(vehicleHasBatchNumber);
  switch (step) {
    case 'import': return rows.filter(vehicle => statusCategory(vehicle) === 'batchmatched');
    case 'arrival': return rows.filter(vehicle => statusCategory(vehicle) === 'prodtransit');
    case 'yardhold': return rows.filter(vehicle => statusCategory(vehicle) === 'yardhold');
    case 'parts': return rows.filter(vehicle => ['notordered', 'onorder', 'stoppage', 'miscacc'].includes(partsDepartmentStatus(vehicle)));
    case 'pmb': return rows.filter(vehicle => statusCategory(vehicle) === 'pmb');
    case 'rft': return rows.filter(vehicle => statusCategory(vehicle) === 'rft');
    default: return rows;
  }
}

function workflowPriorityRows() {
  const pmbRows = workflowVehiclesForStep('pmb');
  const issueRows = [];
  workflowVehiclesForStep('parts')
    .filter(vehicle => partsDepartmentStatus(vehicle) === 'stoppage')
    .forEach(vehicle => issueRows.push({ vehicle, label: 'Parts stoppage', severity: 'danger', detail: partsStoppageReason(vehicle) }));
  pmbRows
    .filter(isPdcBlocked)
    .forEach(vehicle => issueRows.push({ vehicle, label: 'PMB stoppage', severity: 'danger', detail: pdcBlockReason(vehicle) }));
  const seen = new Set();
  return issueRows.filter(row => {
    const key = `${vehicleKey(row.vehicle)}:${row.label}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 8);
}

function fixFirstRowsHtml(rows = [], emptyText = 'No urgent production exceptions right now.') {
  if (!rows.length) return `<div class="empty-state compact-empty fix-first-empty"><strong>Clear</strong><span>${escapeHtml(emptyText)}</span></div>`;
  const rowHtml = rows.map(row => {
    const vehicle = row.vehicle || {};
    const key = vehicleKey(vehicle);
    const identityHtml = vehicleIdentityStackHtml(vehicle);
    const client = vehicleCustomerName(vehicle) || 'Dealer Order';
    const unit = displayVehicle(vehicle) || 'Vehicle not listed';
    const stage = pmbStageLabel(inferredPmbStage(vehicle)) || pdcLocationLabel(vehiclePdcLocation(vehicle)) || incomingBucketLabel(incomingBucketForVehicle(vehicle));
    const severity = row.severity || 'warning';
    return `<button class="fix-first-row fix-first-${escapeHtml(severity)}" type="button" data-open-stock="${escapeHtml(key)}">
      <span class="fix-first-label">${escapeHtml(row.label || 'Action needed')}</span>
      ${identityHtml}
      <small>${escapeHtml(truncate(unit, 44))}</small>
      <em>${escapeHtml(truncate(row.detail || stage || 'Open vehicle for details', 72))}</em>
    </button>`;
  }).join('');
  return `${vehicleIdentityHeaderHtml('fix-first-identity-header')}${rowHtml}`;
}

function bindFixFirstRows(root = document) {
  $$('.fix-first-row[data-open-stock]', root).forEach(button => {
    if (button.dataset.fixFirstBound === 'true') return;
    button.dataset.fixFirstBound = 'true';
    button.addEventListener('click', () => openVehicleModal(button.dataset.openStock));
  });
}

function renderFixFirstGrid() {
  const host = $('#fix-first-grid');
  if (!host) return;
  const rows = workflowPriorityRows();
  host.innerHTML = `<details class="fix-first-list" open><summary>Show stoppages</summary><div class="fix-first-list-body">${fixFirstRowsHtml(rows)}</div></details>`;
  bindFixFirstRows(host);
}

function workflowBoardStats() {
  const pmbRows = workflowVehiclesForStep('pmb');
  const pmbBlocked = pmbRows.filter(isPdcBlocked).length;
  const gateIssues = vehiclesWithRftGateIssues(pmbRows).length;
  const unallocated = pmbRows.filter(vehicle => !inferredPmbStage(vehicle)).length;
  const stageSteps = [
    { value: '', filter: PMB_STAGE_UNASSIGNED_FILTER, number: '0', title: 'Unallocated', action: 'Open list' },
    ...PMB_STAGE_DEFS.map((def, index) => ({ value: def.value, filter: def.value, number: String(index + 1), title: def.label, action: 'Open bays' }))
  ];
  return {
    total: pmbRows.length,
    pmbBlocked,
    gateIssues,
    unallocated,
    steps: stageSteps.map(step => {
      const vehicles = step.value ? pmbRows.filter(vehicle => inferredPmbStage(vehicle) === step.value) : pmbRows.filter(vehicle => !inferredPmbStage(vehicle));
      const metrics = pmbLaneMetrics(step.value, vehicles);
      return {
        ...step,
        count: vehicles.length,
        detail: step.value ? `${vehicles.length} in queue · oldest ${metrics.oldestStageDays}d${metrics.blockedCount ? ` · blocked ${metrics.blockedCount}` : ''}` : 'Vehicles need a PMB category',
        rule: step.value ? 'Click to open the bay board for this PMB category.' : 'Assign these vehicles to the correct PMB category first.',
        target: step.filter,
        state: metrics.overLimit || metrics.blockedCount ? 'warning' : 'ready',
      };
    }),
  };
}

function workflowAction(target = '') {
  app.quickFilter = 'pmb';
  app.pmbSubFilter = normalizePmbSubFilter(target);
  app.activePmbBayStage = normalizePmbStage(target);
  showView('workflow');
  renderWorkflowBoard();
}

function renderWorkflowBoard() {
  const host = $('#workflow-board');
  if (!host) return;
  const activeStationStage = normalizePmbStage(app.activePmbBayStage);
  document.body.classList.toggle('pmb-station-mode', Boolean(activeStationStage));
  if (activeStationStage) {
    host.innerHTML = renderPmbBayBoardHtml(activeStationStage);
    bindPmbDragBoard(host);
    setupPmbScheduleClock();
    updateInlineSelectionBars();
    return;
  }
  const pmbRows = workflowVehiclesForStep('pmb');
  const search = workflowSearchValue();
  app.workflowSearch = search;
  const searchedRows = pmbRows.filter(vehicle => workflowVehicleMatchesSearch(vehicle, search));
  const unassignedRows = pmbRows.filter(vehicle => !inferredPmbStage(vehicle));
  const lanes = [
    { value: '', filter: PMB_STAGE_UNASSIGNED_FILTER, label: 'UNALLOCATED', className: 'pmb-branch-unassigned', hint: 'Needs bucket' },
    ...PMB_STAGE_DEFS.map(def => ({ ...def, filter: def.value, className: `pmb-branch-${def.value.toLowerCase()}`, hint: 'Open bays' }))
  ];
  const laneHtml = lanes.map(lane => {
    const allVehicles = lane.value
      ? pmbRows.filter(vehicle => inferredPmbStage(vehicle) === lane.value)
      : unassignedRows;
    const vehicles = search ? allVehicles.filter(vehicle => workflowVehicleMatchesSearch(vehicle, search)) : allVehicles;
    const active = app.pmbSubFilter === lane.filter || (lane.value && normalizePmbStage(app.activePmbBayStage) === lane.value);
    const metrics = pmbLaneMetrics(lane.value, allVehicles);
    const laneClasses = [
      active ? 'active' : '',
      lane.className,
      metrics.overLimit ? 'is-over-limit' : '',
      metrics.atLimit ? 'is-at-limit' : '',
      metrics.blockedCount ? 'has-blocked' : '',
    ].filter(Boolean).join(' ');
    const cards = vehicles.map(vehicle => lane.value
      ? pmbVehicleCardHtml(vehicle)
      : incomingVehicleDetailRow(vehicle, 'pmb', { draggable: true, hideDelete: true })
    ).join('') || `<div class="pmb-empty-drop">${search ? 'No matching vehicles here — bucket still accepts drops' : lane.value ? 'Drop vehicles here' : 'No unallocated PMB vehicles'}</div>`;
    const capacityLabel = lane.value ? pmbStageCapacityLabel(lane.value) : `${metrics.limitLabel} vehicle limit`;
    const countLabel = search ? `${vehicles.length}/${allVehicles.length}` : `${allVehicles.length}`;
    const hint = metrics.overLimit
      ? `OVER LIMIT ${allVehicles.length}/${metrics.limitLabel}`
      : `${capacityLabel} · ${allVehicles.length} in queue · oldest ${metrics.oldestStageDays}d${metrics.blockedCount ? ` · blocked ${metrics.blockedCount}` : ''}`;
    const openAttr = app.workflowBucketsCollapsed ? '' : ' open';
    const actions = lane.value
      ? `<button class="small-button" type="button" data-open-pmb-bays="${escapeHtml(lane.value)}" title="Open ${escapeHtml(lane.label)} bay line">Open bays</button>`
      : '';
    return `
      <details class="incoming-bucket workflow-stage-bucket pmb-drop-lane ${escapeHtml(laneClasses)}" data-pmb-drop-stage="${escapeHtml(lane.value)}" aria-label="${escapeHtml(lane.label)} PMB bucket"${openAttr}>
        <summary class="incoming-bucket-title workflow-bucket-title">
          <span>${escapeHtml(lane.label)}</span>
          <strong>${escapeHtml(countLabel)}</strong>
          <small>${escapeHtml(lane.value ? `${hint} · drop vehicles here or open bays` : `${hint} · drag these rows into a bucket`)}</small>
          <span class="workflow-bucket-actions">${actions}</span>
        </summary>
        <div class="incoming-bucket-list incoming-vertical-list workflow-vertical-list" data-pmb-drop-stage="${escapeHtml(lane.value)}">
          ${vehicles.length ? vehicleIdentityHeaderHtml('workflow-identity-header') : ''}
          ${cards}
        </div>
      </details>`;
  }).join('');
  const summaryText = search
    ? `${searchedRows.length} of ${pmbRows.length} PMB vehicles match “${search}” · all buckets stay visible for dragging`
    : `${pmbRows.length} PMB vehicles · ${unassignedRows.length} unallocated`;
  const priorityRows = workflowPriorityRows();
  const priorityHtml = `<section class="workflow-fix-first-strip"><div class="branch-header workflow-pmb-header"><div><strong>Fix First</strong><span>Only vehicles with a PMB stoppage or Parts stoppage.</span></div><div class="branch-header-actions"><span class="badge neutral">${priorityRows.length} item${priorityRows.length === 1 ? '' : 's'}</span></div></div><details class="fix-first-list workflow-fix-first-list" open><summary>Show stoppages</summary><div class="fix-first-list-body">${fixFirstRowsHtml(priorityRows, 'No PMB exceptions need action right now.')}</div></details></section>`;
  host.innerHTML = `
    ${priorityHtml}
    <div class="branch-header workflow-pmb-header">
      <div><strong>PMB control board</strong><span>Unallocated vehicles are full rows like the main screen. Drag vehicles into TINT, HOIST, FITTING, FAB, ELEC, TYRE or PIT; use Open bays for numbered bay scheduling.</span></div>
      <div class="branch-header-actions"><span class="badge neutral">${escapeHtml(summaryText)}</span></div>
    </div>
    <div class="workflow-collapsible-board" data-pmb-board>${laneHtml}</div>
  `;
  bindPmbDragBoard(host);
  bindFixFirstRows(host);
  updateInlineSelectionBars(search ? searchedRows : pmbRows);
}

function incomingBucketForVehicle(vehicle = {}) {
  const category = statusCategory(vehicle);
  const status = normalizeToyotaStatus(navisionStatusText(vehicle));
  if (category === 'completed') return 'completed';
  if (category === 'rft') return 'rft';
  if (category === 'pmb') return 'pmb';
  if (category === 'yardhold') return 'yardhold';
  if (category === 'prodtransit') return 'transit';
  return 'overseas';
}

function incomingBucketLabel(bucketKey = '') {
  return ({ completed: 'Completed vehicles', rft: 'RFT', pmb: 'PMB', yardhold: 'Yard Hold', transit: 'In Transit', overseas: 'Overseas / Other' })[bucketKey] || bucketKey || 'Other';
}

function incomingSearchText(vehicle = {}, bucketKey = '') {
  return [
    displayStockNumber(vehicle), vehicle.stock, vehicle.batch, vehicle.order, vehicle.toyotaOrder, vehicle.salesOrder,
    vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle), vehicle.rego, vehicle.registration, vehicle.client, vehicle.toyotaCustomer,
    vehicle.vehicle, vehicle.toyotaVehicle, displayVehicle(vehicle), navisionStatusText(vehicle), incomingBucketLabel(bucketKey),
    vehicle.consultant, vehicle.salesperson, vehicle.salesPerson, vehicle.owner, vehicle.navisionNotes, vehicle.dealerComments,
    vehicle.notes, vehicle.keyNumber, vehicle.keyNo, vehicle.pmbKeyNumber, vehicle.vehicleKeyNumber, vehicle.pdcJobcard, vehicle.jobcard, vehicle.jobCardNumber,
  ].filter(Boolean).join(' ').toLowerCase();
}

function incomingWorkFilterValues() {
  return $$('input[name="incoming-work-filter"]')
    .filter(input => input.checked)
    .map(input => String(input.value || '').trim().toLowerCase())
    .filter(Boolean);
}

function incomingDashboardFilterValues() {
  return {
    search: String($('#incoming-search')?.value || '').trim().toLowerCase(),
    status: String($('#incoming-status-filter')?.value || '').trim(),
    bucket: String($('#incoming-bucket-filter')?.value || '').trim(),
    rep: String($('#incoming-rep-filter')?.value || '').trim(),
    work: incomingWorkFilterValues(),
  };
}

function incomingWorkFilterMatches(vehicle = {}, workKey = '') {
  const key = String(workKey || '').trim().toLowerCase();
  if (!key) return true;
  const def = PDC_JOB_BY_KEY.get(key);
  if (!def) return true;
  return pdcJobRequired(vehicle, def) || pdcJobComplete(vehicle, def);
}

function incomingVehicleMatchesFilters(vehicle = {}, filters = incomingDashboardFilterValues()) {
  const bucket = incomingBucketForVehicle(vehicle);
  if (!bucket) return false;
  const status = navisionStatusText(vehicle) || pdcLocationLabel(vehiclePdcLocation(vehicle)) || '';
  const rep = consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || '';
  if (filters.bucket && bucket !== filters.bucket) return false;
  if (filters.status && status !== filters.status) return false;
  if (filters.rep && rep !== filters.rep) return false;
  const workFilters = Array.isArray(filters.work) ? filters.work : (filters.work ? [filters.work] : []);
  if (workFilters.length && !workFilters.some(work => incomingWorkFilterMatches(vehicle, work))) return false;
  if (filters.search && !incomingSearchText(vehicle, bucket).includes(filters.search)) return false;
  return true;
}

function setSelectOptions(select, options = [], placeholder = 'All') {
  if (!select) return;
  const current = select.value;
  select.innerHTML = `<option value="">${escapeHtml(placeholder)}</option>` + options
    .filter(Boolean)
    .sort((a, b) => String(a).localeCompare(String(b), undefined, { sensitivity: 'base' }))
    .map(value => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`)
    .join('');
  if (options.includes(current)) select.value = current;
}

function updateIncomingDashboardFilterOptions(rows = []) {
  const statuses = [...new Set(rows.map(vehicle => navisionStatusText(vehicle) || pdcLocationLabel(vehiclePdcLocation(vehicle)) || '').filter(Boolean))];
  const reps = [...new Set(rows.map(vehicle => consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || '').filter(Boolean))];
  setSelectOptions($('#incoming-status-filter'), statuses, 'All statuses');
  setSelectOptions($('#incoming-rep-filter'), reps, 'All reps');
}

function collapseDetailsWithin(host) {
  if (!host) return;
  $$('details', host).forEach(row => { row.open = false; });
}

function collapseMainScreenRows() {
  collapseDetailsWithin($('#incoming-main-board'));
}

function collapseWorkflowRows() {
  app.workflowBucketsCollapsed = true;
  if (normalizePmbStage(app.activePmbBayStage) || app.pmbSubFilter) {
    app.activePmbBayStage = '';
    app.pmbSubFilter = '';
    document.body.classList.remove('pmb-station-mode');
    showView('workflow');
    renderWorkflowBoard();
  }
  renderWorkflowBoard();
  collapseDetailsWithin($('#workflow-board'));
}

function clearIncomingDashboardFilters() {
  ['#incoming-search', '#incoming-status-filter', '#incoming-bucket-filter', '#incoming-rep-filter'].forEach(selector => {
    const input = $(selector);
    if (input) input.value = '';
  });
  $$('input[name="incoming-work-filter"]').forEach(input => { input.checked = false; });
  renderIncomingDashboardBoard();
}

function workflowSearchText(vehicle = {}) {
  return incomingSearchText(vehicle, 'pmb');
}

function workflowVehicleMatchesSearch(vehicle = {}, search = '') {
  const needle = String(search || '').trim().toLowerCase();
  if (!needle) return true;
  return workflowSearchText(vehicle).includes(needle);
}

function workflowSearchValue() {
  return String($('#workflow-search')?.value || app.workflowSearch || '').trim().toLowerCase();
}

function clearWorkflowSearch() {
  app.workflowSearch = '';
  const input = $('#workflow-search');
  if (input) input.value = '';
  renderWorkflowBoard();
}

function pmbRequiredWorkLabels(vehicle = {}) {
  return pdcRequirementDefinitions(vehicle).map(item => `${item.label}${pdcJobComplete(vehicle, item) ? ' done' : ' required'}`);
}

function incomingWorkChecklistHtml(vehicle = {}) {
  return `<div class="incoming-work-checks" aria-label="Required work checklist">${PDC_JOB_DEFS.map(def => {
    const required = pdcJobRequired(vehicle, def);
    const complete = required && pdcJobComplete(vehicle, def);
    const classes = ['incoming-work-check'];
    if (required) classes.push('is-required');
    if (complete) classes.push('is-complete');
    return `<span class="${classes.join(' ')}" title="${escapeHtml(required ? pdcJobCompletionTitle(vehicle, def) : `${def.label} not required`)}">
      <span class="incoming-work-box" aria-hidden="true">${complete ? '✓' : required ? '•' : ''}</span>
      <span>${escapeHtml(def.label)}</span>
    </span>`;
  }).join('')}</div>`;
}

function incomingVehicleDetailRow(vehicle = {}, bucketKey = '', options = {}) {
  const key = vehicleKey(vehicle);
  const eta = locationAgeLabel(vehicle);
  const stock = displayStockNumber(vehicle) || vehicleKey(vehicle) || 'No stock';
  const customer = vehicleCustomerName(vehicle) || 'Unknown customer';
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const consultant = consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || '—';

  const keyNo = vehicleKeyNumber(vehicle) || '—';
  const rego = vehicle.rego || vehicle.registration || '—';
  const vin = vehicle.vin || vehicle.VIN || vehicle.chassis || vehicle.chassisNo || '—';
  const age = pmbAgeLabel(vehicle);
  const workChecks = incomingWorkChecklistHtml(vehicle);
  const required = pmbRequiredWorkLabels(vehicle).join(', ') || 'No PMB work flagged';
  const gateIssues = bucketKey === 'pmb' ? vehiclesWithRftGateIssues([vehicle]).flatMap(row => row.issues || []) : [];
  const primaryAction = bucketKey === 'yardhold'
    ? `<button class="primary incoming-transfer-pmb" type="button" data-yh-transfer-pmb="${escapeHtml(key)}">Transfer YH → PMB</button>`
    : bucketKey === 'pmb'
      ? `<button class="primary incoming-transfer-rft" type="button" data-transfer-rft-stock="${escapeHtml(key)}" ${gateIssues.length ? 'disabled' : ''} title="${escapeHtml(gateIssues.length ? `RFT locked: ${gateIssues.join(' | ')}` : 'Transfer PMB vehicle to RFT')}">Transfer to RFT</button><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`
      : bucketKey === 'rft'
        ? `<label class="rft-collected-check incoming-collected-check" title="Tick once the vehicle has been collected"><input type="checkbox" data-rft-collected-key="${escapeHtml(key)}" /> <span>Collected</span></label><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`
        : `<button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`;
  const deleteAction = options.hideDelete ? '' : `<button class="small-button incoming-delete-button" type="button" data-incoming-delete="${escapeHtml(key)}" title="Delete this vehicle from the main screen">Delete</button>`;
  const identitySummary = vehicleIdentityStackHtml(vehicle, { className: 'incoming-identity' });
  const keyBadge = keyNo && keyNo !== '—' ? `<small>Key ${escapeHtml(keyNo)}</small>` : '';
  const selectBox = `<label class="incoming-card-select" title="Select ${escapeHtml(stock)}"><input type="checkbox" data-select-stock="${escapeHtml(key)}" ${app.selectedRows.has(key) ? 'checked' : ''} /><span aria-hidden="true"></span></label>`;
  const dragAttrs = options.draggable ? ` draggable="true" data-pmb-drag-key="${escapeHtml(key)}"` : '';
  const dragClass = options.draggable ? ' workflow-draggable-row' : '';
  return `
    <details class="incoming-vehicle-card incoming-${escapeHtml(bucketKey)}-row${dragClass} ${app.selectedRows.has(key) ? 'is-selected' : ''}" data-incoming-row="${escapeHtml(key)}"${dragAttrs}>
      <summary class="incoming-vehicle-summary">
        ${selectBox}
        <span class="incoming-card-stock">${identitySummary}</span>
        <span class="incoming-card-main">
          <strong>${escapeHtml(truncate(unit, 72))}</strong>
          <small>${escapeHtml(truncate(customer, 46))}</small>
        </span>
        <span class="incoming-card-work-wrap">${workChecks}</span>
        <span class="incoming-card-meta incoming-card-age ${escapeHtml('pmb-age-' + onSiteDaysClass(vehicle))}"><b>${bucketKey === 'pmb' ? 'PMB' : bucketKey === 'yardhold' ? 'YH' : 'ETA'}</b>${escapeHtml(eta)}</span>
        <span class="incoming-card-action">${primaryAction}${deleteAction}</span>
      </summary>
      <div class="incoming-vehicle-detail-grid">

        <div><b>Rego</b><span>${escapeHtml(rego)}</span></div>
        <div><b>VIN / Chassis</b><span>${escapeHtml(vin)}</span></div>
        <div><b>Sales rep</b><span>${escapeHtml(consultant)}</span></div>
        <div><b>Age</b><span>${escapeHtml(age)}</span></div>
        <div><b>Bucket</b><span>${escapeHtml(incomingBucketLabel(bucketKey))}</span></div>
        <div class="wide"><b>PMB work required</b><span>${escapeHtml(required)}</span></div>
      </div>
    </details>`;
}

function renderIncomingDashboardBoard() {
  const host = $('#incoming-main-board');
  if (!host) return;
  const rows = app.data.filter(vehicle => incomingBucketForVehicle(vehicle) && !vehicleCollectedFromRft(vehicle));
  updateIncomingDashboardFilterOptions(rows);
  const filters = incomingDashboardFilterValues();
  const filteredRows = rows.filter(vehicle => incomingVehicleMatchesFilters(vehicle, filters));
  const summary = $('#incoming-filter-summary');
  if (summary) {
    const active = [filters.search && `search “${filters.search}”`, filters.status, filters.bucket && incomingBucketLabel(filters.bucket), filters.rep].filter(Boolean);
    summary.textContent = `${filteredRows.length} of ${rows.length} vehicles shown${active.length ? ` · ${active.join(' · ')}` : ''}`;
  }
  const defs = [
    { key: 'rft', label: 'RFT', hint: 'Vehicles ready for transport', open: false },
    { key: 'pmb', label: 'PMB', hint: 'Vehicles currently at PMB', open: false },
    { key: 'yardhold', label: 'Yard Hold', hint: 'Yard Hold vehicles — release to PMB from here', open: false },
    { key: 'transit', label: 'In Transit', hint: 'Wharf, shipment and WA transit', open: false },
    { key: 'overseas', label: 'Overseas / Other', hint: 'All other non-RFT vehicles not yet in transit/YH/PMB', open: false },
  ];
  host.innerHTML = defs.map(def => {
    if (filters.bucket && filters.bucket !== def.key) return '';
    const vehicles = filteredRows.filter(vehicle => incomingBucketForVehicle(vehicle) === def.key)
      .sort((a, b) => (parseDateAU(navisionEtaForVehicle(a))?.getTime() || 9999999999999) - (parseDateAU(navisionEtaForVehicle(b))?.getTime() || 9999999999999));
    const shown = vehicles.map(vehicle => incomingVehicleDetailRow(vehicle, def.key)).join('') || '<div class="pmb-empty-drop">No vehicles match the current filters</div>';
    const identityHeader = vehicles.length ? vehicleIdentityHeaderHtml('incoming-board-identity-header') : '';
    return `<details class="incoming-bucket incoming-${escapeHtml(def.key)}" ${def.open ? 'open' : ''}>
      <summary class="incoming-bucket-title">
        <span>${escapeHtml(def.label)}</span><strong>${vehicles.length}</strong><small>${escapeHtml(def.hint)}</small>
      </summary>
      <div class="incoming-bucket-list incoming-vertical-list">${identityHeader}${shown}</div>
    </details>`;
  }).join('');
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    openVehicleModal(button.dataset.openStock);
  }));
  $$('[data-incoming-delete]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    deleteIncomingVehicleFromMain(button.dataset.incomingDelete);
  }));
  $$('[data-yh-transfer-pmb]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    transferYhVehicleToPmb(button.dataset.yhTransferPmb);
  }));
  $$('[data-transfer-rft-stock]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    transferVehicleToRftFromCard(button.dataset.transferRftStock);
  }));
  bindRftCollectedInputs(host);
  bindIncomingCardSelection(host);
  updateInlineSelectionBars(filteredRows);
}

function bindIncomingCardSelection(host = document) {
  $$('[data-select-stock]', host).forEach(input => input.addEventListener('click', event => event.stopPropagation()));
  $$('[data-select-stock]', host).forEach(input => input.addEventListener('change', event => {
    const key = input.dataset.selectStock;
    if (!key) return;
    if (input.checked) app.selectedRows.add(key);
    else app.selectedRows.delete(key);
    const card = input.closest('.incoming-vehicle-card');
    if (card) card.classList.toggle('is-selected', input.checked);
    updateInlineSelectionBars();
    updateBulkSelectionPanel();
  }));
}

function updateInlineSelectionBars(visibleRows = []) {
  const validKeys = new Set(app.data.map(vehicleKey));
  [...app.selectedRows].forEach(key => { if (!validKeys.has(key)) app.selectedRows.delete(key); });
  const selected = selectedVehiclesForBulkEmail();
  const count = selected.length;
  const incomingPmbReadyCount = selected.filter(canTransferVehicleToPmb).length;
  const pmbCount = selected.filter(vehicle => statusCategory(vehicle) === 'pmb').length;
  const gateIssueRows = vehiclesWithRftGateIssues(selected);
  ['incoming-selection-bar', 'workflow-selection-bar'].forEach(id => {
    const bar = $(`#${id}`);
    if (bar) bar.classList.toggle('active', count > 0);
  });
  const incomingCount = $('#incoming-selection-count');
  if (incomingCount) incomingCount.textContent = `${count} selected`;
  const workflowCount = $('#workflow-selection-count');
  if (workflowCount) workflowCount.textContent = `${count} selected`;
  const incomingTransfer = $('#incoming-transfer-selected-pmb');
  if (incomingTransfer) {
    incomingTransfer.disabled = !(count > 0 && incomingPmbReadyCount === count);
    incomingTransfer.title = !count ? 'Select one or more Yard Hold or In Transit vehicles first' : incomingPmbReadyCount === count ? `Transfer ${count} selected Yard Hold/In Transit vehicle${count === 1 ? '' : 's'} to PMB` : 'Only Yard Hold or In Transit vehicles can be transferred to PMB';
  }
  const workflowTransfer = $('#workflow-transfer-selected-rft');
  if (workflowTransfer) {
    workflowTransfer.disabled = !(count > 0 && pmbCount === count && gateIssueRows.length === 0);
    workflowTransfer.title = !count ? 'Select one or more PMB vehicles first' : pmbCount !== count ? 'Only PMB vehicles can transfer to RFT' : gateIssueRows.length ? 'RFT locked: all required boxes must be signed off first' : `Transfer ${count} selected PMB vehicle${count === 1 ? '' : 's'} to RFT`;
  }
  ['incoming-delete-selected', 'workflow-delete-selected', 'incoming-clear-selected', 'workflow-clear-selected'].forEach(id => {
    const button = $(`#${id}`);
    if (button) button.disabled = count === 0;
  });
}

async function transferSelectedMainYhVehiclesToPmb() {
  const selected = selectedVehiclesForBulkEmail();
  if (!selected.length) return;
  const notYh = selected.filter(vehicle => !canTransferVehicleToPmb(vehicle));
  if (notYh.length) {
    window.alert('Only Yard Hold or In Transit vehicles can be transferred to PMB from the main screen. Untick any PMB, RFT, completed or overseas rows first.');
    return;
  }
  await transferVehiclesToPmb(selected);
  updateInlineSelectionBars();
}

function deleteIncomingVehicleFromMain(key = '') {
  const vehicle = app.data.find(row => vehicleKey(row) === key || row.stock === key || row.order === key || row.id === key);
  if (!vehicle) return;
  const label = `${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`;
  if (!window.confirm(`Delete this vehicle from the main screen?\n\n${label}\n\nThis hides it from this browser's tracker and keeps the delete in local storage.`)) return;
  removeVehiclesFromTracker([vehicle]);
  refreshAfterVehicleRemoval();
}

function updateDashboardNavisionPasteButtons() {
  const hasText = Boolean(($('#dashboard-navision-paste')?.value || '').trim());
  const importButton = $('#dashboard-import-navision');
  const clearButton = $('#dashboard-clear-navision');
  if (importButton) importButton.disabled = !hasText;
  if (clearButton) clearButton.disabled = !hasText;
}

function clearDashboardNavisionPaste() {
  const input = $('#dashboard-navision-paste');
  if (input) input.value = '';
  updateDashboardNavisionPasteButtons();
}

function importDashboardNavisionPaste() {
  const source = $('#dashboard-navision-paste');
  const text = source?.value || '';
  if (!text.trim()) return;
  const target = $('#navision-paste');
  if (target) target.value = text;
  const pmbOnly = $('#navision-pmb-only');
  if (pmbOnly) pmbOnly.checked = false;
  showView('import');
  updateNavisionImportButton();
  importNavisionVehicles();
}

function updateDashboardPdImportButtons() {
  const hasText = Boolean(($('#dashboard-pd-paste')?.value || '').trim());
  const hasFiles = Boolean(app.dashboardPdFiles && app.dashboardPdFiles.length);
  const importButton = $('#dashboard-import-pd');
  const clearButton = $('#dashboard-clear-pd');
  if (importButton) importButton.disabled = !(hasText || hasFiles);
  if (clearButton) clearButton.disabled = !(hasText || hasFiles);
}

function setDashboardPdStatus(results = []) {
  const host = $('#dashboard-pd-status');
  if (!host) return;
  host.innerHTML = results.map(result => `<div class="po-status-row ${result.ok ? 'ok' : 'warn'}"><strong>${escapeHtml(result.title || 'PD import')}</strong><span>${escapeHtml(result.message || '')}</span></div>`).join('');
}

function clearDashboardPdImport() {
  app.dashboardPdFiles = [];
  const upload = $('#dashboard-pd-upload');
  const paste = $('#dashboard-pd-paste');
  if (upload) upload.value = '';
  if (paste) paste.value = '';
  setDashboardPdStatus([]);
  updateDashboardPdImportButtons();
}

function handleDashboardPdFileSelect(event) {
  app.dashboardPdFiles = [...(event.target.files || [])];
  setDashboardPdStatus(app.dashboardPdFiles.length ? [{ ok: true, title: `${app.dashboardPdFiles.length} PD file${app.dashboardPdFiles.length === 1 ? '' : 's'} ready`, message: 'Click Import PD work to attach the work list.' }] : []);
  updateDashboardPdImportButtons();
}

function bindDashboardPdDropZone() {
  const zone = $('#dashboard-pd-drop');
  if (!zone) return;
  ['dragenter', 'dragover'].forEach(type => zone.addEventListener(type, event => {
    event.preventDefault();
    zone.classList.add('is-dragover');
  }));
  ['dragleave', 'drop'].forEach(type => zone.addEventListener(type, event => {
    event.preventDefault();
    zone.classList.remove('is-dragover');
  }));
  zone.addEventListener('drop', event => {
    app.dashboardPdFiles = [...(event.dataTransfer?.files || [])];
    setDashboardPdStatus(app.dashboardPdFiles.length ? [{ ok: true, title: `${app.dashboardPdFiles.length} PD file${app.dashboardPdFiles.length === 1 ? '' : 's'} ready`, message: 'Click Import PD work to attach the work list.' }] : []);
    updateDashboardPdImportButtons();
  });
}

function parsePdCheckFormText(text = '', filenames = []) {
  const source = `${String(text || '')}\n${(filenames || []).join('\n')}`;
  const squashed = source.replace(/\s+/g, ' ').trim();
  const stock = (squashed.match(/\bstock\s*(?:no\.?|number|#)?\s*[:#-]?\s*(\d{6,8})\b/i) || squashed.match(/\b(\d{8})\b/) || [])[1] || '';
  const order = (squashed.match(/\border\s*(?:no\.?|number|#)?\s*[:#-]?\s*(\d{4,8})\b/i) || squashed.match(/\bpd\s*document\s*(\d{4,8})\b/i) || [])[1] || '';
  const vin = (squashed.match(/\b[A-HJ-NPR-Z0-9]{17}\b/i) || [''])[0].toUpperCase();
  const itemPatterns = [
    ['Bull bar', /bull\s*bar|bullbar/i],
    ['Light bar', /light\s*bar|lightbar|spot\s*light|spotlight/i],
    ['Tray body', /tray\s*body|steel\s*tray|alloy\s*tray|\btray\b/i],
    ['Seat covers', /seat\s*covers?/i],
    ['Tow bar', /tow\s*bar|towbar/i],
    ['Rear rack', /rear\s*rack/i],
    ['Long range tank', /long\s*range\s*(?:fuel\s*)?tank/i],
    ['Ladder rack', /ladder\s*rack/i],
    ['Roof rack', /roof\s*rack/i],
    ['Window tint', /window\s*tint|\btint\b/i],
    ['UHF / radio', /\buhf\b|radio|antenna/i],
    ['Dual battery / 12V', /dual\s*battery|\b12v\b|dcdc|dc\s*dc|redarc|anderson/i],
    ['Canopy', /canopy/i],
    ['Tyre / wheel upgrade', /tyre|tire|wheel\s*upgrade|sunraysia|ko2|ko3/i],
    ['GVM upgrade', /\bgvm\b/i],
    ['Winch', /winch/i],
  ];
  const tasks = itemPatterns.filter(([, pattern]) => pattern.test(squashed)).map(([label]) => label);
  return { stock, order, vin, tasks: [...new Set(tasks)], filenames };
}

function findVehicleForPd(parsed = {}) {
  const stock = String(parsed.stock || '').trim();
  const order = String(parsed.order || '').trim();
  const vin = String(parsed.vin || '').trim().toLowerCase();
  return app.data.find(vehicle =>
    (stock && String(vehicle.stock || '') === stock) ||
    (order && [vehicle.order, vehicle.toyotaOrder, vehicle.salesOrder].some(value => String(value || '') === order)) ||
    (vin && [vehicle.vin, vehicle.autocareVin].some(value => String(value || '').toLowerCase() === vin))
  ) || null;
}

function ensureVehicleForPd(parsed = {}) {
  const found = findVehicleForPd(parsed);
  if (found) return found;
  const stock = parsed.stock || (parsed.order ? `PD-${parsed.order}` : `PD-${Date.now().toString().slice(-6)}`);
  const vehicle = {
    id: `pd-${stock}`,
    sourceRow: '',
    stock,
    client: 'Customer from PD check-form',
    internalStatus: '',
    deliveryDate: '',
    vehicle: '',
    financeNote: '',
    group: 'PD check-form upload',
    source: 'PD check-form',
    order: parsed.order || '',
    toyotaCustomer: '',
    contact: '',
    toyotaVehicle: '',
    suffix: '',
    colour: '',
    trim: '',
    origMth: '',
    prodMth: '',
    compPlate: '',
    arrivalPort: '',
    toyotaStatus: '',
    etaAtDealer: '',
    epodReceipt: '',
    jitQty: '',
    jitaPartsOrdered: 'Unknown',
    consultant: '',
    poTasks: [],
    poFiles: [],
  };
  const added = loadAddedVehicles();
  added.unshift(vehicle);
  saveAddedVehicles(added);
  app.data.unshift(vehicle);
  return vehicle;
}

function pdFlagsFromTasks(tasks = []) {
  const text = tasks.join(' ').toLowerCase();
  return {
    buildPoRaised: Boolean(tasks.length),
    pdcRequiresTint: /tint/.test(text),
    pdcRequiresHoist: /hoist|suspension|gvm|lift|tow/.test(text),
    pdcRequiresFitting: /\bfit\b|fitment|fitting|pdi|accessor|bullbar|towbar|canopy|tray/.test(text),
    pdcRequiresFabrication: /tray|bar|rack|tank|canopy|winch|gvm|fabricat/.test(text),
    pdcRequiresElectrical: /light|uhf|radio|12v|battery|redarc|anderson|electrical|auto.?elec/.test(text),
    pdcRequiresTyre: /tyre|tire|wheel/.test(text),
  };
}

function applyPdCheckFormImport(parsed = {}) {
  const vehicle = ensureVehicleForPd(parsed);
  const key = vehicleKey(vehicle);
  const taskStore = loadPoTasks();
  const fileStore = loadPoFiles();
  const currentTasks = taskStore[key] || taskStore[vehicle.stock] || vehicle.poTasks || [];
  const importedTasks = (parsed.tasks || []).map(task => `PD check-form: ${task}`);
  const combinedTasks = [...new Set(currentTasks.concat(importedTasks))];
  taskStore[key] = combinedTasks;
  const currentFiles = fileStore[key] || fileStore[vehicle.stock] || vehicle.poFiles || [];
  const combinedFiles = [...new Set(currentFiles.concat(parsed.filenames || []))];
  fileStore[key] = combinedFiles;
  savePoTasks(taskStore);
  savePoFiles(fileStore);
  const updates = { ...pdFlagsFromTasks(combinedTasks) };
  if (parsed.order && !vehicle.order) updates.order = parsed.order;
  saveVehicleEdits(key, updates);
  return { vehicle, taskCount: importedTasks.length, totalTasks: combinedTasks.length };
}

async function importDashboardPdWork() {
  const files = app.dashboardPdFiles || [];
  const pastedText = ($('#dashboard-pd-paste')?.value || '').trim();
  const results = [];
  const texts = [];
  for (const file of files) {
    try {
      const isPdf = /\.pdf$/i.test(file.name) || file.type === 'application/pdf';
      const text = isPdf ? await extractTextFromPdfFile(file) : await file.text();
      texts.push({ text, filenames: [file.name] });
    } catch (error) {
      results.push({ ok: false, title: file.name, message: error.message || String(error) });
    }
  }
  if (pastedText) texts.push({ text: pastedText, filenames: ['pasted PD text'] });
  texts.forEach(item => {
    const parsed = parsePdCheckFormText(item.text, item.filenames);
    if (!parsed.stock && !parsed.order && !parsed.vin) {
      results.push({ ok: false, title: item.filenames.join(', '), message: 'No stock, order or VIN found.' });
      return;
    }
    if (!parsed.tasks.length) {
      results.push({ ok: false, title: parsed.stock || parsed.order || parsed.vin, message: 'Vehicle found, but no accessory / fitting work items were detected.' });
      return;
    }
    const applied = applyPdCheckFormImport(parsed);
    results.push({ ok: true, title: displayStockNumber(applied.vehicle) || parsed.order || parsed.vin, message: `${applied.taskCount} PD work item${applied.taskCount === 1 ? '' : 's'} imported; ${applied.totalTasks} total attached.` });
  });
  app.data = buildVehicleData();
  renderAll();
  setDashboardPdStatus(results.length ? results : [{ ok: false, title: 'PD import', message: 'Add a PD PDF or paste PD text first.' }]);
  updateDashboardPdImportButtons();
}

function renderPmbBranchTiles() {
  const host = $('#pmb-branch-grid');
  if (!host) return;
  const vehicleTable = $('#vehicle-table');
  const trackerPanel = typeof vehicleTable?.closest === 'function' ? vehicleTable.closest('.panel') : null;
  const showPmbBuckets = app.quickFilter === 'pmb';
  if (trackerPanel) trackerPanel.hidden = showPmbBuckets || trackerPanel.classList.contains('legacy-incoming-table-panel');
  if (!showPmbBuckets) {
    host.hidden = true;
    host.innerHTML = '';
    app.activePmbBayStage = '';
    document.body.classList.remove('pmb-station-mode');
    setupPmbScheduleClock();
    return;
  }
  host.hidden = false;
  const activeStationStage = normalizePmbStage(app.activePmbBayStage);
  document.body.classList.toggle('pmb-station-mode', Boolean(activeStationStage));
  host.classList.toggle('station-only', Boolean(activeStationStage));
  if (activeStationStage) {
    host.innerHTML = renderPmbBayBoardHtml(activeStationStage);
    bindPmbDragBoard(host);
    setupPmbScheduleClock();
    updateInlineSelectionBars();
    return;
  }
  const pmbRows = filteredPmbVehiclesIgnoringSubFilter();
  const unassignedRows = pmbRows.filter(vehicle => !inferredPmbStage(vehicle));
  const lanes = [
    { value: '', filter: PMB_STAGE_UNASSIGNED_FILTER, label: 'UNALLOCATED', className: 'pmb-branch-unassigned', hint: 'Needs bucket' },
    ...PMB_STAGE_DEFS.map(def => ({ ...def, filter: def.value, className: `pmb-branch-${def.value.toLowerCase()}`, hint: 'Open bays' }))
  ];

  const laneHtml = lanes.map(lane => {
    const vehicles = lane.value
      ? pmbRows.filter(vehicle => inferredPmbStage(vehicle) === lane.value)
      : unassignedRows;
    const active = app.pmbSubFilter === lane.filter || (lane.value && normalizePmbStage(app.activePmbBayStage) === lane.value);
    const metrics = pmbLaneMetrics(lane.value, vehicles);
    const laneClasses = [
      active ? 'active' : '',
      lane.className,
      metrics.overLimit ? 'is-over-limit' : '',
      metrics.atLimit ? 'is-at-limit' : '',
      metrics.blockedCount ? 'has-blocked' : '',
    ].filter(Boolean).join(' ');
    const cards = vehicles.map(pmbVehicleCardHtml).join('') || `<div class="pmb-empty-drop">${lane.value ? 'Drop vehicles here' : 'No unallocated PMB vehicles'}</div>`;
    const capacityLabel = lane.value ? pmbStageCapacityLabel(lane.value) : `${metrics.limitLabel} vehicle limit`;
    const hint = metrics.overLimit
      ? `OVER LIMIT ${vehicles.length}/${metrics.limitLabel}`
      : `${capacityLabel} · ${vehicles.length} in queue · oldest ${metrics.oldestStageDays}d${metrics.blockedCount ? ` · blocked ${metrics.blockedCount}` : ''}`;
    const titleAttrs = lane.value
      ? `data-open-pmb-bays="${escapeHtml(lane.value)}" title="Open ${escapeHtml(lane.label)} bays"`
      : `data-pmb-sub-filter="${escapeHtml(lane.filter)}" title="Show unallocated PMB vehicles"`;
    return `
      <section class="pmb-drop-lane ${escapeHtml(laneClasses)}" data-pmb-drop-stage="${escapeHtml(lane.value)}" aria-label="${escapeHtml(lane.label)} PMB bucket">
        <button class="pmb-lane-title" type="button" ${titleAttrs} aria-pressed="${active}">
          <span>${escapeHtml(lane.label)}</span>
          <strong>${vehicles.length}</strong>
          <small>${escapeHtml(lane.value ? `${hint} · click for bay line` : hint)}</small>
        </button>
        <div class="pmb-lane-dropzone" data-pmb-drop-stage="${escapeHtml(lane.value)}">
          ${cards}
        </div>
      </section>`;
  }).join('');

  const allActive = !app.pmbSubFilter;
  host.innerHTML = `
    <div class="branch-header">
      <div><strong>PMB control board</strong><span>All PMB vehicles land in UNALLOCATED first. Drag into TINT, HOIST, FITTING, FAB, ELEC, TYRE or PIT when that department is ready.</span></div>
      <div class="branch-header-actions">
        <button class="small-button ${allActive ? 'active-lite' : ''}" type="button" data-pmb-sub-filter="">Show all PMB (${pmbRows.length})</button>
        <button class="small-button ${app.pmbSubFilter === PMB_STAGE_UNASSIGNED_FILTER ? 'active-lite' : ''}" type="button" data-pmb-sub-filter="${PMB_STAGE_UNASSIGNED_FILTER}">UNALLOCATED (${unassignedRows.length})</button>
      </div>
    </div>
    <div class="pmb-drop-board" data-pmb-board>${laneHtml}</div>
    ${renderPmbBayBoardHtml(app.activePmbBayStage)}
  `;
  bindPmbDragBoard(host);
  setupPmbScheduleClock();
}


function normalizePmbBayNumber(value = '', stage = '') {
  const parsed = Number.parseInt(String(value || '').trim(), 10);
  const max = stage ? pmbStageBayCount(stage) : PMB_BAY_MAX_COUNT;
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= max ? parsed : '';
}

function pmbBayNumber(vehicle = {}, stage = '') {
  const currentStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  const bayStage = normalizePmbStage(vehicle.pmbBayStage || '');
  const bay = normalizePmbBayNumber(vehicle.pmbBayNumber, currentStage);
  if (!bay) return '';
  if (currentStage && bayStage && bayStage !== currentStage) return '';
  return bay;
}

function pmbBayHours(vehicle = {}) {
  const raw = String(vehicle.pmbBayEstimatedHours ?? '').trim();
  if (!raw) return '';
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed) || parsed < 0) return '';
  return parsed;
}

function pmbBayHoursLabel(vehicle = {}) {
  const hours = pmbBayHours(vehicle);
  if (hours === '') return 'Hours not set';
  return `${hours}${String(hours).includes('.') ? '' : '.0'}h planned`;
}

function pmbBayScheduledStart(vehicle = {}) {
  return parseIsoTimestamp(vehicle.pmbBayScheduledStartAt || '') || parseIsoTimestamp(vehicle.pmbBayEnteredAt || '') || null;
}

function pmbBayScheduledStartLabel(vehicle = {}) {
  const start = pmbBayScheduledStart(vehicle);
  return start ? start.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'Start not set';
}

function datetimeLocalValueFromIso(value = '') {
  const date = parseIsoTimestamp(value);
  if (!date) return '';
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function isoFromDatetimeLocalValue(value = '') {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? '' : date.toISOString();
}

function pmbBayMechanic(vehicle = {}) {
  return cleanNavisionText(vehicle.pmbBayMechanic || '');
}

function mechanicOptionsHtml(current = '') {
  const selected = cleanNavisionText(current);
  const names = loadMechanics();
  const combined = selected && !names.includes(selected) ? [selected, ...names] : names;
  return `<option value="">Unassigned</option>${combined.map(name => `<option value="${escapeHtml(name)}"${name === selected ? ' selected' : ''}>${escapeHtml(name)}</option>`).join('')}`;
}

function pmbBaySubletProvider(vehicle = {}) {
  return cleanNavisionText(vehicle.pmbSubletProvider || '');
}

function subletProviderOptionsHtml(current = '') {
  const selected = cleanNavisionText(current);
  const names = loadSubletProviders();
  const combined = selected && !names.includes(selected) ? [selected, ...names] : names;
  return `<option value="">Unassigned</option>${combined.map(name => `<option value="${escapeHtml(name)}"${name === selected ? ' selected' : ''}>${escapeHtml(name)}</option>`).join('')}`;
}

function addMechanicFromPrompt() {
  const entered = cleanNavisionText(window.prompt('Enter mechanic / technician name:', '') || '');
  if (!entered) return;
  saveMechanics([...loadMechanics(), entered]);
  renderKpis();
  renderAdminLists();
}

function addSubletProviderFromPrompt() {
  const entered = cleanNavisionText(window.prompt('Enter external provider name:', '') || '');
  if (!entered) return;
  saveSubletProviders([...loadSubletProviders(), entered]);
  renderKpis();
  renderAdminLists();
}

function pmbBaySummary(vehicle = {}) {
  const stage = inferredPmbStage(vehicle);
  const bay = pmbBayNumber(vehicle, stage);
  if (!stage || !bay) return '';
  const hours = pmbBayHours(vehicle);
  return `Bay ${bay}${hours !== '' ? ` · ${hours}h` : ''}`;
}

function pmbBayStageVehicles(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!normalizedStage) return [];
  return filteredPmbVehiclesIgnoringSubFilter()
    .filter(vehicle => statusCategory(vehicle) === 'pmb' && inferredPmbStage(vehicle) === normalizedStage)
    .sort((a, b) => {
      const bayA = pmbBayNumber(a, normalizedStage) || 999;
      const bayB = pmbBayNumber(b, normalizedStage) || 999;
      if (bayA !== bayB) return bayA - bayB;
      return String(displayStockNumber(a) || a.order || '').localeCompare(String(displayStockNumber(b) || b.order || ''));
    });
}

function nextOutstandingPmbStage(vehicle = {}, currentStage = '') {
  const current = normalizePmbStage(currentStage || inferredPmbStage(vehicle));
  const currentIndex = PMB_BAY_STATION_SEQUENCE.indexOf(current);
  const after = currentIndex >= 0 ? PMB_BAY_STATION_SEQUENCE.slice(currentIndex + 1) : PMB_BAY_STATION_SEQUENCE.slice();
  const before = currentIndex >= 0 ? PMB_BAY_STATION_SEQUENCE.slice(0, currentIndex) : [];
  return after.concat(before).find(stage => {
    const def = pmbStageJobDef(stage);
    return def && pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def);
  }) || '';
}



const PMB_SCHEDULE_DAYS = 5;
const PMB_SCHEDULE_WORK_START_HOUR = 7;
const PMB_SCHEDULE_WORK_END_HOUR = 17;
const PMB_SCHEDULE_WORK_HOURS_PER_DAY = PMB_SCHEDULE_WORK_END_HOUR - PMB_SCHEDULE_WORK_START_HOUR;
const PMB_SCHEDULE_HOUR_SCALE = 72;
const PMB_SCHEDULE_LEFT_COL = 150;
const PMB_SCHEDULE_SNAP_MINUTES = 15;
const PMB_SCHEDULE_SNAP_HOURS = PMB_SCHEDULE_SNAP_MINUTES / 60;

function isPmbProductionDay(date = new Date()) {
  const day = date.getDay();
  return day >= 1 && day <= 5;
}

function pmbMoveToNextProductionDay(date = new Date()) {
  const d = new Date(date);
  d.setHours(PMB_SCHEDULE_WORK_START_HOUR, 0, 0, 0);
  while (!isPmbProductionDay(d)) d.setDate(d.getDate() + 1);
  return d;
}

function pmbMoveToPreviousProductionDay(date = new Date()) {
  const d = new Date(date);
  d.setHours(PMB_SCHEDULE_WORK_END_HOUR, 0, 0, 0);
  while (!isPmbProductionDay(d)) d.setDate(d.getDate() - 1);
  return d;
}

function pmbAddProductionDays(date = new Date(), days = 0) {
  const d = new Date(date);
  d.setHours(PMB_SCHEDULE_WORK_START_HOUR, 0, 0, 0);
  while (!isPmbProductionDay(d)) d.setDate(d.getDate() + 1);
  let remaining = Math.max(0, Number(days) || 0);
  while (remaining > 0) {
    d.setDate(d.getDate() + 1);
    if (isPmbProductionDay(d)) remaining -= 1;
  }
  return d;
}

function pmbBusinessDayIndexFromScheduleStart(date = new Date(), config = pmbScheduleConfig()) {
  const target = startOfLocalDay(date);
  const start = startOfLocalDay(config.startDate);
  if (target < start) return -1;
  if (!isPmbProductionDay(target)) return -1;
  let idx = 0;
  const cursor = new Date(start);
  while (cursor < target) {
    cursor.setDate(cursor.getDate() + 1);
    if (isPmbProductionDay(cursor)) idx += 1;
  }
  return idx;
}

function pmbScheduleStartDate() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), PMB_SCHEDULE_WORK_START_HOUR, 0, 0, 0);
  return isPmbProductionDay(start) ? start : pmbMoveToNextProductionDay(start);
}

function pmbScheduleConfig() {
  const startDate = pmbScheduleStartDate();
  const hours = PMB_SCHEDULE_DAYS * PMB_SCHEDULE_WORK_HOURS_PER_DAY;
  return {
    startDate,
    startIso: startDate.toISOString(),
    days: PMB_SCHEDULE_DAYS,
    workStartHour: PMB_SCHEDULE_WORK_START_HOUR,
    workEndHour: PMB_SCHEDULE_WORK_END_HOUR,
    workHoursPerDay: PMB_SCHEDULE_WORK_HOURS_PER_DAY,
    hours,
    hourScale: PMB_SCHEDULE_HOUR_SCALE,
    leftCol: PMB_SCHEDULE_LEFT_COL,
    dayWidth: PMB_SCHEDULE_WORK_HOURS_PER_DAY * PMB_SCHEDULE_HOUR_SCALE,
    width: hours * PMB_SCHEDULE_HOUR_SCALE,
  };
}

function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

function dayIndexFromScheduleStart(date = new Date(), config = pmbScheduleConfig()) {
  return pmbBusinessDayIndexFromScheduleStart(date, config);
}

function decimalHour(date = new Date()) {
  return date.getHours() + (date.getMinutes() / 60) + (date.getSeconds() / 3600) + (date.getMilliseconds() / 3600000);
}

function pmbProductionOffsetHoursFromDate(date = new Date(), config = pmbScheduleConfig(), clamp = true) {
  const parsed = date instanceof Date ? date : parseIsoTimestamp(date || '');
  if (!parsed) return 0;
  let dayIndex = pmbBusinessDayIndexFromScheduleStart(parsed, config);
  let inDay = decimalHour(parsed) - config.workStartHour;
  if (clamp) {
    if (dayIndex < 0) {
      const next = pmbMoveToNextProductionDay(parsed);
      dayIndex = pmbBusinessDayIndexFromScheduleStart(next, config);
      if (dayIndex < 0) return 0;
      inDay = 0;
    }
    if (dayIndex >= config.days) return config.hours;
    inDay = Math.max(0, Math.min(config.workHoursPerDay, inDay));
  }
  return dayIndex * config.workHoursPerDay + inDay;
}

function pmbDateAtProductionOffsetHours(config = pmbScheduleConfig(), offsetHours = 0) {
  const safeOffset = Math.max(0, Math.min(config.hours, Number(offsetHours) || 0));
  const dayIndex = Math.min(config.days - 1, Math.floor(safeOffset / config.workHoursPerDay));
  const inDay = Math.min(config.workHoursPerDay, safeOffset - dayIndex * config.workHoursPerDay);
  const date = pmbAddProductionDays(config.startDate, dayIndex);
  date.setHours(config.workStartHour, 0, 0, 0);
  date.setMinutes(date.getMinutes() + Math.round(inDay * 60));
  return date;
}

function pmbClampDateToProductionSlot(date = new Date(), direction = 'forward') {
  const d = new Date(date);
  if (!isPmbProductionDay(d)) {
    return direction === 'back' ? pmbMoveToPreviousProductionDay(d) : pmbMoveToNextProductionDay(d);
  }
  const hour = decimalHour(d);
  if (hour < PMB_SCHEDULE_WORK_START_HOUR) {
    d.setHours(PMB_SCHEDULE_WORK_START_HOUR, 0, 0, 0);
    return d;
  }
  if (hour >= PMB_SCHEDULE_WORK_END_HOUR) {
    if (direction === 'back') {
      d.setHours(PMB_SCHEDULE_WORK_END_HOUR, 0, 0, 0);
      return d;
    }
    d.setDate(d.getDate() + 1);
    return pmbMoveToNextProductionDay(d);
  }
  return d;
}

function pmbNextProductionSlotDate(date = new Date()) {
  return snapDateToScheduleIncrement(pmbClampDateToProductionSlot(date, 'forward'));
}

function pmbAddProductionHours(startDate = new Date(), hours = 0) {
  let current = pmbClampDateToProductionSlot(startDate, 'forward');
  let remaining = Math.max(0, Number(hours) || 0);
  if (!remaining) return current;
  while (remaining > 0.0001) {
    const currentHour = decimalHour(current);
    const availableToday = Math.max(0, PMB_SCHEDULE_WORK_END_HOUR - currentHour);
    if (remaining <= availableToday + 0.0001) {
      current = new Date(current.getTime() + remaining * 3600000);
      return snapDateToScheduleIncrement(current);
    }
    remaining -= availableToday;
    current.setDate(current.getDate() + 1);
    current = pmbMoveToNextProductionDay(current);
  }
  return snapDateToScheduleIncrement(current);
}

function pmbScheduleChipWidthPx(vehicle = {}) {
  const hours = pmbBayHours(vehicle);
  const planned = hours === '' ? 1 : Math.max(PMB_SCHEDULE_SNAP_HOURS, Number(hours));
  return Math.round(Math.min(760, Math.max(96, planned * PMB_SCHEDULE_HOUR_SCALE)));
}

function pmbScheduleChipLeftPx(vehicle = {}, config = pmbScheduleConfig()) {
  const start = pmbBayScheduledStart(vehicle) || pmbNextProductionSlotDate();
  const offsetHours = pmbProductionOffsetHoursFromDate(start, config, true);
  return Math.round(Math.min(config.width - 40, Math.max(0, offsetHours * config.hourScale)));
}

function pmbSchedulePlannedHours(vehicles = []) {
  return vehicles.reduce((sum, vehicle) => {
    const hours = pmbBayHours(vehicle);
    return sum + (hours === '' ? 1 : Math.max(PMB_SCHEDULE_SNAP_HOURS, Number(hours)));
  }, 0);
}

function pmbScheduleMaxHours(rowGroups = []) {
  return PMB_SCHEDULE_DAYS * PMB_SCHEDULE_WORK_HOURS_PER_DAY;
}

function pmbScheduleTickDate(index = 0, config = pmbScheduleConfig()) {
  return pmbDateAtProductionOffsetHours(config, index);
}

function pmbScheduleHourLabel(date = new Date(), index = 0, config = pmbScheduleConfig()) {
  const inDay = index % config.workHoursPerDay;
  const dayLabel = date.toLocaleDateString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit' });
  const timeLabel = date.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' });
  if (inDay === 0) return `<strong>${escapeHtml(dayLabel)}</strong><small>${escapeHtml(timeLabel)}</small>`;
  return `<span${inDay % 2 ? ' class="minor-hour"' : ''}>${escapeHtml(timeLabel)}</span>`;
}

function pmbScheduleTicksHtml(config = pmbScheduleConfig()) {
  const ticks = Array.from({ length: config.hours }, (_, index) => {
    const date = pmbScheduleTickDate(index, config);
    const inDay = index % config.workHoursPerDay;
    const cls = [
      inDay === 0 ? 'day-start' : '',
      inDay === config.workHoursPerDay - 1 ? 'day-last-hour' : '',
      inDay % 2 === 0 ? 'major-hour' : 'minor-hour'
    ].filter(Boolean).join(' ');
    return `<span class="${cls}">${pmbScheduleHourLabel(date, index, config)}</span>`;
  }).join('');
  return `<div class="pmb-schedule-scale" aria-hidden="true">${ticks}</div>`;
}

function renderPmbScheduleRowHtml({ label = '', sub = '', vehicles = [], stage = '', bay = '', type = '', acceptsDrop = true, config = pmbScheduleConfig() } = {}) {
  const normalizedStage = normalizePmbStage(stage);
  const dropAttrs = acceptsDrop && normalizedStage
    ? `data-pmb-bay-drop-stage="${escapeHtml(normalizedStage)}" data-pmb-bay-drop-number="${escapeHtml(bay)}"`
    : '';
  const plannedHours = pmbSchedulePlannedHours(vehicles);
  const countText = vehicles.length ? `${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'}` : 'Available';
  const emptyText = type === 'work-started'
    ? 'Completed work returns here after sign-off.'
    : type === 'unassigned'
      ? 'Drop waiting vehicles here or into a bay.'
      : 'Drop vehicle here';
  const rowClasses = [
    'pmb-schedule-row',
    type ? `pmb-schedule-row-${type}` : '',
    type === 'bay' ? 'timeline-row' : 'holding-row',
    vehicles.length ? 'has-vehicles' : 'is-empty',
    acceptsDrop ? 'accepts-drop' : '',
  ].filter(Boolean).join(' ');
  return `
    <section class="${escapeHtml(rowClasses)}" aria-label="${escapeHtml(label)}">
      <div class="pmb-schedule-row-label">
        <strong>${escapeHtml(label)}</strong>
        <span>${escapeHtml(sub || countText)}</span>
        <small>${escapeHtml(`${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'} · ${plannedHours.toFixed(plannedHours % 1 ? 1 : 0)}h planned`)}</small>
      </div>
      <div class="pmb-schedule-lane" ${dropAttrs}>
        ${vehicles.length ? vehicleIdentityHeaderHtml('pmb-schedule-identity-header') : ''}
        <div class="pmb-schedule-lane-inner">
          ${vehicles.map((vehicle, index) => pmbBayTimelineVehicleCardHtml(vehicle, normalizedStage, type, config, index)).join('') || `<div class="pmb-schedule-empty">${escapeHtml(emptyText)}</div>`}
        </div>
      </div>
    </section>`;
}

function renderPmbBayBoardHtml(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!normalizedStage) return '';
  const label = pmbStageLabel(normalizedStage);
  const vehicles = pmbBayStageVehicles(normalizedStage);
  const jobDef = pmbStageJobDef(normalizedStage);
  const completedCount = jobDef ? vehicles.filter(vehicle => pdcJobComplete(vehicle, jobDef)).length : 0;
  const totalHours = vehicles.reduce((sum, vehicle) => sum + (pmbBayHours(vehicle) || 0), 0);
  const baylessVehicles = vehicles.filter(vehicle => !pmbBayNumber(vehicle, normalizedStage));
  const workStarted = baylessVehicles.filter(vehicle => jobDef && pdcJobComplete(vehicle, jobDef));
  const unassigned = baylessVehicles.filter(vehicle => !(jobDef && pdcJobComplete(vehicle, jobDef)));
  const bayCount = pmbStageBayCount(normalizedStage);
  const bayTiles = Array.from({ length: bayCount }, (_, index) => {
    const bay = index + 1;
    const bayText = String(bay).padStart(2, '0');
    const bayVehicles = vehicles.filter(vehicle => pmbBayNumber(vehicle, normalizedStage) === bay);
    const completeClass = bayVehicles.length && jobDef && bayVehicles.every(vehicle => pdcJobComplete(vehicle, jobDef)) ? ' is-complete' : '';
    return `
      <section class="pmb-bay ${bayVehicles.length ? 'is-occupied' : 'is-empty'}${completeClass}" data-pmb-bay-drop-stage="${escapeHtml(normalizedStage)}" data-pmb-bay-drop-number="${escapeHtml(String(bay))}">
        <div class="pmb-bay-title">
          <strong>Bay ${escapeHtml(bayText)}</strong>
          <span>${bayVehicles.length ? `${bayVehicles.length} vehicle${bayVehicles.length === 1 ? '' : 's'}` : 'Available'}</span>
        </div>
        <div class="pmb-bay-slot">
          ${bayVehicles.map(vehicle => pmbBayVehicleCardHtml(vehicle, normalizedStage)).join('') || '<div class="pmb-bay-empty">Drop vehicle here</div>'}
        </div>
      </section>`;
  }).join('');

  const stageTabs = PMB_STAGE_DEFS.map(def => {
    const tabStage = normalizePmbStage(def.value);
    const tabVehicles = pmbBayStageVehicles(tabStage);
    const activeClass = tabStage === normalizedStage ? ' active' : '';
    const capacityText = pmbStageCapacityLabel(tabStage);
    const vehicleText = `${tabVehicles.length} veh`;
    return `<button class="pmb-bay-stage-tab${activeClass}" type="button" data-open-pmb-bays="${escapeHtml(tabStage)}" aria-pressed="${tabStage === normalizedStage ? 'true' : 'false'}"><span>${escapeHtml(def.label)}</span><strong>${escapeHtml(capacityText)}</strong><em>${escapeHtml(vehicleText)}</em></button>`;
  }).join('');

  return `
    <section class="pmb-bay-board pmb-bay-board-${escapeHtml(normalizedStage.toLowerCase())}" data-pmb-bay-board-stage="${escapeHtml(normalizedStage)}">
      <div class="pmb-bay-board-header">
        <div>
          <strong>${escapeHtml(label)} bays</strong>
          <span>${escapeHtml(pmbStageCapacityLabel(normalizedStage))} · ${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'} · ${completedCount} complete · ${totalHours.toFixed(totalHours % 1 ? 1 : 0)} planned hour${totalHours === 1 ? '' : 's'}</span>
        </div>
        <div class="pmb-bay-board-actions">
          <button class="small-button" type="button" data-close-pmb-bays>Back to PMB buckets</button>
        </div>
      </div>
      <div class="pmb-bay-stage-tabs" aria-label="PMB buckets">${stageTabs}</div>
      <div class="pmb-bay-help"><strong>${escapeHtml(label)} station focus:</strong> ${escapeHtml(pmbStageOperatorGuidance(normalizedStage))}</div>
      <div class="pmb-bay-holding-grid">
        <section class="pmb-bay-unassigned" data-pmb-bay-drop-stage="${escapeHtml(normalizedStage)}" data-pmb-bay-drop-number="">
          <div class="pmb-bay-unassigned-title"><strong>Not in a bay</strong><span>${unassigned.length} waiting</span></div>
          <div class="pmb-bay-unassigned-list">
            ${unassigned.map(vehicle => pmbBayVehicleCardHtml(vehicle, normalizedStage)).join('') || '<div class="pmb-bay-empty compact">All vehicles are assigned to bays.</div>'}
          </div>
        </section>
        <section class="pmb-bay-work-started">
          <div class="pmb-bay-unassigned-title"><strong>Work Started / Complete</strong><span>${workStarted.length} complete</span></div>
          <div class="pmb-bay-unassigned-list">
            ${workStarted.map(vehicle => pmbBayVehicleCardHtml(vehicle, normalizedStage)).join('') || '<div class="pmb-bay-empty compact">No completed vehicles waiting here.</div>'}
          </div>
        </section>
      </div>
      <div class="pmb-bay-grid">${bayTiles}</div>
    </section>`;
}

function pmbBayTimelineVehicleCardHtml(vehicle = {}, stage = '', rowType = '', config = pmbScheduleConfig(), index = 0) {
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  const key = vehicleKey(vehicle);
  const jobDef = pmbStageJobDef(normalizedStage);
  const bay = pmbBayNumber(vehicle, normalizedStage);
  const complete = jobDef ? pdcJobComplete(vehicle, jobDef) : false;
  const widthPx = rowType === 'bay' ? Math.max(pmbScheduleChipWidthPx(vehicle), 340) : 360;
  const leftPx = rowType === 'bay' ? pmbScheduleChipLeftPx(vehicle, config) : 0;
  const title = `${vehicleIdentityTitle(vehicle) || 'Vehicle'} · ${pmbStageLabel(normalizedStage)}${bay ? ` · Bay ${bay}` : rowType === 'work-started' ? ' · Work Started' : ' · no bay'} · click for details`;
  const draggableAttr = complete || rowType === 'bay' ? '' : `draggable="true" data-pmb-drag-key="${escapeHtml(key)}"`;
  const identityHtml = vehicleIdentityStackHtml(vehicle, { className: 'pmb-bay-identity pmb-schedule-identity' });
  const timeLabel = rowType === 'bay' ? pmbScheduleVehicleTimeLabel(vehicle) : '';
  const adjustAttrs = rowType === 'bay'
    ? `data-pmb-schedule-chip="1" data-pmb-schedule-chip-key="${escapeHtml(key)}" data-pmb-schedule-chip-stage="${escapeHtml(normalizedStage)}" data-pmb-schedule-chip-bay="${escapeHtml(bay)}"`
    : '';
  return `
    <article class="pmb-bay-vehicle-card pmb-schedule-chip pmb-schedule-chip-slim ${complete ? 'is-complete' : ''} ${isPdcBlocked(vehicle) ? 'is-blocked' : ''}" ${draggableAttr} ${adjustAttrs} data-open-stock="${escapeHtml(key)}" style="--chip-width:${widthPx}px; --chip-left:${leftPx}px; --chip-stack:${index};" title="${escapeHtml(title)}">
      ${identityHtml}
      ${rowType === 'bay' ? `<span class="pmb-schedule-chip-time" data-pmb-chip-time-label>${escapeHtml(timeLabel)}</span><span class="pmb-schedule-chip-resize-handle" data-pmb-chip-resize-handle title="Drag to change planned hours"></span>` : ''}
    </article>`;
}

function setupPmbScheduleClock() {
  if (app.pmbScheduleClockTimer) {
    window.clearInterval(app.pmbScheduleClockTimer);
    app.pmbScheduleClockTimer = null;
  }
  if (!$('[data-pmb-schedule-start]')) return;
  updatePmbScheduleClock();
  window.setTimeout(scrollPmbSchedulesToNow, 80);
  app.pmbScheduleClockTimer = window.setInterval(updatePmbScheduleClock, 15000);
}

function updatePmbScheduleClock() {
  $$('[data-pmb-schedule-start]').forEach(board => {
    const config = pmbScheduleConfigFromBoard(board);
    const line = $('[data-pmb-schedule-now-line]', board);
    const label = $('[data-pmb-schedule-now-label]', board);
    if (!line || !config.hours) return;
    const now = new Date();
    const dayIndex = dayIndexFromScheduleStart(now, config);
    const nowHour = decimalHour(now);
    const isVisibleDay = isPmbProductionDay(now) && dayIndex >= 0 && dayIndex < config.days;
    line.hidden = !isVisibleDay;
    line.style.display = isVisibleDay ? 'block' : 'none';
    if (!isVisibleDay) return;
    const direction = nowHour > config.workEndHour ? 'back' : 'forward';
    const clampedNow = pmbClampDateToProductionSlot(now, direction);
    const offsetHours = pmbProductionOffsetHoursFromDate(clampedNow, config, true);
    const left = Math.round(config.leftCol + offsetHours * config.hourScale);
    line.style.left = `${left}px`;
    line.style.height = `${Math.max(board.scrollHeight || 0, board.getBoundingClientRect().height || 0)}px`;
    line.style.setProperty('--now-left', `${left}px`);
    if (label) {
      const suffix = nowHour < config.workStartHour
        ? '7:00 am start'
        : nowHour > config.workEndHour
          ? '5:00 pm finish'
          : now.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' });
      label.textContent = `Now ${suffix}`;
    }
  });
}

function pmbScheduleConfigFromBoard(board) {
  const startDate = parseIsoTimestamp(board?.dataset?.pmbScheduleStart || '') || pmbScheduleStartDate();
  const days = Number(board?.dataset?.pmbScheduleDays || PMB_SCHEDULE_DAYS);
  const workHoursPerDay = Number(board?.dataset?.pmbScheduleWorkHours || PMB_SCHEDULE_WORK_HOURS_PER_DAY);
  const hourScale = Number(board?.dataset?.pmbScheduleScale || PMB_SCHEDULE_HOUR_SCALE);
  const leftCol = Number(board?.dataset?.pmbScheduleLeftCol || PMB_SCHEDULE_LEFT_COL);
  const hours = Number(board?.dataset?.pmbScheduleHours || days * workHoursPerDay);
  return {
    startDate,
    startIso: startDate.toISOString(),
    days,
    workStartHour: PMB_SCHEDULE_WORK_START_HOUR,
    workEndHour: PMB_SCHEDULE_WORK_END_HOUR,
    workHoursPerDay,
    hours,
    hourScale,
    leftCol,
    dayWidth: workHoursPerDay * hourScale,
    width: hours * hourScale,
  };
}

function scrollPmbSchedulesToNow() {
  $$('[data-pmb-schedule-start]').forEach(board => {
    const scroll = $('.pmb-schedule-scroll', board);
    if (!scroll || board.dataset.nowScrollDone === '1') return;
    const config = pmbScheduleConfigFromBoard(board);
    const now = new Date();
    const dayIndex = dayIndexFromScheduleStart(now, config);
    if (!isPmbProductionDay(now) || dayIndex < 0 || dayIndex >= config.days) return;
    const clampedNow = pmbClampDateToProductionSlot(now, decimalHour(now) < config.workStartHour ? 'forward' : 'back');
    const offsetHours = pmbProductionOffsetHoursFromDate(clampedNow, config, true);
    const nowLeft = config.leftCol + offsetHours * config.hourScale;
    scroll.scrollLeft = Math.max(0, nowLeft - 240);
    board.dataset.nowScrollDone = '1';
  });
}

function snapScheduleHours(value = 0) {
  const snap = PMB_SCHEDULE_SNAP_HOURS || 0.25;
  return Math.round(Number(value || 0) / snap) * snap;
}

function snapDateToScheduleIncrement(date = new Date()) {
  const snapMs = (PMB_SCHEDULE_SNAP_MINUTES || 15) * 60000;
  return new Date(Math.round(date.getTime() / snapMs) * snapMs);
}

function formatScheduleTime(date = new Date()) {
  return date.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' });
}

function pmbScheduleVehicleTimeLabel(vehicle = {}, startOverride = null, hoursOverride = null) {
  const start = startOverride || pmbBayScheduledStart(vehicle) || pmbNextProductionSlotDate();
  const rawHours = hoursOverride === null ? pmbBayHours(vehicle) : hoursOverride;
  const hours = rawHours === '' ? 1 : Math.max(PMB_SCHEDULE_SNAP_HOURS, Number(rawHours));
  const end = pmbAddProductionHours(start, hours);
  return `${formatScheduleTime(start)}-${formatScheduleTime(end)} · ${Number(hours.toFixed(2))}h`;
}

function isoFromScheduleOffsetHours(config = pmbScheduleConfig(), offsetHours = 0) {
  return pmbDateAtProductionOffsetHours(config, offsetHours).toISOString();
}

function hoursFromIsoAgainstSchedule(iso = '', config = pmbScheduleConfig()) {
  const date = parseIsoTimestamp(iso || '');
  if (!date) return 0;
  return pmbProductionOffsetHoursFromDate(date, config, true);
}

function bindPmbScheduleChips(host) {
  $$('[data-pmb-schedule-chip="1"]', host).forEach(chip => bindPmbScheduleChip(chip));
}

function bindPmbScheduleChip(chip) {
  if (!chip || chip.dataset.pmbScheduleBound === '1') return;
  chip.dataset.pmbScheduleBound = '1';
  const resizeHandle = $('[data-pmb-chip-resize-handle]', chip);
  if (resizeHandle) {
    resizeHandle.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
    });
    resizeHandle.addEventListener('pointerdown', event => startPmbScheduleChipInteraction(chip, event, 'resize'));
  }
  chip.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    if (event.target.closest('[data-pmb-chip-resize-handle]')) return;
    startPmbScheduleChipInteraction(chip, event, 'move');
  });
}

function startPmbScheduleChipInteraction(chip, event, mode = 'move') {
  if (!chip || chip.dataset.pmbScheduleChip !== '1') return;
  const key = chip.dataset.pmbScheduleChipKey || '';
  const stage = chip.dataset.pmbScheduleChipStage || '';
  const vehicle = app.data.find(v => vehicleKey(v) === key || v.stock === key || v.order === key || v.id === key);
  if (!vehicle || !stage) return;
  const board = chip.closest('[data-pmb-schedule-start]');
  if (!board) return;
  const config = pmbScheduleConfigFromBoard(board);
  const originX = event.clientX;
  const startHours = hoursFromIsoAgainstSchedule(vehicle.pmbBayScheduledStartAt || vehicle.pmbBayEnteredAt || '', config);
  const currentHours = pmbBayHours(vehicle);
  const startPlanned = currentHours === '' ? 1 : Math.max(PMB_SCHEDULE_SNAP_HOURS, Number(currentHours));
  const state = {
    chip, key, stage, mode, config, vehicle,
    originX,
    startHours,
    startPlanned,
    startLeftPx: pmbScheduleChipLeftPx(vehicle, config),
    startWidthPx: pmbScheduleChipWidthPx(vehicle),
    moved: false,
  };
  const onMove = moveEvent => continuePmbScheduleChipInteraction(state, moveEvent);
  const onUp = upEvent => endPmbScheduleChipInteraction(state, upEvent, onMove, onUp);
  document.addEventListener('pointermove', onMove);
  document.addEventListener('pointerup', onUp);
  document.body.classList.add('pmb-schedule-adjusting');
  chip.classList.add(mode === 'resize' ? 'is-resizing' : 'is-moving');
  chip.setPointerCapture?.(event.pointerId);
  event.preventDefault();
  event.stopPropagation();
}

function continuePmbScheduleChipInteraction(state, event) {
  const dx = event.clientX - state.originX;
  const deltaHours = snapScheduleHours(dx / state.config.hourScale);
  if (Math.abs(dx) > 3) state.moved = true;
  if (state.mode === 'move') {
    const newOffset = Math.max(0, Math.min(state.config.hours - 0.25, state.startHours + deltaHours));
    const leftPx = Math.round(Math.max(0, Math.min(state.config.width - 40, newOffset * state.config.hourScale)));
    state.previewOffsetHours = newOffset;
    state.chip.style.setProperty('--chip-left', `${leftPx}px`);
    const label = $('[data-pmb-chip-time-label]', state.chip);
    if (label) label.textContent = pmbScheduleVehicleTimeLabel(state.vehicle, pmbDateAtProductionOffsetHours(state.config, newOffset), state.startPlanned);
  } else {
    const newHours = Math.max(PMB_SCHEDULE_SNAP_HOURS, Math.min(24, snapScheduleHours(state.startPlanned + deltaHours)));
    const widthPx = Math.round(Math.min(760, Math.max(96, newHours * state.config.hourScale)));
    state.previewPlannedHours = newHours;
    state.chip.style.setProperty('--chip-width', `${widthPx}px`);
    const label = $('[data-pmb-chip-time-label]', state.chip);
    if (label) label.textContent = pmbScheduleVehicleTimeLabel(state.vehicle, pmbBayScheduledStart(state.vehicle) || pmbNextProductionSlotDate(), newHours);
  }
}

function endPmbScheduleChipInteraction(state, event, onMove, onUp) {
  document.removeEventListener('pointermove', onMove);
  document.removeEventListener('pointerup', onUp);
  document.body.classList.remove('pmb-schedule-adjusting');
  state.chip.classList.remove('is-moving', 'is-resizing');
  state.chip.releasePointerCapture?.(event.pointerId);
  if (!state.moved) return;
  state.chip.dataset.preventOpenUntil = String(Date.now() + 300);
  if (state.mode === 'move' && Number.isFinite(state.previewOffsetHours)) {
    const nextIso = isoFromScheduleOffsetHours(state.config, state.previewOffsetHours);
    updatePmbBayScheduleStart(state.key, state.stage, datetimeLocalValueFromIso(nextIso));
  }
  if (state.mode === 'resize' && Number.isFinite(state.previewPlannedHours)) {
    const nextHours = String(Number(snapScheduleHours(state.previewPlannedHours).toFixed(2)));
    updatePmbBayHours(state.key, state.stage, nextHours);
  }
}

function renderPmbBayControlSection(v = {}) {
  const stage = normalizePmbStage(v.pmbBayStage || inferredPmbStage(v));
  const bay = pmbBayNumber(v, stage);
  if (statusCategory(v) !== 'pmb' || !stage) return '';
  const jobDef = pmbStageJobDef(stage);
  const complete = jobDef ? pdcJobComplete(v, jobDef) : false;
  const isSubletStage = stage === 'SUBLET';
  const assigneeLabel = isSubletStage ? 'Provider' : 'Mechanic';
  const assigneeValue = isSubletStage ? pmbBaySubletProvider(v) : pmbBayMechanic(v);
  const assigneeOptions = isSubletStage ? subletProviderOptionsHtml(assigneeValue) : mechanicOptionsHtml(assigneeValue);
  const startValue = datetimeLocalValueFromIso(v.pmbBayScheduledStartAt || v.pmbBayEnteredAt || pmbNextProductionSlotDate().toISOString());
  return `
    <section class="pmb-bay-detail-box">
      <div class="muted-label section-label">Production bay details</div>
      <form class="pmb-bay-detail-form" data-pmb-bay-detail-form>
        <div class="form-row three-col">
          <label>
            <span class="muted-label">Station</span>
            <input value="${escapeHtml(pmbStageLabel(stage))}${bay ? ` · Bay ${escapeHtml(bay)}` : ' · Not in a bay'}" readonly />
          </label>
          <label>
            <span class="muted-label">Scheduled start</span>
            <input name="pmbBayScheduledStartAt" type="datetime-local" value="${escapeHtml(startValue)}" />
          </label>
          <label>
            <span class="muted-label">Planned hours</span>
            <input name="pmbBayEstimatedHours" type="number" min="0" step="0.25" inputmode="decimal" value="${pmbBayHours(v) === '' ? '' : escapeHtml(pmbBayHours(v))}" placeholder="1" />
          </label>
        </div>
        <div class="form-row two-col">
          <label>
            <span class="muted-label">${escapeHtml(assigneeLabel)}</span>
            <select name="pmbBayAssignee">${assigneeOptions}</select>
          </label>
          <label>
            <span class="muted-label">Status</span>
            <input value="${escapeHtml(complete ? `${jobDef?.label || 'Job'} complete` : `${jobDef?.label || 'Job'} open`)}" readonly />
          </label>
        </div>
        <div class="edit-actions">
          <button class="primary" type="submit">Save bay details</button>
          <button class="small-button ${complete ? 'active-lite' : ''}" type="button" data-modal-complete-pmb-bay-work="${escapeHtml(vehicleKey(v))}" data-modal-complete-pmb-bay-stage="${escapeHtml(stage)}" ${complete ? 'disabled aria-disabled="true"' : ''}>${complete ? 'Complete ✓' : `Complete ${escapeHtml(jobDef?.label || 'work')}`}</button>
          <span class="save-message" data-bay-save-message></span>
        </div>
      </form>
    </section>`;
}

function pmbStageOperatorGuidance(stage = '') {
  const label = pmbStageLabel(stage);
  return {
    TINT: 'Tint (internal) view: confirm tint work, planned hours, bay and technician only. Use Parts or other station pages for their own blockers and sign-offs.',
    HOIST: 'Hoist view: confirm hoist work, planned hours, bay and technician only.',
    FITTING: 'Fitting view: confirm accessory fitment work, planned hours, bay and technician only. Do not use this page for Parts or external specialist updates.',
    FABRICATION: 'Fabrication view: confirm fabrication work, planned hours, bay and technician only. Leave Tint / Electrical / Parts sign-off to their own pages.',
    ELECTRICAL: 'Electrical view: confirm electrical work, planned hours, bay and technician only. Escalate non-electrical blockers instead of clearing other departments here.',
    TYRE: 'Tyre bay view: confirm tyre/wheel work, planned hours, bay and technician only. One of the two bays is the wheel-alignment bay.'
  }[normalizePmbStage(stage)] || `${label} view: complete this station's work only.`;
}

function pmbCurrentStageStatusHtml(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  const jobDef = pmbStageJobDef(normalizedStage);
  if (!jobDef) return '';
  const required = pdcJobRequired(vehicle, jobDef);
  const complete = pdcJobComplete(vehicle, jobDef);
  const className = complete ? 'done' : required ? 'open' : 'not-required';
  const label = complete ? `${jobDef.label} complete` : required ? `${jobDef.label} required` : `${jobDef.label} not required`;
  return `<span class="pmb-bay-chip ${escapeHtml(className)}">${escapeHtml(label)}</span>`;
}

function pmbCardDetailHtml(vehicle = {}) {
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const consultant = consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || 'No sales rep';
  const blocked = isPdcBlocked(vehicle) || partsDepartmentStatus(vehicle) === 'stoppage';
  const blocker = blocked ? (partsStoppageReason(vehicle) || vehicle.pdcBlockedReason || 'Parts/PMB stoppage') : 'No parts stoppage';
  return `<span class="pmb-pill-vehicle" title="${escapeHtml(unit)}">${escapeHtml(truncate(unit, 34))}</span>
    <span class="pmb-pill-meta">
      <span class="pmb-card-age pmb-age-${escapeHtml(onSiteDaysClass(vehicle))}">${escapeHtml(onSiteDaysLabel(vehicle).replace('on site', 'at PMB'))}</span>
      <span class="pmb-pill-blocker ${blocked ? 'is-blocked' : ''}" title="${escapeHtml(blocker)}">${escapeHtml(blocked ? 'Parts stoppage' : 'No stoppage')}</span>
    </span>
    <span class="pmb-pill-sales" title="${escapeHtml(consultant)}">${escapeHtml(truncate(consultant, 30))}</span>`;
}

function pmbBayVehicleCardHtml(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  const key = vehicleKey(vehicle);
  const jobDef = pmbStageJobDef(normalizedStage);
  const bay = pmbBayNumber(vehicle, normalizedStage);
  const complete = jobDef ? pdcJobComplete(vehicle, jobDef) : false;
  const bayLabel = bay ? `Bay ${bay}` : 'No bay';
  const identityHtml = pmbBayPillIdentityHtml(vehicle);
  const customerLine = vehicleCustomerName(vehicle) || 'Dealer Order';
  const title = `${vehicleIdentityTitle(vehicle)} · ${pmbStageLabel(normalizedStage)} ${bayLabel}`;

  return `
    <article class="pmb-bay-vehicle-card pmb-bay-vehicle-pill ${complete ? 'is-complete' : ''} ${isPdcBlocked(vehicle) ? 'is-blocked' : ''}" draggable="true" data-pmb-drag-key="${escapeHtml(key)}" data-open-stock="${escapeHtml(key)}" title="${escapeHtml(title)}">
      <div class="pmb-bay-pill-main">
        ${identityHtml}
        <span class="pmb-bay-pill-customer">${escapeHtml(truncate(customerLine, 30))}</span>
        ${pmbCardDetailHtml(vehicle)}
      </div>
      <div class="pmb-bay-pill-bottom">
        ${pmbOutstandingStationChipsHtml(vehicle)}
        ${isPdcBlocked(vehicle) ? `<span class="pmb-bay-chip blocked">Blocked</span>` : ''}
      </div>
    </article>`;
}

function pmbVehicleCardHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const customerLine = vehicleCustomerName(vehicle) || 'Dealer Order';
  const title = `Drag ${vehicleIdentityTitle(vehicle) || 'vehicle'} to another PMB bucket`;
  return `
    <article class="pmb-vehicle-card pmb-vehicle-pill ${isPdcBlocked(vehicle) ? 'is-blocked' : ''}" draggable="true" data-pmb-drag-key="${escapeHtml(key)}" data-open-stock="${escapeHtml(key)}" title="${escapeHtml(title)}">
      <div class="pmb-pill-main">
        ${pmbBayPillIdentityHtml(vehicle)}
        <span class="pmb-pill-customer">${escapeHtml(truncate(customerLine, 30))}</span>
        ${pmbCardDetailHtml(vehicle)}
      </div>
      <div class="pmb-pill-bottom">
        ${pmbOutstandingStationChipsHtml(vehicle)}
      </div>
    </article>`;
}

function togglePdcJobCompletionFromCard(stockKey, jobKey) {
  const cleanKey = String(stockKey || '').trim();
  const def = PDC_JOB_BY_KEY.get(String(jobKey || '').toLowerCase());
  if (!cleanKey || !def) return;
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  if (!vehicle) return;
  const currentlyComplete = pdcJobComplete(vehicle, def);
  if (currentlyComplete && vehicleCollectedFromRft(vehicle)) {
    window.alert('Completed / collected vehicles are locked. This sign-off cannot be removed from a completed vehicle.');
    return;
  }
  const actionText = currentlyComplete ? 'remove the sign-off from' : 'sign off';
  if (!window.confirm(`${actionText.charAt(0).toUpperCase()}${actionText.slice(1)} ${def.label} for ${displayStockNumber(vehicle) || vehicle.order || 'this vehicle'}?`)) return;
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const updates = { [def.completeKey]: !currentlyComplete };
  if (!currentlyComplete) {
    updates[def.requireKey] = true;
    updates[def.completeAtKey] = now;
    updates[def.completeByKey] = operator;
  } else {
    updates[def.completeAtKey] = '';
    updates[def.completeByKey] = '';
  }
  recordVehicleAudit(vehicle, currentlyComplete ? 'Job sign-off removed' : 'Job signed off', { job: def.label, by: operator });
  saveVehicleEdits(vehicleKey(vehicle), updates);
}

function bindPmbDragBoard(host) {
  $$('.workflow-stage-bucket', host).forEach(bucket => {
    bucket.addEventListener('toggle', () => {
      if (bucket.open) app.workflowBucketsCollapsed = false;
    });
  });
  $$('[data-pmb-sub-filter]', host).forEach(button => button.addEventListener('click', () => applyPmbSubFilter(button.dataset.pmbSubFilter || '')));
  $$('[data-open-pmb-bays]', host).forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openPmbStageBayBoard(button.dataset.openPmbBays || '');
  }));
  $$('[data-close-pmb-bays]', host).forEach(button => button.addEventListener('click', closePmbStageBayBoard));
  $$('[data-add-pmb-mechanic]', host).forEach(button => button.addEventListener('click', addMechanicFromPrompt));
  $$('[data-add-sublet-provider]', host).forEach(button => button.addEventListener('click', addSubletProviderFromPrompt));
  $$('[data-open-stock]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.stopPropagation();
      const preventUntil = Number(button.dataset.preventOpenUntil || 0);
      if (preventUntil && Date.now() < preventUntil) return;
      openVehicleModal(button.dataset.openStock);
    });
  });
  $$('[data-toggle-pdc-job-complete]', host).forEach(marker => {
    marker.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      togglePdcJobCompletionFromCard(marker.dataset.jobStock, marker.dataset.togglePdcJobComplete);
    });
    marker.addEventListener('keydown', event => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      event.stopPropagation();
      togglePdcJobCompletionFromCard(marker.dataset.jobStock, marker.dataset.togglePdcJobComplete);
    });
  });
  $$('[data-transfer-rft-stock]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.stopPropagation();
      transferVehicleToRftFromCard(button.dataset.transferRftStock);
    });
  });
  $$('[data-assign-pmb-bay-key]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      void assignPmbVehicleToBay(
        button.dataset.assignPmbBayKey,
        button.dataset.assignPmbBayStage,
        button.dataset.assignPmbBayNumber || '',
      );
    });
  });
  $$('[data-move-pmb-stage-key]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      void movePmbVehicleToStage(button.dataset.movePmbStageKey, button.dataset.movePmbStageValue || '');
    });
  });
  $$('[data-pmb-bay-hours-key]', host).forEach(input => {
    input.addEventListener('click', event => event.stopPropagation());
    input.addEventListener('change', () => updatePmbBayHours(input.dataset.pmbBayHoursKey, input.dataset.pmbBayHoursStage, input.value));
  });
  $$('[data-pmb-bay-mechanic-key]', host).forEach(select => {
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', () => updatePmbBayMechanic(select.dataset.pmbBayMechanicKey, select.dataset.pmbBayMechanicStage, select.value));
  });
  $$('[data-pmb-bay-provider-key]', host).forEach(select => {
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', () => updatePmbBaySubletProvider(select.dataset.pmbBayProviderKey, select.dataset.pmbBayProviderStage, select.value));
  });
  $$('[data-complete-pmb-bay-work]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      completePmbBayWork(button.dataset.completePmbBayWork, button.dataset.completePmbBayStage);
    });
  });
  $$('[data-move-next-pmb-stage]', host).forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      moveVehicleToNextPmbStageFromBay(button.dataset.moveNextPmbStage, button.dataset.moveNextFromStage);
    });
  });
  $$('[data-pmb-drag-key]', host).forEach(card => bindPmbDraggable(card, card.dataset.pmbDragKey));
  $$('[data-pmb-drop-stage]', host).forEach(dropZone => bindPmbDropTarget(dropZone));
  $$('[data-pmb-bay-drop-stage]', host).forEach(dropZone => bindPmbBayDropTarget(dropZone));
  bindPmbScheduleChips(host);
}

function bindPmbTableRowDragging(table) {
  if (!table || app.quickFilter !== 'pmb') return;
  $$('[data-pmb-table-drag-key]', table).forEach(row => bindPmbDraggable(row, row.dataset.pmbTableDragKey));
}

function bindPmbDraggable(element, key) {
  if (!element || !key) return;
  element.addEventListener('dragstart', event => {
    app.pmbDraggingKey = key;
    element.classList.add('pmb-dragging-source');
    document.body.classList.add('pmb-dragging');
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', key);
      event.dataTransfer.setData('application/x-vehicle-key', key);
    }
  });
  element.addEventListener('dragend', () => {
    element.classList.remove('pmb-dragging-source');
    document.body.classList.remove('pmb-dragging');
    $$('.pmb-drop-lane.drag-over').forEach(lane => lane.classList.remove('drag-over'));
    $$('.pmb-bay.drag-over, .pmb-bay-unassigned.drag-over, .pmb-schedule-lane.drag-over').forEach(target => target.classList.remove('drag-over'));
    app.pmbDraggingKey = '';
  });
}

function bindPmbDropTarget(dropTarget) {
  if (!dropTarget) return;
  dropTarget.addEventListener('dragover', event => {
    if (!app.pmbDraggingKey && !event.dataTransfer) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    dropTarget.closest('.pmb-drop-lane')?.classList.add('drag-over');
  });
  dropTarget.addEventListener('dragleave', event => {
    const lane = dropTarget.closest('.pmb-drop-lane');
    if (lane && !lane.contains(event.relatedTarget)) lane.classList.remove('drag-over');
  });
  dropTarget.addEventListener('drop', event => {
    event.preventDefault();
    event.stopPropagation();
    const key = event.dataTransfer?.getData('application/x-vehicle-key') || event.dataTransfer?.getData('text/plain') || app.pmbDraggingKey;
    const stage = dropTarget.dataset.pmbDropStage || '';
    dropTarget.closest('.pmb-drop-lane')?.classList.remove('drag-over');
    void movePmbVehicleToStage(key, stage);
  });
}

function pmbMovementResolutionChoiceModal(vehicle = {}, currentStage = '', nextStage = '') {
  const stock = displayStockNumber(vehicle) || vehicle.order || 'this vehicle';
  const area = pmbStageLabel(currentStage) || 'the current area';
  const nextArea = pmbStageLabel(nextStage) || 'Unallocated';
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay pmb-resolution-modal-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'pmb-resolution-modal-title');
    overlay.innerHTML = `
      <section class="modal-card pmb-resolution-modal-card">
        <button class="modal-close" type="button" data-pmb-resolution-cancel aria-label="Cancel movement">×</button>
        <div class="panel-header">
          <div>
            <h2 id="pmb-resolution-modal-title">Confirm movement</h2>
            <p>${escapeHtml(stock)} is leaving ${escapeHtml(area)} for ${escapeHtml(nextArea)}. Tick what applies.</p>
          </div>
        </div>
        <div class="pmb-resolution-options" role="group" aria-label="Movement outcome">
          <label class="pmb-resolution-option is-complete">
            <input type="checkbox" value="complete" data-pmb-resolution-choice checked>
            <span>
              <strong>Work complete</strong>
              <small>Tick off ${escapeHtml(area)} and move the vehicle.</small>
            </span>
          </label>
          <label class="pmb-resolution-option is-stoppage">
            <input type="checkbox" value="stoppage" data-pmb-resolution-choice>
            <span>
              <strong>Stoppage</strong>
              <small>Move the vehicle and mark it as stopped.</small>
            </span>
          </label>
          <label class="pmb-resolution-option is-move">
            <input type="checkbox" value="move" data-pmb-resolution-choice>
            <span>
              <strong>Move only</strong>
              <small>Move without changing the work tick.</small>
            </span>
          </label>
        </div>
        <label class="pmb-resolution-reason" data-pmb-resolution-reason-wrap hidden>
          <span>Stoppage reason</span>
          <input type="text" value="${escapeHtml(area)} stoppage" data-pmb-resolution-reason>
        </label>
        <div class="edit-actions pmb-resolution-actions">
          <button class="secondary" type="button" data-pmb-resolution-cancel>Cancel</button>
          <button class="primary" type="button" data-pmb-resolution-save>Apply</button>
        </div>
      </section>
    `;
    const finish = value => {
      document.removeEventListener('keydown', onKeydown);
      overlay.remove();
      resolve(value);
    };
    const selectedChoice = () => overlay.querySelector('[data-pmb-resolution-choice]:checked')?.value || '';
    const syncReason = () => {
      const showReason = selectedChoice() === 'stoppage';
      overlay.querySelector('[data-pmb-resolution-reason-wrap]').hidden = !showReason;
    };
    const onKeydown = event => {
      if (event.key === 'Escape') finish(null);
    };
    overlay.querySelectorAll('[data-pmb-resolution-choice]').forEach(input => {
      input.addEventListener('change', () => {
        if (input.checked) {
          overlay.querySelectorAll('[data-pmb-resolution-choice]').forEach(other => {
            if (other !== input) other.checked = false;
          });
        } else if (!selectedChoice()) {
          input.checked = true;
        }
        syncReason();
      });
    });
    overlay.querySelectorAll('[data-pmb-resolution-cancel]').forEach(btn => btn.addEventListener('click', () => finish(null)));
    overlay.addEventListener('click', event => {
      if (event.target === overlay) finish(null);
    });
    overlay.querySelector('[data-pmb-resolution-save]').addEventListener('click', () => {
      const choice = selectedChoice();
      const reason = cleanNavisionText(overlay.querySelector('[data-pmb-resolution-reason]')?.value || `${area} stoppage`);
      finish({ choice, reason: reason || `${area} stoppage` });
    });
    document.body.appendChild(overlay);
    document.addEventListener('keydown', onKeydown);
    syncReason();
    overlay.querySelector('[data-pmb-resolution-save]')?.focus();
  });
}

async function pmbMovementResolutionUpdates(vehicle = {}, fromStage = '', toStage = '') {
  const currentStage = normalizePmbStage(fromStage);
  const nextStage = normalizePmbStage(toStage);
  if (!currentStage || currentStage === nextStage) return {};
  const jobDef = pmbStageJobDef(currentStage);
  if (!jobDef || pdcJobComplete(vehicle, jobDef)) return {};
  const result = await pmbMovementResolutionChoiceModal(vehicle, currentStage, nextStage);
  if (!result) return null;
  const choice = String(result.choice || '').trim().toLowerCase();
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const area = pmbStageLabel(currentStage) || 'the current area';
  if (choice === 'stoppage') {
    const reason = cleanNavisionText(result.reason || `${area} stoppage`);
    recordVehicleAudit(vehicle, 'PMB movement stoppage recorded', { stage: area, reason, by: operator });
    return { pdcBlocked: true, pdcBlockReason: reason, pdcBlockedAt: now, pdcBlockedBy: operator };
  }
  if (choice === 'complete') {
    recordVehicleAudit(vehicle, 'Job signed off by PMB movement', { job: jobDef.label, from: area, to: pmbStageLabel(nextStage) || 'Unallocated', by: operator });
    return {
      [jobDef.requireKey]: true,
      [jobDef.completeKey]: true,
      [jobDef.completeAtKey]: now,
      [jobDef.completeByKey]: operator,
      pdcBlocked: false,
      pdcBlockReason: '',
    };
  }
  return {};
}

async function movePmbVehicleToStage(key, stage) {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return;
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  if (!vehicle) return;
  if (statusCategory(vehicle) !== 'pmb') {
    window.alert('That vehicle is not currently in PMB. Transfer it from Yard Hold to PMB first.');
    return;
  }
  const nextStage = normalizePmbStage(stage);
  const currentStage = normalizePmbStage(vehicle.pmbStage || vehicle.pdcWorkStage || vehicle.workStage || '');
  if (currentStage === nextStage) return;
  const now = nowIsoString();
  const resolutionUpdates = await pmbMovementResolutionUpdates(vehicle, currentStage, nextStage);
  if (resolutionUpdates === null) return;
  recordVehicleAudit(vehicle, 'PMB bucket moved', { from: pmbStageLabel(currentStage) || 'Unallocated', to: pmbStageLabel(nextStage) || 'Unallocated' });
  saveVehicleEdits(vehicleKey(vehicle), {
    ...resolutionUpdates,
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    pmbEnteredAt: pmbEnteredTimestamp(vehicle) || now,
    pmbTransferredAt: vehicle.pmbTransferredAt || now,
    pdcLocationUpdatedAt: vehicle.pdcLocationUpdatedAt || now,
    pmbStage: nextStage,
    pmbStageUpdatedAt: now,
    pmbStageEnteredAt: now,
    pmbBayStage: '',
    pmbBayNumber: '',
    pmbBayEstimatedHours: '',
    pmbBayEnteredAt: '',
    pmbBayScheduledStartAt: '',
    pmbBayCompletedAt: '',
    pmbBayCompletedBy: '',
    pmbBayCompletedStage: '',
    pmbBayMechanic: '',
  });
}


function openPmbStageBayBoard(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!normalizedStage) return;
  app.quickFilter = 'pmb';
  app.pmbSubFilter = normalizedStage;
  app.activePmbBayStage = normalizedStage;
  showView('workflow');
  renderWorkflowBoard();
}

function closePmbStageBayBoard() {
  app.activePmbBayStage = '';
  app.pmbSubFilter = '';
  document.body.classList.remove('pmb-station-mode');
  showView('workflow');
  renderWorkflowBoard();
}

function bindPmbBayDropTarget(dropTarget) {
  if (!dropTarget) return;
  dropTarget.addEventListener('dragover', event => {
    if (!app.pmbDraggingKey && !event.dataTransfer) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    dropTarget.classList.add('drag-over');
  });
  dropTarget.addEventListener('dragleave', event => {
    if (!dropTarget.contains(event.relatedTarget)) dropTarget.classList.remove('drag-over');
  });
  dropTarget.addEventListener('drop', event => {
    event.preventDefault();
    event.stopPropagation();
    const key = event.dataTransfer?.getData('application/x-vehicle-key') || event.dataTransfer?.getData('text/plain') || app.pmbDraggingKey;
    const stage = dropTarget.dataset.pmbBayDropStage || '';
    const bay = dropTarget.dataset.pmbBayDropNumber || '';
    let scheduledStartIso = '';
    if (bay) {
      const board = dropTarget.closest('[data-pmb-schedule-start]');
      if (board) {
        const config = pmbScheduleConfigFromBoard(board);
        const rect = dropTarget.getBoundingClientRect();
        const offsetPx = Math.max(0, event.clientX - rect.left);
        const offsetHours = Math.max(0, Math.min(config.hours, snapScheduleHours(offsetPx / config.hourScale)));
        scheduledStartIso = isoFromScheduleOffsetHours(config, offsetHours);
      }
    }
    dropTarget.classList.remove('drag-over');
    void assignPmbVehicleToBay(key, stage, bay, scheduledStartIso);
  });
}

function pmbSuggestedBayStartIso(stage = '', bay = '', vehicle = null, requestedStartIso = '') {
  const normalizedStage = normalizePmbStage(stage);
  const bayNumber = normalizePmbBayNumber(bay, normalizedStage);
  if (!normalizedStage || !bayNumber) return '';
  const existingStart = vehicle && pmbBayNumber(vehicle, normalizedStage) === bayNumber ? parseIsoTimestamp(vehicle.pmbBayScheduledStartAt || '') : null;
  if (existingStart && !requestedStartIso) return existingStart.toISOString();
  let latestEnd = null;
  app.data.forEach(row => {
    if (row === vehicle) return;
    if (statusCategory(row) !== 'pmb') return;
    if (normalizePmbStage(inferredPmbStage(row)) !== normalizedStage) return;
    if (pmbBayNumber(row, normalizedStage) !== bayNumber) return;
    const start = pmbBayScheduledStart(row) || parseIsoTimestamp(row.pmbBayEnteredAt || '');
    if (!start) return;
    const rawHours = pmbBayHours(row);
    const hours = rawHours === '' ? 1 : Math.max(PMB_SCHEDULE_SNAP_HOURS, Number(rawHours));
    const end = pmbAddProductionHours(start, hours);
    if (!latestEnd || end > latestEnd) latestEnd = end;
  });
  if (requestedStartIso) {
    const requested = pmbNextProductionSlotDate(parseIsoTimestamp(requestedStartIso) || new Date());
    if (latestEnd && requested < latestEnd) return latestEnd.toISOString();
    return requested.toISOString();
  }
  return (latestEnd || pmbNextProductionSlotDate()).toISOString();
}

async function assignPmbVehicleToBay(key, stage, bay, requestedStartIso = '') {
  const cleanKey = String(key || '').trim();
  const nextStage = normalizePmbStage(stage);
  if (!cleanKey || !nextStage) return;
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  if (!vehicle) return;
  if (statusCategory(vehicle) !== 'pmb') {
    window.alert('That vehicle is not currently in PMB. Transfer it from Yard Hold to PMB first.');
    return;
  }
  const bayNumber = normalizePmbBayNumber(bay, nextStage);
  const currentStage = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
  if (bayNumber) {
    const occupied = pmbBayOccupants(nextStage, bayNumber, cleanKey);
    if (occupied.length) {
      const currentBay = pmbBayNumber(vehicle, nextStage);
      const currentStageForSwap = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
      if (occupied.length !== 1 || currentStageForSwap !== nextStage || !currentBay) {
        window.alert(`${pmbStageLabel(nextStage)} Bay ${bayNumber} already has a vehicle. Move that vehicle out first, or use bay-to-bay swap from another numbered bay.`);
        return;
      }
      const other = occupied[0];
      const otherKey = vehicleKey(other);
      saveVehicleEdits(otherKey, {
        pdcLocation: 'PMB',
        manualLocation: 'PMB',
        pdcLocationLocked: true,
        pmbStage: nextStage,
        pmbBayStage: nextStage,
        pmbBayNumber: currentBay,
        pmbBayEnteredAt: nowIsoString(),
        pmbBayCompletedAt: '',
        pmbBayCompletedBy: '',
        pmbBayCompletedStage: '',
      }, { render: false });
      recordVehicleAudit(other, 'Swapped PMB bay', { stage: pmbStageLabel(nextStage), bay: `Bay ${currentBay}` });
    }
    // Bay assignment is already limited by the specific bay number above. Do not also block
    // moves because the PMB bucket is over its row/queue limit; that made valid bay-to-bay
    // and unallocated-to-empty-bay moves fail on busy days.
  }
  const now = nowIsoString();
  const bayLabel = bayNumber ? `Bay ${bayNumber}` : 'No bay';
  const resolutionUpdates = await pmbMovementResolutionUpdates(vehicle, currentStage, nextStage);
  if (resolutionUpdates === null) return;
  const updates = {
    ...resolutionUpdates,
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    pmbEnteredAt: pmbEnteredTimestamp(vehicle) || now,
    pmbTransferredAt: vehicle.pmbTransferredAt || now,
    pdcLocationUpdatedAt: vehicle.pdcLocationUpdatedAt || now,
    pmbStage: nextStage,
    pmbBayStage: bayNumber ? nextStage : '',
    pmbBayNumber: bayNumber || '',
    pmbBayEnteredAt: bayNumber ? now : '',
    pmbBayScheduledStartAt: bayNumber ? pmbSuggestedBayStartIso(nextStage, bayNumber, vehicle, requestedStartIso) : '',
    pmbBayMechanic: bayNumber && currentStage === nextStage ? pmbBayMechanic(vehicle) : '',
    pmbBayCompletedAt: '',
    pmbBayCompletedBy: '',
    pmbBayCompletedStage: '',
  };
  if (currentStage !== nextStage) {
    updates.pmbStageUpdatedAt = now;
    updates.pmbStageEnteredAt = now;
    recordVehicleAudit(vehicle, 'PMB bucket moved', { from: pmbStageLabel(currentStage) || 'Unallocated', to: pmbStageLabel(nextStage) || 'Unallocated' });
  }



  app.activePmbBayStage = nextStage;
  recordVehicleAudit(vehicle, bayNumber ? 'Assigned to PMB bay' : 'Removed from PMB bay', { stage: pmbStageLabel(nextStage), bay: bayLabel });
  saveVehicleEdits(vehicleKey(vehicle), updates);
}

function updatePmbBayHours(key, stage, value) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  const raw = String(value ?? '').trim();
  const parsed = raw === '' ? '' : Number.parseFloat(raw);
  if (parsed !== '' && (!Number.isFinite(parsed) || parsed < 0)) {
    window.alert('Enter a valid planned-hours number, for example 2, 3.5 or 0.25.');
    renderKpis();
    return;
  }
  const nextValue = parsed === '' ? '' : String(Number(snapScheduleHours(parsed).toFixed(2)));
  recordVehicleAudit(vehicle, 'Bay planned hours updated', { stage: pmbStageLabel(normalizedStage), hours: nextValue || 'blank' });
  saveVehicleEdits(vehicleKey(vehicle), { pdcLocation: 'PMB', manualLocation: 'PMB', pdcLocationLocked: true, pmbBayEstimatedHours: nextValue });
}

function updatePmbBayScheduleStart(key, stage, value) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  let nextIso = isoFromDatetimeLocalValue(value || '');
  if (!nextIso) {
    window.alert('Enter a valid scheduled start date and time.');
    renderKpis();
    return;
  }
  nextIso = pmbNextProductionSlotDate(parseIsoTimestamp(nextIso)).toISOString();
  recordVehicleAudit(vehicle, 'Bay scheduled start updated', { stage: pmbStageLabel(normalizedStage), start: new Date(nextIso).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) });
  saveVehicleEdits(vehicleKey(vehicle), { pdcLocation: 'PMB', manualLocation: 'PMB', pdcLocationLocked: true, pmbBayScheduledStartAt: nextIso });
}

function savePmbBayDetailForm(vehicle, form) {
  if (!vehicle || !form) return false;
  const stage = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
  if (!stage) return false;
  const hoursInput = form.elements?.namedItem('pmbBayEstimatedHours') || form.querySelector('[name="pmbBayEstimatedHours"]');
  const startInput = form.elements?.namedItem('pmbBayScheduledStartAt') || form.querySelector('[name="pmbBayScheduledStartAt"]');
  const assigneeInput = form.elements?.namedItem('pmbBayAssignee') || form.querySelector('[name="pmbBayAssignee"]');
  const rawHours = String(hoursInput?.value ?? '').trim();
  const parsedHours = rawHours === '' ? '' : Number.parseFloat(rawHours);
  if (parsedHours !== '' && (!Number.isFinite(parsedHours) || parsedHours < 0)) {
    window.alert('Enter a valid planned-hours number, for example 2, 3.5 or 0.25.');
    return false;
  }
  let startIso = isoFromDatetimeLocalValue(startInput?.value || '');
  if (!startIso) {
    window.alert('Enter a valid scheduled start date and time.');
    return false;
  }
  startIso = pmbNextProductionSlotDate(parseIsoTimestamp(startIso)).toISOString();
  const assignee = cleanNavisionText(assigneeInput?.value || '');
  const snappedHours = parsedHours === '' ? '' : String(Number(snapScheduleHours(parsedHours).toFixed(2)));
  const updates = {
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    pmbBayScheduledStartAt: startIso,
    pmbBayEstimatedHours: snappedHours,
  };
  if (stage === 'SUBLET') {
    updates.pmbSubletProvider = assignee;
    if (assignee) saveSubletProviders([...loadSubletProviders(), assignee]);
  } else {
    updates.pmbBayMechanic = assignee;
    if (assignee) saveMechanics([...loadMechanics(), assignee]);
  }
  recordVehicleAudit(vehicle, 'Bay detail updated', {
    stage: pmbStageLabel(stage),
    start: new Date(startIso).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }),
    hours: updates.pmbBayEstimatedHours || 'blank',
    assignee: assignee || 'Unassigned',
  });
  saveVehicleEdits(vehicleKey(vehicle), updates);
  return true;
}


function updatePmbBayMechanic(key, stage, value) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  const mechanic = cleanNavisionText(value || '');
  if (mechanic) saveMechanics([...loadMechanics(), mechanic]);
  recordVehicleAudit(vehicle, 'Bay mechanic assigned', { stage: pmbStageLabel(normalizedStage), mechanic: mechanic || 'Unassigned' });
  saveVehicleEdits(vehicleKey(vehicle), { pmbBayMechanic: mechanic });
}

function updatePmbBaySubletProvider(key, stage, value) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  const provider = cleanNavisionText(value || '');
  if (provider) saveSubletProviders([...loadSubletProviders(), provider]);
  recordVehicleAudit(vehicle, 'External provider assigned', { stage: pmbStageLabel(normalizedStage), provider: provider || 'Unassigned' });
  saveVehicleEdits(vehicleKey(vehicle), { pmbSubletProvider: provider });
}

function completePmbBayWork(key, stage) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  const def = pmbStageJobDef(normalizedStage);
  if (!vehicle || !def) return;
  const alreadyComplete = pdcJobComplete(vehicle, def);
  const label = `${vehicleIdentityTitle(vehicle) || 'this vehicle'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`;
  if (alreadyComplete) {
    window.alert(`${def.label} is already signed off for ${label}. Use the job marker or vehicle popup if you need to remove the sign-off.`);
    return;
  }
  const bay = pmbBayNumber(vehicle, normalizedStage);
  const hours = pmbBayHours(vehicle);
  const mechanic = pmbBayMechanic(vehicle);
  const subletProvider = pmbBaySubletProvider(vehicle);
  if (!window.confirm(`Mark ${def.label} complete for ${label}?\n\n${bay ? `Bay ${bay}` : 'No bay assigned'}${hours !== '' ? ` · ${hours} planned hours` : ''}\n\nThis will tick the ${def.label} marker on the main PMB vehicle card.`)) return;
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const updates = {
    [def.requireKey]: true,
    [def.completeKey]: true,
    [def.completeAtKey]: now,
    [def.completeByKey]: operator,
    pmbBayCompletedAt: now,
    pmbBayCompletedBy: operator,
    pmbBayCompletedStage: normalizedStage,
    [pdcJobMechanicKey(def)]: mechanic,
    [pdcJobBayKey(def)]: bay || '',
    [pdcJobHoursKey(def)]: hours === '' ? '' : String(hours),
    ...(normalizedStage === 'SUBLET' ? { pdcCompleteSubletProvider: subletProvider } : {}),
    pmbBayStage: '',
    pmbBayNumber: '',
    pmbBayEstimatedHours: '',
    pmbBayEnteredAt: '',
    pmbBayScheduledStartAt: '',
    pmbBayMechanic: '',
    pmbSubletProvider: '',
  };
  recordVehicleAudit(vehicle, 'Bay work completed', { stage: pmbStageLabel(normalizedStage), job: def.label, bay: bay || 'No bay', hours: hours === '' ? '' : hours, mechanic: mechanic || 'Unassigned', provider: normalizedStage === 'SUBLET' ? (subletProvider || 'Unassigned') : '', by: operator, returnedTo: 'Work Started' });
  saveVehicleEdits(vehicleKey(vehicle), updates);
}

function moveVehicleToNextPmbStageFromBay(key, fromStage) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const currentStage = normalizePmbStage(fromStage || inferredPmbStage(vehicle));
  if (!vehicle || !currentStage) return;
  const currentDef = pmbStageJobDef(currentStage);
  if (currentDef && !pdcJobComplete(vehicle, currentDef)) {
    window.alert(`Complete ${currentDef.label} first. Once it is signed off, this vehicle can be moved to the next required station.`);
    return;
  }
  const nextStage = nextOutstandingPmbStage(vehicle, currentStage);
  if (!nextStage) {
    window.alert('No next PMB station is outstanding for this vehicle. If all required jobs are complete, move it to RFT. If Parts is still outstanding, clear the parts issue before RFT.');
    return;
  }
  const now = nowIsoString();
  const bay = pmbBayNumber(vehicle, currentStage);
  app.activePmbBayStage = nextStage;
  recordVehicleAudit(vehicle, 'Moved to next PMB station', { from: pmbStageLabel(currentStage), to: pmbStageLabel(nextStage), fromBay: bay || 'No bay' });
  saveVehicleEdits(vehicleKey(vehicle), {
    pmbStage: nextStage,
    pmbStageUpdatedAt: now,
    pmbStageEnteredAt: now,
    pmbBayStage: '',
    pmbBayNumber: '',
    pmbBayEstimatedHours: '',
    pmbBayEnteredAt: '',
    pmbBayCompletedAt: '',
    pmbBayCompletedBy: '',
    pmbBayCompletedStage: '',
    pmbBayMechanic: '',
  });
}

function filteredPmbVehiclesIgnoringSubFilter() {
  const savedQuickFilter = app.quickFilter;
  const savedSubFilter = app.pmbSubFilter;
  app.quickFilter = 'pmb';
  app.pmbSubFilter = '';
  const rows = filteredVehicles();
  app.quickFilter = savedQuickFilter;
  app.pmbSubFilter = savedSubFilter;
  return rows;
}

function matchesQuickFilter(filter) {
  return (vehicle) => {
    if (!filter) return true;
    if (filter === 'incoming') return !['pmb', 'rft'].includes(statusCategory(vehicle));
    if (filter === 'batchmatched') return statusCategory(vehicle) === 'batchmatched';
    if (filter === 'partsstoppage') return isActivePartsStoppage(vehicle);
    if (filter === 'partsrequired') {
      const parts = PDC_JOB_BY_KEY.get('parts');
      return Boolean(parts && pdcJobRequired(vehicle, parts) && !pdcJobComplete(vehicle, parts));
    }
    return statusCategory(vehicle) === filter;
  };
}

function quickFilterLabel() {
  const base = {
    incoming: 'Incoming / non-PMB vehicles',
    batchmatched: 'Batch Matched vehicles',
    partsstoppage: 'Parts Stoppage vehicles',
    prodtransit: 'Production / In Transit vehicles',
    yardhold: 'Vehicles at YH',
    pmb: 'Vehicles at PMB',
    rft: 'Vehicles RFT',
    partsrequired: 'Parts Required',
  }[app.quickFilter || 'incoming'] || '';
  if (app.quickFilter === 'pmb' && app.pmbSubFilter) {
    return `${base} · ${pmbSubFilterLabel(app.pmbSubFilter)}`;
  }
  return base;
}

function applyQuickFilter(filter) {
  if (filter === 'partsrequired') {
    // Parts is still available from the sidebar, but the top Parts Required pill is temporarily removed.
    app.quickFilter = '';
    app.pmbSubFilter = '';
    app.activePmbBayStage = '';
    showView('parts');
    renderKpis();
    renderPartsHome();
    return;
  }
  const requestedFilter = filter || 'incoming';
  const nextFilter = app.quickFilter === requestedFilter ? 'incoming' : requestedFilter;
  app.quickFilter = nextFilter;
  if (nextFilter !== 'pmb') {
    app.pmbSubFilter = '';
    app.activePmbBayStage = '';
  }
  showView(nextFilter === 'pmb' ? 'workflow' : 'dashboard');
  renderKpis();
  renderVehicleTable();
}

function applyPmbSubFilter(filter = '') {
  const normalizedFilter = normalizePmbSubFilter(filter);
  app.quickFilter = 'pmb';
  app.pmbSubFilter = app.pmbSubFilter === normalizedFilter ? '' : normalizedFilter;
  app.activePmbBayStage = normalizePmbStage(normalizedFilter) || app.activePmbBayStage;
  showView('workflow');
  renderKpis();
  renderVehicleTable();
}

function clearQuickFilter(render = true) {
  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.activePmbBayStage = '';
  if (render) renderKpis();
}

function clearAllFilters() {
  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.activePmbBayStage = '';
  app.columnFilters = { sales: '', production: '', status: '', jita: '' };
  ['search', 'source-filter'].forEach(id => { const el = $('#' + id); if (el) el.value = ''; });
  renderKpis();
  renderVehicleTable();
}

function nextActionForVehicle(vehicle = {}) {
  const category = statusCategory(vehicle);
  if (isActivePartsStoppage(vehicle)) return `Fix parts stoppage: ${partsStoppageReason(vehicle)}`;
  if (isPdcBlocked(vehicle)) return `Clear blocker: ${pdcBlockReason(vehicle)}`;
  if (category === 'yardhold') return 'Transfer Yard Hold → PMB';
  if (category === 'pmb') {
    const stage = inferredPmbStage(vehicle);
    if (!stage) return 'Assign PMB stage and bay';
    const stageDef = pmbStageJobDef(stage);
    if (stageDef && pdcJobRequired(vehicle, stageDef) && !pdcJobComplete(vehicle, stageDef)) return `Complete ${stageDef.label}`;
    const nextStage = nextOutstandingPmbStage(vehicle, stage);
    if (nextStage) return `Move to ${pmbStageLabel(nextStage)}`;
    const issues = vehicleRftGateIssues(vehicle);
    if (issues.length) return `Fix before RFT: ${issues.join(' · ')}`;
    return 'Transfer to RFT';
  }
  if (category === 'rft') {
    const issues = vehicleRftGateIssues(vehicle);
    return issues.length ? `Fix RFT gate: ${issues.join(' · ')}` : 'Notify salesperson / final handover';
  }
  return 'Watch ETA / update from Navision';
}

function controlBoardIssueCounts() {
  const pmbRows = app.data.filter(vehicle => statusCategory(vehicle) === 'pmb');
  const rftRows = app.data.filter(vehicle => statusCategory(vehicle) === 'rft');
  return {
    partsStoppage: app.data.filter(isActivePartsStoppage).length,
    pmbBlocked: pmbRows.filter(isPdcBlocked).length,
    rftBlocked: rftRows.filter(vehicle => vehicleRftGateIssues(vehicle).length).length,
    pmbUnallocated: pmbRows.filter(vehicle => !inferredPmbStage(vehicle)).length,
    yardHoldReady: app.data.filter(canTransferVehicleToPmb).length,
  };
}

function issueStripButtonHtml(action, label, value, detail, tone = '') {
  return `<button class="exception-card ${escapeHtml(tone)}" type="button" data-control-issue="${escapeHtml(action)}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong><small>${escapeHtml(detail)}</small></button>`;
}

function renderControlBoardIssueStripHtml(counts = controlBoardIssueCounts()) {
  return `
    <div class="exception-strip" aria-label="Fix first queues">
      ${issueStripButtonHtml('parts-stoppage', 'Parts stoppages', counts.partsStoppage, 'Blocking production now', counts.partsStoppage ? 'danger' : '')}
      ${issueStripButtonHtml('pmb-blocked', 'PMB blockers', counts.pmbBlocked, 'Blocked PMB vehicles', counts.pmbBlocked ? 'danger' : '')}
      ${issueStripButtonHtml('rft-blocked', 'RFT blocked', counts.rftBlocked, 'Missing gate sign-offs', counts.rftBlocked ? 'warning' : '')}
      ${issueStripButtonHtml('pmb-unallocated', 'PMB unallocated', counts.pmbUnallocated, 'Needs stage / bay decision', counts.pmbUnallocated ? 'warning' : '')}
      ${issueStripButtonHtml('yardhold-ready', 'Yard Hold ready', counts.yardHoldReady, 'Can move to PMB', counts.yardHoldReady ? 'ready' : '')}
    </div>`;
}

function renderControlBoardFixFirst() {
  const host = $('#control-board-fix-first');
  if (!host) return;
  host.innerHTML = `
    <div class="panel-header compact exception-header">
      <div>
        <h2>Fix first</h2>
        <p>Start with blockers and queues that need action now.</p>
      </div>
      <span class="badge neutral">Exception-led</span>
    </div>
    ${renderControlBoardIssueStripHtml()}`;
  bindControlBoardIssueActions(host);
}

function bindControlBoardIssueActions(root = document) {
  $$('[data-control-issue]', root).forEach(button => button.addEventListener('click', () => handleControlBoardIssueAction(button.dataset.controlIssue)));
}

function handleControlBoardIssueAction(action = '') {
  if (action === 'parts-stoppage') {
    showView('parts');
    const select = $('#parts-status-filter');
    if (select) select.value = 'stoppage';
    renderPartsHome();
    return;
  }
  if (action === 'rft-blocked') {
    showView('rft');
    const select = $('#rft-status-filter');
    if (select) select.value = 'blocked';
    renderRftHome();
    return;
  }
  if (action === 'pmb-unallocated') {
    app.quickFilter = 'pmb';
    app.pmbSubFilter = PMB_STAGE_UNASSIGNED_FILTER;
    app.activePmbBayStage = '';
    showView('workflow');
    return;
  }
  if (action === 'pmb-blocked') {
    app.quickFilter = 'pmb';
    app.pmbSubFilter = '';
    app.activePmbBayStage = '';
    showView('workflow');
    return;
  }
  if (action === 'yardhold-ready') {
    showView('dashboard');
    const bucket = $('#incoming-bucket-filter');
    if (bucket) bucket.value = 'yardhold';
    renderIncomingDashboardBoard();
  }
}

function filteredVehicles() {
  const q = ($('#search')?.value || '').trim().toLowerCase();
  const columnFilters = app.columnFilters || {};
  const status = columnFilters.status || '';
  const sales = columnFilters.sales || '';
  const production = columnFilters.production || '';
  const source = $('#source-filter')?.value || '';
  const jita = columnFilters.jita || '';
  return app.data.filter(v => {
    const productionLabel = productionMonthLabel(v.prodMth || v.productionMonth || '');
    const hay = [v.stock, v.order, v.client, v.toyotaCustomer, displayVehicle(v), v.vehicle, v.toyotaVehicle, v.toyotaStatus, pdcLocationLabel(v.pdcLocation), pmbStageLabel(inferredPmbStage(v)), pmbRequirementText(v), pdcCompletedJobsText(v), pdcOutstandingJobsText(v), isPdcBlocked(v) ? 'blocked' : '', pdcBlockReason(v), pmbStageAgeLabel(v), v.deliveryDate, v.etaAtDealer, productionLabel, v.prodMth, v.autocareVin, v.autocareBatch, v.autocareLoadNumber, v.navisionDealerComments, v.financeNote, v.navisionVehicleNote, consultantName(v), salesPersonInitials(consultantName(v)), v.source, v.internalStatus, ...(v.poTasks || [])].join(' ').toLowerCase();
    const matchesQuery = !q || hay.includes(q);
    const matchesStatus = !status || v.toyotaStatus === status;
    const matchesSales = !sales || salesPersonInitials(consultantName(v)) === sales;
    const matchesProduction = !production || productionLabel === production;
    const matchesSource = !source || v.source === source;
    const matchesJita = !jita || normalizeJita(jitaDisplay(v)) === jita;
    const matchesQuick = !app.quickFilter || matchesQuickFilter(app.quickFilter)(v);
    const currentPmbStage = inferredPmbStage(v);
    const matchesPmbSub = !app.pmbSubFilter || (app.quickFilter === 'pmb' && (app.pmbSubFilter === PMB_STAGE_UNASSIGNED_FILTER ? !currentPmbStage : currentPmbStage === app.pmbSubFilter));
    return matchesQuery && matchesStatus && matchesSales && matchesProduction && matchesSource && matchesJita && matchesQuick && matchesPmbSub;
  });
}


function normalizedVehicleTableColumnOrder(order = []) {
  const defaultIds = VEHICLE_TABLE_DEFAULT_COLUMN_IDS.slice();
  const validIds = new Set(defaultIds);
  const normalized = [];
  (Array.isArray(order) ? order : []).forEach(id => {
    const clean = String(id || '').trim();
    if (validIds.has(clean) && !normalized.includes(clean)) normalized.push(clean);
  });
  defaultIds.forEach(id => {
    if (!normalized.includes(id)) normalized.push(id);
  });
  return normalized;
}

function loadVehicleTableColumnOrder() {
  try {
    return normalizedVehicleTableColumnOrder(JSON.parse(localStorage.getItem(VEHICLE_TABLE_COLUMN_ORDER_KEY) || '[]'));
  } catch {
    return normalizedVehicleTableColumnOrder([]);
  }
}

function saveVehicleTableColumnOrder(order = []) {
  localStorage.setItem(VEHICLE_TABLE_COLUMN_ORDER_KEY, JSON.stringify(normalizedVehicleTableColumnOrder(order)));
}

function moveVehicleTableColumn(draggedId, targetId) {
  if (!draggedId || !targetId || draggedId === targetId) return;
  const order = loadVehicleTableColumnOrder();
  const fromIndex = order.indexOf(draggedId);
  const toIndex = order.indexOf(targetId);
  if (fromIndex === -1 || toIndex === -1) return;
  order.splice(fromIndex, 1);
  const adjustedToIndex = order.indexOf(targetId);
  order.splice(adjustedToIndex, 0, draggedId);
  saveVehicleTableColumnOrder(order);
  renderVehicleTable();
}

function applyVehicleTableColumnOrder(table) {
  if (!table) return;
  const order = loadVehicleTableColumnOrder();
  const orderSet = new Set(order);
  table.querySelectorAll('thead tr, tbody tr').forEach(row => {
    const cells = Array.from(row.children);
    if (!cells.some(cell => cell.dataset?.colId)) return;
    const byId = new Map();
    cells.forEach(cell => {
      const id = cell.dataset?.colId;
      if (id && !byId.has(id)) byId.set(id, cell);
    });
    order.forEach(id => {
      const cell = byId.get(id);
      if (cell) row.appendChild(cell);
    });
    cells.forEach(cell => {
      const id = cell.dataset?.colId;
      if (!id || !orderSet.has(id)) row.appendChild(cell);
    });
  });
}

function makeVehicleColumnsReorderable(table) {
  if (!table) return;
  const headers = Array.from(table.querySelectorAll('thead th[data-col-id]'));
  headers.forEach(th => {
    const colId = th.dataset.colId;
    if (!colId) return;
    th.classList.add('reorderable-column');
    th.addEventListener('dragover', event => {
      event.preventDefault();
      th.classList.add('column-drop-target');
      event.dataTransfer.dropEffect = 'move';
    });
    th.addEventListener('dragleave', () => th.classList.remove('column-drop-target'));
    th.addEventListener('drop', event => {
      event.preventDefault();
      event.stopPropagation();
      th.classList.remove('column-drop-target');
      const draggedId = event.dataTransfer.getData('application/x-vehicle-column') || event.dataTransfer.getData('text/plain');
      moveVehicleTableColumn(draggedId, colId);
    });
    let handle = th.querySelector(':scope > .col-drag-handle');
    if (!handle) {
      handle = document.createElement('span');
      handle.className = 'col-drag-handle';
      handle.textContent = '↔';
      handle.title = 'Drag this column left or right';
      handle.setAttribute('aria-label', 'Drag column left or right');
      th.appendChild(handle);
    }
    handle.draggable = true;
    handle.dataset.dragColumnId = colId;
    handle.addEventListener('click', event => event.stopPropagation());
    handle.addEventListener('mousedown', event => event.stopPropagation());
    handle.addEventListener('dragstart', event => {
      event.stopPropagation();
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('application/x-vehicle-column', colId);
      event.dataTransfer.setData('text/plain', colId);
      table.classList.add('column-reorder-active');
      th.classList.add('column-dragging');
    });
    handle.addEventListener('dragend', () => {
      table.classList.remove('column-reorder-active');
      document.querySelectorAll('.column-drop-target, .column-dragging').forEach(el => el.classList.remove('column-drop-target', 'column-dragging'));
    });
  });
}

function resetVehicleTableColumnOrder() {
  localStorage.removeItem('vehicleTrackingCoreColumnOrder:v1');
  localStorage.removeItem('vehicleTrackingCoreColumnOrder:v2');
  localStorage.removeItem('vehicleTrackingCoreColumnOrder:v3');
  localStorage.removeItem('vehicleTrackingCoreColumnWidths:v1:vehicle-table');
  localStorage.removeItem('vehicleTrackingCoreColumnWidths:v4:vehicle-table');
    localStorage.removeItem('vehicleTrackingCoreColumnWidths:v4:vehicle-table');
  renderVehicleTable();
}

function renderVehicleTable() {
  const rows = sortRows(filteredVehicles());
  renderQuickFilterBanner(rows.length);
  const table = $('#vehicle-table');
  if (!table) return;
  table.classList.add('compact-table');
  if (!rows.length) {
    const emptyHtml = app.data.length
      ? $('#empty-state').innerHTML
      : '<div class="empty-state"><strong>No Navision vehicles loaded yet</strong><span>Upload or paste your first Navision export to populate the tracker.</span><button class="primary" type="button" data-empty-navision-upload>Upload Navision text</button></div>';
    table.innerHTML = `<tbody><tr><td colspan="17">${emptyHtml}</td></tr></tbody>`;
    on($('[data-empty-navision-upload]', table), 'click', () => showView('import'));
    updateBulkSelectionPanel([]);
    return;
  }
  table.innerHTML = `
    <thead><tr>
      <th class="sp-col" data-col-id="sp">${columnFilterSlot('sales', app.filterOptions.consultants, app.columnFilters.sales, 'All SP')}<div class="sp-select-head"><input type="checkbox" data-select-visible aria-label="Select all visible vehicles" />${sortableTh('SP', 'consultant')}</div></th>
      <th data-col-id="stock">${emptyColumnFilterSlot()}${sortableTh('SN', 'stock')}</th>
      <th class="production-month-col" data-col-id="prodMth">${columnFilterSlot('production', app.filterOptions.productionMonths, app.columnFilters.production, 'All P/Month')} ${sortableTh('P/Month', 'prodMth')}</th>
      <th data-col-id="client">${emptyColumnFilterSlot()}${sortableTh('Client', 'client')}</th>
      <th data-col-id="vehicle">${emptyColumnFilterSlot()}${sortableTh('Vehicle', 'vehicle')}</th>
      <th class="flag-col pdc-job-col pdc-col-tint" data-col-id="tint" title="Tint required">${emptyColumnFilterSlot()}${sortableTh('T', 'pdcRequiresTint')}</th>
      <th class="flag-col pdc-job-col pdc-col-hoist" data-col-id="hoist" title="Hoist required">${emptyColumnFilterSlot()}${sortableTh('H', 'pdcRequiresHoist')}</th>
      <th class="flag-col pdc-job-col pdc-col-fitting" data-col-id="fitting" title="Fitting required">${emptyColumnFilterSlot()}${sortableTh('F', 'pdcRequiresFitting')}</th>
      <th class="flag-col pdc-job-col pdc-col-fabrication" data-col-id="fabrication" title="Fabrication required">${emptyColumnFilterSlot()}${sortableTh('Fa', 'pdcRequiresFabrication')}</th>
      <th class="flag-col pdc-job-col pdc-col-electrical" data-col-id="electrical" title="Electrical required">${emptyColumnFilterSlot()}${sortableTh('E', 'pdcRequiresElectrical')}</th>
      <th class="flag-col pdc-job-col pdc-col-tyre" data-col-id="tyre" title="Tyre required">${emptyColumnFilterSlot()}${sortableTh('Ty', 'pdcRequiresTyre')}</th>
      <th class="flag-col pdc-job-col pdc-col-pitInspection" data-col-id="pitInspection" title="Pit Inspection required">${emptyColumnFilterSlot()}${sortableTh('PI', 'pdcRequiresPitInspection')}</th>
      <th data-col-id="status">${columnFilterSlot('status', app.filterOptions.statuses, app.columnFilters.status, 'All statuses')}${sortableTh('Toyota Status', 'toyotaStatus')}</th>
      <th data-col-id="eta">${emptyColumnFilterSlot()}${sortableTh('ETA', 'eta')}</th>
      <th class="navision-notes-full-col" data-col-id="navisionNotes" title="Full Navision Notes from Dealer Comments">${emptyColumnFilterSlot()}${sortableTh('Navision Notes', 'navisionNotes')}</th>
      <th data-col-id="jita">${columnFilterSlot('jita', [{ value: 'Yes', label: '✓ Tick' }, { value: 'No', label: '× Cross' }, { value: 'Unknown', label: 'Unknown' }], app.columnFilters.jita, 'All')}${sortableTh('JITA', 'jita')}</th>
      <th data-col-id="action">${emptyColumnFilterSlot()}<span class="plain-header-label">Action</span></th>
    </tr></thead>
    <tbody>
      ${rows.map(v => {
        const key = vehicleKey(v);
        const rowClasses = [
          app.selectedRows.has(key) ? 'row-selected' : '',
          isAutocareDespatched(v) ? 'autocare-row' : '',
          isNavisionCutButVehicle(v) ? 'cut-but-vehicle-row' : '',
          isPdcBlocked(v) ? 'pdc-blocked-row' : '',
        ].filter(Boolean).join(' ');
        const pmbDragAttrs = statusCategory(v) === 'pmb' ? ` draggable="true" data-pmb-table-drag-key="${escapeHtml(key)}" title="Drag this PMB vehicle to a PMB bucket"` : '';
        return `
        <tr class="${rowClasses}" data-stock="${escapeHtml(key)}"${pmbDragAttrs}>
          <td class="sp-cell" data-col-id="sp"><label class="row-selector" title="Select ${escapeHtml(displayStockNumber(v) || v.order || 'vehicle')}"><input type="checkbox" data-select-stock="${escapeHtml(key)}" ${app.selectedRows.has(key) ? 'checked' : ''} /><span><strong title="${escapeHtml(consultantName(v))}">${escapeHtml(salesPersonInitials(consultantName(v)))}</strong></span></label></td>
          <td class="stock-cell" data-col-id="stock">${vehicleIdentityStackHtml(v, { button: true })}${stockOrderSubline(v)}${v.toyotaCustomer && !isCustomerMatch(v) ? `<div class="subtle review-warning">Check customer</div>` : ''}</td>
          <td class="production-month-cell" data-col-id="prodMth"><span>${escapeHtml(productionMonthLabel(v.prodMth || v.productionMonth || ''))}</span></td>
          <td class="client-cell" data-col-id="client"><span title="${escapeHtml(vehicleCustomerName(v) || '')}">${escapeHtml(vehicleCustomerName(v) || '')}</span></td>
          <td data-col-id="vehicle"><span class="vehicle-cell">${escapeHtml(displayVehicle(v))}</span></td>
          <td class="flag-cell pdc-job-cell" data-col-id="tint">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('tint'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="hoist">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('hoist'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="fitting">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('fitting'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="fabrication">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('fabrication'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="electrical">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('electrical'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="tyre">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('tyre'))}</td>
          <td class="flag-cell pdc-job-cell" data-col-id="pitInspection">${pdcJobTableCell(v, PDC_JOB_BY_KEY.get('pitInspection'))}</td>
          <td data-col-id="status">${formatStatus(v)}${isPdcBlocked(v) ? `<div class="pdc-blocked-inline">Blocked: ${escapeHtml(truncate(pdcBlockReason(v), 42))}</div>` : ''}${statusCategory(v) === 'pmb' ? `<div class="pmb-stage-cell">${pmbStageBadge(v) || '<span class="subtle">PMB stage not allocated</span>'}</div>` : ''}${!isCustomerMatch(v) ? '<div class="subtle review-warning">Check customer match</div>' : ''}</td>
          <td data-col-id="eta">${formatEta(v.etaAtDealer)}</td>
          <td class="navision-notes-full-cell" data-col-id="navisionNotes"><span title="${escapeHtml(navisionDealerNoteText(v))}">${escapeHtml(truncate(navisionDealerNoteText(v), 90))}</span></td>
          <td data-col-id="jita">${jitaIndicator(v)}</td>
          <td data-col-id="action">${actionSelectHtml(key)}</td>
        </tr>
      `; }).join('')}
    </tbody>
  `;
  applyVehicleTableColumnOrder(table);
  bindColumnFilterControls(table);
  makeVehicleColumnsReorderable(table);
  $$('[data-sort-key]', table).forEach(btn => btn.addEventListener('click', () => setSort(btn.dataset.sortKey)));
  const visibleKeys = rows.map(vehicleKey).filter(Boolean);
  if (app.quickFilter) {
    const visibleKeySet = new Set(visibleKeys);
    [...app.selectedRows].forEach(key => { if (!visibleKeySet.has(key)) app.selectedRows.delete(key); });
  }
  const selectAllVisible = $('[data-select-visible]', table);
  if (selectAllVisible) {
    const selectedVisible = visibleKeys.filter(key => app.selectedRows.has(key)).length;
    selectAllVisible.checked = visibleKeys.length > 0 && selectedVisible === visibleKeys.length;
    selectAllVisible.indeterminate = selectedVisible > 0 && selectedVisible < visibleKeys.length;
    selectAllVisible.addEventListener('click', e => e.stopPropagation());
    selectAllVisible.addEventListener('change', () => {
      visibleKeys.forEach(key => {
        if (selectAllVisible.checked) app.selectedRows.add(key);
        else app.selectedRows.delete(key);
      });
      renderVehicleTable();
    });
  }
  $$('[data-select-stock]', table).forEach(input => {
    input.addEventListener('click', e => e.stopPropagation());
    input.addEventListener('change', () => {
      const key = input.dataset.selectStock;
      if (!key) return;
      if (input.checked) app.selectedRows.add(key);
      else app.selectedRows.delete(key);
      renderVehicleTable();
    });
  });
  $$('[data-open-stock]', table).forEach(btn => btn.addEventListener('click', (e) => {
    e.stopPropagation();
    openVehicleModal(btn.dataset.openStock);
  }));
  $$('[data-task-stock]', table).forEach(select => {
    select.addEventListener('click', (e) => e.stopPropagation());
    select.addEventListener('change', () => {
      saveVehicleEdits(select.dataset.taskStock, { internalStatus: select.value });
    });
  });
  $$('[data-flag-stock]', table).forEach(input => {
    input.addEventListener('click', (e) => e.stopPropagation());
    input.addEventListener('change', () => {
      const vehicle = selectedVehicle(input.dataset.flagStock);
      const def = pdcJobDefinitionForKey(input.dataset.flagKey);
      const isCompletionFlag = PDC_JOB_BY_COMPLETE_KEY.has(input.dataset.flagKey);
      const updates = { [input.dataset.flagKey]: input.checked };
      if (isCompletionFlag && def) {
        updates[def.requireKey] = true;
        updates[def.completeAtKey] = input.checked ? nowIsoString() : '';
        updates[def.completeByKey] = input.checked ? getCurrentOperatorName() : '';
      }
      if (vehicle && def) {
        recordVehicleAudit(vehicle, isCompletionFlag ? (input.checked ? 'Job signed off from RFT table' : 'Job sign-off removed from RFT table') : (input.checked ? 'Requirement added' : 'Requirement removed'), { job: def.label });
      }
      saveVehicleEdits(input.dataset.flagStock, updates);
    });
  });
  $$('[data-action-stock]', table).forEach(select => {
    select.addEventListener('click', (e) => e.stopPropagation());
    select.addEventListener('change', () => {
      if (!select.value) return;
      handleVehicleAction(select.dataset.actionStock, select.value);
      select.value = '';
    });
  });
  bindPmbTableRowDragging(table);
  updateBulkSelectionPanel(rows);
  makeTableResizable(table);
  setupFrozenVehicleHeader(table);
}


function removeVehiclesFromTracker(vehicles = []) {
  const list = vehicles.filter(Boolean);
  if (!list.length) return [];
  const deleted = new Set(loadDeletedVehicles());
  let added = loadAddedVehicles();
  const edits = loadVehicleEdits();
  const poTasks = loadPoTasks();
  const poFiles = loadPoFiles();
  const removedKeys = new Set();
  const exactRemovalKeys = new Set();

  list.forEach(vehicle => {
    const exactKeys = [
      vehicleDeleteKey(vehicle),
      vehicleKey(vehicle),
      vehicle.stock,
      vehicle.batch,
      vehicle.order,
      vehicle.id,
    ].map(value => String(value || '').trim()).filter(Boolean);

    const vin = normalizeVin(vehicle.vin || vehicle.fullVin || vehicle.frameVin || vehicle.autocareVin || '');
    const allDeleteKeys = exactKeys.concat(vin ? [vin] : []);

    exactKeys.forEach(key => exactRemovalKeys.add(key));
    allDeleteKeys.forEach(key => {
      deleted.add(key);
      removedKeys.add(key);
      delete edits[key];
      delete poTasks[key];
      delete poFiles[key];
    });
  });

  // Do not use broad Navision comparable keys here. Frame/order fragments can overlap
  // across multiple imported rows, which previously caused one manual delete to remove
  // a group of unrelated vehicles from the saved Navision list.
  added = added.filter(vehicle => {
    const keys = [
      vehicleDeleteKey(vehicle),
      vehicleKey(vehicle),
      vehicle.stock,
      vehicle.batch,
      vehicle.order,
      vehicle.id,
    ].map(value => String(value || '').trim()).filter(Boolean);
    return !keys.some(key => exactRemovalKeys.has(key));
  });

  saveDeletedVehicles([...deleted]);
  saveAddedVehicles(added);
  saveJson(EDITS_KEY, edits);
  savePoTasks(poTasks);
  savePoFiles(poFiles);
  return list;
}

function refreshAfterVehicleRemoval() {
  app.selectedRows.clear();
  app.data = buildVehicleData();
  app.selectedStock = app.data[0] ? vehicleKey(app.data[0]) : null;
  populateFilters();
  renderAll();
  updateNavisionSidebarMeta();
}


function selectedVehiclesForBulkEmail() {
  if (!app.selectedRows || !app.selectedRows.size) return [];
  return [...app.selectedRows]
    .map(key => app.data.find(vehicle => vehicleKey(vehicle) === key || vehicle.stock === key || vehicle.order === key || vehicle.id === key))
    .filter(Boolean);
}

function updateBulkSelectionPanel(visibleRows = []) {
  const validKeys = new Set(app.data.map(vehicleKey));
  [...app.selectedRows].forEach(key => { if (!validKeys.has(key)) app.selectedRows.delete(key); });
  const selected = selectedVehiclesForBulkEmail();
  const count = selected.length;
  const countEl = $('#selection-count');
  const emailButtons = ['#email-selected-amy', '#email-selected-amy-bar'].map(selector => $(selector)).filter(Boolean);
  const clearButtons = ['#clear-selected-rows', '#clear-selected-rows-bar'].map(selector => $(selector)).filter(Boolean);
  const deleteButtons = ['#delete-selected-vehicles', '#delete-selected-vehicles-bar'].map(selector => $(selector)).filter(Boolean);
  const overrideYhButtons = ['#override-selected-to-yh-bar', '#override-selected-to-yh-top'].map(selector => $(selector)).filter(Boolean);
  const transferButtons = ['#transfer-selected-to-pmb-bar', '#transfer-selected-to-pmb-top'].map(selector => $(selector)).filter(Boolean);
  const transferRftButtons = ['#transfer-selected-to-rft-bar'].map(selector => $(selector)).filter(Boolean);
  const printButtons = $$('[data-print-selected-zpl]');
  const bar = $('#bulk-selection-bar');
  if (countEl) {
    countEl.hidden = count === 0;
    countEl.textContent = `${count} selected`;
  }
  if (bar) bar.classList.toggle('active', count > 0);
  emailButtons.forEach(button => { button.disabled = count === 0; });
  clearButtons.forEach(button => { button.disabled = count === 0; });
  deleteButtons.forEach(button => {
    button.disabled = count === 0;
    button.title = count ? `Delete ${count} selected vehicle${count === 1 ? '' : 's'} from this tracker` : 'Select one or more vehicles first';
  });
  printButtons.forEach(button => {
    button.disabled = count === 0;
    button.title = count ? `Print ${count} selected vehicle label${count === 1 ? '' : 's'} to the Zebra printer` : 'Select one or more vehicles first';
  });
  overrideYhButtons.forEach(button => {
    const canOverride = count > 0;
    button.disabled = !canOverride;
    button.title = canOverride
      ? `Manually set ${count} selected vehicle${count === 1 ? '' : 's'} to Yard Hold so they can be transferred to PMB`
      : 'Select one or more vehicles first';
  });
  const pmbSelectedCount = selected.filter(vehicle => statusCategory(vehicle) === 'pmb').length;
  const rftSelectedCount = selected.filter(vehicle => statusCategory(vehicle) === 'rft').length;
  const incomingPmbReadyCount = selected.filter(canTransferVehicleToPmb).length;
  const canTransferSelectedToPmb = count > 0 && pmbSelectedCount === 0 && rftSelectedCount === 0 && incomingPmbReadyCount === count;
  transferButtons.forEach(button => {
    button.disabled = !canTransferSelectedToPmb;
    button.title = !count
      ? 'Select one or more Yard Hold or In Transit vehicles first'
      : canTransferSelectedToPmb
        ? `Transfer ${count} selected vehicle${count === 1 ? '' : 's'} to PMB`
        : 'Only vehicles currently at Yard Hold or In Transit can be bulk-transferred to PMB';
  });
  transferRftButtons.forEach(button => {
    const gateIssueRows = vehiclesWithRftGateIssues(selected);
    const canTransfer = count > 0 && pmbSelectedCount === count && gateIssueRows.length === 0;
    button.disabled = !canTransfer;
    button.title = !count
      ? 'Select one or more PMB vehicles first'
      : pmbSelectedCount !== count
        ? 'Only vehicles currently at PMB can be bulk-transferred to RFT'
        : gateIssueRows.length
          ? 'RFT locked: all required boxes must be signed off first'
          : `Transfer ${count} selected PMB vehicle${count === 1 ? '' : 's'} to RFT`;
  });

  const table = $('#vehicle-table');
  const selectAllVisible = table ? $('[data-select-visible]', table) : null;
  if (selectAllVisible && visibleRows.length) {
    const visibleKeys = visibleRows.map(vehicleKey).filter(Boolean);
    const selectedVisible = visibleKeys.filter(key => app.selectedRows.has(key)).length;
    selectAllVisible.checked = selectedVisible === visibleKeys.length;
    selectAllVisible.indeterminate = selectedVisible > 0 && selectedVisible < visibleKeys.length;
  }
}

function clearSelectedRows() {
  app.selectedRows.clear();
  renderAll();
  updateInlineSelectionBars();
}

function deleteSelectedVehicles() {
  const vehicles = selectedVehiclesForBulkEmail();
  if (!vehicles.length) return;
  const label = `${vehicles.length} selected vehicle${vehicles.length === 1 ? '' : 's'}`;
  const preview = vehicles.slice(0, 8).map(vehicle => `• ${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`).join('\n');
  const more = vehicles.length > 8 ? `\n• plus ${vehicles.length - 8} more` : '';
  if (!window.confirm(`Delete ${label} from the tracker?\n\n${preview}${more}\n\nThis hides them from the prototype and keeps the delete list in this browser.`)) return;

  removeVehiclesFromTracker(vehicles);
  app.selectedRows.clear();
  refreshAfterVehicleRemoval();
}


function overrideSelectedVehiclesToYh() {
  const selected = selectedVehiclesForBulkEmail();
  if (!selected.length) return;
  const preview = selected.slice(0, 10).map(vehicle => `• ${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'} - ${pdcLocationLabel(vehiclePdcLocation(vehicle)) || statusCategory(vehicle)}`).join('\n');
  const more = selected.length > 10 ? `\n• plus ${selected.length - 10} more` : '';
  if (!window.confirm(`Manually override ${selected.length} selected vehicle${selected.length === 1 ? '' : 's'} to Vehicles at YH?\n\n${preview}${more}\n\nThis lets you move them to PMB and protects the manual Yard Hold location from future Navision location changes until you change it again.`)) return;

  const now = nowIsoString();
  const edits = loadVehicleEdits();

  selected.forEach(vehicle => {
    const key = vehicleKey(vehicle);
    if (!key) return;
    const updates = {
      pdcLocation: 'YH',
      manualLocation: 'YH',
      pdcLocationLocked: true,
      navisionLocationLocked: true,
      pdcLocationUpdatedAt: now,
      pmbStage: '',
      pmbStageEnteredAt: '',
      pmbStageUpdatedAt: '',
      pmbBayStage: '',
      pmbBayNumber: '',
      pmbBayEstimatedHours: '',
      pmbBayEnteredAt: '',
      pmbBayScheduledStartAt: '',
      pmbBayCompletedAt: '',
      pmbBayCompletedBy: '',
      pmbBayCompletedStage: '',
      pmbBayMechanic: '',
      pmbSubletProvider: '',
    };
    Object.assign(vehicle, updates);
    edits[key] = { ...(edits[key] || {}), ...updates };
    if (vehicle.stock && vehicle.stock !== key) edits[vehicle.stock] = { ...(edits[vehicle.stock] || {}), ...updates };
    if (vehicle.order && vehicle.order !== key) edits[vehicle.order] = { ...(edits[vehicle.order] || {}), ...updates };
    recordVehicleAudit(vehicle, 'Manual override to YH', { to: 'Yard Hold', protectedFromNavision: 'Yes' });
  });

  saveJson(EDITS_KEY, edits);
  app.selectedRows.clear();
  app.quickFilter = 'yardhold';
  app.pmbSubFilter = '';
  app.activePmbBayStage = '';
  app.data = buildVehicleData();
  populateFilters();
  renderAll();
}


function canTransferVehicleToPmb(vehicle) {
  if (!vehicle) return false;
  const current = statusCategory(vehicle);
  if (current === 'pmb' || current === 'rft' || current === 'completed') return false;
  if (current === 'yardhold' || current === 'prodtransit') return true;
  const text = [
    navisionStatusText(vehicle),
    vehicle.status,
    vehicle.toyotaStatus,
  ].map(value => String(value || '').toLowerCase()).join(' ');
  if (text.includes('yard hold') || text.includes('vehicle in yard hold') || text.includes('vehicle yard hold') || /\byh\b/.test(text)) return true;
  if (text.includes('in transit') || text.includes('production transit') || /\bit\b/.test(text)) return true;
  return app.quickFilter === 'yardhold' || app.quickFilter === 'prodtransit';
}


function pmbRequirementChecklistModal(vehicles = []) {
  const rows = vehicles.filter(Boolean);
  if (!rows.length) return Promise.resolve(null);
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay pmb-requirement-modal-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'pmb-requirement-modal-title');
    const previewRows = rows.map((vehicle, index) => {
      const key = vehicleKey(vehicle);
      const checks = PDC_JOB_DEFS.map(def => {
        const checked = pdcJobRequired(vehicle, def) ? 'checked' : '';
        return `<label class="check-option pdc-toggle-chip pdc-toggle-${escapeHtml(def.key)} ${checked ? 'is-on' : ''}"><input type="checkbox" data-pmb-requirement-row="${index}" data-pmb-requirement-key="${escapeHtml(def.key)}" ${checked} /> <span><b>${escapeHtml(def.short)}</b>${escapeHtml(def.label)}</span></label>`;
      }).join('');
      return `<article class="pmb-requirement-row" data-pmb-requirement-vehicle="${escapeHtml(key)}"><div>${vehicleIdentityStackHtml(vehicle)}<small>${escapeHtml(truncate(displayVehicle(vehicle), 52))}</small></div><div class="form-row six-col check-grid slim-job-grid">${checks}</div></article>`;
    }).join('');
    overlay.innerHTML = `
      <section class="modal-card pmb-requirement-modal-card">
        <button class="modal-close" type="button" data-pmb-requirement-cancel aria-label="Cancel PMB transfer">×</button>
        <div class="panel-header">
          <div>
            <h2 id="pmb-requirement-modal-title">Confirm PMB required work</h2>
            <p>Before releasing Yard Hold/In Transit vehicles into PMB, tick what each vehicle needs: ${escapeHtml(currentPdcJobLabelList())}.</p>
          </div>
          <span class="badge neutral">${rows.length} vehicle${rows.length === 1 ? '' : 's'}</span>
        </div>
        <div class="pmb-requirement-modal-body">${previewRows}</div>
        <div class="edit-actions pmb-requirement-actions">
          <button class="primary" type="button" data-pmb-requirement-confirm>Confirm and transfer to PMB</button>
          <button class="ghost" type="button" data-pmb-requirement-cancel>Cancel</button>
        </div>
      </section>`;
    const cleanup = result => {
      overlay.remove();
      document.body.classList.remove('modal-open');
      resolve(result);
    };
    overlay.addEventListener('click', event => {
      if (event.target === overlay || event.target.closest('[data-pmb-requirement-cancel]')) cleanup(null);
      const checkbox = event.target.closest('[data-pmb-requirement-key]');
      if (checkbox) checkbox.closest('.pdc-toggle-chip')?.classList.toggle('is-on', checkbox.checked);
      if (event.target.closest('[data-pmb-requirement-confirm]')) {
        const selections = new Map();
        rows.forEach((vehicle, index) => {
          const updates = {};
          PDC_JOB_DEFS.forEach(def => {
            const input = overlay.querySelector(`[data-pmb-requirement-row="${index}"][data-pmb-requirement-key="${def.key}"]`);
            updates[def.requireKey] = Boolean(input?.checked);
          });
          selections.set(vehicleKey(vehicle), updates);
        });
        cleanup(selections);
      }
    });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    overlay.querySelector('[data-pmb-requirement-confirm]')?.focus();
  });
}

async function transferSelectedYhVehiclesToPmb() {
  const selected = selectedVehiclesForBulkEmail();
  if (!selected.length) return;

  const transferable = selected.filter(canTransferVehicleToPmb);
  const nonYh = selected.filter(vehicle => !canTransferVehicleToPmb(vehicle));
  if (!transferable.length) {
    window.alert('No selected Yard Hold or In Transit vehicles could be transferred. Clear selection, open Yard Hold/In Transit, then select the rows again.');
    return;
  }
  if (nonYh.length && !window.confirm(`${nonYh.length} selected vehicle${nonYh.length === 1 ? ' is' : 's are'} not at Yard Hold/In Transit and will be skipped.\n\nTransfer the ${transferable.length} Yard Hold/In Transit vehicle${transferable.length === 1 ? '' : 's'} to PMB?`)) return;

  const preview = transferable.slice(0, 10).map(vehicle => `• ${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`).join('\n');
  const more = transferable.length > 10 ? `\n• plus ${transferable.length - 10} more` : '';
  if (!window.confirm(`Transfer ${transferable.length} Yard Hold/In Transit vehicle${transferable.length === 1 ? '' : 's'} to Vehicles at PMB?\n\n${preview}${more}\n\nThis is a manual PDC location change. Future Navision uploads will not move these vehicles back.`)) return;

  const requirementSelections = await pmbRequirementChecklistModal(transferable);
  if (!requirementSelections) return;

  const transferTime = nowIsoString();
  const edits = loadVehicleEdits();

  transferable.forEach(vehicle => {
    const key = vehicleKey(vehicle);
    if (!key) return;
    const updates = {
      pdcLocation: 'PMB',
      manualLocation: 'PMB',
      pdcLocationLocked: true,
      navisionLocationLocked: true,
      pmbEnteredAt: pmbEnteredTimestamp(vehicle) || transferTime,
      pmbTransferredAt: vehicle.pmbTransferredAt || transferTime,
      pdcLocationUpdatedAt: transferTime,
      pmbStage: '',
      pdcWorkStage: '',
      workStage: '',
      pmbStageEnteredAt: '',
      pmbStageUpdatedAt: '',
      pmbBayStage: '',
      pmbBayNumber: '',
      pmbBayEstimatedHours: '',
      pmbBayEnteredAt: '',
      pmbBayScheduledStartAt: '',
      pmbBayCompletedAt: '',
      pmbBayCompletedBy: '',
      pmbBayCompletedStage: '',
      pmbBayMechanic: '',
      pmbSubletProvider: '',
      ...(requirementSelections.get(key) || {}),
    };

    Object.assign(vehicle, updates);
    edits[key] = { ...(edits[key] || {}), ...updates };
    if (vehicle.stock && vehicle.stock !== key) edits[vehicle.stock] = { ...(edits[vehicle.stock] || {}), ...updates };
    if (vehicle.order && vehicle.order !== key) edits[vehicle.order] = { ...(edits[vehicle.order] || {}), ...updates };
    recordVehicleAudit(vehicle, 'Transferred to PMB', { from: pdcLocationLabel(vehiclePdcLocation(vehicle)) || 'Incoming', to: 'PMB - Unallocated', protectedFromNavision: 'Yes' });
  });

  saveJson(EDITS_KEY, edits);
  app.selectedRows.clear();
  app.quickFilter = 'pmb';
  app.pmbSubFilter = '';
  app.activePmbBayStage = '';
  app.data = buildVehicleData();
  populateFilters();
  renderAll();
}

async function transferYhVehicleToPmb(key = '') {
  const vehicle = app.data.find(v => vehicleKey(v) === key || v.stock === key || v.order === key || v.id === key);
  if (!vehicle) return;
  if (!canTransferVehicleToPmb(vehicle)) {
    window.alert('Only Yard Hold or In Transit vehicles can be transferred to PMB from this button.');
    return;
  }
  const stock = displayStockNumber(vehicle) || vehicle.order || 'No stock';
  const customer = vehicleCustomerName(vehicle) || 'Unknown customer';
  if (!window.confirm(`Transfer ${stock} - ${customer} to PMB?\n\nThis is a manual PDC location change. Future Navision uploads will not move it back.`)) return;

  const requirementSelections = await pmbRequirementChecklistModal([vehicle]);
  if (!requirementSelections) return;

  const transferTime = nowIsoString();
  const edits = loadVehicleEdits();
  const rowKey = vehicleKey(vehicle);
  const updates = {
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    navisionLocationLocked: true,
    pmbEnteredAt: pmbEnteredTimestamp(vehicle) || transferTime,
    pmbTransferredAt: vehicle.pmbTransferredAt || transferTime,
    pdcLocationUpdatedAt: transferTime,
    pmbStage: '',
    pdcWorkStage: '',
    workStage: '',
    pmbStageEnteredAt: '',
    pmbStageUpdatedAt: '',
    pmbBayStage: '',
    pmbBayNumber: '',
    pmbBayEstimatedHours: '',
    pmbBayEnteredAt: '',
    pmbBayScheduledStartAt: '',
    pmbBayCompletedAt: '',
    pmbBayCompletedBy: '',
    pmbBayCompletedStage: '',
    pmbBayMechanic: '',
    pmbSubletProvider: '',
    ...(requirementSelections.get(rowKey) || {}),
  };

  Object.assign(vehicle, updates);
  edits[rowKey] = { ...(edits[rowKey] || {}), ...updates };
  if (vehicle.stock && vehicle.stock !== rowKey) edits[vehicle.stock] = { ...(edits[vehicle.stock] || {}), ...updates };
  if (vehicle.order && vehicle.order !== rowKey) edits[vehicle.order] = { ...(edits[vehicle.order] || {}), ...updates };
  recordVehicleAudit(vehicle, 'Transferred to PMB', { from: pdcLocationLabel(vehiclePdcLocation(vehicle)) || 'Incoming', to: 'PMB - Unallocated', protectedFromNavision: 'Yes' });

  saveJson(EDITS_KEY, edits);
  app.quickFilter = 'pmb';
  app.pmbSubFilter = '';
  app.activePmbBayStage = '';
  app.data = buildVehicleData();
  populateFilters();
  renderAll();
}

function transferSelectedPmbVehiclesToRft() {
  const selected = selectedVehiclesForBulkEmail();
  transferVehiclesToRft(selected, { clearSelection: true });
}

function transferVehicleToRftFromCard(key) {
  const vehicle = app.data.find(v => vehicleKey(v) === key || v.stock === key || v.order === key || v.id === key);
  if (!vehicle) return;
  transferVehiclesToRft([vehicle], { clearSelection: false });
}

function confirmRftGateOverride(vehicles = []) {
  const rows = vehiclesWithRftGateIssues(vehicles);
  if (!rows.length) return { allowed: true, overridden: false, reason: '' };
  const issuePreview = rows.slice(0, 12).map(row => {
    const vehicle = row.vehicle;
    return `• ${displayStockNumber(vehicle) || vehicle.order || 'No stock'} - ${row.issues.join('; ')}`;
  }).join('\n');
  const more = rows.length > 12 ? `\n• plus ${rows.length - 12} more with RFT gate issues` : '';
  window.alert(`Cannot transfer to RFT yet.\n\nEvery required PDC box must be signed off before a vehicle can move to RFT.\n\n${issuePreview}${more}`);
  return { allowed: false, overridden: false, reason: '', issueCount: rows.length, issues: rows };
}

function transferVehiclesToRft(vehicles = [], options = {}) {
  const selected = vehicles.filter(Boolean);
  if (!selected.length) return;
  const nonPmb = selected.filter(vehicle => statusCategory(vehicle) !== 'pmb');
  if (nonPmb.length) {
    window.alert('Only vehicles currently at PMB can be transferred to RFT. Clear the selection and select PMB vehicles only.');
    return;
  }
  const gate = confirmRftGateOverride(selected);
  if (!gate.allowed) return;
  const preview = selected.slice(0, 10).map(vehicle => `• ${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'} - ${pmbStageLabel(inferredPmbStage(vehicle)) || 'Unallocated'}`).join('\n');
  const more = selected.length > 10 ? `\n• plus ${selected.length - 10} more` : '';
  if (!window.confirm(`Transfer ${selected.length} PMB vehicle${selected.length === 1 ? '' : 's'} to Vehicles RFT?\n\n${preview}${more}\n\nThis marks the vehicle as Ready for Transport and keeps it protected from Navision location changes.`)) return;

  const transferTime = nowIsoString();
  selected.forEach(vehicle => {
    recordVehicleAudit(vehicle, 'Transferred to RFT', { from: pmbStageLabel(inferredPmbStage(vehicle)) || 'PMB - Unallocated', to: 'RFT', completedJobs: pdcCompletedJobsText(vehicle), outstandingJobs: pdcOutstandingJobsText(vehicle), blocked: isPdcBlocked(vehicle) ? pdcBlockReason(vehicle) : '' });
    saveVehicleEdits(vehicleKey(vehicle), {
      pdcLocation: 'RFT',
      manualLocation: 'RFT',
      pdcLocationLocked: true,
      rftTransferredAt: transferTime,
      pdcLocationUpdatedAt: transferTime,
      pmbEnteredAt: pmbEnteredTimestamp(vehicle) || transferTime,
    });
  });
  if (options.clearSelection) app.selectedRows.clear();
  app.quickFilter = 'rft';
  app.pmbSubFilter = '';
  app.data = buildVehicleData();
  populateFilters();
  renderAll();

}


function salespersonEmail(vehicle = {}) {
  return RFT_SALESPERSON_EMAIL;
}

function draftRftSalespersonNotificationEmail(vehicles = []) {
  const list = vehicles.filter(Boolean);
  if (!list.length) return;
  const body = [
    'Hi Bryce,',
    '',
    list.length === 1 ? 'The following vehicle is complete and ready for transport:' : 'The following vehicles are complete and ready for transport:',
    '',
    list.map(vehicle => {
      const completed = pdcCompletedJobs(vehicle).map(job => {
        const by = vehicle[job.completeByKey] ? ` by ${vehicle[job.completeByKey]}` : '';
        const at = parseIsoTimestamp(vehicle[job.completeAtKey]);
        const atText = at ? ` on ${at.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' })}` : '';
        const mechanic = pdcJobMechanic(vehicle, job) ? ` · mechanic ${pdcJobMechanic(vehicle, job)}` : '';
        const bay = pdcJobBay(vehicle, job) ? ` · bay ${pdcJobBay(vehicle, job)}` : '';
        const hours = pdcJobHours(vehicle, job) ? ` · ${pdcJobHours(vehicle, job)}h` : '';
        return `- ${job.label}${by}${atText}${mechanic}${bay}${hours}`;
      });
      const outstanding = pdcRequirementDefinitions(vehicle).filter(job => !pdcJobComplete(vehicle, job)).map(job => `- ${job.label}`);
      return [
        `Stock number: ${displayStockNumber(vehicle) || 'TBA'}`,
        `Toyota Order: ${vehicle.order || 'TBA'}`,
        `Customer Name: ${vehicleCustomerName(vehicle) || 'TBA'}`,
        `Vehicle: ${displayVehicle(vehicle) || 'TBA'}`,
        `Salesperson: ${consultantName(vehicle) || 'Unassigned'}`,
        `PMB bucket: ${pmbStageLabel(inferredPmbStage(vehicle)) || 'Unallocated'}`,
        `Kewdale ETA age: ${pmbAgeDetailText(vehicle)}`,
        '',
        'Jobs completed:',
        completed.length ? completed.join('\n') : '- No PMB jobs have been ticked as complete in the tracker',
        '',
        'Outstanding jobs at RFT transfer:',
        outstanding.length ? outstanding.join('\n') : '- None recorded',
      ].join('\n');
    }).join('\n\n'),
    '',
    'Status: RFT - Ready for Transport',
    '',
    'Kind Regards,'
  ].join('\n');
  const subject = list.length === 1
    ? `RFT complete - ${displayStockNumber(list[0]) || 'TBA'}`
    : `RFT complete - ${list.length} vehicles`;
  window.location.href = `mailto:${RFT_SALESPERSON_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}


function draftSelectedArrivingVehicleEmail() {
  const vehicles = selectedVehiclesForBulkEmail();
  if (!vehicles.length) return;
  const body = [
    'Hi PDC,',
    '',
    'The following vehicles are arriving:',
    '',
    vehicles.map(vehicle => vehicleEmailLines(vehicle).join('\n')).join('\n\n'),
    '',
    'Kind Regards,'
  ].join('\n');
  const subject = `Vehicles arriving - ${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'}`;
  window.location.href = `mailto:${AMY_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}



const QZ_DEFAULT_PRINTER_NAMES = ['BT-Zebra-EricComp', 'dc-01\\BT-Zebra-EricComp', '192.168.0.164'];
let qzLastPrinterName = localStorage.getItem('vehicleTrackingCoreQzPrinter:v1') || '';

function qzAvailable() {
  return typeof window.qz !== 'undefined' && window.qz.websocket && window.qz.printers && window.qz.configs;
}

async function ensureQzConnected() {
  if (!qzAvailable()) {
    throw new Error('QZ Tray is not available. Check QZ Tray is running, then reload this page.');
  }
  if (!qz.websocket.isActive()) {
    await qz.websocket.connect({ retries: 2, delay: 1 });
  }
}

function printerNameMatches(name = '', target = '') {
  const a = String(name || '').toLowerCase();
  const b = String(target || '').toLowerCase();
  if (!a || !b) return false;
  return a === b || a.includes(b) || b.includes(a);
}

async function findZebraPrinterName() {
  await ensureQzConnected();
  const printers = await qz.printers.find();
  const list = Array.isArray(printers) ? printers : [printers].filter(Boolean);
  const preferred = [qzLastPrinterName, ...QZ_DEFAULT_PRINTER_NAMES].filter(Boolean);
  for (const target of preferred) {
    const match = list.find(name => printerNameMatches(name, target));
    if (match) {
      qzLastPrinterName = match;
      localStorage.setItem('vehicleTrackingCoreQzPrinter:v1', match);
      return match;
    }
  }
  const zebra = list.find(name => /zebra|zdesigner|bt-zebra/i.test(String(name || '')));
  if (zebra) {
    qzLastPrinterName = zebra;
    localStorage.setItem('vehicleTrackingCoreQzPrinter:v1', zebra);
    return zebra;
  }
  if (list.length === 1) return list[0];
  throw new Error(`Could not find BT-Zebra-EricComp. Available printers: ${list.join(', ') || 'none'}`);
}

async function printRawZpl(zpl, sourceLabel = 'labels') {
  const clean = String(zpl || '').trim();
  if (!clean) {
    window.alert('No ZPL labels to print. Generate labels first.');
    return;
  }
  const printButtons = $$('[data-print-selected-zpl]').concat([$('#zpl-print')].filter(Boolean));
  printButtons.forEach(button => { button.disabled = true; });
  try {
    const printerName = await findZebraPrinterName();
    const config = qz.configs.create(printerName, { encoding: 'UTF-8' });
    await qz.print(config, [{ type: 'raw', format: 'plain', data: clean }]);
    const message = `Sent ${sourceLabel} to ${printerName}`;
    const summary = $('#zpl-summary');
    if (summary) summary.insertAdjacentHTML('afterbegin', `<div class="zpl-selected-notice qz-print-ok"><strong>Printed</strong><span>${escapeHtml(message)}</span></div>`);
    else window.alert(message);
  } catch (error) {
    const message = error?.message || String(error || 'QZ Tray print failed.');
    window.alert(`Could not print to Zebra via QZ Tray.\n\n${message}\n\nQZ Tray must be running, and you may need to approve this website in QZ Tray.`);
  } finally {
    updateBulkSelectionPanel(sortRows(filteredVehicles()));
    const output = $('#zpl-output');
    const printButton = $('#zpl-print');
    if (printButton) printButton.disabled = !(output && output.value.trim());
  }
}

function selectedVehiclesToZpl() {
  const vehicles = selectedVehiclesForBulkEmail();
  if (!vehicles.length) return { zpl: '', count: 0, warnings: ['Select one or more vehicles first.'] };
  const tsv = [ZPL_REQUIRED_COLUMNS.join('\t'), ...vehicles.map(selectedVehicleToZplRow)].join('\n');
  const parsed = parseZplInput(tsv);
  const zpl = parsed.vehicles.map(vehicleToZplBlock).join('\n\n');
  return { zpl, count: vehicles.length, warnings: parsed.warnings };
}

async function printZplFromSelectedRows() {
  const result = selectedVehiclesToZpl();
  if (!result.count) return;
  if (result.warnings.length && !window.confirm(`There are ${result.warnings.length} ZPL warning${result.warnings.length === 1 ? '' : 's'} before printing. Print anyway?\n\n${result.warnings.slice(0, 6).join('\n')}${result.warnings.length > 6 ? '\n...' : ''}`)) return;
  await printRawZpl(result.zpl, `${result.count} selected vehicle${result.count === 1 ? '' : 's'}`);
}

async function printCurrentZplOutput() {
  const output = $('#zpl-output')?.value || '';
  await printRawZpl(output, 'current ZPL output');
}

function getSelectedZplBatch(vehicle) {
  const toyota = getToyotaMatch(vehicle) || {};
  return cleanZplField(
    vehicle.autocareBatch ||
    vehicle.batch ||
    vehicle.toyotaBatch ||
    toyota.batch ||
    displayStockNumber(vehicle) ||
    vehicle.order ||
    ''
  );
}

function getSelectedZplVin(vehicle) {
  const directVin = [vehicle.autocareVin, vehicle.vin, vehicle.frameVin, vehicle.vinNumber, vehicle.fullVin]
    .map(value => normalizeVin(value))
    .find(Boolean);
  if (directVin) return directVin;
  const wmi = cleanZplField(vehicle.wmi || vehicle.WMI || '').replace(/\s+/g, '');
  const vds = cleanZplField(vehicle.vdsNumber || vehicle.vds || vehicle.VDS || '').replace(/\s+/g, '');
  const frame = cleanZplField(vehicle.frame || vehicle.frameNo || vehicle.autocareFrame || vehicle.Frame || '').replace(/\s+/g, '');
  return cleanZplField(`${wmi}${vds}${frame}`).replace(/\s+/g, '');
}

function splitVinPartsForZpl(vehicle) {
  const vin = getSelectedZplVin(vehicle);
  const wmiSource = cleanZplField(vehicle.wmi || vehicle.WMI || '').replace(/\s+/g, '');
  const vdsSource = cleanZplField(vehicle.vdsNumber || vehicle.vds || vehicle.VDS || '').replace(/\s+/g, '');
  const frameSource = cleanZplField(vehicle.frame || vehicle.frameNo || vehicle.autocareFrame || vehicle.Frame || '').replace(/\s+/g, '');
  if (vin.length === 17) {
    return { wmi: vin.slice(0, 3), vds: vin.slice(3, 9), frame: vin.slice(9) };
  }
  return { wmi: wmiSource || vin.slice(0, 3), vds: vdsSource, frame: frameSource };
}

function selectedVehicleToZplRow(vehicle) {
  const toyota = getToyotaMatch(vehicle) || {};
  const vinParts = splitVinPartsForZpl(vehicle);
  return [
    getSelectedZplBatch(vehicle),
    cleanZplField(vehicle.client || vehicle.toyotaCustomer || toyota.toyotaCustomer || ''),
    cleanZplField(vehicle.toyotaCustomer || toyota.toyotaCustomer || ''),
    cleanZplField(vehicle.toyotaVehicle || toyota.toyotaVehicle || vehicle.autocareModelDescription || vehicle.autocareModel || displayVehicle(vehicle) || vehicle.vehicle || ''),
    cleanZplField(vehicle.suffix || toyota.suffix || vehicle.autocareVersionDescription || ''),
    cleanZplField(vehicle.trim || toyota.trim || ''),
    cleanZplField(vehicle.colour || vehicle.color || toyota.colour || vehicle.autocareColour || ''),
    cleanZplField(vinParts.wmi),
    cleanZplField(vinParts.vds),
    cleanZplField(vinParts.frame),
  ].join('\t');
}

function generateZplFromSelectedRows() {
  const vehicles = selectedVehiclesForBulkEmail();
  if (!vehicles.length) return;
  const tsv = [ZPL_REQUIRED_COLUMNS.join('\t'), ...vehicles.map(selectedVehicleToZplRow)].join('\n');
  const input = $('#zpl-input');
  if (input) input.value = tsv;
  showView('zpl');
  generateZplFromInput();
  const summary = $('#zpl-summary');
  if (summary) {
    summary.insertAdjacentHTML('afterbegin', `<div class="zpl-selected-notice"><strong>Prepared from selected CRM rows</strong><span>${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'} selected from the main tracker. Review any warnings, then copy the ZPL output.</span></div>`);
  }
}


function makeTableResizable(table) {
  if (!table) return;
  const storageKey = `vehicleTrackingCoreColumnWidths:v4:${table.id || 'vehicle-table'}`;
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(storageKey) || '{}'); } catch { saved = {}; }
  const headers = Array.from(table.querySelectorAll('thead th'));
  headers.forEach((th, index) => {
    const widthKey = th.dataset.colId || String(index);
    if (saved[widthKey] || saved[index]) {
      const savedWidth = `${saved[widthKey] || saved[index]}px`;
      th.style.setProperty('width', savedWidth, 'important');
      th.style.setProperty('min-width', savedWidth, 'important');
      th.style.setProperty('max-width', savedWidth, 'important');
    }
    if (th.querySelector('.col-resizer')) return;
    const grip = document.createElement('span');
    grip.className = 'col-resizer';
    grip.setAttribute('aria-hidden', 'true');
    th.appendChild(grip);
    grip.addEventListener('click', e => e.stopPropagation());
    grip.addEventListener('mousedown', e => {
      e.preventDefault();
      e.stopPropagation();
      const startX = e.clientX;
      const startWidth = th.getBoundingClientRect().width;
      document.body.classList.add('resizing-column');
      const onMove = ev => {
        const next = Math.max(48, Math.round(startWidth + ev.clientX - startX));
        const nextWidth = `${next}px`;
        th.style.setProperty('width', nextWidth, 'important');
        th.style.setProperty('min-width', nextWidth, 'important');
        th.style.setProperty('max-width', nextWidth, 'important');
        saved[widthKey] = next;
      };
      const onUp = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
        document.body.classList.remove('resizing-column');
        localStorage.setItem(storageKey, JSON.stringify(saved));
      };
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  });
}

function setupFrozenVehicleHeader(table) {
  if (!table || table.id !== 'vehicle-table') return;
  const wrap = table.closest('.table-wrap');
  const thead = table.querySelector('thead');
  if (!wrap || !thead) return;

  if (app.frozenHeaderCleanup) app.frozenHeaderCleanup();

  const frozenWrap = document.createElement('div');
  frozenWrap.id = 'vehicle-table-frozen-head';
  frozenWrap.className = 'frozen-table-head';
  frozenWrap.setAttribute('role', 'presentation');

  const frozenTable = document.createElement('table');
  frozenTable.className = `${table.className} frozen-table-head-table`;
  frozenTable.appendChild(thead.cloneNode(true));
  frozenWrap.appendChild(frozenTable);
  document.body.appendChild(frozenWrap);

  const storageKey = `vehicleTrackingCoreColumnWidths:v4:${table.id || 'vehicle-table'}`;
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(storageKey) || '{}'); } catch { saved = {}; }

  let frameRequested = false;
  const requestUpdate = () => {
    if (frameRequested) return;
    frameRequested = true;
    window.requestAnimationFrame(() => {
      frameRequested = false;
      updateFrozenVehicleHeader(table, wrap, frozenWrap, frozenTable);
    });
  };

  const frozenSortButtons = $$('[data-sort-key]', frozenWrap);
  frozenSortButtons.forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      setSort(button.dataset.sortKey);
    });
  });

  bindColumnFilterControls(frozenWrap);
  makeVehicleColumnsReorderable(frozenTable);

  const frozenSelectAll = $('[data-select-visible]', frozenWrap);
  if (frozenSelectAll) {
    frozenSelectAll.addEventListener('click', event => event.stopPropagation());
    frozenSelectAll.addEventListener('change', () => {
      const visibleKeys = sortRows(filteredVehicles()).map(vehicleKey).filter(Boolean);
      visibleKeys.forEach(key => {
        if (frozenSelectAll.checked) app.selectedRows.add(key);
        else app.selectedRows.delete(key);
      });
      renderVehicleTable();
    });
  }

  const frozenHeaders = Array.from(frozenWrap.querySelectorAll('thead th'));
  frozenHeaders.forEach((frozenTh, index) => {
    const grip = frozenTh.querySelector('.col-resizer');
    const widthKey = frozenTh.dataset.colId || String(index);
    if (!grip) return;
    grip.addEventListener('click', event => event.stopPropagation());
    grip.addEventListener('mousedown', event => {
      event.preventDefault();
      event.stopPropagation();
      const realTh = table.querySelectorAll('thead th')[index];
      if (!realTh) return;
      const startX = event.clientX;
      const startWidth = realTh.getBoundingClientRect().width;
      document.body.classList.add('resizing-column');
      const onMove = moveEvent => {
        const next = Math.max(48, Math.round(startWidth + moveEvent.clientX - startX));
        const nextWidth = `${next}px`;
        realTh.style.setProperty('width', nextWidth, 'important');
        realTh.style.setProperty('min-width', nextWidth, 'important');
        realTh.style.setProperty('max-width', nextWidth, 'important');
        frozenTh.style.setProperty('width', nextWidth, 'important');
        frozenTh.style.setProperty('min-width', nextWidth, 'important');
        frozenTh.style.setProperty('max-width', nextWidth, 'important');
        saved[widthKey] = next;
        requestUpdate();
      };
      const onUp = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
        document.body.classList.remove('resizing-column');
        localStorage.setItem(storageKey, JSON.stringify(saved));
        requestUpdate();
      };
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  });

  const listeners = [
    [window, 'scroll', requestUpdate, { passive: true }],
    [window, 'resize', requestUpdate, { passive: true }],
    [wrap, 'scroll', requestUpdate, { passive: true }],
  ];
  listeners.forEach(([target, type, handler, options]) => target.addEventListener(type, handler, options));
  app.frozenHeaderCleanup = () => {
    listeners.forEach(([target, type, handler]) => target.removeEventListener(type, handler));
    frozenWrap.remove();
    document.body.classList.remove('vehicle-table-header-pinned');
  };
  requestUpdate();
}

function updateFrozenVehicleHeader(table, wrap, frozenWrap, frozenTable) {
  if (!table?.isConnected || !wrap?.isConnected || !frozenWrap?.isConnected) return;
  const dashboardActive = $('#dashboard')?.classList.contains('active');
  const thead = table.querySelector('thead');
  const firstBodyRow = table.querySelector('tbody tr');
  if (!dashboardActive || !thead || !firstBodyRow) {
    frozenWrap.classList.remove('active');
    document.body.classList.remove('vehicle-table-header-pinned');
    return;
  }

  const topOffset = 0;
  const tableRect = table.getBoundingClientRect();
  const wrapRect = wrap.getBoundingClientRect();
  const headRect = thead.getBoundingClientRect();
  const headHeight = Math.ceil(headRect.height || 34);
  const shouldPin = headRect.top <= topOffset && tableRect.bottom > topOffset + headHeight + 8;

  frozenWrap.classList.toggle('active', shouldPin);
  document.body.classList.toggle('vehicle-table-header-pinned', shouldPin);
  if (!shouldPin) return;

  frozenWrap.style.top = `${topOffset}px`;
  frozenWrap.style.left = `${Math.max(wrapRect.left, 0)}px`;
  frozenWrap.style.width = `${Math.max(wrapRect.width, 0)}px`;
  frozenWrap.style.height = `${headHeight}px`;
  frozenTable.style.width = `${Math.ceil(tableRect.width)}px`;
  frozenTable.style.minWidth = `${Math.ceil(tableRect.width)}px`;
  frozenTable.style.transform = `translateX(${-wrap.scrollLeft}px)`;

  const realHeaders = Array.from(table.querySelectorAll('thead th'));
  const frozenHeaders = Array.from(frozenWrap.querySelectorAll('thead th'));
  realHeaders.forEach((realTh, index) => {
    const frozenTh = frozenHeaders[index];
    if (!frozenTh) return;
    const width = Math.ceil(realTh.getBoundingClientRect().width);
    const widthPx = `${width}px`;
    frozenTh.style.setProperty('width', widthPx, 'important');
    frozenTh.style.setProperty('min-width', widthPx, 'important');
    frozenTh.style.setProperty('max-width', widthPx, 'important');
  });

  const visibleKeys = sortRows(filteredVehicles()).map(vehicleKey).filter(Boolean);
  const selectedVisible = visibleKeys.filter(key => app.selectedRows.has(key)).length;
  const frozenSelectAll = $('[data-select-visible]', frozenWrap);
  if (frozenSelectAll) {
    frozenSelectAll.checked = visibleKeys.length > 0 && selectedVisible === visibleKeys.length;
    frozenSelectAll.indeterminate = selectedVisible > 0 && selectedVisible < visibleKeys.length;
  }
}

function renderQuickFilterBanner(count) {
  const banner = $('#quick-filter-banner');
  if (!banner) return;
  const label = quickFilterLabel();
  if (!label) {
    banner.classList.remove('active');
    banner.innerHTML = '';
    return;
  }
  banner.classList.add('active');
  banner.innerHTML = `<span><strong>${escapeHtml(label)}</strong> · ${count} vehicle${count === 1 ? '' : 's'} shown</span><button class="small-button" type="button" id="clear-quick-filter-inline">Clear filter</button>`;
  $('#clear-quick-filter-inline')?.addEventListener('click', () => {
    clearQuickFilter(true);
    renderVehicleTable();
  });
}

function loadAuditLog() { return loadJson(AUDIT_LOG_KEY, []); }
function saveAuditLog(log) { saveJson(AUDIT_LOG_KEY, Array.isArray(log) ? log.slice(0, 1500) : []); }

function getCurrentOperatorName() {
  const saved = String(localStorage.getItem(OPERATOR_NAME_KEY) || '').trim();
  if (saved) return saved;
  const entered = window.prompt('Enter your name or initials for the PDC audit trail:', '') || '';
  const clean = entered.trim() || 'Unknown operator';
  try { localStorage.setItem(OPERATOR_NAME_KEY, clean); } catch {}
  return clean;
}

function getCurrentOperatorRole() {
  const saved = String(localStorage.getItem(OPERATOR_ROLE_KEY) || '').trim();
  if (saved) return saved;
  const entered = window.prompt('Enter your department/role for the PDC audit trail (Tint, Hoist, Fitting, Fabrication, Electrical, Tyre bay, Pit Inspection, Parts, Manager):', '') || '';
  const clean = entered.trim() || 'Unassigned role';
  try { localStorage.setItem(OPERATOR_ROLE_KEY, clean); } catch {}
  return clean;
}

function setOperatorProfile() {
  const currentName = String(localStorage.getItem(OPERATOR_NAME_KEY) || '').trim();
  const currentRole = String(localStorage.getItem(OPERATOR_ROLE_KEY) || '').trim();
  const name = window.prompt('Name or initials for the audit trail:', currentName || '') || currentName;
  const role = window.prompt('Department/role for the audit trail:', currentRole || '') || currentRole;
  try {
    localStorage.setItem(OPERATOR_NAME_KEY, (name || 'Unknown operator').trim());
    localStorage.setItem(OPERATOR_ROLE_KEY, (role || 'Unassigned role').trim());
  } catch {}
  renderTvBoard();
  window.alert(`PDC operator set to ${(name || 'Unknown operator').trim()} (${(role || 'Unassigned role').trim() || 'Unassigned role'}).`);
}

function recordVehicleAudit(vehicleOrKey, action, details = {}) {
  const vehicle = typeof vehicleOrKey === 'object' ? vehicleOrKey : selectedVehicle(vehicleOrKey);
  if (!vehicle) return;
  const key = vehicleKey(vehicle);
  const entry = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    at: nowIsoString(),
    by: details.by || getCurrentOperatorName(),
    role: details.role || getCurrentOperatorRole(),
    action,
    vehicleKey: key,
    stock: displayStockNumber(vehicle) || vehicle.stock || '',
    order: vehicle.order || '',
    customer: vehicle.client || vehicle.toyotaCustomer || '',
    vehicle: displayVehicle(vehicle) || '',
    details,
  };
  const log = loadAuditLog();
  log.unshift(entry);
  saveAuditLog(log);
}

function auditTrailForVehicle(vehicle = {}) {
  const keys = new Set([vehicleKey(vehicle), vehicle.stock, vehicle.order, vehicle.id].map(v => String(v || '').trim()).filter(Boolean));
  return loadAuditLog().filter(entry => keys.has(String(entry.vehicleKey || '').trim()) || keys.has(String(entry.stock || '').trim()) || keys.has(String(entry.order || '').trim())).slice(0, 30);
}

function renderAuditTrailSection(vehicle = {}) {
  const rows = auditTrailForVehicle(vehicle);
  if (!rows.length) return '<div class="subtle">No PDC audit events saved for this vehicle yet.</div>';
  return `<div class="audit-log-list">${rows.map(entry => {
    const when = parseIsoTimestamp(entry.at);
    const whenLabel = when ? when.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'Unknown time';
    const detail = entry.details ? Object.entries(entry.details).filter(([key, value]) => !['by'].includes(key) && value !== undefined && value !== '').map(([key, value]) => `${key}: ${value}`).join(' · ') : '';
    return `<div class="audit-log-item"><strong>${escapeHtml(entry.action || 'Update')}</strong><span>${escapeHtml(whenLabel)} · ${escapeHtml(entry.by || entry.user || 'Unknown operator')}${entry.role ? ` (${escapeHtml(entry.role)})` : ''}${detail ? ` · ${escapeHtml(detail)}` : ''}</span></div>`;
  }).join('')}</div>`;
}

function selectedVehicle(key = app.selectedStock) {
  return app.data.find(v => vehicleKey(v) === key || v.stock === key || v.order === key || v.id === key) || app.data[0];
}

function saveVehicleEdits(key, updates) {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const editKey = vehicleKey(vehicle);
  const nextUpdates = { ...updates };
  if ('etaAtDealer' in nextUpdates) nextUpdates.etaAtDealer = navisionEtaForVehicle({ ...vehicle, ...nextUpdates });
  Object.assign(vehicle, nextUpdates);
  const edits = loadVehicleEdits();
  edits[editKey] = { ...(edits[editKey] || {}), ...nextUpdates };
  saveJson(EDITS_KEY, edits);
  renderKpis();
  renderVehicleTable();
  renderKanban();
  renderWorkflowBoard();
  renderTvBoard();
  renderScheduleBoard();
  renderPartsHome();
  renderRftHome();
  renderCompletedVehicles();
  renderIncomingDashboardBoard();
  renderAdminLists();
  renderCustomers();
  renderReviewTable(app.reviewed);
}

function openVehicleModal(stock) {
  app.selectedStock = stock;
  renderDetail();
  const modal = $('#vehicle-modal');
  if (!modal) return;
  modal.hidden = false;
  document.body.classList.add('modal-open');
  $('#modal-close')?.focus();
}

function closeVehicleModal() {
  const modal = $('#vehicle-modal');
  if (!modal) return;
  modal.hidden = true;
  document.body.classList.remove('modal-open');
}

function removeVehicle(stock) {
  const vehicle = selectedVehicle(stock);
  if (!vehicle) return;
  const label = `${vehicleIdentityTitle(vehicle) || 'this vehicle'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`;
  if (!window.confirm(`Remove ${label} from the tracker? This will hide it from the prototype dashboard.`)) return;

  const key = vehicleDeleteKey(vehicle);
  if (key) {
    const deleted = new Set(loadDeletedVehicles());
    deleted.add(key);
    saveDeletedVehicles([...deleted]);
  }

  const added = loadAddedVehicles().filter(v => vehicleDeleteKey(v) !== key && v.stock !== stock);
  saveAddedVehicles(added);

  const edits = loadVehicleEdits();
  delete edits[stock];
  saveJson(EDITS_KEY, edits);

  const poTasks = loadPoTasks();
  const poFiles = loadPoFiles();
  delete poTasks[stock];
  delete poFiles[stock];
  savePoTasks(poTasks);
  savePoFiles(poFiles);

  app.data = buildVehicleData();
  app.selectedStock = app.data[0] ? vehicleKey(app.data[0]) : null;
  closeVehicleModal();
  populateFilters();
  renderAll();
}

function renderDetail() {
  const v = selectedVehicle();
  const panel = $('#vehicle-detail');
  if (!v || !panel) return;
  const key = vehicleKey(v);
  const notes = getNotes(key);
  const customerWarning = !isCustomerMatch(v);
  const workshopTask = v.internalStatus || '';
  const isCompletedVehicle = statusCategory(v) === 'completed';
  const completedLockAttr = isCompletedVehicle ? 'disabled' : '';
  panel.innerHTML = `
    <div class="panel-header"><div><h2 id="vehicle-modal-title">Vehicle detail</h2><p>${stockLabel(v)} ${escapeHtml(displayStockNumber(v))}</p></div>${formatStatus(v)}</div>
    <div class="detail-body">
      <div class="detail-title">
        <div><h3>${escapeHtml(v.client || 'New customer')}</h3><p>${escapeHtml(displayVehicle(v))}</p></div>
        <div class="detail-actions">
          ${actionSelectHtml(key)}
          <button class="danger ghost" type="button" data-remove-vehicle="${escapeHtml(key)}">Remove vehicle</button>
        </div>
      </div>
      <form class="edit-form" data-vehicle-edit-form>
        <div class="form-row three-col">
          <label>
            <span class="muted-label">SP</span>
            <input name="consultant" value="${escapeHtml(consultantName(v) === 'Unassigned' ? '' : salesPersonInitials(consultantName(v)))}" placeholder="e.g. CW" />
          </label>
          <label>
            <span class="muted-label">Client name</span>
            <input name="client" value="${escapeHtml(v.client || '')}" placeholder="Client name" />
          </label>
          <label>
            <span class="muted-label">Key tag number</span>
            ${statusCategory(v) === 'pmb' ? `<input name="keyNumber" value="${escapeHtml(vehicleKeyNumber(v))}" placeholder="One active PMB key tag number" />` : `<input name="keyNumber" value="" placeholder="Available once allocated into PMB" readonly />`}
            <span class="field-help">Shown and editable only while the vehicle is allocated into PMB.</span>
          </label>
        </div>
        <div class="form-row two-col">
          <label>
            <span class="muted-label">JC Jobcard Number</span>
            <input name="pdcJobcard" value="${escapeHtml(vehicleJobcardNumber(v))}" placeholder="Workshop jobcard #" />
          </label>
          <label>
            <span class="muted-label">Navision ETA</span>
            <input value="${escapeHtml(scotEtaOnly(v.etaAtDealer))}" placeholder="No Navision ETA" readonly />
          </label>
          <label>
            <span class="muted-label">JITA Parts Ordered</span>
            <select name="jitaPartsOrdered">
              <option value="Unknown" ${normalizeJita(jitaDisplay(v)) === 'Unknown' ? 'selected' : ''}>Unknown</option>
              <option value="Yes" ${normalizeJita(jitaDisplay(v)) === 'Yes' ? 'selected' : ''}>Yes</option>
              <option value="No" ${normalizeJita(jitaDisplay(v)) === 'No' ? 'selected' : ''}>No</option>
            </select>
          </label>
        </div>
        <div class="form-row two-col">
          <label>
            <span class="muted-label">Task selection</span>
            <select name="internalStatus">${taskOptionsHtml(workshopTask)}</select>
          </label>
          <label>
            <span class="muted-label">PDC location</span>
            <select name="pdcLocation">${pdcLocationSelectOptions(v.pdcLocation)}</select>
            <span class="field-help">Manual from Yard Hold onward. Navision will not overwrite PMB or RFT.</span>
          </label>
        </div>
        <div class="form-row two-col">
          <label>
            <span class="muted-label">Current PMB tile</span>
            <input value="${escapeHtml(pmbStageLabel(inferredPmbStage(v)) || 'Unallocated')}" readonly />
            <span class="field-help">Move vehicles between PMB buckets from the Workflow Board only, so bay movement stays consistent.</span>
          </label>
          <label>
            <span class="muted-label">Bucket age</span>
            <input value="${escapeHtml(statusCategory(v) === 'pmb' ? pmbStageAgeLabel(v) : 'Not in PMB')}" readonly />
          </label>
        </div>
        <div class="muted-label section-label">Blocked / exception control</div>
        <div class="form-row two-col">
          <label class="check-option block-check"><input name="pdcBlocked" type="checkbox" ${isPdcBlocked(v) ? 'checked' : ''} /> <span>Blocked / problem vehicle</span></label>
          <label>
            <span class="muted-label">Blocked reason</span>
            <input name="pdcBlockReason" value="${escapeHtml(v.pdcBlockReason || '')}" placeholder="Parts missing, damage, awaiting supplier, rework..." />
          </label>
        </div>
        <div class="muted-label section-label">Required work before RFT</div>
        <div class="form-row six-col check-grid pdc-requirement-grid slim-job-grid">
          ${PDC_JOB_DEFS.map(def => `<label class="check-option pdc-toggle-chip pdc-toggle-${escapeHtml(def.key)} ${pdcJobRequired(v, def) ? 'is-on' : ''}"><input name="${escapeHtml(def.requireKey)}" type="checkbox" ${pdcJobRequired(v, def) ? 'checked' : ''} ${completedLockAttr} /> <span><b>${escapeHtml(def.short)}</b>${escapeHtml(def.label)}</span></label>`).join('')}
        </div>
        <div class="muted-label section-label">Department sign-off / completed</div>
        <div class="form-row six-col check-grid pdc-completion-grid slim-job-grid">
          ${PDC_JOB_DEFS.map(def => `<label class="check-option pdc-toggle-chip completion-option pdc-toggle-${escapeHtml(def.key)} ${pdcJobComplete(v, def) ? 'is-complete' : ''} ${isCompletedVehicle ? 'is-locked' : ''}"><input name="${escapeHtml(def.completeKey)}" type="checkbox" ${pdcJobComplete(v, def) ? 'checked' : ''} ${completedLockAttr} /> <span><b>${pdcJobComplete(v, def) ? '✓' : escapeHtml(def.short)}</b>${escapeHtml(def.label)}</span></label>`).join('')}
        </div>
        <div class="edit-actions">
          <button class="primary" type="submit">Save changes</button>
          <span class="save-message" data-save-message></span>
        </div>
      </form>
      ${renderPmbBayControlSection(v)}
      ${renderPoUploadSection(v)}
      ${renderPoTasksSection(v)}
      ${renderNavisionDetailSection(v)}
      <div class="detail-metrics">
        <div class="metric"><span>SP</span><strong title="${escapeHtml(consultantName(v))}">${escapeHtml(salesPersonInitials(consultantName(v)))}</strong></div>
        ${statusCategory(v) === 'pmb' ? `<div class="metric"><span>Key tag number</span><strong>${escapeHtml(vehiclePmbKeyNumber(v) || 'Not set')}</strong></div>` : ''}
        <div class="metric"><span>JC Jobcard</span><strong>${escapeHtml(vehicleJobcardNumber(v) || 'Not set')}</strong></div>
        <div class="metric"><span>Contact</span><strong>${escapeHtml(v.contact || 'Not on Excel')}</strong></div>
        <div class="metric"><span>Navision ETA</span>${formatEta(v.etaAtDealer)}</div>
        <div class="metric"><span>PDC location</span><strong>${escapeHtml(pdcLocationLabel(v.pdcLocation) || 'Follow Navision')}</strong></div>
        <div class="metric"><span>PMB work stream</span><strong>${escapeHtml(pmbStageLabel(inferredPmbStage(v)) || 'Not assigned')}</strong></div>
        <div class="metric"><span>PMB bay</span><strong>${escapeHtml(pmbBaySummary(v) || 'Not assigned')}</strong></div>
        <div class="metric"><span>PMB requirements</span><strong>${escapeHtml(pmbRequirementText(v))}</strong></div>
        <div class="metric"><span>PMB completed</span><strong>${escapeHtml(pdcCompletedJobsText(v))}</strong></div>
        <div class="metric"><span>PMB outstanding</span><strong>${escapeHtml(pdcOutstandingJobsText(v))}</strong></div>
        <div class="metric"><span>Blocked</span><strong>${isPdcBlocked(v) ? escapeHtml(pdcBlockReason(v)) : 'No'}</strong></div>
        <div class="metric"><span>PMB age</span><strong>${statusCategory(v) === 'pmb' ? escapeHtml(pmbAgeDetailText(v)) : 'Not in PMB'}</strong></div>
        <div class="metric"><span>Production</span><strong>${escapeHtml(v.prodMth || v.group || 'Not shown')}</strong></div>
        <div class="metric"><span>Port</span><strong>${escapeHtml(v.arrivalPort || 'Not shown')}</strong></div>
        <div class="metric"><span>Autocare VIN</span><strong>${escapeHtml(v.autocareVin || v.vin || 'Not despatched')}</strong></div>
        <div class="metric"><span>Autocare load</span><strong>${escapeHtml(v.autocareLoadNumber || 'None')}</strong></div>
        <div class="metric"><span>JITA Qty</span><strong>${escapeHtml(v.jitQty || 'None shown')}</strong></div>
      </div>
      <div>
        <div class="muted-label">Status history</div>
        <div class="timeline">
          <div class="timeline-item"><span class="dot"></span><div><strong>Task</strong><br>${escapeHtml(v.internalStatus || 'No task selected')}</div></div>
          ${vehiclePdcLocation(v) ? `<div class="timeline-item"><span class="dot"></span><div><strong>PDC location</strong><br>${escapeHtml(pdcLocationLabel(v.pdcLocation))}</div></div>` : ''}
          ${inferredPmbStage(v) ? `<div class="timeline-item"><span class="dot"></span><div><strong>PMB work stream</strong><br>${escapeHtml(pmbStageLabel(inferredPmbStage(v)))}${pmbBaySummary(v) ? ` · ${escapeHtml(pmbBaySummary(v))}` : ''}</div></div>` : ''}
          ${v.toyotaStatus ? `<div class="timeline-item"><span class="dot"></span><div><strong>Navision Sub Location Description</strong><br>${escapeHtml(v.toyotaStatus)}${scotEtaOnly(v.etaAtDealer) ? ` · ETA ${escapeHtml(scotEtaOnly(v.etaAtDealer))}` : ''}</div></div>` : ''}
          ${(v.poTasks || []).length ? `<div class="timeline-item"><span class="dot"></span><div><strong>Purchase order tasks loaded</strong><br>${(v.poTasks || []).length} workshop / accessory task${(v.poTasks || []).length === 1 ? '' : 's'} attached.</div></div>` : ''}
          ${isAutocareDespatched(v) ? `<div class="timeline-item autocare-timeline"><span class="dot"></span><div><strong>Autocare despatch notice matched</strong><br>${v.autocareLoadNumber ? `Load ${escapeHtml(v.autocareLoadNumber)} · ` : ''}${v.autocareBatch ? `Batch ${escapeHtml(v.autocareBatch)} · ` : ''}${v.autocareVin ? `VIN ${escapeHtml(v.autocareVin)}` : 'Marked as despatched from Autocare notice'}</div></div>` : ''}
          ${customerWarning ? `<div class="timeline-item"><span class="dot"></span><div><strong>Customer mismatch warning</strong><br>Tracker says ${escapeHtml(v.client)}; Toyota says ${escapeHtml(v.toyotaCustomer)}.</div></div>` : ''}
        </div>
      </div>
      <div>
        <div class="muted-label">PDC audit trail</div>
        ${renderAuditTrailSection(v)}
      </div>
      <form class="notes-form" data-notes-form>
        <div class="muted-label">Team notes</div>
        <textarea rows="3" placeholder="Add call notes, accessory reminders, or follow-up actions..."></textarea>
        <button class="primary" type="submit">Add note</button>
      </form>
      <div class="notes-list">${notes.map(n => `<div class="note-pill">${escapeHtml(n)}</div>`).join('') || '<div class="subtle">No notes added yet.</div>'}</div>
    </div>
  `;
  $('[data-action-stock]', panel)?.addEventListener('change', (e) => {
    if (!e.currentTarget.value) return;
    handleVehicleAction(key, e.currentTarget.value);
    e.currentTarget.value = '';
  });
  on($('[data-remove-vehicle]', panel), 'click', () => removeVehicle(key));
  on($('[data-vehicle-po-upload]', panel), 'change', (event) => handleVehiclePoSelect(key, event));
  $('[data-vehicle-edit-form]', panel).addEventListener('submit', (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const client = form.client.value.trim() || v.client;
    const keyNumber = statusCategory(v) === 'pmb' ? cleanNavisionText(form.keyNumber?.value || '') : vehicleKeyNumber(v);
    const consultant = form.consultant.value.trim();
    const internalStatus = form.internalStatus.value.trim();
    const previousPdcLocation = vehiclePdcLocation(v);
    const previousPmbStage = normalizePmbStage(v.pmbStage || '');
    const pdcLocation = isCompletedVehicle ? previousPdcLocation : normalizePdcLocation(form.pdcLocation.value);
    const pmbStage = previousPmbStage;
    const pdcJobcard = cleanNavisionText(form.pdcJobcard?.value || '');
    const jitaPartsOrdered = form.jitaPartsOrdered.value;
    const pdcBlocked = Boolean(form.pdcBlocked?.checked);
    const pdcBlockReasonValue = cleanNavisionText(form.pdcBlockReason?.value || '');
    const requirementUpdates = {};
    const completionUpdates = {};
    PDC_JOB_DEFS.forEach(def => {
      requirementUpdates[def.requireKey] = isCompletedVehicle ? pdcJobRequired(v, def) : Boolean(form[def.requireKey]?.checked);
      completionUpdates[def.completeKey] = isCompletedVehicle ? pdcJobComplete(v, def) : Boolean(form[def.completeKey]?.checked);
    });
    const duplicateKeyVehicle = pdcLocation === 'PMB' ? activePmbVehicleWithKeyNumber(keyNumber, key) : null;
    if (duplicateKeyVehicle) {
      window.alert(`Key tag ${keyNumber} is already assigned to ${displayStockNumber(duplicateKeyVehicle) || duplicateKeyVehicle.order || 'another PMB vehicle'}. Only one active PMB vehicle can use a key tag number at a time.`);
      return;
    }
    const updates = { client, keyNumber, pdcJobcard, consultant, internalStatus, pdcLocation, pmbStage, jitaPartsOrdered, pdcBlocked, pdcBlockReason: pdcBlockReasonValue, ...requirementUpdates, ...completionUpdates };
    const changedCompletions = PDC_JOB_DEFS.filter(def => pdcJobComplete(v, def) !== completionUpdates[def.completeKey]);
    if (changedCompletions.length) {
      const operator = getCurrentOperatorName();
      const now = nowIsoString();
      changedCompletions.forEach(def => {
        if (completionUpdates[def.completeKey]) {
          updates[def.completeAtKey] = now;
          updates[def.completeByKey] = operator;
          recordVehicleAudit(v, 'Job signed off', { job: def.label, by: operator });
        } else {
          updates[def.completeAtKey] = '';
          updates[def.completeByKey] = '';
          recordVehicleAudit(v, 'Job sign-off removed', { job: def.label, by: operator });
        }
      });
    }
    PDC_JOB_DEFS.forEach(def => {
      if (pdcJobRequired(v, def) !== requirementUpdates[def.requireKey]) recordVehicleAudit(v, requirementUpdates[def.requireKey] ? 'Requirement added' : 'Requirement removed', { job: def.label });
    });
    if (isPdcBlocked(v) !== pdcBlocked || pdcBlockReason(v) !== (pdcBlockReasonValue || 'Blocked')) {
      recordVehicleAudit(v, pdcBlocked ? 'Vehicle blocked' : 'Vehicle unblocked', { reason: pdcBlockReasonValue });
    }
    if (pdcLocation !== previousPdcLocation) {
      const now = nowIsoString();
      updates.pdcLocationUpdatedAt = now;
      if (pdcLocation === 'PMB') {
        updates.manualLocation = 'PMB';
        updates.pdcLocationLocked = true;
        updates.pmbTransferredAt = v.pmbTransferredAt || now;
        updates.pmbEnteredAt = pmbEnteredTimestamp(v) || now;
        if (previousPdcLocation !== 'PMB') {
          updates.pmbStage = '';
          updates.pdcWorkStage = '';
          updates.workStage = '';
          updates.pmbStageEnteredAt = '';
          updates.pmbStageUpdatedAt = '';
          updates.pmbBayStage = '';
          updates.pmbBayNumber = '';
          updates.pmbBayEstimatedHours = '';
          updates.pmbBayEnteredAt = '';
          updates.pmbBayScheduledStartAt = '';
          updates.pmbBayCompletedAt = '';
          updates.pmbBayCompletedBy = '';
          updates.pmbBayCompletedStage = '';
          updates.pmbBayMechanic = '';
          updates.pmbSubletProvider = '';
        }
      }
      if (pdcLocation === 'RFT') { updates.manualLocation = 'RFT'; updates.pdcLocationLocked = true; updates.rftTransferredAt = now; updates.pmbEnteredAt = pmbEnteredTimestamp(v) || now; }
      if (pdcLocation === 'YH') { updates.manualLocation = 'YH'; updates.pdcLocationLocked = true; }
      recordVehicleAudit(v, 'PDC location changed', { from: pdcLocationLabel(previousPdcLocation) || 'Follow Navision', to: pdcLocationLabel(pdcLocation) || 'Follow Navision' });
    }
    if (!(pdcLocation === 'PMB' && previousPdcLocation !== 'PMB') && pmbStage !== previousPmbStage) {
      updates.pmbStageUpdatedAt = nowIsoString();
      updates.pmbStageEnteredAt = updates.pmbStageUpdatedAt;
      recordVehicleAudit(v, 'PMB bucket moved', { from: pmbStageLabel(previousPmbStage) || 'Unallocated', to: pmbStageLabel(pmbStage) || 'Unallocated' });
    }
    saveVehicleEdits(key, updates);
    renderDetail();
    const msg = $('[data-save-message]', panel);
    if (msg) msg.textContent = 'Saved';
  });
  $('[data-pmb-bay-detail-form]', panel)?.addEventListener('submit', (e) => {
    e.preventDefault();
    const saved = savePmbBayDetailForm(v, e.currentTarget);
    renderDetail();
    if (saved) {
      const msg = $('[data-bay-save-message]', panel) || $('[data-bay-save-message]');
      if (msg) msg.textContent = 'Saved';
    }
  });
  $('[data-modal-complete-pmb-bay-work]', panel)?.addEventListener('click', (e) => {
    e.preventDefault();
    completePmbBayWork(e.currentTarget.dataset.modalCompletePmbBayWork, e.currentTarget.dataset.modalCompletePmbBayStage);
    renderDetail();
  });
  $('[data-notes-form]', panel).addEventListener('submit', (e) => {
    e.preventDefault();
    const text = $('textarea', e.currentTarget).value.trim();
    if (!text) return;
    const stamp = new Date().toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' });
    setNotes(key, [`${stamp} - ${text}`, ...getNotes(key)]);
    renderDetail();
  });
}


function renderNavisionDetailSection(vehicle = {}) {
  const note = navisionDealerNoteText(vehicle);
  const fields = [
    ['Order', vehicle.order],
    ['Batch', vehicle.batch || vehicle.stock],
    ['Production Month', productionMonthLabel(vehicle.prodMth || vehicle.productionMonth || '')],
    ['Model Description', vehicle.toyotaVehicle],
    ['Suffix Description', vehicle.suffix],
    ['Trim Description', vehicle.trim],
    ['Colour Description', vehicle.colour],
    ['VIN', vehicle.vin],
    ['WMI', vehicle.wmi],
    ['VDS Number', vehicle.vdsNumber],
    ['Frame', vehicle.frame],
    ['Dealer Customer Name', vehicle.dealerCustomer || vehicle.toyotaCustomer],
    ['JITA PreOrder', jitaDisplay(vehicle)],
    ['Tray Fitment Ordered', vehicleFlag(vehicle, 'trayOrdered') ? 'Yes' : 'No'],
    ['Tray Fitment Complete', vehicleFlag(vehicle, 'trayFitmentComplete') ? 'Yes' : 'No'],
    ['Sub Location Description', vehicle.navisionSubLocationDescription || vehicle.toyotaStatus],
    ['Location Status', vehicle.navisionLocationStatus],
    ['Build Status', vehicle.navisionBuildStatus],
    ['Transport Load No.', vehicle.navisionTransportLoadNo],
    ['Control Board ETA', scotEtaOnly(vehicle.etaAtDealer)],
    ['ETA At Kewdale Yard', vehicle.navisionKewdaleEta],
    ['ETA Date (not used for dashboard ETA)', vehicle.navisionEtaDate],
    ['Port/Plant ETA Date (not used for dashboard ETA)', vehicle.navisionPortPlantEta],
    ['ETA At Dealer/BB (not used for dashboard ETA)', vehicle.navisionEtaAtDealerBB],
    ['Vehicle Note', vehicle.navisionVehicleNote],
    ['Cut But Vehicle', isNavisionCutButVehicle(vehicle) ? (vehicle.navisionCutButVehicleSource || 'Yes') : ''],
  ].filter(([, value]) => cleanNavisionText(value));

  const notesHtml = note
    ? `<div class="navision-notes-detail"><div class="muted-label">Navision Notes / Dealer Comments</div><pre>${escapeHtml(note)}</pre></div>`
    : `<div class="navision-notes-detail empty"><div class="muted-label">Navision Notes / Dealer Comments</div><pre>No Dealer Comments imported for this vehicle.</pre></div>`;

  return `<section class="navision-detail-panel">
    ${notesHtml}
    <div class="muted-label">Navision vehicle fields</div>
    <div class="navision-field-grid">
      ${fields.map(([label, value]) => `<div class="navision-field"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join('') || '<div class="subtle">No detailed Navision fields are available for this row.</div>'}
    </div>
  </section>`;
}

function renderPoUploadSection(vehicle) {
  const key = vehicleKey(vehicle);
  const files = vehicle.poFiles || [];
  return `<section class="po-task-panel po-upload-panel">
    <div class="muted-label">PO upload</div>
    <label class="inline-upload">
      <input type="file" accept="application/pdf,.pdf" multiple data-vehicle-po-upload data-po-stock="${escapeHtml(key)}" />
      <span>Upload PO PDF for this vehicle</span>
    </label>
    <div class="subtle">Uploading a PO records a PMB fitment PO. ${files.length ? `${files.length} file${files.length === 1 ? '' : 's'} attached.` : 'No PO file attached yet.'}</div>
  </section>`;
}

function renderPoTasksSection(vehicle) {
  const tasks = vehicle.poTasks || [];
  const files = vehicle.poFiles || [];
  if (!tasks.length && !files.length) return '';
  return `<section class="po-task-panel">
    <div class="muted-label">Purchase order / workshop tasks</div>
    ${files.length ? `<div class="subtle"><strong>Uploaded PDFs:</strong> ${files.map(escapeHtml).join(', ')}</div>` : ''}
    ${tasks.length ? `<ul class="po-task-list">${tasks.map(task => `<li>${escapeHtml(task)}</li>`).join('')}</ul>` : ''}
  </section>`;
}

function poTasksForEmail(vehicle) {
  const tasks = vehicle.poTasks || [];
  return tasks.length ? tasks.map(task => `- ${task}`).join('\n') : (vehicle.internalStatus || 'Please confirm workshop requirements.');
}

function vehicleEmailLines(vehicle) {
  return [
    `Stock number: ${displayStockNumber(vehicle) || 'TBA'}`,
    `Customer Name: ${vehicleCustomerName(vehicle) || 'TBA'}`,
    `Vehicle: ${displayVehicle(vehicle) || 'TBA'}`,
  ];
}

function handleVehicleAction(stock, action) {
  if (action === 'released') return draftReleasedVehicleEmail(stock);
  if (action === 'update') return draftRequestUpdateEmail(stock);
  if (action === 'build') return draftNewVehicleBuildEmail(stock);
  if (action === 'tint') return draftTintPoEmail(stock);
}

function draftPdcEmail(stock) {
  return draftReleasedVehicleEmail(stock);
}

function draftReleasedVehicleEmail(stock) {
  const v = selectedVehicle(stock);
  if (!v) return;
  const body = vehicleEmailLines(v).join('\n');
  const subject = `Vehicle released - ${displayStockNumber(v) || 'TBA'}`;
  window.location.href = `mailto:${AMY_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function draftRequestUpdateEmail(stock) {
  const v = selectedVehicle(stock);
  if (!v) return;
  const body = vehicleEmailLines(v).join('\n');
  const subject = `Request update - ${displayStockNumber(v) || 'TBA'}`;
  window.location.href = `mailto:${PMG_UPDATE_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function poAttachmentLines(vehicle) {
  const files = vehicle.poFiles || [];
  if (!files.length) return ['Parts Order (131)', 'PMG work order PO'];
  return files.map(file => {
    const lower = String(file).toLowerCase();
    if (lower.includes('131') || lower.includes('parts order')) return `Parts Order (131) - ${file}`;
    if (lower.includes('pmg') || lower.includes('sublet')) return `PMG work order PO - ${file}`;
    return file;
  });
}

function pmgDueDate(vehicle) {
  return scotEtaOnly(vehicle.etaAtDealer) || '';
}

function draftNewVehicleBuildEmail(stock) {
  const v = selectedVehicle(stock);
  if (!v) return;
  const attachments = poAttachmentLines(v);
  const due = pmgDueDate(v);
  const body = [
    'Hi Guys,',
    '',
    'New vehicle order as attached for',
    '',
    `${displayStockNumber(v) || 'TBA'} - ${displayVehicle(v) || 'Vehicle TBA'}`,
    '',
    'For',
    '',
    `${vehicleCustomerName(v) || 'Customer TBA'}`,
    '',
    'Please find attached',
    '',
    ...attachments,
    '',
    'Dealer to supply all parts on 131 Parts PO',
    '',
    'PMG to supply parts listed on the PMG work order and fit all listed items to the vehicle',
    '',
    'Vehicle is having a TWA Steel tray fitted with underbody and head board tyre hangers.',
    '',
    due ? `This vehicle is due to arrive to PMG by ${due}` : 'This vehicle is due to arrive to PMG by',
    '',
    'Just let me know if you have any queries, or if there are any extended delay in parts',
    '',
    'Kind Regards,'
  ].join('\n');
  const subject = `New PMB work order for ${displayStockNumber(v) || 'TBA'}`;
  if ((v.poFiles || []).length) {
    window.alert('Your email draft will open now. Browser email links cannot attach PDF files automatically, so please attach the uploaded PO PDFs listed in the email body.');
  }
  window.location.href = `mailto:${PMG_UPDATE_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}


function draftTintPoEmail(stock) {
  const v = selectedVehicle(stock);
  if (!v) return;
  const body = [
    'Hi Jono,',
    '',
    'Please see tint PO request for the vehicle below.',
    '',
    ...vehicleEmailLines(v),
    '',
    'Kind Regards,'
  ].join('\n');
  const subject = `Tint PO - ${displayStockNumber(v) || 'TBA'}`;
  window.location.href = `mailto:${TINT_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function renderKanban() {
  const stages = ['Production / In Transit', 'Yard Hold', 'PMB', 'RFT'];
  const pipelineVehicles = app.data.filter(vehicle => getStage(vehicle) !== 'Needs Matching');
  const grouped = groupBy(pipelineVehicles, getStage);
  $('#pipeline-count').textContent = `${pipelineVehicles.length} vehicles`;
  $('#kanban').innerHTML = stages.map(stage => {
    const vehicles = (grouped[stage] || []).slice().sort((a, b) => toyotaStatusRank(a.toyotaStatus) - toyotaStatusRank(b.toyotaStatus) || String(displayStockNumber(a)).localeCompare(String(displayStockNumber(b)), 'en-AU', { numeric: true }));
    return `<details class="pipeline-section" open>
      <summary class="pipeline-summary"><strong>${escapeHtml(stage)}</strong><span class="badge neutral">${vehicles.length}</span></summary>
      <div class="pipeline-list">
        ${vehicles.map(v => `<article class="kanban-card pipeline-card" data-stock="${escapeHtml(vehicleKey(v))}">
          ${vehicleIdentityStackHtml(v)}
          <span>${escapeHtml(salesPersonInitials(consultantName(v)))} · Toyota ${escapeHtml(v.order || 'No order')}</span>
          <span>${escapeHtml(displayVehicle(v))}</span>
          <span>${escapeHtml(pdcLocationLabel(v.pdcLocation) || v.toyotaStatus || 'Not matched')}${statusCategory(v) === 'pmb' && inferredPmbStage(v) ? ` · ${escapeHtml(pmbStageLabel(inferredPmbStage(v)))}` : ''}${scotEtaOnly(v.etaAtDealer) ? ` · ETA ${escapeHtml(scotEtaOnly(v.etaAtDealer))}` : ''}</span>
        </article>`).join('') || '<div class="subtle">No vehicles in this stage.</div>'}
      </div>
    </details>`;
  }).join('');
  $$('.kanban-card').forEach(card => card.addEventListener('click', () => openVehicleModal(card.dataset.stock)));
}



function scheduleDateForVehicle(vehicle = {}) {
  return parseDateAU(kewdaleEtaValue(vehicle) || scotEtaOnly(vehicle.etaAtDealer || '') || vehicle.deliveryDate || '');
}

function scheduleBucketForVehicle(vehicle = {}) {
  const date = scheduleDateForVehicle(vehicle);
  if (!date) return { key: 'unknown', label: 'No ETA set', rank: 4 };
  const start = new Date(date);
  start.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const days = Math.floor((start - today) / (1000 * 60 * 60 * 24));
  if (days < 0) return { key: 'overdue', label: 'Overdue / already at Kewdale', rank: 0 };
  if (days === 0) return { key: 'today', label: 'Due today', rank: 1 };
  if (days <= 7) return { key: 'week', label: 'Next 7 days', rank: 2 };
  return { key: 'later', label: 'Later', rank: 3 };
}

function productionFlowSource(vehicle = {}) {
  return [pdcJobSourceText(vehicle), vehicle.navisionNotes, vehicle.internalStatus, vehicle.toyotaStatus, displayVehicle(vehicle), (vehicle.poTasks || []).join(' ')].join(' ').toLowerCase();
}

function productionDepartmentRequired(vehicle = {}, def = {}) {
  const job = PDC_JOB_BY_KEY.get(def.jobKey);
  const stage = inferredPmbStage(vehicle);
  const source = productionFlowSource(vehicle);
  if (stage && stage === def.stage) return true;
  if (def.search?.test(source)) return true;
  return Boolean(job && pdcJobRequired(vehicle, job) && def.key === 'FITTING');
}

function productionDepartmentComplete(vehicle = {}, def = {}) {
  const job = PDC_JOB_BY_KEY.get(def.jobKey);
  return Boolean(job && pdcJobComplete(vehicle, job));
}

function productionDepartmentsForVehicle(vehicle = {}) {
  return PRODUCTION_FLOW_DEFS
    .map(def => ({ ...def, required: productionDepartmentRequired(vehicle, def), complete: productionDepartmentComplete(vehicle, def) }))
    .filter(def => def.required);
}

function readinessChecklistForVehicle(vehicle = {}) {
  const parts = partsJobDef();
  const fabrication = PDC_JOB_BY_KEY.get('fabrication');
  const items = [];
  if (parts && pdcJobRequired(vehicle, parts)) {
    const status = partsDepartmentStatus(vehicle);
    items.push({ label: `Parts: ${partsDepartmentStatusLabel(status)}`, state: ['issued', 'notrequired'].includes(status) ? 'ready' : (status === 'stoppage' || status === 'notordered' ? 'blocked' : 'watch') });
  }
  if (fabrication && pdcJobRequired(vehicle, fabrication)) {
    items.push({ label: `Fabrication: ${pdcJobComplete(vehicle, fabrication) ? 'signed off' : 'required'}`, state: pdcJobComplete(vehicle, fabrication) ? 'ready' : 'watch' });
  }
  if (isPdcBlocked(vehicle)) items.push({ label: pdcBlockReason(vehicle), state: 'blocked' });
  const issues = vehicleRftGateIssues(vehicle).filter(issue => !issue.startsWith('No PMB bucket'));
  if (issues.length && !items.some(item => item.state === 'blocked')) items.push({ label: `${issues.length} RFT gate issue${issues.length === 1 ? '' : 's'}`, state: 'watch' });
  return items;
}

function scheduleRows() {
  const q = ($('#schedule-search')?.value || '').trim().toLowerCase();
  const department = $('#schedule-department-filter')?.value || '';
  return app.data
    .filter(vehicleHasBatchNumber)
    .map(vehicle => ({ vehicle, departments: productionDepartmentsForVehicle(vehicle), bucket: scheduleBucketForVehicle(vehicle), readiness: readinessChecklistForVehicle(vehicle) }))
    .filter(row => row.departments.length || statusCategory(row.vehicle) === 'pmb')
    .filter(row => !department || row.departments.some(def => def.key === department))
    .filter(row => {
      if (!q) return true;
      const hay = [
        displayStockNumber(row.vehicle), row.vehicle.order, row.vehicle.client, row.vehicle.toyotaCustomer,
        displayVehicle(row.vehicle), pmbStageLabel(inferredPmbStage(row.vehicle)), statusCategoryLabel(row.vehicle),
        row.departments.map(def => def.label).join(' '), row.readiness.map(item => item.label).join(' '),
        kewdaleEtaValue(row.vehicle), pmbAgeLabel(row.vehicle), pdcBlockReason(row.vehicle)
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => a.bucket.rank - b.bucket.rank
      || (scheduleDateForVehicle(a.vehicle)?.getTime() ?? Number.MAX_SAFE_INTEGER) - (scheduleDateForVehicle(b.vehicle)?.getTime() ?? Number.MAX_SAFE_INTEGER)
      || String(displayStockNumber(a.vehicle) || '').localeCompare(String(displayStockNumber(b.vehicle) || ''), 'en-AU', { numeric: true }));
}

function scheduleDepartmentPillsHtml(departments = []) {
  if (!departments.length) return '<span class="schedule-dept-pill neutral">Unallocated</span>';
  return departments.map(def => `<span class="schedule-dept-pill ${def.complete ? 'is-complete' : 'is-open'}">${escapeHtml(def.label)}${def.complete ? ' ✓' : ''}</span>`).join('');
}

function scheduleReadinessHtml(items = []) {
  if (!items.length) return '<span class="schedule-ready-pill ready">Ready prompts clear</span>';
  return items.map(item => `<span class="schedule-ready-pill ${escapeHtml(item.state)}">${escapeHtml(item.label)}</span>`).join('');
}

function renderScheduleBoard() {
  const host = $('#schedule-content');
  if (!host) return;
  const rows = scheduleRows();
  const count = $('#schedule-count');
  if (count) count.textContent = `${rows.length} vehicle${rows.length === 1 ? '' : 's'} · earliest Kewdale ETA first`;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No production / in transit vehicles match this filter</strong><span>Clear search or choose another department.</span></div>';
    return;
  }
  host.innerHTML = `<section class="schedule-list-panel">
    <div class="schedule-list-header">
      <strong>Production / In Transit</strong>
      <span>Sorted by earliest ETA At Kewdale Yard first</span>
    </div>
    <div class="schedule-list" role="list">
      ${rows.map(({ vehicle, departments, readiness }, index) => `
        <article class="schedule-list-item" role="listitem" data-stock="${escapeHtml(vehicleKey(vehicle))}">
          <div class="schedule-list-rank">${escapeHtml(String(index + 1).padStart(2, '0'))}</div>
          <div class="schedule-list-main">
            ${vehicleIdentityStackHtml(vehicle)}
            <small>${escapeHtml(displayVehicle(vehicle))}</small>
          </div>
          <div class="schedule-list-eta">
            <span>ETA Kewdale</span>
            <strong>${escapeHtml(kewdaleEtaValue(vehicle) || 'No ETA')}</strong>
            <small>${escapeHtml(pmbAgeLabel(vehicle))}</small>
          </div>
          <div class="schedule-list-status">
            <span>${escapeHtml(statusCategoryLabel(vehicle))}${inferredPmbStage(vehicle) ? ` · ${escapeHtml(pmbStageLabel(inferredPmbStage(vehicle)))}` : ''}</span>
            <div class="schedule-dept-row">${scheduleDepartmentPillsHtml(departments)}</div>
            <div class="schedule-ready-row">${scheduleReadinessHtml(readiness)}</div>
          </div>
        </article>`).join('')}
    </div>
  </section>`;
  $$('[data-stock]', host).forEach(card => card.addEventListener('click', () => openVehicleModal(card.dataset.stock)));
}

function activeProductionDepartmentDef() {
  const stage = app.activeProductionDepartment || 'TINT';
  return PRODUCTION_FLOW_DEFS.find(def => def.key === stage) || PRODUCTION_FLOW_DEFS[0];
}

function departmentVehicleStatus(vehicle = {}, def = {}) {
  const complete = productionDepartmentComplete(vehicle, def);
  if (isPdcBlocked(vehicle)) return 'blocked';
  return complete ? 'complete' : 'open';
}

function productionDepartmentRows(def = activeProductionDepartmentDef()) {
  const q = ($('#department-search')?.value || '').trim().toLowerCase();
  const filter = $('#department-status-filter')?.value || 'open';
  return app.data
    .filter(vehicleHasBatchNumber)
    .filter(vehicle => productionDepartmentRequired(vehicle, def) || inferredPmbStage(vehicle) === def.stage)
    .filter(vehicle => {
      const status = departmentVehicleStatus(vehicle, def);
      if (filter === 'open' && status !== 'open') return false;
      if (filter === 'blocked' && status !== 'blocked') return false;
      if (filter === 'complete' && status !== 'complete') return false;
      if (!q) return true;
      const hay = [
        displayStockNumber(vehicle), vehicle.order, vehicle.client, vehicle.toyotaCustomer, displayVehicle(vehicle),
        statusCategoryLabel(vehicle), pmbStageLabel(inferredPmbStage(vehicle)), kewdaleEtaValue(vehicle),
        pmbAgeLabel(vehicle), pdcBlockReason(vehicle), readinessChecklistForVehicle(vehicle).map(item => item.label).join(' ')
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => {
      const rank = { blocked: 0, open: 1, complete: 2 };
      const rankDiff = (rank[departmentVehicleStatus(a, def)] ?? 9) - (rank[departmentVehicleStatus(b, def)] ?? 9);
      if (rankDiff) return rankDiff;
      const etaDiff = (scheduleDateForVehicle(a)?.getTime() ?? Number.MAX_SAFE_INTEGER) - (scheduleDateForVehicle(b)?.getTime() ?? Number.MAX_SAFE_INTEGER);
      if (etaDiff) return etaDiff;
      return String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || ''), 'en-AU', { numeric: true });
    });
}

function departmentStatusBadgeHtml(vehicle = {}, def = {}) {
  const status = departmentVehicleStatus(vehicle, def);
  if (status === 'blocked') return `<span class="department-status-badge blocked">Stoppage · ${escapeHtml(pdcBlockReason(vehicle))}</span>`;
  if (status === 'complete') return '<span class="department-status-badge complete">Complete ✓</span>';
  return '<span class="department-status-badge open">Open work</span>';
}

function renderProductionDepartmentBoard() {
  const host = $('#department-content');
  if (!host) return;
  const def = activeProductionDepartmentDef();
  const rows = productionDepartmentRows(def);
  const heading = $('#department-heading');
  const description = $('#department-description');
  const count = $('#department-count');
  const help = $('#department-help-strip');
  const capacity = pmbStageCapacityLabel(def.stage);
  if (heading) heading.textContent = def.label;
  if (description) description.textContent = `${def.label} focused work list. No Navision tracker is shown here; use the action buttons to sign off work, record stoppages, or open the vehicle details.`;
  if (count) count.textContent = `${rows.length} vehicle${rows.length === 1 ? '' : 's'} · ${capacity}`;
  if (help) help.innerHTML = `<strong>${escapeHtml(def.label)}</strong><span>Capacity: ${escapeHtml(capacity)}</span><span>Sort: stoppages first, then earliest Kewdale ETA.</span>`;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No vehicles match this department filter</strong><span>Clear search or change the status filter.</span></div>';
    return;
  }
  host.innerHTML = `<div class="department-card-grid" role="list">
    ${rows.map(vehicle => {
      const key = vehicleKey(vehicle);
      const readiness = readinessChecklistForVehicle(vehicle);
      const complete = productionDepartmentComplete(vehicle, def);
      return `<article class="department-job-card ${departmentVehicleStatus(vehicle, def)}" role="listitem">
        <div class="department-job-main">
          ${vehicleIdentityStackHtml(vehicle)}
          <small>${escapeHtml(displayVehicle(vehicle))}</small>
        </div>
        <div class="department-job-meta">
          ${departmentStatusBadgeHtml(vehicle, def)}
          <span>Current: ${escapeHtml(pmbStageLabel(inferredPmbStage(vehicle)) || statusCategoryLabel(vehicle))}</span>
          <span>ETA Kewdale: ${escapeHtml(kewdaleEtaValue(vehicle) || 'No ETA')}</span>
          <span>${escapeHtml(pmbAgeLabel(vehicle))}</span>
        </div>
        <div class="schedule-ready-row">${scheduleReadinessHtml(readiness)}</div>
        <div class="department-actions">
          ${complete ? `<button type="button" class="secondary" data-dept-next="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Move to next station</button>` : `<button type="button" class="primary" data-dept-complete="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Ready for next bay</button>`}
          <button type="button" class="secondary" data-dept-stoppage="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Stoppage</button>
          ${isPdcBlocked(vehicle) ? `<button type="button" class="secondary" data-dept-clear-stoppage="${escapeHtml(key)}">Clear stoppage</button>` : ''}
          <button type="button" class="ghost" data-dept-open="${escapeHtml(key)}">Open vehicle</button>
        </div>
      </article>`;
    }).join('')}
  </div>`;
  $$('[data-dept-complete]', host).forEach(button => button.addEventListener('click', () => completePmbBayWork(button.dataset.deptComplete, button.dataset.deptStage)));
  $$('[data-dept-next]', host).forEach(button => button.addEventListener('click', () => moveVehicleToNextPmbStageFromBay(button.dataset.deptNext, button.dataset.deptStage)));
  $$('[data-dept-stoppage]', host).forEach(button => button.addEventListener('click', () => markProductionDepartmentStoppage(button.dataset.deptStoppage, button.dataset.deptStage)));
  $$('[data-dept-clear-stoppage]', host).forEach(button => button.addEventListener('click', () => clearProductionDepartmentStoppage(button.dataset.deptClearStoppage)));
  $$('[data-dept-open]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.deptOpen)));
}

function markProductionDepartmentStoppage(key = '', stage = '') {
  const vehicle = selectedVehicle(key);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  const reason = cleanNavisionText(window.prompt(`Enter ${pmbStageLabel(normalizedStage)} stoppage reason:`, isPdcBlocked(vehicle) ? pdcBlockReason(vehicle) : '') || '');
  if (!reason) return;
  const def = pmbStageJobDef(normalizedStage);
  const operator = getCurrentOperatorName();
  const updates = {
    pdcBlocked: true,
    pdcBlockReason: `${pmbStageLabel(normalizedStage)}: ${reason}`,
    pdcBlockedAt: nowIsoString(),
    pdcBlockedBy: operator,
    pmbStage: normalizedStage,
    pmbStageUpdatedAt: nowIsoString(),
  };
  if (def) {
    updates[def.requireKey] = true;
    updates[def.completeKey] = false;
  }
  recordVehicleAudit(vehicle, 'Production stoppage recorded', { stage: pmbStageLabel(normalizedStage), reason, by: operator });
  saveVehicleEdits(key, updates);
}

function clearProductionDepartmentStoppage(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const operator = getCurrentOperatorName();
  recordVehicleAudit(vehicle, 'Production stoppage cleared', { reason: pdcBlockReason(vehicle), by: operator });
  saveVehicleEdits(key, {
    pdcBlocked: false,
    pdcBlockReason: '',
    pdcBlockedClearedAt: nowIsoString(),
    pdcBlockedClearedBy: operator,
  });
}

function partsJobDef() {
  return PDC_JOB_BY_KEY.get('parts');
}

function partsStoppageReason(vehicle = {}) {
  return cleanNavisionText(vehicle.pdcPartsStoppageReason || '') || 'Parts stoppage recorded';
}

function isActivePartsStoppage(vehicle = {}) {
  const parts = PDC_JOB_BY_KEY.get('parts');
  const hasStoppage = vehicle.pdcPartsStoppage === true || Boolean(cleanNavisionText(vehicle.pdcPartsStoppageReason || ''));
  return Boolean(hasStoppage && parts && pdcJobRequired(vehicle, parts) && !pdcJobComplete(vehicle, parts));
}

function partsOrdered(vehicle = {}) {
  return vehicle.pdcPartsOrdered === true || Boolean(cleanNavisionText(vehicle.pdcPartsOrderedAt || vehicle.partsOrderedAt || ''));
}

function partsMiscAcc(vehicle = {}) {
  const value = String(vehicle.pdcPartsMiscAcc || vehicle.partsMiscAcc || vehicle.navisionPartsStatus || vehicle.partsStatus || '').trim().toLowerCase();
  return vehicle.pdcPartsMiscAcc === true || value === 'misc acc' || value === 'miscacc' || value.includes('misc acc');
}

function partsDepartmentStatus(vehicle = {}) {
  const def = partsJobDef();
  if (!pdcJobRequired(vehicle, def)) return 'notrequired';
  if (partsMiscAcc(vehicle)) return 'miscacc';
  if (def && (pdcJobComplete(vehicle, def) || vehicle.pdcPartsReceived === true)) return 'issued';
  if (isActivePartsStoppage(vehicle)) return 'stoppage';
  if (partsOrdered(vehicle)) return 'onorder';
  return 'notordered';
}

function partsDepartmentStatusLabel(status = '') {
  return {
    notrequired: 'Not Required',
    notordered: 'Not Ordered',
    onorder: 'On Order',
    stoppage: 'Stoppage',
    issued: 'Issued',
    miscacc: 'Misc Acc',
  }[status] || 'Not Ordered';
}

function partsDepartmentStatusClass(status = '') {
  return {
    notrequired: 'parts-status-complete',
    notordered: 'parts-status-toorder',
    onorder: 'parts-status-ordered',
    stoppage: 'parts-status-stoppage',
    issued: 'parts-status-complete',
    miscacc: 'parts-status-stoppage',
  }[status] || 'parts-status-toorder';
}

function partsLastUpdateLabel(vehicle = {}) {
  const candidates = [
    vehicle.pdcCompletePartsAt,
    vehicle.pdcPartsStoppageAt,
    vehicle.pdcPartsOrderedAt,
    vehicle.pdcLocationUpdatedAt,
  ].map(parseIsoTimestamp).filter(Boolean).sort((a, b) => b - a);
  if (!candidates.length) return '';
  return candidates[0].toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' });
}

function partsDepartmentRows() {
  const q = ($('#parts-search')?.value || '').trim().toLowerCase();
  const selectedFilter = $('#parts-status-filter')?.value || 'open';
  const filter = ['issued', 'notrequired'].includes(selectedFilter) ? 'open' : selectedFilter;
  return app.data
    .filter(vehicleHasBatchNumber)
    .filter(vehicle => {
      const status = partsDepartmentStatus(vehicle);
      const matchesStatus = (filter === 'all' && !['issued', 'notrequired'].includes(status))
        || (filter === 'open' && !['issued', 'notrequired'].includes(status))
        || (!['all', 'open'].includes(filter) && status === filter);
      if (!matchesStatus) return false;
      if (!q) return true;
      const productionLabel = productionMonthLabel(vehicle.prodMth || vehicle.productionMonth || '');
      const hay = [
        displayStockNumber(vehicle), vehicle.order, vehicle.client, vehicle.toyotaCustomer, displayVehicle(vehicle),
        pdcLocationLabel(vehiclePdcLocation(vehicle)),
        statusCategoryLabel(vehicle), partsDepartmentStatusLabel(status), partsStoppageReason(vehicle), productionLabel,
        kewdaleEtaValue(vehicle), partsEtaCounterLabel(vehicle)
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => {
      const rank = { miscacc: 0, stoppage: 1, notordered: 2, onorder: 3, issued: 4, notrequired: 5 };
      const rankDiff = (rank[partsDepartmentStatus(a)] ?? 9) - (rank[partsDepartmentStatus(b)] ?? 9);
      if (rankDiff) return rankDiff;
      const ageA = pmbAgeDays(a);
      const ageB = pmbAgeDays(b);
      if (ageA !== null || ageB !== null) return (ageB ?? -9999) - (ageA ?? -9999);
      return String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || ''), undefined, { numeric: true });
    });
}

function renderPartsSummary(rows = []) {
  const all = app.data.filter(vehicleHasBatchNumber);
  const counts = all.reduce((acc, vehicle) => {
    const status = partsDepartmentStatus(vehicle);
    acc[status] = (acc[status] || 0) + 1;
    if (!['issued', 'notrequired'].includes(status)) acc.open += 1;
    return acc;
  }, { open: 0, notordered: 0, onorder: 0, stoppage: 0, issued: 0, miscacc: 0, notrequired: 0 });
  const cards = [
    ['stoppage', 'Stoppages', counts.stoppage, 'Fix first — blocks RFT handover'],
    ['open', 'Active parts', counts.open, 'Coming, stoppages and on-order only'],
    ['notordered', 'Not Ordered', counts.notordered, 'Required parts not ordered yet'],
    ['onorder', 'On Order', counts.onorder, 'Waiting on parts arrival'],
    ['miscacc', 'Misc Acc', counts.miscacc, 'Misc accessory override'],
  ];
  const host = $('#parts-summary-grid');
  if (!host) return;
  host.innerHTML = cards.map(([key, label, count, hint]) => `<button class="parts-summary-card ${escapeHtml(partsDepartmentStatusClass(key === 'open' ? 'notordered' : key))}" type="button" data-parts-summary-filter="${escapeHtml(key)}"><span>${escapeHtml(label)}</span><strong>${count}</strong><small>${escapeHtml(hint)}</small></button>`).join('');
  $$('[data-parts-summary-filter]', host).forEach(button => button.addEventListener('click', () => {
    const select = $('#parts-status-filter');
    if (select) select.value = button.dataset.partsSummaryFilter || 'open';
    renderPartsHome();
  }));
}

function renderPartsHome() {
  const host = $('#parts-home-content');
  const summaryHost = $('#parts-summary-grid');
  if (!host && !summaryHost) return;
  const rows = partsDepartmentRows();
  renderPartsSummary(rows);
  if (!host) return;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No vehicles match the current parts filter</strong><span>Clear search or change the Parts status filter.</span></div>';
    return;
  }
  host.innerHTML = `<div class="parts-table-wrap"><table class="data-table compact-table parts-table">
    <thead><tr>
      <th>Parts status</th>
      <th>JITA</th>
      <th>SN</th>
      <th>ETA / age</th>
      <th>Stoppage / blocker</th>
      <th>Actions</th>
      <th>Client</th>
      <th>Vehicle</th>
      <th>Current stage</th>
      <th>Last update</th>
    </tr></thead>
    <tbody>${rows.map(vehicle => {
      const key = vehicleKey(vehicle);
      const status = partsDepartmentStatus(vehicle);
      const complete = ['issued', 'notrequired'].includes(status);
      const eta = kewdaleEtaValue(vehicle);
      const ageClass = partsEtaCounterClass(vehicle);
      const stage = statusCategoryLabel(vehicle);
      const pmbStage = inferredPmbStage(vehicle) ? ` · ${pmbStageLabel(inferredPmbStage(vehicle))}` : '';
      return `<tr class="parts-row ${escapeHtml(partsDepartmentStatusClass(status))}">
        <td><span class="parts-status-pill ${escapeHtml(partsDepartmentStatusClass(status))}">${escapeHtml(partsDepartmentStatusLabel(status))}</span></td>
        <td class="parts-jita-cell"><span class="parts-jita-label">JITA</span>${jitaIndicator(vehicle)}</td>
        <td>${vehicleIdentityStackHtml(vehicle, { button: true })}</td>
        <td><div class="parts-eta"><strong>${escapeHtml(eta || 'No ETA')}</strong><span class="pmb-age ${escapeHtml('pmb-age-' + ageClass)}">${escapeHtml(partsEtaCounterLabel(vehicle))}</span></div></td>
        <td>${status === 'stoppage' ? `<span class="parts-stoppage-text" title="${escapeHtml(partsStoppageReason(vehicle))}">${escapeHtml(truncate(partsStoppageReason(vehicle), 50))}</span>` : '<span class="subtle">No blocker recorded</span>'}</td>
        <td><div class="parts-action-group">
          <button class="small-button danger-button" type="button" data-parts-stoppage="${escapeHtml(key)}" ${complete ? 'disabled' : ''}>Stoppage</button>
          <button class="small-button" type="button" data-parts-ordered="${escapeHtml(key)}" ${complete ? 'disabled' : ''}>Ordered</button>
          <button class="small-button primary" type="button" data-parts-complete="${escapeHtml(key)}">Complete</button>
          ${status === 'stoppage' ? `<button class="small-button" type="button" data-parts-clear-stoppage="${escapeHtml(key)}">Clear stoppage</button>` : ''}
        </div></td>
        <td><span title="${escapeHtml(vehicleCustomerName(vehicle) || '')}">${escapeHtml(truncate(vehicleCustomerName(vehicle) || 'Dealer Order', 34))}</span></td>
        <td><span title="${escapeHtml(displayVehicle(vehicle))}">${escapeHtml(truncate(displayVehicle(vehicle), 48))}</span></td>
        <td>${escapeHtml(stage + pmbStage)}</td>
        <td>${escapeHtml(partsLastUpdateLabel(vehicle) || '')}</td>
      </tr>`;
    }).join('')}</tbody></table></div>`;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  $$('[data-parts-ordered]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsOrdered(button.dataset.partsOrdered)));
  $$('[data-parts-complete]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsComplete(button.dataset.partsComplete)));
  $$('[data-parts-stoppage]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsStoppage(button.dataset.partsStoppage)));
  $$('[data-parts-clear-stoppage]', host).forEach(button => button.addEventListener('click', () => clearVehiclePartsStoppage(button.dataset.partsClearStoppage)));
}

function markVehiclePartsOrdered(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const operator = getCurrentOperatorName();
  recordVehicleAudit(vehicle, 'Parts marked ordered', { by: operator });
  saveVehicleEdits(key, {
    pdcRequiresParts: true,
    pdcPartsOrdered: true,
    pdcPartsOrderedAt: nowIsoString(),
    pdcPartsOrderedBy: operator,
  });
}

function markVehiclePartsComplete(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const def = partsJobDef();
  const operator = getCurrentOperatorName();
  const updates = {
    pdcRequiresParts: true,
    pdcPartsOrdered: true,
    pdcPartsOrderedAt: vehicle.pdcPartsOrderedAt || nowIsoString(),
    pdcPartsOrderedBy: vehicle.pdcPartsOrderedBy || operator,
    pdcPartsStoppage: false,
    pdcPartsStoppageReason: '',
    pdcPartsStoppageClearedAt: nowIsoString(),
    pdcPartsStoppageClearedBy: operator,
  };
  if (def) {
    updates[def.completeKey] = true;
    updates[def.completeAtKey] = nowIsoString();
    updates[def.completeByKey] = operator;
  }
  recordVehicleAudit(vehicle, 'Parts signed off complete', { by: operator });
  saveVehicleEdits(key, updates);
}

function markVehiclePartsStoppage(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const reason = cleanNavisionText(window.prompt('Enter parts stoppage reason:', partsStoppageReason(vehicle) === 'Parts stoppage recorded' ? '' : partsStoppageReason(vehicle)) || '');
  if (!reason) return;
  const def = partsJobDef();
  const operator = getCurrentOperatorName();
  const updates = {
    pdcRequiresParts: true,
    pdcPartsStoppage: true,
    pdcPartsStoppageReason: reason,
    pdcPartsStoppageAt: nowIsoString(),
    pdcPartsStoppageBy: operator,
  };
  if (def) updates[def.completeKey] = false;
  recordVehicleAudit(vehicle, 'Parts stoppage recorded', { reason, by: operator });
  saveVehicleEdits(key, updates);
}

function clearVehiclePartsStoppage(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const operator = getCurrentOperatorName();
  recordVehicleAudit(vehicle, 'Parts stoppage cleared', { reason: partsStoppageReason(vehicle), by: operator });
  saveVehicleEdits(key, {
    pdcPartsStoppage: false,
    pdcPartsStoppageReason: '',
    pdcPartsStoppageClearedAt: nowIsoString(),
    pdcPartsStoppageClearedBy: operator,
  });
}

function exportPartsCsv() {
  const rows = partsDepartmentRows();
  const headers = ['Parts Status','Stock','Toyota Order','Client','Vehicle','Kewdale ETA','Kewdale ETA Age','Current Stage','PMB Stage','Parts Ordered','Parts Ordered By','Parts Issued','Parts Issued By','Parts Stoppage','Parts Stoppage Reason','Last Parts Update'];
  const def = partsJobDef();
  const lines = [headers.join(',')].concat(rows.map(vehicle => [
    partsDepartmentStatusLabel(partsDepartmentStatus(vehicle)),
    displayStockNumber(vehicle), vehicle.order || '', vehicle.client || vehicle.toyotaCustomer || '', displayVehicle(vehicle),
    kewdaleEtaValue(vehicle), pmbAgeLabel(vehicle), statusCategoryLabel(vehicle), pmbStageLabel(inferredPmbStage(vehicle)),
    partsOrdered(vehicle) ? 'Yes' : 'No', vehicle.pdcPartsOrderedBy || '', def && pdcJobComplete(vehicle, def) ? 'Yes' : 'No', def ? (vehicle[def.completeByKey] || '') : '',
    vehicle.pdcPartsStoppage === true ? 'Yes' : 'No', partsStoppageReason(vehicle), partsLastUpdateLabel(vehicle)
  ].map(csvEscape).join(',')));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'pdc-parts-home-export.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function rftHomeStatus(vehicle = {}) {
  if (statusCategory(vehicle) !== 'rft') return '';
  const issues = vehicleRftGateIssues(vehicle);
  if (issues.length) return 'blocked';
  const required = pdcRequiredJobs(vehicle);
  if (required.length && required.every(def => pdcJobComplete(vehicle, def))) return 'complete';
  return 'ready';
}

function rftHomeStatusLabel(status = '') {
  return { blocked: 'Blocked', ready: 'Ready', complete: 'Complete' }[status] || 'Ready';
}

function rftHomeStatusClass(status = '') {
  return {
    blocked: 'parts-status-stoppage rft-status-blocked',
    ready: 'parts-status-ordered rft-status-ready',
    complete: 'parts-status-complete rft-status-complete',
  }[status] || 'parts-status-ordered rft-status-ready';
}

function rftHomeRows() {
  const q = ($('#rft-search')?.value || '').trim().toLowerCase();
  const filter = $('#rft-status-filter')?.value || 'open';
  return app.data
    .filter(vehicle => statusCategory(vehicle) === 'rft' && !vehicleCollectedFromRft(vehicle))
    .filter(vehicle => {
      const status = rftHomeStatus(vehicle);
      const matchesStatus = filter === 'all'
        || (filter === 'open' && status !== 'complete')
        || status === filter;
      if (!matchesStatus) return false;
      if (!q) return true;
      const hay = [
        displayStockNumber(vehicle), vehicle.order, vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle), vehicle.client, vehicle.toyotaCustomer,
        displayVehicle(vehicle), pdcCompletedJobsText(vehicle), pdcOutstandingJobsText(vehicle),
        vehicleRftGateIssues(vehicle).join(' '), rftHomeStatusLabel(status), vehicle.rftTransferredBy || '',
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => {
      const rank = { blocked: 0, ready: 1, complete: 2 };
      const rankDiff = (rank[rftHomeStatus(a)] ?? 9) - (rank[rftHomeStatus(b)] ?? 9);
      if (rankDiff) return rankDiff;
      const timeA = parseIsoTimestamp(a.rftTransferredAt || a.pdcLocationUpdatedAt || '')?.getTime() || 0;
      const timeB = parseIsoTimestamp(b.rftTransferredAt || b.pdcLocationUpdatedAt || '')?.getTime() || 0;
      if (timeA !== timeB) return timeB - timeA;
      return String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || ''), undefined, { numeric: true });
    });
}

function renderRftSummary() {
  const all = app.data.filter(vehicle => statusCategory(vehicle) === 'rft' && !vehicleCollectedFromRft(vehicle));
  const counts = all.reduce((acc, vehicle) => {
    const status = rftHomeStatus(vehicle);
    acc[status] = (acc[status] || 0) + 1;
    if (status !== 'complete') acc.open += 1;
    return acc;
  }, { open: 0, blocked: 0, ready: 0, complete: 0 });
  const cards = [
    ['blocked', 'Blocked', counts.blocked, 'Missing required sign-offs'],
    ['open', 'Open RFT', counts.open, 'Blocked or ready for final checks'],
    ['ready', 'Ready', counts.ready, 'Can be handed over'],
    ['complete', 'Complete', counts.complete, 'All required jobs ticked'],
  ];
  const host = $('#rft-summary-grid');
  if (!host) return;
  host.innerHTML = cards.map(([key, label, count, hint]) => `<button class="parts-summary-card rft-summary-card ${escapeHtml(rftHomeStatusClass(key === 'open' ? 'ready' : key))}" type="button" data-rft-summary-filter="${escapeHtml(key)}"><span>${escapeHtml(label)}</span><strong>${count}</strong><small>${escapeHtml(hint)}</small></button>`).join('');
  $$('[data-rft-summary-filter]', host).forEach(button => button.addEventListener('click', () => {
    const select = $('#rft-status-filter');
    if (select) select.value = button.dataset.rftSummaryFilter || 'open';
    renderRftHome();
  }));
}

function rftCompletionTicksHtml(vehicle = {}) {
  const required = pdcRequiredJobs(vehicle);
  if (!required.length) return '<span class="subtle">No required jobs set</span>';
  const key = vehicleKey(vehicle);
  return `<div class="rft-completion-ticks">${required.map(def => {
    const complete = pdcJobComplete(vehicle, def);
    const title = pdcJobCompletionTitle(vehicle, def);
    return `<label class="rft-completion-tick ${complete ? 'is-complete' : 'is-pending'}" title="${escapeHtml(title)}"><input type="checkbox" data-rft-completion-key="${escapeHtml(key)}" data-rft-completion-job="${escapeHtml(def.key)}" ${complete ? 'checked' : ''} /> <span><b>${complete ? '✓' : escapeHtml(def.short)}</b>${escapeHtml(def.label)}</span></label>`;
  }).join('')}</div>`;
}

function renderRftHome() {
  const host = $('#rft-home-content');
  const summaryHost = $('#rft-summary-grid');
  if (!host && !summaryHost) return;
  const rows = rftHomeRows();
  renderRftSummary();
  if (!host) return;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No RFT vehicles match the current filter</strong><span>Clear search or change the RFT status filter.</span></div>';
    return;
  }
  host.innerHTML = `<div class="parts-table-wrap rft-table-wrap"><table class="data-table compact-table parts-table rft-table">
    <thead><tr>
      <th>RFT status</th>
      <th>SN</th>
      <th>Completion ticks</th>
      <th>Blocker / outstanding</th>
      <th>Actions</th>
      <th>Client</th>
      <th>Vehicle</th>
      <th>Transferred</th>
    </tr></thead>
    <tbody>${rows.map(vehicle => {
      const key = vehicleKey(vehicle);
      const status = rftHomeStatus(vehicle);
      const issues = vehicleRftGateIssues(vehicle);
      const transferredAt = parseIsoTimestamp(vehicle.rftTransferredAt || vehicle.pdcLocationUpdatedAt || '');
      const transferredLabel = transferredAt ? transferredAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '';
      const blocker = issues.length ? issues.join(' · ') : pdcOutstandingJobsText(vehicle);
      return `<tr class="rft-row ${escapeHtml(rftHomeStatusClass(status))}">
        <td><span class="parts-status-pill ${escapeHtml(rftHomeStatusClass(status))}">${escapeHtml(rftHomeStatusLabel(status))}</span></td>
        <td>${vehicleIdentityStackHtml(vehicle, { button: true })}</td>
        <td>${rftCompletionTicksHtml(vehicle)}</td>
        <td><span class="rft-blocker-text" title="${escapeHtml(blocker)}">${escapeHtml(truncate(blocker, 72))}</span></td>
        <td><div class="parts-action-group rft-action-group">
          <label class="rft-collected-check" title="Tick once the vehicle has been collected"><input type="checkbox" data-rft-collected-key="${escapeHtml(key)}" /> <span>Collected</span></label>
          <button class="small-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>
          <button class="small-button primary" type="button" data-rft-email="${escapeHtml(key)}" ${status === 'blocked' ? `disabled title="Cannot email: ${escapeHtml(blocker)}"` : 'title="Email salesperson: all required jobs are signed off"'}>Email salesperson</button>
        </div></td>
        <td><span title="${escapeHtml(vehicleCustomerName(vehicle) || '')}">${escapeHtml(truncate(vehicleCustomerName(vehicle) || 'Dealer Order', 34))}</span></td>
        <td><span title="${escapeHtml(displayVehicle(vehicle))}">${escapeHtml(truncate(displayVehicle(vehicle), 48))}</span></td>
        <td>${escapeHtml(transferredLabel || '')}</td>
      </tr>`;
    }).join('')}</tbody></table></div>`;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  $$('[data-rft-completion-key]', host).forEach(input => input.addEventListener('change', () => {
    togglePdcJobCompletionFromCard(input.dataset.rftCompletionKey, input.dataset.rftCompletionJob);
  }));
  $$('[data-rft-email]', host).forEach(button => button.addEventListener('click', () => draftRftSalespersonNotificationEmail([button.dataset.rftEmail])));
  bindRftCollectedInputs(host);
}


function markRftVehicleCollected(key, collected = true) {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  if (!collected && vehicleCollectedFromRft(vehicle)) {
    window.alert('Completed vehicles are locked once collected. Open the vehicle and contact an admin if this was marked collected in error.');
    renderAll();
    return;
  }
  const operator = getCurrentOperatorName();
  const now = nowIsoString();
  recordVehicleAudit(vehicle, 'Collected from RFT', { by: operator || 'Unknown' });
  saveVehicleEdits(vehicleKey(vehicle), {
    rftCollected: true,
    completedVehicle: true,
    rftCollectedAt: vehicle.rftCollectedAt || now,
    rftCollectedBy: vehicle.rftCollectedBy || operator,
  });
}

function bindRftCollectedInputs(root = document) {
  $$('[data-rft-collected-key]', root).forEach(input => input.addEventListener('click', event => event.stopPropagation()));
  $$('[data-rft-collected-key]', root).forEach(input => input.addEventListener('change', () => {
    const key = input.dataset.rftCollectedKey;
    if (!key) return;
    markRftVehicleCollected(key, input.checked);
  }));
}

function completedVehicleRows() {
  const q = ($('#completed-search')?.value || '').trim().toLowerCase();
  return app.data
    .filter(vehicleCollectedFromRft)
    .filter(vehicle => {
      if (!q) return true;
      const hay = [
        displayStockNumber(vehicle), vehicle.order, vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle), vehicle.client, vehicle.toyotaCustomer,
        displayVehicle(vehicle), vehicle.rftCollectedBy || '', vehicle.rftCollectedAt || '', pdcCompletedJobsText(vehicle),
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => {
      const timeA = parseIsoTimestamp(a.rftCollectedAt || '')?.getTime() || 0;
      const timeB = parseIsoTimestamp(b.rftCollectedAt || '')?.getTime() || 0;
      if (timeA !== timeB) return timeB - timeA;
      return String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || ''), undefined, { numeric: true });
    });
}

function renderCompletedVehicles() {
  const host = $('#completed-vehicles-content');
  if (!host) return;
  const rows = completedVehicleRows();
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No completed vehicles yet</strong><span>Tick Collected on the RFT screen after a vehicle has been picked up.</span></div>';
    return;
  }
  host.innerHTML = `<div class="parts-table-wrap completed-table-wrap"><table class="data-table compact-table parts-table completed-table">
    <thead><tr>
      <th>Collected</th>
      <th>SN</th>
      <th>Client</th>
      <th>Vehicle</th>
      <th>Key</th>
      <th>Collected time</th>
      <th>Collected by</th>
      <th>Actions</th>
    </tr></thead>
    <tbody>${rows.map(vehicle => {
      const key = vehicleKey(vehicle);
      const collectedAt = parseIsoTimestamp(vehicle.rftCollectedAt || '');
      const collectedLabel = collectedAt ? collectedAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '';
      return `<tr class="completed-vehicle-row">
        <td><label class="rft-collected-check completed-collected-check is-locked" title="Collected vehicles are locked"><input type="checkbox" checked disabled /> <span>Collected</span></label></td>
        <td>${vehicleIdentityStackHtml(vehicle, { button: true })}</td>
        <td><span title="${escapeHtml(vehicleCustomerName(vehicle) || '')}">${escapeHtml(truncate(vehicleCustomerName(vehicle) || 'Dealer Order', 34))}</span></td>
        <td><span title="${escapeHtml(displayVehicle(vehicle))}">${escapeHtml(truncate(displayVehicle(vehicle), 48))}</span></td>
        <td>${escapeHtml(vehicleKeyNumber(vehicle) || '')}</td>
        <td>${escapeHtml(collectedLabel)}</td>
        <td>${escapeHtml(vehicle.rftCollectedBy || '')}</td>
        <td><button class="small-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button></td>
      </tr>`;
    }).join('')}</tbody></table></div>`;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  bindRftCollectedInputs(host);
}

function exportCompletedVehiclesCsv() {
  const rows = completedVehicleRows();
  const headers = ['Stock','Toyota Order','Key','Client','Vehicle','Collected At','Collected By','Completed Jobs'];
  const lines = [headers.join(',')].concat(rows.map(vehicle => [
    displayStockNumber(vehicle), vehicle.order || '', vehicleKeyNumber(vehicle), vehicle.client || vehicle.toyotaCustomer || '',
    displayVehicle(vehicle), vehicle.rftCollectedAt || '', vehicle.rftCollectedBy || '', pdcCompletedJobsText(vehicle),
  ].map(csvEscape).join(',')));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'pdc-completed-vehicles-export.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function exportRftCsv() {
  const rows = rftHomeRows();
  const headers = ['RFT Status','Stock','Toyota Order','Key','Client','Vehicle','Completed Jobs','Outstanding Jobs','Blockers','Transferred At','Transferred By'];
  const lines = [headers.join(',')].concat(rows.map(vehicle => [
    rftHomeStatusLabel(rftHomeStatus(vehicle)), displayStockNumber(vehicle), vehicle.order || '', vehicleKeyNumber(vehicle),
    vehicle.client || vehicle.toyotaCustomer || '', displayVehicle(vehicle), pdcCompletedJobsText(vehicle),
    pdcOutstandingJobsText(vehicle), vehicleRftGateIssues(vehicle).join(' | '), vehicle.rftTransferredAt || vehicle.pdcLocationUpdatedAt || '', vehicle.rftTransferredBy || ''
  ].map(csvEscape).join(',')));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'pdc-rft-home-export.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function groupBy(items, fn) {
  return items.reduce((acc, item) => {
    const key = fn(item);
    acc[key] = acc[key] || [];
    acc[key].push(item);
    return acc;
  }, {});
}

function renderTvBoard() {
  const host = $('#tv-board');
  if (!host) return;
  const rows = app.data.slice();
  const pmbRows = rows.filter(vehicle => statusCategory(vehicle) === 'pmb');
  const blocked = pmbRows.filter(isPdcBlocked);
  const gateIssues = pmbRows.filter(vehicle => vehicleRftGateIssues(vehicle).length);
  const stageCards = STATUS_TAB_DEFS.filter(def => def.key !== 'all').map(def => {
    const count = rows.filter(matchesQuickFilter(def.key)).length;
    return `<button class="tv-stage-card ${escapeHtml(def.className)}" type="button" data-tv-filter="${escapeHtml(def.key)}"><span>${escapeHtml(def.label)}</span><strong>${count}</strong><small>${escapeHtml(def.sub)}</small></button>`;
  }).join('');

  const lanes = [
    { value: '', label: 'Unassigned' },
    ...PMB_STAGE_DEFS.map(def => ({ value: def.value, label: def.label }))
  ];
  const laneCards = lanes.map(lane => {
    const vehicles = lane.value ? pmbRows.filter(v => inferredPmbStage(v) === lane.value) : pmbRows.filter(v => !inferredPmbStage(v));
    const metrics = pmbLaneMetrics(lane.value, vehicles);
    const oldest = metrics.oldestStageDays ? `${metrics.oldestStageDays}d oldest` : 'No ageing';
    const className = metrics.overLimit ? 'over-limit' : metrics.blockedCount ? 'has-blocked' : metrics.atLimit ? 'at-limit' : 'normal';
    return `<article class="tv-lane-card ${escapeHtml(className)}">
      <div><span>${escapeHtml(lane.label)}</span><strong>${vehicles.length}/${escapeHtml(metrics.limitLabel)}</strong></div>
      <small>${escapeHtml(oldest)} · ${metrics.blockedCount} blocked · ${vehiclesWithRftGateIssues(vehicles).length} gate issue${vehiclesWithRftGateIssues(vehicles).length === 1 ? '' : 's'}</small>
    </article>`;
  }).join('');

  const overdue = pmbRows
    .map(vehicle => ({ vehicle, days: pmbStageAgeDays(vehicle), limit: pmbLaneAgeLimit(inferredPmbStage(vehicle)) }))
    .filter(row => row.days !== null && row.days > row.limit)
    .sort((a, b) => b.days - a.days)
    .slice(0, 12);

  const issueList = gateIssues.slice(0, 12).map(vehicle => `<button class="tv-issue-row" type="button" data-open-stock="${escapeHtml(vehicleKey(vehicle))}">
    ${vehicleIdentityStackHtml(vehicle)}
    <small>${escapeHtml(vehicleRftGateIssues(vehicle).join(' · '))}</small>
  </button>`).join('') || '<div class="subtle">No active RFT gate issues.</div>';

  const overdueList = overdue.map(row => `<button class="tv-issue-row" type="button" data-open-stock="${escapeHtml(vehicleKey(row.vehicle))}">
    ${vehicleIdentityStackHtml(row.vehicle)}
    <span>${escapeHtml(pmbStageLabel(inferredPmbStage(row.vehicle)) || 'Unallocated')}</span>
    <small>${escapeHtml(row.days)} days in bucket · limit ${escapeHtml(row.limit)} day${row.limit === 1 ? '' : 's'}</small>
  </button>`).join('') || '<div class="subtle">No overdue PMB bucket ageing.</div>';

  const operator = String(localStorage.getItem(OPERATOR_NAME_KEY) || '').trim() || 'Not set';
  const role = String(localStorage.getItem(OPERATOR_ROLE_KEY) || '').trim() || 'Not set';
  host.innerHTML = `
    <div class="tv-operator-strip"><span>Current operator: <strong>${escapeHtml(operator)}</strong> · Role: <strong>${escapeHtml(role)}</strong></span><button class="small-button" id="tv-set-operator" type="button">Set operator</button></div>
    <div class="tv-stage-grid">${stageCards}</div>
    <div class="tv-section-grid">
      <section class="tv-panel"><h3>PMB WIP limits</h3><div class="tv-lane-grid">${laneCards}</div></section>
      <section class="tv-panel"><h3>RFT gate / blocked work</h3><div class="tv-issue-list">${issueList}</div></section>
      <section class="tv-panel"><h3>Overdue bucket ageing</h3><div class="tv-issue-list">${overdueList}</div></section>
    </div>`;
  on($('#tv-set-operator'), 'click', setOperatorProfile);
  $$('[data-tv-filter]', host).forEach(button => button.addEventListener('click', () => applyQuickFilter(button.dataset.tvFilter)));
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
}

function renderCustomers() {
  const grid = $('#customer-grid');
  if (!grid) return;
  const q = ($('#customer-search')?.value || '').toLowerCase();
  const byCustomer = groupBy(app.data, v => v.client || v.toyotaCustomer || 'Unknown');
  const cards = Object.entries(byCustomer)
    .filter(([name]) => !q || name.toLowerCase().includes(q))
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(0, 72)
    .map(([name, vehicles]) => {
      const first = vehicles.find(v => v.contact) || vehicles[0];
      const statuses = [...new Set(vehicles.map(v => v.toyotaStatus).filter(Boolean))];
      const next = vehicles.map(v => scotEtaOnly(v.etaAtDealer)).filter(Boolean).sort((a, b) => (parseDateAU(a)?.getTime() || 0) - (parseDateAU(b)?.getTime() || 0))[0] || '';
      const salesPeople = [...new Set(vehicles.map(v => salesPersonInitials(consultantName(v))))].join(', ');
      return `<article class="customer-card">
        <h3>${escapeHtml(name)}</h3>
        <div class="customer-meta">
          <span class="badge neutral">${vehicles.length} vehicle${vehicles.length > 1 ? 's' : ''}</span>
          
        </div>
        <div class="subtle">SP: ${escapeHtml(salesPeople || '--')}</div>
        <div class="subtle">Contact: ${escapeHtml(first.contact || 'Add contact')}</div>
        <div class="subtle">Next ETA: ${escapeHtml(next)}</div>
        <div class="customer-meta">${vehicles.map(v => `<button class="vehicle-chip" data-stock="${escapeHtml(vehicleKey(v))}">${escapeHtml(displayStockNumber(v) || v.order || 'TBA')} · ${escapeHtml(displayVehicle(v) || 'Vehicle')}</button>`).join('')}</div>
        <div>${statuses.slice(0, 3).map(s => `<span class="badge ${statusClass(s)}">${escapeHtml(s)}</span>`).join(' ')}</div>
      </article>`;
    });
  grid.innerHTML = cards.join('') || $('#empty-state').innerHTML;
  $$('.vehicle-chip').forEach(chip => chip.addEventListener('click', () => openVehicleModal(chip.dataset.stock)));
}

function openCustomerModal() {
  const modal = $('#customer-modal');
  if (!modal) return;
  $('#new-customer-form')?.reset();
  $('#new-customer-message').textContent = '';
  modal.hidden = false;
  document.body.classList.add('modal-open');
  $('#new-customer-form input[name="client"]')?.focus();
}

function closeCustomerModal() {
  const modal = $('#customer-modal');
  if (!modal) return;
  modal.hidden = true;
  if ($('#vehicle-modal')?.hidden !== false) document.body.classList.remove('modal-open');
}

function addCustomerFromForm(e) {
  e.preventDefault();
  const form = e.currentTarget;
  const data = Object.fromEntries(new FormData(form).entries());
  const stock = (data.stock || '').trim() || `NEW-${Date.now().toString().slice(-6)}`;
  const vehicle = {
    id: `manual-${Date.now()}`,
    sourceRow: '',
    stock,
    client: (data.client || '').trim(),
    internalStatus: (data.internalStatus || '').trim(),
    deliveryDate: '',
    vehicle: (data.vehicle || '').trim(),
    financeNote: '',
    group: 'Manual entry',
    source: 'Manual',
    order: '',
    toyotaCustomer: '',
    contact: (data.contact || '').trim(),
    toyotaVehicle: '',
    suffix: '',
    colour: '',
    trim: '',
    origMth: '',
    prodMth: '',
    compPlate: '',
    arrivalPort: '',
    toyotaStatus: '',
    etaAtDealer: (data.etaAtDealer || '').trim(),
    epodReceipt: '',
    jitQty: '',
    jitaPartsOrdered: data.jitaPartsOrdered || 'Unknown',
    pdcJobcard: (data.pdcJobcard || '').trim(),
    consultant: (data.consultant || '').trim(),
  };
  const added = loadAddedVehicles();
  added.unshift(vehicle);
  saveAddedVehicles(added);
  app.data.unshift(vehicle);
  populateFilters();
  renderAll();
  closeCustomerModal();
  showView('dashboard');
  openVehicleModal(stock);
}

function handleVehiclePoSelect(key, event) {
  const files = [...(event.target.files || [])];
  if (!files.length) return;
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const editKey = vehicleKey(vehicle);
  const tasksStore = loadPoTasks();
  const filesStore = loadPoFiles();
  const currentFiles = filesStore[editKey] || vehicle.poFiles || [];
  const names = files.map(file => file.name);
  const combinedFiles = [...new Set(currentFiles.concat(names))];
  filesStore[editKey] = combinedFiles;
  const currentTasks = tasksStore[editKey] || vehicle.poTasks || [];
  tasksStore[editKey] = currentTasks;
  savePoFiles(filesStore);
  savePoTasks(tasksStore);
  const lowerNames = combinedFiles.join(' ').toLowerCase();
  saveVehicleEdits(editKey, {
    buildPoRaised: true,
    pdcRequiresTint: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('tint')) || lowerNames.includes('tint'),
    pdcRequiresHoist: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('hoist')) || /hoist|suspension|gvm|lift|tow/.test(lowerNames),
    pdcRequiresFitting: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('fitting')) || /\bfit\b|fitment|fitting|pdi|accessor|bullbar|towbar|canopy|tray/.test(lowerNames),
    pdcRequiresFabrication: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('fabrication')) || /tray|bar|rack|tank|canopy|winch|gvm|fabricat/.test(lowerNames),
    pdcRequiresElectrical: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('electrical')) || /electrical|auto.?elec|12v|uhf|battery|compressor|spotlight|light bar|anderson|redarc/i.test(lowerNames),
    pdcRequiresTyre: pdcJobRequired(vehicle, PDC_JOB_BY_KEY.get('tyre')) || /tyre|tire|wheel/.test(lowerNames),
  });
  app.data = buildVehicleData();
  renderAll();
  app.selectedStock = editKey;
  renderDetail();
}

function extractStockFromPoFilename(filename) {
  const match = String(filename || '').match(/\b\d{8}\b/);
  return match ? match[0] : '';
}

function tasksFromPurchaseOrderName(filename) {
  const name = String(filename || '').toLowerCase();
  const tasks = [];
  if (name.includes('131') || name.includes('parts order')) {
    tasks.push(
      'Supply heavy duty canvas seat cover - rear',
      'Supply heavy duty canvas seat covers - front',
      'Supply tow bar with small round plug'
    );
  }
  if (name.includes('pmg') || name.includes('sublet')) {
    tasks.push(
      'PMG complete vehicle pre-delivery',
      'PMG supply complementary full tank of fuel',
      'Fit ARB air compressor under bonnet with pump kit',
      'Fit ARB dual battery system with 12v to rear',
      'Fit ARB Frontier long range fuel tank (180L)',
      'Fit ARB OME GVM upgrade',
      'Fit ARB roof rack',
      'Fit ARB Solis spotlights',
      'Fit ARB Summit MK2 bullbar',
      'Fit ARB Winch - Warn EVO 10000lb S/Rope',
      'Fit dash mat',
      'Fit GME XRS UHF with AE4072B antenna',
      'Tyre upgrade - BFG KO3 265/75/16 x 6',
      'Wheel upgrade - Sunraysia Black Steel x 6',
      'Fit window tint',
      'Tray work: TWA steel tray / underbody and headboard tyre hangers'
    );
  }
  return tasks.length ? tasks : ['Review uploaded purchase order and confirm workshop work required'];
}

function ensureVehicleForPo(stock) {
  let vehicle = app.data.find(v => v.stock === stock);
  if (vehicle) return vehicle;
  vehicle = {
    id: `po-${stock}`,
    sourceRow: '',
    stock,
    client: 'Customer from PO',
    internalStatus: '',
    deliveryDate: '',
    vehicle: '',
    financeNote: '',
    group: 'Purchase order upload',
    source: 'PO only',
    order: '',
    toyotaCustomer: '',
    contact: '',
    toyotaVehicle: '',
    suffix: '',
    colour: '',
    trim: '',
    origMth: '',
    prodMth: '',
    compPlate: '',
    arrivalPort: '',
    toyotaStatus: '',
    etaAtDealer: '',
    epodReceipt: '',
    jitQty: '',
    jitaPartsOrdered: 'Unknown',
    consultant: '',
    poTasks: [],
    poFiles: [],
  };
  const added = loadAddedVehicles();
  added.unshift(vehicle);
  saveAddedVehicles(added);
  app.data.unshift(vehicle);
  return vehicle;
}

function handlePoSelect(e) {
  const files = [...(e.target.files || [])];
  const statusList = $('#po-status-list');
  const card = $('#po-scan-card');
  if (!files.length) return;
  const tasksStore = loadPoTasks();
  const filesStore = loadPoFiles();
  const results = [];
  files.forEach(file => {
    const stock = extractStockFromPoFilename(file.name);
    if (!stock) {
      results.push({ file: file.name, stock: '', count: 0, message: 'No stock number found in file name' });
      return;
    }
    const vehicle = ensureVehicleForPo(stock);
    const currentTasks = tasksStore[stock] || vehicle.poTasks || [];
    const newTasks = tasksFromPurchaseOrderName(file.name);
    const combined = [...new Set(currentTasks.concat(newTasks))];
    tasksStore[stock] = combined;
    const currentFiles = filesStore[stock] || vehicle.poFiles || [];
    const combinedFiles = [...new Set(currentFiles.concat(file.name))];
    filesStore[stock] = combinedFiles;
    vehicle.poTasks = combined;
    vehicle.poFiles = combinedFiles;
    const combinedText = combined.join(' ').toLowerCase();
    const inferredFlags = {
      buildPoRaised: Boolean(combinedFiles.length || combined.length),
      pdcRequiresTint: combinedText.includes('window tint') || combinedText.includes('tint'),
      pdcRequiresHoist: /hoist|suspension|gvm|lift|tow/.test(combinedText),
      pdcRequiresFitting: /\bfit\b|fitment|fitting|pdi|accessor|bullbar|towbar|canopy|tray/.test(combinedText),
      pdcRequiresFabrication: combinedText.includes('tray') || combinedText.includes('fabricat') || combinedText.includes('bullbar') || combinedText.includes('bar work'),
      pdcRequiresElectrical: /electrical|auto.?elec|12v|dual battery|battery system|uhf|spotlight|light bar|beacon|compressor|anderson|redarc|brake controller|dc dc|dcdc|dash cam|camera|reverse camera|power outlet|usb/.test(combinedText),
      pdcRequiresTyre: /tyre|tire|wheel/.test(combinedText)
    };
    saveVehicleEdits(stock, { internalStatus: '', ...inferredFlags });
    results.push({ file: file.name, stock, count: newTasks.length, message: `${combined.length} total task${combined.length === 1 ? '' : 's'} loaded` });
  });
  savePoTasks(tasksStore);
  savePoFiles(filesStore);
  app.data = buildVehicleData();
  if (card) {
    card.querySelector('.po-files strong').textContent = `${files.length} file${files.length === 1 ? '' : 's'}`;
    card.querySelector('.po-matched strong').textContent = `${results.filter(r => r.stock).length} matched`;
  }
  if (statusList) {
    statusList.innerHTML = results.map(r => `<div class="po-status-row ${r.stock ? 'ok' : 'warn'}"><strong>${escapeHtml(r.stock || 'Unmatched')}</strong><span>${escapeHtml(r.file)} - ${escapeHtml(r.message)}</span></div>`).join('');
  }
  renderAll();
}


function updateAutocareScanButton() {
  const button = $('#scan-autocare');
  if (!button) return;
  const hasFiles = Boolean(app.autocareFiles && app.autocareFiles.length);
  const hasPaste = Boolean(($('#autocare-paste')?.value || '').trim());
  button.disabled = !(hasFiles || hasPaste);
}

function handleAutocareSelect(e) {
  const files = [...(e.target.files || [])];
  app.autocareFiles = files;
  const card = $('#autocare-scan-card');
  if (card) {
    card.querySelector('.autocare-files strong').textContent = `${files.length} file${files.length === 1 ? '' : 's'}`;
    card.querySelector('.autocare-detected strong').textContent = 'Ready to scan';
    card.querySelector('.autocare-matched strong').textContent = '0 matched';
  }
  app.autocareScan = null;
  renderAutocareResults(null);
  updateAutocareScanButton();
}

function clearAutocareResults() {
  app.autocareFiles = [];
  app.autocareScan = null;
  saveJson(AUTOCARE_RESULTS_KEY, null);
  const upload = $('#autocare-upload');
  const paste = $('#autocare-paste');
  if (upload) upload.value = '';
  if (paste) paste.value = '';
  const card = $('#autocare-scan-card');
  if (card) {
    card.querySelector('.autocare-files strong').textContent = '0 files';
    card.querySelector('.autocare-detected strong').textContent = '0 detected';
    card.querySelector('.autocare-matched strong').textContent = '0 matched';
  }
  renderAutocareResults(null);
  updateAutocareScanButton();
}

async function scanAutocareNotice() {
  const button = $('#scan-autocare');
  if (button) {
    button.disabled = true;
    button.textContent = 'Scanning...';
  }
  const files = app.autocareFiles || [];
  const pastedText = ($('#autocare-paste')?.value || '').trim();
  const texts = [];
  const warnings = [];

  for (const file of files) {
    try {
      const text = await extractTextFromPdfFile(file);
      texts.push(text);
    } catch (error) {
      warnings.push(`${file.name}: ${error.message || error}`);
    }
  }
  if (pastedText) texts.push(pastedText);

  const combinedText = texts.join('\n\n');
  const parsed = parseAutocareNoticeText(combinedText, files.map(file => file.name));
  parsed.warnings = [...(parsed.warnings || []), ...warnings];
  if (!combinedText.trim() && warnings.length) {
    parsed.warnings.unshift('No notice text could be read. Paste the Autocare notice text into the optional paste area, then scan again.');
  }

  const result = applyAutocareDespatch(parsed);
  app.autocareScan = result;
  saveJson(AUTOCARE_RESULTS_KEY, result);
  renderAutocareResults(result);
  updateAutocareControlStats(result);

  if (button) {
    button.textContent = 'Scan Autocare notice';
    updateAutocareScanButton();
  }
}

async function extractTextFromPdfFile(file) {
  if (window.pdfjsLib) {
    try {
      const data = new Uint8Array(await file.arrayBuffer());
      const pdf = await window.pdfjsLib.getDocument({ data }).promise;
      const pages = [];
      for (let pageNo = 1; pageNo <= pdf.numPages; pageNo += 1) {
        const page = await pdf.getPage(pageNo);
        const textContent = await page.getTextContent();
        pages.push(pdfTextContentToLines(textContent));
      }
      return pages.join('\n\n');
    } catch (_) {
      // Fall through to the built-in lightweight PDF reader.
    }
  }
  return extractTextFromPdfStreams(file);
}

async function extractTextFromPdfStreams(file) {
  const buffer = await file.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  const decoder = new TextDecoder('latin1');
  const raw = decoder.decode(bytes);
  const chunks = [];
  const warnings = [];
  let searchFrom = 0;

  while (searchFrom < raw.length) {
    const streamIndex = raw.indexOf('stream', searchFrom);
    if (streamIndex === -1) break;
    let dataStart = streamIndex + 'stream'.length;
    if (bytes[dataStart] === 13) dataStart += 1;
    if (bytes[dataStart] === 10) dataStart += 1;
    const endIndex = raw.indexOf('endstream', dataStart);
    if (endIndex === -1) break;
    let dataEnd = endIndex;
    while (dataEnd > dataStart && (bytes[dataEnd - 1] === 10 || bytes[dataEnd - 1] === 13 || bytes[dataEnd - 1] === 32 || bytes[dataEnd - 1] === 9)) dataEnd -= 1;
    const dictStart = Math.max(0, raw.lastIndexOf('<<', streamIndex));
    const dictText = raw.slice(dictStart, streamIndex);
    const streamBytes = bytes.slice(dataStart, dataEnd);
    if (/\/FlateDecode/i.test(dictText)) {
      const inflated = await inflatePdfStreamBytes(streamBytes);
      if (inflated) chunks.push(inflated);
      else warnings.push('A compressed PDF stream could not be read in this browser.');
    } else if (!/\/DCTDecode|\/Image/i.test(dictText)) {
      chunks.push(decoder.decode(streamBytes));
    }
    searchFrom = endIndex + 'endstream'.length;
  }

  const text = chunks.map(pdfContentStreamText).join('\n');
  if (!text.trim() && /VIN|Batch|DESPATCH|Autocare/i.test(raw)) return raw;
  if (!text.trim() && warnings.length) throw new Error(warnings[0]);
  return text;
}

async function inflatePdfStreamBytes(bytes) {
  if (typeof DecompressionStream === 'undefined') return '';
  for (const format of ['deflate', 'deflate-raw']) {
    try {
      const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream(format));
      const inflated = await new Response(stream).arrayBuffer();
      return new TextDecoder('latin1').decode(inflated);
    } catch (_) {
      // Try the next format.
    }
  }
  return '';
}

function pdfContentStreamText(text = '') {
  const parts = [];
  const re = /\((?:\\.|[^\\)])*\)/g;
  let match;
  while ((match = re.exec(text))) parts.push(decodePdfTextLiteral(match[0].slice(1, -1)));
  return parts.length ? parts.join('\n') : text;
}

function decodePdfTextLiteral(value = '') {
  return String(value)
    .replace(/\\([nrtbf()\\])/g, (_, ch) => ({ n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', '(': '(', ')': ')', '\\': '\\' }[ch] || ch))
    .replace(/\\\r?\n/g, '')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

function pdfTextContentToLines(textContent) {
  const rows = [];
  (textContent.items || []).forEach(item => {
    const str = String(item.str || '').trim();
    if (!str) return;
    const transform = item.transform || [];
    const x = Number(transform[4] || 0);
    const y = Number(transform[5] || 0);
    let row = rows.find(entry => Math.abs(entry.y - y) <= 2);
    if (!row) {
      row = { y, items: [] };
      rows.push(row);
    }
    row.items.push({ x, str });
  });
  return rows
    .sort((a, b) => b.y - a.y)
    .map(row => row.items.sort((a, b) => a.x - b.x).map(item => item.str).join(' '))
    .join('\n');
}

function parseAutocareNoticeText(text, sourceFiles = []) {
  const raw = String(text || '').replace(/\r/g, '\n').replace(/\f/g, '\n');
  const loadNumber = (raw.match(/Load\s*Number\s*:?\s*([A-Z0-9-]+)/i) || [])[1] || '';
  const haulierRegistration = (raw.match(/Haulier\s*Registration\s*:?\s*([A-Z0-9-]+)/i) || [])[1] || '';
  const byVin = new Map();
  const warnings = [];
  const lines = raw.split('\n').map(cleanAutocareLine).filter(Boolean);
  const compactRaw = raw.replace(/\s+/g, ' ');
  const compactDetailRe = /VIN:\s*([A-HJ-NPR-Z0-9]{17})[\s\S]{0,700}?Model:\s*(.*?)\s+Version:\s*(.*?)\s+Frame\s+No#?\s*:?\s*([A-Z0-9]+)\s+Batch\s+No#?\s*:?\s*(\d{6,12})/gi;
  let compactMatch;
  while ((compactMatch = compactDetailRe.exec(compactRaw))) {
    mergeAutocareVehicle(byVin, {
      vin: compactMatch[1],
      model: [compactMatch[2], compactMatch[3]].filter(Boolean).join(' '),
      modelDescription: compactMatch[2],
      versionDescription: compactMatch[3],
      frame: compactMatch[4],
      batch: compactMatch[5],
    });
  }

  lines.forEach(line => {
    const match = line.match(/^([A-HJ-NPR-Z0-9]{17})\s+(.+)$/i);
    if (!match) return;
    const description = match[2]
      .replace(/\s+Colour\s*$/i, '')
      .replace(/\s+Page\s+\d+\s*$/i, '')
      .trim();
    if (/^(manufacturer|model|version|frame|batch|area description)\b/i.test(description)) return;
    mergeAutocareVehicle(byVin, { vin: match[1], model: description });
  });

  raw.split(/VEHICLE DETAILS/i).slice(1).forEach(block => {
    const vin = normalizeVin(extractAutocareLineValue(block, /^VIN\s*:?\s*/i) || ((block.match(/\b[A-HJ-NPR-Z0-9]{17}\b/i) || [])[0]));
    if (!vin) return;
    const model = extractAutocareLineValue(block, /^Model\s*:?\s*/i);
    const version = extractAutocareLineValue(block, /^Version\s*:?\s*/i);
    const frame = extractAutocareLineValue(block, /^Frame\s+No#?\s*:?\s*/i);
    const batch = extractAutocareLineValue(block, /^Batch\s+No#?\s*:?\s*/i);
    mergeAutocareVehicle(byVin, {
      vin,
      model: [model, version].filter(Boolean).join(' '),
      modelDescription: model,
      versionDescription: version,
      frame,
      batch,
    });
  });

  if (!byVin.size) {
    [...raw.matchAll(/\b[A-HJ-NPR-Z0-9]{17}\b/gi)].forEach(match => mergeAutocareVehicle(byVin, { vin: match[0] }));
  }

  const vehicles = [...byVin.values()].sort((a, b) => String(a.vin).localeCompare(String(b.vin), 'en-AU', { numeric: true }));
  if (!vehicles.length && raw.trim()) warnings.push('No 17-character VINs were detected in the Autocare notice text.');
  return { sourceFiles, loadNumber, haulierRegistration, vehicles, warnings };
}

function cleanAutocareLine(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function extractAutocareLineValue(block, labelRegex) {
  const lines = String(block || '').split('\n').map(cleanAutocareLine).filter(Boolean);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!labelRegex.test(line)) continue;
    const value = line.replace(labelRegex, '').replace(/^[:#\s]+/, '').trim();
    return value || cleanAutocareLine(lines[index + 1] || '');
  }
  return '';
}

function normalizeVin(value) {
  const match = String(value || '').toUpperCase().match(/\b[A-HJ-NPR-Z0-9]{17}\b/);
  return match ? match[0] : '';
}

function normalizeBatch(value) {
  return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '').trim();
}

function mergeAutocareVehicle(map, entry) {
  const vin = normalizeVin(entry.vin);
  if (!vin) return;
  const current = map.get(vin) || { vin, model: '', modelDescription: '', versionDescription: '', colour: '', batch: '', frame: '' };
  const nextModel = cleanAutocareLine(entry.model || '');
  const nextModelDescription = cleanAutocareLine(entry.modelDescription || '');
  const nextVersionDescription = cleanAutocareLine(entry.versionDescription || '');
  if (nextModel && nextModel.length >= current.model.length) current.model = nextModel;
  if (nextModelDescription) current.modelDescription = nextModelDescription;
  if (nextVersionDescription) current.versionDescription = nextVersionDescription;
  if (entry.colour || entry.color) current.colour = cleanAutocareLine(entry.colour || entry.color);
  if (entry.batch) current.batch = normalizeBatch(entry.batch);
  if (entry.frame) current.frame = normalizeBatch(entry.frame);
  map.set(vin, current);
}

function findAutocareVehicleMatch(item) {
  const vin = normalizeVin(item.vin);
  const batch = normalizeBatch(item.batch);
  const frame = normalizeBatch(item.frame);

  for (const vehicle of app.data) {
    const vehicleVin = normalizeVin(vehicle.vin || vehicle.autocareVin || vehicle.frameVin);
    if (vin && vehicleVin && vin === vehicleVin) return { vehicle, matchedBy: 'VIN' };
  }

  if (batch) {
    for (const vehicle of app.data) {
      const toyota = getToyotaMatch(vehicle) || {};
      const candidates = [vehicle.stock, vehicle.order, vehicle.batch, vehicle.toyotaBatch, vehicle.autocareBatch, toyota.batch, toyota.stock, toyota.order]
        .map(normalizeBatch)
        .filter(Boolean);
      if (candidates.includes(batch)) return { vehicle, matchedBy: 'Batch / Stock' };
    }
  }

  if (frame) {
    for (const vehicle of app.data) {
      const candidates = [vehicle.frame, vehicle.frameNo, vehicle.autocareFrame]
        .map(normalizeBatch)
        .filter(Boolean);
      if (candidates.includes(frame)) return { vehicle, matchedBy: 'Frame' };
    }
  }
  return null;
}

function applyAutocareDespatch(parsed) {
  const edits = loadVehicleEdits();
  const matched = [];
  const unmatched = [];
  const updatedAt = new Date().toISOString();

  (parsed.vehicles || []).forEach(item => {
    const match = findAutocareVehicleMatch(item);
    if (!match) {
      unmatched.push(item);
      return;
    }
    const key = vehicleKey(match.vehicle);
    const updates = {
      autocareDespatched: true,
      autocareVin: item.vin || match.vehicle.autocareVin || '',
      autocareBatch: item.batch || match.vehicle.autocareBatch || '',
      autocareFrame: item.frame || match.vehicle.autocareFrame || '',
      autocareModel: item.model || match.vehicle.autocareModel || '',
      autocareModelDescription: item.modelDescription || match.vehicle.autocareModelDescription || '',
      autocareVersionDescription: item.versionDescription || match.vehicle.autocareVersionDescription || '',
      autocareColour: item.colour || match.vehicle.autocareColour || '',
      autocareLoadNumber: parsed.loadNumber || match.vehicle.autocareLoadNumber || '',
      autocareNoticeFiles: parsed.sourceFiles || [],
      autocareUpdatedAt: updatedAt,
    };
    matched.push({ vehicle: { ...match.vehicle }, item, matchedBy: match.matchedBy, previousStatus: match.vehicle.toyotaStatus || '' });
    edits[key] = { ...(edits[key] || {}), ...updates };
    Object.assign(match.vehicle, updates);
  });

  saveJson(EDITS_KEY, edits);
  app.data = buildVehicleData();
  populateFilters();
  renderKpis();
  renderVehicleTable();
  renderKanban();
  renderTvBoard();
  renderAdminLists();
  renderCustomers();

  return { ...parsed, matched, unmatched, updatedAt };
}

function updateAutocareControlStats(result) {
  const card = $('#autocare-scan-card');
  if (!card || !result) return;
  const fileCount = app.autocareFiles?.length || 0;
  card.querySelector('.autocare-files strong').textContent = `${fileCount} file${fileCount === 1 ? '' : 's'}`;
  card.querySelector('.autocare-detected strong').textContent = `${result.vehicles.length} detected`;
  card.querySelector('.autocare-matched strong').textContent = `${result.matched.length} matched`;
}

function renderAutocareResults(result) {
  const host = $('#autocare-status-list');
  const clearButton = $('#autocare-clear');
  const zplAllButton = $('#autocare-zpl-all');
  const zplUnmatchedButton = $('#autocare-zpl-unmatched');
  const hasResult = Boolean(result);
  if (clearButton) clearButton.disabled = !hasResult;
  if (zplAllButton) zplAllButton.disabled = !(hasResult && result.vehicles && result.vehicles.length);
  if (zplUnmatchedButton) zplUnmatchedButton.disabled = !(hasResult && result.unmatched && result.unmatched.length);
  if (!host) return;
  if (!result) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>No Autocare notice scanned</strong><span>Upload a despatch notice to update matched vehicles and see any VINs/batches not in the system.</span></div>`;
    return;
  }

  const sourceLabel = result.sourceFiles?.length ? result.sourceFiles.join(', ') : 'Pasted text';
  const warningList = (result.warnings || []).map(warning => `<div class="summary-row warn"><strong>Warning</strong><span>${escapeHtml(warning)}</span></div>`).join('');
  const matchedList = result.matched.length ? result.matched.map((row, index) => {
    const current = app.data.find(vehicle => vehicleKey(vehicle) === vehicleKey(row.vehicle)) || row.vehicle;
    const key = autocareResultItemKey(row.item, index);
    return `<div class="summary-row ok autocare-result-row"><div>${vehicleIdentityStackHtml(current)}<span>${escapeHtml(displayVehicle(current) || row.item.model || 'Vehicle')} · matched by ${escapeHtml(row.matchedBy)}${row.previousStatus ? ` · was ${escapeHtml(row.previousStatus)}` : ''}</span></div><button class="small-button" type="button" data-autocare-zpl-single="matched:${escapeHtml(key)}">Print label</button></div>`;
  }).join('') : `<div class="summary-row"><strong>None matched</strong><span>No vehicles in the CRM matched the VINs or batches on this notice.</span></div>`;

  const unmatchedList = result.unmatched.length ? result.unmatched.map((item, index) => {
    const key = autocareResultItemKey(item, index);
    return `
    <div class="summary-row warn autocare-result-row autocare-unmatched-row" data-autocare-unmatched-key="${escapeHtml(key)}">
      <div class="autocare-result-copy">
        <strong>${escapeHtml(item.batch || item.vin || 'Unknown')}</strong>
        <span>${item.vin ? `VIN ${escapeHtml(item.vin)} · ` : ''}${escapeHtml(item.model || 'Model not shown')}${item.frame ? ` · Frame ${escapeHtml(item.frame)}` : ''}</span>
      </div>
      <label class="autocare-name-field"><span>Customer name for label</span><input type="text" data-autocare-name-key="${escapeHtml(key)}" placeholder="Leave blank for (Dealer Order)" /></label>
      <button class="small-button" type="button" data-autocare-zpl-single="unmatched:${escapeHtml(key)}">Print label</button>
    </div>`;
  }).join('') : `<div class="summary-row ok"><strong>All matched</strong><span>Every vehicle on the despatch notice was found in the CRM.</span></div>`;

  host.innerHTML = `
    <div class="scot-summary-grid autocare-summary-grid">
      <div class="summary-stat"><span>Notice</span><strong>${escapeHtml(result.loadNumber || 'No load #')}</strong></div>
      <div class="summary-stat"><span>Vehicles detected</span><strong>${result.vehicles.length}</strong></div>
      <div class="summary-stat"><span>Marked</span><strong>${result.matched.length}</strong></div>
      <div class="summary-stat"><span>Not in system</span><strong>${result.unmatched.length}</strong></div>
    </div>
    <div class="autocare-zpl-actions">
      <button class="primary" type="button" data-autocare-zpl-mode="all">Print labels from this notice</button>
      <button class="small-button" type="button" data-autocare-zpl-mode="unmatched" ${result.unmatched.length ? '' : 'disabled'}>Print not-in-system only</button>
      <span class="subtle">For vehicles not in the CRM, enter a customer name or leave it blank to print (Dealer Order).</span>
    </div>
    <div class="summary-section">
      <h3>Matched and marked ${escapeHtml(AUTOCARE_DESPATCH_STATUS)}</h3>
      ${matchedList}
    </div>
    <div class="summary-section">
      <h3>Vehicles on the despatch notice not in our system</h3>
      ${unmatchedList}
    </div>
    ${warningList ? `<div class="summary-section"><h3>Extraction notes</h3>${warningList}</div>` : ''}
    <div class="subtle autocare-source">Source: ${escapeHtml(sourceLabel)}${result.haulierRegistration ? ` · Haulier ${escapeHtml(result.haulierRegistration)}` : ''}</div>
  `;

  $$('[data-autocare-zpl-mode]', host).forEach(button => {
    button.addEventListener('click', () => printZplFromAutocareResults(button.dataset.autocareZplMode));
  });
  $$('[data-autocare-zpl-single]', host).forEach(button => {
    button.addEventListener('click', () => printZplFromAutocareSingle(button.dataset.autocareZplSingle));
  });
}

function autocareResultItemKey(item, index = 0) {
  return normalizeBatch(item?.vin || item?.batch || item?.frame || `autocare-${index}`) || `autocare-${index}`;
}

function findAutocareResultItem(kindAndKey) {
  const result = app.autocareScan;
  if (!result) return null;
  const [kind, key] = String(kindAndKey || '').split(':');
  const normalizedKey = normalizeBatch(key);
  if (kind === 'matched') {
    return (result.matched || []).find((row, index) => autocareResultItemKey(row.item, index) === normalizedKey) || null;
  }
  if (kind === 'unmatched') {
    return (result.unmatched || []).find((item, index) => autocareResultItemKey(item, index) === normalizedKey) || null;
  }
  return null;
}

function getAutocareEnteredName(item, index = 0) {
  const key = autocareResultItemKey(item, index);
  const input = $$('[data-autocare-name-key]').find(field => field.dataset.autocareNameKey === key);
  return cleanZplField(input?.value || '');
}

function splitAutocareModelForZpl(item = {}) {
  const explicitModel = cleanZplField(item.modelDescription || '');
  const explicitVersion = cleanZplField(item.versionDescription || '');
  if (explicitModel || explicitVersion) {
    return {
      model: explicitModel || cleanZplField(item.model || ''),
      spec: explicitVersion,
    };
  }
  const combined = cleanZplField(item.model || '');
  if (!combined) return { model: '', spec: '' };
  const upper = combined.toUpperCase();
  const knownPrefixes = [
    'LANDCRUISER 300 SERIES', 'LANDCRUISER', 'COROLLA CROSS', 'YARIS CROSS',
    'PRADO', 'HILUX', 'RAV4', 'CAMRY', 'FORTUNER', 'COROLLA', 'HIACE', 'LC300', 'LC70', 'BZ4X'
  ];
  const found = knownPrefixes.find(prefix => upper === prefix || upper.startsWith(`${prefix} `));
  if (!found) return { model: combined, spec: '' };
  return {
    model: combined.slice(0, found.length).trim(),
    spec: combined.slice(found.length).trim(),
  };
}

function autocareItemToZplRow(item = {}, customerName = '') {
  const vin = normalizeVin(item.vin);
  const modelParts = splitAutocareModelForZpl(item);
  const wmi = vin ? vin.slice(0, 3) : '';
  const vds = vin ? vin.slice(3, 9) : '';
  const frame = vin ? vin.slice(9) : cleanZplField(item.frame || '').replace(/\s+/g, '');
  return [
    cleanZplField(item.batch || item.vin || item.frame || ''),
    cleanZplField(customerName),
    '',
    cleanZplField(modelParts.model),
    cleanZplField(modelParts.spec),
    '',
    cleanZplField(item.colour || item.color || ''),
    cleanZplField(wmi),
    cleanZplField(vds),
    cleanZplField(frame),
  ].join('\t');
}

function matchedAutocareRowToZplRow(row, index = 0) {
  const current = app.data.find(vehicle => vehicleKey(vehicle) === vehicleKey(row.vehicle)) || row.vehicle;
  if (current) {
    const enriched = {
      ...current,
      autocareVin: row.item?.vin || current.autocareVin,
      autocareBatch: row.item?.batch || current.autocareBatch,
      autocareFrame: row.item?.frame || current.autocareFrame,
      autocareModel: row.item?.model || current.autocareModel,
      autocareModelDescription: row.item?.modelDescription || current.autocareModelDescription,
      autocareVersionDescription: row.item?.versionDescription || current.autocareVersionDescription,
      autocareColour: row.item?.colour || current.autocareColour,
    };
    const tsv = selectedVehicleToZplRow(enriched).split('\t');
    if (!tsv[0]) tsv[0] = cleanZplField(row.item?.batch || row.item?.vin || '');
    if (!tsv[3]) {
      const modelParts = splitAutocareModelForZpl(row.item || {});
      tsv[3] = cleanZplField(modelParts.model);
      if (!tsv[4]) tsv[4] = cleanZplField(modelParts.spec);
    }
    return tsv.join('\t');
  }
  return autocareItemToZplRow(row.item, getAutocareEnteredName(row.item, index));
}


function zplFromAutocareRows(rows = []) {
  if (!rows.length) return { zpl: '', count: 0, warnings: ['No Autocare vehicles selected for printing.'] };
  const tsv = [ZPL_REQUIRED_COLUMNS.join('\t'), ...rows].join('\n');
  const parsed = parseZplInput(tsv);
  const zpl = parsed.vehicles.map(vehicleToZplBlock).join('\n\n');
  return { zpl, count: parsed.vehicles.length, warnings: parsed.warnings };
}

async function printZplFromAutocareResults(mode = 'all') {
  const result = app.autocareScan;
  if (!result) return;
  const rows = [];
  if (mode === 'all') {
    (result.matched || []).forEach((row, index) => rows.push(matchedAutocareRowToZplRow(row, index)));
  }
  if (mode === 'all' || mode === 'unmatched') {
    (result.unmatched || []).forEach((item, index) => rows.push(autocareItemToZplRow(item, getAutocareEnteredName(item, index))));
  }
  const print = zplFromAutocareRows(rows);
  if (!print.count) return;
  if (print.warnings.length && !window.confirm(`There are ${print.warnings.length} label warning${print.warnings.length === 1 ? '' : 's'} before printing. Print anyway?\n\n${print.warnings.slice(0, 6).join('\n')}${print.warnings.length > 6 ? '\n...' : ''}`)) return;
  await printRawZpl(print.zpl, `${print.count} Autocare vehicle${print.count === 1 ? '' : 's'}`);
}

async function printZplFromAutocareSingle(kindAndKey) {
  const result = app.autocareScan;
  if (!result) return;
  const [kind] = String(kindAndKey || '').split(':');
  let row = '';
  if (kind === 'matched') {
    const matched = findAutocareResultItem(kindAndKey);
    if (!matched) return;
    row = matchedAutocareRowToZplRow(matched, (result.matched || []).indexOf(matched));
  } else {
    const item = findAutocareResultItem(kindAndKey);
    if (!item) return;
    row = autocareItemToZplRow(item, getAutocareEnteredName(item, (result.unmatched || []).indexOf(item)));
  }
  const print = zplFromAutocareRows([row]);
  if (!print.count) return;
  if (print.warnings.length && !window.confirm(`There are ${print.warnings.length} label warning${print.warnings.length === 1 ? '' : 's'} before printing. Print anyway?\n\n${print.warnings.slice(0, 6).join('\n')}${print.warnings.length > 6 ? '\n...' : ''}`)) return;
  await printRawZpl(print.zpl, 'one Autocare vehicle');
}

function generateZplFromAutocareResults(mode = 'all') {
  const result = app.autocareScan;
  if (!result) return;
  const rows = [];
  if (mode === 'all') {
    (result.matched || []).forEach((row, index) => rows.push(matchedAutocareRowToZplRow(row, index)));
  }
  if (mode === 'all' || mode === 'unmatched') {
    (result.unmatched || []).forEach((item, index) => rows.push(autocareItemToZplRow(item, getAutocareEnteredName(item, index))));
  }
  if (!rows.length) return;
  writeZplRowsToGenerator(rows, mode === 'unmatched' ? 'Prepared from Autocare not-in-system vehicles' : 'Prepared from Autocare despatch notice');
}

function generateZplFromAutocareSingle(kindAndKey) {
  const result = app.autocareScan;
  if (!result) return;
  const [kind] = String(kindAndKey || '').split(':');
  let row = '';
  if (kind === 'matched') {
    const matched = findAutocareResultItem(kindAndKey);
    if (!matched) return;
    row = matchedAutocareRowToZplRow(matched, (result.matched || []).indexOf(matched));
  } else {
    const item = findAutocareResultItem(kindAndKey);
    if (!item) return;
    row = autocareItemToZplRow(item, getAutocareEnteredName(item, (result.unmatched || []).indexOf(item)));
  }
  writeZplRowsToGenerator([row], 'Prepared from one Autocare despatch vehicle');
}

function writeZplRowsToGenerator(rows, title) {
  const input = $('#zpl-input');
  if (input) input.value = [ZPL_REQUIRED_COLUMNS.join('\t'), ...rows].join('\n');
  showView('zpl');
  generateZplFromInput();
  const summary = $('#zpl-summary');
  if (summary) {
    summary.insertAdjacentHTML('afterbegin', `<div class="zpl-selected-notice"><strong>${escapeHtml(title)}</strong><span>${rows.length} label block${rows.length === 1 ? '' : 's'} created from the last Autocare scan. Review any VIN warnings, then copy the ZPL output.</span></div>`);
  }
}




function isRealStockNumber(value) {
  return /^\d{8}$/.test(String(value || '').trim()) && String(value || '').trim() !== '00000000';
}

function detectNewStockNumberRows() {
  const byOrder = groupBy(app.data.filter(v => v.order), v => String(v.order));
  return Object.entries(byOrder).flatMap(([order, vehicles]) => {
    const withStock = vehicles.find(v => isRealStockNumber(v.stock));
    const pending = vehicles.find(v => !isRealStockNumber(v.stock) || String(v.stock || '').startsWith('PENDING-') || String(v.stock || '') === '0');
    if (!withStock || !pending || withStock.stock === pending.stock) return [];
    return [{
      order,
      stock: withStock.stock,
      client: withStock.client || withStock.toyotaCustomer || pending.client || pending.toyotaCustomer || '',
      vehicle: displayVehicle(withStock) || displayVehicle(pending),
    }];
  });
}

function buildScotSummary() {
  const reviewRows = buildReviewRows();
  const changedRows = reviewRows.filter(r => r.changed.length);
  const newStockNumbers = detectNewStockNumberRows();
  const scotOnly = app.data.filter(v => v.source === 'Navision only');
  const pendingNoStock = app.data.filter(v => (!isRealStockNumber(v.stock) || String(v.stock || '').startsWith('PENDING-')) && v.order);
  return {
    rowsDetected: app.report.totalSalesOrders || app.data.length,
    matchedVehicles: Object.keys(app.matches || {}).length,
    proposedChanges: changedRows.length,
    statusChanges: changedRows.filter(r => r.changed.some(([field]) => field === 'Toyota Status')).length,
    etaChanges: changedRows.filter(r => r.changed.some(([field]) => field === 'ETA At Dealer')).length,
    newStockNumbers,
    scotOnly,
    pendingNoStock,
  };
}

function renderScotSummary(scanned = false) {
  const host = $('#scot-summary');
  if (!host) return;
  if (!scanned) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>Ready to scan</strong><span>After scanning, this will show changed fields, new stock numbers, and new Navision-only vehicles.</span></div>`;
    return;
  }
  const summary = buildScotSummary();
  const newStockList = summary.newStockNumbers.slice(0, 8).map(item => `
    <div class="summary-row important"><strong>${escapeHtml(item.stock)}</strong><span>Toyota order ${escapeHtml(item.order)} · ${escapeHtml(item.client)} · ${escapeHtml(item.vehicle)}</span></div>
  `).join('') || `<div class="summary-row"><strong>None detected</strong><span>No order-only vehicles received a new stock number in this sample scan.</span></div>`;
  const scotOnlyList = summary.scotOnly.slice(0, 10).map(v => `
    <div class="summary-row warn">${vehicleIdentityStackHtml(v)}<span>${escapeHtml(displayVehicle(v))}${v.toyotaStatus ? ` · ${escapeHtml(v.toyotaStatus)}` : ''}</span></div>
  `).join('') || `<div class="summary-row"><strong>None detected</strong><span>No new Navision-only vehicles found.</span></div>`;

  host.innerHTML = `
    <div class="scot-summary-grid">
      <div class="summary-stat"><span>Rows detected</span><strong>${summary.rowsDetected}</strong></div>
      <div class="summary-stat"><span>Matched</span><strong>${summary.matchedVehicles}</strong></div>
      <div class="summary-stat"><span>Proposed changes</span><strong>${summary.proposedChanges}</strong></div>
      <div class="summary-stat"><span>Status changes</span><strong>${summary.statusChanges}</strong></div>
      <div class="summary-stat"><span>ETA changes</span><strong>${summary.etaChanges}</strong></div>
      <div class="summary-stat"><span>New vehicles</span><strong>${summary.scotOnly.length}</strong></div>
    </div>
    <div class="summary-section">
      <h3>New stock numbers issued</h3>
      ${newStockList}
    </div>
    <div class="summary-section">
      <h3>New vehicles from Navision not already in the tracker</h3>
      ${scotOnlyList}
      ${summary.scotOnly.length > 10 ? `<div class="subtle">Showing first 10 of ${summary.scotOnly.length}. Use the Navision-only dashboard filter to see all.</div>` : ''}
    </div>
  `;
}


function updateNavisionControlStats(result = null) {
  const card = $('#navision-scan-card');
  if (!card) return;
  const raw = ($('#navision-paste')?.value || '').trim();
  const fileName = app.navisionFileName || (raw ? 'Pasted text' : 'Waiting for text');
  const preview = raw && !result ? parseNavisionInput(raw, navisionImportOptionsFromDom()) : null;
  const rowCount = result?.parsed?.vehicles?.length ?? preview?.vehicles?.length ?? 0;
  const changed = result ? ((result.added?.length || 0) + (result.updated?.length || 0)) : 0;
  const fileEl = card.querySelector('.navision-file strong');
  const detectedEl = card.querySelector('.navision-detected strong');
  const updatedEl = card.querySelector('.navision-updated strong');
  if (fileEl) fileEl.textContent = fileName;
  if (detectedEl) detectedEl.textContent = raw || result ? `${rowCount} row${rowCount === 1 ? '' : 's'}` : '0 rows';
  if (updatedEl) {
    if (result) updatedEl.textContent = `${changed} changed`;
    else if (preview?.warnings?.length) updatedEl.textContent = `${preview.warnings.length} warning${preview.warnings.length === 1 ? '' : 's'}`;
    else updatedEl.textContent = raw ? 'Ready to import' : '0 changed';
  }
}

function updateNavisionImportButton() {
  const raw = ($('#navision-paste')?.value || '').trim();
  const button = $('#import-navision');
  const clear = $('#navision-clear');
  if (button) button.disabled = !raw;
  if (clear) clear.disabled = !raw && !app.navisionImport;
  updateNavisionControlStats(app.pendingNavisionImport || app.navisionImport);
}

async function handleNavisionFileSelect(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  const input = $('#navision-paste');
  const summary = $('#navision-status-list');
  try {
    app.navisionFileName = file.name;
    app.navisionImport = null;
    app.pendingNavisionImport = null;
    if (summary) summary.innerHTML = `<div class="empty-state compact-empty"><strong>${escapeHtml(file.name)}</strong><span>Reading file...</span></div>`;
    let text = '';
    let sourceLabel = 'Text loaded';
    if (isXlsxFile(file)) {
      const parsed = await readXlsxVehicleSpreadsheet(file);
      text = parsed.text;
      app.navisionFileName = `${file.name} · ${parsed.sheetName || 'first sheet'}`;
      sourceLabel = `Excel sheet converted: ${parsed.sheetName || 'first sheet'} (${parsed.rows.length} row${parsed.rows.length === 1 ? '' : 's'})`;
    } else if (/\.xls$/i.test(file.name)) {
      throw new Error('Legacy .xls files are not supported in this browser-only version. Save the spreadsheet as .xlsx, .csv or .tsv and upload it again.');
    } else {
      text = await readTextFile(file);
    }
    if (input) input.value = text;
    updateNavisionImportButton();
    if (summary) {
      summary.innerHTML = `<div class="empty-state compact-empty"><strong>${escapeHtml(file.name)}</strong><span>${escapeHtml(sourceLabel)}. Click Import vehicle updates to update the tracker.</span></div>`;
    }
  } catch (error) {
    console.error('File import failed', error);
    if (input) input.value = '';
    app.navisionFileName = file.name;
    updateNavisionImportButton();
    if (summary) {
      summary.innerHTML = `<div class="summary-row error"><strong>${escapeHtml(file.name)}</strong><span>${escapeHtml(error.message || 'Could not read this file.')}</span></div>`;
    }
    window.alert(error.message || 'Could not read this file.');
  }
}

function isXlsxFile(file = {}) {
  return /\.xlsx$/i.test(file.name || '') || /spreadsheetml\.sheet/i.test(file.type || '');
}

function readTextFile(file) {
  if (file.text) return file.text();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(reader.error || new Error('Could not read text file.'));
    reader.readAsText(file);
  });
}

function readArrayBufferFile(file) {
  if (file.arrayBuffer) return file.arrayBuffer();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error || new Error('Could not read spreadsheet.'));
    reader.readAsArrayBuffer(file);
  });
}

async function readXlsxVehicleSpreadsheet(file) {
  if (typeof DecompressionStream === 'undefined') {
    throw new Error('This browser cannot read .xlsx files directly. Save the spreadsheet as CSV/TSV, or use a current Chrome/Edge browser.');
  }
  const buffer = await readArrayBufferFile(file);
  const files = await unzipXlsxEntries(buffer);
  const sharedStrings = parseXlsxSharedStrings(files['xl/sharedStrings.xml'] || '');
  const dateStyles = parseXlsxDateStyles(files['xl/styles.xml'] || '');
  const sheets = workbookSheetEntries(files);
  const candidates = sheets.length ? sheets : Object.keys(files).filter(name => /^xl\/worksheets\/sheet\d+\.xml$/i.test(name)).map(name => ({ name, path: name }));
  let fallback = null;
  for (const sheet of candidates) {
    const xml = files[sheet.path];
    if (!xml) continue;
    const rows = parseXlsxSheetRows(xml, sharedStrings, dateStyles);
    if (!rows.length) continue;
    if (!fallback) fallback = { sheetName: sheet.name || sheet.path, rows };
    const header = rows[0] || [];
    const headerText = header.map(normalizeNavisionHeader).join('|');
    if (headerText.includes('order') && (headerText.includes('batch') || headerText.includes('stock')) && headerText.includes('model description')) {
      return { sheetName: sheet.name || sheet.path, rows, text: xlsxRowsToDelimitedText(rows) };
    }
  }
  if (!fallback) throw new Error('No usable rows were found in the Excel workbook.');
  return { ...fallback, text: xlsxRowsToDelimitedText(fallback.rows) };
}

async function unzipXlsxEntries(buffer) {
  const bytes = new Uint8Array(buffer);
  const entries = {};
  const decoder = new TextDecoder('utf-8');
  const eocdOffset = findZipEndOfCentralDirectory(bytes);
  if (eocdOffset < 0) throw new Error('This does not look like a valid .xlsx file.');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const totalEntries = view.getUint16(eocdOffset + 10, true);
  let centralOffset = view.getUint32(eocdOffset + 16, true);
  for (let i = 0; i < totalEntries; i += 1) {
    if (view.getUint32(centralOffset, true) !== 0x02014b50) break;
    const method = view.getUint16(centralOffset + 10, true);
    const compressedSize = view.getUint32(centralOffset + 20, true);
    const nameLength = view.getUint16(centralOffset + 28, true);
    const extraLength = view.getUint16(centralOffset + 30, true);
    const commentLength = view.getUint16(centralOffset + 32, true);
    const localOffset = view.getUint32(centralOffset + 42, true);
    const name = decoder.decode(bytes.slice(centralOffset + 46, centralOffset + 46 + nameLength));
    const localNameLength = view.getUint16(localOffset + 26, true);
    const localExtraLength = view.getUint16(localOffset + 28, true);
    const dataStart = localOffset + 30 + localNameLength + localExtraLength;
    const compressed = bytes.slice(dataStart, dataStart + compressedSize);
    let contents;
    if (method === 0) contents = compressed;
    else if (method === 8) contents = new Uint8Array(await inflateRawDeflate(compressed));
    else contents = null;
    if (contents) entries[normalizeZipPath(name)] = decoder.decode(contents);
    centralOffset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

function findZipEndOfCentralDirectory(bytes) {
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 66000); i -= 1) {
    if (bytes[i] === 0x50 && bytes[i + 1] === 0x4b && bytes[i + 2] === 0x05 && bytes[i + 3] === 0x06) return i;
  }
  return -1;
}

async function inflateRawDeflate(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return streamToArrayBuffer(stream);
}

function streamToArrayBuffer(stream) {
  if (new Response(stream).arrayBuffer) return new Response(stream).arrayBuffer();
  return new Promise((resolve, reject) => {
    const reader = stream.getReader();
    const chunks = [];
    reader.read().then(function pump(result) {
      if (result.done) return resolve(new Blob(chunks).arrayBuffer());
      chunks.push(result.value);
      return reader.read().then(pump);
    }).catch(reject);
  });
}

function normalizeZipPath(path = '') {
  const parts = String(path || '').replace(/^\/+/, '').split('/');
  const clean = [];
  parts.forEach(part => {
    if (!part || part === '.') return;
    if (part === '..') clean.pop();
    else clean.push(part);
  });
  return clean.join('/');
}

function joinZipPath(base = '', target = '') {
  if (/^\//.test(target)) return normalizeZipPath(target);
  return normalizeZipPath(`${base.replace(/\/[^/]*$/, '')}/${target}`);
}

function xmlAttr(tag = '', name = '') {
  const match = String(tag || '').match(new RegExp(`\\b${name}="([^"]*)"`, 'i'));
  return match ? decodeXml(match[1]) : '';
}

function decodeXml(value = '') {
  return String(value || '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, num) => String.fromCodePoint(parseInt(num, 10)));
}

function parseXlsxSharedStrings(xml = '') {
  const strings = [];
  String(xml || '').replace(/<si\b[\s\S]*?<\/si>/g, si => {
    const parts = [...si.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(match => decodeXml(match[1]));
    strings.push(parts.join(''));
    return si;
  });
  return strings;
}

function parseXlsxDateStyles(stylesXml = '') {
  const builtinDateIds = new Set([14,15,16,17,18,19,20,21,22,27,28,29,30,31,32,33,34,35,36,45,46,47,50,51,52,53,54,55,56,57,58]);
  const customDateIds = new Set();
  String(stylesXml || '').replace(/<numFmt\b[^>]*\/>/g, tag => {
    const id = Number(xmlAttr(tag, 'numFmtId'));
    const code = xmlAttr(tag, 'formatCode').toLowerCase();
    if (id && /[dmy]/.test(code) && !/\[[^\]]+\]/.test(code)) customDateIds.add(id);
    return tag;
  });
  const xfsMatch = String(stylesXml || '').match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/);
  const xfs = xfsMatch ? xfsMatch[1].match(/<xf\b[^>]*(?:\/>|>[\s\S]*?<\/xf>)/g) || [] : [];
  return xfs.map(tag => {
    const id = Number(xmlAttr(tag, 'numFmtId'));
    return builtinDateIds.has(id) || customDateIds.has(id);
  });
}

function workbookSheetEntries(files = {}) {
  const workbook = files['xl/workbook.xml'] || '';
  const rels = files['xl/_rels/workbook.xml.rels'] || '';
  const relMap = {};
  rels.replace(/<Relationship\b[^>]*\/>/g, tag => {
    const id = xmlAttr(tag, 'Id');
    const target = xmlAttr(tag, 'Target');
    if (id && target) relMap[id] = target;
    return tag;
  });
  const sheets = [];
  workbook.replace(/<sheet\b[^>]*\/>/g, tag => {
    const name = xmlAttr(tag, 'name') || `Sheet ${sheets.length + 1}`;
    const relId = xmlAttr(tag, 'r:id');
    const target = relMap[relId];
    if (target) sheets.push({ name, path: joinZipPath('xl/workbook.xml', target) });
    return tag;
  });
  return sheets;
}

function parseXlsxSheetRows(sheetXml = '', sharedStrings = [], dateStyles = []) {
  const rows = [];
  String(sheetXml || '').replace(/<row\b[^>]*>[\s\S]*?<\/row>/g, rowXml => {
    const row = [];
    rowXml.replace(/<c\b[^>]*(?:\/>|>[\s\S]*?<\/c>)/g, cellXml => {
      const openTag = cellXml.match(/^<c\b[^>]*>/)?.[0] || cellXml;
      const ref = xmlAttr(openTag, 'r');
      const colIndex = columnIndexFromCellRef(ref);
      if (colIndex < 0) return cellXml;
      row[colIndex] = parseXlsxCellValue(cellXml, sharedStrings, dateStyles);
      return cellXml;
    });
    while (row.length && cleanNavisionText(row[row.length - 1]) === '') row.pop();
    if (row.some(cell => cleanNavisionText(cell))) rows.push(row);
    return rowXml;
  });
  return rows;
}

function columnIndexFromCellRef(ref = '') {
  const match = String(ref || '').match(/^([A-Z]+)/i);
  if (!match) return -1;
  return match[1].toUpperCase().split('').reduce((value, ch) => value * 26 + (ch.charCodeAt(0) - 64), 0) - 1;
}

function parseXlsxCellValue(cellXml = '', sharedStrings = [], dateStyles = []) {
  const openTag = String(cellXml || '').match(/^<c\b[^>]*>/)?.[0] || cellXml;
  const type = xmlAttr(openTag, 't');
  const styleIndex = Number(xmlAttr(openTag, 's') || -1);
  if (type === 'inlineStr') {
    return [...String(cellXml).matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(match => decodeXml(match[1])).join('');
  }
  const raw = decodeXml(String(cellXml || '').match(/<v\b[^>]*>([\s\S]*?)<\/v>/)?.[1] || '');
  if (!raw) return '';
  if (type === 's') return sharedStrings[Number(raw)] ?? '';
  if (type === 'b') return raw === '1' ? 'Yes' : 'No';
  if (type === 'd') return isoDateToAu(raw) || raw;
  if (dateStyles[styleIndex] && /^-?\d+(\.\d+)?$/.test(raw)) return excelSerialDateToAu(raw);
  if (/^-?\d+\.0+$/.test(raw)) return raw.replace(/\.0+$/, '');
  return raw;
}

function isoDateToAu(value = '') {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return `${String(date.getUTCDate()).padStart(2, '0')}/${String(date.getUTCMonth() + 1).padStart(2, '0')}/${date.getUTCFullYear()}`;
}

function excelSerialDateToAu(serial) {
  const value = Number(serial);
  if (!Number.isFinite(value)) return String(serial || '');
  const ms = Date.UTC(1899, 11, 30) + Math.round(value * 86400000);
  const date = new Date(ms);
  return `${String(date.getUTCDate()).padStart(2, '0')}/${String(date.getUTCMonth() + 1).padStart(2, '0')}/${date.getUTCFullYear()}`;
}

function tsvCell(value = '') {
  const text = String(value ?? '').replace(/[\r\n]+/g, ' ').trim();
  return /[\t"]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function xlsxRowsToDelimitedText(rows = []) {
  return rows.map(row => row.map(tsvCell).join('\t')).join('\n');
}


function clearNavisionImport() {
  const input = $('#navision-paste');
  const upload = $('#navision-upload');
  if (input) input.value = '';
  if (upload) upload.value = '';
  app.navisionFileName = '';
  app.navisionImport = null;
  app.pendingNavisionImport = null;
  saveJson(NAVISION_IMPORT_RESULTS_KEY, null);
  updateNavisionImportButton();
  const summary = $('#navision-status-list');
  if (summary) {
    summary.innerHTML = '<div class="empty-state compact-empty"><strong>No Navision text imported</strong><span>Paste copied Navision rows, or upload a text/CSV/XLSX file, then click Import vehicle updates.</span></div>';
  }
  updateNavisionControlStats(null);
}

function normalizeNavisionHeader(header = '') {
  return String(header || '')
    .replace(/^\uFEFF/, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function cleanNavisionText(value = '') {
  return String(value ?? '')
    .replace(/[\r\n]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function navisionCutButVehiclePattern(value = '') {
  const text = cleanNavisionText(value).toLowerCase();
  return /\bcut\s+(but|by)\s+vehicle\b/.test(text) || /\bcut\s+vehicle\b/.test(text);
}

function navisionCutButVehicleText(row = [], headerMap = null) {
  const values = [];
  if (headerMap) {
    ['Status', 'Dealer Comments', 'Vehicle Note', 'Instructions', 'Build Status', 'Location Status', 'Sub Location Description'].forEach(column => {
      const value = getNavisionValue(row, headerMap, column);
      if (value) values.push(value);
    });
  }
  if (Array.isArray(row)) values.push(row.map(cleanNavisionText).join(' '));
  return values.find(navisionCutButVehiclePattern) || '';
}

function isNavisionCutButVehicle(vehicle = {}) {
  if (vehicle.navisionCutButVehicle === true) return true;
  return navisionCutButVehiclePattern([
    vehicle.navisionCutButVehicleSource,
    vehicle.navisionDealerComments,
    vehicle.navisionVehicleNote,
    vehicle.navisionBuildStatus,
    vehicle.navisionLocationStatus,
    vehicle.navisionSubLocationDescription,
    vehicle.financeNote,
  ].filter(Boolean).join(' '));
}

function buildNavisionHeaderMap(headers = []) {
  const map = new Map();
  headers.forEach((header, index) => {
    const clean = cleanNavisionText(header).replace(/^\uFEFF/, '');
    const normalized = normalizeNavisionHeader(clean);
    if (clean && !map.has(clean)) map.set(clean, index);
    if (normalized && !map.has(normalized)) map.set(normalized, index);
  });
  return map;
}

function buildHeaderMap(headers = []) {
  return buildNavisionHeaderMap(headers);
}

function hasNavisionColumn(headerMap, column) {
  return headerMap.has(column) || headerMap.has(normalizeNavisionHeader(column));
}

function getNavisionValue(row, headerMap, columns) {
  const names = Array.isArray(columns) ? columns : [columns];
  for (const name of names) {
    const exact = headerMap.get(name);
    const normalized = headerMap.get(normalizeNavisionHeader(name));
    const index = exact !== undefined ? exact : normalized;
    if (index === undefined) continue;
    const value = cleanNavisionText(row[index] || '');
    if (value) return value;
  }
  return '';
}

function formatNavisionProductionMonth(value = '') {
  const text = cleanNavisionText(value);
  const match = text.match(/^(\d{4})(\d{2})$/);
  if (!match) return text;
  return `${match[2]}/${match[1].slice(-2)}`;
}

function productionMonthLabel(value = '') {
  const text = cleanNavisionText(value);
  if (!text) return '';
  const navision = text.match(/^(\d{4})(\d{2})$/);
  if (navision) return `${navision[2]}/${navision[1].slice(-2)}`;
  const slash = text.match(/^(\d{1,2})\/(\d{2}|\d{4})$/);
  if (slash) return `${slash[1].padStart(2, '0')}/${slash[2].slice(-2)}`;
  return text;
}

function productionMonthRank(value = '') {
  const label = productionMonthLabel(value);
  const slash = label.match(/^(\d{1,2})\/(\d{2}|\d{4})$/);
  if (slash) {
    const month = Number(slash[1]);
    const year = Number(slash[2].length === 2 ? `20${slash[2]}` : slash[2]);
    return year * 100 + month;
  }
  const navision = cleanNavisionText(value).match(/^(\d{4})(\d{2})$/);
  if (navision) return Number(navision[1]) * 100 + Number(navision[2]);
  return Number.MAX_SAFE_INTEGER;
}

function sortProductionMonths(months = []) {
  const collator = new Intl.Collator('en-AU', { numeric: true, sensitivity: 'base' });
  return months.slice().sort((a, b) => {
    const ar = productionMonthRank(a);
    const br = productionMonthRank(b);
    const aUnknown = ar === Number.MAX_SAFE_INTEGER;
    const bUnknown = br === Number.MAX_SAFE_INTEGER;
    if (aUnknown && !bUnknown) return 1;
    if (bUnknown && !aUnknown) return -1;
    const rankDiff = br - ar;
    return rankDiff || collator.compare(String(a), String(b));
  });
}

function navisionExpectedDelivery(row, headerMap) {
  const month = getNavisionValue(row, headerMap, 'Expected Customer Delivery Mth');
  const year = getNavisionValue(row, headerMap, 'Expected Customer Delivery Yr');
  return [month, year].filter(Boolean).join(' ');
}

function navisionConsultant(value = '') {
  const text = cleanNavisionText(value);
  const code = text.match(/^([A-Z]{1,4})\b/i);
  if (code && (code[1].length <= 3 || /\d/.test(text))) return code[1].toUpperCase();
  return text;
}

function navisionToyotaStatus(row, headerMap) {
  // Navision-only version: Toyota Status on the dashboard must come only from this column.
  return getNavisionValue(row, headerMap, 'Sub Location Description');
}

function navisionJita(row, headerMap) {
  const value = getNavisionValue(row, headerMap, 'JITA PreOrder');
  if (/^yes$/i.test(value) || (/\d/.test(value) && value !== '0')) return 'Yes';
  if (/^no$/i.test(value)) return 'No';
  return 'Unknown';
}


function explicitImportValue(row, headerMap, columns) {
  const names = Array.isArray(columns) ? columns : [columns];
  const hasAny = names.some(name => hasNavisionColumn(headerMap, name));
  if (!hasAny) return { present: false, value: '' };
  return { present: true, value: getNavisionValue(row, headerMap, names) };
}

function explicitImportBoolean(row, headerMap, columns) {
  const found = explicitImportValue(row, headerMap, columns);
  if (!found.present) return undefined;
  return pdcBooleanFromText(found.value);
}

function buildExplicitPdcUpdatesFromImport(row, headerMap) {
  const updates = {};
  const pairs = [
    ['pdcRequiresTint', ['TINT', 'Tint', 'Requires Tint', 'Tint Required']],
    ['pdcRequiresHoist', ['HOIST', 'Hoist', 'Requires Hoist', 'Hoist Required']],
    ['pdcRequiresFitting', ['FITTING', 'Fitting', 'Fitment', 'Requires Fitting', 'Fitting Required', 'BUILD', 'Build', 'Requires Build', 'Build Required']],
    ['pdcRequiresFabrication', ['FABRICATION', 'Fabrication', 'FAB', 'Fab', 'Requires Fabrication', 'Fabrication Required']],
    ['pdcRequiresElectrical', ['ELECTRICAL', 'Electrical', 'Auto Electrical', 'Auto-Electrical', 'Requires Electrical', 'Electrical Required']],
    ['pdcRequiresTyre', ['TYRE', 'Tyre', 'Tire', 'Wheel', 'Requires Tyre', 'Tyre Required']],
    ['pdcRequiresPitInspection', ['Pit Inspection', 'PIT INSPECTION', 'PI', 'Requires Pit Inspection', 'Pit Inspection Required']],
    ['pdcRequiresParts', ['PARTS', 'Parts', 'Requires Parts', 'Parts Required', 'Parts Needed', 'Parts To Order']],
    ['pdcCompleteTint', ['Tint Complete', 'Tint Completed', 'Tint Done', 'TINT DONE']],
    ['pdcCompleteHoist', ['Hoist Complete', 'Hoist Completed', 'Hoist Done', 'HOIST DONE']],
    ['pdcCompleteFitting', ['Fitting Complete', 'Fitting Completed', 'Fitting Done', 'Fitment Complete', 'BUILD DONE', 'Build Complete', 'Build Completed', 'Build Done']],
    ['pdcCompleteFabrication', ['Fabrication Complete', 'Fabrication Completed', 'Fabrication Done', 'Fab Complete', 'FAB DONE']],
    ['pdcCompleteElectrical', ['Electrical Complete', 'Electrical Completed', 'Electrical Done', 'ELECTRICAL DONE']],
    ['pdcCompleteTyre', ['Tyre Complete', 'Tyre Completed', 'Tyre Done', 'Tire Complete', 'TYRE DONE']],
    ['pdcCompletePitInspection', ['Pit Inspection Complete', 'Pit Inspection Completed', 'Pit Inspection Done', 'PI DONE']],
    ['pdcCompleteParts', ['Parts Complete', 'Parts Completed', 'Parts Done', 'PARTS DONE', 'Parts Issued', 'Parts Received']],
    ['pdcBlocked', ['Blocked', 'PDC Blocked', 'Problem Vehicle']],
  ];
  pairs.forEach(([key, columns]) => {
    const value = explicitImportBoolean(row, headerMap, columns);
    if (value !== undefined) updates[key] = value;
  });
  const location = explicitImportValue(row, headerMap, ['PDC Location', 'PDC Status', 'Manual Location']);
  if (location.present) updates.pdcLocation = normalizePdcLocation(location.value);
  const stage = explicitImportValue(row, headerMap, ['PMB Work Stream', 'PMB Bucket', 'Work Stream', 'Bucket', 'PMB Stage']);
  if (stage.present) updates.pmbStage = normalizePmbStage(stage.value);
  const blockReason = explicitImportValue(row, headerMap, ['Blocked Reason', 'Block Reason', 'Issue', 'Problem', 'Exception']);
  if (blockReason.present) updates.pdcBlockReason = blockReason.value;
  return updates;
}

function navisionTruthyWorkValue(value = '') {
  const text = cleanNavisionText(value);
  if (!text) return false;
  const bool = pdcBooleanFromText(text);
  if (bool !== undefined) return bool;
  return !/^(0|none|no|n|false|na|n\/a|not required)$/i.test(text);
}

function navisionHasExplicitPmbWorkSignal(row, headerMap) {
  const updates = buildExplicitPdcUpdatesFromImport(row, headerMap);
  if (normalizePdcLocation(updates.pdcLocation || '') === 'PMB' || normalizePdcLocation(updates.pdcLocation || '') === 'RFT') return true;
  if (normalizePmbStage(updates.pmbStage || '')) return true;
  const requireKeys = PDC_JOB_DEFS.map(def => def.requireKey);
  return requireKeys.some(key => updates[key] === true);
}

function navisionHasPmbWorkSignal(row, headerMap, vehicle = {}) {
  if (navisionHasExplicitPmbWorkSignal(row, headerMap)) return true;
  if (navisionTruthyWorkValue(getNavisionValue(row, headerMap, ['Body Builder', 'Bodybuilder', 'Body Builder Code']))) return true;
  if (vehicle.trayOrdered === true) return true;

  const locationText = [
    vehicle.navisionLocationStatus,
    vehicle.navisionSubLocationDescription,
    vehicle.toyotaStatus,
  ].map(normalizeToyotaStatus).join(' ');
  if (/\bpmb\b/.test(locationText) || /\brft\b/.test(locationText) || locationText.includes('perth motor bodies') || locationText.includes('body builder')) return true;

  const workText = [
    vehicle.navisionDealerComments,
    vehicle.navisionVehicleNote,
    getNavisionValue(row, headerMap, 'Instructions'),
  ].map(cleanNavisionText).join(' ').toLowerCase();
  return /\b(pmb|perth motor bodies|body builder|purchase order|\bpo\b|tint|tray|electrical|fabrication|sublet|accessory|fitment)\b/i.test(workText);
}

function navisionImportOptionsFromDom() {
  return { pmbOnly: Boolean($('#navision-pmb-only')?.checked) };
}

function pmbWorkSkipMessage(vehicle = {}, excelRow) {
  const identity = displayStockNumber(vehicle) || vehicle.order || `row ${excelRow}`;
  return `Row ${excelRow}${identity ? ` / ${identity}` : ''}: skipped because PMB-only import is on and no PMB work / PO signal was found.`;
}

function protectPmbFirstLandingFromImport(payload = {}, existing = {}) {
  const incomingLocation = normalizePdcLocation(payload.pdcLocation || '');
  const existingLocation = vehiclePdcLocation(existing);
  if (incomingLocation !== 'PMB' || existingLocation === 'PMB') return payload;

  // Import sheets may identify a vehicle as PMB, but the control-board rule is
  // that the first PMB entry lands in Unallocated. Required jobs and PMB Bucket
  // columns must not silently allocate Tint/Hoist/Fitting/Fabrication/Electrical/Tyre/Pit Inspection.
  payload.pmbStage = '';
  payload.pdcWorkStage = '';
  payload.workStage = '';
  payload.pmbStageEnteredAt = '';
  payload.pmbStageUpdatedAt = '';
  payload.pmbBayStage = '';
  payload.pmbBayNumber = '';
  payload.pmbBayEstimatedHours = '';
  payload.pmbBayEnteredAt = '';
  payload.pmbBayScheduledStartAt = '';
  payload.pmbBayCompletedAt = '';
  payload.pmbBayCompletedBy = '';
  payload.pmbBayCompletedStage = '';
  payload.pmbBayMechanic = '';
  payload.pmbSubletProvider = '';
  return payload;
}

function applyExplicitPdcImportFields(payload, incoming = {}, existing = {}) {
  const keys = [
    ...PDC_JOB_DEFS.flatMap(def => [def.requireKey, def.completeKey]),
    'pdcBlocked','pdcBlockReason','pdcLocation','pmbStage'
  ];
  let hasAny = false;
  keys.forEach(key => {
    if (Object.prototype.hasOwnProperty.call(incoming, key)) {
      payload[key] = incoming[key];
      hasAny = true;
    }
  });
  if (!hasAny) return payload;
  protectPmbFirstLandingFromImport(payload, existing);
  const now = nowIsoString();
  if (payload.pdcLocation && normalizePdcLocation(payload.pdcLocation) !== vehiclePdcLocation(existing)) {
    payload.pdcLocationUpdatedAt = now;
    if (normalizePdcLocation(payload.pdcLocation) === 'PMB') {
      payload.pmbEnteredAt = pmbEnteredTimestamp(existing) || now;
      payload.pmbTransferredAt = existing.pmbTransferredAt || now;
    }
  }
  if (Object.prototype.hasOwnProperty.call(payload, 'pmbStage') && normalizePmbStage(payload.pmbStage) !== normalizePmbStage(existing.pmbStage || '')) {
    payload.pmbStageUpdatedAt = now;
    payload.pmbStageEnteredAt = now;
  }
  PDC_JOB_DEFS.forEach(def => {
    if (payload[def.completeKey] === true && !existing[def.completeKey]) {
      payload[def.completeAtKey] = now;
      payload[def.completeByKey] = existing[def.completeByKey] || 'Spreadsheet import';
    }
  });
  return payload;
}

function navisionPrimaryEta(row, headerMap) {
  // Dashboard ETA must come only from the Kewdale ETA field.
  // If Kewdale ETA is blank, leave ETA blank.
  return scotEtaOnly(getNavisionValue(row, headerMap, ['ETA At Kewdale Yard', 'ETA to Kewdale', 'ETA To Kewdale']) || '');
}

function buildNavisionVehicle(row, headerMap, excelRow) {
  const order = getNavisionValue(row, headerMap, ['Order', 'Toyota Order', 'Toyota Order Number', 'Order Number']);
  const batch = getNavisionValue(row, headerMap, ['Batch', 'Stock', 'Stock Number', 'SN', 'Stock No']);
  const stock = isBlankStock(batch) ? '' : batch;
  const mainId = stock || order;
  const modelDescription = getNavisionValue(row, headerMap, ['Model Description', 'Vehicle', 'Model']);
  const suffixDescription = getNavisionValue(row, headerMap, ['Suffix Description', 'Suffix', 'Variant']);
  const trimDescription = getNavisionValue(row, headerMap, ['Trim Description', 'Trim']);
  const colourDescription = getNavisionValue(row, headerMap, ['Colour Description', 'Color Description', 'Colour', 'Color']);
  const customerSurname = getNavisionValue(row, headerMap, ['Customer Surname', 'Customer', 'Client']);
  const dealerCustomerName = getNavisionValue(row, headerMap, ['Dealer Customer Name', 'Customer Name', 'Client Name']);
  const customer = customerSurname || dealerCustomerName || '(Dealer Order)';
  const dealerComments = getNavisionValue(row, headerMap, 'Dealer Comments');
  const vehicleNote = getNavisionValue(row, headerMap, 'Vehicle Note');
  const instructions = getNavisionValue(row, headerMap, 'Instructions');
  const comments = [dealerComments, vehicleNote, instructions].filter(Boolean).join(' ');
  const wmi = getNavisionValue(row, headerMap, 'WMI').replace(/\s+/g, '');
  const vdsNumber = getNavisionValue(row, headerMap, 'VDS Number').replace(/\s+/g, '');
  const frame = getNavisionValue(row, headerMap, 'Frame').replace(/\s+/g, '');
  const vin = `${wmi}${vdsNumber}${frame}`;
  const trayOrdered = /^yes$/i.test(getNavisionValue(row, headerMap, 'Tray Fitment Ordered')) || /tray/i.test(comments);
  const trayComplete = /^yes$/i.test(getNavisionValue(row, headerMap, 'Tray Fitment Complete'));
  const cutButVehicleSource = navisionCutButVehicleText(row, headerMap);
  const rawStatus = navisionToyotaStatus(row, headerMap);
  const navisionEtaAtDealerBB = getNavisionValue(row, headerMap, 'ETA At Dealer/BB');
  const navisionPortPlantEta = getNavisionValue(row, headerMap, 'Port/Plant ETA Date');
  const navisionKewdaleEta = getNavisionValue(row, headerMap, ['ETA At Kewdale Yard', 'ETA to Kewdale', 'ETA To Kewdale']);
  const navisionEtaDate = getNavisionValue(row, headerMap, 'ETA Date');
  const keyNumber = getNavisionValue(row, headerMap, ['Key Number', 'Key No', 'Key No.', 'Key #', 'Key', 'Key Tag']);
  const navisionEta = scotEtaOnly(navisionKewdaleEta);
  return {
    id: `navision-${mainId || excelRow}`,
    sourceRow: excelRow,
    stock,
    batch: batch || stock,
    order,
    keyNumber,
    client: customer,
    toyotaCustomer: dealerCustomerName || customer,
    contact: '',
    internalStatus: 'Allocate vehicle, generate orders',
    deliveryDate: navisionExpectedDelivery(row, headerMap),
    vehicle: [modelDescription, suffixDescription].filter(Boolean).join(' '),
    toyotaVehicle: modelDescription,
    suffix: suffixDescription,
    trim: trimDescription,
    colour: colourDescription,
    financeNote: dealerComments,
    group: 'Navision import',
    owner: navisionConsultant(getNavisionValue(row, headerMap, ['Salesperson', 'Sales Person', 'SP', 'Consultant'])),
    consultant: navisionConsultant(getNavisionValue(row, headerMap, ['Salesperson', 'Sales Person', 'SP', 'Consultant'])),
    source: 'Navision',
    origMth: '',
    prodMth: formatNavisionProductionMonth(getNavisionValue(row, headerMap, ['Production Month', 'Prod Mth', 'P/Month'])),
    compPlate: getNavisionValue(row, headerMap, 'Compliance Date'),
    arrivalPort: getNavisionValue(row, headerMap, 'Arrival Port Name'),
    toyotaStatus: rawStatus,
    etaAtDealer: navisionEta,
    navisionEtaAtDealerBB,
    navisionPortPlantEta,
    navisionKewdaleEta,
    navisionEtaDate,
    navisionTransportLoadNo: getNavisionValue(row, headerMap, 'Transport Load No.'),
    navisionTransportPriority: getNavisionValue(row, headerMap, 'Transport Priority'),
    navisionLocationStatus: getNavisionValue(row, headerMap, 'Location Status'),
    navisionSubLocationDescription: getNavisionValue(row, headerMap, 'Sub Location Description'),
    navisionBuildStatus: getNavisionValue(row, headerMap, 'Build Status'),
    navisionRavStatus: getNavisionValue(row, headerMap, 'RAV Status'),
    navisionDealerComments: dealerComments,
    navisionVehicleNote: vehicleNote,
    epodReceipt: getNavisionValue(row, headerMap, 'EPOD Date'),
    jitQty: '',
    jitaPartsOrdered: navisionJita(row, headerMap),
    wmi,
    vdsNumber,
    frame,
    vin,
    engine: getNavisionValue(row, headerMap, 'Engine'),
    dealerCustomer: getNavisionValue(row, headerMap, 'Dealer Customer'),
    dealerCustomerCategory: getNavisionValue(row, headerMap, 'Dealer Customer Category'),
    salesType: getNavisionValue(row, headerMap, 'Sales Type'),
    listPrice: getNavisionValue(row, headerMap, 'List Price'),
    suburb: getNavisionValue(row, headerMap, 'Suburb'),
    pma: getNavisionValue(row, headerMap, 'PMA'),
    trayOrdered,
    trayFitmentComplete: trayComplete,
    navisionCutButVehicle: Boolean(cutButVehicleSource),
    navisionCutButVehicleSource: cutButVehicleSource,
    ...protectPmbFirstLandingFromImport(buildExplicitPdcUpdatesFromImport(row, headerMap), {}),
    importedAt: new Date().toISOString(),
  };
}

function prepareNavisionText(text = '') {
  let value = String(text || '').trim();
  const looksLikeQuotedCsvOrTsv = /^"[^"\r\n]*"[\t,;]/.test(value);
  const wrappedInStraightQuotes = value.startsWith('"') && value.endsWith('"') && !looksLikeQuotedCsvOrTsv;
  const wrappedInSmartQuotes = value.startsWith('“') && value.endsWith('”');
  if (wrappedInStraightQuotes || wrappedInSmartQuotes) {
    value = value.slice(1, -1);
  }
  return value;
}

function isPostYardHoldNavisionVehicle(vehicle = {}) {
  // Only the actual Navision location fields decide whether a row is past Yard Hold.
  // Notes/comments/build status can mention PMB, body builder or transport work before the
  // vehicle has physically reached Yard Hold, so they must not block the upload.
  const locationStatus = normalizeToyotaStatus(vehicle.navisionLocationStatus || '');
  const subLocation = normalizeToyotaStatus(vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || '');
  const text = `${locationStatus} ${subLocation}`.trim();

  if (!text) return false;
  if (locationStatus === 'yh' || subLocation.includes('yard hold') || /\byh\b/.test(text)) return false;

  return (
    locationStatus === 'pmb' ||
    locationStatus === 'rft' ||
    /\bpmb\b/.test(text) ||
    /\brft\b/.test(text) ||
    text.includes('perth motor bodies') ||
    text.includes('body builder') ||
    text.includes('ready for transport') ||
    text.includes('ready for transfer') ||
    text.includes('out on consignment') ||
    text.includes('at dealer') ||
    text.includes('delivered to dealer') ||
    text.includes('delivered - at dealer') ||
    text.includes('dealer received')
  );
}

function postYardHoldReason(vehicle = {}) {
  return cleanNavisionText(vehicle.navisionLocationStatus || vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || 'past Yard Hold');
}

function parseNavisionInput(text, options = {}) {
  const prepared = prepareNavisionText(text);
  const detected = detectDelimitedRows(prepared);
  const rows = detected.rows;
  if (!rows.length) return { vehicles: [], warnings: ['Paste the Navision export with the header row first.'], missing: [], delimiter: detected.delimiter, options };
  const headers = rows[0].map(header => cleanNavisionText(header).replace(/^\uFEFF/, ''));
  const headerMap = buildNavisionHeaderMap(headers);
  const hasIdentityColumn = ['Batch', 'Stock', 'Stock Number', 'SN', 'Stock No'].some(column => hasNavisionColumn(headerMap, column));
  const hasVehicleColumn = ['Model Description', 'Vehicle', 'Model'].some(column => hasNavisionColumn(headerMap, column));
  const missing = [];
  if (!hasIdentityColumn) missing.push('Batch/Stock');
  if (!hasVehicleColumn) missing.push('Model Description / Vehicle');
  if (missing.length) {
    return {
      vehicles: [],
      warnings: [`Missing required columns: ${missing.join(', ')}. This tracker now only imports rows that have a real Batch / Stock number.`],
      missing,
      delimiter: detected.delimiter,
      options,
    };
  }

  const importOptions = { pmbOnly: false, ...options };
  const warnings = [];
  if (!hasNavisionColumn(headerMap, 'Sub Location Description')) {
    warnings.push('Sub Location Description column was not found, so Toyota Status will be blank for this import.');
  }
  if (importOptions.pmbOnly) {
    warnings.push('PMB-only import is on: rows without Body Builder, PMB/PDC Location, PMB Bucket, tray ordered, or explicit PMB job columns are skipped.');
  }
  const vehicles = [];
  rows.slice(1).forEach((row, index) => {
    const excelRow = index + 2;
    const vehicle = buildNavisionVehicle(row, headerMap, excelRow);
    if (!vehicle.stock) {
      warnings.push(`Row ${excelRow}${vehicle.order ? ` / Order ${vehicle.order}` : ''}: skipped because Batch / Stock number is blank. This tracker only imports vehicles with batch numbers.`);
      return;
    }
    if (importOptions.pmbOnly && !navisionHasPmbWorkSignal(row, headerMap, vehicle)) {
      warnings.push(pmbWorkSkipMessage(vehicle, excelRow));
      return;
    }
    if (!vehicle.vehicle && !vehicle.toyotaVehicle) {
      warnings.push(`Row ${excelRow}${vehicle.order ? ` / Order ${vehicle.order}` : ''}: vehicle description is blank.`);
    }
    vehicles.push(vehicle);
  });
  return { vehicles, warnings, missing: [], delimiter: detected.delimiter, options: importOptions };
}

function navisionMatchKeys(vehicle = {}) {
  vehicle = vehicle || {};
  return [
    vehicle.stock,
    vehicle.batch,
    vehicle.order,
    vehicle.vin,
    vehicle.frame,
    vehicle.id,
  ].map(value => String(value || '').trim()).filter(Boolean);
}

function navisionComparableKeys(vehicle = {}) {
  const v = vehicle || {};
  const keys = new Set();
  const addKey = (value, { stockLike = false } = {}) => {
    const raw = String(value || '').trim();
    if (!raw) return;
    if (stockLike && isBlankStock(raw)) return;
    const clean = normalizeBatch(raw);
    if (!clean || clean === '0' || /^TBA$/i.test(clean)) return;
    keys.add(clean);
  };
  addKey(v.stock, { stockLike: true });
  addKey(v.batch, { stockLike: true });
  addKey(v.toyotaBatch, { stockLike: true });
  addKey(v.autocareBatch, { stockLike: true });
  addKey(v.order);
  addKey(v.frame);
  addKey(v.frameNo);
  addKey(v.autocareFrame);
  [v.vin, v.fullVin, v.frameVin, v.autocareVin, [v.wmi, v.vdsNumber, v.frame].filter(Boolean).join('')]
    .map(normalizeVin)
    .filter(Boolean)
    .forEach(vin => keys.add(vin));
  return [...keys];
}

function navisionVehiclesOverlap(a = {}, b = {}) {
  const keys = new Set(navisionComparableKeys(a));
  if (!keys.size) return false;
  return navisionComparableKeys(b).some(key => keys.has(key));
}

function isProtectedPdcVehicle(vehicle = {}) {
  const manualPdcLocation = vehiclePdcLocation(vehicle);
  if (manualPdcLocation === 'YH' || manualPdcLocation === 'PMB' || manualPdcLocation === 'RFT') return true;
  return statusCategory(vehicle) === 'yardhold';
}

function vehiclesMissingFromNavisionImport(existingRows = [], incomingRows = []) {
  const candidates = existingRows.filter(vehicle => !isProtectedPdcVehicle(vehicle));
  if (!candidates.length) return [];
  if (!incomingRows.length) return candidates.slice();
  return candidates.filter(vehicle => !incomingRows.some(incoming => navisionVehiclesOverlap(incoming, vehicle)));
}

function findAddedVehicleIndex(added, incoming, existing) {
  const keys = new Set(navisionMatchKeys(incoming).concat(navisionMatchKeys(existing)));
  return added.findIndex(vehicle => navisionMatchKeys(vehicle).some(key => keys.has(key)));
}

function findVehicleForNavision(incoming) {
  const stock = normalizeBatch(incoming.stock || incoming.batch);
  const order = normalizeBatch(incoming.order);
  const vin = normalizeVin(incoming.vin);
  const frame = normalizeBatch(incoming.frame);
  return app.data.find(vehicle => {
    const toyota = getToyotaMatch(vehicle) || {};
    const candidates = [vehicle.stock, vehicle.batch, vehicle.toyotaBatch, vehicle.order, toyota.batch, toyota.order, vehicle.autocareBatch, vehicle.id]
      .map(normalizeBatch)
      .filter(Boolean);
    const vins = [vehicle.vin, vehicle.frameVin, vehicle.fullVin, vehicle.autocareVin]
      .map(normalizeVin)
      .filter(Boolean);
    const frames = [vehicle.frame, vehicle.frameNo, vehicle.autocareFrame]
      .map(normalizeBatch)
      .filter(Boolean);
    return (stock && candidates.includes(stock)) ||
      (order && candidates.includes(order)) ||
      (vin && vins.includes(vin)) ||
      (frame && frames.includes(frame));
  }) || null;
}

function mergeNavisionSource(existingSource = '') {
  const source = String(existingSource || '').trim();
  if (!source) return 'Navision';
  if (/navision/i.test(source)) return source;
  return `${source} + Navision`;
}

function navisionEditPayload(incoming, existing = {}) {
  // For existing CRM rows, protect manual edits and preparation fields.
  // Navision refreshes only identifiers needed for matching plus Tray, Dealer Comments, JITA and location/status fields.
  const payload = {
    source: mergeNavisionSource(existing.source || incoming.source),
    importedAt: incoming.importedAt,
    sourceRow: incoming.sourceRow,

    // Navision source fields that should keep refreshing on existing rows.
    prodMth: incoming.prodMth || existing.prodMth || '',
    compPlate: incoming.compPlate || existing.compPlate || '',
    etaAtDealer: incoming.etaAtDealer || '',
    navisionEtaAtDealerBB: incoming.navisionEtaAtDealerBB || '',
    navisionKewdaleEta: incoming.navisionKewdaleEta || '',
    navisionEtaDate: incoming.navisionEtaDate || '',
    navisionPortPlantEta: incoming.navisionPortPlantEta || '',

    // Core identifiers are allowed so order-only vehicles can receive a real stock/batch number later.
    id: existing.id || incoming.id,
    stock: incoming.stock || existing.stock || '',
    batch: incoming.batch || incoming.stock || existing.batch || existing.stock || '',
    order: incoming.order || existing.order || '',
    wmi: incoming.wmi || existing.wmi || '',
    vdsNumber: incoming.vdsNumber || existing.vdsNumber || '',
    frame: incoming.frame || existing.frame || '',
    vin: incoming.vin || existing.vin || '',

    // Allowed Navision refresh fields.
    trayOrdered: incoming.trayOrdered,
    trayFitmentComplete: incoming.trayFitmentComplete,
    jitaPartsOrdered: incoming.jitaPartsOrdered,
    jitQty: incoming.jitQty || '',
    toyotaStatus: incoming.toyotaStatus || '',
    navisionSubLocationDescription: incoming.navisionSubLocationDescription || '',
    navisionLocationStatus: incoming.navisionLocationStatus || '',
    navisionTransportLoadNo: incoming.navisionTransportLoadNo || '',
    navisionTransportPriority: incoming.navisionTransportPriority || '',
    navisionBuildStatus: incoming.navisionBuildStatus || '',
    navisionRavStatus: incoming.navisionRavStatus || '',
    arrivalPort: incoming.arrivalPort || existing.arrivalPort || '',
    navisionDealerComments: incoming.navisionDealerComments || '',
    financeNote: incoming.financeNote || '',
    navisionVehicleNote: incoming.navisionVehicleNote || '',
    navisionCutButVehicle: Boolean(incoming.navisionCutButVehicle),
    navisionCutButVehicleSource: incoming.navisionCutButVehicleSource || '',
  };
  return applyExplicitPdcImportFields(payload, incoming, existing);
}

function navisionComparableValue(value) {
  if (value === true || value === false) return value ? 'Yes' : 'No';
  return cleanNavisionText(value || '');
}

function navisionFieldChanges(existing = {}, payload = {}) {
  const fields = [
    ['stock', 'Stock / Batch'],
    ['batch', 'Batch'],
    ['order', 'Toyota Order'],
    ['prodMth', 'P/Month'],
    ['etaAtDealer', 'ETA'],
    ['toyotaStatus', 'Toyota Status'],
    ['jitaPartsOrdered', 'JITA'],
    ['trayOrdered', 'Tray Fitment Ordered'],
    ['trayFitmentComplete', 'Tray Fitment Complete'],
    ['navisionDealerComments', 'Navision Notes'],
    ['navisionVehicleNote', 'Vehicle Note'],
    ['navisionSubLocationDescription', 'Sub Location Description'],
    ['navisionLocationStatus', 'Location Status'],
    ['navisionTransportLoadNo', 'Transport Load No.'],
    ['navisionBuildStatus', 'Build Status'],
    ['navisionRavStatus', 'RAV Status'],
    ['pdcLocation', 'PDC Location'],
    ['pmbStage', 'PMB Work Stream'],
    ['pdcBlocked', 'Blocked'],
    ['pdcBlockReason', 'Blocked Reason'],
    ...PDC_JOB_DEFS.flatMap(def => [
      [def.requireKey, `Requires ${def.label}`],
      [def.completeKey, `${def.label} Complete`],
    ]),
    ['vin', 'VIN'],
    ['frame', 'Frame'],
  ];
  return fields.flatMap(([key, label]) => {
    const before = navisionComparableValue(key === 'etaAtDealer' ? scotEtaOnly(existing[key]) : existing[key]);
    const after = navisionComparableValue(key === 'etaAtDealer' ? scotEtaOnly(payload[key]) : payload[key]);
    if (before === after) return [];
    if (!before && !after) return [];
    return [{ key, label, before, after }];
  });
}

function buildNavisionImportPlan(parsed) {
  const deleted = new Set(loadDeletedVehicles());
  const activeBeforeImport = app.data.slice();
  const removeMissingChecked = Boolean($('#navision-remove-missing')?.checked);
  const result = {
    parsed,
    added: [],
    updated: [],
    unchanged: [],
    stockNumberUpdates: [],
    restored: [],
    skipped: parsed.warnings.slice(),
    missingFromUpload: [],
    removedMissing: [],
    removeMissingChecked,
    importedAt: new Date().toISOString(),
    fileName: app.navisionFileName || 'Pasted text',
    requiresConfirmation: false,
    confirmed: false,
  };

  parsed.vehicles.forEach(incoming => {
    const existing = findVehicleForNavision(incoming);
    const keys = navisionMatchKeys(incoming).concat(navisionMatchKeys(existing));
    keys.forEach(key => {
      if (deleted.has(key)) result.restored.push(incoming);
    });

    if (existing) {
      const incomingHasStock = incoming.stock && !isBlankStock(incoming.stock);
      const existingHadNoStock = isBlankStock(existing.stock);
      const stockChanged = incomingHasStock && existingHadNoStock;
      const payload = navisionEditPayload(incoming, existing);
      const changes = navisionFieldChanges(existing, payload);
      const row = { incoming, existing: { ...existing }, stockChanged, payload, changes, key: vehicleKey(existing) || vehicleKey(incoming) };
      if (stockChanged) result.stockNumberUpdates.push(row);
      if (changes.length || stockChanged) result.updated.push(row);
      else result.unchanged.push(row);
    } else {
      result.added.push(incoming);
    }
  });

  result.missingFromUpload = vehiclesMissingFromNavisionImport(activeBeforeImport, parsed.vehicles);
  result.requiresConfirmation = Boolean(result.updated.length || result.stockNumberUpdates.length);
  return result;
}

function importNavisionVehicles() {
  const input = $('#navision-paste');
  const text = input?.value || '';
  const parsed = parseNavisionInput(text, navisionImportOptionsFromDom());
  if (!parsed.vehicles.length) {
    app.pendingNavisionImport = null;
    renderNavisionSummary({ parsed, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], skipped: parsed.warnings });
    return;
  }

  const result = buildNavisionImportPlan(parsed);
  if (result.requiresConfirmation) {
    app.pendingNavisionImport = result;
    renderNavisionPendingReview(result);
    updateNavisionControlStats(result);
    updateNavisionImportButton();
    return;
  }

  applyNavisionImportPlan(result);
}

function selectedPendingNavisionUpdateKeys(result) {
  const checked = $$('[data-navision-apply-update]')
    .filter(input => input.checked)
    .map(input => input.dataset.navisionApplyUpdate)
    .filter(Boolean);
  if (!checked.length) return new Set();
  return new Set(checked);
}

function applyPendingNavisionImport(mode = 'all') {
  const pending = app.pendingNavisionImport;
  if (!pending) return;
  const selectedKeys = mode === 'selected' ? selectedPendingNavisionUpdateKeys(pending) : null;
  if (mode === 'selected' && (!selectedKeys || !selectedKeys.size)) {
    window.alert('Select at least one existing vehicle update, or use Apply all Navision updates.');
    return;
  }
  applyNavisionImportPlan(pending, selectedKeys);
}

function cancelPendingNavisionImport() {
  app.pendingNavisionImport = null;
  renderNavisionSummary({ parsed: { vehicles: [], warnings: [] }, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], skipped: ['Navision import cancelled. No tracker data was changed.'] });
  updateNavisionImportButton();
}

function applyNavisionImportPlan(plan, selectedUpdateKeys = null) {
  const parsed = plan.parsed;
  const added = loadAddedVehicles();
  const edits = loadVehicleEdits();
  const deleted = new Set(loadDeletedVehicles());
  const activeBeforeImport = app.data.slice();
  const removeMissingChecked = Boolean(plan.removeMissingChecked);
  const result = { ...plan, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], missingFromUpload: [], removedMissing: [], confirmed: true, appliedAt: new Date().toISOString() };

  parsed.vehicles.forEach(incoming => {
    const existing = findVehicleForNavision(incoming);
    const keys = navisionMatchKeys(incoming).concat(navisionMatchKeys(existing));
    keys.forEach(key => {
      if (deleted.delete(key)) result.restored.push(incoming);
    });

    if (existing) {
      const existingKey = vehicleKey(existing) || vehicleKey(incoming);
      const incomingHasStock = incoming.stock && !isBlankStock(incoming.stock);
      const existingHadNoStock = isBlankStock(existing.stock);
      const stockChanged = incomingHasStock && existingHadNoStock;
      const payload = navisionEditPayload(incoming, existing);
      const changes = navisionFieldChanges(existing, payload);
      const row = { incoming, existing: { ...existing }, stockChanged, payload, changes, key: existingKey };

      if (selectedUpdateKeys && !selectedUpdateKeys.has(existingKey)) {
        result.unchanged.push({ ...row, skippedByUser: true });
        return;
      }

      if (stockChanged) result.stockNumberUpdates.push(row);
      const addedIndex = findAddedVehicleIndex(added, incoming, existing);
      if (addedIndex >= 0) {
        added[addedIndex] = { ...added[addedIndex], ...payload, id: added[addedIndex].id || payload.id };
      }
      const editKeys = new Set(keys.concat([vehicleKey(existing), vehicleKey(incoming)]).filter(Boolean));
      editKeys.forEach(key => { edits[key] = { ...(edits[key] || {}), ...payload }; });
      if (changes.length || stockChanged) result.updated.push(row);
      else result.unchanged.push(row);
    } else {
      added.unshift(incoming);
      result.added.push(incoming);
    }
  });

  const missingFromUpload = vehiclesMissingFromNavisionImport(activeBeforeImport, parsed.vehicles);
  result.missingFromUpload = missingFromUpload;

  saveAddedVehicles(added);
  saveJson(EDITS_KEY, edits);
  saveDeletedVehicles([...deleted]);

  if (removeMissingChecked && missingFromUpload.length) {
    result.removedMissing = removeVehiclesFromTracker(missingFromUpload);
    result.missingFromUpload = [];
  }

  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.columnFilters = { sales: '', production: '', status: '', jita: '' };
  const searchInput = $('#search');
  if (searchInput) searchInput.value = '';
  app.data = buildVehicleData();
  app.selectedRows.clear();
  app.pendingNavisionImport = null;
  populateFilters();
  renderAll();
  app.navisionImport = result;
  saveJson(NAVISION_IMPORT_RESULTS_KEY, result);
  updateNavisionSidebarMeta();
  renderNavisionSummary(result);
  updateNavisionControlStats(result);
  updateNavisionImportButton();
}


function renderNavisionChangeRows(rows = []) {
  if (!rows.length) return `<div class="summary-row"><strong>None</strong><span>No existing vehicles need Navision changes applied.</span></div>`;
  return rows.slice(0, 80).map((row, index) => {
    const key = row.key || vehicleKey(row.existing) || vehicleKey(row.incoming) || `update-${index}`;
    const changes = (row.changes || []).slice(0, 8).map(change => `
      <tr>
        <td>${escapeHtml(change.label)}</td>
        <td>${escapeHtml(change.before || 'Blank')}</td>
        <td>${escapeHtml(change.after || 'Blank')}</td>
      </tr>`).join('');
    return `<div class="summary-row navision-review-row">
      <label class="navision-review-select">
        <input type="checkbox" data-navision-apply-update="${escapeHtml(key)}" checked />
        <span>${vehicleIdentityStackHtml(row.incoming || row.existing)}${navisionVehicleSummary(row.incoming)}</span>
      </label>
      <table class="navision-change-table">
        <thead><tr><th>Field</th><th>Current CRM</th><th>New Navision</th></tr></thead>
        <tbody>${changes || '<tr><td>Stock / Batch</td><td>Order-only vehicle</td><td>New stock number received</td></tr>'}</tbody>
      </table>
    </div>`;
  }).join('') + (rows.length > 80 ? `<div class="subtle">Showing first 80 of ${rows.length} existing vehicle update${rows.length === 1 ? '' : 's'}.</div>` : '');
}

function renderNavisionPendingReview(result) {
  const host = $('#navision-status-list');
  if (!host) return;
  const warnings = (result?.skipped || result?.parsed?.warnings || []).filter(Boolean);
  const warningList = warnings.length
    ? `<div class="summary-section"><h3>Warnings / skipped rows</h3>${warnings.slice(0, 8).map(warning => `<div class="summary-row error"><strong>Review</strong><span>${escapeHtml(warning)}</span></div>`).join('')}</div>`
    : '';

  host.innerHTML = `
    <div class="navision-confirm-banner">
      <div>
        <strong>Review Navision changes before applying</strong>
        <span>Nothing has been written to the tracker yet. Manual team notes and PO uploads are protected. Spreadsheet columns named ${PDC_IMPORT_CONTROL_COLUMNS_TEXT}, PMB Bucket, PDC Location or Blocked can deliberately update those PDC controls.</span>
      </div>
      <div class="navision-confirm-actions">
        <button class="primary" id="navision-apply-all" type="button">Apply all Navision updates</button>
        <button class="small-button" id="navision-apply-selected" type="button">Apply selected updates only</button>
        <button class="small-button danger-button" id="navision-cancel-import" type="button">Cancel import</button>
      </div>
    </div>
    <div class="scot-summary-grid">
      <div class="summary-stat"><span>Rows detected</span><strong>${result.parsed.vehicles.length}</strong></div>
      <div class="summary-stat"><span>New vehicles pending</span><strong>${result.added.length}</strong></div>
      <div class="summary-stat"><span>Existing changes</span><strong>${result.updated.length}</strong></div>
      <div class="summary-stat"><span>Unchanged existing</span><strong>${result.unchanged.length}</strong></div>
      <div class="summary-stat"><span>Not in upload</span><strong>${result.missingFromUpload.length}</strong></div>
      <div class="summary-stat"><span>Warnings</span><strong>${warnings.length}</strong></div>
    </div>
    <div class="summary-section">
      <div class="summary-section-heading"><h3>Existing vehicle changes needing confirmation</h3><label class="small-toggle"><input id="navision-toggle-all-updates" type="checkbox" checked /> Select all</label></div>
      ${renderNavisionChangeRows(result.updated || [])}
    </div>
    <div class="summary-section">
      <h3>New vehicles that will be added after confirmation</h3>
      ${renderNavisionRows(result.added || [], 'navision-new', 'No new vehicles will be added.')}
    </div>
    <div class="summary-section">
      <h3>Vehicles not found in this Navision upload</h3>
      ${renderNavisionRows(result.missingFromUpload || [], 'navision-missing', 'Every current dashboard vehicle was found in this upload.')}
      <div class="subtle">These are not removed until you apply the import. If the cleanup checkbox is ticked, they will be removed after confirmation.</div>
    </div>
    ${warningList}
    <div class="subtle">Navision can update stock/order/VIN, P/Month, Toyota Status, ETA, JITA, Tray, Dealer Comments/Navision Notes and related location fields. Excel update sheets can also update explicit PDC control columns such as TINT, HOIST, FITTING, FABRICATION, ELECTRICAL, TYRE, PIT INSPECTION, PARTS, PMB Bucket, PDC Location and Blocked.</div>
  `;
  on($('#navision-apply-all'), 'click', () => applyPendingNavisionImport('all'));
  on($('#navision-apply-selected'), 'click', () => applyPendingNavisionImport('selected'));
  on($('#navision-cancel-import'), 'click', cancelPendingNavisionImport);
  $('#navision-toggle-all-updates')?.addEventListener('change', event => {
    $$('[data-navision-apply-update]', host).forEach(input => { input.checked = event.currentTarget.checked; });
  });
}

function navisionVehicleSummary(vehicle) {
  return `${vehicleIdentityTitle(vehicle) || (vehicle.order ? `Order ${escapeHtml(vehicle.order)}` : '')} · ${escapeHtml(displayVehicle(vehicle) || vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}`;
}

function renderNavisionRows(rows, cssClass, emptyText) {
  if (!rows.length) return `<div class="summary-row"><strong>None</strong><span>${escapeHtml(emptyText)}</span></div>`;
  return rows.slice(0, 12).map(row => {
    const vehicle = row.incoming || row;
    return `<div class="summary-row ${cssClass}">${vehicleIdentityStackHtml(vehicle)}<span>${navisionVehicleSummary(vehicle)}${vehicle.toyotaStatus ? ` · ${escapeHtml(vehicle.toyotaStatus)}` : ''}</span></div>`;
  }).join('') + (rows.length > 12 ? `<div class="subtle">Showing first 12 of ${rows.length}.</div>` : '');
}

function renderNavisionSummary(result) {
  const host = $('#navision-status-list');
  if (!host) return;
  const parsed = result?.parsed || { vehicles: [], warnings: [] };
  const warnings = (result?.skipped || parsed.warnings || []).filter(Boolean);
  const stockUpdates = result?.stockNumberUpdates || [];
  const missingFromUpload = result?.missingFromUpload || [];
  const removedMissing = result?.removedMissing || [];
  const warningList = warnings.length
    ? `<div class="summary-section"><h3>Warnings / skipped rows</h3>${warnings.slice(0, 12).map(warning => `<div class="summary-row error"><strong>Review</strong><span>${escapeHtml(warning)}</span></div>`).join('')}${warnings.length > 12 ? `<div class="subtle">Showing first 12 of ${warnings.length} warnings.</div>` : ''}</div>`
    : '';
  const stockUpdateList = stockUpdates.length
    ? `<div class="summary-section"><h3>Vehicles receiving a new stock number</h3>${stockUpdates.slice(0, 12).map(row => `<div class="summary-row important"><strong>${escapeHtml(row.incoming.stock)}</strong><span>Matched by Toyota order ${escapeHtml(row.incoming.order || row.existing.order || '')} · ${escapeHtml(row.incoming.client || row.existing.client || '')}</span></div>`).join('')}${stockUpdates.length > 12 ? `<div class="subtle">Showing first 12 of ${stockUpdates.length}.</div>` : ''}</div>`
    : '';
  const missingList = missingFromUpload.length
    ? `<div class="summary-section"><div class="summary-section-heading"><h3>Vehicles not found in this Navision upload</h3><button class="small-button danger-button" id="navision-remove-missing-now" type="button">Remove these from dashboard</button></div>${renderNavisionRows(missingFromUpload, 'navision-missing', 'Every current dashboard vehicle was found in this upload.')}</div>`
    : `<div class="summary-section"><h3>Vehicles not found in this Navision upload</h3><div class="summary-row"><strong>None</strong><span>Every current dashboard vehicle was found in this upload.</span></div></div>`;
  const removedList = removedMissing.length
    ? `<div class="summary-section"><h3>Removed because they were not in this upload</h3>${renderNavisionRows(removedMissing, 'navision-removed', 'No vehicles were removed during this import.')}</div>`
    : '';

  host.innerHTML = `
    <div class="scot-summary-grid">
      <div class="summary-stat"><span>Rows detected</span><strong>${parsed.vehicles.length}</strong></div>
      <div class="summary-stat"><span>New vehicles</span><strong>${result?.added?.length || 0}</strong></div>
      <div class="summary-stat"><span>Updated</span><strong>${result?.updated?.length || 0}</strong></div>
      <div class="summary-stat"><span>New stock #</span><strong>${stockUpdates.length}</strong></div>
      <div class="summary-stat"><span>Not in upload</span><strong>${missingFromUpload.length}</strong></div>
      <div class="summary-stat"><span>Removed</span><strong>${removedMissing.length}</strong></div>
      <div class="summary-stat"><span>Restored</span><strong>${result?.restored?.length || 0}</strong></div>
      <div class="summary-stat"><span>Warnings</span><strong>${warnings.length}</strong></div>
    </div>
    <div class="summary-section">
      <h3>New vehicles added from Navision</h3>
      ${renderNavisionRows(result?.added || [], 'navision-new', 'No new vehicles were added.')}
    </div>
    <div class="summary-section">
      <h3>Existing vehicles updated</h3>
      ${renderNavisionRows(result?.updated || [], 'navision-updated', 'No existing vehicles were updated.')}
    </div>
    ${stockUpdateList}
    ${missingList}
    ${removedList}
    ${warningList}
    <div class="subtle">Toyota Status is taken only from Navision Sub Location Description. Existing rows keep manual CRM fields; Navision refreshes Tray, Dealer Comments/Navision Notes, JITA, Navision ETA, Production Month and location/status fields. Rows marked as Cut But Vehicle are highlighted light blue.</div>
  `;
  on($('#navision-remove-missing-now'), 'click', removeMissingFromLastNavisionImport);
}

function removeMissingFromLastNavisionImport() {
  const result = app.navisionImport || loadJson(NAVISION_IMPORT_RESULTS_KEY, null);
  const missing = result?.missingFromUpload || [];
  if (!missing.length) return;
  const preview = missing.slice(0, 10).map(vehicle => `• ${vehicleIdentityTitle(vehicle) || 'No stock'} - ${vehicleCustomerName(vehicle) || 'Unknown customer'}`).join('\n');
  const more = missing.length > 10 ? `\n• plus ${missing.length - 10} more` : '';
  if (!window.confirm(`Remove ${missing.length} vehicle${missing.length === 1 ? '' : 's'} that were not found in the latest Navision upload?\n\n${preview}${more}`)) return;
  const removed = removeVehiclesFromTracker(missing);
  app.navisionImport = {
    ...result,
    removedMissing: (result.removedMissing || []).concat(removed),
    missingFromUpload: [],
  };
  saveJson(NAVISION_IMPORT_RESULTS_KEY, app.navisionImport);
  refreshAfterVehicleRemoval();
  renderNavisionSummary(app.navisionImport);
  updateNavisionControlStats(app.navisionImport);
  updateNavisionImportButton();
}

function handlePdfSelect(e) {
  const file = e.target.files[0];
  if (!file) return;
  $('#scan-report').disabled = false;
  $('#scan-card .scan-line:nth-child(1) strong').textContent = file.name.includes('SCOT') ? 'Toyota Navision report detected' : 'PDF selected';
  $('#scan-card .scan-line:nth-child(2) strong').textContent = `${app.report.totalSalesOrders || app.data.length} rows in sample parser`; 
  $('#scan-card .scan-line:nth-child(3) strong').textContent = `${Object.keys(app.matches).length} matched to current tracker`;
  $('#progress-bar').style.width = '14%';
  renderScotSummary(false);
}


function scanReport() {
  let width = 14;
  $('#scan-report').disabled = true;
  const timer = setInterval(() => {
    width += 18;
    $('#progress-bar').style.width = `${Math.min(width, 100)}%`;
    if (width >= 100) {
      clearInterval(timer);
      app.reviewed = true;
      renderReviewTable(true);
      renderScotSummary(true);
      $('#approve-all').disabled = false;
    }
  }, 220);
}

function buildReviewRows() {
  return app.data
    .map(v => ({ vehicle: v, match: getToyotaMatch(v) }))
    .filter(row => row.match)
    .map(({ vehicle: v, match: m }) => {
      const changed = [];
      if ((canonicalToyotaStatus(v.toyotaStatus) || '') !== (canonicalToyotaStatus(m.toyotaStatus) || '')) changed.push(['Toyota Status', canonicalToyotaStatus(v.toyotaStatus) || 'Blank', canonicalToyotaStatus(m.toyotaStatus) || 'Blank']);
      if (scotEtaOnly(v.etaAtDealer) !== scotEtaOnly(m.etaAtDealer)) changed.push(['ETA At Dealer', scotEtaOnly(v.etaAtDealer) || 'Blank', scotEtaOnly(m.etaAtDealer) || 'Blank']);
      if ((v.contact || '') !== (m.contact || '')) changed.push(['Contact', v.contact || 'Blank', m.contact || 'Blank']);
      if ((v.order || '') !== (m.order || '')) changed.push(['Toyota Order #', v.order || 'Blank', m.order || 'Blank']);
      const temp = { ...v, ...m, toyotaStatus: m.toyotaStatus };
      const ok = isCustomerMatch(temp);
      return { vehicle: v, match: m, changed, ok };
    });
}

function renderReviewTable(scanned = false) {
  const table = $('#review-table');
  if (!table) return;
  if (!scanned) {
    table.innerHTML = `<tbody><tr><td><div class="empty-state"><strong>Upload and scan the Toyota PDF</strong><span>The proposed update list will appear here.</span></div></td></tr></tbody>`;
    return;
  }
  const rows = buildReviewRows();
  table.innerHTML = `
    <thead><tr><th>Stock #</th><th>Current tracker</th><th>Toyota PDF</th><th>Proposed changes</th><th>Review</th></tr></thead>
    <tbody>${rows.map(r => `
      <tr>
        <td>${vehicleIdentityStackHtml(r.vehicle, { button: true })}${stockOrderSubline(r.vehicle)}</td>
        <td><div class="review-block"><strong>${escapeHtml(vehicleCustomerName(r.vehicle) || 'Customer TBA')}</strong><span class="subtle">${escapeHtml(displayVehicle(r.vehicle))}</span>${scotEtaOnly(r.vehicle.etaAtDealer) ? `<span class="subtle">ETA ${escapeHtml(scotEtaOnly(r.vehicle.etaAtDealer))}</span>` : ''}</div></td>
        <td><div class="review-block"><strong>${escapeHtml(r.match.toyotaCustomer || '')}</strong><span class="subtle">Order ${escapeHtml(r.match.order || '')}</span><span class="subtle">${escapeHtml(displayVehicle(r.match))}</span><span>${formatStatus(r.match)}</span></div></td>
        <td>${r.changed.map(([field, oldVal, newVal]) => `<div><strong>${escapeHtml(field)}</strong><div class="subtle">${escapeHtml(oldVal)} -> ${escapeHtml(newVal)}</div></div>`).join('') || '<span class="subtle">No changes</span>'}</td>
        <td>${r.ok ? '<span class="review-ok">Clean match</span>' : '<span class="review-warning">Needs manual review</span>'}</td>
      </tr>`).join('')}</tbody>
  `;
  $$('[data-open-stock]', table).forEach(btn => btn.addEventListener('click', () => openVehicleModal(btn.dataset.openStock)));
}

function approveCleanMatches() {
  const rows = buildReviewRows().filter(r => r.ok);
  const edits = loadVehicleEdits();
  rows.forEach(({ vehicle, match }) => {
    Object.assign(vehicle, match);
    const key = vehicleKey(vehicle);
    edits[key] = {
      ...(edits[key] || {}),
      order: match.order || vehicle.order || '',
      toyotaStatus: isAutocareDespatched(vehicle) ? AUTOCARE_DESPATCH_STATUS : (match.toyotaStatus || ''),
      contact: match.contact || vehicle.contact || '',
    };
  });
  saveJson(EDITS_KEY, edits);
  app.data = buildVehicleData();
  app.reviewed = false;
  $('#approve-all').disabled = true;
  renderAll();
  showView('dashboard');
}


function clearDashboard() {
  const count = app.data.length;
  const message = count
    ? `Clear the dashboard and remove ${count} vehicle${count === 1 ? '' : 's'} from this browser?\n\nThis gives you a clean Navision-only starting point before the next upload.`
    : 'Dashboard is already clear. Reset saved import state anyway?';
  if (!window.confirm(message)) return;
  [EDITS_KEY, ADDED_KEY, PO_TASKS_KEY, PO_FILES_KEY, DELETED_KEY, AUTOCARE_RESULTS_KEY, NAVISION_IMPORT_RESULTS_KEY].forEach(key => localStorage.removeItem(key));
  for (let index = localStorage.length - 1; index >= 0; index -= 1) {
    const key = localStorage.key(index);
    if (key && key.startsWith('vehicleTrackingCoreNotes:')) localStorage.removeItem(key);
  }
  app.selectedRows.clear();
  app.autocareFiles = [];
  app.autocareScan = null;
  app.navisionImport = null;
  app.navisionFileName = '';
  const navisionPaste = $('#navision-paste');
  const navisionUpload = $('#navision-upload');
  const autocarePaste = $('#autocare-paste');
  const autocareUpload = $('#autocare-upload');
  if (navisionPaste) navisionPaste.value = '';
  if (navisionUpload) navisionUpload.value = '';
  if (autocarePaste) autocarePaste.value = '';
  if (autocareUpload) autocareUpload.value = '';
  app.data = buildVehicleData();
  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.sort = { key: '', dir: 'asc' };
  populateFilters();
  renderAll();
}


function crmManagedStorageKeys() {
  const keys = new Set(CRM_BACKUP_STORAGE_KEYS);
  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index);
    if (!key) continue;
    if (key.startsWith('vehicleTrackingCoreNotes:') || key.startsWith('vehicleTrackingCoreColumnWidths:') || key === VEHICLE_TABLE_COLUMN_ORDER_KEY) keys.add(key);
    if (key.startsWith('vehicleTrackingCoreNavisionOnly')) keys.add(key);
  }
  return [...keys];
}

function crmDefaultStorageValues() {
  return {
    [EDITS_KEY]: '{}',
    [ADDED_KEY]: '[]',
    [PO_TASKS_KEY]: '{}',
    [PO_FILES_KEY]: '{}',
    [DELETED_KEY]: '[]',
    [AUTOCARE_RESULTS_KEY]: 'null',
    [NAVISION_IMPORT_RESULTS_KEY]: 'null',
  };
}

function crmStorageSnapshot() {
  const storage = { ...crmDefaultStorageValues() };
  crmManagedStorageKeys().forEach(key => {
    const value = localStorage.getItem(key);
    if (value !== null) storage[key] = value;
  });
  return storage;
}

function crmBackupStats(backup) {
  const storage = backup?.storage || {};
  let noteCount = 0;
  Object.entries(storage).forEach(([key, value]) => {
    if (!key.startsWith('vehicleTrackingCoreNotes:')) return;
    try {
      const notes = JSON.parse(value || '[]');
      if (Array.isArray(notes)) noteCount += notes.length;
    } catch {}
  });
  return {
    vehicles: Array.isArray(backup?.vehicles) ? backup.vehicles.length : app.data.length,
    addedVehicles: loadJsonFromString(storage[ADDED_KEY], []).length,
    editRows: Object.keys(loadJsonFromString(storage[EDITS_KEY], {})).length,
    deletedVehicles: loadJsonFromString(storage[DELETED_KEY], []).length,
    poRows: Object.keys(loadJsonFromString(storage[PO_TASKS_KEY], {})).length + Object.keys(loadJsonFromString(storage[PO_FILES_KEY], {})).length,
    notes: noteCount,
    storageKeys: Object.keys(storage).length,
  };
}

function loadJsonFromString(value, fallback) {
  if (typeof value !== 'string') return fallback;
  try { return JSON.parse(value); }
  catch { return fallback; }
}

function buildCrmBackup() {
  const storage = crmStorageSnapshot();
  const backup = {
    type: CRM_BACKUP_TYPE,
    version: CRM_BACKUP_VERSION,
    appTitle: 'Vehicle Tracking Core',
    exportedAt: new Date().toISOString(),
    storage,
    vehicles: app.data,
    instructions: 'Restore this JSON from Uploads > CRM backup / restore. CSV exports are for reporting only and are not a complete backup.'
  };
  backup.summary = crmBackupStats(backup);
  return backup;
}

function safeBackupFileDate() {
  const d = new Date();
  const pad = value => String(value).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}`;
}

function exportCrmBackup() {
  const backup = buildCrmBackup();
  const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `vehicle-tracking-core-backup-${safeBackupFileDate()}.json`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
  renderBackupStatus({ type: 'exported', backup });
}

function handleCrmBackupFileSelect(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => restoreCrmBackup(String(reader.result || ''), file.name);
  reader.onerror = () => renderBackupStatus({ type: 'error', message: `Could not read ${file.name}.` });
  reader.readAsText(file);
}

function normalizeIncomingBackupKey(key) {
  if (key.startsWith('broomeToyotaVehicleCrmNavisionOnly')) {
    return key.replace('broomeToyotaVehicleCrmNavisionOnly', 'vehicleTrackingCoreNavisionOnly');
  }
  if (key.startsWith('notes:')) {
    return key.replace('notes:', 'vehicleTrackingCoreNotes:');
  }
  if (key.startsWith('columnWidths:v10:')) {
    return key.replace('columnWidths:v10:', 'vehicleTrackingCoreColumnWidths:v4:');
  }
  return key;
}

function backupStorageKeyAllowed(key) {
  const normalizedKey = normalizeIncomingBackupKey(key);
  return CRM_BACKUP_STORAGE_KEYS.includes(normalizedKey) ||
    normalizedKey.startsWith('vehicleTrackingCoreNotes:') ||
    normalizedKey.startsWith('vehicleTrackingCoreColumnWidths:') ||
    normalizedKey === VEHICLE_TABLE_COLUMN_ORDER_KEY ||
    normalizedKey.startsWith('vehicleTrackingCoreNavisionOnly');
}

function normalizedBackupStorage(backup) {
  const storage = backup?.storage && typeof backup.storage === 'object' ? { ...backup.storage } : {};
  if (!storage[ADDED_KEY] && Array.isArray(backup?.vehicles)) {
    storage[ADDED_KEY] = JSON.stringify(backup.vehicles);
  }
  return Object.fromEntries(Object.entries(storage)
    .filter(([key, value]) => backupStorageKeyAllowed(key) && typeof value === 'string')
    .map(([key, value]) => [normalizeIncomingBackupKey(key), value]));
}

function restoreCrmBackup(text, fileName = 'backup file') {
  let backup;
  try { backup = JSON.parse(text); }
  catch {
    renderBackupStatus({ type: 'error', message: 'That file is not valid JSON. Use a CRM backup JSON, not a CSV export.' });
    return;
  }

  const storage = normalizedBackupStorage(backup);
  const entries = Object.entries(storage);
  if (!entries.length) {
    renderBackupStatus({ type: 'error', message: 'No restorable CRM data was found in that file. CSV exports cannot restore the full tracker state.' });
    return;
  }

  const stats = crmBackupStats({ ...backup, storage });
  const confirmed = window.confirm(
    `Restore ${stats.vehicles} vehicle${stats.vehicles === 1 ? '' : 's'} from ${fileName}?\n\n` +
    'This replaces the saved tracker data in this browser with the backup contents.'
  );
  if (!confirmed) {
    renderBackupStatus({ type: 'cancelled', message: 'Backup restore cancelled.' });
    return;
  }

  crmManagedStorageKeys().forEach(key => localStorage.removeItem(key));
  entries.forEach(([key, value]) => localStorage.setItem(key, value));

  app.data = buildVehicleData();
  app.autocareFiles = [];
  app.autocareScan = loadJson(AUTOCARE_RESULTS_KEY, null);
  app.navisionImport = loadJson(NAVISION_IMPORT_RESULTS_KEY, null);
  app.navisionFileName = '';
  app.pendingNavisionImport = null;
  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.sort = { key: '', dir: 'asc' };
  app.selectedRows.clear();
  app.columnFilters = { sales: '', production: '', status: '', jita: '' };
  ['search', 'source-filter'].forEach(id => { const el = $('#' + id); if (el) el.value = ''; });
  populateFilters();
  renderAll();
  if (app.navisionImport) renderNavisionSummary(app.navisionImport);
  updateNavisionSidebarMeta();
  renderBackupStatus({ type: 'restored', backup: { ...backup, storage }, fileName });

  const upload = $('#backup-upload');
  if (upload) upload.value = '';
}

function renderBackupStatus({ type, backup = null, fileName = '', message = '' } = {}) {
  const host = $('#backup-status-list');
  if (!host) return;
  if (type === 'error') {
    host.innerHTML = `<div class="summary-row error"><strong>Backup error</strong><span>${escapeHtml(message || 'The backup could not be processed.')}</span></div>`;
    return;
  }
  if (type === 'cancelled') {
    host.innerHTML = `<div class="summary-row warn"><strong>Restore cancelled</strong><span>${escapeHtml(message || 'No tracker data was changed.')}</span></div>`;
    return;
  }
  const stats = crmBackupStats(backup || buildCrmBackup());
  const exportedAt = backup?.exportedAt ? new Date(backup.exportedAt) : new Date();
  const when = exportedAt && !Number.isNaN(exportedAt.getTime()) ? exportedAt.toLocaleString('en-AU') : 'Unknown time';
  const heading = type === 'restored' ? 'Backup restored' : 'Backup exported';
  const detail = type === 'restored'
    ? `${fileName ? escapeHtml(fileName) + ' · ' : ''}The dashboard has been reloaded from the backup.`
    : 'A JSON backup file has been downloaded. Keep it with your Navision export history.';
  host.innerHTML = `
    <div class="scot-summary-grid backup-summary-grid">
      <div class="summary-stat"><span>Vehicles</span><strong>${stats.vehicles}</strong></div>
      <div class="summary-stat"><span>Edited rows</span><strong>${stats.editRows}</strong></div>
      <div class="summary-stat"><span>Notes</span><strong>${stats.notes}</strong></div>
      <div class="summary-stat"><span>Saved keys</span><strong>${stats.storageKeys}</strong></div>
    </div>
    <div class="summary-section">
      <h3>${heading}</h3>
      <div class="summary-row ok"><strong>${type === 'restored' ? 'Ready' : 'Downloaded'}</strong><span>${detail}</span></div>
      <div class="summary-row"><strong>Backup time</strong><span>${escapeHtml(when)}</span></div>
    </div>
    <div class="subtle">Use <strong>Export CRM backup JSON</strong> when you need to restore the tracker after a website update.</div>
  `;
}

function teamNotesText(vehicle) {
  return getNotes(vehicleKey(vehicle)).join(' | ');
}

function exportCsv() {
  const jobHeaders = PDC_JOB_DEFS.flatMap(def => [`Requires ${def.label}`, `${def.label} Complete`]);
  const headers = ['SP','Stock','Toyota Order','Key Number','P/Month','Client','Vehicle','PDC Location','PMB Work Stream','PMB Bay','PMB Bay Hours','PMB Bay Scheduled Start','PMB Bay Started','PMB Bay Completed','PMB Requirements','PMB Completed','PMB Outstanding','Blocked','Blocked Reason','Bucket Days','Days Since Kewdale ETA','RFT Gate Issues','RFT Date','Navision Notes','Team Notes','Task', ...jobHeaders, 'PO Tasks','PO Files','Toyota Status (Sub Location)','Navision ETA','Delivery Date','JITA Parts Ordered','JITA Qty','Contact','Source','Autocare VIN','Autocare Batch','Autocare Load','Match Warning'];
  const lines = [headers.join(',')].concat(app.data.map(v => [
    salesPersonInitials(consultantName(v)), displayStockNumber(v), v.order || '', vehicleKeyNumber(v), productionMonthLabel(v.prodMth || v.productionMonth || ''), v.client, displayVehicle(v), pdcLocationLabel(v.pdcLocation), pmbStageLabel(inferredPmbStage(v)), pmbBayNumber(v, inferredPmbStage(v)) || '', pmbBayHours(v) === '' ? '' : pmbBayHours(v), v.pmbBayScheduledStartAt ? new Date(v.pmbBayScheduledStartAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', v.pmbBayEnteredAt ? new Date(v.pmbBayEnteredAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', v.pmbBayCompletedAt ? new Date(v.pmbBayCompletedAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', pmbRequirementText(v), pdcCompletedJobsText(v), pdcOutstandingJobsText(v), isPdcBlocked(v) ? 'Yes' : 'No', pdcBlockReason(v), pmbStageAgeDays(v) === null ? '' : pmbStageAgeDays(v), pmbAgeDays(v) === null ? '' : pmbAgeDays(v), vehicleRftGateIssues(v).join('; '), v.rftTransferredAt ? new Date(v.rftTransferredAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', navisionDealerNoteText(v), teamNotesText(v), v.internalStatus || '', ...PDC_JOB_DEFS.flatMap(def => [pdcJobRequired(v, def) ? 'Yes' : 'No', pdcJobComplete(v, def) ? 'Yes' : 'No']), (v.poTasks || []).join('; '), (v.poFiles || []).join('; '), v.toyotaStatus || '', scotEtaOnly(v.etaAtDealer), v.deliveryDate || '', jitaDisplay(v), v.jitQty || '', v.contact || '', v.source || '', v.autocareVin || '', v.autocareBatch || '', v.autocareLoadNumber || '', isCustomerMatch(v) ? '' : 'Customer mismatch'
  ].map(csvEscape).join(',')));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'vehicle-tracking-core-export.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function csvEscape(value) {
  value = String(value ?? '');
  return /[",\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}


const ZPL_REQUIRED_COLUMNS = [
  'Batch',
  'Customer Surname',
  'Dealer Customer Name',
  'Model Description',
  'Suffix Description',
  'Trim Description',
  'Colour Description',
  'WMI',
  'VDS Number',
  'Frame'
];

function cleanZplField(value) {
  return String(value ?? '')
    .replace(/[\^~]/g, '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseDelimitedLine(line, delimiter = '\t') {
  const cells = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < String(line || '').length; i += 1) {
    const ch = line[i];
    const next = line[i + 1];
    if (ch === '"') {
      if (quoted && next === '"') {
        cell += '"';
        i += 1;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (ch === delimiter && !quoted) {
      cells.push(cell);
      cell = '';
      continue;
    }
    cell += ch;
  }
  cells.push(cell);
  return cells;
}

function detectDelimitedRows(text) {
  const value = String(text || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines = value.split('\n').filter(line => line.trim().length > 0);
  if (!lines.length) return { rows: [], delimiter: '\t' };
  const header = lines[0];
  const counts = [
    ['\t', (header.match(/\t/g) || []).length],
    [',', (header.match(/,/g) || []).length],
    [';', (header.match(/;/g) || []).length],
  ];
  const [delimiter, count] = counts.sort((a, b) => b[1] - a[1])[0];
  const chosen = count > 0 ? delimiter : '\t';
  return { rows: lines.map(line => parseDelimitedLine(line, chosen)), delimiter: chosen };
}

function splitTsvRows(text) {
  return detectDelimitedRows(text).rows;
}

function getTsvValue(row, headerMap, column) {
  const index = headerMap.get(column);
  return index === undefined ? '' : row[index] || '';
}

function vehicleToZplBlock(vehicle) {
  return [
    '^XA',
    '^PW540',
    '^LL360',
    '^LH0,0',
    '^CI28',
    `^FO20,20^A0N,50,50^FB500,1,0,L,0^FD${vehicle.batch}^FS`,
    `^FO20,90^A0N,25,25^FB500,1,0,L,0^FD${vehicle.customer}^FS`,
    `^FO20,125^A0N,25,25^FB500,1,0,L,0^FD${vehicle.model}^FS`,
    `^FO20,160^A0N,25,25^FB500,1,0,L,0^FD${vehicle.specLine}^FS`,
    `^FO20,195^A0N,25,25^FB500,1,0,L,0^FD${vehicle.vin}^FS`,
    `^FO20,300^A0N,50,50^FB500,1,0,L,0^FD${vehicle.batch}^FS`,
    '^PQ2',
    '^XZ'
  ].join('\n');
}

function parseZplInput(text) {
  const rows = splitTsvRows(text);
  if (!rows.length) return { vehicles: [], warnings: ['Paste a tab-separated export with a header row first.'], missing: ZPL_REQUIRED_COLUMNS.slice() };
  const headers = rows[0].map(header => String(header || '').trim());
  const headerMap = new Map(headers.map((header, index) => [header, index]));
  const missing = ZPL_REQUIRED_COLUMNS.filter(column => !headerMap.has(column));
  if (missing.length) return { vehicles: [], warnings: [`Missing required columns: ${missing.join(', ')}`], missing };

  const warnings = [];
  const vehicles = rows.slice(1).map((row, rowIndex) => {
    const excelRow = rowIndex + 2;
    const batch = cleanZplField(getTsvValue(row, headerMap, 'Batch'));
    const customerSurname = cleanZplField(getTsvValue(row, headerMap, 'Customer Surname'));
    const dealerCustomer = cleanZplField(getTsvValue(row, headerMap, 'Dealer Customer Name'));
    const model = cleanZplField(getTsvValue(row, headerMap, 'Model Description'));
    const suffix = cleanZplField(getTsvValue(row, headerMap, 'Suffix Description'));
    const trim = cleanZplField(getTsvValue(row, headerMap, 'Trim Description'));
    const colour = cleanZplField(getTsvValue(row, headerMap, 'Colour Description'));
    const wmi = cleanZplField(getTsvValue(row, headerMap, 'WMI')).replace(/\s+/g, '');
    const vds = cleanZplField(getTsvValue(row, headerMap, 'VDS Number')).replace(/\s+/g, '');
    const frame = cleanZplField(getTsvValue(row, headerMap, 'Frame')).replace(/\s+/g, '');
    const vin = `${wmi}${vds}${frame}`;
    const customer = customerSurname || dealerCustomer || '(Dealer Order)';
    const specLine = [suffix, trim, colour].filter(Boolean).join(' ');
    if (!batch) {
      warnings.push(`Row ${excelRow}: Batch is blank.`);
    }
    const missingVinParts = [];
    if (!vds) missingVinParts.push('VDS Number');
    if (!frame) missingVinParts.push('Frame');
    if (missingVinParts.length || vin.length !== 17) {
      warnings.push(`Row ${excelRow}${batch ? ` / Batch ${batch}` : ''}: VIN is ${vin.length || 0} characters${missingVinParts.length ? `, missing ${missingVinParts.join(' and ')}` : ''}.`);
    }
    return { batch, customer, model, specLine, vin, row: excelRow };
  });
  return { vehicles, warnings, missing: [] };
}

function generateZplFromInput() {
  const input = $('#zpl-input')?.value || '';
  const output = $('#zpl-output');
  const copyButton = $('#zpl-copy');
  const printButton = $('#zpl-print');
  const parsed = parseZplInput(input);
  const zpl = parsed.vehicles.map(vehicleToZplBlock).join('\n\n');
  if (output) output.value = zpl;
  if (copyButton) copyButton.disabled = !zpl;
  if (printButton) printButton.disabled = !zpl;
  renderZplSummary(parsed, zpl);
}

function renderZplSummary(parsed, zpl) {
  const summary = $('#zpl-summary');
  if (!summary) return;
  const count = parsed.vehicles.length;
  const warningList = parsed.warnings.map(warning => `<li>${escapeHtml(warning)}</li>`).join('');
  summary.innerHTML = `
    <div class="zpl-summary-grid">
      <div class="summary-stat"><span>Vehicles processed</span><strong>${count}</strong></div>
      <div class="summary-stat"><span>Label copies</span><strong>${count * 2}</strong></div>
      <div class="summary-stat"><span>ZPL blocks</span><strong>${zpl ? count : 0}</strong></div>
    </div>
    ${parsed.warnings.length ? `<div class="zpl-warning"><strong>Review before printing</strong><ul>${warningList}</ul></div>` : '<div class="zpl-ok">Ready to print. No incomplete VINs detected.</div>'}
  `;
}

function copyZplOutput() {
  const output = $('#zpl-output');
  if (!output || !output.value) return;
  const setCopied = () => {
    const btn = $('#zpl-copy');
    if (!btn) return;
    const original = btn.textContent;
    btn.textContent = 'Copied';
    window.setTimeout(() => { btn.textContent = original; }, 1400);
  };
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(output.value).then(setCopied).catch(() => {
      output.focus();
      output.select();
      document.execCommand('copy');
      setCopied();
    });
  } else {
    output.focus();
    output.select();
    document.execCommand('copy');
    setCopied();
  }
}

function clearZplGenerator() {
  const input = $('#zpl-input');
  const output = $('#zpl-output');
  if (input) input.value = '';
  if (output) output.value = '';
  const copyButton = $('#zpl-copy');
  if (copyButton) copyButton.disabled = true;
  const printButton = $('#zpl-print');
  if (printButton) printButton.disabled = true;
  const summary = $('#zpl-summary');
  if (summary) summary.innerHTML = '<div class="empty-state compact-empty"><strong>Ready</strong><span>Paste rows and generate. Incomplete VINs will be flagged before printing.</span></div>';
}

function getNotes(stock) { return loadJson(`vehicleTrackingCoreNotes:${stock}`, []); }
function setNotes(stock, notes) { saveJson(`vehicleTrackingCoreNotes:${stock}`, notes); }

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => { try { init(); } catch (error) { showStartupError(error); } });
} else {
  try { init(); } catch (error) { showStartupError(error); }
}


on(window, 'error', event => {
  if (event?.error) showStartupError(event.error);
});
on(window, 'unhandledrejection', event => {
  showStartupError(event?.reason || new Error('Unhandled promise rejection'));
});
