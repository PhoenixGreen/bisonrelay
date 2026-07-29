import 'dart:io';

import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/pay_tip.dart';
import 'package:bruig/components/rename_chat.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/suggest_kx.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/trans_reset.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/notifications.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/uploads.dart';
import 'package:bruig/screens/address_book_screen.dart';
import 'package:bruig/screens/chat/new_gc_screen.dart';
import 'package:bruig/screens/chat/new_message_screen.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/gc_invitations.dart';
import 'package:bruig/screens/ln_management.dart';
import 'package:bruig/screens/manage_content_screen.dart';
import 'package:bruig/screens/send_file.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/screens/viewpage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bruig/screens/contacts_msg_times.dart';

class MainMenuItem {
  final String label;
  final String routeName;
  final WidgetBuilder builder;
  final WidgetBuilder titleBuilder;
  final Widget? icon;
  final List<SubMenuInfo> subMenuInfo;
  final bool hiddenFromSideBar;

  // area, if set, is the ThemeArea this menu item's content page is themed
  // as (see overview.dart's route dispatch, which wraps builder(context) in
  // a ThemedArea when this is non-null).
  // (MainMenuItem.area is gone: every page route is framed by the Dual
  // Panel theme area now, so a page no longer names one of its own.)

  MainMenuItem(this.label, this.routeName, this.builder, this.titleBuilder,
      this.icon, this.subMenuInfo,
      {this.hiddenFromSideBar = false});

  factory MainMenuItem.hidden(routeName, builder,
          {WidgetBuilder? titleBuilder, String label = ""}) =>
      MainMenuItem(label, routeName, builder,
          titleBuilder ?? (context) => const Txt.L("Bison Relay"), null, [],
          hiddenFromSideBar: true);
}

MainMenuItem _emptyMenu = MainMenuItem("", "", (context) => const Text(""),
    (context) => const Text(""), null, <SubMenuInfo>[]);

class SubMenuInfo {
  final int pageTab;
  final String label;
  SubMenuInfo(this.pageTab, this.label);
}

final List<SubMenuInfo> feedScreenSub = [
  SubMenuInfo(0, "Feed"),
  SubMenuInfo(1, "Your Posts"),
  SubMenuInfo(2, "Subscriptions"),
  SubMenuInfo(3, "New Post")
];

final List<SubMenuInfo> manageContentScreenSub = [
  SubMenuInfo(0, "Add"),
  SubMenuInfo(1, "Shared"),
  SubMenuInfo(2, "Downloads"),
];

final List<SubMenuInfo> lnScreenSub = [
  SubMenuInfo(0, "Overview"),
  SubMenuInfo(1, "Accounts"),
  SubMenuInfo(2, "On-Chain"),
  SubMenuInfo(3, "Channels"),
  SubMenuInfo(4, "Payments"),
  SubMenuInfo(5, "Network"),
  SubMenuInfo(6, "Backups")
];

final List<MainMenuItem> mainMenu = [
  MainMenuItem(
      "Chat",
      ChatsScreen.routeName,
      (context) =>
          Consumer3<RealtimeChatModel, AppNotifications, TypingEmojiSelModel>(
              builder: (context, rtc, ntfns, typingEmoji, child) =>
                  ChatsScreen(rtc.client, rtc, ntfns, typingEmoji)),
      (context) => const ChatsScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-chat.svg"),
      <SubMenuInfo>[],),
  MainMenuItem(
      "Address Book",
      AddressBookScreen.routeName,
      (context) => const AddressBookScreen(),
      (context) => const AddressBookScreenTitle(),
      const SidebarIcon(Icons.contacts_outlined, false),
      <SubMenuInfo>[]),
  MainMenuItem(
      "Feed",
      FeedScreen.routeName,
      (context) => Consumer2<MainMenuModel, TypingEmojiSelModel>(
          builder: (context, menu, typingEmoji, child) =>
              FeedScreen(menu, typingEmoji)),
      (context) => const FeedScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-news.svg"),
      feedScreenSub,),
  MainMenuItem(
      "Realtime Chat",
      RealtimeChatScreen.routeName,
      (context) => Consumer<TypingEmojiSelModel>(
          builder: (context, typingEmoji, child) =>
              RealtimeChatScreen(typingEmoji)),
      (context) => const RealtimeChatTitle(),
      const SidebarIcon(Icons.phone_rounded, false),
      feedScreenSub,),
  MainMenuItem(
      "LN Management",
      LNScreen.routeName,
      (context) => Consumer<MainMenuModel>(
          builder: (context, menu, child) => LNScreen(menu)),
      (context) => const LNScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-lnmng.svg"),
      lnScreenSub,),
  MainMenuItem(
      "Pages",
      ViewPageScreen.routeName,
      (context) => Consumer2<ClientModel, ResourcesModel>(
          builder: (context, client, resources, child) =>
              ViewPageScreen(resources, client)),
      (context) => const ViewPagesScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-pages.svg"),
      <SubMenuInfo>[],),
  MainMenuItem(
      "Manage Content",
      ManageContentScreen.routeName,
      (context) => Consumer<MainMenuModel>(
          builder: (context, menu, child) => ManageContentScreen(menu)),
      (context) => const ManageContentScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-files.svg"),
      manageContentScreenSub,),
  MainMenuItem(
      "Settings",
      SettingsScreen.routeName,
      (context) => Consumer<ClientModel>(
          builder: (context, client, child) => SettingsScreen(client)),
      (context) => const SettingsScreenTitle(),
      const SidebarSvgIcon("assets/icons/icons-menu-settings.svg"),
      <SubMenuInfo>[]),

  // Menus that are hidden from sidebar but accessible by direct route calls.
  MainMenuItem.hidden(
    NewMessageScreen.routeName,
    (context) => Consumer<ClientModel>(
        builder: (context, client, child) => NewMessageScreen(client)),
    titleBuilder: (context) => const ChatsScreenTitle(),
    label: "Chat",
  ),
  MainMenuItem.hidden(
    NewGcScreen.routeName,
    (context) => Consumer<ClientModel>(
        builder: (context, client, child) => NewGcScreen(client)),
    titleBuilder: (context) => const ChatsScreenTitle(),
    label: "Chat",
  ),
];

class MainMenuModel extends ChangeNotifier {
  // A mutable copy of the static mainMenu list: dynamic-wasm plugins (see
  // DynPluginsModel) register/unregister their own nav item here at
  // runtime. Both the sidebar (components/sidebar.dart) and the route
  // dispatch (screens/overview.dart) already build off this list rather
  // than a hardcoded per-item switch, so appending/removing here is all
  // that's needed for a plugin's nav item to appear/disappear.
  final List<MainMenuItem> menus = List<MainMenuItem>.from(mainMenu);

  // MainMenuModel takes the initially-active theme preset's menu
  // customization (if any) so the very first frame already reflects it --
  // ThemeNotifier resolves the persisted active theme before this model is
  // constructed (see main.dart), so its result is available synchronously
  // here, unlike a from-scratch async load.
  MainMenuModel({Map<String, String>? initialLabels, List<String>? initialOrder}) {
    if (initialLabels != null || initialOrder != null) {
      applyThemeMenu(initialLabels, initialOrder);
    }
  }

  // _customLabels/_customOrder cache the active theme's menu customization
  // independently of the live `menus` list, so it can still be applied to
  // an item that's registered *later* -- e.g. a dynamic-wasm plugin's nav
  // item, which can show up via registerDynamicItem after applyThemeMenu
  // has already run for the currently-active theme.
  Map<String, String> _customLabels = {};
  List<String>? _customOrder;

  // currentLabels/currentOrder snapshot the visible menu's current
  // labels/order, for a ThemePreset save to embed (see
  // ThemeNotifier.saveActivePreset).
  Map<String, String> currentLabels() => {
        for (var e in menus.where((e) => !e.hiddenFromSideBar))
          e.routeName: e.label,
      };
  List<String> currentOrder() => menus
      .where((e) => !e.hiddenFromSideBar)
      .map((e) => e.routeName)
      .toList();

  void _setLabel(String routeName, String newLabel) {
    var idx = menus.indexWhere((e) => e.routeName == routeName);
    if (idx < 0) return;
    var old = menus[idx];
    var updated = MainMenuItem(
        newLabel, old.routeName, old.builder, old.titleBuilder, old.icon,
        old.subMenuInfo,
        hiddenFromSideBar: old.hiddenFromSideBar);
    menus[idx] = updated;
    if (_activeRoute == routeName) {
      _activeMenu = updated;
    }
  }

  void _sortByOrder(List<String> order) {
    menus.sort((a, b) {
      var ia = order.indexOf(a.routeName);
      var ib = order.indexOf(b.routeName);
      return (ia < 0 ? 1 << 30 : ia).compareTo(ib < 0 ? 1 << 30 : ib);
    });
  }

  // renameItem changes a menu item's displayed label (its routeName, and
  // everything else about it, stays the same -- routing/unread-indicator
  // logic elsewhere keys off routeName specifically so it keeps working
  // after a rename). This is a live, in-memory-only edit -- it isn't
  // persisted anywhere on its own; saving a theme preset (see
  // ThemeNotifier.saveActivePreset) is what snapshots the current
  // labels/order (currentLabels/currentOrder) into that preset.
  void renameItem(String routeName, String newLabel) {
    _setLabel(routeName, newLabel);
    notifyListeners();
  }

  // reorderItems re-sorts menus to match newRouteNameOrder. Items whose
  // routeName isn't present in newRouteNameOrder (e.g. hidden routes, or a
  // dynamic-wasm plugin item not covered by this order) keep their relative
  // order at the end. Like renameItem, this is a live, in-memory-only edit.
  void reorderItems(List<String> newRouteNameOrder) {
    _sortByOrder(newRouteNameOrder);
    notifyListeners();
  }

  // applyThemeMenu switches the visible menu's labels/order to match a
  // theme's saved customization (null labels/order for "no customization",
  // i.e. a built-in theme or a preset that's never had its menu saved) --
  // called whenever the active color theme changes (switching/loading a
  // preset, creating one, importing one, or resetting to default), so that
  // each theme's own menu layout travels with it.
  void applyThemeMenu(Map<String, String>? labels, List<String>? order) {
    menus
      ..clear()
      ..addAll(mainMenu);
    _customLabels = labels ?? {};
    _customOrder = order;
    for (var entry in _customLabels.entries) {
      _setLabel(entry.key, entry.value);
    }
    if (order != null) _sortByOrder(order);
    notifyListeners();
  }

  // resetToDefault is applyThemeMenu(null, null) under another name, for
  // call-site clarity where "reset to default" is what's meant.
  void resetToDefault() => applyThemeMenu(null, null);

  // registerDynamicItem adds a nav item contributed by a dynamic-wasm
  // plugin. This is called every time the plugin list re-evaluates (not
  // just on enable/disable -- see DynPluginsModel.update, wired through a
  // ChangeNotifierProxyProvider2 that also depends on this very model), so
  // it must be non-destructive: if the item is already registered, update
  // it in place (new builder/icon from the manifest, but keep whatever
  // label/position the user has since applied) rather than removing and
  // re-appending it, which would silently undo a rename or reorder on
  // every unrelated menu change.
  void registerDynamicItem(MainMenuItem item) {
    var idx = menus.indexWhere((e) => e.routeName == item.routeName);
    if (idx >= 0) {
      var existing = menus[idx];
      // DynPluginsModel.update calls this on every rebuild of the provider
      // tree it's wired into (see the class comment above), passing a
      // freshly-built MainMenuItem each time even when nothing about the
      // plugin actually changed. Notifying unconditionally here would
      // notify MainMenuModel's own listeners -- including that same
      // provider tree -- which re-runs update() and calls back in here,
      // forever. Only touch state/notify when something render-relevant
      // actually differs.
      var unchanged = existing.hiddenFromSideBar == item.hiddenFromSideBar &&
          _sameIcon(existing.icon, item.icon) &&
          existing.subMenuInfo.length == item.subMenuInfo.length;
      if (unchanged) {
        // Still refresh the builder/titleBuilder closures (e.g. manifest
        // screens may have changed) since that's cheap and doesn't need a
        // rebuild -- they're only invoked on demand when the route is
        // navigated to, not eagerly.
        menus[idx] = MainMenuItem(existing.label, item.routeName,
            item.builder, item.titleBuilder, item.icon, item.subMenuInfo,
            hiddenFromSideBar: item.hiddenFromSideBar);
        return;
      }
      menus[idx] = MainMenuItem(existing.label, item.routeName, item.builder,
          item.titleBuilder, item.icon, item.subMenuInfo,
          hiddenFromSideBar: item.hiddenFromSideBar);
    } else {
      // First time this plugin's item is seen -- apply the active theme's
      // customization for it, if any.
      var label = _customLabels[item.routeName] ?? item.label;
      menus.add(MainMenuItem(label, item.routeName, item.builder,
          item.titleBuilder, item.icon, item.subMenuInfo,
          hiddenFromSideBar: item.hiddenFromSideBar));
      if (_customOrder != null) _sortByOrder(_customOrder!);
    }
    _notifyListenersAfterBuild();
  }

  static bool _sameIcon(Widget? a, Widget? b) {
    if (a is SidebarIcon && b is SidebarIcon) {
      return a.icon == b.icon && a.alert == b.alert;
    }
    return a == b;
  }

  // unregisterDynamicItem removes a previously-registered dynamic nav item
  // (plugin disabled/removed), clearing the active route/menu if it was
  // the one currently selected so the UI doesn't keep pointing at a
  // MainMenuItem no longer in menus.
  void unregisterDynamicItem(String routeName) {
    var removed = menus.any((e) => e.routeName == routeName);
    if (!removed) return;
    menus.removeWhere((e) => e.routeName == routeName);
    if (_activeRoute == routeName) {
      _activeRoute = "";
      _activeMenu = _emptyMenu;
      _activeIndex = 0;
      _activePageTab = 0;
    }
    _notifyListenersAfterBuild();
  }

  // registerDynamicItem/unregisterDynamicItem are called from
  // DynPluginsModel.update, itself invoked by a ChangeNotifierProxyProvider2
  // while it (and, transitively, MainMenuModel's own already-built
  // InheritedProviderScope) are mid-build -- calling notifyListeners()
  // directly there trips Flutter's "setState() or markNeedsBuild() called
  // during build" assertion. Deferring to a post-frame callback lets the
  // mutation apply immediately (so synchronous reads see it) while the
  // widget-rebuild notification fires safely once the frame is done.
  void _notifyListenersAfterBuild() {
    SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  String _activeRoute = "";
  MainMenuItem _activeMenu = _emptyMenu;
  int _activePageTab = 0;
  int _activeIndex = 0;
  int get activeIndex => _activeIndex;
  MainMenuItem get activeMenu => _activeMenu;
  String get activeRoute => _activeRoute;
  set activeRoute(String newRoute) {
    var idx = menus.indexWhere((e) => e.routeName == newRoute);
    if (idx < 0) {
      return;
    }
    _activeMenu = menus[idx];
    _activeRoute = newRoute;
    _activeIndex = idx;
    _activePageTab = 0;
    notifyListeners();
  }

  int get activePageTab => _activePageTab;
  set activePageTab(int pageTab) {
    _activePageTab = pageTab;
    notifyListeners();
  }

  MainMenuItem? menuForRoute(String route) {
    var idx = menus.indexWhere((e) => e.routeName == route);
    if (idx < 0) {
      return null;
    }
    return menus[idx];
  }
}

class ChatMenuItem {
  final String label;
  final Future<void> Function(BuildContext context, ClientModel chats)
      onSelected;
  const ChatMenuItem(this.label, this.onSelected);
}

List<ChatMenuItem?> buildChatContextMenu(GlobalKey<NavigatorState> navKey) {
  Future<void> generateInvite(BuildContext context) async {
    Navigator.of(context, rootNavigator: true).pushNamed('/generateInvite');
  }

  Future<void> fetchInvite(BuildContext context) async {
    Navigator.of(context, rootNavigator: true).pushNamed('/fetchInvite');
  }

  Future<void> gotoContactsLastMsgTimeScreen(BuildContext context) async {
    Navigator.of(context, rootNavigator: true)
        .pushNamed(ContactsLastMsgTimesScreen.routeName);
  }

  Future<void> gotoInvitesListScreen(BuildContext context) async {
    Navigator.of(context, rootNavigator: true)
        .pushNamed(GCInvitationsScreen.routeName);
  }

  Future<void> gotoNewMessage(BuildContext context, ClientModel client) async =>
      navKey.currentState?.pushNamed(NewMessageScreen.routeName);

  Future<void> gotoCreateGC(BuildContext context, ClientModel client) async =>
      navKey.currentState?.pushNamed(NewGcScreen.routeName);

  return <ChatMenuItem?>[
    ChatMenuItem("New Message", gotoNewMessage),
    ChatMenuItem("Create Group Chat", gotoCreateGC),
    ChatMenuItem(
        "Create Invite",
        (context, client) async =>
            client.connState.isOnline ? generateInvite(context) : null),
    ChatMenuItem(
        "Fetch Invite",
        (context, client) async =>
            client.connState.isOnline ? fetchInvite(context) : null),
    ChatMenuItem("Received Message Log",
        (context, client) => gotoContactsLastMsgTimeScreen(context)),
    ChatMenuItem("Show GC Invitations",
        (context, client) => gotoInvitesListScreen(context)),
  ];
}

List<ChatMenuItem> buildUserChatMenu(ChatModel chat) {
  void gotoChatScreen(BuildContext context) {
    var nav = Navigator.of(context);
    bool onChat = false;
    nav.popUntil((route) {
      onChat = route.settings.name == ChatsScreen.routeName;
      return true;
    });
    if (!onChat) {
      Navigator.of(context).pushReplacementNamed(ChatsScreen.routeName);
    }
  }

  void sendFile(BuildContext context) async {
    FilePickerResult? filePickRes;
    try {
      filePickRes = await FilePicker.platform.pickFiles();
    } catch (exception) {
      showErrorSnackbar(context, "Unable to select file: $exception");
      return;
    }

    if (filePickRes == null) return;
    var filePath = filePickRes.files.first.path;
    if (filePath == null) return;
    filePath = filePath.trim();
    if (filePath == "") return;

    var uploads = UploadsModel.of(context, listen: false);
    await showSendFileScreen(context,
        chat: chat, file: File(filePath), uploads: uploads);
  }

  void listUserPosts(BuildContext context, ClientModel client) async {
    if (chat.userPostsList.isNotEmpty) {
      // Already have user's posts. Show screen with them.
      FeedScreen.showUsersPosts(context, chat);

      // Request any new items.
      await Golib.listUserPosts(chat.id);
      return;
    }

    // Fetch remote list of posts.
    client.active = chat;
    gotoChatScreen(context);
    var event = ChatEventModel(RequestedUsersPostListEvent(chat.id), null);
    event.sentState = CMS_sending;
    chat.append(event, false);
    try {
      await Golib.listUserPosts(chat.id);
      event.sentState = CMS_sent;
    } catch (exception) {
      event.sendError = "Unable to list user posts: $exception";
    }
  }

  void listUserContent() async {
    var event = SynthChatEvent("Listing user content", SCE_sending);
    try {
      chat.append(ChatEventModel(event, null), false);
      await Golib.listUserContent(chat.id);
      event.state = SCE_sent;
    } catch (exception) {
      event.error = Exception("Unable to list user content: $exception");
    }
  }

  void viewPages(BuildContext context) async {
    var path = ["index.md"];
    try {
      var resources = Provider.of<ResourcesModel>(context, listen: false);
      var sess = await resources.fetchPage(chat.id, path, 0, 0, null, "");
      var event = RequestedResourceEvent(chat.id, sess);
      chat.append(ChatEventModel(event, null), false);
    } catch (exception) {
      var event = SynthChatEvent("", SCE_sending);
      event.error = Exception("Unable to fetch page: $exception");
      chat.append(ChatEventModel(event, null), false);
    }
  }

  void handshake() async {
    try {
      await Golib.handshake(chat.id);
      var event =
          SynthChatEvent("Requested 3-way handshake with user", SCE_sent);
      chat.append(ChatEventModel(event, null), false);
    } catch (exception) {
      var event = SynthChatEvent("", SCE_sending);
      event.error = Exception("Unable to perform handshake: $exception");
      chat.append(ChatEventModel(event, null), false);
    }
  }

  void subscribeToPosts() async {
    await chat.subscribeToPosts();
  }

  void unsubscribeToPosts() async {
    await chat.unsubscribeToPosts();
  }

  return <ChatMenuItem>[
    ChatMenuItem("User Profile", (context, client) async {
      client.active = chat;
      client.ui.showProfile.val = true;
      gotoChatScreen(context);
    }),
    ChatMenuItem(
      "Pay Tip",
      (context, chats) async => showPayTipModalBottom(context, chat),
    ),
    ChatMenuItem(
      "Request Ratchet Reset",
      (context, client) async {
        client.active = chat;
        gotoChatScreen(context);
        chat.requestKXReset();
      },
    ),
    ChatMenuItem("Show Content", (context, client) async {
      client.active = chat;
      gotoChatScreen(context);
      listUserContent();
    }),
    chat.isSubscribed
        ? ChatMenuItem(
            "Unsubscribe to Posts",
            (context, chats) async {
              confirmationDialog(context, () {
                unsubscribeToPosts();
              },
                  "Unsubscribe",
                  "Are you sure you want to unsubscribe from ${chats.active!.nick}'s posts?",
                  "Confirm",
                  "Cancel");
            },
          )
        : !chat.isSubscribing
            ? ChatMenuItem("Subscribe to Posts", (context, chats) async {
                confirmationDialog(
                    context,
                    subscribeToPosts,
                    "Subscribe",
                    "Are you sure you want to subscribe to ${chats.active!.nick}'s posts?",
                    "Confirm",
                    "Cancel");
              })
            : ChatMenuItem(
                "Subscribing to Posts",
                (context, chats) async {},
              ),
    ...(chat.isSubscribed
        ? [
            ChatMenuItem(
              "List Posts",
              (context, client) async => listUserPosts(context, client),
            )
          ]
        : []),
    ChatMenuItem(
      "Send File",
      (context, chats) async => sendFile(context),
    ),
    ChatMenuItem("View Pages", (context, client) async {
      client.active = chat;
      gotoChatScreen(context);
      viewPages(context);
    }),
    ChatMenuItem(
      "Rename User",
      (context, chats) async => showRenameModalBottom(context, chat),
    ),
    ChatMenuItem(
      "Suggest User to KX",
      (context, chats) async => showSuggestKXModalBottom(context, chat),
    ),
    ChatMenuItem(
      "Issue Transitive Reset with User",
      (context, chats) async => showTransResetModalBottom(context, chat),
    ),
    ChatMenuItem("Perform Handshake", (context, client) async {
      client.active = chat;
      gotoChatScreen(context);
      handshake();
    }),
  ];
}

List<ChatMenuItem> buildGCMenu(ChatModel chat) {
  return [
    ChatMenuItem(
        "Manage GC",
        (context, chats) async =>
            Provider.of<ClientModel>(context, listen: false)
                .ui
                .showProfile
                .val = true),
    ChatMenuItem(
      "Rename GC",
      (context, chats) async => showRenameModalBottom(context, chat),
    ),
    ChatMenuItem(
      "Resend GC List",
      (context, chats) async {
        var msg = SynthChatEvent("Resending GC list to members");
        msg.state = SCE_sending;
        chat.append(ChatEventModel(msg, null), false);
        try {
          await chat.resendGCList();
          msg.state = SCE_sent;
        } catch (exception) {
          msg.error = Exception("Unable to resend GC list: $exception");
        }
      },
    ),
  ];
}

class SidebarIcon extends StatelessWidget {
  final IconData icon;
  final bool alert;
  const SidebarIcon(this.icon, this.alert, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var unselectedTextColor = theme.colorScheme.onSurfaceVariant;
    if (alert) {
      return Icon(icon, color: Colors.amber);
    } else {
      return Icon(icon, color: unselectedTextColor);
    }
  }
}

class SidebarSvgIcon extends StatelessWidget {
  final String assetName;
  const SidebarSvgIcon(this.assetName, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var unselectedTextColor = theme.colorScheme.onSurfaceVariant;
    return SvgPicture.asset(
      assetName,
      colorFilter: ColorFilter.mode(unselectedTextColor, BlendMode.srcIn),
    );
  }
}
