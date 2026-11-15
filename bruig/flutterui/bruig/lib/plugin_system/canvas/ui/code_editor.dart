import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// code_editor.dart is a Code panel's file opened for typing: CodeEditorBody,
// a text field with line numbers whose text is coloured as the painter
// colours it (codeSpan). Tab indents as the file's language does, Shift-Tab
// takes it out again, Escape is done and Cmd-Return (or Ctrl-Return) runs.
//
// On the stage it is CodePaneEditor, laid exactly where the pane's code is
// drawn and at the page's scale, so opening it changes nothing that is seen
// but the caret; in the Code Studio it fills its pane at the studio's size.

/// _CodeText colours what is typed as the painter would.
class _CodeText extends TextEditingController {
  CodeElement element;
  String file;
  double fontSize;
  _CodeText(this.element, this.file, this.fontSize, String text)
      : super(text: text);

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    var f = element.file(file);
    if (f == null) return TextSpan(text: text, style: style);
    return codeSpan(element, f.copyWith(text: text), text, text.length,
        CodeColours.of(element.theme),
        fontSize: fontSize);
  }
}

/// CodeEditorBody is the editor itself, filling what it is given, in
/// [fontSize] (page units on the stage, pixels in the studio).
class CodeEditorBody extends StatefulWidget {
  final CodeElement element;
  final String file;
  final double fontSize;
  final ValueChanged<String> onChanged;

  /// onDone is Escape -- and the focus going elsewhere, where [doneOnBlur].
  final VoidCallback? onDone;
  final bool doneOnBlur;

  /// onRun is Cmd-Return.
  final VoidCallback? onRun;
  final bool autofocus;

  const CodeEditorBody({
    required this.element,
    required this.file,
    required this.fontSize,
    required this.onChanged,
    this.onDone,
    this.doneOnBlur = false,
    this.onRun,
    this.autofocus = true,
    super.key,
  });

  @override
  State<CodeEditorBody> createState() => _CodeEditorBodyState();
}

class _CodeEditorBodyState extends State<CodeEditorBody> {
  late final _CodeText _text;
  final FocusNode _focus = FocusNode();
  final ScrollController _down = ScrollController();
  final ScrollController _across = ScrollController();

  @override
  void initState() {
    super.initState();
    var f = widget.element.file(widget.file);
    _text =
        _CodeText(widget.element, widget.file, widget.fontSize, f?.text ?? "");
    _focus.addListener(_onFocus);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(CodeEditorBody old) {
    super.didUpdateWidget(old);
    _text.element = widget.element;
    _text.file = widget.file;
    _text.fontSize = widget.fontSize;
    // Changed from outside (undone, another pane, another file): the field
    // follows.
    var now = widget.element.file(widget.file)?.text;
    if (now != null && now != _text.text) {
      _text.value = TextEditingValue(
          text: now,
          selection: TextSelection.collapsed(
              offset: math
                  .min(_text.selection.baseOffset, now.length)
                  .clamp(0, now.length)));
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
    if (!_focus.hasFocus && widget.doneOnBlur) widget.onDone?.call();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        widget.onDone != null) {
      widget.onDone!();
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        (keys.isMetaPressed || keys.isControlPressed) &&
        widget.onRun != null) {
      widget.onRun!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    var indent = widget.element.file(widget.file)?.language.indent ?? "  ";
    var v = _text.value;
    var sel = v.selection;
    if (!sel.isValid) return KeyEventResult.handled;
    if (keys.isShiftPressed) {
      // Out: the indent at the start of the caret's line taken away.
      var lineStart = sel.start == 0
          ? 0
          : v.text.lastIndexOf("\n", math.max(0, sel.start - 1)) + 1;
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
    var fs = widget.fontSize;
    var lh = codeLineHeight(fs);
    var pad = fs * 0.7;
    var lines = _text.text.split("\n");
    var gutter = e.lineNumbers
        ? math.max(2, "${lines.length}".length) * codeCharWidth(fs) + fs * 1.6
        : fs * 0.5;
    var widest = lines.fold(
        0, (int w, l) => math.max(w, l.replaceAll("\t", "    ").length));
    // Not scaled by the app's text size (Ken runs a larger one): its lines
    // are measured at [fs] -- the scroll view's height, the gutter, the
    // painted code it lies over -- and a scaled field outgrew that and
    // scrolled inside itself, so the top could not be reached.
    return MediaQuery.withNoTextScaling(
        child: LayoutBuilder(builder: (context, room) {
      var textW = math.max(
          room.maxWidth - gutter, (widest + 4) * codeCharWidth(fs) + fs * 2);
      var textH =
          math.max(room.maxHeight, lines.length * lh + pad * 2 + lh * 4);
      return ColoredBox(
        color: c.bg,
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
                      [for (var i = 1; i <= lines.length; i++) "$i"].join("\n"),
                      textAlign: TextAlign.right,
                      strutStyle: codeStrut(fs),
                      style: codeStyle(
                          fs, e.lineNumbers ? c.gutter : Colors.transparent),
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
                            key: ValueKey("codeEditor-${e.id}-${widget.file}"),
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
                            decoration:
                                const InputDecoration.collapsed(hintText: ""),
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
      );
    }));
  }
}

/// CodePaneEditor is the editor on the stage, over a pane's code.
class CodePaneEditor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    var page = Size(rect.width / scale, rect.height / scale);
    return Positioned.fromRect(
      rect: rect,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: page.width,
          maxWidth: page.width,
          minHeight: page.height,
          maxHeight: page.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: page.width,
              height: page.height,
              child: CodeEditorBody(
                element: element,
                file: file,
                fontSize: element.fontSize,
                onChanged: onChanged,
                onDone: onDone,
                doneOnBlur: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
