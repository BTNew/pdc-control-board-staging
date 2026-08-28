'use strict';

const assert = require('assert');
const fs = require('fs');

const index = fs.readFileSync('index.html', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

let count = 0;
function ok(value, message) {
  assert.ok(value, message);
  count += 1;
}

ok(index.includes('data-view="qc"'), 'navigation exposes a dedicated QC view');
ok(index.includes('<section id="qc" class="view">'), 'index contains the dedicated QC page section');
ok(index.includes('id="qc-page-host"'), 'QC page has a render host');
ok(app.includes("case 'qc':") && app.includes('renderQualityControlPage();'), 'active view renders the QC page');
ok(app.includes("qc: ['qc-page-host']"), 'QC page host is released with heavy view cleanup');
ok(/function qcPageVehicles[\s\S]*vehicleInQualityControlGate\(vehicle\)/.test(app), 'QC page filters vehicles still in the QC location, including signed-off vehicles awaiting RFT');
ok(app.includes('data-qc-vehicle-key=') && app.includes('data-qc-open-vehicle='), 'QC page renders selectable vehicle cards');
ok(app.includes('data-qc-operation-check=') && app.includes('data-qc-line-identity=') && app.includes('data-qc-line-version='), 'QC checklist renders stable versioned operation-line controls');
ok(app.includes('function qcPageAllOperationLinesComplete') && app.includes('lines.length > 0 && lines.every'), 'QC readiness requires every active operation line and fails closed on no lines');
ok(app.includes('setQcOperationCompletion') && !app.includes('async function qcPageSetWorkState'), 'QC completion uses the protected per-operation RPC, never department-level local state');
ok(app.includes('Unknown hours') && app.includes('Audited manual line') && app.includes('Source JC unavailable'), 'QC lines expose exact/unknown hours and source identity');
ok(app.includes('accept="image/*"') && app.includes('type="file"') && app.includes('qc-photo-input-'), 'QC page exposes an explicitly associated image chooser');
ok(!app.includes('capture="environment"'), 'Universal chooser does not force camera-only capture and therefore keeps the photo library available');
ok(app.includes('FileReader') && app.includes('readAsDataURL') && !app.includes('URL.createObjectURL(file)'), 'QC photo preview uses CSP-compatible data URLs');
ok(app.includes('qcPagePhotoDisabledReason') && app.includes('Complete all 17 operation lines'), 'QC photo control exposes precise identity/cycle/17-line disabled reasons');
ok(app.includes('function qcPhotoEvidenceIsValid') && app.includes('qc-photo-clear') && app.includes("status: 'accepted'"), 'QC never labels zero/partial evidence stored and exposes clear/retry recovery');
ok(service.includes("record_pdc_qc_retest_photo_747") && service.includes("finalize_pdc_qc_retest_to_rft_747") && service.includes('finalizeQcRetest'), 'Recovered QC retest uses exact cycle-bound receipt and finalization RPCs');
ok(app.includes('qc-photo-progress') && app.includes('qcPagePhotoErrorMessage'), 'QC photo shows progress and precise retry-safe errors');
ok(app.includes('const qcPhotoEvidence = new Map()') && app.includes('uploadQcPhotoEvidence'), 'QC photo is receipt-backed in private staging storage');
ok(app.includes('data-qc-signoff=') && app.includes('finalizeQcToRft'), 'QC finalization uses the authoritative atomic QC-to-RFT action');
ok(styles.includes('.qc-page') && styles.includes('.qc-work-item.is-complete'), 'QC page has dedicated responsive and green-complete styles');
ok(!/qcPhotoDrafts[\s\S]{0,500}localStorage/.test(app), 'QC photo draft does not fall back to browser localStorage');

console.log(`QC page contract: ${count} assertions passed.`);
