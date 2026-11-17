part of 'canvas_mixer.dart';

// Where a channel is heard from: the balance knob, the surround pad, and the
// effects panel's Panner device with its room painters. Part of
// canvas_mixer.dart.

/// _Balance is a knob: dragged up to turn right, down to turn left,
/// double-clicked to centre.
class _Balance extends StatelessWidget {
  final double value;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;

  const _Balance({
    required this.value,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    var reading = value.abs() < 0.02
        ? "C"
        : "${value < 0 ? "L" : "R"}${(value.abs() * 100).round()}";
    return Row(children: [
      Text("Pan",
          style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant)),
      const Spacer(),
      GestureDetector(
        supportedDevices: dragPointers,
        key: const ValueKey("balance"),
        onVerticalDragUpdate: (d) => onChanged(
            (value - d.delta.dy / 80).clamp(-1.0, 1.0),
            transient: true),
        onVerticalDragEnd: (_) => onCommit(),
        onDoubleTap: () => onChanged(0),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: CustomPaint(
            size: const Size(24, 24),
            painter: _KnobPainter(value, theme.colors),
          ),
        ),
      ),
      const Spacer(),
      SizedBox(
        width: 26,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(reading,
              style: TextStyle(fontSize: 10, color: theme.colors.onSurface)),
        ),
      ),
    ]);
  }
}

/// _SoundScene is what the strips need to know of the room: the speakers
/// the piece is mixed for, and where each placed channel is heard from on
/// this frame.
class _SoundScene extends InheritedWidget {
  final SpeakerLayout speakers;
  final Map<String, Heard> placed;
  const _SoundScene(
      {required this.speakers, required this.placed, required super.child});

  static _SoundScene? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SoundScene>();

  @override
  bool updateShouldNotify(_SoundScene old) =>
      old.speakers != speakers || !mapEquals(old.placed, placed);
}

/// angleText is an angle as a strip says it: C, or L or R and how far.
String angleText(double angle) {
  var a = wrapAngle(angle);
  if (a.abs() < 1) return "C";
  return "${a < 0 ? "L" : "R"}${a.abs().round()}°";
}

/// _PanControl is where a channel is heard from. Stereo: the balance knob.
/// Surround: a pad of the room, its speakers round it, the channel a dot to
/// drag (with how wide its two sides are spread, and how much goes to the
/// LFE). Placed by the picture: the same pad, showing where the picture
/// puts it, not to be dragged.
class _PanControl extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  const _PanControl({
    required this.channel,
    required this.mix,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    var scene = _SoundScene.of(context);
    var speakers = scene?.speakers ?? SpeakerLayout.stereo;
    var placed = scene?.placed[channel];
    if (placed == null && !speakers.isSurround) {
      return _Balance(
        value: mix.balance,
        theme: theme,
        onChanged: (v, {transient = false}) =>
            onChanged(mix.copyWith(balance: v), transient: transient),
        onCommit: onCommit,
      );
    }
    var colors = theme.colors;
    var pan = mix.surround ?? const SurroundPan();
    var small = TextStyle(fontSize: 9, color: colors.onSurfaceVariant);
    var value = TextStyle(fontSize: 10, color: colors.onSurface);
    // The pad beside its readings, not over them: a strip is a column of
    // fixed height with the fader taking what is left.
    var pad = Tooltip(
      message: placed != null
          ? "Heard from where the picture puts it: see the sound's "
              "Placement. Its own pan is kept for when it is not placed."
          : "Drag the dot round to where it is heard from. Double-click "
              "for the front pair, as it was mixed.",
      child: _SurroundPad(
        key: const ValueKey("surroundPad"),
        speakers: speakers,
        pan: placed == null ? mix.surround : null,
        placed: placed,
        theme: theme,
        onAngle: placed != null
            ? null
            : (a) => onChanged(mix.withSurround(pan.copyWith(angle: a)),
                transient: true),
        onCommit: onCommit,
        onReset:
            placed != null ? null : () => onChanged(mix.withSurround(null)),
      ),
    );
    Widget fit(Widget child, Alignment to) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: to, child: child);
    return SizedBox(
      height: _SurroundPad.size,
      child: Row(children: [
        pad,
        const SizedBox(width: 5),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Each shrinks rather than runs out of a narrow strip.
                if (placed != null)
                  fit(Text("Placed", style: small), Alignment.centerLeft),
                fit(
                    Text(
                        key: const ValueKey("panReading"),
                        placed != null
                            ? angleText(placed.angle)
                            : mix.surround == null
                                ? "Front"
                                : angleText(pan.angle),
                        style: value),
                    Alignment.centerLeft),
                if (placed == null && speakers.isSurround) ...[
                  _DragNumber(
                    key: const ValueKey("surroundWidth"),
                    label: "W",
                    text: "${pan.width.round()}°",
                    theme: theme,
                    tooltip: "Width: how far apart its left and right are "
                        "heard. 60 is the front pair, nought one point. Drag "
                        "up or down.",
                    onDrag: (dy) => onChanged(
                        mix.withSurround(pan.copyWith(width: pan.width - dy)),
                        transient: true),
                    onCommit: onCommit,
                    onReset: () =>
                        onChanged(mix.withSurround(pan.copyWith(width: 60))),
                  ),
                  _DragNumber(
                    key: const ValueKey("surroundLfe"),
                    label: "LFE",
                    text: mix.lfeDb == null ? "off" : dbText(mix.lfeDb!),
                    theme: theme,
                    tooltip: "How much also goes to the LFE, the "
                        "low-frequency speaker, below 120Hz. Drag up or "
                        "down; double-click for none.",
                    onDrag: (dy) => onChanged(
                        mix.withLfe((mix.lfeDb ?? -61) - dy / 2),
                        transient: true),
                    onCommit: onCommit,
                    onReset: () => onChanged(mix.withLfe(null)),
                  ),
                ] else
                  const Spacer(),
              ]),
        ),
      ]),
    );
  }
}

/// speakerLights is how much of a channel each of [layout]'s speakers
/// carries, nought to one (the same sums MixGraph lands it with), for
/// lighting them.
List<double> speakerLights(
    SpeakerLayout layout, ChannelMix mix, Heard? placed) {
  var n = layout.channels;
  var out = List.filled(n, 0.0);
  if (placed != null) {
    var g = panGains(layout, placed.angle);
    for (var c = 0; c < n; c++) {
      out[c] = g[c] * placed.gain;
    }
    return out;
  }
  if (!layout.isSurround) {
    var b = mix.balance.clamp(-1.0, 1.0);
    return [b > 0 ? 1 - b : 1, b < 0 ? 1 + b : 1];
  }
  var pan = mix.surround;
  if (pan == null) {
    out[0] = 1;
    out[1] = 1;
  } else {
    var gl = panGains(layout, pan.angle - pan.width / 2, centre: pan.centre);
    var gr = panGains(layout, pan.angle + pan.width / 2, centre: pan.centre);
    for (var c = 0; c < n; c++) {
      out[c] = math.max(gl[c], gr[c]);
    }
  }
  if ((layout.lfe, mix.lfeDb) case (var lfe?, var db?)) {
    out[lfe] = dbToGain(db).clamp(0.0, 1.0);
  }
  return out;
}

/// _PannerDevice is the effects panel's view of where a channel is heard
/// from: the room from above, big enough to place a sound by, its speakers
/// lit by how much of the channel each carries. See _PanControl for the
/// stereo, surround and placed cases.
class _PannerDevice extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final DeviceSkin skin;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  const _PannerDevice({
    required this.channel,
    required this.mix,
    required this.theme,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.onChanged,
    required this.onCommit,
  });

  /// _stereoFrom is the balance a point at [angle] gives: the front pair
  /// across, a point behind heard on its own side.
  static double _stereoFrom(double angle) {
    var a = wrapAngle(angle);
    if (a > 90) a = 180 - a;
    if (a < -90) a = -180 - a;
    return (a / 30).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    var scene = _SoundScene.of(context);
    var layout = scene?.speakers ?? SpeakerLayout.stereo;
    var placed = scene?.placed[channel];
    var surround = layout.isSurround;
    var pan = mix.surround ?? const SurroundPan();
    var colors = theme.colors;
    var reading = placed != null
        ? angleText(placed.angle)
        : surround
            ? (mix.surround == null ? "Front" : angleText(pan.angle))
            : (mix.balance.abs() < 0.02
                ? "C"
                : "${mix.balance < 0 ? "L" : "R"}"
                    "${(mix.balance.abs() * 100).round()}");
    // The room fills the device: as wide as it is, as tall as the device less
    // the bar of readings along its foot, with the speakers on an ellipse to
    // match. A press is read against the room as it was drawn.
    void point(Offset local, Size room) {
      var rx = room.width / 2 - 22, ry = room.height / 2 - 18;
      var d = local - room.center(Offset.zero);
      var angle = math.atan2(d.dx / rx, -d.dy / ry) * 180 / math.pi;
      onChanged(
          surround
              ? mix.withSurround(pan.copyWith(angle: angle))
              : mix.copyWith(balance: _stereoFrom(angle)),
          transient: true);
    }

    Widget viewOf(Size room) {
      Widget view = CustomPaint(
        size: room,
        painter: _BigRoomPainter(
          layout: layout,
          mix: mix,
          placed: placed,
          lights: speakerLights(layout, mix, placed),
          studio: theme.studio,
        ),
      );
      if (placed == null) {
        // Set by a press and a drag only: a wheel or trackpad scroll over it
        // scrolls the chain. Its width is the Width number's.
        view = GestureDetector(
          supportedDevices: dragPointers,
          onPanStart: (d) => point(d.localPosition, room),
          onPanUpdate: (d) => point(d.localPosition, room),
          onPanEnd: (_) => onCommit(),
          onDoubleTap: () => onChanged(
              surround ? mix.withSurround(null) : mix.copyWith(balance: 0)),
          child: MouseRegion(cursor: SystemMouseCursors.precise, child: view),
        );
      }
      return view;
    }

    var small = TextStyle(fontSize: 10, color: colors.onSurfaceVariant);
    Widget number(String key, String label, String text, String tip,
            ValueChanged<double> drag, VoidCallback reset) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _DragNumber(
              key: ValueKey(key),
              label: label,
              text: text,
              theme: theme,
              height: 20,
              tooltip: tip,
              onDrag: drag,
              onCommit: onCommit,
              onReset: reset,
            ),
          ),
        );

    var bar = SizedBox(
      height: 24,
      child: Row(children: [
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(reading,
                  key: const ValueKey("pannerReading"),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurface)),
              const SizedBox(width: 6),
              Text(
                  placed != null
                      ? (placed.gain >= 0.999
                          ? "Placed by the picture"
                          : "Placed · ${dbText(gainToDb(placed.gain))} dB")
                      : layout.label,
                  style: small),
            ]),
          ),
        ),
        if (placed == null && surround) ...[
          number(
              "pannerAngle",
              "Angle",
              "${wrapAngle(pan.angle).round()}°",
              "Where it is heard from, round from straight ahead. Drag up or "
                  "down; double-click for the front.",
              (dy) => onChanged(
                  mix.withSurround(pan.copyWith(angle: pan.angle - dy)),
                  transient: true),
              () => onChanged(mix.withSurround(pan.copyWith(angle: 0)))),
          number(
              "pannerWidth",
              "Width",
              "${pan.width.round()}°",
              "How far apart its left and right are heard: 60 is the front "
                  "pair, nought one point.",
              (dy) => onChanged(
                  mix.withSurround(pan.copyWith(width: pan.width - dy)),
                  transient: true),
              () => onChanged(mix.withSurround(pan.copyWith(width: 60)))),
          if (layout.speakers.any((s) => s.$2 == 0))
            number(
                "pannerCentre",
                "Centre",
                "${(pan.centre * 100).round()}%",
                "How much of what is heard from in front goes to the centre "
                    "speaker: all of it, or none -- between the front pair, "
                    "the centre kept for voices.",
                (dy) => onChanged(
                    mix.withSurround(
                        pan.copyWith(centre: pan.centre - dy / 100)),
                    transient: true),
                () => onChanged(mix.withSurround(pan.copyWith(centre: 1)))),
          number(
              "pannerLfe",
              "LFE",
              mix.lfeDb == null ? "off" : "${dbText(mix.lfeDb!)} dB",
              "How much also goes to the LFE, below 120Hz. Double-click for "
                  "none.",
              (dy) => onChanged(mix.withLfe((mix.lfeDb ?? -61) - dy / 2),
                  transient: true),
              () => onChanged(mix.withLfe(null))),
        ] else if (placed == null)
          number(
              "pannerBalance",
              "Pan",
              reading,
              "Left to right. Drag up or down; double-click for the middle.",
              (dy) => onChanged(
                  mix.copyWith(
                      balance: (mix.balance - dy / 80).clamp(-1.0, 1.0)),
                  transient: true),
              () => onChanged(mix.copyWith(balance: 0))),
        if (placed == null)
          TextButton(
            key: const ValueKey("pannerFront"),
            onPressed: () => onChanged(
                surround ? mix.withSurround(null) : mix.copyWith(balance: 0)),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: colors.onSurfaceVariant),
            child: FittedBox(
                child: Text(surround ? "Front pair" : "Centre",
                    style: const TextStyle(fontSize: 11))),
          ),
      ]),
    );

    return DeviceFrame(
      id: "panner",
      icon: Icons.speaker,
      accent: const Color(0xFFCFCBDF),
      help: "Where it is heard from. Drag in the room to place it; in "
          "surround the wheel sets its width. Centre is how much of what is "
          "in front goes to the centre speaker. Double-click for the front.",
      title: "Panner",
      skin: skin,
      folded: folded,
      onFold: onFold,
      // Wider than tall, as a room is.
      width: (height * 1.6).clamp(340.0, 560.0),
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(reading, style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Tooltip(
              message: placed != null
                  ? "Heard from where the picture puts it -- see the sound's "
                      "Placement."
                  : surround
                      ? "Drag to where it is heard from; the wheel sets its "
                          "width. Double-click for the front pair."
                      : "Drag between the speakers to set its balance. "
                          "Double-click for the middle.",
              child: LayoutBuilder(
                builder: (context, box) => KeyedSubtree(
                    key: const ValueKey("pannerRoom"),
                    child: viewOf(box.biggest)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          bar,
        ]),
      ),
    );
  }
}

class _BigRoomPainter extends CustomPainter {
  final SpeakerLayout layout;
  final ChannelMix mix;
  final Heard? placed;
  final List<double> lights;
  final StudioColors studio;

  _BigRoomPainter({
    required this.layout,
    required this.mix,
    required this.placed,
    required this.lights,
    required this.studio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    // The room's width and depth: speakers round an ellipse, not a circle,
    // so the room fills the device. [k] is how far out, nought to one.
    var rx = size.width / 2 - 22, ry = size.height / 2 - 18;
    Offset at(double deg, double k) {
      var a = deg * math.pi / 180;
      return c + Offset(math.sin(a) * rx * k, -math.cos(a) * ry * k);
    }

    Rect oval(double k) =>
        Rect.fromCenter(center: c, width: 2 * rx * k, height: 2 * ry * k);

    void label(String text, Offset centre, Color colour, double fontSize) {
      var p = paintedLabel(
          text,
          TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w600, color: colour));
      p.paint(canvas, centre - Offset(p.width / 2, p.height / 2));
    }

    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = studio.display);
    var guide = Paint()
      ..style = PaintingStyle.stroke
      ..color = studio.displayLine.withValues(alpha: 0.18);
    for (var k in [0.33, 0.66, 1.0]) {
      canvas.drawOval(oval(k), guide);
    }
    for (var deg = 0; deg < 360; deg += 30) {
      canvas.drawLine(c, at(deg.toDouble(), 1), guide);
    }
    // In the corner, clear of the centre speaker under it.
    var front = paintedLabel(
        "▲ FRONT",
        TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: studio.displayLine.withValues(alpha: 0.7)));
    front.paint(canvas, const Offset(8, 6));

    for (var (i, (name, deg)) in layout.speakers.indexed) {
      var lit = i < lights.length ? lights[i] : 0.0;
      if (deg == null) {
        // The LFE has no direction: a box at the foot of the room.
        var box = Rect.fromCenter(
            center: Offset(c.dx, size.height - 10), width: 30, height: 12);
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)),
            Paint()..color = Color.lerp(studio.inset, studio.on, lit)!);
        label("LFE", box.center, lit > 0.5 ? studio.onOn : studio.muted, 8);
        continue;
      }
      var p = at(deg.toDouble(), 1);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(deg * math.pi / 180);
      var cabinet = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 22, height: 14),
          const Radius.circular(3));
      canvas.drawRRect(
          cabinet, Paint()..color = Color.lerp(studio.inset, studio.on, lit)!);
      canvas.drawRRect(
          cabinet,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = studio.edge);
      canvas.restore();
      label(name, p, lit > 0.5 ? studio.onOn : studio.text, 9);
    }

    canvas.drawCircle(c, 9, Paint()..color = studio.raised);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - 4, c.dy - 7)
          ..lineTo(c.dx + 4, c.dy - 7)
          ..lineTo(c.dx, c.dy - 13)
          ..close(),
        Paint()..color = studio.muted);

    var dot = Paint()..color = studio.on;
    var ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = studio.on;
    if (placed case var h?) {
      // Nearer the middle the louder it is.
      var p = at(h.angle, 1.05 - h.gain.clamp(0.25, 1.0) * 0.45);
      canvas.drawCircle(p, 9, ring);
      canvas.drawCircle(p, 5, dot);
      return;
    }
    if (!layout.isSurround) {
      var deg = mix.balance.clamp(-1.0, 1.0) * 30;
      canvas.drawArc(
          oval(0.7),
          (-30 - 90) * math.pi / 180,
          60 * math.pi / 180,
          false,
          guide
            ..strokeWidth = 3
            ..color = studio.displayLine.withValues(alpha: 0.35));
      canvas.drawCircle(at(deg, 0.7), 7, dot);
      return;
    }
    var pan = mix.surround;
    if (pan == null) {
      canvas.drawCircle(at(-30, 0.7), 6, dot);
      canvas.drawCircle(at(30, 0.7), 6, dot);
      return;
    }
    if (pan.width > 0) {
      canvas.drawArc(
          oval(0.7),
          (pan.angle - pan.width / 2 - 90) * math.pi / 180,
          pan.width * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = studio.on.withValues(alpha: 0.5));
      for (var side in [-1, 1]) {
        canvas.drawCircle(at(pan.angle + side * pan.width / 2, 0.7), 4,
            Paint()..color = studio.text);
      }
    }
    canvas.drawCircle(at(pan.angle, 0.7), 7, dot);
  }

  @override
  bool shouldRepaint(_BigRoomPainter old) =>
      old.layout != layout ||
      !identical(old.mix, mix) ||
      old.placed != placed ||
      !listEquals(old.lights, lights) ||
      old.studio != studio;
}

/// _DragNumber is a small label and value, changed by dragging up or down
/// and put back by a double-click.
class _DragNumber extends StatelessWidget {
  final String label;
  final String text;
  final String tooltip;
  final MixerLook theme;
  final ValueChanged<double> onDrag;
  final VoidCallback onCommit;
  final VoidCallback onReset;

  final double height;

  const _DragNumber({
    this.height = 14,
    required this.label,
    required this.text,
    required this.tooltip,
    required this.theme,
    required this.onDrag,
    required this.onCommit,
    required this.onReset,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          supportedDevices: dragPointers,
          onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
          onVerticalDragEnd: (_) => onCommit(),
          onDoubleTap: onReset,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: theme.colors.surfaceContainerLowest,
                border: Border.all(color: theme.colors.outlineVariant),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text("$label $text",
                    style: TextStyle(
                        fontSize: height > 16 ? 11 : 9,
                        color: theme.colors.onSurface)),
              ),
            ),
          ),
        ),
      );
}

/// _SurroundPad is the room from above, the listener in the middle facing
/// up: each speaker a mark round the edge, the channel a dot where it is
/// heard from, its two sides' spread an arc either side.
class _SurroundPad extends StatelessWidget {
  final SpeakerLayout speakers;
  final SurroundPan? pan;
  final Heard? placed;
  final MixerLook theme;
  final ValueChanged<double>? onAngle;
  final VoidCallback onCommit;
  final VoidCallback? onReset;

  const _SurroundPad({
    required this.speakers,
    required this.pan,
    required this.placed,
    required this.theme,
    required this.onAngle,
    required this.onCommit,
    required this.onReset,
    super.key,
  });

  static const double size = 48;
  double get side => size;

  double _angleAt(Offset local) {
    var d = local - Offset(side / 2, side / 2);
    return math.atan2(d.dx, -d.dy) * 180 / math.pi;
  }

  @override
  Widget build(BuildContext context) {
    var painter = CustomPaint(
      size: Size.square(side),
      painter: _RoomPainter(speakers, pan, placed, theme.studio),
    );
    var angle = onAngle;
    if (angle == null) return painter;
    return GestureDetector(
      supportedDevices: dragPointers,
      onPanStart: (d) => angle(_angleAt(d.localPosition)),
      onPanUpdate: (d) => angle(_angleAt(d.localPosition)),
      onPanEnd: (_) => onCommit(),
      onDoubleTap: onReset,
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: painter),
    );
  }
}

class _RoomPainter extends CustomPainter {
  final SpeakerLayout speakers;
  final SurroundPan? pan;
  final Heard? placed;
  final StudioColors studio;
  _RoomPainter(this.speakers, this.pan, this.placed, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 4;
    Offset at(double deg, double radius) {
      var a = deg * math.pi / 180;
      return c + Offset(math.sin(a), -math.cos(a)) * radius;
    }

    canvas.drawCircle(c, r + 3, Paint()..color = studio.inset);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = studio.edge);
    canvas.drawCircle(c, 2.5, Paint()..color = studio.muted);
    for (var (_, deg) in speakers.speakers) {
      if (deg == null) continue;
      canvas.drawCircle(at(deg.toDouble(), r), 3, Paint()..color = studio.text);
    }
    var lit = Paint()..color = studio.on;
    if (placed case var h?) {
      // Nearer the middle the louder it is.
      canvas.drawCircle(
          at(h.angle, r * (1.15 - h.gain.clamp(0.3, 1.0) * 0.4)), 4.5, lit);
      return;
    }
    var p = pan;
    if (p == null) {
      canvas.drawCircle(at(-30, r * 0.75), 3, lit);
      canvas.drawCircle(at(30, r * 0.75), 3, lit);
      return;
    }
    if (p.width > 0) {
      var rect = Rect.fromCircle(center: c, radius: r * 0.75);
      canvas.drawArc(
          rect,
          (p.angle - p.width / 2 - 90) * math.pi / 180,
          p.width * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = studio.on.withValues(alpha: 0.55));
    }
    canvas.drawCircle(at(p.angle, r * 0.75), 4.5, lit);
  }

  @override
  bool shouldRepaint(_RoomPainter old) =>
      old.speakers != speakers ||
      old.pan != pan ||
      old.placed != placed ||
      old.studio != studio;
}

class _KnobPainter extends CustomPainter {
  final double value;
  final ColorScheme colors;
  _KnobPainter(this.value, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.outlineVariant);
    var angle = -math.pi / 2 + value * math.pi * 0.75;
    canvas.drawLine(
        c,
        c + Offset(math.cos(angle), math.sin(angle)) * (r - 2),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.onSurface);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value;
}
