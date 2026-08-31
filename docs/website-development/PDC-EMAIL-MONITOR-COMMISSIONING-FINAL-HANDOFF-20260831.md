# PDC Email Monitor — STAGING commissioning final handoff (human-only activation blocker)

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard: `20260828_191153_4fb787`
Worker session: `20260830_051703_0260dd` (`website-development-lead`)
Production: not contacted or modified
Outbound email: disabled; no email sent

## Authoritative current state

Commissioning is not complete. The elevated `.69` installation receipt is valid (`ok=true`, started `2026-08-31T04:56:16.9486364Z`) and proves `CURRENT=2026.08.69`, inventory verification exit `0`, the pinned `.69` manifest/parent/bridge hashes, and a disabled `LOCAL SERVICE` / `ServiceAccount` / `Limited` / `PT5M` task.

Fresh native task readback at `2026-08-31T07:45:09Z` remains safely fail-closed:

- State: `Disabled`
- Enabled: `false`
- Principal: `LOCAL SERVICE`
- Logon type: `ServiceAccount`
- Run level: `Limited`
- Trigger: `PT5M`
- Last natural run: `2026-08-31T06:23:34Z`
- Last task result: `1`

The latest runtime status failed closed on the `.69` monitor path after the exact bounded NoSuchKey retries were exhausted. No successful post-failure natural cycles are credited.

## Activation defect repaired

The human-approved enable-only activation at `2026-08-31T07:28:30Z` completed its authenticated STAGING observer successfully but failed at task enablement. The first COM task lookup used an invalid doubled root/task path and returned `HRESULT 0x80070002` (`The system cannot find the file specified`). It did not start the task, call OneCycle, contact the mailbox, send outbound email, or contact Production.

The routine source defect is repaired in commit `3cea2add`:

- activation now uses native `Enable-ScheduledTask` rather than the invalid COM lookup;
- the observer uses the protected installed Python runtime rather than a user-local interpreter;
- focused activation contract: `2/2` passed;
- full test and check verification: `229 passed, 0 failed, 1 skipped` for each command;
- `git diff --check`: passed;
- corrected activation script SHA-256: `1e75ab218790bb8dfdee5260a1e2cfa2f0413c04eec6371304573d42ab0206f8`.

A new pinned enable-only launcher is prepared at:

`C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/PDCMonitor-Activate-20260869.ps1`

Launcher SHA-256: `5d13ab976034f114c0cc84ab48ce050a4eaf2d550f29aae40b560fc0bbf93bd6`; PowerShell parse errors: `0`. It validates the corrected activation script hash, never reruns the installer, never starts the task manually, and writes a redacted activation launch record.

## New human-only blocker

Changing the protected Scheduled Task from Disabled to Enabled requires one interactive Administrator elevation. The unattended commissioning lane cannot safely obtain that UAC consent and did not launch another prompt.

Shortest action: run `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/PDCMonitor-Activate-20260869.ps1` with PowerShell and approve its single UAC prompt.

After a successful enable-only receipt, Hermes must still prove two distinct natural `LastTaskResult=0` PT5M cycles and complete authoritative monitor/mailbox/processor/Board, replay/idempotency, duplicate-protection, outbound-disabled, mailbox-flag/UID514 preservation, and Production-exclusion readback before commissioning can be claimed complete.

## Later `.71` attempt and repaired retry path

The later human-approved `.71` attempt is preserved as failed closed at `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871/install-receipt.json`: `ok=false`, `PDC_MONITOR_071_CONTROL_HASH_MISMATCH` with protected staging cleanup access denied, task disabled, and no mailbox/outbound/Production action.

The source/build defect was traced and repaired: the builder used a JSON inventory hash while the installer/verifier used a line-oriented control-tree hash; the builder also emitted non-canonical Windows line endings, omitted staging `root-control` creation, and the elevated wrapper requested automation enablement before VerifyOnly/OneCycle gates. The corrected bundle uses control SHA-256 `3af444ce65b52935a13e57df17b7dfb3dd329719aff59775a8bc266d740b6749`, manifest SHA-256 `13f3affa82e334195b93126c09764c29b50da55e2339642063c2e94d22811c1f`, 3,359 files, exact inventory match and canonical LF manifest.

Prepared retry path: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/PDCMonitor-Install-20260871-repaired.ps1`; redacted preparation receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/corrected-071-control-hash-preparation-receipt.json`. Static `.71` contract tests passed `7/7`, Python compilation and PowerShell parsing passed. No UAC was launched, the task was not enabled, and protected VerifyOnly/OneCycle/natural-cycle proof remains outstanding.

The bundled legacy `verify_release.py` was not changed or bypassed; it is bound to the older immutable 503 release-spec shape and is incompatible with the later `.69`-derived `.71` metadata. This is documented separately from the corrected `.71` operational control/build contract.
