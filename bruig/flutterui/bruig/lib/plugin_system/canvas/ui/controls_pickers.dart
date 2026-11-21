part of 'controls.dart';

// Choosing a value: the dropdown, previewing its options as they are hovered,
// the slider, and the colour button with its swatch. Part of controls.dart.

/// CanvasDropdown is a choice from a fixed list.
class CanvasDropdown<T> extends StatelessWidget implements CanvasGrowable {
  @override
  double get least => width;

  final String label;
  final T value;
  final List<(T, String)> options;
  final double width;
  /// stepped puts an arrow either side to step through the options, as in a
  /// card, wherever it is (a floating bar, say).
  final bool stepped;

  final ValueChanged<T> onChanged;

  /// onPreview is told of each option the pointer passes over while the list
  /// is open, and of null when it closes, so a choice can be seen on the
  /// canvas before it is made.
  final ValueChanged<T?>? onPreview;

  /// enabled is whether it answers at all: greyed rather than hidden, so it
  /// is still seen to exist.
  final bool enabled;

  /// tight holds the caption to the width of the box under it, for controls
  /// sized to the room rather than their contents. Off by default: a cut-off
  /// caption is worse than a wider row.
  final bool tight;

  /// marked are the options drawn as already in use, on a background: for a
  /// list that is both a choice and a set (the shapes a document is laid out
  /// for).
  final Set<T> marked;

  /// onRemove puts a cross on each marked option.
  final void Function(T)? onRemove;

  /// removeTip is the cross's hover text.
  final String Function(T)? removeTip;

  /// leading draws something before each option's name, in the list and in
  /// the closed box (an easing's curve, say).
  final Widget Function(T)? leading;

  /// groupOf puts a heading in the list above each run of options it gives
  /// the same answer for.
  final String Function(T)? groupOf;

  /// grow: see CanvasNumberField.grow.
  @override
  final bool grow;

  const CanvasDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.onPreview,
    this.width = 130,
    this.tight = false,
    this.enabled = true,
    this.grow = true,
    this.stepped = false,
    this.marked = const {},
    this.onRemove,
    this.removeTip,
    this.leading,
    this.groupOf,
    super.key,
  });

  /// _rows is the options as listed, a heading (null value) before each
  /// group.
  List<(T?, String, bool)> _rows() {
    var group = groupOf;
    if (group == null) return [for (var (v, t) in options) (v, t, false)];
    var rows = <(T?, String, bool)>[];
    String? last;
    for (var (v, t) in options) {
      var g = group(v);
      if (g != last) rows.add((null, g, true));
      last = g;
      rows.add((v, t, false));
    }
    return rows;
  }

  /// _menuWidth is how wide the open list must be to show every name whole,
  /// with any picture and marked buttons: at least [width], at most a
  /// sidebar.
  double _menuWidth(BuildContext context) {
    var scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (var (_, text, heading) in _rows()) {
      widest = math.max(widest, _widthOf(text, heading, scaler));
    }
    var extra = 40.0 + // the item's own padding and the scroll bar's room
        (leading != null ? 42 : 0) +
        (marked.isNotEmpty ? 56 : 0);
    return (widest + extra).clamp(width, math.max(width, 420.0));
  }

  /// _cardWidth is how wide a card's dropdown must be to show its longest
  /// name whole between its arrows, held to what a sidebar has room for.
  double _cardWidth(BuildContext context) {
    var scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (var (_, text, heading) in _rows()) {
      if (heading) continue;
      widest = math.max(widest, _widthOf(text, false, scaler));
    }
    // Two arrows and their dividers, and the room either side of the name.
    var chrome = 2 * 33 + 16 + 4 + (leading != null ? 42 : 0);
    return (widest + chrome).clamp(120.0, 320.0);
  }

  /// _widthOf is how wide [text] is set as an option (or, [heading], as a
  /// group's heading) at the text size [scaler] gives: measured once and
  /// remembered, since a settings panel is rebuilt often with the same
  /// names in it. The text size is part of what is remembered: a name is
  /// wider at a larger one, and a list measured without it cuts names short.
  static double _widthOf(String text, bool heading, TextScaler scaler) {
    var key = "${scaler.scale(100)}${heading ? "^" : "|"}$text";
    var known = _widths[key];
    if (known != null) return known;
    var painter = TextPainter(
        text: TextSpan(
            text: heading ? text.toUpperCase() : text,
            style: TextStyle(
                fontSize: heading ? 10 : 12,
                letterSpacing: heading ? 0.8 : null)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1)
      ..layout();
    var width = painter.width;
    painter.dispose();
    if (_widths.length >= 4096) _widths.clear();
    return _widths[key] = width;
  }

  static final Map<String, double> _widths = {};

  /// _named is an option's name, after its [leading] drawing if any.
  Widget _named(T v, String text) {
    var name = Text(text, overflow: TextOverflow.ellipsis);
    var lead = leading;
    if (lead == null) return name;
    // Too narrow for a picture and a name (a style in a forty-pixel slot),
    // it is the picture alone, shrunk to fit.
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 72) {
        return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: lead(v));
      }
      return Row(children: [
        lead(v),
        const SizedBox(width: 6),
        Flexible(child: name),
      ]);
    });
  }

  /// _step is the option [by] from the one chosen, or null past either end.
  T? _step(int by) {
    var values = [for (var (v, _) in options) v];
    var at = values.indexOf(value);
    var next = at + by;
    if (at < 0 || next < 0 || next >= values.length) return null;
    return values[next];
  }

  /// _arrow is one of a card's dropdown arrows.
  Widget _arrow(ThemeNotifier theme, IconData icon, int by) {
    var to = enabled ? _step(by) : null;
    var name = key is ValueKey<String> ? (key as ValueKey<String>).value : null;
    return Semantics(
      button: true,
      label: by < 0 ? "Previous $label" : "Next $label",
      child: InkWell(
        key:
            name == null ? null : ValueKey("$name-${by < 0 ? "less" : "more"}"),
        onTap: to == null ? null : () => onChanged(to as T),
        child: SizedBox(
          width: 32,
          child: Icon(icon,
              size: 18,
              color: theme.colors.onSurfaceVariant
                  .withValues(alpha: to == null ? 0.3 : 0.9)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = stepped ||
        CanvasCards.on(context) && !CanvasControlScope.isInline(context);
    // In a dense panel a plain select: its words and one chevron, not an
    // arrow either side taking their room.
    var plain = card && !stepped && CanvasDense.on(context);
    // A bare DropdownButton, not a DropdownButtonFormField, which keeps its
    // own copy of the value: here the value changes from outside (another
    // element selected, an undo) all the time.
    //
    // Its own Material, because ink is painted by the nearest Material in
    // its coordinates: with the sidebar's, the highlight would float where
    // the dropdown was as the settings scroll.
    var list = Material(
      type: MaterialType.transparency,
      // No highlight once the menu has closed: a box still lit after a
      // choice reads as still open.
      child: DropdownButton<T>(
        focusColor: Colors.transparent,
        value: options.any((o) => o.$1 == value) ? value : null,
        isDense: true,
        isExpanded: true,
        // The open list as wide as its longest name, so none is cut short.
        menuWidth: _menuWidth(context),
        underline: const SizedBox.shrink(),
        style: TextStyle(
            fontSize: plain ? 13 : 12, color: theme.colors.onSurface),
        iconSize: card && !plain ? 0 : (plain ? 18 : 16),
        icon: plain
            ? Icon(Icons.expand_more, color: theme.colors.onSurfaceVariant)
            : card
                ? const SizedBox.shrink()
                : null,
        // The closed button shows the chosen option's name alone, not a
        // marked option's background and cross, nor the preview a resting
        // pointer would start. Only the chosen one is built: the button
        // keeps one child for every option to show whichever is chosen, and
        // a list of fifty fonts built on every build is fifty widgets for
        // one shown.
        selectedItemBuilder: (context) {
          var chosen = options.any((o) => o.$1 == value) ? value : null;
          return [
            for (var (v, text, heading) in _rows())
              heading || v != chosen
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: marked.isEmpty
                          ? _named(v as T, text)
                          : Text(text, overflow: TextOverflow.ellipsis),
                    ),
          ];
        },
        items: [
          for (var (v, text, heading) in _rows())
            if (heading)
              DropdownMenuItem<T>(
                enabled: false,
                child: Text(text.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurfaceVariant)),
              )
            else
              DropdownMenuItem<T>(
                value: v,
                child: _Previewed<T>(
                  value: v as T,
                  onPreview: onPreview,
                  child: marked.contains(v)
                      ? _markedOption(theme, v, text)
                      : _named(v, text),
                ),
              ),
        ],
        onChanged: enabled
            ? (v) {
                // Null is a real answer where the type allows it: a
                // dropdown of "None, Fade, Slide" has null first.
                if (v == null && null is! T) return;
                onChanged(v as T);
              }
            : null,
      ),
    );
    // In a card, arrows step through the options; the middle opens the list.
    var box = plain
        ? Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color:
                  theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: list,
          )
        : card
        ? Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color:
                  theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _arrow(theme, Icons.chevron_left, -1),
              Container(width: 1, color: theme.colors.outlineVariant),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: list,
                ),
              ),
              Container(width: 1, color: theme.colors.outlineVariant),
              _arrow(theme, Icons.chevron_right, 1),
            ]),
          )
        : Container(
            // Centred in its box, not high with a band of nothing underneath.
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: list,
          );
    var least = CanvasControlScope.widthFor(context, width);
    // In a card, never narrower than its arrows and a word between them;
    // in a wrap, which can give it a line of its own, not narrower than its
    // longest name, so a short line wraps rather than cutting the name.
    if (card && !plain) {
      least = math.max(
          least, grow && _CanvasWrapScope.of(context) ? _cardWidth(context) : 120.0);
    } else if (plain) {
      least = math.max(least, 88.0);
    }
    return _labelled(
      theme,
      label,
      cap: tight ? least : null,
      canvasSized(
        context,
        min: least,
        height: heightIn(context),
        grow: grow,
        child: box,
      ),
    );
  }
}

/// _Previewed is one option of an open list, telling [onPreview] when the
/// pointer comes onto it, and null as the list closes.
class _Previewed<T> extends StatefulWidget {
  final T value;
  final ValueChanged<T?>? onPreview;
  final Widget child;
  const _Previewed(
      {required this.value, required this.onPreview, required this.child});

  @override
  State<_Previewed<T>> createState() => _PreviewedState<T>();
}

class _PreviewedState<T> extends State<_Previewed<T>> {
  @override
  void dispose() {
    var preview = widget.onPreview;
    // After the frame: the list is being taken down, and the preview
    // rebuilds the panel it was opened from. Every option says it, which is
    // harmless.
    if (preview != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => preview(null));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var preview = widget.onPreview;
    if (preview == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => preview(widget.value),
      child: widget.child,
    );
  }
}

/// CanvasSlider is a value with a range, drawn as a number field to type or
/// scrub like every other number in the settings.
class CanvasSlider extends StatelessWidget implements CanvasGrowable {
  /// Growable as the number field it is drawn as, so a wrap sees it.
  @override
  bool get grow => true;
  @override
  double get least => width < 62 ? width : 62;

  final String label;
  final double value;
  final double min;
  final double max;
  final double width;
  final int decimals;
  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  const CanvasSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.width = 104,
    this.decimals = 2,
    this.onCommit,
    super.key,
  });

  @override
  Widget build(BuildContext context) => CanvasNumberField(
        label: label,
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        decimals: decimals,
        width: width < 62 ? width : 62,
        onChanged: onChanged,
        onCommit: onCommit,
      );
}

/// CanvasColorButton is a swatch that opens the theme editor's picker. Not
/// a dropdown of palette slots: a canvas's colours are a picture's, not the
/// app theme's.
class CanvasColorButton extends StatefulWidget {
  final String label;
  final Color color;
  final bool allowAlpha;
  final ValueChanged<Color> onChanged;

  /// gradient is the second colour, for things painted with two. Set
  /// [onGradientChanged] to offer the picker's Gradient tab; null leaves a
  /// plain swatch.
  final GradientSpec? gradient;
  final ValueChanged<GradientSpec?>? onGradientChanged;

  /// labelWidth holds the caption to the swatch's width, for rows with a
  /// known amount of room: a Column is as wide as its widest child, so
  /// "Colour" over a thirty-pixel swatch is a fifty-pixel column.
  final double? labelWidth;

  const CanvasColorButton({
    this.label = "",
    required this.color,
    required this.onChanged,
    this.gradient,
    this.onGradientChanged,
    this.labelWidth,
    this.allowAlpha = true,
    super.key,
  });

  @override
  State<CanvasColorButton> createState() => _CanvasColorButtonState();
}

class _CanvasColorButtonState extends State<CanvasColorButton> {
  /// _pick opens the picker and writes back its answer. Where both colour
  /// and fade moved, the second write waits a frame: the controls are built
  /// from the element as last laid out, so two writes in one frame would
  /// build on the same stale copy and the second would undo the first.
  Future<void> _pick() async {
    var picked = await pickPaint(
      context,
      initial: PaintSpec(widget.color, gradient: widget.gradient),
      allowAlpha: widget.allowAlpha,
      fades: widget.onGradientChanged != null,
    );
    if (picked == null || !mounted) return;
    var colourMoved = picked.color != widget.color;
    var fadeMoved = picked.gradient != widget.gradient;
    if (colourMoved) widget.onChanged(picked.color);
    if (!fadeMoved) return;
    if (!colourMoved) {
      widget.onGradientChanged?.call(picked.gradient);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onGradientChanged?.call(picked.gradient);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var label = widget.label;
    var color = widget.color;
    var gradient = widget.gradient;
    var labelWidth = widget.labelWidth;
    return _labelled(
      theme,
      label,
      cap: labelWidth,
      CanvasTip(
        message: widget.onGradientChanged == null
            ? "Choose a colour"
            : "Choose a colour, or two to fade between",
        child: Material(
          // Its own Material: see CanvasControlGroup.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _pick,
            child: CanvasCellFill.on(context)
                // Filling a cell of a row: a swatch and the colour's code.
                ? Container(
                    height: heightIn(context),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colors.outlineVariant),
                    ),
                    child: Row(children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CustomPaint(
                              painter: _SwatchPainter(color, gradient)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            "#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0").toUpperCase()}",
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: "monospace",
                                color: theme.colors.onSurfaceVariant)),
                      ),
                    ]),
                  )
                : Container(
                    width: 30,
                    height: heightIn(context),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: theme.colors.outlineVariant),
                      // The checker tells a transparent colour from black on a
                      // dark background.
                      color: theme.colors.surface,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CustomPaint(
                        painter: _SwatchPainter(color, gradient),
                        size: Size(30, heightIn(context)),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  final Color color;

  /// gradient is drawn in the swatch, so a fade shows without opening it.
  final GradientSpec? gradient;

  const _SwatchPainter(this.color, [this.gradient]);

  @override
  void paint(Canvas canvas, Size size) {
    const square = 6.0;
    var light = Paint()..color = const Color(0xFF9A9A9A);
    var dark = Paint()..color = const Color(0xFF6E6E6E);
    for (var y = 0.0; y < size.height; y += square) {
      for (var x = 0.0; x < size.width; x += square) {
        canvas.drawRect(Rect.fromLTWH(x, y, square, square),
            ((x ~/ square) + (y ~/ square)).isEven ? light : dark);
      }
    }
    var area = Offset.zero & size;
    var shader = PaintSpec(color, gradient: gradient).shaderFor(area);
    canvas.drawRect(area,
        shader == null ? (Paint()..color = color) : (Paint()..shader = shader));
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.gradient != gradient;
}

/// _MarkedOptions draws a CanvasDropdown's marked options.
extension _MarkedOptions<T> on CanvasDropdown<T> {
  /// _markedOption is an option in use: on a background, with a cross where
  /// it can be given up.
  Widget _markedOption(ThemeNotifier theme, T value, String text) => Builder(
        // Across the whole row: a menu item sits inside the menu's private
        // _kMenuItemPadding (16 a side), so the background is drawn that
        // much wider and let to overflow.
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) => OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.center,
            child: Container(
              width: constraints.maxWidth.isFinite
                  ? constraints.maxWidth + 32
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: theme.colors.secondaryContainer,
              child: Row(children: [
                Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
                if (onRemove case var remove?) ...[
                  const SizedBox(width: 4),
                  CanvasTip(
                    message: removeTip?.call(value) ?? "Remove",
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      // Closed by hand: the cross is inside the row, so the
                      // row's own tap never runs and the menu would stay
                      // open over a changed list.
                      onTap: () {
                        Navigator.of(context).pop();
                        remove(value);
                      },
                      child: Icon(Icons.close,
                          size: 13, color: theme.colors.onSecondaryContainer),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
}
