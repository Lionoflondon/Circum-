/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {buildCustodyEvent, buildHealthPlusPlanFields} = require("./health-plus-core");

const STATUS_EVENTS = {
  scheduled: ["booking_created", "Your Health+ collection has been scheduled.", "scheduled"],
  assigned: ["rider_assigned", "A verified rider has been assigned.", "assigned"],
  en_route_pickup: ["en_route_to_collection", "Your rider is travelling to the collection point.", "en_route_pickup"],
  awaiting_pharmacy_collection: ["en_route_to_collection", "Your rider is ready to collect from the pharmacy.", "awaiting_collection"],
  collected: ["prescription_collected", "Your prescription has been collected securely.", "collected"],
  out_for_delivery: ["en_route_to_customer", "Your Health+ delivery is on its way.", "out_for_delivery"],
  delivered: ["delivered", "Your Health+ delivery has been completed.", "completed"],
  prescription_not_ready: ["prescription_not_ready", "The prescription was not ready. Circum is coordinating the next step.", "prescription_not_ready"],
  customer_unavailable: ["customer_unavailable", "We could not complete delivery and will help reschedule.", "customer_unavailable"],
  escalated: ["escalated", "Your Health+ delivery has been escalated for review.", "escalated"],
  rescheduled: ["rescheduled", "Your Health+ collection has been rescheduled.", "scheduled"],
  override_completed: ["override_completion", "Your Health+ delivery was completed following an admin review.", "completed"],
};

function asDate(value) {
  if (!value) return null;
  if (value.toDate) return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

async function queueHealthNotification(db, pickup, type, title, body) {
  const notificationId = `health_${pickup.id}_${type}`;
  const payload = {
    id: notificationId,
    userId: pickup.userId || pickup.senderId || null,
    senderId: pickup.senderId || pickup.userId || null,
    profileId: pickup.profileId || null,
    pickupId: pickup.id,
    type,
    title,
    body,
    source: "health_plus",
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  await db.collection("healthPlusNotifications").doc(notificationId).set(payload, {merge: true});
  if (pickup.email) {
    await db.collection("emailQueue").doc(notificationId).set({
      to: pickup.email,
      subject: title,
      text: body,
      status: "pending",
      source: "health_plus",
      relatedEntityId: pickup.id,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

exports.onHealthPlusPickupOperationalWrite = functions.firestore
    .document("prescriptionPickups/{pickupId}")
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const before = change.before.exists ? change.before.data() : {};
      const pickup = {...change.after.data(), id: context.params.pickupId};
      const status = pickup.status || "scheduled";
      if (change.before.exists && before.status === status && before.assignedDriverId === pickup.assignedDriverId) return null;
      const db = getFirestore();
      try {
        const descriptor = STATUS_EVENTS[status];
        if (descriptor) {
          const eventId = `${context.params.pickupId}_${descriptor[0]}_${status}`;
          await db.collection("healthPlusCustodyArchive").doc(eventId).set({
            pickupId: context.params.pickupId,
            profileId: pickup.profileId || null,
            scheduleId: pickup.scheduleId || null,
            userId: pickup.userId || pickup.senderId || null,
            ...buildCustodyEvent({
              eventType: descriptor[0],
              actorType: pickup.lastAdminId ? "admin" : pickup.assignedDriverId ? "rider" : "system",
              actorId: pickup.lastAdminId || pickup.assignedDriverId || null,
              actorName: pickup.assignedDriverName || null,
              publicMessage: descriptor[1],
              internalNote: pickup.adminNote || null,
              statusAfterEvent: descriptor[2],
            }),
            createdAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          if (["assigned", "collected", "out_for_delivery", "delivered", "rescheduled", "escalated"].includes(status)) {
            await queueHealthNotification(db, pickup, descriptor[0], "Health+ update", descriptor[1]);
          }
        }

        if (status === "delivered" && pickup.scheduleId) {
          const scheduleRef = db.collection("recurringPickupSchedules").doc(pickup.scheduleId);
          await db.runTransaction(async (transaction) => {
            const scheduleSnap = await transaction.get(scheduleRef);
            if (!scheduleSnap.exists) return;
            const schedule = scheduleSnap.data();
            const planFields = buildHealthPlusPlanFields(schedule.planType || schedule.subscriptionPlan, schedule);
            const used = Number(schedule.usedDeliveriesThisCycle || 0) + 1;
            const preferredRiderId = schedule.preferredRiderId || pickup.assignedDriverId || null;
            transaction.set(scheduleRef, {
              ...planFields,
              usedDeliveriesThisCycle: used,
              remainingDeliveriesThisCycle: planFields.includedDeliveries == null ? null : Math.max(0, planFields.includedDeliveries - used),
              preferredRiderId,
              preferredRiderName: schedule.preferredRiderName || pickup.assignedDriverName || null,
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          });
        }
      } catch (error) {
        console.error("Health+ operational projection failed", context.params.pickupId, error);
        await db.collection("healthPlusOperationalErrors").add({
          pickupId: context.params.pickupId,
          status,
          error: `${error.message || error}`,
          retryable: true,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      return null;
    });

exports.processHealthPlusReminders = functions.pubsub
    .schedule("every 30 minutes")
    .timeZone("Europe/London")
    .onRun(async () => {
      const db = getFirestore();
      const now = new Date();
      const horizon = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
      const snapshot = await db.collection("prescriptionPickups")
          .where("status", "in", ["scheduled", "assigned", "awaiting_pharmacy_collection"])
          .limit(300)
          .get();
      await Promise.all(snapshot.docs.map(async (doc) => {
        const pickup = {...doc.data(), id: doc.id};
        const scheduledAt = asDate(pickup.scheduledAt || pickup.preferredPickupAt || pickup.scheduledPickupDate);
        if (!scheduledAt || scheduledAt > horizon) return;
        const msUntil = scheduledAt.getTime() - now.getTime();
        if (msUntil <= 24 * 60 * 60 * 1000 && msUntil > 23 * 60 * 60 * 1000) {
          await queueHealthNotification(db, pickup, "reminder_24h", "Health+ collection tomorrow", `Reminder: Your Health+ collection is scheduled for tomorrow at ${pickup.preferredTime || "the arranged time"}.`);
        }
        if (msUntil <= 2 * 60 * 60 * 1000 && msUntil > 90 * 60 * 1000) {
          await queueHealthNotification(db, pickup, "reminder_2h", "Health+ collection due soon", "Your Health+ collection is scheduled in approximately 2 hours.");
        }
        if (msUntil <= 24 * 60 * 60 * 1000 && !pickup.assignedDriverId) {
          await doc.ref.set({riskStatus: "no_rider_assigned", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        }
        if (msUntil < 0 && !["collected", "out_for_delivery", "delivered"].includes(pickup.status)) {
          await doc.ref.set({riskStatus: "missed_medication_risk", status: "escalated", escalatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        }
      }));
      return null;
    });

exports.resetHealthPlusMonthlyUsage = functions.pubsub
    .schedule("0 2 1 * *")
    .timeZone("Europe/London")
    .onRun(async () => {
      const db = getFirestore();
      const snapshot = await db.collection("recurringPickupSchedules").where("status", "==", "active").get();
      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        const data = doc.data();
        const fields = buildHealthPlusPlanFields(data.planType || data.subscriptionPlan, data);
        batch.set(doc.ref, {
          usedDeliveriesThisCycle: 0,
          remainingDeliveriesThisCycle: fields.includedDeliveries,
          renewalDate: Timestamp.fromDate(new Date(Date.now() + 31 * 24 * 60 * 60 * 1000)),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
      await batch.commit();
      return null;
    });

function nextOccurrence(date, frequency) {
  const next = new Date(date);
  const days = frequency === "weekly" ? 7 :
    frequency === "every_2_weeks" ? 14 :
      frequency === "every_28_days" ? 28 : 0;
  if (days) next.setDate(next.getDate() + days);
  else next.setMonth(next.getMonth() + 1);
  return next;
}

exports.generateHealthPlusRecurringBookings = functions.pubsub
    .schedule("every day 01:30")
    .timeZone("Europe/London")
    .onRun(async () => {
      const db = getFirestore();
      const horizon = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
      const schedules = await db.collection("recurringPickupSchedules")
          .where("status", "==", "active")
          .limit(300)
          .get();
      await Promise.all(schedules.docs.map(async (scheduleDoc) => {
        const schedule = scheduleDoc.data();
        if (schedule.paused === true) return;
        const occurrence = asDate(schedule.nextPickupAt);
        if (!occurrence || occurrence > horizon) return;
        const dateKey = occurrence.toISOString().slice(0, 10).replaceAll("-", "");
        const pickupId = `HPP-${scheduleDoc.id}-${dateKey}`;
        const pickupRef = db.collection("prescriptionPickups").doc(pickupId);
        await db.runTransaction(async (transaction) => {
          const existing = await transaction.get(pickupRef);
          if (existing.exists) return;
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
        });
      }));
      return null;
    });
