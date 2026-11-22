import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/preset_row.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// preset_lists.dart is the lists of saved presets inside the Presets panel
// (presets_panel.dart): one widget for any store of saved presets
// (StorePresetList), and what the scenes, the canvases and the elements
// each make of it. Each is as tall as its rows; the panel scrolls them all.

/// StorePresetList is a store's presets as rows, kept up as the store
/// changes: each used, renamed and deleted from its row.
class StorePresetList extends StatefulWidget {
  final SavedPresetStore store;

  /// query keeps only the presets whose names have it in them.
  final String query;

  final IconData icon;

  /// empty is what is said where nothing is saved and nothing is searched
  /// for: how one comes to be saved. Left out, nothing is said.
  final String? empty;

  /// heading is drawn over the rows, where there are any.
  final Widget? heading;

  /// rowKey names the rows' keys: a row is "rowKey:the preset's id".
  final String rowKey;

  /// says is the line under a preset's name, where there is one.
  final String Function(SavedPreset preset)? says;

  /// onUse is a press on a preset's row.
  final void Function(BuildContext context, SavedPreset preset) onUse;

  /// more is more entries for a preset's menu, by label.
  final Map<String, VoidCallback> Function(SavedPreset preset)? more;

  const StorePresetList(
      {required this.store,
      required this.query,
      required this.icon,
      required this.onUse,
      this.rowKey = "savedPreset",
      this.empty,
      this.heading,
      this.says,
      this.more,
      super.key});

  @override
  State<StorePresetList> createState() => _StorePresetListState();
}

class _StorePresetListState extends State<StorePresetList> {
  @override
  void initState() {
    super.initState();
    widget.store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          var shown = [
            for (var p in widget.store.presets)
              if (presetMatches(p.name, widget.query)) p
          ];
          if (shown.isEmpty) {
            var empty = widget.empty;
            return empty != null && widget.query.isEmpty
                ? CanvasHint(empty)
                : const SizedBox.shrink();
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.heading case var heading?) heading,
                for (var p in shown)
                  PresetRow(
                    key: ValueKey("${widget.rowKey}:${p.id}"),
                    name: p.name,
                    icon: widget.icon,
                    says: widget.says?.call(p),
                    onUse: () => widget.onUse(context, p),
                    extra: widget.more?.call(p) ?? const {},
                    onRename: (name) => widget.store.rename(p, name),
                    onDelete: () => widget.store.remove(p),
                  ),
              ]);
        },
      );
}

/// _count is "1 thing" or "n things".
String _count(int n, String thing) => n == 1 ? "1 $thing" : "$n ${thing}s";

/// ScenePresetList is the scenes somebody has saved: used, one is added
/// after the scene in view (see CanvasController.addScenes).
class ScenePresetList extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const ScenePresetList({required this.controller, this.query = "", super.key});

  @override
  Widget build(BuildContext context) => StorePresetList(
        store: SavedPresetStore.scenes,
        query: query,
        icon: Icons.movie_outlined,
        rowKey: "scenePreset",
        empty: "Nothing saved yet. A scene is saved from its own menu in "
            "the Scenes panel, and arrives here as a copy: editing the "
            "scene afterwards leaves the preset as it was.",
        says: (preset) => _count(preset.elementCount, "element"),
        // Sized to the page it is arriving on, so a scene made on a banner
        // does not hang off a square canvas.
        onUse: (context, preset) => controller
            .addScenes(preset.buildScenes(on: controller.document.size.size)),
      );
}

/// SavedCanvasList is the canvases saved, under those that ship: used, one
/// starts a new document; its menu adds its scenes to this one instead.
class SavedCanvasList extends StatelessWidget {
  final CanvasController controller;

  /// onOpen starts a new document from a preset; unsaved work is the
  /// screen's.
  final ValueChanged<CanvasDocument> onOpen;
  final String query;

  const SavedCanvasList(
      {required this.controller,
      required this.onOpen,
      this.query = "",
      super.key});

  @override
  Widget build(BuildContext context) => StorePresetList(
        store: SavedPresetStore.canvases,
        query: query,
        icon: Icons.dashboard_outlined,
        rowKey: "canvasPreset",
        heading: const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 6),
          child: CanvasSubHeading("Saved"),
        ),
        says: (preset) => _count(preset.sceneCount, "scene"),
        onUse: (context, preset) {
          if (preset.buildDocument() case var document?) onOpen(document);
        },
        more: (preset) => {
          "Add its scenes to this canvas": () => controller
              .addScenes(preset.buildScenes(on: controller.document.size.size)),
        },
      );
}

/// ElementPresetList is the elements saved, and those that ship with the
/// app: used, one is added to the canvas in view.
class ElementPresetList extends StatefulWidget {
  final CanvasController controller;

  /// query keeps only the presets whose names have it in them.
  final String query;

  /// kinds keeps only presets of these kinds, where given.
  final Set<ElementKind>? kinds;

  const ElementPresetList(
      {required this.controller, this.query = "", this.kinds, super.key});

  @override
  State<ElementPresetList> createState() => _ElementPresetListState();
}

class _ElementPresetListState extends State<ElementPresetList> {
  ElementPresetStore get store => ElementPresetStore.instance;

  /// _kind is the filter, null for all; it offers only kinds with presets.
  ElementKind? _kind;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store, builder: (context, _) => _list(context));

  Widget _list(BuildContext context) {
    var all = [
      for (var p in store.presets)
        if ((widget.kinds == null || widget.kinds!.contains(p.kind)) &&
            presetMatches(p.name, widget.query))
          p
    ];
    var kinds = <ElementKind>{for (var p in all) p.kind}.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    // A filter on a kind just emptied would show a list with no reason why.
    var kind = kinds.contains(_kind) ? _kind : null;
    var showing = [
      for (var p in all)
        if (kind == null || p.kind == kind) p
    ];
    // The canvas a preset is arriving on.
    var page = widget.controller.document.size.size;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            onChanged: (v) => setState(
                () => _kind = v.isEmpty ? null : ElementKind.fromName(v)),
          ),
        ),
      for (var preset in showing)
        PresetRow(
          key: ValueKey("elementPreset:${preset.id}"),
          name: preset.name,
          icon: iconForKind(preset.kind),
          says: preset.kind.label,
          // Sized to the page and centred, so a headline made for a
          // 1920-wide banner does not arrive 1920 wide (buildFor).
          onUse: () => widget.controller.addElement(preset.buildFor(page)),
          // The ones that ship with the app are not the reader's to lose.
          onRename:
              preset.builtIn ? null : (name) => store.rename(preset, name),
          onDelete: preset.builtIn ? null : () => store.remove(preset),
        ),
    ]);
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

/// CanvasSubHeading is a quieter heading inside a panel, between what ships
/// with the app and what has been saved.
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
