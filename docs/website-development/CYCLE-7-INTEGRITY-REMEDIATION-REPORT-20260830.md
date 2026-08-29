# Cycle-7 PMB integrity remediation report

Date: 2026-08-30
Dashboard: `20260829_202924_3f0b32`
Environment: STAGING only, Supabase project `cdsmnqxtyyoeoznmbidd`
Production: not contacted or changed
Outbound email: not sent
Mailbox flags/high-water: not changed

## Evidence consumed

- Cycle-7 report and JSON supplied by the PMB Auditor.
- Final pdc-emails historical accounting and management summary after the 782 staging head.
- 782 remediation handoff and frozen historical row/manifest boundary.

The frozen Inbox remains exactly 669/669 UIDs, UIDVALIDITY 1, high-water 685 and 2,305 attachments. The final historical accounting remains operationally blocked: 311 no-action, 296 relevant but not canonically processed, 16 canonical fail-closed, 46 review-blocked, zero successful canonical receipts and zero proven Board changes.

## Completed staging remediation

1. Historical observation integrity

   Migrations `20260830180000_783_historical_observation_digest_repair.sql`, `20260830183000_786_cycle7_contract_repair.sql` and `20260830184000_787_cycle7_contract_version_repair.sql` preserve the private 782 base and authenticated-only public wrapper, but store the request digest and per-attachment observation digest in separate fields. The existing immutable 778 observation and receipt contract versions are consistently 778.1. `observation_sha256` is now required and unique. The private base has no authenticated, anonymous or service-role execute grant.

2. Stage-A projection and complete workflow history

   Migration `20260830181000_784_stage_a_integrity_projection.sql` returns workflow events in deterministic `created_at DESC, id` order with a bounded limit of 500 and matching completeness metadata. VIN, top-level Job Card and canonical Sublet booking-instance evidence are projected directly with `confirmed` or `unknown` classification; no inference is performed. Scheduled, actual and recorded booking duration values are exposed separately, with `source_contradiction_review` when they disagree. Physical timestamps and source durations were not rewritten.

3. Planner and intake access

   Migrations `20260830182000_785_narrow_authenticated_contracts.sql`, `20260830183000_786_cycle7_contract_repair.sql` and `20260830184000_787_cycle7_contract_version_repair.sql` add the authenticated, server-owned dealer-scoped planner detail RPC and status-only `get_pdc_email_intake_status(uuid)` RPC. Direct `ai_email_intake` SELECT remains denied. The old unscoped planner-detail browser grant was revoked; the frontend now calls the scoped contract with the staging dealer code. No generic table access or broad grant was added.

4. Existing data-specific checks

   Stock 13017855 now reads Stage-A workflow history `114/114`, complete, with direct VIN and Job Card classified confirmed. Sublet parity for Stock 13080534 matches the email-derived active booking instance. Stock 13000769 remains an evidence-only review: scheduled interval 1,441 minutes, physical actual interval 1 minute and recorded duration 601 minutes. The source is contradictory and no approved deterministic correction rule exists, so no mutation was made.

## Verification evidence

- Live staging ledger head: `20260830184000 / 787_cycle7_contract_version_repair`.
- Live historical observations/receipts: `0 / 0`.
- Live old planner execute: authenticated `false`; scoped planner execute: authenticated `true`, anonymous/service-role `false`.
- Live direct `ai_email_intake` SELECT: `false`; status RPC authenticated execute: `true`, anonymous execute: `false`.
- Live authenticated Administrator browser session: approved, staging project, no page errors, no console errors and no Production-origin requests.
- Live browser route matrix passed for Dashboard/Vehicle Locations, Workflow, Bus 4x4, Tint, Hoist, Fitting, Fabrication, Electrical, Tyre, Parts, Sublet and RFT.
- Live scoped planner positive probe: HTTP 200 with requirements/bookings; wrong-dealer probe: HTTP 200 with `dealer_scope_denied`; old planner endpoint: HTTP 403; direct intake table: HTTP 403.
- Live Stage-A RPC: HTTP 200; Stock 13017855 workflow `114/114`, complete; VIN/Job Card `confirmed`.
- Live Sublet cross-check: 13080534 email active count `1`, Stage-A status `active`.
- Focused historical/security/783-787 Python suite: `24/24` passed.
- Full local website suite: `npm run test` `229 passed, 0 failed, 1 skipped`.
- Full local check: `npm run check` `229 passed, 0 failed, 1 skipped`.
- PostgreSQL parsing: 783 `15` statements, 784 `13`, 785 `16`, 786 `17`, 787 `13`.
- Staging source commit: `13c2f20d6b4d5fb9ceee70a3fa7c8870fcafb70d`.
- Staging integrity workflow for that commit: successful.
- GitHub Pages deployment workflow for that commit: successful.
- Live cache-busted asset readback contains the scoped planner call, Stage-A `workflowLimit`/`subletAuthority`, and staging `dealerCode` marker.

## Remaining evidence-only items/blockers

- Historical canonical Apply was not run. A valid first-run/replay/idempotency receipt requires the exact approved Monitor actor token/runtime binding for `sales@broometoyota.com.au`; that token is not present in this profile. No substitute Administrator credential was used, and no mailbox or outbound-email path was opened.
- The protected Windows monitor task remains deliberately disabled with `LastTaskResult=267014`, `LOCAL SERVICE`, `Limited`, `PT5M`. The installed bootstrap does not accept the required VerifyOnly/StaticOnly parameter and the protected installed runner is not readable by the current user. The candidate `.68` bundle also fails its own canonical-manifest verifier because the local manifest bytes are CRLF rather than the pinned LF serialization. No unverified runtime was installed and no UAC elevation was forced.
- Two natural monitor-success cycles and historical receipt replay remain unproven until the exact protected runtime and Monitor actor credential are restored through the reviewed shim. The task stays fail-closed.
- A separate approved Operator credential was not available in this profile, so the live browser proof is for the approved Administrator actor. The Administrator passed all requested routes; no alternate or unapproved account was used.

## Artifact paths

- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-pmb-auditor-integration-cycle4-20260817\auditor-reports\cycle-7-integrity-audit-20260830.md`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-pmb-auditor-integration-cycle4-20260817\auditor-reports\cycle-7-integrity-audit-20260830.json`
- `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\historical-reconciliation-management-summary.txt`
- `C:\Users\nwmgr\AppData\Local\hermes\profiles\pdc-emails\data\pdc-email-reviewer\historical-inbox\full-historical-pmb-inbox-accounting.json`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\handoffs\PDC-EMAIL-HISTORICAL-RECONCILIATION-782-REMEDIATION-20260830.md`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830180000_783_historical_observation_digest_repair.sql`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830181000_784_stage_a_integrity_projection.sql`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830182000_785_narrow_authenticated_contracts.sql`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830183000_786_cycle7_contract_repair.sql`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\supabase\staging_only\20260830184000_787_cycle7_contract_version_repair.sql`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\tests\test_cycle7_integrity_remediation_contract.py`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\scripts\verify_cycle7_live_browser.py`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\docs\website-development\AUTONOMOUS-CHANGES-LOG.md`
- `C:\Users\nwmgr\HermesWorkspaces\development\pdc-website-development-lead\docs\website-development\SHARED-FILES.md`
