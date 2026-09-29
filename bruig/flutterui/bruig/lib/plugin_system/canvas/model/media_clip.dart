import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonInt, jsonSpec, jsonString;
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// media_clip.dart is what is played: which files, which part of each, how it
// starts and stops, and whether it goes round again.
//
// One object for every kind of media on a canvas -- the Audio element now,
// and the Video element and media backgrounds after it -- so that the play
// range, the fades, the loop and the playlist are one set of settings drawn
// by one set of controls. Three copies of "start at, end at, fade in, fade
// out" would be three places for them to disagree about what a fade is.
//
// Times are seconds into the file, as doubles. A frame number would tie the
// play range to the document's frame rate, and a sound does not change length
// because somebody changed how many frames a second the canvas runs at.

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
  /// assetId is the file in the media store -- see CanvasMedia. Named by a
  /// hash of its bytes, so the same recording used twice is stored once.
  final String assetId;

  /// name is what the file was called when it was added, which is what the
  /// list shows. The id says nothing to a person.
  final String name;

  /// start and end are the play range, in seconds into the file. An end of
  /// nought means "to the end", which is what a file nobody has trimmed plays.
  final double start;
  final double end;

  /// length is how long the whole file is, in seconds, when that is known.
  ///
  /// Written down when the file is added so that the range fields can say
  /// what "the end" is without opening the file. Nought when it is not known,
  /// and nothing depends on it being right: the player asks the file.
  final double length;

  /// posterId, soundId, width, height and fps are what a *video* file was
  /// found to be when it was added -- see media_picking.dart.
  ///
  /// The poster is a still from the file, stored as an ordinary picture, so
  /// an exported image or a bundle opened without ffmpeg still shows
  /// something that looks like the video. The sound is the file's own audio
  /// taken out into the audio store, which is what the audio engine plays in
  /// step with the picture. Empty for a sound, and for a video with no sound.
  final String posterId;
  final String soundId;
  final int width;
  final int height;
  final double fps;

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
      };

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    var start = math.max(0.0, jsonDouble(json["start"], 0));
    var end = math.max(0.0, jsonDouble(json["end"], 0));
    return MediaSource(
      assetId: jsonString(json["asset"], ""),
      name: jsonString(json["name"], ""),
      start: start,
      // An end before the start is a range with nothing in it, which reads as
      // a file that will not play. Taken as "to the end" instead.
      end: end > start ? end : 0,
      length: math.max(0.0, jsonDouble(json["length"], 0)),
      posterId: jsonString(json["poster"], ""),
      soundId: jsonString(json["sound"], ""),
      width: jsonInt(json["w"], 0),
      height: jsonInt(json["h"], 0),
      fps: math.max(0.0, jsonDouble(json["fps"], 0)),
    );
  }
}

/// MediaClip is everything about how a piece of media plays.
class MediaClip {
  /// playlist is the files, played in order. One file is a playlist of one.
  final List<MediaSource> playlist;

  /// volume is where it starts, nought to one. The reader can move it with
  /// the element's own control; this is what it opens at.
  final double volume;

  /// muted is whether it opens silent.
  final bool muted;

  /// fadeIn and fadeOut are seconds, at the start and end of each file's
  /// range. Each file rather than the list as a whole, because a playlist of
  /// songs that each start at full volume is a playlist that clicks between
  /// every one of them.
  final double fadeIn;
  final double fadeOut;

  final MediaLoop loop;

  /// autoplay starts it when its page opens, and on the master when the
  /// document does.
  final bool autoplay;

  /// acrossPages is for media on the master: it goes on playing from one
  /// page or scene to the next rather than stopping at the join.
  ///
  /// Only the master can mean it, since only the master is on every page.
  /// Anywhere else a sound stops when its page is left, which is what the
  /// page leaving means.
  final bool acrossPages;

  /// timed puts the media on the timeline: it plays with the playhead from
  /// frame [at] -- scrubbed, paused and exported with everything else --
  /// rather than on its own clock when somebody presses it.
  ///
  /// A frame of the scene it is on, or of the whole run for media on the
  /// master, which plays under every scene.
  final bool timed;
  final int at;

  /// mix is this clip's channel strip on the mixer -- its level, balance,
  /// EQ and compressor. See mix.dart.
  final ChannelMix mix;

  /// channel is the timeline channel a sound is on, and channelName what the
  /// channel is called. Several sounds share a channel by sharing its id, and
  /// a channel is only ever the sounds on it -- when the last one goes, so
  /// does the channel. Empty for media given a lane of its own, which is
  /// everything made before channels could hold more than one.
  ///
  /// The channel's strip -- [mix] -- is kept the same on every sound in it,
  /// so each plays and exports through the channel's level as it always did.
  final String channel;
  final String channelName;

  const MediaClip({
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
        ],
      };

  /// posterIds is the stills a video's files carry, which are pictures and
  /// live in the picture store. See MediaSource.posterId.
  Set<String> get posterIds => {
        for (var s in playlist)
          if (s.posterId.isNotEmpty) s.posterId,
      };

  /// runLength is how long the playlist takes to play through once, in
  /// seconds -- each file's range, one after another. A file whose length is
  /// not known counts as nothing, because nothing can be placed after it.
  double get runLength => playlist.fold(0.0, (sum, s) => sum + s.span);

  /// momentAt is what is playing [seconds] after the clip starts on the
  /// timeline: which file, where in it, and how far faded in -- or null where
  /// nothing is, before it starts or after it has finished.
  ///
  /// The one answer to "where is this clip at this frame", for the editor
  /// following the playhead, the channels drawn under it and the exporter;
  /// three answers to that would be a video that is somewhere else once it
  /// has been exported. On the timeline a repeat goes round the whole list,
  /// whichever repeat was chosen: "each" on its own clock is a file played
  /// until somebody stops it, and a timeline has no somebody.
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
  }) =>
      MediaClip(
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
      volume: jsonDouble(json["volume"], 0.8).clamp(0.0, 1.0),
      muted: jsonBool(json["muted"], false),
      fadeIn: math.max(0.0, jsonDouble(json["fadeIn"], 0)),
      fadeOut: math.max(0.0, jsonDouble(json["fadeOut"], 0)),
      loop: MediaLoop.fromName(json["loop"] as String?),
      autoplay: jsonBool(json["autoplay"], false),
      acrossPages: !jsonBool(json["stopsAtJoin"], false),
      timed: jsonBool(json["timed"], false),
      at: math.max(0, jsonInt(json["at"], 0)),
      mix: jsonSpec(json["mix"], ChannelMix.fromJson, const ChannelMix()),
      channel: json["channel"] is String ? json["channel"] as String : "",
      channelName:
          json["channelName"] is String ? json["channelName"] as String : "",
    );
  }
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
