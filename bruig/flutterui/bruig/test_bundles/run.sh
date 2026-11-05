#!/bin/sh
# run.sh runs the whole suite as bundles (see generate.dart): a few compiles
# instead of one for every test file. Run from the package root:
#
#   sh test_bundles/run.sh [flutter test options]
set -e
alone=$(sed -n 's/^ *"\([a-z0-9_]*_test\.dart\)",.*/test\/\1/p' test_bundles/generate.dart)
exec flutter test "$@" test_bundles $alone
