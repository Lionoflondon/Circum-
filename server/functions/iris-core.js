/* eslint-disable max-len, require-jsdoc */
const vehicleDispatch = require("./vehicle-dispatch");
const CATEGORIES = Object.freeze([
  "Documents",
  "Electronics",
  "Clothing & Fashion",
  "Personal Items & Luggage",
  "Food & Consumables",
  "Furniture & Home",
  "Tools & Machinery",
  "Medical & Pharmacy",
  "Business & Commercial",
  "Fragile & Valuable",
  "Other",
]);

const WEIGHT_BANDS = Object.freeze([
  {id: "small_parcel", label: "Small Parcel", minKg: 0, maxKg: 2, baseGbp: 0},
  {id: "medium_parcel", label: "Medium Parcel", minKg: 2, maxKg: 10, baseGbp: 3},
  {id: "large_parcel", label: "Large Parcel", minKg: 10, maxKg: 25, baseGbp: 8},
  {id: "heavy_goods", label: "Heavy Goods", minKg: 25, maxKg: 50, baseGbp: 18},
  {id: "heavy_duty_freight", label: "Heavy Duty Freight", minKg: 50, maxKg: null, baseGbp: 35},
]);

const HANDLING_FLAGS = Object.freeze([
  "Fragile",
  "Perishable",
  "Keep Upright",
  "High Value",
  "Temperature Sensitive",
  "Bulky",
  "Awkward Shape",
  "Van Required",
  "Two Person Lift",
]);

const COMPLIANCE_STATUSES = Object.freeze(["allowed", "unsupported", "prohibited"]);
const REFERRAL_TYPES = Object.freeze([
  "vehicle_transport",
  "pet_transport",
  "funeral_transport",
  "specialist_freight",
]);
const INTERNAL_CONTEXTS = Object.freeze(["domestic", "commercial", "industrial"]);

const OBJECT_MAPPINGS = Object.freeze([
  {
    id: "tv_remote",
    patterns: [/\btv remote\b/, /\btelevision remote\b/, /\bremote control\b/],
    category: "Electronics",
    weightKg: 0.2,
    handlingFlags: ["Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "usb_cable",
    patterns: [/\busb cable\b/, /\bcharging cable\b/, /\bphone charger\b/, /\bcharger cable\b/],
    category: "Electronics",
    weightKg: 0.1,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "smart_watch",
    patterns: [/\bapple watch\b/, /\bsmart watch\b/, /\bsmartwatch\b/],
    category: "Electronics",
    weightKg: 0.2,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "jewellery",
    patterns: [/\bwedding ring\b/, /\bring\b/, /\bjewellery\b/, /\bjewelry\b/, /\bluxury watch\b/],
    category: "Fragile & Valuable",
    weightKg: 0.1,
    handlingFlags: ["High Value"],
    vehicleRequired: "any",
  },
  {
    id: "dresser_cabinet",
    patterns: [/\bdresser cabinet\b/, /\bdresser\b/, /\bdrawer cabinet\b/],
    category: "Furniture & Home",
    weightKg: 35,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "chest_of_drawers",
    patterns: [/\bchest of drawers\b/, /\bdrawers\b/],
    category: "Furniture & Home",
    weightKg: 35,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "bicycle",
    patterns: [/\bbicycle\b/, /\bbike\b/, /\bcycle\b/],
    category: "Personal Items & Luggage",
    weightKg: 14,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "tv",
    patterns: [/\b(65[- ]?inch|65in|large|massive|big screen)\s+(tv|television|telly)\b/, /\btelly\b/, /\bbig screen\b/, /\btv\b/, /\btelevision\b/],
    category: "Electronics",
    weightKg: 32,
    handlingFlags: ["Fragile", "Keep Upright", "Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "laptop",
    patterns: [/\blaptops?\b/, /\bmacbooks?\b/, /\bnotebook computers?\b/],
    category: "Electronics",
    weightKg: 2,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "iphone",
    patterns: [/\biphones?\b/, /\bsmartphones?\b/, /\bmobile phones?\b/],
    category: "Electronics",
    weightKg: 0.3,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "medication",
    patterns: [/\bmedication\b/, /\bmedicine\b/, /\bprescription\b/, /\bpharmacy\b/],
    category: "Medical & Pharmacy",
    weightKg: 0.5,
    handlingFlags: ["Temperature Sensitive"],
    vehicleRequired: "any",
  },
  {
    id: "sofa",
    patterns: [/\bsofa\b/, /\bcouch\b/],
    category: "Furniture & Home",
    weightKg: 45,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "mattress",
    patterns: [/\bmattress\b/],
    category: "Furniture & Home",
    weightKg: 30,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "rug",
    patterns: [/\brug\b/, /\brolled rug\b/, /\bcarpet\b/],
    category: "Furniture & Home",
    weightKg: 18,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "books",
    patterns: [/\bbox of books\b/, /\bbooks\b/],
    category: "Personal Items & Luggage",
    weightKg: 12,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "car_tyre",
    patterns: [/\bcar tyre\b/, /\bcar tire\b/, /\btyre\b/, /\btire\b/],
    category: "Tools & Machinery",
    weightKg: 10,
    handlingFlags: ["Bulky", "Awkward Shape"],
    vehicleRequired: "any",
  },
  {
    id: "appliance",
    patterns: [/\bfridge\b/, /\bfreezer\b/, /\bwashing machine\b/, /\bdishwasher\b/, /\bappliance\b/],
    category: "Furniture & Home",
    weightKg: 45,
    handlingFlags: ["Bulky", "Keep Upright", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "electronics",
    patterns: [/\belectronics\b/, /\btablets?\b/, /\bcameras?\b/, /\bconsole\b/, /\bmonitor\b/, /\bdesktop pc\b/, /\bdesktop computer\b/, /\bprojector\b/, /\bserver rack\b/],
    category: "Electronics",
    weightKg: 2,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "furniture",
    patterns: [/\bfurniture\b/, /\bwardrobe\b/, /\bcabinet\b/, /\btable\b/, /\bdining chairs?\b/, /\bchairs?\b/, /\bbed\b/, /\bhouse move\b/, /\bbedroom\b/, /\bgarage contents\b/],
    category: "Furniture & Home",
    weightKg: 30,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "wedding_dress",
    patterns: [/\bwedding dresses\b/, /\bwedding dress\b/],
    category: "Clothing & Fashion",
    weightKg: 2,
    handlingFlags: ["High Value"],
    vehicleRequired: "any",
  },
  {
    id: "flowers_plants",
    patterns: [/\bflowers?\b/, /\bplants?\b/],
    category: "Food & Consumables",
    weightKg: 1,
    handlingFlags: ["Perishable", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "perfume",
    patterns: [/\bperfumes?\b/, /\bfragrance\b/, /\bcologne\b/],
    category: "Fragile & Valuable",
    weightKg: 0.5,
    handlingFlags: ["Fragile", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "blood_samples",
    patterns: [/\bblood samples?\b/, /\bmedical samples?\b/, /\blab samples?\b/],
    category: "Medical & Pharmacy",
    weightKg: 0.5,
    handlingFlags: ["Temperature Sensitive", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "construction_materials",
    patterns: [/\bbricks?\b/, /\btiles?\b/, /\bconcrete\b/, /\btimber\b/, /\bconcrete mixer\b/],
    category: "Tools & Machinery",
    weightKg: 75,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
]);

const PRICING = Object.freeze({
  baseFareGbp: 6,
  additionalFarePerMileGbp: 1,
  includedBaseMiles: 1,
  shortTripFareFloorMiles: 1.6,
  longDistanceThresholdMiles: 20,
  longDistanceMileageMultiplier: 1.2,
  modifiers: {
    fragile: 5,
    perishable: 4,
    keepUpright: 3,
    highValue: 8,
    temperatureSensitive: 8,
    bulky: 10,
    awkwardShape: 6,
    vanRequired: 10,
    twoPersonLift: 25,
    express: 5,
  },
});

function normalize(value) {
  return `${value || ""}`.toLowerCase().replace(/[^a-z0-9.+\s-]/g, " ").replace(/\s+/g, " ").trim();
}

function includesAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function detectObject(text) {
  return OBJECT_MAPPINGS.find((mapping) =>
    mapping.patterns.some((pattern) => pattern.test(text))) || null;
}

function parseQuantity(text) {
  const normalized = normalize(text);
  const quantityNouns = "(laptops?|macbooks?|phones?|smartphones?|dresses|chairs?|books?|monitors?|tablets?|cameras?|boxes|parcels|items|suitcases?|bags?)";
  const numeric = normalized.match(new RegExp(`\\b(\\d{1,4})\\s+(?:[a-z]+\\s+){0,2}${quantityNouns}\\b`));
  if (numeric) return Math.max(1, Number(numeric[1]));
  const words = {
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10,
    twenty: 20,
    fifty: 50,
    hundred: 100,
  };
  for (const [word, value] of Object.entries(words)) {
    if (new RegExp(`\\b${word}\\s+(?:[a-z]+\\s+){0,2}${quantityNouns}\\b`).test(normalized)) return value;
  }
  return 1;
}

function roundMoney(value) {
  return Math.round(value * 100) / 100;
}

function parseWeightKg(...values) {
  const text = normalize(values.filter(Boolean).join(" "));
  const kg = text.match(/(\d+(?:\.\d+)?)\s*(kg|kilogram|kilograms|kilo|kilos)\b/);
  if (kg) return Number(kg[1]);
  const g = text.match(/(\d+(?:\.\d+)?)\s*(g|gram|grams)\b/);
  if (g) return Number(g[1]) / 1000;
  return null;
}

function weightBandFor(weightKg) {
  const normalizedWeight = Math.max(0, Number(weightKg) || 0);
  return WEIGHT_BANDS.find((band) => {
    const aboveMinimum = band.minKg === 0 ? normalizedWeight >= 0 : normalizedWeight > band.minKg;
    const belowMaximum = band.maxKg == null || normalizedWeight <= band.maxKg;
    return aboveMinimum && belowMaximum;
  }) || WEIGHT_BANDS[WEIGHT_BANDS.length - 1];
}

function estimateWeightKg(text, declaredWeightText) {
  const explicit = parseWeightKg(text, declaredWeightText);
  if (explicit != null) return explicit;
  const object = detectObject(text);
  if (object) return object.weightKg * parseQuantity(text);
  if (includesAny(text, ["iphone", "phone", "smartphone", "passport", "document", "letter"])) return 0.3;
  if (includesAny(text, ["laptop", "tablet", "camera", "console"])) return 2;
  if (includesAny(text, ["65 inch tv", "65-inch tv", "65in tv", "large tv"])) return 32;
  if (includesAny(text, ["tv", "monitor"])) return 12;
  if (includesAny(text, ["microwave", "printer", "toolbox"])) return 15;
  if (includesAny(text, ["sofa", "wardrobe", "mattress", "washing machine", "fridge"])) return 45;
  if (includesAny(text, ["pallet", "engine", "industrial machine"])) return 75;
  if (includesAny(text, ["suitcase", "luggage", "bag"])) return 8;
  if (includesAny(text, ["food", "groceries", "meal", "cake"])) return 3;
  return 2;
}

function classifyCategory(text) {
  const object = detectObject(text);
  if (object) return object.category;
  if (includesAny(text, ["passport", "contract", "document", "letter", "paperwork", "certificate"])) return "Documents";
  if (includesAny(text, ["iphone", "phone", "laptop", "tablet", "tv", "television", "monitor", "camera", "console", "electronics"])) return "Electronics";
  if (includesAny(text, ["clothes", "dress", "shoes", "fashion", "jacket", "shirt"])) return "Clothing & Fashion";
  if (includesAny(text, ["suitcase", "luggage", "keys", "wallet", "personal"])) return "Personal Items & Luggage";
  if (includesAny(text, ["food", "groceries", "meal", "cake", "drink", "consumable"])) return "Food & Consumables";
  if (includesAny(text, ["sofa", "chair", "table", "wardrobe", "mattress", "furniture", "fridge", "washing machine"])) return "Furniture & Home";
  if (includesAny(text, ["tool", "drill", "machinery", "machine", "engine"])) return "Tools & Machinery";
  if (includesAny(text, ["prescription", "medicine", "medication", "pharmacy", "medical"])) return "Medical & Pharmacy";
  if (includesAny(text, ["stock", "invoice", "business", "commercial", "office equipment"])) return "Business & Commercial";
  if (includesAny(text, ["jewellery", "jewelry", "artwork", "antique", "glass", "fragile", "valuable"])) return "Fragile & Valuable";
  return "Other";
}

function handlingFlagsFor(text, category, weightKg) {
  const object = detectObject(text);
  if (object) return object.handlingFlags;
  const flags = new Set();
  if (category === "Electronics" || category === "Fragile & Valuable" || includesAny(text, ["glass", "mirror", "ceramic", "tv", "monitor", "fragile"])) flags.add("Fragile");
  if (category === "Food & Consumables" || includesAny(text, ["food", "meal", "cake", "groceries"])) flags.add("Perishable");
  if (includesAny(text, ["upright", "keep upright", "tv", "fridge"])) flags.add("Keep Upright");
  if (category === "Fragile & Valuable" || includesAny(text, ["iphone", "laptop", "jewellery", "jewelry", "valuable", "expensive"])) flags.add("High Value");
  if (includesAny(text, ["cold", "frozen", "temperature", "medicine", "insulin"])) flags.add("Temperature Sensitive");
  if (weightKg > 10 || includesAny(text, ["large", "65 inch", "65-inch", "sofa", "wardrobe", "mattress", "pallet"])) flags.add("Bulky");
  if (includesAny(text, ["awkward", "odd shape", "long", "ladder"])) flags.add("Awkward Shape");
  if (weightKg > 25 || flags.has("Bulky") || includesAny(text, ["van", "sofa", "wardrobe", "mattress", "65 inch", "65-inch"])) flags.add("Van Required");
  if (weightKg > 25 || includesAny(text, ["two person", "2 person", "sofa", "wardrobe", "65 inch", "65-inch"])) flags.add("Two Person Lift");
  return Array.from(flags);
}

function complianceFor(text) {
  if (includesAny(text, ["illegal drugs", "cocaine", "heroin", "weapon", "gun", "firearm", "knife", "explosive", "bomb", "hazardous chemical", "hazmat", "hazardous materials"])) {
    return {status: "prohibited", reasonCodes: ["prohibited_item"], referralType: null, customerMessage: "This item cannot be carried by Circum."};
  }
  if (includesAny(text, ["live animal", "livestock", "pet transport", "dog transport", "cat transport", "funeral", "deceased", "body transport", "car transport", "vehicle transport", "motorbike transport", "industrial machinery", "specialist freight", "piano", "pianos"]) ||
    /\b(dog|cat)\b/.test(text) && !includesAny(text, ["dog food", "cat food", "dog lead", "cat lead", "dog collar", "cat collar", "dog toy", "cat toy"])) {
    let referralType = "specialist_freight";
    if (includesAny(text, ["pet", "dog", "cat", "live animal", "livestock"])) referralType = "pet_transport";
    if (includesAny(text, ["funeral", "deceased", "body transport"])) referralType = "funeral_transport";
    if (includesAny(text, ["car transport", "vehicle transport", "motorbike transport"])) referralType = "vehicle_transport";
    return {status: "referral_required", reasonCodes: ["specialist_transport_required"], referralType, customerMessage: "This request needs a specialist referral rather than normal rider dispatch."};
  }
  return {status: "allowed", reasonCodes: [], referralType: null, customerMessage: null};
}

function internalContextFor(text, category, weightKg) {
  if (includesAny(text, ["industrial", "factory", "pallet", "machinery", "engine"]) || weightKg > 50) return "industrial";
  if (category === "Business & Commercial" || includesAny(text, ["commercial", "office", "stock", "business"])) return "commercial";
  return "domestic";
}

function calculatePrice({distanceMiles = 0, weightKg = 0, handlingFlags = [], express = false, vehicleType = null}) {
  const weightBand = weightBandFor(weightKg);
  const miles = Number(distanceMiles) || 0;
  const billableMiles = miles < PRICING.shortTripFareFloorMiles ? 0 : Math.max(0, miles - PRICING.includedBaseMiles);
  const distanceMultiplier = miles > PRICING.longDistanceThresholdMiles ? PRICING.longDistanceMileageMultiplier : 1;
  const distanceFare = billableMiles * PRICING.additionalFarePerMileGbp * distanceMultiplier;
  const flags = new Set(handlingFlags);
  let logisticsModifiers = 0;
  if (flags.has("Fragile")) logisticsModifiers += PRICING.modifiers.fragile;
  if (flags.has("Perishable")) logisticsModifiers += PRICING.modifiers.perishable;
  if (flags.has("Keep Upright")) logisticsModifiers += PRICING.modifiers.keepUpright;
  if (flags.has("High Value")) logisticsModifiers += PRICING.modifiers.highValue;
  if (flags.has("Temperature Sensitive")) logisticsModifiers += PRICING.modifiers.temperatureSensitive;
  if (flags.has("Bulky")) logisticsModifiers += PRICING.modifiers.bulky;
  if (flags.has("Awkward Shape")) logisticsModifiers += PRICING.modifiers.awkwardShape;
  if (flags.has("Van Required")) logisticsModifiers += PRICING.modifiers.vanRequired;
  if (flags.has("Two Person Lift")) logisticsModifiers += PRICING.modifiers.twoPersonLift;
  if (express) logisticsModifiers += PRICING.modifiers.express;
  const vehicleSurcharge = normalize(vehicleType).includes("van") ? 10 : 0;
  const total = roundMoney(PRICING.baseFareGbp + distanceFare + weightBand.baseGbp + logisticsModifiers + vehicleSurcharge);
  return {
    baseFare: PRICING.baseFareGbp,
    distanceFare: roundMoney(distanceFare),
    weightSurcharge: weightBand.baseGbp,
    vehicleSurcharge,
    specialConditions: logisticsModifiers,
    surgeMultiplier: 1,
    total,
    weightCategory: weightBand.label,
  };
}

function serviceabilityFor({complianceStatus, weightKg, handlingFlags}) {
  if (complianceStatus !== "allowed") {
    return {status: "manual_review", reasonCodes: ["not_allowed_for_dispatch"], customerMessage: "This request needs review before dispatch."};
  }
  if (weightKg > 50) {
    return {
      status: "serviceable",
      reasonCodes: ["heavy_duty_verification_required"],
      verificationRequired: true,
      customerMessage: null,
    };
  }
  return {status: "serviceable", reasonCodes: [], customerMessage: null};
}

function matchingRequirementsFor({handlingFlags, weightKg, express}) {
  const requiresVan = handlingFlags.includes("Van Required") || weightKg > 25;
  return {
    vehicleRequired: requiresVan ? "van" : "any",
    requiresVerifiedRider: true,
    requiresTwoPerson: handlingFlags.includes("Two Person Lift"),
    priority: express ? "express" : "standard",
  };
}

function customerSafeIris(iris) {
  const recommendation = iris.recommendation || {};
  return {
    version: iris.version || "v1",
    recommendation: {
      category: recommendation.category || null,
      weightBand: recommendation.weightBand || null,
      confidencePercent: recommendation.confidencePercent || null,
      customerSafeExplanation: customerSafeExplanation(iris),
    },
  };
}

function privateIris(iris) {
  return {
    version: iris.version || "v1",
    requestId: iris.requestId || null,
    internal: iris.internal || {},
    verification: iris.verification || {rider: null, adjudication: null},
    learningSnapshot: iris.learningSnapshot || null,
  };
}

function customerSafeExplanation(iris) {
  const recommendation = iris.recommendation || {};
  const band = recommendation.weightBand && recommendation.weightBand.label;
  return `${recommendation.category || "Item"} classified as ${band || "a delivery band"} based on item type, likely size, and handling needs.`;
}

function similarLearningMatches(description, completedExamples = []) {
  const text = normalize(description);
  if (!text) return [];
  const tokens = new Set(text.split(" ").filter((token) => token.length >= 4));
  return completedExamples.filter((example) => {
    const snapshot = example.iris && example.iris.learningSnapshot ? example.iris.learningSnapshot : example.learningSnapshot;
    if (!snapshot || !snapshot.finalOutcome) return false;
    const source = normalize([
      snapshot.customerDeclaration && snapshot.customerDeclaration.description,
      snapshot.originalRecommendation && snapshot.originalRecommendation.detectedItem,
    ].filter(Boolean).join(" "));
    if (!source) return false;
    let overlap = 0;
    tokens.forEach((token) => {
      if (source.includes(token)) overlap += 1;
    });
    return overlap >= Math.min(2, Math.max(1, tokens.size));
  });
}

function applyLearningMemory(recommendation, description, completedExamples) {
  const matches = similarLearningMatches(description, completedExamples);
  if (matches.length < 2) return {...recommendation, learningMatchedExamples: matches.length};
  const counts = new Map();
  for (const match of matches) {
    const snapshot = match.iris && match.iris.learningSnapshot ? match.iris.learningSnapshot : match.learningSnapshot;
    const outcome = snapshot.finalOutcome || {};
    const key = `${outcome.finalCategory || ""}|${outcome.finalWeightBand || ""}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const [bestKey, bestCount] = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])[0] || [];
  if (!bestKey || bestCount < 2) return {...recommendation, learningMatchedExamples: matches.length};
  const [category, weightBandLabel] = bestKey.split("|");
  const band = WEIGHT_BANDS.find((item) => item.label === weightBandLabel);
  return {
    ...recommendation,
    category: category || recommendation.category,
    weightBand: band || recommendation.weightBand,
    confidencePercent: Math.min(98, recommendation.confidencePercent + 6),
    learningMatchedExamples: matches.length,
  };
}

function classifyIris(input = {}) {
  const description = `${input.description || input.packageDescription || ""}`;
  const text = normalize(description);
  const declaredWeightText = input.declaredWeightText || input.weight || "";
  const speed = `${input.speed || ""}`;
  const express = normalize(speed) === "express" || input.express === true || input.urgent === true;
  const compliance = complianceFor(text);
  const estimatedWeightKg = estimateWeightKg(text, declaredWeightText);
  const baseCategory = classifyCategory(text);
  const baseWeightBand = weightBandFor(estimatedWeightKg);
  const handlingFlags = handlingFlagsFor(text, baseCategory, estimatedWeightKg);
  const internalContext = internalContextFor(text, baseCategory, estimatedWeightKg);
  const price = calculatePrice({
    distanceMiles: input.distanceMiles || 0,
    weightKg: estimatedWeightKg,
    handlingFlags,
    express,
    vehicleType: handlingFlags.includes("Van Required") ? "van" : input.vehicleType,
  });
  const baseRecommendation = {
    detectedItem: description.trim() || baseCategory,
    category: baseCategory,
    weightBand: baseWeightBand,
    estimatedWeightKg,
    handlingFlags,
    estimatedPrice: price.total,
    confidencePercent: text ? 82 : 55,
  };
  const recommendation = compliance.status === "allowed" ?
    applyLearningMemory(baseRecommendation, description, input.completedExamples || []) :
    baseRecommendation;
  const serviceability = serviceabilityFor({
    complianceStatus: compliance.status,
    weightKg: recommendation.estimatedWeightKg,
    handlingFlags: recommendation.handlingFlags,
  });
  const matching = matchingRequirementsFor({
    handlingFlags: recommendation.handlingFlags,
    weightKg: recommendation.estimatedWeightKg,
    express,
  });
  const iris = {
    version: "v1",
    status: compliance.status,
    customerDeclaration: {
      description: description.trim(),
      declaredWeightText: `${declaredWeightText || ""}`.trim() || null,
      declaredCategory: input.declaredCategory || null,
      confidence: "low",
    },
    recommendation,
    internal: {
      context: internalContext,
      riskScore: compliance.status === "prohibited" ? 0.95 : compliance.status === "unsupported" ? 0.55 : 0.12,
      logisticsScore: recommendation.handlingFlags.length / HANDLING_FLAGS.length,
      pricingModifiers: price,
      riderMatching: matching,
      learningMatchedExamples: recommendation.learningMatchedExamples || 0,
    },
    compliance: {
      status: compliance.status,
      reasonCodes: compliance.reasonCodes,
      customerMessage: compliance.customerMessage,
      referralType: compliance.referralType,
    },
    serviceability,
    verification: {
      rider: null,
      adjudication: null,
    },
  };
  if (input.publicOnly === true) return customerSafeIris(iris);
  return iris;
}

function createLearningSnapshot(iris, completedDelivery = {}) {
  const recommendation = iris && iris.recommendation ? iris.recommendation : {};
  const customerDeclaration = iris && iris.customerDeclaration ? iris.customerDeclaration : {};
  const riderVerification = iris && iris.verification ? iris.verification.rider : null;
  const adminAdjudication = iris && iris.verification ? iris.verification.adjudication : null;
  const finalCategory = adminAdjudication && adminAdjudication.finalCategory ? adminAdjudication.finalCategory : recommendation.category;
  const finalWeightBand = adminAdjudication && adminAdjudication.finalWeightBand ? adminAdjudication.finalWeightBand : recommendation.weightBand && recommendation.weightBand.label;
  const finalHandlingFlags = adminAdjudication && adminAdjudication.finalHandlingFlags ? adminAdjudication.finalHandlingFlags : recommendation.handlingFlags || [];
  const riderMismatchReported = riderVerification ? riderVerification.status === "mismatch" : false;
  return {
    version: "v1",
    originalRecommendation: {
      detectedItem: recommendation.detectedItem || null,
      category: recommendation.category || null,
      weightBand: recommendation.weightBand ? recommendation.weightBand.label || recommendation.weightBand : null,
      estimatedWeightKg: recommendation.estimatedWeightKg || null,
      handlingFlags: recommendation.handlingFlags || [],
      confidencePercent: recommendation.confidencePercent || null,
    },
    customerDeclaration: {
      description: customerDeclaration.description || completedDelivery.packageDescription || null,
      declaredWeightText: customerDeclaration.declaredWeightText || completedDelivery.weight || null,
      declaredCategory: customerDeclaration.declaredCategory || null,
    },
    riderVerification: riderVerification || null,
    adminAdjudication: adminAdjudication || null,
    finalOutcome: {
      finalCategory: finalCategory || null,
      finalWeightBand: finalWeightBand || null,
      finalHandlingFlags,
      finalPrice: completedDelivery.price || completedDelivery.quote || recommendation.estimatedPrice || null,
      completedAt: completedDelivery.completedAt || completedDelivery.updatedAt || Date.now(),
    },
    learningSignals: {
      irisMatchedRider: riderVerification ? riderVerification.status === "matches" : null,
      irisMatchedAdminFinal: adminAdjudication ? (
        (!adminAdjudication.finalCategory || adminAdjudication.finalCategory === recommendation.category) &&
        (!adminAdjudication.finalWeightBand || adminAdjudication.finalWeightBand === (recommendation.weightBand && recommendation.weightBand.label))
      ) : null,
      customerUnderDeclared: inferCustomerUnderDeclared(customerDeclaration.declaredWeightText, recommendation.estimatedWeightKg),
      riderMismatchReported,
      requiresFutureRuleReview: riderMismatchReported || Boolean(adminAdjudication && ["corrected", "unsupported", "prohibited"].includes(adminAdjudication.decision)),
    },
  };
}

function inferCustomerUnderDeclared(declaredWeightText, estimatedWeightKg) {
  const declared = parseWeightKg(declaredWeightText || "");
  if (declared == null || estimatedWeightKg == null) return null;
  return declared + 2 < estimatedWeightKg;
}

function isDispatchable(request) {
  if (["prohibited", "referral_required", "unsupported"].includes(normalize(request.status))) return false;
  if (normalize(request.matchingStatus) === "blocked") return false;
  const iris = request.iris || {};
  const compliance = iris.compliance && iris.compliance.status || iris.status || "allowed";
  const serviceability = iris.serviceability && iris.serviceability.status || "serviceable";
  return compliance === "allowed" && serviceability === "serviceable";
}

function riderMatchesIris(rider, request) {
  const iris = request.irisPrivate || request.iris || {};
  const matching = iris.internal && iris.internal.riderMatching || request.matchingRules || {};
  if (!vehicleDispatch.riderVehicleMatchesRequest(rider, request)) return false;
  if (matching.requiresTwoPerson && rider.twoPersonLift !== true && rider.twoPersonCapability !== true) return false;
  return true;
}

function dispatchPriority(request) {
  const privateIrisData = request.irisPrivate || {};
  const priority = privateIrisData.internal && privateIrisData.internal.riderMatching && privateIrisData.internal.riderMatching.priority || request.matchingRules && request.matchingRules.irisPriority;
  return priority === "express" || normalize(request.speed) === "express" ? 1 : 0;
}

const RIDER_RANKS = new Set(["agent", "sentinel", "warden", "knight", "veteran"]);

function normalizeRiderRank(value) {
  const rank = normalize(value);
  return RIDER_RANKS.has(rank) ? rank : "agent";
}

function riderCanViewDispatch(rider, request, now = Date.now()) {
  return true;
}

function riderDispatchPriority(rider, request, now = Date.now()) {
  const rank = normalizeRiderRank(rider.rank || rider.riderRank);
  const rawCreatedAt = request.createdAt || request.requestedAt || request.timestamp || request.timeStamp;
  const createdAt = rawCreatedAt && typeof rawCreatedAt.toMillis === "function" ?
    rawCreatedAt.toMillis() : new Date(rawCreatedAt).getTime();
  if (!Number.isFinite(createdAt)) return 0;
  const elapsedMinutes = Math.floor((now - createdAt) / 60000);
  const thresholds = {agent: 0, sentinel: 5, warden: 10, knight: 15, veteran: 20};
  return elapsedMinutes >= thresholds[rank] ? 1 : 0;
}

function deliveryProtocolState(delivery = {}) {
  return {
    vanguardProtocolEnabled: delivery.vanguardProtocolEnabled === true ||
      delivery.vanguardEnabled === true ||
      delivery.requiresVanguard === true ||
      Boolean(delivery.vanguardProtocol && delivery.vanguardProtocol.enabled === true),
    vanguardStatus: delivery.vanguardStatus ||
      delivery.vanguardProtocol && delivery.vanguardProtocol.status ||
      delivery.vanguardVerificationStatus ||
      "not_required",
    vanguardRequiredReason: delivery.vanguardRequiredReason ||
      delivery.vanguardProtocol && delivery.vanguardProtocol.reason ||
      "",
  };
}

module.exports = {
  CATEGORIES,
  WEIGHT_BANDS,
  HANDLING_FLAGS,
  COMPLIANCE_STATUSES,
  REFERRAL_TYPES,
  INTERNAL_CONTEXTS,
  classifyIris,
  customerSafeIris,
  privateIris,
  calculatePrice,
  weightBandFor,
  createLearningSnapshot,
  isDispatchable,
  riderMatchesIris,
  dispatchPriority,
  normalizeRiderRank,
  riderCanViewDispatch,
  riderDispatchPriority,
  deliveryProtocolState,
  normalizeVehicleClass: vehicleDispatch.normalizeVehicleClass,
  normalizeRiderVehicle: vehicleDispatch.normalizeRiderVehicle,
  pickRequiredVehicle: vehicleDispatch.pickRequiredVehicle,
  vehicleCanHandle: vehicleDispatch.vehicleCanHandle,
};
