# Commissioning runbook

## Gate order

1. INSPECT — verify pack checksum, exact source commit, STAGING project/sentinel, Production absence, `.68` rollback and no secrets in pack.
2. SELECT TRANSPORT — select the replaceable hosted/server-side transport as the normal path. Select the Windows `.69/.71` bundle only when the temporary rollback gate is explicitly recorded; it is not an implicit fallback.
3. INSTALL — for the optional Windows rollback only, use the protected `.69`/`.71` bundle; validate the successful installer receipt, manifest/parent/bridge hashes, `CURRENT=.69`, inventory and ACL. Do not relaunch installer during activation. Hosted transport has no Windows installation prerequisite.
4. CONFIGURE — bind the selected provider-neutral gateway, mailbox `pdc-emails`, independent transport/planner/model/prompt/business-rule/ruleset/taxonomy/action-contract version fields and protected secret store. Keep outbound false.
5. VERIFY SUPABASE CONTRACT — read live migration head, RPC definitions, grants, FORCE RLS, Realtime publication and service-role denial.
6. PROVISION/VERIFY CREDENTIALS — owner-only Auth create/rotate path, dedicated non-human identity, exact scopes, runtime login, digest equality, hostile actor/gateway/action/table/SQL denials. Never expose owner key.
7. VERIFY MAILBOX — owning `pdc-emails` connector proves sender enrollment, mailbox identity, UIDVALIDITY and future-only high-water mark without changing flags.
8. VERIFY PLANNER AND EVIDENCE POLICY — prove the configured AI planner/model is the normal live engine, deterministic code is limited to fixtures/regression/validation/fail-safe, action-specific Job Card/attachment gates are loaded, and Sublet requires explicit permitted evidence plus one exact canonical booking/provider instance.
9. RUN SAFE TEST EMAIL — exactly one fresh authorized PMB email with valid Job Card and backend Stock, sent only after all prior gates. Natural pickup only.
10. VERIFY SUPABASE READBACK — capture provider UID/message/thread/attachment/source/evidence digests, typed plan, all versions, per-action audit/disposition/action-RPC receipts, Stock/canonical vehicle, operations/hours/workgroups/dates, expected-vs-actual authoritative state.
11. VERIFY BOARD — compare live AI Intake UI/read projection and Board/read model with authoritative IDs, versions, actions and verification statuses.
12. ENABLE AUTOMATION — only after all prior gates; enable the selected hosted transport. Enable Windows only as the explicitly temporary rollback lane; never manually run it.

## Natural fixture

Use the frozen safe fixture for the Job Card/operation action path:

- Stock `13023405`
- Job Card `J13923405`
- `job-card-13023405.pdf`
- four operations: OP1 `5.18`, OP2 `1.00`, OP3 intentional `0.00`, OP4 `0.75`

The pdc-emails owner lane sends the one message. This profile does not borrow its secret.

## Natural acceptance

Wait for a natural PT5M pickup. Record exact sanitized evidence and verify the action chain. Then repeat the exact same source through the normal scheduled path and prove zero duplicate vehicles, operations, bookings, notes, completions, attachments, receipts, history or drafts. Prove an unrelated vehicle is unchanged. Run two natural result-0 cycles with real pending work where safe and continue the 12-cycle/24-hour soak gates.

For a mixed-result message, verify every action independently: conditional
Job Card/attachment evidence, Sublet evidence gate, planner/model/prompt/
business-rule/ruleset/taxonomy/transport/action-contract provenance, one
terminal disposition and one action-level AI Intake audit. The aggregate must be
`PARTIAL_FAILURE` when outcomes differ. A planner outage must be visible as a
typed retry/quarantine/block, never a silent deterministic decision.

## Disable/rollback

On failure, disable successor automation through the protected owner path,
preserve all receipts/source bytes, revoke runtime capability if required and
leave the Windows `.68` lineage available only as the temporary rollback lane.
Do not delete evidence or touch Production. Hosted transport replacement must
not require changing planner or domain-action semantics.

## Commissioning acceptance

- hosted transport is replaceable and is the default portable path;
- Windows installation/use is explicitly time-bounded rollback, never silent
  fallback;
- action-specific evidence gates and evidence-gated Sublet are enforced;
- independent action dispositions, action-level audit and per-decision
  provenance are present for every outcome;
- deterministic logic is used only for fixtures/regression/validation/fail-safe;
- retained safety controls and clean-room portability are proven before any
  automation enablement.
