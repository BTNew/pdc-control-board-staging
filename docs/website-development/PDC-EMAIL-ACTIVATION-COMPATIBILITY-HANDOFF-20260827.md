# PDC Email Monitor .44 final activation compatibility handoff

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and protected local staging runtime only.
Production: untouched.

## Completed staging repair

The final compatibility chain is applied and read back:

- 670 `20260827067000`
- 671 `20260827067100`
- 672 `20260827067200`
- 673 `20260827106000`
- 674 `20260827108000` — exact mailbox activation and new authenticated proof/readback
- 675 `20260827109000` — exact authenticated enqueue branch through the disabled-pilot trigger
- 676 `20260827110000` — rollback-control repair for the 674/675 enabled flags
- 677 `20260827111000` — exact retained UID514 recovery enqueue/authorization successor
- 678 `20260827112000`, 679 `20260827114000`, 682 `20260828000000`, 683 `20260828010000` — append-only recovery repairs; see `PDC-EMAIL-UID514-RECOVERY-SUCCESSOR-HANDOFF-20260827.md`

The only active mailbox is the existing staging row:

- id: `12fe383d-5c1e-5801-96e4-f67cf3e3bb57`
- key: `pdc_pmb_email`
- address: `pmbcontroller@gmail.com`
- provider: `gmail`
- `test_mode=true`

No unrelated mailbox was activated. Automatic pilot remains disabled.

## Authenticated RPCs

Use the exact standard Supabase `authenticated` JWT for actor
`df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b` / `sales@broometoyota.com.au`.

- `verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text)`
- `read_pdc_uid514_transaction_receipt_authenticated_674(integer)`
- existing 673 queue/claim/attachment/extraction/result/canonical/agentic RPCs, now reached through the exact 674 active scope

The 674 attestation proves `active_mailbox_count=1`, exact mailbox id/address/provider, exact actor/gateway/release/source/manifest/planner/trust, writer/importer, `task_enabled=false`, `mailbox_contacted=false`, `uid514_processed=false` and `production_writes=false`.

Authenticated enqueue/claim/attachment/result was exercised in one synthetic transaction using provider UID `imap_uid:515`; the transaction was rolled back. No intake row remained and no vehicle was touched. UID514 remains unfetched/unprocessed.

Anon, service_role, `pdc_email_monitor`, wrong actor, wrong gateway, malformed provider UID and direct control/history SELECT remain denied.

## External adapter and protected dispatch

The sealed `.44` release and `CURRENT` pointer were not modified. The adapter now registers the dynamically loaded sealed `imap_bridge` module in `sys.modules` before execution, fixing the dataclass import path without changing sealed bytes.

Installed protected paths:

- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\active-preflight-authenticated-mailbox-compatibility.py`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\pdc-authenticated-monitor-runtime-adapter.py`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current.ps1`
- `C:\ProgramData\PDCMonitor\Staging\control\bootstrap.ps1`
- `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current-sealed.ps1`

The scheduled task remains Disabled, `LOCAL SERVICE`, Limited run level, and its action is the protected bootstrap. The protected VerifyOnly route is:

`bootstrap.ps1` → hash-anchored `run-current.ps1` → authenticated 674 preflight → adapter 673 anchor → exact sealed `runtime_launcher.py` smoke.

## Exact hashes

- 674 migration: `d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb`
- 675 migration: `8f7b1c260e03d3cfd5f5c4931abb959aa269ce0e1755728313f98c17ebaca2a0`
- 676 migration: `9d1a922c7c4074ff75df7d1ed821872321d33fff6240667b45530e50aba59e4d`
- authenticated mailbox preflight: `0ab027ce023af99e3667431ed3c8b622da6198789f15d81e89835549e54e7f66`
- external adapter: `a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036`
- dispatch runner: `7047cf5bb0c8ababff226a8ccf5e7f52c10d8e5a0958e960ada46c155f373b09`
- dispatch bootstrap: `3903e0d1420fc2c6a93ce5eb5ffbbb8939be692534b9be2ec49d6a289b72f66a`
- sealed `.44` manifest: `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`
- sealed `.44` runner: `52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd`
- sealed launcher: `28ff38c0c78bc5fd255045a4aacaef6d66e7fc317ba1d929768786ed42bcf9fb`

## Remaining credential gate

The protected runtime's same-scope actor JWT is now expired and returns `PGRST303 JWT expired`. It was not refreshed, copied, fabricated or replaced. Refresh the credential within the pdc-emails owner scope, then run:

`C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\run-current.ps1 -InstallRoot C:\ProgramData\PDCMonitor\Staging -VerifyOnly`

Do not enable/start the task, fetch the mailbox, process UID514, mutate vehicles, send email or access Production as part of this handoff.
