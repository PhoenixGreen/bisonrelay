import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/files_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// canvas_screen.dart is the Canvas section: a sidebar, the canvas, a settings
// band above it and a timeline below.
//
// It exists only while the Canvas feature is turned on -- see canvas_nav.dart,
// which puts it in and takes it out of the navigation.
//
// The layout is the one the writing composer uses next door, with the two
// additions a canvas needs: the settings band across the top, and the timeline
// across the bottom. Both belong to the canvas rather than to the sidebar,
// which is why they are inside the content area and stop at its edges.

/// CanvasScreenTitle is the page heading, which follows the menu: renaming the
/// destination in Settings > Appearance > Menu renames the heading too.
class CanvasScreenTitle extends StatelessWidget {
  const CanvasScreenTitle({super.key});

  @override
  Widget build(BuildContext context) => Consumer<MainMenuModel>(
      builder: (context, menu, child) =>
          Txt.L(menu.headerLabel(CanvasScreen.routeName) ?? "Canvas"));
}

class CanvasScreen extends StatefulWidget {
  static const routeName = '/canvas';

  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  /// _controller holds the editing session. Created here and disposed with the
  /// page, so leaving Canvas and coming back is a fresh session -- which is
  /// why the last-opened canvas is remembered and reopened below.
  late final CanvasController _controller = CanvasController(emptyCanvas());

  final GlobalKey<CanvasStageState> _stageKey = GlobalKey<CanvasStageState>();

  CanvasPanel _panel = CanvasPanel.files;

  /// _selectionRevision identifies what is selected, for the collapsed
  /// sidebar's benefit. See sidebarRevision below.
  ///
  /// A string rather than the set itself, because the controller mutates and
  /// replaces that set and a stale reference would compare equal to a new one
  /// holding different ids.
  String _selectionRevision = "";

  /// _sidebarVisible is whether the sidebar is showing.
  ///
  /// Not persisted, like the Writing page's. Hiding it is "give me the width
  /// for a minute" rather than a decision about the shape of the window, and a
  /// canvas page that opened with no sidebar would look broken to somebody who
  /// had hidden it once a fortnight ago.
  bool _sidebarVisible = true;

  /// _canvasSettingsOpen is whether the canvas settings panel is out.
  ///
  /// Closed to begin with -- the ratio and the export width are set once at the
  /// start of a document and then almost never touched. Held here rather than
  /// in the band because the panel is floated over the canvas by this screen;
  /// as a second row of the band it pushed the canvas down every time it was
  /// opened.
  bool _canvasSettingsOpen = false;

  /// _keyframesOpen is whether the pose bar is out.
  ///
  /// Held here rather than in the timeline for the same reason the canvas
  /// settings are: the bar floats over the canvas area, and a strip that grew
  /// to hold it took height from the canvas and re-fitted it -- so opening a
  /// panel moved the design.
  bool _keyframesOpen = false;

  @override
  void initState() {
    super.initState();
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    var at = prefs.panel;
    _panel = at >= 0 && at < CanvasPanel.values.length
        ? CanvasPanel.values[at]
        : CanvasPanel.files;
    _reopenLast(prefs);
    _controller.addListener(_onSelectionChanged);
  }

  /// _reopenLast puts back whatever was open when the page was last left.
  ///
  /// Failing quietly is right here. The file may have been deleted, renamed or
  /// moved since; an empty canvas is a perfectly good place to start, and an
  /// error about a document the reader has not asked for yet would be noise.
  Future<void> _reopenLast(CanvasPreferences prefs) async {
    if (prefs.lastName.isEmpty) return;
    var document =
        await CanvasStorage.load(prefs.lastFolder, prefs.lastName);
    if (!mounted || document == null) return;
    _controller.load(document,
        folder: prefs.lastFolder, name: prefs.lastName);
  }

  /// _onSelectionChanged redraws the screen only when the *selection* moves.
  ///
  /// The controller notifies on every keystroke of every edit, and the screen
  /// itself shows almost nothing that depends on the document -- the stage,
  /// the band and the timeline all listen for themselves. Rebuilding it for
  /// each of those would be work done for nothing.
  void _onSelectionChanged() {
    var next = _controller.backgroundSelected
        ? "background"
        : (_controller.selection.toList()..sort()).join(",");
    if (next == _selectionRevision) return;
    if (mounted) setState(() => _selectionRevision = next);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _setPanel(CanvasPanel panel) {
    setState(() => _panel = panel);
    Provider.of<CanvasPreferences>(context, listen: false).panel = panel.index;
  }

  /// _confirmDiscard asks before throwing away unsaved work.
  ///
  /// Asked before opening a different canvas and before starting from a
  /// preset, which are the two ways to lose one. There is no autosave: a
  /// canvas is a design being worked on, and saving over the last good version
  /// every few seconds is not what somebody experimenting wants.
  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Discard the changes?"),
            content: Text(
                "${_controller.name ?? "This canvas"} has changes that have "
                "not been saved."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Discard")),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _open(String folder, String name) async {
    var snackbar = SnackBarModel.of(context);
    if (!await _confirmDiscard()) return;

    var document = await CanvasStorage.load(folder, name);
    if (!mounted) return;
    if (document == null) {
      snackbar.error("Unable to read $name — the file may be damaged.");
      return;
    }
    _controller.load(document, folder: folder, name: name);
    if (mounted) {
      Provider.of<CanvasPreferences>(context, listen: false)
          .remember(folder, name);
    }
  }

  /// _openPreset starts a new canvas from a preset.
  ///
  /// The document is handed in already built rather than built here, so the
  /// panel's preview and the working copy are separate objects -- editing the
  /// new canvas must not change the thumbnail beside it.
  Future<void> _openPreset(
      CanvasPreset preset, CanvasDocument document) async {
    if (!await _confirmDiscard()) return;
    _controller.load(document);
    if (mounted) {
      Provider.of<CanvasPreferences>(context, listen: false).remember("", "");
      // Straight to the elements tab, because the next thing anybody does
      // after choosing a starting point is add something to it.
      _setPanel(CanvasPanel.elements);
    }
  }

  Future<void> _publishSaved(String folder, String name) async {
    var snackbar = SnackBarModel.of(context);
    var document = await CanvasStorage.load(folder, name);
    if (!mounted) return;
    if (document == null) {
      snackbar.error("Unable to read $name.");
      return;
    }
    // Published from the file rather than from whatever is in the editor, so
    // "publish that one" means the saved version even when something else is
    // open and half-edited.
    await showPublishSheet(
      context,
      document: document,
      images: _controller.images,
      frame: 0,
      folder: folder,
      name: name,
    );
  }

  Future<void> _openLink(String url) async {
    var snackbar = SnackBarModel.of(context);
    var confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Open this link?"),
        content: Text(url),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Open")),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await launchUrl(Uri.parse(url));
    } catch (exception) {
      if (mounted) snackbar.error("Unable to open the link: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    var client = Provider.of<ClientModel>(context);
    var theme = ThemeNotifier.of(context);

    var content = contentAreaFrame(theme, _content(theme));

    // Hidden means nothing beside the canvas. Not routed through
    // SecondarySideMenuLayout at all, since that would put its own sidebar back
    // where the panel had been -- which made the hide button look as though it
    // had merely closed the panel it was on. The Writing page does the same.
    if (!_sidebarVisible) return ScreenWithChatSideMenu(client, content);

    var sidebar = CanvasSidebarShell(
      panel: _panel,
      onPanelChanged: _setPanel,
      onHide: () => setState(() => _sidebarVisible = false),
      child: switch (_panel) {
        CanvasPanel.files => CanvasFilesPanel(
            controller: _controller,
            onOpen: _open,
            onPublish: _publishSaved,
          ),
        CanvasPanel.presets => CanvasPresetsPanel(onChoose: _openPreset),
        CanvasPanel.elements => CanvasElementsPanel(controller: _controller),
        CanvasPanel.layers => CanvasLayersPanel(controller: _controller),
      },
    );

    return ScreenWithChatSideMenu(
      client,
      SecondarySideMenuLayout(
        storageKey: "canvas",
        list: sidebar,
        // The collapsed drawer rebuilds the sidebar from a stored builder and
        // has no other way to know that what it shows has changed.
        // Which panel, and -- because the Layers panel shows the selected
        // layer's settings under the list -- what is selected. Without the
        // second the collapsed drawer would keep showing the settings of
        // whatever had been chosen when it was last built.
        sidebarRevision: (_panel, _selectionRevision),
        content: content,
      ),
    );
  }

  Widget _content(ThemeNotifier theme) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(children: [
          CanvasSettingsBar(
            controller: _controller,
            onPublish: _publish,
            canvasSettingsOpen: _canvasSettingsOpen,
            onToggleCanvasSettings: () =>
                setState(() => _canvasSettingsOpen = !_canvasSettingsOpen),
            // Only while the sidebar is away. The band is where every other
            // control on this page lives, so the one that brings the sidebar
            // back belongs in it rather than floating on the page behind it.
            onShowSidebar: _sidebarVisible
                ? null
                : () => setState(() => _sidebarVisible = true),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                // The whole canvas area is a drop target, so an element
                // dragged out of the sidebar lands where it was let go rather
                // than in the middle of the page.
                child: DragTarget<ElementKind>(
                  onAcceptWithDetails: (details) {
                    var stage = _stageKey.currentState;
                    var box = _stageKey.currentContext?.findRenderObject();
                    if (stage == null || box is! RenderBox) return;
                    var local = box.globalToLocal(details.offset);
                    _controller.addElement(newElement(
                      details.data,
                      _controller.document,
                      center: stage.toDocumentPoint(local),
                    ));
                  },
                  builder: (context, candidate, rejected) => Container(
                    color: candidate.isEmpty
                        ? null
                        : theme.colors.primary.withValues(alpha: 0.06),
                    child: CanvasStage(
                      key: _stageKey,
                      controller: _controller,
                      onButtonLink: _openLink,
                    ),
                  ),
                ),
              ),
              // Over the top of the canvas rather than above it, so opening
              // the settings does not move the design. It covers a strip of
              // the canvas's top edge while it is open, which closing it gets
              // back; pushing the canvas down is not recoverable in the same
              // way -- the zoom changes under whatever was being looked at.
              if (_canvasSettingsOpen)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CanvasSettingsPanel(controller: _controller),
                ),
              // The pose bar sits against the timeline, at the bottom of the
              // canvas area, for the same reason the settings sit against the
              // band at the top: over the design rather than pushing it.
              if (_keyframesOpen && !_controller.playing)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: CanvasKeyframeBar(controller: _controller),
                ),
            ]),
          ),
          CanvasTimeline(
            controller: _controller,
            keyframesOpen: _keyframesOpen,
            onToggleKeyframes: () =>
                setState(() => _keyframesOpen = !_keyframesOpen),
          ),
        ]),
      );

  /// _publish opens the publish sheet for whatever is in the editor.
  ///
  /// Reached from the settings band's Publish button, which is where the two
  /// undo controls are as well -- they used to float over the top-right corner
  /// of the canvas, on top of the design, which is the one place on this page
  /// nothing should be sitting.
  void _publish() => showPublishSheet(
        context,
        document: _controller.document,
        images: _controller.images,
        frame: _controller.frame,
        folder: _controller.folder,
        name: _controller.name,
      );

}
