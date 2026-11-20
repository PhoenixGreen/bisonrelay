import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/send_to_chat.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/image_action_file.dart';
import 'package:bruig/plugin_system/canvas/model/lightroom_preset.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/presets/image_looks.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart'
    show readColourTableFile;
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// image_actions.dart is a picture's actions: a set of steps -- adjustments,
// textures, colour layers, copies of the picture, the picture's own effects
// -- done to it in one go, as a photo editor's actions are. Every step is a
// layer, there to be changed afterwards, so the layers a picture has are
// already the recording: saving one keeps the layers chosen.
//
// The actions that come with the app first, then the ones kept here (the
// looks folder, which they grew from); each tried on the canvas as the
// pointer passes, done with a click. Added on top of what the picture has,
// or in place of its look.

/// _replacing is whether an action takes the place of the picture's look
/// (true) or is added to it, remembered for the run.
bool _replacing = false;

/// ImageActions is the Actions section's body.
class ImageActions extends StatefulWidget {
  final CanvasController controller;
  final ImageElement element;
  const ImageActions(
      {required this.controller, required this.element, super.key});

  @override
  State<ImageActions> createState() => _ImageActionsState();
}

class _ImageActionsState extends State<ImageActions> {
  final store = SavedPresetStore.looks;

  /// _done is the action last done here, offered to send or delete.
  String? _done;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));

  ImageElement _with(SavedPreset p) =>
      withLookApplied(widget.element, p.data, replace: _replacing);

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: store, builder: (context, _) => _body());

  Widget _body() {
    var controller = widget.controller;
    var e = widget.element;
    var offered = [...builtInLooks, ...store.presets];
    var images = controller.images;
    var picture = e.hasImage ? images.resolve(e.assetId, e.removal) : null;
    var done = store.presets.where((p) => p.id == _done).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CanvasControlGroup(
          key: const ValueKey("imageActionMode"),
          label: "Each action",
          rule: false,
          children: [
            CanvasSegmented<bool>(
              key: const ValueKey("imageActionReplace"),
              options: const [
                (false, "Adds to it"),
                (true, "Replaces its look")
              ],
              value: _replacing,
              keyOf: (r) => r ? "imageActionReplaces" : "imageActionAdds",
              onChanged: (r) => setState(() => _replacing = r),
            ),
          ],
        ),
        CanvasTiles<String>(
          key: const ValueKey("imageActionTiles"),
          help: "Point at an action to see it on the canvas; click it to do "
              "it. Every step becomes a layer, there to change afterwards.",
          columns: 3,
          previewHeight: 52,
          tiles: [
            for (var p in offered)
              CanvasTile(p.id, p.name,
                  drawnFrom: (
                    p.id,
                    e.assetId,
                    e.removal,
                    picture != null,
                    _replacing
                  ),
                  paint: (canvas, size) =>
                      _paintWearing(canvas, size, _with(p), images)),
          ],
          selected: (id) => id == _done,
          keyOf: (id) => "imageAction-$id",
          onPreview: (id) {
            var p = offered.where((p) => p.id == id).firstOrNull;
            controller.tryElement(p == null ? null : _with(p));
          },
          onPick: (id) {
            var p = offered.where((p) => p.id == id).firstOrNull;
            if (p == null) return;
            setState(() => _done = p.id);
            controller.changeImage(_with(p));
          },
        ),
        CanvasControlGroup(
          key: const ValueKey("imageActionKeep"),
          label: "Yours",
          rule: false,
          children: [
            CanvasIconButton(
              key: const ValueKey("imageActionSave"),
              icon: Icons.bookmark_add_outlined,
              tooltip: "Save this picture's steps as an action",
              onPressed: e.stack.any((l) => inLook(e, l)) || _baseHasSteps(e)
                  ? _save
                  : null,
            ),
            CanvasIconButton(
              key: const ValueKey("imageActionImport"),
              icon: Icons.file_open_outlined,
              tooltip: "Import an action",
              onPressed: () => pickImageActionFile(context),
            ),
            if (done != null) ...[
              CanvasIconButton(
                key: const ValueKey("imageActionSend"),
                icon: Icons.send_outlined,
                tooltip: "Send ${done.name} to a chat",
                onPressed: () => sendBytesToChat(context,
                    what: done.name,
                    fileName: safeFileName(done.name, imageActionExtension,
                        fallback: "action"),
                    bytes: () async => packImageAction(done.name, done.data)),
              ),
              CanvasIconButton(
                key: const ValueKey("imageActionExport"),
                icon: Icons.save_alt,
                tooltip: "Save ${done.name} as a file",
                onPressed: () => _export(done),
              ),
              CanvasIconButton(
                key: const ValueKey("imageActionDelete"),
                icon: Icons.delete_outline,
                tooltip: "Delete the action ${done.name}",
                onPressed: () async {
                  await store.remove(done);
                  if (mounted) setState(() => _done = null);
                },
              ),
            ],
            CanvasHint(done != null
                ? "${done.name}: send it, save it as a file, or delete it."
                : "Save keeps the steps you choose from this picture -- "
                    "never the picture -- to do to any other."),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    var e = widget.element;
    var chosen = await showDialog<(String, Set<String>)>(
        context: context,
        builder: (context) => _SaveActionDialog(
            element: e, name: "Action ${store.presets.length + 1}"));
    if (chosen == null || !mounted) return;
    var (name, only) = chosen;
    // The same name again overwrites that action.
    for (var p in store.presets.where((p) => p.name == name).toList()) {
      await store.remove(p);
    }
    var kept = await store.save(name, lookData(e, only: only));
    if (!mounted) return;
    if (kept == null) {
      _say("Could not save the action.");
      return;
    }
    setState(() => _done = kept.id);
    _say("Saved the action $name.");
  }

  Future<void> _export(SavedPreset p) async {
    var bytes = packImageAction(p.name, p.data);
    try {
      var chosen = await FilePicker.platform.saveFile(
          dialogTitle: "Save the action",
          fileName:
              safeFileName(p.name, imageActionExtension, fallback: "action"),
          bytes: bytes);
      if (chosen == null) return;
      // Some platforms only answer with a path.
      await File(chosen).writeAsBytes(bytes, flush: true);
      if (mounted) _say("Saved to $chosen.");
    } catch (e) {
      if (mounted) _say("Could not save it: $e");
    }
  }
}

/// _baseHasSteps is whether [e]'s picture has settings an action keeps:
/// effects, a blend, an opacity.
bool _baseHasSteps(ImageElement e) {
  var base = e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
  return base.effects.isNotEmpty ||
      base.blend != LayerBlend.normal ||
      base.opacity != 1;
}

/// _SaveActionDialog asks for a name and which steps to keep.
class _SaveActionDialog extends StatefulWidget {
  final ImageElement element;
  final String name;
  const _SaveActionDialog({required this.element, required this.name});

  @override
  State<_SaveActionDialog> createState() => _SaveActionDialogState();
}

class _SaveActionDialogState extends State<_SaveActionDialog> {
  late final TextEditingController name =
      TextEditingController(text: widget.name);
  late final List<ImageLayer> steps;
  late final Set<String> chosen;

  @override
  void initState() {
    super.initState();
    var e = widget.element;
    steps = [
      // Top first, as the layers are listed.
      for (var l in e.stack.reversed)
        if (inLook(e, l) || (l.isBase && _baseHasSteps(e))) l
    ];
    chosen = {for (var l in steps) l.id};
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var e = widget.element;
    var ready = name.text.trim().isNotEmpty && chosen.isNotEmpty;
    return AlertDialog(
      title: const Text("Save as an action"),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey("imageActionName"),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Name"),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text("Steps to keep, top first:",
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(shrinkWrap: true, children: [
                for (var l in steps)
                  CheckboxListTile(
                    key: ValueKey("imageActionStep-${l.id}"),
                    dense: true,
                    value: chosen.contains(l.id),
                    title: Text(l.isBase
                        ? "The picture's effects and blend"
                        : stepLabel(e, l)),
                    onChanged: (v) => setState(() =>
                        v == true ? chosen.add(l.id) : chosen.remove(l.id)),
                  ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        FilledButton(
            key: const ValueKey("imageActionSaveConfirm"),
            onPressed: ready
                ? () => Navigator.pop(context, (name.text.trim(), chosen))
                : null,
            child: const Text("Save")),
      ],
    );
  }
}

/// pickImageActionFile asks for an action file and imports it.
Future<void> pickImageActionFile(BuildContext context) async {
  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
        dialogTitle: "Import an action",
        type: FileType.custom,
        allowedExtensions: [
          imageActionExtension.substring(1),
          // A colour table comes in as an action of one step, a Lightroom
          // preset as the adjustments that do what it does.
          "cube",
          "png",
          "xmp",
        ]);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text("Could not choose a file: $e")));
    }
    return;
  }
  var p = picked?.files.firstOrNull?.path;
  if (p == null || !context.mounted) return;
  await importImageActionFile(context, p);
}

/// importImageActionFile reads the action in [file], shows its steps, and
/// keeps it if the person says so.
Future<void> importImageActionFile(BuildContext context, String file) async {
  void say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
  ReceivedImageAction? action;
  var note = "";
  var lower = file.toLowerCase();
  if (lower.endsWith(".xmp")) {
    String text;
    try {
      var f = File(file);
      if (await f.length() > maxPresetBytes) {
        if (context.mounted) say("That is too large to be a preset.");
        return;
      }
      text = await f.readAsString();
    } catch (e) {
      if (context.mounted) say("Could not read it: $e");
      return;
    }
    var (preset, problem) =
        readLightroomPreset(text, path.basenameWithoutExtension(file));
    if (!context.mounted) return;
    if (preset == null) {
      say(problem ?? "That is not a Lightroom preset.");
      return;
    }
    action = ReceivedImageAction(preset.name, preset.data);
    if (preset.left.isNotEmpty) {
      note = " Not carried over, having nothing here that does it: "
          "${preset.left.join(", ")}.";
    }
  } else if (lower.endsWith(".cube") || lower.endsWith(".png")) {
    var (read, problem) = await _tableFile(file);
    if (!context.mounted) return;
    if (read == null) {
      say(problem ?? "That is not a colour table.");
      return;
    }
    action = ReceivedImageAction(read.title, tableAction(read));
  } else {
    Uint8List bytes;
    try {
      var f = File(file);
      if (await f.length() > maxImageActionBytes) {
        if (context.mounted) say("That is too large to be an image action.");
        return;
      }
      bytes = await f.readAsBytes();
    } catch (e) {
      if (context.mounted) say("Could not read it: $e");
      return;
    }
    var (read, problem) = readImageAction(bytes);
    if (!context.mounted) return;
    if (read == null) {
      say(problem ?? "That is not an image action.");
      return;
    }
    action = read;
  }
  var shown = action;
  var keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text("Keep the action ${shown.name}?"),
            content: Text("${shown.steps} step${shown.steps == 1 ? "" : "s"}"
                ": ${lookStepNames(shown.data).join(", ")}. It is settings "
                "only -- no pictures -- and is kept with your actions in a "
                "picture's Actions.$note"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              FilledButton(
                  key: const ValueKey("imageActionImportConfirm"),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Keep it")),
            ],
          ));
  if (keep != true || !context.mounted) return;
  var store = SavedPresetStore.looks;
  await store.load();
  var name = action.name;
  var names = {for (var p in store.presets) p.name};
  for (var n = 2; names.contains(name); n++) {
    name = "${action.name} ($n)";
  }
  await store.save(name, action.data);
  if (context.mounted) say("Kept the action $name.");
}

/// _tableFile reads a colour table file, saying why it could not.
Future<(CubeFile?, String?)> _tableFile(String file) async {
  try {
    return await readColourTableFile(file);
  } catch (e) {
    return (null, "Could not read it: $e");
  }
}

/// tableAction is an action of one step: [read], as a colour table.
Map<String, dynamic> tableAction(CubeFile read) {
  const stand = ImageElement(
      ElementBase(id: "stand-in", width: 1000, height: 1000),
      assetId: "stand-in");
  return lookData(stand.withLayers([
    ImageLayer.base,
    ImageLayer.adjusting(AdjustKind.colourTable).copyWith(
        name: read.title,
        adjust: ImageAdjustment(
            kind: AdjustKind.colourTable,
            cube: read.cube,
            tableName: read.title)),
  ]));
}

/// _paintWearing draws [e] wearing an action, settled: without arrival or
/// loop, which would draw a picture yet to arrive as nothing.
void _paintWearing(
    ui.Canvas canvas, Size size, ImageElement e, CanvasImageSource images) {
  var b = e.bounds;
  if (b.isEmpty) return;
  var k = math.min(size.width / b.width, size.height / b.height);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate(
      (size.width - b.width * k) / 2, (size.height - b.height * k) / 2);
  canvas.scale(k);
  canvas.translate(-b.left, -b.top);
  paintElement(canvas, e.copyWith(animation: const ElementAnimation()), 0,
      images: images);
  canvas.restore();
}
