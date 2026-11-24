part of 'canvas_mixer.dart';

// The return, Scenes and master columns, with the Scenes column's join slots
// and its camera half. Part of canvas_mixer.dart.

/// _ReturnStrip is a return: its letter and name; no clips; its devices
/// (each a slot that opens it) with its EQ and compressor, given the room a
/// channel's sends take; and its pan, switch, fader and level.
class _ReturnStrip extends StatelessWidget {
  final String letter;
  final ReturnChannel ret;
  final _Meter meter;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<ReturnChannel> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<String?> onOpen;
  final VoidCallback onRemove;

  final ValueChanged<String>? onRemoveDevice;
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;

  const _ReturnStrip({
    required this.letter,
    required this.ret,
    required this.meter,
    required this.theme,
    required this.bands,
    required this.onChanged,
    required this.onCommit,
    required this.onOpen,
    required this.onRemove,
    this.onRemoveDevice,
    required this.selected,
    required this.onSelect,
    super.key,
    this.narrow = false,
    this.onNarrow,
  });

  /// devicesWanted is how tall its devices band would be to show them all:
  /// each device, an add slot, its EQ and compressor.
  static double devicesWanted(ReturnChannel ret) =>
      _slotsHeight(ret.devices.length + 3);

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var mix = ret.mix;
    void set(ChannelMix next, {bool transient = false}) =>
        onChanged(ret.copyWith(mix: next), transient: transient);
    var body = _StripFrame(
      noMotion: "",
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: ValueKey("narrow-${ret.id}"),
      deviceCount: _chainCount(ret.chainMix.chain, ret.devices),
      selected: selected,
      theme: theme,
      bands: bands,
      head: Row(children: [
        Text("$letter ",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.studio.on)),
        Expanded(
          child: ChannelNameEditor(
              name: ret.name.isEmpty ? "Return" : ret.name,
              theme: ThemeNotifier.of(context),
              color: colors.onSurface,
              onRename: (name) => onChanged(ret.copyWith(name: name)),
              weight: FontWeight.w600,
              textKey: const ValueKey("returnName"),
              fieldKey: const ValueKey("returnNameField")),
        ),
        // Not when narrow: room only for its letter and a little name.
        if (!narrow)
          InkWell(
            key: const ValueKey("removeReturn"),
            onTap: onRemove,
            child: Tooltip(
              message: "Take this return away. What is sent to it is kept "
                  "on the channels, for undo to find.",
              child:
                  Icon(Icons.close, size: 13, color: colors.onSurfaceVariant),
            ),
          ),
      ]),
      // A return plays what is sent to it, not clips of its own.
      clips: () => const SizedBox(),
      devices: () => _band(_slots([
        ..._chainSlots(theme,
            chain: ret.chainMix.chain,
            devices: ret.devices,
            eq: mix.eq,
            comp: mix.comp,
            devicePrefix: "returnDevice",
            eqKey: "returnEq",
            compKey: "returnComp",
            onEq: () => onOpen("eq"),
            onComp: () => onOpen("comp"),
            onDevice: onOpen,
            onRemove: (key) => onRemoveDevice?.call(key)),
        _slot(
            theme,
            "Add a device",
            false,
            Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
            () => onOpen(null),
            key: const ValueKey("returnAddDevice")),
      ])),
      miniMixer: () => _miniMixerBand(theme,
          bare: bands.bare,
          buttons: [
            _onToggle(theme, letter, mix.mute,
                () => set(mix.copyWith(mute: !mix.mute)),
                key: const ValueKey("returnMute"), what: "This return"),
          ],
          db: mix.gainDb,
          meter: meter,
          onDb: (db, {transient = false}) =>
              set(mix.copyWith(gainDb: db), transient: transient),
          onCommit: onCommit),
      mixer: () => _mixerBand(
        narrow: narrow,
        left: _leftColumn(
          pan: _StripPan(
            channel: ret.id,
            mix: mix,
            theme: theme,
            onChanged: (m, {transient = false}) => set(m, transient: transient),
            onCommit: onCommit,
            onOpenPanner: () => onOpen("panner"),
          ),
          on: _onToggle(
              theme, letter, mix.mute, () => set(mix.copyWith(mute: !mix.mute)),
              key: const ValueKey("returnMute"), what: "This return"),
        ),
        fader: _faderOf(
            theme,
            mix.gainDb,
            meter,
            (db, {transient = false}) =>
                set(mix.copyWith(gainDb: db), transient: transient),
            onCommit,
            narrow: narrow),
        reading: DbReading(
            db: mix.gainDb,
            textKey: const ValueKey("returnReading"),
            onSet: (db) => set(mix.copyWith(gainDb: db)),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface)),
      ),
    );
    return Listener(onPointerDown: (_) => onSelect(), child: body);
  }
}

/// _SceneStrip is the Scenes strip (CanvasDocument.scenesBus), one for the
/// whole canvas: the transitions' sounds sum into it on their way to the
/// master; every other sound goes through its own channel. Its devices, EQ
/// and compressor in chain order, its pan and its fader.
class _SceneStrip extends StatelessWidget {
  final String name;
  final ChannelMix mix;
  final List<String> chain;
  final _Meter meter;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<String?> onOpen;
  final ValueChanged<String>? onRemoveDevice;
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;

  /// joins are its slots: a transition each, one per join between scenes,
  /// outside the cue rows; motion its motion half, the scenes' camera.
  final Widget Function()? joins;
  final Widget Function()? motion;

  /// motionLine is its motion over a minimised mixer: how many transitions.
  final Widget Function()? motionLine;

  const _SceneStrip({
    this.motionLine,
    this.joins,
    this.motion,
    required this.name,
    required this.mix,
    required this.chain,
    required this.meter,
    required this.theme,
    required this.bands,
    required this.onChanged,
    required this.onCommit,
    required this.onOpen,
    this.onRemoveDevice,
    required this.selected,
    required this.onSelect,
    super.key,
    this.narrow = false,
    this.onNarrow,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var devices = withDeviceIds(mix.devices);
    const what = "This scene";
    var body = _StripFrame(
      noMotion: "",
      motion: motion,
      motionLine: motionLine,
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: const ValueKey("narrow-scene"),
      deviceCount: _chainCount(chain, devices),
      selected: selected,
      theme: theme,
      bands: bands,
      head: Row(children: [
        Icon(Icons.movie_outlined, size: 13, color: theme.studio.on),
        const SizedBox(width: 4),
        Expanded(
          child: Tooltip(
            message: "Everything heard in $name goes through here on its "
                "way to the master: its channels, its sounds, its "
                "transition's. The master's own sounds go straight there.",
            child: Text(name,
                key: const ValueKey("sceneStripName"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
          ),
        ),
      ]),
      // Its clips are its channels': it plays what is in the scene.
      clips: joins ?? () => const SizedBox(),
      devices: () => _band(_slots([
        ..._chainSlots(theme,
            chain: chain,
            devices: devices,
            eq: mix.eq,
            comp: mix.comp,
            devicePrefix: "sceneDevice",
            eqKey: "sceneEq",
            compKey: "sceneComp",
            onEq: () => onOpen("eq"),
            onComp: () => onOpen("comp"),
            onDevice: onOpen,
            onRemove: (key) => onRemoveDevice?.call(key)),
        _slot(
            theme,
            "Add a device",
            false,
            Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
            () => onOpen(null),
            key: const ValueKey("sceneAddDevice")),
      ])),
      miniMixer: () => _miniMixerBand(theme,
          bare: bands.bare,
          buttons: [
            _onToggle(theme, "On", mix.mute,
                () => onChanged(mix.copyWith(mute: !mix.mute)),
                key: const ValueKey("sceneMute"),
                what: what,
                icon: Icons.power_settings_new),
          ],
          db: mix.gainDb,
          meter: meter,
          onDb: (db, {transient = false}) =>
              onChanged(mix.copyWith(gainDb: db), transient: transient),
          onCommit: onCommit),
      mixer: () => _mixerBand(
        narrow: narrow,
        left: _leftColumn(
          pan: _StripPan(
            channel: sceneBusKey,
            mix: mix,
            theme: theme,
            onChanged: (m, {transient = false}) =>
                onChanged(m, transient: transient),
            onCommit: onCommit,
            onOpenPanner: () => onOpen("panner"),
          ),
          on: _onToggle(theme, "On", mix.mute,
              () => onChanged(mix.copyWith(mute: !mix.mute)),
              key: const ValueKey("sceneMute"),
              what: what,
              icon: Icons.power_settings_new),
        ),
        fader: _faderOf(
            theme,
            mix.gainDb,
            meter,
            (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit,
            narrow: narrow),
        reading: DbReading(
            db: mix.gainDb,
            textKey: const ValueKey("sceneReading"),
            onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
            style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface)),
      ),
    );
    return Listener(onPointerDown: (_) => onSelect(), child: body);
  }
}

class _MasterStrip extends StatelessWidget {
  final MasterMix mix;
  final SpeakerLayout speakers;
  final _Meter meter;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<MasterMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;
  final VoidCallback onOpenLoudness;

  /// onOpenDevice opens one of its own devices, by id: see devicesOf.
  final ValueChanged<String>? onOpenDevice;

  final ValueChanged<String>? onRemoveDevice;

  /// scenes is its clips band: the scenes, each launching its row.
  final Widget Function() scenes;
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;

  const _MasterStrip({
    required this.mix,
    required this.speakers,
    required this.meter,
    required this.theme,
    required this.bands,
    required this.onChanged,
    required this.onCommit,
    required this.onOpenEq,
    required this.onOpenComp,
    required this.onOpenLoudness,
    this.onOpenDevice,
    this.onRemoveDevice,
    required this.scenes,
    required this.selected,
    required this.onSelect,
    super.key,
    this.narrow = false,
    this.onNarrow,
  });

  static double devicesWanted(int devices) => _slotsHeight(4 + devices);

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    TextStyle small([Color? c]) =>
        TextStyle(fontSize: 10, color: c ?? colors.onSurfaceVariant);
    return Listener(
      onPointerDown: (_) => onSelect(),
      child: _StripFrame(
        noMotion: "",
        narrow: narrow,
        onNarrow: onNarrow,
        narrowKey: const ValueKey("narrow-master"),
        // Its chain, the limiter where it is on, and the loudness.
        deviceCount:
            _chainCount(mix.chain, mix.devices) + (mix.limiter ? 1 : 0) + 1,
        width: 120,
        master: true,
        selected: selected,
        theme: theme,
        bands: bands,
        head: Align(
          alignment: Alignment.centerLeft,
          child: Text("Master",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface)),
        ),
        clips: scenes,
        devices: () => _band(_slots([
          ..._chainSlots(theme,
              chain: mix.chain,
              devices: mix.devices,
              eq: mix.eq,
              comp: mix.comp,
              devicePrefix: "masterDevice",
              eqKey: "masterEqSlot",
              compKey: "masterCompSlot",
              compLabel: "Glue",
              onEq: onOpenEq,
              onComp: onOpenComp,
              onDevice: (key) => onOpenDevice?.call(key),
              onRemove: (key) => onRemoveDevice?.call(key)),
          _slot(
              theme,
              "Limit",
              mix.limiter,
              Text("${dbText(mix.ceilingDb)} dBTP", style: small()),
              () => onChanged(mix.copyWith(limiter: !mix.limiter)),
              key: const ValueKey("limiterSlot")),
          // The loudness the mix is aimed at, measured from its own editor (see
          // _LoudnessDevice); reaching it in an export is a publish setting.
          _slot(
              theme,
              "Loudness",
              true,
              Text("${mix.target.round()} LUFS", style: small()),
              onOpenLoudness,
              key: const ValueKey("loudnessSlot")),
        ])),
        miniMixer: () => _miniMixerBand(theme,
            bare: bands.bare,
            buttons: const [],
            db: mix.gainDb,
            meter: meter,
            onDb: (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit: onCommit),
        mixer: () => _mixerBand(
          narrow: narrow,
          // What the whole mix comes out of, where a channel has its pan.
          left: _leftColumn(
            pan: Tooltip(
              message: "Mixed for ${speakers.label}: set in Canvas settings, "
                  "Audio",
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(speakers.isSurround ? speakers.ffmpeg : "2.0",
                      key: const ValueKey("masterSpeakers"),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant)),
                ),
              ),
            ),
          ),
          fader: _faderOf(
              theme,
              mix.gainDb,
              meter,
              (db, {transient = false}) =>
                  onChanged(mix.copyWith(gainDb: db), transient: transient),
              onCommit,
              wide: true,
              narrow: narrow),
          reading: DbReading(
              db: mix.gainDb,
              textKey: const ValueKey("masterReading"),
              onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
              style: TextStyle(fontSize: 11, color: colors.onSurface)),
        ),
      ),
    );
  }
}

/// _JoinSlot is one join between scenes on the Scenes strip, as a slot: the
/// scenes it leaves and arrives at, a dot where its transition has a sound;
/// pressed, it plays a little of each scene around the transition
/// (previewTransitionAfter). A cue launch passes it by.
class _JoinSlot extends StatefulWidget {
  final CanvasController controller;
  final int join;
  final MixerLook theme;
  const _JoinSlot(
      {super.key,
      required this.controller,
      required this.join,
      required this.theme});

  @override
  State<_JoinSlot> createState() => _JoinSlotState();
}

/// _JoinSlotState is a transition's slot on the Scenes strip, like every
/// other slot: the scene's colour, the same launch strip (pressed, the
/// transition plays), and a label named from its right-click menu. Clicked
/// or double-clicked, its transition opens in the Chain.
class _JoinSlotState extends State<_JoinSlot> with _OnSessionPulse {
  final GlobalKey<ChannelNameEditorState> _name = GlobalKey();
  final MenuController _menu = MenuController();

  CanvasController get c => widget.controller;
  int get join => widget.join;

  // Lit while its transition plays; picked while the Chain shows it.
  @override
  Object? get _slotNow => (c.joinPlaying(join), c.pickedScene == join);

  @override
  bool get _pulses => c.joinPlaying(join);

  @override
  Widget build(BuildContext context) {
    var doc = c.document;
    var scenes = doc.allScenes;
    var t = doc.transitionAfter(join);
    var said = t.label.isNotEmpty
        ? t.label
        : "→ ${scenes[join + 1].name} · ${t.kind.label}";
    void name(String label) =>
        c.setSceneTransition(join, t.copyWith(label: label));
    var lit = c.joinPlaying(join);
    var face = SlotFace(
      side: SlotSide.motion,
      colour: sceneTint(join),
      playing: lit,
      seed: "join$join",
      meta: t.sound.isEmpty
          ? null
          : "with ${t.soundName.isEmpty ? "its sound" : t.soundName}",
      go: Listener(
        key: ValueKey("joinLaunch-$join"),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (e.buttons == kSecondaryMouseButton) return;
          c.pickJoin(join);
          c.previewTransitionAfter(join, exact: true);
        },
        child: SizedBox.expand(
            child: Icon(Icons.play_arrow,
                size: 11, color: lit ? slotPlayingInk : slotInk)),
      ),
      // Picked by the card's own press, below.
      label: KeyedSubtree(
        key: ValueKey("joinOpen-$join"),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ChannelNameEditor(
              key: _name,
              byDoubleClick: false,
              name: said,
              theme: ThemeNotifier.of(context),
              onRename: name,
              fontSize: 10,
              weight: FontWeight.w600,
              color: slotInk,
              textKey: ValueKey("joinName-$join"),
              fieldKey: ValueKey("joinNameField-$join")),
        ),
      ),
    );
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey("joinRename"),
          onPressed: () => _name.currentState?.edit(),
          child: const Text("Name it"),
        ),
        if (t.label.isNotEmpty)
          MenuItemButton(
            key: const ValueKey("joinUnname"),
            onPressed: () => name(""),
            child: const Text("Its own name again"),
          ),
      ],
      child: GestureDetector(
        onSecondaryTapUp: (d) => _menu.open(position: d.localPosition),
        // Picked on the press, anywhere on the card, as the strip is (see
        // pickJoin): a press that went by to the strip would pick the join
        // after the scene shown instead.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (e.buttons == kSecondaryMouseButton) return;
            c.pickJoin(join);
          },
          child: DecoratedBox(
            key: ValueKey("joinSlot-$join"),
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: c.pickedScene == join
                  ? Border.all(color: widget.theme.studio.text, width: 1)
                  : null,
            ),
            child: face,
          ),
        ),
      ),
    );
  }
}

/// _SceneMotion is the Scenes strip's motion half: each scene's camera.
class _SceneMotion extends StatelessWidget {
  final MixerLook theme;
  final bool narrow;
  const _SceneMotion({required this.theme, required this.narrow});

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 14,
          child: Text(narrow ? "CAM" : "CAMERA",
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: narrow ? 0 : 0.6,
                  fontWeight: FontWeight.w600,
                  color: studio.muted)),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: studio.inset, borderRadius: BorderRadius.circular(4)),
            child: Text(narrow ? "Own" : "Each scene's own",
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 9.5, color: studio.muted)),
          ),
        ),
      ]),
    );
  }
}
