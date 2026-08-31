# PDC Email Monitor — staging commissioning final handoff

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Dashboard association: `20260828_191153_4fb787`
Production: not contacted or modified

## Outcome

The exact authenticated monitor enqueue path now handles non-enrolled or unapproved senders as a deterministic immutable `review_queued` receipt and returns success to the cycle. It does not enroll senders, create an intake row, mutate the Board, change mailbox flags, send outbound email, or write Production. Approved enrolled senders retain the exact active authenticated adapter.

## Applied append-only successors

- `20260831210000 / 855_deterministic_inbound_sender_eligibility_successor`: immutable forced-RLS receipt table; deterministic receipt key and `ON CONFLICT DO NOTHING`; `pdc_monitor_sender_not_enrolled` returns `ok=true`, `review_queued`, `idempotent=true`.
- `20260831220000 / 856_active_scope_enabled_pilot_compatibility_successor`: aligns the stale 839 scope predicate with the already enabled supervised staging pilot.
- `20260831230000 / 857_attachment_claim_839_scope_compatibility_successor`: repairs the stale 674 attachment-claim scope check to exact 839.
- `20260831240000 / 858_runtime_authority_839_scope_compatibility_successor`: repairs the stale 502 runtime-authority helper to exact 839.

## Verification evidence

- Focused contracts: 7/7 passed for 855–857; Python syntax passed; SQL sources are append-only with predecessor guards.
- Live staging heads/readbacks: 855, 856, 857 and 858 applied successfully; Production sentinel absent; exact staging target confirmed.
- Protected VerifyOnly: exit 0 / `ok=true`; mailbox false; UID514 false; Production false.
- Protected bounded OneCycle while Scheduled Task remained disabled: exit 0 / `ok=true`; mailbox contacted read-only; UID514 false; Production false; processor `seen=0`, `failed=0`.
- Live non-enrolled replay probe: two identical calls returned the same receipt ID and receipt key, `ok=true`, `code=pdc_monitor_sender_not_enrolled`, `disposition=review_queued`, `board_mutations=0`, `mailbox_flags_changed=false`, `production_writes=false`; authoritative receipt table count `1/1` safe rows.
- Authoritative Board readback: `navision_board_activations=7` before/after commissioning probe.
- Natural enabled PT5M cycles: two distinct runs, both `LastTaskResult=0`, `PDC_MONITOR_766_CYCLE_COMPLETE`, processor `ok=true`, `failed=0`, mailbox contacted true, UID514 false, Production false. First cycle saw 0; second saw 5 and processed 5 as review with 0 failures.
- Final task shape: enabled, `LOCAL SERVICE`, `ServiceAccount`, `Limited`, `PT5M`; outbound email disabled; mailbox flags unchanged.

No UAC was launched. No Production remote, branch, data or credential was used.
