part of 'canvas_mixer.dart';

// A channel's column on the mixer, and the switch arming a MIDI channel for a
// keyboard. Part of canvas_mixer.dart.

class _ChannelStrip extends StatelessWidget {
  final String name;

  /// number is its place among the channels, from one: on its switch.
  final int number;

  /// channelKey is the channel's key: where its placement is looked up.
  final String channelKey;
  final ChannelMix mix;
  final bool editable;
  final bool soloed;

  /// midi is whether it is a MIDI channel, which can be [armed].
  final bool midi;
  final bool armed;
  final _Meter meter;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onSolo;
  final VoidCallback onArm;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;
  final VoidCallback onOpenDuck;
  final VoidCallback onOpenPanner;

  final Widget Function() clips;

  /// selected is whether this is the channel picked, here or on the
  /// timeline; a press anywhere on the strip picks it.
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;

  /// returns are what its sends can feed: a dial for each.
  final List<ReturnChannel> returns;

  /// automated are the settings its lanes move, and held those a hand is
  /// holding instead: see automation.dart. A red dot by each, grey when held.
  final Set<String> automated;
  final Set<String> held;

  /// part is a MIDI channel's instrument part: its In and its MIDI effects
  /// are slots too, before its EQ. [onOpenDevice] opens one by its id.
  final InstrumentPart? part;
  final ValueChanged<String>? onOpenDevice;

  /// onRemoveDevice takes a device out by id: a right-click on its slot.
  final ValueChanged<String>? onRemoveDevice;

  /// motion and motionLine are its element's motion half and line, where
  /// it is an element's own sound: the element and its sound one strip.
  final Widget Function()? motion;
  final Widget Function()? motionLine;

  /// leadSlot is its element's first device slot: where the element's sound
  /// goes, the master or a return it shares.
  final Widget? leadSlot;

  final List<Widget> badges;

  final Color? rowColour;

  /// motionDevices are its element's motion slots, before the sound's.
  final List<Widget> motionDevices;

  const _ChannelStrip({
    this.rowColour,
    this.badges = const [],
    this.motionDevices = const [],
    this.motion,
    this.motionLine,
    this.leadSlot,
    this.automated = const {},
    this.held = const {},
    this.returns = const [],
    this.midi = false,
    this.armed = false,
    this.part,
    this.onOpenDevice,
    this.onRemoveDevice,
    required this.name,
    required this.number,
    required this.channelKey,
    required this.mix,
    required this.editable,
    required this.soloed,
    required this.meter,
    required this.theme,
    required this.bands,
    required this.onChanged,
    required this.onCommit,
    required this.onSolo,
    required this.onArm,
    required this.onOpenEq,
    required this.onOpenComp,
    required this.onOpenDuck,
    required this.onOpenPanner,
    required this.clips,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    super.key,
    this.narrow = false,
    this.onNarrow,
  });

  /// devicesWanted is how tall its devices band would be to show them all.
  static double devicesWanted({InstrumentPart? part, int devices = 0}) =>
      _slotsHeight(3 + devices + (part == null ? 0 : 1 + part.effects.length));

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var body = _StripFrame(
      motion: motion,
      motionLine: motionLine,
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: ValueKey("narrow-$channelKey"),
      badges: badges,
      rowColour: rowColour,
      deviceCount: motionDevices.length +
          (part?.effects.length ?? 0) +
          (mix.speech != null ? 1 : 0) +
          (mix.vocaliser != null ? 1 : 0) +
          _chainCount(mix.chain, mix.devices) +
          (mix.duck.on ? 1 : 0),
      selected: selected,
      theme: theme,
      bands: bands,
      // Double-clicked, renamed: the channel's name on the timeline too.
      head: Align(
        alignment: Alignment.centerLeft,
        child: ChannelNameEditor(
            name: name,
            theme: ThemeNotifier.of(context),
            color: theme.colors.onSurface,
            onRename: onRename,
            weight: FontWeight.w600,
            textKey: const ValueKey("mixerName"),
            fieldKey: const ValueKey("mixerNameField")),
      ),
      clips: clips,
      devices: () => _band([
        ..._slots([
          ...motionDevices,
          if (leadSlot case var lead?) lead,
          // A MIDI channel's In and its MIDI effects, first: what is done
          // to its notes before they are played.
          if (part case var p?) ...[
            _slot(
                theme,
                "In",
                p.monitor != MidiMonitor.off,
                Text(p.monitor.label,
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
                () => onOpenDevice?.call("midiIn"),
                key: const ValueKey("midiInSlot")),
            for (var (i, e) in p.effects.indexed)
              _slot(
                  theme,
                  e.kind.short,
                  e.on,
                  Icon(Icons.circle,
                      size: 7, color: e.on ? theme.studio.on : colors.outline),
                  () => onOpenDevice?.call("midi$i"),
                  onRemove: () => onRemoveDevice?.call("midi$i"),
                  key: ValueKey("midiSlot-$i")),
          ],
          if (mix.speech case var speech?)
            _slot(
                theme,
                "Speech",
                true,
                Text(speech.voiceName.isEmpty ? "voice" : speech.voiceName,
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
                () => onOpenDevice?.call("speech"),
                onRemove: () => onRemoveDevice?.call("speech"),
                key: const ValueKey("speechSlot")),
          if (mix.vocaliser != null)
            _slot(
                theme,
                "Vocaliser",
                true,
                Icon(Icons.music_note,
                    size: 10, color: colors.onSurfaceVariant),
                () => onOpenDevice?.call("vocaliser"),
                onRemove: () => onRemoveDevice?.call("vocaliser"),
                key: const ValueKey("vocaliserSlot")),
          ..._chainSlots(theme,
              chain: mix.chain,
              devices: mix.devices,
              eq: mix.eq,
              comp: mix.comp,
              devicePrefix: "chanDevice",
              eqKey: "eqSlot",
              compKey: "compSlot",
              onEq: onOpenEq,
              onComp: onOpenComp,
              onDevice: (key) => onOpenDevice?.call(key),
              onRemove: (key) => onRemoveDevice?.call(key)),
          // Whether this channel turns the others down while it is heard (see
          // Ducking), on the channel that is listened for: the voice.
          _slot(
              theme,
              "Duck",
              mix.duck.on,
              Text(mix.duck.on ? "${dbText(mix.duck.depthDb)} dB" : "off",
                  style:
                      TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
              onOpenDuck,
              key: const ValueKey("duckSlot")),
        ]),
      ]),
      sends: () => _Sends(
        narrow: narrow,
        mix: mix,
        returns: returns,
        theme: theme,
        onChanged: onChanged,
        onCommit: onCommit,
      ),
      miniMixer: () => _miniMixerBand(theme,
          bare: bands.bare,
          buttons: [
            _onToggle(theme, "$number", mix.mute,
                () => onChanged(mix.copyWith(mute: !mix.mute)),
                key: const ValueKey("mute"), what: "This channel"),
            _Toggle(
                key: const ValueKey("solo"),
                label: "S",
                on: soloed,
                onColor: theme.studio.solo,
                onInk: theme.studio.onSolo,
                height: _buttonH,
                fontSize: 8,
                theme: theme,
                tooltip: "Solo: hear only this, while you listen",
                onTap: onSolo),
            if (midi) _ArmToggle(theme: theme, armed: armed, onTap: onArm),
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
            channel: channelKey,
            mix: mix,
            theme: theme,
            onChanged: onChanged,
            onCommit: onCommit,
            onOpenPanner: onOpenPanner,
          ),
          on: _onToggle(theme, "$number", mix.mute,
              () => onChanged(mix.copyWith(mute: !mix.mute)),
              key: const ValueKey("mute"), what: "This channel"),
          solo: _Toggle(
              key: const ValueKey("solo"),
              label: "S",
              on: soloed,
              onColor: theme.studio.solo,
              onInk: theme.studio.onSolo,
              height: _buttonH,
              fontSize: 8,
              theme: theme,
              tooltip: "Solo: hear only this, while you listen",
              onTap: onSolo),
          arm: midi
              ? _ArmToggle(theme: theme, armed: armed, onTap: onArm)
              : null,
        ),
        fader: _faderOf(
            theme,
            mix.gainDb,
            meter,
            (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit,
            narrow: narrow),
        reading: Row(mainAxisSize: MainAxisSize.min, children: [
          // Held by hand, off its automation: an amber ◉ and amber reading;
          // following it, a red dot.
          if (held.contains("volume"))
            Padding(
              key: const ValueKey("faderHeld"),
              padding: const EdgeInsets.only(right: 3),
              child: Text("◉",
                  style: TextStyle(fontSize: 10, color: theme.studio.on)),
            )
          else if (automated.contains("volume"))
            Container(
              key: const ValueKey("faderAutomated"),
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: automationColour),
            ),
          Flexible(
            child: DbReading(
                db: mix.gainDb,
                textKey: const ValueKey("faderReading"),
                onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
                style: TextStyle(
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: held.contains("volume")
                        ? theme.studio.on
                        : colors.onSurface)),
          ),
        ]),
      ),
    );
    if (editable) {
      // A Listener, not a tap: it picks the channel whatever the press goes on
      // to do, without taking the press from it.
      return Listener(onPointerDown: (_) => onSelect(), child: body);
    }
    return Tooltip(
      message: "On the master: changed there",
      child: IgnorePointer(child: Opacity(opacity: 0.55, child: body)),
    );
  }
}

/// _ArmToggle arms a MIDI channel: a MIDI keyboard then plays its
/// instrument, and a recording writes into it.
class _ArmToggle extends StatelessWidget {
  final MixerLook theme;
  final bool armed;
  final VoidCallback onTap;
  const _ArmToggle(
      {required this.theme, required this.armed, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: armed
            ? "Armed: a MIDI keyboard plays this channel, and recording "
                "writes into it. Press to disarm."
            : "Arm: a MIDI keyboard plays this channel, and recording "
                "writes into it",
        child: Material(
          color:
              armed ? theme.studio.arm : theme.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: const ValueKey("arm"),
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: Center(
              child: Icon(Icons.circle,
                  size: 6,
                  color: armed ? theme.studio.onArm : theme.studio.arm),
            ),
          ),
        ),
      );
}
