import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/mixer_layout.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/storage_manager.dart';

/// _Saved is one value kept in the app's preferences: its key, what it is
/// until something is saved, and how it is stored.
///
/// To add a preference to [CanvasPreferences], declare one of these, give it
/// a getter and a setter that calls [CanvasPreferences._change], and add it
/// to [CanvasPreferences._saved] so that it is loaded.
abstract class _Saved<T> {
  final String key;
  T value;
  _Saved(this.key, this.value);

  /// load reads the stored value, leaving [value] alone when there is none
  /// or it cannot be read.
  Future<void> load();

  /// store writes [value].
  void store();

  /// holds is whether [other] is the value already, so setting it would
  /// change nothing.
  bool holds(T other) => value == other;
}

/// _SavedBool is a switch, stored as a bool.
class _SavedBool extends _Saved<bool> {
  _SavedBool(super.key, super.value);

  @override
  Future<void> load() async =>
      value = await StorageManager.readBool(key, defaultVal: value);

  @override
  void store() => StorageManager.saveBool(key, value);
}

/// _SavedText is a value stored as a string that [write] makes and [read]
/// turns back. A string [read] returns null for, or throws on, is ignored.
class _SavedText<T> extends _Saved<T> {
  final T? Function(String text) read;
  final String Function(T value) write;

  /// byText is for a value with no == of its own (a list, a map, a layout
  /// made new each time): it is the same when it would be written the same.
  final bool byText;

  _SavedText(super.key, super.value,
      {required this.read, required this.write, this.byText = false});

  /// A plain string.
  static _SavedText<String> string(String key) =>
      _SavedText(key, "", read: (t) => t, write: (v) => v);

  /// A size in logical pixels, nought until it is first set.
  static _SavedText<double> size(String key) => _SavedText(key, 0,
      read: double.tryParse, write: (v) => v.toStringAsFixed(1));

  /// A value stored as JSON, which [fromJson] reads from what was decoded.
  static _SavedText<T> json<T>(String key, T value,
          {required T? Function(Object? json) fromJson,
          required Object? Function(T value) toJson}) =>
      _SavedText(key, value,
          read: (t) => fromJson(jsonDecode(t)),
          write: (v) => jsonEncode(toJson(v)),
          byText: true);

  @override
  Future<void> load() async {
    var text = await StorageManager.readString(key);
    if (text.isEmpty) return;
    try {
      value = read(text) ?? value;
    } catch (_) {
      // Unreadable: the value it starts with.
    }
  }

  @override
  void store() => StorageManager.saveString(key, write(value));

  @override
  bool holds(T other) => byText ? write(value) == write(other) : value == other;
}

/// _jsonMap is [json] if it is a JSON object, else null.
Map<String, dynamic>? _jsonMap(Object? json) =>
    json is Map<String, dynamic> ? Map.unmodifiable(json) : null;

/// CanvasPreferences is what the person using the app has decided about the
/// Canvas: whether the feature is there at all, and how the editor was left
/// (the canvas last open, which panels show and how big). It is about the
/// app on this machine; anything about one canvas is saved in that canvas.
///
/// The feature is off by default: it costs a place in the menu most people
/// will never use. It is a preference and not a plugin capability because
/// the Canvas uses no plugin service.
///
/// A setter notifies only when something outside the editor must rebuild:
/// the menu, the Settings page, the app's frame round the page. The others
/// are set by a widget that has already redrawn itself, and a notification
/// would rebuild the whole page under it.
class CanvasPreferences extends ChangeNotifier {
  static const _allowFetchingKey = "canvasAllowFetching";

  final _enabled = _SavedBool("canvasEnabled", false);
  final _allowFetching = _SavedBool(_allowFetchingKey, false);
  final _menuHidden = _SavedBool("canvasMenuHidden", false);
  final _lastFolder = _SavedText.string("canvasLastFolder");
  final _lastName = _SavedText.string("canvasLastName");
  final _filesFolder = _SavedText.string("canvasFilesFolder");
  final _fit = _SavedText<CanvasFit>("canvasFit", CanvasFit.whole,
      read: (t) => CanvasFit.values.where((f) => f.name == t).firstOrNull,
      write: (v) => v.name);
  final _rulers = _SavedText.json<CanvasRulers>(
      "canvasRulers", const CanvasRulers(),
      fromJson: (json) =>
          json is Map<String, dynamic> ? CanvasRulers.fromJson(json) : null,
      toJson: (v) => v.toJson());
  final _canvasViews =
      _SavedText.json<Map<String, Map<String, dynamic>>>("canvasViews", {},
          fromJson: (json) => json is! Map<String, dynamic>
              ? null
              : {
                  for (var e in json.entries)
                    if (e.value is Map<String, dynamic>)
                      e.key: e.value as Map<String, dynamic>,
                },
          toJson: (v) => v);
  final _sidebars = _SavedText.json<SidebarLayout>(
      "canvasSidebars", const SidebarLayout(),
      fromJson: SidebarLayout.fromJson, toJson: (v) => v.toJson());
  final _sidebarAboveWidth = _SavedText.size("canvasSidebarAboveWidth");
  final _dock = _SavedText<DockLayout>("canvasDock", const DockLayout(),
      read: (t) => DockLayout.fromJson(jsonDecode(t)),
      write: (v) => jsonEncode(v.toJson()));
  final _dockLower = _SavedText.size("canvasDockLower");
  final _dockAbove = _SavedText.size("canvasDockAbove");
  final _dockLeft = _SavedText.size("canvasDockLeft");
  final _panels = _SavedText.json<Map<String, dynamic>>(
      "canvasPanels", const {},
      fromJson: _jsonMap, toJson: (v) => v);
  final _timeline = _SavedBool("canvasTimeline", false);
  final _cuesShown = _SavedBool("canvasCuesShown", true);
  final _mixerLayout = _SavedText.json<MixerLayout>(
      "canvasMixerLayout", MixerLayout(),
      fromJson: MixerLayout.fromJson, toJson: (v) => v.toJson());
  final _timelineSnap = _SavedBool("canvasTimelineSnap", false);
  final _timelineTrackpad = _SavedBool("canvasTimelineTrackpad", false);
  final _barBelow = _SavedBool("canvasTimelineBarBelow", false);
  final _studioLook = _SavedText<StudioLook>(
      "canvasStudioLook", StudioLook.studio,
      read: StudioLook.fromName, write: (v) => v.name);
  final _studioOverrides = _SavedText.json<Map<StudioRole, Color>>(
      "canvasStudioColours", const {},
      fromJson: (json) => json is! Map
          ? null
          : Map.unmodifiable({
              for (var role in StudioRole.values)
                if (json[role.name] is num)
                  role: colorFromJson(json[role.name]),
            }),
      toJson: (v) =>
          {for (var e in v.entries) e.key.name: colorToJson(e.value)});
  final _publish = _SavedText.json<Map<String, dynamic>>(
      "canvasPublish", const {},
      fromJson: _jsonMap, toJson: (v) => v);
  final _assetViews =
      _SavedText.json<Map<AssetKind, AssetView>>("canvasAssetViews", const {},
          fromJson: (json) => json is! Map
              ? null
              : Map.unmodifiable({
                  for (var kind in AssetKind.values)
                    if (AssetView.values.asNameMap()[json[kind.name]]
                        case var view?)
                      kind: view,
                }),
          toJson: (v) => {for (var e in v.entries) e.key.name: e.value.name});
  final _stockLibrary = _SavedText<StockLibrary>(
      "canvasStockLibrary", StockLibrary.initial,
      read: StockLibrary.fromName, write: (v) => v.name);
  final _stockFilters = _SavedText.json<Map<StockSource, Map<String, String>>>(
      "canvasStockFilters", const {},
      fromJson: (json) => json is! Map
          ? null
          : Map.unmodifiable({
              for (var e in json.entries)
                // A source this build does not know is passed by, not read as
                // the default one, whose own filters it would overwrite.
                if ((StockSource.values.asNameMap()[e.key], e.value)
                    case (var source?, Map chosen))
                  source: Map<String, String>.unmodifiable({
                    for (var f in chosen.entries) "${f.key}": "${f.value}",
                  }),
            }),
      toJson: (v) => {for (var e in v.entries) e.key.name: e.value});

  /// _saved is every value above, which is what [load] reads. [_change]
  /// refuses one that is missing, so a test that sets it says so.
  late final List<_Saved<Object?>> _saved = [
    _enabled,
    _allowFetching,
    _menuHidden,
    _lastFolder,
    _lastName,
    _filesFolder,
    _fit,
    _rulers,
    _canvasViews,
    _sidebars,
    _sidebarAboveWidth,
    _dock,
    _dockLower,
    _dockAbove,
    _dockLeft,
    _panels,
    _timeline,
    _cuesShown,
    _mixerLayout,
    _timelineSnap,
    _timelineTrackpad,
    _barBelow,
    _studioLook,
    _studioOverrides,
    _publish,
    _assetViews,
    _stockLibrary,
    _stockFilters,
  ];

  /// load reads what was saved, once at startup; until then every value is
  /// the one it starts with.
  Future<void> load() async {
    for (var saved in _saved) {
      await saved.load();
    }
    notifyListeners();
  }

  /// _change gives [saved] a new value and stores it, unless it holds that
  /// value already.
  ///
  /// [soon] stores it once it has stopped changing for a moment, for a size
  /// set at every step of a drag: each write is a round trip to the
  /// platform's preferences. [notify] is for the few that something outside
  /// the editor shows (see the class's note).
  void _change<T>(_Saved<T> saved, T value,
      {bool notify = false, bool soon = false}) {
    assert(
        _saved.contains(saved),
        "add ${saved.key} to _saved, or it is "
        "never loaded");
    if (saved.holds(value)) return;
    saved.value = value;
    if (soon) {
      _unstored.add(saved);
      _storeTimer?.cancel();
      _storeTimer = Timer(const Duration(milliseconds: 400), _storeNow);
    } else {
      saved.store();
    }
    if (notify) notifyListeners();
  }

  /// _unstored is the values changed with `soon` and not yet written.
  final Set<_Saved<Object?>> _unstored = {};
  Timer? _storeTimer;

  void _storeNow() {
    _storeTimer?.cancel();
    _storeTimer = null;
    for (var saved in _unstored) {
      saved.store();
    }
    _unstored.clear();
  }

  @override
  void dispose() {
    _storeNow();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // The feature and what it may do
  // --------------------------------------------------------------------------

  /// enabled is whether the Canvas section exists.
  bool get enabled => _enabled.value;
  set enabled(bool value) => _change(_enabled, value, notify: true);

  /// allowFetching is whether a table or a chart may fetch its data over the
  /// internet. Off by default for privacy: the fetch does not go through the
  /// daemon, so the proxy setting (Tor, say) does not apply and the address
  /// learns who is asking. A file source does the same job offline.
  bool get allowFetching => _allowFetching.value;

  /// allowFetchingLabel is what the switch is called in Settings, for the
  /// places that send a person there to turn it on.
  static const allowFetchingLabel = "Let a canvas fetch data";
  set allowFetching(bool value) => _change(_allowFetching, value, notify: true);

  /// fetchingAllowed is [allowFetching] as saved, for callers with no
  /// preferences to hand (a character drawn on the stage).
  static Future<bool> fetchingAllowed() =>
      StorageManager.readBool(_allowFetchingKey, defaultVal: false);

  /// menuHidden is whether the app's sidebar and header are put away while
  /// the canvas is open. The Bison Relay logo toggles it.
  bool get menuHidden => _menuHidden.value;
  set menuHidden(bool value) => _change(_menuHidden, value, notify: true);

  // --------------------------------------------------------------------------
  // The canvas that was open, and how it was looked at
  // --------------------------------------------------------------------------

  /// lastFolder and lastName are the canvas last open, reopened on return.
  /// Set them with [remember].
  String get lastFolder => _lastFolder.value;
  String get lastName => _lastName.value;

  /// remember records which canvas is open, so it can be reopened next time.
  void remember(String folder, String name) {
    _change(_lastFolder, folder);
    _change(_lastName, name);
  }

  /// pendingOpen is a canvas to open the next time the Canvas page shows,
  /// such as one opened from Files. Not saved.
  (String folder, String name)? pendingOpen;

  /// filesFolder is the folder the Files panel is looking at, kept between
  /// visits as the writing library does. Cleared when the folder has gone.
  String get filesFolder => _filesFolder.value;
  set filesFolder(String value) => _change(_filesFolder, value);

  /// fit is how the canvas is framed: the whole of it, or the full width.
  /// A preference because it is about this screen, not the canvas. Stored
  /// by name, so reordering the fits does not change a saved one.
  CanvasFit get fit => _fit.value;
  set fit(CanvasFit value) => _change(_fit, value);

  /// rulers is which edges of the stage carry a ruler and whether they
  /// show. A preference, not part of a canvas, so a canvas sent to somebody
  /// opens with their rulers rather than its sender's. The page hands it to
  /// the controller and keeps it (KeptView).
  CanvasRulers get rulers => _rulers.value;
  set rulers(CanvasRulers value) => _change(_rulers, value);

  /// canvasView is how the canvas saved as [key] ("folder/name") was last
  /// looked at. See CanvasController.canvasView.
  Map<String, dynamic>? canvasView(String key) => _canvasViews.value[key];

  /// _viewsKept is how many canvases' views are kept: the latest looked at.
  static const _viewsKept = 40;

  void setCanvasView(String key, Map<String, dynamic> view) {
    var views = {..._canvasViews.value};
    // Put in again at the end, so the map runs oldest first and the oldest
    // are the ones dropped.
    views.remove(key);
    views[key] = view;
    while (views.length > _viewsKept) {
      views.remove(views.keys.first);
    }
    _change(_canvasViews, views);
  }

  // --------------------------------------------------------------------------
  // The sidebar and the panels under the canvas
  // --------------------------------------------------------------------------

  /// sidebars is how the sidebar is set out: shown or not and how, its
  /// sidebars and their panels. See sidebar_layout.dart.
  SidebarLayout get sidebars => _sidebars.value;
  set sidebars(SidebarLayout value) => _change(_sidebars, value);

  /// sidebarAboveWidth is how wide the sidebar is while it sits above the
  /// panels under the canvas.
  double get sidebarAboveWidth => _sidebarAboveWidth.value;
  set sidebarAboveWidth(double value) =>
      _change(_sidebarAboveWidth, value, soon: true);

  /// dock is where the panels under the canvas open, how many places there
  /// are, how they are switched and the person's own layouts. See
  /// dock_layout.dart.
  DockLayout get dock => _dock.value;
  set dock(DockLayout value) => _change(_dock, value);

  /// dockLower and dockAbove are the heights of the bottom places and of
  /// the one above them; dockLeft is the left place's width.
  double get dockLower => _dockLower.value;
  set dockLower(double value) => _change(_dockLower, value, soon: true);

  double get dockAbove => _dockAbove.value;
  set dockAbove(double value) => _change(_dockAbove, value, soon: true);

  double get dockLeft => _dockLeft.value;
  set dockLeft(double value) => _change(_dockLeft, value, soon: true);

  /// panels is how the panels under the canvas were left, whatever canvas
  /// is open. The controller writes and reads it: see
  /// CanvasController.panelState.
  Map<String, dynamic> get panels => _panels.value;
  set panels(Map<String, dynamic> value) =>
      _change(_panels, Map<String, dynamic>.unmodifiable(value));

  // --------------------------------------------------------------------------
  // The timeline and the mixer
  // --------------------------------------------------------------------------

  /// timeline is whether the transport and the strip under the canvas are
  /// showing. Off to begin with, then as it was left.
  bool get timeline => _timeline.value;
  set timeline(bool value) => _change(_timeline, value, notify: true);

  /// cuesShown is whether the cues are marked on the timeline's ruler.
  bool get cuesShown => _cuesShown.value;
  set cuesShown(bool value) => _change(_cuesShown, value);

  /// mixerLayout is how the mixer and the Slots panel were left: its bands,
  /// returns, cue columns, slots and rail (CanvasController.mixerLayout).
  MixerLayout get mixerLayout => _mixerLayout.value;
  set mixerLayout(MixerLayout value) => _change(_mixerLayout, value);

  /// timelineSnap is whether a sound dragged on the timeline snaps
  /// (CanvasController.snapping).
  bool get timelineSnap => _timelineSnap.value;
  set timelineSnap(bool value) => _change(_timelineSnap, value);

  /// timelineTrackpad is whether a sideways swipe or the wheel moves the
  /// timeline: the play bar's Scrubbing (CanvasController.trackpadScrolls).
  bool get timelineTrackpad => _timelineTrackpad.value;
  set timelineTrackpad(bool value) => _change(_timelineTrackpad, value);

  /// barBelow is whether the play bar sits under the panels rather than
  /// over them (CanvasController.barBelow).
  bool get barBelow => _barBelow.value;
  set barBelow(bool value) => _change(_barBelow, value);

  // --------------------------------------------------------------------------
  // Studio colours
  // --------------------------------------------------------------------------

  /// studioLook is where the colours of the mixer and the effects come
  /// from. See StudioColors.
  StudioLook get studioLook => _studioLook.value;
  set studioLook(StudioLook value) => _change(_studioLook, value, notify: true);

  /// studioOverrides is the studio colours changed by hand.
  Map<StudioRole, Color> get studioOverrides => _studioOverrides.value;

  /// setStudioColour changes one role, or puts it back with null.
  void setStudioColour(StudioRole role, Color? colour) {
    var next = {..._studioOverrides.value};
    if (colour == null) {
      next.remove(role);
    } else {
      next[role] = colour;
    }
    _change(_studioOverrides, Map<StudioRole, Color>.unmodifiable(next),
        notify: true);
  }

  /// clearStudioColours puts every role back.
  void clearStudioColours() =>
      _change(_studioOverrides, const <StudioRole, Color>{}, notify: true);

  // --------------------------------------------------------------------------
  // Publishing
  // --------------------------------------------------------------------------

  /// publish is how the publish sheet was last set, so the next one opens
  /// the same way. The sheet writes it and reads back only what it still
  /// recognises.
  Map<String, dynamic> get publish => _publish.value;
  set publish(Map<String, dynamic> value) =>
      _change(_publish, Map<String, dynamic>.unmodifiable(value));

  // --------------------------------------------------------------------------
  // The Assets sidebar
  // --------------------------------------------------------------------------

  /// assetView is how the Assets sidebar shows [kind]'s assets.
  AssetView assetView(AssetKind kind) =>
      _assetViews.value[kind] ?? AssetView.defaultFor(kind);

  /// setAssetView changes one kind's view, leaving the others as they are.
  void setAssetView(AssetKind kind, AssetView view) => _change(
      _assetViews,
      Map<AssetKind, AssetView>.unmodifiable(
          {..._assetViews.value, kind: view}));

  /// stockLibrary is the library the Stock panel shows.
  StockLibrary get stockLibrary => _stockLibrary.value;
  set stockLibrary(StockLibrary value) => _change(_stockLibrary, value);

  /// stockFilters is each source's filters as last chosen in the Stock
  /// panel, by filter id. A source or filter not in it has its default.
  Map<StockSource, Map<String, String>> get stockFilters => _stockFilters.value;

  /// setStockFilter chooses [value] for [source]'s filter [id].
  void setStockFilter(StockSource source, String id, String value) => _change(
      _stockFilters,
      Map<StockSource, Map<String, String>>.unmodifiable({
        ..._stockFilters.value,
        source: Map<String, String>.unmodifiable(
            {...?_stockFilters.value[source], id: value}),
      }));
}
