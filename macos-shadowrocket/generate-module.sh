#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/module.template.sgmodule"
TEMP_FILE=""

latitude="37.3349"
longitude="-122.00902"
altitude="56"
horizontal_accuracy="15"
vertical_accuracy="25"
debug="false"
script_path="location-spoofer.js"
output="$SCRIPT_DIR/generated/macos-location-spoofer.sgmodule"

usage() {
  cat <<'EOF'
Usage: ./generate-module.sh [options]

Options:
  --latitude NUMBER             Target latitude (-90...90)
  --longitude NUMBER            Target longitude (-180...180)
  --altitude NUMBER             Altitude in metres (-1000...20000)
  --horizontal-accuracy NUMBER  Horizontal accuracy in metres (1...1000000)
  --vertical-accuracy NUMBER    Vertical accuracy in metres (1...1000000)
  --debug true|false            Enable Shadowrocket script diagnostics
  --script-path PATH_OR_URL     Local Script filename or HTTPS URL
  --output PATH                 Generated module path
  --help                        Show this help

Defaults target Apple Park (including a realistic elevation and accuracy) and
use the local location-spoofer.js.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

need_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value"
  case "$2" in
    --*) die "$1 requires a value" ;;
  esac
}

is_number() {
  awk -v value="$1" 'BEGIN {
    if (value ~ /^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$/) exit 0
    exit 1
  }'
}

in_range() {
  awk -v value="$1" -v minimum="$2" -v maximum="$3" 'BEGIN {
    exit !(value >= minimum && value <= maximum)
  }'
}

is_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

cleanup() {
  if [ -n "${TEMP_FILE:-}" ] && [ -e "$TEMP_FILE" ]; then
    rm -f "$TEMP_FILE"
  fi
}

trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --latitude)
      need_value "$@"
      latitude="$2"
      shift 2
      ;;
    --longitude)
      need_value "$@"
      longitude="$2"
      shift 2
      ;;
    --altitude)
      need_value "$@"
      altitude="$2"
      shift 2
      ;;
    --horizontal-accuracy)
      need_value "$@"
      horizontal_accuracy="$2"
      shift 2
      ;;
    --vertical-accuracy)
      need_value "$@"
      vertical_accuracy="$2"
      shift 2
      ;;
    --debug)
      need_value "$@"
      debug="$2"
      shift 2
      ;;
    --script-path|--script-url)
      need_value "$@"
      script_path="$2"
      shift 2
      ;;
    --output)
      need_value "$@"
      output="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

is_number "$latitude" || die "latitude must be a number"
in_range "$latitude" -90 90 || die "latitude must be between -90 and 90"
is_number "$longitude" || die "longitude must be a number"
in_range "$longitude" -180 180 || die "longitude must be between -180 and 180"
is_number "$altitude" || die "altitude must be a number"
in_range "$altitude" -1000 20000 || die "altitude must be between -1000 and 20000"
is_integer "$horizontal_accuracy" || die "horizontal accuracy must be an integer"
in_range "$horizontal_accuracy" 1 1000000 || die "horizontal accuracy must be between 1 and 1000000"
is_integer "$vertical_accuracy" || die "vertical accuracy must be an integer"
in_range "$vertical_accuracy" 1 1000000 || die "vertical accuracy must be between 1 and 1000000"

case "$debug" in
  true|false) ;;
  *) die "debug must be true or false" ;;
esac

case "$script_path" in
  location-spoofer.js) ;;
  https://*) ;;
  *) die "script path must be location-spoofer.js or an HTTPS URL" ;;
esac

case "$script_path" in
  *','*|*'&'*|*'|'*|*'\\'*|*' '*|*$'\t'*|*$'\r'*|*$'\n'*)
    die "script path contains an unsafe module character"
    ;;
esac

[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

case "$output" in
  *.sgmodule) ;;
  *) die "output must end in .sgmodule" ;;
esac

OUTPUT_PARENT=$(dirname -- "$output")
OUTPUT_NAME=$(basename -- "$output")
mkdir -p "$OUTPUT_PARENT"
OUTPUT_PARENT=$(CDPATH= cd -- "$OUTPUT_PARENT" && pwd -P)
OUTPUT="$OUTPUT_PARENT/$OUTPUT_NAME"

if [ "$OUTPUT" = "$TEMPLATE" ] || { [ -e "$OUTPUT" ] && [ "$OUTPUT" -ef "$TEMPLATE" ]; }; then
  die "output must not replace the module template"
fi

TEMP_FILE=$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.XXXXXX")

sed \
  -e "s|__SCRIPT_PATH__|$script_path|g" \
  -e "s|__LATITUDE__|$latitude|g" \
  -e "s|__LONGITUDE__|$longitude|g" \
  -e "s|__ALTITUDE__|$altitude|g" \
  -e "s|__HORIZONTAL_ACCURACY__|$horizontal_accuracy|g" \
  -e "s|__VERTICAL_ACCURACY__|$vertical_accuracy|g" \
  -e "s|__DEBUG__|$debug|g" \
  "$TEMPLATE" > "$TEMP_FILE"

[ -s "$TEMP_FILE" ] || die "generated module is empty"
if grep -Eq '__[A-Z_]+__' "$TEMP_FILE"; then
  die "generated module contains unresolved placeholders"
fi

mv -f "$TEMP_FILE" "$OUTPUT"
TEMP_FILE=""

printf 'Generated %s\n' "$OUTPUT"
printf 'Target: %s, %s (altitude %sm)\n' "$latitude" "$longitude" "$altitude"
printf 'Script: %s\n' "$script_path"
