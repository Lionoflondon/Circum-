#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const defaultRoot = path.resolve(__dirname, "..");

function unique(values) {
  return [...new Set(values)];
}

function sameValues(left, right) {
  return JSON.stringify([...left].sort()) === JSON.stringify([...right].sort());
}

function startsWithPrefix(file, prefix) {
  return file === prefix || file.startsWith(prefix);
}

function countOccurrences(source, token) {
  if (!token) return 0;
  return source.split(token).length - 1;
}

function normalizeWhitespace(source) {
  return `${source || ""}`.replace(/\s+/g, " ").trim();
}

function countNormalizedOccurrences(source, token) {
  return countOccurrences(normalizeWhitespace(source), normalizeWhitespace(token));
}

function literalUrlAssignment(token) {
  return normalizeWhitespace(token).match(
      /^["'](?:returnUrl|successUrl|cancelUrl)["']\s*:\s*["'](https:\/\/[^"']+)["']$/,
  )?.[1] || null;
}

function filesBelow(rootDir, relativeDirectory, suffix) {
  const found = [];
  const visit = (relativePath) => {
    const absolutePath = path.join(rootDir, relativePath);
    for (const entry of fs.readdirSync(absolutePath, {withFileTypes: true})) {
      const child = path.join(relativePath, entry.name);
      if (entry.isDirectory()) visit(child);
      if (entry.isFile() && child.endsWith(suffix)) found.push(child);
    }
  };
  visit(relativeDirectory);
  return found.sort();
}

function packageNameAt(rootDir) {
  const pubspec = fs.readFileSync(path.join(rootDir, "pubspec.yaml"), "utf8");
  return pubspec.match(/^name:\s*([A-Za-z0-9_]+)/m)?.[1] || "circum";
}

function createReader(rootDir, sourceOverrides = {}) {
  const normalizedOverrides = new Map(
      Object.entries(sourceOverrides).map(([file, source]) => [path.normalize(file), source]),
  );
  return {
    exists(file) {
      const normalized = path.normalize(file);
      return normalizedOverrides.has(normalized) ||
        fs.existsSync(path.join(rootDir, normalized));
    },
    read(file) {
      const normalized = path.normalize(file);
      if (normalizedOverrides.has(normalized)) return normalizedOverrides.get(normalized);
      return fs.readFileSync(path.join(rootDir, normalized), "utf8");
    },
  };
}

function extractDartImports(source) {
  const imports = [];
  const pattern = /^\s*(?:import|export|part)\s+['"]([^'"]+)['"][^;]*;/gm;
  let match = pattern.exec(source);
  while (match) {
    imports.push(match[1]);
    match = pattern.exec(source);
  }
  return imports;
}

function resolveDartImport(fromFile, specifier, packageName, reader) {
  const packagePrefix = `package:${packageName}/`;
  let resolved = null;
  if (specifier.startsWith(packagePrefix)) {
    resolved = `lib/${specifier.slice(packagePrefix.length)}`;
  } else if (!specifier.includes(":")) {
    resolved = path.normalize(path.join(path.dirname(fromFile), specifier));
  }
  return resolved && reader.exists(resolved) ? resolved : null;
}

function dartDependencyGraph(entrypoint, packageName, reader) {
  const pending = [entrypoint];
  const seen = new Set();
  while (pending.length > 0) {
    const file = pending.pop();
    if (!file || seen.has(file) || !reader.exists(file)) continue;
    seen.add(file);
    if (!file.endsWith(".dart")) continue;
    for (const specifier of extractDartImports(reader.read(file))) {
      const dependency = resolveDartImport(file, specifier, packageName, reader);
      if (dependency && !seen.has(dependency)) pending.push(dependency);
    }
  }
  return seen;
}

function ownersFor(file, deployManifest) {
  return Object.entries(deployManifest.products || {})
      .filter(([, product]) =>
        (product.ownedPrefixes || []).some((prefix) => startsWithPrefix(file, prefix)))
      .map(([name]) => name);
}

function allowedDependency(product, file, owners, deployManifest) {
  return (deployManifest.allowedDependencyIntersections || []).some((entry) =>
    (entry.files || []).includes(file) &&
      (entry.products || []).includes(product) &&
      owners.every((owner) => (entry.products || []).includes(owner)),
  );
}

function pureSharedFiles(deployManifest) {
  const intersectionFiles = (deployManifest.allowedDependencyIntersections || [])
      .flatMap((entry) => entry.files || []);
  return unique([...(deployManifest.sharedFiles || []), ...intersectionFiles]).sort();
}

function flowBlock(source, flow, allFlows) {
  const marker = `[RETURN_FLOWS.${flow}]`;
  const start = source.indexOf(marker);
  if (start < 0) return null;
  const laterStarts = allFlows
      .map((candidate) => source.indexOf(`[RETURN_FLOWS.${candidate}]`, start + marker.length))
      .filter((index) => index >= 0);
  const end = laterStarts.length > 0 ? Math.min(...laterStarts) : source.indexOf("});", start);
  return source.slice(start, end >= 0 ? end : source.length);
}

function extractOwnerUrl(block, ownerSymbol) {
  const escaped = ownerSymbol.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return block?.match(new RegExp(`\\[RETURN_OWNERS\\.${escaped}\\]\\s*:\\s*["']([^"']+)["']`))?.[1] || null;
}

function auditRepository(options = {}) {
  const rootDir = options.rootDir || defaultRoot;
  const reader = createReader(rootDir, options.sourceOverrides || {});
  const platformManifest = options.platformManifest ||
    JSON.parse(reader.read("platform-ownership.json"));
  const deployManifest = options.deployManifest ||
    JSON.parse(reader.read(platformManifest.authority.deployManifest));
  const packageName = packageNameAt(rootDir);
  const failures = [];
  const graphs = {};
  const fail = (message) => failures.push(message);

  if (platformManifest.version !== 1) {
    fail("platform-ownership.json: unsupported or missing version");
  }
  if (platformManifest.authority.deployManifest !== "deploy-manifest.json") {
    fail("platform ownership must defer file/deploy authority to deploy-manifest.json");
  }
  if (platformManifest.authority.absoluteOwnershipGuard !==
      "scripts/absolute_product_ownership.js") {
    fail("platform ownership must compose scripts/absolute_product_ownership.js");
  }
  if (!reader.exists(platformManifest.authority.absoluteOwnershipGuard)) {
    fail("absolute product ownership guard is missing");
  }
  if ((deployManifest.sharedFiles || []).length !== 0) {
    fail("deploy-manifest sharedFiles must remain empty under absolute product ownership");
  }
  if ((deployManifest.ignoredPrefixes || []).length !== 0) {
    fail("deploy-manifest ignoredPrefixes must remain empty under absolute product ownership");
  }

  for (const [platformProductName, product] of
    Object.entries(platformManifest.products || {})) {
    const deployProduct = deployManifest.products?.[product.deployProduct];
    if (!deployProduct) {
      fail(`${platformProductName}: deploy product ${product.deployProduct} is missing`);
      continue;
    }
    const expected = product.expectedDeploy || {};
    for (const field of ["identity", "surface", "hostingTarget", "buildDirectory"]) {
      if (deployProduct[field] !== expected[field]) {
        fail(`${platformProductName}: deploy-manifest ${field} must be ${expected[field]}`);
      }
    }
    if (!sameValues(deployProduct.entrypoints || [], expected.entrypoints || [])) {
      fail(`${platformProductName}: platform entrypoints differ from deploy-manifest`);
    }
    for (const entrypoint of expected.entrypoints || []) {
      const owners = ownersFor(entrypoint, deployManifest);
      if (!owners.includes(product.deployProduct)) {
        fail(`${platformProductName}: ${entrypoint} is not owned by ${product.deployProduct}`);
      }
    }
  }

  const rider = platformManifest.products?.rider_app;
  const riderDeploy = deployManifest.products?.[rider?.deployProduct];
  if (!rider || rider.ownership !== "external:Circum-Rider" ||
      riderDeploy?.hostingTarget !== "external:Circum-Rider" ||
      (riderDeploy?.entrypoints || []).length !== 0) {
    fail("Rider deploy/runtime ownership must remain external:Circum-Rider with no local entrypoint");
  }
  for (const prefix of rider?.localCompatibilityPrefixes || []) {
    if (!(riderDeploy?.ownedPrefixes || []).includes(prefix)) {
      fail(`Rider compatibility prefix is not Rider-owned: ${prefix}`);
    }
  }

  for (const [platformProductName, product] of
    Object.entries(platformManifest.products || {})) {
    for (const [surfaceName, surface] of Object.entries(product.surfaces || {})) {
      const label = `${platformProductName}.${surfaceName}`;
      if (!reader.exists(surface.entrypoint)) {
        fail(`${label}: entrypoint is missing: ${surface.entrypoint}`);
        continue;
      }
      const graph = dartDependencyGraph(surface.entrypoint, packageName, reader);
      graphs[label] = [...graph].sort();
      const entrypointSource = reader.read(surface.entrypoint);
      for (const token of surface.requiredEntrypointTokens || []) {
        if (!entrypointSource.includes(token)) {
          fail(`${label}: entrypoint lost required runtime boundary: ${token}`);
        }
      }
      for (const token of surface.forbiddenEntrypointTokens || []) {
        if (entrypointSource.includes(token)) {
          fail(`${label}: entrypoint contains forbidden platform startup token: ${token}`);
        }
      }
      for (const required of surface.requiredReachableFiles || []) {
        if (!graph.has(required)) {
          fail(`${label}: required product composition/config is unreachable: ${required}`);
        }
      }
      for (const file of graph) {
        const forbidden = (surface.forbiddenReachablePrefixes || [])
            .find((prefix) => startsWithPrefix(file, prefix));
        if (forbidden) {
          fail(`${label}: ${file} crosses forbidden runtime boundary ${forbidden}`);
        }
        const owners = ownersFor(file, deployManifest);
        if (owners.length === 0) {
          fail(`${label}: production-reachable source has no deploy owner: ${file}`);
        } else if (!owners.includes(product.deployProduct) &&
          !allowedDependency(product.deployProduct, file, owners, deployManifest)) {
          fail(`${label}: ${file} is owned by ${owners.join(", ")}, not ${product.deployProduct}`);
        }
      }
    }
  }

  const appCheckModules = new Map();
  for (const [productName, product] of Object.entries(platformManifest.products || {})) {
    const policy = product.appCheck;
    if (!policy) continue;
    if (!reader.exists(policy.module)) {
      fail(`${productName}: App Check module is missing: ${policy.module}`);
      continue;
    }
    if (appCheckModules.has(policy.module)) {
      fail(`${productName}: App Check module is shared with ${appCheckModules.get(policy.module)}`);
    }
    appCheckModules.set(policy.module, productName);
    const owners = ownersFor(policy.module, deployManifest);
    if (!owners.includes(product.deployProduct)) {
      fail(`${productName}: App Check module is not owned by ${product.deployProduct}`);
    }
    const source = reader.read(policy.module);
    if (!source.includes(policy.siteKey)) {
      fail(`${productName}: App Check module lost site key ${policy.siteKey}`);
    }
    for (const forbiddenKey of policy.forbiddenSiteKeys || []) {
      if (source.includes(forbiddenKey)) {
        fail(`${productName}: App Check module contains another product key ${forbiddenKey}`);
      }
    }
    for (const token of ["ReCaptchaEnterpriseProvider", "webProvider: webProvider"]) {
      if (!source.includes(token)) fail(`${productName}: Web App Check boundary is missing ${token}`);
    }
    if (policy.runtime === "web") {
      for (const token of ["AndroidProvider", "AppleProvider", "androidProvider:", "appleProvider:"]) {
        if (source.includes(token)) {
          fail(`${productName}: Web-only App Check module contains mobile provider ${token}`);
        }
      }
    }
    for (const token of policy.requiredMobileTokens || []) {
      if (!source.includes(token)) fail(`${productName}: mobile App Check policy lost ${token}`);
    }
    for (const token of policy.requiredWebGateTokens || []) {
      if (!source.includes(token)) fail(`${productName}: App Check platform gate lost ${token}`);
    }
  }

  for (const file of pureSharedFiles(deployManifest)) {
    if (!reader.exists(file)) {
      fail(`pure shared dependency is missing: ${file}`);
      continue;
    }
    const source = reader.read(file);
    for (const token of platformManifest.sharedPureCode?.forbiddenTokens || []) {
      if (source.includes(token)) {
        fail(`${file}: pure shared code contains startup/App Check/product ownership token ${token}`);
      }
    }
  }

  const stripe = platformManifest.stripeReturnOwnership || {};
  const stripeModule = stripe.authorityModule;
  const authorityReturnBases = {};
  if (!reader.exists(stripeModule)) {
    fail(`Stripe return authority is missing: ${stripeModule}`);
  } else {
    const source = reader.read(stripeModule);
    const owners = ownersFor(stripeModule, deployManifest);
    if (!owners.includes("backend")) fail("Stripe return authority must be backend-owned");
    for (const token of stripe.forbiddenAuthorityTokens || []) {
      if (source.includes(token)) {
        fail(`Stripe return authority accepts mutable/caller configuration: ${token}`);
      }
    }
    for (const token of ["resolveReturnOwner", "stripeReturnBase", "stripeReturnUrls"]) {
      if (!source.includes(token)) fail(`Stripe return authority lost ${token}`);
    }
    if (source.includes("defaultOwner") ||
      !source.includes('const owner = `${value || ""}`.trim();')) {
      fail("Stripe return authority must reject a missing owner instead of defaulting across products");
    }
    for (const flow of stripe.requiredFlows || []) {
      const block = flowBlock(source, flow, stripe.requiredFlows || []);
      if (!block) {
        fail(`Stripe return authority lost flow ${flow}`);
        continue;
      }
      authorityReturnBases[flow] = {};
      for (const [owner, prefix] of Object.entries(stripe.allowedOwners || {})) {
        const symbol = owner === "sender_app" ? "SENDER_APP" : "WEBSITE";
        const value = extractOwnerUrl(block, symbol);
        authorityReturnBases[flow][owner] = value;
        if (!value || !value.startsWith(prefix)) {
          fail(`Stripe ${flow} ${owner} return must stay under ${prefix}`);
          continue;
        }
        try {
          if (new URL(value).host !== new URL(prefix).host || new URL(value).protocol !== "https:") {
            fail(`Stripe ${flow} ${owner} return has a non-canonical host`);
          }
        } catch (_) {
          fail(`Stripe ${flow} ${owner} return is not an absolute HTTPS URL`);
        }
      }
    }
  }

  for (const file of stripe.backendCallers || []) {
    if (!reader.exists(file)) {
      fail(`Stripe backend caller is missing: ${file}`);
      continue;
    }
    const source = reader.read(file);
    if (!source.includes("returnOwner")) {
      fail(`${file}: Stripe caller does not pass a constrained returnOwner`);
    }
    for (const token of [
      "data.returnUrl",
      "data.successUrl",
      "data.cancelUrl",
      "req.body.returnUrl",
      "req.body.successUrl",
      "req.body.cancelUrl",
    ]) {
      if (source.includes(token)) fail(`${file}: caller-controlled Stripe return found: ${token}`);
    }
  }

  const flowMatrix = stripe.clientFlowMatrix || {};
  if (!sameValues(Object.keys(flowMatrix), stripe.requiredFlows || [])) {
    fail("Stripe client flow matrix must classify every backend return flow exactly once");
  }
  const declaredOwnerFiles = new Set();
  const declaredCompatibilityUrlTokens = new Set();
  const productionDartFiles = filesBelow(rootDir, "lib", ".dart");
  for (const [flow, policy] of Object.entries(flowMatrix)) {
    const declaredDiscoveryFiles = new Set(policy.discoveryFiles || []);
    for (const token of policy.discoveryTokens || []) {
      for (const file of productionDartFiles) {
        if (reader.read(file).includes(token) && !declaredDiscoveryFiles.has(file)) {
          fail(`${flow}: undeclared production Stripe callsite ${file} contains ${token}`);
        }
      }
    }
    for (const file of declaredDiscoveryFiles) {
      if (!reader.exists(file)) {
        fail(`${flow}: declared Stripe discovery file is missing: ${file}`);
        continue;
      }
      if (!(policy.discoveryTokens || []).some((token) => reader.read(file).includes(token))) {
        fail(`${flow}: ${file} no longer contains a declared checkout call`);
      }
    }
    for (const caller of policy.callers || []) {
      const {file, owner, callToken, ownerToken} = caller;
      declaredOwnerFiles.add(file);
      if (!Object.hasOwn(stripe.allowedOwners || {}, owner)) {
        fail(`${flow}: ${file} declares unsupported return owner ${owner}`);
        continue;
      }
      if (!reader.exists(file)) {
        fail(`${flow}: declared Stripe caller is missing: ${file}`);
        continue;
      }
      const source = reader.read(file);
      const callIndex = source.indexOf(callToken);
      if (callIndex < 0) {
        fail(`${flow}: ${file} lost checkout call token ${callToken}`);
        continue;
      }
      const callBlock = source.slice(Math.max(0, callIndex - 240), callIndex + 1800);
      if (!callBlock.includes(ownerToken)) {
        fail(`${flow}: ${file} checkout is not explicitly owned by ${owner}`);
      }
      const otherOwner = owner === "sender_app" ? "website" : "sender_app";
      if (callBlock.includes(`'returnOwner': '${otherOwner}'`)) {
        fail(`${flow}: ${file} checkout block crosses into ${otherOwner}`);
      }
      for (const token of caller.compatibilityTokens || []) {
        if (!normalizeWhitespace(callBlock).includes(normalizeWhitespace(token))) {
          fail(`${flow}: ${file} lost fixed legacy compatibility signal ${token}`);
          continue;
        }
        const url = literalUrlAssignment(token);
        if (url) {
          const base = authorityReturnBases[flow]?.[owner];
          const separator = base?.includes("?") ? "&" : "?";
          if (!base || (url !== base && !url.startsWith(`${base}${separator}`))) {
            fail(`${flow}: ${file} legacy compatibility URL crosses its ${owner} return base`);
          }
          declaredCompatibilityUrlTokens.add(`${file}\u0000${normalizeWhitespace(token)}`);
        }
      }
      for (const token of caller.fixedCompatibilityTokens || []) {
        if (countNormalizedOccurrences(source, token) !== 1) {
          fail(`${flow}: ${file} must declare fixed compatibility token exactly once: ${token}`);
        }
      }
      if (caller.compatibilityBridge) {
        const bridge = caller.compatibilityBridge;
        if (!reader.exists(bridge.file)) {
          fail(`${flow}: fixed compatibility bridge is missing: ${bridge.file}`);
        } else {
          const bridgeSource = reader.read(bridge.file);
          const bridgeIndex = bridgeSource.indexOf(bridge.callToken);
          if (bridgeIndex < 0) {
            fail(`${flow}: ${bridge.file} lost compatibility bridge call ${bridge.callToken}`);
          } else {
            const bridgeBlock = bridgeSource.slice(
                Math.max(0, bridgeIndex - 240),
                bridgeIndex + 1800,
            );
            for (const token of bridge.tokens || []) {
              if (!normalizeWhitespace(bridgeBlock).includes(normalizeWhitespace(token))) {
                fail(`${flow}: ${bridge.file} lost fixed legacy compatibility signal ${token}`);
                continue;
              }
              const url = literalUrlAssignment(token);
              if (url) {
                const base = authorityReturnBases[flow]?.[owner];
                const separator = base?.includes("?") ? "&" : "?";
                if (!base || (url !== base && !url.startsWith(`${base}${separator}`))) {
                  fail(`${flow}: ${bridge.file} legacy compatibility URL crosses its ${owner} return base`);
                }
                declaredCompatibilityUrlTokens.add(
                    `${bridge.file}\u0000${normalizeWhitespace(token)}`,
                );
              }
            }
          }
        }
      }
    }
  }
  const allowedLegacyUrlAssignments = new Map();
  for (const signal of stripe.legacyClientUrlSignals || []) {
    const expectedCount = Number(signal.count || 0);
    const normalizedToken = normalizeWhitespace(signal.token);
    const assignmentUrl = literalUrlAssignment(signal.token);
    const signalId = `${signal.file}\u0000${normalizedToken}`;
    if (!["returnUrl", "successUrl", "cancelUrl"].includes(signal.key) ||
      !normalizedToken.startsWith(`'${signal.key}':`) || !assignmentUrl ||
      !Number.isInteger(expectedCount) || expectedCount < 1) {
      fail(`Invalid fixed legacy Stripe signal policy for ${signal.file}`);
      continue;
    }
    if (!declaredCompatibilityUrlTokens.has(signalId)) {
      fail(`${signal.file}: legacy URL signal is not tied to a classified Stripe flow`);
    }
    if (!reader.exists(signal.file)) {
      fail(`Legacy Stripe compatibility caller is missing: ${signal.file}`);
      continue;
    }
    const actualCount = countNormalizedOccurrences(reader.read(signal.file), signal.token);
    if (actualCount !== expectedCount) {
      fail(`${signal.file}: fixed ${signal.key} must occur ${expectedCount} time(s), found ${actualCount}`);
    }
    const key = `${signal.file}\u0000${signal.key}`;
    allowedLegacyUrlAssignments.set(
        key,
        (allowedLegacyUrlAssignments.get(key) || 0) + expectedCount,
    );
  }
  for (const file of productionDartFiles) {
    const source = reader.read(file);
    for (const key of ["returnUrl", "successUrl", "cancelUrl"]) {
      const actualCount = [...source.matchAll(new RegExp(`["']${key}["']\\s*:`, "g"))].length;
      const allowedCount = allowedLegacyUrlAssignments.get(`${file}\u0000${key}`) || 0;
      if (actualCount !== allowedCount) {
        fail(`${file}: ${key} must use only classified fixed legacy URLs ` +
          `(allowed ${allowedCount}, found ${actualCount})`);
      }
    }
  }
  for (const file of productionDartFiles) {
    const source = reader.read(file);
    const declaresFixedOwner = source.includes("'returnOwner': 'sender_app'") ||
      source.includes("'returnOwner': 'website'") ||
      source.includes("returnOwner: kIsWeb ? 'sender_app' : ''");
    if (declaresFixedOwner && !declaredOwnerFiles.has(file)) {
      fail(`Unclassified Stripe returnOwner declaration in ${file}`);
    }
  }

  if (!reader.exists(stripe.senderReturnRouter)) {
    fail(`Sender in-app Stripe return router is missing: ${stripe.senderReturnRouter}`);
  } else {
    const router = reader.read(stripe.senderReturnRouter);
    for (const token of [
      "senderGiftPaymentReturnRouteName",
      "senderHealthReturnRouteName",
      "senderBusinessReturnRouteName",
      "senderWalletReturnRouteName",
      "gift_payment",
      "wallet_topup",
    ]) {
      if (!router.includes(token)) fail(`Sender in-app Stripe return router lost ${token}`);
    }
    if (router.includes("circumuk.com")) {
      fail("Sender in-app Stripe return router contains the Website host");
    }
  }

  const riderReturnModule = rider?.stripeReturnModule;
  if (!reader.exists(riderReturnModule)) {
    fail(`Rider Stripe return module is missing: ${riderReturnModule}`);
  } else {
    const source = reader.read(riderReturnModule);
    const riderUrl = `https://${rider.stripeReturnHost}`;
    const escapedRiderUrl = riderUrl.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (!new RegExp(`const\\s+appBaseUrl\\s*=\\s*["']${escapedRiderUrl}["'];`).test(source)) {
      fail(`Rider Stripe appBaseUrl must be fixed to ${riderUrl}`);
    }
    if (!source.includes("const riderStripeReturnUrl = `${appBaseUrl}/rider/stripe/return`;")) {
      fail("Rider Stripe return path is not fixed under the Rider App host");
    }
    if (!source.includes("const riderStripeRefreshUrl = `${appBaseUrl}/rider/stripe/refresh`;")) {
      fail("Rider Stripe refresh path is not fixed under the Rider App host");
    }
  }

  if (options.runAbsoluteOwnership !== false) {
    try {
      cp.execFileSync(
          process.execPath,
          [path.join(rootDir, platformManifest.authority.absoluteOwnershipGuard)],
          {cwd: rootDir, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]},
      );
    } catch (error) {
      const detail = `${error.stdout || ""}${error.stderr || ""}`.trim();
      fail(`absolute product ownership guard failed${detail ? `: ${detail}` : ""}`);
    }
  }

  return {
    ok: failures.length === 0,
    failures,
    products: Object.keys(platformManifest.products || {}),
    surfaces: Object.keys(graphs),
    productionReachableFileCount: unique(Object.values(graphs).flat()).length,
    pureSharedFiles: pureSharedFiles(deployManifest),
    stripeOwners: Object.keys(stripe.allowedOwners || {}),
  };
}

function main() {
  const report = auditRepository();
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exit(1);
}

if (require.main === module) main();

module.exports = {
  auditRepository,
  dartDependencyGraph,
  extractDartImports,
  ownersFor,
  pureSharedFiles,
  resolveDartImport,
};
