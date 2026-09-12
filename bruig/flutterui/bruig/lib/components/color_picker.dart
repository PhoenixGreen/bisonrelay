import 'dart:math' as math;

import 'package:bruig/components/saved_colors.dart';
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
  palette("Palette", Icons.auto_awesome);

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
  String title = "Colour",
}) {
  // As wide as the screen sensibly allows, which is what puts the numbers and
  // the saved colours beside the picker rather than under it. Measured here
  // rather than by the picker: a dialog asks what it holds how big it wants
  // to be, and a widget that measures the room it has been given cannot
  // answer that question.
  var room = MediaQuery.of(context).size.width - 120;
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorDialog(
      initial: initial,
      allowAlpha: allowAlpha,
      title: title,
      width: room.clamp(300.0, 640.0),
    ),
  );
}

class _ColorDialog extends StatefulWidget {
  final Color initial;
  final bool allowAlpha;
  final String title;
  final double width;
  const _ColorDialog({
    required this.initial,
    required this.allowAlpha,
    required this.title,
    required this.width,
  });

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: AppColorPicker(
            color: _color,
            allowAlpha: widget.allowAlpha,
            width: widget.width,
            onChanged: (c) => setState(() => _color = c),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            key: const ValueKey("colorPickerSelect"),
            onPressed: () => Navigator.of(context).pop(_color),
            child: const Text("Select"),
          ),
        ],
      );
}

/// AppColorPicker is the picker itself, for the places that show it in a
/// panel rather than in a dialog.
class AppColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

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
    this.allowAlpha = true,
    this.width = 320,
    super.key,
  });

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

/// _wideAt is the width at which the picker lays itself out in two columns.
const double _wideAt = 560;

/// _pickerColumn is how much of a wide picker the colour itself takes.
const double _pickerColumn = 300;

/// _Spot is one of the five colours in the palette mode.
class _Spot {
  final double hue;
  final double sat;
  final double val;
  const _Spot({required this.hue, required this.sat, required this.val});

  Color get color => HSVColor.fromAHSV(1, hue, sat, val).toColor();
}

class _AppColorPickerState extends State<AppColorPicker> {
  // Hue, saturation, value and alpha rather than a Color.
  //
  // The colour is what comes *out* of these. Held the other way round -- the
  // colour kept and the three numbers worked out from it on every build --
  // black has no hue and no saturation to work out, so dragging the hue
  // slider on a black gave black back, the slider snapped home, and the
  // picker looked broken until something colourful was chosen by hand.
  double _hue = 0;
  double _sat = 0;
  double _val = 0;
  double _alpha = 1;

  ColorPickerMode _mode = ColorPickerMode.sliders;
  ColorFormat _format = ColorFormat.hex;

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

  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _take(widget.color);
    _readField();
    _leadFromCurrent();
    _textFocus.addListener(() {
      // Whatever is half-typed goes back to the real colour when the field is
      // left, so a field holding "#ff" does not sit there looking like a
      // colour the picker is showing.
      if (!_textFocus.hasFocus) setState(_write);
    });
    SavedColors.instance.load();
  }

  @override
  void didUpdateWidget(AppColorPicker old) {
    super.didUpdateWidget(old);
    // Only when somebody else has changed it. Taking it every time would undo
    // the slider positions this picker is holding on to.
    if (widget.color.toARGB32() != _current.toARGB32()) {
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
    var hsv = HSVColor.fromColor(Color(color.toARGB32()).withAlpha(255));
    // A colour with no saturation or no brightness cannot say what hue it is,
    // and a black cannot say how saturated it is: those come back as nought
    // from the conversion whatever the slider was pointing at. Keeping the
    // ones already held is the whole fix for a hue slider that did nothing
    // until a colour had been picked out of the square.
    if (hsv.saturation > 0 && hsv.value > 0) _hue = hsv.hue;
    if (hsv.value > 0) _sat = hsv.saturation;
    _val = hsv.value;
    _alpha = color.a;
    _write();
  }

  /// _tookFromOutside is _take followed by re-reading where that colour sits
  /// in the field, for every way a colour can arrive that is not a drag on
  /// the field itself.
  void _tookFromOutside(Color color) {
    _take(color);
    _readField();
  }

  Color get _current =>
      HSVColor.fromAHSV(_alpha.clamp(0, 1), _hue, _sat, _val).toColor();

  /// _shown is a colour as this picker draws it: itself, or its brightness
  /// alone where the notation in hand is a greyscale.
  Color _shown(Color color) {
    if (_format != ColorFormat.grey) return color;
    var level = greyOf(color).round().clamp(0, 255);
    return Color.fromARGB(255, level, level, level);
  }

  /// _pure is the colour at this hue, at full saturation and brightness: what
  /// the shade square is painted with and what the sliders point at.
  Color get _pure => HSVColor.fromAHSV(1, _hue, 1, 1).toColor();

  void _say() {
    _write();
    widget.onChanged(_current);
  }

  /// _leadFromCurrent points the palette at the colour in hand and lays the
  /// five out around it. What happens when the palette is opened, when reset
  /// is pressed, and when a colour arrives from somewhere else.
  void _leadFromCurrent() {
    _leadHue = _hue;
    _leadSat = _sat <= 0 ? 0.8 : _sat;
    _leadVal = _val <= 0 ? 0.9 : _val;
    _spread();
    _picked = 0;
  }

  /// _spread lays the five out from the colour they are led by.
  void _spread() {
    _spots = [
      for (var (turn, sat, val) in _harmony.places)
        _Spot(
          hue: (_leadHue + turn) % 360,
          sat: (_leadSat * sat).clamp(0.0, 1.0),
          val: (_leadVal * val).clamp(0.0, 1.0),
        ),
    ];
  }

  /// _lead re-lays the set from one of its handles: a harmony is a shape, and
  /// moving one corner of it moves the shape.
  void _lead(int index, double hue, double sat) {
    if (_harmony == ColorHarmony.custom) {
      var next = [..._spots];
      next[index] = _Spot(hue: hue, sat: sat, val: _spots[index].val);
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

  /// _pick answers with one of the five.
  void _pick(int index) {
    _picked = index.clamp(0, _spots.length - 1);
    var spot = _spots[_picked];
    if (_format == ColorFormat.grey) {
      // Working in greys, a palette is five brightnesses: the arrangement
      // still decides them, and what comes out is how bright each one is.
      _hue = spot.hue;
      _sat = 0;
      _val = (greyOf(spot.color) / 255).clamp(0.0, 1.0);
    } else {
      _hue = spot.hue;
      _sat = spot.sat;
      _val = spot.val;
    }
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
      widget.onChanged(_current);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context).colorScheme;
    var wide = widget.width >= _wideAt;
    var pickerWidth = wide ? _pickerColumn : widget.width;
    var settingsWidth = wide ? widget.width - _pickerColumn - 20 : widget.width;

    var picking = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _modes(theme, pickerWidth),
        const SizedBox(height: 10),
        switch (_mode) {
          ColorPickerMode.sliders => _slidersMode(theme, pickerWidth),
          ColorPickerMode.wheel => _wheelMode(theme, pickerWidth),
          ColorPickerMode.palette => _paletteMode(theme, pickerWidth),
        },
      ],
    );

    var settings = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _channels(theme, settingsWidth),
        const SizedBox(height: 14),
        _SavedRow(
          current: _current,
          width: settingsWidth,
          onPick: (c) => setState(() {
            _tookFromOutside(c);
            widget.onChanged(_current);
          }),
        ),
      ],
    );

    if (!wide) {
      return SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [picking, const SizedBox(height: 14), settings],
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: pickerWidth, child: picking),
          const SizedBox(width: 20),
          Expanded(child: settings),
        ],
      ),
    );
  }

  /// _modes is the three ways of choosing, across the top.
  Widget _modes(ColorScheme theme, double width) => SizedBox(
        width: width,
        child: Wrap(
          spacing: 0,
          runSpacing: 6,
          children: [
            for (var mode in ColorPickerMode.values)
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
          ],
        ),
      );

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
              var hsv = HSVColor.fromColor(_fieldColor(_fx, _fy));
              if (hsv.value > 0) _sat = hsv.saturation;
              _val = hsv.value;
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
            onAt: (local, box, _) => setState(() {
              var (hue, sat) = _wheelAt(local, box);
              if (_format == ColorFormat.grey) {
                // The wheel is drawn in greys, so what is picked off it is
                // the grey that was under the pointer -- not the colour the
                // wheel would have shown in another notation.
                var under = HSVColor.fromAHSV(1, hue, sat, _val).toColor();
                _sat = 0;
                _val = (greyOf(under) / 255).clamp(0.0, 1.0);
              } else {
                _hue = hue;
                _sat = sat;
              }
              _readField();
              _say();
            }),
            child: CustomPaint(
              key: const ValueKey("colorWheel"),
              size: Size(size, size),
              painter: _WheelPainter(
                value: _val,
                grey: _format == ColorFormat.grey,
                marks: [(_hue, _sat, _current, true)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _labelledBar(
          theme: theme,
          label: "Brightness",
          key: "colorValue",
          width: width,
          colors: [Colors.black, HSVColor.fromAHSV(1, _hue, _sat, 1).toColor()],
          at: _val,
          onAt: (f) => setState(() {
            _val = f;
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
  Widget _paletteMode(ColorScheme theme, double width) {
    var size = math.min(width, 260.0);
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
                  _leadHue = hue;
                  _spread();
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
                value: _leadVal,
                grey: _format == ColorFormat.grey,
                ring: _leadHue,
                marks: [
                  for (var i = 0; i < _spots.length; i++)
                    (
                      _spots[i].hue,
                      _spots[i].sat,
                      _spots[i].color,
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
          IconButton(
            key: const ValueKey("colorHarmonyReset"),
            icon: const Icon(Icons.restart_alt, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: "Lay the five out again around the colour in hand",
            onPressed: () => setState(_leadFromCurrent),
          ),
        ]),
        const SizedBox(height: 6),
        // The five, with the one being answered with ringed. Pressing one is
        // how the picker is pointed at it.
        Row(
          children: [
            for (var i = 0; i < _spots.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    key: ValueKey("paletteSpot$i"),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(() => _pick(i)),
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color:
                            _shown(_spots[i].color).withValues(alpha: _alpha),
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
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _labelledBar(
          theme: theme,
          label: "Brightness",
          key: "paletteValue",
          width: width,
          colors: [
            Colors.black,
            HSVColor.fromAHSV(1, _leadHue, _leadSat, 1).toColor()
          ],
          at: _leadVal,
          onAt: (f) => setState(() {
            _leadVal = f.clamp(0.02, 1.0);
            _spread();
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
  Widget _channels(ColorScheme theme, double width) {
    var c = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
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
                  _val = (greyOf(_current) / 255).clamp(0.0, 1.0);
                  _sat = 0;
                }
                _readField();
                _write();
                widget.onChanged(_current);
              }),
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 30,
          width: width,
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
              LengthLimitingTextInputFormatter(24),
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
      var colour = _fieldColor(_fx, _fy);
      var hsv = HSVColor.fromColor(colour);
      if (hsv.saturation > 0 && hsv.value > 0) _hue = hsv.hue;
      if (hsv.value > 0) _sat = hsv.saturation;
      _val = hsv.value;
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
      widget.onChanged(_current);
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
  final double width;

  const _SavedRow(
      {required this.current, required this.onPick, required this.width});

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
              Text(
                "SAVED COLOURS",
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                  color: theme.onSurfaceVariant.withValues(alpha: 0.7),
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
                width: width,
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
                LengthLimitingTextInputFormatter(3),
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

/// greyFilter turns whatever is drawn through it into greys, weighted the
/// way an eye sees brightness rather than as a flat average of the three
/// channels -- the same weighting greyOf uses, so a colour and its swatch
/// agree about how bright it is.
const ColorFilter greyFilter = ColorFilter.matrix(<double>[
  0.299, 0.587, 0.114, 0, 0, //
  0.299, 0.587, 0.114, 0, 0, //
  0.299, 0.587, 0.114, 0, 0, //
  0, 0, 0, 1, 0, //
]);

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
  /// value is how bright the wheel is drawn, so a dark colour is picked out
  /// of a dark wheel rather than a bright one that lies about it.
  final double value;

  /// marks are the handles: hue, saturation, what to fill them with, and
  /// whether each is the one being answered with.
  final List<(double, double, Color, bool)> marks;

  /// grey is whether the wheel is drawn without its colour, for a picker
  /// working in greyscale: the same wheel, every colour on it flattened to
  /// how bright it is. A wheel that went on showing colours while the picker
  /// could only answer in greys would be an invitation to pick something it
  /// could not give.
  final bool grey;

  /// ring is where the handle that moves the whole set sits, as a turn of
  /// the wheel -- or null where there is no such handle. It rides in the
  /// margin outside the disc, so it is never in the way of the five and
  /// never mistaken for one of them.
  final double? ring;

  const _WheelPainter({
    required this.value,
    required this.marks,
    this.ring,
    this.grey = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var radius = wheelRadius(size, ringed: ring != null);
    // Everything the disc is made of goes through one layer, so that
    // flattening it to greys is a filter over that layer rather than a
    // second set of colours to keep in step with the first.
    if (grey) {
      canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = greyFilter);
    }
    var centre = Offset(size.width / 2, size.height / 2);
    var box = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = const SweepGradient(colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ]).createShader(box));
    // White out of the middle: saturation is how far from the centre a colour
    // sits.
    canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white, Colors.white.withValues(alpha: 0)],
          ).createShader(box));
    // And the whole thing dimmed to the brightness being worked at.
    if (value < 1) {
      canvas.drawCircle(centre, radius,
          Paint()..color = Colors.black.withValues(alpha: 1 - value));
    }
    if (grey) canvas.restore();

    for (var (hue, sat, color, chosen) in marks) {
      var angle = hue * math.pi / 180;
      var at =
          centre + Offset(math.cos(angle), math.sin(angle)) * (sat * radius);
      _handle(canvas, at, color, chosen ? 10 : 8, chosen);
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
      var at = centre + Offset(math.cos(angle), math.sin(angle)) * track;
      canvas.drawCircle(at, 7, Paint()..color = Colors.white);
      canvas.drawCircle(
          at,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black54);
      // Three dots on it: the mark for a thing that is dragged, and the only
      // way to tell this handle from the five at a glance.
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
            at + Offset(0, i * 2.6), 0.8, Paint()..color = Colors.black54);
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
      old.value != value ||
      old.grey != grey ||
      old.ring != ring ||
      old.marks.toString() != marks.toString();
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
