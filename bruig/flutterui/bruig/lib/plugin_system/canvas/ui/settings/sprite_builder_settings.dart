import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_builder.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// sprite_builder_settings.dart is building a figure for a Sprite element
// from Kenney's modular character pack: each piece chosen -- skin, hair, the
// face, a shirt and its sleeves, trousers and their legs, shoes -- seen as
// it is chosen, and its animations drawn into the sprite's sheet. See
// sprite_builder.dart.

/// modularPack is Kenney's modular character pack, among his packs.
KenneyPack get modularPack => kenneyPacks.firstWhere((p) => p.slug == "modular-character-pack");

class SpriteBuilderGroup extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  const SpriteBuilderGroup({required this.controller, required this.sprite, super.key});

  @override
  State<SpriteBuilderGroup> createState() => SpriteBuilderGroupState();
}

class SpriteBuilderGroupState extends State<SpriteBuilderGroup> {
  /// parts is the pack read, for the rest of the run of the app.
  static ModularParts? parts;

  bool _open = false;
  bool _busy = false;
  bool? _kept;
  String _said = "";
  ModularLook? _look;
  Set<String> _animations = {for (var a in modularAnimations) a.name};
  int _height = 160;
  Map<String, ui.Image?> _pieces = const {};

  @override
  void initState() {
    super.initState();
    var built = widget.sprite.built;
    if (built != null) {
      _look = ModularLook.fromJson(built["look"]);
      if (built["animations"] case List names) _animations = {for (var n in names) "$n"};
      if (built["height"] case num h) _height = h.toInt();
      _open = true;
    }
    _check();
  }

  Future<void> _check() async {
    var kept = parts != null || await (await kenneyFile(modularPack)).exists();
    if (!mounted) return;
    setState(() => _kept = kept);
    if (kept && _open) await _load();
  }

  Future<void> _load() async {
    if (parts == null) {
      setState(() => _busy = true);
      try {
        var bytes = await (await kenneyFile(modularPack)).readAsBytes();
        var read = ModularParts(ZipDecoder().decodeBytes(bytes));
        if (read.isModular) parts = read;
      } catch (_) {}
      if (!mounted) return;
      setState(() => _busy = false);
      if (parts == null) {
        setState(() => _said = "The pack could not be read.");
        return;
      }
    }
    _look ??= parts!.standard();
    await _show();
  }

  Future<void> _show() async {
    var p = parts, look = _look;
    if (p == null || look == null) return;
    var pieces = await modularPieces(p, look);
    if (mounted) setState(() => _pieces = pieces);
  }

  Future<void> _fetch() async {
    var prefs = context.read<CanvasPreferences>();
    setState(() {
      _busy = true;
      _said = "Fetching Kenney's modular character pack…";
    });
    var file = await kenneyFetch(modularPack,
        allowFetching: prefs.allowFetching, proxied: await networkIsProxied());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _kept = file != null;
      _said = file == null ? "It could not be fetched. Check that fetching is allowed in Settings." : "";
    });
    if (file != null) await _load();
  }

  void _set(ModularLook next) {
    setState(() => _look = next);
    _show();
  }

  Future<void> _build() async {
    var p = parts, look = _look;
    if (p == null || look == null) return;
    var chosen = [for (var a in modularAnimations) if (_animations.contains(a.name)) a];
    if (chosen.isEmpty) return;
    setState(() => _busy = true);
    var (sheet, cols, rows) = await modularSheet(p, look, chosen, _height);
    var png = await sheet.toByteData(format: ui.ImageByteFormat.png);
    var id = png == null ? null : await CanvasAssets.save(png.buffer.asUint8List());
    if (!mounted) return;
    setState(() => _busy = false);
    if (id == null) {
      setState(() => _said = "The sheet could not be stored.");
      return;
    }
    await CanvasLibrary.addPicture(id, "Built figure", png!.buffer.asUint8List());
    var c = widget.controller;
    c.images.hold(id, sheet);
    var e = widget.sprite;
    var made = e.copyWith(
      sheet: id,
      sheetName: "Built figure",
      sheetW: sheet.width,
      sheetH: sheet.height,
      columns: cols,
      rows: rows,
      margin: 0,
      spacing: 0,
      rects: const [],
      actions: [
        for (var (row, a) in chosen.indexed)
          SpriteAction(a.name,
              frames: {SpriteFacing.front: [for (var k = 0; k < a.frames.length; k++) row * cols + k]},
              fps: a.fps,
              loop: a.loop),
      ],
      action: chosen.first.name,
      cues: const [],
      pixelArt: false,
      glow: false,
      directions: false,
      built: {
        "look": look.toJson(),
        "animations": [for (var a in chosen) a.name],
        "height": _height,
      },
    );
    var box = made.base;
    var cell = made.frameRect(0).size;
    c.beginInteraction();
    c.replaceElement(made.rebase(box.copyWith(width: box.height * cell.width / cell.height, lockAspect: true)));
    c.endInteraction();
    setState(() => _said = "Built: ${chosen.length} animations.");
  }

  @override
  Widget build(BuildContext context) {
    var p = parts, look = _look;
    return CanvasControlGroup(
      key: const ValueKey("spriteBuilder"),
      label: "Or build a figure",
      help: "A figure built from Kenney's modular character pack -- free for "
          "anything -- each piece chosen: skin, hair, face, shirt, trousers, "
          "shoes. Its animations, standing to waving, are drawn into the sheet.",
      children: [
        if (!_open)
          CanvasTextButton(
            key: const ValueKey("spriteBuilderOpen"),
            label: "Build a figure…",
            icon: Icons.accessibility_new,
            onPressed: () {
              setState(() => _open = true);
              if (_kept == true) _load();
            },
          )
        else if (p == null) ...[
          if (_kept == false && !_busy)
            CanvasTextButton(
              key: const ValueKey("spriteBuilderFetch"),
              label: "Fetch Kenney's modular character pack",
              icon: Icons.download_outlined,
              primary: true,
              onPressed: _fetch,
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ] else if (look != null) ...[
          SizedBox(
            key: const ValueKey("spriteBuilderPreview"),
            height: 190,
            child: CustomPaint(painter: _FigurePainter(p, look, _pieces)),
          ),
          ..._choices(p, look),
          CanvasTiles<String>(
            key: const ValueKey("spriteBuilderAnimations"),
            label: "Animations",
            columns: 3,
            previewHeight: 22,
            tiles: [for (var a in modularAnimations) CanvasTile(a.name, a.name, icon: Icons.play_arrow)],
            selected: (n) => _animations.contains(n),
            keyOf: (n) => "spriteBuilderAnimation-$n",
            onPick: (n) => setState(() => _animations.contains(n) && _animations.length > 1
                ? _animations.remove(n)
                : _animations.add(n)),
          ),
          CanvasStepper(
            key: const ValueKey("spriteBuilderHeight"),
            label: "Height",
            value: _height.toDouble(),
            min: 48,
            max: 512,
            step: 16,
            suffix: " px",
            onChanged: (v) => setState(() => _height = v.round()),
          ),
          CanvasTextButton(
            key: const ValueKey("spriteBuilderBuild"),
            label: _busy ? "Building…" : "Build the sprite",
            icon: Icons.construction,
            primary: true,
            onPressed: _busy ? null : _build,
          ),
        ],
        if (_said.isNotEmpty) CanvasStatus(_said),
        const CanvasStatus("Kenney's art is CC0: free for anything. He makes it "
            "with the help of donations, at kenney.nl."),
      ],
    );
  }

  List<Widget> _choices(ModularParts p, ModularLook look) {
    Widget pick<T>(String key, String label, T value, List<(T, String)> options, ModularLook Function(T) set) =>
        CanvasDropdown<T>(
          key: ValueKey("spriteBuilder-$key"),
          label: label,
          value: options.any((o) => o.$1 == value) ? value : options.first.$1,
          options: options,
          onChanged: (v) => _set(set(v)),
        );
    List<(String, String)> named(Iterable<String> keys) =>
        [for (var k in (keys.toList()..sort())) (k, k[0].toUpperCase() + k.substring(1))];
    String styleName(String s) => s.replaceAllMapped(RegExp(r"(Man|Woman)(\d+)"), (m) => "${m[1]} ${m[2]}");
    var lengths = const [("long", "Long"), ("short", "Short"), ("shorter", "Shorter"), ("none", "None")];
    return [
      pick("skin", "Skin", look.skin, [for (var s in p.skins) (s, "Skin $s")], (v) => look.copyWith(skin: v)),
      pick("hair", "Hair", look.hair,
          [for (var h in ((p.hair[look.hairColour]?.keys ?? const <String>[]).toList()..sort())) (h, styleName(h))],
          (v) => look.copyWith(hair: v)),
      pick("hairColour", "Hair colour", look.hairColour, named(p.hair.keys), (v) => look.copyWith(hairColour: v)),
      pick("eyes", "Eyes", look.eyes, named(p.eyes.keys), (v) => look.copyWith(eyes: v)),
      pick("brows", "Brows", look.brows, named(p.brows.keys), (v) => look.copyWith(brows: v)),
      pick("nose", "Nose", look.nose,
          [for (var n in ((p.noses[look.skin]?.keys ?? const <int>[]).toList()..sort())) (n, "Nose $n")],
          (v) => look.copyWith(nose: v)),
      pick("mouth", "Mouth", look.mouth, named(p.mouths.keys), (v) => look.copyWith(mouth: v)),
      pick("shirtColour", "Shirt", look.shirtColour, named(p.shirts.keys), (v) => look.copyWith(shirtColour: v)),
      pick("shirt", "Shirt style", look.shirt,
          [for (var n in ((p.shirts[look.shirtColour]?.keys ?? const <int>[]).toList()..sort())) (n, "Style $n")],
          (v) => look.copyWith(shirt: v)),
      pick("sleeves", "Sleeves", look.sleeves, lengths, (v) => look.copyWith(sleeves: v)),
      pick("pantsColour", "Trousers", look.pantsColour, named(p.pants.keys), (v) => look.copyWith(pantsColour: v)),
      pick("pants", "Trousers style", look.pants,
          [for (var n in ((p.pants[look.pantsColour]?.keys ?? const <int>[]).toList()..sort())) (n, "Style $n")],
          (v) => look.copyWith(pants: v)),
      pick("legs", "Legs", look.legs, lengths, (v) => look.copyWith(legs: v)),
      pick("shoeColour", "Shoes", look.shoeColour, named(p.shoes.keys), (v) => look.copyWith(shoeColour: v)),
      pick("shoe", "Shoe style", look.shoe,
          [for (var n in ((p.shoes[look.shoeColour]?.keys ?? const <int>[]).toList()..sort())) (n, "Style $n")],
          (v) => look.copyWith(shoe: v)),
    ];
  }
}

class _FigurePainter extends CustomPainter {
  final ModularParts parts;
  final ModularLook look;
  final Map<String, ui.Image?> pieces;
  _FigurePainter(this.parts, this.look, this.pieces);

  @override
  void paint(Canvas canvas, Size size) {
    var scale = size.height / modularCell.height;
    paintModular(canvas, pieces, parts, look, const ModularPose(), Offset(size.width / 2, size.height - 4), scale);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => !identical(old.pieces, pieces) || !identical(old.look, look);
}
