/* Conversion sections are saved through the existing assigned-technician command. */
(function(root){
 'use strict';
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const duration=m=>m==null?'Unknown':`${Math.floor(m/60)}h ${Math.round(m%60)}m`;
 const hours=m=>m==null?'':Number((m/60).toFixed(3));
 const draft=new Map(); let pending='';
 const n=(name,label,value,disabled)=>`<label>${esc(label)}<input name="${name}" type="number" min="0" max="10000" step="any" value="${hours(value)}" ${disabled}></label>`;
 const text=(name,label,value,disabled,max=500)=>`<label>${label}<textarea name="${name}" maxlength="${max}" rows="2" ${disabled}>${esc(value)}</textarea></label>`;
 function formKey(booking,line,part){return `${booking}|${line.line_identity}|${line.scope_hash}|${part}`;}
 function html(line,{editable=false,controller=false,booking=''}={}){
  const c=line.conversion;if(!c)return '';
  if(c.needs_review)return `<article class="fitter-line conversion"><h4>${esc(line.description)}</h4><p class="fitter-warning">4×4 Conversion — model or scope needs review. A controller must confirm the vehicle model and conversion scope before its checklist can be used.</p></article>`;
  const disabled=editable?'':'disabled',m=c.metadata||{};
  const form=(part,content)=>`<form class="conversion-form" data-conversion-form="${esc(formKey(booking,line,part))}" data-conversion-line="${esc(line.line_identity)}" data-conversion-mode="${part.startsWith('section:')?'section':part}" ${part.startsWith('section:')?`data-conversion-section="${esc(part.slice(8))}"`:''}>${content}</form>`;
  const sections=c.sections.map(s=>`<details class="conversion-section ${s.status==='complete'?'is-done':''}" ${s.status==='in_progress'||draft.has(formKey(booking,line,'section:'+s.id))?'open':''}><summary><span>${s.status==='complete'?'✓':'○'} ${esc(s.label)} — ${esc(s.description)}</span><b>${duration(s.planned_minutes)}</b></summary>
    <p>Actual: ${duration(s.actual_minutes)} · Remaining: ${duration(s.remaining_minutes)} · ${esc(s.technician||'Technician not yet recorded')}</p>
    ${s.provisional?`<p class="fitter-warning">Section 12 remains provisional until the applicable manufacturer checklist and scope are confirmed. ${c.release_blocked?'Release blocked.':`Reference: ${esc(m.checklist_reference)}. Scope: ${esc(m.checklist_scope)}`}</p>`:''}
    ${s.blocker||s.deferred?`<p class="fitter-warning">${esc(s.blocker)} ${s.deferred?'Deferred: '+esc(s.deferred):''}</p>`:''}
    ${form('section:'+s.id,`<div class="conversion-fields"><label>Section status<select name="status" ${disabled}><option value="not_started" ${s.status==='not_started'?'selected':''}>Not started</option><option value="in_progress" ${s.status==='in_progress'?'selected':''}>Current section / in progress</option></select></label><label><input type="checkbox" name="completed" ${s.status==='complete'?'checked':''} ${disabled}> Section completed — workshop confirmed</label>${n('actual_minutes','Actual main-technician hours (total for this section)',s.actual_minutes,disabled)}${n('remaining_minutes','Estimated hours remaining',s.remaining_minutes,disabled)}</div>${text('blocker','Blocker',s.blocker,disabled)}${text('deferred','Deferred tightening, connections or checks',s.deferred,disabled)}${text('note','Workshop update / completion evidence',s.note,disabled)}<small>Confirm only work actually completed. For pre-assembly completed before this booking, confirm here; leave actual time blank if unknown. Helper time is recorded separately below.</small><button ${disabled}>Save section update</button>`)}
   </details>`).join('');
  const extras=[['helper_minutes','Helper labour'],['parts_delay_minutes','Parts delays elapsed'],['waiting_minutes','Other waiting elapsed'],['repair_minutes','Additional repairs labour'],['rework_minutes','Rework labour']];
  const promised=m.promised_at?new Date(Date.parse(m.promised_at)+8*3600000).toISOString().slice(0,16):'';
  return `<article class="fitter-line conversion ${c.complete?'is-done':''}"><h4>4×4 Conversion · ${esc(c.model)} ${c.complete?'✓ Complete':''}</h4>
   <p>${esc(line.description)} · Original operation: ${esc(line.hours??'Unknown')} h</p>
   <p><strong>Planning allowance ${duration(c.total_minutes)}</strong> · Pre-assembly ${duration(c.preassembly_minutes)} · Installation ${duration(c.installation_minutes)}</p>
   <p class="fitter-source-note">${esc(c.note)} One main technician, with lifting/positioning help recorded separately. Section allowances are not additional booking hours.</p>
   <p><strong>${esc(c.risk)}</strong> · Current: ${esc(c.current_sections?.join(', ')||'No current section reported')} · Remaining ${duration(c.remaining_minutes)} · Recorded actual ${duration(c.actual_minutes)}${c.actual_complete?'':' (some actual times unknown)'}</p>
   ${c.release_blocked?'<p class="fitter-warning">Release blocked: manufacturer completion checklist and scope confirmation required.</p>':''}
   <p>${c.comparable_builds||0} of 3 comparable timed builds recorded${c.allowance_review_due?` — allowance review due; first-three mean ${duration(c.first_three_average_minutes)}`:''}.</p>
   <div class="conversion-sections">${sections}</div>
   <details class="conversion-planning" ${draft.has(formKey(booking,line,'planning'))?'open':''}><summary>Completion forecast, helper labour, delays and extra work</summary>
    ${form('planning',`<div class="conversion-fields"><label>Promised completion (Perth)<input type="datetime-local" name="promised_at" value="${esc(promised)}" ${disabled}></label>${n('available_minutes','Main-technician hours available from now to the promised date (workshop confirmed)',m.available_minutes,disabled)}${n('delay_remaining_minutes','Known delay hours still ahead',m.delay_remaining_minutes,disabled)}${extras.map(([k,l])=>n(k,l+' — cumulative hours',m[k],disabled)).join('')}</div><label><input type="checkbox" name="comparable" ${m.comparable!==false?'checked':''} ${disabled}> Comparable standard build for allowance review</label>${text('note','Planning / delay / extra-work details',m.planning_note,disabled)}<small>Report available capacity again when plans change. Blank progress, hours or delay estimates show “Progress update required”. Separate labour and elapsed delays do not increase the original conversion allowance.</small><button ${disabled}>Save planning update</button>`)}
   </details>
   ${controller?`<details><summary>Controller: confirm manufacturer completion checklist</summary>${form('checklist',`${text('reference','Applicable manufacturer checklist title / revision / reference',m.checklist_reference,disabled)}${text('scope','Confirmed checklist scope and where the workshop can access it',m.checklist_scope,disabled,1000)}<small>Obtain and check the applicable document before confirming. This does not complete Section 12.</small><button ${disabled}>Confirm checklist scope</button>`)}</details>`:''}
   </article>`;
 }
 function payload(form){
  const d=new FormData(form),mode=form.dataset.conversionMode,out={mode};
  const number=k=>{const raw=d.get(k);return raw==null||raw===''?null:Math.round(Number(raw)*60*100)/100;};
   if(mode==='section'){Object.assign(out,{section:form.dataset.conversionSection,status:d.has('completed')?'complete':d.get('status'),actual_minutes:number('actual_minutes'),remaining_minutes:number('remaining_minutes'),blocker:d.get('blocker'),deferred:d.get('deferred'),note:d.get('note')});}
  if(mode==='planning'){for(const k of ['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','available_minutes','delay_remaining_minutes'])out[k]=number(k);Object.assign(out,{promised_at:d.get('promised_at')?new Date(d.get('promised_at')+':00+08:00').toISOString():null,note:d.get('note'),comparable:d.has('comparable')});}
  if(mode==='checklist')Object.assign(out,{reference:d.get('reference'),scope:d.get('scope')});
  return out;
 }
 function bind(host,save){
  host.querySelectorAll('[data-conversion-form]').forEach(form=>{
   const key=form.dataset.conversionForm,cached=draft.get(key);
   if(cached)for(const [name,value]of Object.entries(cached)){const field=form.elements.namedItem(name);if(field){if(field.type==='checkbox')field.checked=value;else field.value=value;}}
   form.addEventListener('input',()=>{const values={};for(const field of form.elements)if(field.name)values[field.name]=field.type==='checkbox'?field.checked:field.value;draft.set(key,values);host.querySelector('[data-fitter-action="complete"]')?.setAttribute('disabled','');});
   form.addEventListener('submit',event=>{event.preventDefault();if(!form.reportValidity())return;const p=payload(form);pending=key;void save(form.dataset.conversionLine,p);});
  });
 }
 const api={html,payload,bind,duration,hasDrafts:()=>draft.size>0,confirmSave:()=>{draft.delete(pending);pending='';},reset:()=>{draft.clear();pending='';}};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.PdcConversions=api;
})(typeof window==='undefined'?globalThis:window);

