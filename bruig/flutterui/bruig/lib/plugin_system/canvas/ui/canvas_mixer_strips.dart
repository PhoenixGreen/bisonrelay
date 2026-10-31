part of 'canvas_mixer.dart';

// canvas_mixer_strips.dart is the mixer's columns: one for each channel, each
// return and the master, every one the same shape, in three bands top to
// bottom as Ableton's session mixer has them --
//
//   the clips: a channel's clip slots, launched live; the master's scenes;
//   the devices: a column's effects as slots that open them, and its sends;
//   the mixer: pan, on, solo and arm in a column beside the fader.
//
// Each band is one height across every column -- see _Bands -- so the faders
// start on the same line and are as tall, wherever the devices run out.
// Each band is shown or hidden from the rail at the right (MixerSection).

/// _headH, _bandGap and the rest are the columns' measures, at the desk's
/// own size (see _CanvasMixerState.build).
const double _headH = 22;
const double _bandGap = 6;
const double _slotH = 20;
const double _slotGap = 4;
const double _clipH = 20;
const double _clipGap = 3;
const double _stopH = 16;

/// _clipRowsWanted is how many clip slots the clips band is made tall
/// enough for, room allowing; more scroll.
const int _clipRowsWanted = 4;

/// _clipsLeast is the least a clips band is given, room allowing: one
/// slot, and the stop button under it.
const double _clipsLeast = _clipH + _clipGap + _slotGap + _stopH;

/// _mixerMinH is the least a mixer band is given -- its left column and a
/// fader still worth dragging -- and _mixerCapH the most before the room
/// left goes to the clips instead.
const double _mixerMinH = 120;
const double _mixerCapH = 230;

/// _leftW and _leftH are the mixer band's left column: pan, then -- a
/// little way under it -- on, solo, arm, each half a full button's size.
const double _leftW = 24;
const double _leftH = 30 + 10 + 12 + 4 + 12 + 4 + 12;

/// _buttonW and _buttonH are those buttons'.
const double _buttonW = 18;
const double _buttonH = 12;

/// _wideW and _narrowW are a column's widths: wide, with names and a
/// numbered fader, or narrow, for more channels in view -- each column
/// either, by itself or all together (CanvasController.narrowStrips).
const double _wideW = 116;
const double _narrowW = 62;

/// _sendRow is a row of send dials: the dial and its letter; a narrow
/// column's dials are smaller, two to a row.
const double _sendRow = 35;
const double _narrowSendRow = 29;

double _slotsHeight(int n) => n <= 0 ? 0 : n * _slotH + (n - 1) * _slotGap;

/// sendsHeight is the send dials' band for [returns] returns: rows of
/// three, or of two in a narrow column; nought with none.
double sendsHeight(int returns, {bool narrow = false}) {
  if (returns == 0) return 0;
  var rows = (returns / (narrow ? 2 : 3)).ceil();
  return rows * (narrow ? _narrowSendRow : _sendRow) + (rows - 1) * 2;
}

/// _Bands is how tall the clips and devices bands of every column are --
/// null for one hidden -- and whether the mixer band, which takes what is
/// left, is shown.
class _Bands {
  final double? clips;
  final double? devices;

  /// sends is the send dials' band, the height the most of them take --
  /// null hidden, or where there are no returns to send to.
  final double? sends;

  /// mixer is whether the mixer band shows whole, taking what is left;
  /// miniMixer whether it shows minimised, [_miniMixerH] high.
  final bool mixer;
  final bool miniMixer;

  /// bare is the mixer at its smallest: no column has its head -- its name
  /// and the arrow that narrows it.
  final bool bare;
  const _Bands(this.clips, this.devices, this.mixer,
      {this.miniMixer = false, this.sends, this.bare = false});

  /// _Bands.fit shares [inner], a column's height inside its frame, among
  /// the bands as [states] says. A minimised band has its least -- a clip
  /// slot and its stop, a device slot, the mixer as a row -- and the whole
  /// ones share the rest: the mixer its least first, then each of the
  /// others what it wants, then the mixer more, to [_mixerCapH], then the
  /// clips the rest. Short of room, the clips and devices share it as they
  /// want it, and scroll.
  ///
  /// The devices want no more than [devicesCap] -- three slots and the
  /// sends -- while the clips and the mixer both show whole: a long chain
  /// scrolls rather than squeezing them. With either minimised or hidden,
  /// the devices may have all they want.
  factory _Bands.fit(double inner, Map<MixerSection, BandState> states,
      double devicesWanted, double devicesCap,
      {double sendsH = 0, bool bare = false}) {
    bool whole(MixerSection s) => states[s] == BandState.shown;
    bool mini(MixerSection s) => states[s] == BandState.minimised;
    var clips = whole(MixerSection.clips);
    var devices = whole(MixerSection.devices);
    var mixer = whole(MixerSection.mixer);
    // The sends: their own height, as tall as the most dials take.
    var sends = states[MixerSection.sends] != BandState.hidden && sendsH > 0
        ? sendsH
        : null;
    var showing = MixerSection.values
        .where((s) =>
            states[s] != BandState.hidden &&
            (s != MixerSection.sends || sends != null))
        .length;
    var avail = math.max(0.0, inner - (bare ? 0 : _headH) - _bandGap * showing);
    double? c, d;
    var fixed = sends ?? 0.0;
    if (mini(MixerSection.clips)) {
      c = _clipsLeast;
      fixed += c;
    }
    if (mini(MixerSection.devices)) {
      d = _slotH;
      fixed += d;
    }
    if (mini(MixerSection.mixer)) fixed += bare ? _bareMixerH : _miniMixerH;
    var free = math.max(0.0, avail - fixed);
    var want =
        clips && mixer ? math.min(devicesWanted, devicesCap) : devicesWanted;
    var clipsWanted =
        _clipRowsWanted * (_clipH + _clipGap) - _clipGap + _slotGap + _stopH;
    if (!mixer) {
      if (clips && devices) {
        d = math.min(want, math.max(0.0, free - _clipsLeast));
        c = free - d;
      } else if (clips) {
        c = free;
      } else if (devices) {
        d = free;
      }
      return _Bands(c, d, false,
          miniMixer: mini(MixerSection.mixer), sends: sends, bare: bare);
    }
    var wanted = (clips ? clipsWanted : 0) + (devices ? want : 0);
    var forMixer = free - wanted;
    double mixerH;
    if (forMixer < _mixerMinH) {
      mixerH = math.min(_mixerMinH, free);
    } else if (clips) {
      mixerH = math.min(forMixer, _mixerCapH);
    } else {
      mixerH = forMixer;
    }
    var rest = math.max(0.0, free - mixerH);
    if (devices && clips) {
      d = rest >= wanted ? want : rest * want / wanted;
      c = rest - d;
      // A slot and the stop under it, at the least: taken from the
      // devices, which scroll -- shared out by what each wanted, a channel
      // with a long chain left the clips a sliver their stop ran out of.
      if (c < _clipsLeast && rest > _clipsLeast) {
        c = _clipsLeast;
        d = rest - c;
      }
    } else if (devices) {
      d = math.min(rest, want);
    } else if (clips) {
      c = rest;
    }
    return _Bands(c, d, true, sends: sends, bare: bare);
  }
}

/// _miniMixerH is the mixer band minimised: a row of its buttons over a
/// meter on its side, which is the fader too.
const double _miniMixerH = 34;

/// _bareMixerH is it at the mixer's smallest: the meter alone.
const double _bareMixerH = 12;

/// _StripFrame is a column: its frame, its head, and its bands at the
/// heights every column shares.
class _StripFrame extends StatelessWidget {
  final double width;
  final bool selected;
  final bool master;
  final MixerLook theme;
  final _Bands bands;
  final Widget head;
  final Widget Function() clips;
  final Widget Function() devices;
  final Widget Function() mixer;

  /// sends are its send dials, in the sends band -- nothing in a column
  /// without, which keeps the band's room so the faders line up.
  final Widget Function()? sends;

  /// miniMixer is the mixer band minimised: see _miniMixerBand.
  final Widget Function() miniMixer;

  /// narrow is whether the column is narrow, and onNarrow -- the arrow in
  /// its head, keyed [narrowKey] -- makes it the other.
  final bool narrow;
  final VoidCallback? onNarrow;
  final Key? narrowKey;

  const _StripFrame({
    this.width = _wideW,
    this.master = false,
    this.narrow = false,
    this.onNarrow,
    this.narrowKey,
    required this.selected,
    required this.theme,
    required this.bands,
    required this.head,
    required this.clips,
    required this.devices,
    required this.mixer,
    required this.miniMixer,
    this.sends,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var studio = theme.studio;
    return Container(
      width: narrow ? _narrowW : width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: master ? colors.outline : colors.outlineVariant),
      ),
      // Picked, drawn over the frame rather than thickening it: a thicker
      // edge moved the picked column's bands off the others' line. Always
      // there, clear when not picked: a decoration that came and went
      // changed the tree under it, and a reading being typed into, picked
      // by the press that opened it, lost what was typed.
      foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? colors.primary : const Color(0x00000000),
              width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!bands.bare)
          SizedBox(
            height: _headH,
            child: Row(children: [
              Expanded(child: ClipRect(child: head)),
              if (onNarrow case var toggle?)
                Tooltip(
                  message: narrow ? "Make it wide" : "Make it narrow",
                  child: InkWell(
                    key: narrowKey,
                    onTap: toggle,
                    child: Icon(
                        narrow ? Icons.chevron_right : Icons.chevron_left,
                        size: 12,
                        color: studio.muted),
                  ),
                ),
            ]),
          ),
        if (bands.clips case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(height: h, child: clips()),
        ],
        if (bands.devices case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(height: h, child: ClipRect(child: devices())),
        ],
        if (bands.sends case var h?) ...[
          const SizedBox(height: _bandGap),
          SizedBox(
              key: const ValueKey("sendsBand"),
              height: h,
              child: ClipRect(child: sends?.call() ?? const SizedBox())),
        ],
        if (bands.mixer) ...[
          const SizedBox(height: _bandGap),
          Expanded(child: mixer()),
        ],
        if (bands.miniMixer) ...[
          const Spacer(),
          const SizedBox(height: _bandGap),
          SizedBox(
              height: bands.bare ? _bareMixerH : _miniMixerH,
              child: miniMixer()),
        ],
      ]),
    );
  }
}

/// _band is a column of [children] in a band: scrolled when the band is
/// shorter than they are.
Widget _band(List<Widget> children) => ListView(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: children,
    );

/// _slots lays [slots] out a slot's height each, [_slotGap] apart.
List<Widget> _slots(List<Widget> slots) => [
      for (var (i, s) in slots.indexed) ...[
        if (i > 0) const SizedBox(height: _slotGap),
        SizedBox(height: _slotH, child: s),
      ],
    ];

/// _mixerBand is the mixer band: [left] -- pan, on, solo, arm -- beside the
/// fader, with its reading under it.
Widget _mixerBand({
  required Widget left,
  required Widget fader,
  required Widget reading,
  bool narrow = false,
}) =>
    Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: _leftW,
        // Shrunk rather than overflowing, in a band shorter than the
        // column: never, laid out as the bands are, but a short desk
        // zoomed is near it.
        child: Align(
          alignment: Alignment.topCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(width: _leftW, height: _leftH, child: left),
          ),
        ),
      ),
      SizedBox(width: narrow ? 2 : 4),
      Expanded(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: fader),
          const SizedBox(height: 3),
          reading,
        ]),
      ),
    ]);

/// _leftColumn stacks the mixer band's left column: [pan], 30 high; then,
/// a little way under it, on, solo and arm, each in its place whether it is
/// there or not, so every column's line up.
Widget _leftColumn({
  required Widget pan,
  Widget? on,
  Widget? solo,
  Widget? arm,
}) {
  Widget button(Widget? child) => SizedBox(
      height: _buttonH,
      child: Center(child: SizedBox(width: _buttonW, child: child)));
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    SizedBox(height: 30, child: pan),
    const SizedBox(height: 10),
    button(on),
    const SizedBox(height: 4),
    button(solo),
    const SizedBox(height: 4),
    button(arm),
  ]);
}

/// _StripPan is where a column is heard from, in its left column. Stereo,
/// a knob: dragged up to turn right, double-clicked to centre. In surround,
/// or placed by the picture, a button with the room in miniature: the room
/// is too small to place a sound by in a strip, so it opens the Panner in
/// the effects, which is big enough.
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
        message: "Pan: drag up to turn right, down to turn left. "
            "Double-click for the centre.",
        child: GestureDetector(
          supportedDevices: dragPointers,
          key: const ValueKey("balance"),
          onVerticalDragUpdate: (d) => onChanged(
              mix.copyWith(balance: (b - d.delta.dy / 80).clamp(-1.0, 1.0)),
              transient: true),
          onVerticalDragEnd: (_) => onCommit(),
          onDoubleTap: () => onChanged(mix.copyWith(balance: 0)),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Column(children: [
              CustomPaint(
                  size: const Size(21, 21),
                  painter: _KnobPainter(b, theme.colors)),
              const SizedBox(height: 1),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(reading,
                      key: const ValueKey("panReading"), style: small)),
            ]),
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
/// is heard, dark while it is muted -- Ableton's track activator.
Widget _onToggle(MixerLook theme, String label, bool muted, VoidCallback onTap,
        {required Key key, required String what}) =>
    _Toggle(
        key: key,
        label: label,
        on: !muted,
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

/// _fadeArea is a column's fader and its reading, for the mixer band.
Widget _faderOf(
        MixerLook theme,
        double db,
        (double, double) level,
        (double, double) peak,
        _MixWrite<double> onChanged,
        VoidCallback onCommit,
        {bool wide = false,
        bool narrow = false}) =>
    _Fader(
      db: db,
      level: level,
      peak: peak,
      theme: theme,
      wide: wide,
      small: true,
      labels: !narrow,
      onChanged: onChanged,
      onCommit: onCommit,
    );

class _ChannelStrip extends StatelessWidget {
  final String name;

  /// number is its place among the channels, from one: on its switch.
  final int number;

  /// channelKey is the channel's key: where its placement is looked up.
  final String channelKey;
  final ChannelMix mix;
  final bool editable;
  final bool soloed;

  /// midi is whether it is a MIDI channel -- an instrument's -- which can be
  /// armed, and [armed] whether it is.
  final bool midi;
  final bool armed;
  final (double, double) level;
  final (double, double) peak;
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

  /// clips is its clips band, from the mixer: see _ClipBand.
  final Widget Function() clips;

  /// selected is whether this is the channel picked -- here or on the
  /// timeline; a press anywhere on the strip picks it.
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;

  /// returns are what its sends can feed: a dial for each.
  final List<ReturnChannel> returns;

  /// automated are the settings its lanes move, and held those a hand is
  /// holding instead: see automation.dart. A red dot by each -- grey,
  /// held.
  final Set<String> automated;
  final Set<String> held;

  /// part is a MIDI channel's instrument part: its In and its MIDI effects
  /// are slots too, before its EQ. [onOpenDevice] opens one by its id.
  final InstrumentPart? part;
  final ValueChanged<String>? onOpenDevice;

  /// onRemoveDevice takes one of its devices out, by id: a right-click on
  /// its slot.
  final ValueChanged<String>? onRemoveDevice;

  const _ChannelStrip({
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
    required this.level,
    required this.peak,
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
  static double devicesWanted(int returns,
          {bool narrow = false, InstrumentPart? part, int devices = 0}) =>
      _slotsHeight(3 + devices + (part == null ? 0 : 1 + part.effects.length));

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var body = _StripFrame(
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: ValueKey("narrow-$channelKey"),
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
          // Its Speech device, and its own devices, in their order.
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
          for (var (i, d) in mix.devices.indexed)
            _slot(
                theme,
                d.kind.label,
                d.on,
                Icon(Icons.circle,
                    size: 7, color: d.on ? theme.studio.on : colors.outline),
                () => onOpenDevice?.call("dev$i"),
                onRemove: () => onRemoveDevice?.call("dev$i"),
                key: ValueKey("chanDevice-$i")),
          _slot(
              theme,
              "EQ",
              mix.eq.on,
              CustomPaint(
                  size: const Size(40, 14),
                  painter: _MiniCurve(mix.eq, colors)),
              onOpenEq,
              key: const ValueKey("eqSlot")),
          _slot(
              theme,
              "Comp",
              mix.comp.on,
              Icon(Icons.circle,
                  size: 7,
                  color: mix.comp.on ? theme.studio.on : colors.outline),
              onOpenComp,
              key: const ValueKey("compSlot")),
          // Whether this channel turns the others down while it is heard --
          // see Ducking. On the channel that is listened for: the voice.
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
      // Its send dials, in a band of their own -- see MixerSection.sends.
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
          level: level,
          peak: peak,
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
            level,
            peak,
            (db, {transient = false}) =>
                onChanged(mix.copyWith(gainDb: db), transient: transient),
            onCommit,
            narrow: narrow),
        reading: Row(mainAxisSize: MainAxisSize.min, children: [
          if (automated.contains("volume"))
            Container(
              key: const ValueKey("faderAutomated"),
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: held.contains("volume")
                      ? const Color(0xFF7D838D)
                      : automationColour),
            ),
          Flexible(
            child: DbReading(
                db: mix.gainDb,
                textKey: const ValueKey("faderReading"),
                onSet: (db) => onChanged(mix.copyWith(gainDb: db)),
                style: TextStyle(
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.onSurface)),
          ),
        ]),
      ),
    );
    if (editable) {
      // A Listener, not a tap: it picks the channel whatever the press
      // goes on to do -- open an effect, move the fader -- without taking
      // the press from it.
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

/// _ReturnStrip is a return: its letter and name; no clips; its devices --
/// each a slot that opens it -- with its EQ and compressor, given the room a
/// channel's sends take; and its pan, switch, fader and level.
class _ReturnStrip extends StatelessWidget {
  final String letter;
  final ReturnChannel ret;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<ReturnChannel> onChanged;
  final VoidCallback onCommit;
  final ValueChanged<String?> onOpen;
  final VoidCallback onRemove;

  /// onRemoveDevice takes one of its devices out, by id: a right-click on
  /// its slot.
  final ValueChanged<String>? onRemoveDevice;
  final bool selected;
  final bool narrow;
  final VoidCallback? onNarrow;
  final VoidCallback onSelect;

  const _ReturnStrip({
    required this.letter,
    required this.ret,
    required this.level,
    required this.peak,
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
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: ValueKey("narrow-${ret.id}"),
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
        // Taken away from the wide column: a narrow one has room for its
        // letter and a little of its name.
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
        for (var (i, d) in ret.devices.indexed)
          _slot(
              theme,
              d.kind.label,
              d.on,
              Icon(Icons.circle,
                  size: 7, color: d.on ? theme.studio.on : colors.outline),
              () => onOpen("dev$i"),
              onRemove: () => onRemoveDevice?.call("dev$i"),
              key: ValueKey("returnDevice-$i")),
        _slot(
            theme,
            "Add a device",
            false,
            Icon(Icons.add, size: 12, color: colors.onSurfaceVariant),
            () => onOpen(null),
            key: const ValueKey("returnAddDevice")),
        _slot(
            theme,
            "EQ",
            mix.eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(mix.eq, colors)),
            () => onOpen("eq"),
            key: const ValueKey("returnEq")),
        _slot(
            theme,
            "Comp",
            mix.comp.on,
            Icon(Icons.circle,
                size: 7, color: mix.comp.on ? theme.studio.on : colors.outline),
            () => onOpen("comp"),
            key: const ValueKey("returnComp")),
      ])),
      miniMixer: () => _miniMixerBand(theme,
          bare: bands.bare,
          buttons: [
            _onToggle(theme, letter, mix.mute,
                () => set(mix.copyWith(mute: !mix.mute)),
                key: const ValueKey("returnMute"), what: "This return"),
          ],
          db: mix.gainDb,
          level: level,
          peak: peak,
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
            level,
            peak,
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

class _MasterStrip extends StatelessWidget {
  final MasterMix mix;
  final SpeakerLayout speakers;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _Bands bands;
  final _MixWrite<MasterMix> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onOpenEq;
  final VoidCallback onOpenComp;
  final VoidCallback onOpenLoudness;

  /// onOpenDevice opens one of its own devices, by id: see devicesOf.
  final ValueChanged<String>? onOpenDevice;

  /// onRemoveDevice takes one of its devices out, by id: a right-click on
  /// its slot.
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
    required this.level,
    required this.peak,
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
        narrow: narrow,
        onNarrow: onNarrow,
        narrowKey: const ValueKey("narrow-master"),
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
          // Its own devices first, as they are played.
          for (var (i, d) in mix.devices.indexed)
            _slot(
                theme,
                d.kind.label,
                d.on,
                Icon(Icons.circle,
                    size: 7, color: d.on ? theme.studio.on : colors.outline),
                () => onOpenDevice?.call("dev$i"),
                onRemove: () => onRemoveDevice?.call("dev$i"),
                key: ValueKey("masterDevice-$i")),
          _slot(
              theme,
              "EQ",
              mix.eq.on,
              CustomPaint(
                  size: const Size(40, 14),
                  painter: _MiniCurve(mix.eq, colors)),
              onOpenEq,
              key: const ValueKey("masterEqSlot")),
          _slot(
              theme,
              "Glue",
              mix.comp.on,
              Icon(Icons.circle,
                  size: 7,
                  color: mix.comp.on ? theme.studio.on : colors.outline),
              onOpenComp,
              key: const ValueKey("masterCompSlot")),
          _slot(
              theme,
              "Limit",
              mix.limiter,
              Text("${dbText(mix.ceilingDb)} dBTP", style: small()),
              () => onChanged(mix.copyWith(limiter: !mix.limiter)),
              key: const ValueKey("limiterSlot")),
          // The loudness the whole mix is aimed at, measured from its
          // own editor -- see _LoudnessEditor. Reaching it in an export is
          // a publish setting.
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
            level: level,
            peak: peak,
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
              level,
              peak,
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

/// _SectionRail is the rail down the mixer's right edge: a button for each
/// band, lit while it is shown; then the returns, shown or hidden; then
/// every column narrow or wide together.
class _SectionRail extends StatelessWidget {
  final Map<MixerSection, BandState> states;
  final MixerLook theme;
  final ValueChanged<MixerSection> onToggle;
  final bool returnsShown;
  final VoidCallback onReturns;
  final bool allNarrow;
  final VoidCallback onNarrowAll;

  const _SectionRail({
    required this.states,
    required this.theme,
    required this.onToggle,
    required this.returnsShown,
    required this.onReturns,
    required this.allNarrow,
    required this.onNarrowAll,
  });

  Widget _button(
      {required Key key,
      required String tip,
      required bool lit,
      bool half = false,
      required Widget Function(Color ink) child,
      required VoidCallback onTap}) {
    // Half lit -- a band minimised -- is a ring in the lit colour.
    var ink = lit
        ? theme.studio.onOn
        : half
            ? theme.studio.on
            : theme.colors.onSurfaceVariant;
    // Drawn half size, but pressed anywhere in a square twenty across: a
    // twelve-pixel target was easy to miss.
    return Tooltip(
      message: tip,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox.square(
            dimension: 20,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lit
                      ? theme.studio.on
                      : theme.colors.surfaceContainerHighest,
                  border: half
                      ? Border.all(color: theme.studio.on, width: 1.5)
                      : null,
                ),
                child: Center(child: child(ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        // Scrolled, in a mixer shrunk to its least: its buttons are taller
        // than one band.
        child: SingleChildScrollView(
            child: Column(children: [
          for (var s in MixerSection.values)
            _button(
              key: ValueKey("section-${s.name}"),
              tip: "${s.label}: ${switch (states[s]!) {
                BandState.shown when s == MixerSection.sends =>
                  "shown. Press to hide",
                BandState.shown => "shown. Press to minimise",
                BandState.minimised => "minimised. Press to hide",
                BandState.hidden => "hidden. Press to show",
              }} them in every column",
              lit: states[s] == BandState.shown,
              half: states[s] == BandState.minimised,
              onTap: () => onToggle(s),
              child: (ink) => Text(s.letter,
                  style: TextStyle(
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: ink)),
            ),
          const SizedBox(height: 4),
          _button(
            key: const ValueKey("showReturns"),
            tip: returnsShown
                ? "Hide the returns, for the channels' room. What is sent "
                    "to them is still heard."
                : "Show the returns, beside the master",
            lit: returnsShown,
            onTap: onReturns,
            child: (ink) => Text("R",
                style: TextStyle(
                    fontSize: 7,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: ink)),
          ),
          _button(
            key: const ValueKey("narrowAll"),
            tip: allNarrow
                ? "Make every column wide"
                : "Make every column narrow",
            lit: allNarrow,
            onTap: onNarrowAll,
            // Squeezed from the sides: narrower.
            child: (ink) => RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.compress, size: 8, color: ink)),
          ),
        ])),
      );
}

// ---------------------------------------------------------------------------
// The clips band
// ---------------------------------------------------------------------------

/// _ClipScrolls keeps every column's clip slots scrolled together, so a row
/// is one line across the mixer however far down it is.
class _ClipScrolls {
  final Map<String, ScrollController> _of = {};
  bool _syncing = false;

  ScrollController of(String column) =>
      _of[column] ??= ScrollController()..addListener(() => _follow(column));

  void _follow(String column) {
    if (_syncing) return;
    var lead = _of[column];
    if (lead == null || !lead.hasClients) return;
    _syncing = true;
    for (var e in _of.entries) {
      if (e.key == column || !e.value.hasClients) continue;
      var p = e.value.position;
      var to = lead.offset.clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((p.pixels - to).abs() > 0.5) e.value.jumpTo(to);
    }
    _syncing = false;
  }

  void dispose() {
    for (var c in _of.values) {
      c.dispose();
    }
  }
}

/// _blinkOn is whether something waiting for a bar is lit at this moment:
/// a quarter of a second on, a quarter off.
bool get _blinkOn => DateTime.now().millisecondsSinceEpoch ~/ 250 % 2 == 0;

/// _rows lays a column of clip rows out: [row] for each scene, a slot's
/// height and gap apart, scrolled by [scroll], over [foot].
Widget _clipColumn(ScrollController scroll, int rows,
        Widget Function(int row) row, Widget foot) =>
    LayoutBuilder(builder: (context, box) {
      var slots = ListView.builder(
        controller: scroll,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemExtent: _clipH + _clipGap,
        itemCount: rows,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: _clipGap),
          child: row(i),
        ),
      );
      // Squeezed past the stop's room: the slots alone, rather than a
      // stop button running out of the band.
      if (box.maxHeight < _slotGap + _stopH + 4) return slots;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: slots),
        const SizedBox(height: _slotGap),
        SizedBox(height: _stopH, child: foot),
      ]);
    });

/// _ClipBand is a channel's clip slots: a row for each scene, and its stop
/// button under them.
class _ClipBand extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final MixerLook theme;
  final ScrollController scroll;

  const _ClipBand({
    required this.controller,
    required this.channel,
    required this.theme,
    required this.scroll,
  });

  @override
  Widget build(BuildContext context) {
    var stopping = controller.clipPlaying(channel);
    return _clipColumn(
      scroll,
      controller.session.rows,
      (row) => _ClipSlot(
          key: ValueKey("clip-$channel-$row"),
          controller: controller,
          channel: channel,
          row: row,
          theme: theme),
      Tooltip(
        message: "Stop this channel's clips, on the next bar",
        child: Material(
          color: theme.studio.inset,
          borderRadius: BorderRadius.circular(3),
          child: InkWell(
            key: ValueKey("clipStop-$channel"),
            borderRadius: BorderRadius.circular(3),
            onTap: () => controller.stopChannelClips(channel),
            child: Center(
              child: Icon(Icons.stop,
                  size: 11,
                  color: stopping ? theme.studio.text : theme.studio.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// _ClipSlot is one slot: a clip -- its colour, a play mark, its name -- or
/// an empty slot, which stops the channel pressed, or on an armed MIDI
/// channel records into it. A right-click, or a double-click on an empty
/// one, offers what can be done with it.
class _ClipSlot extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final int row;
  final MixerLook theme;

  const _ClipSlot({
    required this.controller,
    required this.channel,
    required this.row,
    required this.theme,
    super.key,
  });

  @override
  State<_ClipSlot> createState() => _ClipSlotState();
}

class _ClipSlotState extends State<_ClipSlot> {
  final MenuController _menu = MenuController();
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rename(SessionClip clip) {
    _name.text = clip.name;
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _name.selection =
            TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      }
    });
  }

  void _renamed(SessionClip clip) {
    if (!_renaming) return;
    setState(() => _renaming = false);
    var name = _name.text.trim();
    if (name != clip.name) {
      c.setSessionClip(widget.channel, widget.row, clip.copyWith(name: name));
    }
  }

  void _set(SessionClip clip) =>
      c.setSessionClip(widget.channel, widget.row, clip);

  /// _duplicate copies the clip into the next empty slot down.
  void _duplicate(SessionClip clip) {
    var grid = c.session;
    var row = widget.row + 1;
    while (grid.at(widget.channel, row) != null) {
      row++;
    }
    if (row >= grid.rows) c.addClipScene();
    c.setSessionClip(widget.channel, row, clip.copyWith(id: newElementId()));
  }

  List<Widget> _clipMenu(SessionClip clip) {
    var studio = widget.theme.studio;
    Widget check(bool on) => Icon(on ? Icons.check : null, size: 14);
    return [
      if (clip.midi)
        MenuItemButton(
          key: const ValueKey("clipEditNotes"),
          leadingIcon: const Icon(Icons.piano, size: 14),
          onPressed: () => c.openPianoRoll(widget.channel, row: widget.row),
          child: const Text("Edit its notes"),
        ),
      SubmenuButton(
        menuChildren: [
          for (var m in LaunchMode.values)
            MenuItemButton(
              key: ValueKey("clipLaunch-${m.name}"),
              leadingIcon: check(clip.launch == m),
              onPressed: () => _set(clip.copyWith(launch: m)),
              child: Tooltip(message: m.hint, child: Text(m.label)),
            ),
        ],
        child: Text("Launch: ${clip.launch.label}"),
      ),
      MenuItemButton(
        key: const ValueKey("clipLoop"),
        leadingIcon: check(clip.loop),
        onPressed: () => _set(clip.copyWith(loop: !clip.loop)),
        child: const Text("Loop"),
      ),
      SubmenuButton(
        menuChildren: [
          for (var b in clipBarChoices)
            MenuItemButton(
              key: ValueKey("clipBars-$b"),
              leadingIcon: check(clip.bars == b),
              onPressed: () => _set(clip.copyWith(bars: b.toDouble())),
              child: Text(b == 1 ? "1 bar" : "$b bars"),
            ),
        ],
        child: Text("Length: ${_barsText(clip.bars)}"),
      ),
      SubmenuButton(
        menuChildren: [
          for (var (i, col) in sectionColors.indexed)
            MenuItemButton(
              key: ValueKey("clipColor-$i"),
              leadingIcon: Icon(Icons.circle, size: 14, color: Color(col)),
              trailingIcon: check(clip.color == i),
              onPressed: () => _set(clip.copyWith(color: i)),
              child: const SizedBox(width: 8),
            ),
        ],
        child: const Text("Colour"),
      ),
      MenuItemButton(
        key: const ValueKey("clipRename"),
        onPressed: () => _rename(clip),
        child: const Text("Rename"),
      ),
      MenuItemButton(
        key: const ValueKey("clipDuplicate"),
        onPressed: () => _duplicate(clip),
        child: const Text("Duplicate below"),
      ),
      MenuItemButton(
        key: const ValueKey("clipDelete"),
        leadingIcon: Icon(Icons.delete_outline, size: 14, color: studio.arm),
        onPressed: () => c.setSessionClip(widget.channel, widget.row, null),
        child: const Text("Delete"),
      ),
    ];
  }

  List<Widget> _emptyMenu() {
    if (c.instrumentChannel(widget.channel)) {
      return [
        MenuItemButton(
          key: const ValueKey("clipRecordHere"),
          leadingIcon: Icon(Icons.fiber_manual_record,
              size: 14, color: widget.theme.studio.arm),
          onPressed: () => c.recordClip(widget.channel, widget.row),
          child: const Text("Record into this slot"),
        ),
        MenuItemButton(
          key: const ValueKey("clipNewMidi"),
          leadingIcon: const Icon(Icons.piano, size: 14),
          onPressed: () {
            c.newMidiClip(widget.channel, widget.row);
            c.openPianoRoll(widget.channel, row: widget.row);
          },
          child: const Text("New MIDI clip, to draw notes into"),
        ),
        MenuItemButton(
          key: const ValueKey("clipFromPart"),
          onPressed: () =>
              c.newMidiClip(widget.channel, widget.row, fromPart: true),
          child: const Text("Copy the channel's part"),
        ),
      ];
    }
    var sounds = c.soundsOf(widget.channel);
    if (sounds.isEmpty) {
      return [
        const MenuItemButton(
          onPressed: null,
          child: Text("No sounds on this channel's timeline yet"),
        ),
      ];
    }
    return [
      for (var (i, s) in sounds.indexed)
        MenuItemButton(
          key: ValueKey("clipSound-$i"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 14),
          onPressed: () => c.clipFromSound(widget.channel, widget.row, s),
          child: Text(s.name.isEmpty ? "Sound ${i + 1}" : s.name),
        ),
    ];
  }

  void _openMenu(Offset at) => _menu.open(position: at);

  /// _menuAt is where a right-click -- or a Mac's Control-click -- went
  /// down, for its menu to open when it comes up: opened on the press, a
  /// menu still open from another slot, closing on the same press, could
  /// take the new one with it.
  Offset? _menuAt;

  @override
  Widget build(BuildContext context) {
    var theme = widget.theme;
    var studio = theme.studio;
    var clip = c.session.at(widget.channel, widget.row);
    var state = c.clipState(widget.channel, widget.row);
    var armed =
        c.armed.contains(widget.channel) && c.instrumentChannel(widget.channel);
    Widget body;
    if (clip == null) {
      var recording = state == ClipState.recording ||
          (state == ClipState.recordQueued && _blinkOn);
      body = Container(
        decoration: BoxDecoration(
          color: studio.inset,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: studio.edge),
        ),
        child: Center(
          child: armed || recording
              ? Icon(Icons.fiber_manual_record,
                  size: 9, color: recording ? studio.arm : studio.muted)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      border: Border.all(color: studio.edge, width: 1)),
                ),
        ),
      );
    } else {
      var col = Color(sectionColors[clip.color % sectionColors.length]);
      var lit = state == ClipState.playing ||
          state == ClipState.stopping ||
          (state == ClipState.queued && _blinkOn);
      var progress = c.clipProgress(widget.channel);
      body = Container(
        decoration: BoxDecoration(
          color: lit ? col : col.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
        padding: const EdgeInsets.only(right: 4),
        child: Row(children: [
          // Its launch button, as Ableton's: pressed, it plays -- held, for
          // a gated clip. The rest of the slot is for picking it, opening
          // it and dragging it to another slot.
          Listener(
            key: ValueKey("clipLaunch-${widget.channel}-${widget.row}"),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_menuClick(e) || _renaming) return;
              c.pressClip(widget.channel, widget.row);
            },
            onPointerUp: (_) => c.releaseClip(widget.channel, widget.row),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 2, 0),
              child: Icon(Icons.play_arrow,
                  size: 12, color: lit ? const Color(0xFF0E0F12) : studio.text),
            ),
          ),
          Expanded(
            child: _renaming
                ? TextField(
                    key: const ValueKey("clipNameField"),
                    controller: _name,
                    focusNode: _focus,
                    style: const TextStyle(fontSize: 10),
                    decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none),
                    onSubmitted: (_) => _renamed(clip),
                    onTapOutside: (_) => _renamed(clip),
                  )
                : _named(
                    clip,
                    Text(clip.name.isEmpty ? "Clip" : clip.name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color:
                                lit ? const Color(0xFF0E0F12) : studio.text))),
          ),
          if (progress != null && state != ClipState.queued)
            SizedBox.square(
              dimension: 9,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                color: const Color(0xFF0E0F12),
                backgroundColor: const Color(0x330E0F12),
              ),
            ),
        ]),
      );
    }
    // A sound dragged from the assets -- or, on a MIDI channel, a MIDI
    // file -- is let go on a slot to be its clip; and a clip from another
    // slot, moved here -- or copied, with Option (Alt) held.
    var midiChannel = c.instrumentChannel(widget.channel);
    var picked = c.selectedSlot == (widget.channel, widget.row);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SlotDrag from => c.canMoveClip(from.clip, widget.channel) &&
            (from.channel, from.row) != (widget.channel, widget.row),
        var other => droppedKind(other) == AssetKind.audio &&
            (other is LibraryAsset && isMidiId(other.id)) == midiChannel,
      },
      onAcceptWithDetails: (d) async {
        if (d.data case _SlotDrag from) {
          c.moveClip(from.channel, from.row, widget.channel, widget.row,
              copy: HardwareKeyboard.instance.isAltPressed);
          return;
        }
        var asset = await droppedAsset(d.data);
        if (asset == null) return;
        if (isMidiId(asset.id)) {
          await c.midiClipFromFile(widget.channel, widget.row, asset.id,
              name: asset.name);
        } else {
          c.clipFromSound(widget.channel, widget.row, asset.source);
        }
      },
      builder: (context, over, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: over.isNotEmpty
              ? Border.all(color: widget.theme.studio.on, width: 2)
              : picked && clip != null
                  ? Border.all(color: widget.theme.studio.text, width: 1)
                  : null,
        ),
        child: _slotBody(clip, body),
      ),
    );
  }

  Widget _slotBody(SessionClip? clip, Widget body) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: clip == null ? _emptyMenu() : _clipMenu(clip),
      child: Listener(
        onPointerDown: (e) {
          if (_menuClick(e)) {
            _menuAt = e.localPosition;
            return;
          }
          // An empty slot pressed stops its channel -- or, armed, records
          // into it. A clip is launched from its own button: see
          // clipLaunch.
          if (_renaming || clip != null) return;
          c.pressClip(widget.channel, widget.row);
        },
        onPointerUp: (e) {
          if (_menuAt case var at?) {
            _menuAt = null;
            _openMenu(at);
            return;
          }
          if (clip == null) c.releaseClip(widget.channel, widget.row);
        },
        onPointerCancel: (_) => _menuAt = null,
        child: GestureDetector(
          // Double-clicked: an empty slot's menu.
          onDoubleTapDown:
              clip == null ? (d) => _openMenu(d.localPosition) : null,
          onDoubleTap: clip == null ? () {} : null,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        ),
      ),
    );
  }

  /// _named is a clip's name in its slot: clicked, the clip picked -- and
  /// shown in the clip editor, where that is open; double-clicked, the
  /// editor opened on it; dragged, the clip moved to another slot.
  Widget _named(SessionClip clip, Widget name) {
    var from = _SlotDrag(widget.channel, widget.row, clip);
    return Draggable<Object>(
      key: ValueKey("clipDrag-${widget.channel}-${widget.row}"),
      data: from,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Color(sectionColors[clip.color % sectionColors.length]),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(clip.name.isEmpty ? "Clip" : clip.name,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0E0F12))),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: name),
      child: GestureDetector(
        key: ValueKey("clipName-${widget.channel}-${widget.row}"),
        behavior: HitTestBehavior.opaque,
        onTap: () => c.selectSlot(widget.channel, widget.row),
        onDoubleTap: () => c.openClipEditor(widget.channel, widget.row),
        child: Align(alignment: Alignment.centerLeft, child: name),
      ),
    );
  }
}

/// _SlotDrag is a clip being dragged from its slot to another.
class _SlotDrag {
  final String channel;
  final int row;
  final SessionClip clip;
  const _SlotDrag(this.channel, this.row, this.clip);
}

/// _menuClick is whether [e] asks for a slot's menu: the right button, or
/// -- as on a Mac -- the left with Control held.
bool _menuClick(PointerDownEvent e) =>
    e.buttons & kSecondaryMouseButton != 0 ||
    (e.buttons == kPrimaryMouseButton &&
        HardwareKeyboard.instance.isControlPressed);

String _barsText(double bars) {
  var whole = bars == bars.roundToDouble();
  var n = whole ? "${bars.round()}" : bars.toStringAsFixed(2);
  return bars == 1 ? "1 bar" : "$n bars";
}

/// _SceneBand is the master's clips band: a launch button for each scene,
/// beside the channels' rows, and Stop All and a new scene under them.
class _SceneBand extends StatelessWidget {
  final CanvasController controller;
  final MixerLook theme;
  final ScrollController scroll;

  const _SceneBand({
    required this.controller,
    required this.theme,
    required this.scroll,
  });

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return _clipColumn(
      scroll,
      controller.session.rows,
      (row) => _SceneSlot(
          key: ValueKey("scene-$row"),
          controller: controller,
          row: row,
          theme: theme),
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Tooltip(
            message: "Stop every channel's clips, on the next bar",
            child: Material(
              color: studio.inset,
              borderRadius: BorderRadius.circular(3),
              child: InkWell(
                key: const ValueKey("clipStopAll"),
                borderRadius: BorderRadius.circular(3),
                onTap: controller.stopAllClips,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.stop, size: 11, color: studio.text),
                      Text(" Stop all",
                          style: TextStyle(fontSize: 9, color: studio.text)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        Tooltip(
          message: "Add a scene: a row of clips to launch together",
          child: Material(
            color: studio.inset,
            borderRadius: BorderRadius.circular(3),
            child: InkWell(
              key: const ValueKey("addClipScene"),
              borderRadius: BorderRadius.circular(3),
              onTap: controller.addClipScene,
              child: SizedBox(
                  width: 20,
                  child: Icon(Icons.add, size: 12, color: studio.text)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// _SceneSlot is a scene's launch button: the whole row from the next bar.
/// Right-clicked: rename it, add one under it, or take it away.
class _SceneSlot extends StatefulWidget {
  final CanvasController controller;
  final int row;
  final MixerLook theme;
  const _SceneSlot(
      {required this.controller,
      required this.row,
      required this.theme,
      super.key});

  @override
  State<_SceneSlot> createState() => _SceneSlotState();
}

class _SceneSlotState extends State<_SceneSlot> {
  /// _menuAt is where a right-click went down -- see _ClipSlotState.
  Offset? _menuAt;

  final MenuController _menu = MenuController();
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _renamed() {
    if (!_renaming) return;
    setState(() => _renaming = false);
    c.renameClipScene(widget.row, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    var studio = widget.theme.studio;
    var lit = c.sceneLaunched == widget.row;
    var name = c.session.sceneName(widget.row);
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey("sceneRename"),
          onPressed: () {
            _name.text = c.session.scenes[widget.row];
            setState(() => _renaming = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            });
          },
          child: const Text("Rename"),
        ),
        MenuItemButton(
          key: const ValueKey("sceneInsert"),
          onPressed: () => c.addClipScene(after: widget.row),
          child: const Text("Add a scene below"),
        ),
        MenuItemButton(
          key: const ValueKey("sceneDelete"),
          onPressed:
              c.session.rows > 1 ? () => c.removeClipScene(widget.row) : null,
          child: const Text("Delete, with its clips"),
        ),
      ],
      child: Tooltip(
        message: "Scene $name: launch every channel's clip in this row "
            "together, from the next bar. Right-click to rename it.",
        waitDuration: const Duration(milliseconds: 600),
        child: Listener(
          onPointerDown: (e) {
            if (_menuClick(e)) {
              _menuAt = e.localPosition;
              return;
            }
            if (!_renaming) c.launchScene(widget.row);
          },
          onPointerUp: (e) {
            if (_menuAt case var at?) {
              _menuAt = null;
              _menu.open(position: at);
            }
          },
          onPointerCancel: (_) => _menuAt = null,
          child: Container(
            decoration: BoxDecoration(
              color: lit ? studio.on : studio.raised,
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Icon(Icons.play_arrow,
                  size: 12, color: lit ? studio.onOn : studio.text),
              const SizedBox(width: 2),
              Expanded(
                child: _renaming
                    ? TextField(
                        key: const ValueKey("sceneNameField"),
                        controller: _name,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 10),
                        decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none),
                        onSubmitted: (_) => _renamed(),
                        onTapOutside: (_) => _renamed(),
                      )
                    : Text(name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: lit ? studio.onOn : studio.text)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The mixer band, minimised
// ---------------------------------------------------------------------------

/// _miniMixerBand is a column's mixer band minimised: its buttons in a row,
/// over its meter on its side -- which is its fader too, dragged sideways.
/// [bare], at the mixer's smallest, the meter alone.
Widget _miniMixerBand(
  MixerLook theme, {
  bool bare = false,
  required List<Widget?> buttons,
  required double db,
  required (double, double) level,
  required (double, double) peak,
  required _MixWrite<double> onDb,
  required VoidCallback onCommit,
}) =>
    bare
        ? _MiniFader(
            db: db,
            level: level,
            peak: peak,
            theme: theme,
            onChanged: onDb,
            onCommit: onCommit)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: _buttonH,
              // Each side shrunk to fit a narrow column, rather than running out
              // of it.
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
                  level: level,
                  peak: peak,
                  theme: theme,
                  onChanged: onDb,
                  onCommit: onCommit),
            ),
          ]);

/// _MiniFader is a meter on its side with the fader's place marked on it:
/// dragged sideways it sets the level, double-clicked it is nought.
class _MiniFader extends StatelessWidget {
  final double db;
  final (double, double) level;
  final (double, double) peak;
  final MixerLook theme;
  final _MixWrite<double> onChanged;
  final VoidCallback onCommit;

  const _MiniFader({
    required this.db,
    required this.level,
    required this.peak,
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
              painter:
                  _MeterPainter(level, peak, theme.studio, horizontal: true),
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
