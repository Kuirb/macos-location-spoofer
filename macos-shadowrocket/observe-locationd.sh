#!/bin/bash

set -eu
set -o pipefail

printf 'Watching locationd logs. Open Maps and request the current location.\n'
printf 'Press Ctrl-C to stop. Streamed metadata can be sensitive; sanitize it before sharing.\n\n'

/usr/bin/log stream \
  --style compact \
  --level debug \
  --predicate 'process == "locationd"' \
  | grep --line-buffered -Ei 'wloc|gs-loc|network|wifi|knownCount|location|certificate|trust|pinning'
