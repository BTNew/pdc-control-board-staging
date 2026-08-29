# PDC Monitor staging current-head successor (.68)

Status: implementation ready; migration 766 applied and read back in staging. Production prohibited.

Dashboard: `20260828_191153_4fb787`

## Compatibility basis

- Live staging project: `cdsmnqxtyyoeoznmbidd`
- Live pre-successor head: `20260830040000 / 765_authenticated_exact_claim_floor_640_successor`
- Live successor head: `20260830050000 / 766_monitor_current_head_compatibility`
- Standard authenticated actor: `sales@broometoyota.com.au`
- Gateway: `pdc-monitor-staging-sales-uid509-v1`
- Sealed runtime identity: `pdc-monitor-staging-m502-2026.08.44`
- Canonical claim: `claim_pdc_email_intake_authenticated_exact_732(integer,text)` with floor 640
- Canonical provider observation: `attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)`
- Canonical process: `process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)`

## Artifact

- Bundle: `C:/Users/nwmgr/HermesWorkspaces/pdc-monitor/pdc-monitor-staging-m502-2026.08.68`
- Manifest SHA-256: `f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b`
- Parent `.66` manifest SHA-256: `ba53dfcab96decf9f41fed36aa2ac66a8a3e3be47a2fb621595006075dafa74f`
- Bundle inventory: 3331 files; static verifier passed.

## Reviewed elevated invocation

Run only after the artifact and migration readbacks remain unchanged:

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\nwmgr\HermesWorkspaces\staging-monitor-compat-20260829\scripts\install_pdc_monitor_successor_20260868.ps1" -InstallRoot "C:\ProgramData\PDCMonitor\Staging" -BundleRoot "C:\Users\nwmgr\HermesWorkspaces\pdc-monitor\pdc-monitor-staging-m502-2026.08.68" -ExpectedManifestSha256 "f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b" -ExpectedParentManifestSha256 "ba53dfcab96decf9f41fed36aa2ac66a8a3e3be47a2fb621595006075dafa74f" -ExpectedProcessorSha256 "b7c8ba1c1d3b82b8e95852c2404e33f2520fea99f727d526a5d235b8a549809a" -MachineStoreSource "C:\Users\nwmgr\AppData\Local\hermes\staging-secrets\pdc-monitor-refresh.dpapi"`

The installer requires Administrator elevation, preserves `.44`/`.66`, installs `.68` disabled, and does not enable or start the task. After install the post-approval sequence is VerifyOnly, bounded OneCycle, then PT5M task enablement and two natural-cycle proof.
