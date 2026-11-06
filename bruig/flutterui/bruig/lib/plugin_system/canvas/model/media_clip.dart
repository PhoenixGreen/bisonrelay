import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonInt, jsonSpec, jsonString, jsonStr;
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart'
    show SpeechLine, SpeechTake;
import 'package:bruig/plugin_system/canvas/model/surround.dart';
export 'package:bruig/plugin_system/canvas/model/surround.dart'
    show SoundPlacement, PlaceBy;

// media_clip.dart is what is played: which files, which part of each, the
// fades and the loop. Audio and Video elements share it, so play range,
// fades and playlist have one meaning and one set of controls.
//
// Times are seconds into the file, not frames, so changing the canvas's
// frame rate leaves them alone.

/// MediaLoop is what happens when the end is reached.
enum MediaLoop {
  none("Play once", "Stop at the end of the list"),
  one("Repeat each", "Play the current file again, and again"),
  all("Repeat the list", "Back to the first file after the last");

  final String label;
  final String description;
  const MediaLoop(this.label, this.description);

  static MediaLoop fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => none);
}

/// MediaSource is one file in a playlist, and the part of it that plays.
class MediaSource {
  /// assetId is the file in the media store (CanvasMedia), named by a hash
  /// of its bytes.
  final String assetId;

  /// name is what the file was called when it was added, for the list.
  final String name;

  /// start and end are the play range, in seconds into the file. An end of
  /// nought means "to the end".
  final double start;
  final double end;

  /// length is how long the whole file is, in seconds, or nought when not
  /// known. Recorded when the file is added so [span] and the range fields
  /// need not open the file; the player asks the file itself.
  final double length;

  /// posterId, soundId, width, height and fps describe a video file, found
  /// when it was added (ui/media_picking.dart).
  ///
  /// The poster is a still stored as an ordinary picture, so an export or a
  /// bundle opened without ffmpeg still shows the video. The sound is the
  /// file's audio extracted into the audio store, which the audio engine
  /// plays in step with the picture. Empty for a sound or a silent video.
  final String posterId;
  final String soundId;
  final int width;
  final int height;
  final double fps;

  /// pitch is its notes moved (see pitch_edit.dart), or null: [assetId] is
  /// then the recording made with them, and pitch.original the one made.
  final PitchEdit? pitch;

  const MediaSource({
    required this.assetId,
    this.name = "",
    this.start = 0,
    this.end = 0,
    this.length = 0,
    this.posterId = "",
    this.soundId = "",
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.pitch,
  });

  /// endOr is where playing stops, given the file's real length.
  double endOr(double fileLength) {
    var stop = end > 0 ? end : fileLength;
    if (fileLength > 0) stop = math.min(stop, fileLength);
    return math.max(start, stop);
  }

  /// span is how long the range plays for, where that can be known.
  double get span {
    var stop = end > 0 ? end : length;
    return stop > start ? stop - start : 0;
  }

  MediaSource copyWith({
    String? assetId,
    String? name,
    double? start,
    double? end,
    double? length,
    String? posterId,
    String? soundId,
    PitchEdit? pitch,
    bool clearPitch = false,
  }) =>
      MediaSource(
        assetId: assetId ?? this.assetId,
        name: name ?? this.name,
        start: start ?? this.start,
        end: end ?? this.end,
        length: length ?? this.length,
        posterId: posterId ?? this.posterId,
        soundId: soundId ?? this.soundId,
        width: width,
        height: height,
        fps: fps,
        pitch: clearPitch ? null : pitch ?? this.pitch,
      );

  Map<String, dynamic> toJson() => {
        "asset": assetId,
        if (name.isNotEmpty) "name": name,
        if (start > 0) "start": start,
        if (end > 0) "end": end,
        if (length > 0) "length": length,
        if (posterId.isNotEmpty) "poster": posterId,
        if (soundId.isNotEmpty) "sound": soundId,
        if (width > 0) "w": width,
        if (height > 0) "h": height,
        if (fps > 0) "fps": fps,
        if (pitch != null) "pitch": pitch!.toJson(),
      };

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    var start = math.max(0.0, jsonDouble(json["start"], 0));
    var end = math.max(0.0, jsonDouble(json["end"], 0));
    return MediaSource(
      assetId: jsonString(json["asset"], ""),
      name: jsonString(json["name"], ""),
      start: start,
      // An end before the start would play nothing: taken as "to the end".
      end: end > start ? end : 0,
      length: jsonDouble(json["length"], 0).clamp(0.0, 6 * 3600.0),
      posterId: jsonString(json["poster"], ""),
      soundId: jsonString(json["sound"], ""),
      width: jsonInt(json["w"], 0),
      height: jsonInt(json["h"], 0),
      fps: math.max(0.0, jsonDouble(json["fps"], 0)),
      pitch: PitchEdit.fromJson(json["pitch"]),
    );
  }
}

/// MediaClip is everything about how a piece of media plays.
class MediaClip {
  /// playlist is the files, played in order. One file is a playlist of one.
  final List<MediaSource> playlist;

  /// volume is the level it opens at (the reader can move it).
  final double volume;

  /// muted is whether it opens silent.
  final bool muted;

  /// fadeIn and fadeOut are seconds at the start and end of each file's
  /// range (each file, not the list, or files would click at every join).
  final double fadeIn;
  final double fadeOut;

  final MediaLoop loop;

  /// autoplay starts it when its page opens, and on the master when the
  /// document does.
  final bool autoplay;

  /// acrossPages is for media on the master: it plays on from one page or
  /// scene to the next rather than stopping at the join. Elsewhere it has no
  /// effect: a sound stops when its page is left.
  final bool acrossPages;

  /// timed puts the media on the timeline: it plays with the playhead from
  /// frame [at] (of its scene, or of the whole run on the master) rather
  /// than on its own clock when pressed.
  final bool timed;
  final int at;

  /// mix is this clip's channel strip on the mixer. See mix.dart.
  final ChannelMix mix;

  /// channel is the timeline channel a sound is on, and channelName its
  /// name. Sounds share a channel by sharing its id; a channel exists only
  /// while a sound is on it. Empty for media on a lane of its own.
  ///
  /// The channel's strip ([mix]) is kept identical on every sound in it.
  final String channel;
  final String channelName;

  /// place is where the sound is heard from, taken from the picture; when
  /// off, the channel's own pan applies.
  final SoundPlacement place;

  const MediaClip({
    this.place = const SoundPlacement(),
    this.playlist = const [],
    this.volume = 0.8,
    this.muted = false,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.loop = MediaLoop.none,
    this.autoplay = false,
    this.acrossPages = true,
    this.timed = false,
    this.at = 0,
    this.mix = const ChannelMix(),
    this.channel = "",
    this.channelName = "",
  });

  bool get isEmpty => playlist.every((s) => s.assetId.isEmpty);

  /// mediaIds is every stored file this clip refers to. See CanvasMedia.
  Set<String> get mediaIds => {
        for (var s in playlist) ...[
          if (s.assetId.isNotEmpty) s.assetId,
          if (s.soundId.isNotEmpty) s.soundId,
          // The recording its notes were moved from.
          if (s.pitch case var p?) p.original,
        ],
        // Its channel's Speech takes: the Vocaliser sings the latest even
        // when its clip is off the timeline.
        for (var t in mix.speech?.takes ?? const <SpeechTake>[]) ...t.ids,
        // And each line's takes, which the clip is joined from again.
        for (var l in mix.speech?.lines ?? const <SpeechLine>[])
          for (var t in l.takes) ...t.ids,
      };

  /// posterIds is the video stills, kept in the picture store. See
  /// MediaSource.posterId.
  Set<String> get posterIds => {
        for (var s in playlist)
          if (s.posterId.isNotEmpty) s.posterId,
      };

  /// runLength is the playlist's play-through time in seconds. A file of
  /// unknown length counts as nothing.
  double get runLength => playlist.fold(0.0, (sum, s) => sum + s.span);

  /// momentAt is what is playing [seconds] after the clip starts on the
  /// timeline (file, time in it, gain), or null when nothing is.
  ///
  /// The editor, the channel drawing and the exporter all ask this, so they
  /// agree. On the timeline any repeat goes round the whole list: "each" is
  /// for media on its own clock, played until somebody stops it.
  ClipMoment? momentAt(double seconds) {
    var total = runLength;
    if (seconds < 0 || total <= 0) return null;
    if (seconds >= total) {
      if (loop == MediaLoop.none) return null;
      seconds %= total;
    }
    var from = 0.0;
    for (var (i, source) in playlist.indexed) {
      var span = source.span;
      if (span <= 0) continue;
      if (seconds < from + span) {
        var into = seconds - from;
        var gain = 1.0;
        if (fadeIn > 0) gain = math.min(gain, into / fadeIn);
        if (fadeOut > 0) gain = math.min(gain, (span - into) / fadeOut);
        return ClipMoment(i, source.start + into, gain.clamp(0.0, 1.0));
      }
      from += span;
    }
    return null;
  }

  MediaClip copyWith({
    List<MediaSource>? playlist,
    double? volume,
    bool? muted,
    double? fadeIn,
    double? fadeOut,
    MediaLoop? loop,
    bool? autoplay,
    bool? acrossPages,
    bool? timed,
    int? at,
    ChannelMix? mix,
    String? channel,
    String? channelName,
    SoundPlacement? place,
  }) =>
      MediaClip(
        place: place ?? this.place,
        playlist: playlist ?? this.playlist,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        fadeIn: fadeIn ?? this.fadeIn,
        fadeOut: fadeOut ?? this.fadeOut,
        loop: loop ?? this.loop,
        autoplay: autoplay ?? this.autoplay,
        acrossPages: acrossPages ?? this.acrossPages,
        timed: timed ?? this.timed,
        at: at ?? this.at,
        mix: mix ?? this.mix,
        channel: channel ?? this.channel,
        channelName: channelName ?? this.channelName,
      );

  Map<String, dynamic> toJson() => {
        if (playlist.isNotEmpty)
          "playlist": [for (var s in playlist) s.toJson()],
        if (volume != 0.8) "volume": volume,
        if (muted) "muted": true,
        if (fadeIn > 0) "fadeIn": fadeIn,
        if (fadeOut > 0) "fadeOut": fadeOut,
        if (loop != MediaLoop.none) "loop": loop.name,
        if (autoplay) "autoplay": true,
        if (!acrossPages) "stopsAtJoin": true,
        if (timed) "timed": true,
        if (at != 0) "at": at,
        if (!mix.isDefault) "mix": mix.toJson(),
        if (channel.isNotEmpty) "channel": channel,
        if (channelName.isNotEmpty) "channelName": channelName,
        if (!place.isOff) "place": place.toJson(),
      };

  factory MediaClip.fromJson(Map<String, dynamic> json) {
    var raw = json["playlist"];
    return MediaClip(
      playlist: raw is List
          ? [
              for (var s in raw)
                if (s is Map<String, dynamic>) MediaSource.fromJson(s),
            ]
          : const [],
      // Up to twice (+6 dB) for a sound on the timeline.
      volume: jsonDouble(json["volume"], 0.8).clamp(0.0, 2.0),
      muted: jsonBool(json["muted"], false),
      fadeIn: math.max(0.0, jsonDouble(json["fadeIn"], 0)),
      fadeOut: math.max(0.0, jsonDouble(json["fadeOut"], 0)),
      loop: MediaLoop.fromName(jsonStr(json["loop"])),
      autoplay: jsonBool(json["autoplay"], false),
      acrossPages: !jsonBool(json["stopsAtJoin"], false),
      timed: jsonBool(json["timed"], false),
      at: math.max(0, jsonInt(json["at"], 0)),
      mix: jsonSpec(json["mix"], ChannelMix.fromJson, const ChannelMix()),
      channel: json["channel"] is String ? json["channel"] as String : "",
      channelName:
          json["channelName"] is String ? json["channelName"] as String : "",
      place: json["place"] is Map<String, dynamic>
          ? SoundPlacement.fromJson(json["place"] as Map<String, dynamic>)
          : const SoundPlacement(),
    );
  }
}

/// GainPoint is one point of a volume envelope: seconds, and a gain nought
/// to one.
class GainPoint {
  final double time;
  final double gain;
  const GainPoint(this.time, this.gain);

  @override
  bool operator ==(Object other) =>
      other is GainPoint && other.time == time && other.gain == gain;

  @override
  int get hashCode => Object.hash(time, gain);

  @override
  String toString() => "GainPoint($time, $gain)";
}

/// envelopeAt is [points]' gain at [seconds]: straight lines between them,
/// flat past either end, and one where there are none.
double envelopeAt(List<GainPoint> points, double seconds) {
  if (points.isEmpty) return 1;
  if (seconds <= points.first.time) return points.first.gain;
  if (seconds >= points.last.time) return points.last.gain;
  for (var i = 0; i < points.length - 1; i++) {
    var a = points[i], b = points[i + 1];
    if (seconds > b.time) continue;
    var span = b.time - a.time;
    if (span <= 0) return b.gain;
    return a.gain + (b.gain - a.gain) * (seconds - a.time) / span;
  }
  return points.last.gain;
}

/// ClipMoment is where a clip on the timeline is at one instant.
class ClipMoment {
  /// index is which file of the playlist, and time how far into that file.
  final int index;
  final double time;

  /// gain is the fade, nought to one: the picture's opacity and a multiplier
  /// on the sound's volume.
  final double gain;

  const ClipMoment(this.index, this.time, this.gain);

  @override
  String toString() => "ClipMoment($index, $time, $gain)";
}
