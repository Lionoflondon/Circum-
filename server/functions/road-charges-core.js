/* eslint-disable max-len, require-jsdoc */
"use strict";

const ROAD_CHARGE_POLICY_VERSION = "2026-08-road-charges-v1";
const CENTRAL_LONDON_FEE_PENCE = 900;

// Tariffs are versioned data. Route facts must come from an authoritative route
// provider; client-supplied geometry is intentionally ignored by callers.
const ROAD_CHARGE_POLICY = Object.freeze({
  version: ROAD_CHARGE_POLICY_VERSION,
  currency: "GBP",
  commercialPolicy: Object.freeze({
    centralLondonFeePence: CENTRAL_LONDON_FEE_PENCE,
    effectiveFrom: "2026-08-01T00:00:00+01:00",
    effectiveUntil: null,
    customerLabel: "Central London fee",
    customerCopy: "Applies to eligible deliveries within the Congestion Charge Zone.",
  }),
  charges: Object.freeze({
    congestion_charge: Object.freeze({
      id: "congestion_charge",
      authority: "Transport for London",
      type: "daily_zone_charge",
      amountPence: 1800,
      effectiveFrom: "2026-01-02T00:00:00+00:00",
      effectiveUntil: null,
      applicableVehicles: Object.freeze(["car", "van"]),
      chargingHours: "07:00-18:00 Monday-Friday; 12:00-18:00 weekends and bank holidays",
      settlementTreatment: "daily_vehicle_liability_half_customer_fee_recovery_waterfall",
      source: "tfl_congestion_charge",
    }),
    blackwall_silvertown: Object.freeze({
      id: "blackwall_silvertown",
      authority: "Transport for London",
      type: "route_toll",
      effectiveFrom: "2025-04-07T00:00:00+00:00",
      effectiveUntil: null,
      chargingHours: "06:00-22:00 daily",
      ratesPence: Object.freeze({
        motorbike: Object.freeze({offPeak: 150, peak: 250}),
        car: Object.freeze({offPeak: 150, peak: 400}),
        van: Object.freeze({offPeak: 150, peak: 400}),
      }),
      settlementTreatment: "customer_pass_through_rider_reimbursement_no_commission",
      source: "tfl_blackwall_silvertown",
    }),
    dartford_crossing: Object.freeze({
      id: "dartford_crossing",
      authority: "National Highways",
      type: "route_toll",
      amountBasis: "one_off_payment",
      effectiveFrom: "2025-09-01T00:00:00+00:00",
      effectiveUntil: null,
      chargingHours: "06:00-22:00 daily",
      ratesPence: Object.freeze({motorcycle: 0, car: 350, van_2_axle: 420, van_multi_axle: 840}),
      settlementTreatment: "customer_pass_through_rider_reimbursement_no_commission",
      source: "govuk_dart_charge",
    }),
    ulez: Object.freeze({
      id: "ulez",
      authority: "Transport for London",
      type: "vehicle_compliance_charge",
      effectiveFrom: "2023-08-29T00:00:00+00:00",
      effectiveUntil: null,
      settlementTreatment: "vehicle_compliance_not_sender_surcharge",
      source: "tfl_ulez",
    }),
    lez: Object.freeze({
      id: "lez",
      authority: "Transport for London",
      type: "vehicle_compliance_charge",
      effectiveFrom: "2008-02-04T00:00:00+00:00",
      effectiveUntil: null,
      settlementTreatment: "vehicle_compliance_not_sender_surcharge",
      source: "tfl_lez",
    }),
  }),
});

function normalizeVehicle(value) {
  const normalized = `${value || ""}`.trim().toLowerCase();
  if (/(van|luton|transit|sprinter)/.test(normalized)) return "van";
  if (/(car|estate|suv|4x4|sedan|saloon|hatchback)/.test(normalized)) return "car";
  if (/(motorbike|motorcycle|motor bike|scooter|bike)/.test(normalized)) return "motorbike";
  return "unknown";
}

function vehicleTariffClassification(vehicleProfile = {}) {
  const vehicleClass = normalizeVehicle(vehicleProfile.type || vehicleProfile.vehicleClass || vehicleProfile.vehicleType);
  if (vehicleClass === "motorbike") return "motorcycle";
  if (vehicleClass === "car") return "car";
  if (vehicleClass !== "van") return "unknown";
  const axleCount = Number(vehicleProfile.axleCount);
  if (Number.isInteger(axleCount) && axleCount === 2) return "van_2_axle";
  if (Number.isInteger(axleCount) && axleCount > 2) return "van_multi_axle";
  return "unknown";
}

function integerPence(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.round(parsed)) : 0;
}

function moneyFromPence(pence) {
  return integerPence(pence) / 100;
}

function dateParts(value) {
  const date = value instanceof Date ? value : new Date(value || Date.now());
  if (Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date).reduce((result, part) => {
    result[part.type] = part.value;
    return result;
  }, {});
  return {
    date: new Intl.DateTimeFormat("en-CA", {timeZone: "Europe/London"}).format(date),
    weekday: parts.weekday,
    hour: Number(parts.hour),
    minute: Number(parts.minute),
  };
}

function minutesOfDay(parts) {
  return parts ? parts.hour * 60 + parts.minute : null;
}

function withinWindow(parts, startHour, endHour) {
  const minutes = minutesOfDay(parts);
  return minutes != null && minutes >= startHour * 60 && minutes < endHour * 60;
}

function isWeekday(parts) {
  return parts && ["Mon", "Tue", "Wed", "Thu", "Fri"].includes(parts.weekday);
}

function congestionChargeable({at, isBankHoliday = false}) {
  const parts = dateParts(at);
  if (!parts) return false;
  if (isWeekday(parts)) return withinWindow(parts, 7, 18);
  return isBankHoliday || withinWindow(parts, 12, 18);
}

function tunnelPeak({at, direction}) {
  const parts = dateParts(at);
  const normalizedDirection = `${direction || ""}`.trim().toLowerCase();
  if (!isWeekday(parts)) return false;
  if (normalizedDirection === "northbound") return withinWindow(parts, 6, 10);
  if (normalizedDirection === "southbound") return withinWindow(parts, 16, 19);
  return false;
}

function chargeIsEffective(charge, at) {
  const timestamp = new Date(at || Date.now()).getTime();
  const from = new Date(charge.effectiveFrom).getTime();
  const until = charge.effectiveUntil ? new Date(charge.effectiveUntil).getTime() : Infinity;
  return Number.isFinite(timestamp) && timestamp >= from && timestamp < until;
}

function stableLiabilityKey({vehicleId, vehicleClass, date, chargeId}) {
  const owner = `${vehicleId || vehicleClass || "unknown_vehicle"}`.trim().toLowerCase();
  return `${owner}:${date}:${chargeId}`;
}

function liabilityRecord(liabilityState, key, amountPence) {
  if (!liabilityState) return {incurred: false, recoveredPence: 0};
  const record = liabilityState.liabilities && liabilityState.liabilities[key] || liabilityState[key];
  if (record && typeof record === "object") {
    return {
      incurred: record.incurred === true || integerPence(
          record.riderRecoveryPence || record.riderReimbursedPence,
      ) > 0,
      recoveredPence: Math.min(integerPence(amountPence), integerPence(
          record.recoveredPence || record.riderRecoveryPence ||
          record.riderRecoveredPence || record.riderReimbursedPence,
      )),
    };
  }
  if (record === true || Array.isArray(liabilityState.coveredKeys) && liabilityState.coveredKeys.includes(key)) {
    return {incurred: true, recoveredPence: amountPence};
  }
  return {incurred: false, recoveredPence: 0};
}

function dailyRecoveryAllocation({liabilityPence, customerFeePence, recoveredPence}) {
  const liability = integerPence(liabilityPence);
  const customerFee = integerPence(customerFeePence);
  const recoveredBefore = Math.min(liability, integerPence(recoveredPence));
  const riderRecovery = Math.min(customerFee, Math.max(0, liability - recoveredBefore));
  return {
    customerFeePence: customerFee,
    riderRecoveryPence: riderRecovery,
    recoveredBeforePence: recoveredBefore,
    recoveredAfterPence: recoveredBefore + riderRecovery,
    remainingRecoveryPence: Math.max(0, liability - recoveredBefore - riderRecovery),
    circumRevenuePence: Math.max(0, customerFee - riderRecovery),
  };
}

function baseCharge({charge, chargeId, type, at, vehicleClass, amountPence, liabilityKey = null, status = "applicable"}) {
  return {
    chargeId,
    authority: charge.authority,
    type,
    amountPence: integerPence(amountPence),
    amount: moneyFromPence(amountPence),
    vehicleClass,
    at: at ? new Date(at).toISOString() : null,
    liabilityKey,
    status,
    settlementTreatment: charge.settlementTreatment,
    policyVersion: ROAD_CHARGE_POLICY_VERSION,
    source: charge.source,
  };
}

function evaluateRoadCharges({
  routeFacts = null,
  selectedVehicle,
  vehicleProfile = {},
  vehicleId = null,
  at = new Date(),
  liabilityState = {},
  requireVehicleIdentity = false,
} = {}) {
  const vehicleClass = normalizeVehicle(selectedVehicle);
  const tariffClassification = vehicleTariffClassification({
    ...vehicleProfile,
    vehicleClass,
  });
  const charges = [];
  const facts = routeFacts && typeof routeFacts === "object" ? routeFacts : null;
  if (!facts || facts.authority !== "authoritative_route") {
    return summary({charges, routeKnown: false, reason: "authoritative_route_facts_unavailable"});
  }

  const crossings = Array.isArray(facts.crossings) ? facts.crossings : [];
  const seenCrossings = new Set();
  for (const crossing of crossings) {
    const chargeId = `${crossing.chargeId || ""}`.trim().toLowerCase();
    const charge = ROAD_CHARGE_POLICY.charges[chargeId];
    if (!charge || charge.type !== "route_toll" || !chargeIsEffective(charge, crossing.at || at)) continue;
    const count = Math.max(1, integerPence(crossing.count || 1));
    const crossingKey = `${chargeId}:${crossing.crossingId || crossing.direction || "unknown"}`;
    if (seenCrossings.has(crossingKey)) continue;
    seenCrossings.add(crossingKey);
    const peak = chargeId === "blackwall_silvertown" ? tunnelPeak(crossing) : false;
    const vanWeight = Number(vehicleProfile.grossVehicleWeightKg);
    const tariffUnknown = vehicleClass === "van" && (
      chargeId === "dartford_crossing" && tariffClassification === "unknown" ||
      chargeId === "blackwall_silvertown" && (!Number.isFinite(vanWeight) || vanWeight > 3500)
    );
    const vehicleRates = charge.ratesPence[vehicleClass];
    const unit = tariffUnknown ? 0 : chargeId === "blackwall_silvertown" && vehicleRates ?
      vehicleRates[peak ? "peak" : "offPeak"] :
      charge.ratesPence[tariffClassification] || 0;
    const classificationUnknown = tariffUnknown || vehicleClass === "unknown";
    charges.push(baseCharge({
      charge,
      chargeId,
      type: charge.type,
      at: crossing.at || at,
      vehicleClass,
      amountPence: unit * count,
      status: classificationUnknown ? "tariff_classification_unknown" :
        unit > 0 ? "applicable" : "exempt_or_zero_rate",
    }));
  }

  const zone = facts.congestionZone;
  if (zone && zone.entered === true) {
    const charge = ROAD_CHARGE_POLICY.charges.congestion_charge;
    const zoneAt = zone.at || at;
    const parts = dateParts(zoneAt);
    const key = stableLiabilityKey({
      vehicleId,
      vehicleClass,
      date: parts && parts.date || "unknown_date",
      chargeId: charge.id,
    });
    const eligibleVehicle = charge.applicableVehicles.includes(vehicleClass);
    const active = chargeIsEffective(charge, zoneAt) && congestionChargeable({
      at: zoneAt,
      isBankHoliday: zone.isBankHoliday === true,
    });
    const record = liabilityRecord(liabilityState, key, charge.amountPence);
    const allocation = dailyRecoveryAllocation({
      liabilityPence: charge.amountPence,
      customerFeePence: ROAD_CHARGE_POLICY.commercialPolicy.centralLondonFeePence,
      recoveredPence: record.recoveredPence,
    });
    if (eligibleVehicle && active && requireVehicleIdentity && !`${vehicleId || ""}`.trim()) {
      charges.push(baseCharge({
        charge,
        chargeId: charge.id,
        type: charge.type,
        at: zoneAt,
        vehicleClass,
        amountPence: 0,
        liabilityKey: null,
        status: "assigned_vehicle_identity_unknown",
      }));
    } else if (!eligibleVehicle || !active) {
      charges.push(baseCharge({
        charge,
        chargeId: charge.id,
        type: charge.type,
        at: zoneAt,
        vehicleClass,
        amountPence: 0,
        liabilityKey: key,
        status: eligibleVehicle ? "outside_charging_hours" : "vehicle_not_applicable",
      }));
    } else if (record.incurred && allocation.remainingRecoveryPence === 0) {
      charges.push({
        ...baseCharge({
          charge,
          chargeId: charge.id,
          type: charge.type,
          at: zoneAt,
          vehicleClass,
          amountPence: charge.amountPence,
          liabilityKey: key,
          status: "daily_liability_recovered",
        }),
        customerContributionPence: allocation.customerFeePence,
        customerContribution: moneyFromPence(allocation.customerFeePence),
        chargingDate: parts && parts.date || null,
        riderReimbursementPence: 0,
        recoveredBeforePence: allocation.recoveredBeforePence,
        recoveredAfterPence: allocation.recoveredAfterPence,
      });
    } else {
      charges.push({
        ...baseCharge({
          charge,
          chargeId: charge.id,
          type: charge.type,
          at: zoneAt,
          vehicleClass,
          amountPence: charge.amountPence,
          liabilityKey: key,
          status: record.incurred ? "daily_liability_recovering" : "new_daily_liability",
        }),
        customerContributionPence: allocation.customerFeePence,
        customerContribution: moneyFromPence(allocation.customerFeePence),
        chargingDate: parts && parts.date || null,
        riderReimbursementPence: allocation.riderRecoveryPence,
        recoveredBeforePence: allocation.recoveredBeforePence,
        recoveredAfterPence: allocation.recoveredAfterPence,
        remainingRecoveryPence: allocation.remainingRecoveryPence,
      });
    }
  } else if (facts.congestionZone && facts.congestionZone.known === false) {
    charges.push({
      chargeId: "congestion_charge",
      authority: ROAD_CHARGE_POLICY.charges.congestion_charge.authority,
      type: "daily_zone_charge",
      amountPence: 0,
      amount: 0,
      vehicleClass,
      status: "unknown",
      policyVersion: ROAD_CHARGE_POLICY_VERSION,
      source: ROAD_CHARGE_POLICY.charges.congestion_charge.source,
    });
  }

  for (const complianceId of ["ulez", "lez"]) {
    if (facts[complianceId] && facts[complianceId].applicable === true) {
      const charge = ROAD_CHARGE_POLICY.charges[complianceId];
      charges.push(baseCharge({
        charge,
        chargeId: complianceId,
        type: charge.type,
        at: facts[complianceId].at || at,
        vehicleClass,
        amountPence: 0,
        status: facts[complianceId].compliant === true ? "compliant" : "compliance_audit_required",
      }));
    }
  }
  return summary({charges, routeKnown: true, reason: null});
}

function summary({charges, routeKnown, reason}) {
  const enriched = charges.map((charge) => {
    const actual = integerPence(charge.amountPence);
    const customer = charge.customerContributionPence != null ?
      integerPence(charge.customerContributionPence) : charge.type === "route_toll" ? actual : 0;
    const reimbursement = charge.riderReimbursementPence != null ?
      integerPence(charge.riderReimbursementPence) :
      charge.type === "route_toll" || charge.type === "daily_zone_charge" ? actual : 0;
    return {
      ...charge,
      customerContributionPence: customer,
      customerContribution: moneyFromPence(customer),
      riderReimbursementPence: reimbursement,
      riderReimbursement: moneyFromPence(reimbursement),
      circumContributionPence: 0,
      circumContribution: 0,
      circumRevenuePence: Math.max(0, customer - reimbursement),
      circumRevenue: moneyFromPence(Math.max(0, customer - reimbursement)),
    };
  });
  const sum = (field) => enriched.reduce((total, charge) => total + integerPence(charge[field]), 0);
  return {
    policyVersion: ROAD_CHARGE_POLICY_VERSION,
    routeKnown,
    reason,
    charges: enriched,
    customerContributionPence: sum("customerContributionPence"),
    customerContribution: moneyFromPence(sum("customerContributionPence")),
    riderReimbursementPence: sum("riderReimbursementPence"),
    riderReimbursement: moneyFromPence(sum("riderReimbursementPence")),
    circumContributionPence: sum("circumContributionPence"),
    circumContribution: moneyFromPence(sum("circumContributionPence")),
    circumRevenuePence: sum("circumRevenuePence"),
    circumRevenue: moneyFromPence(sum("circumRevenuePence")),
    liabilityKeys: enriched.filter((charge) => charge.liabilityKey).map((charge) => charge.liabilityKey),
    authoritativePricingComplete: routeKnown && !enriched.some((charge) =>
      ["unknown", "tariff_classification_unknown", "assigned_vehicle_identity_unknown"].includes(charge.status)),
  };
}

function dispatchRoadChargeScore({routeFacts, rider, request, at} = {}) {
  const selectedVehicle = rider && (rider.vehicleType || rider.vehicleClass || rider.vehicle);
  const liabilityState = rider && rider.roadChargeLiabilityState || {};
  const result = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: selectedVehicle || request && (request.vehicleType || request.requiredVehicle),
    vehicleProfile: rider && (rider.vehicle || rider.vehicleDetails) || {},
    vehicleId: rider && (rider.vehicleId || rider.id),
    liabilityState,
    at,
  });
  return {
    incrementalPence: result.riderReimbursementPence,
    result,
  };
}

module.exports = {
  ROAD_CHARGE_POLICY_VERSION,
  CENTRAL_LONDON_FEE_PENCE,
  ROAD_CHARGE_POLICY,
  normalizeVehicle,
  vehicleTariffClassification,
  stableLiabilityKey,
  dailyRecoveryAllocation,
  evaluateRoadCharges,
  dispatchRoadChargeScore,
};
