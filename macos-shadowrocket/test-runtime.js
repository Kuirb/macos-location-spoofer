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

const privateDiagnostics = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: {
    url: "https://gs-loc.apple.com/clls/wloc?query=SENSITIVE_QUERY#SENSITIVE_QUERY",
    headers: { "Proxy-Authorization": "SENSITIVE_CONFIG_TOKEN" }
  },
  $response: {
    status: 200,
    headers: {
      "content-type": "text/plain",
      "content-length": String(originalResponse.length),
      "content-encoding": "identity",
      "transfer-encoding": "chunked",
      Authorization: "SENSITIVE_CONFIG_TOKEN",
      "pRoXy-AuThOrIzAtIoN": "SENSITIVE_CONFIG_TOKEN",
      Cookie: "SENSITIVE_COOKIE",
      "Set-Cookie": "SENSITIVE_COOKIE",
      "X-Location-Spoofer-Target": "35.658581,139.745433",
      "X-Nested": { authorization: "SENSITIVE_CONFIG_TOKEN", cookie: "SENSITIVE_COOKIE" },
      "X-Array": ["SENSITIVE_CONFIG_TOKEN", { Cookie: "SENSITIVE_COOKIE" }]
    },
    body: originalResponse
  },
  $argument:
    "mode=response&latitude=35.658581&longitude=139.745433&debug=true&dumpRaw=true&dumpHeaders=true&configUrl=" +
    encodeURIComponent("https://config.example/loc.json?token=SENSITIVE_CONFIG_TOKEN")
});
for (const sentinel of ["SENSITIVE_CONFIG_TOKEN", "SENSITIVE_COOKIE", "SENSITIVE_QUERY"]) {
  assert.equal(
    privateDiagnostics.logs.some((line) => line.includes(sentinel)),
    false,
    `diagnostic logs must not include ${sentinel}`
  );
}
assert.equal(privateDiagnostics.logs.some((line) => line.includes("35.658581")), false);
assert.equal(privateDiagnostics.logs.some((line) => line.includes("139.745433")), false);
assert.ok(
  privateDiagnostics.logs.some((line) => line.includes("url=https://gs-loc.apple.com/clls/wloc, status=200")),
  "URL diagnostics must omit query strings and fragments"
);
assert.ok(
  privateDiagnostics.logs.some((line) => line.includes("[REDACTED]")),
  "sensitive headers must be redacted in diagnostics"
);
assert.ok(
  privateDiagnostics.logs.some((line) => line.includes("raw dumps are disabled")),
  "raw dump requests must emit a safe warning"
);
assert.equal(
  Object.keys(privateDiagnostics.result.headers).filter((name) => name.toLowerCase() === "content-type").length,
  1,
  "rewritten response must contain one canonical content type"
);
assert.equal(privateDiagnostics.result.headers["Content-Type"], "application/octet-stream");
assert.equal(
  Object.keys(privateDiagnostics.result.headers).some((name) =>
    ["content-length", "content-encoding", "transfer-encoding"].includes(name.toLowerCase()) &&
    name !== "Content-Length"
  ),
  false,
  "rewritten response must remove stale binary framing headers case-insensitively"
);

const decompressionFailure = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: { "Content-Encoding": "gzip" },
    body: Uint8Array.from([0x1f, 0x8b, 0x00])
  },
  $argument: "mode=response&debug=false",
  $utils: {
    ungzip() {
      throw new Error("decompression fixture failure");
    }
  }
});
assert.deepEqual(decompressionFailure.logs, [], "debug=false must suppress decompression diagnostics");

function assertNonStringResponseUrlIsSafe(url, sentinel) {
  const result = runRuntime({
    $environment: { product: "Shadowrocket" },
    $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
    $response: {
      status: 200,
      url,
      headers: { "Content-Type": "application/octet-stream" },
      body: originalResponse
    },
    $argument: "mode=response&debug=true&dumpHeaders=true"
  });
  assert.equal(result.logs.some((line) => line.includes(sentinel)), false);
  assert.ok(result.logs.some((line) => line.includes("url=<non-string>")));
}

assertNonStringResponseUrlIsSafe(
  ["https://gs-loc.apple.com/clls/wloc", "SENSITIVE_URL_ARRAY"],
  "SENSITIVE_URL_ARRAY"
);
assertNonStringResponseUrlIsSafe(
  { toString: () => "https://gs-loc.apple.com/clls/wloc?SENSITIVE_URL_OBJECT" },
  "SENSITIVE_URL_OBJECT"
);

const sensitivePrefixResponse = spoofer.concatBytes([
  Uint8Array.from(Buffer.from("SENSITIV", "ascii")),
  spoofer.APPLE_WLOC_MARKER,
  spoofer.writeUInt16BE(wifiPayload.length),
  wifiPayload
]);
const sensitivePrefixDiagnostics = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: { "Content-Type": "application/octet-stream" },
    body: sensitivePrefixResponse
  },
  $argument: "mode=response&debug=true"
});
assert.equal(sensitivePrefixDiagnostics.logs.some((line) => line.includes("SENSITIV")), false);
assert.equal(sensitivePrefixDiagnostics.logs.some((line) => line.includes("53454e5349544956")), false);

const probeDiagnostics = runRuntime({
  $environment: { product: "Shadowrocket" },
  $request: { url: "https://gs-loc.apple.com/clls/wloc", headers: {} },
  $response: {
    status: 200,
    headers: {
      "Content-Length": "35.658581,139.745433",
      "Content-Type": ["application/octet-stream", "PROBE_ARRAY_SECRET"],
      "Content-Encoding": { toString: () => "PROBE_OBJECT_SECRET" }
    },
    body: originalResponse
  },
  $argument: "mode=probe&debug=true"
});
for (const sensitiveValue of ["35.658581", "139.745433", "PROBE_ARRAY_SECRET", "PROBE_OBJECT_SECRET"]) {
  assert.equal(probeDiagnostics.logs.some((line) => line.includes(sensitiveValue)), false);
}
assert.ok(
  probeDiagnostics.logs.some((line) =>
    line.includes("content-length=present, content-type=present, content-encoding=present")
  ),
  "probe diagnostics must expose header presence without values"
);

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
