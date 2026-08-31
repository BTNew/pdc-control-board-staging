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
- Installation: not performed; the installer targets protected ProgramData and therefore requires interactive elevation. The task remains disabled at the observed installed `.68` state.
- No mailbox, UID514, outbound email, Production, task enablement, or UAC action was performed.

Shortest human action when ready: run the prepared launcher once interactively and approve UAC; then the task must remain disabled for VerifyOnly/OneCycle gates before any enablement decision.
