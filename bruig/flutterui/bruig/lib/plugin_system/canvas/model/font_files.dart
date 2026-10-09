import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/font_outlines.dart';
import 'package:flutter/services.dart';

// font_files.dart finds the font file a drawing's text is set from: the
// faces the app carries itself, and the ones every desktop has, where this
// one keeps them. A face asked for that is not to be had comes out in Inter,
// the app's own -- and a style a family has no file for is made: an italic
// leant over, where there is no italic to read.

/// FontPick is the face found for a family, weight and slant: the face,
/// and whether it has to be leant over to be italic.
class FontPick {
  final FontFace face;
  final bool lean;
  const FontPick(this.face, {this.lean = false});
}

/// FontFiles finds faces and keeps every one it has read.
class FontFiles {
  FontFiles._();
  static final FontFiles instance = FontFiles._();

  final Map<String, FontPick?> _picks = {};
  final Map<String, Future<FontPick?>> _loading = {};

  static String _key(String family, int weight, bool italic) =>
      "$family/$weight/$italic";

  /// cached is the face for [family], [weight] and [italic] where it has
  /// been read already -- what typing reads, a letter at a time, without
  /// waiting -- or null.
  FontPick? cached(String family, int weight, bool italic) =>
      _picks[_key(family, weight, italic)];

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
    for (var (source, leans) in _sources(family, weight, italic)) {
      var face = await _read(source);
      if (face != null) return FontPick(face, lean: leans);
    }
    if (family != "Inter") return _find("Inter", weight, italic);
    return null;
  }

  /// _read is the face [source] names -- an asset, or a file and the style
  /// to pick out of it where it is a collection -- or null.
  Future<FontFace?> _read((String, String?) source) async {
    var (path, style) = source;
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

  /// _sources is where [family] in [weight] and [italic] may be, best
  /// first, each with whether what is found there has to be leant over.
  List<((String, String?), bool)> _sources(
      String family, int weight, bool italic) {
    var bold = weight >= 600;
    // The family's own files with each style, best first: the one asked
    // for, then the same weight upright -- to lean -- then regular.
    List<((String, String?), bool)> styled(
            (String, String?) Function(bool bold, bool italic) file) =>
        [
          (file(bold, italic), false),
          if (italic) (file(bold, false), true),
          if (bold) (file(false, italic), false),
          (file(false, false), italic),
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
          ((file(italic), null), false),
          if (italic) ((file(false), null), true),
        ];
      case "RobotoMono":
        return [
          if (italic)
            (
              ("assets/fonts/RobotoMono-Italic-VariableFont_wght.ttf", null),
              false
            ),
          (("assets/fonts/RobotoMono-VariableFont_wght.ttf", null), italic),
        ];
    }

    if (Platform.isMacOS) {
      const dir = "/System/Library/Fonts/Supplemental";
      if (family == "Helvetica") {
        String style(bool b, bool i) =>
            b ? (i ? "Bold Oblique" : "Bold") : (i ? "Oblique" : "Regular");
        return styled(
            (b, i) => ("/System/Library/Fonts/Helvetica.ttc", style(b, i)));
      }
      return styled((b, i) {
        var suffix = b ? (i ? " Bold Italic" : " Bold") : (i ? " Italic" : "");
        return ("$dir/$family$suffix.ttf", null);
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
        return ("$root\\$n.ttf", null);
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
        return ("$core/$name$suffix.ttf", null);
      }),
      if (lib != null)
        ...styled((b, i) {
          var suffix =
              b ? (i ? "BoldItalic" : "Bold") : (i ? "Italic" : "Regular");
          return ("$liberation/$lib-$suffix.ttf", null);
        }),
    ];
  }
}
