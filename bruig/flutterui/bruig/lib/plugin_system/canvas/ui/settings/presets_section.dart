import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/material.dart';

// presets_section.dart is the row of saved designs at the top of an element's
// settings.
//
// At the top because it is the first decision: start from something, or start
// from nothing. Below the type and the colours it would be a thing to find
// after the work of setting them by hand has already been done.
//
// A preset *replaces* the element being edited rather than adding a second
// one beside it. Adding put the new design exactly on top of the old one --
// two elements in the same place, one of them invisible and still there --
// which is a mess to clear up and never what somebody choosing a design
// meant. What it leaves behind is an ordinary element: nothing is locked and
// there is no link back to the preset, so it is a head start rather than a
// template, and changing a preset later leaves what was made from it alone.

/// presetsSection lists the presets that make this kind of element.
Widget presetsSection(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) =>
    _PresetsSection(controller: controller, element: element);

class _PresetsSection extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;

  const _PresetsSection({required this.controller, required this.element});

  @override
  State<_PresetsSection> createState() => _PresetsSectionState();
}

class _PresetsSectionState extends State<_PresetsSection> {
  ElementPresetStore get store => ElementPresetStore.instance;

  /// _chosen is the design this element was last started from.
  ///
  /// Held so that Rename and Remove have something to act on. They were one
  /// button opening a list to pick from, which is a dialog to do a thing the
  /// row already has a list for -- and it only appeared once something had
  /// been saved, so on a panel showing the built-in designs there was no way
  /// to reach it at all. Two buttons beside the list, acting on whatever is
  /// in it, is one fewer list.
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

  /// _touched is whether this element has been worked on.
  ///
  /// Measured against what the Add panel would have made: an element that is
  /// still exactly what dropping one gives you has nothing in it to lose, and
  /// asking "are you sure" about that is asking about nothing. Its place and
  /// its id are left out of the comparison -- everybody moves an element
  /// before doing anything else with it, and being moved is not work anybody
  /// minds losing.
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
    if (_touched && !await _confirm(preset)) return;

    // Sized to this page. A design saved on a banner and used on a square
    // canvas arrives at the banner's scale otherwise -- see presetScale --
    // and its place here is the element's own, below.
    var made = scaledElement(preset.build(),
        presetScale(preset.madeOn, widget.controller.document.size.size));
    var here = widget.element;
    // Where the element already is, and the preset's own size: a design is a
    // shape as much as it is a set of colours, and one dropped into the box
    // of whatever was there before is not the design that was saved.
    widget.controller.replaceElement(
      made
          .withBase(
            name: here.name,
            x: here.x,
            y: here.y,
            opacity: here.opacity,
            visible: here.visible,
            locked: here.locked,
          )
          .withId(here.id),
    );
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

    // One row, uncaptioned. "PRESETS" over a list already offering to save
    // this design was the word twice, at the top of every element's settings,
    // above the settings somebody actually came for.
    return CanvasControlGroup(
        label: "Presets",
        hideCaption: true,
        // No rule under it either. A line between one row and the first
        // section of the element's own settings divides nothing: what is
        // above it is a single row, and a rule wants two groups to separate.
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
          // Only for a design somebody saved. A built-in one is not theirs to
          // rename, and a button that is there and refuses is worse than no
          // button.
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
              // With the page it was designed on, so that dropping it on a
              // canvas of another size brings it in at the scale it was
              // saved at rather than the size it happened to be.
              await store.save(name, widget.element,
                  madeOn: widget.controller.document.size.size);
              if (mounted) setState(() => _chosen = name);
            },
          ),
        ]);
  }
}
