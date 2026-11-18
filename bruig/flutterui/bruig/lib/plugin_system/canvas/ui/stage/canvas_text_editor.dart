import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_fields.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// canvas_text_editor.dart is the text field laid over a text element while it
// is written: a real TextField placed, transformed and set like the element.
//
// Usually the canvas goes on drawing the words, looks and all, and the field
// over them is see-through: only its caret and selection show, so opening it
// changes nothing on the page (showWords false). That needs the field to lay
// the words out exactly as the painter does: the same style (textStyleOf),
// the same width to wrap in, and room on the right for the caret, which a
// TextField keeps out of the width it wraps in (caretRoom).
//
// Where the painter sets the words some other way -- along a line, in
// columns, round something in the way -- the field cannot follow, so it
// shows the words itself and the canvas leaves out just those words, never
// the box or the other pieces (showWords true).

/// caretRoom is what a TextField keeps beside its words for the caret: its
/// width and a pixel's gap (RenderEditable's caret margin). Added to the
/// field's width, so it wraps where the painter does.
const double caretRoom = CanvasTextEditor.cursorWidth + 1;

/// editorDrawsWords is whether the field must show [e]'s words (or piece
/// [item]'s) itself, because the painter sets them in a way a TextField
/// cannot match. See the top of this file.
///
/// Words with a field in them (text_fields.dart) are typed as written, a
/// "{page}", where the canvas draws them filled in: the field shows them.
bool editorDrawsWords(TextElement e, TextItem? item) {
  if (item != null) return hasFields(item.text);
  return e.curve != null ||
      !e.columns.isSingle ||
      e.wrap.on ||
      e.flowTo.isNotEmpty ||
      hasFields(e.text);
}

/// CanvasTextEditor is the field itself. It is given the rectangle the words
/// are laid out in, in stage pixels, and the scale they are drawn at, so a
/// canvas zoomed to 200% is typed into at 200%.
class CanvasTextEditor extends StatefulWidget {
  static const double cursorWidth = 1.5;

  final TextElement element;

  /// item is the extra piece being typed into, or null for the element's own
  /// paragraph.
  final TextItem? item;

  /// rect is where the words are laid out on the stage, unrotated: the
  /// element's box for a paragraph that fills it (padded here by the box's
  /// padding), else the words' own block, as wide as they may grow.
  final Rect rect;

  /// pivot is the stage point the element turns about, or null for the
  /// middle of [rect].
  final Offset? pivot;

  /// scale is document units to stage pixels.
  final double scale;

  /// showWords draws the words in the field, the canvas having left them
  /// out; otherwise the field is see-through over the canvas's own words.
  final bool showWords;

  /// clickAt is where the click that opened it landed, globally: the caret
  /// is put there. Null selects every word, as for a new element's "Text".
  final Offset? clickAt;

  /// onChanged fires on every keystroke, so the size estimate and the layer
  /// list keep up.
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  const CanvasTextEditor({
    required this.element,
    this.item,
    required this.rect,
    required this.scale,
    this.pivot,
    this.showWords = true,
    this.clickAt,
    required this.onChanged,
    required this.onDone,
    super.key,
  });

  @override
  State<CanvasTextEditor> createState() => _CanvasTextEditorState();
}

class _CanvasTextEditorState extends State<CanvasTextEditor> {
  /// The writing tools' controller adds its marks itself; with no provider
  /// enabled it behaves like a plain controller. It shows the words in the
  /// element's case, as they are drawn.
  late final _CasedController _text = _CasedController(
      text: widget.item?.text ?? widget.element.text,
      textCase: (widget.item?.spec ?? widget.element.textSpec).textCase);
  final FocusNode _focus = FocusNode();
  final GlobalKey _field = GlobalKey();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    // A new element's "Text" opens selected, so typing replaces it; words
    // already written open with the caret where the click was.
    var words = _text.text;
    var fresh = words.isEmpty || words == "Text";
    _text.selection = fresh || widget.clickAt == null
        ? TextSelection(baseOffset: 0, extentOffset: words.length)
        : TextSelection.collapsed(offset: words.length);
    if (!fresh && widget.clickAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _caretAtClick());
    }
    _focus.addListener(_onFocus);
  }

  /// _caretAtClick puts the caret at the letter the opening click was on,
  /// once the field is laid out.
  void _caretAtClick() {
    if (!mounted) return;
    var at = widget.clickAt;
    var editable = _findEditable(_field.currentContext?.findRenderObject());
    if (at == null || editable == null || !editable.attached) return;
    var position = editable.getPositionForPoint(at);
    _text.selection = TextSelection.collapsed(
        offset: position.offset.clamp(0, _text.text.length));
  }

  static RenderEditable? _findEditable(RenderObject? from) {
    if (from == null) return null;
    if (from is RenderEditable) return from;
    RenderEditable? found;
    from.visitChildren((child) => found ??= _findEditable(child));
    return found;
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
  /// are drawn in a paragraph that fills the box.
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
    var fills = item == null && !bodyIsBlock(e);
    var style = textStyleOf(spec, scale: scale);
    if (!widget.showWords) {
      // See-through: the canvas draws the words, the field its caret.
      // A fade is a foreground paint, which a style cannot have beside a
      // colour.
      const clear = Color(0x00000000);
      style = style.foreground != null
          ? style.copyWith(foreground: Paint()..color = clear)
          : style.copyWith(color: clear);
      style =
          style.copyWith(decoration: TextDecoration.none, shadows: const []);
    }
    var rect = widget.rect;
    var pivot = widget.pivot;
    var caret = spec.color.withValues(alpha: 1);

    Widget field = TextSelectionTheme(
      data: TextSelectionThemeData(
          selectionColor: const Color(0xFF3D7EFF).withValues(alpha: 0.32)),
      child: TextField(
        key: _field,
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        maxLines: null,
        expands: false,
        cursorColor: caret,
        cursorWidth: CanvasTextEditor.cursorWidth,
        textAlign: spec.align.flutter,
        style: style,
        // No border, fill or padding of any kind -- the app's theme puts an
        // underline on every field, which here would be drawn on the page.
        decoration: const InputDecoration.collapsed(
          hintText: null,
          border: InputBorder.none,
        ).copyWith(
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        // What an enabled writing capability offers for the text under the
        // pointer, else the ordinary menu.
        contextMenuBuilder: (context, editableTextState) => writingContextMenu(
            context, editableTextState,
            fallbackItems: editableTextState.contextMenuButtonItems),
        onChanged: widget.onChanged,
      ),
    );

    field = Shortcuts(
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
        child: field,
      ),
    );

    if (fills) {
      field = Padding(
        padding: _room(e, scale),
        child: Align(
          alignment: switch (spec.verticalAlign) {
            VerticalAlignSpec.top => Alignment.topCenter,
            VerticalAlignSpec.middle => Alignment.center,
            VerticalAlignSpec.bottom => Alignment.bottomCenter,
          },
          child: field,
        ),
      );
    }

    return Positioned(
      left: rect.left,
      top: rect.top,
      // The caret's room on the right: the words wrap where they are drawn.
      width: rect.width + caretRoom,
      height: fills ? rect.height : null,
      child: Transform.rotate(
        angle: e.rotationRadians,
        origin: pivot == null ? null : pivot - rect.center,
        child: field,
      ),
    );
  }
}

/// _CasedController shows the words in the element's case (TextCase), as
/// the canvas draws them, so the caret falls between the letters drawn. Not
/// where the case would change the length (a German ß made SS), where the
/// caret could not be placed by the letters shown.
class _CasedController extends WritingTextEditingController {
  final TextCase textCase;

  _CasedController({super.text, required this.textCase});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    var span = super.buildTextSpan(
        context: context, style: style, withComposing: withComposing);
    if (textCase == TextCase.none) return span;
    var shown = textCase.apply(text);
    if (shown.length != text.length) return span;
    // Cut from the whole cased text, as title case depends on where each
    // word starts, which a run on its own cannot tell.
    var at = 0;
    TextSpan cased(TextSpan s) {
      String? t;
      if (s.text case var own?) {
        t = shown.substring(at, at + own.length);
        at += own.length;
      }
      return TextSpan(
        text: t,
        style: s.style,
        recognizer: s.recognizer,
        mouseCursor: s.mouseCursor,
        children: s.children == null
            ? null
            : [
                for (var c in s.children!)
                  if (c is TextSpan) cased(c) else c,
              ],
      );
    }

    return cased(span);
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
