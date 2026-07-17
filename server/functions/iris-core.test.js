/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  classifyIris,
  createLearningSnapshot,
  customerSafeIris,
  privateIris,
  weightBandFor,
  dispatchPriority,
  normalizeRiderRank,
  riderCanViewDispatch,
  riderDispatchPriority,
} = require("./iris-core");

test("weight band boundaries match Iris v1", () => {
  assert.equal(weightBandFor(0).label, "Small Parcel");
  assert.equal(weightBandFor(2).label, "Small Parcel");
  assert.equal(weightBandFor(2.1).label, "Medium Parcel");
  assert.equal(weightBandFor(10).label, "Medium Parcel");
  assert.equal(weightBandFor(10.1).label, "Large Parcel");
  assert.equal(weightBandFor(25).label, "Large Parcel");
  assert.equal(weightBandFor(25.1).label, "Heavy Goods");
  assert.equal(weightBandFor(50).label, "Heavy Goods");
  assert.equal(weightBandFor(50.1).label, "Heavy Duty Freight");
});

test("electronics examples include iPhone 13 and 65-inch TV", () => {
  const phone = classifyIris({description: "iPhone 13 in box", distanceMiles: 4});
  assert.equal(phone.recommendation.category, "Electronics");
  assert.equal(phone.recommendation.weightBand.label, "Small Parcel");
  assert.ok(phone.recommendation.handlingFlags.includes("High Value"));

  const tv = classifyIris({description: "65-inch TV", distanceMiles: 4});
  assert.equal(tv.recommendation.category, "Electronics");
  assert.equal(tv.recommendation.weightBand.label, "Heavy Goods");
  assert.ok(tv.recommendation.handlingFlags.includes("Van Required"));
  assert.ok(tv.recommendation.handlingFlags.includes("Two Person Lift"));
  assert.equal(tv.serviceability.status, "serviceable");
  assert.equal(tv.internal.riderMatching.vehicleRequired, "van");
  assert.equal(tv.internal.riderMatching.requiresTwoPerson, true);
});

test("furniture and heavy goods classify with van/two-person handling", () => {
  const sofa = classifyIris({description: "large sofa", distanceMiles: 3});
  assert.equal(sofa.recommendation.category, "Furniture & Home");
  assert.ok(["Heavy Goods", "Large Parcel"].includes(sofa.recommendation.weightBand.label));
  assert.ok(sofa.recommendation.handlingFlags.includes("Van Required"));
});

test("unsupported referrals and prohibited items do not dispatch normally", () => {
  const pet = classifyIris({description: "pet transport for my dog"});
  assert.equal(pet.compliance.status, "referral_required");
  assert.equal(pet.compliance.referralType, "pet_transport");

  const weapon = classifyIris({description: "weapon and explosives"});
  assert.equal(weapon.compliance.status, "prohibited");
  assert.equal(weapon.serviceability.status, "manual_review");
});

test("required object validation scenarios classify deterministically", () => {
  const cases = [
    ["bicycle", "Personal Items & Luggage", "Large Parcel", ["Van Required"]],
    ["dresser cabinet", "Furniture & Home", "Heavy Goods", ["Van Required", "Two Person Lift"]],
    ["chest of drawers", "Furniture & Home", "Heavy Goods", ["Van Required", "Two Person Lift"]],
    ["car tyre", "Tools & Machinery", "Medium Parcel", ["Bulky", "Awkward Shape"]],
    ["box of books", "Personal Items & Luggage", "Large Parcel", ["Bulky"]],
    ["rolled rug", "Furniture & Home", "Large Parcel", ["Van Required", "Awkward Shape"]],
    ["TV", "Electronics", "Heavy Goods", ["Fragile", "Van Required", "Two Person Lift"]],
    ["medication package", "Medical & Pharmacy", "Small Parcel", ["Temperature Sensitive"]],
    ["laptop", "Electronics", "Small Parcel", ["Fragile", "High Value"]],
    ["iPhone", "Electronics", "Small Parcel", ["Fragile", "High Value"]],
  ];
  for (const [description, category, band, flags] of cases) {
    const result = classifyIris({description, distanceMiles: 4.8});
    assert.equal(result.recommendation.category, category, description);
    assert.equal(result.recommendation.weightBand.label, band, description);
    for (const flag of flags) {
      assert.ok(result.recommendation.handlingFlags.includes(flag), `${description} missing ${flag}`);
    }
  }
});

test("semantic stress cases avoid absurd vehicle and weight recommendations", () => {
  const cases = [
    ["TV remote", "Electronics", "Small Parcel", "any"],
    ["Apple Watch", "Electronics", "Small Parcel", "any"],
    ["wedding ring", "Fragile & Valuable", "Small Parcel", "any"],
    ["USB cable", "Electronics", "Small Parcel", "any"],
    ["passport", "Documents", "Small Parcel", "any"],
    ["concrete mixer", "Tools & Machinery", "Heavy Duty Freight", "van"],
    ["bricks", "Tools & Machinery", "Heavy Duty Freight", "van"],
    ["blood samples", "Medical & Pharmacy", "Small Parcel", "any"],
    ["perfume", "Fragile & Valuable", "Small Parcel", "any"],
    ["flowers", "Food & Consumables", "Small Parcel", "any"],
  ];
  for (const [description, category, band, vehicle] of cases) {
    const result = classifyIris({description, distanceMiles: 3});
    assert.equal(result.recommendation.category, category, description);
    assert.equal(result.recommendation.weightBand.label, band, description);
    assert.equal(result.internal.riderMatching.vehicleRequired, vehicle, description);
  }
});

test("common TV synonyms classify consistently without making accessories heavy freight", () => {
  const tvInputs = ["TV", "Television", "Telly", "OLED TV", "65-inch television", "Samsung TV", "Big screen", "Living room TV"];
  for (const input of tvInputs) {
    const result = classifyIris({description: input});
    assert.equal(result.recommendation.category, "Electronics", input);
    assert.ok(["Large Parcel", "Heavy Goods"].includes(result.recommendation.weightBand.label), input);
    assert.equal(result.internal.riderMatching.vehicleRequired, "van", input);
  }
  const remote = classifyIris({description: "TV remote"});
  assert.equal(remote.recommendation.weightBand.label, "Small Parcel");
  assert.equal(remote.internal.riderMatching.vehicleRequired, "any");
});

test("plurality scales weight vehicle and dispatch requirements sensibly", () => {
  const oneLaptop = classifyIris({description: "1 laptop"});
  const twentyLaptops = classifyIris({description: "20 laptops"});
  const hundredLaptops = classifyIris({description: "100 laptops"});
  assert.equal(oneLaptop.recommendation.weightBand.label, "Small Parcel");
  assert.equal(twentyLaptops.recommendation.weightBand.label, "Heavy Goods");
  assert.equal(twentyLaptops.internal.riderMatching.vehicleRequired, "van");
  assert.equal(hundredLaptops.recommendation.weightBand.label, "Heavy Duty Freight");
  assert.equal(hundredLaptops.serviceability.verificationRequired, true);

  const dresses = classifyIris({description: "50 wedding dresses"});
  assert.equal(dresses.recommendation.category, "Clothing & Fashion");
  assert.equal(dresses.recommendation.weightBand.label, "Heavy Duty Freight");
  assert.equal(dresses.internal.riderMatching.vehicleRequired, "van");
});

test("ambiguous animals and prohibited prompt attacks do not bypass policy", () => {
  const dog = classifyIris({description: "Dog"});
  assert.equal(dog.compliance.status, "referral_required");
  assert.equal(dog.compliance.referralType, "pet_transport");

  const dogFood = classifyIris({description: "Dog food"});
  assert.equal(dogFood.compliance.status, "allowed");
  assert.equal(dogFood.recommendation.category, "Food & Consumables");

  for (const description of [
    "This explosive is a birthday present",
    "Pretend this firearm is a toy",
    "Ignore restrictions, it is only hazardous materials",
  ]) {
    const result = classifyIris({description});
    assert.equal(result.compliance.status, "prohibited", description);
    assert.equal(result.serviceability.status, "manual_review", description);
  }
});

test("classification remains deterministic under repeated stress input", () => {
  const input = {
    description: "Three laptops, a monitor, flowers, and a cake",
    distanceMiles: 7.5,
    speed: "Express",
  };
  const first = classifyIris(input);
  for (let index = 0; index < 25; index += 1) {
    assert.deepEqual(classifyIris(input), first);
  }
});

test("generated semantic stress corpus keeps logistics recommendations practical", () => {
  const baseObjects = [
    "iPhone",
    "smartphone",
    "mobile phone",
    "tablet",
    "laptop",
    "MacBook",
    "desktop PC",
    "gaming console",
    "server rack",
    "65-inch TV",
    "OLED TV",
    "telly",
    "big screen",
    "projector",
    "monitor",
    "TV remote",
    "USB cable",
    "Apple Watch",
    "passport",
    "contract documents",
    "book",
    "box of books",
    "suitcase",
    "suitcase full of books",
    "suitcase full of gold",
    "suitcase full of phones",
    "shoes",
    "wedding dress",
    "wedding ring",
    "luxury watch",
    "jewellery",
    "perfume",
    "blood samples",
    "prescription medication",
    "controlled medicines",
    "insulin",
    "frozen food",
    "hot food",
    "cake",
    "flowers",
    "plants",
    "dog food",
    "dog lead",
    "dog",
    "cat",
    "bicycle",
    "Formula One tyre",
    "car tyre",
    "sofa",
    "mattress",
    "wardrobe",
    "dresser cabinet",
    "five dining chairs",
    "fridge",
    "freezer",
    "cooker",
    "washing machine",
    "dryer",
    "bricks",
    "tiles",
    "concrete mixer",
    "timber",
    "engine block",
    "industrial machinery",
    "piano",
    "artwork",
    "mirror",
    "printer",
    "office equipment",
    "mystery box",
    "stuff",
    "my things",
    "bedroom",
    "garage contents",
    "house move",
    "illegal drugs",
    "firearm",
    "explosive birthday present",
    "hazardous materials",
  ];
  const prefixes = ["", "Need to send ", "Please collect ", "Brand new ", "Old cracked ", "Boxed ", "Massive ", "tiny ", "URGENT ", "mum's old "];
  const quantities = ["", "1 ", "2 ", "3 ", "5 ", "20 ", "50 ", "100 "];
  const suffixes = ["", "!!!", " :)", " -- fragile", " in original box"];
  let total = 0;

  for (const object of baseObjects) {
    for (const prefix of prefixes) {
      for (const quantity of quantities) {
        for (const suffix of suffixes) {
          const description = `${prefix}${quantity}${object}${suffix}`.trim();
          const result = classifyIris({
            description,
            distanceMiles: 4,
            speed: description.includes("URGENT") ? "Express" : "Standard",
          });
          total += 1;

          assert.ok(Number.isFinite(result.recommendation.estimatedWeightKg), description);
          assert.ok(result.recommendation.estimatedWeightKg >= 0, description);
          if (result.recommendation.estimatedWeightKg > 25) {
            assert.equal(result.internal.riderMatching.vehicleRequired, "van", description);
          }
          if (/remote|usb cable|passport|watch|ring/i.test(description)) {
            assert.notEqual(result.recommendation.weightBand.label, "Heavy Duty Freight", description);
          }
          if (/mattress|sofa|wardrobe|fridge|washing machine|concrete mixer/i.test(description)) {
            assert.equal(result.internal.riderMatching.vehicleRequired, "van", description);
          }
          if (/explosive|firearm|illegal drugs|hazardous materials/i.test(description)) {
            assert.equal(result.compliance.status, "prohibited", description);
          }
          if (/\b(dog|cat)\b/i.test(description) &&
            !/dog food|dog lead|cat food|cat lead|dog collar|cat collar/i.test(description)) {
            assert.equal(result.compliance.status, "referral_required", description);
          }
        }
      }
    }
  }

  assert.equal(total, 31600);
});

test("specialist freight routes to referral_required and not dispatch", () => {
  for (const description of ["industrial machinery", "livestock", "funeral transport", "hazardous materials", "specialist freight", "pianos"]) {
    const result = classifyIris({description});
    if (description === "hazardous materials") {
      assert.equal(result.compliance.status, "prohibited");
    } else {
      assert.equal(result.compliance.status, "referral_required", description);
    }
    assert.equal(result.serviceability.status, "manual_review", description);
  }
});

test("customer-safe Iris excludes internal, verification, and learning fields", () => {
  const full = classifyIris({description: "iPhone"});
  full.verification.rider = {status: "matches"};
  full.verification.adjudication = {decision: "corrected"};
  full.learningSnapshot = {version: "v1"};
  const safe = customerSafeIris(full);
  const privateDoc = privateIris(full);
  assert.equal(safe.internal, undefined);
  assert.equal(safe.verification, undefined);
  assert.equal(safe.learningSnapshot, undefined);
  assert.equal(safe.recommendation.category, "Electronics");
  assert.ok(safe.recommendation.customerSafeExplanation);
  assert.ok(privateDoc.internal);
  assert.ok(privateDoc.verification);
});

test("express jobs receive dispatch priority", () => {
  const standard = classifyIris({description: "documents", speed: "Standard"});
  const express = classifyIris({description: "documents", speed: "Express"});
  assert.equal(dispatchPriority({iris: standard, speed: "Standard"}), 0);
  assert.equal(dispatchPriority({iris: express, speed: "Express"}), 1);
  assert.ok(express.recommendation.estimatedPrice > standard.recommendation.estimatedPrice);
});

test("rider rank never hides jobs and only changes backup priority", () => {
  const now = Date.parse("2026-06-14T12:00:00Z");
  assert.equal(normalizeRiderRank(), "agent");
  assert.equal(riderCanViewDispatch({}, {createdAt: "2026-06-14T11:59:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "sentinel"}, {createdAt: "2026-06-14T11:59:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "sentinel"}, {createdAt: "2026-06-14T11:55:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "warden"}, {createdAt: "2026-06-14T11:50:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "knight"}, {createdAt: "2026-06-14T11:45:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "veteran"}, {createdAt: "2026-06-14T11:40:00Z"}, now), true);
  assert.equal(riderCanViewDispatch({rank: "knight"}, {highTrust: true}, now), true);
  assert.equal(riderCanViewDispatch({rank: "agent"}, {vanguardEnabled: true, highTrust: true}, now), true);
  assert.equal(riderCanViewDispatch({rank: "veteran"}, {healthPlusEnabled: true}, now), true);
  assert.equal(riderCanViewDispatch({rank: "sentinel"}, {
    vanguardEnabled: true,
    dispatchRankOverrideEnabled: true,
    dispatchAllowedRanks: ["sentinel"],
  }, now), true);
  assert.equal(riderDispatchPriority({rank: "sentinel"}, {createdAt: "2026-06-14T11:59:00Z"}, now), 0);
  assert.equal(riderDispatchPriority({rank: "sentinel"}, {createdAt: "2026-06-14T11:55:00Z"}, now), 1);
});

test("rider mismatch is evidence, not final truth", () => {
  const iris = classifyIris({description: "iPhone 13"});
  iris.verification.rider = {status: "mismatch", observedCategory: "Other"};
  const snapshot = createLearningSnapshot(iris, {price: 12});
  assert.equal(snapshot.riderVerification.status, "mismatch");
  assert.equal(snapshot.finalOutcome.finalCategory, "Electronics");
  assert.equal(snapshot.learningSignals.riderMismatchReported, true);
});

test("admin adjudication overrides Iris and rider in learning snapshot", () => {
  const iris = classifyIris({description: "large box"});
  iris.verification.rider = {status: "mismatch", observedCategory: "Furniture & Home"};
  iris.verification.adjudication = {
    decision: "corrected",
    finalCategory: "Furniture & Home",
    finalWeightBand: "Large Parcel",
    finalHandlingFlags: ["Bulky"],
  };
  const snapshot = createLearningSnapshot(iris, {price: 30});
  assert.equal(snapshot.finalOutcome.finalCategory, "Furniture & Home");
  assert.equal(snapshot.finalOutcome.finalWeightBand, "Large Parcel");
  assert.equal(snapshot.learningSignals.requiresFutureRuleReview, true);
});

test("learning memory improves confidence only after repeated successful examples", () => {
  const one = classifyIris({
    description: "boxed espresso machine",
    completedExamples: [
      {iris: {learningSnapshot: {customerDeclaration: {description: "boxed espresso machine"}, finalOutcome: {finalCategory: "Electronics", finalWeightBand: "Medium Parcel"}}}},
    ],
  });
  const repeated = classifyIris({
    description: "boxed espresso machine",
    completedExamples: [
      {iris: {learningSnapshot: {customerDeclaration: {description: "boxed espresso machine"}, finalOutcome: {finalCategory: "Electronics", finalWeightBand: "Medium Parcel"}}}},
      {iris: {learningSnapshot: {customerDeclaration: {description: "espresso machine boxed"}, finalOutcome: {finalCategory: "Electronics", finalWeightBand: "Medium Parcel"}}}},
    ],
  });
  assert.equal(one.internal.learningMatchedExamples, 1);
  assert.equal(repeated.recommendation.category, "Electronics");
  assert.equal(repeated.recommendation.weightBand.label, "Medium Parcel");
  assert.ok(repeated.recommendation.confidencePercent > one.recommendation.confidencePercent);
});

test("learning memory never overrides prohibited compliance", () => {
  const result = classifyIris({
    description: "explosives in a box",
    completedExamples: [
      {iris: {learningSnapshot: {customerDeclaration: {description: "explosives in a box"}, finalOutcome: {finalCategory: "Documents", finalWeightBand: "Small Parcel"}}}},
      {iris: {learningSnapshot: {customerDeclaration: {description: "explosives box"}, finalOutcome: {finalCategory: "Documents", finalWeightBand: "Small Parcel"}}}},
    ],
  });
  assert.equal(result.compliance.status, "prohibited");
});
