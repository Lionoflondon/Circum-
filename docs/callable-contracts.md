# Circum Callable Contracts

Generated Phase 3 baseline. Backend exports are preserved; legacy callables are marked but not removed.

## Callable Inventory

- Exported: 133
- Referenced by clients/tests: 69
- Unused exports: 64
- Missing referenced exports: 0
- Legacy exports: StripePayEndpointIntentId, StripePayEndpointMethodId, calculateEarnings, endTrip, getAvaliableRequests, sendMessage, sendRiderUpdate

### Duplicate / Compatibility Exports

| Canonical | Legacy / duplicate | Status |
|---|---|---|
| getAvailableRequests | getAvaliableRequests | Legacy typo alias retained; clients must use canonical spelling. |
| sendCircumMessage | sendMessage | Legacy chat alias retained; clients must use communication engine callables. |
| createPaymentIntent | StripePayEndpointMethodId | Legacy HTTP payment endpoint retained for old clients. |
| confirmPaymentIntent | StripePayEndpointIntentId | Legacy HTTP payment endpoint retained for old clients. |

## Client Usage Matrix

| Action | Sender | Rider | Backend Callable | Status |
|---|---|---|---|---|
| Create delivery quote | Yes | No | createSenderBookingQuote | Canonical |
| Create paid delivery | Yes | No | createSenderPaidDelivery | Canonical |
| Legacy delivery send | Yes | No | sendPackage | Legacy compatibility |
| Preview sender cancellation | Yes | No | previewSenderCancellation | Canonical |
| Execute sender cancellation | Yes | No | requestSenderCancellation | Canonical |
| Accept rider offer | No | Yes | acceptRideRequests | Canonical |
| Get available rider offers | No | Yes | getAvailableRequests | Canonical |
| Go online | No | Yes | goOnline | Canonical |
| Go offline | No | Yes | goOffline | Canonical |
| Update rider presence | No | Yes | updateRiderPresence | Canonical |
| Record rider arrival | No | Yes | recordRiderArrival | Canonical |
| Delivery status transition | No | Yes | updateDeliveryTrackingStatus | Canonical |
| Rider no-show | No | Yes | markRiderNoShow | Canonical |
| Waiting context | No | Yes | reportWaitingContext | Canonical |
| Sender customer response | Yes | No | recordCustomerArrivalResponse | Canonical |
| Delivery chat message | Yes | Yes | sendCircumMessage | Canonical |
| Typing indicator | Yes | Yes | setConversationTyping | Canonical |
| Mark conversation read | Yes | Yes | markConversationRead | Canonical |
| Rider earnings summary | No | Yes | getRiderEarningsSummary | Canonical |
| Sender wallet balance | Yes | No | getSenderWallet | Canonical |
| Sender Roth balance in booking | Yes | No | getSenderRothBalance | Canonical |
| Sender saved address search | Yes | No | searchFreeUkAddresses | Canonical |
| Account closure | Yes | Yes | closeCircumAccount | Canonical |

## Complete Callable Contract Source

The complete machine-readable contract is stored in `docs/callable-contracts.json`.
Each entry contains callable name, purpose, owning backend file, invoked products, input/output schema summary, error codes, auth requirements, classification, and deprecation status.
