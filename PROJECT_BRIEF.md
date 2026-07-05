# PDC Control Board Project Brief

## Purpose
A static GitHub Pages vehicle tracking board for Broome Toyota PDC workflows. The site gives the team a shared visual control board for Navision imports, Yard Hold, PMB work streams, Parts follow-up, bay work and RFT readiness.

## Current operating rules
- Navision import data drives the main vehicle tracker up to Yard Hold.
- Manual Yard Hold / PMB / RFT overrides take priority over imported status.
- Vehicles transferred to PMB must land in Unallocated first.
- Job ticks must not automatically allocate vehicles into PMB production buckets.
- PMB production allocation is manual by `pmbStage`.
- RFT should stay gated until required jobs, including Parts, are complete.

## Visual management direction
The board follows service-management and lean visual-control principles:
- Show exceptions first: stoppages, blockers, overdue/aged items and RFT gate issues.
- Keep each department page focused on the decisions that department can act on.
- Avoid showing unrelated notes or fields on role-specific pages.
- Keep high-frequency actions close to the status and blocker information.
- Preserve a single source of truth in local browser data with backup/export controls.

## Role-focused pages
- Control Board: daily vehicle overview, Fix First exceptions and bulk movement controls.
- PMB Workflow: manual PMB stage allocation and WIP visibility.
- PMB bay views: station-specific bay assignment, planned hours, assignee and completion.
- Parts: parts status, ETA/age, stoppages/blockers and parts actions only.
- Reports/supporting views: PDC lists, backups and supporting operational exports.

## Safety constraints
This is a static localStorage app. Do not add external trackers, hidden network calls, credentials, analytics, destructive data handling, or workflow changes without explicit approval.
