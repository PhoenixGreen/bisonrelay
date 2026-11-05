import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// customise_sidebars.dart is every sidebar at once, for setting them out: a
// column each, its panels as chips to drag between them or take away with
// their ×, and the panels taken away in a column of their own, each with a
// + that puts it back where it was. Sidebars are added, renamed, given an
// icon and taken away here, and the ones taken away put back.

/// showCustomiseSidebars opens the sheet. [read] is the layout as it is,
/// and [write] keeps a change: every change is kept as it is made.
Future<void> showCustomiseSidebars(
  BuildContext context, {
  required CanvasController controller,
  required SidebarLayout Function() read,
  required ValueChanged<SidebarLayout> write,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: SizedBox(
          width: 1000,
          child: CustomiseSidebars(
              controller: controller, read: read, write: write),
        ),
      ),
    );

/// CustomiseSidebars is the sheet's contents.
class CustomiseSidebars extends StatefulWidget {
  final CanvasController controller;
  final SidebarLayout Function() read;
  final ValueChanged<SidebarLayout> write;
  const CustomiseSidebars(
      {required this.controller,
      required this.read,
      required this.write,
      super.key});

  @override
  State<CustomiseSidebars> createState() => _CustomiseSidebarsState();
}

/// _hiddenColumn names the column of panels taken away, as a drop target.
const _hiddenColumn = "__hidden";

class _CustomiseSidebarsState extends State<CustomiseSidebars> {
  late SidebarLayout _layout = widget.read();

  void _set(SidebarLayout next) {
    widget.write(next);
    setState(() => _layout = next);
  }

  String _name(String panel) => sidebarPanelLabel(panel, widget.controller);

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Customise sidebars",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                "Press × to take a panel out of its sidebar, or drag it into "
                "“Not shown”. Drag panels between sidebars, and add a "
                "sidebar for a set you use together. The arrows on a sidebar "
                "move it along the row. Files and the settings always stay; "
                "the settings can move to another sidebar.",
                style:
                    TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
            const SizedBox(height: 14),
            SizedBox(
              height: 420,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var s in _layout.sidebars) _column(colors, s),
                      _hidden(colors),
                      _addColumn(colors),
                    ]),
              ),
            ),
            if (_layout.removed.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("Taken away:",
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                    for (var r in _layout.removed)
                      InputChip(
                        key: ValueKey("customiseRestore-${r.id}"),
                        avatar: Icon(sidebarIcon(r.icon), size: 15),
                        label: Text("${r.name}: put back"),
                        onPressed: () => _set(_layout.restoreSidebar(r.id)),
                      ),
                  ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              TextButton(
                key: const ValueKey("customiseReset"),
                onPressed: () => _set(_layout.asStarted),
                child: const Text("Back to the usual sidebars"),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey("customiseDone"),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Done"),
              ),
            ]),
          ]),
    );
  }

  /// _dropped is [panel] let go on column [into].
  void _dropped(String panel, String into) {
    if (into == _hiddenColumn) {
      _set(_layout.hidePanel(panel));
    } else if (_layout.hidden.contains(panel)) {
      _set(_layout.restorePanel(panel, into: into));
    } else {
      _set(_layout.movePanel(panel, into));
    }
  }

  Widget _target(String id, {required Widget child}) => DragTarget<String>(
        onWillAcceptWithDetails: (d) {
          if (id == _hiddenColumn) {
            return !requiredPanels.contains(d.data) &&
                !_layout.hidden.contains(d.data);
          }
          var s = _layout.byId(id);
          return s != null &&
              SidebarLayout.canGoIn(d.data, s) &&
              !s.panels.contains(d.data);
        },
        onAcceptWithDetails: (d) => _dropped(d.data, id),
        builder: (context, over, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: over.isNotEmpty
                    ? ThemeNotifier.of(context).colors.primary
                    : Colors.transparent,
                width: 2),
          ),
          child: child,
        ),
      );

  Widget _column(ColorScheme colors, SidebarSet s) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: _target(
          s.id,
          child: Container(
            key: ValueKey("customiseColumn-${s.id}"),
            width: 190,
            constraints: const BoxConstraints(minHeight: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IconButton(
                      key: ValueKey("customiseIcon-${s.id}"),
                      tooltip: s.fixed ? s.name : "Change the icon",
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: s.fixed
                          ? null
                          : () {
                              var i = sidebarIconNames.indexOf(s.icon);
                              _set(_layout.withIcon(
                                  s.id,
                                  sidebarIconNames[
                                      (i + 1) % sidebarIconNames.length]));
                            },
                      icon: Icon(sidebarIcon(s.icon)),
                    ),
                    Expanded(
                      child: s.fixed
                          ? Text(s.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12.5))
                          : TextFormField(
                              key: ValueKey("customiseName-${s.id}"),
                              initialValue: s.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12.5),
                              decoration: const InputDecoration(
                                  isDense: true, border: InputBorder.none),
                              onFieldSubmitted: (v) =>
                                  _set(_layout.renamed(s.id, v)),
                              onChanged: (v) {
                                if (v.trim().isNotEmpty) {
                                  _set(_layout.renamed(s.id, v));
                                }
                              },
                            ),
                    ),
                    // Along the row of sidebars: left or right one place.
                    for (var (dir, icon, tip) in [
                      (-1, Icons.chevron_left, "Move this sidebar left"),
                      (1, Icons.chevron_right, "Move this sidebar right"),
                    ])
                      IconButton(
                        key: ValueKey(
                            "customiseMove-${s.id}-${dir < 0 ? "left" : "right"}"),
                        tooltip: tip,
                        iconSize: 15,
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 26),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          var at = _layout.sidebars.indexOf(s) + dir;
                          if (at < 0 || at >= _layout.sidebars.length) return;
                          _set(_layout.moveSidebar(s.id, at));
                        },
                        icon: Icon(icon),
                      ),
                    if (!s.fixed)
                      IconButton(
                        key: ValueKey("customiseRemove-${s.id}"),
                        tooltip: "Take this sidebar away",
                        iconSize: 15,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _set(_layout.removeSidebar(s.id)),
                        icon: const Icon(Icons.close),
                      ),
                  ]),
                  const Divider(height: 10),
                  for (var p in s.panels)
                    _chip(colors, p,
                        movable: !s.gameOnly &&
                            !(s.fixed && requiredPanels.contains(p)),
                        removable: !requiredPanels.contains(p) && !s.gameOnly),
                  if (s.id == "files")
                    _note(
                        colors,
                        "Files and Presets stay here. Presets can "
                        "be taken away."),
                  if (s.gameOnly) _note(colors, "Shown only for a game."),
                ]),
          ),
        ),
      );

  Widget _hidden(ColorScheme colors) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: _target(
          _hiddenColumn,
          child: Container(
            key: const ValueKey("customiseHidden"),
            width: 190,
            constraints: const BoxConstraints(minHeight: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Text("Not shown",
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12.5)),
                  ),
                  const Divider(height: 10),
                  for (var p in _layout.hidden)
                    _chip(colors, p, movable: true, restorable: true),
                  if (_layout.hidden.isEmpty)
                    _note(
                        colors,
                        "Panels taken away land here. Press + on "
                        "one to put it back."),
                ]),
          ),
        ),
      );

  Widget _addColumn(ColorScheme colors) => SizedBox(
        width: 150,
        height: 140,
        child: OutlinedButton.icon(
          key: const ValueKey("customiseAdd"),
          onPressed: _layout.sidebars.length < maxSidebars
              ? () => _set(_layout.addSidebar())
              : null,
          icon: const Icon(Icons.add, size: 16),
          label: const Text("Add a sidebar"),
        ),
      );

  Widget _note(ColorScheme colors, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
      );

  Widget _chip(ColorScheme colors, String panel,
      {bool movable = true, bool removable = false, bool restorable = false}) {
    var face = Container(
      key: ValueKey("customiseChip-$panel"),
      height: 30,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        if (movable)
          Icon(Icons.drag_indicator, size: 13, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(_name(panel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5)),
        ),
        if (requiredPanels.contains(panel))
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text("needed",
                style:
                    TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant)),
          ),
        if (removable)
          IconButton(
            key: ValueKey("customiseHide-$panel"),
            tooltip: "Take ${_name(panel)} out of the sidebar",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(_layout.hidePanel(panel)),
            icon: const Icon(Icons.close),
          ),
        if (restorable)
          IconButton(
            key: ValueKey("customisePutBack-$panel"),
            tooltip: "Put ${_name(panel)} back where it was",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(_layout.restorePanel(panel)),
            icon: const Icon(Icons.add),
          ),
      ]),
    );
    if (!movable) return face;
    return Draggable<String>(
      data: panel,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 172, child: Opacity(opacity: 0.85, child: face)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: face),
      child: face,
    );
  }
}
