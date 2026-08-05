"use strict";

const {createDeliveryCore} = require("./delivery-domain-core");

function fromLegacyDeliveryRecord(record = {}) {
  return createDeliveryCore({
    id: record.id || record.deliveryId || record.requestId,
    status: record.status || record.deliveryStatus || record.deliveryStage,
    senderId: record.senderId || record.userId || record.customerId,
    recipientId: record.recipientId || record.receiverId || record.recipientUserId,
    riderId: record.riderId || record.assignedRiderId || record.driverId,
    createdAt: record.createdAt,
    completedAt: record.completedAt || record.deliveredAt,
    dispatchId: record.dispatchId,
    trackingId: record.trackingId,
    pricingId: record.pricingId,
    paymentId: record.paymentId || record.stripePaymentIntentId,
    evidenceId: record.evidenceId,
    eventVersion: record.eventVersion,
  });
}

module.exports = {fromLegacyDeliveryRecord};
