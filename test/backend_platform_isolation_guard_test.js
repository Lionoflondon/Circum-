"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const {
  auditRepository,
  extractDartImports,
} = require("../scripts/check_platform_isolation.js");

function read(file) {
  return fs.readFileSync(path.join(root, file), "utf8");
}

function auditWith(file, source) {
  return auditRepository({
    rootDir: root,
    runAbsoluteOwnership: false,
    sourceOverrides: {[file]: source},
  });
}

test("guard passes all current production-reachable platform boundaries", () => {
  const report = auditRepository({rootDir: root, runAbsoluteOwnership: false});
  assert.equal(report.ok, true, report.failures.join("\n"));
  assert.deepEqual(report.stripeOwners, ["sender_app", "website"]);
  assert.ok(report.productionReachableFileCount > 100);
  assert.deepEqual(report.pureSharedFiles, ["lib/env/env.dart"]);
});

test("platform manifest composes deploy ownership instead of redefining it", () => {
  const platform = JSON.parse(read("platform-ownership.json"));
  const deploy = JSON.parse(read("deploy-manifest.json"));
  assert.equal(platform.authority.deployManifest, "deploy-manifest.json");
  assert.equal(
      platform.authority.absoluteOwnershipGuard,
      "scripts/absolute_product_ownership.js",
  );
  for (const product of Object.values(platform.products)) {
    assert.ok(deploy.products[product.deployProduct]);
  }
  assert.equal(platform.products.rider_app.ownership, "external:Circum-Rider");
  assert.deepEqual(deploy.products["rider-app"].entrypoints, []);
});

test("Dart import parser covers import export and part edges", () => {
  assert.deepEqual(
      extractDartImports(`
        import 'a.dart';
        export "b.dart" show B;
        part 'c.dart';
      `),
      ["a.dart", "b.dart", "c.dart"],
  );
});

test("Website cannot import or execute the Sender mobile entrypoint", () => {
  const file = "lib/main_public_web.dart";
  const report = auditWith(file, `import 'main.dart';\n${read(file)}`);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("website.web") && failure.includes("lib/main.dart")));
});

test("Sender mobile cannot import Website startup or configuration", () => {
  const file = "lib/main.dart";
  const report = auditWith(
      file,
      `import 'website/shared/firebase/website_firebase_options.dart';\n${read(file)}`,
  );
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("sender_app.mobile") && failure.includes("lib/website/")));
});

test("Web-only App Check modules reject mobile providers", () => {
  const file = "lib/website/shared/security/circum_website_app_check.dart";
  const report = auditWith(file, `${read(file)}\nfinal leak = AndroidProvider.debug;\n`);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("website") && failure.includes("AndroidProvider")));
});

test("pure shared code rejects startup and product ownership", () => {
  const file = "lib/env/env.dart";
  const report = auditWith(file, `${read(file)}\n// Firebase.initializeApp\n`);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes(file) && failure.includes("Firebase.initializeApp")));
});

test("Stripe authority rejects caller-controlled return URLs", () => {
  const file = "server/functions/stripe-return-ownership.js";
  const report = auditWith(file, `${read(file)}\nconst leak = data.returnUrl;\n`);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("caller configuration") && failure.includes("data.returnUrl")));
});

test("Stripe authority rejects a missing-owner Website default", () => {
  const file = "server/functions/stripe-return-ownership.js";
  const source = read(file).replace(
      'const owner = `${value || ""}`.trim();',
      'const owner = `${value || ""}`.trim() || RETURN_OWNERS.WEBSITE;',
  );
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) => failure.includes("reject a missing owner")));
});

test("Stripe client matrix rejects an unclassified production caller", () => {
  const file = "lib/app/sender_mobile/sender_wallet.dart";
  const report = auditWith(
      file,
      `${read(file)}\n// httpsCallable('createWalletTopUp')\n`,
  );
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("WALLET_TOP_UP") && failure.includes(file)));
});

test("Stripe rollout bridge rejects a runtime client return URL", () => {
  const file = "lib/app/sender_mobile/gift_payment_view.dart";
  const source = `${read(file)}\nconst unsafe = {'returnUrl': runtimeReturnUrl};\n`;
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes(file) && failure.includes("returnUrl") &&
      failure.includes("only classified fixed legacy URLs")));
});

test("Stripe rollout bridge rejects a cross-owner compatibility host", () => {
  const file = "lib/app/business/business_repository.dart";
  const source = read(file).replace(
      "https://circum-app-2797c.web.app/?app=business&section=invoicing",
      "https://circumuk.com/send/business?section=invoicing",
  );
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("BUSINESS_INVOICE") && failure.includes("legacy compatibility")));
});

test("Stripe rollout bridge pins the legacy Gifts source signal", () => {
  const file = "lib/app/sender_mobile/gift_campaign_view.dart";
  const source = read(file).replace(
      "const senderGiftCampaignPaymentSource = 'sender_mobile_campaign';",
      "const senderGiftCampaignPaymentSource = 'website';",
  );
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("GIFT") && failure.includes("fixed compatibility token")));
});

test("Stripe owner map rejects cross-host Sender returns", () => {
  const file = "server/functions/stripe-return-ownership.js";
  const source = read(file).replace(
      "https://circum-app-2797c.web.app/?app=business&section=invoicing",
      "https://circumuk.com/send/business?section=invoicing",
  );
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) =>
    failure.includes("BUSINESS_INVOICE sender_app")));
});

test("Rider Stripe ownership cannot be redirected to Website", () => {
  const file = "server/functions/rider-connect.js";
  const source = read(file).replace(
      "const appBaseUrl = \"https://circum-rider-2797c.web.app\";",
      "const appBaseUrl = \"https://circumuk.com\";",
  );
  const report = auditWith(file, source);
  assert.equal(report.ok, false);
  assert.ok(report.failures.some((failure) => failure.includes("Rider Stripe appBaseUrl")));
});
