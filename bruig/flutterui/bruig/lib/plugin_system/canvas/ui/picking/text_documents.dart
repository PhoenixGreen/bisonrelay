import 'dart:async';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/foundation.dart';

// text_documents.dart keeps a document-backed text element up to date. The
// words are copied into the element (see TextDocumentRef), so a poll while the
// canvas is open reads each referenced document and writes back only what
// differs. A poll because the library is a folder of files with no change
// feed; a canvas with no document-backed element does no work.

/// canvasDocumentPoll is how often the library is looked at while a canvas is
/// open: cheap, and quick enough that an edit made in Writing is there on
/// switching back.
const Duration canvasDocumentPoll = Duration(seconds: 3);

/// refreshTextDocuments re-reads every document-backed text element in
/// [controller]'s canvas (each scene, the master and the Cast; see
/// _documentTexts), and every Speech device's script read from one, and
/// returns whether anything changed. Applied as one transient change, outside
/// the undo history: it is not something the reader did.
Future<bool> refreshTextDocuments(CanvasController controller) async {
  var changed = false;

  // Read first, applied after: the reads wait, and a document captured
  // before them would put back whatever was edited meanwhile. Each file
  // once, however many texts show it.
  var read = <(String, String), String>{};
  for (var element in _documentTexts(controller.document)) {
    var ref = (element.document.folder, element.document.name);
    if (read.containsKey(ref)) continue;
    String? raw;
    try {
      raw = await PostStorage.read(ref.$1, ref.$2);
    } catch (exception) {
      debugPrint("Unable to read ${element.document.says}: $exception");
      continue;
    }
    // A deleted or renamed document leaves the last words read in place,
    // rather than losing work that is only on the canvas.
    if (raw != null) read[ref] = raw;
  }

  // [list] with each text showing a document read given its words; [list]
  // itself where none differ.
  List<CanvasElement> fresh(List<CanvasElement> list) {
    var out = [...list];
    var differs = false;
    for (var (i, e) in list.indexed) {
      if (e is! TextElement || !e.document.on) continue;
      var raw = read[(e.document.folder, e.document.name)];
      if (raw == null) continue;
      var (text, parts) = readDocument(raw,
          markdown: e.document.markdown, allow: e.document.allow);
      if (text == e.text && _same(parts, e.documentParts)) continue;
      out[i] = e.copyWith(text: text, documentParts: parts);
      differs = true;
    }
    if (!differs) return list;
    changed = true;
    return out;
  }

  var now = controller.document;
  var scenes = [
    for (var s in now.allScenes)
      if (fresh(s.elements) case var l when !identical(l, s.elements))
        s.copyWith(elements: l)
      else
        s,
  ];
  var master = now.master;
  if (master != null) {
    var l = fresh(master.elements);
    if (!identical(l, master.elements)) master = master.copyWith(elements: l);
  }
  var cast = fresh(now.cast);
  if (changed) {
    // A document with no scene list keeps its one scene's elements apart:
    // they go there with the master off, then it is put back.
    var next = now.scenes.isEmpty
        ? now
            .copyWith(onMaster: false, elements: scenes.single.elements)
            .copyWith(onMaster: now.onMaster)
        : now.withScenes(scenes, at: now.at);
    controller.apply(next.copyWith(master: master, cast: cast),
        transient: true);
  }

  // The Speech devices' scripts: the document's words, as plain text.
  for (var lane in controller.timelineChannels) {
    var spec = lane.mix.speech;
    if (spec == null || !spec.document.on) continue;
    String? raw;
    try {
      raw = await PostStorage.read(spec.document.folder, spec.document.name);
    } catch (exception) {
      debugPrint("Unable to read ${spec.document.says}: $exception");
      continue;
    }
    if (raw == null) continue;
    var (text, _) = readDocument(raw);
    var script = text.trim();
    if (script == spec.script) continue;
    controller.setSpeech(lane.key, spec.withScript(script), transient: true);
    changed = true;
  }
  return changed;
}

/// wantsDocumentPoll is whether this canvas has anything to poll for: a
/// text, or a Speech device's script, read from a document.
bool wantsDocumentPoll(CanvasDocument document,
    {CanvasController? controller}) {
  if (_documentTexts(document).isNotEmpty) return true;
  return controller?.timelineChannels
          .any((l) => l.mix.speech?.document.on ?? false) ??
      false;
}

/// TextDocumentWatch is the poll itself, started and stopped with the page.
class TextDocumentWatch {
  final CanvasController controller;
  Timer? _timer;
  bool _reading = false;

  TextDocumentWatch(this.controller);

  /// start reads once and then keeps reading. Safe to call again: the timer is
  /// replaced rather than doubled.
  void start() {
    stop();
    unawaited(_tick());
    _timer = Timer.periodic(canvasDocumentPoll, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    // A slow disk must not stack polls up behind each other.
    if (_reading) return;
    if (!wantsDocumentPoll(controller.document, controller: controller)) {
      return;
    }
    _reading = true;
    try {
      await refreshTextDocuments(controller);
    } finally {
      _reading = false;
    }
  }
}

/// _documentTexts is every text in [document] showing a document: on each
/// scene, not only the one being edited, on the master and in the Cast.
Iterable<TextElement> _documentTexts(CanvasDocument document) => [
      for (var s in document.allScenes) ...s.elements,
      ...?document.master?.elements,
      ...document.cast,
    ].whereType<TextElement>().where((e) => e.document.on);

/// _same is whether two lists of derived parts say the same thing.
bool _same(List parts, List other) {
  if (parts.length != other.length) return false;
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].toJson().toString() != other[i].toJson().toString()) {
      return false;
    }
  }
  return true;
}
