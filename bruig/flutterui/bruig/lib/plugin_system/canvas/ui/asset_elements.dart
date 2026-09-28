import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
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
    case AssetKind.audio:
      var e = newElement(ElementKind.audio, document, center: center)
          as AudioElement;
      return e
          .copyWith(clip: e.clip.copyWith(playlist: [asset.source]))
          .withBase(name: asset.name);
  }
}

/// audioChannel is a new channel on the timeline: a sound that plays only
/// there, from [at], and is not drawn -- with [asset] in it, or empty, waiting
/// for one. Named after its asset, or numbered after the sounds already on
/// [document].
AudioElement audioChannel(CanvasDocument document, int at,
    {LibraryAsset? asset}) {
  var count = document.elements.whereType<AudioElement>().length;
  var e = newElement(ElementKind.audio, document) as AudioElement;
  return e
          .copyWith(
              clip: MediaClip(
                  timed: true,
                  at: at,
                  playlist: asset == null ? const [] : [asset.source]))
          .withBase(name: asset?.name ?? "Audio ${count + 1}", visible: false)
      as AudioElement;
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
