import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_counter_styles_test.dart is a counter's figures and words set in
// the document's named text styles, so a video's thirty counters change
// face together -- which a text could do and a counter could not.

const _figures = TextSpec(fontFamily: "RobotoMono", fontSize: 96, weight: 700);
const _labels = TextSpec(fontFamily: "Inter", fontSize: 18, weight: 600);

CounterElement _counter(String id) =>
    CounterElement(ElementBase(id: id), from: 0, to: 300);

CanvasController _two() => CanvasController(CanvasDocument(
        textStyles: const [
          NamedTextStyle("Figures", _figures),
          NamedTextStyle("Labels", _labels),
        ])
        .addElement(_counter("a"))
        .addElement(_counter("b"))
        .addElement(TextElement(const ElementBase(id: "t"),
            text: "label", textSpec: _labels, style: "Labels")));

CounterElement _get(CanvasController c, String id) =>
    c.document.elements.firstWhere((e) => e.id == id) as CounterElement;

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test("the style names are saved with the counter", () {
    var e = _counter("a").copyWith(numberStyle: "Figures", wordStyle: "Labels");
    var back = CounterElement.fromJson(e.toJson(), const ElementBase(id: "a"));
    expect(back.numberStyle, "Figures");
    expect(back.wordStyle, "Labels");
    expect(_counter("a").toJson().containsKey("numberStyle"), isFalse);
  });

  test("set in a style, the figures change when it does", () {
    var c = _two();
    addTearDown(c.dispose);
    c.useCounterStyle("a", "Figures");
    c.useCounterStyle("b", "Figures");
    c.useCounterStyle("a", "Labels", words: true);
    expect(_get(c, "a").numberSpec.fontSize, 96, reason: "takes the style");

    c.updateTextStyle("Figures", _figures.copyWith(fontSize: 120));
    expect(_get(c, "a").numberSpec.fontSize, 120);
    expect(_get(c, "b").numberSpec.fontSize, 120, reason: "both of them");

    c.updateTextStyle("Labels", _labels.copyWith(fontSize: 22));
    expect(_get(c, "a").affixSpec.fontSize, 22,
        reason: "the words follow the style a text is in, too");
    expect((c.document.elements.last as TextElement).textSpec.fontSize, 22);
  });

  test("renamed or forgotten, the counters go with it", () {
    var c = _two();
    addTearDown(c.dispose);
    c.useCounterStyle("a", "Figures");
    c.renameTextStyle("Figures", "Numbers");
    expect(_get(c, "a").numberStyle, "Numbers");
    c.removeTextStyle("Numbers");
    expect(_get(c, "a").numberStyle, "");
    expect(_get(c, "a").numberSpec.fontSize, 96, reason: "keeps its type");
  });

  testWidgets("the counter's Type section sets its figures in a style",
      (tester) async {
    var c = _two();
    addTearDown(c.dispose);
    c.selectOnly("a");
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child:
          MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();

    // The Number and Words type expanders remember being open for the rest
    // of the run, so each is opened only if it is shut.
    Future<void> open(String label, String inside) async {
      if (find.byKey(ValueKey(inside)).evaluate().isNotEmpty) return;
      var heading = find.text(label).first;
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
    }

    await open("Number type", "counterNumberStylePick");
    var pick = find.byKey(const ValueKey("counterNumberStylePick"));
    expect(pick, findsOneWidget);
    tester.widget<CanvasDropdown<String>>(pick).onChanged("Figures");
    await tester.pumpAndSettle();
    expect(_get(c, "a").numberStyle, "Figures");
    expect(_get(c, "a").numberSpec.fontFamily, "RobotoMono");

    // And its words' type made a style of its own, linked straight away.
    await open("Words type", "counterWordsStyleSave");
    var save = find.byKey(const ValueKey("counterWordsStyleSave"));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(c.textStyles.length, 3);
    expect(_get(c, "a").wordStyle, c.textStyles.last.name);
  });
}
