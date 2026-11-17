#!/bin/sh
# quick.sh runs the model tests alone -- every test file with no widget test
# in it, one compile -- for a check in about half a minute while working.
# The whole suite (run.sh) is still the check before committing. From the
# package root:
#
#   sh test_bundles/quick.sh [flutter test options]
#
# quick.dart is written by generate.dart, with the bundles.
set -e
exec flutter test "$@" test_bundles/quick.dart
