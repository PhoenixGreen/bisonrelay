import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// code_editor.dart is a Code panel's pane opened for typing on the stage: a
// real text field laid exactly where the pane's code is drawn, at the
// page's scale, its text coloured as the painter colours it (codeSpan), so
// opening it changes nothing that is seen but the caret. Tab indents as the
// file's language does; Escape, or the focus going elsewhere, closes it.

class CodePaneEditor extends StatefulWidget {
  final CodeElement element;
  final String file;

  /// rect is the pane's code on the stage, in the stage's pixels; [scale]
  /// is the stage's pixels to the page's.
  final Rect rect;
  final double scale;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  const CodePaneEditor({
    required this.element,
    required this.file,
    required this.rect,
    required this.scale,
    required this.onChanged,
    required this.onDone,
    super.key,
  });

  @override
  State<CodePaneEditor> createState() => _CodePaneEditorState();
}

/// _CodeText colours what is typed as the painter would.
class _CodeText extends TextEditingController {
  CodeElement element;
  String file;
  _CodeText(this.element, this.file, String text) : super(text: text);

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    var f = element.file(file);
    if (f == null) return TextSpan(text: text, style: style);
    return codeSpan(element, f.copyWith(text: text), text, text.length,
        CodeColours.of(element.theme));
  }
}

class _CodePaneEditorState extends State<CodePaneEditor> {
  late final _CodeText _text;
  final FocusNode _focus = FocusNode();
  final ScrollController _down = ScrollController();
  final ScrollController _across = ScrollController();

  @override
  void initState() {
    super.initState();
    var f = widget.element.file(widget.file);
    _text = _CodeText(widget.element, widget.file, f?.text ?? "");
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(CodePaneEditor old) {
    super.didUpdateWidget(old);
    _text.element = widget.element;
    _text.file = widget.file;
    // Changed from outside (undone, say): the field follows.
    var now = widget.element.file(widget.file)?.text;
    if (now != null && now != _text.text) {
      _text.value = TextEditingValue(
          text: now,
          selection: TextSelection.collapsed(
              offset: math.min(_text.selection.baseOffset, now.length)));
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    _down.dispose();
    _across.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) widget.onDone();
  }

  /// _key answers Tab (an indent, as the file's language indents, or out
  /// again with Shift) and Escape (done).
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDone();
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    var indent = widget.element.file(widget.file)?.language.indent ?? "  ";
    var v = _text.value;
    var sel = v.selection;
    if (!sel.isValid) return KeyEventResult.handled;
    if (HardwareKeyboard.instance.isShiftPressed) {
      // Out: the indent before the caret's line taken away.
      var lineStart = v.text.lastIndexOf("\n", math.max(0, sel.start - 1)) + 1;
      if (sel.start == 0) lineStart = 0;
      if (v.text.startsWith(indent, lineStart)) {
        var t = v.text.replaceRange(lineStart, lineStart + indent.length, "");
        _set(TextEditingValue(
            text: t,
            selection: TextSelection.collapsed(
                offset: math.max(lineStart, sel.start - indent.length))));
      }
      return KeyEventResult.handled;
    }
    var t = v.text.replaceRange(sel.start, sel.end, indent);
    _set(TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: sel.start + indent.length)));
    return KeyEventResult.handled;
  }

  void _set(TextEditingValue v) {
    _text.value = v;
    widget.onChanged(v.text);
  }

  @override
  Widget build(BuildContext context) {
    var e = widget.element;
    var f = e.file(widget.file);
    if (f == null) return const SizedBox.shrink();
    var c = CodeColours.of(e.theme);
    var fs = e.fontSize;
    var lh = codeLineHeight(fs);
    var pad = codeTextPad(e);
    var gutter = codeGutterWidth(e, f);
    var lines = _text.text.split("\n");
    var widest = lines.fold(
        0, (int w, l) => math.max(w, l.replaceAll("\t", "    ").length));
    var page = Size(
        widget.rect.width / widget.scale, widget.rect.height / widget.scale);
    var textW = math.max(
        page.width - gutter, (widest + 4) * codeCharWidth(fs) + fs * 2);
    var textH = math.max(page.height, lines.length * lh + pad * 2 + lh * 4);
    return Positioned.fromRect(
      rect: widget.rect,
      child: ClipRect(
        child: ColoredBox(
          color: c.bg,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: page.width,
            maxWidth: page.width,
            minHeight: page.height,
            maxHeight: page.height,
            child: Transform.scale(
              scale: widget.scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: page.width,
                height: page.height,
                child: SingleChildScrollView(
                  controller: _down,
                  child: SizedBox(
                    height: textH,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line numbers, scrolled with the code.
                        SizedBox(
                          width: gutter,
                          child: Padding(
                            padding: EdgeInsets.only(top: pad, right: fs * 0.8),
                            child: Text(
                              [for (var i = 1; i <= lines.length; i++) "$i"]
                                  .join("\n"),
                              textAlign: TextAlign.right,
                              strutStyle: codeStrut(fs),
                              style: codeStyle(
                                  fs,
                                  e.lineNumbers
                                      ? c.gutter
                                      : Colors.transparent),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _across,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: textW,
                              child: Focus(
                                onKeyEvent: _key,
                                skipTraversal: true,
                                child: Padding(
                                  padding: EdgeInsets.only(top: pad),
                                  child: TextField(
                                    key: ValueKey(
                                        "codeEditor-${e.id}-${widget.file}"),
                                    controller: _text,
                                    focusNode: _focus,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    smartDashesType: SmartDashesType.disabled,
                                    smartQuotesType: SmartQuotesType.disabled,
                                    style: codeStyle(fs, c.fg),
                                    strutStyle: codeStrut(fs),
                                    cursorColor: c.caret,
                                    cursorWidth: math.max(1.5, fs * 0.12),
                                    decoration: const InputDecoration.collapsed(
                                        hintText: ""),
                                    onChanged: widget.onChanged,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
