import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_tiles_fold_narrow_test.dart is a folding row of tiles in a narrow
// place with the app's text larger, as Ken runs it: its heading is cut
// short, not run off the edge (his log, 2026-11-12: "A RenderFlex
// overflowed by 12 pixels on the right", at 103 wide).

void main() {
  for (var scale in [1.0, 1.25, 1.5]) {
    for (var width in [80.0, 103.0, 140.0]) {
      testWidgets("${width}px at ${scale}x", (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    // In a section's cards, where a row of tiles folds.
                    child: CanvasCards(
                        child: CanvasTiles<int>(
                      label: "Which shape",
                      foldAs: "test.tiles.narrow",
                      tiles: [
                        for (var i = 0; i < 6; i++)
                          CanvasTile(i, "Tile number $i", icon: Icons.star),
                      ],
                      selected: (i) => i == 2,
                      onPick: (_) {},
                    )),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
