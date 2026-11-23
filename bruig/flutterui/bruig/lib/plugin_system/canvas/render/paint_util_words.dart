part of 'paint_util.dart';

// One paragraph laid out: the value every place that draws or measures a
// text's words asks, so what is measured is what is drawn. See
// ARCHITECTURE.md, "Text: how a paragraph is laid out". Part of
// paint_util.dart.

/// WordsPass is which of a paragraph's drawings a layout is for: the
/// letters, the outline drawn behind them (a second painter, not a stroke:
/// a stroke is centred on the glyph edge and would thin the letterform), or
/// the shadow and the glow on their own, with the letters themselves left
/// clear (see textStyleOf's soft).
enum WordsPass { letters, outline, soft }

/// LaidOutWords is one paragraph laid out: the words as drawn, in their
/// type and parts, at a width. Made only by layOutWords (or layOutGlyph,
/// for a letter on a line), and shared: read it, never change it.
class LaidOutWords {
  /// text is the words as drawn: the case applied.
  final String text;

  /// parts are the runs drawn differently, counted in [text].
  final List<TextPart> parts;

  /// maxWidth is the width it was given to wrap in; infinite for none.
  final double maxWidth;

  /// painter is the paragraph as Flutter laid it out, for what only it
  /// does (a vector file's words, an animator's layer).
  final TextPainter painter;

  LaidOutWords._(this.text, this.parts, this.maxWidth, this.painter);

  Size get size => painter.size;
  double get width => painter.width;
  double get height => painter.height;

  List<ui.LineMetrics>? _lines;

  /// lines are each line's box and baseline, top to bottom.
  List<ui.LineMetrics> get lines => _lines ??= painter.computeLineMetrics();

  /// boxesOf is the rectangles characters [start] to [end] of [text] take,
  /// one or more a line, in the paragraph's own coordinates.
  List<Rect> boxesOf(int start, int end) => [
        for (var b in painter.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end)))
          b.toRect(),
      ];

  /// boxOf is one rectangle round characters [start] to [end], or null
  /// where they take no room.
  Rect? boxOf(int start, int end) {
    var boxes = boxesOf(start, end);
    if (boxes.isEmpty) return null;
    var out = boxes.first;
    for (var b in boxes.skip(1)) {
      out = out.expandToInclude(b);
    }
    return out;
  }

  /// characterAt is where in [text] the point [at] falls, in the
  /// paragraph's own coordinates.
  int characterAt(Offset at) => painter.getPositionForOffset(at).offset;

  /// linesIn is how many of the lines show in [columns] columns [height]
  /// tall: whole lines, packed as paintTextInColumns packs them, a blank
  /// line passed over at the top of a later column when [tidy].
  int linesIn(double height, {int columns = 1, bool tidy = false}) {
    var runs =
        columnRuns(lines, height, math.max(1, columns), noBlankStart: tidy);
    return runs.isEmpty ? 0 : runs.last.$2;
  }

  /// charactersIn is how many characters of [text] show in [columns]
  /// columns [height] tall (see linesIn): what a box in a chain passes on.
  int charactersIn(double height, {int columns = 1, bool tidy = false}) {
    if (lines.isEmpty) return 0;
    var shown = linesIn(height, columns: columns, tidy: tidy);
    if (shown >= lines.length) return text.length;
    if (shown <= 0) return 0;

    // The character the last line drawn ends at. Asked of the paragraph rather
    // than counted, because where a line breaks is the paragraph's business.
    var last = lines[shown - 1];
    var end = characterAt(Offset(maxWidth + 1000, last.baseline));
    if (end <= 0) return 0;

    // Whitespace at the break belongs to the line that broke, or the next box
    // starts with a crooked first line.
    while (end < text.length && text[end].trim().isEmpty && text[end] != "\n") {
      end++;
    }
    if (end < text.length && text[end] == "\n") end++;
    return math.min(end, text.length);
  }

  /// paint draws the paragraph at [at] as a picture, whatever the canvas.
  void paint(ui.Canvas canvas, Offset at) => painter.paint(canvas, at);

  /// paintAsWords draws it at [at], as words a vector file can hold where
  /// the canvas is one (paintTp).
  void paintAsWords(ui.Canvas canvas, Offset at) =>
      paintTp(painter, canvas, at);
}

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
  WordsPass,
  bool,
  // The size of the box a fading colour runs across, not its place: the
  // shader is in paragraph coordinates, and nothing else carries the height.
  Size?,
  // The parts, written out, and the words they count in where those are not
  // the words drawn.
  String,
  String?,
);

final _layouts = <_LayoutKey, LaidOutWords>{};

/// _partsKeys remembers a parts list written out for the key: a list never
/// changes once made, and writing it out on every lookup cost more than
/// the lookup.
final _partsKeys = Expando<String>();

/// _glyphKeys is the same for the one part over a letter on a line.
final _glyphKeys = Expando<String>();

String _partsKey(List<TextPart> parts) =>
    [for (var p in parts) p.toJson()].toString();

/// _layoutCap is the number of paragraphs kept (a busy table is a few
/// hundred cells); the oldest inserted go first.
const _layoutCap = 512;

/// layOutWords is [text] laid out in [spec] with its [parts], wrapped at
/// [maxWidth] (infinite for one line): the one place a paragraph is laid
/// out. The parts are required, an empty list where there are none, so
/// nothing measures words without the parts they are drawn with.
LaidOutWords layOutWords(
  String text,
  TextSpec spec, {
  required List<TextPart> parts,
  required double maxWidth,
  double scale = 1,

  /// colorOverride draws every letter in one colour (a ghost), parts' too.
  Color? colorOverride,
  WordsPass pass = WordsPass.letters,

  /// fillWidth lays the paragraph out at exactly [maxWidth] rather than its
  /// intrinsic width: a TextPainter aligns within its own width, so without
  /// this every alignment looks like left. Measuring wants it off.
  bool fillWidth = false,

  /// over is the box the words are drawn in, for a fade (see textStyleOf).
  Rect? over,

  /// partsIn is the words [parts] count in, where [text] stands in for
  /// them letter for letter (a scramble's letters, its spaces in place);
  /// [text] itself where null.
  String? partsIn,
}) =>
    _layOut(
        text,
        spec,
        parts,
        parts.isEmpty ? "" : (_partsKeys[parts] ??= _partsKey(parts)),
        (shown) => parts.isEmpty
            ? const []
            : partRuns(
                partsIn == null ? shown : spec.textCase.apply(partsIn), parts),
        maxWidth: maxWidth,
        scale: scale,
        colorOverride: colorOverride,
        pass: pass,
        fillWidth: fillWidth,
        over: over,
        partsIn: partsIn);

/// layOutGlyph is one letter laid out on its own, in [part] where one is
/// over it, as text on a line is placed and drawn a letter at a time: the
/// same layout as a paragraph's, its one run in its part.
LaidOutWords layOutGlyph(String glyph, TextSpec spec,
    {required TextPart? part,
    double scale = 1,
    WordsPass pass = WordsPass.letters}) {
  if (part == null) {
    return layOutWords(glyph, spec,
        parts: const [], maxWidth: double.infinity, scale: scale, pass: pass);
  }
  return _layOut(
      glyph,
      spec,
      [part],
      "whole ${_glyphKeys[part] ??= _partsKey([part])}",
      (shown) => [(start: 0, end: shown.length, part: part)],
      maxWidth: double.infinity,
      scale: scale,
      pass: pass);
}

LaidOutWords _layOut(String text, TextSpec spec, List<TextPart> parts,
    String partsKey, List<PartRun> Function(String shown) runsOf,
    {required double maxWidth,
    double scale = 1,
    Color? colorOverride,
    WordsPass pass = WordsPass.letters,
    bool fillWidth = false,
    Rect? over,
    String? partsIn}) {
  var key = (
    text,
    spec,
    maxWidth,
    scale,
    colorOverride,
    pass,
    fillWidth,
    // The gradient is baked into the style. See _LayoutKey.
    over?.size,
    partsKey,
    partsIn,
  );
  var hit = _layouts[key];
  if (hit != null) return hit;

  // The case transform is idempotent and applied here, so none can forget it.
  var shown = spec.textCase.apply(text);

  var style = textStyleOf(spec,
      scale: scale,
      colorOverride: colorOverride,
      outline: pass == WordsPass.outline,
      soft: pass == WordsPass.soft,
      over: over);

  var painter = TextPainter(
    text: partsKey.isEmpty
        ? TextSpan(text: shown, style: style)
        : styledWords(shown, runsOf(shown), style, spec,
            pass: pass, colorOverride: colorOverride, scale: scale),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  var width = math.max(0.0, maxWidth);
  painter.layout(
      minWidth: fillWidth && width.isFinite ? width : 0, maxWidth: width);

  var out = LaidOutWords._(shown, parts, width, painter);
  if (_layouts.length >= _layoutCap) {
    retirePainter(_layouts.remove(_layouts.keys.first)!.painter);
  }
  _layouts[key] = out;
  return out;
}

/// PartRun is a stretch of words drawn alike: characters [start] to [end],
/// in [part], or as the paragraph where null.
typedef PartRun = ({int start, int end, TextPart? part});

/// partRuns cuts [text] into runs with the same part (see partAt): one a
/// change, not one a letter.
List<PartRun> partRuns(String text, List<TextPart> parts) {
  var out = <PartRun>[];
  var from = 0;
  TextPart? current = partAt(text, parts, 0);
  for (var i = 1; i <= text.length; i++) {
    var here = i == text.length ? null : partAt(text, parts, i);
    if (i == text.length || !identical(here, current)) {
      out.add((start: from, end: i, part: current));
      from = i;
      current = here;
    }
  }
  return out;
}

/// styledWords builds the paragraph from [runs] of [text], so a few words
/// can differ: one span a run, styled by partStyle over [style].
TextSpan styledWords(
    String text, List<PartRun> runs, TextStyle style, TextSpec spec,
    {required WordsPass pass, Color? colorOverride, double scale = 1}) {
  return TextSpan(style: style, children: [
    for (var run in runs)
      TextSpan(
          text: text.substring(run.start, run.end),
          style: partStyle(style, spec, run.part,
              pass: pass, colorOverride: colorOverride, scale: scale)),
  ]);
}

/// partStyle is [style] with what [part] changes: its colour, size, face,
/// weight and slant, and in an outline pass its stroke. The one place a
/// part's settings reach the type, for every way words are set and for the
/// editor laid over them; a new thing a part can change is added here.
TextStyle partStyle(TextStyle style, TextSpec spec, TextPart? part,
    {required WordsPass pass, Color? colorOverride, double scale = 1}) {
  if (pass == WordsPass.outline) {
    // An outline paragraph has a foreground paint, and a TextStyle cannot
    // carry that and a colour (it throws): take the part's size, family,
    // weight, slant and stroke, and never set color.
    var width = part?.outlineWidth ?? spec.outlineWidth;
    var out = part == null ? style : _shapedBy(style, spec, part, scale);
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
  var out = _shapedBy(style, spec, part, scale);
  // The shadow and glow are drawn with clear letters, and a fade is a paint
  // a colour cannot sit beside: neither takes the part's colour.
  if (pass == WordsPass.soft || style.foreground != null) return out;
  // colorOverride wins, so a one-colour preview (a ghost) has no colours.
  return out.copyWith(color: colorOverride ?? part.color ?? style.color);
}

/// _shapedBy is [style] in [part]'s size, face, weight and slant.
TextStyle _shapedBy(
        TextStyle style, TextSpec spec, TextPart part, double scale) =>
    style.copyWith(
      fontFamily: part.family ?? style.fontFamily,
      fontSize: part.scale == null
          ? style.fontSize
          : (style.fontSize ?? spec.fontSize * scale) * part.scale!,
      fontWeight: part.weight == null
          ? style.fontWeight
          : TextSpec.weightOf(part.weight!),
      fontStyle: part.italic == null
          ? style.fontStyle
          : (part.italic! ? FontStyle.italic : FontStyle.normal),
    );

/// _sizingOf is what in [parts] can change how big the words come out, as a
/// key: a list is a new one on every frame, so it cannot be one itself.
/// Beside partStyle, as a thing a part changes that changes the size of
/// the words is added to both (fitFontSize keys its answers on this).
String _sizingOf(List<TextPart> parts) => [
      for (var p in parts)
        if (p.scale != null ||
            p.family != null ||
            p.weight != null ||
            p.italic != null)
          "${p.unit.index} ${p.from} ${p.to} ${p.scale} ${p.family} "
              "${p.weight} ${p.italic}",
    ].join(";");
