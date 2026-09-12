'use strict';

const assert = require('assert');
const fs = require('fs');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const app = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const mapped = mapServerVehicle({
  id: '11111111-1111-4111-8111-111111111111',
  work_items: [{ work_key: 'fitting', required: true, completed: false, completed_at: null, completed_by: null }],
  operation_lines: [{
    operation_line_id: '22222222-2222-4222-8222-222222222222',
    operation_no: 'PD007-ABCDEF12',
    work_key: 'review',
    job_card_number: 'RO-7',
    description: 'Review custom fitment',
    estimated_hours: 1.5,
    estimated_hours_source: 'business_rule_default',
    source_estimated_hours: 0,
    effective_estimated_hours: 1.5,
    hours_provenance: 'pre_delivery_default_1_5',
    parts_on_backorder_raw: 'Yes',
    parts_semantics: 'explicitly_backordered',
    classification: 'Review',
    source_uid: 'pilbara_service_open_jobcards_v1:13000001:RO-7:7',
  }, {
    operation_line_id: '44444444-4444-4444-8444-444444444444',
    operation_no: 'PD008-1234ABCD',
    work_key: 'fitting',
    job_card_number: 'RO-7',
    description: 'Pre-Delivery',
    estimated_hours: 1.5,
    estimated_hours_source: 'job_card',
    source_estimated_hours: 1.5,
    effective_estimated_hours: 1.5,
    hours_provenance: 'source_explicit',
    parts_on_backorder_raw: 'No',
    parts_semantics: 'not_backordered',
    classification: 'FITTING',
    classification_method: 'deterministic_rule',
    classification_confidence: 1,
    classification_rationale: 'Craig pre-delivery rule.',
    source_uid: 'pilbara_service_open_jobcards_v1:13000001:RO-7:8',
  }],
});

assert.strictEqual(mapped.pilbaraServiceOperations.length, 2);
assert.strictEqual(mapped.jobCardNumber, 'RO-7');
assert.strictEqual(mapped.jobcard, 'RO-7');
assert.strictEqual(mapped.pilbaraServiceJobCard, true);
assert.strictEqual(mapped.pilbaraServiceOperations[0].classification, 'Review');
assert.strictEqual(mapped.pilbaraServiceOperations[0].sourceEstimatedHours, 0);
assert.strictEqual(mapped.pilbaraServiceOperations[0].effectiveEstimatedHours, 1.5);
assert.strictEqual(mapped.pilbaraServiceOperations[0].hoursProvenance, 'pre_delivery_default_1_5');
assert.strictEqual(mapped.pilbaraServiceOperations[0].partsSemantics, 'explicitly_backordered');
assert.strictEqual(mapped.pilbaraServiceOperations[1].work_key, 'fitting');
assert.strictEqual(mapped.pilbaraServiceOperations[1].classification, 'FITTING');
assert.strictEqual(mapped.pilbaraServiceOperations[1].classificationMethod, 'deterministic_rule');
assert.strictEqual(mapped.pilbaraServiceOperations[1].classificationConfidence, 1);
assert.strictEqual(mapped.pdcRequiresFitting, true);
assert.strictEqual(mapped.pdcCompleteFitting, false);
const legacyMapped = mapServerVehicle({
  operation_lines: [{ operation_line_id: '33333333-3333-4333-8333-333333333333', operation_no: 'OP1', work_key: 'fitting', description: 'Legacy line' }],
});
assert.strictEqual(legacyMapped.pdcEmailOperationLines[0].partsSemantics, null);
assert.match(app, /Source hours/);
assert.match(app, /Business-rule default/);
assert.match(app, /Pilbara Service Review · R\/O loaded/);
assert.doesNotMatch(app, /pdc-station-review/, 'Service operation count must not add an eleventh top-row category control');
assert.doesNotMatch(app, /const operationJobCard = operation\.job_card_number/, 'rendering must not expose the repeated repair-order subline');
assert.strictEqual(mapped.pilbaraServiceOperations[0].job_card_number, 'RO-7', 'repair-order identity remains in the internal projection');
assert.match(styles, /\.authenticated-email-operations li > small\s*\{[^}]*grid-column:\s*1\s*\/\s*-1/s);
console.log('Pilbara Service Review operation projection: PASS');
