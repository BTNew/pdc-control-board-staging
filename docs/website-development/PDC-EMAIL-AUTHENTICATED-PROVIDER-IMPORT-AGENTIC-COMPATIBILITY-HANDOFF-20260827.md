# PDC Email Monitor .44 — authenticated provider/import/agentic compatibility handoff

Date: 2026-08-27
Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` only.
Production: untouched.

## Applied append-only successors

- `20260828050000` — `684_authenticated_provider_import_agentic_compatibility`
  - SHA-256: `567b756d2b1742e9aa5d1d02451af0c512caa5bd5b3bb54be13bd1af4997fa29`
- `20260828060000` — `685_uid514_exact_attachment_array_guard`
  - SHA-256: `f450ac57f1d195ea2a3540b2d54e0aca44ae20c6896d88fc38062af5e1263a04`

Successors 670–683 and unrelated 714–716 remain preserved. The 685 helper hash after installation is:

- `pdc_monitor_authenticated_uid514_claim_scope_684(text,uuid,uuid,uuid,text,text)`:
  `19eb096013624183f16fc3f78121c34243981473049d0f8c6a579256782c1eab`
- `pdc_monitor_authenticated_uid514_source_scope_684(jsonb)`:
  `7ddd723a5216167dad991e920483f1e0790eee46819e1be8c15e42a173b767af`
- patched compatibility source gate `pdc_agentic_email_source_authorized_502(jsonb)`:
  `d7b4693ce626a62372db91ac777e2c591cd990e43fdd3ecb64acee172f5fa7f1`

## Exact retained UID514 state

- intake: `102e286d-1799-4c97-8e45-e0da9fb31c63`
- provider UID: `imap_uid:514`
- recovery event: `25751401`
- parent/source hash: `440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280`
- mailbox: `12fe383d-5c1e-5801-96e4-f67cf3e3bb57` / `pdc_pmb_email` / `pmbcontroller@gmail.com` / Gmail / Inbox / UIDVALIDITY 1
- actor: `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b` / `sales@broometoyota.com.au`
- JWT role: `authenticated`; server application role: `importer`
- gateway: `pdc-monitor-staging-sales-uid509-v1`
- release: `pdc-monitor-staging-m502-2026.08.44`
- source: `e850c319989d98b45b95a28aa815d78e2c2e3a4b`
- manifest: `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`
- planner: `7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348`
- trust receipt: `e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227`

The existing intake is still `failed` with `queue_attempts=8`; all eight claim attempts remain retained. Authorization count is 1, selection count is 1, attachments count is 7, extracted PDFs count is 4, provider observation count is 0, and Stock `13016925` vehicle count is 0.

## Provider authentication object

Use the exact stored five-key object; do not require DKIM=true:

```json
{"dkim_aligned":false,"dmarc_aligned":true,"gmail_authentication_results":true,"sender_domain":"pmgwa.com.au","spf_aligned":true}
```

Provider service is exactly `mx.google.com`, recipient is `pmbcontroller@gmail.com`, sender is `oleg.borodavkin@pmgwa.com.au`, and the message ID must be read from the retained intake unchanged:

`\r\n <MEYP282MB1430BA116E15298463DA38BFC3DA2@MEYP282MB1430.AUSP282.PROD.OUTLOOK.COM>`

## pdc-emails RPC sequence

1. Refresh/use the pdc-emails owner’s own standard authenticated actor credential. Do not copy a credential from this profile or another owner.
2. Claim the retained intake, preserving prior attempts:

`claim_pdc_uid514_recovery_257(text,integer)`

Arguments: `pdc-monitor-staging-sales-uid509-v1`, `25751401`.

3. Attest only the currently claimed exact Job Card attachment:

`attest_pdc_monitor_provider_email_observation_684(text,uuid,uuid,uuid,text,text,text,text,jsonb)`

Arguments are gateway, claim token, intake UUID, Job Card attachment UUID, exact parent hash, exact Job Card hash, stored exact message ID, `mx.google.com`, and the exact five-key authentication object.

The exact Job Card attachment is:

- UUID `78f14ad0-cff3-40b6-9880-5fcb1f8e635b`
- filename `J139125482 - _13016925.pdf`
- MIME `application/pdf`
- bytes `72551`
- SHA-256 `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`

An identical retry returns `provider_observation_already_attested` with the same observation/request hash. No generic observation RPC remains authenticated-callable.

4. For the exact canonical import wrapper, send the same gateway/claim/intake/attachment/parent/attachment/authentication tuple plus the exact vehicle/work payload:

`import_pdc_monitor_jobcard_attachment_authenticated_684(text,uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)`

- `stock_numbers`: `["13016925"]`
- `job_card_number`: `J139125482`
- `conflicts`: `[]`
- `cancelled`: `false`
- `required_work`: `["fabrication","fitting"]`
- operation lines, in source order:
  - `OP1` `Fill Fuel` `0.00`, `owner_supplied_document`
  - `OP2` `PDI` `0.70`, `owner_supplied_document`
  - `OP3` `HDA Tray` `0.00`, `fabrication`
  - `OP4` `Steel Bull Bar` `5.18`, `fitting`
  - `OP5` `Tow Bar long tongue` `1.58`, `fitting`

The authoritative source total is `7.46` hours. Zeroes are retained. Tow Bar maps to `fitting`. Non-work/unknown evidence remains visibly represented as `owner_supplied_document`. The stale `13.10` expectation is rejected; no `5.64` fabrication or fabricated hours are accepted.

The import wrapper calls the existing claim-bound canonical path and is idempotent through the existing receipt/work-receipt protections. It does not reset or delete prior claim-attempt history.

5. Canonical readback:

`read_pdc_monitor_jobcard_attachment_receipt_authenticated_684(text,uuid,uuid,uuid,text,text,uuid)`

The wrapper proves the same claim, intake, attachment, parent hash and attachment hash before returning the canonical receipt.

## Agentic wrappers

Use the exact source binding from the retained claimed intake. The wrappers are authenticated-only and server-check actor/importer/writer/gateway/release/source/manifest/planner/trust/mailbox/claim/source hashes:

- `read_pdc_agentic_email_context_authenticated_684(jsonb)`
- `record_pdc_agentic_email_plan_authenticated_684(jsonb)`
- `execute_pdc_agentic_email_action_authenticated_684(jsonb)`
- `pdc_agentic_apply_action_authenticated_684(uuid)`
- `finalize_pdc_agentic_email_plan_authenticated_684(jsonb)`

Wrapper source hashes after staging apply:

- context `412fb6835a401ccb0f32aa864aa7a1a67726b22b373d61cfb23434544cf06834`
- plan `4187a2866f1cee6109c50838e6f4492406fa12011206980e74a98d38e2cfbf61`
- action `86132013a747b69d65682522171da94e886ba6b5005a247eedb64f9cc9fbf100`
- apply `488dfda5d354df86a644bd16c68bb316de9c8d2db0364295bb112c8a707f8021`
- finalize `822fbcc7099ba19a6f18f15aa3739920691d29eda0a1603e279fd53987ca1ba5`

Anon, service_role, wrong actor, direct table reads, and legacy provider/import wrapper execution remain denied.

## Safety boundary

Live staging readback after 684/685:

- provider observations: `0`
- intake: `failed`, queue attempts `8`
- authorization: `1`
- selection: `1`
- retained attachments: `7`; extracted PDFs: `4`
- Stock `13016925` vehicles: `0`
- active staging mailboxes: `1` exact PMB test mailbox
- pilot enabled/automatic Job Cards/outbound email: disabled
- task: Disabled under `LOCAL SERVICE`
- task enabled: `false`
- mailbox contacted: `false`
- UID514 processed: `false`
- Production sentinel: absent

The worker did not enable/start the task, contact/fetch the mailbox, process UID514, create a provider observation persistently, create a vehicle, send email, delete/rewrite evidence, or access Production. The live positive/replay tests were transaction-rolled-back rehearsals only.
