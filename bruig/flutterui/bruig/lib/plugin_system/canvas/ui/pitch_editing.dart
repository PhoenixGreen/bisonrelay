import 'dart:async';
import 'dart:isolate';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart' show snapNote;
import 'package:bruig/plugin_system/canvas/media/phrasing.dart' show readTake;
import 'package:bruig/plugin_system/canvas/model/instrument.dart' show MidiNote;
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart'
    show newInstrument;
import 'package:bruig/plugin_system/canvas/media/pitch_retune.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show wav16;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/foundation.dart';

// pitch_editing.dart is what the Pitch editor does to a channel's
// recording: read its pitch once, find its notes, change them, and make
// the recording again from the original with them -- a moment after the
// last change, as the Phrasing editor shapes a take.

/// _tracks are recordings' pitch tracks as read, by asset: a MIDI note
/// every 20ms, null where nothing is voiced.
final Map<String, List<double?>> _tracks = {};
final Set<String> _reading = {};

/// _unread are the recordings whose pitch could not be read: said so,
/// rather than "Reading its pitch…" for ever.
final Set<String> _unread = {};

/// pitchTracksRead goes up as each recording's pitch is read, for an
/// editor waiting on one to draw it.
final ValueNotifier<int> pitchTracksRead = ValueNotifier(0);

/// _renders are each controller's waits before making a recording again.
final Expando<Timer> _renders = Expando("pitchRenders");

/// _asSung are, by controller, the channels heard as sung -- the Pitch
/// editor's Hear: As sung -- each with the recording made from its notes,
/// to go back to.
final Expando<Map<String, String>> _asSung = Expando("pitchAsSung");

/// pitchTrackSeed puts [track] in for [assetId], as read: for tests.
@visibleForTesting
void pitchTrackSeed(String assetId, List<double?> track) =>
    _tracks[assetId] = track;

extension PitchEditing on CanvasController {
  /// notesToMidi makes a MIDI channel playing [key]'s recording's notes --
  /// as edited in the Pitch editor, or as sung -- each on the nearest note
  /// of the scale [root] and [steps] give (every note, with none), from
  /// where the recording starts: the prototype's Auto-tune "Notes to MIDI".
  /// Answers why not, or null.
  String? notesToMidi(String key, {int root = 0, List<int> steps = const []}) {
    var e = pitchElementOf(key);
    if (e == null) return "There is no recording on this channel.";
    var source = e.clip.playlist.first;
    var found = source.pitch?.notes ??
        switch (pitchTrackOf(key)) {
          var track? => findNotes(track),
          null => null,
        };
    if (found == null) return "Still listening to it: try again in a moment.";
    if (found.isEmpty) return "No notes were heard in it.";
    var notes = [
      for (var n in found)
        if (n.end > source.start)
          MidiNote(
              snapNote(n.target, root, steps).round().clamp(0, 127),
              (n.start - source.start).clamp(0.0, double.infinity),
              n.length,
              100),
    ];
    var made = newInstrument(document);
    made = made
        .copyWith(
            instrument: made.instrument!.copyWith(notes: notes),
            clip: made.clip.copyWith(at: e.clip.at))
        .rebase(made.base.copyWith(
            name: "${e.name.isEmpty ? "Recording" : e.name} notes",
            visible: false)) as AudioElement;
    addElement(made);
    return null;
  }

  /// pitchElementOf is the sound on channel [key] the Pitch editor works
  /// on: its first, with a recording.
  AudioElement? pitchElementOf(String key) {
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    for (var l in lane?.lanes ?? const []) {
      if (l.element case AudioElement a
          when a.clip.playlist.isNotEmpty &&
              a.clip.playlist.first.assetId.isNotEmpty) {
        return a;
      }
    }
    return null;
  }

  /// pitchSourceOf is that sound's recording.
  MediaSource? pitchSourceOf(String key) =>
      pitchElementOf(key)?.clip.playlist.first;

  /// pitchTrackOf is the pitch of [key]'s recording as it was made, every
  /// 20ms, or null while it is being read (asked once; see
  /// pitchTracksRead).
  List<double?>? pitchTrackOf(String key) {
    var source = pitchSourceOf(key);
    if (source == null) return null;
    var id = source.pitch?.original ?? source.assetId;
    if (_tracks[id] case var t?) return t;
    if (!_unread.contains(id) && _reading.add(id)) unawaited(_read(id));
    return null;
  }

  /// pitchUnreadable is whether [key]'s recording's pitch could not be
  /// read: its file missing, or not a sound.
  bool pitchUnreadable(String key) {
    var source = pitchSourceOf(key);
    if (source == null) return false;
    return _unread.contains(source.pitch?.original ?? source.assetId);
  }

  Future<void> _read(String id) async {
    try {
      var pcm = await CanvasController.takeAudio(id);
      if (pcm == null) {
        _unread.add(id);
        return;
      }
      var reading = await Isolate.run(() => readTake(pcm, const []));
      _tracks[id] = reading.pitch;
    } catch (exception) {
      debugPrint("A recording's pitch could not be read: $exception");
      _unread.add(id);
    } finally {
      _reading.remove(id);
      pitchTracksRead.value++;
    }
  }

  /// pitchPlayhead is where the playhead is in [key]'s recording, in
  /// seconds from the start of its file, or null where it is not over it.
  double? pitchPlayhead(String key) {
    var e = pitchElementOf(key);
    var source = e?.clip.playlist.first;
    if (e == null || source == null) return null;
    var t = (frame - e.clip.at) / document.frameRate + source.start;
    var end = source.end > 0 ? source.end : source.length;
    return t < source.start || t > end ? null : t;
  }

  /// pitchEditOf is [key]'s recording's notes, as edited, or null where
  /// they have not been found yet.
  PitchEdit? pitchEditOf(String key) => pitchSourceOf(key)?.pitch;

  /// findPitchNotes finds [key]'s recording's notes, to edit: from its
  /// pitch once read. True where they are there to edit.
  bool findPitchNotes(String key) {
    var source = pitchSourceOf(key);
    if (source == null) return false;
    if (source.pitch != null) return true;
    var track = pitchTrackOf(key);
    if (track == null) return false;
    _setSource(
        key,
        source.copyWith(
            pitch: PitchEdit(source.assetId, notes: findNotes(track))));
    return true;
  }

  /// editPitch changes [key]'s recording's notes: an undo step, or --
  /// [transient] -- part of a drag that is. The recording is made again a
  /// moment after the last change.
  void editPitch(String key, PitchEdit Function(PitchEdit edit) change,
      {bool transient = false}) {
    var source = pitchSourceOf(key);
    var edit = source?.pitch;
    if (source == null || edit == null) return;
    _setSource(key, source.copyWith(pitch: change(edit)), transient: transient);
    _renderSoon(key);
  }

  /// pitchHeardAsSung is whether [key]'s recording is heard as sung, its
  /// notes as they were: see hearPitchAsSung.
  bool pitchHeardAsSung(String key) => _asSung[this]?.containsKey(key) ?? false;

  /// hearPitchAsSung plays [key]'s recording as sung, or -- not [asSung]
  /// -- as its notes make it: to hear the difference. Not a change to undo.
  void hearPitchAsSung(String key, bool asSung) {
    var source = pitchSourceOf(key);
    var edit = source?.pitch;
    if (source == null || edit == null) return;
    var held = _asSung[this] ??= {};
    if (asSung == held.containsKey(key)) return;
    if (asSung) {
      held[key] = source.assetId;
      _setSource(key, source.copyWith(assetId: edit.original), transient: true);
    } else {
      var made = held.remove(key)!;
      _setSource(key, source.copyWith(assetId: made), transient: true);
    }
  }

  /// forgetPitch puts [key]'s recording back as it was made.
  void forgetPitch(String key) {
    var source = pitchSourceOf(key);
    var edit = source?.pitch;
    if (source == null || edit == null) return;
    _asSung[this]?.remove(key);
    _setSource(key, source.copyWith(assetId: edit.original, clearPitch: true));
  }

  void _setSource(String key, MediaSource next, {bool transient = false}) {
    var e = pitchElementOf(key);
    if (e == null) return;
    replaceElement(
        e.copyWith(
            clip:
                e.clip.copyWith(playlist: [next, ...e.clip.playlist.skip(1)])),
        transient: transient);
  }

  void _renderSoon(String key) {
    _renders[this]?.cancel();
    _renders[this] = Timer(
        const Duration(milliseconds: 300), () => unawaited(renderPitch(key)));
  }

  /// renderPitch makes [key]'s recording again with its notes as they are,
  /// where they have changed since it was last made: from the original, the
  /// notes changed said at their pitches, the rest as it was. Not an undo
  /// step of its own: what is undone is the change to the notes.
  Future<void> renderPitch(String key) async {
    var edit = pitchEditOf(key);
    if (edit == null || !edit.stale) return;
    var track = _tracks[edit.original];
    var made = edit.key;
    String? id;
    if (edit.notes.any((n) => n.edited)) {
      var pcm = await CanvasController.takeAudio(edit.original);
      if (pcm == null || track == null) return;
      var notes = edit.notes;
      var out = await Isolate.run(() => retuneTake(pcm, track, notes));
      id = await CanvasController.keepRecording(wav16(out, out));
      if (id == null) return;
    } else {
      id = edit.original;
    }
    // Changed again meanwhile: made next.
    var now = pitchSourceOf(key);
    if (now?.pitch == null || now!.pitch!.key != made) return;
    // Heard as sung: kept to go back to, the original still playing.
    var held = _asSung[this];
    if (held != null && held.containsKey(key)) {
      held[key] = id;
      id = now.assetId;
    }
    _setSource(key,
        now.copyWith(assetId: id, pitch: now.pitch!.copyWith(madeWith: made)),
        transient: true);
  }
}

/// pitchTrackOfPcm reads [pcm]'s pitch: for tests that have no files.
@visibleForTesting
List<double?> pitchTrackOfPcm(Float32List pcm) => readTake(pcm, const []).pitch;
