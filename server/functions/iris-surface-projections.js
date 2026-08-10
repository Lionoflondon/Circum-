/* eslint-disable require-jsdoc */
"use strict";

function value(source, path, fallback = null) {
  let current = source;
  for (const key of path) {
    if (!current || typeof current !== "object") return fallback;
    current = current[key];
  }
  return current === undefined ? fallback : current;
}

function versions(iris) {
  return {
    engineVersion: iris.engineVersion || iris.version || "iris-engine-v1",
    knowledgeVersion: iris.knowledgeVersion || "iris-knowledge-baseline-v1",
    weightPolicyVersion: iris.weightPolicyVersion || null,
    visualModelVersion: iris.visualModelVersion || null,
  };
}

function common(iris) {
  return {
    category: value(iris, ["recommendation", "category"]),
    weightBand: value(iris, ["recommendation", "weightBand"]),
    handlingRequirements: value(iris, ["recommendation", "handlingFlags"], []),
    serviceRequirement: value(iris, ["internal", "riderMatching", "vehicleRequired"]),
    ...versions(iris),
  };
}

function projectIrisForSurface(iris = {}, surface, context = {}) {
  const base = common(iris);
  switch (`${surface || ""}`.trim().toLowerCase()) {
    case "sender":
    case "website":
      return {
        detectedItem: iris.workflow === "Health+" ? "Medical parcel" : value(iris, ["recommendation", "detectedItem"]),
        ...base,
        confidenceBand: value(iris, ["recommendation", "confidenceBand"]),
        reviewState: value(iris, ["riskResolution", "resolution"], "REVIEW"),
      };
    case "rider":
      return {
        recommendation: iris.workflow === "Health+" ? "Medical parcel" : value(iris, ["recommendation", "detectedItem"]),
        ...base,
        paidWeightBand: context.paidWeightBand || null,
        discrepancyAllowed: context.discrepancyAllowed === true,
        evidenceRequirements: value(iris, ["verification", "evidenceTypes"], []),
      };
    case "business":
      return {
        category: base.category,
        weightBand: base.weightBand,
        handlingClass: base.handlingRequirements,
        serviceRequirement: base.serviceRequirement,
        slaRelevant: context.slaRelevant === true,
        complianceFlags: value(iris, ["compliance", "reasonCodes"], []),
        ...versions(iris),
      };
    case "gift":
    case "gifts":
      return {
        giftCategory: base.category,
        weightBand: base.weightBand,
        fragile: base.handlingRequirements.includes("Fragile"),
        perishable: base.handlingRequirements.includes("Perishable"),
        packagingRequirements: context.packagingRequirements || [],
        procurementSuitable: value(iris, ["riskResolution", "resolution"]) === "CLEAR",
        substitutionConstraints: context.substitutionConstraints || [],
        ...versions(iris),
      };
    case "health":
    case "health+":
      return {
        itemLabel: "Medical parcel",
        handlingRequirements: base.handlingRequirements,
        coldChainRequired: context.coldChainRequired === true,
        fragile: base.handlingRequirements.includes("Fragile"),
        urgency: context.urgency || null,
        scheduledHandling: context.scheduledHandling === true,
        recipientVerificationRequired: context.recipientVerificationRequired === true,
        ...versions(iris),
      };
    case "scheduled":
      return {...base, timingSensitive: true, scheduledJourneyAt: context.scheduledJourneyAt || null};
    case "vanguard":
      return {...base, enhancedVerification: true, evidenceRequired: true, highValueHandling: true};
    case "heavy_duty":
    case "heavy duty":
      return {
        ...base,
        vehicleRequirement: base.serviceRequirement || "van",
        twoPersonRequired: base.handlingRequirements.includes("Two Person Lift"),
        collectionHoldIfUnsuitable: true,
      };
    case "admin":
      return {
        ...base,
        detectedItem: value(iris, ["recommendation", "detectedItem"]),
        confidence: value(iris, ["internal", "confidenceCalibration"]),
        riskResolution: iris.riskResolution || null,
        canonicalKnowledgeMatch: value(iris, ["internal", "canonicalKnowledgeMatch"]),
        inferencePath: value(iris, ["internal", "inferencePath"]),
      };
    default:
      throw new Error("Unsupported IRIS surface projection.");
  }
}

module.exports = {projectIrisForSurface, versions};
