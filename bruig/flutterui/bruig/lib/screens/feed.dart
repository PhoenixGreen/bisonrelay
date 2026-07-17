import 'dart:async';

import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
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
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/theme_manager.dart';
import 'package:bruig/models/emoji.dart';

class FeedScreenTitle extends StatelessWidget {
  const FeedScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MainMenuModel, ThemeNotifier>(
        builder: (context, menu, theme, child) {
      if (menu.activePageTab <= 0) {
        return const Txt.L("Feed");
      }
      var idx =
          feedScreenSub.indexWhere((e) => e.pageTab == menu.activePageTab);

      return Txt.L("Feed / ${feedScreenSub[idx].label}");
    });
  }
}

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
    setState(() {
      showPost = args;
      tabIndex = index;
      if (index == 1) _yourPostsResetToken++;
    });
    Timer(const Duration(milliseconds: 1),
        () async => widget.mainMenu.activePageTab = index);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Determine if showing a specific user's posts.
    if (ModalRoute.of(context)?.settings.arguments != null) {
      final args = ModalRoute.of(context)!.settings.arguments as PageTabs;
      tabIndex = args.tabIndex;
      setState(() {
        if (args.userPostList != null) {
          userPostList = args.userPostList;
        }
        if (args.postScreenArgs != null) {
          showPost = args.postScreenArgs;
        }
      });
    }
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

  Widget _minimalSidePanelLayout(BuildContext context, AreaStyle feedStyle) {
    final panel = FeedSidePanel(
      view: FeedView.all,
      sort: FeedSort.newest,
      unreadOnly: false,
      searchController: _dummySearchCtrl,
      showBookmarks: feedStyle.feedBookmarks,
      showHidden: feedStyle.feedHidePosts,
      showDrafts: feedStyle.feedDrafts,
      currentTabIndex: tabIndex,
      onView: _gotoFeedView,
      onSort: (_) {},
      onUnreadOnly: (_) {},
      onSearch: (_) {},
      onYourPosts: () => onItemChanged(1, null),
      onSubscriptions: () => onItemChanged(2, null),
      onNewPost: () => onItemChanged(3, null),
    );
    return LayoutBuilder(builder: (context, c) {
      List<Widget> rowChildren;
      if (c.maxWidth >= 1400) {
        rowChildren = [
          const Spacer(),
          SizedBox(width: 260, child: panel),
          const SizedBox(width: 48),
          SizedBox(width: 780, child: activeTab()),
          const SizedBox(width: 308),
          const Spacer(),
        ];
      } else if (c.maxWidth >= 900) {
        rowChildren = [
          const SizedBox(width: 16),
          SizedBox(width: 260, child: panel),
          const SizedBox(width: 48),
          Expanded(child: activeTab()),
        ];
      } else {
        rowChildren = [Expanded(child: activeTab())];
      }
      return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rowChildren);
    });
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

    // AreaStyle.feedSidePanel replaces this screen's own sub-menu
    // everywhere: tabs 0/1 (All posts/Your Posts) render their own full
    // panel inline (FeedPosts owns that state), while Subscriptions/New
    // Post/detail views get a minimal nav-only panel instead, so the
    // sidebar experience stays consistent across the whole Feed screen
    // rather than falling back to the old plain tab list.
    var feedStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.feed);
    bool feedSidePanel = feedStyle.feedSidePanel;
    bool viewingPost = showPost != null;
    bool onOwnPanelTab =
        (tabIndex == 0 || tabIndex == 1) && !viewingPost && !hasArgs;

    if (feedSidePanel && !isScreenSmall) {
      // Reading a single post: optionally drop the sidebar entirely for a
      // more focused reading experience, instead of falling back to the
      // minimal nav-only panel.
      if (viewingPost && feedStyle.feedHideSidebarOnPost) {
        return ScreenWithChatSideMenu(client, activeTab());
      }
      return ScreenWithChatSideMenu(
          client,
          onOwnPanelTab
              ? activeTab()
              : _minimalSidePanelLayout(context, feedStyle));
    }

    return ScreenWithChatSideMenu(
        client,
        !isScreenSmall
            ? SecondarySideMenuLayout(
                // Matches ln_management.dart/manage_content_screen.dart's
                // width -- left unset here it fell back to
                // SecondarySideMenu's 120 default, too narrow for
                // "Subscriptions" to fit on one line.
                width: 140,
                storageKey: "feed",
                items: feedBarItems(onItemChanged, tabIndex),
                // Detail views that don't need the tab list: reading a
                // single post/user-post (showPost set) or composing a new
                // one (tabIndex 3). hasArgs alone only reflects the route's
                // *initial* navigation arguments, so it misses these once
                // the user navigates within the already-mounted screen.
                isDetail: hasArgs || showPost != null || tabIndex == 3,
                // Distinguishes one detail view from the next (e.g. post A
                // vs. post B) so a manual reopen of the submenu doesn't
                // leak across into an unrelated detail view.
                detailKey: showPost ?? tabIndex,
                content: activeTab())
            : activeTab());
  }
}
