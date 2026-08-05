# Delivery Domain Contract

The Delivery Domain is the stable platform boundary. Product-specific data is an extension, never a field on the core delivery record.

## Core

`server/functions/delivery-domain-core.js` defines the versioned universal core:

`deliveryId`, `status`, `senderId`, `recipientId`, `riderId`, lifecycle timestamps, dispatch/tracking/pricing/payment/evidence references, and `eventVersion`.

Legacy Firestore records are converted at the adapter boundary by `delivery-domain-adapter.js`; the stored legacy document is not rewritten by the adapter.

## Events

`delivery-domain-events.js` defines additive, versioned platform events:

`DeliveryCreated`, `DeliveryPriced`, `PaymentAuthorised`, `DispatchStarted`, `RiderAssigned`, `ParcelCollected`, `DeliveryCompleted`, and `DeliveryClosed`.

`DeliveryCompleted` is currently published by the authoritative completion transaction and consumed by independently idempotent subscribers. Product context travels in `extensions`, not in the core.

## Service contracts

`delivery-service-contracts.js` is the dependency-injection boundary for Delivery, Dispatch, Pricing, Tracking, Evidence, Settlement, Notification, and Analytics. Implementations can be replaced without changing the domain contract.

## Ownership

The Delivery Domain owns lifecycle verification, evidence prerequisites, dispatch/tracking references, completion, and settlement authority. Business, Health+, Gifts, and future products own their policy and extension documents and subscribe to platform events.

New product guidance:

1. Create an extension document keyed by `deliveryId`.
2. Add only an extension reference to an event payload.
3. Subscribe to canonical events with deterministic idempotency keys.
4. Do not add product fields to `deliveryRequests` or modify lifecycle authority.
