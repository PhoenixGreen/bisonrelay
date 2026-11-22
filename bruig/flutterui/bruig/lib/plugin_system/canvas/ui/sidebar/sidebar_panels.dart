import 'package:flutter/material.dart';

import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/cast_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/character_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/files_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/game_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/presets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/settings_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/structure_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/vocal_cues_panel.dart';

// sidebar_panels.dart is every panel the Canvas sidebars can hold
// (SidebarPanel, in model/sidebar_layout.dart): its heading (name, icon,
// help, count) and its body. Whichever sidebar a panel is in, it is this
// one panel. A panel added to SidebarPanel is given both here: the two
// switches have no default, so the compiler asks.

/// canvasSidebarPanel is [which] holding [body], headed as it is for what
/// is open now, with [menu] behind its ⋯.
StackPanel canvasSidebarPanel(
    SidebarPanel which, CanvasController controller, Widget body,
    {List<PanelAction> menu = const []}) {
  var document = controller.document;
  StackPanel panel(String label, IconData icon,
          {String? hint,
          String? trailing,
          bool startsOpen = true,
          VoidCallback? onIcon,
          String? iconTooltip}) =>
      StackPanel(
        // Its name: the stack keeps what it remembers of a panel under it.
        id: which.name,
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
  StackPanel assets(AssetKind asset) => panel(
        which.title,
        assetKindIcon(asset),
        // 3D objects start shut, as a heading until somebody has models.
        startsOpen: asset != AssetKind.model,
        hint: switch (asset) {
          AssetKind.picture ||
          AssetKind.video ||
          AssetKind.vector =>
            "Click one to put it in the middle of the canvas, or drag it "
                "where you want it. Double-click a name to rename it.",
          AssetKind.audio => "Click one for a speaker in the middle of the "
              "canvas, or drag it onto a channel on the timeline to play it "
              "there. Double-click a name to rename it.",
          AssetKind.model => "Click one to put it in the middle of the "
              "canvas, or drag it where you want it: its own animations are "
              "in its slots. .glb files.",
        },
      );
  return switch (which) {
    SidebarPanel.picture => assets(AssetKind.picture),
    SidebarPanel.video => assets(AssetKind.video),
    SidebarPanel.audio => assets(AssetKind.audio),
    SidebarPanel.vector => assets(AssetKind.vector),
    SidebarPanel.model => assets(AssetKind.model),
    SidebarPanel.files => panel(which.title, Icons.folder_outlined,
        hint: "Every canvas kept on this computer, in folders. Click one to "
            "open it."),
    SidebarPanel.presets => panel(which.title, Icons.grid_view_outlined,
        hint: "Everything there is to start from or add: canvases, scenes, "
            "elements, a pitch's views, text styles, looks and brushes. The "
            "chips narrow the list; the search finds one by name."),
    SidebarPanel.add => panel(which.title, Icons.category_outlined,
        hint: "Click to add one in the middle of the canvas, or drag it "
            "where you want it."),
    // A sound document shows its sections here, a document of scenes its
    // scenes: one panel, whichever the canvas is.
    SidebarPanel.scenes => document.kind.isAudio
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
    SidebarPanel.vocalCues =>
      panel(which.title, Icons.record_voice_over_outlined,
          trailing: document.cues.isEmpty ? null : "${document.cues.length}",
          hint: "Named moments a voice-over's lines start on, for elements to "
              "be timed against. A scene's transition is in the Animation "
              "panel: double-click the scene on the timeline.",
          startsOpen: false),
    SidebarPanel.layers => panel(which.title, Icons.layers_outlined,
        // One more than the elements: the background is a layer too.
        trailing: "${document.elements.length + 1}"),
    SidebarPanel.colour =>
      panel(which.title, Icons.palette_outlined, startsOpen: false),
    SidebarPanel.settings => panel(
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
    SidebarPanel.characters => panel(which.title, Icons.person_outline,
        hint: "The characters made in the Character Studio. Click one to "
            "place a copy in the middle of the canvas: change it in the "
            "Studio and every copy follows.",
        startsOpen: false),
    SidebarPanel.cast => panel(which.title, Icons.groups_outlined,
        trailing: document.cast.isEmpty ? null : "${document.cast.length}",
        hint: "Elements kept once for the whole document, a game's hero "
            "above all, with a linked copy in each scene. Each copy has its "
            "own place, size, facing and what it does there, and whether it "
            "is the player there; the rest (its look, its game settings, "
            "its motions) is every copy's. Click one to place a copy.",
        startsOpen: false),
    SidebarPanel.stock => panel(which.title, Icons.travel_explore,
        hint: "Search Pixabay, the Noun Project, Freesound and Jamendo with "
            "keys of your own. A result is only a preview until it is used: "
            "click it onto the canvas, drag it, or add it to the library "
            "with its +. It keeps who made it and its licence.",
        startsOpen: false),
    SidebarPanel.game => panel(which.title, Icons.sports_esports_outlined,
        hint: "How the game plays: its scenes, its counts, what happens as "
            "it starts, and what the picked element does in it."),
  };
}

/// SidebarPanelBodies holds the panels' bodies, built once each and handed
/// to the stacks unchanged: a stack rebuilds on every heading change, and
/// handed the same widget Flutter leaves the panel's own subtree alone.
class SidebarPanelBodies {
  final CanvasController controller;
  final Future<void> Function(String folder, String name) onOpen;
  final void Function(String folder, String name) onPublish;
  final Future<void> Function(String folder, String name) onNew;
  final ValueChanged<CanvasDocument> onChoosePreset;

  SidebarPanelBodies({
    required this.controller,
    required this.onOpen,
    required this.onPublish,
    required this.onNew,
    required this.onChoosePreset,
  });

  final Map<SidebarPanel, Widget> _built = {};

  /// _structure stands in for the scenes while the canvas is a piece of
  /// sound: see canvasSidebarPanel.
  late final Widget _structure = CanvasStructurePanel(controller: controller);

  /// body is [panel]'s contents: built once and handed over unchanged
  /// from then on, but for the files, which are built afresh each time,
  /// told whether they are on show (see CanvasFilesPanel.showing).
  Widget body(SidebarPanel panel, {bool showing = true}) {
    if (panel == SidebarPanel.files) return _make(panel, showing: showing);
    if (panel == SidebarPanel.scenes && controller.document.kind.isAudio) {
      return _structure;
    }
    return _built.putIfAbsent(panel, () => _make(panel));
  }

  // Keyed by kind: panels sharing a row become tabs, and without a key one
  // section's state is handed each tab's kind in turn.
  Widget _assets(AssetKind kind) => AssetSection(
      key: ValueKey("assets-${kind.name}"), controller: controller, kind: kind);

  Widget _make(SidebarPanel panel, {bool showing = true}) => switch (panel) {
        SidebarPanel.files => CanvasFilesPanel(
            key: const ValueKey("panel-files"),
            controller: controller,
            onOpen: onOpen,
            onPublish: onPublish,
            onNew: onNew,
            showing: showing,
          ),
        SidebarPanel.presets =>
          CanvasPresetsPanel(controller: controller, onChoose: onChoosePreset),
        SidebarPanel.add => CanvasElementsPanel(controller: controller),
        SidebarPanel.scenes => CanvasScenesPanel(controller: controller),
        SidebarPanel.vocalCues => CanvasVocalCuesPanel(controller: controller),
        SidebarPanel.layers => CanvasLayersPanel(controller: controller),
        SidebarPanel.colour => ColourPanel(controller: controller),
        SidebarPanel.settings => SettingsPanelBody(controller: controller),
        SidebarPanel.picture => _assets(AssetKind.picture),
        SidebarPanel.video => _assets(AssetKind.video),
        SidebarPanel.audio => _assets(AssetKind.audio),
        SidebarPanel.vector => _assets(AssetKind.vector),
        SidebarPanel.model => _assets(AssetKind.model),
        SidebarPanel.characters => CharacterAssetSection(
            key: const ValueKey("assets-characters"), controller: controller),
        SidebarPanel.cast =>
          CastPanel(key: const ValueKey("panel-cast"), controller: controller),
        SidebarPanel.stock => StockPanel(
            key: const ValueKey("assets-stock"), controller: controller),
        SidebarPanel.game => CanvasGamePanel(controller: controller),
      };
}

/// sidebarListenable is what the panels' headings follow: the canvas (two
/// are headed for the document, one for the selection), and whether the
/// settings are sections or a menu, which their heading's icon shows.
/// Through chrome: no heading changes with a drag's steps or a frame of
/// play, and each panel's body listens for itself.
Listenable sidebarListenable(CanvasController controller) =>
    Listenable.merge([controller.chrome, settingsAsMenu]);
