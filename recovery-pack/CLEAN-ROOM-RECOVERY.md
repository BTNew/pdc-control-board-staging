# Clean-room recovery protocol

## Fresh environment requirements

Use a new isolated VM/profile/worktree with no current conversation memory, no copied Hermes cache, no current local pack path and no access to this PC's hidden runtime files. Supply only:

- the immutable GitHub Recovery Pack release;
- a clean checkout of its recorded source commit;
- explicitly supplied protected STAGING owner/runtime/mailbox credentials through secure environment injection;
- the one reviewed UAC approval when the protected `.69` ProgramData install requires it.

## Procedure

Run exactly:

```text
python bootstrap_recovery.py --pack-root . --source-root source-snapshot --execute
```

The runner must stop at the first missing or failed gate and write only sanitized JSON. It must not invent local state, use a service role as runtime, run a browser business write, manually enqueue/import/activate, invoke OneCycle, force a scheduled task, alter mailbox flags or contact Production.

## Evidence and time target

Capture UTC start/end and elapsed seconds. Target under 30 minutes; hard limit 60 minutes. Record every gate, source/pack commit, release URL, migration head, runtime scope booleans, mailbox UID/digests, Stock/vehicle/Job Card, typed plan/actions/versions, receipts/readback, Board/UI parity, replay/isolation counts, and safety flags.

## PASS criteria

- all ten gates pass;
- natural email path only;
- authoritative DB and Board readback match the typed plan;
- exact replay has zero new effects and zero duplicate receipts/history/drafts;
- unrelated vehicle is unchanged;
- two natural result-0 cycles and required soak evidence are recorded;
- `.68` rollback remains available;
- Production/outbound remain false;
- no secret appears in source, logs, pack, receipts or report.

A clean-room design claim is not PASS. The portability answer becomes YES only after this evidence exists.

## Observed clean-room evidence to date

Published v1.7 was cloned into a fresh isolated checkout with no current pack path or session cache. Pack inspect passed, the self-contained pack test passed 3/3, the private `.69` transport asset downloaded and matched SHA-256, and the embedded source snapshot extracted 1,152 files. The embedded source `npm run test` and `npm run check` each passed 222/0/1.

The newer successor activation/provisioning tests are not embedded in the `3cea2add…` source snapshot; they remain covered in the authoritative successor source branch. Full ten-gate clean-room PASS and natural email proof are not claimed until protected STAGING owner/mailbox commands and the approved natural sender lane are explicitly supplied to the clean-room bootstrap.
