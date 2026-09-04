# Deployed PDC UI responsive inventory

Generated: 2026-09-04T20:44:17.189627+00:00
Result: PASS WITH FINDINGS

## Scope and containment

- Deployed URL: https://btnew.github.io/pdc-control-board-staging/
- Authoritative deployed SHA: 6fc3cd3f6392ba76c5947f6571d8fd01f4563ffa
- GitHub Pages run: https://github.com/BTNew/pdc-control-board-staging/actions/runs/33909604666 (success/built)
- STAGING Supabase project: cdsmnqxtyyoeoznmbidd
- Production project contacted or mutated: no
- Product code edited/deployed: no
- Outbound email/actions: blocked and not exercised
- Real business mutations: blocked. One exploratory technician-selector probe persisted unexpectedly; it was immediately bounded and fully rolled back. `cleanup-readback.json` proves the previous technician/version metadata, zero residual QA audit/history/recovery rows, zero temporary auth/role rows, and no Production sentinel.

## Programmatically validated totals

- Routes: 35 (23 primary/admin navigation, 12 code-only routes)
- Viewports: 3 — desktop 1440×1000, tablet 768×1024, mobile 390×844
- Clean fresh authenticated route observations/screenshots: 105/105
- Interaction records: JSON 4358; CSV parser 4358; unique stable IDs 4358
- Interaction outcomes: pass 818; fail 0; blocked 3540
- Issues: 5 — High 1, Medium 2, Low 2
- Clean console/network events: {"console": 9, "http-error": 9}; Production requests: 0
- Assets observed: 145

## Deduplicated findings

### UI-001 — Deleted Vehicles cannot load because archived snapshot RPC returns HTTP 405

Severity/category: High / Functional/Network

Reproduction: sign in as an approved STAGING administrator → Admin → Deleted Vehicles → wait for archived snapshot.
Expected: archived data or a valid empty state. Actual: `Could not load Deleted Vehicles — cannot execute SELECT FOR SHARE in a read-only transaction (25006)`; RPC returns 405 at all viewports.
Evidence: `screenshots/desktop/deleted.png` and `console-network-log.json`.

### UI-002 — AI Auditor is visible to administrator but snapshot access is forbidden

Severity/category: Medium / Functional/Access

Reproduction: sign in as an approved STAGING administrator → AI Auditor. Expected: visible route loads or explains/hides its extra authorization gate. Actual: snapshot RPC returns 403 and the view says the current account is not authorised at all viewports.
Evidence: `screenshots/desktop/ai-auditor.png`.

### UI-003 — Narrow operational tables clip/overlap data without a visible horizontal-scroll affordance

Severity/category: Medium / Responsive/Visual

Reproduction: Parts at 390×844; Back End Data at 768×1024. Expected: reflow or a clear horizontal-scroll affordance. Actual: mobile Parts Vehicle/Customer text overlaps/clips; later columns are undiscoverable, and tablet Back End Data ends mid-table without a cue.
Evidence: `screenshots/mobile/parts.png`, `screenshots/tablet/backend.png`.

### UI-004 — Scrollable compact navigation hides most destinations without an affordance

Severity/category: Low / Responsive/UX

The navigation is intentionally horizontally scrollable and the document itself does not overflow, so this is not classified as inaccessible clipping. At 390px only LOC/QC/CB/B4 are initially visible, with no fade, scrollbar, chevron, or menu cue that more destinations are off-canvas.
Evidence: `screenshots/mobile/dashboard.png`, `screenshots/tablet/dashboard.png`.

### UI-005 — Collected Vehicles route retains the wrong top-bar title

Severity/category: Low / Content/Navigation

Reproduction: Admin → Collected Vehicles. Expected global title `Collected Vehicles`; actual global title `Control Board` while the section says `Collected vehicles` at all viewports.
Evidence: `screenshots/desktop/collected.png`.

## Coverage and exact blocked scope

Every reconciled route was rendered after a fresh authenticated navigation at all three viewports. Safe search/filter/sort/tab/disclosure/display/refresh and cancel-only interactions were exercised. Back, forward, reload, fresh-session authentication, keyboard focus probes, clipping, horizontal containment, and touch-target geometry are represented in the machine-readable files.

Mutation, outbound-email, file-upload, destructive, privileged decision, and immediate-persistence selectors were not intentionally exercised and are explicitly `blocked` per stable interaction ID in `interaction-matrix.json/csv` and `summary.json`. State-dependent controls absent from the two-row STAGING dataset are also recorded rather than inferred.

Authoritative artifacts: `sitemap.json`, `interaction-matrix.json`, `interaction-matrix.csv`, `issue-register.json`, `console-network-log.json`, `summary.json`, `cleanup-readback.json`, and `screenshots/**`.
