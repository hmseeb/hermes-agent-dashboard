#!/usr/bin/env bash
# Listing readme and README must not name a Hermes pin other than the
# Dockerfile's: the daily bump job moves the Dockerfile, never the prose.
set -u
pin=$(grep -oE 'ARG HERMES_IMAGE_VERSION=\S+' "$(dirname "$0")/../Dockerfile" | cut -d= -f2)
fail=0
for f in TEMPLATE_OVERVIEW.md README.md; do
  for v in $(grep -oE '`v[0-9]+\.[0-9]+\.[0-9]+`' "$(dirname "$0")/../$f" | tr -d '`' | sort -u); do
    [ "$v" = "$pin" ] || { echo "FAIL $f names $v, Dockerfile pins $pin"; fail=1; }
  done
done
[ $fail = 0 ] && echo PASS
exit $fail
