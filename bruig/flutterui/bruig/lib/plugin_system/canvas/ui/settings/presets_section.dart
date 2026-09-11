import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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

    var made = preset.build();
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

    return CanvasExpander(
      label: "Presets",
      remember: "elementPresets.${widget.element.kind.name}",
      trailing: presets.isEmpty ? null : "${presets.length}",
      children: [
        // Saving first: it is the one thing here that is about the element in
        // front of you rather than about the list. A button that says what it
        // does rather than an icon under a caption -- a caption reading "This
        // one" over a bookmark icon was two attempts at the same sentence and
        // neither of them said it.
        _SaveButton(
          onPressed: () async {
            var name =
                await _ask("Save as a preset", initial: widget.element.name);
            if (name == null) return;
            await store.save(name, widget.element);
          },
        ),
        // A line under the button, and room either side of it. What is above
        // it is about the element in front of you and what is below it is a
        // list of other designs -- two different things in one short section,
        // and without a break between them the first preset read as another
        // button belonging to the first one.
        _Rule(),
        // A line of plain text rather than a hint: a section with three
        // buttons in it does not need explaining, and the one thing worth
        // saying is what an empty list means.
        if (presets.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              "Nothing saved yet.",
              style: TextStyle(
                  fontSize: 11,
                  color: ThemeNotifier.of(context)
                      .colors
                      .onSurfaceVariant
                      .withValues(alpha: 0.7)),
            ),
          ),
        for (var preset in presets)
          _PresetRow(
            preset: preset,
            onUse: () => _use(preset),
            onRename: preset.builtIn
                ? null
                : () async {
                    var name =
                        await _ask("Rename preset", initial: preset.name);
                    if (name == null) return;
                    await store.rename(preset, name);
                  },
            onDelete: preset.builtIn ? null : () => store.remove(preset),
          ),
      ],
    );
  }
}

/// _PresetRow is one preset: its name, which is the button, and what can be
/// done to it.
///
/// The name is the target rather than a plus beside it. A list of designs is
/// a list of things to choose, and a row that is only a label with a button
/// on the end reads as a setting rather than as a choice.
class _PresetRow extends StatelessWidget {
  final ElementPreset preset;
  final VoidCallback onUse;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _PresetRow({
    required this.preset,
    required this.onUse,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: InkWell(
            key: ValueKey("usePreset.${preset.id}"),
            borderRadius: BorderRadius.circular(4),
            onTap: onUse,
            child: Container(
              height: controlHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.colors.outlineVariant),
              ),
              child: Text(
                preset.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
        if (onRename != null || onDelete != null) const SizedBox(width: 4),
        if (onRename != null)
          _RowIcon(
            icon: Icons.drive_file_rename_outline,
            tooltip: "Rename ${preset.name}",
            onPressed: onRename!,
          ),
        if (onDelete != null)
          _RowIcon(
            icon: Icons.delete_outline,
            tooltip: "Delete ${preset.name}",
            onPressed: onDelete!,
          ),
      ]),
    );
  }
}

/// _Rule is the line between the button that saves and the list of designs.
class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 1,
          color: ThemeNotifier.of(context)
              .colors
              .outlineVariant
              .withValues(alpha: 0.6),
        ),
      );
}

/// _SaveButton is the labelled button that keeps this element's design.
///
/// Built like the panel's own switches rather than like its icon buttons: it
/// is the thing somebody comes to this section to press when they are not
/// choosing a design, and a 24-pixel square with a bookmark on it is not
/// something anybody finds.
class _SaveButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SaveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: const ValueKey("savePreset"),
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          height: controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bookmark_add_outlined,
                size: 14, color: theme.colors.onSurfaceVariant),
            const SizedBox(width: 5),
            Text("Save this design",
                style: TextStyle(
                    fontSize: 11, color: theme.colors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// _RowIcon is a small square button that lines up with a row rather than
/// with a captioned control.
///
/// The panel's own icon button leaves room above itself for the caption its
/// neighbours have, which is right in a row of controls and wrong beside a
/// list item -- there it sat half a caption lower than the thing it belongs
/// to.
class _RowIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RowIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Container(
            width: controlHeight,
            height: controlHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: Icon(icon, size: 15, color: theme.colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
