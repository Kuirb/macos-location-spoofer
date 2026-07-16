"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const zlib = require("node:zlib");
const spoofer = require("../location-spoofer.js");

const source = fs.readFileSync(path.join(__dirname, "..", "location-spoofer.js"), "utf8");

function runRuntime(globals) {
  const completed = [];
  const logs = [];
  const context = {
    ...globals,
    Uint8Array,
    ArrayBuffer,
    BigInt,
    console: { log: (value) => logs.push(String(value)) },
    $done: (value) => completed.push(value)
  };
  vm.runInNewContext(source, context, { filename: "location-spoofer.js" });
  assert.equal(completed.length, 1, "runtime must call $done exactly once");
  return { result: completed[0], logs };
}

const prepare = runRuntime({
  $request: {
    url: "https://gs-loc.apple.com/clls/wloc",
    headers: { "Accept-Encoding": "gzip", "X-Test": "preserved" }
  },
  $argument: "mode=prepare&debug=false"
});
assert.equal(prepare.result.headers["Accept-Encoding"], "identity");
assert.equal(prepare.result.headers["X-Test"], "preserved");
assert.deepEqual(prepare.logs, []);

function makeLocation(latitude, longitude) {
  return spoofer.concatBytes([
    spoofer.makeVarintField(1, spoofer.coordToInt(latitude)),
    spoofer.makeVarintField(2, spoofer.coordToInt(longitude))
  ]);
}

const wifiPayload = spoofer.makeLengthDelimitedField(
  2,
  spoofer.makeLengthDelimitedField(2, makeLocation(51.5074, -0.1278))
);
const originalResponse = spoofer.buildAppleWLocResponse(wifiPayload);
const compressed = new Uint8Array(zlib.gzipSync(Buffer.from(originalResponse)));
let persistentReads = 0;

const response = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: {
      "Content-Encoding": "gzip",
      "Content-Length": String(compressed.length),
      "Content-Type": "application/octet-stream",
      "X-Location-Spoofer-Target": "stale-value"
    },
    // Shadowrocket can expose both slots. bodyBytes intentionally remains the
    // stale compressed value after the script assigns a decoded body.
    body: compressed,
    bodyBytes: compressed
  },
  $argument: "mode=response&latitude=35.658581&longitude=139.745433&debug=false",
  $persistentStore: {
    read(name) {
      persistentReads += 1;
      return name === "configUrl" ? "https://stale.example/loc.json" : null;
    }
  },
  $utils: {
    ungzip(value) {
      return new Uint8Array(zlib.gunzipSync(Buffer.from(value)));
    }
  }
});

assert.ok(response.result.body instanceof Uint8Array);
assert.equal(response.result.headers["Content-Encoding"], undefined);
assert.equal(response.result.headers["Transfer-Encoding"], undefined);
assert.equal(response.result.headers["Content-Length"], String(response.result.body.length));
assert.equal(
  Object.keys(response.result.headers).some((name) =>
    name.toLowerCase().startsWith("x-location-spoofer-")
  ),
  false,
  "debug=false must remove location-spoofer diagnostic headers"
);
assert.deepEqual(response.logs, [], "debug=false must suppress diagnostic logs");
assert.equal(persistentReads, 0, "runtime must not read shared persistent-store arguments");

function locationFieldsFromBody(body) {
  const extracted = spoofer.extractAppleWLocPayload(body);
  const rootFields = spoofer.parseFields(extracted.payload);
  const wifi = spoofer.firstFieldByNumber(rootFields, 2);
  assert.ok(wifi, "rewritten response must retain a Wi-Fi record");
  const wifiFields = spoofer.parseFields(wifi.valueBytes);
  const location = spoofer.firstFieldByNumber(wifiFields, 2);
  assert.ok(location, "Wi-Fi record must contain a location");
  return spoofer.parseFields(location.valueBytes);
}

function signedValue(fields, number) {
  const item = spoofer.firstFieldByNumber(fields, number);
  assert.ok(item, `missing location field ${number}`);
  return BigInt.asIntN(64, spoofer.decodeVarint(item.valueBytes, 0).value);
}

const locationFields = locationFieldsFromBody(response.result.body);
assert.equal(signedValue(locationFields, 1), BigInt(spoofer.coordToInt(35.658581)));
assert.equal(signedValue(locationFields, 2), BigInt(spoofer.coordToInt(139.745433)));

let remoteRequests = 0;
const remoteConflict = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: { "Content-Type": "application/octet-stream" },
    body: originalResponse
  },
  $argument:
    "mode=response&latitude=35.658581&longitude=139.745433&debug=false&configUrl=https%3A%2F%2Fconfig.example%2Floc.json",
  $httpClient: {
    get(options, callback) {
      remoteRequests += 1;
      const body = JSON.stringify({ latitude: 1, longitude: 2, debug: true });
      callback(null, { status: 200 }, body);
      callback(null, { status: 200 }, body);
    }
  }
});
assert.equal(remoteRequests, 1);
assert.deepEqual(remoteConflict.logs, [], "explicit debug=false must override remote config");
const remoteConflictFields = locationFieldsFromBody(remoteConflict.result.body);
assert.equal(
  signedValue(remoteConflictFields, 1),
  BigInt(spoofer.coordToInt(35.658581)),
  "explicit latitude must override remote config"
);
assert.equal(
  signedValue(remoteConflictFields, 2),
  BigInt(spoofer.coordToInt(139.745433)),
  "explicit longitude must override remote config"
);

const cachedConfigUrl = "https://config.example/cached.json";
const cachedRefresh = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: { "Content-Type": "application/octet-stream" },
    body: originalResponse
  },
  $argument:
    "mode=response&latitude=35.658581&longitude=139.745433&debug=false&configUrl=" +
    encodeURIComponent(cachedConfigUrl),
  $persistentStore: {
    read(name) {
      if (name !== "location_spoofer_remote_cfg") {
        return null;
      }
      return JSON.stringify({
        url: cachedConfigUrl,
        data: { latitude: 1, longitude: 2 },
        ts: Date.now()
      });
    },
    write() {
      return true;
    }
  },
  $httpClient: {
    get() {
      throw new Error("sync transport failure");
    }
  }
});
assert.deepEqual(cachedRefresh.logs, [], "debug=false must suppress refresh diagnostics");
const cachedRefreshFields = locationFieldsFromBody(cachedRefresh.result.body);
assert.equal(
  signedValue(cachedRefreshFields, 1),
  BigInt(spoofer.coordToInt(35.658581)),
  "cached refresh failure must retain explicit latitude"
);
assert.equal(
  signedValue(cachedRefreshFields, 2),
  BigInt(spoofer.coordToInt(139.745433)),
  "cached refresh failure must retain explicit longitude"
);

function assertInvalidConfigFailsOpen(argument) {
  const invalid = runRuntime({
    $environment: { product: "Shadowrocket" },
    $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
    $response: {
      status: 200,
      headers: { "Content-Type": "application/octet-stream" },
      body: originalResponse
    },
    $argument: argument
  });
  assert.equal(Object.keys(invalid.result).length, 0, "invalid config must fail open");
}

assertInvalidConfigFailsOpen("mode=response&latitude=999&longitude=0&debug=false");
assertInvalidConfigFailsOpen("mode=response&config=%7Bbad&debug=false");

console.log("Runtime test passed: rewrite, privacy, precedence, and fail-open behavior work.");
