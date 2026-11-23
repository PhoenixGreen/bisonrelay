import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'package:bruig/plugin_system/canvas/model/font_outlines.dart';

// font_files.dart finds the font file a drawing's text is set from: the
// app's bundled faces, and common desktop ones where this system keeps them.
// A missing face falls back to Inter; a missing italic is the upright leant.

class FontFiles {
  FontFiles._();
  static final FontFiles instance = FontFiles._();

  final Map<String, FontPick?> _picks = {};
  final Map<String, Future<FontPick?>> _loading = {};

  static String _key(String family, int weight, bool italic) =>
      "$family/$weight/$italic";

  /// cached is the face for [family], [weight] and [italic] if already read,
  /// or null; typing uses it so as not to wait.
  FontPick? cached(String family, int weight, bool italic) =>
      _picks[_key(family, weight, italic)];

  /// forgetForTest forgets the faces read and any read under way, so the
  /// next test file reads afresh: a read begun under one file's clock never
  /// finishes under the next's, and its load would wait for ever.
  @visibleForTesting
  static void forgetForTest() {
    instance._picks.clear();
    instance._loading.clear();
  }

  /// load is the face for [family], [weight] and [italic], read once.
  Future<FontPick?> load(String family, int weight, bool italic) {
    var key = _key(family, weight, italic);
    if (_picks.containsKey(key)) return Future.value(_picks[key]);
    return _loading[key] ??= _find(family, weight, italic).then((pick) {
      _picks[key] = pick;
      _loading.remove(key);
      return pick;
    });
  }

  Future<FontPick?> _find(String family, int weight, bool italic) async {
    for (var (:file, :leans) in _sources(family, weight, italic)) {
      var face = await _read(file);
      if (face != null) return FontPick(face, lean: leans);
    }
    if (family != "Inter") return _find("Inter", weight, italic);
    return null;
  }

  /// _read is the face [file] names, or null.
  Future<FontFace?> _read(_FontFile file) async {
    var (:path, :style) = file;
    Uint8List? bytes;
    try {
      if (path.startsWith("assets/")) {
        bytes = (await rootBundle.load(path)).buffer.asUint8List();
      } else {
        var f = File(path);
        if (!await f.exists()) return null;
        bytes = await f.readAsBytes();
      }
    } catch (_) {
      return null;
    }
    if (style == null) return FontFace.parse(bytes);
    for (var i = 0; i < FontFace.faces(bytes); i++) {
      var face = FontFace.parse(bytes, index: i);
      if (face != null && face.style.toLowerCase() == style.toLowerCase()) {
        return face;
      }
    }
    return FontFace.parse(bytes);
  }

  /// _familyName is what a family name may be: it comes from the document
  /// and becomes part of a path, so only letters, digits, spaces, few marks.
  static final _familyName = RegExp(r"^[A-Za-z0-9 _+&'-]{1,64}$");

  /// _sources is where [family] in [weight] and [italic] may be, best
  /// first, each with whether what is found there has to be leant over.
  List<_FontSource> _sources(String family, int weight, bool italic) {
    if (!_familyName.hasMatch(family)) return const [];
    var bold = weight >= 600;
    // The family's own files with each style, best first: the one asked
    // for, then the same weight upright -- to lean -- then regular.
    List<_FontSource> styled(_FontFile Function(bool bold, bool italic) file) =>
        [
          (file: file(bold, italic), leans: false),
          if (italic) (file: file(bold, false), leans: true),
          if (bold) (file: file(false, italic), leans: false),
          (file: file(false, false), leans: italic),
        ];

    switch (family) {
      case "Inter":
        const names = {
          100: "Thin",
          200: "ExtraLight",
          300: "Light",
          400: "Regular",
          500: "Medium",
          600: "SemiBold",
          700: "Bold",
          800: "ExtraBold",
          900: "Black",
        };
        var w = ((weight / 100).round() * 100).clamp(100, 900);
        var name = names[w]!;
        String file(bool it) => it
            ? (name == "Regular"
                ? "assets/fonts/Inter-Italic.otf"
                : "assets/fonts/Inter-${name}Italic.otf")
            : "assets/fonts/Inter-$name.otf";
        return [
          _asset(file(italic), leans: false),
          if (italic) _asset(file(false), leans: true),
        ];
      case "RobotoMono":
        return [
          if (italic)
            _asset("assets/fonts/RobotoMono-Italic-VariableFont_wght.ttf",
                leans: false),
          _asset("assets/fonts/RobotoMono-VariableFont_wght.ttf",
              leans: italic),
        ];
      // One weight, and no italic: leant over where one is asked for.
      case "Bebas Neue":
        return [_asset("assets/fonts/BebasNeue-Regular.ttf", leans: italic)];
      // Comic lettering: one face, already leaning, so never leant again.
      case "Bangers":
        return [_asset("assets/fonts/Bangers-Regular.ttf", leans: false)];
      // Regular and bold, each with its own italic.
      case "PTSerif":
        return styled((b, i) => (
              path: "assets/fonts/PTSerif-${b ? "Bold" : ""}"
                  "${i ? "Italic" : (b ? "" : "Regular")}.ttf",
              style: null
            ));
      // Four weights, the nearest taken; no italic.
      case "Oswald":
        var name = switch (weight) {
          < 450 => "Regular",
          < 550 => "Medium",
          < 650 => "SemiBold",
          _ => "Bold",
        };
        return [_asset("assets/fonts/Oswald-$name.ttf", leans: italic)];
    }

    if (Platform.isMacOS) {
      const dir = "/System/Library/Fonts/Supplemental";
      if (family == "Helvetica") {
        String style(bool b, bool i) =>
            b ? (i ? "Bold Oblique" : "Bold") : (i ? "Oblique" : "Regular");
        return styled((b, i) =>
            (path: "/System/Library/Fonts/Helvetica.ttc", style: style(b, i)));
      }
      return styled((b, i) {
        var suffix = b ? (i ? " Bold Italic" : " Bold") : (i ? " Italic" : "");
        return (path: "$dir/$family$suffix.ttf", style: null);
      });
    }
    if (Platform.isWindows) {
      var root = "${Platform.environment["WINDIR"] ?? r"C:\Windows"}\\Fonts";
      const files = {
        "Arial": ("arial", "arialbd", "ariali", "arialbi"),
        "Helvetica": ("arial", "arialbd", "ariali", "arialbi"),
        "Georgia": ("georgia", "georgiab", "georgiai", "georgiaz"),
        "Times New Roman": ("times", "timesbd", "timesi", "timesbi"),
        "Courier New": ("cour", "courbd", "couri", "courbi"),
        "Verdana": ("verdana", "verdanab", "verdanai", "verdanaz"),
        "Impact": ("impact", "impact", "impact", "impact"),
      };
      var f = files[family];
      if (f == null) return const [];
      return styled((b, i) {
        var n = b ? (i ? f.$4 : f.$2) : (i ? f.$3 : f.$1);
        return (path: "$root\\$n.ttf", style: null);
      });
    }
    // Linux: Microsoft's core fonts where they are installed, and the
    // Liberation faces drawn to the same measurements where they are not.
    const core = "/usr/share/fonts/truetype/msttcorefonts";
    const liberation = "/usr/share/fonts/truetype/liberation";
    var name = family.replaceAll(" ", "_");
    var lib = switch (family) {
      "Arial" || "Helvetica" => "LiberationSans",
      "Times New Roman" => "LiberationSerif",
      "Courier New" => "LiberationMono",
      _ => null,
    };
    return [
      ...styled((b, i) {
        var suffix = b ? (i ? "_Bold_Italic" : "_Bold") : (i ? "_Italic" : "");
        return (path: "$core/$name$suffix.ttf", style: null);
      }),
      if (lib != null)
        ...styled((b, i) {
          var suffix =
              b ? (i ? "BoldItalic" : "Bold") : (i ? "Italic" : "Regular");
          return (path: "$liberation/$lib-$suffix.ttf", style: null);
        }),
    ];
  }
}

/// _FontFile is where a face is: an asset or a file, and the style to pick
/// from a collection, or null for its only face.
typedef _FontFile = ({String path, String? style});

/// _FontSource is a place a face may be, and whether what is found there has
/// to be leant over to be italic.
typedef _FontSource = ({_FontFile file, bool leans});

/// _asset is a bundled face, the only one in its file.
_FontSource _asset(String path, {required bool leans}) =>
    (file: (path: path, style: null), leans: leans);
