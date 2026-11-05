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

// controls.dart is the small set of controls the canvas settings are built
// out of: each one labelled thing of a fixed height, so a panel of many
// properties (a chart alone has twenty) stays readable.
//
// Every one reports continuously while it is being changed, and callers pass
// those through as transient edits (see CanvasController.beginInteraction):
// a drag shows the result as it moves, and is still one undo step when it
// stops.

/// controlHeight is what every control stands at: as short as a comfortable
/// click target allows.
const double controlHeight = 27;

/// controlLabelGap is the air between a control's caption and the control,
/// so the caption does not read as part of the box.
const double controlLabelGap = 3;

/// controlLabelHeight is the little caption above each control. Everything
/// with no caption (a toggle, an icon button) is pushed down by exactly
/// this much so the whole row sits on one baseline.
const double controlLabelHeight = 11;

/// The gaps the settings panel is spaced with, one scale for all of it.
///
/// canvasControlGap is between two controls on a line, canvasRowGap between
/// one line of a group and the next, canvasCaptionGap under a group's name,
/// and canvasGroupGap under every group. A rule between two groups sits in
/// the middle of a doubled one. The group gap is three times the row gap:
/// with few rules left, the gap is what says where one group ends.
///
/// canvasCaptionedGap is the control gap after a control with a caption over
/// it: wider, because the captions touch ("Fill", "Colour" and "Border" over
/// three swatches would read as one word). Bordered buttons and toggles keep
/// the plain gap, which the fixed-width rows of buttons over a data grid are
/// built on.
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
/// controlLabelHeight and controlLabelGap inside a card; cardCaptioned is
/// what a captioned control stands at there, all in.
const double cardControlHeight = 38;
const double cardLabelHeight = 15;
const double cardLabelGap = 6;
const double cardCaptioned = cardLabelHeight + cardLabelGap + cardControlHeight;

/// cardGap is the room between two controls on a line in a card, and between
/// two lines.
const double cardGap = 12;

/// heightIn is how tall a control stands where [context] is.
double heightIn(BuildContext context) =>
    CanvasCards.on(context) ? cardControlHeight : controlHeight;

/// nudgeIn is how far down a control with no caption sits, to line up with
/// the captioned ones beside it.
double nudgeIn(BuildContext context) => CanvasControlScope.isInline(context)
    ? 0
    : CanvasCards.on(context)
        ? cardCaptioned - cardControlHeight
        : controlWithLabelHeight - controlHeight;

/// controlWithLabelHeight is what a captioned control stands at, all in.
const double controlWithLabelHeight =
    controlLabelHeight + controlLabelGap + controlHeight;

/// CanvasControlScope says how the controls below it lay themselves out: a
/// group in a row on the band, or stacked down a sidebar with no width to
/// scroll. A group asks the scope which it is in, and every control that
/// sizes itself clamps to what the scope allows.
class CanvasControlScope extends InheritedWidget {
  /// maxWidth is the widest a single control may be: in a sidebar it stops a
  /// control sized past its parent (the chart's data box asks for 260) from
  /// overflowing.
  final double maxWidth;

  /// inline puts a control's caption beside it rather than above it: for the
  /// strip over the canvas, where a line of captions would push the canvas
  /// down. Down a sidebar the captions belong above.
  final bool inline;

  /// hoverCaptions puts a control's caption in its hover text rather than on
  /// the screen: for the timeline's play bar, whose controls are known by what
  /// is in them.
  final bool hoverCaptions;

  const CanvasControlScope({
    required this.maxWidth,
    this.inline = false,
    this.hoverCaptions = false,
    required super.child,
    super.key,
  });

  /// isInline is whether captions go beside their controls here, or nowhere on
  /// screen, in hover text, which lines up the same way.
  static bool isInline(BuildContext context) {
    var scope = maybeOf(context);
    return (scope?.inline ?? false) || (scope?.hoverCaptions ?? false);
  }

  /// hovers is whether captions are hover text here. See hoverCaptions.
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

/// CanvasLineBreak starts a new line inside a group: a child as wide as a
/// line and no height, which is how a Wrap is told where a line ends, so the
/// break does not depend on the sidebar's width.
///
/// [gap] puts air between the two lines, for a break between two different
/// questions. A break with a height is a line of its own, so the air is that
/// height plus a run either side; a few pixels is enough.
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

/// The "?" opens on a click, never on a hover, so passing over it does not
/// put a paragraph over the control beside it. A click anywhere else, or on
/// the "?" again, shuts it.
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

  /// _bubbleOf is the open "?": what it says, under it, and a click anywhere
  /// else shutting it. The theme is read here, as it is drawn: the click that
  /// opened it is outside the tree.
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

/// CanvasStatus is a line of words a panel says back (what a button just
/// did, or what stopped it) on its own line where it can be read. Not a
/// CanvasHint, which is help behind a click: "12 cues found" belongs in
/// view.
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

/// _GrowRoot is a growable control's outermost box. Asked loosely it answers
/// with the least it will take (its control's width or its caption's,
/// whichever is wider), which CanvasWrap packs the lines from; asked tightly
/// it takes what it is given. Either way it passes a tight width down, so
/// the [_Stretch] inside has a width to fill.
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

/// canvasSized is a control's own box: [min] wide and fixed, or as wide as
/// the line has room for, depending on where it has been put and whether it
/// asked to grow.
Widget canvasSized(
  BuildContext context, {
  required double min,
  required double height,
  required bool grow,
  required Widget child,
}) =>
    grow && _CanvasWrapScope.of(context)
        ? _Stretch(min: min, height: height, child: child)
        : SizedBox(width: min, height: height, child: child);

/// CanvasWrap is a Wrap whose marked children share out the room left over,
/// so a row of boxes grows into a sidebar of whatever width instead of
/// leaving a ragged margin.
///
/// The extra is a per-control amount, the same on every line, rather than
/// one width for all: a title field stays wider than a number field beside
/// it, and four number fields on one line and two on the next come out the
/// same width, so Angle sits under X. The amount is the smallest any line
/// can afford, so widening never pushes a control off its line.
///
/// Lines are [canvasRowGap] apart unless told otherwise.
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
          // Marked here rather than by each control: the mark is parent data and
          // has to sit between this and the control, and the scope with it then
          // covers the control alone, not the controls in a child's own Wrap.
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

/// CanvasBlockBreak ends a line and starts the sharing out again: what
/// follows is a different piece of panel. Without it, a button that reveals
/// a line could make its own row narrower, because the revealed line
/// affords less. [CanvasMoreGroup] puts one in front of what its button
/// reveals; a [CanvasLineBreak] does not, since the second line of a group
/// is still the same group.
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

/// _CanvasWrapScope says that a control is inside one of these. A control
/// only offers to grow where there is a line to grow into: anywhere else it
/// answers with the width it was given, or a seventy-pixel field could end
/// up four hundred wide.
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

    // What each child is when nothing is given to it. A marked child is asked
    // with no width at all, so it answers with the least it will take;
    // everything else within the line, since a line break is as wide as one.
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
    // it can afford, so the lines of a group keep the same columns.
    // A line started on purpose (the first, or one after a break or a
    // full-width control) with one control to grow on it fills the line and
    // is left out of the sharing: it has no columns to keep, and a dropdown
    // alone on its line would otherwise cut its words short. A line that only
    // exists because the one above ran out of room still shares, so a row of
    // numbers that wraps keeps its columns.
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

/// CanvasNoScrollbar is a scroll behaviour with no bar on it, for panels
/// scrolled with two fingers rather than by taking hold of anything. The
/// wheel, a trackpad and a dragged finger all still scroll.
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

  /// hideCaption drops the group's own name, for a group whose name is
  /// already said by whatever is above it (the panel's header naming the
  /// element).
  final bool hideCaption;

  /// captionGap is the room between the caption and the controls under it.
  /// The default suits a name; a caption that is a sentence needs more, or it
  /// runs into the first control's caption.
  final double captionGap;

  /// rule is the line under the group, dropped where the next group is a
  /// continuation rather than a new subject.
  final bool rule;

  /// onRename makes the caption a name that can be changed: double-click it
  /// and type, as a file, a scene and a layer are renamed. Null for captions
  /// that are headings.
  final ValueChanged<String>? onRename;

  /// below goes under the group's own line of controls, inside its gap and
  /// above its rule: for the settings a button on that line has opened (see
  /// CanvasMoreGroup), which are part of the group.
  final Widget? below;

  /// folded says this group can be shut, and whether it is; null for groups
  /// that are always open. Shut, the caption stays (it is what is pressed to
  /// get them back) and the controls go. See CanvasFoldingGroup, which
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

  /// _card is the group as a card in a section: its name, and a "?" holding
  /// what it is for, over its controls, on a ground of its own.
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
    var title = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: theme.colors.onSurface);
    Widget name = onRename != null
        ? _RenamableCaption(label: label, style: title, onRename: onRename!)
        : Text(label, style: title);
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
    // the name of the section it is in.
    var named = label.isNotEmpty &&
        (!hideCaption || about.isNotEmpty) &&
        label != CanvasCards.titleOf(context);
    return canvasCard(context,
        title: named ? name : null,
        help: about,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!shut) CanvasWrap(runSpacing: cardGap, children: rest),
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
    // A chevron in front of the words, and the whole caption is the
    // target.
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

    // Every "?" in the group goes up on to its heading row, on the right,
    // as one.
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
                // Spaced as well as run-spaced, so one group's last control does not
                // touch the next one's first. Centred, since a switch, a captioned box
                // and a readout are three heights on a strip that is one line.
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
      // The spacing every group gets, here rather than in each. Every group
      // leaves the same gap under it, and a rule sits in the middle of a
      // doubled one, so the line belongs to neither group.
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
          // No spacing between them: each control carries its own right-hand
          // padding.
          if (!shut) CanvasWrap(runSpacing: canvasRowGap, children: controls),
          if (below != null && !shut) below!,
          if (rule) const CanvasGroupRule(),
        ],
      ),
    );
  }
}

/// CanvasTextButton is a button that says what it does in words -- "Flip
/// across", "Clear mask" -- for an action somebody has to read to find,
/// rather than an icon they have to learn. It shares out the room on its
/// line with the buttons beside it.
class CanvasTextButton extends StatelessWidget implements CanvasGrowable {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// primary fills it with the accent: the one thing a card is for.
  final bool primary;

  @override
  final bool grow;

  /// least is wide enough for its words and icon, so a line of them wraps
  /// before any is cut short.
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
      padding: EdgeInsets.only(right: card ? cardGap : canvasControlGap),
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

/// CanvasSegmented is a choice of a few, all in view, the one chosen lit: a
/// line of its own, with an optional caption over it. For two to four
/// options short enough to read side by side -- more than that is a
/// dropdown's.
class CanvasSegmented<T> extends StatelessWidget {
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// keyOf names each option, for the tests.
  final String Function(T)? keyOf;

  const CanvasSegmented(
      {required this.options,
      required this.value,
      required this.onChanged,
      this.label = "",
      this.keyOf,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var card = CanvasCards.on(context);
    var accent = theme.colors.primary;
    var bar = Container(
      height: card ? cardControlHeight + 4 : controlHeight + 2,
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
                  child: Text(words,
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
                    bottom: card ? cardLabelGap : controlLabelGap),
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
/// beside it -- either may be missing -- over [body], on a ground of its own.
/// Groups, tiles and tools all sit in one, so a section reads as a stack of
/// cards each saying what it is.
Widget canvasCard(BuildContext context,
    {Widget? title, String help = "", required Widget body}) {
  var theme = ThemeNotifier.of(context);
  var heading = title != null || help.isNotEmpty;
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
/// keystroke that parses rather than on submit, so a typed width shows at
/// once.
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
  /// is the field's own last digit, right where the digits are the scale and
  /// wrong where a field is precise but wide (a ring width in ten-thousandths
  /// running to a fifth of the page).
  final double? step;

  final ValueChanged<double> onChanged;

  /// grow lets this take some of the room left over on its line; [width] is
  /// then the least it will be. See CanvasWrap.
  @override
  final bool grow;

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

  /// _hold runs while the number is being pressed, _scrubbing is true once it
  /// has been held long enough, and _from and _startX are where the drag
  /// began (see _ScrubLabel, which does the same arithmetic). Held rather
  /// than dragged, because a field's own drag selects text. Here as well as on
  /// the caption, because a field may have no caption over it (a chart's
  /// fourth series).
  ///
  /// Nothing in the hold reaches the panel (no unfocus, no commit): losing
  /// the focus commits, which rebuilds the panel and can take this field's
  /// state away in the middle of its own gesture.
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
    // The field is only rewritten from outside while it is not being typed
    // into, or the caret would jump to the end on every keystroke. Being
    // scrubbed counts as not being typed into: the press that starts a scrub
    // gives the field the focus.
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

  /// _arrowStep is how far an arrow moves this number, where it is drawn as
  /// a stepper: a fiftieth of a range that is a real range, rounded to the
  /// field's own precision, or a whole unit (a tenth, for a precise field)
  /// where the range is only a guard rail.
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
    // In a card every number is a stepper (an arrow either side of a number
    // dragged sideways), whoever asked for a field.
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
        // A word after a number, "2 years", wants a space; a sign, "40%",
        // does not.
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
          // Translucent, so a press in the room around the digits counts as a
          // press on the field.
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
              // Moved before it was held: that is the field's own drag, which selects
              // the number to retype. The allowance is generous: a hand holding still
              // drifts.
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
            // Left and right over the whole box, as over the caption: it says the
            // number can be dragged. On the field rather than a MouseRegion round
            // it, because a text field's own cursor is innermost and wins.
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

/// _scrubHoldDelay is how long a number has to be pressed before the press
/// becomes a drag on its value, and _scrubHoldSlop how far the pointer may
/// stray while it is being held.
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
///
/// The border is left to the app's own input theme. What is spelled out is
/// the room above and below the words, which decides how tall the field is
/// drawn: with no padding it is drawn shorter than its row and sits at the
/// top of it.
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
          height:
              widget.maxLines > 1 ? heightIn(context) * 2 : heightIn(context),
          grow: widget.grow,
          child: _bottomInCard(
            context,
            TextField(
              controller: _text,
              focusNode: _focus,
              maxLines: widget.maxLines,
              style: const TextStyle(fontSize: 12),
              decoration: canvasFieldDecoration(ThemeNotifier.of(context),
                  hint: widget.hint),
              onChanged: widget.onChanged,
            ),
          ),
        ),
      );

  /// _bottomInCard sits a field's underline on the foot of its box in a card,
  /// where a button's or a stepper's box ends, so a button beside it does not
  /// hang below the line.
  Widget _bottomInCard(BuildContext context, Widget field) =>
      CanvasCards.on(context) && widget.maxLines == 1
          ? Align(alignment: Alignment.bottomLeft, child: field)
          : field;
}

/// CanvasMoreGroup is a group of settings with the rest of them behind a
/// button on the end of its first line: what is changed often is in view,
/// what is set once is one press away.
///
/// The open state is remembered under [remember] for the run, like a
/// section's, so a panel rebuilt on every change to the element does not
/// shut what somebody has just opened.
class CanvasMoreGroup extends StatefulWidget {
  final String label;
  final bool hideCaption;

  /// rule is the line under the group; see CanvasControlGroup.rule.
  final bool rule;

  /// remember names where the open state is kept. Null keeps it only as long
  /// as the widget is in the tree, which in a settings panel is not long.
  final String? remember;

  /// row is what is always shown, and more is what the button reveals. The
  /// button is drawn at the end of the row, so [row] should leave space for
  /// it.
  final List<Widget> row;
  final List<Widget> more;

  /// tooltip says what is behind the button.
  final String tooltip;

  /// onRename makes the caption a name that can be typed into. See
  /// CanvasControlGroup.onRename.
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
      // What the button opened, on a ground of its own: a tint says where
      // the revealed settings start and stop while the eye is still on the
      // button. It is a line of layout of its own, so opening it cannot narrow
      // the row the button sits on.
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
                  // The ground a boxed section is drawn on, a little stronger, to be read
                  // from the corner of the eye.
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

/// _RenamableCaption is a group's caption that can be typed into:
/// double-click and type, as a file, a scene and a layer are renamed. Not on
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
            waitDuration: const Duration(milliseconds: 700),
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

/// canvasMoreInset is the room inside the ground an opened more-settings area
/// is drawn on.
const double canvasMoreInset = 8;

/// CanvasGroupRule is the line between one group of settings and the next,
/// midway between the two: the gap above it is the gap the group under it
/// keeps below.
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
  /// stepped puts an arrow either side to step through the options, as a
  /// dropdown in a card has, wherever it is (in a floating bar, say).
  final bool stepped;

  final ValueChanged<T> onChanged;

  /// onPreview is told of each option the pointer passes over while the list
  /// is open, and of null when it closes, so a choice can be seen on the
  /// canvas before it is made. Null for a list nothing is tried from.
  final ValueChanged<T?>? onPreview;

  /// enabled is whether it answers at all. Greyed rather than hidden where
  /// being seen is the only way anybody learns it exists.
  final bool enabled;

  /// tight holds the caption to the width of the box under it, for controls
  /// sized to the room there is rather than to what they hold. Off by
  /// default: a cut-off caption is worse than a wider row.
  final bool tight;

  /// marked are the options drawn as already in use, with a background
  /// behind them: for a list that is both a choice and a set (the shapes a
  /// document is laid out for, chosen from the list of shapes).
  final Set<T> marked;

  /// onRemove puts a cross on each marked option. Null leaves the marks as
  /// marks.
  final void Function(T)? onRemove;

  /// removeTip is what that cross says it will do.
  final String Function(T)? removeTip;

  /// leading draws something before each option's name, in the list and in
  /// the closed box (an easing's curve, say). Null draws nothing.
  final Widget Function(T)? leading;

  /// groupOf puts a heading in the list above each run of options it gives
  /// the same answer for. Null lists them without headings.
  final String Function(T)? groupOf;

  /// grow lets this take some of the room left over on its line; [width] is
  /// then the least it will be. See CanvasWrap.
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

  /// _rows is the options in the order the list shows them, with a heading
  /// (null in the first place) before each group.
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

  /// _menuWidth is how wide the open list needs to be to show every name in
  /// full (its picture beside it, where it has one, and a marked option's
  /// buttons), never narrower than [width], nor wider than a sidebar.
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

  /// _cardWidth is how wide a card's dropdown needs to be to show its longest
  /// name whole between its two arrows (its picture beside it, where it has
  /// one), held to what a sidebar has room for.
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
  /// is built over and over with the same fifty palette names in it.
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

  /// _named is an option's name, with its leading drawing where it has one.
  Widget _named(T v, String text) {
    var name = Text(text, overflow: TextOverflow.ellipsis);
    var lead = leading;
    if (lead == null) return name;
    // Too narrow for a picture and a name (a style in a forty-pixel slot),
    // it is the picture alone, shrunk to fit. The dropdown is always laid
    // out at a width it is given.
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

  /// _step is the option [by] from the one chosen (the arrows either side of
  /// a dropdown in a card), or null at either end.
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
    // A bare DropdownButton rather than a DropdownButtonFormField, which
    // keeps its own copy of the value: here the value changes from outside
    // (another element selected, an undo) all the time.
    //
    // Its own Material, because ink (the splash, and a focused control's
    // highlight) is painted by the nearest Material ancestor, in its
    // coordinates: with the sidebar's, the highlight was left floating where
    // the dropdown had been as the settings scrolled.
    var list = Material(
      type: MaterialType.transparency,
      // And no highlight once the menu has closed: a box that stays lit
      // after a choice reads as something still open.
      child: DropdownButton<T>(
        focusColor: Colors.transparent,
        value: options.any((o) => o.$1 == value) ? value : null,
        isDense: true,
        isExpanded: true,
        // The open list as wide as its longest name, so no name is cut short
        // while it is being chosen.
        menuWidth: _menuWidth(context),
        underline: const SizedBox.shrink(),
        style: TextStyle(fontSize: 12, color: theme.colors.onSurface),
        iconSize: card ? 0 : 16,
        icon: card ? const SizedBox.shrink() : null,
        // The closed button shows the name and nothing else, not a marked
        // option's background and cross. Always its own where options are
        // tried: built from the items, resting the pointer on the closed button
        // would start a preview nothing ended.
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
                // Null is a real answer where the type says it is one: a dropdown of
                // "None, Fade, Slide" has null first.
                if (v == null && null is! T) return;
                onChanged(v as T);
              }
            : null,
      ),
    );
    // In a card an arrow either side steps through the options and the
    // middle opens the whole list.
    var box = card
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
    // In a card, never narrower than its two arrows and a word between
    // them.
    var least = CanvasControlScope.widthFor(context, width);
    // Nor narrower than its longest name between the arrows, so a line too
    // short for it wraps rather than cutting the name. Only in a wrap,
    // which can give it a line of its own; in a fixed row it keeps the
    // width it was given.
    if (card) {
      least = math.max(
          least, grow && _CanvasWrapScope.of(context) ? _cardWidth() : 120.0);
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
/// pointer comes onto it and, as the list closes, that nothing is being
/// tried any more.
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
    // After the frame: the list is being taken down, and whatever the
    // preview changes rebuilds the panel it was opened from. Every option
    // says it; saying it twice changes nothing.
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

/// CanvasSlider is a value with a range, drawn as a number to type or scrub
/// like the rest; kept as a name for the places that ask for one.
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

  /// Drawn as a number field: typed, or scrubbed by dragging across the
  /// number or its caption, as every other number in the settings is.
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

/// CanvasColorButton is a swatch that opens a picker. Not a dropdown of
/// palette slots as in the theme editor: a canvas's colours are a picture's,
/// not the app theme's. It borrows the theme editor's picker.
class CanvasColorButton extends StatefulWidget {
  final String label;
  final Color color;
  final bool allowAlpha;
  final ValueChanged<Color> onChanged;

  /// gradient is the second colour, for the things that can be painted with
  /// two. Set [onGradientChanged] to offer the picker's Gradient tab; null
  /// leaves a plain swatch. The gradient is set in the picker, not with
  /// controls beside every colour.
  final GradientSpec? gradient;
  final ValueChanged<GradientSpec?>? onGradientChanged;

  /// labelWidth holds the caption to the swatch's own width, for rows where a
  /// swatch has to fit in a known amount of room: a Column is as wide as its
  /// widest child, so "Colour" over a thirty-pixel swatch is a fifty-pixel
  /// column.
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
  /// _pick opens the picker and writes back whatever it answers with.
  ///
  /// Where both the colour and the fade have moved, the second write is left
  /// until the next frame: the panel's controls are built from the element as
  /// it was last laid out, so two writes in one frame would both build on the
  /// same stale copy and the second would undo the first. After the frame
  /// `widget` is the rebuilt one, closed over what the first write left.
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
            child: Container(
              width: 30,
              height: heightIn(context),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.colors.outlineVariant),
                // The checker tells a transparent colour from black on a dark
                // background.
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

  /// gradient is drawn in the swatch itself, so a colour that fades looks
  /// like one without having to be opened.
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
  /// _markedOption is an option that is already in use: a background behind
  /// it, and a cross where it can be given up.
  Widget _markedOption(ThemeNotifier theme, T value, String text) => Builder(
        // Across the whole row rather than a pill round the words: what is
        // marked is the row. A menu item is laid out inside the menu's side
        // padding (the framework's private _kMenuItemPadding, 16 a side), so
        // the background is drawn wider than its slot and let to overflow.
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
                      // The menu is closed by hand: the cross is inside the row, so the row's
                      // own tap never runs and the menu would stay open over a changed list.
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

/// CanvasChip is a named thing on a line, with a cross to take it off: for
/// the shapes a document is being laid out for, read at a glance as a row.
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
  /// of a line of its own -- a setting read as a sentence that is on or off.
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
                height: 36,
                child: Row(children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: theme.colors.onSurface)),
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
            // No check box beside the word: the fill already says it, and the room
            // is what lets five switches fit a narrow sidebar's line. A label longer
            // than the room (one carrying a channel's name) is shortened.
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

/// _Switch is a card's switch: a track that fills with the accent, and a
/// knob that slides to the end it is on.
class _Switch extends StatelessWidget {
  final bool on;
  final ThemeNotifier theme;
  const _Switch({required this.on, required this.theme});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 24,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: on
              ? theme.colors.primary
              : theme.colors.outlineVariant.withValues(alpha: 0.9),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      );
}

/// CanvasReadout is a caption over something the panel can only tell you:
/// which document a text element is reading, what a chain of boxes flows
/// into. A disabled field would invite typing.
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

/// CanvasIconButton is a small square action, for the buttons that sit between
/// the fields -- shuffle a seed, delete a keyframe, bring to front.
class CanvasIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  /// tight drops the room this button leaves above itself for the caption its
  /// neighbours have: right in a row of captioned controls, wrong on a
  /// section's heading.
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
      // The nudge (the caption and the gap under it) lines a control with no
      // caption up with the ones that have them. On the band the captions are
      // beside their controls and there is nothing above to line up under.
      padding: EdgeInsets.only(
          right: CanvasCards.on(context) ? 8 : canvasControlGap,
          top: tight ? 0 : nudgeIn(context)),
      // No hover text where there is nothing to say.
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

/// _maybeTooltip is [child] with [message] as its hover text, or with none
/// where the message is empty.
Widget _maybeTooltip(String message, Widget child) =>
    message.isEmpty ? child : Tooltip(message: message, child: child);

/// _ScrubLabel is a caption you can drag sideways to change the number under
/// it. The caption rather than the field, which owns its own drag (that is
/// how text is selected), so typing an exact number keeps working.
///
/// One pixel of travel moves the number by one of its own last digits: a
/// whole unit on a field of whole numbers, a tenth on one of tenths. Not by
/// a share of the range, since most ranges are guard rails, not scales.
/// Shift makes it ten times finer.
class _ScrubLabel extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;

  /// decimals is how precise the field is, and so what one step means unless
  /// [step] says otherwise.
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
  /// _from is the value the drag started at, so the whole gesture is measured
  /// from one place: summing small deltas drifts, and rounding them makes a
  /// slow drag move less than a fast one.
  double _from = 0;

  /// _startX is where the pointer went down, in screen coordinates: what
  /// arrives is the pointer's position, not how far it has travelled.
  double _startX = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);

    var step = widget.step ?? math.pow(10, -widget.decimals).toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      // A Listener rather than a GestureDetector, so the number moves from the
      // first pixel: a drag is only recognised after about eighteen pixels,
      // which are then lost. Nothing else competes for these pointers.
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

/// _labelled puts a caption above a control. [scrub] makes that caption a
/// handle: dragging it sideways runs the number up and down. See
/// _ScrubLabel.
Widget _labelled(ThemeNotifier theme, String label, Widget child,
    {Widget? scrub, double? cap}) {
  return Builder(builder: (context) {
    // In hover text, and nothing on screen but the control.
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
              // Capped, so a long caption cannot push the control off the end of a
              // strip that is already scrolling sideways.
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

    // In a card: a larger caption, further from a larger control, and more
    // room before the next.
    if (CanvasCards.on(context)) {
      return Padding(
        padding: const EdgeInsets.only(right: cardGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // As wide as its words, not held to its control's: in a card there is
            // the room.
            SizedBox(
                height: cardLabelHeight,
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        color: theme.colors.onSurfaceVariant))),
            const SizedBox(height: cardLabelGap),
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
            // Held to the width of the control it names, where the caller has asked
            // for that: a Column is as wide as its widest child, so a long caption
            // would decide the control's width.
            SizedBox(height: controlLabelHeight, width: cap, child: caption),
          const SizedBox(height: controlLabelGap),
          child,
        ],
      ),
    );
  });
}

/// CanvasExpander is a heading that opens to reveal a list. Not
/// ExpansionTile, whose tile height, dividers and animation are a Material
/// list's. For long lists such as a football team's squad (eleven rows of
/// four fields), which should not sit open above the colours.
class CanvasExpander extends StatefulWidget {
  final String label;

  /// trailing is shown beside the label when closed (a count, usually), and
  /// ellipsised rather than pushing the heading wide.
  final String? trailing;

  /// action is a button on the right of the heading, which works whether the
  /// section is open or shut: refreshing a table's data, putting its rows
  /// back in order.
  final Widget? action;

  final List<Widget> children;

  /// initiallyOpen is false for the squad list: somebody opening a team's
  /// settings is usually there for the colours or the formation.
  final bool initiallyOpen;

  /// remember names where this section's open state is kept (see
  /// _rememberedSections), or null to start closed every time.
  final String? remember;

  /// flat draws the children and nothing else (no heading, always open), for
  /// a section already inside a section of its own.
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

/// _rememberedSections is every named section's open state, for this run of
/// the app. In memory as well as on disk because a settings panel is rebuilt
/// whenever the selection changes, and a fresh State reading the disk
/// asynchronously would show the section shut until the answer came back.
/// Shared by [CanvasExpander] and [CanvasFoldingGroup].
final Map<String, bool> _rememberedSections = {};

/// forgetSectionsForTest forgets which sections and groups were open, as a
/// new run of the app would: for tests run one file after another in one
/// process, each of which starts as the app does.
@visibleForTesting
void forgetSectionsForTest() {
  _rememberedSections.clear();
  _CanvasMoreGroupState._remembered.clear();
}

/// _restoreSection reads a section's state off disk into the map, and tells
/// [then] if it turns out to differ from what is on screen.
Future<void> _restoreSection(String key, ValueChanged<bool> then) async {
  var saved = await StorageManager.readData("canvasSection.$key");
  if (saved is! bool) return;
  _rememberedSections[key] = saved;
  then(saved);
}

/// _keepSection writes one down.
void _keepSection(String? key, bool open) {
  if (key == null) return;
  _rememberedSections[key] = open;
  StorageManager.saveData("canvasSection.$key", open);
}

/// rememberedSection, restoreSection and keepSection are the same memory for
/// the panel sections in panel_kit.dart.
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
    // In a section, a card that folds: its name (and how it is set) to
    // press, and what it holds under it.
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
        // Two layouts, by whether there is a width to fill. Down the sidebar the
        // action goes hard against the right edge with the summary taking what
        // is left. Along the band, a horizontal scroller with unbounded width,
        // an Expanded asserts, so the heading shrink-wraps.
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
                  // The name shrinks before the summary does, and both clip: a Text that
                  // cannot shrink overflows however flexible everything beside it is.
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

/// isTypingInAField is whether the keyboard currently belongs to a text
/// field. The canvas and the timeline claim the arrows and the space bar
/// from a Focus below the app's own Shortcuts, so their handlers run first
/// and must step aside while somebody types. Asks the focus manager, since
/// the field may be in the band, the sidebar or a dialog.
bool isTypingInAField() {
  var context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// CanvasKeyframeDot is the little diamond beside a setting that can be
/// animated: lit where a keyframe sits on the frame being looked at, and
/// pressed to add or remove one. What the keyframe holds (a whole pose, or
/// one value) is the caller's: see valueDot in settings_shared.dart.
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

/// CanvasGridCell is a text field with no caption over it, for the chart's
/// numbers and the table's cells: a grid of CanvasTextFields would be a grid
/// of captions.
class CanvasGridCell extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final bool multiline;
  final bool dense;
  final String hint;

  /// suggestions are what this cell is likely to hold, offered as somebody
  /// types: for a cell holding a name the source knows (the coins a comparison
  /// can ask for). The list narrows what is shown and refuses nothing. See
  /// DataPreset.rowNames.
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
    // Only while it is not being typed in: rewriting the text under the
    // cursor eats a keystroke and moves the caret to the end.
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
    // RawAutocomplete rather than Autocomplete, so the cell keeps its own
    // controller and focus node, which stop it rewriting itself under the
    // cursor and commit when it loses focus.
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
        // Centred on one line, top on several: a cell is given the row's
        // height, and top-aligned one line sits high beside the dropdown in a
        // series row.
        textAlignVertical:
            widget.multiline ? TextAlignVertical.top : TextAlignVertical.center,
        decoration: canvasFieldDecoration(ThemeNotifier.of(context),
            hint: widget.hint, fontSize: widget.dense ? 11 : 12),
        onChanged: widget.onChanged,
      );
}

/// CanvasWatch rebuilds only when the part of a listenable it cares about
/// changes: the canvas controller notifies on every pixel of a drag, and
/// most of the sidebar does not change on most of those.
///
/// [select] must be cheap and must be a value (a string, a number, a
/// record), because it runs on every notification and is compared with ==:
/// a list or a map compares by identity and would rebuild every time.
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

/// CanvasFoldingGroup is a [CanvasControlGroup] that can be shut: a chevron
/// on the caption, the controls put away behind it. [remember] names where
/// the answer is kept, so a group shut stays shut across a rebuild and a
/// restart (see _rememberedSections).
class CanvasFoldingGroup extends StatefulWidget {
  final String label;
  final List<Widget> children;

  /// remember is the name the open state is kept under.
  final String remember;

  /// startShut is what a group nobody has touched does. False: a panel that
  /// opens with everything put away says nothing until it is opened.
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
