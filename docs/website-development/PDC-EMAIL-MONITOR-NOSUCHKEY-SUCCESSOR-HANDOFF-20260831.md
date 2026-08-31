# PDC Email Monitor — NoSuchKey readback successor handoff

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard association: `20260828_191153_4fb787`
Production: not contacted or modified
Outbound email: disabled; no email sent
UAC: not launched

## Implemented

The protected IMAP bridge successor accepts only the exact post-upload eventual-consistency response (`HTTP 400`, `code=NoSuchKey`, `statusCode=404`, `message=Object not found`) for a bounded three-attempt authenticated Storage object readback. It sleeps 0.25s then 0.5s between retries. Near-miss errors, exhausted retries, byte/size/hash/MIME mismatches, and all other failures remain fail-closed.

Changed source: `backend/imap_bridge_successor_20260865.py`
Regression: `tests/test_storage_nosuchkey_readback_successor_20260869.py`

## Bundle and controls

Bundle: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/pdc-monitor-staging-m502-2026.08.69`
Build receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/pdc-monitor-staging-m502-2026.08.69.build-receipt.json`
Release: `pdc-monitor-staging-m502-2026.08.69`
Parent: `pdc-monitor-staging-m502-2026.08.68`
Manifest SHA-256: `fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823`
Parent manifest SHA-256: `f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b`
Bridge SHA-256: `d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071`
Inventory: 3350 files; complete inventory verifier passed.

Prepared controls:
- `scripts/install_pdc_monitor_successor_20260869.ps1` — idempotent elevated installer; requires task already Disabled; never enables or starts it.
- `scripts/launch_pdc_monitor_successor_20260869.ps1` — redacted receipt/launcher preparation; UAC was not requested by this unattended run.
- `scripts/rollback_pdc_monitor_successor_20260869.ps1` — exact rollback from `CURRENT=2026.08.69` to `2026.08.68`, disabling the task first.

## Verification

- Focused regression: 4 passed.
- Python syntax compilation: passed.
- Bundle build: passed.
- Complete protected bundle static verification: passed.
- `npm run test` / `npm run check`: passed (`229 passed, 0 failed, 1 skipped`).
- Staging branch readback: `commissioning/pdc-monitor-859` points to commit `6e868446ab8aa72be4d4d11c48f51dfed166c3bb`; raw GitHub source readback returned HTTP 200 with all retry/fail-closed markers. Pages workflow has no run for this non-Pages commissioning branch; the only commit check is skipped `Supabase Preview`.
- Installation: not performed; the installer targets protected ProgramData and therefore requires interactive elevation. The task remains disabled at the observed installed `.68` state.
- No mailbox, UID514, outbound email, Production, task enablement, or UAC action was performed.

## .69 installation attempt and corrected path

The human-approved `.68` install remains the last successful protected install. The `.69` attempt at `2026-08-31T04:19:40Z` failed closed after `CURRENT` became `.69`: its inventory verifier could not read the newly ACL-protected `releases\\2026.08.69\\release-manifest.json` and returned Access Denied. The later `04:20` wrapper produced no fresh receipt and is treated as cancelled. The task remains safely Disabled with no mailbox, UID514, outbound or Production action.

The routine defect is installer/verifier ordering. The corrected elevated stage pins the installer/verifier hashes, grants only direct temporary access to the existing target/manifest and ancestors when needed, verifies the external immutable bundle, lets the installer own final ACL hardening, and restores temporary snapshots only on failure. It does not use `takeown`, ACL reset, permanent user access, task enablement or task start. The installer and rollback additionally assert `LOCAL SERVICE`/`ServiceAccount`/`Limited`/`PT5M`.

Corrected preparation receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/corrected-installer-path-preparation-receipt.json` (`uac_launched=false`, `task_enable_requested=false`). Ordering/security regression: `8 passed`; PowerShell parse: passed.

## New human-only blocker

The `.69` repair path is historical only. The current protected continuation is the `.71` VerifyOnly → bounded OneCycle → monitor-task enable path recorded below; do not launch any UAC prompt from this unattended lane.

## Superseding chronology correction

Fresh native readback supersedes the earlier `.69` current-state wording: `CURRENT=2026.08.71`; `.71` release/control/trust/venv directories exist; and `PDC-PMB-Email-Monitor-Staging` is still `Disabled` / `LOCAL SERVICE` / `ServiceAccount` / `Limited` / `PT5M` / `LastTaskResult=1` with no new `.71` run. The `.71` install receipt was overwritten around `2026-08-31T10:01Z` with `ok=true`, control hash `3af444ce…`, `stale_partial_removed=true` and `task_enabled=true`, but that flag is for the separate AI-successor task in the installer and does not prove monitor-task enablement.

The cancelled `PDCMonitor-Repair-Schedule-20260871.ps1` path also targeted the AI-successor task, disabled it before trigger repair, and has no receipt. The non-elevated `.71` verifier failed closed with `PDC_MONITOR_071_VERIFY_FILE_MISSING` on protected `release-manifest.json`; no UAC was launched by this unattended lane.

Prepared corrected monitor continuation: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/launch_verify_onecycle_enable_pdc_monitor_20260871.ps1`. It performs protected VerifyOnly, one bounded active-dispatch cycle, authoritative side-effect checks, then enables the existing monitor task without manually starting it. It remains unstarted pending one human Administrator/UAC action.

## Later `.71` attempt

An earlier `.71` attempt produced an `ok=false` `PDC_MONITOR_071_CONTROL_HASH_MISMATCH` receipt with protected staging cleanup access denied. That receipt was subsequently overwritten around `2026-08-31T10:01Z` by the current `ok=true` `.71` install receipt; the monitor task’s native state remains separately Disabled.

The source/build repair corrected the incompatible control hash algorithm (JSON inventory versus line-oriented tree), canonicalized the manifest to LF bytes, creates the staging `root-control` directory before copy, keeps the elevated wrapper disabled-only until protected VerifyOnly and bounded OneCycle gates pass, and pins the manifest and bundled installer hashes before execution. Prepared corrected bundle: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/pdc-monitor-staging-m502-2026.08.71`; manifest `13f3affa82e334195b93126c09764c29b50da55e2339642063c2e94d22811c1f`; control tree `3af444ce65b52935a13e57df17b7dfb3dd329719aff59775a8bc266d740b6749`; 3,359 files; inventory/control/canonical-byte checks passed.

Prepared disabled-only retry: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260871-repaired/PDCMonitor-Install-20260871-repaired.ps1`. No UAC was launched. The bundled legacy `verify_release.py` remains unchanged and is separately incompatible with the later `.69`-derived `.71` metadata; this does not change the corrected `.71` operational control contract.
