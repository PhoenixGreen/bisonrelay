import 'dart:io';

import 'package:bruig/plugin_system/canvas/export/epub_writer.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// epub_media.dart is a page's sound and video, for an interactive EPUB.
//
// A page of an EPUB is its picture with things laid over it, so what can be
// laid over is laid over, as the reader's own <audio> and <video>, and what
// cannot is baked:
//
// - A sound, a speaker to press, a plain video -- one with nothing done to
//   its picture -- are the reader's own, driven by media.js with the same
//   playlist, range, repeat and fades as in the editor.
// - Anything on the page's timeline, and a background video, cannot be laid
//   over a flat picture: a background has to be *behind* the page's
//   elements, and a timeline plays with everything else on it. So the page
//   is filmed -- rendered as an MP4 with its sound by the video exporter,
//   which is to say exactly as it plays in the editor, keyed, graded and
//   mixed -- and the film shown in place of the picture.
// - A keyed or graded video that is not on the timeline has no film to go in
//   and no way to be drawn by a reader, and stays as its poster, which the
//   page's picture already shows. Put it on the timeline to have it move.
//
// Files are converted to what readers play -- AAC for sound, H.264 for video
// -- which is ffmpeg's job. Without it a book has its pages, its links and no
// sound.

/// EpubPageMedia is what one page adds to the book.
class EpubPageMedia {
  final List<EpubMedia> media;
  final List<EpubAction> actions;
  final List<EpubLink> links;
  final List<EpubFile> files;
  final String? film;

  const EpubPageMedia({
    this.media = const [],
    this.actions = const [],
    this.links = const [],
    this.files = const [],
    this.film,
  });
}

class EpubMediaBuilder {
  final String? ffmpeg;
  final double scale;
  final CanvasImageSource? images;

  /// _files is each file converted so far, by href, so a song under ten
  /// pages is converted once.
  final Map<String, EpubFile?> _files = {};

  EpubMediaBuilder(this.ffmpeg, {this.scale = 1, this.images});

  static Future<EpubMediaBuilder> start(
          {double scale = 1, CanvasImageSource? images}) async =>
      EpubMediaBuilder(await ffmpegPath(), scale: scale, images: images);

  /// page is what page [index] of [document] carries, placed in pixels at
  /// [pixels] per design unit -- the page picture's own scale.
  Future<EpubPageMedia> page(
      CanvasDocument document, int index, double pixels) async {
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

    // The film, where the page has anything to film.
    String? film;
    if (ffmpeg != null) {
      var shot = _filmable(document, index);
      if (shot != null && ExportMedia.of(shot) != null) {
        var export = await renderVideo(shot, scale: scale, images: images);
        if (export != null) {
          var href = "media/page$index.mp4";
          carry(EpubFile(href, export.data, "video/mp4"));
          film = href;
        }
      }
    }

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
      );
    }

    Future<EpubMedia?> film_(VideoElement e) async {
      var clip = e.clip;
      if (clip.isEmpty || clip.timed || e.isLink || !plainVideo(e)) {
        return null;
      }
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
      var controls = e.has(VideoControl.playbar) ||
          e.has(VideoControl.time) ||
          e.has(VideoControl.mute) ||
          e.has(VideoControl.volume);
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
        autoplay: clip.autoplay,
        muted: clip.muted,
        volume: clip.volume,
        fadeIn: clip.fadeIn,
        fadeOut: clip.fadeOut,
        controls: controls,
        // With the reader's own controls a press is theirs; without them, a
        // press on the picture plays it as it did on the canvas.
        pressable: !controls &&
            (e.has(VideoControl.clickToggle) || e.has(VideoControl.playButton)),
        poster: poster,
      );
    }

    if (ffmpeg != null) {
      for (var e in elements) {
        switch (e) {
          case AudioElement a:
            if (await sound(a) case var m?) media.add(m);
          case VideoElement v when v.isLink:
            var box = v.look.box.inner(v.bounds);
            links.add(EpubLink(
                x: box.left * pixels,
                y: box.top * pixels,
                width: box.width * pixels,
                height: box.height * pixels,
                href: linkAt(v.link, v.linkStart)));
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
          var box = e.look.box.inner(e.bounds);
          links.add(EpubLink(
              x: box.left * pixels,
              y: box.top * pixels,
              width: box.width * pixels,
              height: box.height * pixels,
              href: linkAt(e.link, e.linkStart)));
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
      ));
    }

    return EpubPageMedia(
        media: media, actions: actions, links: links, files: files, film: film);
  }

  /// _filmable is page [index] alone, as a document to film -- or null when
  /// there is nothing on it that moves with a timeline. A background video
  /// that is not on the timeline is put on it from the start, since the only
  /// way to have it behind the page is in the film.
  CanvasDocument? _filmable(CanvasDocument document, int index) {
    var scene = document.allScenes[index];
    var backdrop = document.backgroundOf(index);
    var video = backdrop.video;
    var own = backdrop;
    if (video != null && !video.clip.isEmpty && !video.clip.timed) {
      own = backdrop.copyWith(
          video: video.copyWith(clip: video.clip.copyWith(timed: true, at: 0)));
    }
    var one = document
        .goToScene(index)
        .copyWith(onMaster: false, background: own)
        .withScenes([scene.copyWith(background: own)], at: 0);
    // A master's backdrop covers the page's own; with it being filmed here,
    // the master's copy has to be the one given the timeline.
    var master = document.master;
    if (master != null &&
        master.sharedBackground != null &&
        !identical(master.sharedBackground, own)) {
      one = one.withMaster(master.copyWith(background: own));
    }
    return ExportMedia.of(one) == null ? null : one;
  }

  /// _convert makes a stored file into one a reader plays, once per book.
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
        "-i", source,
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
          "128k",
        ] else ...[
          "-vn",
          "-c:a",
          "aac",
          "-b:a",
          "160k",
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

/// plainVideo is whether a reader's own <video> can show [e] as the canvas
/// does: nothing keyed, cut, cropped, filtered, tinted or outlined -- only
/// fitted to its box, which CSS can do.
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
