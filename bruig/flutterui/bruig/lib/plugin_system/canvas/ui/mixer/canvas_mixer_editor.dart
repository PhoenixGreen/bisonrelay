part of 'canvas_mixer.dart';

// The device chain of the strip picked: its devices, the slots to add one, and
// the strip's own settings. Part of _CanvasMixerState: its fields, lifecycle
// and build are in canvas_mixer.dart.

extension _MixerEditor on _CanvasMixerState {
  /// _editor is [key]'s effects as a chain, left to right in the order the
  /// sound goes through them, scrolling sideways: for a channel its EQ and
  /// compressor in the order set, what it ducks, its level, and the
  /// master's; for the master its EQ and glue, the limiter, the loudness
  /// and its level.
  Widget _editor(MixerLook theme, String key, TimelineChannel? lane) {
    var master = controller.document.masterMix;
    var isMaster = key == _master;
    var isScene = key == sceneBusKey;
    var channel = isMaster ? null : key;
    var folded = controller.foldedDevices;
    return LayoutBuilder(builder: (context, room) {
      var h = math.max(120.0, room.maxHeight - 14);
      Widget device(String id,
              Widget Function(bool folded, VoidCallback onFold) make) =>
          KeyedSubtree(
            key: _deviceKey(key, id),
            child: make(folded.contains(id),
                () => controller.foldDevice(id, !folded.contains(id))),
          );
      var eq = device(
          "eq",
          (f, fold) => EqDevice(
              controller: controller,
              channel: channel,
              folded: f,
              onFold: fold,
              height: h));
      var comp = device(
          "comp",
          (f, fold) => CompDevice(
              controller: controller,
              channel: channel,
              folded: f,
              onFold: fold,
              height: h));
      // deviceAt is device [i] of the strip's own: a screen or knobs.
      Widget deviceAt(int i) => device(
          deviceKey(deviceIdAt(controller.devicesOf(key), i)),
          (f, fold) => listensOnly(controller.devicesOf(key)[i].kind)
              ? ListenerDevice(
                  controller: controller,
                  owner: key,
                  index: i,
                  folded: f,
                  onFold: fold,
                  height: h)
              : ParamDevice(
                  controller: controller,
                  owner: key,
                  index: i,
                  folded: f,
                  onFold: fold,
                  height: h));
      var ret = isMaster ? null : controller.returnOf(key);
      var skin = DeviceSkin.themed(theme.colors);
      // A clip's editor or a part's piano roll, first in the strip.
      var clipHere =
          controller.clipEditorShown && controller.clipEditing?.channel == key;
      var rollHere = controller.pianoRollShown &&
          controller.pianoRoll?.row == null &&
          controller.pianoRoll?.channel == key;
      var pitchHere = controller.pitchShown && lane != null;
      var instrumentHere = controller.instrumentShown &&
          lane != null &&
          controller.instrumentChannel(key);
      // The channel's Speech: its script, takes and voice -- what makes its
      // clips, not a step of its chain -- as wide as the panel.
      var speechHere = controller.speechShown && lane != null;
      // An editor opened from the Chain's tabs fills the panel, the chain
      // the rail under it.
      var editorId = instrumentHere
          ? "instrument"
          : pitchHere
              ? "pitch"
              : speechHere
                  ? "speech"
                  : clipHere
                      ? "clip"
                      : rollHere
                          ? "roll"
                          : null;
      Widget? editor = switch (editorId) {
        "instrument" => InstrumentEditor(controller: controller, channel: key),
        "pitch" => PitchEditor(controller: controller, channel: key),
        "speech" => controller.speechOf(key) == null
            ? LayoutBuilder(
                builder: (context, box) => Center(
                      child: VoiceStartCard(
                          key: const ValueKey("speechStart"),
                          controller: controller,
                          channel: key,
                          height: math.min(300.0, box.maxHeight - 16)),
                    ))
            : SpeechDevice(
                controller: controller,
                channel: key,
                folded: false,
                onFold: () {},
                height: h,
                editor: true),
        // Every column of its settings where there is room for them; one
        // at a time where not.
        "clip" => LayoutBuilder(
            builder: (context, box) => ClipEditor(
                controller: controller,
                wide: controller.editorWide && _CanvasMixerState._roomForAll(box),
                canWiden: _CanvasMixerState._roomForAll(box))),
        "roll" => LayoutBuilder(
            builder: (context, box) => ClipEditor(
                controller: controller,
                wide: controller.editorWide && _CanvasMixerState._roomForAll(box),
                canWiden: _CanvasMixerState._roomForAll(box),
                part: true)),
        _ => null,
      };
      if (editor != null) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  key: ValueKey("device-$editorId"),
                  color: theme.studio.panel,
                  child: editor,
                ),
              ),
              _ChainRail(controller: controller, channel: key, theme: theme),
            ]);
      }
      // The chain's Macro, in its own zone at the start: knobs that turn
      // other knobs.
      var macroAt = controller
          .devicesOf(key)
          .indexWhere((d) => d.kind == DeviceKind.macro);
      var chain = <Widget>[
        if (controller.chainMacros &&
            (lane != null || isMaster || isScene || ret != null)) ...[
          chainZone("Macros", const Color(0xFFA7A3B8), h),
          if (macroAt >= 0)
            deviceAt(macroAt)
          else
            _MacrosStart(controller: controller, owner: key, height: h),
        ],
        if (isMaster || (ret != null && lane == null)) ...[
          chainZone("Source", const Color(0xFF3FB08D), h),
          device(
              "busSource",
              (f, fold) => _metered(() => _BusSourceDevice(
                  controller: controller,
                  ret: isMaster ? null : ret,
                  levels: _now,
                  theme: theme,
                  folded: f,
                  onFold: fold,
                  height: h))),
        ],
        if (isScene) ...[
          chainZone("Source", _sceneColour, h),
          device(
              "sceneSound",
              (f, fold) => _metered(() => _SceneSoundDevice(
                  controller: controller,
                  levels: _now,
                  theme: theme,
                  folded: f,
                  onFold: fold,
                  height: h))),
        ],
        // An audio channel's sounds, before anything is done to them.
        if (lane != null &&
            !lane.video &&
            !controller.instrumentChannel(key)) ...[
          chainZone("Source", audioColour, h),
          device(
              "audioClips",
              (f, fold) => AudioClipsDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // A MIDI channel's notes -- its part and its note clips -- then its
        // In and its MIDI effects, before its instrument plays: what comes
        // in, and what is done to the notes.
        if (lane != null && controller.instrumentChannel(key)) ...[
          chainZone("Source", midiColour, h),
          device(
              "noteClips",
              (f, fold) => NoteClipsDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
          // A join between each two note devices shows the notes passing as
          // dots. First, the notes as they come, before MIDI In.
          NoteJoin(
              controller: controller,
              channel: key,
              upto: 0,
              height: h,
              name: "in"),
          chainZone("Before", midiColour, h),
          device(
              "midiIn",
              (f, fold) => MidiInDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
          NoteJoin(controller: controller, channel: key, upto: 0, height: h),
          for (var i = 0;
              i < controller.instrumentOf(key)!.instrument!.effects.length;
              i++) ...[
            device(
                "midi$i",
                (f, fold) => MidiEffectDevice(
                    controller: controller,
                    channel: key,
                    index: i,
                    folded: f,
                    onFold: fold,
                    height: h)),
            NoteJoin(
                controller: controller, channel: key, upto: i + 1, height: h),
          ],
          AddMidiEffectSlot(
              key: const ValueKey("addMidiEffectSlot"),
              controller: controller,
              channel: key,
              height: h),
          chainZone("Generator", midiColour, h),
          device(
              "instrumentCard",
              (f, fold) => InstrumentDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // A voice channel's generator: Speech, chosen from the Add menu's
        // Generators. Its script and takes are the Speech tab's.
        if (lane != null && controller.speechOf(key) != null) ...[
          chainZone("Generator", voiceColour, h),
          device(
              "speechCard",
              (f, fold) => SpeechCard(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h,
                  skin: skin)),
        ],
        // The chain in the order it runs, a join between each two devices,
        // then a way to add another. A Ducker comes first: the dips are made
        // to the channel's sounds as they come in.
        if (lane != null &&
            controller.duckersOf(key).isNotEmpty &&
            !controller.partRemoved(key, stripDucked))
          device(
              "ducked",
              (f, fold) => DuckedDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
        if (lane != null || isMaster || isScene || ret != null) ...[
          chainZone(
              lane != null && controller.instrumentChannel(key)
                  ? "After"
                  : "Effects",
              const Color(0xFF4F8FD6),
              h),
          if (lane != null && controller.vocaliserOf(key) != null)
            device(
                "vocaliser",
                (f, fold) => VocaliserDevice(
                    controller: controller,
                    channel: key,
                    folded: f,
                    onFold: fold,
                    height: h)),
          for (var (i, step) in controller.chainOf(key).indexed) ...[
            // The way to add one where it will go: before the EQ and
            // compressor when they are last (see chainOrder).
            if (i == _CanvasMixerState._addAt(controller.chainOf(key)))
              AddDeviceSlot(
                  key: const ValueKey("addDeviceSlot"),
                  controller: controller,
                  owner: key,
                  height: h),
            // A part of the strip taken out is not shown, nor its meter.
            if (!controller.partRemoved(key, step)) _junction(i, h, theme, key),
            if (controller.partRemoved(key, step))
              const SizedBox.shrink()
            else if (step == chainEq)
              eq
            else if (step == chainComp)
              comp
            else if (deviceIndexOf(controller.devicesOf(key), step) case var at
                when at >= 0 && at != macroAt)
              deviceAt(at),
          ],
          _junction(controller.chainOf(key).length, h, theme, key),
          if (_CanvasMixerState._addAt(controller.chainOf(key)) == controller.chainOf(key).length)
            AddDeviceSlot(
                key: const ValueKey("addDeviceSlot"),
                controller: controller,
                owner: key,
                height: h),
        ],
        if (lane != null && !controller.partRemoved(key, stripDuck))
          device(
              "duck",
              (f, fold) => DuckDevice(
                  controller: controller,
                  channel: key,
                  folded: f,
                  onFold: fold,
                  height: h)),
        if (isMaster) ...[
          device(
              "limiter",
              (f, fold) => _metered(() => LimiterDevice(
                  controller: controller,
                  folded: f,
                  onFold: fold,
                  height: h,
                  reductionDb: (_now[limitKey] ?? (0.0, 0.0)).$1))),
          device(
              "loudness",
              (f, fold) => _LoudnessDevice(
                    controller: controller,
                    mix: master,
                    measured: _measured,
                    measuring: _measuring,
                    onMeasure: _measure,
                    theme: theme,
                    folded: f,
                    onFold: fold,
                    height: h,
                  )),
          device(
              "output",
              (f, fold) => _metered(() => _MasterOutputDevice(
                    controller: controller,
                    levels: [
                      for (var c = 0;
                          c < controller.document.audio.speakers.channels;
                          c++)
                        (_now[speakerLevelKey(c)] ?? (-90.0, -90.0)).$1
                    ],
                    theme: theme,
                    skin: skin,
                    folded: f,
                    onFold: fold,
                    height: h,
                  ))),
        ],
        // Where it is heard from, big enough to place it by: the room, its
        // speakers and the channel among them, stereo or surround.
        if (lane != null || ret != null)
          chainZone("Output", const Color(0xFFCFCBDF), h),
        if (lane != null || ret != null)
          device("panner", (f, fold) {
            // A channel's pan as it plays now: see mixNow.
            var mix = lane != null ? controller.mixNow(lane) : ret!.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              if (lane != null) {
                controller.changeChannelMix(lane, mix, next,
                    transient: true, anywhere: true);
              } else {
                controller.setReturn(ret!.copyWith(mix: next), transient: true);
              }
              if (!transient) controller.endInteraction();
            }

            return _PannerDevice(
              channel: key,
              mix: mix,
              theme: theme,
              skin: skin,
              folded: f,
              onFold: fold,
              height: h,
              onChanged: write,
              onCommit: controller.endInteraction,
            );
          }),
        if (lane != null)
          device("meter",
              (f, fold) {
            var meter = _Meter(_board, key);
            var mix = lane.mix;
            void write(ChannelMix next, {bool transient = false}) {
              controller.beginInteraction();
              controller.setChannelMix(lane, next,
                  transient: true, anywhere: true);
              if (!transient) controller.endInteraction();
            }

            void set(double db, {bool transient = false}) =>
                write(mix.copyWith(gainDb: db), transient: transient);

            var to = mix.output.isEmpty
                ? "Master"
                : controller.document.returns
                        .where((r) => r.id == mix.output)
                        .firstOrNull
                        ?.name ??
                    "Master";
            var returns = controller.document.returns;
            var small = TextStyle(fontSize: 10.5, color: theme.studio.muted);
            var value = TextStyle(
                fontSize: 10.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.studio.text);
            return DeviceFrame(
              id: "meter",
              title: "Output",
              skin: skin,
              icon: Icons.speaker,
              accent: const Color(0xFFCFCBDF),
              help: "Where ${lane.name}'s chain ends: its pan, its sends to "
                  "the returns, its fader, mute and solo -- as on the mixer "
                  "-- and where it goes.",
              folded: f,
              onFold: fold,
              width:
                  returns.isEmpty ? 150 : 150 + 52.0 * returns.take(2).length,
              height: h,
              foldedBody: CustomPaint(
                  key: const ValueKey("meterFolded"),
                  painter: _MeterPainter(meter, theme.studio)),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(children: [
                  _PanControl(
                    channel: lane.key,
                    mix: mix,
                    theme: theme,
                    onChanged: (m, {transient = false}) =>
                        write(m, transient: transient),
                    onCommit: controller.endInteraction,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _Toggle(
                          key: const ValueKey("meterMute"),
                          label: "M",
                          on: mix.mute,
                          onColor: theme.studio.arm,
                          theme: theme,
                          tooltip: "Mute: silent here and in exports",
                          onTap: () => write(mix.copyWith(mute: !mix.mute))),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _Toggle(
                          key: const ValueKey("meterSolo"),
                          label: "S",
                          on: controller.solo.contains(key),
                          onColor: theme.studio.solo,
                          theme: theme,
                          tooltip: "Solo: hear only this, while you listen",
                          onTap: () => controller.toggleSolo(key)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _Fader(
                      db: mix.gainDb,
                      meter: meter,
                      theme: theme,
                      wide: true,
                      onChanged: set,
                      onCommit: controller.endInteraction,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DbReading(
                      db: mix.gainDb,
                      textKey: const ValueKey("meterReading"),
                      onSet: (db) => set(db),
                      style: TextStyle(
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colors.onSurface)),
                  if (returns.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var r in returns.take(2))
                            SizedBox(
                              width: 50,
                              child: DeviceKnob(
                                key: ValueKey("outputSend-${r.id}"),
                                label: "Send ${r.name}",
                                text: (mix.sends[r.id] ?? -60) <= -60
                                    ? "off"
                                    : "${mix.sends[r.id]!.toStringAsFixed(1)} dB",
                                value: mix.sends[r.id] ?? -60,
                                initial: -60,
                                min: -60,
                                max: 6,
                                size: 24,
                                accent: const Color(0xFF9A92EA),
                                ink: theme.studio.text,
                                onChanged: (v, {transient = false}) => write(
                                    mix.copyWith(
                                        sends: {
                                      ...mix.sends,
                                      r.id: (v * 2).roundToDouble() / 2,
                                    }..removeWhere((_, db) => db <= -60)),
                                    transient: transient),
                                onCommit: controller.endInteraction,
                              ),
                            ),
                        ]),
                  ],
                  const SizedBox(height: 4),
                  Row(children: [
                    Text("Peak", style: small),
                    const Spacer(),
                    // Read again as the meters move, not the card.
                    ListenableBuilder(
                        listenable: _board,
                        builder: (context, _) {
                          var peak = meter.peak;
                          return Text(
                              peak.$1 <= -80 && peak.$2 <= -80
                                  ? "−∞"
                                  : "${math.max(peak.$1, peak.$2).toStringAsFixed(1)} dB",
                              key: const ValueKey("outputPeak"),
                              style: value);
                        }),
                  ]),
                  Row(children: [
                    Text("To", style: small),
                    const Spacer(),
                    Flexible(
                      child: Text(to,
                          key: const ValueKey("outputTo"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: value),
                    ),
                  ]),
                ]),
              ),
            );
          }),
        if (isScene || (ret != null && lane == null)) ...[
          if (isScene) chainZone("Output", const Color(0xFFCFCBDF), h),
          device("busOutput", (f, fold) {
            var mix = isScene ? controller.sceneBus : ret!.mix;
            return _metered(() => _BusOutputDevice(
              id: "busOutput",
              mix: mix,
              level: _now[key] ?? (-90.0, -90.0),
              to: "Master",
              theme: theme,
              folded: f,
              onFold: fold,
              height: h,
              onChanged: (next, {transient = false}) {
                controller.beginInteraction();
                if (isScene) {
                  controller.setSceneBus(next, transient: true);
                } else {
                  controller.setReturn(ret!.copyWith(mix: next),
                      transient: true);
                }
                if (!transient) controller.endInteraction();
              },
              onCommit: controller.endInteraction,
            ));
          }),
        ],
        // The master's own meter, on its chain only: other chains end at
        // their Output.
        if (isMaster)
          device(
              "masterMeter",
              (f, fold) => MeterDevice(
                  controller: controller,
                  channel: null,
                  id: "masterMeter",
                  title: "Master meter",
                  folded: f,
                  onFold: fold,
                  height: h)),
      ];
      var inside = ScrollConfiguration.of(context);
      return Align(
        alignment: Alignment.topLeft,
        // By the wheel and the trackpad, not by a drag: a drag in a device (a
        // note drawn, a point moved) is the device's.
        child: ScrollConfiguration(
          behavior: inside.copyWith(
              scrollbars: false, dragDevices: {PointerDeviceKind.trackpad}),
          child: SingleChildScrollView(
            key: const ValueKey("effectsChain"),
            controller: _chainScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Each wrapper keyed as its device: matched by place, a device
              // put in ahead would move the rest to other wrappers, and a
              // showing tooltip moved that way asserts.
              for (var (i, d) in chain.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                ScrollConfiguration(
                    key: d.key == null ? null : ValueKey(d.key),
                    behavior: inside,
                    child: d),
              ],
            ]),
          ),
        ),
      );
    });
  }
}
