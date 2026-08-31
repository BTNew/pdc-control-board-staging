# Commissioning runbook

## Gate order

1. INSPECT — verify pack checksum, exact source commit, STAGING project/sentinel, Production absence, `.68` rollback and no secrets in pack.
2. INSTALL — use the protected `.69` bundle only; validate the successful installer receipt, manifest/parent/bridge hashes, `CURRENT=.69`, inventory and ACL. Do not relaunch installer during activation.
3. CONFIGURE — bind exact gateway `pdc-email-ai-successor-069`, mailbox `pdc-emails`, version fields and protected DPAPI runtime store. Keep outbound false.
4. VERIFY SUPABASE CONTRACT — read live migration head, RPC definitions, grants, FORCE RLS, Realtime publication and service-role denial.
5. PROVISION/VERIFY CREDENTIALS — owner-only Auth create/rotate path, dedicated non-human identity, exact scopes, runtime login, digest equality, hostile actor/gateway/action/table/SQL denials. Never expose owner key.
6. VERIFY MAILBOX — owning `pdc-emails` connector proves sender enrollment, mailbox identity, UIDVALIDITY and future-only high-water mark without changing flags.
7. RUN SAFE TEST EMAIL — exactly one fresh authorized PMB email with valid Job Card and backend Stock, sent only after all prior gates. Natural PT5M pickup only.
8. VERIFY SUPABASE READBACK — capture provider UID/message/thread/attachment/source/evidence digests, typed plan, all versions, action/RPC receipts, Stock/canonical vehicle, operations/hours/workgroups/dates, expected-vs-actual authoritative state.
9. VERIFY BOARD — compare live AI Intake UI/read projection and Board/read model with authoritative IDs, versions, actions and verification statuses.
10. ENABLE AUTOMATION — only after all prior gates; enable PT5M, never manually run it.

## Natural fixture

Use the frozen safe fixture:

- Stock `13023405`
- Job Card `J13923405`
- `job-card-13023405.pdf`
- four operations: OP1 `5.18`, OP2 `1.00`, OP3 intentional `0.00`, OP4 `0.75`

The pdc-emails owner lane sends the one message. This profile does not borrow its secret.

## Natural acceptance

Wait for a natural PT5M pickup. Record exact sanitized evidence and verify the action chain. Then repeat the exact same source through the normal scheduled path and prove zero duplicate vehicles, operations, bookings, notes, completions, attachments, receipts, history or drafts. Prove an unrelated vehicle is unchanged. Run two natural result-0 cycles with real pending work where safe and continue the 12-cycle/24-hour soak gates.

## Disable/rollback

On failure, disable successor automation through the protected owner path, preserve all receipts/source bytes, revoke runtime capability if required and leave `.68` available. Do not delete evidence or touch Production.
