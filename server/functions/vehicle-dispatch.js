/* eslint-disable max-len, require-jsdoc */
const VEHICLE_ORDER = ["motorbike", "car", "van"];

function normalizeText(value) {
  return String(value || "").trim().toLowerCase().replace(/[_-]+/g, " ");
}

function normalizeVehicleClass(value, fallback = "any") {
  const text = normalizeText(value);
  if (!text) return fallback;
  if (["any", "all", "none", "no preference"].includes(text)) return "any";
  if (/(luton|lorry|box truck|large van|van|small van|transit|sprinter)/.test(text)) return "van";
  if (/(estate|suv|4x4|estate suv|estate car|car|driver|sedan|saloon|hatchback)/.test(text)) return "car";
  if (/(bike|bicycle|cycle|e bike|ebike|electric bike|motorbike|motorcycle|scooter|moped)/.test(text)) return "motorbike";
  return fallback;
}

function normalizeRiderVehicle(rider = {}) {
  const vehicle = rider.vehicle || rider.vehicleDetails || {};
  return normalizeVehicleClass(
      rider.normalizedVehicleClass ||
      rider.vehicleClass ||
      rider.vehicleType ||
      rider.typeOfVehicle ||
      rider.type ||
      vehicle.class ||
      vehicle.type ||
      rider.vehicleMakeModel,
      null,
  );
}

function pickRequiredVehicle(request = {}) {
  const iris = request.irisPrivate || request.iris || {};
  const internal = iris.internal || {};
  const matching = internal.riderMatching || request.matchingRules || {};
  const candidates = [
    request.vehicleRequirement,
    request.requiredVehicle,
    request.minimumVehicleClass,
    request.irisRecommendedVehicle,
    request.vehicleType,
    matching.minimumVehicleClass,
    matching.vehicleRequirement,
    matching.requiredVehicle,
    matching.vehicleRequired,
    matching.preferredVehicle,
    request.matchingRequirements && request.matchingRequirements.vehicleRequirement,
    request.matchingRequirements && request.matchingRequirements.requiredVehicle,
    iris.vehicleRequirement,
    iris.requiredVehicle,
    iris.minimumVehicleClass,
    iris.recommendedVehicle,
    iris.vehicleType,
    internal.vehicleRequirement,
    internal.requiredVehicle,
    internal.minimumVehicleClass,
  ];
  for (const candidate of candidates) {
    const normalized = normalizeVehicleClass(candidate, null);
    if (normalized) return normalized;
  }
  return "any";
}

function vehicleCanHandle(riderVehicle, requiredVehicle) {
  const riderClass = normalizeVehicleClass(riderVehicle, null);
  const requiredClass = normalizeVehicleClass(requiredVehicle, "any");
  if (requiredClass === "any") return riderClass != null;
  if (!riderClass) return false;
  const riderRank = VEHICLE_ORDER.indexOf(riderClass);
  const requiredRank = VEHICLE_ORDER.indexOf(requiredClass);
  return riderRank >= requiredRank && requiredRank >= 0;
}

function riderVehicleMatchesRequest(rider, request) {
  return vehicleCanHandle(normalizeRiderVehicle(rider), pickRequiredVehicle(request));
}

module.exports = {
  normalizeVehicleClass,
  normalizeRiderVehicle,
  pickRequiredVehicle,
  vehicleCanHandle,
  riderVehicleMatchesRequest,
};
