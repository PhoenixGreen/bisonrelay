import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraFraming, cameraOf;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';

import 'support/canvas_app.dart';
import 'support/panel_rows.dart';

// canvas_button_counter_layout_camera_metronome_panels_test.dart is every
// control of a button's, a counter's, a Layout's, a Camera's and a
// metronome's panels, used in the real sidebar: each pressed or set as a
// person does, what it says checked, and the change one undo step that one
// undo takes back exactly (a control that changes only what the editor
// shows makes none). A new control is one row. The type kit and the box
// group are each pressed once a panel by a control of theirs: their own
// tests press the rest.

void main() {
  setUp(() {
    forgetPanelsForTest();
    forgetSectionsForTest();
    CanvasSection.openAll = true;
  });
  tearDownAll(() => CanvasSection.openAll = false);

  group("a button's panel", () => everyControl(_buttonRows()));
  group("a counter's panel", () => everyControl(_counterRows()));
  group("a Layout's panel", () => everyControl(_layoutRows()));
  group("a Camera's panel", () => everyControl(_cameraRows()));
  group("a metronome's panel", () => everyControl(_metronomeRows()));

  // What a Layout's cells offer is what a cell draws: one border all
  // round, one radius, its fill and paint, and nothing inside it.
  testWidgets("a Layout's cells offer no split sides, padding or inset",
      (tester) async {
    var c = await showPanel(tester, _ownStyled);
    c.pickLayoutCell("L", "a");
    await tester.pumpAndSettle();
    for (var box in ["layoutCellsBox", "layoutCellStyleBox"]) {
      expect(keyed("${box}Border"), findsOneWidget, reason: box);
      expect(keyed("${box}Radius"), findsOneWidget, reason: box);
      for (var gone in ["BorderLink", "RadiusLink", "Padding", "PaddingLink"]) {
        expect(keyed("$box$gone"), findsNothing, reason: "$box$gone");
      }
    }
    expect(keyed("layoutCellsBorderInset"), findsNothing);
    expect(keyed("layoutCellStyleBorderInset"), findsNothing);
  });

  // A cell saved or received with one side's border wider than the rest is
  // drawn at the widest all round, and its one Border says so.
  testWidgets("a cell's one Border shows the width it is drawn at",
      (tester) async {
    await showPanel(
        tester,
        _panels.copyWith(
            cellStyle: const BoxSpec(
                bwT: 9, borderColor: Color(0xFF000000), padding: 0)));
    expect(
        tester.widget<CanvasStepper>(keyed("layoutCellsBoxBorder")).value, 9);
  });

  // The panel's ranges are the model's.
  testWidgets("a Layout's gutters and cut offer the model's range",
      (tester) async {
    var c = await showPanel(tester, _panels);
    c.pickLayoutCell("L", "a");
    await tester.pumpAndSettle();
    for (var key in [
      "layoutGutter",
      "layoutRowGutter",
      "layoutMargin",
      "layoutCutGutter"
    ]) {
      expect(rangeOf(tester, keyed(key)), (0.0, LayoutRange.maxGutter),
          reason: key);
    }
    expect(rangeOf(tester, keyed("layoutCutAt")),
        (LayoutRange.minCutAt * 100, LayoutRange.maxCutAt * 100));
    expect(rangeOf(tester, keyed("layoutCutTilt")),
        (-LayoutRange.maxTilt, LayoutRange.maxTilt));
  });

  // A Layout's panel with a cell picked, which has its own look, and a
  // button's with its hover colours, at the text sizes people use.
  for (var scale in const [0.65, 1.0, 1.25, 1.5]) {
    testWidgets("a Layout's and a button's panels fit at $scale",
        (tester) async {
      setTestTextScale(tester, scale);
      var c = await showPanel(tester, _ownStyled);
      c.pickLayoutCell("L", "a");
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await showPanel(tester, _button);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a Camera's blur offers the model's range", (tester) async {
    await showPanel(tester, _camera);
    expect(rangeOf(tester, keyed("cameraBlur")), (0.0, CameraElement.maxBlur));
  });

  group("of two Cameras shown", () {
    testWidgets("the one that does not frame the scene names the one that does",
        (tester) async {
      await showPanel(tester, _close, beside: [_wide]);
      expect(
          find.text("Wide frames this scene. This one is not in use while it "
              "is shown."),
          findsOneWidget);
      expect(keyed(_useThis), findsOneWidget);
    });

    testWidgets("the one that frames the scene says nothing of the other",
        (tester) async {
      var c = await showPanel(tester, _close, beside: [_wide]);
      c.selectOnly(_wide.id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("cameraLook")), findsOneWidget,
          reason: "its own panel is up");
      expect(keyed("cameraNotInUse"), findsNothing);
      expect(keyed(_useThis), findsNothing);
    });

    testWidgets("one hidden is not in the way of the other", (tester) async {
      await showPanel(tester, _close,
          beside: [_wide.withBase(visible: false) as CameraElement]);
      expect(keyed("cameraNotInUse"), findsNothing);
    });

    // Made to frame it by going just ahead of the other in the scene's
    // order: a Camera is never drawn, so nothing on the page moves, and the
    // other stays on the canvas as it was.
    testWidgets("made the one in use, it goes just ahead of the other",
        (tester) async {
      var shape = newElement(ElementKind.shape, panelDocument);
      var c = await showPanel(tester, _close, beside: [_wide, shape]);
      expect([for (var e in c.document.elements) e.id],
          [_wide.id, shape.id, _close.id]);
      await pressOn(tester, keyed(_useThis));
      expect(cameraOf(c.document)?.id, _close.id);
      expect([for (var e in c.document.elements) e.id],
          [_close.id, _wide.id, shape.id]);
      expect(c.document.elementById(_wide.id)!.visible, isTrue,
          reason: "the other is left shown");
      expect(keyed("cameraNotInUse"), findsNothing);
      c.undo();
      expect(cameraOf(c.document)?.id, _wide.id, reason: "one undo step");
    });

    for (var scale in const [0.65, 1.0, 1.25, 1.5]) {
      testWidgets("the panel of the one not in use fits at $scale",
          (tester) async {
        setTestTextScale(tester, scale);
        await showPanel(tester, _close, beside: [_wide]);
        expect(keyed("cameraNotInUse"), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

T _only<T>(CanvasDocument d) => d.elements.whereType<T>().single;

/// _inGroup is the control keyed [key] inside the group keyed [group]: the
/// type kit's controls carry the same keys wherever they are.
Finder _inGroup(String group, String key) =>
    find.descendant(of: keyed(group), matching: keyed(key)).first;

/// _chosenAt picks the [i]th of the dropdown [f]'s options.
Future<void> Function(WidgetTester) _chosenAt(Finder f, int i) =>
    (tester) async {
      var w = tester.widget<CanvasDropdown<String>>(f);
      w.onChanged(w.options[i].$1);
    };

// ---- A button -------------------------------------------------------------

final _button = (newElement(ElementKind.button, panelDocument) as ButtonElement)
    .copyWith(label: "Go");

ButtonElement _withAction(ButtonAction a) => _button.copyWith(action: a);

List<ControlRow> _buttonRows() {
  ButtonElement b(CanvasDocument d) => _only<ButtonElement>(d);
  var audio = newElement(ElementKind.audio, panelDocument) as AudioElement;
  var shape = newElement(ElementKind.shape, panelDocument);
  const row = controlRow;
  return [
    row(
        "a button's quick Label",
        _button,
        typedText(keyed("quickButtonLabel"), "Hello"),
        (d) => expect(b(d).label, "Hello")),
    row("a button's quick Fill", _button, coloured(keyed("quickButtonFill")),
        (d) => expect(b(d).box.fill, rowRed)),
    row(
        "a button's quick Does",
        _button,
        chosen(keyed("quickButtonDoes"), ButtonActionKind.play),
        (d) => expect(b(d).action.kind, ButtonActionKind.play)),
    row("a button's quick Text", _button, coloured(keyed("quickButtonText")),
        (d) => expect(b(d).textSpec.color, rowRed)),
    row("a button's Label", _button, typedText(keyed("buttonLabel"), "Hi"),
        (d) => expect(b(d).label, "Hi")),
    row(
        "a button's Does",
        _button,
        chosen(keyed("button-does"), ButtonActionKind.restart),
        (d) => expect(b(d).action.kind, ButtonActionKind.restart)),
    row("a button's Frame", _button, keyTyped("button-frame", 12),
        (d) => expect(b(d).action.frame, 12)),
    row(
        "a button's Sound or video",
        _withAction(const ButtonAction(kind: ButtonActionKind.toggleSound)),
        chosen(keyed("buttonSound"), audio.id),
        (d) => expect(b(d).action.elementId, audio.id),
        beside: [audio]),
    row(
        "a button's Element",
        _withAction(const ButtonAction(kind: ButtonActionKind.toggleElement)),
        chosen(keyed("button-element"), shape.id),
        (d) => expect(b(d).action.elementId, shape.id),
        beside: [shape]),
    row(
        "a button's Scene",
        _withAction(const ButtonAction(kind: ButtonActionKind.goToScene)),
        _chosenAt(keyed("buttonScene"), 1),
        (d) => expect(b(d).action.elementId, isNotEmpty)),
    row(
        "a button's Link",
        _withAction(const ButtonAction(kind: ButtonActionKind.openLink)),
        typedText(keyed("button-link"), "https://example.org"),
        (d) => expect(b(d).action.url, "https://example.org")),
    row(
        "a button's label type",
        _button,
        typedIn(_inGroup("buttonLabelType", "typeSize"), 31),
        (d) => expect(b(d).textSpec.fontSize, 31)),
    row("a button's box Fill", _button, coloured(colourIn(lookSection, "Fill")),
        (d) => expect(b(d).box.fill, rowRed)),
    row(
        "a button's box Border colour",
        _button,
        coloured(colourIn(lookSection, "Border colour")),
        (d) => expect(b(d).box.borderColor, rowRed)),
    row("a button's box Border", _button, keyTyped("buttonBoxBorder", 3),
        (d) => expect(b(d).box.borders.top, 3)),
    row("a button's box Corners", _button, keyTyped("buttonBoxRadius", 7),
        (d) => expect(b(d).box.corners.topLeft, 7)),
    row("a button's box Padding", _button, keyTyped("buttonBoxPadding", 5),
        (d) => expect(b(d).box.pad.top, 5)),
    row(
        "a button's box Painted with",
        _button,
        chosen(keyed("buttonBoxFillKind"), TextFillKind.pattern),
        (d) => expect(b(d).box.painted.kind, TextFillKind.pattern)),
    row("a button's Hover fill", _button, coloured(keyed("buttonHoverFill")),
        (d) => expect(b(d).hoverFill, rowRed)),
    row("a button's Hover text", _button, coloured(keyed("buttonHoverText")),
        (d) => expect(b(d).hoverTextColor, rowRed)),
  ];
}

// ---- A counter ------------------------------------------------------------

final _counter =
    newElement(ElementKind.counter, panelDocument) as CounterElement;
final _run = _counter.copyWith(keyed: false, source: CounterSource.run);

/// _keyedCount is a keyed counter counting 0 to 100 over the canvas, its
/// first key held.
final _keyedCount = _counter.withBase(
    track: ElementTrack(const [
  Keyframe(
      frame: 0,
      easing: KeyframeEasing.hold,
      values: {KeyframeChannel.count: 0}),
  Keyframe(frame: 95, values: {KeyframeChannel.count: 100}),
])) as CounterElement;

const _styles = [NamedTextStyle("Big", TextSpec(fontSize: 90))];

List<ControlRow> _counterRows() {
  CounterElement c(CanvasDocument d) => _only<CounterElement>(d);
  Keyframe? key0(CanvasDocument d) => c(d).track?.keyAt(0);
  var games = const CanvasDocument(
      frames: 96,
      frameRate: 24,
      game: true,
      counts: [GameCount("coins", "Coins"), GameCount("lives", "Lives")]);
  const pages = CanvasDocument(kind: CanvasKind.pages);
  const styled = CanvasDocument(frames: 96, frameRate: 24, textStyles: _styles);
  var loose = _counter.copyWith(loose: true, before: "£", after: "kg");
  var withButtons = _run.copyWith(buttons: const [CounterButton.startStop]);
  var looseButtons = withButtons.copyWith(looseButtons: true);
  var bordered = _counter.copyWith(
      box: const BoxSpec(
          borderWidth: 2, borderColor: Color(0xFF000000), padding: 16));
  const row = controlRow;
  return [
    // Its ends and how it is written.
    row("a counter's quick From", _counter, keyTyped("quickCounterFrom", 5),
        (d) => expect(c(d).from, 5)),
    row("a counter's quick To", _counter, keyTyped("quickCounterTo", 50),
        (d) => expect(c(d).to, 50)),
    row("a counter's From", _counter, keyTyped("counterFrom", 6),
        (d) => expect(c(d).from, 6)),
    row("a counter's To", _counter, keyTyped("counterTo", 60),
        (d) => expect(c(d).to, 60)),
    row(
        "a counter's quick Colour",
        _counter,
        coloured(keyed("quickCounterColour")),
        (d) => expect(c(d).numberSpec.color, rowRed)),
    row(
        "a counter's quick Written",
        _counter,
        chosen(keyed("quickCounterWritten"), CounterSeparator.space),
        (d) => expect(c(d).separator, CounterSeparator.space)),
    row(
        "a counter's Written",
        _counter,
        chosen(keyed("counterSeparator"), CounterSeparator.dot),
        (d) => expect(c(d).separator, CounterSeparator.dot)),
    row("a counter's Decimals", _counter, keyTyped("counterDecimals", 2),
        (d) => expect(c(d).decimals, 2)),
    row("a counter's Before", _counter, typedText(keyed("counterBefore"), "£"),
        (d) => expect(c(d).before, "£")),
    row("a counter's After", _counter, typedText(keyed("counterAfter"), "kg"),
        (d) => expect(c(d).after, "kg")),

    // Where its number comes from.
    row("a counter's Keyframes", _counter, switched(keyed("counterKeyed")),
        (d) => expect(c(d).mode, CounterMode.run)),
    row(
        "a run's Shows",
        _run,
        chosen(keyed("counterSource"), CounterSource.clock),
        (d) => expect(c(d).mode, CounterMode.clock)),
    row(
        "a game count's Count",
        _counter.copyWith(
            keyed: false, source: CounterSource.game, gameCount: "coins"),
        chosen(keyed("counterGameCount"), "lives"),
        (d) => expect(c(d).gameCount, "lives"),
        doc: games),
    row("a run's Per second", _run, keyTyped("counterRate", 3),
        (d) => expect(c(d).rate, 3)),
    row("a run's Loop", _run, switched(keyed("counterLoop")),
        (d) => expect(c(d).loop, !_run.loop)),
    row("a run's Start running", _run, switched(keyed("counterRunning")),
        (d) => expect(c(d).running, !_run.running)),
    row(
        "a counter's Page number",
        _counter,
        switched(keyed("counterIsPageNumber")),
        (d) => expect(c(d).mode, CounterMode.page),
        doc: pages),
    row(
        "a page number's Mirror on left pages",
        _counter.copyWith(source: CounterSource.page),
        switched(keyed("counterMirrored")),
        (d) => expect(c(d).mirrored, isTrue),
        doc: pages),

    // A keyed count's points, at the playhead on frame 0.
    row(
        "a keyed count's Start here",
        _counter,
        pressed(keyed("counterPinFrom")),
        (d) => expect(key0(d)?.values[KeyframeChannel.count], _counter.from)),
    row("a keyed count's Finish here", _counter, pressed(keyed("counterPinTo")),
        (d) => expect(key0(d)?.values[KeyframeChannel.count], _counter.to)),
    row(
        "a keyed count's Add a point",
        _counter,
        pressed(keyed("counterAddPoint")),
        (d) => expect(key0(d)?.values[KeyframeChannel.count], _counter.from)),
    row(
        "a keyed count's Value here",
        _counter,
        keyTyped("counterPointValue", 42),
        (d) => expect(key0(d)?.values[KeyframeChannel.count], 42)),
    row(
        "a keyed count's Easing",
        _keyedCount,
        chosen(keyed("counterEasing"), KeyframeEasing.linear),
        (d) => expect(key0(d)?.easing, KeyframeEasing.linear)),
    row("a keyed count's easing for every point", _keyedCount,
        pressed(keyed("counterEasingAll")), (d) {
      for (var k in c(d).track!.keys) {
        expect(k.easing, KeyframeEasing.hold);
      }
    }),
    row("a keyed count's ◆", _keyedCount, pressed(keyed("counterKeyDot")),
        (d) => expect(key0(d)?.values[KeyframeChannel.count], isNull)),

    // Its type and styles.
    row(
        "a counter's number type",
        _counter,
        typedIn(_inGroup("counterNumberType", "typeSize"), 77),
        (d) => expect(c(d).numberSpec.fontSize, 77)),
    row(
        "a counter's words type",
        _counter,
        typedIn(_inGroup("counterWordsType", "typeSize"), 21),
        (d) => expect(c(d).affixSpec.fontSize, 21)),
    row("a counter's Words gap", _counter, keyTyped("counterGap", 0.5),
        (d) => expect(c(d).gap, 0.5)),
    for (var words in [false, true]) ...[
      row(
          "a counter's ${words ? "words'" : "number's"} style",
          _counter,
          chosen(keyed("counter${words ? "Words" : "Number"}StylePick"), "Big"),
          (d) => expect(words ? c(d).wordStyle : c(d).numberStyle, "Big"),
          doc: styled),
      row("a counter's ${words ? "words'" : "number's"} style made", _counter,
          pressed(keyed("counter${words ? "Words" : "Number"}StyleSave")), (d) {
        expect(d.textStyles, hasLength(1));
        expect(words ? c(d).wordStyle : c(d).numberStyle,
            d.textStyles.single.name);
      }),
      row(
          "a counter's ${words ? "words'" : "number's"} style changed to it",
          words
              ? _counter.copyWith(wordStyle: "Big")
              : _counter.copyWith(numberStyle: "Big"),
          pressed(keyed("counter${words ? "Words" : "Number"}StyleUpdate")),
          (d) => expect(d.textStyles.single.spec,
              words ? _counter.affixSpec : _counter.numberSpec),
          doc: styled),
    ],

    // Its words placed freely.
    row("a counter's Place freely", _counter, switched(keyed("counterLoose")),
        (d) => expect(c(d).loose, isTrue)),
    for (var (key, at) in [
      ("counterBeforeAtX", (CounterElement e) => e.beforeAt.dx),
      ("counterBeforeAtY", (CounterElement e) => e.beforeAt.dy),
      ("counterAfterAtX", (CounterElement e) => e.afterAt.dx),
      ("counterAfterAtY", (CounterElement e) => e.afterAt.dy),
    ])
      row("a counter's $key", loose, keyTyped(key, 0.3),
          (d) => expect(at(c(d)), 0.3)),

    // Its box.
    row(
        "a counter's box Fill",
        _counter,
        coloured(colourIn(lookSection, "Fill")),
        (d) => expect(c(d).box.fill, rowRed)),
    row(
        "a counter's box Border colour",
        _counter,
        coloured(colourIn(lookSection, "Border colour")),
        (d) => expect(c(d).box.borderColor, rowRed)),
    row("a counter's box Border", _counter, keyTyped("counterBoxBorder", 3),
        (d) => expect(c(d).box.borders.top, 3)),
    row("a counter's box Corners", _counter, keyTyped("counterBoxRadius", 6),
        (d) => expect(c(d).box.corners.topLeft, 6)),
    row("a counter's box Padding", _counter, keyTyped("counterBoxPadding", 4),
        (d) => expect(c(d).box.pad.top, 4)),
    row(
        "a counter's box Painted with",
        _counter,
        chosen(keyed("counterBoxFillKind"), TextFillKind.pattern),
        (d) => expect(c(d).box.painted.kind, TextFillKind.pattern)),
    row("a counter's box Inset", bordered, keyTyped("counterBorderInset", 3),
        (d) => expect(c(d).box.borderInset, 3)),
    row("a counter's Shrink to fit", _counter, switched(keyed("counterFit")),
        (d) => expect(c(d).fit, !_counter.fit)),

    // A run's buttons.
    for (var button in CounterButton.values)
      row(
          "a run's ${button.label} button",
          withButtons,
          switched(keyed("counterButton-${button.name}")),
          (d) => expect(c(d).buttons.contains(button),
              !withButtons.buttons.contains(button))),
    row(
        "a run's buttons placed freely",
        withButtons,
        switched(keyed("counterLooseButtons")),
        (d) => expect(c(d).looseButtons, isTrue)),
    row(
        "a run's buttons' Width",
        looseButtons,
        keyTyped("counterButtonWidth", 0.4),
        (d) => expect(c(d).buttonSize.width, 0.4)),
    row(
        "a run's buttons' Height",
        looseButtons,
        keyTyped("counterButtonHeight", 0.3),
        (d) => expect(c(d).buttonSize.height, 0.3)),
    row(
        "a run's button placed across",
        looseButtons,
        keyTyped("counterButtonAt0X", 0.2),
        (d) => expect(c(d).placedButton(0).dx, 0.2)),
    row(
        "a run's button placed down",
        looseButtons,
        keyTyped("counterButtonAt0Y", -0.2),
        (d) => expect(c(d).placedButton(0).dy, -0.2)),
    row(
        "a run's button type",
        withButtons,
        typedIn(_inGroup(moreSection, "typeSize"), 15),
        (d) => expect(c(d).buttonSpec.fontSize, 15)),
    row(
        "a run's button box Border",
        withButtons,
        keyTyped("counterButtonBoxBorder", 2),
        (d) => expect(c(d).buttonBox.borders.top, 2)),
  ];
}

// ---- A Layout -------------------------------------------------------------

const _base = ElementBase(id: "L", x: 100, y: 100, width: 600, height: 800);

/// _panels is a Layout of two Panels cells, "a" left of "b".
final _panels = LayoutElement(_base,
    root: const LayoutNode.cut(
        vertical: true, a: LayoutNode.leaf("a"), b: LayoutNode.leaf("b")),
    cells: const [LayoutCell(id: "a"), LayoutCell(id: "b")]);

final _ownStyled = _panels.withCell(const LayoutCell(
    id: "a",
    style:
        BoxSpec(borderWidth: 2, borderColor: Color(0xFF000000), padding: 0)));

final _grid = LayoutElement(_base,
    mode: LayoutMode.grid,
    cells: const [LayoutCell(id: "a"), LayoutCell(id: "b", col: 1)]);

final _free = LayoutElement(_base,
    mode: LayoutMode.free,
    cells: const [LayoutCell(id: "a"), LayoutCell(id: "b", x: 0.5)]);

void _pickA(CanvasController c) => c.pickLayoutCell("L", "a");

List<ControlRow> _layoutRows() {
  LayoutElement l(CanvasDocument d) => _only<LayoutElement>(d);
  LayoutCell cellA(CanvasDocument d) => l(d).cellById("a")!;
  LayoutNode root(CanvasDocument d) => l(d).root;
  var shape = ShapeElement(const ElementBase(
      id: "s", x: 120, y: 130, width: 50, height: 50, dock: "L:a"));
  const row = controlRow;
  return [
    row("a Layout's Start from", _panels, pressed(keyed("layoutPreset-cards")),
        (d) => expect(l(d).mode, LayoutMode.grid)),
    row("a Layout's Mode", _panels, pressed(keyed("layoutMode-free")),
        (d) => expect(l(d).mode, LayoutMode.free)),
    row("a Layout's Cell", _panels, (tester) async {
      await chosen(keyed("layoutPicked"), "a")(tester);
      await tester.pumpAndSettle();
      expect(keyed("layoutCell"), findsOneWidget, reason: "picked");
    }, (_) {}, step: false),
    row("a Panels cell's Cut down", _panels, pressed(keyed("layoutSplitDown")),
        (d) => expect(root(d).cells, hasLength(3)),
        ready: _pickA),
    row(
        "a Panels cell's Cut across",
        _panels,
        pressed(keyed("layoutSplitAcross")),
        (d) => expect(root(d).cells, hasLength(3)),
        ready: _pickA),
    row("a Grid's Add a cell", _grid, pressed(keyed("layoutAddCell")),
        (d) => expect(l(d).cells, hasLength(3))),
    row("a Free layout's Add a cell", _free, pressed(keyed("layoutAddCell")),
        (d) => expect(l(d).cells, hasLength(3))),
    row("a Panels cell merged", _panels, pressed(keyed("layoutRemoveCell")),
        (d) => expect(root(d).cells, ["b"]),
        ready: _pickA),
    row("a Free cell removed", _free, pressed(keyed("layoutRemoveCell")),
        (d) => expect(l(d).cells.map((c) => c.id), ["b"]),
        ready: _pickA),
    row(
        "a Grid's Columns typed a keystroke at a time",
        _grid,
        typedText(keyed("layoutColumns"), "1 2 3", steps: ["1", "1 2", "1 2 "]),
        (d) => expect(l(d).columns, [1, 2, 3])),
    row(
        "a Grid's Rows typed a keystroke at a time",
        _grid,
        typedText(keyed("layoutRows"), "2 1", steps: ["2", "2 "]),
        (d) => expect(l(d).rows, [2, 1])),

    // The picked cell.
    row("a cell's Name", _panels, typedText(keyed("layoutCellName"), "Hero"),
        (d) => expect(cellA(d).name, "Hero"),
        ready: _pickA),
    row("a cell's Cut at", _panels, keyTyped("layoutCutAt", 30),
        (d) => expect(root(d).at, closeTo(0.3, 1e-9)),
        ready: _pickA),
    row("a cell's cut's Tilt", _panels, keyTyped("layoutCutTilt", 12),
        (d) => expect(root(d).tilt, 12),
        ready: _pickA),
    row("a cell's cut's Its gutter", _panels, keyTyped("layoutCutGutter", 40),
        (d) => expect(cutGutter(l(d), root(d)), 40),
        ready: _pickA),
    for (var (key, at) in [
      ("Col", (LayoutCell c) => c.col),
      ("Row", (LayoutCell c) => c.row),
      ("ColSpan", (LayoutCell c) => c.colSpan),
      ("RowSpan", (LayoutCell c) => c.rowSpan),
    ])
      row("a Grid cell's $key", _grid, keyTyped("layoutCell$key", 2),
          (d) => expect(at(cellA(d)), key.endsWith("Span") ? 2 : 1),
          ready: _pickA),
    row(
        "a Free cell's Shape",
        _free,
        chosen(keyed("layoutCellShape"), LayoutCellShape.star),
        (d) => expect(cellA(d).shape, LayoutCellShape.star),
        ready: _pickA),
    row("a Free cell's Turn", _free, keyTyped("layoutCellTurn", 20),
        (d) => expect(cellA(d).turn, 20),
        ready: _pickA),
    row("a cell's Its own look", _panels, switched(keyed("layoutCellOwnStyle")),
        (d) => expect(cellA(d).style, l(d).cellStyle),
        ready: _pickA),
    row(
        "this cell's Fill",
        _ownStyled,
        coloured(colourIn(contentSection, "Fill")),
        (d) => expect(cellA(d).style!.fill, rowRed),
        ready: _pickA),
    row(
        "this cell's border Colour",
        _ownStyled,
        coloured(colourIn(contentSection, "Colour")),
        (d) => expect(cellA(d).style!.borderColor, rowRed),
        ready: _pickA),
    row(
        "this cell's Border",
        _ownStyled,
        keyTyped("layoutCellStyleBoxBorder", 5),
        (d) => expect(cellA(d).style!.borders, const Room(all: 5)),
        ready: _pickA),
    row(
        "this cell's Radius",
        _ownStyled,
        keyTyped("layoutCellStyleBoxRadius", 9),
        (d) => expect(cellA(d).style!.borderRadius, 9),
        ready: _pickA),
    row(
        "this cell's Painted with",
        _ownStyled,
        chosen(keyed("layoutCellStyleBoxFillKind"), TextFillKind.pattern),
        (d) => expect(cellA(d).style!.painted.kind, TextFillKind.pattern),
        ready: _pickA),

    // The reading order.
    row("a Layout's Set reading order", _panels, (tester) async {
      await pressOn(tester, keyed("layoutSetOrder"));
      expect(keyed("layoutOrderDone"), findsOneWidget, reason: "ordering");
    }, (_) {}, step: false),
    row(
        "a Layout's reading order Done",
        _panels,
        pressed(keyed("layoutOrderDone")),
        (d) => expect(l(d).order, ["b", "a"]), ready: (c) {
      c.beginReadingOrder(_panels);
      c.clickReadingOrder("b");
      c.clickReadingOrder("a");
    }),
    row("a Layout's reading order Cancel", _panels,
        pressed(keyed("layoutOrderCancel")), (_) {},
        step: false, ready: (c) {
      c.beginReadingOrder(_panels);
      c.clickReadingOrder("b");
    }),
    row(
        "a Layout's reading order Reset",
        _panels.copyWith(order: const ["b", "a"]),
        pressed(keyed("layoutResetOrder")),
        (d) => expect(l(d).order, isEmpty)),
    row("a cell read sooner", _panels, pressed(keyed("layoutReadUp-b")),
        (d) => expect(l(d).reading.map((c) => c.id), ["b", "a"])),
    row("a cell read later", _panels, pressed(keyed("layoutReadDown-a")),
        (d) => expect(l(d).reading.map((c) => c.id), ["b", "a"])),
    row("a cell left out", _panels, pressed(keyed("layoutReadOn-a")),
        (d) => expect(l(d).unread, ["a"])),

    // Its gutters and the cells' look.
    row("a Layout's Side by side", _panels, keyTyped("layoutGutter", 30),
        (d) => expect(l(d).gutter, 30)),
    row("a Layout's One above another", _panels,
        keyTyped("layoutRowGutter", 31), (d) => expect(l(d).rowGutter, 31)),
    row("a Layout's Margin", _panels, keyTyped("layoutMargin", 12),
        (d) => expect(l(d).margin, 12)),
    row(
        "a Layout's gutter Colour",
        _panels,
        coloured(keyed("layoutGutterColour")),
        (d) => expect(l(d).gutterColor, rowRed)),
    row(
        "a Layout's Clear gutters",
        _panels.copyWith(gutterColor: const Color(0xFFFFFFFF)),
        pressed(keyed("layoutGutterClear")),
        (d) => expect(l(d).gutterColor.a, 0)),
    row(
        "the cells' Fill",
        _panels,
        coloured(colourIn(lookSection, "Fill").last),
        (d) => expect(l(d).cellStyle.fill, rowRed)),
    row(
        "the cells' border Colour",
        _panels,
        coloured(colourIn(lookSection, "Colour").last),
        (d) => expect(l(d).cellStyle.borderColor, rowRed)),
    row("the cells' Border", _panels, keyTyped("layoutCellsBoxBorder", 6),
        (d) => expect(l(d).cellStyle.borders, const Room(all: 6))),
    row("the cells' Radius", _panels, keyTyped("layoutCellsBoxRadius", 8),
        (d) => expect(l(d).cellStyle.borderRadius, 8)),
    row(
        "the cells' Painted with",
        _panels,
        chosen(keyed("layoutCellsBoxFillKind"), TextFillKind.pattern),
        (d) => expect(l(d).cellStyle.painted.kind, TextFillKind.pattern)),

    // Docking another element in a cell, from its own Layout section.
    row(
        "a shape's In a cell",
        shape.withBase(dock: ""),
        chosen(keyed("dockCell"), "L:b"),
        (d) => expect(d.elementById("s")!.base.dock, "L:b"),
        beside: [_panels]),
    row("a docked shape's Break out", shape, switched(keyed("dockOut")),
        (d) => expect(d.elementById("s")!.base.dockOut, isTrue),
        beside: [_panels]),
    row("a docked shape's Fit to the cell", shape, pressed(keyed("dockFit")),
        (d) {
      var cell = layoutPlaceOf(_panels, _panels.bounds, "a")!.bounds;
      expect(d.elementById("s")!.bounds, cell);
    }, beside: [_panels]),
  ];
}

// ---- A Camera -------------------------------------------------------------

final _camera = newElement(ElementKind.camera, panelDocument) as CameraElement;

/// _wide and _close are two Cameras for one scene, which [_wide] frames
/// when it comes first; [_useThis] is the button that makes the other the
/// one in use.
final _wide = (newElement(ElementKind.camera, panelDocument) as CameraElement)
    .withBase(name: "Wide") as CameraElement;
final _close = (newElement(ElementKind.camera, panelDocument) as CameraElement)
    .withBase(name: "Close") as CameraElement;
const _useThis = "stateNote-Use this one";

List<ControlRow> _cameraRows() {
  CameraElement cam(CanvasDocument d) => _only<CameraElement>(d);
  double? keyedHere(CanvasDocument d, String channel) =>
      cam(d).track?.keyAt(0)?.values[channel];
  var shape = newElement(ElementKind.shape, panelDocument);
  var chart = newElement(ElementKind.chart, panelDocument) as ChartElement;
  var aimed = _camera.copyWith(aim: chart.id);
  var stage = BackgroundElement(
      const ElementBase(id: "st", width: 1280, height: 720),
      backdrop: BackdropKind.stage,
      stage: StageElement(const ElementBase(id: ""),
          camera: const StageCamera(yaw: -30, distance: 12)));
  var onStage = panelDocument.addElement(stage);
  const row = controlRow;
  return [
    row("a Camera's Look through it", _camera, (tester) async {
      await switched(keyed("cameraLook"))(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<CanvasToggle>(keyed("cameraLook")).value, isTrue);
    }, (_) {}, step: false),
    row("a Camera's Zoom", _camera, keyTyped("cameraZoom", 2),
        (d) => expect(cameraFraming(cam(d), 0, d).$1, closeTo(2, 1e-6))),
    row("a Camera's Roll", _camera, keyTyped("cameraRoll", 30),
        (d) => expect(cam(d).rotation, 30)),
    row(
        "a Camera's Focus on",
        _camera,
        chosen(keyed("cameraFocusOn"), shape.id),
        (d) => expect(cam(d).focusOn, shape.id),
        beside: [shape]),
    row("a Camera's Focus", _camera, keyTyped("cameraFocus", 40),
        (d) => expect(cam(d).focus, closeTo(0.4, 1e-9))),
    row("a Camera's Blur", _camera, keyTyped("cameraBlur", 10),
        (d) => expect(cam(d).blur, 10)),
    for (var channel in [
      KeyframeChannel.focus,
      KeyframeChannel.blur,
      KeyframeChannel.vignette
    ])
      row(
          "a Camera's $channel keyed here",
          _camera,
          pressed(keyed("cameraKey-$channel")),
          (d) => expect(keyedHere(d, channel), isNotNull)),
    row("a Camera's Parallax", _camera, keyTyped("cameraParallax", 50),
        (d) => expect(cam(d).parallax, 0.5)),
    row(
        "a Camera's aim Chart",
        _camera,
        chosen(keyed("cameraAimChart"), chart.id),
        (d) => expect(cam(d).aim, chart.id),
        beside: [chart]),
    row("a Camera's aim Frames", aimed, chosen(keyed("cameraAimAt"), "leader"),
        (d) => expect(cam(d).aimAt, "leader"),
        beside: [chart]),
    row("a Camera's aim Fills", aimed, keyTyped("cameraAimFill", 70),
        (d) => expect(cam(d).aimFill, closeTo(0.7, 1e-9)),
        beside: [chart]),
    row("a Camera's aim How far", aimed, keyTyped("cameraAimMix", 50),
        (d) => expect(keyedHere(d, KeyframeChannel.aimMix), 0.5),
        beside: [chart]),
    row(
        "a Camera's aim keyed here",
        aimed,
        pressed(keyed("cameraKey-${KeyframeChannel.aimMix}")),
        (d) => expect(keyedHere(d, KeyframeChannel.aimMix), 1),
        beside: [chart]),
    row("a Camera's Vignette", _camera, keyTyped("cameraVignette", 30),
        (d) => expect(cam(d).vignette, closeTo(0.3, 1e-9))),
    row("a Camera's Softness", _camera, keyTyped("cameraVignetteSoft", 80),
        (d) => expect(cam(d).vignetteSoft, closeTo(0.8, 1e-9))),
    row("a Camera's Motion blur", _camera, keyTyped("cameraMotionBlur", 40),
        (d) => expect(cam(d).motionBlur, closeTo(0.4, 1e-9))),
    row(
        "a Camera's move",
        _camera,
        pressed(find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith("cameraMove-"))
            .first),
        (d) => expect(cam(d).base.motion.placed, hasLength(1))),
    row("a Camera not in use, made the one in use", _close,
        pressed(keyed(_useThis)), (d) => expect(cameraOf(d)?.id, _close.id),
        beside: [_wide]),
    for (var (key, value, field) in [
      ("lens", 50.0, (StageCamera v) => v.lens),
      ("distance", 9.0, (StageCamera v) => v.distance),
      ("height", 2.0, (StageCamera v) => v.ty),
      ("turn", 40.0, (StageCamera v) => v.yaw),
      ("tilt", 20.0, (StageCamera v) => v.pitch),
    ])
      row(
          "a Camera's $key on a stage",
          _camera,
          keyTyped("camera3d-$key", value),
          (d) => expect(field(cam(d).view!), value),
          doc: onStage),
  ];
}

// ---- A metronome ----------------------------------------------------------

final _metronome =
    newElement(ElementKind.metronome, panelDocument) as MetronomeElement;

List<ControlRow> _metronomeRows() {
  MetronomeElement m(CanvasDocument d) => _only<MetronomeElement>(d);
  const row = controlRow;
  return [
    row("a metronome's Start", _metronome, (tester) async {
      await pressOn(tester, keyed("metronomeGo"));
      expect(
          find.descendant(
              of: keyed("metronomeGo"), matching: find.text("Stop")),
          findsOneWidget);
      // Stopped again, so nothing is left ticking.
      await pressOn(tester, keyed("metronomeGo"));
      await tester.pump(const Duration(milliseconds: 100));
    }, (_) {}, step: false),
    row("a metronome's quick BPM", _metronome, keyTyped("metronomeBpm", 90),
        (d) => expect(m(d).bpm, 90)),
    row("a metronome's BPM", _metronome, (tester) async {
      var w = tester.widget<CanvasSlider>(keyed("metronomeBpmSlider"));
      w.onChanged(100);
      w.onCommit?.call();
    }, (d) => expect(m(d).bpm, 100)),
    row("a metronome's Beats in a bar", _metronome,
        chosen(keyed("metronomeBeats"), 5), (d) => expect(m(d).beats, 5)),
    row("a metronome's Wood", _metronome, coloured(keyed("metronomeBody")),
        (d) => expect(m(d).body, rowRed)),
    row("a metronome's Lamp", _metronome, coloured(keyed("metronomeAccent")),
        (d) => expect(m(d).accent, rowRed)),
  ];
}
