import 'package:bruig/plugin_system/canvas/model/surround.dart';
export 'package:bruig/plugin_system/canvas/model/surround.dart' show SpeakerLayout;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonDouble, jsonInt;

// audio_settings.dart is a document's sound as a production: its tempo and
// time signature, and how its sound is written when it is published -- the
// format, rate, depth or bitrate, and the loudness it is brought to, which
// together are what "made for YouTube" or "mastered for CD" mean. Kept on the
// document so that every publish of it starts from them.

/// AudioFormat is what a sound file is written as.
enum AudioFormat {
  wav("WAV", "audio/wav", ".wav",
      "Uncompressed: exactly the mix, and the largest file."),
  flac("FLAC", "audio/flac", ".flac",
      "Lossless and about half the size of a WAV."),
  mp3("MP3", "audio/mpeg", ".mp3", "Plays anywhere; small at a good bitrate."),
  aac("AAC (.m4a)", "audio/mp4", ".m4a",
      "Better than an MP3 at the same size, and what Apple's apps use."),
  opus("Opus", "audio/ogg", ".opus",
      "The best sound for its size, for the web and chat apps.");

  final String label;
  final String mime;
  final String extension;
  final String note;
  const AudioFormat(this.label, this.mime, this.extension, this.note);

  bool get lossless => this == wav || this == flac;

  /// carriesSurround is whether a file of this kind can hold more than two
  /// speakers. An MP3 cannot, and is written as the fold-down to stereo.
  bool get carriesSurround => this != mp3;

  /// fixedRate is the one rate the format plays at, or null for any.
  int? get fixedRate => this == opus ? 48000 : null;
}

/// audioBitrates are the bitrates offered for a compressed sound, in kbps.
const audioBitrates = [96, 128, 160, 192, 256, 320];

/// audioRates and audioDepths are the sample rates and bit depths offered.
const audioRates = [44100, 48000, 96000];
const audioDepths = [16, 24];

/// AudioOptions is how a sound is written: the format (for a sound file; a
/// video's is its container's), the bitrate of a compressed one, and the
/// rate and depth.
class AudioOptions {
  final AudioFormat format;
  final int kbps;
  final int sampleRate;
  final int bitDepth;

  const AudioOptions({
    this.format = AudioFormat.wav,
    this.kbps = 192,
    this.sampleRate = 48000,
    this.bitDepth = 24,
  });

  AudioOptions copyWith(
          {AudioFormat? format, int? kbps, int? sampleRate, int? bitDepth}) =>
      AudioOptions(
        format: format ?? this.format,
        kbps: kbps ?? this.kbps,
        sampleRate: sampleRate ?? this.sampleRate,
        bitDepth: bitDepth ?? this.bitDepth,
      );

  Map<String, dynamic> toJson() => {
        "format": format.name,
        "kbps": kbps,
        "rate": sampleRate,
        "depth": bitDepth,
      };

  factory AudioOptions.fromJson(Object? json) {
    const d = AudioOptions();
    if (json is! Map) return d;
    return AudioOptions(
      format: AudioFormat.values
              .where((f) => f.name == json["format"])
              .firstOrNull ??
          d.format,
      kbps: audioBitrates.contains(json["kbps"]) ? json["kbps"] as int : d.kbps,
      sampleRate: audioRates.contains(json["rate"])
          ? json["rate"] as int
          : d.sampleRate,
      bitDepth: audioDepths.contains(json["depth"])
          ? json["depth"] as int
          : d.bitDepth,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioOptions &&
      other.format == format &&
      other.kbps == kbps &&
      other.sampleRate == sampleRate &&
      other.bitDepth == bitDepth;

  @override
  int get hashCode => Object.hash(format, kbps, sampleRate, bitDepth);

  /// summary is these settings in a few words.
  String summary({AudioFormat? as}) {
    var f = as ?? format;
    var rate =
        "${((f.fixedRate ?? sampleRate) / 1000).toStringAsFixed(1)} kHz";
    return f.lossless ? "$bitDepth-bit · $rate" : "$kbps kbps · $rate";
  }
}

/// AudioPreset is a destination's own settings: what the place a piece of
/// sound is going asks for, from its published delivery specifications.
/// Choosing one sets the format and the loudness at once; changing either
/// afterwards makes the settings the document's own.
enum AudioPreset {
  // YouTube normalises playback to about −14 LUFS and recommends AAC-LC,
  // stereo, 48kHz, at a high bitrate.
  youtube("YouTube", AudioOptions(format: AudioFormat.aac, kbps: 320),
      -14, -1, "AAC at 48kHz, brought to −14 LUFS, as YouTube plays it"),
  // Streaming services (Spotify, Apple Music, Tidal) normalise to −14 to −16
  // LUFS and want a lossless master at the CD rate or above.
  streaming(
      "Streaming",
      AudioOptions(format: AudioFormat.flac, sampleRate: 44100),
      -14,
      -1,
      "A 24-bit FLAC master at −14 LUFS, for Spotify, Apple Music and the "
          "rest"),
  // Red Book CD: 16-bit, 44.1kHz PCM. No loudness standard; the true peak
  // kept under full scale for the converters.
  cd(
      "CD",
      AudioOptions(format: AudioFormat.wav, sampleRate: 44100, bitDepth: 16),
      -12,
      -0.3,
      "16-bit, 44.1kHz WAV: the Red Book CD format"),
  // Film and television: 48kHz 24-bit, dialogue-level loudness around −24
  // LKFS (ATSC A/85) to −27 (Netflix), true peak −2.
  film(
      "Film & TV",
      AudioOptions(format: AudioFormat.wav),
      -24,
      -2,
      "24-bit, 48kHz WAV at −24 LKFS, as broadcasters and streamers ask"),
  // Podcasts: −16 LUFS stereo (Apple's guidance), MP3 for everywhere.
  podcast(
      "Podcast",
      AudioOptions(format: AudioFormat.mp3, kbps: 192, sampleRate: 44100),
      -16,
      -1,
      "MP3 at −16 LUFS, the level Apple Podcasts and Spotify ask for"),
  // European broadcast: EBU R128, −23 LUFS, true peak −1.
  broadcast(
      "Broadcast (EBU R128)",
      AudioOptions(format: AudioFormat.wav),
      -23,
      -1,
      "24-bit, 48kHz WAV at −23 LUFS, the European broadcast standard");

  final String label;
  final AudioOptions options;
  final double target;
  final double ceilingDb;
  final String note;
  const AudioPreset(
      this.label, this.options, this.target, this.ceilingDb, this.note);
}

/// Quantise is the grid a sound snaps to on the timeline: a bar, a note
/// value, a triplet -- or nothing.
enum Quantise {
  off("Off", 0),
  bar("1 bar", -1),
  half("1/2", 1 / 2),
  quarter("1/4", 1 / 4),
  eighth("1/8", 1 / 8),
  sixteenth("1/16", 1 / 16),
  eighthTriplet("1/8 T", 1 / 12),
  sixteenthTriplet("1/16 T", 1 / 24);

  final String label;

  /// whole is the grid as a share of a whole note; a bar is its own.
  final double whole;
  const Quantise(this.label, this.whole);

  static Quantise fromName(String? name) =>
      values.firstWhere((q) => q.name == name, orElse: () => quarter);
}

/// sectionNames are the names a section is usually given, offered when one
/// is added.
const sectionNames = [
  "Intro",
  "Verse",
  "Pre-chorus",
  "Chorus",
  "Bridge",
  "Middle 8",
  "Break",
  "Drop",
  "Solo",
  "Outro",
];

/// sectionColors are the colours sections are told apart by on the
/// timeline, in turn.
const sectionColors = [
  0xFF5AA9FF,
  0xFFF08A3C,
  0xFF9B7BEA,
  0xFF2BB3A3,
  0xFFE85D9A,
  0xFFF2B33D,
  0xFF7EE0A8,
  0xFFC9CDD3,
];

/// SongSection is one part of a piece's structure: what it is called and
/// how many bars it lasts. Sections follow one another, each starting where
/// the last ended; a sound is never cut where one gives way to the next.
class SongSection {
  final String id;
  final String name;
  final int bars;

  /// color is its index in sectionColors.
  final int color;

  const SongSection(this.id,
      {this.name = "Section", this.bars = 8, this.color = 0});

  SongSection copyWith({String? name, int? bars, int? color}) => SongSection(id,
      name: name ?? this.name,
      bars: (bars ?? this.bars).clamp(1, 512),
      color: color ?? this.color);

  Map<String, dynamic> toJson() =>
      {"id": id, "name": name, "bars": bars, "color": color};

  static SongSection? fromJson(Object? json) {
    if (json is! Map || json["id"] is! String) return null;
    return SongSection(json["id"] as String,
        name: json["name"] is String ? json["name"] as String : "Section",
        bars: jsonInt(json["bars"], 8).clamp(1, 512),
        color: jsonInt(json["color"], 0) % sectionColors.length);
  }
}

/// AudioSettings is a document's sound as a production.
class AudioSettings {
  /// tempo is in beats a minute, and beatsPerBar over beatUnit the time
  /// signature: what the timeline counts in bars and beats by.
  final double tempo;
  final int beatsPerBar;
  final int beatUnit;

  /// export is how its sound is written when it is published.
  final AudioOptions export;

  /// sections are its structure, in order. None is the master structure:
  /// the whole piece as one.
  final List<SongSection> sections;

  /// quantise is the grid sounds snap to on the timeline.
  final Quantise quantise;

  /// speakers is what it is mixed for: stereo, or surround -- which the
  /// editor plays folded down to stereo, and an export writes whole.
  final SpeakerLayout speakers;

  const AudioSettings({
    this.speakers = SpeakerLayout.stereo,
    this.tempo = 120,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.export = const AudioOptions(),
    this.sections = const [],
    this.quantise = Quantise.quarter,
  });

  /// totalBars is how long the structure is.
  int get totalBars => sections.fold(0, (a, s) => a + s.bars);

  /// startBar is where section [index] starts, counting bars from nought.
  int startBar(int index) =>
      sections.take(index).fold(0, (a, s) => a + s.bars);

  /// gridSeconds is the quantise grid as a length of time, or null for off.
  double? gridSeconds([Quantise? q]) {
    var g = q ?? quantise;
    if (g == Quantise.off) return null;
    if (g == Quantise.bar) return secondsPerBar;
    // The tempo counts the beat the time signature names; a whole note is
    // that many beats over its unit.
    return g.whole * beatUnit * secondsPerBeat;
  }

  /// secondsPerBeat and secondsPerBar are the tempo as lengths of time.
  double get secondsPerBeat => 60 / tempo * 4 / beatUnit;
  double get secondsPerBar => secondsPerBeat * beatsPerBar;

  String get signature => "$beatsPerBar/$beatUnit";

  AudioSettings copyWith(
          {double? tempo,
          int? beatsPerBar,
          int? beatUnit,
          AudioOptions? export,
          List<SongSection>? sections,
          Quantise? quantise,
          SpeakerLayout? speakers}) =>
      AudioSettings(
        speakers: speakers ?? this.speakers,
        tempo: (tempo ?? this.tempo).clamp(20.0, 400.0),
        beatsPerBar: (beatsPerBar ?? this.beatsPerBar).clamp(1, 16),
        beatUnit: beatUnit ?? this.beatUnit,
        export: export ?? this.export,
        sections: sections ?? this.sections,
        quantise: quantise ?? this.quantise,
      );

  bool get isDefault =>
      tempo == 120 &&
      beatsPerBar == 4 &&
      beatUnit == 4 &&
      export == const AudioOptions() &&
      sections.isEmpty &&
      speakers == SpeakerLayout.stereo &&
      quantise == Quantise.quarter;

  Map<String, dynamic> toJson() => {
        if (tempo != 120) "tempo": tempo,
        if (beatsPerBar != 4) "beats": beatsPerBar,
        if (beatUnit != 4) "unit": beatUnit,
        if (export != const AudioOptions()) "export": export.toJson(),
        if (sections.isNotEmpty)
          "sections": [for (var s in sections) s.toJson()],
        if (quantise != Quantise.quarter) "quantise": quantise.name,
        if (speakers != SpeakerLayout.stereo) "speakers": speakers.name,
      };

  factory AudioSettings.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const AudioSettings();
    var unit = jsonInt(json["unit"], 4);
    return const AudioSettings().copyWith(
      tempo: jsonDouble(json["tempo"], 120),
      beatsPerBar: jsonInt(json["beats"], 4),
      beatUnit: const [2, 4, 8, 16].contains(unit) ? unit : 4,
      export: AudioOptions.fromJson(json["export"]),
      sections: [
        if (json["sections"] case List list)
          for (var raw in list)
            if (SongSection.fromJson(raw) case var section?) section,
      ],
      quantise: Quantise.fromName(json["quantise"] as String?),
      speakers: SpeakerLayout.fromName(json["speakers"] as String?),
    );
  }
}

/// timeSignatures are the ones offered.
const timeSignatures = [(4, 4), (3, 4), (2, 4), (6, 8), (5, 4), (7, 8), (12, 8)];
