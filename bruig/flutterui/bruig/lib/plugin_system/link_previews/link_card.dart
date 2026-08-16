import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/feed_render_scope.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/link_previews/youtube_player.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Builds the preview card for a bare URL, for the markdown extension the
/// link-card capability registers (see markdown_extension.dart).
class LinkCardElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // LinkCard is an image/button widget, not selectable text -- posts
    // render their markdown inside a SelectionArea (chat messages don't),
    // and without opting out here that area paints the whole card as one
    // undifferentiated "selected" region (a solid blue overlay) instead of
    // leaving it alone.
    return SelectionContainer.disabled(
        child: LinkCard(element.textContent,
            preferredStyle: preferredStyle,
            alone:
                element.attributes[BareLinkSyntax.aloneAttribute] == "true"));
  }
}

// _players maps a player name a plugin may ask for (LinkMetadata.player) to
// the widget that provides it. This is the whole of the app's knowledge
// about playable links: which *hosts* are playable is the claiming plugin's
// decision, declared per-URL in the metadata it returns, so adding a new
// video site is a plugin change rather than a change here.
//
// A name with no entry falls back to the ordinary still-thumbnail card, so
// a plugin asking for a player this build doesn't ship degrades instead of
// breaking.
final Map<String, Widget Function(String url)> _players = {
  "youtube": YoutubeInlineVideo.new,
};

/// Shows an "unfurl" card (thumbnail, title, author) for URLs a link-card
/// provider claims, fetched via the proxied Go-side Golib.fetchLinkMetadata
/// call. Falls back to a plain, clickable link (the same look bare autolinks
/// would otherwise get) while loading, on error,
/// or when no plugin claims the URL.
///
/// The card always claims the full width of its content area (a
/// SizedBox(width: double.infinity)): since flutter_markdown lays out
/// inline content in a Wrap, a full-width child can never share a line with
/// surrounding text, so this also guarantees the card always starts on its
/// own line.
class LinkCard extends StatefulWidget {
  final String url;
  final TextStyle? preferredStyle;

  /// alone is whether the URL was the whole of what it was written in, rather
  /// than one sitting in a sentence -- see BareLinkSyntax.aloneAttribute.
  final bool alone;

  const LinkCard(this.url,
      {this.preferredStyle, this.alone = false, super.key});

  @override
  State<LinkCard> createState() => _LinkCardState();
}

// Caches successful metadata fetches for the lifetime of the app process,
// keyed by URL. LinkCard is recreated (and would otherwise re-fetch over
// the network) every time its message scrolls out of view and back --
// e.g. in a long chat/feed's lazily-built list -- so without this cache
// the same link refetches every time it's scrolled past. Only successful
// fetches are cached: a null result (network hiccup, plugin not handling
// the URL) is left uncached so a later render can still retry rather than
// permanently freezing on a transient failure.
final Map<String, LinkMetadata> _linkMetadataCache = {};

/// seedLinkMetadata puts a fetch result in the cache without one having been
/// made.
///
/// For tests: a card only draws once the metadata has arrived, and the fetch
/// goes through the client, so without this the only thing a test can ever
/// see is the plain link shown while loading -- which is not the part with a
/// layout to get wrong.
@visibleForTesting
void seedLinkMetadata(String url, LinkMetadata metadata) =>
    _linkMetadataCache[url] = metadata;

class _LinkCardState extends State<LinkCard> {
  LinkMetadata? _metadata;
  bool _loading = true;
  bool _playing = false;

  // _player is the player this link's provider asked for, or null for an
  // ordinary card -- including when it named one this build doesn't have.
  Widget Function(String)? get _player => _players[_metadata?.player ?? ""];

  @override
  void initState() {
    super.initState();
    var cached = _linkMetadataCache[widget.url];
    if (cached != null) {
      _metadata = cached;
      _loading = false;
    } else {
      _fetch();
    }
  }

  void _fetch() async {
    LinkMetadata? metadata;
    try {
      metadata = await Golib.fetchLinkMetadata(widget.url);
      if (metadata != null) {
        _linkMetadataCache[widget.url] = metadata;
      }
    } catch (_) {
      metadata = null;
    }
    if (!mounted) return;
    setState(() {
      _metadata = metadata;
      _loading = false;
    });
  }

  void _openInBrowser() async {
    if (!await launchUrl(Uri.parse(widget.url))) {
      if (!mounted) return;
      SnackBarModel.of(context).error("Could not launch ${widget.url}");
    }
  }

  Widget _buildPlainLink(BuildContext context) {
    // Set exactly as a written-out markdown link is set, style guide and
    // all, rather than in the raw Material accent with an underline added
    // here regardless.
    //
    // It is the same thing on the page, so it has to be the same thing on
    // screen. Drawn its own way it was a different colour from a
    // [text](url) link in the same post, and it carried an underline in
    // every guide -- including the ones, Default among them, that ask for
    // no underline at all. That is the mismatch between the settings
    // preview and a real post.
    return GestureDetector(
      onTap: _openInBrowser,
      child: Text(widget.url,
          style: ThemeNotifier.of(context)
              .markdownLinkStyle(widget.preferredStyle)),
    );
  }

  // _thumbAspectRatio is the standard 16:9 a thumbnail is drawn at, and what
  // YoutubeInlineVideo uses once playing starts.
  static const _thumbAspectRatio = 16 / 9;

  Widget _buildThumbnailArea(Uint8List? thumbBytes, FeedRenderScope? scope) {
    var player = _player;

    // A thumbnail is a picture in a post, so the Feed area's First image
    // display governs it: None means the card keeps its title and
    // description but shows nothing, and the player goes with it -- there is
    // no sense in a play button over a picture the reader asked not to see.
    if (scope?.imagesHidden ?? false) return const SizedBox.shrink();

    if (_playing && player != null) {
      return player(widget.url);
    }

    if (thumbBytes == null && player == null) {
      // No image available and nothing to play in its place -- collapse
      // the area entirely instead of showing an empty placeholder box.
      return const SizedBox.shrink();
    }

    // The thumbnail's size is computed explicitly from the available width
    // via LayoutBuilder rather than using an AspectRatio widget directly:
    // AspectRatio derives its size from the incoming constraints, and in
    // some rendering contexts (e.g. posts) the width isn't as tightly
    // bounded as it is for chat messages, which made AspectRatio blow up to
    // an oversized height that covered the rest of the post.
    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;

      var height = width / _thumbAspectRatio;

      // Cropped, Left and Right all cap how tall a picture in a post may be,
      // and a 16:9 thumbnail derived from the full width ignores that -- a
      // card in a feed cropped to 200px was three times the height of the
      // pictures beside it.
      //
      // The height is cut and the width left alone, which is what "cropped"
      // means: the thumbnail is already drawn with BoxFit.cover, so a
      // shorter box crops it rather than shrinking it. Narrowing the card to
      // keep 16:9 instead -- which is what this did first -- made the card
      // stop short of the column it was in, so a link preview no longer ran
      // the full width of the feed.
      var cap = scope?.mediaMaxHeight;
      if (cap != null && cap < height) height = cap;

      var thumbnail = thumbBytes != null
          ? Image.memory(thumbBytes,
              fit: BoxFit.cover, width: width, height: height)
          : Container(width: width, height: height, color: Colors.black26);

      if (player == null) {
        return thumbnail;
      }

      return GestureDetector(
        onTap: () => setState(() => _playing = true),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(alignment: Alignment.center, children: [
            thumbnail,
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 40),
            ),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // A link card is a link, drawn richly. Where the Feed area has taken
    // links away, there is nothing for it to draw: the feed removes bare
    // URLs from a post's own body, so what reaches here is a URL inside
    // something nested -- a quoted post -- which was still unfurling cards
    // in a feed set to show no links at all.
    var scope = FeedRenderScope.of(context);
    if (scope?.linksDisabled ?? false) return const SizedBox.shrink();

    if (_loading) {
      // Render the plain link immediately so text flows normally while the
      // metadata fetch (which may be slow, or may never resolve) completes
      // in the background; it's replaced by the card if/when it arrives.
      return _buildPlainLink(context);
    }

    var metadata = _metadata;
    if (metadata == null) {
      return _buildPlainLink(context);
    }

    var theme = Theme.of(context);

    Uint8List? thumbBytes;
    if (metadata.thumbnailB64.isNotEmpty) {
      try {
        thumbBytes = base64Decode(metadata.thumbnailB64);
      } catch (_) {
        thumbBytes = null;
      }
    }

    Widget card = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThumbnailArea(thumbBytes, scope),
          Padding(
            // Tighter in a narrow column, where 8px on each side of a
            // 260px card is a noticeable share of it.
            padding: EdgeInsets.all((scope?.narrow ?? false) ? 6 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (metadata.title.isNotEmpty)
                  Txt.S(metadata.title,
                      color: TextColor.onSurface,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                // Author acts as the card's header when there's no title
                // (e.g. tweets, whose oEmbed response has no title field
                // at all) so the card doesn't just open on a wall of
                // unstyled paragraph text.
                if (metadata.author.isNotEmpty)
                  Txt.S(metadata.author,
                      color: TextColor.onSurface,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                if (metadata.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: theme.dividerColor, width: 2)),
                      ),
                      child: Txt.S(metadata.description,
                          color: TextColor.onSurfaceVariant,
                          style: const TextStyle(fontStyle: FontStyle.italic)),
                    ),
                  ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _openInBrowser,
                  // The label gives way rather than overflowing. A card is
                  // now drawn at whatever width the Chat area's Image size
                  // or the feed's media column allows, and at a quarter of
                  // a narrow message "Open in Browser" is wider than the
                  // card it sits in.
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Txt.S("Open in Browser",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // How large the card is allowed to grow, in a chat message.
    //
    // The Chat area's Image size, read as a *maximum* rather than as a share
    // to be drawn at: a card fills whatever it is given, so nothing inside
    // it is ever left with a gap beside it, but it does not grow past the
    // size a picture in the same message would be allowed. Half means a card
    // no wider than a half-width picture, filled edge to edge.
    //
    // Chat is the case with no feed scope and a width handed down from the
    // message: ChatImageWidth is installed by the chat message path and by
    // nothing else. Default has no share to take, so the card is left at the
    // width of the bubble, which is what a preview has always been drawn at
    // -- unlike a picture, a card has no natural size for the 250pt bound to
    // be a bound on.
    var messageWidth = scope == null ? ChatImageWidth.of(context) : null;
    if (messageWidth != null) {
      var max = chatImageWidth(
              ThemeNotifier.of(context).chatImageSize, messageWidth) ??
          messageWidth;
      card = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max), child: card);
    }

    // No claim on the width of the line: the card is a block in its own
    // paragraph by the time it gets here (see MarkdownExtension.standalone),
    // so nothing can be seated beside it and it need only be as wide as it
    // draws. That is what lets a chat bubble -- as wide as its widest
    // content -- fit the card instead of running the width of the window.
    return card;
  }
}
