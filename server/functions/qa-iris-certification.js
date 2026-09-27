/* eslint-disable max-len, require-jsdoc */
"use strict";

// Fixed, PII-free inputs only. This module is reachable solely through the
// private, allowlisted Auth + App Check QA harness.
const zlib = require("node:zlib");
const {classifyIris, customerSafeIris} = require("./iris-core");
const {buildPhotoAnalysis} = require("./iris-photo-analysis")._private;

const SCENARIOS = Object.freeze({
  small: {description: "book in padded envelope", declaredWeightText: "0.5 kg"},
  cake: {description: "birthday cake in box", declaredWeightText: "2 kg"},
  flowers: {description: "bouquet of flowers", declaredWeightText: "1 kg"},
  artwork: {description: "framed artwork", declaredWeightText: "8 kg"},
  suitcase: {description: "suitcase", declaredWeightText: "23 kg"},
  heavy: {description: "heavy furniture cabinet", declaredWeightText: "56 kg"},
  weed: {description: "weed", declaredWeightText: "1 kg"},
  pets: {description: "pet dog", declaredWeightText: "8 kg"},
  remains: {description: "human remains", declaredWeightText: "20 kg"},
  photo: {description: "sealed cardboard parcel box", declaredWeightText: "2 kg"},
});

function crc32(bytes) {
  let crc = -1;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const tag = Buffer.from(type, "ascii");
  const header = Buffer.alloc(4); header.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4); checksum.writeUInt32BE(crc32(Buffer.concat([tag, data])));
  return Buffer.concat([header, tag, data, checksum]);
}

function syntheticParcelPng() {
  const width = 128; const height = 128;
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 2;
  const raw = Buffer.alloc(height * (1 + width * 3));
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = y * (1 + width * 3) + 1 + x * 3;
      const box = x >= 18 && x < 110 && y >= 28 && y < 105;
      const seam = box && (x === 63 || x === 64 || y === 65);
      const edge = box && (x < 21 || x > 106 || y < 31 || y > 102);
      const color = !box ? [235, 235, 231] : seam ? [209, 190, 144] : edge ? [87, 57, 33] : [167, 115, 65];
      raw[offset] = color[0]; raw[offset + 1] = color[1]; raw[offset + 2] = color[2];
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
  ]);
}

function analyse({uid, scenario}) {
  const input = SCENARIOS[scenario];
  if (!input) throw new Error("Unsupported synthetic IRIS scenario.");
  const iris = customerSafeIris(classifyIris(input));
  if (scenario !== "photo") return {scenario, iris};
  const photo = buildPhotoAnalysis({uid, data: input, bytes: syntheticParcelPng(), contentType: "image/png"});
  return {scenario, iris, photo};
}

module.exports = {SCENARIOS, syntheticParcelPng, analyse};
