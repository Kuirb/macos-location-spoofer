"use strict";

const assert = require("node:assert/strict");
const spoofer = require("../location-spoofer.js");

function field(number, payload) {
  return spoofer.makeLengthDelimitedField(number, payload);
}

function originalLocation(latitude, longitude) {
  return spoofer.concatBytes([
    spoofer.makeVarintField(1, spoofer.coordToInt(latitude)),
    spoofer.makeVarintField(2, spoofer.coordToInt(longitude)),
    spoofer.makeVarintField(3, 65),
    spoofer.makeVarintField(5, 10)
  ]);
}

function signedField(fields, number) {
  const match = spoofer.firstFieldByNumber(fields, number);
  assert.ok(match, `missing field ${number}`);
  return BigInt.asIntN(64, spoofer.decodeVarint(match.valueBytes, 0).value);
}

function coordinates(locationPayload) {
  const fields = spoofer.parseFields(locationPayload);
  return {
    fields,
    latitude: Number(signedField(fields, 1)) / 100000000,
    longitude: Number(signedField(fields, 2)) / 100000000,
    latitudeInteger: signedField(fields, 1),
    longitudeInteger: signedField(fields, 2)
  };
}

const wifi = field(2, spoofer.concatBytes([
  spoofer.makeVarintField(1, 1234),
  field(2, originalLocation(51.5074, -0.1278))
]));
const cell = field(22, spoofer.concatBytes([
  spoofer.makeVarintField(1, 5678),
  field(5, originalLocation(48.8566, 2.3522))
]));
const alternateCell = field(24, spoofer.concatBytes([
  spoofer.makeVarintField(1, 9012),
  field(5, originalLocation(40.7128, -74.006))
]));
const root = spoofer.concatBytes([wifi, cell, alternateCell]);
const response = spoofer.buildAppleWLocResponse(root);

const target = spoofer.normalizeConfig({
  latitude: 37.3349,
  longitude: -122.00902,
  altitude: 56,
  horizontalAccuracy: 15,
  verticalAccuracy: 25
});
assert.equal(spoofer.normalizeConfig({ debug: "false" }).debug, false);
assert.equal(spoofer.normalizeConfig({ debug: "true" }).debug, true);
const result = spoofer.spoofAppleResponse(response, target);

assert.equal(result.wifiCount, 1);
assert.equal(result.cellCount, 2);
assert.equal(result.kind, "synthetic");

const patchedRoot = spoofer.parseFields(result.payload);
const patchedWifi = spoofer.parseFields(spoofer.firstFieldByNumber(patchedRoot, 2).valueBytes);
const patchedCell = spoofer.parseFields(spoofer.firstFieldByNumber(patchedRoot, 22).valueBytes);
const patchedAlternateCell = spoofer.parseFields(spoofer.firstFieldByNumber(patchedRoot, 24).valueBytes);
const wifiCoordinates = coordinates(spoofer.firstFieldByNumber(patchedWifi, 2).valueBytes);
const cellCoordinates = coordinates(spoofer.firstFieldByNumber(patchedCell, 5).valueBytes);
const alternateCellCoordinates = coordinates(
  spoofer.firstFieldByNumber(patchedAlternateCell, 5).valueBytes
);

function assertCoordinate(actual, expected, label) {
  assert.equal(
    actual.latitudeInteger,
    BigInt(spoofer.coordToInt(expected.latitude)),
    `${label} latitude integer was not rewritten`
  );
  assert.equal(
    actual.longitudeInteger,
    BigInt(spoofer.coordToInt(expected.longitude)),
    `${label} longitude integer was not rewritten`
  );
}

assertCoordinate(wifiCoordinates, { latitude: 37.3349, longitude: -122.00902 }, "Wi-Fi");
assertCoordinate(cellCoordinates, { latitude: 37.3349, longitude: -122.00902 }, "cell");
assertCoordinate(
  alternateCellCoordinates,
  { latitude: 37.3349, longitude: -122.00902 },
  "alternate cell"
);

function assertLocationMetadata(actual, label) {
  assert.equal(signedField(actual.fields, 3), 15n, `${label} horizontal accuracy was not rewritten`);
  assert.equal(signedField(actual.fields, 4), 3n, `${label} field 4 was not rewritten`);
  assert.equal(signedField(actual.fields, 5), 56n, `${label} altitude was not rewritten`);
  assert.equal(signedField(actual.fields, 6), 25n, `${label} vertical accuracy was not rewritten`);
  assert.equal(signedField(actual.fields, 11), 63n, `${label} motion type was not rewritten`);
  assert.equal(signedField(actual.fields, 12), 467n, `${label} motion confidence was not rewritten`);
}

assertLocationMetadata(wifiCoordinates, "Wi-Fi");
assertLocationMetadata(cellCoordinates, "cell");
assertLocationMetadata(alternateCellCoordinates, "alternate cell");

const trailer = Uint8Array.from([0xaa, 0xbb, 0xcc]);
const livePrefix = Uint8Array.from([0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00]);
const prefixedInput = spoofer.concatBytes([
  spoofer.buildAppleWLocResponse(root, livePrefix),
  trailer
]);
const prefixedResult = spoofer.spoofAppleResponse(prefixedInput, target);
const prefixedExtraction = spoofer.extractAppleWLocPayload(prefixedResult.response);
assert.equal(prefixedResult.kind, "synthetic");
assert.equal(prefixedExtraction.kind, "synthetic");
assert.deepEqual(prefixedExtraction.prefix, livePrefix, "prefixed envelope changed");
assert.deepEqual(prefixedExtraction.suffix, trailer, "prefixed trailer was not preserved");

const markerPrefix = Uint8Array.from([0xde, 0xad]);
const markerInput = spoofer.concatBytes([
  markerPrefix,
  spoofer.APPLE_WLOC_MARKER,
  spoofer.writeUInt16BE(root.length),
  root,
  trailer
]);
const markerResult = spoofer.spoofAppleResponse(markerInput, target);
const markerExtraction = spoofer.extractAppleWLocPayload(markerResult.response);
assert.equal(markerResult.kind, "marker");
assert.equal(markerExtraction.kind, "marker");
assert.deepEqual(markerExtraction.prefix, markerPrefix, "marker prefix changed");
assert.deepEqual(
  markerExtraction.markerAndLen.slice(0, spoofer.APPLE_WLOC_MARKER.length),
  spoofer.APPLE_WLOC_MARKER,
  "marker bytes changed"
);
assert.equal(
  spoofer.readUInt16BE(markerExtraction.markerAndLen, spoofer.APPLE_WLOC_MARKER.length),
  markerResult.payload.length,
  "marker payload length was not updated"
);
assert.deepEqual(markerExtraction.suffix, trailer, "marker trailer was not preserved");

const arpcInput = spoofer.serializeArpc({
  version: 1,
  locale: "en_US",
  appIdentifier: "com.apple.locationd",
  osVersion: "27.0",
  functionId: 1,
  payload: root,
  suffix: trailer
});
const arpcResult = spoofer.spoofAppleResponse(arpcInput, target);
const parsedArpcResult = spoofer.parseArpc(arpcResult.response);
assert.equal(arpcResult.kind, "arpc");
assert.equal(parsedArpcResult.version, 1);
assert.equal(parsedArpcResult.locale, "en_US");
assert.equal(parsedArpcResult.appIdentifier, "com.apple.locationd");
assert.equal(parsedArpcResult.osVersion, "27.0");
assert.equal(parsedArpcResult.functionId, 1);
assert.deepEqual(parsedArpcResult.payload, arpcResult.payload, "ARPC payload was not updated");
assert.deepEqual(parsedArpcResult.suffix, trailer, "ARPC trailer was not preserved");

const bareResult = spoofer.spoofAppleResponse(root, target);
assert.equal(bareResult.kind, "bare");
assert.deepEqual(bareResult.response, bareResult.payload, "bare protobuf gained an envelope");
assert.equal(spoofer.extractAppleWLocPayload(bareResult.response).kind, "bare");

const unsupported = Uint8Array.from(Buffer.from("000100000001000000021801", "hex"));
const unsupportedResult = spoofer.spoofAppleResponse(unsupported, target);
assert.equal(unsupportedResult.wifiCount + unsupportedResult.cellCount, 0);
assert.deepEqual(unsupportedResult.response, unsupported, "unsupported responses must remain byte-for-byte unchanged");

const emptyWifiRecord = Uint8Array.from([0x12, 0x00]);
const emptyWifiResult = spoofer.spoofAppleResponse(emptyWifiRecord, target);
assert.equal(emptyWifiResult.wifiCount + emptyWifiResult.cellCount, 0);
assert.deepEqual(emptyWifiResult.response, emptyWifiRecord, "records without a location payload must remain unchanged");

const malformedWifiRecord = Uint8Array.from([0x12, 0x01, 0x00]);
const malformedWifiResult = spoofer.spoofAppleResponse(malformedWifiRecord, target);
assert.equal(malformedWifiResult.wifiCount + malformedWifiResult.cellCount, 0);
assert.deepEqual(malformedWifiResult.response, malformedWifiRecord, "malformed records must remain unchanged");

const mixedRoot = spoofer.concatBytes([malformedWifiRecord, wifi]);
const mixedResult = spoofer.spoofAppleResponse(mixedRoot, target);
assert.equal(mixedResult.wifiCount, 1, "valid records after malformed ones must still be rewritten");
assert.deepEqual(
  spoofer.parseFields(mixedResult.response)[0].raw,
  malformedWifiRecord,
  "malformed records must be preserved while later valid records are rewritten"
);

const overlongVarintLocation = Uint8Array.from([
  0x08,
  0x80, 0x80, 0x80, 0x80, 0x80,
  0x80, 0x80, 0x80, 0x80, 0x80,
  0x00
]);
const overlongWifiRecord = spoofer.concatBytes([
  Uint8Array.from([0x12, overlongVarintLocation.length]),
  overlongVarintLocation
]);
const overlongWifiResponse = spoofer.concatBytes([
  Uint8Array.from([0x12, overlongWifiRecord.length]),
  overlongWifiRecord
]);
const overlongWifiResult = spoofer.spoofAppleResponse(overlongWifiResponse, target);
assert.equal(overlongWifiResult.wifiCount + overlongWifiResult.cellCount, 0);
assert.deepEqual(overlongWifiResult.response, overlongWifiResponse, "overlong varint records must remain unchanged");

const mixedOverlongRoot = spoofer.concatBytes([overlongWifiResponse, wifi]);
const mixedOverlongResult = spoofer.spoofAppleResponse(mixedOverlongRoot, target);
assert.equal(mixedOverlongResult.wifiCount, 1, "valid records after overlong varints must still be rewritten");
assert.deepEqual(
  spoofer.parseFields(mixedOverlongResult.response)[0].raw,
  overlongWifiResponse,
  "overlong varint records must be preserved while later valid records are rewritten"
);

assert.throws(
  () => spoofer.normalizeConfig({ latitude: 91, longitude: 0 }),
  /invalid latitude/
);
assert.throws(
  () => spoofer.normalizeConfig({ latitude: 0, longitude: 181 }),
  /invalid longitude/
);
assert.throws(
  () => spoofer.normalizeConfig({ altitude: 20001 }),
  /invalid altitude/
);
assert.throws(
  () => spoofer.normalizeConfig({ horizontalAccuracy: 0 }),
  /invalid horizontal accuracy/
);
assert.equal(spoofer.normalizeConfig({ horizontalAccuracy: 1 }).horizontalAccuracy, 1);
assert.equal(spoofer.normalizeConfig({ horizontalAccuracy: 1000000 }).horizontalAccuracy, 1000000);
assert.throws(
  () => spoofer.normalizeConfig({ horizontalAccuracy: 1000001 }),
  /invalid horizontal accuracy/
);
assert.throws(
  () => spoofer.normalizeConfig({ verticalAccuracy: 0 }),
  /invalid vertical accuracy/
);
assert.equal(spoofer.normalizeConfig({ verticalAccuracy: 1 }).verticalAccuracy, 1);
assert.equal(spoofer.normalizeConfig({ verticalAccuracy: 1000000 }).verticalAccuracy, 1000000);
assert.throws(
  () => spoofer.normalizeConfig({ verticalAccuracy: 1000001 }),
  /invalid vertical accuracy/
);
assert.throws(
  () => spoofer.normalizeConfig({ horizontalAccuracy: 1.5 }),
  /invalid horizontal accuracy/
);
assert.throws(
  () => spoofer.normalizeConfig({ verticalAccuracy: 1.5 }),
  /invalid vertical accuracy/
);
assert.throws(
  () => spoofer.normalizeConfig({ altitude: 56.5 }),
  /invalid altitude/
);
assert.throws(
  () => spoofer.normalizeConfig({ unknownValue4: 3.5 }),
  /invalid location field 4/
);
assert.throws(
  () => spoofer.normalizeConfig({ motionActivityType: 63.5 }),
  /invalid motion metadata/
);
assert.throws(
  () => spoofer.normalizeConfig({ motionActivityConfidence: 467.5 }),
  /invalid motion metadata/
);
assert.throws(
  () => spoofer.encodeVarintSignedInt64(1000000000000000000000000000000),
  /safe integer|signed int64/
);
assert.throws(
  () => spoofer.encodeVarintSignedInt64(1n << 63n),
  /signed int64/
);
assert.throws(
  () => spoofer.encodeVarintSignedInt64(-(1n << 63n) - 1n),
  /signed int64/
);
assert.deepEqual(
  spoofer.encodeVarintSignedInt64(-(1n << 63n)),
  Uint8Array.from([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01])
);
assert.deepEqual(
  spoofer.encodeVarintSignedInt64((1n << 63n) - 1n),
  Uint8Array.from([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f])
);

console.log("Protocol test passed: location fields and all supported envelopes were preserved.");
