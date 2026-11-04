import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show ClipTriggerKind;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show MovedElement, sceneFraming;
import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// canvas_file_player.dart plays a canvas file (.bcanvas) where Files
// previews a PDF or a video: every scene in turn, with play, pause and start
// again. Its pictures and sounds are stored in the library on opening, so
// they can be drawn and heard.

/// openCanvasFile puts the canvas in the file at [filePath] in the library
/// (its pictures and sounds stored, filed under its own name or its file's)
/// and goes to the Canvas page, where it opens. A .bcanvas has no other
/// program to open it.
Future<void> openCanvasFile(BuildContext context, String filePath) async {
  var snackbar = SnackBarModel.of(context, listen: false);
  var prefs = Provider.of<CanvasPreferences>(context, listen: false);
  var nav = Navigator.of(context);
  if (!prefs.enabled) {
    snackbar.error("Turn Canvas on in Settings to open a canvas.");
    return;
  }
  try {
    var bundle = await unpackCanvasFile(File(filePath));
    if (bundle == null) {
      snackbar.error("That file is not a canvas.");
      return;
    }
    await storeBundlePictures(bundle);
    var wanted = CanvasStorage.sanitizeName(bundle.document.title) ??
        CanvasStorage.sanitizeName(path.basenameWithoutExtension(filePath)) ??
        "Canvas";
    var name = await CanvasStorage.uniqueName("", wanted);
    var ok = await CanvasStorage.save(
        "", name, bundle.document.copyWith(title: name));
    if (!ok) {
      snackbar.error("Unable to put it in your Canvas.");
      return;
    }
    prefs.pendingOpen = ("", name);
    nav.pushReplacementNamed(CanvasScreen.routeName);
  } catch (exception) {
    snackbar.error("Unable to open it: $exception");
  }
}

/// CanvasFilePlayer plays the canvas in [file].
class CanvasFilePlayer extends StatefulWidget {
  final File file;
  const CanvasFilePlayer({required this.file, super.key});

  @override
  State<CanvasFilePlayer> createState() => _CanvasFilePlayerState();
}

class _CanvasFilePlayerState extends State<CanvasFilePlayer> {
  CanvasController? _c;

  /// controllerForTest is what plays it, for a test to look at.
  @visibleForTesting
  CanvasController? get controllerForTest => _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(CanvasFilePlayer old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      _close();
      setState(() => _error = null);
      _open();
    }
  }

  Future<void> _open() async {
    // A preview stores what the canvas brings with it, so it counts as using
    // Canvas: not while that is switched off.
    if (!Provider.of<CanvasPreferences>(context, listen: false).enabled) {
      setState(() => _error = "Turn Canvas on in Settings to play a canvas.");
      return;
    }
    try {
      var bundle = await unpackCanvasFile(widget.file);
      if (bundle == null) {
        if (mounted) setState(() => _error = "This is not a canvas.");
        return;
      }
      await storeBundlePictures(bundle);
      if (!mounted) return;
      var doc = bundle.document;
      var c = CanvasController(doc);
      // Every scene, one after another, as a reader would see it.
      if (doc.hasScenes) c.playAll = true;
      setState(() => _c = c);
    } catch (exception) {
      if (mounted) setState(() => _error = "Unable to read it: $exception");
    }
  }

  void _close() {
    var c = _c;
    _c = null;
    if (c == null) return;
    if (c.playing) c.pause();
    c.dispose();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _again() {
    var c = _c;
    if (c == null) return;
    c.pause();
    if (c.document.hasScenes) c.goToScene(0);
    c.frame = 0;
    c.backToTimeline();
    _start(c);
  }

  /// _start plays it, and the clips that start with the scene start.
  void _start(CanvasController c) {
    var fromTop = c.frame == 0;
    c.play();
    if (fromTop) c.fireMotionTrigger(ClipTriggerKind.sceneStarts);
  }

  /// _key is a key pressed while it plays: the clips that start on it.
  KeyEventResult _key(CanvasController c, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    var k = e.logicalKey;
    var name = k == LogicalKeyboardKey.space
        ? "Space"
        : k == LogicalKeyboardKey.enter
            ? "Enter"
            : k.keyLabel.toUpperCase();
    c.fireMotionTrigger(ClipTriggerKind.key, name);
    return KeyEventResult.ignored;
  }

  /// _press is a click at [at] in a view [size] big: the button there does
  /// what it does, and the top sound or video there (the scene's over the
  /// master's) plays or stops.
  void _press(CanvasController c, Offset at, Size size) {
    var doc = c.document;
    var page = doc.size.size;
    if (size.width <= 0 || size.height <= 0) return;
    var p = Offset(
        at.dx / size.width * page.width, at.dy / size.height * page.height);
    var clicked = false;
    for (var e in [
      ...doc.elements.reversed,
      ...?doc.masterScene?.elements.reversed,
    ]) {
      if (!e.visible ||
          !e.movedBoundsAt(c.frame, doc, live: c.liveMotion).contains(p)) {
        continue;
      }
      // Clips that start on a click, whatever else it does: the top one's.
      if (!clicked) {
        clicked = true;
        c.fireMotionTrigger(ClipTriggerKind.clicked, e.id);
      }
      switch (e) {
        case ButtonElement b:
          c.runButtonAction(b.action);
          return;
        case AudioElement() || VideoElement():
          c.runButtonAction(ButtonAction(
              kind: ButtonActionKind.toggleSound, elementId: e.id));
          return;
        default:
          continue;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error case var error?) return Center(child: Text(error));
    var c = _c;
    if (c == null) return const Center(child: CircularProgressIndicator());
    var page = c.document.size.size;
    var aspect =
        page.width <= 0 || page.height <= 0 ? 16 / 9 : page.width / page.height;
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(fit: StackFit.expand, children: [
              // Buttons and speakers work as for a reader; links are not followed from
              // a preview.
              LayoutBuilder(
                builder: (context, box) => Focus(
                  autofocus: true,
                  onKeyEvent: (_, e) => _key(c, e),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _press(c, d.localPosition, box.biggest),
                    child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => CustomPaint(
                          key: const ValueKey("canvasFileView"),
                          painter: _PlayedPainter(c)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      ListenableBuilder(
        listenable: c,
        builder: (context, _) =>
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            key: const ValueKey("canvasFilePlay"),
            icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
            tooltip: c.playing ? "Pause" : "Play",
            onPressed: () => c.playing ? c.pause() : _start(c),
          ),
          IconButton(
            key: const ValueKey("canvasFileAgain"),
            icon: const Icon(Icons.replay),
            tooltip: "From the start",
            onPressed: _again,
          ),
        ]),
      ),
    ]);
  }
}

/// _PlayedPainter draws the canvas where its playing has got to -- the
/// scene showing, on its frame -- fitted to the box.
class _PlayedPainter extends CustomPainter {
  final CanvasController c;
  _PlayedPainter(this.c) : super(repaint: c.images);

  @override
  void paint(Canvas canvas, Size size) {
    CanvasDocument doc = c.document;
    var page = doc.size.size;
    if (page.width <= 0 || page.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / page.width, size.height / page.height);
    // On a 3D stage, its Camera is the stage's: see camera_3d.
    directedBy(
        doc,
        c.liveMotion,
        () => paintCanvasDocument(canvas, doc,
            frame: c.frame,
            images: c.images,
            counterValue: c.counterValue,
            liveMotion: c.liveMotion,
            camera: sceneFraming(doc, c.frame, live: c.liveMotion)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayedPainter old) => true;
}
