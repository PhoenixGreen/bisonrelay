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

// preset_panels.dart is the saved scenes and the saved elements, as two lists
// in the Presets sidebar. Using one adds it: an element to the canvas in view,
// a scene after the one in view (see CanvasController.addScenes).

/// ScenePresetsPanel is the scenes somebody has saved.
class ScenePresetsPanel extends StatefulWidget {
  final CanvasController controller;

  /// query keeps only the presets whose names have it in them.
  final String query;

  /// embedded is the list inside another (see CanvasPresetsLibrary): laid
  /// out at its own height, not scrolling, and silent when empty.
  final bool embedded;

  const ScenePresetsPanel(
      {required this.controller,
      this.query = "",
      this.embedded = false,
      super.key});

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

  /// _page is the canvas a preset is arriving on.
  Size _page() => widget.controller.document.size.size;

  @override
  Widget build(BuildContext context) {
    var presets = [
      for (var p in store.presets)
        if (presetMatches(p.name, widget.query)) p
    ];
    return presetList(
      embedded: widget.embedded,
      children: [
        if (presets.isEmpty && !widget.embedded)
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
            // Sized to the page it is arriving on, so a scene made on a banner
            // does not hang off a square canvas.
            onUse: () =>
                widget.controller.addScenes(preset.buildScenes(on: _page())),
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

  /// query keeps only the presets whose names have it in them.
  final String query;

  /// embedded is the list inside another: see ScenePresetsPanel.embedded.
  final bool embedded;

  /// kinds keeps only presets of these kinds, where given.
  final Set<ElementKind>? kinds;

  const ElementPresetsPanel(
      {required this.controller,
      this.query = "",
      this.embedded = false,
      this.kinds,
      super.key});

  @override
  State<ElementPresetsPanel> createState() => _ElementPresetsPanelState();
}

class _ElementPresetsPanelState extends State<ElementPresetsPanel> {
  ElementPresetStore get store => ElementPresetStore.instance;

  /// _kind is the filter: null for all of them. It offers only the kinds
  /// there are presets for.
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

  /// _page is the canvas a preset is arriving on.
  Size _page() => widget.controller.document.size.size;

  @override
  Widget build(BuildContext context) {
    var all = [
      for (var p in store.presets)
        if ((widget.kinds == null || widget.kinds!.contains(p.kind)) &&
            presetMatches(p.name, widget.query))
          p
    ];
    var kinds = <ElementKind>{for (var p in all) p.kind}.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    // A filter on a kind that has just lost its last preset would show an
    // empty list with no way to tell why.
    var kind = kinds.contains(_kind) ? _kind : null;
    var showing = [
      for (var p in all)
        if (kind == null || p.kind == kind) p
    ];

    return presetList(
      embedded: widget.embedded,
      children: [
        if (kinds.length > 1 && widget.kinds == null)
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
        if (showing.isEmpty && !widget.embedded)
          const CanvasHint(
              "Nothing saved yet. Any element can be saved from the Presets "
              "line at the top of its settings, and arrives here as a copy."),
        for (var preset in showing)
          PresetRow(
            key: ValueKey("elementPreset:${preset.id}"),
            name: preset.name,
            icon: iconForKind(preset.kind),
            says: preset.kind.label,
            // Sized to the page and centred on it, so a headline made for a
            // 1920-wide banner does not arrive 1920 wide. See
            // ElementPreset.buildFor.
            onUse: () => widget.controller.addElement(preset.buildFor(_page())),
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

  /// onOpen starts a new document from a preset; what to do about unsaved
  /// work is the screen's decision.
  final void Function(CanvasDocument document) onOpen;

  /// query keeps only the presets whose names have it in them.
  final String query;

  const SavedCanvasPresets(
      {required this.controller,
      required this.onOpen,
      this.query = "",
      super.key});

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

  /// _page is the canvas a preset is arriving on.
  Size _page() => widget.controller.document.size.size;

  @override
  Widget build(BuildContext context) {
    var presets = [
      for (var p in store.presets)
        if (presetMatches(p.name, widget.query)) p
    ];
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
          // Tapped, it starts a document of its own; its menu adds its scenes
          // to the open one instead.
          onUse: () {
            var document = preset.buildDocument();
            if (document != null) widget.onOpen(document);
          },
          extra: {
            "Add its scenes to this canvas": () =>
                widget.controller.addScenes(preset.buildScenes(on: _page())),
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

/// presetMatches is whether a preset called [name] is one [query] asks for:
/// every word of it somewhere in the name, whatever the case.
bool presetMatches(String name, String query) {
  var words = query.toLowerCase().split(RegExp(r"\s+"))
    ..removeWhere((w) => w.isEmpty);
  var lower = name.toLowerCase();
  return words.every(lower.contains);
}

/// presetList is a list of presets: scrolling on its own, or, [embedded] in
/// another list, as tall as it is.
Widget presetList({required bool embedded, required List<Widget> children}) =>
    embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
        : ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            children: children);

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
