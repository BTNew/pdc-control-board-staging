/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
(function(root){
'use strict';
const types=[['production_planned','Production planned'],['vehicle_built','Vehicle built'],['perth_eta','Perth ETA received']];
// r519 (F133): Outlook supplies the signature. No salesperson phone, email or sign-off in the message.
function template(kind){
 const greeting='Hi {{customer_first_name}},\n\n';
 if(kind==='production_planned')return {subject:'Your {{vehicle_model}} - production planned',body:greeting+
  'Your {{vehicle_model}} is planned for production in {{production_month}}. Timing can change. I will let you know once we get confirmation that your vehicle has been built.'};
 if(kind==='vehicle_built')return {subject:'Your {{vehicle_model}} has been built',body:greeting+
  'Just letting you know your {{vehicle_model}} has been built. We are waiting on shipping and tracking details, and I will send another update when those come through.'};
 if(kind==='perth_eta')return {subject:'Your {{vehicle_model}} - estimated Perth arrival',body:greeting+
  'Your {{vehicle_model}} has an estimated arrival into Kewdale, Perth, of {{perth_eta_date}}. That date can move with shipping, port clearances, customs and other factors.\n\n'+
  'That is the estimated Perth arrival, not your handover date. I will update you closer to arrival and confirm handover when we can.\n\n'+
  'In the meantime, please download the myToyota Connect app and create or activate your account. Let me know when it is ready so we can add your vehicle.'};
 throw new Error('Choose a customer update.');
}
const oneLine=v=>String(v??'').replace(/[\r\n\u0000-\u001f\u007f]/g,' ').trim();
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const keys=['customer_first_name','vehicle_model','production_month','perth_eta_date'];
function fill(text,values){return text.replace(/\{\{([a-z_]+)\}\}/g,(token,key)=>keys.includes(key)&&oneLine(values[key])?oneLine(values[key]):token);}
function monthLabel(value){
 const m=/^(0?[1-9]|1[0-2])\/(\d{2}|\d{4})$/.exec(String(value||''));
 if(!m)return '';
 const y=Number(m[2].length===2?'20'+m[2]:m[2]);
 return new Intl.DateTimeFormat('en-AU',{month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(Date.UTC(y,Number(m[1])-1,1)));
}
function titleCaseWord(word){
 const clean=String(word||'').replace(/[^A-Za-z'-]/g,'');
 if(!clean)return '';
 return clean.charAt(0).toUpperCase()+clean.slice(1).toLowerCase();
}
function firstNameFromClient(client){
 const raw=oneLine(client);
 if(!raw)return '';
 if(raw.includes(',')){
  const after=(raw.split(',')[1]||'').trim().split(/\s+/)[0]||'';
  return titleCaseWord(after);
 }
 if(/\b(pty\.?|ltd\.?|limited|company|co\.|trust|group|holdings|enterprises|services|incorporated|inc\.?|plc)\b/i.test(raw))return '';
 const first=raw.split(/\s+/)[0]||'';
 if(/^(the|and|&|t\/as|ta)$/i.test(first))return '';
 return titleCaseWord(first);
}
function draftText(draft,row={}){
 const base=template(draft.template_kind),facts=draft.facts||{};
 const eta=root.BROOME_SALES_TOOLS?.etaInfo(facts.perth_eta_date);
 const first=oneLine(draft.facts?.customer_first_name)||firstNameFromClient(row.client);
 const values={customer_first_name:first,vehicle_model:facts.vehicle_model,production_month:monthLabel(facts.production_month),
  perth_eta_date:eta?.days!==null?eta?.date:''};
 return {recipient:draft.recipient||row.crm_contact?.email||'',subject:draft.subject||fill(base.subject,values),body:draft.body||fill(base.body,values),customer_first_name:first};
}
function validate(data){
 if(/[\r\n]/.test(data.recipient||'')||!/^[A-Za-z0-9.!#$%&'*+/=?^_{|}~-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$/.test(data.recipient||''))throw new Error('Enter one customer email address.');
 if(!String(data.subject||'').trim()||!String(data.body||'').trim())throw new Error('Complete the subject and message.');
 if(/[\r\n]/.test(data.subject)||data.subject.length>250||data.body.length>20000||data.recipient.length>320)throw new Error('Check the email field lengths and subject.');
 if(/\{\{[^}]*\}\}/.test(data.recipient+data.subject+data.body))throw new Error('Complete all {{placeholders}} before preparing this email.');
 return data;
}
function openMailto(url){
 if(!url||!root.document)return;
 const a=root.document.createElement('a');
 a.href=url;a.rel='noopener';a.style.display='none';
 root.document.body.appendChild(a);a.click();a.remove();
}
const api={types,template,fill,monthLabel,firstNameFromClient,draftText,validate,openMailto};
if(typeof module==='object'&&module.exports)module.exports=api;
root.BROOME_CUSTOMER_EMAILS=api;
if(!root.document)return;
const $=id=>root.document.getElementById(id);
let options,queue=[],error='',capturePending=false,active=null,busy=false,epoch=0,request=0,principal='';
const title=k=>types.find(([key])=>key===k)?.[1]||'Customer update';
const token=()=>options?.getToken?.();
const rows=()=>options?.getRows?.()||[];
const visible=()=>queue.filter(d=>rows().some(r=>r.tracking_id===d.tracking_id));
function close(){active=null;busy=false;$('customer-email-dialog').close();for(const id of ['to','subject','body','first-name'])$('customer-email-'+id).value='';$('customer-email-status').textContent='';}
function clear(){epoch++;request++;queue=[];error='';capturePending=false;principal=token();close();$('sales-customeremails').innerHTML='';}
function syncScope(){
 if(token()!==principal){clear();return;}
 if(active&&!visible().some(d=>d.id===active.id))close();
}
function render(){
 syncScope();if(!options?.getContext?.()){ $('sales-customeremails').innerHTML='';return; }
 const list=visible(),pending=list.filter(d=>['draft','prepared'].includes(d.status)),past=list.filter(d=>!['draft','prepared'].includes(d.status));
 function cards(items){return items.map(d=>{
  const row=rows().find(r=>r.tracking_id===d.tracking_id),label=row?.stock||'Toyota order '+(row?.order||'');
  return '<article class="customer-email-card"><div><h3>'+esc(title(d.template_kind))+'</h3><p>'+esc(label)+' · '+esc(d.facts?.vehicle_model||row?.vehicle||'')+'</p><p>'+esc(row?.client||'')+'</p><span class="customer-email-state">'+esc(({draft:'Ready for review',prepared:'Prepared - confirm after sending',sent:'Marked as sent',skipped:'Dismissed',superseded:'Replaced by a newer update'})[d.status]||d.status)+'</span></div><button class="small-button" data-customer-review="'+esc(d.id)+'" type="button">'+(d.status==='draft'?'Review email':'View email')+'</button></article>';
 }).join('');}
 $('sales-customeremails').innerHTML='<section class="panel"><div class="panel-header"><div><h2>Customer updates</h2><p>'+pending.length+' update'+(pending.length===1?'':'s')+' awaiting review or confirmation.</p></div><button class="small-button" data-customer-refresh type="button">Refresh customer emails</button></div><div class="customer-email-content"><p class="tracking-note">Navision status updates prepare drafts for your review, even while this page is closed. Review and send each email yourself, then mark it as sent. A downloaded draft is not recorded as sent. Dismiss removes an update from the awaiting list without deleting its history.</p><p class="tracking-note">An order\'s first import establishes its starting point. It does not create emails for old statuses. Repeated checks and imports reuse the same vehicle update.</p>'+
  (capturePending?'<p class="tracking-note" role="status">Some vehicle updates are waiting for a retry. Refresh customer emails to try again.</p>':'')+
  (error?'<p role="alert">'+esc(error)+'</p>':'')+(pending.length?cards(pending):'<p>No new customer updates to review.</p>')+
  '<details><summary>Earlier updates ('+past.length+')</summary>'+cards(past)+'</details><details><summary>Preview the three email templates</summary>'+types.map(([kind,label])=>{const t=template(kind);return '<h3>'+label+'</h3><strong>'+esc(t.subject)+'</strong><pre class="customer-template">'+esc(t.body)+'</pre>';}).join('')+'</details></div></section>';
}
async function refresh(){
 if(!options?.getContext?.()||!root.PDC_AUTH_CONTEXT)return;
 const generation=epoch,identity=token(),sequence=++request;
 try{
  const {data,error:rpcError}=await root.PDC_SUPABASE.rpc('get_broome_customer_emails');
  if(generation!==epoch||identity!==token()||sequence!==request)return;
  if(rpcError||!Array.isArray(data?.drafts)||!['administrator','salesperson'].includes(data.context?.role))throw rpcError||new Error('Customer emails could not be loaded.');
  queue=data.drafts;error='';capturePending=Number.isSafeInteger(data.capture_pending)&&data.capture_pending>0;
  if(active){const latest=visible().find(d=>d.id===active.id);if(!latest||latest.version!==active.version){close();error='An open update changed. Review the current version before continuing.';}}
 }catch(e){if(generation!==epoch||identity!==token()||sequence!==request)return;queue=[];capturePending=false;close();error=e.message||'Customer emails could not be loaded. Refresh to retry.';}
 render();
}
function open(id){
 syncScope();const d=visible().find(d=>d.id===id);if(!d)return;
 const row=rows().find(r=>r.tracking_id===d.tracking_id),text=draftText(d,row);
 active={...d};busy=false;$('customer-email-title').textContent=title(d.template_kind);
 $('customer-email-to').value=text.recipient;$('customer-email-subject').value=text.subject;$('customer-email-body').value=text.body;
 $('customer-email-first-name').value=text.customer_first_name||'';
 if(d.status==='draft'&&text.customer_first_name){
  const filled={customer_first_name:text.customer_first_name};
  $('customer-email-body').value=fill($('customer-email-body').value,filled);
  $('customer-email-subject').value=fill($('customer-email-subject').value,filled);
 }
 $('customer-email-state').textContent=d.status==='prepared'?'This draft has already been prepared. Mark it as sent after sending, or reopen it only if it was not sent.':d.status==='draft'?'Review all details and fill any remaining placeholders before preparing the email.':'This is a saved record of an earlier customer update.';
 for(const name of ['to','subject','body'])$('customer-email-'+name).readOnly=d.status!=='draft';
 $('customer-email-fill-fields').hidden=d.status!=='draft';
 for(const name of ['save','download','open','dismiss'])$('customer-email-'+name).hidden=d.status!=='draft';
 for(const name of ['sent','reopen'])$('customer-email-'+name).hidden=!(d.status==='prepared'&&d.can_manage_prepared);
 $('customer-email-status').textContent='';setBusy(false);$('customer-email-dialog').showModal();
}
function setBusy(value){busy=value;for(const name of ['save','download','open','dismiss','sent','reopen','fill']){const el=$('customer-email-'+name);if(el)el.disabled=value;}}
function data(){return {recipient:$('customer-email-to').value.trim(),subject:$('customer-email-subject').value,body:$('customer-email-body').value};}
async function action(kind){
 syncScope();if(!active||busy)return;
 const original={...active},generation=epoch,identity=token();let values={},eml,url;
 const rpcAction=kind==='dismiss'?'skip':(['download','open'].includes(kind)?'prepare':kind);
 try{
  if(['save','download','open'].includes(kind))values=data();
  if(['download','open'].includes(kind)){
   validate(values);const message={to:values.recipient,cc:'',subject:values.subject,body:values.body};
   // Construct the email before claiming the update. No external sending occurs here.
   if(kind==='download')eml=root.BROOME_SALES_EMAIL.eml(message,[]);
   else {
    url=root.BROOME_SALES_EMAIL.mailto(message);
    // Open while still in the click gesture. Awaiting the prepare RPC first blocks mailto in most browsers.
    openMailto(url);
   }
  }
  setBusy(true);
  const {data:result,error:rpcError}=await root.PDC_SUPABASE.rpc('save_broome_customer_email',{p_id:original.id,p_action:rpcAction,p_data:values,p_expected_version:original.version});
  if(generation!==epoch||identity!==token()||active?.id!==original.id||!rows().some(r=>r.tracking_id===original.tracking_id))return;
  if(rpcError||!result?.record)throw rpcError||new Error('The customer update was not saved.');
  queue=queue.map(d=>d.id===original.id?result.record:d);active={...result.record};
  if(kind==='download'){
   const blob=new Blob([eml],{type:'message/rfc822'}),href=root.URL.createObjectURL(blob),link=root.document.createElement('a');
   link.href=href;link.download='Customer_'+original.template_kind+'_'+original.id+'.eml';root.document.body.appendChild(link);link.click();link.remove();root.setTimeout(()=>root.URL.revokeObjectURL(href),1000);
  }
  if(['sent','skip','dismiss'].includes(kind)){close();render();return;}
  open(original.id);$('customer-email-status').textContent=kind==='save'?'Draft saved.':['download','open'].includes(kind)?'Email prepared. Send it in your email app, then return here and mark it as sent.':'Reopened. Check that no copy was already sent before preparing it again.';render();
 }catch(e){if(generation===epoch&&identity===token()&&active?.id===original.id)$('customer-email-status').textContent=e.message||'The email could not be prepared. Refresh to check its status before retrying.';}
 finally{if(generation===epoch&&identity===token()&&active?.id===original.id)setBusy(false);}
}
function init(settings){
 options=settings;principal=token();
 $('sales-customeremails').addEventListener('click',e=>{const t=e.target.closest('[data-customer-review],[data-customer-refresh]');if(t?.hasAttribute('data-customer-refresh'))refresh();else if(t)open(t.dataset.customerReview);});
 $('customer-email-close').addEventListener('click',close);$('customer-email-dialog').addEventListener('cancel',close);
 for(const name of ['save','download','open','dismiss','sent','reopen'])$('customer-email-'+name).addEventListener('click',()=>action(name));
 $('customer-email-fill').addEventListener('click',()=>{
  if(!active||active.status!=='draft'||busy)return;
  const values={customer_first_name:$('customer-email-first-name').value};
  $('customer-email-body').value=fill($('customer-email-body').value,values);$('customer-email-subject').value=fill($('customer-email-subject').value,values);
 });
}
Object.assign(api,{init,refresh,clear,syncScope,render});
})(typeof window==='object'?window:globalThis);
