import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';

import 'canvas_app.dart';
import 'canvas_panel_helpers.dart';
import 'canvas_sidebar_host.dart';

// panel_rows.dart is how a test presses every control of a panel: each
// control one row of a table (ControlRow), put up in the real sidebar with
// every section open, pressed or set as a person does, its field checked,
// and held to one undo step that takes the document back exactly
// (everyControl). The finders and presses a row is made of are here too.

/// panelDocument is the document a panel is put up in unless a row says
/// otherwise: long enough to key on.
const panelDocument = CanvasDocument(frames: 96, frameRate: 24);

/// showPanel puts [e] up selected in the real sidebar, on [doc] with
/// [beside] on the canvas too, every section open, and returns its
/// controller.
Future<CanvasController> showPanel(WidgetTester tester, CanvasElement e,
    {List<CanvasElement> beside = const [],
    CanvasDocument doc = panelDocument}) async {
  SharedPreferences.setMockInitialValues({});
  for (var b in beside) {
    doc = doc.addElement(b);
  }
  var c = CanvasController(doc.addElement(e));
  addTearDown(c.dispose);
  c.selectOnly(e.id);
  await pumpCanvasApp(tester, designSidebar(c), size: const Size(320, 9000));
  await openEverything(tester, find.byType(CanvasSidebarHost));
  return c;
}

/// lookSection, layoutSection, contentSection, moreSection and quickStrip
/// name the parts of a panel a control is found in.
const lookSection = "elementSection-look",
    layoutSection = "elementSection-layout",
    contentSection = "elementSection-content",
    moreSection = "elementSection-more",
    quickStrip = "quickStrip";

/// widgetIn is the one [T] in the part of the panel [section] names that
/// [test] takes.
Finder widgetIn<T extends Widget>(String section, bool Function(T) test) =>
    find.descendant(
        of: find.byKey(ValueKey(section)),
        matching: find.byWidgetPredicate((w) => w is T && test(w)));

/// numberIn, stepperIn, dropdownIn and colourIn are the control of their
/// kind labelled [label] in [section].
Finder numberIn(String section, String label) =>
    widgetIn<CanvasNumberField>(section, (w) => w.label == label);

Finder stepperIn(String section, String label) =>
    widgetIn<CanvasStepper>(section, (w) => w.label == label);

Finder dropdownIn(String section, String label) =>
    widgetIn<CanvasDropdown>(section, (w) => w.label == label);

Finder colourIn(String section, String label) =>
    widgetIn<CanvasColorButton>(section, (w) => w.label == label);

/// keyed is the widget keyed [key].
Finder keyed(String key) => find.byKey(ValueKey(key));

/// setNumber gives the number field or stepper [f] the value [v], as a typed
/// number does, and lets the panel rebuild.
Future<void> setNumber(WidgetTester tester, Finder f, double v) async {
  var w = tester.widget(f);
  if (w is CanvasNumberField) {
    w.onChanged(v);
    w.onCommit?.call();
  } else if (w is CanvasStepper) {
    w.onChanged(v);
    w.onCommit?.call();
  }
  await tester.pumpAndSettle();
}

/// pressOn taps [f], brought into view first.
Future<void> pressOn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// rangeOf is the least and most a number field or stepper offers.
(double, double) rangeOf(WidgetTester tester, Finder f) =>
    switch (tester.widget(f)) {
      CanvasNumberField w => (w.min, w.max),
      CanvasStepper w => (w.min, w.max),
      var w => throw StateError("$w is not a number"),
    };

/// ControlRow is one control of a panel: what it is, the element it is
/// shown for (with [beside] on the canvas too, on [doc]), what the editor is
/// set to before it is pressed ([ready]: a cell picked, the playhead moved),
/// how it is pressed or set, and what that must have changed. A control
/// that changes what the editor shows and not the document ([step] false:
/// looking through a camera, a metronome going) makes no step and leaves
/// the document as it was.
typedef ControlRow = ({
  String what,
  CanvasElement element,
  List<CanvasElement> beside,
  CanvasDocument doc,
  void Function(CanvasController)? ready,
  bool step,
  Future<void> Function(WidgetTester) press,
  void Function(CanvasDocument) check,
});

/// controlRow is a [ControlRow].
ControlRow controlRow(
        String what,
        CanvasElement element,
        Future<void> Function(WidgetTester) press,
        void Function(CanvasDocument) check,
        {List<CanvasElement> beside = const [],
        CanvasDocument doc = panelDocument,
        void Function(CanvasController)? ready,
        bool step = true}) =>
    (
      what: what,
      element: element,
      beside: beside,
      doc: doc,
      ready: ready,
      step: step,
      press: press,
      check: check
    );

/// everyControl tests each of [rows]: pressed, it changes what it says, in
/// one undo step that takes the document back as it was; or, where it
/// makes no step, it leaves the document as it was.
void everyControl(List<ControlRow> rows) {
  for (var row in rows) {
    var said = row.step ? "in one step" : "and the document not at all";
    testWidgets("${row.what} changes what it says, $said", (tester) async {
      var c = await showPanel(tester, row.element,
          beside: row.beside, doc: row.doc);
      if (row.ready case var ready?) {
        ready(c);
        await tester.pumpAndSettle();
      }
      var before = jsonEncode(c.document.toJson());
      await row.press(tester);
      await tester.pumpAndSettle();
      row.check(c.document);
      if (!row.step) {
        expect(c.canUndo, isFalse, reason: "no step was made");
        expect(jsonEncode(c.document.toJson()), before);
        return;
      }
      expect(c.canUndo, isTrue, reason: "a step was made");
      c.undo();
      expect(jsonEncode(c.document.toJson()), before,
          reason: "and one undo takes it all back");
      expect(c.canUndo, isFalse, reason: "it was one step");
    });
  }
}

/// rowRed and rowFade are what a colour button is given.
const rowRed = Color(0xFFE53935);
const rowFade = GradientSpec(to: Color(0xFF3D7EFF), angle: 30);

/// typedIn sets the number field or stepper [f] to [v], as a typed number
/// does.
Future<void> Function(WidgetTester) typedIn(Finder f, double v) =>
    (tester) => setNumber(tester, f, v);

/// keyTyped sets the number keyed [key] to [v].
Future<void> Function(WidgetTester) keyTyped(String key, double v) =>
    typedIn(keyed(key), v);

/// chosen picks [v] from the dropdown [f].
Future<void> Function(WidgetTester) chosen<T>(Finder f, T v) =>
    (tester) async => tester.widget<CanvasDropdown<T>>(f).onChanged(v);

/// coloured gives the colour button [f] the colour, or with [fade], the
/// fade, as its picker does.
Future<void> Function(WidgetTester) coloured(Finder f, {bool fade = false}) =>
    (tester) async {
      var w = tester.widget<CanvasColorButton>(f);
      fade ? w.onGradientChanged!(rowFade) : w.onChanged(rowRed);
    };

/// switched turns the switch [f] over.
Future<void> Function(WidgetTester) switched(Finder f) => (tester) async {
      var w = tester.widget<CanvasToggle>(f);
      w.onChanged(!w.value);
    };

/// typedText types [v] into the text field [f] and leaves it, as a person
/// does; each of [steps] first, as keystrokes on the way.
Future<void> Function(WidgetTester) typedText(Finder f, String v,
        {List<String> steps = const []}) =>
    (tester) async {
      var w = tester.widget<CanvasTextField>(f);
      for (var s in steps) {
        w.onChanged(s);
        await tester.pump();
        w = tester.widget<CanvasTextField>(f);
      }
      w.onChanged(v);
      await tester.pump();
      tester.widget<CanvasTextField>(f).onCommit?.call();
    };

/// pressed taps [f].
Future<void> Function(WidgetTester) pressed(Finder f) =>
    (tester) => pressOn(tester, f);
