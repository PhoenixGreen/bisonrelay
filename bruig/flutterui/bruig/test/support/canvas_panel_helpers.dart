import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

// canvas_panel_helpers.dart opens the parts of a sectioned settings panel a
// test needs -- each only if it is shut, since a section opened in one test
// stays open for the rest of the file (see controls.dart's section memory).

/// openSection opens the section remembered as [remember] -- "image.picture.
/// mask", say -- if it is shut.
Future<void> openSection(WidgetTester tester, String remember) async {
  if (find.byKey(ValueKey("sectionBody-$remember")).evaluate().isNotEmpty) {
    return;
  }
  var head = find.byKey(ValueKey("section-$remember"));
  // Inside a rebuilt panel's section that is shut (a picture's Mask in its
  // Content): open those until it shows.
  if (head.evaluate().isEmpty) {
    for (var top in find.byType(CanvasSection).evaluate().toList()) {
      var w = top.widget as CanvasSection;
      if (find
          .byKey(ValueKey("sectionBody-${w.remember}"))
          .evaluate()
          .isNotEmpty) {
        continue;
      }
      var shut = find.byKey(ValueKey("section-${w.remember}"));
      if (shut.evaluate().isEmpty) continue;
      await tester.ensureVisible(shut);
      await tester.tap(shut);
      await tester.pumpAndSettle();
      if (head.evaluate().isNotEmpty) break;
    }
    // Open already, once what it is in is.
    if (find.byKey(ValueKey("sectionBody-$remember")).evaluate().isNotEmpty) {
      return;
    }
  }
  await tester.ensureVisible(head);
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// openLayerList opens a picture's layers from the strip into the list.
Future<void> openLayerList(WidgetTester tester) async {
  if (find.byKey(const ValueKey("imageLayersRows")).evaluate().isNotEmpty) {
    return;
  }
  var head = find.byKey(const ValueKey("imageLayersOpen"));
  await tester.ensureVisible(head);
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// addLayer presses the Add tile [key] -- "imageAddFill", say -- opening the
/// Add tiles first.
Future<void> addLayer(WidgetTester tester, String key) async {
  if (find.byKey(const ValueKey("imageAddTiles")).evaluate().isEmpty) {
    var add = find.byKey(const ValueKey("imageLayersAdd"));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }
  var tile = find.byKey(ValueKey(key));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// typeNumber types [text] into the stepper [key] -- "elementX", say -- the
/// way a person does: a double-click on the number, the digits, Return.
Future<void> typeNumber(WidgetTester tester, String key, String text) =>
    typeInto(tester, find.byKey(ValueKey(key)), text);

/// typeInto types [text] into the stepper found by [field] -- or the number
/// field drawn as one -- for those with no key of their own.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  var number = find.descendant(
      of: field,
      matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onDoubleTap != null));
  await tester.ensureVisible(number);
  await tester.pumpAndSettle();
  await tester.tap(number);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(number);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.descendant(of: field, matching: find.byType(EditableText)), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// openTiles opens the folding tiles remembered as [name] -- "image.tiles.
/// filter", say -- into their grid, if they are shut.
Future<void> openTiles(WidgetTester tester, String name) async {
  if (find.byKey(ValueKey("tilesStrip-$name")).evaluate().isEmpty) return;
  var head = find.byKey(ValueKey("tilesFold-$name"));
  await tester.ensureVisible(head);
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// enterValue types [text] into [field] whatever it is drawn as: straight
/// into a text field, or -- a number in a card, drawn as a stepper -- the
/// way typeInto does.
Future<void> enterValue(WidgetTester tester, Finder field, String text) async {
  var editable = find.descendant(
      of: field, matching: find.byType(EditableText), matchRoot: true);
  if (editable.evaluate().isNotEmpty) {
    await tester.enterText(field, text);
    return;
  }
  await typeInto(tester, field, text);
}

/// openFold opens the folding card an expander is drawn as in a section --
/// remembered as [remember] -- unless [shows], something inside it, is
/// already there.
Future<void> openFold(WidgetTester tester, String remember,
    {required Finder shows}) async {
  if (shows.evaluate().isNotEmpty) return;
  var head = find.byKey(ValueKey("expander-$remember"));
  await tester.ensureVisible(head);
  await tester.pumpAndSettle();
  await tester.tap(head);
  await tester.pumpAndSettle();
}

/// openEverything opens every card, folding group and "more" group under
/// [root] that is shut, and what that shows, until nothing more opens.
Future<void> openEverything(WidgetTester tester, Finder root) async {
  for (var round = 0; round < 12; round++) {
    var presses = <VoidCallback>[];
    for (var el in find
        .descendant(
            of: root,
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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
