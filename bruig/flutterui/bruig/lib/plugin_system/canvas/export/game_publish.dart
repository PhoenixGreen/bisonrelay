import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';

// game_publish.dart is a canvas published as a game: the canvas bundle --
// the document and its pictures and sounds -- carried in the page, with a
// cover to show before it is played. Read in Bison Relay, it is played by
// the same engine it was made in: see game_embed.dart. There is no web
// player; one would be a second engine to keep in step.

/// gameMime marks a published game: a canvas bundle that opens as a game,
/// not as a canvas to edit.
const String gameMime = "application/x-bruig-game";

/// GamePublishOptions are what a published game carries besides itself.
class GamePublishOptions {
  /// howTo says how to play -- its keys and a controller -- on its cover.
  final bool howTo;

  /// hud keeps the Counters showing its counts; off, they are left out.
  final bool hud;

  /// best keeps each reader's best of its first count, on their machine.
  final bool best;

  /// open lets a reader take a copy into their own Canvas, to see how it is
  /// made.
  final bool open;

  const GamePublishOptions(
      {this.howTo = true,
      this.hud = true,
      this.best = true,
      this.open = false});

  GamePublishOptions copyWith(
          {bool? howTo, bool? hud, bool? best, bool? open}) =>
      GamePublishOptions(
          howTo: howTo ?? this.howTo,
          hud: hud ?? this.hud,
          best: best ?? this.best,
          open: open ?? this.open);

  /// params are the options as the embed carries them.
  Map<String, String> get params => {
        "howto": howTo ? "1" : "0",
        "best": best ? "1" : "0",
        "open": open ? "1" : "0",
      };

  static GamePublishOptions fromParams(Map<String, String> p) =>
      GamePublishOptions(
          howTo: p["howto"] != "0",
          best: p["best"] != "0",
          open: p["open"] == "1");
}

/// gameDocument is [doc] as it is published as a game: without its HUD's
/// Counters where [options] leave it out, and opening on its first scene.
CanvasDocument gameDocument(CanvasDocument doc, GamePublishOptions options) {
  if (options.hud) return doc;
  bool kept(CanvasElement e) =>
      !(e is CounterElement && e.source == CounterSource.game);
  var next = doc;
  for (var (i, s) in doc.allScenes.indexed) {
    if (s.elements.every(kept)) continue;
    next = next.withScene(
        i,
        s.copyWith(elements: [
          for (var e in s.elements)
            if (kept(e)) e
        ]));
  }
  var master = next.master;
  if (master != null && !master.elements.every(kept)) {
    next = next.copyWith(
        master: master.copyWith(elements: [
      for (var e in master.elements)
        if (kept(e)) e
    ]));
  }
  return next;
}

/// coverWidth is how wide a game's cover is drawn: enough for a post, small
/// enough to carry in it.
const int coverWidth = 640;

/// gameCover is the first frame of the scene [doc] starts on, as a JPEG-
/// sized PNG [coverWidth] wide -- or null where it cannot be drawn.
Future<Uint8List?> gameCover(
    CanvasDocument doc, CanvasImageSource? images) async {
  var start = doc.gameStart.isEmpty ? -1 : doc.sceneIndexNamed(doc.gameStart);
  var scene = start >= 0 ? doc.goToScene(start) : doc;
  var page = scene.size.size;
  if (page.width <= 0 || page.height <= 0) return null;
  var scale = coverWidth / page.width;
  var w = coverWidth, h = math.max(1, (page.height * scale).round());
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  canvas.scale(scale);
  paintCanvasDocument(canvas, scene, frame: 0, images: images);
  var img = await rec.endRecording().toImage(w, h);
  try {
    var png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

/// exportGame is [doc] published as a game: its bundle, its cover and its
/// [options], ready to go anywhere a canvas can.
Future<CanvasExport> exportGame(CanvasDocument doc, GamePublishOptions options,
    {CanvasImageSource? images}) async {
  var game = gameDocument(doc, options);
  var cover = await gameCover(game, images);
  return CanvasExport(
    await packCanvas(game),
    gameMime,
    width: doc.size.exportWidth,
    height: doc.size.exportHeight,
    cover: cover,
    params: {
      ...options.params,
      if (doc.title.isNotEmpty) "name": Uri.encodeComponent(doc.title),
    },
  );
}
