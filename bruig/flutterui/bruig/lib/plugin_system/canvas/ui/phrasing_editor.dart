import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/phrasing.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/speech_device.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// phrasing_editor.dart is the Phrasing panel: a take's words shaped after
// it is spoken -- see media/phrasing.dart. Like Melodyne, for speech: each
// word a block, as high as it is said and as long as it lasts, its rise
// and fall drawn in it, its loudness a bar under it. A word is picked by
// clicking it, then dragged up or down for its pitch, its right edge along
// for its length, its bar for its loudness -- or set beside, with its
// inflection and the pause after it. It opens on the take as the voice
// said it, every word "as said", and shows in the effects strip as the
// clip editor does, from the Speech device's Phrasing button.

/// PhrasingEditor is the Phrasing panel, on the take the controller has
/// it open on.
class PhrasingEditor extends StatefulWidget {
  final CanvasController controller;
  const PhrasingEditor({required this.controller, super.key});

  @override
  State<PhrasingEditor> createState() => _PhrasingEditorState();
}

class _PhrasingEditorState extends State<PhrasingEditor> {
  int _picked = 0;

  /// A drag: the shape its word had when it began, and how far it has gone.
  WordShape _from = WordShape.plain;
  double _moved = 0;

  CanvasController get c => widget.controller;

  /// _shape changes the picked word -- [transient], part of a drag or a
  /// slider's move, which the controller's interaction makes one undo.
  void _shape(WordShape shape, {bool transient = false}) =>
      c.shapeWord(_picked, shape, transient: transient);

  void _dragStart(int word) {
    setState(() => _picked = word);
    _from = c.phrasingTake?.shapeOf(word) ?? WordShape.plain;
    _moved = 0;
    c.beginInteraction();
  }

  void _dragEnd() => c.endInteraction();

  @override
  Widget build(BuildContext context) {
    var take = c.phrasingTake;
    var at = c.phrasing;
    if (take == null || at == null) return const SizedBox();
    var look = MixerLook.of(context);
    var s = look.studio;
    var k = SpeechKit(s, look.colors);
    var spoken = take.asSpoken;
    var words = spoken.words;
    if (words.isEmpty) {
      return Center(
          child: Text("This take has no words to shape.",
              style: k.text(11, colour: s.muted)));
    }
    _picked = _picked.clamp(0, words.length - 1);
    var reading = c.readingOf(take);
    var shapes = [for (var i = 0; i < words.length; i++) take.shapeOf(i)];
    var hearingShaped = c.speechHeard == take.assetId;
    var hearingSpoken = c.speechHeard == spoken.assetId && !hearingShaped;

    // Its buttons, along the top: made smaller, never cut off, where the
    // room is short or the text large.
    var top = Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          k.button(hearingShaped ? "Stop" : "Hear as shaped",
              () => c.hearSlot(at.channel, at.line, at.slot),
              key: const ValueKey("phrasingHearShaped"),
              icon: hearingShaped ? Icons.stop : Icons.play_arrow,
              small: true),
          const SizedBox(width: 4),
          k.button(hearingSpoken ? "Stop" : "Hear as spoken",
              () => c.hearSlot(at.channel, at.line, at.slot, spoken: true),
              key: const ValueKey("phrasingHearSpoken"),
              icon: hearingSpoken ? Icons.stop : Icons.play_arrow,
              small: true),
          const SizedBox(width: 4),
          k.button("Reset all", take.shaped ? c.resetPhrasing : null,
              key: const ValueKey("phrasingReset"),
              icon: Icons.restart_alt,
              small: true,
              tip: "Every word as the voice said it"),
        ]),
      ),
    );

    var lanes = reading == null
        ? Center(
            child:
                Text("Reading the take…", style: k.text(11, colour: s.muted)))
        : _Lanes(
            words: words,
            shapes: shapes,
            reading: reading,
            seconds: spoken.length,
            picked: _picked,
            s: s,
            k: k,
            onPick: (i) => setState(() => _picked = i),
            onPitchStart: _dragStart,
            onPitch: (dy, st) {
              _moved += dy;
              _shape(
                  _from.copyWith(
                      pitch: _from.pitch + (-_moved / st * 2).round() / 2),
                  transient: true);
            },
            onLengthStart: _dragStart,
            onLength: (dx, width) {
              _moved += dx;
              var times = (width + _moved) / width;
              _shape(
                  _from.copyWith(
                      length: (_from.length * times * 20).round() / 20),
                  transient: true);
            },
            onLoudStart: _dragStart,
            onLoud: (dy, perDb) {
              _moved += dy;
              _shape(
                  _from.copyWith(
                      loudness: _from.loudness + (-_moved / perDb).round()),
                  transient: true);
            },
            onDragEnd: _dragEnd,
          );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            top,
            const SizedBox(height: 6),
            Expanded(child: lanes),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 250,
          child: _WordPanel(
            word: words[_picked],
            shape: shapes[_picked],
            s: s,
            k: k,
            onChanged: (shape) {
              c.beginInteraction();
              _shape(shape, transient: true);
            },
            onChangeEnd: c.endInteraction,
            onSet: _shape,
          ),
        ),
      ]),
    );
  }
}

/// _Lanes are the words: blocks for their pitch and length, bars under for
/// their loudness, laid out as shaped and scrolled sideways where the take
/// is longer than the room.
class _Lanes extends StatelessWidget {
  final List<TimedWord> words;
  final List<WordShape> shapes;
  final TakeReading reading;
  final double seconds;
  final int picked;
  final StudioColors s;
  final SpeechKit k;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onPitchStart, onLengthStart, onLoudStart;

  /// onPitch is a block dragged [dy] further, at [st] pixels a semitone;
  /// onLength its edge [dx] further, it being [width] wide when the drag
  /// began; onLoud its bar [dy] further, at [perDb] pixels a decibel.
  final void Function(double dy, double st) onPitch;
  final void Function(double dx, double width) onLength;
  final void Function(double dy, double perDb) onLoud;
  final VoidCallback onDragEnd;

  const _Lanes(
      {required this.words,
      required this.shapes,
      required this.reading,
      required this.seconds,
      required this.picked,
      required this.s,
      required this.k,
      required this.onPick,
      required this.onPitchStart,
      required this.onPitch,
      required this.onLengthStart,
      required this.onLength,
      required this.onLoudStart,
      required this.onLoud,
      required this.onDragEnd});

  static const _left = 44.0;
  static const _block = 34.0;

  @override
  Widget build(BuildContext context) {
    var laid = shapedWords(words, shapes, seconds);
    var total = seconds;
    for (var (i, w) in words.indexed) {
      total += (w.end - w.start) * (shapes[i].length - 1) + shapes[i].pause;
    }
    var loudest = reading.levels.fold(-60.0, math.max);
    return LayoutBuilder(builder: (context, box) {
      var px = math.max(120.0, (box.maxWidth - _left - 12) / total);
      var width = math.max(box.maxWidth, _left + total * px + 12);
      // The captions a line each, at the text's size; the loudness a
      // quarter of what is left, the pitch the rest.
      var caption = MediaQuery.textScalerOf(context).scale(10) * 1.4;
      var room = math.max(0.0, box.maxHeight - 2 * caption - 6);
      var loudH = (room * 0.25).clamp(20.0, 54.0);
      var pitchH = math.max(_block + 4, room - loudH);
      // Seven semitones either side of the voice's middle, in the lane.
      var st = math.max(4.0, (pitchH / 2 - _block / 2 - 2) / 7);
      var middle = pitchH / 2;
      // Thirty decibels under the loudest word, to six over.
      var perDb = (loudH - 4) / 36;

      Widget grid = CustomPaint(
          size: Size(width, pitchH),
          painter:
              _Grid(middle: middle, st: st, line: s.edge, faint: s.raised));
      // Three semitones apart where there is room to read them; else six.
      var label = MediaQuery.textScalerOf(context).scale(8.5) * 1.3;
      var labels = [
        for (var semis in [6, 3, 0, -3, -6])
          if (semis.abs() != 3 || 3 * st >= label)
            Positioned(
              left: 4,
              top: middle - semis * st - 12,
              child: Text(
                  semis == 0 ? "middle" : "${semis > 0 ? "+" : ""}$semis st",
                  style: k.mono(8.5, colour: s.muted)),
            ),
      ];
      var blocks = <Widget>[];
      var bars = <Widget>[];
      for (var (i, w) in words.indexed) {
        var shape = shapes[i];
        var x = _left + laid[i].start * px;
        var blockW = math.max(18.0, (laid[i].end - laid[i].start) * px);
        var mean = reading.meanOf(w);
        var y = middle -
            ((mean ?? reading.middle) - reading.middle + shape.pitch) * st -
            _block / 2;
        y = y.clamp(0.0, pitchH - _block);
        var isPicked = i == picked;
        var changed = !shape.isPlain;
        var ring = isPicked
            ? s.solo
            : changed
                ? s.on
                : s.edge;
        var fill = isPicked
            ? s.solo.withValues(alpha: 0.25)
            : changed
                ? s.on.withValues(alpha: 0.18)
                : s.raised;
        blocks.add(Positioned(
          left: x,
          top: y,
          width: blockW,
          height: _block,
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: ValueKey("phrasingWord-$i"),
                supportedDevices: dragPointers,
                onTap: () => onPick(i),
                onVerticalDragStart: (_) => onPitchStart(i),
                onVerticalDragUpdate: (d) => onPitch(d.delta.dy, st),
                onVerticalDragEnd: (_) => onDragEnd(),
                child: Container(
                  decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: ring, width: isPicked ? 2 : 1)),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                          painter: _Curve(
                              points: reading.pitchOf(w),
                              mean: mean,
                              inflection: shape.inflection,
                              colour: isPicked
                                  ? s.solo.withValues(alpha: 0.9)
                                  : s.displayLine)),
                    ),
                    Positioned(
                      left: 5,
                      bottom: 2,
                      right: 4,
                      child: Text(w.text,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: k.text(10.5, weight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
            // Its right edge: dragged along, it is drawn out or hurried.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 7,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  key: ValueKey("phrasingEdge-$i"),
                  supportedDevices: dragPointers,
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => onLengthStart(i),
                  onHorizontalDragUpdate: (d) => onLength(d.delta.dx, blockW),
                  onHorizontalDragEnd: (_) => onDragEnd(),
                ),
              ),
            ),
          ]),
        ));
        var level = (i < reading.levels.length ? reading.levels[i] : -60.0) -
            loudest +
            shape.loudness;
        var barH = ((level + 30) * perDb).clamp(4.0, loudH - 4);
        bars.add(Positioned(
          left: x,
          bottom: 2,
          width: math.max(6.0, blockW - 4),
          height: barH,
          child: GestureDetector(
            key: ValueKey("phrasingLoud-$i"),
            supportedDevices: dragPointers,
            onTap: () => onPick(i),
            onVerticalDragStart: (_) => onLoudStart(i),
            onVerticalDragUpdate: (d) => onLoud(d.delta.dy, perDb),
            onVerticalDragEnd: (_) => onDragEnd(),
            child: Container(
              decoration: BoxDecoration(
                color: isPicked
                    ? s.solo
                    : shape.loudness != 0
                        ? s.on
                        : s.meterLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ),
        ));
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: box.maxHeight,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: caption,
              child: Text(
                  "Pitch and length · drag a word up or down, or its edge "
                  "along",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: k.text(10, colour: s.muted)),
            ),
            Container(
              height: pitchH,
              decoration: BoxDecoration(
                  color: s.inset, borderRadius: BorderRadius.circular(5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [grid, ...labels, ...blocks]),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: caption,
              child: Text("Loudness · each word's level",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: k.text(10, colour: s.muted)),
            ),
            Container(
              height: loudH,
              decoration: BoxDecoration(
                  color: s.inset, borderRadius: BorderRadius.circular(5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: bars),
            ),
          ]),
        ),
      );
    });
  }
}

/// _Grid is the pitch lane's lines: the voice's middle, and three and six
/// semitones either side of it.
class _Grid extends CustomPainter {
  final double middle, st;
  final Color line, faint;
  _Grid(
      {required this.middle,
      required this.st,
      required this.line,
      required this.faint});

  @override
  void paint(Canvas canvas, Size size) {
    for (var semis in [6, 3, 0, -3, -6]) {
      var y = middle - semis * st;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = semis == 0 ? line : faint);
    }
  }

  @override
  bool shouldRepaint(_Grid old) =>
      old.middle != middle ||
      old.st != st ||
      old.line != line ||
      old.faint != faint;
}

/// _Curve is a word's rise and fall, drawn in its block: its readings
/// about its mean, as much of them as its inflection says, three pixels a
/// semitone; nothing where it was not voiced.
class _Curve extends CustomPainter {
  final List<double?> points;
  final double? mean;
  final double inflection;
  final Color colour;
  _Curve(
      {required this.points,
      required this.mean,
      required this.inflection,
      required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    var m = mean;
    if (m == null || points.isEmpty) return;
    var paint = Paint()
      ..color = colour
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    var path = Path();
    var drawing = false;
    var mid = size.height / 2 - 5;
    for (var (i, p) in points.indexed) {
      if (p == null) {
        drawing = false;
        continue;
      }
      var x = points.length == 1
          ? size.width / 2
          : 4 + i / (points.length - 1) * (size.width - 8);
      var y = (mid - (p - m) * inflection * 3).clamp(2.0, size.height - 2);
      if (drawing) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        drawing = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_Curve old) =>
      old.points != points ||
      old.mean != mean ||
      old.inflection != inflection ||
      old.colour != colour;
}

/// _WordPanel is the picked word's settings: each as said until moved.
class _WordPanel extends StatelessWidget {
  final TimedWord word;
  final WordShape shape;
  final StudioColors s;
  final SpeechKit k;

  /// onChanged is a slider moved -- part of a move that onChangeEnd ends;
  /// onSet a button's change, one of its own.
  final ValueChanged<WordShape> onChanged;
  final VoidCallback onChangeEnd;
  final ValueChanged<WordShape> onSet;

  const _WordPanel(
      {required this.word,
      required this.shape,
      required this.s,
      required this.k,
      required this.onChanged,
      required this.onChangeEnd,
      required this.onSet});

  @override
  Widget build(BuildContext context) {
    String signed(num v, String unit) =>
        "${v > 0 ? "+" : ""}${v is double && v != v.roundToDouble() ? v.toStringAsFixed(1) : v.round()}$unit";
    Widget slider(
            String label,
            String reading,
            double value,
            double min,
            double max,
            int divisions,
            String low,
            String high,
            WordShape Function(double v) change,
            {required Key key}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: k.text(11.5))),
            Text(reading,
                style: k.mono(10.5, colour: s.text.withValues(alpha: 0.8))),
          ]),
          SizedBox(
            height: 20,
            child: Slider(
              key: key,
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => onChanged(change(v)),
              onChangeEnd: (_) => onChangeEnd(),
            ),
          ),
          Row(children: [
            Expanded(
                child: Text(low,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: k.text(9, colour: s.muted))),
            Text(high, maxLines: 1, style: k.text(9, colour: s.muted)),
          ]),
          const SizedBox(height: 5),
        ]);

    var asSaid = "as said";
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: s.on,
        inactiveTrackColor: s.raised,
        thumbColor: s.on,
        overlayColor: s.on.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Container(
        decoration:
            BoxDecoration(border: Border(left: BorderSide(color: s.edge))),
        padding: const EdgeInsets.only(left: 10),
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text("“${word.text}”",
                    key: const ValueKey("phrasingPicked"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: k.text(13, weight: FontWeight.w700)),
              ),
              Text(
                  "${((word.end - word.start) * shape.length).toStringAsFixed(2)} s",
                  style: k.mono(10, colour: s.muted)),
            ]),
            const SizedBox(height: 6),
            slider(
                "Pitch",
                shape.pitch == 0 ? asSaid : signed(shape.pitch, " st"),
                shape.pitch,
                -6,
                6,
                24,
                "Lower",
                "Higher",
                (v) => shape.copyWith(pitch: v),
                key: const ValueKey("phrasingPitch")),
            slider(
                "Inflection",
                shape.inflection == 1
                    ? asSaid
                    : "${(shape.inflection * 100).round()}%",
                shape.inflection,
                0,
                2,
                20,
                "Flat",
                "More",
                (v) => shape.copyWith(inflection: v),
                key: const ValueKey("phrasingInflection")),
            slider(
                "Length",
                shape.length == 1 ? asSaid : "${(shape.length * 100).round()}%",
                shape.length,
                0.7,
                1.4,
                14,
                "Quicker",
                "Drawn out",
                (v) => shape.copyWith(length: v),
                key: const ValueKey("phrasingLength")),
            slider(
                "Pause after",
                shape.pause == 0
                    ? asSaid
                    : "+${(shape.pause * 1000).round()} ms",
                shape.pause,
                0,
                0.8,
                40,
                "None",
                "0.8 s",
                (v) => shape.copyWith(pause: v),
                key: const ValueKey("phrasingPause")),
            slider(
                "Loudness",
                shape.loudness == 0
                    ? asSaid
                    : signed(shape.loudness.round(), " dB"),
                shape.loudness,
                -12,
                6,
                18,
                "Quieter",
                "Louder",
                (v) => shape.copyWith(loudness: v),
                key: const ValueKey("phrasingLoudness")),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: k.button("Stress this word", () => onSet(shape.stressed),
                    key: const ValueKey("phrasingStress"),
                    icon: Icons.priority_high,
                    small: true,
                    tip: "A little higher, a little longer, a little "
                        "louder: a start, each as you set it after"),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: k.button("Reset word",
                    shape.isPlain ? null : () => onSet(WordShape.plain),
                    key: const ValueKey("phrasingResetWord"),
                    icon: Icons.undo,
                    small: true),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
