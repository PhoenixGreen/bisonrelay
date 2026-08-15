import 'dart:async';
import 'dart:io';

import 'package:bruig/screens/manage_content/file_notes.dart';
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
// It also keeps a reader's place. Where they had got to is recorded as they
// go (see FileNotes.position), but nothing jumps on its own: a file always
// opens at its beginning, and the Continue button in the header is how you
// go back to where you were. A document that silently opened four hundred
// pages in would be worse than one that forgot.
class FilePreview extends StatefulWidget {
  final String filePath;
  final VoidCallback onClose;
  const FilePreview({
    required this.filePath,
    required this.onClose,
    super.key,
  });

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  FileNotes notes = FileNotes.empty;
  bool showNotes = false;

  /// resumeTo is the saved position, handed to the view below when Continue
  /// is pressed and cleared once it has been used, so pressing it is a
  /// one-way trip rather than something that keeps yanking the view back.
  double? resumeTo;

  /// _kind names the unit this file's position is measured in -- see
  /// FileNotes.position. The FileKind's own name, so it can never disagree
  /// with the view that is doing the measuring.
  String get _kind => fileKindOf(widget.filePath).name;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void didUpdateWidget(FilePreview old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      setState(() {
        notes = FileNotes.empty;
        resumeTo = null;
      });
      _loadNotes();
    }
  }

  Future<void> _loadNotes() async {
    var loaded = await FileNotesStore.load(widget.filePath);
    if (mounted) setState(() => notes = loaded);
  }

  /// _recordPosition writes where the reader has got to, merging into
  /// whatever else the sidecar holds -- the notes panel below writes to the
  /// same file, and re-reading first is what stops one of them erasing the
  /// other's work.
  ///
  /// Kept off the UI thread's critical path deliberately: this is called as
  /// the reader scrolls or plays, and none of it is worth a rebuild.
  Future<void> _recordPosition(double position) async {
    if (!mounted) return;
    var existing = await FileNotesStore.load(widget.filePath);
    if (existing.position == position) return;
    notes = existing.copyWith(position: position, positionKind: _kind);
    await FileNotesStore.save(widget.filePath, notes);
  }

  /// _resumeLabel names what Continue will actually do, in the units of the
  /// thing being resumed -- "page 12" is a promise, "continue" alone is not.
  String? get _resumeLabel {
    var at = notes.positionFor(_kind);
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: "Close preview",
            onPressed: widget.onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(path.basename(widget.filePath),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (resume != null)
            TextButton.icon(
              icon: const Icon(Icons.bookmark, size: 16),
              label: Text(resume),
              onPressed: () => setState(() {
                resumeTo = notes.position;
              }),
            ),
          // The note button is here as well as on the list rows, because
          // notes are most worth taking while the thing is in front of you.
          FileNotesButton(
            filePath: widget.filePath,
            open: showNotes,
            onPressed: () => setState(() => showNotes = !showNotes),
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
      if (showNotes)
        FileNotesPanel(
          filePath: widget.filePath,
          height: 180,
          onClose: () => setState(() => showNotes = false),
        ),
    ]);
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
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
              child: Image.file(file,
                  errorBuilder: (context, error, stack) =>
                      Center(child: Text("Unable to read image: $error")))),
        );
      case FileKind.pdf:
        return _PdfPreview(
          filePath: widget.filePath,
          resumeToPage: resumeTo?.round(),
          onPage: (p) => _recordPosition(p.toDouble()),
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
  final ValueChanged<int> onPage;
  const _PdfPreview({
    required this.filePath,
    required this.resumeToPage,
    required this.onPage,
  });

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  final controller = PdfViewerController();

  @override
  void didUpdateWidget(_PdfPreview old) {
    super.didUpdateWidget(old);
    var page = widget.resumeToPage;
    // Only on the edge -- rebuilding with the same target must not keep
    // dragging the reader back to it after they have paged on from there.
    if (page != null && page != old.resumeToPage && controller.isReady) {
      controller.goToPage(pageNumber: page);
    }
  }

  @override
  Widget build(BuildContext context) => PdfViewer.file(
        widget.filePath,
        controller: controller,
        params: PdfViewerParams(
          onPageChanged: (page) {
            if (page != null) widget.onPage(page);
          },
        ),
      );
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
