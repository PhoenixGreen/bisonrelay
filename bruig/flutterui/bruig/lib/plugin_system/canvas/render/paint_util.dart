import 'dart:async';
import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/outline_points.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';

part 'paint_util_text_marks.dart';
part 'paint_util_box.dart';
part 'paint_util_shapes.dart';
part 'paint_util_stroke.dart';
part 'paint_util_columns.dart';
part 'paint_util_text_on_path.dart';
part 'paint_util_words.dart';

// paint_util.dart is the drawing every element does the same way: laying
// out a string, filling a box, turning a shape's name into a path. Every
// text drawer goes through layoutText, so outline, shadow, spacing and line
// height are implemented once. Nothing here touches a BuildContext or a
// theme: an export must not depend on the app's theme.

/// _dashed is outlines already cut into dashes, by what they outline and
/// where: cutting one is dozens of path extractions, and an empty element's
/// placeholder was drawn a dash at a time every frame.
final _dashed = <(String, Rect, double, double), ui.Path>{};
const _dashedCap = 64;

/// dashedOutline is [outline] cut into dashes [on] long, one starting every
/// [every], as one path. [shape] names what [outline] draws round [box]:
/// two outlines with the same name and box must be the same.
ui.Path dashedOutline(String shape, Rect box, double on, double every,
    ui.Path Function() outline) {
  var key = (shape, box, on, every);
  if (_dashed[key] case var hit?) return hit;
  if (_dashed.length >= _dashedCap) _dashed.remove(_dashed.keys.first);
  var dashes = ui.Path();
  for (var m in outline().computeMetrics()) {
    for (var d = 0.0; d < m.length; d += every) {
      dashes.addPath(m.extractPath(d, d + on), Offset.zero);
    }
  }
  return _dashed[key] = dashes;
}

/// retirePainter disposes [painter], which a cache has let go of, once the
/// paint going on is over: a painter handed out earlier in the same paint
/// can be the oldest kept, and so the one let go, and still be drawn with.
/// Caches' painters are never kept past a paint by their callers.
void retirePainter(TextPainter painter) {
  if (_retired.isEmpty) {
    scheduleMicrotask(() {
      for (var p in _retired) {
        p.dispose();
      }
      _retired.clear();
    });
  }
  _retired.add(painter);
}

final _retired = <TextPainter>[];

/// clearTextLayouts lets go of every text laid out and kept.
void clearTextLayouts() {
  for (var words in _layouts.values) {
    words.painter.dispose();
  }
  _layouts.clear();
  for (var painter in _labels.values) {
    painter.dispose();
  }
  _labels.clear();
  _fits.clear();
}

// _labels memoises short labels drawn in one style -- a knob's name, a line
// number, a button's word -- which the element painters used to lay out
// afresh every frame, at about a hundred times the cost of finding them
// here. Keyed on plain values (a colour as its ARGB, a weight as its number),
// never on a TextStyle, whose hash is dearer than the lookup.
typedef _LabelKey = (
  String,
  double,
  int,
  String?,
  int,
  bool,
  double?,
  double?,
  int?,
  String?,
  int,
  double,
);

final _labels = <_LabelKey, TextPainter>{};

/// _labelCap is the number of labels kept: a synth rack and a few code
/// panels draw a few hundred.
const _labelCap = 2048;

/// labelPainter is [text] laid out in one style, as a painter draws a label:
/// [size] and [colour], in [family] (the app's default where null) at
/// [weight], with [spacing] and [height] where given, [maxLines] and
/// [ellipsis], aligned by [align] within [maxWidth]. The painter is shared:
/// paint and measure it, never dispose it or lay it out again.
TextPainter labelPainter(
  String text, {
  required double size,
  required Color colour,
  String? family,
  FontWeight weight = FontWeight.normal,
  bool italic = false,
  double? spacing,
  double? height,
  int? maxLines,
  String? ellipsis,
  TextAlign align = TextAlign.start,
  double maxWidth = double.infinity,
}) {
  var key = (
    text,
    size,
    colour.toARGB32(),
    family,
    weight.value,
    italic,
    spacing,
    height,
    maxLines,
    ellipsis,
    align.index,
    maxWidth,
  );
  var hit = _labels[key];
  if (hit != null) return hit;
  var painter = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: family,
            fontSize: size,
            fontWeight: weight,
            fontStyle: italic ? FontStyle.italic : null,
            letterSpacing: spacing,
            height: height,
            color: colour)),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: maxLines,
    ellipsis: ellipsis,
  )..layout(maxWidth: maxWidth);
  if (_labels.length >= _labelCap) {
    retirePainter(_labels.remove(_labels.keys.first)!);
  }
  _labels[key] = painter;
  return painter;
}

/// layoutText is [text] laid out in [spec] where it has no parts (a label,
/// a cell, a chart's title): layOutWords with none. [outline] lays out the
/// outline drawn behind and [soft] the shadow and glow alone (WordsPass).
TextPainter layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,
  bool soft = false,
  bool fillWidth = false,
  Rect? over,
}) =>
    layOutWords(text, spec,
            parts: const [],
            maxWidth: maxWidth,
            scale: scale,
            colorOverride: colorOverride,
            pass: outline
                ? WordsPass.outline
                : (soft ? WordsPass.soft : WordsPass.letters),
            fillWidth: fillWidth,
            over: over)
        .painter;

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
LaidOutWords? outlineFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    required List<TextPart> parts,
    TextAnimation? animation,
    double reveal = 1}) {
  var outlineSpec =
      outlineSpecFor(spec, parts: parts, animation: animation, reveal: reveal);
  if (outlineSpec == null) return null;
  return layOutWords(text, outlineSpec,
      parts: parts,
      maxWidth: maxWidth,
      scale: scale,
      pass: WordsPass.outline,
      fillWidth: true);
}

/// softFor lays out the shadow and glow alone (the words with clear glyphs,
/// so it lines up), or null with neither. See textStyleOf's soft.
LaidOutWords? softFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    bool fillWidth = true,
    required List<TextPart> parts}) {
  if (!spec.softPasses) return null;
  return layOutWords(text, spec,
      parts: parts,
      maxWidth: maxWidth,
      scale: scale,
      pass: WordsPass.soft,
      fillWidth: fillWidth);
}

/// paintTextInBox lays [text] out inside [box] and draws it, honouring both
/// alignments and the outline, and returns the height it took: words with
/// no parts (a label, a cell, a chart's title), paintWordsInBox with none.
/// [animation] and [reveal] draw it part way through arriving
/// (text_animator.dart).
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
  CanvasImageSource? images,
}) =>
    paintWordsInBox(canvas, text, spec, box,
        parts: const [],
        scale: scale,
        colorOverride: colorOverride,
        clip: clip,
        animation: animation,
        reveal: reveal,
        images: images);

/// paintWordsInBox is paintTextInBox for words drawn with [parts]: the
/// runs drawn differently (a word in another colour, a phrase in bold),
/// an empty list for none.
double paintWordsInBox(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box, {
  required List<TextPart> parts,
  double scale = 1,
  Color? colorOverride,
  bool clip = false,
  TextAnimation? animation,
  double reveal = 1,

  /// timings are where each part arriving alone has got (TextPartAnimation).
  List<PartTiming> timings = const [],

  /// asOne makes the parts arrive with everything, as on the way out.
  bool asOne = false,

  /// images is where a picture used as a fill comes from. See TextFill.
  CanvasImageSource? images,
}) {
  if (text.isEmpty || box.width <= 0) return 0;

  var words = layOutWords(text, spec,
      parts: parts,
      maxWidth: box.width,
      scale: scale,
      colorOverride: colorOverride,
      fillWidth: true,
      // So a fade runs across the box the words are drawn in.
      over: box);

  var offset = textOffsetIn(box, words.painter, spec);

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
  paintPartMarks(canvas, words, parts, spec, offset,
      behind: true,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  // drawn draws the paragraph, through the animator whenever anything moves
  // (an arrival under way, a motion that [keeps] something, a part arriving
  // on its own). A closure because a filled paragraph is drawn twice, once
  // per TextDrawPhase, by the same code so the passes stay in register.
  void drawn({TextDrawPhase phase = TextDrawPhase.all}) {
    if (animation != null &&
        ((animation.on && (reveal < 1 || animation.keeps)) ||
            (!asOne && partsAnimate(parts)))) {
      paintAnimatedText(canvas, words, spec, offset, animation, reveal,
          maxWidth: box.width,
          outline: outline,
          soft: soft,
          timings: timings,
          asOne: asOne,
          phase: phase);
      return;
    }
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) words.paintAsWords(canvas, offset);
  }

  if (!spec.fill.on) {
    drawn();
  } else {
    // Outline and soft passes first, outside the fill's layer: own colours.
    drawn(phase: TextDrawPhase.behind);
    paintThroughText(canvas, box, spec.fill, images,
        () => drawn(phase: TextDrawPhase.letters),
        animation: animation, reveal: reveal, moving: offset & words.size);
  }

  paintPartMarks(canvas, words, parts, spec, offset,
      behind: false,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  if (clip) canvas.restore();
  return words.height;
}

/// fitFontSize is the largest size at which [text] fits inside [box], for
/// autoSize: a bisection, since wrapped height steps as words change lines.
/// [columns] is how many columns it flows into; [box] is one column's box.
/// [parts] are the runs it is drawn with, measured since a part may be
/// another size.
/// _fits keeps fitFontSize's answers. An auto-sized text asked it on every
/// frame, and each answer is fourteen paragraphs laid out and looked up.
final _fits = <(String, TextSpec, Size, int, String), double>{};

/// _fitCap is the number of answers kept: one a text and box size.
const _fitCap = 1024;

double fitFontSize(String text, TextSpec spec, Size box,
    {int columns = 1, required List<TextPart> parts}) {
  var key = (text, spec, box, columns, _sizingOf(parts));
  if (_fits[key] case var hit?) return hit;
  if (_fits.length >= _fitCap) _fits.remove(_fits.keys.first);
  return _fits[key] = _fitFontSize(text, spec, box, columns, parts);
}

double _fitFontSize(
    String text, TextSpec spec, Size box, int columns, List<TextPart> parts) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return spec.fontSize;
  var count = math.max(1, columns);
  var low = 4.0, high = box.height * 2 * count;
  for (var i = 0; i < 14; i++) {
    var mid = (low + high) / 2;
    var words = layOutWords(text, spec.copyWith(fontSize: mid),
        parts: parts, maxWidth: box.width);
    if (words.width > box.width + 0.5) {
      high = mid;
      continue;
    }
    if (count == 1) {
      words.height <= box.height ? low = mid : high = mid;
      continue;
    }
    // Against the real packing, since a column holds whole lines only.
    words.linesIn(box.height, columns: count) >= words.lines.length
        ? low = mid
        : high = mid;
  }
  return low;
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

  softFor(text, spec,
      maxWidth: double.infinity,
      scale: scale,
      fillWidth: false,
      parts: const [])?.paint(canvas, at);
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

/// layOutRuns is one line of differently styled stretches laid out as one
/// paragraph of spans, each in its own case: what paintRunsInBox draws, and
/// what measures the same runs asks, so the two cannot differ. At [width]
/// it fills that width, aligned as [base] says; without, it is as wide as
/// its words. The caller disposes of it.
TextPainter layOutRuns(List<(String, TextSpec)> runs, TextSpec base,
        {double? width}) =>
    TextPainter(
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
    )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);

/// paintRunsInBox draws one line of differently styled stretches, laid out
/// and aligned as paintTextInBox would: one paragraph of spans, so the line
/// aligns as a whole. Used by table cells whose rules style parts, and a
/// counter's number with its words.
double paintRunsInBox(
  ui.Canvas canvas,
  List<(String, TextSpec)> runs,
  TextSpec base,
  Rect box, {
  bool clip = false,
}) {
  if (runs.isEmpty || box.width <= 0) return 0;

  var painter = layOutRuns(runs, base, width: box.width);

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
  var height = painter.height;
  painter.dispose();
  return height;
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
