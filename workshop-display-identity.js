(function(root,factory){
  'use strict';
  const api=factory();
  if(typeof module==='object'&&module.exports) module.exports=api;
  else root.WorkshopDisplayIdentity=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const stages=['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE'];
  const text=value=>String(value??'').trim();
  const recorded=value=>value!=null&&!['','—','-','unknown','tba','not recorded'].includes(text(value).toLowerCase());
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  // Display supplements only. Never match mutable stock numbers, infer an
  // allocation, or accept browser-local/ambiguous records as shared authority.
  function build(rows=[],normalizeStage=value=>text(value).toUpperCase()){
    const grouped=new Map(),result=new Map();
    for(const row of rows){
      const id=text(row?.__emailVehicleId).toLowerCase();
      if(!uuid.test(id)||row.__emailVehicleServerAuthoritative!==true||row.__emailVehicleIdentityConflict===true) continue;
      if(grouped.has(id)) grouped.set(id,null); else grouped.set(id,row);
    }
    for(const [id,row] of grouped){
      if(!row) continue;
      const key=[row.keyNumber,row.key_number,row.keyNo,row.keyTag,row.pdcKeyNumber,row.vehicleKeyNumber].find(recorded);
      const source=row.pdcQcOperationLinesProjectionPresent===true?row.pdcQcOperationLines:row.pdcEmailOperationLines;
      const jobs=new Map(stages.map(stage=>[stage,new Set()]));
      for(const line of Array.isArray(source)?source:[]){
        if(!line||line.active===false) continue;
        const stage=normalizeStage(line.stageCode||line.stage_code||line.work_key||line.workKey||'');
        const job=line.jobCardNumber||line.job_card_number;
        if(jobs.has(stage)&&recorded(job)) jobs.get(stage).add(text(job));
      }
      for(const stage of stages) result.set(`${id}:${stage}`,{key:recorded(key)?text(key):'',job:[...jobs.get(stage)].join(', ')});
    }
    return result;
  }
  return Object.freeze({build});
});
