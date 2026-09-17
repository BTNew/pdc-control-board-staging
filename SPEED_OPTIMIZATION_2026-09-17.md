# Staging performance update — 17 September 2026

## Changes

- Planner vehicle search fetches booking metadata for up to 25 exact vehicle/dealer pairs in one request. No operation payloads are downloaded for search.
- Inactive New Vehicles pages fetch only pending counts, rather than full review queues every 30 seconds. The active review page still loads its authoritative queues and preserves unsaved review choices.
- Fitter polling combines queue and selected-job reads. Unchanged polls return fresh timing only; commands force a fresh authoritative read. Revision keys include source and station revisions, actor, role, session, technician and selected booking.
- Reconnects compare authorized revisions before re-downloading the full board and Navision records. Revision probes have a five-second bound and fall back to the original full read. Initial Navision rows stay read-only until subscription freshness is verified.
- The four authorized Navision dealer scopes load concurrently, with a shared revision check and stable ordering. Mixed revisions never publish.

## Verification

- Planner batch lookup: 69 transactional database checks passed, including exact booking projection across dates/stations, dealer scope, missing/revoked authorization, malformed input, and unchanged booking rows/versions. Database time in that comparison was 10.64 ms for the batch versus 80.99 ms for 25 existing detail calls; network requests reduce from 25 to 1. These are database timings, not end-to-end page timings.
- Review/fitter database rollback checks passed for queue-count parity, realistic fitter route authorization, command POST-only authority, source/station invalidation, actor/session/technician/selection isolation, and timing-only responses. Temporary test changes were rolled back.
- Existing Start, stoppage, completion, overlap protection and write receipt paths are retained. No operational booking data is changed by these migrations.
- Frontend credential scan: 85 source files, zero privileged credential findings.

- Full JavaScript regression suite: 1,065 passed, zero failed.
- Two warm, read-only database samples: background review badge reads fell from a mean 2,524.56 ms / 605,777 bytes to 0.33 ms / 67 bytes. An unchanged fitter poll (44 item lines) fell from 169.41 ms / 18,937 bytes to 2.52 ms / 534 bytes. Timing excludes network; changed jobs still receive full details.

## Remaining cost

The full board response still expands all operation details: a later warm sample was 6.215 seconds and 10.23 MB for 201 vehicles. This release prevents unnecessary repeat downloads, but does not claim instant initial loading. A proposed query-plan change was discarded after reverse-order testing showed no reliable gain; the original operation calculation and permissions remain intact.

## Deployment

Only the existing staging project and repository are targeted. No paid compute change. Migration filenames match the versions recorded by Supabase.
