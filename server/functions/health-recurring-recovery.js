/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const DAY_MS = 86400000;
function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const d = new Date(value); return Number.isNaN(d.getTime()) ? null : d;
}
function nextOccurrence(date, frequency) {
  const next = new Date(date);
  const days = frequency === "weekly" ? 7 :
    frequency === "every_2_weeks" ? 14 :
      frequency === "every_28_days" ? 28 : 0;
  if (days) next.setDate(next.getDate() + days);
  else next.setMonth(next.getMonth() + 1);
  return next;
}

async function generateRecurring({db, now = Date.now(), limit = 20}) {
      const horizon = new Date(now + 7 * DAY_MS);
      const page = await require("./legacy-scheduled-recovery").page({db, collection: "recurringPickupSchedules", worker: "generateHealthPlusRecurringBookings", limit});
      const schedules = page.snapshot;
      await Promise.all(schedules.docs.map(async (scheduleDoc) => {
        const schedule = scheduleDoc.data();
        if (schedule.status !== "active" || schedule.paused === true) return;
        const occurrence = asDate(schedule.nextPickupAt);
        if (!occurrence || occurrence > horizon || occurrence.getTime() < now - DAY_MS) return;
        const dateKey = occurrence.toISOString().slice(0, 10).replaceAll("-", "");
        const pickupId = `HPP-${scheduleDoc.id}-${dateKey}`;
        const pickupRef = db.collection("prescriptionPickups").doc(pickupId);
        await db.runTransaction(async (transaction) => {
          const [existing, freshSnap] = await Promise.all([transaction.get(pickupRef), transaction.get(scheduleDoc.ref)]);
          const fresh = freshSnap.data() || {};
          if (!freshSnap.exists || fresh.status !== "active" || fresh.paused === true || !asDate(fresh.nextPickupAt) || asDate(fresh.nextPickupAt).getTime() !== occurrence.getTime()) return;
          if (existing.exists) return;
          const schedule = fresh;
          transaction.set(pickupRef, {
            id: pickupId,
            scheduleId: scheduleDoc.id,
            profileId: schedule.profileId || null,
            senderId: schedule.senderId || schedule.userId || null,
            userId: schedule.userId || schedule.senderId || null,
            fullName: schedule.fullName || null,
            phoneNumber: schedule.phoneNumber || null,
            email: schedule.email || null,
            pharmacyName: schedule.pharmacyName || null,
            pharmacyAddress: schedule.pharmacyAddress || "",
            deliveryAddress: schedule.deliveryAddress || "",
            prescriptionType: schedule.prescriptionType || null,
            prescriptionNotes: schedule.prescriptionNotes || null,
            planType: schedule.planType || schedule.subscriptionPlan || "core",
            subscriptionPlan: schedule.planType || schedule.subscriptionPlan || "core",
            preferredRiderId: schedule.preferredRiderId || null,
            preferredRiderName: schedule.preferredRiderName || null,
            scheduledAt: Timestamp.fromDate(occurrence),
            scheduledPickupDate: occurrence.toISOString(),
            preferredTime: schedule.preferredTime || null,
            status: "scheduled",
            riskStatus: "scheduled",
            isVanguard: true,
            trustPoints: 6,
            recurring: true,
            source: "health-plus-recurring-engine",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          transaction.set(scheduleDoc.ref, {
            nextPickupAt: Timestamp.fromDate(nextOccurrence(occurrence, schedule.frequency)),
            lastGeneratedPickupId: pickupId,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          transaction.set(db.collection("notifications").doc(`health_admin_${pickupId}_booking_created`), {
            notificationId: `health_admin_${pickupId}_booking_created`,
            recipientId: "circum-operations",
            recipientRole: "admin",
            type: "health_plus_booking_created",
            title: "Health+ recurring pickup scheduled",
            body: "A recurring Health+ pickup is ready for Operations review.",
            message: "A recurring Health+ pickup is ready for Operations review.",
            category: "health",
            pickupId,
            healthPickupId: pickupId,
            profileId: schedule.profileId || null,
            senderId: schedule.senderId || schedule.userId || null,
            destination: {
              route: "admin_health_plus",
              healthPickupId: pickupId,
              pickupId,
            },
            data: {
              category: "Health+",
              pickupId,
              scheduleId: scheduleDoc.id,
              status: "scheduled",
              recurring: true,
            },
            read: false,
            archived: false,
            deliveryStatus: "persisted",
            deliveryState: "persisted",
            source: "health-plus-recurring-engine",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        });
      }));
      await page.save();
      return {scanned: schedules.size};
}
module.exports = {generateRecurring};
