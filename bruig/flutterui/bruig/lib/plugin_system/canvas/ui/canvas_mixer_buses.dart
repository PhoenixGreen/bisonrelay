part of 'canvas_mixer.dart';

// canvas_mixer_buses.dart is a bus's own cards in the Chain, as the chain
// prototype has them (Ken, 2026-11-08): a scene's Source -- everything heard
// in it, summed, with its transition's sound -- and a bus's Output, its
// level and where it goes.

const _sceneColour = Color(0xFF5AB4C8);

/// _SceneSoundDevice is the scene bus's source: each of the scene's
/// channels and its level now, and the sound its transition plays.
class _SceneSoundDevice extends StatelessWidget {
  final CanvasController controller;
  final Map<String, (double, double)> levels;
  final MixerLook theme;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const _SceneSoundDevice(
      {required this.controller,
      required this.levels,
      required this.theme,
      required this.folded,
      required this.onFold,
      required this.height});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var doc = c.document;
    var skin = DeviceSkin.studio(theme.studio);
    var index = doc.at;
    var name = doc.scene.name.isEmpty
        ? "${doc.kind.one} ${index + 1}"
        : doc.scene.name;
    // What the scene's bus sums: its own channels, and the transitions'.
    var rows = <(String, String)>[
      for (var ch in c.timelineChannels)
        if (ch.lanes.any((l) =>
            l.scene >= 0 || l.element.id.startsWith(transitionSoundPrefix)))
          (ch.key, ch.name),
    ];
    var last = index >= doc.allScenes.length - 1;
    var after = last ? null : doc.transitionAfter(index);
    var sound = after != null && after.on && after.sound.isNotEmpty;
    return DeviceFrame(
      id: "sceneSound",
      title: "Scene sound",
      help: "Everything heard in this ${doc.kind.one} -- its channels, its "
          "elements' sounds and its transition's -- summed into its bus, "
          "through its devices and on to the master.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 300,
      height: height,
      icon: Icons.graphic_eq,
      accent: _sceneColour,
      glows: true,
      summary: "${rows.length} channel${rows.length == 1 ? "" : "s"}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        DevicePack(key: const ValueKey("sceneSoundPack"), children: [
          if (sound)
            DeviceKnob(
              key: const ValueKey("sceneTransitionVolume"),
              label: "Transition",
              text: "${(after.soundVolume * 100).round()}%",
              value: after.soundVolume,
              initial: 0.5,
              min: 0,
              max: 1,
              accent: _sceneColour,
              ink: skin.ink,
              onChanged: (v, {transient = false}) {
                c.beginInteraction();
                c.setSceneTransition(index, after.copyWith(soundVolume: v),
                    transient: true);
                if (!transient) c.endInteraction();
              },
              onCommit: c.endInteraction,
            ),
          PackWide(Text(
              sound
                  ? "Gives way with ${after.soundName.isEmpty ? "a sound" : after.soundName}"
                  : last
                      ? "The last ${doc.kind.one}: nothing after it"
                      : "Its transition plays no sound",
              key: const ValueKey("sceneSoundSays"),
              maxLines: 2,
              style: TextStyle(fontSize: 10.5, color: theme.studio.muted))),
        ]),
      ],
      display: CustomPaint(
        key: const ValueKey("sceneSoundScreen"),
        painter: _SumScreen([
          for (var (k, n) in rows) (n, (levels[k] ?? (-90.0, -90.0)).$1),
        ], "everything in $name, summed", theme.studio),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _BusSourceDevice is where a return's or the master's sound comes from,
/// as the prototype's From sends and Every channel: each channel sending to
/// the return (by how much), or everything summed into the master, with its
/// level now.
class _BusSourceDevice extends StatelessWidget {
  final CanvasController controller;

  /// ret is the return it starts; null, the master.
  final ReturnChannel? ret;
  final Map<String, (double, double)> levels;
  final MixerLook theme;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const _BusSourceDevice(
      {required this.controller,
      required this.ret,
      required this.levels,
      required this.theme,
      required this.folded,
      required this.onFold,
      required this.height});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var skin = DeviceSkin.studio(theme.studio);
    var r = ret;
    String db(double v) {
      var sign = v > 0
          ? "+"
          : v < 0
              ? "−"
              : "";
      return "$sign${v.abs().toStringAsFixed(v.abs() < 10 ? 1 : 0)} dB";
    }

    var rows = r != null
        ? <(String, String)>[
            for (var ch in c.timelineChannels)
              if (ch.mix.sendDb(r.id) case var sent?)
                (ch.key, "${ch.name}  ${db(sent)}"),
          ]
        : <(String, String)>[
            for (var ch in c.timelineChannels) (ch.key, ch.name),
            for (var x in c.document.returns) (x.id, x.name),
            if (levels.containsKey(sceneBusKey)) (sceneBusKey, "Scene bus"),
          ];
    var master = r == null;
    var accent = master ? const Color(0xFFCFCBDF) : const Color(0xFF3FB08D);
    return DeviceFrame(
      id: "busSource",
      title: master ? "Every channel" : "From sends",
      help: master
          ? "Everything summed into the master: each channel, return and "
              "the scene's bus, with its level now."
          : "What comes into this return: each channel that sends to it, "
              "and by how much. A channel's send is set on its strip.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 260,
      height: height,
      icon: master ? Icons.merge_type : Icons.call_received,
      accent: accent,
      summary: rows.isEmpty
          ? (master ? "Nothing heard yet" : "Nothing sends to it")
          : "${rows.length} ${master ? "summed" : "sending"}",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      display: CustomPaint(
        key: const ValueKey("busSourceScreen"),
        painter: _SumScreen([
          for (var (k, n) in rows) (n, (levels[k] ?? (-90.0, -90.0)).$1),
        ], master ? "every channel, summed" : "sent to ${r.name}", theme.studio,
            empty: master
                ? "Nothing heard yet"
                : "Nothing sends to it: turn up a channel's send"),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _SumScreen is a bar for each of [rows] -- a name and its level now, in
/// dB -- as the prototype's Sum view draws them.
class _SumScreen extends CustomPainter {
  final List<(String, double)> rows;
  final String caption;
  final StudioColors studio;

  /// empty is what it says with nothing to show.
  final String empty;
  _SumScreen(this.rows, this.caption, this.studio,
      {this.empty = "Nothing heard in it yet"});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var shown = rows.take(7).toList();
    var room = size.height - 22;
    var each = shown.isEmpty ? 0.0 : math.min(20.0, room / shown.length);
    for (var (i, (name, db)) in shown.indexed) {
      var y = 6 + i * each;
      var u = ((db + 60) / 60).clamp(0.0, 1.0);
      var bar = Rect.fromLTWH(8, y + 2, 10, each - 4);
      canvas.drawRect(bar, Paint()..color = studio.edge);
      canvas.drawRect(
          Rect.fromLTRB(
              bar.left, bar.bottom - bar.height * u, bar.right, bar.bottom),
          Paint()..color = const Color(0xFF3FB08D));
      var tp = paintedLabel(name, TextStyle(fontSize: 10, color: studio.text),
          maxWidth: size.width - 34);
      tp.paint(canvas, Offset(26, y + (each - tp.height) / 2));
    }
    var tp = paintedLabel(shown.isEmpty ? empty : caption,
        TextStyle(fontSize: 10, color: studio.muted),
        maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_SumScreen old) => true;
}

/// _BusOutputDevice is where a bus's chain ends -- a scene's, or a
/// return's: its level now, its fader, and where it goes.
class _BusOutputDevice extends StatelessWidget {
  final String id;
  final ChannelMix mix;
  final (double, double) level;
  final String to;
  final MixerLook theme;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final void Function(ChannelMix next, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const _BusOutputDevice(
      {required this.id,
      required this.mix,
      required this.level,
      required this.to,
      required this.theme,
      required this.folded,
      required this.onFold,
      required this.height,
      required this.onChanged,
      required this.onCommit});

  @override
  Widget build(BuildContext context) {
    var skin = DeviceSkin.studio(theme.studio);
    var s = theme.studio;
    return DeviceFrame(
      id: id,
      title: "Output",
      help: "Where this bus's chain ends: how loud it goes on, and where to.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 190,
      height: height,
      icon: Icons.output,
      accent: const Color(0xFFCFCBDF),
      summary: "${mix.gainDb.toStringAsFixed(1)} dB → $to",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        DevicePack(key: ValueKey("$id-pack"), children: [
          DeviceKnob(
            key: ValueKey("$id-level"),
            label: "Level",
            text: "${mix.gainDb.toStringAsFixed(1)} dB",
            value: mix.gainDb,
            initial: 0,
            min: -60,
            max: 6,
            accent: const Color(0xFFCFCBDF),
            ink: skin.ink,
            onChanged: (v, {transient = false}) => onChanged(
                mix.copyWith(gainDb: (v * 10).roundToDouble() / 10),
                transient: transient),
            onCommit: onCommit,
          ),
          PackWide(Row(children: [
            Text("To", style: TextStyle(fontSize: 10.5, color: s.muted)),
            const Spacer(),
            Text(to,
                key: ValueKey("$id-to"),
                style: TextStyle(fontSize: 10.5, color: s.text)),
          ])),
        ]),
      ],
      display: CustomPaint(
        key: ValueKey("$id-meter"),
        painter: _PairMeter(level, s),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _PairMeter is a left and right level, in dB.
class _PairMeter extends CustomPainter {
  final (double, double) level;
  final StudioColors studio;
  _PairMeter(this.level, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var w = math.min(14.0, size.width / 5);
    for (var (i, db) in [level.$1, level.$2].indexed) {
      var u = ((db + 60) / 60).clamp(0.0, 1.0);
      var x = size.width / 2 - w - 2 + i * (w + 4);
      var full = Rect.fromLTWH(x, 8, w, size.height - 16);
      canvas.drawRect(full, Paint()..color = studio.edge);
      canvas.drawRect(
          Rect.fromLTRB(x, full.bottom - full.height * u, x + w, full.bottom),
          Paint()
            ..color =
                db > -1 ? const Color(0xFFE5534B) : const Color(0xFF3FB08D));
    }
  }

  @override
  bool shouldRepaint(_PairMeter old) => old.level != level;
}

/// _LoudnessDevice is the master's loudness, as the chain prototype has it:
/// on its screen the momentary, short-term and integrated readings of what
/// leaves the master against the target -- or, Whole song, the timeline
/// measured as an export would be -- with the Target, what it is aimed for,
/// and whether an export is brought to it.
class _LoudnessDevice extends StatefulWidget {
  final CanvasController controller;
  final MasterMix mix;
  final Loudness? measured;
  final bool measuring;
  final VoidCallback onMeasure;
  final MixerLook theme;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const _LoudnessDevice(
      {required this.controller,
      required this.mix,
      required this.measured,
      required this.measuring,
      required this.onMeasure,
      required this.theme,
      required this.folded,
      required this.onFold,
      required this.height});

  @override
  State<_LoudnessDevice> createState() => _LoudnessDeviceState();
}

class _LoudnessDeviceState extends State<_LoudnessDevice> {
  /// _whole is whether the screen shows the whole song, measured, rather
  /// than what is playing now.
  bool _whole = false;

  void _write(MasterMix m, {bool transient = false}) {
    var c = widget.controller;
    c.beginInteraction();
    c.setMasterMix(m, transient: true);
    if (!transient) c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.controller;
    var m = widget.mix;
    var s = widget.theme.studio;
    var skin = DeviceSkin.studio(s);
    var (icon, accent) = deviceGroupLook(DeviceGroup.analysers);
    var now = c.loudness(mixerMasterKey);
    var measured = widget.measured;
    // The aims offered, with what it is set to if it is none of them.
    var aims = loudnessOptions(m.target);
    return DeviceFrame(
      id: "loudness",
      title: "Loudness",
      help: "How loud the mix is, as broadcast meters read it: momentary "
          "(the last 400 ms), short-term (the last three seconds) and "
          "integrated (all of it, since it began), against the target. "
          "Whole song plays the timeline through the mix into the meter, as "
          "an export would.",
      skin: skin,
      icon: Icons.insights,
      accent: accent,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 320,
      height: widget.height,
      besideDisplay: 220,
      besideSettings: 200,
      summary: "${m.target.round()} LUFS target",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        DevicePack(key: const ValueKey("loudnessPack"), children: [
          DeviceKnob(
            key: const ValueKey("loudnessTargetKnob"),
            label: "Target",
            text: "${m.target.round()} LUFS",
            value: m.target,
            initial: -16,
            min: -36,
            max: -6,
            accent: accent,
            ink: skin.ink,
            onChanged: (v, {transient = false}) => _write(
                m.copyWith(target: v.roundToDouble()),
                transient: transient),
            onCommit: c.endInteraction,
          ),
          StudioDrop<double>(
            key: const ValueKey("loudnessTarget"),
            label: "Aim for",
            value: m.target,
            options: [for (var (v, label) in aims) (v, label)],
            onChanged: (v) => _write(m.copyWith(target: v)),
          ),
          StudioDrop<bool>(
            key: const ValueKey("loudnessNormalise"),
            label: "An export",
            value: m.normalise,
            options: const [(false, "As it is"), (true, "Brought to it")],
            onChanged: (v) => _write(m.copyWith(normalise: v)),
          ),
          PackWide(Wrap(spacing: 5, runSpacing: 5, children: [
            _SmallButton(
                key: const ValueKey("measure"),
                label: widget.measuring ? "Measuring…" : "Measure the song",
                onTap: widget.measuring
                    ? null
                    : () {
                        setState(() => _whole = true);
                        widget.onMeasure();
                      }),
            _SmallButton(
                key: const ValueKey("loudnessReset"),
                label: "Start again",
                onTap: () => c.resetLoudness(mixerMasterKey)),
          ])),
        ]),
      ],
      display: Stack(fit: StackFit.expand, children: [
        CustomPaint(
          key: const ValueKey("loudnessScreen"),
          painter: _LoudnessScreen(
              _whole
                  ? (
                      m: double.negativeInfinity,
                      s: double.negativeInfinity,
                      i: measured?.integrated ?? double.negativeInfinity,
                      peak: measured?.truePeak ?? double.negativeInfinity,
                    )
                  : (
                      m: now?.momentary ?? double.negativeInfinity,
                      s: now?.shortTerm ?? double.negativeInfinity,
                      i: now?.integrated ?? double.negativeInfinity,
                      peak: now?.truePeak ?? double.negativeInfinity,
                    ),
              m.target,
              m.ceilingDb,
              _whole && measured == null
                  ? "Measure plays the timeline through the mix"
                  : null,
              accent,
              s),
          child: const SizedBox.expand(),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var (whole, label) in const [
              (false, "Now"),
              (true, "Whole song")
            ])
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: _SmallButton(
                    key: ValueKey("loudnessView-${whole ? "whole" : "now"}"),
                    label: label,
                    on: _whole == whole,
                    onTap: () => setState(() => _whole = whole)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// _SmallButton is a small button on a card, lit when [on].
class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool on;
  const _SmallButton(
      {required this.label, required this.onTap, this.on = false, super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Material(
      color: on ? s.raised : s.raised.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: on ? s.text : s.edge)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10, color: onTap == null ? s.muted : s.text)),
        ),
      ),
    );
  }
}

/// _LoudnessScreen is three bars -- momentary, short-term, integrated --
/// from −48 to 0 LUFS, the target dashed across them, and the true peak.
class _LoudnessScreen extends CustomPainter {
  final ({double m, double s, double i, double peak}) reading;
  final double target, ceiling;
  final String? say;
  final Color accent;
  final StudioColors studio;
  _LoudnessScreen(this.reading, this.target, this.ceiling, this.say,
      this.accent, this.studio);

  static const _floor = -48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var top = 26.0, bottom = size.height - 22;
    double y(double lufs) =>
        bottom - (bottom - top) * ((lufs - _floor) / -_floor).clamp(0.0, 1.0);
    // The target, dashed across.
    var ty = y(target);
    var dash = Paint()
      ..color = const Color(0xFFE2B04A)
      ..strokeWidth = 1;
    for (var x = 6.0; x < size.width - 6; x += 8) {
      canvas.drawLine(
          Offset(x, ty), Offset(math.min(x + 4, size.width - 6), ty), dash);
    }
    var bars = [("M", reading.m), ("S", reading.s), ("I", reading.i)];
    var w = (size.width - 24) / 3;
    for (var (k, (label, v)) in bars.indexed) {
      var x = 12 + k * w;
      var col = Rect.fromLTRB(x + w * 0.2, top, x + w * 0.8, bottom);
      canvas.drawRect(col, Paint()..color = studio.edge.withValues(alpha: 0.5));
      if (v.isFinite) {
        var over = v > target + 1;
        canvas.drawRect(
            Rect.fromLTRB(col.left, y(v), col.right, bottom),
            Paint()
              ..color = over
                  ? const Color(0xFFE5534B)
                  : k == 2
                      ? accent
                      : const Color(0xFF3FB08D));
      }
      var tp = paintedLabel("$label ${v.isFinite ? v.toStringAsFixed(1) : "–"}",
          TextStyle(fontSize: 9.5, color: studio.muted));
      tp.paint(canvas, Offset(x + (w - tp.width) / 2, bottom + 4));
    }
    var line = say ??
        "target ${target.round()} · true peak "
            "${reading.peak.isFinite ? reading.peak.toStringAsFixed(1) : "–"} dBTP";
    var tp = paintedLabel(
        line,
        TextStyle(
            fontSize: 10,
            color: reading.peak > ceiling
                ? const Color(0xFFE5534B)
                : studio.muted),
        maxWidth: size.width - 120);
    tp.paint(canvas, const Offset(6, 7));
  }

  @override
  bool shouldRepaint(_LoudnessScreen old) => true;
}
