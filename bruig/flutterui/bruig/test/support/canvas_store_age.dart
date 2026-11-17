import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';

/// ageStores dates every file under the test's canvas root as written well
/// before [sweepGrace], so a sweep treats it as settled rather than as
/// something still being brought in.
Future<void> ageStores() async {
  var root = CanvasStorage.rootOverride;
  if (root == null) return;
  var then = DateTime.now().subtract(sweepGrace * 2);
  await for (var e in Directory(root).list(recursive: true)) {
    if (e is File) await e.setLastModified(then);
  }
}
