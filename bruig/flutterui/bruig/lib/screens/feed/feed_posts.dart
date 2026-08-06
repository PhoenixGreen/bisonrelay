import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/pay_tip.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/screens/feed/post_content.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
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

class _FeedPostWState extends State<FeedPostW>
    with AutomaticKeepAliveClientMixin {
  FeedModel get feed => widget.feed;
  FeedPostModel get post => widget.post;
  showContent(BuildContext context) {
    feed.active = post;
    widget.onTabChange(0, PostContentScreenArgs(post));
  }

  // Keeps each post's built state (markdown, images, loaded comments/
  // content) alive once scrolled past instead of tearing it down and
  // rebuilding -- plus redoing the async readComments/readPost Golib calls
  // -- every time it re-enters the ListView's cache range. That
  // repeated teardown/rebuild-from-scratch cycle was the remaining source
  // of scroll jank after the height-clamp flash was fixed.
  @override
  bool get wantKeepAlive => true;

  void authorUpdated() => setState(() {});

  int? _commentCount;

  Future<void> _loadCommentCount() async {
    if (_commentCount != null) return;
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
    super.build(context);
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
    var theme = ThemeNotifier.of(context);
    var feedStyle = theme.areaStyle(ThemeArea.feed);
    var redesign = feedStyle.feedCardRedesign;
    var cardActions = feedStyle.feedCardActions;

    if (!redesign) {
      var markdownData = widget.post.summ.title;
      if (widget.post.summ.title.contains("--embed[type=")) {
        // This will pluck the first embed in a post.  Then we can display just
        // that in feedposts without the rest of the post content.
        var firstIndex = widget.post.content.indexOf("--");
        var nextIndex = widget.post.content.indexOf("--", firstIndex + 1);
        markdownData = widget.post.content.substring(firstIndex, nextIndex + 2);
      }

      if (feedStyle.feedImageLayout == FeedImageLayout.none) {
        markdownData = _stripAllImages(markdownData);
      }

      final legacyStripLinks = feedStyle.feedLinksMode == FeedLinksMode.off ||
          (feedStyle.feedLinksMode == FeedLinksMode.offIfImage &&
              _hasImageEmbed(markdownData));
      if (legacyStripLinks) markdownData = _stripLinks(markdownData);

      return Card.filled(
          color: theme.colors.tertiary,
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
                  Expanded(
                      child: Text(authorNick,
                          style: TextStyle(
                              color: theme.textColor(TextColor.onSurface)))),
                  Text(sincePost,
                      style: TextStyle(
                          color: theme
                              .textColor(TextColor.onSurface)
                              .withValues(alpha: 0.6))),
                ]),

                // Second row: post summary.
                Provider<DownloadSource>(
                    create: (context) =>
                        DownloadSource(widget.post.summ.authorID),
                    child: MarkdownArea(markdownData, false,
                        disableLinks: legacyStripLinks,
                        plainText: feedStyle.feedStripMarkdown)),

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
    var markdownData = widget.post.content.isNotEmpty
        ? widget.post.content
        : widget.post.summ.title;

    // Checked against the original, unmodified content -- whether a post
    // "has an image" for FeedLinksMode.offIfImage shouldn't depend on
    // whether the image layout/text order settings happen to pull that
    // image out for special positioning.
    final postHasImage = _hasImageEmbed(markdownData);

    // Only the first image is ever pulled out for separate placement --
    // posts with no image fall straight through to the original
    // inline-embed rendering. Extraction also kicks in with the image
    // layout otherwise left at Default, as long as a text order has been
    // chosen -- picking "Text first"/"Text last" is meaningless unless the
    // image actually gets pulled out of the text flow and stacked.
    final wantsTextOrder = feedStyle.feedTextOrder != FeedTextOrder.standard;
    _ExtractedImage? firstImage;
    var resolvedImageLayout = FeedImageLayout.standard;
    if (feedStyle.feedImageLayout == FeedImageLayout.none) {
      // Every image is removed, not just the first -- there's nothing left
      // to extract/position.
      markdownData = _stripAllImages(markdownData);
    } else if (feedStyle.feedImageLayout != FeedImageLayout.standard ||
        wantsTextOrder) {
      final (extracted, stripped) = _extractFirstImage(markdownData);
      if (extracted != null) {
        firstImage = extracted;
        markdownData = stripped;
        resolvedImageLayout =
            feedStyle.feedImageLayout == FeedImageLayout.standard
                ? FeedImageLayout.standard
                : _resolveFeedImageLayout(feedStyle.feedImageLayout,
                    widget.post.summ.from, widget.post.summ.id);
      }
    }

    // Limits how much of the (possibly image-stripped) body text is shown;
    // 0 (the default) leaves it unlimited, same as before this setting
    // existed.
    if (feedStyle.feedTextLimit > 0 &&
        markdownData.length > feedStyle.feedTextLimit) {
      markdownData =
          "${markdownData.substring(0, feedStyle.feedTextLimit.toInt())}…";
    }

    final stripLinks = feedStyle.feedLinksMode == FeedLinksMode.off ||
        (feedStyle.feedLinksMode == FeedLinksMode.offIfImage && postHasImage);
    if (stripLinks) markdownData = _stripLinks(markdownData);

    final textContent = _ClampedContent(
      cacheKey: "${widget.post.summ.from}:${widget.post.summ.id}",
      maxHeight: 300,
      onShowMore: () => showContent(context),
      child: Provider<DownloadSource>(
          create: (context) => DownloadSource(widget.post.summ.authorID),
          child: MarkdownArea(markdownData, false,
              disableLinks: stripLinks,
              plainText: feedStyle.feedStripMarkdown)),
    );

    Widget postBody;
    if (firstImage == null) {
      postBody = textContent;
    } else {
      final imageWidget = _FeedFirstImage(
        bytes: firstImage.bytes,
        tip: firstImage.tip,
        layout: resolvedImageLayout,
        cropHeight: feedStyle.feedImageCropHeight,
        applyCropCapToFull: feedStyle.feedImageLayout == FeedImageLayout.random,
        onTap: () => showContent(context),
      );
      switch (resolvedImageLayout) {
        case FeedImageLayout.left:
          postBody =
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 140, child: imageWidget),
            const SizedBox(width: 12),
            Expanded(child: textContent),
          ]);
          break;
        case FeedImageLayout.right:
          postBody =
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: textContent),
            const SizedBox(width: 12),
            SizedBox(width: 140, child: imageWidget),
          ]);
          break;
        case FeedImageLayout.full:
        case FeedImageLayout.cropped:
        case FeedImageLayout.standard:
          postBody = feedStyle.feedTextOrder == FeedTextOrder.textLast
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  imageWidget,
                  const SizedBox(height: 10),
                  textContent,
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  textContent,
                  const SizedBox(height: 10),
                  imageWidget,
                ]);
          break;
        case FeedImageLayout.random:
        case FeedImageLayout.none:
          postBody = textContent; // Unreachable: resolved/handled above.
          break;
      }
    }

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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(authorNick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: theme.textColor(TextColor.onSurface)))),
                const SizedBox(width: 6),
                Text("· $sincePost",
                    style: TextStyle(
                        fontSize: 12.5,
                        color: theme
                            .textColor(TextColor.onSurface)
                            .withValues(alpha: 0.6))),
                const Spacer(),
              ]),
              const SizedBox(height: 6),
              postBody,
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                          final c = widget.client.getExistingChat(authorID);
                          if (c != null) showPayTipModalBottom(context, c);
                        },
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Icon(Icons.repeat,
                            size: 18, color: Color(0xFF5F6764)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (cardActions)
                  ListenableBuilder(
                    listenable: FeedBookmarks.instance,
                    builder: (context, _) {
                      final marked = FeedBookmarks.instance
                          .contains(widget.post.summ.from, widget.post.summ.id);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => FeedBookmarks.instance
                            .toggle(widget.post.summ.from, widget.post.summ.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Icon(
                              marked ? Icons.bookmark : Icons.bookmark_border,
                              size: 18,
                              color: marked
                                  ? const Color(0xFF4D9FFF)
                                  : const Color(0xFF5F6764)),
                        ),
                      );
                    },
                  ),
                // The overflow menu sits at the end of this bar, beside the
                // other things you can do to a post, rather than up beside
                // the author's name where it used to be. Bookmarking isn't
                // in it: it's already one tap away, immediately to its left.
                if (cardActions)
                  ListenableBuilder(
                    listenable: FeedHidden.instance,
                    builder: (context, _) {
                      final hidden = FeedHidden.instance
                          .contains(widget.post.summ.from, widget.post.summ.id);
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
                                  widget.post.summ.from, widget.post.summ.id);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: "hide",
                              child: Text(hidden ? "Unhide post" : "Hide post",
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFFF2F4F3))),
                            ),
                          ],
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

  // Bursts of post-status events (e.g. catching up on a backlog of comment
  // notifications right after connecting) can each trigger a FeedModel
  // notification in quick succession. Coalescing them into a single
  // setState per short window avoids rebuilding (and re-reconciling) the
  // whole visible post list once per event, which was visibly janky while
  // scrolling.
  Timer? _feedChangedDebounce;
  void feedChanged() {
    _feedChangedDebounce?.cancel();
    _feedChangedDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(FeedPosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.feed.removeListener(feedChanged);
    widget.feed.addListener(feedChanged);
  }

  @override
  void dispose() {
    _feedChangedDebounce?.cancel();
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
        final author = (widget.client.getExistingChat(p.summ.authorID)?.nick ??
                p.summ.authorNick)
            .toLowerCase();
        return author.contains(q) ||
            p.summ.title.toLowerCase().contains(q) ||
            p.content.toLowerCase().contains(q);
      });
    }

    // Tie-break by a stable per-post identifier so posts sharing the exact
    // same primary sort value (e.g. identical timestamps) always land in
    // the same relative order across rebuilds. Without this, Dart's
    // List.sort isn't guaranteed stable, so ties could shuffle on every
    // rebuild -- and with FeedPostW's list items now carrying real keys,
    // Flutter faithfully reconciles that shuffle instead of masking it,
    // which made scrolling feel like it never settled.
    int tiebreak(FeedPostModel a, FeedPostModel b) =>
        "${a.summ.from}:${a.summ.id}".compareTo("${b.summ.from}:${b.summ.id}");

    final list = posts.toList();
    switch (_sort) {
      case FeedSort.newest:
        list.sort((a, b) {
          final c = b.summ.date.compareTo(a.summ.date);
          return c != 0 ? c : tiebreak(a, b);
        });
        break;
      case FeedSort.oldest:
        list.sort((a, b) {
          final c = a.summ.date.compareTo(b.summ.date);
          return c != 0 ? c : tiebreak(a, b);
        });
        break;
      case FeedSort.mostComments:
        list.sort((a, b) {
          final c = b.comments.length.compareTo(a.comments.length);
          return c != 0 ? c : tiebreak(a, b);
        });
        break;
    }
    return list;
  }

  Widget _plainList(List<FeedPostModel> posts) => SelectionArea(
          child: Container(
        padding: const EdgeInsets.only(left: 10, right: 0, top: 0, bottom: 10),
        child: ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              var post = posts[index];
              var author = widget.client.getExistingChat(post.summ.authorID);
              var from = widget.client.getExistingChat(post.summ.from);
              return FeedPostW(widget.feed, post, author, from, widget.client,
                  widget.tabChange,
                  key: ValueKey("${post.summ.from}:${post.summ.id}"));
            }),
      ));

  @override
  Widget build(BuildContext context) {
    var feedStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.feed);
    var sidePanel = feedStyle.feedSidePanel;
    // Bookmarks/hiding ride with the post action bar, and the composer's
    // formatting/attach/drafts ride with the composer itself.
    var bookmarks = feedStyle.feedCardActions;
    var hidePosts = feedStyle.feedCardActions;
    var inlineComposer = feedStyle.feedInlineComposer;
    var composerFormatting = inlineComposer;
    var composerAttach = inlineComposer;
    var drafts = inlineComposer;

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
              widget.feed, post, author, from, widget.client, widget.tabChange,
              key: ValueKey("${post.summ.from}:${post.summ.id}"));
        },
      );
    }

    // Wrapped once here rather than at each breakpoint below, so the
    // Content Area applies to the feed's own layout the same way
    // SecondarySideMenuLayout applies it to every other screen's.
    final feedColumn = contentAreaFrame(
        ThemeNotifier.of(context),
        Container(
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
            // SelectionArea is scoped to just the post list (as it was before
            // the side panel existed) rather than the whole row -- wrapping the
            // sidebar/search/sort controls in it too made its drag-to-select
            // gesture recognizers compete with the list's own scroll gesture
            // across a much bigger surface, which is what broke scrolling.
            Expanded(child: SelectionArea(child: body)),
          ]),
        ));

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

    // The Sidebar area's "Resizable" visibility applies here too: this
    // panel is a sidebar like any other, it just lays itself out centered
    // rather than docked, so it borrows the drag strip and the per-screen
    // width store instead of the whole SecondarySideMenuLayout.
    var sidebarStyle = ThemeNotifier.of(context)
            .areaStyle(ThemeArea.subMenuTabBar)
            .subMenuStyle ??
        SubMenuStyle.alwaysVisible;
    var resizable = sidebarStyle == SubMenuStyle.resizable;

    Widget layout(double panelWidth, Widget? handle) {
      return LayoutBuilder(builder: (context, c) {
        if (sidebarStyle == SubMenuStyle.collapsed) {
          ClientModel.of(context, listen: false)
              .ui
              .collapsedSidebar
              .register((context) => panel, kCollapsedSidebarWidth);
          return feedColumn;
        }
        // crossAxisAlignment.stretch gives children a bounded height so the
        // inner ListView lays out correctly.
        //
        // No gap: the feed column starts immediately beside the sidebar,
        // the way content does in SecondarySideMenuLayout. The posts carry
        // their own horizontal padding, and the drag strip its own 8px.
        const gap = 0.0;
        List<Widget> rowChildren;
        if (c.maxWidth >= 1400) {
          rowChildren = [
            const Spacer(),
            SizedBox(width: panelWidth, child: panel),
            if (handle != null) handle,
            SizedBox(width: gap),
            SizedBox(width: 780, child: feedColumn),
            const SizedBox(width: 308),
            const Spacer(),
          ];
        } else if (c.maxWidth >= 900) {
          rowChildren = [
            // No leading gap: the panel butts against the nav bar the way
            // every other sidebar does.
            SizedBox(width: panelWidth, child: panel),
            if (handle != null) handle,
            SizedBox(width: gap),
            Expanded(child: feedColumn),
          ];
        } else {
          // Too narrow for a column of its own: hand the panel over as a
          // drawer, opened by re-tapping this page in the main navigation
          // (see CollapsedSidebarModel). Registering here rather
          // than dropping it is what gives this panel the same way back as
          // every other sidebar -- it used to just disappear, which is why
          // no way back existed at these widths.
          ClientModel.of(context, listen: false)
              .ui
              .collapsedSidebar
              .register((context) => panel, kCollapsedSidebarWidth);
          if (c.maxWidth >= 600) {
            return Row(children: [
              const Spacer(),
              SizedBox(width: 600, child: feedColumn),
              const Spacer(),
            ]);
          }
          return feedColumn;
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
}

// Left-side tools rail (X-style): search, views, sort, filters. Only shown
// when AreaStyle.feedSidePanel is on.
class FeedSidePanel extends StatelessWidget {
  final FeedView view;
  final FeedSort sort;
  final bool unreadOnly;
  final TextEditingController searchController;

  /// showSearch draws the search field at the top. Off where the panel is
  /// shown as navigation rather than as a way through the feed -- beside the
  /// composer, searching posts is not what the sidebar is for.
  final bool showSearch;

  /// framed wraps the panel in its own SecondarySideMenu, which paints the
  /// sidebar's background and border. Off when it is placed inside
  /// somebody else's sidebar, which has already painted them -- nesting the
  /// two draws every border twice.
  final bool framed;

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
    this.showSearch = true,
    this.framed = true,
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

  // The palette's Sidebar Accent, the same color every other sidebar in
  // the app highlights its selected row with -- this panel used to hardcode
  // its own blue, so it was the one sidebar that ignored the theme.
  Color _accent(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return theme.activePreset?.sidebarAccent ?? theme.colors.primary;
  }

  Widget _navItem(BuildContext context, IconData ic, String label, FeedView v,
      {String? trailing}) {
    final selected = view == v;
    final accent = _accent(context);
    return GestureDetector(
      onTap: () => onView(v),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(ic,
              size: 19, color: selected ? accent : const Color(0xFF9AA3A0)),
          const SizedBox(width: 12),
          // Expanded + ellipsis: this panel is drag-resizable, and the
          // longer labels ("Subscriptions", "Most comments") overflow it
          // well before its minimum width. Expanded also does the Spacer's
          // old job of pushing any trailing count to the far edge.
          Expanded(
            child: Text(label,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? accent : const Color(0xFFF2F4F3))),
          ),
          if (trailing != null)
            Text(trailing,
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFF5F6764))),
        ]),
      ),
    );
  }

  Widget _actionItem(
      BuildContext context, IconData ic, String label, VoidCallback onTap,
      {bool selected = false}) {
    final accent = _accent(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(ic,
              size: 19, color: selected ? accent : const Color(0xFF9AA3A0)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? accent : const Color(0xFFF2F4F3))),
          ),
        ]),
      ),
    );
  }

  Widget _sortItem(BuildContext context, String label, FeedSort s) {
    final selected = sort == s;
    final accent = _accent(context);
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
              color: selected ? accent : const Color(0xFF5F6764)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    color: selected ? accent : const Color(0xFFF2F4F3))),
          ),
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
        // Wrapped in the same SecondarySideMenu every other sidebar is
        // built from, so it gets the Sidebar area's background, its border
        // on all four sides, and its padding/margin/radius -- rather than
        // this panel painting an approximation of its own. fillWidth
        // because the feed lays out (and drag-resizes) its width itself.
        var body = SingleChildScrollView(
          // Matches _SidebarNavRow's own 8px inset, so this panel's rows sit
          // where every other sidebar's do rather than floating in from
          // both edges.
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showSearch)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF0E100E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1F231F))),
                child: TextField(
                  controller: searchController,
                  onChanged: onSearch,
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFFF2F4F3)),
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
            _navItem(context, Icons.dynamic_feed_outlined, "All posts",
                FeedView.all),
            if (showBookmarks)
              _navItem(context, Icons.bookmark_outline, "Bookmarks",
                  FeedView.bookmarks,
                  trailing: "${FeedBookmarks.instance.count}"),
            if (showHidden)
              _navItem(context, Icons.visibility_off_outlined, "Hidden",
                  FeedView.hidden,
                  trailing: "${FeedHidden.instance.count}"),
            if (showDrafts)
              _navItem(
                  context, Icons.edit_note_outlined, "Drafts", FeedView.drafts,
                  trailing: "${FeedDrafts.instance.count}"),
            _sectionLabel("POSTS"),
            _actionItem(
                context, Icons.article_outlined, "Your Posts", onYourPosts,
                selected: currentTabIndex == 1),
            _actionItem(
                context, Icons.rss_feed, "Subscriptions", onSubscriptions,
                selected: currentTabIndex == 2),
            _actionItem(context, Icons.add_box_outlined, "New Post", onNewPost,
                selected: currentTabIndex == 3),
            _sectionLabel("SORT"),
            _sortItem(context, "Newest", FeedSort.newest),
            _sortItem(context, "Oldest", FeedSort.oldest),
            _sortItem(context, "Most comments", FeedSort.mostComments),
            _sectionLabel("FILTER"),
            GestureDetector(
              onTap: () => onUnreadOnly(!unreadOnly),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        // Wrapped in the same SecondarySideMenu every other sidebar is
        // built from, so it gets the Sidebar area's background, its border
        // on all four sides, and its padding/margin/radius -- rather than
        // this panel painting an approximation of its own. fillWidth
        // because the feed lays out (and drag-resizes) its width itself.
        //
        // Skipped where the panel is placed inside a sidebar that has
        // already drawn all of that.
        return framed ? SecondarySideMenu(fillWidth: true, child: body) : body;
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
  // Identifies the underlying post so the measured overflow/no-overflow
  // result can be cached across ListView.builder recycling. Without this,
  // scrolling a post out of the cache range and back into view recreates
  // this State from scratch, replaying the "render full height, then snap
  // down to maxHeight next frame" flash every time -- which, repeated for
  // every item revealed while scrolling up, made the list feel like it
  // fought the scroll and never reached the top.
  final String cacheKey;
  const _ClampedContent(
      {required this.child,
      required this.maxHeight,
      required this.onShowMore,
      required this.cacheKey});

  @override
  State<_ClampedContent> createState() => _ClampedContentState();
}

class _ClampedContentState extends State<_ClampedContent> {
  static final Map<String, bool> _overflowCache = {};

  final GlobalKey _key = GlobalKey();
  late bool _overflows = _overflowCache[widget.cacheKey] ?? false;
  bool _measured = false;

  void _measure() {
    // Once a post's overflow state has been measured, trust the cache on
    // subsequent builds/recreations instead of re-measuring -- content for
    // an already-rendered post doesn't change shape, so there's nothing to
    // gain from remeasuring except another height-changing flash.
    if (_measured) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final h = ctx.size?.height ?? 0;
    final over = h > widget.maxHeight + 2;
    _measured = true;
    _overflowCache[widget.cacheKey] = over;
    if (over != _overflows && mounted) setState(() => _overflows = over);
  }

  @override
  void initState() {
    super.initState();
    if (!_overflowCache.containsKey(widget.cacheKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    } else {
      _measured = true;
    }
  }

  @override
  void didUpdateWidget(_ClampedContent old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) {
      _measured = false;
      _overflows = _overflowCache[widget.cacheKey] ?? false;
      if (!_overflowCache.containsKey(widget.cacheKey)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      } else {
        _measured = true;
      }
    }
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

class _ExtractedImage {
  final Uint8List bytes;
  final String tip;
  _ExtractedImage(this.bytes, this.tip);
}

final RegExp _embedRe = RegExp(r'--embed\[(.*?)\]--');

// Finds the first image embed in a post's raw markdown content (skipping
// non-image embeds like quote-posts or file downloads), decodes it, and
// returns it alongside the content with that embed's raw tag removed --
// so callers that pull the image out for separate placement (see
// FeedImageLayout) don't also render it a second time inline via
// MarkdownArea. Returns (null, content unchanged) if there's no image, or
// if AreaStyle.feedImageLayout is FeedImageLayout.standard (the caller is
// expected to skip calling this in that case, but it's harmless either
// way).
(_ExtractedImage?, String) _extractFirstImage(String content) {
  for (final m in _embedRe.allMatches(content)) {
    final raw = m.group(1) ?? "";
    final parms = <String, String>{};
    for (final part in raw.split(",")) {
      final p = part.indexOf("=");
      if (p == -1) continue;
      parms[part.substring(0, p)] = part.substring(p + 1);
    }
    final type = parms["type"] ?? "";
    if (!type.startsWith("image/")) continue;
    final data = parms["data"] ?? "";
    if (data == "") continue;
    try {
      final bytes = base64Decode(data);
      var alt = parms["alt"] ?? "";
      if (alt != "") {
        try {
          alt = Uri.decodeComponent(alt);
        } catch (_) {
          // Keep the raw (undecoded) alt text.
        }
      }
      final stripped = content.replaceRange(m.start, m.end, "");
      return (_ExtractedImage(bytes, alt != "" ? alt : "Image"), stripped);
    } catch (_) {
      continue;
    }
  }
  return (null, content);
}

// Whether a post's raw content contains at least one image embed --
// independent of FeedImageLayout/FeedTextOrder, which only control
// whether/how the *first* image gets specially positioned. Used by
// FeedLinksMode.offIfImage.
bool _hasImageEmbed(String content) => _extractFirstImage(content).$1 != null;

// Removes every image embed from a post's raw content, not just the first
// -- used by FeedImageLayout.none.
String _stripAllImages(String content) {
  var result = content;
  while (true) {
    final (extracted, stripped) = _extractFirstImage(result);
    if (extracted == null) return result;
    result = stripped;
  }
}

// Strips links out of a post's raw markdown content for FeedLinksMode.off/
// offIfImage: markdown-style links ("[label](url)") are reduced to just
// their label text, and bare http(s) URLs are removed outright.
String _stripLinks(String content) {
  var result = content.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? "");
  result = result.replaceAll(RegExp(r'https?://\S+'), "");
  return result;
}

// FeedImageLayout.random deterministically picks one of the concrete
// (non-standard) layouts per post, so the mix looks varied but a given
// post doesn't reshuffle between rebuilds.
const _randomFeedImageLayouts = [
  FeedImageLayout.left,
  FeedImageLayout.right,
  FeedImageLayout.full,
  FeedImageLayout.cropped,
];

FeedImageLayout _resolveFeedImageLayout(
    FeedImageLayout layout, String from, String id) {
  if (layout != FeedImageLayout.random) return layout;
  final hash = "$from:$id".hashCode.abs();
  return _randomFeedImageLayouts[hash % _randomFeedImageLayouts.length];
}

// Renders a feed post's first (extracted) image per FeedImageLayout. Only
// ever called with a concrete (non-standard, non-random) layout --
// FeedImageLayout.random is resolved to one of these by
// _resolveFeedImageLayout before this widget is built.
class _FeedFirstImage extends StatelessWidget {
  final Uint8List bytes;
  final String tip;
  final FeedImageLayout layout;
  final double cropHeight;
  // Whether cropHeight should also cap the "full" layout's height -- true
  // when this layout was resolved from FeedImageLayout.random, since the
  // crop-height slider is shown (and implied to apply) for the whole random
  // rotation, not just the 1-in-4 chance it lands on FeedImageLayout.cropped.
  final bool applyCropCapToFull;
  final VoidCallback onTap;
  const _FeedFirstImage(
      {required this.bytes,
      required this.tip,
      required this.layout,
      required this.cropHeight,
      this.applyCropCapToFull = false,
      required this.onTap});

  // Surfaces decode failures instead of silently swallowing them into an
  // invisible SizedBox.shrink() -- previously a failed decode left a blank,
  // unexplained gap (the reserved box from the layout's fixed height/width
  // stayed, but nothing indicated why nothing was drawn inside it).
  static Widget _errorPlaceholder(Object error, {double? height}) {
    debugPrint("_FeedFirstImage unable to decode image: $error");
    return SizedBox(
      height: height,
      width: double.infinity,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    switch (layout) {
      case FeedImageLayout.left:
      case FeedImageLayout.right:
        image = SizedBox(
          height: 140,
          width: double.infinity,
          child: Image.memory(bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _errorPlaceholder(error, height: 140)),
        );
        break;
      case FeedImageLayout.full:
        image = applyCropCapToFull
            ? _CappedHeightImage(bytes: bytes, maxHeight: cropHeight)
            : Image.memory(bytes,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (context, error, stackTrace) =>
                    _errorPlaceholder(error, height: 140));
        break;
      case FeedImageLayout.cropped:
        image = _CappedHeightImage(bytes: bytes, maxHeight: cropHeight);
        break;
      case FeedImageLayout.standard:
        // Reached only when the image layout is left at Default but a
        // Text order has been chosen -- the image still needs to be
        // extracted to be positioned, but keeps its natural (inline-like)
        // size rather than being stretched or cropped.
        image = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
          child: Image.memory(bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _errorPlaceholder(error, height: 140)),
        );
        break;
      case FeedImageLayout.random:
      case FeedImageLayout.none:
        image = const SizedBox.shrink(); // Unreachable: resolved earlier.
        break;
    }
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
      ),
    );
  }
}

// Renders an image at full available width, only imposing a fixed height
// (and cropping via BoxFit.cover) when the image would naturally render
// taller than maxHeight at that width. Images shorter than maxHeight are
// left at their natural height instead of being scaled up to fill it --
// scaling a short/wide image up to maxHeight while also stretching it to
// fill the available width would crop its sides off, which is the opposite
// of what a height cap should do.
class _CappedHeightImage extends StatefulWidget {
  final Uint8List bytes;
  final double maxHeight;
  const _CappedHeightImage({required this.bytes, required this.maxHeight});

  @override
  State<_CappedHeightImage> createState() => _CappedHeightImageState();
}

class _CappedHeightImageState extends State<_CappedHeightImage> {
  double? _aspectRatio; // width / height of the decoded image.

  @override
  void initState() {
    super.initState();
    _decodeAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _CappedHeightImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      _aspectRatio = null;
      _decodeAspectRatio();
    }
  }

  void _decodeAspectRatio() {
    ui.decodeImageFromList(widget.bytes, (image) {
      if (!mounted) return;
      setState(() => _aspectRatio = image.width / image.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _aspectRatio;
    if (aspectRatio == null) {
      // Aspect ratio not decoded yet: reserve nothing and let the image
      // pop in at its natural size once decoding completes.
      return Image.memory(widget.bytes,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (context, error, stackTrace) =>
              _FeedFirstImage._errorPlaceholder(error, height: 140));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final naturalHeight = constraints.maxWidth / aspectRatio;
      if (naturalHeight <= widget.maxHeight) {
        return Image.memory(widget.bytes,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stackTrace) =>
                _FeedFirstImage._errorPlaceholder(error, height: 140));
      }
      return SizedBox(
        height: widget.maxHeight,
        width: double.infinity,
        child: Image.memory(widget.bytes,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) =>
                _FeedFirstImage._errorPlaceholder(error,
                    height: widget.maxHeight)),
      );
    });
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
    _focus.addListener(_onCtrl);
  }

  // _open is "the composer is in use": focused, or holding text typed
  // earlier. Collapsed it's a single-line box with nothing but the hint --
  // it sits pinned above the feed, so at its full height with a toolbar and
  // a Post button it pushed the first post most of the way off the screen
  // just by existing.
  bool get _open => _focus.hasFocus || _ctrl.text.isNotEmpty;

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onCtrl);
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
    var theme = ThemeNotifier.of(context);
    // Relay is the composer's one filled call-to-action, so it draws as the
    // app's Primary button (ButtonRole.primary) -- the same role as the
    // login screen's Unlock Wallet -- rather than as a pill of its own. It
    // already read accentContainer, which is that role's fill, so this
    // mainly buys it the Buttons theme area's settings and the standard
    // hover/disabled states. The composer's own wider padding is merged in
    // *under* the role style, so a padding set in the editor still wins.
    var relayStyle = theme.buttonStyle(ButtonRole.primary).merge(
        const ButtonStyle(
            padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 26, vertical: 10))));
    var relayOnAccent =
        relayStyle.foregroundColor?.resolve({}) ?? theme.colors.onSurface;
    var inputStyle = theme.areaStyle(ThemeArea.inputAreas);
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
            // One line until it's in use, then the full ~3x compose box.
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              constraints: BoxConstraints(minHeight: _open ? 96 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              // The composer draws its own box rather than an
              // InputDecoration (it holds the tool row as well as the
              // field), so it reads the Input Areas area directly. Unset,
              // it keeps the colours it always had.
              decoration: BoxDecoration(
                color: inputStyle.resolveInputBackgroundColor(theme) ??
                    ((theme.activePreset?.inputBackground.a ?? 0) > 0
                        ? theme.activePreset!.inputBackground
                        : const Color(0xFF0E100E)),
                borderRadius: BorderRadius.circular(
                    inputStyle.inputBorderRadius > 0
                        ? inputStyle.inputBorderRadius
                        : 14),
                border: Border.all(
                    color: inputStyle.resolveInputBorderColor(theme) ??
                        theme.activePreset?.inputResting ??
                        const Color(0xFF1F231F),
                    width: inputStyle.inputBorderWidth > 0
                        ? inputStyle.inputBorderWidth
                        : 1),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                minLines: 1,
                maxLines: _open ? 12 : 1,
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
                  hintStyle: TextStyle(fontSize: 16, color: Color(0xFF5F6764)),
                ),
              ),
            ),
            // The tools and the Relay button only appear once there's
            // something to use them on.
            if (_open) ...[
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
                // A real button rather than a tappable Container: that's
                // what makes it follow the Buttons theme area, fade while
                // posting, and show the same hover as every other button.
                // It also drops the pill's own drop-shadow glow, which no
                // other button in the app has.
                ElevatedButton(
                  onPressed: _posting ? null : _relay,
                  style: relayStyle,
                  child: _posting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: relayOnAccent))
                      : const Text("Relay",
                          // No color: the role's own foreground applies, so
                          // the label follows Text Color 2 like every other
                          // filled button.
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2)),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
