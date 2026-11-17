part of 'panel_kit.dart';

// CanvasStepper, a number with arrows that repeat while held, and
// CanvasSidesField, four such numbers that are usually one. Part of
// panel_kit.dart.

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

/// _unlinked is which side fields are split into four, this run.
final Set<String> _unlinked = {};

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
