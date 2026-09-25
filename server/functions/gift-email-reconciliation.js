/* eslint-disable max-len, require-jsdoc */
"use strict";

const {publishFromEvent, CREATED, UPDATED} = require("./transactional-email-publishers");
const {processEmailQueueRecord} = require("./cloud-run-transactional-email");
const {FieldPath} = require("firebase-admin/firestore");
const {normalizeEmail} = require("./email-queue");

const text = (value) => `${value || ""}`.trim();
const status = (value) => text(value).toLowerCase();

async function reconcileGiftById({db, giftId, repair = false, replayStuck = false,
  processRecord = processEmailQueueRecord, nowMs = Date.now()}) {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(text(giftId))) throw new Error("A specific Gift ID is required.");
  const giftSnap = await db.collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) return {status: "missing"};
  const gift = giftSnap.data() || {};
  const paymentEligible = status(gift.paymentStatus) === "paid" && Number(gift.walletContributionGbp) > 0;
  const senderAvailable = Boolean(normalizeEmail(gift.senderEmail));
  const recipientAvailable = Boolean(normalizeEmail(gift.recipientEmail || gift.recipientContact));
  const storyReady = status(gift.status || gift.giftStatus) === "delivered" &&
    gift.giftStoryUnlocked === true && status(gift.giftStoryStatus) === "unlocked";
  const queueIds = [
    `gift_payment_confirmed_${giftId}`,
    `gift_${giftId}_gift_delivered`,
    `gift_story_${giftId}_sender`,
    `gift_story_${giftId}_recipient`,
  ];
  const queueSnapshots = await Promise.all(queueIds.map((id) => db.collection("emailQueue").doc(id).get()));
  const missingPayment = paymentEligible && senderAvailable && !queueSnapshots[0].exists;
  const missingStory = storyReady && ((senderAvailable && (!queueSnapshots[1].exists || !queueSnapshots[2].exists)) ||
    (recipientAvailable && !queueSnapshots[3].exists));
  const stuck = queueIds.filter((_, index) => queueSnapshots[index].exists &&
    status(queueSnapshots[index].data().status) === "retryable_failed" &&
    Number(queueSnapshots[index].data().nextAttemptAt && queueSnapshots[index].data().nextAttemptAt.toMillis()) <= nowMs);
  let completedDeliveryNeedsStory = false;
  if (!storyReady && text(gift.deliveryId)) {
    const deliverySnap = await db.collection("deliveryRequests").doc(text(gift.deliveryId)).get();
    const delivery = deliverySnap.exists ? deliverySnap.data() || {} : {};
    const linkedGiftId = text(delivery.giftOrderId || delivery.giftRequestId);
    completedDeliveryNeedsStory = deliverySnap.exists && ["completed", "complete", "delivered"].includes(status(delivery.status)) &&
      (linkedGiftId ? linkedGiftId === giftId : status(delivery.serviceType) === "gifts" || status(delivery.sourceModule) === "gifts");
  }
  const sourceName = `projects/circum-2797c/databases/(default)/documents/giftRequests/${giftId}`;
  let paymentPublication = "not_requested";
  let storyPublication = "not_requested";
  if (repair && missingPayment) {
    const result = await publishFromEvent({db, eventType: CREATED, eventId: `reconcile-payment-${giftId}`,
      decoded: {documentName: sourceName, before: {}, after: gift}});
    paymentPublication = result.status;
  }
  if (repair && missingStory) {
    const result = await publishFromEvent({db, eventType: UPDATED, eventId: `reconcile-story-${giftId}`,
      decoded: {documentName: sourceName, before: {paymentStatus: gift.paymentStatus, status: "approved", giftStoryStatus: "locked"}, after: gift}});
    storyPublication = result.status;
  }
  const replayResults = repair && replayStuck ? await Promise.allSettled(stuck.map((id) => processRecord({
    db, emailId: id, eventId: `gift-reconcile-${giftId}-${nowMs}`, nowMs,
  }))) : [];
  return {status: "inspected", paymentEligible, storyReady, recipientUnavailable: !senderAvailable || !recipientAvailable,
    missingPayment, missingStory,
    completedDeliveryNeedsStory, stuckQueueCount: stuck.length,
    paymentPublication, storyPublication,
    replaySent: replayResults.filter((item) => item.status === "fulfilled" && item.value.status === "sent").length,
    replayFailed: replayResults.filter((item) => item.status === "rejected" ||
      item.value.status === "failed").length};
}

async function scanGiftRecoveryPage({db, kind, afterId = "", limit = 50, nowMs = Date.now()}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Scan limit must be 1–100.");
  if (afterId && !/^[A-Za-z0-9_-]{1,120}$/.test(afterId)) throw new Error("Invalid scan cursor.");
  if (kind !== "paid" && kind !== "deliveries") throw new Error("Choose a bounded Gift recovery scan.");
  const collection = kind === "paid" ? "giftRequests" : "deliveryRequests";
  const filter = kind === "paid" ? ["paymentStatus", "==", "paid"] :
    ["status", "in", ["completed", "complete", "delivered"]];
  let query = db.collection(collection).where(...filter).orderBy(FieldPath.documentId()).limit(limit);
  if (afterId) query = query.startAfter(afterId);
  const page = await query.get();
  const candidates = [];
  for (const snapshot of page.docs) {
    if (kind === "paid") {
      const result = await reconcileGiftById({db, giftId: snapshot.id, nowMs});
      if (result.missingPayment || result.missingStory || result.completedDeliveryNeedsStory || result.stuckQueueCount) {
        candidates.push({giftId: snapshot.id, missingPayment: result.missingPayment,
          missingStory: result.missingStory, completedDeliveryNeedsStory: result.completedDeliveryNeedsStory,
          stuckQueueCount: result.stuckQueueCount});
      }
    } else {
      const delivery = snapshot.data() || {};
      const giftId = text(delivery.giftOrderId || delivery.giftRequestId);
      if (status(delivery.serviceType || delivery.sourceModule) !== "gifts" && !giftId) continue;
      if (!giftId) {
        candidates.push({deliveryId: snapshot.id, missingGiftLink: true});
        continue;
      }
      const giftSnap = await db.collection("giftRequests").doc(giftId).get();
      const gift = giftSnap.exists ? giftSnap.data() || {} : {};
      if (!giftSnap.exists || gift.giftStoryUnlocked !== true || status(gift.giftStoryStatus) !== "unlocked") {
        candidates.push({giftId, deliveryId: snapshot.id, completedDeliveryNeedsStory: true,
          missingGift: !giftSnap.exists});
      }
    }
  }
  return {kind, examined: page.docs.length, candidates,
    nextAfterId: page.docs.length === limit ? page.docs.at(-1).id : null};
}

if (require.main === module) {
  const {initializeApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const giftId = text(process.argv.find((arg) => arg.startsWith("--gift-id="))?.slice(10));
  const repair = process.argv.includes("--repair");
  const replayStuck = process.argv.includes("--replay-stuck");
  const repairStory = process.argv.includes("--repair-story");
  const deliveryId = text(process.argv.find((arg) => arg.startsWith("--delivery-id="))?.slice(14));
  const scanPaid = process.argv.includes("--scan-paid");
  const scanDeliveries = process.argv.includes("--scan-deliveries");
  const afterId = text(process.argv.find((arg) => arg.startsWith("--after-id="))?.slice(11));
  const limit = Number(process.argv.find((arg) => arg.startsWith("--limit="))?.slice(8) || 50);
  if ((scanPaid && scanDeliveries) || ((scanPaid || scanDeliveries) && (repair || repairStory || replayStuck || giftId)) ||
      (repairStory && (repair || replayStuck || !/^[A-Za-z0-9_-]{1,120}$/.test(giftId) ||
        (deliveryId && !/^[A-Za-z0-9_-]{1,120}$/.test(deliveryId))))) {
    process.stderr.write("Choose a read-only scan or one exact-Gift repair with valid IDs.\n");
    process.exit(1);
  }
  if (replayStuck && (!repair || !text(process.env.RESEND_API_KEY))) {
    process.stderr.write("Stuck email replay requires --repair and a configured email provider.\n");
    process.exit(1);
  }
  initializeApp();
  const operation = repairStory ? require("./gift-story-automation").retryGiftStoryForDelivery(getFirestore(),
      {giftRequestId: giftId, ...(deliveryId ? {deliveryId} : {})}) :
    scanPaid || scanDeliveries ? scanGiftRecoveryPage({db: getFirestore(),
    kind: scanPaid ? "paid" : "deliveries", afterId, limit}) :
    reconcileGiftById({db: getFirestore(), giftId, repair, replayStuck});
  operation
      .then((result) => process.stdout.write(`${JSON.stringify(result)}\n`))
      .catch((error) => {
        process.stderr.write(`${error.message}\n`);
        process.exitCode = 1;
      });
}

module.exports = {reconcileGiftById, scanGiftRecoveryPage};
