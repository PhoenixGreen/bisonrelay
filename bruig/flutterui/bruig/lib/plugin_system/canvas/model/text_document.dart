import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// text_document.dart is a text element whose words come from the Writing
// library. The words are copied into the element, not read while drawing:
// a canvas must draw the same without the library, and a painter cannot
// wait for a disk. The reference is kept so changes can be read again.

/// MarkdownKind is a piece of markdown a document-backed element honours.
enum MarkdownKind {
  heading1("Heading 1", scale: 1.8, weight: 700),
  heading2("Heading 2", scale: 1.4, weight: 700),
  bold("Bold", weight: 700),
  italic("Italic", slanted: true),
  underline("Underline", underlined: true),
  link("Link", color: Color(0xFF4C8DFF), underlined: true);

  final String label;

  /// scale, weight, slanted, underlined and color are each kind's default
  /// look, until a MarkdownLook overrides it.
  final double scale;
  final int? weight;

  /// slanted is italic, which a value of this enum is named.
  final bool slanted;
  final bool underlined;
  final Color? color;

  const MarkdownKind(this.label,
      {this.scale = 1,
      this.weight,
      this.slanted = false,
      this.underlined = false,
      this.color});
}

/// MarkdownLook is whether one kind of markdown is honoured and how drawn.
/// All but [on] are overrides; null falls back to the kind's default or the
/// element's type.
class MarkdownLook {
  final bool on;

  /// scale is size against the element's own, or null for the kind's.
  final double? scale;
  final Color? color;
  final int? weight;
  final bool? italic;
  final bool? underline;
  final String? family;

  const MarkdownLook({
    this.on = true,
    this.scale,
    this.color,
    this.weight,
    this.italic,
    this.underline,
    this.family,
  });

  /// partFor is this look as a TextPart over words [from]..[to].
  TextPart partFor(MarkdownKind kind, int from, int to) => TextPart(
        from: from,
        to: to,
        scale: (scale ?? kind.scale) == 1 ? null : (scale ?? kind.scale),
        color: color ?? kind.color,
        weight: weight ?? kind.weight,
        italic: (italic ?? kind.slanted) ? true : null,
        family: family,
        underline: (underline ?? kind.underlined)
            ? const PartUnderline(style: PartLineStyle.solid)
            : null,
      );

  MarkdownLook copyWith({
    bool? on,
    double? scale,
    bool clearScale = false,
    Color? color,
    bool clearColor = false,
    int? weight,
    bool clearWeight = false,
    bool? italic,
    bool? underline,
    String? family,
    bool clearFamily = false,
  }) =>
      MarkdownLook(
        on: on ?? this.on,
        scale: clearScale ? null : (scale ?? this.scale),
        color: clearColor ? null : (color ?? this.color),
        weight: clearWeight ? null : (weight ?? this.weight),
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        family: clearFamily ? null : (family ?? this.family),
      );

  /// mapColours maps the look's own colour (none is the kind's, and stays
  /// none), hidden while the look is off.
  MarkdownLook mapColours(ColourMap f) {
    var c = color;
    if (c == null) return this;
    var next = f(c, shown: on);
    return next == c ? this : copyWith(color: next);
  }

  Map<String, dynamic> toJson() => {
        if (!on) "off": true,
        if (scale != null) "scale": scale,
        if (color != null) "color": colorToJson(color!),
        if (weight != null) "weight": weight,
        if (italic != null) "italic": italic,
        if (underline != null) "underline": underline,
        if (family != null) "family": family,
      };

  factory MarkdownLook.fromJson(Map<String, dynamic> json) => MarkdownLook(
        on: !jsonBool(json["off"], false),
        scale: json["scale"] is num
            ? (json["scale"] as num).toDouble().clamp(0.05, 20.0)
            : null,
        color: json["color"] == null
            ? null
            : colorFromJson(json["color"], const Color(0xFFFFFFFF)),
        weight: json["weight"] is num ? (json["weight"] as num).toInt() : null,
        italic: json["italic"] is bool ? json["italic"] as bool : null,
        underline: json["underline"] is bool ? json["underline"] as bool : null,
        family: jsonStr(json["family"]),
      );
}

/// MarkdownAllow is which kinds of markdown a document-backed element
/// honours, each separately, and how each is drawn. Marks not allowed are
/// stripped, not shown as written.
class MarkdownAllow {
  final Map<MarkdownKind, MarkdownLook> looks;

  const MarkdownAllow({this.looks = const {}});

  /// lookFor is [kind]'s look, or the default until one is set.
  MarkdownLook lookFor(MarkdownKind kind) =>
      looks[kind] ?? const MarkdownLook();

  bool allows(MarkdownKind kind) => lookFor(kind).on;

  MarkdownAllow withLook(MarkdownKind kind, MarkdownLook look) =>
      MarkdownAllow(looks: {...looks, kind: look});

  MarkdownAllow mapColours(ColourMap f) {
    var next = mappedValues(looks, (_, l) => l.mapColours(f));
    return identical(next, looks) ? this : MarkdownAllow(looks: next);
  }

  Map<String, dynamic> toJson() {
    var out = <String, dynamic>{};
    for (var entry in looks.entries) {
      var json = entry.value.toJson();
      if (json.isNotEmpty) out[entry.key.name] = json;
    }
    return out;
  }

  factory MarkdownAllow.fromJson(Map<String, dynamic> json) {
    var looks = <MarkdownKind, MarkdownLook>{};
    for (var kind in MarkdownKind.values) {
      var mine = json[kind.name];
      if (mine is Map<String, dynamic>) {
        looks[kind] = MarkdownLook.fromJson(mine);
      }
    }
    return MarkdownAllow(looks: looks);
  }
}

/// TextDocumentRef is the Writing library document a text takes words from.
class TextDocumentRef {
  /// folder is "" for the top level; the library is one level deep.
  final String folder;
  final String name;

  /// markdown is whether formatting is honoured. Off, every mark is stripped
  /// and the element's own styling applies.
  final bool markdown;

  final MarkdownAllow allow;

  /// wasText is the element's words before the document, restored when the
  /// document is removed. Lives here as it exists only while a document does.
  final String wasText;

  const TextDocumentRef({
    this.folder = "",
    this.name = "",
    this.markdown = false,
    this.allow = const MarkdownAllow(),
    this.wasText = "",
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextDocumentRef();

  bool get on => name.isNotEmpty;

  /// says is the document's name, for a settings panel.
  String get says => folder.isEmpty ? name : "$folder / $name";

  TextDocumentRef copyWith({
    String? folder,
    String? name,
    bool? markdown,
    MarkdownAllow? allow,
    String? wasText,
  }) =>
      TextDocumentRef(
        folder: folder ?? this.folder,
        name: name ?? this.name,
        markdown: markdown ?? this.markdown,
        allow: allow ?? this.allow,
        wasText: wasText ?? this.wasText,
      );

  /// mapColours maps the Markdown looks, hidden unless the document is set
  /// and its formatting honoured (they are saved all the same).
  TextDocumentRef mapColours(ColourMap f) {
    var next = allow.mapColours(f.shownOnlyIf(on && markdown));
    return identical(next, allow) ? this : copyWith(allow: next);
  }

  Map<String, dynamic> toJson() => {
        if (folder.isNotEmpty) "folder": folder,
        "name": name,
        if (markdown) "markdown": true,
        if (allow.toJson().isNotEmpty) "allow": allow.toJson(),
        if (wasText.isNotEmpty) "wasText": wasText,
      };

  factory TextDocumentRef.fromJson(Map<String, dynamic> json) =>
      TextDocumentRef(
        folder: jsonString(json["folder"], _defaults.folder),
        name: jsonString(json["name"], _defaults.name),
        markdown: jsonBool(json["markdown"], false),
        allow: json["allow"] is Map<String, dynamic>
            ? MarkdownAllow.fromJson(json["allow"] as Map<String, dynamic>)
            : const MarkdownAllow(),
        wasText: jsonString(json["wasText"], _defaults.wasText),
      );
}

/// readDocument turns markdown into the words a text draws and the parts
/// that style them. A small subset: two heading levels, bold, italic,
/// underline and links. Quotes and lists keep their words; code fence lines
/// are dropped. [markdown] off strips every mark and returns no parts.
(String, List<TextPart>) readDocument(String raw,
    {bool markdown = false, MarkdownAllow allow = const MarkdownAllow()}) {
  var out = StringBuffer();
  var parts = <TextPart>[];

  // Parts are word ranges, so count the words written.
  var words = 0;
  var inWord = false;

  void write(String s) {
    for (var i = 0; i < s.length; i++) {
      var space = s[i].trim().isEmpty;
      if (!space && !inWord) words++;
      inWord = !space;
      out.write(s[i]);
    }
  }

  // styled writes text with a part covering its words.
  void styled(String text, TextPart Function(int from, int to) make) {
    var from = words + 1;
    write(text);
    if (words >= from) parts.add(make(from, words));
  }

  for (var line in raw.split("\n")) {
    if (out.isNotEmpty) {
      write("\n");
      inWord = false;
    }

    // Block marks, off the front of the line; a heading styles the line.
    var heading = 0;
    var text = line;
    if (text.startsWith("## ")) {
      heading = 2;
      text = text.substring(3);
    } else if (text.startsWith("# ")) {
      heading = 1;
      text = text.substring(2);
    } else if (text.startsWith(">")) {
      text = text.substring(1).trimLeft();
    } else if (RegExp(r"^\s*([-*+]|\d+\.)\s+").hasMatch(text)) {
      text = text.replaceFirst(RegExp(r"^\s*([-*+]|\d+\.)\s+"), "");
    } else if (text.trim().startsWith("```")) {
      continue;
    }

    var headingKind =
        heading == 1 ? MarkdownKind.heading1 : MarkdownKind.heading2;
    var wants = allow.allows(headingKind);
    var headingFrom = words + 1;

    // Inline marks in one pass, longest marker first, so "**" is not read
    // as two "*".
    var i = 0;
    var plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      write(plain.toString());
      plain.clear();
    }

    while (i < text.length) {
      var rest = text.substring(i);

      var link = RegExp(r"^\[([^\]]*)\]\(([^)]*)\)").firstMatch(rest);
      if (link != null) {
        flush();
        var shown = link.group(1) ?? "";
        if (markdown && allow.allows(MarkdownKind.link)) {
          styled(
              shown,
              (from, to) => allow
                  .lookFor(MarkdownKind.link)
                  .partFor(MarkdownKind.link, from, to));
        } else {
          write(shown);
        }
        i += link.group(0)!.length;
        continue;
      }

      (String, String)? paired(String mark) {
        if (!rest.startsWith(mark)) return null;
        var end = rest.indexOf(mark, mark.length);
        if (end < 0) return null;
        return (
          rest.substring(mark.length, end),
          rest.substring(0, end + mark.length)
        );
      }

      var bold = paired("**");
      if (bold != null) {
        flush();
        if (markdown && allow.allows(MarkdownKind.bold)) {
          styled(
              bold.$1,
              (from, to) => allow
                  .lookFor(MarkdownKind.bold)
                  .partFor(MarkdownKind.bold, from, to));
        } else {
          write(bold.$1);
        }
        i += bold.$2.length;
        continue;
      }

      var under = paired("__");
      if (under != null) {
        flush();
        if (markdown && allow.allows(MarkdownKind.underline)) {
          styled(
              under.$1,
              (from, to) => allow
                  .lookFor(MarkdownKind.underline)
                  .partFor(MarkdownKind.underline, from, to));
        } else {
          write(under.$1);
        }
        i += under.$2.length;
        continue;
      }

      var italic = paired("*") ?? paired("_");
      if (italic != null) {
        flush();
        if (markdown && allow.allows(MarkdownKind.italic)) {
          styled(
              italic.$1,
              (from, to) => allow
                  .lookFor(MarkdownKind.italic)
                  .partFor(MarkdownKind.italic, from, to));
        } else {
          write(italic.$1);
        }
        i += italic.$2.length;
        continue;
      }

      plain.write(text[i]);
      i++;
    }
    flush();

    if (heading > 0 && markdown && wants && words >= headingFrom) {
      parts.add(
          allow.lookFor(headingKind).partFor(headingKind, headingFrom, words));
    }
  }

  return (out.toString(), parts);
}
