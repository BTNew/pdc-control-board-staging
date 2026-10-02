
(function(root){
'use strict';
const DAY=86400000;
function dateKey(value){
 const text=String(value||'').trim();let m=/^(\d{4})-(\d{2})-(\d{2})(?:$|T)/.exec(text),y,mo,d;
 if(m){[,y,mo,d]=m;}else{m=/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(text);if(!m)return null;[,d,mo,y]=m;}
 y=Number(y);mo=Number(mo);d=Number(d);
 if(y<1900||y>2200)return null;
 const dt=new Date(Date.UTC(y,mo-1,d));
 if(dt.getUTCFullYear()!==y||dt.getUTCMonth()+1!==mo||dt.getUTCDate()!==d)return null;
 return dt.toISOString().slice(0,10);
}
function perthToday(now=new Date()){
 const p=new Intl.DateTimeFormat('en-AU',{timeZone:'Australia/Perth',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 const get=k=>p.find(x=>x.type===k).value;return get('year')+'-'+get('month')+'-'+get('day');
}
function etaInfo(value,today=perthToday()){
 const key=dateKey(value),current=dateKey(today);
 if(!key||!current)return {date:'Not recorded',label:'',tone:'unknown',days:null};
 const delta=Math.round((Date.parse(key+'T00:00:00Z')-Date.parse(current+'T00:00:00Z'))/DAY);
 const [y,m,d]=key.split('-'),n=Math.abs(delta);
 return {date:d+'/'+m+'/'+y,label:delta>0?'Due in '+n+' day'+(n===1?'':'s'):delta<0?n+' day'+(n===1?'':'s')+' past ETA':'Due today',tone:delta<0?'past':'due',days:delta};
}
const defaults=[60,110,90,160,180,135,135,135,185,125,200,185,48,165];
function width(value,fallback){return typeof value==='number'&&Number.isFinite(value)?Math.max(40,Math.min(600,Math.round(value))):fallback;}
function readWidths(text){try{const a=JSON.parse(text);return defaults.map((v,i)=>width(Array.isArray(a)?a[i]:null,v));}catch{return defaults.slice();}}
function initColumns(table,reset){
 if(!table?.querySelectorAll)return;
 const key='broome-sales-column-widths-v2';
 let widths=defaults.slice(),drag=null;
 try{widths=readWidths(root.localStorage?.getItem(key));}catch{}
 function save(){try{root.localStorage?.setItem(key,JSON.stringify(widths));}catch{}}
 function apply(){
  const cols=table.querySelectorAll('col');
  cols.forEach((col,i)=>{col.style.width=widths[i]+'px';});
  table.querySelectorAll('[data-resize]').forEach(handle=>handle.setAttribute('aria-valuenow',String(widths[Number(handle.dataset.resize)])));
  const total=widths.reduce((a,b)=>a+b,0);table.style.width=total+'px';table.style.minWidth=total+'px';
 }
 function finish(){if(drag){drag=null;save();}}
 table.addEventListener('pointerdown',e=>{
  const h=e.target.closest('[data-resize]');if(!h||e.button!==0)return;
  e.preventDefault();e.stopPropagation();const i=Number(h.dataset.resize);
  if(!Number.isInteger(i)||i<0||i>=defaults.length)return;
  drag={i,x:e.clientX,start:widths[i],pointer:e.pointerId};h.setPointerCapture?.(e.pointerId);
 });
 table.addEventListener('pointermove',e=>{if(!drag||e.pointerId!==drag.pointer)return;widths[drag.i]=width(drag.start+e.clientX-drag.x,defaults[drag.i]);apply();});
 table.addEventListener('pointerup',finish);table.addEventListener('pointercancel',finish);table.addEventListener('lostpointercapture',finish);
 table.addEventListener('keydown',e=>{
  const h=e.target.closest('[data-resize]');if(!h)return;const i=Number(h.dataset.resize);
  if(!Number.isInteger(i)||i<0||i>=defaults.length)return;
  if(!['ArrowLeft','ArrowRight','Home'].includes(e.key))return;
  e.preventDefault();e.stopPropagation();widths[i]=e.key==='Home'?defaults[i]:width(widths[i]+(e.key==='ArrowRight'?1:-1)*(e.shiftKey?40:10),defaults[i]);apply();save();
 });
 table.addEventListener('dblclick',e=>{const h=e.target.closest('[data-resize]');if(h){const i=Number(h.dataset.resize);widths[i]=defaults[i];apply();save();}});
 reset?.addEventListener('click',()=>{widths=defaults.slice();apply();save();});
 return {apply,clear:finish};
}
const api={dateKey,perthToday,etaInfo,readWidths,defaults,initColumns};
if(typeof module==='object'&&module.exports)module.exports=api;
root.BROOME_SALES_TOOLS=api;
})(typeof window==='object'?window:globalThis);
