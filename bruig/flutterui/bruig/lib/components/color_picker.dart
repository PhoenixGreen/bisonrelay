import 'dart:math' as math;

import 'package:bruig/components/saved_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// color_picker.dart is the app's colour picker: the one dialog behind every
// swatch, in the canvas, in the palette editor and in the composer's
// formatting panel.
//
// Written here rather than taken from a package, for three reasons that the
// package could not be made to answer:
//
// - The hue slider did nothing on a black, a white or a grey. A colour has
//   no hue once its saturation or its value is nought, so a picker that
//   keeps only the colour cannot remember which way the hue slider was
//   pointing -- and dragging it changed nothing until a colour was picked
//   out of the square first. This one keeps hue, saturation and value as
//   three numbers of its own and builds the colour from them, so every
//   slider always moves something.
//
// - The channels are draggable. R, G, B and A are captions you can grab and
//   pull sideways, which is how every other number in the canvas is set.
//
// - Saved colours. See SavedColors: two rows of swatches under the picker,
//   shared by every picker in the app and kept across restarts.

/// pickColor opens the picker as a dialog and answers with the colour
/// chosen, or null if it was dismissed.
Future<Color?> pickColor(
  BuildContext context, {
  required Color initial,
  bool allowAlpha = true,
  String title = "Colour",
}) =>
    showDialog<Color>(
      context: context,
      builder: (context) =>
          _ColorDialog(initial: initial, allowAlpha: allowAlpha, title: title),
    );

class _ColorDialog extends StatefulWidget {
  final Color initial;
  final bool allowAlpha;
  final String title;
  const _ColorDialog(
      {required this.initial, required this.allowAlpha, required this.title});

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

  /// width is how wide the picker draws. The default fits ten saved swatches
  /// to a row with room either side.
  final double width;

  const AppColorPicker({
    required this.color,
    required this.onChanged,
    this.allowAlpha = true,
    this.width = 300,
    super.key,
  });

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
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

  final TextEditingController _hex = TextEditingController();
  final FocusNode _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _take(widget.color);
    _hexFocus.addListener(() {
      // Whatever is half-typed goes back to the real colour when the field
      // is left, so a field holding "#ff" does not sit there looking like a
      // colour the picker is showing.
      if (!_hexFocus.hasFocus) setState(_writeHex);
    });
    SavedColors.instance.load();
  }

  @override
  void didUpdateWidget(AppColorPicker old) {
    super.didUpdateWidget(old);
    // Only when somebody else has changed it. Taking it every time would
    // undo the slider positions this picker is holding on to.
    if (widget.color.toARGB32() != _current.toARGB32()) _take(widget.color);
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// _take reads a colour in from outside, keeping what it cannot say.
  ///
  /// A grey carries no hue and a black carries neither hue nor saturation.
  /// Rather than reset those to nought -- which is what makes a hue slider
  /// look stuck -- the picker keeps the ones it already had.
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
    _writeHex();
  }

  Color get _current =>
      HSVColor.fromAHSV(_alpha.clamp(0, 1), _hue, _sat, _val).toColor();

  /// _pure is the colour at this hue, at full saturation and brightness:
  /// what the shade square is painted with and what the hue slider points at.
  Color get _pure => HSVColor.fromAHSV(1, _hue, 1, 1).toColor();

  void _say() {
    _writeHex();
    widget.onChanged(_current);
  }

  void _writeHex() {
    var value = _current.toARGB32();
    var text = widget.allowAlpha
        ? value.toRadixString(16).padLeft(8, "0")
        : (value & 0xFFFFFF).toRadixString(16).padLeft(6, "0");
    if (_hex.text.toLowerCase() != text) _hex.text = text;
  }

  void _readHex(String typed) {
    var clean = typed.replaceAll("#", "").trim();
    if (clean.length != 6 && clean.length != 8) return;
    var value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    setState(() {
      _take(Color(clean.length == 6 ? 0xFF000000 | value : value));
      widget.onChanged(_current);
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
      _take(next);
      widget.onChanged(_current);
    });
  }

  @override
  Widget build(BuildContext context) => _body(context, widget.width);

  /// _body is the picker at a width it has been told, rather than one it has
  /// measured. A LayoutBuilder here reads well and breaks the moment the
  /// picker is put in a dialog: an AlertDialog measures what it holds, and a
  /// LayoutBuilder cannot answer that question. Callers with less room say so
  /// -- see AppColorPicker.width.
  Widget _body(BuildContext context, double width) {
    // The scheme Material is already using, which is the app's own palette --
    // see ThemeNotifier.colors, which is where MaterialApp's scheme comes
    // from. Read this way round, the picker works in any context with a
    // Theme above it, rather than only where the notifier has been provided.
    var theme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _shadeSquare(theme, width),
          const SizedBox(height: 12),
          _hueSlider(theme, width),
          if (widget.allowAlpha) ...[
            const SizedBox(height: 10),
            _alphaSlider(theme, width),
          ],
          const SizedBox(height: 12),
          _channels(theme, width),
          const SizedBox(height: 12),
          _SavedRow(
            current: _current,
            onPick: (c) => setState(() {
              _take(c);
              widget.onChanged(_current);
            }),
          ),
        ],
      ),
    );
  }

  /// _shadeSquare is saturation across and brightness down, in the hue the
  /// slider under it is pointing at.
  Widget _shadeSquare(ColorScheme theme, double width) {
    var height = width * 0.52;
    return _Draggable(
      onAt: (local, size) => setState(() {
        _sat = (local.dx / size.width).clamp(0.0, 1.0);
        _val = 1 - (local.dy / size.height).clamp(0.0, 1.0);
        _say();
      }),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          key: const ValueKey("colorShade"),
          size: Size(width, height),
          painter: _ShadePainter(
              pure: _pure,
              at: Offset(_sat, 1 - _val),
              ring: theme.outlineVariant),
        ),
      ),
    );
  }

  Widget _hueSlider(ColorScheme theme, double width) => _Draggable(
        onAt: (local, size) => setState(() {
          _hue = (local.dx / size.width).clamp(0.0, 1.0) * 360;
          _say();
        }),
        child: CustomPaint(
          key: const ValueKey("colorHue"),
          size: Size(width, 18),
          painter: _BarPainter(
            colors: const [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
            at: _hue / 360,
            checker: false,
            ring: theme.outlineVariant,
          ),
        ),
      );

  Widget _alphaSlider(ColorScheme theme, double width) => _Draggable(
        onAt: (local, size) => setState(() {
          _alpha = (local.dx / size.width).clamp(0.0, 1.0);
          _say();
        }),
        child: CustomPaint(
          key: const ValueKey("colorAlpha"),
          size: Size(width, 18),
          painter: _BarPainter(
            colors: [_pure.withValues(alpha: 0), _pure],
            at: _alpha,
            // The checker is what makes see-through read as see-through
            // rather than as a colour that happens to be pale.
            checker: true,
            ring: theme.outlineVariant,
          ),
        ),
      );

  /// _channels is the four numbers, each with a caption that can be dragged.
  Widget _channels(ColorScheme theme, double width) {
    var c = _current;
    // The hex goes on a line of its own where four channels and a field will
    // not fit across: a settings column narrower than the picker asked for is
    // the normal case in a sidebar, and a row that overflows is a stripe of
    // yellow and black over the colour being chosen.
    var roomy = width >= 290;
    var fields = [
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
    ];
    // The hex, for the colour somebody has been given rather than the one
    // they are looking for.
    var hex = TextField(
      key: const ValueKey("colorPickerHex"),
      controller: _hex,
      focusNode: _hexFocus,
      style: const TextStyle(fontSize: 12, fontFamily: "monospace"),
      decoration: InputDecoration(
        isDense: true,
        prefixText: "#",
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: const OutlineInputBorder(),
        hintText: widget.allowAlpha ? "aarrggbb" : "rrggbb",
        hintStyle: TextStyle(
            fontSize: 11, color: theme.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r"[0-9a-fA-F#]")),
        LengthLimitingTextInputFormatter(9),
      ],
      onChanged: _readHex,
      onSubmitted: _readHex,
    );

    if (roomy) {
      return Row(children: [
        ...fields,
        const SizedBox(width: 8),
        Expanded(child: hex),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: fields),
        const SizedBox(height: 8),
        SizedBox(width: width, child: hex),
      ],
    );
  }
}

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
              Wrap(
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
              child: Text(
                widget.label,
                key: ValueKey("channel${widget.label}"),
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
          const SizedBox(height: 2),
          SizedBox(
            width: 42,
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
  final void Function(Offset local, Size size) onAt;
  final Widget child;

  const _Draggable({required this.onAt, required this.child});

  void _at(BuildContext context, Offset global) {
    var box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    onAt(box.globalToLocal(global), box.size);
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (inner) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _at(inner, e.position),
          onPointerMove: (e) => _at(inner, e.position),
          child: child,
        ),
      );
}

/// _ShadePainter is the saturation-and-brightness square.
class _ShadePainter extends CustomPainter {
  final Color pure;
  final Offset at;
  final Color ring;

  const _ShadePainter(
      {required this.pure, required this.at, required this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    var box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = pure);
    // White across and black down, which is what turns one hue into every
    // shade of itself.
    canvas.drawRect(
        box,
        Paint()
          ..shader = const LinearGradient(
            colors: [Colors.white, Colors.transparent],
          ).createShader(box));
    canvas.drawRect(
        box,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(box));

    var spot = Offset(at.dx * size.width, at.dy * size.height);
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
  bool shouldRepaint(_ShadePainter old) => old.pure != pure || old.at != at;
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
