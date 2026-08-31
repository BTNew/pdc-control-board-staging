# PDC Email Monitor — STAGING commissioning final handoff (blocked)

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard: `20260828_191153_4fb787`
Worker session: `20260830_051703_0260dd` (`website-development-lead`)
Production: not contacted or modified
Outbound email: disabled; no email sent

## Authoritative current state

Commissioning is not complete. The fresh elevated `.68` installation receipt is valid (`ok=true`, started `2026-08-30T23:32:28.8262150Z`) and proves `CURRENT=2026.08.68`, protected release/control/trust/secrets ACLs, complete installed inventory, and the exact `LOCAL SERVICE` / `ServiceAccount` / `Limited` / `PT5M` task identity.

A later natural cycle exposed a new protected-runtime defect: immediately after a verified attachment upload, the authenticated Storage readback returned the exact eventual-consistency response `HTTP 400 / NoSuchKey / statusCode 404 / Object not found`. The task failed closed before enqueue completion. Native task readback at `2026-08-31T04:11:40Z` showed it safely Disabled, enabled=false, `LastTaskResult=1`, last run `2026-08-31T11:38:34+08:00`.

The previous success narrative and natural-cycle proof are superseded by this later authoritative failure. Replay/idempotency, duplicate protection and Board readback are not credited for the failed rerun.

## Prepared protected successor

Release `2026.08.69` adds only a bounded retry for the exact post-upload eventual-consistency response: three authenticated readback attempts with 0.25s and 0.5s delays. Near-miss errors, exhausted retries and content/hash/size/MIME mismatches remain fail-closed.

- Bundle: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/pdc-monitor-staging-m502-2026.08.69`
- Manifest SHA-256: `fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823`
- Parent manifest SHA-256: `f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b`
- Bridge SHA-256: `d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071`
- Verification: focused regression 4/4 passed; complete 3,350-file inventory verifier passed.
- Receipt-backed launcher: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/PDCMonitor-Install-20260869.ps1`
- Launcher SHA-256: `63fc062f82e2a0e12871e49cad8ea366bd55a5e73baad98bff03aa1fba45d3f1`
- Elevated stage SHA-256: `1cb25a96dccc3ab4dea8c490616cdba93f88654a3e73441ac49f8c701358e5d8`
- Both PowerShell files parse with zero syntax errors. The installer requires the task to remain Disabled and does not enable or start it.

## Human-only blocker and continuation

One interactive Administrator UAC approval is required because the successor must be written into inheritance-protected ProgramData. No UAC was launched by the unattended cron run.

Shortest action: right-click `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/PDCMonitor-Install-20260869.ps1`, choose **Run with PowerShell**, and approve the single UAC prompt.

After a fresh `.69` `install-receipt.json` records `ok=true`, Hermes will keep scheduling disabled, run protected VerifyOnly and bounded OneCycle, enable the exact PT5M task, prove two distinct natural `LastTaskResult=0` cycles, and complete authoritative mailbox/processor/Board, replay/idempotency, duplicate-protection, outbound-disabled and Production-exclusion readback.

## Superseding .69 failure and corrected installer path

The `.69` elevated attempt at `2026-08-31T04:19:40Z` failed closed after `CURRENT` became `.69`: inventory verification could not read the newly ACL-protected `.69/release-manifest.json` and returned Access Denied. The later `04:20` wrapper produced no fresh receipt and is treated as cancelled. No mailbox, UID514, outbound or Production action occurred; the task remains Disabled / `LOCAL SERVICE` / `Limited` / `PT5M` with result `1`.

The corrected path repairs only installer/verifier ordering. It pins the installer/verifier hashes, grants only direct temporary elevated-SID access to the existing target/manifest and ancestors when needed, verifies the external immutable bundle, lets the installer own final ACL hardening, and restores temporary snapshots only on failure. No ACL reset, `takeown`, permanent user grant, task enable or task start is used. Installer and rollback now assert the exact task identity and `PT5M` trigger.

Preparation receipt: `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/corrected-installer-path-preparation-receipt.json`; ordering/security tests `8 passed`; PowerShell parse passed; UAC was not launched.

## New human-only blocker

The inheritance-protected `.69` ProgramData release cannot be repaired or fully read back non-elevated. Do not launch another UAC prompt from this worker. When Craig is available, the shortest action is one run of `C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869/PDCMonitor-Install-20260869.ps1` and approval of its single UAC request. Completion remains unclaimed until the corrected receipt reports `ok=true`, then VerifyOnly, disabled bounded OneCycle and two natural zero-result cycles are freshly proven.
