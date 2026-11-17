part of '../canvas_controller.dart';

// Clips played live: a slot's state, what a playing clip, a recording and a
// repeat keep, the work done off the UI isolate (sound written, reversed,
// warped and sung, a tempo found), and what the piano roll edits. Part of
// canvas_controller.dart.

/// ClipState is how a clip slot is doing, for the mixer to draw.
enum ClipState {
  empty,
  stopped,
  queued,
  playing,
  stopping,
  recordQueued,
  recording
}

/// _ClipPlay is a clip playing from a slot, or about to: from [from],
/// session seconds, round every [length] -- or once.
class _ClipPlay {
  final String clipId;
  final int row;

  /// from is when it is heard, session seconds.
  final double from;

  /// length is its loop's length; not looping, how long it plays.
  final double length;
  final bool loops;

  /// startAt and loopAt are where it and its loop start, seconds into it.
  final double startAt, loopAt;

  /// origin is when it would have started from its start: [from], or
  /// earlier where it took over another's place -- legato.
  double origin;

  /// followed is whether its follow action is done, and followFrom when its
  /// wait began: [from], or that of the clip it carries on from.
  bool followed = false;
  late double followFrom = from;

  /// sound is what it plays: its own sound, or that warped.
  MediaSource? sound;
  AudioVoice? voice;
  double? stopAt;

  /// level is how loud it was launched, nought to one: see launchLevel.
  double level = 1;
  _ClipPlay(this.clipId, this.row, this.from, this.length, this.loops,
      {this.startAt = 0, this.loopAt = 0})
      : origin = from;

  /// into is where it is [t] seconds after its origin, in seconds into what
  /// it plays: on from its start, then round its loop.
  double into(double t) {
    if (!loops) return startAt + t;
    var run = loopAt + length - startAt;
    if (t < run) return startAt + t;
    return loopAt + (t - run) % length;
  }
}

// ---- Work for another isolate
//
// Each starts from a top-level function: a closure made in a controller
// method can capture the controller and its timers, which cannot be sent.

/// _wavAway is [l] and [r] as a WAV file's bytes, made in another isolate.
Future<Uint8List> _wavAway(Float32List l, Float32List r) =>
    Isolate.run(() => wav16(l, r));

/// _reversedWavAway is [l] and [r] turned round, as a WAV file's bytes.
Future<Uint8List> _reversedWavAway(Float32List l, Float32List r) =>
    Isolate.run(() {
      var n = l.length;
      var rl = Float32List(n), rr = Float32List(n);
      for (var i = 0; i < n; i++) {
        rl[i] = l[n - 1 - i];
        rr[i] = r[n - 1 - i];
      }
      return wav16(rl, rr);
    });

/// _warpedWavAway is a clip's sound warped -- see renderWarp -- as a WAV
/// file's bytes, and how many frames long it is.
Future<(Uint8List, int)> _warpedWavAway(
        Float32List l,
        Float32List r,
        double from,
        double to,
        bool warp,
        WarpMode mode,
        WarpMap map,
        double secondsPerBeat,
        double semitones,
        Map<ClipEnvelope, List<ControlPoint>> envelopes,
        ({
          List<(double, double)> ins,
          List<(double, double)> outs,
          FadeCurve curve
        })? fades) =>
    Isolate.run(() {
      var (wl, wr) = renderWarp(l, r,
          from: from,
          to: to,
          warp: warp,
          mode: mode,
          map: map,
          secondsPerBeat: secondsPerBeat,
          semitones: semitones,
          envelopes: envelopes);
      if (fades != null) {
        fadeEdges(wl, wr,
            ins: fades.ins, outs: fades.outs, curve: fades.curve.level);
      }
      return (wav16(wl, wr), wl.length);
    });

/// _sungAway is [singTake], in another isolate.
Future<Float32List> _sungAway(
        Float32List source, List<SungNote> sung, SingSettings settings) =>
    Isolate.run(() => singTake(source, sung, settings: settings));

/// _tempoAway is [estimateTempo], in another isolate.
Future<double> _tempoAway(
        Float32List l, Float32List r, double near, int beatsPerBar) =>
    Isolate.run(
        () => estimateTempo(l, r, near: near, beatsPerBar: beatsPerBar));

/// clipPieces are what [clip] plays over [seconds] from its start: each a
/// stretch (from and to, seconds into what it plays) and when it is heard,
/// from the start on to the loop's end, then round the loop.
List<(double, double, double)> clipPieces(SessionClip clip, double seconds,
    double secondsPerBeat, double secondsPerBar) {
  var length = math.max(0.05, clip.bars * secondsPerBar);
  var loopAt = clip.loopStart * secondsPerBeat, loopEnd = loopAt + length;
  var start = clip.start * secondsPerBeat;
  if (start >= loopEnd) start = loopAt;
  var out = <(double, double, double)>[];
  var heard = 0.0;
  var from = start;
  while (heard < seconds - 0.001) {
    var to = math.min(loopEnd, from + seconds - heard);
    out.add((from, to, heard));
    heard += to - from;
    if (!clip.loop) break;
    from = loopAt;
  }
  return out;
}

/// _ClipChannel is a channel's slots at play: what it plays now, what it is
/// to play next, and when it stops.
class _ClipChannel {
  final String channel;
  _ClipPlay? now, next;
  double? stopAt;
  _ClipChannel(this.channel);
}

/// _ClipRecord is a slot being recorded into: from [from], session seconds,
/// until [until] once it is set; its notes in beats from [from].
class _ClipRecord {
  final String channel;
  final int row;
  final double from;
  double? until;
  bool started = false;
  final Map<int, (double, int)> held = {};
  final List<MidiNote> notes = [];
  _ClipRecord(this.channel, this.row, this.from);
}

/// _Repeat is a Repeat clip held down: its row, when it is launched again,
/// how often, and how loud.
class _Repeat {
  final int row;
  double nextAt;
  final double step;
  final double level;
  _Repeat(this.row, this.nextAt, this.step, this.level);
}

/// _ClipPlayed is a clip played from a slot while Record was on, from and
/// to session seconds.
class _ClipPlayed {
  final String channel;
  final SessionClip clip;
  final double from, to;
  _ClipPlayed(this.channel, this.clip, this.from, this.to);
}

/// _LiveArp is an arpeggiator playing live: the keys held, each as the keys
/// it sounds through the effects before it, and the one sounding.
class _LiveArp {
  final Arpeggio player;
  final Map<int, List<int>> pressed = {};

  /// velocities are each key's loudest note through the Velocity effect: a
  /// step plays as loud as the loudest held, as the rendered one does.
  final Map<int, int> velocities = {};
  int? sounding;

  /// played is the steps sounded so far: a step's gate lets go of that step
  /// alone, not the same key struck again on the next.
  int played = 0;

  Timer? timer;
  _LiveArp(this.player);

  int get velocity => velocities.values.fold(1, math.max);
}

/// PianoRollTarget is what the piano roll edits: MIDI channel [channel]'s
/// clip in slot [row], or with no row its part.
class PianoRollTarget {
  final String channel;
  final int? row;
  const PianoRollTarget(this.channel, this.row);
}

/// RollContent is what the piano roll shows, in beats -- see
/// CanvasController.rollContent.
class RollContent {
  final List<MidiNote> notes;
  final Map<MidiControl, List<ControlPoint>> controls;
  final double beats;
  final String name;
  final bool clip;
  const RollContent(this.notes, this.controls, this.beats,
      {required this.name, required this.clip});
}
