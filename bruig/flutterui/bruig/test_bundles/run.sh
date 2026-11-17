#!/bin/sh
# run.sh runs the whole suite as bundles (see generate.dart): a few compiles
# instead of one for every test file. Run from the package root:
#
#   sh test_bundles/run.sh [flutter test options]
#
# How many run at once is the machine's: a widget test process wants about
# 2.5 GB to itself, and one fast core. More at once than that is slower, not
# faster -- on an 8 GB M1, 3 at once took 270 s, 4 took 301 s and 8 took
# 762 s, swapping. A --concurrency given here wins.
set -e
case "$(uname)" in
  Darwin)
    mem=$(sysctl -n hw.memsize)
    fast=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null ||
      sysctl -n hw.physicalcpu)
    ;;
  *)
    mem=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024))
    fast=$(nproc)
    ;;
esac
at=$((mem * 2 / 5 / 1073741824))
[ "$at" -gt "$fast" ] && at=$fast
[ "$at" -lt 1 ] && at=1
alone=$(sed -n 's/^ *"\([a-z0-9_]*_test\.dart\)",.*/test\/\1/p' test_bundles/generate.dart)
exec flutter test --concurrency="$at" "$@" test_bundles $alone
