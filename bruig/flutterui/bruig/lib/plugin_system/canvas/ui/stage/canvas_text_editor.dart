import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_text_editor.dart is the text field that appears over a text element
// while it is being written.
//
// A canvas is painted, not laid out, so there is nothing on screen to type
// into. What goes over the top is a real TextField, positioned on the
// element, transformed the same way and styled from the same TextSpec, so
// what is typed looks like what will be drawn.
//
// The illusion has three requirements, all easy to lose:
//
//   the element's own text is not painted while this is open, or the words
//   appear twice, half a pixel apart;
//   the field has no decoration, no fill and no cursor padding of its own;
//   and the transform matches the stage's exactly: scale, then rotation
//   about the centre, in that order.

/// CanvasTextEditor is the field itself, in the element's own coordinates.
/// It is given the element's rectangle in stage pixels and the scale it is
/// drawn at, so a canvas zoomed to 200% is typed into at 200%.
class CanvasTextEditor extends StatefulWidget {
  final TextElement element;

  /// item is the one of the element's extra pieces being typed into, or null
  /// for the element's own paragraph. A piece has its own words, type and
  /// rectangle, so the box's padding and an icon's room are not applied: see
  /// textItemRects.
  final TextItem? item;

  /// rect is where the element's box is on the stage, unrotated.
  final Rect rect;

  /// scale is document units to stage pixels.
  final double scale;

  /// onChanged fires on every keystroke, so the size estimate and the layer
  /// list keep up. onDone closes the editor.
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
  /// The writing tools' controller, which is all it takes to get the marks:
  /// it composes the styled text itself and reads the capability from the
  /// context. With no provider enabled it behaves like a plain controller.
  late final TextEditingController _text = WritingTextEditingController(
      text: widget.item?.text ?? widget.element.text);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Focused and fully selected on open, so typing replaces the placeholder
    // "Text" a new element arrives with rather than appending to it.
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

  /// _onFocus closes the editor when the focus goes elsewhere (the canvas,
  /// another element, a control in the sidebar): an editor left open behind
  /// the next thing would keep swallowing keystrokes.
  void _onFocus() {
    if (!_focus.hasFocus) widget.onDone();
  }

  /// _room is the padding that puts the editor where the words are drawn:
  /// the element's own.
  EdgeInsets _room(TextElement e, double scale) => EdgeInsets.fromLTRB(
      e.box.padLeft * scale,
      e.box.padTop * scale,
      e.box.padRight * scale,
      e.box.padBottom * scale);

  @override
  Widget build(BuildContext context) {
    var e = widget.element;
    var item = widget.item;
    // The type it is drawn in, which with Fit to box on is not the type it is
    // set in: the letters must not change size when the paragraph is clicked
    // into. A piece is set in its own type and held to the edge its slot holds
    // it to, as it is drawn, so the words do not move as they are typed.
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
          // The box's padding and then the room an icon has taken, so the words
          // are typed where they will be drawn rather than on top of the icon.
          padding: item == null ? _room(e, scale) : EdgeInsets.zero,
          child: Align(
            alignment: switch (spec.verticalAlign) {
              VerticalAlignSpec.top => Alignment.topCenter,
              VerticalAlignSpec.middle => Alignment.center,
              VerticalAlignSpec.bottom => Alignment.bottomCenter,
            },
            child: Shortcuts(
              shortcuts: const {
                // Escape finishes. Enter must not: a text element is a paragraph, and
                // Enter starts a new line.
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
                    // Nothing at all: no border, no fill, no counter, and no content
                    // padding (the default inset of sixteen pixels would put every
                    // character somewhere other than where it will be drawn).
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  // What an enabled capability offers for the text under the pointer
                  // (a correction, a dictionary word, a synonym), falling back to the
                  // ordinary menu. Nothing here names a provider.
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

  /// onPickPicture puts a picture in this cell instead of words.
  ///
  /// It returns a Future so it is awaited: called and forgotten, an exception
  /// in it would be an unhandled Future error, silent in a release build.
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
    // Selected, not merely focused: a cell is opened to be replaced far more
    // often than to be appended to.
    _focus.requestFocus();
    _text.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.value.length);
    _focus.addListener(() {
      // Not while the file picker is up: opening it takes the focus from the
      // field, and closing the editor then would cancel the tap that opened it.
      if (!_focus.hasFocus && !_picking) widget.onDone();
    });
  }

  /// _picking is whether the picture button has been pressed.
  ///
  /// Set on pointer down, not on the tap: the field loses focus as the
  /// pointer goes down elsewhere, which closes this editor, so a flag set when
  /// the tap completed would be too late. Not in setState: a rebuild in the
  /// middle of a gesture can lose it.
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
              // A Listener rather than an InkWell, which takes focus off the field
              // when pressed, or onTapDown, which fires only once the gesture arena
              // has settled, by which time the editor has been told to close.
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

/// _CloseCellIntent is Escape, which shuts the editor.
class _CloseCellIntent extends Intent {
  const _CloseCellIntent();
}

/// CounterInput is the field that opens on a live counter's Set button,
/// rather than a dialog that would cover the counter. It opens with the
/// current value selected, so typing replaces it.
class CounterInput extends StatefulWidget {
  final double value;
  final int decimals;

  /// onDone hands back the number typed, or null where the field was closed
  /// without one, which leaves the counter alone.
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
