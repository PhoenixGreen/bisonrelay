import 'package:bruig/models/client.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/viewpage_screen.dart';
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

enum SmallScreenActiveTab {
  chat,
  feed,
  pages,
}

class SmallScreenActiveTabModel extends ChangeNotifier {
  SmallScreenActiveTab _active = SmallScreenActiveTab.chat;
  SmallScreenActiveTab get active => _active;
  set active(SmallScreenActiveTab v) {
    _active = v;
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

  // onActiveBottomTab is true if the current active route is one that corresponds
  // to one of the bottom tabs ("chats", "feeds", "pages").
  bool get onActiveBottomTab => [
        ChatsScreen.routeName,
        FeedScreen.routeName,
        ViewPageScreen.routeName
      ].contains(route);
}

// UIStateModel holds state related to the app's UI.
class UIStateModel {
  final ShowProfileModel showProfile = ShowProfileModel();
  final ChatSearchModel chatSearch = ChatSearchModel();
  final ChatSideMenuActiveModel chatSideMenuActive = ChatSideMenuActiveModel();
  final SettingsTitleModel settingsTitle = SettingsTitleModel();
  final SettingsNavModel settingsNav = SettingsNavModel();
  final SmallScreenActiveTabModel smallScreenActiveTab =
      SmallScreenActiveTabModel();
  final OverviewActivePath overviewActivePath = OverviewActivePath();
  final RouteObserver<ModalRoute<void>> overviewRouteObserver =
      RouteObserver<ModalRoute<void>>();
}

bool checkIsScreenSmall(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 500;
