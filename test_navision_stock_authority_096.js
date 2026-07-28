'use strict';

const fs = require('fs');
const assert = require('assert');
const sql = fs.readFileSync('supabase/staging_only/096_navision_stock_number_authority.sql', 'utf8');

assert(sql.includes('Navision Stock match wins even when PDF-extracted VIN/details disagree'));
assert(sql.includes("cardinality(v_nav_stock_ids)=1"));
assert(sql.includes("multiple_current_navision_stock_matches"));
assert(sql.includes("navision_stock_not_found_vin_points_elsewhere"));
assert(sql.includes("v_vehicle_id:=v_operational_stock_ids[1]"));
assert(!sql.includes('v_nav_stock_ids is distinct from v_nav_vin_ids'));
assert(!sql.includes('v_operational_stock_ids is distinct from v_operational_vin_ids'));
assert(sql.includes("stock_number=case when v_record.id is not null then v_record.normalized_data->>'batch' else v_stock end"));
assert(sql.includes("vin=v_vin"));
assert(sql.includes("public.is_valid_vehicle_vin(v_record.normalized_data->>'vin')"));
assert(sql.includes("v_extracted_vin:=v_vin"));
for (const field of ['toyota_order_number', 'job_card_number', 'customer_name', 'vehicle_description', 'model', 'salesperson_reference', 'registration', 'eta_to_kewdale']) {
  assert(sql.includes(`${field}=case when v_record.id is not null`), `missing Navision authority for ${field}`);
}
assert(sql.includes("'source','pdc_navision_stock_authority_096'"));
assert(sql.includes("'contract','pdc_navision_stock_authority_096'"));
assert(sql.includes("-- current_location is deliberately absent: operational location always wins."));
assert(sql.includes("where not public.vehicle_work_items.completed"));
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(sql));
assert(/revoke all on function public\.import_pdc_authenticated_vehicle_email[\s\S]+from public,anon,authenticated;/i.test(sql));
assert(/grant execute on function public\.import_pdc_authenticated_vehicle_email[\s\S]+to authenticated;/i.test(sql));
console.log('Migration 096 unique Stock/Navision authority contract passed');
