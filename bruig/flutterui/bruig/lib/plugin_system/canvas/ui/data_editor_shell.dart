import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_editor_shell.dart is the frame round a block of data being edited: the
// switch between pasted text and a grid, the height it has been dragged to,
// and the grip that drags it.
//
// One frame for the chart's numbers and the table's cells, because they are
// the same box asked for twice. What differs is only what a cell holds -- a
// number or a word -- and a reader who has learnt one of them should not have
// to learn the other.
//
// Both decisions are remembered for the session as well as on disk, and that
// is the fix rather than an optimisation: the settings panel is rebuilt from
// scratch whenever the selection changes, and a fresh State reads a stored
// preference asynchronously -- so a table dragged taller went back to its
// default every time it was returned to.

const double _minHeight = 70;
const double _maxHeight = 460;

/// CanvasDataEditorShell is the frame; [text] and [grid] are what goes in it.
class CanvasDataEditorShell extends StatefulWidget {
  /// remember names where this editor's height and chosen view are kept. Each
  /// editor passes its own, so a chart and a table are dragged separately.
  final String remember;

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
  /// _grids and _heights are what each named editor was left at, for this run
  /// of the app. See the note at the top of the file on why they are static.
  static final Map<String, bool> _grids = {};
  static final Map<String, double> _heights = {};

  bool get _grid => _grids[widget.remember] ?? false;
  double get _height => _heights[widget.remember] ?? 132;

  String get _gridKey => "${widget.remember}Grid";
  String get _heightKey => "${widget.remember}Height";

  @override
  void initState() {
    super.initState();
    if (!_grids.containsKey(widget.remember)) _restore();
  }

  Future<void> _restore() async {
    var grid = await StorageManager.readData(_gridKey);
    var height = await StorageManager.readData(_heightKey);
    if (grid is bool) _grids[widget.remember] = grid;
    if (height is num) {
      _heights[widget.remember] =
          height.toDouble().clamp(_minHeight, _maxHeight);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // Full width in the sidebar, where there is a column to fill. In the band
    // above the canvas there is not -- the whole line is one control tall --
    // so it keeps to a control's width there.
    var stacked = CanvasControlScope.isStacked(context);

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
          width: stacked ? double.infinity : 280,
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
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() {
            // Kept as it moves rather than only when the drag ends: a drag the
            // surrounding list wins ends as a cancel, and a height saved only
            // on a clean end was a height that sometimes was not saved.
            _heights[widget.remember] =
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
