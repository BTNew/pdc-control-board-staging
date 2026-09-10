# PMG transaction commit correction — STAGING

The actual restricted-viewer apply returned SQLSTATE 23514, PDC_NAVISION_VEHICLE_LINK_OR_REFRESH_INCOMPLETE. Its preview accepted 121 Stocks, but the deferred transaction guard found 78 unlinked Navision records for dealer 14450. The PMG resolver had inherited the Revolution-only dealer 37047 filter. Earlier rollback acceptance omitted SET CONSTRAINTS ALL IMMEDIATE and therefore missed this commit failure.

Migration 20260910065753_pmg_stock_navision_commit_fix aligns the PMG resolver with the global Navision identity scope. It detects ambiguous matches across dealers and links a unique current record to the canonical pending vehicle. Existing historical/tombstone/operational protections remain. The Navision parity guard is unchanged. The non-Tune Revolution path retains its original dealer scope.

New previews use pmg_stock_v4 so old preview evidence is immutable. A bound v3 preview without a successful apply returns preview_refresh_required. Successful v3 apply replay and readback remain supported, including the already committed 105-row unidentified partition. The existing preview/apply RPC signatures and restricted caller checks are unchanged.

Navision-linked records use the existing Navision source identity and refresh helper; source_payload retains intake_source_system=tune_pmg and both source digests. The remaining external records retain source_system=tune_pmg. Linking does not activate the board or change pending status, Yard Hold, workshop bookings, completions or assignments.

Full retained-file rollback test passed with SET CONSTRAINTS ALL IMMEDIATE: 121 hidden pending vehicles; 78 current Navision links; 43 Stock-only external records; 1,395 operations and 1,120.68 supplied hours; zero parity mismatches; exact apply replay. All 340 JavaScript regression tests passed. The committed operational import is performed separately by Hermes using the existing restricted identity and task.

Source workbook SHA256: d19014d07e363c16e808b609a353d5968237b1ad19813446606c334e55d49984.
Resolved partition SHA256: 056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814.
Unidentified committed apply: b461c9d3-7b1d-4710-9345-9fe132e77fbe.

Production was not accessed or changed.

