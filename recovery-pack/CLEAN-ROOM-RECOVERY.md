# Clean-room recovery protocol

## Fresh environment requirements

Use a new isolated VM/profile/worktree with no current conversation memory, no copied Hermes cache, no current local pack path and no access to this PC's hidden runtime files. The portable/default path is the hosted transport connector. Supply only:

- the immutable GitHub Recovery Pack release;
- a clean checkout of its recorded source commit;
- explicitly supplied protected STAGING owner/runtime/mailbox credentials through secure environment injection;
- the reviewed hosted transport connector;
- the one reviewed UAC approval only if the explicitly temporary Windows rollback transport is selected and its ProgramData install requires it.

## Procedure

Run exactly:

```text
python bootstrap_recovery.py --pack-root . --source-root source-snapshot --execute
```

The runner must stop at the first missing or failed gate and write only sanitized JSON. It must not invent local state, use a service role as runtime, run a browser business write, manually enqueue/import/activate, invoke OneCycle, force a scheduled task, alter mailbox flags or contact Production. It must use the normal AI planner/model for live interpretation; deterministic code is permitted only for fixtures, regression, validation and fail-safe checks and cannot silently replace the planner.

## Evidence and time target

Capture UTC start/end and elapsed seconds. Target under 30 minutes; hard limit 60 minutes. Record every gate, source/pack commit, release URL, migration head, runtime scope booleans, mailbox UID/digests, Stock/vehicle/Job Card, typed plan/actions/versions, receipts/readback, Board/UI parity, replay/isolation counts, and safety flags.

## PASS criteria

- all required bootstrap and commissioning gates pass;
- hosted transport is proven as the normal replaceable path, or the optional Windows rollback is explicitly marked temporary and rollback-only;
- natural email path only;
- authoritative DB and Board readback match the typed plan;
- every action has conditional evidence evaluation, independent disposition,
  action-level audit and complete planner/model/prompt/ruleset provenance;
- Sublet has explicit permitted evidence and one exact canonical booking/provider
  instance, or is recorded without a write;
- exact replay has zero new effects and zero duplicate receipts/history/drafts;
- unrelated vehicle is unchanged;
- two natural result-0 cycles and required soak evidence are recorded;
- `.68` rollback remains available;
- Production/outbound remain false;
- no secret appears in source, logs, pack, receipts or report.

A clean-room design claim is not PASS. The portability answer becomes YES only
after this evidence exists and no hidden Hermes, Windows-task or local-file
dependency is observed.

## Observed clean-room evidence to date

Published v1.10 was cloned into a fresh isolated checkout with no current pack path or session cache. Pack inspect passed, the self-contained pack test passed 4/4, the private transport asset downloaded and matched SHA-256, and the current source snapshot extracted 1,153 files. The embedded source `npm run test` and `npm run check` each passed 222/0/1.

The `.71` storage-readback/processor repairs and live-head `20260831380000` bootstrap/dispatch/preflight are included in v1.11 as the optional Windows rollback asset. The snapshot is bound to current source commit `dd826dc2…`. Full clean-room PASS and natural email proof are not claimed until protected STAGING owner/mailbox/hosted-transport commands and the approved natural sender lane are explicitly supplied to the clean-room bootstrap.
