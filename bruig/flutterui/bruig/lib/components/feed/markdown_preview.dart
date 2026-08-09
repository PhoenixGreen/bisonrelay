import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/image_header.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:flutter/material.dart';

// markdown_preview.dart turns the composer's markdown source into styling for
// the field it is being typed into, so a post can be written while it looks
// roughly like what it will become.
//
// It styles the source rather than replacing it. Flutter's editable text maps
// the caret onto the characters the field holds, so a preview that removed
// the "**" around a bold word would put every click and every arrow key after
// it out of step. The markers stay where they are and are shrunk out of
// sight, which costs a keypress to step over one and keeps every offset
// honest -- the same bargain a live-preview editor always makes.
//
// The one thing that genuinely is replaced is an embedded image, and it is
// allowed exactly one character to stand on. See InlineDecoration.widget.

/// _invisible hides a marker without removing it.
///
/// A transparent colour alone still reserves the marker's full width, which
/// leaves a gap where the "##" was; a tiny size closes the gap. Not zero,
/// which some text shapers refuse.
/// Spacing is zeroed as well as the size. A hidden run inherits the field's
/// letter and word spacing, and an embed is over a hundred characters long --
/// enough to push its picture most of a line to the right on nothing but the
/// gaps between letters nobody can see. Measured at 78 pixels before this.
const _invisible = TextStyle(
  fontSize: 0.01,
  color: Colors.transparent,
  letterSpacing: 0,
  wordSpacing: 0,
);

const _headingSizes = [26.0, 22.0, 19.0, 17.0, 16.0, 15.0];

final _heading = RegExp(r"^(#{1,6})([ \t]+)(.*)$", multiLine: true);
final _bold = RegExp(r"(\*\*|__)(?=\S)(.+?)(?<=\S)\1", dotAll: false);
final _italic = RegExp(r"(?<![*\w])(\*|_)(?=\S)([^*_\n]+?)(?<=\S)\1(?![*\w])");
final _strike = RegExp(r"(~~)(?=\S)(.+?)(?<=\S)\1");
final _code = RegExp(r"(`)([^`\n]+?)(`)");
final _fence = RegExp(r"^```.*$", multiLine: true);
final _quote = RegExp(r"^([ \t]*>[ \t]?)(.*)$", multiLine: true);
final _bullet = RegExp(r"^([ \t]*)([-*+]|\d+\.)([ \t]+)", multiLine: true);
final _link = RegExp(r"(\[)([^\]\n]+)(\]\()([^)\n]+)(\))");
final _rule = RegExp(r"^([-*_])\1{2,}$", multiLine: true);
final _embed = RegExp(r"--embed\[(.*?)\]--");

/// markdownDecorations is what the composer's field paints itself with while
/// the preview is on.
///
/// [embeds] maps a tracked embed id to its base64 data, which the composer
/// holds in memory from the moment a file is picked -- so the picture can be
/// built during the field's own build, with nothing to wait for.
/// [guide] is the style guide the post is being written in, or null for the
/// app's own preview styling. When one is given, every rule below is taken
/// from it -- so what the writer sees in the composer is what a reader with
/// that guide will see.
///
/// [roleColor] resolves the guide's colour roles against the live theme, and
/// is required whenever a guide is given.
List<InlineDecoration> markdownDecorations(
  String text, {
  Map<String, String> embeds = const {},
  Color? muted,
  Color? link,
  double baseSize = 14,
  MarkdownStyleGuide? guide,
  Color Function(MarkdownRole)? roleColor,
  ImageRule? image,
}) {
  var resolve = roleColor ?? (_) => const Color(0xFF000000);
  var base = TextStyle(fontSize: baseSize);

  /// from applies a guide's rule, or falls back to what the preview drew
  /// before guides existed.
  TextStyle from(TextRule? rule, TextStyle fallback) =>
      rule == null ? fallback : rule.applyTo(base, resolve);

  // Two lists, because order decides the outcome: a decoration later in the
  // list wins where they overlap, and the hidden markers have to beat the
  // style of the thing they mark. Written the other way round the heading's
  // font size was applied over the top of its own hidden "##", which is how
  // this was found.
  var out = <InlineDecoration>[];
  var hides = <InlineDecoration>[];
  void hide(int start, int end) {
    if (end > start) hides.add(InlineDecoration(start, end, _invisible));
  }

  void style(int start, int end, TextStyle style) {
    if (end > start) out.add(InlineDecoration(start, end, style));
  }

  // Blocks first, so an inline run inside a heading is styled on top of the
  // heading's size rather than instead of it.
  for (var m in _heading.allMatches(text)) {
    var level = m.group(1)!.length;
    hide(m.start, m.start + m.group(1)!.length + m.group(2)!.length);
    style(
        m.start,
        m.end,
        from(
            guide?.headings[level - 1],
            TextStyle(
                fontSize: _headingSizes[level - 1],
                fontWeight: FontWeight.w700)));
  }
  for (var m in _quote.allMatches(text)) {
    hide(m.start, m.start + m.group(1)!.length);
    style(
        m.start,
        m.end,
        from(guide?.quote,
            TextStyle(fontStyle: FontStyle.italic, color: muted)));
  }
  for (var m in _bullet.allMatches(text)) {
    // The marker is kept and dimmed rather than hidden: a list with no
    // bullets at all reads as loose lines, and "-" cannot be turned into a
    // round bullet without replacing the character.
    style(
        m.start + m.group(1)!.length,
        m.start + m.group(1)!.length + m.group(2)!.length,
        from(guide?.listBullet,
            TextStyle(color: muted, fontWeight: FontWeight.w700)));
  }
  for (var m in _rule.allMatches(text)) {
    style(m.start, m.end, TextStyle(color: muted, letterSpacing: -1));
  }
  for (var m in _fence.allMatches(text)) {
    style(m.start, m.end, TextStyle(color: muted, fontSize: baseSize - 2));
  }

  for (var m in _bold.allMatches(text)) {
    hide(m.start, m.start + m.group(1)!.length);
    hide(m.end - m.group(1)!.length, m.end);
    style(m.start, m.end,
        from(guide?.strong, const TextStyle(fontWeight: FontWeight.w700)));
  }
  for (var m in _italic.allMatches(text)) {
    hide(m.start, m.start + 1);
    hide(m.end - 1, m.end);
    style(m.start, m.end,
        from(guide?.emphasis, const TextStyle(fontStyle: FontStyle.italic)));
  }
  for (var m in _strike.allMatches(text)) {
    hide(m.start, m.start + 2);
    hide(m.end - 2, m.end);
    style(m.start, m.end,
        const TextStyle(decoration: TextDecoration.lineThrough));
  }
  for (var m in _code.allMatches(text)) {
    hide(m.start, m.start + 1);
    hide(m.end - 1, m.end);
    style(
        m.start,
        m.end,
        from(guide?.code,
            const TextStyle(fontFamily: "monospace", letterSpacing: -0.3)));
  }
  for (var m in _link.allMatches(text)) {
    // The label is left readable and everything that makes it a link -- the
    // brackets and the target -- goes away.
    hide(m.start, m.start + 1);
    hide(m.start + 1 + m.group(2)!.length, m.end);
    style(
        m.start,
        m.end,
        from(guide?.link,
            TextStyle(color: link, decoration: TextDecoration.underline)));
  }

  for (var m in _embed.allMatches(text)) {
    var picture = _embedWidget(m.group(1) ?? "", embeds, image, resolve);
    if (picture == null) {
      // Nothing to show it with, so it stays legible rather than becoming an
      // invisible run of characters the caret walks through for no reason.
      style(m.start, m.end, TextStyle(color: muted, fontSize: baseSize - 2));
      continue;
    }
    // Everything but the last character disappears, and the picture stands
    // on the one that is left -- the most a widget may cover without moving
    // every offset after it.
    hide(m.start, m.end - 1);
    out.add(
        InlineDecoration(m.end - 1, m.end, const TextStyle(), widget: picture));
  }

  return [...out, ...hides];
}

/// _decoded holds the bytes of each embed that has been drawn, keyed by the
/// base64 it came from.
///
/// It is here to stop the pictures flickering on every keystroke, and the
/// reason is exact: MemoryImage compares equal to another only when it holds
/// the same bytes *object*, because Uint8List does not define equality and
/// falls back to identity. The field rebuilds on every edit, so decoding
/// afresh each time handed Flutter an image provider it had never seen,
/// which threw away the decoded frame and started again.
///
/// Bounded, because this outlives any one post. Sixteen is far more than a
/// post has pictures in it, and the whole map is dropped rather than tracking
/// which entry was used least recently -- the cost of being wrong is one
/// decode.
final Map<String, Uint8List> _decoded = {};
const _decodedLimit = 16;

Uint8List? _bytesFor(String data) {
  var known = _decoded[data];
  if (known != null) return known;
  try {
    var bytes = base64Decode(data);
    if (_decoded.length >= _decodedLimit) _decoded.clear();
    _decoded[data] = bytes;
    return bytes;
  } catch (_) {
    // Half-typed base64 in a field somebody is still editing is ordinary.
    return null;
  }
}

/// _embedWidget builds the picture for one embed, or null when there is not
/// one to build -- a quote, a file download, a type this cannot draw, or data
/// that is not there.
Widget? _embedWidget(String params, Map<String, String> embeds,
    ImageRule? image, Color Function(MarkdownRole) roleColor) {
  var parsed = <String, String>{};
  for (var part in params.split(",")) {
    var at = part.indexOf("=");
    if (at > 0) parsed[part.substring(0, at)] = part.substring(at + 1);
  }

  const drawable = {
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/bmp",
    "image/webp",
  };
  if (!drawable.contains(parsed["type"])) return null;

  var data = parsed["data"] ?? "";
  // While a post is being written the data is a reference to something the
  // composer is holding for it; the base64 itself only goes into the text on
  // the way out. Both forms are accepted so a draft reopened from the post
  // library shows its pictures too.
  var reference = RegExp(r"^\[content ([a-zA-Z0-9]{12})\]$").firstMatch(data);
  if (reference != null) data = embeds[reference.group(1)] ?? "";
  if (data.isEmpty) return null;

  var bytes = _bytesFor(data);
  if (bytes == null) return null;

  {
    // The size has to be settled before the line is laid out, so it is read
    // out of the header rather than left to the Image widget. An Image
    // measures zero until its bytes have been decoded, which happens after
    // layout -- so the line reserved no room at all and the picture landed
    // on top of the text above it.
    var natural = imageDimensions(bytes);
    if (natural == null) return null;

    // The guide's share of the column, applied to the same bound the
    // preview has always used. A field this wide is what the composer gives
    // it, so 100% is that and 60% is six tenths of it.
    var maxWidth = 420.0 * (image?.boundedWidth ?? 100) / 100;
    var size = fitWithin(natural, maxWidth, 260);

    var picture = Image.memory(
      bytes,
      fit: BoxFit.contain,
      // Keep showing the frame already decoded while any new one is being
      // prepared, rather than blanking in between.
      gaplessPlayback: true,
    );

    var radius = BorderRadius.circular(image?.boundedRadius ?? 0);
    var border = image == null || image.boundedBorder == 0
        ? null
        : Border.all(
            color:
                image.borderInk.resolve(roleColor) ?? const Color(0xFF808080),
            width: image.boundedBorder);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: image?.gap ?? 4),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: border == null
            ? null
            : BoxDecoration(border: border, borderRadius: radius),
        child: ClipRRect(borderRadius: radius, child: picture),
      ),
    );
  }
}

/// composerEmbeds is the post model's embed table, or an empty one.
Map<String, String> composerEmbeds(NewPostModel? post) =>
    post?.embedContents ?? const {};
