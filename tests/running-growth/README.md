# Running work growth regression scenarios

These eight SQL files are synthetic database tests. Each requires the owned
`127.0.0.1` / `pdc_restore_check` staging restore, creates its own vehicles,
operations and resources, and rolls back. They must never run against the working
website database or production.

The existing `tools/functional-monitor/run_isolated_workflows.py` runner executes
them with its full suite, preserving original ACLs, disabling copied jobs and
checking cleanup. It requires current function fingerprint evidence to establish
that the copied source matches the working site. Run a focused group with the
runner's existing scenario selection option; do not remove SQL guards.

| File | Assertions |
| --- | --- |
| `category_hoist_started_rollback.sql` | Actual category setter grows running Hoist work and moves planned followers. |
| `category_hoist_stoppage_rollback.sql` | Same path preserves stopped state and actual start. |
| `category_bus_started_rollback.sql` | Actual category setter grows running Mechanical work using its Bus calendar. |
| `category_bus_stoppage_rollback.sql` | Same Bus path preserves stopped state and history. |
| `fitter_extra_rollback.sql` | Actual Hoist item Start/Done adds permitted other-station time; receipt replay never adds it twice. Bus Mechanical, Electrical and whole-job keep their category scope and reject foreign Tint Start/Done without changing work. |
| `protected_chain_rollback.sql` | Genuine started/stopped, technician, Admin, leave and Sublet conflicts remain rejected; planned work cascades through bay, same vehicle and secondary technician; no running allocation shrinks. |
| `management_trigger_rollback.sql` | Actual progress trigger and public helper reconcile trusted system work with explicit system audit and no invented staff actor. |
| `bus_close_rollover_rollback.sql` | Actual Mechanical/Electrical category saves cross their Bus closing time; a separate explicitly labeled private whole-job planner case verifies the same calendar and persistence contract. All cases preserve source/start/scope/history, move the planned follower to working time, and call the real public helper again to reject shortening or double counting. |

The four category cases also return an assigned synthetic reservation through the
canonical return API, then verify its released assignment and retained booking
history remain unchanged during growth. Every test preserves imported source
hours and copied operational bookings. Fixture Start status setup is distinct
from the separate Start-command regressions in the full suite.

These tests do not establish actual browser dragging, touch interaction, external
email delivery, Storage contents or provider integrations. Candidate up/down
installation and post-use inverse checks are release-time checks with private
receipts; the recurring runner does not apply migrations.
