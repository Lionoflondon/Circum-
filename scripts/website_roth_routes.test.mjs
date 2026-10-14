import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {validateAccess, validateWallet, paymentMessage, checkoutDestination} from '../web/roth/state.mjs';
test('hosting routes ROTH APIs only to dedicated TEST runtime', () => {
 const h=JSON.parse(fs.readFileSync(new URL('../firebase.json',import.meta.url))).hosting.find(h=>h.target==='public');
 assert.deepEqual(h.rewrites.find(r=>r.source==='/api/roth/**'),{source:'/api/roth/**',run:{serviceId:'circum-website-roth-test',region:'us-central1'}});
 assert(fs.existsSync(new URL('../web/roth/index.html',import.meta.url)));
});
test('malformed capabilities, balances, statuses and checkout destinations fail closed', () => {
 assert.throws(()=>validateAccess({token:'wrong'}));
 assert.throws(()=>validateWallet({balance:-1,environment:'test'}));
 assert.throws(()=>validateWallet({balance:1,environment:'live'}));
 assert.throws(()=>paymentMessage({balance:1,environment:'test',status:'paid'}));
 assert.throws(()=>checkoutDestination('https://attacker.invalid'));
 assert.equal(checkoutDestination('https://checkout.stripe.com/c/pay/cs_test'), 'https://checkout.stripe.com/c/pay/cs_test');
 for(const status of ['pending','failed','cancelled','credited']) assert(paymentMessage({balance:1,environment:'test',status,roth:1}));
});
test('return handling only retrieves status and cancellation never awards credit',()=>{
 const app=fs.readFileSync(new URL('../web/roth/app.js',import.meta.url),'utf8');
 assert(!app.includes('finalize(')); assert(!app.includes('test-pay'));
 assert(app.includes("api('logout'")); assert(app.includes('finally {reset();}'));  assert(app.includes('sessionStorage.removeItem(storageKey)'));
});

test('App Check binds to the explicit Public Website Firebase app identity',()=>{
 const build=fs.readFileSync(new URL('../scripts/build_public_web.sh',import.meta.url),'utf8');
 const app=fs.readFileSync(new URL('../web/roth/app.js',import.meta.url),'utf8');
 assert(build.includes('lib/website/shared/firebase/website_firebase_options.dart'));
 assert(app.includes('appId: config.firebaseAppId'));
});

test('wallet realms remain distinct for LIVE and TEST responses',()=>{
 assert.equal(validateWallet({balance:1,environment:'live'},'live').balance,1);
 assert.throws(()=>validateWallet({balance:1,environment:'test'},'live'));
 assert.throws(()=>validateWallet({balance:1,environment:'live'},'test'));
 assert.equal(paymentMessage({balance:1,environment:'live',status:'credited',roth:1},'live'),'1 ROTH added to your Circum wallet.');
 const app=fs.readFileSync(new URL('../web/roth/app.js',import.meta.url),'utf8');
 assert(app.includes('roth-live-verification'));
});
