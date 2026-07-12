import 'dart:convert';

import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/pay_tip.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/screens/feed/post_content.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:bruig/components/md_elements.dart';

class _AvatarOrUnread extends StatelessWidget {
  final ClientModel client;
  final bool hasUnread;
  final String uid;
  final String nick;
  const _AvatarOrUnread(this.client, this.uid, this.hasUnread, this.nick);

  @override
  Widget build(BuildContext context) {
    return hasUnread
        ? const Icon(Icons.new_releases_outlined, color: Colors.amber)
        : UserAvatarFromID(client, uid, nick: nick);
  }
}

class FeedPostW extends StatefulWidget {
  final FeedModel feed;
  final FeedPostModel post;
  final ChatModel? author;
  final ChatModel? from;
  final ClientModel client;
  final Function onTabChange;
  const FeedPostW(this.feed, this.post, this.author, this.from, this.client,
      this.onTabChange,
      {super.key});

  @override
  State<FeedPostW> createState() => _FeedPostWState();
}

class _NewCommentTag extends StatelessWidget {
  const _NewCommentTag();

  @override
  Widget build(BuildContext context) {
    return const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.new_releases_outlined, color: Colors.amber),
      SizedBox(width: 10),
      Text("New Comments",
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: 12, // fontSize(TextSize.small),
            color: Colors.amber,
          ))
    ]);
  }
}

class _FeedPostWState extends State<FeedPostW> {
  FeedModel get feed => widget.feed;
  FeedPostModel get post => widget.post;
  showContent(BuildContext context) {
    feed.active = post;
    widget.onTabChange(0, PostContentScreenArgs(post));
  }

  void authorUpdated() => setState(() {});

  int? _commentCount;

  Future<void> _loadCommentCount() async {
    try {
      await post.readComments();
      if (mounted) setState(() => _commentCount = post.comments.length);
    } catch (_) {}
  }

  Future<void> _loadFullContent() async {
    if (post.content.isNotEmpty) return;
    try {
      await post.readPost();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  initState() {
    super.initState();
    widget.author?.addListener(authorUpdated);
    if (post.comments.isNotEmpty) _commentCount = post.comments.length;
    _loadCommentCount();
    _loadFullContent();
    FeedBookmarks.instance.ensureLoaded();
    FeedHidden.instance.ensureLoaded();
  }

  @override
  void didUpdateWidget(FeedPostW oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.author?.removeListener(authorUpdated);
    widget.author?.addListener(authorUpdated);
  }

  @override
  void dispose() {
    widget.author?.removeListener(authorUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var hasUnreadComments = post.hasUnreadComments;
    var hasUnreadPost = post.hasUnreadPost;
    var authorNick = widget.author?.nick ?? "";
    var authorID = widget.post.summ.authorID;
    var mine = authorID == widget.client.publicID;
    if (mine) {
      authorNick = "me";
    } else if (authorNick == "") {
      authorNick = widget.post.summ.authorNick;
      if (authorNick == "") {
        authorNick = "[${widget.post.summ.authorID}]";
      }
    }

    var sincePost = formatTerseTime(widget.post.summ.date);
    var feedStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.feed);
    var redesign = feedStyle.feedCardRedesign;
    var cardActions = feedStyle.feedCardActions;
    var bookmarks = feedStyle.feedBookmarks;
    var hidePosts = feedStyle.feedHidePosts;

    if (!redesign) {
      var markdownData = widget.post.summ.title;
      if (widget.post.summ.title.contains("--embed[type=")) {
        // This will pluck the first embed in a post.  Then we can display just
        // that in feedposts without the rest of the post content.
        var firstIndex = widget.post.content.indexOf("--");
        var nextIndex = widget.post.content.indexOf("--", firstIndex + 1);
        markdownData =
            widget.post.content.substring(firstIndex, nextIndex + 2);
      }

      return Card.filled(
          margin: const EdgeInsets.only(right: 15, bottom: 15),
          child: Container(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                // Header row: Avatar, nick and post time.
                Row(children: [
                  SizedBox(
                      width: 28,
                      child: _AvatarOrUnread(
                          widget.client, authorID, hasUnreadPost, authorNick)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(authorNick)),
                  Text(sincePost),
                ]),

                // Second row: post summary.
                Provider<DownloadSource>(
                    create: (context) =>
                        DownloadSource(widget.post.summ.authorID),
                    child: MarkdownArea(markdownData, false)),

                // Third row: read more button.
                const Divider(),
                SizedBox(
                    width: double.infinity,
                    child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 10,
                        children: [
                          hasUnreadComments
                              ? const _NewCommentTag()
                              : const Empty(),
                          OutlinedButton(
                            onPressed: () => showContent(context),
                            child: const Txt.S("Read More"),
                          )
                        ])),
              ])));
    }

    // X-style redesign: full post body (loaded lazily), height-clamped
    // below, never string-truncated so embeds/images render intact.
    final markdownData = widget.post.content.isNotEmpty
        ? widget.post.content
        : widget.post.summ.title;

    return InkWell(
      onTap: () => showContent(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Color(0xFF2F3336), width: 1)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 38,
              child: _AvatarOrUnread(
                  widget.client, authorID, hasUnreadPost, authorNick)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                        child: Text(authorNick,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14.5))),
                    const SizedBox(width: 6),
                    Text("· $sincePost",
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF5F6764))),
                    const Spacer(),
                    if (bookmarks || hidePosts)
                      ListenableBuilder(
                        listenable: FeedHidden.instance,
                        builder: (context, _) {
                          final hidden = FeedHidden.instance.contains(
                              widget.post.summ.from, widget.post.summ.id);
                          return SizedBox(
                            height: 22,
                            width: 28,
                            child: PopupMenuButton<String>(
                              tooltip: "More",
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              position: PopupMenuPosition.under,
                              color: const Color(0xFF15171A),
                              icon: const Icon(Icons.more_horiz,
                                  color: Color(0xFF5F6764)),
                              onSelected: (v) {
                                if (v == "hide") {
                                  FeedHidden.instance.toggle(
                                      widget.post.summ.from,
                                      widget.post.summ.id);
                                } else if (v == "bookmark") {
                                  FeedBookmarks.instance.toggle(
                                      widget.post.summ.from,
                                      widget.post.summ.id);
                                }
                              },
                              itemBuilder: (context) => [
                                if (bookmarks)
                                  PopupMenuItem(
                                    value: "bookmark",
                                    child: Text(
                                        FeedBookmarks.instance.contains(
                                                widget.post.summ.from,
                                                widget.post.summ.id)
                                            ? "Remove bookmark"
                                            : "Bookmark",
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFFF2F4F3))),
                                  ),
                                if (hidePosts)
                                  PopupMenuItem(
                                    value: "hide",
                                    child: Text(
                                        hidden ? "Unhide post" : "Hide post",
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFFF2F4F3))),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  ]),
                  const SizedBox(height: 6),
                  _ClampedContent(
                    maxHeight: 300,
                    onShowMore: () => showContent(context),
                    child: Provider<DownloadSource>(
                        create: (context) =>
                            DownloadSource(widget.post.summ.authorID),
                        child: MarkdownArea(markdownData, false)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.mode_comment_outlined,
                        size: 16, color: Color(0xFF5F6764)),
                    const SizedBox(width: 6),
                    Text(
                        _commentCount == null
                            ? "—"
                            : "${_commentCount!} ${_commentCount == 1 ? "comment" : "comments"}",
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF9AA3A0))),
                    if (hasUnreadComments) ...[
                      const SizedBox(width: 9),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF4D9FFF)),
                      ),
                      const SizedBox(width: 5),
                      const Text("new",
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF4D9FFF),
                              fontWeight: FontWeight.w500)),
                    ],
                    const Spacer(),
                    if (cardActions) ...[
                      Tooltip(
                        message: "Relay to your subscribers",
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Golib.relayPostToAll(
                              widget.post.summ.from, widget.post.summ.id),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Icon(Icons.cached,
                                size: 18, color: Color(0xFF5F6764)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (!mine)
                        Tooltip(
                          message: "Tip the author",
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final c =
                                  widget.client.getExistingChat(authorID);
                              if (c != null) showPayTipModalBottom(context, c);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Icon(Icons.bolt,
                                  size: 18, color: Color(0xFF4D9FFF)),
                            ),
                          ),
                        ),
                      if (!mine) const SizedBox(width: 4),
                      Tooltip(
                        message: "Quote post",
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.feed.newPost.content =
                                "\n\n--embed[type=quote,from=${widget.post.summ.authorID},post=${widget.post.summ.id}]--\n";
                            widget.onTabChange(3, null);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Icon(Icons.repeat,
                                size: 18, color: Color(0xFF5F6764)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (bookmarks)
                      ListenableBuilder(
                        listenable: FeedBookmarks.instance,
                        builder: (context, _) {
                          final marked = FeedBookmarks.instance.contains(
                              widget.post.summ.from, widget.post.summ.id);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => FeedBookmarks.instance.toggle(
                                widget.post.summ.from, widget.post.summ.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Icon(
                                  marked
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  size: 18,
                                  color: marked
                                      ? const Color(0xFF4D9FFF)
                                      : const Color(0xFF5F6764)),
                            ),
                          );
                        },
                      ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}

class FeedPosts extends StatefulWidget {
  final FeedModel feed;
  final ClientModel client;
  final Function tabChange;
  final bool onlyShowOwnPosts;
  const FeedPosts(this.feed, this.client, this.tabChange, this.onlyShowOwnPosts,
      {super.key});

  @override
  State<FeedPosts> createState() => _FeedPostsState();
}

enum FeedView { all, bookmarks, hidden, drafts }

enum FeedSort { newest, oldest, mostComments }

class _FeedPostsState extends State<FeedPosts> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _composerCtrl = TextEditingController();
  FeedView _view = FeedView.all;
  FeedSort _sort = FeedSort.newest;
  bool _unreadOnly = false;
  String _search = "";

  @override
  void initState() {
    super.initState();
    FeedBookmarks.instance.ensureLoaded();
    FeedHidden.instance.ensureLoaded();
    FeedDrafts.instance.ensureLoaded();
    widget.feed.addListener(feedChanged);
    FeedBookmarks.instance.addListener(feedChanged);
    FeedHidden.instance.addListener(feedChanged);
    FeedDrafts.instance.addListener(feedChanged);
  }

  void feedChanged() async {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(FeedPosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.feed.removeListener(feedChanged);
    widget.feed.addListener(feedChanged);
  }

  @override
  void dispose() {
    widget.feed.removeListener(feedChanged);
    FeedBookmarks.instance.removeListener(feedChanged);
    FeedHidden.instance.removeListener(feedChanged);
    FeedDrafts.instance.removeListener(feedChanged);
    _searchCtrl.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  void _loadDraft(String text) {
    _composerCtrl.text = text;
    setState(() => _view = FeedView.all);
  }

  List<FeedPostModel> _applyFilters(bool bookmarks, bool hidePosts) {
    Iterable<FeedPostModel> posts = widget.onlyShowOwnPosts
        ? widget.feed.posts
            .where((p) => p.summ.authorID == widget.client.publicID)
        : widget.feed.posts;

    bool isHidden(FeedPostModel p) =>
        hidePosts && FeedHidden.instance.contains(p.summ.from, p.summ.id);

    switch (_view) {
      case FeedView.bookmarks:
        posts = posts.where((p) =>
            FeedBookmarks.instance.contains(p.summ.from, p.summ.id) &&
            !isHidden(p));
        break;
      case FeedView.hidden:
        posts = posts.where(isHidden);
        break;
      case FeedView.all:
      case FeedView.drafts:
        posts = posts.where((p) => !isHidden(p));
        break;
    }

    if (_unreadOnly) {
      posts = posts.where((p) => p.hasUnreadPost || p.hasUnreadComments);
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      posts = posts.where((p) {
        final author =
            (widget.client.getExistingChat(p.summ.authorID)?.nick ??
                    p.summ.authorNick)
                .toLowerCase();
        return author.contains(q) ||
            p.summ.title.toLowerCase().contains(q) ||
            p.content.toLowerCase().contains(q);
      });
    }

    final list = posts.toList();
    switch (_sort) {
      case FeedSort.newest:
        list.sort((a, b) => b.summ.date.compareTo(a.summ.date));
        break;
      case FeedSort.oldest:
        list.sort((a, b) => a.summ.date.compareTo(b.summ.date));
        break;
      case FeedSort.mostComments:
        list.sort((a, b) => b.comments.length.compareTo(a.comments.length));
        break;
    }
    return list;
  }

  Widget _plainList(List<FeedPostModel> posts) => SelectionArea(
          child: Container(
        padding:
            const EdgeInsets.only(left: 10, right: 0, top: 0, bottom: 10),
        child: ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              var post = posts[index];
              var author = widget.client.getExistingChat(post.summ.authorID);
              var from = widget.client.getExistingChat(post.summ.from);
              return FeedPostW(widget.feed, post, author, from, widget.client,
                  widget.tabChange);
            }),
      ));

  @override
  Widget build(BuildContext context) {
    var feedStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.feed);
    var sidePanel = feedStyle.feedSidePanel;
    var bookmarks = feedStyle.feedBookmarks;
    var hidePosts = feedStyle.feedHidePosts;
    var inlineComposer = feedStyle.feedInlineComposer;
    var composerFormatting = feedStyle.feedComposerFormatting;
    var composerAttach = feedStyle.feedComposerAttach;
    var drafts = feedStyle.feedDrafts;

    if (!sidePanel) {
      final posts = _applyFilters(bookmarks, hidePosts);
      return _plainList(posts);
    }

    final postList = _applyFilters(bookmarks, hidePosts);
    final Widget body;
    if (drafts && _view == FeedView.drafts) {
      body = _DraftsView(onUse: _loadDraft);
    } else if (postList.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
              _view == FeedView.bookmarks
                  ? "No bookmarks yet.\nTap the bookmark icon on a post to save it."
                  : _view == FeedView.hidden
                      ? "No hidden posts."
                      : _search.isNotEmpty
                          ? "No posts match your search."
                          : "No posts yet.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF5F6764), height: 1.5, fontSize: 14)),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: postList.length,
        itemBuilder: (context, index) {
          final post = postList[index];
          final author = widget.client.getExistingChat(post.summ.authorID);
          final from = widget.client.getExistingChat(post.summ.from);
          return FeedPostW(
              widget.feed, post, author, from, widget.client, widget.tabChange);
        },
      );
    }

    final feedColumn = Container(
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF1C1F1D)),
          right: BorderSide(color: Color(0xFF1C1F1D)),
        ),
      ),
      child: Column(children: [
        if (inlineComposer)
          _FeedComposer(
            client: widget.client,
            feed: widget.feed,
            controller: _composerCtrl,
            showFormatting: composerFormatting,
            showAttach: composerAttach,
            showDrafts: drafts,
          ),
        Expanded(child: body),
      ]),
    );

    final panel = FeedSidePanel(
      view: _view,
      sort: _sort,
      unreadOnly: _unreadOnly,
      searchController: _searchCtrl,
      showBookmarks: bookmarks,
      showHidden: hidePosts,
      showDrafts: drafts,
      currentTabIndex: widget.onlyShowOwnPosts ? 1 : 0,
      onView: (v) {
        // "All posts" from within the Your Posts tab means "go to the
        // actual All posts tab", not "filter Your Posts down to itself"
        // (a no-op that looked like the link didn't work). Bookmarks/
        // Hidden/Drafts are feed-wide sets, so filtering in place still
        // makes sense for those regardless of which tab this panel is on.
        if (widget.onlyShowOwnPosts && v == FeedView.all) {
          widget.tabChange(0, null);
        } else {
          setState(() => _view = v);
        }
      },
      onSort: (s) => setState(() => _sort = s),
      onUnreadOnly: (b) => setState(() => _unreadOnly = b),
      onSearch: (t) => setState(() => _search = t),
      onYourPosts: () => widget.tabChange(1, null),
      onSubscriptions: () => widget.tabChange(2, null),
      onNewPost: () => widget.tabChange(3, null),
    );

    return SelectionArea(
      child: LayoutBuilder(builder: (context, c) {
        // crossAxisAlignment.stretch gives children a bounded height so the
        // inner ListView lays out correctly.
        List<Widget> rowChildren;
        if (c.maxWidth >= 1400) {
          rowChildren = [
            const Spacer(),
            SizedBox(width: 260, child: panel),
            const SizedBox(width: 48),
            SizedBox(width: 780, child: feedColumn),
            const SizedBox(width: 308),
            const Spacer(),
          ];
        } else if (c.maxWidth >= 900) {
          rowChildren = [
            const SizedBox(width: 16),
            SizedBox(width: 260, child: panel),
            const SizedBox(width: 48),
            Expanded(child: feedColumn),
          ];
        } else if (c.maxWidth >= 600) {
          rowChildren = [
            const Spacer(),
            SizedBox(width: 600, child: feedColumn),
            const Spacer(),
          ];
        } else {
          rowChildren = [Expanded(child: feedColumn)];
        }
        return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowChildren);
      }),
    );
  }
}

// Left-side tools rail (X-style): search, views, sort, filters. Only shown
// when AreaStyle.feedSidePanel is on.
class FeedSidePanel extends StatelessWidget {
  final FeedView view;
  final FeedSort sort;
  final bool unreadOnly;
  final TextEditingController searchController;
  final bool showBookmarks;
  final bool showHidden;
  final bool showDrafts;
  // Which Feed screen tab (0=All posts, 1=Your Posts, 2=Subscriptions,
  // 3=New Post) is currently active, so the Your Posts/Subscriptions/New
  // Post shortcuts below can highlight themselves like the FEED-section
  // nav items already do.
  final int currentTabIndex;
  final ValueChanged<FeedView> onView;
  final ValueChanged<FeedSort> onSort;
  final ValueChanged<bool> onUnreadOnly;
  final ValueChanged<String> onSearch;
  final VoidCallback onYourPosts;
  final VoidCallback onSubscriptions;
  final VoidCallback onNewPost;
  const FeedSidePanel({
    super.key,
    required this.view,
    required this.sort,
    required this.unreadOnly,
    required this.searchController,
    required this.showBookmarks,
    required this.showHidden,
    required this.showDrafts,
    required this.currentTabIndex,
    required this.onView,
    required this.onSort,
    required this.onUnreadOnly,
    required this.onSearch,
    required this.onYourPosts,
    required this.onSubscriptions,
    required this.onNewPost,
  });

  Widget _navItem(IconData ic, String label, FeedView v, {String? trailing}) {
    final selected = view == v;
    return GestureDetector(
      onTap: () => onView(v),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF101826) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(ic,
              size: 19,
              color: selected
                  ? const Color(0xFF4D9FFF)
                  : const Color(0xFF9AA3A0)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF4D9FFF)
                      : const Color(0xFFF2F4F3))),
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing,
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFF5F6764))),
          ],
        ]),
      ),
    );
  }

  Widget _actionItem(IconData ic, String label, VoidCallback onTap,
      {bool selected = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF101826) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(ic,
              size: 19,
              color: selected
                  ? const Color(0xFF4D9FFF)
                  : const Color(0xFF9AA3A0)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF4D9FFF)
                      : const Color(0xFFF2F4F3))),
        ]),
      ),
    );
  }

  Widget _sortItem(String label, FeedSort s) {
    final selected = sort == s;
    return GestureDetector(
      onTap: () => onSort(s),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color:
                  selected ? const Color(0xFF4D9FFF) : const Color(0xFF5F6764)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: selected
                      ? const Color(0xFF4D9FFF)
                      : const Color(0xFFF2F4F3))),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(left: 12, top: 18, bottom: 8),
        child: Text(s,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF5F6764))),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FeedBookmarks.instance,
        FeedHidden.instance,
        FeedDrafts.instance,
        searchController,
      ]),
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF0E100E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F231F))),
              child: TextField(
                controller: searchController,
                onChanged: onSearch,
                style: const TextStyle(fontSize: 14, color: Color(0xFFF2F4F3)),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: Color(0xFF5F6764)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  hintText: "Search posts",
                  hintStyle:
                      const TextStyle(fontSize: 14, color: Color(0xFF5F6764)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  suffixIcon: searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            searchController.clear();
                            onSearch("");
                          },
                          child: const Icon(Icons.close,
                              size: 16, color: Color(0xFF5F6764)))
                      : null,
                ),
              ),
            ),
            _sectionLabel("FEED"),
            _navItem(Icons.dynamic_feed_outlined, "All posts", FeedView.all),
            if (showBookmarks)
              _navItem(
                  Icons.bookmark_outline, "Bookmarks", FeedView.bookmarks,
                  trailing: "${FeedBookmarks.instance.count}"),
            if (showHidden)
              _navItem(
                  Icons.visibility_off_outlined, "Hidden", FeedView.hidden,
                  trailing: "${FeedHidden.instance.count}"),
            if (showDrafts)
              _navItem(Icons.edit_note_outlined, "Drafts", FeedView.drafts,
                  trailing: "${FeedDrafts.instance.count}"),
            _sectionLabel("POSTS"),
            _actionItem(Icons.article_outlined, "Your Posts", onYourPosts,
                selected: currentTabIndex == 1),
            _actionItem(Icons.rss_feed, "Subscriptions", onSubscriptions,
                selected: currentTabIndex == 2),
            _actionItem(Icons.add_box_outlined, "New Post", onNewPost,
                selected: currentTabIndex == 3),
            _sectionLabel("SORT"),
            _sortItem("Newest", FeedSort.newest),
            _sortItem("Oldest", FeedSort.oldest),
            _sortItem("Most comments", FeedSort.mostComments),
            _sectionLabel("FILTER"),
            GestureDetector(
              onTap: () => onUnreadOnly(!unreadOnly),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.mark_chat_unread_outlined,
                      size: 18, color: Color(0xFF9AA3A0)),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text("Unread only",
                          style: TextStyle(
                              fontSize: 14.5, color: Color(0xFFF2F4F3)))),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 22,
                    decoration: BoxDecoration(
                        color: unreadOnly
                            ? const Color(0xFF1DFF8C)
                            : const Color(0xFF23262B),
                        borderRadius: BorderRadius.circular(11)),
                    alignment: unreadOnly
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    padding: const EdgeInsets.all(2),
                    child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white)),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// Caps content to [maxHeight]; if it overflows, clips with a bottom fade and
// a "Show more" affordance (X-style). Renders the child unmodified so
// embedded images always display correctly. Only used when
// AreaStyle.feedCardRedesign is on.
class _ClampedContent extends StatefulWidget {
  final Widget child;
  final double maxHeight;
  final VoidCallback onShowMore;
  const _ClampedContent(
      {required this.child,
      required this.maxHeight,
      required this.onShowMore});

  @override
  State<_ClampedContent> createState() => _ClampedContentState();
}

class _ClampedContentState extends State<_ClampedContent> {
  final GlobalKey _key = GlobalKey();
  bool _overflows = false;

  void _measure() {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final h = ctx.size?.height ?? 0;
    final over = h > widget.maxHeight + 2;
    if (over != _overflows && mounted) setState(() => _overflows = over);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_ClampedContent old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final measured = KeyedSubtree(key: _key, child: widget.child);

    if (!_overflows) {
      // Fits (or not yet measured): render naturally.
      return measured;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        ClipRect(
          child: SizedBox(
            height: widget.maxHeight,
            width: double.infinity,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: measured,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x000A0A0A), Color(0xFF0A0A0A)],
                ),
              ),
            ),
          ),
        ),
      ]),
      GestureDetector(
        onTap: widget.onShowMore,
        child: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text("Show more",
              style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4D9FFF),
                  fontWeight: FontWeight.w500)),
        ),
      ),
    ]);
  }
}

// Local-only bookmarks for feed posts, gated by AreaStyle.feedBookmarks.
// Persisted to device storage as a JSON list of "from\tid" keys.
// Self-contained singleton so it needs no provider wiring. Bookmarks do not
// sync across devices (BR has no sync layer).
class FeedBookmarks extends ChangeNotifier {
  FeedBookmarks._();
  static final FeedBookmarks instance = FeedBookmarks._();
  static const String _storeKey = "feedBookmarks";

  final Set<String> _ids = {};
  bool _loaded = false;

  String _k(String from, String id) => "$from\t$id";

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await StorageManager.readString(_storeKey, defaultVal: "");
      if (raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<String>();
        _ids.addAll(list);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await StorageManager.saveString(_storeKey, jsonEncode(_ids.toList()));
    } catch (_) {}
  }

  int get count => _ids.length;
  bool contains(String from, String id) => _ids.contains(_k(from, id));

  Future<void> toggle(String from, String id) async {
    final k = _k(from, id);
    if (!_ids.remove(k)) _ids.add(k);
    notifyListeners();
    await _persist();
  }
}

// Local-only hidden/muted posts, gated by AreaStyle.feedHidePosts. Same
// storage pattern as bookmarks.
class FeedHidden extends ChangeNotifier {
  FeedHidden._();
  static final FeedHidden instance = FeedHidden._();
  static const String _storeKey = "feedHidden";

  final Set<String> _ids = {};
  bool _loaded = false;

  String _k(String from, String id) => "$from\t$id";

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await StorageManager.readString(_storeKey, defaultVal: "");
      if (raw.isNotEmpty) {
        _ids.addAll((jsonDecode(raw) as List).cast<String>());
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await StorageManager.saveString(_storeKey, jsonEncode(_ids.toList()));
    } catch (_) {}
  }

  int get count => _ids.length;
  bool contains(String from, String id) => _ids.contains(_k(from, id));

  Future<void> toggle(String from, String id) async {
    final k = _k(from, id);
    if (!_ids.remove(k)) _ids.add(k);
    notifyListeners();
    await _persist();
  }
}

// Local-only post drafts, gated by AreaStyle.feedDrafts. Stored as a JSON
// list of strings.
class FeedDrafts extends ChangeNotifier {
  FeedDrafts._();
  static final FeedDrafts instance = FeedDrafts._();
  static const String _storeKey = "feedDrafts";

  List<String> _drafts = [];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await StorageManager.readString(_storeKey, defaultVal: "");
      if (raw.isNotEmpty) {
        _drafts = (jsonDecode(raw) as List).cast<String>();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await StorageManager.saveString(_storeKey, jsonEncode(_drafts));
    } catch (_) {}
  }

  List<String> get drafts => List.unmodifiable(_drafts);
  int get count => _drafts.length;

  Future<void> add(String content) async {
    final c = content.trim();
    if (c.isEmpty) return;
    _drafts.insert(0, c);
    notifyListeners();
    await _persist();
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= _drafts.length) return;
    _drafts.removeAt(i);
    notifyListeners();
    await _persist();
  }
}

// Drafts list (shown in the feed column when the Drafts view is active).
// Only reachable when AreaStyle.feedDrafts is on.
class _DraftsView extends StatelessWidget {
  final ValueChanged<String> onUse;
  const _DraftsView({required this.onUse});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeedDrafts.instance,
      builder: (context, _) {
        final drafts = FeedDrafts.instance.drafts;
        if (drafts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                  "No drafts.\nWrite something and tap the draft icon to save it.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF5F6764), height: 1.5, fontSize: 14)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: drafts.length,
          itemBuilder: (context, i) {
            final d = drafts[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFF0C0D0C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1C1F1D))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Color(0xFFCDD3D1))),
                    const SizedBox(height: 12),
                    Row(children: [
                      GestureDetector(
                        onTap: () => onUse(d),
                        behavior: HitTestBehavior.opaque,
                        child: const Text("Use",
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1DFF8C))),
                      ),
                      const SizedBox(width: 22),
                      GestureDetector(
                        onTap: () => FeedDrafts.instance.removeAt(i),
                        behavior: HitTestBehavior.opaque,
                        child: const Text("Delete",
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF5F6764))),
                      ),
                    ]),
                  ]),
            );
          },
        );
      },
    );
  }
}

// "What's happening?" composer pinned at the top of the feed. Lets the user
// write, attach a file, format text and relay a post directly from the feed.
// Only shown when AreaStyle.feedInlineComposer is on.
class _FeedComposer extends StatefulWidget {
  final ClientModel client;
  final FeedModel feed;
  final TextEditingController controller;
  final bool showFormatting;
  final bool showAttach;
  final bool showDrafts;
  const _FeedComposer({
    required this.client,
    required this.feed,
    required this.controller,
    required this.showFormatting,
    required this.showAttach,
    required this.showDrafts,
  });

  @override
  State<_FeedComposer> createState() => _FeedComposerState();
}

class _FeedComposerState extends State<_FeedComposer> {
  TextEditingController get _ctrl => widget.controller;
  final FocusNode _focus = FocusNode();
  final MenuController _fmtMenu = MenuController();
  bool _posting = false;
  // Captured when the format menu opens, since opening it steals focus and
  // invalidates the live selection.
  TextSelection _savedSel = const TextSelection.collapsed(offset: -1);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _focus.dispose();
    super.dispose();
  }

  TextSelection _effectiveSel() {
    if (_savedSel.isValid && _savedSel.end <= _ctrl.text.length) {
      return _savedSel;
    }
    return TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _wrap(String l, String r) {
    final sel = _effectiveSel();
    final text = _ctrl.text;
    final selected = sel.textInside(text);
    _ctrl.text = sel.textBefore(text) + l + selected + r + sel.textAfter(text);
    // Put the cursor between the markers (no selection) or after the wrapped
    // text (had a selection).
    final cursor = selected.isEmpty
        ? sel.start + l.length
        : sel.start + l.length + selected.length + r.length;
    _ctrl.selection = TextSelection.collapsed(offset: cursor);
    _savedSel = _ctrl.selection;
    _focus.requestFocus();
    setState(() {});
  }

  void _insertLink() {
    final sel = _effectiveSel();
    final text = _ctrl.text;
    const tmpl = "[text](url)";
    _ctrl.text = sel.textBefore(text) + tmpl + sel.textAfter(text);
    // Select the word "text" so it can be typed over.
    _ctrl.selection =
        TextSelection(baseOffset: sel.start + 1, extentOffset: sel.start + 5);
    _savedSel = _ctrl.selection;
    _focus.requestFocus();
    setState(() {});
  }

  void _fmt(VoidCallback fn) {
    _fmtMenu.close();
    fn();
  }

  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          "avif",
          "bmp",
          "gif",
          "jpg",
          "jpeg",
          "jxl",
          "png",
          "webp",
          "txt"
        ],
        withData: true,
      );
      if (res == null) return;
      final f = res.files.first;
      if (f.bytes == null) return;
      if (f.size > Golib.maxPayloadSize) {
        messenger.showSnackBar(SnackBar(
            content: Text("File too large (max ${Golib.maxPayloadSizeStr})")));
        return;
      }
      String mime;
      switch (f.extension) {
        case "txt":
          mime = "text/plain";
          break;
        case "avif":
          mime = "image/avif";
          break;
        case "bmp":
          mime = "image/bmp";
          break;
        case "gif":
          mime = "image/gif";
          break;
        case "jpg":
        case "jpeg":
          mime = "image/jpeg";
          break;
        case "jxl":
          mime = "image/jxl";
          break;
        case "png":
          mime = "image/png";
          break;
        case "webp":
          mime = "image/webp";
          break;
        default:
          messenger.showSnackBar(
              const SnackBar(content: Text("Unsupported file type")));
          return;
      }
      final data = const Base64Encoder().convert(f.bytes!);
      _ctrl.text = "${_ctrl.text}\n--embed[type=$mime,data=$data]--\n";
      setState(() {});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Attach failed: $e")));
    }
  }

  Future<void> _relay() async {
    final content = _ctrl.text.trim();
    if (content.isEmpty || _posting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _posting = true);
    try {
      await widget.feed.createPost(content);
      _ctrl.clear();
      messenger.showSnackBar(const SnackBar(content: Text("Relayed")));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Relay failed: $e")));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Widget _iconBtn(IconData ic, String tip, VoidCallback onTap) => IconButton(
        icon: Icon(ic, size: 20, color: const Color(0xFF9AA3A0)),
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        splashRadius: 18,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      );

  void _openFmtMenu() {
    // Capture the selection before the menu steals focus.
    _savedSel = _ctrl.selection;
    if (_fmtMenu.isOpen) {
      _fmtMenu.close();
    } else {
      _fmtMenu.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2F3336))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SelfAvatar(widget.client, radius: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Bigger compose box (~3x a normal input).
            Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E100E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1F231F)),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                minLines: 3,
                maxLines: 12,
                onChanged: (_) => setState(() {}),
                onTap: () => _savedSel = _ctrl.selection,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                    fontSize: 16, height: 1.4, color: Color(0xFFF2F4F3)),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: "What's happening?",
                  hintStyle:
                      TextStyle(fontSize: 16, color: Color(0xFF5F6764)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              if (widget.showAttach)
                _iconBtn(Icons.image_outlined, "Attach", _attach),
              if (widget.showAttach) const SizedBox(width: 2),
              if (widget.showFormatting) ...[
                MenuAnchor(
                  controller: _fmtMenu,
                  menuChildren: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _iconBtn(Icons.format_bold, "Bold",
                            () => _fmt(() => _wrap("**", "**"))),
                        _iconBtn(Icons.format_italic, "Italic",
                            () => _fmt(() => _wrap("_", "_"))),
                        _iconBtn(Icons.code, "Code",
                            () => _fmt(() => _wrap("`", "`"))),
                        _iconBtn(Icons.format_strikethrough, "Strikethrough",
                            () => _fmt(() => _wrap("~~", "~~"))),
                        _iconBtn(Icons.link, "Link", () => _fmt(_insertLink)),
                      ]),
                    ),
                  ],
                  child: _iconBtn(Icons.text_format, "Format", _openFmtMenu),
                ),
                const SizedBox(width: 2),
              ],
              if (widget.showDrafts)
                _iconBtn(Icons.bookmark_add_outlined, "Save draft", () {
                  final messenger = ScaffoldMessenger.of(context);
                  FeedDrafts.instance.add(_ctrl.text);
                  messenger.showSnackBar(
                      const SnackBar(content: Text("Draft saved")));
                }),
              const Spacer(),
              GestureDetector(
                onTap: _posting ? null : _relay,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 26, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1DFF8C), Color(0xFF13D673)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF1DFF8C).withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _posting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF04130B)))
                      : const Text("Relay",
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: Color(0xFF04130B))),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
