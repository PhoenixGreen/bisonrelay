import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/game_embed.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// canvas_file_player.dart is a canvas file -- a .bcanvas, sent, shared or
// downloaded -- played where Files previews a PDF or a video (Ken): its
// animation run through every scene, with play, pause and start again; or,
// a game, its first frame and Play, played as a game in a post is. Its
// pictures and sounds are stored as they are when one is opened from Files
// into the library, for it to be drawn and heard by.

/// openCanvasFile opens the canvas in the file at [filePath] in the Canvas
/// page: put in the library -- its pictures and sounds stored, filed under
/// its own name, or its file's -- and the page gone to, where it opens. A
/// .bcanvas has no other program to open it (Ken: Open on a shared game did
/// nothing).
Future<void> openCanvasFile(BuildContext context, String filePath) async {
  var snackbar = SnackBarModel.of(context, listen: false);
  var prefs = Provider.of<CanvasPreferences>(context, listen: false);
  var nav = Navigator.of(context);
  if (!prefs.enabled) {
    snackbar.error("Turn Canvas on in Settings to open a canvas.");
    return;
  }
  try {
    var bundle = await unpackCanvas(await File(filePath).readAsBytes());
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
    try {
      var bundle = await unpackCanvas(await widget.file.readAsBytes());
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
    c.play();
  }

  /// _press is a click at [at] in a view [size] big: the button there does
  /// what it does, and a sound or a video there plays or stops -- the top
  /// one, the scene's over the master's.
  void _press(CanvasController c, Offset at, Size size) {
    var doc = c.document;
    var page = doc.size.size;
    if (size.width <= 0 || size.height <= 0) return;
    var p = Offset(
        at.dx / size.width * page.width, at.dy / size.height * page.height);
    for (var e in [
      ...doc.elements.reversed,
      ...?doc.masterScene?.elements.reversed,
    ]) {
      if (!e.visible || !e.boundsAt(c.frame).contains(p)) continue;
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
    var game = c.document.game;
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(fit: StackFit.expand, children: [
              // Its buttons and speakers pressed, as a reader presses them;
              // a link is not followed from a preview.
              LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: game
                      ? null
                      : (d) => _press(c, d.localPosition, box.biggest),
                  child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => CustomPaint(
                        key: const ValueKey("canvasFileView"),
                        painter: _PlayedPainter(c)),
                  ),
                ),
              ),
              // A game: Play, and it is played as a game in a post is.
              if (game)
                ColoredBox(
                  color: const Color(0x55101114),
                  child: Center(
                    child: FilledButton.icon(
                      key: const ValueKey("canvasFilePlayGame"),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF30A46C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 26, vertical: 14)),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) =>
                                  GamePlayer(document: c.document))),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Play",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      if (!game)
        ListenableBuilder(
          listenable: c,
          builder: (context, _) =>
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: const ValueKey("canvasFilePlay"),
              icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
              tooltip: c.playing ? "Pause" : "Play",
              onPressed: () => c.playing ? c.pause() : c.play(),
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
    paintCanvasDocument(canvas, doc,
        frame: c.frame, images: c.images, counterValue: c.counterValue);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayedPainter old) => true;
}
