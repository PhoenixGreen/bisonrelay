part of 'controls.dart';

// Fields to type into: the number field, scrubbed by dragging its label, the
// text field, and the labels they sit under. Part of controls.dart.

/// CanvasNumberField is a number with a label above it, committed on every
/// keystroke that parses, so a typed width shows at once.
class CanvasNumberField extends StatefulWidget implements CanvasGrowable {
  @override
  double get least => width;

  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final double width;
  final String suffix;

  /// step is how far one pixel of a drag on the label moves the number. Null
  /// is the field's last digit, wrong for a field precise but wide (a ring
  /// width in ten-thousandths running to a fifth of the page).
  final double? step;

  final ValueChanged<double> onChanged;

  /// grow lets this take some of the room left over on its line; [width] is
  /// then the least it will be. See CanvasWrap.
  @override
  final bool grow;

  /// onCommit is called when editing ends: where a caller ends its undo step.
  final VoidCallback? onCommit;

  const CanvasNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = -100000,
    this.max = 100000,
    this.decimals = 0,
    this.width = 62,
    this.suffix = "",
    this.step,
    this.grow = true,
    this.onCommit,
    super.key,
  });

  @override
  State<CanvasNumberField> createState() => _CanvasNumberFieldState();
}

class _CanvasNumberFieldState extends State<CanvasNumberField> {
  late final TextEditingController _text =
      TextEditingController(text: _format(widget.value));
  final FocusNode _focus = FocusNode();

  /// _hold runs while the number is pressed, _scrubbing is true once held
  /// long enough, and _from and _startX are where the drag began. Held, not
  /// dragged, because a field's own drag selects text; here too because a
  /// field may have no caption. Nothing in the hold reaches the panel (no
  /// unfocus, no commit): losing the focus commits, which rebuilds the panel
  /// and can take this field's state away mid-gesture.
  Timer? _hold;
  bool _scrubbing = false;
  double _from = 0;
  double _startX = 0;

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit?.call();
    });
  }

  @override
  void didUpdateWidget(CanvasNumberField old) {
    super.didUpdateWidget(old);
    // Rewritten from outside only while not typed into, or the caret would
    // jump to the end on every keystroke. A scrub counts as not typing,
    // though its press gives the field the focus.
    if ((_scrubbing || !_focus.hasFocus) && widget.value != old.value) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _endScrub() {
    _hold?.cancel();
    _hold = null;
    if (!_scrubbing) return;
    setState(() => _scrubbing = false);
    widget.onCommit?.call();
  }

  /// _arrowStep is how far a stepper's arrow moves this number: a fiftieth of
  /// a real range, rounded to the field's precision, or a whole unit (a
  /// tenth, for a precise field) where the range is only a guard rail.
  double get _arrowStep {
    var digit = math.pow(10, -widget.decimals).toDouble();
    var span = widget.max - widget.min;
    if (span > 0 && span < 10000) {
      var raw = span / 50;
      return math.max(digit, (raw / digit).roundToDouble() * digit);
    }
    return widget.decimals == 0 ? 1 : digit * 10;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var step = widget.step ?? math.pow(10, -widget.decimals).toDouble();
    // In a card every number is a stepper, whoever asked for a field.
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return CanvasStepper(
        name: widget.key is ValueKey<String>
            ? (widget.key as ValueKey<String>).value
            : null,
        label: widget.label,
        value: widget.value,
        min: widget.min,
        max: widget.max,
        decimals: widget.decimals,
        step: _arrowStep,
        dragStep: step,
        // A word ("2 years") wants a space; a sign ("40%") does not.
        suffix: RegExp(r"^[A-Za-z]").hasMatch(widget.suffix)
            ? " ${widget.suffix}"
            : widget.suffix,
        grow: widget.grow,
        onChanged: widget.onChanged,
        onCommit: widget.onCommit,
      );
    }
    return _labelled(
      theme,
      widget.label,
      scrub: _ScrubLabel(
        label: widget.label,
        value: widget.value,
        min: widget.min,
        max: widget.max,
        decimals: widget.decimals,
        step: widget.step,
        onChanged: widget.onChanged,
        onCommit: widget.onCommit,
      ),
      canvasSized(
        context,
        min: CanvasControlScope.widthFor(context, widget.width),
        height: controlHeight,
        grow: widget.grow,
        child: Listener(
          // Translucent, so a press round the digits counts as on the field.
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _from = widget.value;
            _startX = event.position.dx;
            _hold?.cancel();
            _hold = Timer(_scrubHoldDelay, () {
              _hold = null;
              setState(() => _scrubbing = true);
            });
          },
          onPointerMove: (event) {
            var travelled = event.position.dx - _startX;
            if (!_scrubbing) {
              // Moved before it was held: the field's own drag, selecting
              // the number to retype. Generous, as a hand held still drifts.
              if (travelled.abs() > _scrubHoldSlop) {
                _hold?.cancel();
                _hold = null;
              }
              return;
            }
            widget.onChanged(_scrubbed(_from, travelled, step,
                min: widget.min, max: widget.max));
          },
          onPointerUp: (_) => _endScrub(),
          onPointerCancel: (_) => _endScrub(),
          child: TextField(
            controller: _text,
            focusNode: _focus,
            style: const TextStyle(fontSize: 12),
            textAlignVertical: TextAlignVertical.center,
            // Left and right over the whole box: the number can be dragged.
            // On the field, not a MouseRegion round it, because a text
            // field's own cursor is innermost and wins.
            mouseCursor: SystemMouseCursors.resizeLeftRight,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"^-?[0-9]*\.?[0-9]*")),
            ],
            decoration: canvasFieldDecoration(theme).copyWith(
              suffixText: widget.suffix.isEmpty ? null : widget.suffix,
              suffixStyle: const TextStyle(fontSize: 10),
            ),
            onChanged: (raw) {
              var parsed = double.tryParse(raw);
              if (parsed == null) return;
              widget.onChanged(parsed.clamp(widget.min, widget.max));
            },
            onSubmitted: (_) => widget.onCommit?.call(),
          ),
        ),
      ),
    );
  }
}

/// _scrubHoldDelay is how long a press on a number lasts before it drags the
/// value, and _scrubHoldSlop how far the pointer may stray meanwhile.
const Duration _scrubHoldDelay = Duration(milliseconds: 350);

const double _scrubHoldSlop = 14;

/// _scrubbed is where a scrub of [travelled] pixels from [from] has got to:
/// one step a pixel, and with shift ten times finer.
double _scrubbed(double from, double travelled, double step,
    {required double min, required double max}) {
  var fine = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
  return (from + travelled * step * fine).clamp(min, max).toDouble();
}

/// canvasFieldDecoration is what every field on this panel is drawn with.
/// The vertical padding sets the field's height: without it the field sits
/// short at the top of its row.
InputDecoration canvasFieldDecoration(
  ThemeNotifier theme, {
  String hint = "",
  double fontSize = 12,
}) =>
    InputDecoration(
      isDense: true,
      hintText: hint.isEmpty ? null : hint,
      hintStyle: const TextStyle(fontSize: 11),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: canvasFieldPadding(fontSize),
      ),
    );

/// canvasFieldPadding is the room above and below the words that makes a
/// field exactly [controlHeight] tall: a line of text is about a fifth
/// taller than its point size, and the border takes a pixel at each end.
double canvasFieldPadding(double fontSize) =>
    math.max(0, (controlHeight - 2 - fontSize * 1.2) / 2);

/// CanvasTextField is a short string with a label above it.
class CanvasTextField extends StatefulWidget implements CanvasGrowable {
  @override
  double get least => width;

  final String label;
  final String value;
  final double width;
  final int maxLines;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCommit;

  /// grow: see CanvasNumberField.grow.
  @override
  final bool grow;

  const CanvasTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.width = 150,
    this.maxLines = 1,
    this.hint = "",
    this.grow = true,
    this.onCommit,
    super.key,
  });

  @override
  State<CanvasTextField> createState() => _CanvasTextFieldState();
}

class _CanvasTextFieldState extends State<CanvasTextField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit?.call();
    });
  }

  @override
  void didUpdateWidget(CanvasTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _labelled(
        ThemeNotifier.of(context),
        widget.label,
        canvasSized(
          context,
          min: CanvasControlScope.widthFor(context, widget.width),
          height: widget.maxLines > 1
              ? heightIn(context) * (CanvasDense.on(context) ? 2.2 : 2)
              : heightIn(context),
          grow: widget.grow,
          child: CanvasDense.on(context)
              // Boxed in a dense panel: a field to type into, not a line to
              // type on.
              ? TextField(
                  controller: _text,
                  focusNode: _focus,
                  maxLines: widget.maxLines,
                  minLines: widget.maxLines,
                  expands: false,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                  decoration: _boxed(ThemeNotifier.of(context), widget.hint),
                  onChanged: widget.onChanged,
                )
              : _bottomInCard(
                  context,
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    maxLines: widget.maxLines,
                    style: const TextStyle(fontSize: 12),
                    decoration: canvasFieldDecoration(
                        ThemeNotifier.of(context),
                        hint: widget.hint),
                    onChanged: widget.onChanged,
                  ),
                ),
        ),
      );

  /// _boxed is a dense panel's field: a box with rounded corners, filled a
  /// shade off the panel, its edge lit while it is being typed in.
  InputDecoration _boxed(ThemeNotifier theme, String hint) {
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c));
    return InputDecoration(
      isDense: true,
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(
          fontSize: 13,
          color: theme.colors.onSurfaceVariant.withValues(alpha: 0.6)),
      filled: true,
      fillColor: theme.colors.surfaceContainerHighest.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: edge(theme.colors.outlineVariant),
      focusedBorder: edge(theme.colors.primary),
      border: edge(theme.colors.outlineVariant),
    );
  }

  /// _bottomInCard sits a field's underline at the foot of its box in a
  /// card, level with the buttons and steppers beside it.
  Widget _bottomInCard(BuildContext context, Widget field) =>
      CanvasCards.on(context) && widget.maxLines == 1
          ? Align(alignment: Alignment.bottomLeft, child: field)
          : field;
}

/// _ScrubLabel is a caption dragged sideways to change the number under it
/// (the field's own drag selects text). One pixel moves the number by its
/// last digit, not a share of the range, since most ranges are guard rails,
/// not scales. Shift makes it ten times finer.
class _ScrubLabel extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;

  /// decimals is the field's precision, and so one step unless [step] is set.
  final int decimals;

  /// step is how far one pixel moves the number. Null is the last digit.
  final double? step;

  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  const _ScrubLabel({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    this.step,
    this.onCommit,
  });

  @override
  State<_ScrubLabel> createState() => _ScrubLabelState();
}

class _ScrubLabelState extends State<_ScrubLabel> {
  /// _from is the value the drag started at, so the gesture is measured from
  /// one place: summed deltas drift, and rounding them slows a slow drag.
  double _from = 0;

  /// _startX is where the pointer went down, in screen coordinates.
  double _startX = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    var step = widget.step ?? math.pow(10, -widget.decimals).toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      // A Listener, not a GestureDetector, so the number moves from the first
      // pixel: a drag is only recognised after about eighteen pixels, which
      // are then lost. Nothing else competes for these pointers.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _from = widget.value;
          _startX = event.position.dx;
          _dragging = true;
        },
        onPointerMove: (event) {
          if (!_dragging) return;
          widget.onChanged(_scrubbed(_from, event.position.dx - _startX, step,
              min: widget.min, max: widget.max));
        },
        onPointerUp: (_) {
          if (!_dragging) return;
          _dragging = false;
          widget.onCommit?.call();
        },
        onPointerCancel: (_) => _dragging = false,
        child: SizedBox(
          height: controlLabelHeight,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 9,
              height: 1.1,
              color: theme.colors.onSurfaceVariant,
              // Dotted, the way a draggable number is marked everywhere else.
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor:
                  theme.colors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// canvasLabelled is [child] under [label], for a control drawn by hand.
Widget canvasLabelled(BuildContext context, String label, Widget child) =>
    _labelled(ThemeNotifier.of(context), label, child);

/// canvasControlHeight is how tall a control is where [context] is.
double canvasControlHeight(BuildContext context) =>
    CanvasCards.on(context) ? cardHeightIn(context) : controlHeight;

/// _labelled puts a caption above a control. [scrub] makes the caption a
/// drag handle for the number (see _ScrubLabel).
Widget _labelled(ThemeNotifier theme, String label, Widget child,
    {Widget? scrub, double? cap}) {
  return Builder(builder: (context) {
    // Caption as hover text: only the control on screen.
    if (CanvasControlScope.hovers(context)) {
      return Padding(
        padding: const EdgeInsets.only(right: canvasControlGap),
        child: label.isEmpty ? child : CanvasTip(message: label, child: child),
      );
    }
    var inline = CanvasControlScope.isInline(context);
    var caption = Text(
      label,
      style: TextStyle(
          fontSize: inline ? 10 : 9,
          height: 1.1,
          color: theme.colors.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
    );

    // Beside the control in the band, above it in a sidebar.
    if (inline) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (label.isNotEmpty) ...[
              // Capped, so a long caption cannot push the control off the
              // end of a strip already scrolling sideways.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: scrub ?? caption,
              ),
              const SizedBox(width: 6),
            ],
            child,
          ],
        ),
      );
    }

    // In a card: a larger caption and control, further apart.
    if (CanvasCards.on(context)) {
      return Padding(
        padding: EdgeInsets.only(right: cardGapIn(context)),
        child: Column(
          crossAxisAlignment: CanvasCellFill.on(context)
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // As wide as its words: in a card there is the room.
            SizedBox(
                height: cardLabelHeightIn(context),
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        color: theme.colors.onSurfaceVariant))),
            SizedBox(height: cardLabelGapIn(context)),
            child,
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
          if (scrub != null)
            scrub
          else
            // Held to the control's width where the caller asks: a Column is
            // as wide as its widest child, so a long caption would set it.
            SizedBox(height: controlLabelHeight, width: cap, child: caption),
          const SizedBox(height: controlLabelGap),
          child,
        ],
      ),
    );
  });
}
