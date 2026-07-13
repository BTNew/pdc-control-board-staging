// PDC Control Board Supabase browser config template.
// Copy this file to pdc-supabase-config.js for local testing.
// Do not put Supabase secret keys, service_role keys, database passwords, or Microsoft client secrets here.

window.PDC_SUPABASE_CONFIG = {
  projectRef: 'vjdtsswhroyguxyfjdkt',
  url: 'https://vjdtsswhroyguxyfjdkt.supabase.co',
  publishableKey: 'PASTE_SUPABASE_SB_PUBLISHABLE_KEY_HERE',
  auth: {
    provider: 'azure',
    redirectTo: window.location.origin + window.location.pathname
  }
};
