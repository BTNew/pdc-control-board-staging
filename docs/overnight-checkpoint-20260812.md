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
