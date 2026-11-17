part of 'canvas_mixer.dart';

// The level meters: the board every strip's meter reads from, a meter and its
// painter, and the junction meter between two devices of a chain. Part of
// canvas_mixer.dart.

/// _Junction is the meter between two devices of a chain: how loud the
/// sound is after the one on its left, its peak held -- step [index] of
/// the strip (see StripProcessor.taps).
class _Junction extends StatelessWidget {
  final int index;
  final (double, double) level;
  final (double, double) peak;
  final StudioColors colors;
  final double height;

  /// listening is whether the chain is heard from here; onListen hears it
  /// from here, or all of it again, and onAnalyser puts one here.
  final bool listening;
  final VoidCallback onListen;
  final ValueChanged<DeviceKind> onAnalyser;

  /// latched is whether it has clipped since its lights were last cleared,
  /// and onClear clears every join's of the chain.
  final bool latched;
  final VoidCallback onClear;
  const _Junction(this.index, this.level, this.peak, this.colors, this.height,
      {required this.listening,
      required this.onListen,
      required this.onAnalyser,
      this.latched = false,
      required this.onClear});

  /// clipped is whether it has reached nought decibels: held, or since its
  /// lights were cleared.
  bool get clipped => latched || peak.$1 >= 0 || peak.$2 >= 0;

  String get reading =>
      "${level.$1 <= -80 ? "−∞" : level.$1.toStringAsFixed(1)} dB · hold "
      "${peak.$1 <= -80 ? "−∞" : peak.$1.toStringAsFixed(1)}";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, reading),
        chainMenuItem(look,
            key: ValueKey("junctionListen-$index"),
            text: listening
                ? "Stop listening here"
                : "Listen from here (what comes after unheard)",
            onPressed: onListen),
        if (latched)
          chainMenuItem(look,
              key: ValueKey("junctionClear-$index"),
              text: "Clear the clip lights",
              onPressed: onClear),
        chainMenuDivider(look),
        chainMenuHeading(look, "Add an analyser here"),
        for (var kind in const [
          DeviceKind.spectrum,
          DeviceKind.scope,
          DeviceKind.tuner,
          DeviceKind.loudness,
        ])
          chainMenuItem(look,
              key: ValueKey("junctionAnalyser-$index-${kind.name}"),
              text: kind.label,
              onPressed: () => onAnalyser(kind)),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: ValueKey("junction-$index"),
        behavior: HitTestBehavior.opaque,
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: reading,
            child: SizedBox(
              width: 16,
              height: height,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: listening
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: const Color(0xFFE2B04A), width: 1.5))
                      : null,
                  // Its clip light over it, lit red at 0 dB, and the peak
                  // held under it.
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      key: ValueKey("junctionClip-$index"),
                      width: 7,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 3),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          color: clipped
                              ? const Color(0xFFE5484D)
                              : colors.edge),
                    ),
                    SizedBox(
                      width: 9,
                      height: math.min(150.0, math.max(30.0, height - 80)),
                      child: CustomPaint(
                          painter: _MeterPainter(
                              _Meter.fixed(level, peak), colors)),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 16,
                      height: 10,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            peak.$1 <= -80
                                ? "—"
                                : peak.$1.round().toString().replaceFirst(
                                    "-", "−"),
                            key: ValueKey("junctionDb-$index"),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: 8,
                                color: clipped
                                    ? const Color(0xFFE5484D)
                                    : colors.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final _Meter meter;
  final StudioColors colors;

  /// horizontal lays it on its side: nought on the right, the left side's
  /// bar above the right's.
  final bool horizontal;

  /// inset is the room above and below its bars: none in a fader's well.
  final double inset;

  /// Repainted as [meter]'s board moves, without a rebuild.
  _MeterPainter(this.meter, this.colors,
      {this.horizontal = false, this.inset = 6})
      : super(repaint: meter.board);

  (double, double) get level => meter.level;
  (double, double) get peak => meter.peak;

  /// _fill is how far a meter is lit, minus sixty to nought: green, amber
  /// for the last nine decibels, then red.
  double _fill(double db) => ((db + 60) / 60).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (horizontal) {
      // Turned a quarter: its bottom to the left, the left side on top.
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
      _paint(canvas, Size(size.height, size.width), inset: 0);
      canvas.restore();
      return;
    }
    _paint(canvas, size, inset: inset);
  }

  void _paint(Canvas canvas, Size size, {double inset = 6}) {
    var w = (size.width - 2) / 2;
    for (var (i, (db, held))
        in [(level.$1, peak.$1), (level.$2, peak.$2)].indexed) {
      var x = i * (w + 2);
      var well = Rect.fromLTWH(x, inset, w, size.height - 2 * inset);
      canvas.drawRect(well, Paint()..color = colors.inset);
      var segments = math.max(8, (well.height / 4).floor());
      var step = well.height / segments;
      var lit = _fill(db);
      for (var k = 0; k < segments; k++) {
        var f = (k + 0.5) / segments;
        var lamp = f > 0.95
            ? colors.meterHigh
            : f > 0.85
                ? colors.meterMid
                : colors.meterLow;
        var top = well.bottom - (k + 1) * step + 0.5;
        canvas.drawRect(Rect.fromLTWH(x, top, w, math.max(0.5, step - 1)),
            Paint()..color = f <= lit ? lamp : colors.unlit(lamp));
      }
      var peakY = well.bottom - _fill(held) * well.height;
      canvas.drawRect(Rect.fromLTWH(x, peakY - 1, w, 2),
          Paint()..color = colors.text.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      !identical(old.meter.board, meter.board) ||
      old.meter.key != meter.key ||
      old.level != level ||
      old.peak != peak ||
      old.colors != colors ||
      old.horizontal != horizontal;
}

/// mixerDeskBuilds counts the desk built, for a test that the meters move
/// without it.
@visibleForTesting
int mixerDeskBuilds = 0;

/// _MeterBoard is a desk's meters: each strip's level and held peak, in
/// decibels, by its key. It notifies as they move -- about thirty times a
/// second while there is sound -- and only the meters and readings listen.
class _MeterBoard extends ChangeNotifier {
  final Map<String, (double, double)> now = {};
  final Map<String, (double, double)> peaks = {};
  void moved() => notifyListeners();
}

/// _sessionPulse beats while the session plays, for slots waiting or playing.
final _MeterBoard _sessionPulse = _MeterBoard();

/// _Meter is one meter: strip [key]'s on [board], read as it is painted --
/// or, fixed, the level and peak it was made with (a join's, built again
/// as its board moves).
class _Meter {
  final _MeterBoard? board;
  final String key;
  final (double, double) _level, _peak;
  const _Meter(_MeterBoard this.board, this.key)
      : _level = (-90.0, -90.0),
        _peak = (-90.0, -90.0);
  const _Meter.fixed(this._level, this._peak)
      : board = null,
        key = "";

  (double, double) get level =>
      board == null ? _level : board!.now[key] ?? (-90.0, -90.0);
  (double, double) get peak =>
      board == null ? _peak : board!.peaks[key] ?? (-90.0, -90.0);
}
