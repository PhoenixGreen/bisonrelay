import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_pixels.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/foundation.dart';

// sprite_painting.dart is painting a Sprite element's frames on the canvas,
// pixel by pixel, as a pixel painter does: a frame shown big in the
// element's box, the one before it faint under it, a pencil, a rubber, a
// fill and a picker, and frames added or copied. Each stroke is kept as the
// sheet's picture again when the pen lifts -- one undo -- and undone, the
// sheet before it is painted on.

/// SpriteTool is what painting a sprite does with the pen.
enum SpriteTool {
  pencil("Pencil"),
  eraser("Rubber"),
  fill("Fill"),
  picker("Pick a colour"),
  line("Line");

  final String label;
  const SpriteTool(this.label);
}

/// SpritePaintSession is one sprite being painted.
class SpritePaintSession extends ChangeNotifier {
  final CanvasController controller;
  final String id;
  SpritePaintSession(this.controller, this.id);

  int frame = 0;
  SpriteTool tool = SpriteTool.pencil;
  ui.Color colour = const ui.Color(0xFF1F2430);
  int size = 1;
  bool onion = true;
  bool grid = true;

  SpritePixels? _pixels;
  ui.Image? live;

  /// _sheet is the stored sheet [_pixels] were read from, or kept as.
  String? _sheet;

  /// tick counts the changes to [live], for the stage to draw again.
  int tick = 0;

  SpriteElement? get sprite => switch (controller.document.elementById(id)) {
        SpriteElement e => e,
        _ => null,
      };

  void set({SpriteTool? tool, ui.Color? colour, int? size, bool? onion, bool? grid, int? frame}) {
    if (tool != null) this.tool = tool;
    if (colour != null) this.colour = colour;
    if (size != null) this.size = size.clamp(1, 16).toInt();
    if (onion != null) this.onion = onion;
    if (grid != null) this.grid = grid;
    if (frame != null) this.frame = frame;
    notifyListeners();
  }

  /// view is what the renderer shows of [e] while it is painted.
  SpritePaintView view(SpriteElement e) {
    var f = frame.clamp(0, math.max(0, e.frameCount - 1)).toInt();
    int? before;
    if (onion) {
      var a = e.actionNamed(e.action) ?? e.actions.firstOrNull;
      var list = a?.framesFor(e.facing, mirrorSides: false).$1 ?? const <int>[];
      var k = list.indexOf(f);
      before = k > 0 ? list[k - 1] : (f > 0 ? f - 1 : null);
    }
    return (frame: f, live: _sheet == e.sheet ? live : null, onion: before, grid: grid);
  }

  /// _sync reads the sheet's pixels again when the sheet is not the one
  /// they were read from: another brought in, or a stroke undone.
  Future<SpritePixels?> _sync(SpriteElement e) async {
    if (_sheet == e.sheet && _pixels != null) return _pixels;
    var image = controller.images.resolve(e.sheet, const BackgroundRemoval());
    if (image == null) return null;
    var p = await SpritePixels.of(image);
    if (p == null) return null;
    _pixels = p;
    _sheet = e.sheet;
    live = image;
    return p;
  }

  /// pixelAt is the sheet's pixel under [doc] in the frame painted, or
  /// null off it.
  (int, int)? pixelAt(SpriteElement e, ui.Offset doc) {
    var src = e.frameRect(frame.clamp(0, math.max(0, e.frameCount - 1)).toInt());
    var dst = spriteFit(src.size, e.bounds);
    if (!dst.contains(doc)) return null;
    var u = (doc.dx - dst.left) / dst.width * src.width, v = (doc.dy - dst.top) / dst.height * src.height;
    return ((src.left + u).floor(), (src.top + v).floor());
  }

  (int, int)? _from;
  bool _changed = false;

  /// strokeStart puts the pen down at [doc].
  Future<void> strokeStart(ui.Offset doc) async {
    var e = sprite;
    if (e == null) return;
    var p = await _sync(e);
    var at = pixelAt(e, doc);
    if (p == null || at == null) return;
    _from = at;
    _changed = false;
    var within = e.frameRect(frame);
    switch (tool) {
      case SpriteTool.picker:
        colour = p.at(at.$1, at.$2);
        _from = null;
        notifyListeners();
        return;
      case SpriteTool.fill:
        p.fill(at.$1, at.$2, colour, within: within);
      case SpriteTool.eraser:
        p.dab(at.$1, at.$2, const ui.Color(0x00000000), size: size, within: within);
      case SpriteTool.pencil || SpriteTool.line:
        p.dab(at.$1, at.$2, colour, size: size, within: within);
    }
    _changed = true;
    await _show();
  }

  SpritePixels? _lineBase;

  /// strokeTo carries the pen on to [doc].
  Future<void> strokeTo(ui.Offset doc) async {
    var e = sprite, p = _pixels, from = _from;
    if (e == null || p == null || from == null) return;
    var at = pixelAt(e, doc);
    if (at == null) return;
    var within = e.frameRect(frame);
    switch (tool) {
      case SpriteTool.pencil:
        p.line(from.$1, from.$2, at.$1, at.$2, colour, size: size, within: within);
        _from = at;
      case SpriteTool.eraser:
        p.line(from.$1, from.$2, at.$1, at.$2, const ui.Color(0x00000000), size: size, within: within);
        _from = at;
      case SpriteTool.line:
        // From where it went down, drawn again over the sheet as it was.
        _lineBase ??= p.copy();
        p.rgba.setAll(0, _lineBase!.rgba);
        p.line(from.$1, from.$2, at.$1, at.$2, colour, size: size, within: within);
      case SpriteTool.fill || SpriteTool.picker:
        return;
    }
    _changed = true;
    await _show();
  }

  bool _showing = false;
  bool _again = false;

  /// _show makes the picture of the pixels again -- one at a time, the
  /// last change caught up after.
  Future<void> _show() async {
    if (_showing) {
      _again = true;
      return;
    }
    _showing = true;
    do {
      _again = false;
      var p = _pixels;
      if (p == null) break;
      live = await p.image();
      tick++;
      notifyListeners();
    } while (_again);
    _showing = false;
  }

  /// strokeEnd lifts the pen, keeping what was painted as the sheet.
  Future<void> strokeEnd() async {
    _from = null;
    _lineBase = null;
    if (!_changed) return;
    _changed = false;
    await _keep();
  }

  /// _keep stores the pixels as the sheet's picture, and makes it the
  /// sprite's -- with [change] made to it as well -- as one change.
  Future<void> _keep([SpriteElement Function(SpriteElement)? change]) async {
    var e = sprite, p = _pixels;
    if (e == null || p == null) return;
    var bytes = await p.png();
    if (bytes == null) return;
    var stored = await CanvasAssets.save(bytes);
    if (stored == null) return;
    var image = await p.image();
    controller.images.hold(stored, image);
    _sheet = stored;
    live = image;
    var next = e.copyWith(sheet: stored, sheetW: p.width, sheetH: p.height);
    if (change != null) next = change(next);
    controller.beginInteraction();
    controller.replaceElement(next);
    controller.endInteraction();
    tick++;
    notifyListeners();
  }

  /// addFrame adds a frame after the last -- clear, or [copy]ing the one
  /// painted -- to the animation shown, and paints it next: a column more
  /// on a sheet of one row, a row more on a sheet of several.
  Future<void> addFrame({bool copy = false}) async {
    var e = sprite;
    if (e == null || e.rects.isNotEmpty) return;
    var p = await _sync(e);
    if (p == null) return;
    var cell = e.cellSize;
    var cols = e.columns, rows = e.rows;
    if (rows == 1) {
      cols++;
    } else {
      rows++;
    }
    var w = (e.margin * 2 + cols * cell.width + (cols - 1) * e.spacing).round();
    var h = (e.margin * 2 + rows * cell.height + (rows - 1) * e.spacing).round();
    var grown = p.grown(w, h);
    var made = e.copyWith(columns: cols, rows: rows, sheetW: w, sheetH: h);
    var added = rows == e.rows ? e.frameCount : e.rows * cols;
    if (copy) grown.copyFrame(e.frameRect(frame), made.frameRect(added));
    _pixels = grown;
    frame = added;
    await _keep((next) {
      var s = next.copyWith(columns: cols, rows: rows);
      var a = s.actionNamed(s.action) ?? s.actions.firstOrNull;
      if (a == null) {
        return s.withAction(SpriteAction("Play", frames: {SpriteFacing.front: [added]}));
      }
      var face = s.directions ? s.facing : SpriteFacing.front;
      var own = a.frames[face] ?? const <int>[];
      return s.withAction(a.withFrames(face, [...own, added]));
    });
  }
}

/// blankSprite is [e] made of a new, clear sheet of [count] frames in a
/// row, each [w] by [h] pixels, played as one animation: a sprite to paint
/// from nothing.
Future<SpriteElement?> blankSprite(CanvasController controller, SpriteElement e, int w, int h, int count) async {
  var p = SpritePixels.blank(w * count, h);
  var bytes = await p.png();
  if (bytes == null) return null;
  var stored = await CanvasAssets.save(bytes);
  if (stored == null) return null;
  controller.images.hold(stored, await p.image());
  return e.copyWith(
    sheet: stored,
    sheetName: "Painted",
    sheetW: w * count,
    sheetH: h,
    columns: count,
    rows: 1,
    margin: 0,
    spacing: 0,
    rects: const [],
    actions: [SpriteAction("Play", frames: {SpriteFacing.front: [for (var i = 0; i < count; i++) i]})],
    action: "Play",
    cues: const [],
    pixelArt: true,
  );
}
