const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const policy = fs.readFileSync(require('node:path').join(__dirname, 'delivery-policy.js'), 'utf8');

test('Rider cancellation is a dedicated App Check callable', () => {
  assert.match(policy, /exports\.requestRiderCancellation\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
  assert.match(policy, /RIDER_CANCEL_REASONS/);
  assert.match(policy, /assertAssignedRider\(uid, delivery\)/);
});

test('Rider cancellation redispatches before pickup and rejects custody', () => {
  assert.match(policy, /RIDER_PRE_PICKUP_STATES/);
  assert.match(policy, /RIDER_CUSTODY_STATES/);
  assert.match(policy, /This delivery is in custody/);
  assert.match(policy, /matchingStatus: "requested"/);
  assert.match(policy, /activeDeliveries.*delete|delete\(db\.collection\("activeDeliveries"\)/s);
});

test('Rider cancellation is exported from the Functions entrypoint', () => {
  const index = fs.readFileSync(require('node:path').join(__dirname, 'index.js'), 'utf8');
  assert.match(index, /exports\.requestRiderCancellation\s*=\s*deliveryPolicy\.requestRiderCancellation/);
});
