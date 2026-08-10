'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');

assert(app.includes('data-auth-operation-work'), 'email operation cards must expose the Move jobs entry point');
assert(app.includes("openVehicleModal(button.dataset.authOperationWork);\n    selectVehicleDetailPage('work');"), 'Move jobs must open the modal before selecting the authoritative Workshop page');
assert(!app.includes("if (openVehicleModal(button.dataset.authOperationWork))"), 'Move jobs must not depend on the void modal opener returning true');
assert(app.includes('data-vehicle-workshop-line-stage'), 'editable Workshop lines must expose a station selector');
assert(app.includes('moveVehicleWorkshopLineStage(select)'), 'station selector must use the audited line-adjustment save path');
assert(app.includes('sourceWorkshopStage: group.stage'), 'source station must remain available as immutable provenance');
assert(app.includes('relocatedLines.push({ targetStage, line: adjustedLine })'), 'effective station overlays must relocate lines');
assert(app.includes('relocatedLines.forEach(({ targetStage, line }) => groups.get(targetStage).lines.push(line))'), 'relocated lines must enter the target station group');
assert(app.includes("groups.filter(group => group.requirements.some(item => item?.required === true && item?.completed !== true)).map(group => group.stage)"), 'station choices must be limited to outstanding canonical work');
assert(app.includes('const totalHours = lineHours.length ? lineHours.reduce((sum, value) => sum + value, 0)'), 'station chip hours must sum effective line estimates');
assert(app.includes('vehicleWorkshopCompactLinesHtml(group, bookingFallback, vehicle, validStages)'), 'station choices must be passed to every effective line row');
assert(app.includes("station.operations.map(operation => {"), 'source station headings must sum their displayed operation estimates');
assert(app.includes("const totalHoursLabel = totalHours === null ? 'Unknown hours' : `${totalHours.toFixed(2)} h`"), 'source station headings must display the exact estimated-line sum');
assert(css.includes('.vehicle-workshop-line-station select'), 'station selector must have compact responsive styling');
assert(css.includes('.authenticated-email-operations-heading'), 'Move jobs entry point must have responsive styling');

console.log('vehicle workshop operation routing and hour chips verified');
