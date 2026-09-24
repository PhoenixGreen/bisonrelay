import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_row.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// preset_panels.dart is the saved scenes and the saved elements, as two
// lists in the Presets sidebar.
//
// What a preset does when it is used is the one thing that differs between
// the three lists, and it follows from what the preset is: an element is
// added to the canvas being looked at, a scene is added to the document after
// the one being looked at, and a canvas either starts a new document or gives
// its scenes to this one. See CanvasController.addScenes.

/// ScenePresetsPanel is the scenes somebody has saved.
class ScenePresetsPanel extends StatefulWidget {
  final CanvasController controller;
  const ScenePresetsPanel({required this.controller, super.key});

  @override
  State<ScenePresetsPanel> createState() => _ScenePresetsPanelState();
}

class _ScenePresetsPanelState extends State<ScenePresetsPanel> {
  SavedPresetStore get store => SavedPresetStore.scenes;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
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

  @override
  Widget build(BuildContext context) {
    var presets = store.presets;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      children: [
        if (presets.isEmpty)
          const CanvasHint(
              "Nothing saved yet. A scene is saved from its own menu in "
              "Design › Scenes, and arrives here as a copy: editing the "
              "scene afterwards leaves the preset as it was."),
        for (var preset in presets)
          PresetRow(
            key: ValueKey("scenePreset:${preset.id}"),
            name: preset.name,
            icon: Icons.movie_outlined,
            says: _says(preset),
            onUse: () => widget.controller.addScenes(preset.buildScenes()),
            onRename: (name) => store.rename(preset, name),
            onDelete: () => store.remove(preset),
          ),
      ],
    );
  }

  /// _says is the line under the name: how much is on the scene.
  String _says(SavedPreset preset) {
    var count = (preset.data["elements"] as List?)?.length ?? 0;
    return count == 1 ? "1 element" : "$count elements";
  }
}

/// ElementPresetsPanel is the elements somebody has saved, and the ones that
/// ship with the app.
class ElementPresetsPanel extends StatefulWidget {
  final CanvasController controller;
  const ElementPresetsPanel({required this.controller, super.key});

  @override
  State<ElementPresetsPanel> createState() => _ElementPresetsPanelState();
}

class _ElementPresetsPanelState extends State<ElementPresetsPanel> {
  ElementPresetStore get store => ElementPresetStore.instance;

  /// _kind is the filter: null for all of them.
  ///
  /// A list of every preset of every kind is a list nobody can find a chart
  /// in. The filter offers only the kinds there are presets for, so it is
  /// never a menu of mostly empty answers.
  ElementKind? _kind;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
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

  @override
  Widget build(BuildContext context) {
    var all = store.presets;
    var kinds = <ElementKind>{for (var p in all) p.kind}.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    // A filter pointed at a kind that has just lost its last preset would
    // show an empty list with no way to tell why.
    var kind = kinds.contains(_kind) ? _kind : null;
    var showing = [
      for (var p in all)
        if (kind == null || p.kind == kind) p
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      children: [
        if (kinds.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CanvasDropdown<String>(
              key: const ValueKey("elementPresetKind"),
              label: "Show",
              value: kind?.name ?? "",
              width: 140,
              options: [
                ("", "All"),
                for (var k in kinds) (k.name, k.label),
              ],
              onChanged: (v) => setState(() => _kind = v.isEmpty
                  ? null
                  : ElementKind.values.firstWhere((k) => k.name == v)),
            ),
          ),
        if (showing.isEmpty)
          const CanvasHint(
              "Nothing saved yet. Any element can be saved from the Presets "
              "line at the top of its settings, and arrives here as a copy."),
        for (var preset in showing)
          PresetRow(
            key: ValueKey("elementPreset:${preset.id}"),
            name: preset.name,
            icon: iconForKind(preset.kind),
            says: preset.kind.label,
            onUse: () => widget.controller.addElement(preset.build()),
            // The ones that ship with the app are not the reader's to lose.
            onRename:
                preset.builtIn ? null : (name) => store.rename(preset, name),
            onDelete: preset.builtIn ? null : () => store.remove(preset),
          ),
      ],
    );
  }
}

/// SavedCanvasPresets is the canvases somebody has saved, under the ones that
/// ship with the app.
class SavedCanvasPresets extends StatefulWidget {
  final CanvasController controller;

  /// onOpen starts a new document from a preset. What to do about unsaved
  /// work is the screen's decision, so it is handed up rather than taken
  /// here.
  final void Function(CanvasDocument document) onOpen;

  const SavedCanvasPresets(
      {required this.controller, required this.onOpen, super.key});

  @override
  State<SavedCanvasPresets> createState() => _SavedCanvasPresetsState();
}

class _SavedCanvasPresetsState extends State<SavedCanvasPresets> {
  SavedPresetStore get store => SavedPresetStore.canvases;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
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

  @override
  Widget build(BuildContext context) {
    var presets = store.presets;
    if (presets.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 6),
        child: CanvasSubHeading("Saved"),
      ),
      for (var preset in presets)
        PresetRow(
          key: ValueKey("canvasPreset:${preset.id}"),
          name: preset.name,
          icon: Icons.dashboard_outlined,
          says: _says(preset),
          // Tapped, it starts a document of its own -- which is what a whole
          // canvas is. Its scenes can be added to the document already open
          // from the menu instead.
          onUse: () {
            var document = preset.buildDocument();
            if (document != null) widget.onOpen(document);
          },
          extra: {
            "Add its scenes to this canvas": () =>
                widget.controller.addScenes(preset.buildScenes()),
          },
          onRename: (name) => store.rename(preset, name),
          onDelete: () => store.remove(preset),
        ),
    ]);
  }

  String _says(SavedPreset preset) {
    var scenes = (preset.data["scenes"] as List?)?.length ?? 1;
    return scenes == 1 ? "1 scene" : "$scenes scenes";
  }
}

/// CanvasSubHeading is a quieter heading inside a panel, for the line between
/// what ships with the app and what has been saved.
class CanvasSubHeading extends StatelessWidget {
  final String text;
  const CanvasSubHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: ThemeNotifier.of(context)
              .colors
              .onSurfaceVariant
              .withValues(alpha: 0.75),
        ),
      );
}
