# Department 138 workshop routing — staging

Department 138 operations now always use Bus 4×4. Saved station overrides and later description rules previously allowed those operations into Fitting, Electrical, Sublet and other departments.

The canonical operation projection, pending review classifier, board snapshot and source-line editing controls now enforce the same department rule. Source department is retained in website data so a genuine department 139 operation on a mixed vehicle remains at its assigned station. New vehicle and Tune update reviews lock department 138 to Bus 4×4; the database rejects incompatible source-line adjustments.

The applied migration corrected 157 saved station adjustments across 22 active vehicles, recalculated their work requirements, and wrote before/after routing audit events. These vehicles had no workshop bookings. Approved hours, estimate provenance, descriptions, completion and history were checked unchanged. The original approval timestamps are retained because they prove the approved estimate source.

Validation: 1,019 JavaScript tests passed. Rollback database tests exercised 288 category/hour combinations for each department, mixed-source assignments, canonical and board parity, and rejected invalid insert/update/reactivation. Applied staging verification found no department 138 operation outside Bus 4×4. Security advisor findings were unchanged. No operational test fixtures were retained.

Applied migration: 20260916121430_department138_bus_bays.sql.
