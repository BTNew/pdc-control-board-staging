# PDC Email Historical Reconciliation — Redacted STAGING Handoff

Date: 2026-08-31 WAST; dashboard `20260828_191153_4fb787`
Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only
Production: untouched; Production sentinel absent

## Outcome

The authorized frozen 15-row historical Apply completed in STAGING.

- Five exact renewed rows imported:
  - `1:133` -> Stock `13047164`
  - `1:134` -> Stock `13047383`
  - `1:137` -> Stock `13047272`
  - `1:168` -> Stock `13049488`
  - `1:172` -> Stock `13044227`
- Ten material conflict rows remain pending/review and were not authorized:
  `1:21, 1:22, 1:23, 1:26, 1:40, 1:57, 1:85, 1:93, 1:95, 1:96`
- No historical Apply was run for the ten conflicts.
- Primary local Apply outbox:
  `C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-apply-20260831-0645.sqlite3`
- Primary outbox SHA-256:
  `9536549b9196b36481bc243400c43b04a31810f78cbc9b82c3114ff78aafb7f7`
- Primary outbox state: 15 rows, 5 imported, 10 review, 0 retry, one attempt each.

## Live STAGING proof

- Current migration head: `20260831050000 / 838_ignore_non_monitored_mailbox_alias_successor`
- Historical reconciliation receipts: `5`
- Receipt UIDs: exact five renewed UIDs above
- Provider observations: `24` (4 + 4 + 6 + 6 + 4)
- Intake attachments for the five receipts: `24`
- Complete-domain readbacks: `5`
- 1:134 job-card child receipt: `1`, with `9` operation lines
- 1:134 operation-hours evidence: immutable correction row present; legacy aggregate `0`, authoritative aggregate `NULL`, known count `0`, unknown count `9`, coverage `0`
- Active renewed authorizations: `5`, all unexpired
- Active monitored mailboxes: `1` exact staging test mailbox (`pdc_pmb_email` / Gmail / test mode); no mailbox flags were changed
- Pilot enabled: `false`
- Pilot outbound email: `false`
- Automatic rule application: `false`
- Automatic authenticated jobcards: `false`
- Production sentinel: absent

Authoritative full mailbox accounting artifact:

`C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/full-historical-pmb-inbox-accounting.json`

- Artifact SHA-256: `9f92f4c0455ff710764deb7a611a30127781d9c07224428c546428b9229ff62f`
- Frozen boundary: `669` messages, `2305` attachments
- Folder: `INBOX`
- UIDVALIDITY: `1`
- High-water UID: `685`
- Mailbox mutated: `false`
- Outbound email sent: `false`
- Production touched: `false`

## Regression proof

Live `tests/test_historical_authorization_809_live.py` at head 833 passed all four tests:

- five public-wrapper first/replay paths rollback-only;
- exact five renewal rows and evidence bindings;
- malformed authentication, wrong actor and wrong gateway fail closed without drift;
- 1:134 all-unknown operation hours remain evidence-faithful through the immutable 833 overlay.

The first public-wrapper call and exact replay returned the expected success contract:
`ok=true`, `code=historical_reconciliation_782_receipt`, stable receipt/proposal/vehicle/observation identities, and zero unrelated domain drift.

## Security and containment

- Protected historical tables have FORCE RLS enabled.
- Direct authenticated SELECT on protected historical receipts/observations is denied.
- Public reconciliation wrapper and contained UID514 reader are authenticated-only.
- Nested/private historical functions are denied to authenticated, anonymous and service-role identities; execution is postgres-only.
- Approved actor is active `importer` with `approved` account status.
- UID514 authenticated readback: terminal receipt for recovery event `25751401`; mailbox/folder/UIDVALIDITY/UID matched the bounded receipt; protected evidence fields were not exposed.
- Existing monitor task remained disabled during Apply and DB proof; no mailbox flags were changed.
- The exact mailbox/control commissioning state was established by concurrent guarded STAGING successors through live head 838; the local 834/835 candidates failed closed on stale-head preconditions and caused no mutation.
- No outbox other than the explicitly authorized local historical Apply outbox was created or reused for database delivery.
- No unapproved outbound email, task/pilot enablement during Apply, or Production operation occurred.

## Applied source parity

Applied historical successors are present in the source chain and verified against live function/postcondition hashes:

- 819 `c866070b` — importer auth/sender binding
- 820 `8ac43774` — authorized historical importer freshness
- 821 `66121982` — authorized proposal freshness
- 822 `9134ce9c` — verified derived-child historical context
- 823 `a3f5de88` — exact historical parent fan-in exclusion
- 825 `3b8c7554` — deterministic vehicle creation before postcondition
- 826 `ab11b607` — authorized vehicle evidence freshness
- 827 `315e9245` — unknown operation-hour aggregate repair
- 828 `07d1a100` — receipt-first replay ordering
- 831 `b8d10b05` — Navision pre700 linked refresh
- 832/833 — immutable evidence-faithful operation-hour correction
- local caller validator compatibility repair `57b0896c`

Repository contract suite: `261 passed`.
Caller contract suite: `18 passed`.
The DB migration repository has no `package.json`; `npm run test`/`npm run check` were therefore not applicable in this repository.

## Monitor scheduler commissioning status

The existing task definition still has the required identity and schedule:

- Task: `PDC-PMB-Email-Monitor-Staging`
- Identity: `LOCAL SERVICE`
- Logon: `ServiceAccount`
- Run level: `Limited`
- Repetition: `PT5M`

Fresh elevated installation receipt:

`C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260868/install-receipt.json`

reports `ok=true`, installer exit `0`, `CURRENT=2026.08.68`, protected inventory exit `0`, and protected ACLs. The task was left disabled by the installer as required.

The installed `.68` control bundle is now present and protected. A fresh VerifyOnly/commissioning launch was attempted through the supplied receipt-backed elevation wrapper, but the UAC request was canceled before the wrapper started. A concurrent observer subsequently left the task running; it was fail-closed and disabled after returning `LastTaskResult=1`.

`C:/ProgramData/PDCMonitor/Staging/control/2026.08.68/run-current-active.ps1`

The reviewed VerifyOnly/commissioning runner requires a further interactive Administrator/UAC approval in this worker session. The task is left disabled with the safe preserved PT5M configuration and the failed result visible; no manual run or simulated natural cycle was used.

The remaining human-only step is to approve the supplied elevated VerifyOnly/commissioning observer when its UAC prompt is shown. It must run VerifyOnly, then the bounded OneCycle while scheduling is disabled, then enable the existing task and observe two distinct scheduled runs with `LastTaskResult=0`; do not use `schtasks /Run` as a substitute for natural cycles.

No credentials, passwords, tokens, connection strings or secret values are included in this handoff.

## Final independent review

- Review ID: `c34f0279-4eca-4274-87ba-58c4d87a839c`
- `ready_for_apply`: `false`
- `blockers`: protected `.68` installation requires Administrator elevation; the task is disabled after `LastTaskResult=1`; two natural zero-result cycles are not proven.
- No manual run or simulated cycle was used as a substitute.

## Current independent review status

- The prior independent approval for the corrected 834 candidate did not transfer after the live head advanced.
- A fresh review is required for any later source candidate; no later local candidate was applied.
- The only current blocker is the canceled interactive UAC approval for protected VerifyOnly/commissioning execution; fresh VerifyOnly, bounded OneCycle and two natural zero-result cycles remain unproven.
