part of 'canvas_mixer.dart';

// canvas_mixer_strips.dart is the mixer's columns: one for each channel, each
// return and the master, every one the same shape, in bands top to bottom as
// Ableton's session mixer has them:
//
//   the clips: a channel's clip slots, launched live; the master's scenes;
//   the devices: a column's effects as slots that open them;
//   the sends: its send dials;
//   the mixer: pan, on, solo and arm in a column beside the fader.
//
// Each band is one height across every column (see _Bands), so the faders
// start on the same line and are as tall. Each band is shown or hidden from
// the rail at the right (MixerSection).

/// _headH, _bandGap and the rest are the columns' measures, at the desk's
/// own size (see _CanvasMixerState.build).
const double _headH = 22;
const double _bandGap = 6;
const double _slotH = 20;
const double _slotGap = 4;
const double _clipH = 20;
const double _clipGap = 3;
const double _stopH = 16;

/// _clipRowsWanted is the most clip slots the clips band is made tall
/// enough for, room allowing (fewer while fewer are shown: see
/// CanvasController.slotsShown); more scroll.
const int _clipRowsWanted = 4;

/// _clipsLeast is the least a clips band is given, room allowing: one
/// slot, and the stop button under it.
const double _clipsLeast = _clipH + _clipGap + _slotGap + _stopH;

/// _mixerMinH is the least a mixer band is given (its left column and a
/// fader still worth dragging), and _mixerCapH the most before the room
/// left goes to the clips instead.
// Both grown by the sound half's label, pan and switch rows over the
// fader (the approved design), so the fader keeps its room.
const double _mixerMinH = 120 + _soundRowsH;
const double _mixerCapH = 230 + _soundRowsH;
const double _soundRowsH = 30;

/// _buttonW and _buttonH are those buttons'.
const double _buttonW = 18;
const double _buttonH = 12;

/// _wideW and _narrowW are a column's widths: wide, with names and a
/// numbered fader, or narrow, for more channels in view; each column either,
/// by itself or all together (CanvasController.narrowStrips).
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

/// _Bands is how tall the clips and devices bands of every column are (null
/// for one hidden), and whether the mixer band, which takes what is left, is
/// shown.
class _Bands {
  final double? clips;
  final double? devices;

  /// sends is the send dials' band, the height the most of them take; null
  /// when hidden or there are no returns to send to.
  final double? sends;

  /// mixer is whether the mixer band shows whole, taking what is left;
  /// miniMixer whether it shows minimised, [_miniMixerH] high.
  final bool mixer;
  final bool miniMixer;

  /// bare is the mixer at its smallest: no column has its head (its name
  /// and the arrow that narrows it).
  final bool bare;

  /// motion is the room every column's motion half takes over its sound
  /// half, and motionClip each slot row's motion part over its sound part:
  /// nought where no element has a strip (the approved design: one strip,
  /// one column of slots, per element; the sound halves on one line).
  final double motion;
  final double motionClip;
  const _Bands(this.clips, this.devices, this.mixer,
      {this.miniMixer = false,
      this.sends,
      this.bare = false,
      this.motion = 0,
      this.motionClip = 0});

  /// _Bands.fit shares [inner], a column's height inside its frame, among the
  /// bands as [states] says. A minimised band has its least (a clip slot and
  /// its stop, a device slot, the mixer as a row) and the whole ones share the
  /// rest: the mixer its least first, then each of the others what it wants,
  /// then the mixer more, to [_mixerCapH], then the clips the rest. Short of
  /// room, the clips and devices share it as they want it, and scroll.
  ///
  /// The devices want no more than [devicesCap] (three slots and the sends)
  /// while the clips and the mixer both show whole, so a long chain scrolls
  /// rather than squeezing them.
  factory _Bands.fit(double inner, Map<MixerSection, BandState> states,
      double devicesWanted, double devicesCap,
      {double sendsH = 0,
      bool bare = false,
      int clipRows = _clipRowsWanted,
      bool motion = false}) {
    var mh = motion ? motionHalfHeight + _motionGap : 0.0;
    var mc = motion ? _motionClipH + _motionClipGap : 0.0;
    var mixerLeast = _mixerMinH + mh;
    var mixerMost = _mixerCapH + mh;
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
      c = _clipsLeast + mc;
      fixed += c;
    }
    if (mini(MixerSection.devices)) {
      d = _slotH;
      fixed += d;
    }
    if (mini(MixerSection.mixer)) {
      fixed += bare ? _bareMixerH : _miniMixerH + (motion ? _motionLineH : 0);
    }
    // Too short for even the least of each with the motion's parts: the
    // motion's parts go first.
    if (motion && fixed > avail) {
      return _Bands.fit(inner, states, devicesWanted, devicesCap,
          sendsH: sendsH, bare: bare, clipRows: clipRows);
    }
    var free = math.max(0.0, avail - fixed);
    var want =
        clips && mixer ? math.min(devicesWanted, devicesCap) : devicesWanted;
    var clipsWanted =
        math.min(clipRows, _clipRowsWanted) * (_clipH + _clipGap + mc) -
            _clipGap +
            _slotGap +
            _stopH;
    if (!mixer) {
      if (clips && devices) {
        d = math.min(want, math.max(0.0, free - _clipsLeast - mc));
        c = free - d;
      } else if (clips) {
        c = free;
      } else if (devices) {
        d = free;
      }
      return _Bands(c, d, false,
          miniMixer: mini(MixerSection.mixer),
          sends: sends,
          bare: bare,
          motion: mh,
          motionClip: mc);
    }
    var wanted = (clips ? clipsWanted : 0) + (devices ? want : 0);
    var forMixer = free - wanted;
    double mixerH;
    if (forMixer < mixerLeast) {
      mixerH = math.min(mixerLeast, free);
    } else if (clips) {
      mixerH = math.min(forMixer, mixerMost);
    } else {
      mixerH = forMixer;
    }
    var rest = math.max(0.0, free - mixerH);
    if (devices && clips) {
      d = rest >= wanted ? want : rest * want / wanted;
      c = rest - d;
      // A slot and the stop under it, at the least, taken from the devices,
      // which scroll: shared by what each wanted, a long chain would leave the
      // clips a sliver.
      if (c < _clipsLeast + mc && rest > _clipsLeast + mc) {
        c = _clipsLeast + mc;
        d = rest - c;
      }
    } else if (devices) {
      d = math.min(rest, want);
    } else if (clips) {
      c = rest;
    }
    return _Bands(c, d, true,
        sends: sends, bare: bare, motion: mh, motionClip: mc);
  }
}

/// _miniMixerH is the mixer band minimised: a row of its buttons over a
/// meter on its side, which is the fader too.
const double _miniMixerH = 34;

/// _motionGap is under the motion half; _motionClipH a slot row's motion
/// part, _motionClipGap under it; _motionLineH the motion's line over a
/// minimised mixer.
const double _motionGap = 4;
const double _motionClipH = 14;
const double _motionClipGap = 2;
const double _motionLineH = 18;

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

  /// sends are its send dials, in the sends band; nothing in a column
  /// without, which keeps the band's room so the faders line up.
  final Widget Function()? sends;

  /// miniMixer is the mixer band minimised: see _miniMixerBand.
  final Widget Function() miniMixer;

  /// motion is the motion half over the sound half, where the column has
  /// one (an element's), and motionLine it over a minimised mixer; without
  /// one, a well saying [noMotion] keeps the sound halves on one line.
  final Widget Function()? motion;
  final Widget Function()? motionLine;
  final String noMotion;

  /// narrow is whether the column is narrow, and onNarrow (the arrow in its
  /// head, keyed [narrowKey]) makes it the other.
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
    this.motion,
    this.motionLine,
    this.noMotion = "No motion",
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var studio = theme.studio;
    var withMotion = bands.motion > 0;
    return Container(
      width: narrow ? _narrowW : width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: master ? colors.outline : colors.outlineVariant),
      ),
      // Picked, drawn over the frame rather than thickening it, which would move
      // the picked column's bands off the others' line. Always there, clear when
      // not picked: a decoration that comes and goes changes the tree under it,
      // and a reading being typed into would lose what was typed.
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
          // Short of room, the motion half goes first, then the sound half
          // is drawn smaller rather than overflowing.
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              var sound = box.maxHeight;
              var both = withMotion &&
                  box.maxHeight >= motionHalfHeight + _motionGap + _soundLeast;
              if (both) sound -= motionHalfHeight + _motionGap;
              Widget half = sound >= _soundLeast
                  ? mixer()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                          width: box.maxWidth,
                          height: _soundLeast,
                          child: mixer()));
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (both) ...[
                      SizedBox(
                          height: motionHalfHeight,
                          child: motion?.call() ?? _Well(noMotion, theme)),
                      const SizedBox(height: _motionGap),
                    ],
                    Expanded(child: half),
                  ]);
            }),
          ),
        ],
        if (bands.miniMixer) ...[
          const Spacer(),
          const SizedBox(height: _bandGap),
          if (withMotion && !bands.bare)
            SizedBox(
                height: _motionLineH,
                child: motionLine?.call() ?? const SizedBox()),
          SizedBox(
              height: bands.bare ? _bareMixerH : _miniMixerH,
              child: miniMixer()),
        ],
      ]),
    );
  }
}

/// _Well is a recessed well saying what a half of a strip has not: "No
/// motion", "No sound", or nothing (the returns and the master).
class _Well extends StatelessWidget {
  final String text;
  final MixerLook theme;
  const _Well(this.text, this.theme);

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: theme.studio.inset, borderRadius: BorderRadius.circular(4)),
        child: text.isEmpty
            ? null
            : Text(text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(fontSize: 9.5, color: theme.studio.muted)),
      );
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

/// _mixerBand is a strip's sound half, row for row as the motion half over
/// it (the approved design, 2026-11-08): SOUND and the level; the pan, a
/// slider centred as the cross-fader is; the switches -- on, solo, arm --
/// as chips; then the fader on its meter, with the room left.
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

/// _soundLeast is the least a sound half is drawn at: its rows, and a
/// fader still worth dragging.
const double _soundLeast = 14 + 3 + _panH + 4 + _chipH + 4 + 30;

/// _SoundLeft is what a strip has besides its fader: its pan, and the on,
/// solo and arm switches it has; laid out by _mixerBand.
class _SoundLeft extends StatelessWidget {
  final Widget pan;
  final Widget? on, solo, arm;
  const _SoundLeft({required this.pan, this.on, this.solo, this.arm});

  // Shown alone, as it once was: the pan over the switches.
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(height: _panH, child: pan),
        for (var b in [on, solo, arm])
          if (b != null) SizedBox(height: _chipH, child: b),
      ]);
}

/// _leftColumn is a strip's pan and switches, for _mixerBand.
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
        label: label,
        icon: icon,
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

/// _faderOf is a column's fader and its reading, for the mixer band.
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

class _ChannelStrip extends StatelessWidget {
  final String name;

  /// number is its place among the channels, from one: on its switch.
  final int number;

  /// channelKey is the channel's key: where its placement is looked up.
  final String channelKey;
  final ChannelMix mix;
  final bool editable;
  final bool soloed;

  /// midi is whether it is a MIDI channel (an instrument's), which can be
  /// armed, and [armed] whether it is.
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

  /// clips is its clips band, from the mixer: see _ClipBand.
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

  /// onRemoveDevice takes one of its devices out, by id: a right-click on
  /// its slot.
  final ValueChanged<String>? onRemoveDevice;

  /// motion and motionLine are its element's motion half and line, where
  /// it is an element's own sound: the element and its sound one strip.
  final Widget Function()? motion;
  final Widget Function()? motionLine;

  /// leadSlot is its element's first device slot: where the element's sound
  /// goes, the master or a return it shares.
  final Widget? leadSlot;

  const _ChannelStrip({
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
      // Its send dials, in a band of their own (see MixerSection.sends).
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

  /// onRemoveDevice: see _ChannelStrip.onRemoveDevice.
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
        // Not in a narrow column, which has room only for its letter and a
        // little of its name.
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

/// _SceneStrip is the bus of the scene shown (see CanvasScene.bus): every
/// sound in the scene -- its channels, its backdrop's, its transition's --
/// sums into it on its way to the master, while the master's own sounds go
/// straight there. Its devices, EQ and compressor in its chain's order, its
/// pan and its fader.
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

  const _SceneStrip({
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
      narrow: narrow,
      onNarrow: onNarrow,
      narrowKey: const ValueKey("narrow-scene"),
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
      clips: () => const SizedBox(),
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

  /// onRemoveDevice: see _ChannelStrip.onRemoveDevice.
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
          // The loudness the whole mix is aimed at, measured from its own
          // editor (see _LoudnessDevice). Reaching it in an export is a
          // publish setting.
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
    // Half lit (a band minimised) is a ring in the lit colour.
    var ink = lit
        ? theme.studio.onOn
        : half
            ? theme.studio.on
            : theme.colors.onSurfaceVariant;
    // Drawn half size, but pressed anywhere in a square twenty across.
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
        // Scrolled, in a mixer shrunk to its least: its buttons are taller than
        // one band.
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

/// _OnSessionPulse builds a slot again on each beat of the session's pulse
/// (see _sessionPulse) while [_pulses]: waiting to blink, or playing to go
/// round. The desk is not built again for it.
mixin _OnSessionPulse<T extends StatefulWidget> on State<T> {
  bool get _pulses;

  /// _slotNow is the slot's state now, and _slotWas what it was built
  /// with: changed on a beat -- a clip played out, the playhead moving on
  /// -- it is built again even once it no longer pulses.
  Object? get _slotNow;
  Object? _slotWas;

  void _beat() {
    if (!mounted) return;
    var now = _slotNow;
    if (_pulses || now != _slotWas) {
      _slotWas = now;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionPulse.addListener(_beat);
  }

  @override
  void dispose() {
    _sessionPulse.removeListener(_beat);
    super.dispose();
  }
}

/// _chainSlots is a strip's devices, EQ and compressor as slots, in the
/// order its chain runs them -- as the Chain shows them (Ken's systems
/// review, 2026-11-08: the strips listed the EQ and compressor last
/// whatever the order). [devicePrefix], [eqKey] and [compKey] are each
/// strip's own keys.
List<Widget> _chainSlots(
  MixerLook theme, {
  required List<String> chain,
  required List<MixDevice> devices,
  required Eq eq,
  required Dynamics comp,
  required String devicePrefix,
  required String eqKey,
  required String compKey,
  String compLabel = "Comp",
  required VoidCallback onEq,
  required VoidCallback onComp,
  required void Function(String key) onDevice,
  void Function(String key)? onRemove,
}) {
  var colors = theme.colors;
  return [
    for (var step in chain)
      if (step == chainEq)
        _slot(
            theme,
            "EQ",
            eq.on,
            CustomPaint(
                size: const Size(40, 14), painter: _MiniCurve(eq, colors)),
            onEq,
            key: ValueKey(eqKey))
      else if (step == chainComp)
        _slot(
            theme,
            compLabel,
            comp.on,
            Icon(Icons.circle,
                size: 7, color: comp.on ? theme.studio.on : colors.outline),
            onComp,
            key: ValueKey(compKey))
      else if (deviceIndexOf(devices, step) case var i when i >= 0)
        _slot(
            theme,
            devices[i].kind.label,
            devices[i].on,
            Icon(Icons.circle,
                size: 7,
                color: devices[i].on ? theme.studio.on : colors.outline),
            () => onDevice(deviceKey(step)),
            onRemove: onRemove == null ? null : () => onRemove(deviceKey(step)),
            key: ValueKey("$devicePrefix-$i")),
  ];
}

/// _blinkOn is whether something waiting for a bar is lit at this moment:
/// a quarter of a second on, a quarter off.
bool get _blinkOn => DateTime.now().millisecondsSinceEpoch ~/ 250 % 2 == 0;

/// _clipColumn lays a column of clip rows out: [row] for each scene, a
/// slot's height and gap apart, scrolled by [scroll], over [foot].
///
/// With [motion], each row is a motion part ([motionRow], or nothing) over
/// its sound part ([row]); [whole] is a row that is both (the cue launch).
Widget _clipColumn(ScrollController scroll, int rows,
        Widget Function(int row) row, Widget foot,
        {double motion = 0,
        Widget Function(int row)? motionRow,
        bool whole = false}) =>
    LayoutBuilder(builder: (context, box) {
      var slots = ListView.builder(
        controller: scroll,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemExtent: _clipH + _clipGap + motion,
        itemCount: rows,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: _clipGap),
          child: motion == 0 || whole
              ? row(i)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      SizedBox(
                          height: motion - _motionClipGap,
                          child: motionRow?.call(i) ?? const SizedBox()),
                      const SizedBox(height: _motionClipGap),
                      Expanded(child: row(i)),
                    ]),
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

  /// motion and motionRow are each row's motion part, over its sound slot:
  /// see _clipColumn.
  final double motion;
  final Widget Function(int row)? motionRow;

  const _ClipBand({
    required this.controller,
    required this.channel,
    required this.theme,
    required this.scroll,
    this.motion = 0,
    this.motionRow,
  });

  @override
  Widget build(BuildContext context) {
    var stopping = controller.clipPlaying(channel);
    return _clipColumn(
      scroll,
      controller.slotsShown,
      (row) => _ClipSlot(
          key: ValueKey("clip-$channel-$row"),
          controller: controller,
          channel: channel,
          row: row,
          theme: theme),
      motion: motion,
      motionRow: motionRow,
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

/// _ClipSlot is one slot: a clip (its colour, a play mark, its name) or an
/// empty slot, which stops the channel when pressed, or on an armed MIDI
/// channel records into it. A right-click offers what can be done with it;
/// a double-click on an empty one makes a clip there (see _make).
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

class _ClipSlotState extends State<_ClipSlot> with _OnSessionPulse {
  @override
  Object? get _slotNow =>
      widget.controller.clipState(widget.channel, widget.row);

  @override
  bool get _pulses =>
      switch (widget.controller.clipState(widget.channel, widget.row)) {
        ClipState.queued ||
        ClipState.playing ||
        ClipState.stopping ||
        ClipState.recordQueued ||
        ClipState.recording =>
          true,
        _ => false,
      };

  /// _keys has the keyboard once the slot is clicked: see SlotKeys.
  final FocusNode _keys = FocusNode(debugLabel: "clipSlot");

  final MenuController _menu = MenuController();
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  CanvasController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    _keys.dispose();
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

  /// _make puts a clip in this empty slot, double-clicked (Ken, 2026-11-08,
  /// as the motion slots do): on a MIDI channel an empty one to draw notes
  /// into, on an audio channel one of the channel's sound -- its first; the
  /// menu has the rest. Picked, it takes Delete; double-clicked again, it
  /// opens. With no sound to make one of, the menu says so.
  void _make(Offset at) {
    if (!c.makeSessionClip(widget.channel, widget.row)) {
      _openMenu(at);
      return;
    }
    // Its name, which has the keys, is built on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  /// _menuAt is where a right-click (or a Mac's Control-click) went down, for
  /// its menu to open when it comes up: opened on the press, a menu still open
  /// from another slot, closing on the same press, could take the new one with
  /// it.
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
          // Its launch button, as Ableton's: pressed, it plays (held, for a gated
          // clip). The rest of the slot is for picking it, opening it and dragging
          // it to another slot.
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
                // Return or a click away keeps the name; Escape leaves it
                // as it was.
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          setState(() => _renaming = false),
                    },
                    child: TextField(
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
                    ),
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
    // A sound dragged from the assets (or, on a MIDI channel, a MIDI file) is
    // let go on a slot to be its clip; a clip from another slot is moved here,
    // or copied with Option (Alt) held.
    var midiChannel = c.instrumentChannel(widget.channel);
    var picked = c.selectedSlot == (widget.channel, widget.row);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        SessionSlotDrag from => c.canMoveClip(from.clip, widget.channel) &&
            (from.channel, from.row) != (widget.channel, widget.row),
        var other => droppedKind(other) == AssetKind.audio &&
            (other is LibraryAsset && isMidiId(other.id)) == midiChannel,
      },
      onAcceptWithDetails: (d) async {
        if (d.data case SessionSlotDrag from) {
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
          // An empty slot pressed stops its channel or, armed, records into it. A
          // clip is launched from its own button (keyed clipLaunch).
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
          // Double-clicked: a clip in an empty slot.
          onDoubleTapDown: clip == null ? (d) => _make(d.localPosition) : null,
          onDoubleTap: clip == null ? () {} : null,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        ),
      ),
    );
  }

  /// _named is a clip's name in its slot: clicked, the clip picked (and shown
  /// in the clip editor, where that is open); double-clicked, the editor
  /// opened on it; dragged, the clip moved to another slot.
  Widget _named(SessionClip clip, Widget name) {
    var from = SessionSlotDrag(widget.channel, widget.row, clip);
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
      child: SlotKeys(
        focus: _keys,
        onDelete: () {
          c.beginInteraction();
          c.setSessionClip(widget.channel, widget.row, null);
          c.endInteraction();
        },
        child: GestureDetector(
          key: ValueKey("clipName-${widget.channel}-${widget.row}"),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            c.selectSlot(widget.channel, widget.row);
            _keys.requestFocus();
          },
          onDoubleTap: () => c.openClipEditor(widget.channel, widget.row),
          child: Align(alignment: Alignment.centerLeft, child: name),
        ),
      ),
    );
  }
}

/// _menuClick is whether [e] asks for a slot's menu: the right button, or
/// the left with Control held, as on a Mac.
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

  /// motion is the rows' motion part: a cue's launch is the whole row.
  final double motion;

  const _SceneBand({
    required this.controller,
    required this.theme,
    required this.scroll,
    this.motion = 0,
  });

  @override
  Widget build(BuildContext context) {
    var studio = theme.studio;
    return _clipColumn(
      scroll,
      controller.slotsShown,
      (row) => _SceneSlot(
          key: ValueKey("scene-$row"),
          controller: controller,
          row: row,
          theme: theme),
      motion: motion,
      whole: true,
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
          message: "Add a cue: a row of clips to launch together",
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
  /// _menuAt is where a right-click went down: see _ClipSlotState._menuAt.
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
          child: const Text("Add a cue below"),
        ),
        MenuItemButton(
          key: const ValueKey("sceneDelete"),
          onPressed:
              c.session.rows > 1 ? () => c.removeClipScene(widget.row) : null,
          child: const Text("Delete, with its clips"),
        ),
      ],
      child: Tooltip(
        message: "Cue $name: launch every channel's and element's clip in "
            "this row together, from the next bar. Right-click to rename it.",
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
