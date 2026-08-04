import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:provider/provider.dart';

// Text field with default app styling.
class TextInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final TextSize textSize;
  final ValueChanged<String>? onSubmitted;
  const TextInput(
      {this.textSize = TextSize.medium,
      this.controller,
      this.hintText,
      this.onSubmitted,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => TextField(
              onSubmitted: onSubmitted,
              style: theme.textStyleFor(context, textSize, null),
              controller: controller,
              decoration: hintText != null
                  ? InputDecoration(hintText: hintText!)
                  : null,
            ));
  }
}

class IntEditingController extends TextEditingController {
  int get intvalue => text != "" ? int.parse(text) : 0;
  set intvalue(int v) => text = v.toString();
}

class _LimitIntTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text == "") return newValue;
    try {
      int.parse(newValue.text);
      return newValue;
    } catch (exception) {
      return oldValue;
    }
  }
}

Widget intInput({
  void Function(int amount)? onChanged,
  IntEditingController? controller,
}) =>
    Consumer<ThemeNotifier>(
        builder: (context, theme, _) => TextField(
              style: theme.textStyleFor(context, TextSize.small, null),
              controller: controller,
              onChanged: (String v) {
                try {
                  int val = v != "" ? int.parse(v) : 0;
                  if (onChanged != null) onChanged(val);
                } catch (exception) {
                  // ignore.
                }
              },
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_LimitIntTextInputFormatter()],
            ));

// -----------------------------------------------------------------------------
// The Input Areas theme area, applied.
// -----------------------------------------------------------------------------
//
// Every text input that area covers builds its decoration through
// themedInputDecoration, so one setting reaches all of them instead of
// each screen deciding for itself.
//
// Each setting has a "leave it alone" value (no colour, zero width, zero
// radius) that falls through to what the input looked like before the area
// existed -- so an untouched theme is unchanged, and only what the user
// actually sets is imposed on every box at once.

// kInputFontSize is what text inside an input measures. Fixed rather than
// themed: these boxes were visibly different sizes from each other (the
// Manage search fields and the Add description ran large), and one size is
// most of the point of the area.
const double kInputFontSize = 14;
const TextStyle kInputTextStyle = TextStyle(fontSize: kInputFontSize);

// themedInputBorderColor is what a focused input's border draws in: the
// Input Areas area's own setting, or the palette's Input Color.
Color themedInputBorderColor(BuildContext context) {
  var theme = Provider.of<ThemeNotifier>(context);
  var style = theme.areaStyle(ThemeArea.inputAreas);
  return style.resolveInputBorderColor(theme) ??
      theme.activePreset?.inputSelected ??
      theme.colors.primary;
}

// themedInputRestingColor is the same border when the input isn't focused
// -- its own palette slot (Input Resting Color), seeded to a darker Input
// Color. The area's Border color setting overrides both, since a theme
// that names one border colour means it for the box, not for one state.
Color themedInputRestingColor(BuildContext context) {
  var theme = Provider.of<ThemeNotifier>(context);
  var style = theme.areaStyle(ThemeArea.inputAreas);
  return style.resolveInputBorderColor(theme) ??
      theme.activePreset?.inputResting ??
      theme.colors.outline;
}

InputDecoration themedInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool isDense = true,
  EdgeInsetsGeometry? contentPadding,
  // A caller's own fill still wins: the chat composer paints its
  // background from the Chat area, which is a separate decision.
  bool? filled,
  Color? fillColor,
  // fallbackBorder is what this particular input drew before the area
  // existed -- the pill on the user search, the plain outline on the
  // Manage search fields, nothing at all on the ones that use Flutter's
  // default underline. Used until the theme sets a width or radius of its
  // own, so an untouched theme looks as it did and the area is what brings
  // the boxes into line.
  InputBorder? fallbackBorder,
}) {
  var theme = Provider.of<ThemeNotifier>(context);
  var style = theme.areaStyle(ThemeArea.inputAreas);
  // The area's own Background setting, else the palette's Input
  // Background. Transparent there means "no fill", which is what inputs
  // have always had -- so it's left unfilled rather than painted with a
  // colour that does nothing but cost a layer.
  var paletteBackground = theme.activePreset?.inputBackground;
  var background = style.resolveInputBackgroundColor(theme) ??
      ((paletteBackground?.a ?? 0) > 0 ? paletteBackground : null);
  // The focused colour: the area's own, else the palette's Input Selected.
  var focusColor = themedInputBorderColor(context);
  var restColor = themedInputRestingColor(context);

  var radius = style.inputBorderRadius;
  var width = style.inputBorderWidth;

  InputBorder? resting;
  InputBorder? focused;
  if (radius > 0 || width > 0) {
    // Themed: one shape, drawn in two colours. Focus must not change the
    // corner radius or the thickness -- a box that changes shape when you
    // click into it reads as a different control.
    var shape = BorderRadius.circular(radius);
    var w = width > 0 ? width : 1.0;
    resting = OutlineInputBorder(
        borderRadius: shape,
        borderSide: BorderSide(color: restColor, width: w));
    focused = OutlineInputBorder(
        borderRadius: shape,
        borderSide: BorderSide(color: focusColor, width: w));
  } else if (fallbackBorder is OutlineInputBorder) {
    // Untouched, but this input has an outline of its own: keep its shape
    // and thickness, and give focus the same shape rather than Flutter's
    // own default radius, which is where the corners used to change.
    var w = fallbackBorder.borderSide.width;
    resting = fallbackBorder.copyWith(
        borderSide: BorderSide(color: restColor, width: w));
    focused = fallbackBorder.copyWith(
        borderSide: BorderSide(color: focusColor, width: w));
  }
  // Anything else (no fallback) is left entirely to the input theme, which
  // is Flutter's underline drawn in Input Selected Color when focused.

  return InputDecoration(
    isDense: isDense,
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: contentPadding,
    hintStyle: kInputTextStyle,
    filled: filled ?? (background != null),
    fillColor: fillColor ?? background,
    border: resting,
    enabledBorder: resting,
    focusedBorder: focused,
  );
}
