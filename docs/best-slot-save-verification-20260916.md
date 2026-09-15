# Best slot save repair — 16 September 2026

Best slot searched for a free space but saved through the administrator cascade path. That shifted every later planned job in the chosen bay, even when the new job fitted before them. A displaced vehicle could then overlap its booking in another station and reject the whole transaction.

Best slot now passes a non-cascading creation intent through the scheduling entry point to the existing administrator scheduling RPC. Explicit drag placement retains its cascading behaviour. Permission, version, duration, calendar, vehicle and technician validation are unchanged. Uncertain transport responses replay the same request ID and identical intent.

Validation:
- All 825 JavaScript tests pass, including five new save-path tests.
- Eight staging SQL regression assertions pass in a rolled-back synthetic fixture. The old path reproduces vehicle_overlap; the corrected path books 07:00–09:00 and leaves the following vehicle's 09:00 Fab and 11:00 Fitting bookings unchanged.
- The SQL fixture exercises the scheduling branches called by the administrator RPC. Its website-session authorization guard is unchanged and is not bypassed for SQL testing.
- Assertions confirm pre-existing vehicles and bookings remain unchanged. No operational bookings were made for the reported vehicles.
- No database migration is needed. The existing RPC already supports non-cascading inserts.
