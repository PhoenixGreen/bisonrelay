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

// controls.dart is the small set of fixed-height, labelled controls the
// canvas settings are built from, so a panel of many properties stays
// readable. Each reports continuously while it changes; callers pass that
// through as transient edits (CanvasController.beginInteraction), so a drag
// shows its result live and is still one undo step.

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

class _CanvasWrapParentData extends ContainerBoxParentData<RenderBox> {
  bool fill = false;
  bool restart = false;
}

class _CanvasWrapRestart extends ParentDataWidget<_CanvasWrapParentData> {
  const _CanvasWrapRestart({required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    var data = renderObject.parentData! as _CanvasWrapParentData;
    if (data.restart) return;
    data.restart = true;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _RawCanvasWrap;
}

/// _GrowRoot is a growable control's outermost box. Asked loosely it takes
/// the least it can (the wider of control and caption), which CanvasWrap
/// packs lines from; asked tightly it takes what it is given. Either way it
/// passes a tight width down for the [_Stretch] inside to fill.
class _GrowRoot extends SingleChildRenderObjectWidget {
  final double min;

  const _GrowRoot({required this.min, required Widget super.child});

  @override
  _RenderGrowRoot createRenderObject(BuildContext context) =>
      _RenderGrowRoot(min);

  @override
  void updateRenderObject(BuildContext context, _RenderGrowRoot renderObject) {
    renderObject.min = min;
  }
}

class _RenderGrowRoot extends RenderProxyBox {
  _RenderGrowRoot(this._min);

  double _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markNeedsLayout();
  }

  double _natural() =>
      math.max(_min, child!.getMaxIntrinsicWidth(double.infinity));

  @override
  void performLayout() {
    var width = constraints.hasTightWidth
        ? constraints.maxWidth
        : constraints.constrainWidth(_natural());
    child!.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    size = constraints.constrain(Size(width, child!.size.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => _natural();

  @override
  double computeMaxIntrinsicWidth(double height) => _natural();
}

/// _Stretch is the control's own box inside that: as wide as it is offered,
/// and [min] wide when it is asked how little it will take.
class _Stretch extends SingleChildRenderObjectWidget {
  final double min;
  final double height;

  const _Stretch({
    required this.min,
    required this.height,
    required Widget super.child,
  });

  @override
  _RenderStretch createRenderObject(BuildContext context) =>
      _RenderStretch(min, height);

  @override
  void updateRenderObject(BuildContext context, _RenderStretch renderObject) {
    renderObject
      ..min = min
      ..height = height;
  }
}

class _RenderStretch extends RenderProxyBox {
  _RenderStretch(this._min, this._height);

  double _min;
  set min(double value) {
    if (_min == value) return;
    _min = value;
    markNeedsLayout();
  }

  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var width = constraints.constrainWidth(
        constraints.maxWidth.isFinite ? constraints.maxWidth : _min);
    var height = constraints.constrainHeight(_height);
    child!.layout(BoxConstraints.tightFor(width: width, height: height));
    size = Size(width, height);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _min;

  @override
  double computeMaxIntrinsicWidth(double height) => _min;

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;
}

/// canvasSized is a control's own box: [min] wide, or as wide as the line
/// has room for where it may grow.
Widget canvasSized(
  BuildContext context, {
  required double min,
  required double height,
  required bool grow,
  required Widget child,
}) =>
    CanvasCellFill.on(context)
        ? SizedBox(width: double.infinity, height: height, child: child)
        : grow && _CanvasWrapScope.of(context)
            ? _Stretch(min: min, height: height, child: child)
            : SizedBox(width: min, height: height, child: child);

/// CanvasCellFill makes a control as wide as the room it is given: one cell
/// of a row laid out by hand (see panelRow).
class CanvasCellFill extends InheritedWidget {
  const CanvasCellFill({required super.child, super.key});

  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasCellFill>() != null;

  @override
  bool updateShouldNotify(CanvasCellFill old) => false;
}

/// CanvasWrap is a Wrap whose marked children share out the room left over,
/// so a row of boxes fills a sidebar of any width instead of leaving a
/// ragged margin.
///
/// The extra is one per-control amount, the same on every line: a title
/// field stays wider than a number field, and number fields on different
/// lines come out the same width, so Angle sits under X. The amount is the
/// smallest any line can afford, so widening never pushes a control off its
/// line. Lines are [canvasRowGap] apart unless told otherwise.
class CanvasWrap extends StatelessWidget {
  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  const CanvasWrap({
    required this.children,
    this.spacing = 0,
    this.runSpacing = canvasRowGap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _RawCanvasWrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          // Marked here, not by each control: the mark is parent data and
          // must sit between this and the control, and its scope then
          // covers the control alone, not the controls in a child's Wrap.
          for (var child in children)
            if (child is CanvasGrowable && (child as CanvasGrowable).grow)
              CanvasFill(
                child: _GrowRoot(
                  min: (child as CanvasGrowable).least,
                  child: _CanvasWrapScope(child: child),
                ),
              )
            else if (child is CanvasBlockBreak)
              const _CanvasWrapRestart(child: CanvasLineBreak())
            else
              child,
        ],
      );
}

/// CanvasBlockBreak ends a line and restarts the sharing out, so a revealed
/// line, which affords less, cannot narrow the row of the button that
/// revealed it. [CanvasMoreGroup] puts one before what it reveals; a
/// [CanvasLineBreak] does not, as a group's second line is the same group.
class CanvasBlockBreak extends StatelessWidget {
  const CanvasBlockBreak({super.key});

  @override
  Widget build(BuildContext context) => const CanvasLineBreak();
}

/// CanvasGrowable is a control that will take some of the room left over on
/// its line if [CanvasWrap] offers it. See CanvasTextField.grow.
abstract interface class CanvasGrowable {
  bool get grow;

  /// least is the width it will not go below.
  double get least;
}

/// _CanvasWrapScope says a control is in a CanvasWrap. Only there does it
/// offer to grow; anywhere else a seventy-pixel field could end up four
/// hundred wide.
class _CanvasWrapScope extends InheritedWidget {
  const _CanvasWrapScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CanvasWrapScope>() != null;

  @override
  bool updateShouldNotify(_CanvasWrapScope old) => false;
}

class _RawCanvasWrap extends MultiChildRenderObjectWidget {
  final double spacing;
  final double runSpacing;

  const _RawCanvasWrap({
    required super.children,
    this.spacing = 0,
    this.runSpacing = 0,
  });

  @override
  RenderCanvasWrap createRenderObject(BuildContext context) =>
      RenderCanvasWrap(spacing: spacing, runSpacing: runSpacing);

  @override
  void updateRenderObject(BuildContext context, RenderCanvasWrap renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class RenderCanvasWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CanvasWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CanvasWrapParentData> {
  RenderCanvasWrap({double spacing = 0, double runSpacing = 0})
      : _spacing = spacing,
        _runSpacing = runSpacing;

  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CanvasWrapParentData) {
      child.parentData = _CanvasWrapParentData();
    }
  }

  @override
  void performLayout() {
    var width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;

    // Each child's natural width: a marked child answers with the least it
    // will take; the rest within the line, as a line break is that wide.
    var kids = <RenderBox>[];
    var fills = <bool>[];
    var restarts = <bool>[];
    var widths = <double>[];
    for (var child = firstChild; child != null;) {
      var data = child.parentData! as _CanvasWrapParentData;
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      kids.add(child);
      fills.add(data.fill);
      restarts.add(data.restart);
      widths.add(child.size.width);
      child = data.nextSibling;
    }

    // Packed greedily, as a Wrap packs.
    var lines = <List<int>>[];
    var blockAt = <int>{};
    var line = <int>[];
    var used = 0.0;
    for (var i = 0; i < kids.length; i++) {
      var w = widths[i];
      if (line.isNotEmpty && used + _spacing + w > width + 0.01) {
        lines.add(line);
        line = [];
        used = 0;
      }
      if (restarts[i]) blockAt.add(lines.length + (line.isEmpty ? 0 : 1));
      used += (line.isEmpty ? 0 : _spacing) + w;
      line.add(i);
    }
    if (line.isNotEmpty) lines.add(line);

    // One amount per block (see CanvasBlockBreak), the smallest any line in
    // it can afford, so a group's lines keep the same columns. A line started
    // on purpose (the first, or after a break or full-width control) with one
    // control to grow fills the line and is left out of the sharing, or a
    // lone dropdown would cut its words short. A line that merely wrapped
    // still shares, so a wrapped row of numbers keeps its columns.
    bool full(int i) => widths[i] >= width - 0.5;
    var alone = <int>{};
    for (var (at, row) in lines.indexed) {
      if (row.where((i) => fills[i]).length != 1) continue;
      var wrapped = at > 0 &&
          lines[at - 1].where((i) => fills[i]).length > 1 &&
          !full(lines[at - 1].last) &&
          !full(row.first);
      if (!wrapped) alone.add(at);
    }
    var extras = List<double>.filled(lines.length, 0);
    for (var from = 0; from < lines.length;) {
      var to = from + 1;
      while (to < lines.length && !blockAt.contains(to)) {
        to++;
      }
      var extra = double.infinity;
      for (var at = from; at < to; at++) {
        var row = lines[at];
        var marked = [
          for (var i in row)
            if (fills[i]) i
        ];
        if (marked.isEmpty || alone.contains(at)) continue;
        var taken = _spacing * (row.length - 1);
        for (var i in row) {
          taken += widths[i];
        }
        var slack = width - taken;
        if (slack <= 0) {
          extra = 0;
          break;
        }
        extra = math.min(extra, slack / marked.length);
      }
      if (!extra.isFinite) extra = 0;
      for (var at = from; at < to; at++) {
        extras[at] = extra;
        if (!alone.contains(at)) continue;
        var row = lines[at];
        var taken = _spacing * (row.length - 1);
        for (var i in row) {
          taken += widths[i];
        }
        extras[at] = math.max(0, width - taken);
      }
      from = to;
    }

    // And laid out again at what they have been given.
    for (var (at, row) in lines.indexed) {
      if (extras[at] <= 0) continue;
      for (var i in row) {
        if (!fills[i]) continue;
        kids[i].layout(BoxConstraints.tightFor(width: widths[i] + extras[at]),
            parentUsesSize: true);
        widths[i] = kids[i].size.width;
      }
    }

    // A line with nothing tall on it (a CanvasLineBreak) takes no room and
    // costs no gap, or a deliberate break would be charged the gap twice.
    var y = 0.0;
    var started = false;
    for (var row in lines) {
      var height = 0.0;
      for (var i in row) {
        height = math.max(height, kids[i].size.height);
      }
      if (height > 0 && started) y += _runSpacing;
      var x = 0.0;
      for (var i in row) {
        var data = kids[i].parentData! as _CanvasWrapParentData;
        data.offset = Offset(x, y + (height - kids[i].size.height) / 2);
        x += widths[i] + _spacing;
      }
      if (height == 0) continue;
      y += height;
      started = true;
    }

    size = constraints.constrain(Size(width, math.max(0, y)));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    for (var child = firstChild; child != null;) {
      var data = child.parentData! as _CanvasWrapParentData;
      total += child.getMaxIntrinsicWidth(double.infinity) + _spacing;
      child = data.nextSibling;
    }
    return total;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// CanvasNoScrollbar is a scroll behaviour with no bar, for panels scrolled
/// by wheel, trackpad or finger rather than by a handle.
class CanvasNoScrollbar extends ScrollBehavior {
  const CanvasNoScrollbar();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// CanvasControlGroup is a labelled cluster of controls with a rule after
/// it, so a panel of many controls does not read as one mass.
class CanvasControlGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  /// hideCaption drops the group's own name where something above already
  /// says it (the panel's header naming the element).
  final bool hideCaption;

  /// captionGap is the room under the caption: more for a sentence, or it
  /// runs into the first control's caption.
  final double captionGap;

  /// rule is the line under the group, dropped where the next group is a
  /// continuation rather than a new subject.
  final bool rule;

  /// onRename makes the caption renamable by double-clicking it, as files,
  /// scenes and layers are; null for captions that are headings.
  final ValueChanged<String>? onRename;

  /// below goes under the group's controls and above its rule: the settings
  /// a button in the group has opened (see CanvasMoreGroup).
  final Widget? below;

  /// folded says whether this group is shut; null for groups always open.
  /// Shut, only the caption stays, pressed to reopen it. CanvasFoldingGroup
  /// remembers the answer.
  final bool? folded;

  /// onFold is the press on the caption, required wherever [folded] is set.
  final VoidCallback? onFold;

  const CanvasControlGroup({
    required this.label,
    required this.children,
    this.hideCaption = false,
    this.captionGap = canvasCaptionGap,
    this.rule = true,
    this.below,
    this.onRename,
    this.folded,
    this.onFold,
    this.help,
    super.key,
  });

  /// help is what the group is for, behind the "?" beside its name in a
  /// card. The hints among its children join it there.
  final String? help;

  /// _card is the group as a card in a section.
  Widget _card(BuildContext context, ThemeNotifier theme) {
    var hints = [
      for (var c in children)
        if (c is CanvasHint) c.message
    ];
    var rest = [
      for (var c in children)
        if (c is! CanvasHint) c
    ];
    var about =
        [if (help != null && help!.isNotEmpty) help!, ...hints].join("\n\n");
    var shut = folded == true;
    var dense = CanvasDense.on(context);
    var title = dense
        ? TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: theme.colors.onSurfaceVariant)
        : TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: theme.colors.onSurface);
    Widget name = onRename != null
        ? _RenamableCaption(label: label, style: title, onRename: onRename!)
        : Text(dense ? label.toUpperCase() : label, style: title);
    if (folded != null) {
      name = InkWell(
        onTap: onFold,
        borderRadius: BorderRadius.circular(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(shut ? Icons.chevron_right : Icons.expand_more,
              size: 16, color: theme.colors.onSurfaceVariant),
          const SizedBox(width: 2),
          name,
        ]),
      );
    }
    // Named in a card where there is a "?" to ask about it, but never with
    // the section's own name. In a dense panel a hidden name stays hidden.
    var named = label.isNotEmpty &&
        (!hideCaption || (about.isNotEmpty && !dense)) &&
        label != CanvasCards.titleOf(context);
    // Unnamed in a dense panel, its "?" ends its controls instead of taking
    // a heading line.
    var inline = dense && !named && about.isNotEmpty;
    return canvasCard(context,
        title: named ? name : null,
        help: inline ? "" : about,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!shut)
              CanvasWrap(runSpacing: cardGapIn(context), children: [
                ...rest,
                if (inline) CanvasHint(about, round: true),
              ]),
            if (below != null && !shut) below!,
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return _card(context, theme);
    }
    var style = TextStyle(
      fontSize: 9,
      letterSpacing: 0.7,
      fontWeight: FontWeight.w600,
      color: theme.colors.onSurfaceVariant.withValues(alpha: 0.7),
    );
    Widget caption = Text(label.toUpperCase(), style: style);
    if (onRename != null) {
      caption =
          _RenamableCaption(label: label, style: style, onRename: onRename!);
    }
    // A chevron before the words; the whole caption is the target.
    if (folded != null) {
      caption = Material(
        // Its own Material, so the highlight stays with the control inside a
        // scrolling list rather than on whatever Material is above it. (The
        // same holds wherever this file says "Its own Material".)
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onFold,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(1, 2, 4, 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(folded! ? Icons.chevron_right : Icons.expand_more,
                  size: 13, color: style.color),
              const SizedBox(width: 2),
              caption,
            ]),
          ),
        ),
      );
    }
    var shut = folded == true;

    // Every "?" in the group goes together on its heading row, on the right.
    var about = [
      if (help != null && help!.isNotEmpty) help!,
      for (var c in children)
        if (c is CanvasHint) c.message,
    ].join("\n\n");
    var controls = [
      for (var c in children)
        if (c is! CanvasHint) c
    ];
    var hint = about.isEmpty ? null : CanvasHint(about);

    // Along the band the groups sit side by side, so what separates them is
    // room to the right and a line between them, not a rule underneath.
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
                if (!hideCaption || hint != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 5, left: 1),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!hideCaption) caption,
                        if (hint != null) hint,
                      ])),
                // Spaced as well as run-spaced, so groups do not touch.
                // Centred: a switch, a captioned box and a readout differ
                // in height on a one-line strip.
                if (!shut)
                  Wrap(
                    spacing: 4,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: controls,
                  ),
                if (below != null && !shut) below!,
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
      // Every group leaves the same gap under it, and a rule sits in the
      // middle of a doubled one, so the line belongs to neither group.
      padding: const EdgeInsets.only(bottom: canvasGroupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hideCaption || hint != null)
            Padding(
                padding: EdgeInsets.only(bottom: captionGap, left: 1),
                child: Row(children: [
                  Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: hideCaption ? const SizedBox.shrink() : caption),
                  ),
                  if (hint != null) hint,
                ])),
          // No spacing: each control carries its own right-hand padding.
          if (!shut) CanvasWrap(runSpacing: canvasRowGap, children: controls),
          if (below != null && !shut) below!,
          if (rule) const CanvasGroupRule(),
        ],
      ),
    );
  }
}

/// CanvasTextButton is a button that says what it does in words ("Flip
/// across", "Clear mask"), sharing the room on its line with its neighbours.
class CanvasTextButton extends StatelessWidget implements CanvasGrowable {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// primary fills it with the accent: the one thing a card is for.
  final bool primary;

  @override
  final bool grow;

  /// least fits its words and icon, so a line wraps before any is cut short.
  @override
  double get least =>
      (label.isEmpty ? 0 : 26 + label.length * 7.2) +
      (icon == null ? 0 : (label.isEmpty ? 40 : 22));

  /// tooltip says what an icon alone does, on hover. Words need none.
  final String tooltip;

  const CanvasTextButton(
      {required this.label,
      required this.onPressed,
      this.tooltip = "",
      this.icon,
      this.primary = false,
      this.grow = true,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var enabled = onPressed != null;
    var ink = !enabled
        ? theme.colors.onSurfaceVariant.withValues(alpha: 0.4)
        : primary
            ? theme.colors.onPrimary
            : theme.colors.onSurface;
    Widget button(Widget child) =>
        tooltip.isEmpty ? child : Tooltip(message: tooltip, child: child);
    return Padding(
      padding: EdgeInsets.only(
          right: card ? cardGapIn(context) : canvasControlGap),
      child: canvasSized(
        context,
        min: least,
        height: heightIn(context),
        grow: grow,
        child: button(Material(
          color: primary && enabled ? theme.colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(card ? 10 : 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(card ? 10 : 4),
            onTap: onPressed,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 2 : 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(card ? 10 : 4),
                border: Border.all(
                    color: primary && enabled
                        ? theme.colors.primary
                        : theme.colors.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: label.isEmpty ? 18 : 16, color: ink),
                  if (label.isNotEmpty) const SizedBox(width: 6),
                ],
                if (label.isNotEmpty)
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: card ? 12 : 11,
                            fontWeight:
                                primary ? FontWeight.w600 : FontWeight.normal,
                            color: ink)),
                  ),
              ]),
            ),
          ),
        )),
      ),
    );
  }
}

/// CanvasSegmented is a choice of two to four short options, all in view and
/// the chosen one lit, on a line of its own with an optional caption.
class CanvasSegmented<T> extends StatelessWidget {
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// keyOf names each option, for the tests.
  final String Function(T)? keyOf;

  /// iconOf draws an option as an icon, its words its tooltip.
  final IconData Function(T)? iconOf;

  const CanvasSegmented(
      {required this.options,
      required this.value,
      required this.onChanged,
      this.label = "",
      this.keyOf,
      this.iconOf,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var accent = theme.colors.primary;
    // Dense: one box, its choices side by side with a line between, the
    // chosen one lit by a plain fill.
    var dense = card && CanvasDense.on(context);
    if (dense) {
      var bar = Container(
        height: cardHeightIn(context),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(color: theme.colors.outlineVariant),
        ),
        child: Row(children: [
          for (var (i, (option, words)) in options.indexed) ...[
            if (i > 0) Container(width: 1, color: theme.colors.outlineVariant),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: keyOf == null ? null : ValueKey(keyOf!(option)),
                  onTap: () => onChanged(option),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    // Lighter than the rest, in either theme.
                    color: option == value
                        ? theme.colors.onSurface.withValues(alpha: 0.12)
                        : null,
                    child: iconOf != null
                        ? Tooltip(
                            message: words,
                            child: Icon(iconOf!(option),
                                size: 16,
                                color: option == value
                                    ? theme.colors.onSurface
                                    : theme.colors.onSurfaceVariant))
                        : Text(words,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: option == value
                                    ? theme.colors.onSurface
                                    : theme.colors.onSurfaceVariant)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
      return SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(right: cardGapIn(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.isNotEmpty)
                SizedBox(
                  height: cardLabelHeightIn(context),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          color: theme.colors.onSurfaceVariant)),
                ),
              if (label.isNotEmpty) SizedBox(height: cardLabelGapIn(context)),
              bar,
            ],
          ),
        ),
      );
    }
    var bar = Container(
      height: card ? cardHeightIn(context) + 4 : controlHeight + 2,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(card ? 10 : 5),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Row(children: [
        for (var (option, words) in options)
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: keyOf == null ? null : ValueKey(keyOf!(option)),
                borderRadius: BorderRadius.circular(card ? 8 : 4),
                onTap: () => onChanged(option),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(card ? 8 : 4),
                    color:
                        option == value ? accent.withValues(alpha: 0.16) : null,
                    border: option == value ? Border.all(color: accent) : null,
                  ),
                  child: iconOf != null
                      ? Tooltip(
                          message: words,
                          child: Icon(iconOf!(option),
                              size: 16, color: theme.colors.onSurface))
                      : Text(words,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: card ? 12 : 11,
                              fontWeight: option == value
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: theme.colors.onSurface)),
                ),
              ),
            ),
          ),
      ]),
    );
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(right: card ? 10 : canvasControlGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                    bottom: card ? cardLabelGapIn(context) : controlLabelGap),
                child: Text(label,
                    style: TextStyle(
                        fontSize: card ? 11.5 : 9,
                        color: theme.colors.onSurfaceVariant)),
              ),
            bar,
          ],
        ),
      ),
    );
  }
}

/// canvasCard is a card in a section: a [title] with a "?" holding [help]
/// beside it (either may be missing) over [body], on a ground of its own, so
/// a section reads as a stack of cards each saying what it is.
Widget canvasCard(BuildContext context,
    {Widget? title, String help = "", required Widget body}) {
  var theme = ThemeNotifier.of(context);
  var heading = title != null || help.isNotEmpty;
  // In a dense panel, a group is its name in small capitals over its
  // controls, with no ground of its own.
  if (CanvasDense.on(context)) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: title ?? const SizedBox.shrink()),
                if (help.isNotEmpty) CanvasHint(help),
              ]),
            ),
          body,
        ],
      ),
    );
  }
  // A card inside a card -- a group in a folding part of a section -- is
  // a block with its name over it, not a ground on a ground.
  if (context.dependOnInheritedWidgetOfExactType<_InCard>() != null) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 10),
              child: Row(children: [
                Expanded(child: title ?? const SizedBox.shrink()),
                if (help.isNotEmpty) CanvasHint(help, round: true),
              ]),
            ),
          body,
        ],
      ),
    );
  }
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.45),
      border:
          Border.all(color: theme.colors.outlineVariant.withValues(alpha: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heading)
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 12),
            child: Row(children: [
              Expanded(child: title ?? const SizedBox.shrink()),
              if (help.isNotEmpty) CanvasHint(help, round: true),
            ]),
          ),
        _InCard(child: body),
      ],
    ),
  );
}

/// _InCard marks what is inside a card, so a card in it draws as a block.
class _InCard extends InheritedWidget {
  const _InCard({required super.child});

  @override
  bool updateShouldNotify(_InCard old) => false;
}

/// canvasCardTitle is a card's name, as text.
Widget canvasCardTitle(BuildContext context, String text) => Text(text,
    style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: ThemeNotifier.of(context).colors.onSurface));

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

/// CanvasMoreGroup is a group of settings with the rest behind a button at
/// the end of its first line: what changes often is in view, what is set
/// once is one press away. The open state is remembered under [remember]
/// for the run, so a panel rebuilt on every change does not shut it.
class CanvasMoreGroup extends StatefulWidget {
  final String label;
  final bool hideCaption;

  /// rule is the line under the group; see CanvasControlGroup.rule.
  final bool rule;

  /// remember names where the open state is kept; null keeps it only while
  /// the widget is in the tree.
  final String? remember;

  /// row is always shown and more is what the button reveals. The button
  /// ends the row, so [row] should leave space for it.
  final List<Widget> row;
  final List<Widget> more;

  /// tooltip says what is behind the button.
  final String tooltip;

  /// onRename: see CanvasControlGroup.onRename.
  final ValueChanged<String>? onRename;

  const CanvasMoreGroup({
    required this.label,
    required this.row,
    required this.more,
    this.tooltip = "More settings",
    this.hideCaption = false,
    this.rule = true,
    this.remember,
    this.onRename,
    super.key,
  });

  @override
  State<CanvasMoreGroup> createState() => _CanvasMoreGroupState();
}

class _CanvasMoreGroupState extends State<CanvasMoreGroup> {
  static final Map<String, bool> _remembered = {};

  late bool _open = _remembered[widget.remember] ?? false;

  void _toggle() {
    setState(() => _open = !_open);
    var key = widget.remember;
    if (key != null) _remembered[key] = _open;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // In a card, everything at once: the section it is in already folds.
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return CanvasControlGroup(
        label: widget.label,
        hideCaption: widget.hideCaption,
        rule: widget.rule,
        onRename: widget.onRename,
        children: [
          ...widget.row,
          if (widget.more.isNotEmpty) const CanvasLineBreak(),
          ...widget.more,
        ],
      );
    }
    return CanvasControlGroup(
      label: widget.label,
      hideCaption: widget.hideCaption,
      rule: widget.rule,
      onRename: widget.onRename,
      // What the button opened, on a tinted ground that shows where it
      // starts and stops. It is laid out apart, so opening it cannot narrow
      // the button's own row.
      below: !_open
          ? null
          : Padding(
              key: const ValueKey("more-ground"),
              padding: const EdgeInsets.only(top: canvasRowGap),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(canvasMoreInset,
                    canvasMoreInset, canvasMoreInset - 3, canvasMoreInset),
                decoration: BoxDecoration(
                  // A boxed section's ground, a little stronger.
                  color: theme.colors.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: Border.all(
                      color:
                          theme.colors.outlineVariant.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child:
                    CanvasWrap(runSpacing: canvasRowGap, children: widget.more),
              ),
            ),
      children: [
        ...widget.row,
        if (widget.more.isNotEmpty)
          CanvasIconButton(
            key: ValueKey("more-${widget.remember ?? widget.label}"),
            icon: _open ? Icons.expand_less : Icons.tune,
            tooltip: _open ? "Hide these settings" : widget.tooltip,
            active: _open,
            onPressed: _toggle,
          ),
      ],
    );
  }
}

/// _RenamableCaption is a group's caption renamed by double-clicking, never
/// a single click, since these captions sit above controls people aim at.
class _RenamableCaption extends StatefulWidget {
  final String label;
  final TextStyle style;
  final ValueChanged<String> onRename;

  const _RenamableCaption(
      {required this.label, required this.style, required this.onRename});

  @override
  State<_RenamableCaption> createState() => _RenamableCaptionState();
}

class _RenamableCaptionState extends State<_RenamableCaption> {
  bool _typing = false;
  late final TextEditingController _text =
      TextEditingController(text: widget.label);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _finish();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = widget.label;
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _typing = true);
    _focus.requestFocus();
  }

  void _finish() {
    if (!_typing) return;
    setState(() => _typing = false);
    widget.onRename(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (!_typing) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          onDoubleTap: _start,
          child: Tooltip(
            message: "Double-click to rename",
            waitDuration: CanvasNoHover.on(context)
                ? const Duration(days: 1)
                : const Duration(milliseconds: 700),
            child: Text(widget.label.toUpperCase(), style: widget.style),
          ),
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: controlLabelHeight + 6,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        style: TextStyle(fontSize: 10, color: theme.colors.onSurface),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        ),
        onSubmitted: (_) => _finish(),
        onTapOutside: (_) => _finish(),
      ),
    );
  }
}

/// canvasMoreInset is the padding inside an opened more-settings ground.
const double canvasMoreInset = 8;

/// CanvasGroupRule is the line between one group of settings and the next,
/// midway: the gap above it matches the gap below.
class CanvasGroupRule extends StatelessWidget {
  const CanvasGroupRule({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: canvasGroupGap),
        child: Container(
            height: 1,
            color: ThemeNotifier.of(context)
                .colors
                .outlineVariant
                .withValues(alpha: 0.45)),
      );
}

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
    var widest = 0.0;
    for (var (_, text, heading) in _rows()) {
      widest = math.max(widest, _widthOf(text, heading));
    }
    var extra = 40.0 + // the item's own padding and the scroll bar's room
        (leading != null ? 42 : 0) +
        (marked.isNotEmpty ? 56 : 0);
    return (widest + extra).clamp(width, math.max(width, 420.0));
  }

  /// _cardWidth is how wide a card's dropdown must be to show its longest
  /// name whole between its arrows, held to what a sidebar has room for.
  double _cardWidth() {
    var widest = 0.0;
    for (var (_, text, heading) in _rows()) {
      if (heading) continue;
      widest = math.max(widest, _widthOf(text, false));
    }
    // Two arrows and their dividers, and the room either side of the name.
    var chrome = 2 * 33 + 16 + 4 + (leading != null ? 42 : 0);
    return (widest + chrome).clamp(120.0, 320.0);
  }

  /// _widthOf is how wide [text] is set as an option (or, [heading], as a
  /// group's heading): measured once and remembered, since a settings panel
  /// is rebuilt often with the same names in it.
  static double _widthOf(String text, bool heading) {
    var key = heading ? "^$text" : text;
    var known = _widths[key];
    if (known != null) return known;
    var painter = TextPainter(
        text: TextSpan(
            text: heading ? text.toUpperCase() : text,
            style: TextStyle(
                fontSize: heading ? 10 : 12,
                letterSpacing: heading ? 0.8 : null)),
        textDirection: TextDirection.ltr,
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
        // The closed button shows the name alone, not a marked option's
        // background and cross. Always its own where options are tried:
        // built from the items, resting the pointer on the closed button
        // would start a preview nothing ends.
        selectedItemBuilder: marked.isEmpty &&
                leading == null &&
                groupOf == null &&
                onPreview == null
            ? null
            : (context) => [
                  for (var (v, text, heading) in _rows())
                    heading
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: marked.isEmpty
                                ? _named(v as T, text)
                                : Text(text, overflow: TextOverflow.ellipsis),
                          ),
                ],
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
          least, grow && _CanvasWrapScope.of(context) ? _cardWidth() : 120.0);
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
      Tooltip(
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
                  Tooltip(
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

/// CanvasChip is a named thing on a line, with a cross to take it off: the
/// shapes a document is laid out for, read at a glance as a row.
class CanvasChip extends StatelessWidget {
  final String label;

  /// here marks the one being looked at.
  final bool here;

  /// onRemove is null for a chip that cannot be taken off.
  final VoidCallback? onRemove;

  const CanvasChip(
      {required this.label, this.here = false, this.onRemove, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 4, bottom: 2),
      padding: const EdgeInsets.only(left: 8, right: 2, top: 3, bottom: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: here ? theme.colors.secondaryContainer : null,
        border: Border.all(
            color: here ? theme.colors.primary : theme.colors.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Shortened rather than overrunning a narrow card.
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ),
        if (onRemove case var remove?)
          Tooltip(
            message: "Stop laying out for $label",
            child: Material(
              // Its own Material: see CanvasControlGroup.
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: remove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close,
                      size: 12, color: theme.colors.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 6),
      ]),
    );
  }
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

  /// _row is the switch in a card: the words, and a switch at the far end
  /// of a line of its own.
  Widget _row(BuildContext context, ThemeNotifier theme) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(!value),
              child: SizedBox(
                height: CanvasDense.on(context) ? 30 : 36,
                child: Row(children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: CanvasDense.on(context) ? 13 : 12,
                            color: theme.colors.onSurface)),
                  ),
                  _Switch(on: value, theme: theme),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      return _row(context, theme);
    }
    return Padding(
      // The nudge: see CanvasIconButton.
      padding: EdgeInsets.only(right: canvasControlGap, top: nudgeIn(context)),
      child: Material(
        // Its own Material: see CanvasControlGroup.
        type: MaterialType.transparency,
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
            // No check box: the fill says it, and the room saved lets five
            // switches fit a narrow sidebar's line. A long label (one
            // carrying a channel's name) is shortened.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: value
                            ? theme.colors.onSecondaryContainer
                            : theme.colors.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// _Switch is a card's switch: an accent-filled track and a sliding knob.
class _Switch extends StatelessWidget {
  final bool on;
  final ThemeNotifier theme;
  const _Switch({required this.on, required this.theme});

  @override
  Widget build(BuildContext context) {
    var dense = CanvasDense.on(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: dense ? 34 : 40,
      height: dense ? 20 : 24,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: on
            ? theme.colors.primary
            : theme.colors.outlineVariant.withValues(alpha: 0.9),
      ),
      child: Container(
        width: dense ? 14 : 18,
        height: dense ? 14 : 18,
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    );
  }
}

/// CanvasSwitch is the switch a toggle row ends in, alone: for a row laid
/// out by hand (a look's, see LooksGroup).
class CanvasSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const CanvasSwitch({required this.value, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _Switch(on: value, theme: ThemeNotifier.of(context)),
          ),
        ),
      );
}

/// CanvasReadout is a caption over something the panel can only report
/// (which document a text element is reading), where a disabled field would
/// invite typing.
class CanvasReadout extends StatelessWidget {
  final String label;
  final String value;
  final double width;

  const CanvasReadout(
      {required this.label, required this.value, this.width = 168, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      SizedBox(
        width: width,
        height: heightIn(context),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.colors.onSurface),
          ),
        ),
      ),
    );
  }
}

/// CanvasIconButton is a small square action among the fields: shuffle a
/// seed, delete a keyframe, bring to front.
class CanvasIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  /// tight drops the room left above it for its neighbours' captions, as on
  /// a section's heading.
  final bool tight;

  const CanvasIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.tight = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var enabled = onPressed != null;
    return Padding(
      // The nudge (a caption and its gap) lines a control with no caption up
      // with captioned ones. On the band captions sit beside, so no nudge.
      padding: EdgeInsets.only(
          right: CanvasCards.on(context) ? 8 : canvasControlGap,
          top: tight ? 0 : nudgeIn(context)),
      child: _maybeTooltip(
        tooltip,
        Material(
          // Its own Material: see CanvasControlGroup.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onPressed,
            child: Container(
              width: tight ? controlHeight : heightIn(context),
              height: tight ? controlHeight : heightIn(context),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(CanvasCards.on(context) ? 8 : 4),
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
      ),
    );
  }
}

/// _maybeTooltip is [child] with [message] as hover text, if not empty.
Widget _maybeTooltip(String message, Widget child) =>
    message.isEmpty ? child : Tooltip(message: message, child: child);

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
        child: label.isEmpty ? child : Tooltip(message: label, child: child),
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

/// CanvasExpander is a heading that opens to reveal a long list (a team's
/// squad, say). Not ExpansionTile, whose height, dividers and animation are
/// a Material list's.
class CanvasExpander extends StatefulWidget {
  final String label;

  /// trailing is shown beside the label (a count, usually), ellipsised
  /// rather than widening the heading.
  final String? trailing;

  /// action is a button on the right of the heading, working whether the
  /// section is open or shut (refreshing a table's data, say).
  final Widget? action;

  final List<Widget> children;

  final bool initiallyOpen;

  /// remember names where this section's open state is kept (see
  /// _rememberedSections), or null to start closed every time.
  final String? remember;

  /// flat draws only the children, always open, for a section already
  /// inside one of its own.
  final bool flat;

  const CanvasExpander({
    required this.label,
    required this.children,
    this.trailing,
    this.action,
    this.initiallyOpen = false,
    this.remember,
    this.flat = false,
    super.key,
  });

  @override
  State<CanvasExpander> createState() => _CanvasExpanderState();
}

/// _rememberedSections is every named section's open state for this run,
/// shared by [CanvasExpander] and [CanvasFoldingGroup]. In memory as well as
/// on disk, because a panel is rebuilt on every selection change and a fresh
/// State reading the disk asynchronously would show the section shut first.
final Map<String, bool> _rememberedSections = {};

void forgetSectionsForTest() {
  _rememberedSections.clear();
  _CanvasMoreGroupState._remembered.clear();
}

/// _restoreSection loads a section's saved state and tells [then].
Future<void> _restoreSection(String key, ValueChanged<bool> then) async {
  var saved = await StorageManager.readData("canvasSection.$key");
  if (saved is! bool) return;
  _rememberedSections[key] = saved;
  then(saved);
}

void _keepSection(String? key, bool open) {
  if (key == null) return;
  _rememberedSections[key] = open;
  StorageManager.saveData("canvasSection.$key", open);
}

/// rememberedSection, restoreSection and keepSection share this memory with
/// panel_kit.dart's sections.
bool? rememberedSection(String key) => _rememberedSections[key];
Future<void> restoreSection(String key, ValueChanged<bool> then) =>
    _restoreSection(key, then);
void keepSection(String? key, bool open) => _keepSection(key, open);

class _CanvasExpanderState extends State<CanvasExpander> {
  late bool _open =
      _rememberedSections[widget.remember] ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    var key = widget.remember;
    if (key != null && !_rememberedSections.containsKey(key)) {
      _restoreSection(key, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    _keepSection(widget.remember, _open);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (widget.flat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: widget.children,
      );
    }
    // In a section, a card that folds when its name is pressed.
    if (CanvasCards.on(context) && !CanvasControlScope.isInline(context)) {
      var muted = theme.colors.onSurfaceVariant;
      return canvasCard(context,
          title: Row(children: [
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: widget.remember == null
                      ? null
                      : ValueKey("expander-${widget.remember}"),
                  borderRadius: BorderRadius.circular(6),
                  onTap: _toggle,
                  child: Row(children: [
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(Icons.chevron_right, size: 18, color: muted),
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: canvasCardTitle(context, widget.label)),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(widget.trailing!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: muted)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            if (widget.action != null) widget.action!,
          ]),
          body: !_open
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Down the sidebar the action sits at the right edge with the summary
        // taking what is left. On the band, a horizontal scroller with
        // unbounded width, an Expanded asserts, so the heading shrink-wraps.
        LayoutBuilder(builder: (context, constraints) {
          var fills = constraints.maxWidth.isFinite;
          Widget heading = Material(
            // Its own Material: see CanvasControlGroup.
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_open ? Icons.expand_more : Icons.chevron_right,
                      size: 16, color: theme.colors.onSurfaceVariant),
                  const SizedBox(width: 3),
                  // Both name and summary clip: a Text that cannot shrink
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
                        color: theme.colors.onSurfaceVariant
                            .withValues(alpha: 0.7),
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
            ),
          );

          return Row(
            mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
            children: [
              fills ? Expanded(child: heading) : Flexible(child: heading),
              // Outside the InkWell, so pressing it does not fold the section.
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

/// CanvasKeyframeDot is the diamond beside an animatable setting: lit where
/// a keyframe sits on the current frame, pressed to add or remove one. What
/// the keyframe holds is the caller's (see valueDot in settings_shared.dart).
class CanvasKeyframeDot extends StatelessWidget {
  final bool on;

  /// enabled is false for a still document: a keyframe has nothing to
  /// interpolate towards.
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
      // The nudge: see CanvasIconButton.
      padding: EdgeInsets.only(right: canvasControlGap, top: nudgeIn(context)),
      child: Tooltip(
        message: tooltip,
        child: Material(
          // Its own Material: see CanvasControlGroup.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: 18,
              height: heightIn(context),
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
      ),
    );
  }
}

/// CanvasGridCell is a text field with no caption, for chart and table
/// cells: a grid of CanvasTextFields would be a grid of captions.
class CanvasGridCell extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final bool multiline;
  final bool dense;
  final String hint;

  /// suggestions are names the source knows, offered while typing (see
  /// DataPreset.rowNames). They narrow what is shown and refuse nothing.
  final List<String> suggestions;

  const CanvasGridCell({
    required this.value,
    required this.onChanged,
    required this.onCommit,
    this.multiline = false,
    this.dense = false,
    this.hint = "",
    this.suggestions = const [],
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
    // Not while typed in: rewriting the text under the cursor eats a
    // keystroke and moves the caret to the end.
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
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return _field(context);
    var theme = ThemeNotifier.of(context);
    // RawAutocomplete, so the cell keeps its own controller and focus node,
    // which stop it rewriting itself under the cursor and commit on blur.
    return RawAutocomplete<String>(
      textEditingController: _text,
      focusNode: _focus,
      optionsBuilder: (value) {
        var typed = value.text.trim().toLowerCase();
        if (typed.isEmpty) return const Iterable<String>.empty();
        // What is being typed, wherever it appears in the name: "cash" finds
        // Bitcoin Cash. An exact match offers nothing.
        var found = [
          for (var name in widget.suggestions)
            if (name.toLowerCase().contains(typed)) name,
        ];
        if (found.length == 1 && found.first.toLowerCase() == typed) {
          return const Iterable<String>.empty();
        }
        return found.take(8);
      },
      onSelected: (name) {
        widget.onChanged(name);
        widget.onCommit();
      },
      fieldViewBuilder: (context, controller, focus, submit) => _field(context),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          color: theme.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180, maxWidth: 220),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (var name in options)
                  InkWell(
                    onTap: () => select(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 11, color: theme.colors.onSurface)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        expands: widget.multiline,
        maxLines: widget.multiline ? null : 1,
        minLines: null,
        style: TextStyle(fontSize: widget.dense ? 11 : 12),
        // Centred on one line, top on several: a single top-aligned line
        // sits high beside the dropdown in a series row.
        textAlignVertical:
            widget.multiline ? TextAlignVertical.top : TextAlignVertical.center,
        decoration: canvasFieldDecoration(ThemeNotifier.of(context),
            hint: widget.hint, fontSize: widget.dense ? 11 : 12),
        onChanged: widget.onChanged,
      );
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

/// CanvasFoldingGroup is a [CanvasControlGroup] that can be shut by a
/// chevron on its caption. [remember] names where that is kept, so it lasts
/// across a rebuild and a restart (see _rememberedSections).
class CanvasFoldingGroup extends StatefulWidget {
  final String label;
  final List<Widget> children;

  final String remember;

  /// startShut is whether an untouched group starts shut.
  final bool startShut;

  final bool rule;
  final Widget? below;

  const CanvasFoldingGroup({
    required this.label,
    required this.children,
    required this.remember,
    this.startShut = false,
    this.rule = true,
    this.below,
    super.key,
  });

  @override
  State<CanvasFoldingGroup> createState() => _CanvasFoldingGroupState();
}

class _CanvasFoldingGroupState extends State<CanvasFoldingGroup> {
  late bool _shut =
      !(_rememberedSections[widget.remember] ?? !widget.startShut);

  @override
  void initState() {
    super.initState();
    if (!_rememberedSections.containsKey(widget.remember)) {
      _restoreSection(widget.remember, (open) {
        if (mounted) setState(() => _shut = !open);
      });
    }
  }

  void _toggle() {
    setState(() => _shut = !_shut);
    _keepSection(widget.remember, !_shut);
  }

  @override
  Widget build(BuildContext context) => CanvasControlGroup(
        label: widget.label,
        rule: widget.rule,
        below: widget.below,
        folded: _shut,
        onFold: _toggle,
        children: widget.children,
      );
}
