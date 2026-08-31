# Shared-file register

## Modified by the initial assessment

| File | Classification | Change | Coordination |
|---|---|---|---|
| `AGENTS.md` | Repository instruction | Added Website Development Lead and Hermes security boundary because no repository-local AGENTS.md existed. | Do not broaden into release/security instructions without Hermes. |
| `docs/website-development/*` | Website management | Added durable assessment/control record. | Website Development Lead owned. |

During the initial assessment, no application, authentication, Supabase, migration, Realtime authority, workflow, artifact, header, production or deployment file was modified. The later QC reliability tranche modifies only the application/frontend files registered below.

## QC reliability tranche

| File | Backlog / stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `app.js` | WD-001/003/005, QC mobile + general dialog | `incomingWorkChecklistHtml`, Vehicle Locations QC event bindings, `runVehicleLifecycleButtonAction`, `printQualityControlSignoffLabel`, `printRawZpl`, Vehicle Details modal open/close/focus helpers | Existing lifecycle functions, role gates and payloads unchanged. Covered by QC contracts, modal contracts and isolated browser runner. |
| `styles.css` | WD-001/005, QC mobile | Final `QC mobile reliability` cascade for `#incoming-main-board`; desktop sticky action track | Scoped away from workshop planner/workflow. Six Chrome widths. |
| `test_qc_mobile_frontend_reliability.js` | WD-001/005 | Deterministic source/CSS regression | Auto-discovered by `test_all.js`; no package change. |
| `test_vehicle_modal_accessibility.js` | WD-003 | Deterministic dialog lifecycle regression | Auto-discovered by `test_all.js`; no package change. |
| `browser_qc_mobile_reliability.js` | WD-004 | Local synthetic Chrome viewport/keyboard/rerender/print/resource runner | Manual safe runner; portable Playwright/Chrome discovery, binds 127.0.0.1 and installs the same fail-closed non-local blocker on every page before navigation. |
| `docs/website-development/*` | Management | Assessment, backlog, status, test matrix, risks, integration, shared files and Craig decisions | Website Lead owned. |

## High-contention files inspected but not modified

| File | Website interest | Boundary / coordination rule |
|---|---|---|
| `app.js` | QC, Vehicle Locations, Work & Bookings, navigation, dialogs and controls | Shared monolith. Register exact functions/regions before editing; do not alter auth/Supabase/security bridges. |
| `styles.css` | Global responsive layout, production grids, identities and dialogs | Shared global CSS with many override layers. General-interface commit only unless change is strictly QC scoped. |
| `index.html` | Navigation, views and modal shells | Security meta/config order is Hermes-owned. Do not alter CSP or environment/config script order. |
| `workshop-planner.js` | Planner UI and interaction | UI changes allowed; data/RPC/authority semantics are Hermes-owned. Workshop-schedule commit only. |
| `workshop-planner.css` | Planner responsive layout | Workshop-schedule commit only. |
| `workshop-navigation.js` | Work & Bookings/planner navigation and highlight | Frontend contract; coordinate consumers/tests. |
| `workshop-data-service.js` | State displayed by website | Read-only unless Hermes supplies an exact reviewed interface change. |
| `workshop-realtime.js` | Realtime status displayed by website | Realtime authority is Hermes-owned; inspect/test only. |
| `vehicle-lifecycle-actions.js` | QC/PIT action bridge | Hermes-owned integration boundary; do not change independently. |
| `pdc-auth.js`, `pdc-supabase-config.*.js` | Role/config inputs to UI | Hermes-owned; never modify for website work. |
| `package.json`, `.npmignore`, `scripts/verify_npm_pack_inputs.js` | Tests/package exposure | Artifact/release boundary. Changes require Hermes review. |

## Required entry for future changes

For each touched shared file record: backlog ID, commit stream, exact symbols/selectors, reason, tests, Hermes contract SHA if applicable, and collision/integration notes.

## Isolated PDC Email AI transaction successor — 2026-08-31

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `backend/pdc_email_ai_successor_intake.py`, `backend/pdc_email_ai_successor_poller.py` | Separate staging email successor | RFC822/attachment evidence retention and read-only transport fallback only; no PDC logic, Supabase calls or mailbox flag writes | Focused Python tests; poller disabled unless explicitly enabled. |
| `backend/pdc_email_ai_successor_contract.py`, `backend/pdc_email_ai_successor_planner.py`, `backend/pdc_email_ai_successor_runtime.py` | Separate staging email successor | Strict typed plan, complete correspondence/PDF interpretation, taxonomy/version boundary and four-layer composition | Focused Python tests; no browser/localStorage authority. |
| `backend/pdc_email_ai_successor_executor.py`, `supabase/staging_only/20260831300000_pdc_email_ai_transaction_successor.sql` and `20260831320000_pdc_email_ai_transaction_successor_contract_repair.sql` | Separate staging email successor | One typed command RPC, fixed canonical dispatch, immutable receipts, full source graph/version preflight, RLS/grants and independent Board readback | SQL/Python contract tests; live original apply and forward repair readback passed; no runtime identity provisioned. |
| `backend/pdc_email_ai_successor_acceptance.py`, `scripts/run_pdc_email_ai_successor_acceptance.py` | Separate staging acceptance | Synthetic atomic/replay/partial/isolation/disable rehearsal | CLI output records `ok=true`, no Production writes and no outbound email. |
| `scripts/apply_pdc_email_ai_successor_staging.py`, `scripts/verify_pdc_email_ai_successor_staging.py`, `scripts/apply_pdc_email_ai_successor_contract_repair_staging.py` | STAGING installation/readback | Exact protected connector, live-head guard, append-only forward repair, catalog/function/ACL/forced-RLS readback, Production exclusion | Original apply and current-head forward repair/read-only verifier passed; no runtime identity provisioned, no mailbox/task/outbound/UID514 activity. |
| `pdc-email-ai-successor-inbox.js`, `pdc-email-ai-successor-inbox.css`, `staging.html` | Successor STAGING AI Intake UI | Chronological parent email rows, separate vehicle/action children, safe typed details, refresh and Realtime revision lifecycle; legacy `.68` panel retained hidden | Client/render/controller tests; staging-only Supabase endpoint and no mutation controls. |
| `supabase/staging_only/20260831330000_pdc_email_ai_successor_inbox_read_projection.sql`, `scripts/apply_pdc_email_ai_successor_inbox_staging.py` | Successor STAGING read projection | Typed-plan persistence, authenticated paginated inbox RPC, exact source/attachment/action/readback projection, forced RLS and Realtime revision publication | SQL parse/contract tests; live ledger/RPC/ACL/RLS/publication readback passed. |
| `supabase/staging_only/20260831340000_pdc_email_ai_successor_command_read_hardening.sql` | Successor STAGING command/read hardening | Database identity-to-vehicle binding, confirmed=true, safe legacy plan projection and v2 composite-cursor/read-status contract | Migration 3400 applied/read back; identity/confirmation/composite cursor/RECEIVED_WAITING markers proven; no receipts/mutations. |
| `scripts/verify_pdc_email_ai_successor_inbox_staging.py` | Successor STAGING read verification | Read-only v2 RPC/migration/typed-plan/Realtime/ACL/RLS/receipt-count/Production-sentinel proof | Live verifier returned `ok=true`; no runtime identity or transaction/action receipt provisioned. |
| `docs/PDC-EMAIL-AI-TRANSACTION-SUCCESSOR-PLAN.md`, `docs/PDC-EMAIL-AI-TRANSACTION-SUCCESSOR-RUNBOOK.md`, `runtime/pdc-email-ai-successor-manifest.json` | Management/recovery | Current/proposed map, versions, fault matrix, install/recovery/rollback and residual staging gates | Dashboard association `20260831_095314_64feeb`; current repair lane remains separate. |
