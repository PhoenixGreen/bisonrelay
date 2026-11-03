import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';

// stage_painter.dart draws a 3D stage -- its sky, its floor and what the
// floor is made of, its back wall, its light -- and works out where the
// characters standing on it are on the page.
//
// Both from the one camera, at the one frame, so a character's feet are on
// the floor where the floor is drawn, however the camera moves.

/// stageView is how [stage]'s camera sees it on [frame].
StageView stageView(StageElement stage, int frame) =>
    StageView(stage.bounds, stage.cameraAt(frame));

/// paintStage draws [stage] as it is seen on [frame], filling [box].
void paintStage(Canvas canvas, Rect box, StageElement stage, int frame) {
  var view = StageView(box, stage.cameraAt(frame));
  var s = stage.size;
  canvas.save();
  canvas.clipRect(box);
  canvas.drawRect(box, Paint()..color = stage.sky);

  if (stage.wall) {
    // The back wall, standing at the far edge of the floor, three metres
    // high; a skirting board where it meets the floor.
    var wall = view.polygon([(-s, 0, -s), (s, 0, -s), (s, 3, -s), (-s, 3, -s)]);
    if (wall.length >= 3) {
      canvas.drawPath(Path()..addPolygon(wall, true), Paint()..color = stage.wallColor);
    }
    var skirt = view.polygon(
        [(-s, 0, -s), (s, 0, -s), (s, 0.12, -s), (-s, 0.12, -s)]);
    if (skirt.length >= 3) {
      canvas.drawPath(Path()..addPolygon(skirt, true),
          Paint()..color = Color.lerp(stage.wallColor, const Color(0xFF000000), 0.18)!);
    }
  }

  var floor = view.polygon([(-s, 0, -s), (s, 0, -s), (s, 0, s), (-s, 0, s)]);
  if (floor.length >= 3) {
    var floorPath = Path()..addPolygon(floor, true);
    canvas.drawPath(floorPath, Paint()..color = stage.floor);
    canvas.save();
    canvas.clipPath(floorPath);
    _pattern(canvas, view, stage);
    canvas.restore();
  }

  _light(canvas, box, stage.light);
  canvas.restore();
}

/// _line draws a line on the stage from [a] to [b], cut where it goes
/// behind the camera.
void _line(Canvas canvas, StageView view, (double, double, double) a,
    (double, double, double) b, Paint paint) {
  var seen = view.polygon([a, b]);
  if (seen.length >= 2) canvas.drawLine(seen.first, seen.last, paint);
}

void _pattern(Canvas canvas, StageView view, StageElement stage) {
  var s = stage.size;
  var dark = Color.lerp(stage.floor, const Color(0xFF000000), 0.14)!;
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.6, view.box.height * 0.0015)
    ..color = dark;
  switch (stage.pattern) {
    case FloorPattern.plain:
      break;
    case FloorPattern.grid:
      for (var x = -s; x <= s + 1e-6; x += 1) {
        _line(canvas, view, (x, 0, -s), (x, 0, s), line);
      }
      for (var z = -s; z <= s + 1e-6; z += 1) {
        _line(canvas, view, (-s, 0, z), (s, 0, z), line);
      }
    case FloorPattern.tiles:
      var tile = Paint()..color = dark;
      for (var x = -s; x < s - 1e-6; x += 1) {
        for (var z = -s; z < s - 1e-6; z += 1) {
          if (((x + s) + (z + s)).round().isOdd) continue;
          var q = view.polygon([(x, 0, z), (x + 1, 0, z), (x + 1, 0, z + 1), (x, 0, z + 1)]);
          if (q.length >= 3) canvas.drawPath(Path()..addPolygon(q, true), tile);
        }
      }
    case FloorPattern.boards:
      // Boards running away from the camera's start, their ends staggered.
      for (var x = -s; x <= s + 1e-6; x += 0.3) {
        _line(canvas, view, (x, 0, -s), (x, 0, s), line);
      }
      var row = 0;
      for (var x = -s; x < s; x += 0.3, row++) {
        for (var z = -s + (row % 3) * 0.7; z < s; z += 2.1) {
          _line(canvas, view, (x, 0, z), (x + 0.3, 0, z), line);
        }
      }
    case FloorPattern.grass:
      // Blades scattered by a fixed rule, so the same stage has the same
      // grass in every frame and every export.
      var blade = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.6, view.box.height * 0.002)
        ..color = dark;
      var count = (s * s * 40).round().clamp(50, 3000);
      for (var k = 0; k < count; k++) {
        var x = -s + 2 * s * _unit(k * 2);
        var z = -s + 2 * s * _unit(k * 2 + 1);
        _line(canvas, view, (x, 0, z), (x + 0.02, 0.08, z), blade);
      }
  }
}

void _light(Canvas canvas, Rect box, StageLight light) {
  if (light.strength <= 0) return;
  canvas.drawRect(box,
      Paint()..color = light.tint.withValues(alpha: light.strength));
}

/// lightFilter is [light] laid over a character standing in it, or null
/// where it changes nothing.
ColorFilter? lightFilter(StageLight light) => light.strength <= 0
    ? null
    : ColorFilter.mode(
        light.tint.withValues(alpha: light.strength), BlendMode.srcATop);

double _unit(int n) {
  var h = (n * 0x9E3779B1) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  return (h ^ (h >> 16)) / 0xFFFFFFFF;
}

/// Staging is a character standing on a stage, as it is seen: the box it is
/// drawn in, how far from the camera, which way round, and its shadow.
class Staging {
  final Rect box;
  final double depth;

  /// turn is added to the character's own turn: the camera's swing, and
  /// which way it faces on the floor.
  final double turn;
  final StageLight light;

  /// shadow is its shadow on the floor, or null in a light with none.
  final Path? shadow;

  /// tilt is how far above it the camera looks down on it, in degrees:
  /// added to the character's own tilt, so it is seen from where the
  /// camera is.
  final double tilt;

  const Staging(this.box, this.depth, this.turn, this.light, this.shadow,
      [this.tilt = 0]);
}

/// stageNamed is the stage called [id], as it is drawn: a Background
/// element showing one, or the canvas's own background where [backdrop] is
/// one -- stretched to [page]. Null where there is no such stage, or it is
/// showing its pattern instead.
StageElement? stageNamed(String id, Iterable<CanvasElement> elements,
    {CanvasBackground? backdrop, Rect? page}) {
  if (id == backgroundStageId) {
    if (backdrop == null || page == null || !backdrop.isStage) return null;
    return backdrop.stageOn(page);
  }
  for (var el in elements) {
    if (el.id != id) continue;
    if (el is BackgroundElement && el.isStage) return el.staged;
    // A stage made in code, as the tests make one. A saved one is read as
    // the Background element it has become.
    if (el is StageElement) return el;
  }
  return null;
}

/// stagesIn is every stage a character could stand on: the background's
/// first, then each Background element showing one, as (id, name).
List<(String, String)> stagesIn(Iterable<CanvasElement> elements,
        {CanvasBackground? backdrop}) =>
    [
      if (backdrop?.isStage == true) (backgroundStageId, "Canvas background"),
      for (var el in elements)
        if ((el is BackgroundElement && el.isStage) || el is StageElement)
          (el.id, el.name),
    ];

/// stagingIn is [staging] in [doc], against the background behind the
/// canvas being shown.
Staging? stagingIn(CanvasDocument doc, CharacterElement e, int frame) =>
    staging(e, doc.elements, frame,
        backdrop: doc.drawnBackground, page: doc.size.rect);

/// staging is [e] as it stands on its stage among [elements] on [frame], or
/// null when it is not on one that is there -- or is behind the camera.
Staging? staging(
    CharacterElement e, Iterable<CanvasElement> elements, int frame,
    {CanvasBackground? backdrop, Rect? page}) {
  var on = e.onStage;
  if (on == null) return null;
  var stage = stageNamed(on.stage, elements, backdrop: backdrop, page: page);
  if (stage == null) return null;
  var view = stageView(stage, frame);
  var feet = view.see(on.x, 0, on.z);
  if (feet.depth <= StageView.nearest) return null;
  var tall = view.scaleAt(feet.depth) * on.height;
  var wide = tall * (e.height <= 0 ? 0.5 : e.width / e.height);
  var box = Rect.fromLTWH(
      feet.page.dx - wide / 2, feet.page.dy - tall, wide, tall);
  Path? shadow;
  if (stage.light.shadows && e.shadow != CharacterShadow.none) {
    // An ellipse on the floor round the feet, pushed the way the light
    // throws it.
    var r = on.height * 0.22;
    var off = on.height * stage.light.shadowSlant * 0.25;
    var points = <Offset>[];
    for (var k = 0; k < 20; k++) {
      var a = k / 20 * 2 * math.pi;
      var p = view.see(on.x + off + math.cos(a) * r * (1 + stage.light.shadowSlant.abs() * 0.4),
          0, on.z + math.sin(a) * r * 0.7);
      if (p.depth > StageView.nearest) points.add(p.page);
    }
    if (points.length >= 3) shadow = Path()..addPolygon(points, true);
  }
  // Seen from the camera's height: the angle down to the middle of the
  // body.
  var camera = stage.cameraAt(frame);
  var tilt = view.lookingDown(on.x, on.height / 2, on.z).clamp(-85.0, 85.0);
  return Staging(box, feet.depth, camera.yaw + on.facing, stage.light, shadow,
      tilt);
}

/// canStand is whether [e] can stand on a stage: anything drawn, but for
/// what is a stage, or behind everything, or a sound -- and the old drawn
/// characters, which stand on one their own way.
bool canStand(CanvasElement e) =>
    e is! BackgroundElement &&
    e is! StageElement &&
    e is! ParallaxElement &&
    e is! AudioElement &&
    e is! CharacterElement;

/// Staged is an element standing on a stage, as the camera sees it: the
/// four corners of where it is on the page and the box round them, how far
/// from the camera, and the stage and its view.
class Staged {
  final StageSpot spot;
  final StageElement stage;
  final StageView view;

  /// quad is its corners on the page: top-left, top-right, bottom-right,
  /// bottom-left; box is round them.
  final List<Offset> quad;
  final Rect box;
  final double depth;

  /// matrix lays the element's own box onto the stage, for a flat: see
  /// StageView.perspective. Null for a 3D character, drawn by its own
  /// scene through [view].
  final Float64List? matrix;

  const Staged(this.spot, this.stage, this.view, this.quad, this.box,
      this.depth, this.matrix);
}

/// stagedIn is [staged] in [doc], against the background behind the canvas
/// being shown.
Staged? stagedIn(CanvasDocument doc, CanvasElement e, int frame) =>
    staged(e, doc.elements, frame,
        backdrop: doc.drawnBackground, page: doc.size.rect);

/// staged is where [e] stands on its stage among [elements] on [frame], or
/// null where it is on the page, its stage is not there, or the camera
/// cannot see it whole.
Staged? staged(CanvasElement e, Iterable<CanvasElement> elements, int frame,
    {CanvasBackground? backdrop, Rect? page}) {
  var spot = e.spotAt(frame);
  if (spot == null || !canStand(e)) return null;
  var stage = stageNamed(spot.stage, elements, backdrop: backdrop, page: page);
  if (stage == null) return null;
  var view = stageView(stage, frame);
  var turn = spot.facing * math.pi / 180;
  if (e is Character3dElement) {
    // A body about as tall as a person, and as wide as one with its arms
    // out a little, standing on the spot: what is picked and outlined.
    var feet = view.see(spot.x, spot.lift, spot.z);
    if (feet.depth <= StageView.nearest) return null;
    var corners = <Offset>[];
    for (var (dx, dy, dz) in const [
      (-0.4, 0.0, -0.25), (0.4, 0.0, -0.25), (0.4, 0.0, 0.25),
      (-0.4, 0.0, 0.25), (-0.4, 1.75, -0.25), (0.4, 1.75, -0.25),
      (0.4, 1.75, 0.25), (-0.4, 1.75, 0.25),
    ]) {
      var x = dx * math.cos(turn) + dz * math.sin(turn);
      var z = -dx * math.sin(turn) + dz * math.cos(turn);
      var p = view.see(spot.x + x, spot.lift + dy, spot.z + z);
      if (p.depth <= StageView.nearest) return null;
      corners.add(p.page);
    }
    var box = _around(corners);
    return Staged(spot, stage, view,
        [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft], box,
        feet.depth, null);
  }
  // A flat: its own box, as tall as the spot says and as wide as its shape,
  // stood up, turned to the camera, laid down or hung on the wall.
  var rect = Rect.fromLTWH(e.x, e.y, e.width, e.height);
  if (rect.width <= 0 || rect.height <= 0) return null;
  var tall = spot.height, wide = tall * rect.width / rect.height;
  var (ax, ay, az) = switch (spot.stand) {
    SpotStand.camera => view.right,
    SpotStand.wall => (1.0, 0.0, 0.0),
    _ => (math.cos(turn), 0.0, -math.sin(turn)),
  };
  // Its foot in the middle of its bottom edge, and which way is up it.
  var (fx, fy, fz) = spot.stand == SpotStand.wall
      ? (spot.x, spot.lift, -stage.size + 0.01)
      : (spot.x, spot.lift + (spot.stand == SpotStand.floor ? 0.005 : 0), spot.z);
  var (upx, upy, upz) = spot.stand == SpotStand.floor
      ? (-math.sin(turn), 0.0, -math.cos(turn))
      : (0.0, 1.0, 0.0);
  (double, double, double) at(double across, double up) => (
        fx + ax * across + upx * up,
        fy + ay * across + upy * up,
        fz + az * across + upz * up
      );
  var tl = at(-wide / 2, tall), tr = at(wide / 2, tall);
  var br = at(wide / 2, 0), bl = at(-wide / 2, 0);
  var seen = [for (var c in [tl, tr, br, bl]) view.see(c.$1, c.$2, c.$3)];
  if (seen.any((p) => p.depth <= StageView.nearest)) return null;
  var matrix = view.perspective(rect, tl, tr, bl);
  if (matrix == null) return null;
  var middle = view.see(fx + upx * tall / 2, fy + upy * tall / 2,
      fz + upz * tall / 2);
  var quad = [for (var p in seen) p.page];
  return Staged(spot, stage, view, quad, _around(quad), middle.depth, matrix);
}

Rect _around(List<Offset> points) => Rect.fromLTRB(
    points.map((p) => p.dx).reduce(math.min),
    points.map((p) => p.dy).reduce(math.min),
    points.map((p) => p.dx).reduce(math.max),
    points.map((p) => p.dy).reduce(math.max));

/// inStageOrder is [elements] in the order they are drawn: each element
/// standing on a stage taken out of its place and drawn just after its
/// stage, the furthest from the camera first, so the nearer stand in front
/// whatever order they were added in and however the camera moves.
///
/// Those on the background's own stage come first of all, since that stage
/// is behind everything.
List<CanvasElement> inStageOrder(List<CanvasElement> elements, int frame,
    {CanvasBackground? backdrop, Rect? page}) {
  var onStages = <String, List<(double, CanvasElement)>>{};
  for (var e in elements) {
    if (e is CharacterElement && e.onStage != null) {
      var at = staging(e, elements, frame, backdrop: backdrop, page: page);
      if (at == null) continue;
      (onStages[e.onStage!.stage] ??= []).add((at.depth, e));
    } else if (e.base.spot != null) {
      var at = staged(e, elements, frame, backdrop: backdrop, page: page);
      if (at == null) continue;
      (onStages[at.spot.stage] ??= []).add((at.depth, e));
    }
  }
  if (onStages.isEmpty) return elements;
  var moved = {for (var list in onStages.values) for (var (_, e) in list) e.id};
  var out = <CanvasElement>[];
  if (onStages[backgroundStageId] case var list?) {
    list.sort((a, b) => b.$1.compareTo(a.$1));
    out.addAll([for (var (_, c) in list) c]);
  }
  for (var e in elements) {
    if (moved.contains(e.id)) continue;
    out.add(e);
    if (onStages[e.id] case var list?) {
      list.sort((a, b) => b.$1.compareTo(a.$1));
      out.addAll([for (var (_, c) in list) c]);
    }
  }
  return out;
}
