import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

part 'controls_layout.dart';
part 'controls_groups.dart';
part 'controls_fields.dart';
part 'controls_buttons.dart';
part 'controls_pickers.dart';

// controls.dart is the small set of fixed-height, labelled controls the
// canvas settings are built from, so a panel of many properties stays
// readable. Each reports continuously while it changes; callers pass that
// through as transient edits (CanvasController.beginInteraction), so a drag
// shows its result live and is still one undo step.
//
// This file holds the sizes they share and the small pieces every panel
// uses. The controls themselves are in its parts: controls_layout (how they
// are laid out), controls_groups (what they are gathered in),
// controls_fields, controls_buttons and controls_pickers.

/// CanvasTip is [child] with [message] as its hover text -- or, where hover
/// text is turned off (TooltipVisibility, as in an element's settings), as
/// its name for a screen reader only. A Tooltip built where it can never
/// show costs several widgets on every build of every control.
class CanvasTip extends StatelessWidget {
  final String message;
  final Duration? waitDuration;
  final Widget child;
  const CanvasTip(
      {required this.message, this.waitDuration, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    if (!TooltipVisibility.of(context)) {
      return Semantics(tooltip: message, child: child);
    }
    return Tooltip(message: message, waitDuration: waitDuration, child: child);
  }
}

/// controlHeight is every control's height: a comfortable click target.
const double controlHeight = 27;

/// controlLabelGap keeps a caption from reading as part of its control.
const double controlLabelGap = 3;

/// controlLabelHeight is the caption above each control. Uncaptioned
/// controls are pushed down this much so a row sits on one baseline.
const double controlLabelHeight = 11;

/// The gaps the settings panel is spaced with, one scale for all of it.
///
/// canvasControlGap is between two controls on a line, canvasRowGap between
/// lines of a group, canvasCaptionGap under a group's name and
/// canvasGroupGap under every group (a rule between groups sits in the middle
/// of a doubled one). The group gap is three times the row gap, so the gap
/// alone shows where a group ends.
///
/// canvasCaptionedGap follows a captioned control: wider, because touching
/// captions read as one word. Bordered buttons and toggles keep the plain
/// gap, which the fixed-width button rows over a data grid rely on.
const double canvasControlGap = 5;
const double canvasCaptionedGap = 8;
const double canvasRowGap = 8;
const double canvasCaptionGap = 7;
const double canvasGroupGap = 24;

/// bandGroupHeight is how tall the line between two groups on the band is:
/// the caption and one row of controls, which is the whole of the band.
const double bandGroupHeight = 11 + 5 + controlHeight;

/// CanvasCards marks the settings inside a sectioned panel's section (see
/// panel_kit.dart), where each group is a card with its name and a "?" over
/// it, and the controls are a size up and further apart.
class CanvasCards extends InheritedWidget {
  /// title is the section's own, so a card does not say it a second time.
  final String title;

  /// off is a part of a card drawn at the ordinary size: a grid of cells
  /// with buttons over each column, which has its own measure.
  final bool off;

  const CanvasCards(
      {required super.child, this.title = "", this.off = false, super.key});

  /// none is [child] at the ordinary size, inside a card or not.
  static Widget none(Widget child) => CanvasCards(off: true, child: child);

  static bool on(BuildContext context) {
    var cards = context.dependOnInheritedWidgetOfExactType<CanvasCards>();
    return cards != null && !cards.off;
  }

  /// titleOf is the title of the section [context] is in.
  static String titleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasCards>()?.title ?? "";

  @override
  bool updateShouldNotify(CanvasCards old) =>
      old.title != title || old.off != off;
}

/// cardControlHeight, cardLabelHeight and cardLabelGap are controlHeight,
/// controlLabelHeight and controlLabelGap inside a card.
const double cardControlHeight = 38;
const double cardLabelHeight = 15;
const double cardLabelGap = 6;

/// cardGap is the room between controls, and between lines, in a card.
const double cardGap = 12;

/// CanvasNoHover marks a part of the window with no hover text: the element
/// settings panel, where a tooltip shown while scrolling is left lying over
/// other sections. A "?" explains a control there instead. Tooltips with
/// timings of their own ask this.
class CanvasNoHover extends InheritedWidget {
  const CanvasNoHover({required super.child, super.key});

  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasNoHover>() != null;

  @override
  bool updateShouldNotify(CanvasNoHover old) => false;
}

/// CanvasDense is the settings panel's compact measure: lower controls,
/// closer together, and each group's name in small capitals over its
/// controls rather than a card within the section's card.
class CanvasDense extends InheritedWidget {
  /// height is how tall its controls are: 30 in a section, 36 in the quick
  /// strip over them.
  final double height;
  const CanvasDense({required super.child, this.height = 30, super.key});

  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasDense>() != null;

  static CanvasDense? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasDense>();

  @override
  bool updateShouldNotify(CanvasDense old) => old.height != height;
}

/// cardHeightIn, cardGapIn, cardLabelGapIn and cardLabelHeightIn are the
/// card measures where [context] is, smaller in a dense panel.
double cardHeightIn(BuildContext context) =>
    CanvasDense.of(context)?.height ?? cardControlHeight;
double cardGapIn(BuildContext context) =>
    CanvasDense.on(context) ? 8 : cardGap;
double cardLabelGapIn(BuildContext context) =>
    CanvasDense.on(context) ? 4 : cardLabelGap;
double cardLabelHeightIn(BuildContext context) =>
    CanvasDense.on(context) ? 16 : cardLabelHeight;

/// heightIn is how tall a control stands where [context] is.
double heightIn(BuildContext context) =>
    CanvasCards.on(context) ? cardHeightIn(context) : controlHeight;

/// nudgeIn is how far down an uncaptioned control sits, to line up.
double nudgeIn(BuildContext context) => CanvasControlScope.isInline(context)
    ? 0
    : CanvasCards.on(context)
        ? cardLabelHeightIn(context) + cardLabelGapIn(context)
        : controlWithLabelHeight - controlHeight;

/// controlWithLabelHeight is what a captioned control stands at, all in.
const double controlWithLabelHeight =
    controlLabelHeight + controlLabelGap + controlHeight;

/// CanvasControlScope says how the controls below it lay out: in a row on
/// the band, or stacked down a sidebar with no width to scroll. Every
/// control that sizes itself clamps to what the scope allows.
class CanvasControlScope extends InheritedWidget {
  /// maxWidth is the widest a single control may be, so one sized past its
  /// parent in a sidebar does not overflow.
  final double maxWidth;

  /// inline puts a control's caption beside it rather than above: for the
  /// strip over the canvas, where a line of captions would push it down.
  final bool inline;

  /// hoverCaptions puts captions in hover text: for the timeline's play bar,
  /// whose controls are known by what is in them.
  final bool hoverCaptions;

  const CanvasControlScope({
    required this.maxWidth,
    this.inline = false,
    this.hoverCaptions = false,
    required super.child,
    super.key,
  });

  /// isInline is whether captions sit beside their controls here, or are
  /// hover text, which lines up the same way.
  static bool isInline(BuildContext context) {
    var scope = maybeOf(context);
    return (scope?.inline ?? false) || (scope?.hoverCaptions ?? false);
  }

  /// hovers is whether captions are hover text here.
  static bool hovers(BuildContext context) =>
      maybeOf(context)?.hoverCaptions ?? false;

  static CanvasControlScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasControlScope>();

  /// widthFor is a control's preferred width, capped by the scope.
  static double widthFor(BuildContext context, double wanted) {
    var scope = maybeOf(context);
    return scope == null ? wanted : math.min(wanted, scope.maxWidth);
  }

  @override
  bool updateShouldNotify(CanvasControlScope old) =>
      old.maxWidth != maxWidth ||
      old.inline != inline ||
      old.hoverCaptions != hoverCaptions;
}

/// CanvasLineBreak starts a new line inside a group, whatever the sidebar's
/// width: a child as wide as a line and no height. [gap] adds air; a break
/// with a height is a line of its own, so that is the height plus two runs.
class CanvasLineBreak extends StatelessWidget {
  final double gap;
  const CanvasLineBreak({this.gap = 0, super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, height: gap);
}

/// CanvasSeparator is a rule across a row of controls, with air either side:
/// for a group holding several of the same thing one after another.
class CanvasSeparator extends StatelessWidget {
  const CanvasSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: 1,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        color: ThemeNotifier.of(context)
            .colors
            .outlineVariant
            .withValues(alpha: 0.45),
      );
}

/// CanvasHint is a question mark that explains a section, so the explanation
/// is there for whoever has not read it and takes no room from whoever has.
class CanvasHint extends StatefulWidget {
  final String message;

  /// round draws it as a card's "?": a ring a size up, with the mark in it.
  final bool round;

  const CanvasHint(this.message, {this.round = false, super.key});

  @override
  State<CanvasHint> createState() => _CanvasHintState();
}

/// The "?" opens on a click, never a hover, so passing over it does not
/// cover the control beside it. Any further click shuts it.
class _CanvasHintState extends State<CanvasHint> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _bubble;

  void _toggle() {
    if (_bubble != null) {
      _close();
      return;
    }
    _bubble = OverlayEntry(
      builder: (context) => _bubbleOf(context),
    );
    Overlay.of(context).insert(_bubble!);
    setState(() {});
  }

  /// _bubbleOf is the open "?". The theme is read here, as it is drawn: the
  /// overlay is outside the tree that opened it.
  Widget _bubbleOf(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
        ),
      ),
      CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 6),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          color: theme.colors.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.message,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.colors.onSurface)),
            ),
          ),
        ),
      ),
    ]);
  }

  void _close() {
    _bubble?.remove();
    _bubble = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bubble?.remove();
    _bubble = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var open = _bubble != null;
    var ink = open
        ? theme.colors.primary
        : theme.colors.onSurfaceVariant.withValues(alpha: 0.75);
    Widget mark = widget.round
        ? Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: open
                      ? theme.colors.primary
                      : theme.colors.outlineVariant),
            ),
            child: Text("?",
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(Icons.help_outline, size: 13, color: ink),
          );
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: "Help",
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: mark,
          ),
        ),
      ),
    );
  }
}

/// CanvasStatus is a line a panel says back (what a button just did, or what
/// stopped it), in view on its own line, unlike a CanvasHint behind a click.
class CanvasStatus extends StatelessWidget {
  final String message;
  const CanvasStatus(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return SizedBox(
      width: 260,
      child: Text(message,
          style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant)),
    );
  }
}

/// CanvasFill marks a control that should grow to help fill its line. Its
/// own width is the least it will ever be; [CanvasWrap] decides the rest.
class CanvasFill extends ParentDataWidget<_CanvasWrapParentData> {
  const CanvasFill({required super.child, super.key});

  @override
  void applyParentData(RenderObject renderObject) {
    var data = renderObject.parentData! as _CanvasWrapParentData;
    if (data.fill) return;
    data.fill = true;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _RawCanvasWrap;
}

/// isTypingInAField is whether the keyboard belongs to a text field. The
/// canvas and timeline claim the arrows and space bar from a Focus below
/// the app's Shortcuts, so their handlers run first and must step aside
/// while somebody types. The field may be in the band, sidebar or a dialog.
bool isTypingInAField() {
  var context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// CanvasWatch rebuilds only when the part of a listenable it cares about
/// changes: the canvas controller notifies on every pixel of a drag.
///
/// [select] must be cheap and return a value (a string, number or record):
/// it runs on every notification and is compared with ==, and a list or map
/// compares by identity, so would rebuild every time.
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
