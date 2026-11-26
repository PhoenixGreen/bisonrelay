import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// counter_painter.dart draws a counter: a formatted number with words either
// side, in a box, over whatever buttons it carries. The number and words are
// one line of styled runs, so the line centres as the number's width changes.
// Where each piece lands is worked out once (counterLaidOut), for the
// painter and for the stage's presses alike.

/// counterGap is the space between the buttons, and above them to the number.
const double counterGap = 8;

/// CounterLaidOut is a counter laid out in its box: where its number goes
/// and at what size, and where each piece is. The painter draws from it and
/// the stage presses by it, so the two cannot differ.
class CounterLaidOut {
  /// inner is the box inside its padding; room is what of it the number
  /// has (above a row of buttons).
  final Rect inner;
  final Rect room;

  /// fit is the type's scale, from shrinking to fit (1 where it does not).
  final double fit;

  /// buttons are its buttons' boxes, in its buttons' order; none where they
  /// do nothing (CounterMode.buttonsAct).
  final List<Rect> buttons;

  /// words are where the letters of its loosely placed words are drawn,
  /// with [bands], the line each is laid out on.
  final Map<CounterWords, Rect> words;
  final Map<CounterWords, Rect> bands;

  const CounterLaidOut._(
      this.inner, this.room, this.fit, this.buttons, this.words, this.bands);

  /// pieces are what a press can take on their own, buttons placed freely
  /// first and then loose words, each where it is drawn.
  List<(CounterPiece, Rect)> pieces(CounterElement e) => [
        if (e.looseButtons)
          for (var (i, r) in buttons.indexed) (CounterButtonPiece(i), r),
        for (var MapEntry(:key, :value) in words.entries) (key, value),
      ];
}

/// counterLaidOut is [e] laid out in [bounds], showing [value]; null where
/// its box leaves no room inside.
CounterLaidOut? counterLaidOut(CounterElement e, Rect bounds, double value) {
  if (bounds.width <= 0 || bounds.height <= 0) return null;
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return null;

  var buttons = _buttonRects(e, inner);
  // Loose buttons take no strip from the number.
  var room = buttons.isEmpty || e.looseButtons
      ? inner
      : Rect.fromLTRB(inner.left, inner.top, inner.right,
          buttons.first.top - counterGap * _unit(inner));
  var fit = room.height > 0 && e.fit ? counterFitScale(e, room, value) : 1.0;

  var words = <CounterWords, Rect>{}, bands = <CounterWords, Rect>{};
  if (e.loose && room.height > 0) {
    var affix = _looseSpec(_scaled(e.affixSpec, fit));
    for (var (piece, text, at) in [
      (const CounterWords(after: false), e.before, e.beforeAt),
      (const CounterWords(after: true), e.after, e.afterAt),
    ]) {
      if (text.isEmpty) continue;
      // Element-wide and centred on the point.
      var band = Rect.fromCenter(
          center: _placed(inner, at),
          width: inner.width,
          height: math.max(affix.fontSize * 1.6, 1));
      bands[piece] = band;
      var shown = affix.textCase.apply(text).length;
      words[piece] = textRunBox(text, affix, band, 0, shown) ?? band;
    }
  }
  return CounterLaidOut._(inner, room, fit, buttons, words, bands);
}

/// counterButtonRects is where a counter's buttons are, in document space:
/// none where they do nothing. The stage hit-tests with it, so there is one
/// calculation.
List<Rect> counterButtonRects(CounterElement e, Rect bounds) {
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return const [];
  return _buttonRects(e, inner);
}

List<Rect> _buttonRects(CounterElement e, Rect inner) {
  // Kept as saved in other modes, and drawn and pressed again once it is a
  // run (CounterMode.buttonsAct).
  if (e.buttons.isEmpty || !e.mode.buttonsAct) return const [];

  // Placed by hand, at the element's button size; otherwise a row.
  if (e.looseButtons) {
    var w = math.max(8.0, inner.width * e.buttonSize.width);
    var h = math.max(8.0, inner.height * e.buttonSize.height);
    return [
      for (var i = 0; i < e.buttons.length; i++)
        Rect.fromCenter(
            center: _placed(inner, e.placedButton(i)), width: w, height: h),
    ];
  }

  var height = _buttonRowHeight(e, inner);
  var gap = counterGap * _unit(inner);
  var each = (inner.width - gap * (e.buttons.length - 1)) / e.buttons.length;
  if (each <= 0) return const [];

  return [
    for (var i = 0; i < e.buttons.length; i++)
      Rect.fromLTWH(
          inner.left + (each + gap) * i, inner.bottom - height, each, height),
  ];
}

/// _placed turns a fraction-of-the-box placement into a point, measured
/// from the middle, so nought is centred.
Offset _placed(Rect inner, Offset at) => Offset(
      inner.center.dx + inner.width * at.dx,
      inner.center.dy + inner.height * at.dy,
    );

/// _buttonRowHeight is how tall the row of buttons is: the label plus the
/// button's own padding, and never more than half the element.
double _buttonRowHeight(CounterElement e, Rect inner) {
  var label = e.buttonSpec.fontSize * 1.35;
  var pad = e.buttonBox.pad.top + e.buttonBox.pad.bottom;
  return math.min(inner.height * 0.5, label + pad);
}

/// _unit scales the fixed gaps with the element's size.
double _unit(Rect inner) => math.max(0.2, inner.shortestSide / 120);

/// paintCounter draws one, showing [value], which comes from the animation
/// or from a live clock in the controller.
void paintCounter(
  ui.Canvas canvas,
  Rect bounds,
  CounterElement e,
  double value, {
  /// pressed is the lit button: the one under the pointer; none in an export.
  int pressed = -1,

  /// running is whether it is counting now, for the start/stop label; null
  /// falls back to the element's own setting.
  bool? running,
}) {
  if (bounds.width <= 0 || bounds.height <= 0) return;
  paintBox(canvas, bounds, e.box);

  var laid = counterLaidOut(e, bounds, value);
  if (laid == null) return;

  var room = laid.room;
  if (room.height > 0) {
    var number = _scaled(e.numberSpec, laid.fit);
    if (e.loose) {
      // The words are somewhere of their own; the number keeps the line.
      paintTextInBox(canvas, e.format(value), number, room, clip: true);
      var affix = _looseSpec(_scaled(e.affixSpec, laid.fit));
      for (var MapEntry(key: piece, value: band) in laid.bands.entries) {
        paintTextInBox(canvas, piece.after ? e.after : e.before, affix, band,
            clip: true);
      }
    } else {
      paintRunsInBox(canvas,
          _line(e, value, number, _scaled(e.affixSpec, laid.fit)), number, room,
          clip: true);
    }
  }

  var buttons = laid.buttons;
  for (var i = 0; i < buttons.length; i++) {
    var box = i == pressed
        ? e.buttonBox.copyWith(fill: _lit(e.buttonBox.fill))
        : e.buttonBox;
    paintBox(canvas, buttons[i], box);
    paintTextInBox(
      canvas,
      _labelFor(e, e.buttons[i], running ?? e.running),
      e.buttonSpec.copyWith(
          align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle),
      e.buttonBox.inner(buttons[i]),
      clip: true,
    );
  }
}

/// _line is the counter's number with its words as one line of runs, in
/// the [number]'s and the words' ([affix]) type: what is drawn, and what
/// the fit measures (_measureNow), so the two cannot differ. Loose words
/// are not on it.
List<(String, TextSpec)> _line(
    CounterElement e, double value, TextSpec number, TextSpec affix) {
  var before = e.loose ? "" : e.before, after = e.loose ? "" : e.after;
  // A space run in the number's ems, so it shrinks with fitting; letter
  // spacing would space out the words too.
  var space = _spacer(e.gap, number);
  return [
    if (before.isNotEmpty) ...[(before, affix), if (space != null) space],
    (e.format(value), number),
    if (after.isNotEmpty) ...[if (space != null) space, (after, affix)],
  ];
}

/// _spacer is the gap between the number and a word: a space at [gap] ems
/// of the number's type, or null for no gap.
(String, TextSpec)? _spacer(double gap, TextSpec number) => gap <= 0
    ? null
    : (" ", number.copyWith(fontSize: math.max(0.1, number.fontSize * gap)));

/// _looseSpec is a loose word's type: centred on its point either way.
TextSpec _looseSpec(TextSpec spec) => spec.copyWith(
    align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle);

/// counterFitScale is how much the type comes down for the whole count to fit
/// its room. Measured at both ends of the count and the value showing (a point
/// mid-count can exceed either end), so figures do not resize as they count.
double counterFitScale(CounterElement e, Rect room, double value) {
  if (room.width <= 0 || room.height <= 0) return 1;
  var widest = 0.0, tallest = 0.0;
  for (var v in {e.from, e.to, value}) {
    var size = _measure(e, v);
    widest = math.max(widest, size.width);
    tallest = math.max(tallest, size.height);
  }
  if (widest <= 0 || tallest <= 0) return 1;
  return math.min(1.0, math.min(room.width / widest, room.height / tallest));
}

/// _measured keeps each counter's measured lines by the value shown: the
/// fit is measured three times a frame, for numbers that mostly repeat.
/// Counters never change, so an edited one is a new one and misses.
final _measured = Expando<Map<double, Size>>();

/// _measure is how big one line of this counter is at its own type sizes:
/// the number alone where its words are loose.
Size _measure(CounterElement e, double value) {
  var kept = _measured[e] ??= {};
  if (kept[value] case var size?) return size;
  if (kept.length >= 64) kept.remove(kept.keys.first);
  return kept[value] = _measureNow(e, value);
}

Size _measureNow(CounterElement e, double value) {
  var painter =
      layOutRuns(_line(e, value, e.numberSpec, e.affixSpec), e.numberSpec);
  var size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}

/// _scaled is [spec] at [scale] of its size, letter spacing included.
TextSpec _scaled(TextSpec spec, double scale) => scale >= 0.999
    ? spec
    : spec.copyWith(
        fontSize: spec.fontSize * scale,
        letterSpacing: spec.letterSpacing * scale);

/// _labelFor is what one button says; start/stop says what it would do next.
String _labelFor(CounterElement e, CounterButton button, bool running) =>
    switch (button) {
      CounterButton.startStop => running ? "Stop" : "Start",
      CounterButton.reset => "Reset",
      CounterButton.input => "Set",
    };

/// _lit is a button's fill under the pointer: a little brighter.
Color _lit(Color fill) => Color.lerp(fill, const Color(0xFFFFFFFF), 0.18)!;
