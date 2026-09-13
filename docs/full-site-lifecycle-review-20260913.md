# Lifecycle, QC and Parts review — 13 September 2026

Reviewed staging source based on `288bd699f7adb70a5f6d84614eee7ddbc6a541db`. No real vehicle, booking, QC photo, provider or customer record was changed by this review.

## Confirmed problems and repairs

- **Queued QC checks could run as the next operator.** A behavioral reproduction queued two checklist changes, held the first response, signed out, signed in as another operator, then released the response. Before repair, the second write was dispatched using the replacement operator. QC work now captures its session generation and actor before queuing. Lock/revalidation cancels unsent changes; old responses cannot alter replacement state or clear its pending controls. Same-user revalidation is also covered.
- **Desktop QC photos could start twice or continue after logout.** The busy guard previously started after reading the file, leaving a rapid second selection able to create another upload. It now locks before reading, bounds the read, and checks captured authority before upload and receipt handling. Mobile camera selection, photo preparation, rejection and signoff also discard work from a replaced session.
- **QC signoff could change writer after identity resolution.** The finalization handler now retains the originating authority and service and verifies them after resolving the vehicle, before dispatching finalization.
- **Parts actions could change writer after refresh/identity lookup.** Ordered, received, STOPPAGE, STOPPAGE removal and ETA handlers now retain their originating authority across awaits. Stale responses cannot update another session's ETA, change its filters or offer an old completion email draft. Existing permissions and server receipt/version rules remain in force.
- **RFT actions for different vehicles incorrectly cancelled each other's completion handling.** One global action generation was used as the only request-owner check. Ownership is now tracked separately per vehicle and bound to the originating operator/session. Duplicate actions on one vehicle are still blocked. Logout clears pending ownership, and an older completion cannot release a newer action's lock.

## Verification

`node --test test_*qc*.js test_*parts*.js test_*rft*.js test_vehicle_location_override.js test_operational_closure_411.js` passed **140 tests** in the shared review checkout at the time of this report.

This includes **22 new behavioral scenarios**:

- Nine QC scenarios: different-user queued writes; duplicate photo selection; logout during file reading; ordinary queued version progression; same-user revalidation; old completion versus a newer pending check; signoff identity lookup interruption; mobile photo interruption; mobile rejection error after session replacement.
- Nine Parts scenarios: each of five handlers interrupted during identity lookup; ordered action interrupted during ETA refresh; late ETA receipt after same-user revalidation; normal accepted ETA feedback; late completion unable to offer an email draft.
- Four RFT scenarios: concurrent independent vehicles; duplicate same-vehicle action; logout and old-finally ownership; viewer/locked-session exclusion.

The three initial QC reproductions failed against the prior code and passed after the fixes. Tests exercise extracted deployed handler code with deferred responses and synthetic identities, not alternate implementations.

Existing coverage retained checks for canonical operation identity, deferred PIT, unknown hours/station mapping, QC retest/rework, photo receipt validation, RFT history and transport prerequisites, Parts/JITA independence, STOPPAGE reasons and clearing, and location override without invented completion evidence.

## Independent review of adjacent changes

Reviewed New Vehicles initial approval and operation-update approval, Sublet mutation queue ownership, and the shared Sublet service. New Vehicles preserves the exact request/idempotency key across an uncertain retry; automatic retries remain limited to explicit rolled-back busy responses. UI ownership includes session generation, actor, token and the specific approval request.

Reported two additional Sublet issues to its implementation owner for this same release:

1. A prior session's unresolved queue promise could block the next session's edit of the same booking. Clearing mutation queues during shared-service reset and bounding request duration addresses that wait; old `finally` handlers must retain the existing owner comparison.
2. An accepted Sublet change followed by failed refresh needs a saved-but-not-refreshed message, rather than silently rendering stale status or suggesting nothing was saved.

Final integrated results for those changes are recorded by their owner and the release review.

### Final refresh, search and authority review

Independently reviewed the deferred refresh coordinator, shared-service reset/realtime integration, Perth booking-search date ranges, Yard Hold pipeline count and styles, and final Sublet timeout/receipt paths. The combined related regression run passed **63 tests**. Confirmed Sublet writes followed by failed refresh preserve success and explain the stale display; unknown or timed-out requests do not claim that nothing was saved or retry automatically. Reset detaches prior-session queues so a new operator can proceed before an old reply resolves. A minor version-conflict message that claimed a failed read had loaded current values was reported to the Sublet owner for correction.

The remaining Navision revision callback bypassed the new refresh coalescing. It now uses the same trailing-refresh option as operational vehicle revisions. `test_navision_refresh_backpressure_review_20260913.js` runs the actual callback with the real coordinator: 30 revisions during a held request cause exactly one trailing snapshot, a peak of one active read, and a final snapshot at the latest revision. Detached subscriptions cannot schedule another read. The final refresh subset passed **10 tests**, including this new scenario.

The booking-search label shows both dates when a booking spans several Perth calendar days and one date when it crosses UTC midnight within the same Perth day. Yard Hold waiting remains its own metric and orange legend segment; existing small-screen pipeline behavior is unchanged.

Independently compared all nine location-override migration function definitions against the saved exact originals. Changes consistently use effective location, preserve visibility/lifecycle/role/version/calendar checks and existing ACLs, and extend the ETA-risk trigger without moving booking times. The recorded 25 rollback checks passed, including clearing PMB override to restore source IT ETA risk and applying PMB override to clear it. A read-only comparison found no existing planned-booking risk mismatches requiring a backfill. Migration application and release remain the root agent's responsibility.

## Practical limits

- The live staging QC queue had no vehicle available for a non-mutating end-to-end signoff walkthrough. No real signoff, photo upload, Parts transition, transport booking, email or collection was performed just to test the site.
- Browser/device camera behavior and actual intermittent network conditions are represented by deterministic file-reader and deferred-request tests, not a claim to have tested every phone or network.
- Submitted requests may already have committed when a session ends. The fix cancels unsent work and ignores stale UI callbacks; it does not claim to roll back a server transaction after dispatch. The interruption message directs the user to refresh the saved state.
- Layout colors, compact operation rows, removed per-line Parts text and booking calendar rules were not changed by this patch.
