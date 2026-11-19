import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/share_settings.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/audio_export.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart' show loudnessOptions, loudnessTargets;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/document_export.dart';
import 'package:bruig/plugin_system/canvas/export/epub_check.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/export/publish_record.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/export/panel_video.dart';
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart'
    show hasPanels, panelSteps;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// publish_sheet.dart is the Publish dialog: what to make and where to send
// it, in one sheet because the two depend on each other (a 2400px GIF is not
// going into a chat). Everything is an estimate until Publish is pressed:
// rendering a 200-frame GIF to measure it takes as long as publishing it.

/// PublishAs is what to make, in order of how much of the canvas survives.
/// The canvas itself is last because only it needs Bison Relay at the other
/// end; an image can be shown to anyone.
enum PublishAs {
  image("Image", "A single frame as a PNG, a JPEG or a PDF"),
  animation("Animation", "Every frame as an animated GIF"),
  video("Video", "Every frame as an MP4 or a WebM, at full colour"),
  // The timeline mixed as a video's soundtrack is: audio_export.dart.
  audio("Audio", "The sound alone, mixed: a WAV, FLAC, MP3, AAC or Opus file"),
  // Every canvas a page, in order. See document_export.dart.
  document("Document", "Every page as a PDF or an EPUB, to read and to print"),
  interactive(
      "Interactive canvas",
      "The canvas itself, with its pictures, sounds and videos, to open, "
          "play and edit again");

  final String label;
  final String description;
  const PublishAs(this.label, this.description);
}

/// PublishScenes is how much of a several-canvas document goes.
enum PublishScenes {
  all("All scenes", "The whole document, in order"),
  one("One scene", "Just the one, as if it were the whole document"),
  range("A range", "From one scene to another, in order");

  final String label;
  final String description;
  const PublishScenes(this.label, this.description);
}

/// PublishTo is where it goes: a file, or three things a file cannot do (a
/// canvas in a chat, one a post can embed, one fetched from Files). Disk is
/// first because it always works; the others each need something set up.
enum PublishTo {
  file("Save to a file", Icons.download_outlined),
  chat("Send to a chat", Icons.chat_outlined),
  library("Add to the post library", Icons.menu_book_outlined),
  shared("Share in Files", Icons.folder_shared_outlined);

  final String label;
  final IconData icon;
  const PublishTo(this.label, this.icon);
}

/// showPublishSheet opens the dialog for [document]. [folder] and [name] are
/// where it is saved and what the publish record is keyed on: an unsaved
/// canvas can be published but not updated afterwards, and the sheet says so.
Future<void> showPublishSheet(
  BuildContext context, {
  required CanvasDocument document,
  required CanvasImageSource? images,
  required int frame,
  String? folder,
  String? name,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _PublishSheet(
        document: document,
        images: images,
        frame: frame,
        folder: folder,
        name: name,
      ),
    );

class _PublishSheet extends StatefulWidget {
  final CanvasDocument document;
  final CanvasImageSource? images;
  final int frame;
  final String? folder;
  final String? name;

  const _PublishSheet({
    required this.document,
    required this.images,
    required this.frame,
    required this.folder,
    required this.name,
  });

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  PublishAs _as = PublishAs.image;

  /// _documentAs is which sort of document, when Document is being made.
  DocumentAs _documentAs = DocumentAs.pdf;

  /// _profile is the store an EPUB is made for (StoreProfile), which also
  /// decides whether it is the interactive one.
  StoreProfile _profile = StoreProfile.direct;
  PublishTo _to = PublishTo.file;

  // The still settings, then the animation's, kept side by side so
  // switching between Image and Animation and back finds both as left.
  EmbedFormat _format = EmbedFormat.png;
  int _quality = 85;
  double _scale = 1;

  /// _pdf is whether the still is a page rather than a picture, on [_paper].
  /// A flag rather than a fourth EmbedFormat, which lists what a picture
  /// attached to a post may be.
  bool _pdf = false;
  PdfPaper _paper = PdfPaper.canvas;
  PdfOrientation _orientation = PdfOrientation.auto;

  /// _everyShape is whether to publish at every shape the canvas is designed
  /// for, not only the one on screen. For a file and a chat only: the library
  /// and Files keep one record per canvas. See CanvasDocument.targets.
  bool _everyShape = false;

  /// _spreads lays a book of pages out two to a spread when the reader is
  /// turned on its side (renderDocument's spreads).
  bool _spreads = true;

  /// _panelVideo makes a video of a comic read panel by panel, at
  /// [_panelPace] (renderVideo's panels).
  bool _panelVideo = false;
  PanelPace _panelPace = PanelPace.steady;

  /// _panelMusic lays the canvas's sound under a panel video, looped.
  bool _panelMusic = false;

  bool _dither = true;

  /// _toTarget brings a video's sound to the master's loudness target: a
  /// publish setting rather than the mixer's, being about the file made.
  late bool _toTarget = widget.document.masterMix.normalise;

  /// _target is the loudness it is brought to, starting from the mixer's.
  late double _target = widget.document.masterMix.target;

  /// _sound is how sound is written, from the document's own
  /// AudioSettings.export, not another canvas's last publish.
  late AudioOptions _sound = widget.document.audio.export;

  bool get _needsFfmpeg => _as == PublishAs.video || _as == PublishAs.audio;
  int _colors = 256;
  bool _loop = true;

  VideoFormat _videoFormat = VideoFormat.mp4;
  VideoQuality _videoQuality = VideoQuality.balanced;

  /// _ffmpeg is whether an encoder was found. Assumed absent until the look
  /// comes back, so the sheet never offers something and then withdraws it.
  bool _ffmpeg = false;

  /// _epubcheck is whether EPUBCheck was found (epub_check.dart): a book is
  /// checked by it before it goes anywhere, as Apple checks every book.
  bool _epubcheck = true;

  /// _scenes is how much of a document with several canvases is published,
  /// and _first and _last which ones, counting from one. _last is kept while
  /// a single scene is chosen, so a range comes back as it was.
  PublishScenes _scenes = PublishScenes.all;
  late int _first = widget.document.at;
  late int _last = widget.document.at;

  ChatModel? _chat;
  String _caption = "";

  /// _document is what is published: the whole thing or the chosen scenes,
  /// as a trimmed document, which the GIF, video, PDF, estimate and bundle
  /// all handle without being handed a range.
  CanvasDocument get _document {
    var mix = widget.document.masterMix;
    var document = mix.normalise == _toTarget && mix.target == _target
        ? widget.document
        : widget.document.copyWith(
            masterMix: mix.copyWith(normalise: _toTarget, target: _target));
    return _chosen(document);
  }

  CanvasDocument _chosen(CanvasDocument document) {
    if (!document.hasScenes) return document;
    // A still is one canvas, whichever is chosen.
    if (_onePicture) return document.scenesFrom(_first, _first);
    return switch (_scenes) {
      PublishScenes.all => document,
      PublishScenes.one => document.scenesFrom(_first, _first),
      PublishScenes.range =>
        document.scenesFrom(_first, math.max(_first, _last)),
    };
  }

  /// _runNote is how long what is about to be published runs for.
  String _runNote() {
    var frames = _document.playFrames;
    var rate = _document.frameRate <= 0 ? 1 : _document.frameRate;
    return "$frames frame${frames == 1 ? "" : "s"} at $rate per second — "
        "${(frames / rate).toStringAsFixed(1)} seconds.";
  }

  /// _onePicture is whether what is made is one canvas (PNG or JPEG), which
  /// asks "which one", not "how many".
  bool get _onePicture => _as == PublishAs.image && !_pdf;

  /// _frame is the frame taken: the one being looked at, where it is in the
  /// published document, moved into a trimmed scene's own count.
  int get _frame {
    var document = widget.document;
    if (!document.hasScenes || _scenes == PublishScenes.all && !_onePicture) {
      return widget.frame;
    }
    var from = document.startOfScene(_first);
    var into = widget.frame - from;
    return into >= 0 && into < _document.playFrames ? into : 0;
  }

  /// _record is what this canvas published before: Update and Unpublish.
  PublishRecord _record = const PublishRecord();

  /// _share is the terms it is shared in Files on: set before it is shared,
  /// and read back from the share itself once it is, so a change made on
  /// the Shared page is what the sheet shows. _shareLoaded rebuilds the
  /// fields when those arrive.
  ShareSettings? _share;
  int _shareLoaded = 0;

  /// _busy disables every control while a render runs.
  bool _busy = false;
  String _progress = "";

  /// _canRecord is whether [_record] has a folder and name to be filed by.
  bool get _canRecord => widget.name != null;

  @override
  void initState() {
    super.initState();
    // As last published, and Image the first time: a GIF is the most
    // expensive thing this sheet makes, and should not be the first default.
    _restore();
    _loadRecord();
    _measurePictures();
    // Asked once here, not in build: it launches a process, and build runs
    // on every keystroke in the caption field.
    ffmpegPath().then((found) {
      if (mounted) setState(() => _ffmpeg = found != null);
    });
    epubcheckPath().then((found) {
      if (mounted) setState(() => _epubcheck = found != null);
    });
  }

  /// _goOnDespite shows what the check found wrong with the book and asks
  /// whether to publish it all the same.
  Future<bool> _goOnDespite(EpubCheckReport report) async {
    var shown = report.errors.take(8).toList();
    var more = report.errors.length - shown.length;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(report.byEpubcheck
                ? "EPUBCheck found problems"
                : "The book has problems"),
            content: SingleChildScrollView(
              child: Text([
                "A store would refuse it as it is:",
                for (var e in shown) "• $e",
                if (more > 0) "…and $more more.",
              ].join("\n")),
            ),
            actions: [
              TextButton(
                  key: const ValueKey("epubCheckStop"),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Don't publish")),
              TextButton(
                  key: const ValueKey("epubCheckGoOn"),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Publish anyway")),
            ],
          ),
        ) ??
        false;
  }

  /// _prefs is where settings are remembered; null on its own, as in a test.
  CanvasPreferences? get _prefs {
    try {
      return Provider.of<CanvasPreferences>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  /// _settings is how the sheet is set, as remembered: not the scenes, chat
  /// or caption, which belong to the canvas and the moment.
  Map<String, dynamic> get _settings => {
        "as": _as.name,
        "document": _documentAs.name,
        "profile": _profile.name,
        "to": _to.name,
        "format": _format.name,
        "quality": _quality,
        "scale": _scale,
        "pdf": _pdf,
        "paper": _paper.name,
        "orientation": _orientation.name,
        "everyShape": _everyShape,
        "spreads": _spreads,
        "panelVideo": _panelVideo,
        "panelPace": _panelPace.name,
        "panelMusic": _panelMusic,
        "dither": _dither,
        "colors": _colors,
        "loop": _loop,
        "videoFormat": _videoFormat.name,
        "videoQuality": _videoQuality.name,
        "toTarget": _toTarget,
        "target": _target,
        "sound": _sound.toJson(),
      };

  /// _panelNote is how long a panel-by-panel video runs.
  String _panelNote() {
    var steps = panelSteps(widget.document);
    var rate = widget.document.frameRate >= 12 ? widget.document.frameRate : 24;
    var seconds = PanelTimeline(steps, rate, _panelPace).frames / rate;
    var panels = steps.where((s) => !s.whole).length;
    return "$panels panels on ${widget.document.allScenes.length} pages, "
        "${seconds.round()} seconds.";
  }

  /// _restore sets the sheet as last published with. Anything unrecognised
  /// -- a renamed setting, a value out of range -- keeps the default.
  void _restore() {
    var saved = _prefs?.publish ?? const {};
    if (saved.isEmpty) return;
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.firstWhere((v) => v.name == saved[key], orElse: () => fallback);
    bool flag(String key, bool fallback) =>
        saved[key] is bool ? saved[key] as bool : fallback;
    num number(String key, num fallback) =>
        saved[key] is num ? saved[key] as num : fallback;
    _as = pick(PublishAs.values, "as", _as);
    _documentAs = pick(DocumentAs.values, "document", _documentAs);
    // Saved before there were stores to choose: a plain book for the
    // stores that read pictures, an interactive one sold directly.
    _profile = pick(StoreProfile.values, "profile",
        _documentAs == DocumentAs.epub ? StoreProfile.plain : _profile);
    if (_documentAs != DocumentAs.pdf) _documentAs = _profile.document;
    _to = pick(PublishTo.values, "to", _to);
    _format = pick(EmbedFormat.values, "format", _format);
    _quality = number("quality", _quality).toInt().clamp(1, 100);
    _scale = number("scale", _scale).toDouble().clamp(0.05, maxExportScale);
    _pdf = flag("pdf", _pdf);
    _paper = pick(PdfPaper.values, "paper", _paper);
    _orientation = pick(PdfOrientation.values, "orientation", _orientation);
    _everyShape = flag("everyShape", _everyShape);
    _spreads = flag("spreads", _spreads);
    _panelVideo = flag("panelVideo", _panelVideo);
    _panelPace = pick(PanelPace.values, "panelPace", _panelPace);
    _panelMusic = flag("panelMusic", _panelMusic);
    _dither = flag("dither", _dither);
    _colors = number("colors", _colors).toInt().clamp(2, 256);
    _loop = flag("loop", _loop);
    _videoFormat = pick(VideoFormat.values, "videoFormat", _videoFormat);
    _videoQuality = pick(VideoQuality.values, "videoQuality", _videoQuality);
    _toTarget = flag("toTarget", _toTarget);
    var target = number("target", _target).toDouble();
    if (loudnessTargets.any((t) => t.$1 == target)) _target = target;
  }

  /// _loadRecord reads what this canvas published before. Not awaited by
  /// initState: the button turning to Update a moment later is better than
  /// the dialog appearing late.
  Future<void> _loadRecord() async {
    if (!_canRecord) return;
    var record = await PublishRecords.read(widget.folder ?? "", widget.name!);
    if (mounted && record != null) setState(() => _record = record);
    if (record == null || !record.hasShare) return;
    try {
      var shared = await sharedFileNamed(record.sharedPath);
      if (!mounted || shared == null) return;
      setState(() {
        _share = ShareSettings.of(shared);
        _shareLoaded++;
      });
    } catch (exception) {
      // Not shared after all, or the client is not up: the fields start
      // from the defaults.
    }
  }

  /// _shareTerms is what the fields say, the description defaulting to
  /// the canvas's name.
  ShareSettings get _shareTerms =>
      _share ?? ShareSettings(description: _suggestedName);

  /// _suggestedName is the saved name, else the title, else a word.
  String get _suggestedName =>
      widget.name ??
      (widget.document.title.isEmpty ? "Canvas" : widget.document.title);

  int get _estimate => switch (_as) {
        // A PDF is the same frame with a page round it, deflated rather than
        // PNG-compressed: close enough to the same size.
        PublishAs.image => estimateStillBytes(_document, scale: _scale),
        PublishAs.animation => estimateAnimationBytes(_document, scale: _scale),
        PublishAs.video => estimateVideoBytes(_document,
            scale: _scale, format: _videoFormat, quality: _videoQuality),
        PublishAs.audio => estimateAudioBytes(_document, _sound),
        PublishAs.document => estimateDocumentBytes(_document, scale: _scale),
        // Exact, as an interactive canvas is the document itself; its
        // pictures and media go in at stored size, already compressed.
        PublishAs.interactive => _document.encode().length + _pictureBytes,
      };

  /// _pictureBytes is what the canvas's pictures weigh, nearly all of a
  /// bundle: measured once as the sheet opens, as each must be read.
  int _pictureBytes = 0;

  Future<void> _measurePictures() async {
    var total = 0;
    for (var id in _document.assetIds) {
      total += (await CanvasAssets.load(id))?.length ?? 0;
    }
    // And its sounds and videos, which a bundle carries too.
    for (var id in _document.mediaIds) {
      var file = await CanvasMedia.existingPath(CanvasMedia.kindOf(id), id);
      if (file == null) continue;
      // Gone since it was found (removed in another window, say): it adds
      // nothing, rather than leaving the estimate unshown.
      try {
        total += await File(file).length();
      } on FileSystemException {
        continue;
      }
    }
    if (mounted) setState(() => _pictureBytes = total);
  }

  /// _tooBigForChat is the one warning before rendering: the one failure
  /// that would otherwise come after a long wait.
  bool get _tooBigForChat {
    if (_to != PublishTo.chat) return false;
    // Base64 is four bytes of text per three of data, plus the markup.
    return _estimate * 4 / 3 > 900000;
  }

  /// _render makes the bytes, the only slow thing here. Both raster paths go
  /// through export/canvas_export.dart, as the embed and thumbnail do, so
  /// what is published is what the canvas draws. Only the GIF reports
  /// progress: a still is done before a progress line could be read.
  Future<CanvasExport?> _render({CanvasDocument? of}) async {
    var document = of ?? _document;
    switch (_as) {
      case PublishAs.image:
        if (_pdf) {
          return renderPdf(
            document,
            frame: _frame,
            scale: _scale,
            images: widget.images,
            paper: _paper,
            orientation: _orientation,
          );
        }
        return renderImage(
          document,
          frame: _frame,
          scale: _scale,
          images: widget.images,
          options: EmbedOptions(format: _format, quality: _quality),
        );
      case PublishAs.animation:
        return renderGif(
          document,
          scale: _scale,
          images: widget.images,
          dither: _dither,
          maxColors: _colors,
          loop: _loop ? 0 : 1,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _progress = "Rendering frame $done of $total…");
            }
          },
        );
      case PublishAs.video:
        return renderVideo(
          document,
          scale: _scale,
          images: widget.images,
          format: _videoFormat,
          quality: _videoQuality,
          sound: _sound,
          panels: _panelVideo ? _panelPace : null,
          panelMusic: _panelMusic && _hasTimedSound,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _progress = "Rendering frame $done of $total…");
            }
          },
        );
      case PublishAs.audio:
        return renderAudio(document, options: _sound);
      case PublishAs.document:
        return renderDocument(
          document,
          as: _documentAs,
          profile: _documentAs == DocumentAs.pdf ? null : _profile,
          soundKbps: _sound.kbps,
          spreads: widget.document.isPages ? _spreads : null,
          scale: _scale,
          images: widget.images,
          paper: _paper,
          orientation: _orientation,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _progress = "Rendering page $done of $total…");
            }
          },
        );
      case PublishAs.interactive:
        // Nothing rendered: the canvas goes as itself, declared at its size
        // since a receiver lays out a box before it has content. With its
        // pictures and media where it has any (canvas_bundle.dart), as their
        // ids point at a store only the sender has; with none, plain JSON.
        if (document.assetIds.isEmpty && document.mediaIds.isEmpty) {
          return CanvasExport(
            utf8.encode(document.encode()),
            "application/json",
            width: widget.document.size.exportWidth,
            height: widget.document.size.exportHeight,
          );
        }
        return CanvasExport(
          await packCanvas(document),
          bundleMime,
          width: widget.document.size.exportWidth,
          height: widget.document.size.exportHeight,
        );
    }
  }

  /// _publish renders, sends and reports. The snackbar is taken before the
  /// first await: after a long render the context may be unmounted. Each
  /// branch re-checks mounted after its await, and finally clears _busy.
  Future<void> _publish() async {
    var snackbar = SnackBarModel.of(context);
    if (_to == PublishTo.shared && !_shareTerms.reachesAnyone) {
      snackbar.error("Choose who to share it with.");
      return;
    }
    // Remembered as published, so the next canvas opens the sheet the same.
    _prefs?.publish = _settings;
    setState(() {
      _busy = true;
      _progress = "Rendering…";
    });

    try {
      // The encoder is the likeliest failure on a video: "unable to render"
      // would send somebody to their canvas, not their machine.
      if (_needsFfmpeg) {
        setState(() => _progress = _as == PublishAs.audio
            ? "Mixing the sound…"
            : "Encoding the video…");
      }
      // Every shape it is laid out for, each rendered from the document laid
      // out for it (CanvasDocument.forShape), the one on screen among them.
      if (_everyShape && _canPublishEveryShape) {
        await _publishEveryShape(snackbar);
        return;
      }

      var export = await _render();
      if (!mounted) return;
      if (export == null) {
        snackbar.error(_needsFfmpeg && !_ffmpeg
            ? ffmpegHelp
            : "Unable to render the canvas.");
        return;
      }

      // A book is checked before it goes anywhere: Apple refuses one that
      // fails EPUBCheck, and our own check catches what it finds first.
      if (_as == PublishAs.document && _documentAs != DocumentAs.pdf) {
        setState(() => _progress = "Checking the book…");
        var report = await checkEpub(export.data);
        if (!mounted) return;
        if (!report.passed && !await _goOnDespite(report)) return;
        if (!mounted) return;
      }

      switch (_to) {
        case PublishTo.file:
          var written = await saveToDisk(export, _suggestedName);
          if (!mounted) return;
          // A cancelled save dialog is not a failure.
          if (written != null) snackbar.success("Saved to $written.");

        case PublishTo.chat:
          var chat = _chat;
          if (chat == null) {
            snackbar.error("Choose a chat to send it to.");
            return;
          }
          var problem = await sendToChat(chat, export, caption: _caption);
          if (!mounted) return;
          problem == null
              ? snackbar.success("Sent to ${chat.nick}.")
              : snackbar.error(problem);

        case PublishTo.library:
          var record = await publishToLibrary(export, _suggestedName, _record);
          if (!mounted) return;
          if (record == null) {
            snackbar.error("Unable to add the canvas to the library.");
            return;
          }
          await _remember(record);
          if (!mounted) return;
          snackbar
              .success("Added to the post library under $publishedFolderName. "
                  "Embed it from a post or a page with Add Embed.");

        case PublishTo.shared:
          var record = await shareInFiles(export, _suggestedName, _record,
              terms: _shareTerms);
          if (!mounted) return;
          if (record == null) {
            snackbar.error("Unable to share the canvas.");
            return;
          }
          await _remember(record);
          if (!mounted) return;
          snackbar.success("Shared as $_suggestedName"
              "${extensionFor(export.mime)} in Files.");
      }

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = "";
        });
      }
    }
  }

  /// _canPublishEveryShape: several shapes laid out, going somewhere that
  /// holds several.
  bool get _canPublishEveryShape =>
      widget.document.targets.length > 1 &&
      (_to == PublishTo.file || _to == PublishTo.chat);

  /// _publishEveryShape renders once per shape and sends the lot -- one
  /// folder asked for, or a chat message per shape -- reported as a set
  /// ("three of three") so a failed shape is not a silent gap.
  Future<void> _publishEveryShape(SnackBarModel snackbar) async {
    var here = widget.document.size;
    var made = <({String tag, CanvasExport export})>[];

    for (var key in widget.document.targets) {
      if (!mounted) return;
      var tag = shapeTag(key);
      setState(() => _progress = "Rendering $tag…");
      var laid = _document.forShape(sizeForShape(key, here));
      var export = await _render(of: laid);
      if (export != null) made.add((tag: tag, export: export));
    }
    if (!mounted) return;
    if (made.isEmpty) {
      snackbar.error(_needsFfmpeg && !_ffmpeg
          ? ffmpegHelp
          : "Unable to render the canvas.");
      return;
    }

    var asked = widget.document.targets.length;
    if (_to == PublishTo.file) {
      var saved = await saveAllToDisk(made, _suggestedName);
      if (!mounted) return;
      // A cancelled folder chooser is not a failure.
      if (saved == null) return;
      snackbar.success("Saved ${saved.written.length} of $asked shapes to "
          "${saved.folder}.");
    } else {
      var chat = _chat;
      if (chat == null) {
        snackbar.error("Choose a chat to send it to.");
        return;
      }
      var sent = 0;
      for (var shape in made) {
        var problem = await sendToChat(chat, shape.export,
            caption: _caption.isEmpty ? shape.tag : "$_caption — ${shape.tag}");
        if (problem == null) {
          sent++;
        } else if (mounted) {
          snackbar.error("${shape.tag}: $problem");
        }
      }
      if (!mounted) return;
      if (sent == 0) return;
      snackbar.success("Sent $sent of $asked shapes to ${chat.nick}.");
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// _remember keeps what a publish produced: on screen always, so the
  /// button says Update at once (and an unsaved canvas shows Unpublish while
  /// the sheet is open); on disk only where there is a canvas to file it on.
  Future<void> _remember(PublishRecord record) async {
    setState(() => _record = record);
    if (!_canRecord) return;
    await PublishRecords.write(widget.folder ?? "", widget.name!, record);
  }

  /// _unpublish takes back what went to the chosen destination: only the two
  /// that can be taken back, not a saved file or a sent message.
  Future<void> _unpublish() async {
    var snackbar = SnackBarModel.of(context);
    setState(() => _busy = true);
    try {
      if (_to == PublishTo.shared && _record.hasShare) {
        await unshareFiles(_record);
        await _remember(_record.copyWith(sharedPath: ""));
      } else if (_to == PublishTo.library && _record.hasDocument) {
        await unpublishFromLibrary(_record);
        await _remember(_record.copyWith(documentName: "", documentFolder: ""));
      }
      if (mounted) snackbar.success("No longer published.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _isPublishedHere is whether the destination holds a copy: Update.
  bool get _isPublishedHere => switch (_to) {
        PublishTo.shared => _record.hasShare,
        PublishTo.library => _record.hasDocument,
        _ => false,
      };

  /// One scrolling column in a dialog, so the canvas stays in sight.
  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    return AlertDialog(
      title: Text("Publish $_suggestedName"),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The two questions in order, the first's settings between
              // them: what, how big and in what format, then where. Any
              // problem is said at the choice causing it. A dropdown, not
              // four rows: only the chosen one keeps its description.
              _dropdown<PublishAs>(
                theme,
                "Publish as",
                _as,
                [
                  for (var o in PublishAs.values) (o, o.label),
                ],
                _busy ? (_) {} : (v) => setState(() => _as = v),
              ),
              _note(theme, _as.description),
              // Said at the choice: a video with no encoder cannot be made.
              if (_needsFfmpeg && !_ffmpeg)
                _warning(theme, ffmpegHelp),
              if ((_as == PublishAs.animation || _as == PublishAs.video) &&
                  !widget.document.isAnimated)
                _warning(
                    theme,
                    "This canvas is a single frame, so the animation will be "
                    "one frame long. Add frames on the timeline first."),
              ..._sceneControls(theme),
              const SizedBox(height: 8),
              ..._formatControls(theme),
              const Divider(height: 24),
              _heading("Publish to"),
              for (var option in PublishTo.values)
                _option(
                  theme,
                  selected: option == _to,
                  label: option.label,
                  icon: option.icon,
                  onTap: _busy ? null : () => setState(() => _to = option),
                ),
              if (_canPublishEveryShape) ...[
                const SizedBox(height: 4),
                CanvasToggle(
                  key: const ValueKey("publishEveryShape"),
                  label: "Every shape (${widget.document.targets.length})",
                  value: _everyShape,
                  onChanged:
                      _busy ? (_) {} : (v) => setState(() => _everyShape = v),
                ),
                _note(
                    theme,
                    "One file per shape this canvas is laid out for, each at "
                    "its own layout: ${widget.document.targets.map(shapeTag).join(", ")}."),
              ],
              if (_to == PublishTo.chat) ..._chatControls(theme),
              if (_to == PublishTo.shared) ..._shareControls(),
              if (_to == PublishTo.library)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Txt.S(
                      "The canvas becomes a document in the $publishedFolderName "
                      "folder of the post library, so a post, a page or a store "
                      "product can embed it."),
                ),
              if (_isPublishedHere)
                _note(
                    theme,
                    "Already published here"
                    "${_record.publishedAt == null ? "" : " on "
                        "${_record.publishedAt!.toLocal()}"}. "
                    "Publishing again replaces it."),
              if (!_canRecord &&
                  (_to == PublishTo.shared || _to == PublishTo.library))
                _warning(
                    theme,
                    "Save this canvas first if you want to be able to update "
                    "or unpublish it later."),
              if (_tooBigForChat)
                _warning(
                    theme,
                    "This is likely to be too large for one message. Reduce "
                    "the scale, or publish as a JPEG."),
              const Divider(height: 24),
              // The size line, the reason the sheet estimates: checked before
              // a press that may take a minute, changing with scale and format.
              Row(children: [
                Icon(Icons.data_usage,
                    size: 15, color: theme.colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  _as == PublishAs.interactive
                      ? "Size: ${formatBytes(_estimate)}"
                      : "Estimated size: ${formatBytes(_estimate)}",
                  style: TextStyle(
                      fontSize: 12, color: theme.colors.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  // The file's size: the export size, not the design space.
                  "${(widget.document.size.exportSize.width * _scale).round()}"
                  " × "
                  "${(widget.document.size.exportSize.height * _scale).round()}",
                  style: TextStyle(
                      fontSize: 12, color: theme.colors.onSurfaceVariant),
                ),
              ]),
              if (_progress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(_progress, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isPublishedHere)
          TextButton(
            onPressed: _busy ? null : _unpublish,
            child: const Text("Unpublish"),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed:
              _busy || (_needsFfmpeg && !_ffmpeg) ? null : _publish,
          child: Text(_isPublishedHere ? "Update" : "Publish"),
        ),
      ],
    );
  }

  /// _sceneControls choose how much of a several-canvas document goes;
  /// nothing for one. Under "Publish as", not by the destination: a range of
  /// scenes is a different thing made, not a different place to send it.
  List<Widget> _sceneControls(ThemeNotifier theme) {
    var document = widget.document;
    if (!document.hasScenes) return const [];
    var count = document.allScenes.length;

    /// name says which canvas a number is, so named scenes need no counting.
    String name(int index) {
      var label = document.allScenes[index].name.trim();
      return label.isEmpty ? "Scene ${index + 1}" : "${index + 1}. $label";
    }

    // A still is one canvas, so the only question is which.
    if (_onePicture) {
      return [
        const SizedBox(height: 10),
        _dropdown<int>(
          theme,
          "Scene",
          _first.clamp(0, count - 1),
          [for (var i = 0; i < count; i++) (i, name(i))],
          _busy ? (_) {} : (v) => setState(() => _first = v),
        ),
        _note(theme, "Which canvas the picture is of."),
      ];
    }

    return [
      const SizedBox(height: 10),
      _dropdown<PublishScenes>(
        theme,
        "Scenes",
        _scenes,
        [for (var o in PublishScenes.values) (o, o.label)],
        _busy ? (_) {} : (v) => setState(() => _scenes = v),
      ),
      _note(theme, _scenes.description),
      if (_scenes != PublishScenes.all)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(
              child: _dropdown<int>(
                theme,
                _scenes == PublishScenes.one ? "Scene" : "From",
                _first.clamp(0, count - 1),
                [for (var i = 0; i < count; i++) (i, name(i))],
                (v) => setState(() {
                  _first = v;
                  // A backwards range is no range: the far end follows.
                  if (_last < _first) _last = _first;
                }),
              ),
            ),
            if (_scenes == PublishScenes.range) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown<int>(
                  theme,
                  "To",
                  _last.clamp(_first, count - 1),
                  [for (var i = _first; i < count; i++) (i, name(i))],
                  (v) => setState(() => _last = v),
                ),
              ),
            ],
          ]),
        ),
    ];
  }

  /// _formatControls is the settings for what is being made: a branch per
  /// kind, not every control with some disabled, since a greyed row still
  /// reads as a setting somebody is failing to reach.
  List<Widget> _formatControls(ThemeNotifier theme) {
    switch (_as) {
      case PublishAs.image:
        return [
          Row(children: [
            Expanded(
              // One list, not a format and a PDF switch: three answers to one
              // question, seen at once.
              child: _dropdown<String>(
                  theme,
                  "Format",
                  _pdf ? "pdf" : _format.name,
                  const [
                    ("png", "PNG (lossless)"),
                    ("jpeg", "JPEG (smaller)"),
                    ("pdf", "PDF (a page)"),
                  ],
                  (v) => setState(() {
                        _pdf = v == "pdf";
                        if (!_pdf) {
                          _format =
                              v == "jpeg" ? EmbedFormat.jpeg : EmbedFormat.png;
                        }
                      })),
            ),
            const SizedBox(width: 12),
            Expanded(child: _scaleField(theme)),
          ]),
          if (!_pdf && _format == EmbedFormat.jpeg)
            _slider(theme, "Quality", _quality.toDouble(), 20, 100,
                (v) => setState(() => _quality = v.round()),
                suffix: "$_quality"),
          if (_pdf) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: _dropdown<PdfPaper>(
                    theme,
                    "Page",
                    _paper,
                    [for (var p in PdfPaper.values) (p, p.label)],
                    (v) => setState(() => _paper = v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Only paper has a second way up.
                child: _paper.turns
                    ? _dropdown<PdfOrientation>(
                        theme,
                        "Orientation",
                        _orientation,
                        [for (var o in PdfOrientation.values) (o, o.label)],
                        (v) => setState(() => _orientation = v))
                    : const SizedBox(),
              ),
            ]),
            _note(
                theme,
                _paper == PdfPaper.canvas
                    ? "A page cut to the canvas: "
                        "${_pageLabel()}, with the design filling it. Size is "
                        "the print resolution — 1 is a screen's worth of "
                        "detail, which is soft on paper."
                    : "The design is centred on ${_paper.label} "
                        "${_pageLabel()} with a half inch margin, as large as "
                        "it fits — so a wide design on a portrait sheet fills "
                        "the width and leaves the room above and below. Size "
                        "is the print resolution rather than the page size."),
          ],
        ];

      case PublishAs.animation:
        return [
          Row(children: [
            Expanded(child: _scaleField(theme)),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown<int>(
                  theme,
                  "Colours",
                  _colors,
                  const [
                    (256, "256 (best)"),
                    (128, "128"),
                    (64, "64 (smallest)"),
                  ],
                  (v) => setState(() => _colors = v)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: CheckboxListTile(
                value: _dither,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text("Dither", style: TextStyle(fontSize: 12)),
                subtitle: Text("Smoother gradients, slightly larger",
                    style: TextStyle(
                        fontSize: 10, color: theme.colors.onSurfaceVariant)),
                onChanged: (v) => setState(() => _dither = v ?? true),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                value: _loop,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title:
                    const Text("Loop forever", style: TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() => _loop = v ?? true),
              ),
            ),
          ]),
          // Of the published document: all scenes end to end, or the one.
          _note(theme, _runNote()),
        ];

      case PublishAs.video:
        return [
          Row(children: [
            Expanded(child: _scaleField(theme)),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown<VideoFormat>(
                  theme,
                  "Format",
                  _videoFormat,
                  [for (var f in VideoFormat.values) (f, f.label)],
                  (v) => setState(() => _videoFormat = v)),
            ),
          ]),
          const SizedBox(height: 4),
          _dropdown<VideoQuality>(
              theme,
              "Quality",
              _videoQuality,
              [for (var q in VideoQuality.values) (q, q.label)],
              (v) => setState(() => _videoQuality = v)),
          if (hasPanels(widget.document)) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  key: const ValueKey("publishPanelVideo"),
                  value: _panelVideo,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Panel by panel",
                      style: TextStyle(fontSize: 12)),
                  subtitle: Text(
                      "Read as Panel mode reads it: each page whole, then "
                      "gliding to each panel in its reading order.",
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colors.onSurfaceVariant)),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _panelVideo = v ?? false),
                ),
              ),
              if (_panelVideo) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: _dropdown<PanelPace>(
                      theme,
                      "Pace",
                      _panelPace,
                      [for (var p in PanelPace.values) (p, p.label)],
                      (v) => setState(() => _panelPace = v)),
                ),
              ],
            ]),
          ],
          if (_panelVideo && hasPanels(widget.document) && _hasTimedSound)
            CheckboxListTile(
              key: const ValueKey("publishPanelMusic"),
              value: _panelMusic,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("With its music",
                  style: TextStyle(fontSize: 12)),
              subtitle: Text(
                  "The canvas's sound under the whole reading, from the "
                  "start and round again, fading out at the end. It does "
                  "not keep time with the panels.",
                  style: TextStyle(
                      fontSize: 10, color: theme.colors.onSurfaceVariant)),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _panelMusic = v ?? false),
            ),
          const SizedBox(height: 10),
          if (!(_panelVideo && hasPanels(widget.document)) || _panelMusic)
            ..._soundControls(theme,
                fixedRate: _videoFormat == VideoFormat.webm ? 48000 : null),
          _note(
              theme,
              "${_panelVideo && hasPanels(widget.document) ? _panelNote() : _runNote()} "
              "A video keeps every colour, where a GIF has 256, "
              "and is usually much smaller. ${_videoFormat.note}"),
        ];

      case PublishAs.audio:
        return [
          ..._soundControls(theme, file: _sound.format),
          if (!_hasTimedSound)
            _warning(
                theme,
                "Nothing is on the timeline to hear: add a sound or a video "
                "to a channel first."),
          _note(theme, "${_runNote()} ${_sound.format.note}"),
        ];

      case PublishAs.document:
        return [
          // A PDF, or an EPUB for one store: each store's book carries what
          // it runs and is held to its rules (StoreProfile).
          Row(children: [
            Expanded(
              child: _dropdown<String>(
                theme,
                "Format",
                _documentAs == DocumentAs.pdf ? "pdf" : _profile.name,
                [
                  ("pdf", DocumentAs.pdf.label),
                  for (var p in StoreProfile.values) (p.name, "EPUB for ${p.label}"),
                ],
                (v) => setState(() {
                  if (v == "pdf") {
                    _documentAs = DocumentAs.pdf;
                  } else {
                    _profile = StoreProfile.fromName(v);
                    _documentAs = _profile.document;
                  }
                }),
              ),
            ),
          ]),
          if (_documentAs != DocumentAs.pdf)
            for (var r in [
              ...storeReadiness(widget.document, _profile,
                  scale: _scale, ffmpeg: _ffmpeg),
              if (!_epubcheck) (problem: false, text: epubcheckHelp),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          r.problem
                              ? Icons.error_outline
                              : Icons.info_outline,
                          size: 15,
                          color: r.problem
                              ? theme.colors.error
                              : theme.colors.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(r.text,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colors.onSurfaceVariant))),
                    ]),
              ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _documentAs == DocumentAs.pdf
                  ? _dropdown<PdfPaper>(
                      theme,
                      "Page",
                      _paper,
                      [for (var p in PdfPaper.values) (p, p.label)],
                      (v) => setState(() => _paper = v))
                  // A book's page is the canvas alone: an EPUB is laid out at
                  // the design's size and the reader fits it to the screen.
                  : const SizedBox(),
            ),
            const SizedBox(width: 12),
            Expanded(child: _scaleField(theme)),
          ]),
          if (_documentAs == DocumentAs.pdf && _paper.turns) ...[
            const SizedBox(height: 4),
            _dropdown<PdfOrientation>(
                theme,
                "Orientation",
                _orientation,
                [for (var o in PdfOrientation.values) (o, o.label)],
                (v) => setState(() => _orientation = v)),
          ],
          if (_documentAs != DocumentAs.pdf && widget.document.isPages)
            CheckboxListTile(
              key: const ValueKey("publishSpreads"),
              value: _spreads,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Two-page spreads",
                  style: TextStyle(fontSize: 12)),
              subtitle: Text(
                  "Turned on its side, the reader shows two pages side by "
                  "side, as a printed book opens; upright, one."
                  "${_documentAs == DocumentAs.epub && hasPanels(widget.document) ? " Its panels are marked in their reading order for readers that zoom panel by panel, as a book from the Kindle store does." : ""}",
                  style: TextStyle(
                      fontSize: 10, color: theme.colors.onSurfaceVariant)),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _spreads = v ?? true),
            ),
          if (_documentAs == DocumentAs.interactiveEpub) ...[
            const SizedBox(height: 10),
            _heading("Sound"),
            _dropdown<int>(
                theme,
                "Sound quality",
                _sound.kbps,
                [for (var k in audioBitrates) (k, "$k kbps AAC")],
                (v) => setState(() => _sound = _sound.copyWith(kbps: v))),
          ],
          const SizedBox(height: 10),
          Txt.S("${_documentAs == DocumentAs.pdf ? _documentAs.description : _profile.description}. "
              "${widget.document.allScenes.length} "
              "page${widget.document.allScenes.length == 1 ? "" : "s"}, "
              "each at the size this canvas is."
              "${_documentAs == DocumentAs.interactiveEpub ? " Its buttons "
                  "work as they do here: going to a page, opening a link, "
                  "playing, pausing and showing or hiding. A page that moves "
                  "is its own elements, animated by the reader: sharp at any "
                  "size and light to carry. What an element does that the "
                  "reader cannot — a chart growing, a counter counting — is "
                  "a short video of that element alone, and backgrounds hold "
                  "still." : ""}"),
        ];

      case PublishAs.interactive:
        return [
          Txt.S(widget.document.assetIds.isEmpty &&
                  widget.document.mediaIds.isEmpty
              ? "The canvas is published as itself: whoever opens it can play "
                  "the animation, press its buttons and move anything you "
                  "have not locked. Nothing is rendered, so it stays small "
                  "however large the canvas is."
              : "The canvas is published as itself, with its "
                  "${widget.document.assetIds.length} "
                  "picture${widget.document.assetIds.length == 1 ? "" : "s"} "
                  "packed in beside it, so it opens on another machine "
                  "looking the way it does here. Nothing is rendered: whoever "
                  "opens it can play the animation, press its buttons and "
                  "move anything you have not locked."),
        ];

    }
  }

  /// _hasTimedSound is whether anything on a timeline channel can be heard.
  bool get _hasTimedSound {
    var d = _document;
    for (var e in [
      for (var scene in d.allScenes) ...scene.elements,
      ...?d.masterScene?.elements,
      ...d.drawnBackground.media,
    ]) {
      var clip = switch (e) {
        AudioElement a => a.clip,
        VideoElement v => v.clip,
        _ => null,
      };
      if (clip != null && clip.timed && !clip.isEmpty) return true;
    }
    return false;
  }

  /// _soundControls is how an export's sound is written, for every kind
  /// with sound in it -- with its format where it is a sound file ([file]),
  /// and without a rate where its container has only one ([fixedRate]).
  List<Widget> _soundControls(ThemeNotifier theme,
      {AudioFormat? file, int? fixedRate}) {
    var lossless = file?.lossless ?? false;
    var fixed = fixedRate ?? file?.fixedRate;
    void set(AudioOptions next) => setState(() => _sound = next);
    return [
      _heading("Sound"),
      Row(children: [
        if (file != null) ...[
          Expanded(
            child: _dropdown<AudioFormat>(
                theme,
                "Format",
                file,
                [for (var f in AudioFormat.values) (f, f.label)],
                (v) => set(_sound.copyWith(format: v))),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: lossless
              ? _dropdown<int>(
                  theme,
                  "Bit depth",
                  _sound.bitDepth,
                  [for (var d in audioDepths) (d, "$d-bit")],
                  (v) => set(_sound.copyWith(bitDepth: v)))
              : _dropdown<int>(
                  theme,
                  "Quality",
                  _sound.kbps,
                  [for (var k in audioBitrates) (k, "$k kbps")],
                  (v) => set(_sound.copyWith(kbps: v))),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: fixed != null
              ? _note(theme, "${fixed ~/ 1000} kHz: the only rate it plays at.")
              : _dropdown<int>(
                  theme,
                  "Sample rate",
                  _sound.sampleRate,
                  [
                    for (var r in audioRates)
                      (r, "${(r / 1000).toStringAsFixed(1)} kHz")
                  ],
                  (v) => set(_sound.copyWith(sampleRate: v))),
        ),
        const SizedBox(width: 12),
        // Brought to a loudness over the whole mix (the mixer's Loudness).
        Expanded(
          child: CheckboxListTile(
            key: const ValueKey("publishToTarget"),
            value: _toTarget,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text("To a loudness target",
                style: TextStyle(fontSize: 12)),
            subtitle: Text("Measured, then limited",
                style: TextStyle(
                    fontSize: 10, color: theme.colors.onSurfaceVariant)),
            onChanged: (v) => setState(() => _toTarget = v ?? false),
          ),
        ),
      ]),
      if (_toTarget)
        _dropdown<double>(
            theme,
            "Loudness",
            _target,
            loudnessOptions(_target),
            (v) => setState(() => _target = v)),
    ];
  }

  /// _pageLabel is the sheet's size in inches, the unit a page means
  /// anything in: a canvas 1280 pixels wide is a thirteen-inch page.
  String _pageLabel() {
    var page =
        pageFor(_paper, widget.document.size.size, orientation: _orientation);
    return "${(page.width / 72).toStringAsFixed(1)} × "
        "${(page.height / 72).toStringAsFixed(1)} inches";
  }

  /// _scaleField is in multiples of the canvas, not pixels: "double" can be
  /// pictured; a pixel width is a sum against a size to look up.
  Widget _scaleField(ThemeNotifier theme) => _dropdown<double>(
      theme,
      "Size",
      _scale,
      const [
        (0.5, "Half"),
        (1.0, "Actual size"),
        (2.0, "Double"),
        (3.0, "Triple"),
      ],
      (v) => setState(() => _scale = v));

  /// _shareControls set who can fetch the shared canvas, its cost and its
  /// description before it is shared (Ken, 2026-11-19).
  List<Widget> _shareControls() => [
        const SizedBox(height: 8),
        ShareSettingsFields(
          key: ValueKey("shareFields$_shareLoaded"),
          initial: _shareTerms,
          enabled: !_busy,
          onChanged: (terms) => setState(() => _share = terms),
        ),
        if (_record.hasShare) ...[
          const SizedBox(height: 10),
          const ShareChangeNote(republishing: true),
        ],
      ];

  List<Widget> _chatControls(ThemeNotifier theme) {
    var client = context.watch<ClientModel>();
    var chats = client.activeChats.sorted;
    // Defaulted here, as the chat list is only available now, and without
    // setState on purpose: the dropdown below draws this value, and setState
    // during build is an error.
    if (_chat == null && chats.isNotEmpty) _chat = chats.first;

    return [
      const SizedBox(height: 4),
      if (chats.isEmpty)
        _warning(theme, "There are no chats to send this to yet.")
      else
        _dropdown<ChatModel>(
          theme,
          "Chat",
          _chat ?? chats.first,
          [for (var chat in chats) (chat, chat.nick)],
          (v) => setState(() => _chat = v),
        ),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(
            labelText: "Message (optional)", isDense: true),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) => _caption = v,
      ),
    ];
  }

  /// _option is one choice in either list, not a RadioListTile, whose
  /// groupValue and onChanged are deprecated for a RadioGroup ancestor.
  Widget _option(
    ThemeNotifier theme, {
    required bool selected,
    required String label,
    required VoidCallback? onTap,
    String description = "",
    IconData? icon,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 17,
              color: selected
                  ? theme.colors.primary
                  : theme.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 17, color: theme.colors.onSurfaceVariant),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  if (description.isNotEmpty)
                    Text(description,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      );

  /// _dropdown is a labelled bare DropdownButton: a DropdownButtonFormField
  /// keeps its own copy of the value and goes stale as this state changes.
  Widget _dropdown<T>(
    ThemeNotifier theme,
    String label,
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged,
  ) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style:
                TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant)),
        SizedBox(
          height: 34,
          child: DropdownButton<T>(
            value: options.any((o) => o.$1 == value) ? value : null,
            isDense: true,
            isExpanded: true,
            style: TextStyle(fontSize: 13, color: theme.colors.onSurface),
            items: [
              for (var (v, text) in options)
                DropdownMenuItem(value: v, child: Text(text)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]);

  // The sheet's own small pieces: heading, note, warning and slider. Local,
  // not from ui/controls.dart, which suits the sidebar's narrow bands.

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
      );

  Widget _note(ThemeNotifier theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      );

  /// _warning is the one thing here somebody must read: the error colour on
  /// a tint of it, contrasting whatever the palette. Not tertiary, a panel
  /// background in this app, which makes the warning unreadable.
  Widget _warning(ThemeNotifier theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded,
                size: 15, color: theme.colors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 11, color: theme.colors.onSurface)),
            ),
          ]),
        ),
      );

  Widget _slider(ThemeNotifier theme, String label, double value, double min,
          double max, ValueChanged<double> onChanged,
          {String suffix = ""}) =>
      Row(children: [
        SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
            width: 34,
            child: Text(suffix,
                style: TextStyle(
                    fontSize: 11, color: theme.colors.onSurfaceVariant))),
      ]);
}
