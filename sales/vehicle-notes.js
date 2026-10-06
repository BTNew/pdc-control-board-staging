(function(root){
 'use strict';
 const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function create(host){
  let options,principal=null,scope='',generation=0,request=0,loaded=false,loadError='';
  const records=new Map(),drafts=new Map(),expanded=new Set(),busy=new Set(),messages=new Map();
  const user=()=>host.PDC_AUTH_CONTEXT?.userId||null;
  const rows=()=>options?.getRows?.()||[];
  const allowed=id=>rows().some(r=>r.tracking_id===id&&!r.identity_conflict);
  const editable=id=>allowed(id)&&options?.canEditRow?.(rows().find(r=>r.tracking_id===id))!==false;
  function clear(){generation++;request++;principal=user();scope=options?.getScope?.()||'';loaded=false;loadError='';records.clear();drafts.clear();expanded.clear();busy.clear();messages.clear();}
  function syncScope(){
   if(principal!==user()||scope!==(options?.getScope?.()||''))clear();
   const ids=new Set(rows().map(r=>r.tracking_id));
   for(const map of [records,drafts,expanded,busy,messages])for(const id of map.keys())if(!ids.has(id))map.delete(id);
   return !!user();
  }
  const repaint=()=>options?.onChanged?.();
  function hasSavedNotes(id){
   if(!syncScope()||!allowed(id))return false;
   const record=records.get(id);
   return Boolean(record&&(record.notes.trim()||record.custom_information.trim()));
  }
  async function load(){
   if(!syncScope())return;
   const epoch=generation,who=user(),seq=++request;loadError='';
   try{
    const {data,error}=await host.PDC_SUPABASE.rpc('get_broome_sales_vehicle_notes');
    if(epoch!==generation||who!==user()||seq!==request)return;
    if(error)throw error;
    if(!Array.isArray(data))throw new Error('Vehicle notes could not be loaded.');
    for(const record of data)if(allowed(record.tracking_id)&&Number.isInteger(record.version)&&record.version>0&&
     typeof record.notes==='string'&&typeof record.custom_information==='string'&&record.version>=(records.get(record.tracking_id)?.version||0))records.set(record.tracking_id,record);
    loaded=true;
   }catch(error){if(epoch!==generation||who!==user()||seq!==request)return;loadError=error.message||'Vehicle notes could not be loaded. Refresh to retry.';loaded=false;}
   repaint();
  }
  function toggle(id){if(!syncScope()||!allowed(id)||options?.isHidden?.())return;if(expanded.has(id))expanded.delete(id);else expanded.add(id);repaint();}
  function toggleHtml(row){
   return '<button type="button" class="vehicle-notes-toggle" data-notes-toggle="'+escape(row.tracking_id)+'" aria-expanded="'+expanded.has(row.tracking_id)+'" aria-label="'+(expanded.has(row.tracking_id)?'Collapse':'Expand')+' notes for '+escape(options?.reference?.(row)||row.order||row.stock||'vehicle')+'"'+(row.identity_conflict||options?.isHidden?.()?' disabled':'')+'><span aria-hidden="true">'+(expanded.has(row.tracking_id)?'▾':'▸')+'</span></button>';
  }
  function editorHtml(row){
   const id=row.tracking_id;if(!expanded.has(id)||options?.isHidden?.())return '';
   const record=records.get(id),draft=drafts.get(id),data=draft||record||{},disabled=busy.has(id)||!loaded||!editable(id);
   return '<form class="vehicle-notes-editor" data-notes-form="'+escape(id)+'"><div class="vehicle-notes-heading"><strong>'+escape(options?.reference?.(row)||row.order||row.stock||'Vehicle')+' · Notes &amp; custom information</strong><button type="button" class="small-button" data-notes-toggle="'+escape(id)+'">Collapse notes</button></div><div class="vehicle-notes-fields"><label><span>Vehicle notes</span><textarea name="notes" rows="3" maxlength="4000" placeholder="Customer requests, conversations or delivery notes…"'+(disabled?' disabled':'')+'>'+escape(data.notes||'')+'</textarea></label><label><span>Custom information</span><textarea name="custom_information" rows="3" maxlength="4000" placeholder="Other details you want to keep with this vehicle…"'+(disabled?' disabled':'')+'>'+escape(data.custom_information||'')+'</textarea></label></div><div class="vehicle-notes-actions"><button type="submit" class="primary"'+(disabled?' disabled':'')+'>'+(busy.has(id)?'Saving…':'Save notes')+'</button><button type="button" class="small-button" data-notes-reload="'+escape(id)+'"'+(busy.has(id)?' disabled':'')+'>Reload saved notes</button><span class="vehicle-notes-status" role="status" aria-live="polite">'+escape(messages.get(id)||loadError||(draft?'Unsaved changes':!loaded?'Loading notes…':record?'Saved '+new Date(record.updated_at).toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'}):'No staff notes yet'))+'</span></div></form>';
  }
  function rowHtml(row){const html=editorHtml(row);return html?'<tr class="vehicle-notes-row"><td colspan="13">'+html+'</td></tr>':'';}
  function capture(form){
   const id=form?.dataset?.notesForm;if(!id||!syncScope()||!editable(id)||busy.has(id)||!loaded)return;
   const notes=form.elements.namedItem('notes').value,custom_information=form.elements.namedItem('custom_information').value;
   drafts.set(id,{notes,custom_information,version:drafts.get(id)?.version??records.get(id)?.version??0});messages.delete(id);
   const status=form.querySelector('.vehicle-notes-status');if(status)status.textContent='Unsaved changes';
  }
  async function save(form){
   capture(form);const id=form?.dataset?.notesForm,draft=drafts.get(id);
   if(!draft||busy.has(id)||!loaded||!editable(id)||options?.isHidden?.())return;
   const epoch=generation,who=user();busy.add(id);messages.delete(id);repaint();
   try{
    const {data,error}=await host.PDC_SUPABASE.rpc('save_broome_sales_vehicle_notes',{p_tracking_id:id,p_notes:draft.notes,p_custom_information:draft.custom_information,p_expected_version:draft.version});
    if(epoch!==generation||who!==user()||!allowed(id))return;
    if(error)throw error;
    if(data?.tracking_id!==id||!Number.isInteger(data.version)||data.version<1||data.notes!==draft.notes||data.custom_information!==draft.custom_information)throw new Error('The saved notes could not be confirmed. Your draft has been kept; retry saving.');
    records.set(id,data);drafts.delete(id);messages.set(id,'Notes saved.');
   }catch(error){if(epoch===generation&&who===user()&&allowed(id))messages.set(id,(error.message||'Notes could not be saved.')+' Your draft is kept. Retry saving, or use Reload saved notes to discard your draft and see the latest saved version.');}
   finally{if(epoch===generation&&who===user()){busy.delete(id);repaint();}}
  }
  function bind(container){
   if(!container)return;
   container.addEventListener('input',event=>capture(event.target.closest('[data-notes-form]')));
   container.addEventListener('submit',event=>{const form=event.target.closest('[data-notes-form]');if(form){event.preventDefault();save(form);}});
   container.addEventListener('click',event=>{
    const toggleButton=event.target.closest('[data-notes-toggle]');if(toggleButton){toggle(toggleButton.dataset.notesToggle);return;}
    const reload=event.target.closest('[data-notes-reload]');if(reload&&!busy.has(reload.dataset.notesReload)){drafts.delete(reload.dataset.notesReload);messages.delete(reload.dataset.notesReload);load();return;}
    if(event.target.closest('button,input,select,textarea,a,label,[data-resize]'))return;
    const row=event.target.closest('[data-note-row]');if(row)toggle(row.dataset.noteRow);
   });
   container.addEventListener('keydown',event=>{if(['Enter',' '].includes(event.key)&&event.target.matches?.('[data-note-row]')){event.preventDefault();toggle(event.target.dataset.noteRow);}});
  }
  function init(config){
   options=config;clear();bind(host.document.getElementById('vehicle-table'));bind(host.document.getElementById('sales-mobile-vehicles'));
   host.document.getElementById('sales-expand-notes')?.addEventListener('click',()=>{if(!syncScope()||options.isHidden?.())return;for(const row of options.getVisibleRows())if(allowed(row.tracking_id))expanded.add(row.tracking_id);repaint();});
   host.document.getElementById('sales-collapse-notes')?.addEventListener('click',()=>{expanded.clear();repaint();});
   host.addEventListener?.('pdc-auth-locked',clear);host.addEventListener?.('pdc-auth-failed',clear);
   return api;
  }
  const api={init,clear,syncScope,load,toggleHtml,rowHtml,editorHtml,hasSavedNotes};return api;
 }
 if(typeof module==='object'&&module.exports)module.exports={create};
 if(root.document)root.BROOME_VEHICLE_NOTES=create(root);
})(typeof window==='object'?window:globalThis);
