"use strict";

function completionEventFor({deliveryId, delivery, riderId}) {
  return {
    eventId: `delivery_completed_${deliveryId}`,
    eventType: "DeliveryCompleted",
    schemaVersion: 1,
    deliveryId,
    requestId: delivery.requestId || deliveryId,
    riderId: riderId || delivery.riderId || delivery.assignedRiderId || null,
    senderId: delivery.senderId || delivery.userId || delivery.customerId || null,
    quoteId: delivery.quoteId || null,
    paymentSessionId: delivery.paymentSessionId || null,
    occurredAt: "server_timestamp",
    source: "updateDeliveryTrackingStatus",
  };
}

module.exports = {completionEventFor};
