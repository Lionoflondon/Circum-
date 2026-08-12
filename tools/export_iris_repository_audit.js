const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "lib/app/iris/iris_item_repository.dart"), "utf8");
const blocks = [...source.matchAll(/IrisRepositoryItem\(([\s\S]*?)\n\s*\),/g)].map((match) => match[1]);
const value = (block, key) => {
  const match = block.match(new RegExp(`${key}:\\s*(?:"([^"]*)"|'([^']*)'|([0-9.]+))`));
  return match ? match[1] || match[2] || Number(match[3]) : null;
};
const items = blocks.map((block) => ({
  id: value(block, "id"),
  item: value(block, "itemName"),
  category: value(block, "category"),
  typicalKg: value(block, "estimatedWeightKg"),
  minimumKg: value(block, "minimumWeightKg"),
  maximumKg: value(block, "maximumWeightKg"),
  aliases: (((block.match(/aliases:\s*\[([\s\S]*?)\]/) || [])[1] || "").match(/["'][^"']*["']/g) || []).map((entry) => entry.slice(1, -1)),
}));
const primary = new Map();
for (const item of items) {
  const identity = (item.aliases[0] || item.item || "").toLowerCase();
  if (!primary.has(identity)) primary.set(identity, item);
}
const csv = [["item_identity", "category", "typical_kg", "minimum_kg", "maximum_kg", "weight_status", "pricing_authority"]];
for (const item of [...primary.values()].sort((a, b) => `${a.category}:${a.item}`.localeCompare(`${b.category}:${b.item}`))) {
  csv.push([item.aliases[0] || item.item, item.category, item.typicalKg, item.minimumKg, item.maximumKg, "generic_range_unverified", "none"]);
}
const escape = (entry) => `"${`${entry ?? ""}`.replaceAll('"', '""')}"`;
const output = path.resolve(root, "..", "..", "outputs", "IRIS_REPOSITORY_WEIGHT_REGISTER_2026-08-12.csv");
fs.mkdirSync(path.dirname(output), {recursive: true});
fs.writeFileSync(output, `${csv.map((row) => row.map(escape).join(",")).join("\n")}\n`);
console.log(JSON.stringify({rows: csv.length - 1, output}, null, 2));
