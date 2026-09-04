import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_text_editor.dart is the text field that appears over a text element
// while it is being written.
//
// A canvas is painted, not laid out, so there is nothing on screen to type
// into: the words are pixels drawn by a CustomPainter. What goes over the top
// instead is a real TextField, positioned on the element, transformed the same
// way, and styled from the same TextSpec -- so what is typed looks like what
// will be drawn, at the size and face it will be drawn at.
//
// It replaces a two-line Content box in the settings panel, which could show
// neither the size nor the face nor the width the text had to fit, so writing
// a headline meant typing in one place and looking in another.
//
// The illusion has three requirements, and all three are easy to lose:
//
//   the element's own text is not painted while this is open, or the words
//   appear twice, half a pixel apart;
//   the field has no decoration, no fill and no cursor padding of its own;
//   and the transform matches the stage's exactly -- scale, then rotation
//   about the centre, in that order.

/// CanvasTextEditor is the field itself, in the element's own coordinates.
///
/// It is given the element's rectangle in *stage* pixels and the scale it is
/// drawn at, and sizes its type by that scale so a canvas zoomed to 200% is
/// typed into at 200%.
class CanvasTextEditor extends StatefulWidget {
  final TextElement element;

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
  late final TextEditingController _text =
      TextEditingController(text: widget.element.text);
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

  /// _onFocus closes the editor when the focus goes elsewhere -- clicking the
  /// canvas, another element, or a control in the sidebar. Clicking away is
  /// how most people finish typing, and an editor that stayed open behind the
  /// next thing they did would keep swallowing their keystrokes.
  void _onFocus() {
    if (!_focus.hasFocus) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    var e = widget.element;
    var spec = e.textSpec;
    var scale = widget.scale;

    return Positioned(
      left: widget.rect.left,
      top: widget.rect.top,
      width: widget.rect.width,
      height: widget.rect.height,
      child: Transform.rotate(
        angle: e.rotationRadians,
        child: Padding(
          padding: EdgeInsets.all(e.box.padding * scale),
          child: Align(
            alignment: switch (spec.verticalAlign) {
              VerticalAlignSpec.top => Alignment.topCenter,
              VerticalAlignSpec.middle => Alignment.center,
              VerticalAlignSpec.bottom => Alignment.bottomCenter,
            },
            child: Shortcuts(
              shortcuts: const {
                // Escape finishes. Enter must not: a text element is a
                // paragraph, and the one key everybody presses to start a new
                // line cannot be the one that closes the editor.
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
                    // Nothing at all: no border, no fill, no counter, and --
                    // the one that is easy to miss -- no content padding. The
                    // default inset is sixteen pixels, which would put every
                    // character somewhere other than where it will be drawn.
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
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
/// A plain field rather than CanvasTextEditor, which sets the element's own
/// type at the element's own size across the whole box. That is right for a
/// headline and wrong for a cell in a grid, where what is wanted is a slot the
/// size of the cell with a visible edge -- the cell has rules round it already
/// and an invisible field inside them cannot be told from the table.
class CanvasCellEditor extends StatefulWidget {
  final String value;
  final double fontSize;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  /// onPickPicture puts a picture in this cell instead of words.
  ///
  /// Offered here rather than behind a right-click menu, because this is
  /// already the gesture for "I want to change this cell" -- and a menu with
  /// one item on it is a menu nobody finds.
  ///
  /// Returns a Future so that it can be *awaited*. Called and forgotten, an
  /// exception inside it becomes an unhandled Future error, which in a
  /// release build goes nowhere at all -- so a picker that fell over on its
  /// first line looked exactly like a button that was not connected.
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
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
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
      // Not while the file picker is up. Opening it takes the focus away from
      // the field, which closed the editor and took its own button with it --
      // so the tap that opened the picker was cancelled before it finished
      // and no picture ever arrived.
      if (!_focus.hasFocus && !_picking) widget.onDone();
    });
  }

  /// _picking is whether the picture button has been pressed.
  ///
  /// Set on pointer *down*, not on the tap. The field loses focus the moment
  /// the pointer goes down somewhere else, and losing focus is what closes
  /// this editor -- so a flag set when the tap completed was set after the
  /// editor it was protecting had already gone, taking the half-finished tap
  /// with it. Which is why the button did nothing three times over.
  ///
  /// Not in setState: a rebuild in the middle of a gesture is another way to
  /// lose it.
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
                onChanged: widget.onChanged,
                onSubmitted: (_) => widget.onDone(),
              ),
            ),
            Tooltip(
              message: "Put a picture in this cell",
              // A bare detector rather than an InkWell, which asks for focus
              // and so takes it off the field the moment it is pressed.
              // Listener rather than the detector's own onTapDown, which
              // fires only once the gesture arena has settled -- by which
              // time the focus has already moved and the editor has already
              // been told to close. A Listener sees the pointer itself.
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
