import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/element_samples.dart';

// canvas_palette_keys_test.dart guards "Replace everywhere" for a colour,
// which walks a document's saved JSON and takes any large whole number for
// a colour unless its key is on a list of keys that never hold one
// (canvas_palette.dart). A setting added later that holds a large number
// and is not a colour would be changed by it without a word. This fails
// when such a key first appears, so that somebody decides which it is.

/// _colourKeys are the keys known to hold colours, across the sample
/// elements and the built-in canvases.
const _colourKeys = {
  "accent",
  "axisColor",
  "bc",
  "bg",
  "body",
  "color",
  "color2",
  "colour",
  "fallColor",
  "fg",
  "fill",
  "floor",
  "gridColor",
  "gutterColor",
  "headerFill",
  "hoverFill",
  "iconColor",
  "ink",
  "keeper",
  "oc",
  "outline",
  "paper",
  "player",
  "riseColor",
  "sc",
  "secondary",
  "sky",
  "wallColor",
  "zebraFill",
};

void main() {
  test("every number Replace everywhere would recolour is a colour", () {
    var seen = <String>{
      for (var (_, e) in [...elementSamples(), ...filledSamples()])
        ...colourKeysOf(e.toJson()),
      for (var preset in builtinPresets)
        ...colourKeysOf(preset.build().toJson()),
      ...colourKeysOf(const CanvasDocument().toJson()),
    };
    expect(seen.difference(_colourKeys), isEmpty,
        reason: "these keys hold a number of 0x01000000 or more. If it is a "
            "colour, add the key to _colourKeys here. If it is not, add it "
            "to _notColours in model/canvas_palette.dart, or replacing a "
            "colour may change it.");
  });
}
