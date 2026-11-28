import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_cell_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/counter_input.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_parts.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_parts_on_page_test.dart is a press on an element's own parts on a
// frame where the element is drawn away from where it rests: turned or
// slanted as it rests, turned or sized by its keys about a corner,
// squashed, spun by its loop, moved by a clip. Each part's middle is worked
// out where the painter draws it (the part's place in the element's box,
// laid on the page by placeOnPage), pressed through the real stage, and
// the press is read back: it reached that part and no other, and a drag on
// it moved what is drawn as far as the pointer went. The text editor and a
// table's cell editor are read from the widget tree: each sits on the
// words or the cell as drawn, its corners within a pixel of theirs. The
// element at rest is the control: every kind has always passed there.

const _page = 1000;

/// _midway is the frame each is pressed on: half-way through its keys and
/// its clip, and a quarter of the way round its loop.
const _midway = 12;

/// _near is how close, in document units, what is drawn must come to where
/// it should be after a drag; _pixel how close an editor's corner must be
/// to the one drawn, on screen.
const _near = 0.5;
const _pixel = 1.0;

/// _NoFrames is a video source with nothing in it: no decoder is started.
class _NoFrames implements FrameSource {
  @override
  Future<FrameReader?> open(String path,
          {required double from,
          required int width,
          required int height,
          required double fps}) async =>
      null;
}

/// _keyed is [base] with a key at rest on frame 0 and [to] on frame 24.
ElementBase _keyed(ElementBase base, Keyframe to) => base.copyWith(
    track: ElementTrack([const Keyframe(frame: 0), to.copyWith(frame: 24)]));

/// _clip carries an element [x] across and [y] down in two seconds.
ElementMotion _clip(double x, double y) => ElementMotion(clips: [
      MotionClip(id: "go", kind: MotionKind.action, length: 2, keys: {
        MotionProp.x: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(x))
        ],
        MotionProp.y: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(y))
        ],
      }),
    ], placed: const [
      ClipPlacement(id: "p", clip: "go", length: 2)
    ]);

const _spin = ElementLoop(preset: LoopPreset.spin, cycle: 48);

/// _Motion is one way an element is laid out on [_midway]: its name, what
/// it does to the element's base, and the loop it is given, if any.
typedef _Motion = (String, ElementBase Function(ElementBase), ElementLoop?);

final List<_Motion> _motions = [
  ("at rest", (b) => b, null),
  ("turned as it rests", (b) => b.copyWith(rotation: 30), null),
  ("slanted as it rests", (b) => b.copyWith(skewX: 20), null),
  (
    "turned by its keys about an anchor at its corner",
    (b) => _keyed(b.copyWith(anchorX: 0, anchorY: 0),
        const Keyframe(frame: 0, rotate: 50)),
    null
  ),
  (
    "sized by its keys about an anchor at its corner",
    (b) => _keyed(b.copyWith(anchorX: 0, anchorY: 0),
        const Keyframe(frame: 0, scale: 1.6)),
    null
  ),
  (
    "squashed by its keys",
    (b) => _keyed(
        b,
        const Keyframe(frame: 0, values: {
          KeyframeChannel.squash: 1.6,
          KeyframeChannel.squashAngle: 0,
        })),
    null
  ),
  ("spun by its loop", (b) => b, _spin),
  ("moved by a clip", (b) => b.copyWith(motion: _clip(60, 30)), null),
];

/// _Stage is a controller on a real stage, the element pressed, and the way
/// between the page and the stage's points.
class _Stage {
  final CanvasController c;
  final CanvasStageState stage;
  final String id;
  _Stage(this.c, this.stage, this.id);

  double get scale => stage.pageRect.width / _page;
  Offset toScreen(Offset doc) => stage.toStagePoint(doc);

  CanvasElement get now => c.document.elementById(id)!;

  /// on is the element as the painter lays it out on [_midway] now.
  ElementOnPage get on => placeOnPage(now, _midway, c.document, null);

  /// drawn is [p], a point of the element's box, where it is drawn.
  Offset drawn(Offset p) => on.place.place(p);

  /// along is [d] document units along the element's box, across its
  /// width, as that is drawn on the page from [p].
  Offset along(Offset p, double d) =>
      on.place.place(p + Offset(d, 0)) - on.place.place(p);
}

/// _Kind is one part of one kind of element: its name, the element at rest
/// put on [c] (its id), the element given [loop] (null where the kind has no
/// loop), whether it is selected first, and the check: press the part where
/// it is drawn and read what the press did.
class _Kind {
  final String name;
  final String Function(CanvasController c) make;
  final CanvasElement Function(CanvasElement e, ElementLoop loop)? looped;
  final bool selected;
  final Future<void> Function(WidgetTester tester, _Stage s) check;
  const _Kind(this.name, this.make, this.looped, this.check,
      {this.selected = true});
}

CanvasDocument _empty() => const CanvasDocument(
    size: CanvasSize(width: _page, ratio: CanvasRatio.square),
    frames: 1440,
    frameRate: 12,
    guides: CanvasGuides(snap: false));

const _base = ElementBase(id: "e", x: 300, y: 300, width: 360, height: 180);

/// _put adds [e] to [c] and answers its id.
String _put(CanvasController c, CanvasElement e) {
  c.addElement(e);
  return e.id;
}

/// _drag presses at document point [from] and takes the pointer [by], in
/// document units, in two steps.
Future<void> _drag(
    WidgetTester tester, _Stage s, Offset from, Offset by) async {
  var g = await tester.startGesture(s.toScreen(from));
  await tester.pump();
  await g.moveBy(by * s.scale / 2);
  await tester.pump();
  await g.moveBy(by * s.scale / 2);
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

/// _stayed is that the drag moved the part, not the element: its box, its
/// keys and its motion are as they were.
void _stayed(_Stage s, CanvasElement was) {
  expect(s.now.base, was.base,
      reason: "the part moved, not the element round it");
}

/// _tap presses and lets go at document point [at].
Future<void> _tap(WidgetTester tester, _Stage s, Offset at) async {
  await tester.tapAt(s.toScreen(at));
  await tester.pumpAndSettle();
}

/// _doubleTap is two presses at document point [at], as a person opening
/// something does.
Future<void> _doubleTap(WidgetTester tester, _Stage s, Offset at) async {
  await tester.tapAt(s.toScreen(at));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(s.toScreen(at));
  await tester.pumpAndSettle();
}

/// _corners is [box]'s top left, top right and bottom left as [inside]
/// draws them on screen: its top left and its two edges from there, which
/// show where it is, how big, and its turn and slant.
List<Offset> _screenCorners(RenderBox inside, Size box) => [
      inside.localToGlobal(Offset.zero),
      inside.localToGlobal(Offset(box.width, 0)),
      inside.localToGlobal(Offset(0, box.height)),
    ];

void _sitsOn(List<Offset> field, List<Offset> drawn, String what) {
  for (var i = 0; i < 3; i++) {
    expect((field[i] - drawn[i]).distance, lessThan(_pixel),
        reason: "$what: corner $i at ${field[i]}, drawn at ${drawn[i]}");
  }
}

TableElement _table(ElementBase base,
        {ElementLoop loop = const ElementLoop()}) =>
    TableElement(base,
        rows: const [
          ["Team", "Won", "Lost"],
          ["Hull", "3", "1"],
          ["Leeds", "2", "2"],
        ],
        animation: ElementAnimation(loop: loop));

final List<_Kind> _kinds = [
  _Kind(
    "a counter's Set button",
    (c) => _put(
        c,
        const CounterElement(
            ElementBase(id: "e", x: 300, y: 300, width: 300, height: 140),
            keyed: false,
            buttons: [CounterButton.startStop, CounterButton.input])),
    (e, loop) =>
        (e as CounterElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var rects = counterButtonRects(on.drawn as CounterElement, on.box);
      await _tap(tester, s, s.drawn(rects[1].center));
      expect(find.byType(CounterInput), findsOneWidget,
          reason: "the Set button opens its field");
      expect(s.c.counterRunning(s.now as CounterElement), isFalse,
          reason: "and its Start button was not pressed");
    },
  ),
  _Kind(
    "a counter's loose word, dragged",
    (c) => _put(
        c,
        const CounterElement(
            ElementBase(id: "e", x: 300, y: 300, width: 320, height: 200),
            keyed: false,
            loose: true,
            before: "Score",
            beforeAt: Offset(-0.3, -0.25))),
    (e, loop) =>
        (e as CounterElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var drawn = on.drawn as CounterElement;
      var laid = counterLaidOut(drawn, on.box, s.c.counterValue(drawn))!;
      var word = laid.pieces(drawn).firstWhere(
          (p) => p.$1 is CounterWords && !(p.$1 as CounterWords).after);
      var from = s.drawn(word.$2.center);
      const by = Offset(30, 20);
      var was = s.now;
      await _drag(tester, s, from, by);
      _stayed(s, was);
      var after = s.now as CounterElement;
      expect(after.beforeAt, isNot(drawn.beforeAt), reason: "the word moved");
      // The word's place is a share of the inner box from its middle: it
      // goes under the pointer, as drawn.
      var now = s.on;
      var inner = after.box.inner(now.box);
      var at = now.place.place(inner.center +
          Offset(after.beforeAt.dx * inner.width,
              after.beforeAt.dy * inner.height));
      expect((at - (from + by)).distance, lessThan(_near),
          reason: "under the pointer: $at, pointer at ${from + by}");
    },
  ),
  _Kind(
    "a chart's key entry",
    (c) => _put(
        c,
        ChartElement(
          const ElementBase(id: "e", x: 260, y: 300, width: 480, height: 280),
          showLegend: true,
          data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
        )),
    (e, loop) =>
        (e as ChartElement).copyWith(animation: ChartAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var entry = chartLegendRects(on.drawn as ChartElement, on.box)[1].$2;
      await _tap(tester, s, s.drawn(entry.center));
      var chart = s.now as ChartElement;
      expect(chart.data.series[1].hidden, isTrue, reason: "its series off");
      expect(chart.data.series[0].hidden, isFalse, reason: "not the other");
    },
  ),
  _Kind(
    "a chart's title, dragged",
    (c) => _put(
        c,
        ChartElement(
          const ElementBase(id: "e", x: 260, y: 300, width: 480, height: 280),
          title: "Title",
          titleBox: const ChartLabel(x: 0.3, y: 0.3, width: 0.3, height: 0.12),
          floatingLabels: true,
          data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
        )),
    (e, loop) =>
        (e as ChartElement).copyWith(animation: ChartAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var title = chartLabelPlaces(
          on.drawn as ChartElement, on.box)[ChartLabelPart.title]!;
      var from = s.drawn(title.center);
      const by = Offset(24, 16);
      var was = s.now;
      await _drag(tester, s, from, by);
      _stayed(s, was);
      var now = s.on;
      var moved = chartLabelPlaces(
          now.drawn as ChartElement, now.box)[ChartLabelPart.title]!;
      var at = now.place.place(moved.center);
      expect((at - (from + by)).distance, lessThan(_near),
          reason: "the title's middle under the pointer: $at, "
              "pointer at ${from + by}");
    },
  ),
  _Kind(
    "a table's cell, opened by a double click",
    (c) => _put(c, _table(_base)),
    (e, loop) =>
        (e as TableElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var cell = tableCellRect(on.drawn as TableElement, on.box, 2, 2);
      await _doubleTap(tester, s, s.drawn(cell.center));
      expect(find.byKey(const ValueKey("cell-e-2-2")), findsOneWidget,
          reason: "that cell open for typing");
    },
  ),
  _Kind(
    "a table's cell editor, on the cell as drawn",
    (c) => _put(c, _table(_base)),
    (e, loop) =>
        (e as TableElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var cell = tableCellRect(on.drawn as TableElement, on.box, 2, 2);
      await _doubleTap(tester, s, s.drawn(cell.center));
      var editor = find.byType(CanvasCellEditor);
      expect(editor, findsOneWidget);
      var box = tester.renderObject<RenderBox>(editor);
      _sitsOn(
          _screenCorners(box, cell.size * s.scale),
          [
            s.toScreen(s.drawn(cell.topLeft)),
            s.toScreen(s.drawn(cell.topRight)),
            s.toScreen(s.drawn(cell.bottomLeft)),
          ],
          "the cell editor");
    },
  ),
  _Kind(
    "a table's column rule, dragged",
    (c) => _put(c, _table(_base)),
    (e, loop) =>
        (e as TableElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var rule = tableColumnDividers(on.drawn as TableElement, on.box)[0];
      var middle = Offset(rule, on.box.center.dy);
      var from = s.drawn(middle);
      var by = s.along(middle, 20);
      var was = s.now;
      await _drag(tester, s, from, by);
      _stayed(s, was);
      var now = s.on;
      var moved = tableColumnDividers(now.drawn as TableElement, now.box)[0];
      var at = now.place.place(Offset(moved, now.box.center.dy));
      expect((at - (from + by)).distance, lessThan(_near),
          reason: "the rule under the pointer: $at, pointer at ${from + by}");
    },
  ),
  _Kind(
    "a Code panel's tab",
    (c) {
      var lesson =
          CanvasController(_empty(), audioEngine: FakeEngine(const {}));
      lesson.addCodeLesson(
          starter: codeStarters.firstWhere((s) => s.key == "web"));
      var code = lesson.document.elements.whereType<CodeElement>().single;
      lesson.dispose();
      // Two tabs in its first pane, the first shown.
      var files = code.files;
      code = code.openTab(0, files[1].id).openTab(0, files[0].id);
      return _put(
          c,
          code.rebase(code.base
              .copyWith(id: "e", x: 220, y: 260, width: 560, height: 380)));
    },
    null,
    (tester, s) async {
      var on = s.on;
      var code = on.drawn as CodeElement;
      var pane = codeBoxes(code, on.box).panes.first;
      var shown = s.c.codeShownFile(s.now as CodeElement, pane.index);
      var other = pane.tabs.firstWhere((t) => t.file != shown);
      await _tap(tester, s, s.drawn(other.rect.center));
      expect(s.c.codeShownFile(s.now as CodeElement, pane.index), other.file,
          reason: "the tab pressed is shown");
    },
    selected: false,
  ),
  _Kind(
    "a speaker's volume",
    (c) => _put(
        c,
        const AudioElement(
            ElementBase(id: "e", x: 300, y: 300, width: 400, height: 80),
            controls: [
              AudioControl.playPause,
              AudioControl.mute,
              AudioControl.volume
            ])),
    (e, loop) =>
        (e as AudioElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var bar = audioParts(on.drawn as AudioElement, on.box).volume!;
      var local = Offset(bar.left + bar.width * 0.7, bar.center.dy);
      await _tap(tester, s, s.drawn(local));
      var view = s.c.audio.view(s.now as AudioElement);
      expect(view.volume, closeTo(volumeAt(bar, local.dx), 0.01),
          reason: "set from where along the bar it was pressed");
      expect(view.muted, isFalse, reason: "not its mute");
    },
  ),
  _Kind(
    "a speaker's mute",
    (c) => _put(
        c,
        const AudioElement(
            ElementBase(id: "e", x: 300, y: 300, width: 400, height: 80),
            controls: [
              AudioControl.playPause,
              AudioControl.mute,
              AudioControl.volume
            ])),
    (e, loop) =>
        (e as AudioElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var mute = audioParts(on.drawn as AudioElement, on.box).mute!;
      var was = s.c.audio.view(s.now as AudioElement).volume;
      await _tap(tester, s, s.drawn(mute.center));
      var view = s.c.audio.view(s.now as AudioElement);
      expect(view.muted, isTrue, reason: "muted");
      expect(view.volume, was, reason: "not its volume");
    },
  ),
  _Kind(
    "a video's volume bar",
    (c) => _put(
        c,
        const VideoElement(
            ElementBase(id: "e", x: 260, y: 260, width: 480, height: 270),
            clip: MediaClip(),
            controls: [VideoControl.playbar, VideoControl.volume])),
    (e, loop) =>
        (e as VideoElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var bar = videoParts(on.drawn as VideoElement, on.box).volume!;
      var local = Offset(bar.left + bar.width * 0.6, bar.center.dy);
      await _tap(tester, s, s.drawn(local));
      expect(s.c.video.view(s.now as VideoElement).volume,
          closeTo(alongBar(bar, local.dx), 0.01),
          reason: "set from where along the bar it was pressed");
    },
  ),
  _Kind(
    "a sheet's playbar",
    (c) {
      var sheet = const SheetElement(
          ElementBase(id: "e", x: 200, y: 280, width: 600, height: 300));
      c.addElement(sheet);
      c.newScoreFor(sheet, score: odeToJoy());
      return sheet.id;
    },
    null,
    (tester, s) async {
      var on = s.on;
      var sheet = on.drawn as SheetElement;
      var parts = sheetBarParts(sheetBarRect(sheet, on.box)!);
      var faster = parts[SheetBarPart.faster]!;
      var was = (s.now as SheetElement).tempo;
      await _tap(tester, s, s.drawn(faster.center));
      expect((s.now as SheetElement).tempo, greaterThan(was),
          reason: "its Faster button pressed");
    },
  ),
  _Kind(
    "an instrument's key",
    (c) {
      var made = newInstrument(c.document);
      return _put(
          c,
          made.rebase(
              made.base.copyWith(id: "e", x: 240, y: 340, rotation: 0)));
    },
    (e, loop) =>
        (e as AudioElement).copyWith(animation: ElementAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var e = on.drawn as AudioElement;
      var layout = keyboardLayout(e.instrument!, on.box);
      var white = layout.keys.where((k) => !k.black).elementAt(5);
      var at = s.drawn(Offset(
          white.rect.center.dx, white.rect.bottom - white.rect.height * 0.2));
      var g = await tester.startGesture(s.toScreen(at));
      await tester.pump();
      expect(s.c.heldKeys("e"), {white.key}, reason: "that key sounds");
      await g.up();
      await tester.pumpAndSettle();
    },
  ),
  _Kind(
    "a metronome's Faster button",
    (c) => _put(
        c,
        const MetronomeElement(
            ElementBase(id: "e", x: 380, y: 300, width: 200, height: 316))),
    null,
    (tester, s) async {
      var on = s.on;
      var (scale, at) = metronomeFit(on.box);
      var faster = metronomeLayout.buttons[MetronomePart.faster]!;
      var middle = at + faster.center * scale;
      await _tap(tester, s, s.drawn(middle));
      expect((s.now as MetronomeElement).bpm, 104, reason: "four faster");
    },
    selected: false,
  ),
  _Kind(
    "a text's picture piece, its box and a drag",
    (c) {
      var id = _put(
          c,
          const TextElement(
            ElementBase(id: "e", x: 300, y: 300, width: 400, height: 220),
            text: "Words",
            box: BoxSpec(padding: 20),
            items: [
              TextItem(
                  id: "pic",
                  slot: TextSlot.topRight,
                  icon: TextIcon(assetId: "asset1", size: 80)),
            ],
          ));
      return id;
    },
    (e, loop) =>
        (e as TextElement).copyWith(animation: TextAnimation(loop: loop)),
    (tester, s) async {
      s.c.pickTextLayer("e", "pic");
      await tester.pumpAndSettle();
      var on = s.on;
      var e = on.drawn as TextElement;
      var piece = e.items.single.box.inner(textItemRects(e, on.box).single);
      for (var (handle, corner) in [
        (StageHandle.topLeft, piece.topLeft),
        (StageHandle.bottomRight, piece.bottomRight),
      ]) {
        var at = s.stage.handleAt(handle);
        var drawn = s.toScreen(s.drawn(corner));
        expect((at - drawn).distance, lessThan(_pixel),
            reason: "its ${handle.name} handle at $at, drawn at $drawn");
      }
      var from = s.drawn(piece.center);
      const by = Offset(-30, 20);
      var was = s.now;
      await _drag(tester, s, from, by);
      _stayed(s, was);
      var now = s.on;
      var moved = (now.drawn as TextElement)
          .items
          .single
          .box
          .inner(textItemRects(now.drawn as TextElement, now.box).single);
      var at = now.place.place(moved.center);
      expect((at - (from + by)).distance, lessThan(_near),
          reason: "moved with the pointer: $at, pointer at ${from + by}");
    },
  ),
  _Kind(
    "a text's link to the next box, drawn from its corner",
    (c) {
      c.addElement(const TextElement(
          ElementBase(id: "f", x: 300, y: 700, width: 300, height: 150),
          text: ""));
      return _put(
          c,
          const TextElement(
              ElementBase(id: "e", x: 300, y: 300, width: 300, height: 150),
              text: "Words that run on into the next box.",
              flowTo: "f"));
    },
    (e, loop) =>
        (e as TextElement).copyWith(animation: TextAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      var line = s.stage.textFlowLines.single;
      var from = s.toScreen(
          s.drawn(Offset(on.box.right, on.box.bottom - on.box.height / 4)));
      expect((line.from - from).distance, lessThan(_pixel),
          reason: "it leaves the box where its corner is drawn: "
              "${line.from}, drawn at $from");
    },
  ),
  _Kind(
    "a text's editor, on the words as drawn",
    (c) => _put(
        c,
        const TextElement(
            ElementBase(id: "e", x: 300, y: 300, width: 360, height: 180),
            text: "Words to type into",
            box: BoxSpec(padding: 12))),
    (e, loop) =>
        (e as TextElement).copyWith(animation: TextAnimation(loop: loop)),
    (tester, s) async {
      var on = s.on;
      await _doubleTap(tester, s, s.drawn(on.box.center));
      var editor = find.byType(CanvasTextEditor);
      expect(editor, findsOneWidget);
      // What is laid over the page is what the transform holds: the words'
      // box, turned, slanted and sized as the painter draws it.
      var turned =
          find.descendant(of: editor, matching: find.byType(Transform));
      var inside = tester.renderObject<RenderTransform>(turned.first).child!;
      var box = on.box;
      _sitsOn(
          _screenCorners(inside, box.size * s.scale),
          [
            s.toScreen(s.drawn(box.topLeft)),
            s.toScreen(s.drawn(box.topRight)),
            s.toScreen(s.drawn(box.bottomLeft)),
          ],
          "the text editor");
    },
  ),
];

void main() {
  Future<_Stage> open(WidgetTester tester, _Kind kind, _Motion motion) async {
    var (_, moved, loop) = motion;
    var c = CanvasController(_empty(),
        audioEngine: FakeEngine(const {}), frameSource: _NoFrames());
    addTearDown(c.dispose);
    var id = kind.make(c);
    var e = c.document.elementById(id)!;
    e = e.rebase(moved(e.base));
    if (loop != null) e = kind.looped!(e, loop);
    c.replaceElement(e);
    c.frame = _midway;
    if (kind.selected) {
      c.selectOnly(id);
    } else {
      c.clearSelection();
    }
    var key = GlobalKey<CanvasStageState>();
    const viewport = Size(1200, 1000);
    setTestScreen(tester, viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: viewport.width,
        height: viewport.height,
        child: CanvasStage(key: key, controller: c))));
    await tester.pumpAndSettle();
    return _Stage(c, key.currentState!, id);
  }

  for (var kind in _kinds) {
    group(kind.name, () {
      for (var motion in _motions) {
        var (what, _, loop) = motion;
        if (loop != null && kind.looped == null) continue;
        testWidgets("is pressed where it is drawn, $what", (tester) async {
          var s = await open(tester, kind, motion);
          await kind.check(tester, s);
          // What a press set going (a sheet's new speed) settles.
          await tester.pump(const Duration(seconds: 1));
        });
      }
    });
  }
}
