import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// canvas_forget_document_test.dart holds the editing session to letting go
// of a canvas when another is opened. The session lives as long as the app,
// so whatever it keeps about one canvas is met by the next unless load lets
// go of it, and the place that does (_forgetDocument in saving.dart) is a
// list kept by hand. This test reads the controller's source and fails for
// any state it owns that is neither let go of there nor named below as
// meant to outlive a canvas.
//
// What it reads: canvas_controller.dart and every part under controller/.
// In the class CanvasController and in each holder class (a private class
// whose name ends in "State", held by the controller in a field), a member
// is a line at two spaces of indent, with the lines under it that finish its
// declaration. A member is a method, a constructor, a getter or a setter
// when its head (what comes before its body, its "=>" or its "=") has a name
// followed by "(" other than "Function(", or the word "get" before its name;
// anything else ending in a name is a field. A static field is the app's,
// not the session's, and is passed over.
//
// What it counts as state: each field that is not final; each final field
// whose type is a collection (Map, Set, List, Queue), a ValueNotifier or a
// holder class; and in each holder, its fields by the same rule, named
// "holder.field". A declaration it cannot read fails the test, so a new way
// of writing one is looked at rather than missed.
//
// What it counts as let go of: the field assigned ("name ="), cleared
// ("name.clear()"), cascaded ("name.."), its value set ("name.value =") or
// its forgetDocument called, in load, in _forgetDocument, in a holder's
// forgetDocument that one of those calls, or in one of the methods in
// _lettingGo; or, for a holder, the holder made anew ("_x = _XState()"),
// which lets go of every field in it.

const _ui = "lib/plugin_system/canvas/ui";

/// _lettingGo is the methods load calls, before or after _forgetDocument,
/// that let go of part of what the last canvas left: their bodies are read
/// as _forgetDocument's is. Each must still be called by load, by
/// _forgetDocument or by another method here.
const _lettingGo = <String, String>{
  "set gaming": "load ends a game first, with everything it set going",
  "_endWait": "load ends a stop waiting for an action: a key hook",
  "pause": "load stops play: the timer, a practice, a slowed sheet, "
      "recording, and the slots",
  "_haltClips": "pause stops the slots: what each channel plays and will",
  "_forgetCodePicks": "the Code panels' picks and scrolls, by their ids",
  "paintSprite": "a sprite being painted, ended through its session",
  "paintTiles": "a tile map being painted, ended through its session",
  "listenAt": "a channel listened to alone is told to the engine too",
  "_letGoOfLive": "load and leavePage let go of what is held live: keys, "
      "arpeggios, synth keys, a target chord, metronomes, a voice heard",
  "stopHearing": "a take or a voice heard alone, stopped in the engine",
  "_synthTargetOff": "a task card's target chord, let go of now",
  "_endPractice": "pause ends a practice take, letting go of its keys",
  "_slowRelease": "pause lets go of a slowed sheet's keys",
  "_resetVectorEditing": "a drawing's editing ended: what was picked in it",
  "_putWarpAway": "a picture's warp grid put away with its points",
};

/// _outlivesACanvas is the state meant to stay when another canvas opens,
/// each with why. Something is put here only when it is not the canvas's:
/// the person's own way of working, the app's run, or a cache keyed by
/// what it holds rather than by an element. A name here that is let go of
/// as well fails the test, as does one that no longer exists.
final _outlivesACanvas = <String, String>{
  // The person's view, tools and ways of working, kept by KeptView or for
  // the session.
  "_fitScale": "what the stage last measured of the window, not the canvas",
  "_fit": "how the reader likes a canvas framed; the zoom and pan go",
  "_rulers": "the rulers shown: a view setting",
  "_autoKeyframe": "the keyframe switch: a way of working",
  "_showOverspill": "a view setting",
  "_showHelpers": "a view setting",
  "_showAllBounds": "a view setting",
  "_lockJoins": "a view setting",
  "_hideJoins": "a view setting",
  "_retouch": "the brush in hand: a tool, not part of a canvas",
  "_brushHardness": "a brush setting",
  "_cutInside": "a brush setting",
  "_brushSnap": "a brush setting",
  "_brushSize": "a brush setting",
  "_pageLocked": "a view setting",
  "_stageTool": "the 3D tool in hand",
  "_stageNav": "how the 3D view is moved: a way of working",
  "_chainMeters": "a view setting of the Chain",
  "_chainBadges": "a view setting of the Chain",
  "_chainMacros": "a view setting of the Chain",
  "_motionTrail": "a view setting",
  "_dockState": "which panels are open, kept by KeptView; an audio canvas "
      "opens its own on load",
  "_barBelow": "where the play bar sits: the person's layout",
  "_trackpadScrolls": "a preference",
  "_dock": "the panels' places: the person's layout",
  "_arrangementChosen": "the person's saved arrangement",
  "_timelineShow": "what the timeline shows: a view setting",
  "_slotsShownOf": "the document the slot rows were counted for, compared "
      "by identity: another document is counted afresh",
  "_slotsShownCount": "worked out again for each document (see "
      "_slotsShownOf)",
  "_slotsColumn": "the slots column's dragged width: the person's layout",
  "_tool": "the tool in hand",
  "_opened": "whether the page has been shown this session",
  "_loads": "counts the canvases opened: what a job compares to know",
  "_edits": "counts changes this session; load sets _savedEdits to it, so "
      "the next canvas opens clean",
  "_glideListening": "whether the chart glides' beat is listened to: a "
      "listener of the run",
  "_mixerLayout": "how the mixer is laid out: the person's own",
  "_cameraView": "whether the stage looks through its camera: a view "
      "setting",
  "_chainPhase": "the Chain's filter: a view setting",
  "_hear": "the speakers the editor plays: the person's listening",
  "_editorWide": "the clip editor's width: a view setting",
  "_motionCurves": "a view setting",
  "_trackCurves": "a view setting",
  "_rollStep": "the piano roll's Step input switch",
  "_rollStepGrid": "the piano roll's step: a tool setting",
  "_noteToolPresses": "a seed counter for the note tools, of any canvas",
  "_laneSize": "the timeline's row size: a view setting",
  "_headerWidth": "the timeline's header width: the person's layout",
  "_allFolded": "a view setting of the timeline",
  "_speechShown": "whether the Chain shows Speech: a view setting",
  "_pitchShown": "whether the Chain shows Pitch: a view setting",
  "_instrumentShown": "whether the Chain shows the instrument: a view "
      "setting",
  "_chainFull": "whether the Chain fills the window: a view setting",
  "foldedDevices": "devices folded by kind, the same on every strip of any "
      "canvas: a view setting",
  "escStopsGame": "set by whoever shows the canvas: the editor or a player",
  "_playAll": "the play bar's switch to play every scene: a way of playing",
  "_effectsFocus": "which editor the effects panel last brought forward, by "
      "kind (clip, roll, pitch, instrument), not by any element",
  "_effectsFocusCount": "counts those requests: only goes up",
  "_gameState.tabOpen": "whether the Game tab shows: a view setting",
  "_keyframes.keyClipboard": "keyframes copied: a clipboard, which pastes "
      "into another canvas as the element clipboard does",
  "_laneState.cuesShown": "a view setting of the timeline",
  "_laneState.followPlayhead": "whether the timeline follows the playhead: "
      "a preference",
  "_mixerState.automationArmed": "the bar's automation switch, not any "
      "channel's",
  "_panelState.snapping": "a tool setting",
  "_panelState.timelineTool": "the timeline's tool in hand",
  "_panelState.settingsShut": "which editors' settings are folded: a view "
      "setting",
  "_pictures.frameTool": "a picture tool in hand",
  "_pictures.skewHandles": "a picture tool setting",
  "_pictures.tool": "a picture tool in hand",
  "_pictures.maskHide": "a mask tool setting",
  "_pictures.maskBrushSize": "a mask brush setting",
  "_pictures.maskHardness": "a mask brush setting",
  "_pictures.maskStrength": "a mask brush setting",
  "_pictures.maskRadial": "a mask brush setting",
  "_pictures.maskView": "how a mask is shown: a view setting",
  "_pictures.paintColour": "a paint brush setting",
  "_pictures.paintSize": "a paint brush setting",
  "_pictures.paintHardness": "a paint brush setting",
  "_pictures.paintStrength": "a paint brush setting",
  "_pictures.paintTip": "a paint brush setting",
  "_pictures.paintBrush": "a paint brush setting",
  "_pictures.burning": "a retouch brush setting",
  "_pictures.retouchWholeFrame": "a retouch brush setting",
  "_playbackState.playheadOnly": "set only while a frame of play is told",
  "_playbackState.clockFrames": "the play clock, set afresh by every Play "
      "before it is read",
  "_playbackState.clockPace": "the play clock, as clockFrames",
  "_playbackState.clockFrom": "the play clock, as clockFrames",
  "_playbackState.clockFromFrame": "the play clock, as clockFrames",
  "_playbackState.playWatch": "the play clock, as clockFrames",
  "_playbackState.clockShift": "the play clock, as clockFrames",
  "_playbackState.metronome": "the play bar's metronome switch: a way of "
      "working",
  "_sessionState.stagePointer": "where the pointer is over the stage, set "
      "by the stage as it moves",
  "_sessionState.facesPointerOf": "the document facesPointerWas was worked "
      "out for, compared by identity",
  "_sessionState.facesPointerWas": "worked out again for another document "
      "(see facesPointerOf)",
  "_sessionState.previewTicks": "counts previews for the stage to repaint "
      "by: only goes up",
  // The drawing tools, kept from one drawing to the next.
  for (var tool in _vectorTools) "_vectors.$tool": "a drawing tool setting",
  "_vectors.copiedShapes": "points copied: a clipboard",
  "_vectors.pastes": "how often the points copied were pasted",
  "_vectors.sampled": "the eyedropper's last colour: a swatch of the "
      "person's",
  "_laneState.duckFor": "the document the ducking was worked out for, "
      "compared by identity",
  "_laneState.duckWaves": "worked out again for another document (see "
      "duckFor)",
  "_laneState.ducks": "worked out again for another document (see duckFor)",
  // The app's run: hooks, engines, notifiers and handles.
  "clockForTest": "a test's stand-in for the clock",
  "gameClockForTest": "a test's stand-in for the game's clock",
  "codeLiveSnap": "set by the live preview widget while it is open",
  "_audio": "the sound engine, made once for the session",
  "_video": "the video engine, made once for the session",
  "_autosave": "the save timer: the screen saves a canvas before another "
      "opens, and the timer writes only what the one open then has not",
  "_partTimer": "a timer that renders parts of the canvas open when it "
      "fires",
  "_shapeTimer": "a timer that makes Phrasing's take, if Phrasing is open",
  "_warpTimer": "a timer that warps the clips of the canvas open when it "
      "fires",
  "_controlIdle": "ends a run of turning a knob as an undo step",
  "_previewDir": "a folder of voice previews, shared by every canvas",
  "_disposed": "the session shut",
  "_disposedForWaveform": "the session shut",
  "_viewOnly": "set only while a notification is being sent",
  "_rapid": "set only while a notification is being sent",
  "_revision": "counts changes for the sidebar to watch: must only go up",
  "timelineViewSet": "counts restores of the timeline's view: "
      "_forgetDocument moves it on, and it only goes up",
  "keysHeld": "a beat ticked for the stage to draw by, not state",
  "playheadMoved": "a beat ticked for the playhead to draw by, not state",
  // Caches keyed by what they hold, not by an element.
  "_warpingNow": "renders by their sound and settings: a clip of the next "
      "canvas the same waits on the same render",
  "warping": "the clips whose renders are running, each cleared by its own "
      "render; a render is the same for the same sound and settings",
  "_channels": "worked out from the document, compared by identity",
  "_lanesKept": "worked out from the document, compared by identity",
  "_pressedKept": "worked out from the document, compared by identity",
  "_speechState.readings": "what a take's sound was heard as, by its file",
  "_speechState.readingTakes": "the takes being read, by their files",
  "_speechState.unreadTakes": "the takes that could not be read, by file",
  "_speechState.previews": "voice previews, by everything that changes "
      "how they sound",
  "_speechState.rendering": "parts being rendered, by what they sound "
      "like: written only onto a part that still sounds the same",
};

/// _vectorTools are the drawing tools' settings: a shape's kind and sides,
/// the eraser, the brushes, the pencil, the mirror, the stylus.
const _vectorTools = [
  "cornerRound", "cornerSize", "handleDrag", "handleSnap", "brush", //
  "pencilPoints", "lanes", "shapeKind", "shapeSides", "starInner",
  "shapeCorner", "shapeFill", "shapeLine", "shapeWidth", "eraseWhole",
  "eraseSize", "eraseSoft", "eraseLine", "eraseFill", "mirrorAcross",
  "mirrorDown", "quickFill", "textStyle", "textColour", "knifeGap",
  "fillGap", "pencilFill", "pencilColour", "stylusButtons", "stylusEraser",
  "tint", "brushSize", "brushSoft", "tintLine", "tintFill",
];

/// _Member is one field: its [name], its [head] (modifiers and type before
/// the name), the start of its initializer [init], whether it [isStatic],
/// and [where] it is declared, for a failure to name.
class _Member {
  final String name;
  final String head;
  final String init;
  final bool isStatic;
  final String where;
  _Member(this.name, this.head, this.init,
      {required this.isStatic, required this.where});

  bool get isFinal => RegExp(r"\b(final|const)\b").hasMatch(head);

  /// type is the declared type, or the start of the initializer for one
  /// written without.
  String get type {
    var t = head
        .replaceAll(RegExp(r"\b(late|final|const|var|covariant)\b"), "")
        .trim();
    return t.isEmpty ? init.trim() : t;
  }
}

List<File> _sources() => [
      File("$_ui/canvas_controller.dart"),
      ...Directory("$_ui/controller")
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(".dart"))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)),
    ];

/// _plain is [line] with its strings emptied and a trailing comment cut, so
/// brackets and commas in them are not read as code.
String _plain(String line) {
  var out = line
      .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""')
      .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
  var comment = out.indexOf("//");
  return comment < 0 ? out : out.substring(0, comment);
}

/// _classBody is the lines of class [name] in [lines], without its first
/// and last, or null where it is not declared there.
List<String>? _classBody(List<String> lines, String name) {
  var start =
      lines.indexWhere((l) => RegExp("^(final )?class $name\\b").hasMatch(l));
  if (start < 0) return null;
  var end = lines.indexWhere((l) => l == "}", start);
  return lines.sublist(start + 1, end);
}

/// _depthStep is how a bracket at [k] of [s] moves the depth: "(", "[",
/// "{" and the "<" of a type open; their partners close. A "<" or ">" with
/// a space after or before it is a comparison, not a type's.
int _depthStep(String s, int k) {
  var ch = s[k];
  var next = k + 1 < s.length ? s[k + 1] : " ";
  var before = k > 0 ? s[k - 1] : " ";
  if ("([{".contains(ch)) return 1;
  if (")]}".contains(ch)) return -1;
  if (ch == "<" && !" =<".contains(next) && before != "<") return 1;
  if (ch == ">" &&
      before != " " &&
      before != "=" &&
      before != "-" &&
      next != "=") {
    return -1;
  }
  return 0;
}

/// _members reads the fields of a class body, passing over its methods and
/// failing on a member it cannot read.
List<_Member> _members(List<String> body, String where) {
  var out = <_Member>[];
  var i = 0;
  while (i < body.length) {
    var raw = body[i];
    var line = _plain(raw);
    var indent = line.length - line.trimLeft().length;
    var t = line.trim();
    if (indent != 2 ||
        t.isEmpty ||
        t.startsWith("@") ||
        t.startsWith("}") ||
        t.startsWith(")") ||
        t.startsWith("]")) {
      i++;
      continue;
    }
    // The statement, read on through the lines under it until what it is
    // can be told: a body, an arrow, an initializer or its end.
    var text = StringBuffer();
    var depth = 0;
    String? stop;
    var at = -1;
    var j = i;
    while (stop == null && j < body.length) {
      var piece = _plain(body[j]).trim();
      var base = text.length;
      text.write("$piece ");
      for (var k = 0; k < piece.length && stop == null; k++) {
        var ch = piece[k];
        var next = k + 1 < piece.length ? piece[k + 1] : "";
        var before = k > 0 ? piece[k - 1] : "";
        if (ch == "=" && next == ">") {
          if (depth == 0) {
            stop = "=>";
            at = base + k;
          }
          k++;
          continue;
        }
        var step = _depthStep(piece, k);
        depth += step;
        if (step == 0 && depth == 0 && ch == ";") {
          stop = ";";
          at = base + k;
        } else if (step == 0 &&
            depth == 0 &&
            ch == "=" &&
            next != "=" &&
            !"=!<>".contains(before)) {
          stop = "=";
          at = base + k;
        }
        if (depth == 1 && ch == "{" && stop == null) {
          // A body opened at the top: a method's, a constructor's, or an
          // initializer's -- but an initializer stops at its "=" first.
          stop = "{";
          at = base + k;
        }
      }
      j++;
    }
    if (stop == null) {
      fail("$where: cannot read the member at \"${raw.trim()}\"");
    }
    var all = text.toString();
    var headText = all.substring(0, at).trim();
    var isStatic = RegExp(r"^(static|external)\b").hasMatch(headText);
    var method = RegExp(r"\b(?!Function\b)[A-Za-z_]\w*\s*(<[^()]*>)?\s*\(")
            .hasMatch(headText) ||
        RegExp(r"\bget\s+\w+$").hasMatch(headText) ||
        RegExp(r"\boperator\b").hasMatch(headText) ||
        headText.startsWith("factory ");
    if (method) {
      if (stop == ";" && !headText.contains("(")) {
        fail("$where: \"${raw.trim()}\" reads as a method with no body");
      }
      // On to the next line at the member's indent.
      i = j;
      while (i < body.length) {
        var l = _plain(body[i]);
        var ind = l.length - l.trimLeft().length;
        if (ind == 2 && !l.trim().startsWith("}") && l.trim().isNotEmpty) {
          break;
        }
        i++;
      }
      continue;
    }
    if (stop == "{" || stop == "=>") {
      fail("$where: \"${raw.trim()}\" opens a body but reads as a field");
    }
    // A field: read to its end, for more names after commas.
    var rest = all.substring(at);
    var k = 0;
    var d = 0;
    var full = stop == ";" ? "" : rest;
    if (stop == "=") {
      while (true) {
        for (; k < full.length; k++) {
          var ch = full[k];
          if (ch == "=" && k + 1 < full.length && full[k + 1] == ">") {
            k++;
            continue;
          }
          d += _depthStep(full, k);
          if (d == 0 && ch == ";") break;
        }
        if (k < full.length || j >= body.length) break;
        full += "${_plain(body[j]).trim()} ";
        j++;
      }
      full = full.substring(0, k);
    }
    // The names: the last word of the head, and each after a comma at the
    // top of the head or of the initializers.
    List<String> topLevel(String s) {
      var parts = <String>[];
      var depth = 0;
      var from = 0;
      for (var n = 0; n < s.length; n++) {
        var ch = s[n];
        if (ch == "=" && n + 1 < s.length && s[n + 1] == ">") {
          n++;
          continue;
        }
        depth += _depthStep(s, n);
        if (depth == 0 && ch == ",") {
          parts.add(s.substring(from, n));
          from = n + 1;
        }
      }
      parts.add(s.substring(from));
      return parts;
    }

    var headParts = topLevel(headText);
    var first =
        RegExp(r"^(.*?)([A-Za-z_]\w*)$").firstMatch(headParts.first.trim());
    if (first == null) {
      fail("$where: cannot find the name in \"${raw.trim()}\"");
    }
    var head = first.group(1)!.trim();
    var names = [first.group(2)!];
    for (var p in headParts.skip(1)) {
      var n = p.trim();
      if (!RegExp(r"^[A-Za-z_]\w*$").hasMatch(n)) {
        fail("$where: cannot read \"$n\" in \"${raw.trim()}\"");
      }
      names.add(n);
    }
    var inits = topLevel(full.isEmpty ? "" : full.substring(1));
    for (var p in inits.skip(1)) {
      var m = RegExp(r"^\s*([A-Za-z_]\w*)\s*=").firstMatch(p);
      if (m == null) {
        fail("$where: cannot read \"${p.trim()}\" in \"${raw.trim()}\"");
      }
      names.add(m.group(1)!);
    }
    for (var n in names) {
      out.add(_Member(n, head, inits.first,
          isStatic: isStatic, where: "$where: ${raw.trim()}"));
    }
    i = j;
  }
  return out;
}

/// _isState is whether [m] is state the session keeps: see the header.
bool _isState(_Member m, Set<String> holders) {
  if (m.isStatic) return false;
  if (!m.isFinal) return true;
  var type = m.type;
  if (RegExp(r"^(Map|Set|List|Queue|ValueNotifier)\b").hasMatch(type)) {
    return true;
  }
  if (RegExp(r"^(\{|\[|<)").hasMatch(type)) return true;
  var holder = RegExp(r"^(_\w+)").firstMatch(type)?.group(1);
  return holder != null && holders.contains(holder);
}

/// _body is method [name]'s body in [lines] ("set x" for a setter): the
/// lines from its head to its closing brace at the same indent.
String? _body(List<String> lines, String name, {int indent = 2}) {
  var pad = " " * indent;
  var setter = name.startsWith("set ");
  var bare = setter ? name.substring(4) : name;
  var head = setter
      ? RegExp("^${pad}set $bare\\(")
      : RegExp("^$pad(?![ /])(?!set )[\\w<>?, ()]*?\\b$bare\\(");
  var start = lines.indexWhere(head.hasMatch);
  if (start < 0) return null;
  var end = start;
  while (end < lines.length && lines[end] != "$pad}") {
    end++;
  }
  return lines.sublist(start, end + 1).join("\n");
}

/// _resets is whether [text] assigns, clears, cascades or renews [name].
bool _resets(String text, String name) =>
    RegExp("(?<![\\w.])(this\\.)?${RegExp.escape(name)}\\s*"
            "(=(?![=>])|\\.\\.|\\.clear\\(\\)|\\.value\\s*=(?![=>])"
            "|\\.forgetDocument\\(\\))")
        .hasMatch(text);

void main() {
  var sources = {for (var f in _sources()) f.path: f.readAsLinesSync()};

  // The holder classes, wherever they are declared.
  var holderBodies = <String, List<String>>{};
  for (var MapEntry(key: path, value: lines) in sources.entries) {
    for (var l in lines) {
      var m = RegExp(r"^class (_\w+State)\b").firstMatch(l);
      if (m == null) continue;
      var body = _classBody(lines, m.group(1)!)!;
      if (body.isEmpty) fail("$path: ${m.group(1)} has no body");
      holderBodies[m.group(1)!] = body;
    }
  }
  var holders = holderBodies.keys.toSet();

  var controllerLines = sources["$_ui/canvas_controller.dart"]!;
  var controller = _members(
      _classBody(controllerLines, "CanvasController")!, "CanvasController");

  // Each holder's field in the controller.
  var holderField = <String, String>{};
  for (var m in controller.where((m) => !m.isStatic)) {
    var type = RegExp(r"^(_\w+)").firstMatch(m.type)?.group(1);
    if (type != null && holders.contains(type)) holderField[type] = m.name;
  }

  // What load lets go of: the bodies read.
  String bodyOf(String name) {
    for (var lines in sources.values) {
      var b = _body(lines, name);
      if (b != null) return b;
    }
    fail("no method $name in the controller's sources");
  }

  var load = bodyOf("load");
  var forget = bodyOf("_forgetDocument");
  var readBodies = [load, forget, for (var n in _lettingGo.keys) bodyOf(n)];
  var read = readBodies.join("\n");

  test("each method read with _forgetDocument is still called by load", () {
    for (var name in _lettingGo.keys) {
      var bare = name.startsWith("set ") ? name.substring(4) : name;
      var call = name.startsWith("set ")
          ? RegExp("\\b$bare\\s*=(?!=)")
          : RegExp("(?<![\\w])$bare\\(");
      var callers = [
        load,
        forget,
        for (var other in _lettingGo.keys)
          if (other != name) bodyOf(other)
      ];
      expect(callers.any(call.hasMatch), isTrue,
          reason: "$name is in _lettingGo but nothing load runs calls it");
    }
  });

  // Every piece of state, by the name the list knows it by, with whether
  // it is let go of.
  var state = <String, bool>{};
  for (var m in controller) {
    if (!_isState(m, holders)) continue;
    var type = RegExp(r"^(_\w+)").firstMatch(m.type)?.group(1);
    if (type != null && holders.contains(type)) continue;
    state[m.name] = _resets(read, m.name);
  }
  for (var MapEntry(key: holder, value: body) in holderBodies.entries) {
    var field = holderField[holder];
    if (field == null) {
      test("$holder is held by the controller", () {
        fail("$holder is a holder class no field of the controller holds");
      });
      continue;
    }
    var renewed =
        RegExp("(?<![\\w.])$field\\s*=\\s*$holder\\(\\)").hasMatch(read);
    var ownForget =
        RegExp("(?<![\\w.])$field\\.forgetDocument\\(\\)").hasMatch(read)
            ? _body(body, "forgetDocument") ?? ""
            : "";
    for (var m in _members(body, holder)) {
      if (!_isState(m, holders)) continue;
      state["$field.${m.name}"] = renewed ||
          _resets(read, "$field.${m.name}") ||
          _resets(ownForget, m.name);
    }
  }

  test("the controller's state was read", () {
    // A guard on the reading itself: fields every version has.
    expect(state.keys, containsAll(["_selection", "_frame", "_zoom"]));
    expect(state.keys, contains("_mixerState.listening"));
    expect(state.length, greaterThan(150));
  });

  test("everything about a canvas is let go of when another is opened", () {
    var missing = [
      for (var MapEntry(key: name, value: reset) in state.entries)
        if (!reset && !_outlivesACanvas.containsKey(name)) name,
    ];
    expect(missing, isEmpty,
        reason: "each is the canvas's (let it go in _forgetDocument) or "
            "outlives a canvas (name it in _outlivesACanvas, with why):\n"
            "${missing.join("\n")}");
  });

  test("what outlives a canvas is not also let go of, and still exists", () {
    var both = [
      for (var name in _outlivesACanvas.keys)
        if (state[name] ?? false) name,
    ];
    expect(both, isEmpty,
        reason: "let go of on load, so not on _outlivesACanvas:\n"
            "${both.join("\n")}");
    var gone = [
      for (var name in _outlivesACanvas.keys)
        if (!state.containsKey(name)) name,
    ];
    expect(gone, isEmpty,
        reason: "no longer state of the controller; take them off:\n"
            "${gone.join("\n")}");
    for (var reason in _outlivesACanvas.values) {
      expect(reason, isNotEmpty);
    }
  });
}
