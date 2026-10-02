const assert=require('node:assert/strict'),fs=require('node:fs');
if (!process.env.FIRESTORE_EMULATOR_HOST && process.env.QA_EMAIL_CERTIFICATION !== 'true') throw Error('Explicit private TEST job or emulator required');
require('firebase-admin/app').initializeApp({projectId:process.env.FIRESTORE_EMULATOR_HOST ? 'demo-circum-email' : 'circum-2797c'});
const {getFirestore,Timestamp}=require('firebase-admin/firestore');const raw=getFirestore();raw.settings({ignoreUndefinedProperties:true});
const fid='__codex_email_lifecycle_'+Date.now(),root=raw.collection('giftStoryRuntimeFixtures').doc(fid);
const db=require('./gift-story-fixture-db').fixtureDb(raw,fid);
const {publishFromEvent,CREATED,UPDATED}=require('./transactional-email-publishers');
const {emitNotification}=require('./communication-engine');const {unlockGiftStory}=require('./gift-story-automation');
const {processEmailQueueRecord}=require('./cloud-run-transactional-email');
const e={fixture:fid,customerProviderCalls:0,pushCalls:0,steps:[]};
(async()=>{try{
 await root.create({testOnly:true,createdAt:Timestamp.now()});
 await db.collection('systemConfiguration').doc('giftsCommunicationsPolicy').set({version:'gifts-communications-v1',effectiveAt:'2026-09-26T16:41:34Z'});
 let g={senderId:'__codex_sender',senderEmail:'sender@example.test',recipientEmail:'recipient@example.test',recipientName:'TEST Recipient',paymentStatus:'paid',walletContributionGbp:10,remainingStripeAmountGbp:0,status:'submitted_for_review',paidAt:Timestamp.now()};
 await db.collection('walletTransactions').doc('gift_roth_'+fid).set({status:'completed',amount:-10,referenceId:fid});
 const ref=db.collection('giftRequests').doc(fid);await ref.set(g);
 const pub=(before,after)=>publishFromEvent({db,eventType:before?UPDATED:CREATED,eventId:'test_'+Date.now(),decoded:{documentName:`projects/circum-2797c/databases/(default)/documents/giftRequests/${fid}`,before:before||{},after}});
 assert.equal((await pub(null,g)).status,'queued');
 for(const [status,field,type]of [['approved','approvedAt','gift_approved'],['curation_started',null,'curation_started'],['ready_for_gift_delivery','readyForDeliveryAt','ready_for_gift_delivery'],['delivered','deliveredAt','gift_delivered']]){
 const before=g;g={...g,status,...(field?{[field]:Timestamp.now()}:{})};await ref.set(g);await pub(before,g);
 const input={db,suppressPush:true,recipientId:g.senderId,type,title:'TEST milestone',body:'TEST only',data:{category:'gifts',giftId:fid},dedupeKey:`gift_status:${fid}:${type}:${g.senderId}`};const nid=await emitNotification(input);assert.equal(await emitNotification(input),nid);e.steps.push({status,notificationCreated:true,replayDuplicate:true});}
 await unlockGiftStory(db,await ref.get(),fid,{source:'cloud_run'});await unlockGiftStory(db,await ref.get(),fid,{source:'cloud_run'});
 const queue=await db.collection('emailQueue').get();assert.equal(queue.size,6);let n=0;
 for(const row of queue.docs){const result=await processEmailQueueRecord({db,emailId:row.id,eventId:'consume_'+row.id,apiKey:'not-a-provider-key',fetchImpl:async(_url,o)=>{assert.ok(JSON.parse(o.body).to.every(x=>x.endsWith('@example.test')));n++;return{ok:true,status:200,json:async()=>({id:'00000000-0000-4000-8000-'+String(n).padStart(12,'0')})};}});assert.ok(['sent','suppressed'].includes(result.status));assert.equal((await processEmailQueueRecord({db,emailId:row.id,eventId:'replay_'+row.id,apiKey:'not-a-provider-key',fetchImpl:()=>{throw Error('duplicate provider call')}})).status,'duplicate');}
 e.emailCount=queue.size;e.notifications=(await db.collection('notifications').get()).size;e.simulatedProviderAcceptances=n;e.status='PASS';
 }finally{await raw.recursiveDelete(root);e.cleanup={rootExists:(await root.get()).exists,remainingSubcollections:(await root.listCollections()).length};if(process.env.QA_EMAIL_EVIDENCE_PATH) fs.writeFileSync(process.env.QA_EMAIL_EVIDENCE_PATH,JSON.stringify(e,null,2));}console.log(JSON.stringify(e,null,2));process.exit(0);
})().catch(x=>{console.error(x.message);process.exit(1)});
