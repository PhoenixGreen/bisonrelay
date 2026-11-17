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

// panel_kit.dart is the sectioned settings panel's parts: folding sections,
// picture tiles, tools, the stepper. Element-agnostic; see
// settings/README.md for the rows inside a section.

/// stepperHeight is taller than other controls: arrows are pressed, not aimed.
const double stepperHeight = 30;

/// CanvasStepper is a number with arrows that repeat while held; dragged it
/// runs, double-clicked it is typed. Off [defaultValue] its caption takes
/// the accent and a ↺.
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

  /// dragStep is a drag pixel's step: null is the last digit, or [step] / 5
  /// where coarser, so a range is not hundreds of pixels.
  final double? dragStep;

  final String suffix;

  /// defaultValue is its start, for the ↺; null where it has none (a place).
  final double? defaultValue;

  final double width;

  @override
  final bool grow;

  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  /// name keys its arrows, number and reset ("$name-less") for a stepper
  /// drawn for a keyed field; null uses the stepper's own key.
  final String? name;

  /// fill makes it as wide as given, for one laid out in its own row.
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

  /// _running is the held value, counted here: repeats outpace rebuilds.
  double _running = 0;

  double get _digit => math.pow(10, -widget.decimals).toDouble();
  double get _step => widget.step ?? _digit;
  double get _dragStep =>
      widget.dragStep ?? math.max(_digit, (widget.step ?? 0) / 5);

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  /// _sub keys one of its parts, where it has a name to key them by.
  Key? _sub(String part) {
    var name = widget.name ??
        (widget.key is ValueKey<String>
            ? (widget.key as ValueKey<String>).value
            : null);
    return name == null ? null : ValueKey("$name-$part");
  }

  double _clamp(double v) => v.clamp(widget.min, widget.max).toDouble();

  /// _snap rounds to the field's digits: 0.3, not 0.30000000000000004.
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
    // Held at a limit: say nothing rather than repeat the same value.
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
          // A few pixels of give, so a double-click does not nudge it.
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

  /// _built is the last build, handed back unchanged while [_was] is, so
  /// other edits skip it; its handlers read [widget] live.
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
      // Stretched, so each arrow is pressable over the box's full height.
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
            // No room for a missing caption, so a look's row stays level.
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
          // Caption and box are as tall as any captioned control, so steppers
          // stand level; the box's extra height comes out of the gap.
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

/// CanvasKept is [builder]'s widget, rebuilt only when [deps] or inherited
/// state change, as Flutter skips an unchanged subtree. Pass everything it
/// shows; handlers must read current state, as a kept widget's callbacks
/// are kept too.
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

/// CanvasTile is one choice in [CanvasTiles]: a picture and its name.
class CanvasTile<T> {
  final T value;
  final String label;

  /// preview draws what choosing it does. Null shows [icon] instead.
  final WidgetBuilder? preview;
  final IconData? icon;

  /// paint draws the choice once into a kept picture (see TileSnapshot);
  /// preferred to [preview] for anything through a layer or filter.
  final TilePaint? paint;

  /// drawnFrom is what [preview] draws from beyond [value]; given, a tile in
  /// a folding card is built once and kept (see CanvasKept).
  final Object? drawnFrom;

  const CanvasTile(this.value, this.label,
      {this.preview, this.icon, this.drawnFrom, this.paint});
}

typedef TilePaint = void Function(Canvas canvas, Size size);

/// _snapshots is every tile's picture, drawn once, most recent last.
final LinkedHashMap<String, ui.Image> _snapshots = LinkedHashMap();
const int _snapshotsKept = 240;

/// TileSnapshot is [paint] drawn once at its size and kept as [id].
class TileSnapshot extends StatelessWidget {
  final String id;

  /// slot is which tile this is: while [holding], its last picture shows.
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

  /// holding is whether a control is dragged: tiles keep their pictures till
  /// it ends, or thirty (some 3D) would redraw each step.
  static bool Function() holding = _never;
  static bool _never() => false;

  /// letGo is the panels closed: their editor and kept pictures go.
  static void letGo() {
    holding = _never;
    for (var image in _snapshots.values) {
      image.dispose();
    }
    _snapshots.clear();
  }

  /// stoodIn counts pictures drawn with a stand-in (a body being made): not
  /// kept, and redrawn when [arrived] says the real thing is here.
  static int Function() stoodIn = _none;
  static int _none() => 0;
  static Listenable? arrived;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.infinite,
      painter: _SnapshotPainter(id, slot, paint, ground, radius,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1, arrived));
}

/// _lastIn is the snapshot each tile slot last showed, by key.
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

  /// _stale is whether this showed a picture held during a drag.
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

/// CanvasTiles is a choice made by looking: small named pictures, each
/// tried on the canvas through [onPreview] while pointed at (null on leave).
/// With [multiple], each toggles and wears a tick.
class CanvasTiles<T> extends StatelessWidget {
  final String? label;
  final List<CanvasTile<T>> tiles;
  final bool Function(T) selected;
  final ValueChanged<T> onPick;
  final ValueChanged<T?>? onPreview;
  final int columns;
  final bool multiple;

  /// keyOf names each tile, for tests.
  final String Function(T)? keyOf;

  final double previewHeight;

  /// help is what the choice does, behind its card's "?".
  final String help;

  /// ticked is which tiles wear a tick where that differs from lit (an
  /// effect on, settings shut); null is the lit ones.
  final bool Function(T)? ticked;

  /// scrolls lays the tiles in one scrolling line at [tileWidth] each.
  final bool scrolls;
  final double tileWidth;

  /// foldAs makes the card fold, remembered by that name: shut, one line
  /// with the chosen tile named; open, all.
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
    // In a section, a card of its own, named, with "?" beside the name.
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
                    // Drawn once and kept (see TileSnapshot).
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

class CanvasSections extends StatefulWidget {
  final List<Widget> children;

  /// parts is what the element is made of (a picture's layers), over the
  /// sections and menu bar; not a section.
  final Widget? parts;

  /// quick is the most-changed settings, over the sections (CanvasQuickStrip).
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

/// settingsAsMenu shows element settings as a menu (one section at a time)
/// instead of folding sections; kept (see toggleSettingsLayout).
final ValueNotifier<bool> settingsAsMenu = ValueNotifier(false);

bool _layoutRead = false;

/// readSettingsLayout reads the kept layout, once.
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

/// toggleSettingsLayout swaps the layout and keeps it.
void toggleSettingsLayout() {
  settingsAsMenu.value = !settingsAsMenu.value;
  StorageManager.saveData("canvasSettingsMenu", settingsAsMenu.value);
}

/// _menuChosen is the last menu section as "remember|title": that one, else
/// one of the same name, else the first.
String? _menuChosen;

/// _MenuItem is one section in the menu: name, "?", whether it can reset;
/// [state] is the section, for reset and action.
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

  /// Equal whatever its [action], a new widget each build.
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

/// _MenuScope tells the sections under a menu which is chosen. [owner] null
/// is no menu: a section inside a chosen section's body draws as a section.
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
  /// _items is the menu's sections, found after a frame, not read off
  /// [CanvasSections.children], as a background's are built deep inside.
  List<_MenuItem> _items = const [];
  bool _looking = false;
  final ScrollController _bar = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  final GlobalKey _barView = GlobalKey();
  String? _shown;

  /// _scroll is the panel's scroll, followed by _follow.
  ScrollPosition? _scroll;

  /// _stick is how far down the bar is drawn to stay at the panel's top.
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

  /// _follow keeps the bar at the panel's top while its sections scroll.
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
        // The same sections: their newest actions, shown next build.
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
      // Position (older panels) and Layout are the same section.
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
        // Once the section is laid out, the bar goes back where it belongs.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow();
        });
        // The bar drawn after the sections, so they scroll under it.
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

  /// _menuBar is the menu: section names in a scrolling line, the chosen one
  /// bold and underlined, its "?", action and reset at the end.
  Widget _menuBar(BuildContext context, String? active) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    // The chosen one scrolled into view, once each time it changes.
    if (active != null && active != _shown) {
      _shown = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Sideways only: ensureVisible would scroll the panel too.
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
      // Close to the first setting: the bar names the section.
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

/// CanvasSection is one subject of an element's settings as a folding card:
/// shut, an icon, name and summary line. [changes] adds a dot and, open, a
/// reset. Open, its contents are cards (see CanvasCards).
class CanvasSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String summary;

  /// scope is a tag beside the title ("Whole image" on a layer's frame).
  final String? scope;

  final int changes;
  final VoidCallback? onReset;

  /// action is a heading button outside the fold (a table's Refresh).
  final Widget? action;

  /// remember names where its open state is kept, as CanvasExpander's.
  final String remember;
  final bool initiallyOpen;

  /// forceOpen opens it whenever it turns true, as a held tool does.
  final bool forceOpen;
  final List<Widget> children;

  /// glyph is drawn instead of [icon] (see SectionGlyph).
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

  /// openAll starts every section open, for tests of what controls do.
  @visibleForTesting
  static bool openAll = false;

  /// forced is [forceOpen], or a forced section inside: a tool in a
  /// picture's Retouch opens its Look, or picks its tab in the menu.
  bool get forced => forceOpen || children.any(_forces);

  static bool _forces(Widget w) => switch (w) {
        CanvasSection s => s.forced,
        Column c => c.children.any(_forces),
        _ => false,
      };

  @override
  State<CanvasSection> createState() => _CanvasSectionState();
}

class _CanvasSectionState extends State<CanvasSection> {
  late bool _open = CanvasSection.openAll ||
      (rememberedSection(widget.remember) ?? widget.initiallyOpen);

  @override
  void initState() {
    super.initState();
    if (widget.forced) {
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
    var forced = widget.forced && !old.forced;
    if (forced && !_open) {
      _open = true;
      keepSection(widget.remember, true);
    }
    // In the menu, a tool taken up shows its section, as it opens it here.
    if (forced) {
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

  /// _help is the section's own hints, said once by its heading's "?".
  String get _help => [
        for (var c in widget.children)
          if (c is CanvasHint) c.message
      ].join("\n\n");

  /// _heading is icon, name, summary, and a reset when open and changed.
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
      // Outside the heading's ink, so pressing them does not fold it.
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

  /// _menuBody is the chosen section in the menu: contents only, its name,
  /// "?", action and reset being in the bar.
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

  /// _nested is a section inside another's cards: a fold keeping summary,
  /// dot, reset, "?", action and tool-opening (Retouch inside Look).
  Widget _nested(ThemeNotifier theme) {
    var muted = theme.colors.onSurfaceVariant;
    var open = _open;
    var changed = widget.changes > 0;
    return canvasCard(context,
        title: Row(children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey("section-${widget.remember}"),
                borderRadius: BorderRadius.circular(6),
                onTap: _toggle,
                child: Row(children: [
                  AnimatedRotation(
                    key: ValueKey("sectionFold-${widget.remember}"),
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Icon(Icons.chevron_right, size: 18, color: muted),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: canvasCardTitle(context, widget.title)),
                  ),
                  if (widget.scope != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: theme.colors.outlineVariant),
                      ),
                      child: Text(widget.scope!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 10, color: muted)),
                    ),
                  ],
                  if (widget.summary.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(widget.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: muted)),
                    ),
                  ],
                  if (changed)
                    Container(
                      key: ValueKey("sectionChanged-${widget.remember}"),
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                          color: theme.colors.primary, shape: BoxShape.circle),
                    ),
                ]),
              ),
            ),
          ),
          if (_help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CanvasHint(_help, round: true),
            ),
          if (widget.action != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: widget.action!,
            ),
          if (open && changed && widget.onReset != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CanvasIconButton(
                key: ValueKey("sectionReset-${widget.remember}"),
                tight: true,
                icon: Icons.restart_alt,
                tooltip: "Reset ${widget.title}",
                onPressed: () => widget.onReset?.call(),
              ),
            ),
        ]),
        body: !open
            ? const SizedBox.shrink()
            // Its own name for the cards inside, so the fold's is not repeated.
            : CanvasCards(
                title: widget.title,
                child: Column(
                  key: ValueKey("sectionBody-${widget.remember}"),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c in widget.children)
                      if (c is! CanvasHint) c
                  ],
                ),
              ));
  }

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
    // Inside another section: a fold among its cards.
    if (CanvasCards.on(context)) return _nested(theme);
    var open = _open;
    var changed = widget.changes > 0;
    // Painted on its own, so one changed section repaints alone.
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
          // The heading is kept unless its text changes: it was half the work.
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

/// _ToolRow is a scrolling line of tools keeping [active] in view.
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

/// CanvasToolTiles is a section's tools as named tiles and, on a line
/// below, the held tool's settings. Pressing the held tool puts it down.
class CanvasToolTiles<T> extends StatelessWidget {
  final List<(T, IconData, String)> tools;
  final T? active;
  final ValueChanged<T?> onPick;
  final String Function(T) keyOf;
  final String Function(T) tooltipOf;

  /// settings are the active tool's, under the tiles.
  final List<Widget> settings;

  /// help is what the tools are for, behind their card's "?".
  final String help;

  /// alsoActive lights another tool too (select, under an align tool).
  final bool Function(T)? alsoActive;

  /// lit is whether [tool] is drawn as in hand.
  bool lit(T tool) => tool == active || (alsoActive?.call(tool) ?? false);

  /// idle is what is said under the tiles with none picked.
  final String idle;

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
    // The tool's notes go behind the card's "?", never on a settings row.
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
          // A scrolling line, each tile its own width, so names are not cut.
          child: LayoutBuilder(builder: (context, box) {
            const gap = 6.0;
            var n = tools.length;
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = math.max(64.0, (width - gap * (n - 1)) / n);
            // The held tool kept in view when picked elsewhere (Add, a key).
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

/// _labelRoom is a strip tile's room under its picture at the text size.
double _labelRoom(BuildContext context) =>
    math.max(30.0, 16 + MediaQuery.textScalerOf(context).scale(9.5) * 1.35);

/// _ScrollingTiles is a card of tiles in one line, the choice kept in view.
class _ScrollingTiles<T> extends StatefulWidget {
  final CanvasTiles<T> tiles;
  const _ScrollingTiles({required this.tiles, super.key});

  @override
  State<_ScrollingTiles<T>> createState() => _ScrollingTilesState<T>();
}

class _ScrollingTilesState<T> extends State<_ScrollingTiles<T>> {
  final ScrollController _strip = ScrollController();

  /// _shown is the tile last scrolled into view: once when chosen, not
  /// every rebuild, which would snap the line back under someone scrolling.
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
                // Only as far as needed: one already in view stays put.
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
              // Every tile built: a handful, and off-screen ones are reachable.
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

  /// _kept is [tile], kept while unchanged (see CanvasKept); it picks
  /// through the current tiles, as the old build's pick is stale.
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
          // Its share of a narrow row, cut short at large text sizes.
          Flexible(
            child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: canvasCardTitle(context, t.label ?? "")),
          ),
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
      // Open, clicked too: a tile tried on hover would be chosen, and its
      // settings would come and go under the pointer.
      if (_open) {
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var tile in t.tiles)
            SizedBox(width: each, child: _kept(context, theme, tile)),
        ]);
      }
      // The chosen one scrolled into view, once, when chosen.
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
          // Clicked, never tried on hover: a tried tile would scroll into
          // view and the pointer land on the next.
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

/// _unlinked is which side fields are split into four, this run.
final Set<String> _unlinked = {};

void forgetPanelsForTest() {
  TileSnapshot.letGo();
  _lastIn.clear();
  _unlinked.clear();
  settingsAsMenu.value = false;
  CanvasSection.openAll = false;
}

/// CanvasSidesField is four numbers usually one (sides, corners, padding)
/// as one stepper and a link that splits them, two to a line; pressed again
/// they join on the first. Four that differ show split.
class CanvasSidesField extends StatefulWidget {
  final String label;

  /// name keys the one stepper, and its link as "${name}Link".
  final String name;

  /// values are the four, in the order of [parts].
  final List<double> values;

  /// parts name each of the four, and [partKeys] key them.
  final List<String> parts;
  final List<String> partKeys;

  final double max;
  final double step;

  /// onChanged sets one of the four, or all with a null side.
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
      // Not the proportion lock's chain: four sides, as a box or edges.
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
    // A line of its own, or its own width on the unbounded band.
    return SizedBox(
      width: CanvasControlScope.isInline(context) ? 260 : double.infinity,
      child: body,
    );
  }
}

/// SectionGlyph is a section icon: content, look, layout, motion, more.
enum SectionGlyph { content, look, layout, motion, more }

/// _GlyphPainter draws [glyph] from its 24-unit SVG paths, stroked 1.8 wide
/// with round ends, in a 16-pixel square at the box's middle.
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
