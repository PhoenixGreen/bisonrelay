import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/character_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/files_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/game_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_library.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/structure_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/vocal_cues_panel.dart';
import 'package:flutter/material.dart';

// sidebar_panels.dart is every panel the Canvas sidebars can hold, by its
// name (see sidebarPanelIds): its heading -- name, icon, help, count -- and
// its body. Whichever sidebar a panel is in, it is this one panel; the
// Design and Assets columns build theirs from here too.

/// canvasSidebarPanel is panel [id] holding [body], headed as it is for
/// what is open now, with [menu] behind its ⋯. Null for a name not known.
StackPanel? canvasSidebarPanel(
    String id, CanvasController controller, Widget body,
    {List<PanelAction> menu = const []}) {
  var document = controller.document;
  StackPanel panel(String label, IconData icon,
          {String? hint,
          String? trailing,
          bool startsOpen = true,
          VoidCallback? onIcon,
          String? iconTooltip}) =>
      StackPanel(
        id: id,
        label: label,
        icon: icon,
        hint: hint,
        trailing: trailing,
        startsOpen: startsOpen,
        onIcon: onIcon,
        iconTooltip: iconTooltip,
        menu: menu,
        body: body,
      );
  var asset = AssetKind.values.where((k) => k.name == id).firstOrNull;
  if (asset != null) {
    return panel(
      asset.label,
      assetKindIcon(asset),
      // 3D objects start shut, as a heading until somebody has models.
      startsOpen: asset != AssetKind.model,
      hint: switch (asset) {
        AssetKind.picture ||
        AssetKind.video ||
        AssetKind.vector =>
          "Click one to put it in the middle of the canvas, or drag it where "
              "you want it. Double-click a name to rename it.",
        AssetKind.audio => "Click one for a speaker in the middle of the "
            "canvas, or drag it onto a channel on the timeline to play it "
            "there. Double-click a name to rename it.",
        AssetKind.model => "Click one to put it in the middle of the canvas, "
            "or drag it where you want it: its own animations are in its "
            "slots. .glb files.",
      },
    );
  }
  return switch (id) {
    "files" => panel("Files", Icons.folder_outlined,
        hint: "Every canvas kept on this computer, in folders. Click one to "
            "open it."),
    "presets" => panel("Presets", Icons.grid_view_outlined,
        hint: "Everything there is to start from or add: canvases, scenes, "
            "elements, a pitch's views, text styles, looks and brushes. The "
            "chips narrow the list; the search finds one by name."),
    "add" => panel("Add", Icons.category_outlined,
        hint: "Click to add one in the middle of the canvas, or drag it "
            "where you want it."),
    // A sound document shows its sections here, a document of scenes its
    // scenes: one panel, whichever the canvas is.
    "scenes" => document.kind.isAudio
        ? panel("Structure", Icons.view_week_outlined,
            trailing: document.audio.sections.isEmpty
                ? null
                : "${document.audio.sections.length}",
            hint: "The sections this piece is laid out in, in order, each so "
                "many bars long: an intro, a verse, a chorus. A sound plays "
                "on from one section into the next.")
        : panel(document.kind.manyCap,
            document.isPages ? Icons.menu_book_outlined : Icons.movie_outlined,
            trailing: document.hasScenes
                ? "${document.at + 1}/${document.allScenes.length}"
                : null,
            hint: document.isPages
                ? "The leaves of this document, in order. Drag one up or "
                    "down to move it. The first and last can be marked as "
                    "covers, which takes them out of the numbering."
                : "The canvases this document plays through, in order. Drag "
                    "one up or down to change when it plays.",
            // Shut to begin with: most documents are one canvas.
            startsOpen: false),
    "vocalCues" => panel("Vocal cues", Icons.record_voice_over_outlined,
        trailing: document.cues.isEmpty ? null : "${document.cues.length}",
        hint: "Named moments a voice-over's lines start on, for elements to "
            "be timed against. A scene's transition is in the Animation "
            "panel: double-click the scene on the timeline.",
        startsOpen: false),
    "layers" => panel("Layers", Icons.layers_outlined,
        // One more than the elements: the background is a layer too.
        trailing: "${document.elements.length + 1}"),
    "colour" => panel("Colour", Icons.palette_outlined, startsOpen: false),
    "settings" => panel(
        // Named for what is selected ("Image settings").
        elementSettingsTitle(controller),
        // The icon switches the layout: sections down the panel, or a menu
        // of them across the top with one shown at a time.
        settingsAsMenu.value ? Icons.view_week_outlined : Icons.tune,
        onIcon: toggleSettingsLayout,
        iconTooltip: settingsAsMenu.value
            ? "Show the settings as sections"
            : "Show the settings as a menu",
        hint: elementSettingsHint),
    "characters" => panel("Characters", Icons.person_outline,
        hint: "The characters made in the Character Studio. Click one to "
            "place a copy in the middle of the canvas: change it in the "
            "Studio and every copy follows.",
        startsOpen: false),
    "stock" => panel("Stock", Icons.travel_explore,
        hint: "Search Pixabay, the Noun Project, Freesound and Jamendo with "
            "keys of your own. A result is only a preview until it is used: "
            "click it onto the canvas, drag it, or add it to the library "
            "with its +. It keeps who made it and its licence.",
        startsOpen: false),
    "game" => panel("Game", Icons.sports_esports_outlined,
        hint: "How the game plays: its scenes, its counts, what happens as "
            "it starts, and what the picked element does in it."),
    _ => null,
  };
}

/// sidebarPanelLabel is panel [id]'s name, as a menu lists it.
String sidebarPanelLabel(String id, CanvasController controller) =>
    canvasSidebarPanel(id, controller, const SizedBox())?.label ?? id;

/// SidebarPanelBodies holds the panels' bodies, built once each and handed
/// to the stacks unchanged: a stack rebuilds on every heading change, and
/// handed the same widget Flutter leaves the panel's own subtree alone.
class SidebarPanelBodies {
  final CanvasController controller;
  final Future<void> Function(String folder, String name) onOpen;
  final void Function(String folder, String name) onPublish;
  final Future<void> Function(String folder, String name) onNew;
  final void Function(CanvasPreset? preset, CanvasDocument document)
      onChoosePreset;

  SidebarPanelBodies({
    required this.controller,
    required this.onOpen,
    required this.onPublish,
    required this.onNew,
    required this.onChoosePreset,
  });

  final Map<String, Widget> _built = {};

  /// body is panel [id]'s contents. The files are built afresh each time,
  /// told whether they are on show (see CanvasFilesPanel.showing).
  Widget body(String id, {bool showing = true}) {
    if (id == "files") {
      return CanvasFilesPanel(
        key: const ValueKey("panel-files"),
        controller: controller,
        onOpen: onOpen,
        onPublish: onPublish,
        onNew: onNew,
        showing: showing,
      );
    }
    if (id == "scenes") {
      // Which of the two follows the canvas: see canvasSidebarPanel.
      return controller.document.kind.isAudio
          ? _built.putIfAbsent(
              "structure", () => CanvasStructurePanel(controller: controller))
          : _built.putIfAbsent(
              "scenes", () => CanvasScenesPanel(controller: controller));
    }
    return _built.putIfAbsent(id, () => _make(id));
  }

  Widget _make(String id) {
    var asset = AssetKind.values.where((k) => k.name == id).firstOrNull;
    if (asset != null) {
      // Keyed by kind: panels sharing a row become tabs, and without a key
      // one section's state is handed each tab's kind in turn.
      return AssetSection(
          key: ValueKey("assets-${asset.name}"),
          controller: controller,
          kind: asset);
    }
    return switch (id) {
      "presets" =>
        CanvasPresetsLibrary(controller: controller, onChoose: onChoosePreset),
      "add" => CanvasElementsPanel(controller: controller),
      "vocalCues" => CanvasVocalCuesPanel(controller: controller),
      "layers" => CanvasLayersPanel(controller: controller),
      "colour" => ColourPanel(controller: controller),
      "settings" => SettingsPanelBody(controller: controller),
      "characters" => CharacterAssetSection(
          key: const ValueKey("assets-characters"), controller: controller),
      "stock" =>
        StockPanel(key: const ValueKey("assets-stock"), controller: controller),
      "game" => CanvasGamePanel(controller: controller),
      _ => const SizedBox.shrink(),
    };
  }
}

/// sidebarListenable is what a sidebar's headings follow: the canvas, the
/// settings' layout, and the library.
Listenable sidebarListenable(CanvasController controller) =>
    Listenable.merge([controller, settingsAsMenu, CanvasLibrary.changes]);
