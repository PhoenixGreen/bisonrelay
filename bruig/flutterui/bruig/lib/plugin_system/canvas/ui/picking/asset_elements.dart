import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/painting.dart';

// asset_elements.dart is an asset from the library made into the element that
// shows it: a picture into an Image element, a video into a Video element, a
// sound into an Audio element. One place, so an asset clicked in the sidebar
// and one dragged onto the canvas arrive the same.

/// elementForAsset is [asset] as a new element on [document], centred on
/// [center] (the middle of the page without one), and the shape the picture
/// or the video is.
CanvasElement elementForAsset(LibraryAsset asset, CanvasDocument document,
    {Offset? center}) {
  CanvasElement shaped(CanvasElement e) {
    if (asset.width <= 0 || asset.height <= 0) return e;
    // The size the element would have been, given the asset's proportions:
    // as wide as it was, or as tall where the asset is taller than wide.
    var box = e.bounds;
    var aspect = asset.width / asset.height;
    var side = math.max(box.width, box.height);
    var w = aspect >= 1 ? side : side * aspect;
    var h = aspect >= 1 ? side / aspect : side;
    var c = box.center;
    return e.withBase(x: c.dx - w / 2, y: c.dy - h / 2, width: w, height: h);
  }

  switch (asset.kind) {
    case AssetKind.picture:
      var e = newElement(ElementKind.image, document, center: center)
          as ImageElement;
      return shaped(e.copyWith(assetId: asset.id)).withBase(name: asset.name);
    case AssetKind.video:
      var e = newElement(ElementKind.video, document, center: center)
          as VideoElement;
      return shaped(e.copyWith(clip: MediaClip(playlist: [asset.source])))
          .withBase(name: asset.name);
    // Its own animations in its slots, ready to play: see modelClips.
    case AssetKind.model:
      var e = newElement(ElementKind.object3d, document, center: center)
          as Object3dElement;
      var placed = e.copyWith(assetId: asset.id, animations: asset.animations);
      return placed.withBase(
          name: asset.name, motion: modelClips(placed.id, asset.animations));
    case AssetKind.vector:
      var e = newElement(ElementKind.vector, document, center: center)
          as VectorElement;
      return shaped(e.copyWith(assetId: asset.id)).withBase(name: asset.name);
    case AssetKind.audio:
      var e = newElement(ElementKind.audio, document, center: center)
          as AudioElement;
      return e
          .copyWith(clip: e.clip.copyWith(playlist: [asset.source]))
          .withBase(name: asset.name);
  }
}

/// channelClip is a sound on the timeline: [source] from frame [at], on the
/// channel [channel] called [channelName], playing through [mix] -- the
/// channel's strip, which every sound on it carries. Not drawn: it is heard,
/// and seen on the timeline. Named after its file.
AudioElement channelClip(
  CanvasDocument document,
  int at, {
  required MediaSource source,
  required String channel,
  required String channelName,
  ChannelMix mix = const ChannelMix(),
}) {
  var e = newElement(ElementKind.audio, document) as AudioElement;
  return e
      .copyWith(
          clip: MediaClip(
              timed: true,
              at: at,
              // Full: its own line starts at the top, and is dragged down.
              volume: 1,
              playlist: [source],
              channel: channel,
              channelName: channelName,
              mix: mix))
      .withBase(
          name: source.name.isEmpty ? "Sound" : source.name,
          visible: false) as AudioElement;
}

/// PendingAsset is an asset that is not in the library yet -- a stock result
/// being dragged -- and is fetched only when it is let go somewhere that
/// takes it. Nothing is downloaded for a drag that is abandoned.
class PendingAsset {
  final AssetKind kind;
  final String name;
  final Future<LibraryAsset?> Function() fetch;
  const PendingAsset(
      {required this.kind, required this.name, required this.fetch});
}

/// droppedKind is what a drag carries, for a target deciding whether to take
/// it: an asset or a pending one, and null for anything else.
AssetKind? droppedKind(Object? data) => switch (data) {
      LibraryAsset a => a.kind,
      PendingAsset p => p.kind,
      _ => null,
    };

/// droppedAsset is the asset a drop delivers, fetched first where it has to
/// be; null when the fetch failed, which has said why already.
Future<LibraryAsset?> droppedAsset(Object? data) async => switch (data) {
      LibraryAsset a => a,
      PendingAsset p => await p.fetch(),
      _ => null,
    };

/// modelClips is a 3D object's own [animations] as its clips, "From the
/// model", one in each slot: each the animation's own length, round and
/// round, as a model's walk or idle is.
ElementMotion modelClips(String element, List<ModelAnimation> animations) =>
    modelClipsOnto(ElementMotion.none, element, animations);

/// modelClipsOnto is [motion] with [animations] in its first slots again:
/// each one's clip made anew, its placings on the timeline kept.
ElementMotion modelClipsOnto(
    ElementMotion motion, String element, List<ModelAnimation> animations) {
  var m = motion;
  for (var (i, (name, length)) in animations.indexed) {
    var clip = MotionClip.ofKind("$element-m$i", MotionKind.model, name: name)
        .copyWith(
            length: length > 0 ? length : 1,
            loop: true,
            inside: {"animation": name});
    m = m.withClip(clip).inSlot(i, clip.id);
  }
  return m;
}
