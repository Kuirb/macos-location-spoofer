#!/bin/bash

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$SCRIPT_DIR/location.conf"
output="$SCRIPT_DIR/generated/macos-location-spoofer.sgmodule"

usage() {
  cat <<'EOF'
Usage: ./update-location.sh [options]

Read a plain key=value location file and regenerate the Shadowrocket module.

Options:
  --config PATH  Configuration file (default: location.conf)
  --output PATH  Generated module path
  --help         Show this help
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

need_value() {
  [ "$#" -ge 2 ] || die "option requires a value"
  case "$2" in
    --*) die "option requires a value" ;;
  esac
}

trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      need_value "$@"
      config=$2
      shift 2
      ;;
    --output)
      need_value "$@"
      output=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option"
      ;;
  esac
done

if [ ! -f "$config" ]; then
  if [ "$config" = "$SCRIPT_DIR/location.conf" ]; then
    die "configuration file not found (copy macos-shadowrocket/location.example.conf to macos-shadowrocket/location.conf first)"
  fi
  die "configuration file not found"
fi

if ! { exec 3< "$config"; } 2>/dev/null; then
  die "configuration file could not be opened"
fi

latitude=
longitude=
altitude=
horizontal_accuracy=
vertical_accuracy=
debug=
seen_latitude=false
seen_longitude=false
seen_altitude=false
seen_horizontal_accuracy=false
seen_vertical_accuracy=false
seen_debug=false
line_number=0

while IFS= read -r line || [ -n "$line" ]; do
  line_number=$((line_number + 1))
  line=${line%$'\r'}
  stripped=$(trim "$line")

  case "$stripped" in
    ''|'#'*) continue ;;
  esac

  case "$stripped" in
    *=*) ;;
    *) die "invalid configuration at line $line_number" ;;
  esac

  key=$(trim "${stripped%%=*}")
  parsed_value=$(trim "${stripped#*=}")
  [ -n "$parsed_value" ] || die "configuration value is empty at line $line_number"

  case "$key" in
    latitude)
      [ "$seen_latitude" = false ] || die "duplicate configuration key at line $line_number"
      latitude=$parsed_value
      seen_latitude=true
      ;;
    longitude)
      [ "$seen_longitude" = false ] || die "duplicate configuration key at line $line_number"
      longitude=$parsed_value
      seen_longitude=true
      ;;
    altitude)
      [ "$seen_altitude" = false ] || die "duplicate configuration key at line $line_number"
      altitude=$parsed_value
      seen_altitude=true
      ;;
    horizontal_accuracy)
      [ "$seen_horizontal_accuracy" = false ] || die "duplicate configuration key at line $line_number"
      horizontal_accuracy=$parsed_value
      seen_horizontal_accuracy=true
      ;;
    vertical_accuracy)
      [ "$seen_vertical_accuracy" = false ] || die "duplicate configuration key at line $line_number"
      vertical_accuracy=$parsed_value
      seen_vertical_accuracy=true
      ;;
    debug)
      [ "$seen_debug" = false ] || die "duplicate configuration key at line $line_number"
      debug=$parsed_value
      seen_debug=true
      ;;
    *)
      die "unknown configuration key at line $line_number"
      ;;
  esac
done <&3
exec 3<&-

for required_key in \
  latitude longitude altitude horizontal_accuracy vertical_accuracy debug
do
  case "$required_key" in
    latitude) present=$seen_latitude ;;
    longitude) present=$seen_longitude ;;
    altitude) present=$seen_altitude ;;
    horizontal_accuracy) present=$seen_horizontal_accuracy ;;
    vertical_accuracy) present=$seen_vertical_accuracy ;;
    debug) present=$seen_debug ;;
  esac
  [ "$present" = true ] || die "missing required configuration key"
done

"$SCRIPT_DIR/generate-module.sh" \
  --latitude "$latitude" \
  --longitude "$longitude" \
  --altitude "$altitude" \
  --horizontal-accuracy "$horizontal_accuracy" \
  --vertical-accuracy "$vertical_accuracy" \
  --debug "$debug" \
  --output "$output"
