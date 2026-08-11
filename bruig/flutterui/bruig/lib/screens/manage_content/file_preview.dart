import 'dart:io';

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
class FilePreview extends StatelessWidget {
  final String filePath;
  final VoidCallback onClose;
  const FilePreview({
    required this.filePath,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: "Close preview",
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(path.basename(filePath),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
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
    ]);
  }

  Widget _body(BuildContext context) {
    var file = File(filePath);
    if (!file.existsSync()) {
      return const Center(child: Text("File no longer exists on disk"));
    }

    switch (fileKindOf(filePath)) {
      case FileKind.image:
        // Zoomable: a photo shown at page size is otherwise less useful
        // than the same photo in any image viewer.
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
              child: Image.file(file,
                  errorBuilder: (context, error, stack) =>
                      Center(child: Text("Unable to read image: $error")))),
        );
      case FileKind.pdf:
        return PdfViewer.file(filePath);
      case FileKind.video:
        return _VideoPreview(file: file);
      case FileKind.text:
        return _TextPreview(file: file);
      case FileKind.other:
        return const Center(child: Text("No preview for this file type"));
    }
  }
}

// _TextPreview reads the file itself rather than streaming it, so it caps
// what it will read: a preview of a huge log is the top of it, and holding
// the whole thing in memory to show one screenful is not worth it.
class _TextPreview extends StatefulWidget {
  final File file;
  const _TextPreview({required this.file});

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  static const _maxBytes = 512 * 1024;

  String? content;
  String? error;
  bool truncated = false;

  @override
  void initState() {
    super.initState();
    load();
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
  const _VideoPreview({required this.file});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? controller;
  String? error;

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
  }

  @override
  void dispose() {
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
