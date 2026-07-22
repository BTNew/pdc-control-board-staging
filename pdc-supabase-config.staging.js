// PDC Control Board Supabase browser config — STAGING ONLY.
//
// Points exclusively at the staging Supabase project (cdsmnqxtyyoeoznmbidd).
// Safe to commit: contains only the publishable ("anon") key, never a
// service_role key, database password, or Microsoft client secret. This
// file must never be edited to point at the production project
// (vjdtsswhroyguxyfjdkt) or copied over pdc-supabase-config.js.
//
// Enables shared (multi-user) workshop scheduling and the vehicle
// lifecycle (QC complete -> RFT -> Collected) protected RPC path on this
// staging page only. Both flags are independently opt-in and have no
// effect on production, which is not configured with either flag.

window.PDC_SUPABASE_CONFIG = {
  projectRef: 'cdsmnqxtyyoeoznmbidd',
  url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co',
  publishableKey: 'sb_publishable_hJiXYk7aDCGcijf946MX2g_WVDXnQfk',
  auth: {
    mode: 'password',
    provider: 'password',
    redirectTo: window.location.origin + window.location.pathname
  },
  workshop: {
    sharedData: true,
    // Station-first staging entry: the combined all-department planner stays
    // unavailable so opening Workshop cannot initialise every bay group.
    stationRoutes: { combinedPlannerRollback: false }
  },
  vehicleLifecycle: Object.freeze({
    sharedData: true,
    resolverRollbackDirectRead: false,
    resolverAssetVersion: 'stage2b-c1-review-20260718'
  })
};
