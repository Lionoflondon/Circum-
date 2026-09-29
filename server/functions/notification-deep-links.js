/* eslint-disable max-len, require-jsdoc */

// This is deliberately a small, data-only contract. Notification publishers
// may select an allowlisted product route and opaque entity identifiers, but
// they never supply a client URL or a provider-specific navigation command.
const DEEP_LINK_VERSION = 1;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
const ALLOWED_ROUTES = new Set([
  "tracking", "conversation", "wallet", "gift", "health", "business",
  "profile", "support", "activity", "notifications", "jobs",
]);

const text = (value) => `${value || ""}`.trim();

function safeId(value) {
  const candidate = text(value);
  return candidate && SAFE_ID.test(candidate) ? candidate : "";
}

function safeRoute(value) {
  const route = text(value).toLowerCase();
  return ALLOWED_ROUTES.has(route) ? route : "";
}

function first(...values) {
  for (const value of values) {
    const candidate = safeId(value);
    if (candidate) return candidate;
  }
  return "";
}

function explicitRoute(data = {}) {
  const nested = data.destination && typeof data.destination === "object" ? data.destination : {};
  return safeRoute(data.route || nested.route || data.destinationRoute);
}

function inferRoute(type, data, recipientRole) {
  const normalized = text(type).toLowerCase();
  const role = text(recipientRole).toLowerCase();
  const explicit = explicitRoute(data);
  if (explicit) return explicit;
  if (normalized === "new_delivery" && role === "rider") return "jobs";
  if (normalized === "chat_message" || normalized === "message" || data.chatId || data.conversationId) return "conversation";
  if (normalized.startsWith("delivery_") || normalized === "delivery" || data.deliveryId || data.bookingId || data.requestId) return "tracking";
  if (normalized === "payment" || normalized.startsWith("payment_") || normalized.startsWith("wallet_") || normalized.startsWith("roth_") || normalized.startsWith("referral_") || data.transactionId || data.walletTransactionId) return "wallet";
  if (normalized.startsWith("gift_") || data.giftId || data.giftRequestId) return "gift";
  if (normalized.startsWith("health_") || data.healthPickupId || data.pickupId) return "health";
  if (normalized.startsWith("business_") || data.businessId || data.invoiceId || data.orderId) return "business";
  if (normalized.startsWith("support_") || data.ticketId) return "support";
  if (normalized.startsWith("sender_") || normalized.includes("security") || normalized.includes("profile") || normalized.includes("account")) return "profile";
  return "notifications";
}

function canonicalDeepLink(type, data = {}, recipientRole = "sender") {
  const route = inferRoute(type, data, recipientRole);
  const link = {version: DEEP_LINK_VERSION, route};
  const deliveryId = first(data.deliveryId, data.requestId, data.bookingId, data.destination && data.destination.deliveryId);
  const bookingId = first(data.bookingId, data.requestId, data.destination && data.destination.bookingId);
  const chatId = first(data.chatId, data.conversationId, data.destination && data.destination.chatId);
  const giftId = first(data.giftId, data.giftRequestId, data.destination && data.destination.giftId);
  const healthPickupId = first(data.healthPickupId, data.pickupId, data.destination && data.destination.healthPickupId);
  const businessId = first(data.businessId, data.destination && data.destination.businessId);
  const invoiceId = first(data.invoiceId, data.destination && data.destination.invoiceId);
  const orderId = first(data.orderId, data.businessGiftOrderId, data.destination && data.destination.orderId);
  const transactionId = first(data.transactionId, data.walletTransactionId, data.paymentId, data.destination && data.destination.transactionId);
  const referralId = first(data.referralId, data.destination && data.destination.referralId);
  const ticketId = first(data.ticketId, data.destination && data.destination.ticketId);
  const action = safeId(data.action || data.subroute || data.destination && data.destination.action);

  if (route === "tracking" && deliveryId) link.deliveryId = deliveryId;
  if (route === "tracking" && bookingId) link.bookingId = bookingId;
  if (route === "jobs" && (bookingId || deliveryId)) link.bookingId = bookingId || deliveryId;
  if (route === "conversation" && chatId) link.chatId = chatId;
  if (route === "conversation" && bookingId) link.deliveryId = deliveryId || bookingId;
  if (route === "gift" && giftId) link.giftId = giftId;
  if (route === "health" && healthPickupId) link.healthPickupId = healthPickupId;
  if (route === "business" && businessId) link.businessId = businessId;
  if (route === "business" && invoiceId) link.invoiceId = invoiceId;
  if (route === "business" && orderId) link.orderId = orderId;
  if (route === "wallet" && transactionId) link.transactionId = transactionId;
  if (route === "wallet" && referralId) link.referralId = referralId;
  if (route === "support" && ticketId) link.ticketId = ticketId;
  if (action) link.action = action;

  // A route without its entity is a product landing or a safe centre fallback;
  // it is never converted into a booking/new-delivery action.
  if (route === "tracking" && !link.deliveryId && !link.bookingId) link.route = "activity";
  if (route === "conversation" && !link.chatId) link.route = "notifications";
  return link;
}

function normalizeDeepLink(raw, {type = "", data = {}, recipientRole = "sender"} = {}) {
  const candidate = raw && typeof raw === "object" ? raw : {};
  const route = safeRoute(candidate.route);
  const source = route ? {...data, ...candidate, route} : data;
  return canonicalDeepLink(type, source, recipientRole);
}

module.exports = {
  ALLOWED_ROUTES,
  DEEP_LINK_VERSION,
  canonicalDeepLink,
  normalizeDeepLink,
  safeId,
  safeRoute,
};
