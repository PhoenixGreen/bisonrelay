import 'dart:math' as math;

import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// controls.dart is the small set of controls the canvas settings bar is built
// out of.
//
// There are a lot of properties on a canvas -- a chart alone has twenty -- and
// the only way a bar of them stays readable is if they all look and behave the
// same. So each control here is one labelled thing of a fixed height, they sit
// in a wrapping row, and none of them is allowed to be taller than the bar.
//
// Every one of them reports continuously while it is being changed, and the
// callers pass those through as transient edits (see
// CanvasController.beginInteraction): dragging a slider should show the result
// as it moves, and should still be one undo step when it stops.

/// controlHeight is what every control in the settings bar stands at.
///
/// Deliberately small. The band sits above the canvas and every pixel it takes
/// is a pixel of the thing being designed, so the controls are as short as
/// they can be while still being a comfortable click target.
const double controlHeight = 27;

/// controlLabelHeight is the little caption above each control. Everything
/// that has no caption -- a toggle, an icon button -- is pushed down by
/// exactly this much so the whole row sits on one baseline.
const double controlLabelHeight = 11;

/// CanvasControlScope says how the controls below it should lay themselves out.
///
/// There are two places the same controls appear: the band above the canvas,
/// where a group is a row and the whole line scrolls sideways, and the Layers
/// sidebar, where there is no width to scroll and a group has to stack.
/// Rather than a second set of forty controls, a group asks the scope which it
/// is in, and every control that sizes itself clamps to what the scope allows.
class CanvasControlScope extends InheritedWidget {
  /// stacked wraps a group's controls onto as many lines as they need, and
  /// puts the group's name above them instead of beside them.
  final bool stacked;

  /// maxWidth is the widest a single control may be. In a sidebar this is what
  /// stops the chart's data box -- which asks for 260 -- from running off the
  /// edge, since a control sized past its parent overflows rather than
  /// shrinking.
  final double maxWidth;

  const CanvasControlScope({
    required this.stacked,
    required this.maxWidth,
    required super.child,
    super.key,
  });

  static CanvasControlScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasControlScope>();

  /// widthFor is a control's preferred width, capped by the scope.
  static double widthFor(BuildContext context, double wanted) {
    var scope = maybeOf(context);
    return scope == null ? wanted : math.min(wanted, scope.maxWidth);
  }

  static bool isStacked(BuildContext context) =>
      maybeOf(context)?.stacked ?? false;

  @override
  bool updateShouldNotify(CanvasControlScope old) =>
      old.stacked != stacked || old.maxWidth != maxWidth;
}

/// CanvasControlGroup is a labelled cluster of controls with a rule after it.
///
/// The rules are what stop a bar of thirty controls reading as one undivided
/// mass. Groups, not scrolling panels: everything about the selected element
/// has to be reachable without hunting, because the thing being adjusted is
/// two inches away and looking at it is the whole activity.
class CanvasControlGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const CanvasControlGroup(
      {required this.label, required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var caption = Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w600,
        color: theme.colors.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );

    // Stacked, in a sidebar: the name above, the controls wrapped beneath it,
    // and a gap instead of a rule -- a vertical rule between rows would be
    // drawing a boundary across the direction the eye is already travelling.
    if (CanvasControlScope.isStacked(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 1),
                child: caption),
            Wrap(children: children),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // In the band the group's name sits to the left of its controls rather
      // than above them. Above, it was a second row of caption stacked on top
      // of each control's own caption, and thirteen pixels of every line went
      // on saying a word twice over. The band is above the canvas, so its
      // height comes straight out of the design.
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(right: 7, top: controlLabelHeight),
          child: SizedBox(
            height: controlHeight,
            child: Center(child: caption),
          ),
        ),
        ...children,
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.only(left: 6, top: controlLabelHeight),
          color: theme.colors.outlineVariant.withValues(alpha: 0.5),
        ),
      ]),
    );
  }
}

/// CanvasNumberField is a number with a label above it.
///
/// Committed on every keystroke that parses, rather than on submit. A field
/// that only takes effect when focus leaves it means typing a width and seeing
/// nothing happen, and then wondering whether it took.
class CanvasNumberField extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final double width;
  final String suffix;
  final ValueChanged<double> onChanged;

  /// onCommit is called when the field is done being edited, and is where a
  /// caller ends the undo step it started.
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

  String _format(double v) =>
      widget.decimals == 0 ? v.round().toString() : v.toStringAsFixed(widget.decimals);

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
    // The field is only rewritten from outside while it is not being typed
    // into. Rewriting it under the cursor moves the caret to the end on every
    // keystroke, which makes it impossible to edit the middle of a number.
    if (!_focus.hasFocus && widget.value != old.value) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      widget.label,
      SizedBox(
        width: CanvasControlScope.widthFor(context, widget.width),
        height: controlHeight,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          style: const TextStyle(fontSize: 12),
          textAlignVertical: TextAlignVertical.center,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"^-?[0-9]*\.?[0-9]*")),
          ],
          decoration: InputDecoration(
            isDense: true,
            suffixText: widget.suffix.isEmpty ? null : widget.suffix,
            suffixStyle: const TextStyle(fontSize: 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            border: const OutlineInputBorder(),
          ),
          onChanged: (raw) {
            var parsed = double.tryParse(raw);
            if (parsed == null) return;
            widget.onChanged(parsed.clamp(widget.min, widget.max));
          },
          onSubmitted: (_) => widget.onCommit?.call(),
        ),
      ),
    );
  }
}

/// CanvasTextField is a short string with a label above it.
class CanvasTextField extends StatefulWidget {
  final String label;
  final String value;
  final double width;
  final int maxLines;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCommit;

  const CanvasTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.width = 150,
    this.maxLines = 1,
    this.hint = "",
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
        SizedBox(
          width: CanvasControlScope.widthFor(context, widget.width),
          height: widget.maxLines > 1 ? controlHeight * 2 : controlHeight,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            maxLines: widget.maxLines,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint.isEmpty ? null : widget.hint,
              hintStyle: const TextStyle(fontSize: 11),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      );
}

/// CanvasDropdown is a choice from a fixed list.
class CanvasDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final double width;
  final ValueChanged<T> onChanged;

  const CanvasDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 130,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      Container(
        width: CanvasControlScope.widthFor(context, width),
        height: controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colors.outlineVariant),
        ),
        // A bare DropdownButton rather than a DropdownButtonFormField, which
        // is a FormField and keeps its own copy of the value. In a settings
        // bar the value changes from outside constantly -- a different element
        // is selected, an undo lands -- and a form field would go on showing
        // whatever was chosen in it last.
        child: DropdownButton<T>(
          value: options.any((o) => o.$1 == value) ? value : null,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: TextStyle(fontSize: 12, color: theme.colors.onSurface),
          iconSize: 16,
          items: [
            for (var (v, text) in options)
              DropdownMenuItem(
                value: v,
                child: Text(text, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// CanvasSlider is a value with a range, shown with its number beside it.
///
/// The number is not editable, on purpose: a slider is for the properties
/// where the value is meaningless on its own -- a density of 0.42 -- and where
/// what somebody is actually doing is looking at the canvas while they drag.
class CanvasSlider extends StatelessWidget {
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
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      SizedBox(
        width: CanvasControlScope.widthFor(context, width),
        height: controlHeight,
        child: Row(children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: (_) => onCommit?.call(),
              ),
            ),
          ),
          SizedBox(
            width: decimals == 0 ? 24 : 30,
            child: Text(
              decimals == 0
                  ? value.round().toString()
                  : value.toStringAsFixed(decimals),
              style: TextStyle(
                  fontSize: 10, color: theme.colors.onSurfaceVariant),
              textAlign: TextAlign.right,
            ),
          ),
        ]),
      ),
    );
  }
}

/// CanvasColorButton is a swatch that opens a picker.
///
/// A swatch rather than a dropdown of palette slots, unlike the theme editor
/// next door: a canvas is a picture rather than a part of the app's chrome, so
/// its colours are not the active theme's and should not be tied to it. What
/// it does borrow is the theme editor's picker, so the two feel like the same
/// app.
class CanvasColorButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool allowAlpha;
  final ValueChanged<Color> onChanged;

  const CanvasColorButton({
    required this.label,
    required this.color,
    required this.onChanged,
    this.allowAlpha = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      Tooltip(
        message: "Choose a colour",
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () async {
            var picked = await showDialog<Color>(
              context: context,
              builder: (context) =>
                  _ColorDialog(initial: color, allowAlpha: allowAlpha),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            width: 30,
            height: controlHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colors.outlineVariant),
              // The checker is what makes a transparent or nearly-transparent
              // colour distinguishable from a black one, which otherwise look
              // identical in a swatch on a dark background.
              color: theme.colors.surface,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(
                painter: _SwatchPainter(color),
                size: const Size(30, controlHeight),
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
  const _SwatchPainter(this.color);

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
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}

class _ColorDialog extends StatefulWidget {
  final Color initial;
  final bool allowAlpha;
  const _ColorDialog({required this.initial, required this.allowAlpha});

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("Colour"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _color,
            enableAlpha: widget.allowAlpha,
            displayThumbColor: true,
            hexInputBar: true,
            onColorChanged: (c) => setState(() => _color = c),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_color),
            child: const Text("Select"),
          ),
        ],
      );
}

/// CanvasToggle is a switch with a label, for the many booleans.
class CanvasToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CanvasToggle(
      {required this.label, required this.value, required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 5, top: controlLabelHeight),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onChanged(!value),
        child: Container(
          height: controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: value ? theme.colors.secondaryContainer : null,
            border: Border.all(
                color: value
                    ? theme.colors.secondaryContainer
                    : theme.colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              value ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 14,
              color: value
                  ? theme.colors.onSecondaryContainer
                  : theme.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: value
                        ? theme.colors.onSecondaryContainer
                        : theme.colors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// CanvasIconButton is a small square action, for the buttons that sit between
/// the fields -- shuffle a seed, delete a keyframe, bring to front.
class CanvasIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const CanvasIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(right: 3, top: controlLabelHeight),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Container(
            width: controlHeight,
            height: controlHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: active ? theme.colors.secondaryContainer : null,
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            child: Icon(
              icon,
              size: 15,
              color: !enabled
                  ? theme.colors.onSurfaceVariant.withValues(alpha: 0.35)
                  : active
                      ? theme.colors.onSecondaryContainer
                      : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// _labelled puts a control's own small label above it.
Widget _labelled(ThemeNotifier theme, String label, Widget child) => Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: controlLabelHeight,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  color: theme.colors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          child,
        ],
      ),
    );

/// CanvasExpander is a control that opens to reveal a list.
///
/// Its own thing rather than Flutter's ExpansionTile, which is built for a
/// Material list and brings a tile's height, its own dividers and an animation
/// that all look wrong in a settings column. This is a heading you can press.
///
/// It exists for one case: a football team's squad is eleven rows of four
/// fields, which is far more than any other element's settings put together,
/// and having it permanently open would mean scrolling past a team sheet to
/// reach the colours every time.
class CanvasExpander extends StatefulWidget {
  final String label;

  /// trailing is shown beside the label when closed -- a count, usually, so
  /// the heading says how much is behind it.
  final String? trailing;

  final List<Widget> children;

  /// initiallyOpen is false for the squad list. Somebody opening a team's
  /// settings is usually there for the colours or the formation.
  final bool initiallyOpen;

  const CanvasExpander({
    required this.label,
    required this.children,
    this.trailing,
    this.initiallyOpen = false,
    super.key,
  });

  @override
  State<CanvasExpander> createState() => _CanvasExpanderState();
}

class _CanvasExpanderState extends State<CanvasExpander> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_open ? Icons.expand_more : Icons.chevron_right,
                  size: 16, color: theme.colors.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                widget.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 5),
                Text(
                  widget.trailing!,
                  style: TextStyle(
                      fontSize: 9,
                      color:
                          theme.colors.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
              ],
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}
