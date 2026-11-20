import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

// drawn_characters.dart puts characters together from a drawn style's parts:
// a head, a face, hair, clothes, glasses, each a piece of SVG with places
// for its colours and for the parts inside it. The styles are CC0 drawings
// by Pablo Stanley (Open Peeps), Zoish (Notionists), Lisa Wischofsky
// (Lorelei) and DiceBear (Pixel Art) -- see assets/canvas/characters/
// SOURCES.md -- and a character is made here, never fetched.

class DrawnStyle {
  final String id;
  final String title;
  final String creator;
  final String source;
  final String licence;
  final String licenceUrl;
  final String viewBox;
  final String shapeRendering;
  final String body;

  /// parts are each group's variants: group, variant, SVG.
  final Map<String, Map<String, String>> parts;

  /// defaults are the style's own: each group's choices, each colour's
  /// (the colour's name and "Color"), and how often an optional group
  /// shows (the group's name and "Probability", a percentage).
  final Map<String, Object?> defaults;

  const DrawnStyle({
    required this.id,
    required this.title,
    required this.creator,
    required this.source,
    required this.licence,
    required this.licenceUrl,
    required this.viewBox,
    required this.shapeRendering,
    required this.body,
    required this.parts,
    required this.defaults,
  });

  static DrawnStyle? fromJson(String id, Object? json) {
    if (json is! Map) return null;
    var parts = <String, Map<String, String>>{};
    if (json["parts"] case Map raw) {
      for (var g in raw.entries) {
        if (g.value is! Map) continue;
        parts["${g.key}"] = {
          for (var v in (g.value as Map).entries)
            if (v.value is String) "${v.key}": v.value as String
        };
      }
    }
    String s(Object? v) => v is String ? v : "";
    var licence = json["license"] is Map ? json["license"] as Map : const {};
    return DrawnStyle(
      id: id,
      title: s(json["title"]),
      creator: s(json["creator"]),
      source: s(json["source"]),
      licence: s(licence["name"]),
      licenceUrl: s(licence["url"]),
      viewBox: s(json["viewBox"]),
      shapeRendering: s(json["shapeRendering"]),
      body: s(json["body"]),
      parts: parts,
      defaults: json["defaults"] is Map
          ? Map<String, Object?>.from(json["defaults"] as Map)
          : const {},
    );
  }

  /// groups are the parts a character of this style is made of, in the
  /// order the style draws them.
  List<String> get groups {
    var all = "$body ${parts.values.expand((v) => v.values).join(" ")}";
    var seen = <String>[];
    for (var m in RegExp(r"\{\{p:(\w+)\}\}").allMatches(all)) {
      var g = m.group(1)!;
      if (!seen.contains(g) && (parts[g]?.isNotEmpty ?? false)) seen.add(g);
    }
    return seen;
  }

  /// colours are the colours a character of this style is painted in.
  List<String> get colours {
    var all = "$body ${parts.values.expand((v) => v.values).join(" ")}";
    return {
      for (var m in RegExp(r"\{\{c:(\w+)\}\}").allMatches(all)) m.group(1)!
    }.toList();
  }

  /// choices are [group]'s variants: the style's own list, in its order.
  List<String> choices(String group) {
    var listed = defaults[group];
    var have = parts[group] ?? const {};
    if (listed is List) {
      var picked = [
        for (var v in listed)
          if (have.containsKey("$v")) "$v"
      ];
      if (picked.isNotEmpty) return picked;
    }
    return have.keys.toList();
  }

  /// palette is [colour]'s choices, as six-digit hex or "transparent".
  List<String> palette(String colour) {
    var listed = defaults["${colour}Color"];
    return listed is List ? [for (var c in listed) "$c"] : const [];
  }

  /// chance is how often [group] shows, 0 to 1: always unless the style
  /// says otherwise.
  double chance(String group) {
    var p = defaults["${group}Probability"];
    return p is num ? (p / 100).clamp(0.0, 1.0).toDouble() : 1;
  }

  /// optional is whether a character may go without [group].
  bool optional(String group) => defaults.containsKey("${group}Probability");
}

/// DrawnCharacter is one character: which variant of each part (null for
/// none), and each colour.
class DrawnCharacter {
  final String style;
  final Map<String, String?> parts;
  final Map<String, String> colours;

  const DrawnCharacter(this.style,
      {this.parts = const {}, this.colours = const {}});

  DrawnCharacter withPart(String group, String? variant) =>
      DrawnCharacter(style,
          parts: {...parts, group: variant}, colours: colours);

  DrawnCharacter withColour(String name, String hex) =>
      DrawnCharacter(style, parts: parts, colours: {...colours, name: hex});

  Map<String, dynamic> toJson() =>
      {"style": style, "parts": parts, "colours": colours};

  static DrawnCharacter fromJson(Map<String, dynamic> json) => DrawnCharacter(
        "${json["style"] ?? ""}",
        parts: {
          if (json["parts"] case Map p)
            for (var e in p.entries)
              "${e.key}": e.value is String ? e.value as String : null
        },
        colours: {
          if (json["colours"] case Map c)
            for (var e in c.entries)
              if (e.value is String) "${e.key}": e.value as String
        },
      );
}

/// randomCharacter is a character of [style] as the style itself would
/// make one: each part picked from its choices (an optional part as often
/// as the style shows it), each colour from its palette.
DrawnCharacter randomCharacter(DrawnStyle style, math.Random random) {
  var parts = <String, String?>{};
  for (var g in style.groups) {
    var choices = style.choices(g);
    parts[g] = choices.isEmpty || random.nextDouble() >= style.chance(g)
        ? null
        : choices[random.nextInt(choices.length)];
  }
  var colours = <String, String>{};
  for (var c in style.colours) {
    var palette = style.palette(c);
    if (palette.isNotEmpty) {
      colours[c] = palette[random.nextInt(palette.length)];
    }
  }
  return DrawnCharacter(style.id, parts: parts, colours: colours);
}

/// _hex is a colour as SVG has it: "#rrggbb", or "none" for transparent
/// and anything that is not a colour.
String _hex(String? c) {
  if (c == null || !RegExp(r"^[0-9a-fA-F]{6}$").hasMatch(c)) return "none";
  return "#${c.toLowerCase()}";
}

/// drawnSvg is [character], drawn in [style], as an SVG file.
String drawnSvg(DrawnStyle style, DrawnCharacter character) {
  String fill(String template, int depth) => template
          .replaceAllMapped(RegExp(r"\{\{c:(\w+)\}\}"),
              (m) => _hex(character.colours[m.group(1)]))
          .replaceAllMapped(RegExp(r"\{\{p:(\w+)\}\}"), (m) {
        var variant = character.parts[m.group(1)];
        var part = variant == null ? null : style.parts[m.group(1)]?[variant];
        // Parts hold parts (a head its face), never more than a few deep.
        return part == null || depth > 4 ? "" : fill(part, depth + 1);
      });
  var rendering = RegExp(r"^[\w-]+$").hasMatch(style.shapeRendering)
      ? style.shapeRendering
      : "auto";
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${style.viewBox}" '
      'fill="none" shape-rendering="$rendering">${fill(style.body, 0)}</svg>';
}

/// readDrawnStyles is the styles in a bundle as the app keeps them.
Map<String, DrawnStyle> readDrawnStyles(Uint8List gzipped) {
  var json = jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(gzipped)));
  return {
    if (json is Map)
      for (var e in json.entries)
        if (DrawnStyle.fromJson("${e.key}", e.value) case var s?) "${e.key}": s
  };
}
