'use strict';

/*
 * Stage 2A Realtime diagnostic client -- standalone, outside the main
 * application code.
 *
 * Independent-review remediation. Authenticates as a real staging user
 * via the REST auth endpoint (no browser, no app.js, no
 * workshop-reference-data-service.js), then opens a raw
 * @supabase/supabase-js realtime client subscribed directly to the five
 * Stage 2A tables, and logs every INSERT/UPDATE/DELETE event plus every
 * channel lifecycle transition to stdout with timestamps.
 *
 * This is Method B (independent Realtime client) from the Stage 2A
 * Realtime investigation brief -- deliberately NOT using the app's own
 * client/wrapper code, so it can positively confirm or rule out whether
 * Supabase Realtime is actually delivering postgres_changes events for
 * these five tables at the transport level, independent of any bug in
 * workshop-reference-data-service.js itself.
 *
 * Usage:
 *   node scripts/stage2a_realtime_diagnostic.js
 *
 * Requires PDC_STAGING_SUPABASE_URL, PDC_STAGING_ANON_KEY, and a real
 * staging account email/password (defaults to the administrator test
 * account, overridable via env vars).
 *
 * Runs until Ctrl+C, or for DIAGNOSTIC_DURATION_MS (default 120s) then
 * exits automatically, printing a summary of everything observed.
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.PDC_STAGING_SUPABASE_URL;
const ANON_KEY = process.env.PDC_STAGING_ANON_KEY;
const EMAIL = process.env.PDC_STAGING_DIAGNOSTIC_EMAIL || 'administrator@staging.pdc-workshop.example.com';
const PASSWORD = process.env.PDC_STAGING_DIAGNOSTIC_PASSWORD;
const DURATION_MS = Number(process.env.DIAGNOSTIC_DURATION_MS || 120000);

if (!SUPABASE_URL || !ANON_KEY) {
  console.error('PDC_STAGING_SUPABASE_URL and PDC_STAGING_ANON_KEY must be set.');
  process.exit(1);
}
if (!PASSWORD) {
  console.error('PDC_STAGING_DIAGNOSTIC_PASSWORD must be set (the real password for', EMAIL, ').');
  process.exit(1);
}

const TABLES = ['workshop_technicians', 'salespeople', 'sublet_providers', 'workshop_bays', 'workshop_settings'];

const events = [];
const channelStates = [];

function log(...args) {
  console.log(`[${new Date().toISOString()}]`, ...args);
}

async function main() {
  const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });

  log('Signing in as', EMAIL, '...');
  const { data: authData, error: authError } = await client.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
  if (authError || !authData?.session) {
    console.error('Sign-in failed:', authError);
    process.exit(1);
  }
  log('Signed in. Access token acquired. Role claim:', authData.session.user?.role || '(none)');

  const channels = [];

  for (const table of TABLES) {
    const channel = client
      .channel(`diagnostic-${table}`)
      .on('postgres_changes', { event: '*', schema: 'public', table }, (payload) => {
        const record = {
          table,
          eventType: payload.eventType,
          newId: payload.new?.id ?? null,
          oldId: payload.old?.id ?? null,
          newActive: payload.new?.active ?? payload.new?.is_active ?? null,
          receivedAt: new Date().toISOString(),
        };
        events.push(record);
        log('EVENT', JSON.stringify(record));
      })
      .subscribe((status, err) => {
        const record = { table, status, error: err ? String(err) : null, at: new Date().toISOString() };
        channelStates.push(record);
        log('CHANNEL STATUS', JSON.stringify(record));
      });
    channels.push(channel);
  }

  log(`Subscribed to ${TABLES.length} tables:`, TABLES.join(', '));
  log(`Listening for ${DURATION_MS}ms. Trigger real mutations against staging now (e.g. via curl RPC calls) to observe delivery.`);

  await new Promise((resolve) => setTimeout(resolve, DURATION_MS));

  log('--- SUMMARY ---');
  log(`Total events received: ${events.length}`);
  for (const table of TABLES) {
    const tableEvents = events.filter((e) => e.table === table);
    log(`  ${table}: ${tableEvents.length} events (${tableEvents.map((e) => e.eventType).join(', ') || 'none'})`);
  }
  log('Channel lifecycle transitions:', JSON.stringify(channelStates, null, 2));

  for (const channel of channels) {
    client.removeChannel(channel);
  }
  process.exit(0);
}

main().catch((err) => {
  console.error('Diagnostic client crashed:', err);
  process.exit(1);
});
