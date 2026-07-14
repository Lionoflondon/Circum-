#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const riderRoot = path.resolve(root, "..", "Circum-Rider");
const indexPath = path.join(root, "server/functions/index.js");
const contractPath = path.join(root, "docs/callable-contracts.json");

const classificationOverrides = {
  getAvaliableRequests: "Legacy",
  sendMessage: "Legacy",
  sendRiderUpdate: "Legacy",
  StripePayEndpointMethodId: "Legacy",
  StripePayEndpointIntentId: "Legacy",
  calculateEarnings: "Legacy",
  endTrip: "Legacy",
  resetRiderTestStripeAccount: "Internal only",
  setFounderRiderAccess: "Internal only",
  grantRecognition: "Internal only",
  revokeRecognition: "Internal only",
};

const deprecationOverrides = {
  getAvaliableRequests:
    "Deprecated typo alias. Keep exported for compatibility; clients must use getAvailableRequests.",
  sendMessage:
    "Legacy chat callable. New clients must use sendCircumMessage.",
  sendRiderUpdate:
    "Legacy direct rider update callable. New delivery lifecycle actions must use delivery-policy callables.",
  StripePayEndpointMethodId:
    "Legacy HTTP payment endpoint retained for existing clients.",
  StripePayEndpointIntentId:
    "Legacy HTTP payment confirmation endpoint retained for existing clients.",
  calculateEarnings:
    "Legacy HTTP endpoint. Rider earnings clients should use getRiderEarningsSummary.",
  endTrip:
    "Legacy HTTP endpoint. Delivery completion should use backend delivery lifecycle callables.",
};

const productHints = [
  ["sender", /Sender|sendPackage|sender|Gift|Wallet|Business|Health|Stripe|Payment|Roth|Referral|Address|Iris|Cancellation/i],
  ["rider", /Rider|rider|Presence|AvailableRequests|Arrival|NoShow|Earnings|Withdrawal|Payout|TrackingStatus/i],
  ["admin", /Admin|review|grant|revoke|setFounder|resetRiderTest|Announcement|manageGiftStory|retryGiftStory/i],
];

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function walk(dir, files = []) {
  if (!fs.existsSync(dir)) return files;
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (["build", ".dart_tool", "node_modules", ".firebase", ".git"].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else files.push(full);
  }
  return files;
}

function ownerMap() {
  const source = read(indexPath);
  const requires = {};
  for (const match of source.matchAll(/const\s+([A-Za-z0-9_]+)\s*=\s*require\("([^"]+)"\);/g)) {
    requires[match[1]] = `server/functions/${match[2].replace(/^\.\//, "")}.js`;
  }
  const owners = {};
  for (const match of source.matchAll(/exports\.([A-Za-z0-9_]+)\s*=\s*([^;\n]+)/g)) {
    const name = match[1];
    const expression = match[2].trim();
    const moduleName = expression.split(".")[0].replace(/\(.*/, "");
    owners[name] = requires[moduleName] || "server/functions/index.js";
  }
  return owners;
}

function exportedNames() {
  return [...read(indexPath).matchAll(/exports\.([A-Za-z0-9_]+)\s*=/g)].map((match) => match[1]);
}

function parseClientReferences() {
  const roots = [
    {product: "Sender", base: root, dirs: ["lib"]},
    {product: "Rider", base: riderRoot, dirs: ["lib"]},
  ];
  const references = [];
  const constantValues = new Map();
  for (const {base, dirs} of roots) {
    for (const dir of dirs) {
      for (const file of walk(path.join(base, dir))) {
        if (!/\.(dart|js|ts|tsx|jsx)$/.test(file)) continue;
        const source = read(file);
        const relative = path.relative(base, file);
        for (const match of source.matchAll(/const\s+([A-Za-z0-9_]+)\s*=\s*['"]([A-Za-z0-9_]+)['"]/g)) {
          constantValues.set(match[1], match[2]);
        }
        for (const match of source.matchAll(/httpsCallable\(\s*['"]([A-Za-z0-9_]+)['"]/g)) {
          references.push({name: match[1], file: relative});
        }
        for (const match of source.matchAll(/httpsCallable\(\s*([A-Za-z0-9_]+)\s*\)/g)) {
          const resolved = constantValues.get(match[1]);
          if (resolved) references.push({name: resolved, file: relative});
        }
      }
    }
  }
  return references;
}

function invokedByFor(name, refs) {
  const products = new Set();
  for (const ref of refs.filter((item) => item.name === name)) {
    if (ref.file.includes("rider") || ref.file.includes("Rider")) products.add("Rider");
    if (ref.file.includes("sender") || ref.file.includes("send_package") || ref.file.includes("web_sender")) products.add("Sender");
    if (ref.file.includes("admin") || ref.file.includes("business")) products.add("Admin");
  }
  for (const [product, regex] of productHints) {
    if (regex.test(name)) products.add(product[0].toUpperCase() + product.slice(1));
  }
  return [...products].sort();
}

function purposeFor(name) {
  return name
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/^on /i, "Handle ")
    .replace(/^create /i, "Create ")
    .replace(/^get /i, "Get ")
    .replace(/^set /i, "Set ")
    .replace(/^update /i, "Update ")
    .replace(/^request /i, "Request ")
    .replace(/^mark /i, "Mark ")
    .replace(/^record /i, "Record ")
    .replace(/^sync /i, "Sync ")
    .replace(/^finalize /i, "Finalize ")
    .replace(/^cancel /i, "Cancel ");
}

function authFor(name, owner, classification) {
  if (classification === "Internal only") return "Admin/service account or scheduled backend context.";
  if (/Webhook|Landing|ThankYou|on[A-Z]|process|reset|generate|archive|cleanup|scheduled/i.test(name)) {
    return "Backend trigger, scheduler, webhook signature, or public-token guarded request as implemented.";
  }
  if (/GiftStory/.test(name) && /Access|Event|Video|Privacy/.test(name)) {
    return "Authenticated participant, admin, or signed Gift Story token depending on action.";
  }
  if (/Business/.test(name)) return "Authenticated user with Business membership where required.";
  if (/Rider|Presence|Withdrawal|AvailableRequests|Arrival|NoShow|TrackingStatus|Earnings/.test(name)) {
    return "Authenticated Rider; admin claim where explicitly required.";
  }
  return "Authenticated Firebase user unless owning function explicitly accepts a signed public token.";
}

function classify(name) {
  if (classificationOverrides[name]) return classificationOverrides[name];
  if (/^on[A-Z]|^process|^reset|^generate|^archive|^cleanup|^scheduled|Webhook$/.test(name)) return "Internal only";
  return "Canonical";
}

function buildContracts() {
  const refs = parseClientReferences();
  const owners = ownerMap();
  const exports = exportedNames();
  return exports.map((name) => {
    const classification = classify(name);
    const owner = owners[name] || "server/functions/index.js";
    const invokedBy = invokedByFor(name, refs);
    return {
      callableName: name,
      purpose: purposeFor(name),
      owningBackendFile: owner,
      invokedBy,
      inputSchema: "Validated by owning backend function. See owningBackendFile for exact accepted fields.",
      outputSchema: "Returns the owning backend function response; throws Firebase HttpsError or HTTP error on failure.",
      errorCodes: [
        "unauthenticated",
        "permission-denied",
        "invalid-argument",
        "failed-precondition",
        "not-found",
        "already-exists",
        "internal",
      ],
      authenticationRequirements: authFor(name, owner, classification),
      classification,
      deprecationStatus: deprecationOverrides[name] || "Active",
    };
  });
}

function inventory() {
  const contracts = buildContracts();
  const refs = parseClientReferences();
  const exported = new Set(contracts.map((item) => item.callableName));
  const referenced = new Set(refs.map((item) => item.name));
  return {
    exported: [...exported].sort(),
    referenced: [...referenced].sort(),
    unused: [...exported].filter((name) => !referenced.has(name)).sort(),
    missing: [...referenced].filter((name) => !exported.has(name)).sort(),
    legacy: contracts.filter((item) => item.classification === "Legacy").map((item) => item.callableName).sort(),
    duplicate: [
      {
        canonical: "getAvailableRequests",
        duplicate: "getAvaliableRequests",
        status: "Legacy typo alias retained; clients must use canonical spelling.",
      },
      {
        canonical: "sendCircumMessage",
        duplicate: "sendMessage",
        status: "Legacy chat alias retained; clients must use communication engine callables.",
      },
      {
        canonical: "createPaymentIntent",
        duplicate: "StripePayEndpointMethodId",
        status: "Legacy HTTP payment endpoint retained for old clients.",
      },
      {
        canonical: "confirmPaymentIntent",
        duplicate: "StripePayEndpointIntentId",
        status: "Legacy HTTP payment endpoint retained for old clients.",
      },
    ],
  };
}

function writeContracts() {
  fs.mkdirSync(path.dirname(contractPath), {recursive: true});
  fs.writeFileSync(contractPath, `${JSON.stringify(buildContracts(), null, 2)}\n`);
  const inv = inventory();
  const matrixRows = [
    ["Create delivery quote", "Yes", "No", "createSenderBookingQuote", "Canonical"],
    ["Create paid delivery", "Yes", "No", "createSenderPaidDelivery", "Canonical"],
    ["Legacy delivery send", "Yes", "No", "sendPackage", "Legacy compatibility"],
    ["Preview sender cancellation", "Yes", "No", "previewSenderCancellation", "Canonical"],
    ["Execute sender cancellation", "Yes", "No", "requestSenderCancellation", "Canonical"],
    ["Accept rider offer", "No", "Yes", "acceptRideRequests", "Canonical"],
    ["Get available rider offers", "No", "Yes", "getAvailableRequests", "Canonical"],
    ["Go online", "No", "Yes", "goOnline", "Canonical"],
    ["Go offline", "No", "Yes", "goOffline", "Canonical"],
    ["Update rider presence", "No", "Yes", "updateRiderPresence", "Canonical"],
    ["Record rider arrival", "No", "Yes", "recordRiderArrival", "Canonical"],
    ["Delivery status transition", "No", "Yes", "updateDeliveryTrackingStatus", "Canonical"],
    ["Rider no-show", "No", "Yes", "markRiderNoShow", "Canonical"],
    ["Waiting context", "No", "Yes", "reportWaitingContext", "Canonical"],
    ["Sender customer response", "Yes", "No", "recordCustomerArrivalResponse", "Canonical"],
    ["Delivery chat message", "Yes", "Yes", "sendCircumMessage", "Canonical"],
    ["Typing indicator", "Yes", "Yes", "setConversationTyping", "Canonical"],
    ["Mark conversation read", "Yes", "Yes", "markConversationRead", "Canonical"],
    ["Rider earnings summary", "No", "Yes", "getRiderEarningsSummary", "Canonical"],
    ["Sender wallet balance", "Yes", "No", "getSenderWallet", "Canonical"],
    ["Sender Roth balance in booking", "Yes", "No", "getSenderRothBalance", "Canonical"],
    ["Sender saved address search", "Yes", "No", "searchFreeUkAddresses", "Canonical"],
    ["Account closure", "Yes", "Yes", "closeCircumAccount", "Canonical"],
  ];
  const md = [
    "# Circum Callable Contracts",
    "",
    "Generated Phase 3 baseline. Backend exports are preserved; legacy callables are marked but not removed.",
    "",
    "## Callable Inventory",
    "",
    `- Exported: ${inv.exported.length}`,
    `- Referenced by clients/tests: ${inv.referenced.length}`,
    `- Unused exports: ${inv.unused.length}`,
    `- Missing referenced exports: ${inv.missing.length}`,
    `- Legacy exports: ${inv.legacy.join(", ") || "None"}`,
    "",
    "### Duplicate / Compatibility Exports",
    "",
    "| Canonical | Legacy / duplicate | Status |",
    "|---|---|---|",
    ...inv.duplicate.map((row) => `| ${row.canonical} | ${row.duplicate} | ${row.status} |`),
    "",
    "## Client Usage Matrix",
    "",
    "| Action | Sender | Rider | Backend Callable | Status |",
    "|---|---|---|---|---|",
    ...matrixRows.map((row) => `| ${row.join(" | ")} |`),
    "",
    "## Complete Callable Contract Source",
    "",
    "The complete machine-readable contract is stored in `docs/callable-contracts.json`.",
    "Each entry contains callable name, purpose, owning backend file, invoked products, input/output schema summary, error codes, auth requirements, classification, and deprecation status.",
    "",
  ].join("\n");
  fs.writeFileSync(path.join(root, "docs/callable-contracts.md"), md);
}

if (require.main === module) {
  const command = process.argv[2] || "inventory";
  if (command === "write") {
    writeContracts();
    process.stdout.write("Wrote docs/callable-contracts.json and docs/callable-contracts.md\n");
  } else if (command === "inventory") {
    process.stdout.write(`${JSON.stringify(inventory(), null, 2)}\n`);
  } else if (command === "contracts") {
    process.stdout.write(`${JSON.stringify(buildContracts(), null, 2)}\n`);
  } else {
    process.stderr.write("Usage: node tools/callable_contracts.js [inventory|contracts|write]\n");
    process.exit(1);
  }
}

module.exports = {
  buildContracts,
  inventory,
  parseClientReferences,
  exportedNames,
};
