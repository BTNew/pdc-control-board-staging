(function(root){
'use strict';
const types=[['released','Vehicle Released to Broome'],['update','Request Update'],['build','New Vehicle Build'],['tint','Tint PO Email']];
const recipients={released:'',update:'',build:'',tint:'jono@performancetinting.com.au'};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const oneLine=v=>String(v??'').replace(/[\r\n\u0000-\u001f\u007f]+/g,' ').trim();
function template(kind,row){
 if(!types.some(([k])=>k===kind))throw new Error('Choose an email action.');
 const stock=oneLine(row.stock),order=oneLine(row.order),id=stock||'Toyota order '+(order||'not recorded');
 const vehicle=oneLine(row.vehicle)||'Not recorded',customer=oneLine(row.client)||'Not recorded';
 const facts=(stock?'Stock number: '+stock:'Toyota order: '+(order||'Not recorded')+'\nStock number: Awaiting allocation')+'\nCustomer Name: '+customer+'\nVehicle: '+vehicle;
 const titles={released:'Vehicle released to Broome - ',update:'Request update - ',build:'New vehicle order for ',tint:'Tint PO - '};
 let body=facts+'\n\nKind Regards,';
 if(kind==='tint')body='Hi Jono,\n\nPlease see tint PO request for the vehicle below.\n\n'+body;
 if(kind==='build'){
  const eta=root.BROOME_SALES_TOOLS?.etaInfo(row.kewdale_eta).date||row.kewdale_eta||'Not recorded';
  body='Hi Guys,\n\nNew vehicle order for\n\n'+id+' - '+vehicle+'\n\nFor\n\n'+customer+
   '\n\nBroome to supply all parts on the 131 Parts PO (direct to Welshpool).\n\nPMG to supply parts listed on the PMG sublet order and fit all items to the vehicle.'+
   (row.navision_notes?'\n\nVehicle / build notes: '+String(row.navision_notes):'')+
   '\n\nKewdale ETA: '+eta+
   '\n\nJust let me know if you have any queries, or if there is an extended delay in parts.\n\nKind Regards,';
 }
 return {to:recipients[kind],cc:'',subject:titles[kind]+id+(kind==='build'?' - PMG Build':''),body};
}
function addresses(text,required=false){
 const s=String(text||'').trim();if(!s){if(required)throw new Error('Enter the recipient email address.');return '';}
 const parts=s.split(/[;,]/).map(x=>x.trim());
 if(parts.length>20||parts.some(x=>!/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$/.test(x)))throw new Error('Use email addresses separated by commas or semicolons.');
 return parts.join(', ');
}
function base64(bytes){
 if(typeof Buffer==='function')return Buffer.from(bytes).toString('base64');
 let text='';for(let i=0;i<bytes.length;i+=8192)text+=String.fromCharCode(...bytes.subarray(i,i+8192));return root.btoa(text);
}
const utf8=s=>new TextEncoder().encode(String(s));
const folded=b=>(b.match(/.{1,76}/g)||[]).join('\r\n');
function encodedHeader(text){
 // Split at code point boundaries so every encoded word is independently valid UTF-8.
 const words=[];let chunk='';for(const c of oneLine(text)){if(utf8(chunk+c).length>42){words.push('=?UTF-8?B?'+base64(utf8(chunk))+'?=');chunk='';}chunk+=c;}
 if(chunk)words.push('=?UTF-8?B?'+base64(utf8(chunk))+'?=');return words.join('\r\n ');
}
function attachmentLimits(files){
 if(files.length>10)throw new Error('Choose up to 10 files.');
 if(files.some(f=>!Number.isFinite(f.size)||f.size<0||f.size>10*1024*1024)||files.reduce((n,f)=>n+f.size,0)>20*1024*1024)throw new Error('Each attachment must be 10 MB or less; total attachments must be 20 MB or less.');
}
function eml(draft,attachments=[],boundary='broome_'+(root.crypto?.randomUUID?.()||Date.now().toString(36))){
 const to=addresses(draft.to,true),cc=addresses(draft.cc);
 if(!/^[A-Za-z0-9_-]{1,80}$/.test(boundary))throw new Error('Invalid message boundary.');
 if(!oneLine(draft.subject))throw new Error('Enter an email subject.');
 attachmentLimits(attachments.map(a=>({size:a.bytes?.length??-1})));
 const head=['X-Unsent: 1','To: '+to];if(cc)head.push('Cc: '+cc);
 head.push('Subject: '+encodedHeader(draft.subject),'MIME-Version: 1.0','Content-Type: multipart/mixed; boundary="'+boundary+'"','','This is a multipart message in MIME format.');
 const alt=boundary+'_body';head.push('--'+boundary,'Content-Type: multipart/alternative; boundary="'+alt+'"','');
 for(const [type,text] of [['text/plain',draft.body],['text/html','<!doctype html><html><body><div style="font-family:Arial,sans-serif;white-space:pre-wrap">'+esc(draft.body)+'</div></body></html>']]){
  head.push('--'+alt,'Content-Type: '+type+'; charset=UTF-8','Content-Transfer-Encoding: base64','',folded(base64(utf8(text))));
 }
 head.push('--'+alt+'--');
 for(const a of attachments){
  const name=oneLine(a.name)||'attachment',safe=name.replace(/[^\x20-\x7e]|["\\]/g,'_').slice(0,80)||'attachment';
  const ext=encodeURIComponent(name).replace(/['()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
  head.push('--'+boundary,'Content-Type: application/octet-stream','Content-Transfer-Encoding: base64',"Content-Disposition: attachment; filename*=UTF-8''"+ext+';', ' filename="'+safe+'"','',folded(base64(a.bytes)));
 }
 head.push('--'+boundary+'--','');return head.join('\r\n');
}
function mailto(draft){
 const to=addresses(draft.to,true),cc=addresses(draft.cc);
 if(!oneLine(draft.subject))throw new Error('Enter an email subject.');
 const url='mailto:'+to.split(', ').map(encodeURIComponent).join(',')+'?subject='+encodeURIComponent(oneLine(draft.subject))+'&body='+encodeURIComponent(draft.body)+(cc?'&cc='+encodeURIComponent(cc):'');
 if(url.length>7500)throw new Error('This email is long. Download the email file instead.');return url;
}
let options=null,active=null,epoch=0,busy=false;
const $=id=>root.document.getElementById(id);
function scopeToken(){return options?.getToken?.();}
function current(){return active&&active.token===scopeToken()&&options.getRows().some(r=>r.tracking_id===active.id);}
function clear(){
 epoch++;active=null;busy=false;
 const dialog=$('sales-email');if(dialog?.open)dialog.close();
 for(const id of ['sales-email-to','sales-email-cc','sales-email-subject','sales-email-body','sales-email-files'])if($(id))$(id).value='';
 if($('sales-email-status'))$('sales-email-status').textContent='';
 if($('sales-email-title'))$('sales-email-title').textContent='Create email';
 if($('sales-email-download'))$('sales-email-download').disabled=false;
}
function syncScope(){if(active&&!current())clear();}
function open(kind,id){
 const row=options.getRows().find(r=>r.tracking_id===id);if(!row)return;
 clear();const d=template(kind,row);active={id,token:scopeToken()};
 $('sales-email-title').textContent=types.find(([k])=>k===kind)?.[1]||'Create email';
 for(const key of ['to','cc','subject','body'])$('sales-email-'+key).value=d[key];
 $('sales-email-files').value='';$('sales-email-status').textContent='';$('sales-email').showModal();
}
function readDraft(){if(!current()){clear();throw new Error('Vehicle access changed. Reopen the email from your dashboard.');}
 return Object.fromEntries(['to','cc','subject','body'].map(k=>[k,$('sales-email-'+k).value]));}
function status(text){$('sales-email-status').textContent=text;}
async function download(){
 if(busy)return;let run=epoch;
 try{
  const draft=readDraft(),files=Array.from($('sales-email-files').files||[]);addresses(draft.to,true);addresses(draft.cc);attachmentLimits(files);
  busy=true;$('sales-email-download').disabled=true;status('Preparing email…');
  const attachments=await Promise.all(files.map(async f=>({name:f.name,bytes:new Uint8Array(await f.arrayBuffer())})));
  if(run!==epoch||!current())return;
  const message=eml(draft,attachments),blob=new root.Blob([message],{type:'message/rfc822'});
  const url=root.URL.createObjectURL(blob),a=root.document.createElement('a');
  a.href=url;a.download=oneLine(draft.subject).replace(/[^A-Za-z0-9._-]/g,'_').slice(0,100)+'.eml';
  root.document.body.appendChild(a);a.click();a.remove();root.setTimeout(()=>root.URL.revokeObjectURL(url),1000);
  status('Email downloaded with '+attachments.length+' attachment'+(attachments.length===1?'':'s')+'. Open it in Outlook, check the attachments and add your signature before sending.');
 }catch(e){if(run===epoch)status(e.message||'Could not prepare the email.');}
 finally{if(run===epoch){busy=false;$('sales-email-download').disabled=false;}}
}
function openMail(){
 try{
  const d=readDraft();
  if($('sales-email-files').files?.length)throw new Error('Use Download email to include the files you selected. Opening the email app does not attach files.');
  const url=mailto(d);root.location.href=url;status('Email prepared in your email app. Review it before sending.');
 }catch(e){if(active)status(e.message);}
}
function init(opts){
 options=opts;
 $('sales-email-close').addEventListener('click',clear);$('sales-email').addEventListener('close',()=>{if(!$('sales-email').open)clear();});
 $('sales-email-download').addEventListener('click',download);$('sales-email-open').addEventListener('click',openMail);
}
const api={types,template,addresses,attachmentLimits,eml,mailto,init,open,clear,syncScope};
if(typeof module==='object'&&module.exports)module.exports=api;
root.BROOME_SALES_EMAIL=api;
})(typeof window==='object'?window:globalThis);
