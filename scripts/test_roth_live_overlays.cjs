'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '../server/functions');
const Stripe = require(path.join(root,'node_modules/stripe'));
const {createStripeWebhookProcessor} = require(path.join(root,'stripe-webhook-core.roth-live-overlay.js'));
const stripe = new Stripe('sk_test_fixture');
const secret = 'whsec_fixture';
let refunds=0;
const ignored=async()=>({handled:false});
const processEvent=createStripeWebhookProcessor({stripe,resolveRuntimeConfig:()=>({mode:'live',webhookSecret:secret}),assertEventMode:event=>assert.equal(event.livemode,true),db:{collection:()=>{throw Error('Unexpected financial write');}},ratingsTipping:{processStripeTipRefund:ignored},stripeRefunds:{syncChargeRefund:async()=>{refunds++;return {handled:true};}},logger:{info(){},warn(){},error(){}}});
(async()=>{
 for(const type of ['checkout.session.completed','checkout.session.expired','payment_intent.succeeded','payment_intent.processing','charge.succeeded']){
  const rawBody=Buffer.from(JSON.stringify({id:'evt_fixture',type,livemode:true,data:{object:{id:'fixture',metadata:{type:'website_roth_top_up',websiteRealm:'live'}}}}));
  const signature=stripe.webhooks.generateTestHeaderString({payload:rawBody,secret});
  const result=await processEvent({rawBody,signature});
  assert.equal(result.status,200);assert.equal(result.body.delegated,'website_roth_live');
  assert.equal((await processEvent({rawBody,signature:'invalid'})).status,400);
 }
 const rawBody=Buffer.from(JSON.stringify({id:'evt_refund',type:'charge.refunded',livemode:true,data:{object:{metadata:{type:'website_roth_top_up',websiteRealm:'live'}}}}));
 const signature=stripe.webhooks.generateTestHeaderString({payload:rawBody,secret});
 assert.equal((await processEvent({rawBody,signature})).status,200);assert.equal(refunds,1);
 console.log('PASS: signed website events delegate without writes; existing refunds remain owned by the published handler.');
})().catch(error=>{console.error(error);process.exitCode=1;});
