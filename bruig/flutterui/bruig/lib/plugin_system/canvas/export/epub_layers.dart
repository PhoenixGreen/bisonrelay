import 'package:bruig/plugin_system/canvas/render/code_html.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart'
    show codeBoxes;
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart'
    show codeRunBoxes;
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
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
import 'package:crypto/crypto.dart' show sha1;

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

part 'epub_layers_maker.dart';
part 'epub_layers_keys.dart';
part 'epub_layers_sheets.dart';
part 'epub_layers_changes.dart';
part 'epub_layers_interactive.dart';

// epub_layers.dart lays a page of an interactive EPUB out as the things on
// it, each animated by the reader as on the canvas. What does not move is
// drawn once; each element that moves is a layer: its picture, moved by CSS
// keyframes sampled a frame at a time (pose from its clips and keyframes,
// arrival and leaving read off the renderer, see motionProbe), or, where
// CSS cannot do it, a short video of that element alone.

/// EpubSprite is one picture: where it goes on the page, in pixels,
/// and where it is on its sheet.
class EpubSprite {
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

/// EpubKey is what CSS says about something at one frame.
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

/// EpubClip is an element's change as a video of it alone: [href], from
/// frame [at] for [frames], over [rect], with [before] and [after] it.
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

/// EpubReaction is a clip an element plays when [on] happens
/// (`click:<element>` or `end:<clip>`): keyframes over its [frames], with
/// its row's linked sound, played over the element's timeline place.
class EpubReaction {
  /// clip is its id, which a reaction that follows it names in [on].
  final String clip;
  final String on;
  final int frames;
  final List<EpubKey> keys;

  /// sound is its linked sound's file in the book; volume how loud.
  final String? sound;
  final double volume;

  const EpubReaction(this.clip, this.on, this.frames, this.keys,
      {this.sound, this.volume = 1});
}

/// EpubControl is a layer button the page's clock answers (a Sheet music
/// playbar's): [act] the ask, [rect] its place in page pixels, [data] its
/// frames or span, [inner] what is drawn in it while playing.
class EpubControl {
  final String act;
  final Rect rect;
  final Map<String, String> data;
  final String inner;
  final String label;
  const EpubControl(this.act, this.rect,
      {this.data = const {}, this.inner = "", this.label = ""});
}

/// EpubKeyboard is an instrument a reader plays by pointer, keyboard or
/// MIDI: its place, its keys (number, box, black, lit picture), and every
/// key's sound from [low], [step] seconds apart, in one file.
class EpubKeyboard {
  final Rect box;
  final List<({int key, Rect rect, bool black, EpubSprite lit})> keys;
  final String sound;
  final int low;
  final double step;
  const EpubKeyboard(this.box, this.keys, this.sound, this.low, this.step);
}

/// EpubLayer is one element that moves, shows and hides, or hovers.
class EpubLayer {
  /// id is the element's, which a Show-or-hide button names.
  final String id;

  /// visible is whether it is showing when the page opens.
  final bool visible;

  /// originX and originY are the element's anchor in page pixels: what its
  /// pose turns and grows it about.
  final double originX;
  final double originY;

  /// pose is where the element is, moved, turned, grown and faded, as
  /// keyframes; empty where it stays where it was put.
  final List<EpubKey> pose;

  /// parts are its pictures and how each moves; clip a video of it.
  final List<EpubPart> parts;
  final EpubClip? clip;

  /// hover is the button as it is under the pointer, and hoverBox where it
  /// can be pointed at, in page pixels. Null where pointing changes nothing.
  final EpubSprite? hover;
  final Rect? hoverBox;

  /// legend is where a chart's key has a series to switch on and off, in
  /// page pixels, each with the bit it flips; switched is the chart with
  /// each set of those bits flipped, by mask. See _LayerMaker._legend.
  final List<(int, Rect)> legend;
  final Map<int, EpubSprite> switched;

  /// reactions are the clips it plays on a click or after another clip.
  final List<EpubReaction> reactions;

  /// controls are the buttons on it that the page's clock answers.
  final List<EpubControl> controls;

  /// keyboard is it as an instrument the reader plays, where it is one.
  final EpubKeyboard? keyboard;

  /// frames are pages over it, in frames of their own in the book: a Run
  /// panel's web page, run live; a Code panel's files, to be scrolled.
  final List<EpubFrame> frames;

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
    this.frames = const [],
  });

  /// moves is whether anything on it changes with the playhead.
  bool get moves =>
      pose.length > 1 ||
      clip != null ||
      parts.any((p) => p.keys.length > 1 || p.clipKeys.length > 1);
}

/// EpubSlab is a flattened stretch of the page that does not move: the
/// backdrop and what is over it below the first mover, or between two.
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

  /// autoplay is whether the page starts itself: not with playhead buttons.
  final bool autoplay;

  /// timeline is whether sound or video follows its playhead.
  final bool timeline;

  /// backdropVideo is the page's background video, looped over the backdrop
  /// and under everything; null where there is none a reader can show.
  final String? backdropVideo;

  /// clickable are the elements a click on starts a reaction, and where.
  final List<(String, Rect)> clickable;

  /// sounds are the reactions' sound files, each once.
  final List<String> sounds;

  /// camera is how the page's Camera frames it, frame by frame where it
  /// moves, as a transform on the whole stage; empty for none. See cameraKeys.
  final List<EpubKey> camera;

  /// lens is what the Camera's lens does to each layer by depth (blur,
  /// parallax), as keys on a wrapper round it, by layer id. See lensKeys.
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

  /// alpha is whether clear-backed HEVC can be made (VideoToolbox's): else
  /// an element is filmed over what is under it, exact only if that is still.
  final bool alpha;

  const ElementFilms(this.ffmpeg, {this.alpha = false});

  /// find is the system ffmpeg's, or null without one.
  static Future<ElementFilms?> find(String? ffmpeg) async {
    if (ffmpeg == null) return null;
    Directory? work;
    try {
      // Tried, not asked about: a listed encoder may still not open.
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

/// buildEpubStage lays page [index] out as layers, [pixels] page pixels a
/// design unit on a [width] by [height] page; null where nothing moves,
/// shows, hides or hovers, so its picture is enough.
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

  /// media is the page's timeline media, for a keyed video on it, which is
  /// filmed as itself, keyed, frame by frame.
  ExportMedia? media,

  /// layered are elements to give a layer whether or not they move: a video
  /// the reader plays, which needs its own place in the stack.
  Set<String> layered = const {},
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

  // Shown and hidden by a button on the page: a layer even when still, so
  // there is something to show and hide.
  var toggled = {
    for (var e in elements)
      if (e is ButtonElement &&
          e.visible &&
          e.action.kind == ButtonActionKind.toggleElement)
        e.action.elementId,
  };

  // Buttons that change under the pointer: a layer each, and its look.
  var hovering = {
    for (var e in elements)
      if (e is ButtonElement && e.visible && _hovers(e)) e.id,
  };

  // Lines that only carry text and asked to stay out of the picture.
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

  // What plays a clip on a click or after a clip: a layer each.
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
  codeRunSpans(page);
  var moving = <String>{};
  var changing = <String>{};
  for (var e in drawn) {
    // A Run panel whose page runs live in the book: a layer of its own.
    if (_liveFrames(e, page, pixels).isNotEmpty) moving.add(e.id);
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

  // The still elements since the last mover, as one picture. The first
  // carries the backdrop and facing overhang; with a background video
  // the backdrop is a slab apart, so the video goes between.
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

    // Its pictures read: a vector not yet loaded is a dashed box.
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
            frames: l.frames,
          ),
        _ => item,
      },
  ];

  // A score sheet's playbar plays the page, not the start screen's.
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

class _BackdropVideo {
  const _BackdropVideo();
}

/// isBackdropVideo is whether a stage item is the background video's place.
bool isBackdropVideo(Object item) => item is _BackdropVideo;

String _safe(String id) => id.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_");

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

/// isTimedMedia is whether [e] is a sound or a video on the timeline.
bool isTimedMedia(CanvasElement e) => switch (e) {
      AudioElement a => a.clip.timed && !a.clip.isEmpty,
      VideoElement v => v.clip.timed && !v.clip.isEmpty,
      _ => false,
    };
