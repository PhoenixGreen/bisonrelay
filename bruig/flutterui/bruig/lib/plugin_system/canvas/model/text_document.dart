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

/// MarkdownAllow is which pieces of markdown a document-backed element
/// honours.
///
/// Each on its own, because the answer really is per piece: a poster wants
/// the bold and none of the headings, and a report wants the headings and
/// none of the links. Everything not allowed is *stripped* rather than left
/// as written -- a headline reading "## Title" is not markdown being ignored,
/// it is markdown showing.
class MarkdownAllow {
  final bool heading1;
  final bool heading2;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool link;

  const MarkdownAllow({
    this.heading1 = true,
    this.heading2 = true,
    this.bold = true,
    this.italic = true,
    this.underline = true,
    this.link = true,
  });

  MarkdownAllow copyWith({
    bool? heading1,
    bool? heading2,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? link,
  }) =>
      MarkdownAllow(
        heading1: heading1 ?? this.heading1,
        heading2: heading2 ?? this.heading2,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        link: link ?? this.link,
      );

  Map<String, dynamic> toJson() => {
        if (!heading1) "h1": false,
        if (!heading2) "h2": false,
        if (!bold) "b": false,
        if (!italic) "i": false,
        if (!underline) "u": false,
        if (!link) "a": false,
      };

  factory MarkdownAllow.fromJson(Map<String, dynamic> json) => MarkdownAllow(
        heading1: jsonBool(json["h1"], true),
        heading2: jsonBool(json["h2"], true),
        bold: jsonBool(json["b"], true),
        italic: jsonBool(json["i"], true),
        underline: jsonBool(json["u"], true),
        link: jsonBool(json["a"], true),
      );
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

  const TextDocumentRef({
    this.folder = "",
    this.name = "",
    this.markdown = false,
    this.allow = const MarkdownAllow(),
  });

  bool get on => name.isNotEmpty;

  /// says is the document in words, for a settings panel to show.
  String get says => folder.isEmpty ? name : "$folder / $name";

  TextDocumentRef copyWith({
    String? folder,
    String? name,
    bool? markdown,
    MarkdownAllow? allow,
  }) =>
      TextDocumentRef(
        folder: folder ?? this.folder,
        name: name ?? this.name,
        markdown: markdown ?? this.markdown,
        allow: allow ?? this.allow,
      );

  Map<String, dynamic> toJson() => {
        if (folder.isNotEmpty) "folder": folder,
        "name": name,
        if (markdown) "markdown": true,
        if (allow.toJson().isNotEmpty) "allow": allow.toJson(),
      };

  factory TextDocumentRef.fromJson(Map<String, dynamic> json) =>
      TextDocumentRef(
        folder: jsonString(json["folder"], ""),
        name: jsonString(json["name"], ""),
        markdown: jsonBool(json["markdown"], false),
        allow: json["allow"] is Map<String, dynamic>
            ? MarkdownAllow.fromJson(json["allow"] as Map<String, dynamic>)
            : const MarkdownAllow(),
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

    var wants = heading == 1 ? allow.heading1 : allow.heading2;
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
        if (markdown && allow.link) {
          styled(
              shown,
              (from, to) => TextPart(
                  from: from,
                  to: to,
                  color: const Color(0xFF4C8DFF),
                  underline: const PartUnderline(style: PartLineStyle.solid)));
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
        if (markdown && allow.bold) {
          styled(
              bold.$1, (from, to) => TextPart(from: from, to: to, weight: 700));
        } else {
          write(bold.$1);
        }
        i += bold.$2.length;
        continue;
      }

      var under = paired("__");
      if (under != null) {
        flush();
        if (markdown && allow.underline) {
          styled(
              under.$1,
              (from, to) => TextPart(
                  from: from, to: to, underline: const PartUnderline()));
        } else {
          write(under.$1);
        }
        i += under.$2.length;
        continue;
      }

      var italic = paired("*") ?? paired("_");
      if (italic != null) {
        flush();
        if (markdown && allow.italic) {
          styled(italic.$1,
              (from, to) => TextPart(from: from, to: to, italic: true));
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
      parts.add(TextPart(
        from: headingFrom,
        to: words,
        weight: 700,
        scale: heading == 1 ? 1.6 : 1.3,
      ));
    }
  }

  return (out.toString(), parts);
}
