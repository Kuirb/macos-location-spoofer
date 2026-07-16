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
  [ "$#" -ge 2 ] || die "$1 requires a value"
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
      die "unknown option: $1"
      ;;
  esac
done

if [ ! -f "$config" ]; then
  if [ "$config" = "$SCRIPT_DIR/location.conf" ]; then
    die "configuration file not found: $config (copy location.example.conf to location.conf first)"
  fi
  die "configuration file not found: $config"
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
    *) die "$config:$line_number: expected key=value" ;;
  esac

  key=$(trim "${stripped%%=*}")
  parsed_value=$(trim "${stripped#*=}")
  [ -n "$parsed_value" ] || die "$config:$line_number: $key has no value"

  case "$key" in
    latitude)
      [ "$seen_latitude" = false ] || die "$config:$line_number: duplicate key: $key"
      latitude=$parsed_value
      seen_latitude=true
      ;;
    longitude)
      [ "$seen_longitude" = false ] || die "$config:$line_number: duplicate key: $key"
      longitude=$parsed_value
      seen_longitude=true
      ;;
    altitude)
      [ "$seen_altitude" = false ] || die "$config:$line_number: duplicate key: $key"
      altitude=$parsed_value
      seen_altitude=true
      ;;
    horizontal_accuracy)
      [ "$seen_horizontal_accuracy" = false ] || die "$config:$line_number: duplicate key: $key"
      horizontal_accuracy=$parsed_value
      seen_horizontal_accuracy=true
      ;;
    vertical_accuracy)
      [ "$seen_vertical_accuracy" = false ] || die "$config:$line_number: duplicate key: $key"
      vertical_accuracy=$parsed_value
      seen_vertical_accuracy=true
      ;;
    debug)
      [ "$seen_debug" = false ] || die "$config:$line_number: duplicate key: $key"
      debug=$parsed_value
      seen_debug=true
      ;;
    *)
      die "$config:$line_number: unknown key: $key"
      ;;
  esac
done < "$config"

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
  [ "$present" = true ] || die "$config: missing required key: $required_key"
done

"$SCRIPT_DIR/generate-module.sh" \
  --latitude "$latitude" \
  --longitude "$longitude" \
  --altitude "$altitude" \
  --horizontal-accuracy "$horizontal_accuracy" \
  --vertical-accuracy "$vertical_accuracy" \
  --debug "$debug" \
  --output "$output"
