import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/components/feed/embed_options.dart';
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// publish_sheet.dart is the Publish button's dialog: what to make, and where
// to send it, in one sheet because the two are not independent (a 2400px GIF
// is not going into a chat message), and the sheet has to say so before
// anything is rendered. Everything is an estimate until Publish is pressed:
// rendering a 200-frame GIF to measure it takes as long as publishing it.

/// PublishAs is what to make, in order of how much of the canvas survives:
/// a picture of one frame, a picture of all of them, or the canvas itself.
/// The last is still last because only it needs Bison Relay on the other
/// end; an image can be shown to anyone.
enum PublishAs {
  image("Image", "A single frame as a PNG, a JPEG or a PDF"),
  animation("Animation", "Every frame as an animated GIF"),
  video("Video", "Every frame as an MP4 or a WebM, at full colour"),
  // The sound alone: the timeline mixed, as a video's soundtrack is. See
  // audio_export.dart.
  audio("Audio", "The sound alone, mixed: a WAV, FLAC, MP3, AAC or Opus file"),
  // A document rather than a picture of one: every canvas a page, in
  // order. See document_export.dart.
  document("Document", "Every page as a PDF or an EPUB, to read and to print"),
  interactive(
      "Interactive canvas",
      "The canvas itself, with its pictures, sounds and videos, to open, "
          "play and edit again");

  final String label;
  final String description;
  const PublishAs(this.label, this.description);
}

/// PublishScenes is how much of a document with several canvases goes,
/// offered only where there is more than one.
enum PublishScenes {
  all("All scenes", "The whole document, in order"),
  one("One scene", "Just the one, as if it were the whole document"),
  range("A range", "From one scene to another, in order");

  final String label;
  final String description;
  const PublishScenes(this.label, this.description);
}

/// PublishTo is where it goes: a file, or three things Bison Relay can do
/// that a file cannot (a canvas in a chat, one a post can embed, one somebody
/// can fetch from Files). Saving to disk is first because it always works;
/// the others each need something set up.
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
/// where the canvas is saved and what the publish record is keyed on: an
/// unsaved canvas can be published but not updated afterwards, and the sheet
/// says so.
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

/// _PublishSheet is the dialog itself, opened only through showPublishSheet.
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

  /// _documentAs is which sort of document, once Document is what is being
  /// made. See DocumentAs.
  DocumentAs _documentAs = DocumentAs.pdf;
  PublishTo _to = PublishTo.file;

  // The still settings, then the animation's, kept side by side so
  // switching between Image and Animation and back finds both as left.
  EmbedFormat _format = EmbedFormat.png;
  int _quality = 85;
  double _scale = 1;

  /// _pdf is whether the still is a page rather than a picture, and on what
  /// size of paper. A flag beside the format rather than a fourth EmbedFormat,
  /// which is the app's list of what a picture attached to a post may be.
  bool _pdf = false;
  PdfPaper _paper = PdfPaper.canvas;
  PdfOrientation _orientation = PdfOrientation.auto;

  /// _everyShape is whether to publish the canvas at every shape it is
  /// designed for rather than only the one on screen. Offered for a file and a
  /// chat only: the library and Files keep one publish record per canvas. See
  /// CanvasDocument.targets.
  bool _everyShape = false;

  bool _dither = true;

  /// _toTarget brings a video's sound to the master's loudness target -- a
  /// publish setting rather than the mixer's, since it is about the file
  /// being made. Starts from what the document said before it moved here.
  late bool _toTarget = widget.document.masterMix.normalise;

  /// _target is the loudness it is brought to, starting from the mixer's.
  late double _target = widget.document.masterMix.target;

  /// _sound is how sound is written: a sound file's format, and for every
  /// kind with sound in it the bitrate, rate and depth. See AudioOptions.
  /// Starts from the document's own (AudioSettings.export), not from the last
  /// publish of some other canvas.
  late AudioOptions _sound = widget.document.audio.export;

  /// _needsFfmpeg is whether what is being made is made by ffmpeg.
  bool get _needsFfmpeg => _as == PublishAs.video || _as == PublishAs.audio;
  int _colors = 256;
  bool _loop = true;

  VideoFormat _videoFormat = VideoFormat.mp4;
  VideoQuality _videoQuality = VideoQuality.balanced;

  /// _ffmpeg is whether there is an encoder to make an MP4 with, which is not
  /// known until it has been looked for. Assumed absent until the look comes
  /// back, so the sheet never offers something and then takes it away.
  bool _ffmpeg = false;

  /// _scenes is how much of a document with several canvases is published,
  /// and _first and _last which ones, as indexes shown counting from one.
  /// _last is kept while a single scene is chosen, so a range comes back as
  /// it was.
  PublishScenes _scenes = PublishScenes.all;
  late int _first = widget.document.at;
  late int _last = widget.document.at;

  ChatModel? _chat;
  String _caption = "";

  /// _document is what is actually published: the whole thing, or the scenes
  /// chosen. A trimmed document rather than a range handed to each renderer:
  /// the GIF, the video, the PDF, the estimate and the bundle all do the right
  /// thing with a shorter one.
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
    // A still is one canvas, whichever one is chosen. Everything else follows
    // the three-way choice.
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

  /// _onePicture is whether what is being made holds exactly one canvas: a
  /// PNG or a JPEG, which asks "which one" rather than "how many".
  bool get _onePicture => _as == PublishAs.image && !_pdf;

  /// _frame is which frame is taken: the one the reader was looking at, where
  /// it is in the document being published, moved into a trimmed scene's own
  /// count.
  int get _frame {
    var document = widget.document;
    if (!document.hasScenes || _scenes == PublishScenes.all && !_onePicture) {
      return widget.frame;
    }
    var from = document.startOfScene(_first);
    var into = widget.frame - from;
    return into >= 0 && into < _document.playFrames ? into : 0;
  }

  /// _record is what was published from this canvas before, which is what
  /// makes Publish say Update and puts an Unpublish button in the corner.
  PublishRecord _record = const PublishRecord();

  /// _busy disables every control while a render is running, so a second
  /// press does not render it all twice.
  bool _busy = false;
  String _progress = "";

  /// _canRecord is whether there is anywhere to keep [_record], which is
  /// filed under the canvas's folder and name.
  bool get _canRecord => widget.name != null;

  @override
  void initState() {
    super.initState();
    // As it was last published with, and Image the first time: a GIF is the
    // most expensive thing this sheet makes, and should not be the first size
    // anybody sees.
    _restore();
    _loadRecord();
    _measurePictures();
    // Asked once, here, rather than in build: it is a process launch, and
    // build runs on every keystroke in the caption field.
    ffmpegPath().then((found) {
      if (mounted) setState(() => _ffmpeg = found != null);
    });
  }

  /// _prefs is where the settings are remembered, where there is anywhere --
  /// the sheet opened on its own, as a test opens it, has nowhere.
  CanvasPreferences? get _prefs {
    try {
      return Provider.of<CanvasPreferences>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  /// _settings is how the sheet is set, as it is remembered: not which scenes,
  /// which chat or the caption, which belong to the canvas and the moment.
  Map<String, dynamic> get _settings => {
        "as": _as.name,
        "document": _documentAs.name,
        "to": _to.name,
        "format": _format.name,
        "quality": _quality,
        "scale": _scale,
        "pdf": _pdf,
        "paper": _paper.name,
        "orientation": _orientation.name,
        "everyShape": _everyShape,
        "dither": _dither,
        "colors": _colors,
        "loop": _loop,
        "videoFormat": _videoFormat.name,
        "videoQuality": _videoQuality.name,
        "toTarget": _toTarget,
        "target": _target,
        "sound": _sound.toJson(),
      };

  /// _restore sets the sheet as it was last published with. Anything no
  /// longer recognised -- a setting since renamed, a value out of range --
  /// keeps the sheet's own default.
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
    _to = pick(PublishTo.values, "to", _to);
    _format = pick(EmbedFormat.values, "format", _format);
    _quality = number("quality", _quality).toInt().clamp(1, 100);
    _scale = number("scale", _scale).toDouble().clamp(0.05, maxExportScale);
    _pdf = flag("pdf", _pdf);
    _paper = pick(PdfPaper.values, "paper", _paper);
    _orientation = pick(PdfOrientation.values, "orientation", _orientation);
    _everyShape = flag("everyShape", _everyShape);
    _dither = flag("dither", _dither);
    _colors = number("colors", _colors).toInt().clamp(2, 256);
    _loop = flag("loop", _loop);
    _videoFormat = pick(VideoFormat.values, "videoFormat", _videoFormat);
    _videoQuality = pick(VideoQuality.values, "videoQuality", _videoQuality);
    _toTarget = flag("toTarget", _toTarget);
    var target = number("target", _target).toDouble();
    if (loudnessTargets.any((t) => t.$1 == target)) _target = target;
  }

  /// _loadRecord reads what this canvas published before, if anything. Not
  /// awaited by initState: the button changes from Publish to Update a moment
  /// later rather than the dialog taking a moment to appear.
  Future<void> _loadRecord() async {
    if (!_canRecord) return;
    var record = await PublishRecords.read(widget.folder ?? "", widget.name!);
    if (mounted && record != null) setState(() => _record = record);
  }

  /// _suggestedName is what the file, the document or the share is called: the
  /// canvas's own name if it has been saved, otherwise its title, otherwise a
  /// word rather than an empty string.
  String get _suggestedName =>
      widget.name ??
      (widget.document.title.isEmpty ? "Canvas" : widget.document.title);

  int get _estimate => switch (_as) {
        // A PDF is the same rendered frame with a page round it, its pixels
        // deflated rather than PNG-compressed: close enough to the same size.
        PublishAs.image => estimateStillBytes(_document, scale: _scale),
        PublishAs.animation => estimateAnimationBytes(_document, scale: _scale),
        PublishAs.video => estimateVideoBytes(_document,
            scale: _scale, format: _videoFormat, quality: _videoQuality),
        PublishAs.audio => estimateAudioBytes(_document, _sound),
        PublishAs.document => estimateDocumentBytes(_document, scale: _scale),
        // An interactive canvas is the document itself, so this one is exact
        // and the label says so; its pictures and media go in at their stored
        // size, being compressed already.
        PublishAs.interactive => _document.encode().length + _pictureBytes,
      };

  /// _pictureBytes is what the canvas's pictures weigh, nearly all of a
  /// bundle: measured once when the sheet opens, being a read of each.
  int _pictureBytes = 0;

  Future<void> _measurePictures() async {
    var total = 0;
    for (var id in _document.assetIds) {
      total += (await CanvasAssets.load(id))?.length ?? 0;
    }
    // And its sounds and videos, which a bundle carries too and which are
    // most of what anything with a video in it weighs.
    for (var id in _document.mediaIds) {
      var file = await CanvasMedia.existingPath(CanvasMedia.kindOf(id), id);
      if (file != null) total += await File(file).length();
    }
    if (mounted) setState(() => _pictureBytes = total);
  }

  /// _tooBigForChat is the one warning given before anything is rendered: the
  /// one failure that would otherwise come after a long wait.
  bool get _tooBigForChat {
    if (_to != PublishTo.chat) return false;
    // Base64 is four bytes of text for every three of data, and the markup
    // itself is a few dozen more.
    return _estimate * 4 / 3 > 900000;
  }

  /// _render makes the bytes, and is the only slow thing here. Both raster
  /// paths go through export/canvas_export.dart, as the embed and the thumbnail
  /// do, so what is published is the picture the canvas draws. Only the GIF
  /// reports progress: a still is done before a progress line could be read.
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
          soundKbps: _sound.kbps,
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
        // Nothing is rendered: the canvas goes as itself, declared at the canvas's
        // size because a receiver lays out a box before it has anything to put in
        // it. With its pictures and media, when it has any (see canvas_bundle.dart),
        // since their ids point at a store only the sender has; with none it stays
        // plain JSON.
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

  /// _publish renders and then sends, and reports the result itself. The
  /// snackbar is taken before the first await: after a long render the context
  /// may be unmounted. Every branch re-checks mounted after its own await, and
  /// the finally clears _busy however it ends.
  Future<void> _publish() async {
    var snackbar = SnackBarModel.of(context);
    // Remembered as it is published, so the next canvas opens the sheet the
    // same way.
    _prefs?.publish = _settings;
    setState(() {
      _busy = true;
      _progress = "Rendering…";
    });

    try {
      // The encoder is the likeliest thing to have gone wrong on a video:
      // "unable to render" would send somebody to their canvas, not their
      // machine.
      if (_needsFfmpeg) {
        setState(() => _progress = _as == PublishAs.audio
            ? "Mixing the sound…"
            : "Encoding the video…");
      }
      // Every shape it is laid out for, each rendered from the document laid
      // out for that shape (see CanvasDocument.forShape), the one on screen
      // among them.
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
          var record = await shareInFiles(export, _suggestedName, _record);
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

  /// _canPublishEveryShape is whether the choice is worth offering: a canvas
  /// laid out for more than one shape, going somewhere that can hold several.
  bool get _canPublishEveryShape =>
      widget.document.targets.length > 1 &&
      (_to == PublishTo.file || _to == PublishTo.chat);

  /// _publishEveryShape renders the canvas once per shape and sends the lot:
  /// one folder asked for, or one chat message per shape, reported as a set
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

  /// _remember keeps what a publish produced: on screen always, so the button
  /// says Update at once (and an unsaved canvas just shared shows Unpublish
  /// while the sheet is open); on disk only where there is a canvas to file it
  /// against.
  Future<void> _remember(PublishRecord record) async {
    setState(() => _record = record);
    if (!_canRecord) return;
    await PublishRecords.write(widget.folder ?? "", widget.name!, record);
  }

  /// _unpublish takes back what was published to the chosen destination: only
  /// the two that can be taken back, not a saved file or a sent message.
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

  /// _isPublishedHere is whether the chosen destination already holds a copy,
  /// which is what turns Publish into Update.
  bool get _isPublishedHere => switch (_to) {
        PublishTo.shared => _record.hasShare,
        PublishTo.library => _record.hasDocument,
        _ => false,
      };

  /// The sheet is one scrolling column in a fixed-width dialog, not a route of
  /// its own, so the canvas being published stays in sight.
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
              // The two questions in order, with the settings for the first between
              // them: what it is, how big and in what format, then where it goes.
              // Anything that would go wrong is said where the choice that caused it
              // is. A dropdown rather than four rows: only the chosen one keeps its
              // description underneath.
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
              // Said where the choice is rather than after a long wait: a video
              // with no encoder cannot be published.
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
              if (_to == PublishTo.library)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
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
              // The size line, the reason the sheet estimates anything: checked before
              // a press that may take a minute, and changing as the scale and format
              // do.
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
                  // The size of the file, which is the export size and not
                  // the design's own space.
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

  /// _sceneControls choose how much of a document with several canvases goes:
  /// nothing on a document with one. Under "Publish as" rather than beside the
  /// destination: a range of scenes is a different thing made, not a different
  /// place to send it.
  List<Widget> _sceneControls(ThemeNotifier theme) {
    var document = widget.document;
    if (!document.hasScenes) return const [];
    var count = document.allScenes.length;

    /// name says which canvas a number is, so a document whose scenes are
    /// named does not make anybody count rows to find scene four.
    String name(int index) {
      var label = document.allScenes[index].name.trim();
      return label.isEmpty ? "Scene ${index + 1}" : "${index + 1}. $label";
    }

    // A still is one canvas whatever happens, so the only question worth
    // asking is which one.
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
                  // A range that runs backwards is not a range: the far end follows.
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

  /// _formatControls is the settings for whatever is being made: a branch per
  /// kind rather than every control shown and some disabled, since a greyed-out
  /// row still reads as a setting somebody is failing to reach.
  List<Widget> _formatControls(ThemeNotifier theme) {
    switch (_as) {
      case PublishAs.image:
        return [
          Row(children: [
            Expanded(
              // One list rather than a format and a "make it a PDF" switch: three
              // answers to one question, seen at once.
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
                // Only a sheet of paper has a second way up: a page cut to the
                // canvas is the canvas's shape.
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
          // playFrames and the document being published, not the canvas in
          // front of the reader: all the scenes end to end, or the one chosen.
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
          const SizedBox(height: 10),
          ..._soundControls(theme,
              fixedRate: _videoFormat == VideoFormat.webm ? 48000 : null),
          _note(
              theme,
              "${_runNote()} A video keeps every colour, where a GIF has 256, "
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
          Row(children: [
            Expanded(
              child: _dropdown<DocumentAs>(
                theme,
                "Format",
                _documentAs,
                [for (var d in DocumentAs.values) (d, d.label)],
                (v) => setState(() => _documentAs = v),
              ),
            ),
          ]),
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
                  // A book's page is the canvas and nothing else: an EPUB is laid out
                  // at the design's size and the reader fits it to the screen.
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
          Txt.S("${_documentAs.description}. "
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

  /// _hasTimedSound is whether anything on the timeline can be heard: a
  /// sound or a video placed on a channel, in any scene or on the master.
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
        // The sound brought to a loudness, measured over the whole mix --
        // see the mixer's Loudness slot, which starts it.
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

  /// _pageLabel is the sheet's size in inches, the only unit a page means
  /// anything in: a canvas laid out at 1280 pixels is a thirteen-inch page.
  String _pageLabel() {
    var page =
        pageFor(_paper, widget.document.size.size, orientation: _orientation);
    return "${(page.width / 72).toStringAsFixed(1)} × "
        "${(page.height / 72).toStringAsFixed(1)} inches";
  }

  /// _scaleField is shared by the still and the animation, in multiples of
  /// the canvas rather than a pixel width: "double" can be pictured, a pixel
  /// width is a sum against a size to look up.
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

  List<Widget> _chatControls(ThemeNotifier theme) {
    var client = context.watch<ClientModel>();
    var chats = client.activeChats.sorted;
    // Defaulted here, since the chat list is not available until this runs,
    // and without setState on purpose: the dropdown below draws this very
    // value, and a setState during build is an error.
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

  /// _option is one choice in either list, written out rather than a
  /// RadioListTile, whose groupValue and onChanged are deprecated in favour of
  /// a RadioGroup ancestor.
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

  /// _dropdown is a labelled choice: a bare DropdownButton, since a
  /// DropdownButtonFormField keeps its own copy of the value and goes stale
  /// when this dialog's state changes underneath it.
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

  // The rest are the sheet's own small pieces: a section heading, a quiet
  // line of explanation, a warning, and a slider with its value beside it.
  // Local rather than from ui/controls.dart, which is built for the
  // sidebar's narrow bands.

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

  /// _warning is the one thing on this sheet somebody has to read: drawn in
  /// the error colour on a tint of it, a band that contrasts whatever the
  /// palette. Not tertiary, which is a panel background in this app and made
  /// the warning unreadable.
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
