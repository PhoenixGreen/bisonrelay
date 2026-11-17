part of 'mixer_plugins.dart';

// mixer_sound_devices.dart is what the sound chain's own devices share: the
// inks they read in, cached painted labels, the knob and the one-of-a-few
// choice buttons, and the gain-reduction bar. The devices themselves are in
// mixer_devices_*.dart. A part of mixer_plugins.dart; its imports are the
// library's.

const _eqBack = Color(0xFF0D1826);
const _eqInk = Color(0xFFC9D6E6);

/// _headerInkLight is ink that reads on a device's dark header bar.
const _headerInkLight = Color(0xFFE8EAEE);
const _eqDim = Color(0xFF6E8199);

/// paintedLabel is [text] in [style], laid out and cached: meters and
/// graphs paint the same few labels every frame, and layout was much of
/// their cost. With [maxWidth] it is one line no wider, ending in an
/// ellipsis where it runs over.
TextPainter paintedLabel(String text, TextStyle style, {double? maxWidth}) {
  var width = maxWidth == null ? null : math.max(0.0, maxWidth);
  var key = (text, style, width);
  var kept = _labels[key];
  if (kept != null) return kept;
  if (_labels.length > 400) _labels.clear();
  return _labels[key] = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: width == null ? null : 1,
      ellipsis: width == null ? null : "…",
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: width ?? double.infinity);
}

final _labels = <(String, TextStyle, double?), TextPainter>{};

/// _silverInk and _silverDim are ink that reads on a device's dark card.
const _silverInk = Color(0xFFE8E4EE);
const _silverDim = Color(0xFF8E8A9C);

/// _faceInk and _faceDim read on a cream face (the VU, the ducking curve).
const _faceInk = Color(0xFF2B2F36);
const _faceDim = Color(0xFF6A707A);
const _cream = Color(0xFFF1E7C9);

/// DeviceChoices is a one-of-a-few setting as joined buttons, one filled.
class DeviceChoices extends StatelessWidget {
  /// options are each one's key, name, whether it is chosen, and its press.
  final List<(Key, String, bool, VoidCallback)> options;
  const DeviceChoices({required this.options, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: look.studio.edge),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        for (var (i, (key, label, on, tap)) in options.indexed) ...[
          if (i > 0) Container(width: 1, color: look.studio.edge),
          Expanded(
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              child: Container(
                color: on ? look.colors.primary : null,
                alignment: Alignment.center,
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: on ? look.colors.onPrimary : look.studio.muted)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// _Knob is a rotary control: drag up to turn right, double-click to reset.
class _Knob extends StatefulWidget {
  final String label;
  final String text;
  final double value;
  final double initial;
  final _Range range;
  final double size;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;

  /// automated is whether a lane moves it -- a red dot by its name -- and
  /// held whether a hand is holding it instead: the dot grey.
  final bool automated;
  final bool held;

  /// modulated is whether an LFO moves it: a pink ring round it.
  final bool modulated;

  /// own is whether the copies being edited have a value of their own here
  /// (see instances.dart): its arc amber, with a dot by it.
  final bool own;

  /// menu is its right-click's modulators to move it with; empty for none.
  final List<(String, VoidCallback)> menu;

  /// reading is whether its value is written under it (not on a short card).
  final bool reading;

  /// accent, given, draws the Chain's dark knob with its arc in [accent],
  /// filled from the middle where [bipolar]; [ink] colours label and reading.
  final Color? accent;
  final Color ink;
  final bool bipolar;

  /// step is its arrows' step in ChainPanelStyle; null for 1/50 of travel.
  final double? step;

  const _Knob({
    this.step,
    this.automated = false,
    this.held = false,
    this.modulated = false,
    this.own = false,
    this.menu = const [],
    this.reading = true,
    this.accent,
    this.ink = _silverInk,
    this.bipolar = false,
    required this.label,
    required this.text,
    required this.value,
    required this.initial,
    required this.range,
    required this.size,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<_Knob> createState() => _KnobState();
}

/// _KnobState is a knob and, double-clicked, a field to type a number in.
class _KnobState extends State<_Knob> {
  bool _typing = false;
  final TextEditingController _typed = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clicked away from, what was typed is kept.
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commit();
    });
  }

  @override
  void dispose() {
    _typed.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get label => widget.label;
  String get text => widget.text;
  double get value => widget.value;
  double get initial => widget.initial;
  _Range get range => widget.range;
  double get size => widget.size;
  bool get automated => widget.automated;
  bool get held => widget.held;
  bool get modulated => widget.modulated;
  List<(String, VoidCallback)> get menu => widget.menu;
  bool get reading => widget.reading;
  bool get bipolar => widget.bipolar;
  void Function(double v, {bool transient}) get onChanged => widget.onChanged;
  VoidCallback get onCommit => widget.onCommit;

  void _type() {
    _typed.text = text;
    _typed.selection =
        TextSelection(baseOffset: 0, extentOffset: _typed.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    var v = typedValue(_typed.text, text, range.min, range.max, value: value);
    setState(() => _typing = false);
    if (v != null) onChanged(v);
  }

  /// _face is the knob's drawn size, 32, 27 or 22 by card height.
  double get _face => size >= 44
      ? 32
      : size >= 36
          ? 27
          : size >= 26
              ? 22
              : size;

  /// _panelKnob is the knob in ChainPanelStyle: its name, then its value in
  /// a stepper's box (arrows either side, scrubbed, double-clicked to type).
  Widget _panelKnob(MixerLook look) {
    var s = look.studio;
    // An arrow moves it by the least its reading shows (1% of a share in
    // percent) or 1/100 of its travel; shift, a tenth of that.
    var fine = _fineStep;
    void step(int dir) {
      var by = (HardwareKeyboard.instance.isShiftPressed ? 0.1 : 1.0) *
          (widget.step ?? fine ?? 0);
      var next = widget.step != null || fine != null
          ? _snapped(value + dir * by, by)
          : range.fromUnit(range.toUnit(value) +
              dir * (HardwareKeyboard.instance.isShiftPressed ? 0.001 : 0.01));
      onChanged(next.clamp(range.min, range.max).toDouble(), transient: true);
      onCommit();
    }

    Widget arrow(IconData icon, int dir, String name) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey("knob$name-$label"),
            behavior: HitTestBehavior.opaque,
            onTap: () => step(dir),
            child: SizedBox(
                width: 24, child: Icon(icon, size: 15, color: s.muted)),
          ),
        );
    Widget dot(String key, Color colour) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            key: ValueKey(key),
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
        );
    var reading = _typing
        ? TextField(
            key: ValueKey("knobTyped-$label"),
            controller: _typed,
            focusNode: _focus,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: s.text),
            decoration: const InputDecoration(
                isDense: true, border: InputBorder.none),
            onSubmitted: (_) => _commit(),
          )
        : MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: ValueKey("knobValue-$label"),
              behavior: HitTestBehavior.opaque,
              supportedDevices: dragPointers,
              // From the press: no scrub lost to telling a drag.
              dragStartBehavior: DragStartBehavior.down,
              onDoubleTap: _type,
              onHorizontalDragStart: (_) => _scrubAt = range.toUnit(value),
              onHorizontalDragUpdate: (d) => _scrub(d.delta.dx),
              onHorizontalDragEnd: (_) => onCommit(),
              child: Center(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: s.text)),
              ),
            ),
          );
    var edge = modulated
        ? modulationColour
        : widget.own
            ? ownColour
            : s.edge;
    var body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            key: ValueKey("knobName-$label"),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => onChanged(initial),
            child: SizedBox(
            height: 18,
            child: Row(children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: s.muted)),
              ),
              if (widget.own) dot("knobOwn", ownColour),
              if (modulated) dot("knobModulated", modulationColour),
              if (automated)
                dot("knobAutomated",
                    held ? const Color(0xFF7D838D) : automationColour),
            ]),
          ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: s.inset,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: edge),
            ),
            child: Row(children: [
              arrow(Icons.chevron_left, -1, "Less"),
              Container(width: 1, color: s.edge.withValues(alpha: 0.6)),
              Expanded(child: reading),
              Container(width: 1, color: s.edge.withValues(alpha: 0.6)),
              arrow(Icons.chevron_right, 1, "More"),
            ]),
          ),
        ]);
    // Not dragged up and down as a whole, as the round knob is: its parts
    // say what they do -- the arrows click, the value scrubs across.
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: box.maxWidth.isFinite ? null : 104,
        child: menu.isEmpty ? body : _KnobMenu(menu: menu, child: body),
      ),
    );
  }

  /// _fineStep is the least change the reading shows, but no finer than a
  /// thousandth of travel; null for a log knob, which steps by its travel.
  double? get _fineStep {
    if (range.log) return null;
    var by = shownStep(text, value);
    var travel = (range.max - range.min).abs();
    if (by == null || by < travel / 1000) return travel / 100;
    return by;
  }

  double _snapped(double v, double by) =>
      by <= 0 ? v : (v / by).roundToDouble() * by;

  /// _scrubAt is where a scrub has the knob, in its travel, unsnapped.
  double _scrubAt = 0;

  /// _scrub moves it [dx] px: its whole travel across 400 px, shift four
  /// times finer, snapped to the least its reading shows.
  void _scrub(double dx) {
    var shift = HardwareKeyboard.instance.isShiftPressed;
    _scrubAt = (_scrubAt + dx / (shift ? 1600 : 400)).clamp(0.0, 1.0);
    var v = range.fromUnit(_scrubAt);
    var by = widget.step ?? _fineStep;
    if (by != null) v = _snapped(v, shift ? by / 10 : by);
    onChanged(v.clamp(range.min, range.max).toDouble(), transient: true);
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    if (ChainPanelStyle.on(context)) return _panelKnob(look);
    var face = _face;
    // The whole knob takes a drag: name and reading as well as dial.
    return _Dragged(
      value: value,
      initial: initial,
      range: range,
      onChanged: onChanged,
      onCommit: onCommit,
      menu: menu,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CustomPaint(
                    size: Size.square(face),
                    painter: _KnobFace(range.toUnit(value),
                        accent: widget.own ? ownColour : look.colors.primary,
                        from: bipolar ? range.toUnit(0) : 0)),
                if (widget.own)
                  Positioned(
                    top: 0,
                    left: -6,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey("knobOwn"),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: ownColour, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                if (modulated)
                  IgnorePointer(
                    child: Container(
                      key: const ValueKey("knobModulated"),
                      width: face + 4,
                      height: face + 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: modulationColour, width: 2),
                      ),
                    ),
                  ),
                if (automated)
                  Positioned(
                    top: 0,
                    right: -6,
                    child: Container(
                      key: const ValueKey("knobAutomated"),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: held
                              ? const Color(0xFF7D838D)
                              : automationColour),
                    ),
                  ),
              ]),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, color: look.studio.muted)),
          if (reading && _typing)
            SizedBox(
              width: 56,
              height: 16,
              child: Focus(
                onKeyEvent: (node, e) {
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() => _typing = false);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: ValueKey("knobTyped-$label"),
                  controller: _typed,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: look.studio.text),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    filled: true,
                    fillColor: look.studio.inset,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: look.colors.primary)),
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            )
          else if (reading)
            Tooltip(
              message: "Double-click to type a value",
              waitDuration: const Duration(milliseconds: 800),
              child: GestureDetector(
                key: ValueKey("knobValue-$label"),
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _type,
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: look.studio.text)),
              ),
            ),
        ],
      ),
    );
  }
}

/// DeviceKnob is the Chain's knob for editors outside this file: drag up to
/// turn right, double-click for [initial]; [log] for hertz and seconds.
class DeviceKnob extends StatelessWidget {
  final String label;
  final String text;
  final double value, initial, min, max;
  final bool log;
  final double size;
  final Color accent;
  final Color ink;
  final bool bipolar;
  final void Function(double v, {bool transient}) onChanged;
  final VoidCallback onCommit;

  /// menu, modulated (a pink ring) and own: as _Knob's.
  final List<(String, VoidCallback)> menu;
  final bool modulated;
  final bool own;

  /// automated is whether keys move it: the dot by its name.
  final bool automated;

  final double? step;

  const DeviceKnob({
    this.automated = false,
    this.step,
    this.menu = const [],
    this.modulated = false,
    this.own = false,
    required this.label,
    required this.text,
    required this.value,
    required this.initial,
    required this.min,
    required this.max,
    required this.accent,
    required this.ink,
    required this.onChanged,
    required this.onCommit,
    this.log = false,
    this.size = 38,
    this.bipolar = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _Knob(
        automated: automated,
        step: step,
        menu: menu,
        modulated: modulated,
        own: own,
        label: label,
        text: text,
        value: value,
        initial: initial,
        range: _Range(min, max, log: log),
        size: size,
        accent: accent,
        ink: ink,
        bipolar: bipolar,
        onChanged: onChanged,
        onCommit: onCommit,
      );
}

/// typedValue is what was [typed] for a knob that reads [shown], in its own
/// terms -- "50" a half where it reads in percent, "1.2k" or "1200" hertz
/// -- held to [min] and [max]; null where nothing like a number was typed.
double? typedValue(String typed, String shown, double min, double max,
    {double? value}) {
  var t = typed.trim().replaceAll("\u2212", "-").replaceAll(",", ".");
  var m = RegExp(r"-?\d*\.?\d+").firstMatch(t);
  if (m == null) return null;
  var v = double.tryParse(m.group(0)!);
  if (v == null) return null;
  var rest = t.substring(m.end).trim().toLowerCase();
  if (rest.startsWith("k")) v *= 1000;
  // A share shown in percent (1 shown as "100%") takes a number typed as
  // a percent. Told by what it shows against its value, not by its most:
  // "How far" goes to 300%. A knob already in percent units ("50%" for 50)
  // is not.
  if (shown.trim().endsWith("%")) {
    var n = _shownNumber(shown);
    var ratio = value != null && n != null && n != 0 && value.abs() > 1e-9
        ? n / value
        : null;
    var share = ratio != null ? ratio > 50 && ratio < 200 : max <= 2.0001;
    if (share) v /= 100;
  }
  // Shown in kilohertz, a small number typed is in kilohertz too.
  if (!rest.startsWith("k") && shown.contains("kHz") && v < min) v *= 1000;
  return v.clamp(math.min(min, max), math.max(min, max)).toDouble();
}

double? _shownNumber(String shown) {
  var m = RegExp(r"-?\d*\.?\d+")
      .firstMatch(shown.replaceAll("\u2212", "-").replaceAll(",", "."));
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// shownStep is the least change reading [shown] can show, in the value's
/// terms (1% shown in percent is 0.01), where the reading is the value
/// times a power of ten; null otherwise (dB from a gain) or if unclear.
double? shownStep(String shown, double value) {
  var m = RegExp(r"-?\d*\.?\d+")
      .firstMatch(shown.replaceAll("\u2212", "-").replaceAll(",", "."));
  if (m == null) return null;
  var digits = m.group(0)!;
  var n = double.tryParse(digits);
  if (n == null || n == 0 || value.abs() < 1e-9) return null;
  var scale = (n / value).abs();
  var tens = math.log(scale) / math.ln10;
  // Rounded readings stray from the exact power: within a tenth of one.
  if ((tens - tens.round()).abs() > 0.05) return null;
  var dot = digits.indexOf(".");
  var decimals = dot < 0 ? 0 : digits.length - dot - 1;
  return math.pow(10, -decimals) / math.pow(10, tens.round());
}

/// _sweep is a knob's travel, from seven o'clock round to five.
const _sweepStart = math.pi * 0.75, _sweep = math.pi * 1.5;

class _KnobFace extends CustomPainter {
  final double unit;

  /// accent and from: see _Knob.accent and _Knob.bipolar.
  final Color? accent;
  final double from;
  _KnobFace(this.unit, {this.accent, this.from = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (accent != null) return _dark(canvas, size, accent!);
    var c = size.center(Offset.zero);
    var r = size.width / 2;
    var ring = Rect.fromCircle(center: c, radius: r - 2);
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF9A9EA5));
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep * unit,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2E9BF0));
    var body = r - 7;
    canvas.drawCircle(
        c + const Offset(0, 1.5), body, Paint()..color = Colors.black26);
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFFFAFAFB), Color(0xFFA9AEB6)])
              .createShader(Rect.fromCircle(center: c, radius: body)));
    var a = _sweepStart + _sweep * unit;
    canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * body * 0.25,
        c + Offset(math.cos(a), math.sin(a)) * body * 0.85,
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = _silverInk);
  }

  /// _dark is the Chain's knob: a dark track, the arc in its accent from
  /// [from] to its value, a dark body and a light pointer.
  void _dark(Canvas canvas, Size size, Color accent) {
    var c = size.center(Offset.zero);
    var r = size.width / 2;
    var ring = Rect.fromCircle(center: c, radius: r - 2);
    var stroke = math.max(2.5, size.width * 0.1);
    canvas.drawArc(
        ring,
        _sweepStart,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2C2843));
    var a0 = _sweepStart + _sweep * from.clamp(0.0, 1.0),
        a1 = _sweepStart + _sweep * unit;
    if ((a1 - a0).abs() > 0.01) {
      canvas.drawArc(
          ring,
          math.min(a0, a1),
          (a1 - a0).abs(),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = accent);
    }
    var body = r - stroke - 2;
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.2, -0.36),
                  colors: [Color(0xFF46405F), Color(0xFF211D33)])
              .createShader(Rect.fromCircle(center: c, radius: body)));
    canvas.drawCircle(
        c,
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF3E3958));
    canvas.drawLine(
        c + Offset(math.cos(a1), math.sin(a1)) * body * 0.15,
        c + Offset(math.cos(a1), math.sin(a1)) * body * 0.85,
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF3F0F8));
  }

  @override
  bool shouldRepaint(_KnobFace old) =>
      old.unit != unit || old.accent != accent || old.from != from;
}

/// _ReductionBar is gain reduction as a bar falling from the top (20 dB full).
class _ReductionBar extends CustomPainter {
  final double reduced;
  _ReductionBar(this.reduced);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = const Color(0xFF2B2F36));
    var depth = (reduced / 20).clamp(0.0, 1.0) * (size.height - 4);
    canvas.drawRect(Rect.fromLTWH(2, 2, size.width - 4, depth),
        Paint()..color = const Color(0xFFF0A33C));
  }

  @override
  bool shouldRepaint(_ReductionBar old) => old.reduced != reduced;
}
