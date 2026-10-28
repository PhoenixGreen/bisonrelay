import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// character_drawing_settings.dart is a sketched character's Drawing
// section: drawing on it by hand, panel by panel, with a drawing's own
// tools -- the very ones; see vectorSettings -- and the panel, the zoom and
// what of the generated drawing is left out under it. The bar over the
// canvas has the same; see character_draw_bar.dart.

/// panelOptions is the views [e] is drawn from, each way round -- the
/// other way its mirror until it is drawn on -- named and marked as drawn
/// on or mirrored; and then, with [adding], every view it does not have yet,
/// to add.
List<(String, String)> panelOptions(CharacterElement e, {bool adding = true}) {
  String markAt(String key, String name) => switch (e.drawingAt(key)) {
        (var d, _) when d.isEmpty => name,
        (_, true) => "$name · mirrored",
        _ => "$name · drawn",
      };
  return [
    for (var v in e.views) ...[
      (v.key, markAt(v.key, v.label)),
      if (v.turn != 0 && v.turn != 180)
        (oppositeKey(v.key)!, markAt(oppositeKey(v.key)!, "${v.label}, other way")),
    ],
    if (adding)
      for (var v in CharacterView.all)
        if (!e.views.contains(v)) ("add:${panelKey(v.turn, v.tilt)}", "+ Add ${v.label}"),
  ];
}

/// showPanel turns [e] to the view named [key] -- see panelKey -- where
/// the playhead is; "add:" before it, adds the view first.
CharacterElement showPanel(
    CanvasController controller, CharacterElement e, String key) {
  var adding = key.startsWith("add:");
  if (adding) key = key.substring(4);
  var at = key.indexOf("@");
  var panel = at < 0 ? key : key.substring(0, at);
  var [turn, tilt] = [for (var p in panel.split(",")) double.parse(p)];
  if (adding) e = e.withView(CharacterView.of(turn, tilt));
  var pose = e.poseAtFrame(controller.frame);
  // A view of a pose: in that pose.
  if (at >= 0) {
    var name = key.substring(at + 1);
    for (var v in e.views) {
      if (v.pose == name && v.posed != null) pose = v.posed!;
    }
  }
  pose = pose.withTurn(turn).withTilt(tilt);
  return controller.characterPosed(e, e.inView(pose));
}

/// viewOfKey is the view [key] names -- see viewKeyOf -- turned the way
/// round its mirror is not.
CharacterView viewOfKey(CharacterElement e, String key) {
  var at = key.indexOf("@");
  var [turn, tilt] = [
    for (var p in (at < 0 ? key : key.substring(0, at)).split(",")) double.parse(p)
  ];
  var v = CharacterView.of(turn, tilt);
  if (at < 0) return v;
  var name = key.substring(at + 1);
  return e.views.firstWhere((w) => w.pose == name && w.turn == v.turn && w.tilt == v.tilt,
      orElse: () => v);
}

/// drawingTarget is the drawing the tools edit for [e]: the one laid over
/// it while it is drawn on, or -- before -- the one that would be, which
/// picking a tool lays over it. See CanvasController.drawOnCharacter.
VectorElement drawingTarget(CanvasController controller, CharacterElement e) {
  if (controller.document.elementById(drawingProxyId(e.id))
      case VectorElement on) {
    return on;
  }
  return drawingProxy(
      e, controller.frame, math.max(1, controller.document.frameRate));
}
