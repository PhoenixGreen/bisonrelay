import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/code_run_host.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/character/character_studio_3d.dart';
import 'package:bruig/plugin_system/canvas/ui/code/code_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/element_offers.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_placing.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/text_documents.dart';
import 'package:bruig/plugin_system/canvas/ui/score/score_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_dock.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/kept_view.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/publish_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/page_keys.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/customise_sidebars.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_extras.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_screen.dart is the Canvas section: a sidebar, the canvas, a settings
// band above it and a timeline below, present only while the Canvas feature
// is on (see canvas_nav.dart). The band and timeline belong to the canvas,
// so they sit inside the content area and stop at its edges.

/// startsWithSettingsOpen is whether a new canvas opens with the canvas
/// settings line out: when nothing is on it yet, since its shape and export
/// width are decided first. A preset arrives with both. allScenes, not
/// scenes: a one-scene document keeps its elements on the document.
bool startsWithSettingsOpen(CanvasDocument document) =>
    document.allScenes.every((scene) => scene.elements.isEmpty);

/// CanvasScreenTitle is the page heading, which follows the menu's name for
/// the destination (Settings > Appearance > Menu).
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

  /// framedForTest, where set, puts each page in place of the app's frame
  /// (the chat side menu over it), which needs the chat client a test of
  /// the whole editor does not have.
  @visibleForTesting
  static Widget Function(Widget page)? framedForTest;

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  /// _controller holds the editing session and outlives this page: read from
  /// the provider, not disposed here, so leaving Canvas and coming back finds
  /// the same document, selection, zoom, frame and undo history.
  late final CanvasController _controller = context.read<CanvasController>();

  final GlobalKey<CanvasStageState> _stageKey = GlobalKey<CanvasStageState>();

  /// _sidebars is how the sidebar is set out (sidebar_layout.dart), kept.
  late SidebarLayout _sidebars;

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

  /// _sidebarVisible is whether the sidebar is showing, one way or another.
  bool get _sidebarVisible =>
      _audioKind ? _audioSidebarShown : _sidebars.mode != SidebarMode.hidden;

  /// _audioSidebarShown is whether an audio document's sidebar is out: shut
  /// at first, always full height, and for this session only, so a design's
  /// sidebar is left as it was.
  bool _audioSidebarShown = false;

  /// _aboveAllowed: the sidebar sits above the panels only beside a canvas.
  bool get _aboveAllowed => _shown && !_audioKind;

  /// _line is the line open under the band, if one is.
  BandLine? _line;

  /// _timelineOpen is whether the transport and strip under the canvas show:
  /// off at first, then as left (CanvasPreferences.timeline).
  bool _timelineOpen = false;

  /// _canvasShown is whether the canvas is on screen. Put away, it is kept
  /// but neither drawn nor touched, and the panels fill the room. Per session.
  bool _canvasShown = true;

  /// _audioKind is an audio document, whose timeline is always out.
  bool get _audioKind => _controller.document.kind.isAudio;

  /// _noCanvas is a document with no picture (Ratio "None").
  bool get _noCanvas => _audioKind && !_controller.document.hasCanvas;
  bool get _shown => _canvasShown && !_noCanvas && !_controller.chainFull;
  bool get _timelineShown => _timelineOpen || _audioKind;

  bool get _dockOpen => DockPanel.values.any(_controller.dockOpen);

  /// _dockRoom is the panels' room: from the settings bar to the play bar,
  /// less what of the canvas stays in view while shown.
  double get _dockRoom => math.max(
      0.0, _pageSeen - _topSeen - dockBarHeight - (_shown ? canvasLeast : 0));

  /// _prefs and _kept are made as the page opens: both are needed as it is
  /// left, when looking the preferences up is no longer allowed.
  late final CanvasPreferences _prefs;

  /// _kept puts back how the page was left and writes it down as it
  /// changes: the frame, the rulers, the cues, the mixer, the panels, and
  /// how each canvas was looked at. What is remembered is listed there.
  late final KeptView _kept;

  /// _pushScale lays a Push's pads out in the played channel's scale.
  void _pushScale() {
    // Heard on every change to the canvas: nothing to work out without one.
    var push = MidiInput.shared.push;
    if (push == null) return;
    var (root, steps) = _controller.liveScale;
    push.setScale(root, steps);
    // And, in Session mode, the slots' pads as they launch and stop.
    if (push.session) push.refresh();
  }

  /// _midiNote is what this page hands a MIDI keyboard for its keys, made
  /// once. midiNote is a method of one of the controller's extensions, and
  /// one of those torn off is a new closure each time, never equal to the
  /// last: asked afresh in dispose, it could not be told that the keyboard
  /// was still this page's, and the keyboard was never given back.
  late final void Function(int key, int velocity, {String? from}) _midiNote =
      _controller.midiNote;

  @override
  void initState() {
    super.initState();
    // Run panels run code in this app: a hidden browser, Pyodide, Yaegi.
    useAppCodeRunHost();
    // A MIDI keyboard plays this canvas's instruments while it is open.
    MidiInput.shared.onNote = _midiNote;
    MidiInput.shared.onControl = _controller.midiControl;
    MidiInput.shared.onCc = _controller.midiCc;
    MidiInput.shared.onPlay = _controller.togglePlay;
    MidiInput.shared.onRecord =
        () => _controller.recording = !_controller.recording;
    // A Push's Session mode: its pads the clip slots.
    MidiInput.shared.onClip = _controller.pushClip;
    MidiInput.shared.clipAt = _controller.pushPad;
    var prefs = _prefs = Provider.of<CanvasPreferences>(context, listen: false);
    _sidebars = prefs.sidebars;
    // The Game sidebar only for a game.
    if (_sidebars.current == SidebarSet.gameId && !_controller.document.game) {
      _sidebars = _sidebars.copyWith(current: _holding(SidebarPanel.settings));
    }
    // Told after the first frame: notified during initState, a listener's
    // setState would land mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.gameTabOpen = _sidebars.current == SidebarSet.gameId;
      // A canvas opened from Files: put in the library, and opened here.
      if (prefs.pendingOpen case (var folder, var name)) {
        prefs.pendingOpen = null;
        _open(folder, name);
      }
    });
    // Returning to a page left on the settings counts as having used them.
    _designUsed = _sidebars
            .byId(_sidebars.current)
            ?.panels
            .contains(SidebarPanel.settings) ==
        true;
    _timelineOpen = prefs.timeline;
    // How the page was left, before anything is drawn.
    _kept = KeptView(_controller, prefs)..open();
    // First visit of the session only: after it the controller holds the
    // work, and reopening the last saved file would throw away unsaved
    // edits. Not when a canvas from Files is about to open (below): the two
    // reads would race, and the one to finish last would be the one left
    // open.
    if (!_controller.opened && prefs.pendingOpen == null) _reopenLast(prefs);
    _controller.markOpened();
    _controller.addListener(_onSelectionChanged);
    _gameSeen = _controller.document.game;
    _controller.addListener(_followGame);
    _controller.addListener(_pushScale);
    // A text element can take its words from the Writing library, edited
    // elsewhere, so those documents are re-read every few seconds while this
    // page is open; a canvas with none does no work.
    _documents = TextDocumentWatch(_controller)..start();
  }

  /// _reopenLast puts back what was open when the page was left, failing
  /// quietly: the file may be gone.
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
    var next = _controller.backgroundSelected
        ? "background"
        : (_controller.selection.toList()..sort()).join(",");
    if (next == _selectionRevision) return;
    if (!mounted) return;

    // Choosing something goes to the sidebar its settings are in --
    // only on a choice (clearing must not leave the file list), and only once
    // Design has been used this session (_designUsed).
    var chose = next.isNotEmpty && next != _selectionRevision;
    setState(() => _selectionRevision = next);
    // Not from the Game panel, which shows the chosen element's game settings.
    if (chose &&
        _designUsed &&
        _sidebars.current != _holding(SidebarPanel.settings) &&
        _sidebars.current != SidebarSet.gameId &&
        // A feature's own sidebar (an assistant picking what it works on)
        // keeps the column while it is there: see sidebar_extras.dart.
        CanvasSidebarExtras.byId(_sidebars.current) == null) {
      _showPanel(SidebarPanel.settings);
    }
  }

  bool _gameSeen = false;

  /// _followGame opens the Game panel as the canvas becomes a game, and goes
  /// back to Design as it stops being one.
  void _followGame() {
    var game = _controller.document.game;
    if (game == _gameSeen || !mounted) return;
    _gameSeen = game;
    if (game) {
      _showSidebar(SidebarSet.gameId);
    } else if (_sidebars.current == SidebarSet.gameId) {
      _showPanel(SidebarPanel.settings);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Only if they are still this page's, and not a newer Canvas page's put
    // up before this one came down.
    if (identical(MidiInput.shared.onNote, _midiNote)) {
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
    _controller.removeListener(_pushScale);
    _kept.close();
    // Everything the page set going stops when it is left (see leavePage):
    // a canvas nobody is looking at has no off switch on screen. Just after
    // this frame: stopping notifies watchers, some being taken down in this
    // frame with the tree locked.
    var controller = _controller;
    scheduleMicrotask(controller.leavePage);
    // Not disposed: the session outlives this page (see _controller).
    super.dispose();
  }

  TextDocumentWatch? _documents;

  /// _designUsed is whether Design has been opened this session; it gates
  /// the switch to it in _onSelectionChanged.
  bool _designUsed = false;

  /// _holding is the sidebar [panel] is in, or the first there is.
  String _holding(SidebarPanel panel) =>
      _sidebars.sidebarOf(panel)?.id ?? _sidebars.sidebars.first.id;

  void _showPanel(SidebarPanel panel) => _showSidebar(_holding(panel));

  void _showSidebar(String id) => _setSidebars(_sidebars.copyWith(current: id));

  void _setSidebars(SidebarLayout next) {
    if (!mounted) return;
    var shows = next.byId(next.current);
    if (shows?.panels.contains(SidebarPanel.settings) == true) {
      _designUsed = true;
    }
    setState(() => _sidebars = next);
    _controller.gameTabOpen = next.current == SidebarSet.gameId;
    _prefs.sidebars = next;
  }

  /// _hideSidebar puts the sidebar away: a design's as it is kept, a piece
  /// of sound's for this visit only (_audioSidebarShown).
  void _hideSidebar() => _audioKind
      ? setState(() => _audioSidebarShown = false)
      : _setSidebars(_sidebars.withMode(SidebarMode.hidden));

  void _customise() =>
      showCustomiseSidebars(context, layout: _sidebars, write: _setSidebars);

  /// _confirmDiscard keeps unsaved work before another canvas or a preset
  /// opens, asking only where it cannot: a canvas with a file is saved (it
  /// autosaves anyway); only one never saved, or whose save fails, is asked.
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
      _prefs.remember(folder, name);
    }
  }

  /// _newCanvas starts an empty canvas filed under [name], saved at once so
  /// it autosaves from then on and Files needs no Save button.
  Future<void> _newCanvas(String folder, String name) async {
    var snackbar = SnackBarModel.of(context);
    if (!await _confirmDiscard()) return;

    // The empty preset, so this and the Presets panel's "Empty canvas" match.
    _controller.load(emptyCanvas().copyWith(title: name));
    var saved = await _controller.saveAs(folder, name);
    if (!mounted) return;
    if (!saved) {
      snackbar.error("Unable to make $name.");
      return;
    }
    _prefs.remember(folder, name);
    // Straight to the Add panel, as a preset does.
    _showPanel(SidebarPanel.add);
    _openCanvasSettings();
  }

  /// _openCanvasSettings puts the settings line out for a canvas starting
  /// from nothing.
  void _openCanvasSettings() {
    if (!mounted) return;
    setState(() => _line = BandLine.settings);
  }

  /// _openPreset starts a new canvas from a preset, handed in already built
  /// so editing it cannot change the panel's thumbnail.
  Future<void> _openPreset(CanvasDocument document) async {
    if (!await _confirmDiscard()) return;
    _controller.load(document);
    if (mounted) {
      _prefs.remember("", "");
      // Straight to the Add panel: the next thing is to add something.
      _showPanel(SidebarPanel.add);
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
    // From the file, not the editor: "publish that one" means the saved
    // version even when something else is open.
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
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
      valueListenable: _controller.dataStudio,
      builder: (context, sheet, _) => sheet != null
          ? _dataStudioPage(context, sheet)
          : ValueListenableBuilder<String?>(
              valueListenable: _controller.codeStudio,
              builder: (context, code, _) => code != null
                  ? _codeStudioPage(context, code)
                  : _withoutCodeStudio(context)));

  /// _framed is [page] in the app's frame.
  Widget _framed(BuildContext context, Widget page) =>
      CanvasScreen.framedForTest?.call(page) ??
      ScreenWithChatSideMenu(Provider.of<ClientModel>(context), page);

  /// _dataStudioPage is the Data Studio in place of the canvas.
  Widget _dataStudioPage(BuildContext context, String sheet) {
    var theme = ThemeNotifier.of(context);
    return _framed(
        context,
        contentAreaFrame(
            theme,
            DataStudio(
                controller: _controller,
                sheetId: sheet,
                onDone: _controller.closeDataStudio)));
  }

  Widget _withoutCodeStudio(BuildContext context) =>
      ValueListenableBuilder<String?>(
          valueListenable: _controller.scoreStudio,
          builder: (context, score, _) => score != null
              ? _scoreStudioPage(context, score)
              : ValueListenableBuilder<bool>(
                  valueListenable: _controller.studio3dOpen,
                  builder: (context, studio3d, _) => studio3d
                      ? _studio3dPage(context)
                      : _canvasPage(context)));

  /// _codeStudioPage is the Code Studio in place of the canvas.
  Widget _codeStudioPage(BuildContext context, String code) {
    var theme = ThemeNotifier.of(context);
    return _framed(
        context,
        contentAreaFrame(
            theme,
            CodeStudio(
                controller: _controller,
                codeId: code,
                onDone: _controller.closeCodeStudio)));
  }

  /// _scoreStudioPage is the Score Studio in place of the canvas.
  Widget _scoreStudioPage(BuildContext context, String score) {
    var theme = ThemeNotifier.of(context);
    return _framed(
        context,
        contentAreaFrame(
            theme,
            ScoreStudio(
                controller: _controller,
                scoreId: score,
                onDone: _controller.closeScoreStudio)));
  }

  /// _studio3dPage is the Character Studio in place of the canvas.
  Widget _studio3dPage(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _framed(
        context,
        contentAreaFrame(
            theme,
            CharacterStudio3D(
                design: _controller.studio3dDesign,
                performance: _controller.studio3dPerformance,
                onDone: _controller.closeStudio3d)));
  }

  Widget _canvasPage(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    // The page's keys, wherever the focus is on it: see CanvasPageKeys.
    var content = CanvasPageKeys(
        controller: _controller,
        child: contentAreaFrame(theme, _content(theme)));

    var sidebar = CanvasSidebar(
      controller: _controller,
      layout: _sidebars,
      onLayout: _setSidebars,
      onHide: _hideSidebar,
      bodies: _bodies,
      onCustomise: _customise,
      canSitAbove: _aboveAllowed,
    );

    // Hidden means nothing beside the canvas -- not via
    // SecondarySideMenuLayout, which would put its own sidebar back, as the
    // Writing page also avoids. Above the panels, the sidebar is the
    // content's own, except on a window too narrow for one, where it goes
    // the way a full-height one does.
    var narrow = MediaQuery.sizeOf(context).width < kSidebarCollapseWidth;
    if (!_sidebarVisible) return _framed(context, content);
    if (_sidebars.mode == SidebarMode.above && !narrow && _aboveAllowed) {
      return _framed(
          context,
          CanvasPageKeys(
              controller: _controller,
              child: contentAreaFrame(theme,
                  _content(theme, beside: _besideSidebar(theme, sidebar)))));
    }

    return _framed(
      context,
      SecondarySideMenuLayout(
        storageKey: "canvas",
        list: sidebar,
        // The collapsed drawer rebuilds from a stored builder and cannot
        // otherwise know which sidebar or selection it shows has changed.
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

  /// _besideSidebar is the sidebar left of the canvas and over the panels,
  /// its right edge dragged to resize it.
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

  /// _topSeen and _pageSeen are the heights of the band with its strip, and
  /// of the whole page, at last layout, for the timeline to fit between (see
  /// _Measured). Reported, not read from a LayoutBuilder or GlobalKeys: the
  /// sidebar's LayoutBuilder moves this page, and rebuilding it mid-layout
  /// takes its tooltips with it, which asserts.
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

  /// _canvasAway fills the canvas's room while it is away: the panels, or a
  /// word on where they are and the way back.
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

  /// _content is the page under the sidebar. It is laid out again only on
  /// [CanvasController.chrome]: what is in it listens for itself, so a drag
  /// or a frame of play does not build the whole page again.
  Widget _content(ThemeNotifier theme, {Widget? beside}) => ListenableBuilder(
        listenable: _controller.chrome,
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
                        line: _line,
                        onLine: (line) => setState(() => _line = line),
                        canvasShown: _shown,
                        onToggleCanvas: _noCanvas
                            ? null
                            : () =>
                                setState(() => _canvasShown = !_canvasShown),
                        timelineOpen: _timelineShown,
                        // A piece of sound always shows them: nothing to
                        // switch, and nothing to keep.
                        onToggleTimeline: _audioKind
                            ? null
                            : () => setState(() {
                                  _timelineOpen = !_timelineOpen;
                                  _prefs.timeline = _timelineOpen;
                                }),
                        // Only while the sidebar is away; on the band, with
                        // every other control on this page.
                        onShowSidebar: _sidebarVisible
                            ? null
                            : _audioKind
                                ? () =>
                                    setState(() => _audioSidebarShown = true)
                                : () => _setSidebars(_sidebars.shownAgain),
                      ),
                      // Under the band, not over the canvas: it pushes
                      // the design down and does not cover its top.
                      ...switch (_line) {
                        BandLine.settings => [
                            CanvasSettingsPanel(controller: _controller)
                          ],
                        BandLine.guides => [
                            CanvasGuidesPanel(controller: _controller)
                          ],
                        null => const <Widget>[],
                      },
                    ]))),
            LayoutId(
              id: _PageLayout.middle,
              child: Stack(children: [
                Positioned.fill(
                  // Put away rather than taken out: Offstage keeps the
                  // stage's state and stops it painting and being hit.
                  child: Offstage(
                    offstage: !_shown,
                    // The whole canvas area is a drop target: a chip
                    // dragged from the Add panel lands where it was let go.
                    child: DragTarget<AddOffer>(
                      onAcceptWithDetails: (details) {
                        var stage = _stageKey.currentState;
                        var box = _stageKey.currentContext?.findRenderObject();
                        if (stage == null || box is! RenderBox) return;
                        var local = box.globalToLocal(details.offset);
                        details.data.add(_controller,
                            center: stage.toDocumentPoint(local));
                      },
                      builder: (context, candidate, rejected) =>
                          // An asset or stock result (fetched as it lands)
                          // becomes the element showing it, where let go;
                          // a MIDI file, a MIDI channel (see placeAsset).
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
                          await placeAsset(_controller, asset, center: center);
                        },
                        builder: (context, assets, _) => Container(
                          color: candidate.isEmpty && assets.isEmpty
                              ? null
                              : theme.colors.primary.withValues(alpha: 0.06),
                          // Each part of the page in its own layer (here and
                          // below): the stage redraws every frame of play,
                          // and must not take the timeline, mixer and
                          // sidebar with it.
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
                // The tool in hand on a picture, and what to do with it, over
                // the canvas: see image_tool_hint.dart.
                if (_shown)
                  Positioned(
                    top: 10,
                    left: 16,
                    right: 16,
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      ImageToolHint(controller: _controller),
                      // A drawing's hint as well: only one is edited at once.
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

  /// _publish opens the publish sheet for what is in the editor.
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

/// _PageLayout lays out [top] (the settings band) and [bottom] (the dock)
/// at their heights, and [middle] (the canvas) in what is left, never less
/// than nothing.
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

/// _Measured tells [onHeight] its child's height when layout changes it,
/// after the frame, so the change is a build of its own, not mid-layout.
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
