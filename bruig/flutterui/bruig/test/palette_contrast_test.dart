import 'dart:math' as math;

import 'package:bruig/theming_system/color_palette_section.dart';
import 'package:bruig/theming_system/palette_library.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// palette_contrast_test.dart runs every shipped palette through the real
// apply path (paletteApplied) and measures the contrast of each text/
// background pair it produces, against the WCAG formula rather than an
// eyeballed judgement.
//
// It exists because the failures it guards against are invisible in code
// review: the palettes are dense walls of hex literals, and a slot whose
// meaning changes (or a neutral role that every palette inherits from the
// seed) can quietly drag all of them under the readable floor at once --
// which is exactly what happened to navText/sidebarText.

double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrast(Color a, Color b) {
  var la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

// 4.5:1 is WCAG AA for body text; 3:1 is the floor for a UI element's own
// boundary (a button border), which doesn't have to be read as text.
const _text = 4.5;
const _ui = 3.0;

// _pairs is every foreground/background combination the app actually
// renders from a palette, named the way a person would describe it.
List<(String, Color, Color, double)> _pairs(ThemePreset p) => [
      ("body text on master background", p.onSurface, p.primary, _text),
      ("body text on secondary background", p.onSurface, p.tertiary, _text),
      ("body text on received bubble", p.onSurface, p.speechBackground, _text),
      ("body text on sent bubble", p.onSurface, p.speechBackgroundSent, _text),
      ("body text on notification surface", p.onSurface, p.fourth, _text),
      ("muted text on master background", p.onSurfaceVariant, p.primary, _text),
      ("nav text on nav background", p.navText, p.secondary, _text),
      ("nav selected on nav background", p.navSelected, p.secondary, _text),
      ("sidebar text on sidebar", p.sidebarText, p.sidebarBackground, _text),
      ("sidebar accent on sidebar", p.sidebarAccent, p.sidebarBackground, _text),
      ("error text on master background", p.error, p.primary, _text),
      ("success text on master background", p.success, p.primary, _text),
      // Buttons 2 and 3: an unfilled label, sitting on whichever surface
      // the button happens to be placed on.
      ("button label on master background", p.buttonText1, p.primary, _text),
      ("button label on secondary background", p.buttonText1, p.tertiary, _text),
      ("button border on master background", p.buttonBorderColor, p.primary, _ui),
      // Buttons 1, 4 and 5: a filled label on its own fill.
      ("button 1 label on its fill", p.buttonText2, p.accentContainer, _text),
      ("button 4 label on its fill", p.buttonText2, p.buttonBackgroundThird, _text),
      ("button 5 label on its fill", p.buttonText2, p.buttonBackgroundSecondary,
          _text),
    ];

// _separations are the pairs that must be *distinguishable* rather than
// readable: a surface that has to look raised off the one behind it. 1.15:1
// is about where a flat colour stops being a visible edge -- the bug these
// catch had several of them at 1.03:1, i.e. invisible.
List<(String, Color, Color, double)> _separations(ThemePreset p) => [
      ("notification surface vs master background", p.fourth, p.primary, 1.4),
      ("sent bubble vs master background", p.speechBackgroundSent, p.primary,
          1.15),
      ("received bubble vs master background", p.speechBackground, p.primary,
          1.08),
      ("secondary background vs master background", p.tertiary, p.primary, 1.08),
    ];

void _check(String palette, List<(String, Color, Color, double)> pairs,
    List<String> failures) {
  for (var (what, fg, bg, floor) in pairs) {
    var v = contrast(fg, bg);
    if (v < floor) {
      failures.add("$palette: $what is ${v.toStringAsFixed(2)}:1 "
          "(needs ${floor.toStringAsFixed(2)})");
    }
  }
}

void main() {
  test('every built-in palette is readable once applied', () {
    var failures = <String>[];
    for (var palette in builtinPalettes) {
      var applied =
          paletteApplied(ThemePreset.seedFor(palette.brightness), palette);
      _check(palette.name, _pairs(applied), failures);
      _check(palette.name, _separations(applied), failures);
    }
    expect(failures, isEmpty, reason: "\n${failures.join("\n")}\n");
  });

  test('the Default and Light seeds are readable', () {
    var failures = <String>[];
    for (var b in [Brightness.dark, Brightness.light]) {
      var seed = ThemePreset.seedFor(b);
      var name = b == Brightness.dark ? "Default" : "Light";
      _check(name, _pairs(seed), failures);
      _check(name, _separations(seed), failures);
    }
    expect(failures, isEmpty, reason: "\n${failures.join("\n")}\n");
  });

  // Inputs are not part of a library palette's stored colours, so they have
  // to be *derived* on apply. They weren't, which left every text box in the
  // app on the seed's lavender whichever palette was applied.
  test('inputs follow the palette they were applied from', () {
    var failures = <String>[];
    for (var palette in builtinPalettes) {
      var seed = ThemePreset.seedFor(palette.brightness);
      var a = paletteApplied(seed, palette);
      if (a.inputSelected == seed.inputSelected &&
          a.navAccent != seed.navAccent) {
        failures.add("${palette.name}: focused input border is still the "
            "seed's colour");
      }
      var focused = contrast(a.inputSelected, a.primary);
      var resting = contrast(a.inputResting, a.primary);
      // A border is a UI boundary, so 3:1 -- it isn't read as text.
      if (focused < 3.0) {
        failures.add("${palette.name}: focused input border is "
            "${focused.toStringAsFixed(2)}:1 on the page");
      }
      if (resting >= focused) {
        failures.add("${palette.name}: resting input border "
            "(${resting.toStringAsFixed(2)}:1) is not quieter than focused "
            "(${focused.toStringAsFixed(2)}:1)");
      }
      if (resting < 1.6) {
        failures.add("${palette.name}: resting input border is invisible at "
            "${resting.toStringAsFixed(2)}:1");
      }
    }
    expect(failures, isEmpty, reason: "\n${failures.join("\n")}\n");
  });

  // An input's resting border must always be the quieter of the pair. The
  // seed used to derive it by *darkening* the focused colour, which is only
  // muting on a dark theme -- on the light seed it produced a 9.62:1
  // resting border against a 5.29:1 focused one.
  test('a resting input border is quieter than a focused one', () {
    for (var b in [Brightness.dark, Brightness.light]) {
      var p = ThemePreset.seedFor(b);
      var resting = contrast(p.inputResting, p.primary);
      var selected = contrast(p.inputSelected, p.primary);
      expect(resting, lessThan(selected),
          reason: "${b.name}: resting ${resting.toStringAsFixed(2)}:1 is not "
              "quieter than focused ${selected.toStringAsFixed(2)}:1");
      // ...but still a visible boundary.
      expect(resting, greaterThan(1.6), reason: b.name);
    }
  });

  test('every built-in palette carries a full set of colors', () {
    for (var p in builtinPalettes) {
      expect(p.colors, hasLength(kVividPaletteSlots.length),
          reason: "${p.name} has ${p.colors.length} colors");
    }
  });

  // A palette exported before the button slots existed must still load --
  // the three tail slots fall back to the seed rather than reading off the
  // end of the list.
  test('a short (pre-button) palette still applies', () {
    var short = ColorPalette(
        id: "old", name: "old", colors: builtinPalettes.first.colors.sublist(0, 12));
    var seed = ThemePreset.seedFromDark();
    var applied = paletteApplied(seed, short);
    expect(applied.buttonText1, seed.buttonText1);
    expect(applied.buttonBorderColor, seed.buttonBorderColor);
    expect(applied.buttonBackgroundThird, seed.buttonBackgroundThird);
    expect(applied.primary, short.colors[0]);
  });
}
