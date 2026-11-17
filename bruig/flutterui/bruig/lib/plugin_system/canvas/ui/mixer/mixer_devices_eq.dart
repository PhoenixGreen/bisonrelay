part of 'mixer_plugins.dart';

// The Channel EQ device: its bands and their colours, the band icons, the
// response graph, and the small curve shown when it folds. Part of
// mixer_plugins.dart.

/// eqBandColour is each band's colour, red (lowest) to magenta, as in Logic.
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

/// EqDevice is a strip's Channel EQ; the master's has no [channel].
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

  /// _bandKnobs are the picked band's frequency, gain and Q, and the output.
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

  /// _bandButtons are a chip per band, to pick it and switch it on or off.
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

  /// _handle is [slot]'s handle: a cut's on its curve, the rest at gain.
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

  /// _moveTo drags the handle to [at]: across is frequency, up is gain.
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
        // Set by a press and a drag only: a wheel or trackpad scroll over it
        // scrolls the chain. A band's Q is its knob.
        return GestureDetector(
          key: const ValueKey("eqCurve"),
          supportedDevices: dragPointers,
          // The handle is chosen where the press lands, not where the drag
          // is recognised: in the sideways-scrolling chain that is past it.
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
    // The analyzer: what plays after the EQ, its floor 60 dB under its peak.
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
    // On its side, as the folded device is tall: low at the bottom.
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
