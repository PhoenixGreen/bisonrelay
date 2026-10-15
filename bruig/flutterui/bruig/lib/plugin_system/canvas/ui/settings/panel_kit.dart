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

  const CanvasStepper({
    required this.label,
    this.name,
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
                  fontSize: CanvasCards.on(context) ? 14 : 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            canvasSized(context,
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
          canvasSized(context,
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
class CanvasTile<T> {
  final T value;
  final String label;

  /// preview draws what choosing it does. Null shows [icon] instead.
  final WidgetBuilder? preview;
  final IconData? icon;

  const CanvasTile(this.value, this.label, {this.preview, this.icon});
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

  const CanvasTiles({
    this.help = "",
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

  Widget _tile(BuildContext context, ThemeNotifier theme, CanvasTile<T> t) {
    var on = selected(t.value);
    var accent = theme.colors.primary;
    return MouseRegion(
      onEnter:
          onPreview == null || multiple ? null : (_) => onPreview!(t.value),
      onExit: onPreview == null || multiple ? null : (_) => onPreview!(null),
      child: Semantics(
        button: true,
        selected: on,
        label: t.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: keyOf == null ? null : ValueKey(keyOf!(t.value)),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
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
                  Container(
                    height: previewHeight,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: theme.colors.surfaceContainerHighest,
                    ),
                    alignment: Alignment.center,
                    child: t.preview != null
                        ? SizedBox.expand(child: t.preview!(context))
                        : Icon(t.icon ?? Icons.circle_outlined,
                            size: 20,
                            color: on ? accent : theme.colors.onSurfaceVariant),
                  ),
                  if (multiple && on)
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
    this.initiallyOpen = false,
    this.forceOpen = false,
    super.key,
  });

  @override
  State<CanvasSection> createState() => _CanvasSectionState();
}

class _CanvasSectionState extends State<CanvasSection> {
  late bool _open = rememberedSection(widget.remember) ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) {
      _open = true;
    } else if (rememberedSection(widget.remember) == null) {
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

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var open = _open;
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    var changed = widget.changes > 0;
    return Container(
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
          Row(children: [
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey("section-${widget.remember}"),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          color: open
                              ? accent.withValues(alpha: 0.16)
                              : theme.colors.surfaceContainerHighest,
                        ),
                        child: Icon(widget.icon,
                            size: 18, color: open ? accent : muted),
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
                                        fontSize: 14,
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
                                      style: TextStyle(
                                          fontSize: 10, color: muted)),
                                ),
                              ],
                            ]),
                            if (widget.summary.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(widget.summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: 12, color: muted)),
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
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                        ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child:
                            Icon(Icons.chevron_right, size: 20, color: muted),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            // Outside the heading's ink, so pressing it does not also fold
            // the section.
            if (open && changed && widget.onReset != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CanvasIconButton(
                  key: ValueKey("sectionReset-${widget.remember}"),
                  tight: true,
                  icon: Icons.restart_alt,
                  tooltip: "Reset ${widget.title}",
                  onPressed: widget.onReset,
                ),
              ),
          ]),
          if (open)
            CanvasCards(
              child: Padding(
                key: ValueKey("sectionBody-${widget.remember}"),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: widget.children,
                ),
              ),
            ),
        ],
      ),
    );
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

  const CanvasToolTiles({
    this.help = "",
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
    var body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(right: card ? 10 : 0),
          child: LayoutBuilder(builder: (context, box) {
            const gap = 6.0;
            var n = tools.length;
            var width = box.maxWidth.isFinite ? box.maxWidth : 300.0;
            var each = math.max(44.0, (width - gap * (n - 1)) / n);
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (var (tool, icon, short) in tools)
                SizedBox(
                  width: each,
                  child: Tooltip(
                    message: tooltipOf(tool),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: ValueKey(keyOf(tool)),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onPick(tool == active ? null : tool),
                        child: Container(
                          height: card ? 56 : 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: tool == active
                                ? accent.withValues(alpha: 0.16)
                                : null,
                            border: Border.all(
                                color: tool == active
                                    ? accent
                                    : theme.colors.outlineVariant,
                                width: tool == active ? 1.5 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon,
                                  size: card ? 20 : 18,
                                  color: tool == active
                                      ? accent
                                      : theme.colors.onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text(short,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: card ? 10.5 : 9.5,
                                      color: theme.colors.onSurface)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
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
          if (settings.isNotEmpty)
            CanvasWrap(
                runSpacing: card ? cardGap : canvasRowGap, children: settings),
        ],
      ],
    );
    if (card) {
      return canvasCard(context,
          title: canvasCardTitle(context, "Tools"), help: help, body: body);
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: canvasGroupGap / 2),
        child: body);
  }
}
