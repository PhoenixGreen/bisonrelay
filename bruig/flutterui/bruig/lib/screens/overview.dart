import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/components/clipper.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/mobile_nav_bar.dart';
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

// _CollapsedSidebarDrawer paints whichever sidebar the current screen has
// handed over, sliding it in from the left edge over everything else. It
// renders nothing at all until one is both registered and opened.
class _CollapsedSidebarDrawer extends StatelessWidget {
  final ClientModel client;
  const _CollapsedSidebarDrawer(this.client);

  @override
  Widget build(BuildContext context) {
    var collapsed = client.ui.collapsedSidebar;
    return ListenableBuilder(
      listenable: collapsed,
      builder: (context, _) {
        if (!collapsed.available) return const Empty();
        var builder = collapsed.builder!;
        return Stack(fit: StackFit.expand, children: [
          // A tap anywhere off the drawer puts it away. IgnorePointer while
          // closed so the scrim doesn't swallow taps meant for the content
          // underneath it. Positioned.fill because a ColoredBox has no size
          // of its own -- left to size itself the whole drawer collapsed to
          // nothing and the button appeared to do nothing at all.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !collapsed.open,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: collapsed.open ? 1 : 0,
                child: GestureDetector(
                  onTap: collapsed.close,
                  child: const ColoredBox(color: Color(0x99000000)),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            top: 0,
            bottom: 0,
            left: collapsed.open ? 0 : -collapsed.width,
            width: collapsed.width,
            child: CollapsedSidebarScope(child: Builder(builder: builder)),
          ),
        ]);
      },
    );
  }
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
  const _MainAppBar(
      this.client, this.feed, this.rtc, this.mainMenu, this.navKey);

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

  // Where the header's self-avatar was tapped from, so a second tap can go
  // back to it (see AreaStyle.mobileAvatarSecondTapCloses). Both the route
  // and, when that route was Settings, the page within it -- tapping the
  // avatar while already in Settings moves between pages rather than
  // between screens, and "back" has to mean the same thing either way.
  // Null until the avatar has actually taken you somewhere.
  String? _returnRoute;
  String? _returnSettingsPage;

  // _seenRoute/_selfNavPending invalidate that memory when the page changes
  // under it. Navigating by any other means -- the bottom bar, the back
  // arrow -- has to clear it: without that, arriving at Settings from the
  // navigation bar would look exactly like the avatar having brought you
  // there, and the next tap would jump to wherever it was last tapped from.
  //
  // The flag is needed because the avatar's own navigation lands the same
  // way: overviewActivePath.route is updated a tick after the route is
  // pushed (see OverviewScreen's route generator), so the change is only
  // observed here on a later build, by which time nothing else says who
  // caused it.
  String _seenRoute = "";
  bool _selfNavPending = false;

  void _noteRoute(String route) {
    if (route == _seenRoute) return;
    _seenRoute = route;
    if (_selfNavPending) {
      _selfNavPending = false;
      return;
    }
    _returnRoute = null;
    _returnSettingsPage = null;
  }

  // goToSelf is where the header's self-avatar leads: your own account --
  // avatar, name and identity. Settings otherwise opens on whichever page
  // you left it on (SettingsScreen follows settingsNav), so this is a
  // matter of naming the page as well as the screen. Already being *in*
  // Settings is the case that needs it most: there the screen doesn't
  // change at all, only the page.
  void goToSelf(bool account) {
    var route = client.ui.overviewActivePath.route;
    var page = client.ui.settingsNav.page;
    var target = account ? "Account" : page;
    // Already on exactly what the avatar leads to; nothing to remember and
    // nothing to do.
    if (route == SettingsScreen.routeName && page == target) return;

    _returnRoute = route;
    _returnSettingsPage = page;
    // Only a real route change needs claiming; moving between Settings
    // pages leaves the route where it is.
    if (route != SettingsScreen.routeName) _selfNavPending = true;
    if (account) {
      client.ui.settingsNav.page = "Account";
      client.ui.settingsTitle.title = "Account";
    }
    switchScreen(SettingsScreen.routeName);
  }

  // canLeaveSelf is "the avatar put you here, so it can take you back".
  bool get canLeaveSelf =>
      _returnRoute != null &&
      client.ui.overviewActivePath.route == SettingsScreen.routeName;

  // leaveSelf is goToSelf in reverse. Coming back from Account to another
  // Settings page is a page change, not a navigation -- switchScreen would
  // see the route it's already on and do nothing at all.
  void leaveSelf() {
    var route = _returnRoute;
    var page = _returnSettingsPage;
    _returnRoute = null;
    _returnSettingsPage = null;
    if (route == null) return;

    if (route == SettingsScreen.routeName) {
      if (page != null) {
        client.ui.settingsNav.page = page;
        client.ui.settingsTitle.title = page;
      }
      return;
    }
    _selfNavPending = true;
    switchScreen(route);
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

    var appBar =
        _buildInnerAppBar(context, isScreenSmall, theme, headerOverridden);

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
              // The palette's Header Background is the header's default
              // fill; the area's own Background setting still overrides it.
              tokenColor: theme.activePreset?.headerBackground,
              child: const Empty())),
      appBar,
    ]);
  }

  AppBar _buildInnerAppBar(BuildContext context, bool isScreenSmall,
      ThemeNotifier theme, bool headerOverridden) {
    var headerStyle = theme.areaStyle(ThemeArea.header);
    Widget titleWidget = headerStyle.hideHeaderTitle ||
            headerStyle.contentAlign == ContentAlign.hidden
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
      // The leading icons are drawn the same way wherever the header sits
      // -- HeaderPosition.content used to strip them, but which elements
      // the header carries is now the per-element switches' decision, not
      // the position's. With every one of them off there's no leading
      // content at all, and the title starts at the very edge.
      var showLogo = !headerStyle.hideHeaderLogo;
      var showNewPost = !headerStyle.hideHeaderNewPost;
      Widget? leadingWidget;
      double leadingWidthValue = 0;
      if (showLogo || showNewPost) {
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
        // inflating this value. Each switched-off icon drops out of the
        // sum too, so the title closes up the gap it leaves behind.
        leadingWidthValue = 10 +
            (showLogo ? math.max(48, logoSize) : 0) +
            (showNewPost ? 48 : 0) +
            20;
        leadingWidget = OverflowBox(
          maxWidth: leadingWidthValue + 24,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 10),
            if (showLogo)
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
            if (showNewPost)
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
          // Moot while there's leading content of our own; what it stops
          // is AppBar quietly substituting a back/drawer button once every
          // leading element has been switched off.
          automaticallyImplyLeading: leadingWidget != null,
          backgroundColor: headerOverridden
              ? Colors.transparent
              : (hasHotAudio || hasLiveRTCSess ? bgColorAnim.value : null),
          leading: leadingWidget);
    }

    List<ChatMenuItem?> contextMenu = [];
    if (mainMenu.activeMenu.routeName == ChatsScreen.routeName) {
      contextMenu = buildChatContextMenu(navKey);
    }

    var mobileStyle = theme.areaStyle(ThemeArea.mobile);
    // Which destinations the bottom bar is currently carrying -- a
    // theme setting now, so this can't be the hardcoded three it used to
    // be. It's what the leading widget keys off: on a top-level tab that
    // corner is the self-avatar, and anywhere else it's a back arrow.
    var bottomTabRoutes =
        mobileNavItems(mainMenu, mobileStyle).map((e) => e.routeName).toSet();
    bool onBottomTab(String route) => bottomTabRoutes.contains(route);

    // Read here rather than through a Consumer down inside the leading
    // widget: whether that corner has anything in it at all now decides
    // leadingWidth too, which is the AppBar's own property. These are the
    // same five models the leading used to consume.
    var activePath = Provider.of<OverviewActivePath>(context);
    var activeChat = Provider.of<ActiveChatModel>(context);
    var feedModel = Provider.of<FeedModel>(context);
    var chatSideMenuActive = Provider.of<ChatSideMenuActiveModel>(context);
    var connState = Provider.of<ConnStateModel>(context);
    _noteRoute(activePath.route);

    // Switched off, there's no state left for the arrow to appear in.
    var showBack = !mobileStyle.mobileHideBackButton &&
        (!onBottomTab(activePath.route) ||
            !activeChat.empty ||
            feedModel.active != null ||
            !chatSideMenuActive.empty);
    // A conversation puts the other party's avatar at the head of the title
    // on a phone (see ChatsScreenTitle); yours gives way to it rather than
    // the header carrying two.
    var titleHasAvatar =
        activePath.route == ChatsScreen.routeName && !activeChat.empty;
    var showSelfAvatar =
        !mobileStyle.mobileHideSelfAvatar && !titleHasAvatar && !showBack;

    return AppBar(
        // Nothing in the corner means no corner: left at 60 the title
        // would start after an empty inset the width of the avatar that
        // isn't there. This also takes the connection-state tag with it,
        // since that badge is drawn over the leading content -- it's still
        // shown on every screen whose corner does have something in it.
        leadingWidth: showBack || showSelfAvatar ? 60 : 0,
        // Matches the inset the self-avatar sits at in the leading slot (its
        // Container's 10 margin, below), so whatever starts the title with
        // no leading in front of it -- the other party's avatar in a
        // conversation, most visibly -- lines up where yours would have been
        // instead of hard against the screen edge.
        titleSpacing: showBack || showSelfAvatar ? 0.0 : 10.0,
        title: titleWidget,
        centerTitle: centerTitle,
        toolbarHeight: headerStyle.height,
        backgroundColor: headerOverridden
            ? Colors.transparent
            : (hasHotAudio || hasLiveRTCSess ? bgColorAnim.value : null),
        leading: !showBack && !showSelfAvatar
            ? null
            : Builder(builder: (BuildContext context) {
                var connStateTagKey = connState.state.state;
                if (connStateTagKey == connStateOnline &&
                    connState.suggestedVersion != "") {
                  connStateTagKey = connStateUpdate;
                }
                return InkWell(
                    onTap: () {
                      // Tap-again-to-close: the avatar undoes its own last
                      // tap before it does anything else. The right sidebar
                      // first, since that's what it opened most recently,
                      // then the Account page it opened before that.
                      if (mobileStyle.mobileAvatarSecondTapCloses) {
                        if (!client.ui.chatSideMenuActive.empty) {
                          client.ui.chatSideMenuActive.clear();
                          return;
                        }
                        if (client.ui.showProfile.val) {
                          client.ui.showProfile.val = false;
                          return;
                        }
                        if (canLeaveSelf) {
                          leaveSelf();
                          return;
                        }
                      }
                      // With the back arrow switched off the corner is only
                      // ever the avatar, so it does the one thing an avatar
                      // should rather than silently retracing the back chain
                      // below it.
                      if (mobileStyle.mobileHideBackButton) {
                        goToSelf(mobileStyle.mobileAvatarOpensProfile);
                        return;
                      }
                      // if (client.ui.showAddressBook.val) { // FIXME: How is this triggered?
                      //   client.ui.showAddressBook.val = false;
                      // } else
                      if (!client.ui.chatSideMenuActive.empty) {
                        client.ui.chatSideMenuActive.chat = null;
                      } else if (client.ui.showProfile.val) {
                        client.ui.showProfile.val = false;
                      } else if (!onBottomTab(
                              client.ui.overviewActivePath.route) ||
                          client.active != null) {
                        !client.ui.chatSideMenuActive.empty
                            ? client.ui.chatSideMenuActive.clear()
                            : client.active = null;
                        if (!onBottomTab(client.ui.overviewActivePath.route)) {
                          switchScreen(ChatsScreen.routeName);
                        }
                      } else if (feed.active != null) {
                        feed.active = null;
                        switchScreen(FeedScreen.routeName,
                            args: PageTabs(0, null, null));
                      } else {
                        goToSelf(mobileStyle.mobileAvatarOpensProfile);
                      }
                    },
                    child: Stack(children: [
                      showBack
                          ? const Positioned(
                              left: 25,
                              top: 17,
                              child: Icon(Icons.keyboard_arrow_left_rounded))
                          : Container(
                              margin: const EdgeInsets.all(10),
                              child: SelfAvatar(client)),
                      _connStateStyles[connStateTagKey]?.tag ?? const Empty(),
                    ]));
              }),
        // Without a leading of our own, AppBar would substitute a back
        // button -- exactly the control the corner was just cleared of.
        automaticallyImplyLeading: showBack || showSelfAvatar,
        actions: [
          // Only render page context menu if the mainMenu ONLY has
          // a context menu OR a sub page menu -- and not at all when the
          // Mobile area's re-tap gesture is on, which reaches the same
          // page menu through the sidebar it opens.
          if (!mobileStyle.mobileTapOpensSidebar &&
              ((mainMenu.activeMenu.subMenuInfo.isNotEmpty &&
                      contextMenu.isEmpty) ||
                  (contextMenu.isNotEmpty &&
                      mainMenu.activeMenu.subMenuInfo.isEmpty)))
            PageContextMenu(
              menuItem: mainMenu.activeMenu,
              subMenu: mainMenu.activeMenu.subMenuInfo,
              contextMenu: contextMenu,
              navKey: navKey,
            )
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
  bool hasInstantCall = false;

  // The conversation a re-tap of Chat in the mobile navigation covered with
  // the chat list, so the next one can put it back (see _onNavTapped).
  // Stored by ID, not as a ChatModel, so a chat removed while the list is
  // open can't be reopened. Null until a conversation has been opened at
  // all, which is why a freshly launched app's second tap does nothing.
  String? _lastMobileChatID;

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

  // _onNavTapped is the bottom bar's tap handler, and the mobile
  // counterpart of Sidebar.switchScreen -- same three outcomes, and for the
  // same reasons: go there; or, if you're already there, go back to that
  // page's own list of things (only when the Mobile area's setting asks for
  // it, since on a phone this is the only tap that destination has); and
  // never leave the drawer open over a page you've just navigated away
  // from.
  //
  // Which item reads as selected isn't tracked here at all -- the bar
  // resolves it from MainMenuModel's active route, so it stays right when
  // something other than a tap changes the page.
  void _onNavTapped(String route) {
    String currentPath = "";
    navKey.currentState?.popUntil((route) {
      currentPath = route.settings.name ?? "";
      return true;
    });

    var collapsed = client.ui.collapsedSidebar;
    if (currentPath == route) {
      var tapOpens = ThemeNotifier.of(context, listen: false)
          .areaStyle(ThemeArea.mobile)
          .mobileTapOpensSidebar;
      if (!tapOpens) return;

      // The right sidebar -- the profile / manage-group-chat panel, which
      // opens over Chat and Feed alike -- is the innermost thing a re-tap
      // can put away, so it goes first and on its own: closing it leaves
      // you on the conversation or the post it was covering, rather than
      // walking all the way back to the list in one tap.
      if (!client.ui.chatSideMenuActive.empty) {
        client.ui.chatSideMenuActive.clear();
        return;
      }
      if (client.ui.showProfile.val) {
        client.ui.showProfile.val = false;
        return;
      }

      // Reading a post is Feed's equivalent of being in a conversation, so
      // a re-tap goes back to the feed itself. Unlike Chat this doesn't
      // toggle back into the post: the feed is a list you scroll, and the
      // post you were reading is sitting in it.
      if (route == FeedScreen.routeName && feed.active != null) {
        feed.active = null;
        navKey.currentState!
            .pushReplacementNamed(route, arguments: PageTabs(0, null, null));
        return;
      }

      // Chat is the one destination whose "list" half is a whole page on a
      // phone rather than a sidebar (see ChatsScreen.build), and a better
      // one than a drawer would be -- it carries the New Message and New
      // Group Chat buttons. So a re-tap there shows that list instead of
      // sliding anything in, and re-tapping again puts it away.
      //
      // "Away" means back to the conversation it covered, which is what
      // makes this the same toggle every other destination's re-tap is
      // rather than a one-way trip: without remembering it, closing the
      // list would have to leave you on the list. Only a fresh launch,
      // where no conversation has been opened yet, has nothing to go back
      // to -- there the second tap simply does nothing.
      if (route == ChatsScreen.routeName) {
        if (client.active != null) {
          _lastMobileChatID = client.active!.id;
          client.active = null;
        } else if (_lastMobileChatID != null) {
          // Resolved fresh rather than held as a ChatModel: the chat may
          // have been removed while the list was open, and reopening one
          // that no longer exists is worse than the tap doing nothing.
          var chat = client.getExistingChat(_lastMobileChatID!);
          if (chat != null) {
            client.active = chat;
          } else {
            _lastMobileChatID = null;
          }
        }
        return;
      }
      // available is false on a page with no sidebar of its own, where
      // there's simply nothing to open.
      if (collapsed.available) collapsed.toggle();
      return;
    }

    collapsed.close();
    navKey.currentState!.pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    var theme = ThemeNotifier.of(context);
    var headerHeight =
        theme.areaStyle(ThemeArea.header).height ?? kToolbarHeight;
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
      initialRoute: widget.initialRoute == ""
          ? ChatsScreen.routeName
          : widget.initialRoute,
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
          // Every page is framed by Dual Panel -- its sidebar and content
          // as one region -- rather than each page carrying a background
          // and border of its own. contentAreaFrame's gate applies here too:
          // an untouched area still resolves to an opaque box, so it's only
          // wrapped once it's been given something.
          pageBuilder: (context, animation, secondaryAnimation) => menu != null
              ? dualPanelFrame(ThemeNotifier.of(context), menu.builder(context))
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
                    client, feed, widget.rtc, widget.mainMenu, navKey)),
            Expanded(child: navigator),
          ])
        : navigator;

    return Scaffold(
      key: scaffoldKey,
      appBar: headerPosition == HeaderPosition.top
          ? PreferredSize(
              preferredSize: Size.fromHeight(headerHeight),
              child: _MainAppBar(
                  client, feed, widget.rtc, widget.mainMenu, navKey),
            )
          : null,
      body: SnackbarDisplayer(
          widget.snackBar,
          ThemedArea(
              area: ThemeArea.masterBackground,
              child: Stack(fit: StackFit.expand, children: [
                Row(children: [
                  isScreenSmall
                      ? const Empty()
                      : Sidebar(widget.client, widget.mainMenu, widget.ntfns,
                          navKey, widget.feed),
                  Expanded(child: contentColumn),
                ]),
                // The narrow-window sidebar drawer. It's painted here, above
                // the Row, so it can slide over the main navigation -- the
                // screen that owns the sidebar sits inside the content area
                // and could only ever draw to the right of it. See
                // CollapsedSidebarModel.
                Positioned.fill(child: _CollapsedSidebarDrawer(widget.client)),
              ]))),
      bottomNavigationBar: isScreenSmall && !removeBottomBar
          ? MobileNavBar(client: client, feed: widget.feed, onTap: _onNavTapped)
          : null,
    );
  }
}
