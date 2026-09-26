#!/usr/bin/env node
/* eslint-disable no-console, max-len */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {findCloudRunReplacements, productionCallers} = require("./cloud-run-replacement-registry");
const root = path.resolve(__dirname, "../..");
const registryPath = path.join(root, "docs/architecture/gen1-production-registry.json");
const reportPath = path.join(root, "docs/architecture/GEN1_PRODUCTION_EXIT.md");

function walk(dir, result = []) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if ([".git", "node_modules", "build", ".dart_tool"].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, result);
    else if (/\.(?:js|dart|json|ya?ml|md)$/.test(entry.name)) result.push(full);
  }
  return result;
}

const files = walk(root);
const textByFile = new Map(files.map((file) => [file, fs.readFileSync(file, "utf8")]));
const indexPath = path.join(__dirname, "index.js");
const indexSource = fs.readFileSync(indexPath, "utf8");
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "circum-registry-audit";
const loadedExports = require("./index");
const imports = new Map([...indexSource.matchAll(/const\s+(\w+)\s*=\s*require\("\.\/(.+?)"\)/g)]
    .map((match) => [match[1], `${match[2]}.js`]));

const functions = [...indexSource.matchAll(/exports\.([A-Za-z0-9_]+)\s*=\s*([\s\S]*?);/g)].map((match) => {
  const name = match[1];
  const expression = match[2].replace(/\s+/g, " ").trim();
  const owner = /^(\w+)\./.exec(expression);
  const bareOwner = /^(\w+)$/.exec(expression);
  const sourceFile = owner && imports.get(owner[1]) || bareOwner && imports.get(bareOwner[1]) || "index.js";
  const sourcePath = path.join(__dirname, sourceFile);
  const source = textByFile.get(sourcePath) || indexSource;
  const member = owner && /^(?:\w+)\.([A-Za-z0-9_]+)/.exec(expression);
  const definitionPattern = member ? new RegExp(`exports\\.${member[1]}\\s*=[\\s\\S]{0,900}?(?=\\nexports\\.|$)`) : null;
  const definition = definitionPattern && definitionPattern.exec(source);
  const triggerSource = sourceFile === "index.js" ? match[0] : definition && definition[0] || expression;
  const endpoint = loadedExports[name] && loadedExports[name].__endpoint || {};
  let triggerType = "callable";
  if (endpoint.eventTrigger) triggerType = "firestore-event";
  else if (endpoint.scheduleTrigger) triggerType = "schedule";
  else if (endpoint.httpsTrigger && !endpoint.callableTrigger) triggerType = "http";
  else if (/\.firestore\.|\.document\(/.test(triggerSource) && /\.on(?:Create|Update|Write|Delete)\(/.test(triggerSource)) triggerType = "firestore-event";
  else if (/\.pubsub\.schedule\(|\.scheduler\./.test(triggerSource)) triggerType = "schedule";
  else if (/\.https\.onRequest\(/.test(triggerSource)) triggerType = "http";
  const callers = [];
  const needle = new RegExp(`(?:httpsCallable\\s*\\(\\s*['"]${name}['"]|\\b${name}\\b)`);
  for (const [file, body] of textByFile) {
    if (file === indexPath || file === sourcePath || file === registryPath || file === reportPath || !needle.test(body)) continue;
    callers.push(path.relative(root, file));
  }
  const collections = [...new Set([...source.matchAll(/\.collection\(["']([^"']+)["']\)/g)].map((item) => item[1]))].sort();
  const secrets = [...new Set([
    ...[...source.matchAll(/["']([A-Z][A-Z0-9_]{3,})["']/g)].map((item) => item[1]).filter((item) => /SECRET|KEY|TOKEN|WEBHOOK/.test(item)),
    ...(endpoint.secretEnvironmentVariables || []).map((item) => item.key),
  ])].sort();
  const replacements = findCloudRunReplacements(name, files, textByFile);
  const generation = endpoint.platform === "gcfv2" ? "Gen 2" : "Gen 1";
  const migrationStatus = generation === "Gen 2" || replacements.length ? "ALREADY MIGRATED — CUT OVER REMAINING CALLERS" : triggerType === "firestore-event" ? "REPLACE WITH CLOUD RUN + EVENTARC" : triggerType === "schedule" ? "REPLACE WITH CLOUD RUN + CLOUD SCHEDULER" : ["RetrieveCardDetails", "calculateEarnings", "endTrip"].includes(name) ? "RETIRE — no legitimate production dependency" : "MIGRATE TO CLOUD RUN";
  const scannedCallers = callers.sort();
  return {
    functionName: name,
    sourceFile: `server/functions/${sourceFile}`,
    triggerType,
    triggerDefinition: endpoint.eventTrigger || endpoint.scheduleTrigger || endpoint.httpsTrigger || endpoint.callableTrigger || null,
    generation,
    productionPurpose: expression,
    callers: productionCallers(name, scannedCallers),
    criticality: /ensure|auth|account|delivery|payment|stripe|dispatch|tracking|complete|settle|notification|message|online|offline/i.test(name) ? "P0/P1-review-required" : "review-required",
    authRequired: /context\.auth|verifyIdToken|require[A-Z]/.test(source),
    appCheckRequired: ["adminResolveAccess", "adminSaveGiftRequestEditor"].includes(name) || /app.?check|enforceAppCheck/i.test(source),
    secrets,
    firestoreCollections: collections,
    externalProviders: /stripe/i.test(source) ? ["Stripe"] : [],
    idempotencyProtectionDetected: /idempoten|eventId|requestId|transaction|already[- ](?:exists|processed)|processedEvents/i.test(source),
    currentProductionRuntime: generation === "Gen 2" ? "Firebase Functions Gen 2 (Cloud Run managed) export" : "Firebase Functions Gen 1 export",
    cloudRunReplacement: replacements,
    migrationStatus,
    retirementStatus: migrationStatus.startsWith("RETIRE") ? "candidate" : "not-retired",
  };
}).sort((a, b) => a.functionName.localeCompare(b.functionName));

const v1Files = [...textByFile].filter(([, body]) => /require\(["']firebase-functions\/v1["']\)/.test(body)).map(([file]) => path.relative(root, file)).sort();
const gen1Count = functions.filter((item) => item.generation === "Gen 1").length;
const registry = {schemaVersion: 1, generatedFrom: "server/functions/index.js", sourceExportCount: functions.length, gen1ExportCount: gen1Count, firebaseFunctionsV1Files: v1Files, functions};
const json = `${JSON.stringify(registry, null, 2)}\n`;
const counts = functions.reduce((result, item) => ((result[item.migrationStatus] = (result[item.migrationStatus] || 0) + 1), result), {});
const markdown = `# Circum Gen 1 production exit registry\n\nThis source-derived registry is the reviewed baseline. CI fails if an export or a file importing \`firebase-functions/v1\` is added without regenerating and reviewing this artifact. Runtime deployment state must be certified separately before retirement. A source classification never authorizes retirement by itself; live routing, replacement health, and rollback ownership remain mandatory gates.\n\n- Source exports: ${functions.length}\n- Gen 1 exports: ${gen1Count}\n- Files importing Firebase Functions v1: ${v1Files.length}\n${Object.entries(counts).map(([name, count]) => `- ${name}: ${count}`).join("\n")}\n\n| Function | Source | Runtime | Trigger | Classification | Callers |\n|---|---|---|---|---|---|\n${functions.map((item) => `| ${item.functionName} | ${item.sourceFile} | ${item.generation} | ${item.triggerType} | ${item.migrationStatus} | ${item.callers.join("<br>") || "none found"} |`).join("\n")}\n`;

if (process.argv.includes("--check")) {
  if (!fs.existsSync(registryPath) || !fs.existsSync(reportPath) || fs.readFileSync(registryPath, "utf8") !== json || fs.readFileSync(reportPath, "utf8") !== markdown) {
    console.error("Gen 1 architecture registry drift detected. Regenerate and review it; the allowlist may not grow silently.");
    process.exit(1);
  }
  console.log(`Gen 1 architecture registry is current: ${gen1Count} Gen 1 exports, ${v1Files.length} v1 source files.`);
} else {
  fs.mkdirSync(path.dirname(registryPath), {recursive: true});
  fs.writeFileSync(registryPath, json);
  fs.writeFileSync(reportPath, markdown);
  console.log(`Wrote ${functions.length} exports to ${path.relative(root, registryPath)}.`);
}
