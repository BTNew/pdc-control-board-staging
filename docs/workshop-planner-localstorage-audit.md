# Workshop Planner localStorage audit

Date: 2026-07-16

## Scope

This audit covers the current Workshop Planner storage surface in `workshop-planner.js` and the supporting `app.js` keys that materially affect workshop planning, bookings, bay setup, mechanics, assignees, audit identity, and vehicle-side planner state.

## Summary

The current Workshop Planner is **not** a shared multi-user controller. Operational planner state is split across browser `localStorage` keys plus planner-related vehicle fields saved into the broader `EDITS_KEY` local edit store.

Authoritative operational planner data currently lives in browser storage in these areas:

1. booking rows in `WORKSHOP_PLAN_STORAGE_KEY`
2. bay → mechanic/provider defaults in `WORKSHOP_BAY_SETUP_STORAGE_KEY`
3. planner view state in `WORKSHOP_VIEW_STORAGE_KEY`
4. mechanic/provider master lists in `MECHANICS_KEY` and `SUBLET_PROVIDERS_KEY`
5. operator identity fallback in `OPERATOR_NAME_KEY` / `OPERATOR_ROLE_KEY`
6. vehicle-side workshop metadata embedded inside `EDITS_KEY`
7. local audit trail entries in `AUDIT_LOG_KEY`

This is unsuitable for shared workshop control because conflict enforcement, history, assignee allocation, and live-status changes can all diverge between browsers.

## Planner-specific keys

### 1) `WORKSHOP_PLAN_STORAGE_KEY`
- Key: `vehicleTrackingCoreWorkshopPlan:v1`
- File: `workshop-planner.js:3`
- Loaded at: `workshop-planner.js:232-237`
- Saved at: `workshop-planner.js:239-247`
- Included in CRM backup: `workshop-planner.js:14-18`

#### Purpose
Stores the workshop booking rows themselves.

#### Current stored row shape
Observed from scheduling/move/start/stop/complete logic:
- `id`
- `vehicleKey`
- `stage`
- `bay`
- `startAt`
- `hours`
- `assignee`
- `status` (`planned`, `started`, `stoppage`, `completed`)
- `createdAt`
- `updatedAt`
- optional runtime/history fields such as:
  - `startedAt`
  - `completedAt`
  - `actualHours`
  - `stoppageReason`
  - `stoppageAt`
  - `stoppageMinutes`
  - `resumedAt`

#### What it currently controls
- planned bookings
- live started jobs
- stoppages
- completed booking history
- duration and assignee on planner cards
- bay occupancy/conflict checks
- queue-shifting / rescheduling behavior

#### Why it must move server-side
This is the current operational source of truth for workshop bookings.

---

### 2) `WORKSHOP_BAY_SETUP_STORAGE_KEY`
- Key: `vehicleTrackingCoreWorkshopBaySetup:v1`
- File: `workshop-planner.js:5`
- Loaded at: `workshop-planner.js:331-333`
- Saved at: `workshop-planner.js:336-338`
- Included in CRM backup: `workshop-planner.js:17-18`

#### Purpose
Stores stage/bay default assignee mapping.

#### Current logical shape
Object keyed by:
- `${stage}:${bay}`

Value:
- mechanic/provider display name

#### Example logical entries
- `HOIST:1 -> Daniel Evelyn`
- `FABRICATION:4 -> <technician>`
- `SUBLET:1 -> <provider>`

#### What it currently controls
- default mechanic/provider dropdown selection
- per-bay planner assignment defaults

#### Why it must move server-side
This is shared operational reference data, not a personal preference.

---

### 3) `WORKSHOP_VIEW_STORAGE_KEY`
- Key: `vehicleTrackingCoreWorkshopView:v1`
- File: `workshop-planner.js:4`
- Loaded at: `workshop-planner.js:457-466`
- Saved at: `workshop-planner.js:469`
- Cross-tab listener references it at: `workshop-planner.js:2628`

#### Purpose
Stores the planner display state.

#### Current logical shape
- `date`
- `stage`

#### Classification
This is the only clearly harmless Workshop Planner browser preference at present.

#### Allowed future local-only use
Yes — may remain browser-local as a personal display preference.

---

## Supporting shared-reference keys used by Workshop Planner

### 4) `MECHANICS_KEY`
- Key: `vehicleTrackingCorePdcMechanics:v1`
- File: `app.js:12`
- Used at: `app.js:1287-1300`

#### Purpose
Stores the workshop technician master list used by planner assignment dropdowns.

#### Classification
Shared operational reference data.

#### Must migrate?
Yes.

---

### 5) `MECHANICS_ROSTER_SEED_KEY`
- Key: `vehicleTrackingCorePdcMechanicsRosterSeed:v1`
- File: `app.js:13`
- Used at: `app.js:1289-1293`

#### Purpose
Tracks whether the browser-local default mechanic seed has been applied.

#### Classification
Local bootstrap metadata for the old static model.

#### Must migrate?
No as operational data, but it should disappear once mechanics come from Supabase.

---

### 6) `SUBLET_PROVIDERS_KEY`
- Key: `vehicleTrackingCorePdcSubletProviders:v1`
- File: `app.js:15`
- Used at: `app.js:1398-1412`

#### Purpose
Stores the sublet provider master list used by the planner's Sublet row.

#### Classification
Shared operational reference data.

#### Must migrate?
Yes.

---

### 7) `SUBLET_PROVIDERS_SEED_KEY`
- Key: `vehicleTrackingCorePdcSubletProvidersSeed:v2`
- File: `app.js:16`
- Used at: `app.js:1400-1404`

#### Purpose
Tracks whether provider seed data was written into a browser profile.

#### Classification
Local bootstrap metadata only.

#### Must migrate?
No as operational data, but it should disappear once providers come from Supabase.

---

## Identity and audit-related keys currently affecting planner mutations

### 8) `OPERATOR_NAME_KEY`
- Key: `vehicleTrackingCoreCurrentOperator:v1`
- File: `app.js:10`
- Planner fallback read at: `workshop-planner.js:250-258`

### 9) `OPERATOR_ROLE_KEY`
- Key: `vehicleTrackingCoreCurrentOperatorRole:v1`
- File: `app.js:11`
- Planner fallback read at: `workshop-planner.js:250-258`

#### Purpose
Provides mutable local identity fallback when `window.PDC_AUTH_CONTEXT` is absent.

#### Classification
Operational identity fallback.

#### Must migrate?
Yes. Planner writes must use authenticated Supabase user identity only.

---

### 10) `AUDIT_LOG_KEY`
- Key: `vehicleTrackingCoreNavisionOnlyAuditLog:v1`
- File: `app.js:9`
- Planner transactions include it at multiple mutation points, including:
  - `workshop-planner.js:264-271`
  - `workshop-planner.js:275-282`
  - app-side PMB/workshop actions at `app.js:3156`, `5852`, `6044`, `6223`, `8777`

#### Purpose
Stores local audit/history events for workshop-related updates.

#### Classification
Shared operational audit data.

#### Must migrate?
Yes.

---

## Vehicle edit store that currently carries workshop state

### 11) `EDITS_KEY`
- Key: `vehicleTrackingCoreNavisionOnlyEdits:v1`
- File: `app.js:3`
- Loader: `app.js:1214`
- Planner transactions include it via app-side workflows and `workshopPersistVehiclePlanAction`

#### Purpose
Stores broader per-vehicle operational overrides. The planner currently relies on this for workshop metadata stored on vehicles, including fields such as:
- `pmbStage`
- `pmbBayStage`
- `pmbBayNumber`
- `pmbBayScheduledStartAt`
- `pmbBayEstimatedHours`
- `pmbBayMechanic`
- `pmbSubletProvider`
- `pdcWorkshopBlocked`
- `pdcWorkshopBlockPlanId`
- `pdcWorkshopBlockReason`
- `pdcWorkshopBlockedAt`
- `pdcWorkshopBlockedBy`
- `pdcWorkshopBlockClearedAt`
- `pdcWorkshopBlockClearedBy`
- `workshopEstimatedHoursByStage`
- `workshopAdditionalHoursByStage`
- `workshopJobLineAssignments`

#### Classification
Shared operational state.

#### Must migrate?
Yes.

---

## Neighboring operational keys that interact with workshop workflows

These are not planner-authoritative booking stores, but they intersect with workshop lifecycle and should be accounted for during migration planning:

- `ADDED_KEY` — active manually promoted vehicles
- `PO_TASKS_KEY` — parsed PO/job task rows used to derive workshop job lines
- `PO_FILES_KEY` — parsed PO file payloads
- `DELETED_KEY` — deleted vehicle list
- `AUTOCARE_RESULTS_KEY` — import result state
- `NAVISION_IMPORT_RESULTS_KEY` — import result state
- `EMAIL_REVIEW_DECISIONS_KEY` — reviewed email decisions
- `AI_FILE_ASSISTANT_REVIEWS_KEY` — AI file review drafts
- `OPERATIONAL_HEALTH_KEY` — UI-side operational health summary

These do not all need to move in the same commit as Workshop Planner, but workshop migration must preserve compatibility with vehicle promotion/import and audit flows that currently feed the planner.

## Current architecture issues caused by localStorage authority

1. **No true shared state**
   - each browser can hold a different booking set
2. **Client-side conflict enforcement only**
   - overlaps are blocked only by browser logic
3. **Concurrent users can diverge**
   - stale-tab checks compare `updatedAt` inside one browser snapshot model, not a server lock/version contract
4. **Audit is local, not authoritative**
   - browser-local audit history is not a trustworthy operational log
5. **Reference lists are fragmented**
   - mechanics/providers/bay defaults can differ by PC
6. **Identity is partially local**
   - fallback operator identity can be set per browser profile

## Allowed future local-only preferences

After migration, browser storage may remain only for harmless personal display preferences, such as:
- selected planner date
- selected planner stage tab
- collapsed/expanded UI sections
- local column widths/order
- printer preference

It must not remain authoritative for:
- bookings
- booking status
- technician assignment
- bay defaults
- workshop history/audit
- shared mechanics/providers reference data
- conflict enforcement
- booking durations or actual hours

## Required migration outcome

The operational Workshop Planner source of truth must move from:
- `WORKSHOP_PLAN_STORAGE_KEY`
- `WORKSHOP_BAY_SETUP_STORAGE_KEY`
- `MECHANICS_KEY`
- `SUBLET_PROVIDERS_KEY`
- vehicle workshop fields in `EDITS_KEY`
- local audit in `AUDIT_LOG_KEY`

to Supabase/PostgreSQL tables and RPC-backed mutation paths with realtime fanout.