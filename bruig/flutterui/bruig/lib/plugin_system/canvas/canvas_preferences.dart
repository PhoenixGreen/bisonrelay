import 'dart:convert';

import 'package:bruig/plugin_system/canvas/media/mix/dart_audio_engine.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// canvas_preferences.dart is what the reader has decided about the Canvas
// feature: whether it exists at all, and where the editor was left.
//
// Off by default. Canvas is a whole page and a whole navigation item for
// something most readers of a messaging app will never open, and a feature
// that costs a nav slot has to be asked for. Turning it on is one switch in
// Settings > Plugins.
//
// It is not gated on a plugin capability, unlike the writing tools next door,
// and the difference is real rather than a shortcut: the writing tools consume
// a service some plugin has to provide -- a dictionary, a rule set -- and are
// meaningless without a provider. Canvas provides and consumes nothing. It is
// entirely the app's own code, like notes, so the thing that decides whether
// it is here is a preference rather than an installed module.

class CanvasPreferences extends ChangeNotifier {
  static const _enabledKey = "canvasEnabled";
  static const _panelKey = "canvasSidebarPanel";
  static const _lastFolderKey = "canvasLastFolder";
  static const _lastNameKey = "canvasLastName";
  static const _allowFetchingKey = "canvasAllowFetching";
  static const _allowCaptureKey = "canvasAllowCapture";
  static const _fitKey = "canvasFit";
  static const _timelineKey = "canvasTimeline";
  static const _filesFolderKey = "canvasFilesFolder";
  static const _publishKey = "canvasPublish";
  static const _timelineHeightKey = "canvasTimelineHeight";
  static const _drawBarWidthKey = "canvasDrawBarWidth";
  static const _keyframesShownKey = "canvasKeyframesShown";
  static const _scenesShownKey = "canvasScenesShown";
  static const _cuesShownKey = "canvasCuesShown";
  static const _studioLookKey = "canvasStudioLook";
  static const _mixEngineKey = "canvasMixEngine";
  static const _studioOverridesKey = "canvasStudioColours";

  /// enabled is whether the Canvas section exists.
  bool get enabled => _enabled;
  bool _enabled = false;

  /// panel is which sidebar tab was last open, as an index into CanvasPanel.
  /// Stored as an int so that adding a panel does not invalidate it, and read
  /// back with a bounds check for the same reason.
  int get panel => _panel;
  int _panel = 0;

  /// lastFolder and lastName are the canvas that was open when the page was
  /// last left, so returning to Canvas returns to what you were doing rather
  /// than to a blank page.
  String get lastFolder => _lastFolder;
  String _lastFolder = "";

  String get lastName => _lastName;
  String _lastName = "";

  /// allowFetching is whether a table or a chart may go and get its data over
  /// the internet.
  ///
  /// Off, and a decision rather than a default. Nothing else in this app's
  /// interface opens a connection of its own: everything goes out through the
  /// daemon, which is what the proxy setting in Settings applies to. A fetch
  /// from here does not, so on a machine set up to reach the network only
  /// through Tor it would be the one connection that did not -- and the
  /// address it connected to would learn who was asking.
  ///
  /// That is a fair trade for somebody who wants a live league table on a
  /// machine with no proxy set, and it is not a trade anybody should make
  /// without being told. So the switch says so, and the file source next to it
  /// does the same job with no connection at all.
  bool get allowFetching => _allowFetching;
  bool _allowFetching = false;

  /// allowCapture is whether the canvas may record from the camera and the
  /// microphone -- a movement for a character to copy, a voice-over for it
  /// to speak. Off until switched on, and macOS asks as well the first
  /// time: a design tool that can turn the camera on is one that has to be
  /// asked to.
  bool get allowCapture => _allowCapture;
  bool _allowCapture = false;

  set allowCapture(bool value) {
    if (_allowCapture == value) return;
    _allowCapture = value;
    StorageManager.saveBool(_allowCaptureKey, value);
    notifyListeners();
  }

  /// fit is how the canvas is framed -- the whole of it, or the full width.
  ///
  /// A preference rather than a property of the document, because it is about
  /// the reader's screen rather than about the design: the same canvas wants
  /// the whole frame on a wide monitor and the width on a laptop, and it is
  /// the same canvas either way. So it survives opening a different one, which
  /// is the whole point -- choosing it again for every canvas is choosing it
  /// several times a session.
  ///
  /// Stored as the enum's name so that adding or reordering the fits does not
  /// silently change what an old preference means.
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
  /// showing.
  ///
  /// Off to begin with, and then whatever it was left as. Most canvases are
  /// still designs and a strip of animation controls under one is a strip of
  /// room taken from the page -- and somebody who does animate turns it on
  /// once rather than on every visit.
  bool get timeline => _timeline;
  bool _timeline = false;

  set timeline(bool value) {
    if (_timeline == value) return;
    _timeline = value;
    StorageManager.saveBool(_timelineKey, value);
    notifyListeners();
  }

  /// filesFolder is the folder the Files panel is looking at.
  ///
  /// Kept because being put back at the top of the library every time is
  /// being made to walk back into the folder you were working in -- which is
  /// how the writing library behaves, and it is the better of the two.
  /// Cleared when the folder it names has gone.
  String get filesFolder => _filesFolder;
  String _filesFolder = "";

  set filesFolder(String value) {
    if (_filesFolder == value) return;
    _filesFolder = value;
    StorageManager.saveString(_filesFolderKey, value);
  }

  /// timelineHeight is how tall the timeline was dragged to, or nought for
  /// its least: room for the channels under the keyframe strip is kept
  /// between visits, like which panels are open.
  double get timelineHeight => _timelineHeight;
  double _timelineHeight = 0;

  set timelineHeight(double value) {
    if (_timelineHeight == value) return;
    _timelineHeight = value;
    StorageManager.saveString(_timelineHeightKey, value.toStringAsFixed(1));
  }

  /// drawBarWidth is how wide a sketched character's bar over the canvas
  /// was dragged to, or nought for its usual width -- see
  /// character_draw_bar.dart. One width, whatever tool is in hand.
  double get drawBarWidth => _drawBarWidth;
  double _drawBarWidth = 0;

  set drawBarWidth(double value) {
    if (_drawBarWidth == value) return;
    _drawBarWidth = value;
    StorageManager.saveString(_drawBarWidthKey, value.toStringAsFixed(1));
    notifyListeners();
  }

  /// keyframesShown, scenesShown and cuesShown are which of the timeline's
  /// rows were showing -- the keyframes, the scenes, the cues on the ruler --
  /// kept between visits, like the timeline itself. All shown to begin with.
  bool get keyframesShown => _keyframesShown;
  bool _keyframesShown = true;
  set keyframesShown(bool value) {
    if (_keyframesShown == value) return;
    _keyframesShown = value;
    StorageManager.saveBool(_keyframesShownKey, value);
  }

  bool get scenesShown => _scenesShown;
  bool _scenesShown = true;
  set scenesShown(bool value) {
    if (_scenesShown == value) return;
    _scenesShown = value;
    StorageManager.saveBool(_scenesShownKey, value);
  }

  bool get cuesShown => _cuesShown;
  bool _cuesShown = true;
  set cuesShown(bool value) {
    if (_cuesShown == value) return;
    _cuesShown = value;
    StorageManager.saveBool(_cuesShownKey, value);
  }

  /// mixEngine is whether the editor plays through the mix engine rather
  /// than SoLoud's own buses -- see dart_audio_engine.dart. On by default.
  bool get mixEngine => useMixEngine;
  set mixEngine(bool value) {
    if (useMixEngine == value) return;
    useMixEngine = value;
    StorageManager.saveBool(_mixEngineKey, value);
    notifyListeners();
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
    StorageManager.saveString(_studioOverridesKey,
        jsonEncode({for (var e in next.entries) e.key.name: colorToJson(e.value)}));
    notifyListeners();
  }

  /// clearStudioColours puts every role back.
  void clearStudioColours() {
    _studioOverrides = const {};
    StorageManager.saveString(_studioOverridesKey, "");
    notifyListeners();
  }

  /// publish is how the publish sheet was last set when something was
  /// published with it -- what, as what, where, and every setting for each --
  /// so that the next one opens as the last was left rather than on Image
  /// every time. Kept as the sheet writes it; the sheet reads back only what
  /// it still recognises.
  Map<String, dynamic> get publish => _publish;
  Map<String, dynamic> _publish = const {};

  set publish(Map<String, dynamic> value) {
    _publish = Map.unmodifiable(value);
    StorageManager.saveString(_publishKey, jsonEncode(value));
  }

  /// load reads what was saved. Called once at startup; until it returns the
  /// defaults are in force, which is the right way round -- a nav item that
  /// appeared a moment after the window opened would be worse than one that
  /// was simply there.
  Future<void> load() async {
    _enabled = await StorageManager.readBool(_enabledKey, defaultVal: false);
    _panel = int.tryParse(await StorageManager.readString(_panelKey)) ?? 0;
    _lastFolder = await StorageManager.readString(_lastFolderKey);
    _lastName = await StorageManager.readString(_lastNameKey);
    _allowFetching =
        await StorageManager.readBool(_allowFetchingKey, defaultVal: false);
    _allowCapture =
        await StorageManager.readBool(_allowCaptureKey, defaultVal: false);
    _fit = await StorageManager.readString(_fitKey);
    _timeline = await StorageManager.readBool(_timelineKey, defaultVal: false);
    _filesFolder = await StorageManager.readString(_filesFolderKey);
    _keyframesShown =
        await StorageManager.readBool(_keyframesShownKey, defaultVal: true);
    _scenesShown =
        await StorageManager.readBool(_scenesShownKey, defaultVal: true);
    _cuesShown = await StorageManager.readBool(_cuesShownKey, defaultVal: true);
    _timelineHeight =
        double.tryParse(await StorageManager.readString(_timelineHeightKey)) ??
            0;
    _drawBarWidth =
        double.tryParse(await StorageManager.readString(_drawBarWidthKey)) ?? 0;
    useMixEngine =
        await StorageManager.readBool(_mixEngineKey, defaultVal: true);
    _studioLook =
        StudioLook.fromName(await StorageManager.readString(_studioLookKey));
    try {
      var saved =
          jsonDecode(await StorageManager.readString(_studioOverridesKey));
      if (saved is Map) {
        _studioOverrides = Map.unmodifiable({
          for (var role in StudioRole.values)
            if (saved[role.name] is num)
              role: colorFromJson(saved[role.name]),
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
    // Deliberately not notifying. Which tab is open is the sidebar's own
    // state, already redrawn by whatever changed it; notifying from here would
    // rebuild the navigation and the whole page for a tab click.
  }

  /// remember records which canvas is open, so it can be reopened next time.
  void remember(String folder, String name) {
    if (_lastFolder == folder && _lastName == name) return;
    _lastFolder = folder;
    _lastName = name;
    StorageManager.saveString(_lastFolderKey, folder);
    StorageManager.saveString(_lastNameKey, name);
  }
}
