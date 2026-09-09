import 'dart:async';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter/foundation.dart';

// text_documents.dart keeps a document-backed text element up to date.
//
// The words live in the element -- see TextDocumentRef on why they are copied
// rather than read at drawing time -- so something has to notice when the
// document behind them changes. That is this: a poll while the canvas is
// open, which reads each referenced document and writes back only what
// actually differs.
//
// A poll rather than a watcher because the library is a folder of files that
// another part of the app writes, with no change feed of any kind, and
// because the cost is a handful of small reads every few seconds against a
// canvas that has asked for them. A canvas with no document-backed element
// does no work at all.

/// canvasDocumentPoll is how often the library is looked at while a canvas is
/// open. Slow enough to be free, quick enough that somebody switching from
/// Writing back to Canvas sees their edit by the time they have looked at it.
const Duration canvasDocumentPoll = Duration(seconds: 3);

/// refreshTextDocuments re-reads every document-backed text element in
/// [controller]'s canvas, and returns whether anything changed.
///
/// Applied as one transient change: it is not something the reader did, so it
/// does not belong in the undo history -- undoing your own typing and getting
/// somebody else's document back is not an undo.
Future<bool> refreshTextDocuments(CanvasController controller) async {
  var next = controller.document;
  var changed = false;

  for (var element in controller.document.elements) {
    if (element is! TextElement || !element.document.on) continue;
    String? raw;
    try {
      raw = await PostStorage.read(
          element.document.folder, element.document.name);
    } catch (exception) {
      debugPrint("Unable to read ${element.document.says}: $exception");
      continue;
    }
    // A document that has been deleted or renamed leaves the words that were
    // last read where they are. Emptying the element would lose work that is
    // on the canvas and nowhere else.
    if (raw == null) continue;

    var (text, parts) = readDocument(raw,
        markdown: element.document.markdown, allow: element.document.allow);
    if (text == element.text && _same(parts, element.documentParts)) continue;

    next = next.withElement(element.copyWith(text: text, documentParts: parts));
    changed = true;
  }

  if (changed) controller.apply(next, transient: true);
  return changed;
}

/// wantsDocumentPoll is whether this canvas has anything to poll for.
bool wantsDocumentPoll(CanvasDocument document) {
  for (var element in document.elements) {
    if (element is TextElement && element.document.on) return true;
  }
  return false;
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
    if (!wantsDocumentPoll(controller.document)) return;
    _reading = true;
    try {
      await refreshTextDocuments(controller);
    } finally {
      _reading = false;
    }
  }
}

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
