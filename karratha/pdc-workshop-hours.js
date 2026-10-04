/* Administrator action for Craig's 06:00–16:30 weekday calendar. */
(() => {
  'use strict';
  let loaded=false,busy=false;
  const host=()=>document.getElementById('workshop-hours-setting');
  async function rpc(name) {
    const config=window.PDC_SUPABASE_CONFIG, actor=window.PDC_AUTH_CONTEXT?.userId;
    const token=typeof getPdcSupabaseAccessToken==='function'?getPdcSupabaseAccessToken():'';
    if(!actor||!token||window.PDC_AUTH_CONTEXT?.role!=='administrator'||config?.projectRef!=='cdsmnqxtyyoeoznmbidd') throw Error('Administrator access is required.');
    const response=await fetch(config.url.replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:config.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:'{}'});
    const data=await response.json();
    if(actor!==window.PDC_AUTH_CONTEXT?.userId)throw Error('Your sign-in changed. Refresh Setup.');
    if(!response.ok||data?.ok!==true) throw Error('The calendar change could not be confirmed. Refresh Setup before trying again.');
    return data;
  }
  async function render() {
    const root=host();if(!root||busy)return;
    root.replaceChildren();
    const title=document.createElement('h2');title.textContent='Workshop hours';root.append(title);
    try {
      const data=await rpc('get_workshop_hours_for_setup');
      const note=document.createElement('p');note.textContent=`Monday–Friday · ${data.settings.day_start_time}–${data.settings.day_end_time} · Perth time. Weekends closed.`;root.append(note);
      if(data.settings.day_start_time==='06:00'&&data.settings.day_end_time==='16:30')return;
      const button=document.createElement('button');button.type='button';button.textContent='Set 6:00 am–4:30 pm';root.append(button);
      const explanation=document.createElement('p');explanation.textContent='Adjusts planned bookings to keep their work time, bay assignments and the one-hour vehicle handover. Work already started stays in place.';root.append(explanation);
      button.addEventListener('click',async()=>{
        if(busy)return;busy=true;button.disabled=true;button.textContent='Updating hours and planned bookings…';
        try {const result=await rpc('set_workshop_hours_0600_1630');explanation.textContent=`Hours saved. ${result.changed_bookings} planned bookings adjusted.`;button.textContent='6:00 am–4:30 pm saved';note.textContent='Monday–Friday · 06:00–16:30 · Perth time. Weekends closed.';}
        catch(error){explanation.textContent=error.message;button.textContent='Refresh Setup to check the result';}
        finally{busy=false;}
      });
    } catch(error){const p=document.createElement('p');p.textContent=error.message;root.append(p);}
  }
  window.PdcWorkshopHours={open(){if(!loaded){loaded=true;void render();}},reset(){loaded=false;}};
  window.addEventListener('pdc-auth-locked',()=>{loaded=false;host()?.replaceChildren();});
})();
