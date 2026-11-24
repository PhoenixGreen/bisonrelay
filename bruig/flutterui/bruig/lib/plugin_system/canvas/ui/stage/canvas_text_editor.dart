import 'dart:math' as math;

import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_fields.dart';
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
// none of the app's text scaling,
// each part styled as the painter styles it (partStyle), the same width to
// wrap in, and room on the right for the caret, which a TextField keeps out
// of the width it wraps in (_caretRoom).
//
// Where the painter sets the words some other way -- along a line, in
// columns, round something in the way -- the field cannot follow, so it
// shows the words itself and the canvas leaves out just those words, never
// the box or the other pieces (showWords true).

/// _caretRoom is what a TextField keeps beside its words for the caret: its
/// width and a pixel's gap (RenderEditable's caret margin). Added to the
/// field's width, so it wraps where the painter does.
const double _caretRoom = CanvasTextEditor.cursorWidth + 1;

/// editorDrawsWords is whether the field must show [e]'s words (or piece
/// [item]'s) itself, on a page of [doc], because the painter sets them in a
/// way a TextField cannot match. See the top of this file.
///
/// Words with a field in them (text_fields.dart) are typed as written, a
/// "{page}", where the canvas draws them filled in: the field shows them.
bool editorDrawsWords(TextElement e, TextItem? item, CanvasDocument? doc) {
  if (item != null) return hasFields(item.text);
  return switch (e.wordsSetIn(doc)) {
    // Wrapped whenever something is in the way, which a drag may change.
    WordsSet.onLine || WordsSet.wrapped || WordsSet.inColumns => true,
    WordsSet.inBox => e.flowsOnIn(doc) || hasFields(e.text),
  };
}

/// CanvasTextEditor is the field itself. It is given the rectangle the words
/// are laid out in, in stage pixels, and the scale they are drawn at, so a
/// canvas zoomed to 200% is typed into at 200%.
class CanvasTextEditor extends StatefulWidget {
  static const double cursorWidth = 1.5;

  final TextElement element;

  /// document is the page [element] is on, which decides how its words are
  /// set (TextElement.wordsSetIn).
  final CanvasDocument? document;

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

  /// turn is how far the element is turned where it is drawn, in radians:
  /// with its keys and clips on this frame. Null is its resting turn.
  final double? turn;

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
    this.document,
    this.item,
    required this.rect,
    required this.scale,
    this.pivot,
    this.turn,
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
    var doc = widget.document;
    var spec = item == null
        ? drawnTextSpec(e, e.bounds, doc: doc)
        : item.spec.copyWith(
            align: item.slot.across,
            verticalAlign: VerticalAlignSpec.top,
          );
    var scale = widget.scale;
    var fills = item == null && !bodyIsBlock(e, doc: doc);
    var style = textStyleOf(spec, scale: scale);
    // The runs the canvas draws differently, so the letters are where they
    // are drawn; a piece has none.
    _text.setParts(item == null ? e.drawnParts : const [], spec, scale,
        clear: !widget.showWords);
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

    // Not the app's text size: the field lays its words over the canvas's,
    // which are drawn at their own size whatever the reader's setting. With
    // the app's text made larger the field's words were larger than the
    // ones drawn, so a click picked letters off to one side and the
    // selection sat low -- worst down a paragraph (Ken, 2026-11-24: a
    // double-click on "under" in Absolute Beginners Piano).
    field = MediaQuery.withNoTextScaling(child: field);

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
      width: rect.width + _caretRoom,
      height: fills ? rect.height : null,
      child: Transform.rotate(
        angle: widget.turn ?? e.rotationRadians,
        origin: pivot == null ? null : pivot - rect.center,
        child: field,
      ),
    );
  }
}

/// _CasedController shows the words in the element's case (TextCase), as
/// the canvas draws them, so the caret falls between the letters drawn. Not
/// where the case would change the length (a German ß made SS), where the
/// caret could not be placed by the letters shown. Each of the parts is
/// styled as the painter styles it (partStyle), inside whatever the writing
/// tools mark: their underlines stay, on letters of the part's size.
class _CasedController extends WritingTextEditingController {
  final TextCase textCase;

  _CasedController({super.text, required this.textCase});

  List<TextPart> _parts = const [];
  TextSpec _spec = const TextSpec();
  double _scale = 1;
  bool _clear = false;

  /// setParts is what the words are drawn with: [parts] in [spec] at
  /// [scale], their letters [clear] where the canvas draws them under a
  /// see-through field. Set as the field is built, so a zoom is kept up.
  void setParts(List<TextPart> parts, TextSpec spec, double scale,
      {required bool clear}) {
    _parts = parts;
    _spec = spec;
    _scale = scale;
    _clear = clear;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    var span = super.buildTextSpan(
        context: context, style: style, withComposing: withComposing);
    var shown = textCase.apply(text);
    var cased = textCase != TextCase.none && shown.length == text.length;
    if (!cased && _parts.isEmpty) return span;
    if (!cased) shown = text;
    var runs = _parts.isEmpty ? const <PartRun>[] : partRuns(shown, _parts);
    // Cut from the whole cased text, as title case depends on where each
    // word starts, which a run on its own cannot tell; and the parts counted
    // in the whole, as the painter counts them.
    var at = 0;
    TextSpan rebuilt(TextSpan s, TextStyle? over) {
      var mine = over == null ? s.style : over.merge(s.style);
      String? t;
      var split = <InlineSpan>[];
      if (s.text case var own?) {
        var from = at;
        at += own.length;
        t = shown.substring(from, at);
        var crossing = [
          for (var run in runs)
            if (run.end > from && run.start < at) run,
        ];
        if (mine != null && crossing.any((run) => run.part != null)) {
          for (var run in crossing) {
            split.add(TextSpan(
                text: shown.substring(
                    math.max(run.start, from), math.min(run.end, at)),
                style: partStyle(mine, _spec, run.part,
                    pass: WordsPass.letters,
                    colorOverride: _clear ? const Color(0x00000000) : null,
                    scale: _scale)));
          }
          t = null;
        }
      }
      return TextSpan(
        text: t,
        style: s.style,
        recognizer: s.recognizer,
        mouseCursor: s.mouseCursor,
        children: s.children == null && split.isEmpty
            ? null
            : [
                ...split,
                for (var c in s.children ?? const <InlineSpan>[])
                  if (c is TextSpan) rebuilt(c, mine) else c,
              ],
      );
    }

    return rebuilt(span, null);
  }
}

class _FinishIntent extends Intent {
  const _FinishIntent();
}
