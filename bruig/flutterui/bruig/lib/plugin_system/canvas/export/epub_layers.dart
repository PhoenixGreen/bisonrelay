import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_channels.dart'
    show synthSpeakersHearing;
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:path/path.dart' as path;

import 'package:bruig/plugin_system/canvas/export/epub_media.dart'
    show plainVideo;
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart'
    show looksReach;
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/render/score_engraver.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show ClipPlacement, ClipTriggerKind, ElementMotion, MotionClip;
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show partWav, soundBankPath;
import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// epub_layers.dart is a page of an interactive EPUB as the things on it, each
// animated by the reader the way it is animated on the canvas.
//
// The page is never a film of itself. What does not move is drawn once (the
// background held still), and each element that moves is its own layer:
//
// - Its picture, drawn once by the renderer.
// - Moved, turned, grown and faded by CSS keyframes sampled a frame at a
//   time. The pose is the element's clips and keyframes together; how
//   it arrives and leaves is read off the renderer as it draws each frame
//   (see motionProbe). A word-by-word arrival is a picture a word.
// - What CSS cannot do -- a chart growing, a counter counting, a picture
//   shattering, a keyed video -- is a short video of that element alone for
//   the frames it changes, with its own picture either side.

/// EpubSprite is one picture: where it goes on the page, in pixels, and where
/// it is on its sheet.
class EpubSprite {
  /// href is the sheet it is on.
  final String href;
  final double x;
  final double y;
  final double width;
  final double height;

  /// sx and sy are its top left corner on the sheet.
  final double sx;
  final double sy;

  const EpubSprite(this.href, this.x, this.y, this.width, this.height,
      {this.sx = 0, this.sy = 0});

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}

/// EpubKey is what CSS says about something at one frame: property to value.
class EpubKey {
  final int frame;
  final Map<String, String> css;
  const EpubKey(this.frame, this.css);
}

/// EpubPart is one picture of a layer and how it moves: [keys] on the
/// picture itself -- transform, opacity, blur -- and [clipKeys] on a still
/// frame round it, for a motion that uncovers rather than moves.
class EpubPart {
  final EpubSprite sprite;
  final List<EpubKey> keys;
  final List<EpubKey> clipKeys;
  const EpubPart(this.sprite, {this.keys = const [], this.clipKeys = const []});
}

/// EpubClip is an element's change as a video of the element alone: [href],
/// playing from frame [at] for [frames] frames, over [rect]. [before] and
/// [after] are the element either side of it.
class EpubClip {
  final String href;
  final int at;
  final int frames;
  final Rect rect;
  final EpubSprite? before;
  final EpubSprite? after;
  const EpubClip(this.href, this.at, this.frames, this.rect,
      {this.before, this.after});
}

/// EpubReaction is a clip an element plays when something happens on the
/// page -- [on] is `click:<element>` for a click on that element, or
/// `end:<clip>` for another clip ending -- as keyframes over its own
/// [frames], and the sound linked with it in its row. The page's script plays
/// it over the element's place on the timeline and lets it go at its end:
/// the canvas's clips started by a click or by another clip, kept in a book
/// (Ken, 2026-11-13: "is there a way to fix this export limitation that
/// also complies with the epub3 format?").
class EpubReaction {
  /// clip is its id, which a reaction that follows it names in [on].
  final String clip;
  final String on;
  final int frames;
  final List<EpubKey> keys;

  /// sound is its linked sound's file in the book, and volume how loud.
  final String? sound;
  final double volume;

  const EpubReaction(this.clip, this.on, this.frames, this.keys,
      {this.sound, this.volume = 1});
}

/// EpubLayer is one element that moves, can be shown and hidden, or changes
/// under the pointer.
/// EpubControl is a button on a layer that the page's clock answers: a
/// Sheet music element's playbar (Ken, 2026-11-14). [act] is what it asks
/// of the clock, [rect] where it is in page pixels, [data] what else it
/// says (the frames to step between, the span to seek along), [inner] what
/// is drawn in it (a pause for the play button, shown while it plays).
class EpubControl {
  final String act;
  final Rect rect;
  final Map<String, String> data;
  final String inner;
  final String label;
  const EpubControl(this.act, this.rect,
      {this.data = const {}, this.inner = "", this.label = ""});
}

/// EpubKeyboard is an instrument a reader plays (Ken, 2026-11-14: "click a
/// note on the instrument and have it play both as a mouse/keyboard input
/// and a midi instrument input"): where it is in page pixels, its keys
/// (each key's number, its box within, whether it is black, and a picture
/// of it lit), and its sound -- every key from [low], [step] seconds apart,
/// in one file.
class EpubKeyboard {
  final Rect box;
  final List<({int key, Rect rect, bool black, EpubSprite lit})> keys;
  final String sound;
  final int low;
  final double step;
  const EpubKeyboard(this.box, this.keys, this.sound, this.low, this.step);
}

class EpubLayer {
  /// id is the element's, which a Show-or-hide button names.
  final String id;

  /// visible is whether it is showing when the page opens.
  final bool visible;

  /// originX and originY are the element's anchor, in the page's pixels:
  /// what its pose turns and grows it about.
  final double originX;
  final double originY;

  /// pose is where the element is -- moved, turned, grown and faded -- as
  /// keyframes; empty where it stays where it was put.
  final List<EpubKey> pose;

  /// parts are its pictures and how each moves; clip its change as a video,
  /// for one CSS cannot draw.
  final List<EpubPart> parts;
  final EpubClip? clip;

  /// hover is the button as it is under the pointer, and hoverBox where it
  /// can be pointed at, in page pixels. Null for anything that does not
  /// change when pointed at.
  final EpubSprite? hover;
  final Rect? hoverBox;

  /// legend is where a chart's key has a series to switch on and off, in
  /// page pixels, each with the bit it flips; switched is the chart as it
  /// is with each set of those bits flipped, by mask. Empty for anything
  /// else. See _LayerMaker._legend.
  final List<(int, Rect)> legend;
  final Map<int, EpubSprite> switched;

  /// reactions are the clips it plays on a click or after another clip.
  final List<EpubReaction> reactions;

  /// controls are the buttons on it that the page's clock answers.
  final List<EpubControl> controls;

  /// keyboard is it as an instrument the reader plays, where it is one.
  final EpubKeyboard? keyboard;

  const EpubLayer({
    required this.id,
    this.visible = true,
    required this.originX,
    required this.originY,
    this.pose = const [],
    this.parts = const [],
    this.clip,
    this.hover,
    this.hoverBox,
    this.legend = const [],
    this.switched = const {},
    this.reactions = const [],
    this.controls = const [],
    this.keyboard,
  });

  /// moves is whether anything on it changes with the playhead.
  bool get moves =>
      pose.length > 1 ||
      clip != null ||
      parts.any((p) => p.keys.length > 1 || p.clipKeys.length > 1);
}

/// EpubSlab is a stretch of the page that does not move, flattened: the
/// backdrop and the elements over it up to the first that moves, or the
/// still elements between two that do.
class EpubSlab {
  final EpubSprite sprite;
  const EpubSlab(this.sprite);
}

/// EpubStage is a page laid out as layers.
class EpubStage {
  /// items are the slabs and the layers, bottom to top.
  final List<Object> items;

  final int frames;
  final int rate;

  /// marks are the timeline's stops, pauses, loops and jumps.
  final List<TimelineAction> marks;

  /// autoplay is whether the page starts by itself: unless it has playhead
  /// buttons of its own.
  final bool autoplay;

  /// timeline is whether sound or video follows its playhead.
  final bool timeline;

  /// backdropVideo is the page's background video, played by the reader on a
  /// loop over the backdrop and under everything else. Null where there is
  /// none, or none a reader can show.
  final String? backdropVideo;

  /// clickable are the elements a click on starts a reaction, and where
  /// each is on the page, in its pixels.
  final List<(String, Rect)> clickable;

  /// sounds are the reactions' sound files, each once.
  final List<String> sounds;

  /// camera is how the page's Camera frames it, frame by frame where it
  /// moves: a transform on everything on the stage. Empty for none. See
  /// cameraKeys.
  final List<EpubKey> camera;

  /// lens is what the Camera's lens does to each layer by its element's
  /// depth -- blurs it away from the focus, moves it by parallax -- as
  /// keys on a wrapper round the layer, by the layer's id. See lensKeys.
  final Map<String, List<EpubKey>> lens;

  /// vignette is the Camera's darkened corners, as keys of the overlay's
  /// opacity, with how far in it reaches; empty for none.
  final List<EpubKey> vignette;
  final double vignetteSoft;

  /// ownPlay is whether the page is played by a playbar of its own (a
  /// score sheet's): no start screen over it, and nothing until pressed.
  final bool ownPlay;

  const EpubStage({
    required this.items,
    required this.frames,
    required this.rate,
    this.marks = const [],
    this.autoplay = true,
    this.timeline = false,
    this.backdropVideo,
    this.clickable = const [],
    this.sounds = const [],
    this.camera = const [],
    this.lens = const {},
    this.vignette = const [],
    this.vignetteSoft = 0.5,
    this.ownPlay = false,
  });

  Iterable<EpubLayer> get layers => items.whereType<EpubLayer>();

  /// animates is whether anything on it changes with the playhead, rather
  /// than being laid out only to be shown, hidden and pointed at.
  bool get animates =>
      timeline ||
      camera.length > 1 ||
      vignette.length > 1 ||
      lens.values.any((k) => k.length > 1) ||
      layers.any((l) => l.moves);
}

/// StageResult is a page laid out, and the files it needs.
class StageResult {
  final EpubStage stage;
  final List<EpubFile> files;
  const StageResult(this.stage, this.files);
}

/// ElementFilms is what makes an element's change into a video of its own:
/// ffmpeg, and whether it can keep what is clear clear. Asked once a book.
class ElementFilms {
  final String ffmpeg;

  /// alpha is whether HEVC with a clear background can be made here --
  /// VideoToolbox's, on a Mac. Without it, the element is filmed over what
  /// is under it on the page, which is exact only where that holds still.
  final bool alpha;

  const ElementFilms(this.ffmpeg, {this.alpha = false});

  /// find is the system ffmpeg's, or null without one.
  static Future<ElementFilms?> find(String? ffmpeg) async {
    if (ffmpeg == null) return null;
    Directory? work;
    try {
      // Tried rather than asked about: an encoder can be listed and still
      // decline to open.
      work = await Directory.systemTemp.createTemp("canvas-alpha");
      var out = path.join(work.path, "a.mp4");
      var run = await Process.run(ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-f", "lavfi", "-i", "color=c=red@0.5:s=64x64:r=12,format=bgra",
        "-t", "0.2",
        "-c:v", "hevc_videotoolbox", "-q:v", "60", "-alpha_quality", "0.9",
        "-tag:v", "hvc1", out,
      ]);
      var ok = run.exitCode == 0 &&
          await File(out).exists() &&
          await File(out).length() > 0;
      return ElementFilms(ffmpeg, alpha: ok);
    } catch (_) {
      return ElementFilms(ffmpeg);
    } finally {
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// buildEpubStage lays page [index] of [document] out as layers, at [pixels]
/// page pixels to the design unit on a page of [width] by [height] pixels.
///
/// Returns null where the page has nothing that moves, nothing to show or
/// hide and nothing that changes under the pointer: its picture is enough.
Future<StageResult?> buildEpubStage(
  CanvasDocument document,
  int index, {
  required double pixels,
  required int width,
  required int height,
  CanvasImageSource? images,
  bool autoplay = true,

  /// films makes the videos of elements CSS cannot animate. Without it they
  /// hold still, as their own picture.
  ElementFilms? films,

  /// media is the page's timeline media, for a keyed video on it -- which is
  /// filmed as itself, keyed, frame by frame.
  ExportMedia? media,

  /// layered are elements to give a layer whether or not they move: a video
  /// the reader plays, which needs its own place in the stack.
  Set<String> layered = const {},

  /// timeline is whether the page has sound or video on its timeline.
  bool timeline = false,

  /// backdropVideo is the page's background video as a file a reader plays,
  /// where it has one. See EpubStage.backdropVideo.
  String? backdropVideo,
}) async {
  var page = document.goToScene(index).copyWith(
        onMaster: false,
        background: document.backgroundOf(index),
      );
  var scene = document.allScenes[index];
  var frames = math.max(1, page.frames);
  // This page's: one that leaves the master off has none.
  var master = page.masterScene;
  // In the renderer's order: the master's page numbers over the page.
  var elements = stackedWithMaster(master?.elements ?? const [], scene.elements,
      over: document.masterOver);
  var pageBox = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  // Shown and hidden by a button on the page: a layer even when it is still,
  // so there is something to show and hide.
  var toggled = {
    for (var e in elements)
      if (e is ButtonElement &&
          e.visible &&
          e.action.kind == ButtonActionKind.toggleElement)
        e.action.elementId,
  };

  // Buttons that change under the pointer: a layer each, with the look it
  // changes to.
  var hovering = {
    for (var e in elements)
      if (e is ButtonElement && e.visible && _hovers(e)) e.id,
  };

  // Lines that are only there to carry text and have asked to stay out of the
  // picture, as the renderer leaves them.
  var hidden = {
    for (var e in elements)
      if (e is TextElement && e.curve?.hideHost == true) e.curve!.elementId,
  };

  // A camera frames the page (see cameraKeys) and is never in it.
  var drawn = [
    for (var e in elements)
      if ((e.visible || toggled.contains(e.id)) &&
          !hidden.contains(e.id) &&
          e is! CameraElement)
        e,
  ];

  // What plays a clip on a click, or after another clip: a layer each, and
  // where those clicks land.
  var reacting = {
    for (var e in drawn)
      if (_reactionClips(e).isNotEmpty) e.id,
  };
  var clicked = {
    for (var e in drawn)
      for (var c in _reactionClips(e))
        for (var t in c.triggers)
          if (t.kind == ClipTriggerKind.clicked) t.target,
  };

  // Which elements move: their pose changes, or their look does. A
  // background element holds still in a book.
  bool keyedVideo(CanvasElement e) =>
      e is VideoElement && media != null && isTimedMedia(e) && !plainVideo(e);
  // What the Camera's lens does to each element by its depth: those it
  // blurs or moves are layers of their own, to be done to alone.
  var lens = lensKeys(page, drawn, frames, pixels);
  var moving = <String>{};
  var changing = <String>{};
  for (var e in drawn) {
    if (e is BackgroundElement) continue;
    var changes = _changes(e, frames, page) || keyedVideo(e);
    if (changes) changing.add(e.id);
    if (changes ||
        toggled.contains(e.id) ||
        hovering.contains(e.id) ||
        _switchable(e).isNotEmpty ||
        layered.contains(e.id) ||
        lens.containsKey(e.id) ||
        reacting.contains(e.id)) {
      moving.add(e.id);
    }
  }
  if (!(timeline && frames > 1) &&
      backdropVideo == null &&
      lens.isEmpty &&
      changing.isEmpty &&
      toggled.isEmpty &&
      hovering.isEmpty &&
      reacting.isEmpty &&
      !drawn.any((e) => _switchable(e).isNotEmpty)) {
    return null;
  }

  // The reactions' sounds, each a file in the book once.
  var sounds = await _reactionSounds(page, drawn);

  var sheets = _Sheets("layers/p$index");
  var clips = <EpubFile>[];

  ui.Canvas start(ui.PictureRecorder recorder) =>
      ui.Canvas(recorder)..scale(pixels);

  var items = <Object>[];
  var still = <CanvasElement>[];
  var below = <CanvasElement>[];
  var first = true;

  // The still elements since the last one that moved, as one picture. The
  // first also carries the backdrop and the facing leaf's overhang; with a
  // background video, the backdrop is a slab of its own so the video can go
  // between it and the rest.
  Future<void> flatten() async {
    var base = first;
    first = false;
    if (base && backdropVideo != null) {
      var recorder = ui.PictureRecorder();
      paintCanvasDocument(start(recorder), page,
          part: CanvasPaintPart.backdrop, images: images);
      var picture = recorder.endRecording();
      try {
        var sprite = await sheets.alone(picture, pageBox);
        if (sprite != null) items.add(EpubSlab(sprite));
      } finally {
        picture.dispose();
      }
      items.add(const _BackdropVideo());
    }
    var withBackdrop = base && backdropVideo == null;
    var facing = base && document.facingAt(index) != null;
    if (still.isEmpty && !withBackdrop && !facing) return;
    void paintStill(ui.Canvas canvas) {
      if (withBackdrop) {
        paintCanvasDocument(canvas, page,
            part: CanvasPaintPart.backdrop, images: images);
      }
      if (facing) _paintFacing(canvas, document, index, images);
      for (var e in still) {
        paintElement(canvas, e, 0,
            frameRate: page.frameRate, images: images, document: page);
      }
    }

    // Its pictures read, not their placeholders: a vector not yet loaded
    // was drawn as its dashed box (Ken, 2026-11-13: about 13 missing,
    // the Decred logo among them).
    await drawWhenLoaded(images, (c) {
      c.scale(pixels);
      paintStill(c);
    });
    var recorder = ui.PictureRecorder();
    paintStill(start(recorder));
    still.clear();
    var picture = recorder.endRecording();
    try {
      // The backdrop is a whole page: a sheet of its own, or it would push
      // everything else onto more sheets.
      var sprite = withBackdrop
          ? await sheets.alone(picture, pageBox)
          : await sheets.add(picture, pageBox);
      if (sprite != null) items.add(EpubSlab(sprite));
    } finally {
      picture.dispose();
    }
  }

  for (var e in drawn) {
    if (!moving.contains(e.id)) {
      still.add(e);
      below.add(e);
      continue;
    }
    await flatten();
    var region = _regionFor(e, pixels, pageBox, document,
        moves: e.track != null || movesAtAll(e));
    var maker = _LayerMaker(
        e, page, frames, pixels, images, sheets, start, region, pageBox,
        films: changing.contains(e.id) ? films : null,
        media: keyedVideo(e) ? media : null,
        below: [...below],
        index: index,
        sounds: {
          for (var MapEntry(:key, :value) in sounds.entries) key: value.href
        },
        player: e is VideoElement && layered.contains(e.id) && !keyedVideo(e));
    items.add(await maker.make(hovers: hovering.contains(e.id)));
    clips.addAll(maker.clips);
    below.add(e);
  }
  if (still.isNotEmpty || first) await flatten();
  // Synth cables over every module, as the page draws them: a picture of
  // their own on top, which a press goes through.
  if (drawn.any((e) => e is SynthModuleElement)) {
    var recorder = ui.PictureRecorder();
    paintSynthCables(start(recorder), drawn);
    var picture = recorder.endRecording();
    try {
      var sprite = await sheets.alone(picture, pageBox);
      if (sprite != null) items.add(EpubSlab(sprite));
    } finally {
      picture.dispose();
    }
  }
  await sheets.close();

  var built = [
    for (var item in items)
      switch (item) {
        EpubSlab slab => EpubSlab(sheets.placed(slab.sprite)),
        EpubLayer l => EpubLayer(
            id: l.id,
            visible: l.visible,
            originX: l.originX,
            originY: l.originY,
            pose: l.pose,
            parts: [
              for (var p in l.parts)
                EpubPart(sheets.placed(p.sprite),
                    keys: p.keys, clipKeys: p.clipKeys),
            ],
            clip: l.clip == null
                ? null
                : EpubClip(
                    l.clip!.href, l.clip!.at, l.clip!.frames, l.clip!.rect,
                    before: l.clip!.before == null
                        ? null
                        : sheets.placed(l.clip!.before!),
                    after: l.clip!.after == null
                        ? null
                        : sheets.placed(l.clip!.after!)),
            hover: l.hover == null ? null : sheets.placed(l.hover!),
            hoverBox: l.hoverBox,
            legend: l.legend,
            switched: {
              for (var MapEntry(:key, :value) in l.switched.entries)
                key: sheets.placed(value),
            },
            reactions: l.reactions,
            controls: l.controls,
            keyboard: l.keyboard == null
                ? null
                : EpubKeyboard(
                    l.keyboard!.box,
                    [
                      for (var k in l.keyboard!.keys)
                        (
                          key: k.key,
                          rect: k.rect,
                          black: k.black,
                          lit: sheets.placed(k.lit)
                        ),
                    ],
                    l.keyboard!.sound,
                    l.keyboard!.low,
                    l.keyboard!.step),
          ),
        _ => item,
      },
  ];

  // A score sheet's playbar plays the page (Ken, 2026-11-14: "rather than
  // the ugly play button").
  var ownPlay =
      drawn.any((e) => e is SheetElement && e.playbar && e.score.isNotEmpty);
  var stage = EpubStage(
    items: built,
    frames: frames,
    rate: page.frameRate,
    marks: page.actions,
    autoplay: autoplay && !ownPlay,
    ownPlay: ownPlay,
    timeline: timeline && frames > 1,
    backdropVideo: backdropVideo,
    clickable: [
      for (var e in drawn)
        if (clicked.contains(e.id))
          (
            e.id,
            Rect.fromLTRB(e.bounds.left * pixels, e.bounds.top * pixels,
                e.bounds.right * pixels, e.bounds.bottom * pixels)
          ),
    ],
    sounds: [for (var f in sounds.values) f.href],
    camera: cameraKeys(page, frames, pixels, width, height),
    lens: lens,
    vignette: vignetteKeys(page, frames),
    vignetteSoft: switch (cameraOf(page)) {
      CameraElement c when !isStageScene(page) => c.vignetteSoft,
      _ => 0.5,
    },
  );
  return StageResult(stage, [...sheets.files, ...clips, ...sounds.values]);
}

/// cameraKeys is how [page]'s Camera frames it on each of its [frames], as
/// a transform on the whole stage, [width] by [height] pixels at [pixels]
/// a design unit: the frame it shows scaled up to fill the page. A key on
/// each frame it moves on and at each end of each hold, played straight
/// between them, so its easing is the canvas's. Empty where it has none,
/// or one on a 3D stage, which frames the stage rather than the page.
List<EpubKey> cameraKeys(
    CanvasDocument page, int frames, double pixels, int width, int height) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page)) return const [];
  String at(int f) {
    var (zoom, c) = cameraFraming(cam, f, page);
    var roll = cameraLookAt(cam, f, page).roll;
    if (roll == 0) {
      var tx = width / 2 - c.dx * pixels * zoom;
      var ty = height / 2 - c.dy * pixels * zoom;
      return "translate(${tx.toStringAsFixed(2)}px,${ty.toStringAsFixed(2)}px) "
          "scale(${zoom.toStringAsFixed(5)})";
    }
    // Rolled: about the middle of the page, the picture turned back.
    return "translate(${(width / 2).toStringAsFixed(2)}px,"
        "${(height / 2).toStringAsFixed(2)}px) "
        "rotate(${(-roll).toStringAsFixed(3)}deg) "
        "scale(${zoom.toStringAsFixed(5)}) "
        "translate(${(-c.dx * pixels).toStringAsFixed(2)}px,"
        "${(-c.dy * pixels).toStringAsFixed(2)}px)";
  }

  var all = [for (var f = 0; f < frames; f++) at(f)];
  var keys = <EpubKey>[];
  for (var f = 0; f < frames; f++) {
    var changes = f == 0 ||
        f == frames - 1 ||
        all[f] != all[f - 1] ||
        all[f] != all[f + 1];
    if (changes) keys.add(EpubKey(f, {"transform": all[f]}));
  }
  // Never moving: a still framing is one key.
  if (all.toSet().length == 1) return [keys.first];
  return keys;
}

/// lensKeys are what [page]'s Camera's lens does to each of [elements] by
/// its depth, on each of [frames] where that changes: its parallax as a
/// transform from the camera's framing to its own (see parallaxed), its
/// depth of field as a blur. Only those it does anything to.
Map<String, List<EpubKey>> lensKeys(CanvasDocument page,
    List<CanvasElement> elements, int frames, double pixels) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page) || !cam.hasLens) return const {};
  var rect = page.size.rect;
  var looks = [for (var f = 0; f < frames; f++) cameraLookAt(cam, f, page)];
  var framings = [for (var f = 0; f < frames; f++) cameraFraming(cam, f, page)];
  var out = <String, List<EpubKey>>{};
  for (var e in elements) {
    if (e is CameraElement) continue;
    var depth = e.base.depth;
    if (depth == 0 && looks.every((l) => l.blurAt(0) <= 0.25)) continue;
    var sways = looks.any((l) => l.sways(depth));
    var blurs = looks.any((l) => l.blurAt(depth) > 0.25);
    if (!sways && !blurs) continue;
    Map<String, String> at(int f) {
      var look = looks[f];
      var (zoom, focus) = framings[f];
      var css = <String, String>{};
      if (sways) {
        var (z, c) = parallaxed(zoom, focus, rect, depth, look.parallax);
        var k = z / zoom;
        var tx = (focus.dx - k * c.dx) * pixels;
        var ty = (focus.dy - k * c.dy) * pixels;
        css["transform"] =
            "translate(${tx.toStringAsFixed(2)}px,${ty.toStringAsFixed(2)}px) "
            "scale(${k.toStringAsFixed(5)})";
      }
      if (blurs) {
        var sigma = look.blurAt(depth) * pixels;
        css["filter"] = "blur(${sigma.toStringAsFixed(2)}px)";
      }
      return css;
    }

    var all = [for (var f = 0; f < frames; f++) at(f)];
    bool same(int a, int b) =>
        all[a].length == all[b].length &&
        all[a].entries.every((x) => all[b][x.key] == x.value);
    var keys = <EpubKey>[
      for (var f = 0; f < frames; f++)
        if (f == 0 || f == frames - 1 || !same(f, f - 1) || !same(f, f + 1))
          EpubKey(f, all[f]),
    ];
    out[e.id] = keys.length > 1 && keys.every((k) => same(k.frame, 0))
        ? [keys.first]
        : keys;
  }
  return out;
}

/// vignetteKeys is [page]'s Camera's vignette, as the overlay's opacity on
/// each frame it changes; empty for none.
List<EpubKey> vignetteKeys(CanvasDocument page, int frames) {
  var cam = cameraOf(page);
  if (cam == null || isStageScene(page)) return const [];
  var all = [
    for (var f = 0; f < frames; f++)
      cameraLookAt(cam, f, page).vignette.toStringAsFixed(3)
  ];
  if (all.every((v) => double.parse(v) <= 0)) return const [];
  if (all.toSet().length == 1) {
    return [
      EpubKey(0, {"opacity": all.first})
    ];
  }
  return [
    for (var f = 0; f < frames; f++)
      if (f == 0 ||
          f == frames - 1 ||
          all[f] != all[f - 1] ||
          all[f] != all[f + 1])
        EpubKey(f, {"opacity": all[f]}),
  ];
}

/// _BackdropVideo marks where the background video goes in the stack.
class _BackdropVideo {
  const _BackdropVideo();
}

/// isBackdropVideo is whether a stage item is the background video's place.
bool isBackdropVideo(Object item) => item is _BackdropVideo;

/// _LayerMaker makes one element's layer.
class _LayerMaker {
  final CanvasElement e;
  final CanvasDocument page;
  final int frames;
  final double pixels;
  final CanvasImageSource? images;
  final _Sheets sheets;
  final ui.Canvas Function(ui.PictureRecorder) start;
  final Rect region;
  final Rect pageBox;
  final ElementFilms? films;
  final ExportMedia? media;

  /// below is what is drawn under it, for filming it where there is no clear
  /// background to film it on.
  final List<CanvasElement> below;
  final int index;

  /// clips are the videos made, for the book to carry.
  final List<EpubFile> clips = [];

  /// sounds are the reactions' sound files in the book, by asset.
  final Map<String, String> sounds;

  /// player is whether the reader plays it, as a video of its own.
  final bool player;

  _LayerMaker(this.e, this.page, this.frames, this.pixels, this.images,
      this.sheets, this.start, this.region, this.pageBox,
      {this.films,
      this.media,
      this.below = const [],
      required this.index,
      this.sounds = const {},
      this.player = false});

  int get rate => page.frameRate <= 0 ? 1 : page.frameRate;

  Keyframe poseAt(int f) => poseWithMotion(e, f, page);

  ui.Picture record(int f,
      {bool hovered = false,
      CanvasElement? element,
      VideoShow Function(VideoElement)? videoShow}) {
    var recorder = ui.PictureRecorder();
    paintElement(start(recorder), element ?? e, f,
        frameRate: page.frameRate,
        images: images,
        document: page,
        hovered: hovered,
        videoShow: videoShow,
        poseOutside: true);
    return recorder.endRecording();
  }

  Future<EpubSprite?> picture(int f,
      {bool hovered = false, CanvasElement? element, Rect? crop}) async {
    // Its pictures read first, not their placeholders (see flatten).
    await drawWhenLoaded(
        images, (_) => record(f, hovered: hovered, element: element).dispose());
    var p = record(f, hovered: hovered, element: element);
    try {
      return await sheets.add(p, crop ?? region);
    } finally {
      p.dispose();
    }
  }

  Future<EpubLayer> make({required bool hovers}) async {
    // A video the reader plays is its own <video> in this layer, poster and
    // all: a picture of it under that played over a frozen copy of itself.
    if (player) {
      var box = e.bounds;
      return EpubLayer(
        id: e.id,
        visible: e.visible,
        originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
        originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
        pose: _poseKeys(),
      );
    }
    // A score sheet and an instrument: pictures switched on and off and
    // moved by the clock, never a film (see _sheetLayer).
    if (e case SheetElement s) {
      if (await _sheetLayer(s) case var layer?) return layer;
    }
    if (e case AudioElement a when a.instrument != null && a.visible) {
      if (await _keysLayer(a) case var layer?) return layer;
    }
    // A synth's keyboard module: played as an instrument is, its keys
    // sounding the patch its speaker plays.
    if (e case SynthModuleElement k
        when k.module == SynthModuleKind.keys && k.visible) {
      if (await _synthKeysLayer(k) case var layer?) return layer;
    }
    var names = [
      for (var f = 0; f < frames; f++)
        _lookAt(e, f, poseAt(f), frames, page.frameRate, poseAt: poseAt),
    ];
    var changes = names.toSet().length > 1 || media != null;

    var parts = <EpubPart>[];
    EpubClip? clip;
    if (!changes) {
      if (await picture(0) case var s?) parts.add(EpubPart(s));
    } else {
      var css = _cssAble() ? await _cssParts() : null;
      if (css != null) {
        parts = css;
      } else if (films != null) {
        clip = await _film(names);
      }
      if (css == null && clip == null) {
        // Nothing can move it here: it holds still, as it ends up.
        if (await picture(frames - 1) case var s?) parts.add(EpubPart(s));
      }
    }

    var box = e.bounds;
    return EpubLayer(
      id: e.id,
      visible: e.visible,
      // What a keyframe turns and grows it about: its anchor, where it is
      // on the page. See ElementBase.anchorX.
      originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
      originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
      pose: _poseKeys(),
      parts: parts,
      clip: clip,
      // As it looks when it has arrived: the pointer is on a button that is
      // there.
      hover: hovers ? await picture(frames - 1, hovered: true) : null,
      hoverBox: hovers
          ? Rect.fromLTRB(box.left * pixels, box.top * pixels,
              box.right * pixels, box.bottom * pixels)
          : null,
      legend: [
        for (var (bit, (_, rect)) in _switchable(e).indexed)
          (
            bit,
            Rect.fromLTRB(rect.left * pixels, rect.top * pixels,
                rect.right * pixels, rect.bottom * pixels)
          ),
      ],
      switched: await _legend(),
      reactions: _reactions(),
    );
  }

  /// drawn records [paint] on the page's canvas and packs what it drew over
  /// [crop] (document units) as a picture.
  Future<EpubSprite?> drawn(void Function(ui.Canvas c) paint, Rect crop) async {
    var recorder = ui.PictureRecorder();
    paint(start(recorder));
    var p = recorder.endRecording();
    try {
      return await sheets.add(
          p,
          Rect.fromLTRB(crop.left * pixels, crop.top * pixels,
              crop.right * pixels, crop.bottom * pixels));
    } finally {
      p.dispose();
    }
  }

  /// _onOff is a picture's opacity at each frame: there while [on] says.
  List<EpubKey> _onOff(bool Function(int f) on) => _compact([
        for (var f = 0; f < frames; f++) {"opacity": on(f) ? "1" : "0"},
      ]);

  EpubLayer _layerOf(List<EpubPart> parts,
      {List<EpubControl> controls = const [], EpubKeyboard? keyboard}) {
    var box = e.bounds;
    return EpubLayer(
      id: e.id,
      visible: e.visible,
      originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
      originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
      pose: _poseKeys(),
      parts: parts,
      controls: controls,
      keyboard: keyboard,
    );
  }

  /// _sheetLayer is a score sheet as a book plays it (Ken, 2026-11-14): each
  /// page of its systems a picture, there while that page shows; each note
  /// lit a picture of its own, there while it sounds; the playhead a line
  /// moved along by the clock; and its playbar, buttons the clock answers --
  /// to the start, a note back, play and pause, a note on, and the track.
  Future<EpubLayer?> _sheetLayer(SheetElement s) async {
    var bounds = s.bounds;
    var views = [
      for (var f = 0; f < frames; f++) sheetViewOf(s, bounds, page, f),
    ];
    if (views.any((v) => v == null)) return null;
    var vs = views.cast<SheetView>();
    double pageOf(SheetView v) => v.window.top;
    var parts = <EpubPart>[];
    var sp = vs.first.engraved.options.space;
    // The pages, each as it is at rest.
    var pages = <double, SheetView>{};
    for (var v in vs) {
      pages.putIfAbsent(pageOf(v), () => v);
    }
    for (var MapEntry(key: top, value: v) in pages.entries) {
      var pic = await drawn(
          (c) => paintScoreSheet(c, bounds, s, v,
              lit: const {},
              head: false,
              progress: 0,
              playing: false,
              knob: false),
          bounds);
      if (pic == null) continue;
      parts.add(EpubPart(pic, keys: _onOff((f) => pageOf(vs[f]) == top)));
      // Each note lit, where it is on this page, while it sounds.
      var lit = <String, Set<int>>{};
      for (var (f, w) in vs.indexed) {
        if (pageOf(w) != top) continue;
        for (var id in sheetSounding(w)) {
          (lit[id] ??= {}).add(f);
        }
      }
      for (var MapEntry(key: id, value: on) in lit.entries) {
        var hit = v.engraved.hits
            .where((h) => h.kind == ScoreHitKind.event && h.event == id)
            .firstOrNull;
        if (hit == null) continue;
        // The head and its stem: up or down from it.
        var r = hit.rect.inflate(sp * 0.2);
        r = Rect.fromLTRB(
            r.left, r.top - sp * 3.6, r.right + sp * 1.6, r.bottom + sp * 3.6);
        var crop = Rect.fromLTRB(
            v.origin.dx + r.left * v.scale,
            v.origin.dy + r.top * v.scale,
            v.origin.dx + r.right * v.scale,
            v.origin.dy + r.bottom * v.scale);
        var pic = await drawn(
            (c) => paintScoreSheet(c, bounds, s, v,
                lit: {id},
                head: false,
                progress: 0,
                playing: false,
                bar: false),
            crop.intersect(bounds));
        if (pic == null) continue;
        parts.add(EpubPart(pic, keys: _onOff(on.contains)));
      }
      // The playhead: one line a system, moved along it.
      if (s.playhead) {
        for (var (si, sys) in v.engraved.systems.indexed) {
          var at = <int, double>{};
          for (var (f, w) in vs.indexed) {
            if (pageOf(w) != top || w.place == null) continue;
            var x = w.engraved.xOf(w.place!.bar, w.place!.at);
            if (x == null || x.$2 != si) continue;
            at[f] = w.origin.dx + (x.$1 + sp * 0.5) * w.scale;
          }
          if (at.isEmpty) continue;
          var x0 = at.values.first;
          var y0 = v.origin.dy + (sys.top) * v.scale;
          var y1 = v.origin.dy + (sys.bottom) * v.scale;
          var line = await drawn((c) {
            var paint = ui.Paint()
              ..color = const ui.Color(0xFFE2622B)
              ..strokeWidth = math.max(1.5, sp * 0.25 * v.scale);
            c.drawLine(Offset(x0, y0), Offset(x0, y1), paint);
          }, Rect.fromLTRB(x0 - sp, y0 - 2, x0 + sp, y1 + 2).intersect(bounds));
          if (line == null) continue;
          parts.add(EpubPart(line,
              keys: _compact([
                for (var f = 0; f < frames; f++)
                  {
                    "opacity": at.containsKey(f) ? "1" : "0",
                    "transform":
                        "translate(${_n(((at[f] ?? x0) - x0) * pixels, 2)}px,0px)",
                  },
              ])));
        }
      }
    }
    // The playbar: the track filled as far as the clock has got, and its
    // buttons the clock answers.
    var controls = <EpubControl>[];
    if (sheetBarRect(s, bounds) case var bar?) {
      var parts0 = sheetBarParts(bar);
      var track = parts0[SheetBarPart.track]!;
      // Its bars as they play: all of them, or the range it shows.
      var (from, to) = sheetFrames(s, page) ?? (0, frames);
      double done(int f) => sheetProgress(s, vs[f]);
      // The filled track, revealed from the left; the knob slid along.
      var line = sheetTrackLine(track);
      var orange = ui.Paint()..color = const ui.Color(0xFFE2622B);
      var fill = await drawn(
          (c) => c.drawRRect(
              ui.RRect.fromRectAndRadius(
                  line, ui.Radius.circular(line.height / 2)),
              orange),
          line.inflate(1));
      if (fill != null) {
        parts.add(EpubPart(fill,
            keys: const [],
            clipKeys: _compact([
              for (var f = 0; f < frames; f++)
                {
                  "clip-path":
                      "inset(0px ${_n((1 - done(f)) * 100, 2)}% 0px 0px)",
                },
            ])));
      }
      var radius = sheetKnobRadius(track);
      var knob = await drawn(
          (c) =>
              c.drawCircle(Offset(line.left, line.center.dy), radius, orange),
          Rect.fromCircle(
              center: Offset(line.left, line.center.dy), radius: radius + 1));
      if (knob != null) {
        parts.add(EpubPart(knob,
            keys: _compact([
              for (var f = 0; f < frames; f++)
                {
                  "transform":
                      "translate(${_n(done(f) * line.width * pixels, 2)}px,0px)",
                },
            ])));
      }
      Rect px(Rect r) => Rect.fromLTRB(
          r.left * pixels, r.top * pixels, r.right * pixels, r.bottom * pixels);
      var onsets = sheetOnsets(s, page).join(",");
      // A pause over the play button while it plays: the bar's tint over the
      // paper, and two bars.
      var play = parts0[SheetBarPart.play]!;
      var tint = ui.Color.alphaBlend(
          s.ink.withValues(alpha: 0.07), s.paper.withValues(alpha: 1));
      var u = play.height * 0.16 * pixels;
      var pause = '<span class="pp" style="background:${_cssColour(tint)}">'
          '<span style="left:${_n(play.width * pixels / 2 - u * 0.75, 2)}px;'
          'top:${_n(play.height * pixels / 2 - u * 1.1, 2)}px;'
          'width:${_n(u * 0.5, 2)}px;height:${_n(u * 2.2, 2)}px;'
          'background:${_cssColour(s.ink)}"></span>'
          '<span style="left:${_n(play.width * pixels / 2 + u * 0.25, 2)}px;'
          'top:${_n(play.height * pixels / 2 - u * 1.1, 2)}px;'
          'width:${_n(u * 0.5, 2)}px;height:${_n(u * 2.2, 2)}px;'
          'background:${_cssColour(s.ink)}"></span></span>';
      var first = sheetOnsets(s, page).firstOrNull ?? from;
      controls = [
        EpubControl("goto", px(parts0[SheetBarPart.start]!),
            data: {"frame": "$first"}, label: "To the start"),
        EpubControl("prev", px(parts0[SheetBarPart.back]!),
            data: {"frames": onsets}, label: "A note back"),
        // A range of bars: play starts at its first bar (if the playhead is
        // not in it) and stops at the end of its last.
        s.fromBar > 0 || s.toBar > 0
            ? EpubControl("range", px(play),
                data: {"from": "$from", "to": "$to"},
                inner: pause,
                label: "Play")
            : EpubControl("toggle", px(play), inner: pause, label: "Play"),
        EpubControl("next", px(parts0[SheetBarPart.on]!),
            data: {"frames": onsets}, label: "A note on"),
        EpubControl("seek", px(track),
            data: {"from": "$from", "to": "$to"}, label: "How far it has got"),
      ];
    }
    return _layerOf(parts, controls: controls);
  }

  /// _keysLayer is an instrument as a book plays it: its keys at rest, and
  /// each key it plays lit, a picture of its own there while it sounds.
  Future<EpubLayer?> _keysLayer(AudioElement a) async {
    var part = a.instrument!;
    var bounds = a.bounds;
    var parts = <EpubPart>[];
    var rest = await drawn(
        (c) => paintAudio(c, bounds, a, AudioState(muted: a.clip.muted)),
        bounds);
    if (rest != null) parts.add(EpubPart(rest));
    var on = <int, Set<int>>{};
    for (var f = 0; f < frames; f++) {
      for (var k in AudioState.atFrame(a, f, rate).keys) {
        (on[k] ??= {}).add(f);
      }
    }
    var layout = keyboardLayout(part, bounds);
    // Each key lit: shown while the page plays it, and while the reader
    // presses it. White keys first, the black ones over them.
    var lit = <({int key, Rect rect, bool black, EpubSprite lit})>[];
    for (var black in [false, true]) {
      for (var key in layout.keys) {
        if (key.black != black) continue;
        var pic = await drawn(
            (c) => paintAudio(
                c, bounds, a, AudioState(muted: a.clip.muted, keys: {key.key})),
            key.rect);
        if (pic == null) continue;
        lit.add((
          key: key.key,
          rect: Rect.fromLTRB(
              (key.rect.left - bounds.left) * pixels,
              (key.rect.top - bounds.top) * pixels,
              (key.rect.right - bounds.left) * pixels,
              (key.rect.bottom - bounds.top) * pixels),
          black: key.black,
          lit: pic
        ));
        if (on[key.key] case var frames0?) {
          parts.add(EpubPart(pic, keys: _onOff(frames0.contains)));
        }
      }
    }
    // Its sound, for the reader to play it.
    EpubKeyboard? keyboard;
    if (await _keySounds(a, [for (var k in lit) k.key])
        case (var file, var low)?) {
      clips.add(file);
      keyboard = EpubKeyboard(
          Rect.fromLTRB(bounds.left * pixels, bounds.top * pixels,
              bounds.right * pixels, bounds.bottom * pixels),
          lit,
          file.href,
          low,
          keyStep);
    }
    return _layerOf(parts, keyboard: keyboard);
  }

  /// _synthKeysLayer is a synth's keyboard module as a book plays it: the
  /// module at rest, each key lit while the reader presses it, and the
  /// keys' sounds -- the patch as it is set, played through the speaker
  /// it is patched to (rendered, as an instrument's are: its knobs are not
  /// turned in a book). Null where it reaches no speaker.
  Future<EpubLayer?> _synthKeysLayer(SynthModuleElement keys) async {
    var speaker = synthSpeakersHearing(page, keys.id).firstOrNull;
    var ch = speaker == null ? null : page.elementById(speaker.channel);
    if (ch is! AudioElement || ch.instrument == null) return null;
    var bounds = keys.bounds;
    var parts = <EpubPart>[];
    var rest = await drawn((c) => paintSynthModule(c, bounds, keys), bounds);
    if (rest != null) parts.add(EpubPart(rest));
    var panel = synthPanelOf(keys.module);
    var (s, at) = synthPanelFit(bounds, panel);
    Rect onPage(Rect r) => Rect.fromLTRB(at.dx + r.left * s, at.dy + r.top * s,
        at.dx + r.right * s, at.dy + r.bottom * s);
    var kr = panel.keys!;
    var ww = kr.width / synthKeyboardWhites.length;
    var places = [
      for (var (i, k) in synthKeyboardWhites.indexed)
        (k, Rect.fromLTWH(kr.left + i * ww, kr.top, ww, kr.height), false),
      for (var (k, r) in synthBlackKeys(kr)) (k, r, true),
    ];
    var lit = <({int key, Rect rect, bool black, EpubSprite lit})>[];
    for (var (key, r, black) in places) {
      var rect = onPage(r);
      var pic = await drawn(
          (c) =>
              paintSynthModule(c, bounds, keys, show: SynthShow(held: {key})),
          rect);
      if (pic == null) continue;
      lit.add((
        key: key,
        rect: Rect.fromLTRB(
            (rect.left - bounds.left) * pixels,
            (rect.top - bounds.top) * pixels,
            (rect.right - bounds.left) * pixels,
            (rect.bottom - bounds.top) * pixels),
        black: black,
        lit: pic
      ));
    }
    EpubKeyboard? keyboard;
    if (await _keySounds(ch, [for (var k in lit) k.key])
        case (var file, var low)?) {
      clips.add(file);
      keyboard = EpubKeyboard(
          Rect.fromLTRB(bounds.left * pixels, bounds.top * pixels,
              bounds.right * pixels, bounds.bottom * pixels),
          lit,
          file.href,
          low,
          keyStep);
    }
    return _layerOf(parts, keyboard: keyboard);
  }

  /// keyStep is how far apart each key's sound is in an instrument's file:
  /// a note held a second, and its ring.
  static const keyStep = 1.6;

  /// _keySounds is every key of [a] from the lowest of [keys] to the
  /// highest, each played as [a] plays it, [keyStep] seconds apart in one
  /// file -- AAC where there is ffmpeg, a small WAV where not -- and the
  /// lowest key's number. Null where it cannot be played.
  Future<(EpubFile, int)?> _keySounds(AudioElement a, List<int> keys) async {
    if (keys.isEmpty) return null;
    var part = a.instrument!;
    var low = keys.reduce(math.min), high = keys.reduce(math.max);
    var notes = [
      for (var k = low; k <= high; k++)
        MidiNote(k, (k - low) * keyStep, 1.0, 100),
    ];
    try {
      var bank = await soundBankPath();
      var wav = await partWav(
          part.copyWith(notes: notes, effects: const [], controls: const {}),
          bankPath:
              part.sound == InstrumentSound.bank && await File(bank).exists()
                  ? bank
                  : null);
      var ffmpeg = films?.ffmpeg ?? await ffmpegPath();
      var stem = "media/keys-${a.id}";
      if (ffmpeg == null) return (EpubFile("$stem.wav", wav, "audio/wav"), low);
      var work = await Directory.systemTemp.createTemp("canvas-keys");
      try {
        var input = path.join(work.path, "keys.wav");
        var output = path.join(work.path, "keys.m4a");
        await File(input).writeAsBytes(wav);
        var run = await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-i", input, "-ac", "1", "-c:a", "aac", "-b:a", "96k", output,
        ]);
        if (run.exitCode != 0) {
          return (EpubFile("$stem.wav", wav, "audio/wav"), low);
        }
        return (
          EpubFile("$stem.m4a", await File(output).readAsBytes(), "audio/mp4"),
          low
        );
      } finally {
        await work.delete(recursive: true);
      }
    } catch (exception) {
      debugPrint("Unable to sound the keys: $exception");
      return null;
    }
  }

  /// _reactions are [e]'s clips that start on a click or after another
  /// clip, each sampled a frame at a time as the canvas plays it -- from
  /// where the element stands, the clip alone -- with the sound linked with
  /// it in its row.
  List<EpubReaction> _reactions() {
    var out = <EpubReaction>[];
    var m = e.base.motion;
    for (var c in _reactionClips(e)) {
      var n = math.max(1, (c.span * rate).round());
      // The element with this clip alone on its timeline, from frame 0, on
      // the page -- so a Go to finds what it goes to.
      var alone = e.withBase(
          motion: m.copyWith(placed: [
        ClipPlacement(id: "rx-${c.id}", clip: c.id, layer: c.layer, start: 0),
      ]));
      var on = page.withElement(alone);
      var css = [
        for (var f = 0; f <= n; f++)
          if (poseWithMotion(alone, f, on) case var k)
            {
              "transform": "translate(${_n(k.dx * pixels, 2)}px,"
                  "${_n(k.dy * pixels, 2)}px) rotate(${_n(k.rotate, 3)}deg) "
                  "scale(${_n(k.scale, 4)})",
              "opacity": _n(k.opacity.clamp(0.0, 1.0).toDouble(), 3),
            },
      ];
      var row = m.slots.indexOf(c.id);
      var own = e is VideoElement && (e as VideoElement).clip.channel.isEmpty
          ? e.id
          : "snd-${e.id}";
      var linked =
          row >= 0 && m.isLinked(row) ? page.session.at(own, row) : null;
      var file = linked?.sound == null ? null : sounds[linked!.sound!.assetId];
      for (var t in c.triggers) {
        var on = switch (t.kind) {
          ClipTriggerKind.clicked when t.target.isNotEmpty =>
            "click:${t.target}",
          ClipTriggerKind.clipEnds => "end:${t.target}",
          _ => null,
        };
        if (on == null) continue;
        out.add(EpubReaction(c.id, on, n, _compact(css),
            sound: file,
            volume: linked == null
                ? 1
                : math.pow(10, linked.gain / 20).clamp(0.0, 1.0).toDouble()));
      }
    }
    return out;
  }

  /// _legend is the chart with each set of its key's series switched, by
  /// mask: a picture for each, as it is once it has grown.
  Future<Map<int, EpubSprite>> _legend() async {
    var chart = e;
    var series = _switchable(chart);
    if (chart is! ChartElement || series.isEmpty) return const {};
    var out = <int, EpubSprite>{};
    for (var mask = 1; mask < 1 << series.length; mask++) {
      var flipped = [...chart.data.series];
      for (var (bit, (at, _)) in series.indexed) {
        if (mask & (1 << bit) != 0) {
          flipped[at] = flipped[at].copyWith(hidden: !flipped[at].hidden);
        }
      }
      var switched = chart.copyWith(data: chart.data.copyWith(series: flipped));
      if (await picture(frames - 1, element: switched) case var s?) {
        out[mask] = s;
      }
    }
    return out;
  }

  /// _poseKeys is where the element is, frame by frame, as CSS about its
  /// centre -- or nothing, where it stays where it was put.
  List<EpubKey> _poseKeys() {
    var css = [
      for (var f = 0; f < frames; f++)
        if (poseAt(f) case var k)
          {
            "transform": "translate(${_n(k.dx * pixels, 2)}px,"
                "${_n(k.dy * pixels, 2)}px) rotate(${_n(k.rotate, 3)}deg) "
                "scale(${_n(k.scale, 4)})",
            "opacity": _n(k.opacity.clamp(0.0, 1.0).toDouble(), 3),
          },
    ];
    var keys = _compact(css);
    if (keys.length == 1 &&
        keys.single.css["transform"] ==
            "translate(0px,0px) rotate(0deg) scale(1)" &&
        keys.single.css["opacity"] == "1") {
      return const [];
    }
    return keys;
  }

  /// _cssAble is whether everything [e] does besides its pose is a motion --
  /// something the renderer does to it through applyMotionSpec, which CSS
  /// can do too.
  bool _cssAble() {
    // Nothing but the arrival and the leaving changes.
    String others(int f) {
      var v = {...poseAt(f).values}
        ..remove(KeyframeChannel.reveal)
        ..remove(KeyframeChannel.close);
      var keys = v.keys.toList()..sort();
      return keys.map((k) => "$k=${v[k]}").join(";");
    }

    var first = others(0);
    for (var f = 1; f < frames; f++) {
      if (others(f) != first) return false;
    }
    switch (e) {
      case TextElement t:
        var a = t.animation;
        return t.curve == null &&
            (!a.on || wholeBlockMotion(a.preset.motion)) &&
            (!a.closes || wholeBlockMotion(a.exit.motion)) &&
            // A part of the words with an animation of its own moves on its
            // own clock inside the element's -- filmed, not cut.
            t.parts.every(
                (part) => part.animation.preset == TextAnimationPreset.none);
      case ChartElement _:
      case TeamElement _:
      case BackgroundElement _:
        return false;
      default:
        var a = _elementAnimation(e);
        return a != null && !a.cuts;
    }
  }

  /// _cssParts is [e] as pictures moved by CSS, read off the renderer frame
  /// by frame -- or null where what it does cannot be read that way.
  Future<List<EpubPart>?> _cssParts() async {
    // Ask the renderer, frame by frame, what it moves and how -- only over
    // the stretch where the element arrives or leaves.
    var span = _valuedSpan(e, frames, poseAt);
    if (span == null) return null;
    var calls = <int, List<MotionCall>>{};
    for (var f = math.max(0, span.$1);
        f <= math.min(frames - 1, span.$2 + 1);
        f++) {
      var seen = <MotionCall>[];
      motionProbe = seen.add;
      try {
        record(f).dispose();
      } finally {
        motionProbe = null;
      }
      calls[f] = seen;
    }

    // The pieces: whatever the renderer moved, known by where it was before
    // it moved it -- the same box at every frame.
    String keyOf(MotionCall c) {
      var b = c.before;
      return "${c.box.left.toStringAsFixed(2)},${c.box.top.toStringAsFixed(2)},"
          "${c.box.width.toStringAsFixed(2)},${c.box.height.toStringAsFixed(2)}"
          "@${[
        b[0],
        b[1],
        b[4],
        b[5],
        b[12],
        b[13]
      ].map((v) => v.toStringAsFixed(3)).join(",")}";
    }

    var pieces = <String, MotionCall>{};
    for (var list in calls.values) {
      for (var c in list) {
        pieces.putIfAbsent(keyOf(c), () => c);
      }
    }
    if (pieces.isEmpty) return null;
    var byPiece = e is TextElement &&
        (e as TextElement).animation.preset.scope != TextAnimationScope.block;
    // A whole-element motion that turns out to move it in several pieces --
    // columns, each moved on its own -- would cut the picture wrongly.
    if (!byPiece && pieces.length > 1) return null;

    // As it is when it has arrived, and what of it never moves at all -- a
    // box behind text, say, which is there before the words are.
    Keyframe settledWith(double reveal) => Keyframe(frame: 0, values: {
          ...poseAt(0).values,
          KeyframeChannel.reveal: reveal,
          KeyframeChannel.close: 0,
        });
    // Its clips set aside: these are it at one fixed pose.
    var settled = e.withBase(
        track: ElementTrack([settledWith(1)]), motion: ElementMotion.none);
    var bare = e.withBase(
        track: ElementTrack([settledWith(0)]), motion: ElementMotion.none);

    var parts = <EpubPart>[];
    if (await picture(0, element: bare) case var s?) parts.add(EpubPart(s));

    // Text in a box, its words arriving one by one: the words are cut from
    // it drawn without its box, and the box is a picture of its own, there
    // from when the arrival starts. Cut with the words, the box went in
    // slices with them -- a chip's outline in pieces (Ken, 2026-11-13: the
    // mixer's "2.00 DCR" chips).
    var words = settled;
    if (byPiece && settled is TextElement) {
      var t = settled;
      var b = t.box;
      if (b.fill.a > 0 || (b.borderWidth > 0 && b.borderColor.a > 0)) {
        const none = ui.Color(0x00000000);
        words = t.copyWith(
            box: b.copyWith(
                fill: none,
                borderColor: none,
                flatFill: true,
                flatBorder: true));
        var boxOnly = t.copyWith(textSpec: t.textSpec.copyWith(color: none));
        if (await picture(0, element: boxOnly) case var s?) {
          var from = math.max(0, span.$1);
          parts.add(EpubPart(s, keys: [
            const EpubKey(0, {"opacity": "0"}),
            if (from > 1) EpubKey(from - 1, const {"opacity": "0"}),
            EpubKey(from, const {"opacity": "1"}),
            // Held to the last frame: a last key short of it is run on to
            // the style written inline -- the first key's, hidden.
            if (frames - 1 > from) EpubKey(frames - 1, const {"opacity": "1"}),
          ]));
        }
      }
    }

    var whole = record(0, element: words);
    try {
      for (var entry in pieces.entries) {
        var c = entry.value;
        // A piece is its box, and a little above and below it for what
        // reaches past a line -- as the renderer clips each piece.
        var crop = byPiece
            ? _mapRect(
                c.before,
                Rect.fromLTRB(c.box.left, c.box.top - c.box.height * 0.3,
                    c.box.right, c.box.bottom + c.box.height * 0.3))
            : region;
        var sprite = await sheets.add(whole, crop);
        if (sprite == null) continue;
        parts.add(_moved(sprite, entry.key, calls, keyOf));
      }
    } finally {
      whole.dispose();
    }
    return parts;
  }

  /// _moved is one piece's keyframes, from what the renderer did to it at
  /// each frame.
  EpubPart _moved(EpubSprite sprite, String key,
      Map<int, List<MotionCall>> calls, String Function(MotionCall) keyOf) {
    var blurs = false, clips = false;
    var at = <int, MotionCall>{};
    for (var MapEntry(key: f, value: list) in calls.entries) {
      for (var c in list) {
        if (keyOf(c) == key) {
          at[f] = c;
          if (c.blur > 0) blurs = true;
          if (c.clip != null) clips = true;
        }
      }
    }
    // Where the renderer did not move it, it is either there or not.
    bool there(int f) {
      var v = poseAt(f).values;
      return (v[KeyframeChannel.reveal] ?? 1) >= 1 &&
          (v[KeyframeChannel.close] ?? 0) <= 0;
    }

    const everything = "polygon(-100000px -100000px, 100000px -100000px, "
        "100000px 100000px, -100000px 100000px)";
    var looks = <Map<String, String>>[];
    var frames_ = <Map<String, String>>[];
    for (var f = 0; f < frames; f++) {
      var c = at[f];
      if (c == null) {
        looks.add({
          "transform": "matrix(1,0,0,1,0,0)",
          "opacity": there(f) ? "1" : "0",
          if (blurs) "filter": "blur(0px)",
        });
        if (clips) frames_.add({"clip-path": everything});
        continue;
      }
      var m = _mul(c.after, _invert(c.before));
      var scale = math
          .sqrt((c.before[0] * c.before[5] - c.before[1] * c.before[4]).abs());
      looks.add({
        "transform": "matrix(${_n(m[0], 5)},${_n(m[1], 5)},${_n(m[4], 5)},"
            "${_n(m[5], 5)},${_n(m[12], 2)},${_n(m[13], 2)})",
        "opacity": _n(c.frame.alpha.clamp(0.0, 1.0).toDouble(), 3),
        if (blurs) "filter": "blur(${_n(c.blur * scale, 2)}px)",
      });
      if (clips) {
        var clip = c.clip;
        if (clip == null) {
          frames_.add({"clip-path": everything});
        } else {
          var corners = [
            clip.topLeft,
            clip.topRight,
            clip.bottomRight,
            clip.bottomLeft,
          ].map((p) => _mapPoint(c.before, p) - Offset(sprite.x, sprite.y));
          frames_.add({
            "clip-path":
                "polygon(${corners.map((p) => "${_n(p.dx, 2)}px ${_n(p.dy, 2)}px").join(", ")})",
          });
        }
      }
    }
    return EpubPart(sprite,
        keys: _compact(looks), clipKeys: clips ? _compact(frames_) : const []);
  }

  /// _film makes [e]'s change a video of it alone, over the frames it
  /// changes on.
  Future<EpubClip?> _film(List<String> names) async {
    var films = this.films!;
    int a, b;
    if (media != null) {
      a = 0;
      b = frames - 1;
    } else {
      var changed = [
        for (var i = 1; i < names.length; i++)
          if (names[i] != names[i - 1]) i,
      ];
      if (changed.isEmpty) return null;
      a = changed.first - 1;
      b = changed.last;
    }
    // Even sides: neither encoder takes an odd one.
    var box = Rect.fromLTWH(region.left, region.top,
        (region.width / 2).ceil() * 2.0, (region.height / 2).ceil() * 2.0);
    var w = box.width.round(), h = box.height.round();

    // What is under it on the page, which holds still. With HEVC alpha it is
    // only used for half-clear pixels (see _solidOrClear); without, the
    // element is filmed over it.
    ui.Picture under;
    {
      var recorder = ui.PictureRecorder();
      var canvas = start(recorder);
      paintCanvasDocument(canvas, page,
          part: CanvasPaintPart.backdrop, images: images);
      _paintFacing(canvas, page, index, images);
      for (var x in below) {
        paintElement(canvas, x, 0,
            frameRate: page.frameRate, images: images, document: page);
      }
      under = recorder.endRecording();
    }

    Directory? work;
    Process? running;
    try {
      work = await Directory.systemTemp.createTemp("canvas-element-film");
      var out = path.join(work.path, "clip.mp4");
      var process = running = await Process.start(films.ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "${w}x$h",
        "-r", "$rate", "-i", "-",
        // Tagged sRGB, which is what the renderer drew: untagged, a reader
        // assumes the TV curve and the film no longer matches the element's
        // own picture. The encoder takes this from the frames.
        "-vf",
        [
          if (!films.alpha) "scale=out_color_matrix=bt709:out_range=tv",
          "setparams=color_primaries=bt709:color_trc=iec61966-2-1:"
              "colorspace=bt709:range=tv",
        ].join(","),
        if (films.alpha) ...[
          "-c:v",
          "hevc_videotoolbox",
          "-q:v",
          "60",
          "-alpha_quality",
          "0.9",
          "-tag:v",
          "hvc1",
        ] else ...[
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "18",
          "-pix_fmt",
          "yuv420p",
        ],
        // A picture whole every second, so a page that jumps to a frame
        // finds it without decoding from the start.
        "-g", "$rate",
        "-movflags", "+faststart+write_colr",
        out,
      ]);
      var errors = StringBuffer();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(errors.write);
      Future<Uint8List?> pixels(ui.Picture over, {bool onPage = false}) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder)..translate(-box.left, -box.top);
        if (onPage) canvas.drawPicture(under);
        canvas.drawPicture(over);
        var framed = recorder.endRecording();
        try {
          var image = await framed.toImage(w, h);
          try {
            var raw = await image.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba);
            return raw?.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        } finally {
          framed.dispose();
        }
      }

      for (var f = a; f <= b; f++) {
        var show = media == null ? null : await media!.at(f);
        var p = record(f, videoShow: show);
        try {
          var onPage = await pixels(p, onPage: true);
          if (onPage == null) break;
          if (films.alpha) {
            var alone = await pixels(p);
            if (alone == null) break;
            _solidOrClear(alone, onPage);
            process.stdin.add(alone);
          } else {
            process.stdin.add(onPage);
          }
          await process.stdin.flush();
        } finally {
          p.dispose();
        }
      }
      await process.stdin.close();
      if (await process.exitCode != 0 || !await File(out).exists()) {
        debugPrint("Unable to film ${e.id} for the book: $errors");
        return null;
      }
      var href = "media/p$index-${_safe(e.id)}.mp4";
      clips.add(EpubFile(href, await File(out).readAsBytes(), "video/mp4"));
      return EpubClip(href, a, b - a + 1, box,
          before: await picture(a), after: await picture(b));
    } catch (exception) {
      debugPrint("Unable to film ${e.id} for the book: $exception");
      // Not left waiting on its input for as long as the app runs.
      running?.kill();
      return null;
    } finally {
      under.dispose();
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// _solidOrClear makes every pixel of [alone] -- the element by itself --
/// either clear or solid: a half-clear one takes the colour it makes over the
/// page, from [onPage], and becomes solid.
///
/// Apple Books treats video colour as premultiplied, so half-clear pixels
/// would come out too bright; with none, it looks the same however alpha is
/// read. Exact because what is under the element holds still.
void _solidOrClear(Uint8List alone, Uint8List onPage) {
  var mine = alone.buffer.asUint32List(alone.offsetInBytes, alone.length >> 2);
  var page =
      onPage.buffer.asUint32List(onPage.offsetInBytes, onPage.length >> 2);
  for (var i = 0; i < mine.length; i++) {
    var a = mine[i] >> 24;
    if (a == 0) {
      mine[i] = 0;
    } else if (a != 0xFF) {
      mine[i] = page[i] | 0xFF000000;
    }
  }
}

String _safe(String id) => id.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_");

/// _elementAnimation is the arrival of the kinds that have one of their own.
ElementAnimation? _elementAnimation(CanvasElement e) => switch (e) {
      ShapeElement e => e.animation,
      ImageElement e => e.animation,
      VectorElement e => e.animation,
      LineElement e => e.animation,
      PathElement e => e.animation,
      TableElement e => e.animation,
      CounterElement e => e.animation,
      ButtonElement e => e.animation,
      AudioElement e => e.animation,
      VideoElement e => e.animation,
      Character3dElement e => e.animation,
      _ => null,
    };

/// _cssColour is [c] as CSS.
String _cssColour(ui.Color c) =>
    "rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},"
    "${c.a.toStringAsFixed(3)})";

/// _compact is a value a frame as keyframes: only where something changes,
/// and either end of a stretch where nothing does.
List<EpubKey> _compact(List<Map<String, String>> byFrame) {
  bool same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((x) => b[x.key] == x.value);
  var out = <EpubKey>[];
  for (var f = 0; f < byFrame.length; f++) {
    var here = byFrame[f];
    var keep = f == 0 ||
        f == byFrame.length - 1 ||
        !same(here, byFrame[f - 1]) ||
        !same(here, byFrame[f + 1]);
    if (keep) out.add(EpubKey(f, here));
  }
  // A value that never changes is one key.
  if (out.every((k) => same(k.css, out.first.css))) return [out.first];
  return out;
}

String _n(double v, int places) {
  var s = v.toStringAsFixed(places);
  if (s.contains(".")) {
    s = s.replaceFirst(RegExp(r"0+$"), "").replaceFirst(RegExp(r"\.$"), "");
  }
  return s == "-0" ? "0" : s;
}

/// _mul is a times b, for column-major 4x4 matrices as the canvas gives them.
Float64List _mul(Float64List a, Float64List b) {
  var out = Float64List(16);
  for (var c = 0; c < 4; c++) {
    for (var r = 0; r < 4; r++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[k * 4 + r] * b[c * 4 + k];
      }
      out[c * 4 + r] = sum;
    }
  }
  return out;
}

/// _invert is the inverse of a canvas transform, which is flat: a turn, a
/// scale and a shift, and nothing in depth.
Float64List _invert(Float64List m) {
  var a = m[0], b = m[1], c = m[4], d = m[5], e = m[12], f = m[13];
  var det = a * d - b * c;
  if (det.abs() < 1e-12) det = 1e-12;
  var out = Float64List(16)
    ..[10] = 1
    ..[15] = 1;
  out[0] = d / det;
  out[1] = -b / det;
  out[4] = -c / det;
  out[5] = a / det;
  out[12] = (c * f - d * e) / det;
  out[13] = (b * e - a * f) / det;
  return out;
}

Offset _mapPoint(Float64List m, Offset p) => Offset(
    m[0] * p.dx + m[4] * p.dy + m[12], m[1] * p.dx + m[5] * p.dy + m[13]);

Rect _mapRect(Float64List m, Rect r) {
  var ps = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]
      .map((p) => _mapPoint(m, p))
      .toList();
  return Rect.fromLTRB(
      ps.map((p) => p.dx).reduce(math.min),
      ps.map((p) => p.dy).reduce(math.min),
      ps.map((p) => p.dx).reduce(math.max),
      ps.map((p) => p.dy).reduce(math.max));
}

/// _Sheets packs a page's pictures onto as few sheets as will hold them, so a
/// page is a few files rather than one a picture. Each picture is drawn over
/// its region, read back, trimmed to its ink and named by its pixels; one
/// already packed is not packed twice. Sprites come back placed
/// provisionally -- a sheet is named when it is written -- and [placed] gives
/// the final one after [close].
class _Sheets {
  final String stem;

  /// side is how large a sheet may grow, in pixels: 16 MB decoded, within
  /// what a tablet will decode without complaint.
  static const int side = 2048;

  /// gap keeps a picture's neighbours out of it when a reader scales it and
  /// samples across its edge.
  static const int gap = 2;

  final List<EpubFile> files = [];
  final Map<String, EpubSprite> _byPixels = {};
  final Map<EpubSprite, EpubSprite> _final = {};
  final Map<EpubSprite, String> _hrefs = {};
  final List<Future<EpubFile?>> _encoding = [];

  _Sheets(this.stem);

  final List<(ui.Image, EpubSprite)> _pieces = [];
  int _x = 0, _y = 0, _row = 0, _wide = 0, _tall = 0;

  Future<Uint8List?> _pixels(ui.Picture picture, Rect region) async {
    var w = region.width.round(), h = region.height.round();
    if (w <= 0 || h <= 0) return null;
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    var shifted = recorder.endRecording();
    try {
      var image = await shifted.toImage(w, h);
      try {
        var raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return raw?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      shifted.dispose();
    }
  }

  /// add draws [picture] over [region], trims it, and packs it -- or returns
  /// the same picture already packed, or null for one with nothing in it.
  Future<EpubSprite?> add(ui.Picture picture, Rect region) async {
    region = Rect.fromLTRB(
        region.left.floorToDouble(),
        region.top.floorToDouble(),
        region.right.ceilToDouble(),
        region.bottom.ceilToDouble());
    var w = region.width.round(), h = region.height.round();
    var rgba = await _pixels(picture, region);
    if (rgba == null) return null;
    var ink = _inkBounds(rgba, w, h);
    if (ink == null) return null;
    var cw = ink.width.round(), ch = ink.height.round();
    var cut = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      var from = ((ink.top.round() + y) * w + ink.left.round()) * 4;
      cut.setRange(y * cw * 4, (y + 1) * cw * 4, rgba, from);
    }
    var x = region.left + ink.left, y = region.top + ink.top;
    var name = "${_hashOf(cut)}:${cw}x$ch@$x,$y";
    var known = _byPixels[name];
    if (known == null) {
      known = await _pack(await _fromPixels(cut, cw, ch), x, y);
      _byPixels[name] = known;
    }
    return known;
  }

  /// alone draws [picture] over [region] as a sheet of its own, untrimmed.
  Future<EpubSprite?> alone(ui.Picture picture, Rect region) async {
    var w = region.width.round(), h = region.height.round();
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    var shifted = recorder.endRecording();
    try {
      var image = await shifted.toImage(w, h);
      var sprite = EpubSprite(
          _write(image), region.left, region.top, w.toDouble(), h.toDouble());
      _final[sprite] = sprite;
      return sprite;
    } finally {
      shifted.dispose();
    }
  }

  Future<EpubSprite> _pack(ui.Image piece, double x, double y) async {
    var w = piece.width, h = piece.height;
    if (_x + w > side && _x > 0) {
      _x = 0;
      _y += _row + gap;
      _row = 0;
    }
    if (_y + h > side && _pieces.isNotEmpty) await _flush();
    var sprite = EpubSprite("", x, y, w.toDouble(), h.toDouble(),
        sx: _x.toDouble(), sy: _y.toDouble());
    _pieces.add((piece, sprite));
    _x += w + gap;
    _row = math.max(_row, h);
    _wide = math.max(_wide, _x - gap);
    _tall = math.max(_tall, _y + h);
    return sprite;
  }

  Future<void> _flush() async {
    if (_pieces.isEmpty) return;
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    for (var (image, s) in _pieces) {
      canvas.drawImage(image, Offset(s.sx, s.sy), ui.Paint());
    }
    var picture = recorder.endRecording();
    try {
      var href = _write(await picture.toImage(_wide, _tall));
      for (var (_, s) in _pieces) {
        _hrefs[s] = href;
      }
    } finally {
      picture.dispose();
      for (var (image, _) in _pieces) {
        image.dispose();
      }
      _pieces.clear();
      _x = _y = _row = _wide = _tall = 0;
    }
  }

  /// _write names [image]'s file at once and encodes it alongside whatever
  /// is drawn next; nothing waits on it but [close]. The image is the
  /// writer's to dispose.
  String _write(ui.Image image) {
    var href = "$stem-${_encoding.length}.png";
    _encoding.add(() async {
      try {
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png == null
            ? null
            : EpubFile(href, png.buffer.asUint8List(), "image/png");
      } finally {
        image.dispose();
      }
    }());
    return href;
  }

  /// close writes the last sheet and waits for every one to be encoded.
  Future<void> close() async {
    await _flush();
    for (var f in await Future.wait(_encoding)) {
      if (f != null) files.add(f);
    }
  }

  /// placed is [sprite] on the sheet it was written to.
  EpubSprite placed(EpubSprite sprite) => _final[sprite] ??= EpubSprite(
      _hrefs[sprite] ?? sprite.href,
      sprite.x,
      sprite.y,
      sprite.width,
      sprite.height,
      sx: sprite.sx,
      sy: sprite.sy);
}

/// _switchable is the series of a chart's key that a reader can switch on
/// and off, with where each entry is drawn, in design units -- at most the
/// first five, which is thirty-two pictures of the chart. Empty for anything
/// that is not a chart with a key of series.
List<(int, Rect)> _switchable(CanvasElement e) {
  if (e is! ChartElement || !e.visible) return const [];
  return chartLegendRects(e, e.bounds).take(5).toList();
}

/// _hovers is whether [e] looks different under the pointer.
bool _hovers(ButtonElement e) => e.hoverFill.a > 0 || e.hoverTextColor.a > 0;

/// _regionFor is the part of the page, in page pixels, that [e] can draw in
/// at rest: its box, turned as it is turned, with room round it for what
/// reaches outside a box -- a shadow, an outline, an arrival that slides or
/// grows in. Within the page, unless [moves], when what is off the page at
/// rest can be brought onto it.
Rect _regionFor(
    CanvasElement e, double pixels, Rect pageBox, CanvasDocument document,
    {required bool moves}) {
  var bounds = e.bounds;
  // An element reused is drawn as all of its instances, each where it is
  // put from the element (its place is in the picture; the shared move in
  // the CSS).
  if (e.base.motion.instances case var set?) {
    for (var x in set.items) {
      bounds = bounds.expandToInclude(e.bounds.shift(Offset(x.dx, x.dy)));
    }
  }
  // Things drawn somewhere other than their own box: text riding a line, and
  // a page number mirrored to the outside edge of a left-hand leaf.
  var elsewhere = (e is TextElement && e.curve != null) ||
      (e is CounterElement && e.isPageNumber);
  Rect region;
  if (elsewhere) {
    region = pageBox;
  } else {
    var turned = _turnedBounds(bounds, e.rotationRadians);
    var side = math.max(bounds.width, bounds.height);
    // An arrival that slides, grows, spins or scatters reaches as far again
    // as the element is big. Anything else only reaches as far as a shadow
    // or an outline -- a chart grows inside its own box.
    var room = (_travels(e) ? side : side * 0.1 + 24) +
        // Its looks reach as far as they reach (see motion_looks.dart).
        looksReach(e.base.motion.looks);
    region = Rect.fromLTRB(
        (turned.left - room) * pixels,
        (turned.top - room) * pixels,
        (turned.right + room) * pixels,
        (turned.bottom + room) * pixels);
  }
  var limit = moves
      ? pageBox.inflate(math.max(pageBox.width, pageBox.height) / 2)
      : pageBox;
  region = region.intersect(limit);
  return Rect.fromLTRB(region.left.floorToDouble(), region.top.floorToDouble(),
      region.right.ceilToDouble(), region.bottom.ceilToDouble());
}

/// _travels is whether [e] has an arrival or a leaving that can take it out
/// of its own box.
bool _travels(CanvasElement e) {
  if (e is TextElement) return e.animation.on || e.animation.closes;
  var a = switch (e) {
    ShapeElement e => e.animation,
    ImageElement e => e.animation,
    VectorElement e => e.animation,
    LineElement e => e.animation,
    PathElement e => e.animation,
    TableElement e => e.animation,
    CounterElement e => e.animation,
    ButtonElement e => e.animation,
    AudioElement e => e.animation,
    VideoElement e => e.animation,
    Character3dElement e => e.animation,
    _ => null,
  };
  return a != null && (a.on || a.closes);
}

Rect _turnedBounds(Rect box, double radians) {
  if (radians == 0) return box;
  var c = box.center;
  var cos = math.cos(radians), sin = math.sin(radians);
  var xs = <double>[], ys = <double>[];
  for (var p in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
    var dx = p.dx - c.dx, dy = p.dy - c.dy;
    xs.add(c.dx + dx * cos - dy * sin);
    ys.add(c.dy + dx * sin + dy * cos);
  }
  return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
      xs.reduce(math.max), ys.reduce(math.max));
}

/// _paintFacing is the facing leaf's overhang: what is laid across the gutter
/// from the other page, as renderDocumentPage draws it.
void _paintFacing(ui.Canvas canvas, CanvasDocument document, int index,
    CanvasImageSource? images) {
  var beside = document.facingAt(index);
  if (beside == null) return;
  var size = document.size.size;
  var onLeft = document.facingIsLeft(index) ?? false;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate(onLeft ? size.width : -size.width, 0);
  paintCanvasDocument(
      canvas, document.goToScene(beside).copyWith(onMaster: false),
      part: CanvasPaintPart.contents, images: images);
  canvas.restore();
}

Future<ui.Image> _fromPixels(Uint8List rgba, int width, int height) {
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _changes is whether [e] looks different, or is somewhere different, at
/// any frame of a page [frames] long.
bool _changes(CanvasElement e, int frames, CanvasDocument page) {
  if (frames <= 1) return false;
  // A score sheet lights its notes and moves its playhead as the page
  // plays; an instrument lights its keys.
  if (e is SheetElement && sheetViewOf(e, e.bounds, page, 0) != null) {
    return true;
  }
  // An instrument on the page is played by the reader, its keys lit.
  if (e is AudioElement && e.instrument != null && e.visible) return true;
  // And so is a synth's keyboard module.
  if (e is SynthModuleElement &&
      e.module == SynthModuleKind.keys &&
      e.visible) {
    return true;
  }
  var rate = page.frameRate;
  Keyframe poseAt(int f) => poseWithMotion(e, f, page);
  var first = poseAt(0);
  var firstLook = _lookAt(e, 0, first, frames, rate, poseAt: poseAt);
  for (var f = 1; f < frames; f++) {
    var pose = poseAt(f);
    if (pose.dx != first.dx ||
        pose.dy != first.dy ||
        pose.rotate != first.rotate ||
        pose.scale != first.scale ||
        pose.opacity != first.opacity) {
      return true;
    }
    if (_lookAt(e, f, pose, frames, rate, poseAt: poseAt) != firstLook) {
      return true;
    }
  }
  return false;
}

/// _lookAt names what [e] looks like at frame [f], its pose aside: two frames
/// with the same name are the same picture.
///
/// Mostly that is the channels the pose pins. Things that read the frame
/// itself (staggered text, chart series, text on a line, running players,
/// animated patterns) add the frame to the name where it can matter.
String _lookAt(CanvasElement e, int f, Keyframe pose, int frames, int rate,
    {Keyframe Function(int frame)? poseAt}) {
  var values = pose.values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  var named = values.map((v) => "${v.key}=${v.value}").join(";");
  // A chart whose series start apart is named by how far each has got.
  if (e is ChartElement) {
    if (chartSeriesReveal(e, f, rate, poseAt: poseAt) case var series?) {
      named = "$named;series=${series.join(",")}";
    }
  }
  var span = _frameSpan(e, frames, poseAt);
  if (span == null) return named;
  var (from, to) = span;
  var when = f < from
      ? "before"
      : f > to
          ? "after"
          : "$f";
  return "$named@$when";
}

/// _frameSpan is the stretch of frames over which [e]'s look depends on the
/// frame itself, or null where it never does.
(int, int)? _frameSpan(
    CanvasElement e, int frames, Keyframe Function(int frame)? poseAt) {
  var all = (0, frames - 1);
  switch (e) {
    case BackgroundElement b:
      return b.spec.animated ? all : null;
    case TeamElement t:
      return t.players.any((p) => p.track?.isEmpty == false) ? all : null;
    case TextElement t:
      if (t.curve != null) return all;
      return _valuedSpan(t, frames, poseAt);
    case ChartElement _:
      // Named by its channels and its series -- see _lookAt.
      return null;
    default:
      return null;
  }
}

/// _valuedSpan is from the first keyframe that pins a channel to the last.
///
/// With clips, the stretch over which the values its poses carry change,
/// sampled frame by frame through [poseAt].
(int, int)? _valuedSpan(
    CanvasElement e, int frames, Keyframe Function(int frame)? poseAt) {
  if (poseAt != null && !e.base.motion.isEmpty) {
    int? from, to;
    var was = poseAt(0).values;
    for (var f = 1; f < frames; f++) {
      var now = poseAt(f).values;
      if (!_sameValues(was, now)) {
        from ??= f - 1;
        to = f;
      }
      was = now;
    }
    // Values held the whole way still count from the start.
    if (from == null && poseAt(0).values.isNotEmpty) return (0, 0);
    return from == null ? null : (from, to!);
  }
  var keys = [
    for (var k in e.track?.keys ?? const <Keyframe>[])
      if (k.values.isNotEmpty) k.frame,
  ];
  if (keys.isEmpty) return null;
  return (keys.reduce(math.min), keys.reduce(math.max));
}

bool _sameValues(Map<String, double> a, Map<String, double> b) =>
    a.length == b.length && a.entries.every((x) => b[x.key] == x.value);

/// _inkBounds is the smallest rectangle holding every pixel of [rgba] that
/// is not fully transparent, or null for none. A word a pixel, so a row of
/// nothing is a quarter of the reads.
Rect? _inkBounds(Uint8List rgba, int width, int height) {
  var px = rgba.buffer.asUint32List(rgba.offsetInBytes, width * height);
  // Two pixels a read, to find the rows with nothing in them -- most of
  // them, round an element.
  var pairs = width.isEven
      ? rgba.buffer.asUint64List(rgba.offsetInBytes, width * height >> 1)
      : null;
  const alphas = 0xFF000000FF000000;
  bool blank(int y) {
    if (pairs == null) return false;
    var from = y * width >> 1, to = from + (width >> 1);
    for (var i = from; i < to; i++) {
      if (pairs[i] & alphas != 0) return false;
    }
    return true;
  }

  // Alpha is the last byte of each pixel: the top of a little-endian word.
  const alpha = 0xFF000000;
  var left = width, right = -1, top = height, bottom = -1;
  for (var y = 0; y < height; y++) {
    if (blank(y)) continue;
    var row = y * width;
    var l = -1;
    for (var x = 0; x < width; x++) {
      if (px[row + x] & alpha != 0) {
        l = x;
        break;
      }
    }
    if (l < 0) continue;
    var r = l;
    for (var x = width - 1; x > l; x--) {
      if (px[row + x] & alpha != 0) {
        r = x;
        break;
      }
    }
    if (l < left) left = l;
    if (r > right) right = r;
    if (y < top) top = y;
    bottom = y;
  }
  if (right < 0) return null;
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

/// _hashOf names a picture's pixels: FNV-1a over its words, 64 bits. Only
/// compared between pictures of the same size in the same place on the same
/// page, so a fast non-cryptographic hash is enough.
int _hashOf(Uint8List rgba) {
  var words = rgba.buffer.asUint32List(rgba.offsetInBytes, rgba.length >> 2);
  var h = 0xcbf29ce484222325;
  for (var i = 0; i < words.length; i++) {
    h = (h ^ words[i]) * 0x100000001b3;
  }
  return h;
}

/// isTimedMedia is whether [e] is a sound or a video on the timeline.
bool isTimedMedia(CanvasElement e) => switch (e) {
      AudioElement a => a.clip.timed && !a.clip.isEmpty,
      VideoElement v => v.clip.timed && !v.clip.isEmpty,
      _ => false,
    };

/// _reactionClips are [e]'s clips a book can play on something happening on
/// the page: started by a click on a named element, or by another clip
/// ending. Not sounds, which go with them.
List<MotionClip> _reactionClips(CanvasElement e) => [
      for (var c in e.base.motion.clips)
        if (!c.isSound &&
            c.triggers.any((t) =>
                (t.kind == ClipTriggerKind.clicked && t.target.isNotEmpty) ||
                t.kind == ClipTriggerKind.clipEnds))
          c,
    ];

/// _reactionSounds are the sounds linked with [elements]' reactions, a file
/// each for the book by asset: an MP3 or AAC as it is -- core EPUB 3 audio
/// -- anything else made AAC by ffmpeg, or left out without it.
Future<Map<String, EpubFile>> _reactionSounds(
    CanvasDocument page, List<CanvasElement> elements) async {
  var ids = <String>{};
  for (var e in elements) {
    var m = e.base.motion;
    for (var c in _reactionClips(e)) {
      var row = m.slots.indexOf(c.id);
      if (row < 0 || !m.isLinked(row)) continue;
      var own =
          e is VideoElement && e.clip.channel.isEmpty ? e.id : "snd-${e.id}";
      if (page.session.at(own, row)?.sound case var s?) ids.add(s.assetId);
    }
  }
  var out = <String, EpubFile>{};
  String? ffmpeg;
  for (var id in ids) {
    var file = await CanvasMedia.existingPath(MediaKind.audio, id);
    if (file == null) continue;
    var ext = path.extension(file).toLowerCase();
    var name = "media/rx-${_safe(path.basenameWithoutExtension(file))}";
    if (ext == ".mp3") {
      out[id] =
          EpubFile("$name.mp3", await File(file).readAsBytes(), "audio/mpeg");
      continue;
    }
    if (ext == ".m4a" || ext == ".aac") {
      out[id] =
          EpubFile("$name.m4a", await File(file).readAsBytes(), "audio/mp4");
      continue;
    }
    ffmpeg ??= await ffmpegPath();
    if (ffmpeg == null) continue;
    var tmp = await Directory.systemTemp.createTemp("epub-sound");
    try {
      var to = path.join(tmp.path, "sound.m4a");
      var run = await Process.run(ffmpeg, [
        "-y",
        "-v",
        "error",
        "-i",
        file,
        "-vn",
        "-c:a",
        "aac",
        "-b:a",
        "160k",
        to
      ]);
      if (run.exitCode == 0) {
        out[id] =
            EpubFile("$name.m4a", await File(to).readAsBytes(), "audio/mp4");
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  }
  return out;
}
