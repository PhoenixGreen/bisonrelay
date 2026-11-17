import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:flutter/painting.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';

part 'paint_util_text_marks.dart';
part 'paint_util_shapes.dart';
part 'paint_util_columns.dart';
part 'paint_util_text_on_path.dart';

// paint_util.dart is the drawing every element does the same way: laying
// out a string, filling a box, turning a shape's name into a path. Every
// text drawer goes through layoutText, so outline, shadow, spacing and line
// height are implemented once. Nothing here touches a BuildContext or a
// theme: an export must not depend on the app's theme.

// _layouts memoises laid-out paragraphs, the most expensive thing here and
// repeated every frame for unchanged text. The key is every input that can
// change the result, so nothing has to clear it. Painters are only read
// from, so sharing is safe; evicted ones are dropped, not disposed, as a
// caller may still hold one from an earlier frame.
typedef _LayoutKey = (
  String,
  TextSpec,
  double,
  double,
  Color?,
  bool,
  bool,
  bool,
  // The size of the box a fading colour runs across, not its place: the
  // shader is in paragraph coordinates, and nothing else carries the height.
  Size?,
  // The parts, written out.
  String,
);

final _layouts = <_LayoutKey, TextPainter>{};

/// clearTextLayouts lets go of every text laid out and kept.
void clearTextLayouts() {
  for (var painter in _layouts.values) {
    painter.dispose();
  }
  _layouts.clear();
}

/// _layoutCap is the number of paragraphs kept (a busy table is a few
/// hundred cells); the oldest inserted go first.
const _layoutCap = 512;

/// layoutText builds a laid-out paragraph from a [TextSpec]. The outline is
/// a second painter ([outline]) drawn behind, not a stroke: a stroke is
/// centred on the glyph edge and would thin the letterform.
TextPainter layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,

  /// soft lays out the shadow and the glow on their own, with the letters
  /// themselves left clear. See textStyleOf.
  bool soft = false,

  /// fillWidth lays the paragraph out at exactly [maxWidth] rather than its
  /// intrinsic width: a TextPainter aligns within its own width, so without
  /// this every alignment looks like left. Measuring wants it off.
  bool fillWidth = false,

  /// parts are the runs of the text drawn differently (a word in another
  /// colour, a phrase in bold); empty for almost every paragraph.
  List<TextPart> parts = const [],

  /// over is the box the words are drawn in, for a fade (see textStyleOf).
  Rect? over,
}) {
  var key = (
    text,
    spec,
    maxWidth,
    scale,
    colorOverride,
    outline,
    soft,
    fillWidth,
    // The gradient is baked into the style. See _LayoutKey.
    over?.size,
    parts.isEmpty ? "" : [for (var p in parts) p.toJson()].toString(),
  );
  var hit = _layouts[key];
  if (hit != null) return hit;
  var painter = _layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      soft: soft,
      fillWidth: fillWidth,
      parts: parts,
      over: over);
  if (_layouts.length >= _layoutCap) {
    _layouts.remove(_layouts.keys.first);
  }
  _layouts[key] = painter;
  return painter;
}

TextPainter _layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  Rect? over,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,
  bool soft = false,
  bool fillWidth = false,
  List<TextPart> parts = const [],
}) {
  // The case transform is idempotent and applied here, so none can forget it.
  text = spec.textCase.apply(text);

  var style = textStyleOf(spec,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      soft: soft,
      over: over);

  var painter = TextPainter(
    text: parts.isEmpty
        ? TextSpan(text: text, style: style)
        : _partedSpan(text, spec, parts, style, colorOverride, scale),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  var width = math.max(0.0, maxWidth);
  painter.layout(
      minWidth: fillWidth && width.isFinite ? width : 0, maxWidth: width);
  return painter;
}

/// textOffsetIn is where a laid-out paragraph is drawn inside [box]. Only
/// the vertical alignment moves it: the painter (laid out with fillWidth)
/// has aligned horizontally. Public so things moving with the words use
/// the same paragraph rectangle the motions are fractions of.
Offset textOffsetIn(Rect box, TextPainter painter, TextSpec spec) {
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => box.top,
    VerticalAlignSpec.middle => box.top + (box.height - painter.height) / 2,
    VerticalAlignSpec.bottom => box.bottom - painter.height,
  };
  return Offset(box.left, dy);
}

/// outlineSpecFor is the type a paragraph's outline is drawn in, or null for
/// none; shared by every text layout so they agree. The type's own outline;
/// for a stroke-on arrival, a stroke in the animation's draw colour; or the
/// paragraph spec where only a part asks for one. It never invents a colour.
TextSpec? outlineSpecFor(TextSpec spec,
    {List<TextPart> parts = const [],
    TextAnimation? animation,
    double reveal = 1}) {
  if (spec.outlineWidth > 0) return spec;
  var drawing = animation != null &&
      animation.on &&
      animation.preset.motion == TextMotion.strokeOn &&
      animation.draw.color != null;
  if (drawing) {
    return spec.copyWith(
        outlineWidth: math.max(1.5, spec.fontSize * 0.06),
        outlineColor: animation.draw.color);
  }
  // A part may want an outline in a paragraph without one: the paragraph is
  // stroked with nothing and only the part's run has a width.
  return partsOutline(parts) ? spec : null;
}

/// outlineFor is [outlineSpecFor] laid out, or null where there is none.
TextPainter? outlineFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    List<TextPart> parts = const [],
    TextAnimation? animation,
    double reveal = 1}) {
  var outlineSpec =
      outlineSpecFor(spec, parts: parts, animation: animation, reveal: reveal);
  if (outlineSpec == null) return null;
  return layoutText(text, outlineSpec,
      maxWidth: maxWidth,
      scale: scale,
      outline: true,
      fillWidth: true,
      parts: parts);
}

/// softFor lays out the shadow and glow alone (the words with clear glyphs,
/// so it lines up), or null with neither. See textStyleOf's soft.
TextPainter? softFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    bool fillWidth = true,
    List<TextPart> parts = const []}) {
  if (!spec.softPasses) return null;
  return layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      soft: true,
      fillWidth: fillWidth,
      parts: parts);
}

/// paintTextInBox lays [text] out inside [box] and draws it, honouring both
/// alignments and the outline, and returns the height it took. [animation]
/// and [reveal] draw it part way through arriving (text_animator.dart).
double paintTextInBox(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box, {
  double scale = 1,
  Color? colorOverride,
  bool clip = false,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],

  /// timings are where each part arriving alone has got (TextPartAnimation).
  List<PartTiming> timings = const [],

  /// asOne makes the parts arrive with everything, as on the way out.
  bool asOne = false,

  /// images is where a picture used as a fill comes from. See TextFill.
  CanvasImageSource? images,
}) {
  if (text.isEmpty || box.width <= 0) return 0;

  var painter = layoutText(text, spec,
      maxWidth: box.width,
      scale: scale,
      colorOverride: colorOverride,
      fillWidth: true,
      parts: parts,
      // So a fade runs across the box the words are drawn in.
      over: box);

  var offset = textOffsetIn(box, painter, spec);

  if (clip) {
    canvas.save();
    // With room for the parts' marks. See marksRoom.
    var room = marksRoom(parts);
    canvas.clipRect(Rect.fromLTRB(box.left - room.left, box.top - room.top,
        box.right + room.right, box.bottom + room.bottom));
  }

  var outline = outlineFor(text, spec,
      maxWidth: box.width,
      scale: scale,
      parts: parts,
      animation: animation,
      reveal: reveal);

  var soft =
      softFor(text, spec, maxWidth: box.width, scale: scale, parts: parts);

  // Highlights behind the words now, underlines after them; they move with
  // the words while the arrival is under way.
  var marksMove = animation != null && animation.on && reveal < 1;
  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: true,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  // words draws the paragraph, through the animator whenever anything moves
  // (an arrival under way, a motion that [keeps] something, a part arriving
  // on its own). A closure because a filled paragraph is drawn twice, once
  // per TextDrawPhase, by the same code so the passes stay in register.
  void words({TextDrawPhase phase = TextDrawPhase.all}) {
    if (animation != null &&
        ((animation.on && (reveal < 1 || animation.keeps)) ||
            (!asOne && partsAnimate(parts)))) {
      paintAnimatedText(canvas, painter, text, spec, offset, animation, reveal,
          maxWidth: box.width,
          outline: outline,
          soft: soft,
          parts: parts,
          timings: timings,
          asOne: asOne,
          phase: phase);
      return;
    }
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) paintTp(painter, canvas, offset);
  }

  if (!spec.fill.on) {
    words();
  } else {
    // Outline and soft passes first, outside the fill's layer: own colours.
    words(phase: TextDrawPhase.behind);
    paintThroughText(canvas, box, spec.fill, images,
        () => words(phase: TextDrawPhase.letters),
        animation: animation, reveal: reveal, moving: offset & painter.size);
  }

  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: false,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  if (clip) canvas.restore();
  return painter.height;
}

/// fitFontSize is the largest size at which [text] fits inside [box], for
/// autoSize: a bisection, since wrapped height steps as words change lines.
/// [columns] is how many columns it flows into; [box] is one column's box.
double fitFontSize(String text, TextSpec spec, Size box, {int columns = 1}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return spec.fontSize;
  var count = math.max(1, columns);
  var low = 4.0, high = box.height * 2 * count;
  for (var i = 0; i < 14; i++) {
    var mid = (low + high) / 2;
    var p = layoutText(text, spec.copyWith(fontSize: mid), maxWidth: box.width);
    if (p.width > box.width + 0.5) {
      high = mid;
      continue;
    }
    if (count == 1) {
      p.height <= box.height ? low = mid : high = mid;
      continue;
    }
    // Against the real packing, since a column holds whole lines only.
    var runs = columnRuns(p.computeLineMetrics(), box.height, count);
    var carried = runs.isEmpty ? 0 : runs.last.$2;
    carried >= p.computeLineMetrics().length ? low = mid : high = mid;
  }
  return low;
}

/// _partedSpan builds the paragraph from runs, so a few words can differ:
/// one span per run with the same part (see partAt), not one per letter.
TextSpan _partedSpan(String text, TextSpec spec, List<TextPart> parts,
    TextStyle style, Color? colorOverride, double scale) {
  var children = <TextSpan>[];
  var from = 0;
  TextPart? current = partAt(text, parts, 0);

  TextStyle styleFor(TextPart? part) {
    // An outline paragraph has a foreground paint, and a TextStyle cannot
    // carry that and a colour (it throws): take the part's size, family,
    // weight, slant and stroke, and never set color.
    if (style.foreground != null) {
      var width = part?.outlineWidth ?? spec.outlineWidth;
      var out = part == null
          ? style
          : style.copyWith(
              fontSize: part.scale == null
                  ? style.fontSize
                  : (style.fontSize ?? spec.fontSize) * part.scale!,
              fontFamily: part.family ?? style.fontFamily,
              fontWeight: part.weight == null
                  ? style.fontWeight
                  : FontWeight.values[((part.weight! ~/ 100) - 1)
                      .clamp(0, FontWeight.values.length - 1)],
              fontStyle: part.italic == null
                  ? style.fontStyle
                  : (part.italic! ? FontStyle.italic : FontStyle.normal),
            );
      // A zero width is drawn transparent: a zero-width stroke is a hairline.
      return out.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width * 2 * scale
          ..color = width <= 0
              ? const Color(0x00000000)
              : (part?.outlineColor ?? spec.outlineColor),
      );
    }
    if (part == null) return style;
    return style.copyWith(
      // colorOverride wins, so a one-colour preview (a ghost) has no colours.
      color: colorOverride ?? part.color ?? style.color,
      fontFamily: part.family ?? style.fontFamily,
      fontSize: part.scale == null
          ? style.fontSize
          : (style.fontSize ?? 0) * part.scale!,
      fontWeight: part.weight == null
          ? style.fontWeight
          : FontWeight.values[((part.weight! ~/ 100) - 1)
              .clamp(0, FontWeight.values.length - 1)],
      fontStyle: part.italic == null
          ? style.fontStyle
          : (part.italic! ? FontStyle.italic : FontStyle.normal),
    );
  }

  for (var i = 1; i <= text.length; i++) {
    var here = i == text.length ? null : partAt(text, parts, i);
    if (i == text.length || !identical(here, current)) {
      children.add(
          TextSpan(text: text.substring(from, i), style: styleFor(current)));
      from = i;
      current = here;
    }
  }
  return TextSpan(children: children, style: style);
}

/// _capHeightRatio is how much of a font's size the capitals and digits
/// occupy above the baseline. Flutter does not expose cap height; the faces
/// offered all fall between 0.70 and 0.73.
const double _capHeightRatio = 0.71;

/// paintCentredGlyphs draws [text] with its ink centred on [center], not
/// its laid-out box, which grows with line height: a team's numbers and
/// names share one TextSpec, so a line height set for the names would slide
/// the number out of its dot. `baseline - capHeight / 2` goes on the centre.
void paintCentredGlyphs(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Offset center, {
  double scale = 1,
}) {
  if (text.isEmpty) return;

  // Unconstrained, so "10" never wraps inside a dot barely wider than it.
  var painter = layoutText(text, spec, maxWidth: double.infinity, scale: scale);
  var baseline =
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  if (!baseline.isFinite) baseline = painter.height;

  var capHeight = spec.fontSize * scale * _capHeightRatio;
  var at = Offset(
    center.dx - painter.width / 2,
    center.dy - (baseline - capHeight / 2),
  );

  softFor(text, spec, maxWidth: double.infinity, scale: scale, fillWidth: false)
      ?.paint(canvas, at);
  if (spec.outlineWidth > 0) {
    layoutText(text, spec,
            maxWidth: double.infinity, scale: scale, outline: true)
        .paint(canvas, at);
  }
  paintTp(painter, canvas, at);
}

/// textRunBox is where a stretch of [text] lands inside [box], laid out as
/// paintTextInBox would, for drawing something behind part of a line (a
/// table chip). Null when the range is empty or outside the text.
Rect? textRunBox(String text, TextSpec spec, Rect box, int start, int end) {
  var shown = spec.textCase.apply(text);
  if (start < 0 || end > shown.length || end <= start || box.width <= 0) {
    return null;
  }

  var painter = layoutText(shown, spec, maxWidth: box.width, fillWidth: true);
  var boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end));
  if (boxes.isEmpty) return null;

  // The same vertical placement as textOffsetIn.
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  var out = boxes.first.toRect();
  for (var b in boxes.skip(1)) {
    out = out.expandToInclude(b.toRect());
  }
  return out.translate(box.left, box.top + dy);
}

/// _fades is whether the letters are painted with a gradient: one is set,
/// there is a box to run it across, and no override colour claims them.
bool _fades(TextSpec spec, Color? colorOverride, Rect? over) =>
    spec.fade != null && colorOverride == null && over != null && !over.isEmpty;

/// textStyleOf is one TextSpec as Flutter sees it, the one place a spec's
/// settings become a TextStyle (paintRunsInBox uses it per run too).
TextStyle textStyleOf(
  TextSpec spec, {
  double scale = 1,
  Color? colorOverride,
  bool outline = false,

  /// over is the box the words are drawn in, for a colour fading across it
  /// (a style is built before layout); null gives a flat colour.
  Rect? over,

  /// soft draws the shadow and glow with clear glyphs, a pass of its own: the
  /// order is shadow, outline, words, and a fill layer leaves the glow be.
  bool soft = false,
}) =>
    TextStyle(
      fontFamily: spec.fontFamily,
      fontSize: spec.fontSize * scale,
      fontWeight: spec.fontWeight,
      fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          spec.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: colorOverride ?? spec.color,
      letterSpacing: spec.letterSpacing * scale,
      height: spec.lineHeight,
      // A fade is a foreground shader, the outline's slot, so the outline
      // wins, as does an override: a TextStyle can't have color and both.
      color: soft
          ? const Color(0x00000000)
          : (outline || _fades(spec, colorOverride, over)
              ? null
              : (colorOverride ?? spec.color)),
      foreground: soft
          ? null
          : outline
              ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = spec.outlineWidth * 2 * scale
                ..color = spec.outlineColor)
              : _fades(spec, colorOverride, over)
                  ? (Paint()
                    ..shader = PaintSpec(spec.color, gradient: spec.fade)
                        .shaderFor(over!))
                  : null,
      shadows: soft ? softShadows(spec, scale) : null,
    );

/// softShadows is what falls behind the letters: the glow, then the shadow.
List<Shadow> softShadows(TextSpec spec, double scale) => [
      if (spec.glowBlur > 0)
        Shadow(
          color: spec.glowColor,
          blurRadius: spec.glowBlur * scale,
        ),
      if (spec.shadowBlur > 0 || spec.shadowDistance > 0)
        Shadow(
          color: spec.shadowColor,
          blurRadius: spec.shadowBlur * scale,
          offset: spec.shadowOffset * scale,
        ),
    ];

/// paintRunsInBox draws one line of differently styled stretches, laid out
/// and aligned as paintTextInBox would: one paragraph of spans, so the line
/// aligns as a whole. Used by table cells whose rules style parts.
double paintRunsInBox(
  ui.Canvas canvas,
  List<(String, TextSpec)> runs,
  TextSpec base,
  Rect box, {
  bool clip = false,
}) {
  if (runs.isEmpty || box.width <= 0) return 0;

  var painter = TextPainter(
    text: TextSpan(
      style: textStyleOf(base),
      children: [
        for (var (text, spec) in runs)
          TextSpan(text: spec.textCase.apply(text), style: textStyleOf(spec)),
      ],
    ),
    textAlign: base.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(minWidth: box.width, maxWidth: box.width);

  var dy = switch (base.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  if (clip) {
    canvas.save();
    canvas.clipRect(box);
  }
  paintTp(painter, canvas, Offset(box.left, box.top + dy));
  if (clip) canvas.restore();
  return painter.height;
}

/// drawnPixels renders [draw] into a [w] x [h] picture and reads it back as
/// RGBA bytes: premultiplied, or [straight].
Future<Uint8List> drawnPixels(int w, int h, void Function(ui.Canvas) draw,
    {bool straight = false}) async {
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  var image = await recorder.endRecording().toImage(w, h);
  try {
    var data = await image.toByteData(
        format: straight
            ? ui.ImageByteFormat.rawStraightRgba
            : ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
