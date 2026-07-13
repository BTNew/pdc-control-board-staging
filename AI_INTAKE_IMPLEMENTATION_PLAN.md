# PMB PDC Control Board — AI Email Intake and Workshop Update Plan

## Goal
Add a controlled AI-assisted intake and update system to the existing PMB PDC Control Board. The priority is the secure shared data/backend foundation first; AI must never directly mutate frontend storage, raw database tables, or workflow state outside validated service functions.

## Current-state findings from the repo

### Current project shape
- Main frontend is a static app in `index.html`, `app.js`, `styles.css`, and data fixture files.
- Current operational source of truth is still browser/local static data, with Supabase pilot migrations now present under `supabase/migrations/`.
- Branch for this work: `supabase-pilot`.

### Vehicle data model and storage
- Static baseline comes from `data.js` via `window.VEHICLE_TRACKING_DATA`.
- Operational browser storage keys are defined at the top of `app.js`:
  - `EDITS_KEY`
  - `ADDED_KEY`
  - `PO_TASKS_KEY`
  - `PO_FILES_KEY`
  - `DELETED_KEY`
  - `NAVISION_BACKEND_KEY`
  - `AUTOCARE_RESULTS_KEY`
  - `NAVISION_IMPORT_RESULTS_KEY`
  - `AUDIT_LOG_KEY`
- Local storage wrappers are `loadJson()` and `saveJson()` around `app.js:952`.
- Main build/merge path is `buildVehicleData()` around `app.js:1083`.
- Manual and import-created vehicles are persisted through `saveAddedVehicles()` / `ADDED_KEY`.
- Field edits are persisted through `saveVehicleEdits()` around `app.js:6488`.

### Existing create/update paths
- PD/job-check form path:
  - `findVehicleForPd()`
  - `findNavisionBackEndVehicleForPd()`
  - `ensureVehicleForPd()`
  - `applyPdCheckFormImport()`
- Navision import path:
  - `handleNavisionFileSelect()`
  - `parseNavisionInput()`
  - `buildNavisionImportPlan()`
  - `applyNavisionImportPlan()`
- AutoCare dispatch path:
  - `handleAutocareSelect()`
  - `scanAutocareNotice()`
  - `parseAutocareNoticeText()`
  - `applyAutocareDespatch()`
- General field edit path:
  - `saveVehicleEdits()`
- Delete lifecycle path:
  - `removeVehicle()`
  - `removeVehiclesFromTracker()`
  - deleted records remain reviewable instead of hard-deleting.

### Workflow fields and validation
- PMB stage logic is centralised around `inferredPmbStage()` and related PMB helpers.
- Required work flags are based on `pdcRequirementDefinitions()`, `pdcJobComplete()`, and legacy compatibility flags.
- RFT blockers are centralised in `vehicleRftGateIssues()` around `app.js:563`.
- RFT transfer paths call the existing blocker logic before moving vehicles.
- Current business rule to preserve: required work flags do not automatically allocate a vehicle to a PMB production bay.

### Zebra/QZ printing
- QZ/Zebra config is in `app.js` around `6027`:
  - `QZ_DEFAULT_PRINTER_NAMES = ['BT-Zebra-EricComp', 'dc-01\\BT-Zebra-EricComp', '192.168.0.164']`
  - `ensureQzConnected()`
  - `findZebraPrinterName()`
  - `printRawZpl()`
  - selected vehicle and AutoCare label generation helpers.
- Current printing is browser/QZ based and should remain that way.
- AI/email backend should only request or record label print actions; actual QZ print still occurs in the authorised browser session.

### Audit trail
- Current audit is localStorage-based:
  - `loadAuditLog()`
  - `saveAuditLog()`
  - `recordVehicleAudit()` around `app.js:6446`
- Supabase foundation already added `audit_events` for shared audit history.
- AI/email/voice actions must write to shared `audit_events`, not only localStorage.

## Architecture decision

Use Supabase as the shared data foundation and add a secure backend service layer for email, document extraction, AI interpretation, and workflow mutations.

Recommended implementation route:

1. Supabase Postgres for shared operational data, intake state, mapping rules, audit, label print events, and undo metadata.
2. Supabase Edge Functions or an equivalent secure backend for:
   - Microsoft Graph mailbox polling/webhook handling.
   - Attachment download and text extraction.
   - AI structured extraction.
   - Workshop command interpretation.
   - Validated RPC calls into Postgres.
3. Frontend uses Supabase auth/session and publishable key only.
4. Microsoft Graph secrets, AI keys and database privileged credentials stay only in backend environment variables.

## Stage 1 — Data and API foundation

### Database additions
Add migration `004_ai_intake_foundation.sql` for:
- AI intake configuration.
- Trusted senders/domains.
- Accessory/department mapping rules.
- Email intake records and statuses.
- Email attachment metadata.
- Field-level extraction/source confidence.
- Proposed actions/change sets.
- Workshop natural-language command records.
- Zebra/label print events for duplicate prevention.
- Undo action metadata.
- RLS policies for the new tables.

### Backend/API foundation
Add environment template and API documentation before implementing service code:
- `backend/.env.example`
- `docs/AI_BACKEND_API.md`
- `docs/MICROSOFT_GRAPH_SETUP.md`

Service functions/endpoints should later implement:
- `/api/ai/email/process`
- `/api/ai/email/reprocess`
- `/api/ai/email/approve`
- `/api/ai/email/reject`
- `/api/ai/command/interpret`
- `/api/ai/command/apply`
- vehicle update service functions that call shared validation/RPC.

### Central validation to preserve
- Use existing RFT blocker logic as the source for frontend behaviour, then mirror it in backend RPC/service validation.
- Never allow AI command delete.
- Never allow AI to move ambiguous vehicle matches.
- Never allow AI to bypass RFT blockers or clear stoppages/completions implicitly.

## Stage 2 — Manual AI workshop commands
- Add an `Update a vehicle` box to existing UI.
- Interpret command on backend.
- Return structured proposed actions.
- Show confirmation UI before mutation.
- Apply through controlled functions only.
- Record `workshop_text_ai` or `workshop_voice_ai` audit events.

## Stage 3 — Email inbox connection
- Configure Microsoft Graph access to the dedicated mailbox.
- Store every email as an intake record.
- Download and store attachment metadata and private storage paths.
- Never silently discard an email.
- Treat all email/attachment text as untrusted input.

## Stage 4 — AI extraction and review
- Use strict JSON schema output only.
- Validate schema before applying anything.
- Classify into auto-create, needs-review, duplicate, conflict, failed, ignored.
- Add `AI Intake` review screen with split email preview and extracted/proposed changes.

## Stage 5 — Mapping rules
- Use exact accessory code first, then keyword rules, then semantic fallback.
- Add authorised management screen for mapping rules.
- Keep mappings in database, cached in backend/frontend.

## Stage 6 — AutoCare dispatch arrival
- Detect AutoCare dispatch notices through email intake and current parser rules.
- Match vehicle.
- Set PMB arrival, remove from Yard Hold, land in PMB Unallocated.
- Trigger label print request only if auto-print enabled and no duplicate print exists.

## Stage 7 — Voice updates
- Add browser speech recognition where supported.
- Send transcript through the same command interpretation path as typed text.
- Store transcript in audit.

## Stage 8 — Reporting/questions
- Add read-only command category for reporting queries.
- Query backend/database; do not send full vehicle database to the model.
- Read-only queries must never mutate state.

## Immediate assumptions
- Supabase project is the selected shared backend.
- The final mailbox address is not yet fixed and must remain configurable.
- Microsoft tenant/client ID and client secret are still admin inputs.
- No external customer replies are sent automatically in version 1.
- Existing static/localStorage app remains the manual fallback during rollout.

## Local Outlook bridge pilot
Craig approved using the Outlook account already configured on this PC (`nwmgreception@outlook.com`) as a pilot intake source instead of waiting for Microsoft Graph tenant/admin setup.

Pilot approach:
- Use classic Outlook desktop COM automation from a local backend script.
- Do not store mailbox username/password in code or the website.
- Insert received emails into `ai_email_intake` with `graph_message_id` prefixed as `outlook-com:`.
- Keep attachment copies in ignored local runtime storage.
- Do not directly create/update vehicles from the bridge; downstream validation/review still applies.

Known limitation:
- The new web-based Outlook for Windows does not expose COM automation. If only new Outlook is installed, install/configure classic Outlook desktop or switch back to Microsoft Graph/another inbound mail service.

## Current next step
Get the local Outlook bridge probe working on this PC, then wire the received intake records into the AI extraction/review pipeline. Do not add frontend AI calls until the data/API foundation exists.
