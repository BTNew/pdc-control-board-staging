/* TEST-ONLY in-memory backend. Never loaded by index.html or deployed app entry. */
(() => {
  const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const makeLine = (n, stage, hours) => ({ line_identity: `source:${id(n)}`, source_kind: 'authenticated',
    source_line_id: id(n), source_contract: 'pilbara_service_open_jobcards_v1',
    description: `QA inspection item ${n}`, operation_no: `OP${n}`, job_card_number: 'QA-JC-100',
    stage_code: stage, estimated_hours: hours, active: true, completed: false, line_version: 0 });
  const lines = [makeLine(201,'FITTING',1),makeLine(202,'ELECTRICAL',.5),makeLine(203,'UNALLOCATED_MAPPING_REVIEW',0)];
  const raw = { id:id(100), permanent_vehicle_id:'QA-ONLY-100', stock_number:'QA-QC100',
    customer_name:'Synthetic inspection vehicle', vehicle_description:'QA test vehicle',
    job_card_number:'QA-JC-100',version:10,current_location:'QC',lifecycle_state:'active',visible_on_board:true,
    qc_signed_off:false, qc_completed_at:null,source_system:'microsoft_navision',source_record_id:'QA-QC100',
    work_items:[{work_key:'fitting',required:true,completed:true},{work_key:'electrical',required:true,completed:true}],
    qc_operation_lines:lines,workshop_bookings:[],operation_lines:lines.map(l=>({operation_line_id:l.source_line_id,
      operation_no:l.operation_no,description:l.description,job_card_number:l.job_card_number,
      work_key:l.stage_code==='UNALLOCATED_MAPPING_REVIEW'?'review':l.stage_code.toLowerCase(),estimated_hours:l.estimated_hours})) };
  const next = { vehicle_id:id(101),stock_number:'QA-NEW101',customer_name:'Synthetic new import',vehicle_description:'QA new vehicle',
    job_card_number:'QA-JC-101',status:'pending',snapshot_hash:'a'.repeat(64),current_location:'YH',
    operations:[makeLine(301,'UNALLOCATED_MAPPING_REVIEW',.75),makeLine(302,'FITTING',0)] };
  window.__qa = { raw, rows:[raw], queue:[next], calls:[], failMove:false, failApproval:false, photoCalls:0 };
  const snapshot = () => ({ok:true,code:'snapshot',data:{revision:100,vehicles:__qa.rows}});
  const result = body => new Response(JSON.stringify(body),{status:200,headers:{'Content-Type':'application/json'}});
  window.fetch = async (url, options = {}) => {
    const name=String(url).split('/').pop(), body=JSON.parse(options.body || '{}');
    __qa.calls.push({name,body});
    if(name==='get_pdc_email_vehicle_location_snapshot') return result(snapshot());
    if(name==='get_vehicle_workshop_detail_scoped') {
      if(body.p_dealer_code!=='37047') return new Response('{}',{status:403});
      return result({vehicle_id:raw.id,vehicle_version:raw.version,line_adjustments:[],requirements:[],bookings:[]});
    }
    if(name==='move_vehicle_workshop_source_line_stage') {
      if(__qa.failMove) return result({ok:false,code:'stale_line_version'});
      const l=raw.qc_operation_lines.find(l=>l.line_identity===body.p_line_key);
      if(!l || body.p_vehicle_id!==raw.id) return result({ok:false,code:'identity_mismatch'});
      l.stage_code=body.p_stage_code;raw.version++;
      raw.operation_lines.find(o=>o.operation_line_id===l.source_line_id).work_key=body.p_stage_code.toLowerCase();
      return result({ok:true,data:{vehicle_id:raw.id,line_key:l.line_identity,stage_code:l.stage_code,
        vehicle_version_after:raw.version,adjustment_id:id(900),version:1,description:l.description,
        estimated_hours:l.estimated_hours,qc_line:{...l}}});
    }
    if(name==='set_pdc_qc_operation_completion_379') {
      const l=raw.qc_operation_lines.find(l=>l.line_identity===body.p_line_identity);
      if(!l) return result({ok:false,code:'unknown_line'});
      l.completed=body.p_completed;l.line_version++;raw.version++;
      return result({ok:true,code:'qc_operation_completion_saved',receipt_id:id(800),request_sha256:'a'.repeat(64),
        vehicle_id:raw.id,vehicle_version_after:raw.version,line:{...l,version:l.line_version}});
    }
    if(name==='reject_pdc_qc_vehicle_to_pmb_stoppage_767') {
      const selected=body.p_rejected_lines || [];
      raw.current_location='PMB';raw.version++;raw.pmb_stoppage_reason=body.p_reason;
      return result({ok:true,vehicle_id:raw.id,receipt_id:id(801),current_location:'PMB',workshop_status:'stoppage',
        vehicle_version_after:raw.version,rejected_lines:selected});
    }
    if(name==='list_pdc_new_vehicle_reviews') return result({ok:true,code:'new_vehicle_reviews',data:{items:__qa.queue,total:__qa.queue.length,offset:0,has_more:false}});
    if(name==='approve_pdc_new_vehicle_review') {
      if(__qa.failApproval) return result({ok:false,code:'request_failed'});
      const item=__qa.queue[0], ops=item.operations.map(l=>({...l,stage_code:body.p_assignments.find(a=>a.line_identity===l.line_identity).stage_code}));
      __qa.queue=[];
      return result({ok:true,data:{vehicle_id:item.vehicle_id,visible_on_board:true,bookings_created:0,operations:ops}});
    }
    if(name==='get_navision_visible_snapshot') return result({ok:true,data:{items:app.sharedNavisionVisibleRows,has_more:false,revision:1}});
    return result({ok:false,code:'qa_unmodelled_endpoint'}); // Never silently claim unmodelled operations pass.
  };
  window.PDC_AUTH_CONTEXT={role:'administrator',userId:id(1),email:'qa@example.invalid'};
  getPdcSupabaseAccessToken=()=> 'synthetic-qa-only';
  document.body.classList.remove('auth-pending');document.body.dataset.authState='signed-in';
  document.querySelector('.pdc-auth-gate')?.style.setProperty('display','none','important');
  document.querySelector('.app-shell')?.style.setProperty('display','grid','important');
  document.querySelector('#nav-admin-group')?.removeAttribute('hidden');
  document.querySelector('.app-shell')?.removeAttribute('inert');
  document.querySelector('.app-shell')?.removeAttribute('aria-hidden');
  document.querySelector('.app-shell')?.style.setProperty('pointer-events','auto','important');
  app.sharedNavisionVisibleRows=[{canonical_vehicle_id:raw.id,stock_number:raw.stock_number,
    dealer_code:'37047',is_current:true,record_status:'current',board_activated:true}];
  app.emailVehicleLocationService=window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE.createPdcEmailVehicleLocationService({
    config:window.PDC_SUPABASE_CONFIG,getAccessToken:()=>getPdcSupabaseAccessToken(),fetchImpl:(...args)=>window.fetch(...args)});
  app.data=[mapServerVehicle(raw)];app.emailVehicleLocationRows=[raw];app.emailVehicleLocationRevision=100;
})();
