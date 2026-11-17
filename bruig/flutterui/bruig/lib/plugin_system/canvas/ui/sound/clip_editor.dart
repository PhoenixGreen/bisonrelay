import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/media/spectrogram.dart';
import 'package:bruig/plugin_system/canvas/media/warp.dart' show onsets;
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show ControlPoint;
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/automation_lanes.dart'
    show envelopeLengths, settingLabel;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/sound/piano_roll.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

part 'clip_editor_audio.dart';
part 'clip_editor_columns.dart';

// clip_editor.dart is the clip editor (Ableton's clip view), a device
// first in the channel's chain: settings in columns on the left (Clip,
// Launch, Audio or Notes), and on the right an audio clip's sound on a
// ruler or a MIDI clip's notes in the piano roll. All in beats.

const double _columnW = 220;

/// _fadeInk is the fades, their grips and the warp markers: amber.
const _fadeInk = Color(0xFFE2B04A);

const _envelopeInk = Color(0xFFF08BD0);

/// EditorFrame is the clip editor's (or a part's piano roll's) place in
/// the effects strip, given the room rather than scaled to it.
class EditorFrame extends StatelessWidget {
  final String id;
  final String title;
  final double width;
  final double height;
  final bool wide;
  final VoidCallback onWide;
  final VoidCallback onClose;
  final Widget child;

  /// onResize is the width its dragged right edge asks for.
  final ValueChanged<double>? onResize;

  const EditorFrame({
    this.onResize,
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required this.wide,
    required this.onWide,
    required this.onClose,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var ink = look.colors.onSurface;
    Widget frame = Container(
      key: ValueKey("device-$id"),
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: look.studio.panel,
          border: Border.all(color: Colors.black38),
          borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 28,
          color: look.colors.surfaceContainerHighest,
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
            ),
            IconButton(
              key: const ValueKey("editorWide"),
              tooltip: wide
                  ? "Narrower"
                  : "Wider: every setting, and more "
                      "room for what it plays",
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(wide ? Icons.close_fullscreen : Icons.open_in_full,
                  color: ink),
              onPressed: onWide,
            ),
            IconButton(
              key: const ValueKey("editorClose"),
              tooltip: "Close the editor",
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: ink),
              onPressed: onClose,
            ),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
    if (onResize case var resize?) {
      frame = Stack(children: [
        frame,
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 6,
          child: _EdgeDrag(
              key: ValueKey("editorEdge-$id"), width: width, onResize: resize),
        ),
      ]);
    }
    return frame;
  }
}

/// _EdgeDrag is an editor's right edge, dragged: the start width plus the
/// pointer's travel since, not each move added to the last, which loses
/// moves that come between two frames.
class _EdgeDrag extends StatefulWidget {
  final double width;
  final ValueChanged<double> onResize;
  const _EdgeDrag({required this.width, required this.onResize, super.key});

  @override
  State<_EdgeDrag> createState() => _EdgeDragState();
}

class _EdgeDragState extends State<_EdgeDrag> {
  double _from = 0, _was = 0;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          // From the press: the edge stays under the pointer.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (d) {
            _from = d.globalPosition.dx;
            _was = widget.width;
          },
          onHorizontalDragUpdate: (d) =>
              widget.onResize(_was + d.globalPosition.dx - _from),
        ),
      );
}

class ClipEditor extends StatefulWidget {
  final CanvasController controller;

  final bool wide;

  /// part is whether it edits a MIDI channel's part (from the piano roll's
  /// In) rather than a slot's clip.
  final bool part;

  /// canWiden is whether there is room for every column at once.
  final bool canWiden;
  const ClipEditor(
      {required this.controller,
      this.wide = true,
      this.part = false,
      this.canWiden = true,
      super.key});

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  CanvasController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _changes.dispose();
    super.dispose();
  }

  /// _changes rebuilds the editor on every canvas change but the playhead
  /// moving (its waveform's playhead moves by itself), unless that took its
  /// clip from waiting to playing, or playing to stopped.
  final ValueNotifier<int> _changes = ValueNotifier(0);
  Object? _stateWas;

  Object? get _clipStateNow => switch (c.clipEditing) {
        PianoRollTarget(:var channel, row: var row?) =>
          c.clipState(channel, row),
        _ => null,
      };

  void _changed() {
    var now = _clipStateNow;
    if (c.notifyingPlayhead && now == _stateWas) return;
    _stateWas = now;
    _changes.value++;
  }

  /// _built is the editor as last built, handed back while nothing it shows
  /// has changed: see CanvasMixer's.
  Widget? _built;

  @override
  void setState(VoidCallback fn) {
    _built = null;
    super.setState(fn);
  }

  @override
  void didUpdateWidget(ClipEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.wide != widget.wide ||
        old.part != widget.part ||
        old.canWiden != widget.canWiden) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  /// _said is what the last Reverse, Crop or Warp said; _busy while working.
  String? _said;
  bool _busy = false;

  bool _spectral = false;

  /// _shown is the column shown when narrow: 0 Clip, 1 Launch, 2 Audio/Notes.
  int _shown = 0;

  /// _envelope is the key of the envelope drawn over an audio clip's sound
  /// (its gain or pan, or a channel setting: see SessionClip.curveOf), or
  /// null for its gain.
  String? _envelope;
  bool _envelopes = false;

  Future<void> _run(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    String? said;
    try {
      said = await job();
    } catch (exception, stack) {
      // Said, not lost, so a failure is not a press that does nothing.
      debugPrint("The clip editor could not do that: $exception\n$stack");
      said = "That did not work: $exception";
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _said = said;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _built ??= ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          var look = MixerLook.of(context);
          if (widget.part) {
            var t = c.pianoRoll;
            var content = c.rollContent;
            var e = t == null ? null : c.instrumentOf(t.channel);
            if (t == null || t.row != null || content == null || e == null) {
              return const SizedBox();
            }
            // Straight to its toolbar: its name is in the Chain's header.
            return _layout(
                look,
                null,
                // A slot clip's columns: a part's timeline place, its launch
                // (for a copy in a slot) and its notes' tools.
                [
                  ("Clip", _partColumn(look, e, content), "partColumn"),
                  (
                    "Launch",
                    _partLaunchColumn(look, t.channel),
                    "launchColumn"
                  ),
                  ("Notes", _notesColumn(look), "notesColumn"),
                ],
                PianoRoll(controller: c, inClipEditor: true));
          }
          var t = c.clipEditing;
          var clip = c.editedClip;
          if (t == null || clip == null) return const SizedBox();
          if (!clip.midi) return _audioEditor(look, t, clip);
          return _layout(
              look,
              null,
              [
                ("Clip", _clipColumn(look, clip), "clipColumn"),
                ("Launch", _launchColumn(look, clip), "launchColumn"),
                ("Notes", _notesColumn(look), "notesColumn"),
              ],
              PianoRoll(controller: c, inClipEditor: true));
        },
      );

  // ---- clip_editor_columns.dart -------------------------------------------

  static String _seconds(double s) => s < 1
      ? "${(s * 1000).round()} ms"
      : "${s.toStringAsFixed(s < 10 ? 1 : 0)} s";

}

/// _Sound is a stored sound as drawn: the loudest of each slice, its
/// length, and where it is struck.
typedef _Sound = ({
  Float32List peaks,
  Float32List left,
  Float32List right,
  double seconds,
  List<double> hits
});

final Map<String, Future<_Sound?>> _soundsOf = {};

const int _peakSlices = 4000;

final Map<String, Future<ui.Image?>> _spectraOf = {};

Future<ui.Image?> _spectrumOf(String assetId) =>
    _spectraOf[assetId] ??= () async {
      var audio = await CanvasController.clipAudio(assetId);
      if (audio == null) {
        _spectraOf.remove(assetId);
        return null;
      }
      var (l, r) = audio;
      var made = await Isolate.run(() {
        var mono = Float32List(l.length);
        for (var i = 0; i < l.length; i++) {
          mono[i] = (l[i] + r[i]) / 2;
        }
        return spectrogramOf(mono);
      });
      var done = Completer<ui.Image>();
      ui.decodeImageFromPixels(made.rgba, made.columns, made.rows,
          ui.PixelFormat.rgba8888, done.complete);
      return _spectraMade[assetId] = await done.future;
    }();

final Map<String, ui.Image> _spectraMade = {};

Future<_Sound?> _soundOf(String assetId) => _soundsOf[assetId] ??= () async {
      var audio = await CanvasController.clipAudio(assetId);
      // Not kept, unread: read again next time.
      if (audio == null) {
        _soundsOf.remove(assetId);
        return null;
      }
      var (l, r) = audio;
      // Off the UI isolate: a whole song's peaks and hits there hold up the
      // mixer's sound.
      return Isolate.run(() => _drawingOf(l, r));
    }();

_Sound _drawingOf(Float32List l, Float32List r) {
  var n = l.length;
  var peaks = Float32List(_peakSlices);
  var left = Float32List(_peakSlices), right = Float32List(_peakSlices);
  for (var i = 0; i < n; i++) {
    var a = l[i].abs(), b = r[i].abs();
    var k = i * _peakSlices ~/ n;
    if (a > left[k]) left[k] = a;
    if (b > right[k]) right[k] = b;
    var v = math.max(a, b);
    if (v > peaks[k]) peaks[k] = v;
  }
  return (
    peaks: peaks,
    left: left,
    right: right,
    seconds: n / 48000,
    hits: n == 0 ? const <double>[] : onsets(l, r),
  );
}

enum _Handle { start, loop, length, marker, point, fadeIn, fadeOut }

/// _SampleView is an audio clip's sound against the song's beats: its
/// start's flag and loop's bar on a ruler, to drag, and any warp markers.
class _SampleView extends StatefulWidget {
  final CanvasController controller;
  final SessionClip clip;

  /// envelope is the key of the envelope drawn over its sound, or null;
  /// envelopeRest is its height with no points, and envelopeLength its own
  /// length in beats, or null to follow the clip.
  final String? envelope;
  final double envelopeRest;
  final double? envelopeLength;

  final bool spectral;

  final ValueChanged<String?>? onSay;

  /// envelopeName is a channel setting's envelope's name.
  final String? envelopeName;
  const _SampleView(
      {required this.controller,
      required this.clip,
      this.envelope,
      this.envelopeRest = 1,
      this.envelopeLength,
      this.spectral = false,
      this.onSay,
      this.envelopeName});

  @override
  State<_SampleView> createState() => _SampleViewState();
}

class _SampleViewState extends State<_SampleView>
    with SingleTickerProviderStateMixin {
  CanvasController get c => widget.controller;
  late final Ticker _ticker;
  double? _playhead;
  _Handle? _dragging;
  int _marker = 0;

  /// For a double-click taking a marker out.
  int? _tappedMarker;

  /// For a double-click taking a point out.
  int? _tappedPoint;
  DateTime _tappedAt = DateTime(0);
  double _dragFrom = 0, _valueFrom = 0;

  /// _zoom is how far in the sound is drawn (one: all in view), and _scroll
  /// the beat at the view's left edge: setting a start finer than a beat
  /// needs the sound seen closer than a bar.
  double _zoom = 1;
  double _scroll = 0;
  static const double _maxZoom = 256;

  /// _step is what a drag snaps to, at [beatW] pixels a beat: the finest
  /// grid (a beat, a half, down to 1/256) still eight pixels wide; nothing
  /// with Alt held.
  static double _step(double beatW) {
    if (HardwareKeyboard.instance.isAltPressed) return 0;
    var step = 1.0;
    while (step > 1 / 256 && step / 2 * beatW >= 8) {
      step /= 2;
    }
    return step;
  }

  static double _snap(double v, double step) =>
      step <= 0 ? v : (v / step).roundToDouble() * step;

  void _zoomAbout(double factor, double x, double fit) {
    var was = fit * _zoom;
    var under = x / was + _scroll;
    var next = (_zoom * factor).clamp(1.0, _maxZoom);
    setState(() {
      _zoom = next;
      _scroll = under - x / (fit * next);
    });
  }

  @override
  void initState() {
    super.initState();
    // The ticker runs only while playing: it asks for a frame on every
    // refresh.
    _ticker = createTicker((_) {
      var at = c.clipPlayhead;
      if (at != _playhead) setState(() => _playhead = at);
      if (at == null) _ticker.stop();
    });
    c.addListener(_followPlayhead);
    _followPlayhead();
  }

  void _followPlayhead() {
    if (c.clipPlayhead != null && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    c.removeListener(_followPlayhead);
    _ticker.dispose();
    super.dispose();
  }

  static const double _rulerH = 26;
  static const double _markersH = 14;

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var clip = widget.clip;
    var sound = clip.sound;
    var audio = c.document.audio;
    var bpb = audio.beatsPerBar;
    var spb = math.max(0.001, audio.secondsPerBeat);
    ui.Image? spectrum;
    if (widget.spectral && sound != null) {
      spectrum = _spectraMade[sound.assetId];
      if (spectrum == null) {
        _spectrumOf(sound.assetId).then((_) {
          if (mounted) setState(() {});
        });
      }
    }
    return FutureBuilder<_Sound?>(
      future: sound == null ? null : _soundOf(sound.assetId),
      builder: (context, snap) => LayoutBuilder(builder: (context, size) {
        var heard = snap.data;
        var fileSeconds = heard?.seconds ?? 0.0;
        var playStart = sound?.start ?? 0;
        var playEnd = sound == null
            ? 0.0
            : sound.end > 0
                ? sound.end
                : (fileSeconds > 0 ? fileSeconds : sound.length);
        var length = math.max(0.0, playEnd - playStart);
        var map = clip.warpMap;
        var speed =
            math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
        double beatOf(double seconds) =>
            clip.warp ? map.beatAt(seconds) : seconds / speed / spb;
        double secondOf(double beat) =>
            clip.warp ? map.sourceAt(beat) : beat * spb * speed;
        var soundBeats = beatOf(length);
        // In view: the sound and its loop, edge to edge.
        var beats = [
          soundBeats,
          clip.loopEnd(bpb),
          clip.start + 1,
        ].reduce(math.max);
        var fit = size.maxWidth / beats;
        var beatW = fit * _zoom;
        // Never past the end, never before the start.
        var shown = size.maxWidth / beatW;
        var scroll =
            _scroll.clamp(0.0, math.max(0.0, beats - shown)).toDouble();
        double beatAt(double x) => x / beatW + scroll;
        double xOf(double beat) => (beat - scroll) * beatW;
        var step = _step(beatW);
        var markers = clip.warp ? clip.markers : const <WarpMarker>[];
        var top = _rulerH + _markersH;
        var spbNow = math.max(0.001, c.document.audio.secondsPerBeat);
        // The fades' grips: where the fade in ends and the fade out begins.
        var fadeInX = xOf(clip.start + clip.fadeIn / spbNow);
        var fadeOutX = xOf(clip.loopEnd(bpb) - clip.fadeOut / spbNow);
        return GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("clipRuler"),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          // A click adds a warp marker at a nearby hit; a right-click removes
          // one.
          onTapUp: (d) {
            var p = d.localPosition;
            if (widget.envelope case var env? when p.dy > top) {
              if (_pointNear(clip, env, beatW, top, size.maxHeight,
                      p + Offset(scroll * beatW, 0))
                  case var i?) {
                // Twice on it: taken out, as a right-click does.
                var now = DateTime.now();
                if (i == _tappedPoint &&
                    now.difference(_tappedAt) <
                        const Duration(milliseconds: 400)) {
                  _tappedPoint = null;
                  c.editClip((x) =>
                      x.withCurve(env, [...x.curveOf(env)]..removeAt(i)));
                } else {
                  _tappedPoint = i;
                  _tappedAt = now;
                }
                return;
              }
              _tappedPoint = null;
              var beat = _onEnvelope(_snap(beatAt(p.dx), math.min(step, 0.25)));
              var value = _valueAt(p.dy, top, size.maxHeight);
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env), (beat, value)]));
              return;
            }
            if (p.dy < _rulerH || p.dy > top) return;
            if (!clip.warp) {
              widget.onSay?.call("Switch Warp on to place warp markers");
              return;
            }
            var beat = beatAt(p.dx);
            if (_markerNear(markers, beatW, p.dx + scroll * beatW)
                case var i?) {
              // Twice on it: taken out, as a right-click does.
              var now = DateTime.now();
              if (i == _tappedMarker &&
                  now.difference(_tappedAt) <
                      const Duration(milliseconds: 400)) {
                _tappedMarker = null;
                c.editClip(
                    (x) => x.copyWith(markers: [...x.markers]..removeAt(i)));
              } else {
                _tappedMarker = i;
                _tappedAt = now;
              }
              return;
            }
            var seconds = secondOf(beat).clamp(0.0, length);
            for (var h in heard?.hits ?? const <double>[]) {
              if ((beatOf(h) - beat).abs() * beatW <= 6) seconds = h;
            }
            if (seconds <= 0) return;
            c.editClip((x) => x.copyWith(markers: [
                  ...x.markers,
                  (seconds: seconds, beat: beatOf(seconds)),
                ]));
          },
          onSecondaryTapUp: (d) {
            if (widget.envelope case var env? when d.localPosition.dy > top) {
              var i = _pointNear(clip, env, beatW, top, size.maxHeight,
                  d.localPosition + Offset(scroll * beatW, 0));
              if (i == null) return;
              c.editClip(
                  (x) => x.withCurve(env, [...x.curveOf(env)]..removeAt(i)));
              return;
            }
            var i = _markerNear(
                markers, beatW, d.localPosition.dx + scroll * beatW);
            if (i == null || d.localPosition.dy > top) return;
            c.editClip((x) => x.copyWith(markers: [...x.markers]..removeAt(i)));
          },
          onPanStart: (d) {
            var p = d.localPosition;
            if (widget.envelope case var env? when p.dy > top) {
              var i = _pointNear(clip, env, beatW, top, size.maxHeight,
                  p + Offset(scroll * beatW, 0));
              if (i == null) return;
              _dragging = _Handle.point;
              _marker = i;
              c.beginInteraction();
              return;
            }
            if (p.dy >= top && p.dy <= top + 14) {
              if ((p.dx - fadeInX).abs() <= 8) {
                _dragging = _Handle.fadeIn;
                c.beginInteraction();
                return;
              }
              if ((p.dx - fadeOutX).abs() <= 8) {
                _dragging = _Handle.fadeOut;
                c.beginInteraction();
                return;
              }
            }
            if (p.dy > top + 12) return;
            var x = p.dx;
            if (clip.warp && p.dy >= _rulerH && p.dy <= top) {
              var i = _markerNear(markers, beatW, x + scroll * beatW);
              if (i == null) return;
              _dragging = _Handle.marker;
              _marker = i;
              _valueFrom = markers[i].beat;
            } else {
              var startX = xOf(clip.start);
              var endX = xOf(clip.loopEnd(bpb));
              var loopX = xOf(clip.loopStart);
              if ((x - startX).abs() <= 10) {
                _dragging = _Handle.start;
                _valueFrom = clip.start;
              } else if ((x - endX).abs() <= 10) {
                _dragging = _Handle.length;
                _valueFrom = clip.bars;
              } else if (x >= loopX && x <= endX) {
                _dragging = _Handle.loop;
                _valueFrom = clip.loopStart;
              } else {
                return;
              }
            }
            _dragFrom = x;
            c.beginInteraction();
          },
          onPanUpdate: (d) {
            var handle = _dragging;
            if (handle == null) return;
            // To the finest grid still a few pixels wide (see _step), or with
            // Alt held, to nothing.
            var moved = (d.localPosition.dx - _dragFrom) / beatW;
            switch (handle) {
              case _Handle.fadeIn:
                var b = beatAt(d.localPosition.dx);
                var most = (clip.loopEnd(bpb) - clip.start) / 2;
                var beats = (b - clip.start).clamp(0.0, math.max(0.0, most));
                c.editClip(
                    (x) => x.copyWith(
                        fadeIn: (beats * spbNow * 100).roundToDouble() / 100),
                    transient: true);
              case _Handle.fadeOut:
                var b = beatAt(d.localPosition.dx);
                var most = (clip.loopEnd(bpb) - clip.start) / 2;
                var beats =
                    (clip.loopEnd(bpb) - b).clamp(0.0, math.max(0.0, most));
                c.editClip(
                    (x) => x.copyWith(
                        fadeOut: (beats * spbNow * 100).roundToDouble() / 100),
                    transient: true);
              case _Handle.start:
                var v = math.max(0.0, _snap(_valueFrom + moved, step));
                c.editClip((x) => x.copyWith(start: v), transient: true);
              case _Handle.loop:
                var v = math.max(0.0, _snap(_valueFrom + moved, step));
                c.editClip((x) => x.copyWith(loopStart: v), transient: true);
              case _Handle.length:
                var least = step > 0 ? step : 1 / 64;
                var b = math.max(least, _snap(_valueFrom * bpb + moved, step));
                c.editClip((x) => x.copyWith(bars: b / bpb), transient: true);
              case _Handle.point:
                var env = widget.envelope;
                if (env == null) return;
                var beat = _onEnvelope(
                    _snap(beatAt(d.localPosition.dx), math.min(step, 0.25)));
                var value = _valueAt(d.localPosition.dy, top, size.maxHeight);
                c.editClip((x) {
                  var points = [...x.curveOf(env)];
                  if (_marker >= points.length) return x;
                  points[_marker] = (math.max(0.0, beat), value);
                  var moved = points[_marker];
                  points.sort((a, b) => a.$1.compareTo(b.$1));
                  _marker = points.indexOf(moved);
                  return x.withCurve(env, points);
                }, transient: true);
              case _Handle.marker:
                var v = _snap(_valueFrom + moved, math.min(step, 0.25));
                c.editClip((x) {
                  var next = [...x.markers];
                  if (_marker >= next.length) return x;
                  next[_marker] = (seconds: next[_marker].seconds, beat: v);
                  return x.copyWith(markers: next);
                }, transient: true);
            }
          },
          onPanEnd: (_) {
            if (_dragging == null) return;
            _dragging = null;
            c.endInteraction();
          },
          child: Listener(
            // Two fingers along, or a wheel: across the sound. Pinched, or with
            // Cmd or Ctrl held: zoom about the pointer.
            onPointerSignal: (e) {
              if (e is! PointerScrollEvent) return;
              var keys = HardwareKeyboard.instance;
              if (keys.isMetaPressed || keys.isControlPressed) {
                _zoomAbout(e.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15,
                    e.localPosition.dx, fit);
                return;
              }
              var by =
                  e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
              setState(() => _scroll = scroll + by / beatW);
            },
            onPointerPanZoomUpdate: (e) {
              if ((e.scale - 1).abs() > 0.001) {
                var to = (_pinchFrom * e.scale).clamp(1.0, _maxZoom);
                _zoomAbout(to / _zoom, e.localPosition.dx, fit);
              } else {
                setState(() => _scroll = scroll - e.panDelta.dx / beatW);
              }
            },
            onPointerPanZoomStart: (_) => _pinchFrom = _zoom,
            child: Stack(children: [
              CustomPaint(
                key: const ValueKey("clipSample"),
                size: Size(size.maxWidth, size.maxHeight),
                painter: _SamplePainter(
                  scroll: scroll,
                  step: step,
                  peaks: heard?.peaks,
                  left: heard?.left,
                  right: heard?.right,
                  fileSeconds: fileSeconds,
                  playStart: playStart,
                  playLength: length,
                  secondOf: secondOf,
                  hits: [
                    for (var h in heard?.hits ?? const <double>[])
                      if (h >= playStart && h < playEnd) beatOf(h - playStart)
                  ],
                  markers: [for (var m in markers) m.beat],
                  beatsPerBar: bpb,
                  beatW: beatW,
                  beats: beats,
                  soundBeats: soundBeats,
                  start: clip.start,
                  loopStart: clip.loopStart,
                  loopEnd: clip.loopEnd(bpb),
                  loop: clip.loop,
                  gain: math.pow(10, clip.gain / 20).toDouble(),
                  fadeIn: clip.fadeIn / c.document.audio.secondsPerBeat,
                  fadeOut: clip.fadeOut / c.document.audio.secondsPerBeat,
                  fadeCurve: clip.fadeCurve,
                  spectrum: spectrum,
                  playhead: _playhead,
                  studio: look.studio,
                  rulerH: _rulerH,
                  top: top,
                  envelope: widget.envelope == null
                      ? null
                      : clip.curveOf(widget.envelope!),
                  envelopeRest: widget.envelopeRest,
                  envelopeLength: widget.envelopeLength,
                  envelopeLabel: switch (widget.envelope) {
                    null => "",
                    "gain" => "gain envelope · 0 dB down to silence",
                    "pan" => "pan envelope · left to right",
                    _ => widget.envelopeName ?? "",
                  },
                  gainCurve: clip.envelopes[ClipEnvelope.gain] ?? const [],
                  panCurve: clip.envelopes[ClipEnvelope.pan] ?? const [],
                  key: clip.warpSignature(spb),
                ),
              ),
              // Zoom buttons in the sound's lower corner, off the ruler.
              Positioned(
                right: 6,
                bottom: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _zoomButton(
                      look,
                      "clipZoomOut",
                      Icons.remove,
                      _zoom <= 1
                          ? null
                          : () => _zoomAbout(1 / 2, size.maxWidth / 2, fit)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text("${_zoom.round()}×",
                        key: const ValueKey("clipZoom"),
                        style:
                            TextStyle(fontSize: 10, color: look.studio.muted)),
                  ),
                  _zoomButton(
                      look,
                      "clipZoomIn",
                      Icons.add,
                      _zoom >= _maxZoom
                          ? null
                          : () => _zoomAbout(2, size.maxWidth / 2, fit)),
                  const SizedBox(width: 2),
                  _zoomButton(
                      look,
                      "clipZoomFit",
                      Icons.fit_screen_outlined,
                      _zoom <= 1
                          ? null
                          : () => setState(() {
                                _zoom = 1;
                                _scroll = 0;
                              })),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  double _pinchFrom = 1;

  Widget _zoomButton(
          MixerLook look, String key, IconData icon, VoidCallback? onTap) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              color: look.studio.panel,
              border: Border.all(color: look.studio.edge),
              borderRadius: BorderRadius.circular(3)),
          child: Icon(icon,
              size: 12,
              color: onTap == null
                  ? look.studio.muted.withValues(alpha: 0.4)
                  : look.studio.text),
        ),
      );

  /// _valueAt is an envelope's value at height [y]: one at [top], nought at
  /// [bottom].
  double _valueAt(double y, double top, double bottom) =>
      (1 - (y - top - 6) / math.max(1, bottom - top - 12)).clamp(0.0, 1.0);

  /// _onEnvelope is [beat] kept inside an envelope of its own length: its
  /// points are its first time round, which the rest repeat.
  double _onEnvelope(double beat) {
    var length = widget.envelopeLength;
    beat = math.max(0.0, beat);
    return length == null ? beat : beat.clamp(0.0, length - 0.25);
  }

  int? _pointNear(SessionClip clip, String env, double beatW, double top,
      double bottom, Offset p) {
    for (var (i, (b, v)) in clip.curveOf(env).indexed) {
      var y = top + 6 + (1 - v) * math.max(1, bottom - top - 12);
      if ((Offset(b * beatW, y) - p).distance <= 8) return i;
    }
    return null;
  }

  int? _markerNear(List<WarpMarker> markers, double beatW, double x) {
    for (var (i, m) in markers.indexed) {
      if ((m.beat * beatW - x).abs() <= 7) return i;
    }
    return null;
  }
}

class _SamplePainter extends CustomPainter {
  /// scroll is the beat at the left edge, zoomed in; step the grid a drag
  /// snaps to, drawn where finer than a beat (nought for none).
  final double scroll, step;
  final Float32List? peaks;

  final Float32List? left, right;
  final double fileSeconds, playStart, playLength;
  final double Function(double beat) secondOf;
  final List<double> hits, markers;
  final int beatsPerBar;
  final double beatW, beats, soundBeats, start, loopStart, loopEnd, gain;
  final double rulerH, top;
  final bool loop;
  final double? playhead;
  final StudioColors studio;

  /// envelope is the points (beat, value) drawn over the sound, or null;
  /// envelopeRest is its value with none.
  final List<ControlPoint>? envelope;
  final double envelopeRest;

  /// envelopeLength is its own length in beats (drawn once, then repeated
  /// fainter), or null.
  final double? envelopeLength;

  /// key is what the sound's drawing depends on beyond the rest.
  final String key;

  final String envelopeLabel;

  /// gainCurve and panCurve are the clip's own envelopes: the sound is drawn
  /// as they shape it, shown or not.
  final List<ControlPoint> gainCurve, panCurve;

  _SamplePainter({
    this.scroll = 0,
    this.step = 1,
    required this.peaks,
    this.left,
    this.right,
    required this.fileSeconds,
    required this.playStart,
    required this.playLength,
    required this.secondOf,
    required this.hits,
    required this.markers,
    required this.beatsPerBar,
    required this.beatW,
    required this.beats,
    required this.soundBeats,
    required this.start,
    required this.loopStart,
    required this.loopEnd,
    required this.loop,
    required this.gain,
    required this.playhead,
    required this.studio,
    required this.rulerH,
    required this.top,
    required this.key,
    this.envelope,
    this.envelopeRest = 1,
    this.envelopeLength,
    this.envelopeLabel = "",
    this.gainCurve = const [],
    this.panCurve = const [],
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.fadeCurve = FadeCurve.smooth,
    this.spectrum,
  });

  /// spectrum is its sound as a spectrogram, drawn under its wave.
  final ui.Image? spectrum;

  /// fadeIn and fadeOut are in beats, [fadeCurve] their shape.
  final double fadeIn, fadeOut;
  final FadeCurve fadeCurve;

  @override
  void paint(Canvas canvas, Size size) {
    var h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.inset);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, top), Paint()..color = studio.panel);
    var left = scroll * beatW;
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-left, 0);
    size = Size(math.max(size.width, beats * beatW), size.height);
    if (step > 0 && step < 1) {
      var fine = Paint()..color = studio.edge.withValues(alpha: 0.18);
      var from = (scroll / step).floor();
      var to = ((left + size.width) / beatW / step).ceil();
      for (var k = from; k <= to; k++) {
        var x = k * step * beatW;
        if (x < left - 1 || x > left + size.width) continue;
        canvas.drawLine(Offset(x, rulerH - 2), Offset(x, h), fine);
      }
    }
    // What it does not play, darker: before its start, past its end.
    var dim = Paint()..color = Colors.black.withValues(alpha: 0.28);
    var first = (loop ? math.min(start, loopStart) : start) * beatW;
    canvas.drawRect(Rect.fromLTRB(0, top, first, h), dim);
    canvas.drawRect(Rect.fromLTRB(loopEnd * beatW, top, size.width, h), dim);
    if (beatW >= 24) {
      var quarter = Paint()..color = studio.edge.withValues(alpha: 0.16);
      for (var q = 0; q <= beats * 4; q++) {
        if (q % 4 == 0) continue;
        var x = q * beatW / 4;
        canvas.drawLine(Offset(x, top), Offset(x, h), quarter);
      }
    }
    var label = TextPainter(textDirection: TextDirection.ltr);
    var every = beatW * beatsPerBar < 28 ? 4 : 1;
    for (var b = 0; b <= beats; b++) {
      var x = b * beatW;
      var bar = b % beatsPerBar == 0;
      canvas.drawLine(Offset(x, bar ? 9 : rulerH - 7), Offset(x, rulerH),
          Paint()..color = studio.edge.withValues(alpha: bar ? 1 : 0.7));
      canvas.drawLine(Offset(x, top), Offset(x, h),
          Paint()..color = studio.edge.withValues(alpha: bar ? 0.75 : 0.35));
      if (bar && (b ~/ beatsPerBar) % every == 0) {
        label.text = TextSpan(
            text: "${b ~/ beatsPerBar + 1}",
            style: TextStyle(fontSize: 10.5, color: studio.text));
        label.layout();
        label.paint(canvas, Offset(x + 3, rulerH - 14));
      }
    }
    // Its hits, grey, and its warp markers, yellow, under the ruler.
    if (top > rulerH) {
      var tick = Paint()..color = studio.muted;
      for (var b in hits) {
        canvas.drawLine(
            Offset(b * beatW, top - 5), Offset(b * beatW, top), tick);
      }
      var pin = Paint()..color = _fadeInk;
      for (var b in markers) {
        var x = b * beatW;
        canvas.drawPath(
            Path()
              ..moveTo(x, rulerH + 1)
              ..lineTo(x + 7, rulerH + 1)
              ..lineTo(x + 7, rulerH + 8)
              ..lineTo(x, rulerH + 13)
              ..close(),
            pin);
        canvas.drawLine(Offset(x, rulerH + 1), Offset(x, h),
            Paint()..color = _fadeInk.withValues(alpha: 0.4));
      }
    }
    // Its spectrum: a column of the picture every two pixels.
    if ((spectrum, fileSeconds) case (var image?, var seconds)
        when seconds > 0) {
      var shownTo = left + size.width;
      var paint = Paint()..filterQuality = FilterQuality.low;
      for (var x = left.floorToDouble();
          x < math.min(shownTo, soundBeats * beatW);
          x += 2) {
        var at = playStart + secondOf(x / beatW);
        if (at >= playStart + playLength) break;
        var col = (at / seconds * image.width).floorToDouble();
        if (col < 0 || col >= image.width) continue;
        canvas.drawImageRect(
            image,
            Rect.fromLTWH(col, 0, 1, image.height.toDouble()),
            Rect.fromLTWH(x, top, 2, h - top),
            paint);
      }
    }
    // Each side a half -- or, over its spectrum, both together.
    var peaks = this.peaks;
    if (peaks != null && fileSeconds > 0) {
      var stereo = spectrum == null && this.left != null && right != null;
      var sides = stereo ? [this.left!, right!] : [peaks];
      var band = (h - top) / sides.length;
      var wave = Paint()
        ..color = spectrum == null
            ? const Color(0xFF4F8FD6)
            : studio.text.withValues(alpha: 0.12)
        ..strokeWidth = 1;
      var outside = Paint()
        ..color = const Color(0xFF4F8FD6).withValues(alpha: 0.35)
        ..strokeWidth = 1;
      var first = loop ? math.min(start, loopStart) : start;
      // Only what is in view: zoomed far in, the whole is many windows wide.
      var shownTo = left + size.width;
      for (var (k0, side) in sides.indexed) {
        var mid = top + band * k0 + band / 2;
        var half = band / 2 - 4;
        for (var x = left.floorToDouble();
            x < math.min(shownTo, soundBeats * beatW);
            x += 1) {
          var from = playStart + secondOf(x / beatW);
          var to = playStart + secondOf((x + 1) / beatW);
          if (from >= playStart + playLength) break;
          var a = (from / fileSeconds * _peakSlices)
              .floor()
              .clamp(0, _peakSlices - 1);
          var b =
              (to / fileSeconds * _peakSlices).ceil().clamp(a + 1, _peakSlices);
          var v = 0.0;
          for (var k = a; k < b; k++) {
            v = math.max(v, side[k]);
          }
          var beat = x / beatW;
          // As warp.dart's _envelop makes it: its gain squared, its pan a
          // balance.
          var shaped = 1.0;
          if (gainCurve.isNotEmpty) {
            var g = curveAt(gainCurve, beat, 1);
            shaped = g * g;
          }
          if (panCurve.isNotEmpty) {
            var pan = curveAt(panCurve, beat, 0.5);
            if (stereo) {
              shaped *= k0 == 0
                  ? (pan > 0.5 ? 2 * (1 - pan) : 1)
                  : (pan < 0.5 ? 2 * pan : 1);
            }
          }
          var y = math.min(1.0, v * gain * shaped) * half;
          canvas.drawLine(Offset(x, mid - y), Offset(x, mid + y),
              beat < first || beat > loopEnd ? outside : wave);
        }
        if (stereo) {
          var tp = TextPainter(
              text: TextSpan(
                  text: k0 == 0 ? "L" : "R",
                  style: TextStyle(fontSize: 10, color: studio.muted)),
              textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, Offset(left + 3, mid - tp.height / 2));
        }
      }
      if (stereo) {
        canvas.drawLine(
            Offset(left, top + band),
            Offset(left + size.width, top + band),
            Paint()..color = studio.edge);
      }
    }
    var brace = Paint()
      ..color = (loop ? studio.on : studio.muted).withValues(alpha: 0.45);
    var loopGrip = Paint()..color = loop ? studio.on : studio.muted;
    canvas.drawRect(
        Rect.fromLTRB(loopStart * beatW, 2, loopEnd * beatW, 8), brace);
    canvas.drawRect(Rect.fromLTWH(loopStart * beatW - 2, 1, 4, 9), loopGrip);
    canvas.drawRect(Rect.fromLTWH(loopEnd * beatW - 2, 1, 4, 9), loopGrip);
    var sx = start * beatW;
    canvas.drawPath(
        Path()
          ..moveTo(sx, 11)
          ..lineTo(sx + 7, 15)
          ..lineTo(sx, 19)
          ..close(),
        Paint()..color = studio.text);
    canvas.drawLine(Offset(sx, 11), Offset(sx, h),
        Paint()..color = studio.text.withValues(alpha: 0.35));
    // The envelope: held flat before the first point and after the last.
    if (envelope case var points?) {
      double y(double v) => top + 6 + (1 - v) * math.max(1, h - top - 12);
      const colour = _envelopeInk;
      if (envelopeLabel.isNotEmpty) {
        var tp = TextPainter(
            text: TextSpan(
                text: envelopeLabel,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: colour)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(left + 8, top + 4));
      }
      var line = Paint()
        ..color = colour
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      var length = envelopeLength;
      Path once(double from, double to) {
        var path = Path();
        if (points.isEmpty) {
          return path
            ..moveTo(from, y(envelopeRest))
            ..lineTo(to, y(envelopeRest));
        }
        path.moveTo(from, y(points.first.$2));
        for (var (b, v) in points) {
          path.lineTo(from + b * beatW, y(v));
        }
        return path..lineTo(to, y(points.last.$2));
      }

      if (length == null || length <= 0) {
        canvas.drawPath(once(0, size.width), line);
      } else {
        // Repeated along the clip, the first pass the one edited.
        var span = length * beatW;
        canvas.drawPath(once(0, span), line);
        var faint = Paint()
          ..color = colour.withValues(alpha: 0.35)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (var x = span; x < size.width && span > 1; x += span) {
          canvas.drawPath(once(x, x + span), faint);
        }
        canvas.drawLine(Offset(span, top), Offset(span, h),
            Paint()..color = colour.withValues(alpha: 0.5));
      }
      for (var (b, v) in points) {
        canvas.drawCircle(Offset(b * beatW, y(v)), 4, Paint()..color = colour);
      }
    }
    // Its fades, the faded part shaded.
    void ramp(double from, double to, bool rising) {
      if (to <= from) return;
      var path = Path();
      var shade = Path()..moveTo(from * beatW, top);
      for (var k = 0; k <= 32; k++) {
        var u = k / 32;
        var level = fadeCurve.level(rising ? u : 1 - u);
        var x = (from + (to - from) * u) * beatW;
        var y = top + (h - top) * (1 - level);
        k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        shade.lineTo(x, y);
      }
      shade
        ..lineTo(to * beatW, top)
        ..close();
      canvas.drawPath(shade, Paint()..color = const Color(0x44000000));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _fadeInk);
    }

    var grip = Paint()..color = _fadeInk;
    canvas.drawRect(
        Rect.fromLTWH((start + fadeIn) * beatW - 4, top + 1, 8, 8), grip);
    canvas.drawRect(
        Rect.fromLTWH((loopEnd - fadeOut) * beatW - 4, top + 1, 8, 8), grip);

    if (fadeIn > 0) {
      ramp(start, start + fadeIn, true);
      if (loop && (loopStart - start).abs() > 1e-6) {
        ramp(loopStart, loopStart + fadeIn, true);
      }
    }
    if (fadeOut > 0) ramp(loopEnd - fadeOut, loopEnd, false);
    if (playhead case var p?) {
      canvas.drawLine(
          Offset(p * beatW, top),
          Offset(p * beatW, h),
          Paint()
            ..color = studio.text
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_SamplePainter old) =>
      old.peaks != peaks ||
      old.spectrum != spectrum ||
      old.key != key ||
      old.playhead != playhead ||
      old.start != start ||
      old.loopStart != loopStart ||
      old.loopEnd != loopEnd ||
      old.loop != loop ||
      old.gain != gain ||
      old.beatW != beatW ||
      old.playStart != playStart ||
      old.playLength != playLength ||
      old.hits.length != hits.length ||
      old.envelope != envelope ||
      old.gainCurve != gainCurve ||
      old.panCurve != panCurve ||
      old.envelopeLabel != envelopeLabel ||
      old.envelopeLength != envelopeLength ||
      old.envelopeRest != envelopeRest ||
      old.studio != studio;
}

/// beatsOfPlace is a place typed as Ableton's ("bar.beat.sixteenth",
/// "bar.beat" or "bar", each from one) in beats from the start at
/// [beatsPerBar]; null for what is not one.
double? beatsOfPlace(String text, int beatsPerBar) {
  var parts = text.trim().split(RegExp(r"[.:\s]+"));
  if (parts.isEmpty || parts.length > 3 || parts.first.isEmpty) return null;
  var n = [for (var p in parts) int.tryParse(p)];
  if (n.contains(null)) return null;
  var (bar, beat, sixteenth) =
      (n[0]!, n.length > 1 ? n[1]! : 1, n.length > 2 ? n[2]! : 1);
  if (bar < 1 ||
      beat < 1 ||
      beat > beatsPerBar ||
      sixteenth < 1 ||
      sixteenth > 4) {
    return null;
  }
  return (bar - 1) * beatsPerBar + (beat - 1) + (sixteenth - 1) / 4;
}

/// typedNumber is the number at the front of [text] ("-3", "+2.5 dB",
/// "−1") and its unit in lower case; null where there is no number.
(double, String)? typedNumber(String text) {
  var m = RegExp(r"^\s*([+\-−]?\d*\.?\d+)\s*([a-zA-Z%]*)")
      .firstMatch(text.trim());
  if (m == null) return null;
  var v = double.tryParse(m.group(1)!.replaceAll("−", "-").replaceAll("+", ""));
  if (v == null) return null;
  return (v, m.group(2)!.toLowerCase());
}

/// _TypedPlace is a place shown as bar.beat.sixteenth, typed into once
/// clicked: Return sets it, Escape or clicking away leaves it.
class _TypedPlace extends StatefulWidget {
  final String value;
  final TextStyle style;
  final TextAlign align;
  final ValueChanged<String> onTyped;

  /// doubleClick types into it on a double-click, as a setting's number is
  /// (a click is the slider's).
  final bool doubleClick;
  const _TypedPlace(
      {required this.value,
      required this.style,
      required this.onTyped,
      this.align = TextAlign.center,
      this.doubleClick = false,
      super.key});

  @override
  State<_TypedPlace> createState() => _TypedPlaceState();
}

class _TypedPlaceState extends State<_TypedPlace> {
  bool _typing = false;
  late final _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_typing) {
      void type() {
        _text.text = widget.value;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: widget.value.length);
        setState(() => _typing = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _focus.requestFocus());
      }

      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.doubleClick ? null : type,
          onDoubleTap: widget.doubleClick ? type : null,
          child: Text(widget.value,
              textAlign: widget.align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _typing = false),
      },
      child: TextField(
        key: const ValueKey("typedPlace"),
        controller: _text,
        focusNode: _focus,
        textAlign: widget.align,
        style: widget.style,
        decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero),
        onSubmitted: (v) {
          widget.onTyped(v);
          setState(() => _typing = false);
        },
      ),
    );
  }
}

Widget toolbarGroup(MixerLook look, List<Widget> children) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          border: Border.all(color: look.studio.edge),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

/// editorMenuItem is one choice in an editor toolbar's menu: ticked when
/// [on], with a [hint] under it.
MenuItemButton editorMenuItem(String key, String label, VoidCallback? tap,
        {bool on = false, String? hint}) =>
    MenuItemButton(
      key: ValueKey(key),
      leadingIcon: Icon(on ? Icons.check : null, size: 14),
      onPressed: tap,
      child: hint == null
          ? Text(label)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Text(label),
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFF9A98A6))),
                ]),
    );
