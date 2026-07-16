#!/bin/bash

set -eu

printf 'Watching locationd logs. Open Maps and request the current location.\n'
printf 'Press Ctrl-C to stop. Private fields may be redacted by macOS.\n\n'

/usr/bin/log stream \
  --style compact \
  --level debug \
  --predicate 'process == "locationd"' 2>/dev/null \
  | grep --line-buffered -Ei 'wloc|gs-loc|network|wifi|knownCount|location|certificate|trust|pinning'
