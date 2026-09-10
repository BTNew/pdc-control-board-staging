'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const crypto=require('node:crypto');
const {controls,ready,collected,verifyDraft}=require('./pdc-rft-actions.js');
const v={__emailVehicleServerAuthoritative:true,__emailVehicleId:'synthetic-vehicle',__emailVehicleVersion:16,pdcQcComplete:true,rftTransferredAt:'2026-09-09',pdcLocation:'RFT',lifecycleState:'rft'};
const options={key:'test-stock',allowed:true,authority:true,inFlight:false,collectionEnabled:true};
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const b64=s=>Buffer.from(s).toString('base64');
function draft(body='QC completed. The QC completion photo is attached.') {
 const photo=Buffer.from([255,216,255,0,255,217]);
 const mime=Buffer.from(['MIME-Version: 1.0','X-Unsent: 1','To: salesperson@example.invalid','Subject: Ready for transport','Content-Type: multipart/mixed; boundary="rft-test"','','--rft-test','Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',b64(body),'--rft-test','Content-Type: image/jpeg','Content-Transfer-Encoding: base64','Content-Disposition: attachment; filename="QC-completion-photo.jpg"','',b64(photo),'--rft-test--',''].join('\r\n'));
 return {vehicle_id:v.__emailVehicleId,draft_id:'fixture-only',mime_content_type:'message/rfc822',draft_filename:'RFT-TEST.eml',photo_receipt_id:'fixture-photo',delivery_enabled:false,sent_at:null,delivered_at:null,photo_content_type:'image/jpeg',mime_base64:b64(mime),mime_byte_length:mime.length,mime_sha256:sha(mime),photo_byte_length:photo.length,photo_sha256:sha(photo),text_body:body,recipient_email:'salesperson@example.invalid',subject:'Ready for transport'};
}
test('RFT is a single read-only state icon, not two checked controls',()=>{const html=controls(v,options);assert.equal(ready(v),true);assert.doesNotMatch(html,/<input/);assert.equal((html.match(/<svg /g)||[]).length,3);assert.match(html,/QC signed off/);assert.match(html,/Mark collected/);assert.doesNotMatch(html,/data-rft-draft-key|aria-pressed|[⇩↗☑]/);});
test('draft ready uses an envelope and remains reopenable',()=>{const html=controls({...v,rftTransportDraft:{draft_id:'saved'}},options);assert.match(html,/Open the unsent salesperson email/);const button=html.match(/<button[^>]+data-rft-transport-booked-key[^>]+>/)[0];assert.doesNotMatch(button,/disabled/);assert.doesNotMatch(html,/is-checked|email.*sent or queued/);});
test('no checkmark for collection until collection evidence exists',()=>{const html=controls(v,options);assert.equal(collected(v),false);assert.doesNotMatch(html,/rft-collected-status/);assert.match(html,/rft-collect-action/);const done=controls({...v,rftCollectedAt:'2026-09-09'},options);assert.match(done,/rft-collected-status/);assert.doesNotMatch(done,/data-rft-collected-key/);});
test('viewer and busy controls are disabled',()=>{for(const opts of [{...options,allowed:false},{...options,inFlight:true}]){const html=controls(v,opts);assert.equal((html.match(/ disabled/g)||[]).length,2);}});
test('untrusted or unsigned QC cannot be presented as ready',()=>{assert.equal(ready({...v,__emailVehicleServerAuthoritative:false}),false);assert.equal(ready({...v,pdcQcComplete:false}),false);const html=controls({...v,pdcQcComplete:false},options);assert.match(html,/Awaiting QC/);assert.equal((html.match(/ disabled/g)||[]).length,2);});
test('icon markup escapes stock keys',()=>{const html=controls(v,{...options,key:'"><script>alert(1)</script>'});assert.doesNotMatch(html,/<script/);assert.match(html,/&lt;script/);});
test('complete MIME and QC attachment are verified',async()=>{const result=await verifyDraft(draft(),v.__emailVehicleId);assert.equal(result.photo.length,6);assert.match(result.text,/QC completion photo/);});
test('bad email hash cannot trigger a download',async()=>{await assert.rejects(verifyDraft({...draft(),mime_sha256:'0'.repeat(64)},v.__emailVehicleId),/integrity/);});
test('wrong vehicle and missing photo receipts fail closed',async()=>{await assert.rejects(verifyDraft(draft(),'wrong-vehicle'),/identity/);await assert.rejects(verifyDraft({...draft(),photo_receipt_id:null},v.__emailVehicleId),/identity/);});
test('photo hash and content-type mismatch fail closed',async()=>{await assert.rejects(verifyDraft({...draft(),photo_sha256:'f'.repeat(64)},v.__emailVehicleId),/photo integrity/);await assert.rejects(verifyDraft({...draft(),photo_content_type:'image/png'},v.__emailVehicleId),/photo format/);});
test('old transport requests and mismatched preview text are not presented',async()=>{await assert.rejects(verifyDraft(draft('The QC photo is attached. Please arrange transport.'),v.__emailVehicleId),/transport-request/);await assert.rejects(verifyDraft({...draft(),text_body:'Other body'},v.__emailVehicleId),/body/);});
test('RFT boot uses direct Outlook compose without an email-file download',()=>{const code=fs.readFileSync('pdc-rft-actions.js','utf8');const boot=fs.readFileSync('canonical-entry.js','utf8');assert.match(boot,/pdc-rft-actions\.js\?v=2026\.09\.10\.03/);assert.match(code,/openOutlook\(prepared\); \/\/ Same direct compose/);assert.doesNotMatch(code,/link\.download|createObjectURL|sendMail|graph\.microsoft|\/send\b/);assert.match(code,/readRftTransportDraft739/);assert.match(code,/Copy QC photo/);});
