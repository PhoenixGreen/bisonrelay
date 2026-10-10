import 'package:bruig/plugin_system/canvas/model/procedural_palettes.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_pattern_fill_test.dart is a pattern painted into letters, a box or
// a shape: the same style, looks and palettes a background has, and the
// style's own settings behind a heading.

Future<TextFill Function()> _pump(WidgetTester tester, TextFill start) async {
  SharedPreferences.setMockInitialValues({});
  var fill = start;
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => ThemeNotifier(doLoad: false),
      child: Scaffold(
        body: SingleChildScrollView(
          child: CanvasControlScope(
            maxWidth: 300,
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, set) => CanvasControlGroup(
                  label: "Fill",
                  children: fillBits(
                      context, fill, (f) => set(() => fill = f), () {}, () {},
                      keyPrefix: "shape"),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return () => fill;
}

const _flames = TextFill(
    kind: TextFillKind.pattern,
    pattern: ProceduralSpec(style: ProceduralStyle.flames));

void main() {
  testWidgets("a pattern starts from the style's first look", (tester) async {
    var fill = await _pump(tester, _flames);
    await tester.tap(find.byKey(const ValueKey("shapeFillPattern")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Circuit").last);
    await tester.pumpAndSettle();
    expect(fill().pattern.style, ProceduralStyle.circuit);
    expect(lookMatching(fill().pattern),
        same(looksFor(ProceduralStyle.circuit).first));
  });

  testWidgets("and any of its looks can be chosen", (tester) async {
    var fill = await _pump(tester, _flames);
    var look = looksFor(ProceduralStyle.flames)[2];
    await tester.tap(find.byKey(const ValueKey("shapeFillPatternLook")));
    await tester.pumpAndSettle();
    await tester.tap(find.text(look.name).last);
    await tester.pumpAndSettle();
    expect(lookMatching(fill().pattern), same(look));
  });

  testWidgets("a palette recolours it", (tester) async {
    var fill = await _pump(tester, _flames);
    await tester.tap(find.byKey(const ValueKey("shapeFillPalette")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Ocean").last);
    await tester.pumpAndSettle();
    expect(paletteNamed("Ocean")!.matches(fill().pattern), isTrue);
  });

  testWidgets("its own settings are behind a heading, and reach it",
      (tester) async {
    var fill = await _pump(tester, _flames);
    expect(find.byKey(const ValueKey("param-flameKind")), findsNothing);
    await tester.tap(find.text("PATTERN SETTINGS"));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("param-flameKind")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Soft fire").last);
    await tester.pumpAndSettle();
    expect(fill().pattern.choice("flameKind"), 1);
    // Not the background's own: no light, no layers, no movement.
    expect(find.text("LIGHTS"), findsNothing);
    expect(find.text("PATTERN LAYERS"), findsNothing);
    expect(find.text("MOVEMENT"), findsNothing);
  });
}
