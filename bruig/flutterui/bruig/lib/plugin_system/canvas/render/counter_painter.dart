import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// counter_painter.dart draws a counter: a formatted number with words either
// side of it, in a box, over whatever buttons it carries.
//
// The number and the words are painted as one line of differently styled
// stretches rather than as three pieces side by side. Pieces painted one
// after another have to be positioned by adding up their widths, and a line
// laid out that way is a line that will not centre -- which matters more here
// than anywhere else, because the width of the number changes as it counts.

/// counterGap is the space between the buttons, and between them and the
/// number above.
const double counterGap = 8;

/// counterButtonRects is where a counter's buttons are, in document space.
///
/// Public for the same reason tableRowHeights is: the stage has to know which
/// button the pointer is over, and a second calculation would be a second
/// answer -- a button that lights up under the pointer and does nothing when
/// pressed is worse than no button.
List<Rect> counterButtonRects(CounterElement e, Rect bounds) {
  if (e.buttons.isEmpty) return const [];
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return const [];

  // Placed by hand: each one where it was put, at the size the element
  // carries. The row below is what a set of controls is, and this is for the
  // counters that are not that.
  if (e.looseButtons) {
    var w = math.max(8.0, inner.width * e.buttonSize.width);
    var h = math.max(8.0, inner.height * e.buttonSize.height);
    return [
      for (var i = 0; i < e.buttons.length; i++)
        Rect.fromCenter(
            center: _placed(inner, e.placedButton(i)), width: w, height: h),
    ];
  }

  var height = counterButtonHeight(e, inner);
  var gap = counterGap * _unit(inner);
  var each = (inner.width - gap * (e.buttons.length - 1)) / e.buttons.length;
  if (each <= 0) return const [];

  return [
    for (var i = 0; i < e.buttons.length; i++)
      Rect.fromLTWH(
          inner.left + (each + gap) * i, inner.bottom - height, each, height),
  ];
}

/// _placed turns a fraction-of-the-box placement into a point.
///
/// From the middle rather than from a corner, so that nought is the middle
/// and the two halves are symmetrical -- which is what makes "a little to the
/// left" a small negative number rather than something under a half.
Offset _placed(Rect inner, Offset at) => Offset(
      inner.center.dx + inner.width * at.dx,
      inner.center.dy + inner.height * at.dy,
    );

/// counterButtonHeight is how tall that row is: the label plus the button's
/// own padding, and never more than half the element.
double counterButtonHeight(CounterElement e, Rect inner) {
  if (e.buttons.isEmpty) return 0;
  var label = e.buttonSpec.fontSize * 1.35;
  var pad = e.buttonBox.pad.top + e.buttonBox.pad.bottom;
  return math.min(inner.height * 0.5, label + pad);
}

/// _unit scales the fixed gaps with the element, so a counter exported at four
/// times the size is the same picture rather than the same picture with
/// hairline gaps.
double _unit(Rect inner) => math.max(0.2, inner.shortestSide / 120);

/// paintCounter draws one, showing [value].
///
/// The value is handed in rather than worked out here: on the timeline it
/// comes from the keyframes and in a live counter it comes from a clock that
/// is running, and a painter is the wrong place to know the difference.
void paintCounter(
  ui.Canvas canvas,
  Rect bounds,
  CounterElement e,
  double value, {
  /// pressed is which button is lit, if any: the one under the pointer on the
  /// stage, and none at all in an exported picture.
  int pressed = -1,

  /// running is whether it is counting at this moment, which is what the
  /// start/stop button has to say. Null falls back to what the element says
  /// it does when it opens -- which is what a picture of one shows, nothing
  /// there being able to run.
  bool? running,
}) {
  if (bounds.width <= 0 || bounds.height <= 0) return;
  paintBox(canvas, bounds, e.box);

  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;

  var buttons = counterButtonRects(e, bounds);
  // The number keeps the whole box where the buttons have been placed by
  // hand: they are somewhere of their own choosing, and reserving a strip for
  // a row that is not there would push the figures up for nothing.
  var room = buttons.isEmpty || e.looseButtons
      ? inner
      : Rect.fromLTRB(inner.left, inner.top, inner.right,
          buttons.first.top - counterGap * _unit(inner));

  if (room.height > 0) {
    // Sized to the whole count rather than to the number showing, so that the
    // figures do not change size as they go -- see counterFitScale.
    var scale = e.fit ? counterFitScale(e, room, value) : 1.0;
    var number = _scaled(e.numberSpec, scale);
    var affix = _scaled(e.affixSpec, scale);

    if (e.loose) {
      // The words are somewhere of their own; the number keeps the line.
      paintTextInBox(canvas, e.format(value), number, room, clip: true);
      _paintLoose(canvas, inner, e.before, affix, e.beforeAt);
      _paintLoose(canvas, inner, e.after, affix, e.afterAt);
    } else {
      // A space in the number's own ems, so it holds when the type is shrunk
      // to fit. Written as a stretch of its own rather than as letter spacing
      // on the words, which would space the words themselves apart as well.
      var space = _spacer(e.gap, number);
      paintRunsInBox(
        canvas,
        [
          if (e.before.isNotEmpty) ...[
            (e.before, affix),
            if (space != null) space
          ],
          (e.format(value), number),
          if (e.after.isNotEmpty) ...[
            if (space != null) space,
            (e.after, affix)
          ],
        ],
        number,
        room,
        clip: true,
      );
    }
  }

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

/// _spacer is the gap between the number and a word, as a stretch of text.
///
/// A space set at the gap's own size: one em of type is one space that wide,
/// and asking for two and a half of them is a space two and a half ems wide.
/// Nothing at all where no gap was asked for, so the commonest counter draws
/// exactly what it drew before this existed.
(String, TextSpec)? _spacer(double gap, TextSpec number) => gap <= 0
    ? null
    : (" ", number.copyWith(fontSize: math.max(0.1, number.fontSize * gap)));

/// _paintLoose writes one of the words at a placement of its own.
void _paintLoose(
    ui.Canvas canvas, Rect inner, String text, TextSpec spec, Offset at) {
  if (text.isEmpty) return;
  var centre = _placed(inner, at);
  // A box the width of the element around the point, so long words have
  // somewhere to go and the placement stays the middle of them.
  var box = Rect.fromCenter(
      center: centre,
      width: inner.width,
      height: math.max(spec.fontSize * 1.6, 1));
  paintTextInBox(
      canvas,
      text,
      spec.copyWith(
          align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle),
      box,
      clip: true);
}

/// counterFitScale is how much the type has to come down for the whole count
/// to fit the room it has.
///
/// Measured against the widest value the counter will ever show rather than
/// the one on screen: a number that fits at 42 and not at 1,234,567 would
/// otherwise shrink partway through the count, and a figure that changes size
/// as it counts is worse than one that is small.
///
/// Both ends and the value showing, because a point in the middle of a count
/// can be higher than either end -- that is what points are for.
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

/// _measure is how big one line of this counter is at its own type sizes.
Size _measure(CounterElement e, double value) {
  var painter = TextPainter(
    text: TextSpan(
      style: textStyleOf(e.numberSpec),
      children: [
        if (e.before.isNotEmpty && !e.loose)
          TextSpan(text: e.before, style: textStyleOf(e.affixSpec)),
        if (e.before.isNotEmpty && e.gap > 0 && !e.loose)
          TextSpan(
              text: " ",
              style: textStyleOf(e.numberSpec
                  .copyWith(fontSize: e.numberSpec.fontSize * e.gap))),
        TextSpan(text: e.format(value), style: textStyleOf(e.numberSpec)),
        if (e.after.isNotEmpty && e.gap > 0 && !e.loose)
          TextSpan(
              text: " ",
              style: textStyleOf(e.numberSpec
                  .copyWith(fontSize: e.numberSpec.fontSize * e.gap))),
        if (e.after.isNotEmpty && !e.loose)
          TextSpan(text: e.after, style: textStyleOf(e.affixSpec)),
      ],
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  var size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}

/// _scaled is one spec at a fraction of its size. The letter spacing goes
/// with it: spacing set for sixty-point figures is a gap between
/// twenty-point ones.
TextSpec _scaled(TextSpec spec, double scale) => scale >= 0.999
    ? spec
    : spec.copyWith(
        fontSize: spec.fontSize * scale,
        letterSpacing: spec.letterSpacing * scale);

/// _labelFor is what one button says.
///
/// The start/stop button says which of the two it would do next, which is the
/// only honest label for a control with two jobs -- but only where the
/// counter is running; a still one says "Start" whether it has been stopped
/// or never started.
String _labelFor(CounterElement e, CounterButton button, bool running) =>
    switch (button) {
      CounterButton.startStop => running ? "Stop" : "Start",
      CounterButton.reset => "Reset",
      CounterButton.input => "Set",
    };

/// _lit is a button's fill under the pointer: a little brighter, whatever it
/// started as, so that a counter with its own colours still answers a hover.
Color _lit(Color fill) => Color.lerp(fill, const Color(0xFFFFFFFF), 0.18)!;
