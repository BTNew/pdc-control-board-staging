'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const html = fs.readFileSync(path.join(root, 'staging.html'), 'utf8').replace(/\r\n/g, '\n');
const css = fs.readFileSync(path.join(root, 'ai-auditor.css'), 'utf8').replace(/\r\n/g, '\n');

const auditorStart = html.indexOf('<section id="ai-auditor"');
const auditorEnd = html.indexOf('<section id="sublet"', auditorStart);
const auditor = html.slice(auditorStart, auditorEnd);
const intakeStart = html.indexOf('<section id="emailreview"');
const intakeEnd = html.indexOf('<section id="ai-auditor"', intakeStart);
const intake = html.slice(intakeStart, intakeEnd);

assert.ok(auditor.includes('id="ai-intake-upload"'), 'Auditor must expose the document file input');
assert.ok(auditor.includes('id="ai-auditor-document-drop-zone"') && auditor.includes('role="button"') && auditor.includes('tabindex="0"'), 'drop zone must be keyboard focusable');
assert.ok(auditor.includes('Upload job cards or Sublet information'));
assert.ok(auditor.includes('id="ai-auditor-upload-proposals"'));
assert.ok(auditor.includes('Uploaded evidence never changes Workshop data automatically.'));
assert.ok(!intake.includes('id="ai-intake-upload"'), 'staging must not duplicate the document input in AI Intake');
assert.ok(css.includes('.ai-auditor-upload-proposal'));
assert.ok(css.includes('.ai-auditor-upload-proposal-heading'));
assert.ok(app.includes("app.pdcAuditorSnapshot?.reviewCanDecide !== true"), 'upload analysis must fail closed outside existing Operator/Administrator review authority');
assert.ok(/function handleAiFileAssistantSelect[\s\S]{0,450}reviewCanDecide !== true[\s\S]{0,250}app\.aiIntakeFiles = \[\]/.test(app), 'direct file selection must fail closed and retain no file handles without review authority');
assert.ok(/function clearAiFileAssistantUploads[\s\S]{0,180}aiIntakeAnalysisGeneration \+= 1[\s\S]{0,300}app\.pdcAuditorDocumentProposals = \[\]/.test(app), 'clear/auth reset must invalidate in-flight analysis and purge proposal state');
assert.ok(/function analyzeAiFileAssistantUploads[\s\S]{0,1200}analysisIsCurrent[\s\S]{0,1600}if \(!analysisIsCurrent\(\)\) return false/.test(app), 'async analysis must revalidate generation and authority after awaited extraction/hash work');
assert.ok(/function clearAiFileAssistantUploads[\s\S]{0,400}app\.pdcAuditorDocumentProposals = \[\][\s\S]{0,300}renderPdcAuditorDocumentProposals\(\)/.test(app), 'uploaded evidence must be cleared from memory and DOM on clear/auth reset');
assert.ok(!/data-ai-auditor-apply|applyPdcAuditorDocument/.test(auditor), 'upload UI must not expose an apply/mutation control');

const start = app.indexOf('function pdcAuditorSuggestedStage');
const end = app.indexOf('function loadAiFileAssistantReviews', start);
assert.ok(start >= 0 && end > start, 'document proposal parser block missing');
const block = app.slice(start, end);
assert.ok(block.includes('No automatic changes:'));
assert.ok(block.includes('openAuthenticatedOperationWorkshop'));
const workshopOpenStart = app.indexOf('function openAuthenticatedOperationWorkshop');
const workshopOpenEnd = app.indexOf('\nfunction ', workshopOpenStart + 10);
const workshopOpenBlock = app.slice(workshopOpenStart, workshopOpenEnd);
assert.ok(workshopOpenBlock.indexOf("showView('dashboard')") >= 0 && workshopOpenBlock.indexOf("showView('dashboard')") < workshopOpenBlock.indexOf('vehicleWorkshopCanEditLines()'), 'Auditor review action must leave the read-only view before evaluating Workshop edit authority');
assert.ok(workshopOpenBlock.includes('vehicleWorkshopRoleCanEditLines()'), 'Auditor review action must require an exact Operator/Administrator role before navigation');
assert.ok(app.includes("crypto.subtle.digest('SHA-256'"), 'uploaded proposals must bind to a SHA-256 digest of the selected file bytes');
assert.ok(app.includes("'keydown', handleAiFileAssistantDropZoneKeydown"), 'drop zone must support keyboard file selection');
assert.ok(!block.includes('upsert_vehicle_workshop_line_adjustment'), 'upload parser must not call the adjustment RPC');
assert.ok(!block.includes('saveVehicleEdits('), 'upload parser must not mutate vehicles');

const buttonContext = vm.createContext({
  app: {
    aiIntakeFiles: [],
    pdcAuditorDocumentProposals: [{ id: 'review-only-proposal' }],
    pdcAuditorSnapshot: { reviewCanDecide: true },
  },
  controls: {
    '#ai-intake-analyze': { disabled: false, textContent: '' },
    '#ai-intake-clear': { disabled: true },
    '#ai-auditor-upload-proposals': {},
  },
  $: selector => buttonContext.controls[selector] || null,
});
const buttonsStart = app.indexOf('function updateAiFileAssistantButtons');
const buttonsEnd = app.indexOf('async function aiFileAssistantSourceEvidence', buttonsStart);
assert.ok(buttonsStart >= 0 && buttonsEnd > buttonsStart, 'document upload button-state helper missing');
vm.runInContext(app.slice(buttonsStart, buttonsEnd), buttonContext);
vm.runInContext('updateAiFileAssistantButtons()', buttonContext);
assert.strictEqual(buttonContext.controls['#ai-intake-clear'].disabled, false, 'Clear files must remain enabled while a rendered review-only proposal needs purging');
buttonContext.app.pdcAuditorDocumentProposals = [];
vm.runInContext('updateAiFileAssistantButtons()', buttonContext);
assert.strictEqual(buttonContext.controls['#ai-intake-clear'].disabled, true, 'Clear files may disable only when neither selected files nor proposals remain');

const context = vm.createContext({
  cleanNavisionText: value => String(value == null ? '' : value).replace(/\s+/g, ' ').trim(),
  pdcJobLineStage: line => /wire|elect/i.test(line.description) ? 'ELECTRICAL' : /tint/i.test(line.description) ? 'TINT' : 'FITTING',
  aiFileAssistantReviewId: prefix => `${prefix}:fixed`,
  nowIsoString: () => '2026-08-10T12:00:00.000Z',
  app: { pdcAuditorDocumentProposals: [] },
  escapeHtml: value => String(value),
  pmbStageLabel: value => value,
  openAuthenticatedOperationWorkshop: () => false,
  setAiFileAssistantStatus: () => {},
  $: () => null,
  $$: () => [],
});
vm.runInContext(block, context);
const helperStart = app.indexOf('function aiFileAssistantAcceptedFiles');
const helperEnd = app.indexOf('function clearAiFileAssistantUploads', helperStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'bounded drop/upload helper block missing');
vm.runInContext(app.slice(helperStart, helperEnd), context);
const accepted = vm.runInContext("aiFileAssistantAcceptedFiles([{name:'ok.pdf',size:1024,type:'application/pdf'},{name:'bad.exe',size:1,type:'application/octet-stream'},{name:'huge.txt',size:11*1024*1024,type:'text/plain'}])", context);
assert.deepStrictEqual(JSON.parse(JSON.stringify(accepted)).map(file => file.name), ['ok.pdf']);
assert.ok(app.includes("on($('#ai-auditor-document-drop-zone'), 'drop', handleAiFileAssistantDrop)"), 'drop zone must have a real drop handler');
const proposal = vm.runInContext(`pdcAuditorUploadedDocumentProposal(
  'JOB CARD J139125431\\nStock No: 13045140\\nOP10 Install bullbar 2.50 hrs\\nOP20 Wire driving lights Hours: 1.25\\nOP30 Window tint 0.00 h\\nTotal 3.75',
  { name: 'JC-J139125431.pdf' }
)`, context);
const plain = JSON.parse(JSON.stringify(proposal));
assert.strictEqual(plain.documentType, 'Job card');
assert.strictEqual(plain.stock, '13045140');
assert.strictEqual(plain.jobCard, 'J139125431');
assert.deepStrictEqual(plain.lines.map(line => [line.stage, line.estimatedHours]), [
  ['FITTING', 2.5],
  ['ELECTRICAL', 1.25],
  ['TINT', 0],
]);
assert.strictEqual(plain.warnings.length, 0);
const noCode = vm.runInContext("pdcAuditorUploadedOperationLines('Install towbar 1.00 hrs')", context);
assert.strictEqual(JSON.parse(JSON.stringify(noCode))[0].description, 'Install towbar', 'plain descriptions must not lose their first word');
const falseHours = vm.runInContext("pdcAuditorUploadedOperationLines('OP10 Install bullbar Qty 2\\nOP20 Torque setting 120')", context);
assert.strictEqual(falseHours.length, 0, 'unlabelled quantities and settings must never bind as labour hours');
const duplicates = vm.runInContext("pdcAuditorUploadedOperationLines('OP10 Fit bracket 1.00 hrs\\nOP20 Fit bracket 1.00 hrs')", context);
assert.deepStrictEqual(JSON.parse(JSON.stringify(duplicates)).map(line => line.sourceLine), [1, 2], 'identical source rows must preserve source-line cardinality');
const crlfRows = vm.runInContext("pdcAuditorUploadedOperationLines('OP10 Fit bracket 1.00 hrs\\r\\nOP20 Wire lamp 0.50 hrs')", context);
assert.deepStrictEqual(JSON.parse(JSON.stringify(crlfRows)).map(line => line.sourceLine), [1, 2], 'Windows CRLF rows must preserve physical source-line coordinates');
const unknownStage = vm.runInContext("pdcAuditorUploadedOperationLines('OP10 Calibrate bespoke module 1.00 hrs')", context);
assert.strictEqual(unknownStage[0].stage, '', 'unknown operations must remain unbound instead of defaulting to Fitting');
const exactPhysicalStages = vm.runInContext("pdcAuditorUploadedOperationLines('OP10 Bus 4x4 conversion 2.00 hrs\\nOP20 Pit inspection 1.00 hrs')", context);
assert.deepStrictEqual(JSON.parse(JSON.stringify(exactPhysicalStages)).map(line => line.stage), ['BUS_4X4', 'PIT_INSPECTION'], 'safe physical-station matches must use exact canonical work keys');
assert.ok(app.includes("line.stage ? pmbStageLabel(line.stage) : 'Review required'"), 'unbound stations must render as Review required, never as Unallocated');
const bound = vm.runInContext("pdcAuditorUploadedDocumentProposal('Stock: 13045140\\nOP10 Fit bracket 1.00 hrs',{name:'job.txt',type:'text/plain'},{sha256:'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',byteLength:42,mediaType:'text/plain',lastModified:1})", context);
assert.strictEqual(bound.id, 'auditor-upload:' + 'a'.repeat(64));
assert.strictEqual(bound.sourceEvidence.byteLength, 42);

const sublet = vm.runInContext(`pdcAuditorUploadedDocumentProposal(
  'SUBLET PROVIDER: Tint Co\\nStock: 13045140\\nExpected return 12/08/2026\\nOP1 Window tint 2.00 hrs',
  { name: 'sublet-note.txt' }
)`, context);
assert.strictEqual(sublet.documentType, 'Sublet information');
assert.strictEqual(sublet.lines.length, 1);

const unbound = vm.runInContext("pdcAuditorUploadedDocumentProposal('notes only', { name: 'unknown.txt' })", context);
assert.strictEqual(unbound.lines.length, 0);
assert.strictEqual(unbound.warnings.length, 2);

async function verifyAsyncClearAndAuthorityRace() {
  let resolveText;
  const input = { value: 'selected', files: [] };
  const raceContext = vm.createContext({
    app: {
      aiIntakeFiles: [],
      aiIntakeAnalysisGeneration: 0,
      pdcAuditorDocumentProposals: [],
      pdcAuditorSnapshot: { reviewCanDecide: true },
    },
    cleanNavisionText: value => String(value == null ? '' : value).replace(/\s+/g, ' ').trim(),
    aiFileAssistantAcceptedFiles: files => [...files],
    updateAiFileAssistantButtons: () => {},
    setAiFileAssistantStatus: () => {},
    renderPdcAuditorDocumentProposals: () => {},
    extractTextFromPdfFile: async () => '',
    aiFileAssistantSourceEvidence: async () => ({ sha256: 'a'.repeat(64), byteLength: 1 }),
    pdcAuditorUploadedDocumentProposal: () => ({ lines: [{ description: 'Fit bracket', estimatedHours: 1 }], sourceEvidence: {} }),
    analyzeAiAssistantText: () => ({ ok: false }),
    runStorageTransaction: () => {},
    loadAiFileAssistantReviews: () => [],
    saveAiFileAssistantReviews: () => {},
    renderEmailIntakeReview: () => {},
    AI_FILE_ASSISTANT_REVIEWS_KEY: 'reviews',
    $: selector => selector === '#ai-intake-upload'
      ? input
      : selector === '#ai-intake-analyze'
        ? { disabled: false }
        : selector === '#ai-auditor-upload-proposals'
          ? {}
          : null,
  });
  const raceStart = app.indexOf('function handleAiFileAssistantSelect');
  const raceEnd = app.indexOf('function serverAiIntakeAuthMarker', raceStart);
  vm.runInContext(app.slice(raceStart, raceEnd), raceContext);

  raceContext.app.pdcAuditorSnapshot = { reviewCanDecide: false };
  raceContext.unauthorisedTarget = { files: [{ name: 'private.txt' }], value: 'private.txt' };
  const acceptedWithoutAuthority = vm.runInContext('handleAiFileAssistantSelect({ target: unauthorisedTarget })', raceContext);
  assert.strictEqual(acceptedWithoutAuthority, false);
  assert.strictEqual(raceContext.app.aiIntakeFiles.length, 0, 'unauthorised direct selection must retain no file handles');
  assert.strictEqual(raceContext.unauthorisedTarget.value, '', 'unauthorised direct selection must clear the native input');

  raceContext.app.pdcAuditorSnapshot = { reviewCanDecide: true };
  raceContext.delayedFile = {
    name: 'job.txt',
    type: 'text/plain',
    text: () => new Promise(resolve => { resolveText = resolve; }),
  };
  raceContext.app.aiIntakeFiles = [raceContext.delayedFile];
  const pending = vm.runInContext('analyzeAiFileAssistantUploads()', raceContext);
  await Promise.resolve();
  vm.runInContext('clearAiFileAssistantUploads()', raceContext);
  resolveText('Stock: 13045140\\nOP10 Fit bracket 1.00 hrs');
  const result = await pending;
  assert.strictEqual(result, false, 'cleared in-flight analysis must abort');
  assert.strictEqual(raceContext.app.pdcAuditorDocumentProposals.length, 0, 'cleared in-flight analysis must not repopulate proposals');
}

verifyAsyncClearAndAuthorityRace()
  .then(() => console.log('AI Auditor document upload passed: job card/Sublet extraction, exact hours including 0.00, authority/race controls, review-only UI and no mutation path'))
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
