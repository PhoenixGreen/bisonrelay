import 'dart:ui' as ui;
import 'dart:collection';
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// panel_kit.dart is the parts of the sectioned settings panel: a section
// that folds, holding cards; a row of picture tiles; a section's tools; and
// the stepper. Nothing here knows what an element is; see settings/README.md
// for the rows inside a section.

/// stepperHeight is a stepper's box. Taller than the other controls' because
/// the arrows are pressed rather than aimed at.
const double stepperHeight = 30;

/// CanvasStepper is a number with an arrow either side of it. The arrows
/// nudge it a [step] at a time, repeating while held; the number is dragged
/// sideways to run it, from the first pixel, and double-clicked to type one.
/// Changed from [defaultValue], its caption turns the accent colour and
/// gains a ↺ that puts it back.
class CanvasStepper extends StatefulWidget implements CanvasGrowable {
  @override
  double get least => width;

  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;

  /// step is how far an arrow moves it. Null is its last digit.
  final double? step;

  /// dragStep is how far one pixel of a drag moves it. Null is its last
  /// digit, or a fifth of [step] where that is coarser, so a whole range is
  /// not hundreds of pixels long.
  final double? dragStep;

  final String suffix;

  /// defaultValue is what it starts at, for the ↺. Null where it has no one
  /// value it starts at -- a position.
  final double? defaultValue;

  final double width;

  @override
  final bool grow;

  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  /// name keys its arrows, number and reset -- "$name-less" -- for a
  /// stepper drawn on behalf of a field that carries the key itself. Null is
  /// the stepper's own key.
  final String? name;

  /// fill makes it as wide as it is given, for one laid out by hand -- in a
  /// row of its own rather than a line of a group.
  final bool fill;

  const CanvasStepper({
    required this.label,
    this.name,
    this.fill = false,
    required this.value,
    required this.onChanged,
    this.min = -100000,
    this.max = 100000,
    this.decimals = 0,
    this.step,
    this.dragStep,
    this.suffix = "",
    this.defaultValue,
    this.width = 128,
    this.grow = true,
    this.onCommit,
    super.key,
  });

  /// changed is whether it is away from [defaultValue].
  bool get changed {
    var d = defaultValue;
    if (d == null) return false;
    return (value - d).abs() > math.pow(10, -decimals) / 2;
  }

  @override
  State<CanvasStepper> createState() => _CanvasStepperState();
}

class _CanvasStepperState extends State<CanvasStepper> {
  bool _editing = false;
  late final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  double _from = 0;
  double _startX = 0;
  bool _down = false;
  bool _dragging = false;

  Timer? _repeat;
  bool _held = false;

  /// _running is the value while an arrow is held, counted here rather than
  /// read back off the widget: the repeats can come faster than the panel
  /// rebuilds, and each one read from a value that had not caught up.
  double _running = 0;

  double get _digit => math.pow(10, -widget.decimals).toDouble();
  double get _step => widget.step ?? _digit;
  double get _dragStep =>
      widget.dragStep ?? math.max(_digit, (widget.step ?? 0) / 5);

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  /// _sub is the key of one of its parts, where it has a name to key them by.
  Key? _sub(String part) {
    var name = widget.name ??
        (widget.key is ValueKey<String>
            ? (widget.key as ValueKey<String>).value
            : null);
    return name == null ? null : ValueKey("$name-$part");
  }

  double _clamp(double v) => v.clamp(widget.min, widget.max).toDouble();

  /// _snap rounds to the field's digits, so arrows from 0.1 land on 0.3 and
  /// not on 0.30000000000000004.
  double _snap(double v) =>
      double.parse(_clamp(v).toStringAsFixed(widget.decimals));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finishTyping(keep: true);
    });
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTyping() {
    _text.text = _format(widget.value);
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finishTyping({required bool keep}) {
    if (!_editing) return;
    if (keep) {
      var parsed = double.tryParse(_text.text.trim());
      if (parsed != null) {
        widget.onChanged(_snap(parsed));
        widget.onCommit?.call();
      }
    }
    setState(() => _editing = false);
  }

  void _nudge(int by) {
    var next = _snap(_running + by * _step);
    // Held at a limit: nothing more to say, rather than the same value
    // written sixteen times a second.
    if (next == _running && _held) return;
    _running = next;
    widget.onChanged(_running);
  }

  void _press(int by) {
    _held = true;
    _running = widget.value;
    _nudge(by);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 380), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 60), (_) {
        if (mounted && _held) _nudge(by);
      });
    });
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
    if (!_held) return;
    _held = false;
    widget.onCommit?.call();
  }

  Widget _arrow(ThemeNotifier theme, IconData icon, int by, String key) {
    var can = by < 0 ? widget.value > widget.min : widget.value < widget.max;
    return Semantics(
      button: true,
      label: "${by < 0 ? "Less" : "More"} ${widget.label}",
      child: GestureDetector(
        key: _sub(key),
        behavior: HitTestBehavior.opaque,
        onTapDown: can ? (_) => _press(by) : null,
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: MouseRegion(
          cursor: can ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: SizedBox(
            width: CanvasDense.on(context)
                ? 28
                : CanvasCards.on(context)
                    ? 32
                    : 22,
            child: Icon(icon,
                size: CanvasDense.on(context)
                    ? 16
                    : CanvasCards.on(context)
                        ? 18
                        : 16,
                color: theme.colors.onSurfaceVariant
                    .withValues(alpha: can ? 0.9 : 0.3)),
          ),
        ),
      ),
    );
  }

  Widget _number(ThemeNotifier theme, bool changed) {
    if (_editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _finishTyping(keep: false),
        },
        child: TextField(
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"^-?[0-9]*\.?[0-9]*")),
          ],
          decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero),
          onSubmitted: (_) => _finishTyping(keep: true),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _from = widget.value;
          _startX = event.position.dx;
          _down = true;
          _dragging = false;
        },
        onPointerMove: (event) {
          if (!_down) return;
          var travelled = event.position.dx - _startX;
          // A few pixels of give, so the two presses of a double-click do
          // not nudge the number on their way.
          if (!_dragging && travelled.abs() < 3) return;
          _dragging = true;
          var fine = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
          widget.onChanged(_snap(_from + travelled * _dragStep * fine));
        },
        onPointerUp: (_) {
          _down = false;
          if (_dragging) widget.onCommit?.call();
          _dragging = false;
        },
        onPointerCancel: (_) {
          _down = false;
          _dragging = false;
        },
        child: GestureDetector(
          key: _sub("number"),
          onDoubleTap: _startTyping,
          child: Center(
            child: Text(
              "${_format(widget.value)}${widget.suffix}",
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: CanvasDense.on(context) ? 13 : 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  /// _built is what [build] made last, from [_was]: a stepper showing the
  /// same as it did is handed back as it was, so an edit elsewhere in the
  /// panel does not go through every stepper in it. Everything it does when
  /// pressed reads [widget] then, so nothing kept is out of date.
  Widget? _built;
  List<Object?> _was = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  Widget build(BuildContext context) {
    var w = widget;
    var now = [
      w.label,
      w.value,
      w.min,
      w.max,
      w.decimals,
      w.suffix,
      w.changed,
      w.width,
      w.grow,
      w.fill,
      w.name,
      w.key,
      _editing,
      ThemeNotifier.of(context).colors,
    ];
    var same = _built != null && now.length == _was.length;
    for (var i = 0; same && i < now.length; i++) {
      same = now[i] == _was[i];
    }
    if (!same) {
      _built = _build(context);
      _was = now;
    }
    return _built!;
  }

  Widget _build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var changed = widget.changed;
    var accent = theme.colors.primary;
    var card = CanvasCards.on(context);
    var caption = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: card ? 11.5 : 9.5,
                height: 1.1,
                fontWeight: changed ? FontWeight.w600 : FontWeight.normal,
                color: changed ? accent : theme.colors.onSurfaceVariant)),
      ),
      if (changed)
        Semantics(
          button: true,
          label: "Reset ${widget.label}",
          child: GestureDetector(
            key: _sub("reset"),
            onTap: () {
              widget.onChanged(widget.defaultValue!);
              widget.onCommit?.call();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.restart_alt,
                    size: card ? 13 : 11, color: accent),
              ),
            ),
          ),
        ),
    ]);
    var box = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
            CanvasDense.on(context) ? 9 : (card ? 10 : 7)),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
            color: changed
                ? accent.withValues(alpha: 0.55)
                : theme.colors.outlineVariant),
      ),
      // Stretched, so each arrow is pressed over the box's whole height,
      // not just over its icon.
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _arrow(theme, Icons.chevron_left, -1, "less"),
        Container(width: 1, color: theme.colors.outlineVariant),
        Expanded(child: _number(theme, changed)),
        Container(width: 1, color: theme.colors.outlineVariant),
        _arrow(theme, Icons.chevron_right, 1, "more"),
      ]),
    );
    if (card) {
      return Padding(
        padding: EdgeInsets.only(right: cardGapIn(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // No room kept for a caption it has not got: a look's row
            // stands its stepper level with its name.
            if (widget.label.isNotEmpty) ...[
              SizedBox(height: cardLabelHeightIn(context), child: caption),
              SizedBox(height: cardLabelGapIn(context)),
            ],
            widget.fill
                ? SizedBox(
                    width: double.infinity,
                    height: cardHeightIn(context),
                    child: box)
                : canvasSized(context,
                    min: CanvasControlScope.widthFor(context, widget.width),
                    height: cardHeightIn(context),
                    grow: widget.grow,
                    child: box),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: canvasCaptionedGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Caption and box together are as tall as any other captioned
          // control, so a stepper stands level with the buttons and fields
          // beside it: the box's extra height comes out of the gap.
          SizedBox(height: controlLabelHeight, child: caption),
          SizedBox(
              height: math.max(0.0,
                  controlWithLabelHeight - controlLabelHeight - stepperHeight)),
          widget.fill
              ? SizedBox(
                  width: double.infinity, height: stepperHeight, child: box)
              : canvasSized(context,
                  min: CanvasControlScope.widthFor(context, widget.width),
                  height: stepperHeight,
                  grow: widget.grow,
                  child: box),
        ],
      ),
    );
  }
}

/// CanvasKept is [builder]'s widget, built again only when one of [deps]
/// changes, or something it reads from above (the theme, say). Every edit
/// rebuilds the panel, and a widget handed back unchanged is a subtree
/// Flutter skips. What it is handed must be everything it shows, and what it
/// does when pressed must look up what is current then: a widget kept is a
/// callback kept.
class CanvasKept extends StatefulWidget {
  final List<Object?> deps;
  final WidgetBuilder builder;
  const CanvasKept({required this.deps, required this.builder, super.key});

  @override
  State<CanvasKept> createState() => _CanvasKeptState();
}

class _CanvasKeptState extends State<CanvasKept> {
  Widget? _built;
  List<Object?> _deps = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  Widget build(BuildContext context) {
    var deps = widget.deps;
    var same = _built != null && deps.length == _deps.length;
    for (var i = 0; same && i < deps.length; i++) {
      same = identical(deps[i], _deps[i]) || deps[i] == _deps[i];
    }
    if (!same) {
      _built = widget.builder(context);
      _deps = List.of(deps);
    }
    return _built!;
  }
}

/// CanvasTile is one choice in a row of [CanvasTiles]: a picture of what it
/// does and the word for it.
class CanvasTile<T> {
  final T value;
  final String label;

  /// preview draws what choosing it does. Null shows [icon] instead.
  final WidgetBuilder? preview;
  final IconData? icon;

  /// paint draws what choosing it does, as [preview] does -- once, into a
  /// small picture kept and drawn again as it is: see TileSnapshot. Preferred
  /// to [preview] for anything drawn through a layer or a filter.
  final TilePaint? paint;

  /// drawnFrom is everything [preview] draws from, where it is not just
  /// [value] -- the picture a filter is shown on. Given, or with no preview
  /// at all, a tile in a folding card is built once and kept until it
  /// changes; see CanvasKept.
  final Object? drawnFrom;

  const CanvasTile(this.value, this.label,
      {this.preview, this.icon, this.drawnFrom, this.paint});
}

/// TilePaint draws a tile's picture into [size].
typedef TilePaint = void Function(Canvas canvas, Size size);

/// _snapshots is every tile's picture, drawn once, the most recently drawn
/// last: a scrolled strip otherwise drew every tile's filter, blend layer and
/// shader again on every frame.
final LinkedHashMap<String, ui.Image> _snapshots = LinkedHashMap();
const int _snapshotsKept = 240;

/// TileSnapshot is [paint] drawn once at the size it is shown, kept as
/// [id], and drawn from then on as that picture with its corners rounded.
class TileSnapshot extends StatelessWidget {
  final String id;

  /// slot is which tile this is, whatever it shows: while [holding], the
  /// picture it showed last is shown again rather than a new one drawn.
  final String? slot;
  final TilePaint paint;
  final Color ground;
  final double radius;
  const TileSnapshot(
      {required this.id,
      this.slot,
      required this.paint,
      required this.ground,
      this.radius = 5,
      super.key});

  /// holding is whether a control is being dragged: every tile drawn from
  /// what it changes would be drawn again on every step of the drag --
  /// thirty tiles a step, some of them figures in 3D -- so each keeps its
  /// picture until the drag is let go.
  static bool Function() holding = _never;
  static bool _never() => false;

  /// letGo is the panels closed: the hook no longer holds their editor,
  /// and the pictures kept go.
  static void letGo() {
    holding = _never;
    for (var image in _snapshots.values) {
      image.dispose();
    }
    _snapshots.clear();
  }

  /// stoodIn counts the pictures drawn with something standing in for
  /// what is not ready -- a body still being made: a tile drawn so is not
  /// kept, and is drawn again when [arrived] says the real thing is here.
  static int Function() stoodIn = _none;
  static int _none() => 0;
  static Listenable? arrived;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.infinite,
      painter: _SnapshotPainter(id, slot, paint, ground, radius,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, arrived));
}

/// _lastIn is the snapshot each tile slot last showed, by its key.
final Map<String, String> _lastIn = {};

class _SnapshotPainter extends CustomPainter {
  final String id;
  final String? slot;
  final TilePaint draw;
  final Color ground;
  final double radius;
  final double ratio;
  _SnapshotPainter(this.id, this.slot, this.draw, this.ground, this.radius,
      this.ratio, Listenable? arrived)
      : super(repaint: arrived);

  /// _stale is whether this painter showed an older picture, held while a
  /// control was dragged: the next one draws afresh.
  bool _stale = false;

  ui.Image _image(Size size) {
    var w = math.max(1, (size.width * ratio).round());
    var h = math.max(1, (size.height * ratio).round());
    var key = "$id|${ground.toARGB32()}|${w}x$h";
    var at = slot == null ? null : "$slot|${w}x$h";
    var kept = _snapshots.remove(key);
    if (kept != null) {
      if (at != null) _lastIn[at] = key;
      return _snapshots[key] = kept;
    }
    if (at != null && TileSnapshot.holding()) {
      if (_snapshots[_lastIn[at]] case var held?) {
        _stale = true;
        return held;
      }
    }
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder)..scale(w / size.width, h / size.height);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var stood = TileSnapshot.stoodIn();
    draw(canvas, size);
    var picture = recorder.endRecording();
    var made = picture.toImageSync(w, h);
    picture.dispose();
    if (TileSnapshot.stoodIn() != stood) {
      // Not kept: drawn again when what stood in has arrived.
      _stale = true;
      return made;
    }
    if (at != null) _lastIn[at] = key;
    _snapshots[key] = made;
    while (_snapshots.length > _snapshotsKept) {
      _snapshots.remove(_snapshots.keys.first)!.dispose();
    }
    return made;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    var image = _image(size);
    var all = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(all, Radius.circular(radius)));
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        all,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnapshotPainter old) =>
      old._stale || old.id != id || old.ground != ground || old.ratio != ratio;
}

/// CanvasTiles is a choice made by looking rather than by reading: a grid of
/// small pictures, each named under it.
///
/// Pointed at, a tile is tried on the canvas through [onPreview] -- null when
/// the pointer leaves -- as a dropdown's options are; see CanvasDropdown. With
/// [multiple], each tile is switched on and off by itself and wears a tick.
class CanvasTiles<T> extends StatelessWidget {
  final String? label;
  final List<CanvasTile<T>> tiles;
  final bool Function(T) selected;
  final ValueChanged<T> onPick;
  final ValueChanged<T?>? onPreview;
  final int columns;
  final bool multiple;

  /// keyOf names each tile, for the tests.
  final String Function(T)? keyOf;

  /// previewHeight is how tall the picture on each tile is.
  final double previewHeight;

  /// help is what the choice does, behind the "?" of its card.
  final String help;

  /// ticked is which tiles wear a tick, where that is not the same as which
  /// are lit -- an effect that is on, whose settings are shut. Null is the
  /// lit ones, with [multiple].
  final bool Function(T)? ticked;

  /// scrolls lays the tiles in one line that scrolls sideways rather than
  /// in rows, at [tileWidth] each.
  final bool scrolls;
  final double tileWidth;

  /// foldAs makes the card fold, remembered under that name: shut, its tiles
  /// are one line that scrolls sideways, the one chosen in view and named in
  /// the heading; open, all of them.
  final String? foldAs;

  const CanvasTiles({
    this.scrolls = false,
    this.tileWidth = 78,
    this.help = "",
    this.ticked,
    this.foldAs,
    required this.tiles,
    required this.selected,
    required this.onPick,
    this.label,
    this.onPreview,
    this.columns = 3,
    this.multiple = false,
    this.keyOf,
    this.previewHeight = 38,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var gap = card ? 8.0 : 6.0;
    var grid = LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
      var each = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var t in tiles)
            SizedBox(
                width: math.max(40, each), child: _tile(context, theme, t)),
        ],
      );
    });
    if (card && foldAs != null) return _FoldingTiles<T>(tiles: this);
    if (card && scrolls) return _ScrollingTiles<T>(tiles: this);
    // In a section, a card of its own, named, with the "?" beside the name.
    if (card) {
      return canvasCard(context,
          title: label == null ? null : canvasCardTitle(context, label!),
          help: help,
          body:
              Padding(padding: const EdgeInsets.only(right: 10), child: grid));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: canvasRowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: controlLabelGap + 1),
              child: Text(label!,
                  style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      color: theme.colors.onSurfaceVariant)),
            ),
          LayoutBuilder(builder: (context, box) {
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = (width - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var t in tiles)
                  SizedBox(
                      width: math.max(40, each),
                      child: _tile(context, theme, t)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ThemeNotifier theme, CanvasTile<T> t,
      {bool hover = true, VoidCallback? tapped}) {
    var on = selected(t.value);
    var accent = theme.colors.primary;
    var tries = hover && onPreview != null && !multiple;
    return MouseRegion(
      onEnter: tries ? (_) => onPreview!(t.value) : null,
      onExit: tries ? (_) => onPreview!(null) : null,
      child: Semantics(
        button: true,
        selected: on,
        label: t.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: keyOf == null ? null : ValueKey(keyOf!(t.value)),
            borderRadius: BorderRadius.circular(8),
            onTap: tapped ??
                () {
                  onPreview?.call(null);
                  onPick(t.value);
                },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: on ? accent.withValues(alpha: 0.14) : null,
                border: Border.all(
                    color: on ? accent : theme.colors.outlineVariant,
                    width: on ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(children: [
                  if (t.paint != null)
                    // Drawn once and kept -- see TileSnapshot.
                    SizedBox(
                      height: previewHeight,
                      width: double.infinity,
                      child: TileSnapshot(
                          id: "${t.value.runtimeType}:${t.value}:"
                              "${t.drawnFrom.hashCode}",
                          slot: "${t.label}|${t.value.runtimeType}:${t.value}",
                          paint: t.paint!,
                          ground: theme.colors.surfaceContainerHighest),
                    )
                  else
                    Container(
                      height: previewHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: theme.colors.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: t.preview != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child:
                                  SizedBox.expand(child: t.preview!(context)))
                          : Icon(t.icon ?? Icons.circle_outlined,
                              size: 20,
                              color:
                                  on ? accent : theme.colors.onSurfaceVariant),
                    ),
                  if ((ticked?.call(t.value) ?? (multiple && on)))
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                        child: Icon(Icons.check,
                            size: 10, color: theme.colors.onPrimary),
                      ),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                        color: theme.colors.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// CanvasSections is a run of [CanvasSection]s, down the panel.
class CanvasSections extends StatefulWidget {
  final List<Widget> children;

  /// parts is what the element is made of -- a picture's layers -- shown
  /// over the sections, and over the menu's bar: not a section, so not one
  /// of its names.
  final Widget? parts;

  /// quick is the few settings the element is changed by most, under its
  /// parts and over its sections (see CanvasQuickStrip): never a section
  /// away, in either layout.
  final Widget? quick;

  const CanvasSections({
    required this.children,
    this.parts,
    this.quick,
    super.key,
  });

  @override
  State<CanvasSections> createState() => _CanvasSectionsState();
}

/// settingsAsMenu is whether element settings are laid out as a menu -- the
/// sections' names in a bar across the top, one section shown at a time --
/// rather than as sections down the panel that fold. Switched by the
/// settings panel's icon, and kept: see toggleSettingsLayout.
final ValueNotifier<bool> settingsAsMenu = ValueNotifier(false);

bool _layoutRead = false;

/// readSettingsLayout reads the layout kept from last time, once.
void readSettingsLayout() {
  if (_layoutRead) return;
  _layoutRead = true;
  StorageManager.readData("canvasSettingsMenu").then((v) {
    if (v is bool) settingsAsMenu.value = v;
  });
  StorageManager.readData("canvasSettingsMenuTab").then((v) {
    if (v is String && _menuChosen == null) _menuChosen = v;
  });
}

/// toggleSettingsLayout swaps the layout, and keeps it.
void toggleSettingsLayout() {
  settingsAsMenu.value = !settingsAsMenu.value;
  StorageManager.saveData("canvasSettingsMenu", settingsAsMenu.value);
}

/// _menuChosen is the section last chosen in the menu, as "remember|title":
/// the same section if it is there, else one of the same name -- Animation
/// on a text and then on a picture -- else the first.
String? _menuChosen;

/// _MenuItem is one section as the menu names it: its name, and -- for the
/// end of the bar, where they go in the menu -- its "?" and whether it has
/// a reset to offer. [state] is the section, for its reset and action.
class _MenuItem {
  final String remember;
  final String title;
  final IconData icon;
  final bool changed;
  final String help;
  final bool resets;
  final Widget? action;
  final _CanvasSectionState? state;
  const _MenuItem(this.remember, this.title, this.icon, this.changed,
      {this.help = "", this.resets = false, this.action, this.state});

  /// Equal whatever its [action]: that is a widget, made anew at every
  /// build, and comparing it had every build of the panel cause another.
  @override
  bool operator ==(Object other) =>
      other is _MenuItem &&
      other.remember == remember &&
      other.title == title &&
      other.icon == icon &&
      other.changed == changed &&
      other.help == help &&
      other.resets == resets;

  @override
  int get hashCode => Object.hash(remember, title, icon, changed, help, resets);
}

/// _MenuScope tells the sections under a menu which of them is chosen.
/// [owner] null is no menu: a section inside a chosen section's body is
/// drawn as a section again.
class _MenuScope extends InheritedWidget {
  final _CanvasSectionsState? owner;
  final String? active;
  const _MenuScope(
      {required this.owner, required this.active, required super.child});

  static _MenuScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MenuScope>();

  @override
  bool updateShouldNotify(_MenuScope old) =>
      old.active != active || old.owner != owner;
}

class _CanvasSectionsState extends State<CanvasSections> {
  /// _items is the sections found under the menu, in order. Found by
  /// looking, after a frame, rather than read off [CanvasSections.children]:
  /// a background's sections are built deep inside its own settings.
  List<_MenuItem> _items = const [];
  bool _looking = false;
  final ScrollController _bar = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  final GlobalKey _barView = GlobalKey();
  String? _shown;

  /// _scroll is the panel's scroll, followed so the bar stays at its top --
  /// see _follow.
  ScrollPosition? _scroll;

  /// _stick is how far down its place the bar is drawn, to be at the top of
  /// the panel while the sections under it are scrolled past.
  double _stick = 0;
  final GlobalKey _under = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var next = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (next != _scroll) {
      _scroll?.removeListener(_follow);
      _scroll = next;
      _scroll?.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _scroll?.removeListener(_follow);
    _bar.dispose();
    super.dispose();
  }

  /// _barRoom is the bar's height and the room round it.
  static const double _barRoom = 38 + 2 + 6;

  /// _follow keeps the bar at the top of the panel: scrolled past its own
  /// place, it is drawn that much further down, as far as the end of the
  /// sections under it.
  void _follow() {
    var place = _under.currentContext?.findRenderObject();
    var view = Scrollable.maybeOf(context, axis: Axis.vertical)
        ?.context
        .findRenderObject();
    if (place is! RenderBox || view is! RenderBox || !place.attached) return;
    var top = place.localToGlobal(Offset.zero, ancestor: view).dy;
    var most = math.max(0.0, place.size.height - _barRoom);
    var stick = (-top).clamp(0.0, most).toDouble();
    if ((stick - _stick).abs() > 0.25 && mounted) {
      setState(() => _stick = stick);
    }
  }

  /// _look finds the sections, after this frame.
  void _look() {
    if (_looking) return;
    _looking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looking = false;
      if (!mounted) return;
      var found = <_MenuItem>[];
      void visit(Element e) {
        if (e is StatefulElement && e.state is _CanvasSectionState) {
          var state = e.state as _CanvasSectionState;
          var w = state.widget;
          found.add(_MenuItem(w.remember, w.title, w.icon, w.changes > 0,
              help: state._help,
              resets: w.onReset != null,
              action: w.action,
              state: state));
          return;
        }
        e.visitChildren(visit);
      }

      context.visitChildElements(visit);
      if (!listEquals(found, _items)) {
        setState(() => _items = found);
      } else {
        // The same sections: their newest actions, shown at the next build.
        _items = found;
      }
    });
  }

  /// _active is the section to show among [_items].
  String? get _active {
    if (_items.isEmpty) return null;
    var chosen = _menuChosen;
    if (chosen != null) {
      var bar = chosen.indexOf("|");
      var remember = bar < 0 ? chosen : chosen.substring(0, bar);
      var title = bar < 0 ? "" : chosen.substring(bar + 1);
      for (var i in _items) {
        if (i.remember == remember) return i.remember;
      }
      for (var i in _items) {
        if (i.title == title) return i.remember;
      }
      // Position is a rebuilt panel's Layout (Ken, 2026-11-11), and the
      // other way: the same section, carried between the two.
      var same = const {"Position": "Layout", "Layout": "Position"}[title];
      for (var i in _items) {
        if (i.title == same) return i.remember;
      }
    }
    return _items.first.remember;
  }

  void _choose(_MenuItem item) {
    _menuChosen = "${item.remember}|${item.title}";
    StorageManager.saveData("canvasSettingsMenuTab", _menuChosen);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: settingsAsMenu,
      builder: (context, menu, _) {
        if (!menu) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.parts != null) widget.parts!,
              if (widget.quick != null) widget.quick!,
              ...widget.children,
            ],
          );
        }
        _look();
        var active = _active;
        // Where the section is once laid out, the bar is put back where it
        // belongs.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow();
        });
        // The bar over the sections, drawn after them so what scrolls under
        // it goes under it; moved down to stay at the top of the panel.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.parts != null) widget.parts!,
            if (widget.quick != null) widget.quick!,
            Stack(key: _under, children: [
              Padding(
                padding: const EdgeInsets.only(top: _barRoom),
                child: _MenuScope(
                  owner: this,
                  active: active,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ),
              ),
              Positioned(
                top: _stick,
                left: 0,
                right: 0,
                child: _menuBar(context, active),
              ),
            ]),
          ],
        );
      });

  /// _menuBar is the menu: a name for each section, in a line that scrolls
  /// sideways, the one chosen bold and underlined -- and at its end, kept in
  /// view, the chosen section's "?", action and reset.
  Widget _menuBar(BuildContext context, String? active) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    // The one chosen brought into view, once each time it changes.
    if (active != null && active != _shown) {
      _shown = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Sideways only: ensureVisible would scroll the panel too, up or
        // down to the bar.
        var tab = _tabKeys[active]?.currentContext?.findRenderObject();
        var view = _barView.currentContext?.findRenderObject();
        if (tab is! RenderBox || view is! RenderBox || !_bar.hasClients) {
          return;
        }
        var left = tab.localToGlobal(Offset.zero, ancestor: view).dx;
        var right = left + tab.size.width;
        var width = view.size.width, now = _bar.offset;
        var target = left < 0
            ? now + left
            : right > width
                ? now + right - width
                : now;
        _bar.jumpTo(target.clamp(0.0, _bar.position.maxScrollExtent));
      });
    }
    Widget tab(_MenuItem item) {
      var on = item.remember == active;
      return InkWell(
        key: _tabKeys.putIfAbsent(item.remember, () => GlobalKey()),
        onTap: () => _choose(item),
        child: Container(
          key: ValueKey("menuTab-${item.remember}"),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: on ? accent : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(item.title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? theme.colors.onSurface : muted)),
            if (item.changed)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(left: 5, bottom: 6),
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
          ]),
        ),
      );
    }

    var chosen = _items.where((i) => i.remember == active).firstOrNull;
    var section = chosen?.state;
    var trailing = <Widget>[
      if (chosen != null && chosen.help.isNotEmpty)
        CanvasHint(chosen.help, round: true),
      if (chosen?.action case var action?) action,
      if (chosen != null && chosen.changed && chosen.resets)
        CanvasIconButton(
          key: ValueKey("sectionReset-${chosen.remember}"),
          tight: true,
          icon: Icons.restart_alt,
          tooltip: "Reset ${chosen.title}",
          onPressed: () => section?.widget.onReset?.call(),
        ),
    ];
    return Container(
      key: const ValueKey("settingsMenu"),
      height: 38,
      // Close over the first setting: the bar names the section, so there
      // is no heading between them.
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Row(children: [
        Expanded(
            child: ClipRRect(
          key: _barView,
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            controller: _bar,
            scrollDirection: Axis.horizontal,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var item in _items)
                Material(
                  type: MaterialType.transparency,
                  child: tab(item),
                ),
            ]),
          ),
        )),
        for (var t in trailing)
          Padding(padding: const EdgeInsets.only(right: 6), child: t),
      ]),
    );
  }
}

/// CanvasSection is one subject of an element's settings (where it is, its
/// mask, its colour) as a card that folds. Shut, it is its icon, its name and
/// a line saying how it is set, so the panel reads as a summary. [changes]
/// puts a dot on it and, open, a reset beside the chevron. Open, what is
/// inside is in cards: see CanvasCards.
class CanvasSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String summary;

  /// scope is a tag beside the title for a section that is not about what
  /// the rest are -- "Whole image" on a picture's frame, under a layer's
  /// settings.
  final String? scope;

  final int changes;
  final VoidCallback? onReset;

  /// action is a button on the heading row, outside its fold: what a
  /// section does without being opened -- refreshing a table's data.
  final Widget? action;

  /// remember names where its open state is kept, as CanvasExpander's.
  final String remember;
  final bool initiallyOpen;

  /// forceOpen opens it, whenever it turns true: a tool in hand opens the
  /// section it belongs to, picked from the keyboard or not.
  final bool forceOpen;
  final List<Widget> children;

  /// glyph is drawn instead of [icon]: a rebuilt panel's sections are drawn
  /// with its prototype's own (see SectionGlyph).
  final SectionGlyph? glyph;

  const CanvasSection({
    required this.icon,
    this.glyph,
    required this.title,
    required this.remember,
    required this.children,
    this.summary = "",
    this.scope,
    this.changes = 0,
    this.onReset,
    this.action,
    this.initiallyOpen = false,
    this.forceOpen = false,
    super.key,
  });

  /// openAll starts every section open, for the tests of what a control
  /// does rather than of where it is folded away.
  @visibleForTesting
  static bool openAll = false;

  @override
  State<CanvasSection> createState() => _CanvasSectionState();
}

class _CanvasSectionState extends State<CanvasSection> {
  late bool _open = CanvasSection.openAll ||
      (rememberedSection(widget.remember) ?? widget.initiallyOpen);

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) {
      _open = true;
    } else if (!CanvasSection.openAll &&
        rememberedSection(widget.remember) == null) {
      restoreSection(widget.remember, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  @override
  void didUpdateWidget(CanvasSection old) {
    super.didUpdateWidget(old);
    if (widget.forceOpen && !old.forceOpen && !_open) {
      _open = true;
      keepSection(widget.remember, true);
    }
    // In the menu, a tool taken up shows its section, as it opens it here.
    if (widget.forceOpen && !old.forceOpen) {
      var owner = _MenuScope.of(context)?.owner;
      if (owner != null) {
        var item = _MenuItem(
            widget.remember, widget.title, widget.icon, widget.changes > 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (owner.mounted) owner._choose(item);
        });
      }
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    keepSection(widget.remember, _open);
  }

  /// _help is the notes among the section's own children -- a hint not in
  /// any card -- said once, by the "?" on its heading row.
  String get _help => [
        for (var c in widget.children)
          if (c is CanvasHint) c.message
      ].join("\n\n");

  /// _heading is the section's heading line: its icon, its name and what is
  /// set in it, and -- open, with something changed -- its reset.
  Widget _heading(ThemeNotifier theme, bool open, bool changed) {
    var dense = CanvasDense.on(context);
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    return Row(children: [
      Expanded(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey("section-${widget.remember}"),
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(dense ? 8 : 9),
                    color: open && !dense
                        ? accent.withValues(alpha: 0.16)
                        : theme.colors.surfaceContainerHighest,
                  ),
                  child: widget.glyph != null
                      ? CustomPaint(
                          painter: _GlyphPainter(widget.glyph!, muted))
                      : Icon(widget.icon,
                          size: 16, color: open && !dense ? accent : muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: dense ? 14 : 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.onSurface)),
                        ),
                        if (widget.scope != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: theme.colors.outlineVariant),
                            ),
                            child: Text(widget.scope!,
                                style: TextStyle(fontSize: 10, color: muted)),
                          ),
                        ],
                      ]),
                      if (widget.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(widget.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: dense ? 12 : 10.5, color: muted)),
                        ),
                    ],
                  ),
                ),
                if (changed)
                  Container(
                    key: ValueKey("sectionChanged-${widget.remember}"),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
              ]),
            ),
          ),
        ),
      ),
      // Outside the heading's ink, so pressing them does not fold the
      // section; all left of the fold's arrow, which keeps every heading's
      // far right the same.
      if (_help.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CanvasHint(_help, round: true),
        ),
      if (widget.action != null)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: widget.action!,
        ),
      if (open && changed && widget.onReset != null)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CanvasIconButton(
            key: ValueKey("sectionReset-${widget.remember}"),
            tight: true,
            icon: Icons.restart_alt,
            tooltip: "Reset ${widget.title}",
            onPressed: () => widget.onReset?.call(),
          ),
        ),
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey("sectionFold-${widget.remember}"),
          borderRadius: BorderRadius.circular(8),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
            child: AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(Icons.chevron_right, size: 20, color: muted),
            ),
          ),
        ),
      ),
    ]);
  }

  /// _menuBody is the section as the menu shows it, chosen: everything in
  /// it and nothing over it -- its name is in the bar, and its "?", action
  /// and reset at the bar's end.
  Widget _menuBody() => RepaintBoundary(
        // A section inside this one is a section again, not a menu item.
        child: _MenuScope(
          owner: null,
          active: null,
          child: CanvasCards(
            title: widget.title,
            child: Padding(
              key: ValueKey("sectionBody-${widget.remember}"),
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c in widget.children)
                    if (c is! CanvasHint) c
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // Under a menu, only the section chosen is drawn, and drawn open.
    var menu = _MenuScope.of(context);
    if (menu?.owner case var owner?) {
      owner._look();
      if (menu!.active != widget.remember) return const SizedBox.shrink();
      return _menuBody();
    }
    var open = _open;
    var changed = widget.changes > 0;
    // Painted on its own: one section changed is that section painted
    // again, not the whole panel.
    return RepaintBoundary(
        child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: open
            ? theme.colors.surfaceContainerHighest.withValues(alpha: 0.25)
            : null,
        border: Border.all(
            color: open
                ? theme.colors.outline.withValues(alpha: 0.5)
                : theme.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The heading is kept unless what it says has changed: rebuilt on
          // every edit, the headings were half of a shut panel's work.
          CanvasKept(
            deps: [
              widget.icon,
              widget.title,
              widget.summary,
              widget.scope,
              changed,
              open,
              widget.onReset != null,
              _help,
              widget.action,
              theme.colors,
            ],
            builder: (context) => _heading(theme, open, changed),
          ),
          if (open)
            CanvasCards(
              title: widget.title,
              child: Padding(
                key: ValueKey("sectionBody-${widget.remember}"),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c in widget.children)
                      if (c is! CanvasHint) c
                  ],
                ),
              ),
            ),
        ],
      ),
    ));
  }
}

/// _ToolRow is a line of tools that scrolls sideways, with the one at
/// [active] brought into view whenever it changes -- only as far as it
/// takes, so a tool already in view stays where it is.
class _ToolRow extends StatefulWidget {
  final int active;
  final double step;
  final double each;
  final Widget Function(ScrollController) builder;
  const _ToolRow(
      {required this.active,
      required this.step,
      required this.each,
      required this.builder});

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  final ScrollController _scroll = ScrollController();
  int _shown = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var at = widget.active;
    if (at >= 0 && at != _shown) {
      _shown = at;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        var p = _scroll.position;
        var left = at * widget.step, right = left + widget.each;
        var now = _scroll.offset, width = p.viewportDimension;
        var target = left < now
            ? left
            : right > now + width
                ? right - width
                : now;
        _scroll.jumpTo(target.clamp(0.0, p.maxScrollExtent).toDouble());
      });
    } else if (at < 0) {
      _shown = -1;
    }
    return widget.builder(_scroll);
  }
}

/// CanvasToolTiles is a section's tools, as tiles with their names under
/// them, and -- on a line of their own below -- the settings of the one in
/// hand. Pressing the tool in hand puts it down again.
class CanvasToolTiles<T> extends StatelessWidget {
  final List<(T, IconData, String)> tools;
  final T? active;
  final ValueChanged<T?> onPick;
  final String Function(T) keyOf;
  final String Function(T) tooltipOf;

  /// settings are the active tool's, under the tiles.
  final List<Widget> settings;

  /// help is what the tools are for, behind the "?" of their card.
  final String help;

  /// alsoActive lights a tool besides the one in hand -- the select tool
  /// whose picks an align tool lines up.
  final bool Function(T)? alsoActive;

  /// lit is whether [tool] is drawn as in hand.
  bool lit(T tool) => tool == active || (alsoActive?.call(tool) ?? false);

  /// idle is what is said under the tiles with none of them picked.
  final String idle;

  /// title is the card's name.
  final String title;

  const CanvasToolTiles({
    this.idle = "Pick a tool to work on the canvas.",
    this.title = "Tools",
    this.help = "",
    this.alsoActive,
    required this.tools,
    required this.active,
    required this.onPick,
    required this.keyOf,
    required this.tooltipOf,
    this.settings = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    var card = CanvasCards.on(context);
    var held = [
      for (var t in tools)
        if (t.$1 == active) t
    ].firstOrNull;
    // The tool's own notes go behind the card's "?", never on a row of its
    // settings.
    var notes = [
      for (var w in settings)
        if (w is CanvasHint) w.message
    ];
    var controls = [
      for (var w in settings)
        if (w is! CanvasHint) w
    ];
    var about = [if (help.isNotEmpty) help, ...notes].join("\n\n");
    var body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(right: card ? 10 : 0),
          // A line that scrolls sideways, each tile its own width: squeezed
          // to fit, six tools came out too narrow for their names.
          child: LayoutBuilder(builder: (context, box) {
            const gap = 6.0;
            var n = tools.length;
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = math.max(64.0, (width - gap * (n - 1)) / n);
            // The tool in hand kept in view, when picked from elsewhere (a
            // layers strip's Add, a key).
            return _ToolRow(
                active: tools.indexWhere((t) => t.$1 == active),
                step: each + gap,
                each: each,
                builder: (scroll) => SizedBox(
                    height: card ? 56 : 46,
                    child: SingleChildScrollView(
                        key: const ValueKey("toolsRow"),
                        controller: scroll,
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (var (i, (tool, icon, short)) in tools.indexed)
                            Padding(
                                padding:
                                    EdgeInsets.only(left: i == 0 ? 0 : gap),
                                child: SizedBox(
                                  width: each,
                                  child: Tooltip(
                                    message: tooltipOf(tool),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        key: ValueKey(keyOf(tool)),
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => onPick(
                                            tool == active ? null : tool),
                                        child: Container(
                                          height: card ? 56 : 46,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            color: lit(tool)
                                                ? accent.withValues(alpha: 0.16)
                                                : null,
                                            border: Border.all(
                                                color: lit(tool)
                                                    ? accent
                                                    : theme
                                                        .colors.outlineVariant,
                                                width: lit(tool) ? 1.5 : 1),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(icon,
                                                  size: card ? 20 : 18,
                                                  color: lit(tool)
                                                      ? accent
                                                      : theme.colors
                                                          .onSurfaceVariant),
                                              const SizedBox(height: 4),
                                              Text(short,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize:
                                                          card ? 10.5 : 9.5,
                                                      color: theme
                                                          .colors.onSurface)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                        ]))));
          }),
        ),
        if (held == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(idle,
                style: TextStyle(
                    fontSize: card ? 12 : 10.5,
                    color: theme.colors.onSurfaceVariant)),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            child: Text(tooltipOf(held.$1),
                style: TextStyle(
                    fontSize: card ? 12.5 : 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.onSurface)),
          ),
          if (controls.isNotEmpty)
            CanvasWrap(
                runSpacing: card ? cardGapIn(context) : canvasRowGap,
                children: controls),
        ],
      ],
    );
    if (card) {
      return canvasCard(context,
          title: canvasCardTitle(context, title), help: about, body: body);
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
        child: body);
  }
}

/// _labelRoom is what a tile in a strip needs under its picture: its border
/// and padding and a line of its name at the reader's text size.
double _labelRoom(BuildContext context) =>
    math.max(30.0, 16 + MediaQuery.textScalerOf(context).scale(9.5) * 1.35);

/// _ScrollingTiles is a card of tiles in one line that scrolls sideways,
/// with the one chosen brought into view, so a kind chosen at the far end is
/// seen on coming back to the panel.
class _ScrollingTiles<T> extends StatefulWidget {
  final CanvasTiles<T> tiles;
  const _ScrollingTiles({required this.tiles, super.key});

  @override
  State<_ScrollingTiles<T>> createState() => _ScrollingTilesState<T>();
}

class _ScrollingTilesState<T> extends State<_ScrollingTiles<T>> {
  final ScrollController _strip = ScrollController();

  /// _shown is the tile last brought into view: brought there once when it
  /// is chosen, not on every rebuild, which would snap the line back under
  /// somebody scrolling it.
  int _shown = -1;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var t = widget.tiles;
    const gap = 8.0;
    var at = t.tiles.indexWhere((tile) => t.selected(tile.value));
    return canvasCard(context,
        title: t.label == null ? null : canvasCardTitle(context, t.label!),
        help: t.help,
        body: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: LayoutBuilder(builder: (context, box) {
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            if (at >= 0 && at != _shown) {
              _shown = at;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_strip.hasClients) return;
                // Only as far as it takes to be in view: one already in
                // view stays where it is.
                var left = at * (t.tileWidth + gap);
                var right = left + t.tileWidth;
                var now = _strip.offset;
                var target = left < now
                    ? left
                    : right > now + width
                        ? right - width
                        : now;
                _strip.jumpTo(target
                    .clamp(0.0, _strip.position.maxScrollExtent)
                    .toDouble());
              });
            }
            return SizedBox(
              height: t.previewHeight + _labelRoom(context),
              // Every tile built, not only those in view: a handful, and a
              // tile scrolled out of view is still one to reach.
              child: SingleChildScrollView(
                key: ValueKey("tilesRow-${t.label}"),
                controller: _strip,
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var (i, tile) in t.tiles.indexed)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                      child: SizedBox(
                          width: t.tileWidth,
                          child: t._tile(context, theme, tile, hover: false)),
                    ),
                ]),
              ),
            );
          }),
        ));
  }
}

/// _FoldingTiles is a card of tiles that folds: see CanvasTiles.foldAs.
class _FoldingTiles<T> extends StatefulWidget {
  final CanvasTiles<T> tiles;
  const _FoldingTiles({required this.tiles, super.key});

  @override
  State<_FoldingTiles<T>> createState() => _FoldingTilesState<T>();
}

class _FoldingTilesState<T> extends State<_FoldingTiles<T>> {
  late bool _open = rememberedSection(widget.tiles.foldAs!) ?? false;

  /// _kept is [tile], built once and kept while it shows the same -- see
  /// CanvasKept. Pressed, it picks through the tiles as they are now: the
  /// pick of the build it was kept from would write back what that build
  /// knew.
  Widget _kept(BuildContext context, ThemeNotifier theme, CanvasTile<T> tile) {
    var t = widget.tiles;
    void tapped() => widget.tiles.onPick(tile.value);
    if ((tile.preview != null || tile.paint != null) &&
        tile.drawnFrom == null) {
      return t._tile(context, theme, tile, hover: false, tapped: tapped);
    }
    return CanvasKept(
      key: ValueKey(tile.value),
      deps: [
        tile.value,
        tile.label,
        tile.icon,
        tile.drawnFrom,
        t.selected(tile.value),
        t.ticked?.call(tile.value),
        t.previewHeight,
        theme.colors,
      ],
      builder: (context) => widget.tiles
          ._tile(context, theme, tile, hover: false, tapped: tapped),
    );
  }

  final ScrollController _strip = ScrollController();

  /// _shown is the tile last brought into view, as in _ScrollingTiles.
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    var key = widget.tiles.foldAs!;
    if (rememberedSection(key) == null) {
      restoreSection(key, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _shown = -1;
    });
    keepSection(widget.tiles.foldAs, _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var t = widget.tiles;
    const gap = 8.0;
    var chosen = [
      for (var tile in t.tiles)
        if (t.selected(tile.value)) tile
    ];
    var title = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey("tilesFold-${t.foldAs}"),
        borderRadius: BorderRadius.circular(6),
        onTap: _toggle,
        child: Row(children: [
          AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(Icons.chevron_right,
                size: 18, color: theme.colors.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          canvasCardTitle(context, t.label ?? ""),
          const SizedBox(width: 8),
          Flexible(
            child: Text(chosen.map((c) => c.label).join(" · "),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5, color: theme.colors.onSurfaceVariant)),
          ),
        ]),
      ),
    );
    var body = LayoutBuilder(builder: (context, box) {
      var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
      var each = math.max(40.0, (width - gap * (t.columns - 1)) / t.columns);
      // Open, clicked too: a tile tried on a hover would be the tile chosen,
      // and the settings hanging on it would come and go under the pointer.
      if (_open) {
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var tile in t.tiles)
            SizedBox(width: each, child: _kept(context, theme, tile)),
        ]);
      }
      // The one chosen brought into view -- once, when it is chosen.
      var at = t.tiles.indexWhere((tile) => t.selected(tile.value));
      if (at >= 0 && at != _shown) {
        _shown = at;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_strip.hasClients) return;
          var target = at * (each + gap) - (width - each) / 2;
          _strip.jumpTo(
              target.clamp(0.0, _strip.position.maxScrollExtent).toDouble());
        });
      }
      return SizedBox(
        height: t.previewHeight + _labelRoom(context),
        child: SingleChildScrollView(
          key: ValueKey("tilesStrip-${t.foldAs}"),
          controller: _strip,
          scrollDirection: Axis.horizontal,
          // Clicked, never tried on a hover: trying a tile chose it, the strip
          // scrolled it into view, and the pointer landed on the next.
          child: Row(children: [
            for (var (i, tile) in t.tiles.indexed)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                child:
                    SizedBox(width: each, child: _kept(context, theme, tile)),
              ),
          ]),
        ),
      );
    });
    return canvasCard(context,
        title: title,
        help: t.help,
        body: Padding(padding: const EdgeInsets.only(right: 10), child: body));
  }
}

/// _unlinked is which side fields have been split into their four, for this
/// run of the app.
final Set<String> _unlinked = {};

/// forgetPanelsForTest puts the panels back as a new run of the app has
/// them: see forgetSectionsForTest.
@visibleForTesting
void forgetPanelsForTest() {
  TileSnapshot.letGo();
  _lastIn.clear();
  _unlinked.clear();
  settingsAsMenu.value = false;
  CanvasSection.openAll = false;
}

/// CanvasSidesField is four numbers that are usually one -- a border's
/// sides, a box's corners, its padding -- as one stepper with a link beside
/// it. Pressed, the link splits it into the four, two to a line; pressed
/// again, they join on the first. Four that already differ show split.
class CanvasSidesField extends StatefulWidget {
  final String label;

  /// name keys the one stepper, and its link as "${name}Link".
  final String name;

  /// values are the four, in the order of [parts].
  final List<double> values;

  /// parts are what each of the four is called on its own stepper, and
  /// [partKeys] how each is keyed.
  final List<String> parts;
  final List<String> partKeys;

  final double max;
  final double step;

  /// onChanged sets one of the four -- or, with a null side, all of them.
  final void Function(int? side, double value) onChanged;
  final VoidCallback? onCommit;

  const CanvasSidesField({
    required this.label,
    required this.name,
    required this.values,
    required this.parts,
    required this.partKeys,
    required this.onChanged,
    this.onCommit,
    this.max = 400,
    this.step = 1,
    super.key,
  });

  bool get even => values.every((v) => v == values.first);

  @override
  State<CanvasSidesField> createState() => _CanvasSidesFieldState();
}

class _CanvasSidesFieldState extends State<CanvasSidesField> {
  bool get _split => _unlinked.contains(widget.name) || !widget.even;

  void _toggle() {
    if (_split) {
      _unlinked.remove(widget.name);
      // Joined on the first, so the one number is true of all four.
      if (!widget.even) {
        widget.onChanged(null, widget.values.first);
        widget.onCommit?.call();
      }
    } else {
      _unlinked.add(widget.name);
    }
    setState(() {});
  }

  CanvasStepper _stepper(int? side) => CanvasStepper(
        key: ValueKey(side == null ? widget.name : widget.partKeys[side]),
        label: side == null ? widget.label : widget.parts[side],
        value: side == null ? widget.values.first : widget.values[side],
        min: 0,
        max: widget.max,
        step: widget.step,
        dragStep: 1,
        fill: true,
        onChanged: (v) => widget.onChanged(side, v),
        onCommit: widget.onCommit,
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var split = _split;
    var link = CanvasIconButton(
      key: ValueKey("${widget.name}Link"),
      // Not the chain the proportion lock wears: these are four sides,
      // shown as one box or as its edges.
      icon: split ? Icons.border_outer : Icons.border_all,
      tooltip: split ? "All four the same" : "Set each one",
      active: split,
      onPressed: _toggle,
    );
    Widget body;
    if (!split) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _stepper(null)),
        link,
      ]);
    } else {
      Widget pair(int a, int b) => Row(children: [
            Expanded(child: _stepper(a)),
            Expanded(child: _stepper(b)),
          ]);
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(widget.label,
                    style: TextStyle(
                        fontSize: CanvasCards.on(context) ? 11.5 : 9.5,
                        color: theme.colors.onSurfaceVariant)),
              ),
              pair(0, 1),
              const SizedBox(height: 6),
              pair(2, 3),
            ],
          ),
        ),
        Padding(
            padding: EdgeInsets.only(
                top: CanvasCards.on(context) ? 0 : controlLabelHeight),
            child: link),
      ]);
    }
    // A line of its own, the width of the panel -- or, along the band over
    // the canvas, which has no width to fill, a width of its own.
    return SizedBox(
      width: CanvasControlScope.isInline(context) ? 260 : double.infinity,
      child: body,
    );
  }
}

/// SectionGlyph is one of a rebuilt panel's section icons, as its prototype
/// draws them: what it says, how it looks, where it is, how it moves, and
/// the rest.
enum SectionGlyph { content, look, layout, motion, more }

/// _GlyphPainter draws [glyph] from the prototype's own lines (its 24-unit
/// SVG paths, stroked 1.8 wide with round ends) in a 16-pixel square at the
/// middle of the box.
class _GlyphPainter extends CustomPainter {
  final SectionGlyph glyph;
  final Color colour;
  const _GlyphPainter(this.glyph, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate((size.width - 16) / 2, (size.height - 16) / 2);
    canvas.scale(16 / 24);
    var line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void seg(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);
    switch (glyph) {
      case SectionGlyph.content:
        seg(5, 6, 19, 6);
        seg(5, 11, 19, 11);
        seg(5, 16, 14, 16);
      case SectionGlyph.look:
        canvas.drawPath(
            Path()
              ..moveTo(12, 3)
              ..lineTo(14.5, 8.5)
              ..lineTo(20, 9)
              ..lineTo(16, 13)
              ..lineTo(17, 19)
              ..lineTo(12, 16)
              ..lineTo(7, 19)
              ..lineTo(8, 13)
              ..lineTo(4, 9)
              ..lineTo(9.5, 8.5)
              ..close(),
            line);
      case SectionGlyph.layout:
        canvas.drawRRect(
            RRect.fromLTRBR(4, 4, 20, 20, const Radius.circular(2)), line);
        seg(4, 10, 20, 10);
        seg(10, 10, 10, 20);
      case SectionGlyph.motion:
        seg(3, 12, 7, 12);
        seg(3, 7, 10, 7);
        seg(3, 17, 10, 17);
        canvas.drawCircle(const Offset(16, 12), 4, line);
      case SectionGlyph.more:
        var dot = Paint()..color = colour;
        for (var x in [6.0, 12.0, 18.0]) {
          canvas.drawCircle(Offset(x, 12), 1.6, dot);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.colour != colour;
}
