import 'package:flutter/material.dart';

import 'package:bruig/theming_system/theme_manager.dart';

// counter_input.dart is the field a run's Set button opens over the
// counter.

/// CounterInput is the field a run's Set button opens in place of a
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
