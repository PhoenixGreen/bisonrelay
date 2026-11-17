part of 'canvas_mixer.dart';

// A strip's sound half: its pan slider, on, solo and arm switches, its fader,
// and the band minimised to a row of buttons over a sideways meter. Part of
// canvas_mixer.dart.

/// _mixerBand is a strip's sound half, row for row as the motion half over
/// it: SOUND and the level; the pan, a slider centred as the cross-fader is;
/// the switches (on, solo, arm) as chips; then the fader on its meter.
Widget _mixerBand({
  required Widget left,
  required Widget fader,
  required Widget reading,
  bool narrow = false,
}) =>
    Builder(builder: (context) {
      var studio = MixerLook.of(context).studio;
      var parts = left is _SoundLeft ? left : null;
      var chips = [
        if (parts?.on case var on?) on,
        if (parts?.solo case var solo?) solo,
        if (parts?.arm case var arm?) arm,
      ];
      return Column(
          key: const ValueKey("soundHalf"),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 14,
              child: Row(children: [
                // The label gives way first: the level is the number.
                Flexible(
                  child: Text(narrow ? "SND" : "SOUND",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: narrow ? 0 : 0.6,
                          fontWeight: FontWeight.w600,
                          color: studio.muted)),
                ),
                const SizedBox(width: 2),
                // Bounded, as the level becomes a field to type into.
                Expanded(
                  child:
                      Align(alignment: Alignment.centerRight, child: reading),
                ),
              ]),
            ),
            const SizedBox(height: 3),
            if (parts != null) ...[
              SizedBox(height: _panH, child: parts.pan),
              const SizedBox(height: 4),
              // Its room kept with no switches (the master), so every
              // fader starts on one line.
              SizedBox(
                height: _chipH,
                child: Row(children: [
                  for (var (i, c) in chips.indexed) ...[
                    if (i > 0) SizedBox(width: narrow ? 2 : 3),
                    Expanded(child: c),
                  ],
                ]),
              ),
              const SizedBox(height: 4),
            ] else ...[
              left,
              const SizedBox(height: 4),
            ],
            Expanded(child: fader),
          ]);
    });

/// _panH and _chipH are the sound half's pan and switch rows.
const double _panH = 28;

const double _chipH = 14;

/// _soundLeast is the least a sound half gets: its rows and a usable fader.
const double _soundLeast = 14 + 3 + _panH + 4 + _chipH + 4 + 30;

/// _SoundLeft is a strip's pan and its on, solo and arm switches.
class _SoundLeft extends StatelessWidget {
  final Widget pan;
  final Widget? on, solo, arm;
  const _SoundLeft({required this.pan, this.on, this.solo, this.arm});

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(height: _panH, child: pan),
        for (var b in [on, solo, arm])
          if (b != null) SizedBox(height: _chipH, child: b),
      ]);
}

Widget _leftColumn({
  required Widget pan,
  Widget? on,
  Widget? solo,
  Widget? arm,
}) =>
    _SoundLeft(pan: pan, on: on, solo: solo, arm: arm);

/// _StripPan is where a column is heard from, in its left column. Stereo,
/// a knob: dragged up to turn right, double-clicked to centre. In surround,
/// or placed by the picture, a button with the room in miniature that opens
/// the Panner in the effects, since a strip is too small to place a sound in.
class _StripPan extends StatelessWidget {
  final String channel;
  final ChannelMix mix;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onOpenPanner;

  const _StripPan({
    required this.channel,
    required this.mix,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    required this.onOpenPanner,
  });

  @override
  Widget build(BuildContext context) {
    var scene = _SoundScene.of(context);
    var speakers = scene?.speakers ?? SpeakerLayout.stereo;
    var placed = scene?.placed[channel];
    var colors = theme.colors;
    var small = TextStyle(fontSize: 8, height: 1, color: colors.onSurface);
    if (placed == null && !speakers.isSurround) {
      var b = mix.balance;
      var reading = b.abs() < 0.02
          ? "C"
          : "${b < 0 ? "L" : "R"}${(b.abs() * 100).round()}";
      return Tooltip(
        message: "Pan: drag left or right. Double-click for the centre.",
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            supportedDevices: dragPointers,
            key: const ValueKey("balance"),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => onChanged(
                mix.copyWith(
                    balance: (mix.balance +
                            d.delta.dx * 2 / math.max(24, box.maxWidth - 12))
                        .clamp(-1.0, 1.0)),
                transient: true),
            onHorizontalDragEnd: (_) => onCommit(),
            onDoubleTap: () => onChanged(mix.copyWith(balance: 0)),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Column(children: [
                SizedBox(
                  height: 14,
                  child: CustomPaint(
                      size: Size.infinite,
                      painter: _PanTrackPainter(b, theme.studio)),
                ),
                SizedBox(
                  height: 12,
                  child: Row(children: [
                    Text("L", style: small.copyWith(color: theme.studio.muted)),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(reading,
                                key: const ValueKey("panReading"),
                                style: small)),
                      ),
                    ),
                    Text("R", style: small.copyWith(color: theme.studio.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    var pan = mix.surround;
    var reading = placed != null
        ? angleText(placed.angle)
        : pan == null
            ? "Front"
            : angleText(pan.angle);
    return Tooltip(
      message: placed != null
          ? "Placed by the picture, at $reading: see the sound's "
              "Placement. Open the Panner to see it bigger."
          : "Heard from $reading. Open the Panner in the effects to place it "
              "round the room, with its width and its LFE.",
      child: Material(
        color: theme.studio.inset,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: const ValueKey("pannerButton"),
          borderRadius: BorderRadius.circular(4),
          onTap: onOpenPanner,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.studio.edge),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CustomPaint(
                  size: const Size.square(17),
                  painter: _RoomPainter(speakers, placed == null ? pan : null,
                      placed, theme.studio)),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(reading,
                      key: const ValueKey("panReading"), style: small)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// _onToggle is a column's switch, its number or letter on it: lit while it
/// is heard, dark while it is muted (Ableton's track activator).
Widget _onToggle(MixerLook theme, String label, bool muted, VoidCallback onTap,
        {required Key key, required String what, IconData? icon}) =>
    _Toggle(
        key: key,
        // M, lit amber while muted; a switch with an icon (the scene's
        // power) lit while on.
        label: icon == null ? "M" : label,
        icon: icon,
        on: icon == null ? muted : !muted,
        onColor: theme.studio.on,
        onInk: theme.studio.onOn,
        height: _buttonH,
        fontSize: 8,
        theme: theme,
        tooltip: muted
            ? "$what is off: silent here and in exports. Press to switch "
                "it on."
            : "$what is on. Press to switch it off: silent here and in "
                "exports.",
        onTap: onTap);

Widget _faderOf(MixerLook theme, double db, _Meter meter,
        _MixWrite<double> onChanged, VoidCallback onCommit,
        {bool wide = false, bool narrow = false}) =>
    _Fader(
      db: db,
      meter: meter,
      theme: theme,
      wide: wide,
      small: true,
      labels: !narrow,
      onChanged: onChanged,
      onCommit: onCommit,
    );

/// _miniMixerBand is a column's mixer band minimised: its buttons in a row,
/// over its meter on its side, which is its fader too, dragged sideways.
/// [bare], at the mixer's smallest, the meter alone.
Widget _miniMixerBand(
  MixerLook theme, {
  bool bare = false,
  required List<Widget?> buttons,
  required double db,
  required _Meter meter,
  required _MixWrite<double> onDb,
  required VoidCallback onCommit,
}) =>
    bare
        ? _MiniFader(
            db: db,
            meter: meter,
            theme: theme,
            onChanged: onDb,
            onCommit: onCommit)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: _buttonH,
              // Each side shrinks to fit a narrow column.
              child: Row(children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var b in buttons)
                        if (b != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: SizedBox(
                                width: _buttonW, height: _buttonH, child: b),
                          ),
                    ]),
                  ),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(dbText(db),
                        style: TextStyle(
                            fontSize: 9, color: theme.colors.onSurface)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _MiniFader(
                  db: db,
                  meter: meter,
                  theme: theme,
                  onChanged: onDb,
                  onCommit: onCommit),
            ),
          ]);

/// _MiniFader is a meter on its side with the fader's place marked on it:
/// dragged sideways it sets the level, double-clicked it is nought.
class _MiniFader extends StatelessWidget {
  final double db;
  final _Meter meter;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;

  const _MiniFader({
    required this.db,
    required this.meter,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        var w = math.max(1.0, box.maxWidth);
        void at(double x) =>
            onChanged(faderDb((1 - x / w).clamp(0.0, 1.0)), transient: true);
        return GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("miniFader"),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onCommit(),
          onDoubleTap: () => onChanged(0),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: CustomPaint(
              size: Size(w, box.maxHeight),
              painter: _MeterPainter(meter, theme.studio, horizontal: true),
              foregroundPainter:
                  _CapMark((1 - faderPosition(db)) * w, theme.studio.text),
            ),
          ),
        );
      });
}

class _CapMark extends CustomPainter {
  final double x;
  final Color colour;
  _CapMark(this.x, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x - 2, -1, 4, size.height + 2),
            const Radius.circular(2)),
        Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_CapMark old) => old.x != x || old.colour != colour;
}

/// _PanTrackPainter is the pan slider: a groove with its centre marked, the
/// stretch from the centre to the pan filled, and the thumb.
class _PanTrackPainter extends CustomPainter {
  final double balance;
  final StudioColors studio;
  _PanTrackPainter(this.balance, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.height / 2;
    var span = size.width - 12;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(0, mid - 2, size.width, mid + 2),
            const Radius.circular(2)),
        Paint()..color = studio.inset);
    var centre = 6 + span / 2;
    canvas.drawLine(
        Offset(centre, mid - 5),
        Offset(centre, mid + 5),
        Paint()
          ..color = studio.muted
          ..strokeWidth = 1);
    var x = 6 + span * (balance.clamp(-1.0, 1.0) + 1) / 2;
    canvas.drawRect(
        Rect.fromLTRB(
            math.min(centre, x), mid - 2, math.max(centre, x), mid + 2),
        Paint()..color = studio.on.withValues(alpha: 0.6));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, mid), width: 8, height: size.height - 2),
            const Radius.circular(2)),
        Paint()..color = studio.text);
  }

  @override
  bool shouldRepaint(_PanTrackPainter old) =>
      old.balance != balance || old.studio != studio;
}
