import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// The four gaps the settings panel is spaced with, and the whole of it.
///
/// One scale, because the alternative is what this was: a caption seven
/// pixels over its controls in one group and fourteen in another, a rule with
/// twelve pixels above it and sixteen below, and four different widths of gap
/// between two controls on the same line. None of it is far enough out to
/// name, and all of it together is a panel that reads as having been assembled
/// rather than laid out.
///
/// canvasControlGap is between two controls on a line, canvasRowGap between
/// one line of a group and the next, canvasCaptionGap under a group's name,
/// and canvasGroupGap under every group. A rule between two groups sits in
/// the middle of a doubled one -- the same above as below, which is the one
/// people notice.
///
/// The group gap is three times the row gap, and it has to be: most panels
/// have no rules left in them at all, so the gap is the only thing saying
/// where one group ends. At twice the row gap a run of five groups still read
/// as one block of controls.
const double canvasControlGap = 5;
const double canvasRowGap = 8;
const double canvasCaptionGap = 7;
const double canvasGroupGap = 24;

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

/// CanvasSeparator is a rule across a row of controls, with air either side.
///
/// For a group holding several of the same thing one after another: two
/// icons' worth of settings with only a line break between them read as one
/// icon with a great many settings.
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

/// CanvasFill marks a control that should grow to help fill its line.
///
/// Its own width is the least it will ever be. Everything else about it --
/// where the line breaks, what it sits beside -- is decided by [CanvasWrap],
/// which hands out whatever room is left over.
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

/// _GrowRoot is a growable control's outermost box.
///
/// It answers "how little will you take" when it is asked loosely, which is
/// what CanvasWrap packs the lines from, and takes exactly what it is given
/// when it is asked tightly, which is how the room left over is handed out.
/// Either way it passes a *tight* width down, so that the [_Stretch] inside
/// it has a width to fill.
///
/// The least it will take is its control's own width or its caption's,
/// whichever is wider: a caption longer than the box under it is what decides
/// how much of a row the control needs, and always has been.
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

/// CanvasWrap is a Wrap whose marked children share out the room left over.
///
/// A sidebar is a column of unknown width that people drag, and a row of
/// fixed-width boxes in one leaves a ragged margin down the right that gets
/// wider the wider the panel is. The boxes grow into it instead.
///
/// The extra is shared as a *per-control amount* rather than by making every
/// marked control the same width, and that is the part worth keeping: a title
/// field beside a number field stays the wider of the two, and -- because
/// every line gets the same amount -- four number fields on one line and two
/// on the next come out the same width, so Angle sits under X.
///
/// The amount is the smallest any line can afford, so widening never pushes a
/// control off the end of the line it was packed onto. A line with fewer
/// marked controls than the busiest one therefore stops short of the right
/// margin, which is what makes the columns line up.
class CanvasWrap extends StatelessWidget {
  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  const CanvasWrap({
    required this.children,
    this.spacing = 0,
    this.runSpacing = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _RawCanvasWrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [
          // Marked here rather than by each control, because the mark is
          // parent data and has to sit between this and the control -- and
          // because the scope that goes with it then covers the control and
          // nothing else. Provided from further up it reached every control
          // inside every child, including the ones in a data grid's own
          // Wrap, which is a mark applied to the wrong parent.
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

/// CanvasBlockBreak ends a line and starts the sharing out again.
///
/// A line break that also says "what follows is a different piece of panel".
/// The room left over is shared by the smallest amount any line can afford,
/// so that the lines of a group come out in the same columns -- and on its
/// own that meant opening a button at the end of a row could make that row
/// narrower, because the line it revealed afforded less.
///
/// [CanvasMoreGroup] puts one of these in front of what its button reveals.
/// An ordinary [CanvasLineBreak] does not start a new block, because the
/// second line of a group is still the same group.
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

/// _CanvasWrapScope says that a control is inside one of these.
///
/// A control only offers to grow where there is a line to grow into. Asked for
/// its width by anything else -- a dialog, a Column, the band above the canvas
/// -- it answers with the width it was given and nothing more, because
/// "however much room there is" in an unknown parent is how a seventy-pixel
/// field ends up four hundred wide.
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
    // with no width at all, so that it answers with the least it will take
    // rather than with the whole line; everything else is asked within the
    // line, because a line break is a child as wide as one.
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

    // Packed greedily, exactly as a Wrap packs: a child that does not fit
    // what is left starts the next line.
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

    // One amount per block, rather than one for the whole wrap. Taking the
    // smallest any line can afford is what puts the lines of a group in the
    // same columns -- and across a block break it is what made opening a
    // button narrow the row the button sits on, because the line it revealed
    // afforded less. Settings already on screen moving when something appears
    // under them is the one thing a reveal must not do.
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
        if (marked.isEmpty) continue;
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

    // A line with nothing tall on it takes no room and costs no gap. The one
    // thing that makes such a line is a deliberate break -- CanvasLineBreak,
    // which is as wide as the wrap and no pixels tall -- and counting it as a
    // line of its own charged the gap twice: two rows the sidebar happened to
    // wrap sat eight pixels apart, and two the author had separated on purpose
    // sat sixteen.
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

/// CanvasNoScrollbar is a scroll behaviour with no bar on it.
///
/// For the panels people scroll with two fingers rather than by taking hold of
/// anything: a bar that appears over the right-hand edge of the settings the
/// moment they move, and fades once they stop, is furniture reporting
/// something they can already see. The wheel, a trackpad and a dragged finger
/// all still scroll.
class CanvasNoScrollbar extends ScrollBehavior {
  const CanvasNoScrollbar();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
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

  /// captionGap is the room between the caption and the controls under it.
  ///
  /// The default is what every section heading in the settings panel uses --
  /// a word or two in small capitals, with its controls close under it. A
  /// group whose caption is a sentence rather than a name needs more than
  /// that: read at the same distance, the sentence and the caption of the
  /// first control under it run together as one paragraph.
  final double captionGap;

  /// rule is the line under the group.
  ///
  /// Dropped where the group after it is a continuation rather than a new
  /// subject -- the axis names under the title and the description, which are
  /// one heading's worth of settings split over two lines because the second
  /// line carries a button of its own.
  final bool rule;

  /// below goes under the group's own line of controls, inside its gap and
  /// above its rule. For the settings a button on that line has opened -- see
  /// CanvasMoreGroup -- which are part of the group and have to sit inside
  /// it rather than in a group of their own.
  final Widget? below;

  const CanvasControlGroup({
    required this.label,
    required this.children,
    this.hideCaption = false,
    this.captionGap = canvasCaptionGap,
    this.rule = true,
    this.below,
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
                if (below != null) below!,
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
      // is packed reads as two panels by different hands.
      //
      // Every group leaves the same gap under it, and a rule sits in the
      // middle of a doubled one: with a line, two gaps and the line between
      // them; without, one gap. Unequal either side, the line reads as
      // belonging to whichever group it is nearer, which is the opposite of
      // what a divider is for.
      //
      // The gap without a rule used to be the one between two lines of a
      // group, on the grounds that an unruled group is one the next continues.
      // That is true of two groups and false of five: a run of them with
      // nothing between reads as one undivided block, and the rules were the
      // only thing that had been holding it apart.
      //
      // A rule under most groups as well as a gap. Six clusters of small
      // controls down one narrow column, separated by nine pixels of nothing,
      // ran together into one field of boxes -- the caption above each was the
      // only thing saying where one ended, and a caption is nine pixels tall
      // and grey.
      padding: const EdgeInsets.only(bottom: canvasGroupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hideCaption)
            Padding(
                padding: EdgeInsets.only(bottom: captionGap, left: 1),
                child: caption),
          // No spacing between them: each control carries its own right-hand
          // padding, as it did under the Wrap this replaced. Adding a gap here
          // as well is four pixels a control, which is what pushed a row that
          // had been measured to fit onto two lines.
          CanvasWrap(runSpacing: canvasRowGap, children: children),
          if (below != null) below!,
          if (rule) const CanvasGroupRule(),
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

  /// step is how far one pixel of a drag on the label moves the number.
  /// Null is the field's own last digit, which is right wherever the digits
  /// are the scale -- and wrong where a field is precise but wide, such as a
  /// ring width in ten-thousandths that runs to a fifth of the page: dragging
  /// that across at a ten-thousandth a pixel is two thousand pixels of
  /// travel.
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
  /// began -- see _ScrubLabel, which does the same arithmetic.
  ///
  /// Held rather than dragged, because a field's own drag is how text is
  /// selected and typing an exact number has to go on working. Holding is
  /// free: nothing else on a text field means anything by it.
  ///
  /// It is here as well as on the caption because a caption is written once
  /// per column -- a chart's fourth series has an Offset field with nothing
  /// above it, and on the old arrangement that was a number that could only
  /// be typed.
  /// Nothing in the hold reaches the panel -- no unfocus, no commit. That is
  /// what made it temperamental: losing the focus calls onCommit, which closes
  /// the undo step, which rebuilds the settings panel, which can take this
  /// field's state away in the middle of its own gesture.
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
    // into. Rewriting it under the cursor moves the caret to the end on every
    // keystroke, which makes it impossible to edit the middle of a number.
    //
    // Being scrubbed counts as not being typed into, and has to be said
    // explicitly: pressing the field is what gives it the focus in the first
    // place, so a scrub that started with a press was a number running up and
    // down on the canvas with the old figure still sitting in the box.
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

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var step = widget.step ?? math.pow(10, -widget.decimals).toDouble();
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
          // press on the field: the box is a whole row tall and the words sit
          // in the middle of it.
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
              // Moved before it was held: that is the field's own drag, which
              // is how a number is selected to be retyped. The allowance is
              // generous on purpose -- a hand holding still does not, and a
              // press that gave up over two pixels of drift is a press that
              // works sometimes.
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
            // Left and right over the whole box, the same as over the caption
            // and for the same reason: it is the only thing that says the
            // number can be dragged. Set on the field rather than in a
            // MouseRegion around it, because a text field carries a cursor of
            // its own and the innermost one wins.
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

/// _scrubbed is where a scrub of [travelled] pixels from [from] has got to.
///
/// One pixel of travel moves the number by one step, and shift makes it ten
/// times finer for the last pixel of a nudge.
double _scrubbed(double from, double travelled, double step,
    {required double min, required double max}) {
  var fine = HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0;
  return (from + travelled * step * fine).clamp(min, max).toDouble();
}

/// canvasFieldDecoration is what every field on this panel is drawn with.
///
/// The border is left to the app's own input theme, which draws a line under
/// the words. Spelled out as a box here it matched the dropdown beside it and
/// looked wrong everywhere else, and it is not this panel's decision to make.
///
/// What is spelled out is the room above and below the words, because that is
/// what decides how tall the field is *drawn*. A field is given a row's height
/// to sit in; the decoration is drawn at whatever height its padding adds up
/// to and sits at the top of that row. With no padding at all -- which is what
/// the number fields had -- that is eighteen pixels of field in a
/// twenty-seven pixel row, which is a line sitting nine pixels high of where
/// the eye expects it, on every number on the panel.
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
/// field exactly [controlHeight] tall.
///
/// A line of text is about a fifth taller than its point size, and the border
/// takes a pixel at each end.
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

  /// grow lets this take some of the room left over on its line; [width] is
  /// then the least it will be. See CanvasWrap.
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
          height: widget.maxLines > 1 ? controlHeight * 2 : controlHeight,
          grow: widget.grow,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            maxLines: widget.maxLines,
            style: const TextStyle(fontSize: 12),
            decoration: canvasFieldDecoration(ThemeNotifier.of(context),
                hint: widget.hint),
            onChanged: widget.onChanged,
          ),
        ),
      );
}

/// CanvasMoreGroup is a group of settings with the rest of them behind a
/// button on the end of its first line.
///
/// The shape a chart's series list uses, made shareable: the settings anybody
/// changes are out where they can be seen, and the ones that are set once and
/// left are one press away. A panel where everything is equally visible is a
/// panel where nothing is -- which is what these settings had become, twenty
/// controls deep in sections with no shape to them.
///
/// The open state is remembered under [remember] for the run, like a
/// section's, so a panel that rebuilds -- which it does on every change to the
/// element -- does not shut what somebody has just opened.
class CanvasMoreGroup extends StatefulWidget {
  final String label;
  final bool hideCaption;

  /// rule is the line under the group; see CanvasControlGroup.rule.
  final bool rule;

  /// remember names where the open state is kept. Null keeps it only as long
  /// as the widget is in the tree, which in a settings panel is not long.
  final String? remember;

  /// row is what is always shown, and more is what the button reveals. The
  /// button is drawn at the end of the row, so [row] should be short enough
  /// to leave space for it.
  final List<Widget> row;
  final List<Widget> more;

  /// tooltip says what is behind the button, which is the only thing that
  /// tells anybody whether it is worth pressing.
  final String tooltip;

  const CanvasMoreGroup({
    required this.label,
    required this.row,
    required this.more,
    this.tooltip = "More settings",
    this.hideCaption = false,
    this.rule = true,
    this.remember,
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
    return CanvasControlGroup(
      label: widget.label,
      hideCaption: widget.hideCaption,
      rule: widget.rule,
      // What the button opened, on a ground of its own.
      //
      // A tint rather than a line under it, which is what this was. Opened,
      // these settings run straight into whatever is below them, and a reader
      // who has scrolled past the button has nothing saying which of the
      // controls in front of them came out of it -- a line at the foot says
      // where they stop and nothing says where they start. The ground says
      // both at once, and says it while the eye is still on the button.
      //
      // It is a line of layout of its own as well: what is revealed shares
      // out the room left over among itself, so opening this cannot narrow
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
                  // The ground a boxed section is drawn on, a little stronger:
                  // this one has to be read against the panel from the corner
                  // of the eye while the pointer is still on the button.
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

/// canvasMoreInset is the room inside the ground an opened more-settings area
/// is drawn on.
const double canvasMoreInset = 8;

/// CanvasGroupRule is the line between one group of settings and the next.
///
/// It keeps the gap above it and the group under it keeps the same gap below,
/// so the line sits midway between the two things it divides. Nearer one than
/// the other it reads as belonging to that one, which is the opposite of what
/// a divider is for.
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
  final ValueChanged<T> onChanged;

  /// enabled is whether it answers at all.
  ///
  /// A control that is drawn and does nothing is worse than one that is not
  /// drawn -- except where its being there is the only way anybody learns it
  /// exists, which is what the greyed state is for. See keyframeEasingGroup.
  final bool enabled;

  /// tight holds the caption to the width of the box under it.
  ///
  /// Off by default, because a caption reading "Gives way w..." is worse than
  /// a row an inch wider nearly everywhere. It is for the controls that are
  /// sized to the room there is rather than to what they hold: there, the
  /// caption deciding the width means narrowing the box achieves nothing.
  final bool tight;

  /// grow lets this take some of the room left over on its line.
  ///
  /// [width] is then the least it will be rather than the whole of it. See
  /// CanvasWrap: the extra is shared out evenly among everything on the line
  /// that asked for it, and by the same amount on every line, so that a row of
  /// four fields and a row of two below it come out in the same columns.
  @override
  final bool grow;

  const CanvasDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 130,
    this.tight = false,
    this.enabled = true,
    this.grow = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      cap: tight ? CanvasControlScope.widthFor(context, width) : null,
      canvasSized(
        context,
        min: CanvasControlScope.widthFor(context, width),
        height: controlHeight,
        grow: grow,
        child: Container(
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
              onChanged: enabled
                  ? (v) {
                      // Null is a real answer where the type says it is one --
                      // a dropdown of "None, Fade, Slide" is a dropdown whose
                      // first entry is null, and refusing it meant None could
                      // be chosen and nothing happened.
                      if (v == null && null is! T) return;
                      onChanged(v as T);
                    }
                  : null,
            ),
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

  /// gradient is the second colour, for the things that can be painted with
  /// two. Set [onGradientChanged] to offer the picker's Gradient tab; leave
  /// it null and this is the plain swatch it has always been.
  ///
  /// The gradient is set *in the picker*, not beside it. A Fade toggle, a
  /// second swatch, a Radial toggle and an Angle field next to every colour
  /// is four controls per colour for something most colours never use.
  final GradientSpec? gradient;
  final ValueChanged<GradientSpec?>? onGradientChanged;

  /// labelWidth holds the caption to the swatch's own width, for the rows
  /// where a swatch has to fit in a known amount of room.
  ///
  /// A Column is as wide as its widest child, so a caption longer than the
  /// thing it names is what decides how much of a line the control takes --
  /// and a thirty-pixel swatch under the word "Colour" is a fifty-pixel
  /// column, which is the difference between a row that fits and one that
  /// wraps.
  final double? labelWidth;

  const CanvasColorButton({
    required this.label,
    required this.color,
    required this.onChanged,
    this.gradient,
    this.onGradientChanged,
    this.labelWidth,
    this.allowAlpha = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return _labelled(
      theme,
      label,
      cap: labelWidth,
      Tooltip(
        message: onGradientChanged == null
            ? "Choose a colour"
            : "Choose a colour, or two to fade between",
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () async {
            var picked = await pickPaint(
              context,
              initial: PaintSpec(color, gradient: gradient),
              allowAlpha: allowAlpha,
              fades: onGradientChanged != null,
            );
            if (picked == null) return;
            if (picked.color != color) onChanged(picked.color);
            if (picked.gradient != gradient) {
              onGradientChanged?.call(picked.gradient);
            }
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
                painter: _SwatchPainter(color, gradient),
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
      //
      // The caption *and* the gap under it. The caption alone left this three
      // pixels high of where it should be, which is not much until it is a
      // button sitting beside two dropdowns.
      padding: EdgeInsets.only(
          right: canvasControlGap,
          top: CanvasControlScope.isInline(context)
              ? 0
              : controlWithLabelHeight - controlHeight),
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
          // No check box beside the word. It was nineteen pixels per switch
          // saying what the fill already says, on a panel whose switches come
          // five to a line -- and the difference between five of them fitting
          // a narrow sidebar and four of them fitting was exactly that.
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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

/// CanvasReadout is a caption over something the panel can only tell you.
///
/// For the answers that are not settings: which document a text element is
/// reading, what a chain of boxes is flowing into. A disabled field would say
/// the same thing while inviting somebody to type in it.
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
        height: controlHeight,
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
  /// neighbours have.
  ///
  /// Right in a row of captioned controls, wrong anywhere else: on a
  /// section's heading it put the button half a caption below the words it
  /// sits beside, and made a closed section taller than the one under it.
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
      // The nudge lines a control with no caption up with the ones that have
      // them. On the band the captions are beside their controls and there is
      // nothing above to line up under, so the nudge is what pushed this out
      // of line with its neighbours.
      //
      // The caption *and* the gap under it. The caption alone left this three
      // pixels high of where it should be, which is not much until it is a
      // button sitting beside two dropdowns.
      padding: EdgeInsets.only(
          right: canvasControlGap,
          top: tight || CanvasControlScope.isInline(context)
              ? 0
              : controlWithLabelHeight - controlHeight),
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

    var step = widget.step ?? math.pow(10, -widget.decimals).toDouble();

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

/// _labelled puts a caption above a control.
///
/// [scrub] makes that caption a handle: dragging it sideways runs the number
/// up and down. See _ScrubLabel.
Widget _labelled(ThemeNotifier theme, String label, Widget child,
    {Widget? scrub, double? cap}) {
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
      padding: const EdgeInsets.only(right: canvasControlGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scrub != null)
            scrub
          else
            // Held to the width of the control it names, where the caller
            // has asked for that. A Column is as wide as its widest child,
            // so a caption longer than its control is what decides how much
            // of a row the control takes -- a dropdown narrowed to seventy
            // pixels still took a hundred and thirty, because that is how
            // wide "Gives way with" is.
            SizedBox(height: controlLabelHeight, width: cap, child: caption),
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
          right: canvasControlGap,
          top: CanvasControlScope.isInline(context)
              ? 0
              : controlWithLabelHeight - controlHeight),
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

  /// suggestions are what this cell is likely to hold, offered as soon as
  /// somebody starts typing.
  ///
  /// For a cell whose content is a *name the source knows* rather than free
  /// text: the coins a comparison can ask for, and whatever the next source
  /// with a list of rows turns out to have. Typing is still typing -- the
  /// list narrows what is shown and refuses nothing -- because the list is
  /// never every name there is. See DataPreset.rowNames.
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
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return _field(context);
    var theme = ThemeNotifier.of(context);
    // RawAutocomplete rather than Autocomplete, so the cell keeps its own
    // controller and focus node: those are what make it stop rewriting itself
    // under the cursor and commit when it loses focus, and an Autocomplete
    // would bring a second pair of its own.
    return RawAutocomplete<String>(
      textEditingController: _text,
      focusNode: _focus,
      optionsBuilder: (value) {
        var typed = value.text.trim().toLowerCase();
        if (typed.isEmpty) return const Iterable<String>.empty();
        // What is being typed, wherever it appears in the name: "cash" finds
        // Bitcoin Cash. An exact match offers nothing -- the answer is
        // already in the cell.
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
        // Centred on one line, top on several. A cell is given the row's
        // height, which is more than one line of eleven-point text needs, so
        // top-aligned left the words sitting high in their box -- visibly out
        // of line with the dropdown beside them in a series row.
        textAlignVertical:
            widget.multiline ? TextAlignVertical.top : TextAlignVertical.center,
        decoration: canvasFieldDecoration(ThemeNotifier.of(context),
            hint: widget.hint, fontSize: widget.dense ? 11 : 12),
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
