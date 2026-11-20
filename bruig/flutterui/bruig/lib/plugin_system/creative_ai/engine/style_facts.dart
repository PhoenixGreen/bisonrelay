// style_facts.dart reads a canvas's style out of its saved JSON: the colours
// it uses and how often, its type (font, size, weight, colour) ranked from
// headline down, its backgrounds and text styles, how things arrive and how
// long scenes run, its master mix and voices, and a few elements as samples.
//
// These are the facts a style profile keeps beside its written guide. They
// are measured, not judged: the guide (written by Claude, or by the person)
// says what they mean -- which colour is the accent, what the headline is
// for. Pure Dart over the JSON, so it reads any canvas, one from somebody
// else included, the same way.

/// _colourKeys are keys whose integer values are colours (0xAARRGGBB), in
/// the saved format's own spelling.
const _colourKeys = {
  "color", "colour", "fill", "bc", "accent", "iconColor", "bg", "fg",
  "stroke", "ruleColor", "c", "to", "from", "shadow", "glow", "outline",
  // A text spec's outline, shadow and glow colours.
  "oc", "sc", "gc",
};

/// styleFactsOf is [doc]'s style, measured, on a canvas [width] by
/// [height] design pixels.
Map<String, Object?> styleFactsOf(Map<String, dynamic> doc,
    {required double width, required double height}) {
  var elements = _allElements(doc);
  var size = doc["size"] is Map ? doc["size"] as Map : const {};
  var ratio = size["ratio"];
  var frameRate = (doc["frameRate"] as num?)?.toDouble() ?? 24;

  return {
    "canvas": {
      "width": width.round(),
      "height": height.round(),
      if (ratio != null) "ratio": ratio,
      "frameRate": frameRate,
      if (doc["kind"] != null) "kind": doc["kind"],
    },
    // The elements' colours, apart from the backgrounds': a background's
    // pattern carries settings for colours it may not show, which would
    // crowd out the ones that are seen in front.
    "palette": _palette(elements),
    "backgroundColours":
        _palette([doc["background"], ..._sceneBackgrounds(doc)]),
    "type": _type(elements, height),
    if (doc["textStyles"] is List && (doc["textStyles"] as List).isNotEmpty)
      "textStyles": doc["textStyles"],
    if (doc["background"] != null) "background": doc["background"],
    "motion": _motion(doc, elements, frameRate),
    "sound": _sound(doc, elements),
    "samples": _samples(elements),
  };
}

/// _allElements are every scene's elements and the master's.
List<Map<String, dynamic>> _allElements(Map<String, dynamic> doc) {
  var out = <Map<String, dynamic>>[];
  void add(Object? list) {
    if (list is! List) return;
    for (var e in list) {
      if (e is Map<String, dynamic>) out.add(e);
    }
  }

  if (doc["scenes"] is List) {
    for (var s in doc["scenes"] as List) {
      if (s is Map) add(s["elements"]);
    }
  } else {
    add(doc["elements"]);
  }
  if (doc["master"] is Map) add((doc["master"] as Map)["elements"]);
  return out;
}

List<Object?> _sceneBackgrounds(Map<String, dynamic> doc) => [
      if (doc["scenes"] case List scenes)
        for (var s in scenes)
          if (s is Map && s["background"] != null) s["background"]
    ];

/// hexOf is a colour as #RRGGBB (and its opacity, where not opaque).
String hexOf(int argb) {
  var rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, "0").toUpperCase();
  return "#$rgb";
}

/// _palette counts every colour used, most used first.
List<Map<String, Object?>> _palette(List<Object?> roots) {
  var counts = <int, int>{};
  void walk(Object? v, String? key) {
    if (v is Map) {
      for (var e in v.entries) {
        walk(e.value, "${e.key}");
      }
    } else if (v is List) {
      for (var x in v) {
        walk(x, key);
      }
    } else if (v is int && key != null && _colourKeys.contains(key)) {
      // A colour has some opacity; a plain count or size has none.
      if (v > 0x00FFFFFF && v <= 0xFFFFFFFF) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
  }

  for (var r in roots) {
    walk(r, null);
  }
  var ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (var e in ranked.take(12))
      {
        "argb": e.key,
        "hex": hexOf(e.key),
        if ((e.key >> 24) != 0xFF)
          "opacity": ((e.key >> 24) / 255 * 100).round() / 100,
        "uses": e.value,
      }
  ];
}

/// _type is the type in use, largest first, each with how often and an
/// example of its words; the largest is called the headline.
List<Map<String, Object?>> _type(
    List<Map<String, dynamic>> elements, double height) {
  var groups = <String, Map<String, Object?>>{};
  for (var e in elements) {
    if (e["kind"] != "text") continue;
    var spec = e["textSpec"] is Map ? e["textSpec"] as Map : const {};
    var font = "${spec["font"] ?? "Inter"}";
    var size = (spec["size"] as num?)?.toDouble() ?? 0;
    var weight = (spec["weight"] as num?)?.toInt() ?? 400;
    var key = "$font|${size.round()}|$weight";
    var g = groups.putIfAbsent(
        key,
        () => {
              "font": font,
              "size": size.round(),
              "sizeOfHeight":
                  height > 0 ? (size / height * 1000).round() / 1000 : null,
              "weight": weight,
              if (spec["color"] is int) "color": hexOf(spec["color"] as int),
              if (spec["italic"] == true) "italic": true,
              if (spec["align"] != null) "align": spec["align"],
              if (spec["lh"] != null) "lineHeight": spec["lh"],
              if (spec["ls"] != null) "letterSpacing": spec["ls"],
              if (spec["case"] != null) "case": spec["case"],
              "uses": 0,
              "example": _short("${e["text"] ?? ""}"),
            });
    g["uses"] = (g["uses"] as int) + 1;
  }
  var list = groups.values.toList()
    ..sort((a, b) => (b["size"] as int).compareTo(a["size"] as int));
  const roles = ["headline", "subhead", "body", "caption", "small", "smallest"];
  return [
    for (var i = 0; i < list.length && i < roles.length; i++)
      {"role": roles[i], ...list[i]}
  ];
}

String _short(String s) {
  var t = s.replaceAll(RegExp(r"\s+"), " ").trim();
  return t.length <= 60 ? t : "${t.substring(0, 57)}…";
}

/// _motion is how things arrive and leave, and how long scenes run.
Map<String, Object?> _motion(Map<String, dynamic> doc,
    List<Map<String, dynamic>> elements, double frameRate) {
  var arrivals = <String, int>{};
  var exits = <String, int>{};
  var lengths = <num>[];
  var keyframed = 0;
  for (var e in elements) {
    // A text's arrival is "animation"; every other kind's is "anim".
    var arrival = e["kind"] == "text" ? e["animation"] : e["anim"];
    if (arrival case Map a) {
      if (a["preset"] case String p) arrivals[p] = (arrivals[p] ?? 0) + 1;
      if (a["exit"] case String x) exits[x] = (exits[x] ?? 0) + 1;
      if (a["length"] case num l) lengths.add(l);
    }
    if (e["track"] case Map t when t["keys"] is List) keyframed++;
  }
  var transitions = <String, int>{};
  var seconds = <double>[];
  if (doc["scenes"] case List scenes) {
    for (var s in scenes) {
      if (s is! Map) continue;
      if (s["transition"] case Map t) {
        var k = "${t["kind"] ?? "cut"}";
        transitions[k] = (transitions[k] ?? 0) + 1;
      }
      if (s["frames"] case num f) seconds.add(f / frameRate);
    }
  } else if (doc["frames"] case num f) {
    seconds.add(f / frameRate);
  }
  double? mean(List<num> xs) => xs.isEmpty
      ? null
      : (xs.fold<num>(0, (a, b) => a + b) / xs.length * 100).round() / 100;
  return {
    if (arrivals.isNotEmpty) "arrivals": _ranked(arrivals),
    if (exits.isNotEmpty) "exits": _ranked(exits),
    if (lengths.isNotEmpty) "arrivalFrames": mean(lengths),
    if (keyframed > 0) "keyframedElements": keyframed,
    if (transitions.isNotEmpty) "transitions": _ranked(transitions),
    if (seconds.isNotEmpty) "sceneSeconds": mean(seconds),
  };
}

Map<String, int> _ranked(Map<String, int> counts) {
  var list = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (var e in list) e.key: e.value};
}

/// _sound is the master mix and the voices speech uses.
Map<String, Object?> _sound(
    Map<String, dynamic> doc, List<Map<String, dynamic>> elements) {
  var voices = <String>{};
  var devices = <String, int>{};
  for (var e in elements) {
    var mix = (e["clip"] is Map) ? (e["clip"] as Map)["mix"] : null;
    if (mix is! Map) continue;
    if (mix["speech"] case Map s) {
      for (var k in ["voice", "speaker", "voiceId"]) {
        if (s[k] case String v when v.isNotEmpty) voices.add(v);
      }
    }
    if (mix["devices"] case List list) {
      for (var d in list) {
        if (d is Map && d["kind"] is String) {
          var k = d["kind"] as String;
          devices[k] = (devices[k] ?? 0) + 1;
        }
      }
    }
  }
  return {
    if (doc["masterMix"] != null) "masterMix": doc["masterMix"],
    if (voices.isNotEmpty) "voices": voices.toList(),
    if (devices.isNotEmpty) "channelEffects": _ranked(devices),
  };
}

/// _samples are a few elements to copy from: the largest text, the next
/// size of text, and the first of each other kind, up to six.
List<Map<String, dynamic>> _samples(List<Map<String, dynamic>> elements) {
  double sizeOf(Map e) =>
      ((e["textSpec"] is Map ? (e["textSpec"] as Map)["size"] : null) as num?)
          ?.toDouble() ??
      0;
  var texts = elements.where((e) => e["kind"] == "text").toList()
    ..sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));
  var out = <Map<String, dynamic>>[];
  if (texts.isNotEmpty) out.add(texts.first);
  var second = texts
      .where((t) => sizeOf(t).round() != sizeOf(texts.first).round())
      .firstOrNull;
  if (second != null) out.add(second);
  var kinds = <String>{"text"};
  for (var e in elements) {
    if (out.length >= 6) break;
    var k = "${e["kind"]}";
    if (kinds.add(k)) out.add(e);
  }
  return out;
}

/// factualGuide is a guide written from [facts] alone, for a style saved
/// without Claude: what is measured, plainly.
String factualGuide(String name, Map<String, Object?> facts) {
  var b = StringBuffer("# $name\n\n");
  var canvas = facts["canvas"] as Map? ?? const {};
  b.writeln("A Bison Relay canvas style, measured from a canvas of "
      "${canvas["width"]}×${canvas["height"]} at ${canvas["frameRate"]} "
      "frames a second.\n");
  var palette = facts["palette"] as List? ?? const [];
  if (palette.isNotEmpty) {
    b.writeln("## Colours\n");
    b.writeln("In front (the background's own are in style.json):\n");
    for (var c in palette.take(8)) {
      b.writeln(
          "- ${c["hex"]}${c["opacity"] != null ? " at ${c["opacity"]}" : ""}"
          " (0x${(c["argb"] as int).toRadixString(16).toUpperCase()} = "
          "${c["argb"]}), used ${c["uses"]}×");
    }
    b.writeln();
  }
  var type = facts["type"] as List? ?? const [];
  if (type.isNotEmpty) {
    b.writeln("## Type\n");
    for (var t in type) {
      b.writeln("- ${t["role"]}: ${t["font"]} ${t["weight"]}, size ${t["size"]}"
          "${t["color"] != null ? ", ${t["color"]}" : ""}"
          "${t["example"] != "" ? " — e.g. \"${t["example"]}\"" : ""}");
    }
    b.writeln();
  }
  var motion = facts["motion"] as Map? ?? const {};
  if (motion.isNotEmpty) {
    b.writeln("## Motion and timing\n");
    if (motion["arrivals"] case Map a) {
      b.writeln("- Arrivals: ${a.keys.join(", ")}");
    }
    if (motion["arrivalFrames"] != null) {
      b.writeln("- Arrivals take about ${motion["arrivalFrames"]} frames");
    }
    if (motion["transitions"] case Map t) {
      b.writeln("- Scene transitions: ${t.keys.join(", ")}");
    }
    if (motion["sceneSeconds"] != null) {
      b.writeln("- Scenes run about ${motion["sceneSeconds"]} seconds");
    }
    b.writeln();
  }
  b.writeln("The measured facts, sample elements and backgrounds are in "
      "style.json beside this file (canvas_style_get gives them).");
  return b.toString();
}
