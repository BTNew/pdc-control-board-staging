# PDC Email Monitor — staging commissioning correction handoff

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard association: `20260828_191153_4fb787`
Production: not contacted or modified
Outbound email: disabled; no email sent
UAC: not launched

## Corrected authoritative outcome

Commissioning is complete in STAGING. After successor 859 repaired the compatibility projection and attachment-path handling, protected VerifyOnly and bounded OneCycle passed while scheduling was disabled. The Scheduled Task is now enabled as `LOCAL SERVICE` / `ServiceAccount` / `Limited` with its exact `PT5M` trigger. Three consecutive natural runs completed with `LastTaskResult=0`; the latest enabled-state confirmation ran at `2026-08-31T02:13:34Z`.

## Exact post-commissioning failure

The protected `.68` run reached the monitor path and reported `attachment storage path is invalid` for one malformed failed attachment row. A narrow staging cleanup removed only that exact malformed row after checking its intake, graph part, filename, source hash, failed status and mismatch error. UID514 remained present and unchanged (`1` row); mailbox flags, outbound email and Production remained untouched.

## Earlier failed verification (superseded)

- Protected VerifyOnly attempted at `2026-08-31T01:40:31Z`: failed closed with `PDC_MONITOR_766_PREFLIGHT_DENIED`.
- Protected bounded OneCycle while the task was disabled attempted at `2026-08-31T01:41:00Z`: failed closed with `PDC_MONITOR_766_PREFLIGHT_DENIED`.
- Both runs contacted no mailbox, processed no UID514 row and contacted no Production.

## Root cause (resolved)

Read-only staging inspection showed the live migration head was `20260831240000 / 858_runtime_authority_839_scope_compatibility_successor`. The protected installed `.68` verifier required the legacy RPC response values `migration_head=766` and `compatibility_successor_head=766`, so it correctly failed closed against the newer live head. Successor 859 resolved this incompatibility without changing the protected runtime or weakening its checks.

## Earlier fail-closed task state (superseded)

- State: `Disabled`
- Enabled: `false`
- Identity: `LOCAL SERVICE`, `ServiceAccount`, `Limited`
- Trigger: `PT5M`
- Last run: `2026-08-31T01:28:34Z`
- Last result: `1`
- Next run: `N/A`
- Natural successful cycles after repair: `0`

Fresh redacted receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260868/natural-run-enable-receipt.json`

## Successor completion

- Append-only staging successor `20260831250000 / 859_runtime_766_compatibility_and_attachment_path_successor` is applied and read back live.
- The protected .68 legacy response is restored exactly at `migration_head=766` and `compatibility_successor_head=766`; the function internally validates the live 858+ chain and exact authenticated 839 scope. Protected 672 and the local verifier were not changed.
- Attachment storage paths are normalized per message; malformed paths are represented as `path_quarantined`/null in the read projection only. No Board mutation, mailbox-flag mutation, UID514 processing, outbound email, or Production contact occurred.
- Protected VerifyOnly and disabled bounded OneCycle both passed `ok=true` with no mailbox contact.
- Two NEW consecutive natural PT5M runs passed at `2026-08-31T09:58:34+08:00` and `2026-08-31T10:03:34+08:00`. Both returned `LastTaskResult=0`; processor failures were `0`.
- The task was then left enabled, and a third natural enabled-state confirmation passed at `2026-08-31T10:13:34+08:00` with `LastTaskResult=0`. Authoritative readback at `2026-08-31T02:17:26Z` showed `Ready`, enabled, `PT5M`, and next run `2026-08-31T02:18:33Z`.
- Fresh redacted receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260868/natural-run-enable-receipt.json` (`ok=true`).
- Final dashboard association: `20260828_191153_4fb787`.
