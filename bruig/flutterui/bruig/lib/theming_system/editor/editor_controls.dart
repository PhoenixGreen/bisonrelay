import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// editor_controls.dart holds the small widgets every part of the theme
// editor is built from: the numeric slider, the wrapping equal-column row,
// and the caption/note text. Going through these (rather than raw Slider/
// Wrap/Text) is what keeps the Appearance page's controls looking and
// behaving the same wherever they appear.

// responsiveRow lays `cells` out side by side in equal columns, wrapping
// onto further rows -- and in the narrowest case one per row -- as soon as
// the available width can't give every cell at least `minWidth`. Equal
// widths (rather than each cell taking what it needs) are what keeps the
// controls lined up in columns across a wrap.
Widget responsiveRow(List<Widget> cells, {double minWidth = 150}) {
  if (cells.isEmpty) return const SizedBox.shrink();
  const gap = 16.0;
  return LayoutBuilder(builder: (context, constraints) {
    var perRow = ((constraints.maxWidth + gap) / (minWidth + gap))
        .floor()
        .clamp(1, cells.length);
    var width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: 12,
      children: [
        for (var cell in cells) SizedBox(width: width, child: cell),
      ],
    );
  });
}

// labelled is one cell of a responsiveRow: a caption over its control.
Widget labelled(String label, Widget control) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Txt(label),
      const SizedBox(height: 4),
      control,
    ]);

// noteText is the small explanatory caption shown under some controls,
// without the indent AreaEditorContext.note adds -- a cell inside a row is
// already indented by the column it sits in.
Widget noteText(String text) =>
    Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3A0)));

// ValueSlider is one numeric setting: a slider, and optionally a type-in
// box over the same value, so it can be dragged roughly or set exactly.
//
// Neither control writes on every change. The slider commits when the drag
// ends, not once per frame, and the box when it's submitted or loses focus,
// not per keystroke -- each commit rewrites the draft preset and rebuilds
// the whole app's theme through it, which is far too much work to do per
// frame or per character.
class ValueSlider extends StatefulWidget {
  // label renders the live value above the slider; null leaves it off, for
  // a caller that has already labelled this value itself.
  final String Function(double)? label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool numberField;
  final ValueChanged<double> onCommit;

  const ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.numberField,
    required this.onCommit,
    super.key,
  });

  @override
  State<ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<ValueSlider> {
  // _dragging holds the in-flight value while the slider's thumb is down,
  // so the label and box track the drag before it's committed.
  double? _dragging;
  late final TextEditingController _ctrl =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  double get _shown => _dragging ?? widget.value;

  static String _format(double v) => v.toStringAsFixed(1);

  @override
  void didUpdateWidget(covariant ValueSlider old) {
    super.didUpdateWidget(old);
    // Mirror an outside change (the slider, or a reset elsewhere) into the
    // box -- but never while it's focused, which would rewrite what the
    // user is in the middle of typing.
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commitText();
  }

  void _commitText() {
    // Anything unparseable, negative or past this setting's range snaps
    // back to what's actually set, rather than quietly applying something
    // else or leaving the box disagreeing with the slider beside it.
    var parsed = double.tryParse(_ctrl.text.trim());
    var v = parsed == null
        ? widget.value
        : parsed.clamp(widget.min, widget.max).toDouble();
    if (_ctrl.text != _format(v)) _ctrl.text = _format(v);
    if (v != widget.value) widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) {
    var slider = Slider(
      value: _shown.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChanged: (v) => setState(() {
        _dragging = v;
        if (!_focus.hasFocus) _ctrl.text = _format(v);
      }),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        // Commit exactly what the box shows. A continuous slider otherwise
        // lands on values with more precision than the box displays, and
        // the box would then "change" the setting to its own rounded
        // reading the next time it merely lost focus.
        widget.onCommit(double.parse(_format(v)));
      },
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) Text(widget.label!(_shown)),
      Row(children: [
        Expanded(child: slider),
        if (widget.numberField)
          SizedBox(
            width: 58,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitText(),
            ),
          ),
      ]),
    ]);
  }
}
