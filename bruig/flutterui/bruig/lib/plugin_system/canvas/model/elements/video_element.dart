import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';

export 'package:bruig/plugin_system/canvas/model/layer_blend.dart'
    show LayerBlend;

// video_element.dart is a moving picture on a canvas, from one of two
// sources. A file is footage the canvas owns: decoded frame by frame, drawn
// by the shared renderer, so it can be keyed, graded and exported, its
// sound in step through the audio engine. A link (YouTube, Vimeo...) shows
// a poster and opens the video when pressed: never decoded, keyed or
// exported, as those services' terms forbid downloading or altering it.

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

/// ChromaKey takes one colour out of the picture -- a green screen. Worked
/// on the GPU per frame, before the look (video_key.dart): the image
/// element's CPU background removal is far too slow for every frame.
class ChromaKey {
  final bool on;

  final Color color;

  /// tolerance is how far from [color] a pixel may be and still be removed,
  /// and softness how wide the edge between removed and kept is.
  final double tolerance;
  final double softness;

  /// spill takes the screen's colour back out of what is kept, against the
  /// green fringe bounced off the screen.
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

/// linkAt is [url] with a start time written in the host's way. Only the
/// start: neither host takes an end in a watch address.
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
  /// clip is the files, their ranges, fades, loop and volume (MediaClip).
  final MediaClip clip;

  /// link is a video somewhere else, instead of files.
  final String link;

  /// linkStart is in seconds.
  final double linkStart;

  final ChromaKey key;

  /// look is how the picture is drawn, as an image element's settings; its
  /// picture is a link's poster, unused for a file. Its base is ignored: see
  /// [picture].
  final ImageElement look;

  final List<VideoControl> controls;

  /// accent colours the controls: the bar's played part, switches that are
  /// on.
  final Color accent;

  final ElementAnimation animation;

  /// blend is how the video is laid on what is under it; the light modes
  /// suit overlays shot on black (light leaks, flares).
  final LayerBlend blend;

  /// edges softens the box's edges and fades it out.
  final EdgeMask edges;

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
    this.blend = LayerBlend.normal,
    this.edges = const EdgeMask(),
  });

  @override
  ElementKind get kind => ElementKind.video;

  bool get isLink => link.trim().isNotEmpty;
  bool has(VideoControl control) => controls.contains(control);

  /// picture is [look] on this element's base, for the image painter and
  /// settings, which work crops and padding out from the box.
  ImageElement get picture => look.rebase(base) as ImageElement;

  /// withPicture takes the look back from an edited [picture], and its box
  /// where the edit moved it.
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
      animation: animation,
      blend: blend,
      edges: edges);

  VideoElement copyWith({
    MediaClip? clip,
    String? link,
    double? linkStart,
    ChromaKey? key,
    ImageElement? look,
    List<VideoControl>? controls,
    Color? accent,
    ElementAnimation? animation,
    LayerBlend? blend,
    EdgeMask? edges,
  }) =>
      VideoElement(base,
          clip: clip ?? this.clip,
          link: link ?? this.link,
          linkStart: linkStart ?? this.linkStart,
          key: key ?? this.key,
          look: look ?? this.look,
          controls: controls ?? this.controls,
          accent: accent ?? this.accent,
          animation: animation ?? this.animation,
          blend: blend ?? this.blend,
          edges: edges ?? this.edges);

  @override
  Map<String, dynamic> props() => {
        "clip": clip.toJson(),
        if (isLink) "link": link,
        if (linkStart > 0) "linkStart": linkStart,
        if (key.on) "key": key.toJson(),
        "look": look.props(),
        "controls": [for (var c in controls) c.name],
        "accent": colorToJson(accent),
        if (animation.any) "anim": animation.toJson(),
        if (blend != LayerBlend.normal) "blend": blend.name,
        if (edges.on) "edges": edges.toJson(),
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
            ? ImageElement.fromJson(look, const ElementBase(id: ""))
            : const ImageElement(ElementBase(id: "")),
        controls: raw is List
            ? [
                for (var name in raw)
                  if (VideoControl.fromName(jsonStr(name)) case var c?) c,
              ]
            : const [
                VideoControl.clickToggle,
                VideoControl.playButton,
                VideoControl.playbar,
              ],
        accent: colorFromJson(json["accent"], const Color(0xFF3D7EFF)),
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()),
        blend: LayerBlend.fromName(jsonStr(json["blend"])),
        edges: jsonSpec(json["edges"], EdgeMask.fromJson, const EdgeMask()));
  }
}
