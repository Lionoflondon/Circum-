"use strict";
const test=require("node:test"); const assert=require("node:assert/strict"); const http=require("node:http");
const {Webhook}=require("svix");
const {createServer, recordOutcome}=require("./resend-delivery-events");
function dbFake({queueReady=true}={}) {
const m=new Map(); const ref=(key)=>({key, id: key}); const queueRef=ref("emailQueue/q"); if (queueReady) m.set(queueRef.key, {status: "sent", providerId: "00000000-0000-4000-8000-000000000001"});
 const snap=(r)=>({ref: r, exists: m.has(r.key), data: ()=>m.get(r.key)});
 const query=(c, field, value)=>({limit: ()=>({get: async ()=>({docs: [...m.entries()].filter(([key, row])=>key.startsWith(c+"/") && row[field]===value).map(([key])=>snap(ref(key)))})}), get: async ()=>({docs: [...m.entries()].filter(([key, row])=>key.startsWith(c+"/") && row[field]===value).map(([key])=>snap(ref(key)))})});
 return {m, queueRef, collection: (c)=>({doc: (i)=>ref(c+"/"+i), where: (field, _op, value)=>query(c, field, value)}), runTransaction: async (f)=>f({get: async (r)=>snap(r), create: (r, v)=>m.set(r.key, v), set: (r, v)=>m.set(r.key, {...m.get(r.key), ...v})})};
}
const event={type: "email.bounced", created_at: "2026-10-02T14:00:00Z", data: {email_id: "00000000-0000-4000-8000-000000000001", to: ["private@example.test"]}};
test("delivery outcome is separate from send status and replay creates one alert without recipient data", async ()=>{
const db=dbFake(); const logs=[]; assert.equal((await recordOutcome({db, event, deliveryId: "msg_1", log: (x)=>logs.push(x)})).status, "recorded"); assert.equal((await recordOutcome({db, event, deliveryId: "msg_1", log: (x)=>logs.push(x)})).status, "duplicate"); assert.equal(db.m.get("emailQueue/q").status, "sent"); assert.equal(db.m.get("emailQueue/q").providerDeliveryStatus, "bounced"); assert.equal(logs.length, 1); assert.ok(!JSON.stringify([...db.m.values()]).includes("private@example.test"));
});
test("unknown event types do not persist", async ()=>assert.equal((await recordOutcome({db: dbFake(), event: {type: "email.opened"}, deliveryId: "x"})).status, "ignored"));
test("signed outcome is durably retained when its queue receipt arrives later", async ()=>{
const db=dbFake({queueReady: false}); const logs=[];
let waits=0;
assert.deepEqual(await recordOutcome({db, event, deliveryId: "msg_delayed", log: (x)=>logs.push(x), wait: async ()=>{
waits++; if (waits===2) db.m.set("emailQueue/q", {status: "sent", providerId: event.data.email_id});
}}), {status: "recorded", matchedQueueCount: 1});
const pending=[...db.m.values()].find((row)=>row.eventType==="email.bounced"); assert.equal(pending.matchedQueueCount, 1); assert.equal(db.m.get("emailQueue/q").providerDeliveryStatus, "bounced"); assert.ok(logs.some((line)=>line.includes("email_provider_event_waiting_for_queue_receipt")));
});
test("missing queue receipt remains durable and returns retryable failure", async ()=>{
const db=dbFake({queueReady: false});
await assert.rejects(recordOutcome({db, event, deliveryId: "msg_unmatched", log: ()=>{}, wait: async ()=>{}}), (error)=>error.statusCode===503 && error.code==="queue_receipt_not_ready");
assert.equal([...db.m.values()].filter((row)=>row.eventType==="email.bounced").length, 1);
assert.equal([...db.m.values()].find((row)=>row.eventType==="email.bounced").matchedQueueCount, 0);
});
test("reconciliation applies the newest provider event despite out-of-order delivery", async ()=>{
const db=dbFake(); const newer={...event, type: "email.delivered", created_at: "2026-10-02T15:00:00Z"};
await recordOutcome({db, event: newer, deliveryId: "msg_newer", log: ()=>{}});
await recordOutcome({db, event, deliveryId: "msg_older", log: ()=>{}});
assert.equal(db.m.get("emailQueue/q").providerDeliveryStatus, "delivered");
});
function post(port, body, headers={}) {
return new Promise((resolve, reject)=>{
const q=http.request({port, path: "/resend/events", method: "POST", headers}, (r)=>{
r.resume(); r.on("end", ()=>resolve(r.statusCode));
}); q.on("error", reject); q.end(body);
});
}
test("HTTP rejects forged, stale and changed signatures; accepts signed exact payload", async (t)=>{
const secret="whsec_"+Buffer.alloc(32, 7).toString("base64"); const server=createServer({secret, dbFactory: dbFake, log: ()=>{}}); await new Promise((r)=>server.listen(0, r)); t.after(()=>server.close()); const port=server.address().port; const body=JSON.stringify(event); const now=new Date(); const h={"svix-id": "msg_signed", "svix-timestamp": String(Math.floor(now.getTime()/1000)), "svix-signature": new Webhook(secret).sign("msg_signed", now, body)}; assert.equal(await post(port, body), 401); assert.equal(await post(port, body+" ", h), 401); assert.equal(await post(port, body, {...h, "svix-timestamp": "1"}), 401); assert.equal(await post(port, body, h), 200);
});
