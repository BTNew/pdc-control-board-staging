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
