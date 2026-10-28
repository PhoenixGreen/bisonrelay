import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/gif_encoder.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// sprite_export.dart is a sprite taken out of the canvas, and a character
// brought into one: its sheet laid out an animation to a row, with notes an
// engine reads -- Aseprite's -- or an animation as a GIF; and a character on
// the canvas drawn frame by frame, turned each way if wanted, into a sheet.

/// SheetRow is one row of a sheet laid out for export: an animation, the
/// way it faces, and its frames -- each drawn flipped or not.
typedef SheetRow = ({String name, List<(int, bool)> frames, double fps, bool loop});

/// exportRows is [e]'s animations laid out a row each -- and, with
/// directions, a row for each way it faces -- in the order they are.
List<SheetRow> exportRows(SpriteElement e) => [
      for (var a in e.actions)
        for (var f in e.directions ? SpriteFacing.values : const [SpriteFacing.front])
          if (a.framesFor(f, mirrorSides: e.mirrorSides) case (var list, var flip) when list.isNotEmpty)
            (
              name: e.directions ? "${a.name} ${f.label.toLowerCase()}" : a.name,
              frames: [for (var i in list) (i, flip)],
              fps: a.fps,
              loop: a.loop,
            ),
    ];

/// exportSheet is [e] laid out for an engine: every animation a row of
/// cells as big as its biggest frame, each frame standing on the bottom of
/// its cell -- the picture's .png, and its notes as Aseprite writes them,
/// each row a tag, called [image].
Future<(Uint8List, String)?> exportSheet(SpriteElement e, ui.Image sheet, {String image = "sprite.png"}) async {
  var rows = exportRows(e);
  if (rows.isEmpty) return null;
  var cw = 1.0, ch = 1.0;
  for (var r in rows) {
    for (var (i, _) in r.frames) {
      var s = spriteSource(e, i, sheet).size;
      cw = math.max(cw, s.width);
      ch = math.max(ch, s.height);
    }
  }
  var cols = rows.map((r) => r.frames.length).reduce(math.max);
  var w = (cols * cw).ceil(), h = (rows.length * ch).ceil();
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  var frames = <Map<String, dynamic>>[];
  var tags = <Map<String, dynamic>>[];
  for (var (y, r) in rows.indexed) {
    var start = frames.length;
    for (var (x, (i, flip)) in r.frames.indexed) {
      var src = spriteSource(e, i, sheet);
      var cell = ui.Rect.fromLTWH(x * cw, y * ch, cw, ch);
      var dst = ui.Rect.fromLTWH(cell.center.dx - src.width / 2, cell.bottom - src.height, src.width, src.height);
      canvas.save();
      if (flip) {
        canvas.translate(dst.center.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-dst.center.dx, 0);
      }
      canvas.drawImageRect(sheet, src, dst, ui.Paint()..filterQuality = ui.FilterQuality.none);
      canvas.restore();
      frames.add({
        "filename": "${r.name} $x",
        "frame": {"x": (x * cw).round(), "y": (y * ch).round(), "w": cw.round(), "h": ch.round()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": cw.round(), "h": ch.round()},
        "sourceSize": {"w": cw.round(), "h": ch.round()},
        "duration": (1000 / r.fps).round(),
      });
    }
    tags.add({"name": r.name, "from": start, "to": frames.length - 1, "direction": "forward"});
  }
  var picture = await rec.endRecording().toImage(w, h);
  var png = await picture.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  var notes = const JsonEncoder.withIndent(" ").convert({
    "frames": frames,
    "meta": {
      "app": "Bison Relay Canvas",
      "version": "1.0",
      "image": image,
      "format": "RGBA8888",
      "size": {"w": w, "h": h},
      "scale": "1",
      "frameTags": tags,
    },
  });
  return (png.buffer.asUint8List(), notes);
}

/// exportGif is animation [action] of [e] as a GIF, each frame as long as
/// its speed says, on a cell as big as its biggest frame; facing the way
/// it faces.
Future<Uint8List?> exportGif(SpriteElement e, ui.Image sheet, String action) async {
  var a = e.actionNamed(action);
  if (a == null) return null;
  var (list, flip) = a.framesFor(e.directions ? e.facing : SpriteFacing.front, mirrorSides: e.mirrorSides);
  if (list.isEmpty) return null;
  var sizes = [for (var i in list) spriteSource(e, i, sheet).size];
  var cw = sizes.map((s) => s.width).reduce(math.max).ceil();
  var ch = sizes.map((s) => s.height).reduce(math.max).ceil();
  var frames = <GifFrame>[];
  for (var i in list) {
    var rec = ui.PictureRecorder();
    var canvas = ui.Canvas(rec);
    var src = spriteSource(e, i, sheet);
    var dst = ui.Rect.fromLTWH((cw - src.width) / 2, ch - src.height, src.width, src.height);
    if (flip) {
      canvas.translate(dst.center.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-dst.center.dx, 0);
    }
    canvas.drawImageRect(sheet, src, dst, spritePaint(e)..blendMode = ui.BlendMode.srcOver);
    var img = await rec.endRecording().toImage(cw, ch);
    var data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    frames.add(GifFrame(
        rgba: data.buffer.asUint8List(), width: cw, height: ch, delayMs: (1000 / a.fps).round()));
  }
  return encodeGif(frames, loop: a.loop ? 0 : 1);
}

/// spriteFacings is the way a character is turned for each way a sprite
/// faces: a quarter round to its left faces the page's left.
const Map<SpriteFacing, double> spriteFacings = {
  SpriteFacing.front: 0,
  SpriteFacing.left: 90,
  SpriteFacing.back: 180,
  SpriteFacing.right: -90,
};

/// spriteFromCharacter is [e] made of [who] -- drawn [count] frames from
/// [from], [step] frames of the canvas apart, each in a cell [cell] pixels
/// tall -- and, with [directions], turned each way a sprite can face, a
/// row each. Played as one animation at the canvas's own speed over the
/// frames taken.
Future<SpriteElement?> spriteFromCharacter(SpriteElement e, CharacterElement who,
    {required int from,
    int count = 8,
    int step = 1,
    int frameRate = 12,
    bool directions = false,
    int cell = 128,
    CanvasImageSource? images}) async {
  // Room round the box for arms out and hair up: a figure is drawn past
  // its box.
  var b = who.bounds;
  var room = Rect.fromLTRB(b.left - b.height * 0.16, b.top - b.height * 0.22, b.right + b.height * 0.16,
      b.bottom + b.height * 0.04);
  var k = cell / room.height;
  var cw = (room.width * k).ceil(), ch = cell;
  var facings = directions ? spriteFacings.keys.toList() : [SpriteFacing.front];
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var (row, f) in facings.indexed) {
    var turned = directions ? who.copyWith(pose: who.pose.withTurn(spriteFacings[f]!)) : who;
    for (var n = 0; n < count; n++) {
      canvas.save();
      canvas.translate(n * cw.toDouble(), row * ch.toDouble());
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()));
      canvas.scale(k);
      canvas.translate(-room.left, -room.top);
      paintElement(canvas, turned, from + n * step, frameRate: frameRate, images: images);
      canvas.restore();
    }
  }
  var w = cw * count, h = ch * facings.length;
  var picture = await rec.endRecording().toImage(w, h);
  var png = await picture.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  var bytes = png.buffer.asUint8List();
  var id = await CanvasAssets.save(bytes);
  if (id == null) return null;
  await CanvasLibrary.addPicture(id, who.name, bytes);
  var name = who.name.isEmpty ? "Animation" : who.name;
  return e.copyWith(
    sheet: id,
    sheetName: name,
    sheetW: w,
    sheetH: h,
    columns: count,
    rows: facings.length,
    margin: 0,
    spacing: 0,
    rects: const [],
    actions: [
      SpriteAction(name,
          frames: {
            for (var (row, f) in facings.indexed) f: [for (var n = 0; n < count; n++) row * count + n],
          },
          fps: frameRate / step),
    ],
    action: name,
    cues: const [],
    pixelArt: false,
    directions: directions,
    facing: SpriteFacing.front,
  );
}

/// SpriteExportGroup saves the sprite out: its sheet with its notes, or an
/// animation as a GIF.
class SpriteExportGroup extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  const SpriteExportGroup({required this.controller, required this.sprite, super.key});

  @override
  State<SpriteExportGroup> createState() => SpriteExportGroupState();
}

class SpriteExportGroupState extends State<SpriteExportGroup> {
  String _said = "";

  ui.Image? get _sheet => widget.controller.images.resolve(widget.sprite.sheet, const BackgroundRemoval());

  String get _name {
    var n = widget.sprite.sheetName.isNotEmpty ? widget.sprite.sheetName : widget.sprite.name;
    return n.replaceAll(RegExp(r"[^A-Za-z0-9 _-]"), "").trim().isEmpty
        ? "sprite"
        : n.replaceAll(RegExp(r"[^A-Za-z0-9 _-]"), "").trim();
  }

  Future<void> _saveSheet() async {
    var sheet = _sheet;
    if (sheet == null) return;
    var to = await FilePicker.platform.saveFile(fileName: "$_name.png", type: FileType.custom, allowedExtensions: const ["png"]);
    if (to == null) return;
    var base = path.withoutExtension(to);
    var made = await exportSheet(widget.sprite, sheet, image: path.basename("$base.png"));
    if (made == null) {
      setState(() => _said = "It has no frames to save.");
      return;
    }
    var (png, notes) = made;
    await File("$base.png").writeAsBytes(png);
    await File("$base.json").writeAsString(notes);
    if (mounted) setState(() => _said = "Saved ${path.basename(base)}.png and its .json beside it.");
  }

  Future<void> _saveGif() async {
    var sheet = _sheet;
    var e = widget.sprite;
    if (sheet == null) return;
    var to = await FilePicker.platform
        .saveFile(fileName: "$_name ${e.action}.gif", type: FileType.custom, allowedExtensions: const ["gif"]);
    if (to == null) return;
    var gif = await exportGif(e, sheet, e.action);
    if (gif == null) {
      setState(() => _said = "${e.action} has no frames to save.");
      return;
    }
    await File(to.endsWith(".gif") ? to : "$to.gif").writeAsBytes(gif);
    if (mounted) setState(() => _said = "Saved ${path.basename(to)}.");
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
        key: const ValueKey("spriteExportGroup"),
        label: "Save it out",
        help: "The sheet laid out an animation to a row -- a row for each way "
            "it faces, with directions -- with a .json an engine reads, as "
            "Aseprite writes them; or the animation playing as a GIF.",
        children: [
          CanvasTextButton(
            key: const ValueKey("spriteExportSheet"),
            label: "Save the sheet and its notes…",
            icon: Icons.save_alt,
            onPressed: _saveSheet,
          ),
          CanvasTextButton(
            key: const ValueKey("spriteExportGif"),
            label: "Save ${widget.sprite.action} as a GIF…",
            icon: Icons.gif_box_outlined,
            onPressed: _saveGif,
          ),
          if (_said.isNotEmpty) CanvasStatus(_said),
        ],
      );
}

/// CharacterSpriteMaker makes the sprite of a character on the canvas: so
/// many of its frames from the playhead, turned each way or not.
class CharacterSpriteMaker extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  const CharacterSpriteMaker({required this.controller, required this.sprite, super.key});

  @override
  State<CharacterSpriteMaker> createState() => CharacterSpriteMakerState();
}

class CharacterSpriteMakerState extends State<CharacterSpriteMaker> {
  String? _who;
  int _count = 8, _step = 1, _cell = 128;
  bool _directions = false;
  bool _busy = false;

  Future<void> make() async {
    var c = widget.controller;
    var who = c.document.elementById(_who ?? "");
    if (who is! CharacterElement) return;
    setState(() => _busy = true);
    var made = await spriteFromCharacter(widget.sprite, who,
        from: c.frame,
        count: _count,
        step: _step,
        frameRate: c.document.frameRate <= 0 ? 12 : c.document.frameRate,
        directions: _directions,
        cell: _cell,
        images: c.images);
    if (!mounted) return;
    setState(() => _busy = false);
    if (made == null) return;
    var cell = made.frameRect(0).size;
    var box = made.base;
    c.beginInteraction();
    c.replaceElement(made.rebase(box.copyWith(width: box.height * cell.width / cell.height, lockAspect: true)));
    c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var who = [
      for (var e in widget.controller.document.elements)
        if (e is CharacterElement) e,
    ];
    if (who.isEmpty) return const SizedBox.shrink();
    var picked = who.any((w) => w.id == _who) ? _who! : who.first.id;
    _who = picked;
    return CanvasControlGroup(
      key: const ValueKey("spriteFromCharacter"),
      label: "Or make it from a character",
      help: "A character on this canvas drawn frame by frame from the "
          "playhead -- walking, waving, whatever it does there -- into a "
          "sheet; with directions, turned each way, a row each.",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("spriteFromWho"),
          label: "Character",
          value: picked,
          options: [for (var w in who) (w.id, w.name)],
          onChanged: (id) => setState(() => _who = id),
        ),
        CanvasStepper(
          key: const ValueKey("spriteFromFrames"),
          label: "Frames",
          value: _count.toDouble(),
          min: 1,
          max: 48,
          step: 1,
          onChanged: (v) => setState(() => _count = v.round()),
        ),
        CanvasStepper(
          key: const ValueKey("spriteFromStep"),
          label: "Every",
          value: _step.toDouble(),
          min: 1,
          max: 12,
          step: 1,
          suffix: " frames",
          onChanged: (v) => setState(() => _step = v.round()),
        ),
        CanvasStepper(
          key: const ValueKey("spriteFromSize"),
          label: "Height",
          value: _cell.toDouble(),
          min: 16,
          max: 512,
          step: 8,
          suffix: " px",
          onChanged: (v) => setState(() => _cell = v.round()),
        ),
        CanvasToggle(
          key: const ValueKey("spriteFromDirections"),
          label: "Directions: turned each way",
          value: _directions,
          onChanged: (v) => setState(() => _directions = v),
        ),
        CanvasTextButton(
          key: const ValueKey("spriteFromMake"),
          label: _busy ? "Drawing…" : "Make the sheet",
          icon: Icons.movie_creation_outlined,
          primary: true,
          onPressed: _busy ? null : make,
        ),
      ],
    );
  }
}
