part of 'mixer_plugins.dart';

// The Ducker: the channel turning the others down, and the same device as each
// channel it turns down sees it, with their dip pictures and meters. Part of
// mixer_plugins.dart.

/// DuckDevice is a channel turning the others down while it is heard (see
/// Ducking): the dip's shape, the others' level now, and its settings.
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

  /// _now is how far down, in dB, the ducked channels are at the playhead.
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
                    _NowMeter(barKey: const ValueKey("duckNow"), now: _now),
                    const SizedBox(width: 12),
                    Expanded(child: _controls(duck, write)),
                  ]),
            ),
          );
        },
      );

  /// _segment is one of the card's choices as a chip, the picked one filled.
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

/// _NowMeter is how far the ducked channels are down now: a bar under a
/// never-wrapping label, over its reading in dB (empty when not ducking).
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

/// DuckedDevice is the Ducker as the channel it turns down sees it, first in
/// its chain so the dip meets its sounds as they come in. The dip's settings
/// belong to the voice (see Ducking), so its knobs turn the voice's; off
/// leaves this channel alone. The dips are worked out ahead from the voice's
/// recordings, so they lead each line rather than chase it.
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
