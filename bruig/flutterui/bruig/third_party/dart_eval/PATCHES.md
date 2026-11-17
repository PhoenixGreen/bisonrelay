# dart_eval, patched for bruig

This is dart_eval 0.8.5 (https://pub.dev/packages/dart_eval, BSD 3-Clause
licence: see LICENSE), copied here to fix a compiler bug that broke code a
student writes in the Code element's lessons. Its example, tests and bin are
left out.

Changes:

- lib/src/eval/compiler/reference.dart, `IdentifierReference.setValue`, the
  instance field path: the value was boxed in place to store it, but the
  unboxed Variable was returned. An assignment whose value is used --
  `onPressed: () => setState(() => coins += 2)` -- then boxed it a second
  time and failed at run time with "type '$int' is not a subtype of type
  'int' in type cast". It now returns the boxed Variable, as the explicit
  `obj.field = ...` path above it already did.

- lib/src/eval/runtime/runtime.dart, `Runtime.opLimit` (2026-11-17,
  security review): the most instructions one call into the program may
  run, counted in `execute`'s and `bridgeCall`'s loops, then
  `OpLimitExceeded` is thrown. Null by default, as upstream. bruig sets it
  for the Code element's Flutter runner, which builds a received canvas's
  app on the UI isolate, where `while (true) {}` hung the app.

Used through pubspec.yaml's dependency_overrides, so flutter_eval uses it
too. When a release of dart_eval has the fix, go back to it from pub.dev.

Trimmed (2026-11-17): pubspec.lock is left out; bruig's own lock file
pins the versions.
