import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart';

// asset_placing.dart puts a library asset on the canvas, the one way every
// road does it: the Assets and Stock sidebars, a drop on the canvas, a
// script. It sits beside asset_elements.dart rather than in it because the
// controller imports that file, and this one needs the controller.

/// placeAsset puts [asset] on the canvas: the element that shows it, centred
/// on [center] (the page's middle without one), selected unless [select] is
/// false. A MIDI file is played by an instrument and is not an element: it
/// becomes a MIDI channel of its own. Returns the new element's id; null
/// for a MIDI file.
Future<String?> placeAsset(CanvasController controller, LibraryAsset asset,
    {Offset? center, bool select = true}) async {
  if (isMidiId(asset.id)) {
    await controller.addMidiChannelFrom(asset.source);
    return null;
  }
  var element = elementForAsset(asset, controller.document, center: center);
  controller.addElement(element, select: select);
  return element.id;
}
