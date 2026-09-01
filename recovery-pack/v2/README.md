# PDC Email AI v2 Recovery Pack

Pack: `pdc-email-ai-v2-recovery-pack-v1`
Target: STAGING only. Production endpoints, credentials and deployment actions are excluded.

This pack is portable source and contract evidence for the isolated v2 shadow
runtime. It does not enable controlled writes. Restore requires the exact source
checkout, the contract files, and separately provisioned authorised connectors.
No Hermes memory, legacy Windows queue, legacy proposal format or copied runtime
state is required.

Required authorised credentials are named, never embedded:

- `PDC_V2_MAILBOX_SECRET` — read-only authorised mailbox transport secret;
- `PDC_V2_STAGING_VIEWER_SECRET` — current-state/readback Viewer secret;
- `PDC_V2_MONITOR_ENROLLMENT_SECRET` — scoped runtime enrollment secret, if the
  deployment gateway requires enrollment;
- `PDC_V2_AI_PROVIDER_SECRET` — approved AI interpretation provider secret.

The pack deliberately has no action-writer secret and no Production secret.
Controlled STAGING writes require a later separately reviewed release and are not
part of this task.

Integrity is checked with `RECOVERY-PACK-MANIFEST.json` and the included
`build_manifest.py`. The manifest excludes itself to avoid self-referential
hashing and records every other pack byte.
