# PDC Email AI v2 isolated runtime and shadow evidence

Status: implemented locally, STAGING shadow only. Controlled operational writes are
not enabled by this runtime.

## Chain

1. `pdc_email_ai_v2_transport.py` is the read-only IMAP transport. It selects
   folders read-only, uses `BODY.PEEK[]`, binds each item to UIDVALIDITY and
   enqueues only a reference to immutable evidence.
2. `pdc_email_ai_successor_intake.py` stores RFC822 bytes and supported
   attachments content-addressed, with exact source/evidence/attachment hashes.
3. `pdc_email_ai_v2_planner.py` consumes complete correspondence, attachment
   children and injected current-state context. It emits the versioned typed
   plan; every body clause and operation line receives an independent
   disposition.
4. `pdc_email_ai_v2_rules.py` contains the versioned Craig rule catalog. It is
   non-destructive and exposes rule id, original instruction, aliases, scope and
   active version.
5. `pdc_email_ai_v2_taxonomy.py` applies narrow precedence. FMG/signage/GVM/GCM/
   Tare decals are review-only; Reflective Stripes require explicit Sublet
   evidence; Long Range/Long Ranger/ARB Frontier tanks are Hoist; fire
   extinguisher hardware is Fabrication and decal-only is review; protection,
   PDI and accessory rules retain their approved destinations.
6. `pdc_email_ai_v2_actions.py` builds the least-authority staging request. The
   enabled `ShadowActionClient` validates but never calls a remote writer.
7. `pdc_email_ai_v2_readback.py` is a pure authoritative-readback and projection
   validator. It binds the projection to staging, vehicle identity and a
   digest; it performs no writes.
8. `pdc_email_ai_v2_runtime.py` composes the chain and can consume the durable
   v2 queue. Queue leases, heartbeat, expiry recovery, checkpoint binding and
   source replay protection remain in `pdc_email_ai_v2_queue.py`.

## Shadow proof

`python scripts/run_pdc_email_ai_v2_shadow.py` runs all 14 safe scenario fixtures
and records `review-evidence/v2-runtime/shadow-campaign-receipt.json`. The receipt
records 14 scenarios, 10 hostile-negative fixtures, per-scenario instruction
accounting and the explicit zero-write flags. The frozen-100 taxonomy comparison
remains in `review-evidence/v2-shadow/pdc_email_ai_v2_shadow_receipt.json`.

No mailbox mutation, Supabase operational write, Production contact, legacy
runtime mutation or outbound email is performed by this lane. Any future
controlled writer must be a separately reviewed implementation using the parent
least-authority contracts; this task does not enable it.

## Recovery Pack

`recovery-pack/v2/` is a portable, secretless pack for this shadow runtime. Its
manifest hashes every pack byte except itself and declares the separately supplied
mailbox, staging Viewer, enrollment and AI-provider secret names. It deliberately
contains no action-writer or Production credential.
