import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_pose_library_test.dart is the poses a sketch is put in:
// the ones in action, and the ones kept. See PoseLibrary.

void main() {
  late Directory library;
  setUpAll(() {
    library = Directory.systemTemp.createTempSync("pose_library_test");
    CanvasStorage.rootOverride = library.path;
  });
  tearDownAll(() {
    CanvasStorage.rootOverride = null;
    library.deleteSync(recursive: true);
  });

  test("a pose kept, and read back", () async {
    var store = SavedPresetStore.poses;
    var run = actionPoses.firstWhere((p) => p.name == "Run").pose;
    var kept = await store.save("My run", {"pose": run.toJson()});
    expect(kept, isNotNull);
    var back = CharacterPose.fromJson(store.presets.firstWhere((p) => p.id == kept!.id).data["pose"]);
    expect(back.swing(CharacterBone.thighL), run.swing(CharacterBone.thighL));
    expect(back.lift, run.lift);
    expect(await store.remove(kept!), isTrue);
    expect(store.presets.where((p) => p.id == kept.id), isEmpty);
  });

  test("the poses in action are shaped in depth, and named once", () {
    var names = {for (var p in [...posePresets, ...actionPoses]) p.name};
    expect(names.length, posePresets.length + actionPoses.length);
    for (var p in actionPoses) {
      expect(p.pose.swings, isNotEmpty, reason: "${p.name} reads from the side");
    }
  });
}
