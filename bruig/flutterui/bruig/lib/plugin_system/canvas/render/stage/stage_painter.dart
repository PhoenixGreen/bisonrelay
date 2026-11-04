import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_scene.dart';

// stage_painter.dart draws a 3D stage -- its sky, its floor and what the
// floor is made of, its back wall, its light -- and works out where the
// elements standing on it are on the page. Both come from the one camera at
// the one frame, so feet stay on the floor where it is drawn.

/// stageView is how [stage]'s camera sees it on [frame].
StageView stageView(StageElement stage, int frame) =>
    StageView(stage.bounds, stage.cameraAt(frame));

/// paintStage draws [stage] as it is seen on [frame], filling [box]: its
/// set drawn in 3D by [images] where it keeps stages (stage_scene.dart),
/// and a sketch of it -- the sky, the floor and the wall, plain -- where 3D
/// cannot be drawn, or not yet.
void paintStage(Canvas canvas, Rect box, StageElement stage, int frame,
    {CanvasImageSource? images}) {
  var source = images is CanvasStageSource ? images as CanvasStageSource : null;
  var scene = source?.resolveStage(stage);
  if (scene != null) {
    // As many pixels as the box covers, at the canvas's own scale.
    var m = canvas.getTransform();
    var scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    var most = 4096 / math.max(box.width, box.height);
    scene.paint(canvas, box, stage, frame,
        pixelRatio: scale.clamp(0.25, math.max(0.25, most)));
  } else {
    _sketch(canvas, box, stage, frame);
  }
  canvas.save();
  canvas.clipRect(box);
  _light(canvas, box, stage.light);
  canvas.restore();
}

/// _sketch is [stage] where 3D cannot be drawn: its sky, its floor and its
/// wall in their colours, through its camera, so what stands on it is where
/// it will be.
void _sketch(Canvas canvas, Rect box, StageElement stage, int frame) {
  var view = StageView(box, stage.cameraAt(frame));
  var s = stage.size;
  canvas.save();
  canvas.clipRect(box);
  canvas.drawRect(box, Paint()..color = stage.sky);
  if (stage.wall) {
    var wall = view.polygon([(-s, 0, -s), (s, 0, -s), (s, 3, -s), (-s, 3, -s)]);
    if (wall.length >= 3) {
      canvas.drawPath(Path()..addPolygon(wall, true), Paint()..color = stage.wallColor);
    }
  }
  var floor = view.polygon([(-s, 0, -s), (s, 0, -s), (s, 0, s), (-s, 0, s)]);
  if (floor.length >= 3) {
    canvas.drawPath(Path()..addPolygon(floor, true), Paint()..color = stage.floor);
  }
  canvas.restore();
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

/// canStand is whether [e] can stand on a stage: anything on the canvas,
/// but for a stage itself and scenery that is behind everything -- and a
/// sound on the timeline, which is not on the canvas at all.
bool canStand(CanvasElement e) =>
    e is! StageElement &&
    e is! ParallaxElement &&
    !(e is BackgroundElement && (e.isStage || e.isParallax)) &&
    !isTimelineSound(e);

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

  /// foot is where its spot is seen: the point a drag holds it by -- the
  /// middle of its bottom edge, standing; its middle, lying on the floor.
  final Offset foot;

  /// shadow is a standing flat's shadow on the floor, as the camera sees
  /// it, or null: lying down, on the wall, a 3D character -- which casts
  /// its own -- or in a light that throws none.
  final Path? shadow;

  /// matrix lays the element's own box onto the stage, for a flat: see
  /// StageView.perspective. Null for a 3D character, drawn by its own
  /// scene through [view].
  final Float64List? matrix;

  const Staged(this.spot, this.stage, this.view, this.quad, this.box,
      this.depth, this.matrix, this.foot,
      [this.shadow]);
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
    // A card as big as a person with their arms out a little, standing on
    // the spot turned to the camera: what is picked and outlined, its feet
    // in the middle of its bottom edge.
    var (rx, ry, rz) = view.right;
    var corners = <StagePoint>[
      for (var (across, up) in const [
        (-0.45, 1.75),
        (0.45, 1.75),
        (0.45, 0.0),
        (-0.45, 0.0)
      ])
        view.see(spot.x + rx * across, spot.lift + ry * across + up,
            spot.z + rz * across)
    ];
    if (corners.any((p) => p.depth <= StageView.nearest)) return null;
    var quad = [for (var p in corners) p.page];
    var feet = view.see(spot.x, spot.lift, spot.z);
    return Staged(
        spot, stage, view, quad, _around(quad), feet.depth, null, feet.page);
  }
  // A flat: its own box, its longer side as long as the spot says, stood
  // up, turned to the camera, laid down or hung on the wall. A straight
  // line's box has no height, or no width: it is given some, round its
  // stroke, for a plane to stand in.
  var rect = Rect.fromLTWH(e.x, e.y, e.width, e.height);
  var thin = e is LineElement ? math.max(e.strokeWidth * 4, 8.0) : 1.0;
  if (rect.width < thin) {
    rect = Rect.fromCenter(
        center: rect.center, width: thin, height: rect.height);
  }
  if (rect.height < thin) {
    rect = Rect.fromCenter(
        center: rect.center, width: rect.width, height: thin);
  }
  var longest = math.max(rect.width, rect.height);
  var tall = spot.height * rect.height / longest,
      wide = spot.height * rect.width / longest;
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
  var foot = spot.stand == SpotStand.floor
      ? middle.page
      : view.see(fx, fy, fz).page;
  // Standing, it throws a shadow on the floor under it: as wide as it is,
  // a little deep, pushed the way the light throws it.
  Path? shadow;
  if (stage.light.shadows &&
      (spot.stand == SpotStand.upright || spot.stand == SpotStand.camera)) {
    var deep = math.max(0.12, math.min(wide, tall) * 0.14);
    var push = tall * stage.light.shadowSlant * 0.25;
    var points = <Offset>[];
    for (var k = 0; k < 24; k++) {
      var a = k / 24 * 2 * math.pi;
      var across = math.cos(a) * wide * 0.52, depth = math.sin(a) * deep;
      var p = view.see(fx + ax * across - az * depth + push, 0,
          fz + az * across + ax * depth);
      if (p.depth <= StageView.nearest) break;
      points.add(p.page);
    }
    if (points.length == 24) shadow = Path()..addPolygon(points, true);
  }
  return Staged(spot, stage, view, quad, _around(quad), middle.depth, matrix,
      foot, shadow);
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
    if (e.base.spot == null) continue;
    var at = staged(e, elements, frame, backdrop: backdrop, page: page);
    if (at == null) continue;
    (onStages[at.spot.stage] ??= []).add((at.depth, e));
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
