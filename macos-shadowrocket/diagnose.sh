#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE="$SCRIPT_DIR/generated/macos-location-spoofer.sgmodule"
SHADOWROCKET_INFO="/Applications/Shadowrocket.app/Contents/Info.plist"

section() {
  printf '\n[%s]\n' "$1"
}

section "macOS"
sw_vers
uname -m

section "Shadowrocket"
if [ -f "$SHADOWROCKET_INFO" ]; then
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SHADOWROCKET_INFO" 2>/dev/null || printf 'unknown')
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SHADOWROCKET_INFO" 2>/dev/null || printf 'unknown')
  printf 'Installed: %s (%s)\n' "$version" "$identifier"
else
  printf 'Not found at /Applications/Shadowrocket.app\n'
fi

section "Generated module"
if [ -f "$MODULE" ]; then
  printf 'Found: %s\n' "$MODULE"
  grep -E '^#!name=|^macOS Location Spoofer|^hostname = ' "$MODULE" || true
else
  printf 'Missing. Run ./generate-module.sh first.\n'
fi

section "Core Location endpoint"
if strings -a /usr/libexec/locationd 2>/dev/null | grep -q 'https://gs-loc.apple.com/clls/wloc'; then
  printf 'locationd contains the expected /clls/wloc endpoint.\n'
else
  printf 'WARNING: expected endpoint not found in locationd. This macOS build may use a different path.\n'
fi

section "DNS"
for host in gs-loc.apple.com gs-loc-cn.apple.com bluedot.is.autonavi.com; do
  if dscacheutil -q host -a name "$host" 2>/dev/null | grep -q '^ip_address:'; then
    printf '%-38s resolvable\n' "$host"
  else
    printf '%-38s no address returned\n' "$host"
  fi
done

section "System proxy snapshot"
scutil --proxy

section "locationd service"
if launchctl print system/com.apple.locationd 2>/dev/null | grep -q 'state = running'; then
  printf 'locationd is running.\n'
else
  printf 'locationd state could not be confirmed.\n'
fi

printf '\nThis script is read-only. It does not validate CA trust or prove interception.\n'
