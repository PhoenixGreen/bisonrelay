import 'dart:async';
import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/screens/manage_content/reading_position.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

// FileKind is what a downloaded file can be shown as inside the app.
// Decided by extension: the alternative is sniffing the contents, which
// costs a read of every row in the list to decide whether to offer a
// button.
enum FileKind { image, text, pdf, video, other }

const _imageExts = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"};
const _videoExts = {".mp4", ".mov", ".m4v", ".webm", ".mkv"};
const _textExts = {
  ".txt",
  ".md",
  ".json",
  ".yaml",
  ".yml",
  ".csv",
  ".log",
  ".xml",
  ".ini",
  ".conf",
  ".go",
  ".dart",
  ".py",
  ".js",
  ".ts",
  ".sh",
};

FileKind fileKindOf(String filePath) {
  var ext = path.extension(filePath).toLowerCase();
  if (_imageExts.contains(ext)) return FileKind.image;
  if (_videoExts.contains(ext)) return FileKind.video;
  if (ext == ".pdf") return FileKind.pdf;
  if (_textExts.contains(ext)) return FileKind.text;
  return FileKind.other;
}

// FilePreview shows a downloaded file in the page it was listed on, rather
// than handing it to whatever the OS has registered for it. Opening a file
// externally is still there beside it -- this is for a look at what
// something is without leaving the app.
//
// It also keeps a reader's place, in two different senses that are worth
// keeping apart. Across a *session* -- stepping over to Chat and coming back
// -- the document is simply still open where it was, restored from
// FilePreviewNavModel without anything being asked for. Across a *closing*,
// where they had got to is written beside the file (see ReadingPosition)
// and nothing jumps on its own: the file opens at its beginning and the
// Continue button in the header is how you go back. A document that silently
// opened four hundred pages in would be worse than one that forgot; a
// document that closed itself because you glanced at a message would be
// worse still.
class FilePreview extends StatefulWidget {
  final String filePath;
  final VoidCallback onClose;

  /// nav is where the session's own position and zoom are kept, so they
  /// outlive this widget being rebuilt by its route.
  final ManageContentNavModel nav;
  const FilePreview({
    required this.filePath,
    required this.onClose,
    required this.nav,
    super.key,
  });

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  ReadingPosition mark = ReadingPosition.empty;

  /// zoom is the share of the fit view the document is drawn at -- 1.0 being
  /// the whole page fitted to the panel, which is how it opens.
  late double zoom = widget.nav.zoom;

  /// page/pageCount are the PDF's own, for the counter in the header. Null
  /// until the document has loaded, and for every other kind of file.
  int? page;
  int? pageCount;

  /// resumeTo is the saved position, handed to the view below when Continue
  /// is pressed and cleared once it has been used, so pressing it is a
  /// one-way trip rather than something that keeps yanking the view back.
  double? resumeTo;

  /// _kind names the unit this file's position is measured in -- see
  /// ReadingPosition.position. The FileKind's own name, so it can never
  /// disagree with the view that is doing the measuring.
  String get _kind => fileKindOf(widget.filePath).name;

  @override
  void initState() {
    super.initState();
    _loadMark();
    // Coming back to a page that was already open: pick the document up
    // where it was left rather than at the top. Distinct from Continue,
    // which is for a document being opened again from cold.
    if (widget.nav.path == widget.filePath && widget.nav.position > 0) {
      resumeTo = widget.nav.position;
    }
  }

  @override
  void didUpdateWidget(FilePreview old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      setState(() {
        mark = ReadingPosition.empty;
        resumeTo = null;
      });
      _loadMark();
    }
  }

  Future<void> _loadMark() async {
    var loaded = await ReadingPositionStore.load(widget.filePath);
    if (mounted) setState(() => mark = loaded);
  }

  /// _recordPosition writes where the reader has got to.
  ///
  /// Kept off the UI thread's critical path deliberately: this is called as
  /// the reader scrolls or plays, and none of it is worth a rebuild.
  Future<void> _recordPosition(double position) async {
    // The session's own copy first, and unconditionally: it is what restores
    // the view on coming back to this page, and it costs nothing.
    widget.nav.remember(position: position);
    if (!mounted) return;
    if (mark.position == position && mark.positionKind == _kind) return;
    mark = mark.copyWith(position: position, positionKind: _kind);
    await ReadingPositionStore.save(widget.filePath, mark);
  }

  void _setZoom(double v) {
    widget.nav.remember(zoom: v);
    setState(() => zoom = v);
  }

  /// _resumeLabel names what Continue will actually do, in the units of the
  /// thing being resumed -- "page 12" is a promise, "continue" alone is not.
  String? get _resumeLabel {
    var at = mark.positionFor(_kind);
    if (at == null) return null;
    return switch (fileKindOf(widget.filePath)) {
      FileKind.pdf => "Continue from page ${at.round()}",
      FileKind.video => "Continue from ${_clock(at)}",
      FileKind.text => "Continue where you left off",
      _ => null,
    };
  }

  static String _clock(double seconds) {
    var d = Duration(seconds: seconds.round());
    var mm = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    var ss = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return d.inHours > 0 ? "${d.inHours}:$mm:$ss" : "$mm:$ss";
  }

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    var resume = _resumeLabel;
    var kind = fileKindOf(widget.filePath);
    // Only the two kinds with a page to scale. Text has a font size rather
    // than a zoom, and a video has neither.
    var zoomable = kind == FileKind.pdf || kind == FileKind.image;
    // Notes taken here are about this document, and the notes button at the
    // foot of the content area opens them. This one line is the whole of what
    // the preview knows about notes; the button and the panel are drawn once,
    // around the whole content area, by NotesHost.
    return NoteTargetScope(
      target: NoteTarget.document(widget.filePath),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          // Wrap rather than Row: the name, the page counter, the zoom and the
          // two buttons do not fit across a narrow panel, and a Row would
          // overflow rather than give way.
          child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: "Close preview",
                  onPressed: widget.onClose,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(path.basename(widget.filePath),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                if (pageCount != null)
                  _PageCounter(
                    page: page ?? 1,
                    pageCount: pageCount!,
                    onGoTo: (p) => setState(() => resumeTo = p.toDouble()),
                  ),
                if (zoomable) _ZoomPicker(zoom: zoom, onChanged: _setZoom),
                if (resume != null)
                  TextButton.icon(
                    icon: const Icon(Icons.bookmark, size: 16),
                    label: Text(resume),
                    onPressed: () => setState(() {
                      resumeTo = mark.position;
                    }),
                  ),
              ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _body(context),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    var file = File(widget.filePath);
    if (!file.existsSync()) {
      return const Center(child: Text("File no longer exists on disk"));
    }

    switch (fileKindOf(widget.filePath)) {
      case FileKind.image:
        // Zoomable: a photo shown at page size is otherwise less useful
        // than the same photo in any image viewer. Nothing to remember --
        // an image has no "where you were".
        return _ImagePreview(file: file, zoom: zoom);
      case FileKind.pdf:
        return _PdfPreview(
          filePath: widget.filePath,
          resumeToPage: resumeTo?.round(),
          zoom: zoom,
          onPage: (p) {
            _recordPosition(p.toDouble());
            // The counter in the header follows the document, so it has to
            // rebuild -- unlike the recording above, which nothing shows.
            if (mounted && p != page) setState(() => page = p);
          },
          onLoaded: (count) {
            if (mounted && count != pageCount) {
              setState(() => pageCount = count);
            }
          },
        );
      case FileKind.video:
        return _VideoPreview(
            file: file, resumeToSeconds: resumeTo, onPosition: _recordPosition);
      case FileKind.text:
        return _TextPreview(
            file: file, resumeToOffset: resumeTo, onOffset: _recordPosition);
      case FileKind.other:
        return const Center(child: Text("No preview for this file type"));
    }
  }
}

// _PdfPreview wraps the PDF viewer with the two things a bookmark needs: a
// controller to jump with, and the page change to record.
class _PdfPreview extends StatefulWidget {
  final String filePath;
  final int? resumeToPage;
  final double zoom;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onLoaded;
  const _PdfPreview({
    required this.filePath,
    required this.resumeToPage,
    required this.zoom,
    required this.onPage,
    required this.onLoaded,
  });

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  final controller = PdfViewerController();

  /// _fitZoom is the scale the document opened at -- the whole page fitted
  /// to the panel, which is what 100% means here. pdfrx's own zoom is an
  /// absolute scale, so the percentages have to be taken against this rather
  /// than against 1.0, which would mean something different at every window
  /// size and page size.
  double? _fitZoom;

  @override
  void didUpdateWidget(_PdfPreview old) {
    super.didUpdateWidget(old);
    var page = widget.resumeToPage;
    // Only on the edge -- rebuilding with the same target must not keep
    // dragging the reader back to it after they have paged on from there.
    if (page != null && page != old.resumeToPage && controller.isReady) {
      controller.goToPage(pageNumber: page);
    }
    if (widget.zoom != old.zoom) _applyZoom();
  }

  void _applyZoom() {
    var fit = _fitZoom;
    if (fit == null || !controller.isReady) return;
    controller.setZoom(controller.centerPosition, fit * widget.zoom);
  }

  @override
  Widget build(BuildContext context) => PdfViewer.file(
        widget.filePath,
        controller: controller,
        params: PdfViewerParams(
          onPageChanged: (page) {
            if (page != null) widget.onPage(page);
          },
          onViewerReady: (document, controller) {
            // The scale it settled on is the fit, and the page count is now
            // known. Both are reported out of the frame that produced them.
            _fitZoom ??= controller.currentZoom;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onLoaded(document.pages.length);
              if (widget.zoom != 1) _applyZoom();
              var page = widget.resumeToPage;
              if (page != null) controller.goToPage(pageNumber: page);
            });
          },
        ),
      );
}

// _ImagePreview is the pinch/drag viewer with the zoom buttons driving the
// same transform, so the two agree instead of fighting: pressing 50% takes
// the picture to half the size it opened at, and dragging from there still
// works.
class _ImagePreview extends StatefulWidget {
  final File file;
  final double zoom;
  const _ImagePreview({required this.file, required this.zoom});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  final _transform = TransformationController();

  @override
  void didUpdateWidget(_ImagePreview old) {
    super.didUpdateWidget(old);
    if (widget.zoom != old.zoom) {
      _transform.value = Matrix4.identity()
        ..scaleByDouble(widget.zoom, widget.zoom, widget.zoom, 1);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        transformationController: _transform,
        // Below 1 so the zoom-out levels are reachable by gesture too, not
        // only by the buttons.
        minScale: 0.2,
        maxScale: 8,
        child: Center(
            child: Image.file(widget.file,
                errorBuilder: (context, error, stack) =>
                    Center(child: Text("Unable to read image: $error")))),
      );
}

/// _ZoomPicker is the 100/50/25% control.
///
/// 100% is the view the document opens at -- the whole page fitted to the
/// panel -- rather than true actual size, so the figure means the same thing
/// whatever the page size and window size are.
class _ZoomPicker extends StatelessWidget {
  static const levels = [1.0, 0.5, 0.25];
  final double zoom;
  final ValueChanged<double> onChanged;
  const _ZoomPicker({required this.zoom, required this.onChanged});

  static String label(double z) => "${(z * 100).round()}%";

  @override
  Widget build(BuildContext context) => Tooltip(
        message: "Zoom, as a share of the page fitted to the panel",
        child: DropdownButton<double>(
          value: levels.contains(zoom) ? zoom : 1.0,
          underline: const SizedBox.shrink(),
          items: [
            for (var l in levels)
              DropdownMenuItem(value: l, child: Txt.S(label(l))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}

/// _PageCounter shows "Page: 25 / 100" and lets the number be typed.
///
/// The field carries the current page rather than being a blank box to fill
/// in: it is the counter, and typing over it is how you go somewhere. Out of
/// range or not a number puts the real page back rather than refusing.
class _PageCounter extends StatefulWidget {
  final int page;
  final int pageCount;
  final ValueChanged<int> onGoTo;
  const _PageCounter({
    required this.page,
    required this.pageCount,
    required this.onGoTo,
  });

  @override
  State<_PageCounter> createState() => _PageCounterState();
}

class _PageCounterState extends State<_PageCounter> {
  late final TextEditingController ctrl =
      TextEditingController(text: "${widget.page}");
  final focus = FocusNode();

  @override
  void didUpdateWidget(_PageCounter old) {
    super.didUpdateWidget(old);
    // Follow the document as it is scrolled, but never while the reader is
    // part-way through typing a number into the box.
    if (widget.page != old.page && !focus.hasFocus) {
      ctrl.text = "${widget.page}";
    }
  }

  @override
  void dispose() {
    ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    var n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > widget.pageCount) {
      ctrl.text = "${widget.page}";
      return;
    }
    widget.onGoTo(n);
  }

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Txt.S("Page: "),
        SizedBox(
          width: 48,
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
            onSubmitted: _submit,
            onTapOutside: (_) {
              focus.unfocus();
              _submit(ctrl.text);
            },
          ),
        ),
        Txt.S(" / ${widget.pageCount}"),
      ]);
}

// _TextPreview reads the file itself rather than streaming it, so it caps
// what it will read: a preview of a huge log is the top of it, and holding
// the whole thing in memory to show one screenful is not worth it.
class _TextPreview extends StatefulWidget {
  final File file;
  // resumeToOffset is a scroll offset to jump to, set when Continue is
  // pressed; onOffset reports where the reader has scrolled to.
  final double? resumeToOffset;
  final ValueChanged<double> onOffset;
  const _TextPreview({
    required this.file,
    required this.resumeToOffset,
    required this.onOffset,
  });

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  static const _maxBytes = 512 * 1024;

  String? content;
  String? error;
  bool truncated = false;
  final scrollCtrl = ScrollController();
  Timer? _record;

  @override
  void initState() {
    super.initState();
    scrollCtrl.addListener(_scrolled);
    load();
  }

  // Reported on a timer rather than on every frame of a scroll: this ends
  // in a file write, and a flung scrollbar would otherwise produce hundreds
  // of them for one gesture.
  void _scrolled() {
    if (_record?.isActive ?? false) return;
    _record = Timer(const Duration(milliseconds: 400), () {
      if (mounted && scrollCtrl.hasClients) widget.onOffset(scrollCtrl.offset);
    });
  }

  @override
  void didUpdateWidget(_TextPreview old) {
    super.didUpdateWidget(old);
    var to = widget.resumeToOffset;
    if (to != null && to != old.resumeToOffset && scrollCtrl.hasClients) {
      scrollCtrl.jumpTo(to.clamp(0, scrollCtrl.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _record?.cancel();
    scrollCtrl.dispose();
    super.dispose();
  }

  void load() async {
    try {
      var length = await widget.file.length();
      var bytes = length > _maxBytes
          ? await widget.file.openRead(0, _maxBytes).expand((c) => c).toList()
          : await widget.file.readAsBytes();
      if (!mounted) return;
      setState(() {
        // A file that isn't really text (or is cut mid-character by the
        // cap) decodes with replacement characters rather than throwing.
        content = String.fromCharCodes(bytes);
        truncated = length > _maxBytes;
      });
    } catch (exception) {
      if (mounted) setState(() => error = "$exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Text("Unable to read file: $error"));
    }
    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (truncated)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text("Showing the first 512 KB",
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
          ),
        SelectableText(content!,
            style: const TextStyle(fontFamily: "monospace", fontSize: 13)),
      ]),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final File file;
  // resumeToSeconds is a playback position to seek to, set when Continue is
  // pressed; onPosition reports where playback has reached.
  final double? resumeToSeconds;
  final ValueChanged<double> onPosition;
  const _VideoPreview({
    required this.file,
    required this.resumeToSeconds,
    required this.onPosition,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? controller;
  String? error;
  Timer? _record;

  @override
  void initState() {
    super.initState();
    initController();
  }

  void initController() async {
    var next = VideoPlayerController.file(widget.file);
    try {
      await next.initialize();
    } catch (exception) {
      if (mounted) setState(() => error = "$exception");
      return;
    }
    if (!mounted) {
      next.dispose();
      return;
    }
    // Not auto-played: a preview that starts making noise the moment it
    // opens is a worse default than one more click.
    setState(() => controller = next);
    // Sampled on a timer rather than from the player's own listener, which
    // fires several times a second while playing -- once every few seconds
    // is as close as anyone needs to be put back.
    _record = Timer.periodic(const Duration(seconds: 3), (_) {
      var c = controller;
      if (c != null && c.value.isPlaying) {
        widget.onPosition(c.value.position.inMilliseconds / 1000);
      }
    });
  }

  @override
  void didUpdateWidget(_VideoPreview old) {
    super.didUpdateWidget(old);
    var to = widget.resumeToSeconds;
    if (to != null && to != old.resumeToSeconds) {
      controller?.seekTo(Duration(milliseconds: (to * 1000).round()));
    }
  }

  @override
  void dispose() {
    _record?.cancel();
    // The position at the moment of closing, which the periodic sample will
    // usually have just missed -- closing a video is exactly when where you
    // got to matters most.
    var c = controller;
    if (c != null && c.value.isInitialized) {
      widget.onPosition(c.value.position.inMilliseconds / 1000);
    }
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Text("Unable to play video: $error"));
    }
    var ctrl = controller;
    if (ctrl == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        ),
      ),
      VideoProgressIndicator(ctrl, allowScrubbing: true),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: Icon(ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () =>
              setState(() => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play()),
        ),
        IconButton(
          icon: const Icon(Icons.replay),
          tooltip: "Restart",
          onPressed: () => ctrl.seekTo(Duration.zero),
        ),
      ]),
    ]);
  }
}
