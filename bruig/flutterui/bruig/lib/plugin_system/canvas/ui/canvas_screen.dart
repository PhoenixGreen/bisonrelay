import 'dart:async';
import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/character_draw_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/image_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
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
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/game_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/panel_heights.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/ui/text_documents.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/space_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/publish_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/files_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
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

/// startsWithSettingsOpen is whether a canvas just started should open with
/// the canvas settings line already out.
///
/// A canvas with nothing on it yet: the shape of the page and the width it
/// exports at are decided once, before anything is put on it, and having them
/// already showing is the whole invitation to decide them. A preset arrives
/// with its shape chosen on purpose and something drawn in it, so the line
/// would only be covering the thing that was chosen.
/// allScenes rather than scenes: a document with one scene keeps its elements
/// on the document itself and leaves the list empty, which "every" would call
/// empty however much is drawn on it.
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
  /// _controller holds the editing session, and it outlives this page.
  ///
  /// Read from the provider rather than created here, and deliberately not
  /// disposed by this widget: leaving Canvas for a chat and coming back has to
  /// find the canvas exactly as it was -- the same document, the same
  /// selection, the same zoom, the same frame, the same undo history. Owned by
  /// the page, all of that went when the route was popped, and reopening the
  /// last *saved* file was not the same thing at all: it lost every unsaved
  /// edit made since, which on a page where a document is often never saved is
  /// most of the work.
  late final CanvasController _controller = context.read<CanvasController>();

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

  /// _guidesOpen is whether the grid and guides line is out.
  ///
  /// Only one of the two lines at a time: they open in the same place, so both
  /// at once would be one on top of the other.
  bool _guidesOpen = false;

  /// _timelineOpen is whether the transport and the strip under the canvas
  /// are showing.
  ///
  /// Off to begin with and then whatever it was left as -- see
  /// CanvasPreferences.timeline. Most canvases are still designs, and a strip
  /// of animation controls under one is room taken from the page; somebody
  /// who does animate turns it on once rather than on every visit.
  bool _timelineOpen = false;

  /// _canvasShown is whether the canvas is on screen. Put away, it is kept
  /// -- its zoom, its selection, its tools -- but neither drawn nor
  /// touched, and the mixer and effects fill the room. For this session.
  bool _canvasShown = true;

  /// _audioKind is an audio document: worked on the timeline and the
  /// mixer, so its timeline is always out.
  bool get _audioKind => _controller.document.kind.isAudio;

  /// _noCanvas is a document with no picture -- Ratio "None" -- whose
  /// canvas is away for good.
  bool get _noCanvas => _audioKind && !_controller.document.hasCanvas;
  bool get _shown => _canvasShown && !_noCanvas;
  bool get _timelineShown => _timelineOpen || _audioKind;

  /// _keyframesOpen is whether the pose bar is out.
  ///
  /// Held here rather than in the timeline for the same reason the canvas
  /// settings are: the bar floats over the canvas area, and a strip that grew
  /// to hold it took height from the canvas and re-fitted it -- so opening a
  /// panel moved the design.
  bool _keyframesOpen = false;

  /// _timelineHeight is how tall the timeline is: its least, and whatever it
  /// has been dragged open to for the channels. Kept in the preferences.
  double _timelineHeight = timelineHeight;

  /// _mixerHeight is the mixer's -- see CanvasMixer; whether it is open is
  /// the controller's mixerOpen, set from the timeline. The height is the
  /// session's: a mixer somebody made tall stays tall while they work.
  double _mixerHeight = mixerDefaultHeight;

  /// _mixerLeast is how short the mixer goes with its bands as they are --
  /// see mixerLeastHeight -- at the text's size: the mixer is zoomed with
  /// it. Minimised from the timeline, it is that.
  double get _mixerLeast =>
      mixerLeastHeight(_controller) *
      math.max(1.0, MediaQuery.textScalerOf(context).scale(1));

  /// _mixerShown is the mixer's height on screen: minimised, its least; or
  /// as it was dragged, never under its least.
  double get _mixerShown {
    var least = _mixerLeast;
    return _mixerFixed ? least : math.max(least, _mixerHeight);
  }

  /// _mixerFixed is the mixer minimised or smallest: at its least, giving
  /// and taking no room.
  bool get _mixerFixed =>
      _controller.mixerMinimised || _controller.mixerSmallest;

  /// _stack is the panels under the canvas, top to bottom, sized as one --
  /// see panel_heights.dart: each as it was set, its least, and whether it
  /// is fixed -- a bar, or the mixer minimised. The same stack with the
  /// canvas put away: the panels look and size as they do over it, the top
  /// one filling up to the settings bar -- see _stackShown.
  List<(_Stacked, double, double, bool)> get _stack => [
        if (_controller.mixerOpen)
          (_Stacked.mixer, _mixerShown, _mixerLeast, _mixerFixed),
        if (_controller.effectsOpen)
          (_Stacked.effects, _effectsHeight, effectsMinHeight, false),
        if (_shown && _keyframesOpen && !_controller.playing)
          (_Stacked.keyframes, keyframeBarHeight, keyframeBarHeight, true),
        if (_timelineShown)
          (
            _Stacked.timeline,
            _timelineHeight,
            _timelineHeight > timelineCollapsedHeight + 0.5
                ? timelineHeight
                : timelineCollapsedHeight,
            false
          ),
      ];

  /// _stackRoom is the room the stacked panels have: everything under the
  /// settings bar, less what has to stay in view -- some of the canvas,
  /// where nothing covers it, or the least of the mixer and effects that
  /// fill its place, with it put away.
  double get _stackRoom {
    var room = math.max(0.0, _pageSeen - _topSeen);
    // Put away, there is no canvas to keep in view.
    if (!_shown) return room;
    var covered = _controller.mixerOpen || _controller.effectsOpen;
    return math.max(0.0, room - (covered ? 0 : canvasLeast));
  }

  /// _fillIndex is the panel that fills the room with the canvas put away:
  /// the topmost mixer or effects that can grow. None with the canvas
  /// shown, or with nothing that can.
  int? _fillIndex(List<(_Stacked, double, double, bool)> stack) {
    if (_shown) return null;
    for (var (k, p) in stack.indexed) {
      if ((p.$1 == _Stacked.mixer || p.$1 == _Stacked.effects) && !p.$4) {
        return k;
      }
    }
    return null;
  }

  /// _stackShown is each stacked panel's height on screen: as set, where
  /// they fit; where not, the top ones made shorter first, each to its
  /// least -- and then the timeline down to its play bar. What was set is
  /// kept, for a window made taller again.
  Map<_Stacked, double> get _stackShown {
    var stack = _stack;
    var set = [for (var p in stack) p.$2];
    if (_pageSeen <= 0) return {for (var p in stack) p.$1: p.$2};
    var t = stack.indexWhere((p) => p.$1 == _Stacked.timeline);
    var room = _stackRoom;
    var out = fitPanels(set, [for (var p in stack) p.$3], room,
        collapsible: t < 0 ? null : t, collapsed: timelineCollapsedHeight);
    // The canvas put away: the top panel takes the rest, up to the bar.
    if (_fillIndex(stack) case var f?) {
      var total = out.fold(0.0, (a, b) => a + b);
      if (total < room) out[f] += room - total;
    }
    return {for (var (k, p) in stack.indexed) p.$1: math.max(0.0, out[k])};
  }

  /// _resizeStacked is [which]'s top edge dragged so it would be [h] tall:
  /// taking free room, then the room of the panels over it -- never past
  /// the settings bar -- and, the stack filling the room, giving what it
  /// gives up to the one over it, so the top stays where it is.
  void _resizeStacked(_Stacked which, double h) => setState(() {
        if (which == _Stacked.mixer && !_mixerPulled(h)) return;
        var shown = _stackShown;
        var stack = _stack;
        var i = stack.indexWhere((p) => p.$1 == which);
        if (i < 0) return;
        if (which == _Stacked.timeline) {
          // Down to the play bar alone: below half way to the strip it
          // snaps shut to the bar, and above, it is at least the strip.
          h = h < (timelineCollapsedHeight + timelineHeight) / 2
              ? timelineCollapsedHeight
              : math.max(h, timelineHeight);
        }
        var heights = [for (var p in stack) shown[p.$1]!];
        var out = resizePanel(
            heights,
            [
              for (var p in stack)
                p.$1 == _Stacked.timeline ? timelineCollapsedHeight : p.$3
            ],
            i,
            h,
            _stackRoom,
            fixed: {
              for (var (k, p) in stack.indexed)
                if (p.$4) k
            });
        var t = stack.indexWhere((p) => p.$1 == _Stacked.timeline);
        // The timeline is the strip or its bar alone, never between.
        if (t >= 0 &&
            out[t] > timelineCollapsedHeight + 0.5 &&
            out[t] < timelineHeight - 0.5) {
          return;
        }
        var prefs = Provider.of<CanvasPreferences>(context, listen: false);
        var fill = _fillIndex(stack);
        for (var (k, p) in stack.indexed) {
          switch (p.$1) {
            // The one filling the room, the canvas put away, is that tall
            // only for as long: what it was set to is kept.
            case _ when k == fill:
              break;
            case _Stacked.mixer when !_mixerFixed:
              _mixerHeight = out[k];
              prefs.mixerHeight = out[k];
            case _Stacked.effects:
              _effectsHeight = out[k];
              prefs.effectsHeight = out[k];
            case _Stacked.timeline:
              _timelineHeight = out[k];
              prefs.timelineHeight = out[k];
            default:
          }
        }
      });

  /// _pull is how far the mixer's edge has been dragged past where it
  /// stops -- down at its least, or up at its smallest -- so a drag has to
  /// mean it before the mixer changes size step.
  double _pull = 0;

  /// _mixerPulled steps the mixer between its sizes as its edge is dragged
  /// to [h]: down past its least to its smallest -- no names, no rail --
  /// and up again; minimised, up out to its least. Whether the drag goes on
  /// to size it.
  bool _mixerPulled(double h) {
    var scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    var least = mixerLeastHeight(_controller, bare: false) * scale;
    if (_controller.mixerSmallest) {
      var smallest = mixerLeastHeight(_controller, bare: true) * scale;
      _pull = h > smallest ? _pull + (h - smallest) : 0;
      if (_pull < 16) return false;
      _pull = 0;
      _controller.mixerSmallest = false;
      _controller.mixerMinimised = true;
      return false;
    }
    if (h < least) {
      _pull += least - h;
      if (_pull < 24) return _controller.mixerMinimised ? false : true;
      _pull = 0;
      _controller.mixerMinimised = true;
      _controller.mixerSmallest = true;
      return false;
    }
    _pull = 0;
    if (_controller.mixerMinimised) {
      // Minimised, a drag up opens it out again from its least.
      if (h <= least + 2) return false;
      _controller.mixerMinimised = false;
      _mixerHeight = least;
    }
    return true;
  }

  /// _effectsHeight is the effects panel's, which sits over the mixer.
  double _effectsHeight = effectsDefaultHeight;

  /// _viewKey is the canvas whose view -- see CanvasController.canvasView --
  /// is being kept, by its folder and name; null for one never saved.
  String? _viewKey;
  bool _viewKeyKnown = false;
  Timer? _keepTimer;

  String? get _canvasKey => _controller.name == null
      ? null
      : "${_controller.folder ?? ""}/${_controller.name}";

  /// _keepPanels keeps how the panels were left -- see panelState and
  /// canvasView -- a moment after they change: not on every change, which
  /// while playing is every frame. Another canvas opened, its own view is
  /// put back, the last one's kept first.
  void _keepPanels() {
    var key = _canvasKey;
    if (!_viewKeyKnown || key != _viewKey) {
      if (_viewKeyKnown) _savePanels();
      _viewKeyKnown = true;
      _viewKey = key;
      // As it was left -- or, one never looked at, as it starts: not the
      // last canvas's channels and zoom. After this change has been told:
      // putting it back tells again.
      var view = key == null ? null : _prefs.canvasView(key);
      scheduleMicrotask(() {
        if (mounted && _canvasKey == key) {
          _controller.restoreCanvasView(view ?? const {});
        }
      });
      return;
    }
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
    prefs.keyframesShown = _controller.keyframesShown;
    prefs.scenesShown = _controller.scenesShown;
    prefs.cuesShown = _controller.cuesShown;
    // And the mixer's bands -- C, D, M -- and its returns, R: set up once.
    prefs.mixerBands = _controller.mixerBandNames;
    prefs.returnsShown = _controller.returnsShown;
  }

  @override
  void initState() {
    super.initState();
    // A MIDI keyboard plays this canvas's instruments while it is open.
    MidiInput.shared.onNote = _controller.midiNote;
    MidiInput.shared.onSustain = _controller.sustain;
    MidiInput.shared.onControl = _controller.midiControl;
    MidiInput.shared.onPlay = _controller.togglePlay;
    MidiInput.shared.onRecord =
        () => _controller.recording = !_controller.recording;
    // A Push's Session mode: its pads the clip slots.
    MidiInput.shared.onClip = _controller.pushClip;
    MidiInput.shared.clipAt = _controller.pushPad;
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    // Nought is never set: the strip as it starts. Anything under the strip
    // is the play bar alone, as it was left.
    var kept = prefs.timelineHeight;
    _timelineHeight = kept <= 0
        ? timelineHeight
        : kept < timelineHeight
            ? timelineCollapsedHeight
            : kept;
    var at = prefs.panel;
    _panel = at >= 0 && at < CanvasPanel.values.length
        ? CanvasPanel.values[at]
        : CanvasPanel.files;
    // The Game panel only for a game.
    if (_panel == CanvasPanel.game && !_controller.document.game) {
      _panel = CanvasPanel.design;
    }
    // Returning to a page that was left on Design counts as having used it:
    // the reader chose that tab, even if it was last time.
    _designUsed = _panel == CanvasPanel.design;
    // The one it opens on is the only one worth building to begin with.
    _seen.add(_panel);
    _timelineOpen = prefs.timeline;
    // Only on the very first visit of the session. After that the controller
    // already holds whatever was being worked on, and reopening the last saved
    // file over the top would throw away the unsaved edits this whole
    // arrangement exists to keep.
    // The frame the reader last chose, before anything is drawn. It belongs
    // to them rather than to the document -- see CanvasPreferences.fit -- so
    // it survives opening a different canvas.
    //
    // restoreFit rather than the setter, because the setter notifies and this
    // runs inside initState: notifying a controller that a Provider is handing
    // round marks an inherited widget dirty mid-build, and Flutter answers
    // that with an exception whose stack is four hundred frames long.
    for (var fit in CanvasFit.values) {
      if (fit.name == prefs.fit) _controller.restoreFit(fit);
    }
    _controller.restoreShown(
        keyframes: prefs.keyframesShown,
        scenes: prefs.scenesShown,
        cues: prefs.cuesShown);
    // The mixer as it was left: its bands, its returns, its height and the
    // effects panel's.
    _controller.restoreMixer(prefs.mixerBands, prefs.returnsShown);
    if (prefs.mixerHeight > 0) _mixerHeight = prefs.mixerHeight;
    if (prefs.effectsHeight > 0) _effectsHeight = prefs.effectsHeight;
    // And the rest of how the panels were left, on the first visit of the
    // session -- after it, the controller already holds it.
    if (!_controller.opened) _controller.restorePanels(prefs.panels);
    if (!_controller.opened) _reopenLast(prefs);
    _controller.markOpened();
    _controller.addListener(_onSelectionChanged);
    _gameSeen = _controller.document.game;
    _controller.addListener(_followGame);
    _controller.addListener(_keepShown);
    _controller.addListener(_pushScale);
    _controller.addListener(_keepPanels);
    _keepPanels();
    // A text element can take its words from the Writing library, and the
    // library is edited somewhere else entirely -- so while this page is open
    // the documents behind those elements are read every few seconds. A
    // canvas with none does no work. See TextDocumentWatch.
    _documents = TextDocumentWatch(_controller)..start();
  }

  /// _reopenLast puts back whatever was open when the page was last left.
  ///
  /// Failing quietly is right here. The file may have been deleted, renamed or
  /// moved since; an empty canvas is a perfectly good place to start, and an
  /// error about a document the reader has not asked for yet would be noise.
  Future<void> _reopenLast(CanvasPreferences prefs) async {
    if (prefs.lastName.isEmpty) return;
    var document = await CanvasStorage.load(prefs.lastFolder, prefs.lastName);
    if (!mounted || document == null) return;
    _controller.load(document, folder: prefs.lastFolder, name: prefs.lastName);
  }

  /// _onSelectionChanged redraws the screen only when the *selection* moves.
  ///
  /// The controller notifies on every keystroke of every edit, and the screen
  /// itself shows almost nothing that depends on the document -- the stage,
  /// the band and the timeline all listen for themselves. Rebuilding it for
  /// each of those would be work done for nothing.
  void _onSelectionChanged() {
    // Whatever the frame has ended up as, written down. The buttons that
    // change it are on the band and talk to the controller directly, so this
    // is the one place that sees every way it can change -- including the
    // keyboard and anything added later.
    var prefs = Provider.of<CanvasPreferences>(context, listen: false);
    if (prefs.fit != _controller.fit.name) prefs.fit = _controller.fit.name;

    var next = _controller.backgroundSelected
        ? "background"
        : (_controller.selection.toList()..sort()).join(",");
    if (next == _selectionRevision) return;
    if (!mounted) return;

    // Choosing something on the canvas is asking about it, and its settings
    // are on the Design tab. Selecting an element and then having to find the
    // tab that says anything about it is a step nobody wants twice.
    //
    // Only when something has actually been chosen: clearing the selection
    // must not drag the reader away from the file list they just came to.
    //
    // And only once the reader has been to Design themselves this session.
    // Somebody arranging their files, or reading through the presets, is
    // doing something on purpose, and having the sidebar jump elsewhere the
    // first time they touch the canvas is the page overruling them.
    var chose = next.isNotEmpty && next != _selectionRevision;
    setState(() => _selectionRevision = next);
    // Not from the Game panel, which shows what is chosen too: its game
    // settings.
    if (chose &&
        _designUsed &&
        _panel != CanvasPanel.design &&
        _panel != CanvasPanel.game) {
      _setPanel(CanvasPanel.design);
    }
  }

  /// _gameSeen is whether the canvas was a game when last looked at.
  bool _gameSeen = false;

  /// _followGame opens the Game panel as the canvas is made into a game --
  /// the Make game button in the bar -- and goes back to Design as it stops
  /// being one, the Game panel gone.
  void _followGame() {
    var game = _controller.document.game;
    if (game == _gameSeen || !mounted) return;
    _gameSeen = game;
    if (game) {
      _setPanel(CanvasPanel.game);
    } else if (_panel == CanvasPanel.game) {
      _setPanel(CanvasPanel.design);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (MidiInput.shared.onNote == _controller.midiNote) {
      MidiInput.shared.onNote = null;
      MidiInput.shared.onSustain = null;
      MidiInput.shared.onControl = null;
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
    _keepTimer?.cancel();
    _savePanels();
    // The canvas's sounds stop when the canvas is left. The session goes on
    // -- see below -- but music from a page nobody is looking at, carrying on
    // under a chat, is a sound with no off switch on screen.
    //
    // Just after this frame rather than in it: stopping them tells everything
    // watching the canvas, and some of what watches it is being taken down in
    // this same frame, with the tree locked -- a notification then is an
    // exception, which leaving the page for the chat threw every time a sound
    // had been loaded.
    var controller = _controller;
    scheduleMicrotask(controller.stopAudio);
    // Not disposed: the session outlives this page. The provider owns it, and
    // disposing it here would leave a dead controller behind for the next
    // visit to read.
    super.dispose();
  }

  /// _documents re-reads the Writing library documents this canvas draws.
  TextDocumentWatch? _documents;

  /// _designUsed is whether the Design tab has been opened this session.
  ///
  /// What gates the automatic switch to it -- see _onSelectionChanged. However
  /// it was reached counts: choosing the tab, or being taken there by starting
  /// a canvas, both mean the reader knows the tab is there and is working in
  /// it.
  bool _designUsed = false;

  void _setPanel(CanvasPanel panel) {
    if (panel == CanvasPanel.design) _designUsed = true;
    setState(() {
      _panel = panel;
      // Built from here on, and kept built. See _seen.
      _seen.add(panel);
    });
    Provider.of<CanvasPreferences>(context, listen: false).panel = panel.index;
  }

  /// _confirmDiscard keeps unsaved work, and asks only where it cannot.
  ///
  /// Called before opening a different canvas and before starting from a
  /// preset, which are the two ways to lose one.
  ///
  /// A canvas with a file of its own is saved rather than asked about. It
  /// writes itself out three seconds after the editing stops -- see
  /// CanvasController.scheduleAutosave -- so the only way to see the question
  /// was to move between canvases inside those three seconds, which is
  /// exactly what somebody arranging a document does all afternoon. Asking
  /// then is asking whether to throw away work nobody meant to throw away,
  /// and the honest answer is always no: there is somewhere to put it, so it
  /// goes there.
  ///
  /// What is left is a canvas that has never been saved -- started from a
  /// preset, or from nothing. That one has nowhere to be written to, and
  /// walking away from it really does lose it, so it is still worth a
  /// question. A save that fails falls back to the question too, because
  /// then there is no longer somewhere to put it.
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

  /// _newCanvas starts an empty one, already filed under [name].
  ///
  /// Saved immediately rather than left in the air, which is what lets the
  /// Files panel do without a Save button: a canvas with a file behind it
  /// saves itself from then on -- see CanvasController.scheduleAutosave.
  Future<void> _newCanvas(String folder, String name) async {
    var snackbar = SnackBarModel.of(context);
    if (!await _confirmDiscard()) return;

    // The empty preset rather than a bare CanvasDocument, so that a new
    // canvas made here and one started from the Presets tab's "Empty canvas"
    // are the same thing. Two kinds of empty is one too many.
    _controller.load(emptyCanvas().copyWith(title: name));
    var saved = await _controller.saveAs(folder, name);
    if (!mounted) return;
    if (!saved) {
      snackbar.error("Unable to make $name.");
      return;
    }
    Provider.of<CanvasPreferences>(context, listen: false)
        .remember(folder, name);
    // Straight to the elements tab, as a preset does: the next thing anybody
    // does with an empty canvas is put something on it.
    _setPanel(CanvasPanel.design);
    _openCanvasSettings();
  }

  /// _openCanvasSettings puts the canvas settings line out.
  ///
  /// For a canvas that is starting from nothing: the shape of the page and
  /// the width it exports at are decided once, before anything is put on it,
  /// and a blank canvas that opens with them already showing is the whole
  /// invitation to decide them. On a canvas that has something on it they are
  /// set, which is why the line is otherwise shut.
  void _openCanvasSettings() {
    if (!mounted) return;
    setState(() {
      _canvasSettingsOpen = true;
      // The two lines open in the same place.
      _guidesOpen = false;
    });
  }

  /// _openPreset starts a new canvas from a preset.
  ///
  /// The document is handed in already built rather than built here, so the
  /// panel's preview and the working copy are separate objects -- editing the
  /// new canvas must not change the thumbnail beside it.
  Future<void> _openPreset(
      CanvasPreset? preset, CanvasDocument document) async {
    if (!await _confirmDiscard()) return;
    _controller.load(document);
    if (mounted) {
      Provider.of<CanvasPreferences>(context, listen: false).remember("", "");
      // Straight to the elements tab, because the next thing anybody does
      // after choosing a starting point is add something to it.
      _setPanel(CanvasPanel.design);
      // Only the empty preset, which is the same thing as New: every other
      // preset arrives with its shape already chosen on purpose, and the
      // line would be covering the thing it was chosen for.
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
    var confirmed = await askToConfirm(context,
        title: "Open this link?", message: url, confirm: "Open");
    if (!confirmed) return;
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

    // Space plays and stops from anywhere on this page -- see CanvasSpaceBar.
    var content = CanvasSpaceBar(
        controller: _controller,
        child: contentAreaFrame(theme, _content(theme)));

    // Hidden means nothing beside the canvas. Not routed through
    // SecondarySideMenuLayout at all, since that would put its own sidebar back
    // where the panel had been -- which made the hide button look as though it
    // had merely closed the panel it was on. The Writing page does the same.
    if (!_sidebarVisible) return ScreenWithChatSideMenu(client, content);

    var sidebar = CanvasSidebarShell(
      panel: _panel,
      panels: [
        for (var p in CanvasPanel.values)
          if (p != CanvasPanel.game || _controller.document.game) p,
      ],
      onPanelChanged: _setPanel,
      onHide: () => setState(() => _sidebarVisible = false),
      // Every panel that has been looked at is kept, and only the chosen one
      // is shown.
      //
      // Offstage rather than a switch that builds one and throws the others
      // away. Building the design column from cold is a hundred and thirty
      // milliseconds -- three panels of controls, every text field with its
      // own state, its own focus node, its own editing controller -- and
      // paying that on every tab press is the delay you feel switching back
      // and forth. Offstage keeps the state and skips the layout and the
      // painting, so a hidden panel costs nothing per frame and comes back
      // instantly.
      //
      // Kept, but not built before it is wanted: offstage skips the layout
      // and the painting and not the building, so opening the page at all
      // paid for all three columns -- four hundred milliseconds of text
      // fields, most of them for panels nobody had asked for. See _seen.
      child: Stack(
        children: [
          for (var panel in CanvasPanel.values)
            if (_seen.contains(panel))
              Offstage(
                offstage: _panel != panel,
                child: TickerMode(
                  // Nothing hidden should be animating: an offstage panel with
                  // a spinner in it would go on scheduling frames for something
                  // nobody can see.
                  enabled: _panel == panel,
                  child: switch (panel) {
                    CanvasPanel.files => CanvasFilesPanel(
                        controller: _controller,
                        onOpen: _open,
                        onPublish: _publishSaved,
                        onNew: _newCanvas,
                        showing: _panel == CanvasPanel.files,
                      ),
                    CanvasPanel.presets => CanvasPresetsSidebar(
                        controller: _controller,
                        onChoose: _openPreset,
                      ),
                    CanvasPanel.design =>
                      CanvasDesignPanel(controller: _controller),
                    CanvasPanel.assets =>
                      CanvasAssetsPanel(controller: _controller),
                    CanvasPanel.game =>
                      CanvasGamePanel(controller: _controller),
                  },
                ),
              ),
        ],
      ),
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

  /// _topSeen and _pageSeen are the heights of the band with the strip under
  /// it, and of the whole page, when last laid out -- for the timeline to fit
  /// between. See _Measured.
  ///
  /// Reported by the page as it is laid out, not asked of a LayoutBuilder or
  /// read through GlobalKeys: the sidebar's own LayoutBuilder moves this
  /// page about, and a page rebuilt, or keyed and woken, in the middle of
  /// that took its tooltips with it -- which is not allowed there, and the
  /// page went red.
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

  /// _canvasAway is what is in the canvas's room while it is put away:
  /// behind the panels, which fill it as they do over the canvas -- or, with
  /// neither the mixer nor the effects open, a word on where they are and
  /// the way back.
  Widget _canvasAway(ThemeNotifier theme) => ColoredBox(
        key: const ValueKey("canvasAway"),
        color: theme.colors.surface,
        child: _controller.mixerOpen || _controller.effectsOpen
            ? const SizedBox.expand()
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_noCanvas ? "A piece of sound" : "The canvas is hidden",
                      style: TextStyle(color: theme.colors.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text("Open the mixer or the effects from the timeline.",
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

  Widget _content(ThemeNotifier theme) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          var shown = _stackShown;
          var timelineShown = shown[_Stacked.timeline] ?? _timelineHeight;
          return _Measured(
              onHeight: (h) => _measured(page: h),
              child: Column(children: [
                _Measured(
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
                        // Only while the sidebar is away. The band is where every other
                        // control on this page lives, so the one that brings the sidebar
                        // back belongs in it rather than floating on the page behind it.
                        onShowSidebar: _sidebarVisible
                            ? null
                            : () => setState(() => _sidebarVisible = true),
                      ),
                      ...canvasSecondLine(
                        settings: _canvasSettingsOpen
                            ? CanvasSettingsPanel(controller: _controller)
                            : null,
                        guides: _guidesOpen
                            ? CanvasGuidesPanel(controller: _controller)
                            : null,
                      ),
                    ])),
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(
                      // Put away rather than taken out: Offstage keeps the
                      // stage's state and stops it painting and being hit.
                      child: Offstage(
                        offstage: !_shown,
                        // The whole canvas area is a drop target, so an element
                        // dragged out of the sidebar lands where it was let go rather
                        // than in the middle of the page.
                        child: DragTarget<ElementKind>(
                          onAcceptWithDetails: (details) {
                            var stage = _stageKey.currentState;
                            var box =
                                _stageKey.currentContext?.findRenderObject();
                            if (stage == null || box is! RenderBox) return;
                            var local = box.globalToLocal(details.offset);
                            _controller.addElement(newElement(
                              details.data,
                              _controller.document,
                              center: stage.toDocumentPoint(local),
                            ));
                          },
                          builder: (context, candidate, rejected) =>
                              // And an asset from the Assets sidebar, which becomes the
                              // element that shows it, where it was let go.
                              // Or a stock result, fetched when it lands.
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
                              // A model let go on a character is that
                              // character's body now, not a second character.
                              if (asset.kind == AssetKind.model) {
                                var doc = _controller.document;
                                var on = doc.elements.reversed
                                    .whereType<CharacterElement>()
                                    .where((c) =>
                                        !c.locked &&
                                        visualBoundsOf(
                                                c, doc, _controller.frame)
                                            .contains(center))
                                    .firstOrNull;
                                if (on != null) {
                                  _controller.beginInteraction();
                                  _controller.replaceElement(on.copyWith(
                                      body: on.body.copyWith(
                                          kind: BodyKind.model,
                                          modelId: asset.id,
                                          modelName: asset.name)));
                                  _controller.endInteraction();
                                  _controller.selectOnly(on.id);
                                  return;
                                }
                              }
                              _controller.addElement(elementForAsset(
                                asset,
                                _controller.document,
                                center: center,
                              ));
                            },
                            builder: (context, assets, _) => Container(
                              color: candidate.isEmpty && assets.isEmpty
                                  ? null
                                  : theme.colors.primary
                                      .withValues(alpha: 0.06),
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
                    if (!_shown) Positioned.fill(child: _canvasAway(theme)),
                    // The tool in hand on a picture, and what to do with it, over
                    // the top of the canvas where the eye is -- see
                    // image_tool_hint.dart.
                    if (_shown)
                      Positioned(
                        top: 10,
                        left: 16,
                        right: 16,
                        // A drawing's as well: only one is ever being edited.
                        child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              ImageToolHint(controller: _controller),
                              // A sketched character's: going round it, its
                              // panels, the zoom and the drawing tools.
                              CharacterDrawBar(controller: _controller),
                              VectorToolHint(controller: _controller),
                            ])),
                      ),
                    // The pose bar still sits over the design rather than pushing
                    // it: it is opened while watching an animation, where a shift
                    // in the middle of playback is exactly what nobody wants, and
                    // it hangs off the bottom edge rather than the top -- which is
                    // not the edge anybody is working against.
                    if (_shown && _keyframesOpen && !_controller.playing)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: CanvasKeyframeBar(controller: _controller),
                      ),
                    // Above the pose bar when both are out, and up while playing,
                    // unlike the pose bar: watching the clips go by under the
                    // playhead is half of what it is for.
                    // The mixer over the effects of one of its strips, the
                    // effects at the bottom -- so a strip and the chain it
                    // opens read top to bottom. Each is resized by the grip
                    // along its own top.
                    if (_controller.effectsOpen)
                      Positioned(
                        bottom: _shown && _keyframesOpen && !_controller.playing
                            ? keyframeBarHeight
                            : 0,
                        left: 0,
                        right: 0,
                        child: CanvasMixer.effects(
                          controller: _controller,
                          height: shown[_Stacked.effects] ?? _effectsHeight,
                          onResize: (h) => _resizeStacked(_Stacked.effects, h),
                          onClose: () => _controller.effectsOpen = false,
                        ),
                      ),
                    if (_controller.mixerOpen)
                      Positioned(
                        bottom:
                            (_shown && _keyframesOpen && !_controller.playing
                                    ? keyframeBarHeight
                                    : 0) +
                                (_controller.effectsOpen
                                    ? shown[_Stacked.effects] ?? _effectsHeight
                                    : 0),
                        left: 0,
                        right: 0,
                        child: CanvasMixer(
                          controller: _controller,
                          height: shown[_Stacked.mixer] ?? _mixerShown,
                          onResize: (h) => _resizeStacked(_Stacked.mixer, h),
                          onClose: () => _controller.mixerOpen = false,
                        ),
                      ),
                  ]),
                ),
                // Hidden by taking it out rather than by shrinking it to nothing:
                // the transport holds a focus node and a ticker, and a strip of no
                // height that still answers the keyboard is worse than no strip.
                if (_timelineShown)
                  CanvasTimeline(
                    controller: _controller,
                    keyframesOpen: _keyframesOpen,
                    onToggleKeyframes: () =>
                        setState(() => _keyframesOpen = !_keyframesOpen),
                    height: timelineShown,
                    // With the mixer and the effects, one stack under the
                    // settings bar: see _resizeStacked.
                    onResize: (h) => _resizeStacked(_Stacked.timeline, h),
                    // One line at a time: two strips over the same corner of the
                    // canvas would be one on top of the other.
                  ),
              ]));
        },
      );

  /// _seen is which panels have been looked at, and so which of them are
  /// worth keeping built.
  ///
  /// A panel is added the first time it is chosen and never removed: the
  /// point of keeping them is that going back to one is instant, and what
  /// that costs is one column's worth of controls for each panel somebody
  /// has actually used.
  final Set<CanvasPanel> _seen = {};

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

/// _Stacked is one of the panels stacked under the canvas. See _stack.
enum _Stacked { mixer, effects, keyframes, timeline }

/// canvasLeast is the least of the canvas kept in view when the window is
/// short: the timeline gives way rather than pushing it out.
const double canvasLeast = 120;

/// canvasSecondLine is the strip that opens under the band: the canvas
/// settings, or the grid and guides.
///
/// Above the canvas rather than over it, so it pushes the design down instead
/// of covering the top of it.
///
/// It used to sit over the canvas, on the grounds that opening the settings
/// should not move what is being looked at -- and in Fit whole the height is
/// part of the scale, so the design does shift when this opens. That is the
/// lesser cost: covering the top edge hides the part of the canvas most
/// likely to be worked on while the settings that do the work are open. The
/// timeline at the bottom of the same column has always pushed rather than
/// covered.
///
/// A function of its own, and returning a list rather than a widget, so that
/// where it sits in the column is a thing a test can look at -- which is the
/// whole of what this decides.
List<Widget> canvasSecondLine({Widget? settings, Widget? guides}) => [
      if (settings != null) settings,
      // Never both at once, which the two toggles see to; if one ever gets
      // through, the settings win rather than two strips stacking.
      if (settings == null && guides != null) guides,
    ];

/// _Measured tells [onHeight] its child's height whenever layout changes it
/// -- after the frame, so the change is a build of its own, not one in the
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
