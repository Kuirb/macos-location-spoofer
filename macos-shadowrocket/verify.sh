#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

command -v node >/dev/null 2>&1 || {
  printf 'error: Node.js is required for the offline verification tests.\n' >&2
  exit 2
}

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macos-location-spoofer.XXXXXX")
GENERATED="$TEMP_DIR/verification.sgmodule"

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
grep -Eq '__[A-Z_]+__' "$GENERATED" && {
  printf 'Generated module contains an unresolved placeholder.\n' >&2
  exit 1
}

EXPECTED_HOSTNAME='hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com'
ACTUAL_HOSTNAME=$(grep '^hostname = ' "$GENERATED")
[ "$ACTUAL_HOSTNAME" = "$EXPECTED_HOSTNAME" ] || {
  printf 'Generated module must contain exactly the four supported MITM hosts.\n' >&2
  exit 1
}

SENSITIVE_MODULE="$TEMP_DIR/sensitive-module.sgmodule"
sed 's/&debug=false/&configToken=SENSITIVE_CONFIG_TOKEN&debug=false/g' "$GENERATED" > "$SENSITIVE_MODULE"
MODULE_SUMMARY=$("$SCRIPT_DIR/diagnose.sh" --module-summary "$SENSITIVE_MODULE")
EXPECTED_SUMMARY=$(printf '%s\n' \
  '#!name=macOS Location Spoofer' \
  'macOS Location Spoofer Prepare' \
  'macOS Location Spoofer Response' \
  "$EXPECTED_HOSTNAME")
[ "$MODULE_SUMMARY" = "$EXPECTED_SUMMARY" ] || {
  printf 'Diagnostic module summary must contain only safe module metadata.\n' >&2
  exit 1
}
if printf '%s\n' "$MODULE_SUMMARY" | grep -Eq 'latitude=|longitude=|configToken=|argument='; then
  printf 'Diagnostic module summary exposed sensitive module arguments.\n' >&2
  exit 1
fi

assert_safe_summary_rejection() {
  if SUMMARY_REJECTION_OUTPUT=$("$SCRIPT_DIR/diagnose.sh" --module-summary "$1" 2>&1); then
    printf 'Expected an invalid module summary to fail.\n' >&2
    exit 1
  fi
  if printf '%s\n' "$SUMMARY_REJECTION_OUTPUT" | grep -Eq 'latitude=|longitude=|configToken=|argument=|SENSITIVE_PATH|https?://'; then
    printf 'Invalid module summary output exposed sensitive input.\n' >&2
    exit 1
  fi
}

EMPTY_MODULE="$TEMP_DIR/empty.sgmodule"
: > "$EMPTY_MODULE"
assert_safe_summary_rejection "$EMPTY_MODULE"

DUPLICATE_NAME_MODULE="$TEMP_DIR/duplicate-name.sgmodule"
sed '1a\
#!name=macOS Location Spoofer' "$SENSITIVE_MODULE" > "$DUPLICATE_NAME_MODULE"
assert_safe_summary_rejection "$DUPLICATE_NAME_MODULE"

DUPLICATE_SCRIPT_MODULE="$TEMP_DIR/duplicate-script.sgmodule"
sed '/^\[Script\]$/a\
[Script]' "$SENSITIVE_MODULE" > "$DUPLICATE_SCRIPT_MODULE"
assert_safe_summary_rejection "$DUPLICATE_SCRIPT_MODULE"

INJECTED_SCRIPT_MODULE="$TEMP_DIR/injected-script.sgmodule"
awk '
  /^\[Script\]$/ {
    print
    print "Injected Rule = type=http-response,argument=configToken=SENSITIVE_CONFIG_TOKEN"
    next
  }
  { print }
' "$SENSITIVE_MODULE" > "$INJECTED_SCRIPT_MODULE"
assert_safe_summary_rejection "$INJECTED_SCRIPT_MODULE"

MISSING_RESPONSE_MODULE="$TEMP_DIR/missing-response.sgmodule"
sed '/^macOS Location Spoofer Response =/d' "$SENSITIVE_MODULE" > "$MISSING_RESPONSE_MODULE"
assert_safe_summary_rejection "$MISSING_RESPONSE_MODULE"

OUTSIDE_MITM_MODULE="$TEMP_DIR/outside-mitm.sgmodule"
sed '/^\[MITM\]$/d' "$SENSITIVE_MODULE" > "$OUTSIDE_MITM_MODULE"
assert_safe_summary_rejection "$OUTSIDE_MITM_MODULE"

EXTRA_HOST_MODULE="$TEMP_DIR/extra-host.sgmodule"
sed '/^hostname = /a\
hostname = attacker.example' "$SENSITIVE_MODULE" > "$EXTRA_HOST_MODULE"
assert_safe_summary_rejection "$EXTRA_HOST_MODULE"

OUTSIDE_HOST_MODULE="$TEMP_DIR/outside-host.sgmodule"
printf '%s\n[General]\nhostname = attacker.example\n' "$(cat "$SENSITIVE_MODULE")" > "$OUTSIDE_HOST_MODULE"
assert_safe_summary_rejection "$OUTSIDE_HOST_MODULE"

INJECTED_MITM_MODULE="$TEMP_DIR/injected-mitm.sgmodule"
awk '
  /^hostname = / {
    print
    print "skip-cert-verify = true"
    next
  }
  { print }
' "$SENSITIVE_MODULE" > "$INJECTED_MITM_MODULE"
assert_safe_summary_rejection "$INJECTED_MITM_MODULE"

NAME_IN_MITM_MODULE="$TEMP_DIR/name-in-mitm.sgmodule"
awk '
  /^#!name=/ { next }
  /^\[MITM\]$/ {
    print
    print "#!name=macOS Location Spoofer"
    next
  }
  { print }
' "$SENSITIVE_MODULE" > "$NAME_IN_MITM_MODULE"
assert_safe_summary_rejection "$NAME_IN_MITM_MODULE"

UNEXPECTED_SECTION_MODULE="$TEMP_DIR/unexpected-section.sgmodule"
printf '%s\n[General]\nproxy = configToken=SENSITIVE_CONFIG_TOKEN\n' "$(cat "$SENSITIVE_MODULE")" > "$UNEXPECTED_SECTION_MODULE"
assert_safe_summary_rejection "$UNEXPECTED_SECTION_MODULE"

MISSING_MODULE_PATH="$TEMP_DIR/SENSITIVE_PATH_latitude=39.9042_configToken=SECRET.sgmodule"
assert_safe_summary_rejection "$MISSING_MODULE_PATH"

EXAMPLE_GENERATED="$TEMP_DIR/from-example.sgmodule"
"$SCRIPT_DIR/update-location.sh" \
  --config "$SCRIPT_DIR/location.example.conf" \
  --output "$EXAMPLE_GENERATED"
grep -q 'latitude=37.3349&longitude=-122.00902' "$EXAMPLE_GENERATED"
grep -q 'horizontalAccuracy=15' "$EXAMPLE_GENERATED"
grep -q 'verticalAccuracy=25' "$EXAMPLE_GENERATED"
grep -q 'altitude=56' "$EXAMPLE_GENERATED"
grep -q 'debug=false' "$EXAMPLE_GENERATED"
cmp -s "$EXAMPLE_GENERATED" "$SCRIPT_DIR/../dist/macos-location-spoofer.sgmodule" || {
  printf 'Generated example module differs from dist/macos-location-spoofer.sgmodule.\n' >&2
  exit 1
}

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

if "$SCRIPT_DIR/generate-module.sh" --latitude 91 --output "$TEMP_DIR/invalid.sgmodule" >/dev/null 2>&1; then
  printf 'Expected invalid latitude to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" --horizontal-accuracy 0.5 --output "$TEMP_DIR/invalid.sgmodule" >/dev/null 2>&1; then
  printf 'Expected sub-metre horizontal accuracy to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" --horizontal-accuracy 1000001 --output "$TEMP_DIR/invalid.sgmodule" >/dev/null 2>&1; then
  printf 'Expected oversized horizontal accuracy to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" --vertical-accuracy 1.5 --output "$TEMP_DIR/invalid.sgmodule" >/dev/null 2>&1; then
  printf 'Expected fractional vertical accuracy to fail.\n' >&2
  exit 1
fi

MAX_ACCURACY="$TEMP_DIR/max-accuracy.sgmodule"
"$SCRIPT_DIR/generate-module.sh" \
  --horizontal-accuracy 1000000 \
  --vertical-accuracy 1 \
  --output "$MAX_ACCURACY"
grep -q 'horizontalAccuracy=1000000' "$MAX_ACCURACY"
grep -q 'verticalAccuracy=1' "$MAX_ACCURACY"

if (
  cd "$TEMP_DIR"
  "$SCRIPT_DIR/generate-module.sh" --output --help
) >/dev/null 2>&1; then
  printf 'Expected an option token used as an output value to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" --output "$TEMP_DIR/not-a-module.txt" >/dev/null 2>&1; then
  printf 'Expected a non-.sgmodule output path to fail.\n' >&2
  exit 1
fi

if "$SCRIPT_DIR/generate-module.sh" --output "$SCRIPT_DIR/module.template.sgmodule" >/dev/null 2>&1; then
  printf 'Expected the module template output path to fail.\n' >&2
  exit 1
fi

DESTINATION_DIRECTORY="$TEMP_DIR/destination-directory.sgmodule"
mkdir "$DESTINATION_DIRECTORY"
if "$SCRIPT_DIR/generate-module.sh" --output "$DESTINATION_DIRECTORY" >/dev/null 2>&1; then
  printf 'Expected a directory destination to fail.\n' >&2
  exit 1
fi
[ -d "$DESTINATION_DIRECTORY" ] || {
  printf 'Directory destination was unexpectedly replaced.\n' >&2
  exit 1
}
[ -z "$(find "$DESTINATION_DIRECTORY" -mindepth 1 -print -quit)" ] || {
  printf 'Directory destination received generated content.\n' >&2
  exit 1
}

SYMLINK_DIRECTORY="$TEMP_DIR/symlink-directory.sgmodule"
ln -s "$DESTINATION_DIRECTORY" "$SYMLINK_DIRECTORY"
if "$SCRIPT_DIR/generate-module.sh" --output "$SYMLINK_DIRECTORY" >/dev/null 2>&1; then
  printf 'Expected a symlink-to-directory destination to fail.\n' >&2
  exit 1
fi
[ -L "$SYMLINK_DIRECTORY" ] && [ -d "$SYMLINK_DIRECTORY" ] || {
  printf 'Symlink-to-directory destination was unexpectedly replaced.\n' >&2
  exit 1
}

PRESERVED_OUTPUT="$TEMP_DIR/preserved-output.sgmodule"
printf 'preserve this existing output\n' > "$PRESERVED_OUTPUT"
if "$SCRIPT_DIR/generate-module.sh" --horizontal-accuracy 1000001 --output "$PRESERVED_OUTPUT" >/dev/null 2>&1; then
  printf 'Expected invalid generation to fail before replacing output.\n' >&2
  exit 1
fi
cmp -s "$PRESERVED_OUTPUT" <(printf 'preserve this existing output\n') || {
  printf 'Failed generation replaced an existing output.\n' >&2
  exit 1
}

POST_RENDER_PARENT="$TEMP_DIR/post-render-parent"
POST_RENDER_OUTPUT="$POST_RENDER_PARENT/preserved-output.sgmodule"
FAKE_SED_BIN="$TEMP_DIR/fake-sed-bin"
mkdir "$POST_RENDER_PARENT" "$FAKE_SED_BIN"
printf '%s\n' \
  '#!/bin/bash' \
  'printf "__SCRIPT_PATH__\\n"' > "$FAKE_SED_BIN/sed"
chmod +x "$FAKE_SED_BIN/sed"
printf 'preserve after render failure\n' > "$POST_RENDER_OUTPUT"
if PATH="$FAKE_SED_BIN:$PATH" "$SCRIPT_DIR/generate-module.sh" --output "$POST_RENDER_OUTPUT" >/dev/null 2>&1; then
  printf 'Expected unresolved placeholder validation to fail.\n' >&2
  exit 1
fi
cmp -s "$POST_RENDER_OUTPUT" <(printf 'preserve after render failure\n') || {
  printf 'Post-render validation failure replaced an existing output.\n' >&2
  exit 1
}
[ -z "$(find "$POST_RENDER_PARENT" -maxdepth 1 -name '.preserved-output.sgmodule.*' -print -quit)" ] || {
  printf 'Post-render validation failure left a temporary render file behind.\n' >&2
  exit 1
}

ATOMIC_PARENT="$TEMP_DIR/atomic-parent"
ATOMIC_OUTPUT="$ATOMIC_PARENT/atomic-output.sgmodule"
mkdir "$ATOMIC_PARENT"
"$SCRIPT_DIR/generate-module.sh" --output "$ATOMIC_OUTPUT" >/dev/null
[ -f "$ATOMIC_OUTPUT" ] || {
  printf 'Expected atomic output to be a regular file.\n' >&2
  exit 1
}
[ ! -L "$ATOMIC_OUTPUT" ] || {
  printf 'Expected atomic output not to be a symlink.\n' >&2
  exit 1
}
[ -z "$(find "$ATOMIC_PARENT" -maxdepth 1 -name '.atomic-output.sgmodule.*' -print -quit)" ] || {
  printf 'Generator left a temporary render file behind.\n' >&2
  exit 1
}

NO_NODE_BIN="$TEMP_DIR/no-node-bin"
mkdir "$NO_NODE_BIN"
ln -s "$(command -v dirname)" "$NO_NODE_BIN/dirname"
if MISSING_NODE_OUTPUT=$(PATH="$NO_NODE_BIN" TMPDIR="$TEMP_DIR/missing-parent" "$SCRIPT_DIR/verify.sh" 2>&1); then
  printf 'Expected verification without Node.js to fail.\n' >&2
  exit 1
fi
case "$MISSING_NODE_OUTPUT" in
  *'Node.js is required for the offline verification tests.'*) ;;
  *)
    printf 'Verification must check for Node.js before creating a temporary directory.\n' >&2
    exit 1
    ;;
esac

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
