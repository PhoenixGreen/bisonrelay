# flutter_eval, patched for bruig

This is flutter_eval 0.8.2 (https://pub.dev/packages/flutter_eval, BSD 3-Clause
licence: see LICENSE), copied here because 0.8.2 does not compile against the
Flutter bruig is built with (3.47). Its example and tests are left out.

Changes:

- lib/src/widgets/container.dart: `$Container` gains `isAntiAlias`, the one
  member Flutter 3.47's `Container` has that 0.8.2's wrapper lacked.

Used by the Code element's Run panel to draw a Flutter app's widgets
(lib/plugin_system/canvas/media/code_dart_runner.dart). When a release of
flutter_eval builds against bruig's Flutter, go back to it from pub.dev.
