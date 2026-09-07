import 'dart:math' as math;

import 'package:bruig/storage_manager.dart';
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

/// controlLabelGap is the air between a control's caption and the control.
///
/// Three pixels rather than none. A caption sitting directly on the box it
/// names reads as part of it, which is what made the denser groups -- the
/// picture's, the border's -- look cramped beside the position row, whose
/// fields are underlines with room around them.
const double controlLabelGap = 3;

/// controlLabelHeight is the little caption above each control. Everything
/// that has no caption -- a toggle, an icon button -- is pushed down by
/// exactly this much so the whole row sits on one baseline.
const double controlLabelHeight = 11;

/// bandGroupHeight is how tall the line between two groups on the band is:
/// the caption and one row of controls, which is the whole of the band.
const double bandGroupHeight = 11 + 5 + controlHeight;

/// controlWithLabelHeight is what a captioned control stands at, all in.
///
/// One place, because three others were adding the same two numbers up for
/// themselves -- the keyframe strip's height twice and the timeline's row once
/// -- and none of them knew when a gap was put between the caption and the
/// control. The first thing that happened was three pixels of overflow in a
/// row nobody had touched.
const double controlWithLabelHeight =
    controlLabelHeight + controlLabelGap + controlHeight;

/// CanvasControlScope says how the controls below it should lay themselves out.
///
/// There are two places the same controls appear: the band above the canvas,
/// where a group is a row and the whole line scrolls sideways, and the Layers
/// sidebar, where there is no width to scroll and a group has to stack.
/// Rather than a second set of forty controls, a group asks the scope which it
/// is in, and every control that sizes itself clamps to what the scope allows.
class CanvasControlScope extends InheritedWidget {
  /// maxWidth is the widest a single control may be. In a sidebar this is what
  /// stops the chart's data box -- which asks for 260 -- from running off the
  /// edge, since a control sized past its parent overflows rather than
  /// shrinking.
  final double maxWidth;

  /// inline puts a control's caption beside it rather than above it.
  ///
  /// For the band over the canvas, which is two lines high and was three: a
  /// caption over every control is a whole line of nine-pixel grey text, and
  /// in a strip that is already only as tall as the settings on it that line
  /// is the difference between the canvas starting here and starting an inch
  /// lower. Down a sidebar the captions belong above, where they line the
  /// controls up with each other.
  final bool inline;

  const CanvasControlScope({
    required this.maxWidth,
    this.inline = false,
    required super.child,
    super.key,
  });

  /// isInline is whether captions go beside their controls here.
  static bool isInline(BuildContext context) =>
      maybeOf(context)?.inline ?? false;

  static CanvasControlScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasControlScope>();

  /// widthFor is a control's preferred width, capped by the scope.
  static double widthFor(BuildContext context, double wanted) {
    var scope = maybeOf(context);
    return scope == null ? wanted : math.min(wanted, scope.maxWidth);
  }

  @override
  bool updateShouldNotify(CanvasControlScope old) =>
      old.maxWidth != maxWidth || old.inline != inline;
}

/// CanvasLineBreak starts a new line inside a group.
///
/// A group lays its controls out with a Wrap, which fills each line before
/// starting the next -- so where the break falls depends on how wide the
/// sidebar happens to be, and six controls that are two different questions
/// came out as "X Y W" over "H Angle Opacity". This is a child wide enough to
/// take a whole line and tall enough to take none of it, which is how a Wrap
/// is told where a line ends.
///
class CanvasLineBreak extends StatelessWidget {
  const CanvasLineBreak({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: double.infinity, height: 0);
}

/// CanvasHint is a question mark that explains a section when it is hovered.
///
/// The sidebar's panels each carried a paragraph of explanation above or below
/// their contents, permanently, taking a fifth of a narrow column to say
/// something that is read once and never again. Behind a question mark it is
/// still there for whoever has not read it and costs nothing to whoever has.
///
/// Tap as well as hover, because a hint reachable only by hovering is a hint
/// that does not exist on a touch screen.
class CanvasHint extends StatelessWidget {
  final String message;
  const CanvasHint(this.message, {super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        // Wider than the sidebar, because the sidebar is what it is too big
        // for. A tooltip the width of the column it is explaining would be the
        // paragraph again, in a box.
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(
            Icons.help_outline,
            size: 13,
            color: ThemeNotifier.of(context)
                .colors
                .onSurfaceVariant
                .withValues(alpha: 0.7),
          ),
        ),
      );
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

  /// hideCaption drops the caption in a sidebar and keeps it in the band.
  ///
  /// For the one group whose name is the element's own. The sidebar already
  /// heads the settings with that, so the caption underneath said the same
  /// word a second time; the band has no such heading, so there it is the only
  /// hideCaption drops the group's own name, for a group whose name is
  /// already said by whatever is above it.
  ///
  /// It was called bandOnlyLabel, from when these controls were laid out two
  /// ways: down the sidebar with a caption over each group, and along a band
  /// above the canvas where the caption sat to the left instead. The band is
  /// gone, so "shown only in the band" is no longer a thing that can happen --
  /// what the flag does now is hide the caption, and it is used where the
  /// panel's own header has already named the element.
  final bool hideCaption;

  const CanvasControlGroup({
    required this.label,
    required this.children,
    this.hideCaption = false,
    super.key,
  });

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

    // Along the band the groups sit side by side, so what separates them is
    // room to the right and a line between them -- not a rule underneath,
    // which in a Row is an underline drawn across the strip and a dozen
    // pixels of nothing below every group.
    if (CanvasControlScope.isInline(context)) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hideCaption)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 5, left: 1),
                      child: caption),
                // Spaced as well as run-spaced. Without it the last control of
                // one group and the first of the next were touching, which is
                // what "1280 × 72055.0 KiB" was.
                //
                // Centred against each other, because a line of controls is
                // not all one height -- a switch, a box with a caption beside
                // it and a readout are three -- and aligned at the top they
                // sat at three different heights on a strip whose whole job
                // is to be one line.
                Wrap(
                  spacing: 4,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: children,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 2),
              child: Container(
                  width: 1,
                  height: bandGroupHeight,
                  color: theme.colors.outlineVariant.withValues(alpha: 0.45)),
            ),
          ],
        ),
      );
    }

    return Padding(
      // The spacing every group gets, and the reason it is here rather than in
      // each of them: a settings panel where one group breathes and the next
      // is packed reads as two panels by different hands. These four numbers
      // -- above the caption, under it, between wrapped rows, and before the
      // rule -- are the whole of it.
      //
      // A rule under each group as well as a gap. Six clusters of small
      // controls down one narrow column, separated by nine pixels of nothing,
      // ran together into one field of boxes -- the caption above each was the
      // only thing saying where one ended, and a caption is nine pixels tall
      // and grey.
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hideCaption)
            Padding(
                padding: const EdgeInsets.only(bottom: 7, left: 1),
                child: caption),
          Wrap(runSpacing: 8, children: children),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
                height: 1,
                color: theme.colors.outlineVariant.withValues(alpha: 0.45)),
          ),
        ],
      ),
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
      scrub: _ScrubLabel(
        label: widget.label,
        value: widget.value,
        min: widget.min,
        max: widget.max,
        decimals: widget.decimals,
        onChanged: widget.onChanged,
        onCommit: widget.onCommit,
      ),
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
        //
        // Its own Material, because ink -- the splash, and the highlight a
        // focused control keeps -- is painted by the nearest Material
        // *ancestor*, in that ancestor's coordinates. Without one here the
        // nearest was the whole sidebar, so the highlight left behind by
        // choosing a chart type was drawn at the dropdown's position in the
        // sidebar and stayed there: a grey box floating over the Add panel
        // while the settings scrolled underneath it. Painted here it is in
        // the right place and clipped to the control.
        child: Material(
          type: MaterialType.transparency,
          // And no highlight at all once the menu has closed. In a settings
          // panel the focused control is not a thing anybody is tracking, and
          // a box that stays lit after a choice reads as something still
          // open.
          child: DropdownButton<T>(
            focusColor: Colors.transparent,
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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
              style:
                  TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
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
      {required this.label,
      required this.value,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      // The nudge lines a control with no caption up with the ones that have
      // them. On the band the captions are beside their controls and there is
      // nothing above to line up under, so the nudge is what pushed this out
      // of line with its neighbours.
      padding: EdgeInsets.only(
          right: 5,
          top: CanvasControlScope.isInline(context) ? 0 : controlLabelHeight),
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
      // The nudge lines a control with no caption up with the ones that have
      // them. On the band the captions are beside their controls and there is
      // nothing above to line up under, so the nudge is what pushed this out
      // of line with its neighbours.
      padding: EdgeInsets.only(
          right: 3,
          top: CanvasControlScope.isInline(context) ? 0 : controlLabelHeight),
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
/// _ScrubLabel is a caption you can drag sideways to change the number under
/// it.
///
/// The label rather than the field itself, and that is not a compromise. A
/// TextField owns its own drag -- that is how text is selected -- so a scrub
/// on the field would either fight the selection or take it away, and typing
/// an exact number has to keep working. The caption above it is doing nothing
/// else, is already beside the value it belongs to, and can show a
/// left-and-right cursor to say so.
///
/// One pixel of travel moves the number by one of its own last digits: a whole
/// unit on a field showing whole numbers, a tenth on a field showing tenths.
///
/// Not derived from the field's range, which was the first attempt and was
/// far too coarse. Most of these ranges are guard rails rather than scales --
/// a player's X is bounded at a hundred thousand so that a typo cannot send
/// them into the next county, not because the field is a hundred-thousand-wide
/// dial -- so a step of a four-hundredth of the range was hundreds of pixels
/// per pixel. The last digit is the increment the field itself says it cares
/// about, and 1:1 with the pointer is the only ratio nobody has to learn.
///
/// Shift makes it ten times finer, for the last pixel of a nudge.
class _ScrubLabel extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;

  /// decimals is how precise the field is, and so what one step means.
  final int decimals;

  final ValueChanged<double> onChanged;
  final VoidCallback? onCommit;

  const _ScrubLabel({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    this.onCommit,
  });

  @override
  State<_ScrubLabel> createState() => _ScrubLabelState();
}

class _ScrubLabelState extends State<_ScrubLabel> {
  /// _from is the value the drag started at, so the whole gesture is measured
  /// from one place. Accumulating each small delta instead drifts, and rounding
  /// to whole pixels on the way makes a slow drag move less than a fast one
  /// over the same distance.
  double _from = 0;

  /// _startX is where the pointer went down, in screen coordinates.
  ///
  /// Screen rather than local, and recorded rather than assumed: what arrives
  /// is the pointer's *position*, not how far it has travelled, so without a
  /// starting point to subtract the value jumped by wherever in the label it
  /// was grabbed.
  double _startX = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    var step = math.pow(10, -widget.decimals).toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      // A Listener rather than a GestureDetector, so the number moves from the
      // very first pixel. A drag gesture is not recognised until the pointer
      // has travelled about eighteen pixels, and those eighteen are then gone:
      // a twenty-five pixel scrub moved the value by seven. Nothing else is
      // competing for these pointers -- it is a caption -- so there is no
      // arena to take part in and nothing to be gained by waiting.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _from = widget.value;
          _startX = event.position.dx;
          _dragging = true;
        },
        onPointerMove: (event) {
          if (!_dragging) return;
          var fine = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
          var travelled = event.position.dx - _startX;
          var next =
              (_from + travelled * step * fine).clamp(widget.min, widget.max);
          widget.onChanged(next.toDouble());
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

/// _labelled puts a caption above a control.
///
/// [scrub] makes that caption a handle: dragging it sideways runs the number
/// up and down. See _ScrubLabel.
Widget _labelled(ThemeNotifier theme, String label, Widget child,
    {Widget? scrub}) {
  return Builder(builder: (context) {
    var inline = CanvasControlScope.isInline(context);
    var caption = Text(
      label,
      style: TextStyle(
          fontSize: inline ? 10 : 9,
          height: 1.1,
          color: theme.colors.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
    );

    // Beside the control in the band, above it in a sidebar. The caption is
    // the same words either way; what differs is which direction there is
    // room in.
    if (inline) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (label.isNotEmpty) ...[
              // Capped, so a long caption cannot push the control off the
              // end of a strip that is already scrolling sideways.
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

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scrub != null)
            scrub
          else
            SizedBox(height: controlLabelHeight, child: caption),
          const SizedBox(height: controlLabelGap),
          child,
        ],
      ),
    );
  });
}

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
  ///
  /// Ellipsised rather than allowed to push the heading wide. It is a summary,
  /// and a summary that overflowed the panel by a hundred pixels is what a
  /// preset with a long name did the first time one existed.
  final String? trailing;

  /// action is a button on the right of the heading, which works whether the
  /// section is open or shut.
  ///
  /// For the one thing a section does that somebody wants without reading it:
  /// refreshing a table's data, putting its rows back in order. Opening a
  /// section, finding a button, pressing it and closing the section again is
  /// four actions for one, every time.
  final Widget? action;

  final List<Widget> children;

  /// initiallyOpen is false for the squad list. Somebody opening a team's
  /// settings is usually there for the colours or the formation.
  final bool initiallyOpen;

  /// remember names where this section's open state is kept, or null to let
  /// it start closed every time.
  ///
  /// Kept in memory as well as on disk, and that is the point rather than an
  /// optimisation: the settings panel is rebuilt from scratch whenever the
  /// selection changes, and a fresh State reads a stored preference
  /// asynchronously -- so a section opened, deselected and selected again was
  /// shut for as long as it took the answer to come back off disk, which is
  /// every time anybody looked.
  final String? remember;

  const CanvasExpander({
    required this.label,
    required this.children,
    this.trailing,
    this.action,
    this.initiallyOpen = false,
    this.remember,
    super.key,
  });

  @override
  State<CanvasExpander> createState() => _CanvasExpanderState();
}

class _CanvasExpanderState extends State<CanvasExpander> {
  /// _remembered is every named section's state, for this run of the app.
  static final Map<String, bool> _remembered = {};

  late bool _open = _remembered[widget.remember] ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    var key = widget.remember;
    if (key != null && !_remembered.containsKey(key)) _restore(key);
  }

  Future<void> _restore(String key) async {
    var saved = await StorageManager.readData("canvasSection.$key");
    if (saved is! bool) return;
    _remembered[key] = saved;
    if (mounted) setState(() => _open = saved);
  }

  void _toggle() {
    setState(() => _open = !_open);
    var key = widget.remember;
    if (key == null) return;
    _remembered[key] = _open;
    StorageManager.saveData("canvasSection.$key", _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Two layouts, chosen by whether there is a width to fill.
        //
        // Down the sidebar there is, and the action belongs hard against the
        // right edge with the summary taking whatever is left -- a button
        // floating just after the text looks like part of the text. Along the
        // settings band there is not: it is a horizontal scroller offering
        // unbounded width, where an Expanded is not a layout that looks wrong
        // but an assertion, because a child cannot fill a space of unknown
        // size. So the heading shrink-wraps there instead.
        LayoutBuilder(builder: (context, constraints) {
          var fills = constraints.maxWidth.isFinite;
          Widget heading = InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right,
                    size: 16, color: theme.colors.onSurfaceVariant),
                const SizedBox(width: 3),
                // The name shrinks before the summary does, and both clip. A
                // heading carrying a button as well is wider than a narrow
                // sidebar for several of these, and a Text that cannot shrink
                // overflows however flexible everything beside it is.
                Flexible(
                  child: Text(
                    widget.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w600,
                      color:
                          theme.colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      widget.trailing!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9,
                          color: theme.colors.onSurfaceVariant
                              .withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ]),
            ),
          );

          return Row(
            mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
            children: [
              fills ? Expanded(child: heading) : Flexible(child: heading),
              // Outside the InkWell, so pressing it does not also open or shut
              // the section it sits on.
              if (widget.action != null) widget.action!,
            ],
          );
        }),
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

/// isTypingInAField is whether the keyboard currently belongs to a text field.
///
/// The canvas and the timeline both claim the arrow keys and the space bar --
/// one to nudge and scrub, the other to play. Both do it from a [Focus] that
/// wraps their whole subtree, and that is *below* the app's own Shortcuts
/// widget in the tree, so their handlers run first: a key pressed while typing
/// in one of their own number fields was scrubbing the timeline instead of
/// moving the caret, and the space bar was starting playback instead of
/// typing a space.
///
/// Asking the focus manager rather than tracking it per field, because the
/// field that has focus may belong to the settings band, the sidebar or a
/// dialog, none of which the timeline knows about.
bool isTypingInAField() {
  var context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// CanvasKeyframeDot is the little diamond beside a setting that can be
/// animated.
///
/// It says two things at once: that the setting *can* hold a keyframe, and
/// whether there is one on the frame being looked at. Pressing it adds or
/// removes one.
///
/// A keyframe on this canvas is a whole pose -- where the element is, how big,
/// how turned, how faded -- rather than one channel per property, so every dot
/// on an element's row lights up together and pressing any of them adds the
/// same keyframe. That is a real limitation and the tooltip says so; the
/// alternative is four tracks per element and four rows of marks on a strip
/// that has room for one.
class CanvasKeyframeDot extends StatelessWidget {
  /// on is whether a keyframe sits on the current frame.
  final bool on;

  /// enabled is false when the document is a still, where a keyframe would
  /// have nothing to interpolate towards.
  final bool enabled;

  final String tooltip;
  final VoidCallback onPressed;

  const CanvasKeyframeDot({
    required this.on,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      // The nudge lines a control with no caption up with the ones that have
      // them. On the band the captions are beside their controls and there is
      // nothing above to line up under, so the nudge is what pushed this out
      // of line with its neighbours.
      padding: EdgeInsets.only(
          right: 4,
          top: CanvasControlScope.isInline(context) ? 0 : controlLabelHeight),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 18,
            height: controlHeight,
            child: Icon(
              on ? Icons.diamond : Icons.diamond_outlined,
              size: 11,
              color: !enabled
                  ? theme.colors.onSurfaceVariant.withValues(alpha: 0.25)
                  : on
                      ? theme.colors.primary
                      : theme.colors.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// CanvasGridCell is a text field with no caption over it.
///
/// Its own widget rather than CanvasTextField because that one carries a
/// label above it and a fixed width, and a grid of forty of those would be a
/// grid of forty captions.
///
/// Shared by the chart's numbers and the table's cells, which are the same
/// control asked for twice.
class CanvasGridCell extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final bool multiline;
  final bool dense;
  final String hint;

  const CanvasGridCell({
    required this.value,
    required this.onChanged,
    required this.onCommit,
    this.multiline = false,
    this.dense = false,
    this.hint = "",
    super.key,
  });

  @override
  State<CanvasGridCell> createState() => CanvasGridCellState();
}

class CanvasGridCellState extends State<CanvasGridCell> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit();
    });
  }

  @override
  void didUpdateWidget(CanvasGridCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only while it is not being typed in. Rewriting the text under the cursor
    // is how an editor eats a keystroke and moves the caret to the end.
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
  Widget build(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        expands: widget.multiline,
        maxLines: widget.multiline ? null : 1,
        minLines: null,
        style: TextStyle(fontSize: widget.dense ? 11 : 12),
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint.isEmpty ? null : widget.hint,
          hintStyle: const TextStyle(fontSize: 11),
          contentPadding: EdgeInsets.symmetric(
              horizontal: 6, vertical: widget.dense ? 5 : 6),
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      );
}

/// CanvasWatch rebuilds only when the part of a listenable it cares about
/// actually changes.
///
/// A ListenableBuilder rebuilds on every notification, and the canvas
/// controller notifies on every pixel of a drag. Most of the sidebar does not
/// change on most of those: a layer list shows names and order, and neither
/// moves when an element does. Watching a small value instead means the
/// difference between a list rebuilt sixty times a second and one rebuilt when
/// it has something new to say.
///
/// [select] must be cheap and must be a *value* -- a string, a number, a
/// record -- because it runs on every notification and is compared with ==.
/// Returning a list or a map would compare by identity and never match, which
/// is a rebuild every time wearing a disguise.
class CanvasWatch<T> extends StatefulWidget {
  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  const CanvasWatch({
    required this.listenable,
    required this.select,
    required this.builder,
    super.key,
  });

  @override
  State<CanvasWatch<T>> createState() => _CanvasWatchState<T>();
}

class _CanvasWatchState<T> extends State<CanvasWatch<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_check);
  }

  @override
  void didUpdateWidget(CanvasWatch<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_check);
      widget.listenable.addListener(_check);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_check);
    super.dispose();
  }

  void _check() {
    var next = widget.select();
    if (next == _value) return;
    if (mounted) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
