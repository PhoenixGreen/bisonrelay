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
          if (e.hasSheet) ...[
            SpriteSheetView(
              key: const ValueKey("spriteSheetView"),
              controller: controller,
              sprite: e,
              onTapFrame: action == null
                  ? null
                  : (i) {
                      var (list, flipped) = action.framesFor(e.facing, mirrorSides: false);
                      var own = flipped ? <int>[] : list;
                      now(e.withAction(action.withFrames(e.facing, [...own, i])));
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
        icon: Icons.directions_run,
        title: "Actions",
        summary: action == null ? "None" : "${action.name} · ${e.facing.label}",
        initiallyOpen: true,
        children: [
          if (e.hasSheet)
            _actionsGroup(controller, e, action, now, write, commit)
          else
            const CanvasStatus("Bring in a sheet first: its frames are what each "
                "action -- standing, walking, jumping -- is played from."),
        ]),
    if (e.hasSheet && e.actions.isNotEmpty)
      section(e, "spriteCues",
          icon: Icons.schedule,
          title: "On the timeline",
          summary: e.cues.isEmpty ? "One action" : "${e.cues.length} cues",
          children: [_cuesGroup(controller, e, now)]),
  ];
}

Widget _actionsGroup(CanvasController controller, SpriteElement e, SpriteAction? action,
    void Function(SpriteElement) now, SettingsWrite write, VoidCallback commit) {
  var names = {for (var a in e.actions) a.name};
  var typed = action?.name ?? "";
  return CanvasControlGroup(
    key: const ValueKey("spriteActionGroup"),
    label: "Action",
    help: "What it does, and the frames it does it with for each way it "
        "faces. Pick a way to face, then click frames on the sheet above in "
        "the order they play -- or use a whole row. A side left empty is the "
        "other side, flipped.",
    children: [
      CanvasDropdown<String>(
        key: const ValueKey("spriteAction"),
        label: "Action",
        value: action?.name ?? "",
        options: [
          if (action == null) ("", "None"),
          for (var a in e.actions) (a.name, a.name),
        ],
        onChanged: (n) => now(e.copyWith(action: n)),
      ),
      CanvasDropdown<String>(
        key: const ValueKey("spriteActionAdd"),
        label: "Add",
        value: "",
        options: [
          ("", "Add an action…"),
          for (var n in spriteActionNames)
            if (!names.contains(n)) (n, n),
        ],
        onChanged: (n) {
          if (n.isEmpty) return;
          now(e.withAction(SpriteAction(n)).copyWith(action: n));
        },
      ),
      if (action != null) ...[
        CanvasTextField(
          key: ValueKey("spriteActionName-${action.name}"),
          label: "Name",
          value: action.name,
          // Renamed once typed, not at every letter: cues follow it.
          onChanged: (v) => typed = v,
          onCommit: () {
            var name = typed.trim();
            if (name.isEmpty || name == action.name || names.contains(name)) return;
            now(e.withAction(action.copyWith(name: name), replacing: action.name).copyWith(
                action: name,
                cues: [
                  for (var c in e.cues)
                    (frame: c.frame, action: c.action == action.name ? name : c.action, facing: c.facing)
                ]));
          },
        ),
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
          onPick: (f) => now(e.copyWith(facing: f)),
        ),
        _framesRow(e, action, now),
        CanvasDropdown<int>(
          key: const ValueKey("spriteUseRow"),
          label: "Use a row",
          value: -1,
          options: [
            (-1, "Pick a row…"),
            if (e.rects.isEmpty)
              for (var r = 0; r < e.rows; r++) (r, "Row ${r + 1}")
            else
              (-2, "Every frame"),
          ],
          onChanged: (r) {
            if (r == -1) return;
            var frames = r == -2 ? [for (var i = 0; i < e.frameCount; i++) i] : e.row(r);
            now(e.withAction(action.withFrames(e.facing, frames)));
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
          onChanged: (v) => write(e.withAction(action.copyWith(fps: v))),
          onCommit: commit,
        ),
        CanvasToggle(
          key: const ValueKey("spriteLoop"),
          label: "Loop",
          value: action.loop,
          onChanged: (v) => now(e.withAction(action.copyWith(loop: v))),
        ),
        CanvasToggle(
          key: const ValueKey("spriteMirror"),
          label: "Mirror an empty side",
          value: e.mirrorSides,
          onChanged: (v) => now(e.copyWith(mirrorSides: v)),
        ),
        if (e.actions.length > 1)
          CanvasTextButton(
            key: const ValueKey("spriteActionRemove"),
            label: "Remove ${action.name}",
            icon: Icons.delete_outline,
            onPressed: () {
              var rest = [for (var a in e.actions) if (a.name != action.name) a];
              now(e.copyWith(
                  actions: rest,
                  action: rest.first.name,
                  cues: [for (var c in e.cues) if (c.action != action.name) c]));
            },
          ),
      ],
    ],
  );
}

/// _framesRow is the frames the action plays facing the way picked, in
/// order: each one taken out with a click, or all of them.
Widget _framesRow(SpriteElement e, SpriteAction action, void Function(SpriteElement) now) {
  var (list, flipped) = action.framesFor(e.facing, mirrorSides: e.mirrorSides);
  var own = action.frames[e.facing] ?? const <int>[];
  return Wrap(
    key: const ValueKey("spriteFrames"),
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (own.isEmpty)
        CanvasStatus(list.isEmpty
            ? "No frames yet: click them on the sheet."
            : flipped
                ? "The other side, flipped."
                : "The ${e.facing == SpriteFacing.front ? "first" : "front's"} frames, as none of its own.")
      else ...[
        for (var (k, i) in own.indexed)
          CanvasChip(
            key: ValueKey("spriteFrame-$k"),
            label: "${i + 1}",
            onRemove: () {
              var next = [...own]..removeAt(k);
              now(e.withAction(action.withFrames(e.facing, next)));
            },
          ),
        CanvasTextButton(
          key: const ValueKey("spriteFramesClear"),
          label: "Clear",
          icon: Icons.clear,
          onPressed: () => now(e.withAction(action.withFrames(e.facing, const []))),
        ),
      ],
    ],
  );
}

Widget _cuesGroup(CanvasController controller, SpriteElement e, void Function(SpriteElement) now) {
  var frame = controller.frame;
  var here = e.cues.where((c) => c.frame == frame).firstOrNull;
  return CanvasControlGroup(
    key: const ValueKey("spriteCueGroup"),
    label: "Cues",
    help: "Where on the timeline it changes what it does, or the way it "
        "faces: from the frame the playhead is on until the next cue.",
    children: [
      CanvasTextButton(
        key: const ValueKey("spriteCueAdd"),
        label: here == null ? "Cue ${e.action} facing ${e.facing.label.toLowerCase()} here" : "Change this cue",
        icon: Icons.add_alarm,
        onPressed: () => now(e.copyWith(cues: [
          for (var c in e.cues)
            if (c.frame != frame) c,
          (frame: frame, action: e.action, facing: e.facing),
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
