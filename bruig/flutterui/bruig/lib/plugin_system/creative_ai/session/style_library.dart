import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// style_library.dart is the style profiles kept on this computer: each a
// folder holding a written guide, the facts measured from the canvas it came
// from (palette, type, motion, samples) and a picture of it.
//
// The folder is laid out as a Claude skill (a SKILL.md with a name and a
// description, and the files it refers to), on purpose. Claude reads a
// style's guide here through canvas_style_get; the same folder copied into
// Claude Code's skills folder lets Claude Code use the style on its own,
// with no change. A style is a set of rules to make new work from -- unlike
// a canvas preset, which is a copy of finished work.
//
//   <canvas library>/.presets/styles/<slug>/
//     SKILL.md      the guide, with front matter (name, description)
//     style.json    the facts and samples (styleFactsOf), and its name
//     preview.png   the canvas it came from, small

/// StyleKind is what a style is for: a canvas's look, or a writer's voice.
enum StyleKind {
  canvas(
      "Bison Relay canvas",
      "making or restyling a Bison Relay canvas in "
          "this style (with the bisonrelay canvas tools)"),
  writing(
      "Bison Relay writing",
      "writing or rewriting a Bison Relay "
          "document in this voice (with the bisonrelay writing tools)");

  final String what;
  final String when;
  const StyleKind(this.what, this.when);

  static StyleKind fromName(Object? name) =>
      values.where((k) => k.name == name).firstOrNull ?? canvas;
}

/// StyleProfile is one style, as listed.
class StyleProfile {
  final String slug;
  final StyleKind kind;
  final String name;
  final String description;

  /// guide is SKILL.md's body: the rules, in words.
  final String guide;

  /// facts are what was measured (see styleFactsOf).
  final Map<String, dynamic> facts;

  /// from is the canvas it was saved from, if known.
  final String from;
  final DateTime saved;
  final String folder;

  /// receivedFrom is who sent it, for a style imported from someone else:
  /// its guide is theirs, and is read as a description, never as orders.
  final String receivedFrom;

  const StyleProfile({
    required this.slug,
    this.kind = StyleKind.canvas,
    required this.name,
    required this.description,
    required this.guide,
    required this.facts,
    required this.from,
    required this.saved,
    required this.folder,
    this.receivedFrom = "",
  });

  String get previewPath => path.join(folder, "preview.png");

  /// colours are its palette's colours, most used first.
  List<int> get colours => [
        if (facts["palette"] case List p)
          for (var c in p)
            if (c is Map && c["argb"] is int) c["argb"] as int
      ];

  /// fonts are the fonts its type uses, largest first.
  List<String> get fonts => [
        ...{
          if (facts["type"] case List t)
            for (var x in t)
              if (x is Map && x["font"] is String) x["font"] as String
        }
      ];

  /// skillName is the name it goes by as a Claude skill.
  String get skillName => skillNameOf(kind, slug);

  /// summary is a line of what was measured from a writing style's text.
  String get summary {
    if (kind != StyleKind.writing) return "";
    var f = facts;
    return [
      if (f["sentenceWords"] case num n) "${n.round()} words a sentence",
      if (f["spelling"] case String s when s != "unclear") s,
      if (f["contractions"] case String c) "contractions $c",
      if (f["readingEase"] case String r) r.toLowerCase(),
    ].join(" · ");
  }

  Map<String, Object?> brief() => {
        "style": slug,
        "kind": kind.name,
        "name": name,
        "description": description,
        if (kind == StyleKind.writing) "measured": summary,
        if (kind == StyleKind.canvas) ...{
          "colours": [
            for (var c in colours.take(6))
              "#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, "0").toUpperCase()}"
          ],
          "fonts": fonts,
        },
        "saved": saved.toIso8601String(),
        if (from.isNotEmpty) "from": from,
        if (receivedFrom.isNotEmpty) "receivedFrom": receivedFrom,
      };
}

/// ReceivedStyle is a style file's contents, checked but not yet kept.
class ReceivedStyle {
  final StyleKind kind;
  final String name;
  final String description;
  final String guide;
  final Map<String, Object?> facts;
  final String from;
  final Uint8List? preview;
  const ReceivedStyle({
    required this.kind,
    required this.name,
    required this.description,
    required this.guide,
    required this.facts,
    required this.from,
    this.preview,
  });
}

/// styleFiles are what a style's folder holds, and all a style file may.
const styleFiles = ["SKILL.md", "style.json", "preview.png"];

/// maxStyleFileBytes bounds a style file and each part of it.
const int maxStyleFileBytes = 4 << 20;

/// maxGuideChars bounds a received guide: it is read into every request.
const int maxGuideChars = 40000;

/// styleFileExtension names a style sent as a file.
const String styleFileExtension = ".brstyle";

/// slugOf is [name] as a folder name: lower case, words joined by "-".
String slugOf(String name) {
  var s = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
      .replaceAll(RegExp(r"^-+|-+$"), "");
  if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r"-+$"), "");
  return s.isEmpty ? "style" : s;
}

/// skillNameOf is a style's name as a Claude skill.
String skillNameOf(StyleKind kind, String slug) => kind == StyleKind.writing
    ? "bisonrelay-writing-style-${slug.replaceFirst("writing-", "")}"
    : "bisonrelay-style-$slug";

/// skillMarkdown is SKILL.md for a style.
String skillMarkdown(
        {required String slug,
        required String name,
        required String description,
        required String guide,
        StyleKind kind = StyleKind.canvas}) =>
    """
---
name: ${skillNameOf(kind, slug)}
description: ${_oneLine("${kind.what} style \"$name\"${description.isEmpty ? "" : ": $description"}. Use when ${kind.when}.")}
---

${guide.trim()}
""";

String _oneLine(String s) => s.replaceAll(RegExp(r"\s+"), " ").trim();

/// guideOf is SKILL.md's body, without its front matter.
String guideOf(String markdown) {
  var m = RegExp(r"^---\n[\s\S]*?\n---\n?").firstMatch(markdown);
  return (m == null ? markdown : markdown.substring(m.end)).trim();
}

class StyleLibrary extends ChangeNotifier {
  /// root is the presets folder the styles folder sits in.
  final Future<String> Function() root;
  StyleLibrary(this.root);

  List<StyleProfile> _styles = const [];
  bool _loaded = false;
  bool _disposed = false;

  /// styles are those on disk, newest first, as last read.
  List<StyleProfile> get styles => _styles;
  bool get loaded => _loaded;

  final Map<StyleKind, String> _active = {};

  /// of are the styles of [kind].
  List<StyleProfile> of(StyleKind kind) => [
        for (var s in _styles)
          if (s.kind == kind) s
      ];

  /// activeOf is the style [kind]'s work is done in, if any.
  StyleProfile? activeOf(StyleKind kind) => _styles
      .where((s) => s.kind == kind && s.slug == _active[kind])
      .firstOrNull;

  /// use makes [style] the one [kind]'s work is done in; null stops.
  void use(StyleKind kind, StyleProfile? style) {
    if (style == null) {
      _active.remove(kind);
    } else {
      _active[kind] = style.slug;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _dir() async {
    var dir = Directory(path.join(await root(), "styles"));
    await dir.create(recursive: true);
    return dir;
  }

  String? _error;

  /// error is why the styles could not be read, the last time they were not.
  String? get error => _error;

  /// refresh reads the styles from disk.
  Future<List<StyleProfile>> refresh() async {
    var out = <StyleProfile>[];
    try {
      var dir = await _dir();
      await for (var e in dir.list()) {
        if (e is! Directory) continue;
        var style = await _read(e.path);
        if (style != null) out.add(style);
      }
      _error = null;
    } catch (e) {
      _error = "$e";
    }
    out.sort((a, b) => b.saved.compareTo(a.saved));
    _styles = out;
    _loaded = true;
    _notify();
    return out;
  }

  Future<StyleProfile?> _read(String folder) async {
    try {
      var skill = File(path.join(folder, "SKILL.md"));
      var json = File(path.join(folder, "style.json"));
      if (!await skill.exists() || !await json.exists()) return null;
      var data = jsonDecode(await json.readAsString());
      if (data is! Map) return null;
      return StyleProfile(
        slug: path.basename(folder),
        kind: StyleKind.fromName(data["kind"]),
        name: "${data["name"] ?? path.basename(folder)}",
        description: "${data["description"] ?? ""}",
        guide: guideOf(await skill.readAsString()),
        facts: data["facts"] is Map
            ? Map<String, dynamic>.from(data["facts"] as Map)
            : const {},
        from: "${data["from"] ?? ""}",
        receivedFrom: "${data["receivedFrom"] ?? ""}",
        saved: DateTime.tryParse("${data["saved"]}") ?? DateTime(2000),
        folder: folder,
      );
    } catch (_) {
      return null;
    }
  }

  /// byName finds a style of [kind] by its slug or its name.
  Future<StyleProfile?> byName(String name,
      {StyleKind kind = StyleKind.canvas}) async {
    if (!_loaded) await refresh();
    var slug = slugOf(name);
    var mine = of(kind);
    return mine
            .where((s) =>
                s.slug == name || s.slug == slug || s.slug == "writing-$slug")
            .firstOrNull ??
        mine
            .where((s) => s.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
  }

  /// save keeps a style called [name], replacing one of the same name.
  Future<StyleProfile> save({
    required String name,
    required String description,
    required String guide,
    required Map<String, Object?> facts,
    StyleKind kind = StyleKind.canvas,
    String from = "",
    Uint8List? preview,
    String receivedFrom = "",
  }) async {
    // A writing style's folder is told from a canvas style's of a name.
    var slug =
        kind == StyleKind.writing ? "writing-${slugOf(name)}" : slugOf(name);
    var folder = path.join((await _dir()).path, slug);
    await Directory(folder).create(recursive: true);
    var saved = DateTime.now();
    await File(path.join(folder, "SKILL.md")).writeAsString(skillMarkdown(
        slug: slug,
        name: name,
        description: description,
        guide: guide,
        kind: kind));
    await File(path.join(folder, "style.json"))
        .writeAsString(const JsonEncoder.withIndent(" ").convert({
      "kind": kind.name,
      "name": name,
      "description": description,
      "saved": saved.toIso8601String(),
      "from": from,
      if (receivedFrom.isNotEmpty) "receivedFrom": receivedFrom,
      "facts": facts,
    }));
    if (preview != null) {
      await File(path.join(folder, "preview.png")).writeAsBytes(preview);
    }
    await refresh();
    return _styles.firstWhere((s) => s.slug == slug);
  }

  /// updateGuide replaces a style's written guide (and its description).
  Future<void> updateGuide(StyleProfile style,
      {required String guide, String? description}) async {
    var desc = description ?? style.description;
    await File(path.join(style.folder, "SKILL.md")).writeAsString(skillMarkdown(
        slug: style.slug,
        name: style.name,
        description: desc,
        guide: guide,
        kind: style.kind));
    if (description != null) {
      var file = File(path.join(style.folder, "style.json"));
      var data = jsonDecode(await file.readAsString()) as Map;
      data["description"] = description;
      await file.writeAsString(const JsonEncoder.withIndent(" ").convert(data));
    }
    await refresh();
  }

  Future<void> delete(StyleProfile style) async {
    await Directory(style.folder).delete(recursive: true);
    if (_active[style.kind] == style.slug) _active.remove(style.kind);
    await refresh();
  }

  /// pack is [style] as one file to send (a zip of its folder), for
  /// [unpack] at the other end.
  Future<Uint8List> pack(StyleProfile style) async {
    var archive = Archive();
    for (var name in styleFiles) {
      var f = File(path.join(style.folder, name));
      if (!await f.exists()) continue;
      var bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// read checks a style file sent by someone else, without keeping it:
  /// what it holds, or why it is refused. The file is a stranger's, so it
  /// is held to limits: a zip of at most the three files a style has, each
  /// bounded, the guide plain text, the facts a JSON object, the picture a
  /// PNG.
  static (ReceivedStyle?, String?) read(Uint8List bytes) {
    if (bytes.length > maxStyleFileBytes) {
      return (null, "That is too large to be a style.");
    }
    // A zip starts "PK\x03\x04"; anything else is not one.
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 3 ||
        bytes[3] != 4) {
      return (null, "That is not a style file.");
    }
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return (null, "That is not a style file.");
    }
    var files = <String, Uint8List>{};
    for (var f in archive.files) {
      if (!f.isFile) continue;
      if (!styleFiles.contains(f.name)) {
        return (null, "That style file holds something a style does not.");
      }
      var content = f.readBytes();
      if (content == null || content.length > maxStyleFileBytes) {
        return (null, "A part of that style is too large.");
      }
      files[f.name] = content;
    }
    var skill = files["SKILL.md"], json = files["style.json"];
    if (skill == null || json == null) {
      return (null, "That style file is missing its guide or its facts.");
    }
    Map<String, dynamic> data;
    String guide;
    try {
      var decoded = jsonDecode(utf8.decode(json));
      if (decoded is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(decoded);
      guide = guideOf(utf8.decode(skill));
    } catch (_) {
      return (null, "That style file could not be read.");
    }
    if (guide.length > maxGuideChars) guide = guide.substring(0, maxGuideChars);
    // A picture only if it starts as a PNG does.
    var preview = files["preview.png"];
    if (preview != null &&
        (preview.length < 8 ||
            preview[0] != 0x89 ||
            preview[1] != 0x50 ||
            preview[2] != 0x4E ||
            preview[3] != 0x47)) {
      preview = null;
    }
    var kind = StyleKind.fromName(data["kind"]);
    var name = _oneLine("${data["name"] ?? "Style"}");
    if (name.isEmpty) name = "Style";
    if (name.length > 80) name = name.substring(0, 80);
    return (
      ReceivedStyle(
        kind: kind,
        name: name,
        description: _oneLine("${data["description"] ?? ""}"),
        guide: guide,
        facts: data["facts"] is Map
            ? Map<String, Object?>.from(data["facts"] as Map)
            : <String, Object?>{},
        from: "${data["from"] ?? ""}",
        preview: preview,
      ),
      null
    );
  }

  /// keep saves [style], received from [from]. A style of the same name is
  /// not replaced: the new one is numbered.
  Future<StyleProfile> keep(ReceivedStyle style, {String from = ""}) async {
    if (!_loaded) await refresh();
    var name = style.name;
    for (var n = 2; of(style.kind).any((s) => s.name == name); n++) {
      name = "${style.name} $n";
    }
    return save(
      kind: style.kind,
      name: name,
      description: style.description,
      guide: style.guide,
      facts: style.facts,
      from: style.from,
      preview: style.preview,
      receivedFrom: from.isEmpty ? "someone else" : from,
    );
  }

  /// unpack is [read] then [keep]: the style, or why not.
  Future<(StyleProfile?, String?)> unpack(Uint8List bytes,
      {String from = ""}) async {
    var (received, problem) = read(bytes);
    if (received == null) return (null, problem);
    return (await keep(received, from: from), null);
  }

  /// copyToSkills puts [style] in Claude Code's skills folder ([skillsDir],
  /// ~/.claude/skills by default), so Claude Code can use it anywhere.
  /// Returns the folder it went to.
  Future<String> copyToSkills(StyleProfile style, {String? skillsDir}) async {
    var home = Platform.environment["HOME"] ??
        Platform.environment["USERPROFILE"] ??
        "";
    var into = path.join(
        skillsDir ?? path.join(home, ".claude", "skills"), style.skillName);
    await Directory(into).create(recursive: true);
    for (var name in ["SKILL.md", "style.json", "preview.png"]) {
      var f = File(path.join(style.folder, name));
      if (await f.exists()) await f.copy(path.join(into, name));
    }
    return into;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
