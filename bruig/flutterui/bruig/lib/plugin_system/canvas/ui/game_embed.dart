import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart' show getCrc32;
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/game_publish.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// game_embed.dart is a game published from Canvas, as a reader meets it in
// a post or on a page: its cover, with Play -- and, pressed, the game itself,
// played by the same engine it was made in. See game_publish.dart for the
// other half. Nothing is unpacked until Play is pressed: a post scrolled
// past costs its cover and no more.

const _gameTag = "canvasgame";

/// canvasMarkdownExtensions are what Canvas draws in markdown: a published
/// game. See MarkdownAreaModel.setPluginExtensions.
List<MarkdownExtension> canvasMarkdownExtensions() => [
      MarkdownExtension(
          tag: _gameTag, builder: _GameEmbedBuilder(), embedType: gameMime),
    ];

class _GameEmbedBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      SelectionContainer.disabled(
          child: GameEmbed(
              data: element.textContent, params: Map.of(element.attributes)));
}

/// GameEmbed is a published game's cover: its first frame, its name, how
/// to play it, the reader's best -- and Play.
class GameEmbed extends StatefulWidget {
  /// data is the game's bundle, in base64, as the embed carries it.
  final String data;
  final Map<String, String> params;
  const GameEmbed({required this.data, required this.params, super.key});

  @override
  State<GameEmbed> createState() => _GameEmbedState();
}

class _GameEmbedState extends State<GameEmbed> {
  Uint8List? _cover;
  int? _best;
  bool _opening = false;

  GamePublishOptions get _options =>
      GamePublishOptions.fromParams(widget.params);

  String get _name {
    var raw = widget.params["name"] ?? "";
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  /// _key is the game's own, for its best to be kept under: from what it is,
  /// so the same game in two posts is one best.
  String get _key {
    var d = widget.data;
    var sample = d.length <= 8192 ? d : d.substring(0, 8192);
    return "canvasGameBest:${getCrc32(utf8.encode(sample))}:${d.length}";
  }

  @override
  void initState() {
    super.initState();
    try {
      var c = widget.params["cover"];
      if (c != null && c.isNotEmpty) _cover = base64Decode(c);
    } catch (_) {}
    if (_options.best) _readBest();
  }

  Future<void> _readBest() async {
    try {
      var v = await StorageManager.readData(_key);
      if (mounted && v is int) setState(() => _best = v);
    } catch (_) {}
  }

  Future<void> _play() async {
    var snackbar = SnackBarModel.of(context, listen: false);
    setState(() => _opening = true);
    CanvasBundle? bundle;
    Uint8List? bytes;
    try {
      bytes = base64Decode(widget.data);
      bundle = await unpackCanvas(bytes);
      if (bundle != null) await storeBundlePictures(bundle);
    } catch (_) {
      bundle = null;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (bundle == null || bytes == null) {
      snackbar.error("That game could not be opened.");
      return;
    }
    var best = await Navigator.of(context).push<int>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => GamePlayer(
            document: bundle!.document, best: _best, canOpen: _options.open)));
    if (!mounted || best == null || !_options.best) return;
    if (best > (_best ?? -1)) {
      setState(() => _best = best);
      await StorageManager.saveData(_key, best);
    }
  }

  @override
  Widget build(BuildContext context) {
    var options = _options;
    var cover = _cover;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            if (cover != null)
              Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF9DD4F0), Color(0xFF6BB04A)]))),
            const ColoredBox(color: Color(0x55101114)),
            Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_name.isNotEmpty)
                    Text(_name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 6, color: Color(0x88000000))
                            ])),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey("gameEmbedPlay"),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF30A46C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14)),
                    onPressed: _opening ? null : _play,
                    icon: _opening
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: Text(_opening ? "Opening…" : "Play",
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (options.howTo &&
                      (widget.params["keys"] ?? "").isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_decoded(widget.params["keys"]!),
                        key: const ValueKey("gameEmbedKeys"),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 3, color: Color(0x88000000))
                            ])),
                  ],
                  if (options.best && _best != null) ...[
                    const SizedBox(height: 6),
                    Text("Your best: $_best",
                        key: const ValueKey("gameEmbedBest"),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF2C94C))),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _decoded(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// GamePlayer is a published game, played: the canvas as the game has it,
/// filling the window, with a slim bar to pause, start again and leave.
/// Popped, it gives back the best of the game's first count reached.
class GamePlayer extends StatefulWidget {
  final CanvasDocument document;
  final int? best;

  /// canOpen is whether the reader may take a copy into their own Canvas.
  final bool canOpen;
  const GamePlayer(
      {required this.document, this.best, this.canOpen = false, super.key});

  @override
  State<GamePlayer> createState() => _GamePlayerState();
}

class _GamePlayerState extends State<GamePlayer> {
  late final CanvasController _c =
      CanvasController(widget.document.copyWith(game: true));
  final FocusNode _focus = FocusNode();
  bool _started = false;
  bool _ended = false;
  int _reached = 0;

  String? get _firstCount =>
      widget.document.counts.isEmpty ? null : widget.document.counts.first.id;

  @override
  void initState() {
    super.initState();
    _c.addListener(_follow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _start();
      _focus.requestFocus();
    });
  }

  void _start() {
    _ended = false;
    _started = true;
    _c.gaming = true;
  }

  /// _follow keeps the best reached, and notices the game ending by itself:
  /// after its last scene, or told to end.
  void _follow() {
    var id = _firstCount;
    var run = _c.game;
    if (id != null && run != null) {
      _reached = math.max(_reached, run.countOf(_c.document, id));
    }
    if (_started && !_c.gaming && !_ended && mounted) {
      setState(() => _ended = true);
    }
  }

  void _leave() =>
      Navigator.of(context).pop(_firstCount == null ? null : _reached);

  void _again() {
    if (_c.gaming) _c.gaming = false;
    setState(_start);
  }

  Future<void> _open() async {
    var snackbar = SnackBarModel.of(context, listen: false);
    var doc = widget.document;
    var wanted = CanvasStorage.sanitizeName(doc.title) ?? "Game";
    var name = await CanvasStorage.uniqueName("", wanted);
    var ok = await CanvasStorage.save("", name, doc.copyWith(title: name));
    snackbar.success(ok
        ? "Opened in Canvas as $name."
        : "It could not be put in your Canvas.");
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    var key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _leave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP && _c.gaming) {
      _c.gamePaused = !_c.gamePaused;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _again();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _c.removeListener(_follow);
    if (_c.gaming) _c.gaming = false;
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var page = widget.document.size.size;
    var aspect =
        page.width <= 0 || page.height <= 0 ? 16 / 9 : page.width / page.height;
    const bar = TextStyle(fontSize: 11, color: Color(0xFFE6E7EA));
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF101114),
        body: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: Stack(fit: StackFit.expand, children: [
                  ListenableBuilder(
                    listenable: _c,
                    builder: (context, _) => CustomPaint(
                        key: const ValueKey("gamePlayerCanvas"),
                        painter: _GamePainter(_c)),
                  ),
                  ListenableBuilder(
                    listenable: _c,
                    builder: (context, _) => _c.gamePaused || _ended
                        ? ColoredBox(
                            color: const Color(0xAA101114),
                            child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_ended ? "Game over" : "Paused",
                                        style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white)),
                                    if (_ended && _firstCount != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                          "Best this time: $_reached"
                                          "${widget.best != null ? " · before: ${widget.best}" : ""}",
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFFC9CCD2))),
                                    ],
                                    const SizedBox(height: 14),
                                    FilledButton(
                                      key: const ValueKey("gamePlayerResume"),
                                      onPressed: _ended
                                          ? _again
                                          : () => _c.gamePaused = false,
                                      child:
                                          Text(_ended ? "Play again" : "Go on"),
                                    ),
                                  ]),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ]),
              ),
            ),
          ),
          Container(
            height: 34,
            color: const Color(0xFF16171B),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Flexible(
                child: Text("Esc to leave · P to pause · R to start again",
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: bar),
              ),
              const Spacer(),
              if (widget.canOpen) ...[
                TextButton(
                  key: const ValueKey("gamePlayerOpen"),
                  onPressed: _open,
                  child: const Text("Open in Canvas", style: bar),
                ),
                const SizedBox(width: 6),
              ],
              OutlinedButton(
                key: const ValueKey("gamePlayerLeave"),
                onPressed: _leave,
                child: const Text("Leave", style: bar),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// _GamePainter draws the game as it is now -- fitted to the box, every
/// count showing what the game has.
class _GamePainter extends CustomPainter {
  final CanvasController c;
  _GamePainter(this.c) : super(repaint: c.images);

  @override
  void paint(Canvas canvas, Size size) {
    var doc = c.gameView ?? c.document;
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
  bool shouldRepaint(_GamePainter old) => true;
}
