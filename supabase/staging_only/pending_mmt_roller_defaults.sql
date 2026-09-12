-- Owner rules are review proposals. Call only for pending, untouched source lines.
CREATE OR REPLACE FUNCTION public.pdc_pending_work_category_20260912(p_line jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path TO pg_catalog, public
AS $function$
DECLARE
 d text:=upper(regexp_replace(coalesce(p_line->>'description',''),'[[:space:]]+',' ','g'));
 stage text:=p_line->>'stage_code'; rule text; result jsonb:=p_line;
 times numeric[]; effective numeric; default_hours numeric; default_provenance text; quantity_match text[];
BEGIN
 -- Preparation standards and specific product rules precede department defaults.
 IF d ~ '\m(FILL[ ]+(WITH[ ]+)?FUEL|FULL[ ]+TANK[ ]+(OF[ ]+)?FUEL|REFUEL(LING|ING)?|PIT[ ]*(AND|&)[ ]*WEIGH)\M'
  OR d ~ 'BATTERY[ ]*100[ ]*%' OR public.pdc_is_pre_delivery_20260910(d) THEN
  stage:='FITTING'; rule:='preparation_fitting';
 ELSIF d ~ '\mMINE[ -]?BARS?\M' OR (d ~ '\mWHIP[ -]?FLAGS?\M' AND d ~ 'ROOF[ -]?RACK|RHINO[ -]?RACK|LIGHT|LED|ILLUMINAT') THEN
  stage:='ELECTRICAL'; rule:='mine_bar_or_lit_roof_whip';
 ELSIF d ~ '\mSUBCORE?\M.*(SIGN|LOGO|RIBBON)' OR d ~ '\mPTE\M.*TRAY'
  OR d ~ 'HEAVY[ -]?DUTY.*RUBBER.*(FLOOR[ -]?)?MATS?' OR d ~ '\m(PROTECTED|PROTECTA)\M.*MATS?' OR d ~ 'VINYL[ -]?FLOOR'
  OR ((d ~ '\m(HI[ -]?DRIVE|HIGH[ -]?DRIVE|BOSTON|MTE)\M.*(CANOP|BULL|MOTOR[ -]?BOD|BODIES|BODY)' OR d ~ '\mCANOP(Y|IES)\M|BODY[ -]?BUILDER')
   AND d !~ 'SOCKET|OUTLET|ANDERSON|COMPRESSOR|BEACON|DECAL|FRIDGE[ -]?SLIDE|AIR[ -]?VENT|SECURITY[ -]?GRILL|ROOF[ -]?RACK|RHINO[ -]?RACK|CABINET|LIGHT') THEN
  stage:='SUBLET'; rule:='specified_sublet_product';
 ELSIF d ~ 'WHEEL[ -]?CHOCK' THEN
  stage:='FITTING'; rule:='wheel_chocks_fitting';
 ELSIF d ~ 'TRIANGLE.*(MOUNT|HOLDER)|(MOUNT|HOLDER).*TRIANGLE' THEN
  stage:='FABRICATION'; rule:='mounted_triangle_holder_fabrication';
 ELSIF d ~ 'MMT.*SEAT[ -]?COVERS?' THEN
  stage:='SUBLET'; rule:='mmt_seat_covers_sublet';
 ELSIF d ~ 'MANUAL.*ROLLER.*PZQ7D0K050' THEN
  stage:='FITTING'; rule:='toyota_manual_roller_cover';
 ELSIF d ~ 'RYCO.*CATCH[ -]?CAN.*KIT' THEN
  stage:='FITTING'; rule:='ryco_catch_can_kit';
 ELSIF d ~ 'ADDITIONAL.*(GENUINE|ALLOY).*RIM' THEN
  stage:='FABRICATION'; rule:='additional_genuine_alloy_rim';
 ELSIF d ~ 'SPARE[ -]?(TYRE|WHEEL).*(HOLDER|MOUNT).*PMB.*CAB[ -]?RACK' THEN
  stage:='FABRICATION'; rule:='pmb_cab_rack_tyre_holder';
 ELSIF d ~ 'CERTIFIED.*MESH.*CAB[ -]?RACK.*BARRIER' OR d ~ 'ADDITIONAL.*ALLOY.*RIMS?'
  OR (d ~ '\m(800[ ]*MM[ ]*)?TOOL[ -]?BOX(ES)?\M' AND d !~ 'CENTRAL[ -]?LOCK|SOCKET|OUTLET|WIRING|LIGHT') OR d ~ 'TIE[ -]?DOWN.*(POINT|ANCHOR).*FLOOR'
  OR d ~ 'SPARE[ -]?WHEEL.*(MOUNT|HOLDER).*\m(TRAY|TOOL[ -]?BOX)' THEN
  stage:='FABRICATION'; rule:='fabricated_accessory';
 ELSIF d ~ 'BUSHRANGER.*COVERT.*WINCH|ROOF[ -]?RACK|RHINO[ -]?RACK|FIRST[ -]?AID.*KIT'
  OR d ~ 'ANTI[ -]?THEFT.*(NUMBER|NO[ .-]?)[ -]?PLATE.*SCREW' OR d ~ '\mEV[ -]?TAGS?\M' THEN
  stage:='FITTING'; rule:='specific_minor_or_roof_fitment';
 ELSIF d ~ '\mPMB[ -]*0*02\M|\mPMB[ -]+ITEMS?\M|^PMB([A-Z]?[0-9]+)?\M' THEN
  stage:='FABRICATION'; rule:='pmb_product';
 END IF;
 IF rule IS NOT NULL THEN result:=result||jsonb_build_object('stage_code',stage,'routing_rule',rule,'routing_rule_version','craig_work_categories_20260912'); END IF;
 -- Do not replace positive source/AI estimates or explicitly stated zero hours.
 IF stage='ELECTRICAL' THEN
  default_hours:=1.5; default_provenance:='craig_electrical_default_1_5_hours';
 ELSIF stage='FITTING' AND d ~ 'MANUAL.*ROLLER.*PZQ7D0K050' THEN
  default_hours:=3; default_provenance:='craig_manual_roller_cover_default_3_hours';
 ELSIF stage='FITTING' AND d ~ 'ARB.*COMMERCIAL.*BULL[ -]?BAR' AND d ~ 'HILUX' AND d ~ 'MY[ ]?26' THEN
  default_hours:=5; default_provenance:='craig_my26_hilux_arb_commercial_bar_5_hours';
 ELSIF stage='FITTING' AND d ~ 'RYCO.*CATCH[ -]?CAN.*KIT' THEN
  default_hours:=1.5; default_provenance:='craig_ryco_catch_can_default_1_5_hours';
 ELSIF stage='FABRICATION' THEN
  IF d ~ 'ADDITIONAL.*(GENUINE|ALLOY).*RIM' THEN
   default_hours:=0.5; default_provenance:='craig_additional_rim_default_0_5_hours';
  ELSIF d ~ 'TIE[ -]?DOWN.*POINT.*FLOOR' THEN
   quantity_match:=regexp_match(d,'[ ]X[ ]*([0-9]+)\M');
   default_hours:=coalesce(quantity_match[1]::numeric,1);
   default_provenance:='craig_floor_tie_down_1_hour_each';
  ELSIF d ~ 'PMB.*STEEL.*TRAY|PMB.*TRAY.*STEEL' THEN
   default_hours:=2; default_provenance:='craig_steel_tray_default_2_hours';
  ELSIF d ~ 'MESH.*CAB[ -]?RACK.*BARRIER' THEN
   default_hours:=0.5; default_provenance:='craig_mesh_cab_rack_default_0_5_hours';
  ELSIF d ~ 'SPARE[ -]?(TYRE|WHEEL).*(HOLDER|MOUNT).*PMB.*CAB[ -]?RACK' THEN
   default_hours:=0.5; default_provenance:='craig_tyre_holder_default_0_5_hours';
  END IF;
 END IF;
 IF default_hours IS NOT NULL AND coalesce((p_line->>'estimated_hours')::numeric,0)=0
  AND coalesce((p_line->>'source_estimated_hours')::numeric,0)=0 THEN
  SELECT array_agg(DISTINCT (m[1])::numeric / CASE WHEN m[2] LIKE 'MIN%' THEN 60 ELSE 1 END)
   INTO times FROM regexp_matches(d,'\m([0-9]+(?:\.[0-9]+)?)[ ]*(HOURS?|HRS?|H|MINUTES?|MINS?)\M','g') m;
  IF coalesce(cardinality(times),0)>1 THEN
   result:=result||jsonb_build_object('estimated_hours',NULL,'hours_provenance','conflicting_description_times');
  ELSE
   effective:=CASE WHEN cardinality(times)=1 THEN round(times[1],2) ELSE default_hours END;
   result:=result||jsonb_build_object('estimated_hours',effective,'effective_estimated_hours',effective,
    'hours_provenance',CASE WHEN cardinality(times)=1 THEN 'explicit_description_time' ELSE default_provenance END);
  END IF;
 END IF;
 RETURN result;
END $function$;
REVOKE ALL ON FUNCTION public.pdc_pending_work_category_20260912(jsonb) FROM PUBLIC,anon,authenticated;
