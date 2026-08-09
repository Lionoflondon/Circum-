const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const read = (file) => fs.readFileSync(path.join(__dirname, file), "utf8");
const senderBooking = read("sender-booking.js");

test("ineligible paid Sender deliveries have an explicit review recovery path", () => {
  assert.match(senderBooking, /exports\.recoverIneligibleSenderDelivery = functions\.https\.onCall/);
  assert.match(senderBooking, /status: "review_required"/);
  assert.match(senderBooking, /matchingStatus: "review_required"/);
  assert.match(senderBooking, /normalDispatchEligible: false/);
  assert.match(senderBooking, /hasCollectionProof/);
});
