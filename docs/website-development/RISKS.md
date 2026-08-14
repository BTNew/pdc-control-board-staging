# Known website risks

| ID | Severity | Risk | Evidence / impact | Mitigation / owner |
|---|---|---|---|---|
| R-001 | Mitigated | QC phone workflow required wide horizontal matrix navigation. | Final QC override now contains cards through 1100px and keeps desktop actions sticky; isolated Chrome shows zero list overflow at 360–1024. | Residual IA risk: WD-001 and CD-001/002/007/010. |
| R-002 | High | Existing booking move/resize is pointer/spatial first. | `workshop-planner.js:4183-4314`; keyboard/touch parity not browser-proven. | WD-002; Website Lead, backend interface unchanged. |
| R-003 | Medium | Inconsistent dialog focus containment/return. | Vehicle Details is corrected and browser-proven; customer and specialist overlays are not yet standardised. | WD-003 remaining overlays. |
| R-004 | High | Required test matrix is not a single safe local browser gate. | 217 passing tests are mostly unit/source; mobile/roles/state combinations remain unproven. | WD-004. |
| R-005 | Medium | Touch targets are too small outside the corrected Vehicle Locations surface. | QC/Vehicle Locations controls now reach 44px through 1100px; planner/admin and other sampled controls remain. | WD-005 remaining surfaces. |
| R-006 | Medium | Completed workshop history disappears below 1300px. | `workshop-planner.css:1014-1049`. | WD-007; Craig CD-006. |
| R-007 | Medium | Critical identity distinction may depend on truncation/title. | `app.js:2477-2486`, fixed overflow-hidden pills at `styles.css:4507-4522`. | WD-009; Craig CD-002/007. |
| R-008 | Medium | Monolithic frontend increases load and regression cost. | `app.js` 1.16MB; `styles.css` 388KB; many shared selectors. | WD-013/014; coordinate artifact boundaries with Hermes. |
| R-009 | Medium | Browser compatibility is unproven beyond Chrome. | Current rendered tests launch Chrome only. | WD-012; Craig CD-008. |
| R-010 | Medium | Existing operational UI browser regression fails. | Parts “Email sales” row-end assertion failed at 1600px. | Triage before adopting as gate; Website Lead. |
| R-011 | Medium | Offline/freshness meaning can be misunderstood. | Workshop has banners, but not all surfaces show consistent last-confirmed age. | WD-010; Craig CD-009. |
| R-012 | Medium | Native prompt/alert flows produce inconsistent validation/pending UX. | QC and Work & Bookings paths use browser dialogs. | WD-001/003/006; Craig CD-003/010. |
| R-013 | Low | Mobile navigation abbreviations may be unclear. | Below 820px labels collapse to `data-short` tokens. | Include in usability testing under WD-004/011. |
| R-014 | High | Accidental security-boundary edit could couple website work to authority/release work. | `app.js` and `index.html` contain both UI and security/integration bridges. | AGENTS.md, SHARED-FILES.md; Hermes owns protected regions. |
| R-015 | High | Read-only Planner looks editable. | Viewer/read-only rendering can retain drag/mutation affordances even though authority rejects writes. | WD-018; role-rendered browser matrix. |
| R-016 | High | Work & Bookings can remain stale across users. | No detail invalidation/reload is tied to the workshop revision/reconnect lifecycle. | WD-019; use only Hermes-reviewed signals. |
| R-017 | Medium | Offline/terminal-state copy can contradict rendered data. | Copy can claim retained state while rows are hidden/cleared; initial incompatible/offline can remain Loading. | WD-010/018; state browser fixtures. |
| R-018 | Medium | Parallel planner attempts create ambiguous UI outcomes. | No consistent busy latch before protected version/idempotency handling. | WD-002/004; double-click/tap/Enter tests. |
| R-019 | Medium | Planner instructions can contradict active configuration. | Header hardcodes 8am–4pm while runtime/shared hours can differ. | WD-011; render from reviewed configuration. |
| R-020 | High | PMB pill movement is not keyboard/touch equivalent. | Non-focusable draggable article/HTML5 drag path excludes keyboard and is unreliable on touch. | WD-017; Craig CD-010. |
| R-021 | Medium | QC lifecycle save can succeed while local label printing fails. | UI now states that QC is saved/RFT when QZ fails, but no approved retry/acknowledgement policy exists. | CD-004; no rollback is implied. |
| R-022 | Medium | QC regression evidence is Chromium-only and uses local authority fixtures. | Six viewport/layout runs passed, but live role demotion, offline/reconnect, stale events and two-user convergence remain unproven. | WD-004/012; Hermes boundary preserved. |
| R-023 | High | Auth refresh can remove modal-owned application-shell inertness while Vehicle Details remains open. | `pdc-auth.js` owns protected lock/unlock behavior; editing it here would cross the security boundary. Ordinary modal lifecycle passes, but auth-transition isolation is unproven and not claimed. | BCR-001 submitted to Hermes; integrate only a reviewed ownership interface/SHA. |

## Risk acceptance

Only Craig can accept product/usability risk. Hermes must accept security, data, integration and release risk. Website documentation does not waive either approval.
