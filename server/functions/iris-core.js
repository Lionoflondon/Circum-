/* eslint-disable max-len, require-jsdoc */
const vehicleDispatch = require("./vehicle-dispatch");
const {accountEligibilityDecision} = require("./rider-dispatch-authority");
const deliveryPolicy = require("./circum-delivery-policy.json");
const {
  WEIGHT_BANDS,
  WEIGHT_POLICY_VERSION,
  weightBandFor,
} = require("./canonical-weight-policy");
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
const TERMINAL_DELIVERY_STATUSES = new Set([
  "completed",
  "cancelled",
  "canceled",
  "expired",
  "archived",
  "failed",
  "refunded",
  "closed",
]);
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
    id: "flagship_smartphone",
    patterns: [/\bsamsung s\d{2}(?: ultra| plus| pro)?\b/, /\bgalaxy s\d{2}(?: ultra| plus| pro)?\b/, /\bpixel \d+(?: pro)?\b/],
    category: "Electronics",
    weightKg: 0.3,
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
    id: "medical_documents",
    patterns: [/\bhospital documents?\b/, /\bclinic paperwork\b/, /\bgp referrals?\b/, /\bx[- ]?rays?\b/, /\bmri scans?\b/, /\bmedical records?\b/],
    category: "Medical & Pharmacy",
    weightKg: 0.5,
    handlingFlags: ["Keep Upright"],
    vehicleRequired: "any",
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
    id: "groceries",
    patterns: [/\bbags of groceries\b/, /\bgroceries\b/],
    category: "Food & Consumables",
    weightKg: 8,
    handlingFlags: ["Perishable"],
    vehicleRequired: "any",
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
    id: "luxury_handbag",
    patterns: [/\bluxury handbags?\b/, /\bdesigner handbags?\b/],
    category: "Fragile & Valuable",
    weightKg: 1,
    handlingFlags: ["High Value"],
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
    patterns: [/\bmedication\b/, /\bmedicine\b/, /\bprescription\b/, /\bprescriptions?\b/, /\bpharmacy\b/, /\bpharmacy collections?\b/, /\binsulin\b/, /\bvaccines?\b/, /\btemperature[- ]controlled medication\b/],
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
    id: "book_bundle",
    patterns: [
      /\bbox of books\b/,
      /\bbox full of books\b/,
      /\bsuitcase containing books\b/,
      /\bsuitcase full of books\b/,
      /\bstack of books\b/,
    ],
    category: "Personal Items & Luggage",
    weightKg: 12,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "books",
    patterns: [/\bbooks?\b/],
    category: "Documents",
    weightKg: 0.6,
    handlingFlags: [],
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
    id: "office_desk",
    patterns: [/\boffice desks?\b/, /\bdesks?\b/],
    category: "Furniture & Home",
    weightKg: 30,
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
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
    id: "designer_clothing",
    patterns: [/\bdesigner clothing\b/, /\bluxury clothing\b/],
    category: "Clothing & Fashion",
    weightKg: 2,
    handlingFlags: ["High Value"],
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
    id: "glass_cabinet",
    patterns: [/\bglass cabinets?\b/, /\bdisplay cabinets?\b/, /\bglass display cabinets?\b/, /\bglass tables?\b/],
    category: "Fragile & Valuable",
    weightKg: 30,
    handlingFlags: ["Fragile", "Keep Upright", "Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
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
    patterns: [/\belectronics\b/, /\btablets?\b/, /\bcameras?\b/, /\bconsoles?\b/, /\bmonitors?\b/, /\bdisplay\b/, /\bdesktop pc\b/, /\bdesktop computer\b/, /\bprojector\b/, /\bps5\b/, /\bplaystation(?:\s+\d+)?\b/, /\bxbox(?:\s+series\s+[xs])?\b/, /\bnintendo switch(?:\s+\d+)?\b/],
    category: "Electronics",
    weightKg: 2,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "speakers",
    patterns: [/\bspeakers?\b/, /\baudio speakers?\b/],
    category: "Electronics",
    weightKg: 5,
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
    patterns: [/\bcellos?\b/, /\bguitars?\b/, /\bmusical instruments?\b/],
    category: "Fragile & Valuable",
    weightKg: 8,
    handlingFlags: ["Fragile", "Awkward Shape", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "drum_kit",
    patterns: [/\bdrum kits?\b/],
    category: "Fragile & Valuable",
    weightKg: 25,
    handlingFlags: ["Fragile", "Awkward Shape", "Bulky", "Van Required"],
    vehicleRequired: "van",
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
    id: "christmas_tree",
    patterns: [/\bchristmas trees?\b/],
    category: "Furniture & Home",
    weightKg: 10,
    handlingFlags: ["Bulky", "Keep Upright", "Van Required"],
    vehicleRequired: "van",
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
    id: "coffee_machine",
    patterns: [/\bcoffee machines?\b/, /\bespresso machines?\b/],
    category: "Furniture & Home",
    weightKg: 6,
    handlingFlags: ["Fragile"],
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
    handlingFlags: ["Bulky", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "barbell",
    patterns: [/\bbarbells?\b/, /\bbar bell\b/],
    category: "Tools & Machinery",
    weightKg: 20,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required"],
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
    patterns: [/\bblood samples?\b/, /\bpathology specimens?\b/, /\bmedical specimens?\b/, /\bmedical samples?\b/, /\bdiagnostic samples?\b/, /\burine samples?\b/, /\btissue samples?\b/, /\bswab samples?\b/, /\blab samples?\b/, /\blaboratory samples?\b/, /\bbiological specimens?\b/],
    category: "Medical & Pharmacy",
    weightKg: 0.5,
    handlingFlags: ["Temperature Sensitive", "Keep Upright"],
    vehicleRequired: "any",
  },
  {
    id: "medical_equipment",
    patterns: [/\bmedical equipment\b/, /\bdiagnostic equipment\b/],
    category: "Medical & Pharmacy",
    weightKg: 4,
    handlingFlags: ["Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "cat_litter",
    patterns: [/\bcat litter\b/],
    category: "Food & Consumables",
    weightKg: 10,
    handlingFlags: ["Bulky"],
    vehicleRequired: "any",
  },
  {
    id: "server_equipment",
    patterns: [/\bserver equipment\b/, /\bserver racks?\b/, /\bnetwork servers?\b/],
    category: "Electronics",
    weightKg: 25,
    handlingFlags: ["Fragile", "High Value", "Bulky", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "motorbike_parts",
    patterns: [/\bmotorbike parts?\b/, /\bmotorcycle parts?\b/],
    category: "Tools & Machinery",
    weightKg: 30,
    handlingFlags: ["Bulky", "Awkward Shape", "Van Required", "Two Person Lift"],
    vehicleRequired: "van",
  },
  {
    id: "aquarium",
    patterns: [/\baquariums?\b/, /\bglass aquarium\b/],
    category: "Fragile & Valuable",
    weightKg: 25,
    handlingFlags: ["Fragile", "Keep Upright", "Bulky", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "portable_ac",
    patterns: [/\bportable ac\b/, /\bportable air conditioner\b/, /\bair conditioning unit\b/],
    category: "Furniture & Home",
    weightKg: 18,
    handlingFlags: ["Bulky", "Keep Upright", "Van Required"],
    vehicleRequired: "van",
  },
  {
    id: "household_small_appliance",
    patterns: [/\bvacuum cleaners?\b/, /\bfans?\b/],
    category: "Furniture & Home",
    weightKg: 7,
    handlingFlags: [],
    vehicleRequired: "any",
  },
  {
    id: "motorbike_helmet",
    patterns: [/\bmotorbike helmets?\b/, /\bmotorcycle helmets?\b/],
    category: "Personal Items & Luggage",
    weightKg: 2,
    handlingFlags: ["Fragile"],
    vehicleRequired: "any",
  },
  {
    id: "wedding_gifts",
    patterns: [/\bwedding gifts?\b/],
    category: "Fragile & Valuable",
    weightKg: 10,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "gaming_pc",
    patterns: [/\bgaming pcs?(?: tower)?\b/, /\bpc towers?\b/, /\bcomputer towers?\b/],
    category: "Electronics",
    weightKg: 14,
    handlingFlags: ["Fragile", "High Value", "Bulky"],
    vehicleRequired: "van",
  },
  {
    id: "drone",
    patterns: [/\bdrones?\b/],
    category: "Electronics",
    weightKg: 4,
    handlingFlags: ["Fragile", "High Value"],
    vehicleRequired: "any",
  },
  {
    id: "dj_equipment",
    patterns: [/\bdj equipment\b/, /\bdj mixers?\b/, /\baudio mixers?\b/, /\bturntables?\b/],
    category: "Electronics",
    weightKg: 20,
    handlingFlags: ["Fragile", "High Value", "Bulky"],
    vehicleRequired: "van",
  },
  {
    id: "film_equipment",
    patterns: [/\bfilm equipment\b/, /\blighting rigs?\b/, /\bcamera rigs?\b/],
    category: "Electronics",
    weightKg: 18,
    handlingFlags: ["Fragile", "High Value", "Bulky"],
    vehicleRequired: "van",
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
  baseFareGbp: deliveryPolicy.pricing.baseDeliveryGbp,
  additionalFarePerMileGbp: deliveryPolicy.pricing.distancePerMileGbp,
  includedBaseMiles: deliveryPolicy.pricing.includedBaseMiles,
  shortTripFareFloorMiles: deliveryPolicy.pricing.shortTripFareFloorMiles,
  longDistanceThresholdMiles: deliveryPolicy.pricing.longDistanceThresholdMiles,
  longDistanceMileageMultiplier: deliveryPolicy.pricing.longDistanceMileageMultiplier,
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
    carVehicle: deliveryPolicy.pricing.vehicleSurchargesGbp.car,
    vanVehicle: deliveryPolicy.pricing.vehicleSurchargesGbp.van,
    express: deliveryPolicy.pricing.express.minimumSurchargeGbp,
  },
});

function normalize(value) {
  return `${value || ""}`
      .normalize("NFKC")
      .replace(/(?:[\u200b-\u200d]|\uFE0E|\uFE0F|\uFEFF)/g, "")
      .toLowerCase()
      .replace(/(\d)\.(\d)/g, "$1decimalpoint$2")
      .replace(/[._,\-/\\]+/g, " ")
      .replace(/[^a-z0-9+\s]/g, " ")
      .replace(/decimalpoint/g, ".")
      .replace(/\s+/g, " ")
      .trim();
}

function safeText(value, seen = new WeakSet(), depth = 0) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return `${value}`;
  if (typeof value !== "object") return "";
  if (seen.has(value) || depth > 3) return "";
  seen.add(value);
  if (Array.isArray(value)) {
    return value.map((item) => safeText(item, seen, depth + 1)).filter(Boolean).join(" ");
  }
  return Object.entries(value)
      .filter(([key]) => !["__proto__", "constructor", "prototype"].includes(key))
      .map(([key, item]) => `${key} ${safeText(item, seen, depth + 1)}`)
      .filter(Boolean)
      .join(" ");
}

function safetyCanonicalText(value) {
  return safeText(value).normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .normalize("NFKC")
      .replace(/\u0430/g, "a")
      .replace(/\u0435/g, "e")
      .replace(/\u0456/g, "i")
      .replace(/\u03bf/g, "o")
      .replace(/\u03c5/g, "u")
      .replace(/@/g, "a")
      .replace(/\$/g, "s")
      .replace(/0/g, "o")
      .replace(/1/g, "i")
      .replace(/3/g, "e")
      .replace(/5/g, "s")
      .replace(/7/g, "t")
      .replace(/ph/g, "f");
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
    "pc",
    "pcs",
    "generator",
    "generators",
    "printer",
    "printers",
    "sofa",
    "sofas",
    "wardrobe",
    "wardrobes",
    "mattress",
    "mattresses",
    "fridge",
    "fridges",
    "toolbox",
    "toolboxes",
    "equipment",
    "server",
    "servers",
    "unit",
    "units",
    "tree",
    "trees",
    "barbell",
    "barbells",
    "speaker",
    "speakers",
    "ac",
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
    {patterns: [/^(?:two|2) pairs? of\b/], value: 4},
    {patterns: [/^(?:three|3) pairs? of\b/], value: 6},
    {patterns: [/^(?:four|4) pairs? of\b/], value: 8},
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

function parsePerUnitWeightKg(rawText) {
  const source = normalize(rawText);
  const quantityPattern = "(\\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)";
  const weightPattern = "(\\d+(?:\\.\\d+)?)\\s*(kg|kilogram|kilograms|kilo|kilos|g|gram|grams)";
  const match = source.match(new RegExp(`\\b${quantityPattern}\\b[\\s\\w+-]{0,80}?${weightPattern}\\s*(?:each|per item|per unit|per piece)\\b`));
  if (!match) return null;
  const quantity = parseQuantityToken(match[1]);
  if (!quantity) return null;
  const value = Number(match[2]);
  if (!Number.isFinite(value) || value <= 0) return null;
  const unit = match[3];
  const kg = unit === "g" || unit === "gram" || unit === "grams" ? value / 1000 : value;
  return Math.round(quantity * kg * 100) / 100;
}

function splitItemClauses(rawText) {
  const normalized = `${rawText || ""}`
      .replace(/\n+/g, ",")
      .replace(/[+&]/g, ",")
      .replace(/\bcontaining\b/gi, ",")
      .replace(/\bfull of\b/gi, ",")
      .replace(/\bfilled with\b/gi, ",")
      .replace(/\bwith\b/gi, ",")
      .replace(/\b(suitcases?|box(?:es)?|crates?|bags?|envelopes?|backpacks?|toolbox(?:es)?)\s+of\b/gi, "$1,");
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
  return /\b(suitcases?|box(?:es)?|crates?|bags?|envelopes?|backpacks?|toolbox(?:es)?)\s+(containing|full of|filled with|with|of)\b/i.test(`${rawText || ""}`);
}

function parseQuantityToken(token) {
  const normalized = normalize(token);
  const direct = Number(normalized);
  if (Number.isInteger(direct) && direct > 0) return direct;
  const numbers = {
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
  };
  return numbers[normalized] || null;
}

function extractNestedContainerItems(rawText) {
  const source = normalize(rawText).replace(/[×*]/g, " x ");
  const nested = [];
  const pattern = /\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(?:boxes|box|crates?|bags?|packs?)\s+(?:containing|with|of|full of|filled with)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+([a-z0-9 .+-]+?)(?:\s+each\b|$)/g;
  let match = pattern.exec(source);
  while (match) {
    const containerQuantity = parseQuantityToken(match[1]);
    const itemQuantity = parseQuantityToken(match[2]);
    const itemText = match[3].replace(/\beach\b/g, "").trim();
    const object = detectObject(itemText);
    if (containerQuantity && itemQuantity && object) {
      const quantity = containerQuantity * itemQuantity;
      nested.push({
        id: object.id,
        description: `${match[2]} ${itemText} in each ${match[1]} container`,
        category: object.category,
        quantity,
        unitWeightKg: object.weightKg,
        totalWeightKg: Math.round(object.weightKg * quantity * 100) / 100,
        handlingFlags: object.handlingFlags,
        vehicleRequired: object.vehicleRequired,
      });
    }
    match = pattern.exec(source);
  }
  if (!nested.length) {
    const containerPattern = /\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(boxes|box|crates?|bags?|packs?|suitcases?|stacks?)\s+(?:containing|with|of|full of|filled with)\s+([a-z0-9 .+-]+?)(?:$|\s+(?:with|near|from|to|for|please|collection|drop|recipient)\b)/g;
    match = containerPattern.exec(source);
    while (match) {
      const containerQuantity = parseQuantityToken(match[1]);
      const container = match[2];
      const itemText = match[3].replace(/\beach\b/g, "").trim();
      const object = /\bbooks?\b/.test(itemText) && /^(boxes|box|suitcases?|stacks?)$/.test(container) ?
        detectObject("box of books") :
        detectObject(itemText);
      if (containerQuantity && object) {
        nested.push({
          id: object.id,
          description: `${containerQuantity} ${itemText}`,
          category: object.category,
          quantity: containerQuantity,
          unitWeightKg: object.weightKg,
          totalWeightKg: Math.round(object.weightKg * containerQuantity * 100) / 100,
          handlingFlags: object.handlingFlags,
          vehicleRequired: object.vehicleRequired,
        });
      }
      match = containerPattern.exec(source);
    }
  }
  return nested;
}

function extractShipmentItems(rawText) {
  const nestedItems = extractNestedContainerItems(rawText);
  if (nestedItems.length) return nestedItems;
  const source = normalize(rawText);
  if (/\b(box|boxes|suitcase|suitcases|stack|stacks)\b.*\bbooks\b/.test(source)) {
    const object = detectObject("box of books");
    const bundleQuantity = source.match(/\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(?:boxes|box|suitcases?|stacks?)\s+(?:of|full of|containing|with)\s+books\b/);
    const quantity = bundleQuantity ? parseQuantityToken(bundleQuantity[1]) || 1 : parseQuantity(rawText);
    return [{
      id: object.id,
      description: rawText,
      category: object.category,
      quantity,
      unitWeightKg: object.weightKg,
      totalWeightKg: Math.round(object.weightKg * quantity * 100) / 100,
      handlingFlags: object.handlingFlags,
      vehicleRequired: object.vehicleRequired,
    }];
  }
  const clauses = splitItemClauses(rawText);
  const items = [];
  const describesContainerContents = hasContainerContents(rawText);
  for (const clause of clauses) {
    const text = normalize(clause);
    if (describesContainerContents &&
        /^(?:(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+)?(?:suitcases?|box(?:es)?|crates?|bags?|envelopes?|backpacks?|toolbox(?:es)?)$/i.test(text)) {
      continue;
    }
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
    vehicleRequired: items.some((item) => item.vehicleRequired === "van") || combinedWeightKg >= 40 ? "van" : "any",
  };
}

function estimateCombinedWeightKg(rawText) {
  const clauses = splitItemClauses(rawText);
  if (clauses.length < 2) return null;
  const items = extractShipmentItems(rawText);
  if (items.length < 1) return null;
  return summarizeShipmentItems(items).combinedWeightKg;
}

function estimateIrisWeightKg(rawText, normalizedText = normalize(rawText)) {
  const combined = estimateCombinedWeightKg(rawText);
  if (combined != null) return combined;
  const object = detectObject(normalizedText);
  if (object) return Math.round(object.weightKg * parseQuantity(rawText) * 100) / 100;
  if (includesAny(normalizedText, ["iphone", "phone", "smartphone", "passport", "document", "letter"])) return 0.3;
  if (includesAny(normalizedText, ["laptop", "tablet", "camera", "console"])) return 2;
  if (includesAny(normalizedText, ["65 inch tv", "65-inch tv", "65in tv", "large tv"])) return 32;
  if (includesAny(normalizedText, ["tv", "monitor"])) return 12;
  if (includesAny(normalizedText, ["microwave", "printer", "toolbox"])) return 15;
  if (includesAny(normalizedText, ["sofa", "wardrobe", "mattress", "washing machine", "fridge"])) return 45;
  if (includesAny(normalizedText, ["pallet", "engine", "industrial machine"])) return 75;
  if (includesAny(normalizedText, ["suitcase", "luggage", "bag"])) return 8;
  if (includesAny(normalizedText, ["food", "groceries", "meal", "cake"])) return 3;
  return 2;
}

function resolveAuthoritativeShipmentWeight({rawText, declaredWeightText, shipmentSummary, shipmentItems, photoEstimatedWeightKg = null}) {
  const declaredWeightKg = parseWeightKg(rawText, declaredWeightText);
  const explicitPerUnitWeightKg = parsePerUnitWeightKg(rawText);
  const itemWeightKg = Array.isArray(shipmentItems) && shipmentItems.length ?
    Math.round(shipmentItems.reduce((sum, item) => sum + item.totalWeightKg, 0) * 100) / 100 :
    null;
  const parsedQuantity = parseQuantity(rawText);
  const perUnitDeclaredWeightKg = declaredWeightKg != null && parsedQuantity > 1 &&
    /\b(each|per item|per unit|per piece)\b/.test(normalize(rawText)) ?
    Math.round(declaredWeightKg * parsedQuantity * 100) / 100 :
    null;
  const fallbackIrisWeightKg = estimateIrisWeightKg(rawText);
  const irisEstimatedWeightKg = itemWeightKg != null ? itemWeightKg : fallbackIrisWeightKg;
  const candidates = [
    {source: "iris_estimate", value: irisEstimatedWeightKg, confidence: itemWeightKg != null ? "high" : "medium"},
  ];
  if (shipmentSummary && Number.isFinite(shipmentSummary.combinedWeightKg)) {
    candidates.push({source: "combined_items", value: shipmentSummary.combinedWeightKg, confidence: "high"});
  }
  if (declaredWeightKg != null && declaredWeightKg >= 0) {
    candidates.push({source: "declared_weight", value: declaredWeightKg, confidence: "sender_declared"});
  }
  if (perUnitDeclaredWeightKg != null && perUnitDeclaredWeightKg >= 0) {
    candidates.push({source: "declared_per_unit_weight", value: perUnitDeclaredWeightKg, confidence: "sender_declared_per_unit"});
  }
  if (explicitPerUnitWeightKg != null && explicitPerUnitWeightKg >= 0) {
    candidates.push({source: "explicit_per_unit_weight", value: explicitPerUnitWeightKg, confidence: "sender_declared_per_unit"});
  }
  const visualWeightKg = Number(photoEstimatedWeightKg);
  if (Number.isFinite(visualWeightKg) && visualWeightKg > 0) {
    candidates.push({source: "backend_photo_estimate", value: visualWeightKg, confidence: "backend_photo_signal"});
  }
  const best = candidates
      .filter((candidate) => Number.isFinite(candidate.value) && candidate.value >= 0)
      .sort((a, b) => b.value - a.value)[0] || {source: "iris_estimate", value: 2, confidence: "low"};
  const lowerDeclaration = declaredWeightKg != null && declaredWeightKg < irisEstimatedWeightKg;
  const higherDeclaration = declaredWeightKg != null && declaredWeightKg > irisEstimatedWeightKg;
  return {
    declaredWeightKg,
    irisEstimatedWeightKg,
    combinedWeightKg: shipmentSummary ? shipmentSummary.combinedWeightKg : itemWeightKg,
    photoEstimatedWeightKg: Number.isFinite(visualWeightKg) && visualWeightKg > 0 ? Math.round(visualWeightKg * 100) / 100 : null,
    authoritativeWeightKg: Math.round(best.value * 100) / 100,
    authoritySource: best.source,
    confidence: best.confidence,
    overrideReason: lowerDeclaration ? "declared_weight_below_iris_estimate" :
      higherDeclaration ? "declared_weight_above_iris_estimate" : "declared_and_iris_aligned",
  };
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
  if (includesAny(text, ["prescription", "medicine", "medication", "pharmacy", "medical", "pathology", "diagnostic sample", "urine sample", "tissue sample", "swab sample", "hospital", "clinic", "gp referral", "x-ray", "xray", "mri"])) return "Medical & Pharmacy";
  if (includesAny(text, ["stock", "invoice", "business", "commercial", "office equipment"])) return "Business & Commercial";
  if (includesAny(text, ["jewellery", "jewelry", "artwork", "antique", "glass", "fragile", "valuable"])) return "Fragile & Valuable";
  return "Other";
}

function handlingFlagsFor(text, category, weightKg, shipmentSummary = null) {
  const object = detectObject(text);
  const flags = new Set(shipmentSummary ? shipmentSummary.handlingFlags : object ? object.handlingFlags : []);
  const compactPrinterLoad = includesAny(text, ["printer"]) &&
    weightKg < deliveryPolicy.vehiclePolicy.carSuitableMaxExclusiveKg;
  if (category === "Electronics" || category === "Fragile & Valuable" || includesAny(text, ["glass", "mirror", "ceramic", "tv", "monitor", "fragile"])) flags.add("Fragile");
  if (category === "Food & Consumables" || includesAny(text, ["food", "meal", "cake", "groceries"])) flags.add("Perishable");
  if (includesAny(text, ["upright", "keep upright", "tv", "fridge", "glass cabinet", "display cabinet", "glass table"])) flags.add("Keep Upright");
  if (category === "Fragile & Valuable" || includesAny(text, ["iphone", "laptop", "jewellery", "jewelry", "watch", "valuable", "expensive", "designer", "luxury"])) flags.add("High Value");
  if (includesAny(text, ["cold", "frozen", "temperature", "medicine", "insulin", "vaccine", "blood sample", "pathology", "diagnostic sample", "urine sample", "tissue sample", "swab sample", "specimen"])) flags.add("Temperature Sensitive");
  if (weightKg > 10 || includesAny(text, ["large", "65 inch", "65-inch", "sofa", "wardrobe", "mattress", "pallet"])) flags.add("Bulky");
  if (includesAny(text, ["awkward", "odd shape", "long", "ladder"])) flags.add("Awkward Shape");
  if (weightKg >= deliveryPolicy.vehiclePolicy.vanRequiredMinKg ||
      !compactPrinterLoad && flags.has("Bulky") ||
      includesAny(text, ["van", "sofa", "wardrobe", "mattress", "65 inch", "65-inch"])) flags.add("Van Required");
  if (weightKg >= deliveryPolicy.vehiclePolicy.vanRequiredMinKg || includesAny(text, ["two person", "2 person", "sofa", "wardrobe", "65 inch", "65-inch"])) flags.add("Two Person Lift");
  return Array.from(flags);
}

function multilingualProhibitedMatch(rawText) {
  const source = safetyCanonicalText(rawText).toLowerCase();
  const compact = source.replace(/[\s\u200b-\u200d\uFEFF._-]+/g, "");
  const highRiskPatterns = [
    /炸药|爆炸物|爆竹|枪|枪支|弹药|汽油|毒品/,
    /سلاح|مسدس|ذخيرة|متفجرات|بنزين|مخدرات|ألعابنارية|العابنارية/,
    /arme\s*(?:à|a)\s*feu|munitions?|explosifs?|feux\s*d[’']?artifice|essence|drogues?\s*ill[eé]gales?/,
    /arma\s*de\s*fuego|munici[oó]n|explosiv[oa]s?|fuegos\s*artificiales|gasolina|drogas?\s*ilegales?/,
    /bro[nń]|amunicj[aeę]|materia[łl]ywybuchowe|fajerwerki|benzyn[aeę]|narkotyki/,
  ];
  return highRiskPatterns.some((pattern) => pattern.test(source) || pattern.test(compact));
}

function compactEmojiText(rawText) {
  return safeText(rawText).normalize("NFKC")
      .replace(/\s/g, "")
      .replace(/\u200b/g, "")
      .replace(/\u200c/g, "")
      .replace(/\u200d/g, "")
      .replace(/\uFE0E/g, "")
      .replace(/\uFE0F/g, "")
      .replace(/\uFEFF/g, "");
}

function containsDangerousEmoji(rawText) {
  const compact = compactEmojiText(rawText);
  return ["💣", "🔫", "🧨", "☢", "☣", "🔪"]
      .some((symbol) => compact.includes(symbol));
}

function containsLiveAnimalEmoji(rawText) {
  const compact = compactEmojiText(rawText);
  return ["🐶", "🐕", "🐩", "🐈", "🐱", "🐍", "🐐", "🐟", "🐠", "🐛", "🐜", "🪲"]
      .some((symbol) => compact.includes(symbol));
}

function safetyScanFor(rawText) {
  const source = safetyCanonicalText(rawText)
      .replace(/\u200b|\u200c|\u200d|\uFE0E|\uFE0F|\uFEFF/g, "")
      .toLowerCase();
  const spaced = source
      .replace(/[._,\-/\\]+/g, " ")
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  const compact = source.replace(/[^a-z0-9]/g, "");
  return {spaced, compact};
}

function spacedLetterPattern(term) {
  return new RegExp(`(?:^|\\b)${term.split("").join("[\\s._,\\-/\\\\\\u200b-\\u200d\\uFEFF]*")}(?:\\b|$)`);
}

function hasSafetyTerm(scan, terms) {
  return terms.some((term) => {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (new RegExp(`\\b${escaped}\\b`).test(scan.spaced)) return true;
    if (term.length >= 3 && spacedLetterPattern(term).test(scan.spaced)) return true;
    const compactTerm = term.replace(/[^a-z0-9]/g, "");
    if (compactTerm.length >= 4 && scan.compact.includes(compactTerm)) return true;
    return false;
  });
}

function hasSafetyPhrase(scan, phrases) {
  return phrases.some((phrase) => {
    if (scan.spaced.includes(phrase)) return true;
    const compactPhrase = phrase.replace(/[^a-z0-9]/g, "");
    return compactPhrase.length >= 4 && scan.compact.includes(compactPhrase);
  });
}

function hasHighRiskObfuscatedProhibitedPhrase(scan) {
  const compact = scan.compact;
  const spaced = scan.spaced;
  const compactPatterns = [
    /illegal(?:drug|drugs)/,
    /controlled(?:drug|drugs)/,
    /compressedgas/,
    /haz(?:a)?rdous(?:chemical|chemicals|material|materials|chem|khem|khemcal|khemcals|kemical|kemicals)/,
    /(?:radioactive|radioactve|radiactive|rdioactive|rdioactve)(?:material|materials)/,
  ];
  const spacedPatterns = [
    /\bhaz(?:a)?rdous\b.*\b(?:chem|khem|chemical|chemicals|material|materials)\b/,
    /\b(?:radioactive|radioactve|radiactive|rdioactive|rdioactve)\b.*\bmaterials?\b/,
  ];
  return compactPatterns.some((pattern) => pattern.test(compact)) ||
    spacedPatterns.some((pattern) => pattern.test(spaced));
}

function lowInformationDescription(rawText, normalizedText = normalize(rawText)) {
  if (/[🎁📦]/u.test(`${rawText || ""}`)) return false;
  const itemText = normalizedText
      .replace(/\b(?:ignore restrictions|customer insists allowed|not dangerous|just|sum|mark allowed|no questions)\b/g, " ")
      .replace(/\b(?:pickup|dropoff|collection|delivery)\b/g, " ")
      .replace(/\b[a-z]{1,2}\d[a-z\d]?\s*\d[a-z]{2}\b/g, " ")
      .replace(/\b[a-z]{1,2}\d[a-z\d]?\b/g, " ")
      .replace(/\b\d[a-z]{2}\b/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  const words = itemText.split(/\s+/).filter(Boolean);
  const compact = itemText.replace(/[^a-z0-9]/g, "");
  const vagueTerms = new Set([
    "item",
    "items",
    "parcel",
    "parcels",
    "package",
    "packages",
    "thing",
    "things",
    "stuff",
    "goods",
    "delivery",
    "box",
    "boxes",
    "private",
    "contents",
    "misc",
    "miscellaneous",
    "normal",
    "courier",
    "small",
    "safe",
    "important",
    "urgent",
    "pls",
    "please",
    "during",
    "heavy",
    "rain",
    "weather",
    "caller",
    "says",
    "it",
    "is",
    "fragile",
    "stairs",
    "lift",
    "access",
    "no",
    "allowed",
    "fine",
    "customer",
    "insists",
    "gift",
  ]);
  if (!compact) return true;
  if (compact.length < 3) return true;
  if (words.length <= 2 && words.every((word) => vagueTerms.has(word))) return true;
  const informative = words.filter((word) => word.length >= 3 && !vagueTerms.has(word));
  return informative.length === 0;
}

function complianceFor(text, rawText = text) {
  const safetyScan = safetyScanFor(rawText);
  const prohibitedTerms = [
    "gun",
    "rifle",
    "pistol",
    "firearm",
    "shotgun",
    "grenade",
    "bullet",
    "bullets",
    "ammunition",
    "ammo",
    "taser",
    "knife",
    "switchblade",
    "sword",
    "machete",
    "weapon",
    "explosive",
    "explosives",
    "bomb",
    "bomba",
    "pistola",
    "gnub",
    "fireworks",
    "petrol",
    "gasoline",
    "cash",
    "cocaine",
    "heroin",
    "poison",
    "detonator",
    "dynamite",
    "biohazard",
  ];
  const prohibitedPhrases = [
    "illegal drugs",
    "controlled drugs",
    "hazardous chemical",
    "hazardous chemicals",
    "hazardous material",
    "hazardous materials",
    "hazmat",
    "toxic chemical",
    "radioactive material",
    "corrosive acid",
    "compressed gas",
    "large cash",
    "cash delivery",
  ];
  const specialistTerms = [
    "snake",
    "goat",
    "insect",
    "insects",
    "livestock",
    "perro",
    "piano",
    "pianos",
  ];
  const specialistPhrases = [
    "live animal",
    "live animals",
    "live fish",
    "pet transport",
    "dog transport",
    "cat transport",
    "animal transport",
    "veterinary transport",
    "human remains",
    "body transport",
    "funeral",
    "deceased",
    "car transport",
    "vehicle transport",
    "motorbike transport",
    "industrial machinery",
    "specialist freight",
  ];
  if (containsDangerousEmoji(rawText)) {
    return {status: "prohibited", reasonCodes: ["dangerous_symbol"], referralType: null, customerMessage: "This item cannot be carried by Circum."};
  }
  if (hasSafetyTerm(safetyScan, prohibitedTerms) || hasSafetyPhrase(safetyScan, prohibitedPhrases) || hasHighRiskObfuscatedProhibitedPhrase(safetyScan)) {
    return {status: "prohibited", reasonCodes: ["prohibited_item"], referralType: null, customerMessage: "This item cannot be carried by Circum."};
  }
  if (multilingualProhibitedMatch(rawText)) {
    return {status: "prohibited", reasonCodes: ["multilingual_prohibited_item"], referralType: null, customerMessage: "This item cannot be carried by Circum."};
  }
  if (containsLiveAnimalEmoji(rawText) && !includesAny(text, ["dog food", "cat food", "pet food", "food", "lead", "collar", "toy"])) {
    return {status: "referral_required", reasonCodes: ["specialist_transport_required"], referralType: "pet_transport", customerMessage: "This request needs a specialist referral rather than normal rider dispatch."};
  }
  const petTermDetected = hasSafetyTerm(safetyScan, ["dog", "cat", "puppy", "puppies", "kitten", "kittens"]);
  if (hasSafetyTerm(safetyScan, specialistTerms) || hasSafetyPhrase(safetyScan, specialistPhrases) ||
    includesAny(text, ["live animal", "livestock", "pet transport", "dog transport", "cat transport", "animal transport", "veterinary transport", "funeral", "deceased", "body transport", "human remains", "car transport", "vehicle transport", "motorbike transport", "industrial machinery", "specialist freight", "piano", "pianos"]) ||
    petTermDetected &&
    !includesAny(text, ["dog food", "cat food", "cat litter", "dog lead", "cat lead", "dog collar", "cat collar", "dog toy", "cat toy", "puppy food", "kitten food", "puppy toy", "kitten toy"])) {
    let referralType = "specialist_freight";
    if (hasSafetyTerm(safetyScan, ["snake", "goat", "insect", "insects", "perro", "dog", "cat", "puppy", "puppies", "kitten", "kittens"]) || includesAny(text, ["pet", "dog", "cat", "puppy", "puppies", "kitten", "kittens", "live animal", "livestock", "live fish", "animal transport", "veterinary transport"])) referralType = "pet_transport";
    if (includesAny(text, ["funeral", "deceased", "body transport", "human remains"])) referralType = "funeral_transport";
    if (includesAny(text, ["car transport", "vehicle transport", "motorbike transport"])) referralType = "vehicle_transport";
    return {status: "referral_required", reasonCodes: ["specialist_transport_required"], referralType, customerMessage: "This request needs a specialist referral rather than normal rider dispatch."};
  }
  if (lowInformationDescription(rawText, text)) {
    return {status: "unsupported", reasonCodes: ["insufficient_item_description"], referralType: null, customerMessage: "Please describe the item before normal dispatch can continue."};
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
  if (express) {
    const standardSubtotal = PRICING.baseFareGbp +
      distanceFare +
      weightBand.baseGbp +
      logisticsModifiers;
    logisticsModifiers += Math.max(
        PRICING.modifiers.express,
        roundMoney(standardSubtotal * 0.2),
    );
  }
  const vehicleText = normalize(vehicleType);
  const vehicleSurcharge = vehicleText.includes("van") ?
    PRICING.modifiers.vanVehicle :
    vehicleText.includes("car") ?
      PRICING.modifiers.carVehicle :
      0;
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
  const requiresVan = handlingFlags.includes("Van Required") ||
    weightKg >= deliveryPolicy.vehiclePolicy.vanRequiredMinKg;
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
    return {level: "enhanced_verification_required", reasons: ["high_value_or_fragile_item"]};
  }
  return {level: "standard_protection", reasons: ["normal_delivery_risk"]};
}

function workflowFor({category, declaredWorkflow}) {
  const workflow = normalize(declaredWorkflow);
  if (workflow.includes("health")) return "Health+";
  if (workflow.includes("business")) return "Business";
  if (workflow.includes("gift")) return "Gifts";
  if (category === "Medical & Pharmacy") return "Health+";
  return "Standard";
}

function vanguardPolicyFor({workflow, valueProtection, category, text}) {
  if (valueProtection && valueProtection.level === "admin_referral_required") {
    return {required: false, reason: ""};
  }
  if (workflow === "Business") {
    return {required: true, reason: "Vanguard is included for Business deliveries."};
  }
  if (workflow === "Health+") {
    return {required: true, reason: "Vanguard is included for Health+ deliveries."};
  }
  if (workflow === "Gifts") {
    return {required: true, reason: "Vanguard is included for Gifts deliveries."};
  }
  if (valueProtection && valueProtection.level === "enhanced_verification_required") {
    return {required: true, reason: "Vanguard is included for high-value deliveries."};
  }
  if (includesAny(text, ["passport", "legal document", "legal documents", "legal files", "confidential", "confidential contract", "confidential document", "confidential documents", "government paperwork", "exam papers"])) {
    return {required: true, reason: "Vanguard is included for protected documents."};
  }
  if (category === "Medical & Pharmacy" ||
      includesAny(text, ["medicine", "prescription", "insulin", "blood sample", "swab sample", "specimen"])) {
    return {required: true, reason: "Vanguard is included for medical deliveries."};
  }
  return {required: false, reason: ""};
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
    safeText(input.description),
    safeText(input.packageDescription),
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
  if (liftUnavailable &&
      (collectionFloor > 1 || deliveryFloor > 1 ||
        includesAny(values, ["stairs only", "third floor", "3rd floor", "fourth floor", "4th floor", "fifth floor", "5th floor"]))) {
    constraints.push("stairs_without_lift");
  }
  if (includesAny(values, ["tower block", "estate", "gated", "concierge"])) constraints.push("managed_or_gated_access");
  if (includesAny(values, ["hospital", "airport", "station", "stadium", "hotel", "university", "warehouse", "construction"])) constraints.push("controlled_site_access");
  if (includesAny(values, ["red route", "loading restriction", "loading bay", "restricted parking", "parking restriction", "no parking", "no parking outside", "pedestrian", "market", "forecourt", "bus gate", "ltn", "ulez", "congestion charge", "road closure", "school traffic", "school street", "airport", "airport security", "airport drop off", "security checkpoint", "event congestion", "event traffic", "football match", "match day", "concert congestion", "station", "station forecourt", "stadium", "temporary access restriction", "hospital access", "hospital loading", "construction zone", "construction site", "roadworks", "bridge restriction", "underground car park", "height restriction"])) constraints.push("declared_loading_or_parking_constraint");
  if (constraints.includes("stairs_without_lift")) instructions.push("Confirm stair access and safe carry before dispatch.");
  if (constraints.includes("managed_or_gated_access")) instructions.push("Request gate, estate, concierge or block access details.");
  if (constraints.includes("controlled_site_access")) instructions.push("Confirm reception, security or loading point before arrival.");
  if (constraints.includes("declared_loading_or_parking_constraint")) instructions.push("Rider should plan lawful loading access from supplied notes.");
  const difficulty = constraints.includes("stairs_without_lift") || constraints.length >= 3 ? "high" : constraints.length ? "moderate" : "low";
  return {
    difficulty,
    constraints,
    additionalPersonRecommended: difficulty === "high",
    vehicleAccessWarning: constraints.includes("declared_loading_or_parking_constraint") ||
      constraints.includes("stairs_without_lift"),
    loadingTimeWarning: difficulty !== "low",
    riderInstructions: instructions,
  };
}

function customerSafeIris(iris) {
  const recommendation = iris.recommendation || {};
  const operational = iris.operationalRecommendation || {};
  const vehicle = operational.vehicleRecommendation || {};
  const riderMatching = iris.internal && iris.internal.riderMatching ?
    iris.internal.riderMatching : {};
  const recommendedVehicle =
    customerVehicleLabel(vehicle) || riderMatching.vehicleRequired || null;
  const protection = operational.valueProtectionRecommendation || {};
  const vanguardRequired =
    protection.level === "enhanced_verification_required" ||
    iris.vanguardRequired === true;
  const vanguardRecommended =
    vanguardRequired ||
    protection.level === "enhanced_verification_recommended";
  const vanguardReason = iris.vanguardRequiredReason ||
    (protection.reasons || []).join(", ");
  return {
    version: iris.version || "v1",
    engineVersion: iris.engineVersion || iris.version || "iris-engine-v1",
    knowledgeVersion: iris.knowledgeVersion || "iris-knowledge-baseline-v1",
    weightPolicyVersion: iris.weightPolicyVersion || WEIGHT_POLICY_VERSION,
    workflow: iris.workflow || "Standard",
    itemName: recommendation.detectedItem || null,
    totalWeightKg: recommendation.estimatedWeightKg || null,
    recommendedVehicle,
    vanguardRequired,
    vanguardRequiredReason: vanguardRequired ? vanguardReason : null,
    vanguardRecommended,
    recommendation: {
      detectedItem: recommendation.detectedItem || null,
      estimatedWeightKg: recommendation.estimatedWeightKg || null,
      handlingFlags: recommendation.handlingFlags || [],
      recommendedVehicle,
      vanguardRequired,
      vanguardRequiredReason: vanguardRequired ? vanguardReason : null,
      vanguardRecommended,
      category: recommendation.category || null,
      weightBand: recommendation.weightBand || null,
      confidencePercent: recommendation.confidencePercent || null,
      customerSafeExplanation: customerSafeExplanation(iris),
    },
    vanguard: {
      required: vanguardRequired,
      recommended: vanguardRecommended,
      reason: vanguardRequired ?
        (vanguardReason || "Vanguard is included for this delivery.") :
        vanguardRecommended ?
          "Enhanced verification is recommended for this parcel." : null,
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

function customerVehicleLabel(vehicle) {
  if (!vehicle) return null;
  const required = `${vehicle.required || ""}`.trim();
  if (required && required !== "any") return required;
  if (vehicle.motorbikeSuitable === true) return "Motorbike";
  if (vehicle.carSuitable === true) return "Car";
  if (vehicle.vanSuitable === true) return "Van";
  return required || null;
}

function similarLearningMatches(description, completedExamples = []) {
  const text = normalize(description);
  if (!text) return [];
  const tokens = new Set(text.split(" ").filter((token) => token.length >= 4));
  return completedExamples.filter((example) => {
    const trusted = example && (example.trusted === true ||
      example.reviewStatus === "approved" || example.reviewStatus === "promoted");
    if (!trusted) return false;
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

function approvedCanonicalMatch(description, canonicalKnowledge = []) {
  const normalizedDescription = normalize(description);
  if (!normalizedDescription || !Array.isArray(canonicalKnowledge)) return null;
  return canonicalKnowledge.find((record) => {
    if (!record || record.status !== "active" || record.repositoryReviewStatus !== "promoted") return false;
    const name = normalize(record.canonicalName || record.objectName || "");
    return name && (normalizedDescription === name || normalizedDescription.includes(name));
  }) || null;
}

function classifyIris(input = {}) {
  const description = safeText(input.description || input.packageDescription || "");
  const text = normalize(description);
  const declaredWeightText = safeText(input.declaredWeightText || input.weight || "");
  const speed = safeText(input.speed || "");
  const express = normalize(speed) === "express" || input.express === true || input.urgent === true;
  const compliance = complianceFor(text, description);
  const shipmentItems = extractShipmentItems(description);
  const shipmentSummary = splitItemClauses(description).length >= 2 && shipmentItems.length >= 1 ?
    summarizeShipmentItems(shipmentItems) : null;
  const weightAuthority = resolveAuthoritativeShipmentWeight({
    rawText: description,
    declaredWeightText,
    shipmentSummary,
    shipmentItems,
    photoEstimatedWeightKg: input.photoEstimatedWeightKg,
  });
  const canonicalMatch = approvedCanonicalMatch(description, input.canonicalKnowledge);
  const canonicalWeightKg = Number(canonicalMatch && canonicalMatch.knownWeight);
  const estimatedWeightKg = Number.isFinite(canonicalWeightKg) && canonicalWeightKg > 0 ?
    Math.max(weightAuthority.authoritativeWeightKg, canonicalWeightKg) : weightAuthority.authoritativeWeightKg;
  const baseCategory = canonicalMatch && canonicalMatch.category || classifyCategory(text, shipmentSummary);
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
  price.normalCheckoutEligible = compliance.status === "allowed";
  if (!price.normalCheckoutEligible) {
    price.checkoutBlockReason = "not_allowed_for_normal_dispatch";
  }
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
  const recommendation = compliance.status === "allowed" && !canonicalMatch ?
    applyLearningMemory(baseRecommendation, description, input.completedExamples || []) :
    baseRecommendation;
  const authoritativeRecommendation = {
    ...recommendation,
    estimatedWeightKg,
    weightBand: weightBandFor(estimatedWeightKg),
    handlingFlags,
    estimatedPrice: price.total,
  };
  const serviceability = serviceabilityFor({
    complianceStatus: compliance.status,
    weightKg: authoritativeRecommendation.estimatedWeightKg,
    handlingFlags: authoritativeRecommendation.handlingFlags,
  });
  const dimensionalBand = dimensionalBandFor({
    text,
    weightKg: authoritativeRecommendation.estimatedWeightKg,
    handlingFlags: authoritativeRecommendation.handlingFlags,
    shipmentSummary,
  });
  const matching = matchingRequirementsFor({
    handlingFlags: authoritativeRecommendation.handlingFlags,
    weightKg: authoritativeRecommendation.estimatedWeightKg,
    express,
  });
  if (compliance.status !== "allowed") {
    matching.vehicleRequired = "van";
  }
  const access = accessIntelligenceFor(input);
  const verificationPolicy = verificationPolicyFor({
    text,
    category: authoritativeRecommendation.category,
    handlingFlags: authoritativeRecommendation.handlingFlags,
    complianceStatus: compliance.status,
    serviceability,
  });
  const valueProtection = valueProtectionFor({
    text,
    category: authoritativeRecommendation.category,
    handlingFlags: authoritativeRecommendation.handlingFlags,
    complianceStatus: compliance.status,
  });
  const workflow = workflowFor({
    category: authoritativeRecommendation.category,
    declaredWorkflow: input.workflow || input.serviceType || input.productType,
  });
  const vanguardPolicy = vanguardPolicyFor({
    workflow,
    valueProtection,
    category: authoritativeRecommendation.category,
    text,
  });
  const operationalWarnings = [];
  if (access.vehicleAccessWarning) operationalWarnings.push("Declared access or loading constraints may affect rider approach.");
  if (access.loadingTimeWarning) operationalWarnings.push("Access conditions may require additional handover time.");
  if (dimensionalBand.id === "oversized" || dimensionalBand.id === "long") operationalWarnings.push("Item dimensions may constrain vehicle choice.");
  const iris = {
    version: input.engineVersion || "iris-engine-v1",
    engineVersion: input.engineVersion || "iris-engine-v1",
    knowledgeVersion: input.knowledgeVersion || "iris-knowledge-baseline-v1",
    weightPolicyVersion: WEIGHT_POLICY_VERSION,
    status: compliance.status,
    workflow,
    vanguardRequired: vanguardPolicy.required,
    vanguardRequiredReason: vanguardPolicy.reason,
    customerDeclaration: {
      description: description.trim(),
      declaredWeightText: `${declaredWeightText || ""}`.trim() || null,
      declaredCategory: input.declaredCategory || null,
      confidence: "low",
    },
    recommendation: authoritativeRecommendation,
    operationalRecommendation: {
      dimensionalBand,
      vehicleRecommendation: {
        required: matching.vehicleRequired,
        motorbikeSuitable: matching.vehicleRequired === "any" && authoritativeRecommendation.estimatedWeightKg <= 10,
        carSuitable: matching.vehicleRequired === "any" &&
          authoritativeRecommendation.estimatedWeightKg < deliveryPolicy.vehiclePolicy.carSuitableMaxExclusiveKg,
        vanSuitable: true,
        heavyDutySuitable: authoritativeRecommendation.estimatedWeightKg > 50 || authoritativeRecommendation.handlingFlags.includes("Two Person Lift"),
      },
      accessComplexity: access.difficulty,
      valueProtectionRecommendation: valueProtection,
      operationalWarnings,
      confidence: authoritativeRecommendation.confidencePercent,
    },
    internal: {
      context: internalContext,
      riskScore: compliance.status === "prohibited" ? 0.95 : compliance.status === "unsupported" ? 0.55 : 0.12,
      logisticsScore: authoritativeRecommendation.handlingFlags.length / HANDLING_FLAGS.length,
      pricingModifiers: price,
      riderMatching: matching,
      weightAuthority,
      shipmentSummary: shipmentSummary ? {
        itemCount: shipmentSummary.itemCount,
        totalQuantity: shipmentSummary.totalQuantity,
        combinedWeightKg: shipmentSummary.combinedWeightKg,
        dominantItemId: shipmentSummary.dominantItem.id,
        vehicleRequired: shipmentSummary.vehicleRequired,
      } : null,
      accessIntelligence: access,
      learningMatchedExamples: authoritativeRecommendation.learningMatchedExamples || 0,
      canonicalKnowledgeMatch: canonicalMatch ? canonicalMatch.canonicalId || canonicalMatch.id || null : null,
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

function requestIrisDescription(request = {}) {
  const parcel = request.parcel && typeof request.parcel === "object" ? request.parcel : {};
  const declaration = request.iris && request.iris.customerDeclaration || {};
  return safeText(
      request.packageDescription ||
      request.originalDescription ||
      parcel.description ||
      parcel.itemName ||
      request.normalizedItemName ||
      declaration.description ||
      request.description ||
      "",
  );
}

function serverIrisForDispatch(request = {}) {
  const parcel = request.parcel && typeof request.parcel === "object" ? request.parcel : {};
  const description = requestIrisDescription(request);
  if (!description) return null;
  return classifyIris({
    description,
    declaredWeightText: request.weight || request.weightLabel || parcel.weightLabel || parcel.weightKg || "",
    photoEstimatedWeightKg: request.photoEstimatedWeightKg ||
      request.irisPhotoAnalysis && request.irisPhotoAnalysis.estimatedWeightKg ||
      request.iris && request.iris.photoAnalysis && request.iris.photoAnalysis.estimatedWeightKg ||
      null,
    distanceMiles: request.distanceMiles || request.routeDistanceMiles || 0,
    speed: request.selectedSpeed || request.selectedServiceLevel || request.serviceLevel || request.speed || "",
    vehicleType: request.vehicleType || request.recommendedVehicle || null,
  });
}

function dispatchComplianceDecision(request = {}) {
  if (TERMINAL_DELIVERY_STATUSES.has(normalize(request.status))) {
    return {dispatchable: false, reason: "terminal_delivery_status"};
  }
  if (["prohibited", "referral_required", "unsupported"].includes(normalize(request.status))) {
    return {dispatchable: false, reason: "blocked_request_status"};
  }
  if (normalize(request.matchingStatus) === "blocked") {
    return {dispatchable: false, reason: "blocked_matching_status"};
  }
  const serverIris = serverIrisForDispatch(request);
  if (!serverIris) {
    return {dispatchable: false, reason: "missing_server_iris"};
  }
  const compliance = serverIris.compliance && serverIris.compliance.status || serverIris.status || "prohibited";
  const serviceability = serverIris.serviceability && serverIris.serviceability.status || "manual_review";
  const storedIris = request.iris || {};
  const storedCompliance = storedIris.compliance && storedIris.compliance.status || storedIris.status || null;
  const storedServiceability = storedIris.serviceability && storedIris.serviceability.status || null;
  return {
    dispatchable: compliance === "allowed" && serviceability === "serviceable",
    reason: compliance === "allowed" && serviceability === "serviceable" ?
      "server_iris_allowed" :
      "server_iris_blocked",
    compliance,
    serviceability,
    serverIris,
    storedIrisMismatch: Boolean(
        storedCompliance && storedCompliance !== compliance ||
        storedServiceability && storedServiceability !== serviceability,
    ),
  };
}

function isDispatchable(request) {
  return dispatchComplianceDecision(request).dispatchable === true;
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

function isApprovedRiderForDispatch(rider = {}) {
  return accountEligibilityDecision(rider).eligible === true;
}

function riderDispatchEligibilityReason(rider = {}) {
  const decision = accountEligibilityDecision(rider);
  return decision.eligible ? null : decision.reason;
}

function riderCanViewDispatch(rider, request, now = Date.now()) {
  return isApprovedRiderForDispatch(rider);
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
  dispatchComplianceDecision,
  isDispatchable,
  requestIrisDescription,
  serverIrisForDispatch,
  riderMatchesIris,
  dispatchPriority,
  normalizeRiderRank,
  riderCanViewDispatch,
  riderDispatchEligibilityReason,
  riderDispatchPriority,
  deliveryProtocolState,
  normalizeVehicleClass: vehicleDispatch.normalizeVehicleClass,
  normalizeRiderVehicle: vehicleDispatch.normalizeRiderVehicle,
  pickRequiredVehicle: vehicleDispatch.pickRequiredVehicle,
  vehicleCanHandle: vehicleDispatch.vehicleCanHandle,
};
