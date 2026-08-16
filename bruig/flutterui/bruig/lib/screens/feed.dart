import 'dart:async';

import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/plugin_system/writing_tools/writing_nav.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_screen.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/feed/user_posts.dart';
import 'package:bruig/screens/overview.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/screens/feed/feed_posts.dart';
import 'package:bruig/components/feed_bar.dart';
import 'package:bruig/screens/feed/post_content.dart';
import 'package:bruig/screens/feed/new_post.dart';
import 'package:bruig/screens/feed/post_lists.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/models/emoji.dart';

class FeedScreenTitle extends StatelessWidget {
  const FeedScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MainMenuModel, ThemeNotifier>(
        builder: (context, menu, theme, child) {
      // The name the menu currently gives this destination, so renaming it
      // renames the heading with it. Only the page's own part; the sub-page
      // after the slash is named by the sidebar, not the main menu.
      var name = menu.headerLabel(FeedScreen.routeName) ?? "Feed";
      if (menu.activePageTab <= 0) {
        return Txt.L(name);
      }
      var idx =
          feedScreenSub.indexWhere((e) => e.pageTab == menu.activePageTab);

      return Txt.L("$name / ${feedScreenSub[idx].label}");
    });
  }
}

/// kNewPostTab is the Feed's compose tab, named because two places have to
/// agree on it: the tab list that offers it, and the redirect that sends it
/// to the Writing section when there is one.
const int kNewPostTab = 3;

class FeedScreen extends StatefulWidget {
  static const routeName = '/feed';

  // Goes to the screen that shows the user's posts.
  static void showUsersPosts(BuildContext context, ChatModel chat) =>
      Navigator.of(context).pushReplacementNamed(FeedScreen.routeName,
          arguments: PageTabs(4, chat, null));

  // Goest to the screen that shows a specific post.
  static void showPost(BuildContext context, FeedPostModel post) =>
      Navigator.of(context).pushReplacementNamed(FeedScreen.routeName,
          arguments: PageTabs(0, null, PostContentScreenArgs(post)));

  final int tabIndex;
  final MainMenuModel mainMenu;
  final TypingEmojiSelModel typingEmoji;
  const FeedScreen(this.mainMenu, this.typingEmoji,
      {super.key, this.tabIndex = 0});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  ChatModel? userPostList;
  int tabIndex = 0;
  PostContentScreenArgs? showPost;

  GlobalKey<NavigatorState> navKey = GlobalKey(debugLabel: "overview nav key");

  // Dummy search controller for the minimal side panel shown on tabs that
  // don't own a post list (Subscriptions, New Post, and any post/user-post
  // detail view) -- search/sort/filter don't apply there, only the nav
  // shortcuts do, but AreaStyle.feedSidePanel still needs to render
  // *something* consistent instead of the old sub-menu.
  final TextEditingController _dummySearchCtrl = TextEditingController();

  // Bumped every time "Your Posts" is navigated to, forcing a fresh
  // FeedPosts instance (and so a fresh FeedView.all default) via its key.
  // Without this, Your Posts would keep whatever Bookmarks/Hidden/Drafts
  // sub-view was last selected *while on that tab*, making the Your Posts
  // link look like it "stopped working" until you bounced through All
  // Posts first. All posts doesn't need this -- browsing its own
  // Bookmarks/Hidden/Drafts sub-views and having them persist there is
  // expected, since those are part of that tab's own experience.
  int _yourPostsResetToken = 0;

  Widget activeTab() {
    switch (tabIndex) {
      case 0:
        if (showPost == null) {
          return Consumer2<FeedModel, ClientModel>(
              key: const ValueKey('feed-tab-all'),
              builder: (context, feed, client, child) =>
                  FeedPosts(feed, client, onItemChanged, false));
        } else {
          return PostContentScreen(showPost as PostContentScreenArgs,
              onItemChanged, widget.typingEmoji);
        }
      case 1:
        if (showPost == null) {
          return Consumer2<FeedModel, ClientModel>(
            key: ValueKey('feed-tab-own-$_yourPostsResetToken'),
            builder: (context, feed, client, child) =>
                FeedPosts(feed, client, onItemChanged, true),
          );
        } else {
          return PostContentScreen(showPost as PostContentScreenArgs,
              onItemChanged, widget.typingEmoji);
        }
      case 2:
        return Consumer<ClientModel>(
            builder: (context, client, child) => PostListsScreen(client));
      case 3:
        return Consumer<FeedModel>(
            builder: (context, feed, child) => NewPostScreen(feed));
      case 4:
        if (showPost == null && userPostList != null) {
          return Consumer2<FeedModel, ClientModel>(
              builder: (context, feed, client, child) =>
                  UserPosts(userPostList!, feed, client, onItemChanged));
        } else if (showPost != null) {
          return PostContentScreen(showPost as PostContentScreenArgs,
              onItemChanged, widget.typingEmoji);
        } else {
          return Text("Active tab $tabIndex without post or userPostList");
        }
    }
    return Text("Active is $tabIndex");
  }

  void onItemChanged(int index, PostContentScreenArgs? args) {
    // New Post, with the writing tools switched on, is the Writing section
    // -- the same destination the navigation carries, reached from the place
    // somebody looking to write a post actually looks. This screen's own New
    // Post tab is what is left for everybody else; see new_post.dart.
    //
    // A redirect rather than a hidden item, so the link stays where it has
    // always been and simply leads somewhere better.
    if (index == kNewPostTab && hasWritingPage(widget.mainMenu)) {
      Navigator.of(context).pushReplacementNamed(WritingScreen.routeName);
      return;
    }
    setState(() {
      showPost = args;
      tabIndex = index;
      Provider.of<FeedModel>(context, listen: false).lastTab = index;
      if (index == 1) _yourPostsResetToken++;
    });
    Timer(const Duration(milliseconds: 1),
        () async => widget.mainMenu.activePageTab = index);
  }

  @override
  void initState() {
    super.initState();
    // Where the reader left off, which is not this screen's to forget: the
    // screen goes when the route does.
    //
    // Except the compose tab, once the Writing section exists: a session
    // that ended on New Post, and a plugin enabled since, would otherwise
    // reopen the composer this page no longer offers. Corrected here rather
    // than redirected, because initState is too early to navigate from.
    tabIndex = Provider.of<FeedModel>(context, listen: false).lastTab;
    if (tabIndex == kNewPostTab && hasWritingPage(widget.mainMenu)) {
      tabIndex = 0;
    }
  }

  // _appliedRouteArgs is the PageTabs this screen has already navigated to,
  // so the route's arguments are applied once rather than on every rebuild.
  //
  // Reported: after commenting on a post, clicking "New Post" did nothing --
  // it opened and was replaced by the post again within the frame -- and
  // going to another screen and back fixed it.
  //
  // didChangeDependencies runs whenever *any* inherited widget this State
  // depends on changes, not only when the route does. The arguments describe
  // where the screen was told to open, so re-applying them silently undoes
  // every navigation made within the screen since: tapping "New Post" set
  // tabIndex to 3, the writing sidebar's controller notified a frame later
  // when the composer offered itself for review, and this put the reader
  // straight back on the post the route had named.
  //
  // The bug needed a route carrying a post to be visible at all, which is
  // why it only appeared after reading or commenting on one -- and why
  // navigating away and back, to a route with no post in its arguments,
  // cleared it.
  Object? _appliedRouteArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    var args = ModalRoute.of(context)?.settings.arguments;
    // Compared by identity: each navigation builds a fresh PageTabs, and
    // arriving at the same destination twice is a new instance.
    if (args is! PageTabs || identical(args, _appliedRouteArgs)) return;
    _appliedRouteArgs = args;

    setState(() {
      tabIndex = args.tabIndex;
      Provider.of<FeedModel>(context, listen: false).lastTab = args.tabIndex;
      // Determine if showing a specific user's posts.
      if (args.userPostList != null) {
        userPostList = args.userPostList;
      }
      if (args.postScreenArgs != null) {
        showPost = args.postScreenArgs;
      }
    });
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _dummySearchCtrl.dispose();
    super.dispose();
  }

  // Jump to the main "All posts" tab, matching what tapping a FEED-section
  // nav item means when there's no post-list-owning FeedPosts around to
  // interpret it (Subscriptions/New Post/detail views).
  void _gotoFeedView(FeedView v) => onItemChanged(0, null);

  /// _feedSidePanel is this screen's own navigation panel, for the tabs that
  /// do not own a post list of their own to draw it from.
  FeedSidePanel _feedSidePanel(AreaStyle feedStyle) => FeedSidePanel(
        view: FeedView.all,
        sort: FeedSort.newest,
        unreadOnly: false,
        searchController: _dummySearchCtrl,
        showSearch: true,
        framed: true,
        showBookmarks: feedStyle.feedCardActions,
        showHidden: feedStyle.feedCardActions,
        showDrafts: feedStyle.feedInlineComposer,
        currentTabIndex: tabIndex,
        onView: _gotoFeedView,
        onSort: (_) {},
        onUnreadOnly: (_) {},
        onSearch: (_) {},
        onYourPosts: () => onItemChanged(1, null),
        onSubscriptions: () => onItemChanged(2, null),
        onNewPost: () => onItemChanged(3, null),
      );

  Widget _minimalSidePanelLayout(BuildContext context, AreaStyle feedStyle) {
    final panel = _feedSidePanel(feedStyle);
    // Resizes with -- and to the same width as -- the full panel on the
    // All Posts/Your Posts tabs: same storageKey, so dragging either one
    // moves both and the panel doesn't jump width when switching tabs.
    var sidebarStyle = ThemeNotifier.of(context)
            .areaStyle(ThemeArea.subMenuTabBar)
            .subMenuStyle ??
        SubMenuStyle.alwaysVisible;
    var resizable = sidebarStyle == SubMenuStyle.resizable;

    // Same Content Area treatment SecondarySideMenuLayout gives every other
    // screen's content -- this layout doesn't go through it, so it applies
    // it itself.
    var content = contentAreaFrame(ThemeNotifier.of(context), activeTab());

    Widget layout(double panelWidth, Widget? handle) {
      return LayoutBuilder(builder: (context, c) {
        if (sidebarStyle == SubMenuStyle.collapsed) {
          ClientModel.of(context, listen: false)
              .ui
              .collapsedSidebar
              .register((context) => panel, kCollapsedSidebarWidth);
          return content;
        }
        const gap = 0.0;
        List<Widget> rowChildren;
        if (c.maxWidth >= 1400) {
          rowChildren = [
            const Spacer(),
            SizedBox(width: panelWidth, child: panel),
            if (handle != null) handle,
            SizedBox(width: gap),
            SizedBox(width: 780, child: content),
            const SizedBox(width: 308),
            const Spacer(),
          ];
        } else if (c.maxWidth >= 900) {
          rowChildren = [
            SizedBox(width: panelWidth, child: panel),
            if (handle != null) handle,
            SizedBox(width: gap),
            Expanded(child: content),
          ];
        } else {
          // Too narrow for a column of its own: hand the panel over as a
          // drawer, opened by re-tapping this page in the main navigation
          // (see CollapsedSidebarModel). Registering here rather
          // than dropping it is what gives this panel the same way back as
          // every other sidebar -- it used to just disappear.
          ClientModel.of(context, listen: false)
              .ui
              .collapsedSidebar
              .register((context) => panel, kCollapsedSidebarWidth);
          return content;
        }
        ClientModel.of(context, listen: false).ui.collapsedSidebar.unregister();
        return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowChildren);
      });
    }

    if (!resizable) return layout(260, null);
    return ResizableSidebar(
      storageKey: "feedPanel",
      defaultWidth: 260,
      builder: (context, width, handle) => layout(width, handle),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    bool hasArgs = false;
    if (ModalRoute.of(context)?.settings.arguments is PageTabs) {
      var args = ModalRoute.of(context)?.settings.arguments as PageTabs;
      hasArgs = args.postScreenArgs != null || args.userPostList != null;
    }

    var client = Provider.of<ClientModel>(context);

    var feedStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.feed);
    bool feedSidePanel = feedStyle.feedSidePanel;

    // AreaStyle.feedSidePanel replaces this screen's own sub-menu
    // everywhere: tabs 0/1 (All posts/Your Posts) render their own full
    // panel inline (FeedPosts owns that state), while Subscriptions/New
    // Post/detail views get a minimal nav-only panel instead, so the
    // sidebar experience stays consistent across the whole Feed screen
    // rather than falling back to the old plain tab list.
    bool viewingPost = showPost != null;
    bool onOwnPanelTab =
        (tabIndex == 0 || tabIndex == 1) && !viewingPost && !hasArgs;

    if (feedSidePanel && !isScreenSmall) {
      // Reading a single post: drop the sidebar entirely for a more focused
      // read, instead of falling back to the minimal nav-only panel.
      if (viewingPost && feedStyle.feedHideSidebarOnPost) {
        // Still the Content Area, even with no sidebar beside it -- a
        // border around the reading area shouldn't vanish just because the
        // panel did.
        return ScreenWithChatSideMenu(
            client, contentAreaFrame(ThemeNotifier.of(context), activeTab()));
      }
      return ScreenWithChatSideMenu(
          client,
          onOwnPanelTab
              ? activeTab()
              : _minimalSidePanelLayout(context, feedStyle));
    }

    return ScreenWithChatSideMenu(
        client,
        // Deliberately not short-circuited to a bare activeTab() on a small
        // screen: below SecondarySideMenuLayout's collapse width it already
        // renders content-only, but it also hands its item list to
        // CollapsedSidebarModel on the way -- which is what gives the mobile
        // navigation's re-tap gesture (see the Mobile theme area) something to
        // slide in, and what the mobile header's three-dot menu used to be the
        // only route to.
        SecondarySideMenuLayout(
            // Matches ln_management.dart/manage_content_screen.dart's
            // width -- left unset here it fell back to
            // SecondarySideMenu's 120 default, too narrow for
            // "Subscriptions" to fit on one line.
            storageKey: "feed",
            items: feedBarItems(onItemChanged, tabIndex),
            // Detail views that don't need the tab list: reading a
            // single post/user-post (showPost set). hasArgs alone only
            // reflects the route's *initial* navigation arguments, so it
            // misses these once the user navigates within the
            // already-mounted screen.
            //
            // New Post is deliberately not one of them: it is a tab of this
            // screen like the other three, and it keeps this screen's
            // sidebar exactly as they do.
            isDetail: hasArgs || showPost != null,
            // Distinguishes one detail view from the next (e.g. post A
            // vs. post B) so a manual reopen of the submenu doesn't
            // leak across into an unrelated detail view.
            detailKey: showPost ?? tabIndex,
            content: activeTab()));
  }
}
