# PDC Email Monitor — STAGING commissioning final handoff (human-only activation blocker)

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard: `20260828_191153_4fb787`
Worker session: `20260830_051703_0260dd` (`website-development-lead`)
Production: not contacted or modified
Outbound email: disabled; no email sent

## Authoritative current state

Commissioning is not complete. Fresh native readback now proves `CURRENT=2026.08.71` and both `.69` and `.71` release/control/trust/venv directories exist. The current `PDC-PMB-Email-Monitor-Staging` task remains safely fail-closed:

- State: `Disabled`
- Enabled: `false`
- Principal: `LOCAL SERVICE`
- Logon type: `ServiceAccount`
- Run level: `Limited`
- Trigger: `PT5M`
- Last task result: `1`
- Last run: unchanged old run time; no new `.71` cycle

The `.71` install receipt was overwritten around `2026-08-31T10:01Z` with `ok=true`, `CURRENT=.71`, control hash `3af444ce…`, `stale_partial_removed=true`, and `task_enabled=true`. That flag belongs to the `.71` AI-successor task in the installer, not the existing monitor task. The separate activation record reports the same stale/inconsistent enabled result using an older wrapper hash. Current native `schtasks` readback is authoritative for the monitor task.

The non-elevated `.71` verifier was run read-only and failed closed with `PDC_MONITOR_071_VERIFY_FILE_MISSING` because the protected `.71/release-manifest.json` is not readable without Administrator elevation. No successful `.71` VerifyOnly, OneCycle or natural-cycle proof is credited.

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

## Current human-only blocker

The `.71` release is installed and `CURRENT=2026.08.71`, but the existing `PDC-PMB-Email-Monitor-Staging` task remains Disabled. The `.71` install receipt's `task_enabled=true` refers to the separate AI-successor task; it is not proof that the existing monitor task was enabled. The cancelled schedule-repair process targeted the AI-successor task, disabled it before trigger repair, and left no receipt. PID `7576` and the later matching repair process are no longer running.

The non-elevated `.71` verifier was run read-only and failed closed with `PDC_MONITOR_071_VERIFY_FILE_MISSING` because the protected `.71/release-manifest.json` is not readable. Protected Administrator execution is therefore required for the next gates; this unattended lane launched no UAC prompt and did not enable or start the task.

Prepared minimal continuation: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/launch_verify_onecycle_enable_pdc_monitor_20260871.ps1`. It is designed to verify the installed `.71` release while the monitor task is disabled, run one bounded `.71` active-dispatch cycle, verify fresh status with Production/UID514 exclusion, then enable the monitor task without manually starting it.

The `.71` control/build repair remains verified: control SHA-256 `3af444ce65b52935a13e57df17b7dfb3dd329719aff59775a8bc266d740b6749`, repaired bundle manifest SHA-256 `13f3affa82e334195b93126c09764c29b50da55e2339642063c2e94d22811c1f`, 3,359 files, exact inventory/control/canonical-byte checks, 8 source contract tests, full Node tests/checks `222 passed, 0 failed, 1 skipped` each, Python compilation and PowerShell parsing passed.

The original `.71` install receipt, activation record, schedule-repair launch record, current native task readback and redacted state reconciliation are preserved. The bundled legacy `verify_release.py` was not changed or bypassed; it remains separately incompatible with the later `.69`-derived `.71` metadata.
