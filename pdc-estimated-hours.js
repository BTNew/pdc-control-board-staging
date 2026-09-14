(function(root){
  'use strict';
  const present = (line={}, value=line.estimatedHours ?? line.estimated_hours ?? line.hours, edited=false) => {
    const provenance=String(line.hoursProvenance ?? line.hours_provenance ?? '').trim().toLowerCase();
    const supplied=value!==null && value!==undefined && String(value).trim()!=='';
    const ai=!edited && supplied && Number.isFinite(Number(value)) && Number(value)>0 && provenance==='ai_estimated'
      && String(line.stageCode ?? line.stage_code ?? line.stage ?? '').toUpperCase()!=='SUBLET';
    return {ai,label:ai?'AI estimate':'',className:ai?'pdc-ai-estimate':'',
      detail:ai?[line.estimateBasis ?? line.estimate_basis,line.reviewNote ?? line.review_note].filter(x=>typeof x==='string' && x.trim()).join('\n'):''};
  };
  const forVehicleLine=(vehicle={},line={},value=null)=>{
    const id=String(line.workshopLineKey || line.line_identity || line.lineIdentity || ('source:'+(line.operation_line_id || line.source_operation_line_id || '')));
    const rows=(vehicle.pdcQcOperationLines || []).filter(x=>x.lineIdentity===id && x.active===true);
    if(rows.length>1)return present({},null);
    if(rows.length===1){
      const row=rows[0];
      return present(row,value, row.estimatedHours===null || value===null || Number(row.estimatedHours)!==Number(value));
    }
    return present(line,value,!!line.adjustmentId || !!line.manualHoursUnknown);
  };
  const api={present,forVehicleLine};
  if(typeof module==='object' && module.exports)module.exports=api;
  if(root){
    root.PdcEstimatedHours=api;
    root.document?.addEventListener('input',event=>{
      if(!event.target?.hasAttribute?.('data-vehicle-workshop-hours-batch-input'))return;
      const cell=event.target.closest('.vehicle-workshop-line-hours');
      cell?.classList.remove('pdc-ai-estimate');
      const badge=cell?.querySelector('.pdc-ai-estimate-badge');
      if(badge){badge.textContent='Draft estimate';badge.classList.remove('pdc-ai-estimate');}
    });
  }
})(typeof window==='undefined'?null:window);
