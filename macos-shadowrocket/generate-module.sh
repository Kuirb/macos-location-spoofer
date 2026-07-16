#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/module.template.sgmodule"

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
  --horizontal-accuracy NUMBER  Horizontal accuracy in metres (> 0)
  --vertical-accuracy NUMBER    Vertical accuracy in metres (> 0)
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

greater_than_zero() {
  awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

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
is_number "$horizontal_accuracy" || die "horizontal accuracy must be a number"
greater_than_zero "$horizontal_accuracy" || die "horizontal accuracy must be greater than zero"
is_number "$vertical_accuracy" || die "vertical accuracy must be a number"
greater_than_zero "$vertical_accuracy" || die "vertical accuracy must be greater than zero"

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
mkdir -p "$(dirname -- "$output")"

sed \
  -e "s|__SCRIPT_PATH__|$script_path|g" \
  -e "s|__LATITUDE__|$latitude|g" \
  -e "s|__LONGITUDE__|$longitude|g" \
  -e "s|__ALTITUDE__|$altitude|g" \
  -e "s|__HORIZONTAL_ACCURACY__|$horizontal_accuracy|g" \
  -e "s|__VERTICAL_ACCURACY__|$vertical_accuracy|g" \
  -e "s|__DEBUG__|$debug|g" \
  "$TEMPLATE" > "$output"

printf 'Generated %s\n' "$output"
printf 'Target: %s, %s (altitude %sm)\n' "$latitude" "$longitude" "$altitude"
printf 'Script: %s\n' "$script_path"
