const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {planRoadChargeSettlement, dailyId} = require("./road-charge-settlement");

const app = getApps().length ? getApps()[0] : initializeApp({projectId: "circum-road-charge-test"});
const db = getFirestore(app);

async function settle(deliveryId, charge, vehicleId = "vehicle-1") {
  const effectRef = db.collection("testRoadEffects").doc(`${deliveryId}:ccz`);
  const dailyRef = db.collection("testRoadDaily").doc(dailyId(charge, vehicleId, charge.chargingDate));
  return db.runTransaction(async (transaction) => {
    const [effectSnap, dailySnap] = await Promise.all([
      transaction.get(effectRef),
      transaction.get(dailyRef),
    ]);
    if (effectSnap.exists) return {duplicate: true, reimbursementPence: 0};
    const plan = planRoadChargeSettlement({
      deliveryId,
      riderId: "rider-1",
      assignedVehicle: {id: vehicleId, type: "car"},
      delivery: {pricingBreakdown: {roadCharges: {charges: [charge]}}},
      dailyState: {[dailyRef.id]: dailySnap.exists ? dailySnap.data() : {}},
    });
    const effect = plan.effects[0];
    if (!effect) return {duplicate: false, reimbursementPence: 0};
    transaction.create(effectRef, effect);
    transaction.set(dailyRef, {
      recoveredPence: (dailySnap.exists ? Number(dailySnap.data().recoveredPence || 0) : 0) + effect.reimbursementPence,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {duplicate: false, reimbursementPence: effect.reimbursementPence};
  });
}

test("emulator contention caps concurrent CCZ recovery at £18", async () => {
  const day = `emulator-${Date.now()}`;
  const charge = {chargeId: "congestion_charge", type: "daily_zone_charge", amountPence: 1800, customerContributionPence: 900, chargingDate: day};
  const results = await Promise.all([
    settle(`job-a-${day}`, charge),
    settle(`job-b-${day}`, charge),
    settle(`job-c-${day}`, charge),
    settle(`job-d-${day}`, charge),
  ]);
  const daily = await db.collection("testRoadDaily").doc(dailyId(charge, "vehicle-1", day)).get();
  assert.equal(Math.min(1800, Number(daily.data().recoveredPence || 0)), 1800);
  assert.equal(results.reduce((sum, result) => sum + result.reimbursementPence, 0), 1800);
  assert.equal(new Set(results.map((result, index) => result.duplicate ? `duplicate-${index}` : index)).size, 4);
});

test("emulator retry creates no duplicate crossing effect", async () => {
  const day = `emulator-crossing-${Date.now()}`;
  const charge = {chargeId: "blackwall_silvertown", type: "route_toll", amountPence: 400, riderReimbursementPence: 400, chargingDate: day};
  const first = await settle(`crossing-${day}`, charge);
  const retry = await settle(`crossing-${day}`, charge);
  assert.equal(first.reimbursementPence, 400);
  assert.equal(retry.duplicate, true);
  assert.equal((await db.collection("testRoadEffects").doc(`crossing-${day}:ccz`).get()).exists, true);
});
