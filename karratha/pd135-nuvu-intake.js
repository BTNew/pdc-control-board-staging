(function (root) {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
  const required = ['stock_number','repair_order_number','original_line_number','operation_description','store_code'];
  const labels = {stock_number:'Stock',repair_order_number:'Job card',original_line_number:'Original operation line',operation_description:'Description',source_estimated_hours:'Source hours (decimal)',store_code:'Store',stage_code:'Station',parts_required:'Parts required',dealer_code:'Dealer code',vin:'VIN',toyota_order_number:'Toyota order'};
  const stages = new Set(['TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PARTS','REFERENCE','REVIEW']);
  const hashPattern = /^[a-f0-9]{64}$/;
  function freeze(value){if(value&&typeof value==='object'){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}
  async function sha(text) { return [...new Uint8Array(await root.crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(value=>value.toString(16).padStart(2,'0')).join(''); }
  function groupRows(rows,workbookHash) {
    if (!hashPattern.test(workbookHash) || !Array.isArray(rows) || !rows.length || rows.length>10000) throw new Error('This source could not be verified.');
    const groups=new Map();
    rows.forEach((row,index)=>{
      const stock=String(row.stock_number??'').trim(),job=String(row.repair_order_number??'').trim(),store=String(row.store_code??'').trim();
      const key=JSON.stringify([store,stock,job,(!stock||!job)?index:null]);
      if(!groups.has(key))groups.set(key,{key,stock,job,store,rows:[],issues:[]});
      const group=groups.get(key),issues=group.issues;
      if(store!=='135')issues.push('Source store is not 135.');
      if(!stock||!job)issues.push('Stock and job-card identifiers are required.');
      if(!Number.isSafeInteger(row.original_line_number)||row.original_line_number<1)issues.push('A stable original operation line is required.');
      if(!String(row.operation_description??'').trim())issues.push('Operation description is blank.');
      const hours=row.source_estimated_hours;
      if(hours!==null && hours!==undefined && (!Number.isFinite(hours)||hours<0||hours>999.99||Math.abs(hours*100-Math.round(hours*100))>0.000001))issues.push('Source hours must be decimal hours with at most two decimal places.');
      const raw=JSON.parse(JSON.stringify(row.raw_row||{}));
      if(Object.hasOwn(raw,'parent_attachment_sha256')&&raw.parent_attachment_sha256!==workbookHash)issues.push('Existing attachment hash contradicts this source.');
      raw.parent_attachment_sha256=workbookHash;
      const line={department:'135',workbook_sha256:workbookHash,stock_number:stock,repair_order_number:job,original_line_number:row.original_line_number,operation_description:String(row.operation_description??''),source_estimated_hours:hours===null||hours===undefined?null:String(hours),proposed_station:stages.has(row.stage_code)?row.stage_code:'REVIEW',raw_row:raw};
      for(const field of ['dealer_code','vin','toyota_order_number'])if(row[field]!==undefined)line[field]=String(row[field]);
      group.rows.push({index,line});
    });
    return [...groups.values()].map(group=>({...group,issues:[...new Set(group.issues)]}));
  }
  function create(options) {
    let generation=0,cards=[],selected=new Set(),attempt=null,preview=null,result=null,busy=false,error='';
    const authority=()=>options.getAuthority();
    const current=(owner,stamp)=>owner===authority()&&stamp===generation;
    const notify=()=>options.onChanged?.();
    function invalidate(){generation++;attempt=null;preview=null;result=null;error='';}
    function clear(){invalidate();cards=[];selected.clear();busy=false;notify();}
    function setRows(rows,hash){invalidate();cards=groupRows(rows,hash);selected.clear();notify();}
    function select(key,value){if(busy)throw new Error('Wait for the current review to finish.');const card=cards.find(item=>item.key===key);if(!card||card.issues.length)throw new Error('This job card needs source review first.');invalidate();value?selected.add(key):selected.delete(key);notify();}
    function state(){return {cards,selected:new Set(selected),attempt,preview,result,busy,error};}
    async function run(kind){
      if(busy)return;
      const owner=authority(),stamp=generation;
      if(!owner)throw new Error('Sign in with approved Department 135 access.');
      if(kind==='apply'&&(!preview?.apply_allowed||!attempt))throw new Error('Review the selected job cards first.');
      busy=true;error='';notify();
      try{
        if(!attempt){
          const rows=cards.filter(card=>selected.has(card.key)&&!card.issues.length).flatMap(card=>card.rows).sort((a,b)=>a.index-b.index).map(item=>item.line);
          if(!rows.length)throw new Error('Select the job cards to import.');
          const bytes=JSON.stringify(rows),hash=await (options.hash||sha)(bytes);
          if(!current(owner,stamp))return;
          if(!hashPattern.test(hash))throw new Error('The selected source could not be verified.');
          attempt=freeze({rows:JSON.parse(bytes),bytes,hash,previewNonce:root.crypto.randomUUID(),applyNonce:root.crypto.randomUUID()});
        }
        const payload=kind==='preview'?{p_rows:attempt.rows,p_source_hash:attempt.hash,p_idempotency_key:attempt.previewNonce}:{p_preview_batch_id:preview.preview_batch_id,p_source_hash:attempt.hash,p_idempotency_key:attempt.applyNonce};
        const reply=await options.rpc('pdc_pilbara_service_'+kind+'_v1',payload);
        if(!current(owner,stamp))return;
        if(reply?.ok!==true||reply.source_hash!==attempt.hash)throw new Error(reply?.code||'The source review could not be confirmed.');
        if(kind==='preview'){
          if(typeof reply.preview_batch_id!=='string'||!reply.preview_batch_id||reply.workbook_sha256!==attempt.rows[0].workbook_sha256)throw new Error('The preview source could not be confirmed.');
          preview=reply;
        }else{
          if(!['applied','apply_replay'].includes(reply.code)||reply.atomic!==true||reply.approvals_created!==0||reply.bookings_created!==0||reply.completions_created!==0)throw new Error('The import receipt could not be confirmed. Refresh the queue before continuing.');
          result=reply;options.onApplied?.();
        }
      }catch(failure){if(current(owner,stamp))error=String(failure.message||'The request could not be confirmed.');}
      finally{if(current(owner,stamp)){busy=false;notify();}}
    }
    return Object.freeze({setRows,select,clear,state,preview:()=>run('preview'),apply:()=>run('apply')});
  }
  const api=Object.freeze({groupRows,create,required,labels,esc});
  if(typeof module==='object'&&module.exports){module.exports=api;return;}
  root.PDC135_NUVU=api;
  if(!root.document)return;
  let dialog=null,body=null,source=null,table=null,mapping={},sourceGeneration=0,pageNumber=0,refreshQueue=null;
  const writable=()=>root.PDC_AUTH_CONTEXT?.centreCode==='135'&&['operator','administrator'].includes(root.PDC_AUTH_CONTEXT?.role);
  const owner=()=>writable()?JSON.stringify([root.PDC_AUTH_CONTEXT.userId,root.PDC_AUTH_CONTEXT.role,root.PDC_AUTH_CONTEXT.membership_version,root.PDC_AUTH_CONTEXT.engine_version]):'';
  const rpc=async(name,payload)=>{
    if(!writable())throw new Error('Department 135 approval is required.');
    const token=root.PDC_AUTH?.getAccessToken?.()|| (typeof getPdcSupabaseAccessToken==='function'?getPdcSupabaseAccessToken():'');
    if(!token)throw new Error('Sign in again before reviewing this source.');
    const config=root.PDC_SUPABASE_CONFIG,receipt=await root.fetch(config.url.replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:config.publishableKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(payload)});
    const data=await receipt.json();if(!receipt.ok)throw new Error(data?.code||data?.message||'The source request failed.');return data;
  };
  const model=create({getAuthority:owner,rpc,onChanged:()=>render(),onApplied:()=>refreshQueue?.()});
  function clear(){sourceGeneration++;source=null;table=null;mapping={};pageNumber=0;model.clear();if(dialog){dialog.hidden=true;dialog.remove();dialog=null;body=null;}}
  root.addEventListener('pdc-auth-locked',clear);
  root.addEventListener('pdc-auth-ready',()=>{if(dialog&&!writable())clear();});
  function message(code){if(/arb_missing_hours|hours/.test(code))return 'Some operation hours need research or staff review. Source hours have been preserved; no estimates were invented.';if(/session|authorized|access changed/.test(code))return 'Access changed. Sign in again and review this file.';if(/conflicting_stock|identity|ambiguous/.test(code))return 'The source identifiers conflict. Check the stock, job card and original line columns before continuing.';if(/^[a-z0-9_]+$/.test(code))return 'This source could not be confirmed. Check the file and refresh the review before retrying.';return code;}
  function render(){
    if(!body)return;
    const state=model.state(),cards=state.cards.slice(pageNumber*30,pageNumber*30+30),frozen=state.busy;
    body.innerHTML=`<header class="nv-header"><div><span class="eyebrow">Department 135</span><h2 id="pd135-nuvu-title">Review NuVu job cards</h2><p>Select only the job cards this department will review. Importing does not approve work or create bookings.</p></div><button type="button" data-intake-close ${frozen?'disabled':''} aria-label="Close file review">×</button></header>
      <label class="nv-queue-search">NuVu export<input type="file" data-intake-file accept=".xlsx,.xls,.csv,.tsv,.txt" ${frozen?'disabled':''}></label>
      ${source?`<p class="nv-help">${esc(source.name)}<br>Map the original columns. Keep the source’s own operation line number.</p><div class="nv-header-actions"><label>Worksheet<select data-intake-sheet ${frozen?'disabled':''}>${source.sheets.map(name=>`<option ${name===table?.sheet_name?'selected':''}>${esc(name)}</option>`).join('')}</select></label><label>Header row<input data-intake-header type="number" min="1" max="1000" value="${table?.header_row||1}" ${frozen?'disabled':''}></label>${source.text!==undefined?`<label>Delimiter<select data-intake-delimiter ${frozen?'disabled':''}><option value="tab">Tab</option><option value="comma">Comma</option><option value="semicolon">Semicolon</option></select></label>`:''}<button data-intake-columns ${frozen?'disabled':''}>Read columns</button></div>`:''}
      ${table?`<div class="pd135-mapping">${root.KARRATHA_NUVU.fields.map(field=>`<label>${esc(labels[field])}${required.includes(field)?' *':''}<select data-intake-map="${field}" ${frozen?'disabled':''}><option value="">${required.includes(field)?'Choose source column':'Not supplied'}</option>${table.headers.map(header=>`<option value="${esc(header)}" ${mapping[field]===header?'selected':''}>${esc(header)}</option>`).join('')}</select></label>`).join('')}</div><button data-intake-review ${frozen?'disabled':''}>Review job cards</button>`:''}
      ${state.error?`<div class="nv-error" role="alert">${esc(message(state.error))}</div>`:''}
      ${state.cards.length?`<p class="nv-help">${state.cards.length} job-card groups · ${state.selected.size} selected. Unselected groups are not sent to the department.</p><div class="nv-list">${cards.map(card=>`<article class="nv-card"><label><input type="checkbox" data-intake-select="${esc(card.key)}" ${state.selected.has(card.key)?'checked':''} ${frozen||card.issues.length?'disabled':''}> <strong>${esc(card.stock||'Stock missing')}</strong> · ${esc(card.job||'Job card missing')}</label><small>Store ${esc(card.store||'missing')} · ${card.rows.length} source lines</small>${card.issues.length?`<p class="nv-card-error">${card.issues.map(esc).join(' ')}</p>`:''}<details><summary>Original source lines</summary>${card.rows.map(({line})=>`<p class="pd135-source-line"><strong>Line ${esc(line.original_line_number??'missing')}</strong> · ${esc(line.source_estimated_hours??'Hours not supplied')} h · ${esc(line.proposed_station)}<br>${esc(line.operation_description)}</p>`).join('')}</details></article>`).join('')}</div><div class="nv-pagination"><button data-intake-page="-1" ${frozen||!pageNumber?'disabled':''}>Previous</button><span>${pageNumber+1} / ${Math.ceil(state.cards.length/30)}</span><button data-intake-page="1" ${frozen||(pageNumber+1)*30>=state.cards.length?'disabled':''}>Next</button></div><button class="primary" data-intake-preview ${frozen||!state.selected.size||state.result?'disabled':''}>${frozen?'Checking…':'Preview selected job cards'}</button>`:''}
      ${state.preview?`<section class="nv-summary"><h3>Source preview</h3><p>${esc(state.preview.source_rows??'')} source rows · ${esc(state.preview.accepted_lines??'')} accepted lines</p><p>Matched stock: ${esc(state.preview.matched?.stocks??0)} · Unmatched: ${esc(state.preview.unmatched?.stocks??0)} · Ambiguous: ${esc(state.preview.ambiguous?.stocks??0)}</p><p>New lines: ${esc(state.preview.operations?.insert??0)} · Unchanged: ${esc(state.preview.operations?.unchanged??0)} · Quarantined: ${esc(state.preview.operations?.quarantine??0)} · Conflicts: ${esc(state.preview.operations?.conflict??0)}</p><p>${state.preview.apply_allowed?'These selected source lines can enter the existing Job Card review queue.':'This source needs further review before import.'}</p><button class="primary" data-intake-apply ${frozen||!state.preview.apply_allowed||state.result?'disabled':''}>Import selected source lines</button></section>`:''}
      ${state.result?'<div class="nv-notice" role="status">Import confirmed. Review the Job Cards in New Vehicles before approving them for the board. No approvals, bookings or completions were created.</div>':''}`;
    body.querySelector('[data-intake-close]').onclick=()=>clear();
    body.querySelector('[data-intake-file]').onchange=async event=>{
      const file=event.target.files?.[0],stamp=++sourceGeneration,actor=owner();if(!file||!actor)return;source=null;table=null;mapping={};model.clear();
      try{const parsed=await root.KARRATHA_NUVU.read(file);if(stamp!==sourceGeneration||actor!==owner())return;source=parsed;table=null;mapping={};render();}catch(error){if(stamp===sourceGeneration&&actor===owner())body.querySelector('header').insertAdjacentHTML('afterend',`<div class="nv-error" role="alert">${esc(error.message)}</div>`);}
    };
    body.querySelector('[data-intake-columns]')?.addEventListener('click',()=>{
      if(!writable()||frozen)return;
      const delimiters={tab:'\t',comma:',',semicolon:';'};
      try{table=root.KARRATHA_NUVU.table(source,body.querySelector('[data-intake-sheet]').value,Number(body.querySelector('[data-intake-header]').value),delimiters[body.querySelector('[data-intake-delimiter]')?.value]||'\t');mapping={};model.clear();render();}catch(error){body.querySelector('header').insertAdjacentHTML('afterend',`<div class="nv-error" role="alert">${esc(error.message)}</div>`);}
    });
    body.querySelectorAll('[data-intake-map]').forEach(select=>select.onchange=()=>{mapping[select.dataset.intakeMap]=select.value;model.clear();});
    body.querySelector('[data-intake-review]')?.addEventListener('click',()=>{
      try{if(!writable()||frozen)return;for(const field of required)if(!mapping[field])throw new Error('Choose every required source column, including the original operation line.');pageNumber=0;model.setRows(root.KARRATHA_NUVU.mapped(table,mapping),source.hash);}catch(error){body.querySelector('header').insertAdjacentHTML('afterend',`<div class="nv-error" role="alert">${esc(error.message)}</div>`);}
    });
    body.querySelectorAll('[data-intake-select]').forEach(input=>input.onchange=()=>model.select(input.dataset.intakeSelect,input.checked));
    body.querySelectorAll('[data-intake-page]').forEach(button=>button.onclick=()=>{pageNumber+=Number(button.dataset.intakePage);render();});
    body.querySelector('[data-intake-preview]')?.addEventListener('click',()=>void model.preview());
    body.querySelector('[data-intake-apply]')?.addEventListener('click',()=>void model.apply());
  }
  function open(){
    if(!writable())return;
    if(!dialog){dialog=root.document.createElement('div');dialog.className='modal-overlay';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');dialog.setAttribute('aria-labelledby','pd135-nuvu-title');body=root.document.createElement('section');body.className='modal-card detail-panel pd135-intake';dialog.appendChild(body);root.document.body.appendChild(dialog);dialog.addEventListener('keydown',event=>{if(event.key==='Escape'&&!model.state().busy)clear();if(event.key==='Tab'){const focus=[...body.querySelectorAll('button:not([disabled]),input:not([disabled]),select:not([disabled]),summary')];if(!focus.length)return;const first=focus[0],last=focus.at(-1);if(event.shiftKey&&root.document.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&root.document.activeElement===last){event.preventDefault();first.focus();}}});}
    dialog.hidden=false;render();body.querySelector('button')?.focus();
  }
  function mount(page,refresh){
    refreshQueue=refresh;
    if(!writable()||page.querySelector('[data-pd135-nuvu-open]'))return;
    const actions=page.querySelector('.nv-header-actions');if(!actions)return;
    const button=root.document.createElement('button');button.type='button';button.dataset.pd135NuvuOpen='';button.textContent='Review NuVu file';button.addEventListener('click',open);actions.prepend(button);
  }
  root.PDC135_NUVU=Object.freeze({...api,mount,clear});
})(typeof window==='object'?window:globalThis);
