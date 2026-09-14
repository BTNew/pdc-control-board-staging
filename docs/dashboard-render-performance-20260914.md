# Dashboard rendering and startup cost

The main renderer already limits work to the active route. Direct dashboard callbacks for search, filters and live updates bypassed its temporary parsed-JSON cache, however. Each dashboard redraw could read and parse a vehicle's saved notes 12–19 times. Dashboard grouping also recalculated every vehicle's location once for each displayed location group.

`renderIncomingDashboardBoard` now uses the existing cache for the duration of its synchronous call, including direct callbacks. It reuses an enclosing render's cache and restores it on success or exception. Existing `saveJson` invalidation remains in effect; subsequent renders reread storage. No shared snapshot, authority, freshness or mutation behavior is cached or changed. The renderer groups the filtered rows by location in one pass before producing the same sorted HTML.

The Book all stations helper now redraws only when Vehicle Locations is active. The RFT helper's initial redraw runs on Vehicle Locations, RFT and Collected. Both still install their functions and listeners on every route, so later navigation renders the added controls. All post-write refresh behavior remains unchanged.

## Measurements

Baseline: `BTNew/pdc-control-board-staging` main `cde89dc7775e90804932f2cf12342f24363b1feb`.

The local benchmark executes the full application's actual HTML-generation functions with 102 synthetic vehicles and inert DOM/network boundaries. Four warmups precede 15 measured redraws. These measurements exclude downloading data, browser layout and painting.

| Scenario | Before | After |
| --- | ---: | ---: |
| Saved-note storage reads per redraw | 1,462 | 102 |
| Vehicle location classifications per redraw | 918 | 306 |
| Median redraw, no saved notes | 27.43 ms | 21.84 ms |
| Median redraw, 20 notes per vehicle | 38.71 ms | 30.65 ms |
| Generated HTML | 571,124 bytes | 571,124 bytes |

Generated HTML is byte-for-byte identical in both scenarios; SHA-256 `0f2e99909d8fb6c0c52077ac612a565a17dd98c543bd1065d8da34c1b0911823`. The startup route regression verifies that unrelated routes perform zero hidden dashboard draws and zero unnecessary active-page redraws from these two helpers.

Run `node qa/benchmark-dashboard-render.cjs /path/to/baseline/app.js` to repeat the comparison. Timing varies by machine; read counts, classifications and output parity are the stable checks.

## Validation

Five new full-application regressions cover rendering cost, later-read freshness, invalidation during a render, cache restoration on failure/nesting, route-specific startup and helper installation for later navigation. Forty-three existing focused checks pass for dashboard sorting, operational refresh, delegated refresh clicks, Book all stations, asynchronous RFT ownership and PMB release. Total: 48 passing checks.

Runtime changes: `app.js`, `pdc-book-all-stations.js`, `pdc-rft-actions.js`. Their loader URLs need a fresh version parameter at release. No database changes are required.
