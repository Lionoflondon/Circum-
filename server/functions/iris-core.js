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
    patterns: [/\busb cable\b/, /\bcharging cable\b/, /\bphone chargers?\b/, /\bchargers?\b/, /\bcharger cable\b/],
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
    patterns: [/\bwedding ring\b/, /\bring\b/, /\bjewellery\b/, /\bjewelry\b/, /\bluxury watches?\b/, /\bhigh[- ]value watch(?:es)?\b/],
    category: "Fragile & Valuable",
    weightKg: 0.1,
    handlingFlags: ["High Value"],
    vehicleRequired: "any",
  },
  {
    id: "safe",
    patterns: [/\bsafe\b(?!\s+packaging)/, /\bsafes\b/, /\bsecurity safe\b/],
    category: "Fragile & Valuable",
    weightKg: 40,
    handlingFlags: ["High Value", "Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "passport_documents",
    patterns: [/\bpassports?\b/, /\bdocuments?\b/, /\benvelopes?\b/, /\bletters?\b/, /\bexam papers?\b/, /\blegal files?\b/, /\bgovernment paperwork\b/, /\bconfidential documents?\b/],
    category: "Documents",
    weightKg: 0.3,
    handlingFlags: [],
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
    patterns: [/\bbicycles?\b/, /\bbikes?\b/, /\bcycles?\b/],
    category: "Personal Items & Luggage",
    weightKg: 14,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "electric_scooter",
    patterns: [/\belectric scooters?\b/, /\be[- ]?scooters?\b/],
    category: "Personal Items & Luggage",
    weightKg: 14,
    handlingFlags: ["Bulky", "Awkward Shape", "High Value"],
    vehicleRequired: "van",
  },
  {
    id: "suitcase",
    patterns: [/\bsuitcases?\b/, /\bluggage\b/, /\bbackpacks?\b/, /\bbags?\b/],
    category: "Personal Items & Luggage",
    weightKg: 8,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "tv",
    patterns: [/\b(65[- ]?inch|65in|large|massive|big screen)\s+(tv|television|telly)\b/, /\btelly\b/, /\bbig screen\b/, /\btvs?\b/, /\btelevisions?\b/],
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
    patterns: [/\biphones?\b/, /\bphones?\b/, /\bsmartphones?\b/, /\bmobile phones?\b/],
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
    id: "mobility_aid",
    patterns: [/\bwalking frames?\b/, /\bcrutches\b/, /\bwheelchairs?\b/],
    category: "Medical & Pharmacy",
    weightKg: 8,
    handlingFlags: ["Bulky", "Awkward Shape"],
    vehicleRequired: "any",
  },
  {
    id: "baby_stroller",
    patterns: [/\bbaby strollers?\b/, /\bpushchairs?\b/, /\bprams?\b/],
    category: "Personal Items & Luggage",
    weightKg: 10,
    handlingFlags: ["Bulky", "Awkward Shape"],
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
    id: "parcel",
    patterns: [/\bparcels?\b/, /\bpackages?\b/],
    category: "Other",
    weightKg: 2,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "box",
    patterns: [/\bboxes\b/],
    category: "Other",
    weightKg: 2,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "keyboard",
    patterns: [/\bkeyboards?\b/],
    category: "Electronics",
    weightKg: 0.8,
    handlingFlags: ["Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "games",
    patterns: [/\bgames?\b/, /\bvideo games?\b/],
    category: "Electronics",
    weightKg: 0.2,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "dining_chair",
    patterns: [/\bdining chairs?\b/, /\bchairs?\b/],
    category: "Furniture & Home",
    weightKg: 6,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "table",
    patterns: [/\btables?\b/],
    category: "Furniture & Home",
    weightKg: 20,
    handlingFlags: ["Bulky", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "roses",
    patterns: [/\broses?\b/],
    category: "Food & Consumables",
    weightKg: 0.08,
    handlingFlags: ["Perishable", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "bottle",
    patterns: [/\bbottles?\b/],
    category: "Food & Consumables",
    weightKg: 1,
    handlingFlags: ["Fragile", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "clothes",
    patterns: [/\bclothes\b/, /\bclothing\b/, /\bshirts?\b/, /\bjackets?\b/],
    category: "Clothing & Fashion",
    weightKg: 0.5,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "flyers_leaflets",
    patterns: [/\bflyers?\b/, /\bleaflets?\b/],
    category: "Business & Commercial",
    weightKg: 0.01,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "earrings",
    patterns: [/\bearrings?\b/],
    category: "Fragile & Valuable",
    weightKg: 0.05,
    handlingFlags: ["High Value"],
    vehicleRequired: "any",
  },
  {
    id: "skis",
    patterns: [/\bskis?\b/],
    category: "Personal Items & Luggage",
    weightKg: 5,
    handlingFlags: ["Awkward Shape", "Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "golf_clubs",
    patterns: [/\bgolf clubs?\b/],
    category: "Personal Items & Luggage",
    weightKg: 8,
    handlingFlags: ["Awkward Shape", "Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "chocolates",
    patterns: [/\bchocolates?\b/],
    category: "Food & Consumables",
    weightKg: 0.5,
    handlingFlags: ["Perishable"],
    vehicleRequired: "any",
  },
  {
    id: "drinks",
    patterns: [/\bdrinks?\b/],
    category: "Food & Consumables",
    weightKg: 1,
    handlingFlags: ["Fragile", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "food",
    patterns: [/\bfoods?\b/, /\bgroceries\b/, /\bmeals?\b/],
    category: "Food & Consumables",
    weightKg: 3,
    handlingFlags: ["Perishable"],
    vehicleRequired: "any",
  },
  {
    id: "car_battery",
    patterns: [/\bcar batter(?:y|ies)\b/],
    category: "Tools & Machinery",
    weightKg: 15,
    handlingFlags: ["Keep Upright", "Awkward Shape"],
    vehicleRequired: "any",
  },
  {
    id: "batteries",
    patterns: [/\bbatter(?:y|ies)\b/, /\bbattery pack\b/],
    category: "Electronics",
    weightKg: 0.1,
    handlingFlags: ["Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "glass_sheet",
    patterns: [/\bsheet of glass\b/, /\bglass sheet\b/],
    category: "Fragile & Valuable",
    weightKg: 8,
    handlingFlags: ["Fragile", "Awkward Shape"],
    vehicleRequired: "any",
  },
  {
    id: "mirror",
    patterns: [/\bmirrors?\b/],
    category: "Fragile & Valuable",
    weightKg: 8,
    handlingFlags: ["Fragile", "Awkward Shape", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "car_tyre",
    patterns: [/\bcar tyres?\b/, /\bcar tires?\b/, /\btyres?\b/, /\btires?\b/],
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
    patterns: [/\belectronics\b/, /\btablets?\b/, /\bcameras?\b/, /\bconsoles?\b/, /\bmonitors?\b/, /\bdisplay\b/, /\bdesktop pc\b/, /\bdesktop computer\b/, /\bprojector\b/, /\bserver rack\b/, /\bplaystation\b/, /\bxbox\b/, /\bnintendo switch\b/],
    category: "Electronics",
    weightKg: 2,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "printer",
    patterns: [/\bprinters?\b/],
    category: "Business & Commercial",
    weightKg: 15,
    handlingFlags: ["Bulky", "Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "musical_instrument",
    patterns: [/\bdrum kits?\b/, /\bcellos?\b/, /\bguitars?\b/, /\bmusical instruments?\b/],
    category: "Fragile & Valuable",
    weightKg: 8,
    handlingFlags: ["Fragile", "Awkward Shape", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "toner",
    patterns: [/\btoner\b/, /\bprinter ink\b/, /\bink cartridges?\b/],
    category: "Business & Commercial",
    weightKg: 1,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "furniture",
    patterns: [/\bfurniture\b/, /\bwardrobe\b/, /\bcabinet\b/, /\bbed\b/, /\bhouse move\b/, /\boffice move\b/, /\bstudent move\b/, /\bbedroom\b/, /\bbedroom contents\b/, /\bgarage contents\b/],
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
    id: "shoes",
    patterns: [/\bshoes?\b/, /\btrainers?\b/, /\bsneakers?\b/],
    category: "Clothing & Fashion",
    weightKg: 0.8,
    handlingFlags: [],
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
    id: "cake",
    patterns: [/\bcakes?\b/],
    category: "Food & Consumables",
    weightKg: 3,
    handlingFlags: ["Perishable", "Fragile", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "champagne",
    patterns: [/\bchampagne\b/, /\bwine\b/],
    category: "Food & Consumables",
    weightKg: 1.5,
    handlingFlags: ["Fragile", "Keep Upright"],
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
    id: "paint",
    patterns: [/\bpaint\b/, /\bpaint tins?\b/, /\bpaint cans?\b/],
    category: "Tools & Machinery",
    weightKg: 2,
    handlingFlags: ["Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "chainsaw",
    patterns: [/\bchainsaws?\b/],
    category: "Tools & Machinery",
    weightKg: 6,
    handlingFlags: ["Awkward Shape"],
    vehicleRequired: "any",
  },
  {
    id: "generator",
    patterns: [/\bgenerators?\b/],
    category: "Tools & Machinery",
    weightKg: 28,
    handlingFlags: ["Bulky", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "treadmill",
    patterns: [/\btreadmills?\b/],
    category: "Tools & Machinery",
    weightKg: 70,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "sensitive_evidence",
    patterns: [/\bsensitive evidence\b/, /\bevidence package\b/],
    category: "Documents",
    weightKg: 1,
    handlingFlags: ["High Value"],
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
    id: "graphics_card",
    patterns: [/\bgraphics cards?\b/, /\brtx\b/, /\bgpu\b/],
    category: "Electronics",
    weightKg: 1.5,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "bricks",
    patterns: [/\bbricks?\b/],
    category: "Tools & Machinery",
    weightKg: 0.3,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "tiles",
    patterns: [/\btiles?\b/],
    category: "Tools & Machinery",
    weightKg: 1,
    handlingFlags: ["Fragile", "Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "construction_materials",
    patterns: [/\bconcrete\b/, /\btimber\b/, /\bconcrete mixer\b/, /\bengine blocks?\b/, /\bengines?\b/],
    category: "Tools & Machinery",
    weightKg: 75,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "tools",
    patterns: [/\btools?\b/, /\btoolbox\b/],
    category: "Tools & Machinery",
    weightKg: 15,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "artwork",
    patterns: [/\bartwork\b/, /\bpaintings?\b/, /\bframed art\b/],
    category: "Fragile & Valuable",
    weightKg: 5,
    handlingFlags: ["Fragile", "High Value", "Keep Upright"],
    vehicleRequired: "any",
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
  const normalized = normalize(`${text || ""}`.replace(/[×*]/g, " x ").replace(/"/g, " inch ").replace(/-/g, " "));
  const quantityNouns = new Set([
    "laptop",
    "laptops",
    "macbook",
    "macbooks",
    "phone",
    "phones",
    "smartphone",
    "smartphones",
    "iphone",
    "iphones",
    "dress",
    "dresses",
    "chair",
    "chairs",
    "book",
    "books",
    "monitor",
    "monitors",
    "tablet",
    "tablets",
    "camera",
    "cameras",
    "box",
    "boxes",
    "parcel",
    "parcels",
    "item",
    "items",
    "suitcase",
    "suitcases",
    "bag",
    "bags",
    "tv",
    "tvs",
    "television",
    "televisions",
    "console",
    "consoles",
    "device",
    "devices",
    "card",
    "cards",
    "brick",
    "bricks",
    "bicycle",
    "bicycles",
    "flower",
    "flowers",
    "rose",
    "roses",
    "bottle",
    "bottles",
    "earring",
    "earrings",
    "ski",
    "skis",
    "club",
    "clubs",
    "chocolate",
    "chocolates",
    "drink",
    "drinks",
    "battery",
    "batteries",
    "timber",
    "carpet",
    "glass",
    "clothes",
    "flyer",
    "flyers",
    "leaflet",
    "leaflets",
    "keyboard",
    "keyboards",
    "table",
    "tables",
    "shoe",
    "shoes",
  ]);
  const measurementUnits = new Set([
    "inch",
    "inches",
    "in",
    "cm",
    "centimetre",
    "centimetres",
    "centimeter",
    "centimeters",
    "m",
    "metre",
    "metres",
    "meter",
    "meters",
    "ml",
    "millilitre",
    "millilitres",
    "milliliter",
    "milliliters",
    "l",
    "litre",
    "litres",
    "liter",
    "liters",
    "kg",
    "kilogram",
    "kilograms",
    "kilo",
    "kilos",
    "g",
    "gram",
    "grams",
    "gb",
    "tb",
  ]);
  const tokens = normalized.split(" ")
      .map((token) => token.replace(/^\.+|\.+$/g, ""))
      .filter(Boolean);
  const findQuantityNoun = (start, end) => {
    for (let cursor = start; cursor < Math.min(tokens.length, end); cursor += 1) {
      if (Number.isInteger(Number(tokens[cursor])) && measurementUnits.has(tokens[cursor + 1] || "")) {
        cursor += 1;
        continue;
      }
      if (measurementUnits.has(tokens[cursor])) break;
      if (quantityNouns.has(tokens[cursor])) return true;
    }
    return false;
  };

  for (let index = 0; index < tokens.length; index += 1) {
    const value = Number(tokens[index]);
    if (!Number.isInteger(value) || value <= 0) continue;
    const next = tokens[index + 1] || "";
    if (measurementUnits.has(next)) continue;
    if (next === "x" && Number.isInteger(Number(tokens[index + 2])) &&
      measurementUnits.has(tokens[index + 3] || "")) {
      for (let cursor = index + 4; cursor < Math.min(tokens.length, index + 10); cursor += 1) {
        if (quantityNouns.has(tokens[cursor])) return value;
      }
      continue;
    }
    if (Number.isInteger(Number(next)) && measurementUnits.has(tokens[index + 2] || "")) {
      for (let cursor = index + 3; cursor < Math.min(tokens.length, index + 9); cursor += 1) {
        if (quantityNouns.has(tokens[cursor])) return value;
      }
      continue;
    }
    const start = next === "x" ? index + 2 : index + 1;
    if (findQuantityNoun(start, start + 8)) return value;
  }

  const specialQuantifiers = [
    {patterns: [/^a dozen\b/, /^dozen\b/], value: 12},
    {patterns: [/^half a dozen\b/, /^half dozen\b/], value: 6},
    {patterns: [/^a couple of\b/, /^couple of\b/], value: 2},
    {patterns: [/^a few\b/, /^few\b/], value: 3},
    {patterns: [/^several\b/], value: 4},
    {patterns: [/^many\b/, /^lots of\b/, /^loads of\b/], value: 10},
    {patterns: [/^hundreds of\b/], value: 200},
    {patterns: [/^thousands of\b/], value: 2000},
    {patterns: [/^pair of\b/, /^a pair of\b/], value: 2},
    {patterns: [/^set of\b/, /^a set of\b/], value: 1},
    {patterns: [/^box of\b/, /^a box of\b/], value: 1},
    {patterns: [/^crate of\b/, /^a crate of\b/], value: 1},
    {patterns: [/^pack of\b/, /^a pack of\b/], value: 1},
    {patterns: [/^bundle of\b/, /^a bundle of\b/], value: 1},
    {patterns: [/^roll of\b/, /^a roll of\b/], value: 1},
    {patterns: [/^sheet of\b/, /^a sheet of\b/], value: 1},
    {patterns: [/^stack of\b/, /^a stack of\b/], value: 1},
  ];
  for (let index = 0; index < tokens.length; index += 1) {
    const phrase = tokens.slice(index, Math.min(tokens.length, index + 5)).join(" ");
    for (const quantifier of specialQuantifiers) {
      if (quantifier.patterns.some((pattern) => pattern.test(phrase)) &&
        findQuantityNoun(index + 1, index + 9)) {
        return quantifier.value;
      }
    }
  }

  const article = tokens.findIndex((token) => token === "a" || token === "an");
  if (article >= 0 && findQuantityNoun(article + 1, article + 6)) return 1;

  const smallNumbers = {
    zero: 0,
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
    eleven: 11,
    twelve: 12,
    thirteen: 13,
    fourteen: 14,
    fifteen: 15,
    sixteen: 16,
    seventeen: 17,
    eighteen: 18,
    nineteen: 19,
  };
  const tens = {
    twenty: 20,
    thirty: 30,
    forty: 40,
    fourty: 40,
    fifty: 50,
    sixty: 60,
    seventy: 70,
    eighty: 80,
    ninety: 90,
  };
  function parseNumberWordsAt(start) {
    let total = 0;
    let current = 0;
    let consumed = 0;
    let matched = false;
    for (let cursor = start; cursor < tokens.length; cursor += 1) {
      const token = tokens[cursor];
      if (token === "and" || token === "x" || token === "of") {
        consumed += 1;
        continue;
      }
      if (smallNumbers[token] != null) {
        current += smallNumbers[token];
        consumed += 1;
        matched = true;
        continue;
      }
      if (tens[token] != null) {
        current += tens[token];
        consumed += 1;
        matched = true;
        continue;
      }
      if (token === "hundred") {
        current = Math.max(1, current) * 100;
        consumed += 1;
        matched = true;
        continue;
      }
      if (token === "thousand") {
        total += Math.max(1, current) * 1000;
        current = 0;
        consumed += 1;
        matched = true;
        continue;
      }
      break;
    }
    if (!matched) return null;
    return {value: total + current, consumed};
  }
  for (let index = 0; index < tokens.length; index += 1) {
    const parsed = parseNumberWordsAt(index);
    if (!parsed || parsed.value <= 0) continue;
    const next = tokens[index + parsed.consumed] || "";
    if (measurementUnits.has(next)) continue;
    if (findQuantityNoun(index + parsed.consumed, index + parsed.consumed + 8)) return parsed.value;
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

function splitItemClauses(rawText) {
  const normalized = `${rawText || ""}`
      .replace(/\n+/g, ",")
      .replace(/[+&]/g, ",")
      .replace(/\bcontaining\b/gi, ",")
      .replace(/\bfull of\b/gi, ",")
      .replace(/\bfilled with\b/gi, ",")
      .replace(/\bwith\b/gi, ",")
      .replace(/\b(suitcase|box|crate|bag|envelope|backpack|toolbox)\s+of\b/gi, "$1,");
  const clauses = normalized
      .split(/\s*,\s*/i)
      .map((part) => part.trim())
      .filter(Boolean);
  const expanded = [];
  for (const clause of clauses) {
    const andParts = clause.split(/\s+and\s+/i).map((part) => part.trim()).filter(Boolean);
    if (andParts.length > 1 && andParts.every((part) => detectObject(normalize(part)))) {
      expanded.push(...andParts);
    } else {
      expanded.push(clause);
    }
  }
  return expanded;
}

function hasContainerContents(rawText) {
  return /\b(suitcase|box|crate|bag|envelope|backpack|toolbox)\s+(containing|full of|filled with|with|of)\b/i.test(`${rawText || ""}`);
}

function extractShipmentItems(rawText) {
  const clauses = splitItemClauses(rawText);
  const items = [];
  const describesContainerContents = hasContainerContents(rawText);
  for (const clause of clauses) {
    const text = normalize(clause);
    if (describesContainerContents && /^(suitcase|box|crate|bag|envelope|backpack|toolbox)$/i.test(text)) continue;
    const object = detectObject(text);
    if (!object) continue;
    const quantity = parseQuantity(clause);
    items.push({
      id: object.id,
      description: clause,
      category: object.category,
      quantity,
      unitWeightKg: object.weightKg,
      totalWeightKg: Math.round(object.weightKg * quantity * 100) / 100,
      handlingFlags: object.handlingFlags,
      vehicleRequired: object.vehicleRequired,
    });
  }
  return items;
}

function summarizeShipmentItems(items = []) {
  if (!Array.isArray(items) || items.length === 0) return null;
  const combinedWeightKg = Math.round(items.reduce((sum, item) => sum + item.totalWeightKg, 0) * 100) / 100;
  const dominantItem = items.slice().sort((a, b) => {
    if (b.totalWeightKg !== a.totalWeightKg) return b.totalWeightKg - a.totalWeightKg;
    return b.handlingFlags.length - a.handlingFlags.length;
  })[0];
  const handlingFlags = Array.from(new Set(items.flatMap((item) => item.handlingFlags)));
  return {
    itemCount: items.length,
    totalQuantity: items.reduce((sum, item) => sum + item.quantity, 0),
    combinedWeightKg,
    dominantItem,
    handlingFlags,
    vehicleRequired: items.some((item) => item.vehicleRequired === "van") || combinedWeightKg > 25 ? "van" : "any",
  };
}

function estimateCombinedWeightKg(rawText) {
  const clauses = splitItemClauses(rawText);
  if (clauses.length < 2) return null;
  const items = extractShipmentItems(rawText);
  if (items.length < 1) return null;
  return summarizeShipmentItems(items).combinedWeightKg;
}

function weightBandFor(weightKg) {
  const normalizedWeight = Math.max(0, Number(weightKg) || 0);
  return WEIGHT_BANDS.find((band) => {
    const aboveMinimum = band.minKg === 0 ? normalizedWeight >= 0 : normalizedWeight > band.minKg;
    const belowMaximum = band.maxKg == null || normalizedWeight <= band.maxKg;
    return aboveMinimum && belowMaximum;
  }) || WEIGHT_BANDS[WEIGHT_BANDS.length - 1];
}

function estimateWeightKg(rawText, declaredWeightText) {
  const text = normalize(rawText);
  const explicit = parseWeightKg(rawText, declaredWeightText);
  if (explicit != null) return explicit;
  const combined = estimateCombinedWeightKg(rawText);
  if (combined != null) return combined;
  const object = detectObject(text);
  if (object) return Math.round(object.weightKg * parseQuantity(rawText) * 100) / 100;
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

function classifyCategory(text, shipmentSummary = null) {
  if (shipmentSummary && shipmentSummary.dominantItem) return shipmentSummary.dominantItem.category;
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

function handlingFlagsFor(text, category, weightKg, shipmentSummary = null) {
  const object = detectObject(text);
  const flags = new Set(shipmentSummary ? shipmentSummary.handlingFlags : object ? object.handlingFlags : []);
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
  if (includesAny(text, ["illegal drugs", "cocaine", "heroin", "weapon", "gun", "firearm", "ammunition", "ammo", "knife", "explosive", "bomb", "fireworks", "petrol", "gasoline", "hazardous chemical", "hazmat", "hazardous materials"])) {
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

function dimensionalBandFor({text, weightKg, handlingFlags, shipmentSummary}) {
  const screen = text.match(/\b(\d{2,3})\s*(inch|in)\b/);
  if (screen && Number(screen[1]) >= 65) {
    return {id: "oversized", label: "Oversized", confidence: "high", reasons: ["large_screen_size"]};
  }
  const dimension = text.match(/\b(\d+(?:\.\d+)?)\s*(cm|metre|metres|meter|meters|m)\b/);
  if (dimension) {
    const value = Number(dimension[1]);
    const unit = dimension[2];
    const cm = unit === "m" || unit.startsWith("met") ? value * 100 : value;
    if (cm >= 180) return {id: "long", label: "Long", confidence: "high", reasons: ["declared_long_measurement"]};
    if (cm >= 100) return {id: "bulky", label: "Bulky", confidence: "medium", reasons: ["declared_large_measurement"]};
  }
  if (handlingFlags.includes("Two Person Lift")) {
    return {id: "two_person_candidate", label: "Two-person lift candidate", confidence: "medium", reasons: ["two_person_handling"]};
  }
  if (handlingFlags.includes("Van Required") || handlingFlags.includes("Bulky") || weightKg > 25) {
    return {id: "bulky", label: "Bulky", confidence: "medium", reasons: ["bulky_or_heavy_item"]};
  }
  if (handlingFlags.includes("Awkward Shape")) {
    return {id: "awkward", label: "Awkward", confidence: "medium", reasons: ["awkward_shape"]};
  }
  if (shipmentSummary && shipmentSummary.itemCount >= 4) {
    return {id: "standard", label: "Standard", confidence: "medium", reasons: ["multi_item_standard_load"]};
  }
  if (weightKg <= 2) return {id: "compact", label: "Compact", confidence: "medium", reasons: ["small_weight_band"]};
  return {id: "standard", label: "Standard", confidence: "medium", reasons: ["default_standard_parcel"]};
}

function valueProtectionFor({text, category, handlingFlags, complianceStatus}) {
  if (complianceStatus !== "allowed") {
    return {level: "admin_referral_required", reasons: ["not_allowed_for_normal_dispatch"]};
  }
  if (includesAny(text, ["sensitive evidence", "confidential", "exam papers", "government paperwork"])) {
    return {level: "declared_value_review_required", reasons: ["sensitive_or_confidential_material"]};
  }
  if (handlingFlags.includes("High Value") || category === "Fragile & Valuable") {
    return {level: "enhanced_verification_recommended", reasons: ["high_value_or_fragile_item"]};
  }
  return {level: "standard_protection", reasons: ["normal_delivery_risk"]};
}

function verificationPolicyFor({text, category, handlingFlags, complianceStatus, serviceability}) {
  const reasons = [];
  const policy = {
    senderPinRequired: false,
    recipientPinRequired: false,
    verifiedRecipientRequired: false,
    identityCheckRequired: false,
    ageVerificationRequired: false,
    photoEvidenceRequired: false,
    adminReviewRequired: false,
    handoverEvidenceLevel: "standard_digital_lifecycle",
    reasons,
  };
  if (complianceStatus !== "allowed" || serviceability.status === "manual_review") {
    policy.adminReviewRequired = true;
    policy.handoverEvidenceLevel = "admin_review_before_dispatch";
    reasons.push("not_allowed_for_normal_dispatch");
    return policy;
  }
  if (category === "Documents" || includesAny(text, ["passport", "confidential", "exam papers", "sensitive evidence", "government paperwork"])) {
    policy.recipientPinRequired = true;
    policy.verifiedRecipientRequired = true;
    policy.identityCheckRequired = true;
    policy.handoverEvidenceLevel = "identity_confirmed_recipient_pin";
    reasons.push("sensitive_document_handover");
  }
  if (category === "Medical & Pharmacy" || handlingFlags.includes("Temperature Sensitive")) {
    policy.recipientPinRequired = true;
    policy.verifiedRecipientRequired = true;
    policy.photoEvidenceRequired = true;
    policy.handoverEvidenceLevel = "authorised_recipient_with_condition_evidence";
    reasons.push("medical_or_temperature_sensitive_delivery");
  }
  if (handlingFlags.includes("High Value") || category === "Fragile & Valuable") {
    policy.senderPinRequired = true;
    policy.recipientPinRequired = true;
    policy.photoEvidenceRequired = true;
    policy.handoverEvidenceLevel = "dual_pin_with_photo_evidence";
    reasons.push("high_value_or_fragile_delivery");
  }
  if (includesAny(text, ["wine", "champagne"])) {
    policy.ageVerificationRequired = true;
    policy.verifiedRecipientRequired = true;
    reasons.push("permitted_age_restricted_item");
  }
  return policy;
}

function accessIntelligenceFor(input = {}) {
  const values = [
    input.pickupPropertyType,
    input.deliveryPropertyType,
    input.pickupLocationType,
    input.deliveryLocationType,
    input.buildingType,
    input.accessNotes,
    input.parkingRestriction,
    input.londonContext,
  ].map(normalize).join(" ");
  const collectionFloor = Number(input.collectionFloor || input.pickupFloor || 0) || 0;
  const deliveryFloor = Number(input.deliveryFloor || input.dropoffFloor || 0) || 0;
  const liftUnavailable = input.liftAvailable === false || input.hasLift === false || includesAny(values, ["no lift", "stairs only"]);
  const constraints = [];
  const instructions = [];
  if (collectionFloor > 2 || deliveryFloor > 2) constraints.push("upper_floor_access");
  if (liftUnavailable && (collectionFloor > 1 || deliveryFloor > 1)) constraints.push("stairs_without_lift");
  if (includesAny(values, ["tower block", "estate", "gated"])) constraints.push("managed_or_gated_access");
  if (includesAny(values, ["hospital", "airport", "station", "stadium", "hotel", "university", "warehouse", "construction"])) constraints.push("controlled_site_access");
  if (includesAny(values, ["red route", "loading restriction", "restricted parking", "pedestrian", "market", "forecourt", "bus gate", "ltn"])) constraints.push("declared_loading_or_parking_constraint");
  if (constraints.includes("stairs_without_lift")) instructions.push("Confirm stair access and safe carry before dispatch.");
  if (constraints.includes("managed_or_gated_access")) instructions.push("Request gate, estate, concierge or block access details.");
  if (constraints.includes("controlled_site_access")) instructions.push("Confirm reception, security or loading point before arrival.");
  if (constraints.includes("declared_loading_or_parking_constraint")) instructions.push("Rider should plan lawful loading access from supplied notes.");
  const difficulty = constraints.includes("stairs_without_lift") || constraints.length >= 3 ? "high" : constraints.length ? "moderate" : "low";
  return {
    difficulty,
    constraints,
    additionalPersonRecommended: difficulty === "high",
    vehicleAccessWarning: constraints.includes("declared_loading_or_parking_constraint"),
    loadingTimeWarning: difficulty !== "low",
    riderInstructions: instructions,
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
  const shipmentItems = extractShipmentItems(description);
  const shipmentSummary = splitItemClauses(description).length >= 2 && shipmentItems.length >= 1 ?
    summarizeShipmentItems(shipmentItems) : null;
  const estimatedWeightKg = estimateWeightKg(description, declaredWeightText);
  const baseCategory = classifyCategory(text, shipmentSummary);
  const baseWeightBand = weightBandFor(estimatedWeightKg);
  const handlingFlags = handlingFlagsFor(text, baseCategory, estimatedWeightKg, shipmentSummary);
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
    detectedItems: shipmentItems.length ? shipmentItems.map((item) => ({
      id: item.id,
      description: item.description,
      category: item.category,
      quantity: item.quantity,
      estimatedWeightKg: item.totalWeightKg,
      handlingFlags: item.handlingFlags,
    })) : undefined,
    dominantItem: shipmentSummary && shipmentSummary.dominantItem ? {
      id: shipmentSummary.dominantItem.id,
      description: shipmentSummary.dominantItem.description,
      category: shipmentSummary.dominantItem.category,
      estimatedWeightKg: shipmentSummary.dominantItem.totalWeightKg,
    } : undefined,
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
  const dimensionalBand = dimensionalBandFor({
    text,
    weightKg: recommendation.estimatedWeightKg,
    handlingFlags: recommendation.handlingFlags,
    shipmentSummary,
  });
  const matching = matchingRequirementsFor({
    handlingFlags: recommendation.handlingFlags,
    weightKg: recommendation.estimatedWeightKg,
    express,
  });
  const access = accessIntelligenceFor(input);
  const verificationPolicy = verificationPolicyFor({
    text,
    category: recommendation.category,
    handlingFlags: recommendation.handlingFlags,
    complianceStatus: compliance.status,
    serviceability,
  });
  const valueProtection = valueProtectionFor({
    text,
    category: recommendation.category,
    handlingFlags: recommendation.handlingFlags,
    complianceStatus: compliance.status,
  });
  const operationalWarnings = [];
  if (access.vehicleAccessWarning) operationalWarnings.push("Declared access or loading constraints may affect rider approach.");
  if (access.loadingTimeWarning) operationalWarnings.push("Access conditions may require additional handover time.");
  if (dimensionalBand.id === "oversized" || dimensionalBand.id === "long") operationalWarnings.push("Item dimensions may constrain vehicle choice.");
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
    operationalRecommendation: {
      dimensionalBand,
      vehicleRecommendation: {
        required: matching.vehicleRequired,
        bikeSuitable: matching.vehicleRequired === "any" && !recommendation.handlingFlags.includes("Bulky"),
        motorbikeSuitable: matching.vehicleRequired === "any" && recommendation.estimatedWeightKg <= 10,
        carSuitable: matching.vehicleRequired === "any" || recommendation.estimatedWeightKg <= 25,
        vanSuitable: true,
        heavyDutySuitable: recommendation.estimatedWeightKg > 50 || recommendation.handlingFlags.includes("Two Person Lift"),
      },
      accessComplexity: access.difficulty,
      valueProtectionRecommendation: valueProtection,
      operationalWarnings,
      confidence: recommendation.confidencePercent,
    },
    internal: {
      context: internalContext,
      riskScore: compliance.status === "prohibited" ? 0.95 : compliance.status === "unsupported" ? 0.55 : 0.12,
      logisticsScore: recommendation.handlingFlags.length / HANDLING_FLAGS.length,
      pricingModifiers: price,
      riderMatching: matching,
      shipmentSummary: shipmentSummary ? {
        itemCount: shipmentSummary.itemCount,
        totalQuantity: shipmentSummary.totalQuantity,
        combinedWeightKg: shipmentSummary.combinedWeightKg,
        dominantItemId: shipmentSummary.dominantItem.id,
        vehicleRequired: shipmentSummary.vehicleRequired,
      } : null,
      accessIntelligence: access,
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
      ...verificationPolicy,
      rider: null,
      adjudication: null,
    },
    routing: {
      declaredAccessConstraints: access.constraints,
      liveRoutingRequired: access.vehicleAccessWarning || Boolean(input.requiresLiveRouting),
      authoritativeRoutingStatus: "not_consulted",
      riderInstructions: access.riderInstructions,
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
