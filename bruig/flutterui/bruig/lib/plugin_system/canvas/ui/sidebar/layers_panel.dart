import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// layers_panel.dart is the Layers tab: what is on the canvas, and everything
// about whichever of it is selected.
//
// Its own tab rather than the bottom half of Design Elements, which is where
// the list started. The two answer different questions -- "what can I add" is
// asked once at the beginning, "what is already here and which of it am I
// looking at" is asked continuously -- and sharing a panel meant the layer
// list was always scrolled below a grid of things the reader had finished
// with.
//
// The panel is in two parts with a divider between them that can be dragged,
// and the lower part can be closed altogether. The list grows without limit --
// a football canvas is thirty layers -- and settings pushed off the bottom by
// it were settings that had to be scrolled back to after every selection.
// Splitting the height means both are on screen, and how the height is shared
// is the reader's call: a document being arranged wants the list, one being
// styled wants the settings, and one being arranged with the band's copy of
// the settings open wants no settings here at all.
//
// The settings themselves are shared with the Design Elements tab and with the
// band above the canvas -- see element_settings_pane.dart, which also holds the
// section that carries them. This tab remembers its own open state and its own
// height, independently of the other two.

class CanvasLayersPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasLayersPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasSettingsSplit(
        controller: controller,
        storageKey: "canvasLayers",
        top: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _layerList(),
        ),
      );

  Widget _layerList() {
    var elements = controller.document.elements;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      children: [
        CanvasSectionHeading("Layers (${elements.length + 1})"),
        // Reversed, so what is on top of the canvas is at the top of the list.
        // The document stores paint order, where the last element is the
        // frontmost; a list showing that order literally reads upside down to
        // anybody looking at the canvas.
        for (var i = elements.length - 1; i >= 0; i--)
          CanvasLayerRow(
            controller: controller,
            element: elements[i],
            index: i,
            key: ValueKey(elements[i].id),
          ),
        // The background is always the bottom row, because it is always behind
        // everything: it is painted before any element and cannot be reordered
        // into the middle of them. Showing it in the list at all is what makes
        // it findable -- it used to be reachable only by deselecting
        // everything and then noticing that the band had changed.
        CanvasBackgroundLayerRow(controller: controller),
      ],
    );
  }
}

/// CanvasBackgroundLayerRow is the canvas's own background, shown as the
/// bottom layer.
///
/// It is not an element and has no reorder, hide or lock controls -- there is
/// nowhere for it to move to, and a canvas whose background could be switched
/// off would just be showing the editor's own colour and looking broken.
/// Selecting it is the only thing it does.
class CanvasBackgroundLayerRow extends StatelessWidget {
  final CanvasController controller;
  const CanvasBackgroundLayerRow({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var selected = controller.backgroundSelected;
    var spec = controller.document.background.spec;

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
              // A swatch of the background's own colour rather than an icon:
              // it says which background this is, which matters as soon as
              // there is more than one document open in a day.
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
                  "Background — ${spec.style.label}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? theme.colors.onSecondaryContainer
                        : theme.colors.onSurface,
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

  /// _renaming is the text field standing in for the name, or null.
  ///
  /// Held on the row rather than on the panel, so that a rebuild caused by
  /// anything else on the canvas cannot end an edit half way through -- and so
  /// there is no chance of two rows believing they are the one being renamed.
  TextEditingController? _renaming;
  final FocusNode _renameFocus = FocusNode();

  /// _lastPress is when the name was last pressed, for spotting the second
  /// press of a double click. Read off the pointer event rather than the wall
  /// clock, so it is the same clock the gesture system is using.
  Duration? _lastPress;

  /// _doubleClick is how long a second press has to arrive within. Flutter's
  /// own kDoubleTapTimeout, which is what everything else double-clicked in
  /// this app is being judged by.
  static const Duration _doubleClick = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Clicking away commits, which is what every other inline rename in this
    // app does and what anybody expects of a field that appeared under the
    // pointer. Escape is the way out without saving -- see _finishRename.
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

    // An empty name is not a name, and it is also how the model says "use the
    // kind's label" -- so clearing the field puts the default back rather than
    // leaving a row with nothing written on it.
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

    var row = InkWell(
      onTap: () => controller.selectOnly(element.id),
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
          // The buttons stay, alongside the drag. They say which direction the
          // layer will go before it goes there, they reach a layer at the far
          // end of a long list without dragging the length of it, and they are
          // the only way to reorder with a keyboard.
          _rowButton(theme, Icons.keyboard_arrow_up, "Move forward",
              index < count - 1
                  ? () => controller.apply(
                      controller.document.reorder(index, index + 1))
                  : null),
          _rowButton(theme, Icons.keyboard_arrow_down, "Move back",
              index > 0
                  ? () => controller.apply(
                      controller.document.reorder(index, index - 1))
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
          // Filled and tinted when it is locked, outlined when it is not.
          // The pair used to be lock_outline and lock_open_outlined, which are
          // the same padlock with the shackle moved a couple of pixels -- at
          // fourteen pixels on a row of five icons the state was unreadable,
          // and locking something looked like it had done nothing.
          _rowButton(
            theme,
            element.locked ? Icons.lock : Icons.lock_open_outlined,
            element.locked ? "Unlock" : "Lock",
            () => controller
                .replaceElement(element.withBase(locked: !element.locked)),
            active: element.locked,
          ),
          // Duplicate rather than copy. A copy did nothing anybody could see:
          // the canvas was unchanged and the only evidence was that a paste
          // somewhere else would now produce this. What the button is reached
          // for is a second one of these, so it makes one. Cmd-C is still
          // there for a copy that is going somewhere.
          _rowButton(
            theme,
            Icons.control_point_duplicate_outlined,
            "Duplicate",
            () => controller.duplicateElement(element.id),
          ),
        ]),
      ),
    );

    // A row being renamed is not a row being dragged. The field would lose
    // focus to the drag the moment it was pressed, which is the one gesture
    // that must reach the text.
    if (_renaming != null) return row;

    return _draggable(theme, row, index);
  }

  /// _name is the layer's name, or the field that is renaming it.
  ///
  /// Double click rather than a pencil button. The list already carries five
  /// controls per row and a sixth for something done occasionally would be
  /// paying for it on every row -- and double-clicking a name is what renaming
  /// a thing in a list means everywhere else.
  Widget _name(ThemeNotifier theme, bool selected) {
    var colour = element.visible
        ? (selected ? theme.colors.onSecondaryContainer : theme.colors.onSurface)
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

    // A Listener reading the clock rather than GestureDetector.onDoubleTap.
    //
    // onDoubleTap holds the gesture arena open for the three hundred
    // milliseconds a second tap might arrive in, so every single click on a
    // layer name would have selected it a third of a second late -- and
    // selecting layers is what this list is mostly for. Here the first press
    // selects immediately and a second press soon after starts the rename,
    // which costs the click that opens the field nothing anybody notices.
    //
    // A Listener also stays out of the arena altogether, so it cannot get into
    // an argument with the long press that picks the row up.
    return Listener(
      onPointerDown: (event) {
        var previous = _lastPress;
        _lastPress = event.timeStamp;
        if (previous != null && event.timeStamp - previous < _doubleClick) {
          _lastPress = null;
          _startRename();
          return;
        }
        controller.selectOnly(element.id);
      },
      child: Text(element.name, overflow: TextOverflow.ellipsis, style: style),
    );
  }

  /// _draggable makes the row something to pick up and something to drop on.
  ///
  /// A long press to start, not a plain drag. The list scrolls and the canvas
  /// beside it drags, and a row that begins moving the moment a pointer
  /// travels across it is a row that cannot be scrolled past.
  ///
  /// Deliberately Draggable rather than ReorderableListView. That widget
  /// *moves* a row's element by GlobalKey instead of rebuilding it, and
  /// re-attaching an overlay that way during layout is a framework error --
  /// which is a problem for a row carrying five tooltips. See the Writing
  /// sidebar, which learnt this the hard way.
  Widget _draggable(ThemeNotifier theme, Widget row, int index) {
    // What the pointer carries: the row's own look, without the controls,
    // which are not part of what is being moved.
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
          VoidCallback? onTap, {bool active = false}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
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

/// layerRenameFieldKey names the field a layer is being renamed in. The
/// settings under this list are full of text fields, so "the text field" is
/// not enough to find it by.
const Key layerRenameFieldKey = Key("canvasLayerRename");

/// _CancelRenameIntent is Escape, leaving the name as it was.
class _CancelRenameIntent extends Intent {
  const _CancelRenameIntent();
}
