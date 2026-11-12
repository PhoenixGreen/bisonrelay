part of 'mixer_plugins.dart';

// mixer_listeners.dart is the devices that only listen: a tuner, a spectrum: part of mixer_plugins.dart, split from it to keep
// that file readable (Ken, 2026-11-12). Its imports are the library's.

// ---- The devices that only listen: a tuner, a spectrum

/// ListenerDevice is a Tuner or a Spectrum on strip [owner]: what it hears,
/// drawn a few times a second, changing nothing.
class ListenerDevice extends StatefulWidget {
  final CanvasController controller;
  final String owner;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const ListenerDevice({
    required this.controller,
    required this.owner,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  State<ListenerDevice> createState() => _ListenerDeviceState();
}

class _ListenerDeviceState extends State<ListenerDevice>
    with SingleTickerProviderStateMixin, _Metered {
  /// _history is a Spectrum's spectrogram: its spectra, oldest first, one
  /// taken each tick while it is shown.
  final List<Float32List> _history = [];
  static const int _historyLength = 240;

  // What it shows is read in build: a tick only asks for it again -- and a
  // spectrogram keeps what it heard.
  @override
  void tick() {
    var c = widget.controller;
    var devices = c.devicesOf(widget.owner);
    if (widget.index >= devices.length) return;
    var device = devices[widget.index];
    if (device.kind != DeviceKind.spectrum || device.value("view") < 0.5) {
      return;
    }
    var bins = c.spectrum(widget.owner == mixerMasterKey ? null : widget.owner);
    // Kept while there is sound: played, a clip launched, or keys pressed.
    if (bins == null || !_loud) return;
    _history.add(Float32List.fromList(bins));
    if (_history.length > _historyLength) _history.removeAt(0);
  }

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var devices = c.devicesOf(widget.owner);
    if (widget.index >= devices.length) return const SizedBox();
    var device = devices[widget.index];
    var tuner = device.kind == DeviceKind.tuner;
    var look = MixerLook.of(context);
    var studio = look.studio;
    Widget body;
    String summary = "Listening";
    if (tuner) {
      var heard = c.pitch(widget.owner);
      String note = "–", reading = "Listening…";
      double cents = 0;
      if (heard != null && heard.clarity > 0.5) {
        var midi = 69 + 12 * math.log(heard.hz / 440) / math.ln2;
        var nearest = midi.round();
        cents = (midi - nearest) * 100;
        note = "${const [
          "C",
          "C♯",
          "D",
          "E♭",
          "E",
          "F",
          "F♯",
          "G",
          "A♭",
          "A",
          "B♭",
          "B"
        ][nearest % 12]}"
            "${nearest ~/ 12 - 1}";
        reading = "${heard.hz.toStringAsFixed(1)} Hz · "
            "${cents >= 0 ? "+" : ""}${cents.round()} cents";
      }
      summary = note == "–"
          ? "Listening"
          : "$note ${cents >= 0 ? "+" : "−"}${cents.abs().round()} cents";
      // The note as big as the screen has room for, its needle and its
      // reading under it while there is room for them.
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: LayoutBuilder(builder: (context, box) {
          var roomy = box.maxHeight > 110;
          return Column(children: [
            Expanded(
              child: FittedBox(
                // Smaller where the screen is short; never bigger.
                fit: BoxFit.scaleDown,
                child: Text(note,
                    key: const ValueKey("tunerNote"),
                    style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: cents.abs() < 5 && note != "–"
                            ? studio.meterLow
                            : studio.text)),
              ),
            ),
            SizedBox(
              height: roomy ? 34 : 18,
              width: double.infinity,
              child: CustomPaint(painter: _TunerPainter(cents, studio)),
            ),
            if (roomy) ...[
              const SizedBox(height: 6),
              Text(reading,
                  key: const ValueKey("tunerReading"),
                  style: TextStyle(fontSize: 12, color: studio.muted)),
            ],
          ]);
        }),
      );
    } else if (device.kind == DeviceKind.scope) {
      var wave = c.wave(DeviceKind.scope, widget.owner);
      summary = "${device.value("time").round()} ms";
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("scopeView"),
          size: Size.infinite,
          painter: _ScopePainter(wave, device.value("zoom"), studio),
        ),
      );
    } else if (device.kind == DeviceKind.stereoImage) {
      var wave = c.wave(DeviceKind.stereoImage, widget.owner);
      var r = wave == null ? 0.0 : correlation(wave);
      summary =
          "correlation ${r >= 0 ? "+" : "−"}${r.abs().toStringAsFixed(2)}";
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Expanded(
            child: CustomPaint(
              key: const ValueKey("stereoImageView"),
              size: Size.infinite,
              painter: _GoniometerPainter(wave, studio),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            width: double.infinity,
            child: CustomPaint(
                key: const ValueKey("correlationBar"),
                painter: _CorrelationPainter(r, studio)),
          ),
          Text(summary,
              key: const ValueKey("correlationReading"),
              style: TextStyle(fontSize: 11, color: studio.muted)),
        ]),
      );
    } else if (device.kind == DeviceKind.loudness) {
      var heard = c.loudness(widget.owner);
      var target = device.value("target");
      String lufs(double v) =>
          v.isFinite ? "${v < 0 ? "−" : ""}${v.abs().toStringAsFixed(1)}" : "–";
      summary = heard == null || !heard.shortTerm.isFinite
          ? "Listening"
          : "${lufs(heard.shortTerm)} LUFS";
      Widget row(String key, String label, String value) => Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: studio.muted)),
            ),
            Text(value,
                key: ValueKey(key),
                style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: studio.text)),
          ]);
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: LayoutBuilder(builder: (context, box) {
          return SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(heard == null ? "–" : lufs(heard.shortTerm),
                        key: const ValueKey("loudnessShortTerm"),
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: studio.text)),
                  ),
                  Text("LUFS short-term · aim ${target.round()}",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: studio.muted)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 10,
                    child: CustomPaint(
                        painter: _LoudnessBarPainter(
                            heard?.shortTerm ?? -double.infinity,
                            target,
                            studio)),
                  ),
                  const SizedBox(height: 6),
                  row("loudnessMomentary", "Momentary",
                      heard == null ? "–" : lufs(heard.momentary)),
                  row("loudnessIntegrated", "Whole, since reset",
                      heard == null ? "–" : lufs(heard.integrated)),
                  row(
                      "loudnessTruePeak",
                      "True peak",
                      heard == null || !heard.truePeak.isFinite
                          ? "–"
                          : "${lufs(heard.truePeak)} dBTP"),
                ]),
          );
        }),
      );
    } else if (device.value("view") >= 0.5) {
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("spectrogramView"),
          size: Size.infinite,
          painter: _SpectrogramPainter(_history, _history.length),
        ),
      );
    } else {
      body = Container(
        color: studio.display,
        padding: const EdgeInsets.all(6),
        child: CustomPaint(
          key: const ValueKey("spectrumView"),
          size: Size.infinite,
          painter: _SpectrumPainter(
              c.spectrum(widget.owner == mixerMasterKey ? null : widget.owner),
              studio),
        ),
      );
    }
    void write(MixDevice next) {
      var now = c.devicesOf(widget.owner);
      if (widget.index >= now.length) return;
      c.beginInteraction();
      c.setDevicesOf(widget.owner, [...now]..[widget.index] = next);
      c.endInteraction();
    }

    var (icon, accent) = deviceGroupLook(device.kind.group);
    var skin = DeviceSkin.studio(studio);
    var hooks = freezeHooks(
        context, c, widget.owner, deviceIdAt(devices, widget.index));
    return DeviceFrame(
      id: deviceKey(deviceIdAt(devices, widget.index)),
      title: device.kind.label,
      help: deviceAbout(device.kind),
      frozen: hooks.frozen,
      onFreeze: hooks.onFreeze,
      onUnfreeze: hooks.onUnfreeze,
      onDuplicate: () => duplicateDevice(c, widget.owner, widget.index),
      onReset: () => resetDevice(c, widget.owner, widget.index),
      onSavePreset: () =>
          saveDevicePreset(context, device.kind.label, devices: [device]),
      skin: skin,
      // Its screen is all of it, and its few settings: it only listens.
      display: body,
      controls: (tier) => [
        for (var p in device.kind.params)
          if (!p.isChoice)
            _Knob(
              key: ValueKey("device-${widget.index}-${p.id}"),
              label: p.label,
              text: p.reading(device.value(p.id)),
              value: device.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: tier == DeviceTier.large ? 38 : 28,
              reading: tier != DeviceTier.small,
              accent: accent,
              ink: skin.ink,
              onChanged: (v, {transient = false}) {
                var now = c.devicesOf(widget.owner);
                if (widget.index >= now.length) return;
                c.beginInteraction();
                c.setDevicesOf(widget.owner,
                    [...now]..[widget.index] = device.withValue(p.id, v),
                    transient: true);
                if (!transient) c.endInteraction();
              },
              onCommit: c.endInteraction,
            ),
      ],
      summary: summary,
      icon: icon,
      accent: accent,
      on: device.on,
      onPower: (v) => write(device.switched(v)),
      powerKey: ValueKey("devicePower-${widget.index}"),
      folded: widget.folded,
      onFold: widget.onFold,
      width: switch (device.kind) {
        DeviceKind.tuner => 220,
        DeviceKind.stereoImage || DeviceKind.loudness => 290,
        _ => 360,
      },
      height: widget.height,
      actions: [
        // A Spectrum shown as it is now, or over time; a Loudness started
        // again.
        if (device.kind == DeviceKind.spectrum)
          IconButton(
            key: ValueKey("spectrumView-${widget.index}"),
            tooltip: device.value("view") >= 0.5
                ? "Show the spectrum as it is now"
                : "Show it over time: a spectrogram",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(
                device.value("view") >= 0.5
                    ? Icons.show_chart
                    : Icons.view_week_outlined,
                color: skin.ink),
            onPressed: () {
              _history.clear();
              write(device.withValue(
                  "view", device.value("view") >= 0.5 ? 0 : 1));
            },
          ),
        if (device.kind == DeviceKind.loudness)
          IconButton(
            key: ValueKey("loudnessReset-${widget.index}"),
            tooltip: "Start measuring again",
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.restart_alt, color: skin.ink),
            onPressed: () => c.resetLoudness(widget.owner),
          ),
        ...deviceMoveButtons(c, widget.owner, widget.index, skin.ink),
        IconButton(
          key: ValueKey("deviceRemove-${widget.index}"),
          tooltip: "Take the ${device.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: skin.ink),
          onPressed: () {
            var now = c.devicesOf(widget.owner);
            if (widget.index >= now.length) return;
            c.beginInteraction();
            c.setDevicesOf(widget.owner, [...now]..removeAt(widget.index));
            c.endInteraction();
          },
        ),
      ],
      foldedBody: const SizedBox(),
      body: body,
    );
  }
}

/// _TunerPainter is the tuner's needle: fifty cents flat to fifty sharp,
/// in tune in the middle.
class _TunerPainter extends CustomPainter {
  final double cents;
  final StudioColors studio;
  _TunerPainter(this.cents, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.width / 2;
    var line = Paint()
      ..color = _eqDim
      ..strokeWidth = 1;
    for (var c = -50; c <= 50; c += 10) {
      var x = mid + c / 50 * (size.width / 2 - 6);
      canvas.drawLine(Offset(x, size.height * (c == 0 ? 0.1 : 0.35)),
          Offset(x, size.height * 0.65), line);
    }
    var x = mid + cents.clamp(-50, 50) / 50 * (size.width / 2 - 6);
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = cents.abs() < 5 ? studio.meterLow : studio.meterMid);
  }

  @override
  bool shouldRepaint(_TunerPainter old) => old.cents != cents;
}

/// _ScopePainter is a sound's wave over the Scope's time: left and right
/// over each other, [zoom] times as tall.
class _ScopePainter extends CustomPainter {
  final Wave? wave;
  final double zoom;
  final StudioColors studio;
  _ScopePainter(this.wave, this.zoom, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = studio.muted.withValues(alpha: 0.3));
    var w = wave;
    if (w == null || w.$1.isEmpty) return;
    for (var (side, colour) in [
      (w.$2, studio.meterMid.withValues(alpha: 0.7)),
      (w.$1, studio.meterLow),
    ]) {
      var path = Path();
      for (var i = 0; i < side.length; i++) {
        var x = i / math.max(1, side.length - 1) * size.width;
        var y = mid - (side[i] * zoom).clamp(-1.0, 1.0) * (mid - 2);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }
  }

  @override
  bool shouldRepaint(_ScopePainter old) => true;
}

/// _GoniometerPainter draws left against right as a goniometer does: the
/// middle (both alike) straight up, the sides (left less right) across, so
/// mono is a vertical line and a wide sound a cloud.
class _GoniometerPainter extends CustomPainter {
  final Wave? wave;
  final StudioColors studio;
  _GoniometerPainter(this.wave, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = math.min(size.width, size.height) / 2 - 4;
    var guide = Paint()
      ..color = studio.muted.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), guide);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), guide);
    var d = r * math.sqrt1_2;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), guide);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), guide);
    var w = wave;
    if (w == null) return;
    var (l, rr) = w;
    // Its loudest, so a quiet sound still fills it.
    var most = 1e-6;
    for (var i = 0; i < l.length; i++) {
      most = math.max(most, math.max(l[i].abs(), rr[i].abs()));
    }
    var scale = r / math.max(most, 0.05) * math.sqrt1_2;
    var points = <Offset>[
      for (var i = 0; i < l.length; i++)
        c + Offset((l[i] - rr[i]) * scale, -(l[i] + rr[i]) * scale),
    ];
    canvas.drawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = studio.meterLow.withValues(alpha: 0.75)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_GoniometerPainter old) => true;
}

/// _CorrelationPainter is the correlation's bar: minus one (opposite, left
/// of the middle, in the warning colour) to plus one (alike).
class _CorrelationPainter extends CustomPainter {
  final double value;
  final StudioColors studio;
  _CorrelationPainter(this.value, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6),
        const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = studio.inset);
    var mid = size.width / 2;
    canvas.drawLine(Offset(mid, 0), Offset(mid, size.height),
        Paint()..color = studio.muted.withValues(alpha: 0.5));
    var x = mid + value.clamp(-1.0, 1.0) * (mid - 4);
    canvas.drawCircle(Offset(x, size.height / 2), 5,
        Paint()..color = value < 0 ? studio.meterHigh : studio.meterLow);
  }

  @override
  bool shouldRepaint(_CorrelationPainter old) => old.value != value;
}

/// _LoudnessBarPainter is short-term loudness from -40 to nought LUFS, the
/// target marked: green under it, amber to a couple over, red past.
class _LoudnessBarPainter extends CustomPainter {
  final double lufs, target;
  final StudioColors studio;
  _LoudnessBarPainter(this.lufs, this.target, this.studio);

  double _x(double v, double w) => ((v + 40) / 40).clamp(0.0, 1.0) * w;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
        Paint()..color = studio.inset);
    if (lufs.isFinite) {
      var colour = lufs > target + 2
          ? studio.meterHigh
          : lufs > target - 1
              ? studio.meterMid
              : studio.meterLow;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, _x(lufs, size.width), size.height),
              const Radius.circular(3)),
          Paint()..color = colour);
    }
    var t = _x(target, size.width);
    canvas.drawLine(
        Offset(t, -2),
        Offset(t, size.height + 2),
        Paint()
          ..color = studio.text
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_LoudnessBarPainter old) =>
      old.lufs != lufs || old.target != target;
}

/// _SpectrogramPainter is a Spectrum over time: a column a tick, the
/// oldest on the left, low pitches at the bottom, each as bright as loud.
class _SpectrogramPainter extends CustomPainter {
  final List<Float32List> history;
  final int count;
  _SpectrogramPainter(this.history, this.count);

  static const int _rows = 64;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1622));
    if (history.isEmpty) return;
    var colW = size.width / _ListenerDeviceState._historyLength;
    var rowH = size.height / _rows;
    var left = size.width - history.length * colW;
    const lowHz = 30.0, highHz = 20000.0;
    var paint = Paint();
    for (var (c, bins) in history.indexed) {
      for (var r = 0; r < _rows; r++) {
        var hz = lowHz * math.pow(highHz / lowHz, r / _rows);
        var i = (hz / 24000 * bins.length).floor().clamp(0, bins.length - 1);
        var db = 20 * math.log(math.max(1e-6, bins[i])) / math.ln10;
        var v = ((db + 80) / 80).clamp(0.0, 1.0);
        if (v < 0.05) continue;
        paint.color = Color.lerp(
            const Color(0xFF3C2470),
            v < 0.6 ? const Color(0xFFD0506A) : const Color(0xFFFFE9A8),
            v < 0.6 ? v / 0.6 : (v - 0.6) / 0.4)!;
        canvas.drawRect(
            Rect.fromLTWH(left + c * colW, size.height - (r + 1) * rowH,
                colW + 0.5, rowH + 0.5),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) => true;
}

/// _SpectrumPainter is a sound's spectrum, low on the left to high on the
/// right, the frequencies spread as an octave a step.
class _SpectrumPainter extends CustomPainter {
  final Float32List? bins;
  final StudioColors studio;
  _SpectrumPainter(this.bins, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E1622));
    var b = bins;
    if (b == null || b.isEmpty) return;
    var path = Path()..moveTo(0, size.height);
    const lowHz = 30.0, highHz = 20000.0;
    for (var x = 0.0; x <= size.width; x += 2) {
      var hz = lowHz * math.pow(highHz / lowHz, x / size.width);
      var i = (hz / 24000 * b.length).floor().clamp(0, b.length - 1);
      var db = 20 * math.log(math.max(1e-6, b[i])) / math.ln10;
      var y = size.height * (1 - ((db + 80) / 80).clamp(0.0, 1.0));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = studio.on.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}

/// DeviceLevels is a device's screen: its own picture (see
/// device_screens.dart), moving with the sound, or where it has none how
/// loud the sound is going into it and coming out of it over the last few
/// seconds. What it changes the level by is read between the devices of
/// [channel]'s strip -- see CanvasController.deviceLevels -- and is not
/// shown for a strip that is not a channel's (null).
class DeviceLevels extends StatefulWidget {
  final CanvasController controller;
  final String? channel;
  final int index;

  /// device is what it draws: see hasScreen. [deviceId] is its id on the
  /// strip, by which its display is switched on (see
  /// CanvasController.analysing); none, it is a picture only.
  final MixDevice? device;
  final String? deviceId;
  final Color accent;

  /// back is the display's background: the studio palette's Display.
  final Color back;
  const DeviceLevels(
      {required this.controller,
      required this.channel,
      required this.index,
      required this.accent,
      this.device,
      this.deviceId,
      this.back = const Color(0xFF110F22),
      super.key});

  @override
  State<DeviceLevels> createState() => _DeviceLevelsState();
}

class _DeviceLevelsState extends State<DeviceLevels>
    with SingleTickerProviderStateMixin, _Metered {
  /// _history is the last few seconds of (in, out), in decibels, oldest
  /// first: for a device with no picture of its own.
  final List<(double, double)> _history = [];
  static const int _length = 120;

  /// _scope is what the engine last kept of the sound through it, and
  /// _stamp counts the readings, for the painter.
  ScopeReading? _scope;
  int _stamp = 0;

  @override
  CanvasController get meteredBy => widget.controller;

  /// _moving is a modulator's screen: what it moves knobs by, drawn as it
  /// goes -- there is no sound through it to show.
  bool get _moving => widget.device?.kind.modulates ?? false;

  /// _t is how long it has been moving, for a modulator's screen.
  double _t = 0;

  /// _on is whether its display shows the real sound (Ken: off until
  /// switched on, as it costs).
  bool get _on {
    if (_moving) return false;
    var channel = widget.channel, id = widget.deviceId;
    if (channel == null || id == null) return widget.device == null;
    return widget.controller.analysing(channel, id);
  }

  @override
  bool get metering => _on || _moving || widget.device == null;

  @override
  void didUpdateWidget(DeviceLevels old) {
    super.didUpdateWidget(old);
    meterAgain();
    if (!_on) _scope = null;
  }

  @override
  void dispose() {
    var channel = widget.channel, id = widget.deviceId;
    if (channel != null && id != null) {
      widget.controller.stopScope(channel, id);
    }
    super.dispose();
  }

  @override
  void tick() {
    _t += 0.033;
    var channel = widget.channel;
    if (channel == null) return;
    var id = widget.deviceId;
    var device = widget.device;
    if (device != null && hasScreen(device.kind)) {
      if (id != null && _on) {
        _scope = widget.controller.deviceScope(channel, id);
        _stamp++;
      }
      return;
    }
    var taps = widget.controller.deviceLevels(channel);
    var i = widget.index;
    if (i + 1 >= taps.length) return;
    double db((double, double) p) => gainToDb(math.max(p.$1, p.$2));
    _history.add((db(taps[i]), db(taps[i + 1])));
    if (_history.length > _length) _history.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    var device = widget.device;
    if (device != null && hasScreen(device.kind)) {
      var channel = widget.channel, id = widget.deviceId;
      var on = _on;
      return Stack(fit: StackFit.expand, children: [
        CustomPaint(
          painter: _moving
              ? DeviceScreenPainter(
                  device,
                  ScreenMoment(t: _t, live: widget.controller.playing),
                  widget.accent,
                  widget.back)
              : on
              ? DeviceAnalysisPainter(
                  device, _scope, widget.accent, widget.back, stamp: _stamp)
              // Off: a still picture of what its settings do.
              : DeviceScreenPainter(
                  device, const ScreenMoment(), widget.accent, widget.back),
        ),
        if (channel != null && id != null && !_moving)
          Positioned(
            top: 3,
            right: 3,
            child: _AnalyseSwitch(
              key: ValueKey("deviceAnalyse-$id"),
              on: on,
              accent: widget.accent,
              onTap: () => widget.controller.setAnalysing(channel, id, !on),
            ),
          ),
      ]);
    }
    return CustomPaint(
      painter: _LevelsPainter(
          List.of(_history), _length, widget.accent, widget.back),
      child: const SizedBox.expand(),
    );
  }
}

/// _AnalyseSwitch puts a device's display on or off: "Analyse", lit while
/// it shows the real sound.
class _AnalyseSwitch extends StatelessWidget {
  final bool on;
  final Color accent;
  final VoidCallback onTap;
  const _AnalyseSwitch(
      {required this.on, required this.accent, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    return Tooltip(
      message: on
          ? "Stop showing the sound through it"
          : "Show the real sound going in and coming out",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
              color: on
                  ? accent.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: on ? accent : look.studio.edge)),
          child: Text("Analyse",
              style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: on ? look.studio.text : look.studio.muted)),
        ),
      ),
    );
  }
}

class _LevelsPainter extends CustomPainter {
  final List<(double, double)> history;
  final int length;
  final Color accent;
  final Color back;
  _LevelsPainter(this.history, this.length, this.accent, this.back);

  /// _y is where [db] sits, nought at the top to minus sixty at the bottom.
  static double _y(double db, double h) =>
      ((-db) / 60).clamp(0.0, 1.0) * (h - 6) + 3;

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var grid = Paint()..color = Color.lerp(back, Colors.white, 0.07)!;
    for (var db in [-12.0, -24.0, -36.0, -48.0]) {
      canvas.drawRect(Rect.fromLTWH(0, _y(db, h), w, 1), grid);
    }
    if (history.length < 2) {
      _label(canvas, "Its levels in and out, while it plays", 6, h - 15,
          const Color(0xFF8E8A9C));
      return;
    }
    Path line(double Function((double, double)) of) {
      var p = Path();
      for (var (i, v) in history.indexed) {
        var x = w - (history.length - 1 - i) * w / (length - 1);
        var y = _y(of(v), h);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    canvas.drawPath(
        line((v) => v.$1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x667FC8F8));
    canvas.drawPath(
        line((v) => v.$2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent);
    var (inDb, outDb) = history.last;
    var change = inDb <= -80 || outDb <= -80 ? null : outDb - inDb;
    _label(
        canvas,
        change == null
            ? "—"
            : "${change >= 0 ? "+" : "−"}${change.abs().toStringAsFixed(1)} dB",
        6,
        h - 15,
        change == null
            ? const Color(0xFF8E8A9C)
            : change > 0.05
                ? const Color(0xFFE2B04A)
                : change < -0.05
                    ? const Color(0xFF7FC8F8)
                    : const Color(0xFFE8E4EE));
  }

  void _label(Canvas canvas, String text, double x, double y, Color colour) {
    var tp = paintedLabel(
        text,
        TextStyle(
            fontSize: 10,
            color: colour,
            fontFeatures: const [FontFeature.tabularFigures()]));
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_LevelsPainter old) =>
      old.history.length != history.length ||
      (history.isNotEmpty && old.history.last != history.last) ||
      old.accent != accent;
}

/// VoiceStartCard is the way into a channel's Speech where it has none --
/// "Speak a script" -- or, with [sing], to its Vocaliser: "Sing it", a sung
/// copy of the speech made as a new clip.
class VoiceStartCard extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final double height;
  final bool sing;
  const VoiceStartCard(
      {required this.controller,
      required this.channel,
      required this.height,
      this.sing = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    return Container(
      width: 200,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: look.studio.strip,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: look.studio.edge)),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(sing ? Icons.music_note : Icons.record_voice_over,
              size: 20, color: skin.ink),
          const SizedBox(height: 8),
          Text(
              sing
                  ? "Sing it: the speech sung to notes, made as a new clip."
                  : "Speak a script: each line spoken is a clip on this "
                      "channel, beside recordings.",
              style: TextStyle(fontSize: 11.5, height: 1.4, color: skin.dim)),
          const SizedBox(height: 10),
          FilledButton.tonal(
            key: ValueKey(sing ? "speechSingButton" : "speechStartButton"),
            onPressed: () {
              controller.beginInteraction();
              if (sing) {
                controller.setVocaliser(channel, const VocaliserSpec());
              } else {
                controller.setSpeech(channel, const SpeechSpec());
              }
              controller.endInteraction();
              controller.openEffects(channel,
                  device: sing ? "vocaliser" : "speech");
            },
            child: Text(sing ? "Sing it" : "Speak a script"),
          ),
        ]),
      ),
    );
  }
}
