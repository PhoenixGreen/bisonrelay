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
// open, how tall each one is, what order they come in and which of them share
// a place as tabs are all decisions somebody makes once about how they work,
// so all of them are written down and come back next time -- see
// [CanvasPanelStack.storageKey].
//
// Two panels can share a place. Dropping one onto another's header tabs them
// together: they take one panel's worth of room and one is showing at a time,
// which is what somebody with a tall list and a tall settings panel and a
// short sidebar actually wants. It is the same list underneath -- a stack of
// groups, most of them holding one panel -- so a tab is not a second kind of
// thing to arrange.
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

  /// body is the panel's contents, built once by whoever owns the stack.
  ///
  /// A widget rather than a builder, and that is the whole point: the stack
  /// rebuilds whenever a header's name or count changes, and a builder would
  /// rebuild every panel's contents with it. Handed the same widget instance
  /// twice, Flutter leaves that subtree alone -- so a panel updates when what
  /// it shows changes rather than when its neighbour's heading does.
  final Widget body;

  const CanvasStackPanel({
    required this.id,
    required this.label,
    required this.icon,
    required this.body,
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

  /// _groups is the arrangement: a list of places down the column, each
  /// holding one panel or several as tabs.
  ///
  /// Ids the stack does not know about are ignored and ones it has never seen
  /// are appended, so adding a panel in a later version does not throw away
  /// the arrangement somebody chose.
  List<List<String>> _groups = const [];

  final Map<String, bool> _open = {};

  /// _selected is which tab is showing, for the groups that have more than
  /// one. At most one id per group is in it; a group with none of its ids
  /// here shows its first.
  ///
  /// A set of ids rather than an index per group, because groups are made and
  /// unmade by dragging and an index would point at the wrong tab the moment
  /// one moved.
  final Set<String> _selected = {};

  /// _share is what an open place was given last time the column was laid
  /// out, for the places that have never been resized.
  ///
  /// Kept because the first drag of a boundary has to carry on from what is
  /// on the screen. Without it that drag started from a guess -- twice the
  /// minimum -- so a panel filling half the sidebar jumped down to a hundred
  /// and sixty pixels the moment its edge was touched.
  double _share = _minBody * 2;

  /// _hovering is the drop the pointer is currently over, while a panel is
  /// being dragged: which place, and what would happen there.
  (int, _Drop)? _hovering;

  /// _heights is what each open *place* was last given, in pixels, filed
  /// under the id of the first panel in it.
  ///
  /// The place rather than the panel, because a place is what has a height: a
  /// group of tabs is one box that different panels take turns inside, and
  /// heights kept per tab made the sidebar jump every time somebody looked at
  /// the other one.
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
    _groups = [
      for (var p in widget.panels) [p.id]
    ];
    _restore();
  }

  /// _order is the ids in order, flattened -- for saving, and for the checks
  /// that only care which panels exist.
  List<String> get _order => [
        for (var group in _groups) ...group,
      ];

  String get _orderKey => "${widget.storageKey}.order";
  String get _tabKey => "${widget.storageKey}.tab";
  String _openKey(String id) => "${widget.storageKey}.open.$id";
  String _heightKey(String id) => "${widget.storageKey}.height.$id";

  Future<void> _restore() async {
    var saved = await StorageManager.readString(_orderKey);
    var tabs = await StorageManager.readString(_tabKey);
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
        // "a+b,c" is two places: a and b as tabs, then c. An arrangement
        // saved before tabs existed is "a,b,c", which reads as three places
        // of one -- which is exactly what it was.
        var known = {for (var p in widget.panels) p.id};
        var taken = <String>{};
        var wanted = <List<String>>[];
        for (var group in saved.split(",")) {
          var ids = [
            for (var id in group.split("+"))
              if (known.contains(id) && taken.add(id)) id,
          ];
          if (ids.isNotEmpty) wanted.add(ids);
        }
        _groups = [
          ...wanted,
          for (var p in widget.panels)
            if (!taken.contains(p.id)) [p.id],
        ];
      }
      _selected.addAll(tabs.split(",").where((id) => id.isNotEmpty));
      _open.addAll(open);
      _heights.addAll(heights);
    });
  }

  bool _isOpen(String id) => _open[id] ?? true;

  void _toggle(String id) {
    setState(() => _open[id] = !_isOpen(id));
    StorageManager.saveData(_openKey(id), _open[id]);
  }

  /// _groupOf is which place a panel is in.
  int _groupOf(String id) => _groups.indexWhere((g) => g.contains(id));

  /// _activeIn is the tab a place is showing.
  String _activeIn(List<String> group) => group.firstWhere(
        _selected.contains,
        orElse: () => group.first,
      );

  void _select(String id) {
    var group = _groups[_groupOf(id)];
    setState(() {
      _selected.removeAll(group);
      _selected.add(id);
    });
    StorageManager.saveString(_tabKey, _selected.join(","));
  }

  /// _rearrange applies a drop: [id] goes above a place, below it, or into it
  /// as a tab.
  ///
  /// One function for the three, because they are one operation with a
  /// different destination -- and because taking a panel out of wherever it
  /// was has to happen exactly once however it lands.
  void _rearrange(String id, int place, _Drop drop) {
    if (place < 0 || place >= _groups.length) return;
    var from = _groupOf(id);
    if (from < 0) return;
    // Onto its own place, alone, is nothing at all.
    if (from == place && _groups[from].length == 1 && drop == _Drop.tab) return;

    setState(() {
      var groups = [
        for (var group in _groups) [...group]
      ];
      // The place being aimed at, by identity rather than by number: taking
      // the panel out below may shift every index after it.
      var target = groups[place];
      groups[from].remove(id);
      groups.removeWhere((g) => g.isEmpty);

      var at = groups.indexOf(target);
      if (at < 0) {
        // The place it was aimed at was the panel's own, and emptying it took
        // it away. Landing where it was is doing nothing.
        _groups = [
          for (var g in groups) g,
          if (!groups.any((g) => g.contains(id))) [id],
        ];
        return;
      }
      switch (drop) {
        case _Drop.above:
          groups.insert(at, [id]);
        case _Drop.below:
          groups.insert(at + 1, [id]);
        case _Drop.tab:
          target.add(id);
          // Shown straight away: dropping a panel onto another and having
          // nothing happen, because the one it joined is the one on top, is
          // indistinguishable from the drop not working.
          _selected.removeAll(target);
          _selected.add(id);
          // And open, or a panel tabbed into a shut place vanishes.
          _open[id] = true;
      }
      _groups = groups;
    });
    _saveArrangement();
  }

  /// _tabTo puts [id] beside [beside] in the same place, before or after it.
  void _tabTo(String id, String beside, {required bool after}) {
    if (id == beside) return;
    var place = _groupOf(beside);
    var from = _groupOf(id);
    if (place < 0 || from < 0) return;

    setState(() {
      var groups = [
        for (var group in _groups) [...group]
      ];
      var target = groups[place];
      groups[from].remove(id);
      groups.removeWhere((g) => g.isEmpty);
      var at = target.indexOf(beside);
      target.insert(after ? at + 1 : at, id);
      _selected.removeAll(target);
      _selected.add(id);
      _open[id] = true;
      _groups = groups;
    });
    _saveArrangement();
  }

  void _saveArrangement() {
    StorageManager.saveString(
        _orderKey, [for (var g in _groups) g.join("+")].join(","));
    StorageManager.saveString(_tabKey, _selected.join(","));
    for (var id in _order) {
      StorageManager.saveData(_openKey(id), _isOpen(id));
    }
  }

  /// _resize gives [by] pixels to the place above [id], taking them from the
  /// space the ones below it share.
  ///
  /// The place above rather than this one, because the edge being dragged is
  /// the boundary between the two and a boundary belongs to both. Moving it
  /// down makes the one above taller, which is what it looks like it does.
  ///
  /// [id] is a place's key: the first panel in it.
  void _resize(String id, double by) {
    var open = [
      for (var group in _groups)
        if (_isOpen(_activeIn(group))) group.first,
    ];
    var at = open.indexOf(id);
    if (at <= 0) return;
    var above = open[at - 1];

    setState(() {
      _heights[above] = math.max(_minBody, (_heights[above] ?? _share) + by);
    });
    StorageManager.saveData(_heightKey(above), _heights[above]);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var byId = {for (var p in widget.panels) p.id: p};

    // The arrangement as panels rather than as ids, with anything the stack
    // has forgotten about dropped.
    var places = [
      for (var group in _groups)
        [
          for (var id in group)
            if (byId[id] case var panel?) panel,
        ],
    ]..removeWhere((g) => g.isEmpty);
    if (places.isEmpty) return const SizedBox();

    var showing = [
      for (var place in places)
        place.firstWhere((p) => _selected.contains(p.id),
            orElse: () => place.first),
    ];
    var open = [
      for (var panel in showing)
        if (_isOpen(panel.id)) panel,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // What is left for the open panels once every header has had its row. A
      // place costs one header whether it holds one panel or four.
      var room = constraints.maxHeight -
          places.length * _headerHeight -
          math.max(0, places.length - 1) * _dividerHeight;
      var share = open.isEmpty ? 0.0 : math.max(_minBody, room / open.length);
      _share = share;

      return Column(children: [
        for (var (i, place) in places.indexed) ...[
          if (i > 0) _divider(theme, place.first),
          _header(theme, place, showing[i], i),
          if (_isOpen(showing[i].id))
            // The last open panel takes what is left rather than a remembered
            // height, so the column always fills the sidebar exactly and there
            // is never a strip of nothing at the bottom.
            if (showing[i].id == open.last.id)
              Expanded(child: _body(showing[i]))
            else
              SizedBox(
                // The place's height, not the tab's: a group of tabs is one
                // box that different panels take turns inside.
                height: math.min(
                    math.max(_minBody, _heights[place.first.id] ?? share),
                    math.max(_minBody, room)),
                child: _body(showing[i]),
              ),
        ],
      ]);
    });
  }

  Widget _body(CanvasStackPanel panel) => ClipRect(
        child: panel.body,
      );

  /// _divider is the line between two panels, and the grip that moves it.
  ///
  /// Between them rather than inside a header, which is where the grip used to
  /// be. A boundary is the thing being moved, so the boundary is the thing to
  /// take hold of -- and an icon in the header was a second small target in a
  /// band that is otherwise one big one.
  Widget _divider(ThemeNotifier theme, CanvasStackPanel below) => MouseRegion(
        // Named after the place below it, which is the one it belongs to and
        // is how a test takes hold of a boundary that is otherwise seven
        // pixels of nothing.
        key: ValueKey("panelDivider:${below.id}"),
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

  /// _header is a place's band: one panel's name, or a row of tabs.
  ///
  /// A DragTarget rather than a reorderable list. A list would move the
  /// panels' elements rather than rebuild them, which is how an overlay inside
  /// one gets re-attached mid-layout and takes the sidebar down with it -- and
  /// these panels are full of tooltips and menus. Dropping one header on
  /// another rebuilds both, which nothing minds.
  ///
  /// Three things can happen to a panel dropped on a header, and which one
  /// depends on where in the band the pointer is: above it, below it, or into
  /// it as a tab. The band says which as you hover -- a line at the edge it
  /// would go to, or the whole band lit for a tab -- because a drop that does
  /// one of three things without saying which is a drop nobody will risk.
  Widget _header(ThemeNotifier theme, List<CanvasStackPanel> place,
      CanvasStackPanel showing, int at) {
    // A Builder, so the callbacks below measure against *this header* rather
    // than against the whole stack. Handed the stack's own context they
    // measured the pointer's position down the sidebar and called everything
    // near the top "above", which turned every drop on the first panel into a
    // move.
    return Builder(
        builder: (context) =>
            _headerTarget(context, theme, place, showing, at));
  }

  Widget _headerTarget(BuildContext context, ThemeNotifier theme,
      List<CanvasStackPanel> place, CanvasStackPanel showing, int at) {
    return DragTarget<PanelDrag>(
      onWillAcceptWithDetails: (details) =>
          !(place.length == 1 && place.first.id == details.data.id),
      onMove: (details) {
        var drop = _dropAt(context, details.offset, at);
        if (_hovering != drop) setState(() => _hovering = drop);
      },
      onLeave: (_) => setState(() => _hovering = null),
      onAcceptWithDetails: (details) {
        var drop = _hovering?.$1 == at ? _hovering!.$2 : _Drop.tab;
        setState(() => _hovering = null);
        _rearrange(details.data.id, at, drop);
      },
      builder: (context, candidate, _) {
        var over = candidate.isNotEmpty && _hovering?.$1 == at;
        var drop = over ? _hovering!.$2 : null;
        return Stack(children: [
          Material(
            // Its own colour across the whole band, so a header is a header at
            // a glance rather than a line of small capitals floating above
            // some controls. A Material rather than a Container, so the ink
            // the InkWell draws -- the hover, the press -- lands on this
            // rather than on whatever is behind the sidebar.
            color: drop == _Drop.tab
                ? theme.colors.primary.withValues(alpha: 0.18)
                : theme.colors.surfaceContainerHighest,
            child: SizedBox(
              height: _headerHeight,
              child: place.length == 1
                  ? _oneName(theme, place.first)
                  : _tabs(theme, place, showing),
            ),
          ),
          // The edge it would land at. A line rather than a tint, because
          // "above this" and "into this" have to look like different answers.
          if (drop == _Drop.above || drop == _Drop.below)
            Positioned(
              left: 0,
              right: 0,
              top: drop == _Drop.above ? 0 : null,
              bottom: drop == _Drop.below ? 0 : null,
              child: Container(height: 3, color: theme.colors.primary),
            ),
        ]);
      },
    );
  }

  /// _dropAt works out which of the three a pointer is asking for.
  ///
  /// The top and bottom thirds move the panel to that side; the middle makes
  /// a tab. Thirds rather than halves so the middle -- the one that is a
  /// different kind of answer -- is the easiest to hit deliberately and the
  /// hardest to hit by accident.
  (int, _Drop)? _dropAt(BuildContext context, Offset global, int at) {
    var box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return (at, _Drop.tab);
    var y = box.globalToLocal(global).dy / math.max(1, box.size.height);
    if (y < 0.33) return (at, _Drop.above);
    if (y > 0.67) return (at, _Drop.below);
    return (at, _Drop.tab);
  }

  /// _oneName is the band of a place holding a single panel: the name, and the
  /// grip that carries it.
  Widget _oneName(ThemeNotifier theme, CanvasStackPanel panel) => InkWell(
        onTap: () => _toggle(panel.id),
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
                    color: theme.colors.onSurfaceVariant.withValues(alpha: 0.9),
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
      );

  /// _tabs is the band of a place holding several: one tab each, and nothing
  /// else.
  ///
  /// The names go small and the counts go, because four tabs in a sidebar two
  /// hundred pixels wide is all the room there is. What a tab has to say is
  /// which panel it is.
  Widget _tabs(ThemeNotifier theme, List<CanvasStackPanel> place,
          CanvasStackPanel showing) =>
      Row(
        children: [
          for (var (i, panel) in place.indexed)
            Flexible(
              child: _tab(theme, panel,
                  showing: panel.id == showing.id, last: i == place.length - 1),
            ),
        ],
      );

  /// _tab is one tab: a name that selects it, and a handle that is the tab
  /// itself.
  ///
  /// Pressing the one already showing shuts the place, and pressing it again
  /// opens it -- so a tab is the switch for the whole panel, the way a single
  /// panel's band is. Pressing a different one shows that panel instead, and
  /// opens the place if it was shut, because asking for a panel and being
  /// given a closed box is not an answer.
  Widget _tab(ThemeNotifier theme, CanvasStackPanel panel,
      {required bool showing, required bool last}) {
    var lit = showing && _isOpen(panel.id);
    var body = Container(
      height: _headerHeight,
      // More room after the name than before it, so the gap between one tab's
      // name and the next reads as a gap between tabs rather than as part of
      // the next one.
      padding: const EdgeInsets.only(left: 8, right: 12),
      decoration: BoxDecoration(
        color: lit ? theme.colors.surfaceContainerLow : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: lit ? theme.colors.primary : Colors.transparent,
            width: 2,
          ),
          // A line between one tab and the next. Shut, no tab is lit and
          // nothing else says where one ends -- three names in a row read as
          // one long heading with odd spacing.
          right: last
              ? BorderSide.none
              : BorderSide(
                  color: theme.colors.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(panel.icon,
            size: 13,
            color: theme.colors.onSurfaceVariant
                .withValues(alpha: lit ? 0.95 : 0.5)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            panel.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: theme.colors.onSurfaceVariant
                  .withValues(alpha: lit ? 0.95 : 0.55),
            ),
          ),
        ),
      ]),
    );

    // A target as well as a handle, so tabs are put in order by dragging one
    // past another -- left of the tab you drop on, or right of it.
    return DragTarget<PanelDrag>(
      onWillAcceptWithDetails: (details) => details.data.id != panel.id,
      onAcceptWithDetails: (details) {
        var box = context.findRenderObject();
        var after = false;
        if (box is RenderBox && box.hasSize) {
          after = box.globalToLocal(details.offset).dx > box.size.width / 2;
        }
        _tabTo(details.data.id, panel.id, after: after);
      },
      builder: (context, candidate, _) => MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<PanelDrag>(
          data: PanelDrag(panel.id),
          // The pointer, not the corner of the ghost: where a drop lands is
          // decided by which third of a header it is over, and a payload
          // measured from its own top-left answers for a place the pointer is
          // nowhere near.
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => setState(() => _dragging = panel.id),
          onDragEnd: (_) => setState(() {
            _dragging = null;
            _hovering = null;
          }),
          feedback: _carried(theme, panel),
          childWhenDragging: Opacity(opacity: 0.3, child: body),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (showing) {
                _toggle(panel.id);
                return;
              }
              _select(panel.id);
              if (!_isOpen(panel.id)) _toggle(panel.id);
            },
            child: Container(
              foregroundDecoration: candidate.isEmpty
                  ? null
                  : BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: theme.colors.primary, width: 2))),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  /// _carried is what a dragged panel looks like under the pointer.
  Widget _carried(ThemeNotifier theme, CanvasStackPanel panel) => Material(
        color: theme.colors.surfaceContainerHighest,
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(panel.label.toUpperCase(),
              style: const TextStyle(fontSize: 10, letterSpacing: 0.8)),
        ),
      );

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
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => setState(() => _dragging = panel.id),
        onDragEnd: (_) => setState(() {
          _dragging = null;
          _hovering = null;
        }),
        feedback: _carried(theme, panel),
        childWhenDragging: Opacity(opacity: 0.3, child: icon),
        child: icon,
      ),
    );
  }
}

/// _Drop is what would happen if the panel being carried were let go here.
enum _Drop { above, below, tab }
