# PMB AI Backend API

This API is the controlled boundary between the PDC Control Board frontend, Microsoft Graph email intake, AI extraction, and vehicle workflow mutations.

The frontend must not call OpenAI, Microsoft Graph, mailbox credentials, service-role database access, or raw table mutation directly.

## Common requirements for all mutation endpoints

Every update endpoint must:

1. Authenticate the user or service.
2. Check the user's PMB role.
3. Validate the request body against a schema.
4. Load the current vehicle and related work/stoppage state.
5. Apply the existing PMB workflow rules.
6. Reject ambiguous vehicle matches.
7. Reject attempts to delete vehicles through AI.
8. Write an audit event with previous and new values.
9. Commit transactionally.
10. Return the updated vehicle/action state.
11. Notify open clients through realtime updates.

Never expose secrets, stack traces, service-role keys, Graph tokens, or private attachment paths in normal user-facing responses.

## Email intake endpoints

### POST `/api/ai/email/process`

Service endpoint for a new Microsoft Graph message or queued reprocessing job.

Input:

```json
{
  "graphMessageId": "",
  "force": false
}
```

Behaviour:

- Fetches the email and attachments from Microsoft Graph.
- Stores/updates `ai_email_intake`.
- Extracts body/attachment text.
- Sends untrusted source text to the AI extraction schema.
- Validates structured JSON.
- Matches existing vehicle candidates server-side before applying anything.
- Creates `ai_proposed_actions` and `ai_extracted_fields`.
- Applies only if confidence/trust/no-conflict rules allow it.
- Otherwise marks `needs_review`.

### POST `/api/ai/email/reprocess`

Input:

```json
{
  "intakeId": "uuid"
}
```

Re-runs text extraction and AI parsing for a stored intake record. Must not create duplicate vehicles/tasks/labels.

### POST `/api/ai/email/approve`

Input:

```json
{
  "intakeId": "uuid",
  "selectedActionIds": ["uuid"],
  "fieldOverrides": {}
}
```

Applies selected proposed changes only after validating vehicle/workflow rules.

### POST `/api/ai/email/reject`

Input:

```json
{
  "intakeId": "uuid",
  "reason": ""
}
```

Marks an intake/proposed changes as rejected/ignored with audit.

## Workshop command endpoints

### POST `/api/ai/command/interpret`

Input:

```json
{
  "source": "workshop_text_ai",
  "instruction": "Key 4821 has finished fabrication and is waiting on driving lights."
}
```

Behaviour:

- Performs deterministic vehicle candidate lookup first.
- Sends only the instruction, relevant mapping rules, and limited candidate vehicles to the model.
- Returns proposed structured actions, validation warnings, blockers, confidence, and whether approval/confirmation is required.
- Does not mutate vehicles.

### POST `/api/ai/command/apply`

Input:

```json
{
  "commandId": "uuid",
  "selectedActionIds": ["uuid"]
}
```

Applies confirmed actions through controlled service functions and writes audit events.

## Vehicle service functions

The backend can expose REST endpoints or internal service functions. They must all use the same validation path:

- `createVehicle`
- `patchVehicle`
- `addTask`
- `completeTask`
- `addStoppage`
- `clearStoppage`
- `arrivePmb`
- `moveVehicle`
- `completeDepartment`
- `reopenDepartment`
- `moveToRft`
- `releaseVehicle`
- `requestPrintLabel`

`moveToRft` must use the central RFT blocker logic and return exact blockers rather than partially completing work.

## Read-only reporting commands

Reporting queries must be classified as read-only and run through database/backend queries. They must never create proposed mutation actions.

Examples:

- vehicles waiting on parts
- vehicles at PMB over 90/150 days
- active stoppages
- ready for transport
- department completions today
- low-confidence imports
