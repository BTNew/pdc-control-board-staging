# PDC Email Bot .44 active preflight compatibility handoff

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and local staging runtime only.
Production: untouched.

## Root cause

The sealed `pdc-monitor-staging-m502-2026.08.44` release intentionally contains
`agentic_active_planner_trust_receipt_sha256=null`. Its sealed `preflight.py`
therefore rejected the externally commissioned planner with the trust-null
error, even though the exact planner and trust receipt were installed and the
staging database binding had been commissioned by migrations 670 and 671.

## Compatibility repair

Added a guarded external preflight successor and an external control runner:

- `scripts/pdc_active_preflight_compatibility.py`
- `scripts/run_current_active_compatibility.ps1`
- `scripts/install_pdc_active_preflight_compatibility.ps1`
- `tests/test_pdc_active_preflight_compatibility.py`

The successor leaves the sealed release untouched. It requires the exact
2026.08.44 release identity, reads the planner and receipt only from the
protected external trust root, verifies their bytes, validates the receipt
contract, runs the deterministic planner smoke, and sends the narrow active
attestation/readback RPCs with the exact 670 predecessor and 671 commissioned
hash pair. Null, mismatch, path escape, reparse/symlink, ACL, actor, staging
URL, broad-credential and server-attestation failures remain fail-closed.

The control runner uses the successor only for explicit `-AgenticMode active`;
contained mode continues through the sealed launcher. The installer preserves a
byte-verified copy of the original control runner as `run-current-sealed.ps1`.
It does not enable or start the Windows task and contains no mailbox action.

## Exact bindings

- Release: `pdc-monitor-staging-m502-2026.08.44`
- Sealed manifest SHA-256: `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`
- Planner SHA-256 (671): `7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348`
- Trust receipt SHA-256 (671): `e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227`
- 670 predecessor planner SHA-256: `d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a`
- 670 predecessor trust SHA-256: `639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65`
- Installed compatibility successor SHA-256: `36c38b9549de471e6004ede72cf02e760eefd8cb5cde3a3e4e8f96732890f654`
- Installed control runner SHA-256: `932e16ad4367590a8e9caaec1603dc9c2100f681c232ad8077d0cdcd2f16370b`

Protected installed paths:

- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\active-preflight-compatibility.py`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current.ps1`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current-sealed.ps1`
- `C:\ProgramData\PDCMonitor\Staging\trust\2026.08.44\ACTIVE_PREFLIGHT_COMPATIBILITY_SHA256`

The installed compatibility file and its protected hash anchor both read
`36c38b9549de471e6004ede72cf02e760eefd8cb5cde3a3e4e8f96732890f654`.
The preserved sealed runner hash matches the release manifest's original
`run-current.ps1` hash. The sealed manifest hash and release inventory were
unchanged.

## Verification

- Focused compatibility suite: 8 passed, 0 failed.
- Python syntax: `py_compile` passed.
- PowerShell parser: installer and runner 0 syntax errors.
- Full website suite: `npm run test` — 226 passed, 0 failed, 1 skipped.
- Full check: `npm run check` — 226 passed, 0 failed, 1 skipped.
- Installer: completed successfully with `sealed_release_unchanged=true`,
  `task_enabled=false`, `task_started=false`, `mailbox_contacted=false`, and
  `production_contacted=false`.
- Runtime cleanup: removed 6 generated `__pycache__` directories that were
  outside the sealed manifest inventory; manifest SHA remained unchanged.
- Task readback: `PDC-PMB-Email-Monitor-Staging` remains Disabled, principal
  `LOCAL SERVICE`, limited run level.
- Installed active-preflight readback: using a disposable copy of the
  installed config with only the non-secret active-mode switch changed to true,
  the sealed Python 3.11 venv executed the installed successor and planner
  smoke, then stopped at `CREDENTIAL_GATE_NARROW_IDENTITY_REQUIRED`. The old
  `commissioning-injected release trust receipt` error did not occur. The
  disposable config was deleted; no protected credential or task setting was
  changed.
- Exact-match and mismatch live-attestation paths are covered by the focused
  test; an actual staging RPC readback still requires the unexpired
  same-scope `pdc_email_monitor` JWT, which remains a pdc-emails credential
  gate and was not refreshed, copied, rotated or exposed.

## Handoff boundary

pdc-emails can use the protected .44 control runner with explicit active mode
once its own same-scope actor credential is available. This compatibility
repair does not authorize task enablement, mailbox contact, UID514 processing,
credential rotation/copying, or Production access.
