const cleanText = (value, fallback = "") => {
  if (value === undefined || value === null) return fallback;
  const text = `${value}`.trim();
  return text.length > 0 ? text : fallback;
};

const buildRiderVehicleSnapshot = (rider = {}) => {
  const vehicle = rider.vehicle || rider.vehicleDetails || {};
  const snapshot = {
    type: cleanText(vehicle.type || rider.vehicleType || rider.typeOfVehicle),
    manufacturer: cleanText(vehicle.manufacturer || vehicle.make),
    model: cleanText(vehicle.model),
    colour: cleanText(vehicle.colour || vehicle.color),
    registration: cleanText(
        vehicle.registration || rider.vehicleRegistration || rider.plateNumber),
    capacity: cleanText(vehicle.capacity),
    insurance: cleanText(vehicle.insurance),
    mot: cleanText(vehicle.mot || vehicle.MOT),
    verificationStatus: cleanText(vehicle.verificationStatus || vehicle.status),
  };
  return Object.fromEntries(
      Object.entries(snapshot).filter(([, value]) => value !== ""));
};

module.exports = {
  buildRiderVehicleSnapshot,
};
