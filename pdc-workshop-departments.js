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
  const PD = Object.freeze(['HOIST','FITTING','FABRICATION','ELECTRICAL']);
  const names = {BUS_4X4:'Bus 4×4',TINT:'Tint · shared',TYRE:'Tyres · shared',HOIST:'Hoist',FITTING:'Fitting',FABRICATION:'Fabrication',ELECTRICAL:'Electrical'};
  const normalize = value => ['138','139'].includes(String(value)) ? String(value) : '';
  const group = id => BUS_GROUPS.find(item => item.id === id) || null;
  const groupForBay = bay => BUS_GROUPS.find(item => item.bays.includes(Number(bay))) || null;
  function stageVisible(stage, department) {
    const dept = normalize(department);
    return !dept || SHARED.includes(stage) || (dept === '138' ? stage === 'BUS_4X4' : PD.includes(stage));
  }
  function options(department) {
    const dept = normalize(department);
    const bus = BUS_GROUPS.map(item => ({id:'bus-'+item.id,stage:'BUS_4X4',group:item.id,label:item.label,bays:item.bays,shared:false}));
    const shared = SHARED.map(stage => ({id:stage,stage,group:'',label:names[stage],shared:true}));
    const pd = PD.map(stage => ({id:stage,stage,group:'',label:names[stage],shared:false}));
    return dept === '138' ? [...bus,...shared] : dept === '139' ? [...pd,...shared] : [...bus,...pd,...shared];
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
    if (/\bCONVERSION\b|\b(?:CARRIER|HOLDER|CHOCKS?|INDICATORS?|INDICAORS|CHAIR)\b|WHEEL[ -]*NUT/.test(text)) return 'BUS_4X4';
    if (/\b(?:TYRES?|TIRES?|RIMS?)\b|WHEEL[ -]*(?:ALIGNMENT|BALANC(?:E|ING))|\b(?:2ND|SECOND|EXTRA|ADDITIONAL)\s+SPARE\s+(?:GENUINE\s+)?WHEEL\b/.test(text)) return 'TYRE';
    return 'BUS_4X4';
  }
  return Object.freeze({BUS_GROUPS,SHARED,PD,normalize,group,groupForBay,stageVisible,options,bayLabel,sharedStation});
});
