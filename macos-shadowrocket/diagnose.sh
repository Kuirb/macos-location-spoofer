#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE="$SCRIPT_DIR/generated/macos-location-spoofer.sgmodule"
SHADOWROCKET_INFO="/Applications/Shadowrocket.app/Contents/Info.plist"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

module_summary() {
  if ! awk '
    BEGIN {
      expected_name = "#!name=macOS Location Spoofer"
      expected_desc = "#!desc=Rewrite Apple Wi-Fi positioning responses on macOS through Shadowrocket. A trusted local MITM CA is required."
      expected_homepage = "#!homepage=https://github.com/Kuirb/macos-location-spoofer"
      expected_hostname = "hostname = %APPEND% gs-loc.apple.com, gs-loc-cn.apple.com, bluedot.is.autonavi.com, bluedot.is.autonavi.com.gds.alibabadns.com"
      section = "top"
    }
    /^#!name=/ {
      name_count++
      if (section != "top" || $0 != expected_name) invalid = 1
      next
    }
    /^#!desc=/ {
      desc_count++
      if (section != "top" || $0 != expected_desc) invalid = 1
      next
    }
    /^#!homepage=/ {
      homepage_count++
      if (section != "top" || $0 != expected_homepage) invalid = 1
      next
    }
    /^#!/ {
      invalid = 1
      next
    }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ {
      next
    }
    /^\[Script\]$/ {
      if (section != "top" || script_section_count > 0) invalid = 1
      script_section_count++
      section = "script"
      next
    }
    /^\[MITM\]$/ {
      if (section != "script" || mitm_section_count > 0) invalid = 1
      mitm_section_count++
      section = "mitm"
      next
    }
    /^\[[^]]+\]$/ {
      invalid = 1
      section = "other"
      next
    }
    {
      if (section == "script") {
        if ($0 ~ /^macOS Location Spoofer Prepare[[:space:]]*=/) {
          prepare_count++
        } else if ($0 ~ /^macOS Location Spoofer Response[[:space:]]*=/) {
          response_count++
        } else {
          invalid = 1
        }
        next
      }
      if (section == "mitm") {
        hostname = $0
        sub(/^[[:space:]]*/, "", hostname)
        sub(/[[:space:]]*$/, "", hostname)
        hostname_count++
        if (hostname != expected_hostname) invalid = 1
        next
      }
      invalid = 1
    }
    END {
      if (invalid || name_count != 1 || desc_count != 1 || homepage_count != 1 || script_section_count != 1 || mitm_section_count != 1 || prepare_count != 1 || response_count != 1 || hostname_count != 1) {
        exit 1
      }
      print expected_name
      print "macOS Location Spoofer Prepare"
      print "macOS Location Spoofer Response"
      print expected_hostname
    }
  ' "$1" 2>/dev/null; then
    printf 'warning: module summary is unavailable; inspect the module locally before sharing.\n' >&2
    return 1
  fi
}

if [ "${1:-}" = "--module-summary" ]; then
  [ "$#" -eq 2 ] || die "--module-summary requires a module path"
  [ -f "$2" ] || die "module summary is unavailable"
  module_summary "$2" || exit 2
  exit 0
fi

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
  printf 'Found: macos-shadowrocket/generated/macos-location-spoofer.sgmodule\n'
  module_summary "$MODULE"
else
  printf 'Missing. Run ./macos-shadowrocket/generate-module.sh first.\n'
fi

section "Core Location endpoint"
if strings -a /usr/libexec/locationd 2>/dev/null | grep -q 'https://gs-loc.apple.com/clls/wloc'; then
  printf 'locationd contains the expected /clls/wloc endpoint.\n'
else
  printf 'WARNING: expected endpoint not found in locationd. This macOS build may use a different path.\n'
fi

section "DNS"
for host in gs-loc.apple.com gs-loc-cn.apple.com bluedot.is.autonavi.com bluedot.is.autonavi.com.gds.alibabadns.com; do
  if dscacheutil -q host -a name "$host" 2>/dev/null | grep -q '^ip_address:'; then
    printf '%-38s resolvable\n' "$host"
  else
    printf '%-38s no address returned\n' "$host"
  fi
done

section "System proxy flags"
if scutil --proxy >/dev/null 2>&1; then
  scutil --proxy | awk '
    /^(HTTPEnable|HTTPSEnable|SOCKSEnable|ProxyAutoConfigEnable) :/ {
      printf "%s: %s\n", $1, $3
    }
  '
else
  printf 'Proxy flags could not be read.\n'
fi

section "locationd service"
if launchctl print system/com.apple.locationd 2>/dev/null | grep -q 'state = running'; then
  printf 'locationd is running.\n'
else
  printf 'locationd state could not be confirmed.\n'
fi

printf '\nThis script is read-only. It does not validate CA trust or prove interception.\n'
