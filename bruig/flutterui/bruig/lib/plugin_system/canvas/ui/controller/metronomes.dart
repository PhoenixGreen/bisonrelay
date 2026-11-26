part of '../canvas_controller.dart';

// Part of CanvasController: Metronome elements going (metronome_element.dart).
// Their state is the reader's, not the document's: started and stopped,
// sped up and slowed, tapped, each clicking and swinging on its own.

extension CanvasMetronomes on CanvasController {
  /// metronomeGoing is whether metronome [id] is going.
  bool metronomeGoing(String id) => _metroStarted.containsKey(id);

  /// metronomeShowFor is how metronome [e] is going: how many beats it has
  /// gone, for its pendulum and lamp. They keep time with its click: taken
  /// from where the click has been heard to; held on the beat it starts
  /// from while the sound gets ready, so the swing does not run ahead of
  /// the first click; and by the clock alone where there is no sound.
  MetronomeShow metronomeShowFor(MetronomeElement e) {
    var started = _metroStarted[e.id];
    if (started == null) return const MetronomeShow();
    var perBeat = 60 / e.bpm;
    if (audio.metronomeHeard(e.id) case var heard?) {
      return MetronomeShow(going: true, beats: heard / perBeat);
    }
    if (audio.metronomeWaiting(e.id)) {
      return MetronomeShow(going: true, beats: started.from);
    }
    var seconds = _metroClock.elapsedMicroseconds / 1e6 - started.at;
    return MetronomeShow(going: true, beats: started.from + seconds / perBeat);
  }

  /// toggleMetronome starts [e] from its first beat, or stops it.
  void toggleMetronome(MetronomeElement e) {
    if (_metroStarted.remove(e.id) != null) {
      audio.metronome(on: false, key: e.id);
    } else {
      _metroStart(e);
    }
    keysHeld.value++;
    notifyListeners();
  }

  /// _metroStart starts [e]'s swing and click from [beat] beats in: the
  /// click track is played from there, so its next click falls on the next
  /// beat, the bar's first as louder as ever.
  void _metroStart(MetronomeElement e, {double beat = 0}) {
    if (!_metroClock.isRunning) _metroClock.start();
    _metroStarted[e.id] =
        (at: _metroClock.elapsedMicroseconds / 1e6, from: beat);
    var perBeat = 60 / e.bpm;
    audio.metronome(
        on: true,
        key: e.id,
        at: beat * perBeat,
        secondsPerBeat: perBeat,
        beatsPerBar: e.beats);
    _metroTicking();
  }

  /// _metroTicking redraws the metronomes going, about thirty times a
  /// second, until none is.
  void _metroTicking() {
    _metroTick ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      // One taken away while going: stopped with it.
      for (var id in [..._metroStarted.keys]) {
        if (_document.elementById(id) is! MetronomeElement) {
          _metroStarted.remove(id);
          audio.metronome(on: false, key: id);
        }
      }
      if (_metroStarted.isEmpty) {
        _metroTick?.cancel();
        _metroTick = null;
        return;
      }
      keysHeld.value++;
    });
  }

  /// setMetronome writes [e] over the one with its id. If it was going and
  /// its tempo or its beats in a bar changed, it goes on from the beat it
  /// was on, at the new tempo and in the new bar; any other change (its
  /// colours) leaves its swing and click as they were.
  void setMetronome(MetronomeElement e) {
    var was = _document.elementById(e.id);
    replaceElement(e);
    if (!metronomeGoing(e.id) || was is! MetronomeElement) return;
    if (was.bpm == e.bpm && was.beats == e.beats) return;
    _metroStart(e, beat: metronomeShowFor(was).beats);
  }

  /// metronomeStep makes [e] [by] beats a minute faster (or slower).
  void metronomeStep(MetronomeElement e, double by) =>
      setMetronome(e.copyWith(bpm: e.bpm + by));

  /// cycleMetronomeBeats steps [e]'s bar on through metronomeBeats, from the
  /// most it holds round to one.
  void cycleMetronomeBeats(MetronomeElement e) {
    var i = metronomeBeats.indexOf(e.beats);
    setMetronome(
        e.copyWith(beats: metronomeBeats[(i + 1) % metronomeBeats.length]));
  }

  /// tapMetronome sets [e]'s tempo from the pace of the last few taps, a
  /// moment apart at most, from the second tap on. [at] stands in for now,
  /// in seconds, in tests.
  void tapMetronome(MetronomeElement e, {double? at}) {
    if (!_metroClock.isRunning) _metroClock.start();
    var now = at ?? _metroClock.elapsedMicroseconds / 1e6;
    var taps = _metroTaps.putIfAbsent(e.id, () => []);
    if (taps.isNotEmpty && now - taps.last > 2.5) taps.clear();
    taps.add(now);
    if (taps.length > 5) taps.removeAt(0);
    if (taps.length < 2) return;
    var gap = (taps.last - taps.first) / (taps.length - 1);
    if (gap <= 0) return;
    setMetronome(e.copyWith(bpm: 60 / gap));
  }
}
