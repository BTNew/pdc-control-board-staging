# PDC Email Monitor .44 authenticated identity successor handoff

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and the protected local staging runtime only.
Production: untouched.

## Outcome

The exact active identity mismatch is repaired through append-only staging
successor 672. The sealed `.44` release, its `CURRENT` pointer, inventory,
670/671 history, planner and trust receipt remain preserved. The successor
accepts only a normal Supabase JWT whose database role is `authenticated`, and
then proves the exact actor and server-side importer capability inside guarded
`SECURITY DEFINER` RPCs.

## Exact successor

- Migration: `supabase/staging_only/20260827067200_672_authenticated_active_email_monitor_identity_successor.sql`
- Migration SHA-256: `9f5efd2fbaa5f9d66783f27f660dbaa585598a773d67f2c9059eddb5362fbefc`
- Predecessor: exact ledger head `20260827067100`, name
  `671_email_monitor_active_planner_rotation_after_670`
- Active attestation RPC:
  `verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)`
- UID514 read-only RPC:
  `read_pdc_uid514_transaction_receipt_authenticated_672(integer)`

Every call proves, server-side: actor UUID
`df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`, database/JWT email
`sales@broometoyota.com.au`, JWT role `authenticated`, exactly one approved
active server application role `importer`, exactly one active writer, exact
gateway/release/source/manifest, commissioned planner/trust pair, staging
sentinel, absent Production sentinel, zero active mailboxes and disabled
automatic pilot. Auditor identities, wrong actors, wrong roles and wrong
gateways fail closed.

The new capability/history tables are forced-RLS and immutable. Only the two
new RPCs are executable by `authenticated`; `anon`, `service_role`,
`pdc_email_monitor` and direct table DML remain denied. No JWT was issued or
custom-signed, no signing secret was used, and no broad authenticated table DML
was granted.

## Live staging proof

Management-path preflight and apply completed with exact predecessor guards.
Live read-only database claims using standard `authenticated` claims returned:

- active attestation: `ok=true`, code
  `runtime_binding_verified_authenticated_672`, migration head `503`,
  compatibility head `672`, operational/activation-ready true, writer and
  planner commissioned true, server role `importer`, Production writes false;
- UID514 reader: `ok=true`, `uid514_receipt_terminal`, terminal true, Inbox,
  UIDVALIDITY 1 / UID 514, seven MIME parts, four retained authenticated
  attachment records, zero vehicle operations and zero operation lines;
- repeated attestation returned the identical result;
- wrong actor and `pdc_email_monitor` JWT claims were rejected with
  `PDC_672_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED`;
- wrong gateway returned `ok=false`,
  `runtime_binding_mismatch`, `activation_ready=false`;
- privilege read-back: authenticated execute true for both new RPCs, anon and
  service_role execute false, capability tables not selectable, history RLS and
  forced RLS true, active writers 1, active mailboxes 0, automatic pilot 0.

The installed protected runtime control is:

- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\active-preflight-authenticated-compatibility.py`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current.ps1`
- `C:\ProgramData\PDCMonitor\Staging\trust\2026.08.44\ACTIVE_PREFLIGHT_AUTHENTICATED_COMPATIBILITY_SHA256`

The installer verified `sealed_release_unchanged=true` and left task enablement,
task start, mailbox contact and UID514 processing false.

## Remaining credential handoff

The protected installed `.44` environment currently contains an expired
same-scope actor JWT (`PGRST303 JWT expired`); both parsed claims are otherwise
exact standard `authenticated` claims. This worker did not refresh, rotate,
copy or fabricate credentials and cannot use another profile's credential.

pdc-emails must refresh its own protected standard actor credential, with no
custom JWT/signing-secret path, then run:

`C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current.ps1 -InstallRoot C:\ProgramData\PDCMonitor\Staging -VerifyOnly`

That control path uses the two new exact-actor RPCs and requires terminal UID514
readback before any later monitor action. This handoff does not enable the
Windows task, contact the mailbox, process UID514 or authorize Production.
