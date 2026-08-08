/* eslint-disable max-len, require-jsdoc */
"use strict";

const pence = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.round(number)) : 0;
};

const money = (value) => Math.round(pence(value) / 100) / 100;

const roadChargesFor = (delivery = {}) => {
  const breakdown = delivery.pricingBreakdown || {};
  const charges = delivery.roadCharges || breakdown.roadCharges;
  return charges && Array.isArray(charges.charges) ? charges.charges : [];
};

const effectId = (deliveryId, charge, role) =>
  `${deliveryId}:${charge.chargeId || charge.key || "road_charge"}:${role}`
      .replace(/[^a-zA-Z0-9:_-]/g, "_");

const dailyId = (charge, vehicleId, date) =>
  `${vehicleId || "unknown_vehicle"}:${date}:${charge.chargeId || "congestion_charge"}`
      .replace(/[^a-zA-Z0-9:_-]/g, "_");

function planRoadChargeSettlement({deliveryId, riderId, delivery = {}, assignedVehicle = {}, dailyState = {}} = {}) {
  const vehicleId = assignedVehicle.id || assignedVehicle.registration || delivery.assignedVehicleId || null;
  const vehicleClass = assignedVehicle.class || assignedVehicle.type || delivery.assignedVehicleClass || "unknown";
  const effects = [];
  const dailyUpdates = [];
  let reimbursementPence = 0;
  for (const charge of roadChargesFor(delivery)) {
    const type = `${charge.type || ""}`.toLowerCase();
    const amount = pence(charge.amountPence);
    const customer = pence(charge.customerContributionPence);
    if (type === "vehicle_compliance" || amount <= 0) continue;
    if (type === "daily_zone_charge") {
      const date = `${charge.chargingDate || ""}`.trim();
      if (!date || !vehicleId) continue;
      const id = dailyId(charge, vehicleId, date);
      const before = pence(dailyState[id] && dailyState[id].recoveredPence);
      const recovery = Math.min(customer, Math.max(0, amount - before));
      if (recovery <= 0 && customer <= 0) continue;
      effects.push({
        id: effectId(deliveryId, charge, "ccz_recovery"),
        role: "ccz_recovery",
        chargeId: charge.chargeId,
        type,
        deliveryId,
        riderId,
        vehicleId,
        vehicleClass,
        chargingDate: date,
        customerAmountPence: customer,
        reimbursementPence: recovery,
        circumRevenuePence: Math.max(0, customer - recovery),
      });
      dailyUpdates.push({id, charge, before, recovery, customer});
      reimbursementPence += recovery;
      continue;
    }
    const reimbursement = pence(charge.riderReimbursementPence || amount);
    if (reimbursement <= 0) continue;
    effects.push({
      id: effectId(deliveryId, charge, "crossing_reimbursement"),
      role: "crossing_reimbursement",
      chargeId: charge.chargeId,
      type,
      deliveryId,
      riderId,
      vehicleId,
      vehicleClass,
      customerAmountPence: customer,
      reimbursementPence: reimbursement,
      circumRevenuePence: Math.max(0, customer - reimbursement),
    });
    reimbursementPence += reimbursement;
  }
  return {effects, dailyUpdates, reimbursementPence, reimbursement: money(reimbursementPence)};
}

module.exports = {roadChargesFor, planRoadChargeSettlement, effectId, dailyId, pence};
