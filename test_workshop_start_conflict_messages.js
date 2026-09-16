'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
const start=source.indexOf('function workshopDescribeSharedActionError('),end=source.indexOf('function workshopPersistPlanAction(',start);
const c={workshopAdministratorCanMove:()=>true,workshopAdministratorErrorDetail:r=>r.error};vm.createContext(c);vm.runInContext(source.slice(start,end),c);
test('booking protection messages explain the blocker without raw database codes',()=>{
 for(const code of ['fixed_booking_conflict','live_booking_conflict','admin_block_conflict','schedule_changed','schedule_write_order_blocked','technician_unavailable']){
  const message=c.workshopDescribeSharedActionError({error:code});assert.ok(message.length>40);assert.ok(!message.includes(code));assert.ok(!message.includes('server rejected'));
 }
});
