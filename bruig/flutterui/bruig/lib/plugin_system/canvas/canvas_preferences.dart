import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';

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
  static const _fitKey = "canvasFit";

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
    _fit = await StorageManager.readString(_fitKey);
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
