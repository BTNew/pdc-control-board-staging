'use strict';
const assert=require('assert'),fs=require('fs');const app=fs.readFileSync('app.js','utf8');
for(const marker of ['function authenticatedOperationSummaryLines','detail.line_adjustments','adjustmentByKey.get(lineKey)','stage === vehicleWorkshopStageCode(adjustment.stage_code)','estimatedHours: Number.isFinite','data-auth-operation-summary','function loadAuthenticatedOperationSummary','get_vehicle_workshop_detail','bindAuthenticatedOperationSummaries(host)','refreshOpenAuthenticatedOperationSummaries'])assert.ok(app.includes(marker),`missing ${marker}`);
assert.ok(app.includes("if (adjustment?.active === false) return [];"),'removed source lines must stay absent');
assert.ok(app.includes("if (row.open) void loadAuthenticatedOperationSummary(row);"),'expanded rows must load authoritative adjustments');
assert.ok(app.includes("refreshOpenAuthenticatedOperationSummaries($('#incoming-main-board') || document);"),'closing editor must refresh visible counts');
console.log('authenticated_operation_summary_adjustments: PASS');
