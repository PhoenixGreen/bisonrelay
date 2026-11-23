import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_cell_editor.dart is the field a table cell is typed into, laid over
// the cell where it is drawn.

/// CanvasCellEditor is one table cell, opened for typing where it is drawn.
///
/// A plain field rather than CanvasTextEditor: a cell wants a slot the size
/// of the cell with a visible edge, since an invisible field inside the
/// cell's rules cannot be told from the table.
class CanvasCellEditor extends StatefulWidget {
  final String value;
  final double fontSize;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  /// onPickPicture puts a picture in this cell instead of words. It returns
  /// a Future so it is awaited: unawaited, an exception in it would be lost.
  final Future<void> Function() onPickPicture;

  const CanvasCellEditor({
    required this.value,
    required this.fontSize,
    required this.onChanged,
    required this.onDone,
    required this.onPickPicture,
    super.key,
  });

  @override
  State<CanvasCellEditor> createState() => _CanvasCellEditorState();
}

class _CanvasCellEditorState extends State<CanvasCellEditor> {
  /// A table cell gets the writing tools' marks too.
  late final TextEditingController _text =
      WritingTextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Selected: a cell is opened to be replaced more often than appended to.
    _focus.requestFocus();
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.value.length);
    _focus.addListener(() {
      // Not while the file picker is up: opening it takes the focus from the
      // field, and closing the editor then would cancel the tap that opened it.
      if (!_focus.hasFocus && !_picking) widget.onDone();
    });
  }

  /// _picking is whether the picture button has been pressed. Set on pointer
  /// down, since the field loses focus (closing this editor) before a tap
  /// completes; and not in setState, as a mid-gesture rebuild can lose it.
  bool _picking = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _CloseCellIntent(),
      },
      child: Actions(
        actions: {
          _CloseCellIntent: CallbackAction<_CloseCellIntent>(
            onInvoke: (_) {
              widget.onDone();
              return null;
            },
          ),
        },
        child: Material(
          color: theme.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: BorderSide(color: theme.colors.primary, width: 1.5),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                style: TextStyle(
                    fontSize: widget.fontSize.clamp(9, 40),
                    color: theme.colors.onSurface),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                ),
                // The same menu the headline above it gets.
                contextMenuBuilder: (context, editableTextState) =>
                    writingContextMenu(context, editableTextState,
                        fallbackItems:
                            editableTextState.contextMenuButtonItems),
                onChanged: widget.onChanged,
                onSubmitted: (_) => widget.onDone(),
              ),
            ),
            Tooltip(
              message: "Put a picture in this cell",
              // A Listener: an InkWell takes the field's focus, and onTapDown
              // fires after the arena settles, once the editor is closing.
              child: Listener(
                onPointerDown: (_) => _picking = true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapCancel: () => _picking = false,
                  onTap: () async {
                    _picking = true;
                    try {
                      await widget.onPickPicture();
                    } catch (exception) {
                      debugPrint("Unable to put a picture in the cell: "
                          "$exception");
                    }
                    _picking = false;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.add_photo_alternate_outlined,
                        size: 15, color: theme.colors.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CloseCellIntent extends Intent {
  const _CloseCellIntent();
}
