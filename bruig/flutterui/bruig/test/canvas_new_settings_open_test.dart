import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_new_settings_open_test.dart is whether a canvas opens with the
// canvas settings line already out.
//
// The shape of the page and the width it exports at are decided once, at the
// start, and then almost never touched again -- which is why the line is shut
// the rest of the time, and exactly why it should be open at the one moment
// they are wanted. A canvas with nothing on it yet is that moment.
//
// A preset is not: it arrives with its shape chosen on purpose and something
// drawn in it, and the line would open over the thing that was chosen.

void main() {
  test("a canvas with nothing on it opens the settings line", () {
    expect(startsWithSettingsOpen(emptyCanvas()), isTrue);
  });

  test("a preset with something drawn in it does not", () {
    var banner = bannerCanvas();
    expect(banner.allScenes.any((s) => s.elements.isNotEmpty), isTrue,
        reason: "otherwise this test is not asking anything -- and a one-scene "
            "document keeps its elements off the scenes list");
    expect(startsWithSettingsOpen(banner), isFalse);
  });

  test("nor does a canvas opened from a file that has work in it", () {
    var document = CanvasDocument(scenes: [
      const CanvasScene(id: "a", name: "Scene 1", elements: []),
      CanvasScene(id: "b", name: "Scene 2", elements: [
        ShapeElement(const ElementBase(id: "s1", width: 10, height: 10)),
      ]),
    ]);
    expect(startsWithSettingsOpen(document), isFalse,
        reason: "work anywhere in the document counts, not just scene one");
  });
}
