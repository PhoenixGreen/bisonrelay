part of 'mixer_plugins.dart';

// ParamDevice, a device drawn from its kind's table of settings. Part of
// mixer_plugins.dart.

/// ParamDevice is a device drawn from its kind's table of settings.
class ParamDevice extends StatelessWidget {
  final CanvasController controller;

  /// owner is the strip it is on: see CanvasController.devicesOf.
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

  /// _range is how a knob turns for [p]: log for times and frequencies.
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
    var lane =
        controller.timelineChannels.where((c) => c.key == owner).firstOrNull;
    var automated = {
      for (var l in lane?.mix.automation ?? const <AutomationLane>[])
        if (l.points.isNotEmpty) l.target
    };
    var held = controller.overridden[owner] ?? const <String>{};
    var moved = {
      for (var d in devices)
        if (d.on && d.kind.modulates)
          for (var m in d.mods)
            if (m.device == deviceIdAt(devices, index)) m.param,
    };
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
    List<(String, VoidCallback)> knobMenu(DeviceParam p) {
      var me = deviceIdAt(devices, index);
      // On every strip: an LFO of its own, a macro's knob, and reset.
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
    // Tall with text at size, Notes to MIDI is a button at its foot;
    // otherwise an icon on its bar, leaving the screen the room.
    var roomy = DeviceTier.of(height) == DeviceTier.large &&
        MediaQuery.textScalerOf(context).scale(10) <= 12;
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

    // A setting that is one of a few (a filter's type, an LFO's shape) is
    // a dropdown, not a knob.
    bool listed(DeviceParam p) =>
        paramShown(device, p) &&
        device.kind != DeviceKind.split &&
        device.kind != DeviceKind.macro &&
        !(autoTune && (p.id == "key" || p.id == "scale"));
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
          // Short, its knobs only; medium or with large text, key and scale
          // as lists on one row; tall, rows of buttons.
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
          if (device.kind == DeviceKind.split)
            SplitBranches(
              key: ValueKey("splitBranches-$index"),
              device: device,
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
          // A macro's random knobs, and its settings kept as variations.
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
          // A gate or follower listens to its own sound or another channel's.
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
        if (device.kind.worksOnSides)
          worksOnMenu(look,
              id: "deviceStereo-$index",
              value: device.value("stereo").round(),
              onPick: (k) => write(device.withValue("stereo", k.toDouble()))),
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
      width: device.kind == DeviceKind.split
          ? SplitBranches.width
          : device.kind == DeviceKind.macro
              ? MacroPanel.width
              : autoTune
              ? _autoTuneWidth
              : math.max(240.0, 24.0 + 72 * columns),
      height: height,
      actions: [
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
                  channel: owner,
                  // Read at its place in the chain, after any EQ or compressor.
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

  /// _sourceChannel is which channel a device listens to beside its own: a
  /// vocoder's carrier (an instrument playing chords, muted so only the
  /// vocoder is heard) or, with [itself], a gate's key, "" for its own.
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
