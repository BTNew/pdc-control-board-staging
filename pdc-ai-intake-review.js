'use strict';

function buildAiIntakeReviewSummary(item = {}) {
  const text = String(item.summary || '').replace(/\s+/g, ' ').trim();
  if (text) return { available: true, approvalReady: true, text, warning: '' };
  return {
    available: false,
    approvalReady: false,
    text: 'No email summary is available for this review.',
    warning: 'Do not approve this proposal until the source email has a readable summary.',
  };
}

function normalizeAiIntakeDecision(decision = '') {
  return String(decision || '').trim().toLowerCase();
}

function appendDecisionEffect(documentRef, host, label, text) {
  const block = documentRef.createElement('div');
  const heading = documentRef.createElement('span');
  const detail = documentRef.createElement('strong');
  heading.textContent = label;
  detail.textContent = text;
  block.append(heading, detail);
  host.append(block);
}

function enhanceAiIntakeReviewCard(card, item, documentRef = document) {
  if (!card || !item) return;
  const review = buildAiIntakeReviewSummary(item);
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
    appendDecisionEffect(
      documentRef,
      effects,
      'If approved',
      item.action_type === 'board_activate_only'
        ? 'The server re-checks the exact current Navision match, then activates that car on the Control Board if validation passes.'
        : 'Approval is not available for this information-only item.',
    );
    appendDecisionEffect(
      documentRef,
      effects,
      'If denied',
      'The proposal is rejected. No vehicle details or Control Board location are changed.',
    );
  }

  const approve = card.querySelector('[data-ai-intake-apply]');
  if (approve && !review.approvalReady) {
    approve.disabled = true;
    approve.title = 'Email summary required before approval';
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
      if (!proposal || !buildAiIntakeReviewSummary(proposal).approvalReady) {
        windowRef.alert('Approval blocked: this intake item has no readable email summary. Deny it or refresh after the source evidence is reviewed.');
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
  buildAiIntakeReviewSummary,
  normalizeAiIntakeDecision,
  enhanceAiIntakeReviewCard,
  enhanceAiIntakeReviewRows,
  installAiIntakeReviewOverlay,
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
if (typeof window !== 'undefined') {
  window.PDC_AI_INTAKE_REVIEW = api;
  if (typeof document !== 'undefined') installAiIntakeReviewOverlay(window, document);
}
