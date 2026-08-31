import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
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
