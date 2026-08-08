/* eslint-disable max-len, require-jsdoc */
"use strict";

const CCZ_BOUNDARY = require("./road-charge-ccz-boundary.json");

const GEOGRAPHY_VERSION = "2026-08-circum-road-geography-v2";

const OFFICIAL_CCZ_POLYGONS = Object.freeze(CCZ_BOUNDARY.features
    .filter((feature) => feature && feature.geometry && feature.geometry.type === "Polygon")
    .map((feature) => feature.geometry.coordinates[0]));

// TfL CC_Boundary_v8, converted from the published EPSG:27700 shapefile to
// WGS84 and simplified for deterministic server-side point-in-polygon checks.
const CCZ_POLYGON = Object.freeze([[-0.106331, 51.531808], [-0.114031, 51.531288], [-0.115699, 51.529366], [-0.119614, 51.528552], [-0.120834, 51.530082], [-0.122714, 51.530448], [-0.129471, 51.527647], [-0.135701, 51.525465], [-0.134825, 51.52459], [-0.137364, 51.523555], [-0.138145, 51.524679], [-0.14719, 51.52285], [-0.148006, 51.523358], [-0.157323, 51.522025], [-0.156786, 51.520859], [-0.15921, 51.520443], [-0.15971, 51.521554], [-0.164753, 51.52071], [-0.167099, 51.518077], [-0.160023, 51.513364], [-0.158106, 51.513292], [-0.15656, 51.510374], [-0.150966, 51.505695], [-0.150772, 51.503461], [-0.149503, 51.502512], [-0.151156, 51.501827], [-0.148275, 51.499836], [-0.147045, 51.498405], [-0.142421, 51.497894], [-0.141863, 51.495388], [-0.140625, 51.49417], [-0.12961, 51.488857], [-0.125509, 51.487035], [-0.121359, 51.486267], [-0.113147, 51.487126], [-0.111127, 51.489037], [-0.10632, 51.490743], [-0.103649, 51.491332], [-0.101014, 51.493162], [-0.100833, 51.495726], [-0.094587, 51.494276], [-0.086756, 51.494378], [-0.084783, 51.494875], [-0.082641, 51.496463], [-0.079844, 51.497863], [-0.077498, 51.502916], [-0.074484, 51.5071], [-0.074047, 51.509188], [-0.074942, 51.511329], [-0.073173, 51.511339], [-0.073906, 51.51466], [-0.072161, 51.515423], [-0.074651, 51.518391], [-0.074694, 51.520304], [-0.077506, 51.522678], [-0.083539, 51.525934], [-0.08713, 51.52568], [-0.089062, 51.527439], [-0.101791, 51.530749], [-0.102652, 51.529778], [-0.106331, 51.531808]]);

const CROSSINGS = Object.freeze([
  Object.freeze({chargeId: "blackwall_silvertown", crossingId: "blackwall", southPortal: [-0.0085, 51.497], northPortal: [-0.0066, 51.5095], radiusMeters: 550}),
  Object.freeze({chargeId: "blackwall_silvertown", crossingId: "silvertown", southPortal: [0.0058, 51.4992], northPortal: [0.0148, 51.5051], radiusMeters: 450}),
  Object.freeze({chargeId: "dartford_crossing", crossingId: "dartford", southPortal: [0.2575, 51.464], northPortal: [0.2585, 51.486], radiusMeters: 850}),
]);

const GEOGRAPHY_POLICY = Object.freeze({
  version: GEOGRAPHY_VERSION,
  effectiveFrom: "2026-08-01T00:00:00Z",
  source: "TfL CC_Boundary_v8 and CIRCUM verified crossing corridors",
  sourceUrl: "https://s3-eu-west-1.amazonaws.com/roads.data.tfl.gov.uk/boundaries/CC_Boundary_v8_20190526_tab_shape.zip",
  verifiedAt: "2026-08-08T00:00:00Z",
  cczPolygon: CCZ_POLYGON,
  cczPolygons: OFFICIAL_CCZ_POLYGONS,
  crossings: CROSSINGS,
});

function pointInPolygon(point, polygon) {
  const [x, y] = point;
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

function distanceMeters(a, b) {
  const rad = (value) => value * Math.PI / 180;
  const lat1 = rad(a[1]);
  const lat2 = rad(b[1]);
  const dLat = lat2 - lat1;
  const dLon = rad(b[0] - a[0]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function deriveCircumRouteFacts(points, {at = new Date(), googleTollSignal = null} = {}) {
  if (!Array.isArray(points) || points.length < 2 || points.some((point) =>
    !Array.isArray(point) || !Number.isFinite(point[0]) || !Number.isFinite(point[1]))) {
    return {status: "ROUTE_UNAVAILABLE", known: false, geographyVersion: GEOGRAPHY_VERSION};
  }
  const entered = points.some((point) =>
    OFFICIAL_CCZ_POLYGONS.some((polygon) => pointInPolygon(point, polygon)));
  const crossings = [];
  for (const definition of CROSSINGS) {
    const nearest = (portal) => points.reduce((best, point, index) => {
      const distance = distanceMeters(point, portal);
      return distance < best.distance ? {distance, index} : best;
    }, {distance: Infinity, index: -1});
    const south = nearest(definition.southPortal);
    const north = nearest(definition.northPortal);
    if (south.distance <= definition.radiusMeters && north.distance <= definition.radiusMeters) {
      crossings.push({
        chargeId: definition.chargeId,
        crossingId: definition.crossingId,
        direction: south.index < north.index ? "northbound" : "southbound",
        count: 1,
        at: new Date(at).toISOString(),
      });
    }
  }
  const circumDetectedCharge = entered || crossings.length > 0;
  const googleReportedToll = googleTollSignal === true;
  return {
    authority: "authoritative_route",
    financialAuthority: "circum_road_charge_engine",
    status: circumDetectedCharge ? "CHARGE_CONFIRMED" : "NO_CHARGE",
    known: true,
    geographyVersion: GEOGRAPHY_VERSION,
    congestionZone: {entered, known: true, at: new Date(at).toISOString()},
    crossings,
    corroboration: {
      googleReportedToll,
      disagreement: googleTollSignal != null && googleReportedToll !== circumDetectedCharge,
    },
  };
}

module.exports = {
  GEOGRAPHY_VERSION,
  GEOGRAPHY_POLICY,
  pointInPolygon,
  distanceMeters,
  deriveCircumRouteFacts,
};

