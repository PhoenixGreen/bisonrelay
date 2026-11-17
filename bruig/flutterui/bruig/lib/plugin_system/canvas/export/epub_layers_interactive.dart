part of 'epub_layers.dart';

// What runs or reacts in the reader: web pages and code panes run live in
// frames, and the clips and sounds an element plays on a click or when another
// clip ends. Part of epub_layers.dart.

/// EpubFrame is a web page run live in the book: [html] in [rect] (page
/// pixels), over the picture of its last run.
class EpubFrame {
  final Rect rect;
  final String html;
  const EpubFrame(this.rect, this.html);
}

/// _liveFrames are [e]'s pages in frames of their own in a book: a Run
/// panel's web page, run live (without the app's console catcher), where it
/// has run one; each pane of a Code panel, its file whole, to be scrolled.
List<EpubFrame> _liveFrames(
    CanvasElement e, CanvasDocument page, double pixels) {
  Rect onPage(Rect r) => Rect.fromLTRB(
      r.left * pixels, r.top * pixels, r.right * pixels, r.bottom * pixels);
  if (e is CodeElement) {
    var boxes = codeBoxes(e, e.bounds);
    return [
      for (var (i, p) in e.shownPanes.indexed)
        if (i < boxes.panes.length)
          if (p.shows case var id?)
            if (e.file(id) case var f?)
              EpubFrame(onPage(boxes.panes[i].code),
                  codeFileHtml(e, f, px: e.fontSize * pixels)),
    ];
  }
  if (e is! CodeRunElement || e.result == null) return const [];
  var code = page.elementById(e.code);
  if (code is! CodeElement) return const [];
  var entry = entryFile(e, code);
  if (entry == null || runnerOf(e, code) != CodeRunner.web) return const [];
  var preview = codeRunBoxes(e, e.bounds, runner: CodeRunner.web).preview;
  if (preview == null) return const [];
  // Sealed off the network as it is in the app (see sealed): a reader of
  // the book must not be told to whoever wrote the page.
  return [EpubFrame(onPage(preview), sealed(webPage(code, entry, head: "")))];
}

/// _codeRunSpan is, while a page's layers are made, each Run panel's frame
/// either side of its run: set by codeRunSpans.
Map<String, (int, int)> _codeRunSpan = const {};

/// codeRunSpans notes when each of [doc]'s Run panels runs, for the look of
/// its layer to change there.
void codeRunSpans(CanvasDocument doc) {
  var rate = math.max(1, doc.frameRate);
  _codeRunSpan = {
    for (var r in doc.elements.whereType<CodeRunElement>())
      if (runAt(
              r,
              doc.elementById(r.code) is CodeElement
                  ? doc.elementById(r.code) as CodeElement
                  : null)
          case var t? when t > 0)
        r.id: (
          math.max(0, (t * rate).floor() - 1),
          (t * rate).ceil().clamp(0, math.max(0, doc.frames - 1)).toInt()
        ),
  };
}

/// _reactionClips are [e]'s clips a book plays on a click on a named
/// element or another clip ending; not sounds, which go with them.
List<MotionClip> _reactionClips(CanvasElement e) => [
      for (var c in e.base.motion.clips)
        if (!c.isSound &&
            c.triggers.any((t) =>
                (t.kind == ClipTriggerKind.clicked && t.target.isNotEmpty) ||
                t.kind == ClipTriggerKind.clipEnds))
          c,
    ];

/// _reactionSounds are [elements]' reaction sounds, a file each by asset:
/// MP3 or AAC as is, anything else made AAC by ffmpeg, or left out.
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
