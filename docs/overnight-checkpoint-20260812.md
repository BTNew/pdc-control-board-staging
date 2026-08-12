# PDC staging overnight checkpoint — 2026-08-12

## Boundaries
- Staging project only: `cdsmnqxtyyoeoznmbidd`.
- Production, main, DNS and production credentials untouched.
- Development profile owns this worktree. It must not access/copy `work-receipting` or `pdc-monitor` credentials, browser state, mailbox or runtime state.
- No real outbound email.
- Mailbox UIDVALIDITY 1: UIDs 470–477 remain excluded/untouched. Retained replay point is UID 478 only, and can run only in owning `pdc-monitor` profile after scoped provisioning.

## Approved baseline
- AI Auditor source: `c4183d54583fdb6253f5c6575031de63a79ba82b`.
- Staging migration head: 231.
- Runtime tests: 24/24. Regression: 188/188 plus one intentional skip.
- Approved source/database artifact must not be modified without new SHA, tests, regression and reviews.
- Real Telegram activation remains blocked: development profile is not `work-receipting`; runtime is not installed there; Telegram evidence is not gateway-signed; real ingress/restart/two-user browser tests are outstanding.

## Clean implementation worktree
- Path: `C:\Users\nwmgr\HermesWorkspaces\development\pdc-overnight-implementation-20260812`
- Branch: `feat/staging-overnight-implementation-20260812`
- Base: `c4183d54583fdb6253f5c6575031de63a79ba82b`
- Primary repo `C:\Users\nwmgr\pdc-control-board` was already dirty with unrelated historical work and must not be reset or used for overnight edits.

## Owning-profile replay points
### work-receipting
1. Verify credential-free handoff signature/hash and exact approved source.
2. Provision scoped secrets inside that profile only.
3. Implement/verify cryptographically gateway-signed Telegram evidence before activation.
4. Install runtime, automatic startup and durable queue/receipts.
5. Run real Review, reversible Apply/retry, Undo/retry, unauthorized/altered/replayed evidence, restart recovery and two-user Realtime tests.

### pdc-monitor
1. Verify monitor release compatibility with DB head 231; never downgrade.
2. Provision only scoped Monitor/access identities in that profile.
3. Keep high-water below 478 until all four UID478 attachments are independently receipted or safely reviewed.
4. Replay UIDVALIDITY 1 UID478 only; never touch 470–477.
5. No outbound email or mailbox flag changes.

## Durable status
This file is the restart checkpoint. Git commits on the overnight branch are the authoritative implementation checkpoints. Credentials and secret material must never be added here.

## Implementation checkpoint
- Exact implementation SHA before this checkpoint update: `d7034799b4066d7eafe457a9c79ac7c7523b21c3`.
- Proposed append-only staging migrations `232`–`236` rehearse sequentially against permanent head `231` in one rollback-only transaction; none is permanently applied yet.
- Scope: mechanic/default-technician trigger and exclusive history; UID478 attachment-atomic receipts; bounded Sublet expected-return conflicts; reversible operation soft removal; authorised fuel-fill rule.
- Full JavaScript regression: 194 passed, 0 failed, 1 intentional skip.
- Python discovery: 33 passed, 3 optional XLSX skips. Syntax/compile and diff checks passed.
- UID478 was not replayed; `pdc-monitor` mailbox and credentials were not accessed.
- AI Auditor was not activated; `work-receipting` credentials and gateway were not accessed.
- Website helper/QC/notification modules and Vehicle Config processing core are foundations, not proof of integrated/activated runtime behavior.
- Three exact-SHA independent reviews are in progress: database security, frontend/provenance and Vehicle Config integrity.

## Resume protocol
1. Verify clean worktree and exact HEAD.
2. Read the three independent reviews and fix every valid finding; any source change requires reviews against the new SHA.
3. Confirm permanent staging migration head remains `231` before applying `232`–`236` sequentially.
4. Do not deploy or claim activation for owning-profile runtimes from development.
5. Keep production, main and DNS untouched.
