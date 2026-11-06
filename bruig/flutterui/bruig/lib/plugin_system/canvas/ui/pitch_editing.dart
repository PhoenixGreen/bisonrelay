import 'dart:async';
import 'dart:isolate';

import 'package:bruig/plugin_system/canvas/media/phrasing.dart' show readTake;
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

/// pitchTracksRead goes up as each recording's pitch is read, for an
/// editor waiting on one to draw it.
final ValueNotifier<int> pitchTracksRead = ValueNotifier(0);

/// _renders are each controller's waits before making a recording again.
final Expando<Timer> _renders = Expando("pitchRenders");

/// pitchTrackSeed puts [track] in for [assetId], as read: for tests.
@visibleForTesting
void pitchTrackSeed(String assetId, List<double?> track) =>
    _tracks[assetId] = track;

extension PitchEditing on CanvasController {
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
    if (_reading.add(id)) unawaited(_read(id));
    return null;
  }

  Future<void> _read(String id) async {
    try {
      var pcm = await CanvasController.takeAudio(id);
      if (pcm == null) return;
      var reading = await Isolate.run(() => readTake(pcm, const []));
      _tracks[id] = reading.pitch;
      pitchTracksRead.value++;
    } finally {
      _reading.remove(id);
    }
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

  /// forgetPitch puts [key]'s recording back as it was made.
  void forgetPitch(String key) {
    var source = pitchSourceOf(key);
    var edit = source?.pitch;
    if (source == null || edit == null) return;
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
    _setSource(key,
        now.copyWith(assetId: id, pitch: now.pitch!.copyWith(madeWith: made)),
        transient: true);
  }
}

/// pitchTrackOfPcm reads [pcm]'s pitch: for tests that have no files.
@visibleForTesting
List<double?> pitchTrackOfPcm(Float32List pcm) => readTake(pcm, const []).pitch;
