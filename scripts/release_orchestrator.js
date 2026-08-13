#!/usr/bin/env node
/* eslint-disable no-console */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

const root = path.resolve(__dirname, "..");
const reportPath = path.join(root, "deployment_report.md");
const argv = process.argv.slice(2);
const argSet = new Set(argv);
const shouldDeploy = argSet.has("--deploy");
const full = argSet.has("--full");
const functionsScopeOptions = argv.filter((arg) => arg.startsWith("--functions="));
if (argv.includes("--functions") || functionsScopeOptions.length > 1) {
  console.error("Use exactly one --functions=name1,name2 option.");
  process.exit(64);
}
const requestedFunctions = functionsScopeOptions.length === 1 ?
  functionsScopeOptions[0].slice("--functions=".length) : null;
const mode = argv.find((arg) => !arg.startsWith("--")) || "changed";
const maxFunctionsPerDeploy = 10;

function resolveFunctionsDeployScope(requested) {
  if (requested === null) return null;
  const names = requested.split(",").map((name) => name.trim()).filter(Boolean);
  if (names.length === 0) {
    throw new Error("--functions requires at least one exported Function name.");
  }
  const unique = [...new Set(names)];
  if (unique.length !== names.length) {
    throw new Error("--functions must not contain duplicate Function names.");
  }
  if (unique.length > maxFunctionsPerDeploy) {
    throw new Error(
        `--functions is limited to ${maxFunctionsPerDeploy} names per narrow deployment.`,
    );
  }
  const result = cp.spawnSync(
      process.execPath,
      [path.join(root, "scripts/scoped_functions_deploy_list.js"), "--only", unique.join(",")],
      {cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]},
  );
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "Invalid Functions scope.").trim());
  }
  const scope = result.stdout.trim();
  if (!scope || scope.split(",").length !== unique.length ||
      scope.split(",").some((entry) => !/^functions:[A-Za-z0-9_]+$/.test(entry))) {
    throw new Error("Functions scope resolver returned an invalid deployment target.");
  }
  return scope;
}

let functionsDeployScope = null;
try {
  functionsDeployScope = resolveFunctionsDeployScope(requestedFunctions);
} catch (error) {
  console.error(`Functions deployment blocked: ${error.message}`);
  process.exit(64);
}

function run(command, options = {}) {
  const startedAt = Date.now();
  try {
    const output = cp.execSync(command, {
      cwd: options.cwd || root,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: {...process.env, CI: "true"},
      timeout: options.timeoutMs || 15 * 60 * 1000,
    });
    return {ok: true, command, ms: Date.now() - startedAt, output: output.trim()};
  } catch (error) {
    return {
      ok: false,
      command,
      ms: Date.now() - startedAt,
      output: `${error.stdout || ""}${error.stderr || ""}`.trim(),
      code: error.status || 1,
    };
  }
}

function exists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
}

function changedFiles() {
  const status = run("git status --porcelain=v1 --untracked-files=all");
  if (!status.ok || !status.output) return [];
  return [...new Set(status.output.split("\n")
      .filter(Boolean)
      .flatMap((line) => {
        const file = line.replace(/^[ MADRCU?!]{1,2}\s+/, "").trim();
        return file.includes(" -> ") ?
          file.split(" -> ").map((part) => part.trim()) :
          [file];
      })
      .filter((file) => file && file !== ".firebase/" &&
        !file.startsWith(".firebase/")))];
}

function startsWithAny(file, prefixes) {
  return prefixes.some((prefix) => file === prefix || file.startsWith(prefix));
}

function classify(file) {
  if (file.startsWith("lib/app/rider_") ||
      file.startsWith("lib/main_rider") ||
      file.startsWith("test/rider_") ||
      file.includes("rider_deployment_manifest")) {
    return "rider-external";
  }
  if (file === "firestore.rules") return "firestore-rules";
  if (file === "storage.rules") return "storage-rules";
  if (file === "firestore.indexes.json") return "indexes";
  if (file.startsWith("server/functions/")) return "functions";
  if (file.startsWith("lib/app/admin/") ||
      file === "lib/main_admin_web.dart" ||
      file.startsWith("test/admin_") ||
      file.startsWith("scripts/build_admin") ||
      file.startsWith("scripts/deploy_admin") ||
      file.includes("deploy_admin")) {
    return "admin";
  }
  if (file.startsWith("lib/website/") ||
      file === "lib/main_public_web.dart" ||
      file === "lib/web_platform_routing.dart" ||
      file.startsWith("scripts/build_public") ||
      file.startsWith("scripts/deploy_public") ||
      file.includes("deploy_website") ||
      file.startsWith("test/website_") ||
      file === "test/web_platform_routing_test.dart") {
    return "website";
  }
  if (file.startsWith("lib/app/sender_mobile/") ||
      file.startsWith("lib/app/send_package/") ||
      file.startsWith("lib/app/sender_profile/") ||
      file.startsWith("lib/app/account/") ||
      file.startsWith("lib/app/authentication/") ||
      file.startsWith("lib/app/iris/") ||
      file.startsWith("lib/app/support/") ||
      file.startsWith("lib/app/media/") ||
      file.startsWith("lib/app/security/") ||
      file === "lib/main.dart" ||
      file === "lib/app.dart" ||
      file === "lib/messaging.dart" ||
      file.startsWith("scripts/build_sender") ||
      file.startsWith("scripts/deploy_sender") ||
      file.includes("deploy_sender") ||
      file.startsWith("test/sender") ||
      file.startsWith("test/sender_mobile/") ||
      file.startsWith("test/iris_") ||
      file.startsWith("test/gift") ||
      file.startsWith("test/health_plus") ||
      file.startsWith("test/vanguard")) {
    return "sender";
  }
  if (file.startsWith(".github/workflows/")) return "ci";
  if (file === "test/security/circum_app_check_contract_test.dart" ||
      file === "test/web_artifact_isolation_test.dart") {
    return "release-tooling";
  }
  if (file.startsWith("docs/") || file === "README.md") return "documentation";
  if (file === "PRODUCTION_DIAGNOSTICS.md" ||
      file.includes("startup_diagnostics")) return "diagnostics";
  if (file.startsWith("scripts/") ||
      file === "safe_release.sh" ||
      file === "deployment_report.md" ||
      file === "deploy-manifest.json" ||
      file === "firebase.json") {
    return "release-tooling";
  }
  if (file.startsWith("android/") || file.startsWith("ios/") ||
      file.startsWith("assets/") || file === "pubspec.yaml" ||
      file === "pubspec.lock") {
    return "sender";
  }
  return "unknown";
}

const targets = [
  {
    key: "sender",
    name: "Sender App",
    lanes: ["sender"],
    deployable: false,
    manual: true,
    manualReason: "Mobile app publishing is manual.",
    build: full ? "flutter build apk --debug" : null,
  },
  {
    key: "sender-web",
    aliases: ["sender"],
    name: "Sender Web",
    lanes: ["sender", "release-tooling", "ci", "diagnostics"],
    artifactGate: "node scripts/validate_web_artifacts.js --surface=sender-app",
    artifacts: [
      "build/sender_app_web/index.html",
      "build/sender_app_web/main.dart.js",
      "build/sender_app_web/circum-surface.json",
    ],
    deploy: "firebase deploy --only hosting:app --project circum-2797c",
    hostingTarget: "hosting:app",
  },
  {
    key: "website",
    name: "Public Website",
    lanes: ["website", "release-tooling", "ci"],
    artifactGate: "node scripts/validate_web_artifacts.js --surface=website",
    artifacts: [
      "build/public_web/index.html",
      "build/public_web/main.dart.js",
      "build/public_web/circum-surface.json",
    ],
    deploy: "firebase deploy --only hosting:public --project circum-2797c",
    hostingTarget: "hosting:public",
  },
  {
    key: "admin",
    name: "Admin",
    lanes: ["admin", "release-tooling", "ci"],
    artifactGate: "node scripts/validate_web_artifacts.js --surface=admin",
    artifacts: [
      "build/web_admin/index.html",
      "build/web_admin/main.dart.js",
      "build/web_admin/circum-surface.json",
    ],
    deploy: "firebase deploy --only hosting:admin --project circum-2797c",
    hostingTarget: "hosting:admin",
  },
  {
    key: "functions",
    name: "Cloud Functions",
    lanes: ["functions", "release-tooling", "ci"],
    tests: full ? ["cd server/functions && npm test"] : [],
    requiresFunctionsScope: true,
    deploy: functionsDeployScope ?
      `firebase deploy --only "${functionsDeployScope}" --project circum-2797c` :
      null,
  },
  {
    key: "rules",
    aliases: ["firestore-rules"],
    name: "Firestore Rules",
    lanes: ["firestore-rules"],
    artifacts: ["firestore.rules"],
    tests: full ? ["cd server/functions && npm run test:rules"] : [],
    deploy: "firebase deploy --only firestore:rules --project circum-2797c",
  },
  {
    key: "storage",
    aliases: ["storage-rules"],
    name: "Storage Rules",
    lanes: ["storage-rules"],
    artifacts: ["storage.rules"],
    deploy: "firebase deploy --only storage --project circum-2797c",
  },
  {
    key: "indexes",
    name: "Indexes",
    lanes: ["indexes"],
    artifacts: ["firestore.indexes.json"],
    deploy: "firebase deploy --only firestore:indexes --project circum-2797c",
  },
  {
    key: "rider",
    name: "Rider",
    lanes: ["rider-external"],
    external: true,
  },
];

function selfTest() {
  const cases = [
    ["lib/app/sender_mobile/home.dart", "sender"],
    ["lib/website/shared/app.dart", "website"],
    ["lib/app/admin/shell.dart", "admin"],
    ["server/functions/index.js", "functions"],
    ["firestore.rules", "firestore-rules"],
    ["storage.rules", "storage-rules"],
    ["firestore.indexes.json", "indexes"],
    ["lib/main_rider_web.dart", "rider-external"],
    ["docs/safe-release-orchestrator.md", "documentation"],
  ];
  const failures = cases.filter(([file, expected]) => classify(file) !== expected);
  if (failures.length) {
    console.error("SELF TEST FAILED");
    for (const [file, expected] of failures) {
      console.error(`${file}: expected ${expected}, got ${classify(file)}`);
    }
    process.exit(1);
  }
  console.log("SELF TEST PASS");
}

if (argSet.has("--self-test")) selfTest();
if (argSet.has("--self-test")) process.exit(0);

function selectedTargets(filesByLane) {
  if (mode === "all") return targets;
  if (mode === "changed") {
    return targets.filter((target) =>
      target.lanes.some((lane) => (filesByLane.get(lane) || []).length > 0));
  }
  const selected = targets.find((target) =>
    target.key === mode || (target.aliases || []).includes(mode));
  if (!selected) {
    console.error("Usage: node scripts/release_orchestrator.js " +
      "[changed|sender|website|admin|functions|rules|storage|indexes|all] " +
      "[--full] [--deploy] [--functions=name1,name2] [--self-test]");
    process.exit(64);
  }
  return [selected];
}

function candidateFiles(target, filesByLane) {
  return target.lanes.flatMap((lane) => filesByLane.get(lane) || []);
}

function validate(target, files, allFilesByLane) {
  const checks = [];
  const fail = (name, detail) => checks.push({ok: false, name, detail});
  const pass = (name, detail = "PASS") => checks.push({ok: true, name, detail});

  if (target.external) {
    fail("repository", "Owned by Circum-Rider repository");
    return checks;
  }

  const unknown = allFilesByLane.get("unknown") || [];
  const rider = allFilesByLane.get("rider-external") || [];
  if (unknown.length && mode !== target.key) {
    pass("unknown changes", `ignored outside ${target.name}`);
  }
  if (rider.length && target.key !== "rider") {
    pass("Rider changes", "skipped: owned by Circum-Rider repository");
  }

  const manifest = readJson("deploy-manifest.json");
  pass("deployment manifest", Object.keys(manifest.products || {}).join(", "));

  const diff = run("git diff --check");
  diff.ok ? pass("git diff --check") : fail("git diff --check", diff.output);

  if (full) {
    const analyze = run(
        "flutter analyze --no-fatal-warnings --no-fatal-infos",
        {timeoutMs: 20 * 60 * 1000},
    );
    analyze.ok ? pass("flutter analyze") : fail("flutter analyze", analyze.output);
    const tests = run("flutter test", {timeoutMs: 20 * 60 * 1000});
    tests.ok ? pass("flutter test") : fail("flutter test", tests.output);
  }

  for (const command of target.tests || []) {
    const result = run(command, {timeoutMs: 20 * 60 * 1000});
    result.ok ? pass(command) : fail(command, result.output);
  }

  if (target.artifacts) {
    const missing = target.artifacts.filter((artifact) => !exists(artifact));
    missing.length ? fail("target artifacts", `missing: ${missing.join(", ")}`) :
      pass("target artifacts", "present");
  }

  if (target.artifactGate && target.artifacts &&
      target.artifacts.every((artifact) => exists(artifact))) {
    const artifact = run(target.artifactGate);
    artifact.ok ? pass("artifact gate") : fail("artifact gate", artifact.output);
  }

  if (target.build && shouldDeploy) {
    const build = run(target.build, {timeoutMs: 30 * 60 * 1000});
    build.ok ? pass("build") : fail("build", build.output);
  }

  if (target.requiresFunctionsScope && !functionsDeployScope) {
    fail(
        "deploy command",
        `Explicit --functions=name1,name2 scope required (maximum ${maxFunctionsPerDeploy}).`,
    );
  } else if (target.deployable === false || !target.deploy) {
    fail("deploy command", target.manualReason || "No deploy command configured");
  }

  if (files.length === 0) pass("change set", "NO CHANGES");
  else pass("change set", `${files.length} file(s) in lane`);

  return checks;
}

function statusFor(target, files, checks) {
  if (target.external) return "EXTERNAL";
  if (target.manual) return files.length === 0 ? "NO CHANGES" : "MANUAL";
  if (files.length === 0) return "NO CHANGES";
  return checks.some((check) => !check.ok) ? "NOT SAFE" : "SAFE";
}

function deploy(target) {
  if (!shouldDeploy || !target.deploy) return null;
  const timestamp = new Date().toISOString();
  const result = run(target.deploy, {timeoutMs: 30 * 60 * 1000});
  return {timestamp, result};
}

function format(results, filesByLane) {
  const clean = (value) => `${value}`.split("\n")
      .map((line) => line.trimEnd())
      .join("\n");
  const lines = ["# SAFE RELEASE REPORT", ""];
  for (const result of results) {
    lines.push(`## ${result.name}`);
    lines.push("");
    lines.push(result.status);
    if (result.files.length) {
      lines.push("");
      lines.push("Changed files:");
      result.files.forEach((file) => lines.push(`- ${file}`));
    }
    const failures = result.checks.filter((check) => !check.ok);
    if (failures.length) {
      lines.push("");
      lines.push("Reasons:");
      failures.forEach((check) =>
        lines.push(`- ${check.name}: ${clean(check.detail)}`));
    }
    if (result.deployment) {
      lines.push("");
      lines.push(`Deployment: ${result.deployment.result.ok ? "PASS" : "FAIL"}`);
      lines.push(`Timestamp: ${result.deployment.timestamp}`);
    }
    lines.push("");
  }

  const untouched = targets.filter((target) =>
    !results.some((result) => result.key === target.key));
  if (untouched.length) {
    lines.push("## Untouched Targets");
    lines.push("");
    untouched.forEach((target) => lines.push(`- ${target.name}: NO CHANGES`));
    lines.push("");
  }

  const deployable = results.filter((result) => result.status === "SAFE").length;
  const blocked = results.filter((result) => result.status === "NOT SAFE").length;
  const skipped = results.filter((result) =>
    ["NO CHANGES", "EXTERNAL", "MANUAL"].includes(result.status)).length +
    untouched.length;
  lines.push("## Deploy Summary");
  lines.push("");
  lines.push(`Deployable: ${deployable}`);
  lines.push(`Skipped: ${skipped}`);
  lines.push(`Blocked: ${blocked}`);
  lines.push(`Mode: ${mode}${shouldDeploy ? " --deploy" : ""}${full ? " --full" : ""}`);
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push("");
  lines.push("## Change Classification");
  lines.push("");
  for (const [lane, files] of [...filesByLane.entries()].sort()) {
    lines.push(`- ${lane}: ${files.length}`);
    if (lane === "unknown" || lane === "rider-external") {
      files.forEach((file) => lines.push(`  - ${file}`));
    }
  }
  return lines.join("\n");
}

const files = changedFiles();
const filesByLane = new Map();
for (const file of files) {
  const lane = classify(file);
  if (!filesByLane.has(lane)) filesByLane.set(lane, []);
  filesByLane.get(lane).push(file);
}

const selected = selectedTargets(filesByLane);
if (shouldDeploy && selected.some((target) => target.requiresFunctionsScope) &&
    !functionsDeployScope) {
  console.error(
      "Functions deployment blocked before any target was deployed: " +
      "explicit --functions=name1,name2 scope is required.",
  );
  process.exit(64);
}
const results = selected.map((target) => {
  const filesForTarget = candidateFiles(target, filesByLane);
  const checks = validate(target, filesForTarget, filesByLane);
  const status = statusFor(target, filesForTarget, checks);
  const deployment = status === "SAFE" ? deploy(target) : null;
  if (deployment && !deployment.result.ok) {
    checks.push({ok: false, name: "deploy", detail: deployment.result.output});
  }
  return {
    key: target.key,
    name: target.name,
    status: deployment && deployment.result.ok ? "DEPLOYED" : status,
    files: filesForTarget,
    checks,
    deployment,
  };
});

const report = `${format(results, filesByLane)}\n`;
fs.writeFileSync(reportPath, report);
console.log(report);

if (results.some((result) => result.status === "NOT SAFE")) process.exitCode = 1;
