import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';

// image_action_file.dart is an image action as a file of its own (.braction):
// sent in a chat or saved to disk, and read back in. An action is only
// settings -- layers and numbers, never a picture or code -- and a received
// one is read through the same parser as the app's own, then written out
// again, so nothing it carried but the settings survives.

const imageActionExtension = ".braction";
const _format = "bruig-image-action";

/// maxImageActionBytes is the largest action file read: a colour table makes
/// one tens of kilobytes; nothing an action holds comes near this.
const maxImageActionBytes = 2 * 1024 * 1024;

/// packImageAction is the file for the action [name] with [data] (lookData).
Uint8List packImageAction(String name, Map<String, dynamic> data) =>
    utf8.encode(const JsonEncoder.withIndent(" ").convert({
      "format": _format,
      "version": 1,
      "name": name,
      "data": data,
    }));

/// ReceivedImageAction is an action read from a file, ready to keep.
class ReceivedImageAction {
  final String name;
  final Map<String, dynamic> data;
  const ReceivedImageAction(this.name, this.data);

  int get steps => lookSteps(data);
}

/// readImageAction is the action in [bytes], or why there is none.
(ReceivedImageAction?, String?) readImageAction(Uint8List bytes) {
  if (bytes.length > maxImageActionBytes) {
    return (null, "That is too large to be an image action.");
  }
  Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return (null, "That is not an image action.");
  }
  if (json is! Map<String, dynamic> || json["format"] != _format) {
    return (null, "That is not an image action.");
  }
  if (json["data"] is! Map<String, dynamic>) {
    return (null, "That action has nothing in it.");
  }
  var name = jsonString(json["name"], "").trim();
  if (name.length > 80) name = name.substring(0, 80);
  if (name.isEmpty) name = "Action";
  var data = cleanLookData(json["data"] as Map<String, dynamic>);
  if (lookSteps(data) == 0) {
    return (null, "That action has nothing in it.");
  }
  return (ReceivedImageAction(name, data), null);
}

/// cleanLookData is [data] (see lookData) as the app itself would write it:
/// worn by a stand-in picture and read off again, so only what a look can
/// hold is kept, every number within its range.
Map<String, dynamic> cleanLookData(Map<String, dynamic> data) {
  const stand = ImageElement(
      ElementBase(id: "stand-in", width: 1000, height: 1000),
      assetId: "stand-in");
  return lookData(withLookApplied(stand, data));
}

/// stepLabel names layer [l] of [e] as a step.
String stepLabel(ImageElement e, ImageLayer l) {
  if (l.name.isNotEmpty) return l.name;
  if (isPictureCopy(e, l)) return "Copy of the picture";
  return switch (l.kind) {
    LayerKind.adjustment => l.adjust.kind.label,
    LayerKind.texture => l.texture.kind.label,
    LayerKind.fill => "Colour",
    var k => k.label,
  };
}

/// lookStepNames are the steps of [data] (see lookData), as stepLabel
/// names them.
List<String> lookStepNames(Map<String, dynamic> data) {
  const stand = ImageElement(
      ElementBase(id: "stand-in", width: 1000, height: 1000),
      assetId: "stand-in");
  var e = withLookApplied(stand, data);
  var base = e.stack.firstWhere((l) => l.isBase);
  return [
    for (var l in e.stack)
      if (inLook(e, l)) stepLabel(e, l),
    for (var f in base.effects) f.kind.label,
  ];
}
