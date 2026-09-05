import 'dart:convert';

import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/publish_record.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// publish_sheet.dart is the Publish button's dialog: what to make, and where
// to send it.
//
// Two questions in one sheet, deliberately. "Publish as a GIF" and "publish
// into a chat" are not independent -- a GIF at 2400px is not going into a chat
// message, and the sheet has to be able to say so before anything is rendered.
// Splitting them into two steps would mean finding that out on the second one.
//
// Everything is estimated until Publish is pressed, and the estimate is
// labelled as one. Rendering a 200-frame GIF to find out how big it is takes
// as long as publishing it.

/// PublishAs is what to make.
///
/// In order of how much of the canvas survives: a picture of one frame, a
/// picture of all of them, or the canvas itself. The last is the cheapest and
/// the most capable and is still last, because it is the one that needs the
/// reader on the other end to have Bison Relay -- an image is what can be
/// shown to anyone.
enum PublishAs {
  image("Image", "A single frame as a PNG or a JPEG"),
  animation("Animation", "Every frame as an animated GIF"),
  video("Video", "Every frame as an MP4 or a WebM, at full colour"),
  interactive("Interactive canvas",
      "The canvas itself, with its pictures, to open and edit again");

  final String label;
  final String description;
  const PublishAs(this.label, this.description);
}

/// PublishTo is where it goes.
///
/// Four destinations rather than one save dialog, because three of them are
/// things Bison Relay can do that a file cannot: a canvas in a chat, a canvas
/// a post can embed, a canvas somebody can fetch from Files. Saving to disk is
/// the one that leaves the app, and it is first because it is the one that
/// always works -- the other three each need something set up.
enum PublishTo {
  file("Save to a file", Icons.download_outlined),
  chat("Send to a chat", Icons.chat_outlined),
  library("Add to the post library", Icons.menu_book_outlined),
  shared("Share in Files", Icons.folder_shared_outlined);

  final String label;
  final IconData icon;
  const PublishTo(this.label, this.icon);
}

/// showPublishSheet opens the dialog for [document].
///
/// [folder] and [name] are where the canvas is saved, and are what the publish
/// record is keyed on -- an unsaved canvas can still be published, it just
/// cannot be updated afterwards, because there is nothing to hang the record
/// on. The sheet says so rather than refusing.
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

/// _PublishSheet is the dialog itself. Private: everything outside goes
/// through showPublishSheet, so there is one way to open it and one place the
/// arguments it needs are listed.
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
  PublishTo _to = PublishTo.file;

  // The still settings, then the animation's. Kept side by side rather than
  // in one settings object per kind, because switching between Image and
  // Animation and back has to find both exactly as they were left -- somebody
  // comparing the two sizes does that several times in a row.
  EmbedFormat _format = EmbedFormat.png;
  int _quality = 85;
  double _scale = 1;

  bool _dither = true;
  int _colors = 256;
  bool _loop = true;

  VideoFormat _videoFormat = VideoFormat.mp4;
  VideoQuality _videoQuality = VideoQuality.balanced;

  /// _ffmpeg is whether there is an encoder to make an MP4 with, which is not
  /// known until it has been looked for. Assumed absent until the look comes
  /// back, so the sheet never offers something and then takes it away.
  bool _ffmpeg = false;

  ChatModel? _chat;
  String _caption = "";

  /// _record is what was published from this canvas before, which is what
  /// makes Publish say Update and puts an Unpublish button in the corner.
  PublishRecord _record = const PublishRecord();

  /// _busy disables every control while a render is running. A GIF takes long
  /// enough that a second press is a real possibility, and it would render the
  /// whole thing twice and publish whichever finished last.
  bool _busy = false;
  String _progress = "";

  /// _canRecord is whether there is anywhere to keep [_record]. The record is
  /// filed under the canvas's folder and name, so a canvas that has never been
  /// saved can be published but not updated afterwards.
  bool get _canRecord => widget.name != null;

  @override
  void initState() {
    super.initState();
    // A still document should not default to offering an animation, and an
    // animated one almost always wants to be one.
    if (widget.document.isAnimated) _as = PublishAs.animation;
    _loadRecord();
    _measurePictures();
    // Asked once, here, rather than in build: it is a process launch, and
    // build runs on every keystroke in the caption field.
    ffmpegPath().then((found) {
      if (mounted) setState(() => _ffmpeg = found != null);
    });
  }

  /// _loadRecord reads what this canvas published before, if anything.
  ///
  /// Not awaited by initState -- the sheet opens immediately and fills this in
  /// when it arrives, which is a button that changes from Publish to Update a
  /// moment later rather than a dialog that takes a moment to appear.
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
        PublishAs.image => estimateStillBytes(widget.document, scale: _scale),
        PublishAs.animation =>
          estimateAnimationBytes(widget.document, scale: _scale),
        PublishAs.video => estimateVideoBytes(widget.document,
            scale: _scale, format: _videoFormat, quality: _videoQuality),
        // An interactive canvas is the document itself, which is a known
        // quantity rather than an estimate -- so this one is exact, and the
        // label below says so. The pictures are added at their stored size,
        // which is what the bundle will carry: they go in without being
        // deflated again, being compressed already.
        PublishAs.interactive =>
          widget.document.encode().length + _pictureBytes,
      };

  /// _pictureBytes is what the canvas's pictures weigh, which is nearly all
  /// of a bundle. Measured once when the sheet opens rather than per build:
  /// it is a read of every picture in the canvas.
  int _pictureBytes = 0;

  Future<void> _measurePictures() async {
    var total = 0;
    for (var id in widget.document.assetIds) {
      total += (await CanvasAssets.load(id))?.length ?? 0;
    }
    if (mounted) setState(() => _pictureBytes = total);
  }

  /// _tooBigForChat is the one warning the sheet gives before anything is
  /// rendered, because it is the one failure that would otherwise happen after
  /// a long wait and produce nothing.
  bool get _tooBigForChat {
    if (_to != PublishTo.chat) return false;
    // Base64 is four bytes of text for every three of data, and the markup
    // itself is a few dozen more.
    return _estimate * 4 / 3 > 900000;
  }

  /// _render makes the bytes, and is the only slow thing here.
  ///
  /// Both raster paths go through export/canvas_export.dart, which is also
  /// what the embed and the thumbnail use -- so what is published is the same
  /// picture the canvas draws, at a different size. Only the GIF reports
  /// progress, because it is the only one where there is any to report: a
  /// still is one frame and is done before a progress line could be read.
  Future<CanvasExport?> _render() async {
    switch (_as) {
      case PublishAs.image:
        return renderImage(
          widget.document,
          frame: widget.frame,
          scale: _scale,
          images: widget.images,
          options: EmbedOptions(format: _format, quality: _quality),
        );
      case PublishAs.animation:
        return renderGif(
          widget.document,
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
          widget.document,
          scale: _scale,
          images: widget.images,
          format: _videoFormat,
          quality: _videoQuality,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _progress = "Rendering frame $done of $total…");
            }
          },
        );
      case PublishAs.interactive:
        // Nothing is rendered: the canvas goes as itself. It is declared as
        // the canvas's size all the same, because whatever receives it lays
        // out a box before it has anything to put in it.
        //
        // With its pictures when it has any -- see canvas_bundle.dart. Without
        // them the file opened on somebody else's machine with a grey
        // placeholder where every photograph had been, because the ids in it
        // pointed at a store only the sender had. A canvas with no pictures
        // stays the plain readable JSON it has always been.
        if (widget.document.assetIds.isEmpty) {
          return CanvasExport(
            utf8.encode(widget.document.encode()),
            "application/json",
            width: widget.document.size.width,
            height: widget.document.size.height,
          );
        }
        return CanvasExport(
          await packCanvas(widget.document),
          bundleMime,
          width: widget.document.size.width,
          height: widget.document.size.height,
        );
    }
  }

  /// _publish renders and then sends, and reports the result itself.
  ///
  /// The snackbar is taken before the first await. Reading it afterwards means
  /// reaching for an InheritedWidget through a context whose element may have
  /// been unmounted by a render that took a minute, which is the exception
  /// nobody sees until a slow publish is cancelled.
  ///
  /// Every branch below re-checks mounted after its own await for the same
  /// reason, and the finally clears _busy however it ends -- an error that
  /// left the sheet disabled would be a dialog that can only be closed by
  /// cancelling.
  Future<void> _publish() async {
    var snackbar = SnackBarModel.of(context);
    setState(() {
      _busy = true;
      _progress = "Rendering…";
    });

    try {
      // The encoder is the likeliest thing to have gone wrong on a video, and
      // "unable to render" would send somebody looking at their canvas rather
      // than at their machine.
      if (_as == PublishAs.video) {
        setState(() => _progress = "Encoding the video…");
      }
      var export = await _render();
      if (!mounted) return;
      if (export == null) {
        snackbar.error(_as == PublishAs.video && !_ffmpeg
            ? ffmpegHelp
            : "Unable to render the canvas.");
        return;
      }

      switch (_to) {
        case PublishTo.file:
          var written = await saveToDisk(export, _suggestedName);
          if (!mounted) return;
          // A cancelled save dialog is not a failure and must not be reported
          // as one -- the reader knows they cancelled.
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

  /// _remember keeps what a publish produced, both on screen and on disk.
  ///
  /// On screen always, so the button says Update immediately; on disk only
  /// when there is a canvas to file it against. An unsaved canvas that has
  /// just been shared still shows its Unpublish button for as long as the
  /// sheet is open, which is the honest thing -- the share exists.
  Future<void> _remember(PublishRecord record) async {
    setState(() => _record = record);
    if (!_canRecord) return;
    await PublishRecords.write(widget.folder ?? "", widget.name!, record);
  }

  /// _unpublish takes back what was published to the chosen destination.
  ///
  /// Only the two that can be taken back. A file that has been saved and a
  /// message that has been sent are gone from here, and offering to undo them
  /// would be a button that lies.
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

  /// The sheet is one scrolling column in a fixed-width dialog rather than a
  /// page of its own. It is a decision with an answer, taken in the middle of
  /// working on a canvas, and a full-screen route would lose sight of the
  /// thing being published.
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
              // The two questions in order, with the settings for the first
              // between them: what it is, then how big and in what format,
              // then where it goes. Anything that would go wrong -- a
              // one-frame animation, an unsaved canvas, a chat message too
              // large to send -- is said where the choice that caused it is,
              // rather than collected into one list at the bottom.
              _heading("Publish as"),
              for (var option in PublishAs.values)
                _option(
                  theme,
                  selected: option == _as,
                  label: option.label,
                  description: option.description,
                  onTap: _busy ? null : () => setState(() => _as = option),
                ),
              // Said where the choice is rather than after a long wait: a
              // video with no encoder to make it cannot be published, and the
              // button below says so too.
              if (_as == PublishAs.video && !_ffmpeg)
                _warning(theme, ffmpegHelp),
              if ((_as == PublishAs.animation || _as == PublishAs.video) &&
                  !widget.document.isAnimated)
                _warning(
                    theme,
                    "This canvas is a single frame, so the animation will be "
                    "one frame long. Add frames on the timeline first."),
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
              // The size line, which is the whole reason the sheet estimates
              // anything. It is what a reader checks before pressing a button
              // that may take a minute, and it changes as the scale and the
              // format do -- so the effect of each setting can be seen without
              // publishing anything.
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
                  "${(widget.document.size.width * _scale).round()} × "
                  "${(widget.document.size.height * _scale).round()}",
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
              _busy || (_as == PublishAs.video && !_ffmpeg) ? null : _publish,
          child: Text(_isPublishedHere ? "Update" : "Publish"),
        ),
      ],
    );
  }

  /// _formatControls is the settings for whatever is being made.
  ///
  /// A branch per kind rather than every control shown and some of them
  /// disabled: quality means nothing to a GIF and dithering means nothing to
  /// a PNG, and a greyed-out row still reads as a setting somebody is failing
  /// to reach.
  List<Widget> _formatControls(ThemeNotifier theme) {
    switch (_as) {
      case PublishAs.image:
        return [
          Row(children: [
            Expanded(
              child: _dropdown<EmbedFormat>(
                  theme,
                  "Format",
                  _format,
                  const [
                    (EmbedFormat.png, "PNG (lossless)"),
                    (EmbedFormat.jpeg, "JPEG (smaller)"),
                  ],
                  (v) => setState(() => _format = v)),
            ),
            const SizedBox(width: 12),
            Expanded(child: _scaleField(theme)),
          ]),
          if (_format == EmbedFormat.jpeg)
            _slider(theme, "Quality", _quality.toDouble(), 20, 100,
                (v) => setState(() => _quality = v.round()),
                suffix: "$_quality"),
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
          _note(
              theme,
              "${widget.document.frames} frames at "
              "${widget.document.frameRate} per second — "
              "${widget.document.durationSeconds.toStringAsFixed(1)} seconds."),
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
          Row(children: [
            Expanded(
              child: _dropdown<VideoQuality>(
                  theme,
                  "Quality",
                  _videoQuality,
                  [for (var q in VideoQuality.values) (q, q.label)],
                  (v) => setState(() => _videoQuality = v)),
            ),
            // The second half is deliberately empty. A dropdown stretched to
            // the width of the dialog looks like it holds more than three
            // words, and the two rows line up as one grid this way.
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ]),
          _note(
              theme,
              "${widget.document.frames} frames at "
              "${widget.document.frameRate} per second — "
              "${widget.document.durationSeconds.toStringAsFixed(1)} seconds. "
              "A video keeps every colour, where a GIF has 256, and is "
              "usually much smaller. ${_videoFormat.note}"),
        ];

      case PublishAs.interactive:
        return [
          Txt.S(widget.document.assetIds.isEmpty
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

  /// _scaleField is shared by the still and the animation, and is multiples of
  /// the canvas rather than a pixel width.
  ///
  /// The canvas has a size of its own that the reader chose, so "double" is a
  /// thing they can picture; a box wanting a number in pixels is a sum they
  /// have to do first, against a size they would have to go and look up.
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
    // Defaulted here rather than in initState, because the chat list is not
    // available until this runs. Assigned without setState on purpose: the
    // dropdown below is about to draw this very value, so there is nothing
    // stale to rebuild -- and a setState during build would be an error.
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

  /// _option is one choice in either list.
  ///
  /// Written out rather than using RadioListTile, whose groupValue and
  /// onChanged were deprecated in favour of a RadioGroup ancestor -- which
  /// would mean wrapping two unrelated lists in two inherited widgets for a
  /// row that is a circle, a label and a tap.
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

  /// _dropdown is a labelled choice.
  ///
  /// A bare DropdownButton rather than a DropdownButtonFormField, which keeps
  /// its own copy of the value and would go on showing whatever was chosen in
  /// it even after this dialog's state changed underneath.
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
  // line of explanation, a warning in the theme's tertiary colour, and a
  // slider with its value beside it. Local rather than from ui/controls.dart,
  // which is built for the sidebar's narrow bands and looks wrong at a
  // dialog's width.

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

  /// _warning is the one thing on this sheet somebody has to read.
  ///
  /// Drawn in the error colour on a tint of it, rather than as coloured text
  /// on the dialog. It was tertiary, which is not an accent in this app at all
  /// -- see the theming system, where tertiary is the *background* of a
  /// settings panel and is 0xFF232030 in the dark theme. Dark grey text on a
  /// dark grey sheet: the warning was drawn every time and could not be read
  /// once, which is worse than not drawing it, because the button it explains
  /// is disabled and nothing says why.
  ///
  /// The band is what makes it independent of the palette. Whatever the reader
  /// has chosen, error contrasts with surface and the tint is made from the
  /// same colour, so the two cannot come out the same as each other.
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
