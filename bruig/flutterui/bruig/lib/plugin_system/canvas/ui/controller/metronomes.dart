part of '../canvas_controller.dart';

// Part of CanvasController: Metronome elements going (metronome_element.dart).
// Their state is the reader's, not the document's: started and stopped,
// sped up and slowed, tapped, each clicking and swinging on its own.

extension CanvasMetronomes on CanvasController {
  bool metronomeGoing(String id) => _metroStarted.containsKey(id);

  /// metronomeShowFor is how metronome [e] is going: how many beats since it
  /// was started, for its pendulum and lamp.
  MetronomeShow metronomeShowFor(MetronomeElement e) {
    var from = _metroStarted[e.id];
    if (from == null) return const MetronomeShow();
    var seconds = _metroClock.elapsedMicroseconds / 1e6 - from;
    return MetronomeShow(going: true, beats: seconds * e.bpm / 60);
  }

  void toggleMetronome(MetronomeElement e) {
    if (_metroStarted.remove(e.id) != null) {
      audio.metronome(on: false, key: e.id);
    } else {
      _metroStart(e);
    }
    keysHeld.value++;
    notifyListeners();
  }

  void _metroStart(MetronomeElement e) {
    if (!_metroClock.isRunning) _metroClock.start();
    _metroStarted[e.id] = _metroClock.elapsedMicroseconds / 1e6;
    audio.metronome(
        on: true,
        key: e.id,
        at: 0,
        secondsPerBeat: 60 / e.bpm,
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

  /// setMetronome writes [e] over the one with its id; if it was going, it
  /// goes on at the new speed from its next beat.
  void setMetronome(MetronomeElement e) {
    replaceElement(e);
    if (metronomeGoing(e.id)) _metroStart(e);
  }

  /// metronomeStep makes [e] [by] beats a minute faster (or slower).
  void metronomeStep(MetronomeElement e, double by) =>
      setMetronome(e.copyWith(bpm: e.bpm + by));

  /// cycleMetronomeBeats steps [e]'s bar on through metronomeBeats.
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
