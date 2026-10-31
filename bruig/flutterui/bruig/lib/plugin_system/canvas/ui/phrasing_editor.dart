import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/phrasing.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/speech_device.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// phrasing_editor.dart is Phrasing: a take's words shaped after it is
// spoken -- see media/phrasing.dart. Like Melodyne, for speech: each word a
// block, as high as it is said and as long as it lasts, its rise and fall
// drawn in it, its loudness a bar under it. Words are picked by clicking
// -- shift or command for more, or a box dragged round them -- then
// dragged up or down for their pitch, a right edge along for their length,
// a bar for their loudness, or set in PhrasingWordPanel. A pinch, or the
// buttons, zoom in on the time or, with option, the pitch; a click on the
// ruler puts the playhead where hearing starts.
//
// It shows in the Speech device in place of its sections, from the
// Phrasing button in the device's header: PhrasingLanes where the voices
// and sections were, PhrasingWordPanel where the feel was.

/// PhrasingLanes are the take's words, as blocks and bars, with what zooms
/// them and hears them.
class PhrasingLanes extends StatefulWidget {
  final CanvasController controller;
  const PhrasingLanes({required this.controller, super.key});

  @override
  State<PhrasingLanes> createState() => _PhrasingLanesState();
}

class _PhrasingLanesState extends State<PhrasingLanes>
    with SingleTickerProviderStateMixin {
  /// How far zoomed in: on the time, from the whole take in the room; on
  /// the pitch, from seven semitones either side of the voice's middle.
  double _timeZoom = 1, _pitchZoom = 1;

  /// _playhead is where hearing starts, in the take as shaped, seconds.
  double _playhead = 0;

  final _across = ScrollController();
  final _down = ScrollController();
  final _focus = FocusNode(debugLabel: "phrasing");
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  /// A drag: the picked words' shapes when it began, and how far it has
  /// gone.
  Map<int, WordShape> _from = const {};
  double _moved = 0;

  /// A box being dragged round words, in the pitch lane's own place, and
  /// whether it adds to those picked -- and those picked when it began.
  Rect? _box;
  Offset _boxFrom = Offset.zero;
  bool _boxAdds = false;
  Set<int> _boxHad = const {};

  /// A pinch: the zoom when it began.
  double _pinchFrom = 1;

  /// Whether the pitch lane has been scrolled to the voice's middle, as it
  /// is when it opens and when it is fitted again.
  bool _centred = false;

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _ticker.dispose();
    _across.dispose();
    _down.dispose();
    _focus.dispose();
    super.dispose();
  }

  static bool get _adding =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _pick(int word) {
    _focus.requestFocus();
    c.pickWords([word], adding: _adding);
  }

  /// _dragStart begins a drag on [word]: it and the others picked, or --
  /// a word not picked -- it alone.
  void _dragStart(int word) {
    _focus.requestFocus();
    if (!c.phrasingPicked.contains(word)) c.pickWords([word]);
    var take = c.phrasingTake;
    if (take == null) return;
    _from = {for (var w in c.phrasingPicked) w: take.shapeOf(w)};
    _moved = 0;
    c.beginInteraction();
  }

  void _drag(WordShape Function(WordShape from) change) =>
      c.shapeWords({for (var e in _from.entries) e.key: change(e.value)},
          transient: true);

  void _dragEnd() {
    _from = const {};
    c.endInteraction();
  }

  /// _zoom zooms the time by [time] times, and the pitch by [pitch],
  /// keeping what is at [about] -- in the lanes' view -- where it is.
  void _zoom({double time = 1, double pitch = 1, Offset? about}) {
    var oldTime = _timeZoom, oldPitch = _pitchZoom;
    var nextTime = (_timeZoom * time).clamp(0.5, 16.0);
    var nextPitch = (_pitchZoom * pitch).clamp(0.5, 6.0);
    if (nextTime == oldTime && nextPitch == oldPitch) return;
    setState(() {
      _timeZoom = nextTime;
      _pitchZoom = nextPitch;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_across.hasClients && nextTime != oldTime) {
        var x = about?.dx ?? _across.position.viewportDimension / 2;
        var at = (_across.offset + x) * nextTime / oldTime - x;
        _across.jumpTo(at.clamp(0.0, _across.position.maxScrollExtent));
      }
      if (_down.hasClients && nextPitch != oldPitch) {
        var y = about?.dy ?? _down.position.viewportDimension / 2;
        var at = (_down.offset + y) * nextPitch / oldPitch - y;
        _down.jumpTo(at.clamp(0.0, _down.position.maxScrollExtent));
      }
    });
  }

  void _fit() => setState(() {
        _timeZoom = 1;
        _pitchZoom = 1;
        _centred = false;
      });

  /// _zooming is the lanes listening for a zoom: a trackpad's pinch, or a
  /// scroll with command or control held -- the time -- or option -- the
  /// pitch. Put inside each scrolling view, so it hears a zoom before the
  /// view takes it for a scroll.
  Widget _zooming(Widget child) => Listener(
        onPointerPanZoomStart: (_) => _pinchFrom =
            HardwareKeyboard.instance.isAltPressed ? _pitchZoom : _timeZoom,
        onPointerPanZoomUpdate: (e) {
          if (e.scale == 1) return;
          if (HardwareKeyboard.instance.isAltPressed) {
            _zoom(
                pitch: _pinchFrom * e.scale / _pitchZoom,
                about: e.localPosition);
          } else {
            _zoom(
                time: _pinchFrom * e.scale / _timeZoom, about: e.localPosition);
          }
        },
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          var keys = HardwareKeyboard.instance;
          var time = keys.isMetaPressed || keys.isControlPressed;
          var pitch = keys.isAltPressed;
          if (!time && !pitch) return;
          GestureBinding.instance.pointerSignalResolver.register(e, (e) {
            var by = math.exp(-(e as PointerScrollEvent).scrollDelta.dy / 300);
            pitch
                ? _zoom(pitch: by, about: e.localPosition)
                : _zoom(time: by, about: e.localPosition);
          });
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var k = SpeechKit(s, look.colors);
    var at = c.phrasing;
    var take = c.phrasingTake;
    if (at == null) return const SizedBox();
    if (take == null) {
      return Center(
          child: Text(
              "Slot ${String.fromCharCode(65 + at.slot)} of section "
              "${at.line + 1} has no take: speak into it, or pick another.",
              textAlign: TextAlign.center,
              style: k.text(11, colour: s.muted)));
    }
    var spoken = take.asSpoken;
    var words = spoken.words;
    var reading = c.readingOf(take);
    if (words.isEmpty || reading == null) {
      return Center(
          child: Text(
              words.isEmpty
                  ? "This take has no words to shape."
                  : "Reading the take…",
              style: k.text(11, colour: s.muted)));
    }
    var shapes = [for (var i = 0; i < words.length; i++) take.shapeOf(i)];
    var laid = shapedWords(words, shapes, spoken.length);
    var total = spoken.length;
    for (var (i, w) in words.indexed) {
      total += (w.end - w.start) * (shapes[i].length - 1) + shapes[i].pause;
    }
    _playhead = _playhead.clamp(0.0, total);

    // What is being heard, and how far in -- as shaped, where it is the
    // take as spoken being heard.
    var hearingShaped = c.speechHeard == take.assetId;
    var hearingSpoken = c.speechHeard == spoken.assetId && !hearingShaped;
    var hearing = hearingShaped || hearingSpoken;
    double? heard;
    if (c.heardSeconds case var t? when hearing) {
      heard = hearingShaped ? t : phrasingShapedAt(t, words, laid);
    }
    if (hearing != _ticker.isActive) {
      hearing ? _ticker.start() : _ticker.stop();
    }

    Widget zoomButton(String tip, IconData icon, VoidCallback onTap,
            {required Key key}) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icon, size: 15, color: s.text),
            ),
          ),
        );
    var zoomRow = Row(mainAxisSize: MainAxisSize.min, children: [
      Text("Time", style: k.text(10, colour: s.muted)),
      zoomButton(
          "Zoom out on the time", Icons.zoom_out, () => _zoom(time: 1 / 1.5),
          key: const ValueKey("phrasingTimeOut")),
      zoomButton("Zoom in on the time -- or pinch", Icons.zoom_in,
          () => _zoom(time: 1.5),
          key: const ValueKey("phrasingTimeIn")),
      const SizedBox(width: 6),
      Text("Pitch", style: k.text(10, colour: s.muted)),
      zoomButton(
          "Zoom out on the pitch", Icons.zoom_out, () => _zoom(pitch: 1 / 1.5),
          key: const ValueKey("phrasingPitchOut")),
      zoomButton("Zoom in on the pitch -- or pinch with option held",
          Icons.zoom_in, () => _zoom(pitch: 1.5),
          key: const ValueKey("phrasingPitchIn")),
      const SizedBox(width: 4),
      zoomButton("All of it in view", Icons.fit_screen, _fit,
          key: const ValueKey("phrasingFit")),
    ]);
    var hearRow = Row(mainAxisSize: MainAxisSize.min, children: [
      k.button(hearingShaped ? "Stop" : "Hear as shaped",
          () => c.hearSlot(at.channel, at.line, at.slot, at: _playhead),
          key: const ValueKey("phrasingHearShaped"),
          icon: hearingShaped ? Icons.stop : Icons.play_arrow,
          small: true,
          tip: "From the playhead"),
      const SizedBox(width: 4),
      k.button(
          hearingSpoken ? "Stop" : "Hear as spoken",
          () => c.hearSlot(at.channel, at.line, at.slot,
              spoken: true, at: phrasingSpokenAt(_playhead, words, laid)),
          key: const ValueKey("phrasingHearSpoken"),
          icon: hearingSpoken ? Icons.stop : Icons.play_arrow,
          small: true,
          tip: "From the playhead"),
      const SizedBox(width: 4),
      k.button("Reset all", take.shaped ? c.resetPhrasing : null,
          key: const ValueKey("phrasingReset"),
          icon: Icons.restart_alt,
          small: true,
          tip: "Every word as the voice said it"),
    ]);
    var top = Row(children: [
      Flexible(
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: zoomRow),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: hearRow),
      ),
    ]);

    var lanes = LayoutBuilder(builder: (context, box) {
      const left = 44.0, block = 34.0;
      var scale = MediaQuery.textScalerOf(context);
      var caption = scale.scale(9) * 1.4;
      var ruler = math.max(14.0, caption);
      var room = math.max(0.0, box.maxHeight - ruler - caption - 4);
      var loudH = (room * 0.25).clamp(18.0, 54.0);
      var pitchView = math.max(block + 4, room - loudH);
      var fitPx = math.max(20.0, (box.maxWidth - left - 12) / total);
      var px = fitPx * _timeZoom;
      var width = math.max(box.maxWidth, left + total * px + 12);
      // Twelve semitones either side of the voice's middle, seven of them
      // in view before it is zoomed.
      var st = math.max(2.0, (pitchView - block) / 14 * _pitchZoom);
      var pitchH = math.max(pitchView, 24 * st + block + 4);
      var middle = pitchH / 2;
      if (!_centred) {
        _centred = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_down.hasClients) {
            _down.jumpTo(((pitchH - pitchView) / 2)
                .clamp(0.0, _down.position.maxScrollExtent));
          }
        });
      }
      var loudest = reading.levels.fold(-60.0, math.max);
      var perDb = (loudH - 4) / 36;
      var picked = c.phrasingPicked;
      double xOf(double t) => left + t * px;

      var label = scale.scale(8.5) * 1.3;
      var lines = <Widget>[
        CustomPaint(
            size: Size(width, pitchH),
            painter:
                _Grid(middle: middle, st: st, line: s.edge, faint: s.raised)),
        for (var semis in [12, 9, 6, 3, 0, -3, -6, -9, -12])
          if (semis % 6 == 0 || 3 * st >= label)
            Positioned(
              left: 4,
              top: middle - semis * st - label,
              child: IgnorePointer(
                child: Text(
                    semis == 0 ? "middle" : "${semis > 0 ? "+" : ""}$semis st",
                    style: k.mono(8.5, colour: s.muted)),
              ),
            ),
      ];
      var blocks = <Widget>[];
      var rects = <Rect>[];
      var bars = <Widget>[];
      for (var (i, w) in words.indexed) {
        var shape = shapes[i];
        var x = xOf(laid[i].start);
        var blockW = math.max(14.0, (laid[i].end - laid[i].start) * px);
        var mean = reading.meanOf(w);
        var y = (middle -
                ((mean ?? reading.middle) - reading.middle + shape.pitch) * st -
                block / 2)
            .clamp(0.0, pitchH - block);
        rects.add(Rect.fromLTWH(x, y, blockW, block));
        var isPicked = picked.contains(i);
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
          height: block,
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: ValueKey("phrasingWord-$i"),
                supportedDevices: dragPointers,
                onTap: () => _pick(i),
                onVerticalDragStart: (_) => _dragStart(i),
                onVerticalDragUpdate: (d) {
                  _moved += d.delta.dy;
                  var by = (-_moved / st * 2).round() / 2;
                  _drag((f) => f.copyWith(pitch: f.pitch + by));
                },
                onVerticalDragEnd: (_) => _dragEnd(),
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
            // Its right edge: dragged along, it -- and those picked with
            // it -- drawn out or hurried.
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
                  onHorizontalDragStart: (_) => _dragStart(i),
                  onHorizontalDragUpdate: (d) {
                    _moved += d.delta.dx;
                    var times = (blockW + _moved) / blockW;
                    _drag((f) => f.copyWith(
                        length: (f.length * times * 20).round() / 20));
                  },
                  onHorizontalDragEnd: (_) => _dragEnd(),
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
            onTap: () => _pick(i),
            onVerticalDragStart: (_) => _dragStart(i),
            onVerticalDragUpdate: (d) {
              _moved += d.delta.dy;
              var by = (-_moved / perDb).roundToDouble();
              _drag((f) => f.copyWith(loudness: f.loudness + by));
            },
            onVerticalDragEnd: (_) => _dragEnd(),
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

      // The playhead -- or, while it plays, where it has got to.
      var playX = xOf(heard ?? _playhead);
      Widget playLine(double height) => Positioned(
          left: playX,
          top: 0,
          height: height,
          width: 1.5,
          child: IgnorePointer(
              child: ColoredBox(color: s.text.withValues(alpha: 0.85))));

      void setPlayhead(double x) =>
          setState(() => _playhead = ((x - left) / px).clamp(0.0, total));

      // Behind the words: a box dragged round them picks them.
      var boxer = Positioned.fill(
        child: GestureDetector(
          key: const ValueKey("phrasingBox"),
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _focus.requestFocus(),
          onPanStart: (d) {
            _focus.requestFocus();
            _boxFrom = d.localPosition;
            _boxAdds = _adding;
            _boxHad = c.phrasingPicked;
            setState(() => _box = Rect.fromPoints(_boxFrom, _boxFrom));
          },
          onPanUpdate: (d) {
            var r = Rect.fromPoints(_boxFrom, d.localPosition);
            setState(() => _box = r);
            var inside = [
              for (var (i, b) in rects.indexed)
                if (b.overlaps(r)) i
            ];
            if (_boxAdds) {
              c.pickWords({..._boxHad, ...inside});
            } else if (inside.isNotEmpty) {
              c.pickWords(inside);
            }
          },
          onPanEnd: (_) => setState(() => _box = null),
        ),
      );

      var pitchLane = SingleChildScrollView(
        controller: _down,
        child: _zooming(SizedBox(
          height: pitchH,
          // The box under the words, over the lines: a painter takes every
          // press on it.
          child: Stack(children: [
            ...lines,
            boxer,
            ...blocks,
            if (_box case var b?)
              Positioned.fromRect(
                rect: b,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: s.solo.withValues(alpha: 0.12),
                      border: Border.all(color: s.solo),
                    ),
                  ),
                ),
              ),
            playLine(pitchH),
          ]),
        )),
      );

      return SingleChildScrollView(
        controller: _across,
        scrollDirection: Axis.horizontal,
        child: _zooming(SizedBox(
          width: width,
          height: box.maxHeight,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The ruler: a second a tick, clicked or dragged along for the
            // playhead.
            SizedBox(
              height: ruler,
              child: GestureDetector(
                key: const ValueKey("phrasingRuler"),
                supportedDevices: dragPointers,
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setPlayhead(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setPlayhead(d.localPosition.dx),
                child: Stack(children: [
                  Positioned.fill(
                    child: CustomPaint(
                        painter: _Ruler(
                            left: left,
                            px: px,
                            seconds: total,
                            ink: s.muted,
                            style: k.mono(8, colour: s.muted))),
                  ),
                  Positioned(
                    left: xOf(_playhead) - 6,
                    bottom: -2,
                    child: IgnorePointer(
                      child: Icon(Icons.arrow_drop_down,
                          key: const ValueKey("phrasingPlayhead"),
                          size: 13,
                          color: s.text),
                    ),
                  ),
                ]),
              ),
            ),
            Container(
              height: pitchView,
              decoration: BoxDecoration(
                  color: s.inset, borderRadius: BorderRadius.circular(5)),
              clipBehavior: Clip.antiAlias,
              child: pitchLane,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: caption,
              child: Text("Loudness · each word's level",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: k.text(9, colour: s.muted)),
            ),
            Container(
              height: loudH,
              decoration: BoxDecoration(
                  color: s.inset, borderRadius: BorderRadius.circular(5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [...bars, playLine(loudH)]),
            ),
          ]),
        )),
      );
    });

    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        var keys = HardwareKeyboard.instance;
        if (e.logicalKey == LogicalKeyboardKey.keyA &&
            (keys.isMetaPressed || keys.isControlPressed)) {
          c.pickWords([for (var i = 0; i < words.length; i++) i]);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          c.pickWords([c.phrasingPicked.first]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        top,
        const SizedBox(height: 4),
        Expanded(child: lanes),
      ]),
    );
  }
}

/// phrasingSpokenAt is the moment of the take as spoken that [t] -- in the
/// take as shaped, [laid] being where its [words] are now -- was: within a
/// word, as far through it; between two, as far through the gap.
double phrasingSpokenAt(double t, List<TimedWord> words, List<TimedWord> laid) {
  var spokenEdge = 0.0, laidEdge = 0.0;
  for (var (i, w) in words.indexed) {
    var l = laid[i];
    if (t < l.start) {
      var gap = l.start - laidEdge;
      var was = w.start - spokenEdge;
      return spokenEdge + (gap <= 0 ? 0 : (t - laidEdge) / gap * was);
    }
    if (t <= l.end) {
      var span = l.end - l.start;
      return w.start +
          (span <= 0 ? 0 : (t - l.start) / span * (w.end - w.start));
    }
    spokenEdge = w.end;
    laidEdge = l.end;
  }
  return spokenEdge + (t - laidEdge);
}

/// phrasingShapedAt is phrasingSpokenAt the other way: the moment of the
/// take as shaped that [t], in the take as spoken, is now.
double phrasingShapedAt(
        double t, List<TimedWord> words, List<TimedWord> laid) =>
    phrasingSpokenAt(t, laid, words);

/// _Ruler is a tick a second -- or a half, or a tenth, zoomed in -- each
/// second numbered.
class _Ruler extends CustomPainter {
  final double left, px, seconds;
  final Color ink;
  final TextStyle style;
  _Ruler(
      {required this.left,
      required this.px,
      required this.seconds,
      required this.ink,
      required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()..color = ink.withValues(alpha: 0.6);
    var step = px >= 120 ? 0.1 : (px >= 40 ? 0.5 : 1.0);
    var ticks = (seconds / step).floor();
    for (var n = 0; n <= ticks; n++) {
      var t = n * step;
      var x = left + t * px;
      var whole = (t - t.roundToDouble()).abs() < 1e-6;
      canvas.drawLine(Offset(x, size.height - (whole ? 6 : 3)),
          Offset(x, size.height), paint);
      if (whole) {
        var text = TextPainter(
            text: TextSpan(text: "${t.round()}s", style: style),
            textDirection: TextDirection.ltr)
          ..layout();
        text.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_Ruler old) =>
      old.left != left ||
      old.px != px ||
      old.seconds != seconds ||
      old.ink != ink;
}

/// _Grid is the pitch lane's lines: the voice's middle, and every three
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
    for (var semis = -12; semis <= 12; semis += 3) {
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

/// PhrasingWordPanel is the picked words' settings: the first picked's
/// shown, every word picked moved by as much -- each as said, until moved.
class PhrasingWordPanel extends StatelessWidget {
  final CanvasController controller;
  const PhrasingWordPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var look = MixerLook.of(context);
    var s = look.studio;
    var k = SpeechKit(s, look.colors);
    var take = c.phrasingTake;
    if (take == null || take.asSpoken.words.isEmpty) {
      return Center(
          child: Text("No words to shape.",
              textAlign: TextAlign.center, style: k.text(11, colour: s.muted)));
    }
    var words = take.asSpoken.words;
    var picked = [
      for (var w in c.phrasingPicked)
        if (w >= 0 && w < words.length) w
    ];
    if (picked.isEmpty) picked = [0];
    var first = picked.first;
    var shape = take.shapeOf(first);
    var word = words[first];

    // A slider moved: every word picked moved by as much as the first,
    // part of one change.
    void change(WordShape next) {
      c.beginInteraction();
      c.shapeWords({
        for (var w in picked)
          w: () {
            var f = take.shapeOf(w);
            return f.copyWith(
                pitch: f.pitch + next.pitch - shape.pitch,
                inflection: f.inflection + next.inflection - shape.inflection,
                length: f.length + next.length - shape.length,
                pause: f.pause + next.pause - shape.pause,
                loudness: f.loudness + next.loudness - shape.loudness);
          }(),
      }, transient: true);
    }

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
            WordShape Function(double v) next,
            {required Key key}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: k.text(11))),
            Text(reading,
                style: k.mono(10, colour: s.text.withValues(alpha: 0.8))),
          ]),
          SizedBox(
            height: 18,
            child: Slider(
              key: key,
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => change(next(v)),
              onChangeEnd: (_) => c.endInteraction(),
            ),
          ),
          Row(children: [
            Expanded(
                child: Text(low,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: k.text(8.5, colour: s.muted))),
            Text(high, maxLines: 1, style: k.text(8.5, colour: s.muted)),
          ]),
          const SizedBox(height: 3),
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
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                  picked.length == 1
                      ? "“${word.text}”"
                      : "${picked.length} words",
                  key: const ValueKey("phrasingPicked"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: k.text(12.5, weight: FontWeight.w700)),
            ),
            Flexible(
              child: Text(
                  picked.length == 1
                      ? "${((word.end - word.start) * shape.length).toStringAsFixed(2)} s"
                      : "as “${word.text}”",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: k.mono(9.5, colour: s.muted)),
            ),
          ]),
          const SizedBox(height: 4),
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
              shape.pause == 0 ? asSaid : "+${(shape.pause * 1000).round()} ms",
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
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: k.button(
                  "Stress",
                  () => c.shapeWords(
                      {for (var w in picked) w: take.shapeOf(w).stressed}),
                  key: const ValueKey("phrasingStress"),
                  icon: Icons.priority_high,
                  small: true,
                  tip: "A little higher, a little longer, a little louder: "
                      "a start, each as you set it after"),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: k.button(
                  "Reset",
                  picked.every((w) => take.shapeOf(w).isPlain)
                      ? null
                      : () => c.shapeWords(
                          {for (var w in picked) w: WordShape.plain}),
                  key: const ValueKey("phrasingResetWord"),
                  icon: Icons.undo,
                  small: true,
                  tip: "The words picked as the voice said them"),
            ),
          ]),
        ]),
      ),
    );
  }
}
