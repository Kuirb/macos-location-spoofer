#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macos-location-spoofer.XXXXXX")
GENERATED="$TEMP_DIR/verification.sgmodule"

command -v node >/dev/null 2>&1 || {
  printf 'error: Node.js is required for the offline verification tests.\n' >&2
  exit 2
}

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

bash -n "$SCRIPT_DIR/generate-module.sh"
bash -n "$SCRIPT_DIR/update-location.sh"
bash -n "$SCRIPT_DIR/diagnose.sh"
bash -n "$SCRIPT_DIR/observe-locationd.sh"

node "$SCRIPT_DIR/test-protocol.js"
node "$SCRIPT_DIR/test-runtime.js"

"$SCRIPT_DIR/generate-module.sh" \
  --latitude 39.9042 \
  --longitude 116.4074 \
  --altitude 43 \
  --horizontal-accuracy 25 \
  --vertical-accuracy 80 \
  --debug false \
  --output "$GENERATED"

grep -q "latitude=39.9042&longitude=116.4074" "$GENERATED"
grep -q "altitude=43" "$GENERATED"
grep -q "horizontalAccuracy=25" "$GENERATED"
grep -q "verticalAccuracy=80" "$GENERATED"
grep -q 'script-path=location-spoofer.js' "$GENERATED"
grep -q '^macOS Location Spoofer Prepare = type=http-request' "$GENERATED"
grep -q '^macOS Location Spoofer Response = type=http-response' "$GENERATED"
grep -q '^hostname = %APPEND% gs-loc.apple.com' "$GENERATED"

EXAMPLE_GENERATED="$TEMP_DIR/from-example.sgmodule"
"$SCRIPT_DIR/update-location.sh" \
  --config "$SCRIPT_DIR/location.example.conf" \
  --output "$EXAMPLE_GENERATED"
grep -q 'latitude=37.3349&longitude=-122.00902' "$EXAMPLE_GENERATED"
grep -q 'horizontalAccuracy=15' "$EXAMPLE_GENERATED"
grep -q 'verticalAccuracy=25' "$EXAMPLE_GENERATED"
grep -q 'altitude=56' "$EXAMPLE_GENERATED"
grep -q 'debug=false' "$EXAMPLE_GENERATED"

CONFIG="$TEMP_DIR/location.conf"
FROM_CONFIG="$TEMP_DIR/from-config.sgmodule"
printf '%s\n' \
  '# whitespace and comments are accepted' \
  ' latitude = 35.658581 ' \
  'longitude=139.745433' \
  'altitude=40' \
  'horizontal_accuracy=10' \
  'vertical_accuracy=20' \
  'debug=false' > "$CONFIG"

"$SCRIPT_DIR/update-location.sh" --config "$CONFIG" --output "$FROM_CONFIG"
grep -q 'latitude=35.658581&longitude=139.745433' "$FROM_CONFIG"
grep -q 'horizontalAccuracy=10' "$FROM_CONFIG"
grep -q 'verticalAccuracy=20' "$FROM_CONFIG"
grep -q 'altitude=40' "$FROM_CONFIG"
grep -q 'debug=false' "$FROM_CONFIG"

printf '%s\n' \
  'latitude=35.658581' \
  'longitude=139.745433' \
  'altitude=40' \
  'horizontal_accuracy=10' \
  'vertical_accuracy=20' \
  'debug=false' \
  'script_path=https://example.invalid/injected.js' > "$CONFIG"

if "$SCRIPT_DIR/update-location.sh" --config "$CONFIG" --output "$FROM_CONFIG" >/dev/null 2>&1; then
  printf 'Expected an unknown configuration key to fail.\n' >&2
  exit 1
fi

SIDE_EFFECT="$TEMP_DIR/side-effect"
printf 'latitude=$(touch %s)\n' "$SIDE_EFFECT" > "$CONFIG"
printf '%s\n' \
  'longitude=139.745433' \
  'altitude=40' \
  'horizontal_accuracy=10' \
  'vertical_accuracy=20' \
  'debug=false' >> "$CONFIG"

if "$SCRIPT_DIR/update-location.sh" --config "$CONFIG" --output "$FROM_CONFIG" >/dev/null 2>&1; then
  printf 'Expected a non-numeric configuration value to fail.\n' >&2
  exit 1
fi

[ ! -e "$SIDE_EFFECT" ] || {
  printf 'Configuration contents were unexpectedly executed.\n' >&2
  exit 1
}

if "$SCRIPT_DIR/generate-module.sh" --latitude 91 --output "$GENERATED.invalid" >/dev/null 2>&1; then
  printf 'Expected invalid latitude to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" \
  --script-path 'https://example.invalid/x.js,argument=enabled=false' \
  --output "$GENERATED.injected" >/dev/null 2>&1; then
  printf 'Expected an injected module field in script-path to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" \
  --script-path 'http://localhost:80@evil.example/x.js' \
  --output "$GENERATED.pseudo-loopback" >/dev/null 2>&1; then
  printf 'Expected a pseudo-loopback HTTP script URL to fail.\n' >&2
  exit 1
fi

printf 'All macOS Shadowrocket checks passed.\n'
