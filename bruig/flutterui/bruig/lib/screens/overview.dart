import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/components/clipper.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/indicator.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/page_context_menu.dart';
import 'package:bruig/components/route_error.dart';
import 'package:bruig/components/sidebar.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/notifications.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/screens/feed/post_content.dart';
import 'package:bruig/notification_service.dart';
import 'package:bruig/screens/settings.dart';
import 'package:bruig/screens/viewpage_screen.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';

// These are hacks. Find a way to remove them.
final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
final GlobalKey<NavigatorState> overviewNavKey = GlobalKey<NavigatorState>();

class OverviewNavigatorModel extends ChangeNotifier {
  final GlobalKey<NavigatorState> navKey;

  OverviewNavigatorModel(this.navKey);

  static OverviewNavigatorModel of(BuildContext context,
          {bool listen = true}) =>
      Provider.of<OverviewNavigatorModel>(context, listen: listen);
}

class _OverviewScreenTitle extends StatelessWidget {
  const _OverviewScreenTitle();

  @override
  Widget build(BuildContext context) {
    return Consumer<MainMenuModel>(
        builder: (context, mainMenu, child) =>
            mainMenu.activeMenu.titleBuilder(context));
  }
}

class PageTabs {
  final int tabIndex;
  final ChatModel? userPostList;
  final PostContentScreenArgs? postScreenArgs;

  PageTabs(this.tabIndex, this.userPostList, this.postScreenArgs);
}

class OverviewScreen extends StatefulWidget {
  static const routeName = '/overview';
  static String subRoute(String route) => route.isNotEmpty && route[0] == "/"
      ? "$routeName$route"
      : "$routeName/$route";
  final ClientModel client;
  final AppNotifications ntfns;
  final DownloadsModel down;
  final String initialRoute;
  final MainMenuModel mainMenu;
  final FeedModel feed;
  final SnackBarModel snackBar;
  final RealtimeChatModel rtc;
  const OverviewScreen(this.down, this.client, this.ntfns, this.initialRoute,
      this.mainMenu, this.feed, this.snackBar, this.rtc,
      {super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenAppBarConnState {
  final Widget tag;

  _OverviewScreenAppBarConnState({required this.tag});
}

const _connStateTagClipPath =
    "M 0.31234165,80.167689 79.855347,0 37.064542,0.10411388 0,37.793339 Z";

const connStateUpdate = 999;

final _connStateStyles = {
  connStateCheckingWallet: _OverviewScreenAppBarConnState(
      tag: ClipPath(
          clipper:
              SVGClipper(_connStateTagClipPath, offset: const Offset(-10, 0)),
          child: Image.asset("assets/images/checktag.png", width: 50))),
  connStateOffline: _OverviewScreenAppBarConnState(
      tag: ClipPath(
          clipper:
              SVGClipper(_connStateTagClipPath, offset: const Offset(-10, 0)),
          child: Image.asset("assets/images/offlinetag.png", width: 50))),
  connStateOnline: _OverviewScreenAppBarConnState(tag: const Empty()),
  connStateUpdate: _OverviewScreenAppBarConnState(
      tag: ClipPath(
          clipper:
              SVGClipper(_connStateTagClipPath, offset: const Offset(-10, 0)),
          child: Image.asset("assets/images/updatetag.png", width: 50))),
};

class _MainAppBar extends StatefulWidget {
  final ClientModel client;
  final FeedModel feed;
  final RealtimeChatModel rtc;
  final MainMenuModel mainMenu;
  final GlobalKey<NavigatorState> navKey;
  // contentMode is true when HeaderPosition.content is selected: the header
  // sits above just the content area (not the sidebar), so the app-wide
  // logo/about-button and "new post" button (which belong to the global
  // chrome) are omitted -- only the title remains.
  final bool contentMode;
  const _MainAppBar(
      this.client, this.feed, this.rtc, this.mainMenu, this.navKey,
      {this.contentMode = false});

  @override
  State<_MainAppBar> createState() => __MainAppBarState();
}

class __MainAppBarState extends State<_MainAppBar>
    with SingleTickerProviderStateMixin {
  GlobalKey<NavigatorState> get navKey => widget.navKey;
  MainMenuModel get mainMenu => widget.mainMenu;
  ClientModel get client => widget.client;
  FeedModel get feed => widget.feed;
  RealtimeChatModel get rtc => widget.rtc;

  late AnimationController bgColorCtrl;
  late Animation<Color?> bgColorAnim;

  bool hasLiveRTCSess = false;
  bool hasHotAudio = false;
  bool get hasAnimation => hasLiveRTCSess || hasHotAudio;

  void goToNewPost(BuildContext context) {
    navKey.currentState
        ?.pushReplacementNamed('/feed', arguments: PageTabs(3, null, null));
  }

  void goToAbout(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pushNamed("/about");
  }

  void switchScreen(String route, {Object? args}) {
    navKey.currentState!.pushReplacementNamed(route, arguments: args);
  }

  void rtcChanged() {
    bool newHasHotAudio = rtc.hotAudioSession.active?.inLiveSession ?? false;
    bool newHasLive = rtc.liveSessions.hasSessions;
    if (newHasLive != hasLiveRTCSess || newHasHotAudio != hasHotAudio) {
      setState(() {
        hasLiveRTCSess = newHasLive;
        hasHotAudio = newHasHotAudio;
      });
      if (hasAnimation) {
        bgColorCtrl.repeat();
      } else {
        bgColorCtrl.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();

    rtc.hotAudioSession.addListener(rtcChanged);
    rtc.liveSessions.addListener(rtcChanged);

    // Initialize animation controller
    bgColorCtrl = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Create the color animation sequence
    bgColorAnim = TweenSequence<Color?>([
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade600,
          end: Colors.green.shade900,
        ),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade900,
          end: Colors.green.shade600,
        ),
      ),
    ]).animate(bgColorCtrl);
  }

  @override
  void dispose() {
    bgColorCtrl.dispose();
    rtc.hotAudioSession.removeListener(rtcChanged);
    rtc.liveSessions.removeListener(rtcChanged);
    super.dispose();
  }

  Widget buildAppBar(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    var theme = ThemeNotifier.of(context);
    var headerStyle = theme.areaStyle(ThemeArea.header);
    // Deliberately only the background/border/margin fields, not every
    // header setting: height/contentAlign are applied unconditionally
    // inside _buildInnerAppBar regardless of this flag, so they must NOT
    // factor in here -- doing so would needlessly disable the live-call
    // pulsing background color below whenever only the header's height or
    // text alignment (not its background/border) was customized.
    var headerOverridden = headerStyle.mode != AreaBackgroundMode.token ||
        headerStyle.borderMode != AreaBackgroundMode.token ||
        // A non-default image preset paints over the Default background,
        // so it needs the themed container too even though `mode` is still
        // Default.
        headerStyle.imagePreset != AreaImagePreset.standard ||
        !headerStyle.margins.isZero;

    var appBar = _buildInnerAppBar(context, isScreenSmall, theme, headerOverridden);

    if (!headerOverridden) return appBar;
    // Deliberately not using AppBar.flexibleSpace for this -- flexibleSpace
    // is stacked internally with StackFit.passthrough, and getting a plain
    // themed Container to actually fill the bar through that (rather than
    // collapsing to its own near-zero intrinsic size) needs care that's
    // easy to get subtly wrong. Wrapping the whole (transparent-background)
    // AppBar in our own Stack, where we control every constraint, sidesteps
    // that entirely: PreferredSize (set by the caller) already fixes this
    // widget's height, so Positioned.fill here has an unambiguous area to
    // fill.
    return Stack(children: [
      Positioned.fill(
          child: theme.areaContainer(ThemeArea.header, SurfaceColor.surface,
              child: const Empty())),
      appBar,
    ]);
  }

  AppBar _buildInnerAppBar(BuildContext context, bool isScreenSmall,
      ThemeNotifier theme, bool headerOverridden) {
    var headerStyle = theme.areaStyle(ThemeArea.header);
    Widget titleWidget = headerStyle.contentAlign == ContentAlign.hidden
        ? const Empty()
        : ChangeNotifierProvider.value(
            value: OverviewNavigatorModel(navKey),
            builder: (context, _) => const _OverviewScreenTitle());
    if (headerStyle.contentAlign == ContentAlign.end) {
      // Left-aligned text already gets its gap from the leading content via
      // titleSpacing (the padding's left side, below) -- using this setting
      // here too (not a separate hardcoded inset) keeps both sides governed
      // by Padding, rather than right always having a fixed 20px gap
      // regardless of it while left has none until Padding is raised. Each
      // side reads its own value, so splitting Padding per side controls
      // the two gaps independently.
      titleWidget = Align(
          alignment: Alignment.centerRight,
          child: Padding(
              padding: EdgeInsets.only(right: headerStyle.paddings.right),
              child: titleWidget));
    }
    bool? centerTitle = switch (headerStyle.contentAlign) {
      ContentAlign.center => true,
      ContentAlign.start => false,
      ContentAlign.end || ContentAlign.hidden || null => null,
    };

    if (!isScreenSmall) {
      var logoSize = headerStyle.logoSize ?? 40;
      // HeaderPosition.content strips the app-wide logo/about-button and
      // "new post" button entirely -- they belong to the global chrome,
      // not a bar scoped to just the content area -- leaving only the
      // title.
      Widget? leadingWidget;
      double leadingWidthValue = 0;
      if (!widget.contentMode) {
        // AppBar always starts the title at exactly
        // leadingWidth + titleSpacing, regardless of how much of
        // leadingWidth the leading content actually uses -- so this must
        // stay a *tight* fit for the icon row below (SizedBox(10) + the
        // app icon IconButton (Material's minimum interactive width is
        // 48, wider than its logoSize alone, when logoSize < 48) + the
        // "new post" IconButton (also floors to 48) + the trailing
        // SizedBox(20)), or the title ends up with a visible dead gap
        // before it that grows with any extra margin added here. The row
        // can still need a few pixels more than that at larger toolbar
        // heights (a Material3 AppBar internal quirk, empirically ~1.5px
        // past toolbarHeight~99) -- OverflowBox below absorbs that safely
        // without stealing space from the title position, unlike just
        // inflating this value.
        leadingWidthValue = 10 + math.max(48, logoSize) + 48 + 20;
        leadingWidget = OverflowBox(
          maxWidth: leadingWidthValue + 24,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 10),
            Consumer<ConnStateModel>(builder: (context, connState, child) {
              var connStateTagKey = connState.state.state;
              if (connStateTagKey == connStateOnline &&
                  connState.suggestedVersion != "") {
                connStateTagKey = connStateUpdate;
              }
              return Stack(children: [
                IconButton(
                    tooltip: "About Bison Relay",
                    splashRadius: 20,
                    // IconButton's iconSize reliably constrains an
                    // Icon/ImageIcon, but a plain Image (like this logo)
                    // doesn't consult IconTheme at all -- left
                    // unconstrained, it was sizing itself based on
                    // whatever space happened to be available, which
                    // grows as the header's height setting increases.
                    // BisonRelayLogo forces it to a fixed size (now
                    // user-configurable via logoSize), preserving the
                    // asset's true (non-square) aspect ratio, regardless
                    // of the surrounding toolbar height.
                    iconSize: logoSize,
                    onPressed: () => goToAbout(context),
                    icon: BisonRelayLogo(size: logoSize)),
                _connStateStyles[connStateTagKey]?.tag ??
                    const SizedBox(width: 100),
              ]);
            }),
            IconButton(
                splashRadius: 20,
                tooltip: "Create a new post",
                onPressed: () => goToNewPost(context),
                iconSize: 20,
                icon: const Icon(size: 20, Icons.mode)),
            const SizedBox(width: 20),
          ]),
        );
      }

      return AppBar(
          titleSpacing: headerStyle.paddings.left,
          title: titleWidget,
          centerTitle: centerTitle,
          toolbarHeight: headerStyle.height,
          leadingWidth: leadingWidthValue,
          automaticallyImplyLeading: !widget.contentMode,
          backgroundColor: headerOverridden
              ? Colors.transparent
              : (hasHotAudio || hasLiveRTCSess ? bgColorAnim.value : null),
          leading: leadingWidget);
    }

    List<ChatMenuItem?> contextMenu = [];
    if (mainMenu.activeMenu.routeName == ChatsScreen.routeName) {
      contextMenu = buildChatContextMenu(navKey);
    }

    return AppBar(
        leadingWidth: 60,
        titleSpacing: 0.0,
        title: titleWidget,
        centerTitle: centerTitle,
        toolbarHeight: headerStyle.height,
        backgroundColor: headerOverridden
            ? Colors.transparent
            : (hasHotAudio || hasLiveRTCSess ? bgColorAnim.value : null),
        leading: Builder(builder: (BuildContext context) {
          return InkWell(onTap: () {
            // if (client.ui.showAddressBook.val) { // FIXME: How is this triggered?
            //   client.ui.showAddressBook.val = false;
            // } else
            if (!client.ui.chatSideMenuActive.empty) {
              client.ui.chatSideMenuActive.chat = null;
            } else if (client.ui.showProfile.val) {
              client.ui.showProfile.val = false;
            } else if (!client.ui.overviewActivePath.onActiveBottomTab ||
                client.active != null) {
              !client.ui.chatSideMenuActive.empty
                  ? client.ui.chatSideMenuActive.clear()
                  : client.active = null;
              if (!client.ui.overviewActivePath.onActiveBottomTab) {
                switchScreen(ChatsScreen.routeName);
              }
            } else if (feed.active != null) {
              feed.active = null;
              switchScreen(FeedScreen.routeName, args: PageTabs(0, null, null));
            } else {
              switchScreen(SettingsScreen.routeName);
            }
          }, child: Consumer5<OverviewActivePath, ActiveChatModel, FeedModel,
                  ChatSideMenuActiveModel, ConnStateModel>(
              builder: (context, overviewActivePath, activeChat, feed,
                  chatSideMenuActive, connState, child) {
            var connStateTagKey = connState.state.state;
            if (connStateTagKey == connStateOnline &&
                connState.suggestedVersion != "") {
              connStateTagKey = connStateUpdate;
            }

            return Stack(children: [
              !overviewActivePath.onActiveBottomTab ||
                      !activeChat.empty ||
                      feed.active != null ||
                      !chatSideMenuActive.empty
                  ? const Positioned(
                      left: 25,
                      top: 17,
                      child: Icon(Icons.keyboard_arrow_left_rounded))
                  : Container(
                      margin: const EdgeInsets.all(10),
                      child: SelfAvatar(client)),
              _connStateStyles[connStateTagKey]?.tag ?? const Empty(),
            ]);
          }));
        }),
        actions: [
          // Only render page context menu if the mainMenu ONLY has
          // a context menu OR a sub page menu.
          (mainMenu.activeMenu.subMenuInfo.isNotEmpty && contextMenu.isEmpty) ||
                  (contextMenu.isNotEmpty &&
                      mainMenu.activeMenu.subMenuInfo.isEmpty)
              ? PageContextMenu(
                  menuItem: mainMenu.activeMenu,
                  subMenu: mainMenu.activeMenu.subMenuInfo,
                  contextMenu: contextMenu,
                  navKey: navKey,
                )
              : const Empty()
        ]);
  }

  @override
  Widget build(BuildContext context) {
    if (hasAnimation) {
      return AnimatedBuilder(
          animation: bgColorAnim,
          builder: (context, child) => buildAppBar(context));
    }

    return buildAppBar(context);
  }
}

class _OverviewScreenState extends State<OverviewScreen> {
  ClientModel get client => widget.client;
  AppNotifications get ntfns => widget.ntfns;
  DownloadsModel get down => widget.down;
  FeedModel get feed => widget.feed;
  RealtimeChatModel get rtc => widget.rtc;
  ServerSessionState connState = ServerSessionState.empty();
  GlobalKey<NavigatorState> navKey =
      overviewNavKey; // GlobalKey(debugLabel: "overview nav key");

  bool removeBottomBar = false;
  var selectedIndex = 0;
  bool hasInstantCall = false;

  void connStateChanged() {
    var newConnState = client.connState.state;
    if (newConnState.state != connState.state ||
        newConnState.checkWalletErr != connState.checkWalletErr) {
      setState(() {
        connState = newConnState;
      });
      ntfns.delType(AppNtfnType.walletCheckFailed);
      if (newConnState.state == connStateCheckingWallet &&
          newConnState.checkWalletErr != null) {
        var msg = "LN wallet check failed: ${newConnState.checkWalletErr}";
        ntfns.addNtfn(AppNtfn(AppNtfnType.walletCheckFailed, msg: msg));
      }
    }
  }

  void checkInstantCall() {
    var newInstantCallState = rtc.active.active != null;
    if (newInstantCallState != hasInstantCall) {
      setState(() {
        hasInstantCall = newInstantCallState;
        if (hasInstantCall) {
          removeBottomBar = true;
        } else {
          removeBottomBar = false;
        }
      });
    }
  }

  void goToSubMenuPage(String route, int pageTab) {
    navKey.currentState!
        .pushReplacementNamed(route, arguments: PageTabs(pageTab, null, null));
    Timer(const Duration(milliseconds: 1),
        () async => widget.mainMenu.activePageTab = pageTab);
    Navigator.pop(context);
  }

  // This sets up the listener for notification tapping actions.  When
  // a user taps a chat notification they should be brought to the corresponding
  // chat.  When a user taps a post/comment notification they are brought to the
  // corresponding post.
  void _configureSelectNotificationSubject() {
    NotificationService()
        .selectNotificationStream
        .stream
        .listen((String? payload) async {
      debugPrint("Bruig: Processing system notification (payload $payload)");
      if (payload != null) {
        if (payload.startsWith("chat:") || payload.startsWith("gc:")) {
          switchScreen(ChatsScreen.routeName);
          var uid = payload.split(":")[1];
          bool isGC = payload.startsWith("gc:");
          if (uid.length > 1) {
            client.setActiveByUID(uid, isGC: isGC);
          }
        } else if (payload.contains("post")) {
          var authorPostIDs = payload.split(":");
          if (authorPostIDs.length > 2) {
            var authorID = authorPostIDs[1];
            var pid = authorPostIDs[2];
            var post = feed.getPost(authorID, pid);
            if (post != null) {
              navKey.currentState!.pushReplacementNamed("/feed",
                  arguments: PageTabs(0, null, PostContentScreenArgs(post)));
              feed.active = post;
            }
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    connState = widget.client.connState.state;
    widget.client.connState.addListener(connStateChanged);
    widget.rtc.active.addListener(checkInstantCall);
    _configureSelectNotificationSubject();
  }

  @override
  void didUpdateWidget(OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.connState.removeListener(connStateChanged);
      widget.client.connState.addListener(connStateChanged);
    }
    if (oldWidget.rtc.active != widget.rtc.active) {
      oldWidget.rtc.active.removeListener(checkInstantCall);
      widget.rtc.active.addListener(checkInstantCall);
    }
  }

  @override
  void dispose() {
    widget.client.active?.removeListener(checkInstantCall);
    widget.client.connState.removeListener(connStateChanged);
    NotificationService().selectNotificationStream.close();
    super.dispose();
  }

  void switchScreen(String route) {
    // Do not change screen if already there.
    String currentPath = "";
    navKey.currentState?.popUntil((route) {
      currentPath = route.settings.name ?? "";
      return true;
    });

    if (currentPath == route) {
      return;
    }

    navKey.currentState!.pushReplacementNamed(route);
  }

  void _onItemTapped(int index) {
    setState(() {
      switch (index) {
        case 0:
          switchScreen(ChatsScreen.routeName);
          client.ui.smallScreenActiveTab.active = SmallScreenActiveTab.chat;
          //Navigator.pop(context);
          break;
        case 1:
          switchScreen(FeedScreen.routeName);
          client.ui.smallScreenActiveTab.active = SmallScreenActiveTab.feed;
          //Navigator.pop(context);
          break;
        case 2:
          switchScreen(ViewPageScreen.routeName);
          client.ui.smallScreenActiveTab.active = SmallScreenActiveTab.pages;
          // Navigator.pop(context);
          break;
      }
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    var theme = ThemeNotifier.of(context);
    var headerHeight = theme.areaStyle(ThemeArea.header).height ?? kToolbarHeight;
    // HeaderPosition only applies to the desktop layout -- mobile's leading
    // content is already a totally different (avatar/back-button based)
    // widget with no sidebar to scope a "content" bar against.
    var headerPosition = isScreenSmall
        ? HeaderPosition.top
        : (theme.areaStyle(ThemeArea.header).headerPosition ??
            HeaderPosition.top);

    Widget navigator = Navigator(
      key: navKey,
      observers: [client.ui.overviewRouteObserver],
      initialRoute:
          widget.initialRoute == "" ? ChatsScreen.routeName : widget.initialRoute,
      onGenerateRoute: (settings) {
        String routeName = settings.name!;
        MainMenuItem? menu = widget.mainMenu.menuForRoute(routeName);

        // These updates needs to be on a timer so that they are decoupled to
        // the widget build stack frame.
        Timer(const Duration(milliseconds: 1), () async {
          widget.mainMenu.activeRoute = routeName;
          client.ui.overviewActivePath.route = routeName;
        });

        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => menu != null
              ? (menu.area != null
                  ? ThemedArea(area: menu.area!, child: menu.builder(context))
                  : menu.builder(context))
              : RouteErrorPage(settings.name ?? "", OverviewScreen.routeName),
          transitionDuration: Duration.zero,
          //reverseTransitionDuration: Duration.zero,
          settings: settings,
        );
      },
    );

    Widget contentColumn = headerPosition == HeaderPosition.content
        ? Column(children: [
            SizedBox(
                height: headerHeight,
                child: _MainAppBar(
                    client, feed, widget.rtc, widget.mainMenu, navKey,
                    contentMode: true)),
            Expanded(child: navigator),
          ])
        : navigator;

    return Scaffold(
      key: scaffoldKey,
      appBar: headerPosition == HeaderPosition.top
          ? PreferredSize(
              preferredSize: Size.fromHeight(headerHeight),
              child:
                  _MainAppBar(client, feed, widget.rtc, widget.mainMenu, navKey),
            )
          : null,
      body: SnackbarDisplayer(
          widget.snackBar,
          ThemedArea(
              area: ThemeArea.masterBackground,
              child: Row(children: [
            isScreenSmall
                ? const Empty()
                : Sidebar(widget.client, widget.mainMenu, widget.ntfns, navKey,
                    widget.feed),
            Expanded(child: contentColumn),
          ]))),
      bottomNavigationBar: isScreenSmall && !removeBottomBar
          ? Consumer<ThemeNotifier>(
              builder: (context, theme, _) => BottomNavigationBar(
                    selectedFontSize: fontSize(TextSize.large)!,
                    iconSize: 40,
                    items: <BottomNavigationBarItem>[
                      BottomNavigationBarItem(
                        // Always the same Stack/SidebarSvgIcon element,
                        // regardless of unread state -- only the dot's
                        // visibility toggles. Branching between a Stack and
                        // a bare Container here (as this used to) swaps the
                        // SidebarSvgIcon's element out and back in on every
                        // unread-state change, forcing flutter_svg to
                        // re-mount its underlying VectorGraphic State; that
                        // widget's didChangeDependencies() calls setState()
                        // synchronously on a cache hit, which then fires
                        // mid-build ("setState() or markNeedsBuild() called
                        // during build").
                        icon: Stack(children: [
                          Container(
                              padding: const EdgeInsets.all(3),
                              child: const SidebarSvgIcon(
                                  "assets/icons/icons-menu-chat.svg")),
                          if (client.activeChats.hasUnreadMsgs)
                            const Positioned(
                                top: 1, right: 1, child: RedDotIndicator()),
                        ]),
                        label: 'Chat',
                      ),
                      BottomNavigationBarItem(
                        icon: Stack(children: [
                          Container(
                              padding: const EdgeInsets.all(3),
                              child: const SidebarSvgIcon(
                                  "assets/icons/icons-menu-news.svg")),
                          if (widget.feed.hasUnreadPostsComments)
                            const Positioned(
                                top: 1, right: 1, child: RedDotIndicator()),
                        ]),
                        label: 'Feed',
                      ),
                      BottomNavigationBarItem(
                        icon: Container(
                            padding: const EdgeInsets.all(3),
                            child: const SidebarSvgIcon(
                                "assets/icons/icons-menu-pages.svg")),
                        label: 'Pages',
                      ),
                    ],

                    currentIndex: selectedIndex, //New
                    onTap: _onItemTapped, //New
                  ))
          : null,
    );
  }
}
