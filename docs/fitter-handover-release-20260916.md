# Fitter current-job and next-job handover

The fitter screen now uses one full-width current-job sheet on tablet, phone and desktop. Planned jobs are shown in a compact next-job preview and a collapsed later-jobs list rather than a narrow parallel sidebar. Running and stopped work remains the current job; mechanics with more than one active assignment can switch between their active jobs.

The completion control sits after this bay's checklist. Once all required items and notes are saved, Complete & open next job saves the existing canonical completion, reloads the current assigned queue, opens the next job and scrolls to its heading. It does not start that next booking automatically. Remaining stopped/running assignments take priority over future work. Existing planner eligibility, parts, calendar and booking-order rules remain in force.

A rejected completion retains the current job. An uncertain response holds the current screen and can only retry the same receipt. If completion succeeds but loading the next queue fails, completion is clearly confirmed and old job actions stay disabled until refresh recovers. Fresh assignments take precedence over the earlier preview, including reassignment and an empty queue.

Validation: 883 JavaScript tests passed across 294 files, including 10 new handover tests. Isolated browser checks covered portrait iPad (820px), phone (390px), completion-to-next navigation, a separate next-job start, and no horizontal control overflow. No operational jobs were changed for testing. No database changes were needed.

Fitter asset version: 2026.09.16.04.
