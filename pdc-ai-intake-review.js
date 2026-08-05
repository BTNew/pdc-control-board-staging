'use strict';

const AI_INTAKE_PREVIEW_EVENTS = Object.freeze({
  BOARD_ACTIVATE: 'Control Board activation',
  WPC_COMPLETE: 'WPC completion',
  PARTS_COMPLETE: 'Parts completion',
});

function cleanAiIntakePreviewText(value, max = 160) {
  const text = String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
  return text.length <= max ? text : '';
}

function buildAiIntakeReviewSummary(item = {}) {
  const text = cleanAiIntakePreviewText(item.summary, 2000);
  if (text) return { available: true, approvalReady: true, text, warning: '' };
  const reviewOnly = item.action_type === 'review_only';
  return {
    available: false,
    approvalReady: false,
    text: 'No email summary is available for this review.',
    warning: reviewOnly
      ? 'Review the source email before dismissing this information-only item.'
      : 'Do not approve this proposal until the source email has a readable summary.',
  };
}

function normalizeAiIntakeDecision(decision = '') {
  return String(decision || '').trim().toLowerCase();
}

function aiIntakePreviewSource(item = {}) {
  if (item.proposed_change && typeof item.proposed_change === 'object' && !Array.isArray(item.proposed_change)) return item.proposed_change;
  if (item.proposed_change_preview && typeof item.proposed_change_preview === 'object' && !Array.isArray(item.proposed_change_preview)) return item.proposed_change_preview;
  return null;
}

function buildAiIntakeDetectedChangePreview(item = {}) {
  if (item.action_type === 'board_activate_only' && !aiIntakePreviewSource(item)) {
    return {
      available: true,
      valid: true,
      approvalSupported: true,
      eventType: 'BOARD_ACTIVATE',
      eventLabel: AI_INTAKE_PREVIEW_EVENTS.BOARD_ACTIVATE,
      validationState: 'validated',
      targetLabel: cleanAiIntakePreviewText(item.stock_number, 40) ? `Stock ${cleanAiIntakePreviewText(item.stock_number, 40)}` : 'Validated Navision vehicle',
      changes: [{ screen: 'Control Board', field: 'Board status', before: 'Not active', after: 'Active', visualEffect: 'Vehicle appears on the Control Board' }],
      approvalEffect: 'Apply exactly the displayed Control Board activation after the server re-checks identity and revisions.',
      rejectionEffect: 'Record the rejection. No vehicle, location, work, Parts or Control Board status changes.',
    };
  }

  const source = aiIntakePreviewSource(item);
  if (!source) {
    return {
      available: false,
      valid: item.action_type === 'review_only',
      approvalSupported: false,
      eventType: '',
      eventLabel: 'No operational change proposed',
      validationState: item.action_type === 'review_only' ? 'review_only' : 'blocked',
      targetLabel: cleanAiIntakePreviewText(item.stock_number, 40) ? `Stock ${cleanAiIntakePreviewText(item.stock_number, 40)}` : 'No uniquely matched vehicle',
      changes: [],
      approvalEffect: '',
      rejectionEffect: item.action_type === 'review_only'
        ? 'Dismiss the information-only evidence. No operational status changes.'
        : 'Reject or leave pending. No operational status changes.',
    };
  }

  const eventType = cleanAiIntakePreviewText(source.event_type || source.eventType, 40).toUpperCase();
  const validationState = cleanAiIntakePreviewText(source.validation_state || source.validationState, 32).toLowerCase();
  const rawChanges = Array.isArray(source.changes) ? source.changes : [];
  const allowedEvent = Object.prototype.hasOwnProperty.call(AI_INTAKE_PREVIEW_EVENTS, eventType);
  const allowedValidation = ['validated', 'blocked', 'review_only'].includes(validationState);
  const changes = rawChanges.slice(0, 32).map(change => ({
    screen: cleanAiIntakePreviewText(change?.screen || change?.affected_screen, 80),
    field: cleanAiIntakePreviewText(change?.field || change?.field_label, 100),
    before: cleanAiIntakePreviewText(change?.before ?? change?.current_value, 120),
    after: cleanAiIntakePreviewText(change?.after ?? change?.proposed_value, 120),
    visualEffect: cleanAiIntakePreviewText(change?.visual_effect, 160),
  })).filter(change => change.screen && change.field && change.before && change.after && change.before !== change.after);
  const valid = source.contract_version === 1
    && allowedEvent
    && allowedValidation
    && (validationState !== 'validated' || changes.length > 0)
    && rawChanges.length === changes.length
    && rawChanges.length <= 32;
  const requiredAction = {
    BOARD_ACTIVATE: 'board_activate_only',
    WPC_COMPLETE: 'wpc_complete',
    PARTS_COMPLETE: 'parts_complete',
  }[eventType];
  const actionMatches = item.action_type === requiredAction;
  const approvalSupported = valid && actionMatches && validationState === 'validated' && source.approval_supported === true;
  return {
    available: true,
    valid,
    approvalSupported,
    eventType,
    eventLabel: AI_INTAKE_PREVIEW_EVENTS[eventType] || 'Unsupported detected event',
    validationState: valid ? validationState : 'blocked',
    targetLabel: cleanAiIntakePreviewText(source.target_label || source.targetLabel, 120)
      || (cleanAiIntakePreviewText(item.stock_number, 40) ? `Stock ${cleanAiIntakePreviewText(item.stock_number, 40)}` : 'No uniquely matched vehicle'),
    changes: valid ? changes : [],
    approvalEffect: approvalSupported
      ? cleanAiIntakePreviewText(source.approval_effect, 500) || 'Apply exactly the displayed changes after server revalidation.'
      : 'Approval is blocked. The detected event has not passed the operational validation contract.',
    rejectionEffect: cleanAiIntakePreviewText(source.rejection_effect, 500)
      || 'Record the rejection. No operational status changes.',
  };
}

function appendDecisionEffect(documentRef, host, label, text, className = '') {
  const block = documentRef.createElement('div');
  const heading = documentRef.createElement('span');
  const detail = documentRef.createElement('strong');
  if (className) block.className = className;
  heading.textContent = label;
  detail.textContent = text;
  block.append(heading, detail);
  host.append(block);
}

function renderAiIntakeDetectedChangePreview(documentRef, host, preview) {
  if (!host) return;
  host.replaceChildren();
  const heading = documentRef.createElement('span');
  heading.textContent = 'Detected changes';
  host.append(heading);

  const summary = documentRef.createElement('div');
  summary.className = `ai-intake-change-preview-summary is-${preview.validationState}`;
  const title = documentRef.createElement('strong');
  title.textContent = preview.eventLabel;
  const target = documentRef.createElement('small');
  target.textContent = preview.targetLabel;
  summary.append(title, target);
  host.append(summary);

  if (preview.changes.length) {
    const table = documentRef.createElement('div');
    table.className = 'ai-intake-change-preview-table';
    preview.changes.forEach(change => {
      const row = documentRef.createElement('div');
      row.className = 'ai-intake-change-preview-row';
      const label = documentRef.createElement('div');
      const screen = documentRef.createElement('small');
      const field = documentRef.createElement('strong');
      const values = documentRef.createElement('div');
      const before = documentRef.createElement('span');
      const arrow = documentRef.createElement('b');
      const after = documentRef.createElement('span');
      screen.textContent = change.screen;
      field.textContent = change.field;
      before.textContent = change.before;
      before.className = 'is-before';
      arrow.textContent = '→';
      after.textContent = change.after;
      after.className = 'is-after';
      label.append(screen, field);
      values.append(before, arrow, after);
      row.append(label, values);
      if (change.visualEffect) {
        const effect = documentRef.createElement('small');
        effect.className = 'ai-intake-change-preview-effect';
        effect.textContent = change.visualEffect;
        row.append(effect);
      }
      table.append(row);
    });
    host.append(table);
  } else {
    const empty = documentRef.createElement('p');
    empty.className = 'ai-intake-no-changes';
    empty.textContent = preview.validationState === 'review_only'
      ? 'Information only — no operational change is proposed.'
      : 'No validated before/after changes are available. Approval remains blocked.';
    host.append(empty);
  }
}

function enhanceAiIntakeReviewCard(card, item, documentRef = document) {
  if (!card || !item) return;
  const review = buildAiIntakeReviewSummary(item);
  const preview = buildAiIntakeDetectedChangePreview(item);
  const summary = card.querySelector('.ai-intake-email-summary');
  if (summary) {
    summary.classList.toggle('is-available', review.available);
    summary.classList.toggle('is-missing', !review.available);
    summary.setAttribute('aria-label', 'Email summary');
    const paragraph = summary.querySelector('p');
    if (paragraph) paragraph.textContent = review.text;
    summary.querySelector('[data-ai-summary-warning]')?.remove();
    if (review.warning) {
      const warning = documentRef.createElement('small');
      warning.dataset.aiSummaryWarning = 'true';
      warning.setAttribute('role', 'alert');
      warning.textContent = review.warning;
      summary.append(warning);
    }
  }

  renderAiIntakeDetectedChangePreview(documentRef, card.querySelector('.ai-intake-detected-changes'), preview);

  const proposedAction = card.querySelector('.ai-intake-proposed-action');
  let effects = card.querySelector('.ai-intake-decision-effects');
  if (!effects && proposedAction) {
    effects = documentRef.createElement('section');
    effects.className = 'ai-intake-decision-effects';
    effects.setAttribute('aria-label', 'Decision effects');
    proposedAction.insertAdjacentElement('afterend', effects);
  }
  if (effects) {
    effects.replaceChildren();
    if (preview.approvalSupported) appendDecisionEffect(documentRef, effects, 'If approved', preview.approvalEffect, 'is-approved');
    appendDecisionEffect(
      documentRef,
      effects,
      preview.approvalSupported ? 'If rejected' : item.action_type === 'review_only' ? 'If dismissed' : 'If not approved',
      preview.rejectionEffect,
      'is-rejected',
    );
  }

  const approve = card.querySelector('[data-ai-intake-apply]');
  if (approve && (!review.approvalReady || !preview.approvalSupported)) {
    approve.disabled = true;
    approve.title = !review.approvalReady ? 'Email summary required before approval' : 'Validated operational change preview required before approval';
  }
}

function enhanceAiIntakeReviewRows(documentRef = document, items = []) {
  const byProposal = new Map(items.map(item => [String(item?.proposal_id || ''), item]));
  documentRef.querySelectorAll('.ai-intake-review-card[data-ai-intake-proposal]').forEach(card => {
    enhanceAiIntakeReviewCard(card, byProposal.get(String(card.dataset.aiIntakeProposal || '')), documentRef);
  });
}

function installAiIntakeReviewOverlay(windowRef = window, documentRef = document) {
  if (typeof renderServerAiIntake !== 'function' || typeof decideServerAiIntake !== 'function') return false;
  const originalRender = renderServerAiIntake;
  const originalDecision = decideServerAiIntake;

  renderServerAiIntake = function renderServerAiIntakeWithDecisionContext(...args) {
    const result = originalRender.apply(this, args);
    const items = typeof app !== 'undefined' && Array.isArray(app.serverAiIntakeItems) ? app.serverAiIntakeItems : [];
    enhanceAiIntakeReviewRows(documentRef, items);
    return result;
  };

  decideServerAiIntake = async function decideServerAiIntakeWithSummaryGate(proposalId = '', decision = '') {
    const normalizedDecision = normalizeAiIntakeDecision(decision);
    if (normalizedDecision === 'apply') {
      const proposal = typeof app !== 'undefined' && Array.isArray(app.serverAiIntakeItems)
        ? app.serverAiIntakeItems.find(item => String(item?.proposal_id || '') === String(proposalId || ''))
        : null;
      const preview = proposal ? buildAiIntakeDetectedChangePreview(proposal) : null;
      if (proposal?.action_type === 'review_only') {
        windowRef.alert('Approval blocked: this is an information-only item. Review it and use Dismiss; no car can be changed.');
        renderServerAiIntake();
        return false;
      }
      if (!proposal || !buildAiIntakeReviewSummary(proposal).approvalReady || !preview?.approvalSupported) {
        windowRef.alert('Approval blocked: this item does not have a readable, validated before/after change preview. Reject it or refresh after the source evidence is reviewed.');
        renderServerAiIntake();
        return false;
      }
    }
    return originalDecision.call(this, proposalId, normalizedDecision);
  };

  const items = typeof app !== 'undefined' && Array.isArray(app.serverAiIntakeItems) ? app.serverAiIntakeItems : [];
  enhanceAiIntakeReviewRows(documentRef, items);
  return true;
}

const api = {
  AI_INTAKE_PREVIEW_EVENTS,
  buildAiIntakeReviewSummary,
  buildAiIntakeDetectedChangePreview,
  normalizeAiIntakeDecision,
  renderAiIntakeDetectedChangePreview,
  enhanceAiIntakeReviewCard,
  enhanceAiIntakeReviewRows,
  installAiIntakeReviewOverlay,
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
if (typeof window !== 'undefined') {
  window.PDC_AI_INTAKE_REVIEW = api;
  if (typeof document !== 'undefined') installAiIntakeReviewOverlay(window, document);
}
