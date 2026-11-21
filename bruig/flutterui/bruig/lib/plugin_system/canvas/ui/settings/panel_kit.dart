import 'dart:ui' as ui;
import 'dart:collection';
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show GestureBinding, PointerRemovedEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'panel_kit_steppers.dart';
part 'panel_kit_tiles.dart';
part 'panel_kit_hold.dart';

// panel_kit.dart is the sectioned settings panel's parts: folding sections,
// picture tiles, tools, the stepper. Element-agnostic; see
// settings/README.md for the rows inside a section. The stepper and sides
// field are in panel_kit_steppers.dart, the tiles and tool tiles in
// panel_kit_tiles.dart.

/// CanvasKept is [builder]'s widget, rebuilt only when [deps] or inherited
/// state change, as Flutter skips an unchanged subtree. Pass everything it
/// shows; handlers must read current state, as a kept widget's callbacks
/// are kept too.
class CanvasKept extends StatefulWidget {
  final List<Object?> deps;
  final WidgetBuilder builder;
  const CanvasKept({required this.deps, required this.builder, super.key});

  @override
  State<CanvasKept> createState() => _CanvasKeptState();
}

class _CanvasKeptState extends State<CanvasKept> {
  Widget? _built;
  List<Object?> _deps = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  Widget build(BuildContext context) {
    var deps = widget.deps;
    var same = _built != null && deps.length == _deps.length;
    for (var i = 0; same && i < deps.length; i++) {
      same = identical(deps[i], _deps[i]) || deps[i] == _deps[i];
    }
    if (!same) {
      _built = widget.builder(context);
      _deps = List.of(deps);
    }
    return _built!;
  }
}

class CanvasSections extends StatefulWidget {
  final List<Widget> children;

  /// parts is what the element is made of (a picture's layers), over the
  /// sections and menu bar; not a section.
  final Widget? parts;

  /// quick is the most-changed settings, over the sections (CanvasQuickStrip).
  final Widget? quick;

  const CanvasSections({
    required this.children,
    this.parts,
    this.quick,
    super.key,
  });

  @override
  State<CanvasSections> createState() => _CanvasSectionsState();
}

/// settingsAsMenu shows element settings as a menu (one section at a time)
/// instead of folding sections; kept (see toggleSettingsLayout).
final ValueNotifier<bool> settingsAsMenu = ValueNotifier(false);

bool _layoutRead = false;

/// readSettingsLayout reads the kept layout, once.
void readSettingsLayout() {
  if (_layoutRead) return;
  _layoutRead = true;
  StorageManager.readData("canvasSettingsMenu").then((v) {
    if (v is bool) settingsAsMenu.value = v;
  });
  StorageManager.readData("canvasSettingsMenuTab").then((v) {
    if (v is String && _menuChosen == null) _menuChosen = v;
  });
}

/// toggleSettingsLayout swaps the layout and keeps it.
void toggleSettingsLayout() {
  settingsAsMenu.value = !settingsAsMenu.value;
  StorageManager.saveData("canvasSettingsMenu", settingsAsMenu.value);
}

/// _menuChosen is the last menu section as "remember|title": that one, else
/// one of the same name, else the first.
String? _menuChosen;

/// _MenuItem is one section in the menu: name, "?", whether it can reset;
/// [state] is the section, for reset and action.
class _MenuItem {
  final String remember;
  final String title;
  final IconData icon;
  final bool changed;
  final String help;
  final bool resets;
  final Widget? action;
  final _CanvasSectionState? state;
  const _MenuItem(this.remember, this.title, this.icon, this.changed,
      {this.help = "", this.resets = false, this.action, this.state});

  /// Equal whatever its [action], a new widget each build.
  @override
  bool operator ==(Object other) =>
      other is _MenuItem &&
      other.remember == remember &&
      other.title == title &&
      other.icon == icon &&
      other.changed == changed &&
      other.help == help &&
      other.resets == resets;

  @override
  int get hashCode => Object.hash(remember, title, icon, changed, help, resets);
}

/// _MenuScope tells the sections under a menu which is chosen. [owner] null
/// is no menu: a section inside a chosen section's body draws as a section.
class _MenuScope extends InheritedWidget {
  final _CanvasSectionsState? owner;
  final String? active;
  const _MenuScope(
      {required this.owner, required this.active, required super.child});

  static _MenuScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MenuScope>();

  @override
  bool updateShouldNotify(_MenuScope old) =>
      old.active != active || old.owner != owner;
}

class _CanvasSectionsState extends State<CanvasSections> {
  /// _items is the menu's sections, found after a frame, not read off
  /// [CanvasSections.children], as a background's are built deep inside.
  List<_MenuItem> _items = const [];
  bool _looking = false;
  final ScrollController _bar = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  final GlobalKey _barView = GlobalKey();
  String? _shown;

  /// _scroll is the panel's scroll, followed by _follow.
  ScrollPosition? _scroll;

  /// _stick is how far down the bar is drawn to stay at the panel's top.
  double _stick = 0;
  final GlobalKey _under = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var next = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (next != _scroll) {
      _scroll?.removeListener(_follow);
      _scroll = next;
      _scroll?.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _scroll?.removeListener(_follow);
    _bar.dispose();
    super.dispose();
  }

  /// _barRoom is the bar's height and the room round it.
  static const double _barRoom = 38 + 2 + 6;

  /// _follow keeps the bar at the panel's top while its sections scroll.
  void _follow() {
    var place = _under.currentContext?.findRenderObject();
    var view = Scrollable.maybeOf(context, axis: Axis.vertical)
        ?.context
        .findRenderObject();
    if (place is! RenderBox || view is! RenderBox || !place.attached) return;
    var top = place.localToGlobal(Offset.zero, ancestor: view).dy;
    var most = math.max(0.0, place.size.height - _barRoom);
    var stick = (-top).clamp(0.0, most).toDouble();
    if ((stick - _stick).abs() > 0.25 && mounted) {
      setState(() => _stick = stick);
    }
  }

  /// _look finds the sections, after this frame.
  void _look() {
    if (_looking) return;
    _looking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looking = false;
      if (!mounted) return;
      var found = <_MenuItem>[];
      void visit(Element e) {
        if (e is StatefulElement && e.state is _CanvasSectionState) {
          var state = e.state as _CanvasSectionState;
          var w = state.widget;
          found.add(_MenuItem(w.remember, w.title, w.icon, w.changes > 0,
              help: state._help,
              resets: w.onReset != null,
              action: w.action,
              state: state));
          return;
        }
        e.visitChildren(visit);
      }

      context.visitChildElements(visit);
      if (!listEquals(found, _items)) {
        setState(() => _items = found);
      } else {
        // The same sections: their newest actions, shown next build.
        _items = found;
      }
    });
  }

  /// _active is the section to show among [_items].
  String? get _active {
    if (_items.isEmpty) return null;
    var chosen = _menuChosen;
    if (chosen != null) {
      var bar = chosen.indexOf("|");
      var remember = bar < 0 ? chosen : chosen.substring(0, bar);
      var title = bar < 0 ? "" : chosen.substring(bar + 1);
      for (var i in _items) {
        if (i.remember == remember) return i.remember;
      }
      for (var i in _items) {
        if (i.title == title) return i.remember;
      }
      // Position (older panels) and Layout are the same section.
      var same = const {"Position": "Layout", "Layout": "Position"}[title];
      for (var i in _items) {
        if (i.title == same) return i.remember;
      }
    }
    return _items.first.remember;
  }

  final _parts = _HeldBody(), _quick = _HeldBody();

  /// _kept is the parts row or the quick strip, kept as a section is while
  /// a pointer is held in a gesture elsewhere (see PanelHold).
  Widget _kept(String key, _HeldBody held, Widget child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => PanelHoldScope.of(context)?.claim(e.pointer, key),
        child: held.of(context, key, () => child),
      );

  void _choose(_MenuItem item) {
    _menuChosen = "${item.remember}|${item.title}";
    StorageManager.saveData("canvasSettingsMenuTab", _menuChosen);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: settingsAsMenu,
      builder: (context, menu, _) {
        if (!menu) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.parts != null) _kept("parts", _parts, widget.parts!),
              if (widget.quick != null) _kept("quick", _quick, widget.quick!),
              ...widget.children,
            ],
          );
        }
        _look();
        var active = _active;
        // Once the section is laid out, the bar goes back where it belongs.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow();
        });
        // The bar drawn after the sections, so they scroll under it.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.parts != null) _kept("parts", _parts, widget.parts!),
            if (widget.quick != null) _kept("quick", _quick, widget.quick!),
            Stack(key: _under, children: [
              Padding(
                padding: const EdgeInsets.only(top: _barRoom),
                child: _MenuScope(
                  owner: this,
                  active: active,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.children,
                  ),
                ),
              ),
              Positioned(
                top: _stick,
                left: 0,
                right: 0,
                child: _menuBar(context, active),
              ),
            ]),
          ],
        );
      });

  /// _menuBar is the menu: section names in a scrolling line, the chosen one
  /// bold and underlined, its "?", action and reset at the end.
  Widget _menuBar(BuildContext context, String? active) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    // The chosen one scrolled into view, once each time it changes.
    if (active != null && active != _shown) {
      _shown = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Sideways only: ensureVisible would scroll the panel too.
        var tab = _tabKeys[active]?.currentContext?.findRenderObject();
        var view = _barView.currentContext?.findRenderObject();
        if (tab is! RenderBox || view is! RenderBox || !_bar.hasClients) {
          return;
        }
        var left = tab.localToGlobal(Offset.zero, ancestor: view).dx;
        var right = left + tab.size.width;
        var width = view.size.width, now = _bar.offset;
        var target = left < 0
            ? now + left
            : right > width
                ? now + right - width
                : now;
        _bar.jumpTo(target.clamp(0.0, _bar.position.maxScrollExtent));
      });
    }
    Widget tab(_MenuItem item) {
      var on = item.remember == active;
      return InkWell(
        key: _tabKeys.putIfAbsent(item.remember, () => GlobalKey()),
        onTap: () => _choose(item),
        child: Container(
          key: ValueKey("menuTab-${item.remember}"),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: on ? accent : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(item.title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? theme.colors.onSurface : muted)),
            if (item.changed)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(left: 5, bottom: 6),
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
          ]),
        ),
      );
    }

    var chosen = _items.where((i) => i.remember == active).firstOrNull;
    var section = chosen?.state;
    var trailing = <Widget>[
      if (chosen != null && chosen.help.isNotEmpty)
        CanvasHint(chosen.help, round: true),
      if (chosen?.action case var action?) action,
      if (chosen != null && chosen.changed && chosen.resets)
        CanvasIconButton(
          key: ValueKey("sectionReset-${chosen.remember}"),
          tight: true,
          icon: Icons.restart_alt,
          tooltip: "Reset ${chosen.title}",
          onPressed: () => section?.widget.onReset?.call(),
        ),
    ];
    return Container(
      key: const ValueKey("settingsMenu"),
      height: 38,
      // Close to the first setting: the bar names the section.
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Row(children: [
        Expanded(
            child: ClipRRect(
          key: _barView,
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            controller: _bar,
            scrollDirection: Axis.horizontal,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var item in _items)
                Material(
                  type: MaterialType.transparency,
                  child: tab(item),
                ),
            ]),
          ),
        )),
        for (var t in trailing)
          Padding(padding: const EdgeInsets.only(right: 6), child: t),
      ]),
    );
  }
}

/// CanvasSection is one subject of an element's settings as a folding card:
/// shut, an icon, name and summary line. [changes] adds a dot and, open, a
/// reset. Open, its contents are cards (see CanvasCards).
class CanvasSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String summary;

  /// scope is a tag beside the title ("Whole image" on a layer's frame).
  final String? scope;

  final int changes;
  final VoidCallback? onReset;

  /// action is a heading button outside the fold (a table's Refresh).
  final Widget? action;

  /// remember names where its open state is kept, as CanvasExpander's.
  final String remember;
  final bool initiallyOpen;

  /// forceOpen opens it whenever it turns true, as a held tool does.
  final bool forceOpen;
  final List<Widget> children;

  /// glyph is drawn instead of [icon] (see SectionGlyph).
  final SectionGlyph? glyph;

  /// followsStage marks a section that shows where the element is (its
  /// place and size): built on every step of a drag on the canvas, where
  /// the others are kept (see PanelHold).
  final bool followsStage;

  const CanvasSection({
    required this.icon,
    this.glyph,
    required this.title,
    required this.remember,
    required this.children,
    this.summary = "",
    this.scope,
    this.changes = 0,
    this.onReset,
    this.action,
    this.initiallyOpen = false,
    this.forceOpen = false,
    this.followsStage = false,
    super.key,
  });

  /// openAll starts every section open, for tests of what controls do.
  @visibleForTesting
  static bool openAll = false;

  /// forced is [forceOpen], or a forced section inside: a tool in a
  /// picture's Retouch opens its Look, or picks its tab in the menu.
  bool get forced => forceOpen || children.any(_forces);

  static bool _forces(Widget w) => switch (w) {
        CanvasSection s => s.forced,
        Column c => c.children.any(_forces),
        _ => false,
      };

  @override
  State<CanvasSection> createState() => _CanvasSectionState();
}

/// _FollowsStage tells the sections under it whether the section they are
/// in follows the canvas (CanvasSection.followsStage).
class _FollowsStage extends InheritedWidget {
  final bool follows;
  const _FollowsStage({required this.follows, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_FollowsStage>()?.follows ?? false;

  @override
  bool updateShouldNotify(_FollowsStage old) => false;
}

class _CanvasSectionState extends State<CanvasSection> {
  final _held = _HeldBody();

  /// _body is the section's controls: kept as they were while a pointer is
  /// held in a gesture elsewhere (see PanelHold).
  ///
  /// A section inside one that follows the canvas follows it too (a
  /// picture's Position, inside Layout): kept, it would show the place the
  /// element was dragged from while its parent showed where it is.
  Widget _body() {
    var follows = widget.followsStage || _FollowsStage.of(context);
    return _held.of(
        context,
        widget.remember,
        () => _FollowsStage(
              follows: follows,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c in widget.children)
                    if (c is! CanvasHint) c
                ],
              ),
            ),
        followsStage: follows);
  }

  late bool _open = CanvasSection.openAll ||
      (rememberedSection(widget.remember) ?? widget.initiallyOpen);

  @override
  void initState() {
    super.initState();
    if (widget.forced) {
      _open = true;
    } else if (!CanvasSection.openAll &&
        rememberedSection(widget.remember) == null) {
      restoreSection(widget.remember, (open) {
        if (mounted) setState(() => _open = open);
      });
    }
  }

  @override
  void didUpdateWidget(CanvasSection old) {
    super.didUpdateWidget(old);
    var forced = widget.forced && !old.forced;
    if (forced && !_open) {
      _open = true;
      keepSection(widget.remember, true);
    }
    // In the menu, a tool taken up shows its section, as it opens it here.
    if (forced) {
      var owner = _MenuScope.of(context)?.owner;
      if (owner != null) {
        var item = _MenuItem(
            widget.remember, widget.title, widget.icon, widget.changes > 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (owner.mounted) owner._choose(item);
        });
      }
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    keepSection(widget.remember, _open);
  }

  /// _help is the section's own hints, said once by its heading's "?".
  String get _help => [
        for (var c in widget.children)
          if (c is CanvasHint) c.message
      ].join("\n\n");

  /// _heading is icon, name, summary, and a reset when open and changed.
  Widget _heading(ThemeNotifier theme, bool open, bool changed) {
    var dense = CanvasDense.on(context);
    var accent = theme.colors.primary;
    var muted = theme.colors.onSurfaceVariant;
    return Row(children: [
      Expanded(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey("section-${widget.remember}"),
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(dense ? 8 : 9),
                    color: open && !dense
                        ? accent.withValues(alpha: 0.16)
                        : theme.colors.surfaceContainerHighest,
                  ),
                  child: widget.glyph != null
                      ? CustomPaint(
                          painter: _GlyphPainter(widget.glyph!, muted))
                      : Icon(widget.icon,
                          size: 16, color: open && !dense ? accent : muted),
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
                                  fontSize: dense ? 14 : 12.5,
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
                                style: TextStyle(fontSize: 10, color: muted)),
                          ),
                        ],
                      ]),
                      if (widget.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(widget.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: dense ? 12 : 10.5, color: muted)),
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
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
              ]),
            ),
          ),
        ),
      ),
      // Outside the heading's ink, so pressing them does not fold it.
      if (_help.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CanvasHint(_help, round: true),
        ),
      if (widget.action != null)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: widget.action!,
        ),
      if (open && changed && widget.onReset != null)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CanvasIconButton(
            key: ValueKey("sectionReset-${widget.remember}"),
            tight: true,
            icon: Icons.restart_alt,
            tooltip: "Reset ${widget.title}",
            onPressed: () => widget.onReset?.call(),
          ),
        ),
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey("sectionFold-${widget.remember}"),
          borderRadius: BorderRadius.circular(8),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
            child: AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(Icons.chevron_right, size: 20, color: muted),
            ),
          ),
        ),
      ),
    ]);
  }

  /// _menuBody is the chosen section in the menu: contents only, its name,
  /// "?", action and reset being in the bar.
  Widget _menuBody() => RepaintBoundary(
        // A section inside this one is a section again, not a menu item.
        child: _MenuScope(
          owner: null,
          active: null,
          child: CanvasCards(
            title: widget.title,
            child: Padding(
              key: ValueKey("sectionBody-${widget.remember}"),
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: _body(),
            ),
          ),
        ),
      );

  /// _nested is a section inside another's cards: a fold keeping summary,
  /// dot, reset, "?", action and tool-opening (Retouch inside Look).
  Widget _nested(ThemeNotifier theme) {
    var muted = theme.colors.onSurfaceVariant;
    var open = _open;
    var changed = widget.changes > 0;
    return canvasCard(context,
        title: Row(children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey("section-${widget.remember}"),
                borderRadius: BorderRadius.circular(6),
                onTap: _toggle,
                child: Row(children: [
                  AnimatedRotation(
                    key: ValueKey("sectionFold-${widget.remember}"),
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Icon(Icons.chevron_right, size: 18, color: muted),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: canvasCardTitle(context, widget.title)),
                  ),
                  if (widget.scope != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: theme.colors.outlineVariant),
                      ),
                      child: Text(widget.scope!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 10, color: muted)),
                    ),
                  ],
                  if (widget.summary.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(widget.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: muted)),
                    ),
                  ],
                  if (changed)
                    Container(
                      key: ValueKey("sectionChanged-${widget.remember}"),
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                          color: theme.colors.primary, shape: BoxShape.circle),
                    ),
                ]),
              ),
            ),
          ),
          if (_help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CanvasHint(_help, round: true),
            ),
          if (widget.action != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: widget.action!,
            ),
          if (open && changed && widget.onReset != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CanvasIconButton(
                key: ValueKey("sectionReset-${widget.remember}"),
                tight: true,
                icon: Icons.restart_alt,
                tooltip: "Reset ${widget.title}",
                onPressed: () => widget.onReset?.call(),
              ),
            ),
        ]),
        body: !open
            ? const SizedBox.shrink()
            // Its own name for the cards inside, so the fold's is not repeated.
            : CanvasCards(
                title: widget.title,
                child: KeyedSubtree(
                  key: ValueKey("sectionBody-${widget.remember}"),
                  child: _body(),
                ),
              ));
  }

  @override
  Widget build(BuildContext context) => Listener(
        // A pointer going down here makes this section the live one while
        // it is held: see PanelHold.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) =>
            PanelHoldScope.of(context)?.claim(e.pointer, widget.remember),
        child: _section(context),
      );

  Widget _section(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // Under a menu, only the section chosen is drawn, and drawn open.
    var menu = _MenuScope.of(context);
    if (menu?.owner case var owner?) {
      owner._look();
      if (menu!.active != widget.remember) return const SizedBox.shrink();
      return _menuBody();
    }
    // Inside another section: a fold among its cards.
    if (CanvasCards.on(context)) return _nested(theme);
    var open = _open;
    var changed = widget.changes > 0;
    // Painted on its own, so one changed section repaints alone.
    return RepaintBoundary(
        child: Container(
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
          // The heading is kept unless its text changes: it was half the work.
          CanvasKept(
            deps: [
              widget.icon,
              widget.title,
              widget.summary,
              widget.scope,
              changed,
              open,
              widget.onReset != null,
              _help,
              widget.action,
              theme.colors,
            ],
            builder: (context) => _heading(theme, open, changed),
          ),
          if (open)
            CanvasCards(
              title: widget.title,
              child: Padding(
                key: ValueKey("sectionBody-${widget.remember}"),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: _body(),
              ),
            ),
        ],
      ),
    ));
  }
}

void forgetPanelsForTest() {
  TileSnapshot.letGo();
  _lastIn.clear();
  _unlinked.clear();
  settingsAsMenu.value = false;
  CanvasSection.openAll = false;
}

/// SectionGlyph is a section icon: content, look, layout, motion, more.
enum SectionGlyph { content, look, layout, motion, more }

/// _GlyphPainter draws [glyph] from its 24-unit SVG paths, stroked 1.8 wide
/// with round ends, in a 16-pixel square at the box's middle.
class _GlyphPainter extends CustomPainter {
  final SectionGlyph glyph;
  final Color colour;
  const _GlyphPainter(this.glyph, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate((size.width - 16) / 2, (size.height - 16) / 2);
    canvas.scale(16 / 24);
    var line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void seg(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), line);
    switch (glyph) {
      case SectionGlyph.content:
        seg(5, 6, 19, 6);
        seg(5, 11, 19, 11);
        seg(5, 16, 14, 16);
      case SectionGlyph.look:
        canvas.drawPath(
            Path()
              ..moveTo(12, 3)
              ..lineTo(14.5, 8.5)
              ..lineTo(20, 9)
              ..lineTo(16, 13)
              ..lineTo(17, 19)
              ..lineTo(12, 16)
              ..lineTo(7, 19)
              ..lineTo(8, 13)
              ..lineTo(4, 9)
              ..lineTo(9.5, 8.5)
              ..close(),
            line);
      case SectionGlyph.layout:
        canvas.drawRRect(
            RRect.fromLTRBR(4, 4, 20, 20, const Radius.circular(2)), line);
        seg(4, 10, 20, 10);
        seg(10, 10, 10, 20);
      case SectionGlyph.motion:
        seg(3, 12, 7, 12);
        seg(3, 7, 10, 7);
        seg(3, 17, 10, 17);
        canvas.drawCircle(const Offset(16, 12), 4, line);
      case SectionGlyph.more:
        var dot = Paint()..color = colour;
        for (var x in [6.0, 12.0, 18.0]) {
          canvas.drawCircle(Offset(x, 12), 1.6, dot);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.colour != colour;
}
