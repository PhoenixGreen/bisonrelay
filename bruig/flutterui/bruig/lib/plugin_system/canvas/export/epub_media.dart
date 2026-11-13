import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:bruig/plugin_system/canvas/export/epub_layers.dart';
import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/web_link.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// epub_media.dart is a page's sound and video, for an interactive EPUB.
//
// What can be laid over the page picture is, as the reader's own <audio> and
// <video>; what cannot is baked:
//
// - A sound, a speaker to press, a plain video -- one with nothing done to
//   its picture -- are the reader's own, driven by media.js with the same
//   playlist, range, repeat and fades as in the editor.
// - A page that moves is laid out as the things on it, each animated by the
//   reader -- see epub_layers.dart. Never as a film of the page.
// - Sound on the page's timeline is mixed into one soundtrack played in step
//   with it; a plain video on the timeline is the reader's own player,
//   placed by the playhead; a keyed one is filmed as itself, alone.
// - A keyed or graded video that is not on the timeline has no way to be
//   drawn by a reader, and stays as its poster, which the page's picture
//   already shows. Put it on the timeline to have it move.
//
// Files are converted by ffmpeg to AAC and H.264. Without it a book has its
// pages, its links and no sound.

/// EpubPageMedia is what one page adds to the book.
class EpubPageMedia {
  final List<EpubMedia> media;
  final List<EpubAction> actions;
  final List<EpubLink> links;
  final List<EpubFile> files;
  final EpubStage? stage;
  final String? soundtrack;

  const EpubPageMedia({
    this.media = const [],
    this.actions = const [],
    this.links = const [],
    this.files = const [],
    this.stage,
    this.soundtrack,
  });
}

/// EpubMediaBuilder builds each page's media for one book, converting each
/// file once.
class EpubMediaBuilder {
  final String? ffmpeg;
  final double scale;
  final CanvasImageSource? images;

  /// _films is how elements are filmed on their own, found once a book.
  Future<ElementFilms?>? _filmsFound;
  Future<ElementFilms?> _films() => _filmsFound ??= ElementFilms.find(ffmpeg);

  /// _files is each file converted so far, by href, so a song under ten
  /// pages is converted once.
  final Map<String, EpubFile?> _files = {};

  /// audioKbps is the bitrate the book's sound is written at, its videos'
  /// soundtracks included.
  final int audioKbps;

  EpubMediaBuilder(this.ffmpeg,
      {this.scale = 1, this.images, this.audioKbps = 160});

  static Future<EpubMediaBuilder> start(
          {double scale = 1,
          CanvasImageSource? images,
          int audioKbps = 160}) async =>
      EpubMediaBuilder(await ffmpegPath(),
          scale: scale, images: images, audioKbps: audioKbps);

  /// page is what page [index] of [document] carries, placed in pixels at
  /// [pixels] per design unit -- the page picture's own scale -- on a page
  /// [width] by [height] pixels.
  Future<EpubPageMedia> page(CanvasDocument document, int index, double pixels,
      {int? width, int? height}) async {
    var scene = document.allScenes[index];
    var master = document.masterScene;
    var elements = [...?master?.elements, ...scene.elements];
    var backdrop = document.backgroundOf(index);

    var media = <EpubMedia>[];
    var links = <EpubLink>[];
    var files = <EpubFile>[];
    var used = <String>{};

    void carry(EpubFile f) {
      if (used.add(f.href)) files.add(f);
    }

    // A page with playhead buttons waits for them, as the canvas does; one
    // without starts by itself.
    var driven = elements.any((e) =>
        e is ButtonElement && e.visible && _playheadAct(e.action.kind) != null);

    // The videos the reader plays itself: in their own layer on a page laid
    // out as layers, so they sit where they sit in the stack.
    var players = {
      if (ffmpeg != null)
        for (var e in elements)
          if (e is VideoElement &&
              !e.isLink &&
              !e.clip.isEmpty &&
              plainVideo(e))
            e.id,
    };

    // A plain background video plays as itself under the page.
    String? backdropVideo;
    var backVideo = document.backgroundOf(index).video;
    if (backVideo != null &&
        !backVideo.clip.isEmpty &&
        !backVideo.isLink &&
        plainVideo(backVideo)) {
      var f =
          await _convert(backVideo.clip.playlist.first.assetId, video: true);
      if (f != null) {
        carry(f);
        backdropVideo = f.href;
      }
    }

    // A video washed over the whole page and blended into it -- the Decred
    // infographic's Rain, screened at a tenth -- is drawn into the page's
    // background as one plain video (Ken, 2026-11-13: the book's rain and
    // sound stuttered, the reader blending a page of video every frame).
    var laid = document;
    if (backdropVideo == null && ffmpeg != null) {
      if (washOf(document, index) case var wash?) {
        var w = width ?? (document.size.size.width * pixels).round();
        var h = height ?? (document.size.size.height * pixels).round();
        var f = await _washed(document, index, wash, pixels, w, h);
        if (f != null) {
          carry(f);
          backdropVideo = f.href;
          laid = document.withScene(
              index,
              scene.copyWith(elements: [
                for (var e in scene.elements)
                  if (e.id != wash.id) e,
              ]));
          elements = [...?master?.elements, ...laid.allScenes[index].elements];
          players.remove(wash.id);
        }
      }
    }

    // The page as its elements, where anything on it moves.
    EpubStage? stage;
    String? soundtrack;
    // A keyed video on the timeline is filmed frame by frame, read the way an
    // export reads it.
    var keyed = elements.any((e) =>
        e is VideoElement && isTimedMedia(e) && !e.isLink && !plainVideo(e));
    var timeline = keyed && ffmpeg != null
        ? ExportMedia.of(_pageAlone(laid, index))
        : null;
    try {
      var size = document.size.size;
      var built = await buildEpubStage(laid, index,
          pixels: pixels,
          width: width ?? (size.width * pixels).round(),
          height: height ?? (size.height * pixels).round(),
          images: images,
          autoplay: !driven,
          films: await _films(),
          media: timeline,
          layered: players,
          timeline: _onTimeline(document, index),
          backdropVideo: backdropVideo);
      if (built != null) {
        stage = built.stage;
        built.files.forEach(carry);
      }
    } finally {
      timeline?.dispose();
    }
    // The sound on its timeline, mixed as an export of it would be, played in
    // step with the playhead.
    if (stage != null && ffmpeg != null) {
      var track = await renderSoundtrack(_pageAlone(document, index));
      if (track != null) {
        var href = "media/page$index-sound.m4a";
        carry(EpubFile(href, track, "audio/mp4"));
        soundtrack = href;
      }
    }
    // A video on the timeline follows the playhead of a page laid out as
    // layers.
    var following = stage != null;

    Future<EpubMedia?> sound(AudioElement e, {bool backdrop = false}) async {
      var clip = e.clip;
      if (clip.isEmpty || clip.timed) return null;
      var sources = <String>[];
      var ranges = <(double, double)>[];
      for (var s in clip.playlist) {
        var f = await _convert(s.assetId, video: false);
        if (f == null) continue;
        carry(f);
        sources.add(f.href);
        ranges.add((s.start, s.end));
      }
      if (sources.isEmpty) return null;
      var box = e.bounds;
      return EpubMedia(
        id: e.id,
        video: false,
        x: box.left * pixels,
        y: box.top * pixels,
        width: backdrop || !e.visible ? 0 : box.width * pixels,
        height: backdrop || !e.visible ? 0 : box.height * pixels,
        sources: sources,
        ranges: ranges,
        loop: clip.loop.name,
        autoplay: clip.autoplay,
        muted: clip.muted,
        volume: clip.volume,
        fadeIn: clip.fadeIn,
        fadeOut: clip.fadeOut,
        pressable: !backdrop && e.visible && e.has(AudioControl.playPause),
        radius:
            math.min(e.box.borderRadius, math.min(box.width, box.height) / 2) *
                pixels,
      );
    }

    Future<EpubMedia?> film_(VideoElement e) async {
      var clip = e.clip;
      if (clip.isEmpty || e.isLink || !plainVideo(e)) return null;
      if (clip.timed && !following) return null;
      var sources = <String>[];
      var ranges = <(double, double)>[];
      for (var s in clip.playlist) {
        var f = await _convert(s.assetId, video: true);
        if (f == null) continue;
        carry(f);
        sources.add(f.href);
        ranges.add((s.start, s.end));
      }
      if (sources.isEmpty) return null;
      String? poster;
      var still = clip.playlist.first.posterId;
      if (still.isNotEmpty) {
        var bytes = await CanvasAssets.load(still);
        if (bytes != null) {
          var f = EpubFile(
              "media/$still", Uint8List.fromList(bytes), _pictureMime(still));
          carry(f);
          poster = f.href;
        }
      }
      var inner = e.look.box.inner(e.bounds);
      // On the playhead it is the playhead's: no controls of its own, and no
      // sound -- that is in the page's soundtrack.
      var timed = clip.timed;
      var controls = !timed &&
          (e.has(VideoControl.playbar) ||
              e.has(VideoControl.time) ||
              e.has(VideoControl.mute) ||
              e.has(VideoControl.volume));
      return EpubMedia(
        id: e.id,
        video: true,
        x: inner.left * pixels,
        y: inner.top * pixels,
        width: inner.width * pixels,
        height: inner.height * pixels,
        rotation: e.rotation,
        sources: sources,
        ranges: ranges,
        loop: clip.loop.name,
        autoplay: clip.autoplay && !timed,
        muted: clip.muted || timed,
        volume: clip.volume,
        fadeIn: clip.fadeIn,
        fadeOut: clip.fadeOut,
        controls: controls,
        // With the reader's own controls a press is theirs; without them, a
        // press on the picture plays it as it did on the canvas.
        pressable: !timed &&
            !controls &&
            (e.has(VideoControl.clickToggle) || e.has(VideoControl.playButton)),
        playButton: !timed && !controls && e.has(VideoControl.playButton),
        poster: poster,
        at: timed ? clip.at : null,
        spans: timed ? [for (var s in clip.playlist) s.span] : const [],
        element: e.id,
        opacity: e.opacity.clamp(0.0, 1.0).toDouble(),
        blend: cssBlend(videoBlend(e) ?? LayerBlend.normal),
        speed: timed ? clip.speed.clamp(0.01, 100.0).toDouble() : 1,
      );
    }

    if (ffmpeg != null) {
      for (var e in elements) {
        switch (e) {
          case AudioElement a:
            if (await sound(a) case var m?) media.add(m);
          case VideoElement v when v.isLink:
            var href = webLink(linkAt(v.link, v.linkStart))?.toString();
            if (href == null) continue;
            var box = v.look.box.inner(v.bounds);
            links.add(EpubLink(
                x: box.left * pixels,
                y: box.top * pixels,
                width: box.width * pixels,
                height: box.height * pixels,
                href: href,
                element: v.id));
          case VideoElement v:
            if (await film_(v) case var m?) media.add(m);
        }
      }
      if (backdrop.sound case var s?) {
        if (await sound(s, backdrop: true) case var m?) media.add(m);
      }
    } else {
      // Links need no ffmpeg.
      for (var e in elements) {
        if (e is VideoElement && e.isLink) {
          var href = webLink(linkAt(e.link, e.linkStart))?.toString();
          if (href == null) continue;
          var box = e.look.box.inner(e.bounds);
          links.add(EpubLink(
              x: box.left * pixels,
              y: box.top * pixels,
              width: box.width * pixels,
              height: box.height * pixels,
              href: href,
              element: e.id));
        }
      }
    }

    // The buttons that play, pause, stop and mute them.
    var targets = {for (var m in media) m.id};
    var actions = <EpubAction>[];
    for (var e in elements) {
      if (e is! ButtonElement || !e.visible) continue;
      var action = e.action;
      if (!action.kind.needsSound || !targets.contains(action.elementId)) {
        continue;
      }
      var box = e.bounds;
      actions.add(EpubAction(
        x: box.left * pixels,
        y: box.top * pixels,
        width: box.width * pixels,
        height: box.height * pixels,
        act: switch (action.kind) {
          ButtonActionKind.playSound => "play",
          ButtonActionKind.pauseSound => "pause",
          ButtonActionKind.stopSound => "stop",
          ButtonActionKind.muteSound => "mute",
          _ => "toggle",
        },
        target: action.elementId,
        element: e.id,
      ));
    }

    // Show or hide, aimed at the layer the element was given for it.
    var layers = {for (var l in stage?.layers ?? const <EpubLayer>[]) l.id};
    for (var e in elements) {
      if (e is! ButtonElement || !e.visible) continue;
      var action = e.action;
      if (action.kind != ButtonActionKind.toggleElement ||
          !layers.contains(action.elementId)) {
        continue;
      }
      var box = e.bounds;
      actions.add(EpubAction(
        x: box.left * pixels,
        y: box.top * pixels,
        width: box.width * pixels,
        height: box.height * pixels,
        act: "showhide",
        target: action.elementId,
        element: e.id,
      ));
    }

    // The playhead's buttons, aimed at the page's layers -- which is where
    // the playhead is in a book.
    if (stage?.animates ?? false) {
      for (var e in elements) {
        if (e is! ButtonElement || !e.visible) continue;
        var action = e.action;
        var act = _playheadAct(action.kind);
        if (act == null) continue;
        var box = e.bounds;
        actions.add(EpubAction(
          x: box.left * pixels,
          y: box.top * pixels,
          width: box.width * pixels,
          height: box.height * pixels,
          act: act,
          target: filmTarget,
          frame: action.frame,
          element: e.id,
        ));
      }
    }

    return EpubPageMedia(
        media: media,
        actions: actions,
        links: links,
        files: files,
        stage: stage,
        soundtrack: soundtrack);
  }

  /// _onTimeline is whether page [index] has sound or video on its timeline.
  bool _onTimeline(CanvasDocument document, int index) {
    var elements = [
      ...?document.masterScene?.elements,
      ...document.allScenes[index].elements,
    ];
    var backdrop = document.backgroundOf(index);
    return elements.any(isTimedMedia) || backdrop.media.any(isTimedMedia);
  }

  /// _pageAlone is page [index] as a document of its own, with its own
  /// backdrop: what the timeline media of that page -- its soundtrack, a keyed
  /// video on it -- are read from, counted from the page's first frame.
  CanvasDocument _pageAlone(CanvasDocument document, int index) {
    var scene = document.allScenes[index];
    var own = document.backgroundOf(index);
    return document
        .goToScene(index)
        .copyWith(onMaster: false, background: own)
        .withScenes([scene.copyWith(background: own)], at: 0);
  }

  /// _convert makes a stored file into one a reader plays, once per book.
  /// _washed is the page's background with [wash] blended over it as its
  /// canvas blends it, as one video once round its loop: see washOf.
  Future<EpubFile?> _washed(CanvasDocument document, int index,
      VideoElement wash, double pixels, int width, int height) async {
    var ffmpeg = this.ffmpeg;
    var blend = videoBlend(wash);
    var mode = blend == null ? null : ffmpegBlend(blend);
    if (ffmpeg == null || mode == null) return null;
    var clip = wash.clip;
    var s = clip.playlist.single;
    var source = await CanvasMedia.existingPath(MediaKind.video, s.assetId);
    var seconds = clip.runLength;
    if (source == null || !(seconds > 0) || !(s.span > 0)) return null;
    var speed = clip.speed > 0.01 ? clip.speed : 1.0;
    var rate = math.max(1, document.frameRate);

    // The background alone, as the page's picture draws it.
    var page = document.goToScene(index).copyWith(
          onMaster: false,
          background: document.backgroundOf(index),
        );
    void draw(ui.Canvas canvas) {
      canvas.scale(pixels);
      paintCanvasDocument(canvas, page,
          part: CanvasPaintPart.backdrop, images: images);
    }

    await drawWhenLoaded(images, draw);
    var recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    var picture = recorder.endRecording();
    var ground = await picture.toImage(width, height);
    picture.dispose();
    var png = await ground.toByteData(format: ui.ImageByteFormat.png);
    ground.dispose();
    if (png == null) return null;

    Directory? work;
    try {
      work = await Directory.systemTemp.createTemp("canvas-epub-wash");
      var under = path.join(work.path, "ground.png");
      await File(under).writeAsBytes(png.buffer.asUint8List());
      var out = path.join(work.path, "wash.mp4");
      // The video as its box shows it (cover), then the page's part of it.
      var b = wash.bounds;
      int even(double v) => math.max(2, (v / 2).round() * 2);
      var bw = even(b.width * pixels), bh = even(b.height * pixels);
      var ox = (-b.left * pixels).round(), oy = (-b.top * pixels).round();
      var w = even(width.toDouble()), h = even(height.toDouble());
      // Written no wider than washWidth: a page of rain at full size is a
      // video too big to play smoothly, and the reader scales it to the
      // page. Drawn at the page's size, then made smaller.
      var shrink = math.min(1.0, washWidth / w);
      var ow = even(w * shrink), oh = even(h * shrink);
      // ffmpeg's normal weighs its first input -- the page -- by the
      // opacity; its other modes mix from the page to the blend by it.
      var o = wash.opacity.clamp(0.0, 1.0).toDouble();
      var opacity = (mode == "normal" ? 1 - o : o).toStringAsFixed(4);
      var run = await Process.run(ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-loop", "1", "-framerate", "$rate", "-i", under,
        "-ss", "${s.start}", "-t", "${s.span}", ...ffmpegInput(source),
        "-filter_complex",
        "[1:v]setpts=(PTS-STARTPTS)/$speed,fps=$rate,"
            "scale=$bw:$bh:force_original_aspect_ratio=increase,"
            "crop=$bw:$bh,crop=$w:$h:$ox:$oy,format=gbrp[top];"
            "[0:v]scale=$w:$h,format=gbrp[bottom];"
            // The page first: ffmpeg mixes by the opacity from its first
            // input to the blend, as the canvas mixes from what is under.
            "[bottom][top]blend=all_mode=$mode:all_opacity=$opacity:"
            "shortest=1,scale=$ow:$oh,format=yuv420p[v]",
        "-map", "[v]", "-t", seconds.toStringAsFixed(3), "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "24",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", out,
      ]);
      if (run.exitCode != 0 || !await File(out).exists()) {
        debugPrint("Unable to draw ${wash.id} into the page: ${run.stderr}");
        return null;
      }
      return EpubFile("media/page$index-wash.mp4",
          await File(out).readAsBytes(), "video/mp4");
    } catch (exception) {
      debugPrint("Unable to draw ${wash.id} into the page: $exception");
      return null;
    } finally {
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<EpubFile?> _convert(String assetId, {required bool video}) async {
    var stem = path.basenameWithoutExtension(assetId);
    var href = video ? "media/$stem.mp4" : "media/$stem.m4a";
    if (_files.containsKey(href)) return _files[href];
    var ffmpeg = this.ffmpeg;
    if (ffmpeg == null) return _files[href] = null;
    var source = await CanvasMedia.existingPath(
        video ? MediaKind.video : MediaKind.audio, assetId);
    if (source == null) return _files[href] = null;
    Directory? work;
    try {
      work = await Directory.systemTemp.createTemp("canvas-epub");
      var out = path.join(work.path, video ? "out.mp4" : "out.m4a");
      var run = await Process.run(ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        ...ffmpegInput(source),
        if (video) ...[
          "-vf",
          "scale='min(1280,iw)':-2",
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "26",
          "-pix_fmt",
          "yuv420p",
          "-c:a",
          "aac",
          "-b:a",
          "${audioKbps}k",
        ] else ...[
          "-vn",
          "-c:a",
          "aac",
          "-b:a",
          "${audioKbps}k",
        ],
        "-movflags", "+faststart",
        out,
      ]);
      if (run.exitCode != 0 || !await File(out).exists()) {
        debugPrint("Unable to convert $assetId for the book: ${run.stderr}");
        return _files[href] = null;
      }
      return _files[href] = EpubFile(href, await File(out).readAsBytes(),
          video ? "video/mp4" : "audio/mp4");
    } catch (exception) {
      debugPrint("Unable to convert $assetId for the book: $exception");
      return _files[href] = null;
    } finally {
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// _playheadAct is what a button that moves the playhead is called in the
/// page's script, or null for one that does something else.
String? _playheadAct(ButtonActionKind kind) => switch (kind) {
      ButtonActionKind.play => "play",
      ButtonActionKind.pause => "pause",
      ButtonActionKind.togglePlay => "toggle",
      ButtonActionKind.restart => "restart",
      ButtonActionKind.goToFrame => "goto",
      ButtonActionKind.playFrom => "playfrom",
      ButtonActionKind.playToFrame => "playto",
      _ => null,
    };

/// cssBlend is [b] as CSS's mix-blend-mode, or null for normal.
String? cssBlend(LayerBlend b) => switch (b) {
      LayerBlend.normal => null,
      LayerBlend.add => "plus-lighter",
      LayerBlend.colorBurn => "color-burn",
      LayerBlend.colorDodge => "color-dodge",
      LayerBlend.softLight => "soft-light",
      LayerBlend.hardLight => "hard-light",
      LayerBlend.colour => "color",
      _ => b.name,
    };

/// plainVideo is whether a reader's own `<video>` can show [e] as the canvas
/// does: nothing keyed, cut, cropped, filtered, tinted or outlined -- only
/// fitted to its box, which CSS can do.
/// washWidth is the widest a page's baked background video is written:
/// see EpubMediaBuilder._washed.
const int washWidth = 1280;

/// washOf is the video washed over the whole of page [index] and blended
/// into it, that a book draws into the page's background (see
/// EpubMediaBuilder._washed): the lowest thing on the page, covering it,
/// still, going round from the page's start, blended in a way ffmpeg can --
/// or null.
VideoElement? washOf(CanvasDocument document, int index) {
  var master = document.masterScene?.elements ?? const <CanvasElement>[];
  var elements = document.allScenes[index].elements;
  if (master.isNotEmpty || elements.isEmpty) return null;
  if (elements.first case VideoElement e
      when e.visible &&
          !e.isLink &&
          plainVideo(e) &&
          e.clip.playlist.length == 1 &&
          e.clip.loop != MediaLoop.none &&
          (e.clip.timed ? e.clip.at <= 0 : e.clip.autoplay) &&
          videoBlend(e) != null &&
          (videoBlend(e) != LayerBlend.normal || e.opacity < 1) &&
          ffmpegBlend(videoBlend(e)!) != null &&
          e.rotation == 0 &&
          e.base.skewX == 0 &&
          e.base.skewY == 0 &&
          (e.base.track?.isEmpty ?? true) &&
          !e.base.motion.moves &&
          e.base.motion.looks.isEmpty &&
          e.bounds.inflate(0.5).contains(Offset.zero) &&
          e.bounds
              .inflate(0.5)
              .contains(document.size.size.bottomRight(Offset.zero))) {
    return e;
  }
  return null;
}

/// videoBlend is how a video is laid on the page: its Output's blend, else
/// its own -- the canvas lays on both, one inside the other -- or null where
/// they differ, which a single blend cannot say.
LayerBlend? videoBlend(VideoElement e) {
  var outer = e.base.blend, own = e.blend;
  if (outer == LayerBlend.normal) return own;
  if (own == LayerBlend.normal || own == outer) return outer;
  return null;
}

/// ffmpegBlend is [b] as ffmpeg's blend filter calls it, or null for one
/// it cannot do as the canvas does: only those the same whichever is on
/// top, since ffmpeg's and the canvas's ideas of top and bottom differ for
/// the others (dodge, burn, overlay, soft and hard light).
String? ffmpegBlend(LayerBlend b) => switch (b) {
      LayerBlend.normal => "normal",
      LayerBlend.darken => "darken",
      LayerBlend.multiply => "multiply",
      LayerBlend.lighten => "lighten",
      LayerBlend.screen => "screen",
      LayerBlend.add => "addition",
      LayerBlend.difference => "difference",
      LayerBlend.exclusion => "exclusion",
      _ => null,
    };

bool plainVideo(VideoElement e) {
  var l = e.look;
  return !e.key.on &&
      l.frame == null &&
      l.filter == ImageFilterPreset.none &&
      l.blend == OverlayBlend.none &&
      l.tint.a == 0 &&
      l.saturation == 1 &&
      l.brightness == 1 &&
      l.crop.isWhole &&
      l.framing.isDefault &&
      !l.outline.on &&
      l.fit == ImageFit.cover;
}

String _pictureMime(String id) => switch (path.extension(id)) {
      ".jpg" || ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".webp" => "image/webp",
      ".svg" => "image/svg+xml",
      _ => "image/png",
    };
