const assert = require('assert');
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const start = source.indexOf('function renderWorkshopPlanner(options = {})');
const end = source.indexOf('\nfunction bindWorkshopPlanner', start);
assert.ok(start >= 0 && end > start, 'planner render implementation exists');
const render = source.slice(start, end);
assert.match(render, /const pendingStage = normalizePmbStage\(app\.pendingWorkshopStage \|\| ''\)/);
assert.match(render, /const stageChanged = state\.stage !== requestedStage/);
assert.match(render, /if \(stageChanged \|\| pendingStage\) workshopClearSelectedDetail\(state\)/);
assert.doesNotMatch(render, /state\.stage = requestedStage;\s*workshopClearSelectedDetail\(state\)/, 'ordinary dedicated re-render must not erase the selected booking');
const select = source.slice(source.indexOf("root.querySelectorAll('[data-workshop-select-plan]')"), source.indexOf("root.querySelectorAll('[data-workshop-open-plan]')"));
assert.match(select, /workshopSelectPlanForDetail\(button\.dataset\.workshopSelectPlan\);\s*renderWorkshopPlanner\(\)/, 'visible booking button must select then render detail');
console.log('Workshop dedicated booking detail selection contract passed.');
