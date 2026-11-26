import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';

// canvas_box_group_test.dart is the box group (box_group.dart): what is
// behind its button, and two boxes in one panel kept apart.

void main() {
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
  });

  group("a box's more-settings button", () {
    // Outside a card -- a dialog, the band over the canvas -- the group is a
    // line with a button on its end for what is set once.
    Future<void> flat(WidgetTester tester, BoxSpec box,
        {bool fill = false}) async {
      await pumpCanvasApp(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: CanvasControlScope(
                maxWidth: 400,
                child: Builder(
                    builder: (context) => boxGroup(box, (_) {}, () {}, () {},
                        fillPickedIn: fill ? context : null)),
              ),
            ),
          ),
          size: const Size(500, 800));
    }

    testWidgets("is not there when nothing is set once", (tester) async {
      // No border to inset and no paint offered: a button there opens onto
      // an empty ground.
      await flat(tester, const BoxSpec());
      expect(find.byKey(const ValueKey("more-boxBox")), findsNothing);
    });

    testWidgets("holds the border's inset where there is a border",
        (tester) async {
      await flat(tester,
          const BoxSpec(borderWidth: 2, borderColor: Color(0xFF000000)));
      await tester.tap(find.byKey(const ValueKey("more-boxBox")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("boxBorderInset")), findsOneWidget);
    });

    testWidgets("and what the box is painted with where that is offered",
        (tester) async {
      await flat(tester, const BoxSpec(), fill: true);
      await tester.tap(find.byKey(const ValueKey("more-boxBox")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("boxBoxFillKind")), findsOneWidget);
    });
  });

  group("two boxes in one panel", () {
    // A run has its own box and its buttons' box.
    Future<void> counter(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      setTestScreen(tester, const Size(300, 9000));
      CanvasSection.openAll = true;
      addTearDown(() => CanvasSection.openAll = false);
      const doc = CanvasDocument();
      var e = (newElement(ElementKind.counter, doc) as CounterElement)
          .copyWith(keyed: false, buttons: CounterButton.values);
      var c = CanvasController(doc.addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await tester.pumpAndSettle();
    }

    /// borders are the two boxes' Border fields, the counter's first.
    List<CanvasSidesField> borders(WidgetTester tester) => tester
        .widgetList<CanvasSidesField>(find.byWidgetPredicate(
            (w) => w is CanvasSidesField && w.label == "Border"))
        .toList();

    testWidgets("are found each by its own name", (tester) async {
      await counter(tester);
      var [own, buttons] = borders(tester);
      expect(own.name, isNot(buttons.name));
      expect(
          own.partKeys.toSet().intersection(buttons.partKeys.toSet()), isEmpty);
    });

    testWidgets("splitting one's border into sides leaves the other's whole",
        (tester) async {
      await counter(tester);
      var [own, buttons] = borders(tester);
      var link = find.byKey(ValueKey("${own.name}Link")).first;
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey(own.partKeys.first)), findsOneWidget,
          reason: "the counter's own border is split");
      [own, buttons] = borders(tester);
      expect(
          find.descendant(
              of: find.byWidget(buttons),
              matching: find.byKey(ValueKey(buttons.partKeys.first))),
          findsNothing,
          reason: "the buttons' border is still one number");
    });
  });
}
