import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_dropdown_menu_test.dart is a dropdown's open list: as wide as its
// longest name, so no name is cut short while it is being chosen.

void main() {
  testWidgets("an open list shows every name in full", (tester) async {
    // The test's font draws every letter twelve pixels wide.
    const long = "Gradient map, long";
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (c) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: CanvasDropdown<int>(
                key: const ValueKey("menu"),
                label: "",
                value: 0,
                width: 100,
                options: const [(0, "Fade"), (1, long)],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Fade"));
    await tester.pumpAndSettle();
    // The long name in the open list, laid out in full: no wider than
    // the line it has.
    var shown = find.text(long).last;
    var text = tester.renderObject<RenderParagraph>(shown);
    expect(text.didExceedMaxLines, isFalse, reason: "not cut short");
    expect(tester.getSize(shown).width, greaterThan(150),
        reason: "wider than the button it opened from");
  });
}
