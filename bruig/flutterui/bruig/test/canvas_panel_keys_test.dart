import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/canvas_sidebar_host.dart';
import 'support/element_samples.dart';
import 'support/kept_lists.dart';

// canvas_panel_keys_test.dart is what every kind's settings show, in the real
// sidebar at the width it opens at, with every section, card and "more"
// group open: every key in order and every piece of text in order, for each
// kind as first added and as filled (element_samples.dart), and for the few
// places that the place-and-size group shows something of its own (a page
// number, a Camera's depth, several page shapes, words on a line) and
// for a panel with two boxes.
//
// It is how a change to how panels are built is shown to change nothing a
// person sees. Set PANEL_KEYS to a folder and run this file on the code as
// it is: each state's lists are written there. Make the change and run it
// again: a state whose lists differ fails, showing both where they part.
// Without PANEL_KEYS each state is still mounted and nothing is kept.
// A text's own states are canvas_text_panel_keys_test.dart's.

const _screen = Size(300, 9000);

/// _State is one element on the canvas it is on, selected.
typedef _State = ({String name, CanvasDocument document, String id});

const _doc = CanvasDocument(frames: 96, frameRate: 24);

List<_State> _states() {
  _State alone(String name, CanvasElement e) =>
      (name: name, document: _doc.addElement(e), id: e.id);
  var counter = newElement(ElementKind.counter, _doc) as CounterElement;
  var text = newElement(ElementKind.text, _doc) as TextElement;
  const line = LineElement(
      ElementBase(id: "line", x: 100, y: 400, width: 600, height: 10));
  const camera = CameraElement(ElementBase(id: "camera"));
  return [
    for (var (name, e) in [...elementSamples(), ...filledSamples()])
      // A 3D character's panel waits on its 3D scene, which a test cannot
      // build.
      if (e.kind != ElementKind.character3d) alone(name, e),
    (
      name: "Counter, in a document of pages",
      document:
          const CanvasDocument(kind: CanvasKind.pages).addElement(counter),
      id: counter.id,
    ),
    (
      name: "Counter, the page number",
      document: const CanvasDocument(kind: CanvasKind.pages)
          .addElement(counter.copyWith(source: CounterSource.page)),
      id: counter.id,
    ),
    // Two boxes in one panel: its own and its buttons'.
    alone("Counter, with buttons",
        counter.copyWith(buttons: CounterButton.values)),
    (
      name: "Text, with a Camera, on two page shapes",
      document: const CanvasDocument(targets: ["feedAd", "wide"])
          .addElement(camera)
          .addElement(text),
      id: text.id,
    ),
    (
      name: "Text, its own on this page shape",
      document: const CanvasDocument(targets: ["feedAd", "wide"])
          .addElement(text.withBase(ownDesign: true)),
      id: text.id,
    ),
    (
      name: "Text, on a line",
      document: _doc.addElement(line).addElement(
          text.copyWith(curve: const TextOnCurve(elementId: "line"))),
      id: text.id,
    ),
  ];
}

/// _openEverything opens every card, folding group and "more" group in the
/// sidebar that is shut, and what that shows, until nothing more opens.
Future<void> _openEverything(WidgetTester tester) async {
  for (var round = 0; round < 12; round++) {
    var presses = <VoidCallback>[];
    for (var el in find
        .descendant(
            of: find.byType(CanvasSidebarHost),
            matching: find.byWidgetPredicate((w) =>
                w is CanvasMoreGroup ||
                (w is CanvasExpander && !w.flat) ||
                (w is CanvasControlGroup &&
                    w.folded == true &&
                    w.onFold != null)))
        .evaluate()) {
      var w = el.widget;
      if (w is CanvasControlGroup) {
        presses.add(w.onFold!);
      } else if (w is CanvasMoreGroup) {
        var button = _first<CanvasIconButton>(
            el,
            (b) =>
                b.key == ValueKey("more-${w.remember ?? w.label}") &&
                !b.active);
        if (button?.onPressed case var press?) presses.add(press);
      } else if (_expanderShut(el)) {
        if (_first<InkWell>(el, (_) => true)?.onTap case var press?) {
          presses.add(press);
        }
      }
    }
    if (presses.isEmpty) return;
    for (var press in presses) {
      press();
    }
    await _settle(tester);
  }
  fail("the sidebar was still opening after twelve rounds");
}

/// _expanderShut is whether the expander at [el] is shut: its chevron is
/// unturned in a card, and points right outside one.
bool _expanderShut(Element el) {
  var turned = _first<AnimatedRotation>(el, (_) => true);
  if (turned != null) return turned.turns == 0;
  var icon = _first<Icon>(el, (_) => true);
  return icon?.icon == Icons.chevron_right;
}

/// _first is the first widget of type [T] under [el] that [test] takes.
T? _first<T extends Widget>(Element el, bool Function(T) test) {
  T? found;
  void visit(Element e) {
    if (found != null) return;
    var w = e.widget;
    if (w is T && test(w)) {
      found = w;
      return;
    }
    e.visitChildren(visit);
  }

  el.visitChildren(visit);
  return found;
}

/// _steadyIds is [keys] with the ids made fresh each run (newElementId's:
/// the element's own, a Layout's cells) said the same way every run: the
/// element's as `<id>`, the others numbered in the order they are met.
List<String> _steadyIds(List<String> keys, String id) {
  var fresh =
      RegExp(r"(?<![A-Za-z0-9])e[0-9a-z]{1,4}_[0-9a-z]{1,4}(?![0-9a-z])");
  var named = <String, String>{id: "<id>"};
  return [
    for (var k in keys)
      k.replaceAllMapped(fresh, (m) {
        var seen = m[0]!;
        return named.putIfAbsent(seen, () => "<id${named.length}>");
      }),
  ];
}

/// _settle lets what was opened lay out, its chevrons turn and anything read
/// from disk arrive, without waiting on a panel that never stops moving.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Each state from a panel as a new run has it, so that what the one
  // before opened does not show in the next, whichever runs alone.
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
    CanvasSection.openAll = true;
  });
  tearDownAll(() => CanvasSection.openAll = false);

  for (var state in _states()) {
    testWidgets("${state.name}: what its settings show", (tester) async {
      SharedPreferences.setMockInitialValues({});
      setTestScreen(tester, _screen);
      var c = CanvasController(state.document);
      addTearDown(c.dispose);
      c.selectOnly(state.id);
      await tester.pumpWidget(canvasApp(designSidebar(c)));
      await _settle(tester);
      await _openEverything(tester);

      var (shown, words) = shownUnder(tester, find.byType(CanvasSidebarHost));
      expect(shown, isNotEmpty, reason: state.name);
      var keys = _steadyIds(shown, state.id);
      keepOrCompareLines("PANEL_KEYS", state.name, "keys", keys);
      keepOrCompareLines("PANEL_KEYS", state.name, "words", words);
    });
  }
}
