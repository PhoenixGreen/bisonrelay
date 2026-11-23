import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// audio_element.dart is a sound on a canvas: an icon a reader presses, with
// mute and volume where wanted, playing a MediaClip. Play state and volume
// are the reader's (CanvasController.audioState), not the document's.

/// AudioGlyph is the icon drawn without a picture: paths, not a font, so it
/// exports without one and has playing, paused and muted forms.
enum AudioGlyph {
  speaker("Speaker"),
  note("Music note"),
  headphones("Headphones"),
  mic("Microphone"),
  play("Play button");

  final String label;
  const AudioGlyph(this.label);

  static AudioGlyph fromName(String? name) =>
      values.firstWhere((g) => g.name == name, orElse: () => speaker);
}

/// AudioControl is one thing a reader can do to the sound from the element.
enum AudioControl {
  playPause("Play and pause", "Pressing the icon starts and stops it"),
  mute("Mute", "A switch beside the icon that silences it"),
  volume("Volume", "A bar beside the icon that sets how loud it is");

  final String label;
  final String description;
  const AudioControl(this.label, this.description);

  static AudioControl? fromName(String? name) {
    for (var c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// defaultLeftAccent is an instrument's left hand's colour as it starts:
/// a teal beside its amber right hand.
const defaultLeftAccent = Color(0xFF2BB3C0);

class AudioElement extends CanvasElement {
  final MediaClip clip;

  final AudioGlyph glyph;

  /// picture, pausedPicture and mutedPicture replace the drawn icon. Only
  /// [picture] is needed: the other two fall back to it.
  final String picture;
  final String pausedPicture;
  final String mutedPicture;

  /// iconColor is the drawn icon's colour, and accent the colour of what
  /// shows it is on: the waves while playing, the volume bar's fill.
  final Color iconColor;
  final Color accent;

  /// leftAccent is, on an instrument playing two staves (a piano's), the
  /// colour of the left hand's keys; the right hand's are [accent].
  final Color leftAccent;

  /// box is what the icon sits on: a disc, a rounded square, nothing.
  final BoxSpec box;

  /// controls is which of the three the reader gets, in the order drawn.
  final List<AudioControl> controls;

  final ElementAnimation animation;

  /// instrument is the part it plays, where it is an instrument: drawn as a
  /// keyboard, its clip's file the part. See instrument.dart.
  final InstrumentPart? instrument;

  bool get isInstrument => instrument != null;

  const AudioElement(
    super.base, {
    this.instrument,
    this.clip = const MediaClip(),
    this.glyph = AudioGlyph.speaker,
    this.picture = "",
    this.pausedPicture = "",
    this.mutedPicture = "",
    this.iconColor = const Color(0xFFFFFFFF),
    this.accent = const Color(0xFF3D7EFF),
    this.leftAccent = defaultLeftAccent,
    this.box =
        const BoxSpec(fill: Color(0xFF223046), borderRadius: 999, padding: 10),
    this.controls = const [AudioControl.playPause],
    this.animation = const ElementAnimation(),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = AudioElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.audio;

  bool has(AudioControl control) => controls.contains(control);

  /// assetIds is the pictures standing in for the icon, and the box's own;
  /// the sound is in [mediaIds].
  @override
  Set<String> get assetIds => {
        ...box.assetIds,
        for (var id in [picture, pausedPicture, mutedPicture])
          if (id.isNotEmpty) id,
      };

  @override
  Set<String> get mediaIds => clip.mediaIds;

  @override
  CanvasElement rebase(ElementBase base) => AudioElement(base,
      instrument: instrument,
      clip: clip,
      glyph: glyph,
      picture: picture,
      pausedPicture: pausedPicture,
      mutedPicture: mutedPicture,
      iconColor: iconColor,
      accent: accent,
      leftAccent: leftAccent,
      box: box,
      controls: controls,
      animation: animation);

  AudioElement copyWith({
    MediaClip? clip,
    AudioGlyph? glyph,
    String? picture,
    String? pausedPicture,
    String? mutedPicture,
    Color? iconColor,
    Color? accent,
    Color? leftAccent,
    BoxSpec? box,
    List<AudioControl>? controls,
    ElementAnimation? animation,
    InstrumentPart? instrument,
  }) =>
      AudioElement(base,
          instrument: instrument ?? this.instrument,
          clip: clip ?? this.clip,
          glyph: glyph ?? this.glyph,
          picture: picture ?? this.picture,
          pausedPicture: pausedPicture ?? this.pausedPicture,
          mutedPicture: mutedPicture ?? this.mutedPicture,
          iconColor: iconColor ?? this.iconColor,
          accent: accent ?? this.accent,
          leftAccent: leftAccent ?? this.leftAccent,
          box: box ?? this.box,
          controls: controls ?? this.controls,
          animation: animation ?? this.animation);

  @override
  AudioElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var iconColor = p(this.iconColor);
    var accent = p(this.accent);
    var leftAccent = p(this.leftAccent);
    var box = p.part(this.box, (b) => b.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      iconColor: iconColor,
      accent: accent,
      leftAccent: leftAccent,
      box: box,
      animation: animation,
    );
  }

  @override
  Map<String, dynamic> props() => {
        "clip": clip.toJson(),
        if (glyph != _defaults.glyph) "glyph": glyph.name,
        if (picture.isNotEmpty) "picture": picture,
        if (pausedPicture.isNotEmpty) "pausedPicture": pausedPicture,
        if (mutedPicture.isNotEmpty) "mutedPicture": mutedPicture,
        "iconColor": colorToJson(iconColor),
        "accent": colorToJson(accent),
        if (leftAccent != _defaults.leftAccent)
          "leftAccent": colorToJson(leftAccent),
        "box": box.toJson(),
        "controls": [for (var c in controls) c.name],
        if (animation.any) "anim": animation.toJson(),
        if (instrument case var part?) "instrument": part.toJson(),
      };

  factory AudioElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["controls"];
    return AudioElement(b,
        instrument: json["instrument"] is Map<String, dynamic>
            ? InstrumentPart.fromJson(json["instrument"] as Map<String, dynamic>)
            : null,
        clip: jsonSpec(json["clip"], MediaClip.fromJson, _defaults.clip),
        glyph: AudioGlyph.fromName(jsonStr(json["glyph"])),
        picture: jsonString(json["picture"], _defaults.picture),
        pausedPicture: jsonString(json["pausedPicture"], _defaults.pausedPicture),
        mutedPicture: jsonString(json["mutedPicture"], _defaults.mutedPicture),
        iconColor: colorFromJson(json["iconColor"], _defaults.iconColor),
        accent: colorFromJson(json["accent"], _defaults.accent),
        leftAccent: colorFromJson(json["leftAccent"], _defaults.leftAccent),
        box: jsonSpec(
            json["box"],
            BoxSpec.fromJson,
            _defaults.box),
        controls: raw is List
            ? [
                for (var name in raw)
                  if (AudioControl.fromName(jsonStr(name)) case var c?) c,
              ]
            : const [AudioControl.playPause],
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, _defaults.animation));
  }
}

/// isTimelineSound is whether [e] is a timed, undrawn sound on a timeline
/// channel: the canvas's layers, select-all and speaker settings skip it.
bool isTimelineSound(Object? e) =>
    e is AudioElement && e.clip.timed && !e.visible;
