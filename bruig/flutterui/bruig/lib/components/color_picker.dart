import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/components/saved_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// color_picker.dart is the app's colour picker: the one behind every swatch,
// in the canvas, in the palette editor and in the composer's formatting
// panel.
//
// Written here rather than taken from a package, because of the things a
// package could not be asked for: a hue that survives a black, channels that
// are dragged rather than typed, colours that can be kept between pickers and
// between sessions, and three ways of choosing rather than one.
//
// The three ways are the same colour seen three ways, not three settings:
// whatever is chosen in one is what the others open on.

/// ColorPickerMode is how the colour is being chosen.
enum ColorPickerMode {
  /// sliders is the square and the two bars: the plain way, and the one that
  /// can say exactly what it means.
  sliders("Sliders", Icons.tune),

  /// wheel is hue round and saturation out from the middle, with brightness
  /// and opacity under it. Faster to reach a colour with, harder to be exact.
  wheel("Wheel", Icons.colorize),

  /// palette is five colours at once, arranged by one of the harmonies.
  palette("Palette", Icons.auto_awesome),

  /// gradient is the second colour and how it is reached. Offered only where
  /// the thing being coloured can hold two, which is why it is last: the
  /// three before it are always there, and this one comes and goes.
  gradient("Gradient", Icons.gradient);

  final String label;
  final IconData icon;
  const ColorPickerMode(this.label, this.icon);
}

/// ColorFormat is how the colour is written out in the field under it.
///
/// The same colour in whichever notation the person reading it works in --
/// hex from a designer, HSL from a stylesheet, CMYK from a printer, LAB from
/// a colour system, or the one number a greyscale needs.
enum ColorFormat {
  hex("Hex"),
  hsl("HSL"),
  cmyk("CMYK"),
  lab("LAB"),
  grey("Greyscale");

  final String label;
  const ColorFormat(this.label);
}

/// ColorHarmony is how five colours are arranged around the wheel.
///
/// Each is a set of five places relative to the one being led by: how far
/// round the wheel, how much of the saturation, and how much of the
/// brightness. Custom is the absence of a rule -- every handle goes where it
/// is put.
enum ColorHarmony {
  custom("Custom"),
  analogous("Analogous"),
  complementary("Complementary"),
  splitComplementary("Split complementary"),
  triad("Triad"),
  square("Square"),
  compound("Compound"),
  shades("Shades"),
  monochromatic("Monochromatic");

  final String label;
  const ColorHarmony(this.label);

  /// places is the five (turn, saturation, brightness) offsets this harmony
  /// puts its colours at, the first being the one led by.
  List<(double, double, double)> get places => switch (this) {
        custom => const [
            (0, 1, 1),
            (30, 1, 1),
            (-30, 1, 1),
            (60, 1, 1),
            (-60, 1, 1)
          ],
        analogous => const [
            (0, 1, 1),
            (-40, 0.9, 1),
            (-20, 0.95, 1),
            (20, 0.95, 1),
            (40, 0.9, 1)
          ],
        complementary => const [
            (0, 1, 1),
            (0, 0.55, 1),
            (180, 1, 1),
            (180, 0.55, 1),
            (0, 0.25, 1)
          ],
        splitComplementary => const [
            (0, 1, 1),
            (150, 1, 1),
            (210, 1, 1),
            (150, 0.5, 1),
            (210, 0.5, 1)
          ],
        triad => const [
            (0, 1, 1),
            (120, 1, 1),
            (240, 1, 1),
            (120, 0.5, 1),
            (240, 0.5, 1)
          ],
        square => const [
            (0, 1, 1),
            (90, 1, 1),
            (180, 1, 1),
            (270, 1, 1),
            (0, 0.5, 1)
          ],
        compound => const [
            (0, 1, 1),
            (30, 0.85, 1),
            (180, 1, 1),
            (210, 0.85, 1),
            (150, 0.7, 1)
          ],
        shades => const [
            (0, 1, 1),
            (0, 1, 0.8),
            (0, 1, 0.6),
            (0, 1, 0.42),
            (0, 1, 0.28)
          ],
        monochromatic => const [
            (0, 1, 1),
            (0, 0.75, 0.95),
            (0, 0.5, 0.9),
            (0, 0.3, 1),
            (0, 0.15, 1)
          ],
      };
}

/// pickColor opens the picker as a dialog and answers with the colour
/// chosen, or null if it was dismissed.
Future<Color?> pickColor(
  BuildContext context, {
  required Color initial,
  bool allowAlpha = true,
}) async {
  var picked = await pickPaint(context,
      initial: PaintSpec(initial), allowAlpha: allowAlpha, fades: false);
  return picked?.color;
}

/// pickPaint is pickColor with the gradient tab offered: it answers with a
/// colour and, if one was set up, the second colour to fade to.
///
/// The gradient lives here rather than beside the thing being coloured, so
/// that every swatch in the app gains gradients at once and none of them
/// grows a row of gradient settings of its own.
Future<PaintSpec?> pickPaint(
  BuildContext context, {
  required PaintSpec initial,
  bool allowAlpha = true,
  bool fades = true,
}) {
  // As wide as the screen sensibly allows, which is what puts the numbers and
  // the saved colours beside the picker rather than under it. Measured here
  // rather than by the picker: a dialog asks what it holds how big it wants
  // to be, and a widget that measures the room it has been given cannot
  // answer that question.
  //
  // Allowing for everything between the screen's edge and the content: the
  // dialog's own margin at each side and its padding inside that. Under-
  // counting it by eight pixels is not a dialog eight pixels too wide -- it
  // is a picker told it has room it does not have, which lays itself out for
  // that room and overflows by the difference.
  return showDialog<PaintSpec>(
    context: context,
    builder: (context) => _ColorDialog(
      initial: initial,
      allowAlpha: allowAlpha,
      fades: fades,
    ),
  );
}

/// pickerWidthFor is how wide the picker is drawn on a screen this wide.
///
/// Worked out in the dialog's own build rather than once when it opens, so
/// that dragging the window narrower re-lays the picker out instead of
/// leaving it at the width the screen used to be -- which is a picker holding
/// on to room it no longer has, and that is an overflow stripe.
///
/// No floor: on a small screen there is no width to be had. A picker told it
/// has 280 pixels of a 192-pixel dialog lays itself out for 280 and overflows
/// by the difference. It is narrow because the screen is narrow, which is the
/// right answer.
double pickerWidthFor(double screen) =>
    math.min(screen - dialogChrome(screen), pickerWidest);

class _ColorDialog extends StatefulWidget {
  final PaintSpec initial;
  final bool allowAlpha;
  final bool fades;
  const _ColorDialog({
    required this.initial,
    required this.allowAlpha,
    required this.fades,
  });

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late PaintSpec _paint = widget.initial;

  @override
  Widget build(BuildContext context) {
    var screen = MediaQuery.of(context).size.width;
    return AlertDialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: _dialogInset(screen), vertical: 24),
      contentPadding:
          EdgeInsets.fromLTRB(_dialogPad(screen), 20, _dialogPad(screen), 24),
      // No title. A square of colour, a hue bar and four channels is not a
      // panel anybody needs the word "Colour" over.
      content: SingleChildScrollView(
        child: AppColorPicker(
          color: _paint.color,
          gradient: _paint.gradient,
          onGradientChanged: widget.fades
              ? (g) =>
                  setState(() => _paint = PaintSpec(_paint.color, gradient: g))
              : null,
          allowAlpha: widget.allowAlpha,
          width: pickerWidthFor(screen),
          onChanged: (c) =>
              setState(() => _paint = PaintSpec(c, gradient: _paint.gradient)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        TextButton(
          key: const ValueKey("colorPickerSelect"),
          onPressed: () => Navigator.of(context).pop(_paint),
          child: const Text("Select"),
        ),
      ],
    );
  }
}

/// AppColorPicker is the picker itself, for the places that show it in a
/// panel rather than in a dialog.
class AppColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  /// gradient is the second colour, when the thing being coloured has one.
  ///
  /// Null with [onGradientChanged] set means "can fade, but does not"; a null
  /// [onGradientChanged] means the gradient tab is not offered at all, which
  /// is how the palette editor next door keeps a picker that answers with one
  /// flat colour.
  final GradientSpec? gradient;
  final ValueChanged<GradientSpec?>? onGradientChanged;

  /// allowAlpha offers the transparency channel. Off where the thing being
  /// coloured has no way to be see-through.
  final bool allowAlpha;

  /// width is how wide the picker draws, and -- past [_wideAt] -- whether the
  /// numbers and the saved colours sit beside the colour or under it.
  ///
  /// Told rather than measured: a LayoutBuilder reads better and breaks the
  /// moment the picker is put in a dialog, because an AlertDialog measures
  /// what it holds and a LayoutBuilder cannot answer that question.
  final double width;

  const AppColorPicker({
    required this.color,
    required this.onChanged,
    this.gradient,
    this.onGradientChanged,
    this.allowAlpha = true,
    this.width = 320,
    super.key,
  });

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

/// dialogChrome is everything between the screen's edge and the picker: the
/// dialog's margin at each side and its padding inside that.
///
/// A dialog's usual 40 of margin and 24 of padding is 128 pixels of nothing,
/// which on a phone is nearly half the screen -- so on a narrow one the
/// dialog is pulled in to the edges instead. Read here *and* used to lay the
/// dialog out, because a picker told it has room the dialog does not give it
/// lays itself out for that room and overflows by the difference.
double dialogChrome(double screen) => screen < _wideAt ? 32 : 128;

/// _dialogInset and _dialogPad are the two halves of that, for the dialog
/// itself.
double _dialogInset(double screen) => screen < _wideAt ? 8 : 40;
double _dialogPad(double screen) => screen < _wideAt ? 8 : 24;

/// pickerWidest is as big as the picker is ever drawn. Past this the square
/// and the bars stop looking like controls and start looking like a poster.
///
/// Public for the one caller that lays the picker out itself rather than in a
/// dialog -- the palette editor's expanding row, which measures the room it
/// has and caps it with this.
const double pickerWidest = 700;

/// _wideAt is the width at which the picker lays itself out in two columns.
///
/// The least each column will accept, added together, rather than a round
/// number picked by eye. Under it the numbers and the saved colours go
/// beneath the colour instead of beside it.
const double _wideAt = _pickerLeast + _columnGap + _settingsColumn;

/// _columnGap is the gutter between the colour and the numbers beside it.
///
/// Wide enough to read as two columns rather than as one that happens to
/// have a seam in it: the right-hand one is a stack of small boxes, and small
/// boxes close to a big one look like part of it.
const double _columnGap = 36;

/// _pickerColumn is how much of a wide picker the colour itself would like,
/// and _pickerLeast is how little it will accept.
///
/// The colour column gives way first, down to its floor. It is the one with
/// something to give: a square and two bars read perfectly well at 250, and
/// four numbered boxes at 150 do not -- they fold one to a line, which is the
/// strip that was appearing beside a colour square that had not budged.
const double _pickerColumn = 344;
const double _pickerLeast = 250;

/// _stopButtons is how much room the add and remove buttons take beside the
/// stop bar, each.
const double _stopButtons = 30;

/// _settingsColumn is the least the numbers and the saved colours can be
/// given: four channel boxes and the gaps between them, and no less.
///
/// Held rather than shrunk. What shrinking it does is fold the fourth channel
/// onto a line of its own, and a column of four numbers stacked is worse than
/// two narrower columns side by side.
const double _settingsColumn = 4 * (_channelWidth + 6) + 8;

/// _Spot is one of the five colours in the palette mode.
class _Spot {
  /// hue and sat are where the colour sits on the wheel -- a turn and a
  /// distance out -- and third is its place on whatever axis the notation in
  /// hand has no room for on the wheel.
  ///
  /// Not a colour: what these three mean is the notation's business, so a
  /// palette in LAB is five places on the a-b plane rather than five HSV
  /// colours that happen to have been drawn there.
  final double hue;
  final double sat;
  final double third;
  const _Spot({required this.hue, required this.sat, required this.third});
}

class _AppColorPickerState extends State<AppColorPicker> {
  /// _rgb is the colour the picker is answering with, without its
  /// transparency -- which is held beside it, because a colour that has been
  /// made see-through has no way to say how see-through it was meant to be
  /// once it is fully so.
  Color _rgb = const Color(0xFF000000);
  double _alpha = 1;

  /// _opened is the colour the picker was given to start with, which is what
  /// reset goes back to. Not widget.color: every caller feeds what the picker
  /// says back into it, so by the time reset is pressed that is whatever was
  /// last chosen -- which is the thing being reset away from.
  /// Read in initState rather than lazily: a late final that is first
  /// touched when reset is pressed would be initialised from whatever the
  /// colour is by then, which is the opposite of what it is for.
  late final Color _opened;

  /// _openedGradient is the second colour the picker was given, for the same
  /// reason [_opened] is held: reset goes back to how it opened.
  late final GradientSpec? _openedGradient;

  // Where the handle sits on the wheel: a turn and a distance out.
  //
  // Held rather than worked out from the colour, because a colour does not
  // always say where it was picked from -- a black is every hue, and in LAB
  // or CMYK the wheel's own coordinates are not the colour's saturation at
  // all. Worked out on every build, the handle creeps as it is dragged and
  // the hue slider does nothing on a black.
  double _hue = 0;
  double _sat = 0;

  ColorPickerMode _mode = ColorPickerMode.sliders;
  ColorFormat _format = ColorFormat.hex;

  /// _gradient is the fade as the picker currently has it, and _editingStop
  /// is which of its colours the three colour modes are pointed at: -1 for
  /// the first, 0 for the second, and so on.
  ///
  /// One picker editing whichever stop is selected, rather than a second
  /// picker per colour: a gradient's colours are chosen against each other,
  /// and a dialog each is what stops you doing that.
  GradientSpec? _gradient;
  int _editingStop = -1;

  /// _fades is whether this picker is being asked for a gradient at all.
  bool get _fades => widget.onGradientChanged != null;

  /// _modesOffered leaves the gradient tab out where there is nowhere to put
  /// one.
  List<ColorPickerMode> get _modesOffered => [
        for (var mode in ColorPickerMode.values)
          if (mode != ColorPickerMode.gradient || _fades) mode,
      ];

  // The palette mode's own state. The five colours are a shape laid out
  // around a colour it is led by, which is not the same thing as the colour
  // the picker is answering with -- that is whichever of the five has been
  // picked out. Held apart, or choosing the fourth colour of a triad would
  // re-lay the triad around it and the set would walk away as it was used.
  ColorHarmony _harmony = ColorHarmony.analogous;
  double _leadHue = 0;
  double _leadSat = 1;
  double _leadVal = 1;
  List<_Spot> _spots = const [];
  int _picked = 0;

  /// _locked is which of the five are being kept while the rest are worked
  /// on. A locked colour is not moved by a change of harmony, by the handle
  /// on the rim, or by the brightness under it -- which is what makes a
  /// palette something that can be arrived at one colour at a time.
  List<bool> _locked = List.filled(5, false);

  /// _grabbed is which handle a drag on the palette wheel has hold of, or -1
  /// for the one outside the disc that moves them all.
  int _grabbed = 0;

  // Where the colour sits in the field the chosen notation draws, and what
  // its one or two extra sliders are set to.
  //
  // Held rather than worked out from the colour on every build, for the same
  // reason the hue is: a colour does not always say where it was picked from.
  // Black is every hue, a grey is every a and b in LAB, and a colour that has
  // been through CMYK and back may land a point away from where the handle
  // was put -- so the handle would creep as it was dragged.
  double _fx = 0;
  double _fy = 0;
  double _fz = 0;
  double _fw = 0;

  /// _third is the axis the wheel and the palette have no room for, in
  /// whatever the notation in hand calls it: brightness in hex, lightness in
  /// HSL, how much black ink in CMYK, L in LAB, and the level itself in a
  /// greyscale.
  ///
  /// Held for the same reason the field's numbers are: a wheel says which
  /// colour and how much of it, and the third number has to live somewhere
  /// that a drag round the wheel does not disturb.
  double _third = 1;

  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _opened = widget.color;
    _gradient = widget.gradient;
    _openedGradient = widget.gradient;
    // Opened on whichever way of choosing is in use: a swatch that is already
    // a fade opens on the fade. Otherwise the tab that shows what is set is
    // the one tab nobody is on, and the first thing a picker does is make
    // the colour in hand look like a flat one.
    if (widget.gradient != null && _fades) _mode = ColorPickerMode.gradient;
    _take(widget.color);
    _readWheel();
    _readThird();
    _readField();
    _leadFromCurrent();
    _textFocus.addListener(() {
      // Selected the moment it is reached, so that a pasted colour replaces
      // what is there. A full field and a caret would make a paste twice as
      // long as the notation allows, and the half thrown away is the half
      // that was pasted.
      if (_textFocus.hasFocus) {
        // After the frame: the tap that brought the focus here puts the caret
        // where it landed, and it does that after this runs.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_textFocus.hasFocus || !mounted) return;
          _text.selection =
              TextSelection(baseOffset: 0, extentOffset: _text.text.length);
        });
        return;
      }
      // And whatever is half-typed goes back to the real colour when the
      // field is left, so a field holding "#ff" does not sit there looking
      // like a colour the picker is showing.
      setState(_write);
    });
    SavedColors.instance.load();
  }

  @override
  void didUpdateWidget(AppColorPicker old) {
    super.didUpdateWidget(old);
    // Only when somebody else has changed it. Taking it every time would undo
    // the slider positions this picker is holding on to.
    // ...and not while the colour modes are pointed at the far end of a
    // gradient, where widget.color is the end they are *not* editing.
    if (_editingStop < 0 && widget.color.toARGB32() != _current.toARGB32()) {
      _tookFromOutside(widget.color);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// _take reads a colour in from outside, keeping what it cannot say.
  void _take(Color color) {
    _rgb = Color(color.toARGB32()).withAlpha(255);
    _alpha = color.a;
    var hsv = HSVColor.fromColor(_rgb);
    // A colour with no saturation or no brightness cannot say what hue it is,
    // and a black cannot say how saturated it is: those come back as nought
    // from the conversion whatever the slider was pointing at. Keeping the
    // ones already held is the whole fix for a hue slider that did nothing
    // until a colour had been picked out of the square.
    if (hsv.saturation > 0 && hsv.value > 0) _hue = hsv.hue;
    if (hsv.value > 0) _sat = hsv.saturation;
    _write();
  }

  /// _tookFromOutside is _take followed by re-reading where that colour sits
  /// on every surface the picker draws, for each of the ways a colour can
  /// arrive that is not a drag on one of them.
  void _tookFromOutside(Color color) {
    _take(color);
    _readWheel();
    _readThird();
    _readField();
  }

  /// _readWheel works out where the colour in hand sits on the wheel of the
  /// notation in hand: the two are the same question only where the wheel is
  /// an HSV wheel.
  void _readWheel() {
    var (hue, sat) = _wheelOf(_current);
    _hue = hue;
    _sat = sat;
  }

  /// _wheelOf is where a colour sits on the wheel of the notation in hand.
  /// The hue it gives back is the one already held where the colour has none
  /// of its own -- a black, a grey, anything with no chroma in it.
  (double, double) _wheelOf(Color colour) {
    var hue = _hue;
    var sat = _sat;
    switch (_format) {
      case ColorFormat.hex:
      case ColorFormat.cmyk:
        var hsv = HSVColor.fromColor(colour);
        if (hsv.saturation > 0 && hsv.value > 0) hue = hsv.hue;
        if (hsv.value > 0) sat = hsv.saturation;
      case ColorFormat.hsl:
        var hsl = HSLColor.fromColor(colour);
        if (hsl.saturation > 0) hue = hsl.hue;
        sat = hsl.saturation;
      case ColorFormat.lab:
        var (_, a, b) = toLab(colour);
        var chroma = math.sqrt(a * a + b * b);
        if (chroma > 0.5) {
          hue = (math.atan2(b, a) * 180 / math.pi + 360) % 360;
        }
        sat = (chroma / 110).clamp(0.0, 1.0);
      case ColorFormat.grey:
        sat = 0;
    }
    return (hue, sat);
  }

  Color get _current => _rgb.withValues(alpha: _alpha.clamp(0, 1));

  /// _val is how bright the colour in hand is, for the places that want the
  /// number rather than the colour.
  double get _val => HSVColor.fromColor(_rgb).value;

  /// _pure is the colour at this hue, at full saturation and brightness: what
  /// the shade square is painted with and what the sliders point at.
  Color get _pure => HSVColor.fromAHSV(1, _hue, 1, 1).toColor();

  /// _colorAt is the colour a turn of the wheel and a distance out from its
  /// middle stand for, at a given third axis -- in the space the notation in
  /// hand works in.
  ///
  /// The wheel is painted with this and read with it, so what is picked is
  /// what was shown. Told to work in LAB, the wheel really is the a-b plane
  /// at a lightness; in CMYK the distance out is how much ink and the third
  /// axis is the black; in a greyscale there is no colour on it at all.
  Color _colorAt(double hue, double sat, double third) {
    switch (_format) {
      case ColorFormat.hex:
        return HSVColor.fromAHSV(1, hue, sat, third).toColor();
      case ColorFormat.hsl:
        return HSLColor.fromAHSL(1, hue, sat, third).toColor();
      case ColorFormat.cmyk:
        // The inks of the colour at this turn, with the black from the
        // third axis: what a printer would mix to reach it.
        var (c, m, y, _) = toCmyk(HSVColor.fromAHSV(1, hue, sat, 1).toColor());
        return fromCmyk(c, m, y, 1 - third);
      case ColorFormat.lab:
        var angle = hue * math.pi / 180;
        var chroma = sat * 110;
        return fromLab(
            third * 100, math.cos(angle) * chroma, math.sin(angle) * chroma);
      case ColorFormat.grey:
        var level = (third * 255).round().clamp(0, 255);
        return Color.fromARGB(255, level, level, level);
    }
  }

  /// _wheelColor is that colour at whatever the third axis is set to now.
  Color _wheelColor(double hue, double sat) => _colorAt(hue, sat, _third);

  /// _thirdName is what this notation calls its third axis, for the slider
  /// that sets it.
  String get _thirdName => switch (_format) {
        ColorFormat.hex => "Brightness",
        ColorFormat.hsl => "Lightness",
        ColorFormat.cmyk => "Ink",
        ColorFormat.lab => "Lightness",
        ColorFormat.grey => "Level",
      };

  /// _readThird works out where the third axis stands for the colour in
  /// hand, so that a notation opens where the last one left off.
  void _readThird() => _third = _thirdOf(_current);

  /// _thirdOf is where a colour sits on the axis the wheel has no room for.
  double _thirdOf(Color colour) {
    return switch (_format) {
      ColorFormat.hex => HSVColor.fromColor(colour).value,
      ColorFormat.hsl => HSLColor.fromColor(colour).lightness,
      ColorFormat.cmyk => 1 - toCmyk(colour).$4,
      ColorFormat.lab => (toLab(colour).$1 / 100).clamp(0.0, 1.0),
      ColorFormat.grey => (greyOf(colour) / 255).clamp(0.0, 1.0),
    };
  }

  /// _fromWheel takes the colour the wheel is showing at a turn and a
  /// distance out, and keeps those two as where the handle is.
  ///
  /// The wheel's own coordinates are the truth here, not the colour they
  /// make: in LAB and CMYK the colour cannot be asked where it came from
  /// exactly, so a handle placed from it would walk as it was dragged.
  void _fromWheel(double hue, double sat) {
    setState(() {
      _hue = hue;
      _sat = sat;
      _rgb = _wheelColor(hue, sat);
      _readField();
      _say();
    });
  }

  void _say() {
    _write();
    // Whichever end is selected. The three colour modes do not know there is
    // a gradient; this is the one place that decides which of its two
    // colours they have been editing.
    var g = _gradient;
    if (_editingStop >= 0 && g != null && _editingStop < g.ramp.length) {
      _gradient = g.withStop(
          _editingStop, g.ramp[_editingStop].copyWith(color: _current));
      widget.onGradientChanged?.call(_gradient);
      return;
    }
    widget.onChanged(_current);
  }

  /// _editEnd points the colour modes at one of the fade's colours, opening
  /// them on whatever that colour already is.
  void _editEnd(int stop) {
    var g = _gradient;
    setState(() {
      _editingStop = stop;
      _tookFromOutside(
          stop < 0 || g == null ? widget.color : g.ramp[stop].color);
      _leadFromCurrent();
    });
  }

  /// _setGradient writes the gradient out, and keeps the colour modes
  /// pointing at a colour that still exists.
  void _setGradient(GradientSpec? next) {
    setState(() {
      _gradient = next;
      if (next == null || _editingStop >= next.ramp.length) {
        _editingStop = -1;
        _tookFromOutside(widget.color);
        _leadFromCurrent();
      }
      widget.onGradientChanged?.call(next);
    });
  }

  /// _leadFromCurrent points the palette at the colour in hand and lays the
  /// five out around it. What happens when the palette is opened, when reset
  /// is pressed, and when a colour arrives from somewhere else.
  void _leadFromCurrent() {
    _leadHue = _hue;
    _leadSat = _sat <= 0 ? 0.8 : _sat;
    _leadVal = _third <= 0 ? 0.9 : _third;
    _locked = List.filled(5, false);
    _spread();
    _picked = 0;
  }

  /// _spread lays the five out from the colour they are led by, leaving
  /// alone any that have been locked.
  ///
  /// A custom set is never laid out: its five are wherever they have been
  /// put, and the whole point of it is that no rule moves them. Re-laid, the
  /// handle on the rim wiped out the arrangement it was supposed to be
  /// turning.
  void _spread() {
    var was = _spots;
    if (_harmony == ColorHarmony.custom && was.length == 5) return;
    _spots = [
      for (var (i, (turn, sat, val)) in _harmony.places.indexed)
        if (i < was.length && i < _locked.length && _locked[i])
          was[i]
        else
          _Spot(
            hue: (_leadHue + turn) % 360,
            sat: (_leadSat * sat).clamp(0.0, 1.0),
            third: (_leadVal * val).clamp(0.0, 1.0),
          ),
    ];
  }

  /// _spotColor is what one of the five looks like, in the notation in hand.
  Color _spotColor(_Spot spot) => _colorAt(spot.hue, spot.sat, spot.third);

  /// _brightenAll takes the whole set lighter or darker.
  ///
  /// An arrangement is re-laid at the new brightness. A custom set is not
  /// re-laid -- it has no rule to re-lay it by -- so each of its five is
  /// moved by the same proportion instead, which keeps whatever was built
  /// and changes only how bright it is.
  void _brightenAll(double to) {
    if (_harmony == ColorHarmony.custom && _spots.length == 5) {
      var by = _leadVal <= 0 ? 1.0 : to / _leadVal;
      _spots = [
        for (var (i, spot) in _spots.indexed)
          if (i < _locked.length && _locked[i])
            spot
          else
            _Spot(
                hue: spot.hue,
                sat: spot.sat,
                third: (spot.third * by).clamp(0.0, 1.0)),
      ];
      _leadVal = to;
      return;
    }
    _leadVal = to;
    _spread();
  }

  /// _turnAll points the set at a new turn of the wheel.
  ///
  /// An arrangement is re-laid around it, which is the same shape pointing
  /// somewhere else. A custom set has no shape to re-lay -- it is five
  /// colours somebody has placed -- so it is turned instead: every one of
  /// them moves by the same amount, which is what makes the handle on the
  /// rim a way of trying a custom set against every part of the wheel rather
  /// than a way of losing it.
  void _turnAll(double hue) {
    if (_harmony == ColorHarmony.custom) {
      var by = hue - _leadHue;
      _spots = [
        for (var (i, spot) in _spots.indexed)
          if (i < _locked.length && _locked[i])
            spot
          else
            _Spot(
                hue: (spot.hue + by) % 360 < 0
                    ? (spot.hue + by) % 360 + 360
                    : (spot.hue + by) % 360,
                sat: spot.sat,
                third: spot.third),
      ];
      _leadHue = hue;
      return;
    }
    _leadHue = hue;
    _spread();
  }

  /// _lead re-lays the set from one of its handles: a harmony is a shape, and
  /// moving one corner of it moves the shape.
  void _lead(int index, double hue, double sat) {
    // A locked colour stays where it is, whichever way it is pulled: it is
    // being kept while the rest of the set is worked out around it.
    if (index < _locked.length && _locked[index]) {
      setState(() => _pick(index));
      return;
    }
    if (_harmony == ColorHarmony.custom) {
      var next = [..._spots];
      next[index] = _Spot(hue: hue, sat: sat, third: _spots[index].third);
      setState(() {
        _spots = next;
        _pick(index);
      });
      return;
    }
    var (turn, satOf, _) = _harmony.places[index];
    var led = (hue - turn) % 360;
    setState(() {
      _leadHue = led < 0 ? led + 360 : led;
      if (satOf > 0) _leadSat = (sat / satOf).clamp(0.0, 1.0);
      _spread();
      _pick(index);
    });
  }

  /// _setSpot puts a colour into one of the five, by hand.
  ///
  /// What that means depends on which one: a locked colour, or any colour in
  /// a custom set, is simply set; one of an arrangement re-lays the
  /// arrangement around itself, exactly as dragging its handle does. Typing a
  /// hex into the second of a triad and having the other two stay where they
  /// were would not be a triad any more.
  void _setSpot(int index, Color colour) {
    if (index < 0 || index >= _spots.length) return;
    var (hue, sat) = _wheelOf(colour);
    var third = _thirdOf(colour);
    setState(() {
      if (_harmony == ColorHarmony.custom ||
          (index < _locked.length && _locked[index])) {
        var next = [..._spots];
        next[index] = _Spot(hue: hue, sat: sat, third: third);
        _spots = next;
        _pick(index);
        return;
      }
      var (turn, satOf, valOf) = _harmony.places[index];
      var led = (hue - turn) % 360;
      _leadHue = led < 0 ? led + 360 : led;
      if (satOf > 0) _leadSat = (sat / satOf).clamp(0.0, 1.0);
      if (valOf > 0) _leadVal = (third / valOf).clamp(0.0, 1.0);
      _spread();
      // And then this one exactly, because the arrangement cannot always
      // reach it: the fourth of a set of shades is drawn at a quarter of the
      // brightness it is led by, so a bright colour typed there would need a
      // lead four times brighter than there is room for, and what came back
      // was a darker colour than the one that had been typed. What is typed
      // is what that colour becomes; the rest follow the harmony around it.
      var next = [..._spots];
      next[index] = _Spot(hue: hue, sat: sat, third: third);
      _spots = next;
      _pick(index);
    });
  }

  /// _pick answers with one of the five.
  void _pick(int index) {
    _picked = index.clamp(0, _spots.length - 1);
    var spot = _spots[_picked];
    _hue = spot.hue;
    _sat = spot.sat;
    _rgb = _colorAt(spot.hue, spot.sat, spot.third);
    _readField();
    _say();
  }

  void _write() {
    var text = ColorText.write(_current, _format, alpha: widget.allowAlpha);
    if (_text.text != text) _text.text = text;
  }

  void _read(String typed) {
    var color = ColorText.read(typed, _format, _current);
    if (color == null) return;
    setState(() {
      _tookFromOutside(color);
      // Through _say, so that a colour typed in while the far end of a
      // gradient is selected lands on that end like every other way of
      // choosing one does.
      _say();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Told, never measured. A LayoutBuilder here reads better and does not
    // work: an AlertDialog asks what it holds how wide it would like to be,
    // and a LayoutBuilder cannot answer an intrinsic question -- it asserts.
    //
    // So the caller has to be right. pickPaint is, because it sets the
    // dialog's own margin and padding as well as reading them: see
    // dialogChrome, which is the one place that knows what stands between
    // the screen's edge and this.
    var width = widget.width;
    var theme = Theme.of(context).colorScheme;
    var wide = width >= _wideAt;
    // What is left after the numbers have had what they need, up to what the
    // colour column would like and down to what it will accept. The colour
    // column gives way first: a picker only just wide enough for two columns
    // should be two narrow ones rather than a comfortable one beside a strip.
    var pickerWidth = wide
        ? (width - _columnGap - _settingsColumn)
            .clamp(_pickerLeast, _pickerColumn)
        : width;

    var picking = switch (_mode) {
      ColorPickerMode.sliders => _slidersMode(theme, pickerWidth),
      ColorPickerMode.wheel => _wheelMode(theme, pickerWidth),
      ColorPickerMode.palette => _paletteMode(theme, pickerWidth),
      ColorPickerMode.gradient => _gradientMode(theme, pickerWidth),
    };

    var settings = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _channels(theme),
        const SizedBox(height: 14),
        _SavedRow(
          current: _current,
          onPick: (c) => setState(() {
            _tookFromOutside(c);
            _say();
          }),
        ),
      ],
    );

    // The ways of choosing run across the whole picker rather than across the
    // colour column only. They are the picker's own navigation, not a part of
    // the square underneath them -- and given the narrower column they wrapped
    // onto a second line, which moves everything below them down the dialog
    // for no reason at all.
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _modes(theme, width),
          const SizedBox(height: 10),
          if (!wide) ...[
            picking,
            const SizedBox(height: 14),
            settings,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: pickerWidth, child: picking),
                const SizedBox(width: _columnGap),
                Expanded(child: settings),
              ],
            ),
        ],
      ),
    );
  }

  /// _modes is the ways of choosing, across the top of the whole picker.
  Widget _modes(ColorScheme theme, double width) => SizedBox(
        width: width,
        child: Wrap(
          spacing: 0,
          runSpacing: 6,
          children: [
            for (var mode in _modesOffered)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  key: ValueKey("colorMode${mode.name}"),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setState(() {
                    _mode = mode;
                    // The palette opens on the colour in hand, so switching to
                    // it is a way of asking "what goes with this?".
                    if (mode == ColorPickerMode.palette) _leadFromCurrent();
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: _mode == mode ? theme.secondaryContainer : null,
                      border: Border.all(
                          color: _mode == mode
                              ? theme.secondaryContainer
                              : theme.outlineVariant),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(mode.icon,
                          size: 13,
                          color: _mode == mode
                              ? theme.onSecondaryContainer
                              : theme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(mode.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: _mode == mode
                                  ? theme.onSecondaryContainer
                                  : theme.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
            // Everything back to how the picker opened: the colour it was
            // given, hex, the harmony it starts on, nothing locked. Three
            // ways of choosing and five notations is a lot of state to have
            // fiddled with, and the way out of a tangle should not be closing
            // the dialog and opening it again.
            InkWell(
              key: const ValueKey("colorReset"),
              borderRadius: BorderRadius.circular(4),
              onTap: _reset,
              child: Tooltip(
                message: "Put every mode back to how it started",
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.outlineVariant),
                  ),
                  child: Icon(Icons.restart_alt,
                      size: 14, color: theme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      );

  /// _reset puts the picker back to how it opened.
  void _reset() {
    setState(() {
      _format = ColorFormat.hex;
      _harmony = ColorHarmony.analogous;
      _locked = List.filled(5, false);
      // The gradient too, and the end being edited with it: it is as much a
      // part of how the picker opened as the colour is, and a reset that
      // left a second colour behind would be a way out of half a tangle.
      _gradient = _openedGradient;
      _editingStop = -1;
      widget.onGradientChanged?.call(_gradient);
      _tookFromOutside(_opened);
      _leadFromCurrent();
      widget.onChanged(_current);
    });
  }

  /// _slidersMode is the field and the bars under it.
  ///
  /// Which field and which bars is the notation's business: hex picks a
  /// colour out of saturation against brightness under a hue slider, HSL out
  /// of saturation against lightness, CMYK out of cyan against magenta with
  /// the other two inks on sliders, LAB out of the a-b plane at a lightness,
  /// and greyscale out of a single ramp with no hue anywhere in sight. A
  /// notation that only changed the writing under the picker would be a
  /// label, not a way of working.
  Widget _slidersMode(ColorScheme theme, double width) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(theme, width),
          const SizedBox(height: 12),
          ..._fieldBars(theme, width),
          if (widget.allowAlpha) ...[
            const SizedBox(height: 10),
            _alphaBar(theme, width),
          ],
        ],
      );

  /// _field is the two-dimensional part of whichever notation is chosen.
  Widget _field(ColorScheme theme, double width) {
    var flat = _format == ColorFormat.grey;
    var height = flat ? 40.0 : width * 0.52;
    return _Draggable(
      onAt: (local, size, _) => _fromField(
          local.dx / size.width, flat ? _fy : local.dy / size.height),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          key: const ValueKey("colorShade"),
          size: Size(width, height),
          painter: _FieldPainter(
              at: _fieldColor, mark: Offset(_fx, _fy), flat: flat),
        ),
      ),
    );
  }

  /// _fieldBars are the sliders the chosen notation needs beside its field:
  /// the axes it has that the field has no room for.
  List<Widget> _fieldBars(ColorScheme theme, double width) {
    switch (_format) {
      case ColorFormat.hex:
      case ColorFormat.hsl:
        return [
          _bar(
            key: "colorHue",
            width: width,
            colors: _hueColors,
            at: _hue / 360,
            onAt: (f) => setState(() {
              _hue = f * 360;
              // The field is drawn in this hue, so the colour under the
              // handle is whatever the field now says there. The handle
              // itself does not move: a hue slider changes the colour, not
              // where in the square it was picked from.
              _rgb = _fieldColor(_fx, _fy);
              _readThird();
              _say();
            }),
            theme: theme,
          ),
        ];
      case ColorFormat.cmyk:
        return [
          _labelledBar(
            theme: theme,
            label: "Yellow",
            key: "colorYellow",
            width: width,
            colors: [
              fromCmyk(_fx, _fy, 0, _fw),
              fromCmyk(_fx, _fy, 1, _fw),
            ],
            at: _fz,
            onAt: (f) => setState(() {
              _fz = f;
              _fromField(_fx, _fy);
            }),
          ),
          const SizedBox(height: 10),
          _labelledBar(
            theme: theme,
            label: "Black",
            key: "colorBlack",
            width: width,
            colors: [
              fromCmyk(_fx, _fy, _fz, 0),
              fromCmyk(_fx, _fy, _fz, 1),
            ],
            at: _fw,
            onAt: (f) => setState(() {
              _fw = f;
              _fromField(_fx, _fy);
            }),
          ),
        ];
      case ColorFormat.lab:
        return [
          _labelledBar(
            theme: theme,
            label: "Lightness",
            key: "colorLightness",
            width: width,
            colors: [Colors.black, Colors.white],
            at: _fz,
            onAt: (f) => setState(() {
              _fz = f;
              _fromField(_fx, _fy);
            }),
          ),
        ];
      case ColorFormat.grey:
        // Nothing: a greyscale has one axis, and it is the ramp above.
        return const [];
    }
  }

  /// _wheelMode is hue round and saturation out, with brightness under it.
  ///
  /// The brightness slider is not decoration: a wheel says which colour and
  /// how much of it, and without a third control there is no way to reach a
  /// dark one at all.
  Widget _wheelMode(ColorScheme theme, double width) {
    var size = math.min(width, 260.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: _Draggable(
            onAt: (local, box, _) {
              var (hue, sat) = _wheelAt(local, box);
              _fromWheel(hue, sat);
            },
            child: CustomPaint(
              key: const ValueKey("colorWheel"),
              size: Size(size, size),
              painter: _WheelPainter(
                at: _wheelColor,
                marks: [(_hue, _sat, _current, true)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _labelledBar(
          theme: theme,
          label: _thirdName,
          key: "colorValue",
          width: width,
          colors: [
            _colorAt(_hue, _sat, 0),
            _colorAt(_hue, _sat, 1),
          ],
          at: _third,
          onAt: (f) => setState(() {
            _third = f;
            _rgb = _wheelColor(_hue, _sat);
            _readField();
            _say();
          }),
        ),
        if (widget.allowAlpha) ...[
          const SizedBox(height: 10),
          _labelledBar(
            theme: theme,
            label: "Opacity",
            key: "colorAlpha",
            width: width,
            colors: [_pure.withValues(alpha: 0), _pure],
            at: _alpha,
            checker: true,
            onAt: (f) => setState(() {
              _alpha = f;
              _say();
            }),
          ),
        ],
      ],
    );
  }

  /// _paletteMode is five colours at once.
  /// _gradientMode is the colours a fade runs through, and how it runs.
  ///
  /// There is no "make this a gradient" switch. A colour with one point on
  /// the bar is a flat colour and a colour with two is a fade, which is the
  /// same thing the switch used to say and one control fewer to find.
  ///
  /// The fade itself is shown full size, at the same height the colour square
  /// is, and painted with the very shader the painters use -- so the angle and
  /// the radial switch are things you watch happen rather than things you set
  /// and go and look at. The points live on a bar under it, where they can be
  /// dragged along a straight line whichever way the gradient itself is
  /// pointing.
  Widget _gradientMode(ColorScheme theme, double width) {
    var g = _gradient;
    var label = TextStyle(fontSize: 11, color: theme.onSurfaceVariant);
    var chosen = _chosenColour();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GradientPreview(
            key: const ValueKey("gradientPreview"),
            paint: PaintSpec(widget.color, gradient: g),
            width: width,
            // Shorter than the colour square: the fade and the square that
            // picks its colours are both on this tab now, and a full-height
            // preview pushed the square off the bottom of the dialog.
            height: width * 0.34,
            outline: theme.outlineVariant,
          ),
          const SizedBox(height: 8),
          // The points, and the buttons that add one and take one away. On a
          // straight bar however the gradient itself is pointing: dragging a
          // handle round a radial fade is not a thing anybody can aim.
          Row(children: [
            _GradientBar(
              key: const ValueKey("gradientBar"),
              from: widget.color,
              spec: g,
              editing: _editingStop,
              onPick: _editEnd,
              onMove: (index, at) {
                if (g == null) return;
                _setGradient(index < 0
                    ? g.copyWith(start: at)
                    : g.withStop(index, g.ramp[index].copyWith(at: at)));
              },
              onBias: (index, bias) {
                if (g == null) return;
                _setGradient(
                    g.withStop(index, g.ramp[index].copyWith(bias: bias)));
              },
              width: math.max(60, width - _stopButtons * 2),
            ),
            _GradientStopButton(
              key: const ValueKey("gradientAdd"),
              icon: Icons.add,
              width: _stopButtons,
              tip: g == null
                  ? "Fade to a second colour"
                  : "Another colour in the fade",
              // The first press is what turns a flat colour into a fade.
              onTap: () {
                if (g == null) {
                  _setGradient(GradientSpec(to: _fadeTowards(widget.color)));
                  _editEnd(0);
                  return;
                }
                var (next, index) = g.plus();
                _setGradient(next);
                _editEnd(index);
              },
            ),
            _GradientStopButton(
              key: const ValueKey("gradientRemove"),
              icon: Icons.remove,
              width: _stopButtons,
              tip: g == null
                  ? "One colour already"
                  : "Take this colour out of the fade",
              // And taking the last one out is what turns it back.
              onTap: g == null || _editingStop < 0
                  ? null
                  : () {
                      var next = g.minus(_editingStop);
                      _editingStop =
                          math.min(_editingStop, (next?.count ?? 2) - 2);
                      _setGradient(next);
                    },
            ),
          ]),
          const SizedBox(height: 6),
          Text(g == null ? "One colour" : _editingName(g), style: label),
          // And the square to choose that colour with, right here.
          //
          // The three colour tabs have always edited whichever point is
          // picked -- see _say -- but having to leave the fade to use them
          // meant choosing a colour without seeing the fade it is in, which
          // is the one thing this tab is for. The same field and the same
          // bars, so there is one place that knows how a colour is picked.
          const SizedBox(height: 10),
          _field(theme, width),
          const SizedBox(height: 12),
          ..._fieldBars(theme, width),
          if (g != null) ...[
            const SizedBox(height: 10),
            // Which way it runs. A radial one runs outwards from the middle
            // and has no direction, so the angle goes away rather than
            // sitting there doing nothing.
            Row(children: [
              _GradientShapeButton(
                key: const ValueKey("gradientLinear"),
                icon: Icons.linear_scale,
                label: "Straight",
                on: !g.radial,
                onTap: () => _setGradient(g.copyWith(radial: false)),
              ),
              const SizedBox(width: 6),
              _GradientShapeButton(
                key: const ValueKey("gradientRadial"),
                icon: Icons.blur_circular,
                label: "Radial",
                on: g.radial,
                onTap: () => _setGradient(g.copyWith(radial: true)),
              ),
            ]),
            if (!g.radial)
              _gradientSlider(
                theme,
                key: const ValueKey("gradientAngle"),
                name: "Angle",
                value: g.angle.clamp(0, 360),
                max: 360,
                divisions: 72,
                reading: "${g.angle.round()}\u00B0",
                onChanged: (v) => _setGradient(g.copyWith(angle: v)),
              ),
          ],
          // How see-through the colour in hand is. Per point, so a fade can
          // run from a colour to nothing -- which is most of what a gradient
          // on a chart or a picture is actually for.
          if (widget.allowAlpha)
            _gradientSlider(
              theme,
              key: const ValueKey("gradientOpacity"),
              name: "Opacity",
              value: chosen.a,
              max: 1,
              divisions: 100,
              reading: "${(chosen.a * 100).round()}%",
              onChanged: (v) => _setChosen(chosen.withValues(alpha: v)),
            ),
        ],
      ),
    );
  }

  /// _chosenColour is the colour the gradient tab is working on: one of the
  /// fade's, or the flat colour when there is no fade.
  Color _chosenColour() {
    var g = _gradient;
    if (g == null || _editingStop < 0 || _editingStop >= g.ramp.length) {
      return widget.color;
    }
    return g.ramp[_editingStop].color;
  }

  /// _setChosen writes a colour back to wherever the tab is working, and
  /// brings the rest of the picker with it.
  void _setChosen(Color colour) {
    setState(() {
      _take(colour);
      _readWheel();
      _readThird();
      _readField();
      _say();
    });
  }

  /// _gradientSlider is one named number with its reading beside it. Three of
  /// these in a row is most of the gradient tab.
  Widget _gradientSlider(
    ColorScheme theme, {
    required Key key,
    required String name,
    required double value,
    required double max,
    required int divisions,
    required String reading,
    required ValueChanged<double> onChanged,
  }) {
    var label = TextStyle(fontSize: 11, color: theme.onSurfaceVariant);
    return Row(children: [
      SizedBox(width: 54, child: Text(name, style: label)),
      Expanded(
        child: Slider(
          key: key,
          value: value,
          max: max,
          divisions: divisions,
          label: reading,
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 48, child: Text(reading, style: label)),
    ]);
  }

  /// _editingName says which colour the rest of the picker is working on.
  String _editingName(GradientSpec g) {
    if (_editingStop < 0) return "Editing the first colour";
    if (_editingStop == 0 && g.count == 2) return "Editing the second colour";
    return "Editing colour ${_editingStop + 2} of ${g.count}";
  }

  /// _fadeTowards is what a gradient starts out running to: the same colour
  /// most of the way to black, or to white where it is already dark.
  ///
  /// A second colour that is visibly related to the first. Starting on a flat
  /// black meant every new gradient's first job was to be undone.
  Color _fadeTowards(Color from) {
    var hsv = HSVColor.fromColor(Color(from.toARGB32()).withAlpha(255));
    var value = hsv.value > 0.4 ? hsv.value * 0.35 : 0.9;
    return hsv
        .withValue(value.clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: from.a);
  }

  Widget _paletteMode(ColorScheme theme, double width) {
    // The disc itself the same size as the wheel mode's: the box is bigger by
    // the margin the handle on the rim runs in, rather than the wheel being
    // smaller by it.
    var size = math.min(width, 260.0 + _wheelMargin * 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: _Draggable(
            onAt: (local, box, first) {
              var (hue, sat) = _wheelAt(local, box, ringed: true);
              // What was grabbed is decided when the drag starts and held for
              // the rest of it. The handle outside the disc takes the whole
              // set with it: the arrangement keeps its shape and turns.
              if (first) {
                _grabbed = _onRing(local, box) ? -1 : _nearestSpot(hue, sat);
              }
              if (_grabbed < 0) {
                setState(() {
                  _turnAll(hue);
                  _pick(_picked);
                });
                return;
              }
              _lead(_grabbed, hue, sat);
            },
            child: CustomPaint(
              key: const ValueKey("colorPaletteWheel"),
              size: Size(size, size),
              painter: _WheelPainter(
                // At the palette's own brightness, not the wheel mode's: the
                // slider under this wheel sets how bright the *set* is, so
                // the disc it is picked out of has to be showing that. Drawn
                // at the other one, the only things that moved when the
                // slider moved were the five dots.
                at: (hue, sat) => _colorAt(hue, sat, _leadVal),
                locked: {
                  for (var i = 0; i < _locked.length; i++)
                    if (_locked[i]) i,
                },
                ring: _leadHue,
                marks: [
                  for (var i = 0; i < _spots.length; i++)
                    (
                      _spots[i].hue,
                      _spots[i].sat,
                      _spotColor(_spots[i]),
                      i == _picked
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ColorHarmony>(
                key: const ValueKey("colorHarmony"),
                isDense: true,
                isExpanded: true,
                value: _harmony,
                style: TextStyle(fontSize: 12, color: theme.onSurface),
                items: [
                  for (var h in ColorHarmony.values)
                    DropdownMenuItem(value: h, child: Text(h.label)),
                ],
                onChanged: (h) => setState(() {
                  _harmony = h ?? _harmony;
                  _spread();
                  _pick(_picked);
                }),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // The five, with the one being answered with ringed. Pressing one is
        // how the picker is pointed at it, and the padlock under it is how a
        // colour is kept while the rest are still being worked on.
        Row(
          children: [
            for (var i = 0; i < _spots.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: ValueKey("paletteSpot$i"),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _pick(i)),
                        child: Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color:
                                _spotColor(_spots[i]).withValues(alpha: _alpha),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: i == _picked
                                  ? theme.primary
                                  : theme.outlineVariant,
                              width: i == _picked ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: ValueKey("paletteLock$i"),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _locked[i] = !_locked[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Icon(
                            _locked[i] ? Icons.lock : Icons.lock_open,
                            size: 13,
                            color: _locked[i]
                                ? theme.primary
                                : theme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      // The colour itself, typed. A palette usually starts
                      // from a colour somebody already has -- a brand, a
                      // photograph, a page being matched -- and the way that
                      // colour arrives is as six characters.
                      _SpotHex(
                        key: ValueKey("paletteHex$i"),
                        color: _spotColor(_spots[i]),
                        onChanged: (c) => _setSpot(i, c),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _labelledBar(
          theme: theme,
          label: _thirdName,
          key: "paletteValue",
          width: width,
          colors: [
            _colorAt(_leadHue, _leadSat, 0),
            _colorAt(_leadHue, _leadSat, 1),
          ],
          at: _leadVal,
          onAt: (f) => setState(() {
            _brightenAll(f.clamp(0.02, 1.0));
            _pick(_picked);
          }),
        ),
        if (widget.allowAlpha) ...[
          const SizedBox(height: 10),
          _labelledBar(
            theme: theme,
            label: "Opacity",
            key: "colorAlpha",
            width: width,
            colors: [_pure.withValues(alpha: 0), _pure],
            at: _alpha,
            checker: true,
            onAt: (f) => setState(() {
              _alpha = f;
              _say();
            }),
          ),
        ],
      ],
    );
  }

  /// _wheelAt is the hue and saturation a point on the wheel stands for.
  (double, double) _wheelAt(Offset local, Size box, {bool ringed = false}) {
    var centre = Offset(box.width / 2, box.height / 2);
    var away = local - centre;
    var radius = wheelRadius(box, ringed: ringed);
    var hue = (math.atan2(away.dy, away.dx) * 180 / math.pi + 360) % 360;
    return (hue, (away.distance / radius).clamp(0.0, 1.0));
  }

  /// _onRing is whether a press landed outside the disc, where the handle
  /// that moves the whole set runs.
  bool _onRing(Offset local, Size box) {
    var centre = Offset(box.width / 2, box.height / 2);
    return (local - centre).distance >
        wheelRadius(box, ringed: true) + _wheelMargin * 0.1;
  }

  /// _nearestSpot is which of the five a press was aimed at.
  int _nearestSpot(double hue, double sat) {
    var best = 0;
    var closest = double.infinity;
    for (var i = 0; i < _spots.length; i++) {
      var turn = (_spots[i].hue - hue).abs();
      if (turn > 180) turn = 360 - turn;
      // Degrees and saturation are not the same units; a whole turn is
      // counted as being worth the whole radius, which is what makes picking
      // between a near handle and a far one behave.
      var d = math.sqrt(
          math.pow(turn / 180, 2) + math.pow((_spots[i].sat - sat) * 1.2, 2));
      if (d < closest) {
        closest = d;
        best = i;
      }
    }
    return best;
  }

  List<Color> get _hueColors => const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ];

  Widget _alphaBar(ColorScheme theme, double width) => _bar(
        key: "colorAlpha",
        width: width,
        colors: [_pure.withValues(alpha: 0), _pure],
        at: _alpha,
        checker: true,
        theme: theme,
        onAt: (f) => setState(() {
          _alpha = f;
          _say();
        }),
      );

  Widget _bar({
    required String key,
    required double width,
    required List<Color> colors,
    required double at,
    required ValueChanged<double> onAt,
    required ColorScheme theme,
    bool checker = false,
  }) =>
      _Draggable(
        onAt: (local, size, _) => onAt((local.dx / size.width).clamp(0.0, 1.0)),
        child: CustomPaint(
          key: ValueKey(key),
          size: Size(width, 18),
          painter: _BarPainter(
              colors: colors,
              at: at,
              checker: checker,
              ring: theme.outlineVariant),
        ),
      );

  /// _labelledBar is a bar with its name beside it, for the two that are not
  /// obvious from their colours.
  Widget _labelledBar({
    required ColorScheme theme,
    required String label,
    required String key,
    required double width,
    required List<Color> colors,
    required double at,
    required ValueChanged<double> onAt,
    bool checker = false,
  }) {
    var caption = 66.0;
    return Row(children: [
      SizedBox(
        width: caption,
        child: Text(label,
            style: TextStyle(fontSize: 10, color: theme.onSurfaceVariant)),
      ),
      _bar(
        key: key,
        width: math.max(60, width - caption),
        colors: colors,
        at: at,
        onAt: onAt,
        theme: theme,
        checker: checker,
      ),
    ]);
  }

  /// _channels is the four numbers and the notation under them.
  /// _channels is the four numbers, the notation and the field.
  ///
  /// Told nothing about how wide it is. Everything in here fills the column
  /// it is given instead, because a width worked out by the caller and a
  /// width actually handed down by the layout are two different numbers the
  /// moment a dialog trims anything -- and the difference comes out as an
  /// overflow stripe rather than as a narrower picker.
  Widget _channels(ColorScheme theme) {
    var c = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrapped rather than a row: in the narrowest dialog four boxes and
        // their gaps are wider than the column, and a Row that does not fit
        // is a stripe rather than a second line.
        Wrap(children: [
          _ChannelField(
              label: "R",
              value: (c.r * 255).roundToDouble(),
              onChanged: (v) => _channel(0, v)),
          _ChannelField(
              label: "G",
              value: (c.g * 255).roundToDouble(),
              onChanged: (v) => _channel(1, v)),
          _ChannelField(
              label: "B",
              value: (c.b * 255).roundToDouble(),
              onChanged: (v) => _channel(2, v)),
          if (widget.allowAlpha)
            _ChannelField(
                label: "A",
                value: (_alpha * 255).roundToDouble(),
                onChanged: (v) => setState(() {
                      _alpha = (v / 255).clamp(0.0, 1.0);
                      _say();
                    })),
        ]),
        const SizedBox(height: 10),
        // The notation and the value in it, laid out the way a channel is:
        // the name over the box rather than beside it, so this row and the
        // one above line up instead of sitting at two different heights. The
        // name is the dropdown -- what the field is holding is the title it
        // needs.
        SizedBox(
          height: 16,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ColorFormat>(
              key: const ValueKey("colorFormat"),
              isDense: true,
              value: _format,
              iconSize: 16,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.onSurfaceVariant),
              items: [
                for (var f in ColorFormat.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (f) => setState(() {
                _format = f ?? _format;
                // Where the colour sits in the new notation's field, and
                // -- for greyscale -- the fact that it no longer has a hue
                // to sit at. Told to work in greys, the picker works in
                // greys, and the grey it starts from is how bright the
                // colour was: dropping the saturation and keeping the value
                // instead turns a dark red into a light grey, because
                // brightness in HSV is not brightness to an eye.
                if (_format == ColorFormat.grey) {
                  var level = greyOf(_current).round().clamp(0, 255);
                  _rgb = Color.fromARGB(255, level, level, level);
                  _sat = 0;
                }
                _readWheel();
                _readThird();
                _readField();
                _write();
                _say();
              }),
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 30,
          width: double.infinity,
          child: TextField(
            key: const ValueKey("colorPickerHex"),
            controller: _text,
            focusNode: _textFocus,
            // No monospace: the family is not on every machine this runs on,
            // and what came of asking for one was a hex whose "ff" sat tight
            // and whose other characters did not.
            style: const TextStyle(fontSize: 12, letterSpacing: 0.6),
            decoration: InputDecoration(
              isDense: true,
              prefixText: _format == ColorFormat.hex ? "#" : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: const OutlineInputBorder(),
              hintText: ColorText.hint(_format, widget.allowAlpha),
              hintStyle: TextStyle(
                  fontSize: 11,
                  color: theme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
            inputFormatters: [
              if (_format == ColorFormat.hex)
                FilteringTextInputFormatter.allow(RegExp(r"[0-9a-fA-F#]"))
              else
                FilteringTextInputFormatter.allow(RegExp(r"[0-9,.\-% ]")),
              _KeepWhatArrived(24),
            ],
            onChanged: _read,
            onSubmitted: _read,
          ),
        ),
      ],
    );
  }

  /// _readField works out where the colour in hand sits in the field the
  /// chosen notation draws. Called when the notation changes and whenever a
  /// colour arrives from anywhere but the field itself.
  void _readField() {
    var colour = _current;
    switch (_format) {
      case ColorFormat.hex:
        _fx = _sat;
        _fy = 1 - _val;
      case ColorFormat.hsl:
        var hsl = HSLColor.fromColor(colour);
        _fx = hsl.saturation;
        _fy = 1 - hsl.lightness;
      case ColorFormat.cmyk:
        var (c, m, y, k) = toCmyk(colour);
        _fx = c;
        _fy = m;
        _fz = y;
        _fw = k;
      case ColorFormat.lab:
        var (l, a, b) = toLab(colour);
        _fx = ((a + 110) / 220).clamp(0.0, 1.0);
        _fy = 1 - ((b + 110) / 220).clamp(0.0, 1.0);
        _fz = (l / 100).clamp(0.0, 1.0);
      case ColorFormat.grey:
        _fx = (greyOf(colour) / 255).clamp(0.0, 1.0);
    }
  }

  /// _fieldColor is the colour at a place in the field, given whatever its
  /// extra sliders are set to. The field is painted with this and read with
  /// it, so what is picked is what was shown.
  Color _fieldColor(double x, double y) {
    switch (_format) {
      case ColorFormat.hex:
        return HSVColor.fromAHSV(1, _hue, x, 1 - y).toColor();
      case ColorFormat.hsl:
        return HSLColor.fromAHSL(1, _hue, x, 1 - y).toColor();
      case ColorFormat.cmyk:
        return fromCmyk(x, y, _fz, _fw);
      case ColorFormat.lab:
        return fromLab(_fz * 100, x * 220 - 110, (1 - y) * 220 - 110);
      case ColorFormat.grey:
        var level = (x * 255).round();
        return Color.fromARGB(255, level, level, level);
    }
  }

  /// _fromField takes the colour the field is showing at [x], [y].
  void _fromField(double x, double y) {
    setState(() {
      _fx = x.clamp(0.0, 1.0);
      _fy = y.clamp(0.0, 1.0);
      // The field is the truth here, so the colour is read out of it rather
      // than the other way round -- and the handle stays exactly where it was
      // put even where the notation cannot express the colour precisely.
      _rgb = _fieldColor(_fx, _fy);
      _readThird();
      _say();
    });
  }

  /// _channel sets one of red, green and blue, keeping the other two.
  void _channel(int index, double to) {
    var c = _current;
    var next = Color.fromARGB(
      (_alpha * 255).round(),
      index == 0 ? to.round() : (c.r * 255).round(),
      index == 1 ? to.round() : (c.g * 255).round(),
      index == 2 ? to.round() : (c.b * 255).round(),
    );
    setState(() {
      _tookFromOutside(next);
      _say();
    });
  }
}

/// _ColorText is a colour written out in one notation, and read back from it.
///
/// Its own thing rather than four methods on the picker, so that the sums --
/// which are the only part of this file that can be wrong in a way nobody
/// sees -- can be tested without a widget.
class ColorText {
  /// write is [color] in [format], without the leading # or any units.
  static String write(Color color, ColorFormat format, {bool alpha = true}) {
    switch (format) {
      case ColorFormat.hex:
        var value = color.toARGB32();
        return alpha
            ? value.toRadixString(16).padLeft(8, "0")
            : (value & 0xFFFFFF).toRadixString(16).padLeft(6, "0");
      case ColorFormat.hsl:
        var hsl = HSLColor.fromColor(color);
        return "${hsl.hue.round()}, ${(hsl.saturation * 100).round()}%, "
            "${(hsl.lightness * 100).round()}%";
      case ColorFormat.cmyk:
        var (c, m, y, k) = toCmyk(color);
        return "${(c * 100).round()}, ${(m * 100).round()}, "
            "${(y * 100).round()}, ${(k * 100).round()}";
      case ColorFormat.lab:
        var (l, a, b) = toLab(color);
        return "${l.round()}, ${a.round()}, ${b.round()}";
      case ColorFormat.grey:
        return greyOf(color).round().toString();
    }
  }

  /// read is what [typed] means in [format], or null if it means nothing yet.
  ///
  /// Nothing yet rather than nothing at all: this is called on every
  /// keystroke, and half of a colour is what a colour looks like while it is
  /// being typed.
  static Color? read(String typed, ColorFormat format, Color was) {
    if (format == ColorFormat.hex) {
      var clean = typed.replaceAll("#", "").trim();
      if (clean.length != 6 && clean.length != 8) return null;
      var value = int.tryParse(clean, radix: 16);
      if (value == null) return null;
      return Color(clean.length == 6 ? 0xFF000000 | value : value);
    }

    var numbers = [
      for (var part in typed.split(RegExp(r"[^0-9\.\-]+")))
        if (part.isNotEmpty) double.tryParse(part),
    ];
    if (numbers.any((n) => n == null)) return null;
    var n = numbers.cast<double>();
    var alpha = was.a;

    switch (format) {
      case ColorFormat.hex:
        return null;
      case ColorFormat.hsl:
        if (n.length < 3) return null;
        return HSLColor.fromAHSL(alpha, n[0] % 360, (n[1] / 100).clamp(0, 1),
                (n[2] / 100).clamp(0, 1))
            .toColor();
      case ColorFormat.cmyk:
        if (n.length < 4) return null;
        return fromCmyk(n[0] / 100, n[1] / 100, n[2] / 100, n[3] / 100)
            .withValues(alpha: alpha);
      case ColorFormat.lab:
        if (n.length < 3) return null;
        return fromLab(n[0], n[1], n[2]).withValues(alpha: alpha);
      case ColorFormat.grey:
        if (n.isEmpty) return null;
        var level = n[0].clamp(0, 255).round();
        return Color.fromARGB((alpha * 255).round(), level, level, level);
    }
  }

  /// hint is what an empty field should say it wants.
  static String hint(ColorFormat format, bool alpha) => switch (format) {
        ColorFormat.hex => alpha ? "aarrggbb" : "rrggbb",
        ColorFormat.hsl => "h, s%, l%",
        ColorFormat.cmyk => "c, m, y, k",
        ColorFormat.lab => "l, a, b",
        ColorFormat.grey => "0-255",
      };
}

/// toCmyk is the four inks, as fractions.
(double, double, double, double) toCmyk(Color color) {
  double r = color.r, g = color.g, b = color.b;
  double k = 1 - math.max(r, math.max(g, b));
  if (k >= 1) return (0.0, 0.0, 0.0, 1.0);
  return (
    (1 - r - k) / (1 - k),
    (1 - g - k) / (1 - k),
    (1 - b - k) / (1 - k),
    k,
  );
}

/// fromCmyk is the colour those four inks make.
Color fromCmyk(double c, double m, double y, double k) {
  double channel(double ink) =>
      ((1 - ink.clamp(0.0, 1.0)) * (1 - k.clamp(0.0, 1.0))).clamp(0.0, 1.0);
  return Color.fromARGB(255, (channel(c) * 255).round(),
      (channel(m) * 255).round(), (channel(y) * 255).round());
}

/// toLab is CIE L*a*b*, by way of XYZ, against the D65 white point.
///
/// Written out rather than reached for, because it is twenty lines and the
/// alternative is a package for four numbers.
(double, double, double) toLab(Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  var r = linear(color.r), g = linear(color.g), b = linear(color.b);
  var x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  var y = (r * 0.2126 + g * 0.7152 + b * 0.0722);
  var z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;

  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + (16 / 116);

  var fx = f(x), fy = f(y), fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// fromLab is the way back.
Color fromLab(double l, double a, double b) {
  var fy = (l + 16) / 116;
  var fx = fy + a / 500;
  var fz = fy - b / 200;

  double back(double t) =>
      t * t * t > 0.008856 ? t * t * t : (t - 16 / 116) / 7.787;

  var x = back(fx) * 0.95047, y = back(fy), z = back(fz) * 1.08883;
  var r = x * 3.2406 + y * -1.5372 + z * -0.4986;
  var g = x * -0.9689 + y * 1.8758 + z * 0.0415;
  var bb = x * 0.0557 + y * -0.2040 + z * 1.0570;

  double gamma(double channel) {
    var v = channel <= 0.0031308
        ? channel * 12.92
        : 1.055 * math.pow(channel, 1 / 2.4).toDouble() - 0.055;
    return v.clamp(0.0, 1.0);
  }

  return Color.fromARGB(255, (gamma(r) * 255).round(), (gamma(g) * 255).round(),
      (gamma(bb) * 255).round());
}

/// greyOf is how bright a colour is, 0 to 255, weighted the way an eye sees
/// it rather than as a flat average of the three channels.
double greyOf(Color color) =>
    (0.299 * color.r + 0.587 * color.g + 0.114 * color.b) * 255;

/// _SavedRow is the two rows of kept colours, and the pair of buttons that
/// put one there and take it away again.
class _SavedRow extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onPick;

  const _SavedRow({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    // The scheme Material is already using, which is the app's own palette --
    // see ThemeNotifier.colors, which is where MaterialApp's scheme comes
    // from. Read this way round, the picker works in any context with a
    // Theme above it, rather than only where the notifier has been provided.
    var theme = Theme.of(context).colorScheme;
    var saved = SavedColors.instance;
    return ListenableBuilder(
      listenable: saved,
      builder: (context, _) {
        var colors = saved.colors;
        var kept = saved.has(current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              // Flexible, so on the narrowest phone the heading gives way
              // rather than pushing the two buttons off the end of the row.
              // The buttons are the part you cannot do without.
              Flexible(
                child: Text(
                  "SAVED COLOURS",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                    color: theme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const Spacer(),
              // Add keeps what the picker is showing; remove takes away the
              // saved colour it is showing. One of the two is always the
              // wrong thing to press, so the wrong one is always the one
              // that is greyed out.
              IconButton(
                key: const ValueKey("saveColor"),
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: saved.isFull
                    ? "There is room for $savedColorsLimit saved colours"
                    : kept
                        ? "This colour is already saved"
                        : "Keep this colour",
                onPressed:
                    kept || saved.isFull ? null : () => saved.add(current),
              ),
              IconButton(
                key: const ValueKey("forgetColor"),
                icon: const Icon(Icons.remove, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: kept
                    ? "Forget this colour"
                    : "Choose a saved colour to forget it",
                onPressed: kept ? () => saved.remove(current) : null,
              ),
            ]),
            const SizedBox(height: 2),
            if (colors.isEmpty)
              Text(
                "Colours you keep here are offered by every picker in the app.",
                style: TextStyle(fontSize: 11, color: theme.onSurfaceVariant),
              )
            else
              SizedBox(
                key: const ValueKey("savedSwatches"),
                width: double.infinity,
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (var c in colors)
                      _Swatch(
                        color: c,
                        chosen: c.toARGB32() == current.toARGB32(),
                        onTap: () => onPick(c),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool chosen;
  final VoidCallback onTap;

  const _Swatch(
      {required this.color, required this.chosen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // The scheme Material is already using, which is the app's own palette --
    // see ThemeNotifier.colors, which is where MaterialApp's scheme comes
    // from. Read this way round, the picker works in any context with a
    // Theme above it, rather than only where the notifier has been provided.
    var theme = Theme.of(context).colorScheme;
    return Tooltip(
      message: "#${color.toARGB32().toRadixString(16).padLeft(8, "0")}",
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              // The chosen one is ringed, which is also how somebody knows
              // the remove button is about to remove *this* one.
              color: chosen ? theme.primary : theme.outlineVariant,
              width: chosen ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CustomPaint(painter: _SwatchPainter(color)),
          ),
        ),
      ),
    );
  }
}

/// _channelWidth is how wide one channel's box is, and so how wide the
/// caption over it is: the two are the same number in one place, or they
/// drift apart and the caption stops sitting over what it names.
const double _channelWidth = 46;

/// _KeepWhatArrived is a length limit that keeps the new characters rather
/// than the old ones.
///
/// LengthLimitingTextInputFormatter truncates from the end, which is the
/// wrong end for a box that is always full: six hex characters of six, three
/// digits of three. Pasting a colour with the caret sitting anywhere in one
/// gives twelve characters, and the six that survive are the six that were
/// already there -- so the paste appears to do nothing at all.
///
/// What is kept instead is the run of characters ending where the caret
/// finished, which is exactly what was typed or pasted.
class _KeepWhatArrived extends TextInputFormatter {
  final int max;
  const _KeepWhatArrived(this.max);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue fresh) {
    if (fresh.text.length <= max) return fresh;
    var end = fresh.selection.end < 0 ? fresh.text.length : fresh.selection.end;
    end = end.clamp(0, fresh.text.length);
    var start = math.max(0, end - max);
    var kept = fresh.text.substring(start, end);
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

/// _SpotHex is the hex of one of the palette's five, which can be typed over.
///
/// Six characters and no alpha: a palette is about which colours, and how
/// see-through they are is one setting for the set rather than five.
class _SpotHex extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  const _SpotHex({required this.color, required this.onChanged, super.key});

  @override
  State<_SpotHex> createState() => _SpotHexState();
}

class _SpotHexState extends State<_SpotHex> {
  late final TextEditingController _text =
      TextEditingController(text: _hexOf(widget.color));
  final FocusNode _focus = FocusNode();

  static String _hexOf(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0");

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // The whole of it, selected, the moment it is reached. A hex box is
        // always full -- six characters of six -- so anything pasted into it
        // with the caret merely sitting somewhere would be twelve characters
        // long, and the limit would throw away the half that was pasted.
        // Selected, a paste replaces it, which is the only thing anybody
        // pastes a colour in order to do.
        //
        // After the frame, because the tap that brought the focus here puts
        // the caret where it landed, and it does that after this runs.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_focus.hasFocus || !mounted) return;
          _text.selection =
              TextSelection(baseOffset: 0, extentOffset: _text.text.length);
        });
        return;
      }
      // And what is half-typed goes back to the colour when the field is
      // left, so a box holding "3f" does not sit there looking like a colour.
      setState(() => _text.text = _hexOf(widget.color));
    });
  }

  @override
  void didUpdateWidget(_SpotHex old) {
    super.didUpdateWidget(old);
    // Not while it is being typed into: at that moment the field is the one
    // place the colour is coming *from*.
    if (!_focus.hasFocus && widget.color != old.color) {
      _text.text = _hexOf(widget.color);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _read(String typed) {
    var clean = typed.replaceAll("#", "").trim();
    if (clean.length != 6) return;
    var value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    widget.onChanged(Color(0xFF000000 | value));
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 22,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9.5, color: theme.onSurfaceVariant),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 1, vertical: 4),
          border: OutlineInputBorder(),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r"[0-9a-fA-F]")),
          _KeepWhatArrived(6),
        ],
        onChanged: _read,
        onSubmitted: _read,
      ),
    );
  }
}

/// _ChannelField is one channel: a caption that scrubs and a box that types.
class _ChannelField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ChannelField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ChannelField> createState() => _ChannelFieldState();
}

class _ChannelFieldState extends State<_ChannelField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value.round().toString());
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Selected on arrival, for the same reason the hex boxes are: a channel
    // reading 255 is three characters of three, and typing or pasting into
    // it with a caret is three characters that go nowhere.
    _focus.addListener(() {
      if (!_focus.hasFocus) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_focus.hasFocus || !mounted) return;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      });
    });
  }

  /// _from and _startX are where a drag began. Measured from the start rather
  /// than accumulated, so a slow drag and a quick one over the same distance
  /// move the number by the same amount.
  double _from = 0;
  double _startX = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(_ChannelField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _text.text = widget.value.round().toString();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scheme Material is already using, which is the app's own palette --
    // see ThemeNotifier.colors, which is where MaterialApp's scheme comes
    // from. Read this way round, the picker works in any context with a
    // Theme above it, rather than only where the notifier has been provided.
    var theme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        // Over the middle of the box it names, rather than up against its
        // left edge: the numbers underneath are centred, and a caption
        // hanging off one corner of them read as a different row.
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            // A Listener rather than a drag gesture, so the number moves from
            // the first pixel: a drag is not recognised until the pointer has
            // travelled about eighteen pixels, and those eighteen are then
            // gone.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                _from = widget.value;
                _startX = event.position.dx;
                _dragging = true;
              },
              onPointerMove: (event) {
                if (!_dragging) return;
                // Two pixels to the step, so a channel's whole range is a
                // comfortable drag rather than a flick, and shift is finer.
                var step = HardwareKeyboard.instance.isShiftPressed ? 0.2 : 1.0;
                var travelled = event.position.dx - _startX;
                widget.onChanged((_from + travelled * step)
                    .clamp(0.0, 255.0)
                    .roundToDouble());
              },
              onPointerUp: (_) => _dragging = false,
              onPointerCancel: (_) => _dragging = false,
              child: SizedBox(
                width: _channelWidth,
                child: Text(
                  widget.label,
                  key: ValueKey("channel${widget.label}"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.onSurfaceVariant,
                    // Dotted, the way a draggable number is marked elsewhere.
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    decorationColor:
                        theme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: _channelWidth,
            height: 28,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _KeepWhatArrived(3),
              ],
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                border: OutlineInputBorder(),
              ),
              onChanged: (typed) {
                var value = int.tryParse(typed);
                if (value == null) return;
                widget.onChanged(value.clamp(0, 255).toDouble());
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// _Draggable reports where a pointer is inside its child, from the first
/// pixel of the press and for as long as it is held.
class _Draggable extends StatelessWidget {
  /// onAt is where the pointer is, and whether this is the press that started
  /// the drag -- which is when a thing with several handles decides which of
  /// them is being held. Decided on every move instead, a handle dragged past
  /// its neighbour would hand the drag over to it half way.
  final void Function(Offset local, Size size, bool first) onAt;
  final Widget child;

  const _Draggable({required this.onAt, required this.child});

  void _at(BuildContext context, Offset global, bool first) {
    var box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    onAt(box.globalToLocal(global), box.size, first);
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (inner) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _at(inner, e.position, true),
          onPointerMove: (e) => _at(inner, e.position, false),
          child: child,
        ),
      );
}

/// _wheelMargin is the ring of room outside the disc that the move-all
/// handle runs in.
const double _wheelMargin = 22;

/// wheelRadius is how big the disc is inside a box of [size]. Shared by the
/// painter and by the hit testing, which have to agree about where the rim
/// is or a handle cannot be grabbed where it is drawn.
double wheelRadius(Size size, {required bool ringed}) =>
    math.min(size.width, size.height) / 2 - (ringed ? _wheelMargin : 0);

/// _WheelPainter is hue round and saturation out from the middle, at one
/// brightness, with the handles drawn on it.
///
/// A sweep of hues with a white disc faded over it, rather than a pixel loop:
/// the two together *are* the wheel -- every hue at the rim, white in the
/// middle, the shade between -- and a shader is one draw call where a loop
/// over sixty thousand pixels is sixty thousand.
class _WheelPainter extends CustomPainter {
  /// at is the colour a turn of the wheel and a distance out from its middle
  /// stand for. The wheel is painted with the same function the picking uses,
  /// so what is picked is what was shown -- which is what lets one wheel be
  /// an HSV wheel, an HSL one, the a-b plane of LAB, a page of inks, or a
  /// greyscale, depending only on what is asked of it.
  final Color Function(double hue, double sat) at;

  /// marks are the handles: hue, saturation, the colour to fill them with,
  /// and whether each is the one being answered with.
  final List<(double, double, Color, bool)> marks;

  /// ring is where the handle that moves the whole set sits, as a turn of
  /// the wheel -- or null where there is no such handle. It rides in the
  /// margin outside the disc, so it is never in the way of the five and
  /// never mistaken for one of them.
  final double? ring;

  /// locked are the handles drawn as being kept: the ones a change of
  /// harmony or a turn of the ring leaves where they are.
  final Set<int> locked;

  const _WheelPainter({
    required this.at,
    required this.marks,
    this.ring,
    this.locked = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    var radius = wheelRadius(size, ringed: ring != null);
    var centre = Offset(size.width / 2, size.height / 2);

    // Drawn as a grid clipped to the disc rather than as a sweep with white
    // faded over it. A sweep is two draws and is only ever an HSV wheel; this
    // is a few thousand small rectangles and is whatever the notation says.
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: centre, radius: radius)));
    var across = 72;
    var step = radius * 2 / across;
    for (var x = 0; x < across; x++) {
      for (var y = 0; y < across; y++) {
        var away = Offset((x + 0.5) * step - radius, (y + 0.5) * step - radius);
        var out = away.distance / radius;
        if (out > 1.02) continue;
        var hue = (math.atan2(away.dy, away.dx) * 180 / math.pi + 360) % 360;
        canvas.drawRect(
            Rect.fromLTWH(centre.dx - radius + x * step,
                centre.dy - radius + y * step, step + 1, step + 1),
            Paint()..color = at(hue, out.clamp(0.0, 1.0)));
      }
    }
    canvas.restore();

    for (var (i, (hue, sat, color, chosen)) in marks.indexed) {
      var angle = hue * math.pi / 180;
      var spot =
          centre + Offset(math.cos(angle), math.sin(angle)) * (sat * radius);
      _handle(canvas, spot, color, chosen ? 10 : 8, chosen);
      if (locked.contains(i)) {
        // A dot in the middle of a handle that is being kept: the same mark
        // the swatch under it carries.
        canvas.drawCircle(spot, 2.5, Paint()..color = Colors.white);
        canvas.drawCircle(
            spot,
            2.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Colors.black87);
      }
    }

    if (ring != null) {
      // A track for it, so it reads as a thing that runs round the wheel
      // rather than a sixth colour that has got loose.
      var track = radius + _wheelMargin / 2;
      canvas.drawCircle(
          centre,
          track,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _wheelMargin - 4
            ..color = Colors.white.withValues(alpha: 0.12));
      var angle = ring! * math.pi / 180;
      var spot = centre + Offset(math.cos(angle), math.sin(angle)) * track;
      canvas.drawCircle(spot, 7, Paint()..color = Colors.white);
      canvas.drawCircle(
          spot,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black54);
      // Three dots on it: the mark for a thing that is dragged, and the only
      // way to tell this handle from the five at a glance.
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
            spot + Offset(0, i * 2.6), 0.8, Paint()..color = Colors.black54);
      }
    }
  }

  void _handle(
      Canvas canvas, Offset at, Color color, double radius, bool chosen) {
    if (color.a > 0) canvas.drawCircle(at, radius - 2, Paint()..color = color);
    // Two rings, light over dark, so a handle is visible on a pale part of the
    // wheel and on a dark one.
    canvas.drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = chosen ? 3 : 2
          ..color = Colors.white);
    canvas.drawCircle(
        at,
        radius + 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.ring != ring ||
      old.locked.length != locked.length ||
      old.marks.toString() != marks.toString() ||
      // Two samples of the wheel itself, which is how a change of notation or
      // of the axis it is drawn at reaches the picture.
      old.at(30, 0.8) != at(30, 0.8) ||
      old.at(210, 0.4) != at(210, 0.4);
}

/// _FieldPainter is a two-dimensional colour field: whatever colour the
/// function gives for a place in it, with a handle where the colour in hand
/// sits.
///
/// One painter for four fields. The shade square is a pair of gradients and
/// could be drawn with a shader; saturation against lightness, cyan against
/// magenta, and the a-b plane of LAB are not gradients of anything -- so they
/// are drawn as a grid fine enough that nobody can see the squares, which is
/// a few thousand rectangles and still one frame's work.
class _FieldPainter extends CustomPainter {
  /// at is the colour at a place in the field, both axes running nought to
  /// one, with nought at the top left.
  final Color Function(double x, double y) at;

  /// mark is where the colour in hand sits, in those same coordinates.
  final Offset mark;

  /// flat is whether the field has one axis rather than two -- a greyscale
  /// ramp, where up and down mean nothing.
  final bool flat;

  const _FieldPainter(
      {required this.at, required this.mark, this.flat = false});

  @override
  void paint(Canvas canvas, Size size) {
    var across = 72;
    var down = flat ? 1 : 44;
    var wide = size.width / across;
    var tall = size.height / down;
    for (var x = 0; x < across; x++) {
      for (var y = 0; y < down; y++) {
        canvas.drawRect(
            // A shade over, so the seams between the squares do not show as
            // a grid of hairlines.
            Rect.fromLTWH(x * wide, y * tall, wide + 1, tall + 1),
            Paint()..color = at((x + 0.5) / across, (y + 0.5) / down));
      }
    }

    var spot = Offset(
        mark.dx * size.width, flat ? size.height / 2 : mark.dy * size.height);
    // Two rings, dark inside light, so the handle is visible on a white
    // corner and on a black one.
    canvas.drawCircle(
        spot,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    canvas.drawCircle(
        spot,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.mark != mark ||
      old.flat != flat ||
      old.at(0.2, 0.2) != at(0.2, 0.2) ||
      old.at(0.8, 0.7) != at(0.8, 0.7);
}

/// _BarPainter is a slider: a gradient with a handle on it.
class _BarPainter extends CustomPainter {
  final List<Color> colors;
  final double at;
  final bool checker;
  final Color ring;

  const _BarPainter({
    required this.colors,
    required this.at,
    required this.checker,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var box = Offset.zero & size;
    var rounded = RRect.fromRectAndRadius(box, const Radius.circular(9));
    canvas.save();
    canvas.clipRRect(rounded);
    if (checker) paintCheckerboard(canvas, box);
    canvas.drawRect(box,
        Paint()..shader = LinearGradient(colors: colors).createShader(box));
    canvas.restore();
    canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ring);

    var x = (at.clamp(0.0, 1.0) * size.width)
        .clamp(size.height / 2, size.width - size.height / 2);
    var spot = Offset(x, size.height / 2);
    canvas.drawCircle(
        spot,
        size.height / 2 - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white);
    canvas.drawCircle(
        spot,
        size.height / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.at != at ||
      old.colors.first != colors.first ||
      old.colors.last != colors.last;
}

/// _SwatchPainter draws a saved colour over a checker, so a see-through one
/// reads as see-through.
class _SwatchPainter extends CustomPainter {
  final Color color;
  const _SwatchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var box = Offset.zero & size;
    paintCheckerboard(canvas, box);
    canvas.drawRect(box, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}

/// paintCheckerboard is the grey chequer behind anything see-through.
void paintCheckerboard(Canvas canvas, Rect box, {double square = 6}) {
  canvas.drawRect(box, Paint()..color = const Color(0xFFBDBDBD));
  var light = Paint()..color = const Color(0xFFE0E0E0);
  var rows = (box.height / square).ceil();
  var cols = (box.width / square).ceil();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if ((x + y).isEven) continue;
      canvas.drawRect(
          Rect.fromLTWH(
              box.left + x * square,
              box.top + y * square,
              math.min(square, box.right - (box.left + x * square)),
              math.min(square, box.bottom - (box.top + y * square))),
          light);
    }
  }
}

/// _GradientShapeButton is one of the two shapes a gradient can be.
class _GradientShapeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _GradientShapeButton({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: on ? theme.secondaryContainer : null,
          border: Border.all(
              color: on ? theme.secondaryContainer : theme.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 13,
              color: on ? theme.onSecondaryContainer : theme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: on
                      ? theme.onSecondaryContainer
                      : theme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// _GradientStopButton adds a colour to the fade or takes one away.
class _GradientStopButton extends StatelessWidget {
  final IconData icon;
  final String tip;
  final double width;
  final VoidCallback? onTap;

  const _GradientStopButton(
      {required this.icon,
      required this.tip,
      required this.width,
      this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: SizedBox(
        width: width,
        height: width,
        child: IconButton(
          icon: Icon(icon, size: 16),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: theme.onSurfaceVariant,
          onPressed: onTap,
        ),
      ),
    );
  }
}

/// _GradientPreview is the fade drawn the way it will actually be painted.
///
/// Through the same PaintSpec the renderers use, rather than a Flutter
/// LinearGradient built to look similar: a preview with its own idea of what
/// a gradient is is a preview that can be wrong about the angle, the falloff
/// or where the third colour lands, and being wrong is the only thing a
/// preview must not be.
class _GradientPreview extends StatelessWidget {
  final PaintSpec paint;
  final double width;
  final double height;
  final Color outline;

  const _GradientPreview({
    required this.paint,
    required this.width,
    required this.height,
    required this.outline,
    super.key,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _GradientPreviewPainter(paint, outline),
      );
}

class _GradientPreviewPainter extends CustomPainter {
  final PaintSpec spec;
  final Color outline;

  const _GradientPreviewPainter(this.spec, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    var area = Offset.zero & size;
    var round = RRect.fromRectAndRadius(area, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(round);
    _checker(canvas, area);
    var shader = spec.shaderFor(area);
    canvas.drawRect(
        area,
        shader == null
            ? (Paint()..color = spec.color)
            : (Paint()..shader = shader));
    canvas.restore();
    canvas.drawRRect(
        round,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_GradientPreviewPainter old) =>
      old.spec != spec || old.outline != outline;
}

/// _checker is the grey squares that make a see-through colour visibly
/// see-through rather than black.
void _checker(Canvas canvas, Rect area) {
  const square = 6.0;
  var light = Paint()..color = const Color(0xFF9A9A9A);
  var dark = Paint()..color = const Color(0xFF6E6E6E);
  for (var y = area.top; y < area.bottom; y += square) {
    for (var x = area.left; x < area.right; x += square) {
      canvas.drawRect(Rect.fromLTWH(x, y, square, square),
          ((x ~/ square) + (y ~/ square)).isEven ? light : dark);
    }
  }
}

/// _GradientBar is where each colour in the fade is reached, with a handle
/// apiece.
///
/// Dragging them together makes the change abrupt and dragging them apart
/// leaves more of each colour flat. Always drawn left to right whatever
/// direction the gradient runs in: this bar is the order of the colours, and
/// the preview above it is the direction.
/// _GradientBar is the gradient itself, with a handle at each end.
///
/// The handles are where the two colours stop being themselves, so dragging
/// them together makes the change abrupt and dragging them apart leaves more
/// of each colour flat. Shown on the gradient rather than as two numbers,
/// because "how far along does the fade start" is a question about a picture.
class _GradientBar extends StatefulWidget {
  final Color from;

  /// spec is null when the colour is flat: the bar then has one point on it,
  /// and the add button beside it is what turns it into a fade.
  final GradientSpec? spec;

  /// editing is which colour is selected: -1 for the first, 0 for the second,
  /// and so on.
  final int editing;
  final ValueChanged<int> onPick;
  final void Function(int stop, double at) onMove;

  /// onBias moves one of the thin handles either side of the selected point:
  /// where the change into the colour at [stop] is half done.
  final void Function(int stop, double bias) onBias;
  final double width;

  const _GradientBar({
    required this.from,
    required this.spec,
    required this.editing,
    required this.onPick,
    required this.onMove,
    required this.onBias,
    required this.width,
    super.key,
  });

  @override
  State<_GradientBar> createState() => _GradientBarState();
}

/// _Held is what a drag on the bar has hold of.
enum _Held { stop, bias }

class _GradientBarState extends State<_GradientBar> {
  /// _dragging is which handle is under the finger and what kind it is, so a
  /// drag running past another one does not hand itself over to it.
  int? _dragging;
  _Held _kind = _Held.stop;

  static const double _bar = 34;
  static const double _grip = 18;

  /// _inset is the room the handles need at each end: half a handle, so one
  /// pushed all the way to 0 or 1 is still fully drawn.
  static const double _inset = _grip / 2;

  double _at(double x) {
    var span = widget.width - _grip;
    if (span <= 0) return 0;
    return ((x - _inset) / span).clamp(0.0, 1.0);
  }

  double _xOf(double at) => _inset + (widget.width - _grip) * at;

  /// _places is every point's position, the first colour's included.
  List<double> get _places => widget.spec?.positions ?? const [0.0];

  /// _biasHandles are the thin handles either side of the selected point:
  /// which span each one shapes, and where it currently sits.
  ///
  /// A span belongs to the colour it runs *into*, so the handle to the left
  /// of a point shapes that point's own span and the one to its right shapes
  /// the next point's. The first colour has nothing to its left.
  List<(int, double)> get _biasHandles {
    var spec = widget.spec;
    if (spec == null) return const [];
    var places = spec.positions;
    var ramp = spec.ramp;
    var out = <(int, double)>[];
    void add(int stop) {
      if (stop < 0 || stop >= ramp.length) return;
      var from = places[stop];
      var to = places[stop + 1];
      out.add((stop, from + (to - from) * ramp[stop].bias));
    }

    // The span into this point, and the one out of it.
    add(widget.editing);
    add(widget.editing + 1);
    return out;
  }

  /// _grab picks whatever is nearest the touch. The thin handles win a tie:
  /// they are small, they are only there while their point is selected, and
  /// the point itself is a much bigger thing to hit.
  void _grab(double x) {
    for (var (stop, at) in _biasHandles) {
      if ((_xOf(at) - x).abs() <= 7) {
        setState(() {
          _dragging = stop;
          _kind = _Held.bias;
        });
        return;
      }
    }
    var at = _at(x);
    var places = _places;
    var nearest = 0;
    for (var i = 1; i < places.length; i++) {
      if ((at - places[i]).abs() < (at - places[nearest]).abs()) nearest = i;
    }
    setState(() {
      _dragging = nearest;
      _kind = _Held.stop;
    });
    widget.onPick(nearest - 1);
  }

  void _move(double x) {
    var index = _dragging;
    if (index == null) return;
    if (_kind == _Held.bias) {
      var places = _places;
      var from = places[index];
      var to = places[index + 1];
      var span = to - from;
      if (span <= 0) return;
      widget.onBias(index, ((_at(x) - from) / span).clamp(0.05, 0.95));
      return;
    }
    widget.onMove(index - 1, _at(x));
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      // From where the finger went down, not from where the drag was
      // recognised. A drag is not recognised until the pointer has travelled
      // about eighteen pixels, and eighteen pixels is far enough past a thin
      // handle to miss it and take the point behind it instead -- which is
      // why dragStartBehavior is down.
      onHorizontalDragStart: (d) => _grab(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _move(d.localPosition.dx),
      onHorizontalDragEnd: (_) => setState(() => _dragging = null),
      onTapDown: (d) => _grab(d.localPosition.dx),
      child: CustomPaint(
        size: Size(widget.width, _bar),
        painter: _GradientBarPainter(
          from: widget.from,
          spec: widget.spec,
          editing: widget.editing,
          biases: _biasHandles,
          outline: theme.outlineVariant,
          ring: theme.primary,
          inset: _inset,
          grip: _grip,
        ),
      ),
    );
  }
}

class _GradientBarPainter extends CustomPainter {
  final Color from;
  final GradientSpec? spec;
  final int editing;
  final List<(int, double)> biases;
  final Color outline;
  final Color ring;
  final double inset;
  final double grip;

  const _GradientBarPainter({
    required this.from,
    required this.spec,
    required this.editing,
    required this.biases,
    required this.outline,
    required this.ring,
    required this.inset,
    required this.grip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var track =
        Rect.fromLTWH(inset, 6, size.width - inset * 2, size.height - 18);
    var round = RRect.fromRectAndRadius(track, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(round);
    _checker(canvas, track);
    var paint = PaintSpec(from, gradient: spec);
    if (spec == null) {
      canvas.drawRect(track, Paint()..color = from);
    } else {
      // Left to right whatever direction the gradient runs in, and with each
      // span's bias already in it -- this is the order of the colours and how
      // sharply each gives way to the next.
      var (colours, places) = paint.rampFor();
      canvas.drawRect(
        track,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(track.left, track.center.dy),
            Offset(track.right, track.center.dy),
            colours,
            places,
          ),
      );
    }
    canvas.restore();
    canvas.drawRRect(
        round,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke);

    // The thin handles first, so a point drawn over one still reads as the
    // thing on top.
    for (var (_, at) in biases) {
      var x = inset + (size.width - grip) * at;
      canvas.drawLine(
        Offset(x, track.top + 2),
        Offset(x, track.bottom - 2),
        Paint()
          ..color = ring
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(x, track.top + 2),
        Offset(x, track.bottom - 2),
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..strokeWidth = 0.8,
      );
    }

    var handles = spec?.positions ?? const [0.0];
    var inks = [from, for (var stop in spec?.ramp ?? const []) stop.color];
    for (var i = 0; i < handles.length; i++) {
      var x = inset + (size.width - grip) * handles[i];
      var selected = editing == i - 1;
      var centre = Offset(x, size.height - grip / 2);
      // On the checker, so a see-through point looks see-through: a gradient
      // running to nothing is most of what these are for.
      canvas.save();
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: centre, radius: grip / 2)));
      _checker(canvas, Rect.fromCircle(center: centre, radius: grip / 2));
      canvas.restore();
      canvas.drawCircle(centre, grip / 2, Paint()..color = inks[i]);
      canvas.drawCircle(
        centre,
        grip / 2,
        Paint()
          ..color = selected ? ring : outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(_GradientBarPainter old) =>
      old.from != from ||
      old.spec != spec ||
      old.editing != editing ||
      old.biases.length != biases.length ||
      old.ring != ring;
}
