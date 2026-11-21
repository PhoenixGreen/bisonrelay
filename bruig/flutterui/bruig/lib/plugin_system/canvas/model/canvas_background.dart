import 'dart:ui' show Rect;

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

/// CanvasBackground is what is behind the whole document: a pattern, a
/// stage or parallax scenery (see [backdrop]), with any picture, drawing and
/// video over it. Each is kept while another is shown, so trying one loses
/// nothing.
class CanvasBackground {
  final ProceduralSpec spec;

  /// picture, video and sound are elements, so their controls and painters
  /// serve here too. Each is stretched to the page when drawn, whatever box
  /// it was saved with; the sound is never drawn.
  final ImageElement? picture;
  final VideoElement? video;
  final AudioElement? sound;

  /// drawing is a vector drawing between the picture and the video.
  final VectorElement? drawing;

  /// backdrop is whether the pattern, [stage] or [parallax] is drawn.
  final BackdropKind backdrop;

  /// stage is the 3D stage, where [backdrop] says so; its camera's keys are
  /// on their own track. Its id is [backgroundStageId], which a character
  /// standing on it names.
  final StageElement? stage;

  /// parallax is the scenery, where [backdrop] says so; its camera's keys are
  /// on their own track under [backgroundParallaxId].
  final ParallaxElement? parallax;

  const CanvasBackground({
    this.spec = const ProceduralSpec(),
    this.picture,
    this.video,
    this.sound,
    this.drawing,
    this.backdrop = BackdropKind.flat,
    this.stage,
    this.parallax,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CanvasBackground();

  bool get isStage => backdrop == BackdropKind.stage;
  bool get isParallax => backdrop == BackdropKind.parallax;

  /// parallaxOn is the scenery stretched to a page of [rect].
  ParallaxElement parallaxOn(Rect rect) {
    var p = parallax ??
        const ParallaxElement(ElementBase(id: backgroundParallaxId));
    return p.withBase(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height) as ParallaxElement;
  }

  /// stageOn is the stage stretched to a page of [rect], as the picture and
  /// video are.
  StageElement stageOn(Rect rect) {
    var s = stage ?? defaultBackgroundStage;
    return s.withBase(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height) as StageElement;
  }

  ImageElement? get shownPicture {
    if (picture case var p? when p.hasImage) return p;
    return null;
  }

  bool get isImage => shownPicture != null;

  List<CanvasElement> get media => [
        if (video case var v? when !v.clip.isEmpty) v,
        if (sound case var a? when !a.clip.isEmpty) a,
      ];

  Set<String> get assetIds => {
        ...?shownPicture?.assetIds,
        ...?video?.assetIds,
        ...?drawing?.assetIds,
        ...?parallax?.assetIds,
      };

  Set<String> get mediaIds => {
        ...?video?.mediaIds,
        ...?sound?.mediaIds,
        ...?drawing?.mediaIds,
      };

  CanvasBackground copyWith({
    ProceduralSpec? spec,
    ImageElement? picture,
    VideoElement? video,
    AudioElement? sound,
    VectorElement? drawing,
    bool clearPicture = false,
    bool clearVideo = false,
    bool clearSound = false,
    bool clearDrawing = false,
    BackdropKind? backdrop,
    StageElement? stage,
    ParallaxElement? parallax,
  }) =>
      CanvasBackground(
        backdrop: backdrop ?? this.backdrop,
        stage: stage ?? this.stage,
        parallax: parallax ?? this.parallax,
        spec: spec ?? this.spec,
        picture: clearPicture ? null : picture ?? this.picture,
        video: clearVideo ? null : video ?? this.video,
        sound: clearSound ? null : sound ?? this.sound,
        drawing: clearDrawing ? null : drawing ?? this.drawing,
      );

  Map<String, dynamic> toJson() => {
        "spec": spec.toJson(),
        if (picture != null) "picture": picture!.toJson(),
        if (video != null) "video": video!.toJson(),
        if (sound != null) "sound": sound!.toJson(),
        if (drawing != null) "drawing": drawing!.toJson(),
        if (backdrop != _defaults.backdrop) "backdrop": backdrop.name,
        if (stage != null) "stage": stage!.toJson(),
        if (parallax != null) "parallax": parallax!.toJson(),
      };

  factory CanvasBackground.fromJson(Map<String, dynamic> json) {
    // An element of the wrong kind under a key is left out.
    T? element<T>(Object? raw) {
      Object? read = raw is Map<String, dynamic> ? elementFromJson(raw) : null;
      return read is T ? read : null;
    }

    return CanvasBackground(
      spec: jsonSpec(json["spec"], ProceduralSpec.fromJson, _defaults.spec),
      picture: element<ImageElement>(json["picture"]),
      video: element<VideoElement>(json["video"]),
      sound: element<AudioElement>(json["sound"]),
      drawing: element<VectorElement>(json["drawing"]),
      backdrop: BackdropKind.fromName(jsonStr(json["backdrop"])),
      // Read as a stage directly: elementFromJson reads no stage of its own,
      // only one inside a Background element.
      stage: jsonSpec(
          json["stage"],
          (j) => StageElement.fromJson(
              j, ElementBase.fromJson(j, ElementKind.stage.label)),
          null),
      parallax: jsonSpec(
          json["parallax"],
          (j) => ParallaxElement.fromJson(
              j, ElementBase.fromJson(j, ElementKind.parallax.label)),
          null),
    );
  }
}

/// defaultBackgroundStage is the stage a background first becomes.
const StageElement defaultBackgroundStage =
    StageElement(ElementBase(id: backgroundStageId, name: "3D stage"));
