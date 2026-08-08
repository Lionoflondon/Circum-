const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const read = (file) => fs.readFileSync(path.join(__dirname, file), "utf8");
const senderBooking = read("sender-booking.js");
const sendPackage = read("send-package.js");
const availableRequests = read("get-avaliable-requests.js");
const acceptRequests = read("accept-ride-requests.js");

test("normal checkout is gated by authoritative IRIS eligibility", () => {
  assert.match(senderBooking, /normalDispatchEligibilityForDeliveryPayload\(deliveryPayload\)/);
  assert.match(senderBooking, /quote\.normalCheckoutEligible !== true/);
  assert.match(senderBooking, /This delivery requires review before normal payment and dispatch/);
});

test("paid finalization revalidates eligibility and routes blocked payment to review", () => {
  assert.match(senderBooking, /recordIneligiblePaidCheckoutReview\(db/);
  assert.match(senderBooking, /Paid checkout requires review before normal dispatch/);
  assert.match(senderBooking, /reviewStatus: "manual_review"/);
});

test("dispatch and Rider offer/acceptance retain the server-side IRIS backstop", () => {
  assert.match(sendPackage, /const dispatchDecision = dispatchComplianceDecision\(deliveryRequest\[0\]\)/);
  assert.match(availableRequests, /if \(!isDispatchable\(requestData\)\) return false/);
  assert.match(acceptRequests, /if \(!isDispatchable\(deliveryRequest\)\)/);
});

test("ineligible paid Sender deliveries have an explicit review recovery path", () => {
  assert.match(senderBooking, /exports\.recoverIneligibleSenderDelivery = functions\.https\.onCall/);
  assert.match(senderBooking, /status: "review_required"/);
  assert.match(senderBooking, /matchingStatus: "review_required"/);
  assert.match(senderBooking, /normalDispatchEligible: false/);
  assert.match(senderBooking, /hasCollectionProof/);
});
