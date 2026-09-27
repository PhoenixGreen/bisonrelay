import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';

// video_element.dart is a moving picture on a canvas.
//
// Two kinds of source, and they are deliberately not equals:
//
// - **A file** is footage the canvas owns. It is decoded frame by frame and
//   drawn by the same renderer as everything else, so it can be keyed, graded,
//   cut to a shape and -- later -- put on the timeline and exported. Its sound
//   plays through the audio engine, in step with the picture.
// - **A link** (YouTube, Vimeo, anything else) is somebody else's video that
//   the canvas points at. It shows a poster and opens the video when pressed.
//   Those services' terms forbid downloading or altering what they host, and
//   a published canvas with someone's video baked into it would carry that
//   video to everyone it was sent to -- so a link is never decoded, keyed or
//   exported as footage.
//
// What the picture looks like -- the shape it is cut to, its crop and framing,
// the filter, overlay, outline, and the box round it -- is an image element's
// look, held whole in [look]. The same controls set it and the same painter
// draws it, so a video and a photograph beside it are graded by one set of
// rules rather than two that drift.

/// VideoControl is one thing a reader can do to the video from the canvas.
enum VideoControl {
  clickToggle("Click to play", "Pressing the picture starts and stops it"),
  playButton("Play button", "A large play button while it is stopped"),
  playbar("Play bar", "Play and pause, and a bar to move through it"),
  time("Time", "How far in it is, beside the play bar"),
  mute("Mute", "A switch that silences it"),
  volume("Volume", "A bar that sets how loud it is");

  final String label;
  final String description;
  const VideoControl(this.label, this.description);

  static VideoControl? fromName(String? name) {
    for (var c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// ChromaKey takes one colour out of the picture -- a green screen.
///
/// Worked on the GPU, frame by frame, before the look is applied -- see
/// video_key.dart. Not the image element's background removal, which decides
/// colour by colour on the processor and would take most of a second on
/// every frame of a video.
class ChromaKey {
  final bool on;

  /// color is the screen's colour. Green and blue are what screens are.
  final Color color;

  /// tolerance is how far from [color] a pixel may be and still go, and
  /// softness how wide the edge between gone and kept is -- hair is neither
  /// one nor the other, and a hard edge cuts it off in steps.
  final double tolerance;
  final double softness;

  /// spill is how much of the screen's colour is taken back out of what is
  /// kept. Light bounces off a green screen onto whoever stands in front of
  /// it, and without this they come out with a green outline.
  final double spill;

  const ChromaKey({
    this.on = false,
    this.color = const Color(0xFF00B140),
    this.tolerance = 0.3,
    this.softness = 0.1,
    this.spill = 0.5,
  });

  ChromaKey copyWith({
    bool? on,
    Color? color,
    double? tolerance,
    double? softness,
    double? spill,
  }) =>
      ChromaKey(
        on: on ?? this.on,
        color: color ?? this.color,
        tolerance: tolerance ?? this.tolerance,
        softness: softness ?? this.softness,
        spill: spill ?? this.spill,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        "color": colorToJson(color),
        "tolerance": tolerance,
        "softness": softness,
        "spill": spill,
      };

  factory ChromaKey.fromJson(Map<String, dynamic> json) => ChromaKey(
        on: jsonBool(json["on"], false),
        color: colorFromJson(json["color"], const Color(0xFF00B140)),
        tolerance: jsonDouble(json["tolerance"], 0.3).clamp(0.0, 1.0),
        softness: jsonDouble(json["softness"], 0.1).clamp(0.0, 1.0),
        spill: jsonDouble(json["spill"], 0.5).clamp(0.0, 1.0),
      );
}

/// VideoHost is who a link points at, for what the poster says and how a
/// start time is written into the address.
enum VideoHost {
  youtube("YouTube"),
  vimeo("Vimeo"),
  other("Video");

  final String label;
  const VideoHost(this.label);

  static VideoHost of(String url) {
    var u = url.toLowerCase();
    if (u.contains("youtube.com/") || u.contains("youtu.be/")) return youtube;
    if (u.contains("vimeo.com/")) return vimeo;
    return other;
  }
}

/// linkAt is [url] with a start time written into it, the way each host
/// reads one. Only the start: neither host takes an end in the address of a
/// page to watch, and a canvas cannot stop somebody else's player.
String linkAt(String url, double start) {
  if (start <= 0) return url;
  var seconds = start.floor();
  var uri = Uri.tryParse(url);
  if (uri == null) return url;
  switch (VideoHost.of(url)) {
    case VideoHost.youtube:
      return uri.replace(queryParameters: {
        ...uri.queryParameters,
        "t": "${seconds}s",
      }).toString();
    case VideoHost.vimeo:
      return uri.replace(fragment: "t=${seconds}s").toString();
    case VideoHost.other:
      return url;
  }
}

class VideoElement extends CanvasElement {
  /// clip is the files, their ranges, the fades, the loop and the sound's
  /// volume -- the same settings an Audio element has. See MediaClip.
  final MediaClip clip;

  /// link is a video somewhere else, instead of files. See the top of this
  /// file for why the two are not the same thing.
  final String link;

  /// linkStart is where the linked video opens, in seconds.
  final double linkStart;

  final ChromaKey key;

  /// look is how the picture is drawn: an image element's settings, whose
  /// own picture is the poster of a link video and unused for a file. Its
  /// base is ignored -- see [picture], which puts this element's on it.
  final ImageElement look;

  final List<VideoControl> controls;

  /// accent colours the controls: the played part of the bar, the switches
  /// that are on.
  final Color accent;

  final ElementAnimation animation;

  const VideoElement(
    super.base, {
    this.clip = const MediaClip(volume: 1),
    this.link = "",
    this.linkStart = 0,
    this.key = const ChromaKey(),
    this.look = const ImageElement(ElementBase(id: "")),
    this.controls = const [
      VideoControl.clickToggle,
      VideoControl.playButton,
      VideoControl.playbar,
    ],
    this.accent = const Color(0xFF3D7EFF),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.video;

  bool get isLink => link.trim().isNotEmpty;
  bool has(VideoControl control) => controls.contains(control);

  /// picture is [look] standing where this element stands, which is what the
  /// image painter and the image settings both need: a crop or a padding
  /// that moves the box is worked out from the box.
  ImageElement get picture => look.rebase(base) as ImageElement;

  /// withPicture takes the look back from an edited [picture], and the box
  /// with it where the edit moved one.
  VideoElement withPicture(ImageElement edited) {
    var next = copyWith(
        look: edited.rebase(const ElementBase(id: "")) as ImageElement);
    return next.rebase(edited.base.copyWith(id: id)) as VideoElement;
  }

  @override
  Set<String> get assetIds => {
        ...look.assetIds,
        if (!isLink) ...clip.posterIds,
      };

  @override
  Set<String> get mediaIds => isLink ? const {} : clip.mediaIds;

  @override
  CanvasElement rebase(ElementBase base) => VideoElement(base,
      clip: clip,
      link: link,
      linkStart: linkStart,
      key: key,
      look: look,
      controls: controls,
      accent: accent,
      animation: animation);

  VideoElement copyWith({
    MediaClip? clip,
    String? link,
    double? linkStart,
    ChromaKey? key,
    ImageElement? look,
    List<VideoControl>? controls,
    Color? accent,
    ElementAnimation? animation,
  }) =>
      VideoElement(base,
          clip: clip ?? this.clip,
          link: link ?? this.link,
          linkStart: linkStart ?? this.linkStart,
          key: key ?? this.key,
          look: look ?? this.look,
          controls: controls ?? this.controls,
          accent: accent ?? this.accent,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "clip": clip.toJson(),
        if (isLink) "link": link,
        if (linkStart > 0) "linkStart": linkStart,
        if (key.on) "key": key.toJson(),
        "look": look.props(),
        "controls": [for (var c in controls) c.name],
        "accent": colorToJson(accent),
        if (animation.on || animation.closes) "anim": animation.toJson(),
      };

  factory VideoElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var raw = json["controls"];
    var look = json["look"];
    return VideoElement(b,
        clip: jsonSpec(
            json["clip"], MediaClip.fromJson, const MediaClip(volume: 1)),
        link: jsonString(json["link"], ""),
        linkStart: jsonDouble(json["linkStart"], 0),
        key: jsonSpec(json["key"], ChromaKey.fromJson, const ChromaKey()),
        look: look is Map<String, dynamic>
            ? ImageElement.fromJson(
                // "aspect" present, so the decoder does not apply the old
                // pictures-lock-their-proportions rule to a look.
                {...look, "aspect": true},
                const ElementBase(id: ""))
            : const ImageElement(ElementBase(id: "")),
        controls: raw is List
            ? [
                for (var name in raw)
                  if (VideoControl.fromName(name as String?) case var c?) c,
              ]
            : const [
                VideoControl.clickToggle,
                VideoControl.playButton,
                VideoControl.playbar,
              ],
        accent: colorFromJson(json["accent"], const Color(0xFF3D7EFF)),
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }
}
