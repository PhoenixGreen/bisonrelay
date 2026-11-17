part of 'mixer_plugins.dart';

// The compressor, the master's limiter and the level meter, with the VU needle,
// transfer curve, LED meter and limiter history they draw. Part of
// mixer_plugins.dart.

/// CompDevice is a strip's compressor; the master's glue has no [channel].
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

  /// _needleShown shows the gain-reduction needle, not the transfer curve.
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

  /// _display is the compressor's screen: its curve or a gain-reduction
  /// needle, switched in its corner, with the reduction read along its foot.
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

  /// line, grid and dim are its colours, for a cream face or a dark display.
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

/// _LedMeter is a level meter of lit segments, red in the top 6 dB.
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

/// MeterDevice is a strip's level as it leaves (a channel's after its fader,
/// the master's as heard), each side with its held peak and loudest yet.
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
          // The loudest yet, red where it touched the top; a click clears it.
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

/// _MeterScale is the dB marks beside a _LedMeter (-60 bottom, 0 top).
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

/// LimiterDevice is the master's limiter, last in its chain: its recent
/// turn-down against its ceiling, its knobs, and its look-ahead's delay.
class LimiterDevice extends StatefulWidget {
  static const width = 280.0;
  final CanvasController controller;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  /// reductionDb is how far it turns the sound down now, in dB (<= 0).
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
