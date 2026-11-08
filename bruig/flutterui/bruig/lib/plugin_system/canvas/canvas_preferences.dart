import 'dart:async';
import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// canvas_preferences.dart is what the reader has decided about the Canvas
// feature: whether it exists at all, and where the editor was left.
//
// Off by default: it costs a nav slot most readers of a messaging app will
// never use. It is a preference, not a plugin capability as the writing tools
// are, because Canvas consumes no service a plugin provides; it is the app's
// own code, like notes.

/// CanvasPreferences is the Canvas feature's saved settings.
class CanvasPreferences extends ChangeNotifier {
  static const _enabledKey = "canvasEnabled";
  static const _panelKey = "canvasSidebarPanel";
  static const _lastFolderKey = "canvasLastFolder";
  static const _lastNameKey = "canvasLastName";
  static const _allowFetchingKey = "canvasAllowFetching";
  static const _fitKey = "canvasFit";
  static const _timelineKey = "canvasTimeline";
  static const _filesFolderKey = "canvasFilesFolder";

  /// _elevenLabsKeyKey is where an ElevenLabs API key was kept, to be
  /// deleted: see load.
  static const _elevenLabsKeyKey = "canvasElevenLabsKey";
  static const _publishKey = "canvasPublish";
  static const _timelineHeightKey = "canvasTimelineHeight";
  static const _keyframesShownKey = "canvasKeyframesShown";
  static const _cuesShownKey = "canvasCuesShown";
  static const _studioLookKey = "canvasStudioLook";
  static const _studioOverridesKey = "canvasStudioColours";
  static const _menuHiddenKey = "canvasMenuHidden";
  static const _mixerBandsKey = "canvasMixerBands";
  static const _returnsShownKey = "canvasReturnsShown";
  static const _mixerHeightKey = "canvasMixerHeight";
  static const _effectsHeightKey = "canvasEffectsHeight";
  static const _panelsKey = "canvasPanels";
  static const _canvasViewsKey = "canvasViews";
  static const _dockKey = "canvasDock";
  static const _sidebarsKey = "canvasSidebars";
  static const _sidebarAboveWidthKey = "canvasSidebarAboveWidth";
  static const _dockLowerKey = "canvasDockLower";
  static const _dockAboveKey = "canvasDockAbove";
  static const _dockLeftKey = "canvasDockLeft";

  /// enabled is whether the Canvas section exists.
  bool get enabled => _enabled;
  bool _enabled = false;

  /// panel is which sidebar tab was last open, as an index into CanvasPanel;
  /// readers bounds-check it.
  int get panel => _panel;
  int _panel = 0;

  /// lastFolder and lastName are the canvas that was open when the page was
  /// last left, reopened on return.
  String get lastFolder => _lastFolder;
  String _lastFolder = "";

  String get lastName => _lastName;
  String _lastName = "";

  /// allowFetching is whether a table or a chart may fetch its data over the
  /// internet. Off by default for privacy: the fetch does not go through the
  /// daemon, so the proxy setting (Tor, say) does not apply and the address
  /// learns who is asking. A file source does the same job offline.
  bool get allowFetching => _allowFetching;
  bool _allowFetching = false;

  /// fit is how the canvas is framed -- the whole of it, or the full width.
  /// A preference, not part of the document, because it is about the
  /// reader's screen. Stored as the enum's name so reordering the fits does
  /// not change an old preference.
  String get fit => _fit;
  String _fit = "";

  set fit(String value) {
    if (_fit == value) return;
    _fit = value;
    StorageManager.saveString(_fitKey, value);
  }

  set allowFetching(bool value) {
    if (_allowFetching == value) return;
    _allowFetching = value;
    StorageManager.saveBool(_allowFetchingKey, value);
    notifyListeners();
  }

  /// timeline is whether the transport and the strip under the canvas are
  /// showing. Off to begin with, then as it was left.
  bool get timeline => _timeline;
  bool _timeline = false;

  set timeline(bool value) {
    if (_timeline == value) return;
    _timeline = value;
    StorageManager.saveBool(_timelineKey, value);
    notifyListeners();
  }

  /// filesFolder is the folder the Files panel is looking at, kept between
  /// visits as the writing library does. Cleared when the folder has gone.
  String get filesFolder => _filesFolder;
  String _filesFolder = "";

  set filesFolder(String value) {
    if (_filesFolder == value) return;
    _filesFolder = value;
    StorageManager.saveString(_filesFolderKey, value);
  }

  /// timelineHeight is how tall the timeline was dragged to, or nought for
  /// its least.
  double get timelineHeight => _timelineHeight;
  double _timelineHeight = 0;

  set timelineHeight(double value) {
    if (_timelineHeight == value) return;
    _timelineHeight = value;
    _saveSoon(_timelineHeightKey, value.toStringAsFixed(1));
  }

  /// _saveSoon writes [value] under [key] once it has stopped changing for
  /// a moment: a panel's edge dragged sets its height at every step, and
  /// each write is a round trip to the platform's preferences.
  void _saveSoon(String key, String value) {
    _unsaved[key] = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    for (var MapEntry(:key, :value) in _unsaved.entries) {
      StorageManager.saveString(key, value);
    }
    _unsaved.clear();
  }

  final Map<String, String> _unsaved = {};
  Timer? _saveTimer;

  @override
  void dispose() {
    _saveNow();
    super.dispose();
  }

  /// menuHidden is whether the app's sidebar and header are put away while
  /// the canvas is open. The Bison Relay logo toggles it, and sits at the
  /// start of the canvas's own bar while the menu is away.
  bool get menuHidden => _menuHidden;
  bool _menuHidden = false;
  set menuHidden(bool value) {
    if (_menuHidden == value) return;
    _menuHidden = value;
    StorageManager.saveBool(_menuHiddenKey, value);
    notifyListeners();
  }

  /// mixerBands is how each of the mixer's bands was left (shown, minimised
  /// or hidden, by name), and returnsShown whether the returns were. Empty
  /// for as they start.
  List<String> get mixerBands => _mixerBands;
  List<String> _mixerBands = const [];
  set mixerBands(List<String> value) {
    if (_mixerBands.join(",") == value.join(",")) return;
    _mixerBands = value;
    StorageManager.saveString(_mixerBandsKey, value.join(","));
  }

  bool get returnsShown => _returnsShown;
  bool _returnsShown = true;
  set returnsShown(bool value) {
    if (_returnsShown == value) return;
    _returnsShown = value;
    StorageManager.saveBool(_returnsShownKey, value);
  }

  /// mixerHeight and effectsHeight are how tall the mixer and the effects
  /// panel were dragged to, or nought for as they start.
  double get mixerHeight => _mixerHeight;
  double _mixerHeight = 0;
  set mixerHeight(double value) {
    if (_mixerHeight == value) return;
    _mixerHeight = value;
    _saveSoon(_mixerHeightKey, value.toStringAsFixed(1));
  }

  double get effectsHeight => _effectsHeight;
  double _effectsHeight = 0;
  set effectsHeight(double value) {
    if (_effectsHeight == value) return;
    _effectsHeight = value;
    _saveSoon(_effectsHeightKey, value.toStringAsFixed(1));
  }

  /// sidebars is how the sidebar is set out: shown or not and how, its
  /// sidebars and their panels. See sidebar_layout.dart.
  SidebarLayout get sidebars => _sidebars;
  SidebarLayout _sidebars = const SidebarLayout();
  set sidebars(SidebarLayout value) {
    var json = jsonEncode(value.toJson());
    if (json == jsonEncode(_sidebars.toJson())) return;
    _sidebars = value;
    StorageManager.saveString(_sidebarsKey, json);
  }

  /// sidebarAboveWidth is how wide the sidebar is sitting above the panels
  /// under the canvas; nought until dragged.
  double get sidebarAboveWidth => _sidebarAboveWidth;
  double _sidebarAboveWidth = 0;
  set sidebarAboveWidth(double value) {
    if (_sidebarAboveWidth == value) return;
    _sidebarAboveWidth = value;
    _saveSoon(_sidebarAboveWidthKey, value.toStringAsFixed(1));
  }

  /// dock is where the panels under the canvas open, how many places there
  /// are, how they are switched and the reader's own layouts. See
  /// dock_layout.dart.
  DockLayout get dock => _dock;
  DockLayout _dock = const DockLayout();
  set dock(DockLayout value) {
    if (value == _dock) return;
    _dock = value;
    StorageManager.saveString(_dockKey, jsonEncode(value.toJson()));
  }

  /// dockLower and dockAbove are how tall the bottom places and the one
  /// above them are, and dockLeft how wide the left place is; nought until
  /// set.
  double get dockLower => _dockLower;
  double _dockLower = 0;
  set dockLower(double value) {
    if (_dockLower == value) return;
    _dockLower = value;
    _saveSoon(_dockLowerKey, value.toStringAsFixed(1));
  }

  double get dockAbove => _dockAbove;
  double _dockAbove = 0;
  set dockAbove(double value) {
    if (_dockAbove == value) return;
    _dockAbove = value;
    _saveSoon(_dockAboveKey, value.toStringAsFixed(1));
  }

  double get dockLeft => _dockLeft;
  double _dockLeft = 0;
  set dockLeft(double value) {
    if (_dockLeft == value) return;
    _dockLeft = value;
    _saveSoon(_dockLeftKey, value.toStringAsFixed(1));
  }

  /// panels is how the panels under the canvas were left, whatever canvas
  /// is open -- see CanvasController.panelState. Empty for as they start.
  Map<String, dynamic> get panels => _panels;
  Map<String, dynamic> _panels = const {};
  set panels(Map<String, dynamic> value) {
    var json = jsonEncode(value);
    if (json == jsonEncode(_panels)) return;
    _panels = Map.unmodifiable(value);
    StorageManager.saveString(_panelsKey, json);
  }

  /// canvasView is how the canvas saved as [key] ("folder/name") was last
  /// looked at. See CanvasController.canvasView.
  Map<String, dynamic>? canvasView(String key) => _canvasViews[key];
  Map<String, Map<String, dynamic>> _canvasViews = {};

  /// _viewsKept is how many canvases' views are kept: the latest looked at.
  static const _viewsKept = 40;

  void setCanvasView(String key, Map<String, dynamic> view) {
    var json = jsonEncode(view);
    if (_canvasViews[key] != null && jsonEncode(_canvasViews[key]) == json) {
      return;
    }
    // Re-inserted so the map runs oldest first; the oldest are dropped.
    _canvasViews.remove(key);
    _canvasViews[key] = view;
    while (_canvasViews.length > _viewsKept) {
      _canvasViews.remove(_canvasViews.keys.first);
    }
    StorageManager.saveString(_canvasViewsKey, jsonEncode(_canvasViews));
  }

  /// keyframesShown and cuesShown are which of the timeline's rows
  /// (keyframes, cues on the ruler) were showing. All shown to
  /// begin with.
  bool get keyframesShown => _keyframesShown;
  bool _keyframesShown = true;
  set keyframesShown(bool value) {
    if (_keyframesShown == value) return;
    _keyframesShown = value;
    StorageManager.saveBool(_keyframesShownKey, value);
  }

  bool get cuesShown => _cuesShown;
  bool _cuesShown = true;
  set cuesShown(bool value) {
    if (_cuesShown == value) return;
    _cuesShown = value;
    StorageManager.saveBool(_cuesShownKey, value);
  }

  /// studioLook is where the mixer's and the effects' colours come from,
  /// and studioOverrides any of them changed by hand. See StudioColors.
  StudioLook get studioLook => _studioLook;
  StudioLook _studioLook = StudioLook.studio;
  set studioLook(StudioLook value) {
    if (_studioLook == value) return;
    _studioLook = value;
    StorageManager.saveString(_studioLookKey, value.name);
    notifyListeners();
  }

  Map<StudioRole, Color> get studioOverrides => _studioOverrides;
  Map<StudioRole, Color> _studioOverrides = const {};

  /// setStudioColour changes one role, or puts it back with null.
  void setStudioColour(StudioRole role, Color? colour) {
    var next = {..._studioOverrides};
    if (colour == null) {
      next.remove(role);
    } else {
      next[role] = colour;
    }
    _studioOverrides = Map.unmodifiable(next);
    StorageManager.saveString(
        _studioOverridesKey,
        jsonEncode(
            {for (var e in next.entries) e.key.name: colorToJson(e.value)}));
    notifyListeners();
  }

  /// clearStudioColours puts every role back.
  void clearStudioColours() {
    _studioOverrides = const {};
    StorageManager.saveString(_studioOverridesKey, "");
    notifyListeners();
  }

  /// publish is how the publish sheet was last set when something was
  /// published, so the next one opens the same way. Kept as the sheet writes
  /// it; the sheet reads back only what it still recognises.
  Map<String, dynamic> get publish => _publish;
  Map<String, dynamic> _publish = const {};

  set publish(Map<String, dynamic> value) {
    _publish = Map.unmodifiable(value);
    StorageManager.saveString(_publishKey, jsonEncode(value));
  }

  /// load reads what was saved, once at startup; the defaults are in force
  /// until it returns.
  Future<void> load() async {
    _enabled = await StorageManager.readBool(_enabledKey, defaultVal: false);
    _panel = int.tryParse(await StorageManager.readString(_panelKey)) ?? 0;
    _lastFolder = await StorageManager.readString(_lastFolderKey);
    _lastName = await StorageManager.readString(_lastNameKey);
    _allowFetching =
        await StorageManager.readBool(_allowFetchingKey, defaultVal: false);
    _fit = await StorageManager.readString(_fitKey);
    _timeline = await StorageManager.readBool(_timelineKey, defaultVal: false);
    _filesFolder = await StorageManager.readString(_filesFolderKey);
    // A stored ElevenLabs API key from a removed engine: delete it.
    if (await StorageManager.exists(_elevenLabsKeyKey)) {
      await StorageManager.deleteData(_elevenLabsKeyKey);
    }
    _keyframesShown =
        await StorageManager.readBool(_keyframesShownKey, defaultVal: true);
    _cuesShown = await StorageManager.readBool(_cuesShownKey, defaultVal: true);
    _timelineHeight =
        double.tryParse(await StorageManager.readString(_timelineHeightKey)) ??
            0;
    _menuHidden = await StorageManager.readBool(_menuHiddenKey);
    var bands = await StorageManager.readString(_mixerBandsKey);
    _mixerBands = bands.isEmpty ? const [] : bands.split(",");
    _returnsShown =
        await StorageManager.readBool(_returnsShownKey, defaultVal: true);
    _mixerHeight =
        double.tryParse(await StorageManager.readString(_mixerHeightKey)) ?? 0;
    try {
      _dock = DockLayout.fromJson(
          jsonDecode(await StorageManager.readString(_dockKey)));
    } catch (_) {
      // Nothing kept yet: the panels open where they start.
    }
    var sidebars = await StorageManager.readString(_sidebarsKey);
    if (sidebars.isNotEmpty) {
      try {
        _sidebars = SidebarLayout.fromJson(jsonDecode(sidebars));
      } catch (_) {
        // Unreadable: the sidebars as they start.
      }
    } else {
      // Kept before the sidebars could be set out: on the tab last open.
      const tabs = ["files", "files", "design", "assets", "game"];
      _sidebars = SidebarLayout(
          current:
              _panel >= 0 && _panel < tabs.length ? tabs[_panel] : "files");
    }
    _sidebarAboveWidth = double.tryParse(
            await StorageManager.readString(_sidebarAboveWidthKey)) ??
        0;
    _dockLower =
        double.tryParse(await StorageManager.readString(_dockLowerKey)) ?? 0;
    _dockAbove =
        double.tryParse(await StorageManager.readString(_dockAboveKey)) ?? 0;
    _dockLeft =
        double.tryParse(await StorageManager.readString(_dockLeftKey)) ?? 0;
    _effectsHeight =
        double.tryParse(await StorageManager.readString(_effectsHeightKey)) ??
            0;
    try {
      var saved = jsonDecode(await StorageManager.readString(_panelsKey));
      if (saved is Map<String, dynamic>) _panels = Map.unmodifiable(saved);
    } catch (_) {
      // Nothing kept yet.
    }
    try {
      var saved = jsonDecode(await StorageManager.readString(_canvasViewsKey));
      if (saved is Map<String, dynamic>) {
        _canvasViews = {
          for (var e in saved.entries)
            if (e.value is Map<String, dynamic>)
              e.key: e.value as Map<String, dynamic>,
        };
      }
    } catch (_) {
      // Nothing kept yet.
    }
    _studioLook =
        StudioLook.fromName(await StorageManager.readString(_studioLookKey));
    try {
      var saved =
          jsonDecode(await StorageManager.readString(_studioOverridesKey));
      if (saved is Map) {
        _studioOverrides = Map.unmodifiable({
          for (var role in StudioRole.values)
            if (saved[role.name] is num) role: colorFromJson(saved[role.name]),
        });
      }
    } catch (_) {
      // Nothing changed by hand yet.
    }
    try {
      var saved = jsonDecode(await StorageManager.readString(_publishKey));
      if (saved is Map<String, dynamic>) _publish = Map.unmodifiable(saved);
    } catch (_) {
      // Nothing saved yet, or something unreadable: the sheet's own defaults.
    }
    notifyListeners();
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    StorageManager.saveBool(_enabledKey, value);
    notifyListeners();
  }

  set panel(int value) {
    if (_panel == value) return;
    _panel = value;
    StorageManager.saveString(_panelKey, "$value");
    // Deliberately not notifying: the sidebar has already redrawn, and a
    // notify would rebuild the navigation and the whole page.
  }

  /// pendingOpen is a canvas to open the next time the Canvas page shows,
  /// such as one opened from Files. Not saved.
  (String folder, String name)? pendingOpen;

  /// remember records which canvas is open, so it can be reopened next time.
  void remember(String folder, String name) {
    if (_lastFolder == folder && _lastName == name) return;
    _lastFolder = folder;
    _lastName = name;
    StorageManager.saveString(_lastFolderKey, folder);
    StorageManager.saveString(_lastNameKey, name);
  }
}
