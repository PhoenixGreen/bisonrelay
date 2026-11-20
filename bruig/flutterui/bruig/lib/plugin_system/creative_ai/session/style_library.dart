import 'dart:convert';
import 'dart:io';

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

/// StyleProfile is one style, as listed.
class StyleProfile {
  final String slug;
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

  const StyleProfile({
    required this.slug,
    required this.name,
    required this.description,
    required this.guide,
    required this.facts,
    required this.from,
    required this.saved,
    required this.folder,
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
  String get skillName => "bisonrelay-style-$slug";

  Map<String, Object?> brief() => {
        "style": slug,
        "name": name,
        "description": description,
        "colours": [
          for (var c in colours.take(6))
            "#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, "0").toUpperCase()}"
        ],
        "fonts": fonts,
        "saved": saved.toIso8601String(),
        if (from.isNotEmpty) "from": from,
      };
}

/// slugOf is [name] as a folder name: lower case, words joined by "-".
String slugOf(String name) {
  var s = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
      .replaceAll(RegExp(r"^-+|-+$"), "");
  if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r"-+$"), "");
  return s.isEmpty ? "style" : s;
}

/// skillMarkdown is SKILL.md for a style.
String skillMarkdown(
        {required String slug,
        required String name,
        required String description,
        required String guide}) =>
    """
---
name: bisonrelay-style-$slug
description: ${_oneLine("Bison Relay canvas style \"$name\"${description.isEmpty ? "" : ": $description"}. Use when making or restyling a Bison Relay canvas in this style (with the bisonrelay canvas tools).")}
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

  String? _active;

  /// active is the style the sidebar's conversation works in, if any.
  StyleProfile? get active =>
      _styles.where((s) => s.slug == _active).firstOrNull;

  set active(StyleProfile? style) {
    _active = style?.slug;
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
        name: "${data["name"] ?? path.basename(folder)}",
        description: "${data["description"] ?? ""}",
        guide: guideOf(await skill.readAsString()),
        facts: data["facts"] is Map
            ? Map<String, dynamic>.from(data["facts"] as Map)
            : const {},
        from: "${data["from"] ?? ""}",
        saved: DateTime.tryParse("${data["saved"]}") ?? DateTime(2000),
        folder: folder,
      );
    } catch (_) {
      return null;
    }
  }

  /// byName finds a style by its slug or its name.
  Future<StyleProfile?> byName(String name) async {
    if (!_loaded) await refresh();
    var slug = slugOf(name);
    return _styles.where((s) => s.slug == name || s.slug == slug).firstOrNull ??
        _styles
            .where((s) => s.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
  }

  /// save keeps a style called [name], replacing one of the same name.
  Future<StyleProfile> save({
    required String name,
    required String description,
    required String guide,
    required Map<String, Object?> facts,
    String from = "",
    Uint8List? preview,
  }) async {
    var slug = slugOf(name);
    var folder = path.join((await _dir()).path, slug);
    await Directory(folder).create(recursive: true);
    var saved = DateTime.now();
    await File(path.join(folder, "SKILL.md")).writeAsString(skillMarkdown(
        slug: slug, name: name, description: description, guide: guide));
    await File(path.join(folder, "style.json"))
        .writeAsString(const JsonEncoder.withIndent(" ").convert({
      "name": name,
      "description": description,
      "saved": saved.toIso8601String(),
      "from": from,
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
        slug: style.slug, name: style.name, description: desc, guide: guide));
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
    if (_active == style.slug) _active = null;
    await refresh();
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
