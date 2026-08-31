# Simplified PDC Email AI — Recovery / Commissioning Pack

Pack version: `pdc-email-ai-recovery-pack-v1`
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard: `20260831_095314_64feeb`
Production: prohibited; no Production credential, endpoint, branch, data or release is part of this pack.

Authoritative private release: `https://github.com/BTNew/pdc-email-ai-successor-recovery/releases/tag/pdc-email-ai-recovery-pack-v1.5`

## Portable recovery answer

A fresh PC can restore this successor only when it has:

1. this pack or the immutable GitHub release artifact;
2. a clean clone of the exact source commit recorded in `RECOVERY-PACK-MANIFEST.json`;
3. explicitly supplied protected STAGING credentials for the owner provisioning and mailbox sender lanes;
4. the protected `.69` transport installation permission when Windows ProgramData ACLs require elevation.

The pack is designed to make the answer **YES** after the clean-room procedure completes and produces the required evidence bundle. Before that clean-room run, the claim is not accepted merely from documentation or source tests.

## One bootstrap command

From a clean checkout, run:

```text
python bootstrap_recovery.py --pack-root . --source-root source-snapshot --execute
```

The command is deterministic and fail-closed. It executes these gates in order and records a secretless report:

`INSPECT -> INSTALL -> CONFIGURE -> VERIFY SUPABASE CONTRACT -> PROVISION/VERIFY CREDENTIALS -> VERIFY MAILBOX -> RUN SAFE TEST EMAIL -> VERIFY SUPABASE READBACK -> VERIFY BOARD -> ENABLE AUTOMATION`

External protected connectors are supplied by environment variable names documented in `ENV-VAR-CONTRACT.md`; their values are never printed, committed or stored in this pack. The command refuses to continue when a required gate command or credential boundary is absent.

## Pack contents

- `RECOVERY-PACK-MANIFEST.json` — exact pack/source commit, release artifact and checksums.
- `VERSIONS.json` — model, prompt, instruction, taxonomy, business-rule, transport, action and schema versions.
- `SUPABASE-CONTRACT-INVENTORY.json` — append-only migrations, RPCs, action allow-list, grants and RLS expectations.
- `ARCHITECTURE.md` — evidence intake, AI plan, canonical command and authoritative readback layers.
- `COMMISSIONING-RUNBOOK.md` — install, configure, verify, provision, mailbox, natural proof and rollback sequence.
- `ENV-VAR-CONTRACT.md` — names only; no values or secret material.
- `FAILURE-MODES.md` — known failures and repairs, including the real Windows ACL/task/UAC lessons.
- `CLEAN-ROOM-RECOVERY.md` — fresh-PC recovery protocol and elapsed-time evidence.
- `EVIDENCE-REPORT.template.json` — required sanitized result schema for natural proof and clean-room recovery.
- `bootstrap_recovery.py` — one deterministic gated bootstrap command.
- `fixtures/` — safe Job Card/PDF acceptance fixture and pre-state metadata; no mailbox credentials or raw live correspondence.
- `source-snapshot/` — source snapshot manifest and exact Git provenance; the immutable Git release remains authoritative.
- `TRANSPORT-BUNDLE.json` / `TRANSPORT-BUNDLE.md` — exact `.69` full transport asset name, SHA-256, size and installation boundary.

The private v1.5 release also carries `pdc-monitor-staging-m502-2026.08.69.tar.gz`, the 3,351-file secretless transport asset required for clean-room Windows installation.

## Secret boundary

The pack contains no plaintext password, token, service key, DSN, mailbox credential, private key or DPAPI payload. Runtime credentials remain in the dedicated protected secret store, and owner provisioning credentials remain only in the owning protected profile/connector during one-time provisioning.

Never place these in the pack:

- `PDC_STAGING_SERVICE_ROLE_KEY` values;
- Auth admin passwords or tokens;
- mailbox/SMTP/IMAP passwords;
- runtime password or JWT;
- Windows DPAPI bytes;
- production URL/key/connection values.

## Acceptance evidence required

The clean-room report must include only sanitized values:

- pack version, source commit, GitHub release URL and checksums;
- elapsed time and each gate result;
- staging migration head and RPC readback;
- runtime identity presence, exact scope booleans and credential digest equality;
- mailbox UID/provider/message/thread/attachment digests;
- Stock, canonical vehicle ID, Job Card and operation numbers/hours;
- typed plan and all version strings;
- action/RPC receipts and expected-vs-actual authoritative readback;
- Board/UI parity;
- exact replay/repeated schedule zero-effect counts;
- unrelated-vehicle isolation;
- two natural result-0 cycles and soak progress;
- Production/outbound/mailbox safety flags.

Do not report HTTP success, `ok=true`, visual appearance or a local fixture as authoritative business proof.
