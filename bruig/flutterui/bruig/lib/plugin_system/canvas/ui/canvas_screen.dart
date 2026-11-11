import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/ui/image_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/ui/text_documents.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/space_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dock.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/customise_sidebars.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:provider/provider.dart';
import 'package:bruig/plugin_system/canvas/ui/character_studio_3d.dart';
import 'package:url_launcher/url_launcher.dart';

// canvas_screen.dart is the Canvas section: a sidebar, the canvas, a settings
// band above it and a timeline below. It exists only while the Canvas
// feature is turned on (see canvas_nav.dart). The band and the timeline
// belong to the canvas rather than the sidebar, so they are inside the
// content area and stop at its edges.

/// startsWithSettingsOpen is whether a canvas just started should open with
/// the canvas settings line already out: when nothing is on it yet, since
/// the page's shape and export width are decided before anything is put on
/// it. A preset arrives with its shape chosen and something drawn in it.
/// allScenes rather than scenes: a document with one scene keeps its
/// elements on the document and leaves the list empty.
bool startsWithSettingsOpen(CanvasDocument document) =>
    document.allScenes.every((scene) => scene.elements.isEmpty);

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
  /// _controller holds the editing session, and it outlives this page: read
  /// from the provider and not disposed here, so leaving Canvas for a chat and
  /// coming back finds the same document, selection, zoom, frame and undo
  /// history, unsaved edits included.
  late final CanvasController _controller = context.read<CanvasController>();

  final GlobalKey<CanvasStageState> _stageKey = GlobalKey<CanvasStageState>();

  /// _sidebars is how the sidebar is set out (see sidebar_layout.dart):
  /// shown or not and how, which sidebar is on show, and their panels. Kept
  /// in the preferences as it changes.
  late SidebarLayout _sidebars;

  /// _bodies are the sidebar panels' bodies, built once each.
  late final SidebarPanelBodies _bodies = SidebarPanelBodies(
    controller: _controller,
    onOpen: _open,
    onPublish: _publishSaved,
    onNew: _newCanvas,
    onChoosePreset: _openPreset,
  );

  /// _selectionRevision identifies what is selected, for the collapsed
  /// sidebar (see sidebarRevision below). A string rather than the set,
  /// which the controller mutates and replaces.
  String _selectionRevision = "";

  /// _sidebarVisible is whether the sidebar is showing, one way or the other.
  /// the Writing page's: hiding it is "give me the width for a minute".
  bool get _sidebarVisible =>
      _audioKind ? _audioSidebarShown : _sidebars.mode != SidebarMode.hidden;

  /// _audioSidebarShown is whether an audio document's sidebar is out: shut
  /// to begin with, and always full height, as its panels fill the page.
  /// For this session, so it leaves the sidebar of a design as it was.
  bool _audioSidebarShown = false;

  /// _aboveAllowed is whether the sidebar can sit above the bottom panels:
  /// only with the canvas on screen beside it.
  bool get _aboveAllowed => _shown && !_audioKind;

  /// _canvasSettingsOpen is whether the canvas settings line is out. Closed
  /// to begin with: the ratio and export width are set once and then rarely
  /// touched.
  bool _canvasSettingsOpen = false;

  /// _guidesOpen is whether the grid and guides line is out. Only one of the
  /// two lines at a time: they open in the same place.
  bool _guidesOpen = false;

  /// _timelineOpen is whether the transport and the strip under the canvas
  /// are showing: off to begin with and then whatever it was left as (see
  /// CanvasPreferences.timeline), since most canvases are still designs.
  bool _timelineOpen = false;

  /// _canvasShown is whether the canvas is on screen. Put away, it is kept
  /// (its zoom, selection, tools) but neither drawn nor touched, and the
  /// mixer and effects fill the room. For this session.
  bool _canvasShown = true;

  /// _audioKind is an audio document: worked on the timeline and the
  /// mixer, so its timeline is always out.
  bool get _audioKind => _controller.document.kind.isAudio;

  /// _noCanvas is a document with no picture (Ratio "None"), whose canvas
  /// is away for good.
  bool get _noCanvas => _audioKind && !_controller.document.hasCanvas;
  bool get _shown => _canvasShown && !_noCanvas && !_controller.chainFull;
  bool get _timelineShown => _timelineOpen || _audioKind;

  /// _dockOpen is whether any panel under the canvas is open.
  bool get _dockOpen => DockPanel.values.any(_controller.dockOpen);

  /// _dockRoom is the room the panels under the canvas have: everything
  /// under the settings bar and over the play bar, less what of the canvas
  /// stays in view while it is shown.
  double get _dockRoom => math.max(
      0.0, _pageSeen - _topSeen - dockBarHeight - (_shown ? canvasLeast : 0));

  /// _keepDock keeps where the panels open, as it changes: only when it
  /// has, since this hears every change, which playing is every frame.
  void _keepDock() {
    if (identical(_controller.dock, _dockKept)) return;
    _dockKept = _controller.dock;
    _prefs.dock = _controller.dock;
  }

  DockLayout? _dockKept;

  /// _viewKey is the canvas whose view (see CanvasController.canvasView) is
  /// being kept, by its folder and name; null for one never saved.
  String? _viewKey;
  bool _viewKeyKnown = false;
  Timer? _keepTimer;

  String? get _canvasKey => _controller.name == null
      ? null
      : "${_controller.folder ?? ""}/${_controller.name}";

  /// _keepPanels keeps how the panels were left (see panelState and
  /// canvasView) a moment after they change, not on every change, which while
  /// playing is every frame. When another canvas opens, the last one's view is
  /// kept and its own put back.
  void _keepPanels() {
    var key = _canvasKey;
    if (!_viewKeyKnown || key != _viewKey) {
      if (_viewKeyKnown) _savePanels();
      _viewKeyKnown = true;
      _viewKey = key;
      // As it was left or, one never looked at, as it starts (not the last
      // canvas's channels and zoom). After this change has been told:
      // putting it back tells again.
      var view = key == null ? null : _prefs.canvasView(key);
      scheduleMicrotask(() {
        if (mounted && _canvasKey == key) {
          _controller.restoreCanvasView(view ?? const {});
        }
      });
      return;
    }
    // Not while it plays: what is kept changes at every frame of it (the
    // view follows the playhead), and it is kept as it stops.
    if (_controller.playing) return;
    _keepTimer ??= Timer(const Duration(milliseconds: 800), () {
      _keepTimer = null;
      _savePanels();
    });
  }

  void _savePanels() {
    _keepTimer?.cancel();
    _keepTimer = null;
    _prefs.panels = _controller.panelState;
    if (_viewKey case var key?) {
      _prefs.setCanvasView(key, _controller.canvasView);
    }
  }

  /// _prefs is the preferences, taken once: they are kept as the page is
  /// left, when looking them up is no longer allowed.
  late final CanvasPreferences _prefs =
      Provider.of<CanvasPreferences>(context, listen: false);

  /// _pushScale lays a Push's pads out in the played channel's scale.
  void _pushScale() {
    var (root, steps) = _controller.liveScale;
    var push = MidiInput.shared.push;
    push?.setScale(root, steps);
    // And, in Session mode, the slots' pads as they launch and stop.
    if (push != null && push.session) push.refresh();
  }

  /// _keepShown saves which timeline rows are showing whenever one is shown
  /// or hidden: the preferences skip a value that has not changed.
  void _keepShown() {
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    prefs.cuesShown = _controller.cuesShown;
    // And the mixer's bands (C, D, M) and its returns (R): set up once.
    prefs.mixerBands = _controller.mixerBandNames;
    prefs.returnsShown = _controller.returnsShown;
    prefs.mixerLook = _controller.mixerLook;
  }

  @override
  void initState() {
    super.initState();
    // A MIDI keyboard plays this canvas's instruments while it is open.
    MidiInput.shared.onNote = _controller.midiNote;
    MidiInput.shared.onControl = _controller.midiControl;
    MidiInput.shared.onCc = _controller.midiCc;
    MidiInput.shared.onPlay = _controller.togglePlay;
    MidiInput.shared.onRecord =
        () => _controller.recording = !_controller.recording;
    // A Push's Session mode: its pads the clip slots.
    MidiInput.shared.onClip = _controller.pushClip;
    MidiInput.shared.clipAt = _controller.pushPad;
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    _sidebars = prefs.sidebars;
    // The Game sidebar only for a game.
    if (_sidebars.current == "game" && !_controller.document.game) {
      _sidebars = _sidebars.copyWith(current: _holding("settings"));
    }
    // Told after the first frame: notified during initState, a listener's
    // setState would land mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.gameTabOpen = _sidebars.current == "game";
      // A canvas opened from Files: put in the library, and opened here.
      if (prefs.pendingOpen case (var folder, var name)) {
        prefs.pendingOpen = null;
        _open(folder, name);
      }
    });
    // Returning to a page left where the settings are counts as having
    // used them.
    _designUsed =
        _sidebars.byId(_sidebars.current)?.panels.contains("settings") == true;
    _timelineOpen = prefs.timeline;
    // The frame the reader last chose, before anything is drawn. It belongs
    // to them rather than the document (see CanvasPreferences.fit). restoreFit
    // rather than the setter, which notifies: notifying a provided controller
    // inside initState marks an inherited widget dirty mid-build.
    for (var fit in CanvasFit.values) {
      if (fit.name == prefs.fit) _controller.restoreFit(fit);
    }
    _controller.restoreShown(cues: prefs.cuesShown);
    // The mixer as it was left: its bands, its returns, its height and the
    // effects panel's.
    _controller.restoreMixer(prefs.mixerBands, prefs.returnsShown);
    _controller.restoreMixerLook(prefs.mixerLook);
    // Where the panels open, as left, before which are open.
    _controller.restoreDock(prefs.dock);
    // On the first visit of the session only: after it, the controller
    // already holds how the panels were left and what was being worked on,
    // and reopening the last saved file would throw away unsaved edits.
    if (!_controller.opened) _controller.restorePanels(prefs.panels);
    if (!_controller.opened) _reopenLast(prefs);
    _controller.markOpened();
    _controller.addListener(_onSelectionChanged);
    _gameSeen = _controller.document.game;
    _controller.addListener(_followGame);
    _controller.addListener(_keepShown);
    _controller.addListener(_pushScale);
    _controller.addListener(_keepPanels);
    _controller.addListener(_keepDock);
    _keepPanels();
    // A text element can take its words from the Writing library, edited
    // elsewhere, so while this page is open those documents are re-read every
    // few seconds. A canvas with none does no work. See TextDocumentWatch.
    _documents = TextDocumentWatch(_controller)..start();
  }

  /// _reopenLast puts back whatever was open when the page was last left.
  /// It fails quietly: the file may have gone, and an empty canvas is a fine
  /// place to start.
  Future<void> _reopenLast(CanvasPreferences prefs) async {
    if (prefs.lastName.isEmpty) return;
    var document = await CanvasStorage.load(prefs.lastFolder, prefs.lastName);
    if (!mounted || document == null) return;
    _controller.load(document, folder: prefs.lastFolder, name: prefs.lastName);
  }

  /// _onSelectionChanged redraws the screen only when the selection moves:
  /// the controller notifies on every edit, and the stage, band and timeline
  /// all listen for themselves.
  void _onSelectionChanged() {
    // Whatever the frame has ended up as, written down: this is the one
    // place that sees every way it can change, the keyboard included.
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    if (prefs.fit != _controller.fit.name) prefs.fit = _controller.fit.name;

    var next = _controller.backgroundSelected
        ? "background"
        : (_controller.selection.toList()..sort()).join(",");
    if (next == _selectionRevision) return;
    if (!mounted) return;

    // Choosing something on the canvas goes to the Design tab, where its
    // settings are. Only when something has been chosen (clearing must not
    // leave the file list), and only once the reader has been to Design this
    // session (see _designUsed).
    var chose = next.isNotEmpty && next != _selectionRevision;
    setState(() => _selectionRevision = next);
    // Not from the Game panel, which shows what is chosen too: its game
    // settings.
    if (chose &&
        _designUsed &&
        _sidebars.current != _holding("settings") &&
        _sidebars.current != "game") {
      _showPanel("settings");
    }
  }

  /// _gameSeen is whether the canvas was a game when last looked at.
  bool _gameSeen = false;

  /// _followGame opens the Game panel as the canvas is made into a game (the
  /// Make game button in the bar) and goes back to Design as it stops being
  /// one.
  void _followGame() {
    var game = _controller.document.game;
    if (game == _gameSeen || !mounted) return;
    _gameSeen = game;
    if (game) {
      _showSidebar("game");
    } else if (_sidebars.current == "game") {
      _showPanel("settings");
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (MidiInput.shared.onNote == _controller.midiNote) {
      MidiInput.shared.onNote = null;
      MidiInput.shared.onControl = null;
      MidiInput.shared.onCc = null;
      MidiInput.shared.onPlay = null;
      MidiInput.shared.onRecord = null;
      MidiInput.shared.onClip = null;
      MidiInput.shared.clipAt = null;
    }
    _documents?.stop();
    _controller.removeListener(_onSelectionChanged);
    _controller.removeListener(_followGame);
    _controller.removeListener(_keepShown);
    _controller.removeListener(_pushScale);
    _controller.removeListener(_keepPanels);
    _controller.removeListener(_keepDock);
    _keepTimer?.cancel();
    _savePanels();
    // Everything the page set going stops when it is left (see leavePage):
    // the session goes on, but a canvas nobody is looking at would have no
    // off switch on screen. Just after this frame: stopping notifies
    // watchers, some of which are being taken down in this frame with the
    // tree locked.
    var controller = _controller;
    scheduleMicrotask(controller.leavePage);
    // Not disposed: the session outlives this page (see _controller).
    super.dispose();
  }

  /// _documents re-reads the Writing library documents this canvas draws.
  TextDocumentWatch? _documents;

  /// _designUsed is whether the Design tab has been opened this session,
  /// however it was reached. It gates the automatic switch to it: see
  /// _onSelectionChanged.
  bool _designUsed = false;

  /// _holding is the sidebar [panel] is in, or the first there is.
  String _holding(String panel) =>
      _sidebars.sidebarOf(panel)?.id ?? _sidebars.sidebars.first.id;

  /// _showPanel shows the sidebar [panel] is in.
  void _showPanel(String panel) => _showSidebar(_holding(panel));

  /// _showSidebar shows sidebar [id].
  void _showSidebar(String id) => _setSidebars(_sidebars.copyWith(current: id));

  /// _setSidebars is the sidebar set out as [next], kept.
  void _setSidebars(SidebarLayout next) {
    if (!mounted) return;
    // An audio document's sidebar is shown or put away for the session,
    // its place left as it was for the designs.
    if (_audioKind && next.mode == SidebarMode.hidden) {
      setState(() => _audioSidebarShown = false);
      return;
    }
    var shows = next.byId(next.current);
    if (shows?.panels.contains("settings") == true) _designUsed = true;
    setState(() => _sidebars = next);
    _controller.gameTabOpen = next.current == "game";
    _prefs.sidebars = next;
  }

  /// _customise opens the sidebars' settings.
  void _customise() => showCustomiseSidebars(context,
      controller: _controller, read: () => _sidebars, write: _setSidebars);

  /// _confirmDiscard keeps unsaved work, and asks only where it cannot. Called
  /// before opening a different canvas and before starting from a preset.
  ///
  /// A canvas with a file of its own is saved rather than asked about: it
  /// autosaves anyway (see CanvasController.scheduleAutosave). Only a canvas
  /// never saved, or one whose save fails, gets the question.
  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    if (_controller.name != null && await _controller.save()) return true;
    if (!mounted) return false;
    return askToConfirm(context,
        title: "Discard the changes?",
        message: "${_controller.name ?? "This canvas"} has changes that have "
            "not been saved.",
        confirm: "Discard");
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

  /// _newCanvas starts an empty one, already filed under [name]. Saved at
  /// once, so it autosaves from then on (see
  /// CanvasController.scheduleAutosave) and Files needs no Save button.
  Future<void> _newCanvas(String folder, String name) async {
    var snackbar = SnackBarModel.of(context);
    if (!await _confirmDiscard()) return;

    // The empty preset rather than a bare CanvasDocument, so this and the
    // Presets tab's "Empty canvas" are the same thing.
    _controller.load(emptyCanvas().copyWith(title: name));
    var saved = await _controller.saveAs(folder, name);
    if (!mounted) return;
    if (!saved) {
      snackbar.error("Unable to make $name.");
      return;
    }
    Provider.of<CanvasPreferences>(context, listen: false)
        .remember(folder, name);
    // Straight to the elements tab, as a preset does.
    _showPanel("add");
    _openCanvasSettings();
  }

  /// _openCanvasSettings puts the canvas settings line out, for a canvas
  /// starting from nothing (see startsWithSettingsOpen).
  void _openCanvasSettings() {
    if (!mounted) return;
    setState(() {
      _canvasSettingsOpen = true;
      // The two lines open in the same place.
      _guidesOpen = false;
    });
  }

  /// _openPreset starts a new canvas from a preset. The document is handed in
  /// already built, so editing the new canvas cannot change the panel's
  /// thumbnail.
  Future<void> _openPreset(
      CanvasPreset? preset, CanvasDocument document) async {
    if (!await _confirmDiscard()) return;
    _controller.load(document);
    if (mounted) {
      Provider.of<CanvasPreferences>(context, listen: false).remember("", "");
      // Straight to the elements tab: the next thing is to add something.
      _showPanel("add");
      // Only the empty preset: see startsWithSettingsOpen.
      if (startsWithSettingsOpen(document)) _openCanvasSettings();
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
    // Published from the file rather than from the editor, so "publish that
    // one" means the saved version even when something else is open.
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
    var uri = webLink(url);
    if (uri == null) {
      snackbar.error("Only web and email links open: $url");
      return;
    }
    var confirmed = await askToConfirm(context,
        title: "Open this link?", message: url, confirm: "Open");
    if (!confirmed) return;
    try {
      await launchUrl(uri);
    } catch (exception) {
      if (mounted) snackbar.error("Unable to open the link: $exception");
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: _controller.studio3dOpen,
      builder: (context, studio3d, _) =>
          studio3d ? _studio3dPage(context) : _canvasPage(context));

  /// _studio3dPage is the Character Studio, given the whole page in place of
  /// the canvas: see character_studio_3d.dart.
  Widget _studio3dPage(BuildContext context) {
    var client = Provider.of<ClientModel>(context);
    var theme = ThemeNotifier.of(context);
    return ScreenWithChatSideMenu(
        client,
        contentAreaFrame(
            theme,
            CharacterStudio3D(
                design: _controller.studio3dDesign,
                performance: _controller.studio3dPerformance,
                onDone: _controller.closeStudio3d)));
  }

  Widget _canvasPage(BuildContext context) {
    var client = Provider.of<ClientModel>(context);
    var theme = ThemeNotifier.of(context);

    // Space plays and stops from anywhere on this page: see CanvasSpaceBar.
    var content = CanvasSpaceBar(
        controller: _controller,
        child: contentAreaFrame(theme, _content(theme)));

    var sidebar = CanvasSidebar(
      controller: _controller,
      layout: _sidebars,
      onLayout: _setSidebars,
      bodies: _bodies,
      onCustomise: _customise,
      canSitAbove: _aboveAllowed,
    );

    // Hidden means nothing beside the canvas. Not through
    // SecondarySideMenuLayout, which would put its own sidebar back where the
    // panel had been. The Writing page does the same. Above the panels
    // under the canvas, it is the content's own, beside the canvas and over
    // the panels -- except on a window too narrow for a sidebar at all,
    // where it goes the way a full-height one does.
    var narrow = MediaQuery.sizeOf(context).width < kSidebarCollapseWidth;
    if (!_sidebarVisible) return ScreenWithChatSideMenu(client, content);
    if (_sidebars.mode == SidebarMode.above && !narrow && _aboveAllowed) {
      return ScreenWithChatSideMenu(
          client,
          CanvasSpaceBar(
              controller: _controller,
              child: contentAreaFrame(theme,
                  _content(theme, beside: _besideSidebar(theme, sidebar)))));
    }

    return ScreenWithChatSideMenu(
      client,
      SecondarySideMenuLayout(
        storageKey: "canvas",
        list: sidebar,
        // The collapsed drawer rebuilds the sidebar from a stored builder and
        // has no other way to know that what it shows has changed: which
        // sidebar, and what is selected (the Layers panel shows its
        // settings).
        sidebarRevision: (
          _sidebars.current,
          _selectionRevision,
          jsonEncode(_sidebars.toJson())
        ),
        content: content,
      ),
    );
  }

  /// _aboveWidth is the sidebar's width sitting above the panels.
  late double _aboveWidth =
      _prefs.sidebarAboveWidth > 0 ? _prefs.sidebarAboveWidth : 300;

  /// _besideSidebar is the sidebar in the content, left of the canvas and
  /// over the panels, its right edge dragged to make it wider or narrower.
  Widget _besideSidebar(ThemeNotifier theme, Widget sidebar) =>
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: _aboveWidth,
          child: SecondarySideMenu(width: _aboveWidth, child: sidebar),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const ValueKey("sidebarAboveGrip"),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(
                () => _aboveWidth = (_aboveWidth + d.delta.dx).clamp(220, 560)),
            onHorizontalDragEnd: (_) => _prefs.sidebarAboveWidth = _aboveWidth,
            child: Container(
                width: 5,
                decoration: BoxDecoration(
                    border: Border(
                        right:
                            BorderSide(color: theme.colors.outlineVariant)))),
          ),
        ),
      ]);

  /// _topSeen and _pageSeen are the heights of the band with the strip under
  /// it, and of the whole page, when last laid out, for the timeline to fit
  /// between. See _Measured. Reported by the page rather than read from a
  /// LayoutBuilder or GlobalKeys: the sidebar's own LayoutBuilder moves this
  /// page about, and rebuilding it mid-layout takes its tooltips with it,
  /// which asserts.
  double _topSeen = 48;
  double _pageSeen = double.infinity;

  void _measured({double? top, double? page}) {
    if (!mounted) return;
    var t = top ?? _topSeen, p = page ?? _pageSeen;
    if ((t - _topSeen).abs() > 0.5 || (p - _pageSeen).abs() > 0.5) {
      setState(() {
        _topSeen = t;
        _pageSeen = p;
      });
    }
  }

  /// _canvasAway is what is in the canvas's room while it is put away: behind
  /// the panels, which fill it as they do over the canvas, or, with neither
  /// the mixer nor the effects open, a word on where they are and the way
  /// back.
  Widget _canvasAway(ThemeNotifier theme) => ColoredBox(
        key: const ValueKey("canvasAway"),
        color: theme.colors.surface,
        child: _dockOpen
            ? const SizedBox.expand()
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_noCanvas ? "A piece of sound" : "The canvas is hidden",
                      style: TextStyle(color: theme.colors.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text("Open a panel from the play bar.",
                      style: TextStyle(
                          fontSize: 12, color: theme.colors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  if (!_noCanvas)
                    TextButton.icon(
                      key: const ValueKey("showCanvas"),
                      onPressed: () => setState(() => _canvasShown = true),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text("Show the canvas"),
                    ),
                ]),
              ),
      );

  Widget _content(ThemeNotifier theme, {Widget? beside}) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          var dock = _timelineShown
              ? CanvasDock(
                  controller: _controller,
                  room: _dockRoom,
                  fill: !_shown,
                  onCustomiseSidebars: _customise,
                )
              : null;
          // Laid out top first, then the dock as tall as it is, and the
          // canvas in what is left: the top's height is known a frame late
          // (see _Measured), and a Column would overflow for that frame.
          var page = ClipRect(
              child: CustomMultiChildLayout(delegate: _PageLayout(), children: [
            LayoutId(
                id: _PageLayout.top,
                child: _Measured(
                    onHeight: (h) => _measured(top: h),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CanvasSettingsBar(
                        controller: _controller,
                        onPublish: _publish,
                        canvasSettingsOpen: _canvasSettingsOpen,
                        onToggleCanvasSettings: () => setState(() {
                          _canvasSettingsOpen = !_canvasSettingsOpen;
                          if (_canvasSettingsOpen) _guidesOpen = false;
                        }),
                        guidesOpen: _guidesOpen,
                        onToggleGuides: () => setState(() {
                          _guidesOpen = !_guidesOpen;
                          if (_guidesOpen) _canvasSettingsOpen = false;
                        }),
                        canvasShown: _shown,
                        onToggleCanvas: _noCanvas
                            ? null
                            : () =>
                                setState(() => _canvasShown = !_canvasShown),
                        timelineOpen: _timelineShown,
                        onToggleTimeline: () => setState(() {
                          _timelineOpen = !_timelineOpen;
                          Provider.of<CanvasPreferences>(context, listen: false)
                              .timeline = _timelineOpen;
                        }),
                        // Only while the sidebar is away; on the band, with every other control
                        // on this page.
                        onShowSidebar: _sidebarVisible
                            ? null
                            : _audioKind
                                ? () =>
                                    setState(() => _audioSidebarShown = true)
                                : () => _setSidebars(_sidebars.shownAgain),
                      ),
                      ...canvasSecondLine(
                        settings: _canvasSettingsOpen
                            ? CanvasSettingsPanel(controller: _controller)
                            : null,
                        guides: _guidesOpen
                            ? CanvasGuidesPanel(controller: _controller)
                            : null,
                      ),
                    ]))),
            LayoutId(
              id: _PageLayout.middle,
              child: Stack(children: [
                Positioned.fill(
                  // Put away rather than taken out: Offstage keeps the
                  // stage's state and stops it painting and being hit.
                  child: Offstage(
                    offstage: !_shown,
                    // The whole canvas area is a drop target, so an element dragged out of
                    // the sidebar lands where it was let go.
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
                      builder: (context, candidate, rejected) =>
                          // And an asset from the Assets sidebar, or a stock result (fetched when
                          // it lands), becomes the element that shows it, where it was let go.
                          DragTarget<Object>(
                        onWillAcceptWithDetails: (d) =>
                            droppedKind(d.data) != null,
                        onAcceptWithDetails: (details) async {
                          var stage = _stageKey.currentState;
                          var box =
                              _stageKey.currentContext?.findRenderObject();
                          if (stage == null || box is! RenderBox) return;
                          var local = box.globalToLocal(details.offset);
                          var center = stage.toDocumentPoint(local);
                          var asset = await droppedAsset(details.data);
                          if (asset == null || !mounted) return;
                          _controller.addElement(elementForAsset(
                            asset,
                            _controller.document,
                            center: center,
                          ));
                        },
                        builder: (context, assets, _) => Container(
                          color: candidate.isEmpty && assets.isEmpty
                              ? null
                              : theme.colors.primary.withValues(alpha: 0.06),
                          // Each part of the page in a layer of its own
                          // (here and below): the stage redraws at every
                          // frame of play, and without these the timeline,
                          // the mixer and the sidebar were redrawn with
                          // it.
                          child: RepaintBoundary(
                            child: CanvasStage(
                              key: _stageKey,
                              controller: _controller,
                              onButtonLink: _openLink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_shown) Positioned.fill(child: _canvasAway(theme)),
                // The tool in hand on a picture, and what to do with it, over the top
                // of the canvas where the eye is: see image_tool_hint.dart.
                if (_shown)
                  Positioned(
                    top: 10,
                    left: 16,
                    right: 16,
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      ImageToolHint(controller: _controller),
                      // A drawing's hint as well: only one is ever being edited. (A
                      // character is drawn in the Character Studio, with its own bar.)
                      VectorToolHint(controller: _controller),
                    ])),
                  ),
              ]),
            ),
            // Taken out rather than shrunk to nothing when put away: the
            // play bar holds a focus node and a ticker, and an empty bar
            // would still answer the keyboard.
            if (beside == null && dock != null)
              LayoutId(id: _PageLayout.bottom, child: dock),
          ]));
          return _Measured(
              onHeight: (h) => _measured(page: h),
              child: beside == null
                  ? page
                  : Column(children: [
                      Expanded(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [beside, Expanded(child: page)]),
                      ),
                      if (dock != null) dock,
                    ]));
        },
      );

  /// _publish opens the publish sheet for whatever is in the editor, from the
  /// settings band's Publish button.
  void _publish() => showPublishSheet(
        context,
        document: _controller.document,
        images: _controller.images,
        frame: _controller.frame,
        folder: _controller.folder,
        name: _controller.name,
      );
}

/// canvasLeast is the least of the canvas kept in view when the window is
/// short: the timeline gives way rather than pushing it out.
const double canvasLeast = 120;

/// canvasSecondLine is the strip that opens under the band: the canvas
/// settings, or the grid and guides. Above the canvas rather than over it,
/// so it pushes the design down instead of covering its top edge, as the
/// timeline does at the bottom. A list of its own so a test can see where
/// it sits in the column.
List<Widget> canvasSecondLine({Widget? settings, Widget? guides}) => [
      if (settings != null) settings,
      // Never both at once, which the two toggles see to; if one gets through,
      // the settings win.
      if (settings == null && guides != null) guides,
    ];

/// _PageLayout lays the page out: [top] (the settings band) as tall as it
/// is, [bottom] (the dock) as tall as it is under it, and [middle] (the
/// canvas) in what is left between, never less than nothing.
class _PageLayout extends MultiChildLayoutDelegate {
  static const top = 0, middle = 1, bottom = 2;

  @override
  void performLayout(Size size) {
    var w = size.width;
    var wide = BoxConstraints(minWidth: w, maxWidth: w);
    var t = hasChild(top) ? layoutChild(top, wide).height : 0.0;
    var b = hasChild(bottom) ? layoutChild(bottom, wide).height : 0.0;
    var m = math.max(0.0, size.height - t - b);
    if (hasChild(middle)) {
      layoutChild(middle, BoxConstraints.tightFor(width: w, height: m));
      positionChild(middle, Offset(0, t));
    }
    if (hasChild(top)) positionChild(top, Offset.zero);
    if (hasChild(bottom)) positionChild(bottom, Offset(0, t + m));
  }

  @override
  bool shouldRelayout(_PageLayout oldDelegate) => false;
}

/// _Measured tells [onHeight] its child's height whenever layout changes it,
/// after the frame, so the change is a build of its own, not one in the
/// middle of layout.
class _Measured extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _Measured({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _told;
  _RenderMeasured(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    var h = size.height;
    if (_told != null && (h - _told!).abs() <= 0.5) return;
    _told = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
