const APP_VERSION = '2026.07.21.02-combined-staging-candidate';
// Production Supabase project ref. Used only to LABEL which environment
// the backup status panel is showing (staging vs production) -- this
// constant intentionally names only the production ref, never the
// staging ref, so this file can ship to production without the
// production-artifact secret/staging-reference scan failing.
const PRODUCTION_SUPABASE_PROJECT_REF = 'vjdtsswhroyguxyfjdkt';
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
// Stage 2A (independent-review remediation, localStorage-to-Supabase
// migration): mechanics/salespeople/sublet providers are now
// authoritative in Supabase (public.workshop_technicians/
// public.salespeople/public.sublet_providers via
// workshop-reference-data-service.js). These six key constants are
// DELIBERATELY KEPT (not deleted) purely so the Stage 2A browser-data
// importer (scripts/import_stage2a_reference_data.py) can still read
// whatever a given staff computer's old local roster contained during
// the one-time import/reconciliation step. No other code path reads
// from or writes to these keys anymore -- loadMechanics()/
// loadSalespersons()/loadSubletProviders() read exclusively from
// workshop-reference-data-service.js's Supabase-backed cache.
const MECHANICS_KEY = 'vehicleTrackingCorePdcMechanics:v1';
const MECHANICS_ROSTER_SEED_KEY = 'vehicleTrackingCorePdcMechanicsRosterSeed:v1';
const MECHANICS_ROSTER_SEED_VERSION = '2026-07-15-departments-138-139-v1';
const SUBLET_PROVIDERS_KEY = 'vehicleTrackingCorePdcSubletProviders:v1';
const SUBLET_PROVIDERS_SEED_KEY = 'vehicleTrackingCorePdcSubletProvidersSeed:v2';
const SUBLET_PROVIDERS_SEED_VERSION = '2026-07-13-v2';
const SALESPERSONS_KEY = 'vehicleTrackingCoreSalespersons:v1';
const SALESPERSONS_SEED_KEY = 'vehicleTrackingCoreSalespersonsSeed:v1';
const SALESPERSONS_SEED_VERSION = '2026-07-13-v1';
const OPERATIONAL_HEALTH_KEY = 'vehicleTrackingCoreOperationalHealth:v1';
const EMAIL_REVIEW_DECISIONS_KEY = 'vehicleTrackingCoreEmailReviewDecisions:v1';
const AI_FILE_ASSISTANT_REVIEWS_KEY = 'vehicleTrackingCoreAiFileAssistantReviews:v1';
const STORAGE_TRANSACTION_JOURNAL_KEY = 'vehicleTrackingCoreStorageTransaction:v1';
const VEHICLE_TABLE_COLUMN_ORDER_KEY = 'vehicleTrackingCoreColumnOrder:v4';
const WORKFLOW_WIDTH_MODE_KEY = 'vehicleTrackingCoreWorkflowWidthMode:v1';
const ROW_WIDTH_MODE_KEY = 'vehicleTrackingCoreRowWidthMode:v1';
const VEHICLE_TABLE_DEFAULT_COLUMN_IDS = ['sp', 'stock', 'prodMth', 'client', 'vehicle', 'bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'pitInspection', 'status', 'eta', 'navisionNotes', 'jita', 'action'];
const PO_TASKS_KEY = 'vehicleTrackingCoreNavisionOnlyPoTasks:v1';
const PO_FILES_KEY = 'vehicleTrackingCoreNavisionOnlyPoFiles:v1';
const ARB_LABOUR_CATALOG = window.ARB_LABOUR_CATALOG || { entries: {}, ambiguous: {}, labourRate: 160, sourceCode: 'DRT20260201.1' };
const DELETED_KEY = 'vehicleTrackingCoreNavisionOnlyDeleted:v1';
const TOYOTA_MATCHES = window.VEHICLE_TRACKING_DATA?.toyotaMatches || {};
const AUTOCARE_DESPATCH_STATUS = 'AUTOCARE DESPATCHED';
const AUTOCARE_RESULTS_KEY = 'vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1';
const NAVISION_IMPORT_RESULTS_KEY = 'vehicleTrackingCoreNavisionOnlyImport:v1';
const NAVISION_LOCAL_STORAGE_SAFE_BUDGET_BYTES = 4 * 1024 * 1024;
const NAVISION_IMPORT_SUMMARY_VERSION = 2;
const NAVISION_IMPORT_SUMMARY_MAX_CHARS = 16 * 1024;
const NAVISION_IMPORT_TOO_LARGE_MESSAGE = 'Import too large—nothing saved';
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
  // MECHANICS_KEY/MECHANICS_ROSTER_SEED_KEY, SUBLET_PROVIDERS_KEY/
  // SUBLET_PROVIDERS_SEED_KEY, and SALESPERSONS_KEY/SALESPERSONS_SEED_KEY
  // are intentionally NOT included here as of Stage 2A: mechanics,
  // sublet providers, and salespeople are now authoritative in Supabase
  // (public.workshop_technicians/public.sublet_providers/
  // public.salespeople via workshop-reference-data-service.js), covered
  // by the real Supabase encrypted backup/restore system, not this
  // browser-local export mechanism. The key constants and any existing
  // browser-local data under them are deliberately left untouched on
  // disk (not deleted, not read from, not written to) so the Stage 2A
  // browser-data importer can still read a given staff computer's old
  // local roster during the one-time import/reconciliation step -- see
  // scripts/import_stage2a_reference_data.py. They are never treated as
  // an authoritative source by any other code path.
  OPERATIONAL_HEALTH_KEY,
  EMAIL_REVIEW_DECISIONS_KEY,
  AI_FILE_ASSISTANT_REVIEWS_KEY,
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
  { value: 'BUS_4X4', label: 'Bus 4x4' },
  { value: 'TINT', label: 'Tint' },
  { value: 'HOIST', label: 'Hoist' },
  { value: 'FITTING', label: 'Fitting' },
  { value: 'FABRICATION', label: 'Fab' },
  { value: 'ELECTRICAL', label: 'Elec' },
  { value: 'TYRE', label: 'Tyre' },
  { value: 'PIT_INSPECTION', label: 'Pit' },
  { value: 'SUBLET', label: 'Sublet' },
];

const PMB_STAGE_DEFS = PMB_STAGE_OPTIONS.filter(option => option.value);
const PDC_JOB_LINE_STAGE_OPTIONS = PMB_STAGE_OPTIONS.filter(option => option.value && option.value !== 'SUBLET');
const PMB_STAGE_UNASSIGNED_FILTER = '__UNASSIGNED__';
const PMB_STAGE_LABELS = new Map(PMB_STAGE_OPTIONS.map(option => [option.value, option.label]));

const PMB_WIP_LIMITS = {
  '': 12,
  BUS_4X4: 1,
  TINT: 2,
  HOIST: 3,
  FITTING: 5,
  FABRICATION: 13,
  ELECTRICAL: 10,
  TYRE: 2,
  PIT_INSPECTION: 1,
  SUBLET: 12,
};

const PMB_STAGE_BAY_COUNTS = {
  BUS_4X4: 1,
  TINT: 2,
  HOIST: 3,
  FITTING: 5,
  FABRICATION: 13,
  ELECTRICAL: 10,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

const PMB_STAGE_CAPACITY_LABELS = {
  BUS_4X4: '1 bay',
  FABRICATION: '13 bays',
  TYRE: '2 bays · 1 wheel alignment bay',
  SUBLET: 'Provider queue',
};

const PMB_STAGE_AGE_LIMITS = {
  '': 1,
  BUS_4X4: 2,
  TINT: 2,
  HOIST: 2,
  FITTING: 3,
  FABRICATION: 4,
  ELECTRICAL: 2,
  TYRE: 2,
  PIT_INSPECTION: 1,
};

const PMB_BAY_MAX_COUNT = 13;
const PMB_BAY_STATION_SEQUENCE = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];
const PRODUCTION_FLOW_DEFS = [
  { key: 'BUS_4X4', label: 'Bus 4x4', short: 'B4', jobKey: 'bus4x4', stage: 'BUS_4X4', department: '138', search: /\b(bus\s*4x4|4x4 bus|department\s*138)\b/i },
  { key: 'TINT', label: 'Tint', short: 'T', jobKey: 'tint', stage: 'TINT', search: /\b(tint|tinting|window tint)\b/i },
  { key: 'HOIST', label: 'Hoist', short: 'H', jobKey: 'hoist', stage: 'HOIST', search: /\b(hoist|suspension|gvm|lift kit|lift|underbody|towbar|tow bar)\b/i },
  { key: 'FITTING', label: 'Fitting', short: 'F', jobKey: 'fitting', stage: 'FITTING', search: /\b(fit|fitting|build|pdi|pre delivery|pre-delivery|accessor(?:y|ies)|job card|workshop)\b/i },
  { key: 'FABRICATION', label: 'Fab', short: 'Fa', jobKey: 'fabrication', stage: 'FABRICATION', search: /\b(fab|fabricat|tray|canopy|body builder|bodybuilder|steel tray|aluminium tray|tub body|bullbar|bar work)\b/i },
  { key: 'ELECTRICAL', label: 'Elec', short: 'E', jobKey: 'electrical', stage: 'ELECTRICAL', search: /\b(electrical|auto electrical|auto-elec|12v|dual battery|battery system|uhf|spotlight|light bar|beacon|compressor|anderson|redarc|brake controller|dc dc|dcdc|dash cam|camera|reverse camera|power outlet|usb)\b/i },
  { key: 'TYRE', label: 'Tyre', short: 'Ty', jobKey: 'tyre', stage: 'TYRE', search: /\b(tyre|tire|wheel|wheels|alloy|rotation|balance|alignment)\b/i },
  { key: 'PIT_INSPECTION', label: 'Pit', short: 'PI', jobKey: 'pitInspection', stage: 'PIT_INSPECTION', search: /\b(pit inspection|pit|inspection)\b/i },
];
const PRODUCTION_DEPARTMENT_VIEWS = {
  'dept-bus-4x4': 'BUS_4X4',
  'dept-tint': 'TINT',
  'dept-hoist': 'HOIST',
  'dept-fitting': 'FITTING',
  'dept-fabrication': 'FABRICATION',
  'dept-electrical': 'ELECTRICAL',
  'dept-tyre': 'TYRE',
  'dept-pit-inspection': 'PIT_INSPECTION',
};

const PDC_JOB_DEFS = [
  { key: 'bus4x4', label: 'BUS 4X4', short: 'B4', requireKey: 'pdcRequiresBus4x4', completeKey: 'pdcCompleteBus4x4', completeAtKey: 'pdcCompleteBus4x4At', completeByKey: 'pdcCompleteBus4x4By' },
  { key: 'tint', label: 'TINT', short: 'T', requireKey: 'pdcRequiresTint', completeKey: 'pdcCompleteTint', completeAtKey: 'pdcCompleteTintAt', completeByKey: 'pdcCompleteTintBy' },
  { key: 'hoist', label: 'HOIST', short: 'H', requireKey: 'pdcRequiresHoist', completeKey: 'pdcCompleteHoist', completeAtKey: 'pdcCompleteHoistAt', completeByKey: 'pdcCompleteHoistBy' },
  { key: 'fitting', label: 'FITTING', short: 'F', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting', completeAtKey: 'pdcCompleteFittingAt', completeByKey: 'pdcCompleteFittingBy' },
  { key: 'fabrication', label: 'FAB', short: 'Fa', requireKey: 'pdcRequiresFabrication', completeKey: 'pdcCompleteFabrication', completeAtKey: 'pdcCompleteFabricationAt', completeByKey: 'pdcCompleteFabricationBy' },
  { key: 'electrical', label: 'ELEC', short: 'E', requireKey: 'pdcRequiresElectrical', completeKey: 'pdcCompleteElectrical', completeAtKey: 'pdcCompleteElectricalAt', completeByKey: 'pdcCompleteElectricalBy' },
  { key: 'tyre', label: 'TYRE', short: 'Ty', requireKey: 'pdcRequiresTyre', completeKey: 'pdcCompleteTyre', completeAtKey: 'pdcCompleteTyreAt', completeByKey: 'pdcCompleteTyreBy' },
  { key: 'sublet', label: 'SUBLET', short: 'S', requireKey: 'pdcRequiresSublet', completeKey: 'pdcCompleteSublet', completeAtKey: 'pdcCompleteSubletAt', completeByKey: 'pdcCompleteSubletBy' },
  { key: 'pitInspection', label: 'PIT', short: 'PI', requireKey: 'pdcRequiresPitInspection', completeKey: 'pdcCompletePitInspection', completeAtKey: 'pdcCompletePitInspectionAt', completeByKey: 'pdcCompletePitInspectionBy' },
  { key: 'parts', label: 'PARTS', short: 'P', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts', completeAtKey: 'pdcCompletePartsAt', completeByKey: 'pdcCompletePartsBy' },
];
function currentPdcJobLabelList() {
  return PDC_JOB_DEFS.map(def => def.label).join(', ');
}

function currentPdcJobColumnList() {
  return PDC_JOB_DEFS.map(def => def.label).join('/');
}

function pdcJobTriState(vehicle = {}, def = {}) {
  if (pdcJobComplete(vehicle, def)) return 'complete';
  if (pdcJobRequired(vehicle, def)) return 'required';
  return 'none';
}

function pdcJobTriStateControl(vehicle = {}, def = {}, locked = false) {
  const state = pdcJobTriState(vehicle, def);
  const stateLabel = state === 'complete' ? 'Completed' : state === 'required' ? 'To be completed' : 'Not required';
  const disabled = locked ? ' disabled' : '';
  return `<button class="pdc-work-state pdc-work-state-${escapeHtml(state)} pdc-toggle-${escapeHtml(def.key)}" type="button" data-pdc-work-state="${escapeHtml(def.key)}" data-state="${escapeHtml(state)}" aria-label="${escapeHtml(def.label)} - ${stateLabel}" title="${escapeHtml(def.label)} - ${stateLabel}. Click to cycle: grey not required, red to complete, green completed."${disabled}>
    <span class="pdc-work-state-code">${escapeHtml(def.short)}</span>
    <span class="pdc-work-state-label">${escapeHtml(def.label)}</span>
    <span class="pdc-work-state-status">${escapeHtml(stateLabel)}</span>
  </button>
  <input type="hidden" data-pdc-work-require="${escapeHtml(def.key)}" name="${escapeHtml(def.requireKey)}" value="${state === 'none' ? '0' : '1'}" />
  <input type="hidden" data-pdc-work-complete="${escapeHtml(def.key)}" name="${escapeHtml(def.completeKey)}" value="${state === 'complete' ? '1' : '0'}" />`;
}

const PDC_JOB_BY_REQUIRE_KEY = new Map(PDC_JOB_DEFS.map(def => [def.requireKey, def]));
const PDC_JOB_BY_COMPLETE_KEY = new Map(PDC_JOB_DEFS.map(def => [def.completeKey, def]));
const PDC_JOB_BY_KEY = new Map(PDC_JOB_DEFS.map(def => [def.key, def]));
const PDC_IMPORT_CONTROL_COLUMNS_TEXT = 'BUS 4X4, TINT, HOIST, FITTING, FABRICATION, ELECTRICAL, TYRE, SUBLET, PIT INSPECTION, PARTS';

function currentPdcJobLabelsText() {
  return PDC_JOB_DEFS.map(def => def.label).join(', ');
}

const PMB_STAGE_TO_JOB_KEY = {
  BUS_4X4: 'bus4x4',
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

function pmbStageForPdcJob(def = {}) {
  const match = PRODUCTION_FLOW_DEFS.find(item => item.jobKey === def?.key);
  return match ? normalizePmbStage(match.stage) : '';
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
  if (/\bBUS[ _-]*4X4\b|\b4X4[ _-]*BUS\b|\b(?:DEPT|DEPARTMENT)[ _-]*138\b/.test(clean)) return 'BUS_4X4';
  if (clean.includes('TINT')) return 'TINT';
  if ((clean.includes('EXPRESS') && clean.includes('HOIST')) || clean.includes('PITS HOIST') || clean.includes('PIT HOIST')) return 'HOIST';
  if (clean.includes('EXPRESS') && (clean.includes('FITOUT') || clean.includes('FIT OUT') || clean.includes('FITTING') || clean.includes('FITMENT'))) return 'FITTING';
  if (clean.includes('HOIST') || clean.includes('SUSPENSION') || clean.includes('LIFT')) return 'HOIST';
  if (clean.includes('FITTING') || clean.includes('FITMENT') || clean.includes('FITOUT') || clean.includes('FIT OUT') || clean.includes('BUILD') || clean.includes('PDI') || clean.includes('PRE DELIVERY') || clean.includes('PRE-DELIVERY')) return 'FITTING';
  if (clean.includes('FAB') || clean.includes('TRAY') || clean.includes('BODY')) return 'FABRICATION';
  if (clean.includes('ELECTRICAL') || clean.includes('AUTO ELEC') || clean.includes('AUTO-ELEC') || clean.includes('12V') || clean.includes('UHF')) return 'ELECTRICAL';
  if (clean.includes('TYRE') || clean.includes('TIRE') || clean.includes('WHEEL')) return 'TYRE';
  if (clean.includes('PIT') || clean.includes('INSPECTION')) return 'PIT_INSPECTION';
  if (clean.includes('SUBLET') || clean.includes('SUB-LET') || clean.includes('SUB LET') || clean.includes('OUTSOURCE') || clean.includes('EXTERNAL')) return 'SUBLET';
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
  return vehicle.pmbEnteredAt || vehicle.pmbTransferredAt || '';
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

const PDC_DEPARTMENT_LABELS = { '138': 'Bus 4x4', '137': 'Fab', '139': 'PD' };

function vehicleDepartmentCode(vehicle = {}) {
  const raw = cleanNavisionText(vehicle.pdcDepartmentCode || vehicle.departmentCode || vehicle.navisionDepartmentCode || vehicle.department || vehicle.dept || '');
  const match = raw.match(/\b(137|138|139)\b/);
  if (match) return match[1];
  const text = raw.toLowerCase();
  if (/bus\s*4x4|4x4\s*bus/.test(text)) return '138';
  if (/\bfab(?:rication)?\b/.test(text)) return '137';
  if (/\bpd\b|pre.?delivery/.test(text)) return '139';
  return '';
}

function vehicleDepartmentLabel(vehicle = {}) {
  const code = vehicleDepartmentCode(vehicle);
  return code ? `${code} ${PDC_DEPARTMENT_LABELS[code]}` : '';
}

function vehicleDepartmentBadge(vehicle = {}) {
  const label = vehicleDepartmentLabel(vehicle);
  return label ? `<span class="badge pdc-department-badge pdc-department-${escapeHtml(vehicleDepartmentCode(vehicle))}">${escapeHtml(label)}</span>` : '';
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
  if (days > 5) return 'watch';
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
  if (days > 30) return 'critical';
  if (days > 15) return 'warning';
  if (days > 7) return 'watch';
  if (days < 0) return 'future';
  return 'fresh';
}

function completedPmbStartDate(vehicle = {}) {
  return parseDateAU(kewdaleEtaValue(vehicle));
}

function completedRftDate(vehicle = {}) {
  return parseIsoTimestamp(vehicle.rftTransferredAt || vehicle.pdcLocationUpdatedAt || vehicle.rftCollectedAt || '');
}

function dateOnly(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  date.setHours(0, 0, 0, 0);
  return date;
}

function completedPmbDays(vehicle = {}) {
  const start = dateOnly(completedPmbStartDate(vehicle));
  const end = dateOnly(completedRftDate(vehicle));
  if (!start || !end) return null;
  return Math.max(0, Math.floor((end - start) / (1000 * 60 * 60 * 24)));
}

function completedPmbDaysLabel(vehicle = {}) {
  const days = completedPmbDays(vehicle);
  if (days === null) return 'Unknown';
  if (days === 0) return 'Same day';
  return `${days} day${days === 1 ? '' : 's'}`;
}

function completedPmbStatisticsFromDays(values = []) {
  const durations = (Array.isArray(values) ? values : [])
    .filter(value => Number.isFinite(value) && value >= 0)
    .sort((a, b) => a - b);
  const midpoint = Math.floor(durations.length / 2);
  const median = !durations.length
    ? null
    : (durations.length % 2 ? durations[midpoint] : (durations[midpoint - 1] + durations[midpoint]) / 2);
  return {
    known: durations.length,
    average: durations.length ? durations.reduce((total, value) => total + value, 0) / durations.length : null,
    median,
    fastest: durations.length ? durations[0] : null,
    longest: durations.length ? durations[durations.length - 1] : null,
  };
}

function completedPmbStatistics(vehicles = []) {
  const rows = Array.isArray(vehicles) ? vehicles : [];
  const stats = completedPmbStatisticsFromDays(rows.map(completedPmbDays));
  return { ...stats, total: rows.length, unknown: Math.max(0, rows.length - stats.known) };
}

function completedPmbStatisticDaysLabel(value) {
  if (!Number.isFinite(value)) return '—';
  const rounded = Math.round(value * 10) / 10;
  return `${rounded} day${rounded === 1 ? '' : 's'}`;
}

function renderCompletedPmbStatistics() {
  const host = $('#completed-pmb-statistics');
  if (!host) return;
  const stats = completedPmbStatistics(app.data.filter(vehicleCollectedFromRft));
  host.innerHTML = `<div class="completed-statistics-heading">
      <div><span>PMB turnaround statistics</span><strong>Collected vehicle history</strong></div>
      <small>${stats.known} of ${stats.total} vehicle${stats.total === 1 ? '' : 's'} have usable PMB and RFT dates${stats.unknown ? ` · ${stats.unknown} excluded as unknown` : ''}</small>
    </div>
    <div class="completed-statistics-grid">
      <article class="completed-stat-card is-primary"><span>Average time at PMB</span><strong>${escapeHtml(completedPmbStatisticDaysLabel(stats.average))}</strong><small>Mean across vehicles with known dates</small></article>
      <article class="completed-stat-card"><span>Median time</span><strong>${escapeHtml(completedPmbStatisticDaysLabel(stats.median))}</strong><small>Middle turnaround time</small></article>
      <article class="completed-stat-card"><span>Fastest</span><strong>${escapeHtml(completedPmbStatisticDaysLabel(stats.fastest))}</strong><small>Shortest recorded turnaround</small></article>
      <article class="completed-stat-card"><span>Longest</span><strong>${escapeHtml(completedPmbStatisticDaysLabel(stats.longest))}</strong><small>Longest recorded turnaround</small></article>
      <article class="completed-stat-card"><span>Collected vehicles</span><strong>${stats.total}</strong><small>${stats.known} included in PMB-time statistics</small></article>
    </div>`;
}

function shortDateAu(date) {
  if (!date) return '';
  return date.toLocaleDateString('en-AU', { day: '2-digit', month: '2-digit', year: 'numeric' });
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
  return vehicle.pdcBlocked === true
    || Boolean(cleanNavisionText(vehicle.pdcBlockReason || ''))
    || vehicle.pdcWorkshopBlocked === true
    || Boolean(cleanNavisionText(vehicle.pdcWorkshopBlockReason || ''));
}

function pdcBlockReason(vehicle = {}) {
  return cleanNavisionText(vehicle.pdcBlockReason || '')
    || cleanNavisionText(vehicle.pdcWorkshopBlockReason || '')
    || 'Blocked';
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
  if (partsEtaRisk(vehicle)) issues.push(`PARTS RISK: Parts ETA ${partsWorstEtaLabel(vehicle)} is later than Kewdale ETA ${kewdaleEtaValue(vehicle)}`);
  const outstanding = pdcRequirementDefinitions(vehicle).filter(job => !pdcJobComplete(vehicle, job)).map(job => job.label);
  if (outstanding.length) issues.push(`Outstanding jobs: ${outstanding.join(', ')}`);
  const alreadyTransferredToRft = vehiclePdcLocation(vehicle) === 'RFT' || statusCategory(vehicle) === 'rft' || vehicleCollectedFromRft(vehicle);
  if (!alreadyTransferredToRft && statusCategory(vehicle) === 'pmb') {
    const currentStage = normalizePmbStage(inferredPmbStage(vehicle));
    const currentBay = currentStage ? pmbBayNumber(vehicle, currentStage) : '';
    if (currentBay) issues.push(`Currently in ${pmbStageLabel(currentStage)} Bay ${currentBay}`);
    if (!outstanding.length && vehicle.pdcQcComplete !== true) issues.push('QC sign-off required');
  }
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

function navisionVehicleRequiresExplicitPdcWork(vehicle = {}) {
  const lifecycle = cleanNavisionText(vehicle.recordLifecycle || '').toLowerCase();
  const source = cleanNavisionText(vehicle.source || '').toLowerCase();
  return lifecycle === 'navision' || source === 'navision' || source === 'navision import';
}

function pdcStageMatchesJob(stage = '', def = {}) {
  const normalized = normalizePmbStage(stage);
  if (!normalized || !def?.key) return false;
  return ({
    bus4x4: 'BUS_4X4',
    tint: 'TINT',
    hoist: 'HOIST',
    fitting: 'FITTING',
    fabrication: 'FABRICATION',
    electrical: 'ELECTRICAL',
    tyre: 'TYRE',
    pitInspection: 'PIT_INSPECTION',
    sublet: 'SUBLET',
  })[def.key] === normalized;
}

function pdcJobFallbackRequired(vehicle = {}, def = {}) {
  const source = pdcJobSourceText(vehicle);
  const stage = normalizePmbStage(vehicle.pmbStage || vehicle.pdcWorkStage || vehicle.workStage || '');
  // Daily Navision and Back End Data rows must not create work ticks from free-text
  // comments, vehicle notes or location descriptions. Explicit spreadsheet booleans,
  // PO-derived flags and operator choices are handled before this fallback. A deliberate
  // PMB bay/stage assignment may still show its matching work item as required.
  if (navisionVehicleRequiresExplicitPdcWork(vehicle)) return pdcStageMatchesJob(stage, def);
  switch (def.key) {
    case 'bus4x4':
      return /\b(bus\s*4x4|4x4\s*bus|department\s*138)\b/.test(source) || stage === 'BUS_4X4' || vehicleDepartmentCode(vehicle) === '138';
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

function pdcJobDefsPartsFirst() {
  const rowOrder = ['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'pitInspection'];
  return rowOrder.map(key => PDC_JOB_BY_KEY.get(key)).filter(Boolean);
}


const PDC_GRID_JOB_LABELS = {
  parts: 'Parts',
  bus4x4: 'Bus 4x4',
  tint: 'Tint',
  hoist: 'Hoist',
  fitting: 'Fitting',
  fabrication: 'Fab',
  electrical: 'Elec',
  tyre: 'Tyre',
  sublet: 'Sublet',
  pitInspection: 'Pit',
};

function pdcGridJobLabel(def = {}) {
  return PDC_GRID_JOB_LABELS[def.key] || def.label || def.key || 'Station';
}

function pdcGridCompletedJobsText(vehicle = {}) {
  const jobs = pdcJobDefsPartsFirst().filter(def => pdcJobComplete(vehicle, def));
  return jobs.length ? jobs.map(pdcGridJobLabel).join(', ') : 'No station sign-offs';
}

function workflowHeaderOptionsHtml(options = [], current = '') {
  return options.map(option => `<option value="${escapeHtml(option.value)}"${option.value === current ? ' selected' : ''}>${escapeHtml(option.label)}</option>`).join('');
}

function workflowHeaderFilterHtml(label = '', filterType = '', options = [], current = '', className = '', dataAttributes = '') {
  const selected = options.find(option => option.value === current);
  const activeText = current ? (selected?.short || selected?.label || current) : '';
  const classes = ['workflow-column-filter', className, current ? 'is-active' : ''].filter(Boolean).join(' ');
  return `<label class="${escapeHtml(classes)}" title="${escapeHtml(`Filter or sort ${label}`)}">
    <span>${escapeHtml(label)}</span>
    ${activeText ? `<small>${escapeHtml(activeText)}</small>` : ''}
    <select data-workflow-header-filter="${escapeHtml(filterType)}" ${dataAttributes} aria-label="${escapeHtml(`Filter or sort ${label}`)}">${workflowHeaderOptionsHtml(options, current)}</select>
  </label>`;
}

function productionGridHeaderHtml(className = '', options = {}) {
  const meta1Label = options.meta1Label || 'Age / ETA';
  const meta2Label = options.meta2Label || 'Status';
  const actionLabel = options.actionLabel || 'Actions';
  const classes = ['pdc-production-grid-header', className || ''].filter(Boolean).join(' ');
  const workflowFilters = options.workflowFilters || null;
  if (workflowFilters) {
    const sortOptions = {
      key: [{ value: '', label: 'No key sort' }, { value: 'key-asc', label: 'Key low to high', short: '↑' }, { value: 'key-desc', label: 'Key high to low', short: '↓' }],
      stock: [{ value: '', label: 'No stock sort' }, { value: 'stock-asc', label: 'Stock A to Z', short: 'A–Z' }, { value: 'stock-desc', label: 'Stock Z to A', short: 'Z–A' }],
      jobcard: [{ value: '', label: 'No job card sort' }, { value: 'jobcard-asc', label: 'Job card A to Z', short: 'A–Z' }, { value: 'jobcard-desc', label: 'Job card Z to A', short: 'Z–A' }],
      customer: [{ value: '', label: 'No customer sort' }, { value: 'customer-asc', label: 'Customer A to Z', short: 'A–Z' }, { value: 'customer-desc', label: 'Customer Z to A', short: 'Z–A' }],
      vehicle: [{ value: '', label: 'No vehicle sort' }, { value: 'vehicle-asc', label: 'Vehicle A to Z', short: 'A–Z' }, { value: 'vehicle-desc', label: 'Vehicle Z to A', short: 'Z–A' }],
    };
    const sortValueFor = key => sortOptions[key].some(option => option.value === workflowFilters.sort) ? workflowFilters.sort : '';
    const workOptions = [
      { value: '', label: 'All vehicles' },
      { value: 'yes', label: 'Yes — required', short: 'Yes' },
      { value: 'no', label: 'No — not required', short: 'No' },
      { value: 'outstanding', label: 'Outstanding work', short: 'Open' },
      { value: 'complete', label: 'Completed work', short: 'Done' },
    ];
    const stationHeaders = pdcJobDefsPartsFirst().map(def => {
      let current = '';
      if (workflowFilters.work === def.key) {
        if (workflowFilters.required === 'yes') current = 'yes';
        else if (workflowFilters.required === 'no') current = 'no';
        else if (workflowFilters.completion === 'outstanding') current = 'outstanding';
        else if (workflowFilters.completion === 'complete') current = 'complete';
      }
      const stationOptions = def.key === 'parts' ? workOptions.filter(option => option.value !== 'no') : workOptions;
      return workflowHeaderFilterHtml(pdcGridJobLabel(def), 'work', stationOptions, current, `pdc-grid-station-heading pdc-grid-station-${def.key}`, `data-workflow-work-key="${escapeHtml(def.key)}"`);
    }).join('');
    const statusOptions = [
      { value: '', label: 'All PMB statuses' },
      { value: 'bucket:UNALLOCATED', label: 'Unallocated', short: 'Unalloc.' },
      ...PMB_STAGE_DEFS.map(def => ({ value: `bucket:${def.value}`, label: def.label, short: def.label })),
      { value: 'stoppage:yes', label: 'Stoppage only', short: 'Stopped' },
      { value: 'stoppage:no', label: 'No stoppage', short: 'Clear' },
    ];
    const statusValue = workflowFilters.bucket ? `bucket:${workflowFilters.bucket}` : workflowFilters.stoppage ? `stoppage:${workflowFilters.stoppage}` : '';
    const ageOptions = [
      { value: 'oldest', label: 'Oldest at PMB first', short: 'Oldest' },
      { value: 'newest', label: 'Newest at PMB first', short: 'Newest' },
    ];
    const hasColumnFilters = Boolean(workflowFilters.bucket || workflowFilters.work || workflowFilters.required || workflowFilters.completion || workflowFilters.stoppage || !['oldest', 'newest'].includes(workflowFilters.sort));
    return `<div class="${escapeHtml(classes)}">
      <span class="pdc-grid-control-heading" aria-hidden="true"></span>
      <span class="pdc-grid-select-heading" aria-hidden="true"></span>
      <span class="pdc-grid-identity-heading">
        ${workflowHeaderFilterHtml('Key', 'sort', sortOptions.key, sortValueFor('key'), 'workflow-identity-filter')}
        ${workflowHeaderFilterHtml('Stock', 'sort', sortOptions.stock, sortValueFor('stock'), 'workflow-identity-filter')}
        ${workflowHeaderFilterHtml('Job Card', 'sort', sortOptions.jobcard, sortValueFor('jobcard'), 'workflow-identity-filter')}
        ${workflowHeaderFilterHtml('Customer', 'sort', sortOptions.customer, sortValueFor('customer'), 'workflow-identity-filter')}
      </span>
      ${workflowHeaderFilterHtml('Vehicle', 'sort', sortOptions.vehicle, sortValueFor('vehicle'), 'pdc-grid-vehicle-heading')}
      <span class="pdc-grid-stations-heading">${stationHeaders}</span>
      ${workflowHeaderFilterHtml(meta1Label, 'sort', ageOptions, ['newest'].includes(workflowFilters.sort) ? 'newest' : 'oldest', 'pdc-grid-meta-heading workflow-age-filter')}
      ${workflowHeaderFilterHtml(meta2Label, 'status', statusOptions, statusValue, 'pdc-grid-status-heading')}
      <span class="pdc-grid-action-heading workflow-header-actions"><span>${escapeHtml(actionLabel)}</span>${hasColumnFilters ? '<button type="button" data-workflow-clear-column-filters>Clear</button>' : ''}</span>
    </div>`;
  }
  const stationHeaders = pdcJobDefsPartsFirst().map(def => {
    const label = pdcGridJobLabel(def);
    return `<span class="pdc-grid-station-heading pdc-grid-station-${escapeHtml(def.key)}" title="${escapeHtml(label)}"><span>${escapeHtml(label)}</span></span>`;
  }).join('');
  return `<div class="${escapeHtml(classes)}">
    <span class="pdc-grid-control-heading" aria-hidden="true"></span>
    <span class="pdc-grid-select-heading" aria-hidden="true"></span>
    <span class="pdc-grid-identity-heading">
      <span>Key</span><span>Stock</span><span>Job Card</span><span>Customer</span>
    </span>
    <span class="pdc-grid-vehicle-heading">Vehicle</span>
    <span class="pdc-grid-stations-heading">${stationHeaders}</span>
    <span class="pdc-grid-meta-heading">${escapeHtml(meta1Label)}</span>
    <span class="pdc-grid-status-heading">${escapeHtml(meta2Label)}</span>
    <span class="pdc-grid-action-heading">${escapeHtml(actionLabel)}</span>
  </div>`;
}

function incomingGridStatusLabel(vehicle = {}, bucketKey = '') {
  if (bucketKey === 'pmb') return pmbStageLabel(inferredPmbStage(vehicle)) || 'Unallocated';
  if (bucketKey === 'rft') return rftHomeStatusLabel(rftHomeStatus(vehicle));
  if (bucketKey === 'yardhold') return 'Yard Hold';
  if (bucketKey === 'transit') return 'In Transit';
  if (bucketKey === 'overseas') return navisionStatusText(vehicle) || 'Overseas / Other';
  return statusCategoryLabel(vehicle) || incomingBucketLabel(bucketKey) || navisionStatusText(vehicle) || 'Current';
}

function pdcJobMarkersHtml(vehicle = {}, interactive = false) {
  return `<div class="pmb-card-requirements" aria-label="PMB requirements">${pdcJobDefsPartsFirst().map(def => {
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
  const outstanding = pdcRequirementDefinitions(vehicle)
    .filter(job => !pdcJobComplete(vehicle, job))
    .sort((a, b) => (a.key === 'parts' ? -1 : b.key === 'parts' ? 1 : 0));
  const chips = outstanding.length
    ? outstanding.map(job => `<span class="pmb-outstanding-station" title="${escapeHtml(`${pdcGridJobLabel(job)} outstanding`)}">${escapeHtml(pdcGridJobLabel(job))}</span>`)
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

function pmbPillCustomerHtml(vehicle = {}) {
  const customer = vehicleCustomerName(vehicle) || 'Unknown customer';
  return `<span class="pmb-pill-customer" title="${escapeHtml(customer)}">${escapeHtml(customer)}</span>`;
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
    ['Delivered - At Body Builder', s => s.includes('body builder') && (s.includes('delivered') || s.startsWith('at ') || s === 'body builder')],
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

let activeRenderJsonCache = null;

function loadJson(key, fallback) {
  if (activeRenderJsonCache?.has(key)) return activeRenderJsonCache.get(key);
  let value = fallback;
  try {
    const stored = localStorage.getItem(key);
    value = stored === null ? JSON.parse(JSON.stringify(fallback)) : JSON.parse(stored);
  } catch {
    value = fallback;
  }
  activeRenderJsonCache?.set(key, value);
  return value;
}

function saveJson(key, value) {
  activeRenderJsonCache?.delete(key);
  localStorage.setItem(key, JSON.stringify(value));
}

function sha256Hex(value = '') {
  const bytes = [];
  for (const character of String(value)) {
    const code = character.codePointAt(0);
    if (code <= 0x7f) bytes.push(code);
    else if (code <= 0x7ff) bytes.push(0xc0 | (code >>> 6), 0x80 | (code & 63));
    else if (code <= 0xffff) bytes.push(0xe0 | (code >>> 12), 0x80 | ((code >>> 6) & 63), 0x80 | (code & 63));
    else bytes.push(0xf0 | (code >>> 18), 0x80 | ((code >>> 12) & 63), 0x80 | ((code >>> 6) & 63), 0x80 | (code & 63));
  }
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while ((bytes.length % 64) !== 56) bytes.push(0);
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((high >>> shift) & 255);
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((low >>> shift) & 255);
  const k = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
  ];
  const h = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
  const rotate = (word, bits) => (word >>> bits) | (word << (32 - bits));
  for (let offset = 0; offset < bytes.length; offset += 64) {
    const w = new Array(64);
    for (let i = 0; i < 16; i += 1) {
      const p = offset + i * 4;
      w[i] = ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i += 1) {
      const s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a,b,c,d,e,f,g,hh] = h;
    for (let i = 0; i < 64; i += 1) {
      const s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25);
      const ch = (e & f) ^ ((~e) & g);
      const t1 = (hh + s1 + ch + k[i] + w[i]) >>> 0;
      const s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (s0 + maj) >>> 0;
      hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    h[0]=(h[0]+a)>>>0; h[1]=(h[1]+b)>>>0; h[2]=(h[2]+c)>>>0; h[3]=(h[3]+d)>>>0;
    h[4]=(h[4]+e)>>>0; h[5]=(h[5]+f)>>>0; h[6]=(h[6]+g)>>>0; h[7]=(h[7]+hh)>>>0;
  }
  return h.map(word => word.toString(16).padStart(8, '0')).join('');
}

function navisionPayloadFingerprint(text = '') {
  return sha256Hex(String(text || ''));
}

function localStorageQuotaBytes(key, value) {
  return 2 * (String(key || '').length + String(value ?? '').length);
}

function currentLocalStorageValues() {
  const values = new Map();
  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index);
    if (key !== null) values.set(key, localStorage.getItem(key));
  }
  return values;
}

function boundedNavisionImportSummary(result = {}) {
  const parsedVehicles = result?.parsed?.vehicles || [];
  const allWarnings = (result?.skipped || result?.parsed?.warnings || [])
    .filter(Boolean).map(value => String(value));
  const warnings = allWarnings.slice(0, 50).map(value => value.slice(0, 200));
  const counts = {
    rows: parsedVehicles.length,
    added: result?.added?.length || 0,
    updated: result?.updated?.length || 0,
    unchanged: result?.unchanged?.length || 0,
    stockNumberUpdates: result?.stockNumberUpdates?.length || 0,
    restored: result?.restored?.length || 0,
    missingFromUpload: result?.missingFromUpload?.length || 0,
    removedMissing: result?.removedMissing?.length || 0,
    warnings: allWarnings.length,
  };
  const summary = {
    summaryVersion: NAVISION_IMPORT_SUMMARY_VERSION,
    fileName: String(result.fileName || app.navisionFileName || 'Pasted text').slice(0, 255),
    importedAt: String(result.importedAt || '').slice(0, 64),
    appliedAt: String(result.appliedAt || '').slice(0, 64),
    fullRefresh: result.fullRefresh !== false,
    confirmed: result.confirmed === true,
    counts,
    sourceFingerprint: /^[a-f0-9]{64}$/i.test(String(result.sourceFingerprint || ''))
      ? String(result.sourceFingerprint).toLowerCase()
      : sha256Hex(String(result.sourceFingerprint || '')),
    vehiclePayloadSha256: sha256Hex(JSON.stringify(parsedVehicles)),
    warningSha256: sha256Hex(JSON.stringify(allWarnings)),
    parsed: { vehicleCount: counts.rows, warnings },
    warningPreviewTruncated: allWarnings.length > warnings.length,
  };
  while (JSON.stringify(summary).length > NAVISION_IMPORT_SUMMARY_MAX_CHARS && summary.parsed.warnings.length) {
    summary.parsed.warnings.pop();
    summary.warningPreviewTruncated = true;
  }
  if (JSON.stringify(summary).length > NAVISION_IMPORT_SUMMARY_MAX_CHARS) {
    summary.parsed.warnings = [];
    summary.warningPreviewTruncated = true;
  }
  if (JSON.stringify(summary).length > NAVISION_IMPORT_SUMMARY_MAX_CHARS) {
    const minimal = {
      summaryVersion: NAVISION_IMPORT_SUMMARY_VERSION,
      counts,
      sourceFingerprint: summary.sourceFingerprint,
      vehiclePayloadSha256: summary.vehiclePayloadSha256,
      warningSha256: summary.warningSha256,
      warningPreviewTruncated: true,
    };
    if (JSON.stringify(minimal).length > NAVISION_IMPORT_SUMMARY_MAX_CHARS) {
      throw new Error('Navision import summary exceeds hard serialized ceiling');
    }
    return minimal;
  }
  return summary;
}

let storageTransactionDepth = 0;

function storageTransactionJournalStores() {
  const stores = [localStorage];
  try {
    if (typeof sessionStorage !== 'undefined' && sessionStorage && sessionStorage !== localStorage) stores.push(sessionStorage);
  } catch {}
  return stores;
}

function clearStorageTransactionJournals() {
  storageTransactionJournalStores().forEach(store => {
    try { store.removeItem(STORAGE_TRANSACTION_JOURNAL_KEY); } catch {}
  });
}

function recoverInterruptedStorageTransaction() {
  let journal = null;
  for (const store of storageTransactionJournalStores()) {
    let candidate = null;
    try { candidate = JSON.parse(store.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) || 'null'); } catch {}
    if (candidate?.snapshot && typeof candidate.snapshot === 'object') {
      journal = candidate;
      break;
    }
    try { store.removeItem(STORAGE_TRANSACTION_JOURNAL_KEY); } catch {}
  }
  if (!journal) return false;
  Object.keys(journal.snapshot).forEach(key => localStorage.removeItem(key));
  Object.entries(journal.snapshot).forEach(([key, entry]) => {
    if (entry?.exists) localStorage.setItem(key, String(entry.value ?? ''));
    else localStorage.removeItem(key);
  });
  clearStorageTransactionJournals();
  return true;
}

function prepareStorageTransaction(label = 'Tracker update', keys = [], startedAt = nowIsoString()) {
  const touchedKeys = [...new Set((Array.isArray(keys) ? keys : []).map(key => String(key || '').trim()).filter(Boolean))]
    .filter(key => key !== STORAGE_TRANSACTION_JOURNAL_KEY);
  const snapshot = Object.fromEntries(touchedKeys.map(key => {
    const value = localStorage.getItem(key);
    return [key, { exists: value !== null, value }];
  }));
  const journal = { version: 1, label, startedAt, snapshot };
  return { label, touchedKeys, snapshot, journal, serializedJournal: JSON.stringify(journal) };
}

function runStorageTransaction(label = 'Tracker update', keys = [], operation = () => undefined, prepared = null) {
  if (storageTransactionDepth > 0) return operation();
  const transaction = prepared || prepareStorageTransaction(label, keys);
  const { touchedKeys, snapshot, serializedJournal } = transaction;
  const snapshotStillCurrent = touchedKeys.every(key => {
    const value = localStorage.getItem(key);
    const entry = snapshot[key];
    return entry?.exists ? value === entry.value : value === null;
  });
  if (!snapshotStillCurrent) throw new Error(`${label} was cancelled because browser storage changed after the safety check.`);
  let journalStore = null;
  for (const store of storageTransactionJournalStores()) {
    try {
      store.setItem(STORAGE_TRANSACTION_JOURNAL_KEY, serializedJournal);
      journalStore = store;
      break;
    } catch {}
  }
  if (!journalStore) {
    throw new Error(`${label} could not start safely because the browser storage recovery snapshot could not be saved. Export a backup and free browser storage before trying again.`);
  }
  storageTransactionDepth += 1;
  try {
    const result = operation();
    journalStore.removeItem(STORAGE_TRANSACTION_JOURNAL_KEY);
    return result;
  } catch (error) {
    touchedKeys.forEach(key => localStorage.removeItem(key));
    Object.entries(snapshot).forEach(([key, entry]) => {
      if (entry.exists) localStorage.setItem(key, entry.value);
      else localStorage.removeItem(key);
    });
    journalStore.removeItem(STORAGE_TRANSACTION_JOURNAL_KEY);
    throw new Error(`${label} was not saved. The previous tracker data was restored. ${error?.message || error}`);
  } finally {
    storageTransactionDepth = Math.max(0, storageTransactionDepth - 1);
  }
}

function trackerTransactionKeys(extraKeys = []) {
  return [...new Set(CRM_BACKUP_STORAGE_KEYS.concat(extraKeys || []).filter(Boolean))];
}

function clearLocalDataFromUrl() {
  const search = String(window.location?.search || '');
  const ParamsCtor = window.URLSearchParams || (typeof URLSearchParams !== 'undefined' ? URLSearchParams : null);
  const resetRequested = ParamsCtor
    ? new ParamsCtor(search).has('clearLocalData') || new ParamsCtor(search).has('resetLocalData') || new ParamsCtor(search).has('freshData')
    : /[?&](clearLocalData|resetLocalData|freshData)(=|&|$)/.test(search);
  if (!resetRequested) return;
  const path = String(window.location?.pathname || '');
  const resetAllowed = /(?:test-\d+|no-vehicles)\.html$/i.test(path) || window.PDC_ALLOW_LOCAL_RESET === true;
  if (!resetAllowed) {
    console.warn('Local data reset was ignored on the live board. Use the Back End Data reset controls instead.');
    return;
  }
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

recoverInterruptedStorageTransaction();
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
function deletedVehicleKeyFromRecord(record) {
  return typeof record === 'string' ? record : String(record?.key || record?.vehicleKey || record?.stock || record?.order || record?.id || '').trim();
}
function deletedVehicleKeys(records = loadDeletedVehicles()) {
  const keys = new Set();
  (Array.isArray(records) ? records : []).forEach(record => {
    const primary = deletedVehicleKeyFromRecord(record);
    if (primary) keys.add(primary);
    if (record && typeof record === 'object' && Array.isArray(record.keys)) {
      record.keys.map(value => String(value || '').trim()).filter(Boolean).forEach(value => keys.add(value));
    }
  });
  return keys;
}
function deletedVehicleRecords() {
  return (Array.isArray(loadDeletedVehicles()) ? loadDeletedVehicles() : []).map(record => {
    if (typeof record === 'string') return { key: record, deletedAt: '', deletedBy: '', vehicle: { stock: record } };
    return {
      key: deletedVehicleKeyFromRecord(record),
      deletedAt: record.deletedAt || '',
      deletedBy: record.deletedBy || '',
      deletedRole: record.deletedRole || '',
      reason: record.reason || '',
      deletionType: record.deletionType || '',
      vehicle: record.vehicle || { stock: record.stock || record.key || '' },
      keys: Array.isArray(record.keys) ? record.keys : [],
    };
  }).filter(record => record.key);
}
function saveDeletedVehicleRecords(records = []) { saveDeletedVehicles(records); }
const DEFAULT_MECHANICS = [
  'Ajafari Abdelkrim',
  'Andrew McCormick',
  'Ben Palmer',
  'Chelsea Rees # 2',
  'Daniel Evelyn',
  'Gurmohan Singh',
  'James Ierino',
  'Jamie Bello',
  'Joe Izzi',
  'John Castagna',
  'Jundullah Sharif Ramli',
  'Kade Bailey',
  'Luke Walton',
  'Nick Darker',
  'Ratchapool Jaumorn',
  'Ravindra Singh',
  'Richard Tatov',
  'Robert Celenza',
  'Samuel Sherratt',
  'Simon Duncan',
  'Simon Fraser',
  'Thanh Truong',
  'Wilfredo Aquionos',
  'Winn Chiu Pang',
  'Zachary King',
];

function normalizedMechanicList(names = []) {
  return [...new Set((Array.isArray(names) ? names : []).map(name => cleanNavisionText(name)).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
}

// Stage 2A: mechanics/technicians are now authoritative in Supabase
// (public.workshop_technicians via workshop-reference-data-service.js),
// not localStorage. loadMechanics() keeps its existing synchronous,
// plain-name-array return shape so every one of its ~10 existing call
// sites (bay-assignment dropdowns, Setup screen admin list, KPI counts)
// keeps working unmodified -- but the data itself now comes from the
// service's disposable in-memory cache, refreshed by realtime, never from
// MECHANICS_KEY. If the shared service has not loaded yet (e.g. before
// the first authenticated fetch completes) this returns an empty list
// rather than falling back to localStorage or the old hard-coded
// DEFAULT_MECHANICS seed -- a real name list only ever comes from
// Supabase now.
function loadMechanics() {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedTechnicians();
  return normalizedMechanicList((cached.rows || []).filter(row => row.active).map(row => row.name));
}
// Returns the full technician records (id/name/active/version), not just
// names -- needed by the Setup screen admin UI to call
// addTechnician/editTechnician/setTechnicianActive with a real id and
// expected_version rather than only a display name.
function loadMechanicRecords(includeInactive = false) {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedTechnicians();
  const rows = cached.rows || [];
  return includeInactive ? rows : rows.filter(row => row.active);
}
// Triggers an authoritative (re)load from Supabase -- call this once at
// boot and whenever the admin Setup screen is opened, since loadMechanics()
// itself only reads the disposable in-memory cache synchronously and never
// triggers a network fetch on its own (matching the existing synchronous
// call-site contract every caller of loadMechanics() already relies on).
function refreshWorkshopReferenceData() {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return;
  service.listTechnicians(true).catch(() => {});
  service.listSalespeople(true).catch(() => {});
  service.listSubletProviders(true).catch(() => {});
  service.listWorkshopBays(true).catch(() => {});
  if (typeof service.getWorkshopConfiguration === 'function') service.getWorkshopConfiguration().catch(() => {});
  service.subscribeTechnicians();
  service.subscribeSalespeople();
  service.subscribeSubletProviders();
  service.subscribeWorkshopBays();
  if (typeof service.subscribeWorkshopSettings === 'function') service.subscribeWorkshopSettings();
  startWorkshopReferenceDataReconciliationTimer();
}

// Periodic lightweight reconciliation while the page is open, as a
// backstop against any missed/undelivered realtime event (network
// blips, dropped messages, etc.) -- the realtime subscriptions above
// are the primary update path and this timer is deliberately low
// frequency (2 minutes) since it is a safety net, not the main path.
// Guarded against duplicate timers if this is called more than once
// per page load (e.g. across the two refreshWorkshopReferenceData()
// call sites), and stopped on logout/account-lockout so it never
// polls with a signed-out session.
function startWorkshopReferenceDataReconciliationTimer() {
  if (window.__workshopReferenceDataReconcileTimer) return;
  window.__workshopReferenceDataReconcileTimer = window.setInterval(() => {
    const service = window.__workshopReferenceDataService;
    if (!service || !window.PDC_AUTH_CONTEXT) return;
    service.listTechnicians(true).catch(() => {});
    service.listSalespeople(true).catch(() => {});
    service.listSubletProviders(true).catch(() => {});
    service.listWorkshopBays(true).catch(() => {});
    if (typeof service.getWorkshopConfiguration === 'function') service.getWorkshopConfiguration().catch(() => {});
  }, 120000);
}

function stopWorkshopReferenceDataReconciliationTimer() {
  if (window.__workshopReferenceDataReconcileTimer) {
    window.clearInterval(window.__workshopReferenceDataReconcileTimer);
    window.__workshopReferenceDataReconcileTimer = null;
  }
  if (window.__workshopReferenceDataService && typeof window.__workshopReferenceDataService.unsubscribeAll === 'function') {
    window.__workshopReferenceDataService.unsubscribeAll();
  }
}

const DEFAULT_SUBLET_PROVIDERS = [
  '4X4 Mechanic - Ascot',
  'ARB',
  'ARB - Welshpool',
  'Ashley Group',
  'Autonomo',
  'AV Auto Elec',
  'Beam',
  'Beam Rustproofing',
  'Bull Motor Bodies',
  'Customer Sublet',
  'Electrical - 53 Fortron Blvd High Wycombe',
  'Great Racks',
  'Great Racks - Bibra Lake',
  'Harness Master',
  'Hidrive',
  'Hidrive - Canning Vale',
  'Hunter Mech',
  'Ironman Canning Vale',
  'Jaram',
  'Jason Signs',
  'Lovells',
  'Malaga Springs',
  'Malaga Springs and Suspensions',
  'MMT',
  'MRT Perth',
  'MRT - Bibra Lake',
  'Norweld',
  'Pedders - Cockburn',
  'Pedders - Malaga',
  'Pedders Cannington',
  'Perth Ceramic Coating',
  'PK Technology',
  'PTE',
  'Roscoes',
  'SWAT',
  'Swank',
  'TC Boxes Bayswater',
  'Techfire',
  'TL Engineering',
  'TWD 4X4',
  'Tyrepower - Osborne Park',
  'Tyrepower - West Perth',
  'Ultimate 4X4',
  'Unicorn Transport Equipment',
  'Westrac',
];

const SUBLET_PROVIDER_ALIASES = new Map([
  ['arb welshpool', 'ARB - Welshpool'],
  ['arb - welshpool', 'ARB - Welshpool'],
  ['customersublet', 'Customer Sublet'],
  ['customer sublet', 'Customer Sublet'],
  ['harnessmaster', 'Harness Master'],
  ['harness master', 'Harness Master'],
  ['hidrive canning vale', 'Hidrive - Canning Vale'],
  ['hidrive - canning vale', 'Hidrive - Canning Vale'],
  ['malaga springs and suspensions', 'Malaga Springs and Suspensions'],
  ['pedders malaga', 'Pedders - Malaga'],
  ['pedders - malaga', 'Pedders - Malaga'],
  ['roscos', 'Roscoes'],
  ['roscoes', 'Roscoes'],
  ['techfire', 'Techfire'],
  ['tyrepower west perth', 'Tyrepower - West Perth'],
  ['tyrepower - west perth', 'Tyrepower - West Perth'],
  ['ultimate4x4', 'Ultimate 4X4'],
  ['ultimate 4x4', 'Ultimate 4X4'],
]);

const SUBLET_PROVIDER_ACRONYMS = new Set(['4X4', 'ARB', 'AV', 'MMT', 'MRT', 'PK', 'PTE', 'SWAT', 'TC', 'TL', 'TWD']);

function normalizeSubletProviderName(value = '') {
  const clean = cleanNavisionText(value).replace(/\s*-\s*/g, ' - ');
  if (!clean) return '';
  const alias = SUBLET_PROVIDER_ALIASES.get(clean.toLowerCase());
  if (alias) return alias;
  return clean.toLowerCase().replace(/\b[0-9a-z]+\b/gi, (word, offset) => {
    const upper = word.toUpperCase();
    if (SUBLET_PROVIDER_ACRONYMS.has(upper)) return upper;
    if (offset > 0 && ['and', 'of', 'the'].includes(word.toLowerCase())) return word.toLowerCase();
    return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  });
}

function normalizedSubletProviderList(names = []) {
  const unique = new Map();
  (Array.isArray(names) ? names : []).forEach(name => {
    const normalized = normalizeSubletProviderName(name);
    if (normalized) unique.set(normalized.toLowerCase(), normalized);
  });
  return [...unique.values()].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
}

// Stage 2A: sublet providers are now authoritative in Supabase
// (public.sublet_providers via workshop-reference-data-service.js), not
// localStorage. loadSubletProviders() keeps its existing synchronous
// plain-name-array shape for every existing call site.
function loadSubletProviders() {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedSubletProviders();
  return normalizedSubletProviderList((cached.rows || []).filter(row => row.active).map(row => row.name));
}
function loadSubletProviderRecords(includeInactive = false) {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedSubletProviders();
  const rows = cached.rows || [];
  return includeInactive ? rows : rows.filter(row => row.active);
}

const DEFAULT_SALESPERSONS = [
  { initials: 'SL', name: 'Scott Lovett', email: 'scott.lovett@pmgwa.com.au' },
  { initials: 'CW', name: 'Craig Watson', email: 'craig.watson@broometoyota.com.au' },
  { initials: 'BG', name: 'Bryce Guthrie', email: 'bryce.guthrie@broometoyota.com.au' },
  { initials: 'CF', name: 'Clint Franklin', email: 'clint.franklin@pmgwa.com.au' },
  { initials: 'JB', name: 'Jason Battle', email: 'jason.battle@pmgwa.com.au' },
];

function normalizeSalespersonRecord(record = {}) {
  const initials = cleanNavisionText(record.initials || record.code || record.consultant || '').replace(/[^a-z0-9]/gi, '').toUpperCase().slice(0, 6);
  const name = cleanNavisionText(record.name || record.fullName || '');
  const email = cleanNavisionText(record.email || '').toLowerCase();
  if (!initials || !email || !email.includes('@')) return null;
  return { initials, name: name || initials, email };
}

function normalizedSalespersonList(records = []) {
  const unique = new Map();
  (Array.isArray(records) ? records : []).forEach(record => {
    const normalized = normalizeSalespersonRecord(record);
    if (normalized) unique.set(normalized.initials, normalized);
  });
  return [...unique.values()].sort((a, b) => a.initials.localeCompare(b.initials));
}

// Stage 2A: salespeople are now authoritative in Supabase
// (public.salespeople via workshop-reference-data-service.js), not
// localStorage. loadSalespersons() keeps its existing synchronous
// {initials, name, email} record shape for every existing call site --
// 'initials' maps to the database's 'code' column.
function loadSalespersons() {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedSalespeople();
  return normalizedSalespersonList((cached.rows || []).filter(row => row.active).map(row => ({ initials: row.code, name: row.name, email: row.email })));
}
function loadSalespersonRecords(includeInactive = false) {
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) return [];
  const cached = service.getCachedSalespeople();
  const rows = cached.rows || [];
  return includeInactive ? rows : rows.filter(row => row.active);
}

function salespersonRecord(value = '') {
  const clean = cleanNavisionText(value);
  const lower = clean.toLowerCase();
  const isInitialsCode = /^[a-z0-9]{1,6}$/i.test(clean);
  return loadSalespersons().find(record =>
    (isInitialsCode && record.initials === clean.toUpperCase()) ||
    record.name.toLowerCase() === lower || record.email.toLowerCase() === lower
  ) || null;
}

function salespersonForVehicle(vehicle = {}) {
  const directEmail = cleanNavisionText(vehicle.salespersonEmail || vehicle.salesPersonEmail || vehicle.consultantEmail || vehicle.ownerEmail || vehicle.salesEmail || '');
  const consultant = consultantName(vehicle);
  if (directEmail) {
    const directRecord = loadSalespersons().find(record => record.email.toLowerCase() === directEmail.toLowerCase());
    return { initials: directRecord?.initials || salesPersonInitials(consultant), name: directRecord?.name || (consultant === 'Unassigned' ? 'Sales' : consultant), email: directEmail };
  }
  const record = salespersonRecord(consultant);
  if (record) return record;
  return null;
}

function salespersonOptionsHtml(current = '') {
  const selectedValue = cleanNavisionText(current);
  const isInitialsCode = /^[a-z0-9]{1,6}$/i.test(selectedValue);
  const records = loadSalespersons();
  const known = records.some(record => (isInitialsCode && record.initials === selectedValue.toUpperCase()) || record.name.toLowerCase() === selectedValue.toLowerCase());
  const unknownOption = selectedValue && selectedValue !== 'Unassigned' && !known
    ? `<option value="${escapeHtml(selectedValue)}" selected>${escapeHtml(selectedValue)} — imported value</option>`
    : '';
  return `<option value="">Unassigned</option>${unknownOption}${records.map(record => {
    const selected = (isInitialsCode && record.initials === selectedValue.toUpperCase()) || record.name.toLowerCase() === selectedValue.toLowerCase();
    return `<option value="${escapeHtml(record.initials)}"${selected ? ' selected' : ''}>${escapeHtml(record.initials)} — ${escapeHtml(record.name)}</option>`;
  }).join('')}`;
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
  return Boolean(key && deletedVehicleKeys().has(key));
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
  const deleted = deletedVehicleKeys();
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
  singleSearchFocus: {},
  workflowFilters: {
    sort: 'oldest',
    bucket: '',
    work: '',
    required: '',
    completion: '',
    stoppage: '',
  },
  workflowWidthMode: 'standard',
  sort: { key: '', dir: 'asc' },
  selectedRows: new Set(),
  columnFilters: { sales: '', production: '', status: '', jita: '' },
  filterOptions: { statuses: [], consultants: [], productionMonths: [], sources: [] },
  autocareFiles: [],
  autocareScan: loadJson(AUTOCARE_RESULTS_KEY, null),
  aiIntakeFiles: [],
  aiIntakeStatus: [],
  navisionImport: loadJson(NAVISION_IMPORT_RESULTS_KEY, null),
  pendingNavisionImport: null,
  navisionFileName: '',
  rejectedNavisionFingerprint: '',
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
  const accessible = `JITA ${state}: ${detail || 'No status recorded'}`;
  if (state === 'Yes') return `<span class="jita-icon jita-yes" role="img" aria-label="${escapeHtml(accessible)}" title="${escapeHtml(detail)}">✓</span>`;
  if (state === 'No') return `<span class="jita-icon jita-no" role="img" aria-label="${escapeHtml(accessible)}" title="${escapeHtml(detail)}">×</span>`;
  return `<span class="jita-icon jita-unknown" role="img" aria-label="${escapeHtml(accessible)}" title="${escapeHtml(detail)}">?</span>`;
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

const STATUS_TAB_DEFS = [];
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

  // Source status may group an already-visible vehicle through Yard Hold. PMB and
  // RFT are independent PDC locations and are protected from normal Navision imports.
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
  return '';
}

function vehicleIdentityStackHtml(vehicle = {}, options = {}) {
  const includeName = options.includeName !== false;
  const cells = vehicleIdentityCells(vehicle).filter(cell => includeName || cell.label !== 'Name');
  const key = vehicleKey(vehicle);
  const title = vehicleIdentityTitle(vehicle);
  const classes = ['vehicle-identity-stack', 'vehicle-identity-columns', includeName ? '' : 'vehicle-identity-no-name', options.className || ''].filter(Boolean).join(' ');
  const html = cells.map((cell, index) => {
    const rawValue = cleanNavisionText(cell.value) || '—';
    // Customer names are deliberately left intact. CSS gives the name cell room to wrap
    // so long company names remain readable instead of being cut down to a few characters.
    const value = cell.label === 'Name' ? rawValue : truncate(rawValue, 18);
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
  const importTimestamp = app.navisionImport?.appliedAt || app.navisionImport?.importedAt || '';
  const importedAt = importTimestamp ? new Date(importTimestamp) : null;
  const masterImport = window.VEHICLE_TRACKING_DATA?.report?.masterImport || null;
  const masterDate = masterImport?.importedAt ? parseDateAU(String(masterImport.importedAt).split('-').reverse().join('/')) : null;
  const dateLabel = importedAt && !Number.isNaN(importedAt.getTime())
    ? importedAt.toLocaleString('en-AU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : masterImport
      ? `Master EOS · ${masterDate && !Number.isNaN(masterDate.getTime()) ? masterDate.toLocaleDateString('en-AU') : masterImport.importedAt}`
      : 'No Navision import yet';
  const reportDate = $('#report-date');
  const reportMeta = $('#report-meta');
  const pdcCount = pdcSheetVehicles(app.data).length;
  const backEndOnlyCount = app.data.length - pdcCount;
  if (reportDate) reportDate.textContent = dateLabel;
  if (reportMeta) reportMeta.textContent = `${pdcCount} PDC sheet · ${backEndOnlyCount} back end only`;
}

function loadOperationalHealth() {
  return loadJson(OPERATIONAL_HEALTH_KEY, {});
}

function updateOperationalHealth(updates = {}) {
  const health = { ...loadOperationalHealth(), ...updates };
  try { saveJson(OPERATIONAL_HEALTH_KEY, health); }
  catch (error) { console.warn('Operational health metadata could not be saved.', error); }
  renderOperationalHealthSummary();
  return health;
}

function operationalHealthDateLabel(value = '') {
  const date = parseIsoTimestamp(value);
  return date ? date.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'Not recorded';
}

function operationalHealthAgeHours(value = '') {
  const date = parseIsoTimestamp(value);
  return date ? Math.max(0, (Date.now() - date.getTime()) / 3600000) : null;
}

function renderOperationalHealthSummary() {
  const host = $('#operational-health-summary');
  if (!host) return;
  const health = loadOperationalHealth();
  const navisionAt = health.lastNavisionImportAt || app.navisionImport?.appliedAt || app.navisionImport?.importedAt || '';
  const navisionAge = operationalHealthAgeHours(navisionAt);
  const navisionTone = navisionAge === null || navisionAge > 36 ? 'warn' : Number(health.lastNavisionWarnings || 0) > 0 ? 'watch' : 'ok';
  const backupAge = operationalHealthAgeHours(health.lastBackupAt);
  const backupTone = backupAge === null || backupAge > 168 ? 'warn' : 'ok';
  const navisionDetail = navisionAt
    ? `${operationalHealthDateLabel(navisionAt)}${health.lastNavisionRows ? ` · ${health.lastNavisionRows} rows` : ''}${health.lastNavisionWarnings ? ` · ${health.lastNavisionWarnings} warning${Number(health.lastNavisionWarnings) === 1 ? '' : 's'}` : ''}`
    : 'Not imported yet';
  const workLabel = cleanNavisionText(health.lastWorkImportType || '') || 'PO / job card';
  const workDetail = health.lastWorkImportAt
    ? `${operationalHealthDateLabel(health.lastWorkImportAt)}${health.lastWorkImportRows ? ` · ${health.lastWorkImportRows} vehicle${Number(health.lastWorkImportRows) === 1 ? '' : 's'}` : ''}`
    : 'Not imported yet';
  host.innerHTML = `
    <span class="health-line ${navisionTone}" title="${escapeHtml(navisionDetail)}"><b>Navision</b><small>${escapeHtml(navisionDetail)}</small></span>
    <span class="health-line ${health.lastWorkImportAt ? 'ok' : 'neutral'}" title="${escapeHtml(workDetail)}"><b>${escapeHtml(workLabel)}</b><small>${escapeHtml(workDetail)}</small></span>
    <span class="health-line ${backupTone}"><b>Backup</b><small>${escapeHtml(health.lastBackupAt ? operationalHealthDateLabel(health.lastBackupAt) : 'Not exported yet')}</small></span>`;
}

function vehicleSourceText(vehicle = {}) {
  return cleanNavisionText(vehicle.source || vehicle.group || '').toLowerCase();
}

function vehicleHasManualOrPdcOrigin(vehicle = {}) {
  const source = vehicleSourceText(vehicle);
  const lifecycle = cleanNavisionText(vehicle.recordLifecycle || '').toLowerCase();
  return Boolean(
    /\bmanual\b|pd check-form|purchase order|po only|master2021|master sheet/.test(source) ||
    ['manual', 'purchase-order', 'pd-check-form', 'pdc'].includes(lifecycle)
  );
}

function vehicleHasPdcTrackingSignal(vehicle = {}) {
  if (vehicle.pdcSheetVisible === true) return true;
  if (vehiclePdcLocation(vehicle)) return true;
  if (normalizePmbStage(vehicle.pmbStage || vehicle.pdcWorkStage || vehicle.workStage || '')) return true;
  if (isPdcBlocked(vehicle) || vehicle.pdcPartsStoppage === true) return true;
  if ((vehicle.poTasks || []).length || (vehicle.poFiles || []).length || vehicle.buildPoRaised === true) return true;
  return PDC_JOB_DEFS.some(def => vehicle[def.requireKey] === true || vehicle[def.completeKey] === true);
}

function isVehicleVisibleOnPdcSheet(vehicle = {}) {
  if (vehicleHasManualOrPdcOrigin(vehicle) || vehicleHasPdcTrackingSignal(vehicle)) return true;
  if (vehicle.pdcSheetVisible === false) return false;
  const source = vehicleSourceText(vehicle);
  // Legacy tracker/master rows pre-date the visibility flag and must remain visible.
  return !/navision/.test(source);
}

function pdcSheetVehicles(rows = app.data) {
  return (Array.isArray(rows) ? rows : []).filter(isVehicleVisibleOnPdcSheet);
}

function isNavisionOnlyBackEndVehicle(vehicle = {}) {
  const source = vehicleSourceText(vehicle);
  return /navision/.test(source) && !vehicleHasManualOrPdcOrigin(vehicle) && !isVehicleVisibleOnPdcSheet(vehicle);
}

function promoteVehicleToPdcSheet(vehicle = {}, visibilitySource = 'Independent vehicle load') {
  const key = vehicleKey(vehicle);
  if (!key) return vehicle;
  const updates = {
    pdcSheetVisible: true,
    pdcVisibilitySource: cleanNavisionText(visibilitySource) || 'Independent vehicle load',
    pdcPromotedAt: vehicle.pdcPromotedAt || nowIsoString(),
  };
  Object.assign(vehicle, updates);
  const edits = loadVehicleEdits();
  edits[key] = { ...(edits[key] || {}), ...updates };
  saveJson(EDITS_KEY, edits);
  return vehicle;
}

function pdcVisibilityPromotionUpdates(vehicle = {}, visibilitySource = 'Independent PDC work') {
  return {
    pdcSheetVisible: true,
    pdcVisibilitySource: cleanNavisionText(visibilitySource) || 'Independent PDC work',
    pdcPromotedAt: vehicle.pdcPromotedAt || nowIsoString(),
  };
}

function vehicleWasIndependentlyPromoted(vehicle = {}) {
  if (vehicleHasManualOrPdcOrigin(vehicle)) return true;
  const source = cleanNavisionText(vehicle.pdcVisibilitySource || '').toLowerCase();
  return /manual|purchase order|pd check-form|work \/ job file|independent|operator|job card/.test(source);
}

function init() {
  ensureAppDataAvailable();
  migrateLegacyAutocareArrivalsToPmb();
  renderAppVersionMarker();
  renderHostingSecurityWarning();
  applyWorkflowWidthMode(loadWorkflowWidthMode());
  if (document.body?.dataset) document.body.dataset.currentView = app.currentView || 'dashboard';
  updateNavisionSidebarMeta();
  const visibleRows = pdcSheetVehicles();
  app.selectedStock = vehicleKey(visibleRows.find(v => v.toyotaStatus) || visibleRows[0] || app.data[0]);
  bindNav();
  populateFilters();
  renderAll();
  loadVehicleLifecycleSharedActionsIfConfigured();
  loadWorkshopReferenceDataServiceIfConfigured();
}

// Loads workshop-reference-data-service.js (Stage 2A) lazily, mirroring
// the existing lazy-load pattern used for the other shared-data bridges.
// Unlike those, this one is NOT behind a feature flag -- it loads
// whenever window.PDC_SUPABASE_CONFIG exists at all, since mechanics/
// salespeople/sublet-providers/bays/workshop-configuration must be
// Supabase-authoritative immediately per the Stage 2A instruction. It
// still requires a real authenticated session before it reports anything
// other than a clear not-authenticated/offline state (see
// initWorkshopReferenceDataServiceIfAvailable() and
// getPdcSupabaseAccessToken()).
function loadWorkshopReferenceDataServiceIfConfigured() {
  if (!window.PDC_SUPABASE_CONFIG || typeof loadExternalScript !== 'function') return;
  loadExternalScript(`workshop-reference-data-service.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-reference-data-service-script')
    .then(() => {
      initWorkshopReferenceDataServiceIfAvailable();
      if (typeof refreshWorkshopReferenceData === 'function') refreshWorkshopReferenceData();
    })
    .catch(() => { /* non-fatal: renderAdminLists()/loadMechanics() etc. report an explicit offline/error state instead of throwing */ });
}

// Loads vehicle-lifecycle-actions.js lazily (mirrors the workshop shared
// data service's own lazy-load pattern) and only initializes the bridge
// once loaded. No-op unless window.PDC_SUPABASE_CONFIG.vehicleLifecycle.
// sharedData is explicitly true, so pages without that config never fetch
// the extra script and legacy QC/RFT/Collected behaviour is unaffected.
function loadVehicleLifecycleSharedActionsIfConfigured() {
  if (typeof workshopSharedModeEnabled === 'function' && workshopSharedModeEnabled(window.PDC_SUPABASE_CONFIG)) {
    // Already being loaded by the workshop planner path; createWorkshopSupabaseClient
    // will already be available once that finishes, so just wait for it below.
  }
  if (!window.PDC_SUPABASE_CONFIG || !window.PDC_SUPABASE_CONFIG.vehicleLifecycle || window.PDC_SUPABASE_CONFIG.vehicleLifecycle.sharedData !== true) return;
  if (typeof loadExternalScript !== 'function') return;
  const lifecycleAssetVersion = window.PDC_SUPABASE_CONFIG.vehicleLifecycle.resolverAssetVersion || APP_VERSION;
  loadExternalScript(`vehicle-lifecycle-actions.js?v=${encodeURIComponent(lifecycleAssetVersion)}`, 'vehicle-lifecycle-actions-script')
    .then(() => {
      // createWorkshopSupabaseClient lives in workshop-data-service.js; load
      // it too if it is not already present (it may already be loaded by
      // the workshop planner path, in which case this is a fast no-op).
      if (typeof createWorkshopSupabaseClient === 'function') {
        initVehicleLifecycleSharedActionsIfEnabled();
        return;
      }
      loadExternalScript(`workshop-data-service.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-data-service-script')
        .then(() => initVehicleLifecycleSharedActionsIfEnabled())
        .catch(() => { /* fail closed: configured shared lifecycle actions report service_unavailable */ });
    })
    .catch(() => { /* fail closed: configured shared lifecycle actions report service_unavailable */ });
}

function renderAppVersionMarker() {
  const host = $('#app-version');
  if (host) host.textContent = `Version ${APP_VERSION}`;
}

let incomingSearchRenderTimer = null;

function queueIncomingDashboardRender() {
  if (incomingSearchRenderTimer) clearTimeout(incomingSearchRenderTimer);
  incomingSearchRenderTimer = setTimeout(() => {
    incomingSearchRenderTimer = null;
    renderIncomingDashboardBoard();
  }, 160);
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
  on($('#parts-eta-filter'), 'change', renderPartsHome);
  on($('#parts-eta-sort'), 'change', renderPartsHome);
  on($('#parts-department-filter'), 'change', renderPartsHome);
  on($('#email-review-status-filter'), 'change', renderEmailIntakeReview);
  // Do not pass the click event as the explicit analysis clock.
  on($('#ai-board-refresh'), 'click', () => renderAiBoardAdvisor());
  on($('#ai-intake-upload'), 'change', handleAiFileAssistantSelect);
  on($('#ai-intake-analyze'), 'click', analyzeAiFileAssistantUploads);
  on($('#ai-intake-clear'), 'click', () => clearAiFileAssistantUploads());
  on($('#sublet-search'), 'input', renderSubletHome);
  on($('#sublet-status-filter'), 'change', renderSubletHome);
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
  on($('#deleted-export-csv'), 'click', exportDeletedVehiclesCsv);
  on($('#deleted-search'), 'input', renderDeletedVehicles);
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
  on($('#email-selected-update-bar'), 'click', () => draftSelectedVehicleStatusEmail());
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
  on($('#navision-dealer-code'), 'change', updateNavisionImportButton);
  on($('#export-local-navision'), 'click', exportLocalNavisionDataset);
  on($('#dashboard-navision-paste'), 'input', updateDashboardNavisionPasteButtons);
  on($('#dashboard-import-navision'), 'click', importDashboardNavisionPaste);
  on($('#dashboard-clear-navision'), 'click', clearDashboardNavisionPaste);
  on($('#dashboard-pd-paste'), 'input', updateDashboardPdImportButtons);
  on($('#dashboard-pd-upload'), 'change', handleDashboardPdFileSelect);
  on($('#dashboard-import-pd'), 'click', importDashboardPdWork);
  on($('#dashboard-clear-pd'), 'click', clearDashboardPdImport);
  on($('#incoming-search'), 'input', queueIncomingDashboardRender);
  on($('#incoming-status-filter'), 'change', renderIncomingDashboardBoard);
  on($('#incoming-bucket-filter'), 'change', renderIncomingDashboardBoard);
  on($('#incoming-rep-filter'), 'change', renderIncomingDashboardBoard);
  $$('input[name="incoming-work-filter"]').forEach(input => input.addEventListener('change', renderIncomingDashboardBoard));
  on($('#incoming-find'), 'click', renderIncomingDashboardBoard);
  on($('#incoming-clear-filters'), 'click', clearIncomingDashboardFilters);
  on($('#incoming-collapse-all'), 'click', toggleMainScreenRows);
  on($('#workflow-collapse-all'), 'click', toggleWorkflowRows);
  on($('#rft-collapse-all'), 'click', toggleRftRows);
  on($('#completed-collapse-all'), 'click', toggleCompletedRows);
  on($('#deleted-collapse-all'), 'click', toggleDeletedRows);
  on($('#workflow-width-mode'), 'change', event => setWorkflowWidthMode(event.target.value));
  on($('#workflow-search'), 'input', event => { app.workflowSearch = String(event.target.value || '').trim().toLowerCase(); renderWorkflowBoard(); });
  on($('#workflow-find'), 'click', () => { app.workflowSearch = String($('#workflow-search')?.value || '').trim().toLowerCase(); renderWorkflowBoard(); });
  on($('#workflow-clear-search'), 'click', clearWorkflowSearch);
  document.addEventListener('change', event => {
    const select = event.target?.closest?.('[data-workflow-header-filter]');
    if (!select) return;
    applyWorkflowHeaderFilter(select.dataset.workflowHeaderFilter, select.value, select.dataset.workflowWorkKey || '');
  });
  document.addEventListener('click', event => {
    const clear = event.target?.closest?.('[data-workflow-clear-column-filters]');
    if (!clear) return;
    event.preventDefault();
    event.stopPropagation();
    clearWorkflowFilters();
  });
  if (window.addEventListener) {
    window.addEventListener('scroll', scheduleWorkflowFloatingHeaderUpdate, { passive: true });
    window.addEventListener('resize', scheduleWorkflowFloatingHeaderUpdate, { passive: true });
  }
  document.addEventListener('scroll', scheduleWorkflowFloatingHeaderUpdate, true);
  on($('#incoming-transfer-selected-pmb'), 'click', transferSelectedMainYhVehiclesToPmb);
  on($('#incoming-email-selected-update'), 'click', () => draftSelectedVehicleStatusEmail());
  on($('#incoming-delete-selected'), 'click', deleteSelectedVehicles);
  on($('#incoming-clear-selected'), 'click', clearSelectedRows);
  on($('#workflow-transfer-selected-rft'), 'click', transferSelectedPmbVehiclesToRft);
  on($('#workflow-email-selected-update'), 'click', () => draftSelectedVehicleStatusEmail());
  on($('#workflow-delete-selected'), 'click', deleteSelectedVehicles);
  on($('#workflow-clear-selected'), 'click', clearSelectedRows);
  bindDashboardPdDropZone();
  on($('#navision-pmb-only'), 'change', updateNavisionImportButton);
  on($('#import-navision'), 'click', importNavisionVehicles);
  on($('#apply-navision-shared'), 'click', applySharedNavisionImport);
  on($('#navision-clear'), 'click', clearNavisionImport);
  on($('#backend-data-search'), 'input', renderBackEndData);
  on($('#backend-data-state-filter'), 'change', renderBackEndData);
  on($('#backend-data-clear-search'), 'click', clearBackEndDataSearch);
  on($('#add-mechanic-list-button'), 'click', addMechanicFromAdminInput);
  on($('#mechanic-name-input'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); addMechanicFromAdminInput(); } });
  on($('#add-sublet-provider-button'), 'click', addSubletProviderFromAdminInput);
  on($('#sublet-provider-name-input'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); addSubletProviderFromAdminInput(); } });
  on($('#add-salesperson-button'), 'click', addSalespersonFromAdminInput);
  on($('#backup-status-refresh'), 'click', renderBackupStatusPanel);
  on($('#user-management-refresh'), 'click', renderUserManagementScreen);
  $$('#user-management-tabs [data-um-tab]').forEach(button => on(button, 'click', () => {
    USER_MANAGEMENT_STATE.tab = button.dataset.umTab;
    $$('#user-management-tabs [data-um-tab]').forEach(other => other.classList.toggle('active', other === button));
    renderUserManagementScreen();
  }));
  ['#salesperson-initials-input', '#salesperson-name-input', '#salesperson-email-input'].forEach(selector => {
    on($(selector), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); addSalespersonFromAdminInput(); } });
  });
  on($('#scan-autocare'), 'click', scanAutocareNotice);
  on($('#autocare-clear'), 'click', clearAutocareResults);
  on($('#autocare-zpl-all'), 'click', () => printZplFromAutocareResults('all'));
  on($('#autocare-zpl-unmatched'), 'click', () => printZplFromAutocareResults('unmatched'));
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
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared mechanic list right now. Check your connection and try again.'); return; }
  service.addTechnician(entered).then(result => {
    if (!result.ok) {
      window.alert(result.error === 'duplicate_name' ? `"${entered}" is already on the mechanic list.` : (result.error || 'Could not add mechanic.'));
      return;
    }
    if (input) input.value = '';
    renderAdminLists();
    renderKpis();
  });
}

function removeMechanicFromAdminList(name = '') {
  const clean = cleanNavisionText(name);
  if (!clean) return;
  if (!window.confirm(`Remove mechanic "${clean}" from the dropdown list? Existing vehicle history will stay on the vehicle.`)) return;
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared mechanic list right now. Check your connection and try again.'); return; }
  const record = loadMechanicRecords(true).find(row => row.name === clean);
  if (!record) { window.alert(`"${clean}" was not found.`); return; }
  // Deactivate rather than delete -- preserves every historical
  // workshop_booking_assignments row that already points at this
  // technician_id, exactly as the Stage 2A requirement specifies.
  service.setTechnicianActive(record.id, record.version, false).then(result => {
    if (!result.ok) { window.alert(result.error || 'Could not remove mechanic.'); return; }
    renderAdminLists();
    renderKpis();
  });
}

function addSubletProviderFromAdminInput() {
  const input = $('#sublet-provider-name-input');
  const entered = cleanNavisionText(input?.value || '');
  if (!entered) return;
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared provider list right now. Check your connection and try again.'); return; }
  service.addSubletProvider(entered).then(result => {
    if (!result.ok) {
      window.alert(result.error === 'duplicate_name' ? `"${entered}" is already on the provider list.` : (result.error || 'Could not add provider.'));
      return;
    }
    if (input) input.value = '';
    renderAdminLists();
    renderKpis();
  });
}

function removeSubletProviderFromAdminList(name = '') {
  const clean = cleanNavisionText(name);
  if (!clean) return;
  if (!window.confirm(`Remove provider "${clean}" from the dropdown list? Existing vehicle history will stay on the vehicle.`)) return;
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared provider list right now. Check your connection and try again.'); return; }
  const record = loadSubletProviderRecords(true).find(row => row.name === clean);
  if (!record) { window.alert(`"${clean}" was not found.`); return; }
  service.setSubletProviderActive(record.id, record.version, false).then(result => {
    if (!result.ok) { window.alert(result.error || 'Could not remove provider.'); return; }
    renderAdminLists();
    renderKpis();
  });
}

function renderHostingSecurityWarning() {
  const host = $('#hosting-security-warning');
  if (!host) return;
  const publicStaticHost = /(^|\.)github\.io$/i.test(String(window.location?.hostname || ''));
  const bundledVehicleCount = Array.isArray(window.VEHICLE_TRACKING_DATA?.vehicles) ? window.VEHICLE_TRACKING_DATA.vehicles.length : 0;
  host.hidden = !(publicStaticHost && bundledVehicleCount > 0);
}

function addSalespersonFromAdminInput() {
  const initialsInput = $('#salesperson-initials-input');
  const nameInput = $('#salesperson-name-input');
  const emailInput = $('#salesperson-email-input');
  const record = normalizeSalespersonRecord({ initials: initialsInput?.value, name: nameInput?.value, email: emailInput?.value });
  if (!record) {
    window.alert('Enter salesperson initials, name and a valid email address.');
    return;
  }
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared salesperson list right now. Check your connection and try again.'); return; }
  const finish = () => {
    if (initialsInput) initialsInput.value = '';
    if (nameInput) nameInput.value = '';
    if (emailInput) emailInput.value = '';
    renderAdminLists();
    renderDetail();
  };
  const existing = loadSalespersonRecords(true).find(row => (row.code || '').toUpperCase() === record.initials);
  const request = existing
    ? service.editSalesperson(existing.id, existing.version, { name: record.name, email: record.email, code: record.initials })
    : service.addSalesperson(record.name, record.email, record.initials);
  request.then(result => {
    if (!result.ok) {
      window.alert(result.error === 'duplicate_code' ? `Salesperson code "${record.initials}" is already in use.` : (result.error || 'Could not save salesperson.'));
      return;
    }
    finish();
  });
}

function removeSalespersonFromAdminList(initials = '') {
  const clean = cleanNavisionText(initials).toUpperCase();
  const record = loadSalespersonRecords(true).find(row => (row.code || '').toUpperCase() === clean);
  if (!record) return;
  if (!window.confirm(`Remove ${record.code} - ${record.name} from the salesperson dropdown? Existing vehicles keep their saved initials.`)) return;
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared salesperson list right now. Check your connection and try again.'); return; }
  service.setSalespersonActive(record.id, record.version, false).then(result => {
    if (!result.ok) { window.alert(result.error || 'Could not remove salesperson.'); return; }
    renderAdminLists();
  });
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
  const salesHost = $('#salesperson-list-admin');
  if (salesHost) {
    const salespersons = loadSalespersons();
    salesHost.innerHTML = salespersons.length
      ? salespersons.map(record => `<span class="admin-chip salesperson-admin-chip"><strong>${escapeHtml(record.initials)} — ${escapeHtml(record.name)}</strong><small>${escapeHtml(record.email)}</small><button type="button" class="text-button" data-remove-salesperson="${escapeHtml(record.initials)}">Remove</button></span>`).join('')
      : '<div class="empty-state compact-empty"><strong>No salespersons yet</strong><span>Add initials, name and email to populate vehicle dropdowns.</span></div>';
  }
  $$('[data-remove-mechanic]').forEach(button => button.addEventListener('click', () => removeMechanicFromAdminList(button.dataset.removeMechanic)));
  $$('[data-remove-provider]').forEach(button => button.addEventListener('click', () => removeSubletProviderFromAdminList(button.dataset.removeProvider)));
  $$('[data-remove-salesperson]').forEach(button => button.addEventListener('click', () => removeSalespersonFromAdminList(button.dataset.removeSalesperson)));
  renderBackupStatusPanel();
}

// Admin-visible backup status widget (Setup screen). Reads only from
// backup_runs / restore_test_runs, both RLS-gated to administrator role
// at the database layer -- a viewer/controller loading this same page
// simply gets zero rows back (see migration 017), so this frontend
// visibility check is a convenience, not the security boundary.
function backupStatusSharedModeReady() {
  return typeof window !== 'undefined'
    && typeof workshopSharedModeEnabled === 'function'
    && workshopSharedModeEnabled(window.PDC_SUPABASE_CONFIG)
    && !!window.PDC_SUPABASE
    && typeof window.PDC_SUPABASE.from === 'function'
    && window.PDC_AUTH_CONTEXT
    && window.PDC_AUTH_CONTEXT.role === 'administrator';
}

function formatBackupBytes(bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = Number(bytes);
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

async function renderBackupStatusPanel() {
  const panel = $('#backup-status-panel');
  const host = $('#backup-status-content');
  if (!panel || !host) return;

  if (!backupStatusSharedModeReady()) {
    panel.hidden = true;
    return;
  }
  panel.hidden = false;
  host.innerHTML = '<div class="empty-state compact-empty"><strong>Loading backup status…</strong></div>';

  try {
    const client = window.PDC_SUPABASE;
    if (!client || typeof client.from !== 'function') {
      throw new Error('Supabase client is not ready yet');
    }
    const environment = (window.PDC_SUPABASE_CONFIG && window.PDC_SUPABASE_CONFIG.projectRef === PRODUCTION_SUPABASE_PROJECT_REF) ? 'production' : 'staging';

    const { data: runs, error: runsError } = await client
      .from('backup_runs')
      .select('id,status,started_at,finished_at,file_size_bytes,file_path,error_message,kind,triggered_by')
      .eq('environment', environment)
      .order('started_at', { ascending: false })
      .limit(20);
    if (runsError) throw runsError;

    const { data: restoreTests, error: restoreError } = await client
      .from('restore_test_runs')
      .select('id,status,started_at,finished_at,row_count_matches,target_schema')
      .eq('environment', environment)
      .order('started_at', { ascending: false })
      .limit(1);
    if (restoreError) throw restoreError;

    const lastSuccess = (runs || []).find(run => run.status === 'success');
    let consecutiveFailures = 0;
    for (const run of (runs || [])) {
      if (run.status === 'failed') consecutiveFailures += 1;
      else if (run.status === 'success') break;
    }
    const recentFailures = (runs || []).filter(run => run.status === 'failed').slice(0, 5);
    const lastRestoreTest = (restoreTests || [])[0];

    let nextScheduledLabel = '—';
    if (lastSuccess && lastSuccess.started_at) {
      const nextDate = new Date(new Date(lastSuccess.started_at).getTime() + 3 * 60 * 60 * 1000);
      nextScheduledLabel = nextDate.toLocaleString();
    }

    const alertBanner = consecutiveFailures >= 3
      ? `<div class="hosting-security-warning" role="alert"><strong>Backup alert</strong><span>${consecutiveFailures} consecutive backup failures for ${escapeHtml(environment)}. An administrator must investigate.</span></div>`
      : '';

    host.innerHTML = `
      ${alertBanner}
      <div class="visibility-grid backup-status-grid">
        <div class="visibility-card"><span class="muted-label">Environment</span><strong>${escapeHtml(environment)}</strong></div>
        <div class="visibility-card"><span class="muted-label">Last successful backup</span><strong>${lastSuccess ? new Date(lastSuccess.started_at).toLocaleString() : 'Never'}</strong></div>
        <div class="visibility-card"><span class="muted-label">Next scheduled backup</span><strong>${escapeHtml(nextScheduledLabel)}</strong></div>
        <div class="visibility-card"><span class="muted-label">Last backup size</span><strong>${lastSuccess ? formatBackupBytes(lastSuccess.file_size_bytes) : '—'}</strong></div>
        <div class="visibility-card"><span class="muted-label">Backup location</span><strong>Encrypted file store (server-side, outside the live database)</strong></div>
        <div class="visibility-card"><span class="muted-label">Last restore test</span><strong>${lastRestoreTest ? `${new Date(lastRestoreTest.started_at).toLocaleString()} — ${lastRestoreTest.row_count_matches ? 'passed' : 'FAILED'}` : 'Never run'}</strong></div>
        <div class="visibility-card"><span class="muted-label">Recent failures</span><strong>${consecutiveFailures} consecutive</strong></div>
        <div class="visibility-card"><span class="muted-label">Retention policy</span><strong>7d / 30d daily / 12w weekly / 12mo monthly</strong></div>
      </div>
      ${recentFailures.length ? `<div class="parts-help-strip"><strong>Recent failure detail:</strong><span>${recentFailures.map(run => `${escapeHtml(new Date(run.started_at).toLocaleString())} — ${escapeHtml(run.error_message || 'unknown error')}`).join(' · ')}</span></div>` : ''}
    `;
  } catch (error) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>Could not load backup status</strong><span>${escapeHtml(error && error.message ? error.message : String(error))}</span></div>`;
  }
}

// ---------------------------------------------------------------------
// Administrator-only User Management screen. Reads directly from
// pdc_user_roles (RLS lets an administrator see every row; anyone else
// sees only their own row at the database layer -- see migration 018),
// and every action button below calls the corresponding protected RPC
// (admin_approve_user / admin_reject_registration / admin_change_role /
// admin_disable_user / admin_restore_user), each of which independently
// re-verifies the caller is an active administrator server-side. This
// frontend code is a convenience UI, not the security boundary.
// ---------------------------------------------------------------------
const USER_MANAGEMENT_STATE = { tab: 'pending', rows: [], realtimeChannel: null };

function userManagementSharedModeReady() {
  return backupStatusSharedModeReady(); // same gating: shared mode + signed-in administrator
}

async function loadUserManagementRows() {
  const client = window.PDC_SUPABASE;
  const { data, error } = await client
    .from('pdc_user_roles')
    .select('id,email,full_name,display_name,role,active,account_status,registered_at,approved_by,approved_at,rejected_at,rejection_reason,disabled_at,disabled_reason,restored_at,last_sign_in_at,created_at')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

function userManagementRowActionsHtml(row) {
  const email = escapeHtml(row.email);
  if (row.account_status === 'pending') {
    return `
      <select class="um-role-select" data-um-role-for="${email}">
        <option value="viewer">viewer</option>
        <option value="operator">controller</option>
        <option value="administrator">administrator</option>
      </select>
      <button class="small-button primary" data-um-approve="${email}">Approve</button>
      <button class="small-button text-button" data-um-reject="${email}">Reject</button>
    `;
  }
  if (row.account_status === 'approved') {
    return `
      <select class="um-role-select" data-um-role-for="${email}">
        <option value="viewer" ${row.role === 'viewer' ? 'selected' : ''}>viewer</option>
        <option value="operator" ${row.role === 'operator' ? 'selected' : ''}>controller</option>
        <option value="administrator" ${row.role === 'administrator' ? 'selected' : ''}>administrator</option>
      </select>
      <button class="small-button" data-um-change-role="${email}">Change role</button>
      <button class="small-button text-button" data-um-disable="${email}">Disable</button>
    `;
  }
  if (row.account_status === 'disabled') {
    return `<button class="small-button primary" data-um-restore="${email}">Restore</button>`;
  }
  return '<span class="muted-label">No actions</span>';
}

function userManagementRowHtml(row) {
  const roleLabel = row.role === 'operator' ? 'controller' : (row.role || '—');
  return `<tr>
    <td>${escapeHtml(row.full_name || row.display_name || '—')}</td>
    <td>${escapeHtml(row.email)}</td>
    <td>${escapeHtml(roleLabel)}</td>
    <td>${row.registered_at ? escapeHtml(new Date(row.registered_at).toLocaleString()) : (row.created_at ? escapeHtml(new Date(row.created_at).toLocaleString()) : '—')}</td>
    <td>${row.approved_at ? escapeHtml(new Date(row.approved_at).toLocaleString()) : '—'}</td>
    <td>${row.last_sign_in_at ? escapeHtml(new Date(row.last_sign_in_at).toLocaleString()) : 'Never'}</td>
    <td>${row.account_status === 'disabled' ? `${row.disabled_at ? escapeHtml(new Date(row.disabled_at).toLocaleDateString()) : ''} ${row.disabled_reason ? '— ' + escapeHtml(row.disabled_reason) : ''}` : '—'}</td>
    <td class="um-actions-cell">${userManagementRowActionsHtml(row)}</td>
  </tr>`;
}

async function renderUserManagementScreen() {
  const navItem = $('#nav-user-management');
  const host = $('#user-management-content');
  if (!host) return;

  if (!userManagementSharedModeReady()) {
    if (navItem) navItem.hidden = true;
    host.innerHTML = '<div class="empty-state compact-empty"><strong>Administrator access required</strong></div>';
    return;
  }
  if (navItem) navItem.hidden = false;
  host.innerHTML = '<div class="empty-state compact-empty"><strong>Loading…</strong></div>';

  subscribeUserManagementRealtime();

  try {
    USER_MANAGEMENT_STATE.rows = await loadUserManagementRows();
  } catch (error) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>Could not load users</strong><span>${escapeHtml(error && error.message ? error.message : String(error))}</span></div>`;
    return;
  }

  const filtered = USER_MANAGEMENT_STATE.rows.filter(row => row.account_status === USER_MANAGEMENT_STATE.tab);
  if (!filtered.length) {
    host.innerHTML = `<div class="empty-state compact-empty"><strong>No ${escapeHtml(USER_MANAGEMENT_STATE.tab)} accounts</strong></div>`;
    return;
  }

  host.innerHTML = `<div class="parts-table-wrap"><table class="data-table compact-table">
    <thead><tr><th>Full name</th><th>Email</th><th>Role</th><th>Registered</th><th>Approved</th><th>Last login</th><th>Disabled</th><th>Actions</th></tr></thead>
    <tbody>${filtered.map(userManagementRowHtml).join('')}</tbody>
  </table></div>`;

  wireUserManagementActions();
}

function subscribeUserManagementRealtime() {
  const client = window.PDC_SUPABASE;
  if (!client || typeof client.channel !== 'function') return;
  if (USER_MANAGEMENT_STATE.realtimeChannel) return; // already subscribed for this session
  const channel = client
    .channel('pdc_user_roles_admin_view')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pdc_user_roles' }, () => {
      // Any account-status/role change (approve/reject/change-role/
      // disable/restore) re-renders the currently active tab live,
      // without requiring a manual "Refresh" click -- proven via a real
      // two-browser test: one browser makes the change, a second,
      // already-open browser on this screen picks it up automatically.
      if (document.getElementById('user-management')?.classList.contains('active')) {
        renderUserManagementScreen();
      }
    })
    .subscribe();
  USER_MANAGEMENT_STATE.realtimeChannel = channel;
}

async function userManagementCallRpc(rpcName, params, successMessage) {
  const client = window.PDC_SUPABASE;
  const { error } = await client.rpc(rpcName, params);
  if (error) {
    alert(`Action failed: ${error.message || error}`);
    return false;
  }
  if (successMessage) {
    // Non-blocking confirmation; the row list below refreshes immediately
    // afterward regardless, so this is just an audible/visible cue.
  }
  await renderUserManagementScreen();
  return true;
}

function wireUserManagementActions() {
  $$('[data-um-approve]').forEach(button => button.addEventListener('click', async () => {
    const email = button.dataset.umApprove;
    const select = $(`[data-um-role-for="${email}"]`);
    const role = select ? select.value : 'viewer';
    await userManagementCallRpc('admin_approve_user', { p_target_email: email, p_role: role }, 'Approved');
  }));
  $$('[data-um-reject]').forEach(button => button.addEventListener('click', async () => {
    const email = button.dataset.umReject;
    const reason = window.prompt(`Reason for rejecting ${email} (optional):`, '') || null;
    await userManagementCallRpc('admin_reject_registration', { p_target_email: email, p_reason: reason }, 'Rejected');
  }));
  $$('[data-um-change-role]').forEach(button => button.addEventListener('click', async () => {
    const email = button.dataset.umChangeRole;
    const select = $(`[data-um-role-for="${email}"]`);
    const role = select ? select.value : null;
    if (!role) return;
    await userManagementCallRpc('admin_change_role', { p_target_email: email, p_role: role }, 'Role changed');
  }));
  $$('[data-um-disable]').forEach(button => button.addEventListener('click', async () => {
    const email = button.dataset.umDisable;
    const reason = window.prompt(`Reason for disabling ${email} (optional):`, '') || null;
    if (!window.confirm(`Disable access for ${email}? They will immediately lose all operational access.`)) return;
    await userManagementCallRpc('admin_disable_user', { p_target_email: email, p_reason: reason }, 'Disabled');
  }));
  $$('[data-um-restore]').forEach(button => button.addEventListener('click', async () => {
    const email = button.dataset.umRestore;
    await userManagementCallRpc('admin_restore_user', { p_target_email: email, p_reason: 'Restored via User Management screen' }, 'Restored');
  }));
}

function showView(view) {
  const requestedView = view || 'dashboard';
  const departmentStage = PRODUCTION_DEPARTMENT_VIEWS[requestedView] || '';
  const nextView = departmentStage ? 'department' : requestedView;
  releaseHeavyViewDom(app.currentView, nextView);
  if (requestedView !== 'workflow') {
    app.activePmbBayStage = '';
    app.pmbSubFilter = '';
    document.body.classList.remove('pmb-station-mode');
    const pmbWorkflowHost = $('#pmb-workflow-board');
    if (pmbWorkflowHost) pmbWorkflowHost.classList.remove('station-only');
  }
  if (departmentStage) app.activeProductionDepartment = departmentStage;
  app.currentView = nextView;
  if (document.body?.dataset) document.body.dataset.currentView = requestedView;
  $$('.view').forEach(el => el.classList.toggle('active', el.id === requestedView || (departmentStage && el.id === 'department')));
  $$('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.view === requestedView));
  const departmentDef = departmentStage ? PRODUCTION_FLOW_DEFS.find(def => def.key === departmentStage) : null;
  const titleMap = {
    dashboard: 'Vehicle Locations',
    workflow: 'Control Board',
    workshop: 'Workshop Planner',
    pipeline: 'Vehicle Pipeline',
    visibility: 'Operational Visibility',
    tv: 'PDC TV Board',
    schedule: 'Production',
    parts: 'Parts',
    emailreview: 'AI Intake Review',
    sublet: 'Sublet',
    rft: 'RFT',
    completed: 'Completed vehicles',
    deleted: 'Deleted vehicles',
    backend: 'Back End Data',
    lists: 'Setup',
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
  scheduleWorkflowFloatingHeaderUpdate();
}

const HEAVY_VIEW_HOSTS = Object.freeze({
  dashboard: ['incoming-main-board', 'kpi-grid', 'vehicle-table'],
  workflow: ['workflow-board'],
  workshop: ['workshop-planner-root'],
  parts: ['parts-home-content', 'parts-summary-grid'],
  emailreview: ['email-intake-review-content'],
  sublet: ['sublet-home-content'],
  rft: ['rft-home-content', 'rft-summary-grid'],
  completed: ['completed-vehicles-content'],
  deleted: ['deleted-vehicles-content'],
  backend: ['backend-data-content'],
  department: ['department-content'],
  schedule: ['schedule-content'],
  pipeline: ['kanban'],
  visibility: ['visibility-content'],
  tv: ['tv-content'],
});

function releaseHeavyViewDom(previousView = '', nextView = '') {
  if (!previousView || previousView === nextView) return;
  (HEAVY_VIEW_HOSTS[previousView] || []).forEach(id => {
    const host = document.getElementById(id);
    if (host) host.replaceChildren();
  });
}


function populateFilters() {
  const visibleRows = pdcSheetVehicles();
  const statuses = sortToyotaStatuses([...new Set(visibleRows.map(v => v.toyotaStatus).filter(Boolean))]);
  const consultants = [...new Set(visibleRows.map(v => salesPersonInitials(consultantName(v))).filter(Boolean))].sort();
  const productionMonths = sortProductionMonths([...new Set(visibleRows.map(v => productionMonthLabel(v.prodMth || v.productionMonth || '')).filter(Boolean))]);
  const sources = [...new Set(visibleRows.map(v => v.source).filter(Boolean))].sort();
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
  renderOperationalHealthSummary();
}

function renderAll() {
  ensureAppDataAvailable();
  updateSidebarStats();
  populateFilters();
  renderActiveView();
  updateNavisionImportButton();
}

// Bridges to the real Supabase client that pdc-auth.js already creates
// (window.PDC_SUPABASE) as part of the standard login flow. Kept as thin,
// dedicated functions (rather than reaching into window.PDC_SUPABASE
// directly from workshop-data-service.js) so the shared data service
// module has no hard dependency on pdc-auth.js's internal implementation
// details, and so a future auth provider swap only touches these two
// functions.
function getPdcSupabaseAccessToken() {
  // supabase-js v2 exposes the session via getSession() (async) but every
  // caller of getAccessToken() here is synchronous by contract (see
  // workshop-data-service.js). pdc-auth.js caches the current access
  // token on window.__pdcCachedAccessToken every time it unlocks the app
  // or reacts to an auth state change (including silent token refresh),
  // and clears it immediately on sign-out/session loss -- so this is
  // always either the live token or null, never stale beyond one tick.
  return window.PDC_AUTH_CONTEXT ? (window.__pdcCachedAccessToken || null) : null;
}

function createPdcSupabaseRealtimeSubscription(config, handlers) {
  const client = window.PDC_SUPABASE;
  if (!client || typeof client.channel !== 'function') return { unsubscribe: () => {} };
  const channel = client
    .channel('workshop-revision')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'workshop_revision' }, payload => {
      if (typeof handlers?.onChange === 'function') handlers.onChange(payload);
    })
    .subscribe(status => {
      if (typeof handlers?.onStatus === 'function') handlers.onStatus(status);
    });
  return { unsubscribe: () => client.removeChannel(channel) };
}

// Generic per-table realtime subscription, used by
// workshop-reference-data-service.js (Stage 2A) for mechanics/salespeople/
// sublet-providers/bays/workshop-settings, none of which share the single
// fixed 'workshop-revision' channel the booking-data path above uses.
// Each table gets its own named channel so unrelated resources never
// interfere with each other's subscribe/reconnect lifecycle.
function createPdcSupabaseTableRealtimeSubscription(tableName, handlers) {
  const client = window.PDC_SUPABASE;
  if (!client || typeof client.channel !== 'function') return { unsubscribe: () => {} };
  const channel = client
    .channel(`pdc-reference-${tableName}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: tableName }, payload => {
      if (typeof handlers?.onChange === 'function') handlers.onChange(payload);
    })
    .subscribe(status => {
      if (typeof handlers?.onStatus === 'function') handlers.onStatus(status);
    });
  return { unsubscribe: () => client.removeChannel(channel) };
}

// Constructs the Stage 2A shared workshop reference/configuration data
// service exactly once per page load. Unlike
// initWorkshopSharedServicesIfEnabled() above (which stays behind an
// explicit opt-in flag while the legacy local-plan booking fallback is
// retired in a later stage), this service is NOT gated by a feature flag
// -- per the Stage 2A instruction, Supabase must be authoritative for
// mechanics/salespeople/sublet-providers/bays/workshop-configuration
// immediately. It still requires a real, authenticated session
// (getPdcSupabaseAccessToken()) before it will report anything other than
// a clear "not authenticated"/offline state -- there is no synchronous
// path back to localStorage.
function initWorkshopReferenceDataServiceIfAvailable() {
  if (window.__workshopReferenceDataService) return window.__workshopReferenceDataService;
  if (!window.PDC_SUPABASE_CONFIG || typeof createWorkshopReferenceDataService !== 'function' || typeof createWorkshopReferenceSupabaseClient !== 'function') return null;

  const client = createWorkshopReferenceSupabaseClient(window.PDC_SUPABASE_CONFIG);
  const service = createWorkshopReferenceDataService({
    config: window.PDC_SUPABASE_CONFIG,
    client,
    getAccessToken: () => (typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null),
    subscribeRealtime: (tableName, handlers) => createPdcSupabaseTableRealtimeSubscription(tableName, handlers),
    onStateChange: () => {
      // Independent-review remediation (finding 1): pull the latest
      // validated workshop configuration into the planner's live
      // scheduling constants BEFORE re-rendering, so a settings change
      // made in another browser (or the periodic reconciliation
      // backstop) actually changes planner behaviour here, not only
      // the raw cached JSON.
      if (typeof workshopSyncConfigFromSharedSettings === 'function') {
        try { workshopSyncConfigFromSharedSettings(); } catch (_err) { /* keep last-known-good config */ }
      }
      renderAdminLists();
      renderKpis();
      if (app.currentView === 'workshop' && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
    }
  });
  window.__workshopReferenceDataService = service;
  return service;
}

// Lazily constructs the shared workshop data service + realtime manager
// exactly once per page load. No-op (and leaves window.__workshopDataService
// undefined) unless window.PDC_SUPABASE_CONFIG.workshop.sharedData is
// explicitly true -- see workshop-data-service.js for the fail-closed
// opt-in contract. Kept in app.js (not workshop-planner.js) because it owns
// the actual Supabase client / auth token / realtime subscription
// wiring, which are already app.js concerns for the rest of the site.
function initWorkshopSharedServicesIfEnabled() {
  if (typeof workshopSharedModeEnabled !== 'function' || !workshopSharedModeEnabled(window.PDC_SUPABASE_CONFIG)) return;

  if (!window.__workshopDataService) {
    if (typeof createWorkshopDataService !== 'function' || typeof createWorkshopSupabaseClient !== 'function') return;

    const client = createWorkshopSupabaseClient(window.PDC_SUPABASE_CONFIG);
    const dataService = createWorkshopDataService({
      config: window.PDC_SUPABASE_CONFIG,
      client,
      getAccessToken: () => (typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null),
      getRole: () => (typeof window.PDC_AUTH_CONTEXT !== 'undefined' ? window.PDC_AUTH_CONTEXT?.role : null),
      onStateChange: () => {
        if (app.currentView === 'workshop' && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
        if (app.currentView === 'emailreview' && typeof renderAiBoardAdvisor === 'function') renderAiBoardAdvisor();
      },
      onSnapshot: () => {
        if (app.currentView === 'workshop' && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
        if (app.currentView === 'emailreview' && typeof renderAiBoardAdvisor === 'function') renderAiBoardAdvisor();
      }
    });
    window.__workshopDataService = dataService;

    dataService.loadSnapshot('initial');
  }

  // Deliberately re-checked every call, same reasoning as the shared-
  // actions block below: workshop-realtime.js is also lazy-loaded
  // on-demand when the user first opens the Workshop Planner, which can
  // happen after the data service already exists (e.g. pdc-auth-ready
  // firing on login before the planner has ever been opened).
  if (!window.__workshopRealtimeManager && typeof createWorkshopRealtimeManager === 'function' && typeof createPdcSupabaseRealtimeSubscription === 'function') {
    window.__workshopRealtimeManager = createWorkshopRealtimeManager({
      dataService: window.__workshopDataService,
      subscribe: (handlers) => createPdcSupabaseRealtimeSubscription(window.PDC_SUPABASE_CONFIG, handlers),
      onStatusChange: () => {
        if (app.currentView === 'workshop' && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
      }
    });
    window.__workshopRealtimeManager.start();
    window.addEventListener('online', () => window.__workshopRealtimeManager.forceReconnect());
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') window.__workshopDataService.onVisibilityReturn();
    });
  }

  // Deliberately re-checked every call (not just inside the "first init"
  // branch above): workshop-shared-actions.js is lazy-loaded on-demand
  // when the user first opens the Workshop Planner view, which can easily
  // happen *after* the data service was already constructed here (e.g.
  // from the pdc-auth-ready listener firing on login before the user has
  // ever visited the planner). Without this re-check, window.
  // __workshopSharedActions would stay null forever once the data service
  // already existed.
  if (!window.__workshopSharedActions && typeof buildWorkshopSharedActions === 'function') {
    window.__workshopSharedActions = buildWorkshopSharedActions(window.__workshopDataService);
  }
}

// Lazily constructs the vehicle-lifecycle shared actions bridge (QC
// complete -> RFT -> Collected) exactly once per page load. Independent of
// initWorkshopSharedServicesIfEnabled(): a site can enable shared workshop
// scheduling without enabling shared QC/RFT/Collected, or vice versa.
// Fails closed -- if not enabled/loaded, window.__vehicleLifecycleActions
// stays undefined and configured shared lifecycle actions fail closed.
function initVehicleLifecycleSharedActionsIfEnabled() {
  if (typeof vehicleLifecycleSharedModeEnabled !== 'function' || !vehicleLifecycleSharedModeEnabled(window.PDC_SUPABASE_CONFIG)) return;
  if (typeof createWorkshopSupabaseClient !== 'function' || typeof buildVehicleLifecycleSharedActions !== 'function') return;
  const client = createWorkshopSupabaseClient(window.PDC_SUPABASE_CONFIG);
  if (!window.__vehicleLifecycleActions) {
    window.__vehicleLifecycleActions = buildVehicleLifecycleSharedActions(
      client,
      () => (typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null),
    );
  }
  window.__vehicleLifecycleResolverDiagnostics = window.__vehicleLifecycleResolverDiagnostics || [];
  const rollback = typeof vehicleLifecycleResolverRollbackEnabled === 'function'
    && vehicleLifecycleResolverRollbackEnabled(window.PDC_SUPABASE_CONFIG);
  if (rollback) {
    window.__vehicleLifecycleResolverDiagnostics.push({
      type: 'rollback_mode',
      at: new Date().toISOString(),
      mode: 'staging_direct_read',
    });
    console.warn('PDC C1 lifecycle resolver: explicit staging rollback direct-read mode is active.');
    return;
  }
  if (!window.__vehicleLifecycleIdentityResolver && typeof createVehicleLifecycleIdentityResolver === 'function') {
    window.__vehicleLifecycleIdentityResolver = createVehicleLifecycleIdentityResolver({
      client,
      getAccessToken: () => (typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null),
      subscribe: handlers => createPdcSupabaseTableRealtimeSubscription('vehicle_lifecycle_resolver_revision', handlers),
      onDiagnostic: item => {
        window.__vehicleLifecycleResolverDiagnostics.push(item);
        if (window.__vehicleLifecycleResolverDiagnostics.length > 100) window.__vehicleLifecycleResolverDiagnostics.shift();
      },
      onRefresh: item => {
        window.dispatchEvent?.(new CustomEvent('pdc-vehicle-lifecycle-resolver-refresh', { detail: item }));
      },
    });
    window.__vehicleLifecycleIdentityResolver.start();
  }
  if (!window.__vehicleLifecycleResolverReconcileListenersInstalled) {
    window.addEventListener('online', () => {
      window.__vehicleLifecycleIdentityResolver?.reconcile?.('online_return');
    });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        window.__vehicleLifecycleIdentityResolver?.reconcile?.('visibility_return');
      }
    });
    window.__vehicleLifecycleResolverReconcileListenersInstalled = true;
  }
  window.__vehicleLifecycleIdentityResolver?.reconcile?.('auth_ready');
}

function vehicleLifecycleSharedModeActive() {
  return typeof window !== 'undefined'
    && typeof vehicleLifecycleSharedModeEnabled === 'function'
    && vehicleLifecycleSharedModeEnabled(window.PDC_SUPABASE_CONFIG);
}

// pdc-auth.js dispatches 'pdc-auth-ready' every time a session unlocks the
// app (initial load, token refresh redirect, re-login after sign-out).
// Re-run the shared-services init so a user who logs in while already on
// the Workshop Planner view (or returns after a session refresh) gets the
// data service without needing to navigate away and back.
window.addEventListener?.('pdc-auth-ready', () => {
  if (typeof initWorkshopSharedServicesIfEnabled === 'function') initWorkshopSharedServicesIfEnabled();
  if (typeof initVehicleLifecycleSharedActionsIfEnabled === 'function') initVehicleLifecycleSharedActionsIfEnabled();
  if (typeof refreshWorkshopReferenceData === 'function') refreshWorkshopReferenceData();
  const navItem = document.getElementById('nav-user-management');
  if (navItem) navItem.hidden = !(typeof backupStatusSharedModeReady === 'function' && backupStatusSharedModeReady());
  if (app.currentView === 'emailreview' && typeof renderAiBoardAdvisor === 'function') renderAiBoardAdvisor();
});

// Independent-review remediation, finding #5 / critical blocker #5:
// pdc-auth.js now subscribes every signed-in browser to its own
// pdc_user_roles row and fires 'pdc-auth-locked' the instant that row
// shows the account is no longer approved (disabled, rejected, or
// reverted to pending) -- without waiting for a reload or sign-out.
// This handler is the operational-data side of that fix: it tears down
// every shared realtime subscription and drops in-memory shared-mode
// state so a disabled user's already-open tab cannot continue showing
// (or silently re-deriving UI from) previously-loaded operational data.
window.addEventListener?.('pdc-auth-locked', () => {
  const advisorHost = document.getElementById('ai-board-advisor-content');
  if (advisorHost) advisorHost.replaceChildren();
  try {
    if (window.__workshopRealtimeManager && typeof window.__workshopRealtimeManager.stop === 'function') {
      window.__workshopRealtimeManager.stop();
    }
  } catch (_err) { /* best-effort teardown */ }
  try {
    if (window.__workshopDataService && typeof window.__workshopDataService.destroy === 'function') {
      window.__workshopDataService.destroy();
    }
  } catch (_err) { /* best-effort teardown */ }
  try {
    if (window.__vehicleLifecycleIdentityResolver && typeof window.__vehicleLifecycleIdentityResolver.stop === 'function') {
      window.__vehicleLifecycleIdentityResolver.stop();
    }
    if (window.__vehicleLifecycleRealtimeManager && typeof window.__vehicleLifecycleRealtimeManager.stop === 'function') {
      window.__vehicleLifecycleRealtimeManager.stop();
    }
  } catch (_err) { /* best-effort teardown */ }
  try {
    if (USER_MANAGEMENT_STATE && USER_MANAGEMENT_STATE.realtimeChannel && window.PDC_SUPABASE && typeof window.PDC_SUPABASE.removeChannel === 'function') {
      window.PDC_SUPABASE.removeChannel(USER_MANAGEMENT_STATE.realtimeChannel);
      USER_MANAGEMENT_STATE.realtimeChannel = null;
      USER_MANAGEMENT_STATE.rows = [];
    }
  } catch (_err) { /* best-effort teardown */ }
  try {
    // Stage 2A: tear down every workshop reference/configuration data
    // realtime subscription (technicians/salespeople/sublet-providers/
    // bays) on lockout too, exactly like every other shared-data service
    // above -- otherwise a disabled user's already-open tab could keep
    // receiving mechanic/salesperson/provider/bay change events after
    // being locked out of everything else.
    if (window.__workshopReferenceDataService && typeof window.__workshopReferenceDataService.unsubscribeAll === 'function') {
      window.__workshopReferenceDataService.unsubscribeAll();
    }
  } catch (_err) { /* best-effort teardown */ }
  window.__workshopRealtimeManager = null;
  window.__workshopDataService = null;
  window.__workshopSharedActions = null;
  window.__vehicleLifecycleIdentityResolver = null;
  window.__vehicleLifecycleResolverDiagnostics = [];
  window.__vehicleLifecycleActions = null;
  window.__workshopReferenceDataService = null;
  const navItem = document.getElementById('nav-user-management');
  if (navItem) navItem.hidden = true;
});

function renderWorkshopPlannerWhenReady() {
  if (typeof renderWorkshopPlanner === 'function') {
    initWorkshopSharedServicesIfEnabled();
    renderWorkshopPlanner();
    return;
  }
  const root = $('#workshop-planner-root');
  if (root) root.innerHTML = '<div class="empty-state"><strong>Loading Workshop Planner</strong><span>Preparing scheduling controls…</span></div>';
  // Load the shared-data service + realtime manager modules first. Both
  // stay completely inert (no snapshot fetch, no subscription, no writes)
  // unless window.PDC_SUPABASE_CONFIG.workshop.sharedData is explicitly set
  // to true; the planner UI/runtime is not modified by this load and
  // continues to operate exactly as before.
  loadExternalScript(`workshop-data-service.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-data-service-script')
    .then(() => loadExternalScript(`workshop-realtime.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-realtime-script'))
    .then(() => loadExternalScript(`workshop-shared-actions.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-shared-actions-script'))
    .catch(() => { /* non-fatal: shared mode simply stays unavailable */ })
    .then(() => loadExternalScript(`workshop-planner.js?v=${encodeURIComponent(APP_VERSION)}`, 'workshop-planner-script'))
    .then(() => {
      initWorkshopSharedServicesIfEnabled();
      if (app.currentView === 'workshop' && typeof renderWorkshopPlanner === 'function') renderWorkshopPlanner();
    })
    .catch(error => {
      if (!root) return;
      root.innerHTML = '<div class="empty-state"><strong>Workshop Planner could not load</strong><span></span></div>';
      const message = root.querySelector('span');
      if (message) message.textContent = error.message || String(error);
    });
}

function renderActiveView() {
  ensureAppDataAvailable();
  const view = app.currentView || 'dashboard';
  const previousRenderJsonCache = activeRenderJsonCache;
  activeRenderJsonCache = new Map();
  try {
    switch (view) {
    case 'dashboard':
      renderKpis();
      renderIncomingDashboardBoard();
      break;
    case 'workflow':
      renderWorkflowBoard();
      break;
    case 'workshop':
      renderWorkshopPlannerWhenReady();
      break;
    case 'parts':
      renderPartsHome();
      break;
    case 'emailreview':
      renderEmailIntakeReview();
      break;
    case 'sublet':
      renderSubletHome();
      break;
    case 'rft':
      renderRftHome();
      break;
    case 'completed':
      renderCompletedVehicles();
      break;
    case 'deleted':
      renderDeletedVehicles();
      break;
    case 'backend':
      renderBackEndData();
      break;
    case 'lists':
      renderAdminLists();
      break;
    case 'user-management':
      renderUserManagementScreen();
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
  } finally {
    activeRenderJsonCache = previousRenderJsonCache;
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
  const rows = pdcSheetVehicles().filter(vehicleHasBatchNumber);
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
    .forEach(vehicle => {
      const eta = partsWorstEtaLabel(vehicle);
      issueRows.push({
        vehicle,
        label: 'Parts stoppage',
        severity: 'danger',
        detail: `${partsStoppageReason(vehicle)} · ${eta ? `Parts ETA ${eta}` : 'Parts ETA pending'}`,
      });
    });
  pmbRows
    .filter(isPdcBlocked)
    .forEach(vehicle => issueRows.push({ vehicle, label: 'PMB stoppage', severity: 'danger', detail: pdcBlockReason(vehicle) }));
  const seen = new Set();
  return issueRows.filter(row => {
    const key = `${vehicleKey(row.vehicle)}:${row.label}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((a, b) => {
    if (a.label === 'Parts stoppage' && b.label === 'Parts stoppage') {
      const etaDiff = partsWorstEtaSortValue(a.vehicle) - partsWorstEtaSortValue(b.vehicle);
      if (etaDiff) return etaDiff;
    }
    return 0;
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
      <small>${escapeHtml(unit)}</small>
      <em>${escapeHtml(row.detail || stage || 'Open vehicle for details')}</em>
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
  host.innerHTML = `<details class="fix-first-list"><summary>Show stoppages</summary><div class="fix-first-list-body">${fixFirstRowsHtml(rows)}</div></details>`;
  bindFixFirstRows(host);
}

function workflowBoardStats() {
  const pmbRows = workflowVehiclesForStep('pmb');
  const pmbBlocked = pmbRows.filter(isPdcBlocked).length;
  const gateIssues = vehiclesWithRftGateIssues(pmbRows).length;
  const unallocated = pmbRows.filter(vehicle => !inferredPmbStage(vehicle)).length;
  const stageSteps = [
    { value: '', filter: PMB_STAGE_UNASSIGNED_FILTER, number: '0', title: 'Unallocated', action: 'Open list' },
    ...PMB_STAGE_DEFS.map((def, index) => ({ value: def.value, filter: def.value, number: String(index + 1), title: def.label, action: def.value === 'SUBLET' ? 'Provider queue' : 'Open bays' }))
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
        rule: step.value === 'SUBLET' ? 'Assign provider and track outsourced work in the SUBLET row.' : step.value ? 'Click to open the bay board for this PMB category.' : 'Assign these vehicles to the correct PMB category first.',
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

function pmbVehicleNeedsStationWork(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  const def = pmbStageJobDef(normalizedStage);
  if (statusCategory(vehicle) !== 'pmb' || !def || !PMB_BAY_STATION_SEQUENCE.includes(normalizedStage)) return false;
  const incomplete = !pdcJobComplete(vehicle, def);
  if (!incomplete) return false;
  return pdcJobRequired(vehicle, def) || normalizePmbStage(inferredPmbStage(vehicle)) === normalizedStage;
}

function pmbVehiclesNeedingStationWork(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  return app.data
    .filter(vehicle => pmbVehicleNeedsStationWork(vehicle, normalizedStage))
    .sort((a, b) => String(displayStockNumber(a) || vehicleKey(a) || '').localeCompare(String(displayStockNumber(b) || vehicleKey(b) || '')));
}

// C1 resolves a legacy lifecycle consumer through the narrow deterministic RPC.
// The old direct table query remains available only through the explicit,
// staging-project-only rollback flag. Neither path selects a first row when
// multiple candidates exist.
function recordVehicleLifecycleResolverDiagnostic(item = {}) {
  window.__vehicleLifecycleResolverDiagnostics = window.__vehicleLifecycleResolverDiagnostics || [];
  window.__vehicleLifecycleResolverDiagnostics.push({ at: new Date().toISOString(), ...item });
  if (window.__vehicleLifecycleResolverDiagnostics.length > 100) window.__vehicleLifecycleResolverDiagnostics.shift();
}

async function vehicleLifecycleLegacyDirectRef(vehicle = {}) {
  const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null;
  const identity = String(displayStockNumber(vehicle) || vehicle.order || '').trim();
  if (!identity) return { outcome: 'invalid_input' };
  const url = `${window.PDC_SUPABASE_CONFIG.url}/rest/v1/vehicles?select=id,version,qc_completed_at,lifecycle_state,deleted_at&or=(stock_number.eq.${encodeURIComponent(identity)},permanent_vehicle_id.eq.${encodeURIComponent(identity)})&limit=2`;
  recordVehicleLifecycleResolverDiagnostic({ type: 'rollback_direct_read', identityFields: ['legacy_identity'] });
  try {
    const res = await fetch(url, {
      headers: {
        apikey: window.PDC_SUPABASE_CONFIG.publishableKey,
        Authorization: `Bearer ${token || window.PDC_SUPABASE_CONFIG.publishableKey}`,
      },
    });
    if (res.status === 401 || res.status === 403) return { outcome: 'unauthorized' };
    if (!res.ok) return { outcome: 'service_unavailable' };
    const rows = await res.json();
    if (!Array.isArray(rows)) return { outcome: 'service_unavailable' };
    if (rows.length === 0) return { outcome: 'not_found' };
    if (rows.length > 1) return { outcome: 'ambiguous' };
    const row = rows[0];
    return {
      outcome: 'resolved',
      vehicleId: row.id,
      version: row.version,
      qcCompletedAt: row.qc_completed_at,
      lifecycleState: row.lifecycle_state,
      isArchived: row.deleted_at != null,
      resolverRevision: null,
      matchedBy: ['legacy_direct_read'],
    };
  } catch (_err) {
    return { outcome: 'service_unavailable' };
  }
}

async function vehicleLifecycleSharedRef(vehicle = {}) {
  if (!vehicleLifecycleSharedModeActive()) return { outcome: 'service_unavailable' };
  const rollback = typeof vehicleLifecycleResolverRollbackEnabled === 'function'
    && vehicleLifecycleResolverRollbackEnabled(window.PDC_SUPABASE_CONFIG);
  if (rollback) return vehicleLifecycleLegacyDirectRef(vehicle);
  if (!window.__vehicleLifecycleIdentityResolver || typeof buildVehicleLifecycleIdentityInput !== 'function') {
    return { outcome: 'service_unavailable' };
  }
  const input = buildVehicleLifecycleIdentityInput(vehicle);
  const result = await window.__vehicleLifecycleIdentityResolver.resolve(input, { reason: 'lifecycle_consumer' });
  recordVehicleLifecycleResolverDiagnostic({
    type: 'consumer_resolution',
    outcome: result && result.outcome,
    inputFields: Object.keys(input).sort(),
  });
  return result || { outcome: 'service_unavailable' };
}

function describeVehicleLifecycleResolutionOutcome(result = {}) {
  const messages = {
    not_found: 'This vehicle was not found in the shared database.',
    ambiguous: 'More than one shared vehicle matches this identity. No change was made; an administrator must resolve the duplicate.',
    conflict: 'The supplied vehicle identifiers point to different shared vehicles. No change was made.',
    invalid_input: 'This vehicle does not have a valid shared identity. No change was made.',
    unauthorized: 'Your account is not authorized to resolve shared vehicle identity.',
    service_unavailable: 'Shared vehicle identity is temporarily unavailable. No change was made.',
  };
  return messages[result && result.outcome] || 'This vehicle could not be resolved safely. No change was made.';
}

function vehicleReadyForQualityControl(vehicle = {}) {
  if (statusCategory(vehicle) !== 'pmb' || vehicle.pdcQcComplete === true || isPdcBlocked(vehicle) || isActivePartsStoppage(vehicle)) return false;
  if (pdcRequirementDefinitions(vehicle).some(job => !pdcJobComplete(vehicle, job))) return false;
  return !normalizePmbStage(inferredPmbStage(vehicle));
}

function qualityControlVehicleHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const stock = displayStockNumber(vehicle) || key || 'No stock';
  return `<button class="control-board-work-vehicle control-board-qc-vehicle" type="button" data-qc-complete="${escapeHtml(key)}" aria-label="Complete QC for ${escapeHtml(stock)}">
    <span class="control-board-work-identity">${vehicleIdentityStackHtml(vehicle)}</span>
    <span class="control-board-work-main"><strong>${escapeHtml(displayVehicle(vehicle) || 'Vehicle not listed')}</strong></span>
    <span class="control-board-work-location"><b>Now</b><span>Unallocated</span></span>
    <span class="control-board-work-age"><b>PMB</b><span>${escapeHtml(pmbAgeLabel(vehicle))}</span></span>
    <span class="badge warning">Complete QC</span>
  </button>`;
}

async function completeVehicleQualityControl(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return false;
  if (!vehicleReadyForQualityControl(vehicle)) {
    window.alert('QC is available only when all required work is complete and the vehicle is back in PMB Unallocated.');
    return false;
  }
  const operator = cleanNavisionText(window.PDC_AUTH_CONTEXT?.displayName || window.PDC_AUTH_CONTEXT?.email || localStorage.getItem(OPERATOR_NAME_KEY) || '');
  const role = cleanNavisionText(window.PDC_AUTH_CONTEXT?.role || localStorage.getItem(OPERATOR_ROLE_KEY) || '');
  if (!operator || !role) {
    window.alert('Set your operator name and role before completing QC. No vehicle was changed.');
    return false;
  }
  const label = vehicleIdentityTitle(vehicle) || displayStockNumber(vehicle) || 'this vehicle';
  if (!window.confirm(`Mark QC complete for ${label}?\n\nThis will unlock Transfer to RFT while the vehicle remains in Unallocated.`)) return false;

  if (vehicleLifecycleSharedModeActive()) {
    const ref = await vehicleLifecycleSharedRef(vehicle);
    if (!ref || ref.outcome !== 'resolved') {
      window.alert(describeVehicleLifecycleResolutionOutcome(ref));
      return false;
    }
    if (ref.isArchived) {
      window.alert('This vehicle is archived in shared data, so QC was not completed. No change was made.');
      return false;
    }
    if (ref.qcCompletedAt) {
      window.alert('QC has already been completed for this vehicle.');
      renderAll();
      return false;
    }
    const result = await window.__vehicleLifecycleActions.qcCompleteVehicle({
      vehicleId: ref.vehicleId,
      expectedVersion: ref.version,
      workItemKey: 'QC',
      completedSummary: pdcCompletedJobsText(vehicle) || null,
    });
    if (!result || result.ok !== true) {
      const message = typeof describeVehicleLifecycleActionError === 'function'
        ? describeVehicleLifecycleActionError(result && result.error)
        : 'The QC sign-off could not be saved.';
      window.alert(message);
      if (typeof window.__workshopDataService !== 'undefined' && window.__workshopDataService) window.__workshopDataService.loadSnapshot('qc_complete_rejected');
      renderAll();
      return false;
    }
    if (result.notification_has_recipient === false) {
      window.alert('QC complete was saved, but no salesperson email is on file for this vehicle. The "ready for transport" notification could not be queued for sending. Please set the correct salesperson and use Retry from the notification outbox.');
    }
    renderAll();
    return true;
  }

  const now = nowIsoString();
  try {
    runStorageTransaction('Complete vehicle QC', [EDITS_KEY, AUDIT_LOG_KEY], () => {
      recordVehicleAudit(vehicle, 'Vehicle QC completed', { by: operator, role, location: 'PMB Unallocated' });
      if (!saveVehicleEdits(vehicleKey(vehicle), { pdcQcComplete: true, pdcQcCompleteAt: now, pdcQcCompleteBy: operator })) {
        throw new Error('The QC sign-off could not be saved.');
      }
    });
  } catch (error) {
    window.alert(error.message || String(error));
    return false;
  }
  renderAll();
  return true;
}

function controlBoardStationVehicleHtml(vehicle = {}, stage = '') {
  const key = vehicleKey(vehicle);
  const stock = displayStockNumber(vehicle) || key || 'No stock';
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const currentStage = normalizePmbStage(inferredPmbStage(vehicle));
  const currentBay = currentStage ? pmbBayNumber(vehicle, currentStage) : '';
  const inBay = Boolean(currentStage && currentBay);
  const currentLabel = inBay ? `${pmbStageLabel(currentStage)} · Bay ${currentBay}` : currentStage ? `${pmbStageLabel(currentStage)} queue` : 'Unallocated';
  const blocked = isPdcBlocked(vehicle) || isActivePartsStoppage(vehicle);
  return `<button class="control-board-work-vehicle${blocked ? ' is-blocked' : ''}${inBay ? ' is-in-bay' : ''}" type="button" data-open-stock="${escapeHtml(key)}" aria-label="Open ${escapeHtml(stock)} for ${escapeHtml(pmbStageLabel(stage))} work">
    <span class="control-board-work-identity">${vehicleIdentityStackHtml(vehicle)}</span>
    <span class="control-board-work-main"><strong>${escapeHtml(unit)}</strong></span>
    <span class="control-board-work-location"><b>Now</b><span>${escapeHtml(currentLabel)}</span></span>
    <span class="control-board-work-age"><b>PMB</b><span>${escapeHtml(pmbAgeLabel(vehicle))}</span></span>
    ${blocked ? '<span class="badge danger">Stopped</span>' : inBay ? `<span class="badge info">IN ${escapeHtml(pmbStageLabel(currentStage).toUpperCase())} BAY ${escapeHtml(currentBay)}</span>` : '<span class="badge warning">Work required</span>'}
  </button>`;
}

function openWorkshopPlannerForStage(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!PMB_BAY_STATION_SEQUENCE.includes(normalizedStage)) return;
  if (typeof workshopState === 'function') {
    const state = workshopState();
    state.stage = normalizedStage;
    state.selectedPlanId = '';
    app.pendingWorkshopStage = '';
  } else {
    app.pendingWorkshopStage = normalizedStage;
  }
  showView('workshop');
}

function renderWorkflowBoard() {
  const host = $('#workflow-board');
  if (!host) return;
  document.body.classList.remove('pmb-station-mode');
  app.activePmbBayStage = '';
  const search = String($('#workflow-search')?.value || app.workflowSearch || '').trim().toLowerCase();
  app.workflowSearch = search;
  const stationRows = PMB_BAY_STATION_SEQUENCE.map(stage => {
    const allVehicles = pmbVehiclesNeedingStationWork(stage);
    const vehicles = search ? allVehicles.filter(vehicle => incomingSearchText(vehicle, 'pmb').includes(search)) : allVehicles;
    return { stage, allVehicles, vehicles };
  });
  const totalPmb = workflowVehiclesForStep('pmb').length;
  const qualityControlVehicles = workflowVehiclesForStep('pmb').filter(vehicleReadyForQualityControl);
  const outstandingVehicleKeys = new Set([...stationRows.flatMap(row => row.allVehicles.map(vehicleKey)), ...qualityControlVehicles.map(vehicleKey)]);
  const stationHtml = stationRows.map(({ stage, allVehicles, vehicles }) => {
    const label = pmbStageLabel(stage);
    const countLabel = search ? `${vehicles.length}/${allVehicles.length}` : `${allVehicles.length}`;
    const rows = vehicles.map(vehicle => controlBoardStationVehicleHtml(vehicle, stage)).join('')
      || `<div class="pmb-empty-drop">${escapeHtml(search ? 'No matching vehicles need this work.' : `No PMB vehicles currently need ${label} work.`)}</div>`;
    const openAttr = app.workflowBucketsCollapsed ? '' : ' open';
    return `<details class="incoming-bucket workflow-stage-bucket control-board-station-row pmb-branch-${escapeHtml(stage.toLowerCase())}"${openAttr}>
      <summary class="incoming-bucket-title workflow-bucket-title">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(countLabel)}</strong>
        <small>PMB vehicles with ${escapeHtml(label)} required and not completed</small>
        <span class="workflow-bucket-actions"><button class="small-button primary" type="button" data-open-workshop-stage="${escapeHtml(stage)}">Open Bays</button></span>
      </summary>
      <div class="control-board-work-list">${rows}</div>
    </details>`;
  }).join('');
  const qualityControlRows = qualityControlVehicles.filter(vehicle => !search || incomingSearchText(vehicle, 'pmb').includes(search));
  const qualityControlHtml = `<details class="incoming-bucket workflow-stage-bucket control-board-station-row control-board-qc-row" open>
    <summary class="incoming-bucket-title workflow-bucket-title">
      <span>QC</span>
      <strong>${escapeHtml(search ? `${qualityControlRows.length}/${qualityControlVehicles.length}` : qualityControlVehicles.length)}</strong>
      <small>All required work complete · final quality check before RFT</small>
      <span class="workflow-bucket-actions"><span class="badge neutral">Final gate</span></span>
    </summary>
    <div class="control-board-work-list">${qualityControlRows.map(qualityControlVehicleHtml).join('') || '<div class="pmb-empty-drop">No vehicles are waiting for QC.</div>'}</div>
  </details>`;
  host.innerHTML = `
    <div class="branch-header workflow-pmb-header">
      <div><strong>PMB work overview</strong><span>Vehicles appear in every station row where required work is still outstanding. Open Bays goes directly to that station in Workshop Planner.</span></div>
      <div class="branch-header-actions"><span class="badge neutral">${outstandingVehicleKeys.size} needing work · ${totalPmb} at PMB</span></div>
    </div>
    <div class="workflow-collapsible-board control-board-station-list">${stationHtml}${qualityControlHtml}</div>
  `;
  $$('[data-open-workshop-stage]', host).forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openWorkshopPlannerForStage(button.dataset.openWorkshopStage);
  }));
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  $$('[data-qc-complete]', host).forEach(button => button.addEventListener('click', () => completeVehicleQualityControl(button.dataset.qcComplete)));
  updateCollapseToggleButtons();
  scheduleWorkflowFloatingHeaderUpdate();
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
    vehicle.purchaseOrderNumber, vehicle.purchaseOrderReference, vehicle.purchaseOrderDeliverTo, vehicle.purchaseOrderIssuedBy,
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

function setCollapseToggleLabel(button, expanded) {
  if (button) button.textContent = expanded ? 'Collapse all rows' : 'Expand all rows';
}

function detailsWithin(host) {
  if (!host) return [];
  const directSelectors = [
    ':scope > details',
    ':scope > .incoming-vertical-list > details',
    ':scope > .rft-compact-list > details',
    ':scope > .deleted-compact-list > details',
    ':scope > .workflow-collapsible-board > details',
  ];
  const rows = directSelectors.flatMap(selector => {
    try { return $$(selector, host); } catch (error) { return []; }
  });
  const unique = [...new Set(rows)];
  return unique.length ? unique : $$('details', host).filter(row => row.parentElement === host);
}

function setDetailsWithin(host, open) {
  detailsWithin(host).forEach(row => { row.open = open; });
}

function toggleDetailsWithin(host, button) {
  const rows = detailsWithin(host);
  if (!rows.length) return;
  const shouldExpand = !rows.some(row => row.open);
  rows.forEach(row => { row.open = shouldExpand; });
  setCollapseToggleLabel(button, shouldExpand);
}

function updateCollapseToggleButtons() {
  [
    ['#incoming-main-board', '#incoming-collapse-all'],
    ['#rft-home-content', '#rft-collapse-all'],
    ['#completed-vehicles-content', '#completed-collapse-all'],
    ['#deleted-vehicles-content', '#deleted-collapse-all'],
  ].forEach(([hostSelector, buttonSelector]) => {
    const rows = detailsWithin($(hostSelector));
    if (rows.length) setCollapseToggleLabel($(buttonSelector), rows.some(row => row.open));
  });
  const workflowRows = detailsWithin($('#workflow-board'));
  if (workflowRows.length) setCollapseToggleLabel($('#workflow-collapse-all'), workflowRows.some(row => row.open));
}

function toggleMainScreenRows() {
  toggleDetailsWithin($('#incoming-main-board'), $('#incoming-collapse-all'));
}

function toggleRftRows() {
  toggleDetailsWithin($('#rft-home-content'), $('#rft-collapse-all'));
}

function toggleCompletedRows() {
  toggleDetailsWithin($('#completed-vehicles-content'), $('#completed-collapse-all'));
}

function toggleDeletedRows() {
  toggleDetailsWithin($('#deleted-vehicles-content'), $('#deleted-collapse-all'));
}

function toggleWorkflowRows() {
  const host = $('#workflow-board');
  const rows = detailsWithin(host);
  const shouldExpand = !rows.some(row => row.open);
  app.workflowBucketsCollapsed = !shouldExpand;
  if (normalizePmbStage(app.activePmbBayStage) || app.pmbSubFilter) {
    app.activePmbBayStage = '';
    app.pmbSubFilter = '';
    document.body.classList.remove('pmb-station-mode');
    showView('workflow');
  }
  renderWorkflowBoard();
  setDetailsWithin($('#workflow-board'), shouldExpand);
  setCollapseToggleLabel($('#workflow-collapse-all'), shouldExpand);
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

function revealSingleVehicleSearchResult(host, vehicles = [], query = '', scope = 'vehicle-search') {
  const needle = String(query || '').trim().toLowerCase();
  if (!host || !needle || vehicles.length !== 1) {
    if (app.singleSearchFocus) app.singleSearchFocus[scope] = '';
    return;
  }
  const key = vehicleKey(vehicles[0]);
  const matchingRows = $$('[data-incoming-row]', host).filter(row => row.dataset.incomingRow === key);
  if (!matchingRows.length) return;
  matchingRows.forEach(row => {
    row.open = true;
    row.classList.add('vehicle-search-highlight');
    const bucket = row.closest?.('details.incoming-bucket');
    if (bucket) bucket.open = true;
  });
  const primary = matchingRows.find(row => !row.closest?.('.workflow-fix-first-bucket, .incoming-priority-stoppages')) || matchingRows[0];
  const token = `${needle}|${key}`;
  if (app.singleSearchFocus?.[scope] === token) return;
  app.singleSearchFocus[scope] = token;
  window.requestAnimationFrame?.(() => primary.scrollIntoView?.({ block: 'center', behavior: 'smooth' }));
}

function focusVehiclesAfterWorkImport(keys = []) {
  const focusKeys = [...new Set((Array.isArray(keys) ? keys : [keys]).map(value => String(value || '').trim()).filter(Boolean))];
  if (!focusKeys.length) return;

  ['#incoming-search', '#incoming-status-filter', '#incoming-bucket-filter', '#incoming-rep-filter'].forEach(selector => {
    const input = $(selector);
    if (input) input.value = '';
  });
  $$('input[name="incoming-work-filter"]').forEach(input => { input.checked = false; });
  app.quickFilter = 'incoming';
  app.singleSearchFocus.incoming = '';
  showView('dashboard');

  window.requestAnimationFrame?.(() => {
    const host = $('#incoming-main-board');
    if (!host) return;
    $$('details', host).forEach(details => { details.open = false; });
    const focusedRows = [];
    focusKeys.forEach(key => {
      const rows = $$('[data-incoming-row]', host).filter(row => row.dataset.incomingRow === key);
      const primary = rows.find(row => !row.closest?.('.incoming-priority-stoppages')) || rows[0];
      if (!primary) return;
      primary.open = true;
      primary.classList.add('vehicle-search-highlight', 'vehicle-import-highlight');
      const bucket = primary.closest?.('details.incoming-bucket');
      if (bucket) bucket.open = true;
      focusedRows.push(primary);
    });
    updateCollapseToggleButtons();
    focusedRows[0]?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
  });
}

function clearWorkflowSearch() {
  app.workflowSearch = '';
  const input = $('#workflow-search');
  if (input) input.value = '';
  renderWorkflowBoard();
}

function workflowFilterValues() {
  const previous = app.workflowFilters || {};
  const filters = {
    search: workflowSearchValue(),
    sort: String(previous.sort || 'oldest').trim() || 'oldest',
    bucket: String(previous.bucket || '').trim(),
    work: String(previous.work || '').trim(),
    required: String(previous.required || '').trim(),
    completion: String(previous.completion || '').trim(),
    stoppage: String(previous.stoppage || '').trim(),
  };
  if (!filters.work) {
    filters.required = '';
    filters.completion = '';
  }
  if (filters.required === 'no') {
    filters.completion = '';
  }
  app.workflowFilters = {
    sort: filters.sort,
    bucket: filters.bucket,
    work: filters.work,
    required: filters.required,
    completion: filters.completion,
    stoppage: filters.stoppage,
  };
  return filters;
}

function workflowFiltersNarrowRows(filters = {}) {
  return Boolean(filters.search || filters.bucket || filters.work || filters.required || filters.completion || filters.stoppage);
}

function workflowColumnFiltersActive(filters = {}) {
  return Boolean(filters.bucket || filters.work || filters.required || filters.completion || filters.stoppage);
}

function workflowVehicleHasStoppage(vehicle = {}) {
  return Boolean(isPdcBlocked(vehicle) || partsDepartmentStatus(vehicle) === 'stoppage');
}

function workflowVehicleMatchesFilters(vehicle = {}, filters = {}) {
  if (filters.search && !workflowVehicleMatchesSearch(vehicle, filters.search)) return false;
  const stage = inferredPmbStage(vehicle);
  if (filters.bucket === 'UNALLOCATED' && stage) return false;
  if (filters.bucket && filters.bucket !== 'UNALLOCATED' && stage !== filters.bucket) return false;

  const workDef = filters.work ? PDC_JOB_BY_KEY.get(filters.work) : null;
  if (workDef) {
    const required = pdcJobRequired(vehicle, workDef) || pdcJobComplete(vehicle, workDef);
    const complete = pdcJobComplete(vehicle, workDef);
    if (filters.required === 'yes' && !required) return false;
    if (filters.required === 'no' && required) return false;
    if (filters.completion === 'outstanding' && !(required && !complete)) return false;
    if (filters.completion === 'complete' && !complete) return false;
  }

  const stopped = workflowVehicleHasStoppage(vehicle);
  if (filters.stoppage === 'yes' && !stopped) return false;
  if (filters.stoppage === 'no' && stopped) return false;
  return true;
}

function workflowVehicleSortTimestamp(vehicle = {}) {
  const entered = parseIsoTimestamp(pmbEnteredTimestamp(vehicle));
  if (entered) return entered.getTime();
  const kewdaleDate = parseDateAU(kewdaleEtaValue(vehicle));
  return kewdaleDate ? kewdaleDate.getTime() : null;
}

function workflowCompareVehicles(a = {}, b = {}, sort = 'oldest') {
  const textCompare = (left, right) => String(left || '').localeCompare(String(right || ''), undefined, { numeric: true, sensitivity: 'base' });
  if (sort === 'key-asc' || sort === 'key-desc') {
    const direction = sort === 'key-desc' ? -1 : 1;
    return direction * textCompare(vehicleKeyNumber(a), vehicleKeyNumber(b));
  }
  if (sort === 'stock-asc' || sort === 'stock-desc') {
    const direction = sort === 'stock-desc' ? -1 : 1;
    return direction * textCompare(displayStockNumber(a) || vehicleKey(a), displayStockNumber(b) || vehicleKey(b));
  }
  if (sort === 'customer-asc') {
    const customerDiff = textCompare(vehicleCustomerName(a), vehicleCustomerName(b));
    return customerDiff || textCompare(displayStockNumber(a) || vehicleKey(a), displayStockNumber(b) || vehicleKey(b));
  }
  if (sort === 'customer-desc') {
    const customerDiff = textCompare(vehicleCustomerName(b), vehicleCustomerName(a));
    return customerDiff || textCompare(displayStockNumber(a) || vehicleKey(a), displayStockNumber(b) || vehicleKey(b));
  }
  if (sort === 'jobcard-asc' || sort === 'jobcard-desc') {
    const direction = sort === 'jobcard-desc' ? -1 : 1;
    return direction * textCompare(vehicleJobcardNumber(a), vehicleJobcardNumber(b));
  }
  if (sort === 'vehicle-asc' || sort === 'vehicle-desc') {
    const direction = sort === 'vehicle-desc' ? -1 : 1;
    return direction * textCompare(displayVehicle(a), displayVehicle(b));
  }
  const aDate = workflowVehicleSortTimestamp(a);
  const bDate = workflowVehicleSortTimestamp(b);
  if (aDate === null && bDate !== null) return 1;
  if (aDate !== null && bDate === null) return -1;
  if (aDate !== null && bDate !== null && aDate !== bDate) return sort === 'newest' ? bDate - aDate : aDate - bDate;
  return textCompare(displayStockNumber(a) || vehicleKey(a), displayStockNumber(b) || vehicleKey(b));
}

function workflowFilterAndSortRows(rows = [], filters = {}) {
  return rows
    .filter(vehicle => workflowVehicleMatchesFilters(vehicle, filters))
    .map((vehicle, index) => ({ vehicle, index }))
    .sort((a, b) => workflowCompareVehicles(a.vehicle, b.vehicle, filters.sort || 'oldest') || a.index - b.index)
    .map(item => item.vehicle);
}

function workflowFilterSummary(filters = {}, matched = 0, total = 0) {
  const parts = [`Showing ${matched} of ${total}`];
  const sortLabels = { oldest: 'oldest first', newest: 'newest first', 'key-asc': 'key low–high', 'key-desc': 'key high–low', 'stock-asc': 'stock A–Z', 'stock-desc': 'stock Z–A', 'jobcard-asc': 'job card A–Z', 'jobcard-desc': 'job card Z–A', 'customer-asc': 'customer A–Z', 'customer-desc': 'customer Z–A', 'vehicle-asc': 'vehicle A–Z', 'vehicle-desc': 'vehicle Z–A' };
  const bucketLabels = { UNALLOCATED: 'Unallocated', TINT: 'Tint', HOIST: 'Hoist', FITTING: 'Fitting', FABRICATION: 'Fab', ELECTRICAL: 'Elec', TYRE: 'Tyre', PIT_INSPECTION: 'Pit', SUBLET: 'Sublet' };
  if (filters.search) parts.push(`search “${filters.search}”`);
  if (filters.bucket) parts.push(`bucket ${bucketLabels[filters.bucket] || filters.bucket}`);
  if (filters.work) parts.push(`work ${PDC_JOB_BY_KEY.get(filters.work)?.label || filters.work}`);
  if (filters.required) parts.push(`required ${filters.required}`);
  if (filters.completion) parts.push(filters.completion);
  if (filters.stoppage) parts.push(filters.stoppage === 'yes' ? 'stoppage only' : 'no stoppage');
  parts.push(sortLabels[filters.sort] || 'oldest first');
  return parts.join(' · ');
}

function applyWorkflowHeaderFilter(type = '', value = '', workKey = '') {
  const filters = { ...(app.workflowFilters || {}) };
  if (type === 'sort') {
    filters.sort = value || 'oldest';
  } else if (type === 'status') {
    filters.bucket = '';
    filters.stoppage = '';
    const [kind, selected] = String(value || '').split(':');
    if (kind === 'bucket') filters.bucket = selected || '';
    if (kind === 'stoppage') filters.stoppage = selected || '';
  } else if (type === 'work') {
    filters.work = value ? workKey : '';
    filters.required = value === 'yes' ? 'yes' : value === 'no' ? 'no' : '';
    filters.completion = value === 'outstanding' ? 'outstanding' : value === 'complete' ? 'complete' : '';
  }
  app.workflowFilters = filters;
  renderWorkflowBoard();
}

function clearWorkflowFilters() {
  app.workflowFilters = { sort: 'oldest', bucket: '', work: '', required: '', completion: '', stoppage: '' };
  renderWorkflowBoard();
}

let workflowFloatingHeaderFrame = 0;

function scheduleWorkflowFloatingHeaderUpdate() {
  if (workflowFloatingHeaderFrame || !window.requestAnimationFrame) return;
  workflowFloatingHeaderFrame = window.requestAnimationFrame(() => {
    workflowFloatingHeaderFrame = 0;
    updateWorkflowFloatingHeader();
  });
}

function workflowFloatingHeaderHost() {
  let floating = $('#workflow-floating-column-header');
  if (floating) return floating;
  floating = document.createElement('div');
  floating.id = 'workflow-floating-column-header';
  floating.className = 'workflow-floating-column-header';
  floating.hidden = true;
  floating.addEventListener('scroll', () => {
    const sourceList = floating.__sourceList;
    if (sourceList && Math.abs(sourceList.scrollLeft - floating.scrollLeft) > 1) sourceList.scrollLeft = floating.scrollLeft;
  }, { passive: true });
  document.body.appendChild(floating);
  return floating;
}

function updateWorkflowFloatingHeader() {
  const floating = $('#workflow-floating-column-header');
  if (document.body?.dataset?.currentView !== 'workflow' || document.body.classList.contains('pmb-station-mode')) {
    if (floating) floating.hidden = true;
    return;
  }
  const headers = $$('.workflow-production-grid-header', $('#workflow-board'));
  const top = 8;
  let source = null;
  headers.forEach(header => {
    const lane = header.closest('.workflow-stage-bucket');
    if (!lane?.open) return;
    const headerRect = header.getBoundingClientRect();
    const laneRect = lane.getBoundingClientRect();
    if (headerRect.top < top && laneRect.bottom > top + headerRect.height) source = header;
  });
  if (!source) {
    if (floating) floating.hidden = true;
    return;
  }
  const sourceList = source.closest('.workflow-vertical-list');
  if (!sourceList) return;
  const listRect = sourceList.getBoundingClientRect();
  const visibleLeft = Math.max(0, listRect.left);
  const visibleRight = Math.min(window.innerWidth, listRect.right);
  const host = workflowFloatingHeaderHost();
  if (host.__sourceHeader !== source) {
    host.innerHTML = '';
    const clone = source.cloneNode(true);
    clone.classList.add('is-floating-copy');
    clone.removeAttribute('id');
    host.appendChild(clone);
    host.__sourceHeader = source;
  }
  host.__sourceList = sourceList;
  host.style.left = `${Math.round(visibleLeft)}px`;
  host.style.width = `${Math.max(0, Math.round(visibleRight - visibleLeft))}px`;
  host.hidden = false;
  if (Math.abs(host.scrollLeft - sourceList.scrollLeft) > 1) host.scrollLeft = sourceList.scrollLeft;
}


function loadWorkflowWidthMode() {
  try {
    const value = localStorage.getItem(ROW_WIDTH_MODE_KEY) || localStorage.getItem(WORKFLOW_WIDTH_MODE_KEY) || 'standard';
    return ['compact', 'standard', 'wide', 'xl'].includes(value) ? value : 'standard';
  } catch (error) {
    return 'standard';
  }
}

function applyWorkflowWidthMode(mode = 'standard') {
  const normalized = ['compact', 'standard', 'wide', 'xl'].includes(mode) ? mode : 'standard';
  app.workflowWidthMode = normalized;
  if (document.documentElement?.dataset) {
    document.documentElement.dataset.workflowWidth = normalized;
    document.documentElement.dataset.rowWidth = normalized;
  }
  const select = $('#workflow-width-mode');
  if (select) select.value = normalized;
}

function setWorkflowWidthMode(mode = 'standard') {
  const normalized = ['compact', 'standard', 'wide', 'xl'].includes(mode) ? mode : 'standard';
  try {
    localStorage.setItem(WORKFLOW_WIDTH_MODE_KEY, normalized);
    localStorage.setItem(ROW_WIDTH_MODE_KEY, normalized);
  } catch (error) {}
  applyWorkflowWidthMode(normalized);
}

function pmbRequiredWorkLabels(vehicle = {}) {
  return pdcRequirementDefinitions(vehicle).map(item => `${item.label}${pdcJobComplete(vehicle, item) ? ' done' : ' required'}`);
}

function incomingWorkChecklistHtml(vehicle = {}, options = {}) {
  const key = vehicleKey(vehicle);
  const showStationTransfer = options.stationTransfer === true && statusCategory(vehicle) === 'pmb';
  const currentStage = normalizePmbStage(inferredPmbStage(vehicle));
  return `<div class="incoming-work-checks pdc-station-strip" aria-label="Required work stations">${pdcJobDefsPartsFirst().map(def => {
    const required = pdcJobRequired(vehicle, def);
    const complete = pdcJobComplete(vehicle, def);
    const stage = pmbStageForPdcJob(def);
    const stageJobKey = PMB_STAGE_TO_JOB_KEY[currentStage] || '';
    const blocked = def.key === 'parts'
      ? isActivePartsStoppage(vehicle)
      : Boolean(isPdcBlocked(vehicle) && stageJobKey === def.key);
    const classes = ['incoming-work-check', `pdc-station-${def.key}`];
    if (!required && !complete) classes.push('is-not-required');
    if (required) classes.push('is-required');
    if (complete) classes.push('is-complete');
    if (blocked) classes.push('is-blocked');
    if (stage && currentStage === stage) classes.push('is-current-stage');
    const state = complete ? 'complete' : blocked ? 'blocked' : required ? 'required' : 'not required';
    const marker = complete ? '✓' : blocked ? '!' : required ? '•' : '–';
    const transfer = showStationTransfer && stage
      ? `<select class="incoming-work-transfer" data-pmb-work-transfer-key="${escapeHtml(key)}" data-pmb-work-transfer-stage="${escapeHtml(stage)}" aria-label="Move ${escapeHtml(displayStockNumber(vehicle) || key)} to ${escapeHtml(pmbStageLabel(stage))}">
          <option value="">↧</option>
          <option value="${escapeHtml(stage)}">To ${escapeHtml(pmbStageLabel(stage))}</option>
        </select>`
      : '';
    return `<span class="${classes.join(' ')}" title="${escapeHtml(required || complete ? pdcJobCompletionTitle(vehicle, def) : `${pdcGridJobLabel(def)} not required`)}" aria-label="${escapeHtml(`${pdcGridJobLabel(def)} ${state}`)}">
      <span class="incoming-work-box" aria-hidden="true">${marker}</span>
      ${transfer}
      <span class="incoming-work-label">${escapeHtml(pdcGridJobLabel(def))}</span>
    </span>`;
  }).join('')}</div>`;
}

function workStatusLegendHtml() {
  return `<div class="work-status-legend" aria-label="Work status legend">
    <strong>Work status</strong>
    <span class="work-status-key status-none"><b>—</b> Not required</span>
    <span class="work-status-key status-required"><b>●</b> Required</span>
    <span class="work-status-key status-complete"><b>✓</b> Complete</span>
    <span class="work-status-key status-blocked"><b>!</b> Stoppage</span>
  </div>`;
}

function incomingVehicleDetailRow(vehicle = {}, bucketKey = '', options = {}) {
  const key = vehicleKey(vehicle);
  const eta = locationAgeLabel(vehicle);
  const stock = displayStockNumber(vehicle) || vehicleKey(vehicle) || 'No stock';
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const consultant = consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || '—';
  const keyNo = vehicleKeyNumber(vehicle) || '—';
  const rego = vehicle.rego || vehicle.registration || '—';
  const vin = vehicle.vin || vehicle.VIN || vehicle.chassis || vehicle.chassisNo || '—';
  const age = pmbAgeLabel(vehicle);
  const workChecks = incomingWorkChecklistHtml(vehicle, { stationTransfer: bucketKey === 'pmb' && options.stationTransfer !== false });
  const required = pmbRequiredWorkLabels(vehicle).join(', ') || 'No PMB work flagged';
  const stage = inferredPmbStage(vehicle);
  const rowStatus = incomingGridStatusLabel(vehicle, bucketKey);
  const subletProvider = pmbBaySubletProvider(vehicle);
  const subletProviderField = bucketKey === 'pmb' && stage === 'SUBLET'
    ? `<div class="wide incoming-sublet-provider"><b>Sublet provider</b><span><select data-pmb-bay-provider-key="${escapeHtml(key)}" data-pmb-bay-provider-stage="SUBLET" aria-label="Sublet provider for ${escapeHtml(stock)}">${subletProviderOptionsHtml(subletProvider)}</select></span></div>`
    : '';
  const gateIssues = bucketKey === 'pmb' ? vehiclesWithRftGateIssues([vehicle]).flatMap(row => row.issues || []) : [];
  const primaryAction = bucketKey === 'yardhold'
    ? `<button class="primary incoming-transfer-pmb" type="button" data-yh-transfer-pmb="${escapeHtml(key)}" title="Transfer Yard Hold vehicle to PMB">To PMB</button><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`
    : bucketKey === 'pmb'
      ? `<button class="primary incoming-transfer-rft" type="button" data-transfer-rft-stock="${escapeHtml(key)}" ${gateIssues.length ? 'disabled' : ''} title="${escapeHtml(gateIssues.length ? `RFT locked: ${gateIssues.join(' | ')}` : 'Transfer PMB vehicle to RFT')}">To RFT</button><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`
      : bucketKey === 'rft'
        ? `<label class="rft-collected-check incoming-collected-check" title="Tick once the vehicle has been collected"><input type="checkbox" data-rft-collected-key="${escapeHtml(key)}" /> <span>Collected</span></label><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`
        : `<button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button>`;
  const labelAction = `<button class="small-button vehicle-label-button" type="button" data-label-vehicle="${escapeHtml(key)}" title="Print one Zebra label for ${escapeHtml(stock)}">Label</button>`;
  const deleteAction = options.showDelete ? `<button class="small-button incoming-delete-button" type="button" data-incoming-delete="${escapeHtml(key)}" title="Move this vehicle to Deleted vehicles">Delete</button>` : '';
  const identitySummary = vehicleIdentityStackHtml(vehicle, { className: 'incoming-identity' });
  const selectBox = `<label class="incoming-card-select" title="Select ${escapeHtml(stock)}"><input type="checkbox" data-select-stock="${escapeHtml(key)}" aria-label="Select ${escapeHtml(stock)}" ${app.selectedRows.has(key) ? 'checked' : ''} /><span aria-hidden="true"></span></label>`;
  const dragAttrs = options.draggable ? ` draggable="true" data-pmb-drag-key="${escapeHtml(key)}"` : '';
  const dragClass = options.draggable ? ' workflow-draggable-row' : '';
  const risk = partsEtaRisk(vehicle);
  return `
    <details class="incoming-vehicle-card pdc-production-grid-card incoming-${escapeHtml(bucketKey)}-row${dragClass} ${app.selectedRows.has(key) ? 'is-selected' : ''}${risk ? ' has-parts-risk' : ''}" data-incoming-row="${escapeHtml(key)}"${dragAttrs}>
      <summary class="incoming-vehicle-summary pdc-production-grid-row">
        ${selectBox}
        <span class="incoming-card-stock">${identitySummary}</span>
        <span class="incoming-card-main"><strong title="${escapeHtml(unit)}">${escapeHtml(unit)}</strong></span>
        <span class="incoming-card-work-wrap">${workChecks}</span>
        <span class="incoming-card-meta incoming-card-age ${escapeHtml('pmb-age-' + onSiteDaysClass(vehicle))}"><b>${bucketKey === 'pmb' ? 'PMB' : bucketKey === 'yardhold' ? 'YH' : 'ETA'}</b><span>${escapeHtml(eta)}</span></span>
        <span class="incoming-card-meta incoming-card-status"><b>Status</b><span>${partsRiskBadge(vehicle)}${vehicleDepartmentBadge(vehicle)}${escapeHtml(rowStatus)}</span></span>
        <span class="incoming-card-action">${primaryAction}${labelAction}${deleteAction}</span>
      </summary>
      <div class="incoming-vehicle-detail-grid">
        <div><b>Rego</b><span>${escapeHtml(rego)}</span></div>
        <div><b>VIN / Chassis</b><span>${escapeHtml(vin)}</span></div>
        <div><b>Sales rep</b><span>${escapeHtml(consultant)}</span></div>
        <div><b>Age</b><span>${escapeHtml(age)}</span></div>
        <div><b>Bucket</b><span>${escapeHtml(incomingBucketLabel(bucketKey))}</span></div>
        ${risk ? `<div class="wide parts-risk-detail"><b>PARTS RISK</b><span>Parts ETA ${escapeHtml(partsWorstEtaLabel(vehicle))} is later than Kewdale ETA ${escapeHtml(kewdaleEtaValue(vehicle))}</span></div>` : ''}
        ${subletProviderField}
        <div class="wide"><b>PMB work required</b><span>${escapeHtml(required)}</span></div>
      </div>
    </details>`;
}

function renderIncomingDashboardBoard() {
  const host = $('#incoming-main-board');
  if (!host) return;
  const rows = pdcSheetVehicles().filter(vehicle => incomingBucketForVehicle(vehicle) && !vehicleCollectedFromRft(vehicle));
  updateIncomingDashboardFilterOptions(rows);
  const filters = incomingDashboardFilterValues();
  updateIncomingMoreFiltersState(filters);
  const filteredRows = rows.filter(vehicle => incomingVehicleMatchesFilters(vehicle, filters));
  const summary = $('#incoming-filter-summary');
  if (summary) {
    const workCount = Array.isArray(filters.work) ? filters.work.length : (filters.work ? 1 : 0);
    const active = [filters.search && `search “${filters.search}”`, filters.status, filters.bucket && incomingBucketLabel(filters.bucket), filters.rep, workCount && `${workCount} work type${workCount === 1 ? '' : 's'}`].filter(Boolean);
    summary.textContent = `${filteredRows.length} of ${rows.length} vehicles shown${active.length ? ` · ${active.join(' · ')}` : ''}`;
  }
  const defs = [
    { key: 'rft', label: 'RFT', hint: 'Vehicles ready for transport', open: false },
    { key: 'pmb', label: 'PMB', hint: 'Vehicles currently at PMB', open: false },
    { key: 'yardhold', label: 'Yard Hold', hint: 'Yard Hold vehicles — release to PMB from here', open: false },
    { key: 'transit', label: 'In Transit', hint: 'Wharf, shipment and WA transit', open: false },
    { key: 'overseas', label: 'Overseas / Other', hint: 'All other non-RFT vehicles not yet in transit/YH/PMB', open: false },
  ];
  const priorityRows = workflowPriorityRows();
  const priorityHtml = filters.bucket ? '' : `<section class="incoming-priority-stoppages" aria-label="Parts and PMB stoppages">
    <div class="incoming-priority-stoppages-head"><strong>Stoppages / Fix First</strong><span>${priorityRows.length} active</span><small>Red priority list before RFT. Sort Parts stoppages by Parts ETA so long-delay items fall lower.</small></div>
    <details class="fix-first-list incoming-priority-list"><summary>Show stoppages</summary><div class="fix-first-list-body">${fixFirstRowsHtml(priorityRows)}</div></details>
  </section>`;
  host.innerHTML = workStatusLegendHtml() + priorityHtml + defs.map(def => {
    if (filters.bucket && filters.bucket !== def.key) return '';
    const vehicles = filteredRows.filter(vehicle => incomingBucketForVehicle(vehicle) === def.key)
      .sort((a, b) => (parseDateAU(navisionEtaForVehicle(a))?.getTime() || 9999999999999) - (parseDateAU(navisionEtaForVehicle(b))?.getTime() || 9999999999999));
    const shown = vehicles.map(vehicle => incomingVehicleDetailRow(vehicle, def.key)).join('') || '<div class="pmb-empty-drop">No vehicles match the current filters</div>';
    const identityHeader = vehicles.length ? productionGridHeaderHtml('incoming-production-grid-header') : '';
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
  bindVehicleLabelButtons(host);
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
  $$('[data-pmb-bay-provider-key]', host).forEach(select => {
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', () => updatePmbBaySubletProvider(select.dataset.pmbBayProviderKey, select.dataset.pmbBayProviderStage, select.value));
  });
  bindPmbWorkTransferSelects(host);
  bindFixFirstRows(host);
  bindRftCollectedInputs(host);
  bindIncomingCardSelection(host);
  revealSingleVehicleSearchResult(host, filteredRows, filters.search, 'incoming');
  updateInlineSelectionBars(filteredRows);
  updateCollapseToggleButtons();
}

function bindPmbWorkTransferSelects(host = document) {
  $$('[data-pmb-work-transfer-key]', host).forEach(select => {
    select.addEventListener('click', event => event.stopPropagation());
    select.addEventListener('change', event => {
      event.stopPropagation();
      const stage = select.value || select.dataset.pmbWorkTransferStage || '';
      if (!stage) return;
      void movePmbVehicleToStage(select.dataset.pmbWorkTransferKey, stage);
      select.value = '';
    });
  });
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
  ['incoming-email-selected-update', 'workflow-email-selected-update'].forEach(id => {
    const button = $(`#${id}`);
    if (!button) return;
    button.disabled = count !== 1;
    button.title = count === 1 ? 'Email the selected vehicle update to its salesperson' : 'Select exactly one vehicle to email an update';
  });
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
  setDashboardPdStatus(app.dashboardPdFiles.length ? [{ ok: true, title: `${app.dashboardPdFiles.length} PD file${app.dashboardPdFiles.length === 1 ? '' : 's'} ready`, message: 'Click Review job-card work to check the vehicle and detected work before importing.' }] : []);
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
    setDashboardPdStatus(app.dashboardPdFiles.length ? [{ ok: true, title: `${app.dashboardPdFiles.length} PD file${app.dashboardPdFiles.length === 1 ? '' : 's'} ready`, message: 'Click Review job-card work to check the vehicle and detected work before importing.' }] : []);
    updateDashboardPdImportButtons();
  });
}

function parsePdCheckFormText(text = '', filenames = []) {
  const source = `${String(text || '')}\n${(filenames || []).join('\n')}`;
  const squashed = source.replace(/\s+/g, ' ').trim();
  const stock = (squashed.match(/\bstock\s*(?:no\.?|number|#)?\s*[:#-]?\s*(\d{6,8})\b/i) || squashed.match(/\b(\d{8})\b/) || [])[1] || '';
  const order = (squashed.match(/\border\s*(?:no\.?|number|#)?\s*[:#-]?\s*(\d{4,8})\b/i) || squashed.match(/\bpd\s*document\s*(\d{4,8})\b/i) || [])[1] || '';
  const vin = (squashed.match(/\b[A-HJ-NPR-Z0-9]{17}\b/i) || [''])[0].toUpperCase();
  const jobcard = (squashed.match(/\b(?:job\s*card|jobcard|jc)\s*(?:no\.?|number|#)?\s*[:#-]?\s*([A-Z0-9-]{3,24})\b/i) || [])[1] || '';
  const customer = (source.match(/^\s*(?:customer|client)\s*[:#-]\s*(.+)$/im) || [])[1] || '';
  const vehicle = (source.match(/^\s*(?:vehicle|model|model description)\s*[:#-]\s*(.+)$/im) || [])[1] || '';
  const salesperson = (source.match(/^\s*(?:salesperson|sales person|sales rep|consultant)\s*[:#-]\s*([A-Z0-9 -]{1,40})$/im) || [])[1] || '';
  const colour = (source.match(/^\s*colou?r\s*[:#-]\s*(.+)$/im) || [])[1] || '';
  const trim = (source.match(/^\s*trim\s*[:#-]\s*(.+)$/im) || [])[1] || '';
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
  return {
    stock,
    order,
    vin,
    jobcard: cleanNavisionText(jobcard),
    customer: cleanNavisionText(customer),
    vehicle: cleanNavisionText(vehicle),
    salesperson: cleanNavisionText(salesperson),
    colour: cleanNavisionText(colour),
    trim: cleanNavisionText(trim),
    tasks: [...new Set(tasks)],
    filenames,
  };
}

function bindVehicleLabelButtons(host = document) {
  $$('[data-label-vehicle]', host).forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    void printZplForVehicleKey(button.dataset.labelVehicle || '');
  }));
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
  if (found) return promoteVehicleToPdcSheet(found, 'PD check-form upload');
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
    recordLifecycle: 'pd-check-form',
    pdcSheetVisible: true,
    pdcVisibilitySource: 'PD check-form upload',
    pdcPromotedAt: nowIsoString(),
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
    pdcRequiresBus4x4: /\bbus\s*4x4\b|\b4x4\s*bus\b|\bdepartment\s*138\b/.test(text),
    pdcRequiresTint: /tint/.test(text),
    pdcRequiresHoist: /hoist|suspension|gvm|lift|tow/.test(text),
    pdcRequiresFitting: /\bfit\b|fitment|fitting|pdi|pre.?delivery|accessor|bull ?bar|tow ?bar|canopy|tray/.test(text),
    pdcRequiresFabrication: /tray|bull ?bar|bar work|rack|tank|canopy|winch|gvm|fabricat/.test(text),
    pdcRequiresElectrical: /light|uhf|radio|12v|battery|redarc|anderson|electrical|auto.?elec|camera|power outlet|usb/.test(text),
    pdcRequiresTyre: /tyre|tire|wheel/.test(text),
  };
}

const WORK_IMPORT_DETECTION_DEFS = [
  { label: 'Tint', pattern: /\btint(?:ing)?\b|window tint/i },
  { label: 'Tray', pattern: /\btray\b|tray body|steel tray|alloy tray|aluminium tray/i },
  { label: 'Bull bar', pattern: /bull\s*bar|bullbar/i },
  { label: 'Tow bar', pattern: /tow\s*bar|towbar/i },
  { label: 'Canopy', pattern: /\bcanopy\b/i },
  { label: 'Rack', pattern: /\b(?:roof|rear|ladder)\s*rack\b/i },
  { label: 'Suspension / GVM', pattern: /\bgvm\b|suspension|lift kit|spring/i },
  { label: 'Electrical / 12V', pattern: /electrical|auto.?elec|\b12v\b|dual battery|dcdc|dc\s*dc|redarc|anderson|light bar|spotlight|\buhf\b|radio|camera|usb/i },
  { label: 'Tyres / wheels', pattern: /tyre|tire|wheel|alignment/i },
  { label: 'Winch', pattern: /\bwinch\b/i },
  { label: 'Fuel tank', pattern: /long range.*tank|fuel tank/i },
  { label: 'Pit inspection', pattern: /pit inspection|quality control|final inspection/i },
];

function detectedWorkLabelsFromTasks(tasks = []) {
  const text = (Array.isArray(tasks) ? tasks : []).map(cleanNavisionText).filter(Boolean).join(' ');
  return WORK_IMPORT_DETECTION_DEFS.filter(def => def.pattern.test(text)).map(def => def.label);
}

function workImportRequirementUpdates(parsed = {}, vehicle = {}, tasks = []) {
  const explicit = parsed.reviewRequirementUpdates;
  if (!explicit || typeof explicit !== 'object') return pdFlagsFromTasks(tasks);
  const preview = { ...vehicle };
  if (parsed.stock) preview.stock = parsed.stock;
  if (parsed.reference && !preview.batch) preview.batch = parsed.reference;
  const updates = {};
  PDC_JOB_DEFS.forEach(def => {
    const completed = pdcJobComplete(vehicle, def);
    const standardPartsGate = def.key === 'parts' && vehicleHasBatchNumber(preview);
    updates[def.requireKey] = completed || standardPartsGate || explicit[def.requireKey] === true;
  });
  return updates;
}

function workImportVehicleUpdates(parsed = {}) {
  const reviewed = parsed.reviewVehicleUpdates;
  if (!reviewed || typeof reviewed !== 'object') return {};
  const updates = {
    client: cleanNavisionText(reviewed.client),
    vehicle: cleanNavisionText(reviewed.vehicle),
    consultant: cleanNavisionText(reviewed.consultant),
    pdcJobcard: cleanNavisionText(reviewed.pdcJobcard),
    order: cleanNavisionText(reviewed.order),
    vin: normalizeVin(reviewed.vin),
    colour: cleanNavisionText(reviewed.colour),
    trim: cleanNavisionText(reviewed.trim),
  };
  updates.toyotaVehicle = updates.vehicle;
  return updates;
}

function workImportReviewPreviewVehicle(kind = 'jobcard', parsed = {}, existing = null) {
  if (existing) return existing;
  return {
    stock: parsed.stock || parsed.reference || '',
    batch: parsed.stock || parsed.reference || '',
    order: parsed.order || '',
    vin: parsed.vin || '',
    client: parsed.client || parsed.customer || (kind === 'po' ? 'Broome Toyota' : 'Customer from job card'),
    vehicle: parsed.vehicle || '',
    consultant: parsed.salesperson || '',
    pdcJobcard: parsed.jobcard || '',
    colour: parsed.colour || '',
    trim: parsed.trim || '',
    source: kind === 'po' ? 'Purchase order upload' : 'PD check-form',
  };
}

function showWorkImportReviewModal({ kind = 'jobcard', parsed = {}, filename = '', existing = null } = {}) {
  if (typeof document?.createElement !== 'function') return Promise.resolve(null);
  const sourceLabel = kind === 'po' ? 'purchase order' : 'job card / work file';
  const preview = workImportReviewPreviewVehicle(kind, parsed, existing);
  const detectedLabels = detectedWorkLabelsFromTasks(parsed.tasks || []);
  const detectedFlags = pdFlagsFromTasks(parsed.tasks || []);
  const existingRequired = new Set(PDC_JOB_DEFS.filter(def => pdcJobRequired(preview, def)).map(def => def.requireKey));
  const completedKeys = new Set(PDC_JOB_DEFS.filter(def => pdcJobComplete(preview, def)).map(def => def.requireKey));
  const standardPartsGate = vehicleHasBatchNumber(preview);
  const identity = displayStockNumber(preview) || preview.order || preview.vin || 'Identity needs review';
  const workChecks = PDC_JOB_DEFS.map(def => {
    const detected = detectedFlags[def.requireKey] === true;
    const completed = completedKeys.has(def.requireKey);
    const required = existingRequired.has(def.requireKey) || completed || (def.key === 'parts' && standardPartsGate);
    const locked = completed || (def.key === 'parts' && standardPartsGate);
    const stateNote = completed ? 'Completed' : def.key === 'parts' && standardPartsGate ? 'Standard stock gate' : detected ? 'Detected in file' : 'Select if required';
    return `<label class="work-import-check ${detected ? 'is-detected' : ''} ${required ? 'is-selected' : ''} ${locked ? 'is-locked' : ''}">
      <input type="checkbox" data-import-work-key="${escapeHtml(def.key)}" data-import-require-key="${escapeHtml(def.requireKey)}" ${required ? 'checked' : ''} ${locked ? 'disabled' : ''} />
      <span><b>${escapeHtml(def.short)}</b><strong>${escapeHtml(def.label)}</strong><small>${escapeHtml(stateNote)}</small></span>
    </label>`;
  }).join('');
  const taskDetails = (parsed.tasks || []).map(task => `<li>${escapeHtml(task)}</li>`).join('');
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay work-import-review-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'work-import-review-title');
    overlay.innerHTML = `
      <section class="modal-card work-import-review-card">
        <button class="modal-close" type="button" data-work-import-cancel aria-label="Cancel import">×</button>
        <div class="panel-header work-import-review-heading">
          <div>
            <span class="eyebrow">Review before importing</span>
            <h2 id="work-import-review-title">${kind === 'po' ? 'Purchase order' : 'Job card'} vehicle card</h2>
            <p>No changes have been saved yet. Check the vehicle and choose exactly what work is required.</p>
          </div>
          <span class="badge ${existing ? 'neutral' : 'warning'}">${existing ? 'Matched vehicle' : 'New vehicle'}</span>
        </div>
        <form class="work-import-review-form">
          <div class="work-import-vehicle-card">
            <div class="work-import-vehicle-identity"><span>${escapeHtml(kind === 'po' ? parsed.purchaseOrderNumber || 'PO' : parsed.jobcard || 'Job card')}</span><strong>${escapeHtml(identity)}</strong><small>${escapeHtml(filename || (parsed.filenames || []).join(', ') || sourceLabel)}</small></div>
            <div class="form-row four-col work-import-fields">
              <label><span>Stock number</span><input name="stock" value="${escapeHtml(parsed.stock || preview.stock || '')}" ${existing ? 'readonly' : ''} placeholder="Stock #" /></label>
              <label><span>Toyota order</span><input name="order" value="${escapeHtml(parsed.order || preview.order || '')}" placeholder="Order #" /></label>
              <label><span>Job card</span><input name="pdcJobcard" value="${escapeHtml(parsed.jobcard || vehicleJobcardNumber(preview) || '')}" placeholder="Job card #" /></label>
              <label><span>Salesperson</span><select name="consultant">${salespersonOptionsHtml(parsed.salesperson || consultantName(preview))}</select></label>
            </div>
            <div class="form-row two-col work-import-fields">
              <label><span>Customer</span><input name="client" value="${escapeHtml(parsed.customer || parsed.client || preview.client || preview.toyotaCustomer || '')}" required placeholder="Customer name" /></label>
              <label><span>Vehicle</span><input name="vehicle" value="${escapeHtml(parsed.vehicle || preview.vehicle || preview.toyotaVehicle || '')}" required placeholder="Vehicle model / grade" /></label>
            </div>
            <div class="form-row three-col work-import-fields">
              <label><span>VIN</span><input name="vin" value="${escapeHtml(parsed.vin || preview.vin || '')}" maxlength="17" placeholder="VIN if supplied" /></label>
              <label><span>Colour</span><input name="colour" value="${escapeHtml(parsed.colour || preview.colour || '')}" /></label>
              <label><span>Trim</span><input name="trim" value="${escapeHtml(parsed.trim || preview.trim || '')}" /></label>
            </div>
          </div>
          <div class="work-import-detection-card ${detectedLabels.length ? 'has-detections' : 'no-detections'}">
            <div>
              <span class="eyebrow">Detected work</span>
              <strong>${detectedLabels.length ? `We detected: ${escapeHtml(detectedLabels.join(', '))}` : 'No work areas were confidently detected'}</strong>
              <p>${detectedLabels.length ? 'Would you like us to tick the matching work areas automatically? You can still amend every selection below.' : 'Please select the required work areas manually below.'}</p>
            </div>
            ${detectedLabels.length ? `<div class="work-import-detection-actions"><button class="primary" type="button" data-work-import-use-detected>Yes — tick detected work</button><button class="secondary" type="button" data-work-import-manual>No — select manually</button></div>` : ''}
          </div>
          <fieldset class="work-import-requirements">
            <legend>Required work for this vehicle</legend>
            <div class="work-import-check-grid">${workChecks}</div>
          </fieldset>
          ${taskDetails ? `<details class="work-import-task-details"><summary>View ${parsed.tasks.length} detected line item${parsed.tasks.length === 1 ? '' : 's'}</summary><ul>${taskDetails}</ul></details>` : ''}
          <div class="edit-actions work-import-review-actions">
            <button class="primary" type="submit">Confirm and import vehicle</button>
            <button class="secondary" type="button" data-work-import-cancel>Cancel — save nothing</button>
          </div>
        </form>
      </section>`;
    const form = overlay.querySelector('form');
    const syncCheckStyles = () => overlay.querySelectorAll('[data-import-work-key]').forEach(input => input.closest('.work-import-check')?.classList.toggle('is-selected', input.checked));
    const finish = result => {
      document.removeEventListener('keydown', onKeydown);
      overlay.remove();
      const anotherOpenModal = [...document.querySelectorAll('.modal-overlay')].some(modal => modal.hidden === false);
      if (!anotherOpenModal) document.body.classList.remove('modal-open');
      resolve(result);
    };
    const onKeydown = event => { if (event.key === 'Escape') finish(null); };
    overlay.querySelectorAll('[data-work-import-cancel]').forEach(button => button.addEventListener('click', () => finish(null)));
    overlay.addEventListener('click', event => { if (event.target === overlay) finish(null); });
    overlay.querySelectorAll('[data-import-work-key]').forEach(input => input.addEventListener('change', syncCheckStyles));
    overlay.querySelector('[data-work-import-use-detected]')?.addEventListener('click', () => {
      PDC_JOB_DEFS.forEach(def => {
        if (detectedFlags[def.requireKey] !== true) return;
        const input = overlay.querySelector(`[data-import-work-key="${def.key}"]`);
        if (input && !input.disabled) input.checked = true;
      });
      overlay.querySelector('[data-work-import-use-detected]')?.classList.add('is-active');
      overlay.querySelector('[data-work-import-manual]')?.classList.remove('is-active');
      syncCheckStyles();
    });
    overlay.querySelector('[data-work-import-manual]')?.addEventListener('click', () => {
      PDC_JOB_DEFS.forEach(def => {
        const input = overlay.querySelector(`[data-import-work-key="${def.key}"]`);
        if (input && !input.disabled && detectedFlags[def.requireKey] === true && !existingRequired.has(def.requireKey)) input.checked = false;
      });
      overlay.querySelector('[data-work-import-manual]')?.classList.add('is-active');
      overlay.querySelector('[data-work-import-use-detected]')?.classList.remove('is-active');
      syncCheckStyles();
    });
    form?.addEventListener('submit', event => {
      event.preventDefault();
      if (!form.reportValidity()) return;
      const values = new FormData(form);
      const stock = cleanNavisionText(values.get('stock'));
      const order = cleanNavisionText(values.get('order'));
      const vin = normalizeVin(values.get('vin'));
      if (!stock && !order && !vin) {
        window.alert('Enter a stock number, Toyota order or VIN before importing this vehicle.');
        return;
      }
      const requirementUpdates = {};
      PDC_JOB_DEFS.forEach(def => {
        const input = overlay.querySelector(`[data-import-work-key="${def.key}"]`);
        requirementUpdates[def.requireKey] = Boolean(input?.checked || completedKeys.has(def.requireKey) || (def.key === 'parts' && standardPartsGate));
      });
      const reviewVehicleUpdates = {
        client: values.get('client'),
        vehicle: values.get('vehicle'),
        consultant: values.get('consultant'),
        pdcJobcard: values.get('pdcJobcard'),
        order,
        vin,
        colour: values.get('colour'),
        trim: values.get('trim'),
      };
      finish({
        ...parsed,
        stock,
        order,
        vin,
        customer: cleanNavisionText(values.get('client')),
        client: cleanNavisionText(values.get('client')),
        vehicle: cleanNavisionText(values.get('vehicle')),
        salesperson: cleanNavisionText(values.get('consultant')),
        jobcard: cleanNavisionText(values.get('pdcJobcard')),
        colour: cleanNavisionText(values.get('colour')),
        trim: cleanNavisionText(values.get('trim')),
        reviewRequirementUpdates: requirementUpdates,
        reviewVehicleUpdates,
      });
    });
    document.addEventListener('keydown', onKeydown);
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    syncCheckStyles();
    const firstControl = overlay.querySelector('[data-work-import-use-detected]') || overlay.querySelector('input');
    firstControl?.focus();
  });
}

function updateIncomingMoreFiltersState(filters = incomingDashboardFilterValues()) {
  const workCount = Array.isArray(filters.work) ? filters.work.length : (filters.work ? 1 : 0);
  const activeCount = (filters.rep ? 1 : 0) + workCount;
  const details = $('#incoming-more-filters');
  const label = details ? $('[data-incoming-more-filter-label]', details) : null;
  if (label) label.textContent = activeCount ? `More filters (${activeCount} active)` : 'More filters';
  details?.classList.toggle('has-active-filters', activeCount > 0);
}

function applyPdCheckFormImport(parsed = {}) {
  return runStorageTransaction('PD / job-card import', trackerTransactionKeys(), () => applyPdCheckFormImportUnsafe(parsed));
}

function applyPdCheckFormImportUnsafe(parsed = {}) {
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
  const updates = {
    ...workImportRequirementUpdates(parsed, vehicle, combinedTasks),
    ...workImportVehicleUpdates(parsed),
  };
  updates.buildPoRaised = Boolean(combinedTasks.length);
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
  for (const item of texts) {
    const parsed = parsePdCheckFormText(item.text, item.filenames);
    try {
      const reviewed = await showWorkImportReviewModal({
        kind: 'jobcard',
        parsed,
        filename: item.filenames.join(', '),
        existing: findVehicleForPd(parsed),
      });
      if (!reviewed) {
        results.push({ ok: false, cancelled: true, title: parsed.stock || parsed.order || parsed.vin || item.filenames.join(', '), message: 'Import cancelled. No vehicle data was changed.' });
        continue;
      }
      const applied = applyPdCheckFormImport(reviewed);
      const selectedWork = PDC_JOB_DEFS.filter(def => reviewed.reviewRequirementUpdates?.[def.requireKey]).map(def => def.label);
      results.push({
        ok: true,
        title: displayStockNumber(applied.vehicle) || reviewed.order || reviewed.vin,
        vehicleKey: vehicleKey(applied.vehicle),
        message: `${applied.taskCount} detected line item${applied.taskCount === 1 ? '' : 's'} attached · Required work: ${selectedWork.join(', ') || 'none selected'}.`,
      });
    } catch (error) {
      app.data = buildVehicleData();
      results.push({ ok: false, title: parsed.stock || parsed.order || parsed.vin, message: error.message || String(error) });
    }
  }
  app.data = buildVehicleData();
  const successfulImports = results.filter(result => result.ok);
  if (successfulImports.length) {
    updateOperationalHealth({
      lastWorkImportAt: nowIsoString(),
      lastWorkImportType: 'PD / job card',
      lastWorkImportRows: successfulImports.length,
    });
  }
  renderAll();
  setDashboardPdStatus(results.length ? results : [{ ok: false, title: 'PD import', message: 'Add a PD PDF or paste PD text first.' }]);
  focusVehiclesAfterWorkImport(successfulImports.map(result => result.vehicleKey));
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
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared mechanic list right now. Check your connection and try again.'); return; }
  service.addTechnician(entered).then(result => {
    if (!result.ok && result.error !== 'duplicate_name') { window.alert(result.error || 'Could not add mechanic.'); return; }
    renderKpis();
    renderAdminLists();
  });
}

function addSubletProviderFromPrompt() {
  const entered = cleanNavisionText(window.prompt('Enter external provider name:', '') || '');
  if (!entered) return;
  const service = typeof initWorkshopReferenceDataServiceIfAvailable === 'function' ? initWorkshopReferenceDataServiceIfAvailable() : null;
  if (!service) { window.alert('Cannot reach the shared provider list right now. Check your connection and try again.'); return; }
  service.addSubletProvider(entered).then(result => {
    if (!result.ok && result.error !== 'duplicate_name') { window.alert(result.error || 'Could not add provider.'); return; }
    renderKpis();
    renderAdminLists();
  });
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
const PMB_SCHEDULE_WORK_START_HOUR = 8;
const PMB_SCHEDULE_WORK_END_HOUR = 16;
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
        <section class="pmb-bay-work-started" data-pmb-complete-drop-stage="${escapeHtml(normalizedStage)}">
          <div class="pmb-bay-unassigned-title"><strong>Completed / return to unallocated</strong><span>${workStarted.length} complete</span></div>
          <div class="pmb-bay-unassigned-list">
            ${workStarted.map(vehicle => pmbBayVehicleCardHtml(vehicle, normalizedStage)).join('') || '<div class="pmb-bay-empty compact">Drop a vehicle here to choose Complete, Stoppage, or Move only.</div>'}
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
  return `<span class="pmb-pill-vehicle" title="${escapeHtml(unit)}">${escapeHtml(unit)}</span>
    <span class="pmb-pill-meta">
      <span class="pmb-card-age pmb-age-${escapeHtml(onSiteDaysClass(vehicle))}">${escapeHtml(onSiteDaysLabel(vehicle).replace('on site', 'at PMB'))}</span>
      <span class="pmb-pill-blocker ${blocked ? 'is-blocked' : ''}" title="${escapeHtml(blocker)}">${escapeHtml(blocked ? 'Parts stoppage' : 'No stoppage')}</span>
    </span>
    <span class="pmb-pill-sales" title="${escapeHtml(consultant)}">${escapeHtml(consultant)}</span>`;
}

function pmbBayVehicleCardHtml(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage || vehicle.pmbBayStage || inferredPmbStage(vehicle));
  const key = vehicleKey(vehicle);
  const jobDef = pmbStageJobDef(normalizedStage);
  const bay = pmbBayNumber(vehicle, normalizedStage);
  const complete = jobDef ? pdcJobComplete(vehicle, jobDef) : false;
  const bayLabel = bay ? `Bay ${bay}` : 'No bay';
  const identityHtml = pmbBayPillIdentityHtml(vehicle);
  const title = `${vehicleIdentityTitle(vehicle)} · ${pmbStageLabel(normalizedStage)} ${bayLabel}`;
  const finishButton = normalizedStage
    ? `<button class="small-button pmb-finish-button" type="button" data-move-pmb-stage-key="${escapeHtml(key)}" data-move-pmb-stage-value="" title="Choose Complete, Stoppage, or Move only, then return this vehicle to PMB unallocated">Finish / unallocate</button>`
    : '';

  return `
    <article class="pmb-bay-vehicle-card pmb-bay-vehicle-pill ${complete ? 'is-complete' : ''} ${isPdcBlocked(vehicle) ? 'is-blocked' : ''}" draggable="true" data-pmb-drag-key="${escapeHtml(key)}" data-open-stock="${escapeHtml(key)}" title="${escapeHtml(title)}">
      <div class="pmb-bay-pill-main">
        ${identityHtml}
        ${pmbPillCustomerHtml(vehicle)}
      </div>
      <div class="pmb-bay-pill-bottom">
        ${pmbOutstandingStationChipsHtml(vehicle)}
        ${isPdcBlocked(vehicle) ? `<span class="pmb-bay-chip blocked">Blocked</span>` : ''}
        ${finishButton}
      </div>
    </article>`;
}

function pmbVehicleCardHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const stage = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
  const title = `Drag ${vehicleIdentityTitle(vehicle) || 'vehicle'} to another PMB bucket`;
  const finishButton = stage
    ? `<button class="small-button pmb-finish-button" type="button" data-move-pmb-stage-key="${escapeHtml(key)}" data-move-pmb-stage-value="" title="Choose Complete, Stoppage, or Move only, then return this vehicle to PMB unallocated">Finish / unallocate</button>`
    : '';
  return `
    <article class="pmb-vehicle-card pmb-vehicle-pill ${isPdcBlocked(vehicle) ? 'is-blocked' : ''}" draggable="true" data-pmb-drag-key="${escapeHtml(key)}" data-open-stock="${escapeHtml(key)}" title="${escapeHtml(title)}">
      <div class="pmb-pill-main">
        ${pmbBayPillIdentityHtml(vehicle)}
        ${pmbPillCustomerHtml(vehicle)}
      </div>
      <div class="pmb-pill-bottom">
        ${pmbOutstandingStationChipsHtml(vehicle)}
        ${finishButton}
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
  const updates = { [def.completeKey]: !currentlyComplete, pdcQcComplete: false, pdcQcCompleteAt: '', pdcQcCompleteBy: '' };
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
  if (!currentlyComplete) {
    offerSalespersonChangeEmail(vehicle, {
      title: `${def.label} completed`,
      subject: 'PDC work completed',
      details: [`${def.label} was signed off by ${operator}.`],
    });
  }
}

function bindPmbDragBoard(host) {
  bindIncomingCardSelection(host);
  bindVehicleLabelButtons(host);
  $$('.workflow-stage-bucket', host).forEach(bucket => {
    bucket.addEventListener('toggle', () => {
      if (bucket.open) app.workflowBucketsCollapsed = false;
      scheduleWorkflowFloatingHeaderUpdate();
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
  $$('[data-pmb-complete-drop-stage]', host).forEach(dropZone => bindPmbCompletionDropTarget(dropZone));
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
              <strong>${escapeHtml(area)} complete</strong>
              <small>Sign off this PMB job and move the vehicle.</small>
            </span>
          </label>
          <label class="pmb-resolution-option is-stoppage">
            <input type="checkbox" value="stoppage" data-pmb-resolution-choice>
            <span>
              <strong>Parts / job stoppage</strong>
              <small>Move the vehicle and record why this PMB job is stopped.</small>
            </span>
          </label>
          <label class="pmb-resolution-option is-move">
            <input type="checkbox" value="move" data-pmb-resolution-choice>
            <span>
              <strong>Move only - keep job open</strong>
              <small>Move or unallocate the vehicle without ticking off the PMB job.</small>
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
    return { pdcBlocked: true, pdcBlockReason: reason, pdcBlockedAt: now, pdcBlockedBy: operator };
  }
  if (choice === 'complete') {
    return {
      [jobDef.requireKey]: true,
      [jobDef.completeKey]: true,
      [jobDef.completeAtKey]: now,
      [jobDef.completeByKey]: operator,
      pdcQcComplete: false,
      pdcQcCompleteAt: '',
      pdcQcCompleteBy: '',
      pdcBlocked: false,
      pdcBlockReason: '',
    };
  }
  return {};
}

function recordPmbMovementResolutionAudit(vehicle = {}, fromStage = '', toStage = '', updates = {}) {
  const currentStage = normalizePmbStage(fromStage);
  const nextStage = normalizePmbStage(toStage);
  const operator = getCurrentOperatorName();
  if (updates.pdcBlocked === true) {
    recordVehicleAudit(vehicle, 'PMB movement stoppage recorded', { stage: pmbStageLabel(currentStage), reason: updates.pdcBlockReason || 'Stoppage', by: operator });
    return;
  }
  const jobDef = pmbStageJobDef(currentStage);
  if (jobDef && updates[jobDef.completeKey] === true) {
    recordVehicleAudit(vehicle, 'Job signed off by PMB movement', { job: jobDef.label, from: pmbStageLabel(currentStage), to: pmbStageLabel(nextStage) || 'Unallocated', by: operator });
  }
}

function partsIncompleteMovementStage(stage = '') {
  return ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'].includes(normalizePmbStage(stage));
}

function partsMovementOverrideRoleAllowed(role = '') {
  return /(^|[^a-z])(manager|admin|administrator)([^a-z]|$)/i.test(cleanNavisionText(role));
}

function pmbPhysicalBayEntry(currentStage = '', currentBay = '', nextStage = '', nextBay = '') {
  const normalizedCurrent = normalizePmbStage(currentStage);
  const normalizedNext = normalizePmbStage(nextStage);
  const normalizedNextBay = normalizePmbBayNumber(nextBay, normalizedNext);
  if (!normalizedNext || !normalizedNextBay) return false;
  return normalizedCurrent !== normalizedNext || !normalizePmbBayNumber(currentBay, normalizedCurrent);
}

function confirmPartsIncompleteMovement(vehicle = {}, stage = '') {
  const nextStage = normalizePmbStage(stage);
  const partsStatus = partsDepartmentStatus(vehicle);
  if (!partsIncompleteMovementStage(nextStage) || ['issued', 'notrequired'].includes(partsStatus)) return { updates: {}, audit: null };
  const operator = cleanNavisionText(localStorage.getItem(OPERATOR_NAME_KEY) || '');
  const role = cleanNavisionText(localStorage.getItem(OPERATOR_ROLE_KEY) || '');
  if (!operator || !role) {
    window.alert('Set your operator name and role before moving a Parts-incomplete vehicle into a physical bay. No vehicle was changed.');
    return null;
  }
  if (!partsMovementOverrideRoleAllowed(role)) {
    window.alert('Parts are not complete. Only a Manager or Admin can authorise entry into a physical bay. No vehicle was changed.');
    return null;
  }
  const stock = displayStockNumber(vehicle) || vehicle.order || 'this vehicle';
  const destination = pmbStageLabel(nextStage);
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-backdrop pmb-resolution-modal';
    overlay.innerHTML = `
      <section class="modal-card pmb-resolution-modal-card">
        <button class="modal-close" type="button" data-parts-override-cancel aria-label="Cancel movement">×</button>
        <div class="panel-header"><div>
          <h2>Parts not complete</h2>
          <p>${escapeHtml(stock)} is ${escapeHtml(partsDepartmentStatusLabel(partsStatus))}. Moving it into ${escapeHtml(destination)} requires an authorised exception and a reason.</p>
        </div></div>
        <label class="pmb-resolution-reason">
          <span>Manager / admin override reason</span>
          <input type="text" data-parts-override-reason maxlength="180" placeholder="Enter the operational reason" autocomplete="off">
        </label>
        <p class="form-error" data-parts-override-error hidden>Enter an override reason before continuing.</p>
        <div class="edit-actions pmb-resolution-actions">
          <button class="secondary" type="button" data-parts-override-cancel>Cancel</button>
          <button class="primary" type="button" data-parts-override-save>Confirm override</button>
        </div>
      </section>`;
    const finish = value => {
      document.removeEventListener('keydown', onKeydown);
      overlay.remove();
      resolve(value);
    };
    const onKeydown = event => { if (event.key === 'Escape') finish(null); };
    overlay.querySelectorAll('[data-parts-override-cancel]').forEach(button => button.addEventListener('click', () => finish(null)));
    overlay.addEventListener('click', event => { if (event.target === overlay) finish(null); });
    overlay.querySelector('[data-parts-override-save]').addEventListener('click', () => {
      const reason = cleanNavisionText(overlay.querySelector('[data-parts-override-reason]')?.value || '');
      if (!reason) {
        overlay.querySelector('[data-parts-override-error]').hidden = false;
        overlay.querySelector('[data-parts-override-reason]')?.focus();
        return;
      }
      finish({
        updates: { pdcPartsMovementOverrideReason: reason, pdcPartsMovementOverrideAt: nowIsoString(), pdcPartsMovementOverrideBy: operator },
        audit: { stage: destination, reason, by: operator, role },
      });
    });
    document.body.appendChild(overlay);
    document.addEventListener('keydown', onKeydown);
    overlay.querySelector('[data-parts-override-reason]')?.focus();
  });
}

async function movePmbVehicleToStage(key, stage) {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return;
  const vehicle = selectedVehicle(cleanKey);
  if (!vehicle) return;
  if (statusCategory(vehicle) !== 'pmb') {
    window.alert('That vehicle is not currently in PMB. Transfer it from Yard Hold to PMB first.');
    return;
  }
  const nextStage = normalizePmbStage(stage);
  const currentStage = normalizePmbStage(vehicle.pmbBayStage || vehicle.pmbStage || inferredPmbStage(vehicle) || vehicle.pdcWorkStage || vehicle.workStage || '');
  if (currentStage === nextStage) return;
  const now = nowIsoString();
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
  };
  const snapshot = { ...vehicle };
  try {
    runStorageTransaction('Move PMB vehicle to stage', [EDITS_KEY, AUDIT_LOG_KEY], () => {
      recordPmbMovementResolutionAudit(vehicle, currentStage, nextStage, resolutionUpdates);
      recordVehicleAudit(vehicle, 'PMB bucket moved', { from: pmbStageLabel(currentStage) || 'Unallocated', to: pmbStageLabel(nextStage) || 'Unallocated' });
      if (!saveVehicleEdits(vehicleKey(vehicle), updates)) throw new Error('The PMB stage update failed.');
    });
  } catch (error) {
    Object.keys(vehicle).forEach(field => { if (!Object.prototype.hasOwnProperty.call(snapshot, field)) delete vehicle[field]; });
    Object.assign(vehicle, snapshot);
    window.alert(error.message || String(error));
    return;
  }
  const completedDef = pmbStageJobDef(currentStage);
  if (resolutionUpdates.pdcBlocked === true) {
    offerSalespersonChangeEmail(vehicle, {
      title: `${pmbStageLabel(currentStage) || 'PMB'} stoppage recorded`,
      subject: 'PDC stoppage update',
      details: [resolutionUpdates.pdcBlockReason || 'A production stoppage was recorded.', `Moved to ${pmbStageLabel(nextStage) || 'Unallocated'}.`],
    });
  } else if (completedDef && resolutionUpdates[completedDef.completeKey] === true) {
    offerSalespersonChangeEmail(vehicle, {
      title: `${completedDef.label} completed`,
      subject: 'PDC work completed',
      details: [`${completedDef.label} was signed off by ${getCurrentOperatorName()}.`, `Moved to ${pmbStageLabel(nextStage) || 'Unallocated'}.`],
    });
  }
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

function bindPmbCompletionDropTarget(dropTarget) {
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
    dropTarget.classList.remove('drag-over');
    void movePmbVehicleToStage(key, '');
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

async function assignPmbVehicleToBay(key, stage, bay, requestedStartIso = '', transactionOptions = {}) {
  const cleanKey = String(key || '').trim();
  const nextStage = normalizePmbStage(stage);
  if (!cleanKey || !nextStage) return;
  const vehicle = selectedVehicle(cleanKey);
  if (!vehicle) return;
  if (statusCategory(vehicle) !== 'pmb') {
    window.alert('That vehicle is not currently in PMB. Transfer it from Yard Hold to PMB first.');
    return;
  }
  const bayNumber = normalizePmbBayNumber(bay, nextStage);
  const currentStage = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
  const currentBay = pmbBayNumber(vehicle, currentStage);
  const entersNumberedBay = pmbPhysicalBayEntry(currentStage, currentBay, nextStage, bayNumber);
  let swap = null;
  if (bayNumber) {
    const occupied = pmbBayOccupants(nextStage, bayNumber, cleanKey);
    if (occupied.length) {
      const currentStageForSwap = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
      if (occupied.length !== 1 || currentStageForSwap !== nextStage || !currentBay) {
        window.alert(`${pmbStageLabel(nextStage)} Bay ${bayNumber} already has a vehicle. Move that vehicle out first, or use bay-to-bay swap from another numbered bay.`);
        return;
      }
      const other = occupied[0];
      swap = { other, otherKey: vehicleKey(other) };
    }
    // Bay assignment is already limited by the specific bay number above. Do not also block
    // moves because the PMB bucket is over its row/queue limit; that made valid bay-to-bay
    // and unallocated-to-empty-bay moves fail on busy days.
  }
  const partsDecision = entersNumberedBay ? await confirmPartsIncompleteMovement(vehicle, nextStage) : { updates: {}, audit: null };
  if (partsDecision === null) return;
  const resolutionUpdates = await pmbMovementResolutionUpdates(vehicle, currentStage, nextStage);
  if (resolutionUpdates === null) return;
  const now = nowIsoString();
  const bayLabel = bayNumber ? `Bay ${bayNumber}` : 'No bay';
  const updates = {
    ...partsDecision.updates,
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
    ...(entersNumberedBay ? { pdcQcComplete: false, pdcQcCompleteAt: '', pdcQcCompleteBy: '' } : {}),
  };
  if (currentStage !== nextStage) {
    updates.pmbStageUpdatedAt = now;
    updates.pmbStageEnteredAt = now;
  }
  const vehicleSnapshot = { ...vehicle };
  const swapSnapshot = swap ? { ...swap.other } : null;
  const extraTransactionKeys = Array.isArray(transactionOptions.keys) ? transactionOptions.keys : [];
  try {
    runStorageTransaction('Assign vehicle to PMB bay', [EDITS_KEY, AUDIT_LOG_KEY, ...extraTransactionKeys], () => {
      if (swap) {
        saveVehicleEdits(swap.otherKey, {
          pdcLocation: 'PMB', manualLocation: 'PMB', pdcLocationLocked: true,
          pmbStage: nextStage, pmbBayStage: nextStage, pmbBayNumber: currentBay,
          pmbBayEnteredAt: now, pmbBayCompletedAt: '', pmbBayCompletedBy: '', pmbBayCompletedStage: '',
        }, { render: false });
        recordVehicleAudit(swap.other, 'Swapped PMB bay', { stage: pmbStageLabel(nextStage), bay: `Bay ${currentBay}` });
      }
      recordPmbMovementResolutionAudit(vehicle, currentStage, nextStage, resolutionUpdates);
      if (currentStage !== nextStage) recordVehicleAudit(vehicle, 'PMB bucket moved', { from: pmbStageLabel(currentStage) || 'Unallocated', to: pmbStageLabel(nextStage) || 'Unallocated' });
      if (partsDecision.audit) recordVehicleAudit(vehicle, 'Parts-incomplete movement override', partsDecision.audit);
      recordVehicleAudit(vehicle, bayNumber ? 'Assigned to PMB bay' : 'Removed from PMB bay', { stage: pmbStageLabel(nextStage), bay: bayLabel });
      if (!saveVehicleEdits(vehicleKey(vehicle), updates)) throw new Error('The vehicle bay update failed.');
      if (typeof transactionOptions.afterAssign === 'function') transactionOptions.afterAssign(vehicle, updates);
    });
  } catch (error) {
    Object.keys(vehicle).forEach(field => { if (!Object.prototype.hasOwnProperty.call(vehicleSnapshot, field)) delete vehicle[field]; });
    Object.assign(vehicle, vehicleSnapshot);
    if (swap && swapSnapshot) {
      Object.keys(swap.other).forEach(field => { if (!Object.prototype.hasOwnProperty.call(swapSnapshot, field)) delete swap.other[field]; });
      Object.assign(swap.other, swapSnapshot);
    }
    window.alert(error.message || String(error));
    return false;
  }
  app.activePmbBayStage = nextStage;
  return true;
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
    // No roster-add call here: pmbBayAssignee is a <select> populated
    // exclusively from loadSubletProviders() (Supabase-backed as of
    // Stage 2A), so `assignee` can only ever be a name that already
    // exists -- there is nothing new to add.
  } else {
    updates.pmbBayMechanic = assignee;
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
  // No roster-add call here: `value` comes from a <select> populated
  // exclusively from loadMechanics() (Supabase-backed as of Stage 2A), so
  // it can only ever be a name that already exists.
  recordVehicleAudit(vehicle, 'Bay mechanic assigned', { stage: pmbStageLabel(normalizedStage), mechanic: mechanic || 'Unassigned' });
  saveVehicleEdits(vehicleKey(vehicle), { pmbBayMechanic: mechanic });
}

function updatePmbBaySubletProvider(key, stage, value) {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(v => vehicleKey(v) === cleanKey || v.stock === cleanKey || v.order === cleanKey || v.id === cleanKey);
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!vehicle || !normalizedStage) return;
  const provider = cleanNavisionText(value || '');
  // No roster-add call here: `value` comes from a <select> populated
  // exclusively from loadSubletProviders() (Supabase-backed as of Stage
  // 2A), so it can only ever be a name that already exists.
  recordVehicleAudit(vehicle, 'External provider assigned', { stage: pmbStageLabel(normalizedStage), provider: provider || 'Unassigned' });
  saveVehicleEdits(vehicleKey(vehicle), { pmbSubletProvider: provider });
}

function completePmbBayWork(key, stage, transactionOptions = {}) {
  const cleanKey = String(key || '').trim();
  const vehicle = selectedVehicle(cleanKey);
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
    pdcQcComplete: false,
    pdcQcCompleteAt: '',
    pdcQcCompleteBy: '',
    pmbBayCompletedAt: now,
    pmbBayCompletedBy: operator,
    pmbBayCompletedStage: normalizedStage,
    pmbStage: '',
    pmbStageUpdatedAt: now,
    pmbStageEnteredAt: now,
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
  const snapshot = { ...vehicle };
  const extraTransactionKeys = Array.isArray(transactionOptions.keys) ? transactionOptions.keys : [];
  try {
    runStorageTransaction('Complete PMB bay work', [EDITS_KEY, AUDIT_LOG_KEY, ...extraTransactionKeys], () => {
      recordVehicleAudit(vehicle, 'Bay work completed', { stage: pmbStageLabel(normalizedStage), job: def.label, bay: bay || 'No bay', hours: hours === '' ? '' : hours, mechanic: mechanic || 'Unassigned', provider: normalizedStage === 'SUBLET' ? (subletProvider || 'Unassigned') : '', by: operator, returnedTo: 'PMB unallocated' });
      if (!saveVehicleEdits(vehicleKey(vehicle), updates)) throw new Error('The completed bay work could not be saved.');
      if (typeof transactionOptions.afterComplete === 'function') transactionOptions.afterComplete(vehicle, def, updates);
    });
  } catch (error) {
    Object.keys(vehicle).forEach(field => { if (!Object.prototype.hasOwnProperty.call(snapshot, field)) delete vehicle[field]; });
    Object.assign(vehicle, snapshot);
    window.alert(error.message || String(error));
    return false;
  }
  offerSalespersonChangeEmail(vehicle, {
    title: `${def.label} completed`,
    subject: 'PDC work completed',
    details: [
      `${def.label} was signed off by ${operator}.`,
      bay ? `Completed in bay ${bay}.` : 'Completed without a numbered bay.',
      mechanic ? `Mechanic: ${mechanic}.` : '',
    ],
  });
  return true;
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
  const rows = pdcSheetVehicles();
  const pmbRows = rows.filter(vehicle => statusCategory(vehicle) === 'pmb');
  const rftRows = rows.filter(vehicle => statusCategory(vehicle) === 'rft');
  return {
    partsStoppage: rows.filter(isActivePartsStoppage).length,
    pmbBlocked: pmbRows.filter(isPdcBlocked).length,
    rftBlocked: rftRows.filter(vehicle => vehicleRftGateIssues(vehicle).length).length,
    pmbUnallocated: pmbRows.filter(vehicle => !inferredPmbStage(vehicle)).length,
    yardHoldReady: rows.filter(canTransferVehicleToPmb).length,
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
  return pdcSheetVehicles().filter(v => {
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
        Object.assign(updates, { pdcQcComplete: false, pdcQcCompleteAt: '', pdcQcCompleteBy: '' });
      }
      if (vehicle && def) {
        recordVehicleAudit(vehicle, isCompletionFlag ? (input.checked ? 'Job signed off from RFT table' : 'Job sign-off removed from RFT table') : (input.checked ? 'Requirement added' : 'Requirement removed'), { job: def.label });
      }
      saveVehicleEdits(input.dataset.flagStock, updates);
      if (vehicle && def && isCompletionFlag && input.checked) {
        offerSalespersonChangeEmail(vehicle, {
          title: `${def.label} completed`,
          subject: 'PDC work completed',
          details: [`${def.label} was signed off by ${getCurrentOperatorName()}.`],
        });
      }
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


function removeVehiclesFromTracker(vehicles = [], options = {}) {
  try {
    return runStorageTransaction('Vehicle removal', trackerTransactionKeys(), () => removeVehiclesFromTrackerUnsafe(vehicles, options));
  } catch (error) {
    app.data = buildVehicleData();
    window.alert(error.message || String(error));
    return [];
  }
}

function removeVehiclesFromTrackerUnsafe(vehicles = [], options = {}) {
  const list = vehicles.filter(Boolean);
  if (!list.length) return [];
  const deletedRecords = deletedVehicleRecords();
  const existingRecordsByKey = new Map();
  deletedRecords.forEach(record => {
    [record.key].concat(record.keys || []).filter(Boolean).forEach(key => existingRecordsByKey.set(String(key), record));
  });
  let added = loadAddedVehicles();
  const edits = loadVehicleEdits();
  const poTasks = loadPoTasks();
  const poFiles = loadPoFiles();
  const exactRemovalKeys = new Set();
  const operator = getCurrentOperatorName();
  const role = getCurrentOperatorRole();
  const deletedAt = nowIsoString();
  const deletionType = cleanNavisionText(options.deletionType || 'manual') || 'manual';
  const deletionReason = cleanNavisionText(options.reason || (deletionType === 'navision-missing' ? 'No longer present in the latest full Navision upload' : 'Deleted by an operator'));

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
    const allDeleteKeys = [...new Set(exactKeys.concat(vin ? [vin] : []))];
    const key = exactKeys[0] || vin;

    exactKeys.forEach(value => exactRemovalKeys.add(value));
    allDeleteKeys.forEach(value => {
      delete edits[value];
      delete poTasks[value];
      delete poFiles[value];
    });

    if (key && !allDeleteKeys.some(value => existingRecordsByKey.has(value))) {
      const record = {
        key,
        keys: allDeleteKeys,
        deletedAt,
        deletedBy: operator || 'Unknown operator',
        deletedRole: role || 'Unassigned role',
        reason: deletionReason,
        deletionType,
        vehicle: JSON.parse(JSON.stringify(vehicle)),
      };
      deletedRecords.unshift(record);
      allDeleteKeys.forEach(value => existingRecordsByKey.set(value, record));
      const auditAction = deletionType === 'navision-missing' ? 'Retired from Navision back end' : 'Deleted from board';
      recordVehicleAudit(vehicle, auditAction, { by: operator || 'Unknown operator', role: role || 'Unassigned role', reason: deletionReason });
    }
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

  saveDeletedVehicleRecords(deletedRecords);
  saveAddedVehicles(added);
  saveJson(EDITS_KEY, edits);
  savePoTasks(poTasks);
  savePoFiles(poFiles);
  return list;
}

function refreshAfterVehicleRemoval() {
  app.selectedRows.clear();
  app.data = buildVehicleData();
  const visibleRows = pdcSheetVehicles();
  app.selectedStock = visibleRows[0] ? vehicleKey(visibleRows[0]) : (app.data[0] ? vehicleKey(app.data[0]) : null);
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
  const statusEmailButton = $('#email-selected-update-bar');
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
  if (statusEmailButton) {
    statusEmailButton.disabled = count !== 1;
    statusEmailButton.title = count === 1 ? 'Email the selected vehicle update to its salesperson' : 'Select exactly one vehicle to email an update';
  }
  clearButtons.forEach(button => { button.disabled = count === 0; });
  deleteButtons.forEach(button => {
    button.disabled = count === 0;
    button.title = count ? `Delete ${count} selected vehicle${count === 1 ? '' : 's'} from this tracker` : 'Select one or more vehicles first';
  });
  printButtons.forEach(button => {
    button.hidden = count === 0;
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
      ...pdcVisibilityPromotionUpdates(vehicle, 'Operator manual Yard Hold override'),
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
      ...pdcVisibilityPromotionUpdates(vehicle, 'Operator PMB transfer'),
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
    ...pdcVisibilityPromotionUpdates(vehicle, 'Operator PMB transfer'),
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

async function transferVehiclesToRft(vehicles = [], options = {}) {
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

  if (vehicleLifecycleSharedModeActive()) {
    const failures = [];
    for (const vehicle of selected) {
      const ref = await vehicleLifecycleSharedRef(vehicle);
      if (!ref || ref.outcome !== 'resolved') {
        failures.push(`${vehicleIdentityTitle(vehicle) || 'No stock'} - ${describeVehicleLifecycleResolutionOutcome(ref)}`);
        continue;
      }
      if (ref.isArchived) {
        failures.push(`${vehicleIdentityTitle(vehicle) || 'No stock'} - archived in shared data`);
        continue;
      }
      if (!ref.qcCompletedAt) {
        failures.push(`${vehicleIdentityTitle(vehicle) || 'No stock'} - QC sign-off required first`);
        continue;
      }
      const result = await window.__vehicleLifecycleActions.rftTransferVehicle({ vehicleId: ref.vehicleId, expectedVersion: ref.version });
      if (!result || result.ok !== true) {
        const message = typeof describeVehicleLifecycleActionError === 'function' ? describeVehicleLifecycleActionError(result && result.error) : 'The transfer could not be saved.';
        failures.push(`${vehicleIdentityTitle(vehicle) || 'No stock'} - ${message}`);
        continue;
      }
    }
    if (failures.length) {
      window.alert(`Some vehicles were not transferred:\n\n${failures.join('\n')}`);
    }
    if (options.clearSelection) app.selectedRows.clear();
    app.quickFilter = 'rft';
    app.pmbSubFilter = '';
    if (typeof window.__workshopDataService !== 'undefined' && window.__workshopDataService) window.__workshopDataService.loadSnapshot('rft_transfer');
    renderAll();
    if (selected.length === 1 && !failures.length) {
      offerSalespersonChangeEmail(selected[0], {
        title: 'Vehicle ready for transport (RFT)',
        subject: 'Vehicle ready for transport',
        shared: true,
        details: ['The vehicle has moved to RFT and is ready for transport. A notification has been queued for the assigned salesperson.'],
      });
    }
    return;
  }

  const transferTime = nowIsoString();
  selected.forEach(vehicle => {
    recordVehicleAudit(vehicle, 'Transferred to RFT', { from: pmbStageLabel(inferredPmbStage(vehicle)) || 'PMB - Unallocated', to: 'RFT', completedJobs: pdcCompletedJobsText(vehicle), outstandingJobs: pdcOutstandingJobsText(vehicle), blocked: isPdcBlocked(vehicle) ? pdcBlockReason(vehicle) : '' });
    saveVehicleEdits(vehicleKey(vehicle), {
      ...pdcVisibilityPromotionUpdates(vehicle, 'Operator RFT transfer'),
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
  if (selected.length === 1) {
    offerSalespersonChangeEmail(selected[0], {
      title: 'Vehicle ready for transport (RFT)',
      subject: 'Vehicle ready for transport',
      details: ['The vehicle has moved to RFT and is ready for transport.'],
    });
  }
}


function salespersonEmail(vehicle = {}) {
  return cleanNavisionText(salespersonForVehicle(vehicle)?.email || RFT_SALESPERSON_EMAIL);
}

function salespersonDisplayName(vehicle = {}) {
  return salespersonForVehicle(vehicle)?.name || consultantName(vehicle) || 'Sales';
}

function salespersonChangeFlag(vehicle = {}, change = {}) {
  const title = cleanNavisionText(change.title || '');
  if (title && title.toLowerCase() !== 'vehicle status update') return title;
  if (statusCategory(vehicle) === 'rft') return 'Ready for transport (RFT)';
  if (vehicleCollectedFromRft(vehicle)) return 'Vehicle completed / collected';
  if (isActivePartsStoppage(vehicle)) return 'Parts delay / stoppage';
  const partsStatus = partsDepartmentStatus(vehicle);
  if (partsWorstEtaLabel(vehicle) && !['issued', 'notrequired'].includes(partsStatus)) return 'Parts ETA / delay update';
  if (isPdcBlocked(vehicle)) return 'PDC stoppage / blocker';
  return title || 'Vehicle status update';
}

function salespersonChangeBannerLines(vehicle = {}, change = {}) {
  return [
    '========================================',
    `IMPORTANT UPDATE: ${salespersonChangeFlag(vehicle, change).toUpperCase()}`,
    '========================================',
  ];
}

function salespersonChangeEmailBody(vehicle = {}, change = {}) {
  const salesperson = salespersonDisplayName(vehicle);
  const details = (Array.isArray(change.details) ? change.details : [change.details]).map(cleanNavisionText).filter(Boolean);
  return [
    `Hi ${salesperson},`,
    '',
    ...salespersonChangeBannerLines(vehicle, change),
    '',
    'The PDC Control Board has been updated for the following vehicle:',
    '',
    ...vehicleEmailLines(vehicle),
    `Job Card: ${vehicleJobcardNumber(vehicle) || 'TBA'}`,
    `Update: ${cleanNavisionText(change.title || 'Vehicle status updated')}`,
    ...details.map(detail => `- ${detail}`),
    `Current status: ${statusCategoryLabel(vehicle)}${inferredPmbStage(vehicle) ? ` / ${pmbStageLabel(inferredPmbStage(vehicle))}` : ''}`,
    '',
    'Please update the customer or delivery expectation if required.',
    '',
    'Kind Regards,',
  ].join('\n');
}

function draftSalespersonChangeEmail(vehicle = {}, change = {}, recipient = '') {
  const email = cleanNavisionText(recipient || salespersonEmail(vehicle));
  if (!email) {
    window.alert('Enter a salesperson email address before opening the email draft.');
    return false;
  }
  const stock = displayStockNumber(vehicle) || vehicle.order || 'TBA';
  const subject = `${cleanNavisionText(change.subject || change.title || 'PDC vehicle update')} - ${stock}`;
  const body = String(change.body || '').trim() || salespersonChangeEmailBody(vehicle, change);
  if (change.shared !== true) {
    recordVehicleAudit(vehicle, 'Salesperson update email drafted', { change: change.title || 'Vehicle status updated', recipient: email });
  }
  window.location.href = `mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  return true;
}

function offerSalespersonChangeEmail(vehicle = {}, change = {}) {
  if (!vehicle || !change?.title || typeof document?.createElement !== 'function') return;
  const existingOverlay = document.querySelector('[data-sales-change-email-overlay]');
  if (typeof existingOverlay?.remove === 'function') existingOverlay.remove();
  const salesperson = salespersonDisplayName(vehicle) || 'Unassigned';
  const defaultEmail = salespersonEmail(vehicle);
  const details = (Array.isArray(change.details) ? change.details : [change.details]).map(cleanNavisionText).filter(Boolean);
  const overlay = document.createElement('div');
  if (typeof overlay?.querySelectorAll !== 'function' || typeof overlay?.querySelector !== 'function') return;
  overlay.className = 'modal-overlay sales-change-email-overlay';
  overlay.dataset.salesChangeEmailOverlay = 'true';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-labelledby', 'sales-change-email-title');
  overlay.innerHTML = `
    <section class="modal-card sales-change-email-card">
      <button class="modal-close" type="button" data-sales-email-cancel aria-label="Close email notification">×</button>
      <div class="sales-change-email-heading">
        <span class="sales-change-email-icon">@</span>
        <div><h2 id="sales-change-email-title">Notify salesperson?</h2><p>The vehicle update has been saved. Open a prepared email to let sales know what changed.</p></div>
      </div>
      <div class="sales-change-email-summary">
        <strong>${escapeHtml(salespersonChangeFlag(vehicle, change))}</strong>
        <span>${escapeHtml(vehicleIdentityTitle(vehicle) || displayStockNumber(vehicle) || vehicle.order || 'Vehicle')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
        ${details.map(detail => `<small>${escapeHtml(detail)}</small>`).join('')}
      </div>
      <div class="sales-change-email-fields">
        <label><span>Salesperson</span><input value="${escapeHtml(salesperson)}" readonly /></label>
        <label><span>Email address</span><input type="email" value="${escapeHtml(defaultEmail)}" data-sales-email-recipient autocomplete="email" /></label>
      </div>
      <div class="subtle">The website opens an email draft for review. Check the recipient before sending, especially when the imported file contains only salesperson initials.</div>
      <div class="edit-actions sales-change-email-actions">
        <button class="secondary" type="button" data-sales-email-cancel>Not now</button>
        <button class="primary" type="button" data-sales-email-open>Open email draft</button>
      </div>
    </section>`;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  overlay.querySelectorAll('[data-sales-email-cancel]').forEach(button => button.addEventListener('click', close));
  overlay.addEventListener('click', event => { if (event.target === overlay) close(); });
  overlay.querySelector('[data-sales-email-open]')?.addEventListener('click', () => {
    const recipient = overlay.querySelector('[data-sales-email-recipient]')?.value || '';
    if (draftSalespersonChangeEmail(vehicle, change, recipient)) close();
  });
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
  overlay.querySelector('[data-sales-email-open]')?.focus();
}

function vehicleStatusUpdateEmailBody(vehicle = {}) {
  const salesperson = salespersonDisplayName(vehicle);
  const location = pdcLocationLabel(vehiclePdcLocation(vehicle)) || statusCategoryLabel(vehicle) || 'Follow Navision';
  const stage = inferredPmbStage(vehicle);
  const stageLabel = stage ? pmbStageLabel(stage) : (vehiclePdcLocation(vehicle) === 'PMB' ? 'Unallocated' : 'Not in PMB');
  const bay = pmbBaySummary(vehicle) || 'No numbered bay';
  const partsStatus = partsDepartmentStatus(vehicle);
  const partsOpen = !['issued', 'notrequired'].includes(partsStatus);
  const partsEta = partsWorstEtaLabel(vehicle) || 'Not recorded';
  const partsCountdown = partsWorstEtaCountdownLabel(vehicle);
  const completed = pdcCompletedJobs(vehicle).map(job => {
    const completedAt = parseIsoTimestamp(vehicle[job.completeAtKey]);
    const when = completedAt ? ` on ${completedAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' })}` : '';
    const by = cleanNavisionText(vehicle[job.completeByKey] || '');
    const mechanic = pdcJobMechanic(vehicle, job);
    const completedBay = pdcJobBay(vehicle, job);
    const hours = pdcJobHours(vehicle, job);
    return `- ${job.label}${when}${by ? ` by ${by}` : ''}${mechanic ? ` · Mechanic: ${mechanic}` : ''}${completedBay ? ` · Bay: ${completedBay}` : ''}${hours ? ` · ${hours}h` : ''}`;
  });
  const outstanding = pdcRequirementDefinitions(vehicle)
    .filter(job => !pdcJobComplete(vehicle, job))
    .map(job => `- ${job.label}`);
  const workshopHistory = vehicleWorkshopHistoryLines(vehicle);
  const blocker = isPdcBlocked(vehicle) ? pdcBlockReason(vehicle) : '';
  return [
    `Hi ${salesperson},`,
    '',
    ...salespersonChangeBannerLines(vehicle, { title: 'Vehicle status update' }),
    '',
    'Here is the latest PDC update for this vehicle:',
    '',
    ...vehicleEmailLines(vehicle),
    `Job Card: ${vehicleJobcardNumber(vehicle) || 'TBA'}`,
    `Current location: ${location}`,
    `Current PMB area: ${stageLabel}${vehiclePdcLocation(vehicle) === 'PMB' ? ` · ${bay}` : ''}`,
    `Navision sub-location: ${navisionStatusText(vehicle) || 'Not supplied'}`,
    `ETA to Kewdale: ${scotEtaOnly(vehicle.etaAtDealer) || 'Not supplied'}`,
    '',
    `Parts status: ${partsDepartmentStatusLabel(partsStatus)}`,
    ...(partsOpen ? [
      `Parts ETA: ${partsEta}${partsCountdown ? ` (${partsCountdown})` : ''}`,
      ...(isActivePartsStoppage(vehicle) ? [`Parts stoppage: ${partsStoppageReason(vehicle)}`] : []),
    ] : []),
    '',
    'Workshop / bay history:',
    ...(workshopHistory.length ? workshopHistory : ['- No bay visits recorded yet']),
    '',
    'Work completed:',
    ...(completed.length ? completed : ['- No PDC work has been signed off yet']),
    '',
    'Work still outstanding:',
    ...(outstanding.length ? outstanding : ['- None']),
    ...(blocker ? ['', `Current stoppage / blocker: ${blocker}`] : []),
    '',
    'Kind Regards,',
  ].join('\n');
}

function draftSelectedVehicleStatusEmail(key = '') {
  const cleanKey = String(key || '').trim();
  const selected = cleanKey
    ? app.data.filter(vehicle => [vehicleKey(vehicle), vehicle.stock, vehicle.order, vehicle.id].map(String).includes(cleanKey))
    : selectedVehiclesForBulkEmail();
  if (selected.length !== 1) {
    window.alert('Select exactly one vehicle before using EMAIL UPDATE.');
    return;
  }
  const vehicle = selected[0];
  offerSalespersonChangeEmail(vehicle, {
    title: 'Vehicle status update',
    subject: 'Vehicle update',
    details: [
      `Current location: ${pdcLocationLabel(vehiclePdcLocation(vehicle)) || statusCategoryLabel(vehicle) || 'Follow Navision'}.`,
      `Parts: ${partsDepartmentStatusLabel(partsDepartmentStatus(vehicle))}.`,
      'The draft includes parts ETA, bay history, completed work and outstanding work.',
    ],
    body: vehicleStatusUpdateEmailBody(vehicle),
  });
}

function draftRftSalespersonNotificationEmail(vehicles = []) {
  const list = vehicles.map(item => typeof item === 'string' ? selectedVehicle(item) : item).filter(Boolean);
  if (!list.length) return;
  const salesperson = list.length === 1 ? salespersonDisplayName(list[0]) : 'Sales team';
  const body = [
    `Hi ${salesperson},`,
    '',
    ...salespersonChangeBannerLines(list[0], { title: 'Ready for transport (RFT)' }),
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
  const recipient = list.length === 1 ? salespersonEmail(list[0]) : RFT_SALESPERSON_EMAIL;
  window.location.href = `mailto:${recipient}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
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
const externalScriptLoads = new Map();

function loadExternalScript(src = '', id = '') {
  const cleanSrc = String(src || '').trim();
  if (!cleanSrc) return Promise.reject(new Error('No script source was supplied.'));
  if (externalScriptLoads.has(cleanSrc)) return externalScriptLoads.get(cleanSrc);
  const existing = id ? document.getElementById(id) : null;
  if (existing?.dataset.loaded === 'true') return Promise.resolve(existing);
  const promise = new Promise((resolve, reject) => {
    const script = existing || document.createElement('script');
    if (id) script.id = id;
    script.src = cleanSrc;
    script.async = true;
    script.addEventListener('load', () => {
      script.dataset.loaded = 'true';
      resolve(script);
    }, { once: true });
    script.addEventListener('error', () => {
      externalScriptLoads.delete(cleanSrc);
      reject(new Error(`Could not load ${cleanSrc}.`));
    }, { once: true });
    if (!existing) document.head.appendChild(script);
  });
  externalScriptLoads.set(cleanSrc, promise);
  return promise;
}

function qzAvailable() {
  return typeof window.qz !== 'undefined' && window.qz.websocket && window.qz.printers && window.qz.configs;
}

async function ensureQzConnected() {
  if (!qzAvailable()) {
    await loadExternalScript('vendor/qz/qz-tray.js?v=2.2.6', 'qz-tray-script');
  }
  if (!qzAvailable()) {
    throw new Error('The QZ Tray browser connector did not load. Check QZ Tray is installed and running.');
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
  for (const target of QZ_DEFAULT_PRINTER_NAMES) {
    const match = list.find(name => String(name || '').toLowerCase() === String(target).toLowerCase());
    if (match) {
      qzLastPrinterName = match;
      localStorage.setItem('vehicleTrackingCoreQzPrinter:v1', match);
      return match;
    }
  }
  const savedZebra = list.find(name => name === qzLastPrinterName && /zebra|zdesigner|bt-zebra/i.test(String(name || '')));
  if (savedZebra) return savedZebra;
  for (const target of QZ_DEFAULT_PRINTER_NAMES) {
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
  throw new Error(`Zebra printer not found. Expected BT-Zebra-EricComp, dc-01\\BT-Zebra-EricComp or 192.168.0.164. Available printers: ${list.join(', ') || 'none'}`);
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
    const config = qz.configs.create(printerName, {
      copies: 1,
      scaleContent: false,
      encoding: 'UTF-8',
    });
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

function confirmZplWarnings(warnings = [], description = 'labels') {
  if (!warnings.length) return true;
  const preview = warnings.slice(0, 8).map(warning => `• ${warning}`).join('\n');
  const more = warnings.length > 8 ? `\n• plus ${warnings.length - 8} more warning${warnings.length - 8 === 1 ? '' : 's'}` : '';
  return window.confirm(`VIN / label warning before printing ${description}:\n\n${preview}${more}\n\nThe label can still be printed. Continue?`);
}

function selectedVehicleLabelData(vehicle = {}) {
  return {
    keyNumber: cleanZplField(vehicleKeyNumber(vehicle) || getSelectedZplBatch(vehicle)),
    stock: cleanZplField(displayStockNumber(vehicle) || vehicle.order || ''),
    jobCard: cleanZplField(vehicleJobcardNumber(vehicle) || ''),
    customer: cleanZplField(vehicleCustomerName(vehicle) || vehicle.client || 'Dealer Order'),
    model: cleanZplField(displayVehicle(vehicle) || vehicle.vehicle || ''),
    sales: cleanZplField(consultantName(vehicle) || vehicle.salesperson || vehicle.salesPerson || ''),
    department: cleanZplField(vehicleDepartmentLabel(vehicle) || vehicle.dealershipDepartment || vehicle.dealership || 'PDC'),
  };
}

function vehiclesToZpl(vehicles = []) {
  if (!vehicles.length) return { zpl: '', count: 0, warnings: ['Select one or more vehicles first.'] };
  const zpl = vehicles.map(vehicle => vehicleToZplBlock(selectedVehicleLabelData(vehicle))).join('\n\n');
  return { zpl, count: vehicles.length, warnings: [] };
}

function selectedVehiclesToZpl() {
  return vehiclesToZpl(selectedVehiclesForBulkEmail());
}

async function printZplFromSelectedRows() {
  const result = selectedVehiclesToZpl();
  if (!result.count) return;
  if (!confirmZplWarnings(result.warnings, `${result.count} selected vehicle${result.count === 1 ? '' : 's'}`)) return;
  await printRawZpl(result.zpl, `${result.count} selected vehicle${result.count === 1 ? '' : 's'}`);
}

async function printCurrentZplOutput() {
  const output = $('#zpl-output')?.value || '';
  if (!output.trim()) {
    window.alert('No ZPL labels to print. Generate labels first.');
    return;
  }
  const parsed = parseZplInput($('#zpl-input')?.value || '');
  if (!confirmZplWarnings(parsed.warnings, 'the troubleshooting ZPL output')) return;
  await printRawZpl(output, 'current ZPL output');
}

async function printZplForVehicleKey(key = '') {
  const cleanKey = String(key || '').trim();
  const vehicle = app.data.find(item => [vehicleKey(item), item.stock, item.batch, item.order, item.id].map(String).includes(cleanKey));
  if (!vehicle) {
    window.alert('This vehicle could not be found. Refresh the page and try again.');
    return;
  }
  const result = vehiclesToZpl([vehicle]);
  if (!result.count) return;
  const stock = displayStockNumber(vehicle) || vehicle.order || 'this vehicle';
  if (!confirmZplWarnings(result.warnings, stock)) return;
  await printRawZpl(result.zpl, `${stock} label`);
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
    .map(value => cleanZplField(value).toUpperCase().replace(/[^A-HJ-NPR-Z0-9]/g, ''))
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
  return {
    wmi: wmiSource || vin.slice(0, 3),
    vds: vdsSource || vin.slice(3, 9),
    frame: frameSource || vin.slice(9),
  };
}

function selectedVehicleToZplRow(vehicle) {
  const toyota = getToyotaMatch(vehicle) || {};
  const vinParts = splitVinPartsForZpl(vehicle);
  return [
    getSelectedZplBatch(vehicle),
    cleanZplField(vehicle.customerSurname || vehicle.client || ''),
    cleanZplField(vehicle.dealerCustomerName || vehicle.toyotaCustomer || toyota.toyotaCustomer || vehicle.dealerCustomer || ''),
    cleanZplField(vehicle.modelDescription || vehicle.toyotaVehicle || toyota.toyotaVehicle || vehicle.autocareModelDescription || vehicle.autocareModel || displayVehicle(vehicle) || vehicle.vehicle || ''),
    cleanZplField(vehicle.suffixDescription || vehicle.suffix || toyota.suffix || vehicle.autocareVersionDescription || ''),
    cleanZplField(vehicle.trimDescription || vehicle.trim || toyota.trim || ''),
    cleanZplField(vehicle.colourDescription || vehicle.colour || vehicle.color || toyota.colour || vehicle.autocareColour || ''),
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
  const authenticated = String(window.PDC_AUTH_CONTEXT?.displayName || window.PDC_AUTH_CONTEXT?.email || '').trim();
  if (authenticated) return authenticated;
  const saved = String(localStorage.getItem(OPERATOR_NAME_KEY) || '').trim();
  if (saved) return saved;
  const entered = window.prompt('Enter your name or initials for the PDC audit trail:', '') || '';
  const clean = entered.trim() || 'Unknown operator';
  try { localStorage.setItem(OPERATOR_NAME_KEY, clean); } catch {}
  return clean;
}

function getCurrentOperatorRole() {
  const authenticated = String(window.PDC_AUTH_CONTEXT?.role || '').trim();
  if (authenticated) return authenticated;
  const saved = String(localStorage.getItem(OPERATOR_ROLE_KEY) || '').trim();
  if (saved) return saved;
  const entered = window.prompt('Enter your department/role for the PDC audit trail (Tint, Hoist, Fitting, Fabrication, Electrical, Tyre bay, Pit Inspection, Parts, Manager):', '') || '';
  const clean = entered.trim() || 'Unassigned role';
  try { localStorage.setItem(OPERATOR_ROLE_KEY, clean); } catch {}
  return clean;
}

function setOperatorProfile() {
  if (window.PDC_AUTH_CONTEXT?.email) {
    window.alert(`Signed in as ${window.PDC_AUTH_CONTEXT.displayName || window.PDC_AUTH_CONTEXT.email} (${window.PDC_AUTH_CONTEXT.role}).`);
    return;
  }
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

function vehicleWorkshopHistoryLines(vehicle = {}) {
  const workshopActions = new Set([
    'Transferred to PMB',
    'PMB bucket moved',
    'Assigned to PMB bay',
    'Swapped PMB bay',
    'Removed from PMB bay',
    'Bay work completed',
    'Moved to next PMB station',
    'Job signed off',
  ]);
  return auditTrailForVehicle(vehicle)
    .filter(entry => workshopActions.has(cleanNavisionText(entry.action || '')))
    .reverse()
    .map(entry => {
      const details = entry.details || {};
      const when = parseIsoTimestamp(entry.at);
      const whenLabel = when ? when.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'Date not recorded';
      const movement = details.from || details.to ? [details.from, details.to].filter(Boolean).join(' → ') : '';
      const place = [details.stage, details.bay].map(cleanNavisionText).filter(Boolean).join(' · ');
      const work = cleanNavisionText(details.job || '');
      const assignee = cleanNavisionText(details.mechanic || details.provider || '');
      const hours = cleanNavisionText(details.hours || '');
      const extra = [movement, place, work, assignee ? `Mechanic/provider: ${assignee}` : '', hours ? `${hours}h` : ''].filter(Boolean).join(' · ');
      return `- ${whenLabel}: ${entry.action}${extra ? ` · ${extra}` : ''}`;
    });
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
  const requested = String(key ?? '').trim();
  if (!requested) return null;
  const canonicalMatches = app.data.filter(vehicle => String(vehicleKey(vehicle) || '').trim() === requested);
  if (canonicalMatches.length === 1) return canonicalMatches[0];
  if (canonicalMatches.length > 1) {
    console.warn('Vehicle lookup was ambiguous; no vehicle was selected.', { requested, matchCount: canonicalMatches.length });
    return null;
  }
  const aliasMatches = app.data.filter(vehicle => [vehicle.stock, vehicle.batch, vehicle.order, vehicle.id]
    .map(value => String(value || '').trim())
    .includes(requested));
  if (aliasMatches.length === 1) return aliasMatches[0];
  if (aliasMatches.length > 1) console.warn('Vehicle alias lookup was ambiguous; no vehicle was selected.', { requested, matchCount: aliasMatches.length });
  return null;
}

function saveVehicleEdits(key, updates, options = {}) {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return false;
  const editKey = vehicleKey(vehicle);
  const nextUpdates = { ...updates };
  if ('etaAtDealer' in nextUpdates) nextUpdates.etaAtDealer = navisionEtaForVehicle({ ...vehicle, ...nextUpdates });
  const wasNestedTransaction = storageTransactionDepth > 0;
  const previousValues = Object.fromEntries(Object.keys(nextUpdates).map(field => [field, {
    exists: Object.prototype.hasOwnProperty.call(vehicle, field),
    value: vehicle[field],
  }]));
  try {
    runStorageTransaction('Vehicle update', [EDITS_KEY], () => {
      Object.assign(vehicle, nextUpdates);
      const edits = loadVehicleEdits();
      edits[editKey] = { ...(edits[editKey] || {}), ...nextUpdates };
      saveJson(EDITS_KEY, edits);
    });
  } catch (error) {
    Object.entries(previousValues).forEach(([field, previous]) => {
      if (previous.exists) vehicle[field] = previous.value;
      else delete vehicle[field];
    });
    if (wasNestedTransaction) throw error;
    window.alert(error.message || String(error));
    return false;
  }
  if (options.render !== false) renderAll();
  return true;
}

function openVehicleModal(stock) {
  const vehicle = selectedVehicle(stock);
  if (!vehicle) {
    window.alert('That vehicle could not be found. Refresh the list and try again. No vehicle was changed.');
    return false;
  }
  app.selectedStock = vehicleKey(vehicle);
  renderDetail();
  const modal = $('#vehicle-modal');
  if (!modal) return;
  modal.hidden = false;
  document.body.classList.add('modal-open');
  $('#modal-close')?.focus();
  return true;
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
  if (!window.confirm(`Move ${label} to Deleted vehicles?\n\nThe record can still be reviewed on the Deleted vehicles screen.`)) return;

  removeVehiclesFromTracker([vehicle]);
  refreshAfterVehicleRemoval();
  closeVehicleModal();
}

function renderDetail() {
  const v = selectedVehicle();
  const panel = $('#vehicle-detail');
  if (!v || !panel) return;
  const key = vehicleKey(v);
  const notes = getNotes(key);
  const customerWarning = !isCustomerMatch(v);
  const isCompletedVehicle = statusCategory(v) === 'completed';
  const completedLockAttr = isCompletedVehicle ? 'disabled' : '';
  panel.innerHTML = `
    <div class="panel-header"><div><h2 id="vehicle-modal-title">Vehicle detail</h2><p>${stockLabel(v)} ${escapeHtml(displayStockNumber(v))}</p></div>${formatStatus(v)}</div>
    <div class="detail-body">
      <div class="detail-title">
        <div><h3>${escapeHtml(v.client || 'New customer')}</h3><p>${escapeHtml(displayVehicle(v))}</p></div>
        <div class="detail-actions">
          <button class="small-button vehicle-label-button" type="button" data-label-vehicle="${escapeHtml(key)}">Label</button>
          <button class="primary" type="button" data-email-vehicle-update="${escapeHtml(key)}">EMAIL UPDATE</button>
        </div>
      </div>
      <form class="edit-form" data-vehicle-edit-form>
        <div class="form-row three-col">
          <label>
            <span class="muted-label">SP</span>
            <select name="consultant">${salespersonOptionsHtml(consultantName(v))}</select>
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
        <div class="form-row one-col">
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
        <div class="pdc-work-state-grid" data-pdc-work-state-grid>
          ${PDC_JOB_DEFS.map(def => pdcJobTriStateControl(v, def, isCompletedVehicle)).join('')}
        </div>
        <div class="field-help pdc-work-state-help">Click each work item to cycle: grey = not required, red = to be completed, green = completed.</div>
        <div class="edit-actions">
          <button class="primary" type="submit">Save changes</button>
          <button class="ghost" type="button" data-modal-cancel>Cancel</button>
          <span class="save-message" data-save-message role="status" aria-live="polite"></span>
        </div>
      </form>
      ${renderPmbBayControlSection(v)}
      ${renderPoUploadSection(v)}
      ${renderPoTasksSection(v)}
      ${renderPdcJobLinesSection(v)}
      ${renderPurchaseOrderDetailSection(v)}
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
      <div class="detail-danger-zone">
        <div><strong>Move vehicle to Deleted vehicles</strong><span>Use this only for duplicate, cancelled or incorrectly imported records.</span></div>
        <button class="danger ghost" type="button" data-remove-vehicle="${escapeHtml(key)}">Delete vehicle</button>
      </div>
    </div>
  `;
  on($('[data-email-vehicle-update]', panel), 'click', () => draftSelectedVehicleStatusEmail(key));
  bindVehicleLabelButtons(panel);
  on($('[data-remove-vehicle]', panel), 'click', () => removeVehicle(key));
  on($('[data-modal-cancel]', panel), 'click', closeVehicleModal);
  on($('[data-vehicle-po-upload]', panel), 'change', (event) => handleVehiclePoSelect(key, event));
  $$('[data-confirm-pdc-job-line]', panel).forEach(button => {
    button.addEventListener('click', () => {
      const lineId = button.dataset.confirmPdcJobLine || '';
      const input = panel.querySelector(`[data-pdc-job-line-hours="${lineId}"]`);
      const stage = panel.querySelector(`[data-pdc-job-line-stage="${lineId}"]`);
      confirmPdcJobLineHours(key, lineId, input?.value || '', stage?.value || '');
    });
  });
  $$('[data-pdc-work-state]', panel).forEach(button => {
    button.addEventListener('click', () => {
      if (button.disabled) return;
      const current = button.dataset.state || 'none';
      const next = current === 'none' ? 'required' : current === 'required' ? 'complete' : 'none';
      button.dataset.state = next;
      button.classList.remove('pdc-work-state-none', 'pdc-work-state-required', 'pdc-work-state-complete');
      button.classList.add(`pdc-work-state-${next}`);
      const statusText = next === 'complete' ? 'Completed' : next === 'required' ? 'To be completed' : 'Not required';
      const status = button.querySelector('.pdc-work-state-status');
      if (status) status.textContent = statusText;
      const jobKey = button.dataset.pdcWorkState || '';
      const requireInput = panel.querySelector(`input[data-pdc-work-require="${jobKey}"]`);
      const completeInput = panel.querySelector(`input[data-pdc-work-complete="${jobKey}"]`);
      if (requireInput) requireInput.value = next === 'none' ? '0' : '1';
      if (completeInput) completeInput.value = next === 'complete' ? '1' : '0';
      const label = button.querySelector('.pdc-work-state-label')?.textContent || 'Work item';
      button.setAttribute('aria-label', `${label} - ${statusText}`);
      button.title = `${label} - ${statusText}. Click to cycle: grey not required, red to complete, green completed.`;
    });
  });
  $('[data-vehicle-edit-form]', panel).addEventListener('submit', (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const client = form.client.value.trim() || v.client;
    const keyNumber = statusCategory(v) === 'pmb' ? cleanNavisionText(form.keyNumber?.value || '') : vehicleKeyNumber(v);
    const consultant = form.consultant.value.trim();
    const internalStatus = v.internalStatus || '';
    const previousPdcLocation = vehiclePdcLocation(v);
    const previousPmbStage = normalizePmbStage(v.pmbStage || '');
    const previouslyPdcBlocked = isPdcBlocked(v);
    const pdcLocation = isCompletedVehicle ? previousPdcLocation : normalizePdcLocation(form.pdcLocation.value);
    const pmbStage = previousPmbStage;
    const pdcJobcard = cleanNavisionText(form.pdcJobcard?.value || '');
    const jitaPartsOrdered = form.jitaPartsOrdered.value;
    const pdcBlocked = Boolean(form.pdcBlocked?.checked);
    const pdcBlockReasonValue = cleanNavisionText(form.pdcBlockReason?.value || '');
    const requirementUpdates = {};
    const completionUpdates = {};
    PDC_JOB_DEFS.forEach(def => {
      requirementUpdates[def.requireKey] = isCompletedVehicle ? pdcJobRequired(v, def) : form[def.requireKey]?.value === '1';
      completionUpdates[def.completeKey] = isCompletedVehicle ? pdcJobComplete(v, def) : form[def.completeKey]?.value === '1';
    });
    const duplicateKeyVehicle = pdcLocation === 'PMB' ? activePmbVehicleWithKeyNumber(keyNumber, key) : null;
    if (duplicateKeyVehicle) {
      window.alert(`Key tag ${keyNumber} is already assigned to ${displayStockNumber(duplicateKeyVehicle) || duplicateKeyVehicle.order || 'another PMB vehicle'}. Only one active PMB vehicle can use a key tag number at a time.`);
      return;
    }
    const updates = { client, keyNumber, pdcJobcard, consultant, internalStatus, pdcLocation, pmbStage, jitaPartsOrdered, pdcBlocked, pdcBlockReason: pdcBlockReasonValue, ...requirementUpdates, ...completionUpdates };
    const hasIndependentPdcWork = Boolean(
      pdcJobcard || pdcLocation || pdcBlocked ||
      PDC_JOB_DEFS.some(def => requirementUpdates[def.requireKey] || completionUpdates[def.completeKey])
    );
    if (hasIndependentPdcWork) Object.assign(updates, pdcVisibilityPromotionUpdates(v, pdcJobcard ? 'Operator job card / PDC work update' : 'Operator PDC work update'));
    const changedCompletions = PDC_JOB_DEFS.filter(def => pdcJobComplete(v, def) !== completionUpdates[def.completeKey]);
    const changedRequirements = PDC_JOB_DEFS.filter(def => pdcJobRequired(v, def) !== requirementUpdates[def.requireKey]);
    if (changedCompletions.length || changedRequirements.length) {
      Object.assign(updates, { pdcQcComplete: false, pdcQcCompleteAt: '', pdcQcCompleteBy: '' });
    }
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
    const newlyCompleted = changedCompletions.filter(def => completionUpdates[def.completeKey]);
    const stoppageAdded = !previouslyPdcBlocked && pdcBlocked;
    if (newlyCompleted.length || stoppageAdded) {
      const notificationTitle = stoppageAdded
        ? 'PDC stoppage recorded'
        : newlyCompleted.length === 1
          ? `${newlyCompleted[0].label} completed`
          : `${newlyCompleted.length} PDC jobs completed`;
      offerSalespersonChangeEmail(v, {
        title: notificationTitle,
        subject: stoppageAdded ? 'PDC stoppage update' : 'PDC work completed',
        details: [
          ...newlyCompleted.map(def => `${def.label} was signed off by ${getCurrentOperatorName()}.`),
          stoppageAdded ? `Reason: ${pdcBlockReasonValue || 'Blocked'}` : '',
        ],
      });
    }
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

function pdcJobLineIdentity(line = {}) {
  if (cleanNavisionText(line.id || '')) return cleanNavisionText(line.id);
  const source = [line.code, line.description, Number(line.quantity || 1)].join('|').toUpperCase();
  let hash = 5381;
  for (let index = 0; index < source.length; index += 1) hash = ((hash << 5) + hash) ^ source.charCodeAt(index);
  return `jobline-${(hash >>> 0).toString(16).padStart(8, '0')}`;
}

function pdcJobLineStage(line = {}) {
  const requested = normalizePmbStage(line.category || line.stage || line.suggestedStage || '');
  if (PDC_JOB_LINE_STAGE_OPTIONS.some(option => option.value === requested)) return requested;
  const value = `${line.code || ''} ${line.description || ''}`;
  if (/\btint\b/i.test(value)) return 'TINT';
  if (/\b(?:tyres?|tires?|wheel alignment|alignment)\b/i.test(value)) return 'TYRE';
  if (/\b(?:electrical|driving lights?|light bar|dual battery|battery system|uhf|antenna|reverse alarm|brake controller|wiring|solis)\b/i.test(value)) return 'ELECTRICAL';
  if (/\b(?:bull\s*bar|nudge\s*bar|tow\s*bar|winch|canopy|snorkel|side rails?|side steps?|seat covers?|floor mats?|dash mat|recovery point|roof rack|fold step|fit(?:ting)?)\b/i.test(value)) return 'FITTING';
  if (/\b(?:fabricat|tray|module|service body|rops|tool ?box|jacking points?|water tank|mine bar|weld)\b/i.test(value)) return 'FABRICATION';
  if (/\b(?:suspension|gvm|lift kit|weight upgrade)\b/i.test(value)) return 'HOIST';
  if (/\b(?:pit inspection|pit and weigh|quality check)\b/i.test(value)) return 'PIT_INSPECTION';
  if (/\bbus\s*4\s*x\s*4\b/i.test(value)) return 'BUS_4X4';
  return 'FITTING';
}

function pdcJobLineStageOptionsHtml(current = '') {
  const selected = normalizePmbStage(current);
  return PDC_JOB_LINE_STAGE_OPTIONS.map(option => `<option value="${escapeHtml(option.value)}"${option.value === selected ? ' selected' : ''}>${escapeHtml(option.label)}</option>`).join('');
}

function mergePdcJobLines(...groups) {
  const merged = new Map();
  groups.flat().filter(line => line && typeof line === 'object').forEach(line => {
    const id = pdcJobLineIdentity(line);
    merged.set(id, { ...(merged.get(id) || {}), ...line, id });
  });
  return [...merged.values()];
}

function arbEstimateForJobLine(code = '', description = '', quantity = 1) {
  const entries = ARB_LABOUR_CATALOG.entries || {};
  const ambiguous = ARB_LABOUR_CATALOG.ambiguous || {};
  const tokens = [code, description].join(' ').toUpperCase().match(/\b[A-Z0-9][A-Z0-9-]{2,39}\b/g) || [];
  const matchedCodes = [...new Set(tokens.filter(token => entries[token]))];
  const candidateHours = [...new Set(matchedCodes.map(token => Number(entries[token]?.hours || 0)).filter(hours => hours > 0))];
  const normalizedQuantity = Math.max(0.01, Number(quantity || 1));
  if (matchedCodes.length === 1 && candidateHours.length === 1) {
    const matchedCode = matchedCodes[0];
    const entry = entries[matchedCode];
    const fittingCharge = Number(entry.fittingCharge || 0);
    const rateDetail = fittingCharge
      ? ` · $${fittingCharge} ÷ $${Number(ARB_LABOUR_CATALOG.labourRate || 160)}/h (rate p${ARB_LABOUR_CATALOG.labourRateSourcePage || '?'})`
      : ' · explicit catalogue fit time';
    return {
      estimatedHours: Number((candidateHours[0] * normalizedQuantity).toFixed(4)),
      estimateStatus: 'provisional',
      estimateSource: `${ARB_LABOUR_CATALOG.sourceCode || 'ARB catalogue'} · ${matchedCode} · page ${entry.page || '?'}${rateDetail}`,
      estimateMethod: entry.method || 'catalogue',
      catalogHoursEach: candidateHours[0],
    };
  }
  const ambiguousCode = tokens.find(token => ambiguous[token]);
  return {
    estimatedHours: null,
    estimateStatus: 'review-required',
    estimateSource: ambiguousCode
      ? `${ARB_LABOUR_CATALOG.sourceCode || 'ARB catalogue'} · ${ambiguousCode} has vehicle-dependent fitting times`
      : (matchedCodes.length > 1 ? `${ARB_LABOUR_CATALOG.sourceCode || 'ARB catalogue'} · multiple product codes require line-by-line review` : ''),
    estimateMethod: '',
    catalogHoursEach: null,
  };
}

function pdcJobLineFromPurchaseOrderItem(item = {}) {
  const code = cleanNavisionText(item.item || item.code || '').toUpperCase();
  const description = cleanNavisionText(item.description || 'Purchase order work item');
  const quantity = Math.max(0.01, Number(item.quantity || 1));
  const estimate = arbEstimateForJobLine(code, description, quantity);
  const line = {
    code,
    description,
    quantity,
    source: 'Reviewed PO upload',
    ...estimate,
  };
  line.id = pdcJobLineIdentity(line);
  return line;
}

function vehiclePdcJobLines(vehicle = {}) {
  const reviews = vehicle.pdcJobLineReviews && typeof vehicle.pdcJobLineReviews === 'object' ? vehicle.pdcJobLineReviews : {};
  return mergePdcJobLines(vehicle.pdcJobLines || [], vehicle.pdcManualJobLines || []).map(line => {
    const review = reviews[pdcJobLineIdentity(line)] || {};
    return { ...line, ...review, id: pdcJobLineIdentity(line) };
  });
}

function validPdcJobLineHours(value) {
  const hours = Number(value);
  return Number.isFinite(hours) && hours >= (1 / 12) && hours <= 40 ? Number(hours.toFixed(2)) : null;
}

function renderPdcJobLinesSection(vehicle) {
  const lines = vehiclePdcJobLines(vehicle);
  if (!lines.length) return '';
  const completedLocked = vehicleCollectedFromRft(vehicle);
  const confirmed = lines.filter(line => line.confirmed === true).length;
  const total = lines.reduce((sum, line) => sum + (Number(line.confirmedHours ?? line.estimatedHours) || 0), 0);
  return `<section class="pdc-job-lines-panel">
    <div class="pdc-job-lines-header">
      <div><div class="muted-label">Job card / PO work and estimated hours</div><div class="subtle">${completedLocked ? 'Completed vehicle — job-line hours are locked.' : 'Orange estimates require confirmation. Adjust the hours beside each job line, then confirm.'}</div></div>
      <strong>${confirmed}/${lines.length} confirmed · ${total.toFixed(2).replace(/\.00$/, '')}h total</strong>
    </div>
    <div class="pdc-job-line-list">${lines.map(line => {
      const isConfirmed = line.confirmed === true;
      const hours = isConfirmed ? line.confirmedHours : line.estimatedHours;
      const source = cleanNavisionText(line.estimateSource || (line.estimatedHours == null ? 'No safe catalogue match — enter hours for review' : 'ARB catalogue estimate'));
      return `<div class="pdc-job-line ${isConfirmed ? 'is-confirmed' : 'is-provisional'}" data-pdc-job-line="${escapeHtml(line.id)}">
        <div class="pdc-job-line-copy">
          <strong>${line.code ? `<span>${escapeHtml(line.code)}</span> · ` : ''}${escapeHtml(line.description || 'Work item')}</strong>
          <small>Qty ${escapeHtml(String(line.quantity || 1))} · ${escapeHtml(source)}</small>
        </div>
        <label><span>Category</span><select data-pdc-job-line-stage="${escapeHtml(line.id)}" ${completedLocked ? 'disabled' : ''}>${pdcJobLineStageOptionsHtml(pdcJobLineStage(line))}</select></label>
        <label><span>Hours</span><input type="number" min="0.08" max="40" step="0.25" value="${hours == null ? '' : escapeHtml(String(hours))}" placeholder="Enter" data-pdc-job-line-hours="${escapeHtml(line.id)}" ${completedLocked ? 'disabled' : ''} /></label>
        <button class="${isConfirmed ? 'ghost' : 'primary'}" type="button" data-confirm-pdc-job-line="${escapeHtml(line.id)}" ${completedLocked ? 'disabled' : ''}>${isConfirmed ? 'Update confirmed' : 'Confirm hours'}</button>
      </div>`;
    }).join('')}</div>
  </section>`;
}

function confirmPdcJobLineHours(vehicleKeyValue, lineId, rawHours, rawStage = '') {
  const vehicle = selectedVehicle(vehicleKeyValue);
  if (!vehicle) return false;
  if (vehicleCollectedFromRft(vehicle)) {
    window.alert('This vehicle is completed/collected. Job-line hours are locked and were not changed.');
    return false;
  }
  const line = vehiclePdcJobLines(vehicle).find(item => item.id === lineId);
  if (!line) return false;
  const hours = validPdcJobLineHours(rawHours);
  if (hours == null) {
    window.alert('Enter estimated hours from 0.08 to 40 before confirming this job line.');
    return false;
  }
  const stage = normalizePmbStage(rawStage || pdcJobLineStage(line));
  if (!PDC_JOB_LINE_STAGE_OPTIONS.some(option => option.value === stage)) {
    window.alert('Choose a workshop category before confirming this job line.');
    return false;
  }
  const operator = getCurrentOperatorName();
  if (!operator || operator === 'Unknown operator') {
    window.alert('Set an operator name before confirming job-line hours. No hours were saved.');
    return false;
  }
  const role = getCurrentOperatorRole();
  const key = vehicleKey(vehicle);
  const previousReviews = vehicle.pdcJobLineReviews;
  const nextReviews = {
    ...(previousReviews || {}),
    [lineId]: {
      confirmed: true,
      confirmedHours: hours,
      confirmedAt: nowIsoString(),
      confirmedBy: operator,
      estimateStatus: 'confirmed',
      category: stage,
    },
  };
  try {
    runStorageTransaction('Confirm job-line hours', [EDITS_KEY, AUDIT_LOG_KEY], () => {
      vehicle.pdcJobLineReviews = nextReviews;
      const edits = loadVehicleEdits();
      edits[key] = { ...(edits[key] || {}), pdcJobLineReviews: nextReviews };
      saveJson(EDITS_KEY, edits);
      recordVehicleAudit(vehicle, line.confirmed === true ? 'Confirmed job-line hours updated' : 'Provisional job-line hours confirmed', {
        job: line.description || line.code || 'Work item',
        code: line.code || '',
        hours,
        previousHours: line.confirmedHours ?? line.estimatedHours ?? '',
        category: stage,
        by: operator,
        role,
      });
    });
  } catch (error) {
    if (previousReviews === undefined) delete vehicle.pdcJobLineReviews;
    else vehicle.pdcJobLineReviews = previousReviews;
    window.alert(error.message || String(error));
    return false;
  }
  app.data = buildVehicleData();
  app.selectedStock = key;
  renderAll();
  renderDetail();
  return true;
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

function renderPurchaseOrderDetailSection(vehicle) {
  if (!vehicle.purchaseOrderNumber) return '';
  const fields = [
    ['PO number', vehicle.purchaseOrderNumber],
    ['Due date', vehicle.purchaseOrderDueDate],
    ['Issued by', vehicle.purchaseOrderIssuedBy],
    ['Department', vehicle.purchaseOrderDepartment],
    ['Reference', vehicle.purchaseOrderReference],
    ['Deliver to', vehicle.purchaseOrderDeliverTo],
    ['Model code', vehicle.purchaseOrderModelCode],
    ['Colour', [vehicle.purchaseOrderColourCode, vehicle.colour].filter(Boolean).join(' ')],
    ['Trim', [vehicle.purchaseOrderTrimCode, vehicle.trim].filter(Boolean).join(' ')],
    ['Factory option', vehicle.purchaseOrderFactoryOption],
    ['Alternate model', vehicle.purchaseOrderAlternateModel],
    ['Engine', vehicle.purchaseOrderEngine],
    ['Build date', vehicle.purchaseOrderBuildDate],
    ['VIN', vehicle.vin],
    ['Total inc. GST', vehicle.purchaseOrderTotalIncGst ? `$${vehicle.purchaseOrderTotalIncGst}` : ''],
  ].filter(([, value]) => cleanNavisionText(value));
  return `<section class="navision-detail-panel purchase-order-detail-panel">
    <div class="muted-label">Purchase order vehicle details</div>
    <div class="navision-field-grid">
      ${fields.map(([label, value]) => `<div class="navision-field"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join('')}
    </div>
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
  const pipelineVehicles = pdcSheetVehicles().filter(vehicle => getStage(vehicle) !== 'Needs Matching');
  const grouped = groupBy(pipelineVehicles, getStage);
  $('#pipeline-count').textContent = `${pipelineVehicles.length} vehicles`;
  $('#kanban').innerHTML = stages.map(stage => {
    const vehicles = (grouped[stage] || []).slice().sort((a, b) => toyotaStatusRank(a.toyotaStatus) - toyotaStatusRank(b.toyotaStatus) || String(displayStockNumber(a)).localeCompare(String(displayStockNumber(b)), 'en-AU', { numeric: true }));
    return `<details class="pipeline-section" open>
      <summary class="pipeline-summary"><strong>${escapeHtml(stage)}</strong><span class="badge neutral">${vehicles.length}</span></summary>
      <div class="pdc-production-grid-scroll pipeline-production-grid">
        ${vehicles.length ? productionGridHeaderHtml('pipeline-production-grid-header', { meta1Label: 'Sales / order', meta2Label: 'Location / ETA', actionLabel: 'Open' }) : ''}
        <div class="pdc-production-grid-body pipeline-list">
          ${vehicles.map(v => `<button class="kanban-card pipeline-card pdc-production-grid-row pdc-production-grid-static-row" type="button" data-stock="${escapeHtml(vehicleKey(v))}">
            <span class="pdc-grid-control" aria-hidden="true">›</span><span class="pdc-grid-select-spacer" aria-hidden="true"></span>
            <span class="incoming-card-stock">${vehicleIdentityStackHtml(v)}</span>
            <span class="incoming-card-main"><strong>${escapeHtml(displayVehicle(v) || 'Vehicle not listed')}</strong></span>
            <span class="incoming-card-work-wrap">${incomingWorkChecklistHtml(v)}</span>
            <span class="incoming-card-meta"><b>Sales</b><span>${escapeHtml(salesPersonInitials(consultantName(v)) || '—')}</span><small>Order ${escapeHtml(v.order || '—')}</small></span>
            <span class="incoming-card-meta"><b>Location</b><span>${escapeHtml(pdcLocationLabel(v.pdcLocation) || v.toyotaStatus || 'Not matched')}</span><small>${scotEtaOnly(v.etaAtDealer) ? `ETA ${escapeHtml(scotEtaOnly(v.etaAtDealer))}` : ''}</small></span>
            <span class="incoming-card-action"><span class="small-button">Open</span></span>
          </button>`).join('') || '<div class="subtle pdc-grid-empty-row">No vehicles in this stage.</div>'}
        </div>
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
  return pdcSheetVehicles()
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
  host.innerHTML = `<section class="schedule-list-panel pdc-grid-page-section">
    <div class="schedule-list-header"><strong>Production / In Transit</strong><span>Sorted by earliest ETA At Kewdale Yard first</span></div>
    <div class="pdc-production-grid-scroll">
      ${productionGridHeaderHtml('schedule-production-grid-header', { meta1Label: 'ETA Kewdale', meta2Label: 'Current stage', actionLabel: 'Readiness' })}
      <div class="pdc-production-grid-body" role="list">
        ${rows.map(({ vehicle, departments, readiness }, index) => {
          const stage = `${statusCategoryLabel(vehicle)}${inferredPmbStage(vehicle) ? ` · ${pmbStageLabel(inferredPmbStage(vehicle))}` : ''}`;
          const readinessTitle = readiness.length ? readiness.map(item => item.label).join(' · ') : 'Ready prompts clear';
          return `<button class="pdc-production-grid-row pdc-production-grid-static-row schedule-production-row" type="button" role="listitem" data-stock="${escapeHtml(vehicleKey(vehicle))}" title="${escapeHtml(readinessTitle)}">
            <span class="pdc-grid-control pdc-grid-rank">${escapeHtml(String(index + 1).padStart(2, '0'))}</span>
            <span class="pdc-grid-select-spacer" aria-hidden="true"></span>
            <span class="incoming-card-stock">${vehicleIdentityStackHtml(vehicle)}</span>
            <span class="incoming-card-main"><strong>${escapeHtml(displayVehicle(vehicle) || 'Vehicle not listed')}</strong></span>
            <span class="incoming-card-work-wrap">${incomingWorkChecklistHtml(vehicle)}</span>
            <span class="incoming-card-meta"><b>ETA</b><span>${escapeHtml(kewdaleEtaValue(vehicle) || 'No ETA')}</span><small>${escapeHtml(pmbAgeLabel(vehicle))}</small></span>
            <span class="incoming-card-meta"><b>Stage</b><span>${escapeHtml(stage)}</span></span>
            <span class="incoming-card-action schedule-grid-readiness">${scheduleReadinessHtml(readiness)}</span>
          </button>`;
        }).join('')}
      </div>
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
  if (description) description.textContent = `${def.label} focused work list. Use the row actions to sign off work, record stoppages, or open the vehicle details.`;
  if (count) count.textContent = `${rows.length} vehicle${rows.length === 1 ? '' : 's'} · ${capacity}`;
  if (help) help.innerHTML = `<strong>${escapeHtml(def.label)}</strong><span>Capacity: ${escapeHtml(capacity)}</span><span>Sort: stoppages first, then earliest Kewdale ETA.</span>`;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No vehicles match this department filter</strong><span>Clear search or change the status filter.</span></div>';
    return;
  }
  host.innerHTML = `<div class="pdc-production-grid-scroll department-production-grid">
    ${productionGridHeaderHtml('department-production-grid-header', { meta1Label: 'Station status', meta2Label: 'ETA / age', actionLabel: 'Actions' })}
    <div class="pdc-production-grid-body" role="list">
      ${rows.map(vehicle => {
        const key = vehicleKey(vehicle);
        const complete = productionDepartmentComplete(vehicle, def);
        return `<article class="pdc-production-grid-row pdc-production-grid-static-row department-job-card ${departmentVehicleStatus(vehicle, def)}" role="listitem">
          <span class="pdc-grid-control" aria-hidden="true">›</span>
          <span class="pdc-grid-select-spacer" aria-hidden="true"></span>
          <span class="incoming-card-stock">${vehicleIdentityStackHtml(vehicle)}</span>
          <span class="incoming-card-main"><strong>${escapeHtml(displayVehicle(vehicle) || 'Vehicle not listed')}</strong></span>
          <span class="incoming-card-work-wrap">${incomingWorkChecklistHtml(vehicle)}</span>
          <span class="incoming-card-meta department-grid-status"><b>${escapeHtml(def.label)}</b>${departmentStatusBadgeHtml(vehicle, def)}<small>Current: ${escapeHtml(pmbStageLabel(inferredPmbStage(vehicle)) || statusCategoryLabel(vehicle))}</small></span>
          <span class="incoming-card-meta"><b>ETA</b><span>${escapeHtml(kewdaleEtaValue(vehicle) || 'No ETA')}</span><small>${escapeHtml(pmbAgeLabel(vehicle))}</small></span>
          <span class="incoming-card-action department-actions">
            ${complete ? `<button type="button" class="small-button" data-dept-next="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Next bay</button>` : `<button type="button" class="primary" data-dept-complete="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Complete</button>`}
            <button type="button" class="small-button" data-dept-stoppage="${escapeHtml(key)}" data-dept-stage="${escapeHtml(def.stage)}">Stoppage</button>
            ${isPdcBlocked(vehicle) ? `<button type="button" class="small-button" data-dept-clear-stoppage="${escapeHtml(key)}">Clear</button>` : ''}
            <button type="button" class="small-button" data-dept-open="${escapeHtml(key)}">Open</button>
          </span>
        </article>`;
      }).join('')}
    </div>
  </div>`;
  $$('[data-dept-complete]', host).forEach(button => button.addEventListener('click', () => completePmbBayWork(button.dataset.deptComplete, button.dataset.deptStage)));
  $$('[data-dept-next]', host).forEach(button => button.addEventListener('click', () => moveVehicleToNextPmbStageFromBay(button.dataset.deptNext, button.dataset.deptStage)));
  $$('[data-dept-stoppage]', host).forEach(button => button.addEventListener('click', () => markProductionDepartmentStoppage(button.dataset.deptStoppage, button.dataset.deptStage)));
  $$('[data-dept-clear-stoppage]', host).forEach(button => button.addEventListener('click', () => clearProductionDepartmentStoppage(button.dataset.deptClearStoppage)));
  $$('[data-dept-open]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.deptOpen)));
}

function markProductionDepartmentStoppage(key = '', stage = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const normalizedStage = normalizePmbStage(stage || inferredPmbStage(vehicle));
  if (!normalizedStage) return;
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
  offerSalespersonChangeEmail(vehicle, {
    title: `${pmbStageLabel(normalizedStage)} stoppage recorded`,
    subject: 'PDC stoppage update',
    details: [`Reason: ${reason}`, `Recorded by ${operator}.`],
  });
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

function partsWorstEtaValue(vehicle = {}) {
  return cleanNavisionText(vehicle.pdcPartsWorstEta || vehicle.partsWorstEta || '');
}

function partsWorstEtaDate(vehicle = {}) {
  const value = partsWorstEtaValue(vehicle);
  if (!value) return null;
  const isoDate = String(value).match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoDate) return new Date(Number(isoDate[1]), Number(isoDate[2]) - 1, Number(isoDate[3]));
  return parseDateAU(value) || parseIsoTimestamp(value);
}

function partsWorstEtaInputValue(vehicle = {}) {
  const value = partsWorstEtaValue(vehicle);
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const date = partsWorstEtaDate(vehicle);
  if (!date) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function partsWorstEtaLabel(vehicle = {}) {
  const value = partsWorstEtaValue(vehicle);
  if (!value) return '';
  const date = partsWorstEtaDate(vehicle);
  if (date) return date.toLocaleDateString('en-AU', { day: '2-digit', month: '2-digit', year: 'numeric' });
  return value;
}

function partsWorstEtaDaysUntil(vehicle = {}) {
  const date = partsWorstEtaDate(vehicle);
  if (!date) return null;
  const target = new Date(date);
  target.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target - today) / (1000 * 60 * 60 * 24));
}

function partsWorstEtaCountdownLabel(vehicle = {}) {
  const days = partsWorstEtaDaysUntil(vehicle);
  if (days === null) return '';
  if (days < 0) return `${Math.abs(days)} day${Math.abs(days) === 1 ? '' : 's'} overdue`;
  if (days === 0) return 'Due today';
  return `${days} day${days === 1 ? '' : 's'} to Parts ETA`;
}

function partsWorstEtaCountdownClass(vehicle = {}) {
  const days = partsWorstEtaDaysUntil(vehicle);
  if (days === null) return 'unset';
  if (days < 0) return 'overdue';
  if (days <= 7) return 'soon';
  return 'later';
}

function partsWorstEtaSortValue(vehicle = {}) {
  const date = partsWorstEtaDate(vehicle);
  return date ? date.getTime() : -8640000000000000;
}

function partsEtaRisk(vehicle = {}) {
  const partsDate = partsWorstEtaDate(vehicle);
  const kewdaleDate = parseDateAU(kewdaleEtaValue(vehicle));
  if (!partsDate || !kewdaleDate) return false;
  const partsDay = new Date(partsDate); partsDay.setHours(0, 0, 0, 0);
  const kewdaleDay = new Date(kewdaleDate); kewdaleDay.setHours(0, 0, 0, 0);
  return partsDay > kewdaleDay;
}

function partsRiskBadge(vehicle = {}) {
  return partsEtaRisk(vehicle) ? `<span class="badge parts-risk-badge" title="Parts ETA is later than Kewdale ETA">PARTS RISK</span>` : '';
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

function partsCurrentLocationLabel(vehicle = {}) {
  if (vehicleCollectedFromRft(vehicle)) return 'Completed';
  const category = statusCategory(vehicle);
  const location = vehiclePdcLocation(vehicle);
  if (location === 'PMB' || category === 'pmb') {
    const stage = normalizePmbStage(vehicle.pmbBayStage || inferredPmbStage(vehicle));
    if (!stage) return 'PMB · Unallocated';
    if (stage === 'SUBLET') {
      const provider = pmbBaySubletProvider(vehicle);
      return provider ? `Sublet · ${provider}` : 'Sublet';
    }
    const bay = pmbBayNumber(vehicle, stage);
    return `${pmbStageLabel(stage)} · ${bay ? `Bay ${String(bay).padStart(2, '0')}` : 'No bay'}`;
  }
  if (location === 'YH') return 'Yard Hold';
  if (location === 'RFT') return 'RFT';
  if (location) return pdcLocationLabel(location);
  return {
    yardhold: 'Yard Hold',
    rft: 'RFT',
    transit: 'In Transit',
    overseas: 'Overseas / Other',
    completed: 'Completed',
  }[category] || statusCategoryLabel(vehicle) || 'Current location unknown';
}

function partsCurrentLocationUpdateLabel(vehicle = {}) {
  const category = statusCategory(vehicle);
  const location = vehiclePdcLocation(vehicle);
  let values = [];
  if (vehicleCollectedFromRft(vehicle)) {
    values = [vehicle.rftCollectedAt, vehicle.rftTransferredAt, vehicle.pdcLocationUpdatedAt];
  } else if (location === 'PMB' || category === 'pmb') {
    values = [
      vehicle.pmbBayEnteredAt,
      vehicle.pmbStageUpdatedAt,
      vehicle.pmbStageEnteredAt,
      vehicle.pmbEnteredAt,
      vehicle.pmbTransferredAt,
      vehicle.pdcLocationUpdatedAt,
    ];
  } else if (location === 'RFT' || category === 'rft') {
    values = [vehicle.rftTransferredAt, vehicle.pdcLocationUpdatedAt];
  } else {
    values = [vehicle.pdcLocationUpdatedAt];
  }
  const latest = values.map(parseIsoTimestamp).filter(Boolean).sort((a, b) => b - a)[0];
  return latest ? latest.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '';
}

function partsDepartmentRows() {
  const q = ($('#parts-search')?.value || '').trim().toLowerCase();
  const selectedFilter = $('#parts-status-filter')?.value || 'open';
  const etaFilter = $('#parts-eta-filter')?.value || 'all';
  const departmentFilter = $('#parts-department-filter')?.value || '';
  const etaSort = $('#parts-eta-sort')?.value || 'status';
  const filter = ['issued', 'notrequired'].includes(selectedFilter) ? 'open' : selectedFilter;
  return pdcSheetVehicles()
    .filter(vehicleHasBatchNumber)
    .filter(vehicle => {
      const status = partsDepartmentStatus(vehicle);
      const matchesStatus = (filter === 'all' && !['issued', 'notrequired'].includes(status))
        || (filter === 'open' && !['issued', 'notrequired'].includes(status))
        || (!['all', 'open'].includes(filter) && status === filter);
      if (!matchesStatus) return false;
      if (departmentFilter && vehicleDepartmentCode(vehicle) !== departmentFilter) return false;
      const etaDays = partsWorstEtaDaysUntil(vehicle);
      if (etaFilter === 'risk' && !partsEtaRisk(vehicle)) return false;
      if (etaFilter === 'overdue' && !(etaDays !== null && etaDays < 0)) return false;
      if (etaFilter === 'none' && partsWorstEtaValue(vehicle)) return false;
      if (!q) return true;
      const productionLabel = productionMonthLabel(vehicle.prodMth || vehicle.productionMonth || '');
      const hay = [
        displayStockNumber(vehicle), vehicle.order, vehicle.client, vehicle.toyotaCustomer, displayVehicle(vehicle),
        pdcLocationLabel(vehiclePdcLocation(vehicle)),
        partsCurrentLocationLabel(vehicle), statusCategoryLabel(vehicle), partsDepartmentStatusLabel(status), partsStoppageReason(vehicle), productionLabel,
        kewdaleEtaValue(vehicle), partsEtaCounterLabel(vehicle), partsWorstEtaLabel(vehicle), partsWorstEtaValue(vehicle),
        vehicleDepartmentLabel(vehicle), partsEtaRisk(vehicle) ? 'parts risk' : ''
      ].join(' ').toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => {
      if (etaSort === 'nearest' || etaSort === 'latest') {
        const missing = etaSort === 'nearest' ? 8640000000000000 : -8640000000000000;
        const aEta = partsWorstEtaDate(a)?.getTime() ?? missing;
        const bEta = partsWorstEtaDate(b)?.getTime() ?? missing;
        if (aEta !== bEta) return etaSort === 'nearest' ? aEta - bEta : bEta - aEta;
      }
      const rank = { miscacc: 0, stoppage: 1, notordered: 2, onorder: 3, issued: 4, notrequired: 5 };
      const rankDiff = (rank[partsDepartmentStatus(a)] ?? 9) - (rank[partsDepartmentStatus(b)] ?? 9);
      if (rankDiff) return rankDiff;
      if (partsDepartmentStatus(a) === 'stoppage' && partsDepartmentStatus(b) === 'stoppage') {
        const etaDiff = partsWorstEtaSortValue(a) - partsWorstEtaSortValue(b);
        if (etaDiff) return etaDiff;
      }
      const ageA = pmbAgeDays(a);
      const ageB = pmbAgeDays(b);
      if (ageA !== null || ageB !== null) return (ageB ?? -9999) - (ageA ?? -9999);
      return String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || ''), undefined, { numeric: true });
    });
}

function renderPartsSummary(rows = []) {
  const all = pdcSheetVehicles().filter(vehicleHasBatchNumber);
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

function partsQueueActionsHtml(vehicle = {}, status = partsDepartmentStatus(vehicle)) {
  const key = vehicleKey(vehicle);
  const stock = displayStockNumber(vehicle) || key;
  const complete = ['issued', 'notrequired'].includes(status);
  const showEmailSales = Boolean(partsWorstEtaLabel(vehicle)) && !complete;
  let primaryAction = '';
  const moreActions = [];
  if (status === 'notordered') {
    primaryAction = `<button class="small-button primary" type="button" data-parts-ordered="${escapeHtml(key)}" aria-label="Mark parts ordered for ${escapeHtml(stock)}">Mark ordered</button>`;
    moreActions.push(`<button class="small-button" type="button" data-parts-complete="${escapeHtml(key)}">Complete</button>`);
    moreActions.push(`<button class="small-button danger-button" type="button" data-parts-stoppage="${escapeHtml(key)}">Stoppage</button>`);
    moreActions.push(`<button class="small-button" type="button" data-open-stock="${escapeHtml(key)}">Open vehicle</button>`);
  } else if (status === 'stoppage') {
    primaryAction = `<button class="small-button primary" type="button" data-open-stock="${escapeHtml(key)}">Review stoppage</button>`;
    moreActions.push(`<button class="small-button" type="button" data-parts-clear-stoppage="${escapeHtml(key)}">Clear stoppage</button>`);
    moreActions.push(`<button class="small-button" type="button" data-parts-complete="${escapeHtml(key)}">Complete</button>`);
  } else if (complete) {
    primaryAction = `<button class="small-button primary" type="button" data-open-stock="${escapeHtml(key)}">Open vehicle</button>`;
  } else {
    primaryAction = `<button class="small-button primary" type="button" data-parts-complete="${escapeHtml(key)}">Complete</button>`;
    moreActions.push(`<button class="small-button danger-button" type="button" data-parts-stoppage="${escapeHtml(key)}">Stoppage</button>`);
    moreActions.push(`<button class="small-button" type="button" data-open-stock="${escapeHtml(key)}">Open vehicle</button>`);
  }
  const moreMenu = moreActions.length ? `<button class="small-button parts-more-button" type="button" data-parts-more-button aria-expanded="false">More</button><template data-parts-more-template><div class="parts-more-popover" role="group" aria-label="More parts actions for ${escapeHtml(stock)}">${moreActions.join('')}</div></template>` : '';
  const emailSales = showEmailSales ? `<div class="parts-email-sales-secondary"><button class="small-button parts-email-sales-button" type="button" data-parts-eta-email="${escapeHtml(key)}">Email sales</button></div>` : '';
  return `<div class="parts-action-group"><div class="parts-action-primary">${primaryAction}${moreMenu}</div>${emailSales}</div>`;
}

function closePartsMoreMenu({ restoreFocus = false } = {}) {
  const current = app.partsMoreMenu;
  if (!current) return;
  current.popover?.remove();
  current.trigger?.setAttribute('aria-expanded', 'false');
  if (restoreFocus) current.trigger?.focus();
  app.partsMoreMenu = null;
}

function bindPartsQueueActionButtons(host) {
  if (!host) return;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  $$('[data-parts-ordered]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsOrdered(button.dataset.partsOrdered)));
  $$('[data-parts-complete]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsComplete(button.dataset.partsComplete)));
  $$('[data-parts-stoppage]', host).forEach(button => button.addEventListener('click', () => markVehiclePartsStoppage(button.dataset.partsStoppage)));
  $$('[data-parts-clear-stoppage]', host).forEach(button => button.addEventListener('click', () => clearVehiclePartsStoppage(button.dataset.partsClearStoppage)));
  $$('[data-parts-eta-email]', host).forEach(button => button.addEventListener('click', () => draftPartsEtaSalesEmail(button.dataset.partsEtaEmail)));
}

function openPartsMoreMenu(trigger) {
  closePartsMoreMenu();
  const template = trigger?.parentElement?.querySelector('[data-parts-more-template]');
  const popover = template?.content?.firstElementChild?.cloneNode(true);
  if (!popover) return;
  document.body.appendChild(popover);
  trigger.setAttribute('aria-expanded', 'true');
  app.partsMoreMenu = { popover, trigger };
  bindPartsQueueActionButtons(popover);
  popover.addEventListener('click', event => {
    if (event.target.closest('button')) closePartsMoreMenu();
  });
  const triggerRect = trigger.getBoundingClientRect();
  const menuRect = popover.getBoundingClientRect();
  const margin = 8;
  const availableBelow = window.innerHeight - triggerRect.bottom - margin;
  const availableAbove = triggerRect.top - margin;
  const openUpward = menuRect.height > availableBelow && availableAbove > availableBelow;
  const top = openUpward
    ? Math.max(margin, triggerRect.top - menuRect.height - 4)
    : Math.min(window.innerHeight - menuRect.height - margin, triggerRect.bottom + 4);
  const left = Math.min(window.innerWidth - menuRect.width - margin, Math.max(margin, triggerRect.right - menuRect.width));
  popover.style.top = `${Math.round(top)}px`;
  popover.style.left = `${Math.round(left)}px`;
  popover.classList.toggle('opens-upward', openUpward);
  popover.querySelector('button')?.focus({ preventScroll: true });
}

function bindPartsMoreMenus(host) {
  $$('[data-parts-more-button]', host).forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    if (app.partsMoreMenu?.trigger === button) closePartsMoreMenu({ restoreFocus: true });
    else openPartsMoreMenu(button);
  }));
  if (app.partsMoreMenuDocumentBound) return;
  app.partsMoreMenuDocumentBound = true;
  document.addEventListener('pointerdown', event => {
    if (!app.partsMoreMenu || app.partsMoreMenu.popover.contains(event.target) || app.partsMoreMenu.trigger.contains(event.target)) return;
    closePartsMoreMenu();
  });
  document.addEventListener('focusout', () => {
    window.setTimeout(() => {
      if (!app.partsMoreMenu) return;
      const active = document.activeElement;
      if (app.partsMoreMenu.popover.contains(active) || app.partsMoreMenu.trigger.contains(active)) return;
      closePartsMoreMenu();
    }, 0);
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && app.partsMoreMenu) {
      event.preventDefault();
      closePartsMoreMenu({ restoreFocus: true });
    }
  });
  if (window && typeof window.addEventListener === 'function') window.addEventListener('resize', () => closePartsMoreMenu());
}

function partsQueueRowHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const status = partsDepartmentStatus(vehicle);
  const complete = ['issued', 'notrequired'].includes(status);
  const eta = kewdaleEtaValue(vehicle);
  const ageClass = partsEtaCounterClass(vehicle);
  const currentLocation = partsCurrentLocationLabel(vehicle);
  const worstEtaInput = partsWorstEtaInputValue(vehicle);
  const worstEtaLabel = partsWorstEtaLabel(vehicle);
  const worstEtaCountdown = partsWorstEtaCountdownLabel(vehicle);
  const worstEtaCountdownClass = partsWorstEtaCountdownClass(vehicle);
  const customer = vehicleCustomerName(vehicle) || 'Dealer Order';
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const blocker = status === 'stoppage' ? partsStoppageReason(vehicle) : '';
  return `<tr class="parts-row parts-queue-row ${escapeHtml(partsDepartmentStatusClass(status))}">
    <td><div class="parts-queue-status-cell">
      <span class="parts-status-pill ${escapeHtml(partsDepartmentStatusClass(status))}">${escapeHtml(partsDepartmentStatusLabel(status))}</span>${partsRiskBadge(vehicle)}${vehicleDepartmentBadge(vehicle)}
    </div></td>
    <td><button class="parts-queue-identity parts-compact-identity" type="button" data-open-stock="${escapeHtml(key)}" aria-label="Open vehicle ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || key)}">
      <strong>Stock ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || '—')}</strong>
      <span>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || '—')} · Key ${escapeHtml(vehicleKeyNumber(vehicle) || '—')}</span>
    </button></td>
    <td><div class="parts-queue-customer"><strong title="${escapeHtml(customer)}">${escapeHtml(customer)}</strong><span title="${escapeHtml(unit)}">${escapeHtml(unit)}</span></div></td>
    <td><div class="parts-eta"><strong>${escapeHtml(eta || 'No ETA')}</strong><span class="pmb-age ${escapeHtml('pmb-age-' + ageClass)}">${escapeHtml(partsEtaCounterLabel(vehicle))}</span></div></td>
    <td><div class="parts-worst-eta-wrap"><label class="parts-worst-eta"><span class="sr-only">Parts worst ETA</span><input type="date" data-parts-worst-eta="${escapeHtml(key)}" value="${escapeHtml(worstEtaInput)}" ${complete ? 'disabled' : ''} /></label><span class="parts-worst-eta-details">${worstEtaLabel ? `<span class="parts-worst-eta-label">${escapeHtml(worstEtaLabel)}</span>${worstEtaCountdown ? `<span class="parts-worst-eta-countdown ${escapeHtml(worstEtaCountdownClass)}">${escapeHtml(worstEtaCountdown)}</span>` : ''}` : '<span class="subtle parts-worst-eta-label">Set worst ETA</span>'}</span></div></td>
    <td class="parts-queue-jita-cell">${jitaIndicator(vehicle)}</td>
    <td class="parts-queue-blocker">${blocker ? `<strong title="${escapeHtml(blocker)}">${escapeHtml(blocker)}</strong>` : '<span class="subtle">No blocker recorded</span>'}</td>
    <td><div class="parts-queue-stage"><strong>${escapeHtml(currentLocation)}</strong><span>${escapeHtml(partsCurrentLocationUpdateLabel(vehicle) || 'No location update recorded')}</span></div></td>
    <td>${partsQueueActionsHtml(vehicle, status)}</td>
  </tr>`;
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
  host.innerHTML = `<div class="parts-table-wrap parts-queue-wrap"><table class="data-table compact-table parts-queue-table">
    <thead><tr>
      <th>Status</th><th>Vehicle ID</th><th>Customer / vehicle</th><th>Kewdale ETA</th><th>Parts ETA</th><th>Jita</th><th>Blocker</th><th>Stage / update</th><th>Actions</th>
    </tr></thead>
    <tbody>${rows.map(partsQueueRowHtml).join('')}</tbody></table></div>`;
  bindPartsQueueActionButtons(host);
  bindPartsMoreMenus(host);
  $$('[data-parts-worst-eta]', host).forEach(input => input.addEventListener('change', () => updateVehiclePartsWorstEta(input.dataset.partsWorstEta, input.value)));
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
    pdcPartsWorstEta: '',
    pdcPartsStoppageClearedAt: nowIsoString(),
    pdcPartsStoppageClearedBy: operator,
    pdcQcComplete: false,
    pdcQcCompleteAt: '',
    pdcQcCompleteBy: '',
  };
  if (def) {
    updates[def.completeKey] = true;
    updates[def.completeAtKey] = nowIsoString();
    updates[def.completeByKey] = operator;
  }
  recordVehicleAudit(vehicle, 'Parts signed off complete', { by: operator });
  saveVehicleEdits(key, updates);
  offerSalespersonChangeEmail(vehicle, {
    title: 'Parts completed',
    subject: 'PDC work completed',
    details: [`Parts were signed off by ${operator}.`],
  });
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
  offerSalespersonChangeEmail(vehicle, {
    title: 'Parts stoppage recorded',
    subject: 'PDC stoppage update',
    details: [`Reason: ${reason}`, `Recorded by ${operator}.`],
  });
}

function updateVehiclePartsWorstEta(key = '', value = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const eta = cleanNavisionText(value || '');
  const previousEta = partsWorstEtaValue(vehicle);
  const operator = getCurrentOperatorName();
  recordVehicleAudit(vehicle, eta ? 'Parts worst ETA updated' : 'Parts worst ETA cleared', { eta, previousEta, by: operator });
  saveVehicleEdits(key, {
    pdcPartsPreviousWorstEta: previousEta,
    pdcPartsWorstEta: eta,
    pdcPartsWorstEtaUpdatedAt: nowIsoString(),
    pdcPartsWorstEtaUpdatedBy: operator,
  });
  if (eta !== previousEta) {
    const previousLabel = previousEta ? partsWorstEtaLabel({ pdcPartsWorstEta: previousEta }) : 'Not previously recorded';
    const newLabel = eta ? partsWorstEtaLabel({ pdcPartsWorstEta: eta }) : 'Cleared';
    offerSalespersonChangeEmail(vehicle, {
      title: eta ? 'Parts ETA updated' : 'Parts ETA cleared',
      subject: 'Parts ETA update',
      details: [`Previous Parts ETA: ${previousLabel}`, `New Parts ETA: ${newLabel}`, eta ? `Revised countdown: ${partsWorstEtaCountdownLabel(vehicle) || 'Not available'}` : ''],
    });
  }
}

function draftPartsEtaSalesEmail(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const eta = partsWorstEtaLabel(vehicle);
  if (!eta) {
    window.alert('Set a Parts ETA before emailing sales.');
    return;
  }
  const salesperson = salespersonDisplayName(vehicle);
  const countdown = partsWorstEtaCountdownLabel(vehicle);
  const previousEta = cleanNavisionText(vehicle.pdcPartsPreviousWorstEta || vehicle.previousPartsWorstEta || '');
  const previousEtaLabel = previousEta ? partsWorstEtaLabel({ pdcPartsWorstEta: previousEta }) : '';
  const blocker = partsStoppageReason(vehicle);
  const body = [
    `Hi ${salesperson},`,
    '',
    ...salespersonChangeBannerLines(vehicle, { title: 'Parts ETA / delay update' }),
    '',
    'Parts have updated the expected ETA for the vehicle below.',
    '',
    ...vehicleEmailLines(vehicle),
    `Job Card: ${vehicleJobcardNumber(vehicle) || 'TBA'}`,
    `Current stage: ${statusCategoryLabel(vehicle)}${inferredPmbStage(vehicle) ? ` / ${pmbStageLabel(inferredPmbStage(vehicle))}` : ''}`,
    `Previous Parts ETA: ${previousEtaLabel || 'Not recorded'}`,
    `New Parts ETA: ${eta}`,
    `Revised countdown: ${countdown || 'No countdown available'}`,
    blocker ? `Parts note: ${blocker}` : '',

    'Please update the customer/delivery expectation as required.',
    '',
    'Kind Regards,',
  ].filter(line => line !== '').join('\n');
  const subject = `Parts ETA update - ${displayStockNumber(vehicle) || vehicle.order || 'TBA'}`;
  recordVehicleAudit(vehicle, 'Parts ETA sales email drafted', { eta, countdown, salesperson });
  window.location.href = `mailto:${salespersonEmail(vehicle)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function clearVehiclePartsStoppage(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const operator = getCurrentOperatorName();
  recordVehicleAudit(vehicle, 'Parts stoppage cleared', { reason: partsStoppageReason(vehicle), by: operator });
  saveVehicleEdits(key, {
    pdcPartsStoppage: false,
    pdcPartsStoppageReason: '',
    pdcPartsWorstEta: '',
    pdcPartsStoppageClearedAt: nowIsoString(),
    pdcPartsStoppageClearedBy: operator,
  });
}

function exportPartsCsv() {
  const rows = partsDepartmentRows();
  const headers = ['Parts Status','Stock','Toyota Order','Client','Vehicle','Kewdale ETA','Kewdale ETA Age','Parts Worst ETA','Parts Worst ETA Countdown','Current Stage','PMB Stage','Parts Ordered','Parts Ordered By','Parts Issued','Parts Issued By','Parts Stoppage','Parts Stoppage Reason','Last Parts Update'];
  const def = partsJobDef();
  const lines = [headers.join(',')].concat(rows.map(vehicle => [
    partsDepartmentStatusLabel(partsDepartmentStatus(vehicle)),
    displayStockNumber(vehicle), vehicle.order || '', vehicle.client || vehicle.toyotaCustomer || '', displayVehicle(vehicle),
    kewdaleEtaValue(vehicle), pmbAgeLabel(vehicle), partsWorstEtaLabel(vehicle), partsWorstEtaCountdownLabel(vehicle), statusCategoryLabel(vehicle), pmbStageLabel(inferredPmbStage(vehicle)),
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

function rftCompletionSummaryHtml(vehicle = {}) {
  const required = pdcRequiredJobs(vehicle);
  if (!required.length) return '<span class="subtle">No jobs</span>';
  const done = required.filter(def => pdcJobComplete(vehicle, def)).length;
  const pending = required.length - done;
  return `<span class="rft-completion-summary-pill ${pending ? 'is-pending' : 'is-complete'}">${done}/${required.length} jobs${pending ? ` · ${pending} open` : ' · done'}</span>`;
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
  host.innerHTML = `<div class="incoming-vertical-list rft-compact-list">${productionGridHeaderHtml('rft-production-grid-header', { meta1Label: 'RFT date', meta2Label: 'RFT status', actionLabel: 'Actions' })}${rows.map(vehicle => rftVehicleDetailRow(vehicle)).join('')}</div>`;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    openVehicleModal(button.dataset.openStock);
  }));
  $$('[data-rft-completion-key]', host).forEach(input => input.addEventListener('change', () => {
    togglePdcJobCompletionFromCard(input.dataset.rftCompletionKey, input.dataset.rftCompletionJob);
  }));
  $$('[data-rft-email]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    draftRftSalespersonNotificationEmail([button.dataset.rftEmail]);
  }));
  $$('[data-rft-delete]', host).forEach(button => button.addEventListener('click', event => {
    event.stopPropagation();
    deleteIncomingVehicleFromMain(button.dataset.rftDelete);
  }));
  bindRftCollectedInputs(host);
  updateCollapseToggleButtons();
}

function rftVehicleDetailRow(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const status = rftHomeStatus(vehicle);
  const statusClass = rftHomeStatusClass(status);
  const issues = vehicleRftGateIssues(vehicle);
  const transferredAt = parseIsoTimestamp(vehicle.rftTransferredAt || vehicle.pdcLocationUpdatedAt || '');
  const transferredLabel = transferredAt ? transferredAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '—';
  const blocker = issues.length ? issues.join(' · ') : pdcOutstandingJobsText(vehicle);
  const stock = displayStockNumber(vehicle) || key || 'No stock';
  const unit = displayVehicle(vehicle) || 'Vehicle not listed';
  const customer = vehicleCustomerName(vehicle) || 'Dealer Order';
  const keyNo = vehicleKeyNumber(vehicle) || '—';
  return `
    <details class="incoming-vehicle-card pdc-production-grid-card incoming-rft-row rft-compact-row ${escapeHtml(statusClass)}" data-rft-row="${escapeHtml(key)}">
      <summary class="incoming-vehicle-summary pdc-production-grid-row rft-vehicle-summary">
        <span class="pdc-grid-select-spacer" aria-hidden="true"></span>
        <span class="incoming-card-stock">${vehicleIdentityStackHtml(vehicle, { className: 'incoming-identity' })}</span>
        <span class="incoming-card-main"><strong title="${escapeHtml(unit)}">${escapeHtml(unit)}</strong></span>
        <span class="incoming-card-work-wrap rft-card-work-wrap">${incomingWorkChecklistHtml(vehicle)}</span>
        <span class="incoming-card-meta incoming-card-age"><b>RFT</b><span>${escapeHtml(transferredLabel)}</span></span>
        <span class="incoming-card-meta"><b>Status</b><span class="parts-status-pill ${escapeHtml(statusClass)}">${escapeHtml(rftHomeStatusLabel(status))}</span></span>
        <span class="incoming-card-action rft-card-actions">
          ${rftCompletionSummaryHtml(vehicle)}
        </span>
      </summary>
      <div class="incoming-vehicle-detail-grid">
        <div><b>RFT status</b><span>${escapeHtml(rftHomeStatusLabel(status))}</span></div>
        <div><b>Stock</b><span>${escapeHtml(stock)}</span></div>
        <div><b>Key</b><span>${escapeHtml(keyNo)}</span></div>
        <div><b>Customer</b><span>${escapeHtml(customer)}</span></div>
        <div class="wide"><b>Blocker / outstanding</b><span>${escapeHtml(blocker || 'No outstanding RFT blockers')}</span></div>
        <div class="wide"><b>Completion ticks</b><span>${rftCompletionTicksHtml(vehicle)}</span></div>
        <div class="wide rft-detail-actions"><b>Handover actions</b><span><label class="rft-collected-check" title="Tick once the vehicle has been collected"><input type="checkbox" data-rft-collected-key="${escapeHtml(key)}" /> <span>Collected</span></label><button class="small-button incoming-open-button" type="button" data-open-stock="${escapeHtml(key)}">Open vehicle</button></span></div>
      </div>
    </details>`;
}

async function markRftVehicleCollected(key, collected = true) {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  if (!collected && vehicleCollectedFromRft(vehicle)) {
    window.alert('Completed vehicles are locked once collected. Open the vehicle and contact an admin if this was marked collected in error.');
    renderAll();
    return;
  }
  if (!collected) return;
  const label = vehicleIdentityTitle(vehicle) || displayStockNumber(vehicle) || 'this vehicle';
  if (!window.confirm(`Confirm ${label} has been collected?\n\nThis will move it out of RFT into Completed Vehicles and cannot be undone here.`)) {
    renderAll();
    return;
  }
  const operator = getCurrentOperatorName();

  if (vehicleLifecycleSharedModeActive()) {
    const ref = await vehicleLifecycleSharedRef(vehicle);
    if (!ref || ref.outcome !== 'resolved') {
      window.alert(describeVehicleLifecycleResolutionOutcome(ref));
      renderAll();
      return;
    }
    if (ref.isArchived) {
      window.alert('This vehicle is archived in shared data, so it was not marked collected. No change was made.');
      renderAll();
      return;
    }
    if (ref.lifecycleState === 'completed') {
      window.alert('This vehicle has already been collected and moved to Completed Vehicles.');
      renderAll();
      return;
    }
    const result = await window.__vehicleLifecycleActions.rftCollectVehicle({ vehicleId: ref.vehicleId, expectedVersion: ref.version });
    if (!result || result.ok !== true) {
      const message = typeof describeVehicleLifecycleActionError === 'function' ? describeVehicleLifecycleActionError(result && result.error) : 'This vehicle could not be marked collected.';
      window.alert(message);
      if (typeof window.__workshopDataService !== 'undefined' && window.__workshopDataService) window.__workshopDataService.loadSnapshot('rft_collect_rejected');
      renderAll();
      return;
    }
    offerSalespersonChangeEmail(vehicle, {
      title: 'Vehicle completed and collected',
      subject: 'Vehicle collection complete',
      shared: true,
      details: [`Collected from RFT by ${operator || 'Unknown operator'}.`],
    });
    if (typeof window.__workshopDataService !== 'undefined' && window.__workshopDataService) window.__workshopDataService.loadSnapshot('rft_collect');
    renderAll();
    return;
  }

  const now = nowIsoString();
  recordVehicleAudit(vehicle, 'Collected from RFT', { by: operator || 'Unknown' });
  saveVehicleEdits(vehicleKey(vehicle), {
    rftCollected: true,
    completedVehicle: true,
    rftCollectedAt: vehicle.rftCollectedAt || now,
    rftCollectedBy: vehicle.rftCollectedBy || operator,
  });
  offerSalespersonChangeEmail(vehicle, {
    title: 'Vehicle completed and collected',
    subject: 'Vehicle collection complete',
    details: [`Collected from RFT by ${operator || 'Unknown operator'}.`],
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
        displayVehicle(vehicle), vehicle.rftCollectedBy || '', vehicle.rftCollectedAt || '', vehicle.rftTransferredAt || '',
        shortDateAu(completedPmbStartDate(vehicle)), shortDateAu(completedRftDate(vehicle)), completedPmbDaysLabel(vehicle), pdcCompletedJobsText(vehicle),
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
  renderCompletedPmbStatistics();
  const rows = completedVehicleRows();
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No completed vehicles yet</strong><span>Tick Collected on the RFT screen after a vehicle has been picked up.</span></div>';
    return;
  }
  host.innerHTML = `<div class="parts-table-wrap completed-table-wrap pdc-grid-table-wrap"><table class="data-table compact-table completed-table pdc-grid-table">
    <thead><tr>
      <th>Collected</th><th>Key</th><th>Stock</th><th>Job Card</th><th>Customer</th><th>Vehicle</th>
      <th>Collected time</th><th>PMB start</th><th>RFT date</th><th>Days at PMB</th><th>Collected by</th><th>Completed stations</th><th>Actions</th>
    </tr></thead>
    <tbody>${rows.map(vehicle => {
      const key = vehicleKey(vehicle);
      const collectedAt = parseIsoTimestamp(vehicle.rftCollectedAt || '');
      const collectedLabel = collectedAt ? collectedAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '';
      const pmbStartLabel = shortDateAu(completedPmbStartDate(vehicle)) || '—';
      const rftDateLabel = shortDateAu(completedRftDate(vehicle)) || '—';
      const pmbDaysLabel = completedPmbDaysLabel(vehicle);
      return `<tr class="completed-vehicle-row">
        <td><label class="rft-collected-check completed-collected-check is-locked" title="Collected vehicles are locked"><input type="checkbox" checked disabled /> <span>Collected</span></label></td>
        <td class="pdc-id-cell pdc-key-cell">${escapeHtml(vehicleKeyNumber(vehicle) || '—')}</td>
        <td class="pdc-id-cell pdc-stock-cell"><button class="stock-link stock-button" type="button" data-open-stock="${escapeHtml(key)}">${escapeHtml(displayStockNumber(vehicle) || vehicle.order || '—')}</button></td>
        <td class="pdc-id-cell pdc-jc-cell">${escapeHtml(vehicleJobcardNumber(vehicle) || '—')}</td>
        <td class="pdc-name-cell"><span title="${escapeHtml(vehicleCustomerName(vehicle) || '')}">${escapeHtml(vehicleCustomerName(vehicle) || 'Dealer Order')}</span></td>
        <td class="pdc-vehicle-cell"><span title="${escapeHtml(displayVehicle(vehicle))}">${escapeHtml(displayVehicle(vehicle) || 'Vehicle not listed')}</span></td>
        <td>${escapeHtml(collectedLabel)}</td><td>${escapeHtml(pmbStartLabel)}</td><td>${escapeHtml(rftDateLabel)}</td><td>${escapeHtml(pmbDaysLabel)}</td>
        <td>${escapeHtml(vehicle.rftCollectedBy || '')}</td>
        <td class="pdc-completed-stations-cell">${escapeHtml(pdcGridCompletedJobsText(vehicle))}</td>
        <td><button class="small-button" type="button" data-open-stock="${escapeHtml(key)}">Open</button></td>
      </tr>`;
    }).join('')}</tbody></table></div>`;
  $$('[data-open-stock]', host).forEach(button => button.addEventListener('click', () => openVehicleModal(button.dataset.openStock)));
  bindRftCollectedInputs(host);
}

function deletedVehiclesSearchText(record = {}) {
  const vehicle = record.vehicle || {};
  return [
    record.key, record.deletedAt, record.deletedBy, record.deletedRole,
    displayStockNumber(vehicle), vehicle.order, vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle),
    vehicle.client, vehicle.toyotaCustomer, displayVehicle(vehicle), auditTrailForVehicle(vehicle).map(entry => `${entry.action} ${entry.by} ${entry.at}`).join(' '),
  ].join(' ').toLowerCase();
}

function deletedVehicleRows() {
  const q = ($('#deleted-search')?.value || '').trim().toLowerCase();
  return deletedVehicleRecords()
    .filter(record => !q || deletedVehiclesSearchText(record).includes(q))
    .sort((a, b) => {
      const timeA = parseIsoTimestamp(a.deletedAt || '')?.getTime() || 0;
      const timeB = parseIsoTimestamp(b.deletedAt || '')?.getTime() || 0;
      return timeB - timeA;
    });
}

function renderDeletedVehicles() {
  const host = $('#deleted-vehicles-content');
  if (!host) return;
  const rows = deletedVehicleRows();
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No deleted vehicles saved</strong><span>Vehicles deleted from the Control Board or RFT will appear here with their audit trail.</span></div>';
    return;
  }
  host.innerHTML = `<div class="incoming-vertical-list deleted-compact-list">${productionGridHeaderHtml('deleted-production-grid-header', { meta1Label: 'Deleted', meta2Label: 'Deleted by', actionLabel: 'Record' })}${rows.map(record => {
    const vehicle = record.vehicle || { stock: record.key };
    const key = record.key || vehicleKey(vehicle);
    const deletedAt = parseIsoTimestamp(record.deletedAt || '');
    const deletedLabel = deletedAt ? deletedAt.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'Unknown time';
    const customer = vehicleCustomerName(vehicle) || 'Unknown customer';
    const unit = displayVehicle(vehicle) || 'Vehicle not listed';
    return `
      <details class="incoming-vehicle-card pdc-production-grid-card deleted-vehicle-row" data-deleted-row="${escapeHtml(key)}">
        <summary class="incoming-vehicle-summary pdc-production-grid-row deleted-vehicle-summary">
          <span class="pdc-grid-select-spacer" aria-hidden="true"></span>
          <span class="incoming-card-stock">${vehicleIdentityStackHtml(vehicle, { className: 'incoming-identity' })}</span>
          <span class="incoming-card-main"><strong title="${escapeHtml(unit)}">${escapeHtml(unit)}</strong></span>
          <span class="incoming-card-work-wrap">${incomingWorkChecklistHtml(vehicle)}</span>
          <span class="incoming-card-meta incoming-card-age"><b>Deleted</b><span>${escapeHtml(deletedLabel)}</span></span>
          <span class="incoming-card-meta"><b>By</b><span>${escapeHtml(record.deletedBy || 'Unknown')}</span></span>
          <span class="incoming-card-action deleted-card-actions"><span class="parts-status-pill blocked">Deleted</span><button class="small-button" type="button" disabled title="Deleted vehicle records cannot be deleted again">Locked</button></span>
        </summary>
        <div class="incoming-vehicle-detail-grid deleted-vehicle-detail-grid">
          <div><b>Stock</b><span>${escapeHtml(displayStockNumber(vehicle) || key)}</span></div>
          <div><b>Order</b><span>${escapeHtml(vehicle.order || '—')}</span></div>
          <div><b>Key</b><span>${escapeHtml(vehicleKeyNumber(vehicle) || '—')}</span></div>
          <div><b>Deleted by</b><span>${escapeHtml(record.deletedBy || 'Unknown')}${record.deletedRole ? ` (${escapeHtml(record.deletedRole)})` : ''}</span></div>
          <div class="wide"><b>Movement / deletion log</b>${renderAuditTrailSection(vehicle)}</div>
        </div>
      </details>`;
  }).join('')}</div>`;
  updateCollapseToggleButtons();
}

function backEndDataRows() {
  const deletedRecords = deletedVehicleRecords().map(record => ({
    vehicle: record.vehicle || {},
    state: 'Deleted',
    detail: record.reason || 'Removed from current Navision / dashboard data',
    deletedAt: record.deletedAt || '',
  }));
  const activeRows = app.data.map(vehicle => ({
    vehicle,
    state: isVehicleVisibleOnPdcSheet(vehicle) ? 'PDC Sheet' : 'Back end only',
    detail: [vehicle.source || (vehicle.importedAt ? 'Navision' : 'Tracker'), vehicle.pdcVisibilitySource].filter(Boolean).join(' · '),
    deletedAt: '',
  }));
  return activeRows.concat(deletedRecords).sort((a, b) => String(displayStockNumber(a.vehicle) || vehicleKey(a.vehicle) || '').localeCompare(String(displayStockNumber(b.vehicle) || vehicleKey(b.vehicle) || ''), 'en-AU', { numeric: true }));
}

function filteredBackEndDataRows(rows = backEndDataRows()) {
  const query = cleanNavisionText($('#backend-data-search')?.value || '').toLowerCase();
  const stateFilter = $('#backend-data-state-filter')?.value || 'all';
  const terms = query.split(/\s+/).filter(Boolean);
  return rows.filter(row => {
    if (stateFilter === 'backend' && row.state !== 'Back end only') return false;
    if (stateFilter === 'active' && row.state !== 'PDC Sheet') return false;
    if (stateFilter === 'deleted' && row.state !== 'Deleted') return false;
    if (!terms.length) return true;
    const vehicle = row.vehicle || {};
    const haystack = [
      displayStockNumber(vehicle), vehicle.batch, vehicle.order, vehicle.toyotaOrder,
      vehicle.vin, vehicle.fullVin, vehicle.frame, vehicle.autocareVin,
      vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle), vehicleCustomerName(vehicle),
      displayVehicle(vehicle), vehicle.toyotaStatus, consultantName(vehicle),
      vehicle.purchaseOrderNumber, vehicle.purchaseOrderReference, vehicle.purchaseOrderDeliverTo,
      vehicle.source, row.state, row.detail,
    ].map(value => cleanNavisionText(value || '').toLowerCase()).join(' ');
    return terms.every(term => haystack.includes(term));
  });
}

function clearBackEndDataSearch() {
  const search = $('#backend-data-search');
  const state = $('#backend-data-state-filter');
  if (search) search.value = '';
  if (state) state.value = 'all';
  renderBackEndData();
}

function navisionLocationSourceText(vehicle = {}) {
  return [
    vehicle.navisionLocationStatus,
    vehicle.locationStatus,
    vehicle.navisionSubLocationDescription,
    vehicle.toyotaStatus,
    vehicle.navisionBuildStatus,
    vehicle.internalStatus,
  ].map(value => normalizeToyotaStatus(value || '')).filter(Boolean).join(' ');
}

function navisionTextIsBodyBuilder(text = '') {
  const normalized = normalizeToyotaStatus(text);
  return /\bbody\s*-?\s*builder\b|\bbodybuilder\b|\bpmb\b/.test(normalized) || normalized.includes('perth motor bodies');
}

function currentPdcLocationFromNavision(vehicle = {}) {
  const automatic = navisionAutoPdcLocation(vehicle);
  if (automatic) return automatic;
  const locationStatus = normalizeToyotaStatus(vehicle.navisionLocationStatus || vehicle.locationStatus || '');
  const subLocation = normalizeToyotaStatus(vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || '');
  const text = navisionLocationSourceText(vehicle);
  if (locationStatus === 'yh' || subLocation.includes('yard hold') || /\byh\b/.test(text)) return 'YH';
  if (
    locationStatus === 'rft' || /\brft\b/.test(text) ||
    text.includes('ready for transport') || text.includes('ready for transfer') ||
    text.includes('at dealer') || text.includes('delivered to dealer') ||
    text.includes('delivered - at dealer') || text.includes('dealer received')
  ) return 'RFT';
  return '';
}

function navisionDerivedLocationUpdates(incoming = {}, existing = {}) {
  const nextLocation = currentPdcLocationFromNavision(incoming);
  const previousLocation = vehiclePdcLocation(existing);
  const now = nowIsoString();
  const updates = {
    pdcLocation: nextLocation,
    manualLocation: '',
    pdcLocationLocked: false,
    pdcLocationDerivedFromNavision: true,
    pdcLocationSource: 'Navision current location',
  };
  if (nextLocation !== previousLocation) updates.pdcLocationUpdatedAt = now;
  if (nextLocation === 'PMB' && previousLocation !== 'PMB') {
    Object.assign(updates, {
      pmbEnteredAt: pmbEnteredTimestamp(existing) || now,
      pmbTransferredAt: existing.pmbTransferredAt || now,
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
    });
  }
  if (nextLocation === 'RFT' && previousLocation !== 'RFT') updates.rftTransferredAt = existing.rftTransferredAt || now;
  if (previousLocation === 'PMB' && nextLocation !== 'PMB') {
    Object.assign(updates, {
      pmbStage: '',
      pdcWorkStage: '',
      workStage: '',
      pmbBayStage: '',
      pmbBayNumber: '',
      pmbBayEstimatedHours: '',
      pmbBayEnteredAt: '',
      pmbBayScheduledStartAt: '',
      pmbBayMechanic: '',
      pmbSubletProvider: '',
    });
  }
  return updates;
}

function backEndActivationLocationLabel(vehicle = {}) {
  const location = currentPdcLocationFromNavision(vehicle);
  if (location === 'PMB') return 'PMB - Unallocated';
  if (location) return pdcLocationLabel(location);
  return statusCategoryLabel(vehicle) || navisionStatusText(vehicle) || 'current Navision location';
}

function transferBackEndVehicleToActive(key = '') {
  const vehicle = app.data.find(row => vehicleKey(row) === key || row.stock === key || row.order === key || row.id === key);
  if (!vehicle || isVehicleVisibleOnPdcSheet(vehicle)) return;
  const identity = displayStockNumber(vehicle) || vehicle.order || 'this vehicle';
  const customer = vehicleCustomerName(vehicle) || 'Unknown customer';
  const locationLabel = backEndActivationLocationLabel(vehicle);
  const navisionLocation = navisionStatusText(vehicle) || cleanNavisionText(vehicle.navisionLocationStatus || '') || 'No Navision location supplied';
  if (!window.confirm(`Move ${identity} - ${customer} from Back End Data to the active PDC Sheet?\n\nCurrent location: ${locationLabel}\nNavision: ${navisionLocation}\n\nThe active vehicle will follow this current Navision location. Body Builder / PMB vehicles land in PMB Unallocated.`)) return;
  saveVehicleEdits(vehicleKey(vehicle), {
    ...pdcVisibilityPromotionUpdates(vehicle, 'Operator transfer from Back End Data'),
    ...navisionDerivedLocationUpdates(vehicle, vehicle),
  });
  recordVehicleAudit(vehicle, 'Moved from Back End Data to active PDC Sheet', { by: getCurrentOperatorName(), location: locationLabel, navisionLocation });
  app.data = buildVehicleData();
  renderAll();
}

function renderBackEndData() {
  const host = $('#backend-data-content');
  if (!host) return;
  const allRows = backEndDataRows();
  const rows = filteredBackEndDataRows(allRows);
  const pdcSheet = allRows.filter(row => row.state === 'PDC Sheet').length;
  const backEndOnly = allRows.filter(row => row.state === 'Back end only').length;
  const deleted = allRows.filter(row => row.state === 'Deleted').length;
  const count = $('#backend-data-count');
  if (count) count.textContent = `${rows.length} shown · ${pdcSheet} active · ${backEndOnly} back end only · ${deleted} deleted`;
  if (!rows.length) {
    host.innerHTML = `<div class="empty-state"><strong>No matching back-end vehicles</strong><span>${allRows.length ? 'Change the search or state filter, then try again.' : 'Upload the latest Navision dump to populate this page.'}</span></div>`;
    return;
  }
  host.innerHTML = `<div class="responsive-table pdc-grid-table-wrap"><table class="data-table backend-data-table pdc-grid-table">
    <thead><tr><th>Key</th><th>Stock</th><th>Job Card</th><th>Customer</th><th>Vehicle</th><th>Status</th><th>Source / note</th><th>Updated</th><th>Actions</th></tr></thead>
    <tbody>${rows.map(row => {
      const v = row.vehicle || {};
      const key = vehicleKey(v);
      const isDeleted = row.state === 'Deleted';
      const isBackEndOnly = row.state === 'Back end only';
      return `<tr class="${isDeleted ? 'deleted-row' : ''}">
        <td class="pdc-id-cell pdc-key-cell">${escapeHtml(vehicleKeyNumber(v) || '—')}</td>
        <td class="pdc-id-cell pdc-stock-cell">${isDeleted ? escapeHtml(displayStockNumber(v) || v.order || '—') : `<button class="stock-link stock-button" type="button" data-open-stock="${escapeHtml(key)}">${escapeHtml(displayStockNumber(v) || v.order || '—')}</button>`}</td>
        <td class="pdc-id-cell pdc-jc-cell">${escapeHtml(vehicleJobcardNumber(v) || '—')}</td>
        <td class="pdc-name-cell">${escapeHtml(vehicleCustomerName(v) || 'Customer TBA')}</td>
        <td class="pdc-vehicle-cell">${escapeHtml(displayVehicle(v) || v.vehicle || v.toyotaVehicle || '')}</td>
        <td class="pdc-status-cell"><span class="badge ${isDeleted ? 'danger' : isBackEndOnly ? 'warning' : 'neutral'}">${escapeHtml(row.state)}</span>${v.toyotaStatus ? ` <span class="subtle">${escapeHtml(v.toyotaStatus)}</span>` : ''}</td>
        <td class="pdc-note-cell">${escapeHtml(row.detail || '')}</td>
        <td>${escapeHtml(isDeleted ? (parseIsoTimestamp(row.deletedAt)?.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) || '') : (parseIsoTimestamp(v.importedAt || v.updatedAt || '')?.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) || ''))}</td>
        <td class="backend-action-cell">${isBackEndOnly ? `<button class="small-button primary" type="button" data-backend-activate="${escapeHtml(key)}">Move to active</button>` : isDeleted ? '<span class="subtle">Locked</span>' : '<span class="badge neutral">Active</span>'}</td>
      </tr>`;
    }).join('')}</tbody>
  </table></div>`;
  $$('[data-open-stock]', host).forEach(btn => btn.addEventListener('click', () => openVehicleModal(btn.dataset.openStock)));
  $$('[data-backend-activate]', host).forEach(btn => btn.addEventListener('click', () => transferBackEndVehicleToActive(btn.dataset.backendActivate)));
}

function exportDeletedVehiclesCsv() {
  const rows = deletedVehicleRows();
  const headers = ['Stock','Toyota Order','Key','Client','Vehicle','Deleted At','Deleted By','Deleted Role','Audit Events'];
  const lines = [headers.join(',')].concat(rows.map(record => {
    const vehicle = record.vehicle || { stock: record.key };
    const audit = auditTrailForVehicle(vehicle).map(entry => `${entry.at || ''} ${entry.action || ''} ${entry.by || ''}`).join(' | ');
    return [
      displayStockNumber(vehicle) || record.key || '', vehicle.order || '', vehicleKeyNumber(vehicle), vehicle.client || vehicle.toyotaCustomer || '',
      displayVehicle(vehicle), record.deletedAt || '', record.deletedBy || '', record.deletedRole || '', audit,
    ].map(csvEscape).join(',');
  }));
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'pdc-deleted-vehicles-export.csv';
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function exportCompletedVehiclesCsv() {
  const rows = completedVehicleRows();
  const headers = ['Stock','Toyota Order','Key','Client','Vehicle','Collected At','PMB Start ETA to Kewdale','RFT Date','Days at PMB','Collected By','Completed Jobs'];
  const lines = [headers.join(',')].concat(rows.map(vehicle => [
    displayStockNumber(vehicle), vehicle.order || '', vehicleKeyNumber(vehicle), vehicle.client || vehicle.toyotaCustomer || '',
    displayVehicle(vehicle), vehicle.rftCollectedAt || '', shortDateAu(completedPmbStartDate(vehicle)), shortDateAu(completedRftDate(vehicle)), completedPmbDays(vehicle) ?? '', vehicle.rftCollectedBy || '', pdcCompletedJobsText(vehicle),
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
  const rows = pdcSheetVehicles();
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
  const byCustomer = groupBy(pdcSheetVehicles(), v => v.client || v.toyotaCustomer || 'Unknown');
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
  const salespersonSelect = $('[data-new-customer-salesperson]');
  if (salespersonSelect) salespersonSelect.innerHTML = salespersonOptionsHtml('');
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
    recordLifecycle: 'manual',
    pdcSheetVisible: true,
    pdcVisibilitySource: 'Manual vehicle entry',
    pdcPromotedAt: nowIsoString(),
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

function normalizePurchaseOrderText(value = '') {
  return String(value || '')
    .replace(/\r/g, '\n')
    .replace(/\f/g, '\n')
    .replace(/[−–—]/g, '-')
    .replace(/\u00a0/g, ' ');
}

function cleanPurchaseOrderLine(value = '') {
  return normalizePurchaseOrderText(value).replace(/\s+/g, ' ').trim();
}

function purchaseOrderNumberFromFilename(filename = '') {
  return ((String(filename).match(/\bPO\d{6,}\b/i) || [])[0] || '').toUpperCase();
}

function extractStockFromPoFilename(filename = '') {
  const value = String(filename || '');
  const labelled = value.match(/(?:stock|batch)[ _#:-]*(\d{6,12})/i);
  if (labelled) return labelled[1];
  if (/\bPO\d{6,}\b/i.test(value)) return '';
  const unlabelled = value.match(/\b\d{7,12}\b/);
  return unlabelled ? unlabelled[0] : '';
}

function purchaseOrderCodeAndDescription(value = '') {
  const cleaned = cleanPurchaseOrderLine(value);
  const match = cleaned.match(/^(TOY[A-Z0-9]+)\s+(.+)$/i);
  return match ? { code: match[1].toUpperCase(), description: match[2].trim() } : { code: '', description: cleaned };
}

function purchaseOrderClientFromDeliverTo(deliverTo = '') {
  if (/FLEET/i.test(deliverTo)) return 'Broome Toyota Fleet Sales';
  if (/RETAIL/i.test(deliverTo)) return 'Broome Toyota Retail Sales';
  return 'Broome Toyota';
}

function purchaseOrderSalespersonCode(issuedBy = '') {
  const code = cleanPurchaseOrderLine(issuedBy).toUpperCase();
  if (/^[A-Z]{5,}$/.test(code)) return `${code[0]}${code[code.length - 1]}`;
  return /^[A-Z]{1,4}$/.test(code) ? code : '';
}

function purchaseOrderLabelValue(lines, labelPattern) {
  const line = lines.find(value => labelPattern.test(value));
  return line ? cleanPurchaseOrderLine(line.replace(labelPattern, '')) : '';
}

function parsePurchaseOrderText(text, sourceFilename = '') {
  const raw = normalizePurchaseOrderText(text);
  const lines = raw.split('\n').map(cleanPurchaseOrderLine).filter(Boolean);
  const compact = lines.join(' ');
  const headerMatch = compact.match(/\b(PO\d{6,})\s+(\d{1,2}\/\d{1,2}\/\d{2,4})\s+([A-Z][A-Z0-9]{1,15})\s+Vehicle\s*\/\s*Sublet\s+(\d{2,4})\s+(\d{6,12})\s+\d+\b/i);
  const purchaseOrderNumber = ((headerMatch && headerMatch[1]) || (raw.match(/\bPO\d{6,}\b/i) || [])[0] || purchaseOrderNumberFromFilename(sourceFilename)).toUpperCase();
  const stock = ((raw.match(/Stock\s*#\s*:?\s*(\d{6,12})/i) || [])[1] || (headerMatch && headerMatch[5]) || extractStockFromPoFilename(sourceFilename) || '').trim();
  const dueDate = (headerMatch && headerMatch[2]) || '';
  const issuedBy = ((headerMatch && headerMatch[3]) || ((sourceFilename.match(/^([A-Z]{3,})_PO/i) || [])[1]) || '').toUpperCase();
  const department = (headerMatch && headerMatch[4]) || '';
  const reference = (headerMatch && headerMatch[5]) || stock;
  const printedMatch = compact.match(/Printed\s+(\d{1,2}\/\d{1,2}\/\d{2,4})\s+(\d{1,2}:\d{2})/i);
  const deliverTo = ((compact.match(/\bNEW TOYOTA (?:FLEET|RETAIL) SALES\b/i) || [])[0] || '').toUpperCase();
  const colourValue = purchaseOrderLabelValue(lines, /^Colour\s*:\s*/i);
  const trimValue = purchaseOrderLabelValue(lines, /^Trim\s*:\s*/i);
  const colour = purchaseOrderCodeAndDescription(colourValue);
  const trim = purchaseOrderCodeAndDescription(trimValue);
  const factoryOption = purchaseOrderLabelValue(lines, /^Factory Option\s*:\s*/i);
  const alternateModel = purchaseOrderLabelValue(lines, /^Alternate Model\s*:\s*/i);
  const engine = purchaseOrderLabelValue(lines, /^Engine\s*:\s*/i);
  const buildDate = purchaseOrderLabelValue(lines, /^Build Date\s*:\s*/i);
  const vin = normalizeVin(purchaseOrderLabelValue(lines, /^VIN\s*:\s*/i));

  const metadataIndexes = new Set();
  lines.forEach((line, index) => {
    if (/^(Colour|Trim|Factory Option|Alternate Model|Engine|Build Date|Stock\s*#|VIN)\s*:/i.test(line)) metadataIndexes.add(index);
  });
  const colourIndex = lines.findIndex(line => /^Colour\s*:/i.test(line));
  let vehicle = '';
  let modelCode = '';
  if (colourIndex > 0) {
    const immediatelyBefore = lines[colourIndex - 1];
    const separateModelCode = immediatelyBefore.match(/^([A-Z0-9-]{5,})\s+(\d{3})$/i);
    if (separateModelCode && colourIndex > 1) {
      modelCode = `${separateModelCode[1]} ${separateModelCode[2]}`;
      vehicle = lines[colourIndex - 2];
      metadataIndexes.add(colourIndex - 2);
      metadataIndexes.add(colourIndex - 1);
    } else {
      const combinedModelCode = immediatelyBefore.match(/\s+([A-Z0-9-]{5,})\s+(\d{3})$/i);
      modelCode = combinedModelCode ? `${combinedModelCode[1]} ${combinedModelCode[2]}` : '';
      vehicle = combinedModelCode ? immediatelyBefore.slice(0, combinedModelCode.index).trim() : immediatelyBefore;
      metadataIndexes.add(colourIndex - 1);
    }
  }

  const lineItems = [];
  let currentLineItem = null;
  const wrappedDescriptionIndexes = new Set();
  lines.forEach((line, index) => {
    if (wrappedDescriptionIndexes.has(index)) return;
    let itemLine = line;
    const nextLine = lines[index + 1] || '';
    if (/^[!A-Z][A-Z0-9_*!-]{1,40}$/.test(line) && /\s+\d+(?:\.\d+)?\s+\$?[\d,.]+\s+\$?[\d,.]+$/.test(nextLine)) {
      itemLine = `${line} ${nextLine}`;
      wrappedDescriptionIndexes.add(index + 1);
    }
    const itemMatch = itemLine.match(/^([!A-Z][A-Z0-9_*!-]{1,40})\s+(.+?)\s+(\d+(?:\.\d+)?)\s+\$?([\d,.]+)\s+\$?([\d,.]+)$/);
    if (itemMatch) {
      if (/^PO\d{6,}$/i.test(itemMatch[1])) return;
      currentLineItem = {
        item: itemMatch[1],
        description: itemMatch[2].trim(),
        quantity: itemMatch[3],
        unitPrice: itemMatch[4],
        extendedPrice: itemMatch[5],
      };
      lineItems.push(currentLineItem);
      return;
    }
    if (/^Stock\s*#/i.test(line)) {
      currentLineItem = null;
      return;
    }
    if (!currentLineItem || metadataIndexes.has(index)) return;
    if (/^(PURCHASE ORDER|Printed|\d{1,2}\/\d{1,2}\/\d{2,4}\s+\d{1,2}:\d{2}|To Deliver To|PILBARA MOTOR GROUP|PO BOX|CNR\b|BROOME\b|MALAGA\b|PH:|P\.O\. No\.|PO\d{6,}\b|Item Description|Text$|\*+\s*CONTINUED|TOTAL$|Total Exc\.|GST\b|Purchase order number|No backorders|Authorised Signature|\(Includes GST\))/i.test(line)) return;
    if (line.length <= 160 && !/^[\d$,. ]+$/.test(line)) currentLineItem.description = `${currentLineItem.description} ${line}`.replace(/\s+/g, ' ').trim();
  });

  const totalMatches = [...raw.matchAll(/\$\s*([\d,]+\.\d{2})/g)];
  const tasks = [...new Set(lineItems.map(item => item.description).filter(Boolean))];
  return {
    sourceFilename,
    purchaseOrderNumber,
    stock,
    dueDate,
    issuedBy,
    salesperson: purchaseOrderSalespersonCode(issuedBy),
    department,
    reference,
    printedDate: (printedMatch && printedMatch[1]) || '',
    printedTime: (printedMatch && printedMatch[2]) || '',
    deliverTo,
    client: purchaseOrderClientFromDeliverTo(deliverTo),
    vehicle,
    modelCode,
    colourCode: colour.code,
    colour: colour.description,
    trimCode: trim.code,
    trim: trim.description,
    factoryOption,
    alternateModel,
    engine,
    buildDate,
    vin,
    totalIncGst: totalMatches.length ? totalMatches[totalMatches.length - 1][1] : '',
    lineItems,
    tasks,
  };
}

function findVehicleForPurchaseOrder(parsed = {}) {
  const stock = normalizeBatch(parsed.stock);
  const reference = normalizeBatch(parsed.reference);
  const vin = normalizeVin(parsed.vin);
  return app.data.find(vehicle => {
    const identities = [vehicle.stock, vehicle.batch, vehicle.order, vehicle.toyotaBatch].map(normalizeBatch).filter(Boolean);
    const vehicleVin = normalizeVin(vehicle.vin || vehicle.autocareVin || vehicle.frameVin);
    return (stock && identities.includes(stock)) || (reference && identities.includes(reference)) || (vin && vehicleVin === vin);
  }) || null;
}

function ensureVehicleForPo(stockOrParsed) {
  const parsed = typeof stockOrParsed === 'object' ? stockOrParsed : { stock: String(stockOrParsed || '') };
  const stock = String(parsed.stock || parsed.reference || '').trim();
  let vehicle = findVehicleForPurchaseOrder(parsed);
  if (vehicle) return promoteVehicleToPdcSheet(vehicle, 'Purchase order upload');
  vehicle = {
    id: `po-${stock}`,
    sourceRow: '',
    stock,
    batch: stock,
    client: parsed.client || 'Broome Toyota',
    internalStatus: '',
    deliveryDate: '',
    vehicle: parsed.vehicle || '',
    financeNote: '',
    group: 'Purchase order upload',
    source: 'Purchase order upload',
    recordLifecycle: 'purchase-order',
    pdcSheetVisible: true,
    pdcVisibilitySource: 'Purchase order upload',
    pdcPromotedAt: nowIsoString(),
    order: '',
    toyotaCustomer: '',
    contact: '',
    toyotaVehicle: parsed.vehicle || '',
    suffix: '',
    colour: parsed.colour || '',
    trim: parsed.trim || '',
    origMth: '',
    prodMth: '',
    compPlate: '',
    arrivalPort: '',
    toyotaStatus: '',
    etaAtDealer: '',
    epodReceipt: '',
    jitQty: '',
    jitaPartsOrdered: 'Unknown',
    consultant: parsed.salesperson || '',
    vin: parsed.vin || '',
    poTasks: [],
    poFiles: [],
  };
  const added = loadAddedVehicles();
  added.unshift(vehicle);
  saveAddedVehicles(added);
  app.data.unshift(vehicle);
  return vehicle;
}

function purchaseOrderVehicleUpdates(vehicle, parsed, combinedTasks, combinedFiles) {
  const flags = workImportRequirementUpdates(parsed, vehicle, combinedTasks);
  const wasReviewed = Boolean(parsed.reviewRequirementUpdates && typeof parsed.reviewRequirementUpdates === 'object');
  const importedJobLines = (parsed.lineItems || []).map(pdcJobLineFromPurchaseOrderItem);
  const updates = {
    purchaseOrderNumber: parsed.purchaseOrderNumber,
    purchaseOrderDueDate: parsed.dueDate,
    purchaseOrderIssuedBy: parsed.issuedBy,
    purchaseOrderDepartment: parsed.department,
    purchaseOrderReference: parsed.reference,
    purchaseOrderPrintedDate: parsed.printedDate,
    purchaseOrderPrintedTime: parsed.printedTime,
    purchaseOrderDeliverTo: parsed.deliverTo,
    purchaseOrderTotalIncGst: parsed.totalIncGst,
    purchaseOrderModelCode: parsed.modelCode,
    purchaseOrderColourCode: parsed.colourCode,
    purchaseOrderTrimCode: parsed.trimCode,
    purchaseOrderFactoryOption: parsed.factoryOption,
    purchaseOrderAlternateModel: parsed.alternateModel,
    purchaseOrderEngine: parsed.engine,
    purchaseOrderBuildDate: parsed.buildDate,
    purchaseOrderLineItems: parsed.lineItems,
    pdcManualJobLines: mergePdcJobLines(vehicle.pdcManualJobLines || [], importedJobLines),
    poTasks: combinedTasks,
    poFiles: combinedFiles,
    buildPoRaised: true,
    pdcSheetVisible: true,
    pdcVisibilitySource: 'Purchase order upload',
    pdcPromotedAt: vehicle.pdcPromotedAt || nowIsoString(),
    pdcLocation: vehiclePdcLocation(vehicle) || 'PMB',
  };
  Object.entries(flags).forEach(([key, value]) => {
    updates[key] = wasReviewed ? value === true : value === true || vehicle[key] === true;
  });
  if ((!vehicle.client || /customer (?:from|not on) po/i.test(vehicle.client)) && parsed.client) updates.client = parsed.client;
  if (!cleanNavisionText(vehicle.vehicle) && parsed.vehicle) updates.vehicle = parsed.vehicle;
  if (!cleanNavisionText(vehicle.toyotaVehicle) && parsed.vehicle) updates.toyotaVehicle = parsed.vehicle;
  if (!cleanNavisionText(vehicle.colour) && parsed.colour) updates.colour = parsed.colour;
  if (!cleanNavisionText(vehicle.trim) && parsed.trim) updates.trim = parsed.trim;
  if (!normalizeVin(vehicle.vin) && parsed.vin) updates.vin = parsed.vin;
  if ((!vehicle.consultant || consultantName(vehicle) === 'Unassigned') && parsed.salesperson) updates.consultant = parsed.salesperson;
  Object.assign(updates, workImportVehicleUpdates(parsed));
  return updates;
}

function persistPurchaseOrderVehicleUpdates(vehicle, updates) {
  const key = vehicleKey(vehicle);
  Object.assign(vehicle, updates);
  const edits = loadVehicleEdits();
  edits[key] = { ...(edits[key] || {}), ...updates };
  saveJson(EDITS_KEY, edits);
}

function applyPurchaseOrderImport(parsed, filename) {
  return runStorageTransaction('Purchase-order import', trackerTransactionKeys(), () => applyPurchaseOrderImportUnsafe(parsed, filename));
}

function applyPurchaseOrderImportUnsafe(parsed, filename) {
  const existing = findVehicleForPurchaseOrder(parsed);
  const vehicle = ensureVehicleForPo(parsed);
  const key = vehicleKey(vehicle);
  const tasksStore = loadPoTasks();
  const filesStore = loadPoFiles();
  const currentTasks = tasksStore[key] || vehicle.poTasks || [];
  const combinedTasks = [...new Set(currentTasks.concat(parsed.tasks || []))];
  const currentFiles = filesStore[key] || vehicle.poFiles || [];
  const combinedFiles = [...new Set(currentFiles.concat(filename || parsed.sourceFilename || []).filter(Boolean))];
  tasksStore[key] = combinedTasks;
  filesStore[key] = combinedFiles;
  savePoTasks(tasksStore);
  savePoFiles(filesStore);
  persistPurchaseOrderVehicleUpdates(vehicle, purchaseOrderVehicleUpdates(vehicle, parsed, combinedTasks, combinedFiles));
  recordVehicleAudit(vehicle, existing ? 'Purchase order matched' : 'Vehicle created from purchase order', {
    purchaseOrder: parsed.purchaseOrderNumber,
    file: filename,
    tasks: (parsed.tasks || []).length,
  });
  return { vehicle, created: !existing, taskCount: (parsed.tasks || []).length, totalTasks: combinedTasks.length };
}

async function handleVehiclePoSelect(key, event) {
  const files = [...(event.target.files || [])];
  if (!files.length) return;
  const selected = selectedVehicle(key);
  if (!selected) return;
  const selectedStock = normalizeBatch(selected.stock || selected.batch);
  const messages = [];
  let importedCount = 0;
  for (const file of files) {
    try {
      const parsed = parsePurchaseOrderText(await extractTextFromPdfFile(file), file.name);
      if (!parsed.stock && selectedStock) parsed.stock = selectedStock;
      if (selectedStock && normalizeBatch(parsed.stock) !== selectedStock) {
        throw new Error(`This PO is for stock ${parsed.stock}, not ${displayStockNumber(selected) || selectedStock}.`);
      }
      const reviewed = await showWorkImportReviewModal({ kind: 'po', parsed, filename: file.name, existing: selected });
      if (!reviewed) {
        messages.push(`${file.name}: import cancelled; no changes saved.`);
        continue;
      }
      const result = applyPurchaseOrderImport(reviewed, file.name);
      importedCount += 1;
      messages.push(`${reviewed.purchaseOrderNumber || file.name}: ${result.taskCount} work items imported after review.`);
    } catch (error) {
      messages.push(`${file.name}: ${error.message || error}`);
    }
  }
  app.data = buildVehicleData();
  if (importedCount) {
    updateOperationalHealth({
      lastWorkImportAt: nowIsoString(),
      lastWorkImportType: 'Purchase order',
      lastWorkImportRows: importedCount,
    });
  }
  renderAll();
  app.selectedStock = vehicleKey(selected);
  renderDetail();
  if (messages.some(message => /not |No Stock|could not|error/i.test(message))) window.alert(messages.join('\n'));
  event.target.value = '';
}

async function handlePoSelect(e) {
  const files = [...(e.target.files || [])];
  const statusList = $('#po-status-list');
  const card = $('#po-scan-card');
  if (!files.length) return;
  if (statusList) statusList.innerHTML = '<div class="po-status-row"><strong>Reading PDFs</strong><span>Extracting stock, vehicle details and PMB work items...</span></div>';
  if (card) {
    card.querySelector('.po-files strong').textContent = `${files.length} file${files.length === 1 ? '' : 's'}`;
    card.querySelector('.po-matched strong').textContent = 'Reading...';
    card.querySelector('.po-created strong').textContent = 'Reading...';
  }
  const results = [];
  for (const file of files) {
    try {
      const text = await extractTextFromPdfFile(file);
      const parsed = parsePurchaseOrderText(text, file.name);
      const reviewed = await showWorkImportReviewModal({
        kind: 'po',
        parsed,
        filename: file.name,
        existing: findVehicleForPurchaseOrder(parsed),
      });
      if (!reviewed) {
        results.push({ ok: false, cancelled: true, file: file.name, stock: parsed.stock || '', created: false, message: 'Import cancelled. No vehicle data was changed.' });
        continue;
      }
      const applied = applyPurchaseOrderImport(reviewed, file.name);
      const selectedWork = PDC_JOB_DEFS.filter(def => reviewed.reviewRequirementUpdates?.[def.requireKey]).map(def => def.label);
      results.push({
        ok: true,
        file: file.name,
        stock: reviewed.stock,
        created: applied.created,
        po: reviewed.purchaseOrderNumber,
        vehicle: reviewed.vehicle,
        count: applied.taskCount,
        vehicleKey: vehicleKey(applied.vehicle),
        message: `${applied.created ? 'Created new active vehicle from PO' : 'Matched existing vehicle'} · Required work: ${selectedWork.join(', ') || 'none selected'} · ${reviewed.client}`,
      });
    } catch (error) {
      results.push({ ok: false, file: file.name, stock: '', created: false, message: error.message || String(error) });
    }
  }
  app.data = buildVehicleData();
  const successfulImports = results.filter(result => result.ok);
  if (successfulImports.length) {
    updateOperationalHealth({
      lastWorkImportAt: nowIsoString(),
      lastWorkImportType: 'Purchase order',
      lastWorkImportRows: successfulImports.length,
    });
  }
  if (card) {
    card.querySelector('.po-matched strong').textContent = `${results.filter(result => result.ok).length} active`;
    card.querySelector('.po-created strong').textContent = `${results.filter(result => result.ok && result.created).length} new`;
  }
  if (statusList) {
    statusList.innerHTML = results.map(result => `<div class="po-status-row ${result.ok ? 'ok' : 'warn'}"><strong>${escapeHtml(result.stock || 'Not imported')}</strong><span>${result.po ? `<b>${escapeHtml(result.po)}</b> · ` : ''}${result.vehicle ? `${escapeHtml(result.vehicle)} · ` : ''}${escapeHtml(result.message)}<small>${escapeHtml(result.file)}</small></span></div>`).join('');
  }
  app.quickFilter = 'incoming';
  populateFilters();
  renderAll();
  focusVehiclesAfterWorkImport(results.filter(result => result.ok).map(result => result.vehicleKey));
  e.target.value = '';
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
  if (result.vehicles?.length && window.confirm(`Autocare notice loaded ${result.vehicles.length} vehicle${result.vehicles.length === 1 ? '' : 's'}.\n\nPrint one Zebra label for each vehicle now?`)) {
    await printZplFromAutocareResults('all');
  }
}

async function extractTextFromPdfFile(file) {
  if (!window.pdfjsLib) {
    try {
      await loadExternalScript('vendor/pdfjs/pdf.min.js?v=3.11.174', 'pdfjs-script');
      if (window.pdfjsLib) window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'vendor/pdfjs/pdf.worker.min.js?v=3.11.174';
    } catch (_) {
      // The built-in lightweight reader below remains available when PDF.js cannot load.
    }
  }
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

function autocarePmbArrivalUpdates(vehicle = {}, arrivedAt = nowIsoString()) {
  const explicitLocation = vehiclePdcLocation(vehicle);
  const category = vehicleCollectedFromRft(vehicle)
    ? 'completed'
    : explicitLocation === 'RFT'
      ? 'rft'
      : explicitLocation === 'PMB'
        ? 'pmb'
        : statusCategory(vehicle);
  const alreadyFurtherAlong = category === 'rft' || category === 'completed';
  const alreadyAtPmb = category === 'pmb';
  const updates = {
    pdcSheetVisible: true,
    pdcVisibilitySource: 'Autocare despatch notice - PMB arrival',
    pdcPromotedAt: vehicle.pdcPromotedAt || arrivedAt,
  };
  if (alreadyFurtherAlong) {
    return {
      updates,
      arrivalNote: category === 'completed'
        ? 'Autocare arrival recorded; Completed location retained'
        : 'Autocare arrival recorded; RFT location retained',
      movedToPmb: false,
    };
  }
  Object.assign(updates, {
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    pdcLocationDerivedFromNavision: false,
    pdcLocationUpdatedAt: arrivedAt,
    pmbEnteredAt: pmbEnteredTimestamp(vehicle) || arrivedAt,
  });
  if (!alreadyAtPmb) {
    Object.assign(updates, {
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
    });
  }
  return {
    updates,
    arrivalNote: alreadyAtPmb
      ? `PMB arrival confirmed; ${pmbStageLabel(inferredPmbStage(vehicle)) || 'Unallocated'} retained`
      : 'Arrived at PMB; placed in Unallocated',
    movedToPmb: !alreadyAtPmb,
  };
}

function migrateLegacyAutocareArrivalsToPmb() {
  const edits = loadVehicleEdits();
  let migrated = 0;
  app.data.forEach(vehicle => {
    if (!isAutocareDespatched(vehicle)) return;
    const explicitLocation = vehiclePdcLocation(vehicle);
    if (vehicleCollectedFromRft(vehicle) || explicitLocation === 'RFT' || explicitLocation === 'PMB') return;
    const arrivedAt = parseIsoTimestamp(vehicle.autocareUpdatedAt)?.toISOString() || nowIsoString();
    const arrival = autocarePmbArrivalUpdates(vehicle, arrivedAt);
    const key = vehicleKey(vehicle);
    if (!key) return;
    edits[key] = { ...(edits[key] || {}), ...arrival.updates };
    migrated += 1;
  });
  if (migrated) {
    saveJson(EDITS_KEY, edits);
    app.data = buildVehicleData();
  }
  return migrated;
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
    const arrival = autocarePmbArrivalUpdates(match.vehicle, updatedAt);
    const updates = {
      ...arrival.updates,
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
    matched.push({ vehicle: { ...match.vehicle }, item, matchedBy: match.matchedBy, previousStatus: match.vehicle.toyotaStatus || '', arrivalNote: arrival.arrivalNote, movedToPmb: arrival.movedToPmb });
    recordVehicleAudit(match.vehicle, 'Autocare PMB arrival recorded', {
      matchedBy: match.matchedBy,
      loadNumber: parsed.loadNumber || '',
      outcome: arrival.arrivalNote,
    });
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
    return `<div class="summary-row ok autocare-result-row"><div>${vehicleIdentityStackHtml(current)}<span>${escapeHtml(displayVehicle(current) || row.item.model || 'Vehicle')} · matched by ${escapeHtml(row.matchedBy)}${row.previousStatus ? ` · was ${escapeHtml(row.previousStatus)}` : ''} · ${escapeHtml(row.arrivalNote || 'Arrived at PMB')}</span></div><button class="small-button" type="button" data-autocare-zpl-single="matched:${escapeHtml(key)}">Print label</button></div>`;
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
      <h3>Matched vehicles — PMB arrival recorded</h3>
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
    '',
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
  if (!confirmZplWarnings(print.warnings, `${print.count} Autocare vehicle${print.count === 1 ? '' : 's'}`)) return;
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
  if (!confirmZplWarnings(print.warnings, 'one Autocare vehicle')) return;
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
  const dealerCode = ($('#navision-dealer-code')?.value || '').trim();
  const sharedMode = Boolean($('#navision-dealer-code')) && Boolean(navisionSharedBackendService());
  if (sharedMode && app.pendingSharedNavisionImport && (app.pendingSharedNavisionImport.dealerCode !== dealerCode || app.pendingSharedNavisionImport.sourceTextSha256 !== sha256Hex(raw))) {
    app.pendingSharedNavisionImport = null;
  }
  const button = $('#import-navision');
  const applyButton = $('#apply-navision-shared');
  const clear = $('#navision-clear');
  if (button) button.disabled = !raw || (sharedMode && !['14450', '37047'].includes(dealerCode));
  if (applyButton) applyButton.disabled = !app.pendingSharedNavisionImport;
  if (clear) clear.disabled = !raw && !app.navisionImport && !app.pendingSharedNavisionImport;
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
      const headerNote = parsed.headerRowIndex > 0 ? `; headings found on workbook row ${parsed.headerRowIndex + 1}` : '';
      sourceLabel = `Excel sheet converted: ${parsed.sheetName || 'first sheet'} (${parsed.rows.length} row${parsed.rows.length === 1 ? '' : 's'}${headerNote})`;
    } else if (/\.xls$/i.test(file.name)) {
      throw new Error('Legacy .xls files are not supported in this browser-only version. Save the spreadsheet as .xlsx, .csv or .tsv and upload it again.');
    } else {
      text = await readTextFile(file);
    }
    if (input) input.value = text;
    updateNavisionImportButton();
    const preview = parseNavisionInput(text, navisionImportOptionsFromDom());
    if (summary) {
      const warning = preview.vehicles.length ? '' : ` ${preview.warnings?.[0] || 'No usable vehicle rows were found.'}`;
      summary.innerHTML = `<div class="empty-state compact-empty"><strong>${escapeHtml(file.name)}</strong><span>${escapeHtml(sourceLabel)}. ${preview.vehicles.length} vehicle row${preview.vehicles.length === 1 ? '' : 's'} detected.${escapeHtml(warning)}${preview.vehicles.length ? ' Click Import vehicle updates to continue.' : ''}</span></div>`;
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
    const headerRowIndex = findNavisionHeaderRowIndex(rows);
    if (headerRowIndex >= 0) {
      const importRows = rows.slice(headerRowIndex);
      return {
        sheetName: sheet.name || sheet.path,
        rows: importRows,
        text: xlsxRowsToDelimitedText(importRows),
        headerRowIndex,
      };
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
  app.pendingSharedNavisionImport = null;
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

function navisionHeaderRowScore(row = []) {
  const headers = (Array.isArray(row) ? row : []).map(normalizeNavisionHeader).filter(Boolean);
  if (!headers.length) return 0;
  const has = aliases => aliases.some(alias => headers.includes(normalizeNavisionHeader(alias)));
  const identity = has(['Batch', 'Batch Number', 'Batch No', 'Batch No.', 'Stock', 'Stock Number', 'Vehicle Stock Number', 'SN', 'Stock No', 'Stock No.', 'Order', 'Toyota Order', 'Order Number']);
  const vehicle = has(['Model Description', 'Model Desc', 'Model Desc.', 'Vehicle Description', 'Vehicle', 'Model']);
  const workFile = has(['PDC Job Card', 'Job Card', 'Job Card Number', 'Work File', 'Body Builder', 'PDC Location', 'PMB Bucket', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT INSPECTION', 'PARTS']);
  if (!identity || (!vehicle && !workFile)) return 0;
  let score = 10;
  if (has(['Order', 'Toyota Order', 'Order Number'])) score += 2;
  if (has(['Customer Surname', 'Dealer Customer Name', 'Customer', 'Client'])) score += 1;
  if (has(['Sub Location Description', 'Location Status'])) score += 1;
  if (has(['ETA At Kewdale Yard', 'ETA to Kewdale', 'ETA To Kewdale'])) score += 1;
  if (has(['JITA PreOrder', 'JITA'])) score += 1;
  return score;
}

function findNavisionHeaderRowIndex(rows = []) {
  let bestIndex = -1;
  let bestScore = 0;
  (Array.isArray(rows) ? rows : []).slice(0, 80).forEach((row, index) => {
    const score = navisionHeaderRowScore(row);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  });
  return bestIndex;
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
    ['pdcRequiresBus4x4', ['BUS 4X4', 'Bus 4x4', 'BUS_4X4', 'Requires Bus 4x4', 'Bus 4x4 Required', 'Department 138']],
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
  const jobCard = explicitImportValue(row, headerMap, ['PDC Job Card', 'Job Card', 'Job Card Number', 'Jobcard', 'Work File', 'Work Number']);
  if (jobCard.present) updates.pdcJobcard = jobCard.value;
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
  if (cleanNavisionText(updates.pdcJobcard || '')) return true;
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

function navisionImportIsFullRefresh() {
  return !Boolean($('#navision-pmb-only')?.checked);
}

function pmbWorkSkipMessage(vehicle = {}, excelRow) {
  const identity = displayStockNumber(vehicle) || vehicle.order || `row ${excelRow}`;
  return `Row ${excelRow}${identity ? ` / ${identity}` : ''}: skipped because PDC work / job file mode is on and no work signal was found.`;
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
    'pdcBlocked','pdcBlockReason','pdcLocation','pmbStage','pdcJobcard'
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

function navisionAutoPdcLocation(vehicle = {}) {
  const locationStatus = normalizeToyotaStatus(vehicle.navisionLocationStatus || '');
  const subLocation = normalizeToyotaStatus(vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || '');
  const text = navisionLocationSourceText(vehicle);
  if (!text) return '';
  if (locationStatus === 'yh' || subLocation.includes('yard hold') || /\byh\b/.test(text)) return '';
  if (locationStatus === 'pmb' || navisionTextIsBodyBuilder(text) || text.includes('on consignment') || text.includes('out on consignment')) return 'PMB';
  if (locationStatus === 'rft' || /\brft\b/.test(text) || text.includes('ready for transport') || text.includes('ready for transfer')) return 'RFT';
  return '';
}

function applyNavisionAutoPdcLocation(payload = {}, incoming = {}, existing = {}) {
  const autoLocation = navisionAutoPdcLocation(incoming);
  if (!autoLocation) return payload;
  if (existing && (existing.pdcLocationLocked || existing.manualLocation || vehiclePdcLocation(existing))) return payload;
  if (normalizePdcLocation(payload.pdcLocation || '')) return payload;
  const now = nowIsoString();
  payload.pdcLocation = autoLocation;
  payload.pdcLocationUpdatedAt = now;
  if (autoLocation === 'PMB') {
    payload.pmbEnteredAt = pmbEnteredTimestamp(existing) || now;
    payload.pmbTransferredAt = existing.pmbTransferredAt || now;
    protectPmbFirstLandingFromImport(payload, existing);
  }
  if (autoLocation === 'RFT') {
    payload.rftTransferredAt = existing.rftTransferredAt || now;
  }
  return payload;
}

function vehicleLooksNonToyota(vehicle = {}) {
  const text = [vehicle.make, vehicle.manufacturer, vehicle.brand, vehicle.vehicleMake, vehicle.vehicleManufacturer, vehicle.vehicle, vehicle.toyotaVehicle, vehicle.model, vehicle.modelDescription, vehicle.navisionDealerComments, vehicle.financeNote]
    .map(value => cleanNavisionText(value || '').toLowerCase())
    .filter(Boolean)
    .join(' ');
  return /\b(nissan|isuzu|ford|mazda|mitsubishi|subaru|hyundai|kia|volkswagen|vw|ldv|gwm|haval|ram|chevrolet|holden|hino|fuso|mercedes|benz|iveco)\b/.test(text);
}

function vehicleLooksToyota(vehicle = {}) {
  if (vehicleLooksNonToyota(vehicle)) return false;
  const text = [vehicle.make, vehicle.manufacturer, vehicle.brand, vehicle.vehicleMake, vehicle.vehicleManufacturer, vehicle.vehicle, vehicle.toyotaVehicle, vehicle.model, vehicle.modelDescription, vehicle.source, vehicle.group, vehicle.toyotaStatus]
    .map(value => cleanNavisionText(value || '').toLowerCase())
    .filter(Boolean)
    .join(' ');
  if (/\btoyota\b/.test(text)) return true;
  if (vehicle.toyotaStatus || vehicle.toyotaVehicle || vehicle.toyotaCustomer || vehicle.order || vehicle.navisionSubLocationDescription || /navision/.test(text)) return true;
  return false;
}

function buildNavisionVehicle(row, headerMap, excelRow, options = {}) {
  const order = getNavisionValue(row, headerMap, ['Order', 'Toyota Order', 'Toyota Order Number', 'Order Number']);
  const batch = getNavisionValue(row, headerMap, ['Batch', 'Batch Number', 'Batch No', 'Batch No.', 'Stock', 'Stock Number', 'Vehicle Stock Number', 'SN', 'Stock No', 'Stock No.']);
  const stock = isBlankStock(batch) ? '' : batch;
  const mainId = stock || order;
  const modelDescription = getNavisionValue(row, headerMap, ['Model Description', 'Model Desc', 'Model Desc.', 'Vehicle Description', 'Vehicle', 'Model']);
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
  const workFileMode = options.pmbOnly === true || options.workFile === true;
  const explicitPdcUpdates = workFileMode ? protectPmbFirstLandingFromImport(buildExplicitPdcUpdatesFromImport(row, headerMap), {}) : {};
  const payload = {
    id: `navision-${mainId || excelRow}`,
    sourceRow: excelRow,
    stock,
    batch: batch || stock,
    order,
    keyNumber,
    client: customer,
    customerSurname,
    dealerCustomerName,
    toyotaCustomer: dealerCustomerName || customer,
    contact: '',
    internalStatus: 'Allocate vehicle, generate orders',
    deliveryDate: navisionExpectedDelivery(row, headerMap),
    vehicle: [modelDescription, suffixDescription].filter(Boolean).join(' '),
    modelDescription,
    suffixDescription,
    trimDescription,
    colourDescription,
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
    ...explicitPdcUpdates,
    recordLifecycle: 'navision',
    pdcImportMode: workFileMode ? 'work-file' : 'navision',
    importedAt: new Date().toISOString(),
  };
  const pdcVisibilitySignal = workFileMode && navisionHasPmbWorkSignal(row, headerMap, payload);
  payload.pdcSheetVisible = Boolean(pdcVisibilitySignal);
  payload.pdcVisibilitySource = pdcVisibilitySignal ? 'PDC work / job file upload' : 'Navision back end only';
  return workFileMode ? applyNavisionAutoPdcLocation(payload, payload, {}) : payload;
}

function prepareNavisionText(text = '') {
  let value = restoreNavisionExpandedTabs(String(text || '')).trim();
  const looksLikeQuotedCsvOrTsv = /^"[^"\r\n]*"[\t,;]/.test(value);
  const wrappedInStraightQuotes = value.startsWith('"') && value.endsWith('"') && !looksLikeQuotedCsvOrTsv;
  const wrappedInSmartQuotes = value.startsWith('“') && value.endsWith('”');
  if (wrappedInStraightQuotes || wrappedInSmartQuotes) {
    value = value.slice(1, -1);
  }
  return value;
}

function restoreNavisionExpandedTabs(text = '', tabWidth = 6) {
  // Some Navision copy operations expand each tab to enough U+2002 EN SPACE
  // characters to reach the next six-character tab stop. Reconstruct the
  // original tabs, including consecutive tabs that represent blank cells.
  return String(text || '').split(/\r?\n/).map(line => {
    const characters = Array.from(line);
    let output = '';
    let column = 0;
    for (let index = 0; index < characters.length; index += 1) {
      const character = characters[index];
      if (character !== '\u2002') {
        output += character;
        column += 1;
        continue;
      }
      let runLength = 1;
      while (characters[index + runLength] === '\u2002') runLength += 1;
      const firstTabWidth = tabWidth - (column % tabWidth || 0);
      const remainder = runLength - firstTabWidth;
      if (remainder >= 0 && remainder % tabWidth === 0) {
        output += '\t'.repeat(1 + (remainder / tabWidth));
      } else {
        // A non-tab-aligned EN SPACE run is still a delimiter in Navision text.
        output += '\t';
      }
      column += runLength;
      index += runLength - 1;
    }
    return output;
  }).join('\n');
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
  const headerRowIndex = findNavisionHeaderRowIndex(rows);
  const resolvedHeaderRowIndex = headerRowIndex >= 0 ? headerRowIndex : 0;
  const rawHeaders = rows[resolvedHeaderRowIndex].map(header => String(header ?? '').replace(/^\uFEFF/, ''));
  const headers = rawHeaders.map(header => cleanNavisionText(header));
  const headerMap = buildNavisionHeaderMap(headers);
  const hasIdentityColumn = ['Batch', 'Batch Number', 'Batch No', 'Batch No.', 'Stock', 'Stock Number', 'Vehicle Stock Number', 'SN', 'Stock No', 'Stock No.'].some(column => hasNavisionColumn(headerMap, column));
  const hasOrderColumn = ['Order', 'Toyota Order', 'Toyota Order Number', 'Order Number'].some(column => hasNavisionColumn(headerMap, column));
  const hasVehicleColumn = ['Model Description', 'Model Desc', 'Model Desc.', 'Vehicle Description', 'Vehicle', 'Model'].some(column => hasNavisionColumn(headerMap, column));
  const missing = [];
  if (!hasIdentityColumn && !hasOrderColumn) missing.push('Batch/Stock or Toyota Order');
  if (!hasVehicleColumn && !options.pmbOnly && !options.workFile) missing.push('Model Description / Vehicle');
  if (missing.length) {
    return {
      vehicles: [],
      warnings: [`Missing required columns: ${missing.join(', ')}.`],
      missing,
      delimiter: detected.delimiter,
      options,
    };
  }

  const importOptions = { pmbOnly: false, ...options };
  const warnings = [];
  if (resolvedHeaderRowIndex > 0) warnings.push(`Navision headings were detected on row ${resolvedHeaderRowIndex + 1}; the report title rows above them were ignored.`);
  if (!hasNavisionColumn(headerMap, 'Sub Location Description')) {
    warnings.push('Sub Location Description column was not found, so Toyota Status will be blank for this import.');
  }
  if (importOptions.pmbOnly) {
    warnings.push('PDC work / job file mode is on: matching rows are promoted to the PDC Sheet; rows without a work signal are skipped.');
  }
  const vehicles = [];
  const rejectedRows = [];
  rows.slice(resolvedHeaderRowIndex + 1).forEach((row, index) => {
    const excelRow = resolvedHeaderRowIndex + index + 2;
    const vehicle = buildNavisionVehicle(row, headerMap, excelRow, importOptions);
    const rawEvidence = {
      sourceRow: excelRow,
      columns: rawHeaders.map((header, columnIndex) => ({ header, value: String(row[columnIndex] ?? '') })),
    };
    vehicle.navisionRawEvidence = rawEvidence;
    if (!vehicle.stock && !vehicle.order && !vehicle.vin) {
      warnings.push(`Row ${excelRow}: skipped because Batch / Stock, Toyota Order and VIN are all blank.`);
      rejectedRows.push(rawEvidence);
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
  return { vehicles, rejectedRows, warnings, missing: [], delimiter: detected.delimiter, options: importOptions };
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
  return !isNavisionOnlyBackEndVehicle(vehicle);
}

function vehiclesMissingFromNavisionImport(existingRows = [], incomingRows = [], options = {}) {
  const fullRefresh = options.fullRefresh !== false;
  if (!fullRefresh) return [];
  const candidates = existingRows.filter(isNavisionOnlyBackEndVehicle).filter(vehicleLooksToyota);
  if (!candidates.length) return [];
  if (!incomingRows.length) return candidates.slice();
  return candidates.filter(vehicle => !incomingRows.some(incoming => navisionVehiclesOverlap(incoming, vehicle)));
}

function deletedVehicleRecordMatchesNavision(record = {}, incoming = {}) {
  if (record.vehicle && navisionVehiclesOverlap(record.vehicle, incoming)) return true;
  const incomingKeys = new Set(navisionComparableKeys(incoming));
  return [record.key].concat(record.keys || [])
    .map(value => normalizeBatch(value))
    .filter(Boolean)
    .some(key => incomingKeys.has(key));
}

function deletedRecordForNavision(records = [], incoming = {}) {
  return (Array.isArray(records) ? records : []).find(record => deletedVehicleRecordMatchesNavision(record, incoming)) || null;
}

function navisionCanRestoreDeletedRecord(record = {}) {
  return cleanNavisionText(record.deletionType || '').toLowerCase() === 'navision-missing';
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
  const workFileMode = incoming.pdcImportMode === 'work-file';
  const independentlyPromoted = vehicleWasIndependentlyPromoted(existing) || Boolean(existing.pdcLocationLocked || existing.navisionLocationLocked || existing.manualLocation);
  const workFilePromotes = workFileMode && incoming.pdcSheetVisible === true;
  const keepVisible = independentlyPromoted || workFilePromotes;
  const payload = {
    source: mergeNavisionSource(existing.source || incoming.source),
    recordLifecycle: existing.recordLifecycle || incoming.recordLifecycle || 'navision',
    pdcSheetVisible: keepVisible,
    pdcVisibilitySource: workFilePromotes
      ? (incoming.pdcVisibilitySource || 'PDC work / job file upload')
      : independentlyPromoted
        ? (existing.pdcVisibilitySource || 'Independent PDC work')
        : 'Navision back end only',
    pdcPromotedAt: keepVisible ? (existing.pdcPromotedAt || incoming.importedAt || nowIsoString()) : '',
    pdcImportMode: workFileMode ? 'work-file' : 'navision',
    importedAt: incoming.importedAt,
    sourceRow: incoming.sourceRow,

    // Navision source fields that should keep refreshing on existing rows.
    prodMth: incoming.prodMth || existing.prodMth || '',
    compPlate: incoming.compPlate || existing.compPlate || '',
    etaAtDealer: workFileMode ? (existing.etaAtDealer || '') : (incoming.etaAtDealer || ''),
    navisionEtaAtDealerBB: workFileMode ? (existing.navisionEtaAtDealerBB || '') : (incoming.navisionEtaAtDealerBB || ''),
    navisionKewdaleEta: workFileMode ? (existing.navisionKewdaleEta || '') : (incoming.navisionKewdaleEta || ''),
    navisionEtaDate: workFileMode ? (existing.navisionEtaDate || '') : (incoming.navisionEtaDate || ''),
    navisionPortPlantEta: workFileMode ? (existing.navisionPortPlantEta || '') : (incoming.navisionPortPlantEta || ''),

    // Core identifiers are allowed so order-only vehicles can receive a real stock/batch number later.
    id: existing.id || incoming.id,
    stock: incoming.stock || existing.stock || '',
    batch: incoming.batch || incoming.stock || existing.batch || existing.stock || '',
    order: incoming.order || existing.order || '',
    wmi: incoming.wmi || existing.wmi || '',
    vdsNumber: incoming.vdsNumber || existing.vdsNumber || '',
    frame: incoming.frame || existing.frame || '',
    vin: incoming.vin || existing.vin || '',
    customerSurname: incoming.customerSurname || existing.customerSurname || '',
    dealerCustomerName: incoming.dealerCustomerName || existing.dealerCustomerName || '',
    modelDescription: incoming.modelDescription || existing.modelDescription || '',
    suffixDescription: incoming.suffixDescription || existing.suffixDescription || '',
    trimDescription: incoming.trimDescription || existing.trimDescription || '',
    colourDescription: incoming.colourDescription || existing.colourDescription || '',

    // Allowed Navision refresh fields.
    trayOrdered: workFileMode ? (incoming.trayOrdered === true || existing.trayOrdered === true) : incoming.trayOrdered,
    trayFitmentComplete: workFileMode ? (incoming.trayFitmentComplete === true || existing.trayFitmentComplete === true) : incoming.trayFitmentComplete,
    jitaPartsOrdered: workFileMode ? (existing.jitaPartsOrdered || 'Unknown') : incoming.jitaPartsOrdered,
    jitQty: workFileMode ? (existing.jitQty || '') : (incoming.jitQty || ''),
    toyotaStatus: workFileMode ? (existing.toyotaStatus || '') : (incoming.toyotaStatus || ''),
    navisionSubLocationDescription: workFileMode ? (existing.navisionSubLocationDescription || '') : (incoming.navisionSubLocationDescription || ''),
    navisionLocationStatus: workFileMode ? (existing.navisionLocationStatus || '') : (incoming.navisionLocationStatus || ''),
    navisionTransportLoadNo: workFileMode ? (existing.navisionTransportLoadNo || '') : (incoming.navisionTransportLoadNo || ''),
    navisionTransportPriority: workFileMode ? (existing.navisionTransportPriority || '') : (incoming.navisionTransportPriority || ''),
    navisionBuildStatus: workFileMode ? (existing.navisionBuildStatus || '') : (incoming.navisionBuildStatus || ''),
    navisionRavStatus: workFileMode ? (existing.navisionRavStatus || '') : (incoming.navisionRavStatus || ''),
    arrivalPort: incoming.arrivalPort || existing.arrivalPort || '',
    navisionDealerComments: workFileMode ? (existing.navisionDealerComments || '') : (incoming.navisionDealerComments || ''),
    financeNote: workFileMode ? (existing.financeNote || '') : (incoming.financeNote || ''),
    navisionVehicleNote: workFileMode ? (existing.navisionVehicleNote || '') : (incoming.navisionVehicleNote || ''),
    navisionCutButVehicle: workFileMode ? Boolean(existing.navisionCutButVehicle) : Boolean(incoming.navisionCutButVehicle),
    navisionCutButVehicleSource: workFileMode ? (existing.navisionCutButVehicleSource || '') : (incoming.navisionCutButVehicleSource || ''),
  };
  if (!workFileMode) {
    const wasOldAutomaticPromotion = /navision pdc work|navision.*location signal/i.test(existing.pdcVisibilitySource || '');
    if (!independentlyPromoted && wasOldAutomaticPromotion) {
      payload.pdcLocation = '';
      payload.pmbStage = '';
      payload.pdcWorkStage = '';
      payload.workStage = '';
      payload.pdcBlocked = false;
      payload.pdcPartsStoppage = false;
      PDC_JOB_DEFS.forEach(def => {
        payload[def.requireKey] = false;
        payload[def.completeKey] = false;
      });
    }
    // Vehicles promoted from Back End Data initially follow their latest Navision
    // location. Once an operator manually transfers/places one, the location lock
    // takes precedence and later daily files cannot move it behind their back.
    const operatorBackendPromotion = existing.pdcVisibilitySource === 'Operator transfer from Back End Data';
    if ((existing.pdcLocationDerivedFromNavision === true || operatorBackendPromotion) && !existing.pdcLocationLocked && !existing.manualLocation) {
      Object.assign(payload, navisionDerivedLocationUpdates(incoming, existing));
    }
    return payload;
  }
  const explicitPayload = applyExplicitPdcImportFields(payload, incoming, existing);
  return applyNavisionAutoPdcLocation(explicitPayload, incoming, existing);
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
    ['pdcSheetVisible', 'PDC Sheet visibility'],
    ['pdcJobcard', 'PDC Job Card'],
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
  const deletedRecords = deletedVehicleRecords();
  const activeBeforeImport = app.data.slice();
  const fullRefresh = navisionImportIsFullRefresh();
  const removeMissingChecked = Boolean($('#navision-remove-missing')?.checked) && fullRefresh;
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
    fullRefresh,
    requiresConfirmation: false,
    confirmed: false,
  };

  parsed.vehicles.forEach(incoming => {
    const deletedRecord = deletedRecordForNavision(deletedRecords, incoming);
    if (deletedRecord && !navisionCanRestoreDeletedRecord(deletedRecord)) {
      result.skipped.push(`${displayStockNumber(incoming) || incoming.order || 'Vehicle'} remains Deleted because it was removed by an operator.`);
      return;
    }
    const existing = findVehicleForNavision(incoming);
    if (deletedRecord) result.restored.push(incoming);

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

  result.missingFromUpload = vehiclesMissingFromNavisionImport(activeBeforeImport, parsed.vehicles, { fullRefresh });
  result.requiresConfirmation = Boolean(result.updated.length || result.stockNumberUpdates.length);
  return result;
}

function navisionSharedBackendService() {
  if (app.navisionSharedBackendService) return app.navisionSharedBackendService;
  const serviceModule = window.PDC_NAVISION_BACKEND_SERVICE;
  const factory = serviceModule?.createNavisionBackendService;
  const config = window.PDC_SUPABASE_CONFIG || {};
  if (typeof factory !== 'function') return null;
  try {
    app.navisionSharedBackendService = factory({
      config,
      projectRef: serviceModule.NAVISION_STAGING_PROJECT_REF,
      getAccessToken: () => window.__pdcCachedAccessToken || null,
    });
    return app.navisionSharedBackendService;
  } catch (error) {
    console.error('Shared Navision service unavailable', error);
    return null;
  }
}

function navisionBrowserAuthoritySha256() {
  const keys = [ADDED_KEY, EDITS_KEY, DELETED_KEY, PO_TASKS_KEY, PO_FILES_KEY, AUDIT_LOG_KEY, NAVISION_IMPORT_RESULTS_KEY, OPERATIONAL_HEALTH_KEY]
    .filter(Boolean).sort();
  return sha256Hex(JSON.stringify(keys.map(key => [key, localStorage.getItem(key)])));
}

function navisionSharedPreviewData(result = null) {
  return result?.data?.data || result?.data || null;
}

function renderSharedNavisionPreview(state = {}, applied = false) {
  const host = $('#navision-status-list');
  if (!host) return;
  const data = navisionSharedPreviewData(applied ? state.applyResult : state.previewResult) || {};
  const counts = data.counts || state.previewData?.counts || {};
  const blocking = data.blocking === true || Number(counts.invalid || 0) > 0 || Number(counts.conflict || 0) > 0;
  const values = ['new', 'changed', 'unchanged', 'missing', 'invalid', 'conflict'];
  host.innerHTML = `<div class="summary-row ${blocking ? 'error' : 'success'}"><strong>${applied ? 'Shared Navision batch applied' : (blocking ? 'Shared preview blocked' : 'Shared preview ready')}</strong><span>Microsoft Navision · dealer ${escapeHtml(state.dealerCode || '')} · browser-local authority SHA-256 ${escapeHtml(state.browserLocalSha256 || '')}</span></div>
    <div class="scot-summary-grid">${values.map(key => `<div class="summary-stat"><span>${escapeHtml(key)}</span><strong>${Number(counts[key] || 0)}</strong></div>`).join('')}</div>
    <div class="subtle navision-note">${applied ? `Durable receipt: ${escapeHtml(data.receipt_id || data.receiptId || 'returned by shared service')} · revision ${escapeHtml(data.revision ?? data.result_revision ?? '')}. Browser-local data was not applied or replaced.` : `Preview hash ${escapeHtml(data.preview_hash || '')}. Apply is enabled only when invalid/conflict totals are zero and the exact preview is unchanged.`}</div>`;
}

async function importNavisionVehicles() {
  const input = $('#navision-paste');
  const text = input?.value || '';
  if (!$('#navision-dealer-code')) return importNavisionVehiclesLocal(text);
  const dealerCode = ($('#navision-dealer-code')?.value || '').trim();
  if (!['14450', '37047'].includes(dealerCode)) {
    window.alert('Select the exact dealer code: Pilbara Toyota 14450 or Broome Toyota 37047. No preview was created.');
    return;
  }
  const options = navisionImportOptionsFromDom();
  const parsed = parseNavisionInput(text, options);
  if (parsed.rejectedRows?.length) {
    app.pendingSharedNavisionImport = null;
    renderNavisionSummary({ parsed, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], skipped: parsed.warnings });
    window.alert('One or more source rows have no Navision identity. Shared preview was blocked so no raw source evidence is silently discarded.');
    updateNavisionImportButton();
    return;
  }
  if (!parsed.vehicles.length) {
    app.pendingSharedNavisionImport = null;
    renderNavisionSummary({ parsed, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], skipped: parsed.warnings });
    updateNavisionImportButton();
    return;
  }
  const service = navisionSharedBackendService();
  if (!service) {
    window.alert('The staging shared Navision backend is unavailable. No localStorage fallback was attempted and no data changed.');
    return;
  }
  const browserLocalSha256 = navisionBrowserAuthoritySha256();
  const rows = parsed.vehicles;
  const metadata = { sourceSystem: 'microsoft_navision', dealerCode, sourceName: app.navisionFileName || 'Pasted text', sourceTimestamp: null };
  const previewResult = await service.preview(rows, metadata);
  if (!previewResult?.ok) {
    app.pendingSharedNavisionImport = null;
    updateNavisionImportButton();
    window.alert(`Shared Navision preview failed: ${previewResult?.error || 'service unavailable'}. No local data changed.`);
    return;
  }
  const previewData = navisionSharedPreviewData(previewResult) || {};
  app.pendingSharedNavisionImport = { rows, parsed, dealerCode, metadata, previewResult, previewData, browserLocalSha256, sourceTextSha256: sha256Hex(text.trim()) };
  renderSharedNavisionPreview(app.pendingSharedNavisionImport);
  updateNavisionImportButton();
}

function importNavisionVehiclesLocal(text = '') {
  const options = navisionImportOptionsFromDom();
  const parsed = parseNavisionInput(text, options);
  if (!parsed.vehicles.length) {
    app.pendingNavisionImport = null;
    renderNavisionSummary({ parsed, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], skipped: parsed.warnings });
    return;
  }
  const result = buildNavisionImportPlan(parsed);
  result.sourceFingerprint = navisionPayloadFingerprint(text, options);
  if (result.requiresConfirmation) {
    app.pendingNavisionImport = result;
    renderNavisionPendingReview(result);
    updateNavisionControlStats(result);
    updateNavisionImportButton();
    return;
  }
  applyNavisionImportPlan(result);
}

async function applySharedNavisionImport() {
  const pending = app.pendingSharedNavisionImport;
  if (!pending) return;
  const data = pending.previewData || {};
  const counts = data.counts || {};
  if (data.blocking === true || Number(counts.invalid || 0) > 0 || Number(counts.conflict || 0) > 0) {
    window.alert('This shared preview has blocking invalid or conflict rows. Correct the file and preview again. Nothing was applied.');
    return;
  }
  if (navisionBrowserAuthoritySha256() !== pending.browserLocalSha256) {
    window.alert('Browser-local operational data changed after preview. Preview again before applying. Nothing was applied.');
    app.pendingSharedNavisionImport = null;
    updateNavisionImportButton();
    return;
  }
  const totals = ['new', 'changed', 'unchanged', 'missing', 'invalid', 'conflict'].map(key => `${key} ${Number(counts[key] || 0)}`).join(', ');
  if (!window.confirm(`Apply this exact shared Navision preview?\n\nDealer: ${pending.dealerCode}\n${totals}\n\nThis writes only to the shared Navision backend. Browser-local authority, workflow, location, Parts and workshop data will not change.`)) return;
  const service = navisionSharedBackendService();
  const idempotencyKey = `normal-upload:${pending.dealerCode}:${data.source_hash || sha256Hex(JSON.stringify(pending.rows))}`.slice(0, 200);
  const applyResult = await service.apply(pending.rows, pending.previewResult, { ...pending.metadata, confirmed: true, idempotencyKey });
  if (!applyResult?.ok) {
    window.alert(`Shared Navision apply failed: ${applyResult?.error || 'service unavailable'}. No localStorage fallback was attempted.`);
    return;
  }
  const afterSha256 = navisionBrowserAuthoritySha256();
  if (afterSha256 !== pending.browserLocalSha256) throw new Error('Shared Navision apply unexpectedly changed browser-local authority.');
  app.pendingSharedNavisionImport = null;
  renderSharedNavisionPreview({ ...pending, applyResult, browserLocalSha256: afterSha256 }, true);
  updateNavisionControlStats({ parsed: pending.parsed, added: [], updated: [], unchanged: pending.parsed.vehicles, stockNumberUpdates: [] });
  updateNavisionImportButton();
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

function navisionRemovalAuditEntry(vehicle, action, details, at, index) {
  return {
    id: `${Date.parse(at) || Date.now()}-nav-${String(index).padStart(4, '0')}-${sha256Hex(vehicleKey(vehicle) || JSON.stringify(vehicle)).slice(0, 8)}`,
    at,
    by: details.by || getCurrentOperatorName(),
    role: details.role || getCurrentOperatorRole(),
    action,
    vehicleKey: vehicleKey(vehicle),
    stock: displayStockNumber(vehicle) || vehicle.stock || '',
    order: vehicle.order || '',
    customer: vehicle.client || vehicle.toyotaCustomer || '',
    vehicle: displayVehicle(vehicle) || '',
    details,
  };
}

function buildNavisionImportCommit(plan, selectedUpdateKeys = null, appliedAt = nowIsoString()) {
  const parsed = plan.parsed;
  let added = loadAddedVehicles().map(vehicle => ({ ...vehicle }));
  const edits = JSON.parse(JSON.stringify(loadVehicleEdits()));
  let deletedRecords = deletedVehicleRecords().map(record => JSON.parse(JSON.stringify(record)));
  const poTasks = JSON.parse(JSON.stringify(loadPoTasks()));
  const poFiles = JSON.parse(JSON.stringify(loadPoFiles()));
  const auditLog = JSON.parse(JSON.stringify(loadAuditLog()));
  const activeBeforeImport = app.data.slice();
  const removeMissingChecked = Boolean(plan.removeMissingChecked);
  const result = { ...plan, added: [], updated: [], unchanged: [], stockNumberUpdates: [], restored: [], missingFromUpload: [], removedMissing: [], confirmed: true, appliedAt };

  parsed.vehicles.forEach(incoming => {
    const deletedRecord = deletedRecordForNavision(deletedRecords, incoming);
    if (deletedRecord && !navisionCanRestoreDeletedRecord(deletedRecord)) return;
    if (deletedRecord) {
      deletedRecords = deletedRecords.filter(record => record !== deletedRecord);
      result.restored.push(incoming);
    }
    const existing = findVehicleForNavision(incoming);
    const keys = navisionMatchKeys(incoming).concat(navisionMatchKeys(existing));
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
      if (addedIndex >= 0) added[addedIndex] = { ...added[addedIndex], ...payload, id: added[addedIndex].id || payload.id };
      const editKeys = new Set(keys.concat([vehicleKey(existing), vehicleKey(incoming)]).filter(Boolean));
      editKeys.forEach(key => { edits[key] = { ...(edits[key] || {}), ...payload }; });
      if (changes.length || stockChanged) result.updated.push(row);
      else result.unchanged.push(row);
    } else {
      added.unshift(incoming);
      result.added.push(incoming);
    }
  });

  const missingFromUpload = vehiclesMissingFromNavisionImport(activeBeforeImport, parsed.vehicles, { fullRefresh: plan.fullRefresh !== false });
  result.missingFromUpload = missingFromUpload;
  let removalKeysChanged = false;
  if (removeMissingChecked && missingFromUpload.length) {
    removalKeysChanged = true;
    const existingRecordsByKey = new Map();
    deletedRecords.forEach(record => {
      [record.key].concat(record.keys || []).filter(Boolean).forEach(key => existingRecordsByKey.set(String(key), record));
    });
    const exactRemovalKeys = new Set();
    const operator = getCurrentOperatorName();
    const role = getCurrentOperatorRole();
    const reason = 'No longer present in the latest full Navision upload';
    missingFromUpload.forEach((vehicle, index) => {
      const exactKeys = [vehicleDeleteKey(vehicle), vehicleKey(vehicle), vehicle.stock, vehicle.batch, vehicle.order, vehicle.id]
        .map(value => String(value || '').trim()).filter(Boolean);
      const vin = normalizeVin(vehicle.vin || vehicle.fullVin || vehicle.frameVin || vehicle.autocareVin || '');
      const allDeleteKeys = [...new Set(exactKeys.concat(vin ? [vin] : []))];
      const key = exactKeys[0] || vin;
      exactKeys.forEach(value => exactRemovalKeys.add(value));
      allDeleteKeys.forEach(value => {
        delete edits[value];
        delete poTasks[value];
        delete poFiles[value];
      });
      if (key && !allDeleteKeys.some(value => existingRecordsByKey.has(value))) {
        const record = {
          key,
          keys: allDeleteKeys,
          deletedAt: appliedAt,
          deletedBy: operator || 'Unknown operator',
          deletedRole: role || 'Unassigned role',
          reason,
          deletionType: 'navision-missing',
          vehicle: JSON.parse(JSON.stringify(vehicle)),
        };
        deletedRecords.unshift(record);
        allDeleteKeys.forEach(value => existingRecordsByKey.set(value, record));
        auditLog.unshift(navisionRemovalAuditEntry(vehicle, 'Retired from Navision back end', {
          by: operator || 'Unknown operator', role: role || 'Unassigned role', reason,
        }, appliedAt, index));
      }
    });
    added = added.filter(vehicle => {
      const keys = [vehicleDeleteKey(vehicle), vehicleKey(vehicle), vehicle.stock, vehicle.batch, vehicle.order, vehicle.id]
        .map(value => String(value || '').trim()).filter(Boolean);
      return !keys.some(key => exactRemovalKeys.has(key));
    });
    result.removedMissing = missingFromUpload.slice();
    result.missingFromUpload = [];
  }

  const workFileRows = parsed.vehicles.filter(vehicle => vehicle.pdcImportMode === 'work-file');
  const healthUpdates = workFileRows.length ? {
    lastWorkImportAt: appliedAt,
    lastWorkImportType: 'Job card / work file',
    lastWorkImportRows: workFileRows.length,
  } : {
    lastNavisionImportAt: appliedAt,
    lastNavisionRows: parsed.vehicles.length,
    lastNavisionAdded: result.added.length,
    lastNavisionUpdated: result.updated.length,
    lastNavisionWarnings: (result.skipped || parsed.warnings || []).length,
  };
  const finalValues = new Map([
    [ADDED_KEY, JSON.stringify(added)],
    [EDITS_KEY, JSON.stringify(edits)],
    [DELETED_KEY, JSON.stringify(deletedRecords)],
    [NAVISION_IMPORT_RESULTS_KEY, JSON.stringify(boundedNavisionImportSummary(result))],
    [OPERATIONAL_HEALTH_KEY, JSON.stringify({ ...loadOperationalHealth(), ...healthUpdates })],
  ]);
  if (removalKeysChanged) {
    finalValues.set(PO_TASKS_KEY, JSON.stringify(poTasks));
    finalValues.set(PO_FILES_KEY, JSON.stringify(poFiles));
    finalValues.set(AUDIT_LOG_KEY, JSON.stringify(auditLog.slice(0, 1500)));
  }
  return { result, finalValues, workFileRows };
}

function projectNavisionImportPeakStorage(plan, selectedUpdateKeys = null) {
  const commit = buildNavisionImportCommit(plan, selectedUpdateKeys);
  const transaction = prepareStorageTransaction('Navision import', [...commit.finalValues.keys()], commit.result.appliedAt);
  const current = currentLocalStorageValues();
  const currentBytes = [...current.entries()].reduce((total, [key, value]) => total + localStorageQuotaBytes(key, value), 0);
  const existingJournal = current.get(STORAGE_TRANSACTION_JOURNAL_KEY);
  const existingJournalBytes = existingJournal === undefined ? 0 : localStorageQuotaBytes(STORAGE_TRANSACTION_JOURNAL_KEY, existingJournal);
  const journalBytes = localStorageQuotaBytes(STORAGE_TRANSACTION_JOURNAL_KEY, transaction.serializedJournal);
  let runningBytes = currentBytes - existingJournalBytes + journalBytes;
  let projectedPeakBytes = Math.max(currentBytes, runningBytes);
  const writeOrder = [...commit.finalValues.entries()].map(([key, value], index) => {
    const previous = current.get(key);
    const oldBytes = previous === undefined ? 0 : localStorageQuotaBytes(key, previous);
    const newBytes = localStorageQuotaBytes(key, value);
    return { key, value, index, deltaBytes: newBytes - oldBytes, oldBytes, newBytes };
  }).sort((a, b) => a.deltaBytes - b.deltaBytes || a.index - b.index);
  writeOrder.forEach(write => {
    runningBytes += write.deltaBytes;
    projectedPeakBytes = Math.max(projectedPeakBytes, runningBytes);
  });
  const summaryValue = commit.finalValues.get(NAVISION_IMPORT_RESULTS_KEY) || '';
  return {
    allowed: projectedPeakBytes <= NAVISION_LOCAL_STORAGE_SAFE_BUDGET_BYTES,
    budgetBytes: NAVISION_LOCAL_STORAGE_SAFE_BUDGET_BYTES,
    projectedPeakBytes,
    currentBytes,
    journalBytes,
    finalBytes: runningBytes - journalBytes,
    summaryBytes: localStorageQuotaBytes(NAVISION_IMPORT_RESULTS_KEY, summaryValue),
    writeOrder,
    commit,
    transaction,
  };
}

function renderNavisionQuotaRejection(projection) {
  const host = $('#navision-status-list');
  if (host) {
    host.innerHTML = `<div class="summary-row error"><strong>${NAVISION_IMPORT_TOO_LARGE_MESSAGE}</strong><span>The projected peak is ${projection.projectedPeakBytes.toLocaleString('en-AU')} bytes, above the ${projection.budgetBytes.toLocaleString('en-AU')}-byte safety limit. The existing local Navision dataset was not changed. Select a different file or export the current dataset.</span></div>`;
  }
  const button = $('#import-navision');
  if (button) button.disabled = true;
}

function finalizeNavisionImportCommit(commit) {
  const { result, workFileRows } = commit;
  app.quickFilter = 'incoming';
  app.pmbSubFilter = '';
  app.columnFilters = { sales: '', production: '', status: '', jita: '' };
  const searchInput = $('#search');
  if (searchInput) searchInput.value = '';
  app.data = buildVehicleData();
  app.selectedRows.clear();
  app.pendingNavisionImport = null;
  app.rejectedNavisionFingerprint = '';
  app.rejectedNavisionProjection = null;
  populateFilters();
  app.navisionImport = result;
  renderOperationalHealthSummary();
  renderAll();
  updateNavisionSidebarMeta();
  renderNavisionSummary(result);
  updateNavisionControlStats(result);
  updateNavisionImportButton();
  const workFileKeys = workFileRows.map(vehicle => vehicleKey(findVehicleForNavision(vehicle) || vehicle));
  if (workFileKeys.length) focusVehiclesAfterWorkImport(workFileKeys);
}

function applyNavisionImportPlan(plan, selectedUpdateKeys = null) {
  const fingerprint = plan?.sourceFingerprint || sha256Hex(JSON.stringify(plan?.parsed?.vehicles || []));
  if (app.rejectedNavisionFingerprint && app.rejectedNavisionFingerprint === fingerprint) {
    renderNavisionQuotaRejection(app.rejectedNavisionProjection || { projectedPeakBytes: 0, budgetBytes: NAVISION_LOCAL_STORAGE_SAFE_BUDGET_BYTES });
    window.alert(NAVISION_IMPORT_TOO_LARGE_MESSAGE);
    return null;
  }
  const projection = projectNavisionImportPeakStorage(plan, selectedUpdateKeys);
  if (!projection.allowed) {
    app.rejectedNavisionFingerprint = fingerprint;
    app.rejectedNavisionProjection = projection;
    app.pendingNavisionImport = plan;
    renderNavisionQuotaRejection(projection);
    window.alert(NAVISION_IMPORT_TOO_LARGE_MESSAGE);
    return null;
  }
  try {
    runStorageTransaction('Navision import', projection.transaction.touchedKeys, () => {
      projection.writeOrder.forEach(write => localStorage.setItem(write.key, write.value));
    }, projection.transaction);
  } catch (error) {
    app.data = buildVehicleData();
    app.pendingNavisionImport = plan;
    renderAll();
    window.alert(error.message || String(error));
    return null;
  }
  finalizeNavisionImportCommit(projection.commit);
  return projection.commit.result;
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
      <div class="summary-stat"><span>Back end to retire</span><strong>${result.missingFromUpload.length}</strong></div>
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
      <h3>Navision-only back-end vehicles not found</h3>
      ${renderNavisionRows(result.missingFromUpload || [], 'navision-missing', 'No eligible back-end vehicle needs retiring.')}
      <div class="subtle">Only unpromoted Navision-only back-end rows are eligible. Manual, PO, PD check-form and PDC Sheet vehicles stay protected when absent from Navision.</div>
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
  const counts = result?.counts || {};
  const parsedVehicleCount = parsed.vehicleCount ?? parsed.vehicles?.length ?? counts.rows ?? 0;
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
    ? `<div class="summary-section"><div class="summary-section-heading"><h3>Navision-only back-end vehicles not found</h3><button class="small-button danger-button" id="navision-remove-missing-now" type="button">Retire from back end</button></div>${renderNavisionRows(missingFromUpload, 'navision-missing', 'Every Navision-only back-end vehicle was found in this upload.')}<div class="subtle">Manual, PO, PD check-form and PDC Sheet vehicles are protected even when they are absent from Navision.</div></div>`
    : `<div class="summary-section"><h3>Navision-only back-end vehicles not found</h3><div class="summary-row"><strong>None</strong><span>No eligible back-end vehicle needs retiring.</span></div></div>`;
  const removedList = removedMissing.length
    ? `<div class="summary-section"><h3>Retired from the Navision back end</h3>${renderNavisionRows(removedMissing, 'navision-removed', 'No Navision-only back-end vehicles were retired during this import.')}</div>`
    : '';

  host.innerHTML = `
    <div class="scot-summary-grid">
      <div class="summary-stat"><span>Rows detected</span><strong>${parsedVehicleCount}</strong></div>
      <div class="summary-stat"><span>Back end added</span><strong>${result?.added?.length ?? counts.added ?? 0}</strong></div>
      <div class="summary-stat"><span>Updated</span><strong>${result?.updated?.length ?? counts.updated ?? 0}</strong></div>
      <div class="summary-stat"><span>New stock #</span><strong>${stockUpdates.length || counts.stockNumberUpdates || 0}</strong></div>
      <div class="summary-stat"><span>Not in upload</span><strong>${missingFromUpload.length || counts.missingFromUpload || 0}</strong></div>
      <div class="summary-stat"><span>Removed</span><strong>${removedMissing.length || counts.removedMissing || 0}</strong></div>
      <div class="summary-stat"><span>Restored</span><strong>${result?.restored?.length ?? counts.restored ?? 0}</strong></div>
      <div class="summary-stat"><span>Warnings</span><strong>${warnings.length}</strong></div>
    </div>
    <div class="summary-section-heading"><h3>Import complete</h3><button class="small-button" id="navision-view-backend" type="button">View Back End Data</button></div>
    <div class="subtle">${app.data.length} active back-end records · ${pdcSheetVehicles().length} vehicles currently visible on the PDC Sheet.</div>
    <div class="summary-section">
      <h3>New vehicles stored in Back End Data</h3>
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
    <div class="subtle">Toyota Status is taken only from Navision Sub Location Description. Normal Navision uploads refresh source data but do not promote new vehicles to the PDC Sheet. Rows marked as Cut But Vehicle are highlighted light blue.</div>
  `;
  on($('#navision-remove-missing-now'), 'click', removeMissingFromLastNavisionImport);
  on($('#navision-view-backend'), 'click', () => showView('backend'));
}

function removeMissingFromLastNavisionImport() {
  const result = app.navisionImport || loadJson(NAVISION_IMPORT_RESULTS_KEY, null);
  const missingCount = Number(result?.missingCount ?? result?.missingFromUpload?.length ?? 0);
  if (!missingCount) return;
  window.alert(`For storage safety, no records were changed. Re-select the same Navision source file, choose the reviewed “Retire missing” option in the import confirmation, and apply it through the exact quota preflight (${missingCount} currently missing).`);
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
  try {
    runStorageTransaction('Dashboard clear', crmManagedStorageKeys(), () => {
      [EDITS_KEY, ADDED_KEY, PO_TASKS_KEY, PO_FILES_KEY, DELETED_KEY, AUTOCARE_RESULTS_KEY, NAVISION_IMPORT_RESULTS_KEY].forEach(key => localStorage.removeItem(key));
      for (let index = localStorage.length - 1; index >= 0; index -= 1) {
        const key = localStorage.key(index);
        if (key && key.startsWith('vehicleTrackingCoreNotes:')) localStorage.removeItem(key);
      }
    });
  } catch (error) {
    app.data = buildVehicleData();
    window.alert(error.message || String(error));
    return;
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

function exportLocalNavisionDataset() {
  const storedValue = localStorage.getItem(ADDED_KEY);
  const sourceValue = storedValue === null ? '[]' : storedValue;
  let records = null;
  try {
    const parsed = JSON.parse(sourceValue);
    if (Array.isArray(parsed)) records = parsed.length;
  } catch {}
  const exportedAt = new Date().toISOString();
  const evidence = {
    sourceKey: ADDED_KEY,
    exportedAt,
    records,
    datasetSha256: sha256Hex(sourceValue),
    exactStoredBytes: storedValue !== null,
  };
  const blob = new Blob([sourceValue], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `pdc-browser-local-navision-${exportedAt.slice(0, 10)}.json`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  return evidence;
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
  updateOperationalHealth({ lastBackupAt: backup.exportedAt });
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

  try {
    runStorageTransaction('CRM backup restore', [...new Set(crmManagedStorageKeys().concat(entries.map(([key]) => key)))], () => {
      const incomingKeys = new Set(entries.map(([key]) => key));
      entries.forEach(([key, value]) => localStorage.setItem(key, value));
      crmManagedStorageKeys().filter(key => !incomingKeys.has(key)).forEach(key => localStorage.removeItem(key));
    });
  } catch (error) {
    renderBackupStatus({ type: 'error', message: error.message || String(error) });
    return;
  }

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
  updateOperationalHealth({ lastRestoreAt: nowIsoString() });
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
  const headers = ['SP','Stock','Toyota Order','Key Number','P/Month','Client','Vehicle','PDC Location','PMB Work Stream','SUBLET Provider','PMB Bay','PMB Bay Hours','PMB Bay Scheduled Start','PMB Bay Started','PMB Bay Completed','PMB Requirements','PMB Completed','PMB Outstanding','Blocked','Blocked Reason','Bucket Days','Days Since Kewdale ETA','Parts Status','Parts ETA','Parts Worst ETA','RFT Gate Issues','RFT Date','Navision Notes','Team Notes','Task', ...jobHeaders, 'PO Tasks','PO Files','Toyota Status (Sub Location)','Navision ETA','Delivery Date','JITA Parts Ordered','JITA Qty','Contact','Source','Autocare VIN','Autocare Batch','Autocare Load','Match Warning'];
  const lines = [headers.join(',')].concat(pdcSheetVehicles().map(v => [
    salesPersonInitials(consultantName(v)), displayStockNumber(v), v.order || '', vehicleKeyNumber(v), productionMonthLabel(v.prodMth || v.productionMonth || ''), v.client, displayVehicle(v), pdcLocationLabel(v.pdcLocation), pmbStageLabel(inferredPmbStage(v)), pmbBaySubletProvider(v), pmbBayNumber(v, inferredPmbStage(v)) || '', pmbBayHours(v) === '' ? '' : pmbBayHours(v), v.pmbBayScheduledStartAt ? new Date(v.pmbBayScheduledStartAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', v.pmbBayEnteredAt ? new Date(v.pmbBayEnteredAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', v.pmbBayCompletedAt ? new Date(v.pmbBayCompletedAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', pmbRequirementText(v), pdcCompletedJobsText(v), pdcOutstandingJobsText(v), isPdcBlocked(v) ? 'Yes' : 'No', pdcBlockReason(v), pmbStageAgeDays(v) === null ? '' : pmbStageAgeDays(v), pmbAgeDays(v) === null ? '' : pmbAgeDays(v), partsDepartmentStatusLabel(partsDepartmentStatus(v)), kewdaleEtaValue(v), partsWorstEtaLabel(v), vehicleRftGateIssues(v).join('; '), v.rftTransferredAt ? new Date(v.rftTransferredAt).toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : '', navisionDealerNoteText(v), teamNotesText(v), v.internalStatus || '', ...PDC_JOB_DEFS.flatMap(def => [pdcJobRequired(v, def) ? 'Yes' : 'No', pdcJobComplete(v, def) ? 'Yes' : 'No']), (v.poTasks || []).join('; '), (v.poFiles || []).join('; '), v.toyotaStatus || '', scotEtaOnly(v.etaAtDealer), v.deliveryDate || '', jitaDisplay(v), v.jitQty || '', v.contact || '', v.source || '', v.autocareVin || '', v.autocareBatch || '', v.autocareLoadNumber || '', isCustomerMatch(v) ? '' : 'Customer mismatch'
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
  const sampleLines = lines.slice(0, 40);
  // Navision's browser copy/export can use U+2002 EN SPACE between cells instead
  // of a real tab. Preserve repeated separators because they represent blank columns.
  const counts = ['\t', '\u2002', ',', ';'].map(delimiter => {
    const perLine = sampleLines.map(line => Array.from(line).filter(character => character === delimiter).length);
    const strongest = perLine.slice().sort((a, b) => b - a).slice(0, 5);
    return [delimiter, strongest.reduce((sum, value) => sum + value, 0)];
  });
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
  const keyNumber = cleanZplField(vehicle.keyNumber || vehicle.batch || 'NO KEY');
  const stock = cleanZplField(vehicle.stock || '—');
  const jobCard = cleanZplField(vehicle.jobCard || '—');
  const customer = cleanZplField(vehicle.customer || '(Dealer Order)');
  const model = cleanZplField(vehicle.model || 'Vehicle not listed');
  const sales = cleanZplField(vehicle.sales || '—');
  const department = cleanZplField(vehicle.department || 'PDC');
  return [
    '^XA', '^PW540', '^LL360', '^LH0,0', '^CI28',
    `^FO18,12^A0N,62,62^FB504,1,0,L,0^FD${keyNumber}^FS`,
    `^FO18,82^A0N,28,28^FB504,1,0,L,0^FDSTOCK ${stock}^FS`,
    `^FO18,116^A0N,25,25^FB504,1,0,L,0^FDJOB CARD ${jobCard}^FS`,
    `^FO18,150^A0N,27,27^FB504,2,2,L,0^FD${customer}^FS`,
    `^FO18,210^A0N,25,25^FB504,2,2,L,0^FD${model}^FS`,
    `^FO18,276^A0N,23,23^FB504,1,0,L,0^FDSALES ${sales}^FS`,
    `^FO18,308^A0N,22,22^FB504,1,0,L,0^FD${department}^FS`,
    '^PQ1', '^XZ'
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
    if (!wmi) missingVinParts.push('WMI');
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
      <div class="summary-stat"><span>Label copies</span><strong>${count}</strong></div>
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

function aiBoardNormalizeStockIdentity(value = '') {
  const raw = String(value || '').trim().toUpperCase();
  const normalized = raw.replace(/[\s-]+/g, '');
  if (!normalized || ['0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED'].includes(normalized)) return '';
  if (/^(NEW|PD|PENDING|TEMP)-/.test(raw)) return '';
  return normalized;
}

function aiBoardSharedModeEnabled() {
  return window.PDC_SUPABASE_CONFIG?.workshop?.sharedData === true;
}

function aiBoardSharedSnapshot() {
  if (!aiBoardSharedModeEnabled()) return null;
  const service = window.__workshopDataService;
  if (!service || typeof service.getTrustedSnapshot !== 'function') return null;
  const snapshot = service.getTrustedSnapshot();
  return snapshot && typeof snapshot === 'object' ? snapshot : null;
}

function aiBoardSharedVehicleIdentity(vehicle = {}, snapshot = null) {
  const rows = snapshot && Array.isArray(snapshot.vehicles) ? snapshot.vehicles : [];
  const legacyKey = vehicleKey(vehicle);
  const stockIdentity = aiBoardNormalizeStockIdentity(legacyKey);
  const sourceIdentity = String(legacyKey || '').trim().toUpperCase();
  const matches = rows.filter(row => (
    (stockIdentity && aiBoardNormalizeStockIdentity(row?.stock_number) === stockIdentity)
    || (sourceIdentity && String(row?.permanent_vehicle_id || '').trim().toUpperCase() === sourceIdentity)
  ));
  const ids = [...new Set(matches.map(row => String(row?.id || '').trim()).filter(Boolean))];
  return ids.length === 1 ? `shared:${ids[0]}` : '';
}

function aiBoardVehicleIdentity(vehicle = {}, snapshot = null) {
  if (aiBoardSharedModeEnabled() && snapshot) return aiBoardSharedVehicleIdentity(vehicle, snapshot);
  const key = String(vehicleKey(vehicle) || '').trim();
  return key ? `legacy:${key}` : '';
}

function aiBoardDateIso(value = '') {
  const direct = parseIsoTimestamp(value);
  if (direct) return direct.toISOString();
  const local = parseDateAU(value);
  return local && !Number.isNaN(local.getTime()) ? local.toISOString() : '';
}

function aiBoardVehicleDtos(snapshot = null) {
  return pdcSheetVehicles().map(vehicle => {
    const required = pdcRequiredJobs(vehicle);
    const completed = pdcCompletedJobs(vehicle);
    const parts = partsJobDef();
    return {
      identity: aiBoardVehicleIdentity(vehicle, snapshot),
      stock: displayStockNumber(vehicle) || vehicleKey(vehicle),
      currentStage: inferredPmbStage(vehicle),
      stageAgeDays: pmbStageAgeDays(vehicle),
      stageAgeLimitDays: pmbLaneAgeLimit(inferredPmbStage(vehicle)),
      deliveryAt: aiBoardDateIso(vehicle.deliveryDate || ''),
      blocked: isPdcBlocked(vehicle),
      blockReason: pdcBlockReason(vehicle),
      requiredStages: required.filter(def => def.key !== 'parts').map(def => pmbStageForPdcJob(def) || def.label),
      completedStages: completed.filter(def => def.key !== 'parts').map(def => pmbStageForPdcJob(def) || def.label),
      parts: {
        required: Boolean(parts && pdcJobRequired(vehicle, parts)),
        complete: Boolean(parts && pdcJobComplete(vehicle, parts)),
        stoppage: Boolean(vehicle.pdcPartsStoppage),
        reason: cleanNavisionText(vehicle.pdcPartsStoppageReason || ''),
        eta: aiBoardDateIso(vehicle.pdcPartsWorstEta || ''),
      },
      jobLines: (Array.isArray(vehicle.pdcManualJobLines) ? vehicle.pdcManualJobLines : []).map(line => ({
        description: cleanNavisionText(line?.description || ''),
        hours: line?.confirmedHours ?? line?.estimatedHours ?? null,
        confirmed: line?.confirmed === true || line?.estimateStatus === 'confirmed',
      })),
    };
  });
}

function aiBoardBookingDtos(snapshot = null) {
  if (aiBoardSharedModeEnabled()) {
    if (!snapshot || snapshot.revision == null || !Array.isArray(snapshot.bookings)) return { bookingCoverage: false, bookingSource: 'shared', bookingRevision: '', bookings: [] };
    return {
      bookingCoverage: true,
      bookingSource: 'shared',
      bookingRevision: String(snapshot.revision),
      bookings: snapshot.bookings.map(booking => {
        const duration = Number(booking?.default_duration_minutes || 0);
        const start = parseIsoTimestamp(booking?.scheduled_start_at || '');
        const calculatedEnd = start && duration > 0 ? new Date(start.getTime() + duration * 60000).toISOString() : '';
        return {
          id: booking?.booking_id || booking?.id || '',
          vehicleIdentity: booking?.vehicle?.id ? `shared:${booking.vehicle.id}` : '',
          stage: booking?.stage?.code || booking?.stage_code || '',
          bay: booking?.bay?.bay_number ?? booking?.bay_number ?? '',
          status: booking?.status === 'queued' ? 'planned' : booking?.status || '',
          startAt: booking?.scheduled_start_at || '',
          endAt: booking?.scheduled_end_at || calculatedEnd,
          stoppageReason: booking?.stoppage_reason || '',
        };
      }),
    };
  }
  const rows = loadJson('vehicleTrackingCoreWorkshopPlan:v1', []);
  return {
    bookingCoverage: true,
    bookingSource: 'local',
    bookingRevision: '',
    bookings: (Array.isArray(rows) ? rows : []).map(booking => {
      const start = parseIsoTimestamp(booking?.startAt || '');
      const hours = Number(booking?.hours || 0);
      return {
        id: booking?.id || '',
        vehicleIdentity: booking?.sharedVehicleId ? `shared:${String(booking.sharedVehicleId).trim()}` : (booking?.vehicleKey ? `legacy:${String(booking.vehicleKey).trim()}` : ''),
        stage: booking?.stage || '',
        bay: booking?.bay || booking?.assignee || '',
        status: booking?.status || '',
        startAt: booking?.startAt || '',
        endAt: start && hours > 0 ? new Date(start.getTime() + hours * 3600000).toISOString() : '',
        stoppageReason: booking?.stoppageReason || '',
      };
    }),
  };
}

function aiBoardAdvisorInput(nowIso = nowIsoString()) {
  const snapshot = aiBoardSharedSnapshot();
  const bookingData = aiBoardBookingDtos(snapshot);
  return {
    nowIso,
    bookingCoverage: bookingData.bookingCoverage,
    bookingSource: bookingData.bookingSource,
    bookingRevision: bookingData.bookingRevision,
    vehicles: aiBoardVehicleDtos(snapshot),
    bookings: bookingData.bookings,
  };
}

function aiBoardSeverityLabel(severity = '') {
  return ({ critical: 'Critical', high: 'High', medium: 'Review', low: 'Low' })[severity] || 'Review';
}

function renderAiBoardAdvisor(nowIso = nowIsoString()) {
  const host = $('#ai-board-advisor-content');
  if (!host) return null;
  const api = window.PdcAiBoardAdvisor;
  if (!api || typeof api.analyze !== 'function') {
    host.innerHTML = '<div class="empty-state"><strong>Advisor unavailable</strong><span>The read-only advisory engine did not load. No operational data was changed.</span></div>';
    return null;
  }
  const result = api.analyze(aiBoardAdvisorInput(nowIso));
  const counts = result.counts || { critical: 0, high: 0, medium: 0, low: 0, total: 0 };
  const coverage = result.bookingCoverage
    ? `<span class="badge ready">Vehicle + ${result.bookingSource === 'shared' ? `booking coverage · revision ${escapeHtml(result.bookingRevision || '')}` : 'local booking coverage'}</span>`
    : '<span class="badge warning">Vehicle coverage only</span>';
  const findings = Array.isArray(result.findings) ? result.findings : [];
  const priorityFindings = findings.filter(item => item.severity === 'critical' || item.severity === 'high');
  const visibleFindings = findings.slice(0, Math.max(50, priorityFindings.length));
  host.innerHTML = `
    <div class="ai-board-summary" role="status" aria-live="polite">
      <div class="summary-stat ai-board-critical"><span>Critical</span><strong>${counts.critical || 0}</strong></div>
      <div class="summary-stat ai-board-high"><span>High</span><strong>${counts.high || 0}</strong></div>
      <div class="summary-stat"><span>Review</span><strong>${counts.medium || 0}</strong></div>
      <div class="summary-stat"><span>Total</span><strong>${counts.total || 0}</strong></div>
    </div>
    <div class="ai-board-coverage">${coverage}<span>Calculated ${escapeHtml(operationalHealthDateLabel(result.generatedAt) || result.generatedAt || 'now')} · deterministic rules ${escapeHtml(result.version || '')}</span></div>
    ${result.bookingCoverage ? '' : '<div class="parts-help-strip"><strong>Coverage limit:</strong><span>No authoritative Workshop booking snapshot is available in this session, so booking conflicts and unscheduled-work checks are omitted rather than guessed.</span></div>'}
    ${findings.length ? `${findings.length > visibleFindings.length ? `<div class="parts-help-strip"><strong>Priority view:</strong><span>Showing the first ${visibleFindings.length} of ${findings.length} deterministically ranked findings. Critical and high risks sort first.</span></div>` : ''}<ol class="ai-board-findings" aria-label="Advisory findings">${visibleFindings.map(item => `
      <li class="ai-board-finding ai-board-${escapeHtml(item.severity)}">
        <div class="ai-board-finding-heading"><span class="badge ${item.severity === 'critical' ? 'danger' : item.severity === 'high' ? 'warning' : 'neutral'}">${escapeHtml(aiBoardSeverityLabel(item.severity))}</span><strong>${escapeHtml(item.title)}</strong><code>${escapeHtml(item.rule)}</code></div>
        <p>${escapeHtml(item.explanation)}</p>
        ${item.stock ? `<div class="ai-board-identity"><b>Stock:</b> ${escapeHtml(item.stock)}</div>` : ''}
        <ul>${(Array.isArray(item.evidence) ? item.evidence : []).map(value => `<li>${escapeHtml(value)}</li>`).join('')}</ul>
        <div class="ai-board-recommendation"><strong>Human review:</strong> ${escapeHtml(item.recommendation)}</div>
      </li>`).join('')}</ol>` : '<div class="empty-state compact-empty"><strong>No deterministic risks detected</strong><span>This is not an approval or guarantee. Continue normal staff checks and refresh when data changes.</span></div>'}
  `;
  return result;
}

function loadAiFileAssistantReviews() {
  const reviews = loadJson(AI_FILE_ASSISTANT_REVIEWS_KEY, []);
  return Array.isArray(reviews) ? reviews.filter(item => item && typeof item === 'object' && cleanNavisionText(item.id || '')) : [];
}

function saveAiFileAssistantReviews(reviews = []) {
  const safeReviews = (Array.isArray(reviews) ? reviews : [])
    .filter(item => item && typeof item === 'object' && cleanNavisionText(item.id || ''))
    .slice(-200);
  saveJson(AI_FILE_ASSISTANT_REVIEWS_KEY, safeReviews);
}

function aiFileAssistantReviewId(prefix = 'ai-review') {
  const random = Math.random().toString(36).slice(2, 8);
  return `${prefix}:${Date.now().toString(36)}:${random}`;
}

function aiAssistantReviewWarnings(review = {}) {
  return Array.isArray(review.analysisWarnings) ? review.analysisWarnings.map(item => cleanNavisionText(item)).filter(Boolean) : [];
}

function aiAssistantReviewSourceFiles(review = {}) {
  return Array.isArray(review.sourceFiles) ? review.sourceFiles.map(item => cleanNavisionText(item)).filter(Boolean) : [];
}

function aiAssistantReviewMetaHtml(review = {}) {
  const warnings = aiAssistantReviewWarnings(review);
  const files = aiAssistantReviewSourceFiles(review);
  const confidence = cleanNavisionText(review.analysisConfidence || '');
  const summary = cleanNavisionText(review.analysisSummary || '');
  const sourceType = cleanNavisionText(review.sourceType || '');
  if (!warnings.length && !files.length && !confidence && !summary && !sourceType) return '';
  return `<div class="email-review-analysis-meta">${[
    summary ? `<span><b>Analysis:</b> ${escapeHtml(summary)}</span>` : '',
    sourceType ? `<span><b>Source:</b> ${escapeHtml(sourceType)}</span>` : '',
    confidence ? `<span><b>Confidence:</b> ${escapeHtml(confidence)}</span>` : '',
    files.length ? `<span><b>Files:</b> ${escapeHtml(files.join(', '))}</span>` : '',
    warnings.length ? `<span><b>Warnings:</b> ${escapeHtml(warnings.join(' · '))}</span>` : ''
  ].filter(Boolean).join('')}</div>`;
}

function aiAssistantTaskJobLines(tasks = []) {
  return [...new Set((Array.isArray(tasks) ? tasks : []).map(task => cleanNavisionText(task)).filter(Boolean))].map(description => {
    const stage = pdcJobLineStage({ description });
    const line = {
      description,
      quantity: 1,
      estimatedHours: null,
      estimateStatus: 'review-required',
      estimateSource: 'Phase 1 file analysis · enter labour hours before pushing to the PDC board',
      suggestedStage: stage,
      category: stage,
      source: 'AI file assistant',
    };
    line.id = pdcJobLineIdentity(line);
    return line;
  });
}

function aiAssistantVehicleImportReview(kind = 'jobcard', parsed = {}, files = [], detectedWarnings = []) {
  const preview = workImportReviewPreviewVehicle(kind, parsed, findVehicleForPurchaseOrder(parsed) || findVehicleForPd(parsed));
  const sourceFiles = (Array.isArray(files) ? files : []).map(item => cleanNavisionText(item)).filter(Boolean);
  const warnings = [...new Set((Array.isArray(detectedWarnings) ? detectedWarnings : []).map(item => cleanNavisionText(item)).filter(Boolean))];
  const id = aiFileAssistantReviewId(kind === 'po' ? 'ai-po' : 'ai-job');
  const receivedAt = nowIsoString();
  const stock = cleanNavisionText(parsed.stock || parsed.reference || preview.stock || preview.batch || '');
  const jobLines = kind === 'po'
    ? (Array.isArray(parsed.lineItems) ? parsed.lineItems.map(pdcJobLineFromPurchaseOrderItem).filter(line => cleanNavisionText(line.description || '')) : [])
    : aiAssistantTaskJobLines(parsed.tasks || []);
  const confidence = kind === 'po'
    ? ((parsed.purchaseOrderNumber && stock && jobLines.length) ? 'high' : 'medium')
    : ((parsed.stock || parsed.order || parsed.vin) && jobLines.length ? 'medium' : 'low');
  return {
    id,
    intakeId: id,
    type: 'vehicle-import',
    source: 'AI file assistant',
    sender: 'Local file upload',
    receivedAt,
    stock,
    vehicle: {
      stock,
      batch: stock,
      order: cleanNavisionText(parsed.order || preview.order || ''),
      vin: normalizeVin(parsed.vin || preview.vin || ''),
      client: cleanNavisionText(parsed.customer || parsed.client || preview.client || ''),
      vehicle: cleanNavisionText(parsed.vehicle || preview.vehicle || ''),
      consultant: cleanNavisionText(parsed.salesperson || preview.consultant || ''),
      jobCardNumber: cleanNavisionText(parsed.jobcard || preview.pdcJobcard || ''),
      colour: cleanNavisionText(parsed.colour || preview.colour || ''),
      trim: cleanNavisionText(parsed.trim || preview.trim || ''),
    },
    jobLines,
    sourceFiles,
    sourceType: kind === 'po' ? 'Purchase order PDF/text' : 'PD check-form / job file',
    analysisSummary: kind === 'po'
      ? `Detected purchase-order work for stock ${stock || 'unknown'}${parsed.purchaseOrderNumber ? ` · ${parsed.purchaseOrderNumber}` : ''}`
      : `Detected ${jobLines.length || 0} work item${jobLines.length === 1 ? '' : 's'} from the uploaded job file`,
    analysisConfidence: confidence,
    analysisWarnings: warnings,
  };
}

function parseAiAssistantPartsUpdate(text = '', sourceFilename = '') {
  const source = String(text || '').replace(/\r/g, '\n');
  const squashed = source.replace(/\s+/g, ' ').trim();
  if (!/\bparts?\b|back\s*order|eta|stoppage|received|issued/i.test(squashed)) return null;
  const stock = (squashed.match(/\bstock\s*(?:no\.?|number|#)?\s*[:#-]?\s*(\d{6,12})\b/i) || squashed.match(/\b(\d{6,12})\b/) || [])[1] || '';
  if (!stock) return null;
  const rawEta = (source.match(/\bETA\s*[:#-]?\s*([^\n]+)/i) || source.match(/\b(\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4})\b/) || [])[1] || '';
  const notes = cleanNavisionText(source.split('\n').map(line => cleanNavisionText(line)).filter(Boolean).slice(0, 3).join(' · ')).slice(0, 280);
  const action = /\breceived\b|\bissued\b|\bcomplete\b/.test(squashed)
    ? 'complete'
    : (/\bstoppage\b|back\s*order|awaiting|\beta\b/.test(squashed) ? 'stoppage' : 'note');
  const warning = action === 'note' ? 'No clear complete/stoppage action was detected; review before applying.' : '';
  return {
    id: aiFileAssistantReviewId('ai-parts'),
    intakeId: aiFileAssistantReviewId('ai-parts-intake'),
    type: 'parts-update',
    source: 'AI file assistant',
    sender: 'Local file upload',
    receivedAt: nowIsoString(),
    stock,
    action,
    eta: cleanNavisionText(rawEta),
    notes,
    reason: action === 'stoppage' ? cleanNavisionText(notes || 'Parts stoppage from uploaded file') : '',
    sourceFiles: [cleanNavisionText(sourceFilename)].filter(Boolean),
    sourceType: 'Parts update text file',
    analysisSummary: `Detected Parts ${action === 'complete' ? 'completion' : action === 'stoppage' ? 'stoppage' : 'note'} for stock ${stock}`,
    analysisConfidence: action === 'note' ? 'low' : 'medium',
    analysisWarnings: warning ? [warning] : [],
  };
}

function analyzeAiAssistantText(text = '', file = {}) {
  const filename = cleanNavisionText(file?.name || 'uploaded file');
  const po = parsePurchaseOrderText(text, filename);
  if ((cleanNavisionText(po.purchaseOrderNumber || '') || cleanNavisionText(po.stock || '')) && Array.isArray(po.lineItems) && po.lineItems.length) {
    const warnings = [];
    if (!cleanNavisionText(po.stock || '')) warnings.push('Purchase order parsed without a stock number. Confirm the vehicle before applying.');
    return { ok: true, review: aiAssistantVehicleImportReview('po', po, [filename], warnings), message: `${filename}: purchase order draft created with ${po.lineItems.length} job line${po.lineItems.length === 1 ? '' : 's'}.` };
  }
  const parts = parseAiAssistantPartsUpdate(text, filename);
  if (parts) {
    return { ok: true, review: parts, message: `${filename}: Parts review draft created for stock ${parts.stock}.` };
  }
  const pd = parsePdCheckFormText(text, [filename]);
  if (cleanNavisionText(pd.stock || pd.order || pd.vin || pd.jobcard || '') || (Array.isArray(pd.tasks) && pd.tasks.length)) {
    const warnings = [];
    if (!pd.tasks?.length) warnings.push('No safe work lines were detected automatically. Add or amend the review lines before applying.');
    return { ok: true, review: aiAssistantVehicleImportReview('jobcard', pd, [filename], warnings), message: `${filename}: job-file draft created with ${(pd.tasks || []).length} detected work item${(pd.tasks || []).length === 1 ? '' : 's'}.` };
  }
  return { ok: false, message: `${filename}: no safe AI review draft could be created from this file yet.` };
}

function setAiFileAssistantStatus(rows = []) {
  const host = $('#ai-intake-status');
  app.aiIntakeStatus = Array.isArray(rows) ? rows : [];
  if (!host) return;
  if (!app.aiIntakeStatus.length) {
    host.innerHTML = '<div class="empty-state compact-empty"><strong>No files queued</strong><span>Add one or more files above to create review drafts.</span></div>';
    return;
  }
  host.innerHTML = `<div class="email-intake-status-list">${app.aiIntakeStatus.map(row => `<div class="summary-row ${row.ok ? 'navision-updated' : 'navision-skipped'}"><strong>${escapeHtml(row.title || 'AI file analysis')}</strong><span>${escapeHtml(row.message || '')}</span></div>`).join('')}</div>`;
}

function updateAiFileAssistantButtons() {
  const files = Array.isArray(app.aiIntakeFiles) ? app.aiIntakeFiles : [];
  const analyze = $('#ai-intake-analyze');
  const clear = $('#ai-intake-clear');
  if (analyze) {
    analyze.disabled = !files.length;
    analyze.textContent = files.length ? `Analyse files (${files.length})` : 'Analyse files';
  }
  if (clear) clear.disabled = !files.length;
}

function handleAiFileAssistantSelect(event) {
  app.aiIntakeFiles = [...(event?.target?.files || [])];
  updateAiFileAssistantButtons();
  setAiFileAssistantStatus(app.aiIntakeFiles.length
    ? [{ ok: true, title: `${app.aiIntakeFiles.length} file${app.aiIntakeFiles.length === 1 ? '' : 's'} ready`, message: app.aiIntakeFiles.map(file => cleanNavisionText(file.name || 'uploaded file')).join(', ') }]
    : []);
}

function clearAiFileAssistantUploads(preserveStatus = false) {
  app.aiIntakeFiles = [];
  const input = $('#ai-intake-upload');
  if (input) input.value = '';
  updateAiFileAssistantButtons();
  if (!preserveStatus) setAiFileAssistantStatus([]);
}

async function analyzeAiFileAssistantUploads() {
  const files = Array.isArray(app.aiIntakeFiles) ? app.aiIntakeFiles : [];
  if (!files.length) {
    setAiFileAssistantStatus([{ ok: false, title: 'No files selected', message: 'Choose one or more PDFs or text files first.' }]);
    return false;
  }
  const analyzeButton = $('#ai-intake-analyze');
  if (analyzeButton) analyzeButton.disabled = true;
  const results = [];
  const createdReviews = [];
  for (const file of files) {
    try {
      const isPdf = /\.pdf$/i.test(file.name || '') || file.type === 'application/pdf';
      const text = isPdf ? await extractTextFromPdfFile(file) : await file.text();
      const result = analyzeAiAssistantText(text, file);
      results.push({ ok: result.ok, title: file.name, message: result.message });
      if (result.ok && result.review) createdReviews.push(result.review);
    } catch (error) {
      results.push({ ok: false, title: file.name || 'uploaded file', message: error.message || String(error) });
    }
  }
  if (createdReviews.length) {
    runStorageTransaction('Save AI file assistant review drafts', [AI_FILE_ASSISTANT_REVIEWS_KEY], () => {
      const existing = loadAiFileAssistantReviews();
      const merged = new Map(existing.map(item => [String(item.id || ''), item]));
      createdReviews.forEach(review => merged.set(String(review.id || ''), review));
      saveAiFileAssistantReviews([...merged.values()]);
    });
    renderEmailIntakeReview();
  }
  setAiFileAssistantStatus(results.length ? results : [{ ok: false, title: 'AI file assistant', message: 'No files were analysed.' }]);
  clearAiFileAssistantUploads(true);
  return createdReviews.length > 0;
}

function emailReviewItems() {
  const seeded = Array.isArray(window.PDC_EMAIL_BOARD_DATA?.reviews) ? window.PDC_EMAIL_BOARD_DATA.reviews : [];
  const local = loadAiFileAssistantReviews();
  const merged = new Map();
  seeded.concat(local).forEach(review => {
    if (!review || typeof review !== 'object') return;
    const id = cleanNavisionText(review.id || '');
    if (!id) return;
    merged.set(id, review);
  });
  return [...merged.values()].sort((a, b) => String(b.receivedAt || '').localeCompare(String(a.receivedAt || '')) || String(a.id || '').localeCompare(String(b.id || '')));
}

function emailReviewDecisions() {
  return loadJson(EMAIL_REVIEW_DECISIONS_KEY, {});
}

function saveEmailReviewDecision(id = '', status = '', details = {}) {
  const decisions = emailReviewDecisions();
  decisions[id] = { status, ...details, decidedAt: nowIsoString(), decidedBy: getCurrentOperatorName() };
  saveJson(EMAIL_REVIEW_DECISIONS_KEY, decisions);
}

function vehicleForEmailReview(review = {}) {
  const stock = cleanNavisionText(review.stock || '').toUpperCase();
  if (!stock) return null;
  const matches = app.data.filter(vehicle => [vehicleKey(vehicle), displayStockNumber(vehicle), vehicle.order, vehicle.batch]
    .map(value => cleanNavisionText(value).toUpperCase()).includes(stock));
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) console.warn('Email review vehicle lookup was ambiguous; no vehicle was selected.', { stock, matchCount: matches.length });
  return null;
}

function emailReviewActionLabel(review = {}) {
  if (review.type === 'vehicle-import') return 'Review vehicle, labour and workshop categories';
  return review.action === 'complete' ? 'Mark Parts complete' : review.action === 'stoppage' ? 'Record Parts stoppage' : 'Add Parts note';
}

function emailReviewApplyUpdates(vehicle = {}, review = {}) {
  const operator = getCurrentOperatorName();
  const now = nowIsoString();
  const notes = cleanNavisionText(review.notes || '');
  const reason = cleanNavisionText(review.reason || notes || 'Parts stoppage received by email');
  const existingNotes = Array.isArray(vehicle.pdcPartsEmailNotes) ? vehicle.pdcPartsEmailNotes : [];
  const updates = {
    pdcRequiresParts: true,
    pdcPartsEmailNotes: notes ? [...existingNotes, { note: notes, at: now, by: operator, intakeId: review.intakeId || '' }].slice(-20) : existingNotes,
    pdcLastEmailReviewId: review.id || '',
    pdcLastEmailReviewAt: now,
    pdcLastEmailReviewBy: operator,
  };
  const def = partsJobDef();
  if (review.action === 'complete') {
    Object.assign(updates, {
      pdcPartsOrdered: true,
      pdcPartsOrderedAt: vehicle.pdcPartsOrderedAt || now,
      pdcPartsStoppage: false,
      pdcPartsStoppageReason: '',
      pdcPartsWorstEta: '',
    });
    if (def) {
      updates[def.completeKey] = true;
      updates[def.completeAtKey] = now;
      updates[def.completeByKey] = operator;
    }
  } else if (review.action === 'stoppage') {
    Object.assign(updates, {
      pdcPartsStoppage: true,
      pdcPartsStoppageReason: reason,
      pdcPartsStoppageAt: now,
      pdcPartsStoppageBy: operator,
      pdcPartsWorstEta: cleanNavisionText(review.eta || vehicle.pdcPartsWorstEta || ''),
    });
    if (def) updates[def.completeKey] = false;
  }
  return updates;
}

function emailVehicleReviewDetailValues(reviewId = '') {
  const row = $$('[data-email-vehicle-review]').find(item => item.dataset.emailVehicleReview === reviewId);
  if (!row) return {};
  return {
    client: cleanNavisionText($('[data-email-vehicle-customer]', row)?.value || ''),
    vehicle: cleanNavisionText($('[data-email-vehicle-description]', row)?.value || ''),
    jobCardNumber: cleanNavisionText($('[data-email-vehicle-job-card]', row)?.value || ''),
  };
}

function emailVehicleReviewLineValues(reviewId = '') {
  const row = $$('[data-email-vehicle-review]').find(item => item.dataset.emailVehicleReview === reviewId);
  if (!row) return [];
  return $$('[data-email-review-line]', row).map(lineRow => ({
    id: lineRow.dataset.emailReviewLine || '',
    included: Boolean($('[data-email-line-include]', lineRow)?.checked),
    description: $('[data-email-line-description]', lineRow)?.value || '',
    hours: $('[data-email-line-hours]', lineRow)?.value || '',
    category: $('[data-email-line-stage]', lineRow)?.value || '',
  }));
}

function reviewedEmailJobLines(review = {}, values = [], operator = getCurrentOperatorName()) {
  const valueMap = new Map((Array.isArray(values) ? values : []).map(value => [String(value.id || ''), value]));
  const now = nowIsoString();
  return (Array.isArray(review.jobLines) ? review.jobLines : []).map(sourceLine => {
    const id = pdcJobLineIdentity(sourceLine);
    const value = valueMap.get(id) || { id, included: true, description: sourceLine.description, hours: sourceLine.estimatedHours, category: pdcJobLineStage(sourceLine) };
    if (!value.included) return null;
    const description = cleanNavisionText(value.description || sourceLine.description || '');
    const hours = validPdcJobLineHours(value.hours);
    const category = normalizePmbStage(value.category || pdcJobLineStage(sourceLine));
    if (!description) throw new Error('Every included job line needs a description.');
    if (hours == null) throw new Error(`Enter valid labour hours for “${description}” before pushing to the PDC board.`);
    if (!PDC_JOB_LINE_STAGE_OPTIONS.some(option => option.value === category)) throw new Error(`Choose a workshop category for “${description}”.`);
    return {
      ...sourceLine,
      id,
      description,
      category,
      confirmed: true,
      confirmedHours: hours,
      estimatedHours: Number(sourceLine.estimatedHours ?? hours),
      estimateStatus: 'confirmed',
      confirmedAt: now,
      confirmedBy: operator,
      source: 'AI Intake Review',
    };
  }).filter(Boolean);
}

function reviewedEmailVehicleUpdates(vehicle = {}, review = {}, lines = [], operator = getCurrentOperatorName(), details = {}) {
  const mergedLines = mergePdcJobLines(vehicle.pdcManualJobLines || [], lines);
  const updates = {
    ...Object.fromEntries(Object.entries(details || {}).filter(([, value]) => cleanNavisionText(value || ''))),
    pdcManualJobLines: mergedLines,
    pdcLastEmailReviewId: review.id || '',
    pdcLastEmailReviewAt: nowIsoString(),
    pdcLastEmailReviewBy: operator,
  };
  lines.forEach(line => {
    const def = pmbStageJobDef(line.category);
    if (def?.requireKey) updates[def.requireKey] = true;
  });
  return updates;
}

function applyVehicleImportReview(review = {}) {
  const operator = getCurrentOperatorName();
  if (!operator || operator === 'Unknown operator') {
    window.alert('Set an operator name before approving an email import. Nothing was changed.');
    return false;
  }
  let lines;
  try {
    lines = reviewedEmailJobLines(review, emailVehicleReviewLineValues(review.id), operator);
  } catch (error) {
    window.alert(error.message || String(error));
    return false;
  }
  if (!lines.length) {
    window.alert('Select at least one valid work line before pushing this vehicle to the PDC board.');
    return false;
  }
  const existing = vehicleForEmailReview(review);
  const details = emailVehicleReviewDetailValues(review.id);
  const baseVehicle = existing || { ...(review.vehicle || {}), ...details, stock: review.stock || review.vehicle?.stock || '' };
  const updates = reviewedEmailVehicleUpdates(baseVehicle, review, lines, operator, details);
  const key = vehicleKey(baseVehicle) || cleanNavisionText(review.stock || '');
  if (!key) {
    window.alert('This proposal has no safe stock/job-card identity and cannot be pushed.');
    return false;
  }
  try {
    runStorageTransaction('Approve email vehicle import', [ADDED_KEY, EDITS_KEY, AUDIT_LOG_KEY, EMAIL_REVIEW_DECISIONS_KEY], () => {
      if (existing) {
        const edits = loadVehicleEdits();
        edits[key] = { ...(edits[key] || {}), ...updates };
        saveJson(EDITS_KEY, edits);
      } else {
        const added = loadAddedVehicles();
        const nextVehicle = { ...baseVehicle, ...updates, id: baseVehicle.id || `reviewed-email-${key}`, stock: baseVehicle.stock || key };
        const nextAdded = [...added.filter(item => vehicleKey(item) !== key), nextVehicle];
        saveAddedVehicles(nextAdded);
      }
      recordVehicleAudit(baseVehicle, 'Email vehicle import approved and pushed to PDC board', {
        intakeId: review.intakeId || '',
        jobLineCount: lines.length,
        categories: [...new Set(lines.map(line => line.category))],
        by: operator,
      });
      saveEmailReviewDecision(review.id, 'applied', { stock: review.stock, action: 'vehicle-import', jobLineCount: lines.length });
    });
  } catch (error) {
    window.alert(error.message || String(error));
    return false;
  }
  app.data = buildVehicleData();
  populateFilters();
  renderAll();
  renderEmailIntakeReview();
  return true;
}

function applyEmailReview(id = '') {
  const review = emailReviewItems().find(item => String(item.id || '') === String(id || ''));
  if (!review) return;
  if (review.type === 'vehicle-import') return applyVehicleImportReview(review);
  const vehicle = vehicleForEmailReview(review);
  if (!vehicle) {
    window.alert(`No vehicle matching stock ${review.stock || 'unknown'} was found. Keep this proposal pending until the vehicle exists.`);
    return;
  }
  const updates = emailReviewApplyUpdates(vehicle, review);
  const operator = getCurrentOperatorName();
  const vehicleSnapshot = { ...vehicle };
  try {
    runStorageTransaction('Apply reviewed Parts email', [EDITS_KEY, AUDIT_LOG_KEY, EMAIL_REVIEW_DECISIONS_KEY], () => {
      if (!saveVehicleEdits(vehicleKey(vehicle), updates, { render: false })) throw new Error('The vehicle update failed.');
      recordVehicleAudit(vehicle, 'Reviewed Parts email applied', { action: review.action, reason: review.reason || '', notes: review.notes || '', eta: review.eta || '', intakeId: review.intakeId || '', by: operator });
      saveEmailReviewDecision(review.id, 'applied', { stock: review.stock, action: review.action });
    });
  } catch (error) {
    Object.keys(vehicle).forEach(key => { if (!Object.prototype.hasOwnProperty.call(vehicleSnapshot, key)) delete vehicle[key]; });
    Object.assign(vehicle, vehicleSnapshot);
    window.alert(error.message || String(error));
    return false;
  }
  renderAll();
  const freshVehicle = selectedVehicle(vehicleKey(vehicle)) || vehicle;
  offerSalespersonChangeEmail(freshVehicle, {
    title: review.action === 'complete' ? 'Parts completed from reviewed email' : review.action === 'stoppage' ? 'Parts stoppage from reviewed email' : 'Parts note received',
    subject: 'PDC Parts email update',
    details: [review.reason && `Reason: ${review.reason}`, review.notes && `Notes: ${review.notes}`, review.eta && `Parts ETA: ${review.eta}`].filter(Boolean),
  });
  renderEmailIntakeReview();
  return true;
}

function rejectEmailReview(id = '') {
  const review = emailReviewItems().find(item => String(item.id || '') === String(id || ''));
  if (!review || !window.confirm(`Reject this proposed update for ${review.stock}?`)) return false;
  const vehicle = vehicleForEmailReview(review);
  try {
    runStorageTransaction('Reject reviewed email update', [AUDIT_LOG_KEY, EMAIL_REVIEW_DECISIONS_KEY], () => {
      saveEmailReviewDecision(review.id, 'rejected', { stock: review.stock, action: review.action });
      if (vehicle) recordVehicleAudit(vehicle, 'Reviewed Parts email rejected', { action: review.action, intakeId: review.intakeId || '', by: getCurrentOperatorName() });
    });
  } catch (error) {
    window.alert(error.message || String(error));
    return false;
  }
  renderEmailIntakeReview();
  return true;
}

function emailVehicleReviewLinesHtml(review = {}, disabled = false) {
  const lines = Array.isArray(review.jobLines) ? review.jobLines : [];
  if (!lines.length) return '<div class="empty-state compact-empty"><strong>No safe job lines were extracted</strong><span>Reject this proposal or add the vehicle manually.</span></div>';
  return `<div class="email-vehicle-review-lines">${lines.map(line => {
    const id = pdcJobLineIdentity(line);
    const stage = pdcJobLineStage(line);
    const hours = line.estimatedHours == null ? '' : line.estimatedHours;
    const source = cleanNavisionText(line.estimateSource || 'Starting estimate requires staff confirmation');
    return `<div class="email-vehicle-review-line" data-email-review-line="${escapeHtml(id)}">
      <label class="email-line-include"><input type="checkbox" data-email-line-include checked ${disabled ? 'disabled' : ''}> Include</label>
      <label class="email-line-description"><span>Job line</span><input type="text" data-email-line-description value="${escapeHtml(line.description || '')}" ${disabled ? 'disabled' : ''}><small>${line.code ? `${escapeHtml(line.code)} · ` : ''}${escapeHtml(source)}</small></label>
      <label><span>Category</span><select data-email-line-stage ${disabled ? 'disabled' : ''}>${pdcJobLineStageOptionsHtml(stage)}</select></label>
      <label><span>Labour hours</span><input type="number" min="0.08" max="40" step="0.25" data-email-line-hours value="${escapeHtml(String(hours))}" placeholder="Enter" ${disabled ? 'disabled' : ''}></label>
    </div>`;
  }).join('')}</div>`;
}

function renderEmailIntakeReview() {
  const host = $('#email-intake-review-content');
  if (!host) return;
  renderAiBoardAdvisor();
  updateAiFileAssistantButtons();
  const decisions = emailReviewDecisions();
  const filter = $('#email-review-status-filter')?.value || 'pending';
  const all = emailReviewItems();
  const rows = all.filter(review => {
    const state = decisions[review.id]?.status || 'pending';
    return filter === 'all' || state === filter;
  });
  const pending = all.filter(review => !decisions[review.id]?.status).length;
  const countHost = $('#email-review-count');
  if (countHost) countHost.textContent = `${pending} pending · ${all.length} total`;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No review proposals match this filter</strong><span>Email and uploaded-file proposals appear here for approval before any PDC-board changes are made.</span></div>';
    return;
  }
  host.innerHTML = `<div class="email-review-list">${rows.map(review => {
    const decision = decisions[review.id] || {};
    const vehicle = vehicleForEmailReview(review);
    const state = decision.status || 'pending';
    if (review.type === 'vehicle-import') {
      const proposalVehicle = vehicle || review.vehicle || {};
      const lineCount = Array.isArray(review.jobLines) ? review.jobLines.length : 0;
      const customer = vehicleCustomerName(proposalVehicle) || 'Customer not supplied';
      const vehicleDescription = displayVehicle(proposalVehicle) || proposalVehicle.vehicle || 'Vehicle details not supplied';
      const jobCard = vehicleJobcardNumber(proposalVehicle) || proposalVehicle.jobCardNumber || 'Not supplied';
      const confidence = cleanNavisionText(review.analysisConfidence || '').toUpperCase() || 'REVIEW';
      const metaHtml = aiAssistantReviewMetaHtml(review);
      return `<details class="email-review-row email-vehicle-review email-review-${escapeHtml(state)}" data-email-vehicle-review="${escapeHtml(review.id)}">
        <summary class="email-review-summary">
          <span class="email-review-summary-identity"><span class="badge ${state === 'pending' ? 'warning' : state === 'applied' ? 'ready' : 'neutral'}">${escapeHtml(state.toUpperCase())}</span><strong>Stock ${escapeHtml(review.stock || 'Not found')}</strong></span>
          <span class="email-review-summary-cell"><small>Customer</small><b title="${escapeHtml(customer)}">${escapeHtml(customer)}</b></span>
          <span class="email-review-summary-cell"><small>Vehicle</small><b title="${escapeHtml(vehicleDescription)}">${escapeHtml(vehicleDescription)}</b></span>
          <span class="email-review-summary-cell"><small>Job card</small><b>${escapeHtml(jobCard)}</b></span>
          <span class="email-review-summary-meta"><b>${lineCount} job ${lineCount === 1 ? 'line' : 'lines'}</b><small>${escapeHtml(review.receivedAt ? operationalHealthDateLabel(review.receivedAt) : 'Date unavailable')}</small></span>
          <span class="email-review-summary-meta"><b>${escapeHtml(confidence)}</b><small>Confidence</small></span>
          <span class="email-review-open-label" aria-hidden="true"></span>
        </summary>
        <div class="email-review-expanded">
          <div class="email-review-expanded-heading"><b>${escapeHtml(emailReviewActionLabel(review))}</b><small>Review and approve this vehicle only when you are ready.</small></div>
          ${metaHtml}
          <div class="email-review-vehicle-fields"><label><span>Customer</span><input type="text" data-email-vehicle-customer value="${escapeHtml(vehicleCustomerName(proposalVehicle) || '')}" ${state !== 'pending' ? 'disabled' : ''}></label><label><span>Vehicle details</span><input type="text" data-email-vehicle-description value="${escapeHtml(displayVehicle(proposalVehicle) || proposalVehicle.vehicle || '')}" ${state !== 'pending' ? 'disabled' : ''}></label><label><span>Job card</span><input type="text" data-email-vehicle-job-card value="${escapeHtml(vehicleJobcardNumber(proposalVehicle) || proposalVehicle.jobCardNumber || '')}" ${state !== 'pending' ? 'disabled' : ''}></label></div>
          <div class="email-review-guidance"><strong>Check every included row.</strong> Correct the description, move it to the workshop category that will perform it, and confirm labour hours. Only approved rows are pushed to the PDC board and Workshop Planner.</div>
          ${emailVehicleReviewLinesHtml(review, state !== 'pending')}
          <div class="email-review-actions">${state === 'pending' ? `<button class="primary" type="button" data-email-review-apply="${escapeHtml(review.id)}" ${lineCount ? '' : 'disabled'}>Approve &amp; push to PDC board</button><button class="small-button" type="button" data-email-review-reject="${escapeHtml(review.id)}">Reject</button>` : `<span class="subtle">${escapeHtml(decision.decidedBy || '')} · ${escapeHtml(decision.decidedAt ? operationalHealthDateLabel(decision.decidedAt) : '')}</span>`}</div>
        </div>
      </details>`;
    }
    return `<article class="email-review-row email-review-${escapeHtml(state)}">
      <div class="email-review-main"><span class="badge ${state === 'pending' ? 'warning' : state === 'applied' ? 'ready' : 'neutral'}">${escapeHtml(state.toUpperCase())}</span><strong>${escapeHtml(review.stock || 'No stock')}</strong><b>${escapeHtml(emailReviewActionLabel(review))}</b><small>${escapeHtml(review.receivedAt ? operationalHealthDateLabel(review.receivedAt) : 'Date unavailable')}</small></div>
      <div class="email-review-details"><span><b>Vehicle:</b> ${escapeHtml(vehicle ? `${vehicleCustomerName(vehicle)} · ${displayVehicle(vehicle)}` : 'No matching vehicle')}</span>${review.reason ? `<span><b>Reason:</b> ${escapeHtml(review.reason)}</span>` : ''}${review.notes ? `<span><b>Notes:</b> ${escapeHtml(review.notes)}</span>` : ''}${review.eta ? `<span><b>ETA:</b> ${escapeHtml(review.eta)}</span>` : ''}<span><b>Sender:</b> ${escapeHtml(review.sender || 'Unknown')}</span></div>
      ${aiAssistantReviewMetaHtml(review)}
      <div class="email-review-actions">${state === 'pending' ? `<button class="primary" type="button" data-email-review-apply="${escapeHtml(review.id)}" ${vehicle ? '' : 'disabled'}>Apply reviewed update</button><button class="small-button" type="button" data-email-review-reject="${escapeHtml(review.id)}">Reject</button>` : `<span class="subtle">${escapeHtml(decision.decidedBy || '')} · ${escapeHtml(decision.decidedAt ? operationalHealthDateLabel(decision.decidedAt) : '')}</span>`}</div>
    </article>`;
  }).join('')}</div>`;
  $$('[data-email-vehicle-review]', host).forEach(row => row.addEventListener('toggle', () => {
    if (!row.open) return;
    $$('[data-email-vehicle-review]', host).forEach(other => {
      if (other !== row) other.removeAttribute('open');
    });
  }));
  $$('[data-email-review-apply]', host).forEach(button => button.addEventListener('click', () => applyEmailReview(button.dataset.emailReviewApply)));
  $$('[data-email-review-reject]', host).forEach(button => button.addEventListener('click', () => rejectEmailReview(button.dataset.emailReviewReject)));
}

function plainDateValue(value = '') {
  const match = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function subletRows() {
  return pdcSheetVehicles().filter(vehicle => inferredPmbStage(vehicle) === 'SUBLET' || Boolean(pmbBaySubletProvider(vehicle) || vehicle.pmbSubletBookingDate || vehicle.pmbSubletExpectedReturnDate || vehicle.pmbSubletActualReturnDate));
}

function subletIsOverdue(vehicle = {}) {
  const expected = plainDateValue(vehicle.pmbSubletExpectedReturnDate || '');
  if (!expected || plainDateValue(vehicle.pmbSubletActualReturnDate || '')) return false;
  const today = new Date();
  const localToday = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  return expected < localToday;
}

function updateSubletField(key = '', field = '', value = '') {
  const allowed = new Set(['pmbSubletProvider', 'pmbSubletProviderEmail', 'pmbSubletPoSentDate', 'pmbSubletBookingDate', 'pmbSubletExpectedReturnDate', 'pmbSubletActualReturnDate', 'pmbSubletNotes']);
  if (!allowed.has(field)) return;
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const cleanValue = cleanNavisionText(value || '');
  recordVehicleAudit(vehicle, 'Sublet booking updated', { field, value: cleanValue, by: getCurrentOperatorName() });
  saveVehicleEdits(key, { [field]: cleanValue, pmbSubletUpdatedAt: nowIsoString(), pmbSubletUpdatedBy: getCurrentOperatorName() });
}

function setSubletEmailSent(key = '', sent = false) {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  recordVehicleAudit(vehicle, sent ? 'Sublet email marked sent' : 'Sublet email marked not sent', { by: getCurrentOperatorName() });
  saveVehicleEdits(key, { pmbSubletEmailSent: Boolean(sent), pmbSubletEmailSentAt: sent ? nowIsoString() : '', pmbSubletEmailSentBy: sent ? getCurrentOperatorName() : '' });
}

function draftSubletProviderEmail(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  const recipient = cleanNavisionText(vehicle.pmbSubletProviderEmail || '');
  const stock = displayStockNumber(vehicle) || vehicle.order || 'TBA';
  const subject = `Sublet booking - ${stock}`;
  const body = [`Hello ${pmbBaySubletProvider(vehicle) || 'Sublet provider'},`, '', 'Please confirm the following booking:', '', ...vehicleEmailLines(vehicle), `Job Card: ${vehicleJobcardNumber(vehicle) || 'TBA'}`, `Booking date: ${plainDateValue(vehicle.pmbSubletBookingDate) || 'TBA'}`, `Expected return: ${plainDateValue(vehicle.pmbSubletExpectedReturnDate) || 'TBA'}`, `Notes: ${cleanNavisionText(vehicle.pmbSubletNotes || 'None')}`, '', 'Kind Regards,'].join('\n');
  recordVehicleAudit(vehicle, 'Sublet provider email drafted', { provider: pmbBaySubletProvider(vehicle), recipient, by: getCurrentOperatorName() });
  saveVehicleEdits(key, { pmbSubletEmailDraftedAt: nowIsoString(), pmbSubletEmailDraftedBy: getCurrentOperatorName() });
  window.location.href = `mailto:${encodeURIComponent(recipient)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function draftSubletSalesUpdate(key = '') {
  const vehicle = selectedVehicle(key);
  if (!vehicle) return;
  draftSalespersonChangeEmail(vehicle, {
    title: subletIsOverdue(vehicle) ? 'Sublet return overdue' : 'Sublet booking update',
    subject: 'PDC Sublet update',
    details: [`Provider: ${pmbBaySubletProvider(vehicle) || 'Unassigned'}`, `Booking: ${plainDateValue(vehicle.pmbSubletBookingDate) || 'TBA'}`, `Expected return: ${plainDateValue(vehicle.pmbSubletExpectedReturnDate) || 'TBA'}`, vehicle.pmbSubletNotes && `Notes: ${vehicle.pmbSubletNotes}`].filter(Boolean),
  });
}

function renderSubletHome() {
  const host = $('#sublet-home-content');
  if (!host) return;
  const search = cleanNavisionText($('#sublet-search')?.value || '').toLowerCase();
  const filter = $('#sublet-status-filter')?.value || 'active';
  const rows = subletRows().filter(vehicle => {
    const returned = Boolean(plainDateValue(vehicle.pmbSubletActualReturnDate || ''));
    if (filter === 'active' && returned) return false;
    if (filter === 'overdue' && !subletIsOverdue(vehicle)) return false;
    if (filter === 'returned' && !returned) return false;
    if (!search) return true;
    return [displayStockNumber(vehicle), vehicleCustomerName(vehicle), displayVehicle(vehicle), pmbBaySubletProvider(vehicle), vehicle.pmbSubletNotes].join(' ').toLowerCase().includes(search);
  }).sort((a, b) => String(a.pmbSubletExpectedReturnDate || '9999').localeCompare(String(b.pmbSubletExpectedReturnDate || '9999')));
  const overdue = subletRows().filter(subletIsOverdue).length;
  const count = $('#sublet-summary');
  if (count) count.textContent = `${rows.length} shown · ${overdue} overdue`;
  if (!rows.length) {
    host.innerHTML = '<div class="empty-state"><strong>No Sublet vehicles match this filter</strong><span>Move a PMB vehicle into SUBLET to create its provider booking record.</span></div>';
    return;
  }
  host.innerHTML = `<div class="sublet-table-wrap"><table class="data-table compact-table sublet-table"><thead><tr><th>Vehicle</th><th>Provider</th><th>PO sent</th><th>Booking</th><th>Expected return</th><th>Actual return</th><th>Notes / email</th><th>Actions</th></tr></thead><tbody>${rows.map(vehicle => {
    const key = vehicleKey(vehicle);
    const stock = displayStockNumber(vehicle) || vehicle.order || 'vehicle';
    const accessibleStock = escapeHtml(stock);
    const overdueClass = subletIsOverdue(vehicle) ? ' sublet-overdue' : '';
    return `<tr class="sublet-row${overdueClass}"><td><strong>${escapeHtml(stock === 'vehicle' ? '—' : stock)}</strong><span>${escapeHtml(vehicleCustomerName(vehicle) || 'Dealer Order')}</span><small>${escapeHtml(displayVehicle(vehicle) || '')}</small></td><td><select aria-label="Sublet provider for ${accessibleStock}" data-sublet-field="pmbSubletProvider" data-sublet-key="${escapeHtml(key)}">${subletProviderOptionsHtml(pmbBaySubletProvider(vehicle))}</select><input type="email" aria-label="Sublet provider email for ${accessibleStock}" placeholder="Provider email" value="${escapeHtml(vehicle.pmbSubletProviderEmail || '')}" data-sublet-field="pmbSubletProviderEmail" data-sublet-key="${escapeHtml(key)}"></td><td><input type="date" aria-label="PO sent date for ${accessibleStock}" value="${escapeHtml(plainDateValue(vehicle.pmbSubletPoSentDate))}" data-sublet-field="pmbSubletPoSentDate" data-sublet-key="${escapeHtml(key)}"></td><td><input type="date" aria-label="Sublet booking date for ${accessibleStock}" value="${escapeHtml(plainDateValue(vehicle.pmbSubletBookingDate))}" data-sublet-field="pmbSubletBookingDate" data-sublet-key="${escapeHtml(key)}"></td><td><input type="date" aria-label="Expected sublet return for ${accessibleStock}" value="${escapeHtml(plainDateValue(vehicle.pmbSubletExpectedReturnDate))}" data-sublet-field="pmbSubletExpectedReturnDate" data-sublet-key="${escapeHtml(key)}">${subletIsOverdue(vehicle) ? '<b class="sublet-overdue-label">OVERDUE</b>' : ''}</td><td><input type="date" aria-label="Actual sublet return for ${accessibleStock}" value="${escapeHtml(plainDateValue(vehicle.pmbSubletActualReturnDate))}" data-sublet-field="pmbSubletActualReturnDate" data-sublet-key="${escapeHtml(key)}"></td><td><textarea rows="2" aria-label="Sublet notes for ${accessibleStock}" data-sublet-field="pmbSubletNotes" data-sublet-key="${escapeHtml(key)}">${escapeHtml(vehicle.pmbSubletNotes || '')}</textarea><label class="sublet-email-check"><input type="checkbox" data-sublet-email-sent="${escapeHtml(key)}" ${vehicle.pmbSubletEmailSent ? 'checked' : ''}> Email sent</label></td><td><button class="small-button" type="button" data-sublet-provider-email="${escapeHtml(key)}">Draft provider email</button><button class="small-button" type="button" data-sublet-sales-email="${escapeHtml(key)}">Draft sales update</button></td></tr>`;
  }).join('')}</tbody></table></div>`;
  $$('[data-sublet-field]', host).forEach(input => input.addEventListener('change', () => updateSubletField(input.dataset.subletKey, input.dataset.subletField, input.value)));
  $$('[data-sublet-email-sent]', host).forEach(input => input.addEventListener('change', () => setSubletEmailSent(input.dataset.subletEmailSent, input.checked)));
  $$('[data-sublet-provider-email]', host).forEach(button => button.addEventListener('click', () => draftSubletProviderEmail(button.dataset.subletProviderEmail)));
  $$('[data-sublet-sales-email]', host).forEach(button => button.addEventListener('click', () => draftSubletSalesUpdate(button.dataset.subletSalesEmail)));
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
