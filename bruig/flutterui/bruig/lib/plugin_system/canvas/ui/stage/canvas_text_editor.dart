import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_text_editor.dart is the text field laid over a text element while it
// is written: a real TextField placed, transformed and styled like the
// element, so what is typed looks like what will be drawn. That holds only
// if the element's own text is not painted meanwhile, the field has no
// decoration or padding of its own, and the transform matches the stage's:
// scale, then rotation about the centre.

/// CanvasTextEditor is the field itself. It is given the element's rectangle
/// in stage pixels and the scale it is drawn at, so a canvas zoomed to 200%
/// is typed into at 200%.
class CanvasTextEditor extends StatefulWidget {
  final TextElement element;

  /// item is the extra piece being typed into, or null for the element's own
  /// paragraph. A piece has its own rectangle, so the box's padding is not
  /// applied: see textItemRects.
  final TextItem? item;

  /// rect is the element's box on the stage, unrotated.
  final Rect rect;

  /// scale is document units to stage pixels.
  final double scale;

  /// onChanged fires on every keystroke, so the size estimate and the layer
  /// list keep up.
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  const CanvasTextEditor({
    required this.element,
    this.item,
    required this.rect,
    required this.scale,
    required this.onChanged,
    required this.onDone,
    super.key,
  });

  @override
  State<CanvasTextEditor> createState() => _CanvasTextEditorState();
}

class _CanvasTextEditorState extends State<CanvasTextEditor> {
  /// The writing tools' controller adds the marks itself; with no provider
  /// enabled it behaves like a plain controller.
  late final TextEditingController _text = WritingTextEditingController(
      text: widget.item?.text ?? widget.element.text);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Fully selected on open, so typing replaces a new element's "Text".
    _focus.requestFocus();
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// _onFocus closes the editor when the focus goes elsewhere: one left open
  /// behind the next thing would keep swallowing keystrokes.
  void _onFocus() {
    if (!_focus.hasFocus) widget.onDone();
  }

  /// _room is the element's padding, which puts the editor where the words
  /// are drawn.
  EdgeInsets _room(TextElement e, double scale) => EdgeInsets.fromLTRB(
      e.box.padLeft * scale,
      e.box.padTop * scale,
      e.box.padRight * scale,
      e.box.padBottom * scale);

  @override
  Widget build(BuildContext context) {
    var e = widget.element;
    var item = widget.item;
    // The type it is drawn in (with Fit to box, not the type it is set in),
    // and a piece held to its slot's edge, so nothing moves as it is typed.
    var spec = item == null
        ? drawnTextSpec(e, e.bounds)
        : item.spec.copyWith(
            align: item.slot.across,
            verticalAlign: VerticalAlignSpec.top,
          );
    var scale = widget.scale;

    return Positioned(
      left: widget.rect.left,
      top: widget.rect.top,
      width: widget.rect.width,
      height: widget.rect.height,
      child: Transform.rotate(
        angle: e.rotationRadians,
        child: Padding(
          padding: item == null ? _room(e, scale) : EdgeInsets.zero,
          child: Align(
            alignment: switch (spec.verticalAlign) {
              VerticalAlignSpec.top => Alignment.topCenter,
              VerticalAlignSpec.middle => Alignment.center,
              VerticalAlignSpec.bottom => Alignment.bottomCenter,
            },
            child: Shortcuts(
              shortcuts: const {
                // Escape finishes; Enter starts a new line in the paragraph.
                SingleActivator(LogicalKeyboardKey.escape): _FinishIntent(),
              },
              child: Actions(
                actions: {
                  _FinishIntent: CallbackAction<_FinishIntent>(
                    onInvoke: (_) {
                      widget.onDone();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: null,
                  expands: false,
                  cursorColor: spec.color,
                  cursorWidth: 1.5,
                  textAlign: spec.align.flutter,
                  style: TextStyle(
                    fontFamily: spec.fontFamily,
                    fontSize: spec.fontSize * scale,
                    fontWeight: spec.fontWeight,
                    fontStyle:
                        spec.italic ? FontStyle.italic : FontStyle.normal,
                    letterSpacing: spec.letterSpacing * scale,
                    height: spec.lineHeight,
                    color: spec.color,
                  ),
                  decoration: const InputDecoration(
                    // No border, fill or content padding: the default inset
                    // would put every character off where it will be drawn.
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  // What an enabled writing capability offers for the text
                  // under the pointer, else the ordinary menu.
                  contextMenuBuilder: (context, editableTextState) =>
                      writingContextMenu(context, editableTextState,
                          fallbackItems:
                              editableTextState.contextMenuButtonItems),
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinishIntent extends Intent {
  const _FinishIntent();
}

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

/// CounterInput is the field a live counter's Set button opens in place of a
/// dialog that would cover the counter. Its value opens selected.
class CounterInput extends StatefulWidget {
  final double value;
  final int decimals;

  /// onDone hands back the number typed, or null to leave the counter alone.
  final ValueChanged<double?> onDone;

  const CounterInput({
    required this.value,
    required this.decimals,
    required this.onDone,
    super.key,
  });

  @override
  State<CounterInput> createState() => _CounterInputState();
}

class _CounterInputState extends State<CounterInput> {
  late final TextEditingController _field =
      TextEditingController(text: widget.value.toStringAsFixed(widget.decimals))
        ..selection = TextSelection(
            baseOffset: 0,
            extentOffset: widget.value.toStringAsFixed(widget.decimals).length);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// _read is the number typed, with the separators a counter writes (1,240)
  /// taken back out.
  double? _read() => double.tryParse(
      _field.text.trim().replaceAll(",", "").replaceAll(" ", ""));

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Focus(
      onFocusChange: (has) {
        if (!has) widget.onDone(null);
      },
      child: TextField(
        key: const ValueKey("counterInputField"),
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: TextStyle(color: theme.colors.onSurface, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.colors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => widget.onDone(_read()),
      ),
    );
  }
}
