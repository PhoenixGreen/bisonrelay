part of 'canvas_mixer.dart';

// The fader: its decibel travel, the typed level under it, and the well, scale
// and cap it is drawn in. Part of canvas_mixer.dart.

/// _faderTop and _faderBottom are the fader's travel, in decibels. The
/// bottom is silence.
const double _faderTop = 6;

const double _faderBottom = -60;

/// faderPosition is where [db] sits on the fader, nought at the top to one at
/// the bottom. Not a straight line in decibels: most of the travel is spent
/// where mixing happens, between minus thirty and the top.
double faderPosition(double db) => db <= _faderBottom
    ? 1
    : math
        .pow((_faderTop - db) / (_faderTop - _faderBottom), 0.6)
        .toDouble()
        .clamp(0.0, 1.0);

double faderDb(double position) => position >= 0.995
    ? -90
    : _faderTop -
        math.pow(position.clamp(0.0, 1.0), 1 / 0.6) *
            (_faderTop - _faderBottom);

String dbText(double db) => db <= -89
    ? "−∞"
    : "${db > 0 ? "+" : db < 0 ? "−" : ""}${db.abs().toStringAsFixed(1)}";

/// parseDb reads a level somebody typed: "-6", "−6.5 dB", "+3", "0", or
/// "-inf" for silence, clamped to what the fader reaches. Null for anything
/// that is not a level, which leaves the fader where it was.
double? parseDb(String text) {
  var t = text
      .trim()
      .toLowerCase()
      .replaceAll("−", "-")
      .replaceAll("db", "")
      .replaceAll(" ", "");
  if (t == "-inf" || t == "-∞" || t == "inf" || t == "∞") return -90;
  var v = double.tryParse(t);
  if (v == null || !v.isFinite) return null;
  if (v <= _faderBottom - 30) return -90;
  return v.clamp(-90.0, _faderTop).toDouble();
}

/// DbReading is the level under a fader: clicked, it takes a typed value.
class DbReading extends StatefulWidget {
  final double db;
  final ValueChanged<double> onSet;
  final TextStyle style;

  /// textKey is on the reading itself, for tests.
  final Key? textKey;

  final double fieldHeight;

  /// unit follows the number: " dB" under a fader, nothing where there is
  /// no room for it.
  final String unit;

  const DbReading(
      {required this.db,
      required this.onSet,
      required this.style,
      this.textKey,
      this.fieldHeight = 16,
      this.unit = " dB",
      super.key});

  @override
  State<DbReading> createState() => _DbReadingState();
}

class _DbReadingState extends State<DbReading> {
  bool _typing = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    setState(() {
      _typing = true;
      _text.text = widget.db <= -89 ? "-inf" : widget.db.toStringAsFixed(1);
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (!_typing) return;
    var v = parseDb(_text.text);
    setState(() => _typing = false);
    if (v != null && v != widget.db) widget.onSet(v);
  }

  @override
  Widget build(BuildContext context) {
    if (_typing) {
      return SizedBox(
        height: widget.fieldHeight,
        child: TextField(
          key: const ValueKey("dbEntry"),
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          style: widget.style,
          decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        // One line, shrunk rather than wrapped: a reading on two lines would
        // make a column's fader shorter than its neighbours'.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text("${dbText(widget.db)}${widget.unit}",
              key: widget.textKey,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: widget.style),
        ),
      ),
    );
  }
}

class _Fader extends StatelessWidget {
  final double db;
  final _Meter meter;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;
  final bool wide;

  /// small is a mixer strip's, half the effects' size. [labels] numbers its
  /// scale (not in a narrow strip).
  final bool small;
  final bool labels;

  const _Fader({
    required this.db,
    required this.meter,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    this.wide = false,
    this.small = false,
    this.labels = true,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          var h = box.maxHeight;
          void at(double y) =>
              onChanged(faderDb(((y - 6) / (h - 12)).clamp(0.0, 1.0)),
                  transient: true);
          // A strip's: one well, the meter inside it, the cap riding over it
          // and on a wide strip the decibels beside it.
          if (small) {
            var width = labels ? _wellWideW : _wellNarrowW;
            return Center(
              child: GestureDetector(
                supportedDevices: dragPointers,
                key: const ValueKey("fader"),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) => at(d.localPosition.dy),
                onVerticalDragUpdate: (d) => at(d.localPosition.dy),
                onVerticalDragEnd: (_) => onCommit(),
                onDoubleTap: () => onChanged(0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: SizedBox(
                    width: width,
                    height: h,
                    child: Stack(children: [
                      if (labels)
                        Positioned.fill(
                          child: CustomPaint(
                              painter: _WellScale(theme.studio, width / 2)),
                        ),
                      Positioned(
                        left: width / 2 - _wellMeterW / 2,
                        width: _wellMeterW,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: theme.studio.inset,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: theme.studio.edge),
                          ),
                          child: CustomPaint(
                              size: Size.infinite,
                              painter: _MeterPainter(meter, theme.studio,
                                  inset: 0)),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _WellCap(db, theme.studio)),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          }
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
              supportedDevices: dragPointers,
              key: const ValueKey("fader"),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) => at(d.localPosition.dy),
              onVerticalDragUpdate: (d) => at(d.localPosition.dy),
              onVerticalDragEnd: (_) => onCommit(),
              onDoubleTap: () => onChanged(0),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: CustomPaint(
                  size: Size(
                      small
                          ? (labels ? 26 : 14)
                          : wide
                              ? 44
                              : 40,
                      h),
                  painter: _FaderPainter(db, theme.studio,
                      small: small, labels: labels),
                ),
              ),
            ),
            SizedBox(width: small ? 2 : 4),
            CustomPaint(
              size: Size(
                  small
                      ? (labels ? (wide ? 12 : 9) : 6)
                      : wide
                          ? 22
                          : 14,
                  h),
              painter: _MeterPainter(meter, theme.studio),
            ),
          ]);
        },
      );
}

/// _wellWideW and _wellNarrowW are a strip's fader well with its scale and
/// without; _wellMeterW the meter's well in the middle of it.
const double _wellWideW = 78;

const double _wellNarrowW = 32;

const double _wellMeterW = 14;

/// _WellScale is a strip fader's decibels, down the left of its cap: each
/// mark's number with a short line, nought brighter.
class _WellScale extends CustomPainter {
  final StudioColors colors;
  final double centre;
  _WellScale(this.colors, this.centre);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < 70) return;
    var right = centre - 18;
    for (var m in _FaderPainter._marks) {
      var y = 6 + faderPosition(m) * (size.height - 12);
      var unity = m == 0;
      var ink = unity ? colors.text : colors.muted;
      canvas.drawLine(Offset(right - 3, y), Offset(right, y),
          Paint()
            ..strokeWidth = 1
            ..color = ink);
      var label = paintedLabel(
          m > 0 ? "+${m.round()}" : "${m.round()}".replaceAll("-", "−"),
          TextStyle(
              fontSize: 8,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ink));
      label.paint(canvas,
          Offset(right - 5 - label.width, y - label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WellScale old) =>
      old.colors != colors || old.centre != centre;
}

/// _WellCap is a strip fader's cap, riding over its well where the level
/// is: light, rounded, a line across its middle.
class _WellCap extends CustomPainter {
  final double db;
  final StudioColors colors;
  _WellCap(this.db, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var y = 6 + faderPosition(db) * (size.height - 12);
    var cap = Rect.fromCenter(
        center: Offset(size.width / 2, y), width: 30, height: 12);
    var rrect = RRect.fromRectAndRadius(cap, const Radius.circular(3));
    canvas.drawRRect(
        rrect.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0xAA000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.drawRRect(
        rrect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE6E8EC), Color(0xFFADB2BA)],
          ).createShader(cap));
    canvas.drawLine(Offset(cap.left + 5, y), Offset(cap.right - 5, y),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0xFF4A4D55));
  }

  @override
  bool shouldRepaint(_WellCap old) => old.db != db || old.colors != colors;
}

/// _FaderPainter is the fader: a slot with the decibels marked down its
/// left, nought picked out, and a ridged cap with a line in the strip's
/// "on" colour where the level is.
class _FaderPainter extends CustomPainter {
  final double db;
  final StudioColors colors;
  final bool small;
  final bool labels;
  _FaderPainter(this.db, this.colors, {this.small = false, this.labels = true});

  static const _marks = [6.0, 0.0, -6.0, -12.0, -24.0, -48.0];

  @override
  void paint(Canvas canvas, Size size) {
    var k = small ? 0.5 : 1.0;
    var slotX = size.width - (small ? 7 : 13);
    double yOf(double d) => 6 + faderPosition(d) * (size.height - 12);
    for (var m in _marks) {
      var y = yOf(m);
      var unity = m == 0;
      canvas.drawLine(
          Offset(slotX - (unity ? 12 : 8) * k - (small ? 2 : 0), y),
          Offset(slotX - 3 * k - (small ? 1.5 : 0), y),
          Paint()
            ..strokeWidth = 1
            ..color = unity ? colors.muted : colors.edge);
      if (!labels) continue;
      var label = paintedLabel(
          m > 0 ? "+${m.round()}" : "${m.round()}".replaceAll("-", "−"),
          TextStyle(
              fontSize: small ? 6 : 7,
              height: 1,
              color: unity ? colors.text : colors.muted));
      if (size.height > (small ? 70 : 90)) {
        label.paint(
            canvas,
            Offset(
                slotX - (small ? 9 : 14) - label.width, y - label.height / 2));
      }
    }
    var slot = RRect.fromLTRBR(
        slotX - 2, 6, slotX + 2, size.height - 6, const Radius.circular(2));
    canvas.drawRRect(slot, Paint()..color = colors.inset);
    var y = yOf(db);
    canvas.drawRRect(
        RRect.fromLTRBR(slotX - 1.5, y, slotX + 1.5, size.height - 6,
            const Radius.circular(1.5)),
        Paint()..color = colors.on.withValues(alpha: 0.55));
    var cap = Rect.fromCenter(
        center: Offset(slotX, y),
        width: 22 * k + (small ? 1 : 0),
        height: 30 * k);
    var rrect = RRect.fromRectAndRadius(cap, Radius.circular(4 * k + 0.5));
    canvas.drawRRect(
        rrect.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(
        rrect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFECEEF2),
              Color(0xFFC3C7CE),
              Color(0xFF9AA0A9),
              Color(0xFFC9CDD3),
            ],
            stops: [0, 0.46, 0.54, 1],
          ).createShader(cap));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF0E0F12));
    var grip = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF7D838D);
    for (var dy in small ? [-4.5, 4.5] : [-9.0, -5.0, 5.0, 9.0]) {
      canvas.drawLine(
          Offset(slotX - 7 * k, y + dy), Offset(slotX + 7 * k, y + dy), grip);
    }
    canvas.drawLine(
        Offset(slotX - 8 * k, y),
        Offset(slotX + 8 * k, y),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.on);
  }

  @override
  bool shouldRepaint(_FaderPainter old) =>
      old.db != db ||
      old.colors != colors ||
      old.small != small ||
      old.labels != labels;
}
