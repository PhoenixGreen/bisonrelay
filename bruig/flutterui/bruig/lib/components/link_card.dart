import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/text.dart';
import 'package:bruig/components/youtube_video_player.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Builds the native "Pretty Links" preview card for bare URLs matched by
/// BareLinkSyntax (see md_elements.dart).
class LinkCardElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // LinkCard is an image/button widget, not selectable text -- posts
    // render their markdown inside a SelectionArea (chat messages don't),
    // and without opting out here that area paints the whole card as one
    // undifferentiated "selected" region (a solid blue overlay) instead of
    // leaving it alone.
    return SelectionContainer.disabled(
        child: LinkCard(element.textContent, preferredStyle: preferredStyle));
  }
}

const _youtubeHosts = {
  "youtube.com",
  "www.youtube.com",
  "youtu.be",
  "m.youtube.com",
};

bool _isYoutubeUrl(String url) {
  try {
    var host = Uri.parse(url).host.toLowerCase();
    return _youtubeHosts.contains(host);
  } catch (_) {
    return false;
  }
}

/// Shows a native "unfurl" card (thumbnail, title, author) for URLs an
/// enabled plugin recognizes, fetched via the proxied Go-side
/// Golib.fetchLinkMetadata call. Falls back to a plain, clickable link (the
/// same look bare autolinks would otherwise get) while loading, on error,
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
  const LinkCard(this.url, {this.preferredStyle, super.key});

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

class _LinkCardState extends State<LinkCard> {
  LinkMetadata? _metadata;
  bool _loading = true;
  bool _playing = false;

  bool get _isYoutube => _isYoutubeUrl(widget.url);

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
    var theme = Theme.of(context);
    return GestureDetector(
      onTap: _openInBrowser,
      child: Text(widget.url,
          style: (widget.preferredStyle ?? const TextStyle()).copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline)),
    );
  }

  Widget _buildThumbnailArea(Uint8List? thumbBytes) {
    if (_playing) {
      return YoutubeInlineVideo(widget.url);
    }

    if (thumbBytes == null && !_isYoutube) {
      // No image available and nothing to play in its place -- collapse
      // the area entirely instead of showing an empty placeholder box.
      return const SizedBox.shrink();
    }

    // Standard thumbnail aspect ratio (matches YoutubeInlineVideo's own
    // AspectRatio once playing starts). Computed explicitly from the
    // available width via LayoutBuilder rather than using an AspectRatio
    // widget directly: AspectRatio derives its size from the incoming
    // constraints, and in some rendering contexts (e.g. posts) the width
    // isn't as tightly bounded as it is for chat messages, which made
    // AspectRatio blow up to an oversized height that covered the rest of
    // the post.
    const thumbAspectRatio = 16 / 9;

    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
      var height = width / thumbAspectRatio;

      var thumbnail = thumbBytes != null
          ? Image.memory(thumbBytes,
              fit: BoxFit.cover, width: width, height: height)
          : Container(width: width, height: height, color: Colors.black26);

      if (!_isYoutube) {
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

    return SizedBox(
      width: double.infinity,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThumbnailArea(thumbBytes),
            Padding(
              padding: const EdgeInsets.all(8),
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
                            style:
                                const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                    ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _openInBrowser,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Txt.S("Open in Browser",
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
