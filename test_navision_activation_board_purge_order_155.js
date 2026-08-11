'use strict';const assert=require('assert');const fs=require('fs');const sql=fs.readFileSync('supabase/staging_only/155_navision_activation_board_purge_order.sql','utf8');
for(const token of ['purge_vehicle_from_board_pre155','where canonical_vehicle_id=p_vehicle_id and active','navision_activation_board_purge_order','staging_migration_155'])assert(sql.includes(token),`Migration155 missing ${token}`);
assert(sql.indexOf('purge_vehicle_from_board_pre155(p_vehicle_id')<sql.indexOf('update public.navision_board_activations'),'Vehicle tombstone must be authoritative before Navision deactivation');
assert(sql.includes("grant execute on function public.purge_vehicle_from_board(uuid,integer,text) to authenticated")&&sql.includes("revoke all on function public.purge_vehicle_from_board_pre155"),'Only the guarded public wrapper may be executable');
console.log('Navision activation complete Board purge ordering passed');
