part of 'controls.dart';

// How a panel's controls are laid out: CanvasWrap, which puts them in rows that
// wrap and grow to fill them, the stretch and grow wrappers it works with, and
// a scroll with no bar. Part of controls.dart.

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
