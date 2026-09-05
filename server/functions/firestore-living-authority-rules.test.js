/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const fs = require("node:fs");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  updateDoc,
  getDoc,
  deleteField,
  Timestamp,
} = require("firebase/firestore");
let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-living-authority-regression",
    firestore: {
      rules: fs.readFileSync(`${__dirname}/../../firestore.rules`, "utf8"),
    },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), "deliveryRequests/job"), {
      senderId: "sender",
      userId: "sender",
      riderId: "rider",
      driverId: "rider",
      assignedDriverId: "rider",
      businessId: "",
      status: "requested",
      dispatchStatus: "requested",
      matchingStatus: "available",
      riderEarning: 6,
      requiresVanguard: true,
      pickupEvidence: {photoUrl: "original"},
    });
    await setDoc(doc(c.firestore(), "users/sender"), {role: "sender"});
    await setDoc(doc(c.firestore(), "riderProfiles/eligible"), {
      name: "Eligible",
    });
    await setDoc(doc(c.firestore(), "riderPresence/eligible"), {
      dispatchEligible: true,
      isOnline: true,
      availabilityStatus: "available",
      lastHeartbeatAt: Timestamp.now(),
    });
  });
});
after(async () => env.cleanup());
test("owner cannot change payout, safety, dispatch, adjustment or evidence authority through add/update/delete", async () => {
  const ref = doc(
    env.authenticatedContext("sender").firestore(),
    "deliveryRequests/job",
  );
  for (const [field, value] of Object.entries({
    riderEarning: 999,
    estimatedEarnings: 999,
    driverId: "sender",
    assignedDriverId: "sender",
    pickupEvidence: {photoUrl: "fake"},
    handoverEvidence: {},
    requiresVanguard: false,
    verificationRequired: false,
    vehicleRequirement: "motorbike",
    loadDiscrepancy: {adminDecision: "approve"},
    riderEligibleFare: 9999,
    collectionPin: "000000",
    category: "Health+",
  })) {
    await assertFails(updateDoc(ref, {[field]: value}));
  }
  await assertFails(updateDoc(ref, {pickupEvidence: deleteField()}));
  await assertSucceeds(updateDoc(ref, {recipientNotes: "Side entrance"}));
});
test("canonical available jobs remain private even to an approved online Rider", async () => {
  const c = env.authenticatedContext("stranger").firestore();
  await assertFails(
    setDoc(doc(c, "riderProfiles/stranger"), {name: "Unapproved"}),
  );
  await assertFails(getDoc(doc(c, "deliveryRequests/job")));
  await assertFails(
    getDoc(
      doc(
        env.authenticatedContext("eligible").firestore(),
        "deliveryRequests/job",
      ),
    ),
  );
  await assertSucceeds(
    getDoc(
      doc(
        env.authenticatedContext("eligible").firestore(),
        "riderPresence/eligible",
      ),
    ),
  );
  await assertFails(
    updateDoc(doc(c, "riderPresence/stranger"), {dispatchEligible: true}),
  );
  await assertFails(getDoc(doc(c, "riderPresence/eligible")));
});
test("Legend authority cannot be added, rewritten or removed by a customer", async () => {
  const ref = doc(
    env.authenticatedContext("sender").firestore(),
    "users/sender",
  );
  await assertFails(updateDoc(ref, {isLegend: true, legendNumber: 1}));
  await env.withSecurityRulesDisabled(async (c) =>
    updateDoc(doc(c.firestore(), "users/sender"), {isLegend: false}),
  );
  await assertFails(updateDoc(ref, {isLegend: true}));
  await assertFails(updateDoc(ref, {isLegend: deleteField()}));
});
test("legacy web draft keeps owner reads but rejects payment and IRIS authority", async () => {
  const db = env.authenticatedContext("sender").firestore();
  const ref = doc(db, "webSenderRequests/draft");
  await assertSucceeds(
    setDoc(ref, {senderId: "sender", packageDescription: "book"}),
  );
  await assertSucceeds(getDoc(ref));
  await assertFails(
    getDoc(
      doc(
        env.authenticatedContext("other").firestore(),
        "webSenderRequests/draft",
      ),
    ),
  );
  for (const patch of [
    {paymentStatus: "paid"},
    {price: 0.01},
    {iris: {allowed: true}},
  ]) {
    await assertFails(updateDoc(ref, patch));
  }
});
test("financial and operational collection matrix denies unrelated reads and client authority writes", async () => {
  const cases = [
    ["giftRequests", "record", true],
    ["giftPaymentDrafts", "record", true],
    ["senderWallets", "sender", true],
    ["wallets", "record", true],
    ["walletTransactions", "record", true],
    ["referrals", "sender", true],
    ["businessAccounts", "business", true],
    ["businessMemberships", "record", true],
    ["businessInvoices", "record", true],
    ["business_wallets", "business", true],
    ["prescriptionPickups", "record", true],
    ["healthPlusProfiles", "record", true],
    ["recurringPickupSchedules", "record", true],
    ["healthPlusUsageEvents", "record", true],
    ["healthPlusNotifications", "record", true],
    ["healthPlusPayments", "record", true],
    ["riderApplications", "sender", true],
    ["riderDocuments", "record", true],
    ["payments", "record", false],
    ["deliveryRequestsPrivate", "record", false],
  ];
  await env.withSecurityRulesDisabled(async (c) => {
    for (const [collection, id] of cases) {
      await setDoc(doc(c.firestore(), collection, id), {
        uid: "sender",
        userId: "sender",
        senderId: "sender",
        riderId: "sender",
        referredUid: "sender",
        referrerUid: "sender",
        ownerUid: "sender",
        createdByUserId: "sender",
        teamMemberIds: [],
        businessId: "business",
        paymentStatus: "pending",
        status: "pending",
        balance: 0,
      });
    }
  });
  const owner = env.authenticatedContext("sender").firestore();
  const other = env.authenticatedContext("unrelated").firestore();
  for (const [collection, id, read] of cases) {
    if (read) await assertSucceeds(getDoc(doc(owner, collection, id)));
    else await assertFails(getDoc(doc(owner, collection, id)));
    await assertFails(getDoc(doc(other, collection, id)));
    await assertFails(
      updateDoc(doc(owner, collection, id), {
        paymentStatus: "paid",
        balance: 999,
      }),
    );
  }
});

test("private IRIS matching and verification authority cannot be seeded by Sender or Rider", async () => {
  const payload = {
    senderId: "sender",
    requestId: "job",
    internal: {
      riderMatching: {
        requiresTwoPerson: false,
        minimumVehicleClass: "motorbike",
      },
    },
    verification: {rider: null, adjudication: null},
  };
  await assertFails(
    setDoc(
      doc(env.authenticatedContext("sender").firestore(), "irisPrivate/job"),
      payload,
    ),
  );
  await assertFails(
    setDoc(
      doc(env.authenticatedContext("rider").firestore(), "irisPrivate/job"),
      {
        requestId: "job",
        deliveryDocId: "job",
        verification: {rider: {approved: true}},
      },
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(
        env
          .authenticatedContext("admin", {adminRole: "operations_admin"})
          .firestore(),
        "irisPrivate/job",
      ),
      payload,
    ),
  );
  await assertFails(
    updateDoc(
      doc(env.authenticatedContext("rider").firestore(), "irisPrivate/job"),
      {verification: {rider: {approved: true}}},
    ),
  );
});
