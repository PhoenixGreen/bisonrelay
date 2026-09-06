import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// panel_stack.dart is a column of panels that open, close, resize and change
// places, and remembers all three.
//
// It replaces a two-way split that could only ever be two things -- a list on
// top and the settings under it, with one grip between them. Three panels was
// one too many for that shape, and the shape was the reason the design
// elements, the layers and the settings lived in different tabs at all: they
// are used together, and a tab is a place you have to leave to reach another.
//
// Everything about the arrangement belongs to the reader. Which panels are
// open, how tall each one is, and what order they come in are all decisions
// somebody makes once about how they work, so all three are written down and
// come back next time -- see [CanvasPanelStack.storageKey].
//
// A header is a band of its own colour with nothing in it but the panel's
// name: no expander arrow, because the whole band is the switch and an arrow
// beside a band that is entirely clickable is a smaller target that looks like
// the only one, and no grip, because the line between two panels is where
// anybody reaches to move a boundary.

/// PanelDrag is a panel being carried, and exists only to be its own type.
///
/// The layer list inside one of these panels drags its rows as Strings. A
/// panel dragged as a String too would be a payload the layer list's own
/// targets would accept -- dropping a panel header onto a layer row would ask
/// the list to move a layer whose id is "settings", which is not a mistake
/// worth leaving available. Two drag systems in one tree need two types.
class PanelDrag {
  final String id;
  const PanelDrag(this.id);
}

/// CanvasStackPanel is one panel: what it is called, and what is in it.
class CanvasStackPanel {
  /// id names this panel in storage and identifies it while it is being
  /// dragged. It must outlive a rename of the label.
  final String id;

  final String label;
  final IconData icon;

  /// hint is the question mark beside the name, for a panel that needs one.
  final String? hint;

  /// trailing is a short summary shown beside the name -- a count, usually --
  /// so a shut panel still says how much is behind it.
  final String? trailing;

  final WidgetBuilder builder;

  const CanvasStackPanel({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.hint,
    this.trailing,
  });
}

/// CanvasPanelStack lays [panels] down a column, in the reader's own order.
class CanvasPanelStack extends StatefulWidget {
  final List<CanvasStackPanel> panels;

  /// storageKey is where this stack's arrangement is remembered. One stack,
  /// one key; the settings band and the sidebar would each want their own.
  final String storageKey;

  const CanvasPanelStack({
    required this.panels,
    required this.storageKey,
    super.key,
  });

  @override
  State<CanvasPanelStack> createState() => _CanvasPanelStackState();
}

class _CanvasPanelStackState extends State<CanvasPanelStack> {
  /// _headerHeight is what a shut panel costs. Its own constant because the
  /// arithmetic that shares out the rest has to subtract it for every panel,
  /// open or not.
  ///
  /// Roomy for a row of nine-pixel capitals, deliberately: the whole band is
  /// the switch, so it may as well be worth aiming at.
  static const double _headerHeight = 34;

  /// _dividerHeight is the line between two panels, and the grip that moves
  /// it. Thin to look at and thick enough to catch.
  static const double _dividerHeight = 7;

  /// _minBody keeps a panel from being dragged away to nothing. A panel that
  /// can be closed by dragging is a panel that gets closed by accident, and
  /// there is a button for that a few pixels away.
  static const double _minBody = 80;

  /// _order is the panel ids, top to bottom. Ids the stack does not know about
  /// are ignored and ones it has never seen are appended, so adding a panel in
  /// a later version does not throw away the order somebody chose.
  List<String> _order = const [];
  final Map<String, bool> _open = {};

  /// _heights is what each open panel was last given, in pixels.
  ///
  /// Pixels rather than fractions: a sidebar that is made taller should give
  /// the extra room to the last panel rather than stretching every one of them
  /// proportionally, which is what a reader who sized a panel to its contents
  /// expects.
  final Map<String, double> _heights = {};

  /// _dragging is the panel being carried, while one is.
  String? _dragging;

  @override
  void initState() {
    super.initState();
    _order = [for (var p in widget.panels) p.id];
    _restore();
  }

  String get _orderKey => "${widget.storageKey}.order";
  String _openKey(String id) => "${widget.storageKey}.open.$id";
  String _heightKey(String id) => "${widget.storageKey}.height.$id";

  Future<void> _restore() async {
    var saved = await StorageManager.readString(_orderKey);
    var open = <String, bool>{};
    var heights = <String, double>{};
    for (var panel in widget.panels) {
      var wasOpen = await StorageManager.readData(_openKey(panel.id));
      if (wasOpen is bool) open[panel.id] = wasOpen;
      var height = await StorageManager.readData(_heightKey(panel.id));
      if (height is num) heights[panel.id] = height.toDouble();
    }
    if (!mounted) return;

    setState(() {
      if (saved.isNotEmpty) {
        var known = {for (var p in widget.panels) p.id};
        var wanted = [
          for (var id in saved.split(","))
            if (known.contains(id)) id,
        ];
        _order = [
          ...wanted,
          for (var p in widget.panels)
            if (!wanted.contains(p.id)) p.id,
        ];
      }
      _open.addAll(open);
      _heights.addAll(heights);
    });
  }

  bool _isOpen(String id) => _open[id] ?? true;

  void _toggle(String id) {
    setState(() => _open[id] = !_isOpen(id));
    StorageManager.saveData(_openKey(id), _open[id]);
  }

  void _move(String id, String before) {
    if (id == before) return;
    setState(() {
      var order = [..._order]..remove(id);
      order.insert(math.max(0, order.indexOf(before)), id);
      _order = order;
    });
    StorageManager.saveString(_orderKey, _order.join(","));
  }

  /// _resize gives [by] pixels to the panel above [id], taking them from the
  /// space the ones below it share.
  ///
  /// The panel above rather than this one, because the edge being dragged is
  /// the boundary between the two and a boundary belongs to both. Moving it
  /// down makes the one above taller, which is what it looks like it does.
  void _resize(String id, double by) {
    var open = [
      for (var p in _order)
        if (_isOpen(p)) p
    ];
    var at = open.indexOf(id);
    if (at <= 0) return;
    var above = open[at - 1];

    setState(() {
      _heights[above] =
          math.max(_minBody, (_heights[above] ?? _minBody * 2) + by);
    });
    StorageManager.saveData(_heightKey(above), _heights[above]);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var byId = {for (var p in widget.panels) p.id: p};
    var panels = [
      for (var id in _order)
        if (byId[id] case var panel?) panel,
    ];
    var open = [
      for (var p in panels)
        if (_isOpen(p.id)) p
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // What is left for the open panels once every header has had its row.
      var room = constraints.maxHeight -
          panels.length * _headerHeight -
          math.max(0, panels.length - 1) * _dividerHeight;
      var share = open.isEmpty ? 0.0 : math.max(_minBody, room / open.length);

      return Column(children: [
        for (var (i, panel) in panels.indexed) ...[
          if (i > 0) _divider(theme, panel),
          _header(theme, panel),
          if (_isOpen(panel.id))
            // The last open panel takes what is left rather than a remembered
            // height, so the column always fills the sidebar exactly and there
            // is never a strip of nothing at the bottom.
            if (panel.id == open.last.id)
              Expanded(child: _body(panel))
            else
              SizedBox(
                height: math.min(
                    math.max(_minBody, _heights[panel.id] ?? share),
                    math.max(_minBody, room)),
                child: _body(panel),
              ),
        ],
      ]);
    });
  }

  Widget _body(CanvasStackPanel panel) => ClipRect(
        child: Builder(builder: panel.builder),
      );

  /// _divider is the line between two panels, and the grip that moves it.
  ///
  /// Between them rather than inside a header, which is where the grip used to
  /// be. A boundary is the thing being moved, so the boundary is the thing to
  /// take hold of -- and an icon in the header was a second small target in a
  /// band that is otherwise one big one.
  Widget _divider(ThemeNotifier theme, CanvasStackPanel below) => MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) =>
              _resize(below.id, details.delta.dy),
          child: SizedBox(
            height: _dividerHeight,
            child: Center(
              child: Container(
                height: 1,
                color: theme.colors.outlineVariant,
              ),
            ),
          ),
        ),
      );

  /// _header is the panel's name, its switch and its handle -- which are two
  /// things, because the whole band is the switch.
  ///
  /// A DragTarget rather than a reorderable list. A list would move the
  /// panels' elements rather than rebuild them, which is how an overlay inside
  /// one gets re-attached mid-layout and takes the sidebar down with it -- and
  /// these panels are full of tooltips and menus. Dropping one header on
  /// another rebuilds both, which nothing minds.
  Widget _header(ThemeNotifier theme, CanvasStackPanel panel) {
    return DragTarget<PanelDrag>(
      onWillAcceptWithDetails: (details) => details.data.id != panel.id,
      onAcceptWithDetails: (details) => _move(details.data.id, panel.id),
      builder: (context, candidate, _) => Material(
        // Its own colour across the whole band, so a header is a header at a
        // glance rather than a line of small capitals floating above some
        // controls. A Material rather than a Container, so the ink the InkWell
        // draws -- the hover, the press -- lands on this rather than on
        // whatever is behind the sidebar.
        color: candidate.isEmpty
            ? theme.colors.surfaceContainerHighest
            : theme.colors.primary.withValues(alpha: 0.18),
        child: InkWell(
          onTap: () => _toggle(panel.id),
          child: SizedBox(
            height: _headerHeight,
            child: Row(children: [
              const SizedBox(width: 10),
              Icon(panel.icon, size: 14, color: theme.colors.onSurfaceVariant),
              const SizedBox(width: 7),
              // One Expanded holding the whole name, rather than a Flexible
              // label and a Spacer beside it.
              //
              // Those were two flexible children of one Row, and a Flexible
              // is allotted its share of the leftover width whether it uses
              // it or not -- so the space after the name was half of what was
              // going, the handle sat wherever that put it, and the three
              // headers lined their handles up at three different places.
              Expanded(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(
                      panel.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurfaceVariant
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  if (panel.trailing != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        panel.trailing!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9,
                            color: theme.colors.onSurfaceVariant
                                .withValues(alpha: 0.55)),
                      ),
                    ),
                  ],
                  if (panel.hint != null) CanvasHint(panel.hint!),
                ]),
              ),
              _handle(theme, panel),
            ]),
          ),
        ),
      ),
    );
  }

  /// _handle is what a panel is carried by.
  Widget _handle(ThemeNotifier theme, CanvasStackPanel panel) {
    var icon = SizedBox(
      width: 26,
      height: _headerHeight,
      child: Icon(Icons.drag_indicator,
          size: 14,
          color: theme.colors.onSurfaceVariant
              .withValues(alpha: _dragging == panel.id ? 0.9 : 0.45)),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<PanelDrag>(
        data: PanelDrag(panel.id),
        axis: Axis.vertical,
        onDragStarted: () => setState(() => _dragging = panel.id),
        onDragEnd: (_) => setState(() => _dragging = null),
        feedback: Material(
          color: theme.colors.surfaceContainerHighest,
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(panel.label.toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 0.8)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: icon),
        child: icon,
      ),
    );
  }
}
