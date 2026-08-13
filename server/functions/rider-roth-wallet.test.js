/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ledgerSource = fs.readFileSync(path.join(__dirname, "roth-ledger.js"), "utf8");
const riderSource = fs.readFileSync(path.join(__dirname, "rider-account.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Rider Roth reads use App Check protected backend authorities", () => {
  assert.match(ledgerSource, /exports\.getRiderRothWallet\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
  assert.match(ledgerSource, /exports\.getRiderRothTransactions\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
  assert.match(indexSource, /exports\.getRiderRothWallet\s*=\s*rothLedger\.getRiderRothWallet/);
  assert.match(indexSource, /exports\.getRiderRothTransactions\s*=\s*rothLedger\.getRiderRothTransactions/);
  assert.match(riderSource, /exports\.ensureRiderRothWallet\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
});

test("Rider Roth wallet is a projection of the canonical ledger balance", () => {
  assert.match(ledgerSource, /collection\("wallets"\)\.doc\(identity\.walletId\)/);
  assert.match(ledgerSource, /collection\("riderRothWallets"\)\.doc\(context\.auth\.uid\)/);
  assert.match(ledgerSource, /authority:\s*"canonical_ledger_balance"/);
  assert.match(ledgerSource, /authority:\s*"projection"/);
  assert.match(ledgerSource, /projectionOf:\s*`wallets\/\$\{identity\.walletId\}`/);
  assert.doesNotMatch(riderSource, /collection\("riderRothWallets"\)[\s\S]{0,500}balance:\s*0/);
});

test("Rider Roth authority binds authentication to an existing Rider", () => {
  assert.match(ledgerSource, /if \(!context\.auth\)/);
  assert.match(ledgerSource, /collection\("riders"\)\.doc\(context\.auth\.uid\)/);
  assert.match(ledgerSource, /if \(!riderSnap\.exists\)/);
  assert.match(riderSource, /requestedRiderId !== rider\.uid/);
});

test("Rider Roth history is owner bounded and paginated", () => {
  assert.match(ledgerSource, /async function walletTransactionsPage/);
  assert.match(ledgerSource, /where\("walletId", "==", identity\.walletId\)/);
  assert.match(ledgerSource, /where\("uid", "==", uid\)/);
  assert.match(ledgerSource, /cursor\.data\(\)\.walletId !== identity\.walletId/);
  assert.match(ledgerSource, /cursor\.data\(\)\.uid !== uid/);
  assert.match(ledgerSource, /Math\.min\(50, Math\.max\(1, Math\.floor\(requestedPageSize\)\)\)/);
});

test("Rider Roth onboarding delegates to the canonical wallet authority", () => {
  assert.match(riderSource, /rothLedger\.initialiseRiderWalletRecord\(context/);
  assert.match(riderSource, /markOnboarding:\s*true/);
  assert.match(ledgerSource, /doc\(`roth_wallet_\$\{context\.auth\.uid\}`\)/);
});
