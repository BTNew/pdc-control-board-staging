# Full-width New Vehicles review — 12 September 2026

Craig requested applying his work-category rules to vehicles already awaiting review and showing full operation descriptions with drag-to-station buckets.

The review now uses full-width operation rows. Descriptions wrap without an internal scroll box. Station buckets stay visible above the list; each row also has a station selector for keyboard and touch use. Missing/invalid workshop hours come first. Sublet remains exempt; drafts survive station changes and are saved by the existing approval action.

The staging database projects the owner rules only for pending, hidden, active vehicles with no booking or completion history, and only source lines without staff adjustments. It preserves immutable Tune evidence and positive estimates. Electrical defaults to 1.5 hours only for missing/placeholder zero estimates unless the description specifies another time. Explicit zero and conflicting times still require review. Mine bars and roof-rack whip flags take Electrical precedence. Canopy accessory descriptions are not treated as a canopy purchase merely because they mention a canopy.

The existing approval transaction saves the reviewed choices. No approval, booking, completion, parts update or vehicle movement is performed by applying these rules. Already-approved work is unchanged. The separate parts-feed implementation is outside this release.

Validation: 42 database rule cases; Node regression suite; browser fixture at 1706/1366/1024/600 pixels checking full descriptions, missing-hours order, drag/drop, station selection, retained hour drafts and sticky buckets. Browser tests use synthetic data and perform no backend writes. Database readback verifies source/staff/vehicle/review/booking fingerprints remain unchanged and compares current review projections with the previous function.
