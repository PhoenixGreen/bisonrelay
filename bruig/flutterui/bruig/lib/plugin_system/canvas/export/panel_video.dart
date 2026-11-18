import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show settledFrameOf;
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource, drawWhenLoaded;
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart'
    show paintLeaf;
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

// panel_video.dart is a comic exported as a video read panel by panel, as
// Panel mode reads it (panel_reading.dart): each page held whole, then the
// view gliding to each panel in its reading order and holding there, and
// the next page fading in. Ken, 2026-11-18: "can you also use the panel
// view when exporting a comic as a video file?"
//
// Each page is drawn once, sharp enough for its closest panel, and every
// frame is cut from that picture: a book of eighty panels is thousands of
// frames, nearly all of them a still view of one page.

/// PanelPace is how long a panel video dwells: on each page whole, on each
/// panel, and moving from one to the next, in seconds.
enum PanelPace {
  quick("Quick", 1.5, 2.0, 0.5),
  steady("Steady", 2.5, 3.5, 0.8),
  slow("Slow", 3.5, 5.0, 1.0);

  final String label;
  final double page, panel, move;
  const PanelPace(this.label, this.page, this.panel, this.move);

  static PanelPace fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => steady);
}

/// PanelTimeline is when each step of [steps] shows at [rate] frames a
/// second: a move into it (none into the first), then a hold.
class PanelTimeline {
  final List<PanelStep> steps;
  final int rate;
  final PanelPace pace;
  final List<int> _starts = [], _moves = [], _holds = [];
  late final int frames;

  PanelTimeline(this.steps, this.rate, this.pace) {
    var at = 0;
    for (var (i, s) in steps.indexed) {
      var move = i == 0 ? 0 : math.max(1, (pace.move * rate).round());
      var hold =
          math.max(1, ((s.whole ? pace.page : pace.panel) * rate).round());
      _starts.add(at);
      _moves.add(move);
      _holds.add(hold);
      at += move + hold;
    }
    frames = at;
  }

  /// at is what frame [frame] shows.
  PanelMoment at(int frame) {
    if (steps.isEmpty) return (at: 0, from: -1, t: 1);
    var f = frame.clamp(0, math.max(0, frames - 1));
    var i = steps.length - 1;
    while (i > 0 && _starts[i] > f) {
      i--;
    }
    var into = f - _starts[i];
    if (into < _moves[i]) {
      var t = Curves.easeInOut.transform((into + 1) / (_moves[i] + 1));
      return (at: i, from: i - 1, t: t);
    }
    return (at: i, from: -1, t: 1);
  }

  /// still is whether frame [frame] is the same picture as the one before.
  bool still(int frame) {
    if (frame <= 0) return false;
    var a = at(frame), b = at(frame - 1);
    return a.from < 0 && b.from < 0 && a.at == b.at;
  }
}

/// PanelFrames draws a [PanelTimeline]'s frames at [scale] of the export
/// size, from each page drawn once (two kept, for a fade between them).
class PanelFrames {
  final CanvasDocument document;
  final PanelTimeline timeline;
  final double scale;
  final CanvasImageSource? images;
  final Map<int, ui.Image> _pages = {};

  PanelFrames(this.document, this.timeline, {required this.scale, this.images});

  int get width =>
      math.max(1, (document.size.exportSize.width * scale).round());
  int get height =>
      math.max(1, (document.size.exportSize.height * scale).round());

  /// _page is page [scene] as a picture, sharp at its closest panel: up to
  /// three times the video's own size, and no side past 6000 pixels.
  Future<ui.Image> _page(int scene) async {
    if (_pages[scene] case var kept?) return kept;
    var page = document.size.size;
    var zoom = 1.0;
    for (var s in timeline.steps) {
      if (s.scene != scene) continue;
      zoom = math.max(zoom, page.width / panelView(s, page).width);
    }
    var px = width / page.width * zoom.clamp(1.0, 3.0);
    px = math.min(px, 6000 / math.max(page.width, page.height));
    void draw(ui.Canvas canvas) {
      canvas.scale(px);
      paintLeaf(canvas, document, scene,
          frameOf: (i) => settledFrameOf(document.goToScene(i)),
          images: images);
    }

    await drawWhenLoaded(images, draw);
    var recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    var picture = recorder.endRecording();
    ui.Image image;
    try {
      image = await picture.toImage(math.max(1, (page.width * px).round()),
          math.max(1, (page.height * px).round()));
    } finally {
      picture.dispose();
    }
    // Only the pages this frame or a fade into it needs.
    var needed = {scene, if (scene > 0) scene - 1};
    for (var k in [..._pages.keys]) {
      if (!needed.contains(k)) _pages.remove(k)!.dispose();
    }
    _pages[scene] = image;
    return image;
  }

  /// frame is frame [i]; the caller disposes it.
  Future<ui.Image> frame(int i) async {
    var m = timeline.at(i);
    var steps = timeline.steps;
    var to = steps[m.at];
    var was = m.from >= 0 ? steps[m.from] : null;
    var pictures = {
      if (was != null && was.scene != to.scene)
        was.scene: await _page(was.scene),
      to.scene: await _page(to.scene),
    };
    var page = document.size.size;
    void drawPage(ui.Canvas canvas, int scene) {
      var image = pictures[scene];
      if (image == null) return;
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Offset.zero & page,
          Paint()..filterQuality = FilterQuality.medium);
    }

    var size = Size(width.toDouble(), height.toDouble());
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF000000));
    paintPanelMoment(canvas, size, document, steps, m, page: drawPage);
    var picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  void dispose() {
    for (var image in _pages.values) {
      image.dispose();
    }
    _pages.clear();
  }
}
