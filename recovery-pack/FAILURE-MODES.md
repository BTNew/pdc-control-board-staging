# Known failure modes and repairs

## Hosted transport and temporary Windows rollback

Hosted/server-side transport is the preferred, replaceable evidence transport.
The Windows `.68/.69/.71` lineage is temporary rollback-only and must not be
selected as an implicit fallback or make any planner/business decision. A
transport replacement must preserve source/attachment digests, receipt identity,
action keys and all independent version fields.

If the hosted connector is unavailable, record a typed transport failure and
stop or use the explicitly approved temporary Windows rollback lane. Do not
silently switch transport, planner, taxonomy or business rules.

## Planner/model outage and deterministic boundary

The AI planner/model is the normal live interpretation engine. Deterministic
logic is allowed only for fixtures, regression, contract validation and explicit
fail-safe checks. An unavailable/failed planner becomes
`FAILED_QUEUED_RETRY`, quarantine or `BLOCKED_EXACT_REASON` with provenance; it
must never silently invoke deterministic live interpretation.

## Conditional evidence and independent actions

Job Card and attachment gates are action-specific. A missing artifact blocks only
the action whose matrix row requires it. Sublet additionally requires explicit
Job Card `SUBLET` or explicit staff/provider/booking evidence and one exact
canonical booking/provider instance; generic wording cannot create or move a
booking. Each action retains its own disposition, audit event, provenance and
readback, and a mixed-result plan is `PARTIAL_FAILURE`.

## Windows ACL representation

The installer grants `S-1-5-19` read/execute with `(OI)(CI)(RX)`, but `icacls` commonly renders that as `NT AUTHORITY\\LOCAL SERVICE:(OI)(CI)(RX)`. The verifier must accept both representations and must not reset inheritance, grant write access or weaken protected ACLs.

## Protected ProgramData readback

The `.69` ProgramData release is intentionally unreadable non-elevated. A standard user may see Access Denied even when the installation is correct. Elevated verification must read the successful immutable installer receipt, exact manifest/trust hashes, inventory and ACL. Do not infer failure from a non-elevated read.

## UAC and receipt ordering

The `.69` installer is separate from activation. Never relaunch the installer during activation. The enable-only launcher validates the successful receipt, then requests one Administrator UAC elevation. A canceled/redundant launch may overwrite a current receipt; the authoritative successful receipt is restored only by the protected owner procedure and must be hash/JSON validated.

## Elevated Python resolution

A bare `python.exe` may resolve in the normal shell but fail in an elevated child. Use the reviewed absolute interpreter path and fail with an explicit missing-runtime code. Do not place credentials in command arguments.

## Task registration

The exact task identity is `LOCAL SERVICE`, `ServiceAccount`, `Limited`, `PT5M`. Activation may call `Enable-ScheduledTask` only after all gates pass. It must never call `Start-ScheduledTask`, `schtasks /Run`, OneCycle or a forced run.

## Service-role boundary

`PDC_STAGING_SERVICE_ROLE_KEY` exists only in protected owner provisioning. It must never enter the runtime, source, logs, receipts or pack. Runtime uses only the dedicated authenticated identity and approved RPC execute grants.

## Mailbox failure

Mailbox sender credentials belong to `pdc-emails`. Do not copy them into the website-development profile. Missing sender command, UIDVALIDITY, high-water mark or enrollment proof fails closed. No manual import, enqueue, activation, flag manipulation, OneCycle or browser write is an acceptable substitute.

## Storage eventual consistency

The `.69` transport retries only the exact authenticated Storage `HTTP 400 / NoSuchKey / statusCode 404 / Object not found` response with bounded delays. Near-miss errors, exhausted retries and byte/size/hash/MIME mismatch quarantine or fail closed.

## Replay and partial failure

Stable mailbox/message/source/vehicle/action keys and immutable receipts make exact replay produce zero duplicate effects. Every requested instruction remains represented. One failing action makes the plan `PARTIAL_FAILURE`; unrelated vehicles continue safely.

## Clean-room portability

A pack path on this PC, hidden Hermes memory, an old session, an undocumented local file or an untracked ACL repair is not a dependency. The clean-room must clone the exact immutable source release, provide protected credentials explicitly and produce a complete sanitized evidence report.
