import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// panel_stack_fit_test.dart is a sidebar holding what has been opened in it.
//
// Every open panel used to be given the height it was last dragged to, and
// the last one whatever was left over -- which is nothing once the others
// have taken more than the sidebar has. Reported from the canvas Design
// sidebar with three panels open: the bottom one was pushed off the screen
// and Flutter drew its overflow stripe across it.

Widget _stack(List<String> ids, {double bodyHeight = 400}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PanelStack(
            storageKey: "fitTest",
            panels: [
              for (var id in ids)
                StackPanel(
                  id: id,
                  label: id,
                  icon: Icons.layers,
                  body: SizedBox(height: bodyHeight, child: Text("body $id")),
                ),
            ],
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("three open panels fit the sidebar they are in", (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_stack(["scenes", "layers", "settings"]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: "nothing overflowed");
    // And the last panel is on the screen, not below it.
    var last = tester.getRect(find.text("body settings"));
    expect(last.bottom, lessThanOrEqualTo(700 + 0.5),
        reason: "the bottom panel is inside the sidebar");
  });

  testWidgets("panels dragged taller than the sidebar are reined in",
      (tester) async {
    // The reported case: the boundaries had been dragged, so two panels
    // between them asked for more than the whole sidebar and the third was
    // pushed off the bottom.
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_stack(["scenes", "layers", "settings"]));
    await tester.pumpAndSettle();

    // Drag each boundary down, which grows the panel above it.
    for (var below in ["layers", "settings"]) {
      await tester.drag(
          find.byKey(ValueKey("panelDivider:$below")), const Offset(0, 260));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull, reason: "nothing overflowed");
    var last = tester.getRect(find.text("body settings"));
    expect(last.height, greaterThanOrEqualTo(79),
        reason: "the bottom panel keeps a body to be seen in");
    expect(last.bottom, lessThanOrEqualTo(700 + 0.5));
  });

  testWidgets("and where they cannot, the stack scrolls instead",
      (tester) async {
    // Six panels at eighty pixels each is more than a short sidebar holds.
    // Shrinking them further would make all six useless to save the last, so
    // they keep a usable height and the column scrolls.
    tester.view.physicalSize = const Size(400, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _stack(["a", "b", "c", "d", "e", "f"], bodyHeight: 200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: "nothing overflowed");
    expect(find.byKey(const ValueKey("panelStackScroll")), findsOneWidget);
  });
}
