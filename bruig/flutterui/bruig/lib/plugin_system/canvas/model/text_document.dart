import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';

// text_document.dart is a text element whose words come from the Writing
// library rather than from the canvas.
//
// The words are *copied* into the element rather than read at drawing time.
// That is the whole design: a canvas has to draw the same on a machine that
// has never seen the library, an export runs with no file system to consult,
// and a painter cannot wait for a disk. So the document is read when the
// canvas is open and the text it produced is saved with the element -- and
// the reference is kept beside it so it can be read again when it changes.

/// MarkdownKind is a piece of markdown a document-backed element honours.
enum MarkdownKind {
  heading1("Heading 1", scale: 1.8, weight: 700),
  heading2("Heading 2", scale: 1.4, weight: 700),
  bold("Bold", weight: 700),
  italic("Italic", slanted: true),
  underline("Underline", underlined: true),
  link("Link", color: Color(0xFF4C8DFF), underlined: true);

  final String label;

  /// The look each one has until it is given another: a heading is bigger and
  /// heavier, a link is blue and underlined. Chosen to be what somebody would
  /// have set by hand, so the switch on its own is already useful.
  final double scale;
  final int? weight;

  /// slanted rather than italic, because a value of this enum is called
  /// italic and the two cannot share a name.
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

/// MarkdownLook is how one piece of markdown is drawn.
///
/// Its own type rather than a switch, because "honour the headings" is only
/// half the question: a poster's heading is a different size, weight, face
/// and colour from a report's, and the alternative to saying so here is a
/// document whose headings can only ever look like the one thing this code
/// happened to choose.
///
/// Everything but [on] is an override: null means the element's own, so a
/// look that has been switched on and left alone follows the type settings
/// and picks up a change to them.
class MarkdownLook {
  final bool on;

  /// scale is the size against the element's own, or null for the kind's own
  /// idea of it -- 1.8 for a first-level heading, 1 for bold.
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

  /// partFor is this look as a run of styled words -- see TextPart, which is
  /// the one way anything in a text element says "these words, not those".
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
        family: json["family"] is String ? json["family"] as String : null,
      );
}

/// MarkdownAllow is which pieces of markdown a document-backed element
/// honours, and how each of them is drawn.
///
/// Each on its own, because the answer really is per piece: a poster wants
/// the bold and none of the headings, and a report wants the headings and
/// none of the links. Everything not allowed is *stripped* rather than left
/// as written -- a headline reading "## Title" is not markdown being ignored,
/// it is markdown showing.
class MarkdownAllow {
  final Map<MarkdownKind, MarkdownLook> looks;

  const MarkdownAllow({this.looks = const {}});

  /// lookFor is how [kind] is drawn, which is its own default until something
  /// has been said about it.
  MarkdownLook lookFor(MarkdownKind kind) =>
      looks[kind] ?? const MarkdownLook();

  bool allows(MarkdownKind kind) => lookFor(kind).on;

  MarkdownAllow withLook(MarkdownKind kind, MarkdownLook look) =>
      MarkdownAllow(looks: {...looks, kind: look});

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
    // Read what the switches used to be, so a canvas saved when this was six
    // booleans opens with those switches where they were left.
    const was = {
      "h1": MarkdownKind.heading1,
      "h2": MarkdownKind.heading2,
      "b": MarkdownKind.bold,
      "i": MarkdownKind.italic,
      "u": MarkdownKind.underline,
      "a": MarkdownKind.link,
    };
    for (var entry in was.entries) {
      if (json[entry.key] == false) {
        looks[entry.value] = const MarkdownLook(on: false);
      }
    }
    return MarkdownAllow(looks: looks);
  }
}

/// TextDocumentRef says which document in the Writing library a text element
/// takes its words from.
class TextDocumentRef {
  /// folder is "" for the top level. The library is one level deep.
  final String folder;
  final String name;

  /// markdown is whether the document's formatting is honoured at all. Off,
  /// the words arrive as plain text and every mark is stripped -- which is
  /// what a poster wants: all of the styling comes from the element.
  final bool markdown;

  final MarkdownAllow allow;

  /// wasText is what the element said before the document took the words
  /// over, and what it says again when the document is taken away.
  ///
  /// Kept here rather than on the element because it exists only while a
  /// document does: it is part of what "reading a document" means, and it
  /// goes when the reference goes. Without it, turning the switch off left
  /// somebody's headline reading a paragraph of their own document with no
  /// way back to what they had typed.
  final String wasText;

  const TextDocumentRef({
    this.folder = "",
    this.name = "",
    this.markdown = false,
    this.allow = const MarkdownAllow(),
    this.wasText = "",
  });

  bool get on => name.isNotEmpty;

  /// says is the document in words, for a settings panel to show.
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

  Map<String, dynamic> toJson() => {
        if (folder.isNotEmpty) "folder": folder,
        "name": name,
        if (markdown) "markdown": true,
        if (allow.toJson().isNotEmpty) "allow": allow.toJson(),
        if (wasText.isNotEmpty) "wasText": wasText,
      };

  factory TextDocumentRef.fromJson(Map<String, dynamic> json) =>
      TextDocumentRef(
        folder: jsonString(json["folder"], ""),
        name: jsonString(json["name"], ""),
        markdown: jsonBool(json["markdown"], false),
        allow: json["allow"] is Map<String, dynamic>
            ? MarkdownAllow.fromJson(json["allow"] as Map<String, dynamic>)
            : const MarkdownAllow(),
        wasText: jsonString(json["wasText"], ""),
      );
}

/// readDocument turns a markdown file into the words a text element draws and
/// the parts that style them.
///
/// A deliberately small subset -- two heading levels, bold, italic, underline
/// and links -- because a canvas is not a document viewer. Everything else is
/// stripped: block quotes, code fences, images and lists lose their marks and
/// keep their words, so what lands in a headline is the headline.
///
/// [markdown] off strips every mark and returns no parts at all, which is the
/// plain-text case and the default. See MarkdownAllow.
(String, List<TextPart>) readDocument(String raw,
    {bool markdown = false, MarkdownAllow allow = const MarkdownAllow()}) {
  var out = StringBuffer();
  var parts = <TextPart>[];

  /// words counts what has been written so far, because a part is a range of
  /// *words* -- see TextPart -- and the reader is walking characters.
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

  /// styled writes [text] and records a part covering the words it added.
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

    // The block marks, taken off the front of the line. A heading is a part
    // covering the whole line, so it is bigger and heavier than what is
    // around it; a quote or a list keeps its words and loses its mark.
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
      // A fence is not words at all.
      continue;
    }

    var headingKind =
        heading == 1 ? MarkdownKind.heading1 : MarkdownKind.heading2;
    var wants = allow.allows(headingKind);
    var headingFrom = words + 1;

    // The inline marks. One pass over the line, longest marker first, so
    // "**" is not read as two "*".
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
