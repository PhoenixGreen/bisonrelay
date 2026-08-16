import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/widgets.dart';

// feed_render_scope.dart is how the Feed area's presentation settings reach
// the things a post contains rather than the post itself.
//
// A post's own body is shaped by feed_posts.dart, which has the settings in
// hand: it strips the images out, pulls the first one aside, cuts the text to
// length and takes the links away before any of it is rendered. Everything
// *inside* the post is drawn by a markdown builder several layers below --
// a quoted post, a link card -- and those builders are handed a markdown
// element and nothing else. They had no way to know a reader had asked for
// no links, or for pictures no taller than 200px, so they went on drawing
// full-width thumbnails and live link cards in a feed set to show neither.
//
// The scope is that missing argument. feed_posts.dart installs one around
// each card; the builders read it if it is there. Absent -- in chat, in a
// post opened on its own, in the composer's preview -- means "as it was",
// which is what keeps this a feed-page feature.

/// ExtractedImage is one image embed lifted out of a post's raw markdown.
class ExtractedImage {
  final Uint8List bytes;
  final String tip;
  ExtractedImage(this.bytes, this.tip);
}

final RegExp _embedRe = RegExp(r'--embed\[(.*?)\]--');

/// extractFirstImage finds the first image embed in a post's raw markdown
/// content (skipping non-image embeds like quote-posts or file downloads),
/// decodes it, and returns it alongside the content with that embed's raw
/// tag removed -- so callers that pull the image out for separate placement
/// (see FeedImageLayout) don't also render it a second time inline.
///
/// Returns (null, content unchanged) if there's no image.
(ExtractedImage?, String) extractFirstImage(String content) {
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
      return (ExtractedImage(bytes, alt != "" ? alt : "Image"), stripped);
    } catch (_) {
      continue;
    }
  }
  return (null, content);
}

/// hasImageEmbed reports whether the content carries a decodable image.
bool hasImageEmbed(String content) => extractFirstImage(content).$1 != null;

final RegExp _bareUrlRe = RegExp(r'https?://\S+');

/// extractFirstCard finds the first thing in a post that is drawn as a card
/// rather than set as text -- a quoted post, or a bare URL the link-card
/// capability will unfurl -- and returns it alongside the content with it
/// removed.
///
/// The point of pulling it out is that a card is a picture as far as the
/// layout is concerned. "First image display" says where a post's one piece
/// of media goes, and a post whose media is a quoted post or a link preview
/// was ignoring the setting entirely: the card sat full width under the
/// writing while a picture in the same feed sat in a column beside it.
///
/// [claimsLink] is asked of each bare URL, and only one somebody will
/// actually unfurl counts. Null means no URL does.
///
/// Asked per URL rather than once for the whole feed, because that is the
/// shape of the answer: a link-card provider declares the hostnames it knows
/// and says nothing about the rest of the web. Treating every URL as a card
/// because *some* provider is installed put a bare zerohedge.com link -- which
/// nothing unfurls, so it renders as ordinary link text -- alone in the media
/// column, wrapped over five lines. A link that will not become a card is not
/// a card, and belongs in the writing with the rest of the text.
///
/// Returns (null, content unchanged) when there is nothing of the kind.
(String?, String) extractFirstCard(String content,
    {bool Function(String url)? claimsLink}) {
  // A quoted post first: it is unambiguously a card, and a quoted post that
  // happens to also contain a URL should be placed as the quote it is.
  for (final m in _embedRe.allMatches(content)) {
    final raw = m.group(1) ?? "";
    if (!raw.split(",").any((p) => p.trim() == "type=quote")) continue;
    return (m.group(0), content.replaceRange(m.start, m.end, ""));
  }

  if (claimsLink == null) return (null, content);

  // The first *claimed* URL, not simply the first: a post opening with a
  // link to somebody's blog and going on to a YouTube link has a card, and
  // it is the YouTube one.
  for (final m in _bareUrlRe.allMatches(content)) {
    final url = m.group(0)!;
    if (!claimsLink(url)) continue;
    return (url, content.replaceRange(m.start, m.end, ""));
  }
  return (null, content);
}

/// limitText cuts content to [limit] characters without cutting an embed in
/// half. 0 means no limit.
///
/// An embed is one token -- `--embed[type=image/jpeg,data=...]--` -- and the
/// data in it is a whole picture in base64, so a single embed is routinely
/// tens of thousands of characters long. Cutting at the limit therefore lands
/// inside one far more often than not, and half an embed is not an embed: it
/// no longer parses, so the reader is shown the raw tag and a wall of base64
/// where the picture should be.
///
/// The cut moves back to the start of any embed it lands in. An embed is
/// either wholly in or wholly out.
String limitText(String content, double limit) {
  if (limit <= 0 || content.length <= limit) return content;
  var cut = limit.toInt();
  for (final m in _embedRe.allMatches(content)) {
    if (m.start >= cut) break;
    if (m.end > cut) {
      cut = m.start;
      break;
    }
  }
  // A post opening with a picture bigger than the limit cuts to nothing at
  // all, which reads as a broken card rather than as a short one. The embed
  // is kept and the writing after it is what gets cut.
  if (cut == 0) {
    final first = _embedRe.firstMatch(content);
    if (first != null && first.start == 0) {
      return content.substring(0, first.end) +
          limitText(content.substring(first.end), limit);
    }
  }
  return "${content.substring(0, cut)}…";
}

/// stripAllImages removes every image embed, not just the first -- what
/// FeedImageLayout.none asks for.
String stripAllImages(String content) {
  var result = content;
  while (true) {
    final (extracted, stripped) = extractFirstImage(result);
    if (extracted == null) return result;
    result = stripped;
  }
}

/// stripLinks takes the links out of raw markdown for FeedLinksMode.off and
/// offIfImage: a written-out link ("[label](url)") is reduced to its label,
/// and a bare http(s) URL is removed outright.
String stripLinks(String content) {
  var result = content.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? "");
  result = result.replaceAll(RegExp(r'https?://\S+'), "");
  return result;
}

// _randomFeedImageLayouts is what FeedImageLayout.random draws from. The
// pick is deterministic per post, so the mix looks varied but a given post
// doesn't reshuffle between rebuilds.
const _randomFeedImageLayouts = [
  FeedImageLayout.left,
  FeedImageLayout.right,
  FeedImageLayout.full,
  FeedImageLayout.cropped,
];

/// resolveFeedImageLayout turns FeedImageLayout.random into the concrete
/// layout this post gets; every other layout is already concrete.
FeedImageLayout resolveFeedImageLayout(
    FeedImageLayout layout, String from, String id) {
  if (layout != FeedImageLayout.random) return layout;
  final hash = "$from:$id".hashCode.abs();
  return _randomFeedImageLayouts[hash % _randomFeedImageLayouts.length];
}

/// FeedRenderScope carries one post card's presentation settings down to
/// whatever that post contains.
///
/// An InheritedWidget rather than a parameter for the same reason
/// MarkdownGuideScope is one: the widget that draws a quoted post or a link
/// card is built by flutter_markdown from a builder, well below whoever read
/// the settings, and there is no argument to thread down.
class FeedRenderScope extends InheritedWidget {
  /// linksDisabled is the Links setting, already resolved against whether
  /// this particular post has an image (FeedLinksMode.offIfImage).
  final bool linksDisabled;

  /// imageLayout is First image display, with random already resolved to the
  /// concrete layout this post drew.
  final FeedImageLayout imageLayout;

  /// cropHeight is the Cropped image max height slider.
  final double cropHeight;

  /// textLimit is Limit text, in characters; 0 means no limit.
  final double textLimit;

  /// stripMarkdown is Strip markdown formatting.
  final bool stripMarkdown;

  const FeedRenderScope({
    required this.linksDisabled,
    required this.imageLayout,
    required this.cropHeight,
    required this.textLimit,
    required this.stripMarkdown,
    required super.child,
    super.key,
  });

  static FeedRenderScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedRenderScope>();

  /// asMedia is this scope as it applies *inside* the media column.
  ///
  /// A card placed in the column beside the post's writing is itself the
  /// media, so whatever is inside it should not be split side by side all
  /// over again -- a quoted post in a 260px column with its own picture in a
  /// 110px column beside its own text is three columns of nothing. Inside
  /// the card the picture goes above the writing, capped to the same height
  /// the column is.
  FeedRenderScope asMedia({required Widget child}) => FeedRenderScope(
        linksDisabled: linksDisabled,
        imageLayout: FeedImageLayout.cropped,
        cropHeight: mediaMaxHeight ?? cropHeight,
        textLimit: textLimit,
        stripMarkdown: stripMarkdown,
        child: child,
      );

  /// cardColumnWidth is how wide a card is drawn when it is the media in a
  /// Left or Right layout.
  ///
  /// Wider than the 140px a picture gets, because a card is not a picture:
  /// it carries a title, an author and a line or two of description, and at
  /// 140px every one of those wraps to one word a line.
  static const double cardColumnWidth = 260;

  /// imagesHidden is First image display set to None, which means no
  /// pictures at all -- including the thumbnail on a link card and the ones
  /// inside a quoted post.
  bool get imagesHidden => imageLayout == FeedImageLayout.none;

  /// narrow is a layout that puts the picture in a column beside the text
  /// (Left or Right). Anything nested renders in the same narrow column, so
  /// it is drawn compactly rather than at the width it would take on its own.
  bool get narrow =>
      imageLayout == FeedImageLayout.left ||
      imageLayout == FeedImageLayout.right;

  /// mediaMaxHeight is the cap a nested picture is drawn under, or null for
  /// no cap.
  ///
  /// Cropped means it, and Left/Right are already height-limited to the
  /// column beside the text -- so a link card's 16:9 thumbnail inside one
  /// gets the same treatment rather than towering over the post it sits in.
  double? get mediaMaxHeight => switch (imageLayout) {
        FeedImageLayout.cropped => cropHeight,
        FeedImageLayout.left || FeedImageLayout.right => 140,
        _ => null,
      };

  /// constrain applies the settings that are about *text* to a nested post's
  /// raw markdown -- the images, which need placing rather than editing, are
  /// left to whoever draws them.
  String constrain(String content) {
    var result = content;
    if (imagesHidden) result = stripAllImages(result);
    if (linksDisabled) result = stripLinks(result);
    return limitText(result, textLimit);
  }

  @override
  bool updateShouldNotify(FeedRenderScope old) =>
      old.linksDisabled != linksDisabled ||
      old.imageLayout != imageLayout ||
      old.cropHeight != cropHeight ||
      old.textLimit != textLimit ||
      old.stripMarkdown != stripMarkdown;
}
