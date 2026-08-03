import 'package:bruig/models/client.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

class ShowProfileModel extends BoolFlagModel {}

class CreateGroupChatModel extends BoolFlagModel {}

// ChatSearchModel tracks whether the active chat's in-chat search panel is
// open. Only meaningful when AreaStyle.enableChatSearch is on.
class ChatSearchModel extends BoolFlagModel {}

class ChatSideMenuActiveModel extends ChangeNotifier {
  ChatModel? _chat;
  ChatModel? get chat => _chat;
  set chat(ChatModel? v) {
    _chat = v;
    notifyListeners();
  }

  bool get empty => _chat == null;

  void clear() => chat = null;
}

class SettingsTitleModel extends ChangeNotifier {
  String _title = "Settings";
  String get title => _title;
  set title(String v) {
    _title = v;
    notifyListeners();
  }
}

// SettingsNavModel remembers where the user last was in Settings >
// Appearance (which sub-page, whether the Theme Areas section was expanded,
// and which area was selected) so navigating away to check a setting (e.g.
// visiting the chat page to see an area style take effect) and back doesn't
// lose the spot -- Settings is rebuilt from scratch on every navigation to
// it (pushReplacementNamed), so this can't just live in State.
class SettingsNavModel extends ChangeNotifier {
  String _page = "main";
  String get page => _page;
  set page(String v) {
    _page = v;
    notifyListeners();
  }

  bool _themeAreasExpanded = false;
  bool get themeAreasExpanded => _themeAreasExpanded;
  set themeAreasExpanded(bool v) {
    _themeAreasExpanded = v;
    notifyListeners();
  }

  bool _paletteExpanded = false;
  bool get paletteExpanded => _paletteExpanded;
  set paletteExpanded(bool v) {
    _paletteExpanded = v;
    notifyListeners();
  }

  ThemeArea _selectedThemeArea = ThemeArea.chat;
  ThemeArea get selectedThemeArea => _selectedThemeArea;
  set selectedThemeArea(ThemeArea v) {
    _selectedThemeArea = v;
    notifyListeners();
  }
}

class OverviewActivePath extends ChangeNotifier {
  String _route = "";
  String get route => _route;
  set route(String v) {
    if (_route != v) {
      _route = v;
      notifyListeners();
    }
  }
}

// CollapsedSidebarModel connects the three parts of the narrow-window
// sidebar drawer, which live in three different places in the tree:
//
// - the screen that owns a sidebar (SecondarySideMenuLayout, or the feed's
//   own panel) registers how to build it, and stops rendering it inline;
// - the main navigation opens it, when its already-selected destination is
//   tapped again (see Sidebar.switchScreen);
// - OverviewScreen paints it, above everything, when it's open -- which is
//   what lets the drawer cover the main navigation rather than starting
//   beside it.
//
// The screen can't paint it itself: it sits inside the content area, so
// anything it draws is clipped to the right of the main nav.
class CollapsedSidebarModel extends ChangeNotifier {
  WidgetBuilder? _builder;
  double _width = 200;
  bool _open = false;

  // available is "some screen currently has a collapsed sidebar", which is
  // what decides whether the main nav's re-tap opens anything.
  bool get available => _builder != null;
  WidgetBuilder? get builder => _builder;
  double get width => _width;
  bool get open => _open && available;

  // register/unregister are called from a screen's build, so they defer
  // notifying until the frame is done -- listeners rebuilding mid-build
  // would throw.
  //
  // The builder itself is stored every time (it's a fresh closure on each
  // build, so it can never compare equal), but only a change in whether
  // there *is* one, or in how wide it is, is worth telling anyone about --
  // notifying on every build would wake the drawer once per frame for no
  // visible change.
  void register(WidgetBuilder builder, double width) {
    var changed = _builder == null || _width != width;
    _builder = builder;
    _width = width;
    if (changed) _notifyLater();
  }

  void unregister() {
    if (_builder == null) return;
    _builder = null;
    _open = false;
    _notifyLater();
  }

  void toggle() {
    _open = !_open;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  void _notifyLater() => WidgetsBinding.instance
      .addPostFrameCallback((_) => notifyListeners());
}

// UIStateModel holds state related to the app's UI.
class UIStateModel {
  final ShowProfileModel showProfile = ShowProfileModel();
  final ChatSearchModel chatSearch = ChatSearchModel();
  final ChatSideMenuActiveModel chatSideMenuActive = ChatSideMenuActiveModel();
  final SettingsTitleModel settingsTitle = SettingsTitleModel();
  final SettingsNavModel settingsNav = SettingsNavModel();
  final OverviewActivePath overviewActivePath = OverviewActivePath();
  final CollapsedSidebarModel collapsedSidebar = CollapsedSidebarModel();
  final RouteObserver<ModalRoute<void>> overviewRouteObserver =
      RouteObserver<ModalRoute<void>>();
}

bool checkIsScreenSmall(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 500;
