part of 'mixer_plugins.dart';

// mixer_midi_devices.dart is a MIDI channel's devices: where its notes come from, and its MIDI effects: part of mixer_plugins.dart, split from it to keep
// that file readable (Ken, 2026-11-12). Its imports are the library's.

// ---- A MIDI channel's devices: where its notes come from, and its MIDI effects

/// MidiInDevice is a MIDI channel's In: which keyboard it takes notes from,
/// and when it plays them -- see MidiMonitor. First in its chain.
class MidiInDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MidiInDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var part = controller.instrumentOf(channel)?.instrument;
    if (part == null) return const SizedBox();
    var look = MixerLook.of(context);
    var skin = DeviceSkin.themed(look.colors);
    var keyboards = [
      for (var d in MidiInput.shared.devices) d.name,
      if (part.input.isNotEmpty &&
          part.input != noInput &&
          !MidiInput.shared.devices.any((d) => d.name == part.input))
        part.input,
    ];
    var armed = controller.armed.contains(channel);
    TextStyle small([Color? c]) =>
        TextStyle(fontSize: 11, color: c ?? skin.ink);
    return DeviceFrame(
      id: "midiIn",
      title: "MIDI In",
      help: "Where the channel's notes come in from: a keyboard, or all of "
          "them. Monitor is when what comes in is heard: always, while the "
          "channel is armed, or never.",
      skin: skin,
      icon: Icons.grid_view,
      accent: midiColour,
      folded: folded,
      onFold: onFold,
      width: 190,
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text("In: ${part.monitor.label}", style: small(skin.dim)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("From", style: small(skin.dim)),
          const SizedBox(height: 2),
          DropdownButton<String>(
            key: const ValueKey("midiFrom"),
            isExpanded: true,
            isDense: true,
            value: part.input,
            style: small(),
            dropdownColor: look.colors.surfaceContainerHigh,
            items: [
              const DropdownMenuItem(value: "", child: Text("All MIDI inputs")),
              for (var k in keyboards)
                DropdownMenuItem(
                    value: k, child: Text(k, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: noInput, child: Text("No input")),
            ],
            onChanged: (v) {
              if (v == null) return;
              controller.setChannelPart(channel, (p) => p.copyWith(input: v));
            },
          ),
          const SizedBox(height: 12),
          Text("Monitor", style: small(skin.dim)),
          const SizedBox(height: 4),
          Row(children: [
            for (var m in MidiMonitor.values) ...[
              Expanded(
                child: Tooltip(
                  message: m.hint,
                  child: Material(
                    color: part.monitor == m
                        ? look.studio.on
                        : look.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      key: ValueKey("midiMonitor-${m.name}"),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => controller.setChannelPart(
                          channel, (p) => p.copyWith(monitor: m)),
                      child: SizedBox(
                        height: 24,
                        child: Center(
                          child: Text(m.label,
                              style: small(part.monitor == m
                                  ? look.studio.onOn
                                  : skin.ink)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (m != MidiMonitor.values.last) const SizedBox(width: 4),
            ],
          ]),
          const SizedBox(height: 12),
          Text(
            switch (part.monitor) {
              MidiMonitor.input => "Plays what comes in, armed or not.",
              MidiMonitor.auto => armed
                  ? "Armed: plays what comes in."
                  : "Plays what comes in once it is armed.",
              MidiMonitor.off => "Plays only its clips and its part.",
            },
            style: small(skin.dim),
          ),
          if (MidiInput.shared.device == null) ...[
            const SizedBox(height: 8),
            Text("No keyboard chosen: see the instrument's settings.",
                style: small(skin.dim)),
          ],
          const Spacer(),
          OutlinedButton.icon(
            key: const ValueKey("openPianoRoll"),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: skin.ink,
                textStyle: const TextStyle(fontSize: 11)),
            onPressed: () => controller.openPianoRoll(channel),
            icon: const Icon(Icons.piano, size: 14),
            label: const Text("Piano roll: its part"),
          ),
        ]),
      ),
    );
  }
}

/// MidiEffectDevice is one of a MIDI channel's MIDI effects -- see
/// midi_effects.dart -- as knobs: a choice turned through its choices.
class MidiEffectDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final int index;
  final bool folded;
  final VoidCallback onFold;
  final double height;

  const MidiEffectDevice({
    required this.controller,
    required this.channel,
    required this.index,
    required this.folded,
    required this.onFold,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var part = controller.instrumentOf(channel)?.instrument;
    if (part == null || index >= part.effects.length) return const SizedBox();
    var effect = part.effects[index];
    void write(MidiEffect next, {bool transient = false}) {
      controller.beginInteraction();
      controller.setChannelPart(
          channel,
          (p) => index >= p.effects.length
              ? p
              : p.copyWith(effects: [...p.effects]..[index] = next),
          transient: true);
      if (!transient) controller.endInteraction();
    }

    var params = effect.kind.params;
    void edit(List<MidiEffect> Function(List<MidiEffect>) change) {
      controller.beginInteraction();
      controller.setChannelPart(
          channel,
          (p) => index >= p.effects.length
              ? p
              : p.copyWith(effects: change([...p.effects])));
      controller.endInteraction();
    }

    var abKey = "$channel|midi$index|${effect.kind.name}";
    return DeviceFrame(
      id: "midi$index",
      title: effect.kind.label,
      onDuplicate: () => edit((e) => e..insert(index + 1, e[index])),
      onSavePreset: () =>
          saveDevicePreset(context, effect.kind.label, midi: [effect]),
      onReset: () =>
          edit((e) => e..[index] = MidiEffect(e[index].kind, on: e[index].on)),
      // Kept by its place and kind: another effect moved into its place
      // starts its own A and B.
      onAB: () => controller.toggleABOf(abKey, effect,
          (o) => write((o as MidiEffect).switched(effect.on), transient: true)),
      showingB: controller.showingBOf(abKey),
      help: "Done to the notes before the instrument plays them.",
      skin: DeviceSkin.silver,
      icon: Icons.grid_view,
      accent: midiColour,
      on: effect.on,
      onPower: (v) => write(effect.switched(v)),
      powerKey: ValueKey("midiPower-$index"),
      folded: folded,
      onFold: onFold,
      width: 236,
      height: height,
      actions: [
        IconButton(
          key: ValueKey("midiRemove-$index"),
          tooltip: "Take the ${effect.kind.label.toLowerCase()} out",
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: _headerInkLight),
          onPressed: () {
            controller.beginInteraction();
            controller.setChannelPart(
                channel,
                (p) => index >= p.effects.length
                    ? p
                    : p.copyWith(effects: [...p.effects]..removeAt(index)));
            controller.endInteraction();
          },
        ),
      ],
      foldedBody: const SizedBox(),
      summary: [
        for (var p in params) "${p.label} ${p.reading(effect.value(p.id))}"
      ].join(" · "),
      controls: (tier) => [
        for (var p in params)
          if (!p.isChoice)
            _Knob(
              key: ValueKey("midi-$index-${p.id}"),
              label: p.label,
              text: p.reading(effect.value(p.id)),
              value: effect.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: switch (tier) {
                DeviceTier.large => 46,
                DeviceTier.medium => 38,
                _ => 28,
              },
              reading: tier != DeviceTier.small,
              accent: midiColour,
              onChanged: (v, {transient = false}) =>
                  write(effect.withValue(p.id, v), transient: transient),
              onCommit: controller.endInteraction,
            ),
        // A rate, a mode, a scale: chosen from a list, as a sound device's.
        if (params.any((p) => p.isChoice))
          DevicePack(key: ValueKey("midiChoices-$index"), children: [
            for (var p in params)
              if (p.isChoice)
                StudioDrop<int>(
                  key: ValueKey("midi-$index-${p.id}"),
                  label: p.label,
                  value: effect.choice(p.id).clamp(0, p.choices.length - 1),
                  options: [for (var (i, ch) in p.choices.indexed) (i, ch)],
                  onChanged: (i) => write(effect.withValue(p.id, i.toDouble())),
                ),
          ]),
      ],
      body: const SizedBox(),
    );
  }
}

/// AddMidiEffectSlot puts a MIDI effect on a MIDI channel, after the
/// others, before its instrument: the chain's "+".
class AddMidiEffectSlot extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final double height;

  const AddMidiEffectSlot(
      {required this.controller,
      required this.channel,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    devicePresets.load();
    return ListenableBuilder(
      listenable: devicePresets,
      builder: (context, _) => AddSlot(
        id: "addMidiOpen",
        title: "Add a MIDI effect",
        height: height,
        groups: [
          // Kept with Save as a preset: its MIDI effects, after the rest.
          if (devicePresets.presets.where((p) => presetHolds(p, midi: true))
              case var kept when kept.isNotEmpty)
            (
              "Presets",
              [
                for (var p in kept)
                  (
                    "addPreset-${p.id}",
                    p.name,
                    () => useDevicePreset(controller, channel, p.data),
                  ),
              ]
            ),
          (
            "MIDI effects",
            [
              for (var kind in MidiEffectKind.values)
                (
                  "addMidi-${kind.name}",
                  kind.label,
                  () {
                    controller.beginInteraction();
                    controller.setChannelPart(
                        channel,
                        (p) => p.copyWith(
                            effects: [...p.effects, MidiEffect(kind)]));
                    controller.endInteraction();
                    controller.openEffects(channel,
                        device:
                            "midi${controller.instrumentOf(channel)!.instrument!.effects.length - 1}");
                  }
                ),
            ]
          ),
        ],
      ),
    );
  }
}
