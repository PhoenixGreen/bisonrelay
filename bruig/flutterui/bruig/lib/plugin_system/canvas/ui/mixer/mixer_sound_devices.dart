part of 'mixer_plugins.dart';

// mixer_sound_devices.dart is the sound chain's own devices: the channel EQ, the compressor, the meters and limiter, and ducking: part of mixer_plugins.dart, split from it to keep
// that file readable (Ken, 2026-11-12). Its imports are the library's.

// ---- Channel EQ

/// eqBandColour is each band's colour: its button, its handle and its own
/// curve. Red at the bottom through to magenta at the top, as Logic has
/// them.
Color eqBandColour(EqSlot slot) => switch (slot) {
      EqSlot.lowCut => const Color(0xFFE5484D),
      EqSlot.low => const Color(0xFFF27D3A),
      EqSlot.lowMid => const Color(0xFFF2C94C),
      EqSlot.mid => const Color(0xFF6FCF5E),
      EqSlot.highMid => const Color(0xFF35C6C2),
      EqSlot.presence => const Color(0xFF3E9BF2),
      EqSlot.high => const Color(0xFF8E6CF2),
      EqSlot.highCut => const Color(0xFFE45BC6),
    };

const _eqBack = Color(0xFF0D1826);
const _eqInk = Color(0xFFC9D6E6);

/// _headerInkLight is what reads on a device's dark header bar -- its
/// remove button, which drawn in the body's ink was there but not seen.
const _headerInkLight = Color(0xFFE8EAEE);
const _eqDim = Color(0xFF6E8199);

/// EqDevice is a strip's Channel EQ in the chain -- the master's, with no
/// [channel].
class EqDevice extends StatefulWidget {
  static const width = 392.0;
  final CanvasController controller;
  final String? channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const EqDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<EqDevice> createState() => _EqDeviceState();
}

class _EqDeviceState extends State<EqDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _analyzer is whether what is playing is drawn behind the curve.
  bool _analyzer = false;
  Float32List? _spectrum;

  /// _picked is the band last touched: its own curve is drawn in its colour.
  EqSlot? _picked;
  EqSlot? _dragging;

  @override
  void tick() =>
      _spectrum = _analyzer && !widget.folded ? strip.spectrum : null;

  static const _fMin = 20.0, _fMax = 20000.0, _gMax = 12.0;
  static const _freq = _Range(_fMin, _fMax, log: true);

  void _write(Eq eq, {bool transient = false}) =>
      strip.write(eq: eq, transient: transient);

  /// _band writes [b] into [slot], switching the EQ and the band on: moving
  /// something is asking to hear it.
  void _band(EqSlot slot, EqBand b, {bool transient = false}) {
    setState(() => _picked = slot);
    _write(strip.eq.withBand(slot, b.copyWith(on: true)).copyWith(on: true),
        transient: transient);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var eq = strip.eq;
          var look = MixerLook.of(context);
          var studio = look.studio;
          var picked = _picked ?? EqSlot.mid;
          var hooks = widget.channel == null
              ? (frozen: false, onFreeze: null, onUnfreeze: null)
              : freezeHooks(
                  context, widget.controller, widget.channel!, chainEq);
          return DeviceFrame(
            id: "eq",
            frozen: hooks.frozen,
            onFreeze: hooks.onFreeze,
            onUnfreeze: hooks.onUnfreeze,
            title: widget.channel == null ? "Master EQ" : "Channel EQ",
            help: "Shapes the sound's tone. Drag a band's point on the curve: "
                "across for where, up and down for how much; its Q knob for "
                "how wide. A chip picks a band and shows its knobs; pressed "
                "again, switches it off.",
            skin: DeviceSkin.studio(studio),
            // The prototype's Tone family: its own colour and mark.
            icon: Icons.equalizer,
            accent: const Color(0xFF9A92EA),
            on: eq.on,
            powerKey: const ValueKey("eqOn"),
            onPower: (v) => _write(eq.copyWith(on: v)),
            // A second set of bands to compare by ear, and back to flat.
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel ?? mixerMasterKey}|eq",
                eq,
                (o) => _write(o as Eq, transient: true)),
            showingB: widget.controller
                .showingBOf("${widget.channel ?? mixerMasterKey}|eq"),
            onReset: () => _write(const Eq().copyWith(on: eq.on)),
            // On the whole sound, its middle or its sides.
            extraMenu: (look) => [
              worksOnMenu(look,
                  id: "eqStereo",
                  value: eq.stereo,
                  onPick: (k) => _write(eq.copyWith(stereo: k))),
            ],
            barExtras: [
              _GainBadge(
                  key: const ValueKey("gainBadge-eq"),
                  controller: widget.controller,
                  channel: widget.channel ?? mixerMasterKey,
                  id: chainEq),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-eq"),
                label: StripPart.eq.label,
                kept: () => _stripKept(StripPart.eq),
                name: widget.controller
                    .presetNameOf(widget.channel ?? mixerMasterKey, "eq"),
                builtIn: [for (var (n, v) in eqPresets) (n, v.toJson())],
                onPick: (name, value) {
                  _write(Eq.fromJson(value));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "eq", name);
                },
                onDefault: () {
                  _write(const Eq().copyWith(on: eq.on));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "eq", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.eq, eq.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: EqDevice.width,
            height: widget.height,
            actions: [
              if (widget.channel case var owner?
                  when widget.controller.canRemovePart(owner, chainEq))
                IconButton(
                  key: const ValueKey("deviceRemove-eq"),
                  tooltip: "Take the EQ out",
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.controller.removePart(owner, chainEq),
                ),
              DeviceMove(
                  id: "eq",
                  canLeft: strip.canMove(chainEq).$1,
                  canRight: strip.canMove(chainEq).$2,
                  onMove: (by) => strip.move(chainEq, by),
                  ink: studio.text),
            ],
            summary: [
              for (var slot in EqSlot.values)
                if (eq.band(slot).on) slot.label,
            ].join(" · "),
            foldedBody: CustomPaint(
                key: const ValueKey("eqFolded"), painter: _MiniCurve(eq)),
            // Its curve, the bands dragged on it, what is playing behind it
            // while Analyzer is on.
            display: Stack(children: [
              Positioned.fill(
                  child: ColoredBox(color: _eqBack, child: _graph(eq))),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  key: const ValueKey("eqAnalyzer"),
                  onTap: () => setState(() {
                    _analyzer = !_analyzer;
                    _spectrum = null;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: studio.panel.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: _analyzer ? look.colors.primary : studio.edge),
                    ),
                    child: Text("Analyse",
                        style: TextStyle(
                            fontSize: 9.5,
                            color: _analyzer ? studio.text : studio.muted)),
                  ),
                ),
              ),
            ]),
            controls: (tier) => [
              _bandButtons(eq),
              ..._bandKnobs(eq, picked, tier),
              if (picked.isCut) _slope(eq, picked, studio),
            ],
            body: const SizedBox(),
          );
        },
      );

  /// _bandKnobs are the picked band's knobs -- where it is, how much (a
  /// bell's or shelf's), how wide -- and the EQ's output.
  List<Widget> _bandKnobs(Eq eq, EqSlot slot, DeviceTier tier) {
    var b = eq.band(slot);
    var size = switch (tier) {
      DeviceTier.large => 46.0,
      DeviceTier.medium => 38.0,
      _ => 28.0,
    };
    var accent = eqBandColour(slot);
    void set(EqBand next, {bool transient = false}) =>
        _band(slot, next, transient: transient);
    return [
      _Knob(
        key: ValueKey("eqFreq-${slot.name}"),
        label: "${slot.label} freq",
        text: _hz(b.freq),
        value: b.freq,
        initial: slot.initial.freq,
        range: _freq,
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        onChanged: (v, {transient = false}) =>
            set(b.copyWith(freq: v), transient: transient),
        onCommit: strip.commit,
      ),
      if (!slot.isCut)
        _Knob(
          key: ValueKey("eqGain-${slot.name}"),
          label: "Gain",
          text: "${_signed(b.gainDb)} dB",
          value: b.gainDb,
          initial: 0,
          range: const _Range(-12, 12),
          size: size,
          reading: tier != DeviceTier.small,
          accent: accent,
          bipolar: true,
          onChanged: (v, {transient = false}) => set(
              b.copyWith(gainDb: (v * 2).roundToDouble() / 2),
              transient: transient),
          onCommit: strip.commit,
        ),
      _Knob(
        key: ValueKey("eqQ-${slot.name}"),
        label: "Q",
        text: b.q.toStringAsFixed(2),
        value: b.q,
        initial: slot.initial.q,
        range: const _Range(0.1, 10, log: true),
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        onChanged: (v, {transient = false}) =>
            set(b.copyWith(q: v), transient: transient),
        onCommit: strip.commit,
      ),
      _Knob(
        key: const ValueKey("eqOutput"),
        label: "Output",
        text: "${_signed(eq.gainDb)} dB",
        value: eq.gainDb,
        initial: 0,
        range: const _Range(-12, 12),
        size: size,
        reading: tier != DeviceTier.small,
        accent: accent,
        bipolar: true,
        onChanged: (v, {transient = false}) => _write(
            eq.copyWith(on: true, gainDb: (v * 2).roundToDouble() / 2),
            transient: transient),
        onCommit: strip.commit,
      ),
    ];
  }

  /// _slope is a cut's steepness, stepped through by a click.
  Widget _slope(Eq eq, EqSlot slot, StudioColors studio) {
    var b = eq.band(slot);
    return Row(children: [
      Text("Slope", style: TextStyle(fontSize: 9.5, color: studio.muted)),
      const SizedBox(width: 8),
      GestureDetector(
        key: ValueKey("eqSlope-${slot.name}"),
        onTap: () {
          var i = eqSlopes.indexOf(b.slope);
          _band(slot, b.copyWith(slope: eqSlopes[(i + 1) % eqSlopes.length]));
        },
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: studio.edge),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text("${b.slope} dB/Oct ▸",
              style: TextStyle(fontSize: 10, color: studio.text)),
        ),
      ),
    ]);
  }

  /// _bandButtons are a chip a band: pressed, the band is picked -- its
  /// knobs shown -- and switched on or off.
  Widget _bandButtons(Eq eq) => SizedBox(
        height: 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var slot in EqSlot.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Tooltip(
                  message: "${slot.label}: "
                      "${eq.band(slot).on ? "on" : "off"}",
                  child: GestureDetector(
                    key: ValueKey("eqBand-${slot.name}"),
                    onTap: () {
                      var b = eq.band(slot);
                      // A press on the band picked switches it; on another,
                      // picks it, switching it on.
                      var switching = _picked == slot || !b.on;
                      setState(() => _picked = slot);
                      if (switching) {
                        _write(eq
                            .withBand(slot, b.copyWith(on: !b.on))
                            .copyWith(on: true));
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: eq.band(slot).on
                            ? eqBandColour(slot).withValues(alpha: 0.85)
                            : const Color(0xFF1F2E40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: (_picked ?? EqSlot.mid) == slot
                                ? Colors.white70
                                : Colors.black26),
                      ),
                      child: CustomPaint(
                        painter: _BandIcon(
                            slot,
                            eq.band(slot).on
                                ? const Color(0xFF0D1826)
                                : _eqDim),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  double _x(double f, double w) => _freq.toUnit(f) * w;
  double _y(double g, double h) => h / 2 - g / _gMax * (h / 2 - 14);
  double _g(double y, double h) =>
      ((h / 2 - y) / (h / 2 - 14) * _gMax).clamp(-_gMax, _gMax);

  /// _handle is where [slot]'s handle is drawn: a cut's on its own curve at
  /// its corner, the rest at their gain.
  Offset _handle(Eq eq, EqSlot slot, double w, double h) {
    var b = eq.band(slot);
    return Offset(_x(b.freq, w),
        _y(slot.isCut ? (b.on ? eq.bandDb(slot, b.freq) : 0) : b.gainDb, h));
  }

  EqSlot? _nearest(Eq eq, Offset p, double w, double h, double within) {
    EqSlot? best;
    var closest = within;
    for (var slot in EqSlot.values) {
      var d = (_handle(eq, slot, w, h) - p).distance;
      if (d < closest) {
        closest = d;
        best = slot;
      }
    }
    return best;
  }

  /// _moveTo puts the handle being dragged at [at]: sideways its
  /// frequency, up and down its gain.
  void _moveTo(Offset at, double w, double h) {
    var slot = _dragging;
    if (slot == null) return;
    var b = strip.eq.band(slot);
    var next = b.copyWith(
        freq: _freq.fromUnit(at.dx / w),
        gainDb: slot.isCut ? b.gainDb : (_g(at.dy, h) * 2).roundToDouble() / 2);
    _band(slot, next, transient: true);
  }

  Widget _graph(Eq eq) => LayoutBuilder(builder: (context, box) {
        var w = box.maxWidth, h = box.maxHeight;
        // Set by a press and a drag only: a wheel or a trackpad's scroll
        // over it scrolls the chain (Ken). A band's Q is its knob.
        return GestureDetector(
          key: const ValueKey("eqCurve"),
          supportedDevices: dragPointers,
          // The handle is chosen where the press lands, not where the drag
          // is recognised: in the sideways-scrolling chain that is a
          // little way off, past the handle.
          onPanDown: (d) => setState(() {
            _dragging = _nearest(eq, d.localPosition, w, h, 24);
            if (_dragging != null) _picked = _dragging;
          }),
          onPanCancel: () => setState(() => _dragging = null),
          // Moved from the start: what was moved while the drag was being
          // recognised arrives with it, not as an update.
          onPanStart: (d) => _moveTo(d.localPosition, w, h),
          onPanUpdate: (d) => _moveTo(d.localPosition, w, h),
          onPanEnd: (_) {
            if (_dragging != null) strip.commit();
            setState(() => _dragging = null);
          },
          onDoubleTapDown: (d) {
            var slot = _nearest(eq, d.localPosition, w, h, 14);
            if (slot == null || slot.isCut) return;
            _band(slot, eq.band(slot).copyWith(gainDb: 0));
          },
          child: CustomPaint(
            size: Size(w, h),
            painter: _EqGraph(eq, _picked, _spectrum, _x, _y, _handle),
          ),
        );
      });
}

/// _BandIcon is a band's shape, drawn small on its button.
class _BandIcon extends CustomPainter {
  final EqSlot slot;
  final Color ink;
  _BandIcon(this.slot, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var cx = w / 2, mid = h / 2;
    var l = cx - 16, r = cx + 16, up = mid - 7, down = mid + 7;
    var p = Path();
    switch (slot.kind) {
      case EqKind.lowCut:
        p
          ..moveTo(l, down)
          ..quadraticBezierTo(l + 8, mid - 2, l + 14, mid - 2)
          ..lineTo(r, mid - 2);
      case EqKind.highCut:
        p
          ..moveTo(l, mid - 2)
          ..lineTo(r - 14, mid - 2)
          ..quadraticBezierTo(r - 8, mid - 2, r, down);
      case EqKind.lowShelf:
        p
          ..moveTo(l, up)
          ..lineTo(cx - 5, up)
          ..cubicTo(cx, up, cx, mid + 3, cx + 5, mid + 3)
          ..lineTo(r, mid + 3);
      case EqKind.highShelf:
        p
          ..moveTo(l, mid + 3)
          ..lineTo(cx - 5, mid + 3)
          ..cubicTo(cx, mid + 3, cx, up, cx + 5, up)
          ..lineTo(r, up);
      case EqKind.bell:
        p
          ..moveTo(l, mid + 4)
          ..lineTo(cx - 9, mid + 4)
          ..cubicTo(cx - 4, mid + 4, cx - 3, up - 1, cx, up - 1)
          ..cubicTo(cx + 3, up - 1, cx + 4, mid + 4, cx + 9, mid + 4)
          ..lineTo(r, mid + 4);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = ink);
  }

  @override
  bool shouldRepaint(_BandIcon old) => old.ink != ink || old.slot != slot;
}

/// paintedLabel is [text] in [style], laid out: kept, as the meters and
/// graphs paint the same few labels on every frame they move, and laying
/// them out again each time was much of what those frames cost.
///
/// With [maxWidth] it is laid out no wider, on one line ended with an
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

class _EqGraph extends CustomPainter {
  final Eq eq;
  final EqSlot? picked;
  final Float32List? spectrum;
  final double Function(double, double) x;
  final double Function(double, double) y;
  final Offset Function(Eq, EqSlot, double, double) handle;
  _EqGraph(this.eq, this.picked, this.spectrum, this.x, this.y, this.handle);

  static const _labels = [
    (20.0, "20"),
    (50.0, "50"),
    (100.0, "100"),
    (200.0, "200"),
    (500.0, "500"),
    (1000.0, "1k"),
    (2000.0, "2k"),
    (5000.0, "5k"),
    (10000.0, "10k"),
    (20000.0, "20k"),
  ];

  void _text(Canvas canvas, String s, Offset at, {bool right = false}) {
    var tp = paintedLabel(s, const TextStyle(fontSize: 9, color: _eqDim));
    tp.paint(canvas, right ? at - Offset(tp.width, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    var frame =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(
        frame,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF16273B), Color(0xFF0A1420)])
              .createShader(Offset.zero & size));
    canvas.save();
    canvas.clipRRect(frame);
    var grid = Paint()..color = const Color(0xFF22354B);
    for (var (f, label) in _labels) {
      var px = x(f, w);
      canvas.drawLine(Offset(px, 0), Offset(px, h), grid);
      if (f > 20 && f < 20000) _text(canvas, label, Offset(px + 3, 3));
    }
    for (var g in const [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      canvas.drawLine(Offset(0, y(g, h)), Offset(w, y(g, h)),
          g == 0 ? (Paint()..color = const Color(0xFF3A5272)) : grid);
      if (g != 12 && g != -12) {
        _text(canvas, g == 0 ? "0" : _signed(g), Offset(w - 4, y(g, h) - 11),
            right: true);
      }
    }
    // The analyzer: what is playing, after the EQ, sixty decibels below its
    // loudest at the floor.
    if (spectrum case var bins? when bins.isNotEmpty) {
      var loudest = bins.fold(0.0, (m, v) => v > m ? v : m);
      if (loudest > 0) {
        const nyquist = 22050.0;
        var fill = Path()..moveTo(0, h);
        for (var i = 1; i < bins.length; i++) {
          var f = i * nyquist / bins.length;
          if (f < 20) continue;
          var db = 20 * math.log(bins[i] / loudest + 1e-6) / math.ln10 +
              eq.responseDb(f);
          fill.lineTo(x(f, w), h - ((db + 60) / 60).clamp(0.0, 1.0) * (h - 16));
        }
        fill
          ..lineTo(w, h)
          ..close();
        canvas.drawPath(fill,
            Paint()..color = const Color(0xFF5F7FA6).withValues(alpha: 0.35));
      }
    }
    var shown = eq.copyWith(on: true);
    var zero = y(0, h);
    Path curve(double Function(double f) db) {
      var p = Path();
      for (var i = 0; i <= 200; i++) {
        var px = i / 200 * w;
        var f = 20 * math.pow(1000, px / w).toDouble();
        var py = y(db(f).clamp(-14.0, 14.0), h);
        i == 0 ? p.moveTo(px, py) : p.lineTo(px, py);
      }
      return p;
    }

    // The band last touched, alone, in its colour.
    if (picked case var slot? when eq.band(slot).on) {
      var own = curve((f) => shown.bandDb(slot, f));
      var area = Path.from(own)
        ..lineTo(w, zero)
        ..lineTo(0, zero)
        ..close();
      canvas.drawPath(
          area, Paint()..color = eqBandColour(slot).withValues(alpha: 0.22));
      canvas.drawPath(
          own,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = eqBandColour(slot).withValues(alpha: 0.8));
    }
    // Everything together, filled to the line.
    var all = curve((f) => shown.responseDb(f));
    var area = Path.from(all)
      ..lineTo(w, zero)
      ..lineTo(0, zero)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..color = (eq.on ? const Color(0xFF6CC4FF) : const Color(0xFF6E8199))
              .withValues(alpha: 0.16));
    canvas.drawPath(
        all,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = eq.on ? const Color(0xFFE6F2FF) : _eqDim);
    for (var slot in EqSlot.values) {
      var b = eq.band(slot);
      var at = handle(eq, slot, w, h);
      var colour = eqBandColour(slot);
      canvas.drawCircle(at, slot == picked ? 8 : 6.5,
          Paint()..color = b.on ? colour : colour.withValues(alpha: 0.3));
      canvas.drawCircle(
          at,
          slot == picked ? 8 : 6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = slot == picked ? Colors.white : Colors.black54);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EqGraph old) =>
      old.spectrum != spectrum ||
      old.picked != picked ||
      !identical(old.eq, eq);
}

// ---- Compressor

/// _silverInk and _silverDim are what reads on a device's card: they were
/// a silver unit's dark ink, and every card is the Chain's dark one now.
const _silverInk = Color(0xFFE8E4EE);
const _silverDim = Color(0xFF8E8A9C);

/// _faceInk and _faceDim read on a cream meter's face: the compressor's VU,
/// the ducking curve.
const _faceInk = Color(0xFF2B2F36);
const _faceDim = Color(0xFF6A707A);
const _cream = Color(0xFFF1E7C9);

/// CompDevice is a strip's compressor in the chain -- the master's glue,
/// with no [channel].
class CompDevice extends StatefulWidget {
  static const width = 440.0;
  final CanvasController controller;
  final String? channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const CompDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<CompDevice> createState() => _CompDeviceState();
}

class _CompDeviceState extends State<CompDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _needleShown is whether the display shows the gain-reduction needle
  /// rather than the transfer curve, which it opens on, as the prototype's.
  bool _needleShown = false;
  double _input = -90;

  /// _needle is the gain reduction shown, eased as a VU needle is.
  double _needle = 0;

  @override
  void tick() {
    _input = strip.levelDb;
    var comp = strip.comp;
    // What the compressor is really taking off, from an engine that can
    // measure inside a strip; worked out from the strip's level otherwise.
    var channel = widget.channel;
    var measured =
        channel != null && widget.controller.deviceLevels(channel).isNotEmpty;
    var reduction = !comp.on
        ? 0.0
        : measured
            ? widget.controller.reduction(channel)
            : _input > -60
                ? _input - comp.reducedDb(_input)
                : 0.0;
    _needle += (reduction - _needle) * 0.35;
  }

  void _write(Dynamics c, {bool transient = false}) =>
      strip.write(comp: c, transient: transient);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var comp = strip.comp;
          var output = comp.on && _input > -90
              ? _input +
                  comp.mix *
                      (comp.reducedDb(_input) + comp.totalMakeupDb - _input)
              : _input;
          var look = MixerLook.of(context);
          var studio = look.studio;
          var hooks = widget.channel == null
              ? (frozen: false, onFreeze: null, onUnfreeze: null)
              : freezeHooks(
                  context, widget.controller, widget.channel!, chainComp);
          return DeviceFrame(
            id: "comp",
            frozen: hooks.frozen,
            onFreeze: hooks.onFreeze,
            onUnfreeze: hooks.onUnfreeze,
            title: widget.channel == null ? "Glue" : "Compressor",
            help: "Turns the sound down when it goes over the Threshold, by "
                "the Ratio, so loud and quiet sit closer. Attack and Release "
                "are how fast; Make up brings it back up. Listens to another "
                "channel to duck under it, as a kick pumps a pad.",
            skin: DeviceSkin.studio(studio),
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            on: comp.on,
            powerKey: const ValueKey("compOn"),
            onPower: (v) => _write(comp.copyWith(on: v)),
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel ?? mixerMasterKey}|comp",
                comp,
                (o) => _write(o as Dynamics, transient: true)),
            showingB: widget.controller
                .showingBOf("${widget.channel ?? mixerMasterKey}|comp"),
            // The master's glue starts gentler than a channel's compressor.
            onReset: () => _write((widget.channel == null
                    ? const MasterMix().comp
                    : const Dynamics())
                .copyWith(on: comp.on)),
            extraMenu: (look) => [
              worksOnMenu(look,
                  id: "compStereo",
                  value: comp.stereo,
                  onPick: (k) => _write(comp.copyWith(stereo: k))),
            ],
            barExtras: [
              _GainBadge(
                  key: const ValueKey("gainBadge-comp"),
                  controller: widget.controller,
                  channel: widget.channel ?? mixerMasterKey,
                  id: chainComp),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-comp"),
                label: StripPart.comp.label,
                kept: () => _stripKept(StripPart.comp),
                name: widget.controller
                    .presetNameOf(widget.channel ?? mixerMasterKey, "comp"),
                builtIn: [for (var (n, v) in compPresets) (n, v.toJson())],
                onPick: (name, value) {
                  _write(Dynamics.fromJson(value));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "comp", name);
                },
                onDefault: () {
                  _write((widget.channel == null
                          ? const MasterMix().comp
                          : const Dynamics())
                      .copyWith(on: comp.on));
                  widget.controller.setPresetName(
                      widget.channel ?? mixerMasterKey, "comp", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.comp, comp.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: CompDevice.width,
            height: widget.height,
            actions: [
              if (widget.channel case var owner?
                  when widget.controller.canRemovePart(owner, chainComp))
                IconButton(
                  key: const ValueKey("deviceRemove-comp"),
                  tooltip: "Take the compressor out",
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      widget.controller.removePart(owner, chainComp),
                ),
              DeviceMove(
                  id: "comp",
                  canLeft: strip.canMove(chainComp).$1,
                  canRight: strip.canMove(chainComp).$2,
                  onMove: (by) => strip.move(chainComp, by),
                  ink: studio.text),
            ],
            summary: "${comp.threshold.round()} dB · "
                "${comp.ratio.toStringAsFixed(1)}:1 · "
                "−${_needle.toStringAsFixed(1)} dB",
            // Folded, how much it is taking off.
            foldedBody: CustomPaint(
                key: const ValueKey("compFolded"),
                size: const Size(14, double.infinity),
                painter: _ReductionBar(_needle)),
            display: _display(comp, studio, output),
            controls: (tier) => [
              ..._knobList(comp, tier),
              _autoGain(comp, studio),
              if (widget.channel != null) _listensTo(comp),
            ],
            body: const SizedBox(),
          );
        },
      );

  /// _display is the compressor's screen: its curve, or how much it is
  /// taking off as a needle, switched in its corner, with the reduction
  /// read along its foot.
  Widget _display(Dynamics comp, StudioColors studio, double output) =>
      Stack(children: [
        Positioned.fill(
          child: ColoredBox(
            color: studio.display,
            child: _needleShown
                ? Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _cream, borderRadius: BorderRadius.circular(4)),
                    child: CustomPaint(
                        key: const ValueKey("gainReduction"),
                        painter: _VuNeedle(_needle)),
                  )
                : CustomPaint(
                    key: const ValueKey("compCurve"),
                    painter: _TransferCurve(comp, _input,
                        line: Color.lerp(studio.text, Colors.white, 0.1)!,
                        grid: studio.edge.withValues(alpha: 0.6),
                        dim: studio.muted)),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(children: [
            _tab("Curve", !_needleShown, const ValueKey("compViewGraph"),
                () => setState(() => _needleShown = false), studio),
            const SizedBox(width: 3),
            _tab("Meter", _needleShown, const ValueKey("compViewMeter"),
                () => setState(() => _needleShown = true), studio),
          ]),
        ),
        Positioned(
          left: 6,
          bottom: 4,
          child: IgnorePointer(
            child: Text(
                "takes off ${_needle.toStringAsFixed(1)} dB · out "
                "${output > -60 ? output.round() : "−∞"} dB",
                style: TextStyle(
                    fontSize: 9.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: studio.muted)),
          ),
        ),
      ]);

  /// _tab is one of the display's views, in its corner, as the prototype's.
  Widget _tab(String label, bool on, Key key, VoidCallback onTap,
          StudioColors studio) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: studio.panel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: on ? MixerLook.of(context).colors.primary : studio.edge),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 9.5, color: on ? studio.text : studio.muted)),
        ),
      );

  /// _autoGain is its make-up worked out for it: off, or to a level.
  Widget _autoGain(Dynamics comp, StudioColors studio) => Row(children: [
        Text("Auto gain", style: TextStyle(fontSize: 9.5, color: studio.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: DeviceChoices(
            options: [
              for (var a in AutoGain.values)
                (
                  ValueKey("autoGain-${a.name}"),
                  a.label,
                  comp.autoGain == a,
                  () => _write(comp.copyWith(autoGain: a))
                ),
            ],
          ),
        ),
      ]);

  /// _listensTo is what the compressor hears to turn down by: its own sound,
  /// or another channel's -- a sidechain, as a kick pumps a pad.
  Widget _listensTo(Dynamics comp) {
    var channels = [
      for (var c in widget.controller.timelineChannels)
        if (c.key != widget.channel) c,
    ];
    var chosen = channels.any((c) => c.key == comp.source) ? comp.source : "";
    const ink = TextStyle(fontSize: 11, color: _silverInk);
    return Row(children: [
      const Text("Listens to",
          style: TextStyle(fontSize: 10, color: _silverDim)),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButton<String>(
          key: const ValueKey("compSource"),
          isExpanded: true,
          isDense: true,
          value: chosen,
          style: ink,
          iconEnabledColor: _silverInk,
          dropdownColor: MixerLook.of(context).studio.raised,
          items: [
            const DropdownMenuItem(
                value: "", child: Text("Itself", style: ink)),
            for (var c in channels)
              DropdownMenuItem(
                  value: c.key,
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis, style: ink)),
          ],
          onChanged: (v) {
            if (v != null) _write(comp.copyWith(source: v));
          },
        ),
      ),
    ]);
  }

  /// _knobList are its knobs, sized for [tier], in the order the
  /// prototype has them.
  List<Widget> _knobList(Dynamics comp, DeviceTier tier) {
    var initial =
        widget.channel == null ? const MasterMix().comp : const Dynamics();
    Widget knob(String label, String key, double value, double initialValue,
            _Range range, String text, Dynamics Function(double) apply,
            {bool big = false}) =>
        _Knob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initialValue,
          range: range,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          reading: tier != DeviceTier.small,
          accent: deviceGroupLook(DeviceGroup.dynamics).$2,
          onChanged: (v, {transient = false}) =>
              _write(apply(v), transient: transient),
          onCommit: strip.commit,
        );
    return [
      knob(
          "Threshold",
          "compThreshold",
          comp.threshold,
          initial.threshold,
          const _Range(-60, 0),
          "${comp.threshold.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(threshold: v),
          big: true),
      knob(
          "Ratio",
          "compRatio",
          comp.ratio,
          initial.ratio,
          const _Range(1, 10, log: true),
          "${comp.ratio.toStringAsFixed(1)} : 1",
          (v) => comp.copyWith(ratio: v),
          big: true),
      knob(
          "Make up",
          "compMakeup",
          comp.makeupDb,
          initial.makeupDb,
          const _Range(0, 24),
          "${comp.makeupDb.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(makeupDb: v),
          big: true),
      knob(
          "Knee",
          "compKnee",
          comp.kneeDb,
          initial.kneeDb,
          const _Range(0, 18),
          "${comp.kneeDb.toStringAsFixed(1)} dB",
          (v) => comp.copyWith(kneeDb: v)),
      knob(
          "Attack",
          "compAttack",
          comp.attackMs,
          initial.attackMs,
          const _Range(0.1, 100, log: true),
          "${comp.attackMs.toStringAsFixed(comp.attackMs < 10 ? 1 : 0)} ms",
          (v) => comp.copyWith(attackMs: v)),
      knob(
          "Release",
          "compRelease",
          comp.releaseMs,
          initial.releaseMs,
          const _Range(10, 1000, log: true),
          "${comp.releaseMs.round()} ms",
          (v) => comp.copyWith(releaseMs: v)),
      knob("Mix", "compMix", comp.mix, initial.mix, const _Range(0, 1),
          "${(comp.mix * 100).round()}%", (v) => comp.copyWith(mix: v)),
    ];
  }
}

/// DeviceChoices is a setting that is one of a few, as the prototype draws one:
/// joined buttons, the one chosen filled.
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

/// _Knob is a rotary control: dragged up to turn it right, double-clicked
/// to put it back.
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

  /// menu is what its right-click offers -- a modulator of the chain to
  /// move it with, each -- by name; empty for none.
  final List<(String, VoidCallback)> menu;

  /// reading is whether its value is written under it: not on a short
  /// device, where the room is the knob's.
  final bool reading;

  /// accent, given, draws it as the Chain's cards have it: a dark knob with
  /// its arc in [accent], filled from the middle for a setting that goes
  /// both ways (see [bipolar]); [ink] its label's and reading's colour.
  final Color? accent;
  final Color ink;
  final bool bipolar;

  /// step is how far its arrows move it, in ChainPanelStyle: null for a
  /// fiftieth of its travel.
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

/// _KnobState is a knob, and -- its value double-clicked -- a field to type
/// a number into.
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

  /// _face is the knob's size drawn, as the prototype's: 32 on a tall card,
  /// 27 and 22 on shorter ones, whatever size it was asked for.
  double get _face => size >= 44
      ? 32
      : size >= 36
          ? 27
          : size >= 26
              ? 22
              : size;

  /// _panelKnob is the knob in ChainPanelStyle: its name, then its value
  /// in a stepper's box -- arrows either side, dragged up and down as the
  /// knob is, double-clicked to type.
  Widget _panelKnob(MixerLook look) {
    var s = look.studio;
    // Ken, 2026-11-12: its arrows and its scrub "jump too far ... hard for
    // fine tuning". An arrow moves it by the least its reading shows -- 1%
    // of a share in percent -- or a hundredth of its travel; shift, a tenth
    // of that.
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
        // Its value: scrubbed left and right (Ken, 2026-11-12: the box
        // reads across, so it drags across), double-clicked to type.
        : MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              key: ValueKey("knobValue-$label"),
              behavior: HitTestBehavior.opaque,
              supportedDevices: dragPointers,
              // From where it was pressed: none of the scrub lost to the
              // few pixels it takes to tell a drag.
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
          // Its name, double-clicked: back to where it starts.
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

  /// _fineStep is the least change the reading shows, where that is a fair
  /// step: not finer than a thousandth of its travel. Null for a log knob
  /// (hertz, seconds), which steps by its travel instead.
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
    // The whole of it takes a drag, its name and reading as well as its
    // dial, as the prototype's knobs do.
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
          // Its value, double-clicked: typed in.
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

/// DeviceKnob is the Chain's knob for an editor outside this file (the
/// Instrument's, say): dragged up to turn it right, double-clicked to put it
/// back to [initial]; [log] spreads its travel as hertz and seconds want.
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

  /// menu is its right-click's choices, and modulated whether something
  /// moves it (a pink ring), as a device's own knobs have; own whether the
  /// copies edited have their own value (see _Knob.own).
  final List<(String, VoidCallback)> menu;
  final bool modulated;
  final bool own;

  /// automated is whether keys move it: the dot by its name.
  final bool automated;

  /// step: see _Knob.step.
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
  // In thousands: "k", or kilohertz.
  if (rest.startsWith("k")) v *= 1000;
  // A share the knob shows in percent -- 1 shown as "100%" -- takes a
  // number typed as a percent. Told by what it shows against its value,
  // where it can be: "How far" goes to 300%, past the old test of a most of
  // 2, so 100 typed was read as 100 times and held to 300% (Ken,
  // 2026-11-12). A knob already in percent units ("50%" for 50) is not.
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

/// _shownNumber is the number a knob's reading shows, or null.
double? _shownNumber(String shown) {
  var m = RegExp(r"-?\d*\.?\d+")
      .firstMatch(shown.replaceAll("\u2212", "-").replaceAll(",", "."));
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// shownStep is the least change a knob's reading [shown] can show, in
/// the value's own terms -- 1% of a share shown in percent is 0.01, "1.25×"
/// a hundredth -- where the reading is the value times a power of ten;
/// null where it is not (decibels from a gain, say) or cannot be told.
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

/// _VuNeedle is the gain-reduction meter: a needle at rest on the right,
/// swinging left as the compressor takes level off, thirty decibels across.
class _VuNeedle extends CustomPainter {
  final double reduction;
  _VuNeedle(this.reduction);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    // Across the top: from thirty decibels down on the left to none, the
    // pivot just under the bottom edge, as on a VU meter.
    const swing = 0.8; // radians either side of upright
    var radius = math.min(h * 0.78, (w / 2 - 26) / math.sin(swing));
    var pivot = Offset(w / 2, h - 6 + radius * 0.08);
    double angle(double db) =>
        -math.pi / 2 - swing + (1 - (db / 30).clamp(0.0, 1.0)) * 2 * swing;
    var arc = Rect.fromCircle(center: pivot, radius: radius);
    canvas.drawArc(
        arc,
        angle(30),
        2 * swing,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _faceInk);
    canvas.drawArc(
        arc.deflate(-4),
        angle(30),
        angle(20) - angle(30),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFC0392B));
    for (var db in const [0, 2, 4, 6, 8, 10, 15, 20, 30]) {
      var a = angle(db.toDouble());
      var dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          pivot + dir * radius,
          pivot + dir * (radius + 7),
          Paint()
            ..strokeWidth = 1.2
            ..color = _faceInk);
      var tp =
          paintedLabel("$db", const TextStyle(fontSize: 10, color: _faceInk));
      tp.paint(canvas,
          pivot + dir * (radius + 16) - Offset(tp.width / 2, tp.height / 2));
    }
    var tp = paintedLabel("GAIN REDUCTION  dB",
        const TextStyle(fontSize: 9, letterSpacing: 1, color: _faceDim));
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, pivot.dy - radius * 0.45));
    var a = angle(reduction);
    canvas.drawLine(
        pivot,
        pivot + Offset(math.cos(a), math.sin(a)) * (radius + 4),
        Paint()
          ..strokeWidth = 1.8
          ..color = const Color(0xFF1A1A1A));
  }

  @override
  bool shouldRepaint(_VuNeedle old) => old.reduction != reduction;
}

/// _TransferCurve is what goes in along the bottom against what comes out up
/// the side: the diagonal is no compressor at all.
class _TransferCurve extends CustomPainter {
  final Dynamics comp;
  final double input;

  /// line, grid and dim are its colours: on a cream face by default, or the
  /// Chain's dark display.
  final Color line, grid, dim;
  _TransferCurve(this.comp, this.input,
      {this.line = _faceInk,
      this.grid = const Color(0xFFD3C7A4),
      this.dim = _faceDim});

  static const _lo = -60.0;

  @override
  void paint(Canvas canvas, Size size) {
    var pad = 14.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    double px(double db) => pad + (db - _lo) / -_lo * w;
    double py(double db) => pad + h - ((db - _lo) / -_lo).clamp(0.0, 1.0) * h;
    var grid = Paint()..color = this.grid;
    for (var db = -48.0; db <= 0; db += 12) {
      canvas.drawLine(Offset(px(db), pad), Offset(px(db), pad + h), grid);
      canvas.drawLine(Offset(pad, py(db)), Offset(pad + w, py(db)), grid);
    }
    canvas.drawLine(Offset(px(_lo), py(_lo)), Offset(px(0), py(0)),
        Paint()..color = const Color(0xFFB5A77F));
    canvas.drawLine(
        Offset(px(comp.threshold), pad),
        Offset(px(comp.threshold), pad + h),
        Paint()..color = const Color(0xFFC0392B));
    var path = Path();
    for (var i = 0; i <= 120; i++) {
      var db = _lo + i / 120 * -_lo;
      var out = comp.reducedDb(db) + comp.totalMakeupDb;
      var p = Offset(px(db), py(out));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = comp.on ? line : dim);
    if (input > _lo) {
      var out = comp.on ? comp.reducedDb(input) + comp.totalMakeupDb : input;
      canvas.drawCircle(Offset(px(input), py(out)), 5,
          Paint()..color = const Color(0xFFE08A1E));
    }
  }

  @override
  bool shouldRepaint(_TransferCurve old) =>
      old.input != input ||
      !identical(old.comp, comp);
}

/// _LedMeter is a level meter of lit segments: green, then amber, then red
/// in the top six decibels.
class _LedMeter extends CustomPainter {
  final double db;
  _LedMeter(this.db);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = const Color(0xFF2B2F36));
    const segments = 30;
    var gap = 1.5;
    var seg = (size.height - 4 - gap * (segments - 1)) / segments;
    var lit = ((db + 60) / 60 * segments).clamp(0, segments).floor();
    for (var i = 0; i < segments; i++) {
      var level = -60 + (i + 1) * 2.0;
      var colour = level > -6
          ? const Color(0xFFE5484D)
          : level > -18
              ? const Color(0xFFF2C94C)
              : const Color(0xFF52C26A);
      var y = size.height - 2 - (i + 1) * seg - i * gap;
      canvas.drawRect(Rect.fromLTWH(3, y, size.width - 6, seg),
          Paint()..color = i < lit ? colour : colour.withValues(alpha: 0.12));
    }
  }

  @override
  bool shouldRepaint(_LedMeter old) => old.db != db;
}

/// _MiniCurve is a folded EQ: its curve, small.
class _MiniCurve extends CustomPainter {
  final Eq eq;
  _MiniCurve(this.eq);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
        Paint()..color = const Color(0xFF16273B));
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2),
        Paint()..color = const Color(0xFF3A5272));
    var shown = eq.copyWith(on: true);
    // Turned on its side, as the folded device is tall: low at the bottom,
    // a lift to the right.
    var p = Path();
    for (var i = 0; i <= 60; i++) {
      var y = h - i / 60 * h;
      var f = 20 * math.pow(1000, i / 60).toDouble();
      var x = w / 2 + shown.responseDb(f).clamp(-12.0, 12.0) / 12 * (w / 2 - 3);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = eq.on ? const Color(0xFFE6F2FF) : _eqDim);
  }

  @override
  bool shouldRepaint(_MiniCurve old) =>
      !identical(old.eq, eq);
}

/// _ReductionBar is gain reduction as a bar falling from the top: twenty
/// decibels fills it.
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

// ---- Meters and the limiter

/// MeterDevice is a strip's level as it leaves -- the channel's after its
/// fader, or the master's, which is what is heard -- each side with its
/// held peak and the loudest it has been.
class MeterDevice extends StatefulWidget {
  static const width = 180.0;
  final CanvasController controller;
  final String? channel;
  final String id;
  final String title;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const MeterDevice(
      {required this.controller,
      required this.channel,
      required this.id,
      required this.title,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<MeterDevice> createState() => _MeterDeviceState();
}

class _MeterDeviceState extends State<MeterDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;
  (double, double) _now = (-90, -90);
  (double, double) _held = (-90, -90);

  /// _loudest is the highest peak since it was last cleared, per side.
  (double, double) _loudest = (-90, -90);

  @override
  void tick() {
    var (l, r) = strip.levels;
    _now = (gainToDb(l), gainToDb(r));
    _held = (
      math.max(_now.$1, _held.$1 - 0.66),
      math.max(_now.$2, _held.$2 - 0.66),
    );
    _loudest = (
      math.max(_now.$1, _loudest.$1),
      math.max(_now.$2, _loudest.$2),
    );
  }

  String _db(double v) => v > -60 ? v.toStringAsFixed(1) : "−∞";

  @override
  Widget build(BuildContext context) {
    Widget pair(double width) =>
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var (i, (side, db))
              in [("L", _now.$1), ("R", _now.$2)].indexed) ...[
            // A gap between the two, not after them: folded, they fill
            // the fold's 26 exactly.
            if (i > 0) const SizedBox(width: 4),
            SizedBox(
              width: width,
              child: CustomPaint(
                  key: ValueKey("meter$side-${widget.id}"),
                  size: Size.infinite,
                  painter: _LedMeter(db)),
            ),
          ],
        ]);
    var clipped = _loudest.$1 > -0.1 || _loudest.$2 > -0.1;
    return DeviceFrame(
      id: widget.id,
      title: widget.title,
      skin: DeviceSkin.navy,
      folded: widget.folded,
      onFold: widget.onFold,
      width: MeterDevice.width,
      height: widget.height,
      foldedBody: pair(11),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: [
          // The loudest yet, red where it touched the top; a click clears
          // it.
          GestureDetector(
            key: ValueKey("meterLoudest-${widget.id}"),
            onTap: () => setState(() => _loudest = (-90, -90)),
            child: Tooltip(
              message: "The loudest peak so far: click to clear",
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: clipped
                      ? const Color(0xFFE5484D)
                      : const Color(0xFF132233),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("${_db(_loudest.$1)}  ${_db(_loudest.$2)}",
                    style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: _eqInk)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: pair(20)),
              // The scale, top to bottom.
              SizedBox(
                width: 26,
                child: CustomPaint(painter: _MeterScale()),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text("${_db(_held.$1)}  ${_db(_held.$2)} dB",
              style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: _eqDim)),
        ]),
      ),
    );
  }
}

/// _MeterScale is the decibel marks beside a _LedMeter, which runs from -60
/// at the bottom to 0 at the top.
class _MeterScale extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var db in const [0, -6, -12, -18, -24, -36, -48, -60]) {
      var y = 2 + (-db / 60) * (size.height - 4);
      var tp = paintedLabel("$db", const TextStyle(fontSize: 9, color: _eqDim));
      tp.paint(canvas, Offset(size.width - tp.width, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MeterScale old) => false;
}

/// LimiterDevice is the master's limiter, last in its chain, as the chain
/// prototype has it (Ken, 2026-11-08): its screen the turn-down it has made
/// lately against its ceiling, its Ceiling, Release and Look-ahead, and
/// the delay its look-ahead adds on its bar.
class LimiterDevice extends StatefulWidget {
  static const width = 280.0;
  final CanvasController controller;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  /// reductionDb is how far it is turning the sound down now, in dB (zero
  /// or less).
  final double reductionDb;
  const LimiterDevice(
      {required this.controller,
      required this.folded,
      required this.onFold,
      required this.height,
      this.reductionDb = 0,
      super.key});

  @override
  State<LimiterDevice> createState() => _LimiterDeviceState();
}

class _LimiterDeviceState extends State<LimiterDevice> {
  /// _history is the turn-down at each of the last readings, oldest first.
  final List<double> _history = [];

  /// _reduction is the turn-down read now: none where nothing has been
  /// read (silence reads as minus infinity, not as all the way down).
  double get _reduction => widget.reductionDb.isFinite
      ? widget.reductionDb.clamp(-24.0, 0.0)
      : 0.0;

  @override
  void didUpdateWidget(LimiterDevice old) {
    super.didUpdateWidget(old);
    _history.add(_reduction);
    if (_history.length > 160) _history.removeAt(0);
  }

  void _write(MasterMix m, {bool transient = false}) {
    var c = widget.controller;
    c.beginInteraction();
    c.setMasterMix(m, transient: true);
    if (!transient) c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var m = c.document.masterMix;
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var (icon, accent) = deviceGroupLook(DeviceGroup.dynamics);
    var reading = "${m.ceilingDb.toStringAsFixed(1)} dBTP";
    return DeviceFrame(
      id: "limiter",
      title: "Limiter",
      skin: skin,
      icon: icon,
      accent: accent,
      help: "Last in the chain: no peak gets past its ceiling, in playing or "
          "in an export. It looks ahead, so it turns down before a peak "
          "arrives -- which delays everything by that much -- and lets go "
          "over its release.",
      on: m.limiter,
      powerKey: const ValueKey("limitOn"),
      onPower: (v) => _write(m.copyWith(limiter: v)),
      onReset: () => _write(m.copyWith(
          ceilingDb: -1, limiterAheadMs: 5, limiterReleaseMs: 50)),
      onAB: () => widget.controller.toggleABOf(
          "$mixerMasterKey|limiter",
          (m.ceilingDb, m.limiterAheadMs, m.limiterReleaseMs),
          (o) {
        var (ceiling, ahead, release) = o as (double, double, double);
        _write(
            widget.controller.document.masterMix.copyWith(
                ceilingDb: ceiling,
                limiterAheadMs: ahead,
                limiterReleaseMs: release),
            transient: true);
      }),
      showingB: widget.controller.showingBOf("$mixerMasterKey|limiter"),
      folded: widget.folded,
      onFold: widget.onFold,
      width: LimiterDevice.width,
      height: widget.height,
      besideDisplay: 200,
      besideSettings: 180,
      // Its look-ahead delays the whole mix by as much.
      barExtras: [
        // How far it is holding the mix down now.
        if (_reduction > 0.05 && widget.controller.chainBadges)
          _ReadingBadge(
              key: const ValueKey("gainBadge-limiter"),
              text: "−${_reduction.toStringAsFixed(1)}"),
        _StripPresetPicker(
          key: const ValueKey("stripPreset-limiter"),
          label: StripPart.limiter.label,
                kept: () => _stripKept(StripPart.limiter),
          name: c.presetNameOf(mixerMasterKey, "limiter"),
          builtIn: [
            for (var (n, v) in limiterPresets)
              (
                n,
                {
                  "ceiling": v.ceilingDb,
                  "ahead": v.aheadMs,
                  "release": v.releaseMs
                }
              ),
          ],
          onPick: (name, value) {
            _write(m.copyWith(
                ceilingDb: (value["ceiling"] as num?)?.toDouble(),
                limiterAheadMs: (value["ahead"] as num?)?.toDouble(),
                limiterReleaseMs: (value["release"] as num?)?.toDouble()));
            c.setPresetName(mixerMasterKey, "limiter", name);
          },
          onDefault: () {
            _write(m.copyWith(
                ceilingDb: -1, limiterAheadMs: 5, limiterReleaseMs: 50));
            c.setPresetName(mixerMasterKey, "limiter", null);
          },
          onSave: () => saveStripPreset(context, StripPart.limiter, {
            "ceiling": m.ceilingDb,
            "ahead": m.limiterAheadMs,
            "release": m.limiterReleaseMs,
          }),
        ),
        Container(
          key: const ValueKey("limitLatency"),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: look.studio.edge)),
          child: Text("${m.limiterAheadMs.toStringAsFixed(1)} ms",
              style: TextStyle(fontSize: 9.5, color: look.studio.muted)),
        ),
      ],
      summary: "$reading · ${_reduction.toStringAsFixed(1)} dB",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        for (var (key, label, text, value, min, max, initial, log, set) in [
          (
            "limitCeiling",
            "Ceiling",
            reading,
            m.ceilingDb,
            -12.0,
            0.0,
            -1.0,
            false,
            (double v) =>
                m.copyWith(ceilingDb: (v * 10).roundToDouble() / 10)
          ),
          (
            "limitRelease",
            "Release",
            "${m.limiterReleaseMs.round()} ms",
            m.limiterReleaseMs,
            5.0,
            1000.0,
            50.0,
            true,
            (double v) => m.copyWith(limiterReleaseMs: v.roundToDouble())
          ),
          (
            "limitAhead",
            "Look-ahead",
            "${m.limiterAheadMs.toStringAsFixed(1)} ms",
            m.limiterAheadMs,
            0.5,
            20.0,
            5.0,
            true,
            (double v) =>
                m.copyWith(limiterAheadMs: (v * 10).roundToDouble() / 10)
          ),
        ])
          _Knob(
            key: ValueKey(key),
            label: label,
            text: text,
            value: value,
            initial: initial,
            range: _Range(min, max, log: log),
            size: switch (tier) {
              DeviceTier.large => 46,
              DeviceTier.medium => 38,
              _ => 30,
            },
            accent: accent,
            ink: skin.ink,
            onChanged: (v, {transient = false}) =>
                _write(set(v), transient: transient),
            onCommit: c.endInteraction,
          ),
      ],
      display: CustomPaint(
        key: const ValueKey("limitScreen"),
        painter: _LimitHistory(
            List.of(_history), m.ceilingDb, accent, look.studio),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _LimitHistory is the limiter's turn-down over the last readings, down
/// from the top (none) to twelve decibels, and its ceiling written.
class _LimitHistory extends CustomPainter {
  final List<double> history;
  final double ceiling;
  final Color accent;
  final StudioColors studio;
  _LimitHistory(this.history, this.ceiling, this.accent, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var grid = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var db = 3; db < 12; db += 3) {
      var y = size.height * db / 12;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), grid);
    }
    if (history.isNotEmpty) {
      var step = size.width / math.max(1, 159);
      var x0 = size.width - (history.length - 1) * step;
      var path = Path()..moveTo(x0, 0);
      for (var (i, db) in history.indexed) {
        var y = size.height * (-db).clamp(0.0, 12.0) / 12;
        path.lineTo(x0 + i * step, y);
      }
      path
        ..lineTo(size.width, 0)
        ..close();
      canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.35));
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2),
        Paint()..color = const Color(0xFFE5534B));
    var now = history.isEmpty ? 0.0 : history.last;
    var tp = paintedLabel(
        "ceiling ${ceiling.toStringAsFixed(1)} dB · "
        "${now < -0.05 ? "down ${(-now).toStringAsFixed(1)} dB" : "not turning down"}",
        TextStyle(fontSize: 10, color: studio.muted),
        maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_LimitHistory old) => true;
}

// ---- Ducking

/// DuckDevice is a channel turning the others down while it is heard -- see
/// Ducking -- as a unit beside the compressor: the shape of the dip on its
/// screen, how far the others are down now, knobs for the depth and the
/// times, and which channels it ducks.
class DuckDevice extends StatefulWidget {
  static const width = 600.0;
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const DuckDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<DuckDevice> createState() => _DuckDeviceState();
}

class _DuckDeviceState extends State<DuckDevice>
    with SingleTickerProviderStateMixin, _Metered {
  // Made again each time: the card may be given another strip.
  _Strip get strip => _Strip(widget.controller, widget.channel);

  @override
  CanvasController get meteredBy => widget.controller;

  /// _now is how far, in decibels, the channels it ducks are down at the
  /// playhead.
  double _now = 0;

  List<TimelineChannel> get _others => [
        for (var c in widget.controller.timelineChannels)
          if (c.key != widget.channel) c,
      ];

  @override
  void tick() {
    var c = widget.controller;
    var duck = strip.gone ? const Ducking() : strip.duck;
    var ducked = _others
        .where((o) => !duck.except.contains(o.key))
        .map((o) => o.key)
        .firstOrNull;
    var env = ducked == null ? null : c.duckEnvelopeOf(ducked);
    var rate = math.max(1, c.document.frameRate);
    _now = env == null || !duck.on
        ? 0
        : -gainToDb(envelopeAt(env, c.runFrame / rate)).clamp(-60.0, 0.0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (strip.gone) return const SizedBox.shrink();
          var duck = strip.duck;
          void write(Ducking d, {bool transient = false}) =>
              strip.writeDuck(d, transient: transient);
          return DeviceFrame(
            id: "duck",
            title: "Ducker",
            actions: [
              if (widget.controller.canRemovePart(widget.channel, stripDuck))
                IconButton(
                  key: const ValueKey("deviceRemove-duck"),
                  tooltip: "Take the Ducker out",
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      widget.controller.removePart(widget.channel, stripDuck),
                ),
            ],
            skin: DeviceSkin.silver,
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            help: "Turns the other channels down while this one plays -- a "
                "voice over music -- by Depth, easing down and back.",
            on: duck.on,
            powerKey: const ValueKey("duckOn"),
            onPower: (v) => write(duck.copyWith(on: v)),
            onAB: () => widget.controller.toggleABOf(
                "${widget.channel}|duck",
                duck,
                (o) => write(o as Ducking, transient: true)),
            showingB: widget.controller.showingBOf("${widget.channel}|duck"),
            onReset: () => write(Ducking(on: duck.on, except: duck.except)),
            barExtras: [
              // How far it is turning the others down now.
              if (_now > 0.05 && widget.controller.chainBadges)
                _ReadingBadge(
                    key: const ValueKey("gainBadge-duck"),
                    text: "−${_now.toStringAsFixed(1)}"),
              _StripPresetPicker(
                key: const ValueKey("stripPreset-duck"),
                label: StripPart.duck.label,
                kept: () => _stripKept(StripPart.duck),
                name: widget.controller
                    .presetNameOf(widget.channel, "duck"),
                builtIn: [for (var (n, v) in duckPresets) (n, v.toJson())],
                onPick: (name, value) {
                  // Its own list of who is not turned down is kept.
                  write(Ducking.fromJson(value).copyWith(except: duck.except));
                  widget.controller
                      .setPresetName(widget.channel, "duck", name);
                },
                onDefault: () {
                  write(Ducking(on: duck.on, except: duck.except));
                  widget.controller
                      .setPresetName(widget.channel, "duck", null);
                },
                onSave: () =>
                    saveStripPreset(context, StripPart.duck, duck.toJson()),
              ),
            ],
            folded: widget.folded,
            onFold: widget.onFold,
            width: DuckDevice.width,
            height: widget.height,
            foldedBody: Column(children: [
              const Text("Duck",
                  style: TextStyle(fontSize: 10, color: _silverDim)),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                    key: const ValueKey("duckFolded"),
                    size: const Size(14, double.infinity),
                    painter: _ReductionBar(_now)),
              ),
              const SizedBox(height: 4),
              Text(duck.on ? "${duck.depthDb.round()}" : "off",
                  style: const TextStyle(fontSize: 10, color: _silverInk)),
            ]),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 280, child: _screen(duck, write)),
                    const SizedBox(width: 10),
                    // How far the others are down now.
                    _NowMeter(barKey: const ValueKey("duckNow"), now: _now),
                    const SizedBox(width: 12),
                    Expanded(child: _controls(duck, write)),
                  ]),
            ),
          );
        },
      );

  /// _segment is one of the card's choices, as the Chain's chips: the one
  /// picked filled in the accent, the rest outlined on the dark card.
  Widget _segment(String label, bool on, Key key, VoidCallback onTap) {
    var look = MixerLook.of(context);
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: on ? look.colors.primary : look.studio.inset,
          borderRadius: BorderRadius.circular(5),
          border:
              Border.all(color: on ? look.colors.primary : look.studio.edge),
        ),
        child: Text(label,
            maxLines: 1,
            style: TextStyle(
                fontSize: 11,
                color: on ? look.colors.onPrimary : look.studio.text)),
      ),
    );
  }

  /// _screen is the dip drawn on the cream screen, and under it its shape.
  Widget _screen(
          Ducking duck, void Function(Ducking, {bool transient}) write) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF8D8F93), width: 2),
            ),
            child: CustomPaint(
                key: const ValueKey("duckShape"),
                painter: _DuckShape(duck, strip.name)),
          ),
        ),
        const SizedBox(height: 8),
        const Text("Shape",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _silverDim)),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.center, runSpacing: 4, children: [
          for (var c in DuckCurve.values)
            _segment(c.label, duck.curve == c, ValueKey("duckCurve-${c.name}"),
                () => write(duck.copyWith(curve: c))),
        ]),
      ]);

  Widget _controls(
      Ducking duck, void Function(Ducking, {bool transient}) write) {
    Widget knob(String label, String key, double value, double initial,
            _Range range, String text, Ducking Function(double) apply) =>
        _Knob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initial,
          range: range,
          size: 56,
          onChanged: (v, {transient = false}) =>
              write(apply(v), transient: transient),
          onCommit: strip.commit,
        );
    var others = _others;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        knob(
            "Depth",
            "duckDepth",
            duck.depthDb,
            -10,
            const _Range(-40, -1),
            "${duck.depthDb.toStringAsFixed(1)} dB",
            (v) => duck.copyWith(depthDb: (v * 2).roundToDouble() / 2)),
        knob(
            "Down",
            "duckAttack",
            duck.attack,
            0.3,
            const _Range(0, 2),
            "${duck.attack.toStringAsFixed(2)} s",
            (v) => duck.copyWith(attack: (v * 100).roundToDouble() / 100)),
        knob(
            "Back",
            "duckRelease",
            duck.release,
            0.8,
            const _Range(0, 4),
            "${duck.release.toStringAsFixed(2)} s",
            (v) => duck.copyWith(release: (v * 100).roundToDouble() / 100)),
      ]),
      const SizedBox(height: 10),
      Text(
          others.isEmpty
              ? "No other channels to duck"
              : "Ducks, while ${strip.name} is heard:",
          style: const TextStyle(fontSize: 10, color: _silverDim)),
      const SizedBox(height: 4),
      Expanded(
        child: SingleChildScrollView(
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            // Lit is ducked; a click leaves it alone.
            for (var o in others)
              _segment(
                  o.name,
                  !duck.except.contains(o.key),
                  ValueKey("duckExcept-${o.key}"),
                  () => write(duck.copyWith(except: [
                        for (var k in duck.except)
                          if (k != o.key) k,
                        if (!duck.except.contains(o.key)) o.key,
                      ]))),
          ]),
        ),
      ),
    ]);
  }
}

/// _NowMeter is how far the ducked channels are down now: a bar, under a
/// label that never wraps, over the reading -- in dB while it is ducking,
/// and nothing when it is not.
class _NowMeter extends StatelessWidget {
  final Key barKey;
  final double now;
  const _NowMeter({required this.barKey, required this.now});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        child: Column(children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text("Now",
                maxLines: 1, style: TextStyle(fontSize: 10, color: _silverDim)),
          ),
          const SizedBox(height: 4),
          Expanded(
              child: CustomPaint(
                  key: barKey,
                  size: Size.infinite,
                  painter: _ReductionBar(now))),
          const SizedBox(height: 4),
          SizedBox(
            height: 13,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(now > 0.05 ? "−${now.toStringAsFixed(1)} dB" : "",
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 9,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: _silverInk)),
            ),
          ),
        ]),
      );
}

/// DuckedDevice is the Ducker as the channel it turns down sees it: first in
/// its chain, as the dip is made to its sounds as they come in. Which voices
/// duck it, the dips drawn across the run with the playhead, how far down it
/// is now, and its switch -- off leaves this channel alone. The dip's
/// settings belong to the voice, for every channel it ducks (see Ducking),
/// so the knobs here turn the voice's, and say so.
///
/// The dips are worked out ahead from the voice's recordings, so they lead
/// each line rather than chase it.
class DuckedDevice extends StatefulWidget {
  static const width = 460.0;
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const DuckedDevice(
      {required this.controller,
      required this.channel,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<DuckedDevice> createState() => _DuckedDeviceState();
}

class _DuckedDeviceState extends State<DuckedDevice>
    with SingleTickerProviderStateMixin, _Metered {
  @override
  CanvasController get meteredBy => widget.controller;

  /// _now is how far, in decibels, the channel is down at the playhead.
  double _now = 0;

  @override
  void tick() {
    var c = widget.controller;
    var env = c.duckEnvelopeOf(widget.channel);
    var rate = math.max(1, c.document.frameRate);
    _now = env == null
        ? 0
        : -gainToDb(envelopeAt(env, c.runFrame / rate)).clamp(-60.0, 0.0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          var c = widget.controller;
          var by = c.duckersOf(widget.channel);
          if (by.isEmpty) return const SizedBox.shrink();
          var on = by.any((v) => !v.mix.duck.except.contains(widget.channel));
          var names = by.map((v) => v.name).join(", ");
          var rate = math.max(1, c.document.frameRate);
          return DeviceFrame(
            id: "ducked",
            title: "Ducker",
            actions: [
              IconButton(
                key: const ValueKey("deviceRemove-ducked"),
                tooltip: "Take it out: this channel is not ducked",
                icon: const Icon(Icons.close),
                onPressed: () => c.removePart(widget.channel, stripDucked),
              ),
            ],
            skin: DeviceSkin.silver,
            icon: deviceGroupLook(DeviceGroup.dynamics).$1,
            accent: deviceGroupLook(DeviceGroup.dynamics).$2,
            help: "This channel is turned down while the ones that duck it "
                "play: worked out ahead, as the sounds come in.",
            on: on,
            powerKey: const ValueKey("duckedOn"),
            onPower: (v) => c.setDuckedBy(widget.channel, v),
            folded: widget.folded,
            onFold: widget.onFold,
            width: DuckedDevice.width,
            height: widget.height,
            foldedBody: Column(children: [
              const Text("Duck",
                  style: TextStyle(fontSize: 10, color: _silverDim)),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                    key: const ValueKey("duckedFolded"),
                    size: const Size(14, double.infinity),
                    painter: _ReductionBar(_now)),
              ),
            ]),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("By $names, ahead of each line",
                        key: const ValueKey("duckedBy"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: _silverInk)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _cream,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF8D8F93), width: 2),
                                ),
                                child: CustomPaint(
                                    key: const ValueKey("duckedDips"),
                                    painter: _RunDips(
                                        on
                                            ? c.duckEnvelopeOf(
                                                    widget.channel) ??
                                                const []
                                            : const [],
                                        c.document.playFrames / rate,
                                        c.runFrame / rate)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _NowMeter(
                                barKey: const ValueKey("duckedNow"), now: _now),
                          ]),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (var v in by)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            key: ValueKey("duckedOpen-${v.key}"),
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: _silverInk),
                            onPressed: () =>
                                c.openEffects(v.key, device: "duck"),
                            child: Text(
                                "${v.name}: ${v.mix.duck.depthDb.toStringAsFixed(1)} dB",
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ]),
                  ]),
            ),
          );
        },
      );
}

/// _RunDips is a channel's ducking over the whole run: how far down it is,
/// forty decibels down the screen, with the playhead.
class _RunDips extends CustomPainter {
  final List<GainPoint> env;
  final double total, now;
  _RunDips(this.env, this.total, this.now);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    if (w <= 0 || h <= 0 || total <= 0) return;
    double x(double t) => pad + (t / total).clamp(0.0, 1.0) * w;
    double y(double gain) => pad + (-gainToDb(gain).clamp(-40.0, 0.0) / 40) * h;
    var grid = Paint()..color = const Color(0xFFD3C7A4);
    for (var db = 0.0; db >= -40; db -= 10) {
      var gy = pad + -db / 40 * h;
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), grid);
    }
    var path = Path()..moveTo(x(0), y(env.isEmpty ? 1 : env.first.gain));
    for (var p in env) {
      path.lineTo(x(p.time), y(p.gain));
    }
    path.lineTo(x(total), y(env.isEmpty ? 1 : env.last.gain));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = _faceInk);
    canvas.drawLine(Offset(x(now), pad), Offset(x(now), pad + h),
        Paint()..color = const Color(0xFFE08A1E));
  }

  @override
  bool shouldRepaint(_RunDips old) =>
      old.now != now || old.total != total || !identical(old.env, env);
}

/// _DuckShape is one dip: the others at full level, down by the depth over
/// the attack in the chosen shape, held while the channel is heard, and back
/// over the release.
class _DuckShape extends CustomPainter {
  final Ducking duck;
  final String name;
  _DuckShape(this.duck, this.name);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    var w = size.width - 2 * pad, h = size.height - 2 * pad;
    // Forty decibels down the screen; time along it, the held part a fixed
    // second and a half so the ramps read at their own lengths.
    double y(double gain) => pad + (-gainToDb(gain).clamp(-40.0, 0.0) / 40) * h;
    const hold = 1.5;
    var lead = 0.4;
    var total = lead + duck.attack + hold + duck.release + lead;
    double x(double t) => pad + t / total * w;
    var grid = Paint()..color = const Color(0xFFD3C7A4);
    for (var db = 0.0; db >= -40; db -= 10) {
      var gy = pad + -db / 40 * h;
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), grid);
    }
    // When the channel listened for is heard.
    var from = lead + duck.attack, to = from + hold;
    canvas.drawRect(Rect.fromLTRB(x(from), pad, x(to), pad + h),
        Paint()..color = const Color(0xFFE08A1E).withValues(alpha: 0.18));
    var tp = paintedLabel(name, const TextStyle(fontSize: 9, color: _faceDim),
        maxWidth: x(to) - x(from) - 4);
    tp.paint(canvas, Offset(x(from) + 2, pad + h - tp.height - 2));
    var env = duckEnvelope([(from, to)],
        gain: dbToGain(duck.depthDb),
        attack: duck.attack,
        release: duck.release,
        curve: duck.curve);
    var path = Path()..moveTo(x(0), y(1));
    for (var p in env) {
      path.lineTo(x(p.time), y(p.gain));
    }
    path.lineTo(x(total), y(1));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = duck.on ? _faceInk : _faceDim);
  }

  @override
  bool shouldRepaint(_DuckShape old) =>
      old.name != name ||
      !identical(old.duck, duck);
}

/// ParamDevice is a device in a return's chain, drawn from its kind's table
/// of settings: a knob for each, its switch, and a way to take it out. A
/// reverb or a delay -- and whatever device is added to the table next.
class ParamDevice extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip the device is on: a return's id, or a channel's
  /// key -- see CanvasController.devicesOf.
  final String owner;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const ParamDevice({
    required this.controller,
    required this.owner,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  /// _autoTuneWidth is the Auto-tune's card: room for its twelve keys.
  static const double _autoTuneWidth = 330;

  /// _range is how a knob turns for [p]: times and frequencies on a log
  /// scale, everything else in a straight line.
  static _Range _range(DeviceParam p) {
    var log = p.unit == "Hz" || p.unit == "ms";
    return _Range(log && p.min <= 0 ? 1 : p.min, p.max, log: log);
  }

  @override
  Widget build(BuildContext context) {
    var devices = controller.devicesOf(owner);
    if (index >= devices.length) return const SizedBox();
    var device = devices[index];
    void write(MixDevice next, {bool transient = false}) {
      var now = controller.devicesOf(owner);
      if (index >= now.length) return;
      controller.beginInteraction();
      controller.setDevicesOf(owner, [...now]..[index] = next, transient: true);
      if (!transient) controller.endInteraction();
    }

    var params = device.kind.params;
    var columns = (params.length + 1) ~/ 2;
    // Which of its knobs a lane moves, and which a hand is holding.
    var lane =
        controller.timelineChannels.where((c) => c.key == owner).firstOrNull;
    var automated = {
      for (var l in lane?.mix.automation ?? const <AutomationLane>[])
        if (l.points.isNotEmpty) l.target
    };
    var held = controller.overridden[owner] ?? const <String>{};
    // Which of its knobs an LFO in the chain moves.
    var moved = {
      for (var d in devices)
        if (d.on && d.kind.modulates)
          for (var m in d.mods)
            if (m.device == deviceIdAt(devices, index)) m.param,
    };
    // Right-click: move it with a modulator of the chain.
    void moveWith(int j, ModTarget t) {
      var now = controller.devicesOf(owner);
      if (j >= now.length) return;
      var m = now[j];
      if (m.mods.any((x) =>
          x.device == t.device && x.param == t.param && x.from == t.from)) {
        return;
      }
      controller.beginInteraction();
      controller.setDevicesOf(
          owner, [...now]..[j] = m.withMods([...m.mods, t]));
      controller.endInteraction();
    }

    List<(String, VoidCallback)> modMenu(DeviceParam p) {
      var me = deviceIdAt(devices, index);
      return [
        for (var (j, m) in devices.indexed)
          if (j != index && m.kind.modulates)
            if (m.kind == DeviceKind.macro)
              for (var k = 0; k < macroKnobs; k++)
                (
                  "Turn with ${m.kind.label} ${j + 1}'s M${k + 1}",
                  () => moveWith(j, ModTarget(me, p.id, 0.5, k))
                )
            else
              (
                "Move with ${m.kind.label} ${j + 1}",
                () => moveWith(j, ModTarget(me, p.id))
              ),
      ];
    }

    String target(DeviceParam p) => AutomationTarget.deviceSetting(
            deviceIdAt(devices, index), device.kind, p.id)
        .id;
    // A knob's lane, and a controller's knob learnt for it, as the
    // prototype's right-click.
    List<(String, VoidCallback)> knobMenu(DeviceParam p) {
      var me = deviceIdAt(devices, index);
      // What the prototype's knob menu has on every strip: an LFO of its
      // own, a macro's knob, and back where it began.
      var anyStrip = <(String, VoidCallback)>[
        if (!device.kind.modulates && !p.isChoice) ...[
          (
            "Move it with a new LFO",
            () {
              controller.beginInteraction();
              controller.setDevicesOf(
                  owner,
                  withDeviceIds([
                    ...controller.devicesOf(owner),
                    const MixDevice(DeviceKind.lfo)
                        .withMods([ModTarget(me, p.id)]),
                  ]));
              controller.endInteraction();
            }
          ),
          (
            "Add it to a macro",
            () {
              var now = controller.devicesOf(owner);
              var at = now.indexWhere((d) => d.kind == DeviceKind.macro);
              var macro = at >= 0 ? now[at] : const MixDevice(DeviceKind.macro);
              // Its first knob turning nothing yet -- or the first.
              var used = {for (var m in macro.mods) m.from};
              var k = [for (var k = 0; k < macroKnobs; k++) k]
                      .where((k) => !used.contains(k))
                      .firstOrNull ??
                  0;
              var next =
                  macro.withMods([...macro.mods, ModTarget(me, p.id, 0.5, k)]);
              controller.beginInteraction();
              controller.setDevicesOf(
                  owner,
                  withDeviceIds(
                      at >= 0 ? ([...now]..[at] = next) : [...now, next]));
              controller.endInteraction();
            }
          ),
        ],
        ("Reset", () => write(device.withValue(p.id, p.initial))),
      ];
      if (lane == null) return anyStrip;
      var t = target(p);
      var cc = controller.controlOf(owner, t);
      var laned =
          controller.automationLaneOf(lane, t)?.points.isNotEmpty ?? false;
      return [
        ("Show its automation lane", () => controller.showLaneFor(owner, t)),
        if (!laned)
          (
            "Automate it",
            () {
              // A lane begun where it is now, and shown to be drawn on.
              controller.beginInteraction();
              controller.setAutomationPoints(
                  lane, t, [(0.0, device.value(p.id))],
                  transient: true);
              controller.endInteraction();
              controller.showLaneFor(owner, t);
            }
          ),
        if (controller.overridden[owner]?.contains(t) ?? false)
          (
            "Back to its automation",
            () => controller.backToAutomationFor(owner, t)
          ),
        ...anyStrip,
        if (cc != null)
          (
            "Forget the controller (CC $cc)",
            () => controller.forgetControl(owner, t)
          )
        else
          (
            "Learn a controller: turn one of its knobs next",
            () => controller.learnControl(owner, t)
          ),
      ];
    }

    var (icon, accent) = deviceGroupLook(device.kind.group);
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var autoTune = device.kind == DeviceKind.autoTune;
    // Tall, with its text at size, Notes to MIDI is a button at its foot,
    // as the prototype's; shorter, or its text larger, an icon on its bar,
    // leaving its screen the room.
    var roomy = DeviceTier.of(height) == DeviceTier.large &&
        MediaQuery.textScalerOf(context).scale(10) <= 12;
    // Auto-tune's notes made a MIDI channel, as the prototype's foot.
    void notesToMidi() {
      var why = controller.notesToMidi(owner,
          root: device.value("key").round(), steps: autoTuneSteps(device));
      try {
        var snack = SnackBarModel.of(context);
        why == null
            ? snack.success("Its notes are on a new MIDI channel")
            : snack.error(why);
      } catch (_) {}
    }

    // A setting that is one of a few -- a filter's type, an LFO's shape --
    // is a list, not a knob: the prototype's dropdowns.
    bool listed(DeviceParam p) =>
        paramShown(device, p) &&
        device.kind != DeviceKind.split &&
        device.kind != DeviceKind.macro &&
        !(autoTune && (p.id == "key" || p.id == "scale"));
    // Its own knobs, then the Out trim at its foot if it has one.
    var turned = [
      ...params,
      if (device.kind.hasOut) deviceExtras.firstWhere((p) => p.id == "out"),
    ];
    List<Widget> knobs(DeviceTier tier) => [
          for (var p in turned)
            if (listed(p) && !p.isChoice)
              _Knob(
                key: ValueKey("device-$index-${p.id}"),
                automated: automated.contains(target(p)),
                held: held.contains(target(p)),
                modulated: moved.contains(p.id),
                menu: [
                  if (!device.kind.modulates) ...modMenu(p),
                  ...knobMenu(p),
                ],
                label: p.label,
                text: p.reading(device.value(p.id)),
                value: device.value(p.id),
                initial: p.initial,
                range: _range(p),
                size: switch (tier) {
                  DeviceTier.large => 46,
                  DeviceTier.medium => 38,
                  _ => 28,
                },
                reading: tier != DeviceTier.small,
                accent: accent,
                ink: skin.ink,
                bipolar: p.min < 0 && p.max > 0,
                onChanged: (v, {transient = false}) =>
                    write(device.withValue(p.id, v), transient: transient),
                onCommit: controller.endInteraction,
              ),
          if (params.any((p) => listed(p) && p.isChoice))
            DevicePack(key: ValueKey("deviceChoices-$index"), children: [
              for (var p in params)
                if (listed(p) && p.isChoice)
                  StudioDrop<int>(
                    key: ValueKey("device-$index-${p.id}"),
                    label: p.label,
                    value: device
                        .value(p.id)
                        .round()
                        .clamp(0, p.choices.length - 1),
                    options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                    onChanged: (i) =>
                        write(device.withValue(p.id, i.toDouble())),
                  ),
            ]),
          // Short, its knobs only, as the prototype's.
          // Medium, or its text large, its key and scale as lists on one
          // row; tall, as the prototype's rows of buttons.
          if (autoTune && tier != DeviceTier.small) ...[
            if (tier == DeviceTier.medium ||
                MediaQuery.textScalerOf(context).scale(10) > 12)
              AutoTuneKeyScaleRow(
                  key: ValueKey("autoTuneKeyScaleRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (param, v) =>
                      write(device.withValue(param, v.toDouble())))
            else ...[
              AutoTuneKey(
                  key: ValueKey("autoTuneKeyRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (k) => write(device.withValue("key", k.toDouble()))),
              AutoTuneScale(
                  key: ValueKey("autoTuneScaleRow-$index"),
                  device: device,
                  index: index,
                  width: _autoTuneWidth - 16,
                  onPick: (k) =>
                      write(device.withValue("scale", k.toDouble()))),
            ],
            if (roomy && controller.pitchElementOf(owner) != null)
              SizedBox(
                width: _autoTuneWidth - 16,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    key: ValueKey("menu-autoTuneToMidi-$index"),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11)),
                    onPressed: notesToMidi,
                    child: const Text("Notes to MIDI"),
                  ),
                ),
              ),
          ],
          if (device.kind == DeviceKind.vocoder &&
              device.value("carrier").round() == carrierFromChannel)
            _sourceChannel(context, device, write),
          // A split's branches, each its own chain.
          if (device.kind == DeviceKind.split)
            SplitBranches(
              key: ValueKey("splitBranches-$index"),
              device: device,
              // Its branches' knobs a modulator of the chain moves.
              moved: {
                for (var d in devices)
                  if (d.on && d.kind.modulates)
                    for (var m in d.mods)
                      if (branchDevicePath(m.device)
                          case (var split, var b, var id)
                          when split == deviceIdAt(devices, index))
                        "$b/$id/${m.param}",
              },
              ink: skin.ink,
              accent: accent,
              onChanged: (branches, {transient = false}) =>
                  write(device.withBranches(branches), transient: transient),
              onSet: (param, v, {transient = false}) =>
                  write(device.withValue(param, v), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // A macro's knobs set at random, and its settings kept as
          // variations to come back to, as the prototype's Macros.
          if (device.kind == DeviceKind.macro)
            MacroPanel(
              key: ValueKey("macroPanel-$index"),
              index: index,
              device: device,
              knobs: [
                // The instrument's own: its envelope, cutoff and glide.
                if (controller.instrumentChannel(owner))
                  for (var k in instrumentKnobs)
                    (instrumentTarget, k.id, "Instrument · ${k.label}"),
                for (var (i, d) in devices.indexed)
                  if (i != index && !d.kind.modulates)
                    for (var p in d.kind.params)
                      if (!p.isChoice)
                        (
                          deviceIdAt(devices, i),
                          p.id,
                          "${d.kind.label} · ${p.label}"
                        ),
              ],
              accent: accent,
              ink: skin.ink,
              onChanged: (next, {transient = false}) =>
                  write(next, transient: transient),
              onCommit: controller.endInteraction,
            ),
          if (device.kind == DeviceKind.macro)
            _MacroTools(
              key: ValueKey("macroTools-$index"),
              index: index,
              device: device,
              look: MixerLook.of(context),
              onChanged: (next) {
                write(next, transient: true);
                controller.endInteraction();
              },
            ),
          // What a modulator moves: any knob of the chain's other devices.
          // A macro's are its panel's.
          if (device.kind.modulates && device.kind != DeviceKind.macro)
            ModTargets(
              key: ValueKey("modTargets-$index"),
              mods: device.mods,
              sources: device.kind == DeviceKind.macro
                  ? [for (var i = 1; i <= macroKnobs; i++) "M$i"]
                  : const [],
              knobs: [
                for (var (i, d) in devices.indexed)
                  if (i != index && !d.kind.modulates) ...[
                    for (var p in d.kind.params)
                      if (!p.isChoice)
                        (
                          deviceIdAt(devices, i),
                          p.id,
                          "${d.kind.label} · ${p.label}"
                        ),
                    // And the knobs of a split's branches' devices.
                    for (var (b, branch) in d.branches.indexed)
                      for (var (j, x) in branch.devices.indexed)
                        for (var p in x.kind.params)
                          if (!p.isChoice)
                            (
                              branchDeviceId(deviceIdAt(devices, i), b,
                                  deviceIdAt(branch.devices, j)),
                              p.id,
                              "${splitBranchNames(d.value("mode").round(), d.branches.length).elementAtOrNull(b) ?? "Branch"}"
                                  " · ${x.kind.label} · ${p.label}"
                            ),
                  ],
              ],
              ink: skin.ink,
              onChanged: (mods, {transient = false}) =>
                  write(device.withMods(mods), transient: transient),
              onCommit: controller.endInteraction,
            ),
          // A gate opens to its own sound, or to another channel's; a
          // follower follows one or the other.
          if (device.kind == DeviceKind.gate ||
              device.kind == DeviceKind.follower)
            _sourceChannel(context, device, write, itself: true),
        ];
    var hooks =
        freezeHooks(context, controller, owner, deviceIdAt(devices, index));
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, index)),
      title: device.kind.label,
      help: deviceAbout(device.kind),
      frozen: hooks.frozen,
      onFreeze: hooks.onFreeze,
      onUnfreeze: hooks.onUnfreeze,
      onDuplicate: () => duplicateDevice(controller, owner, index),
      onReset: () => resetDevice(controller, owner, index),
      onSavePreset: () =>
          saveDevicePreset(context, device.kind.label, devices: [device]),
      onAB: device.kind.params.isEmpty ||
              device.kind == DeviceKind.macro ||
              device.kind == DeviceKind.split
          ? null
          : () => controller.toggleAB(owner, deviceIdAt(devices, index)),
      barExtras: [
        // What it does to the level, on any strip: a channel's, the
        // master's, a scene's bus or a return.
        _GainBadge(
              key: ValueKey("gainBadge-$index"),
              controller: controller,
              channel: owner,
              id: deviceIdAt(devices, index)),
        if (device.kind != DeviceKind.macro && device.kind != DeviceKind.split)
          _PresetPicker(
            key: ValueKey("devicePreset-$index"),
            kind: device.kind,
            name: controller.presetNameOf(owner, deviceIdAt(devices, index)),
            onPick: (name, preset) {
              var next = device;
              for (var p in [...device.kind.params, ...deviceExtras]) {
                next = next.withValue(p.id, preset.value(p.id));
              }
              write(next);
              controller.setPresetName(
                  owner, deviceIdAt(devices, index), name);
            },
            onDefault: () {
              resetDevice(controller, owner, index);
              controller.setPresetName(owner, deviceIdAt(devices, index), null);
            },
            onSave: () =>
                saveDevicePreset(context, device.kind.label, devices: [device]),
          ),
      ],
      extraMenu: (look) => [
        // A drive's harmonics kept from folding back down.
        if (device.kind.oversamples)
          SubmenuButton(
            key: ValueKey("deviceOversample-$index"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              for (var (k, label) in const [
                (1, "Off"),
                (2, "×2"),
                (4, "×4"),
              ])
                chainMenuItem(look,
                    key: ValueKey("deviceOversample-$index-$k"),
                    text: label,
                    hint: k == 1 ? null : "cleaner, a little more work",
                    current: (device.value("oversample").round() >= 3
                            ? 4
                            : device.value("oversample").round()) ==
                        k,
                    onPressed: () =>
                        write(device.withValue("oversample", k.toDouble()))),
            ],
            child: Text(
                "Oversample: ${device.value("oversample").round() <= 1 ? "off" : "×${device.value("oversample").round() >= 3 ? 4 : 2}"}"),
          ),
        // Only the middle of the sound, or only its sides.
        if (device.kind.worksOnSides)
          worksOnMenu(look,
              id: "deviceStereo-$index",
              value: device.value("stereo").round(),
              onPick: (k) => write(device.withValue("stereo", k.toDouble()))),
        // What it listens to beside its own sound.
        if (device.kind == DeviceKind.gate ||
            device.kind == DeviceKind.follower ||
            (device.kind == DeviceKind.vocoder &&
                device.value("carrier").round() == carrierFromChannel))
          SubmenuButton(
            key: ValueKey("deviceListens-$index"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              if (device.kind != DeviceKind.vocoder)
                chainMenuItem(look,
                    key: ValueKey("deviceListens-$index-itself"),
                    text: "Itself",
                    current: device.source.isEmpty,
                    onPressed: () => write(device.withSource(""))),
              for (var ch in controller.timelineChannels)
                if (ch.key != owner)
                  chainMenuItem(look,
                      key: ValueKey("deviceListens-$index-${ch.key}"),
                      text: ch.name,
                      current: device.source == ch.key,
                      onPressed: () => write(device.withSource(ch.key))),
            ],
            child: const Text("Listens to (sidechain)"),
          ),
      ],
      showingB: controller.showingB(owner, deviceIdAt(devices, index)),
      skin: skin,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-$index"),
      folded: folded,
      onFold: onFold,
      // A split's branches side by side, a column each.
      width: device.kind == DeviceKind.split
          ? SplitBranches.width
          : device.kind == DeviceKind.macro
              ? MacroPanel.width
              : autoTune
              ? _autoTuneWidth
              : math.max(240.0, 24.0 + 72 * columns),
      height: height,
      actions: [
        // Auto-tune's notes: in the Pitch editor, or made a MIDI channel.
        if (autoTune)
          Tooltip(
            message: "How far behind it puts what it hears",
            child: Text("${autoTuneLatencyMs.round()} ms",
                key: ValueKey("autoTuneLatency-$index"),
                style: TextStyle(
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: skin.ink.withValues(alpha: 0.7))),
          ),
        if (autoTune && !roomy && controller.pitchElementOf(owner) != null)
          IconButton(
            key: ValueKey("menu-autoTuneToMidi-$index"),
            tooltip: "Notes to MIDI",
            icon: const Icon(Icons.piano),
            onPressed: notesToMidi,
          ),
        if (autoTune && controller.pitchElementOf(owner) != null)
          IconButton(
            key: ValueKey("autoTunePitch-$index"),
            tooltip: "Open its notes in the Pitch editor",
            icon: const Icon(Icons.open_in_new),
            onPressed: () => controller.showPitch(owner),
          ),
        ...deviceMoveButtons(controller, owner, index, _headerInkLight),
        IconButton(
          key: ValueKey("deviceRemove-$index"),
          tooltip: "Take the ${device.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () {
            var now = controller.devicesOf(owner);
            if (index >= now.length) return;
            controller.beginInteraction();
            controller.setDevicesOf(owner, [...now]..removeAt(index));
            controller.endInteraction();
          },
        ),
      ],
      // Folded, its level as it leaves it, at its foot.
      foldedBody: _FoldedLevel(
          key: ValueKey("foldedLevel-$index"),
          controller: controller,
          owner: owner,
          at: controller.chainOf(owner).indexOf(deviceIdAt(devices, index)) +
              1),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: knobs(DeviceTier.large),
        ),
      ),
      // Laid out for its height: its levels over its knobs.
      controls: knobs,
      // A split's branches are its picture: they have the room.
      display: device.kind == DeviceKind.split ||
              device.kind == DeviceKind.macro
          ? null
          : autoTune
              ? AutoTuneScreen(
                  key: ValueKey("autoTuneScreen-$index"),
                  controller: controller,
                  owner: owner,
                  device: device,
                  index: index)
              : DeviceLevels(
                  key: ValueKey("deviceLevels-$index"),
                  controller: controller,
                  deviceId: deviceIdAt(devices, index),
                  // Measured on any strip: a channel's, a return's, the
                  // master's or a scene's bus.
                  channel: owner,
                  // Its place in the chain, where its levels are read: the EQ and
                  // compressor can be before it.
                  index: controller
                      .chainOf(owner)
                      .indexOf(deviceIdAt(devices, index)),
                  device: device,
                  accent: accent,
                  back: look.studio.display),
      summary: [
        for (var p in params.where((p) => paramShown(device, p)).take(2))
          "${p.label} ${p.reading(device.value(p.id))}"
      ].join(" · "),
      icon: icon,
      accent: accent,
    );
  }

  /// _sourceChannel is which channel a device listens to beside its own:
  /// a vocoder's carrier -- an instrument playing the chords, muted so only
  /// the vocoder is heard -- or, with [itself], a gate's key, where "" is
  /// its own sound.
  Widget _sourceChannel(
      BuildContext context, MixDevice device, void Function(MixDevice) write,
      {bool itself = false}) {
    var look = MixerLook.of(context);
    var channels = [
      for (var c in controller.timelineChannels)
        if (c.key != owner) c,
    ];
    var chosen = channels.any((c) => c.key == device.source)
        ? device.source
        : itself
            ? ""
            : null;
    var ink = TextStyle(fontSize: 11, color: look.studio.text);
    return SizedBox(
      width: 104,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("From", style: ink.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          key: ValueKey("deviceSource-$index"),
          isExpanded: true,
          isDense: true,
          value: chosen,
          style: ink,
          iconEnabledColor: look.studio.text,
          dropdownColor: look.colors.surfaceContainerHigh,
          hint: Text(channels.isEmpty ? "No other channel" : "A channel",
              style: ink, overflow: TextOverflow.ellipsis),
          items: [
            if (itself)
              DropdownMenuItem(
                  value: "",
                  child: Text("Itself",
                      style: TextStyle(
                          fontSize: 11, color: look.colors.onSurface))),
            for (var c in channels)
              DropdownMenuItem(
                  value: c.key,
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: look.colors.onSurface))),
          ],
          selectedItemBuilder: (_) => [
            if (itself) Text("Itself", style: ink),
            for (var c in channels)
              Text(c.name, overflow: TextOverflow.ellipsis, style: ink),
          ],
          onChanged: channels.isEmpty && !itself
              ? null
              : (v) {
                  if (v != null) write(device.withSource(v));
                },
        ),
      ]),
    );
  }
}

/// AddDeviceSlot puts a device on strip [owner], after its others: the
/// prototype's "+" at the chain's end, opening every kind of device by its
/// family.
class AddDeviceSlot extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip it adds to: see CanvasController.devicesOf.
  final String owner;
  final double height;

  const AddDeviceSlot(
      {required this.controller,
      required this.owner,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    // A sound's channel can be given a generator: Speech, which makes its
    // clips. A MIDI channel has its instrument; a bus, a video's sound or
    // one with speech already, none.
    var lane =
        controller.timelineChannels.where((l) => l.key == owner).firstOrNull;
    var canSpeak = lane != null &&
        !lane.video &&
        !controller.instrumentChannel(owner) &&
        controller.speechOf(owner) == null;
    devicePresets.load();
    return ListenableBuilder(
      listenable: devicePresets,
      builder: (context, _) => AddSlot(
        id: "addDeviceOpen",
        title: "Add a device",
        height: height,
        groups: [
          // Kept with Save as a preset: a device, or a whole chain.
          if (devicePresets.presets.where((p) => presetHolds(p)) case var kept
              when kept.isNotEmpty)
            (
              "Presets",
              [
                for (var p in kept)
                  (
                    "addPreset-${p.id}",
                    p.name,
                    () => useDevicePreset(controller, owner, p.data),
                  ),
              ]
            ),
          // The strip's own parts taken out, to put back.
          if ([
            for (var part in removableParts)
              if (controller.partRemoved(owner, part)) part
          ]
              case var gone when gone.isNotEmpty)
            (
              "Channel strip",
              [
                for (var part in gone)
                  (
                    "addPart-$part",
                    switch (part) {
                      chainEq => "EQ",
                      chainComp => "Compressor",
                      stripDucked => "Ducked by others",
                      _ => "Ducker",
                    },
                    () => controller.restorePart(owner, part),
                  ),
              ]
            ),
          // A voice can be sung: the Vocaliser, among its effects.
          if (lane != null &&
              controller.speechOf(owner) != null &&
              controller.vocaliserOf(owner) == null)
            (
              "Voice",
              [
                (
                  "addDevice-vocaliser",
                  "Vocaliser",
                  () {
                    controller.beginInteraction();
                    controller.setVocaliser(owner, const VocaliserSpec());
                    controller.endInteraction();
                    controller.openEffects(owner, device: "vocaliser");
                  }
                ),
              ]
            ),
          if (canSpeak)
            (
              "Generators",
              [
                (
                  "addDevice-speech",
                  "Speech",
                  () {
                    controller.beginInteraction();
                    controller.setSpeech(owner, const SpeechSpec());
                    controller.endInteraction();
                    controller.showSpeech(owner);
                  }
                ),
              ]
            ),
          for (var group in DeviceGroup.values)
            (
              group.label,
              [
                for (var kind in DeviceKind.values)
                  if (kind.group == group)
                    (
                      "addDevice-${kind.name}",
                      kind.label,
                      () {
                        var now = controller.devicesOf(owner);
                        controller.beginInteraction();
                        controller
                            .setDevicesOf(owner, [...now, MixDevice(kind)]);
                        controller.endInteraction();
                        controller.openEffects(owner,
                            device: deviceKey(deviceIdAt(
                                controller.devicesOf(owner), now.length)));
                      }
                    ),
              ]
            ),
        ],
      ),
    );
  }
}

/// AddSlot is the chain's "+", as the prototype draws it: a slim dashed slot
/// that, pressed, opens what can be added -- a search, and each family's
/// kinds in columns.
class AddSlot extends StatelessWidget {
  /// id keys the slot itself; each item is keyed by its own key.
  final String id;
  final String title;
  final double height;

  /// groups are each family's name and its items: a key, a name, and what
  /// picking it does.
  final List<(String, List<(String, String, VoidCallback)>)> groups;

  const AddSlot(
      {required this.id,
      required this.title,
      required this.height,
      required this.groups,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return MenuAnchor(
      builder: (context, menu, _) => Tooltip(
        message: title,
        child: InkWell(
          key: ValueKey(id),
          borderRadius: BorderRadius.circular(8),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: SizedBox(
            width: 30,
            height: height,
            child: CustomPaint(
              painter: _DashedSlot(look.studio.edge),
              child: Center(
                child: Icon(Icons.add, size: 16, color: look.studio.muted),
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Builder(
          builder: (context) => _AddPanel(
            title: title,
            groups: groups,
            onPicked: () => MenuController.maybeOf(context)?.close(),
          ),
        ),
      ],
    );
  }
}

/// _DashedSlot draws the "+" slot's dashed outline.
class _DashedSlot extends CustomPainter {
  final Color colour;
  _DashedSlot(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    var r = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(3), const Radius.circular(8));
    var paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlot old) => old.colour != colour;
}

/// _AddPanel is what the "+" opens: a search over every kind, and the kinds
/// by family, four families to a row.
class _AddPanel extends StatefulWidget {
  final String title;
  final List<(String, List<(String, String, VoidCallback)>)> groups;
  final VoidCallback onPicked;
  const _AddPanel(
      {required this.title, required this.groups, required this.onPicked});

  @override
  State<_AddPanel> createState() => _AddPanelState();
}

class _AddPanelState extends State<_AddPanel> {
  String _q = "";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var q = _q.toLowerCase();
    var shown = [
      for (var (family, items) in widget.groups)
        (
          family,
          [
            for (var item in items)
              if (q.isEmpty ||
                  item.$2.toLowerCase().contains(q) ||
                  family.toLowerCase().contains(q))
                item
          ]
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    var columns = math.min(4, math.max(1, shown.length));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 150.0 * columns + 8 * (columns - 1),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 30,
                child: TextField(
                  key: const ValueKey("addSlotSearch"),
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        "Find ${widget.title.toLowerCase().replaceFirst("add ", "")}",
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (var (family, items) in shown)
                  SizedBox(
                    width: 150,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                            child: Text(family.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w500,
                                    color: look.studio.muted)),
                          ),
                          for (var (key, label, pick) in items)
                            InkWell(
                              key: ValueKey(key),
                              borderRadius: BorderRadius.circular(5),
                              onTap: () {
                                widget.onPicked();
                                pick();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: Text(label,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                        ]),
                  ),
              ]),
            ]),
      ),
    );
  }
}
