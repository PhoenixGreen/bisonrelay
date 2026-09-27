import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// audio_element.dart is a sound on a canvas, and the thing a reader presses
// to hear it.
//
// On the canvas it is an icon, with a mute switch and a volume bar beside it
// when those are wanted. What plays is a MediaClip -- the same settings a
// video and a media background will carry. A button can play it too, and a
// sound that is only ever started by a button can be hidden: hidden is not
// drawn, and still plays.
//
// Where the sound has got to is not in the document. Playing, paused, muted
// and the volume somebody dragged to are the reader's, the way a running
// counter's value is -- see CanvasController.audioState. So a published
// canvas opens with the clip's own volume and silent until pressed (or
// autoplayed), whatever the author was doing with it at the time.

/// AudioGlyph is the icon drawn for the element when no picture is chosen.
///
/// Drawn as paths rather than taken from an icon font: the same shapes have
/// to appear in an exported picture, where no font is guaranteed, and each
/// shape has a playing, paused and muted form that a font glyph does not.
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

class AudioElement extends CanvasElement {
  final MediaClip clip;

  final AudioGlyph glyph;

  /// picture, pausedPicture and mutedPicture replace the drawn icon with the
  /// reader's own. Only [picture] is needed: the other two fall back to it,
  /// so one picture is an icon, and three are an icon that changes.
  final String picture;
  final String pausedPicture;
  final String mutedPicture;

  /// iconColor is the drawn icon's colour, and accent the colour of what
  /// shows it is on: the waves while playing, the filled part of the volume
  /// bar.
  final Color iconColor;
  final Color accent;

  /// box is what the icon sits on -- a disc, a rounded square, nothing.
  final BoxSpec box;

  /// controls is which of the three the reader gets, in the order drawn.
  final List<AudioControl> controls;

  final ElementAnimation animation;

  const AudioElement(
    super.base, {
    this.clip = const MediaClip(),
    this.glyph = AudioGlyph.speaker,
    this.picture = "",
    this.pausedPicture = "",
    this.mutedPicture = "",
    this.iconColor = const Color(0xFFFFFFFF),
    this.accent = const Color(0xFF3D7EFF),
    this.box =
        const BoxSpec(fill: Color(0xFF223046), borderRadius: 999, padding: 10),
    this.controls = const [AudioControl.playPause],
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.audio;

  bool has(AudioControl control) => controls.contains(control);

  /// assetIds is the pictures standing in for the icon, and the box's own.
  /// The sound is not a picture: it is in [mediaIds].
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
      clip: clip,
      glyph: glyph,
      picture: picture,
      pausedPicture: pausedPicture,
      mutedPicture: mutedPicture,
      iconColor: iconColor,
      accent: accent,
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
    BoxSpec? box,
    List<AudioControl>? controls,
    ElementAnimation? animation,
  }) =>
      AudioElement(base,
          clip: clip ?? this.clip,
          glyph: glyph ?? this.glyph,
          picture: picture ?? this.picture,
          pausedPicture: pausedPicture ?? this.pausedPicture,
          mutedPicture: mutedPicture ?? this.mutedPicture,
          iconColor: iconColor ?? this.iconColor,
          accent: accent ?? this.accent,
          box: box ?? this.box,
          controls: controls ?? this.controls,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "clip": clip.toJson(),
        if (glyph != AudioGlyph.speaker) "glyph": glyph.name,
        if (picture.isNotEmpty) "picture": picture,
        if (pausedPicture.isNotEmpty) "pausedPicture": pausedPicture,
        if (mutedPicture.isNotEmpty) "mutedPicture": mutedPicture,
        "iconColor": colorToJson(iconColor),
        "accent": colorToJson(accent),
        "box": box.toJson(),
        "controls": [for (var c in controls) c.name],
        if (animation.on || animation.closes) "anim": animation.toJson(),
      };

  factory AudioElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["controls"];
    return AudioElement(b,
        clip: jsonSpec(json["clip"], MediaClip.fromJson, const MediaClip()),
        glyph: AudioGlyph.fromName(json["glyph"] as String?),
        picture: jsonString(json["picture"], ""),
        pausedPicture: jsonString(json["pausedPicture"], ""),
        mutedPicture: jsonString(json["mutedPicture"], ""),
        iconColor: colorFromJson(json["iconColor"], const Color(0xFFFFFFFF)),
        accent: colorFromJson(json["accent"], const Color(0xFF3D7EFF)),
        box: jsonSpec(
            json["box"],
            BoxSpec.fromJson,
            const BoxSpec(
                fill: Color(0xFF223046), borderRadius: 999, padding: 10)),
        controls: raw is List
            ? [
                for (var name in raw)
                  if (AudioControl.fromName(name as String?) case var c?) c,
              ]
            : const [AudioControl.playPause],
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }
}
