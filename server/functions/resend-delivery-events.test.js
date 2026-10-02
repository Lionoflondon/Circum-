"use strict";
const test=require("node:test"); const assert=require("node:assert/strict"); const http=require("node:http");
const {Webhook}=require("svix");
const {createServer, recordOutcome}=require("./resend-delivery-events");
function dbFake() {
const m=new Map(); const ref=(key)=>({key, id: key}); const queueRef=ref("emailQueue/q"); m.set(queueRef.key, {status: "sent", providerId: "00000000-0000-4000-8000-000000000001"});
 const snap=(r)=>({ref: r, exists: m.has(r.key), data: ()=>m.get(r.key)});
 return {m, collection: (c)=>({doc: (i)=>ref(c+"/"+i), where: ()=>({limit: ()=>({get: async ()=>({docs: [snap(queueRef)]})})})}), runTransaction: async (f)=>f({get: async (r)=>snap(r), create: (r, v)=>m.set(r.key, v), set: (r, v)=>m.set(r.key, {...m.get(r.key), ...v})})};
}
const event={type: "email.bounced", created_at: "2026-10-02T14:00:00Z", data: {email_id: "00000000-0000-4000-8000-000000000001", to: ["private@example.test"]}};
test("delivery outcome is separate from send status and replay creates one alert without recipient data", async ()=>{
const db=dbFake(); const logs=[]; assert.equal((await recordOutcome({db, event, deliveryId: "msg_1", log: (x)=>logs.push(x)})).status, "recorded"); assert.equal((await recordOutcome({db, event, deliveryId: "msg_1", log: (x)=>logs.push(x)})).status, "duplicate"); assert.equal(db.m.get("emailQueue/q").status, "sent"); assert.equal(db.m.get("emailQueue/q").providerDeliveryStatus, "bounced"); assert.equal(logs.length, 1); assert.ok(!JSON.stringify([...db.m.values()]).includes("private@example.test"));
});
test("unknown event types do not persist", async ()=>assert.equal((await recordOutcome({db: dbFake(), event: {type: "email.opened"}, deliveryId: "x"})).status, "ignored"));
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
