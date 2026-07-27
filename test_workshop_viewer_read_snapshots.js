'use strict';
const fs=require('fs');
function assert(v,m){if(!v)throw new Error(m);}
const sql=fs.readFileSync('supabase/staging_only/078_workshop_viewer_read_snapshots.sql','utf8');
for(const name of ['get_workshop_eligibility_snapshot','get_station_workshop_snapshot']) assert(sql.includes(`FUNCTION public.${name}`)||sql.includes(`function public.${name}`),`Missing ${name}`);
assert((sql.match(/require_pdc_role\('viewer'\)/g)||[]).length===2,'Both read snapshots must permit authenticated viewers');
assert(!sql.includes('workshop_require_planner_operator'),'Read snapshots must not require mutation authority');
assert(!/create or replace function public\.(schedule_vehicle_work|move_workshop_booking|start_workshop_work)/i.test(sql),'Viewer migration must not alter mutation RPCs');
assert((sql.match(/revoke all on function public\./g)||[]).length===2,'Both snapshots must remain unavailable to public and anon');
assert((sql.match(/grant execute on function public\./g)||[]).length===2,'Both snapshots must remain executable by authenticated users');
console.log('Workshop viewer read-only snapshot contract passed');
