# Workshop categories and loading performance — 16 October 2026

The PMG sidebar now provides direct category links: Bus 4×4 Mechanical, Accessories, Electrical, QA and external Pit; PMB Hoist, Fab, Fitting and Electrical; shared Tint and Tyres. Department selection applies on initial entry as well as after changing departments. Each Bus category has a stable address for reload and browser Back. The Control Board shows all physical bays, including Progression bays. Booking forms retain compatible bay overrides. Physical bay IDs and booking rules are unchanged.

On 17 October, the duplicate Bus, PMB and Shared navigation rows and their All 10 bays checkbox were removed from the planners. Use the left menu for category schedules and the Control Board for the full bay overview.

Pit displays outstanding canonical Department 138 inspection lines and opens the existing vehicle detail. It distinguishes loading, unavailable, incomplete and empty data. It refreshes when either source finishes loading or fails. Pit is external work and does not create a physical bay. Activity uses the existing Bus and Departments reporting buckets without changing the database allowlist.

Reference data changes no longer repaint hidden Setup or Dashboard panels or repeatedly read backup status. Visible Setup still updates its reference lists, and losing admin access still clears the privileged panel. The shared planner no longer builds and discards a legacy vehicle list. A full render cancels its duplicate queued render; a clock-only projection preserves pending full work. Data refresh and polling intervals remain unchanged.

A partial index speeds the existing exact import-evidence lookup by batch, stock, job card and source line. Its predicates match the existing insert/unchanged reader; function bodies, hours rules, permissions and operational data are unchanged. Deployment is guarded for the staff-working staging project and rejects an unexpected reader or table definition. It preserves bookings and records the exact migration atomically.

## Validation

- Full Node regression suite, runtime build, syntax and secret checks.
- Route regression tests cover initial department filters, category clicks, reload/Back, shared scope reuse, All 10 bays, external Pit, fitter routing, freshness failures and activity attribution.
- Owned, password-protected loopback restore with outbound facilities disabled: exact before/after JSON equality for 120 catalogue lookups and the entire 434-vehicle board.
- On that restored snapshot, 120 lookups averaged 870 ms before and 77 ms after indexing; the board read took 34.9 seconds before and 17.7 seconds after. These are isolated database measurements, not browser paint timings or a live latency guarantee.
- Browser-code tests cover routing and rendering. Authenticated browser/iPad interaction was unavailable, so it was not verified by actual clicking or dragging.

The restore server stopped and plaintext was removed successfully. A separate experimental category-read rewrite was withheld because a concurrent release added reviewed operation-category precedence. This release preserves that newer logic exactly.
