const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("Rider withdrawal cancellation is callable and audited", () => {
  const functionsDir = __dirname;
  const riderConnect = fs.readFileSync(
      path.join(functionsDir, "rider-connect.js"),
      "utf8",
  );
  const index = fs.readFileSync(path.join(functionsDir, "index.js"), "utf8");

  assert.match(riderConnect, /function cancelRiderWithdrawal\(\)/);
  assert.match(riderConnect, /collection\("riderPayoutAudit"\)\.add/);
  assert.match(riderConnect, /action: "withdrawal_cancelled"/);
  assert.match(riderConnect, /status: "cancelled"/);
  assert.match(index, /exports\.cancelRiderWithdrawal/);
});
