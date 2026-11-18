import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// panel_reader.dart is Panel mode in the app: a book read panel by panel
// (panel_reading.dart), back and forward stepping through each page's
// panels and on to the next page, gliding from one panel to the next and
// fading between pages. The canvas file player turns it on for a reader;
// the editor opens it full screen (showPanelReader) to try a book out.

/// showPanelReader opens [document] in Panel mode over the whole window,
/// at page [scene]; Escape or its close button shuts it.
Future<void> showPanelReader(
        BuildContext context, CanvasDocument document, CanvasImageStore images,
        {int scene = 0}) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xF0101114),
      pageBuilder: (context, _, __) => SafeArea(
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PanelReader(
              document: document,
              images: images,
              scene: scene,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );

class PanelReader extends StatefulWidget {
  final CanvasDocument document;
  final CanvasImageStore images;

  /// scene is the page it opens on, whole.
  final int scene;

  /// onClose shuts it, given; [extra] go beside its buttons.
  final VoidCallback? onClose;
  final List<Widget> extra;

  const PanelReader({
    required this.document,
    required this.images,
    this.scene = 0,
    this.onClose,
    this.extra = const [],
    super.key,
  });

  @override
  State<PanelReader> createState() => PanelReaderState();
}

class PanelReaderState extends State<PanelReader>
    with SingleTickerProviderStateMixin {
  late List<PanelStep> _steps = panelSteps(widget.document);
  late int _at = _startAt();
  int _from = -1;
  late final AnimationController _move = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320))
    ..value = 1;

  /// at is the step showing, for tests.
  int get at => _at;
  List<PanelStep> get steps => _steps;

  int _startAt() {
    var i = _steps.indexWhere((s) => s.scene == widget.scene);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(PanelReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      _steps = panelSteps(widget.document);
      _at = _at.clamp(0, _steps.isEmpty ? 0 : _steps.length - 1);
      _from = -1;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  /// step goes [by] stops on, from page to page at the ends of one.
  void step(int by) {
    var to = (_at + by).clamp(0, _steps.length - 1);
    if (to == _at) return;
    setState(() {
      _from = _at;
      _at = to;
    });
    _move.forward(from: 0);
  }

  KeyEventResult _key(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight ||
            LogicalKeyboardKey.arrowDown ||
            LogicalKeyboardKey.pageDown ||
            LogicalKeyboardKey.space:
        step(1);
      case LogicalKeyboardKey.arrowLeft ||
            LogicalKeyboardKey.arrowUp ||
            LogicalKeyboardKey.pageUp:
        step(-1);
      case LogicalKeyboardKey.escape when widget.onClose != null:
        widget.onClose!();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String _where() {
    if (_steps.isEmpty) return "";
    var s = _steps[_at];
    var name = widget.document.nameOf(s.scene);
    if (name.isEmpty) name = "Page ${s.scene + 1}";
    var onPage = [
      for (var x in _steps)
        if (x.scene == s.scene && !x.whole) x
    ];
    if (s.whole) return onPage.isEmpty ? name : "$name · whole page";
    return "$name · panel ${onPage.indexOf(s) + 1} of ${onPage.length}";
  }

  @override
  Widget build(BuildContext context) {
    var page = widget.document.size.size;
    var aspect =
        page.width <= 0 || page.height <= 0 ? 0.7 : page.width / page.height;
    const ink = Color(0xFFE8EAF0);
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, e) => _key(e),
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  key: const ValueKey("panelReaderView"),
                  behavior: HitTestBehavior.opaque,
                  // The left third back, the rest on, as a reader turns.
                  onTapUp: (d) =>
                      step(d.localPosition.dx < box.maxWidth / 3 ? -1 : 1),
                  child: AnimatedBuilder(
                    animation: _move,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _PanelPainter(
                        widget.document,
                        widget.images,
                        _steps,
                        _at,
                        _from,
                        Curves.easeInOut.transform(_move.value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          key: const ValueKey("panelReaderBack"),
          icon: const Icon(Icons.chevron_left, color: ink),
          tooltip: "Back",
          onPressed: _at > 0 ? () => step(-1) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180),
          child: Text(_where(),
              key: const ValueKey("panelReaderWhere"),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: ink)),
        ),
        IconButton(
          key: const ValueKey("panelReaderForward"),
          icon: const Icon(Icons.chevron_right, color: ink),
          tooltip: "Forward",
          onPressed: _at < _steps.length - 1 ? () => step(1) : null,
        ),
        ...widget.extra,
        if (widget.onClose != null)
          IconButton(
            key: const ValueKey("panelReaderClose"),
            icon: const Icon(Icons.close, color: ink),
            tooltip: "Close (Escape)",
            onPressed: widget.onClose,
          ),
      ]),
    ]);
  }
}

/// _PanelPainter draws step [at], arriving from [from] by [t]: on one page
/// the view glides and the dimming moves from one panel to the next;
/// between pages the new one fades in over the old.
class _PanelPainter extends CustomPainter {
  final CanvasDocument doc;
  final CanvasImageStore images;
  final List<PanelStep> steps;
  final int at, from;
  final double t;
  _PanelPainter(this.doc, this.images, this.steps, this.at, this.from, this.t)
      : super(repaint: images);

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;
    var page = doc.size.size;
    var to = steps[at];
    var was = from >= 0 && from < steps.length && t < 1 ? steps[from] : null;
    List<(Path, double)> lit(PanelStep s, double share) =>
        s.outline == null ? const [] : [(s.outline!, share)];
    if (was != null && was.scene == to.scene) {
      var view = Rect.lerp(panelView(was, page), panelView(to, page), t)!;
      paintPanelView(canvas, size, doc, to.scene, view,
          lit: [...lit(was, 1 - t), ...lit(to, t)], images: images);
      return;
    }
    paintPanelView(canvas, size, doc, to.scene, panelView(to, page),
        lit: lit(to, 1), images: images);
    if (was != null) {
      canvas.saveLayer(
          Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - t));
      paintPanelView(canvas, size, doc, was.scene, panelView(was, page),
          lit: lit(was, 1), images: images);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.at != at || old.from != from || old.t != t || old.doc != doc;
}
