import 'package:bruig/theming_system/model/preset_library.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// builtin_presets_test.dart loads the themes that ship with the app.
//
// They are stored as JSON (see preset_library.dart for why), so nothing but
// a test proves they still parse -- a malformed one would otherwise fail at
// startup, on a user's machine, with the theme picker simply missing an
// entry.

void main() {
  test("every built-in preset parses", () {
    expect(builtinPresets, isNotEmpty);
    for (var p in builtinPresets) {
      expect(p.id, isNotEmpty);
      expect(p.name, isNotEmpty);
      expect(isBuiltinPresetId(p.id), isTrue);
    }
  });

  test("Ulysses ships, and carries what it was built with", () {
    var u = builtinPresets.firstWhere((p) => p.id == "ulysses");
    expect(u.name, "Ulysses");
    expect(u.brightness, Brightness.dark);

    // The palette it was authored against.
    expect(u.primary, const Color(0xFF1E1E1E));
    expect(u.secondary, const Color(0xFF161616));
    expect(u.sidebarAccent, const Color(0xFFC08A5B));
    expect(u.navAccent, const Color(0xFF0A84FF));

    // It names the built-in style guide rather than carrying a copy, so the
    // two stay one thing.
    var md = u.areas[ThemeArea.markdown];
    expect(md, isNotNull);
    expect(md!.markdownGuideId, "ulysses");
    expect(md.markdownSavedGuides, isEmpty);
    expect(builtInGuideFor(md.markdownGuideId), isNotNull,
        reason: "the guide it names has to exist");
  });

  test("a built-in preset compiles to a theme", () {
    // toAppTheme is what registering one runs, so a preset that parses but
    // cannot be compiled would still break the picker.
    for (var p in builtinPresets) {
      var theme = p.toAppTheme();
      expect(theme.key, "custom:${p.id}");
      expect(theme.data.colorScheme.surface, p.primary);
    }
  });

  test("it round-trips back to itself", () {
    for (var p in builtinPresets) {
      var again = ThemePreset.fromJson(p.toJson());
      expect(again.primary, p.primary);
      expect(again.areas.keys.toSet(), p.areas.keys.toSet());
    }
  });
}
