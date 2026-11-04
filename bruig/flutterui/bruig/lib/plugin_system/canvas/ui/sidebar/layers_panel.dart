import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// layers_panel.dart is the layer list: what is on the canvas, top to bottom,
// as one of the Design column's panels (see design_panel.dart).

class CanvasLayersPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasLayersPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasWatch<String>(
        listenable: controller,
        // Only what the list shows: the controller notifies on every pixel of
        // a drag, which changes none of it.
        select: () => _shape(),
        builder: (context, _) => _layerList(),
      );

  /// _shape is everything the list is drawn from, as one string, so it can be
  /// compared with == on every notification (see CanvasWatch).
  String _shape() {
    var document = controller.document;
    // The background row's state too (style, colour, whether the shared
    // backdrop is off), or its eye keeps the state it was built with.
    var out = StringBuffer("${controller.backgroundSelected}"
        "|${document.ownBackground.spec.style.name}"
        "|${document.ownBackground.spec.background.toARGB32()}"
        "|${document.editingMaster}"
        "|${document.master?.backgroundOff}");
    for (var e in controller.document.elements) {
      out.write("|${e.id}:${e.name}:${e.visible}:${e.locked}:"
          "${controller.selection.contains(e.id)}");
    }
    return out.toString();
  }

  Widget _layerList() {
    var elements = controller.document.elements;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      children: [
        // Reversed: the document stores paint order (last is frontmost), and
        // the list shows what is on top at the top.
        for (var i = elements.length - 1; i >= 0; i--)
          // Sounds on the timeline are on its channels, not the canvas.
          if (!isTimelineSound(elements[i]))
            CanvasLayerRow(
              controller: controller,
              element: elements[i],
              index: i,
              key: ValueKey(elements[i].id),
            ),
        // The background is always the bottom row: it is painted before any
        // element and cannot be reordered.
        CanvasBackgroundLayerRow(controller: controller),
      ],
    );
  }
}

/// CanvasBackgroundLayerRow is the canvas's own background, shown as the
/// bottom layer, with no reorder or lock controls.
///
/// It can be switched off only on the shared canvas (a master that carries
/// just a logo, over scenes with their own backdrops); on an ordinary canvas
/// that would leave the editor's own colour showing.
class CanvasBackgroundLayerRow extends StatelessWidget {
  final CanvasController controller;
  const CanvasBackgroundLayerRow({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = controller.backgroundSelected;
    var document = controller.document;
    var spec = document.ownBackground.spec;
    var onMaster = document.editingMaster;
    var off = onMaster && document.master!.backgroundOff;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: selected ? theme.colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: controller.selectBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(children: [
              // A swatch of the background's own colour rather than an icon.
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: spec.background,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: theme.colors.outlineVariant),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  off
                      ? "Background — off, each scene shows its own"
                      : "Background — ${spec.style.label}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: off
                        ? theme.colors.onSurfaceVariant
                        : (selected
                            ? theme.colors.onSecondaryContainer
                            : theme.colors.onSurface),
                  ),
                ),
              ),
              if (onMaster)
                Tooltip(
                  message: off
                      ? "Use this backdrop on every scene"
                      : "Leave every scene its own backdrop. This one is kept.",
                  child: InkWell(
                    key: const ValueKey("masterBackgroundOff"),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => controller.setMasterBackgroundOff(!off),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        off ? Icons.visibility_off : Icons.visibility,
                        size: 15,
                        color: theme.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class CanvasLayerRow extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;
  final int index;

  const CanvasLayerRow({
    required this.controller,
    required this.element,
    required this.index,
    super.key,
  });

  @override
  State<CanvasLayerRow> createState() => _CanvasLayerRowState();
}

class _CanvasLayerRowState extends State<CanvasLayerRow> {
  CanvasController get controller => widget.controller;
  CanvasElement get element => widget.element;

  /// _renaming is the text field standing in for the name, or null. Held on
  /// the row so a rebuild from elsewhere cannot end an edit half way.
  TextEditingController? _renaming;
  final FocusNode _renameFocus = FocusNode();

  /// _lastPress is when the name was last pressed, for spotting a double
  /// click. Read off the pointer event, the gesture system's clock.
  Duration? _lastPress;

  /// _doubleClick is how soon a second press must follow: Flutter's
  /// kDoubleTapTimeout.
  static const Duration _doubleClick = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Clicking away commits, as every inline rename here does; Escape
    // leaves without saving (see _finishRename).
    _renameFocus.addListener(() {
      if (!_renameFocus.hasFocus && _renaming != null) _finishRename(true);
    });
  }

  @override
  void dispose() {
    _renaming?.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename() {
    setState(() => _renaming = TextEditingController(text: element.name));
    _renameFocus.requestFocus();
    _renaming!.selection =
        TextSelection(baseOffset: 0, extentOffset: element.name.length);
  }

  void _finishRename(bool keep) {
    var field = _renaming;
    if (field == null) return;
    var next = field.text.trim();
    setState(() => _renaming = null);
    field.dispose();

    // An empty name means "use the kind's label" in the model, so clearing
    // the field puts the default back.
    if (keep && next != element.name) {
      controller.replaceElement(element.withBase(name: next));
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = controller.selection.contains(element.id);
    var count = controller.document.elements.length;
    var index = widget.index;

    var row = Material(
      // Its own Material inside the list: the sidebar's let the highlight
      // spill over other sections and stay put when the list scrolled.
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => pickLayer(controller, element.id),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected ? theme.colors.secondaryContainer : null,
          ),
          child: Row(children: [
            Icon(
              iconForKind(element.kind),
              size: 15,
              color: selected
                  ? theme.colors.onSecondaryContainer
                  : theme.colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(child: _name(theme, selected)),
            // Buttons as well as the drag: they show the direction, reach the far
            // end of a long list, and are the only keyboard way to reorder.
            _rowButton(
                theme,
                Icons.keyboard_arrow_up,
                "Move forward",
                index < count - 1
                    ? () => controller
                        .apply(controller.document.reorder(index, index + 1))
                    : null),
            _rowButton(
                theme,
                Icons.keyboard_arrow_down,
                "Move back",
                index > 0
                    ? () => controller
                        .apply(controller.document.reorder(index, index - 1))
                    : null),
            _rowButton(
              theme,
              element.visible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              element.visible ? "Hide" : "Show",
              () => controller
                  .replaceElement(element.withBase(visible: !element.visible)),
            ),
            // Filled and tinted when locked, outlined when not: the two padlock
            // outlines were indistinguishable at this size.
            _rowButton(
              theme,
              element.locked ? Icons.lock : Icons.lock_open_outlined,
              element.locked ? "Unlock" : "Lock",
              () => controller
                  .replaceElement(element.withBase(locked: !element.locked)),
              active: element.locked,
            ),
            // Duplicate rather than copy, which changed nothing visible. Cmd-C
            // still copies.
            _rowButton(
              theme,
              Icons.control_point_duplicate_outlined,
              "Duplicate",
              () => controller.duplicateElement(element.id),
            ),
            // On the selected row only: a tablet has no Delete key.
            if (selected)
              _rowButton(
                theme,
                Icons.delete_outline,
                "Delete",
                element.locked
                    ? null
                    : () => controller.deleteElement(element.id),
                tapKey: "layerDelete-${element.id}",
              ),
          ]),
        ),
      ),
    );

    // A row being renamed is not draggable: the drag would take focus
    // from the field on the press.
    if (_renaming != null) return row;

    return _draggable(theme, row, index);
  }

  /// _name is the layer's name, or the field renaming it. Double-clicked to
  /// rename, rather than a sixth button on every row.
  Widget _name(ThemeNotifier theme, bool selected) {
    var colour = element.visible
        ? (selected
            ? theme.colors.onSecondaryContainer
            : theme.colors.onSurface)
        : theme.colors.onSurfaceVariant.withValues(alpha: 0.5);
    var style = TextStyle(fontSize: 12, color: colour);

    var field = _renaming;
    if (field != null) {
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CancelRenameIntent(),
        },
        child: Actions(
          actions: {
            _CancelRenameIntent: CallbackAction<_CancelRenameIntent>(
              onInvoke: (_) {
                _finishRename(false);
                return null;
              },
            ),
          },
          child: TextField(
            key: layerRenameFieldKey,
            controller: field,
            focusNode: _renameFocus,
            style: style,
            cursorHeight: 13,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 2),
              border: UnderlineInputBorder(),
            ),
            onSubmitted: (_) => _finishRename(true),
          ),
        ),
      );
    }

    // A Listener reading the clock rather than GestureDetector.onDoubleTap,
    // which holds the arena open for the double-tap window and so would
    // select every layer late. The Listener is out of the arena, so it
    // cannot fight the long press that picks the row up either.
    return Listener(
      onPointerDown: (event) {
        var previous = _lastPress;
        _lastPress = event.timeStamp;
        if (previous != null && event.timeStamp - previous < _doubleClick) {
          _lastPress = null;
          _startRename();
          return;
        }
        // On the press only a plain click: it is what a drag picks up. A
        // click with Cmd, Ctrl or Shift is the row's tap to deal with, or
        // the layer is toggled twice and ends where it started.
        var keys = HardwareKeyboard.instance;
        if (!keys.isMetaPressed &&
            !keys.isControlPressed &&
            !keys.isShiftPressed) {
          pickLayer(controller, element.id);
        }
      },
      child: Text(element.name, overflow: TextOverflow.ellipsis, style: style),
    );
  }

  /// _draggable makes the row something to pick up and drop on.
  ///
  /// A long press to start, so the list can still be scrolled past. Draggable
  /// rather than ReorderableListView, which moves a row by GlobalKey during
  /// layout and so cannot carry tooltips (a framework error).
  Widget _draggable(ThemeNotifier theme, Widget row, int index) {
    // What the pointer carries: the row's look, without its controls.
    Widget feedback() => Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: Container(
              width: 200,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: theme.colors.secondaryContainer,
              ),
              child: Row(children: [
                Icon(iconForKind(element.kind),
                    size: 15, color: theme.colors.onSecondaryContainer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(element.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colors.onSecondaryContainer)),
                ),
              ]),
            ),
          ),
        );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != element.id,
      onAcceptWithDetails: (details) {
        var from = controller.document.elements
            .indexWhere((e) => e.id == details.data);
        if (from < 0) return;
        controller.apply(controller.document.reorder(from, index));
        controller.selectOnly(details.data);
      },
      builder: (context, candidate, rejected) => Container(
        decoration: candidate.isEmpty
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.colors.primary, width: 1.5),
              ),
        child: LongPressDraggable<String>(
          data: element.id,
          feedback: feedback(),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        ),
      ),
    );
  }

  Widget _rowButton(ThemeNotifier theme, IconData icon, String tooltip,
          VoidCallback? onTap,
          {bool active = false, String? tapKey}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          key: tapKey == null ? null : ValueKey(tapKey),
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              icon,
              size: 14,
              color: onTap == null
                  ? theme.colors.onSurfaceVariant.withValues(alpha: 0.3)
                  : active
                      ? theme.colors.primary
                      : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}

/// layerRenameFieldKey names the field a layer is being renamed in, among
/// the many text fields of the settings beside it.
const Key layerRenameFieldKey = Key("canvasLayerRename");

/// _CancelRenameIntent is Escape, leaving the name as it was.
class _CancelRenameIntent extends Intent {
  const _CancelRenameIntent();
}

/// _layerAnchor is the layer last clicked on its own, where a Shift-click
/// runs a range from.
String? _layerAnchor;

/// pickLayer is a click on layer [id]: on its own, one layer; with Cmd or
/// Ctrl, that layer added or taken away; with Shift, every layer from the
/// one last clicked to this one.
void pickLayer(CanvasController controller, String id) {
  var keys = HardwareKeyboard.instance;
  if (keys.isMetaPressed || keys.isControlPressed) {
    controller.toggleSelected(id);
    _layerAnchor = id;
    return;
  }
  var anchor = _layerAnchor;
  var list = controller.document.elements;
  var from = anchor == null ? -1 : list.indexWhere((e) => e.id == anchor);
  var to = list.indexWhere((e) => e.id == id);
  if (keys.isShiftPressed && from >= 0 && to >= 0) {
    var lo = from < to ? from : to, hi = from < to ? to : from;
    controller.selectMany({for (var i = lo; i <= hi; i++) list[i].id});
    return;
  }
  controller.selectOnly(id);
  _layerAnchor = id;
}
