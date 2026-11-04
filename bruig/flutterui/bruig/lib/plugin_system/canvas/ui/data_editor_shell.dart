import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_editor_shell.dart is the frame round a block of data being edited:
// the switch between pasted text and a grid, the height it has been dragged
// to, and the grip that drags it; one frame for the chart's numbers and the
// table's cells. Both choices are kept for the session as well as on disk:
// the panel is rebuilt on every selection and a fresh State reads the
// stored preference asynchronously, so without the session copy a dragged
// height was lost every time.

const double _minHeight = 70;

/// _maxHeight is as tall as the box may get on its own: generous, since the
/// panel scrolls and a grid scrolling inside it fights it for the wheel.
const double _maxHeight = 1200;

/// editorHeight is how tall the box is: what was dragged this session, or
/// else the larger of the rows it holds and [stored]. [stored] is a floor,
/// not the answer: it is one number shared by every table, so a height
/// chosen for three rows must not make twenty scroll. A drag this session is
/// obeyed exactly, shorter or taller.
double editorHeight({double? dragged, double? stored, double wanted = 0}) {
  if (dragged != null) return dragged.clamp(_minHeight, _maxHeight);
  var floor = stored ?? 132;
  return math.max(floor, wanted).clamp(_minHeight, _maxHeight);
}

/// CanvasDataEditorShell is the frame; [text] and [grid] are what goes in it.
class CanvasDataEditorShell extends StatefulWidget {
  /// remember names where this editor's chosen view is kept. Each editor
  /// passes its own, so a chart and a table are switched separately.
  final String remember;

  /// scope names the one element whose height is kept: its id. Separate from
  /// [remember] because grid or text is a way of working, kept per editor,
  /// while the height belongs to what is in the box.
  final String scope;

  /// wanted is how tall the grid would be if nothing cut it off: enough for
  /// every row. The box grows to it, up to [_maxHeight], until the grip is
  /// dragged; a chosen height is then kept.
  final double wanted;

  /// gridTooltip and textTooltip name the two views in the switch between
  /// them -- "Edit the cells in a grid" reads better than "Grid".
  final String gridTooltip;
  final String textTooltip;

  /// toolbar is whatever else belongs on the switch's line: the buttons that
  /// add a row, a column or a series.
  final List<Widget> toolbar;

  final Widget Function(BuildContext) text;
  final Widget Function(BuildContext) grid;

  /// below is drawn under the grip, for anything that describes what is in
  /// the editor rather than being part of it -- a chart's series, say.
  final List<Widget> below;

  const CanvasDataEditorShell({
    required this.remember,
    this.scope = "",
    this.wanted = 0,
    required this.gridTooltip,
    required this.textTooltip,
    required this.text,
    required this.grid,
    this.toolbar = const [],
    this.below = const [],
    super.key,
  });

  @override
  State<CanvasDataEditorShell> createState() => _CanvasDataEditorShellState();
}

class _CanvasDataEditorShellState extends State<CanvasDataEditorShell> {
  /// _grids, _stored and _dragged are what each named editor was left at, for
  /// this run of the app (see the top of the file). A height read from disk
  /// and one dragged this sitting are kept apart: see editorHeight.
  static final Map<String, bool> _grids = {};
  static final Map<String, double> _stored = {};
  static final Map<String, double> _dragged = {};

  bool get _grid => _grids[widget.remember] ?? false;

  /// _mine is where this editor's height is kept: its own name and the
  /// element it is showing.
  String get _mine => widget.scope.isEmpty
      ? widget.remember
      : "${widget.remember}.${widget.scope}";

  double get _height => editorHeight(
        dragged: _dragged[_mine],
        stored: _stored[_mine],
        wanted: widget.wanted,
      );

  String get _gridKey => "${widget.remember}Grid";
  String get _heightKey => "${_mine}Height";

  @override
  void initState() {
    super.initState();
    if (!_grids.containsKey(widget.remember) || !_stored.containsKey(_mine)) {
      _restore();
    }
  }

  @override
  void didUpdateWidget(CanvasDataEditorShell old) {
    super.didUpdateWidget(old);
    // A different element in the same panel: its height is its own and has to
    // be read for itself.
    if (old.scope != widget.scope && !_stored.containsKey(_mine)) _restore();
  }

  Future<void> _restore() async {
    var grid = await StorageManager.readData(_gridKey);
    var height = await StorageManager.readData(_heightKey);
    if (grid is bool) _grids[widget.remember] = grid;
    if (height is num) {
      _stored[_mine] = height.toDouble().clamp(_minHeight, _maxHeight);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          CanvasIconButton(
            icon: _grid ? Icons.notes : Icons.grid_on,
            tooltip: _grid ? widget.textTooltip : widget.gridTooltip,
            active: _grid,
            onPressed: () {
              setState(() => _grids[widget.remember] = !_grid);
              StorageManager.saveData(_gridKey, _grid);
            },
          ),
          ...widget.toolbar,
        ]),
        SizedBox(
          key: const ValueKey("dataEditorBody"),
          width: double.infinity,
          height: _height,
          child: _grid ? widget.grid(context) : widget.text(context),
        ),
        _grip(theme),
        ...widget.below,
      ],
    );
  }

  /// _grip drags the editor taller or shorter.
  Widget _grip(ThemeNotifier theme) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey("dataEditorGrip"),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() {
            // Kept as it moves, not only at the end: a drag the surrounding
            // list wins ends as a cancel.
            _dragged[_mine] =
                (_height + d.delta.dy).clamp(_minHeight, _maxHeight);
          }),
          onVerticalDragEnd: (_) =>
              StorageManager.saveData(_heightKey, _height),
          onVerticalDragCancel: () =>
              StorageManager.saveData(_heightKey, _height),
          child: SizedBox(
            height: 11,
            child: Center(
              child: Container(
                height: 3,
                width: 34,
                decoration: BoxDecoration(
                  color: theme.colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
}
