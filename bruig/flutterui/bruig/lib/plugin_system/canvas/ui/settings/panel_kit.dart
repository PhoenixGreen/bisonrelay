import 'dart:ui' as ui;
import 'dart:collection';
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// panel_kit.dart is the parts of the sectioned settings panel: a section that
// folds, holding cards; a row of picture tiles; a section's tools; and the
// stepper -- a number with an arrow either side.
//
// Built for the picture's panel first and meant for every element's after it,
// so nothing here knows what a picture is. See image_settings.dart for the
// first panel built from them, and settings/README.md for the rows inside a
// section, which are the same groups as ever.

/// stepperHeight is a stepper's box. Taller than the other controls' because
/// the arrows are pressed rather than aimed at.
const double stepperHeight = 30;

/// CanvasStepper is a number with an arrow either side of it.
///
/// The arrows nudge it a [step] at a time, and repeat while held. The number
/// itself is dragged sideways to run it up and down -- from the first pixel,
/// since nothing else in the box wants a drag -- and double-clicked to type
/// one. Changed from [defaultValue], its caption turns the accent colour and
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
  /// digit, or a fifth of [step] where that is coarser -- a step of five
  /// percent dragged at one percent a pixel is about right; at a tenth it is
  /// five hundred pixels from one end to the other.
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
    _running = _snap(_running + by * _step);
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
            width: CanvasCards.on(context) ? 32 : 22,
            child: Icon(icon,
                size: CanvasCards.on(context) ? 18 : 16,
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
                  fontSize: 12,
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
        borderRadius: BorderRadius.circular(card ? 10 : 7),
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
        padding: const EdgeInsets.only(right: cardGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: cardLabelHeight, child: caption),
            const SizedBox(height: cardLabelGap),
            widget.fill
                ? SizedBox(
                    width: double.infinity,
                    height: cardControlHeight,
                    child: box)
                : canvasSized(context,
                    min: CanvasControlScope.widthFor(context, widget.width),
                    height: cardControlHeight,
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

/// CanvasTile is one choice in a row of [CanvasTiles]: a picture of what it
/// does and the word for it.
/// CanvasKept is [builder]'s widget, built again only when one of [deps] is
/// not what it was -- or something it reads from above, the theme say, has
/// changed.
///
/// Every edit rebuilds the whole panel, and most of it -- the layers strip,
/// the headings of the sections that are shut -- is what it was: the same
/// widget handed back is a subtree Flutter does not go through at all. What
/// it is handed must be everything the widget shows, and anything it does
/// when pressed must look up what is current then, not keep what was: a
/// widget kept is a callback kept.
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
/// last. A strip of tiles scrolled was every tile's filter, blend layer and
/// shader drawn again on every frame -- with nothing kept between frames, as
/// the renderer keeps nothing -- and a rounded clip a tile on top. Drawn
/// from here, a tile is one picture, clipped in place.
final LinkedHashMap<String, ui.Image> _snapshots = LinkedHashMap();
const int _snapshotsKept = 240;

/// TileSnapshot is [paint] drawn once at the size it is shown, kept as
/// [id], and drawn from then on as that picture with its corners rounded.
class TileSnapshot extends StatelessWidget {
  final String id;
  final TilePaint paint;
  final Color ground;
  final double radius;
  const TileSnapshot(
      {required this.id,
      required this.paint,
      required this.ground,
      this.radius = 5,
      super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.infinite,
      painter: _SnapshotPainter(id, paint, ground, radius,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1));
}

class _SnapshotPainter extends CustomPainter {
  final String id;
  final TilePaint draw;
  final Color ground;
  final double radius;
  final double ratio;
  _SnapshotPainter(this.id, this.draw, this.ground, this.radius, this.ratio);

  ui.Image _image(Size size) {
    var w = math.max(1, (size.width * ratio).round());
    var h = math.max(1, (size.height * ratio).round());
    var key = "$id|${ground.toARGB32()}|${w}x$h";
    var kept = _snapshots.remove(key);
    if (kept != null) return _snapshots[key] = kept;
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder)..scale(w / size.width, h / size.height);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    draw(canvas, size);
    var picture = recorder.endRecording();
    var made = picture.toImageSync(w, h);
    picture.dispose();
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
      old.id != id || old.ground != ground || old.ratio != ratio;
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
  /// are one line that scrolls sideways, with the one chosen in view and
  /// named in the heading; open, all of them. As the layers strip does --
  /// a choice made once and then mostly looked at takes a line, not a block.
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
    if (card && scrolls) {
      return canvasCard(context,
          title: label == null ? null : canvasCardTitle(context, label!),
          help: help,
          body: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              height: previewHeight + 30,
              // Every tile built, not only those in view: a handful, and a
              // tile scrolled out of view is still one to reach.
              child: SingleChildScrollView(
                key: ValueKey("tilesRow-$label"),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var (i, t) in tiles.indexed)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                      child: SizedBox(
                          width: tileWidth,
                          child: _tile(context, theme, t, hover: false)),
                    ),
                ]),
              ),
            ),
          ));
    }
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
class CanvasSections extends StatelessWidget {
  final List<Widget> children;
  const CanvasSections({required this.children, super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
}

/// CanvasSection is one subject of an element's settings -- where it is, its
/// mask, its colour -- as a card that folds.
///
/// Shut, it is its icon, its name and a line saying how it is set now, so
/// the panel reads as a summary of the element before anything is opened.
/// [changes] puts a dot on it, and once open a reset beside the chevron, for
/// a section moved away from how it starts. Open, what is inside is in
/// cards -- see CanvasCards.
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

  const CanvasSection({
    required this.icon,
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
                    borderRadius: BorderRadius.circular(9),
                    color: open
                        ? accent.withValues(alpha: 0.16)
                        : theme.colors.surfaceContainerHighest,
                  ),
                  child:
                      Icon(widget.icon, size: 16, color: open ? accent : muted),
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
                                  fontSize: 12.5,
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
                              style: TextStyle(fontSize: 10.5, color: muted)),
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
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(Icons.chevron_right, size: 20, color: muted),
                ),
              ]),
            ),
          ),
        ),
      ),
      // Outside the heading's ink, so pressing them does not also fold
      // the section: what it is for, and what it does shut.
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
          padding: const EdgeInsets.only(right: 8),
          child: CanvasIconButton(
            key: ValueKey("sectionReset-${widget.remember}"),
            tight: true,
            icon: Icons.restart_alt,
            tooltip: "Reset ${widget.title}",
            onPressed: () => widget.onReset?.call(),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
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
          // The heading is what it was unless what it says has changed --
          // nine of them, rebuilt on every edit, were half of a shut panel's
          // work. See CanvasKept.
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

  const CanvasToolTiles({
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
            return SizedBox(
                height: card ? 56 : 46,
                child: SingleChildScrollView(
                    key: const ValueKey("toolsRow"),
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var (i, (tool, icon, short)) in tools.indexed)
                        Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                            child: SizedBox(
                              width: each,
                              child: Tooltip(
                                message: tooltipOf(tool),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: ValueKey(keyOf(tool)),
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () =>
                                        onPick(tool == active ? null : tool),
                                    child: Container(
                                      height: card ? 56 : 46,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: lit(tool)
                                            ? accent.withValues(alpha: 0.16)
                                            : null,
                                        border: Border.all(
                                            color: lit(tool)
                                                ? accent
                                                : theme.colors.outlineVariant,
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
                                                  : theme
                                                      .colors.onSurfaceVariant),
                                          const SizedBox(height: 4),
                                          Text(short,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: card ? 10.5 : 9.5,
                                                  color:
                                                      theme.colors.onSurface)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )),
                    ])));
          }),
        ),
        if (held == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text("Pick a tool to work on the canvas.",
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
                runSpacing: card ? cardGap : canvasRowGap, children: controls),
        ],
      ],
    );
    if (card) {
      return canvasCard(context,
          title: canvasCardTitle(context, "Tools"), help: about, body: body);
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
        child: body);
  }
}

/// _FoldingTiles is a card of tiles that folds -- see CanvasTiles.foldAs.
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

  /// _shown is the tile the strip last brought into view, so it is brought
  /// there once when it is chosen and not again on every rebuild -- which
  /// would snap the strip back under somebody scrolling it.
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
      // Open, clicked too: a tile tried on a hover was, to the panel, the
      // tile chosen -- the highlight followed the pointer about, and the
      // settings that hang on the choice came and went under it.
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
        height: t.previewHeight + 30,
        child: SingleChildScrollView(
          key: ValueKey("tilesStrip-${t.foldAs}"),
          controller: _strip,
          scrollDirection: Axis.horizontal,
          // Clicked, never tried on a hover: a hover tried the tile, the
          // tile tried was the one chosen, the strip scrolled to bring it
          // into view under the pointer -- and the pointer was on the next.
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
