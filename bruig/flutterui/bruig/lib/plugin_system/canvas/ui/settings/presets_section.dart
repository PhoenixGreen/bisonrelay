import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// presets_section.dart is the row of saved designs at the top of an element's
// settings.
//
// At the top because it is the first decision: start from something, or start
// from nothing. Below the type and the colours it would be a thing to find
// after the work of setting them by hand has already been done.
//
// What a preset makes is an ordinary element. There is no link back to the
// preset and nothing about the element is locked, so what somebody gets is a
// head start rather than a template to fill in -- and changing a preset later
// leaves everything made from it alone, which is what makes it safe to change
// one.

/// presetsSection lists the presets that make [kind], with the buttons that
/// save, rename and delete them.
Widget presetsSection(
  BuildContext context,
  CanvasController controller,
  ElementKind kind, {
  CanvasElement? selected,
}) =>
    _PresetsSection(controller: controller, kind: kind, selected: selected);

class _PresetsSection extends StatefulWidget {
  final CanvasController controller;
  final ElementKind kind;
  final CanvasElement? selected;

  const _PresetsSection({
    required this.controller,
    required this.kind,
    this.selected,
  });

  @override
  State<_PresetsSection> createState() => _PresetsSectionState();
}

class _PresetsSectionState extends State<_PresetsSection> {
  ElementPresetStore get store => ElementPresetStore.instance;

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

  /// _use puts a preset on the canvas, selected, so the next thing somebody
  /// does is edit it.
  void _use(ElementPreset preset) {
    var element = preset.build();
    // Where the canvas would put a new element of that kind, so a preset
    // saved from a big canvas lands on the page of a small one.
    var at = widget.controller.document.size.rect.center;
    var box = element.bounds;
    widget.controller.addElement(element.withBase(
      x: at.dx - box.width / 2,
      y: at.dy - box.height / 2,
    ));
  }

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
    var presets = store.forKind(widget.kind);
    var selected = widget.selected;

    return CanvasExpander(
      label: "Presets",
      remember: "elementPresets.${widget.kind.name}",
      trailing: presets.isEmpty ? null : "${presets.length}",
      children: [
        const CanvasHint(
            "A preset is a whole element saved under a name. Choosing one "
            "puts a copy on the canvas and everything about it can then be "
            "changed — it is a head start, not a template, so changing a "
            "preset later leaves what was made from it alone."),
        if (presets.isEmpty)
          const CanvasHint("Nothing saved yet. Design an element the way you "
              "want it and press Save."),
        for (var preset in presets)
          CanvasControlGroup(label: preset.name, children: [
            CanvasIconButton(
              key: ValueKey("usePreset.${preset.id}"),
              icon: Icons.add,
              tooltip: "Put ${preset.name} on the canvas",
              onPressed: () => _use(preset),
            ),
            if (!preset.builtIn) ...[
              CanvasIconButton(
                icon: Icons.drive_file_rename_outline,
                tooltip: "Rename this preset",
                onPressed: () async {
                  var name = await _ask("Rename preset", initial: preset.name);
                  if (name == null) return;
                  await store.rename(preset, name);
                },
              ),
              CanvasIconButton(
                icon: Icons.delete_outline,
                tooltip: "Delete this preset",
                onPressed: () => store.remove(preset),
              ),
            ],
          ]),
        CanvasControlGroup(label: "Save", hideCaption: true, children: [
          CanvasIconButton(
            key: const ValueKey("savePreset"),
            icon: Icons.bookmark_add_outlined,
            tooltip: selected == null
                ? "Choose an element to save it as a preset"
                : "Save this one as a preset",
            // Nothing selected of this kind means nothing to save, which is
            // the one thing this button cannot do without.
            onPressed: selected == null
                ? null
                : () async {
                    var name =
                        await _ask("Save as a preset", initial: selected.name);
                    if (name == null) return;
                    await store.save(name, selected);
                  },
          ),
        ]),
      ],
    );
  }
}
