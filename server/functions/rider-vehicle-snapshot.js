const cleanText = (value, fallback = "") => {
  if (value === undefined || value === null) return fallback;
  const text = `${value}`.trim();
  return text.length > 0 ? text : fallback;
};

const canonicalVehicleType = (value) => {
  const raw = cleanText(value);
  const normalized = raw.toLowerCase().replace(/[_-]+/g, " ");
  if (!normalized) return "";
  if (/(van|luton|lorry|box truck|transit|sprinter)/.test(normalized)) {
    return "Van";
  }
  if (/(car|estate|suv|4x4|sedan|saloon|hatchback)/.test(normalized)) {
    return "Car";
  }
  if (
    /(bike|bicycle|cycle|motorcycle|motorbike|moped|scooter)/
        .test(normalized)
  ) {
    return "Motorbike";
  }
  return raw;
};

const buildRiderVehicleSnapshot = (rider = {}) => {
  const vehicle = rider.vehicle || rider.vehicleDetails || {};
  const axleCount = Number(vehicle.axleCount || rider.vehicleAxleCount);
  const grossVehicleWeightKg = Number(
      vehicle.grossVehicleWeightKg || vehicle.grossWeightKg || rider.grossVehicleWeightKg,
  );
  const snapshot = {
    id: cleanText(vehicle.id || vehicle.vehicleId || rider.activeVehicleId || rider.vehicleId),
    type: canonicalVehicleType(
        vehicle.type || rider.vehicleType || rider.typeOfVehicle,
    ),
    manufacturer: cleanText(vehicle.manufacturer || vehicle.make),
    model: cleanText(vehicle.model),
    colour: cleanText(vehicle.colour || vehicle.color),
    registration: cleanText(
        vehicle.registration || rider.vehicleRegistration || rider.plateNumber),
    capacity: cleanText(vehicle.capacity),
    insurance: cleanText(vehicle.insurance),
    mot: cleanText(vehicle.mot || vehicle.MOT),
    verificationStatus: cleanText(vehicle.verificationStatus || vehicle.status),
    axleCount: Number.isInteger(axleCount) && axleCount > 0 ? axleCount : undefined,
    grossVehicleWeightKg: Number.isFinite(grossVehicleWeightKg) && grossVehicleWeightKg > 0 ?
      grossVehicleWeightKg : undefined,
    emissionsClass: cleanText(vehicle.emissionsClass || vehicle.euroClass),
    ulezCompliant: typeof vehicle.ulezCompliant === "boolean" ? vehicle.ulezCompliant : undefined,
    lezCompliant: typeof vehicle.lezCompliant === "boolean" ? vehicle.lezCompliant : undefined,
  };
  return Object.fromEntries(
      Object.entries(snapshot).filter(([, value]) => value !== "" && value !== undefined));
};

module.exports = {
  buildRiderVehicleSnapshot,
};
