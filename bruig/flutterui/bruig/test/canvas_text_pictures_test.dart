import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// canvas_text_pictures_test.dart keeps what the renderer draws of a text
// element, to the byte, in each of about a hundred and fifty states: the
// four ways words are set (in a box, in columns, round something in the
// way, along a line), each with every kind of part and look; type fitted to
// its box; a chain of boxes; pieces in slots; an arrival of every family at
// three moments, in a box and on a line; a Markdown document; and the other
// elements that draw words with the same code. Beside each picture it keeps
// the numbers the stage and the chain ask of the same layout: where a text
// is drawn (visualBoundsOf), the size Fit to box chose, where a chain
// splits the words, and where each piece sits. It is the proof that a
// change meant only to move how a paragraph is laid out draws and measures
// exactly what it did before.
//
// To use it, set TEXT_PICTURES to a folder and run this file on the code as
// it is: each state's picture (<state>.rgba and .png) and numbers
// (<state>.txt) are written there. Run it again to see that every one is
// stable from run to run. Then make the change and run it after each step:
// a state whose picture differs fails, saying how many pixels changed and
// where, and leaves the new picture beside the kept one as
// <state>.new.png; numbers that differ fail with both. Without
// TEXT_PICTURES each state is still drawn and measured, and nothing is
// kept, so the test is harmless in the whole suite.

const _w = 480, _h = 320;

const _size =
    CanvasSize(width: _w, ratio: CanvasRatio.custom, customRatio: _w / _h);

const _words = "The quick brown fox jumps over the lazy dog, "
    "and then the cat wakes up to see what all the noise is about.";

const _spec = TextSpec(
    fontSize: 22,
    weight: 400,
    align: TextAlignSpec.left,
    verticalAlign: VerticalAlignSpec.top,
    color: Color(0xFFF2F2F2));

const _red = Color(0xFFE53935);

/// _Pictures hands the painter one picture, whatever is asked for.
class _Pictures implements CanvasImageSource {
  final ui.Image image;
  _Pictures(this.image);

  @override
  bool get loading => false;

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId.isEmpty ? null : image;

  @override
  CanvasVector? resolveVector(String assetId) => null;

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

/// _State is one thing kept: a document drawn on frame 0.
typedef _State = (String, CanvasDocument);

/// _doc is a page holding [elements].
CanvasDocument _doc(List<CanvasElement> elements) =>
    CanvasDocument(size: _size, elements: elements, frames: 48);

/// _text is a text element in most of the page, with what is given.
TextElement _text({
  String id = "t",
  Rect at = const Rect.fromLTWH(60, 40, 360, 240),
  String text = _words,
  TextSpec spec = _spec,
  List<TextPart> parts = const [],
  PartHighlight? highlight,
  PartUnderline? underline,
  TextColumns columns = const TextColumns(),
  TextWrap wrap = const TextWrap(),
  TextOnCurve? curve,
  TextAnimation animation = const TextAnimation(),
  bool autoSize = false,
  List<TextItem> items = const [],
  TextSlot? slot,
  String flowTo = "",
  List<TextPart> documentParts = const [],
  BoxSpec box = const BoxSpec(padding: 0),
}) =>
    TextElement(
      ElementBase(
          id: id, x: at.left, y: at.top, width: at.width, height: at.height),
      text: text,
      textSpec: spec,
      parts: parts,
      highlight: highlight,
      underline: underline,
      columns: columns,
      wrap: wrap,
      curve: curve,
      animation: animation,
      autoSize: autoSize,
      items: items,
      slot: slot,
      flowTo: flowTo,
      documentParts: documentParts,
      box: box,
    );

/// _at is [e] with its arrival [reveal] of the way through on frame 0.
CanvasElement _at(CanvasElement e, double reveal) => e.withBase(
        track: ElementTrack([
      Keyframe(frame: 0, values: {KeyframeChannel.reveal: reveal}),
    ]));

/// _features are the things a paragraph can be drawn with, one per state:
/// parts of each kind, the element's own marks, case, spacing, looks, a
/// picture fill and a fade.
List<(String, TextElement Function(TextElement))> _features() => [
      ("plain", (e) => e),
      (
        "bold",
        (e) => e.copyWith(parts: const [TextPart(from: 2, to: 3, weight: 900)])
      ),
      (
        "double",
        (e) => e.copyWith(parts: const [TextPart(from: 2, to: 2, scale: 2)])
      ),
      (
        "face",
        (e) => e.copyWith(parts: const [
              TextPart(from: 3, to: 5, family: "Bangers", italic: true)
            ])
      ),
      (
        "coloured",
        (e) => e.copyWith(parts: const [TextPart(from: 4, to: 6, color: _red)])
      ),
      (
        "highlighted",
        (e) => e.copyWith(parts: const [
              TextPart(from: 4, to: 9, highlight: PartHighlight(radius: 4))
            ])
      ),
      for (var style in PartLineStyle.values)
        (
          "underlined-${style.name}",
          (e) => e.copyWith(parts: [
                TextPart(
                    from: 4,
                    to: 9,
                    underline: PartUnderline(style: style, color: _red))
              ])
        ),
      (
        "outlined",
        (e) => e.copyWith(parts: const [
              TextPart(from: 2, to: 4, outlineWidth: 2, outlineColor: _red)
            ])
      ),
      (
        "own-highlight",
        (e) =>
            e.copyWith(highlight: const PartHighlight(color: Color(0x6633AAFF)))
      ),
      (
        "own-underline",
        (e) => e.copyWith(underline: const PartUnderline(width: 2))
      ),
      (
        "upper",
        (e) =>
            e.copyWith(textSpec: e.textSpec.copyWith(textCase: TextCase.upper))
      ),
      (
        "title-case",
        (e) =>
            e.copyWith(textSpec: e.textSpec.copyWith(textCase: TextCase.title))
      ),
      (
        "spaced",
        (e) => e.copyWith(
            textSpec: e.textSpec.copyWith(letterSpacing: 3, lineHeight: 1.8))
      ),
      (
        "outline-look",
        (e) => textLooksLifted(e.copyWith(
            textSpec: e.textSpec.copyWith(outlineWidth: 2, outlineColor: _red)))
      ),
      (
        "shadow-look",
        (e) => textLooksLifted(e.copyWith(
            textSpec: e.textSpec.copyWith(
                shadowBlur: 4,
                shadowDistance: 4,
                shadowColor: const Color(0xFF000000))))
      ),
      (
        "glow-look",
        (e) => textLooksLifted(e.copyWith(
            textSpec: e.textSpec
                .copyWith(glowBlur: 6, glowColor: const Color(0xFF33FF66))))
      ),
      (
        "picture-fill",
        (e) => e.copyWith(
            textSpec: e.textSpec.copyWith(
                fill: const TextFill(kind: TextFillKind.image, assetId: "pic")))
      ),
      (
        "fade",
        (e) => e.copyWith(
            textSpec: e.textSpec
                .copyWith(fade: const GradientSpec(to: _red, angle: 90)))
      ),
      // Mixes: a fade with a part, and a glow kept in the type (never read
      // from a file, which would lift it) under a coloured part.
      (
        "fade-bold",
        (e) => e.copyWith(
            textSpec: e.textSpec
                .copyWith(fade: const GradientSpec(to: _red, angle: 90)),
            parts: const [TextPart(from: 2, to: 3, weight: 900)])
      ),
      (
        "glow-coloured",
        (e) => e.copyWith(
            textSpec: e.textSpec
                .copyWith(glowBlur: 6, glowColor: const Color(0xFF33FF66)),
            parts: const [TextPart(from: 4, to: 6, color: _red)])
      ),
    ];

/// _obstacle is a shape in the way of the words.
ShapeElement _obstacle(String id, Rect at,
        {ShapeKind shape = ShapeKind.ellipse}) =>
    ShapeElement(
        ElementBase(
            id: id, x: at.left, y: at.top, width: at.width, height: at.height),
        shape: shape,
        fill: const Color(0xFF3949AB));

/// _line is a line for words to ride: straight, or bowed by [curvature].
LineElement _line({double curvature = 0, bool flipped = false}) => LineElement(
    const ElementBase(id: "l", x: 40, y: 190, width: 400, height: 4),
    curvature: curvature,
    flipped: flipped,
    color: const Color(0x55FFFFFF));

const _caption = "Riding along the line";

/// _onLine is a text riding [line].
TextElement _onLine({TextOnCurve on = const TextOnCurve(elementId: "l")}) =>
    _text(
        at: const Rect.fromLTWH(10, 10, 120, 40),
        text: _caption,
        spec: _spec.copyWith(fontSize: 26, align: TextAlignSpec.center),
        curve: on);

/// _presets are the arrivals, one or more of every family.
const _presets = [
  TextAnimationPreset.slideLeft,
  TextAnimationPreset.fadeUp,
  TextAnimationPreset.letters,
  TextAnimationPreset.words,
  TextAnimationPreset.pop,
  TextAnimationPreset.scramble,
  TextAnimationPreset.mosaic,
  TextAnimationPreset.shatter,
  TextAnimationPreset.echoDown,
  TextAnimationPreset.echoLetters,
  TextAnimationPreset.trailDown,
  TextAnimationPreset.trailLetters,
  TextAnimationPreset.strokeOn,
  TextAnimationPreset.highlight,
  TextAnimationPreset.underline,
];

const _moments = [("first", 0.25), ("part-way", 0.6), ("settled", 1.0)];

/// _states is every state kept.
List<_State> _states() {
  var out = <_State>[];

  // In a box: every alignment, each vertical place, justified.
  for (var align in TextAlignSpec.values) {
    out.add((
      "box-align-${align.name}",
      _doc([_text(spec: _spec.copyWith(align: align))])
    ));
  }
  for (var v in [VerticalAlignSpec.middle, VerticalAlignSpec.bottom]) {
    out.add((
      "box-vertical-${v.name}",
      _doc([_text(spec: _spec.copyWith(verticalAlign: v))])
    ));
  }

  // Each feature in a box, in columns, wrapped and on a line.
  for (var (name, apply) in _features()) {
    out.add(("box-$name", _doc([apply(_text())])));
  }
  for (var count in [2, 3]) {
    var columns = TextColumns(
        count: count, gap: 20, ruleStyle: ColumnRuleStyle.solid, ruleWidth: 2);
    out.add((
      "columns-$count",
      _doc([_text(columns: columns, spec: _spec.copyWith(fontSize: 16))])
    ));
  }
  for (var (name, apply) in _features()) {
    if (name == "plain") continue;
    var columns = const TextColumns(
        count: 2, gap: 20, ruleStyle: ColumnRuleStyle.dashed, ruleWidth: 2);
    out.add(("columns-$name", _doc([apply(_text(columns: columns))])));
  }
  const wrap = TextWrap(on: true, gap: 8);
  var oneInWay = _obstacle("o", const Rect.fromLTWH(200, 90, 110, 110));
  var twoInWay = [
    _obstacle("o", const Rect.fromLTWH(40, 60, 120, 90)),
    _obstacle("p", const Rect.fromLTWH(300, 150, 140, 100),
        shape: ShapeKind.rectangle),
  ];
  out.add(("wrap-one", _doc([oneInWay, _text(wrap: wrap)])));
  out.add(("wrap-two", _doc([...twoInWay, _text(wrap: wrap)])));
  for (var (name, apply) in _features()) {
    if (name == "plain") continue;
    out.add(("wrap-$name", _doc([oneInWay, apply(_text(wrap: wrap))])));
  }
  out.add(("line-straight", _doc([_line(), _onLine()])));
  out.add(("line-curve", _doc([_line(curvature: 0.5), _onLine()])));
  out.add((
    "line-flipped",
    _doc([_line(curvature: 0.5, flipped: true), _onLine()])
  ));
  out.add((
    "line-away",
    _doc([
      _line(curvature: 0.5),
      _onLine(on: const TextOnCurve(elementId: "l", away: true))
    ])
  ));
  out.add((
    "line-letter-gap",
    _doc([
      _line(curvature: 0.5),
      _onLine(on: const TextOnCurve(elementId: "l", spacing: 4, offset: 0.1))
    ])
  ));
  for (var (name, apply) in _features()) {
    if (name == "plain") continue;
    out.add(("line-$name", _doc([_line(curvature: 0.5), apply(_onLine())])));
  }

  // Type fitted to its box, with and without a larger part, and in columns.
  var fit = _text(at: const Rect.fromLTWH(60, 60, 300, 160), autoSize: true);
  out.add(("fit-plain", _doc([fit])));
  out.add((
    "fit-double",
    _doc([
      fit.copyWith(parts: const [TextPart(from: 2, to: 2, scale: 2)])
    ])
  ));
  out.add((
    "fit-columns",
    _doc([fit.copyWith(columns: const TextColumns(count: 2, gap: 16))])
  ));

  // A chain of two and of three boxes, the first opening on a heading.
  var (:text, :parts) = readDocument(
      "# A heading\n\n$_words\n\nAnd a second paragraph to carry on into "
      "the boxes after the first, with **bold** words in it.",
      markdown: true);
  var head = _text(
      id: "a",
      at: const Rect.fromLTWH(20, 20, 200, 130),
      text: text,
      documentParts: parts,
      spec: _spec.copyWith(fontSize: 16),
      flowTo: "b");
  var second = _text(
      id: "b",
      at: const Rect.fromLTWH(250, 20, 200, 130),
      text: "",
      spec: _spec.copyWith(fontSize: 16));
  var third = _text(
      id: "c",
      at: const Rect.fromLTWH(20, 170, 430, 120),
      text: "",
      spec: _spec.copyWith(fontSize: 16));
  out.add(("chain-two", _doc([head, second])));
  out.add(("chain-three", _doc([head, second.copyWith(flowTo: "c"), third])));

  // A Markdown document in a box.
  var (text: md, parts: mdParts) = readDocument(
      "# Heading\n\n## Second\n\n- one item\n- *another* item\n\n"
      "Some **bold** and *italic* words and [a link](https://example.org).",
      markdown: true);
  out.add((
    "markdown",
    _doc([
      _text(
          text: md, documentParts: mdParts, spec: _spec.copyWith(fontSize: 18))
    ])
  ));

  // Pieces in several slots: words, a picture, an icon; the body sized by
  // its words in a slot of its own.
  var pieces = _text(
    at: const Rect.fromLTWH(40, 30, 400, 260),
    text: "The body's words, set in their own slot.",
    slot: TextSlot.bottomLeft,
    parts: const [TextPart(from: 2, to: 2, scale: 1.6)],
    box: const BoxSpec(fill: Color(0xFF263238), padding: 12),
    items: const [
      TextItem(
          id: "kicker",
          text: "KICKER",
          slot: TextSlot.topLeft,
          spec: TextSpec(fontSize: 18, color: Color(0xFFFFCC80))),
      TextItem(
          id: "title",
          text: "A title piece",
          slot: TextSlot.topLeft,
          gap: 6,
          spec: TextSpec(fontSize: 30, weight: 800)),
      TextItem(
          id: "picture",
          slot: TextSlot.middleRight,
          icon: TextIcon(assetId: "pic", size: 60)),
      TextItem(
          id: "badge",
          slot: TextSlot.bottomRight,
          icon: TextIcon(assetId: "pic", size: 30, turn: 20)),
    ],
  );
  out.add(("pieces", _doc([pieces])));
  out.add(("pieces-body-filling", _doc([pieces.copyWith(slot: null)])));

  // Arrivals: every family at three moments, whole-block and per piece, in
  // a box and on a line.
  for (var preset in _presets) {
    var animation = TextAnimation(
        preset: preset,
        draw: const TextDrawSpec(color: _red, padLeft: 3, padRight: 3),
        ease: ChartEase.linear);
    for (var (moment, reveal) in _moments) {
      out.add((
        "arrive-box-${preset.name}-$moment",
        _doc([_at(_text(animation: animation), reveal)])
      ));
      out.add((
        "arrive-line-${preset.name}-$moment",
        _doc([
          _line(curvature: 0.5),
          _at(_onLine().copyWith(animation: animation), reveal)
        ])
      ));
    }
  }
  // A part arriving on its own, and a highlight drawn on.
  var partArrives = _text(parts: const [
    TextPart(
        from: 3,
        to: 5,
        color: _red,
        animation: TextPartAnimation(preset: TextAnimationPreset.pop)),
    TextPart(
        from: 8,
        to: 10,
        highlight: PartHighlight(),
        animation: TextPartAnimation(marks: true)),
  ]);
  for (var (moment, reveal) in _moments) {
    out.add(("arrive-part-$moment", _doc([_at(partArrives, reveal)])));
    out.add((
      "arrive-part-line-$moment",
      _doc([
        _line(curvature: 0.5),
        _at(_onLine().copyWith(parts: partArrives.parts), reveal)
      ])
    ));
    out.add((
      "arrive-columns-$moment",
      _doc([
        _at(
            _text(
                columns: const TextColumns(count: 2),
                animation: const TextAnimation(
                    preset: TextAnimationPreset.letterRise,
                    ease: ChartEase.linear)),
            reveal)
      ])
    ));
    out.add((
      "arrive-wrap-$moment",
      _doc([
        oneInWay,
        _at(
            _text(
                wrap: wrap,
                animation: const TextAnimation(
                    preset: TextAnimationPreset.strokeOn,
                    draw: TextDrawSpec(color: _red),
                    ease: ChartEase.linear)),
            reveal)
      ])
    ));
    out.add((
      "arrive-pieces-$moment",
      _doc([
        _at(
            pieces.copyWith(
                animation: const TextAnimation(
                    preset: TextAnimationPreset.fadeUp,
                    piecesInTurn: true,
                    ease: ChartEase.linear)),
            reveal)
      ])
    ));
  }

  // The other elements that draw words with the same code.
  var page = _doc(const []);
  CanvasElement made(ElementKind kind, String id) =>
      newElement(kind, page).withId(id);
  out.add((
    "other-shape",
    _doc([
      ShapeElement(
          const ElementBase(id: "s", x: 100, y: 80, width: 280, height: 160),
          shape: ShapeKind.ellipse,
          fill: const Color(0xFF00897B),
          text: "A shape's label, wrapped",
          textSpec: _spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.middle)),
    ])
  ));
  for (var kind in [
    ElementKind.button,
    ElementKind.counter,
    ElementKind.table,
    ElementKind.chart,
    ElementKind.playTask,
  ]) {
    out.add(("other-${kind.name}", _doc([made(kind, "k")])));
  }
  return out;
}

/// _numbers is what the stage and the chain ask of each text in [doc], one
/// line each, written exactly.
String _numbers(CanvasDocument doc) {
  var out = StringBuffer();
  for (var e in doc.elements.whereType<TextElement>()) {
    var bounds = e.bounds;
    var spec = drawnTextSpec(e, bounds);
    var inner = textBodyRect(e, bounds) ?? e.box.inner(bounds);
    var flow = flowFor(e, doc, inner, spec);
    out.writeln("${e.id} drawn ${visualBoundsOf(e, doc, 0)}");
    out.writeln("${e.id} size ${spec.fontSize}");
    out.writeln("${e.id} flow ${flow.text.length} ${flow.overflows}");
    out.writeln("${e.id} body ${textBodyRect(e, bounds)}");
    out.writeln("${e.id} pieces ${textItemRects(e, bounds)}");
  }
  return out.toString();
}

void main() {
  late _Pictures pictures;

  setUpAll(() async {
    // Four colours, one a quarter, so which part of a picture shows is plain.
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    const colours = [
      Color(0xFFFF5252),
      Color(0xFF40C4FF),
      Color(0xFFFFEB3B),
      Color(0xFF69F0AE)
    ];
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH((i % 2) * 16.0, (i ~/ 2) * 16.0, 16, 16),
          Paint()..color = colours[i]);
    }
    pictures = _Pictures(await recorder.endRecording().toImage(32, 32));
  });

  /// keep draws [doc] and compares the picture and numbers with those kept
  /// as [name], or keeps them.
  Future<void> keep(String name, CanvasDocument doc) async {
    var recorder = ui.PictureRecorder();
    paintCanvasDocument(ui.Canvas(recorder), doc, images: pictures);
    var image = await recorder.endRecording().toImage(_w, _h);
    var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    var png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    var numbers = _numbers(doc);

    var dir = Platform.environment["TEXT_PICTURES"];
    if (dir == null || dir.isEmpty) return;
    Directory(dir).createSync(recursive: true);
    var kept = File("$dir/$name.rgba");
    var keptNumbers = File("$dir/$name.txt");
    if (!kept.existsSync()) {
      kept.writeAsBytesSync(raw);
      File("$dir/$name.png").writeAsBytesSync(png);
      keptNumbers.writeAsStringSync(numbers);
      return;
    }
    var fresh = File("$dir/$name.new.png");
    if (fresh.existsSync()) fresh.deleteSync();
    var was = kept.readAsBytesSync();
    if (!_same(was, raw)) {
      fresh.writeAsBytesSync(png);
      var changed = 0;
      int? left, top, right, bottom;
      for (var i = 0; i < raw.length && i < was.length; i += 4) {
        if (raw[i] == was[i] &&
            raw[i + 1] == was[i + 1] &&
            raw[i + 2] == was[i + 2] &&
            raw[i + 3] == was[i + 3]) {
          continue;
        }
        changed++;
        var x = (i ~/ 4) % _w, y = (i ~/ 4) ~/ _w;
        left = left == null || x < left ? x : left;
        right = right == null || x > right ? x : right;
        top = top == null || y < top ? y : top;
        bottom = bottom == null || y > bottom ? y : bottom;
      }
      fail("$name: $changed pixels differ, within x $left..$right, "
          "y $top..$bottom (see $name.new.png)");
    }
    expect(numbers, keptNumbers.readAsStringSync(), reason: name);
  }

  var states = _states();
  test("there are as many states as meant", () {
    expect(states.length, greaterThan(100));
    expect({for (var (name, _) in states) name}.length, states.length,
        reason: "every state has a name of its own");
  });
  for (var (name, doc) in states) {
    test(name, () => keep(name, doc));
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
