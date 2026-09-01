# PDC Email AI v2 environment requirements

The following names are required by an authorised deployment environment. Values
must be supplied through its protected secret store and must never be placed in
this pack or printed in receipts.

- `PDC_V2_TYPED_COMMISSIONING_CONNECTOR` — protected absolute executable path,
  only for a separately approved commissioning run;
- `PDC_V2_MAILBOX_SECRET` — protected mailbox credential for a separately approved transport run;
- `PDC_V2_STAGING_VIEWER_SECRET`
- `PDC_V2_MONITOR_ENROLLMENT_SECRET` (only when gateway enrollment requires it)
- `PDC_V2_AI_PROVIDER_SECRET`

Non-secret configuration is bound to `staging`, the approved hosted mailbox
transport, the v2 contract versions and the shadow mode. Production URLs,
service-role keys, administrator keys and arbitrary SQL access are explicitly
unsupported. A missing secret is a provisioning blocker; it is not a reason to
substitute another profile or privileged identity.
