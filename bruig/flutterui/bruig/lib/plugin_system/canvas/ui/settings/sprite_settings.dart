import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sprite_painting.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// sprite_settings.dart is a Sprite element's settings: its sheet, brought
// in and sliced into frames; its actions, each a run of frames for each way
// it faces; and when on the timeline it changes action or turns.

/// spriteActionNames is the actions a sprite usually has, offered when one
/// is added.
const List<String> spriteActionNames = [
  "Idle", "Walk", "Run", "Jump", "Fall", "Attack", "Shoot", "Cast", "Hurt", "Die", "Climb",
];

/// spriteFromSheet is [e] made of the sheet stored as [id], called [name]:
/// [image] measured, sliced as [notes] say -- a sheet's .json beside it --
/// or by the gaps between its frames, and an action for each tag the notes
/// give, or for each row of the grid, for a start.
Future<SpriteElement> spriteFromSheet(SpriteElement e, String id, String name, ui.Image image,
    {SheetNotes? notes}) async {
  var w = image.width, h = image.height;
  if (notes != null) {
    var actions = notes.actions.isNotEmpty
        ? notes.actions
        : [
            SpriteAction("Play",
                frames: {SpriteFacing.front: [for (var i = 0; i < notes.frames.length; i++) i]}),
          ];
    return e.copyWith(
        sheet: id,
        sheetName: name,
        sheetW: notes.width,
        sheetH: notes.height,
        rects: notes.frames,
        columns: 1,
        rows: 1,
        actions: actions,
        action: actions.first.name,
        cues: const []);
  }
  var (cols, rows) = await findGrid(image) ?? (1, 1);
  var made = e.copyWith(
      sheet: id,
      sheetName: name,
      sheetW: w,
      sheetH: h,
      rects: const [],
      columns: cols,
      rows: rows,
      margin: 0,
      spacing: 0,
      cues: const []);
  var actions = [
    for (var r = 0; r < rows; r++)
      SpriteAction(rows == 1 ? "Play" : "Row ${r + 1}", frames: {SpriteFacing.front: made.row(r)}),
  ];
  return made.copyWith(actions: actions, action: actions.first.name);
}

/// findGrid is the grid [image]'s frames are laid out in, from the clear
/// columns and rows between them, or null when it cannot tell.
Future<(int, int)?> findGrid(ui.Image image) async {
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;
  var w = image.width;
  bool clear(int x, int y) => data.getUint8((y * w + x) * 4 + 3) < 8;
  return gridFromGaps(w, image.height, clear);
}

/// readSheet reads the file at [file] -- a picture, or a sheet's .json
/// with its picture beside it -- stores the picture, and gives [e] made of
/// it; or says why it could not.
Future<(SpriteElement?, String)> readSheet(SpriteElement e, String file) async {
  try {
    SheetNotes? notes;
    var picture = file;
    if (file.toLowerCase().endsWith(".json")) {
      notes = SheetNotes.read(await File(file).readAsString());
      if (notes == null) return (null, "That .json does not describe a sprite sheet.");
      var beside = path.join(path.dirname(file),
          notes.image.isNotEmpty ? notes.image : "${path.basenameWithoutExtension(file)}.png");
      if (!await File(beside).exists()) {
        return (null, "The sheet's picture, ${path.basename(beside)}, is not beside its .json.");
      }
      picture = beside;
    }
    var bytes = await File(picture).readAsBytes();
    var id = await CanvasAssets.save(bytes);
    if (id == null) return (null, "That picture could not be stored.");
    var name = path.basenameWithoutExtension(picture);
    await CanvasLibrary.addPicture(id, name, bytes);
    var codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    var image = (await codec.getNextFrame()).image;
    var made = await spriteFromSheet(e, id, name, image, notes: notes);
    var said = notes != null
        ? "${made.frameCount} frames and ${made.actions.length} actions, from its notes."
        : made.frameCount > 1
            ? "Sliced into ${made.columns} by ${made.rows} frames. Check the grid below."
            : "Set the grid below: how many frames across and down.";
    return (made, said);
  } on FileSystemException {
    return (null, "That file could not be opened.");
  } catch (_) {
    return (null, "That file could not be read as a picture.");
  }
}

List<Widget> spriteSettings(BuildContext context, CanvasController controller, SpriteElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(SpriteElement next) {
    begin();
    write(next);
    commit();
  }

  var action = e.actionNamed(e.action) ?? e.actions.firstOrNull;
  var painting = controller.spritePaint?.id == e.id ? controller.spritePaint : null;
  return [
    section(e, "spriteSheet",
        icon: Icons.grid_on,
        title: "Sheet",
        summary: e.hasSheet
            ? "${e.sheetName.isEmpty ? "Sheet" : e.sheetName} · ${e.frameCount} frames"
            : "None yet",
        initiallyOpen: true,
        children: [
          SpriteSheetPicker(key: ValueKey("spriteImport-${e.id}"), controller: controller, sprite: e),
          if (!e.hasSheet) BlankSheetMaker(key: ValueKey("spriteBlank-${e.id}"), controller: controller, sprite: e),
          if (e.hasSheet) ...[
            SpriteSheetView(
              key: const ValueKey("spriteSheetView"),
              controller: controller,
              sprite: e,
              onTapFrame: action == null
                  ? null
                  : (i) {
                      var face = e.directions ? e.facing : SpriteFacing.front;
                      var own = action.frames[face] ?? const <int>[];
                      now(e.withAction(action.withFrames(face, [...own, i])));
                    },
            ),
            if (e.rects.isEmpty)
              CanvasControlGroup(
                key: const ValueKey("spriteGrid"),
                label: "Grid",
                help: "How the sheet is cut into frames: how many across and "
                    "down, how far in from the edge the first one starts, and "
                    "the gap between them, in the sheet's pixels.",
                children: [
                  for (var (key, label, value, max, set) in [
                    ("spriteColumns", "Across", e.columns.toDouble(), 64.0,
                        (double v) => e.copyWith(columns: v.round())),
                    ("spriteRows", "Down", e.rows.toDouble(), 64.0,
                        (double v) => e.copyWith(rows: v.round())),
                    ("spriteMargin", "Margin", e.margin, 256.0, (double v) => e.copyWith(margin: v)),
                    ("spriteSpacing", "Gap", e.spacing, 256.0, (double v) => e.copyWith(spacing: v)),
                  ])
                    CanvasStepper(
                      key: ValueKey(key),
                      label: label,
                      value: value,
                      min: key == "spriteColumns" || key == "spriteRows" ? 1 : 0,
                      max: max,
                      step: 1,
                      onChanged: (v) => write(set(v)),
                      onCommit: commit,
                    ),
                  CanvasTextButton(
                    key: const ValueKey("spriteFindGrid"),
                    label: "Find the grid",
                    icon: Icons.auto_fix_high,
                    onPressed: () async {
                      var image = controller.images.resolve(e.sheet, const BackgroundRemoval());
                      if (image == null) return;
                      if (await findGrid(image) case (var c, var r)) {
                        now(e.copyWith(columns: c, rows: r, margin: 0, spacing: 0));
                      }
                    },
                  ),
                ],
              ),
            CanvasToggle(
              key: const ValueKey("spritePixelArt"),
              label: "Pixel art: square pixels",
              value: e.pixelArt,
              onChanged: (v) => now(e.copyWith(pixelArt: v)),
            ),
          ],
        ]),
    section(e, "spriteActions",
        icon: Icons.movie_filter_outlined,
        title: "Animations",
        summary: action == null ? "None" : "${action.name}${e.directions ? " · ${e.facing.label}" : ""}",
        initiallyOpen: true,
        children: [
          if (e.hasSheet)
            AnimationsEditor(
                key: ValueKey("spriteAnimations-${e.id}"),
                controller: controller,
                sprite: e,
                write: write,
                commit: commit)
          else
            const CanvasStatus("Bring in a sheet, or paint a new one: its frames are "
                "what each animation is played from."),
        ]),
    if (e.hasSheet)
      section(e, "spritePaint",
          icon: Icons.brush_outlined,
          title: "Paint",
          summary: painting == null ? "Off" : "Frame ${painting.frame + 1} · ${painting.tool.label}",
          children: [_paintGroup(controller, e, painting)]),
    if (e.hasSheet && e.actions.isNotEmpty)
      section(e, "spriteCues",
          icon: Icons.schedule,
          title: "On the timeline",
          summary: e.cues.isEmpty ? "One animation" : "${e.cues.length} cues",
          children: [_cuesGroup(controller, e, now)]),
  ];
}

/// _paintGroup is painting the sprite's frames on the canvas, a pixel at a
/// time: on and off, the tool, its colour and size, the frame painted, the
/// one before shown faintly, and frames added or copied.
Widget _paintGroup(CanvasController controller, SpriteElement e, SpritePaintSession? painting) {
  return CanvasControlGroup(
    key: const ValueKey("spritePaintGroup"),
    label: "Paint frames",
    help: "Paint the frames pixel by pixel, right on the sprite on the "
        "canvas: the frame shown big, the one before it faint under it. Each "
        "stroke is one undo.",
    children: [
      CanvasToggle(
        key: const ValueKey("spritePaintOn"),
        label: "Paint on the canvas",
        value: painting != null,
        onChanged: (v) => controller.paintSprite(v ? e.id : null),
      ),
      if (painting != null) ...[
        CanvasTiles<SpriteTool>(
          key: const ValueKey("spritePaintTools"),
          columns: 5,
          previewHeight: 24,
          tiles: [
            for (var t in SpriteTool.values)
              CanvasTile(t, t.label,
                  icon: switch (t) {
                    SpriteTool.pencil => Icons.edit,
                    SpriteTool.eraser => Icons.auto_fix_normal,
                    SpriteTool.fill => Icons.format_color_fill,
                    SpriteTool.picker => Icons.colorize,
                    SpriteTool.line => Icons.horizontal_rule,
                  }),
          ],
          selected: (t) => t == painting.tool,
          keyOf: (t) => "spritePaintTool-${t.name}",
          onPick: (t) => painting.set(tool: t),
        ),
        CanvasColorButton(
          key: const ValueKey("spritePaintColour"),
          label: "Colour",
          color: painting.colour,
          onChanged: (c) => painting.set(colour: c),
        ),
        CanvasStepper(
          key: const ValueKey("spritePaintSize"),
          label: "Size",
          value: painting.size.toDouble(),
          min: 1,
          max: 16,
          step: 1,
          defaultValue: 1,
          onChanged: (v) => painting.set(size: v.round()),
        ),
        CanvasStepper(
          key: const ValueKey("spritePaintFrame"),
          label: "Frame",
          value: painting.frame + 1.0,
          min: 1,
          max: math.max(1, e.frameCount).toDouble(),
          step: 1,
          onChanged: (v) => painting.set(frame: v.round() - 1),
        ),
        CanvasToggle(
          key: const ValueKey("spritePaintOnion"),
          label: "Show the frame before",
          value: painting.onion,
          onChanged: (v) => painting.set(onion: v),
        ),
        CanvasToggle(
          key: const ValueKey("spritePaintGrid"),
          label: "Rule the pixels",
          value: painting.grid,
          onChanged: (v) => painting.set(grid: v),
        ),
        if (e.rects.isEmpty) ...[
          CanvasTextButton(
            key: const ValueKey("spritePaintAddFrame"),
            label: "Add a frame",
            icon: Icons.add_box_outlined,
            onPressed: () => painting.addFrame(),
          ),
          CanvasTextButton(
            key: const ValueKey("spritePaintCopyFrame"),
            label: "Copy this frame to a new one",
            icon: Icons.copy_all_outlined,
            onPressed: () => painting.addFrame(copy: true),
          ),
        ],
      ],
    ],
  );
}

/// BlankSheetMaker makes a new, clear sheet to paint: so many frames of so
/// many pixels.
class BlankSheetMaker extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  const BlankSheetMaker({required this.controller, required this.sprite, super.key});

  @override
  State<BlankSheetMaker> createState() => BlankSheetMakerState();
}

class BlankSheetMakerState extends State<BlankSheetMaker> {
  int _w = 32, _h = 32, _count = 4;

  Future<void> make() async {
    var c = widget.controller;
    var made = await blankSprite(c, widget.sprite, _w, _h, _count);
    if (made == null) return;
    c.beginInteraction();
    var box = made.base;
    c.replaceElement(made.rebase(box.copyWith(width: box.height * _w / _h, lockAspect: true)));
    c.endInteraction();
    c.paintSprite(made.id);
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
        key: const ValueKey("spriteBlankGroup"),
        label: "Or paint one",
        help: "A clear sheet of frames to paint pixel by pixel, on the canvas.",
        children: [
          CanvasStepper(
            key: const ValueKey("spriteBlankWidth"),
            label: "Width",
            value: _w.toDouble(),
            min: 4,
            max: 256,
            step: 1,
            suffix: " px",
            onChanged: (v) => setState(() => _w = v.round()),
          ),
          CanvasStepper(
            key: const ValueKey("spriteBlankHeight"),
            label: "Height",
            value: _h.toDouble(),
            min: 4,
            max: 256,
            step: 1,
            suffix: " px",
            onChanged: (v) => setState(() => _h = v.round()),
          ),
          CanvasStepper(
            key: const ValueKey("spriteBlankFrames"),
            label: "Frames",
            value: _count.toDouble(),
            min: 1,
            max: 32,
            step: 1,
            onChanged: (v) => setState(() => _count = v.round()),
          ),
          CanvasTextButton(
            key: const ValueKey("spriteBlankMake"),
            label: "Paint a new sheet",
            icon: Icons.brush_outlined,
            primary: true,
            onPressed: make,
          ),
        ],
      );
}

/// AnimationsEditor is the sprite's animations, as Godot's sprite frames
/// editor lays them out: the animation picked -- added, named, copied,
/// taken away -- playing in a preview; its frames in order, each one
/// moved, copied or taken out with buttons, or added from the sheet;
/// how fast, and whether it loops. A figure's has directions: frames for
/// each way it faces.
class AnimationsEditor extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  final SettingsWrite write;
  final VoidCallback commit;
  const AnimationsEditor(
      {required this.controller,
      required this.sprite,
      required this.write,
      required this.commit,
      super.key});

  @override
  State<AnimationsEditor> createState() => AnimationsEditorState();
}

class AnimationsEditorState extends State<AnimationsEditor> {
  /// _picked is the frame of the strip picked, by its place in it.
  int _picked = -1;
  String _typed = "";

  SpriteElement get e => widget.sprite;

  void _now(SpriteElement next) {
    widget.controller.beginInteraction();
    widget.write(next);
    widget.commit();
  }

  SpriteFacing get _face => e.directions ? e.facing : SpriteFacing.front;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var action = e.actionNamed(e.action) ?? e.actions.firstOrNull;
    var names = {for (var a in e.actions) a.name};
    String fresh() {
      var n = 1;
      while (names.contains("Animation $n")) {
        n++;
      }
      return "Animation $n";
    }

    var (shown, flipped) = action?.framesFor(_face, mirrorSides: e.mirrorSides) ?? (const <int>[], false);
    var own = action?.frames[_face] ?? const <int>[];
    var picked = _picked >= 0 && _picked < own.length ? _picked : -1;
    void setFrames(List<int> list, {int? pick}) {
      if (action == null) return;
      setState(() => _picked = pick ?? -1);
      _now(e.withAction(action.withFrames(_face, list)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CanvasControlGroup(
        key: const ValueKey("spriteActionGroup"),
        label: "Animation",
        help: "What it plays: walk, flicker, spin, open. Each is a run of the "
            "sheet's frames at its own speed. Turn on directions for a "
            "figure, to give each way it faces frames of its own.",
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("spriteAction"),
            label: "Animation",
            value: action?.name ?? "",
            options: [
              if (action == null) ("", "None"),
              for (var a in e.actions) (a.name, a.name),
            ],
            onChanged: (n) => _now(e.copyWith(action: n)),
          ),
          CanvasDropdown<String>(
            key: const ValueKey("spriteActionAdd"),
            label: "Add",
            value: "",
            options: [
              ("", "Add an animation…"),
              ("+", "A new one"),
              for (var n in spriteActionNames)
                if (!names.contains(n)) (n, n),
            ],
            onChanged: (n) {
              if (n.isEmpty) return;
              var name = n == "+" ? fresh() : n;
              _now(e.withAction(SpriteAction(name)).copyWith(action: name));
            },
          ),
          if (action != null) ...[
            CanvasTextField(
              key: ValueKey("spriteActionName-${action.name}"),
              label: "Name",
              value: action.name,
              // Renamed once typed, not at every letter: cues follow it.
              onChanged: (v) => _typed = v,
              onCommit: () {
                var name = _typed.trim();
                if (name.isEmpty || name == action.name || names.contains(name)) return;
                _now(e.withAction(action.copyWith(name: name), replacing: action.name).copyWith(
                    action: name,
                    cues: [
                      for (var c in e.cues)
                        (frame: c.frame, action: c.action == action.name ? name : c.action, facing: c.facing)
                    ]));
              },
            ),
            CanvasTextButton(
              key: const ValueKey("spriteActionCopy"),
              label: "Copy",
              icon: Icons.copy_outlined,
              onPressed: () {
                var name = "${action.name} copy";
                var n = 2;
                while (names.contains(name)) {
                  name = "${action.name} copy ${n++}";
                }
                _now(e.withAction(action.copyWith(name: name)).copyWith(action: name));
              },
            ),
            if (e.actions.length > 1)
              CanvasTextButton(
                key: const ValueKey("spriteActionRemove"),
                label: "Remove",
                icon: Icons.delete_outline,
                onPressed: () {
                  var rest = [for (var a in e.actions) if (a.name != action.name) a];
                  _now(e.copyWith(
                      actions: rest,
                      action: rest.first.name,
                      cues: [for (var c in e.cues) if (c.action != action.name) c]));
                },
              ),
          ],
        ],
      ),
      if (action != null) ...[
        CanvasToggle(
          key: const ValueKey("spriteDirections"),
          label: "Directions: frames for each way it faces",
          value: e.directions,
          onChanged: (v) => _now(e.copyWith(directions: v)),
        ),
        if (e.directions)
          CanvasTiles<SpriteFacing>(
            key: const ValueKey("spriteFacing"),
            label: "Facing",
            columns: 4,
            previewHeight: 22,
            tiles: [
              for (var f in SpriteFacing.values)
                CanvasTile(f, f.label,
                    icon: switch (f) {
                      SpriteFacing.front => Icons.south,
                      SpriteFacing.back => Icons.north,
                      SpriteFacing.left => Icons.west,
                      SpriteFacing.right => Icons.east,
                    }),
            ],
            selected: (f) => f == e.facing,
            keyOf: (f) => "spriteFacing-${f.name}",
            onPick: (f) => _now(e.copyWith(facing: f)),
          ),
        // Playing, as it will on the canvas.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SpritePreview(
              key: const ValueKey("spritePreview"),
              controller: widget.controller,
              sprite: e,
              frames: shown,
              flipped: flipped,
              fps: action.fps,
              loop: action.loop),
        ),
        // The frames, in order.
        SizedBox(
          height: 64,
          child: own.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: CanvasStatus(shown.isEmpty
                      ? "No frames yet: click them on the sheet above, or use a row."
                      : flipped
                          ? "The other side, flipped. Click frames to give it its own."
                          : "The front's frames. Click frames to give it its own."))
              : ListView(
                  key: const ValueKey("spriteFrames"),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var (k, i) in own.indexed)
                      GestureDetector(
                        key: ValueKey("spriteFrame-$k"),
                        onTap: () => setState(() => _picked = k == picked ? -1 : k),
                        child: Container(
                          width: 52,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                width: k == picked ? 2 : 1,
                                color: k == picked ? theme.colors.primary : theme.colors.outlineVariant),
                          ),
                          child: Column(children: [
                            Expanded(
                                child: SpriteFrameThumb(
                                    controller: widget.controller, sprite: e, index: i)),
                            Text("${k + 1}",
                                style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant)),
                          ]),
                        ),
                      ),
                  ],
                ),
        ),
        Wrap(spacing: 2, children: [
          CanvasIconButton(
            key: const ValueKey("spriteFrameEarlier"),
            icon: Icons.chevron_left,
            tooltip: "Move the picked frame earlier",
            onPressed: picked > 0
                ? () => setFrames([...own]
                  ..removeAt(picked)
                  ..insert(picked - 1, own[picked]), pick: picked - 1)
                : null,
          ),
          CanvasIconButton(
            key: const ValueKey("spriteFrameLater"),
            icon: Icons.chevron_right,
            tooltip: "Move the picked frame later",
            onPressed: picked >= 0 && picked < own.length - 1
                ? () => setFrames([...own]
                  ..removeAt(picked)
                  ..insert(picked + 1, own[picked]), pick: picked + 1)
                : null,
          ),
          CanvasIconButton(
            key: const ValueKey("spriteFrameCopy"),
            icon: Icons.copy_outlined,
            tooltip: "Play the picked frame twice",
            onPressed: picked >= 0
                ? () => setFrames([...own]..insert(picked + 1, own[picked]), pick: picked + 1)
                : null,
          ),
          CanvasIconButton(
            key: const ValueKey("spriteFrameRemove"),
            icon: Icons.delete_outline,
            tooltip: "Take the picked frame out",
            onPressed: picked >= 0 ? () => setFrames([...own]..removeAt(picked)) : null,
          ),
          CanvasIconButton(
            key: const ValueKey("spriteFramesClear"),
            icon: Icons.clear_all,
            tooltip: "Take every frame out",
            onPressed: own.isNotEmpty ? () => setFrames(const []) : null,
          ),
        ]),
        CanvasDropdown<int>(
          key: const ValueKey("spriteUseRow"),
          label: "Use a row",
          value: -1,
          options: [
            (-1, "Pick a row…"),
            if (e.rects.isEmpty)
              for (var r = 0; r < e.rows; r++) (r, "Row ${r + 1}"),
            (-2, "Every frame"),
          ],
          onChanged: (r) {
            if (r == -1) return;
            setFrames(r == -2 ? [for (var i = 0; i < e.frameCount; i++) i] : e.row(r));
          },
        ),
        CanvasStepper(
          key: const ValueKey("spriteFps"),
          label: "Speed",
          value: action.fps,
          min: 1,
          max: 30,
          step: 1,
          suffix: " fps",
          defaultValue: 8,
          onChanged: (v) => widget.write(e.withAction(action.copyWith(fps: v))),
          onCommit: widget.commit,
        ),
        CanvasToggle(
          key: const ValueKey("spriteLoop"),
          label: "Loop",
          value: action.loop,
          onChanged: (v) => _now(e.withAction(action.copyWith(loop: v))),
        ),
        if (e.directions)
          CanvasToggle(
            key: const ValueKey("spriteMirror"),
            label: "Mirror an empty side",
            value: e.mirrorSides,
            onChanged: (v) => _now(e.copyWith(mirrorSides: v)),
          ),
      ],
    ]);
  }
}

/// SpriteFrameThumb is frame [index] of [sprite]'s sheet, fitted to it.
class SpriteFrameThumb extends StatelessWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  final int index;
  final bool flipped;
  const SpriteFrameThumb(
      {required this.controller, required this.sprite, required this.index, this.flipped = false, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller.images,
        builder: (context, _) {
          var painting = controller.spritePaint;
          var live = painting != null && painting.id == sprite.id
              ? painting.view(sprite).live
              : null;
          var image = live ?? controller.images.resolve(sprite.sheet, const BackgroundRemoval());
          return CustomPaint(
              size: Size.infinite,
              painter: _FramePainter(sprite, image, index, flipped));
        },
      );
}

class _FramePainter extends CustomPainter {
  final SpriteElement e;
  final ui.Image? image;
  final int index;
  final bool flipped;
  _FramePainter(this.e, this.image, this.index, this.flipped);

  @override
  void paint(Canvas canvas, Size size) {
    var img = image;
    if (img == null || e.frameCount == 0) return;
    var src = spriteSource(e, index.clamp(0, e.frameCount - 1), img);
    if (src.isEmpty) return;
    var dst = spriteFit(src.size, (Offset.zero & size).deflate(3));
    if (flipped) {
      canvas.translate(dst.center.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-dst.center.dx, 0);
    }
    canvas.drawImageRect(
        img, src, dst, Paint()..filterQuality = e.pixelArt ? FilterQuality.none : FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      !identical(old.e, e) || old.image != image || old.index != index || old.flipped != flipped;
}

/// SpritePreview plays [frames] of [sprite] at [fps], over and over or
/// once, with a button to stop and start it.
class SpritePreview extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  final List<int> frames;
  final bool flipped;
  final double fps;
  final bool loop;
  const SpritePreview(
      {required this.controller,
      required this.sprite,
      required this.frames,
      required this.flipped,
      required this.fps,
      required this.loop,
      super.key});

  @override
  State<SpritePreview> createState() => SpritePreviewState();
}

class SpritePreviewState extends State<SpritePreview> with SingleTickerProviderStateMixin {
  /// _ticker is made when it first plays -- and only then, not while the
  /// panel is being taken down.
  Ticker? _ticker;
  Duration _at = Duration.zero;

  /// _playing is whether it plays: not until asked, as Godot's preview --
  /// a settings panel left open is not left spinning.
  bool _playing = false;

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _tick(Duration t) => setState(() => _at = t);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var list = widget.frames;
    var k = (_at.inMicroseconds / 1e6 * widget.fps).floor();
    var shown = list.isEmpty
        ? -1
        : list[widget.loop ? k % list.length : math.min(k, list.length - 1)];
    return Row(children: [
      Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colors.outlineVariant),
        ),
        child: shown < 0
            ? null
            : SpriteFrameThumb(
                controller: widget.controller, sprite: widget.sprite, index: shown, flipped: widget.flipped),
      ),
      const SizedBox(width: 8),
      CanvasIconButton(
        key: const ValueKey("spritePreviewPlay"),
        icon: _playing ? Icons.pause : Icons.play_arrow,
        tooltip: _playing ? "Stop the preview" : "Play the preview",
        onPressed: () {
          setState(() => _playing = !_playing);
          var ticker = _ticker ??= createTicker(_tick);
          if (_playing) {
            ticker.start();
          } else {
            ticker.stop();
          }
        },
      ),
      Expanded(
        child: Text(
            shown < 0 ? "" : "Frame ${list.indexOf(shown) + 1} of ${list.length}",
            style: TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      ),
    ]);
  }
}

/// _cuesGroup is where on the timeline it changes animation, or turns.
Widget _cuesGroup(CanvasController controller, SpriteElement e, void Function(SpriteElement) now) {
  var frame = controller.frame;
  var here = e.cues.where((c) => c.frame == frame).firstOrNull;
  var turn = e.directions ? " facing ${e.facing.label.toLowerCase()}" : "";
  return CanvasControlGroup(
    key: const ValueKey("spriteCueGroup"),
    label: "Cues",
    help: "Where on the timeline it changes what it plays -- or, with "
        "directions, the way it faces: from the frame the playhead is on "
        "until the next cue.",
    children: [
      CanvasTextButton(
        key: const ValueKey("spriteCueAdd"),
        label: here == null ? "Cue ${e.action}$turn here" : "Change this cue",
        icon: Icons.add_alarm,
        onPressed: () => now(e.copyWith(cues: [
          for (var c in e.cues)
            if (c.frame != frame) c,
          (frame: frame, action: e.action, facing: e.directions ? e.facing : null),
        ]..sort((a, b) => a.frame.compareTo(b.frame)))),
      ),
      for (var (k, c) in e.cues.indexed)
        CanvasChip(
          key: ValueKey("spriteCue-$k"),
          label: "${c.frame}: ${c.action}${c.facing == null ? "" : " · ${c.facing!.label}"}",
          here: c.frame == frame,
          onRemove: () => now(e.copyWith(cues: [...e.cues]..removeAt(k))),
        ),
    ],
  );
}

/// SpriteSheetPicker brings a sheet in: a picture, or a sheet's .json with
/// its picture beside it.
class SpriteSheetPicker extends StatefulWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  const SpriteSheetPicker({required this.controller, required this.sprite, super.key});

  @override
  State<SpriteSheetPicker> createState() => SpriteSheetPickerState();
}

class SpriteSheetPickerState extends State<SpriteSheetPicker> {
  String _said = "";

  Future<void> importFrom(String file) async {
    var (made, said) = await readSheet(widget.sprite, file);
    if (made != null) {
      var c = widget.controller;
      c.beginInteraction();
      // The box takes a frame's own shape, as tall as it was.
      var f = made.frameRect(0).size;
      var box = made.base;
      var width = f.height <= 0 ? box.width : box.height * f.width / f.height;
      c.replaceElement(made.rebase(box.copyWith(width: width, lockAspect: true)));
      c.endInteraction();
    }
    if (mounted) setState(() => _said = said);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CanvasTextButton(
          key: const ValueKey("spriteImport"),
          label: widget.sprite.hasSheet ? "Bring in another sheet…" : "Bring in a sprite sheet…",
          icon: Icons.file_open_outlined,
          primary: !widget.sprite.hasSheet,
          onPressed: () async {
            var picked = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ["png", "gif", "webp", "jpg", "jpeg", "json"],
              withData: false,
            );
            var file = picked?.files.singleOrNull?.path;
            if (file != null) await importFrom(file);
          },
        ),
        CanvasStatus(_said.isNotEmpty
            ? _said
            : widget.sprite.hasSheet
                ? "Click a frame on the sheet to add it to the action, facing the way picked."
                : "A picture of the frames side by side, or an Aseprite or "
                    "TexturePacker .json with its picture beside it."),
      ]);
}

/// SpriteSheetView is the sheet with its frames marked on it, numbered,
/// the ones the action plays the way picked lit -- a click on one adding it.
class SpriteSheetView extends StatelessWidget {
  final CanvasController controller;
  final SpriteElement sprite;
  final ValueChanged<int>? onTapFrame;
  const SpriteSheetView({required this.controller, required this.sprite, this.onTapFrame, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var e = sprite;
    return ListenableBuilder(
      listenable: controller.images,
      builder: (context, _) {
        var image = controller.images.resolve(e.sheet, const BackgroundRemoval());
        return LayoutBuilder(builder: (context, room) {
          var w = room.maxWidth.isFinite ? room.maxWidth : 300.0;
          var k = w / math.max(1, e.sheetW);
          var h = math.min(e.sheetH * k, 360.0);
          k = math.min(k, h / math.max(1, e.sheetH));
          var action = e.actionNamed(e.action) ?? e.actions.firstOrNull;
          var lit = action?.framesFor(e.facing, mirrorSides: e.mirrorSides).$1 ?? const <int>[];
          return GestureDetector(
            onTapUp: onTapFrame == null
                ? null
                : (d) {
                    var p = d.localPosition / k;
                    for (var i = 0; i < e.frameCount; i++) {
                      if (e.frameRect(i).contains(p)) {
                        onTapFrame!(i);
                        return;
                      }
                    }
                  },
            child: Container(
              height: e.sheetH * k,
              width: e.sheetW * k,
              alignment: Alignment.topLeft,
              decoration: BoxDecoration(
                  color: theme.colors.surfaceContainerHighest,
                  border: Border.all(color: theme.colors.outlineVariant)),
              child: CustomPaint(
                size: Size(e.sheetW * k, e.sheetH * k),
                painter: _SheetPainter(e, image, k, lit.toSet(), theme.colors.primary),
              ),
            ),
          );
        });
      },
    );
  }
}

class _SheetPainter extends CustomPainter {
  final SpriteElement e;
  final ui.Image? image;
  final double k;
  final Set<int> lit;
  final Color accent;
  _SheetPainter(this.e, this.image, this.k, this.lit, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (image case var img?) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Offset.zero & size, Paint()..filterQuality = e.pixelArt ? FilterQuality.none : FilterQuality.medium);
    }
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.5);
    var on = Paint()..color = accent.withValues(alpha: 0.22);
    var tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < e.frameCount; i++) {
      var r = e.frameRect(i);
      var s = Rect.fromLTWH(r.left * k, r.top * k, r.width * k, r.height * k);
      if (lit.contains(i)) canvas.drawRect(s, on);
      canvas.drawRect(s, line);
      if (s.width > 14 && s.height > 12) {
        tp.text = TextSpan(
            text: "${i + 1}",
            style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.w600));
        tp.layout();
        tp.paint(canvas, s.topLeft + const Offset(2, 1));
      }
    }
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      !identical(old.e, e) || old.image != image || old.k != k || old.lit.length != lit.length;
}

/// spritePreviewRect is where frame [index] of [e] is drawn in a box
/// [size] across -- what a tile of it shows.
Rect spritePreviewRect(SpriteElement e, int index, Size size) =>
    spriteFit(e.frameRect(index).size, Offset.zero & size);
