import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// sprite_element.dart is the Sprite element: a sprite sheet -- a picture
// of frames side by side, of anything: a figure, a flame, a coin, a door --
// sliced into them, by a grid or by the frames the sheet's own notes say,
// and its animations, each a run of those frames played at so many frames
// a second. A figure's can have directions too: frames for each way it
// faces, played for the way it faces now, as a sprite sheet is drawn for
// a game. (An animation is a SpriteAction, from when sprites were figures
// only; saved canvases keep the name.)

/// SpriteFacing is a way a sprite can face: towards the reader, away, or
/// to the page's left or right.
enum SpriteFacing {
  front("Front"),
  back("Back"),
  left("Left"),
  right("Right");

  final String label;
  const SpriteFacing(this.label);

  /// of is the way a character turned [turn] degrees faces: turned a
  /// quarter round it faces the page's left, as a sketch's side view does.
  static SpriteFacing of(double turn) {
    var t = ((turn + 180) % 360 + 360) % 360 - 180;
    if (t.abs() < 45) return front;
    if (t.abs() > 135) return back;
    return t > 0 ? left : right;
  }
}

/// SpriteAction is one thing a sprite does -- stands, walks, jumps -- as
/// the frames played for each way it faces, how fast, and whether over
/// and over or once.
class SpriteAction {
  final String name;
  final Map<SpriteFacing, List<int>> frames;
  final double fps;
  final bool loop;

  const SpriteAction(this.name,
      {this.frames = const {}, this.fps = 8, this.loop = true});

  /// framesFor is the frames played facing [f], and whether they are drawn
  /// flipped: a side with none of its own is the other side mirrored, and
  /// a way with none at all is the front.
  (List<int>, bool) framesFor(SpriteFacing f, {bool mirrorSides = true}) {
    var own = frames[f];
    if (own != null && own.isNotEmpty) return (own, false);
    if (mirrorSides && (f == SpriteFacing.left || f == SpriteFacing.right)) {
      var other = frames[f == SpriteFacing.left ? SpriteFacing.right : SpriteFacing.left];
      if (other != null && other.isNotEmpty) return (other, true);
    }
    for (var g in SpriteFacing.values) {
      var any = frames[g];
      if (any != null && any.isNotEmpty) return (any, false);
    }
    return (const [], false);
  }

  SpriteAction copyWith({
    String? name,
    Map<SpriteFacing, List<int>>? frames,
    double? fps,
    bool? loop,
  }) =>
      SpriteAction(name ?? this.name,
          frames: frames ?? this.frames, fps: fps ?? this.fps, loop: loop ?? this.loop);

  SpriteAction withFrames(SpriteFacing f, List<int> list) =>
      copyWith(frames: {...frames, f: List.unmodifiable(list)});

  Map<String, dynamic> toJson() => {
        "name": name,
        "frames": {for (var e in frames.entries) e.key.name: e.value},
        "fps": fps,
        if (!loop) "loop": false,
      };

  static SpriteAction? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var name = json["name"];
    if (name is! String || name.isEmpty) return null;
    var frames = <SpriteFacing, List<int>>{};
    if (json["frames"] case Map raw) {
      for (var f in SpriteFacing.values) {
        if (raw[f.name] case List list) {
          frames[f] = [for (var v in list) if (v is num) v.toInt()];
        }
      }
    }
    return SpriteAction(name,
        frames: frames,
        fps: jsonDouble(json["fps"], 8).clamp(0.5, 60.0),
        loop: jsonBool(json["loop"], true));
  }
}

/// SpriteCue is what a sprite takes up on a frame of the canvas, until the
/// next cue: an action, and -- when the cue says -- a way to face.
typedef SpriteCue = ({int frame, String action, SpriteFacing? facing});

/// SpriteElement is a sprite sheet on the canvas, and what is made of it.
class SpriteElement extends CanvasElement {
  /// sheet is the stored picture of the frames, and width and height its
  /// size in pixels -- kept so the frames can be found without it.
  final String sheet;
  final String sheetName;
  final int sheetW;
  final int sheetH;

  /// columns and rows are the grid the sheet is sliced by; margin how far
  /// in from its edge the first frame is, and spacing the gap between
  /// frames -- all in the sheet's pixels.
  final int columns;
  final int rows;
  final double margin;
  final double spacing;

  /// rects are the frames a sheet's own notes give, in place of the grid:
  /// an Aseprite or TexturePacker sheet, packed tight.
  final List<Rect> rects;

  final List<SpriteAction> actions;

  /// action is the action it takes, and cues where it changes to another.
  final String action;
  final List<SpriteCue> cues;

  /// pixelArt draws the frames' pixels as squares, not smoothed.
  final bool pixelArt;

  /// mirrorSides is whether a side with no frames of its own is the other
  /// side, flipped.
  final bool mirrorSides;

  /// facing is the way it faces, until a cue turns it.
  final SpriteFacing facing;

  /// directions is whether its animations have frames for each way it can
  /// face -- a figure's -- or one run each, whichever way: a flame's.
  final bool directions;

  const SpriteElement(
    super.base, {
    this.sheet = "",
    this.sheetName = "",
    this.sheetW = 1,
    this.sheetH = 1,
    this.columns = 1,
    this.rows = 1,
    this.margin = 0,
    this.spacing = 0,
    this.rects = const [],
    this.actions = const [],
    this.action = "",
    this.cues = const [],
    this.pixelArt = true,
    this.mirrorSides = true,
    this.facing = SpriteFacing.front,
    this.directions = false,
  });

  @override
  ElementKind get kind => ElementKind.sprite;

  /// hasSheet is whether it has a sheet to draw from yet.
  bool get hasSheet => sheet.isNotEmpty;

  /// Its sheet is a stored picture, kept while it is used.
  @override
  Set<String> get assetIds => {if (sheet.isNotEmpty) sheet};

  @override
  CanvasElement rebase(ElementBase base) => SpriteElement(base,
      sheet: sheet,
      sheetName: sheetName,
      sheetW: sheetW,
      sheetH: sheetH,
      columns: columns,
      rows: rows,
      margin: margin,
      spacing: spacing,
      rects: rects,
      actions: actions,
      action: action,
      cues: cues,
      pixelArt: pixelArt,
      mirrorSides: mirrorSides,
      facing: facing,
      directions: directions);

  /// frameCount is how many frames the sheet is sliced into.
  int get frameCount => rects.isNotEmpty ? rects.length : columns * rows;

  /// cellSize is a grid frame's size, in the sheet's pixels.
  Size get cellSize => Size(
      math.max(1, (sheetW - margin * 2 - spacing * (columns - 1)) / columns),
      math.max(1, (sheetH - margin * 2 - spacing * (rows - 1)) / rows));

  /// frameRect is where frame [i] is on the sheet.
  Rect frameRect(int i) {
    if (rects.isNotEmpty) return rects[i.clamp(0, rects.length - 1)];
    var c = cellSize;
    var col = i % columns, row = (i ~/ columns).clamp(0, rows - 1);
    return Rect.fromLTWH(
        margin + col * (c.width + spacing), margin + row * (c.height + spacing), c.width, c.height);
  }

  /// row is the frames of row [r] of the grid, left to right.
  List<int> row(int r) => [for (var c = 0; c < columns; c++) r * columns + c];

  SpriteAction? actionNamed(String name) =>
      actions.where((a) => a.name == name).firstOrNull;

  /// actionAt is the action taken on [frame]: the last cue's at or before
  /// it, or the one set.
  SpriteAction? actionAt(int frame) {
    var name = action;
    for (var c in cues) {
      if (c.frame <= frame) name = c.action;
    }
    return actionNamed(name) ?? actions.firstOrNull;
  }

  /// facingAt is the way it faces on [frame]: the last cue's that turns it,
  /// or its own.
  SpriteFacing facingAt(int frame) {
    if (!directions) return SpriteFacing.front;
    var f = facing;
    for (var c in cues) {
      if (c.frame <= frame && c.facing != null) f = c.facing!;
    }
    return f;
  }

  /// sheetFrameAt is the sheet's frame drawn on [frame] of a canvas played at
  /// [frameRate] -- and whether flipped -- or null with no frames to draw.
  (int, bool)? sheetFrameAt(int frame, int frameRate) {
    var facing = facingAt(frame);
    var a = actionAt(frame);
    if (a == null) return frameCount > 0 ? (0, false) : null;
    var (list, flip) = a.framesFor(facing, mirrorSides: mirrorSides);
    if (list.isEmpty) return null;
    // Counted from the cue it began on.
    var start = 0;
    for (var c in cues) {
      if (c.frame <= frame) start = c.frame;
    }
    var t = (frame - start) / math.max(1, frameRate);
    var k = (t * a.fps).floor();
    k = a.loop ? k % list.length : math.min(k, list.length - 1);
    return (list[k].clamp(0, math.max(0, frameCount - 1)), flip);
  }

  SpriteElement copyWith({
    String? sheet,
    String? sheetName,
    int? sheetW,
    int? sheetH,
    int? columns,
    int? rows,
    double? margin,
    double? spacing,
    List<Rect>? rects,
    List<SpriteAction>? actions,
    String? action,
    List<SpriteCue>? cues,
    bool? pixelArt,
    bool? mirrorSides,
    SpriteFacing? facing,
    bool? directions,
  }) =>
      SpriteElement(
        base,
        sheet: sheet ?? this.sheet,
        sheetName: sheetName ?? this.sheetName,
        sheetW: sheetW ?? this.sheetW,
        sheetH: sheetH ?? this.sheetH,
        columns: math.max(1, columns ?? this.columns),
        rows: math.max(1, rows ?? this.rows),
        margin: margin ?? this.margin,
        spacing: spacing ?? this.spacing,
        rects: rects ?? this.rects,
        actions: actions ?? this.actions,
        action: action ?? this.action,
        cues: cues ?? this.cues,
        pixelArt: pixelArt ?? this.pixelArt,
        mirrorSides: mirrorSides ?? this.mirrorSides,
        facing: facing ?? this.facing,
        directions: directions ?? this.directions,
      );

  /// withAction is this with [a] in place of the action of its name -- or
  /// added, when there is none.
  SpriteElement withAction(SpriteAction a, {String? replacing}) {
    var name = replacing ?? a.name;
    var found = actions.any((x) => x.name == name);
    return copyWith(
      actions: found ? [for (var x in actions) x.name == name ? a : x] : [...actions, a],
      action: action == name || action.isEmpty ? a.name : action,
    );
  }

  @override
  Map<String, dynamic> props() => {
        "sheet": sheet,
        if (sheetName.isNotEmpty) "sheetName": sheetName,
        "w": sheetW,
        "h": sheetH,
        "cols": columns,
        "rows": rows,
        if (margin != 0) "margin": margin,
        if (spacing != 0) "spacing": spacing,
        if (rects.isNotEmpty)
          "rects": [
            for (var r in rects) [r.left, r.top, r.width, r.height]
          ],
        "actions": [for (var a in actions) a.toJson()],
        if (action.isNotEmpty) "action": action,
        if (cues.isNotEmpty)
          "cues": [
            for (var c in cues) [c.frame, c.action, if (c.facing != null) c.facing!.name]
          ],
        if (!pixelArt) "pixelArt": false,
        if (!mirrorSides) "mirrorSides": false,
        if (facing != SpriteFacing.front) "facing": facing.name,
        if (directions) "directions": true,
      };

  factory SpriteElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    SpriteFacing? facingOf(Object? v) =>
        SpriteFacing.values.where((f) => f.name == v).firstOrNull;
    return SpriteElement(
      b,
      sheet: json["sheet"] as String? ?? "",
      sheetName: json["sheetName"] as String? ?? "",
      sheetW: jsonDouble(json["w"], 1).round().clamp(1, 1 << 15),
      sheetH: jsonDouble(json["h"], 1).round().clamp(1, 1 << 15),
      columns: jsonDouble(json["cols"], 1).round().clamp(1, 512),
      rows: jsonDouble(json["rows"], 1).round().clamp(1, 512),
      margin: jsonDouble(json["margin"], 0),
      spacing: jsonDouble(json["spacing"], 0),
      rects: [
        if (json["rects"] case List raw)
          for (var r in raw)
            if (r is List && r.length == 4 && r.every((v) => v is num))
              Rect.fromLTWH(
                  (r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble(), (r[3] as num).toDouble()),
      ],
      actions: [
        if (json["actions"] case List raw)
          for (var a in raw)
            if (SpriteAction.fromJson(a) case var action?) action,
      ],
      action: json["action"] as String? ?? "",
      cues: [
        if (json["cues"] case List raw)
          for (var c in raw)
            if (c is List && c.length >= 2 && c[0] is num && c[1] is String)
              (
                frame: (c[0] as num).toInt(),
                action: c[1] as String,
                facing: c.length > 2 ? facingOf(c[2]) : null
              ),
      ],
      pixelArt: jsonBool(json["pixelArt"], true),
      mirrorSides: jsonBool(json["mirrorSides"], true),
      facing: facingOf(json["facing"]) ?? SpriteFacing.front,
      directions: jsonBool(json["directions"], false),
    );
  }
}

/// SheetNotes is what a sprite sheet's own notes -- an Aseprite or a
/// TexturePacker .json beside it -- say: each frame's place on the sheet,
/// the sheet's size and file, and its tagged runs of frames.
class SheetNotes {
  final List<Rect> frames;
  final int width, height;
  final String image;
  final List<SpriteAction> actions;
  const SheetNotes(this.frames, this.width, this.height, this.image, this.actions);

  /// read reads [text] as notes, or null when it is not any it knows:
  /// frames as a list or as a map by name, the "meta" size and image, and
  /// Aseprite's frame tags -- each an action, played at the speed its
  /// frames last.
  static SheetNotes? read(String text) {
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    var raw = json["frames"];
    var entries = <Map<String, dynamic>>[];
    if (raw is List) {
      entries = [for (var f in raw) if (f is Map<String, dynamic>) f];
    } else if (raw is Map) {
      entries = [for (var f in raw.values) if (f is Map<String, dynamic>) f];
    } else {
      return null;
    }
    var frames = <Rect>[];
    var lasting = <double>[];
    for (var f in entries) {
      var r = f["frame"];
      if (r is! Map) return null;
      frames.add(Rect.fromLTWH(jsonDouble(r["x"], 0), jsonDouble(r["y"], 0),
          jsonDouble(r["w"], 1), jsonDouble(r["h"], 1)));
      lasting.add(jsonDouble(f["duration"], 100));
    }
    if (frames.isEmpty) return null;
    var meta = json["meta"] is Map ? json["meta"] as Map : const {};
    var size = meta["size"] is Map ? meta["size"] as Map : const {};
    var w = jsonDouble(size["w"], frames.map((r) => r.right).reduce(math.max)).round();
    var h = jsonDouble(size["h"], frames.map((r) => r.bottom).reduce(math.max)).round();
    var actions = <SpriteAction>[];
    if (meta["frameTags"] case List tags) {
      for (var t in tags) {
        if (t is! Map) continue;
        var name = t["name"];
        if (name is! String) continue;
        var from = jsonDouble(t["from"], 0).round(), to = jsonDouble(t["to"], 0).round();
        from = from.clamp(0, frames.length - 1);
        to = to.clamp(from, frames.length - 1);
        var list = [for (var i = from; i <= to; i++) i];
        if (t["direction"] == "reverse") list = list.reversed.toList();
        if (t["direction"] == "pingpong" && list.length > 2) {
          list = [...list, ...list.reversed.skip(1).take(list.length - 2)];
        }
        var ms = [for (var i = from; i <= to; i++) lasting[i]].reduce((a, b) => a + b) / (to - from + 1);
        actions.add(SpriteAction(name,
            frames: {SpriteFacing.front: list}, fps: (1000 / math.max(1, ms)).clamp(0.5, 60.0)));
      }
    }
    return SheetNotes(frames, math.max(1, w), math.max(1, h), meta["image"] as String? ?? "", actions);
  }
}

/// gridFromGaps is the grid a sheet [width] by [height] pixels is laid out
/// in, found from [clear] -- whether a pixel is see-through -- the columns
/// and rows of nothing between its frames: how many across and down, or
/// null when no gaps run right across it.
(int, int)? gridFromGaps(int width, int height, bool Function(int x, int y) clear) {
  // A line of the sheet is a gap where every pixel along it is clear.
  List<bool> gaps(int along, int across, bool Function(int a, int b) at) => [
        for (var a = 0; a < along; a++)
          () {
            for (var b = 0; b < across; b++) {
              if (!at(a, b)) return false;
            }
            return true;
          }(),
      ];
  int runs(List<bool> gap) {
    var n = 0;
    var inside = false;
    for (var g in gap) {
      if (!g && !inside) n++;
      inside = !g;
    }
    return n;
  }

  var cols = runs(gaps(width, height, (x, y) => clear(x, y)));
  var rows = runs(gaps(height, width, (y, x) => clear(x, y)));
  if (cols < 1 || rows < 1 || (cols == 1 && rows == 1)) return null;
  return (cols, rows);
}
