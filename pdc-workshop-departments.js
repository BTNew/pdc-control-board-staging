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
    {id:'mechanical',code:'BUS_MECHANICAL',label:'Mechanical',bays:[1,2,3,4]},
    {id:'accessory',code:'BUS_ACCESSORIES',label:'Accessories',bays:[10]},
    {id:'electrical',code:'BUS_ELECTRICAL',label:'Electrical',bays:[8,9]},
    {id:'qa',code:'BUS_QA',label:'QA',bays:[7]},
    {id:'pit',code:'BUS_PIT',label:'Pit',bays:[],external:true},
  ].map(item => Object.freeze({...item,bays:Object.freeze(item.bays)})));
  const names = {BUS_4X4:'Bus 4×4',TINT:'Tint · shared',TYRE:'Tyres · shared',HOIST:'Hoist',FITTING:'Fitting',FABRICATION:'Fab',ELECTRICAL:'Electrical',SUBLET:'Sublet'};
  const category = value => BUS_WORK.find(item => item.code === value || item.id === value) || null;
  const categoryLabel = value => category(value)?.label || names[value] || value;
  const categoryStage = value => value === 'BUS_PIT' ? 'PIT_INSPECTION' : category(value) ? 'BUS_4X4' : value;
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
          bookings:group.bookings.filter(booking => !booking.work_category || booking.work_category === item.code)}];
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
  function bayLabel(stage, bay) {
    const base = 'Bay '+String(bay).padStart(2,'0');
    return stage === 'BUS_4X4' && groupForBay(bay) ? groupForBay(bay).label+' · '+base : base;
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
  return Object.freeze({BUS_GROUPS,BUS_WORK,SHARED,PD,normalize,group,groupForBay,category,categoryLabel,categoryStage,categoryChoices,selectedCategory,splitGroups,stageVisible,options,plannerTitle,plannerSections,bayLabel,sharedStation});
});
