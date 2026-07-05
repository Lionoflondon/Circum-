const test = require("node:test");
const assert = require("node:assert/strict");
const {
  nominatimSearchUrl,
  sanitizeQuery,
  searchFreeUkAddresses,
} = require("./free-address-core");

test("sanitizes address queries", () => {
  assert.equal(sanitizeQuery("  Harley   Street   London  "), "Harley Street London");
  assert.equal(sanitizeQuery("ab"), "ab");
});

test("builds a free UK-only Nominatim search URL", () => {
  const url = nominatimSearchUrl("Harley Street London");
  assert.match(url, /nominatim\.openstreetmap\.org\/search/);
  assert.match(url, /countrycodes=gb/);
  assert.match(url, /addressdetails=1/);
  assert.doesNotMatch(url, /maps\.googleapis\.com/);
});

test("maps free address search results into Circum address suggestions", async () => {
  const fetchImpl = async (url) => {
    assert.match(url, /nominatim\.openstreetmap\.org/);
    return {
      ok: true,
      async json() {
        return [{
          osm_type: "way",
          osm_id: 502230296,
          lat: "51.5181037",
          lon: "-0.1465558",
          importance: 0.05,
          display_name: "Harley Street, Marylebone, London, W1G 9QU, United Kingdom",
          address: {
            road: "Harley Street",
            city: "City of Westminster",
            postcode: "W1G 9QU",
            country: "United Kingdom",
          },
        }];
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Harley Street London",
    fetchImpl,
  });
  assert.equal(result.status, "OK");
  assert.equal(result.attribution, "OpenStreetMap");
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].provider, "openstreetmap_nominatim");
  assert.equal(result.results[0].components.postcode, "W1G 9QU");
  assert.equal(result.results[0].lat, 51.5181037);
});
