part of 'canvas_mixer.dart';

// The chain under an open effects editor: its rail, the zones marking where
// each part begins, the empty Macros start, and the master's Output device with
// its speaker meters. Part of canvas_mixer.dart.

/// _ChainRail is the chain under an open editor: "Chain" back to it, then a
/// chip per step, pressed to open the chain on that step.
class _ChainRail extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final MixerLook theme;
  const _ChainRail(
      {required this.controller, required this.channel, required this.theme});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var studio = theme.studio;
    var steps = <(String, String, Color, bool)>[];
    if (c.instrumentOf(channel)?.instrument case var part?) {
      steps.add(("midiIn", "MIDI In", midiColour, true));
      for (var (i, e) in part.effects.indexed) {
        steps.add(("midi$i", e.kind.label, midiColour, e.on));
      }
      steps.add(("instrumentCard", "Instrument", midiColour, true));
    }
    var devices = c.devicesOf(channel);
    for (var step in c.chainOf(channel)) {
      if (step == chainEq) {
        steps.add(("eq", "EQ", const Color(0xFF9A92EA), true));
      } else if (step == chainComp) {
        steps.add((
          "comp",
          "Compressor",
          deviceGroupLook(DeviceGroup.dynamics).$2,
          true
        ));
      } else if (deviceIndexOf(devices, step) case var at when at >= 0) {
        var d = devices[at];
        steps.add((
          deviceKey(step),
          d.kind.label,
          deviceGroupLook(d.kind.group).$2,
          d.on
        ));
      }
    }
    steps.add(("panner", "Output", const Color(0xFFCFCBDF), true));
    Widget chip(String id, String name, Color colour, bool on) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: InkWell(
            key: ValueKey("railChip-$id"),
            borderRadius: BorderRadius.circular(5),
            onTap: () {
              c.closeEditor();
              c.openEffects(channel, device: id);
            },
            child: Opacity(
              opacity: on ? 1 : 0.45,
              child: Container(
                height: 22,
                padding: const EdgeInsets.fromLTRB(4, 0, 7, 0),
                decoration: BoxDecoration(
                  color: studio.raised,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: studio.edge),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                          color: colour,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text(name,
                      style: TextStyle(fontSize: 10.5, color: studio.muted)),
                ]),
              ),
            ),
          ),
        );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: studio.panel,
        border: Border(top: BorderSide(color: studio.edge)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          InkWell(
            key: const ValueKey("editorClose"),
            borderRadius: BorderRadius.circular(5),
            onTap: c.closeEditor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text("Chain",
                  style: TextStyle(fontSize: 11, color: studio.text)),
            ),
          ),
          const SizedBox(width: 4),
          for (var (id, name, colour, on) in steps) chip(id, name, colour, on),
        ]),
      ),
    );
  }
}

/// _MacrosStart is the Macros zone of a chain with no Macro yet: a narrow
/// dashed "+" that adds one.
class _MacrosStart extends StatelessWidget {
  final CanvasController controller;
  final String owner;
  final double height;
  const _MacrosStart(
      {required this.controller, required this.owner, required this.height});

  @override
  Widget build(BuildContext context) => DashedAddButton(
        key: const ValueKey("macrosAdd"),
        tip: "Add macros: eight knobs, each turning any knobs of this "
            "chain you give it",
        height: height,
        onTap: () {
          controller.beginInteraction();
          controller.setDevicesOf(owner, [
            ...controller.devicesOf(owner),
            const MixDevice(DeviceKind.macro),
          ]);
          controller.endInteraction();
        },
      );
}

/// chainZone marks where a part of a chain begins: its name up the side, a
/// line of [colour] beside it.
Widget chainZone(String label, Color colour, double height) => Builder(
      builder: (context) {
        var look = MixerLook.of(context);
        return Container(
          key: ValueKey("chainZone-$label"),
          width: 16,
          height: height,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colour, width: 2))),
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(label.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                    fontSize: 9, letterSpacing: 1.1, color: look.studio.muted)),
          ),
        );
      },
    );

/// _MasterOutputDevice is the master's Output, last in its chain: the
/// speakers the piece is mixed for (stereo, 5.1 or 7.1), a meter for each,
/// and -- in surround, which the editor plays folded down to two -- which
/// of them are heard here, everything or one group alone.
class _MasterOutputDevice extends StatelessWidget {
  final CanvasController controller;

  final List<double> levels;
  final MixerLook theme;
  final DeviceSkin skin;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const _MasterOutputDevice({
    required this.controller,
    required this.levels,
    required this.theme,
    required this.skin,
    required this.folded,
    required this.onFold,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    var audio = controller.document.audio;
    var master = controller.document.masterMix;
    var layout = audio.speakers;
    var hear = controller.hear;
    var small = TextStyle(fontSize: 11, color: skin.ink.withValues(alpha: 0.7));
    return DeviceFrame(
      id: "output",
      accent: const Color(0xFFCFCBDF),
      help: "What the piece is mixed for: two speakers, 5.1 or 7.1, with a "
          "meter for each. Surround is heard here folded down to two; Hear "
          "plays one group of speakers alone, to check what goes where. "
          "Exports carry the whole mix.",
      title: "Output",
      skin: skin,
      icon: Icons.speaker,
      folded: folded,
      onFold: onFold,
      width: math.max(
          190.0, 70.0 + 26 * layout.channels + (layout.isSurround ? 90 : 60)),
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(layout.label,
              style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: CustomPaint(
              key: const ValueKey("outputMeters"),
              painter: _SpeakerMetersPainter(
                layout: layout,
                levels: levels,
                hear: hear,
                studio: theme.studio,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // The master's Out and its level: the fader at the end.
          Row(children: [
            DeviceKnob(
              key: const ValueKey("outputOut"),
              label: "Out",
              text: "${dbText(master.gainDb)} dB",
              value: master.gainDb.clamp(-24.0, 12.0),
              initial: 0,
              min: -24,
              max: 12,
              size: 30,
              accent: const Color(0xFFCFCBDF),
              ink: skin.ink,
              bipolar: true,
              onChanged: (v, {transient = false}) {
                controller.beginInteraction();
                controller.setMasterMix(
                    controller.document.masterMix
                        .copyWith(gainDb: (v * 10).roundToDouble() / 10),
                    transient: true);
                if (!transient) controller.endInteraction();
              },
              onCommit: controller.endInteraction,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  key: const ValueKey("outputLufs"),
                  switch (controller.loudness(mixerMasterKey)?.shortTerm) {
                    var l? when l.isFinite => "${l.toStringAsFixed(1)} LUFS",
                    _ => "— LUFS",
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
          const SizedBox(height: 6),
          CanvasDropdown<SpeakerLayout>(
            key: const ValueKey("outputSpeakers"),
            label: "Speakers",
            value: layout,
            tight: true,
            width: 150,
            options: [for (var l in SpeakerLayout.values) (l, l.label)],
            onChanged: (l) => controller.setAudio(audio.copyWith(speakers: l)),
          ),
          if (layout.isSurround) ...[
            const SizedBox(height: 6),
            Tooltip(
              message: "Heard here on two speakers: everything folded "
                  "down, as most listeners will hear it, or one group "
                  "alone to check what goes where. What is written is "
                  "the whole mix.",
              child: CanvasDropdown<SpeakerGroup>(
                key: const ValueKey("outputHear"),
                label: "Hear",
                value: hear,
                tight: true,
                width: 150,
                options: [
                  for (var g in SpeakerGroup.values)
                    if (g == SpeakerGroup.all ||
                        layout.speakers.any((s) => g.has(s.$2)))
                      (g, g.label)
                ],
                onChanged: controller.hearSpeakers,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text("Two speakers, as heard here",
                maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
          ],
        ]),
      ),
    );
  }
}

/// _SpeakerMetersPainter draws a meter a speaker, named beneath, those not
/// heard here dimmed.
class _SpeakerMetersPainter extends CustomPainter {
  final SpeakerLayout layout;
  final List<double> levels;
  final SpeakerGroup hear;
  final StudioColors studio;

  _SpeakerMetersPainter({
    required this.layout,
    required this.levels,
    required this.hear,
    required this.studio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var n = layout.channels;
    const foot = 14.0;
    var w = size.width / n;
    var h = size.height - foot;
    if (h <= 4) return;
    for (var (c, (name, deg)) in layout.speakers.indexed) {
      var x = c * w + 3;
      var bar = Rect.fromLTWH(x, 0, w - 6, h);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)),
          Paint()..color = studio.inset);
      var db = c < levels.length ? levels[c] : -90.0;
      var u = ((db + 60) / 60).clamp(0.0, 1.0);
      var heard = hear.has(deg);
      var colour = db > -1
          ? studio.meterHigh
          : db > -12
              ? studio.meterMid
              : studio.meterLow;
      if (u > 0) {
        canvas.drawRect(Rect.fromLTWH(x, h * (1 - u), w - 6, h * u),
            Paint()..color = colour.withValues(alpha: heard ? 1 : 0.3));
      }
      // Kept, as it is painted at the meters' rate.
      var label = paintedLabel(
          name,
          TextStyle(
              fontSize: 9.5,
              color: studio.muted.withValues(alpha: heard ? 1 : 0.5)),
          maxWidth: w);
      label.paint(canvas, Offset(c * w + (w - label.width) / 2, h + 2));
    }
  }

  @override
  bool shouldRepaint(_SpeakerMetersPainter old) =>
      old.layout != layout ||
      old.hear != hear ||
      old.studio != studio ||
      !_same(old.levels, levels);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.2) return false;
    }
    return true;
  }
}
