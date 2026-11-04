import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:flutter/material.dart';

// presets_section.dart is the row of saved designs at the top of an
// element's settings: the first decision, starting from something or from
// nothing. A preset replaces the element being edited (added beside it, it
// would sit exactly on top of the old one) and leaves an ordinary element
// with no link back, so changing a preset later leaves it alone.

/// presetsSection lists the presets that make this kind of element.
Widget presetsSection(
  BuildContext context,
  CanvasController controller,
  CanvasElement element, {
  void Function(CanvasElement made)? onUse,
}) =>
    _PresetsSection(controller: controller, element: element, onUse: onUse);

/// backgroundPresetsSection is the presets row for the canvas's own
/// background: the same designs a background element saves and offers, since
/// a background is a background wherever it is drawn. Saving keeps the
/// pattern; using one puts its pattern on the canvas, leaving the picture,
/// the video and the sound laid over it alone.
Widget backgroundPresetsSection(
        BuildContext context, CanvasController controller, ProceduralSpec spec,
        {required void Function(ProceduralSpec) onUse}) =>
    _PresetsSection(
      controller: controller,
      element: BackgroundElement(
          ElementBase(id: "canvasBackground", name: "Background"),
          spec: spec),
      onUse: (made) {
        if (made is BackgroundElement) onUse(made.spec);
      },
      // Nothing to lose but a pattern, which undo gives back.
      confirmUse: false,
    );

class _PresetsSection extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;

  /// onUse is what using a preset does, for an element that is not in the
  /// document -- the canvas's background. Null replaces the element.
  final void Function(CanvasElement made)? onUse;
  final bool confirmUse;

  const _PresetsSection(
      {required this.controller,
      required this.element,
      this.onUse,
      this.confirmUse = true});

  @override
  State<_PresetsSection> createState() => _PresetsSectionState();
}

class _PresetsSectionState extends State<_PresetsSection> {
  ElementPresetStore get store => ElementPresetStore.instance;

  /// _chosen is the design this element was last started from, for Rename
  /// and Remove to act on.
  String _chosen = "";

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    // Reads the folder once, ever. Until it comes back the built-in presets
    // are shown, which is the right thing to show while waiting.
    store.load();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// _touched is whether this element has been worked on: whether it differs
  /// from what the Add panel would make, its place and id aside (everybody
  /// moves an element first).
  bool get _touched {
    var fresh = newElement(widget.element.kind, widget.controller.document);
    return _shape(widget.element).toString() != _shape(fresh).toString();
  }

  Map<String, dynamic> _shape(CanvasElement e) => {...e.toJson()}
    ..remove("id")
    ..remove("x")
    ..remove("y")
    ..remove("name");

  /// _use puts a preset's design on the element being edited.
  Future<void> _use(ElementPreset preset) async {
    if (widget.confirmUse && _touched && !await _confirm(preset)) return;
    if (widget.onUse case var use?) {
      use(preset.build());
      return;
    }

    // Sized to this page. A design saved on a banner and used on a square
    // canvas arrives at the banner's scale otherwise -- see presetScale --
    // and its place here is the element's own, below.
    var made = scaledElement(preset.build(),
        presetScale(preset.madeOn, widget.controller.document.size.size));
    var here = widget.element;
    // Where the element already is, at the preset's own size: a design is a
    // shape as much as its colours. What it does (clips, keyframes, cue, game
    // part, stage place) is the element's, and stays.
    var placed = made.withId(here.id);
    var hereBase = here.base;
    widget.controller.replaceElement(placed.rebase(placed.base.copyWith(
      name: here.name,
      x: here.x,
      y: here.y,
      opacity: here.opacity,
      visible: here.visible,
      locked: here.locked,
      track: hereBase.track,
      clearTrack: hereBase.track == null,
      motion: hereBase.motion,
      cue: hereBase.cue,
      play: hereBase.play,
      spot: hereBase.spot,
      clearSpot: hereBase.spot == null,
    )));
  }

  Future<bool> _confirm(ElementPreset preset) => askToConfirm(context,
      title: "Use ${preset.name}?",
      message: "This replaces the element you are editing. What you have "
          "changed about it will be gone.",
      confirm: "Use the preset");

  Future<String?> _ask(String title, {String initial = ""}) {
    var text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: "Name"),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(text.text),
              child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var presets = store.forKind(widget.element.kind);
    // Gone if it was thrown away, or if the panel is now showing a different
    // kind of element with designs of its own.
    var chosen = presets.where((p) => p.name == _chosen).firstOrNull;

    // One row, uncaptioned: the save offer already says what it is.
    return CanvasControlGroup(
        label: "Presets",
        hideCaption: true,
        // No rule under a single row.
        rule: false,
        children: [
          CanvasDropdown<String>(
            key: const ValueKey("elementPresets"),
            label: "",
            value: chosen?.name ?? "",
            width: 168,
            enabled: presets.isNotEmpty,
            options: [
              // What the box reads when nothing has been chosen, which depends on
              // whether there is anything to choose.
              ("", presets.isEmpty ? "Save this design" : "Choose a preset"),
              for (var preset in presets) (preset.name, preset.name),
            ],
            onChanged: (name) {
              var picked = presets.where((p) => p.name == name).firstOrNull;
              if (picked == null) {
                setState(() => _chosen = "");
                return;
              }
              setState(() => _chosen = picked.name);
              _use(picked);
            },
          ),
          // Only for a design somebody saved: a built-in one cannot be renamed.
          if (chosen != null && !chosen.builtIn) ...[
            CanvasIconButton(
              key: const ValueKey("elementPresetRename"),
              icon: Icons.drive_file_rename_outline,
              tooltip: "Rename ${chosen.name}",
              onPressed: () async {
                var name = await _ask("Rename preset", initial: chosen.name);
                if (name == null || name.trim().isEmpty) return;
                await store.rename(chosen, name);
                if (mounted) setState(() => _chosen = name);
              },
            ),
            CanvasIconButton(
              key: const ValueKey("elementPresetRemove"),
              icon: Icons.delete_outline,
              tooltip: "Remove ${chosen.name}",
              onPressed: () async {
                if (!await askToConfirm(context,
                    title: "Remove ${chosen.name}?",
                    message:
                        "The saved design is thrown away. Anything already "
                        "made from it is left alone.",
                    confirm: "Remove")) {
                  return;
                }
                await store.remove(chosen);
                if (mounted) setState(() => _chosen = "");
              },
            ),
          ],
          CanvasIconButton(
            key: const ValueKey("elementPresetSave"),
            icon: Icons.bookmark_add_outlined,
            tooltip: "Save this design as a preset",
            onPressed: () async {
              var name =
                  await _ask("Save as a preset", initial: widget.element.name);
              if (name == null || name.trim().isEmpty) return;
              // With the page it was designed on, so it comes in at the scale it was
              // saved at on a canvas of another size.
              await store.save(name, widget.element,
                  madeOn: widget.controller.document.size.size);
              if (mounted) setState(() => _chosen = name);
            },
          ),
        ]);
  }
}
