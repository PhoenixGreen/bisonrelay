import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/screens/feed/post_content.dart';
import 'package:bruig/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
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
    var redesign =
        ThemeNotifier.of(context).areaStyle(ThemeArea.feed).feedCardRedesign;

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

class _FeedPostsState extends State<FeedPosts> {
  void feedChanged() async {
    setState(() {});
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var posts = widget.onlyShowOwnPosts
        ? widget.feed.posts
            .where((post) => (post.summ.authorID == widget.client.publicID))
        : widget.feed.posts;
    return SelectionArea(
        child: Container(
      padding: const EdgeInsets.only(left: 10, right: 0, top: 0, bottom: 10),
      child: ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) {
            var post = posts.elementAt(index);
            var author = widget.client.getExistingChat(post.summ.authorID);
            var from = widget.client.getExistingChat(post.summ.from);
            return FeedPostW(widget.feed, post, author, from, widget.client,
                widget.tabChange);
          }),
    ));
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
