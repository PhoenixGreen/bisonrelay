import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/character_turnaround.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_drawing_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_turnaround_test.dart is a sketch's turnaround sheet: its
// other views laid out beside it, lines across them at the heights a turn
// keeps, and a panel clicked turning it to that view.

CharacterElement _sketch() => CharacterElement(
    const ElementBase(id: "c", x: 40, y: 40, width: 120, height: 300),
    dna: characterCast.first.dna,
    views: CharacterView.start);

void main() {
  test("the sheet: a panel for each other view, in a row, and the lines", () {
    var e = _sketch();
    var sheet = Turnaround.of(e, 0, 12, panelOptions(e, adding: false));
    // Front, side both ways and back: three beside the front.
    expect(sheet.current, "0,0");
    expect(sheet.panels.map((p) => p.key), isNot(contains("0,0")));
    expect(sheet.panels, hasLength(panelOptions(e, adding: false).length - 1));
    for (var (i, p) in sheet.panels.indexed) {
      expect(p.rect.width, closeTo(e.bounds.width, 1e-6));
      expect(p.rect.height, closeTo(e.bounds.height, 1e-6));
      expect(p.rect.left, greaterThan(i == 0 ? e.bounds.right : sheet.panels[i - 1].rect.right));
    }
    // Top to bottom, inside the figure's height.
    var ys = [for (var g in sheet.guides) g.y];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(ys.first, greaterThanOrEqualTo(e.bounds.top));
    expect(ys.last, lessThanOrEqualTo(e.bounds.bottom + 1));
    // A panel shows the character from its view.
    var side = sheet.panels.firstWhere((p) => p.key == "90,0");
    expect(sheet.shownAs(side.key, side.rect).pose.turn, 90);
    expect(sheet.panelAt(side.rect.center)?.key, "90,0");
    expect(sheet.neighbour, isNotNull);
  });

  testWidgets("a panel clicked turns it to that view", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(_sketch()));
    addTearDown(c.dispose);
    c.selectOnly("c");
    c.showTurnaround = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: CanvasStage(key: const ValueKey("stage"), controller: c))),
    ));
    await tester.pumpAndSettle();
    var stage = tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
    var page = stage.pageRect;
    var scale = page.width / c.document.size.size.width;
    Offset onScreen(Offset doc) =>
        tester.getTopLeft(find.byKey(const ValueKey("stage"))) + page.topLeft + doc * scale;
    var e = c.document.elementById("c") as CharacterElement;
    var sheet = Turnaround.of(e, 0, 12, panelOptions(e, adding: false));
    var back = sheet.panels.firstWhere((p) => p.key == "180,0");
    await tester.tapAt(onScreen(back.rect.center));
    await tester.pumpAndSettle();
    expect((c.document.elementById("c") as CharacterElement).pose.turn, 180);
    c.undo();
    expect((c.document.elementById("c") as CharacterElement).pose.turn, 0, reason: "one step");
    expect(tester.takeException(), isNull);
  });
}
