/* Department views share physical bay IDs and booking records. */
(function(root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.PDC_WORKSHOP_DEPARTMENTS = api;
})(typeof window === 'object' ? window : globalThis, function() {
  'use strict';
  const BUS_GROUPS = Object.freeze([
    {id:'mechanical',label:'Mechanical',bays:[1,2,3,4]},
    {id:'progression',label:'Progression',bays:[5,6]},
    {id:'qa',label:'QA',bays:[7]},
    {id:'electrical',label:'Electrical',bays:[8,9]},
    {id:'accessory',label:'Accessory Fitting',bays:[10]},
  ].map(group => Object.freeze({...group,bays:Object.freeze(group.bays)})));
  const SHARED = Object.freeze(['TINT','TYRE']);
  const PD = Object.freeze(['HOIST','FABRICATION','FITTING','ELECTRICAL']);
  const BUS_WORK = Object.freeze([
    // bays = the category's own planner view. r447 (F60, Bhavesh 21 Oct):
    // preferred = the category's own bays in the Dept 138 bay guide
    // (pdc_work_categories_private.preferred_bay; Best slot and Book all use
    // only these); allowed = every bay it goes in with no warning
    // (pdc_work_categories_private.allowed_bay = own bays + overflow Bays 5-6).
    // Any other bay asks to confirm and the override is logged (r417).
    {id:'mechanical',code:'BUS_MECHANICAL',label:'Mechanical',bays:[1,2,3,4],preferred:[1,2,3,4],allowed:[1,2,3,4,5,6]},
    {id:'accessory',code:'BUS_ACCESSORIES',label:'Accessories',bays:[10],preferred:[1,2,3,4,8,9,10],allowed:[1,2,3,4,5,6,8,9,10]},
    {id:'electrical',code:'BUS_ELECTRICAL',label:'Electrical',bays:[8,9],preferred:[8,9,10],allowed:[5,6,8,9,10]},
    {id:'qa',code:'BUS_QA',label:'QA',bays:[7],preferred:[7],allowed:[5,6,7]},
    {id:'pit',code:'BUS_PIT',label:'Pit',bays:[],preferred:[],allowed:[],external:true},
  ].map(item => Object.freeze({...item,bays:Object.freeze(item.bays),preferred:Object.freeze(item.preferred),allowed:Object.freeze(item.allowed),
    view:'planner-bus-'+item.id,path:'workshop/bus-4x4/'+item.id})));
  // r450 (F63, Craig 21 Oct): a whole job books every unbooked Bus line of a
  // vehicle (all categories) to one technician as one booking, so their job
  // card lists every line. It is not a line category: it never appears in the
  // category lists, views or splits. Same bays as the server
  // (pdc_work_categories_private.allowed_bay): any Bus bay except QA Bay 7.
  const WHOLE_JOB = Object.freeze({code:'BUS_WHOLE_JOB',label:'Whole job',allowed:Object.freeze([1,2,3,4,5,6,8,9,10]),preferred:Object.freeze([1,2,3,4,5,6,8,9,10])});
  const isWholeJob = value => value === WHOLE_JOB.code;
  const names = {BUS_4X4:'Bus 4×4',TINT:'Tint · shared',TYRE:'Tyres · shared',HOIST:'Hoist',FITTING:'Fitting',FABRICATION:'Fab',ELECTRICAL:'Electrical',SUBLET:'Sublet'};
  const category = value => BUS_WORK.find(item => item.code === value || item.id === value) || null;
  const allowedBays = value => isWholeJob(value) ? [...WHOLE_JOB.allowed] : category(value)?.allowed ? [...category(value).allowed] : null;
  const preferredBays = value => isWholeJob(value) ? [...WHOLE_JOB.preferred] : category(value)?.preferred ? [...category(value).preferred] : null;
  const categoryForView = value => BUS_WORK.find(item => item.view === value) || null;
  // r406 (F18): Pit is recognised by stage or by wording, in every department,
  // with the same rule as the QC page (app.js qcPageOperationLineIsDeferredPit)
  // and the server (public.pdc_line_is_pit_401, r405). Job cards file "PIT AND
  // WEIGH" as Fitting or Sublet, so the stage alone missed them.
  const PIT_WORDING = /(^|[^A-Z])PITS? ?(AND|&|\+|\/|N|'N')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT/;
  function isPitLine(line = {}) {
    return String(line?.stageCode || '').trim().toUpperCase() === 'PIT_INSPECTION'
      || PIT_WORDING.test(String(line?.description || '').toUpperCase().replace(/\s+/g, ' '));
  }
  function externalPitLines(vehicle = {}) {
    const lifecycle = String(vehicle.pdcLifecycleState || vehicle.vehicleLifecycleState || vehicle.lifecycleState || '').toLowerCase();
    const location = String(vehicle.pdcLocation || '').toLowerCase();
    if (vehicle.__emailVehicleServerAuthoritative !== true || vehicle.pdcQcOperationLinesProjectionPresent !== true
        || vehicle.tuneCheckout?.confirmed === true || vehicle.completedVehicle === true || vehicle.vehicleCollectedState === true
        || ['collected','completed','deleted'].includes(lifecycle) || ['collected','completed'].includes(location)) return [];
    return (vehicle.pdcQcOperationLines || []).filter(line => line.active === true && line.completed !== true
      && line.rejected !== true && isPitLine(line));
  }
  const categoryLabel = value => isWholeJob(value) ? WHOLE_JOB.label : category(value)?.label || names[value] || value;
  const categoryStage = value => value === 'BUS_PIT' ? 'PIT_INSPECTION' : category(value) || isWholeJob(value) ? 'BUS_4X4' : value;
  // r450 (F63): the whole job on offer, from the vehicle's Bus categories
  // (pdc_work_categories_private.vehicle_categories): needs 2+ unbooked,
  // unfinished categories, every one with confirmed hours.
  function wholeJobChoice(workCategories) {
    const rows = (Array.isArray(workCategories) ? workCategories : []).filter(row => {
      const item = category(row?.work_category);
      return item && !item.external && row.completed !== true && row.existing_booking !== true;
    });
    if (rows.length < 2 || rows.some(row => !Number.isFinite(Number(row.estimated_hours)) || row.estimated_hours === null)) return null;
    const hours = rows.reduce((sum, row) => sum + Number(row.estimated_hours), 0);
    if (!(hours > 0)) return null;
    return {code:WHOLE_JOB.code,label:WHOLE_JOB.label,categories:rows.map(row => row.work_category),hours};
  }
  function categoryChoices(department) {
    return String(department) === '138' ? [...BUS_WORK.map(item => item.code),...SHARED,'SUBLET'] : [...PD,...SHARED,'SUBLET'];
  }
  function selectedCategory(authority, code) {
    if (!Array.isArray(authority?.work_categories)) return authority;
    const selected = authority.work_categories.find(item => item.work_category === code);
    const stationBlocked = authority.schedule_enabled === false && !['active_booking_exists','estimated_duration_missing'].includes(authority.disabled_reason);
    return selected ? {...authority,...selected,
      schedule_enabled:!stationBlocked && selected.schedule_enabled === true && selected.completed !== true,
      disabled_reason:stationBlocked ? authority.disabled_reason : selected.disabled_reason || ''}
      : {...authority,work_category:code,estimated_hours:null,existing_booking:false,schedule_enabled:false,completed:true,disabled_reason:'no_category_work'};
  }
  function splitGroups(groups) {
    return groups.flatMap(group => {
      if (group.stage !== 'BUS_4X4' || !group.lines.some(line => category(line.work_category))) return [group];
      return BUS_WORK.filter(item => !item.external).flatMap(item => {
        const lines = group.lines.filter(line => line.work_category === item.code);
        if (!lines.length) return [];
        return [{...group,category:item.code,label:'Bus 4×4 · '+item.label,lines,
          bookings:group.bookings.filter(booking => !booking.work_category || booking.work_category === item.code || isWholeJob(booking.work_category))}];
      });
    });
  }
  const normalize = value => ['138','139'].includes(String(value)) ? String(value) : '';
  const group = id => BUS_GROUPS.find(item => item.id === id) || null;
  const groupForBay = bay => BUS_GROUPS.find(item => item.bays.includes(Number(bay))) || null;
  function stageVisible(stage, department) {
    const dept = normalize(department);
    return !dept || SHARED.includes(stage) || (dept === '138' ? stage === 'BUS_4X4' : PD.includes(stage));
  }
  function options(department) {
    const dept = normalize(department);
    const bus = BUS_WORK.map(item => ({id:'bus-'+item.id,stage:'BUS_4X4',group:item.id,category:item.code,label:item.label,bays:item.bays,external:!!item.external,shared:false}));
    const shared = SHARED.map(stage => ({id:stage,stage,group:'',label:names[stage],shared:true}));
    const pd = PD.map(stage => ({id:stage,stage,group:'',label:names[stage],shared:false}));
    return dept === '138' ? [...bus,...shared] : dept === '139' ? [...pd,...shared] : [...bus,...pd,...shared];
  }
  function plannerTitle(stage) {
    if (stage === 'BUS_4X4') return 'Workshop Planner — Bus 4×4 (138)';
    if (PD.includes(stage)) return 'Workshop Planner — PMB (139)';
    if (SHARED.includes(stage)) return 'Shared Bays — ' + (stage === 'TYRE' ? 'Tyres' : 'Tint');
    return 'Workshop Planner';
  }
  function plannerSections(department) {
    const destinations = options(department);
    const definitions = [
      {id:'138', label:plannerTitle('BUS_4X4'), stages:['BUS_4X4']},
      {id:'139', label:plannerTitle('FITTING'), stages:PD},
      {id:'shared', label:'Shared Bays · Tint and Tyres (138 & 139)', stages:SHARED},
    ];
    return definitions.map(section => ({...section, options:destinations.filter(option => section.stages.includes(option.stage))}))
      .filter(section => section.options.length);
  }
  // r483 (F96, Craig 22 Oct): Dept 139 (PMB) bay names and Craig's bay numbers 1-22, like the Dept 138 bay groups.
  // Keyed by station and the station's own bay_number: bookings keep bay_id / bay_number, only the label changes.
  // r509 (F122): Fabrication shows 14 bays. Bays 01 and 02 keep Internal / External Fabrication (PMB Bays 11 and 12).
  // Bays 03-14 keep the plain 'Bay NN' label. Shared Tint / Tyre and Bus 4x4 are not in this map.
  const PMB_BAYS_VERSION = 'r483';
  const pmbBayRows = (first, label, count) => Object.freeze(Object.fromEntries(Array.from({length:count}, (_, i) =>
    [i+1, Object.freeze({number:first+i, label})])));
  const PMB_BAYS = Object.freeze({
    HOIST: Object.freeze({1:Object.freeze({number:1,label:'Express / Pits Hoist'}),2:Object.freeze({number:2,label:'Express'}),3:Object.freeze({number:3,label:'Hoist'})}),
    FITTING: pmbBayRows(6, 'Fitting', 5),
    FABRICATION: Object.freeze({1:Object.freeze({number:11,label:'Internal Fabrication'}),2:Object.freeze({number:12,label:'External Fabrication'})}),
    ELECTRICAL: pmbBayRows(13, 'Electrical', 10),
  });
  const PMB_BAY_COUNTS = Object.freeze({HOIST:3,FITTING:5,FABRICATION:14,ELECTRICAL:10});
  const pmbBay = (stage, bay) => PMB_BAYS[String(stage || '').trim().toUpperCase()]?.[Number(bay)] || null;
  // 'Fitting · Bay 06' for a Dept 139 bay, '' for any other station (callers keep their own 'Bay N').
  function pmbBayLabel(stage, bay) {
    const named = pmbBay(stage, bay);
    return named ? named.label+' · Bay '+String(named.number).padStart(2,'0') : '';
  }
  function bayLabel(stage, bay) {
    // r546 (F160): bay 0 is no bay. Callers that used to pad it to Bay 00 say Unallocated.
    const number = Number(bay);
    if (!Number.isInteger(number) || number < 1) return 'Unallocated';
    const base = 'Bay '+String(number).padStart(2,'0');
    return pmbBayLabel(stage, number) || (stage === 'BUS_4X4' && groupForBay(number) ? groupForBay(number).label+' · '+base : base);
  }
  // Combined conversion lines stay together: mentioning a tyre specification does
  // not split a conversion's source hours into invented operations.
  function sharedStation(description) {
    const text = String(description || '').toUpperCase();
    if (/\bTINT(?:ING|S)?\b/.test(text) && !/BONNET[ -]*PROTECT|WEATHER[ -]*(?:SHIELD|SHEILD)/.test(text)) return 'TINT';
    if (/\bCONVERSION\b|SUPER SINGLE.*(?:TYRES?|RIMS?).*COASTER|COASTER.*SUPER SINGLE|\b(?:CARRIER|HOLDER|CHOCKS?|INDICATORS?|INDICAORS|CHAIR)\b|WHEEL[ -]*NUT/.test(text)) return 'BUS_4X4';
    if (/\b(?:TYRES?|TIRES?|RIMS?)\b|WHEEL[ -]*(?:ALIGNMENT|BALANC(?:E|ING))|\b(?:2ND|SECOND|EXTRA|ADDITIONAL)\s+SPARE\s+(?:GENUINE\s+)?WHEEL\b/.test(text)) return 'TYRE';
    return 'BUS_4X4';
  }
  return Object.freeze({PMB_BAYS_VERSION,PMB_BAYS,PMB_BAY_COUNTS,pmbBay,pmbBayLabel,BUS_GROUPS,BUS_WORK,WHOLE_JOB,isWholeJob,wholeJobChoice,SHARED,PD,normalize,group,groupForBay,category,allowedBays,preferredBays,categoryForView,externalPitLines,isPitLine,categoryLabel,categoryStage,categoryChoices,selectedCategory,splitGroups,stageVisible,options,plannerTitle,plannerSections,bayLabel,sharedStation});
});
